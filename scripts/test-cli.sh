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
V6S="$T/v6sample.txt"; printf '%s\n' '== IPv6 router (default route) ==' '  fe80::9683:c4ff:fea9:72d6%en0 (en0)' '  IPv6 DNS servers: fd7a:115c:a1e0::53 fd09:3040:5f16::1' '[ OK ] The IPv6 router answers (avg 0.9 ms)' > "$V6S"
for needle in "9683:c4ff" "fea9:72d6" "fd7a:115c" "fd09:3040"; do
  lib_not "redact hides in the IPv6 section: $needle" "redact_filter < $V6S" "$needle"
done
V6T="$T/v6ula.txt"; printf '%s\n' '  DNS: 100.100.100.100 fd7a:115c:a1e0::53 192.168.0.1 fd09:3040:5f16::1' '    nameserver[1] : fd09:3040:5f16::1' > "$V6T"
for needle in "fd7a" "fd09" "115c"; do lib_not "redact hides a ULA anywhere: $needle" "redact_filter < $V6T" "$needle"; done
lib "redact keeps the other addresses next to a ULA" 0 "192.168.0.1" "redact_filter < $V6T"
lib_not "redact: a word that merely contains fd is untouched" "echo 'config fdisk: fd12 is fine' | redact_filter" "<redacted>"
lib "redact keeps the IPv6 router verdict and interface" 0 "The IPv6 router answers (avg 0.9 ms)" "redact_filter < $V6S"
lib "redact keeps the interface of the IPv6 router"       0 "%en0 (en0)"                       "redact_filter < $V6S"
lib "redact does not double-mark link-local addresses" 0 "fe80::<redacted>%en0" "redact_filter < $V6S"
lib_not "redact does not stack placeholders" "redact_filter < $V6S" "<redacted><redacted>"
lib "redact keeps private gateway / public DNS / latency" 0 "gateway 192.168.0.1 and DNS 1.1.1.1 and 12 ms" "redact_filter < $T/sample.txt"
lib "redact keeps the Wi-Fi signal values"               0 "<redacted>"                                     "redact_filter < $T/sample.txt"

# 4b. shapes the first version missed: the overview's "Wi-Fi: <name>" row, raw JSON without jq, IPv6 + country
cat > "$T/sample2.txt" <<'X'
  Wi-Fi: Max Home 5G
  Public IP: {"ip":"71.83.193.52","city":"Springfield","latitude":39.78}
{"ip":"71.83.193.52","country":"United States","isp":"Spectrum","latitude":39.78}
   2603:8000:abcd::1  United States Spectrum
  note: connected to Max Home 5G via 71.83.193.52 and 2603:8000:abcd::1
X
RL=$'Max Home 5G\n71.83.193.52\n2603:8000:abcd::1'
for needle in "Max Home 5G" 71.83.193.52 Springfield 39.78 2603:8000; do
  lib_not "redact (exact values) hides: $needle" "REDACT_LITERALS='$RL' redact_filter < $T/sample2.txt" "$needle"
done
for needle in Springfield 39.78 2603:8000; do   # even without the exact values, the line shapes must be covered
  lib_not "redact (shapes only) hides: $needle" "grep -v '^  note' $T/sample2.txt | redact_filter" "$needle"
done
# a host with only an AAAA record must not be reported as "cannot resolve" (macOS ping cannot resolve it)
printf '#!/bin/sh\necho "name: v6only.example"; echo "ipv6_address: 2001:db8::1"\n' > "$T/bin/dscacheutil"; chmod +x "$T/bin/dscacheutil"
lib "cannot_resolve: AAAA-only host resolves" 1 "" "cannot_resolve v6only.example"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/dscacheutil"
lib "cannot_resolve: unknown host"           0 "" "cannot_resolve nosuch.example"
rm -f "$T/bin/dscacheutil"

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

# ---- 8. speed verdict, MAC vendor -------------------------------------------------------------------
SP_BAD='Uplink capacity: 24 Mbps\nDownlink capacity: 496 Mbps\nUplink Responsiveness: Low (1.8 seconds | 32 RPM)\nDownlink Responsiveness: High (42 milliseconds | 1410 RPM)'
SP_OK='Uplink capacity: 30 Mbps\nDownlink capacity: 300 Mbps\nUplink Responsiveness: High (30 milliseconds | 1900 RPM)\nDownlink Responsiveness: High (40 milliseconds | 1500 RPM)'
SP_MID='Uplink capacity: 30 Mbps\nDownlink capacity: 300 Mbps\nUplink Responsiveness: Medium (200 milliseconds | 600 RPM)\nDownlink Responsiveness: High (40 milliseconds | 1500 RPM)'
lib "speed: upload bufferbloat"   0 "Bufferbloat: latency under upload load" "speed_verdict \"\$(printf '$SP_BAD')\""
lib "speed: good responsiveness"  0 "Responsiveness is good"                  "speed_verdict \"\$(printf '$SP_OK')\""
lib "speed: fair responsiveness"  0 "Responsiveness is fair"                  "speed_verdict \"\$(printf '$SP_MID')\""
lib "speed: single Responsiveness line (fair)" 0 "Responsiveness is fair (879 RPM)" "speed_verdict 'Downlink capacity: 521 Mbps
Uplink capacity: 21 Mbps
Responsiveness: Medium (68 milliseconds | 879 RPM)'"
lib "speed: single Responsiveness line (bad)"  0 "Bufferbloat: latency under network load is very high (120 RPM)" "speed_verdict 'Uplink capacity: 21 Mbps
Responsiveness: Low (500 milliseconds | 120 RPM)'"
lib "speed: unparseable output"   0 "no bufferbloat verdict"                  "speed_verdict 'garbage'"
lib "speed: slow upload warns"    0 "Upload bandwidth is only 3 Mbps"         "speed_verdict \"\$(printf 'Uplink capacity: 3 Mbps\\nDownlink capacity: 90 Mbps\\nUplink Responsiveness: High (3 milliseconds | 1900 RPM)')\""
printf 'A47733\tGoogle\n00000C Cisco Systems\n' > "$T/oui.txt"
lib "vendor: found in OUI file"   0 "Google"                      "mac_vendor a4:77:33:1b:2c:3d $T/oui.txt"
lib "vendor: single-digit octets" 0 "Cisco Systems"               "mac_vendor 0:0:c:1:2:3 $T/oui.txt"
lib "vendor: random MAC"          0 "random / virtual"            "mac_vendor 5a:11:22:33:44:55 $T/oui.txt"
lib "vendor: no database, no guess" 0 "[]"                        "echo \"[\$(mac_vendor a4:77:33:1b:2c:3d '')]\""
lib "vendor: unknown MAC is blank" 0 "[]"                         "echo \"[\$(mac_vendor ? $T/oui.txt)]\""

# ---- 9. mtr verdict, leak assessment, bonjour parsing --------------------------------------------------
mv() { printf '%s\n' "$2" | PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; mtr_verdict $1 | mtr_explain; echo rc=\${PIPESTATUS[1]}" 2>&1 | strip; }
mcheck() { # name dest rows-with-\n want-substring want-rc
  local out; out=$(mv "$2" "$3")
  if ! printf '%s' "$out" | grep -qF -- "$4"; then fail "$1" "wanted '$4', got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  elif ! printf '%s' "$out" | grep -qF -- "rc=$5"; then fail "$1" "wanted rc=$5, got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  else pass; fi
}
mcheck "mtr: healthy path"             9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 9 8 12\n3 9.9.9.9 0 12 10 15' "Path looks healthy" 0
mcheck "mtr: middle hop ICMP limit"    9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 100 - - -\n3 9.9.9.9 0 12 10 15' "ignores or rate-limits" 0
mcheck "mtr: loss from hop 1"          9.9.9.9 $'1 192.168.0.1 40 3 1 20\n2 10.0.0.1 40 9 8 30\n3 9.9.9.9 38 12 10 40' "Loss starts at hop 1" 1
mcheck "mtr: hop 1 advice"             9.9.9.9 $'1 192.168.0.1 40 3 1 20\n2 10.0.0.1 40 9 8 30\n3 9.9.9.9 38 12 10 40' "your own router" 1
mcheck "mtr: loss from hop 4"          9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 9 8 12\n3 10.1.1.1 0 9 8 12\n4 10.2.2.2 25 20 10 90\n5 9.9.9.9 30 22 10 90' "Loss starts at hop 4" 1
mcheck "mtr: loss in the middle only"  9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 50 9 8 12\n3 9.9.9.9 0 12 10 15' "destination is fine" 0
mcheck "mtr: never reaches the target" 9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 9 8 12' "stops at hop 2" 1
mcheck "mtr: destination ignores ping" 9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 9.9.9.9 100 - - -' "does not answer ping" 0
mcheck "mtr: latency jump"             9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 9 8 12\n3 9.9.9.9 0 180 170 200' "Latency jumps by about 171 ms at hop 3" 0
mcheck "mtr: temporary spike is not a jump" 9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 200 8 300\n3 9.9.9.9 0 12 10 15' "Path looks healthy" 0
out=$(mv 9.9.9.9 $'1 192.168.0.1 0 1 1 2\n2 10.0.0.1 0 200 8 300\n3 9.9.9.9 0 12 10 15'); if printf '%s' "$out" | grep -q "Latency jumps"; then fail "mtr: a spike that does not persist must not be reported" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)"; else pass; fi
lib "mtr: destination from the normal first line" 0 "9.9.9.9" "printf '%s\n' 'traceroute to dns9.quad9.net (9.9.9.9), 30 hops max' ' 1  192.168.0.1  1 ms' | mtr_dest"
lib "mtr: destination after a multi-address warning" 0 "93.184.216.34" "printf '%s\n' 'traceroute: Warning: example.com has multiple addresses; using 93.184.216.34' 'traceroute to example.com (93.184.216.34), 30 hops max' ' 1  10.0.0.1  1 ms' | mtr_dest"
out=$(PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; printf '%s\n' 'traceroute: Warning: example.com has multiple addresses; using 93.184.216.34' 'traceroute to example.com (93.184.216.34), 30 hops max' | mtr_dest | wc -l" | tr -d ' '); [ "$out" = 1 ] && pass || fail "mtr: only one destination line" "$out"
expect "mtr: bad count"           1 "from 3 to 100"        /bin/bash $ND mtr 1.1.1.1 2
expect "mtr: count not a number"  1 "from 3 to 100"        /bin/bash $ND mtr 1.1.1.1 abc
expect "mtr: IPv6 unsupported"    1 "IPv4 only"            /bin/bash $ND mtr ::1
expect "mtr: no host"             1 "Usage"                /bin/bash $ND mtr
expect "mtr: invalid host"        1 "Invalid host"         /bin/bash $ND mtr 'x;ls'
lk() { PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; printf '%s' \"\$4\" | leak_assess \"\$1\" \"\$2\" \"\$3\"; echo rc=\$?" _ "$@" 2>&1 | strip; }
lcheck() { local out; out=$(lk "$2" "$3" "$4" "$5"); if printf '%s' "$out" | grep -qF -- "$6" && printf '%s' "$out" | grep -qF -- "rc=$7"; then pass; else fail "$1" "wanted '$6' rc=$7, got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-220)"; fi; }
lcheck "leak: no VPN"              en0 en0 1 $'192.168.0.1 en0\n'                  "No full-tunnel VPN" 0
lcheck "leak: VPN, DNS inside"     utun4 utun4 1 $'10.8.0.1 utun4\n'                "reached through the tunnel" 0
lcheck "leak: VPN, DNS outside"    utun4 utun4 0 $'192.168.0.1 en0\n'               "DNS leak: 192.168.0.1" 1
lcheck "leak: VPN, IPv6 outside"   utun4 en0 1 $'10.8.0.1 utun4\n'                  "IPv6 leak" 1
lcheck "leak: VPN, no IPv6"        utun4 en0 0 $'10.8.0.1 utun4\n'                  "IPv6 cannot leak" 0
lcheck "leak: fix hint on leak"    utun4 utun4 0 $'192.168.0.1 en0\n'               "kill switch" 1
lcheck "leak: IPsec VPN counts"    ipsec0 ipsec0 0 $'10.8.0.1 ipsec0\n'            "VPN active" 0
lcheck "leak: local resolver is not a leak" utun4 utun4 1 $'127.0.0.1 lo0\n'             "resolver on this Mac" 0
lcheck "leak: local resolver ::1"           utun4 utun4 1 $'::1 lo0\n'                   "resolver on this Mac" 0
lcheck "leak: a real leak is still found next to a local resolver" utun4 utun4 1 $'127.0.0.1 lo0\n192.168.0.1 en0\n' "DNS leak: 192.168.0.1" 1
# ---- Wi-Fi channels: parse + assess + verdict ----
SP="$T/sp.txt"; cat > "$SP" <<'SPEOF'
          Supported Channels: 1 (2GHz), 6 (2GHz), 11 (2GHz), 36 (5GHz), 40 (5GHz), 44 (5GHz), 48 (5GHz), 52 (5GHz), 149 (5GHz)
          Current Network Information:
            <redacted>:
              Channel: 6 (2GHz, 20MHz)
              Signal / Noise: -50 dBm / -88 dBm
          Other Local Wi-Fi Networks:
            <redacted>:
              Channel: 6 (2GHz, 20MHz)
              Signal / Noise: -55 dBm / -88 dBm
            <redacted>:
              Channel: 5 (2GHz, 20MHz)
            <redacted>:
              Channel: 7 (2GHz, 20MHz)
            <redacted>:
              Channel: 36 (5GHz, 80MHz)
SPEOF
lib "channels: parse current network"     0 "cur 6 2 20 -50"  "wifi_scan_parse < $SP"
lib "channels: parse neighbour + width"   0 "oth 36 5 80 -"   "wifi_scan_parse < $SP"
lib "channels: parse supported channels"  0 "sup 149 5 20 -"  "wifi_scan_parse < $SP"
lib "channels: overlap score (2.4 GHz adjacent channels count)" 0 "CUR 2 6 20 4 3" "wifi_scan_parse < $SP | channels_assess"
SP4="$T/sp4.txt"; { printf '%s\n' '          Supported Channels: 1 (2GHz), 6 (2GHz), 11 (2GHz)' '          Current Network Information:' '            x:' '              Channel: 6 (2GHz, 20MHz)' '          Other Local Wi-Fi Networks:'; for c in 1 1 5 6 6 7 11 11; do printf '%s\n' '            n:' "              Channel: $c (2GHz, 20MHz)"; done; } > "$SP4"
SP5="$T/sp5.txt"; printf '%s\n' '          Supported Channels: 36 (5GHz), 52 (5GHz), 149 (5GHz)' '          Current Network Information:' '            x:' '              Channel: 36 (5GHz, 20MHz)' '          Other Local Wi-Fi Networks:' '            a:' '              Channel: 36 (5GHz, 20MHz)' '            b:' '              Channel: 36 (5GHz, 20MHz)' '            c:' '              Channel: 36 (5GHz, 20MHz)' > "$SP5"
lib "channels: ch 1 is a candidate, scored lower" 0 "CAND 1 1 0" "wifi_scan_parse < $SP | channels_assess"
lib "channels: 2.4 GHz candidates are only 1/6/11" 0 "" "wifi_scan_parse < $SP | channels_assess | awk '\$1==\"CAND\" && \$2!=1 && \$2!=6 && \$2!=11{exit 1}'"
lib "channels: recommends the quiet channel" 0 "set the 5 GHz channel" "wifi_scan_parse < $SP5 | channels_assess | channels_verdict"
lib "channels: busy but nothing clearly better" 0 "no other channel in this band is clearly better" "wifi_scan_parse < $SP4 | channels_assess | channels_verdict"
lib "channels: 5 GHz hint on a crowded 2.4 GHz channel" 0 "connect to the 5 GHz network" "wifi_scan_parse < $SP | channels_assess | channels_verdict"
SP2="$T/sp2.txt"; printf '%s\n' '          Current Network Information:' '            x:' '              Channel: 36 (5GHz, 80MHz)' '          Other Local Wi-Fi Networks:' '            a:' '              Channel: 40 (5GHz, 20MHz)' '            b:' '              Channel: 44 (5GHz, 80MHz)' '            c:' '              Channel: 36 (5GHz, 80MHz)' > "$SP2"
lib "channels: 5 GHz overlap follows the 80 MHz block" 0 "CUR 5 36 80 3 3" "wifi_scan_parse < $SP2 | channels_assess"
SP3="$T/sp3.txt"; printf '%s\n' '          Current Network Information:' '            x:' '              Channel: 36 (5GHz, 80MHz)' > "$SP3"
lib "channels: quiet channel" 0 "Your channel is quiet" "wifi_scan_parse < $SP3 | channels_assess | channels_verdict"
lib "channels: not connected" 1 "not connected to a Wi-Fi" "printf '' | channels_assess | channels_verdict"
# ---- IPv6 verdict ----
v6() { local name=$1 want=$2 rc=$3; shift 3; lib "$name" "$rc" "$want" "ipv6_assess $*"; }
v6 "ipv6: no IPv6 at all"            "provides no IPv6 at all"     0 glob=0 gw=0
v6 "ipv6: only local IPv6 (ULA)"     "only local IPv6"             0 glob=0 ula=1 gw=1
v6 "ipv6: address but no route"      "no IPv6 default route"       1 glob=1 gw=0
v6 "ipv6: router silent"             "does not answer"             1 glob=1 gw=1 gwok=0
v6 "ipv6: upstream broken"           "fault is upstream"           1 glob=1 gw=1 gwok=1 ipok=0
v6 "ipv6: upstream fix advice"       "networksetup -setv6off"      1 glob=1 gw=1 gwok=1 ipok=0
v6 "ipv6: MTU black hole"            "path-MTU black hole"         1 glob=1 gw=1 gwok=1 ipok=1 bigok=0
v6 "ipv6: HTTPS blocked over v6"     "HTTPS over IPv6 to a real site fails" 0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=0 aaaa=1
v6 "ipv6: DNS gives no AAAA"         "gives no IPv6 (AAAA)"        0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=0 aaaa=0
v6 "ipv6: slow compared with IPv4"   "much slower to connect"      0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=1 aaaa=1 t4=20 t6=450
v6 "ipv6: a small gap is not slow"   "IPv6 is healthy"             0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=1 aaaa=1 t4=20 t6=200
v6 "ipv6: VPN default route is not diagnosed"  "Not diagnosed"  0 tun=1 glob=1 gw=1
v6 "ipv6: VPN is never reported healthy"  "not tested"      0 tun=1 glob=1 gw=1
mkdir -p "$T/p6"
printf '#!/bin/sh\necho "16 bytes from fe80::1: icmp_seq=0 hlim=64 time=10.000 ms"\necho "16 bytes from fe80::1: icmp_seq=1 hlim=64 time=20.000 ms"\n' > "$T/p6/ping6"; chmod +x "$T/p6/ping6"
lib "ping6_stats: killed ping6 (no summary) still reports the average in \$2" 0 "avg=15.000" "PATH=$T/p6:\$PATH; set -- \$(ping6_stats ::1 2 '' 4); echo avg=\${2:-}"
lib "ping6_stats: the empty loss field is a placeholder"                     0 "loss=-"     "PATH=$T/p6:\$PATH; set -- \$(ping6_stats ::1 2 '' 4); echo loss=\$1"
printf '#!/bin/sh\nexit 1\n' > "$T/p6/ping6"
lib "ping6_stats: nothing answered means no average"                         0 "avg=[]"     "PATH=$T/p6:\$PATH; set -- \$(ping6_stats ::1 2 '' 4); echo \"avg=[\${2:-}]\""
printf '#!/bin/sh\necho "2 packets transmitted, 2 packets received, 0.0%% packet loss"\necho "round-trip min/avg/max/std-dev = 1.000/2.500/4.000/0.1 ms"\n' > "$T/p6/ping6"; chmod +x "$T/p6/ping6"
lib "ping6_stats: normal summary is unchanged"                               0 "0.0 2.500"  "PATH=$T/p6:\$PATH; ping6_stats ::1 2 '' 4"
# ---- IPv6 helpers: address selection, virtual interfaces, probes ----
IFC="$T/ifconfig6.txt"; printf '%s\n' 'lo0: flags=8049<UP,LOOPBACK>' '	inet6 ::1 prefixlen 128' '	inet6 fe80::1%lo0 prefixlen 64' 'en0: flags=8863<UP>' '	inet6 fe80::aa:bb%en0 prefixlen 64' '	inet6 fd09:1::5 prefixlen 64' 'en5: flags=8863<UP>' '	inet6 2001:db8::5 prefixlen 64' 'utun3: flags=8051<UP>' '	inet6 fd7a:115c::1 prefixlen 64' 'wg0: flags=80d1<UP>' '	inet6 2001:db8:ff::9 prefixlen 128' 'awdl0: flags=8943<UP>' '	inet6 2001:db8:aa::7 prefixlen 64' > "$IFC"
lib "v6_addrs: link-local and loopback are dropped"   0 "u en0 fd09:1::5"   "v6_addrs < $IFC"
lib_not "v6_addrs: no link-local rows" "v6_addrs < $IFC" "fe80"
lib "v6_addrs: classifies global"                      0 "g en5 2001:db8::5" "v6_addrs < $IFC"
lib "v6_pick: all physical interfaces by default"      0 "g 2001:db8::5"   "v6_addrs < $IFC | v6_pick ''"
lib_not "v6_pick: tunnels are skipped (utun, wg, awdl)" "v6_addrs < $IFC | v6_pick ''" "fd7a"
lib_not "v6_pick: WireGuard wg0 is a tunnel"            "v6_addrs < $IFC | v6_pick ''" "2001:db8:ff"
lib_not "v6_pick: awdl is virtual"                      "v6_addrs < $IFC | v6_pick ''" "2001:db8:aa"
lib "v6_pick: only the wanted interface"               0 "u fd09:1::5"     "v6_addrs < $IFC | v6_pick en0"
lib_not "v6_pick: another interface is left out"        "v6_addrs < $IFC | v6_pick en0" "2001:db8::5"
lib "v6_pick: '-' matches nothing" 1 "" "v6_addrs < $IFC | v6_pick - | grep -q ."
lib "virtual_if: wg0 / utun0 / lo0 / awdl0" 0 "" "virtual_if wg0 && virtual_if utun0 && virtual_if lo0 && virtual_if awdl0"
lib "virtual_if: en0 is not virtual"        1 "" "virtual_if en0"
printf '#!/bin/sh\necho "<html>"\nprintf "0.045000 0.020000"\n' > "$T/p6/curl"; chmod +x "$T/p6/curl"
lib "tls_ms: a finished TLS handshake gives the connect time in ms" 0 "ms=20" "PATH=$T/p6:\$PATH; echo ms=\$(tls_ms 6 example.com)"
printf '#!/bin/sh\nprintf "0.000000 0.000000"\nexit 28\n' > "$T/p6/curl"; chmod +x "$T/p6/curl"
lib "tls_ms: no TLS handshake is a failure" 1 "" "PATH=$T/p6:\$PATH; tls_ms 6 example.com"
rm -f "$T/p6/curl"
printf '#!/bin/sh\nif [ "$4" = "2001:db8::2" ] || [ "$6" = "2001:db8::2" ]; then echo "2 packets transmitted, 2 packets received, 0.0%% packet loss"; echo "round-trip min/avg/max/std-dev = 1.000/7.500/9.000/0.1 ms"; fi\n' > "$T/p6/ping6"; chmod +x "$T/p6/ping6"
lib "v6_first_reachable: skips the silent one, returns the first that answers" 0 "2001:db8::2 7.500" "PATH=$T/p6:\$PATH; v6_first_reachable '' 2001:db8::1 2001:db8::2"
lib "v6_first_reachable: none answer"                                         1 ""                  "PATH=$T/p6:\$PATH; v6_first_reachable '' 2001:db8::1 2001:db8::3"
v6 "ipv6: healthy"                   "IPv6 is healthy"             0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=1 aaaa=1 v4ok=1
v6 "ipv6: IPv6-only network"          "IPv6-only connectivity"     0 glob=1 gw=1 gwok=1 ipok=1 bigok=1 nameok=1 aaaa=1 v4ok=0
# ---- exposure: netstat parsing and assessment ----
NS="$T/ns.txt"; printf '%s\n' 'tcp4       0      0  *.22                   *.*                    LISTEN' 'tcp6       0      0  *.22                   *.*                    LISTEN' 'tcp4       0      0  127.0.0.1.6379         *.*                    LISTEN' 'tcp4       0      0  192.168.0.5.8080       *.*                    LISTEN' 'tcp6       0      0  ::1.631                *.*                    LISTEN' 'tcp6       0      0  fe80::1%lo0.80         *.*                    LISTEN' 'tcp46      0      0  *.55146                *.*                    LISTEN' 'tcp4       0      0  *.9999                 *.*                    ESTABLISHED' > "$NS"
lib "exposure: wildcard is all"            0 "22 all"      "exposure_parse < $NS"
lib "exposure: loopback is local"          0 "6379 local"  "exposure_parse < $NS"
lib "exposure: a specific address is lan"  0 "8080 lan"     "exposure_parse < $NS"
lib "exposure: ::1 is local"               0 "631 local"   "exposure_parse < $NS"
lib "exposure: tcp46 wildcard is all"      0 "55146 all"   "exposure_parse < $NS"
lib_not "exposure: non-LISTEN rows are ignored" "exposure_parse < $NS" "9999"
lib "exposure: widest scope wins (22 listed once)" 0 "" "exposure_parse < $NS | awk '\$1==22' | wc -l | grep -qx ' *1'"
ex() { local name=$1 want=$2 rc=$3 in=$4; shift 4; lib "$name" "$rc" "$want" "printf '%s\n' '$in' | exposure_assess $*"; }
ex "exposure: Redis open to the network is serious" "Redis is open" 1 "6379 all redis-server" fw=on
ex "exposure: Docker API is serious"               "Docker API"    1 "2375 all dockerd" fw=on
ex "exposure: Redis on loopback is fine"           "Nothing sensitive is exposed" 0 "6379 local redis-server" fw=on
ex "exposure: SSH is a warning, not an error"      "Remote Login (SSH)" 0 "22 all ?" fw=on
ex "exposure: SMB is a warning"                    "File Sharing (SMB)" 0 "445 all ?" fw=on
ex "exposure: dev server on all interfaces"        "development server" 0 "3000 all node" fw=on
ex "exposure: unknown daemon port is only listed"  "reachable from the network" 0 "88 all ?" fw=on
ex "exposure: high ports are folded"               "1 high ports (49152+)" 0 "55146 all rapportd" fw=on
ex "exposure: firewall off with exposure"          "firewall is OFF" 0 "22 all ?" fw=off
ex "exposure: firewall unknown"                    "could not read the firewall state" 0 "5000 all ControlCe" fw=unknown
ex "exposure: Redis on a high port is still serious"  "data store"  1 "50000 all redis-server" fw=on
ex "exposure: node on a high port is still flagged"   "development server" 0 "60000 all node" fw=on
ex "exposure: a high port of an unknown process is folded" "1 high ports (49152+)" 0 "50000 all ?" fw=on
ex "exposure: folded high ports do not count as exposed" "no ports below 49152" 0 "50000 all rapportd" fw=on
printf '%s\n' 'tcp6       0      0  fe80::1%lo0.80         *.*                    LISTEN' > "$T/ns_lo.txt"
lib "exposure: link-local on lo0 is local" 0 "80 local" "exposure_parse < $T/ns_lo.txt"
LS="$T/lsof.txt"; printf '%s\n' 'COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME' 'node     101 max   20u  IPv4 0x1      0t0  TCP 127.0.0.1:3000 (LISTEN)' 'python3  202 max   21u  IPv4 0x2      0t0  TCP *:3000 (LISTEN)' 'cupsd    303 max   22u  IPv6 0x3      0t0  TCP [::1]:631 (LISTEN)' > "$LS"
lib "exposure: the externally reachable listener names the port" 0 "3000 python3" "exposure_procs < $LS"
lib "exposure: loopback-only port keeps its process name"         0 "631 cupsd"    "exposure_procs < $LS"
ex "exposure: nothing exposed"                     "no ports below 49152" 0 "631 local cupsd" fw=on
SD=$'0:36:43.593  Add        3   7 .                    _tcp.local.          _ssh\n0:36:43.593  Add        3  15 .                    _tcp.local.          _ssh\n0:36:43.593  Add        3   7 .                    _udp.local.          _sleep-proxy\n0:36:43.593  Rmv        3   7 .                    _tcp.local.          _gone'
printf '%s\n' "$SD" > "$T/meta.txt"
lib "bonjour: service types (dedupe, Rmv ignored)" 0 "_ssh._tcp" "bonjour_types $T/meta.txt"
lib "bonjour: udp type"                            0 "_sleep-proxy._udp" "bonjour_types $T/meta.txt"
lib_not "bonjour: removed type ignored"            "bonjour_types $T/meta.txt" "_gone"
printf '%s\n' $'0:36:43.593  Add        3   7 local.               _airplay._tcp.       Living Room TV' $'0:36:43.600  Add        3  15 local.               _airplay._tcp.       Living Room TV' $'0:36:43.600  Add        2  15 local.               _ipp._tcp.           HP Color LaserJet' $'0:36:44.000  Rmv        0  15 local.               _ipp._tcp.           Old Printer' > "$T/b.txt"
lib "bonjour: instance with spaces"  0 "_airplay._tcp|Living Room TV" "bonjour_parse $T/b.txt"
lib "bonjour: same service on two interfaces counted once" 0 "1" "bonjour_parse $T/b.txt | grep -c airplay"
lib_not "bonjour: removed instance ignored" "bonjour_parse $T/b.txt" "Old Printer"
lib "bonjour: friendly label"        0 "AirPlay" "bonjour_label _airplay._tcp"
lib "bonjour: unknown type kept"     0 "_weird._tcp" "bonjour_label _weird._tcp"
expect "bonjour: bad seconds"        1 "from 2 to 30"  /bin/bash $ND bonjour 1
expect "bonjour: not a number"       1 "from 2 to 30"  /bin/bash $ND bonjour x

# ---- 10. tools list: optional tools are not warnings ---------------------------------------------------
mkdir -p "$T/empty"
out=$(PATH="$T/empty" /bin/bash $ND tools </dev/null 2>&1 | strip); rc=$?
if printf '%s' "$out" | grep -qF "Optional third-party tools (NetDoctor works without them)"; then pass; else fail "tools: optional heading" "$(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
if printf '%s' "$out" | grep -qF "gping" && printf '%s' "$out" | grep -qF "brew install gping"; then pass; else fail "tools: install hint for a missing tool"; fi
if printf '%s' "$out" | grep -qF "brew install trippy"; then pass; else fail "tools: command trip maps to package trippy"; fi
if printf '%s' "$out" | grep -qF "brew install httpie"; then pass; else fail "tools: command http maps to package httpie"; fi
if printf '%s' "$out" | grep -F "gping" | grep -q "WARN"; then fail "tools: a missing optional tool must not be a warning"; else pass; fi
if printf '%s' "$out" | grep -qF "0 of 14 optional tools installed. None of them is required."; then pass; else fail "tools: summary line" "$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"; fi
[ "$rc" = 0 ] && pass || fail "tools: exit code" "rc=$rc"
NETDOCTOR_LANG=zh out=$(PATH="$T/empty" /bin/bash $ND tools </dev/null 2>&1 | strip)
if printf '%s' "$out" | grep -qF "已安装 0 / 14 个可选工具"; then pass; else fail "tools: Chinese summary"; fi
export NETDOCTOR_LANG=en   # the assignment above is not scoped to one command: put English back for the tests that follow

# ---- 10. fix (doctor --fix) and the HTML report ---------------------------------------------------------
for v in "dhcp:renew_dhcp" "dns:flush_dns" "dns_all:flush_dns" "clock:sync_clock" "captive:open_portal"; do
  lib "fix_actions: ${v%%:*}" 0 "${v#*:}" "fix_actions ${v%%:*}"
done
for v in http internet gateway link unstable ""; do
  lib "fix_actions: '$v' has no automatic fix" 0 "[]" "echo \"[\$(fix_actions '$v')]\""
done
# fake privileged commands: they only record what they were asked to run; the fake sudo runs its arguments
mkdir -p "$T/fx"; : > "$T/fx.log"
for c in ipconfig dscacheutil killall sntp open; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$T/fx.log" > "$T/fx/$c"; chmod +x "$T/fx/$c"; done
printf '#!/bin/sh\n[ "$1" = -n ] && shift\nexec "$@"\n' > "$T/fx/sudo"; chmod +x "$T/fx/sudo"
fxlib() { # name want-rc substring code   (runs with the recording fakes; never run as root, where priv would not use sudo)
  [ "$(id -u)" = 0 ] && return 0; : > "$T/fx.log"
  lib "$1" "$2" "$3" "export PATH=$T/fx:\$PATH; sleep() { :; }; $4"
}
fxlog_has() { grep -qF -- "$2" "$T/fx.log" && pass || fail "$1" "log: $(tr '\n' ';' < "$T/fx.log")"; }
fxlog_empty() { [ ! -s "$T/fx.log" ] && pass || fail "$1" "unexpected commands ran: $(tr '\n' ';' < "$T/fx.log")"; }
fxlib "fix_apply: renew DHCP"        0 "" "fix_apply renew_dhcp en0";                 fxlog_has "fix_apply: renew DHCP runs ipconfig" "ipconfig set en0 DHCP"
fxlib "fix_apply: bad interface"     1 "" "fix_apply renew_dhcp 'en0;ls'";            fxlog_empty "fix_apply: bad interface runs nothing"
fxlib "fix_apply: empty interface"   1 "" "fix_apply renew_dhcp ''";                  fxlog_empty "fix_apply: empty interface runs nothing"
fxlib "fix_apply: flush DNS"         0 "" "fix_apply flush_dns";                      fxlog_has "fix_apply: flush runs dscacheutil" "dscacheutil -flushcache"
fxlog_has "fix_apply: flush restarts mDNSResponder" "killall -HUP mDNSResponder"
fxlib "fix_apply: sync clock"        0 "" "fix_apply sync_clock";                     fxlog_has "fix_apply: sntp" "sntp -sS time.apple.com"
fxlib "fix_apply: unknown action"    1 "" "fix_apply rm_rf_slash";                    fxlog_empty "fix_apply: unknown action runs nothing"
fxlib "fix_apply: open portal"       0 "" "fix_apply open_portal";                    fxlog_has "fix_apply: opens the portal URL" "open http://captive.apple.com"
# cmd_fix with a stubbed cmd_doctor
STUB='cmd_doctor() { DOCTOR_VERDICT=${V:-}; DOCTOR_IFC=en0; return 1; }'
fxlib "fix: captive portal as root is not a failure" 1 "open http://captive.apple.com yourself" "$STUB; id() { echo 0; }; V=captive cmd_fix yes"; fxlog_empty "fix: captive portal as root does not run open"
lib_not "fix: captive portal as root does not say Failed" "$STUB; id() { echo 0; }; V=captive cmd_fix yes" "Failed"
fxlib "fix: healthy → nothing to fix"  0 "Nothing to fix" "$STUB; V= cmd_fix";        fxlog_empty "fix: healthy runs nothing"
fxlib "fix: http cannot be fixed here" 1 "cannot be fixed from the Mac" "$STUB; V=http cmd_fix"; fxlog_empty "fix: http runs nothing"
fxlib "fix: unstable has no fix"       1 "No automatic fix" "$STUB; V=unstable cmd_fix"
# not a terminal and no 'yes': show the plan, change nothing
fxlib "fix: plan only without yes"     1 "Nothing was changed" "$STUB; V=dns cmd_fix";  fxlog_empty "fix: plan only runs nothing"
fxlib "fix: plan shows the command"    1 "dscacheutil -flushcache" "$STUB; V=dns cmd_fix"
# with yes: applies, then re-diagnoses (the second doctor run reports healthy)
fxlib "fix: yes applies and re-checks" 0 "Checking again" "cmd_doctor() { if [ -e $T/second ]; then DOCTOR_VERDICT=; return 0; fi; : > $T/second; DOCTOR_VERDICT=dns; DOCTOR_IFC=en0; return 1; }; rm -f $T/second; cmd_fix yes"
fxlog_has "fix: yes really flushed the cache" "dscacheutil -flushcache"
fxlib "fix: dhcp uses the diagnosed interface" 0 "" "cmd_doctor() { DOCTOR_VERDICT=dhcp; DOCTOR_IFC=en7; return 0; }; cmd_fix yes"; fxlog_has "fix: dhcp renews en7" "ipconfig set en7 DHCP"
fxlib "fix: still broken after the fix → rc 1" 1 "Checking again" "$STUB; V=dns cmd_fix yes"
# without administrator rights (the earlier fake sudo exits 1) a privileged step is refused, not attempted
if [ "$(id -u)" != 0 ]; then
  lib "fix: no admin rights" 1 "Needs administrator rights" "$STUB; V=dns cmd_fix yes"
fi
lib "doctor --fix is routed to fix"   0 "ROUTED yes" 'cmd_fix() { echo ROUTED "$@"; }; cmd_doctor --fix yes'
lib "doctor fix is routed to fix"     0 "ROUTED"     'cmd_fix() { echo ROUTED "$@"; }; cmd_doctor fix'
# HTML report
hr() { printf '%s' "$1" | PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c '. ./netdoctor; report_to_html "NetDoctor report" now Summary en' 2>&1; }
HTML=$(hr $'# note\n\n== Diagnosis ==\n[ OK ] a <script>x</script> & b\n[WARN] w\n[FAIL] f\n[FAIL] g\n\n== Verdict ==\n[ OK ] fine')
printf '%s' "$HTML" | grep -qF '<span class="f">FAIL 2</span>' && pass || fail "html: FAIL count" "$(printf '%s' "$HTML" | grep -o 'class="sum".*' | head -1)"
printf '%s' "$HTML" | grep -qF '<span class="w">WARN 1</span>' && pass || fail "html: WARN count"
printf '%s' "$HTML" | grep -qF '<span class="o">OK 2</span>' && pass || fail "html: OK count"
printf '%s' "$HTML" | grep -qF '&lt;script&gt;x&lt;/script&gt; &amp; b' && pass || fail "html: text is escaped"
printf '%s' "$HTML" | grep -qF '<script>' && fail "html: raw <script> leaked" || pass
[ "$(printf '%s' "$HTML" | grep -c '<details')" = 2 ] && pass || fail "html: one block per section"
printf '%s' "$HTML" | grep -qF '<summary>Verdict</summary>' && pass || fail "html: section titles"
printf '%s' "$HTML" | grep -qF '<span class="f">[FAIL]</span> f' && pass || fail "html: marker colouring"
printf '%s' "$HTML" | grep -qE '(src|href)="https?:' && fail "html: must not reference external files" || pass
expect "report: unknown option"  1 "Unknown option"  /bin/bash $ND report nonsense
# redaction still applies to the text before it becomes HTML
lib "report html: redacted values never reach the page" 0 "" 'REDACT_LITERALS="203.0.113.9"; printf "%s\n" "== X ==" "Public IP: 203.0.113.9 and 203.0.113.9" | redact_filter | report_to_html t n s en | grep -c 203.0.113.9 | grep -qx 0'

# ---- 11. watch ------------------------------------------------------------------------------------------
ws() { printf '%b' "$1" | PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; watch_summary 1.1.1.1" 2>&1 | strip; }
wcheck() { local out; out=$(ws "$2"); if printf '%s' "$out" | grep -qF -- "$3"; then pass; else fail "$1" "wanted '$3', got: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"; fi; }
wcheck "watch: counts and loss"        '100 10\n101 12\n102 -\n103 20\n' "4 pings, 1 lost (25.0%)"
wcheck "watch: min/avg/max"            '100 10\n101 20\n' "min/avg/max = 10.0/15.0/20.0 ms"
wcheck "watch: jitter"                 '100 10\n101 20\n102 10\n' "jitter 10.0 ms"
wcheck "watch: no outage"              '100 10\n101 -\n102 -\n103 12\n' "No outage"
wcheck "watch: 2 lost in a row is not an outage" '100 10\n101 -\n102 -\n103 12\n' "No outage"
wcheck "watch: outage duration"        '100 10\n101 -\n102 -\n103 -\n104 -\n105 9\n' "from +1 s, lasted 4 s"
wcheck "watch: outage still down"      '100 10\n101 -\n102 -\n103 -\n' "still down at the end"
wcheck "watch: two outages"            '100 10\n101 -\n102 -\n103 -\n104 9\n105 -\n106 -\n107 -\n108 9\n' "2 outage(s)"
wcheck "watch: all lost has no latency line" '100 -\n101 -\n102 -\n' "3 pings, 3 lost (100.0%)"
out=$(ws '100 -\n101 -\n102 -\n'); printf '%s' "$out" | grep -qF "Latency" && fail "watch: all lost must not print latency" || pass
wcheck "watch: no samples"             '' "No samples."
out=$(printf '100 10\n' | NETDOCTOR_LANG=zh PATH="$T/bin:$PATH" NETDOCTOR_SOURCE_ONLY=1 /bin/bash -c ". $ND; watch_summary h" 2>&1)
printf '%s' "$out" | grep -qF "没有断线" && pass || fail "watch: Chinese summary"
expect "watch: bad host"         1 "Invalid host"        /bin/bash $ND watch 'x;ls' 10
expect "watch: seconds too small" 1 "from 5 to 3600"     /bin/bash $ND watch 1.1.1.1 2
expect "watch: seconds not a number" 1 "from 5 to 3600"  /bin/bash $ND watch 1.1.1.1 abc
# a live run with a fake ping that fails three times, then answers: alert, recovery and the summary
mkdir -p "$T/wp"; : > "$T/wp.n"
printf '#!/bin/sh\necho x >> "%s"\nn=$(wc -l < "%s")\n[ "$n" -le 3 ] && exit 1\necho "64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=7.5 ms"\n' "$T/wp.n" "$T/wp.n" > "$T/wp/ping"; chmod +x "$T/wp/ping"
out=$(PATH="$T/wp:$PATH" /bin/bash $ND watch 1.1.1.1 7 </dev/null 2>&1 | strip)
printf '%s' "$out" | grep -qF "Connection lost" && pass || fail "watch: alerts after 3 lost pings" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
printf '%s' "$out" | grep -qF "Back online after" && pass || fail "watch: reports the recovery"
printf '%s' "$out" | grep -qF "1 outage(s)" && pass || fail "watch: summary counts the outage" "$(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
printf '%s' "$out" | grep -qF "min/avg/max = 7.5/7.5/7.5" && pass || fail "watch: latency parsed from ping output"

# ---- 12. compare ----------------------------------------------------------------------------------------
CD="$T/cmp"; mkdir -p "$CD/home/Desktop"
printf 'netdoctor report Sat Nov  7 08:00:00 PST 2026\n== Diagnosis ==\n[ OK ] 2/6 Gateway 192.168.0.1: reachable (avg 1.139 ms)\n[ OK ] 4/6 DNS: works\n[WARN] 6/6 Proxy / VPN: tunnels: utun4\nSignal / Noise: -47 dBm / -88 dBm\n  8.8.8.8      11 ms      x\n[ OK ] https://www.apple.com  200 0.116464s\n' > "$CD/a.txt"
printf 'netdoctor report Sat Nov  7 09:30:41 PST 2026\n== Diagnosis ==\n[ OK ] 2/6 Gateway 192.168.0.1: reachable (avg 3.912 ms)\n[ OK ] 4/6 DNS: works\n[WARN] 6/6 Proxy / VPN: tunnels: utun4\nSignal / Noise: -52 dBm / -90 dBm\n  8.8.8.8      7 ms       x\n[ OK ] https://www.apple.com  200 1.214492s\n' > "$CD/b.txt"
printf 'netdoctor report Sat Nov  7 10:00:00 PST 2026\n== Diagnosis ==\n[ OK ] 2/6 Gateway 10.0.0.1: reachable (avg 2.0 ms)\n[FAIL] 4/6 DNS: the system resolver fails\n[WARN] 6/6 Proxy / VPN: tunnels: utun4\nSignal / Noise: -47 dBm / -88 dBm\n  8.8.8.8      11 ms      x\n[ OK ] https://www.apple.com  200 0.116464s\n' > "$CD/c.txt"
expect "compare: only timings differ"   0 "Nothing changed apart from timings" /bin/bash $ND compare "$CD/a.txt" "$CD/b.txt"
expect "compare: a changed gateway is shown (was)" 0 "was  [ OK ] 2/6 Gateway 192.168.0.1" /bin/bash $ND compare "$CD/a.txt" "$CD/c.txt"
expect "compare: a changed gateway is shown (now)" 0 "now  [ OK ] 2/6 Gateway 10.0.0.1" /bin/bash $ND compare "$CD/a.txt" "$CD/c.txt"
expect "compare: new failure is shown"   0 "now  [FAIL] 4/6 DNS" /bin/bash $ND compare "$CD/a.txt" "$CD/c.txt"
expect "compare: problem counts"         0 "FAIL 0 → 1,  WARN 1 → 1" /bin/bash $ND compare "$CD/a.txt" "$CD/c.txt"
out=$(/bin/bash $ND compare "$CD/a.txt" "$CD/c.txt" </dev/null 2>&1); printf '%s' "$out" | grep -qF "Signal" && fail "compare: unchanged lines must not be listed" || pass
expect "compare: one argument"           1 "Usage"         /bin/bash $ND compare "$CD/a.txt"
expect "compare: missing file"           1 "Cannot read"   /bin/bash $ND compare "$CD/a.txt" "$CD/nope.txt"
printf '<html>' > "$CD/r.html"; expect "compare: html is refused" 1 "Only .txt reports" /bin/bash $ND compare "$CD/a.txt" "$CD/r.html"
printf 'hello\n' > "$CD/x.txt"; expect "compare: not a report"   1 "Not a netdoctor report" /bin/bash $ND compare "$CD/a.txt" "$CD/x.txt"
H2="$CD/home2"; mkdir -p "$H2/Desktop"; for f in "$H2/Desktop/netdoctor-report-1.txt" "$H2/netdoctor-report-2.txt" "$H2/netdoctor-report-3.txt"; do cp "$CD/a.txt" "$f"; done
touch -t 202001010000 "$H2/Desktop/netdoctor-report-1.txt"; touch -t 202201010000 "$H2/netdoctor-report-2.txt"; touch -t 202301010000 "$H2/netdoctor-report-3.txt"
expect "compare: picks the two newest across Desktop and home (older)" 0 "older: $H2/netdoctor-report-2.txt" env HOME="$H2" /bin/bash $ND compare
expect "compare: picks the two newest across Desktop and home (newer)" 0 "newer: $H2/netdoctor-report-3.txt" env HOME="$H2" /bin/bash $ND compare
expect "compare: no saved reports"       1 "found 0"       env HOME="$CD/home" /bin/bash $ND compare
cp "$CD/a.txt" "$CD/home/Desktop/netdoctor-report-1.txt"; touch -t 202611070800 "$CD/home/Desktop/netdoctor-report-1.txt"
expect "compare: only one saved report"  1 "found 1"       env HOME="$CD/home" /bin/bash $ND compare
cp "$CD/c.txt" "$CD/home/Desktop/netdoctor-report-2.txt"; touch -t 202611071000 "$CD/home/Desktop/netdoctor-report-2.txt"
expect "compare: picks the two newest, older first" 0 "was  [ OK ] 2/6 Gateway 192.168.0.1" env HOME="$CD/home" /bin/bash $ND compare

# ---- 13. Wi-Fi quality in doctor -------------------------------------------------------------------------
SPROF='Wi-Fi:\n  Interfaces:\n    en0:\n      Status: Connected\n      Current Network Information:\n        Home:\n          PHY Mode: 802.11ax\n          Channel: 36 (5GHz, 80MHz)\n          Signal / Noise: %s dBm / %s dBm\n          Transmit Rate: 286\n      Other Local Wi-Fi Networks:\n        Neighbour:\n          Channel: 6 (2GHz, 20MHz)\n'
sp() { printf "$SPROF" "$1" "$2"; }
lib "wifi_read: signal, noise, rate, channel" 0 "-49|-89|286|36 (5GHz, 80MHz)" "sp() { printf '$SPROF' -49 -89; }; sp | wifi_read"
lib "wifi_read: ignores other networks' channel" 0 "|||" "printf 'Other Local Wi-Fi Networks:\n  X:\n    Channel: 6 (2GHz)\n' | wifi_read"
lib "wifi_read: no data" 0 "|||" "printf '' | wifi_read"
lib "wifi_weak: strong signal and quiet" 1 "" "wifi_weak -50 -90"
lib "wifi_weak: -70 is weak"             0 "signal is weak (-70 dBm" "wifi_weak -70 -95"
lib "wifi_weak: -69 is fine"             1 "" "wifi_weak -69 -95"
lib "wifi_weak: noisy (SNR 15)"          0 "SNR 15 dB" "wifi_weak -60 -75"
lib "wifi_weak: SNR 20 is not flagged"   1 "" "wifi_weak -60 -80"
lib "wifi_weak: no noise value, strong"  1 "" "wifi_weak -50 ''"
lib "wifi_weak: no noise value, weak"    0 "signal is weak" "wifi_weak -80 ''"
lib "wifi_weak: garbage input"           1 "" "wifi_weak abc 5"
# doctor with everything else healthy (stubbed), only the Wi-Fi numbers vary
DR='default_if() { echo en0; }; gateway() { echo 192.168.0.1; }; self_assigned_if() { :; }; ping_stats() { echo "0 5.0"; }; resolves() { return 0; }
curl() { echo 200; }; scutil() { :; }; ifconfig() { :; }; wifi_if() { echo ${WIFI_IF:-en0}; }'
drwifi() { echo "$DR; system_profiler() { printf '$SPROF' $1 $2; }; $3"; }
lib "doctor: good Wi-Fi is shown and healthy" 0 "Wi-Fi: signal -50 dBm, noise -90 dBm, 286 Mbps, channel 36 (5GHz, 80MHz)" "$(drwifi -50 -90 cmd_doctor)"
lib "doctor: good Wi-Fi stays healthy"        0 "Everything looks healthy" "$(drwifi -50 -90 cmd_doctor)"
lib "doctor: weak Wi-Fi is the verdict"       1 "the Wi-Fi link itself is weak" "$(drwifi -80 -92 cmd_doctor)"
lib "doctor: weak Wi-Fi explains the reason"  1 "the signal is weak (-80 dBm" "$(drwifi -80 -92 cmd_doctor)"
lib "doctor: weak Wi-Fi suggests next steps"  1 "Move closer to the router" "$(drwifi -80 -92 cmd_doctor)"
lib "doctor: weak Wi-Fi sets the verdict variable" 0 "wifi" "$(drwifi -80 -92 'cmd_doctor >/dev/null; echo $DOCTOR_VERDICT')"
lib "doctor: noisy Wi-Fi is flagged"          1 "too much noise (SNR 15 dB" "$(drwifi -60 -75 cmd_doctor)"
lib "doctor: a real fault wins over weak Wi-Fi" 1 "DNS resolution is the problem" "$(drwifi -80 -92 'resolves() { return 1; }; cmd_doctor')"
lib "doctor: unstable + weak Wi-Fi blames Wi-Fi" 1 "the Wi-Fi link itself is weak" "$(drwifi -80 -92 'ping_stats() { echo "20 30.0"; }; cmd_doctor')"
lib "doctor: wired default interface skips Wi-Fi" 0 "Everything looks healthy" "$(drwifi -80 -92 'WIFI_IF=en9; export WIFI_IF; cmd_doctor')"
lib_not "doctor: wired default interface prints no Wi-Fi line" "$(drwifi -80 -92 'WIFI_IF=en9; export WIFI_IF; cmd_doctor')" "Wi-Fi:"
lib "doctor: slow Wi-Fi read shows a note"     0 "reading the Wi-Fi details" "$DR; system_profiler() { sleep 1; printf '$SPROF' -50 -90; }; cmd_doctor"
lib "doctor: slow Wi-Fi read still gives the line" 0 "Wi-Fi: signal -50 dBm" "$DR; system_profiler() { sleep 1; printf '$SPROF' -50 -90; }; cmd_doctor"
lib "doctor: a hung Wi-Fi read is abandoned"   0 "Everything looks healthy" "$DR; NETDOCTOR_WIFI_WAIT=1; export NETDOCTOR_WIFI_WAIT; system_profiler() { sleep 30; }; cmd_doctor"
lib "doctor: a hung Wi-Fi read ends quickly"   0 "fast" "$DR; NETDOCTOR_WIFI_WAIT=1; export NETDOCTOR_WIFI_WAIT; system_profiler() { sleep 30; }; SECONDS=0; cmd_doctor >/dev/null; [ \$SECONDS -lt 10 ] && echo fast"
lib_not "doctor: a hung Wi-Fi read leaves no Wi-Fi line" "$DR; NETDOCTOR_WIFI_WAIT=1; export NETDOCTOR_WIFI_WAIT; system_profiler() { sleep 30; }; cmd_doctor" "Wi-Fi: signal"
lib_not "doctor: NETDOCTOR_NOWIFI skips the read" "$DR; NETDOCTOR_NOWIFI=1; export NETDOCTOR_NOWIFI; system_profiler() { printf '$SPROF' -80 -92; }; cmd_doctor" "Wi-Fi"
lib "doctor: no Wi-Fi data in the profile is silent" 0 "Everything looks healthy" "$DR; system_profiler() { :; }; cmd_doctor"
lib "doctor: no verdict line by default"        0 "" "$(drwifi -50 -90 'cmd_doctor | grep -c "^verdict=" | grep -qx 0')"
lib "doctor: verdict line when asked (healthy)" 0 "verdict=ok"   "$(drwifi -50 -90 'NETDOCTOR_VERDICT_LINE=1 cmd_doctor')"
lib "doctor: verdict line (weak Wi-Fi)"         1 "verdict=wifi" "$(drwifi -80 -92 'NETDOCTOR_VERDICT_LINE=1 cmd_doctor')"
lib "doctor: verdict line (DNS)"                1 "verdict=dns"  "$(drwifi -50 -90 'resolves() { return 1; }; NETDOCTOR_VERDICT_LINE=1 cmd_doctor')"
lib "doctor: verdict line is the last line of the output" 0 "verdict=ok" "$(drwifi -50 -90 'NETDOCTOR_VERDICT_LINE=1 cmd_doctor | tail -1')"
lib "fix: weak Wi-Fi has no automatic fix"    1 "weak Wi-Fi signal" "$(drwifi -80 -92 cmd_fix)"

# ---- 14. dnsset and dnsbench apply -----------------------------------------------------------------------
# a fake networksetup that keeps the DNS setting of "Wi-Fi" in a file and logs what it was asked to do
DNSST="$T/dns.state"
cat > "$T/fx/networksetup" <<E
#!/bin/sh
case "\$1" in
  -listnetworkserviceorder) printf 'An asterisk (*) denotes that a network service is disabled.\n(1) Ethernet\n(Hardware Port: Ethernet, Device: en0)\n\n(2) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en1)\n\n(*) Old VPN\n(Hardware Port: VPN, Device: ppp0)\n';;
  -getdnsservers) if [ -s "$DNSST" ]; then tr ' ' '\n' < "$DNSST"; else echo "There aren't any DNS Servers set on \$2."; fi;;
  -setdnsservers) echo "networksetup \$*" >> "$T/fx.log"; svc=\$2; shift 2; if [ "\$1" = empty ]; then : > "$DNSST"; else echo "\$*" > "$DNSST"; fi;;
esac
E
cat > "$T/fx/dig" <<'E'
#!/bin/sh
srv=system; for a in "$@"; do case "$a" in @*) srv=${a#@};; esac; done
case "$srv" in
  system) ms=${ND_DIG_SYS:-100};; 1.1.1.1) ms=10;; 8.8.8.8) ms=20;; 9.9.9.9) ms=30;; *) exit 9;;
esac
printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n;; Query time: %s msec\n' "$ms"
E
chmod +x "$T/fx/networksetup" "$T/fx/dig"
NH="$T/nh"; DNSENV="NETDOCTOR_HOME=$NH; export NETDOCTOR_HOME; default_if() { echo en1; }; resolves() { return 0; }"
dreset() { rm -rf "$NH"; : > "$DNSST"; }
fxlib "net_service: Wi-Fi"            0 "Wi-Fi"     "net_service en1"
fxlib "net_service: Ethernet"         0 "Ethernet"  "net_service en0"
fxlib "net_service: disabled service name has no star" 0 "Old VPN" "net_service ppp0"
fxlib "net_service: unknown interface" 0 "[]"       "echo \"[\$(net_service en9)]\""
for v in 2606:4700:4700::1111 ::1 2001:db8:: 1:2:3:4:5:6:7:8 fe80::1; do fxlib "dns_valid_ip: valid IPv6 $v" 0 "yes" "dns_valid_ip $v && echo yes || echo no"; done
for v in :::: :: 1:2 :1:2:3:4:5:6:7 1::2::3 12345::1 1:2:3:4:5:6:7:8:9 1:2:3:4:5:6:7::8 abc: :abc; do fxlib "dns_valid_ip: invalid IPv6 $v" 0 "no" "dns_valid_ip $v && echo yes || echo no"; done
fxlib "dns_service: normal default interface" 0 "Wi-Fi"     "default_if() { echo en1; }; dns_service"
fxlib "dns_service: VPN default route falls back to the active Ethernet" 0 "Ethernet" "default_if() { echo utun3; }; ipconfig() { [ \"\$2\" = en0 ] && echo 10.0.0.2; }; dns_service"
fxlib "dns_service: VPN default route, only Wi-Fi has an IP" 0 "Wi-Fi" "default_if() { echo utun3; }; ipconfig() { [ \"\$2\" = en1 ] && echo 10.0.0.3; }; dns_service"
fxlib "dns_service: VPN default route, nothing connected -> empty" 0 "[]" "default_if() { echo utun3; }; ipconfig() { :; }; echo \"[\$(dns_service)]\""
fxlib "dns_service: a disabled service is never chosen" 0 "[]" "default_if() { echo utun3; }; ipconfig() { [ \"\$2\" = ppp0 ] && echo 10.9.9.9; }; echo \"[\$(dns_service)]\""
dreset; fxlib "dnsset: VPN only, no guessing" 1 "Could not tell which network service" "$DNSENV; default_if() { echo utun3; }; ipconfig() { :; }; cmd_dnsset 1.1.1.1"
[ "$(grep -c 'setdnsservers' "$T/fx.log")" = 0 ] && pass || fail "dnsset: must not change anything when the service is unknown" "$(tr '\n' ';' < "$T/fx.log")"
dreset; fxlib "dnsset: sets two servers"  0 "automatic → 1.1.1.1 8.8.8.8" "$DNSENV; cmd_dnsset 1.1.1.1 8.8.8.8"
fxlog_has "dnsset: calls networksetup once with the servers" "networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8"
[ "$(grep -c 'setdnsservers' "$T/fx.log")" = 1 ] && pass || fail "dnsset: servers must not be passed twice" "$(tr '\n' ';' < "$T/fx.log")"
fxlog_has "dnsset: flushes the DNS cache" "dscacheutil -flushcache"
[ -f "$NH/dns-backup/Wi-Fi" ] && pass || fail "dnsset: writes a backup"
dreset; fxlib "dnsset: commas are accepted" 0 "1.1.1.1 8.8.8.8" "$DNSENV; cmd_dnsset 1.1.1.1,8.8.8.8"
dreset; fxlib "dnsset: IPv6 is accepted"    0 "2606:4700:4700::1111" "$DNSENV; cmd_dnsset 2606:4700:4700::1111"
# the backup keeps the FIRST original, even after several changes
dreset; fxlib "dnsset: first change" 0 "" "$DNSENV; cmd_dnsset 1.1.1.1 >/dev/null; cmd_dnsset 9.9.9.9 >/dev/null; cmd_dnsset show"
fxlib "dnsset: show lists the saved original" 0 "saved original: automatic" "$DNSENV; cmd_dnsset 1.1.1.1 >/dev/null; cmd_dnsset 9.9.9.9 >/dev/null; cmd_dnsset show"
fxlib "dnsset: restore goes back to automatic" 0 "Restored" "$DNSENV; cmd_dnsset restore"
fxlog_has "dnsset: restore uses empty" "setdnsservers Wi-Fi empty"
[ ! -f "$NH/dns-backup/Wi-Fi" ] && pass || fail "dnsset: restore removes the backup"
dreset; echo "192.168.0.1" > "$DNSST"
fxlib "dnsset: an existing manual DNS is remembered" 0 "192.168.0.1 → 1.1.1.1" "$DNSENV; cmd_dnsset 1.1.1.1"
fxlib "dnsset: restore brings the manual DNS back"   0 "Restored \"Wi-Fi\": 192.168.0.1" "$DNSENV; cmd_dnsset restore"
fxlib "dnsset: restore without backup" 1 "No saved original" "$DNSENV; rm -rf $NH; cmd_dnsset restore"
dreset; echo "192.168.0.1" > "$DNSST"
fxlib "dnsset: rolls back when nothing resolves" 1 "going back to the previous setting" "$DNSENV; resolves() { return 1; }; cmd_dnsset 1.1.1.1"
[ "$(cat "$DNSST")" = "192.168.0.1" ] && pass || fail "dnsset: rollback restored the old servers" "state: $(cat "$DNSST")"
[ ! -f "$NH/dns-backup/Wi-Fi" ] && pass || fail "dnsset: failed change leaves no backup behind"
dreset; fxlib "dnsset: auto" 0 "→ automatic" "$DNSENV; echo 1.1.1.1 > $DNSST; cmd_dnsset auto"
fxlib "dnsset: not an IP"            1 "Not an IP address" "$DNSENV; cmd_dnsset 'bad;host'"
fxlib "dnsset: injection attempt"    1 "Not an IP address" "$DNSENV; cmd_dnsset '1.1.1.1;ls'"
fxlib "dnsset: IPv6-looking injection" 1 "Not an IP address" "$DNSENV; cmd_dnsset '2606::1;ls'"
fxlib "dnsset: letters without colon"  1 "Not an IP address" "$DNSENV; cmd_dnsset abcd"
fxlib "dnsset: out of shape IPv4"    1 "Not an IP address" "$DNSENV; cmd_dnsset 1.1.1"
fxlib "dnsset: octet above 255"       1 "Not an IP address" "$DNSENV; cmd_dnsset 999.1.1.1"
fxlib "dnsset: last octet 256"         1 "Not an IP address" "$DNSENV; cmd_dnsset 1.1.1.256"
fxlib "dnsset: too many servers"     1 "1 to 4"            "$DNSENV; cmd_dnsset 1.1.1.1 8.8.8.8 9.9.9.9 4.4.4.4 5.5.5.5"
if [ "$(id -u)" != 0 ]; then
  lib "dnsset: no admin rights" 1 "Administrator rights" "default_if() { echo en1; }; networksetup() { :; }; cmd_dnsset 1.1.1.1"
fi
if [ "$(id -u)" != 0 ]; then   # bad input is reported before the administrator check
  lib "dnsset: bad IP is reported before the sudo check" 1 "Not an IP address" "default_if() { echo en1; }; networksetup() { :; }; cmd_dnsset '1.1.1.1;ls'"
fi
dreset; fxlib "dnsset: show without changes" 0 "automatic (from DHCP)" "$DNSENV; cmd_dnsset show"
# dnsbench apply: fake dig (system 100 ms, 1.1.1.1 10 ms, 8.8.8.8 20 ms, 9.9.9.9 30 ms, the rest fail)
dreset; fxlib "dnsbench: plan only without yes" 0 "Nothing was changed" "$DNSENV; cmd_dnsbench apply"
fxlib "dnsbench: plan names the two fastest" 0 "Set the DNS of \"Wi-Fi\" to 1.1.1.1 8.8.8.8" "$DNSENV; cmd_dnsbench apply"
[ ! -s "$DNSST" ] && pass || fail "dnsbench: plan only must not change anything" "state: $(cat "$DNSST")"
dreset; fxlib "dnsbench: yes switches" 0 "automatic → 1.1.1.1 8.8.8.8" "$DNSENV; cmd_dnsbench yes"
[ "$(cat "$DNSST")" = "1.1.1.1 8.8.8.8" ] && pass || fail "dnsbench: yes sets the two fastest" "state: $(cat "$DNSST")"
dreset; fxlib "dnsbench: without apply it only suggests" 0 "netdoctor dnsbench yes" "$DNSENV; cmd_dnsbench"
[ ! -s "$DNSST" ] && pass || fail "dnsbench without apply must not change anything"
dreset; fxlib "dnsbench: fast system DNS is left alone" 0 "not noticeably slower" "$DNSENV; ND_DIG_SYS=11; export ND_DIG_SYS; cmd_dnsbench yes"
[ ! -s "$DNSST" ] && pass || fail "dnsbench: nothing to switch must not change anything"
dreset; fxlib "dnsbench: fastest is the system DNS" 0 "already the fastest" "$DNSENV; ND_DIG_SYS=3; export ND_DIG_SYS; cmd_dnsbench yes"
fxlib "dnsbench: domain argument still works" 0 "DNS benchmark" "$DNSENV; cmd_dnsbench example.org"

# ---- 15. web UI: command line arguments built from the form -------------------------------------------
pyt() { # name 'python expression using g (the module), C (commands by id)' expected-output
  local out; out=$(python3 -c "import importlib.util as u; sp=u.spec_from_file_location('g','netdoctor-gui.py'); g=u.module_from_spec(sp); sp.loader.exec_module(g); C={c['id']:c for c in g.COMMANDS}
$2" 2>&1)
  if [ "$out" = "$3" ]; then pass; else fail "$1" "wanted: $3 -- got: $out"; fi
}
pyt "web args: both checkboxes"                    "print(g.build_args(C['report'],{'redact':'redact','html':'html'}))" "['redact', 'html']"
pyt "web args: only the second checkbox is kept"   "print(g.build_args(C['report'],{'redact':'','html':'html'}))" "['html']"
pyt "web args: only the first checkbox"            "print(g.build_args(C['report'],{'redact':'redact','html':''}))" "['redact']"
pyt "web args: no checkbox"                        "print(g.build_args(C['report'],{'redact':'','html':''}))" "[]"
pyt "web args: empty optional field, ticked box"   "print(g.build_args(C['dnsbench'],{'domain':'','yes':'yes'}))" "['yes']"
pyt "web args: filled field and ticked box"        "print(g.build_args(C['dnsbench'],{'domain':'example.org','yes':'yes'}))" "['example.org', 'yes']"
pyt "web args: filled field, unticked box"         "print(g.build_args(C['dnsbench'],{'domain':'example.org','yes':''}))" "['example.org']"
pyt "web args: positional fields after an empty one are not passed" "print(g.build_args({'inputs':[{'name':'a'},{'name':'b'},{'name':'f','flag':'go'}]},{'a':'','b':'2','f':'go'}))" "['go']"
pyt "web args: default value is used"              "print(g.build_args(C['dnsset'],{}))" "['show']"
pyt "web args: commas are fine"                    "print(g.build_args(C['dnsset'],{'servers':'1.1.1.1,8.8.8.8'}))" "['1.1.1.1,8.8.8.8']"
pyt "web args: a space is refused"                 "
try: g.build_args(C['dnsset'],{'servers':'1.1.1.1 8.8.8.8'})
except ValueError as e: print('refused')" "refused"
pyt "web args: a leading dash is refused"          "
try: g.build_args(C['dnsset'],{'servers':'-x'})
except ValueError as e: print('refused')" "refused"
pyt "web args: a required field must be filled"    "
try: g.build_args(C['mtr'],{'host':''})
except ValueError as e: print('refused')" "refused"

# ---- result ------------------------------------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then echo "all $PASS tests passed"; exit 0; fi
echo "$FAIL failed, $PASS passed"; exit 1
