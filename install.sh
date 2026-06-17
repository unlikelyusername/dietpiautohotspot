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
echo "[1/7] Installing packages..."
apt-get install -y hostapd dnsmasq >/dev/null

# --- disable auto-start of AP services ----------------------
echo "[2/7] Configuring hostapd + dnsmasq..."
systemctl unmask  hostapd dnsmasq 2>/dev/null || true
systemctl disable hostapd dnsmasq 2>/dev/null || true

# --- write config files (don't overwrite if already present) -
echo "[3/7] Writing config files..."

if [ ! -f /etc/hostapd/hostapd.conf ]; then
    mkdir -p /etc/hostapd
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

if grep -q 'dhcp-range=192.168.99' /etc/dnsmasq.conf 2>/dev/null; then
    echo "  /etc/dnsmasq.conf already has AP stanza — skipped"
else
    cat >> /etc/dnsmasq.conf <<EOF

# --- autohotspot AP fallback ---
interface=wlan0
bind-dynamic
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=192.168.99.10,192.168.99.100,255.255.255.0,24h
dhcp-option=3,192.168.99.1
dhcp-option=6,192.168.99.1
EOF
    echo "  Appended AP stanza to /etc/dnsmasq.conf"
fi

# --- Pi 5 USB gadget (g_ether) setup -------------------------
echo "[4/7] Configuring Pi 5 USB gadget (g_ether)..."

CONFIG_TXT="/boot/firmware/config.txt"
CMDLINE_TXT="/boot/firmware/cmdline.txt"

if [ ! -f "$CONFIG_TXT" ]; then
    echo "  WARNING: ${CONFIG_TXT} not found — skipping USB gadget setup"
    echo "  (Not a Pi 5 with firmware partition? Add manually if needed.)"
else
    if grep -q 'otg_mode=1' "$CONFIG_TXT"; then
        echo "  config.txt: otg_mode=1 already present — skipped"
    else
        cat >> "$CONFIG_TXT" <<'EOF'

[pi5]
otg_mode=1

[all]
dtoverlay=dwc2
EOF
        echo "  config.txt: added [pi5] otg_mode=1 + [all] dtoverlay=dwc2"
    fi

    if grep -q 'modules-load=dwc2' "$CMDLINE_TXT" 2>/dev/null; then
        echo "  cmdline.txt: modules-load=dwc2,g_ether already present — skipped"
    else
        # cmdline.txt is one line — append the module load param
        sed -i 's/$/ modules-load=dwc2,g_ether/' "$CMDLINE_TXT"
        echo "  cmdline.txt: added modules-load=dwc2,g_ether"
    fi
fi

# --- install script + service --------------------------------
echo "[5/7] Installing autohotspot script..."
cp autohotspot /usr/bin/autohotspot
chmod +x /usr/bin/autohotspot

echo "[6/7] Installing systemd service..."
cp autohotspot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable autohotspot.service

# --- test run ------------------------------------------------
echo "[7/7] Running script once to verify..."
/usr/bin/autohotspot
echo

# --- summary -------------------------------------------------
echo "=== Done ==="
echo
echo "AP SSID      : ${SSID}"
echo "AP passphrase: ${PASS}"
echo
if grep -q 'otg_mode=1' "${CONFIG_TXT:-/dev/null}" 2>/dev/null; then
    echo "NOTE: Pi 5 USB gadget config written — reboot required for usb0 to appear."
    echo
fi
echo "Log:"
awk '/=== autohotspot/{buf=""} {buf=buf"\n"$0} END{print buf}' /var/log/autohotspot.log
