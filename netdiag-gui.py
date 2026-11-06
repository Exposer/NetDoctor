#!/usr/bin/env python3
"""NetDiag GUI - 本机网页界面 (仅标准库, 仅监听 127.0.0.1)。
用法: python3 netdiag-gui.py [--port 8765] [--no-open]
"""
import argparse, json, os, re, secrets, shlex, subprocess, sys, threading, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
NETDIAG = os.path.join(HERE, "netdiag")
TOKEN = secrets.token_urlsafe(16)

# admin: True=必须管理员权限, "optional"=可勾选, False=不需要
COMMANDS = [
 {"id":"quick","label":"一键体检","icon":"🩺","desc":"网关 → 外网IP → DNS → HTTP 逐层检查并给出判读","inputs":[]},
 {"id":"wifi","label":"Wi-Fi","icon":"📶","desc":"SSID、信号、噪声、信道、速率","inputs":[],"admin":"optional"},
 {"id":"dns","label":"DNS 对比","icon":"🔎","desc":"系统与多家公共 DNS 的解析结果与耗时","inputs":[{"name":"domain","label":"域名","ph":"example.com","req":True}]},
 {"id":"http","label":"HTTP 耗时","icon":"🌐","desc":"DNS/TCP/TLS/首字节/总耗时分解","inputs":[{"name":"url","label":"URL","ph":"https://example.com","req":True}]},
 {"id":"ping","label":"Ping","icon":"📡","desc":"丢包与延迟统计","inputs":[{"name":"host","label":"主机","ph":"1.1.1.1","req":True},{"name":"count","label":"次数","ph":"20","def":"20"}]},
 {"id":"route","label":"路由/路径","icon":"🧭","desc":"走哪块网卡/VPN + mtr/traceroute 逐跳","inputs":[{"name":"host","label":"主机","ph":"example.com","req":True}],"admin":"optional"},
 {"id":"port","label":"端口检测","icon":"🚪","desc":"TCP 端口是否可连","inputs":[{"name":"host","label":"主机","ph":"example.com","req":True},{"name":"port","label":"端口","ph":"443","req":True}]},
 {"id":"tls","label":"TLS 证书","icon":"🔒","desc":"证书、协议、有效期","inputs":[{"name":"host","label":"主机","ph":"example.com","req":True},{"name":"port","label":"端口","ph":"443"}]},
 {"id":"mtu","label":"MTU 探测","icon":"📏","desc":"路径 MTU,排查 VPN/大包丢失","inputs":[{"name":"host","label":"主机","ph":"1.1.1.1"}]},
 {"id":"speed","label":"测速","icon":"⚡","desc":"networkQuality 带宽与响应性 (约 20 秒)","inputs":[]},
 {"id":"conns","label":"连接/监听","icon":"🔌","desc":"按进程列出监听端口与连接","inputs":[],"admin":True},
 {"id":"proxy","label":"代理/VPN","icon":"🛡️","desc":"系统代理、环境变量、VPN 与 utun","inputs":[]},
 {"id":"fixdns","label":"刷新 DNS","icon":"🧹","desc":"清除 DNS 缓存并重启 mDNSResponder","inputs":[],"admin":True},
 {"id":"report","label":"导出报告","icon":"📄","desc":"保存综合报告到桌面","inputs":[]},
 {"id":"tools","label":"工具检查","icon":"🧰","desc":"系统与第三方工具安装情况","inputs":[]},
]
BY_ID = {c["id"]: c for c in COMMANDS}
ARG_RE = re.compile(r"^[A-Za-z0-9._:/?&=%@~+,\[\]-]{1,300}$")

def build_args(spec, values):
    args = []
    for i in spec["inputs"]:
        v = (values.get(i["name"]) or i.get("def") or "").strip()
        if not v:
            if i.get("req"):
                raise ValueError("缺少参数: " + i["label"])
            break  # 位置参数后面的也不再传
        if v.startswith("-") or not ARG_RE.match(v):
            raise ValueError("参数不合法: " + i["label"])
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
            page = HTML.replace("__TOKEN__", TOKEN).replace("__CMDS__", json.dumps(COMMANDS, ensure_ascii=False))
            return self._send(200, page)
        self._send(404, "not found")

    def do_POST(self):
        if not self._ok_host() or self.headers.get("X-Token") != TOKEN:
            return self._send(403, "forbidden")
        if self.path == "/quit":
            self._send(200, "bye"); threading.Thread(target=self.server.shutdown, daemon=True).start(); return
        if self.path != "/run": return self._send(404, "not found")
        try:
            n = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(n) or b"{}")
            spec = BY_ID.get(req.get("cmd"))
            if not spec: raise ValueError("未知命令")
            args = build_args(spec, req.get("values") or {})
            admin = spec.get("admin")
            use_admin = admin is True or (admin == "optional" and req.get("admin"))
        except Exception as e:
            return self._send(400, "错误: %s\n" % e, "text/plain; charset=utf-8")

        env = dict(os.environ, NETDIAG_COLOR="1", LANG="en_US.UTF-8")
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:" + env.get("PATH", "")
        self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store"); self.end_headers()
        if use_admin and sys.platform == "darwin":
            inner = "HOME=%s PATH=%s NETDIAG_COLOR=1 %s 2>&1" % (
                shlex.quote(os.path.expanduser("~")), shlex.quote(env["PATH"]),
                " ".join(shlex.quote(x) for x in [NETDIAG, spec["id"]] + args))
            inner = inner.replace("\\", "\\\\").replace('"', '\\"')
            cmd = ["osascript", "-e", 'do shell script "%s" with administrator privileges' % inner]
            self.wfile.write("(等待系统弹出管理员密码框…)\n".encode()); self.wfile.flush()
        else:
            cmd = [NETDIAG, spec["id"]] + args
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=env, bufsize=0)
        except Exception as e:
            self.wfile.write(("启动失败: %s\n" % e).encode()); return
        try:
            while True:
                chunk = p.stdout.read1(4096) if hasattr(p.stdout, "read1") else p.stdout.read(4096)
                if not chunk: break
                self.wfile.write(chunk); self.wfile.flush()
            rc = p.wait()
            self.wfile.write(("\n\x1b[2m[退出码 %d]\x1b[0m\n" % rc).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass  # 用户点了停止
        finally:
            if p.poll() is None:
                p.kill()

HTML = r"""<!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NetDiag 网络诊断</title><style>
:root{--bg:#f5f5f7;--card:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#e0e0e5;--acc:#0071e3;--term:#14161a;--termfg:#d8dde6}
@media(prefers-color-scheme:dark){:root{--bg:#1c1c1e;--card:#2c2c2e;--fg:#f5f5f7;--mut:#98989d;--line:#3a3a3c;--acc:#0a84ff;--term:#0b0c0e}}
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
</style></head><body>
<nav><h1>🛰️ NetDiag</h1><div id="list"></div><button onclick="quit()" style="margin-top:14px;color:var(--mut)">⏻ 退出</button></nav>
<main><div class="card"><h2 id="t"></h2><p id="d"></p><form id="f"></form></div>
<div class="bar"><span class="sp" id="st" style="color:var(--mut)"></span><button class="btn sec" onclick="copy()">复制</button><button class="btn sec" onclick="save()">保存</button><button class="btn sec" id="stop" onclick="stop()" disabled>停止</button></div>
<pre id="out">选择左侧工具,点“运行”。建议先跑「一键体检」。</pre></main>
<script>
const TOKEN="__TOKEN__",CMDS=__CMDS__;let cur=null,ctl=null,raw="";
const $=s=>document.querySelector(s);
CMDS.forEach(c=>{const b=document.createElement('button');b.innerHTML=`<span>${c.icon}</span><span>${c.label}</span>`;b.onclick=()=>pick(c.id);b.id='b_'+c.id;$('#list').append(b)});
function pick(id){cur=CMDS.find(c=>c.id==id);document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.id=='b_'+id));
$('#t').textContent=cur.icon+' '+cur.label;$('#d').textContent=cur.desc;const f=$('#f');f.innerHTML='';
cur.inputs.forEach(i=>{const l=document.createElement('label');l.textContent=i.label+(i.req?' *':'');const x=document.createElement('input');x.type='text';x.name=i.name;x.placeholder=i.ph||'';x.value=i.def||'';l.append(x);f.append(l)});
if(cur.admin===true||cur.admin==='optional'){const l=document.createElement('label');l.className='chk';l.innerHTML=`<input type="checkbox" name="_admin" ${cur.admin===true?'checked disabled':''}>需要管理员权限${cur.admin===true?'':'(信息更完整)'}`;f.append(l)}
const r=document.createElement('button');r.className='btn';r.id='run';r.textContent='运行';r.type='submit';f.append(r);
f.onsubmit=e=>{e.preventDefault();run()};const first=f.querySelector('input[type=text]');first&&first.focus()}
function ansi(s){const esc=t=>t.replace(/&/g,'&amp;').replace(/</g,'&lt;');let open=0,o='';
return esc(s).replace(/\x1b\[(\d+)m/g,(m,c)=>{let r='';if(c=='0'||c=='22'){r='</span>'.repeat(open);open=0;return r}
const k={1:'b',31:'r',32:'g',33:'y',2:'d'}[c];if(!k)return '';open++;return `<span class="${k}">`})+'</span>'.repeat(open)}
async function run(){const values={};let admin=false;$('#f').querySelectorAll('input').forEach(i=>{if(i.name=='_admin')admin=i.checked;else values[i.name]=i.value});
ctl=new AbortController();raw='';$('#out').textContent='';$('#run').disabled=true;$('#stop').disabled=false;$('#st').textContent='运行中…';const t0=Date.now();
try{const r=await fetch('/run',{method:'POST',headers:{'X-Token':TOKEN},body:JSON.stringify({cmd:cur.id,values,admin}),signal:ctl.signal});
const rd=r.body.getReader(),dc=new TextDecoder();for(;;){const {done,value}=await rd.read();if(done)break;raw+=dc.decode(value,{stream:true});$('#out').innerHTML=ansi(raw);$('#out').scrollTop=1e9}
$('#st').textContent='完成,用时 '+((Date.now()-t0)/1000).toFixed(1)+'s'}catch(e){$('#st').textContent=e.name=='AbortError'?'已停止':'失败: '+e}
$('#run').disabled=false;$('#stop').disabled=true}
function stop(){ctl&&ctl.abort()}
const plain=()=>raw.replace(/\x1b\[\d+m/g,'');
function copy(){navigator.clipboard.writeText(plain());$('#st').textContent='已复制'}
function save(){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([plain()]));a.download=`netdiag-${cur?cur.id:'out'}-${Date.now()}.txt`;a.click()}
async function quit(){if(confirm('退出 NetDiag 服务?')){await fetch('/quit',{method:'POST',headers:{'X-Token':TOKEN}}).catch(()=>{});document.body.innerHTML='<p style="margin:40px">已退出,可关闭此页面。</p>'}}
pick('quick');
</script></body></html>"""

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--port", type=int, default=0); ap.add_argument("--no-open", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    url = "http://127.0.0.1:%d/" % srv.server_address[1]
    print("NetDiag GUI:", url, "(Ctrl-C 退出)")
    if not a.no_open: threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__":
    main()
