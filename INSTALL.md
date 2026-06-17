# Install

```bash
git clone https://github.com/unlikelyusername/dietpiautohotspot
cd dietpiautohotspot
sudo ./install.sh
```

Answer the two prompts (SSID + passphrase). The script installs everything and runs once to verify.

**Pi 5 note**: if this is the first install, the USB gadget (`usb0`) config is written to `/boot/firmware/` — a reboot is required before `usb0` appears. The AP fallback (wlan0) works immediately.

---

## What install.sh does

1. `apt install hostapd dnsmasq`
2. `systemctl disable/unmask` both (they start on demand, not at boot)
3. Creates `/etc/hostapd/hostapd.conf` with the SSID + passphrase you provided (skipped if already exists)
4. Appends AP DHCP stanza to `/etc/dnsmasq.conf` (skipped if already present)
5. Adds USB gadget config to `/boot/firmware/config.txt` and `cmdline.txt` (Pi 5 only; skipped if already present)
6. Copies `autohotspot` to `/usr/bin/` and enables `autohotspot.service`
7. Runs the script once and prints the log

---

## Manual reference

If you prefer to do it by hand:

### Packages

```bash
sudo apt install hostapd dnsmasq
sudo systemctl disable hostapd dnsmasq
sudo systemctl unmask hostapd dnsmasq
```

### `/etc/hostapd/hostapd.conf`

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

### `/etc/dnsmasq.conf` — append:

```
# --- autohotspot AP fallback ---
interface=wlan0
bind-dynamic
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=192.168.99.10,192.168.99.100,255.255.255.0,24h
dhcp-option=3,192.168.99.1
dhcp-option=6,192.168.99.1
```

The `AP_IP` in the script (`192.168.99.1`) must be on the same subnet as `dhcp-range`.

### Pi 5 USB gadget (`/boot/firmware/config.txt`)

```
[pi5]
otg_mode=1

[all]
dtoverlay=dwc2
```

### Pi 5 USB gadget (`/boot/firmware/cmdline.txt`)

Append to the existing single line (no newline):

```
modules-load=dwc2,g_ether
```

### Script + service

```bash
sudo cp autohotspot /usr/bin/autohotspot
sudo chmod +x /usr/bin/autohotspot
sudo cp autohotspot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable autohotspot.service
```

### Verify

```bash
sudo /usr/bin/autohotspot
cat /var/log/autohotspot.log
```

To force a full usb0 re-cycle (DHCP → link-local):

```bash
sudo /usr/bin/autohotspot --teardown
```

---

## Uninstall

```bash
sudo systemctl disable autohotspot.service
sudo rm /etc/systemd/system/autohotspot.service
sudo rm /usr/bin/autohotspot
```

The script never modifies system config files. Packages and config files installed by `install.sh` must be removed manually if desired.
