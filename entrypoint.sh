#!/bin/bash
set -e

# Default printer IP if not provided
PRINTER_IP=${PRINTER_IP:-192.168.1.100}
PRINTER_NAME=${PRINTER_NAME:-Epson_L3250}
PRINTER_LOCATION=${PRINTER_LOCATION:-Home}
PRINTER_INFO=${PRINTER_INFO:-"Epson L3250 AirPrint"}
HOST_NAME=${HOST_NAME:-localhost}
CUPS_USER=${CUPS_USER:-admin}
CUPS_PASSWORD=${CUPS_PASSWORD:-admin}

echo "Printer IP: ${PRINTER_IP}"
echo "Printer name: ${PRINTER_NAME}"
echo "Host name: ${HOST_NAME}"
echo "CUPS user: ${CUPS_USER}"

# Create CUPS admin user unconditionally
echo "Setting up CUPS admin user: ${CUPS_USER}"
useradd -r -G lpadmin -m $CUPS_USER 2>/dev/null || true
echo "${CUPS_USER}:${CUPS_PASSWORD}" | chpasswd
echo "CUPS admin user configured."

# Create the Avahi service file for AirPrint with proper replacements
echo "Creating Avahi service file for AirPrint..."
mkdir -p /avahi-services

cat > /avahi-services/airprint.service << EOL
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">AirPrint ${PRINTER_NAME} @ ${HOST_NAME}</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtver=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/${PRINTER_NAME}</txt-record>
    <txt-record>ty=${PRINTER_INFO}</txt-record>
    <txt-record>adminurl=http://${HOST_NAME}:631/printers/${PRINTER_NAME}</txt-record>
    <txt-record>note=${PRINTER_INFO}</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>product=(GPL Ghostscript)</txt-record>
    <txt-record>printer-state=3</txt-record>
    <txt-record>printer-type=0x809C</txt-record>
    <txt-record>Transparent=T</txt-record>
    <txt-record>Binary=T</txt-record>
    <txt-record>Fax=F</txt-record>
    <txt-record>Color=T</txt-record>
    <txt-record>Duplex=F</txt-record>
    <txt-record>Staple=F</txt-record>
    <txt-record>Copies=T</txt-record>
    <txt-record>Collate=F</txt-record>
    <txt-record>Punch=F</txt-record>
    <txt-record>Bind=F</txt-record>
    <txt-record>Sort=F</txt-record>
    <txt-record>Scan=F</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,image/urf</txt-record>
    <txt-record>URF=W8,SRGB24,CP1,RS600</txt-record>
  </service>
</service-group>
EOL

echo "Avahi service file created at /avahi-services/airprint.service"

# Disable SSL/TLS in CUPS to force only http:// URLs (no https://)
echo "Disabling SSL in CUPS to prevent IPPS protocol usage"
sed -i 's/^EnableSSL.*/EnableSSL No/' /etc/cups/cupsd.conf
echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# Disable cups-browsed service which may be auto-registering IPPS
echo "Disabling cups-browsed service (if installed)..."
if dpkg -l cups-browsed > /dev/null 2>&1; then
  echo "cups-browsed found, stopping and disabling it..."
  systemctl stop cups-browsed 2>/dev/null || true
  systemctl disable cups-browsed 2>/dev/null || true
  killall cups-browsed 2>/dev/null || true
fi

# Additional fixes for IPPS record issues
if [ -f /etc/cups/cups-browsed.conf ]; then
  echo "Configuring cups-browsed to disable IPPS..."
  # Backup original config
  cp /etc/cups/cups-browsed.conf /etc/cups/cups-browsed.conf.bak
  # Disable IPPS protocol
  sed -i 's/^IPPSEnable.*/IPPSEnable No/' /etc/cups/cups-browsed.conf
  # If the option doesn't exist, add it
  if ! grep -q "IPPSEnable" /etc/cups/cups-browsed.conf; then
    echo "IPPSEnable No" >> /etc/cups/cups-browsed.conf
  fi
fi

# Now start CUPS
echo "Starting CUPS daemon..."
mkdir -p /run/cups  # Ensure directory exists
rm -f /run/cups/cupsd.pid  # Remove stale PID file if exists
cupsd -f &
CUPS_PID=$!

echo "Waiting for CUPS to start..."
sleep 5  # Give CUPS more time to start fully

echo "Configuring printer..."

# Use the specific Epson L3250 PPD file that we know exists
PPD_PATH="/opt/epson-inkjet-printer-escpr/share/cups/model/epson-inkjet-printer-escpr/Epson-L3250_Series-epson-escpr-en.ppd"

if [ ! -f "$PPD_PATH" ]; then
  echo "ERROR: Specific Epson L3250 PPD file not found at $PPD_PATH!"
  echo "Searching for alternative PPD files..."
  PPD_PATH=$(find /opt -name "*.ppd" | grep -i epson | head -1 || find /usr/share -name "*.ppd" | grep -i epson | head -1)
  
  if [ -z "$PPD_PATH" ]; then
    echo "ERROR: No Epson PPD files found. Falling back to generic driver."
    PPD_PATH="/usr/share/cups/model/generic-cups-pdf.ppd"
  fi
fi

echo "Using PPD: $PPD_PATH"

# Delete any existing printers
echo "Removing any existing printers..."
rm -f /etc/cups/printers.conf
touch /etc/cups/printers.conf
chown root:lp /etc/cups/printers.conf
chmod 640 /etc/cups/printers.conf

# Restart CUPS after cleaning printers
echo "Restarting CUPS to apply clean printer config..."
kill $CUPS_PID
sleep 2
rm -f /run/cups/cupsd.pid  # Remove stale PID file if exists
cupsd -f &
CUPS_PID=$!
sleep 3

# Set up the printer using lpadmin command
echo "Adding printer with proper driver..."
lpadmin -p ${PRINTER_NAME} -E -v socket://${PRINTER_IP}:9100 -P "${PPD_PATH}" -L "${PRINTER_LOCATION}" -D "${PRINTER_INFO}"
lpadmin -p ${PRINTER_NAME} -o printer-is-shared=true
lpadmin -d ${PRINTER_NAME}  # Set as default printer

# List printers to verify
echo "Available printers:"
lpstat -v || echo "CUPS is not responding, but we will continue anyway"
lpstat -p -d || echo "Could not get printer details"

echo "CUPS interface available at http://${HOST_NAME}:631"
echo "CUPS admin login: ${CUPS_USER} / ${CUPS_PASSWORD}"

# Keep the container running
echo "Services started. Press Ctrl+C to stop..."
wait $CUPS_PID

