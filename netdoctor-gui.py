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
</style><script>try{var th=localStorage.getItem('nd_theme');if(th==='light'||th==='dark')document.documentElement.dataset.theme=th}catch(e){}</script></head><body>
<nav><h1>🛰️ NetDoctor</h1><div id="list"></div><button onclick="toggleTheme()" id="theme" style="margin-top:14px;color:var(--mut)"></button><button onclick="toggleLang()" id="lang" style="color:var(--mut)"></button><button onclick="quit()" style="color:var(--mut)">⏻ <span data-i="Quit">Quit</span></button></nav>
<main><div class="card"><h2 id="t"></h2><p id="d"></p><form id="f"></form></div>
<div class="bar"><span class="sp" id="st" style="color:var(--mut)"></span><button class="btn sec" onclick="copy()" data-i="Copy">Copy</button><button class="btn sec" onclick="save()" data-i="Save">Save</button><button class="btn sec" id="stop" onclick="stop()" data-i="Stop" disabled>Stop</button></div>
<pre id="out"></pre></main>
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
applyTheme();if(cur)pick(cur.id,true)}
function toggleLang(){lang=lang=='zh'?'en':'zh';try{localStorage.setItem('nd_lang',lang)}catch(e){}applyLang()}
function pick(id,keep){const old={};if(keep)document.querySelectorAll('#f input').forEach(i=>{old[i.name]=i.type=='checkbox'?i.checked:i.value});cur=CMDS.find(c=>c.id==id);document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_'+id));
$('#t').textContent=cur.icon+' '+t(cur.label);$('#d').textContent=t(cur.desc);const f=$('#f');f.innerHTML='';
cur.inputs.forEach(i=>{const l=document.createElement('label');l.textContent=t(i.label)+(i.req?' *':'');const x=document.createElement('input');x.type='text';x.name=i.name;x.placeholder=i.ph||'';x.value=(keep&&old[i.name]!==undefined)?old[i.name]:(i.def||'');l.append(x);f.append(l)});
if(cur.admin===true||cur.admin==='optional'){const l=document.createElement('label');l.className='chk';l.innerHTML=`<input type="checkbox" name="_admin" ${cur.admin===true?'checked disabled':''}>${t('Requires administrator rights')}${cur.admin===true?'':' '+t('(fuller details)')}`;f.append(l);if(keep&&old._admin!==undefined&&cur.admin!==true)l.querySelector('input').checked=old._admin}
const r=document.createElement('button');r.className='btn';r.id='run';r.textContent=t('Run');r.type='submit';f.append(r);
f.onsubmit=e=>{e.preventDefault();run()};const first=f.querySelector('input[type=text]');first&&first.focus()}
function ansi(s){const esc=t=>t.replace(/&/g,'&amp;').replace(/</g,'&lt;');let open=0,o='';
return esc(s).replace(/\x1b\[(\d+)m/g,(m,c)=>{let r='';if(c=='0'||c=='22'){r='</span>'.repeat(open);open=0;return r}
const k={1:'b',31:'r',32:'g',33:'y',2:'d'}[c];if(!k)return '';open++;return `<span class="${k}">`})+'</span>'.repeat(open)}
async function run(){const values={};let admin=false;$('#f').querySelectorAll('input').forEach(i=>{if(i.name=='_admin')admin=i.checked;else values[i.name]=i.value});
ctl=new AbortController();raw='';idle=false;$('#out').textContent='';$('#run').disabled=true;$('#stop').disabled=false;$('#st').textContent=t('Running…');const t0=Date.now();
try{const r=await fetch('/run',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({cmd:cur.id,values,admin,lang}),signal:ctl.signal});
const rd=r.body.getReader(),dc=new TextDecoder();for(;;){const {done,value}=await rd.read();if(done)break;raw+=dc.decode(value,{stream:true});$('#out').innerHTML=ansi(raw);$('#out').scrollTop=1e9}
$('#st').textContent=fmt('Done in %ss',((Date.now()-t0)/1000).toFixed(1))}catch(e){$('#st').textContent=e.name=='AbortError'?t('Stopped'):t('Failed')+': '+e}
$('#run').disabled=false;$('#stop').disabled=true}
function stop(){ctl&&ctl.abort()}
const plain=()=>raw.replace(/\x1b\[\d+m/g,'');
function copy(){navigator.clipboard.writeText(plain());$('#st').textContent=t('Copied')}
function save(){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([plain()]));a.download=`netdoctor-${cur?cur.id:'out'}-${Date.now()}.txt`;a.click()}
async function quit(){if(confirm(t('Quit the NetDoctor service?'))){await fetch('/quit',{method:'POST',headers:{'X-Token':TOKEN}}).catch(()=>{});document.body.innerHTML='<p style="margin:40px">'+t('Quit. You can close this page.')+'</p>'}}
pick('quick');applyLang();
</script></body></html>"""

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=int, default=0); ap.add_argument("--no-open", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    url = "http://127.0.0.1:%d/" % srv.server_address[1]
    print("NetDoctor GUI:", url, "(Ctrl-C to quit)")
    if not a.no_open: threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__":
    main()
