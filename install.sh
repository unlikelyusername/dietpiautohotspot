#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo ./install.sh"
    exit 1
fi

echo "=== autohotspot installer ==="
echo

# --- prompts -------------------------------------------------
read -rp "AP SSID       [DietPi-Fallback]: " SSID
SSID="${SSID:-DietPi-Fallback}"

while true; do
    read -rp "AP passphrase (8+ chars)        : " PASS
    [ "${#PASS}" -ge 8 ] && break
    echo "  Passphrase must be at least 8 characters."
done

echo

# --- packages ------------------------------------------------
echo "[1/6] Installing packages..."
apt-get install -y hostapd dnsmasq iw tcpdump >/dev/null

# --- disable auto-start of AP services ----------------------
echo "[2/6] Configuring hostapd + dnsmasq..."
systemctl disable hostapd dnsmasq 2>/dev/null || true
systemctl unmask  hostapd dnsmasq 2>/dev/null || true

# Ensure hostapd knows where its config is
if [ -f /etc/default/hostapd ]; then
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi

# --- write config files (don't overwrite if already present) -
echo "[3/6] Writing config files..."

if [ ! -f /etc/hostapd/hostapd.conf ]; then
    cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    echo "  Created /etc/hostapd/hostapd.conf"
else
    echo "  /etc/hostapd/hostapd.conf already exists — skipped"
fi

if [ ! -f /etc/dnsmasq.conf ] || ! grep -q 'dhcp-range=192.168.99' /etc/dnsmasq.conf; then
    cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
bind-dynamic
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=192.168.99.10,192.168.99.100,255.255.255.0,24h
dhcp-option=3,192.168.99.1
dhcp-option=6,192.168.99.1
EOF
    echo "  Created /etc/dnsmasq.conf"
else
    echo "  /etc/dnsmasq.conf already exists — skipped"
fi

# --- remove DietPi usb0 drop-in if present ------------------
if [ -f /etc/network/interfaces.d/usb0 ]; then
    rm /etc/network/interfaces.d/usb0
    echo "  Removed /etc/network/interfaces.d/usb0 (conflicts with script)"
fi

# --- install script + service --------------------------------
echo "[4/6] Installing autohotspot script..."
cp autohotspot /usr/bin/autohotspot
chmod +x /usr/bin/autohotspot

echo "[5/6] Installing systemd service..."
cp autohotspot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable autohotspot.service

# --- test run ------------------------------------------------
echo "[6/6] Running script once to verify..."
/usr/bin/autohotspot
echo

# --- summary -------------------------------------------------
echo "=== Done ==="
echo
echo "AP SSID      : ${SSID}"
echo "AP passphrase: ${PASS}"
echo
echo "Log:"
awk '/=== autohotspot/{buf=""} {buf=buf"\n"$0} END{print buf}' /var/log/autohotspot.log
