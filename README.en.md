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
Pick a tool on the left, fill in the parameters, click "Run". The UI follows your browser language; the 🌐 button at the bottom left switches between English and 中文. The theme follows the system appearance by default; the 🖥/☀️/🌙 button next to it lets you pick Auto / Light / Dark. Output streams live and can be stopped, copied or saved.
Features that need administrator rights (connections/listeners, flush DNS, and the full Wi-Fi/route details) show the system password prompt.
Wi-Fi signal: open the 📶 **Wi-Fi signal** entry (or press `w`) for live signal and noise curves (macOS only).
Favorites: the ☆ next to a host / domain / URL input saves it; click a chip to fill it in, in any tool.
Compare: tick two runs in the history panel and press **Compare** for a line diff. History can be **Export**ed / **Import**ed as JSON (favorites included).
Live latency: open the 📈 **Live latency** entry (or press `m`) to ping a target once a second and watch a chart of latency, jitter and loss.
History: every run is saved automatically (latest 50, full output included). Open it with the 🕘 sidebar button or `h`; search, view, **Re-run** or delete entries. It is stored only in your browser. The web UI listens on port 8765 by default (a free port is used if it is busy); change it with `--port`.
Keyboard shortcuts (press `?` for the full list): `⌘/Ctrl+Enter` run, `Esc` stop, `j`/`k` change tool, `1`–`9` jump, `/` focus input, `c` copy, `s` save, `m` live latency, `w` Wi-Fi signal, `h` history, `l` language, `t` theme.
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
| Port unreachable | `netdoctor port host 443`, `nmap -p 443 host` |
| HTTPS / certificate problems | `netdoctor tls host`, `testssl host` |
| Some sites are slow over VPN | `netdoctor mtu`, `netdoctor route host` (see which utun is used) |
| What is using the bandwidth | `sudo bandwhich`, `nettop -P`, `netdoctor conns` |
| Need to inspect packets | `netdoctor capture 'host x'` → open in Wireshark |
| Speed test | `netdoctor speed` (networkQuality); on a LAN use `iperf3 -s` / `iperf3 -c` |
| Odd DNS behavior | `netdoctor fixdns` |

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
Features: all diagnostic tools, live output, stop/copy/save, a live latency chart, and latency shown in the menu bar. The UI follows the system language (English / Simplified Chinese).
If the build fails on your toolchain, please open an issue.
Development: `cd NetDoctorApp && NETDOCTOR_PATH=../netdoctor swift run`
