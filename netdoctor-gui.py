#!/usr/bin/env python3
"""NetDoctor GUI - local web interface (standard library only, listens on 127.0.0.1 only).
Usage: python3 netdoctor-gui.py [--port 8765] [--no-open]
"""
import argparse, json, os, re, secrets, select, shlex, socket, subprocess, sys, threading, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
NETDOCTOR = os.path.join(HERE, "netdoctor")
TOKEN = secrets.token_urlsafe(16)

# admin: True=required, "optional"=user can tick it, False=not needed
COMMANDS = [
 {"id":"quick","label":"Quick check","icon":"🩺","desc":"Gateway → public IP → DNS → HTTP, layer by layer, with a diagnosis","inputs":[]},
 {"id":"wifi","label":"Wi-Fi","icon":"📶","desc":"SSID, signal, noise, channel, rate","inputs":[],"admin":"optional"},
 {"id":"dns","label":"DNS compare","icon":"🔎","desc":"Answers and timings from the system and several public DNS servers","inputs":[{"name":"domain","label":"Domain","ph":"example.com","req":True}]},
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
        self._send(404, "not found")

    def do_POST(self):
        if not self._ok_host() or self.headers.get("X-Token") != TOKEN:
            return self._send(403, "forbidden")
        if self.path == "/quit":
            self._send(200, "bye"); threading.Thread(target=self.server.shutdown, daemon=True).start(); return
        if self.path != "/run": return self._send(404, "not found")
        lang = "en"
        try:
            n = int(self.headers.get("Content-Length") or 0)
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
                " ".join(shlex.quote(x) for x in [NETDOCTOR, spec["id"]] + args))
            inner = inner.replace("\\", "\\\\").replace('"', '\\"')
            cmd = ["osascript", "-e", 'do shell script "%s" with administrator privileges' % inner]
            self.wfile.write((tr(lang, "(Waiting for the system administrator password prompt…)") + "\n").encode()); self.wfile.flush()
        else:
            cmd = [NETDOCTOR, spec["id"]] + args
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=env, bufsize=0)
        except Exception as e:
            self.wfile.write(("%s: %s\n" % (tr(lang, "Failed to start"), e)).encode()); return
        try:
            fd = p.stdout.fileno()
            while True:
                r, _, _ = select.select([fd, self.connection], [], [], 1.0)
                if self.connection in r:  # 浏览器断开 (点了停止/关了页面) -> 结束子进程
                    try:
                        if not self.connection.recv(1, socket.MSG_PEEK): break
                    except OSError: break
                if fd in r:
                    chunk = os.read(fd, 4096)
                    if not chunk: break
                    self.wfile.write(chunk); self.wfile.flush()
            if p.poll() is None and not p.stdout.closed:
                p.kill()
            rc = p.wait()
            self.wfile.write(("\n\x1b[2m%s\x1b[0m\n" % (tr(lang, "[exit code %d]") % rc)).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass  # user clicked Stop
        finally:
            if p.poll() is None:
                p.kill()

HTML = r"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NetDoctor Network Diagnostics</title><style>
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
</style><script>try{var th=localStorage.getItem('nd_theme');if(th==='light'||th==='dark')document.documentElement.dataset.theme=th}catch(e){}</script></head><body>
<nav><h1>🛰️ NetDoctor</h1><div id="list"></div><button onclick="toggleHist()" id="histbtn" style="margin-top:14px;color:var(--mut)">🕘 <span data-i="History">History</span></button><button onclick="toggleHelp()" id="helpbtn" style="color:var(--mut)">⌨ <span data-i="Shortcuts">Shortcuts</span></button><button onclick="toggleTheme()" id="theme" style="color:var(--mut)"></button><button onclick="toggleLang()" id="lang" style="color:var(--mut)"></button><button onclick="quit()" style="color:var(--mut)">⏻ <span data-i="Quit">Quit</span></button></nav>
<main><div class="card"><h2 id="t"></h2><p id="d"></p><form id="f"></form></div>
<div class="bar"><span class="sp" id="st" style="color:var(--mut)"></span><button class="btn sec" onclick="copy()" data-i="Copy">Copy</button><button class="btn sec" onclick="save()" data-i="Save">Save</button><button class="btn sec" id="stop" onclick="stop()" data-i="Stop" disabled>Stop</button></div>
<pre id="out"></pre></main>
<aside id="hist"><header><h3>🕘 <span data-i="History">History</span></h3><button class="btn sec" onclick="clearHist()" data-i="Clear all">Clear all</button><button class="btn sec" onclick="toggleHist(false)" data-i="Close">Close</button></header>
<input type="text" id="hq" oninput="renderHist()"><p class="note" data-i="Stored in this browser only (last 50 runs).">Stored in this browser only (last 50 runs).</p><div id="hlist"></div></aside>
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
function applyLang(){document.documentElement.lang=lang=='zh'?'zh-CN':'en';document.title=t('NetDoctor Network Diagnostics');
document.querySelectorAll('[data-i]').forEach(e=>e.textContent=t(e.dataset.i));
CMDS.forEach(c=>{$('#b_'+c.id+' .nl').textContent=t(c.label)});
$('#lang').textContent='🌐 '+(lang=='zh'?'English':'中文');if(idle)$('#out').textContent=t(INTRO);
applyTheme();if($('#hist').classList.contains('on'))renderHist();$('#stop').title='Esc';$('#histbtn').title='h';$('#lang').title='l';$('#theme').title='t';$('#helpbtn').title='?';if(cur)pick(cur.id,true,true)}
function toggleLang(){lang=lang=='zh'?'en':'zh';try{localStorage.setItem('nd_lang',lang)}catch(e){}applyLang()}
function pick(id,keep,nofocus){const old={};if(keep)document.querySelectorAll('#f input').forEach(i=>{old[i.name]=i.type=='checkbox'?i.checked:i.value});cur=CMDS.find(c=>c.id==id);document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_'+id));
$('#t').textContent=cur.icon+' '+t(cur.label);$('#d').textContent=t(cur.desc);const f=$('#f');f.innerHTML='';
cur.inputs.forEach(i=>{const l=document.createElement('label');l.textContent=t(i.label)+(i.req?' *':'');const x=document.createElement('input');x.type='text';x.name=i.name;x.placeholder=i.ph||'';x.value=(keep&&old[i.name]!==undefined)?old[i.name]:(i.def||'');l.append(x);f.append(l)});
if(cur.admin===true||cur.admin==='optional'){const l=document.createElement('label');l.className='chk';l.innerHTML=`<input type="checkbox" name="_admin" ${cur.admin===true?'checked disabled':''}>${t('Requires administrator rights')}${cur.admin===true?'':' '+t('(fuller details)')}`;f.append(l);if(keep&&old._admin!==undefined&&cur.admin!==true)l.querySelector('input').checked=old._admin}
const r=document.createElement('button');r.className='btn';r.id='run';r.textContent=t('Run');r.title=MOD+'+Enter';r.type='submit';f.append(r);
f.onsubmit=e=>{e.preventDefault();run()};const first=f.querySelector('input[type=text]');first&&!nofocus&&first.focus()}
function ansi(s){const esc=t=>t.replace(/&/g,'&amp;').replace(/</g,'&lt;');let open=0,o='';
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
function renderHist(){const q=$('#hq').value.trim().toLowerCase();$('#hq').placeholder=t('Search…');
const rows=hist.filter(h=>{if(!q)return true;const c=CMDS.find(c=>c.id==h.cmd),lab=c?c.label:h.cmd;return (t(lab)+' '+lab+' '+Object.values(h.values||{}).join(' ')).toLowerCase().includes(q)});
$('#hlist').innerHTML=rows.length?rows.map(h=>{const c=CMDS.find(c=>c.id==h.cmd)||{icon:'•',label:h.cmd};
const args=Object.values(h.values||{}).filter(Boolean).join(' ')+(h.admin?' 🔒':'');
const when=new Date(h.ts).toLocaleString(lang=='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit'});
const lbl={ok:'Done',stopped:'Stopped',failed:'Failed'}[h.state]||'Done';
return `<div class="hi${h.id==hsel?' sel':''}" onclick="viewHist('${h.id}')"><span>${c.icon}</span><div class="m"><div class="n">${esc(t(c.label))}<span class="bd ${h.state}">${esc(t(lbl))}</span></div><div class="a">${esc(args)||'&nbsp;'}</div><div class="w">${esc(when)} · ${h.sec}s</div></div><div class="x"><button onclick="event.stopPropagation();rerunHist('${h.id}')">${esc(t('Re-run'))}</button><button onclick="event.stopPropagation();delHist('${h.id}')">${esc(t('Delete'))}</button></div></div>`}).join(''):`<p style="color:var(--mut);padding:8px">${esc(t(hist.length?'No matches':'No history yet'))}</p>`}
function toggleHist(on){const h=$('#hist');const open=on===undefined?!h.classList.contains('on'):on;h.classList.toggle('on',open);if(open){renderHist()}}
function viewHist(id){const h=hist.find(x=>x.id==id);if(!h)return;hsel=id;pick(h.cmd,false,true);
document.querySelectorAll('#f input').forEach(i=>{if(i.name=='_admin'){if(!i.disabled)i.checked=!!h.admin}else if(h.values&&h.values[i.name]!==undefined)i.value=h.values[i.name]});
raw=h.out;idle=false;$('#out').innerHTML=ansi(raw);$('#out').scrollTop=0;
$('#st').textContent=t('Viewing history')+': '+new Date(h.ts).toLocaleString(lang=='zh'?'zh-CN':'en-US');renderHist()}
function rerunHist(id){viewHist(id);if(!$('#run').disabled)run()}
function delHist(id){hist=hist.filter(h=>h.id!=id);saveHist();renderHist()}
function clearHist(){if(hist.length&&confirm(t('Clear all history?'))){hist=[];hsel=null;saveHist();renderHist()}}
const MOD=/Mac|iPhone|iPad/.test(navigator.platform)?'⌘':'Ctrl';
const SC=[[[MOD+' + Enter'],'Run the current tool'],[['Esc'],'Stop a running command; otherwise leave the input box'],
[['j','↓'],'Previous / next tool'],[['1'],'Jump to tool 1–9'],[['/'],'Focus the first input'],[['Enter'],'Run (when not typing)'],
[['c'],'Copy output'],[['s'],'Save output'],[['l'],'Switch language'],[['t'],'Switch theme'],[['h'],'Show / hide history'],[['?'],'Show / hide this help']];
SC[2][0]=['j / ↓  ·  k / ↑'];SC[3][0]=['1 … 9'];
function toggleHelp(on){const h=$('#help');const open=on===undefined?!h.classList.contains('on'):on;
if(open){$('#helph').textContent='⌨ '+t('Keyboard shortcuts');$('#helpt').innerHTML=SC.map(([k,d])=>`<tr><td>${k.map(x=>'<kbd>'+x.replace(/&/g,'&amp;').replace(/</g,'&lt;')+'</kbd>').join('')}</td><td>${t(d)}</td></tr>`).join('')}
h.classList.toggle('on',open)}
function go(delta,abs){const i=CMDS.findIndex(c=>c.id==(cur&&cur.id));const n=abs!==undefined?abs:Math.max(0,Math.min(CMDS.length-1,i+delta));if(CMDS[n]){pick(CMDS[n].id,false,true);$('#b_'+CMDS[n].id).scrollIntoView({block:'nearest'})}}
document.addEventListener('keydown',e=>{
const typing=/^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)&&e.target.type!='checkbox';
const helpOpen=$('#help').classList.contains('on'),histOpen=$('#hist').classList.contains('on');
if(e.key=='Escape'){if(helpOpen){toggleHelp(false)}else if(histOpen&&$('#stop').disabled){toggleHist(false)}else if(!$('#stop').disabled){stop()}else if(typing){e.target.blur()}else return;e.preventDefault();return}
if((e.metaKey||e.ctrlKey)&&e.key=='Enter'){if(!$('#run').disabled){e.preventDefault();run()}return}
if(e.metaKey||e.ctrlKey||e.altKey||typing)return;
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
else if(k=='h')toggleHist();
else if(k=='l')toggleLang();
else if(k=='t')toggleTheme();
else used=false;
if(used)e.preventDefault()});
pick('quick');applyLang();
</script></body></html>"""

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=int, default=8765, help="0 = random free port; falls back to random if busy"); ap.add_argument("--no-open", action="store_true")
    a = ap.parse_args()
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    except OSError:  # port busy (e.g. a second instance): use any free port
        srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    url = "http://127.0.0.1:%d/" % srv.server_address[1]
    print("NetDoctor GUI:", url, "(Ctrl-C to quit)")
    if not a.no_open: threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__":
    main()
