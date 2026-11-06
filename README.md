# NetDoctor — macOS 网络诊断工具集

## 图形界面
```bash
./NetDiag.command        # 双击或运行,自动打开浏览器界面
./make-app.sh            # 可选:生成 NetDiag.app,拖进“应用程序”
```
左侧选工具,填参数,点“运行”,输出实时显示,可停止/复制/保存。
需要管理员权限的功能(连接/监听、刷新 DNS,以及 Wi-Fi/路由的完整信息)会弹出系统密码框。
安全:只监听 127.0.0.1,带随机令牌,校验 Host 头,参数白名单且不经 shell。

## 命令行

```bash
brew bundle --file=Brewfile        # 安装第三方工具
sudo ln -s "$PWD/netdiag" /usr/local/bin/netdiag   # 可选:全局使用
netdiag quick                      # 先跑一键体检
netdiag tools                      # 查看装了哪些
```

## 按症状选工具
| 症状 | 命令 / 工具 |
|---|---|
| 完全上不了网 | `netdiag quick`(逐层判断:网关→IP→DNS→HTTP) |
| Wi-Fi 卡/断 | `netdiag wifi`;Option+点 Wi-Fi 图标 → 无线诊断 |
| 网页打不开但 ping 通 | `netdiag dns x.com` → `netdiag http URL` → `netdiag proxy` |
| 某跳丢包/延迟高 | `netdiag route host`(mtr)、`gping`、`trip` |
| 端口不通 | `netdiag port host 443`、`nmap -p 443 host` |
| HTTPS/证书问题 | `netdiag tls host`、`testssl host` |
| VPN 后部分网站卡 | `netdiag mtu`、`netdiag route host`(看走哪块 utun) |
| 谁在占带宽 | `sudo bandwhich`、`nettop -P`、`netdiag conns` |
| 需要看包 | `netdiag capture 'host x'` → Wireshark 打开 |
| 测速 | `netdiag speed`(networkQuality);局域网用 `iperf3 -s` / `iperf3 -c` |
| DNS 异常 | `netdiag fixdns` |

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
cd NetDiagApp && ./build-app.sh   # UNIVERSAL=1 ./build-app.sh 生成 Intel+Apple 芯片通用版
open NetDiag.app
```
功能:全部诊断工具、实时输出、停止/复制/保存、实时延迟折线图、菜单栏常驻延迟显示。
开发调试:`cd NetDiagApp && NETDIAG_PATH=../netdiag swift run`
