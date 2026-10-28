import Foundation

/// Minimal iXML (https://www.ixml.info) writer/reader for the fields JUJU uses.
/// JUJU identifiers live as `KEY=VALUE` lines inside `<USER>`, the spec's free-text application field;
/// no non-standard top-level elements are emitted.
public enum IXML {
    public static let version = "2.10"

    public struct Document: Equatable, Sendable {
        public var project: String?     // job display name
        public var scene: String?       // "Line03" / "FullRead"
        public var take: Int?
        public var note: String?
        public var user: [(key: String, value: String)]
        public init(project: String? = nil, scene: String? = nil, take: Int? = nil, note: String? = nil,
                    user: [(key: String, value: String)] = []) {
            self.project = project; self.scene = scene; self.take = take; self.note = note; self.user = user
        }
        public static func == (l: Document, r: Document) -> Bool {
            l.project == r.project && l.scene == r.scene && l.take == r.take && l.note == r.note &&
            l.user.map(\.key) == r.user.map(\.key) && l.user.map(\.value) == r.user.map(\.value)
        }
    }

    public static func encode(_ doc: Document) -> Data {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<BWFXML>\n"
        x += "  <IXML_VERSION>\(version)</IXML_VERSION>\n"
        if let p = doc.project { x += "  <PROJECT>\(escape(p))</PROJECT>\n" }
        if let s = doc.scene { x += "  <SCENE>\(escape(s))</SCENE>\n" }
        if let t = doc.take { x += "  <TAKE>\(t)</TAKE>\n" }
        if let n = doc.note { x += "  <NOTE>\(escape(n))</NOTE>\n" }
        if !doc.user.isEmpty {
            x += "  <USER>" + doc.user.map { "\($0.key)=\(escape($0.value))" }.joined(separator: "\n") + "</USER>\n"
        }
        x += "</BWFXML>\n"
        return Data(x.utf8)
    }

    /// Chunk text with trailing NUL/space padding removed.
    static func text(from body: Data) -> String {
        let trimmed = body.reversed().drop { $0 == 0 || $0 == 0x20 }.reversed()
        return String(decoding: Array(trimmed), as: UTF8.self)
    }

    /// Text content of every occurrence of `<tag>` (non-nested elements only), unescaped.
    public static func elements(_ tag: String, in xml: String) -> [String] {
        var out: [String] = []
        var rest = xml[...]
        while let open = rest.range(of: "<\(tag)>"), let close = rest.range(of: "</\(tag)>", range: open.upperBound..<rest.endIndex) {
            out.append(unescape(String(rest[open.upperBound..<close.lowerBound])))
            rest = rest[close.upperBound...]
        }
        return out
    }

    /// `KEY=VALUE` pairs from USER text (lines or `;`-separated), keys upper-cased, whitespace trimmed.
    public static func userPairs(_ userText: String) -> [(key: String, value: String)] {
        userText.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == ";" }).compactMap { line in
            guard let eq = line.firstIndex(of: "=") else { return nil }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces).uppercased()
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return k.isEmpty ? nil : (k, v)
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
