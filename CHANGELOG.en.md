# Changelog

[中文](CHANGELOG.md) | **English**

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `netdoctor ipv6` and a matching **IPv6 check** tool: checks for a global IPv6 address (link-local and private ones are ignored), AAAA resolution and real IPv4 / IPv6 reachability, and explains the problem when an IPv6 address exists but traffic fails. `report` includes it too.
- `netdoctor captive` and a matching **Captive portal** tool: detects Wi-Fi that needs a login before it gives internet access, and shows the redirect URL.
- Web UI: a **command palette**. Press `⌘/Ctrl+K` and type a name, a description or an English / Chinese keyword to search and jump to any tool or page (including live latency, Wi-Fi signal, watchlist, auto-check, history and the shortcut help); it can also switch language and theme. `↑` / `↓` select, `Enter` opens, `Esc` closes.
- Web UI: a **Speed trend** page, opened from the 📉 sidebar entry or with `p`. Run speed test measures with `networkQuality` and stores the result in History; download / upload speeds are parsed from the history and charted over time, with the latest, average and best download speed (Gbps / Kbps are converted to Mbps). A run whose output cannot be read is reported instead of being plotted as a data point.
- Web UI: an **Auto-check** page, opened from the 🔁 sidebar entry or with `a`. It runs Diagnose in the background every 1 / 5 / 15 / 30 / 60 minutes and keeps going while you use other pages (the sidebar shows ●). Each result is stored in History, and a timeline shows Healthy / Unstable / Problem with the verdict; View opens the full output. With **Notify** ticked it sends a desktop notification when the verdict changes (for example from healthy to a DNS problem, or back) and the tab title shows ⚠ while there is a problem. Handy for intermittent network trouble.
- Web UI: a **Report…** menu in the history panel exports entries as **Markdown** or as a self-contained **HTML** report (colours kept, all content escaped, light / dark aware). If entries are ticked only those are exported, otherwise the current search result.

### Changed
- Web UI: HTML escaping of the output pane now also covers `>` (defence in depth); exporting a report from an empty selection now shows a message instead of doing nothing.
- `netdoctor`: an unknown command now prints "Unknown command: xxx" with the running version (and a hint to `git pull`) before the usage text, and exits with status 2. Added `netdoctor --version` (also `version` and `-v`) as well as `help`, `-h` and `--help`. Previously an unrecognised command silently printed the usage text, which made it impossible to tell a typo from an outdated local copy.

### Fixed
- `netdoctor http`: an error status such as 404 or 500 was only listed as a number, with no verdict and exit code 0; 2xx now shows a pass, and 3xx / 4xx / 5xx give an explanation (the network works, but the server rejected the request or failed) and exit code 1.
- `netdoctor tls`: the host name was never verified, so a certificate issued for another name (for example `wrong.host.badssl.com`, which presents `*.badssl.com`) still showed "Verification: OK". OpenSSL now uses `-verify_hostname`; the system LibreSSL, which lacks that option, gets its own SAN / CN comparison (a wildcard matches exactly one label) and reports a mismatch. The exit code is 1 when certificate verification fails (expired, self-signed, wrong host).
- Web UI and SwiftUI app: two input placeholders ("22,80,443 or 1-1024", "extra domain (optional)") stayed in English in the Chinese UI; they are now translated.
- `netdoctor-gui.py`: when the requested port was already in use, a second instance did not fail but silently shared the port with the first one (macOS allows this with `SO_REUSEADDR`), so requests landed on either server and the token mismatch showed up as a baffling "forbidden"; the port is now probed before binding and a free port is used instead, with a notice. `--port` outside 0–65535 gives a clear error instead of a traceback.
- `netdoctor report`: when run in a terminal it called `sudo wdutil` in the middle of generating the report and showed a password prompt (the output was already redirected to a file, which was confusing); the report now only uses `sudo -n` and skips that detail if admin rights are not available. Running `netdoctor wifi` on its own still asks for the password as before.
- `Brewfile`: the `wireshark` cask was renamed to `wireshark-app` (the old name is only an alias); the canonical name is used now.
- Administrator path (`osascript` in the web UI and the SwiftUI app): `do shell script` converts line feeds to `\r` by default, which broke line breaks in copied / saved text and reports; it now uses `without altering line endings`.
- Web UI: on narrow screens (phone width, half-screen windows) the page overflowed horizontally and buttons were clipped; at ≤720px the sidebar becomes a horizontally scrollable bar at the top, and the wide layout is unchanged.
- Web UI Wi-Fi signal page: shows "Reading Wi-Fi… (this can take 10+ seconds on some Macs)" during the first read so it does not look stuck (`system_profiler` takes around 13 s on some Macs and there is no faster source without sudo).
- Web UI: switching to another tool now clears the previous tool's output (before, the Diagnose page still showed the last Captive portal result and its timing, which was misleading); the output is kept while a run is in progress, when switching language and when viewing history.
- Web UI Wi-Fi signal page: `system_profiler SPAirPortDataType` takes over ten seconds on some Macs while the server timed out after 12, so the page always said "unavailable"; the timeout is now 30 s. An SSID hidden by macOS (`<redacted>`) is no longer shown.
- Web UI watchlist: a host whose first probe was lost showed Up; it now shows Waiting… and is only marked Down after 3 consecutive losses.
- Web UI: report / history export file names used the UTC date, which could differ from the local date shown on the page; they now use the local date.
- Web UI command palette: searching for a tool by its Chinese name (e.g. 诊断, 强制门户, 局域网) found nothing while the UI was in English; both the English and Chinese names of every tool are now searched.
- `netdoctor quick`: a failed public-IP lookup is now reported (the old `|| warn` could never fire, so nothing was shown); the exit code is 1 when there is no default route or any check fails (it was always 0).
- `netdoctor port` / `http` / `mtu` / `speed`: exited with 0 on failure (`bad` itself returns 0), so the web UI and app showed "exit code 0"; they now return 1.
- SwiftUI app: Stop now ends the whole process tree (it only killed direct children, so `nc` / `ping` started from background subshells by `ports`, `dnsbench` and `lan` were left running).
- Build scripts: the `Info.plist` version is read from `VERSION` in `netdoctor` instead of being hard-coded; both apps now declare `NSLocalNetworkUsageDescription` so macOS can show the Local Network permission prompt that `lan` needs to read device MAC addresses.
- `netdoctor tcpping`: the `IO::Socket::INET` that ships with macOS perl reports "connection refused" as success when a timeout (non-blocking connect) is used, so closed ports looked connected; it now uses a blocking connect with an `alarm` timeout and `getaddrinfo` (IPv6 works). A failure of perl itself no longer exits with 0.
- `netdoctor ports`: exit code was 1 when every port was open; the host is now validated so a value starting with `-` can no longer be taken as an `nc` option.
- Web UI: Stop / closing the page now terminates the whole process group (including perl / nc / networkQuality started by the script), not just bash; request bodies are capped at 64 KB.
- `netdoctor lan`: scans the whole subnet for /22 and smaller (previously anything above a /24 was cut to the /24 and devices were missed); fixes IP parsing when a hostname contains a space (e.g. `name lan`); this Mac is no longer listed twice; when the ARP table cannot be read (e.g. macOS Local Network privacy inside the web UI / app) it still lists hosts that answered ping, shows `?` for the MAC and points to the permission setting.
- `netdoctor` now always runs under `/bin/bash` (`#!/usr/bin/env bash` could pick up an old x86 bash when the web UI puts `/usr/local/bin` first in PATH, which broke commands such as `arp`); the web UI also invokes it through `/bin/bash` explicitly.


## [1.1.7] - 2026-11-07

### Added
- `netdoctor doctor` (alias `diagnose`) and a matching **Diagnose** tool: six layered checks — link → gateway → internet (by IP) → DNS → HTTPS → proxy / VPN — where later steps show "skipped" if an earlier one failed. It ends with a verdict (not connected / broken link to the router / router fine but no internet / DNS problem / web access blocked / unstable connection / healthy) and targeted next-step commands. The exit code is 1 when something is wrong, and `report` now includes the diagnosis.
- `netdoctor tcpping <host> <port> [count]` and a matching **TCP ping** tool: measures TCP connect latency to a port (min / avg / max and loss), for when ping is blocked. The exit code is 1 when nothing connects.
- `netdoctor dnsbench [domain]` and a matching **DNS benchmark** tool: compares the system DNS with 1.1.1.1, 8.8.8.8, 9.9.9.9, 223.5.5.5, 119.29.29.29, 114.114.114.114 and 180.76.76.76 in parallel, using 5 common domains (plus one of your own), and ranks them by average / minimum latency and success rate. When the system DNS is noticeably slower it prints the `networksetup -setdnsservers` commands to switch and to undo (it never changes anything itself).
- `netdoctor lan` and a matching **LAN scan** tool: pings the local subnet in parallel (only the surrounding /24 if the network is larger), then reads the ARP table and lists IP / MAC / name, marking the gateway and this Mac. Duplicates, broadcast and multicast addresses and other subnets are filtered out.
- `netdoctor overview` and a matching **Overview** tool: one screen with the default interface and MTU, IPv4 / IPv6, MAC, gateway (with reachability), DNS servers and search domains, Wi-Fi network name, system proxy, VPN / tunnel interfaces and the public IP with its ISP. `report` includes it too.
- `netdoctor ports <host> [ports]` and a matching **Multi-port check** tool: checks many ports in parallel. By default it tests 22 common ports; you can give `22,80,443`, `1-1024` or a mix, up to 1024 per run. It lists the open ports with well-known service names and open / closed counts. Scanning 1024 local ports takes about 0.6 s.
- All of these tools are available in the CLI, the web UI and the SwiftUI app, in English and Chinese.

## [1.1.6] - 2026-11-07

### Added
- App icon: a Wi-Fi signal with a heartbeat line (a temporary design; the "Wi-Fi + stethoscope with heartbeat" version is kept in `assets/alt/`). Ships as `assets/icon.svg`, `assets/AppIcon.icns` (all sizes from 16 to 1024 px) and PNGs. Both the SwiftUI app and the web-UI `NetDoctor.app` include it when built, and the web UI uses it as its browser-tab icon. `assets/make_icns.py` packs PNGs into an `.icns` without needing `iconutil`.
- Web UI: a **Watchlist** page, opened from the 📋 sidebar entry or with `f`. It pings every favorite and shows its status (Up / Slow / Down), now / average / loss and a trend sparkline. The "slow above N ms" threshold is adjustable, and hosts can be added or removed right on the page.
- Web UI: down alerts. With **Notify** ticked, a desktop notification is sent when a host misses 3 pings in a row and again when it recovers; while a host is down the browser tab title shows `⚠ N`.
- Web UI: **Copy as Markdown** copies the current result as Markdown with a heading, arguments, timestamp and a code block, ready to paste into a ticket or chat.

## [1.1.5] - 2026-11-07

### Added
- Web UI: a **Wi-Fi signal** page. Every ~1.5 s it reads signal / noise / SNR / channel / rate and draws the signal and noise curves over bands for good (> −60 dBm), fair and poor. Open it from the 📶 sidebar entry or with `w`. Data comes from `system_profiler`, needs no sudo, macOS only.
- Web UI: **favorite hosts**. The ☆ next to a host / domain / URL input saves it; favorites are shared by every tool and the live latency page, shown as chips that fill the input on click (URLs and hostnames are converted automatically), × removes one, up to 30.
- Web UI: **compare two runs**. Tick two entries in the history panel and press Compare for a line diff with additions and deletions. "Only changes" and "Ignore numbers" options keep differing timings from counting as changes.
- Web UI: **history export / import**. Export to JSON (favorites included); import validates and sanitises every field, de-duplicates by id and keeps at most 50 entries.
- Web UI: a **Live latency** page, matching the SwiftUI app. It pings the target once a second (pick 1.1.1.1, 8.8.8.8, 223.5.5.5, 114.114.114.114 or type your own), shows now / average / min-max / jitter / loss and draws a chart of the last 120 samples with packet loss marked in red. Open it from the 📈 sidebar entry or with `m`; it stops automatically when you leave the page.
- Web UI: run history. Every run (including stopped and failed ones) is saved with its tool, parameters, status, duration and full output — the latest 50. Open the panel with the 🕘 sidebar button or the `h` key; search, click to view, **Re-run**, delete or clear. Stored only in the browser (localStorage).

### Changed
- The web UI now defaults to port 8765 (falling back to a free port if it is busy), so history, theme and language choices survive restarting the server. `--port 0` still gives a random port.

## [1.1.2] - 2026-11-06

### Added
- Web UI: keyboard shortcuts. `⌘/Ctrl+Enter` runs, `Esc` stops, `j`/`k` or the arrow keys change tool, `1`–`9` jump to a tool, `/` focuses the input, `c` copies, `s` saves, `l` switches language, `t` switches theme and `?` shows the shortcut list. Single-key shortcuts are ignored while typing in an input.

## [1.1.1] - 2026-11-06

### Added
- Web UI: theme switch (Auto / Light / Dark). The 🖥/☀️/🌙 button in the sidebar cycles through them; "Auto" follows the system appearance and the choice is remembered.

## [1.1.0] - 2026-11-06

### Changed
- Build scripts and `Brewfile` comments are now in English.
- `netdoctor` picks its language from `NETDOCTOR_LANG` or `LANG`; the web UI always calls it with the language selected on the page.
- The web UI, SwiftUI app and `netdoctor` CLI output are bilingual (English / Simplified Chinese) and follow the system language; override with `NETDOCTOR_LANG=zh|en`. App strings live in `NetDoctorApp/Resources/*.lproj`; the web UI follows the browser language and has an in-page switch (the choice is remembered).

### Fixed
- SwiftUI app: removed `swiftLanguageVersion` from `Package.swift`, fixing build failures on newer toolchains.
- `netdoctor`: added a `priv()` privilege helper that uses `sudo -n` when there is no terminal (web UI / app), so runs no longer hang on a password prompt; `route` falls back from mtr to traceroute with a notice when admin rights are missing.
- `netdoctor tls`: works with the LibreSSL shipped with macOS; reports a clear error and a non-zero exit code when no certificate is received.
- `netdoctor speed`: no longer reports a false error when `networkQuality` succeeds; corrected exit codes of several commands.
- Web UI: the child process is now killed when the browser disconnects (Stop or closing the page), so no stray background processes are left.

## [1.0.0] - 2026-11-06

First release.

### Added
- **Command-line tool `netdoctor`**: `quick` runs a one-shot check (gateway → public IP → DNS → HTTP, layer by layer), plus `wifi`, `dns`, `route`, `ping`, `port`, `http`, `tls`, `mtu`, `speed`, `conns`, `proxy`, `capture`, `fixdns`, `report` and `tools`.
- **Web UI `netdoctor-gui.py`**: Python standard library only; live output that can be stopped, copied or saved. Listens on 127.0.0.1 only, with a random token, Host header check and argument whitelist.
- **Native SwiftUI app `NetDoctorApp`** (macOS 13+): all diagnostic tools, a live latency chart (latency / jitter / packet loss), latency shown in the menu bar, and an administrator password prompt. Built with SwiftPM via `build-app.sh`; no Xcode project needed.
- **`Brewfile`**: installs third-party tools in one go — mtr, iperf3, nmap, gping, trippy, doggo, testssl, wireshark, bandwhich and more.
- **`make-app.sh`**: packages the web UI as a double-clickable `NetDoctor.app`.
- `README.md`: a symptom-to-tool table and a cheat sheet of built-in system commands.

### Notes
- Wi-Fi details now come from `wdutil` and `system_profiler`, because the `airport` command was removed in macOS 14.4.
- The SwiftUI source has not yet been compiled on macOS. If the first build fails, please open an issue.
