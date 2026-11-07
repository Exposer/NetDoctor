import Foundation

/// Looks a UI string up in the app's Localizable.strings (English text is the key).
func loc(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ToolInput: Identifiable {
    let name: String
    let label: String
    var placeholder: String = ""
    var required: Bool = false
    var defaultValue: String = ""
    var id: String { name }
}

enum AdminMode { case none, optional, required }

struct Tool: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String          // SF Symbol
    let summary: String
    var inputs: [ToolInput] = []
    var admin: AdminMode = .none

    static func == (a: Tool, b: Tool) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [Tool] = [
        Tool(id: "quick", title: "Quick check", icon: "stethoscope",
             summary: "Gateway → public IP → DNS → HTTP, layer by layer, with a diagnosis"),
        Tool(id: "doctor", title: "Diagnose", icon: "cross.case",
             summary: "Layer-by-layer checks with a verdict and suggested next steps"),
        Tool(id: "overview", title: "Overview", icon: "list.bullet.rectangle",
             summary: "Interface, IP, gateway, DNS, Wi-Fi, proxy and public IP at a glance"),
        Tool(id: "dhcp", title: "DHCP / IP address", icon: "arrow.triangle.2.circlepath",
             summary: "Check the DHCP lease and spot a self-assigned 169.254 address (DHCP failed)"),
        Tool(id: "ports", title: "Multi-port check", icon: "square.grid.3x3",
             summary: "Check common or custom ports on a host in parallel",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "example.com", required: true),
                      ToolInput(name: "ports", label: "Ports", placeholder: "22,80,443 or 1-1024")]),
        Tool(id: "tcpping", title: "TCP ping", icon: "timer",
             summary: "TCP connect latency to a port — for when ping is blocked",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "example.com", required: true),
                      ToolInput(name: "port", label: "Port", placeholder: "443", required: true),
                      ToolInput(name: "count", label: "Count", placeholder: "10", defaultValue: "10")]),
        Tool(id: "ipv6", title: "IPv6 check", icon: "6.circle",
             summary: "Compare IPv4 / IPv6 connectivity and spot a broken IPv6 path"),
        Tool(id: "captive", title: "Captive portal", icon: "wifi.exclamationmark",
             summary: "Wi-Fi connected but no web access? Detect a login page"),
        Tool(id: "lan", title: "LAN scan", icon: "network",
             summary: "Discover devices on the local network (IP, MAC, name)"),
        Tool(id: "wifi", title: "Wi-Fi", icon: "wifi",
             summary: "SSID, signal, noise, channel, rate", admin: .optional),
        Tool(id: "dns", title: "DNS compare", icon: "magnifyingglass",
             summary: "Answers and timings from the system and several public DNS servers",
             inputs: [ToolInput(name: "domain", label: "Domain", placeholder: "example.com", required: true)]),
        Tool(id: "dnsbench", title: "DNS benchmark", icon: "gauge.with.dots.needle.67percent",
             summary: "Compare the system and public DNS servers by speed and get a recommendation",
             inputs: [ToolInput(name: "domain", label: "Domain", placeholder: "extra domain (optional)")]),
        Tool(id: "http", title: "HTTP timing", icon: "globe",
             summary: "DNS / TCP / TLS / first byte / total breakdown",
             inputs: [ToolInput(name: "url", label: "URL", placeholder: "https://example.com", required: true)]),
        Tool(id: "ping", title: "Ping", icon: "dot.radiowaves.left.and.right",
             summary: "Packet loss and latency statistics",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "1.1.1.1", required: true),
                      ToolInput(name: "count", label: "Count", placeholder: "20", defaultValue: "20")]),
        Tool(id: "route", title: "Route / path", icon: "point.topleft.down.curvedto.point.bottomright.up",
             summary: "Which interface / VPN is used, plus hop-by-hop mtr / traceroute",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "example.com", required: true)],
             admin: .optional),
        Tool(id: "port", title: "Port check", icon: "door.left.hand.open",
             summary: "Is the TCP port reachable",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "example.com", required: true),
                      ToolInput(name: "port", label: "Port", placeholder: "443", required: true)]),
        Tool(id: "tls", title: "TLS certificate", icon: "lock.shield",
             summary: "Certificate, protocol, validity",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "example.com", required: true),
                      ToolInput(name: "port", label: "Port", placeholder: "443")]),
        Tool(id: "mtu", title: "MTU probe", icon: "ruler",
             summary: "Path MTU; troubleshoot VPN / large-packet loss",
             inputs: [ToolInput(name: "host", label: "Host", placeholder: "1.1.1.1")]),
        Tool(id: "speed", title: "Speed test", icon: "speedometer",
             summary: "networkQuality bandwidth and responsiveness (~20 s)"),
        Tool(id: "conns", title: "Connections", icon: "cable.connector",
             summary: "Listening ports and connections by process", admin: .required),
        Tool(id: "proxy", title: "Proxy / VPN", icon: "shield.lefthalf.filled",
             summary: "System proxy, environment variables, VPN and utun"),
        Tool(id: "fixdns", title: "Flush DNS", icon: "arrow.triangle.2.circlepath",
             summary: "Clear the DNS cache and restart mDNSResponder", admin: .required),
        Tool(id: "report", title: "Export report", icon: "doc.text",
             summary: "Save a combined report to the Desktop"),
        Tool(id: "tools", title: "Tool check", icon: "wrench.and.screwdriver",
             summary: "Which system and third-party tools are installed"),
    ]
}
