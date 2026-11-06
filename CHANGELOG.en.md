# Changelog

[中文](CHANGELOG.md) | **English**

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- All in-app text is now in English: `netdoctor` CLI output, the web UI, the SwiftUI app, the build scripts and the `Brewfile` comments.

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
