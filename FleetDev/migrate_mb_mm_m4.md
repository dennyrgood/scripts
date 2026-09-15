# MacBook M2 (mb) → FleetDev (Mac Mini M4) Migration Guide

*Edited: 2026-09-15*

## Overview

This guide covers migrating from **mb** (Denniss-MacBook-Air, Apple M2, 8GB unified, current daily driver) to **FleetDev** (new Mac Mini M4, 512GB drive, brand new / never powered on).

**Approach:** Full clone via Apple Migration Assistant — NOT a fresh build. FleetDev keeps its name as the permanent hostname post-clone.

**Transition model:** Both machines run together for a while. mb stays the daily driver and keeps its current services running. FleetDev comes up alongside it, not as a day-one replacement. Decommissioning duplicate services on mb is explicitly a **future step**, out of scope for this pass.

---

## Part 1: Pre-Clone Cleanup on mb

Goal: don't copy junk onto a brand-new machine. All items below are confirmed for removal.

### Confirmed removals:

| Item | Size | Notes |
|---|---|---|
| `~/Parallels/Windows 11.pvm` | 59G | Windows 11 VM |
| `~/Library/Application Support/Blender` | 10G | Support files |
| `~/Library/Application Support/Insta360` / `QooCamStudio` (+cache) | ~2.5G combined | Camera app support files |
| `~/Library/Application Support/com.isaacmarovitz.Whisky` | 854M | Wine wrapper, not needed |
| Playwright (`ms-playwright`) cache | 2G | Pure cache, regenerates via `npx playwright install` |
| `~/Downloads/NAS release_...img` + `UGREEN NAS_...dmg` | ~1.9G | One-time firmware installer, done its job |
| `~/Downloads/data-e4157ef2-...batch-0000` + `.zip` | ~172M | Unclear provenance — confirm before deleting if unsure |
| `~/Downloads/Reality_Converter_beta_6.dmg` | 67M | App installer, already installed |
| `~/Library/Caches/*` (whole dir) | 6.4G | Pure cache, every app rebuilds it |
| `~/migration-backup/` | 64K | Leftover manifests from the M2→M3-era migration, historical only |
| `~/Desktop/$RECYCLE.BIN`, `Thumbs.db`, `desktop.ini` | small | Windows filesystem artifacts, dead weight |

### Needs a look before removing:

| Item | Size | Action |
|---|---|---|
| `~/fleet_monitor/` | 20K | Check whether anything still writes here — may be superseded by the heartbeat writer under `~/repos/scripts` |

**Total confirmed cleanup: ~82.5GB+** freed on mb before cloning.

### Storage gut-check

A full clone has no selective-transfer safety valve — if the math is wrong, it's wrong on the new machine too, not caught mid-transfer. Rough numbers as of 2026-09-15:

- mb home directory total (top-level `du`, current state): **~254GB**
- After the ~82.5GB confirmed cleanup above: **~171.5GB** expected to transfer
- FleetDev target drive: **512GB**

Comfortable margin either way — this isn't a tight fit like the old M2→M3 move was. Still worth re-running `du -sh ~/*/ | sort -rh` on mb immediately before starting Migration Assistant, since cleanup and normal usage between now and clone day will shift the number.

---

## Part 2: The Clone

### Target hardware
- **Mac Mini M4**, 512GB drive
- Brand new, never powered on
- Will be named **FleetDev**
- Apple Silicon (arm64) — same architecture family as mb's M2, so no Rosetta/x86↔arm64 translation concerns for any cloned binaries

### Process
1. Complete Part 1 cleanup on mb first.
2. Power on FleetDev for the first time.
3. On FleetDev's initial setup screen, select **Migration Assistant** → transfer from a Mac.
4. On mb, open **Migration Assistant** (Applications > Utilities) → "To another Mac."
5. Connect both machines (cable/Ethernet fastest if available; Wi-Fi works but is slower for a transfer at this scale).
6. Enter the security code shown on mb into FleetDev.
7. Transfer everything — this is a full clone, no selective unchecking.
8. Let it run — see time estimate below; plan for it to run unattended.

### What a full clone means for you
Because this is a complete filesystem copy (not a selective Migration Assistant transfer like the old M2→M3 move), the following come along **byte-for-byte, no reinstallation needed**:
- Keychain (gh auth, SSH keys — `id_ed25519_amsterdamdesktop`, `id_ed25519_ubuntu` — all survive)
- Homebrew installs, npm global packages, pip packages — as actual working binaries, not just files to reinstall from
- The exact Python 3.14.3 Homebrew cellar path the venv shebangs point to
- Dotfiles (`.zshrc`, `.gitconfig`, etc.)
- All 10 `com.dennis.*` launchd agent plists
- Repos, venvs, and app-layer config as-is
- Git identity (`user.name`/`user.email`) already correct, no reconfiguration needed

This is why there's no "Development Environment Setup" section reinstalling Homebrew/npm/pip packages the way the old M2→M3 doc had — that script existed because *that* migration used selective transfer and deliberately chose to reinstall dev tooling fresh rather than trust a partial copy. A full clone on matching architecture doesn't have that problem, and re-running such a script here would actively risk *reintroducing* version drift (e.g. pulling a newer Homebrew Python bottle than the 3.14.3 the venvs are pinned to) rather than preventing it.

### Time estimate

| Task | Estimate |
|---|---|
| Migration Assistant transfer (~170GB, full clone) | Ethernet: roughly 1–3 hours. Wi-Fi: could run considerably longer — prefer a wired connection if available. |
| First-boot re-authentication pass (Part 3) | 20–40 min |
| Post-clone divergence steps (Part 4) | 30–60 min |
| Verification pass (Part 5) | 15–20 min |
| **Total** | **~2.5–5 hours**, most of it unattended during the transfer itself |

---

## Part 3: First-Boot Re-Authentication

A full clone carries files and Keychain data over, but some things are tied to the physical hardware itself, not to what's on disk — these need attention regardless of clone method.

- **Touch ID** — biometric enrollment never transfers on any migration method (it's hardware-bound). Not applicable here since Mac Mini has no Touch ID hardware — confirming explicitly rather than silently skipping.
- **App license reactivation** — apps that tie licensing to a hardware ID/serial (e.g. Adobe, Microsoft Office) may demand reactivation once they see FleetDev's serial number differs from mb's, even with every file present. Expect this, don't treat it as breakage.
- **iCloud / Apple ID device trust** — Apple ID itself should carry over, but first launch on new hardware can trigger a "new device" 2FA challenge or trust prompt. Expected, not an error.
- **Google Drive re-verification** — credentials/tokens may carry over via Keychain, but first sync on new hardware can prompt a re-auth or device-trust step.
- **OneDrive** — do NOT rely on the cloned copy. See Part 4 step 5 — OneDrive gets fully uninstalled and reinstalled fresh on FleetDev rather than re-authenticated in place.
- **App permissions** (Camera, Microphone, Files & Folders, Screen Recording, Accessibility, etc.) — macOS ties these to the specific hardware's TCC database entries per device; expect to re-grant on first launch of anything that needed them on mb.

None of this is cleanup or reinstallation — it's just the category of prompt to expect on first boot, so it doesn't read as something having gone wrong with the clone.

---

## Part 4: Post-Clone Divergence

This is the real work of this migration — not gathering config (it all comes over automatically), but making FleetDev stop being an identical twin of mb.

### 1. Tailscale — do this early
FleetDev will boot as a byte-for-byte copy of mb's Tailscale state. **Do not let it join the tailnet as a re-keyed duplicate of mb's existing node.**
- Create a new Tailscale identity/registration for FleetDev before, or immediately at, its first boot onto the tailnet.
- Confirm FleetDev appears as its own distinct node in `tailscale status`, not a collision with mb.

### 2. Hostname rename
FleetDev will boot identified as mb (full clone). Rename it to FleetDev post-clone before doing anything else machine-identity-related.

### 3. Launchd services — three categories, three different treatments

**heartbeat-writer**
- Runs under the *same label*, as-is, on every fleet Mac. This is the established fleet convention.
- No changes needed. Expected to duplicate across mb and FleetDev.

**mb-health-monitor / mb-nightly-summary**
- Do **not** let the cloned mb-* copies run on FleetDev.
- Create new `fleetdev-health-monitor` / `fleetdev-nightly-summary` versions, modeled on the mb originals, pointed at FleetDev's own paths and identity.
- Unload/disable (don't delete) the cloned mb-* versions that arrive on FleetDev via the clone, so there's no path/identity confusion later.

**The 4 app services + comfy-fleet-http/scan + fleet-digest**
- Per the fleet doc, these are the services intended to migrate to FleetDev.
- **Open question, not yet resolved:** since both machines run together for a while, should these run on both temporarily, or only start on FleetDev once it's verified stable? Decide this before commissioning, don't assume.

### 4. OneDrive — clean reinstall, not a cloned re-auth

OneDrive is the one cloud-sync client not treated as a simple re-auth. The full clone brings over mb's entire local OneDrive folder (~15G) plus its sync-client app state — rather than let FleetDev inherit that as a starting point, tear it down and start clean:

1. Quit OneDrive on FleetDev.
2. Sign out (if it still shows signed in from the clone).
3. Uninstall: drag OneDrive.app to Trash, then remove leftover state:
   - `~/Library/Containers/com.microsoft.OneDrive`
   - `~/Library/Application Support/OneDrive`
   - `~/Library/Application Support/com.apple.sharedfilelist/*onedrive*` (if present)
4. Also remove the cloned local OneDrive data folder (`~/OneDrive` / `~/Library/CloudStorage/OneDrive-Personal`) so there's no stale copy sitting alongside the fresh install.
5. Reinstall OneDrive fresh (Microsoft's installer, not the cloned app bundle).
6. Sign in fresh on FleetDev and let it resync from the cloud from scratch.

mb's own OneDrive install and sync are untouched by any of this — this is FleetDev-only cleanup, done after the clone, not a pre-clone step on mb.

### 5. Explicitly deferred — do not act on yet
- Decommissioning duplicate services on mb once FleetDev is confirmed stable. This is a future step once the transition period ends.

---

## Part 5: Verification Checklist

### Dev environment integrity (confirms the clone transferred a working state, not a fresh install)
- [ ] `brew doctor` runs clean
- [ ] `gh --version && gh auth status` — authenticated without re-login
- [ ] `git --version` and `git config --global user.name`/`user.email` already correct
- [ ] `node --version`
- [ ] `python3 --version`

### Identity / networking
- [ ] FleetDev shows its own hostname (not "mb")
- [ ] FleetDev registered on Tailscale as a distinct node, not a re-key of mb
- [ ] `tailscale status` shows both mb and FleetDev separately

### Launchd services
- [ ] `heartbeat-writer` running on both mb and FleetDev under the same label (expected/correct)
- [ ] `fleetdev-health-monitor` and `fleetdev-nightly-summary` created and running on FleetDev
- [ ] Cloned `mb-health-monitor` / `mb-nightly-summary` copies on FleetDev are unloaded/disabled, not running
- [ ] Decision made and documented on whether the 4 app services + comfy-fleet-http/scan + fleet-digest run on both machines during transition or only on FleetDev

### Cleanup verification (should NOT be present on FleetDev after clone, since removed from mb pre-clone)
- [ ] No Parallels Windows 11 VM
- [ ] No Blender support files
- [ ] No Insta360/QooCamStudio support files
- [ ] No Whisky
- [ ] Playwright cache empty (regenerate via `npx playwright install` if/when needed)

### General usability
- [ ] Wi-Fi connects (if used — FleetDev is Ethernet-capable and likely wired, but confirm whichever applies)
- [ ] OneDrive fully uninstalled-and-reinstalled fresh on FleetDev (not just re-authenticated on the cloned install) — see Part 4 step 4
- [ ] No leftover cloned OneDrive local folder/state remains alongside the fresh install
- [ ] Google Drive actually resyncing correctly on the new hardware, not just authenticated
- [ ] iCloud (Photos/Messages/Drive as applicable) resyncing correctly

### Functional
- [ ] SSH to the 3 Windows fleet boxes works (keys carried over via Keychain/full clone)
- [ ] Python venv-backed services (search_adv, search_shows, tmdb_explorer) run without modification (shebang paths intact via full clone)
- [ ] `~/repos/scripts` present and PATH references resolve correctly

---

## Part 6: Troubleshooting

- **Migration Assistant stalls or fails partway through a 512GB-scale transfer** — retry over a wired Ethernet connection rather than Wi-Fi if not already using one; confirm both machines stay awake (disable sleep) for the duration.
- **An app license won't reactivate on FleetDev** — expected for some hardware-ID-tied licenses (see Part 3); check the vendor's device-management/deactivation page to free up a seat if it was capped by device count.
- **`brew doctor` reports issues post-clone** — check for stale symlinks referencing mb-specific paths before assuming a real breakage; Homebrew's Cellar paths themselves are typically absolute and clone correctly.
- **A cloud service (OneDrive/Google Drive/iCloud) shows connected but isn't actually syncing** — sign out and back in on FleetDev specifically; Keychain-carried tokens sometimes need a fresh handshake on new hardware even when they don't prompt for it upfront.
- **Venv-backed launchd services fail to start on FleetDev** — check `~/Library/Logs/<service>.log` first; if the failure is a missing Python interpreter path, the Homebrew Python cellar version didn't survive the clone as expected — this would be a deviation from Part 2's stated expectation and worth investigating rather than working around.

---

## Open Questions Log

Tracking unresolved items so they don't get silently assumed:

1. **Should the 4 migrating app services (+ comfy-fleet-http/scan + fleet-digest) run on both mb and FleetDev during the transition, or only start on FleetDev once verified stable?** — Not yet decided.
2. **`~/fleet_monitor/` (20K)** — needs confirmation nothing still writes here before deletion; may be superseded by the heartbeat writer under `~/repos/scripts`.
3. **Decommissioning duplicate mb services once FleetDev is stable** — deliberately deferred, revisit later.

---

## Reference: Fleet Context

- **mb** (denniss-macbook-air) — 100.72.187.19 — macOS, Apple M2/8GB — daily driver, not always-on
- **FleetDev** (new) — Mac Mini M4, 512GB — to be commissioned
- Fleet-wide security policy: Ollama stays Tailscale-only on all machines; `ollama.ldmathes.cc` DNS record must never be recreated
- Cloudflare tunnels are CLI-created only — inject existing JSON from fleet-configs repo during any rebuild, never create new tunnel IDs

---

**Document Version:** 2.0
**Migration:** MacBook Air M2 (mb) → Mac Mini M4 (FleetDev), full clone approach
