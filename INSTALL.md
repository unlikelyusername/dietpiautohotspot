# Install

This repo contains a script and service file. Everything else — packages, config files — must be set up on the target system. This document is the complete, reproducible setup for a fresh DietPi install.

## 1. Install packages

```bash
sudo apt install hostapd dnsmasq iw
```

Both `hostapd` and `dnsmasq` must be disabled (not auto-started) but unmasked (startable on demand):

```bash
sudo systemctl disable hostapd dnsmasq
sudo systemctl unmask hostapd dnsmasq
```

## 2. Create config files on the target system

These files are not in the repo — they contain credentials and are system-specific.

**`/etc/hostapd/hostapd.conf`**
```
interface=wlan0
driver=nl80211
ssid=DietPi-Fallback
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=ChangeMe123
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
```

Change `ssid` and `wpa_passphrase` before deploying.

Verify hostapd will find its config:
```bash
cat /etc/default/hostapd | grep DAEMON_CONF
# should show: DAEMON_CONF="/etc/hostapd/hostapd.conf"
```

**`/etc/dnsmasq.conf`**
```
interface=wlan0
bind-dynamic
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=192.168.99.10,192.168.99.100,255.255.255.0,24h
dhcp-option=3,192.168.99.1
dhcp-option=6,192.168.99.1
```

The `AP_IP` in the script (`192.168.99.1`) must be on the same subnet as `dhcp-range`. If you change one, change both.

**`/etc/wpa_supplicant/wpa_supplicant.conf`**

Managed by `dietpi-config`. Add known networks there. The script reads this file but never modifies it.

**Remove any DietPi-managed usb0 config if present:**
```bash
sudo rm -f /etc/network/interfaces.d/usb0
```

DietPi sometimes creates this. If present, it runs its own `dhclient` on `usb0` indefinitely, which conflicts with the script's USB tethering tier.

**USB cable for iPad tethering (Pi 5 specific):**
Smart USB-C cables (Apple braided, Thunderbolt, USB4) break Pi 5 gadget mode TX silently. Use a cheap USB-C cable (no e-marker chip) or a USB-C → USB-A → USB-C adapter chain. See `autohotspot.md` for details.

## 3. Install the script and service

```bash
sudo cp autohotspot /usr/bin/autohotspot
sudo chmod +x /usr/bin/autohotspot
sudo cp autohotspot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable autohotspot.service
```

## 4. Verify

Run the script manually before rebooting:
```bash
sudo /usr/bin/autohotspot
cat /var/log/autohotspot.log
```

Then reboot and check:
```bash
sudo journalctl -b 0 | grep autohotspot
cat /var/log/autohotspot.log
```

## Uninstall

```bash
sudo systemctl disable autohotspot.service
sudo rm /etc/systemd/system/autohotspot.service
sudo rm /usr/bin/autohotspot
```

The script never modifies system config files. Nothing else to undo.
