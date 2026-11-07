# Changelog

**中文** | [English](CHANGELOG.en.md)

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),版本号遵循语义化版本。

## [1.1.5] - 2026-11-07

### 新增
- 网页界面:**Wi-Fi signal**(Wi-Fi 信号)页:每约 1.5 秒读取一次信号 / 噪声 / 信噪比 / 信道 / 速率,画出信号与噪声曲线,背景按好(> −60 dBm)/ 一般 / 差分色;左侧栏 📶 或按 `w` 打开。数据来自 `system_profiler`,无需 sudo,仅 macOS。
- 网页界面:**收藏常用主机**。主机 / 域名 / URL 输入框旁的 ☆ 可加入收藏,所有工具和实时延迟页共用,以标签形式显示,点击填入(URL 与主机会自动转换),× 删除,最多 30 个。
- 网页界面:**对比两次运行**。在历史面板勾选两条记录点 Compare,按行 diff 显示新增 / 删除,可选“仅显示差异”和“忽略数字”(耗时等数字不同不算差异)。
- 网页界面:**历史导出 / 导入**。导出为 JSON(含收藏),导入时校验并清理字段、按 id 去重、最多保留 50 条。
- 网页界面:**Live latency**(实时延迟)页,与 SwiftUI 应用对齐:每秒 ping 一次目标(可选 1.1.1.1、8.8.8.8、223.5.5.5、114.114.114.114 或自填),显示当前 / 平均 / 最小最大 / 抖动 / 丢包,并画出最近 120 个样本的折线图,丢包用红线标出;左侧栏 📈 或按 `m` 打开,切走时自动停止。
- 网页界面:历史记录。每次运行(含停止、失败)自动保存工具、参数、状态、耗时和完整输出,最近 50 条;左侧栏 🕘 或按 `h` 打开面板,可搜索、点击查看、**重新运行**、删除或清空。仅保存在浏览器本地(localStorage)。

### 变更
- 网页界面默认端口固定为 8765(被占用时自动换空闲端口),这样历史记录、主题和语言选择在重启服务后不会丢失;`--port 0` 仍可使用随机端口。

## [1.1.2] - 2026-11-06

### 新增
- 网页界面:键盘快捷键。`⌘/Ctrl+Enter` 运行,`Esc` 停止,`j`/`k` 或方向键切换工具,`1`–`9` 跳转,`/` 聚焦输入框,`c` 复制,`s` 保存,`l` 切换语言,`t` 切换主题,`?` 查看快捷键列表;在输入框里打字时不会触发单键快捷键。

## [1.1.1] - 2026-11-06

### 新增
- 网页界面:新增主题切换(自动 / 浅色 / 深色),左侧栏 🖥/☀️/🌙 按钮循环切换;“自动”跟随系统外观,选择会被记住。

## [1.1.0] - 2026-11-06

### 变更
- 构建脚本和 `Brewfile` 注释改为英文。
- `netdoctor` 的语言由 `NETDOCTOR_LANG` 或 `LANG` 决定;网页界面固定按所选语言调用。
- 网页界面、SwiftUI 应用与 `netdoctor` 命令行输出支持中英双语,跟随系统语言(`NETDOCTOR_LANG=zh|en` 可强制指定);应用字符串位于 `NetDoctorApp/Resources/*.lproj`;网页界面跟随浏览器语言,可在页面上手动切换(记住选择)。

### 修复
- SwiftUI 应用:去掉 `Package.swift` 中的 `swiftLanguageVersion`,修复在新版工具链上构建失败的问题。
- `netdoctor`:新增 `priv()` 提权助手,无终端(网页 / 应用调用)时用 `sudo -n`,不再卡在密码提示;`route` 在没有权限时从 mtr 回退到 traceroute 并给出提示。
- `netdoctor tls`:兼容 macOS 自带的 LibreSSL;取不到证书时明确报错并返回非零退出码。
- `netdoctor speed`:修复 `networkQuality` 成功时误报错误;修正若干命令的退出码。
- 网页界面:浏览器断开(点“停止”或关闭页面)时结束子进程,避免遗留后台进程。

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
