#!/usr/bin/env python3
"""NetDoctor GUI - local web interface (standard library only, listens on 127.0.0.1 only).
Usage: python3 netdoctor-gui.py [--port 8765] [--no-open]
"""
import argparse, json, os, re, secrets, select, shlex, signal, socket, subprocess, sys, threading, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
NETDOCTOR = os.path.join(HERE, "netdoctor")
TOKEN = secrets.token_urlsafe(16)

# admin: True=required, "optional"=user can tick it, False=not needed
COMMANDS = [
 {"id":"quick","label":"Quick check","icon":"🩺","desc":"Gateway → public IP → DNS → HTTP, layer by layer, with a diagnosis","inputs":[]},
 {"id":"doctor","label":"Diagnose","icon":"🩹","desc":"Layer-by-layer checks with a verdict and suggested next steps","inputs":[]},
 {"id":"overview","label":"Overview","icon":"🗺️","desc":"Interface, IP, gateway, DNS, Wi-Fi, proxy and public IP at a glance","inputs":[]},
 {"id":"dhcp","label":"DHCP / IP address","icon":"🧾","desc":"Check the DHCP lease and spot a self-assigned 169.254 address (DHCP failed)","inputs":[]},
 {"id":"ports","label":"Multi-port check","icon":"🔢","desc":"Check common or custom ports on a host in parallel","inputs":[{"name":"host","label":"Host","ph":"example.com","req":True},{"name":"ports","label":"Ports","ph":"22,80,443 or 1-1024"}]},
 {"id":"tcpping","label":"TCP ping","icon":"⏱️","desc":"TCP connect latency to a port — for when ping is blocked","inputs":[{"name":"host","label":"Host","ph":"example.com","req":True},{"name":"port","label":"Port","ph":"443","req":True},{"name":"count","label":"Count","ph":"10","def":"10"}]},
 {"id":"lan","label":"LAN scan","icon":"🖧","desc":"Discover devices on the local network (IP, MAC, name)","inputs":[]},
 {"id":"wifi","label":"Wi-Fi","icon":"📶","desc":"SSID, signal, noise, channel, rate","inputs":[],"admin":"optional"},
 {"id":"dns","label":"DNS compare","icon":"🔎","desc":"Answers and timings from the system and several public DNS servers","inputs":[{"name":"domain","label":"Domain","ph":"example.com","req":True}]},
 {"id":"ipv6","label":"IPv6 check","icon":"6️⃣","desc":"Compare IPv4 / IPv6 connectivity and spot a broken IPv6 path","inputs":[]},
 {"id":"captive","label":"Captive portal","icon":"🚧","desc":"Wi-Fi connected but no web access? Detect a login page","inputs":[]},
 {"id":"dnsbench","label":"DNS benchmark","icon":"🏁","desc":"Compare the system and public DNS servers by speed and get a recommendation","inputs":[{"name":"domain","label":"Domain","ph":"extra domain to include (optional)"}]},
 {"id":"http","label":"HTTP timing","icon":"🌐","desc":"DNS / TCP / TLS / first byte / total breakdown","inputs":[{"name":"url","label":"URL","ph":"https://example.com","req":True}]},
 {"id":"ping","label":"Ping","icon":"📡","desc":"Packet loss and latency statistics","inputs":[{"name":"host","label":"Host","ph":"1.1.1.1","req":True},{"name":"count","label":"Count","ph":"20","def":"20"}]},
 {"id":"route","label":"Route / path","icon":"🧭","desc":"Which interface/VPN is used + hop-by-hop mtr/traceroute","inputs":[{"name":"host","label":"Host","ph":"example.com","req":True}],"admin":"optional"},
 {"id":"port","label":"Port check","icon":"🚪","desc":"Is the TCP port reachable","inputs":[{"name":"host","label":"Host","ph":"example.com","req":True},{"name":"port","label":"Port","ph":"443","req":True}]},
 {"id":"tls","label":"TLS certificate","icon":"🔒","desc":"Certificate, protocol, validity","inputs":[{"name":"host","label":"Host","ph":"example.com","req":True},{"name":"port","label":"Port","ph":"443"}]},
 {"id":"mtu","label":"MTU probe","icon":"📏","desc":"Path MTU; troubleshoot VPN / large-packet loss","inputs":[{"name":"host","label":"Host","ph":"1.1.1.1"}]},
 {"id":"speed","label":"Speed test","icon":"⚡","desc":"networkQuality bandwidth and responsiveness (~20 s)","inputs":[]},
 {"id":"conns","label":"Connections","icon":"🔌","desc":"Listening ports and connections by process","inputs":[],"admin":True},
 {"id":"proxy","label":"Proxy / VPN","icon":"🛡️","desc":"System proxy, environment variables, VPN and utun","inputs":[]},
 {"id":"fixdns","label":"Flush DNS","icon":"🧹","desc":"Clear the DNS cache and restart mDNSResponder","inputs":[],"admin":True},
 {"id":"report","label":"Export report","icon":"📄","desc":"Save a combined report to the Desktop","inputs":[]},
 {"id":"tools","label":"Tool check","icon":"🧰","desc":"Which system and third-party tools are installed","inputs":[]},
]
BY_ID = {c["id"]: c for c in COMMANDS}

# Simplified Chinese strings (the English text is the key). Used for server messages and sent to the page.
ZH = {
    "Quick check": "一键体检",
    "Gateway → public IP → DNS → HTTP, layer by layer, with a diagnosis": "网关 → 外网IP → DNS → HTTP 逐层检查并给出判读",
    "SSID, signal, noise, channel, rate": "SSID、信号、噪声、信道、速率",
    "DNS compare": "DNS 对比",
    "Answers and timings from the system and several public DNS servers": "系统与多家公共 DNS 的解析结果与耗时",
    "Domain": "域名",
    "HTTP timing": "HTTP 耗时",
    "DNS / TCP / TLS / first byte / total breakdown": "DNS/TCP/TLS/首字节/总耗时分解",
    "URL": "URL",
    "Ping": "Ping",
    "Packet loss and latency statistics": "丢包与延迟统计",
    "Host": "主机",
    "Count": "次数",
    "Route / path": "路由/路径",
    "Which interface/VPN is used + hop-by-hop mtr/traceroute": "走哪块网卡/VPN + mtr/traceroute 逐跳",
    "Port check": "端口检测",
    "Is the TCP port reachable": "TCP 端口是否可连",
    "Port": "端口",
    "TLS certificate": "TLS 证书",
    "Certificate, protocol, validity": "证书、协议、有效期",
    "MTU probe": "MTU 探测",
    "Path MTU; troubleshoot VPN / large-packet loss": "路径 MTU,排查 VPN/大包丢失",
    "Speed test": "测速",
    "networkQuality bandwidth and responsiveness (~20 s)": "networkQuality 带宽与响应性 (约 20 秒)",
    "Connections": "连接/监听",
    "Listening ports and connections by process": "按进程列出监听端口与连接",
    "Proxy / VPN": "代理/VPN",
    "System proxy, environment variables, VPN and utun": "系统代理、环境变量、VPN 与 utun",
    "Flush DNS": "刷新 DNS",
    "Clear the DNS cache and restart mDNSResponder": "清除 DNS 缓存并重启 mDNSResponder",
    "Export report": "导出报告",
    "Save a combined report to the Desktop": "保存综合报告到桌面",
    "Tool check": "工具检查",
    "Which system and third-party tools are installed": "系统与第三方工具安装情况",
    "Missing parameter": "缺少参数",
    "Invalid parameter": "参数不合法",
    "Unknown command": "未知命令",
    "Error": "错误",
    "(Waiting for the system administrator password prompt…)": "(等待系统弹出管理员密码框…)",
    "Failed to start": "启动失败",
    "[exit code %d]": "[退出码 %d]",
    "Quit": "退出",
    "Speed trend": "速度趋势",
    "Measures download and upload speed with networkQuality and charts the results over time.": "用 networkQuality 测下载和上传速度,并画出随时间的变化。",
    "Run speed test": "开始测速",
    "Testing… (about 20 s)": "测速中…(约 20 秒)",
    "Download": "下载",
    "Upload": "上传",
    "Latest": "最近",
    "Best": "最高",
    "No speed results yet": "还没有测速结果",
    "Could not read the speed results (macOS 12+ is required)": "无法读取测速结果(需要 macOS 12+)",
    "Command palette": "命令面板",
    "Search tools and pages…": "搜索工具和页面…",
    "Open speed trend": "打开速度趋势",
    "Auto-check": "自动体检",
    "Runs Diagnose on a schedule, keeps every result in History and alerts when the verdict changes.": "按计划自动运行“智能诊断”,每次结果存入历史记录,结论变化时提醒。",
    "Every": "每隔",
    "minutes": "分钟",
    "Run now": "立即运行",
    "Healthy": "正常",
    "Unstable": "不稳定",
    "Problem": "有问题",
    "Auto-check is running": "自动体检运行中",
    "No runs yet": "还没有运行记录",
    "View": "查看",
    "Network verdict: %s": "网络结论: %s",
    "Open Auto-check": "打开自动体检",
    "Report…": "报告…",
    "Markdown (.md)": "Markdown (.md)",
    "HTML (.html)": "HTML (.html)",
    "NetDoctor report": "NetDoctor 报告",
    "Generated": "生成时间",
    "Duration": "耗时",
    "Diagnose": "智能诊断",
    "Layer-by-layer checks with a verdict and suggested next steps": "逐层检查并给出结论和下一步建议",
    "TCP ping": "TCP 延迟",
    "TCP connect latency to a port — for when ping is blocked": "测量到某个端口的 TCP 连接延迟,适用于 ping 被屏蔽时",
    "IPv6 check": "IPv6 检测",
    "DHCP / IP address": "DHCP / IP 地址",
    "Check the DHCP lease and spot a self-assigned 169.254 address (DHCP failed)": "查看 DHCP 租约, 识别 169.254 自分配地址 (DHCP 失败)",
    "Compare IPv4 / IPv6 connectivity and spot a broken IPv6 path": "对比 IPv4 / IPv6 连通性,发现异常的 IPv6 链路",
    "Captive portal": "强制门户",
    "Wi-Fi connected but no web access? Detect a login page": "连上 Wi-Fi 却打不开网页?检测登录跳转页",
    "DNS benchmark": "DNS 测速",
    "Compare the system and public DNS servers by speed and get a recommendation": "对比系统与多家公共 DNS 的速度并给出推荐",
    "LAN scan": "局域网扫描",
    "Discover devices on the local network (IP, MAC, name)": "发现局域网设备 (IP、MAC、名称)",
    "Overview": "网络概览",
    "Interface, IP, gateway, DNS, Wi-Fi, proxy and public IP at a glance": "网卡、IP、网关、DNS、Wi-Fi、代理和公网 IP 一屏看全",
    "Multi-port check": "多端口检测",
    "Check common or custom ports on a host in parallel": "并行检测主机的常用或自定义端口",
    "Ports": "端口",
    "Watchlist": "监控列表",
    "Pings every favorite and alerts when one goes down.": "逐个 ping 收藏的主机,有主机掉线时提醒。",
    "Slow above (ms)": "慢于(毫秒)",
    "Notify": "桌面通知",
    "No verdict (is the NetDoctor server still running?)": "没有拿到结论(NetDoctor 服务还在运行吗?)",
    "Notifications are blocked by the browser": "浏览器已阻止通知",
    "Trend": "趋势",
    "Status": "状态",
    "Up": "正常",
    "Slow": "较慢",
    "Down": "离线",
    "Waiting…": "等待中…",
    "No favorites yet. Star hosts with ☆ in any tool, or add one here:": "还没有收藏。可在任意工具里点 ☆,或在这里添加:",
    "Add": "添加",
    "%s is down": "%s 离线",
    "%s is back up": "%s 已恢复",
    "Open Watchlist": "打开监控列表",
    "Copy as Markdown": "复制为 Markdown",
    "Copied as Markdown": "已复制为 Markdown",
    "Export": "导出",
    "Import": "导入",
    "Imported %s run(s), %s favorite(s)": "已导入 %s 条记录、%s 个收藏",
    "Import failed: invalid file": "导入失败:文件无效",
    "Compare": "对比",
    "Tick two runs to compare": "勾选两次运行进行对比",
    "Compare runs": "对比两次运行",
    "Older": "较早",
    "Newer": "较新",
    "Only changes": "仅显示差异",
    "Ignore numbers": "忽略数字",
    "+%s / −%s lines": "+%s / −%s 行",
    "No differences": "没有差异",
    "… %s unchanged lines …": "… %s 行未变 …",
    "(only the first 1500 lines are compared)": "(仅对比前 1500 行)",
    "Favorites": "收藏",
    "Add to favorites": "加入收藏",
    "Remove from favorites": "取消收藏",
    "Wi-Fi signal": "Wi-Fi 信号",
    "Signal": "信号",
    "Noise": "噪声",
    "SNR": "信噪比",
    "Channel": "信道",
    "Rate": "速率",
    "Reading Wi-Fi… (this can take 10+ seconds on some Macs)": "正在读取 Wi-Fi…(部分 Mac 需要十几秒)",
    "22,80,443 or 1-1024": "22,80,443 或 1-1024",
    "extra domain to include (optional)": "额外要测的域名(可选)",
    "Wi-Fi info unavailable": "无法获取 Wi-Fi 信息",
    "Reads the link every few seconds (macOS only). Rule of thumb: > −60 dBm good, −70 fair, < −75 poor.": "每隔几秒读取一次(仅 macOS)。经验值:> −60 dBm 好,−70 一般,< −75 差。",
    "Open Wi-Fi signal": "打开 Wi-Fi 信号",
    "Live latency": "实时延迟",
    "Pings once a second; red lines mark packet loss.": "每秒 ping 一次,红线表示丢包。",
    "Target": "目标",
    "Presets": "预设",
    "Start": "开始",
    "Clear": "清空",
    "Now": "当前",
    "Average": "平均",
    "Min / Max": "最小 / 最大",
    "Jitter": "抖动",
    "Loss": "丢包",
    "Open live latency": "打开实时延迟",
    "History": "历史记录",
    "Search…": "搜索…",
    "No history yet": "暂无历史记录",
    "No matches": "没有匹配项",
    "Clear all": "清空",
    "Clear all history?": "清空全部历史记录?",
    "Re-run": "重新运行",
    "Delete": "删除",
    "Done": "完成",
    "(output truncated)": "(输出已截断)",
    "Viewing history": "正在查看历史记录",
    "Show / hide history": "显示 / 隐藏历史记录",
    "Stored in this browser only (last 50 runs).": "仅保存在此浏览器中(最近 50 次)。",
    "Shortcuts": "快捷键",
    "Keyboard shortcuts": "键盘快捷键",
    "Close": "关闭",
    "Run the current tool": "运行当前工具",
    "Stop a running command; otherwise leave the input box": "停止正在运行的命令;否则退出输入框",
    "Previous / next tool": "上一个 / 下一个工具",
    "Jump to tool 1–9": "跳到第 1–9 个工具",
    "Focus the first input": "聚焦第一个输入框",
    "Run (when not typing)": "运行(不在输入时)",
    "Copy output": "复制输出",
    "Save output": "保存输出",
    "Switch language": "切换语言",
    "Switch theme": "切换主题",
    "Show / hide this help": "显示 / 隐藏此帮助",
    "Auto": "自动",
    "Light": "浅色",
    "Dark": "深色",
    "Copy": "复制",
    "Save": "保存",
    "Stop": "停止",
    "Run": "运行",
    "Running…": "运行中…",
    "Done in %ss": "完成,用时 %ss",
    "Stopped": "已停止",
    "Failed": "失败",
    "Copied": "已复制",
    "Quit the NetDoctor service?": "退出 NetDoctor 服务?",
    "Quit. You can close this page.": "已退出,可关闭此页面。",
    "Requires administrator rights": "需要管理员权限",
    "(fuller details)": "(信息更完整)",
    "Pick a tool on the left and click “Run”. Start with “Quick check”.": "选择左侧工具,点“运行”。建议先跑「一键体检」。",
    "NetDoctor Network Diagnostics": "NetDoctor 网络诊断",
}

def tr(lang, s):
    return ZH.get(s, s) if lang == "zh" else s

ARG_RE = re.compile(r"^[A-Za-z0-9._:/?&=%@~+,\[\]-]{1,300}$")

HOST_RE = re.compile(r"^[A-Za-z0-9._:-]{1,253}$")

def ping_once(host):
    """One ping; returns round-trip time in ms, or None on loss/timeout/missing ping."""
    flags = ["-c", "1", "-t", "2"] if sys.platform == "darwin" else ["-c", "1", "-W", "2"]
    try:
        out = subprocess.run(["ping"] + flags + [host], stdin=subprocess.DEVNULL, capture_output=True,
                             text=True, timeout=4).stdout
    except Exception:
        return None
    m = re.search(r"time[=<]([0-9.]+)", out)
    return float(m.group(1)) if m else None

def wifi_info():
    """Current Wi-Fi link info via system_profiler (macOS, no sudo). Returns a dict or {"error": ...}."""
    try:
        out = subprocess.run([os.environ.get("NETDOCTOR_SYSTEM_PROFILER", "system_profiler"), "SPAirPortDataType"],
                             stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return {"error": "unavailable"}
    m = re.search(r"Current Network Information:\s*\n(.*?)(?:\n\s*Other Local Wi-Fi Networks:|\Z)", out, re.S)
    if not m:
        return {"error": "not connected"}
    blk = m.group(1)
    sn = re.search(r"Signal / Noise:\s*(-?\d+) dBm / (-?\d+) dBm", blk)
    if not sn:
        return {"error": "no signal info"}
    def field(name):
        mm = re.search(name + r":\s*(.+)", blk)
        return mm.group(1).strip()[:60] if mm else ""
    first = blk.strip().splitlines()[0].strip().rstrip(":") if blk.strip() else ""
    return {"rssi": int(sn.group(1)), "noise": int(sn.group(2)), "channel": field("Channel"),
            "rate": field("Transmit Rate"), "phy": field("PHY Mode"),
            "ssid": "" if "redacted" in first.lower() else first[:60]}  # macOS hides the SSID without Location permission

def build_args(spec, values, lang="en"):
    args = []
    for i in spec["inputs"]:
        v = (values.get(i["name"]) or i.get("def") or "").strip()
        if not v:
            if i.get("req"):
                raise ValueError(tr(lang, "Missing parameter") + ": " + tr(lang, i["label"]))
            break  # positional args: stop at the first empty one
        if v.startswith("-") or not ARG_RE.match(v):
            raise ValueError(tr(lang, "Invalid parameter") + ": " + tr(lang, i["label"]))
        args.append(v)
    return args

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass

    def _ok_host(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("127.0.0.1", "localhost")

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        if not self._ok_host(): return self._send(403, "forbidden")
        if self.path.split("?")[0] == "/":
            page = (HTML.replace("__TOKEN__", TOKEN).replace("__CMDS__", json.dumps(COMMANDS, ensure_ascii=False))
                    .replace("__ZH__", json.dumps(ZH, ensure_ascii=False)))
            return self._send(200, page)
        if self.path.split("?")[0] == "/icon.svg":
            for cand in (os.path.join(HERE, "assets", "icon.svg"), os.path.join(HERE, "icon.svg")):
                if os.path.isfile(cand):
                    with open(cand, "rb") as fh:
                        return self._send(200, fh.read(), "image/svg+xml")
        self._send(404, "not found")

    def do_POST(self):
        if not self._ok_host() or self.headers.get("X-Token") != TOKEN:
            return self._send(403, "forbidden")
        if self.path == "/quit":
            self._send(200, "bye"); threading.Thread(target=self.server.shutdown, daemon=True).start(); return
        if self.path == "/wifi":
            return self._send(200, json.dumps(wifi_info()), "application/json")
        if self.path == "/ping":
            try:
                n = min(int(self.headers.get("Content-Length") or 0), 65536)
                host = str((json.loads(self.rfile.read(n) or b"{}")).get("host") or "").strip()
            except Exception:
                host = ""
            if not HOST_RE.match(host) or host.startswith("-"):
                return self._send(400, json.dumps({"error": "invalid host"}), "application/json")
            return self._send(200, json.dumps({"ms": ping_once(host)}), "application/json")
        if self.path != "/run": return self._send(404, "not found")
        lang = "en"
        try:
            n = min(int(self.headers.get("Content-Length") or 0), 65536)
            req = json.loads(self.rfile.read(n) or b"{}")
            lang = "zh" if req.get("lang") == "zh" else "en"
            spec = BY_ID.get(req.get("cmd"))
            if not spec: raise ValueError(tr(lang, "Unknown command"))
            args = build_args(spec, req.get("values") or {}, lang)
            admin = spec.get("admin")
            use_admin = admin is True or (admin == "optional" and req.get("admin"))
        except Exception as e:
            return self._send(400, "%s: %s\n" % (tr(lang, "Error"), e), "text/plain; charset=utf-8")

        env = dict(os.environ, NETDOCTOR_COLOR="1", NETDOCTOR_LANG=lang, LANG="en_US.UTF-8")
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:" + env.get("PATH", "")
        self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store"); self.end_headers()
        if use_admin and sys.platform == "darwin":
            inner = "HOME=%s PATH=%s NETDOCTOR_COLOR=1 NETDOCTOR_LANG=%s %s 2>&1" % (
                shlex.quote(os.path.expanduser("~")), shlex.quote(env["PATH"]), lang,
                " ".join(shlex.quote(x) for x in ["/bin/bash", NETDOCTOR, spec["id"]] + args))
            inner = inner.replace("\\", "\\\\").replace('"', '\\"')
            cmd = ["osascript", "-e", 'do shell script "%s" with administrator privileges without altering line endings' % inner]
            self.wfile.write((tr(lang, "(Waiting for the system administrator password prompt…)") + "\n").encode()); self.wfile.flush()
        else:
            cmd = ["/bin/bash", NETDOCTOR, spec["id"]] + args
        try:
            # 独立进程组: 点"停止"时可以连同脚本启动的 ping/perl/nc 等子进程一起结束
            p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=env, bufsize=0, start_new_session=True)
        except Exception as e:
            self.wfile.write(("%s: %s\n" % (tr(lang, "Failed to start"), e)).encode()); return
        def kill_group():
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try: os.killpg(p.pid, sig)
                except (ProcessLookupError, PermissionError, OSError): break
                try: p.wait(timeout=1); break
                except subprocess.TimeoutExpired: pass
        gone = False
        try:
            fd = p.stdout.fileno()
            while True:
                r, _, _ = select.select([fd, self.connection], [], [], 1.0)
                if self.connection in r:  # 浏览器断开 (点了停止/关了页面) -> 结束子进程
                    try:
                        if not self.connection.recv(1, socket.MSG_PEEK): gone = True; break
                    except OSError: gone = True; break
                if fd in r:
                    chunk = os.read(fd, 4096)
                    if not chunk: break
                    self.wfile.write(chunk); self.wfile.flush()
            if gone: kill_group()
            rc = p.wait()
            self.wfile.write(("\n\x1b[2m%s\x1b[0m\n" % (tr(lang, "[exit code %d]") % rc)).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass  # user clicked Stop
        finally:
            if p.poll() is None:
                kill_group()
            try: p.stdout.close()
            except OSError: pass

HTML = r"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NetDoctor Network Diagnostics</title><link rel="icon" type="image/svg+xml" href="/icon.svg"><style>
:root{--bg:#f5f5f7;--card:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#e0e0e5;--acc:#0071e3;--term:#14161a;--termfg:#d8dde6}
:root{color-scheme:light}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){color-scheme:dark;--bg:#1c1c1e;--card:#2c2c2e;--fg:#f5f5f7;--mut:#98989d;--line:#3a3a3c;--acc:#0a84ff;--term:#0b0c0e}}
:root[data-theme=dark]{color-scheme:dark;--bg:#1c1c1e;--card:#2c2c2e;--fg:#f5f5f7;--mut:#98989d;--line:#3a3a3c;--acc:#0a84ff;--term:#0b0c0e}
*{box-sizing:border-box}body{margin:0;font:14px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:var(--bg);color:var(--fg);display:flex;height:100vh}
nav{width:210px;background:var(--card);border-right:1px solid var(--line);overflow:auto;padding:12px 8px;flex:none}
nav h1{font-size:15px;margin:4px 10px 12px}nav button{display:flex;gap:8px;width:100%;text-align:left;border:0;background:none;color:var(--fg);padding:8px 10px;border-radius:8px;font:inherit;cursor:pointer}
nav button:hover{background:var(--bg)}nav button.on{background:var(--acc);color:#fff}
main{flex:1;display:flex;flex-direction:column;padding:18px;min-width:0;gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px}
.card h2{margin:0 0 2px;font-size:17px}.card p{margin:0 0 10px;color:var(--mut)}
form{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end}label{display:flex;flex-direction:column;gap:3px;font-size:12px;color:var(--mut)}
input[type=text]{padding:7px 9px;border:1px solid var(--line);border-radius:7px;background:var(--bg);color:var(--fg);font:inherit;min-width:200px}
.btn{padding:8px 16px;border:0;border-radius:8px;background:var(--acc);color:#fff;font:inherit;cursor:pointer}.btn.sec{background:var(--bg);color:var(--fg);border:1px solid var(--line)}.btn:disabled{opacity:.4}
.chk{flex-direction:row;align-items:center;gap:6px;color:var(--fg)}
#out{flex:1;min-height:0;background:var(--term);color:var(--termfg);border-radius:12px;padding:14px;overflow:auto;white-space:pre-wrap;word-break:break-all;font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;margin:0}
.b{font-weight:700}.g{color:#32d74b}.r{color:#ff453a}.y{color:#ffd60a}.d{opacity:.55}
.bar{display:flex;gap:8px;align-items:center}.sp{flex:1}
main.mon>:not(#mon){display:none}main:not(.mon)>#mon{display:none}
main.wf>:not(#wf){display:none}main:not(.wf)>#wf{display:none}
main.wl>:not(#wl){display:none}main:not(.wl)>#wl{display:none}
main.ac>:not(#ac){display:none}main:not(.ac)>#ac{display:none}
main.sp>:not(#sp){display:none}main:not(.sp)>#sp{display:none}
#sp{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}#sp .row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
#sp .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px}
#sp .stat{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:8px 12px}#sp .stat small{display:block;color:var(--mut);font-size:11px}#sp .stat b{font:600 17px ui-monospace,Menlo,monospace}
#spchart{width:100%;flex:1;min-height:220px;background:var(--card);border:1px solid var(--line);border-radius:12px}
#pal{position:fixed;inset:0;background:rgba(0,0,0,.45);display:none;align-items:flex-start;justify-content:center;z-index:11;padding-top:13vh}#pal.on{display:flex}
#pal .box{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:14px;width:min(560px,calc(100% - 24px));overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.4)}
#palq{width:100%;border:0;border-bottom:1px solid var(--line);background:transparent;color:var(--fg);font:inherit;font-size:16px;padding:14px 16px;outline:none;margin:0;min-width:0}
#pall{max-height:52vh;overflow:auto;padding:6px}.pi{display:flex;gap:10px;align-items:center;padding:8px 10px;border-radius:9px;cursor:pointer}.pi.sel{background:var(--acc);color:#fff}.pi .d{opacity:.65;font-size:12px;margin-left:auto;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:55%}
#ac{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}#ac .row{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap}
#ac select,#hrep{padding:7px 9px;border:1px solid var(--line);border-radius:7px;background:var(--bg);color:var(--fg);font:inherit}
#hrep{padding:4px 8px;font-size:12px}
#aclog{flex:1;min-height:0;overflow:auto;background:var(--card);border:1px solid var(--line);border-radius:12px}
.al{display:flex;gap:10px;align-items:center;padding:9px 14px;border-bottom:1px solid var(--line);font-size:13px}.al .tm{color:var(--mut);font-family:ui-monospace,Menlo,monospace;font-size:12px;white-space:nowrap}.al .tx{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.al button{border:1px solid var(--line);background:var(--bg);color:var(--fg);border-radius:6px;font:inherit;font-size:11px;padding:2px 8px;cursor:pointer}
#wl{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}#wl .row{display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap}
#wl input[type=number]{width:90px;min-width:0}#wl .tbl{flex:1;min-height:0;overflow:auto;background:var(--card);border:1px solid var(--line);border-radius:12px}
#wl table{width:100%;border-collapse:collapse}#wl th{position:sticky;top:0;background:var(--card);text-align:left;font-size:11px;color:var(--mut);padding:8px 12px;border-bottom:1px solid var(--line)}
#wl td{padding:8px 12px;border-bottom:1px solid var(--line);font-size:13px}#wl td.h{font-weight:600;word-break:break-all}#wl td.n{font-family:ui-monospace,Menlo,monospace}
#wl .rm{border:0;background:none;color:var(--mut);cursor:pointer;font-size:15px}#wl .rm:hover{color:#d1342a}
.st{font-size:11px;border-radius:99px;padding:1px 9px;color:#fff;white-space:nowrap}.st.up{background:#2fa84f}.st.slow{background:#c98a00}.st.down{background:#d1342a}.st.wait{background:#8b93a1}
#wl svg{display:block}#wl .empty{padding:18px;color:var(--mut)}
#wf{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}#wf .row{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap}
#wf .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:10px}
#wf .stat{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:8px 12px}#wf .stat small{display:block;color:var(--mut);font-size:11px}#wf .stat b{font:600 16px ui-monospace,Menlo,monospace}
#wchart{width:100%;flex:1;min-height:220px;background:var(--card);border:1px solid var(--line);border-radius:12px}
.fw{display:flex;gap:4px}.star{border:1px solid var(--line);background:var(--bg);color:var(--fg);border-radius:7px;cursor:pointer;font-size:14px;padding:0 8px}.star.on{color:#e6a700}
.chips{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:10px}.chips:empty{display:none}.chips small{color:var(--mut);font-size:11px}
.chip{display:inline-flex;align-items:center;gap:4px;border:1px solid var(--line);background:var(--bg);border-radius:99px;padding:2px 4px 2px 10px;font-size:12px;cursor:pointer}.chip:hover{border-color:var(--acc)}
.chip i{font-style:normal;color:var(--mut);padding:0 5px;border-radius:99px}.chip i:hover{background:var(--line);color:var(--fg)}
.hbar{display:flex;gap:6px;padding:0 14px 6px;flex-wrap:wrap}.hbar .btn{padding:4px 10px;font-size:12px}
.hi .hc{margin-top:3px}
#cmp{position:fixed;inset:0;background:rgba(0,0,0,.5);display:none;align-items:center;justify-content:center;z-index:10}#cmp.on{display:flex}
#cmp .box{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:14px;padding:16px 18px;width:min(980px,calc(100% - 24px));height:min(86vh,800px);display:flex;flex-direction:column;gap:10px}
#cmp h3{margin:0;font-size:16px}#cmpmeta{display:grid;grid-template-columns:1fr 1fr;gap:8px;font-size:12px}#cmpmeta div{background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:6px 10px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#cmp .row{display:flex;gap:14px;align-items:center;flex-wrap:wrap}#cmpout{flex:1;min-height:0;overflow:auto;background:var(--term);color:var(--termfg);border-radius:10px;padding:8px 0;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;margin:0}
.dl{padding:0 10px;white-space:pre-wrap;word-break:break-all}.dl.add{background:rgba(47,168,79,.22)}.dl.del{background:rgba(209,52,42,.25)}.dl.gap{color:#8b93a1;text-align:center}
#mon{display:flex;flex-direction:column;gap:12px;flex:1;min-height:0}
#mon .row{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap}
#mon .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:10px}
#mon .stat{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:8px 12px}
#mon .stat small{display:block;color:var(--mut);font-size:11px}#mon .stat b{font:600 18px ui-monospace,Menlo,monospace}
#mchart{width:100%;flex:1;min-height:220px;background:var(--card);border:1px solid var(--line);border-radius:12px}
kbd{font:12px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--bg);border:1px solid var(--line);border-bottom-width:2px;border-radius:5px;padding:1px 6px;margin-right:3px;white-space:nowrap}
#help{position:fixed;inset:0;background:rgba(0,0,0,.45);display:none;align-items:center;justify-content:center;z-index:9}
#hist{position:fixed;top:0;right:0;bottom:0;width:min(400px,100%);background:var(--card);color:var(--fg);border-left:1px solid var(--line);box-shadow:-8px 0 24px rgba(0,0,0,.25);display:none;flex-direction:column;z-index:8}
#hist.on{display:flex}#hist header{display:flex;gap:8px;align-items:center;padding:12px 14px;border-bottom:1px solid var(--line)}#hist header h3{margin:0;font-size:16px;flex:1}
#hist input{margin:10px 14px 4px;min-width:0}#hist .note{margin:0 14px 6px;font-size:11px;color:var(--mut)}
#hlist{flex:1;overflow:auto;padding:4px 8px 12px}
.hi{display:flex;gap:8px;align-items:flex-start;padding:8px 8px;border-radius:9px;cursor:pointer}.hi:hover{background:var(--bg)}.hi.sel{outline:2px solid var(--acc)}
.hi .m{flex:1;min-width:0}.hi .n{font-weight:600}.hi .a{color:var(--mut);font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.hi .w{color:var(--mut);font-size:11px}
.hi .x{display:flex;flex-direction:column;gap:4px}.hi .x button{border:1px solid var(--line);background:var(--bg);color:var(--fg);border-radius:6px;font:inherit;font-size:11px;padding:2px 7px;cursor:pointer}
.bd{font-size:11px;border-radius:99px;padding:0 7px;margin-left:6px;color:#fff;white-space:nowrap}.bd.ok{background:#2fa84f}.bd.stopped{background:#b58105}.bd.failed{background:#d1342a}
#help.on{display:flex}#help .box{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:14px;padding:18px 22px;max-width:520px;width:calc(100% - 32px);max-height:85vh;overflow:auto}
#help h3{margin:0 0 10px;font-size:16px}#help table{width:100%;border-collapse:collapse}#help td{padding:5px 0;vertical-align:top}#help td:first-child{width:46%}
/* 窄屏 (手机宽度 / 半屏窗口): 侧边栏改为顶部可横向滑动的工具条 */
@media(max-width:720px){
body{flex-direction:column;height:auto;min-height:100vh}
nav{width:auto;border-right:0;border-bottom:1px solid var(--line);display:flex;flex-wrap:nowrap;align-items:center;gap:4px;overflow-x:auto;overflow-y:hidden;padding:8px;position:sticky;top:0;z-index:5}
nav h1{display:none}#list{display:contents}
nav button{width:auto;flex:none;white-space:nowrap;margin-top:0!important}
main{padding:12px;min-height:calc(100vh - 56px)}
#out{min-height:260px}
.bar{flex-wrap:wrap}
input[type=text]{min-width:0;width:100%}
form{align-items:stretch}
}
</style><script>try{var th=localStorage.getItem('nd_theme');if(th==='light'||th==='dark')document.documentElement.dataset.theme=th}catch(e){}</script></head><body>
<nav><h1>🛰️ NetDoctor</h1><div id="list"></div><button onclick="toggleHist()" id="histbtn" style="margin-top:14px;color:var(--mut)">🕘 <span data-i="History">History</span></button><button onclick="toggleHelp()" id="helpbtn" style="color:var(--mut)">⌨ <span data-i="Shortcuts">Shortcuts</span></button><button onclick="toggleTheme()" id="theme" style="color:var(--mut)"></button><button onclick="toggleLang()" id="lang" style="color:var(--mut)"></button><button onclick="quit()" style="color:var(--mut)">⏻ <span data-i="Quit">Quit</span></button></nav>
<main><div class="card"><h2 id="t"></h2><p id="d"></p><form id="f"></form><div id="favs" class="chips"></div></div>
<datalist id="favlist"></datalist>
<div class="bar"><span class="sp" id="st" style="color:var(--mut)"></span><button class="btn sec" onclick="copy()" data-i="Copy">Copy</button><button class="btn sec" id="mdbtn" onclick="copyMd()" data-i="Copy as Markdown">Copy as Markdown</button><button class="btn sec" onclick="save()" data-i="Save">Save</button><button class="btn sec" id="stop" onclick="stop()" data-i="Stop" disabled>Stop</button></div>
<pre id="out"></pre>
<section id="mon"><div class="card"><h2>📈 <span data-i="Live latency">Live latency</span></h2><p data-i="Pings once a second; red lines mark packet loss.">Pings once a second; red lines mark packet loss.</p>
<div class="row"><label><span data-i="Target">Target</span><span class="fw"><input type="text" id="mhost" value="1.1.1.1" list="mpre" spellcheck="false" oninput="renderFavs()"><button type="button" class="star" id="mstar" onclick="toggleFav($('#mhost').value)">☆</button></span><datalist id="mpre"></datalist></label>
<button class="btn" id="mgo" onclick="monToggle()" data-i="Start">Start</button><button class="btn sec" onclick="monClear()" data-i="Clear">Clear</button></div></div>
<div class="stats"><div class="stat"><small data-i="Now">Now</small><b id="s_now">—</b></div><div class="stat"><small data-i="Average">Average</small><b id="s_avg">—</b></div><div class="stat"><small data-i="Min / Max">Min / Max</small><b id="s_mm">—</b></div><div class="stat"><small data-i="Jitter">Jitter</small><b id="s_jit">—</b></div><div class="stat"><small data-i="Loss">Loss</small><b id="s_loss">—</b></div></div>
<div id="mfavs" class="chips"></div>
<canvas id="mchart"></canvas></section>
<section id="wf"><div class="card"><h2>📶 <span data-i="Wi-Fi signal">Wi-Fi signal</span></h2><p data-i="Reads the link every few seconds (macOS only). Rule of thumb: > −60 dBm good, −70 fair, < −75 poor.">Reads the link every few seconds (macOS only). Rule of thumb: > −60 dBm good, −70 fair, < −75 poor.</p>
<div class="row"><button class="btn" id="wgo" onclick="wfToggle()" data-i="Start">Start</button><button class="btn sec" onclick="wfClear()" data-i="Clear">Clear</button><span id="wmsg" style="color:var(--mut);font-size:12px"></span></div></div>
<div class="stats"><div class="stat"><small data-i="Signal">Signal</small><b id="w_rssi">—</b></div><div class="stat"><small data-i="Noise">Noise</small><b id="w_noise">—</b></div><div class="stat"><small data-i="SNR">SNR</small><b id="w_snr">—</b></div><div class="stat"><small data-i="Channel">Channel</small><b id="w_ch">—</b></div><div class="stat"><small data-i="Rate">Rate</small><b id="w_rate">—</b></div></div>
<canvas id="wchart"></canvas></section>
<section id="wl"><div class="card"><h2>📋 <span data-i="Watchlist">Watchlist</span></h2><p data-i="Pings every favorite and alerts when one goes down.">Pings every favorite and alerts when one goes down.</p>
<div class="row"><button class="btn" id="wlgo" onclick="wlToggle()" data-i="Start">Start</button>
<label><span data-i="Slow above (ms)">Slow above (ms)</span><input type="number" id="wlslow" value="150" min="1" max="5000"></label>
<label class="chk"><input type="checkbox" id="wlnote" onchange="wlNotify(this)"><span data-i="Notify">Notify</span></label>
<span class="fw"><input type="text" id="wladd" placeholder="example.com" spellcheck="false" onkeydown="if(event.key==='Enter'){event.preventDefault();wlAdd()}"><button class="btn sec" id="wladdbtn" onclick="wlAdd()" data-i="Add">Add</button></span><span id="wlmsg" style="color:var(--mut);font-size:12px"></span></div></div>
<div class="tbl" id="wltbl"></div></section>
<section id="sp"><div class="card"><h2>📉 <span data-i="Speed trend">Speed trend</span></h2><p data-i="Measures download and upload speed with networkQuality and charts the results over time.">Measures download and upload speed with networkQuality and charts the results over time.</p>
<div class="row"><button class="btn" id="spgo" onclick="spRun()" data-i="Run speed test">Run speed test</button><span id="spmsg" style="color:var(--mut);font-size:12px"></span></div></div>
<div class="stats"><div class="stat"><small data-i="Download">Download</small><b id="sp_dl">—</b></div><div class="stat"><small data-i="Upload">Upload</small><b id="sp_ul">—</b></div><div class="stat"><small><span data-i="Average">Average</span> ↓</small><b id="sp_avg">—</b></div><div class="stat"><small><span data-i="Best">Best</span> ↓</small><b id="sp_best">—</b></div></div>
<canvas id="spchart"></canvas></section>
<section id="ac"><div class="card"><h2>🔁 <span data-i="Auto-check">Auto-check</span></h2><p data-i="Runs Diagnose on a schedule, keeps every result in History and alerts when the verdict changes.">Runs Diagnose on a schedule, keeps every result in History and alerts when the verdict changes.</p>
<div class="row"><button class="btn" id="acgo" onclick="acToggle()" data-i="Start">Start</button><button class="btn sec" id="acnow" onclick="acTick()" data-i="Run now">Run now</button>
<label><span data-i="Every">Every</span><span class="fw"><select id="acint" onchange="acInterval(this.value)"><option value="1">1</option><option value="5" selected>5</option><option value="15">15</option><option value="30">30</option><option value="60">60</option></select><span data-i="minutes" style="align-self:center">minutes</span></span></label>
<label class="chk"><input type="checkbox" id="acnote" onchange="acNotifyChange(this)"><span data-i="Notify">Notify</span></label><span id="acmsg" style="color:var(--mut);font-size:12px"></span></div></div>
<div id="aclog"></div></section></main>
<aside id="hist"><header><h3>🕘 <span data-i="History">History</span></h3><button class="btn sec" onclick="clearHist()" data-i="Clear all">Clear all</button><button class="btn sec" onclick="toggleHist(false)" data-i="Close">Close</button></header>
<div class="hbar"><button class="btn sec" onclick="exportHist()" data-i="Export">Export</button><button class="btn sec" onclick="$('#hfile').click()" data-i="Import">Import</button><button class="btn" id="cmpbtn" onclick="cmpOpen()" data-i="Compare" disabled>Compare</button><select id="hrep" onchange="makeReport(this.value);this.value=''"><option value="" data-i="Report…">Report…</option><option value="md" data-i="Markdown (.md)">Markdown (.md)</option><option value="html" data-i="HTML (.html)">HTML (.html)</option></select><input type="file" id="hfile" accept="application/json,.json" style="display:none" onchange="importHist(this)"></div>
<input type="text" id="hq" oninput="renderHist()"><p class="note" data-i="Stored in this browser only (last 50 runs).">Stored in this browser only (last 50 runs).</p><div id="hlist"></div></aside>
<div id="cmp" onclick="if(event.target===this)cmpClose()"><div class="box"><h3>⇄ <span data-i="Compare runs">Compare runs</span></h3><div id="cmpmeta"></div>
<div class="row"><label class="chk"><input type="checkbox" id="cmpchg" checked onchange="cmpRender()"><span data-i="Only changes">Only changes</span></label><label class="chk"><input type="checkbox" id="cmpnum" checked onchange="cmpRender()"><span data-i="Ignore numbers">Ignore numbers</span></label><span id="cmpsum" class="sp"></span><button class="btn sec" onclick="cmpClose()" data-i="Close">Close</button></div><div id="cmpout"></div></div></div>
<div id="pal" onclick="if(event.target===this)palClose()"><div class="box"><input type="text" id="palq" autocomplete="off" spellcheck="false" oninput="palSel=0;renderPal()"><div id="pall"></div></div></div>
<div id="help" onclick="if(event.target===this)toggleHelp(false)"><div class="box"><h3 id="helph"></h3><table id="helpt"></table><p style="margin:12px 0 0;text-align:right"><button class="btn sec" onclick="toggleHelp(false)" data-i="Close">Close</button></p></div></div>
<script>
const TOKEN="__TOKEN__",CMDS=__CMDS__,ZH=__ZH__;let cur=null,ctl=null,raw="",idle=true,lang="en";
const $=s=>document.querySelector(s);
try{lang=localStorage.getItem('nd_lang')||(/^zh/i.test(navigator.language)?'zh':'en')}catch(e){lang=/^zh/i.test(navigator.language)?'zh':'en'}
const t=s=>lang=='zh'&&ZH[s]?ZH[s]:s;
const fmt=(k,v)=>t(k).replace('%s',v);
let theme='auto';try{const v=localStorage.getItem('nd_theme');if(v==='light'||v==='dark')theme=v}catch(e){}
const THEMES={auto:'🖥 Auto',light:'☀️ Light',dark:'🌙 Dark'};
function applyTheme(){const r=document.documentElement;if(theme=='auto')delete r.dataset.theme;else r.dataset.theme=theme;const [i,n]=THEMES[theme].split(' ');$('#theme').textContent=i+' '+t(n)}
function toggleTheme(){theme={auto:'light',light:'dark',dark:'auto'}[theme];try{theme=='auto'?localStorage.removeItem('nd_theme'):localStorage.setItem('nd_theme',theme)}catch(e){}applyTheme()}
const INTRO='Pick a tool on the left and click “Run”. Start with “Quick check”.';
CMDS.forEach(c=>{const b=document.createElement('button');b.innerHTML=`<span>${c.icon}</span><span class="nl"></span>`;b.onclick=()=>pick(c.id);b.id='b_'+c.id;$('#list').append(b)});
{const b=document.createElement('button');b.id='b_mon';b.innerHTML='<span>📈</span><span class="nl"></span>';b.onclick=showMon;$('#list').append(b)}
{const b=document.createElement('button');b.id='b_wf';b.innerHTML='<span>📶</span><span class="nl"></span>';b.onclick=showWf;$('#list').append(b)}
{const b=document.createElement('button');b.id='b_sp';b.innerHTML='<span>📉</span><span class="nl"></span>';b.onclick=showSp;$('#list').append(b)}
{const b=document.createElement('button');b.id='b_ac';b.innerHTML='<span>🔁</span><span class="nl"></span>';b.onclick=showAc;$('#list').append(b)}
{const b=document.createElement('button');b.id='b_wl';b.innerHTML='<span>📋</span><span class="nl"></span>';b.onclick=showWl;$('#list').append(b)}
const MAXS=120;let msamples=[],mtimer=null,mbusy=false;
function leaveViews(){monStop();wfStop();wlStop();const m=document.querySelector('main');m.classList.remove('sp');m.classList.remove('mon');m.classList.remove('wf');m.classList.remove('wl');m.classList.remove('ac')}
function showMon(){leaveViews();const m=document.querySelector('main');m.classList.add('mon');document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_mon'));cur=null;drawMon();renderFavs()}
function monToggle(){if(mtimer){monStop()}else{monStart()}}
function monStart(){if(mtimer)return;$('#mgo').textContent=t('Stop');mtimer=setInterval(monTick,1000);monTick()}
function monStop(){if(mtimer){clearInterval(mtimer);mtimer=null}$('#mgo').textContent=t('Start')}
function monClear(){msamples=[];drawMon()}
async function monTick(){if(mbusy)return;mbusy=true;const host=$('#mhost').value.trim();
let v=null;try{const r=await fetch('/ping',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({host})});if(!r.ok){monStop();mbusy=false;return}v=(await r.json()).ms}catch(e){}
mbusy=false;if(!mtimer)return;msamples.push(v);if(msamples.length>MAXS)msamples.shift();drawMon()}
function drawMon(){const vals=msamples.filter(x=>x!==null),n=msamples.length;
const f=(x,d)=>x===undefined||x===null||!isFinite(x)?'—':x.toFixed(d)+' ms';
const avg=vals.length?vals.reduce((a,b)=>a+b,0)/vals.length:null;let jit=null;if(vals.length>1){let d=0;for(let i=1;i<vals.length;i++)d+=Math.abs(vals[i]-vals[i-1]);jit=d/(vals.length-1)}
const last=n?msamples[n-1]:undefined;$('#s_now').textContent=n?(last===null?t('Loss'):f(last,0)):'—';$('#s_avg').textContent=f(avg,1);
$('#s_mm').textContent=vals.length?Math.min(...vals).toFixed(0)+' / '+Math.max(...vals).toFixed(0)+' ms':'—';$('#s_jit').textContent=f(jit,1);
$('#s_loss').textContent=n?((n-vals.length)/n*100).toFixed(1)+'%':'—';$('#s_loss').style.color=n&&vals.length<n?'#d1342a':'';
const cv=$('#mchart');if(!cv.clientWidth)return;const dpr=window.devicePixelRatio||1,w=cv.clientWidth,h=cv.clientHeight;cv.width=w*dpr;cv.height=h*dpr;
const g=cv.getContext('2d');g.scale(dpr,dpr);const cs=getComputedStyle(document.documentElement),mut=cs.getPropertyValue('--mut').trim(),line=cs.getPropertyValue('--line').trim(),acc=cs.getPropertyValue('--acc').trim();
const L=46,B=8,T=10,R=10,pw=w-L-R,ph=h-T-B,top=Math.max(10,...vals)*1.15;
g.font='11px ui-monospace,Menlo,monospace';g.fillStyle=mut;g.strokeStyle=line;g.lineWidth=1;
for(let i=0;i<=4;i++){const y=T+ph-ph*i/4;g.beginPath();g.moveTo(L,y);g.lineTo(w-R,y);g.stroke();g.fillText((top*i/4).toFixed(0),6,y+4)}
const X=i=>L+pw-(n-1-i)*pw/(MAXS-1);
g.strokeStyle='rgba(209,52,42,.7)';msamples.forEach((v,i)=>{if(v===null){g.beginPath();g.moveTo(X(i),T);g.lineTo(X(i),T+ph);g.stroke()}});
g.strokeStyle=acc;g.lineWidth=2;g.lineJoin='round';g.beginPath();let pen=false;
msamples.forEach((v,i)=>{if(v===null){pen=false;return}const y=T+ph-ph*v/top;if(pen)g.lineTo(X(i),y);else{g.moveTo(X(i),y);pen=true}});g.stroke()}
/* ---- watchlist: ping every favorite, alert on down/up transitions ---- */
const WLN=60;let wlrun=false,wlto=null,wlst={},wlLoop=0;const BASE_TITLE=()=>t('NetDoctor Network Diagnostics');
function showWl(){leaveViews();document.querySelector('main').classList.add('wl');document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_wl'));cur=null;renderWl()}
function wlToggle(){wlrun?wlStop():wlStart()}
function wlStart(){if(wlrun||!favs.length)return;wlrun=true;wlst={};$('#wlgo').textContent=t('Stop');wlTick(++wlLoop)}
function wlStop(){wlrun=false;wlLoop++;clearTimeout(wlto);const b=$('#wlgo');if(b)b.textContent=t('Start');document.title=BASE_TITLE()}
function wlStatus(h){const x=wlst[h];if(!x||!x.s.length)return 'wait';const s=x.s,n=s.length;if(n>=3&&s[n-1]===null&&s[n-2]===null&&s[n-3]===null)return 'down';
const last=s[n-1];if(last===null){if(!s.some(a=>a!==null))return 'wait';return x.prev=='down'?'down':'up'}return last>(+$('#wlslow').value||150)?'slow':'up'}
function wlNote(msg){if($('#wlnote').checked&&'Notification' in window&&Notification.permission=='granted'){try{new Notification('NetDoctor',{body:msg})}catch(e){}}}
async function wlOne(h){let v=null;try{const r=await fetch('/ping',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({host:h})});if(r.ok)v=(await r.json()).ms}catch(e){}return v}
async function wlTick(id){if(!wlrun||id!=wlLoop)return;const hosts=[...favs];
for(let i=0;i<hosts.length;i+=6){const chunk=hosts.slice(i,i+6);const res=await Promise.all(chunk.map(wlOne));if(!wlrun||id!=wlLoop)return;
chunk.forEach((h,k)=>{const x=wlst[h]||(wlst[h]={s:[],prev:'wait'});x.s.push(res[k]);if(x.s.length>WLN)x.s.shift();const st=wlStatus(h);
if(st=='down'&&x.prev!='down')wlNote(t('%s is down').replace('%s',h));else if(x.prev=='down'&&st!='down')wlNote(t('%s is back up').replace('%s',h));x.prev=st})}
const down=hosts.filter(h=>wlst[h]&&wlst[h].prev=='down').length;document.title=(down?'⚠ '+down+' · ':'')+BASE_TITLE();renderWl();wlto=setTimeout(()=>wlTick(id),1000)}
async function wlNotify(cb){if(!cb.checked)return;if(!('Notification' in window)){cb.checked=false;return}
if(Notification.permission=='default'){try{await Notification.requestPermission()}catch(e){}}
if(Notification.permission!='granted'){cb.checked=false;$('#wlmsg').textContent=t('Notifications are blocked by the browser')}else $('#wlmsg').textContent=''}
function spark(s){const v=s.filter(x=>x!==null);if(!v.length)return '';const W=110,H=22,mx=Math.max(...v,10),n=s.length;let d='',pen=false;
s.forEach((x,i)=>{if(x===null){pen=false;return}const px=(i/(WLN-1))*W+(W-(n-1)/(WLN-1)*W),py=H-2-(H-4)*x/mx;d+=(pen?'L':'M')+px.toFixed(1)+' '+py.toFixed(1)+' ';pen=true});
const lost=s.map((x,i)=>x===null?'<line x1="'+((i/(WLN-1))*W+(W-(n-1)/(WLN-1)*W)).toFixed(1)+'" x2="'+((i/(WLN-1))*W+(W-(n-1)/(WLN-1)*W)).toFixed(1)+'" y1="2" y2="'+(H-2)+'" stroke="#d1342a" opacity=".6"/>':'').join('');
return '<svg width="'+W+'" height="'+H+'" viewBox="0 0 '+W+' '+H+'">'+lost+'<path d="'+d+'" fill="none" stroke="var(--acc)" stroke-width="1.6" stroke-linejoin="round"/></svg>'}
function renderWl(){const box=$('#wltbl');if(!favs.length){box.innerHTML='<div class="empty">'+esc(t('No favorites yet. Star hosts with ☆ in any tool, or add one here:'))+'</div>';return}
const rows=favs.map((h,i)=>{const x=wlst[h],st=wlStatus(h),v=x?x.s.filter(a=>a!==null):[],n=x?x.s.length:0,last=x&&n?x.s[n-1]:undefined;
const avg=v.length?(v.reduce((a,b)=>a+b,0)/v.length).toFixed(0)+' ms':'—',loss=n?((n-v.length)/n*100).toFixed(0)+'%':'—';
return `<tr><td class="h">${esc(h)}</td><td><span class="st ${st}">${esc(t({up:'Up',slow:'Slow',down:'Down',wait:'Waiting…'}[st]))}</span></td><td class="n">${last===undefined?'—':last===null?esc(t('Loss')):last.toFixed(0)+' ms'}</td><td class="n">${avg}</td><td class="n">${loss}</td><td>${x?spark(x.s):''}</td><td><button class="rm" title="${esc(t('Remove from favorites'))}" onclick="rmFav(${i})">✕</button></td></tr>`}).join('');
box.innerHTML='<table><thead><tr><th>'+esc(t('Host'))+'</th><th>'+esc(t('Status'))+'</th><th>'+esc(t('Now'))+'</th><th>'+esc(t('Average'))+'</th><th>'+esc(t('Loss'))+'</th><th>'+esc(t('Trend'))+'</th><th></th></tr></thead><tbody>'+rows+'</tbody></table>'}
function wlAdd(){const i=$('#wladd'),v=i.value.trim();if(!v)return;if(!/^[A-Za-z0-9._:\/?&=%@~+,\[\]-]{1,253}$/.test(v)||v.startsWith('-'))return;if(!favs.includes(v))toggleFav(v);i.value='';i.focus()}
/* ---- copy a result as Markdown ---- */
function copyMd(){if(!raw||!cur)return;const args=Object.values((()=>{const v={};document.querySelectorAll('#f input[type=text]').forEach(i=>{if(i.value)v[i.name]=i.value});return v})()).join(' ');
const body=plain().replace(/\s+$/,'');const fence=/`{3,}/.test(body)?'````':'```';
const md='### '+cur.icon+' '+cur.label+(args?' — `'+args+'`':'')+'\n\n_'+new Date().toISOString().replace('T',' ').slice(0,19)+' · NetDoctor_\n\n'+fence+'text\n'+body+'\n'+fence+'\n';
navigator.clipboard.writeText(md).then(()=>{$('#st').textContent=t('Copied as Markdown')})}
/* ---- auto-check: run Diagnose on a schedule (keeps running while you use other pages) ---- */
let acrun=false,acto=null,acbusy=false,acmin=5,aclog=[],accls=null;
function showAc(){leaveViews();document.querySelector('main').classList.add('ac');document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_ac'));cur=null;renderAc()}
function acToggle(){acrun?acStop():acStart()}
function acStart(){if(acrun)return;acrun=true;acBadge();acTick()}
function acStop(){acrun=false;clearTimeout(acto);acBadge();acUpdateTitle();renderAc()}
function acBadge(){const n=$('#b_ac .nl');if(n)n.textContent=t('Auto-check')+(acrun?' ●':'')}
function acInterval(v){acmin=+v||5;if(acrun&&!acbusy){clearTimeout(acto);acto=setTimeout(acTick,acmin*60000)}}
function acVerdict(out){const lines=stripAnsi(out).split('\n');let k=-1;lines.forEach((l,i)=>{if(/^==\s*(Verdict|结论)\s*==/.test(l.trim()))k=i});
if(k>=0)for(let i=k+1;i<lines.length;i++){const m=lines[i].match(/^\[(FAIL| OK |WARN)\]\s*(.*)$/);if(m)return{cls:m[1]=='FAIL'?'bad':m[1]=='WARN'?'warn':'ok',text:m[2]}}
return{cls:'bad',text:'?'}}
async function acTick(){if(acbusy)return;acbusy=true;clearTimeout(acto);renderAc();const t0=Date.now();let out='',state='ok';
try{const r=await fetch('/run',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({cmd:'doctor',values:{},admin:false,lang})});if(!r.ok)state='failed';out=await r.text()}catch(e){state='failed';out=String(e)}
let v=acVerdict(out);const noRes=v.text=='?';if(noRes)v={cls:'warn',text:t('No verdict (is the NetDoctor server still running?)')};if(v.cls!='ok')state='failed';
addHist({cmd:'doctor',values:{},admin:false,state,sec:+((Date.now()-t0)/1000).toFixed(1),out});
aclog.unshift({ts:Date.now(),cls:v.cls,text:v.text,hid:hist.length?hist[0].id:null});aclog=aclog.slice(0,50);
if(!noRes&&accls!==null&&accls!==v.cls&&$('#acnote').checked&&'Notification' in window&&Notification.permission=='granted'){try{new Notification('NetDoctor',{body:t('Network verdict: %s').replace('%s',v.text)})}catch(e){}}
if(!noRes)accls=v.cls;acbusy=false;acUpdateTitle();renderAc();if(acrun)acto=setTimeout(acTick,acmin*60000)}
function acUpdateTitle(){if(!wlrun)document.title=(acrun&&accls=='bad'?'⚠ ':'')+BASE_TITLE()}
async function acNotifyChange(cb){if(!cb.checked)return;if(!('Notification' in window)){cb.checked=false;return}
if(Notification.permission=='default'){try{await Notification.requestPermission()}catch(e){}}
if(Notification.permission!='granted'){cb.checked=false;$('#acmsg').textContent=t('Notifications are blocked by the browser')}else $('#acmsg').textContent=''}
function acView(id){viewHist(id)}
function renderAc(){const g=$('#acgo');if(!g)return;g.textContent=t(acrun?'Stop':'Start');$('#acnow').disabled=acbusy;
if(acbusy)$('#acmsg').textContent=t('Running…');else if(acrun)$('#acmsg').textContent=t('Auto-check is running');else if($('#acmsg').textContent==t('Running…')||$('#acmsg').textContent==t('Auto-check is running'))$('#acmsg').textContent='';
const lab={ok:['up','Healthy'],warn:['slow','Unstable'],bad:['down','Problem']};
$('#aclog').innerHTML=aclog.length?aclog.map(r=>`<div class="al"><span class="st ${lab[r.cls][0]}">${esc(t(lab[r.cls][1]))}</span><span class="tm">${esc(new Date(r.ts).toLocaleTimeString(lang=='zh'?'zh-CN':'en-US'))}</span><span class="tx" title="${esc(r.text)}">${esc(r.text)}</span>${r.hid?`<button onclick="acView('${r.hid}')">${esc(t('View'))}</button>`:''}</div>`).join(''):`<div class="empty" style="padding:18px;color:var(--mut)">${esc(t('No runs yet'))}</div>`}
/* ---- history report (Markdown / HTML) ---- */
const ymd=d=>d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
function reportRows(){const q=$('#hq').value.trim().toLowerCase();let rows=hist.filter(h=>{if(!q)return true;const c=CMDS.find(c=>c.id==h.cmd),lab=c?c.label:h.cmd;return (t(lab)+' '+lab+' '+Object.values(h.values||{}).join(' ')).toLowerCase().includes(q)});
if(hcmp.length)rows=hist.filter(h=>hcmp.includes(h.id));return rows.slice().sort((a,b)=>a.ts-b.ts)}
function makeReport(kind){if(!kind)return;const rows=reportRows();if(!rows.length){$('#st').textContent=t(hist.length?'No matches':'No history yet');return}const loc=lang=='zh'?'zh-CN':'en-US',now=new Date();
const fmt=ts=>new Date(ts).toLocaleString(loc),sl={ok:'Done',stopped:'Stopped',failed:'Failed'};
const head=h=>{const c=CMDS.find(c=>c.id==h.cmd);return {title:(c?c.icon+' '+t(c.label):h.cmd),args:Object.values(h.values||{}).filter(Boolean).join(' ')+(h.admin?' 🔒':'')}};
let body,mime,ext;
if(kind=='md'){body='# '+t('NetDoctor report')+'\n\n_'+t('Generated')+': '+fmt(now)+'_\n\n'+rows.map((h,i)=>{const x=head(h),o=stripAnsi(h.out).replace(/\s+$/,''),f=/`{3,}/.test(o)?'````':'```';
return '## '+(i+1)+'. '+x.title+(x.args?' — `'+x.args.replace(/`/g,"'")+'`':'')+'\n\n_'+fmt(h.ts)+' · '+t(sl[h.state]||'Done')+' · '+h.sec+' s_\n\n'+f+'text\n'+o+'\n'+f+'\n'}).join('\n');mime='text/markdown';ext='md'}
else{const css='body{font:14px -apple-system,"Segoe UI",sans-serif;max-width:920px;margin:32px auto;padding:0 16px;color:#1d1d1f;background:#f5f5f7}@media(prefers-color-scheme:dark){body{color:#f5f5f7;background:#1c1c1e}}h1{font-size:22px}h2{font-size:16px;margin:26px 0 2px}.m{color:#6e6e73;font-size:12px;margin:0 0 8px}pre{background:#14161a;color:#d8dde6;border-radius:10px;padding:12px;overflow:auto;white-space:pre-wrap;word-break:break-all;font:12px/1.5 ui-monospace,Menlo,monospace}.b{font-weight:700}.g{color:#32d74b}.r{color:#ff453a}.y{color:#ffd60a}.d{opacity:.55}code{background:rgba(127,127,127,.18);border-radius:4px;padding:1px 5px}';
body='<!doctype html><html lang="'+(lang=='zh'?'zh-CN':'en')+'"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(t('NetDoctor report'))+'</title><style>'+css+'</style></head><body><h1>'+esc(t('NetDoctor report'))+'</h1><p class="m">'+esc(t('Generated'))+': '+esc(fmt(now))+'</p>'+
rows.map((h,i)=>{const x=head(h);return '<h2>'+(i+1)+'. '+esc(x.title)+(x.args?' — <code>'+esc(x.args)+'</code>':'')+'</h2><p class="m">'+esc(fmt(h.ts))+' · '+esc(t(sl[h.state]||'Done'))+' · '+esc(h.sec)+' s</p><pre>'+ansi(h.out)+'</pre>'}).join('')+'</body></html>';mime='text/html';ext='html'}
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([body],{type:mime+';charset=utf-8'}));a.download='netdoctor-report-'+ymd(now)+'.'+ext;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),2000)}
/* ---- speed trend ---- */
let spbusy=false;
function parseSpeed(out){const o=stripAnsi(out),conv=(v,u)=>{v=parseFloat(v);u=(u||'M').toUpperCase()[0];return u=='G'?v*1000:u=='K'?v/1000:v};
const d=o.match(/Downlink capacity:\s*([\d.]+)\s*([KMG])bps/i),u=o.match(/Uplink capacity:\s*([\d.]+)\s*([KMG])bps/i);
return{dl:d?conv(d[1],d[2]):null,ul:u?conv(u[1],u[2]):null}}
function spData(){return hist.filter(h=>h.cmd=='speed').map(h=>Object.assign({ts:h.ts},parseSpeed(h.out))).filter(x=>x.dl!==null||x.ul!==null).sort((a,b)=>a.ts-b.ts).slice(-60)}
function showSp(){leaveViews();document.querySelector('main').classList.add('sp');document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_sp'));cur=null;drawSp()}
async function spRun(){if(spbusy)return;spbusy=true;$('#spgo').disabled=true;$('#spmsg').textContent=t('Testing… (about 20 s)');const t0=Date.now();let out='',st='ok';
try{const r=await fetch('/run',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({cmd:'speed',values:{},admin:false,lang})});if(!r.ok)st='failed';out=await r.text()}catch(e){st='failed';out=String(e)}
const v=parseSpeed(out);if(v.dl===null&&v.ul===null)st='failed';
addHist({cmd:'speed',values:{},admin:false,state:st,sec:+((Date.now()-t0)/1000).toFixed(1),out});
spbusy=false;$('#spgo').disabled=false;$('#spmsg').textContent=st=='failed'?t('Could not read the speed results (macOS 12+ is required)'):'';drawSp()}
function drawSp(){const d=spData(),f=x=>x===null||x===undefined?'—':(x>=100?x.toFixed(0):x.toFixed(1))+' Mbps',last=d[d.length-1],dls=d.map(x=>x.dl).filter(x=>x!==null);
$('#sp_dl').textContent=last?f(last.dl):'—';$('#sp_ul').textContent=last?f(last.ul):'—';$('#sp_avg').textContent=dls.length?f(dls.reduce((a,b)=>a+b,0)/dls.length):'—';$('#sp_best').textContent=dls.length?f(Math.max(...dls)):'—';
const cv=$('#spchart');if(!cv.clientWidth)return;const dpr=window.devicePixelRatio||1,w=cv.clientWidth,h=cv.clientHeight;cv.width=w*dpr;cv.height=h*dpr;const g=cv.getContext('2d');g.scale(dpr,dpr);
const cs=getComputedStyle(document.documentElement),mut=cs.getPropertyValue('--mut').trim(),line=cs.getPropertyValue('--line').trim(),acc=cs.getPropertyValue('--acc').trim();
g.font='12px -apple-system,sans-serif';
if(!d.length){g.fillStyle=mut;g.textAlign='center';g.fillText(t('No speed results yet'),w/2,h/2);return}
const L=52,T=14,B=26,R=14,pw=w-L-R,ph=h-T-B,top=Math.max(10,...d.map(x=>Math.max(x.dl||0,x.ul||0)))*1.15,X=i=>d.length==1?L+pw/2:L+pw*i/(d.length-1),Y=v=>T+ph-ph*v/top;
g.lineWidth=1;g.textAlign='left';for(let i=0;i<=4;i++){const y=T+ph-ph*i/4;g.strokeStyle=line;g.beginPath();g.moveTo(L,y);g.lineTo(w-R,y);g.stroke();g.fillStyle=mut;g.fillText((top*i/4).toFixed(0),6,y+4)}
const series=(key,color)=>{g.strokeStyle=color;g.fillStyle=color;g.lineWidth=2;g.lineJoin='round';g.beginPath();let pen=false;d.forEach((x,i)=>{if(x[key]===null){pen=false;return}if(pen)g.lineTo(X(i),Y(x[key]));else{g.moveTo(X(i),Y(x[key]));pen=true}});g.stroke();d.forEach((x,i)=>{if(x[key]!==null){g.beginPath();g.arc(X(i),Y(x[key]),3.5,0,7);g.fill()}})};
series('ul','#e6a700');series('dl',acc);
g.fillStyle=mut;g.textAlign='left';g.fillText(new Date(d[0].ts).toLocaleString(lang=='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}),L,h-8);
g.textAlign='right';g.fillText(new Date(d[d.length-1].ts).toLocaleString(lang=='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}),w-R,h-8);
g.textAlign='left';g.fillStyle=acc;g.fillText('● '+t('Download'),L+8,T+14);g.fillStyle='#e6a700';g.fillText('● '+t('Upload'),L+110,T+14)}
/* ---- command palette (Ctrl/Cmd+K) ---- */
let palSel=0,palItems=[];
function palAll(){const pg=(k,icon,fn,alt)=>({icon,label:t(k),alt:k+' '+alt,d:'',run:fn});
return CMDS.map(c=>({icon:c.icon,label:t(c.label),alt:c.label+' '+(ZH[c.label]||'')+' '+c.id+' '+c.desc+' '+(ZH[c.desc]||''),d:t(c.desc),run:()=>pick(c.id)})).concat([
pg('Live latency','📈',showMon,'monitor ping latency 延迟 监控'),pg('Wi-Fi signal','📶',showWf,'wifi signal rssi 信号'),pg('Watchlist','📋',showWl,'favorites hosts 收藏 监控列表'),
pg('Auto-check','🔁',showAc,'schedule diagnose 自动 体检 定时'),pg('Speed trend','📉',showSp,'speed bandwidth history chart 测速 带宽 趋势'),
pg('History','🕘',()=>toggleHist(true),'runs past 历史 记录'),pg('Keyboard shortcuts','⌨',()=>toggleHelp(true),'help keys 快捷键 帮助'),
pg('Switch language','🌐',toggleLang,'english chinese 中文 语言'),pg('Switch theme','🌓',toggleTheme,'dark light 深色 浅色 主题')])}
function palFilter(){const q=$('#palq').value.trim().toLowerCase(),all=palAll();if(!q)return all.slice(0,14);const tk=q.split(/\s+/);
return all.map(i=>{const hay=(i.label+' '+i.alt).toLowerCase();if(!tk.every(x=>hay.includes(x)))return null;const l=i.label.toLowerCase();return{i,sc:l.startsWith(q)?0:l.includes(q)?1:2}}).filter(Boolean).sort((a,b)=>a.sc-b.sc).map(x=>x.i).slice(0,14)}
function renderPal(){palItems=palFilter();palSel=Math.max(0,Math.min(palSel,palItems.length-1));$('#palq').placeholder=t('Search tools and pages…');
$('#pall').innerHTML=palItems.length?palItems.map((i,n)=>`<div class="pi${n==palSel?' sel':''}" onmousemove="if(palSel!=${n}){palSel=${n};renderPal()}" onclick="palRun(${n})"><span>${i.icon}</span><span>${esc(i.label)}</span><span class="d">${esc(i.d||'')}</span></div>`).join(''):`<div style="padding:14px;color:var(--mut)">${esc(t('No matches'))}</div>`;
const el=$('#pall .sel');if(el)el.scrollIntoView({block:'nearest'})}
function palOpen(){$('#pal').classList.add('on');$('#palq').value='';palSel=0;renderPal();$('#palq').focus()}
function palClose(){$('#pal').classList.remove('on');$('#palq').blur()}
function palRun(n){const i=palItems[n];palClose();if(i)setTimeout(i.run,0)}
window.addEventListener('resize',()=>{const m=document.querySelector('main');if(m.classList.contains('sp'))drawSp();if(m.classList.contains('mon'))drawMon();if(m.classList.contains('wf'))drawWf()});
/* ---- Wi-Fi signal ---- */
let wsamples=[],wrun=false,wto=null,wmeta={};
function showWf(){leaveViews();const m=document.querySelector('main');m.classList.add('wf');document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_wf'));cur=null;drawWf();renderFavs()}
function wfToggle(){wrun?wfStop():wfStart()}
function wfStart(){if(wrun)return;wrun=true;$('#wgo').textContent=t('Stop');wfLoop()}
function wfStop(){wrun=false;clearTimeout(wto);$('#wgo').textContent=t('Start')}
function wfClear(){wsamples=[];wmeta={};$('#wmsg').textContent='';drawWf()}
async function wfLoop(){if(!wrun)return;if(!wsamples.length)$('#wmsg').textContent=t('Reading Wi-Fi… (this can take 10+ seconds on some Macs)');let d=null;try{const r=await fetch('/wifi',{method:'POST',headers:{'X-Token':TOKEN},body:'{}'});d=await r.json()}catch(e){d={error:'unavailable'}}
if(!wrun)return;if(d.error){$('#wmsg').textContent=t('Wi-Fi info unavailable')+' ('+d.error+')';wsamples.push(null)}else{$('#wmsg').textContent=d.ssid||'';wmeta=d;wsamples.push({r:d.rssi,n:d.noise})}
if(wsamples.length>MAXS)wsamples.shift();drawWf();wto=setTimeout(wfLoop,1500)}
function drawWf(){const last=[...wsamples].reverse().find(x=>x);const q=v=>v>-60?'#2fa84f':v>-70?'#c98a00':'#d1342a';
$('#w_rssi').textContent=last?last.r+' dBm':'—';$('#w_rssi').style.color=last?q(last.r):'';$('#w_noise').textContent=last?last.n+' dBm':'—';
$('#w_snr').textContent=last?(last.r-last.n)+' dB':'—';$('#w_ch').textContent=wmeta.channel||'—';$('#w_rate').textContent=wmeta.rate?wmeta.rate+' Mbps':'—';
const cv=$('#wchart');if(!cv.clientWidth)return;const dpr=window.devicePixelRatio||1,w=cv.clientWidth,h=cv.clientHeight;cv.width=w*dpr;cv.height=h*dpr;const g=cv.getContext('2d');g.scale(dpr,dpr);
const cs=getComputedStyle(document.documentElement),mut=cs.getPropertyValue('--mut').trim(),line=cs.getPropertyValue('--line').trim(),acc=cs.getPropertyValue('--acc').trim();
const L=46,T=10,B=8,R=10,pw=w-L-R,ph=h-T-B,LO=-100,HI=-30,Y=v=>T+ph*(HI-Math.max(LO,Math.min(HI,v)))/(HI-LO);
[[HI,-60,'rgba(47,168,79,.12)'],[-60,-70,'rgba(201,138,0,.12)'],[-70,LO,'rgba(209,52,42,.10)']].forEach(([a,b,c])=>{g.fillStyle=c;g.fillRect(L,Y(a),pw,Y(b)-Y(a))});
g.font='11px ui-monospace,Menlo,monospace';g.lineWidth=1;for(let v=LO;v<=HI;v+=10){const y=Y(v);g.strokeStyle=line;g.beginPath();g.moveTo(L,y);g.lineTo(w-R,y);g.stroke();g.fillStyle=mut;g.fillText(String(v),6,y+4)}
const n=wsamples.length,X=i=>L+pw-(n-1-i)*pw/(MAXS-1);
const path=(key,color,dash)=>{g.strokeStyle=color;g.lineWidth=2;g.setLineDash(dash);g.lineJoin='round';g.beginPath();let pen=false;wsamples.forEach((s,i)=>{if(!s){pen=false;return}const y=Y(s[key]);if(pen)g.lineTo(X(i),y);else{g.moveTo(X(i),y);pen=true}});g.stroke();g.setLineDash([])};
path('n',mut,[5,4]);path('r',acc,[])}
/* ---- favorites ---- */
const FKEY='nd_favs',FMAX=30,FAVN=['host','domain','url'];let favs=[];
try{favs=JSON.parse(localStorage.getItem(FKEY)||'[]').filter(x=>typeof x=='string'&&x.length<=300)}catch(e){}
function saveFavs(){try{localStorage.setItem(FKEY,JSON.stringify(favs))}catch(e){}}
function favTarget(){const m=document.querySelector('main');if(m.classList.contains('mon'))return $('#mhost');if(m.classList.contains('wf')||m.classList.contains('wl'))return null;return document.querySelector(FAVN.map(n=>'#f input[name='+n+']').join(','))}
function toggleFav(v){v=(v||'').trim();if(!v)return;const i=favs.indexOf(v);if(i>=0)favs.splice(i,1);else{favs.unshift(v);favs=favs.slice(0,FMAX)}saveFavs();renderFavs()}
function fillFav(i){const el=favTarget(),v=favs[i];if(!el||v===undefined)return;let x=v;
if(el.name=='url'&&!/^https?:\/\//.test(x))x='https://'+x;else if(el.name&&el.name!='url'&&/^https?:\/\//.test(x))x=x.replace(/^https?:\/\//,'').split(/[\/?#]/)[0];
el.value=x;el.focus();renderFavs()}
function rmFav(i){favs.splice(i,1);saveFavs();renderFavs()}
function renderFavs(){const html=favs.length?'<small>★ '+esc(t('Favorites'))+'</small>'+favs.map((v,i)=>`<span class="chip" onclick="fillFav(${i})">${esc(v)}<i title="${esc(t('Remove from favorites'))}" onclick="event.stopPropagation();rmFav(${i})">×</i></span>`).join(''):'';
const m=document.querySelector('main'),mon=m.classList.contains('mon');$('#favs').innerHTML=mon||!document.querySelector('#f input[name=host],#f input[name=domain],#f input[name=url]')?'':html;$('#mfavs').innerHTML=mon?html:'';
$('#favlist').innerHTML=favs.map(v=>`<option value="${esc(v)}">`).join('');$('#mpre').innerHTML=[...favs,'1.1.1.1','8.8.8.8','223.5.5.5','114.114.114.114'].filter((v,i,a)=>a.indexOf(v)==i).map(v=>`<option value="${esc(v)}">`).join('');
document.querySelectorAll('#f .star').forEach(b=>{const on=favs.includes(b.previousSibling.value.trim());b.classList.toggle('on',on);b.textContent=on?'★':'☆';b.title=t(on?'Remove from favorites':'Add to favorites')});
const ms=$('#mstar'),mon2=favs.includes($('#mhost').value.trim());ms.classList.toggle('on',mon2);ms.textContent=mon2?'★':'☆';ms.title=t(mon2?'Remove from favorites':'Add to favorites');if(document.querySelector('main').classList.contains('wl'))renderWl()}
/* ---- compare two runs ---- */
let hcmp=[];
function cmpToggle(id,on){hcmp=hcmp.filter(x=>x!=id);if(on)hcmp.push(id);if(hcmp.length>2)hcmp.shift();renderHist()}
const stripAnsi=x=>x.replace(/\x1b\[\d+m/g,'');
function diffOps(a,b,key){const n=a.length,m=b.length,A=a.map(key),B=b.map(key),dp=Array.from({length:n+1},()=>new Uint16Array(m+1));
for(let i=n-1;i>=0;i--)for(let j=m-1;j>=0;j--)dp[i][j]=A[i]===B[j]?dp[i+1][j+1]+1:Math.max(dp[i+1][j],dp[i][j+1]);
const ops=[];let i=0,j=0;while(i<n&&j<m){if(A[i]===B[j]){ops.push(['=',b[j]]);i++;j++}else if(dp[i+1][j]>=dp[i][j+1]){ops.push(['-',a[i]]);i++}else{ops.push(['+',b[j]]);j++}}
while(i<n)ops.push(['-',a[i++]]);while(j<m)ops.push(['+',b[j++]]);return ops}
function cmpOpen(){if(hcmp.length!=2)return;$('#cmp').classList.add('on');cmpRender()}
function cmpClose(){$('#cmp').classList.remove('on')}
function cmpRender(){const [x,y]=hcmp.map(id=>hist.find(h=>h.id==id)).filter(Boolean).sort((a,b)=>a.ts-b.ts);if(!y){cmpClose();return}
const lab=h=>{const c=CMDS.find(c=>c.id==h.cmd);return (c?c.icon+' '+t(c.label):h.cmd)+' · '+Object.values(h.values||{}).filter(Boolean).join(' ')+' · '+new Date(h.ts).toLocaleString(lang=='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit'})};
$('#cmpmeta').innerHTML='<div title="'+esc(lab(x))+'"><b>'+esc(t('Older'))+':</b> '+esc(lab(x))+'</div><div title="'+esc(lab(y))+'"><b>'+esc(t('Newer'))+':</b> '+esc(lab(y))+'</div>';
const CAP=1500,lines=h=>stripAnsi(h.out).split('\n').map(l=>l.replace(/\s+$/,'')),la=lines(x),lb=lines(y),cut=la.length>CAP||lb.length>CAP;
const key=$('#cmpnum').checked?l=>l.replace(/\d+(\.\d+)?/g,'#'):l=>l;const ops=diffOps(la.slice(0,CAP),lb.slice(0,CAP),key);
const add=ops.filter(o=>o[0]=='+').length,del=ops.filter(o=>o[0]=='-').length;
$('#cmpsum').textContent=(add||del?t('+%s / −%s lines').replace('%s',add).replace('%s',del):t('No differences'))+(cut?' '+t('(only the first 1500 lines are compared)'):'');
const only=$('#cmpchg').checked,show=new Array(ops.length).fill(!only);if(only){ops.forEach((o,i)=>{if(o[0]!='='){for(let k=Math.max(0,i-2);k<=Math.min(ops.length-1,i+2);k++)show[k]=true}})}
let html='',hidden=0;const flush=()=>{if(hidden){html+='<div class="dl gap">'+esc(t('… %s unchanged lines …').replace('%s',hidden))+'</div>';hidden=0}};
ops.forEach((o,i)=>{if(!show[i]){hidden++;return}flush();html+='<div class="dl '+({'+':'add','-':'del','=':''}[o[0]])+'">'+esc((o[0]=='='?'  ':o[0]+' ')+o[1])+'</div>'});flush();$('#cmpout').innerHTML=html}
/* ---- history export / import ---- */
function exportHist(){const data={app:'netdoctor',version:1,exported:new Date().toISOString(),history:hist,favorites:favs};
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(data,null,1)],{type:'application/json'}));a.download='netdoctor-history-'+ymd(new Date())+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),2000)}
async function importHist(inp){const f=inp.files[0];inp.value='';if(!f)return;
try{if(f.size>8e6)throw 0;const d=JSON.parse(await f.text());if(!d||d.app!='netdoctor'||!Array.isArray(d.history||[]))throw 0;
const ids=new Set(hist.map(h=>h.id)),okS=['ok','stopped','failed'];let nh=0,nf=0;
(d.history||[]).forEach(h=>{if(!h||typeof h.cmd!='string'||!CMDS.some(c=>c.id==h.cmd)||typeof h.out!='string'||typeof h.id!='string'||!/^[\w.-]{1,40}$/.test(h.id)||ids.has(h.id))return;
const vals={};if(h.values&&typeof h.values=='object')Object.keys(h.values).forEach(k=>{if(typeof h.values[k]=='string')vals[k.slice(0,40)]=h.values[k].slice(0,300)});
hist.push({id:h.id,ts:Number.isFinite(+h.ts)?+h.ts:Date.now(),cmd:h.cmd,values:vals,admin:!!h.admin,state:okS.includes(h.state)?h.state:'ok',sec:Number.isFinite(+h.sec)?+h.sec:0,out:h.out.slice(-OMAX)});ids.add(h.id);nh++});
hist.sort((a,b)=>b.ts-a.ts);hist=hist.slice(0,HMAX);saveHist();
(Array.isArray(d.favorites)?d.favorites:[]).forEach(v=>{if(typeof v=='string'&&v.trim()&&v.length<=300&&!favs.includes(v)&&favs.length<FMAX){favs.push(v);nf++}});saveFavs();
renderHist();renderFavs();$('#st').textContent=t('Imported %s run(s), %s favorite(s)').replace('%s',nh).replace('%s',nf)}
catch(e){$('#st').textContent=t('Import failed: invalid file')}}
function applyLang(){$('#b_mon .nl').textContent=t('Live latency');$('#b_wf .nl').textContent=t('Wi-Fi signal');$('#b_wl .nl').textContent=t('Watchlist');$('#b_sp .nl').textContent=t('Speed trend');if($('#pal').classList.contains('on'))renderPal();acBadge();renderAc();$('#wlgo').textContent=wlrun?t('Stop'):t('Start');if(!wlrun)document.title=t('NetDoctor Network Diagnostics');if(wrun)$('#wgo').textContent=t('Stop');else $('#wgo').textContent=t('Start');if($('#cmp').classList.contains('on'))cmpRender();if(!mtimer)$('#mgo').textContent=t('Start');else $('#mgo').textContent=t('Stop');document.documentElement.lang=lang=='zh'?'zh-CN':'en';document.title=t('NetDoctor Network Diagnostics');
document.querySelectorAll('[data-i]').forEach(e=>e.textContent=t(e.dataset.i));
CMDS.forEach(c=>{$('#b_'+c.id+' .nl').textContent=t(c.label)});
$('#lang').textContent='🌐 '+(lang=='zh'?'English':'中文');if(idle)$('#out').textContent=t(INTRO);
applyTheme();renderFavs();if($('#hist').classList.contains('on'))renderHist();if(document.querySelector('main').classList.contains('wf'))drawWf();if(document.querySelector('main').classList.contains('wl'))renderWl();$('#stop').title='Esc';$('#histbtn').title='h';$('#lang').title='l';$('#theme').title='t';$('#helpbtn').title='?';if(cur)pick(cur.id,true,true)}
function toggleLang(){lang=lang=='zh'?'en':'zh';try{localStorage.setItem('nd_lang',lang)}catch(e){}applyLang()}
function pick(id,keep,nofocus){leaveViews();const busy=!!($('#run')&&$('#run').disabled);
// 切换到另一个工具时清掉上一个工具的输出, 避免 Diagnose 标题下显示别的工具的结果 (运行中或同一工具重绘时保留)
if(!keep&&!busy&&(!cur||cur.id!=id)){raw='';idle=true;$('#out').textContent=t(INTRO);$('#st').textContent=''}
const old={};if(keep)document.querySelectorAll('#f input').forEach(i=>{old[i.name]=i.type=='checkbox'?i.checked:i.value});cur=CMDS.find(c=>c.id==id);document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_'+id));
$('#t').textContent=cur.icon+' '+t(cur.label);$('#d').textContent=t(cur.desc);const f=$('#f');f.innerHTML='';
cur.inputs.forEach(i=>{const l=document.createElement('label');l.textContent=t(i.label)+(i.req?' *':'');const x=document.createElement('input');x.type='text';x.name=i.name;x.placeholder=t(i.ph||'');x.value=(keep&&old[i.name]!==undefined)?old[i.name]:(i.def||'');if(FAVN.includes(i.name)){x.setAttribute('list','favlist');x.setAttribute('spellcheck','false');const star=document.createElement('button');star.type='button';star.className='star';star.onclick=()=>toggleFav(x.value);x.addEventListener('input',renderFavs);const w=document.createElement('span');w.className='fw';w.append(x,star);l.append(w)}else l.append(x);f.append(l)});
if(cur.admin===true||cur.admin==='optional'){const l=document.createElement('label');l.className='chk';l.innerHTML=`<input type="checkbox" name="_admin" ${cur.admin===true?'checked disabled':''}>${t('Requires administrator rights')}${cur.admin===true?'':' '+t('(fuller details)')}`;f.append(l);if(keep&&old._admin!==undefined&&cur.admin!==true)l.querySelector('input').checked=old._admin}
const r=document.createElement('button');r.className='btn';r.id='run';r.textContent=t('Run');r.title=MOD+'+Enter';r.type='submit';f.append(r);
f.onsubmit=e=>{e.preventDefault();run()};const first=f.querySelector('input[type=text]');renderFavs();first&&!nofocus&&first.focus()}
function ansi(s){const esc=t=>t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');let open=0,o='';
return esc(s).replace(/\x1b\[(\d+)m/g,(m,c)=>{let r='';if(c=='0'||c=='22'){r='</span>'.repeat(open);open=0;return r}
const k={1:'b',31:'r',32:'g',33:'y',2:'d'}[c];if(!k)return '';open++;return `<span class="${k}">`})+'</span>'.repeat(open)}
async function run(){let state='ok';const values={};let admin=false;$('#f').querySelectorAll('input').forEach(i=>{if(i.name=='_admin')admin=i.checked;else values[i.name]=i.value});
ctl=new AbortController();raw='';idle=false;$('#out').textContent='';$('#run').disabled=true;$('#stop').disabled=false;$('#st').textContent=t('Running…');const t0=Date.now();
try{const r=await fetch('/run',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({cmd:cur.id,values,admin,lang}),signal:ctl.signal});if(!r.ok)state='failed';
const rd=r.body.getReader(),dc=new TextDecoder();for(;;){const {done,value}=await rd.read();if(done)break;raw+=dc.decode(value,{stream:true});$('#out').innerHTML=ansi(raw);$('#out').scrollTop=1e9}
$('#st').textContent=fmt('Done in %ss',((Date.now()-t0)/1000).toFixed(1))}catch(e){state=e.name=='AbortError'?'stopped':'failed';$('#st').textContent=e.name=='AbortError'?t('Stopped'):t('Failed')+': '+e}
$('#run').disabled=false;$('#stop').disabled=true;
const mc=raw.match(/\[(?:exit code|退出码) (\d+)\]/);if(mc&&mc[1]!='0'&&state=='ok')state='failed';
addHist({cmd:cur.id,values,admin,state,sec:+((Date.now()-t0)/1000).toFixed(1),out:raw})}
function stop(){ctl&&ctl.abort()}
const plain=()=>raw.replace(/\x1b\[\d+m/g,'');
function copy(){navigator.clipboard.writeText(plain());$('#st').textContent=t('Copied')}
function save(){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([plain()]));a.download=`netdoctor-${cur?cur.id:'out'}-${Date.now()}.txt`;a.click()}
async function quit(){if(confirm(t('Quit the NetDoctor service?'))){await fetch('/quit',{method:'POST',headers:{'X-Token':TOKEN}}).catch(()=>{});document.body.innerHTML='<p style="margin:40px">'+t('Quit. You can close this page.')+'</p>'}}
const HKEY='nd_history',HMAX=50,OMAX=60000;
let hist=[],hsel=null;try{hist=JSON.parse(localStorage.getItem(HKEY)||'[]')}catch(e){}
function saveHist(){for(;;){try{localStorage.setItem(HKEY,JSON.stringify(hist));return}catch(e){if(!hist.length)return;hist.pop()}}}
function addHist(h){if(h.out.length>OMAX)h.out='…'+t('(output truncated)')+'\n'+h.out.slice(-OMAX);
h.id=Date.now()+'-'+Math.random().toString(36).slice(2,6);h.ts=Date.now();hist.unshift(h);hist=hist.slice(0,HMAX);hsel=h.id;saveHist();if($('#hist').classList.contains('on'))renderHist()}
const esc=x=>String(x).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
function renderHist(){$('#cmpbtn').disabled=hcmp.length!=2;const q=$('#hq').value.trim().toLowerCase();$('#hq').placeholder=t('Search…');
const rows=hist.filter(h=>{if(!q)return true;const c=CMDS.find(c=>c.id==h.cmd),lab=c?c.label:h.cmd;return (t(lab)+' '+lab+' '+Object.values(h.values||{}).join(' ')).toLowerCase().includes(q)});
$('#hlist').innerHTML=rows.length?rows.map(h=>{const c=CMDS.find(c=>c.id==h.cmd)||{icon:'•',label:h.cmd};
const args=Object.values(h.values||{}).filter(Boolean).join(' ')+(h.admin?' 🔒':'');
const when=new Date(h.ts).toLocaleString(lang=='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit'});
const lbl={ok:'Done',stopped:'Stopped',failed:'Failed'}[h.state]||'Done';
return `<div class="hi${h.id==hsel?' sel':''}" onclick="viewHist('${h.id}')"><input type="checkbox" class="hc" title="${esc(t('Tick two runs to compare'))}" ${hcmp.includes(h.id)?'checked':''} onclick="event.stopPropagation();cmpToggle('${h.id}',this.checked)"><span>${c.icon}</span><div class="m"><div class="n">${esc(t(c.label))}<span class="bd ${h.state}">${esc(t(lbl))}</span></div><div class="a">${esc(args)||'&nbsp;'}</div><div class="w">${esc(when)} · ${h.sec}s</div></div><div class="x"><button onclick="event.stopPropagation();rerunHist('${h.id}')">${esc(t('Re-run'))}</button><button onclick="event.stopPropagation();delHist('${h.id}')">${esc(t('Delete'))}</button></div></div>`}).join(''):`<p style="color:var(--mut);padding:8px">${esc(t(hist.length?'No matches':'No history yet'))}</p>`}
function toggleHist(on){const h=$('#hist');const open=on===undefined?!h.classList.contains('on'):on;h.classList.toggle('on',open);if(open){renderHist()}}
function viewHist(id){const h=hist.find(x=>x.id==id);if(!h)return;hsel=id;pick(h.cmd,false,true);
document.querySelectorAll('#f input').forEach(i=>{if(i.name=='_admin'){if(!i.disabled)i.checked=!!h.admin}else if(h.values&&h.values[i.name]!==undefined)i.value=h.values[i.name]});
raw=h.out;idle=false;$('#out').innerHTML=ansi(raw);$('#out').scrollTop=0;
$('#st').textContent=t('Viewing history')+': '+new Date(h.ts).toLocaleString(lang=='zh'?'zh-CN':'en-US');renderHist()}
function rerunHist(id){viewHist(id);if(!$('#run').disabled)run()}
function delHist(id){hist=hist.filter(h=>h.id!=id);hcmp=hcmp.filter(x=>x!=id);saveHist();renderHist()}
function clearHist(){if(hist.length&&confirm(t('Clear all history?'))){hist=[];hsel=null;hcmp=[];saveHist();renderHist()}}
const MOD=/Mac|iPhone|iPad/.test(navigator.platform)?'⌘':'Ctrl';
const SC=[[[MOD+' + Enter'],'Run the current tool'],[['Esc'],'Stop a running command; otherwise leave the input box'],
[['j','↓'],'Previous / next tool'],[['1'],'Jump to tool 1–9'],[['/'],'Focus the first input'],[['Enter'],'Run (when not typing)'],
[['c'],'Copy output'],[['s'],'Save output'],[['l'],'Switch language'],[['t'],'Switch theme'],[['m'],'Open live latency'],[['w'],'Open Wi-Fi signal'],[['f'],'Open Watchlist'],[['a'],'Open Auto-check'],[['p'],'Open speed trend'],[[MOD+' + K'],'Command palette'],[['h'],'Show / hide history'],[['?'],'Show / hide this help']];
SC[2][0]=['j / ↓  ·  k / ↑'];SC[3][0]=['1 … 9'];
function toggleHelp(on){const h=$('#help');const open=on===undefined?!h.classList.contains('on'):on;
if(open){$('#helph').textContent='⌨ '+t('Keyboard shortcuts');$('#helpt').innerHTML=SC.map(([k,d])=>`<tr><td>${k.map(x=>'<kbd>'+x.replace(/&/g,'&amp;').replace(/</g,'&lt;')+'</kbd>').join('')}</td><td>${t(d)}</td></tr>`).join('')}
h.classList.toggle('on',open)}
function go(delta,abs){const i=CMDS.findIndex(c=>c.id==(cur&&cur.id));const n=abs!==undefined?abs:Math.max(0,Math.min(CMDS.length-1,i+delta));if(CMDS[n]){pick(CMDS[n].id,false,true);$('#b_'+CMDS[n].id).scrollIntoView({block:'nearest'})}}
document.addEventListener('keydown',e=>{
const typing=/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)&&e.target.type!='checkbox';
const palIsOpen=$('#pal').classList.contains('on');
if((e.metaKey||e.ctrlKey)&&(e.key=='k'||e.key=='K')){e.preventDefault();palIsOpen?palClose():palOpen();return}
if(palIsOpen){if(e.key=='Escape')palClose();else if(e.key=='ArrowDown'){palSel=Math.min(palItems.length-1,palSel+1);renderPal()}else if(e.key=='ArrowUp'){palSel=Math.max(0,palSel-1);renderPal()}else if(e.key=='Enter')palRun(palSel);else return;e.preventDefault();return}
const helpOpen=$('#help').classList.contains('on'),histOpen=$('#hist').classList.contains('on'),cmpIsOpen=$('#cmp').classList.contains('on');
if(e.key=='Escape'){if(cmpIsOpen){cmpClose()}else if(helpOpen){toggleHelp(false)}else if(histOpen&&$('#stop').disabled){toggleHist(false)}else if(!$('#stop').disabled){stop()}else if(typing){e.target.blur()}else return;e.preventDefault();return}
if((e.metaKey||e.ctrlKey)&&e.key=='Enter'){if(!$('#run').disabled){e.preventDefault();run()}return}
if(e.metaKey||e.ctrlKey||e.altKey||typing)return;
if(cmpIsOpen)return;
if(helpOpen){if(e.key=='?'){toggleHelp(false);e.preventDefault()}return}
if(histOpen&&e.key!='h'&&e.key!='?')return;
const k=e.key;let used=true;
if(k=='?')toggleHelp(true);
else if(k=='j'||k=='ArrowDown')go(1);
else if(k=='k'||k=='ArrowUp')go(-1);
else if(/^[1-9]$/.test(k))go(0,+k-1);
else if(k=='/'){const f=$('#f input[type=text]');f?f.focus():used=false}
else if(k=='Enter'&&e.target.tagName!='BUTTON'){if(!$('#run').disabled)run()}
else if(k=='c'){if(raw)copy()}
else if(k=='s'){if(raw)save()}
else if(k=='m')showMon();
else if(k=='w')showWf();
else if(k=='f')showWl();
else if(k=='a')showAc();
else if(k=='p')showSp();
else if(k=='h')toggleHist();
else if(k=='l')toggleLang();
else if(k=='t')toggleTheme();
else used=false;
if(used)e.preventDefault()});
pick('quick');applyLang();
</script></body></html>"""

def port_arg(v):
    n = int(v)
    if not 0 <= n <= 65535:
        raise argparse.ArgumentTypeError("must be between 0 and 65535")
    return n

def port_in_use(port):
    """True if something already accepts connections on 127.0.0.1:port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sk:
        sk.settimeout(0.5)
        return sk.connect_ex(("127.0.0.1", port)) == 0

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=port_arg, default=8765, help="0 = random free port; falls back to random if busy"); ap.add_argument("--no-open", action="store_true")
    a = ap.parse_args()
    # macOS lets two sockets listen on the same port when SO_REUSEADDR is set (the default for this server
    # class), so a busy port does not make bind() fail and a second instance would silently share it.
    # Probe first, so the "busy -> random free port" fallback really happens.
    if a.port and port_in_use(a.port):
        print("Port %d is already in use; picking a free port instead." % a.port)
        a.port = 0
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    except OSError:  # still busy (race or no permission): use any free port
        srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    url = "http://127.0.0.1:%d/" % srv.server_address[1]
    print("NetDoctor GUI:", url, "(Ctrl-C to quit)")
    if not a.no_open: threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__":
    main()
