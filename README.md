# autohotspot

Boot-once networking for a headless DietPi (Pi 5). On every boot, brings up all non-conflicting interfaces:

1. **WiFi client** — join a known network (OS handles this; script checks the result)
2. **USB uplink** — always attempted: DHCP from a connected Mac, or link-local to a connected iPad
3. **AP fallback** — own hotspot on wlan0, only if wifi client failed (they conflict)

**Log:** `/var/log/autohotspot.log`

---

## Files

- `autohotspot` — the script (v1.8)
- `autohotspot.service` — systemd unit
- `install.sh` — one-command installer
- `INSTALL.md` — setup guide

**Runtime dependencies (installed by install.sh):**
- `hostapd`, `dnsmasq`
- `/etc/hostapd/hostapd.conf`
- `/etc/dnsmasq.conf`
- `/etc/wpa_supplicant/wpa_supplicant.conf` (managed by dietpi-config)

---

## How it works

### Step 1 — WiFi client

DietPi's own networking runs wpa_supplicant and dhclient on wlan0 before the service starts. The script just checks `has_ip wlan0`. No retry, no teardown.

### Step 2 — USB (always attempted, two sub-steps)

The Pi presents as a USB Ethernet gadget (`g_ether`) on its USB-C port. This runs regardless of whether wifi succeeded.

There is no early carrier check — usb0 timing at boot is unreliable (the kernel creates the interface before it's properly enumerated). DHCP failure is the signal to move to link-local.

**2a — DHCP uplink (Mac)**
Mac has Internet Sharing on. Script runs `dhclient` with a 10-second timeout. If dhclient succeeds and usb0 has an IP, done.

**2b — Link-local (iPad / Mac without Internet Sharing)**
If DHCP fails, script reloads the USB gadget driver (`rmmod g_ether; modprobe g_ether`). This forces a fresh USB enumeration, after which the peer self-assigns a `169.254.x.x` address (RFC 5227). If carrier is then present, the script assigns its own static `169.254.1.1/16` and is done. It does **not** try to discover or ping the peer — on a point-to-point USB link the peer connects to the Pi at the known `169.254.1.1`, so there's nothing to discover. No carrier means nothing is connected, and usb0 is left unconfigured.

If nothing responds (battery pack, nothing connected), usb0 is left unconfigured and the script continues.

**Cable matters (Pi 5 specific):**
Smart USB-C cables (Apple braided, Thunderbolt, USB4, e-marked) negotiate Power Delivery on the CC pin and silently break Pi 5 gadget TX. Use a cheap USB-C cable (no e-marker) or a USB-C → USB-A → USB-C adapter chain. Confirmed working with a basic Anker C-C cable.

iPad Pro M4 only, if a dumb cable still fails: set `PSU_MAX_CURRENT=3000` in Pi EEPROM.

### Step 3 — AP fallback (only if wifi client failed)

If wlan0 didn't get a client IP, tears down wlan0, brings it up in AP mode at `192.168.99.1/24`, starts hostapd and dnsmasq. SSID: `DietPi-Fallback`. This is skipped if wifi client succeeded (they conflict on the same interface).

---

## Future extension: multi-interface routing

When both wlan0 and usb0 are up simultaneously, Linux may have two default routes. Desired behaviour (not yet implemented):

- If usb0 got DHCP (Mac, has internet): pick the "better" default route, or set metrics so wlan0 wins if both have internet.
- If usb0 is link-local (iPad, no internet): ensure the default route stays on wlan0; don't let the 169.254.x.x interface steal it.
- Policy routing (ip rule / ip route tables) would allow both paths to work independently for their respective peers.

---

## Pending tests

### USB manual test

With iPad or Mac connected, run the script manually. If usb0 is already configured
from a previous run it will skip setup immediately. To force a full re-cycle:

```bash
sudo /usr/bin/autohotspot --teardown
sudo awk '/=== autohotspot/{buf=""} {buf=buf"\n"$0} END{print buf}' /var/log/autohotspot.log
```

### AP manual test

Requires a second SSH path in (Mac USB tethering) before pulling wlan0 down.

```bash
sudo ifdown wlan0
sudo ip link set wlan0 up
sudo ip addr add 192.168.99.1/24 dev wlan0
sudo systemctl start hostapd
sudo systemctl start dnsmasq
```

Connect phone/Mac to `DietPi-Fallback`, confirm `192.168.99.x` IP, SSH to `192.168.99.1`.

Tear down:
```bash
sudo systemctl stop hostapd dnsmasq
sudo ip addr flush dev wlan0
sudo ifup wlan0
```

### Boot test — WiFi path

Reboot with a known WiFi network in range.

```bash
sudo journalctl -b 0 | grep -E "(autohotspot|Startup finished)"
sudo cat /var/log/autohotspot.log
# or tail just the last run:
sudo awk '/=== autohotspot/{buf=""} {buf=buf"\n"$0} END{print buf}' /var/log/autohotspot.log
```

Expected: `wifi: client up, addr=...`, boot-to-SSH under 35 seconds.

### Boot test — AP fallback

Reboot with no known WiFi in range. Expected: AP comes up, phone connects to `DietPi-Fallback`, SSH to `192.168.99.1` works.

---

## Appendix: dev system notes

**`wifi-restore.service`** — disabled 2026-06-14. Was failing every boot (read-only filesystem at that stage). Files still at `/usr/local/bin/emergency-wifi-restore` and `/root/wpa_supplicant.conf.golden`. Safe to delete.

**`update_config=1` in `wpa_supplicant.conf`** — allows wpa_supplicant to overwrite the config. Consider setting to `0` once stable.

## Appendix: changelog

### v1.8 (2026-06-17)

- **Stop trying to discover/verify the USB peer.** The link-local path no longer scans with `tcpdump`, polls `ip neigh`, or pings the peer. On a point-to-point USB link the peer connects to the Pi at the static `169.254.1.1`, so there is nothing to discover. Success is now simply: carrier present → assign `169.254.1.1/16`.
- Removed the flush-on-timeout that could strip a working `169.254.1.1/16` when the old 20s discovery window expired (broke iPad Air without tcpdump).
- `tcpdump` is no longer used or referenced anywhere. Removed `USB_LINKLOCAL_TIMEOUT`.
- The g_ether `rmmod`/`modprobe` reload is kept — the iPad won't self-assign an IPv4 link-local address without a fresh re-enumeration.

### v1.7 (2026-06-17)

- Fix double-logging: `log()` was using `tee -a` (writes to file + stdout) while the systemd service had `StandardOutput=append` — every line appeared twice. Now writes directly to `$LOG` only.
- Fix DHCP success check: removed default-route requirement. macOS USB gadget DHCP assigns an IP but doesn't send a default route option — the old code rejected a working connection. Now: dhclient exit=0 + has IP = success.

### v1.6 (2026-06-15)

- **Idempotency**: `try_usb0()` now exits immediately if usb0 already has any IP — no wasted DHCP timeout or g_ether reload on re-runs
- **`--teardown` flag**: `sudo autohotspot --teardown` flushes usb0 and forces a full DHCP → link-local setup cycle (for debugging / manual re-test)
- Previously a leftover `169.254.1.1/16` from a prior run would cause a false "DHCP assigned" log, flush the working IP, and restart the whole 35s cycle

### v1.5 (2026-06-15)

- Verbose logging throughout: every step logs its result, exit codes, and interface state
- `run_logged` helper captures stdout+stderr of subcommands into the log
- `log_usb_state` snapshots carrier/addr/link line at key points
- Link-local peer discovery via `tcpdump` (later removed entirely in v1.8 — see above)
- All `&&/||` chains in error paths replaced with explicit `if/then`
- Boot run header/footer with full interface + route summary

### v1.4 (2026-06-15)

- Removed early carrier check in `try_usb0()` — usb0 timing at boot is unreliable; DHCP failure is the correct signal to fall through to link-local
- `try_usb0()` now always runs regardless of wifi client result — both interfaces come up if both work
- AP fallback now only starts if wlan0 client failed (previously could skip usb0 entirely if wifi was up)

### v1.3 (2026-06-15)

- `try_client()` is now check-only — OS already tried wlan0, no point retrying
- Removed DietPi usb0 drop-in (`/etc/network/interfaces.d/usb0`) — was running `dhclient -i` (infinite), racing with the script
- `try_usb0()` now owns usb0 entirely: DHCP uplink (Mac) then link-local (iPad)
- Link-local uses `rmmod`/`modprobe` rather than a link bounce — a simple `ip link set down/up` does not trigger iPadOS re-enumeration
- `has_internet()` removed from decision logic — reachability (ping gateway/peer) is the criterion
- Service: added `TimeoutStartSec=60`, stdout/stderr now appended to log file

### v1.2

- Fixed priority order (was USB first, now WiFi first)
- Fixed `has_internet()` being interface-blind (claimed success via wlan0 when testing usb0)
- Fixed `try_client()` tearing down a working wlan0 connection unconditionally
