#!/bin/bash
# Hermetic tests for the netdoctor CLI: no network, no sudo, nothing written outside a temp dir.
# Run:  /bin/bash scripts/test-cli.sh      (works with the stock macOS bash 3.2)
# Exit code 0 = all passed. Every failure prints what was expected and what came out.
#
# The functions are tested by sourcing `netdoctor` as a library (NETDOCTOR_SOURCE_ONLY=1) and putting fake
# curl / ifconfig / ipconfig / route commands first in PATH, so the results do not depend on the machine.
cd "$(dirname "$0")/.." || exit 1
ND=./netdoctor
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NETDOCTOR_LANG=en NETDOCTOR_NOSUDO=1; unset NETDOCTOR_COLOR
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; return 0; }
strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# expect NAME WANT_RC SUBSTRING COMMAND...   (SUBSTRING may be empty)
expect() {
  local name=$1 want=$2 sub=$3 out rc; shift 3
  out=$("$@" </dev/null 2>&1); rc=$?; out=$(printf '%s' "$out" | strip)
  if [ "$rc" != "$want" ]; then fail "$name" "exit code $rc, wanted $want. Output: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  elif [ -n "$sub" ] && ! printf '%s' "$out" | grep -qF -- "$sub"; then fail "$name" "output lacks '$sub'. Got: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  else pass; fi
}
# lib NAME WANT_RC SUBSTRING 'shell code run after sourcing netdoctor'   (fake commands in $T/bin come first)
lib() {
  local name=$1 want=$2 sub=$3 code=$4 out rc
  out=$(PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; $code" </dev/null 2>&1); rc=$?; out=$(printf '%s' "$out" | strip)
  if [ "$rc" != "$want" ]; then fail "$name" "exit code $rc, wanted $want. Output: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  elif [ -n "$sub" ] && ! printf '%s' "$out" | grep -qF -- "$sub"; then fail "$name" "output lacks '$sub'. Got: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  else pass; fi
}
# lib_not NAME 'code' NEEDLE   the output must NOT contain NEEDLE
lib_not() {
  local out; out=$(PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; $2" </dev/null 2>&1)
  if printf '%s' "$out" | grep -qF -- "$3"; then fail "$1" "output still contains '$3'"; else pass; fi
}

mkdir -p "$T/bin"

# ---- 1. command line: argument validation and basics ---------------------------------------------
expect "version"                    0 "netdoctor "          /bin/bash $ND version
expect "unknown command"            2 "Unknown command"     /bin/bash $ND nosuchcommand
expect "help lists dhcp"            0 "dhcp"                /bin/bash $ND help
expect "ports: port 0"              1 "out of range"        /bin/bash $ND ports 127.0.0.1 0
expect "ports: port 70000"          1 "out of range"        /bin/bash $ND ports 127.0.0.1 70000
expect "ports: reversed range"      1 "Invalid port range"  /bin/bash $ND ports 127.0.0.1 100-50
expect "ports: letters"             1 "Invalid port list"   /bin/bash $ND ports 127.0.0.1 a,b
expect "ports: too many"            1 "Too many ports"      /bin/bash $ND ports 127.0.0.1 1-65535
expect "ports: bad host"            1 "Invalid host"        /bin/bash $ND ports "bad host" 80
expect "ports: shell metachar"      1 "Invalid host"        /bin/bash $ND ports 'x;ls' 80
expect "port: not a number"         1 "must be a number"    /bin/bash $ND port 127.0.0.1 abc
expect "port: out of range"         1 "must be a number"    /bin/bash $ND port 127.0.0.1 99999
expect "dns: space in domain"       1 "Invalid domain"      /bin/bash $ND dns "a b"
expect "dns: injection"             1 "Invalid domain"      /bin/bash $ND dns 'x;ls'
expect "dnsbench: bad domain"       1 "Invalid domain"      /bin/bash $ND dnsbench "bad host"
expect "tcpping: bad port"          1 "Port must be"        /bin/bash $ND tcpping 127.0.0.1 99999
expect "mtu: IPv6 unsupported"      1 "IPv4 only"           /bin/bash $ND mtu ::1
expect "ping: no host"              1 "Usage"               /bin/bash $ND ping
expect "route: no host"             1 "Usage"               /bin/bash $ND route
expect "http: no URL"               1 "Usage"               /bin/bash $ND http
expect "tls: no host"               1 "Usage"               /bin/bash $ND tls
# Elevation must be refused, never attempted: CI machines often have passwordless sudo, which would make
# these commands really run (fixdns would flush the DNS cache, capture would sniff packets forever).
# A fake `sudo` that always fails keeps the test hermetic; skip when running as root (nothing to refuse).
printf '#!/bin/sh\nexit 1\n' > "$T/bin/sudo"; chmod +x "$T/bin/sudo"
if [ "$(id -u)" != 0 ]; then
  expect "fixdns: no admin rights"  1 "Administrator rights" env PATH="$T/bin:$PATH" /bin/bash $ND fixdns
  expect "capture: no admin rights" 1 "Administrator rights" env PATH="$T/bin:$PATH" /bin/bash $ND capture
fi
NETDOCTOR_LANG=zh expect "zh: ports error is Chinese" 1 "端口超出范围" /bin/bash $ND ports 127.0.0.1 0
# source-only mode must define functions and run nothing
expect "source-only runs nothing"   0 ""                    /bin/bash -c "NETDOCTOR_SOURCE_ONLY=1; . $ND; type host_matches >/dev/null"

# ---- 2. host name matching (tls) -------------------------------------------------------------------
t() { lib "host_matches: $1 vs ${*:3}" "$2" "" "host_matches $(printf '%q ' "$1" "${@:3}")"; }
t www.example.com   0 "*.example.com"
t example.com       1 "*.example.com"
t a.b.example.com   1 "*.example.com"
t EXAMPLE.com       0 example.com
t evil-example.com  1 "*.example.com" example.org
t foo.example.org   0 example.net "*.example.org"
t localhost         1 "*.localhost"

# ---- 3. human_secs ----------------------------------------------------------------------------------
lib "human_secs minutes" 0 "5 minutes" "human_secs 300"
lib "human_secs hours"   0 "3 hours"   "human_secs 10800"
lib "human_secs negative" 0 "3 hours"  "human_secs -10800"
lib "human_secs days"    0 "2 days"    "human_secs 200000"

# ---- 4. report redaction -----------------------------------------------------------------------------
HS=$(hostname -s); HN=$(hostname); U=$(id -un)
cat > "$T/sample.txt" <<E
Darwin $HN 27.2.0 Darwin Kernel
  IPv6: 2603:8000:abcd:1234:aaaa:bbbb:cccc:dddd
  MAC: a4:77:33:1b:2c:3d
  Search domains: corp.example.com lan
  VPN / tunnels: utun4=100.69.255.68
  Public IP: 71.83.193.52  United States Spectrum
  Wi-Fi: Current Wi-Fi Network: Max's Home 5G
    SSID           : Max's Home 5G
    BSSID          : a4:77:33:1b:2c:3d
   	inet6 2603:8000:abcd:1234:aaaa:bbbb:cccc:dddd prefixlen 64
   	inet6 fe80::1c2d:3e4f:5a6b:7c8d%en0 prefixlen 64
   	ether a4:77:33:1b:2c:3d
== Public IP ==
   71.83.193.52  United States Spectrum
[ OK ] IPv4  71.83.193.52
log: /Users/$U/Documents/x
keep: gateway 192.168.0.1 and DNS 1.1.1.1 and 12 ms
E
for needle in 71.83.193.52 a4:77:33:1b:2c:3d "Max's Home 5G" 2603:8000 100.69.255.68 corp.example.com 1c2d:3e4f "/Users/$U" "$HN"; do
  lib_not "redact hides: $needle" "redact_filter < $T/sample.txt" "$needle"
done
lib "redact keeps private gateway / public DNS / latency" 0 "gateway 192.168.0.1 and DNS 1.1.1.1 and 12 ms" "redact_filter < $T/sample.txt"
lib "redact keeps the Wi-Fi signal values"               0 "<redacted>"                                     "redact_filter < $T/sample.txt"

# ---- 5. captive portal probe (fake curl) ------------------------------------------------------------
cat > "$T/bin/curl" <<'E'
#!/bin/sh
# Fake curl. ND_PORTAL=yes|off|ok drives captive.apple.com; ND_SKEW / ND_AGE drive the Date / Age headers.
all="$*"
case "$all" in
  *captive.apple.com*)
    case "$ND_PORTAL" in
      yes) case "$all" in *redirect_url*) printf 'http://login.cafe.example/p';; *) printf '<html>Please sign in. Success stories inside</html>';; esac;;
      off) exit 6;;
      *)   case "$all" in *redirect_url*) printf '';; *) printf '<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>';; esac;;
    esac; exit 0;;
  *"-sI"*)
    [ -z "$ND_SKEW" ] && exit 6
    case "$ND_SKEW" in -*) v="+${ND_SKEW#-}";; *) v="-${ND_SKEW}";; esac
    d=$(LC_ALL=C date -u -v"${v}"S '+%a, %d %b %Y %H:%M:%S GMT')
    printf 'HTTP/1.1 301 Moved\r\nDate: %s\r\n' "$d"; [ -n "$ND_AGE" ] && printf 'Age: %s\r\n' "$ND_AGE"; printf '\r\n'; exit 0;;
esac
exit 7
E
chmod +x "$T/bin/curl"
lib "captive: normal"                       0 "ok"      "ND_PORTAL=ok;  export ND_PORTAL; captive_probe; echo \$CAP_STATE"
lib "captive: login page"                   0 "portal"  "ND_PORTAL=yes; export ND_PORTAL; captive_probe; echo \$CAP_STATE"
lib "captive: login page redirect url"      0 "login.cafe.example" "ND_PORTAL=yes; export ND_PORTAL; captive_probe; echo \$CAP_REDIR"
lib "captive: offline"                      0 "offline" "ND_PORTAL=off; export ND_PORTAL; captive_probe; echo \$CAP_STATE"
lib "captive command: portal exits 1"       1 "Captive portal suspected" "ND_PORTAL=yes; export ND_PORTAL; cmd_captive"
lib "captive command: ok exits 0"           0 "No captive portal"        "ND_PORTAL=ok;  export ND_PORTAL; cmd_captive"
lib "captive command: offline exits 1"      1 "Could not reach"          "ND_PORTAL=off; export ND_PORTAL; cmd_captive"

# ---- 6. clock skew (fake curl) ----------------------------------------------------------------------
skew_between() { # name, env, low, high
  local out; out=$(PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c "$2; export ND_SKEW ND_AGE; . $ND; clock_skew" </dev/null 2>&1)
  if [ -n "$out" ] && [ "$out" -ge "$3" ] 2>/dev/null && [ "$out" -le "$4" ] 2>/dev/null; then pass; else fail "$1" "skew '$out' not in $3..$4"; fi
}
skew_between "clock: accurate server"            "ND_SKEW=0"                -3 3
skew_between "clock: Mac 3 h ahead"              "ND_SKEW=10800"            10797 10803
skew_between "clock: Mac 3 h behind"             "ND_SKEW=-10800"           -10803 -10797
skew_between "clock: cached reply, Age corrects" "ND_SKEW=7200 ND_AGE=7200" -3 3
lib "clock: no Date header gives no answer" 0 "[]" "ND_SKEW=; export ND_SKEW; echo \"[\$(clock_skew)]\""

# ---- 7. DHCP (fake ifconfig / ipconfig / route) -----------------------------------------------------
cat > "$T/bin/ifconfig" <<'E'
#!/bin/sh
case "$ND_MODE" in
  selfassigned) echo "en0: flags=8863<UP> mtu 1500"; printf '\tinet 169.254.12.34 netmask 0xffff0000\n';;
  noip)         echo "en0: flags=8863<UP> mtu 1500"; printf '\tstatus: inactive\n';;
  *)            echo "en0: flags=8863<UP> mtu 1500"; printf '\tinet 192.168.0.230 netmask 0xfffffc00\n';;
esac
E
cat > "$T/bin/route" <<'E'
#!/bin/sh
case "$ND_MODE" in
  selfassigned) exit 1;;
  vpn) printf '   route to: default\n    gateway: 10.8.0.1\n  interface: en0\n';;
  *)   printf '   route to: default\n    gateway: 192.168.0.1\n  interface: en0\n';;
esac
E
cat > "$T/bin/ipconfig" <<'E'
#!/bin/sh
case "$ND_MODE" in manual) exit 1;; esac
lease=0xa8c0; [ "$ND_MODE" = short ] && lease=0x12c
cat <<X
op = BOOTREPLY
server_identifier (ip): 192.168.0.1
lease_time (uint32): $lease
subnet_mask (ip): 255.255.252.0
router (ip_mult): {192.168.0.1}
domain_name_server (ip_mult): {192.168.0.1}
domain_name (string): lan
X
E
chmod +x "$T/bin/ifconfig" "$T/bin/route" "$T/bin/ipconfig"
lib "dhcp: normal lease"             0 "DHCP server    192.168.0.1" "ND_MODE=ok; export ND_MODE; cmd_dhcp"
lib "dhcp: lease time shown"         0 "12 h 0 min"               "ND_MODE=ok; export ND_MODE; cmd_dhcp"
lib "dhcp: gateway matches"          0 "matches the router"       "ND_MODE=ok; export ND_MODE; cmd_dhcp"
lib "dhcp: self-assigned fails"      1 "self-assigned address 169.254.12.34" "ND_MODE=selfassigned; export ND_MODE; cmd_dhcp"
lib "dhcp: no address fails"         1 "no IPv4 address"          "ND_MODE=noip; export ND_MODE; cmd_dhcp"
lib "dhcp: manual address warns"     0 "No DHCP lease"            "ND_MODE=manual; export ND_MODE; cmd_dhcp"
lib "dhcp: short lease warns"        0 "Very short lease"         "ND_MODE=short; export ND_MODE; cmd_dhcp"
lib "dhcp: VPN gateway mismatch"     0 "not the router the DHCP server offered" "ND_MODE=vpn; export ND_MODE; cmd_dhcp"
lib "doctor: self-assigned = DHCP failed" 1 "DHCP failed" "ND_MODE=selfassigned; export ND_MODE; cmd_doctor"

# ---- result ------------------------------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then echo "all $PASS tests passed"; exit 0; fi
echo "$FAIL failed, $PASS passed"; exit 1
