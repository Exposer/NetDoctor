<p align="center"><img src="assets/icon-256.png" width="128" alt="NetDoctor"></p>

# NetDoctor — Network Diagnostics Toolkit for macOS

[中文](README.md) | **English**

**In one sentence:** when the internet is down, a page won't load, or video keeps buffering, open NetDoctor and run "Quick check". It tests layer by layer — gateway, public IP, DNS, HTTP — and tells you where the problem is.

Three ways to use it, all backed by the same diagnostic logic:

| Form | Best for | Entry point |
|---|---|---|
| Command line | Terminal users, SSH, scripts | `./netdoctor quick` |
| Web UI | Clickable buttons, zero dependencies (python3 only) | `./NetDoctor.command` |
| Native SwiftUI app | Everyday use, live latency in the menu bar | `NetDoctorApp/build-app.sh` |

A `Brewfile` is included to install common third-party tools (mtr, nmap, iperf3, wireshark, …) in one go. See the [CHANGELOG](CHANGELOG.en.md) for release history.

## Web UI
```bash
./NetDoctor.command        # double-click or run; opens the UI in your browser
./make-app.sh              # optional: build NetDoctor.app to drop into /Applications
```
Pick a tool on the left, fill in the parameters, click "Run". The UI follows your browser language; the 🌐 button at the bottom left switches between English and 中文. The theme follows the system appearance by default; the 🖥/☀️/🌙 button next to it lets you pick Auto / Light / Dark. Output streams live and can be stopped, copied, saved or copied as Markdown (handy for tickets and chat).
Features that need administrator rights (connections/listeners, flush DNS, and the full Wi-Fi/route details) show the system password prompt.
Command palette: press `⌘/Ctrl+K` and type a keyword (English or Chinese) to search and jump to any tool or page.
Speed trend: open the 📉 **Speed trend** entry (or press `p`) and click Run speed test; results are charted as download / upload speed over time.
Auto-check: open the 🔁 **Auto-check** entry (or press `a`) to run Diagnose on a schedule in the background and get notified when the verdict changes — handy for intermittent problems.
Reports: the **Report…** menu in the history panel exports Markdown or a self-contained HTML report you can send to a colleague or attach to a ticket.
Watchlist: open the 📋 **Watchlist** entry (or press `f`) to ping every favorite and see its status and trend; tick **Notify** for desktop notifications when a host goes down or recovers (the tab title shows `⚠ N`).
Wi-Fi signal: open the 📶 **Wi-Fi signal** entry (or press `w`) for live signal and noise curves (macOS only).
Favorites: the ☆ next to a host / domain / URL input saves it; click a chip to fill it in, in any tool.
Compare: tick two runs in the history panel and press **Compare** for a line diff. History can be **Export**ed / **Import**ed as JSON (favorites included).
Live latency: open the 📈 **Live latency** entry (or press `m`) to ping a target once a second and watch a chart of latency, jitter and loss.
History: every run is saved automatically (latest 50, full output included). Open it with the 🕘 sidebar button or `h`; search, view, **Re-run** or delete entries. It is stored only in your browser. The web UI listens on port 8765 by default (a free port is used if it is busy); change it with `--port`.
Keyboard shortcuts (press `?` for the full list): `⌘/Ctrl+Enter` run, `Esc` stop, `j`/`k` change tool, `1`–`9` jump, `/` focus input, `c` copy, `s` save, `m` live latency, `w` Wi-Fi signal, `f` watchlist, `a` auto-check, `p` speed trend, `⌘/Ctrl+K` command palette, `h` history, `l` language, `t` theme.
Without a terminal, steps that need `sudo` never block on a password prompt: use the "Administrator rights" option to get the system password dialog, otherwise they are skipped or degrade (e.g. mtr falls back to traceroute).
Security: listens on 127.0.0.1 only, uses a random token, checks the Host header, whitelists arguments, and never passes them through a shell.

## Command line

Output language follows your locale (`LANG`); force it with `NETDOCTOR_LANG=zh` or `NETDOCTOR_LANG=en`.

```bash
brew bundle --file=Brewfile                              # install third-party tools
sudo ln -s "$PWD/netdoctor" /usr/local/bin/netdoctor     # optional: use it globally
netdoctor quick                                          # start with the quick check
netdoctor tools                                          # see which tools are installed
```

## Pick a tool by symptom
| Symptom | Command / tool |
|---|---|
| No connectivity at all | `netdoctor quick` (checks gateway → IP → DNS → HTTP) |
| Wi-Fi slow or dropping | `netdoctor wifi`; Option-click the Wi-Fi icon → Wireless Diagnostics |
| Pages won't load but ping works | `netdoctor dns x.com` → `netdoctor http URL` → `netdoctor proxy` |
| Packet loss / high latency on some hop | `netdoctor route host` (mtr), `gping`, `trip` |
| Not sure what is broken | `netdoctor doctor` (layered checks with a verdict and next steps) |
| Wi-Fi connected but pages won't load (login needed?) | `netdoctor captive` |
| Some sites slow / IPv6 problems | `netdoctor ipv6` |
| Ping is blocked / measure a port's latency | `netdoctor tcpping host 443` (TCP connect latency and loss) |
| Slow DNS / pick the fastest DNS | `netdoctor dnsbench` (compares and recommends); `netdoctor dnsbench yes` switches to the two fastest; `netdoctor dnsset restore` puts the original back (backed up first, rolled back if names stop resolving) |
| Who is on my network | `netdoctor lan` (IP / MAC / name) |
| Connected to Wi-Fi / cable but not online, IP starts with 169.254 | `netdoctor dhcp` (DHCP lease details; spots a "self-assigned address = DHCP failed", and `doctor` detects it too) |
| The connection is flaky and you do not know which segment is to blame | `netdoctor mtr <host>` (per-hop loss and latency, and whether the problem is in your router, your ISP or further away; a middle router that only rate-limits ping is recognised as harmless) |
| A VPN is on and you worry about DNS / IPv6 leaks | `netdoctor leak` (checks whether DNS requests and IPv6 bypass the tunnel, and how to fix it) |
| What this Mac exposes to the network, and whether anything should not be | `netdoctor exposure` (splits listening ports into network-reachable vs this-Mac-only, flags SSH, sharing, databases, Docker and checks the firewall; use `netdoctor ports` for another host) |
| Wi-Fi slow / drops and you suspect neighbours on the same channel | `netdoctor channels` (scans nearby networks, tells you whether your channel is crowded and recommends a quieter one) |
| What AirPlay devices, printers and shares are on the LAN | `netdoctor bonjour` (discovers services advertised over Bonjour / mDNS; use `netdoctor lan` for everything that answers ping) |
| A snapshot of the whole network state | `netdoctor overview` (interface / IP / gateway / DNS / Wi-Fi / proxy / public IP) |
| Port unreachable | `netdoctor port host 443`, `nmap -p 443 host` |
| Check many ports at once | `netdoctor ports host` (common ports), `netdoctor ports host 22,80,443`, `netdoctor ports host 1-1024` |
| HTTPS / certificate problems | `netdoctor tls host`, `testssl host` |
| Some sites are slow over VPN | `netdoctor mtu`, `netdoctor route host` (see which utun is used) |
| What is using the bandwidth | `sudo bandwhich`, `nettop -P`, `netdoctor conns` |
| Need to inspect packets | `netdoctor capture 'host x'` → open in Wireshark |
| Speed test | `netdoctor speed` (networkQuality); on a LAN use `iperf3 -s` / `iperf3 -c` |
| Odd DNS behavior | `netdoctor fixdns` |
| Want the tool to fix it | `netdoctor fix` (diagnoses, then renews DHCP / flushes DNS / syncs the clock / opens the login page as the verdict calls for; asks before each step and re-checks afterwards) |
| "It worked yesterday" | Save a `netdoctor report` while it works and another when it breaks, then run `netdoctor compare` (picks the two newest, ignores timing noise, lists changes in gateway / IP / DNS / verdicts) |
| Want to watch whether the connection drops | `netdoctor watch` (pings 1.1.1.1 for 60 s by default; tells you at once when it drops, bell included, and summarises loss, jitter and outages at the end; `netdoctor watch host 300` sets host and seconds) |
| Need to send results to someone / keep a record | `netdoctor report` (saves diagnosis, overview, DHCP, quick check, Wi-Fi, DNS, IPv6 and proxy info to a Desktop file; `netdoctor report html` makes a collapsible web page; `netdoctor report redact` hides the public IP, MAC address, Wi-Fi name and other personal info) |

## Handy built-in commands
- `scutil --dns` / `scutil --proxy`: the DNS and proxy settings actually in effect
- `networksetup -listallnetworkservices`: network services; `-setdnsservers Wi-Fi 1.1.1.1`
- `route -n get default`, `netstat -rn`: routing table
- `arp -a`: LAN neighbors; `ifconfig`: interfaces
- `lsof -nP -iTCP -sTCP:LISTEN`: who is listening
- `sudo log stream --predicate 'subsystem == "com.apple.networkd"'`: system network log
- `sudo wdutil diagnose`: generate a Wi-Fi diagnostics bundle

> Note: macOS 14.4+ removed the `airport` command; the script uses `wdutil` / `system_profiler` instead.

## Native SwiftUI app (macOS 13+)
```bash
xcode-select --install                 # skip if already installed
cd NetDoctorApp && ./build-app.sh      # UNIVERSAL=1 ./build-app.sh builds for Intel + Apple silicon
open NetDoctor.app
```
Features: all diagnostic tools, live output, stop/copy/save, a live latency chart, latency shown in the menu bar, and a **health history** (runs the diagnosis in the background on a schedule and shows on a timeline when, and at which layer, the network had problems; pick the interval in the menu bar → Automatic health check; records are kept for 14 days) and a **speed history** (runs a speed test on a schedule and charts download / upload / responsiveness over time; pick the interval in the menu bar → Automatic speed test; off by default, kept for 30 days; a test uses a lot of data, so it is skipped on metered connections such as a phone hotspot). The UI follows the system language (English / Simplified Chinese).
If the build fails on your toolchain, please open an issue.
Development: `cd NetDoctorApp && NETDOCTOR_PATH=../netdoctor swift run`
