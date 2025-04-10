# Epson L3250 AirPrint Server

A Docker container that makes your Epson L3250 (or similar) printer available as an AirPrint device for iOS/macOS.

## Prerequisites

- Docker and Docker Compose installed
- Raspberry Pi or other Linux server where you'll run this container
- Epson L3250 printer connected to your network
- Avahi daemon running on the host system

## Configuration

1. Edit the `.env` file to configure your printer:

```
PRINTER_IP=192.168.1.100  # Your printer's IP address
PRINTER_NAME=Epson_L3250  # Printer name (no spaces)
PRINTER_LOCATION=Home     # Location description
PRINTER_INFO="Epson L3250 AirPrint"  # Printer info/description
HOST_NAME=pi.local        # Hostname (must be resolvable on your network (host of raspberry pi))
CUPS_USER=admin           # CUPS web interface username
CUPS_PASSWORD=admin       # CUPS web interface password
```

2. Ensure your host machine has Avahi daemon installed and running:

```bash
# For Debian/Ubuntu/Raspberry Pi OS
sudo apt update
sudo apt install avahi-daemon
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
```

## Usage

1. Build and start the container:

```bash
docker compose up -d
```

2. The container will automatically create an Avahi service file directly in your host's `/etc/avahi/services` directory.

3. Restart Avahi daemon to apply the new service:

```bash
sudo systemctl restart avahi-daemon
```

4. Your printer should now be available as an AirPrint device on your iOS/macOS devices.

## Accessing CUPS Web Interface

The CUPS web interface is available at:

```
http://<your-host-ip>:631
```

Use the CUPS_USER and CUPS_PASSWORD from your .env file to log in.

## Troubleshooting

- Make sure your printer is powered on and connected to the network
- Verify that the printer IP in .env is correct
- Check container logs: `docker compose logs`
- Check Avahi logs: `journalctl -u avahi-daemon`
- Ensure that port 631 is not blocked by a firewall

## Fixing SSH Connectivity Issues

If you're experiencing frequent SSH disconnections with your Raspberry Pi, try the following:

1. Edit SSH configuration:

```bash
sudo nano /etc/ssh/sshd_config
```

2. Add or modify these settings:

```
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
```

3. Restart SSH service:

```bash
sudo systemctl restart ssh
```

These settings will ensure SSH keeps the connection alive by sending small packets periodically, even when idle. 