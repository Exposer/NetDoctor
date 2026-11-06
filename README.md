# NetDoctor — macOS 网络诊断工具集

**中文** | [English](README.en.md)

**一句话**:遇到“网上不去/网页打不开/视频卡”,打开 NetDoctor,先点“一键体检”,它会从网关、外网 IP、DNS 到 HTTP 逐层检查,告诉你问题出在哪一层。

三种使用方式,背后是同一套诊断逻辑:

| 形态 | 适合 | 入口 |
|---|---|---|
| 命令行 | 终端用户、SSH、脚本 | `./netdoctor quick` |
| 网页界面 | 想点按钮,零依赖(仅需 python3) | `./NetDoctor.command` |
| 原生 SwiftUI 应用 | 日常常驻,菜单栏实时看延迟 | `NetDoctorApp/build-app.sh` |

另附 `Brewfile`,一次装好 mtr、nmap、iperf3、wireshark 等常用第三方工具。版本变更见 [CHANGELOG](CHANGELOG.md)。

## 图形界面
```bash
./NetDoctor.command        # 双击或运行,自动打开浏览器界面
./make-app.sh            # 可选:生成 NetDoctor.app,拖进“应用程序”
```
左侧选工具,填参数,点“运行”,输出实时显示,可停止/复制/保存。
需要管理员权限的功能(连接/监听、刷新 DNS,以及 Wi-Fi/路由的完整信息)会弹出系统密码框。
安全:只监听 127.0.0.1,带随机令牌,校验 Host 头,参数白名单且不经 shell。

## 命令行

```bash
brew bundle --file=Brewfile        # 安装第三方工具
sudo ln -s "$PWD/netdoctor" /usr/local/bin/netdoctor   # 可选:全局使用
netdoctor quick                      # 先跑一键体检
netdoctor tools                      # 查看装了哪些
```

## 按症状选工具
| 症状 | 命令 / 工具 |
|---|---|
| 完全上不了网 | `netdoctor quick`(逐层判断:网关→IP→DNS→HTTP) |
| Wi-Fi 卡/断 | `netdoctor wifi`;Option+点 Wi-Fi 图标 → 无线诊断 |
| 网页打不开但 ping 通 | `netdoctor dns x.com` → `netdoctor http URL` → `netdoctor proxy` |
| 某跳丢包/延迟高 | `netdoctor route host`(mtr)、`gping`、`trip` |
| 端口不通 | `netdoctor port host 443`、`nmap -p 443 host` |
| HTTPS/证书问题 | `netdoctor tls host`、`testssl host` |
| VPN 后部分网站卡 | `netdoctor mtu`、`netdoctor route host`(看走哪块 utun) |
| 谁在占带宽 | `sudo bandwhich`、`nettop -P`、`netdoctor conns` |
| 需要看包 | `netdoctor capture 'host x'` → Wireshark 打开 |
| 测速 | `netdoctor speed`(networkQuality);局域网用 `iperf3 -s` / `iperf3 -c` |
| DNS 异常 | `netdoctor fixdns` |

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
功能:全部诊断工具、实时输出、停止/复制/保存、实时延迟折线图、菜单栏常驻延迟显示。
开发调试:`cd NetDoctorApp && NETDOCTOR_PATH=../netdoctor swift run`
