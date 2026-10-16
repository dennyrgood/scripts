# Shelly plug + watchdog for the home Ziggo modem

Status: **planned, not started** (written 2026-10-16, after the outage below).

## Why

On 2026-10-13..16 the home Ziggo SmartWifi modem/router (gateway `192.168.178.1`)
hung for ~3 days while the user was away (at sea). Symptoms, as tested from WBU on
the home LAN:

- LAN-to-LAN traffic fine (WBU -> NAS 0.38 ms; Tailscale direct pings to mmm/cwh/ib 1-2 ms).
- Router answered ARP (`REACHABLE`) but nothing else: no ping, and ports 80, 443,
  49000 (TR-064) and 53 all **timed out** (`nc -zv -w 3 192.168.178.1 80 443 49000 53`).
- No new outbound connections (DNS, HTTPS to 1.1.1.1 / github.com all failed;
  `tailscale netcheck`: `UDP: false`, no DERP).
- Already-established flows kept working - the one long-lived mb2 <-> WBU Tailscale
  connection survived, and was the only way in.

So the router's web UI reboot was impossible. It was fixed by power-cycling the whole
UPS from FleetNAS (`upscmd -u nut ups0 shutdown.return`). That worked - internet back
~6 min later - but the UPS also feeds the NAS, mathes-mac-mini and the WiFi controller,
and **mmm does not come back after a power loss** (needs its physical button despite
`pmset autorestart 1`), so it stayed down until someone gets home.

A cloud-controlled plug (e.g. Tapo via its app) would not have helped: its control
path goes through the same hung router. What's needed is a plug that is switched
**from inside the LAN**, ideally automatically.

## What to buy

**Two Shelly Gen3 plugs, EU (type F / Schuko)** - one for the Ziggo modem, one for the
Archer AX50 WiFi router. Either model works; both are Gen3 with the same local API,
scripts and auto-on:

| Model | Max load | Size | Amazon.nl 2026-10-16 |
|---|---|---|---|
| **Plug S MTR Gen3** (current name of "Plug S Gen3"; MTR = Matter) | 12 A / 2500 W | ~40x40x36 mm, doesn't block neighbouring sockets | set of 2 EUR 34.99 |
| **Plug M Gen3** | 13 A / 3000 W | ~50x50x46 mm, can partly block neighbours | 2 pcs EUR 19.90 |

Load is irrelevant (modem/AP ~10-25 W). Pick by **UPS outlet spacing**: tight -> S, roomy -> M.
Sizes/blocking from a techtest.org review; loads from Shelly's own comparison.

Why Shelly Gen3:

- Fully local control over WiFi - plain HTTP RPC from the LAN, no cloud required.
- Runs on-device scripts (API docs list up to 10 Script instances), so the plug
  can be its own watchdog.
- Has an **auto-on timer**: any OFF reverts to ON after N seconds, so a bad script
  or click can't leave the modem dark.

Refs: <https://shelly-api-docs.shelly.cloud/gen2/Devices/Gen3/ShellyPlugSG3>,
<https://www.shelly.com/blogs/documentation/whats-the-difference-between-the-plug-s-plug-m-and-plug-pm-gen3>,
<https://techtest.org/shelly-plug-s-gen3-vs-plug-m-gen3-unterschiede-vergleich-kaufberatung/>

## Wiring

```
UPS outlet -> Shelly #1 -> Ziggo modem
UPS outlet -> Shelly #2 -> Archer AX50 WiFi router
UPS outlet -> FleetNAS, mathes-mac-mini, GL-X2000   (directly, NOT on a Shelly)
```

- The switch and the GL-X2000 must **not** be on a Shelly - the control path runs through them.
- mmm should arguably move off the UPS-cycled outlets entirely, given it won't auto-restart.

## Control path

The Shellys don't connect *to* WBU; they join a WiFi network and WBU talks to them over the
LAN. **Join them to the GL-X2000's WiFi, not the Archer's** (see [BACKUP_4G.md](BACKUP_4G.md);
in option A the GL's WiFi is on the home 192.168.178.x network):

```
WBU --(LAN)--> switch --> GL-X2000 WiFi --> Shelly #1 --power--> Ziggo modem
                                       \--> Shelly #2 --power--> Archer AX50
 |
 +- every few min: "internet reachable?"  no for 15 min -> "Shelly #1, off"
                                          auto-on -> modem back on after 30 s
```

- Nothing on that path goes through the modem's own software, so it keeps working while the
  modem is hung - same as WBU <-> NAS kept working during the 2026-10-16 outage. For the
  "hung modem" failure this is fully automatic and needs no out-of-band link.
- Using the GL's WiFi takes the Archer out of the control path, so a hung Archer can still
  be power-cycled - and both plugs are reachable from outside over 4G via the GL.
- If the Archer were the control WiFi instead, Shelly #2 would be unreachable exactly when
  the Archer is hung (an "off" still works while it's healthy - auto-on brings it back
  without any network).
- Remaining single point: the GL itself. If it hangs, both plugs are unreachable, but
  auto-on means nothing can get stuck off, and the modem watchdog can also run on the plug.
- Bluetooth control from WBU was considered and rejected: possible in principle (Gen3 has
  BLE) but unproven from Linux, needs a dongle, ~10 m range.

Also: the Archer AX50 likely has a built-in **scheduled reboot** (TP-Link feature) - turn it
on weekly regardless (verify the AX50 has it). A hung Archer only drops WiFi devices
(FleetDev, ESPs, cameras, Tapos); wired boxes and remote access are unaffected.

## Plug settings (do these on install)

- Power-on default: **ON**
- Auto-on after OFF: **30 s**
- **Static IP set on the plug itself** (not only a DHCP reservation) - the Ziggo modem is the
  DHCP server, and a hung modem can't renew leases. Record them here:
  Shelly #1 (modem) `192.168.178.___`, Shelly #2 (Archer) `192.168.178.___`
- WiFi: join the **GL-X2000's** network, not the Archer's.
- Check WBU's address the same way (currently `192.168.178.242` via DHCP) - it should be
  static too, or at least have a long lease.
- Local-only is fine; cloud can stay off.

## What this does NOT cover

The watchdog only helps when a power-cycle fixes things. It won't help with: a Ziggo
outage, a dead modem, WBU itself down, or anything needing hands (e.g. mmm's power button).
After its rate limit it gives up, and remote access stays down until the cause clears. An
out-of-band 4G/5G path would cover those - see [BACKUP_4G.md](BACKUP_4G.md).

## Watchdog design (to write later)

Two layers, either works alone:

1. **WBU watchdog** (cron/systemd timer, WBU is not on the UPS and survives the cycle):
   - Every ~5 min check internet (e.g. HTTPS to two unrelated hosts + `192.168.178.1:80`).
   - If down continuously for **15 min**, turn the plug off; auto-on brings it back.
     Gen2+ RPC: `http://<plug-ip>/rpc/Switch.Set?id=0&on=false` (verify against the docs).
   - Rate-limit: **at most once per hour**, and back off (e.g. stop after 3 cycles
     in 6 h - a real ISP outage won't be fixed by rebooting).
   - Log every check-fail and every cycle; optionally email via the existing msmtp setup
     once internet is back.
2. **On-plug script** (mJS) doing the same check/cycle logic, as a backstop if WBU is down.
   Caveat: the plug's own WiFi failing would look like "internet down" - keep the same
   rate limits.

## Open questions

- Confirm exact SKU / that it's the Gen3 EU variant on purchase.
- Does the Ziggo modem tolerate abrupt power cuts every so often? (It did fine 2026-10-16.)
- Worth adding a separate 4G/5G path into WBU as an out-of-band way in? (see "What this does NOT cover")
- Pull the modem's event log (UI via tunnel: `~/nas-tunnel.sh` on mb, then
  `http://localhost:8080` -> `https://localhost:8443`) to see why it hung.

See also: memory note `home-router-ups-power-cycle`; `~/cycle-watch.log` on WBU
(timeline of the 2026-10-16 UPS cycle).
