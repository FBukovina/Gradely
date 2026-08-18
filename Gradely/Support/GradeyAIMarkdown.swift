import SwiftUI

enum GradeyAIMarkdownBlock: Equatable, Sendable {
    case heading(String, level: Int)
    case paragraph(String)
    case list([String])
}

enum GradeyAIMarkdown {
    static func blocks(from markdown: String) -> [GradeyAIMarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [GradeyAIMarkdownBlock] = []
        var paragraphLines: [String] = []
        var listItems: [String] = []

        func flushParagraph() {
            let text = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushList() {
            if !listItems.isEmpty {
                blocks.append(.list(listItems))
            }
            listItems.removeAll(keepingCapacity: true)
        }

        for rawLine in normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if let heading = heading(from: line) {
                flushParagraph()
                flushList()
                blocks.append(.heading(heading.text, level: heading.level))
                continue
            }
            if let item = listItem(from: line) {
                flushParagraph()
                listItems.append(item)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                flushList()
                continue
            }
            flushList()
            paragraphLines.append(line)
        }

        flushParagraph()
        flushList()
        return blocks
    }

    static func inlineAttributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(markdown)
    }

    private static func heading(from line: String) -> (text: String, level: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: /^(#{1,6})\s+(.+?)\s*#*\s*$/) else {
            return nil
        }
        let text = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (text, match.1.count)
    }

    private static func listItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: /^[-*+]\s+(.+)$/) {
            return String(match.1)
        }
        if let match = trimmed.wholeMatch(of: /^\d+[.)]\s+(.+)$/) {
            return String(match.1)
        }
        return nil
    }
}

struct GradeyAIMarkdownText: View {
    let markdown: String

    var body: some View {
        let blocks = GradeyAIMarkdown.blocks(from: markdown)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text, let level):
                    Text(GradeyAIMarkdown.inlineAttributed(text))
                        .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, 2)
                case .paragraph(let text):
                    Text(GradeyAIMarkdown.inlineAttributed(text))
                        .fixedSize(horizontal: false, vertical: true)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Brand.primary)
                                    .accessibilityHidden(true)
                                Text(GradeyAIMarkdown.inlineAttributed(item))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
}
