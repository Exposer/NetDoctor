import Foundation

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
        Tool(id: "quick", title: "一键体检", icon: "stethoscope",
             summary: "网关 → 外网 IP → DNS → HTTP 逐层检查并给出判读"),
        Tool(id: "wifi", title: "Wi-Fi", icon: "wifi",
             summary: "SSID、信号、噪声、信道、速率", admin: .optional),
        Tool(id: "dns", title: "DNS 对比", icon: "magnifyingglass",
             summary: "系统与多家公共 DNS 的解析结果与耗时",
             inputs: [ToolInput(name: "domain", label: "域名", placeholder: "example.com", required: true)]),
        Tool(id: "http", title: "HTTP 耗时", icon: "globe",
             summary: "DNS / TCP / TLS / 首字节 / 总耗时分解",
             inputs: [ToolInput(name: "url", label: "URL", placeholder: "https://example.com", required: true)]),
        Tool(id: "ping", title: "Ping", icon: "dot.radiowaves.left.and.right",
             summary: "丢包与延迟统计",
             inputs: [ToolInput(name: "host", label: "主机", placeholder: "1.1.1.1", required: true),
                      ToolInput(name: "count", label: "次数", placeholder: "20", defaultValue: "20")]),
        Tool(id: "route", title: "路由 / 路径", icon: "point.topleft.down.curvedto.point.bottomright.up",
             summary: "走哪块网卡 / VPN,以及 mtr / traceroute 逐跳",
             inputs: [ToolInput(name: "host", label: "主机", placeholder: "example.com", required: true)],
             admin: .optional),
        Tool(id: "port", title: "端口检测", icon: "door.left.hand.open",
             summary: "TCP 端口是否可连",
             inputs: [ToolInput(name: "host", label: "主机", placeholder: "example.com", required: true),
                      ToolInput(name: "port", label: "端口", placeholder: "443", required: true)]),
        Tool(id: "tls", title: "TLS 证书", icon: "lock.shield",
             summary: "证书、协议、有效期",
             inputs: [ToolInput(name: "host", label: "主机", placeholder: "example.com", required: true),
                      ToolInput(name: "port", label: "端口", placeholder: "443")]),
        Tool(id: "mtu", title: "MTU 探测", icon: "ruler",
             summary: "路径 MTU,排查 VPN / 大包丢失",
             inputs: [ToolInput(name: "host", label: "主机", placeholder: "1.1.1.1")]),
        Tool(id: "speed", title: "测速", icon: "speedometer",
             summary: "networkQuality 带宽与响应性(约 20 秒)"),
        Tool(id: "conns", title: "连接 / 监听", icon: "cable.connector",
             summary: "按进程列出监听端口与连接", admin: .required),
        Tool(id: "proxy", title: "代理 / VPN", icon: "shield.lefthalf.filled",
             summary: "系统代理、环境变量、VPN 与 utun"),
        Tool(id: "fixdns", title: "刷新 DNS", icon: "arrow.triangle.2.circlepath",
             summary: "清除 DNS 缓存并重启 mDNSResponder", admin: .required),
        Tool(id: "report", title: "导出报告", icon: "doc.text",
             summary: "保存综合报告到桌面"),
        Tool(id: "tools", title: "工具检查", icon: "wrench.and.screwdriver",
             summary: "系统与第三方工具安装情况"),
    ]
}
