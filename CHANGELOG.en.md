# Changelog

[中文](CHANGELOG.md) | **English**

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

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
