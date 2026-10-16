import Foundation
import NaturalLanguage

/// Turns a markdown answer into something pleasant to hear.
enum SpeechText {
    static let maxCharacters = 3000

    static func clean(_ markdown: String) -> String {
        var t = markdown
        t = t.replacing(#"```[\s\S]*?```"#, with: " ")                 // code blocks
        t = t.replacing(#"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1")       // links -> link text
        t = t.replacing(#"https?://\S+"#, with: "")                    // bare URLs
        t = t.replacing(#"`([^`]*)`"#, with: "$1")                     // inline code
        t = t.replacing(#"<[^>]+>"#, with: "")                         // html tags

        var lines: [String] = []
        for var line in t.components(separatedBy: .newlines) {
            if line.range(of: #"^\s*\|?\s*:?-{3,}"#, options: .regularExpression) != nil { continue } // table rules
            line = line.replacing(#"^\s*(#{1,6}|>|[-*+])\s+"#, with: "")  // headings, quotes, bullets
            line = line.replacingOccurrences(of: "|", with: ", ")
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "__", with: "")
            line = line.replacingOccurrences(of: "→", with: " to ")
            line = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
            guard !line.isEmpty else { continue }
            // Give each line a pause so bullets don't run together.
            if let last = line.last, !".!?:;".contains(last) { line += "." }
            lines.append(line)
        }
        t = lines.joined(separator: " ")
        t = t.replacing(#"\s+"#, with: " ").trimmingCharacters(in: .whitespaces)

        if t.count > maxCharacters {
            let cut = t.prefix(maxCharacters)
            let end = cut.lastIndex(where: { ".!?".contains($0) }) ?? cut.endIndex
            t = String(cut[..<end]) + ". There's more on screen."
        }
        return t
    }

    /// First sentence alone (so speech starts fast), then groups of ~400 chars.
    static func chunks(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        var chunks: [String] = []
        var current = ""
        for s in sentences {
            if chunks.isEmpty && current.isEmpty {
                chunks.append(s)
            } else if current.count + s.count > 400 {
                chunks.append(current)
                current = s
            } else {
                current += current.isEmpty ? s : " " + s
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

extension String {
    func replacing(_ pattern: String, with template: String) -> String {
        replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
