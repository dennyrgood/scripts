# 4G back door into the home LAN

Status: **planned, not started** (written 2026-10-16). Companion to
[SHELLY_PLUG.md](SHELLY_PLUG.md).

## Why

The Shelly + WBU watchdog fixes a *hung* Ziggo modem automatically, but not a Ziggo
outage, a dead modem, or anything needing a decision. During the 2026-10-16 outage the
only way in was one long-lived mb2 <-> WBU Tailscale connection that happened to survive.
A 4G link that doesn't depend on the Ziggo modem gives a guaranteed way in.

What it buys:

1. Reachability when Ziggo is down - WBU, NAS, UPS, Shelly, modem admin page and logs.
2. Prompt alerting ("home internet down since 14:02") instead of noticing from a digest
   full of MISSING days later.
3. Remote triage: Ziggo outage (call them) vs dead modem (send someone) vs hang (watchdog).
4. (Optional, later) keep a few key services - nightly summaries, digest, health
   monitors - online over 4G. Not whole-house failover.

What it does NOT fix: whole-house power cut (WBU and the switch aren't on the UPS),
mmm's power button, or the 4G router itself failing.

## Design - option A (chosen direction)

One 4G router on the home LAN, acting as a Tailscale subnet router for the whole LAN:

```
                       +-- GL-X2000 (WAN = 4G SIM, Tailscale, advertises 192.168.178.0/24) -- mobile -- you
home switch -----------+
  |                    +-- Ziggo modem (WAN = cable) -- internet
  +-- WBU, NAS, mmm, cwh, ib, Archer WiFi, Shelly ...
```

- No changes on any other machine; every LAN device (incl. non-Tailscale ones: modem UI,
  Shelly, glkvm, printers) becomes reachable through it.
- Power: on the UPS, **not** on a Shelly.
- Its WiFi doubles as the control network for both Shelly plugs (modem + Archer AX50), so
  the Archer is out of the control path - see [SHELLY_PLUG.md](SHELLY_PLUG.md).

Fallback - option B: leave the GL on its own subnet (192.168.8.x) and cable its LAN to a
second NIC on WBU and/or the NAS (DXP6800 Pro has two ports). True second exit for those
boxes, but each needs route metrics so 4G is backup-only. Only if A misbehaves, or if (4)
above becomes a goal.

## Hardware

**GL.iNet GL-X2000 Spitz Plus - EU version** (Quectel **EG120K-EA** modem).

- Tailscale supported (GL firmware 4.x; still marked *beta*). "Advertise LAN Subnets"
  option (renamed in v4.9); the route must be approved in the Tailscale admin console.
- EU module LTE bands: FDD B1/3/5/7/8/20/28/32, TDD B38/40/41 - covers Dutch networks
  (KPN B3/7/20; Odido B1/3/7/8/20 per Kimovil, undated). B20 (800 MHz) matters most indoors.
- Dual SIM, gigabit Ethernet WAN - could later be a whole-house failover router.

**Purchase link (chosen):** <https://www.gl-inet.com/en-de/products/gl-x2000?country=NL>
- Region option: **"DE warehouse - Quectel EG120K-EA / EU+UK+AU Plug"**
- **EUR 184.03** incl. Dutch VAT (2026-10-16), 2-year warranty, 30-day money back.

**There really are two versions, and the modem can't be swapped.** GL.iNet staff on their
forum: the X2000's EG120K is soldered (LGA, not an M.2 card) and comes in a North America
version and an EMEA/APAC/Brazil version; there is no global variant. A wrong unit can't be
fixed by swapping the module.

**Do not buy the US/NA version** (EG120K-NA). Its band list wasn't found, but the
predecessor EG12-NA has no B3/B8/B20, so it would likely work poorly or not at all in NL
(inference). Other prices seen: US store USD 165.99-175.99, UK store GBP 157.99.

**Amazon.nl listing not used:** ASIN `B0DMNGNNSL`, EUR 180.99. Its product details name no
modem/region, and the title says "T-Mobile & AT&T IoT" (US carriers - though the same title
text also appears on a UK retailer's listing, so likely copied marketing). Not worth
gambling EUR 3 on a soldered modem.

Ruled out:

- **GL-X750 / X750V2 Spitz** - listed as *unsupported* for Tailscale in GL.iNet's docs
  (insufficient memory). US X750V2 also ships a North-America modem (EC25-AF).
- **GL-X3000 Spitz AX** - global RM520N-GL module (a US purchase might work; bands not
  confirmed), but USD 379.99 / EUR 389.99 for 5G that a back door doesn't need.
- **USB 4G stick on WBU** (e.g. Huawei E3372) - cheapest, but WBU-only access (option B shape).

## SIM / data plan

Need ~**1 GB/month** (Tailscale keepalives + occasional SSH).

**Suggested: Lyca Mobile 1 GB, monthly cancellable, ~EUR 6/mo (KPN network)** - or Odido's
data SIM if Odido has better reception at home. Monthly cancellable is worth the ~EUR 2/mo
premium: if reception turns out poor, switch without a 2-year lock-in.

| Provider | Network | Found (2026-10-16) | Where |
|---|---|---|---|
| **Lyca Mobile** | KPN | 1 GB monthly cancellable **EUR 6/mo** (Keuze price check, Jul 2026); 2-year EUR 4/mo (promo EUR 2/mo first 12 mo); also 1-year option | lycamobile.nl/sim-only |
| **Odido Data Sim Only** | Odido | "from EUR 5/mo", data-only, you choose the term; same page shows EUR 7.50 for its 2 GB example (inconsistent); 15-day cooling-off | odido.nl/mobiel-abonnement/data-sim-only |
| **Lebara** | KPN | ~EUR 4/mo for 1 GB, mostly 1-2-year contracts | lebara.nl |
| Lebara prepaid data | KPN | ~EUR 5/mo | prepaid expiry, see below |
| *(comparison)* | | 11 of 14 Dutch SIM-only providers offer monthly-cancellable plans | keuze.nl/sim-only/maandelijks-opzegbaar |

**Avoid the Vodafone network.** Ziggo and Vodafone are the same company (VodafoneZiggo), so
a Vodafone-network back door shares an owner and possibly infrastructure with the link it
backs up (reasoning, not verified). Use KPN (Lyca, Lebara) or Odido - whichever covers home
better: check postcode on **KPN's dekkingskaart** and **Odido's dekkingskaart**, and ideally
test with a phone on that network where the router will sit.

Prefer a **subscription over prepaid**: prepaid SIMs die if unused/not topped up (sources
conflict: Lebara 90 days, Simyo 6 months, KPN numbers 9 months). A silently expired backup
SIM defeats the purpose.

Checklist before ordering:

1. **Physical SIM, not eSIM.** GL-X2000 SIM size not confirmed - get a **triple-cut**
   card (standard/micro/nano); most Dutch providers ship these.
2. Data-only or data+minutes both fine; ~1 GB/mo. SMS could be handy for alerts later.
3. **No surprise charges** - confirm data stops at the bundle limit (usual in NL), no auto top-up.
4. **Router use allowed** - check the terms don't restrict the device.
5. **No public IP needed** - Tailscale works behind carrier NAT.
6. For setup, have the provider's **APN** and the **SIM PIN** (enter it in the GL, or
   disable it in a phone first).
7. Subscription sign-up needs a Dutch address + IBAN.

Prices are from comparison sites/provider pages of mixed dates - re-check before ordering.

## Setup checklist (when it arrives)

1. Test 4G reception at the intended spot; insert SIM, confirm data.
2. Update GL firmware; enable Tailscale, log in to the tailnet.
3. **Put the GL's LAN side on the home network**: fixed `192.168.178.___` (record it),
   **DHCP server OFF**, and it must not advertise itself as the house gateway. Test this
   first - it's the tricky bit; fall back to option B if it fights back.
4. Enable "Advertise LAN Subnets" for `192.168.178.0/24`; approve in the Tailscale admin
   console. Decide whether to drop WBU's existing `192.168.178.123/32` route.
5. **Subnet clash check**: if mb2's (or any remote) location also uses 192.168.178.x
   (common Fritz!Box/Ziggo default), the home subnet route is ambiguous from there - check
   before relying on it.
6. Cable into the home switch (Cat6, 1-2 m - one is in the box); power from the UPS (not a
   Shelly). Check the UPS has a free outlet; add a short power strip if not.
7. Real test: unplug the Ziggo modem's WAN cable and confirm, from outside, that you can
   reach WBU, the NAS UI and the modem UI through the GL.

## Ongoing

- Weekly automated check that the GL path works on 4G alone (e.g. from WBU, or a
  Tailscale ping to the GL), alert if not. Untested backups fail when needed.
- Keeps the SIM active too, if it's ever prepaid.
- Optional later: WBU alert over the 4G path when Ziggo drops.

## Sources (checked 2026-10-16)

- GL.iNet Tailscale docs: <https://docs.gl-inet.com/router/en/4/interface_guide/tailscale>
  (unsupported-model list: <https://docs.gl-inet.com/router/de/4/interface_guide/tailscale/>)
- GL-X2000 purchase page (EU, EG120K-EA option): <https://www.gl-inet.com/en-de/products/gl-x2000?country=NL>
- GL-X2000 two-region / soldered-modem confirmation (GL.iNet staff):
  <https://forum.gl-inet.com/t/introducing-spitz-plus-gl-x2000-4g-lte-wi-fi-6-router/49595?page=2>
- GL-X2000 datasheet: <https://static.gl-inet.com/www/images/products/datasheet/x2000_datasheet_20260305.pdf>
- GL-X2000 store pages: <https://store-eu.gl-inet.com/products/x2000>,
  <https://store.gl-inet.com/collections/ces/products/x2000>,
  <https://store-uk.gl-inet.com/collections/cellular-router/products/x2000>
- GL-X750V2: <https://store-eu.gl-inet.com/collections/all/products/spitz-gl-x750v2-smart-wifi-dual-band-router-4g-lte>,
  <https://store.gl-inet.com/products/spitz-gl-x750v2-smart-wifi-dual-band-router-4g-lte>
- GL-X3000: <https://store-eu.gl-inet.com/collections/ces/products/spitz-ax-gl-x3000-wi-fi-6-4g-lte-5g-nrdual-sim-openwrt-c19g>
- Quectel EG120K: <https://www.quectel.com/product/lte-a-eg120k-series/>;
  EG12 band reference: <https://www.quectel.com.cn/wp-content/uploads/2021/03/Quectel_EG12_Series_LTE-A_Specification_V1.1.pdf>
- NL bands: <https://www.kimovil.com/de/frequency-checker/NL>
- SIM prices: <https://www.providers.nl/mobiel/sim-only/goedkoopste/>,
  <https://www.internetvergelijk.nl/info/data-only/>,
  <https://www.keuze.nl/sim-only/maandelijks-opzegbaar>
- Lyca: <https://www.lycamobile.nl/sim-only/en/>, <https://selectra.nl/telecom/telecomaanbieder/lyca-mobile>
- Odido: <https://www.odido.nl/mobiel-abonnement/data-sim-only>,
  <https://selectra.nl/telecom/telecomaanbieder/odido/sim-only>
- Prepaid expiry: <https://webwoordenboek.nl/kenniscentrum/hoe-lang-blijft-een-simkaart-actief>
