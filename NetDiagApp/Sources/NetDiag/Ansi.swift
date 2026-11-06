import SwiftUI

/// 把带 ANSI 颜色码的文本转成 AttributedString,并保留跨块的样式状态。
struct AnsiParser {
    private var bold = false
    private var dim = false
    private var color: Color? = nil
    private static let baseColor = Color(white: 0.85)
    private static let regex = try! NSRegularExpression(pattern: "\u{1B}\\[(\\d+)m")

    mutating func parse(_ text: String) -> AttributedString {
        var out = AttributedString()
        let ns = text as NSString
        var last = 0
        for m in Self.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                out += segment(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            }
            apply(code: Int(ns.substring(with: m.range(at: 1))) ?? 0)
            last = m.range.location + m.range.length
        }
        if last < ns.length { out += segment(ns.substring(from: last)) }
        return out
    }

    private mutating func apply(code: Int) {
        switch code {
        case 0, 22: bold = false; dim = false; color = nil
        case 1: bold = true
        case 2: dim = true
        case 31: color = Color(red: 1.0, green: 0.27, blue: 0.23)
        case 32: color = Color(red: 0.20, green: 0.84, blue: 0.29)
        case 33: color = Color(red: 1.0, green: 0.84, blue: 0.04)
        default: break
        }
    }

    private func segment(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.font = .system(size: 12.5, weight: bold ? .bold : .regular, design: .monospaced)
        a.foregroundColor = (color ?? Self.baseColor).opacity(dim ? 0.55 : 1)
        return a
    }

    static func strip(_ s: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }
}
