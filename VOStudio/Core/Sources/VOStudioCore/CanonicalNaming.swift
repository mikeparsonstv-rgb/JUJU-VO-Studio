import Foundation

/// `<JobName>-<ActorName>-YYYY-MM-DD-Line01-Take01.wav` (brief §7). Display names stay separate and unchanged.
public enum CanonicalNaming {
    /// Filename-safe token: diacritics stripped, words joined in CamelCase, ASCII letters and digits only.
    /// "Lenor Autumn DE" → "LenorAutumnDE", "Zoë" → "Zoe", "anna-lena" → "AnnaLena".
    public static func token(_ display: String, fallback: String, maxLength: Int = 40) -> String {
        let folded = display.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? display
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let joined = words.map { w -> String in
            let s = String(w)
            return s.prefix(1).uppercased() + s.dropFirst()
        }.joined()
        let token = String(joined.prefix(maxLength))
        return token.isEmpty ? fallback : token
    }

    /// Actor token unique within a job: "Anna", then "Anna2", "Anna3" for further actors with the same name.
    public static func uniqueActorToken(_ display: String, taken: Set<String>) -> String {
        let base = token(display, fallback: "Actor")
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base)\(n)".lowercased()) { n += 1 }
        return "\(base)\(n)"
    }

    public static func lineToken(_ lineKey: Int) -> String { lineKey == 0 ? "FullRead" : String(format: "Line%02d", lineKey) }

    /// Basename without extension. `productionDate` is the local yyyy-MM-dd at take creation (not export).
    public static func basename(jobToken: String, actorToken: String, productionDate: String, lineKey: Int, takeNumber: Int) -> String {
        "\(jobToken)-\(actorToken)-\(productionDate)-\(lineToken(lineKey))-Take\(String(format: "%02d", takeNumber))"
    }

    public static func productionDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Recall lookup key for a file name: extension dropped, Finder/mail copy suffixes are NOT stripped
    /// (no fuzzy matching), Unicode-normalised and case-folded so "take04.WAV" from a case-insensitive disk still matches.
    public static func lookupKey(forFileName name: String) -> String {
        var n = name
        if n.lowercased().hasSuffix(".wav") { n = String(n.dropLast(4)) }
        return n.precomposedStringWithCanonicalMapping.lowercased()
    }
}
