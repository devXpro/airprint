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

# Update Avahi service configuration with correct hostname
echo "Updating Avahi service configuration with hostname: ${HOST_NAME}"
sed -i "s/localhost/${HOST_NAME}/g" /etc/avahi/services/airprint.service
sed -i "s/%h/${HOST_NAME}/g" /etc/avahi/services/airprint.service

# Ensure hostname is set properly for Avahi by creating /etc/hostname with the proper hostname
echo "${HOST_NAME}" > /etc/hostname
hostname "${HOST_NAME}"

# Disable SSL/TLS in CUPS to force only http:// URLs (no https://)
echo "Disabling SSL in CUPS to prevent IPPS protocol usage"
sed -i 's/^EnableSSL.*/EnableSSL No/' /etc/cups/cupsd.conf
echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# Also add explicit rule to prevent IPPS advertising from Avahi
echo "Checking for any other Avahi service files that might advertise IPPS..."
rm -f /etc/avahi/services/*ipps*.service 2>/dev/null || true

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

# Start Avahi daemon but handle MacOS host network differently
echo "Starting Avahi daemon..."
# Clean any existing PID files that might cause problems
mkdir -p /run/dbus
rm -f /run/dbus/pid
mkdir -p /run/avahi-daemon
rm -f /run/avahi-daemon/pid

# Start dbus first (required for Avahi)
dbus-daemon --system &
DBUS_PID=$!
sleep 3  # Give dbus more time to start

# Start Avahi daemon
avahi-daemon --no-chroot &
AVAHI_PID=$!
sleep 3  # Give avahi more time to start

# Verify avahi is running
if ! pgrep avahi-daemon > /dev/null; then
    echo "ERROR: avahi-daemon failed to start"
else
    echo "avahi-daemon is running"
fi

# Now start CUPS after Avahi is fully established
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
wait $CUPS_PID $AVAHI_PID $DBUS_PID

