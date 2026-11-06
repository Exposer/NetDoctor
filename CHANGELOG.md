# Changelog

**中文** | [English](CHANGELOG.en.md)

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),版本号遵循语义化版本。

## [未发布]

### 变更
- 网页界面、构建脚本和 `Brewfile` 注释改为英文。
- SwiftUI 应用与 `netdoctor` 命令行输出支持中英双语,跟随系统语言(`NETDOCTOR_LANG=zh|en` 可强制指定);字符串位于 `NetDoctorApp/Resources/*.lproj`。

## [1.0.0] - 2026-11-06

首个版本。

### 新增
- **命令行工具 `netdoctor`**:`quick` 一键体检(网关 → 外网 IP → DNS → HTTP 逐层判断),以及 `wifi`、`dns`、`route`、`ping`、`port`、`http`、`tls`、`mtu`、`speed`、`conns`、`proxy`、`capture`、`fixdns`、`report`、`tools`。
- **网页图形界面 `netdoctor-gui.py`**:仅用 Python 标准库,实时输出、可停止/复制/保存;只监听 127.0.0.1,带随机令牌、Host 校验和参数白名单。
- **原生 SwiftUI 应用 `NetDoctorApp`**(macOS 13+):全部诊断工具、实时延迟折线图(延迟/抖动/丢包)、菜单栏常驻延迟显示、管理员权限弹窗;用 `build-app.sh` 以 SwiftPM 构建,无需 Xcode 工程。
- **`Brewfile`**:一键安装 mtr、iperf3、nmap、gping、trippy、doggo、testssl、wireshark、bandwhich 等第三方工具。
- **`make-app.sh`**:把网页版打包成可双击的 `NetDoctor.app`。
- `README.md`:按症状选工具的对照表与系统命令速查。

### 说明
- Wi-Fi 信息改用 `wdutil` 和 `system_profiler`,因为 macOS 14.4 起已移除 `airport` 命令。
- SwiftUI 应用的源码尚未在 macOS 上编译验证,首次构建如遇报错请提交 issue。
