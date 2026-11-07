<p align="center"><img src="assets/icon-256.png" width="128" alt="NetDoctor"></p>

# NetDoctor — macOS 网络诊断工具集

**中文** | [English](README.en.md)

**一句话**:遇到“网上不去/网页打不开/视频卡”,打开 NetDoctor,先点 **Quick check**(一键体检),它会从网关、外网 IP、DNS 到 HTTP 逐层检查,告诉你问题出在哪一层。

三种使用方式,背后是同一套诊断逻辑:

| 形态 | 适合 | 入口 |
|---|---|---|
| 命令行 | 终端用户、SSH、脚本 | `./netdoctor quick` |
| 网页界面 | 想点按钮,零依赖(仅需 python3) | `./NetDoctor.command` |
| 原生 SwiftUI 应用 | 日常常驻,菜单栏实时看延迟 | `NetDoctorApp/build-app.sh` |

原生应用、网页界面和命令行输出都支持中英双语(跟随系统/浏览器语言;命令行可用 `NETDOCTOR_LANG=zh|en` 强制,网页左下角可手动切换)。下文用英文界面名标注按钮,中文界面对应“一键体检 / 运行 / 停止 / 复制 / 保存”等。另附 `Brewfile`,一次装好 mtr、nmap、iperf3、wireshark 等常用第三方工具。版本变更见 [CHANGELOG](CHANGELOG.md)。

## 图形界面
```bash
./NetDoctor.command        # 双击或运行,自动打开浏览器界面
./make-app.sh            # 可选:生成 NetDoctor.app,拖进“应用程序”
```
左侧选工具(如 **Quick check**、**DNS compare**),填参数,点 **Run**,输出实时显示,可 **Stop** / **Copy** / **Save** / **Copy as Markdown**。界面语言跟随浏览器,左下角 🌐 可切换中文 / English;主题默认跟随系统外观,也可用旁边的 🖥/☀️/🌙 按钮手动选择自动 / 浅色 / 深色。
需要管理员权限的功能(**Connections**、**Flush DNS**,以及 **Wi-Fi** / **Route / path** 勾选 *Administrator rights* 后的完整信息)会弹出系统密码框。
命令面板:按 `⌘/Ctrl+K`,输入关键词(中英文都行)即可搜索并跳转到任意工具或页面。
速度趋势:左侧 📉 **Speed trend** 或按 `p`,点 Run speed test 测速,结果自动画成下载 / 上传速度随时间变化的曲线。
自动体检:左侧 🔁 **Auto-check** 或按 `a`,按间隔在后台自动运行“智能诊断”,结论变化时发通知,适合排查时断时续的问题。
报告:历史面板的 **Report…** 可导出 Markdown 或自带样式的 HTML 报告,方便发给同事或贴进工单。
监控列表:左侧 📋 **Watchlist** 或按 `f`,逐个 ping 收藏的主机,显示状态和趋势;勾选 **Notify** 后掉线 / 恢复时发桌面通知,标签页标题显示 `⚠ N`。
Wi-Fi 信号:左侧 📶 **Wi-Fi signal** 或按 `w`,画出信号 / 噪声曲线(仅 macOS)。
收藏:主机 / 域名 / URL 输入框旁的 ☆ 加入收藏,点标签即可填入,所有工具通用。
对比:历史面板里勾选两条记录点 **Compare**,按行显示差异。历史可 **Export** / **Import** 为 JSON(含收藏)。
实时延迟:左侧 📈 **Live latency** 或按 `m`,每秒 ping 一次并画折线图(延迟 / 抖动 / 丢包)。
历史记录:每次运行自动保存(最近 50 条,含完整输出),点左侧 🕘 或按 `h` 打开,可搜索、查看、**重新运行**、删除;只保存在本机浏览器里。网页默认端口 8765(被占用时自动换端口),`--port` 可指定。
快捷键(按 `?` 查看全部):`⌘/Ctrl+Enter` 运行,`Esc` 停止,`j`/`k` 切换工具,`1`–`9` 跳转,`/` 聚焦输入框,`c` 复制,`s` 保存,`m` 实时延迟,`w` Wi-Fi 信号,`f` 监控列表,`a` 自动体检,`p` 速度趋势,`⌘/Ctrl+K` 命令面板,`h` 历史,`l` 语言,`t` 主题。
没有终端时,需要 `sudo` 的步骤不会卡在密码提示:勾选 *Administrator rights* 会弹出系统密码框,否则会被跳过或降级(例如 mtr 回退为 traceroute)。
安全:只监听 127.0.0.1,带随机令牌,校验 Host 头,参数白名单且不经 shell。

## 命令行

```bash
brew bundle --file=Brewfile        # 安装第三方工具
sudo ln -s "$PWD/netdoctor" /usr/local/bin/netdoctor   # 可选:全局使用
netdoctor quick                      # 先跑 quick(一键体检)
netdoctor tools                      # 查看装了哪些
```

## 按症状选工具
| 症状 | 命令 / 工具 |
|---|---|
| 完全上不了网 | `netdoctor quick`(逐层判断:网关→IP→DNS→HTTP) |
| Wi-Fi 卡/断 | `netdoctor wifi`;Option+点 Wi-Fi 图标 → 无线诊断 |
| 网页打不开但 ping 通 | `netdoctor dns x.com` → `netdoctor http URL` → `netdoctor proxy` |
| 某跳丢包/延迟高 | `netdoctor route host`(mtr)、`gping`、`trip` |
| 不知道哪里坏了 | `netdoctor doctor`(逐层检查,给出结论和下一步建议) |
| 连上 Wi-Fi 却打不开网页(要登录?) | `netdoctor captive` |
| 某些网站慢 / IPv6 异常 | `netdoctor ipv6` |
| ping 被屏蔽 / 想测端口延迟 | `netdoctor tcpping host 443`(TCP 连接延迟与丢包) |
| DNS 慢 / 想选最快的 DNS | `netdoctor dnsbench`(对比并推荐);`netdoctor dnsbench yes` 直接切到最快的两个;`netdoctor dnsset restore` 一键还原原设置(改前自动备份,改完解析不了会自动改回) |
| 想知道网内有哪些设备 | `netdoctor lan`(IP / MAC / 主机名) |
| 连上 Wi-Fi / 网线却上不了网, IP 以 169.254 开头 | `netdoctor dhcp`(查看 DHCP 租约;识别“自分配地址 = DHCP 失败”,`doctor` 也会自动判断) |
| 网络时好时坏、不知道卡在哪一段 | `netdoctor mtr <主机>`(逐跳丢包和延迟,并判断问题出在你的路由器、运营商还是更远处;中间路由器限速 ping 会被识别为无害) |
| 开着 VPN 担心 DNS / IPv6 泄漏 | `netdoctor leak`(检查 DNS 请求和 IPv6 是否绕过隧道,给出修复办法) |
| 想知道这台 Mac 对网络开放了哪些端口、有没有不该暴露的服务 | `netdoctor exposure`(本机监听端口分为"对网络开放 / 仅本机",标出 SSH、共享、数据库、Docker 等风险并检查防火墙;检查别的主机用 `netdoctor ports`) |
| Wi-Fi 慢 / 老掉线,怀疑邻居信道干扰 | `netdoctor channels`(扫描附近网络,判断你的信道是否拥挤,并推荐更空的信道) |
| 想知道局域网里有哪些 AirPlay、打印机、共享服务 | `netdoctor bonjour`(发现 Bonjour / mDNS 广播的服务;所有能应答 ping 的设备用 `netdoctor lan`) |
| 想一眼看全网络状态 | `netdoctor overview`(网卡 / IP / 网关 / DNS / Wi-Fi / 代理 / 公网 IP) |
| 端口不通 | `netdoctor port host 443`、`nmap -p 443 host` |
| 一次查多个端口 | `netdoctor ports host`(常用端口)、`netdoctor ports host 22,80,443`、`netdoctor ports host 1-1024` |
| HTTPS/证书问题 | `netdoctor tls host`、`testssl host` |
| VPN 后部分网站卡 | `netdoctor mtu`、`netdoctor route host`(看走哪块 utun) |
| 谁在占带宽 | `sudo bandwhich`、`nettop -P`、`netdoctor conns` |
| 需要看包 | `netdoctor capture 'host x'` → Wireshark 打开 |
| 测速 | `netdoctor speed`(networkQuality);局域网用 `iperf3 -s` / `iperf3 -c` |
| DNS 异常 | `netdoctor fixdns` |
| 出了问题想让工具直接修 | `netdoctor fix`(先诊断,再按结论重新获取 DHCP / 刷新 DNS / 校准时钟 / 打开登录页,每步确认,修完自动复查) |
| “昨天还好好的” | 好的时候先 `netdoctor report` 存一份,出问题再存一份,然后 `netdoctor compare`(自动对比最新两份,忽略延迟波动,只列出网关 / IP / DNS / 结论的变化) |
| 想盯一会儿看网络会不会掉线 | `netdoctor watch`(默认 ping 1.1.1.1 共 60 秒;断线即时提示并响铃,结束给出丢包、抖动和断线汇总;`netdoctor watch 主机 300` 指定主机和秒数) |
| 要把排查结果发给别人 / 留档 | `netdoctor report`(诊断、概览、DHCP、体检、Wi-Fi、DNS、IPv6、代理等保存到桌面文件;`netdoctor report html` 存成带颜色、可折叠的网页;`netdoctor report redact` 会自动隐藏公网 IP、MAC、Wi-Fi 名称等个人信息) |

## 常用速查(系统自带)
- `scutil --dns` / `scutil --proxy`:真实生效的 DNS、代理
- `networksetup -listallnetworkservices`:网络服务;`-setdnsservers Wi-Fi 1.1.1.1`
- `route -n get default`、`netstat -rn`:路由表
- `arp -a`:局域网邻居;`ifconfig`:接口
- `lsof -nP -iTCP -sTCP:LISTEN`:谁在监听
- `sudo log stream --predicate 'subsystem == "com.apple.networkd"'`:系统网络日志
- `sudo wdutil diagnose`:生成 Wi-Fi 诊断包

> 注:macOS 14.4+ 已移除 `airport` 命令,脚本用 `wdutil`/`system_profiler` 代替。

## 原生 SwiftUI 应用 (macOS 13+)
```bash
xcode-select --install        # 已装可跳过
cd NetDoctorApp && ./build-app.sh   # UNIVERSAL=1 ./build-app.sh 生成 Intel+Apple 芯片通用版
open NetDoctor.app
```
功能:全部诊断工具、实时输出、停止 / 复制 / 保存、实时延迟折线图、菜单栏常驻延迟显示、**健康历史**(定时在后台跑诊断,时间线上显示什么时候、哪一层出过问题;菜单栏 → 自动健康检查 选间隔,记录保存 14 天)、**速度历史**(定时自动测速,画出下载 / 上传 / 响应性随时间的变化;菜单栏 → 自动测速 选间隔,默认关闭,记录保存 30 天;一次测速会用掉很多流量,连接 iPhone 热点时自动跳过)。界面语言跟随系统(简体中文 / English)。
如果在你的工具链上构建失败,欢迎提 issue。
开发调试:`cd NetDoctorApp && NETDOCTOR_PATH=../netdoctor swift run`
