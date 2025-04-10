FROM debian:bullseye-slim

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Add armhf architecture support
RUN dpkg --add-architecture armhf && \
    apt-get update && \
    apt-get install -y \
    libc6:armhf \
    libcups2:armhf \
    libstdc++6:armhf

# Install required packages
RUN apt-get update && apt-get install -y \
    cups \
    cups-client \
    cups-filters \
    avahi-daemon \
    avahi-discover \
    libnss-mdns \
    dbus \
    curl \
    wget \
    usbutils \
    iputils-ping \
    libcups2 \
    net-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a directory for Epson driver
WORKDIR /tmp

# Download the driver .deb file directly from Epson's website
RUN wget -O epson-inkjet-printer-escpr_1.8.6_armhf.deb https://download3.ebz.epson.net/dsc/f/03/00/16/21/80/56451c0bb589feef994ae349a39fe7ed80790197/epson-inkjet-printer-escpr_1.8.6_armhf.deb

# Install the driver (allowing architecture mismatch)
RUN dpkg -i --force-architecture epson-inkjet-printer-escpr_1.8.6_armhf.deb || apt-get -f install -y

# Configure CUPS
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
    echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
    echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf

# Add lpadmin group to manage printers
RUN usermod -a -G lpadmin root

# Configure Avahi
COPY avahi-airprint.conf /etc/avahi/services/airprint.service

# Create entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Clean up
RUN rm -f /tmp/epson-inkjet-printer-escpr_1.8.6_armhf.deb

EXPOSE 631/tcp
EXPOSE 5353/udp

ENTRYPOINT ["/entrypoint.sh"]

