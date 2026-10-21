import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One page of a timetable document, already turned into a grid when it held one.
nonisolated struct TimetableDocumentPage: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String?
    let draft: ImportedTimetableDraft?
}

enum TimetableDocumentError: LocalizedError, Equatable {
    case unreadable
    case noTimetable

    var errorDescription: String? {
        switch self {
        case .unreadable: AppL10n.string("friends.import.error.unreadable")
        case .noTimetable: AppL10n.string("friends.import.error.noTimetable")
        }
    }
}

/// Reads positioned text out of a PDF (its text layer, or OCR for scans) or a
/// photo, entirely on the device, and hands it to `TimetableGridReconstructor`.
nonisolated enum TimetableDocumentReader {
    /// Pages after this are ignored: a whole-school export can run to dozens.
    static let maxPages = 60

    static func read(fileAt url: URL) async throws -> [TimetableDocumentPage] {
        let data = try Data(contentsOf: url)
        return try await read(data: data)
    }

    static func read(data: Data) async throws -> [TimetableDocumentPage] {
        try await Task.detached(priority: .userInitiated) {
            let pages: [(runs: [TimetableTextRun], sizesAreReliable: Bool)]
            if let document = PDFDocument(data: data), document.pageCount > 0 {
                pages = try (0..<min(document.pageCount, maxPages)).compactMap { index in
                    guard let page = document.page(at: index) else { return nil }
                    let runs = textRuns(on: page)
                    return runs.count >= 12 ? (runs, true) : (try recognizedRuns(in: rendered(page)), false)
                }
            } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) {
                let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32
                pages = [(try recognizedRuns(in: image, orientation: orientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up), false)]
            } else {
                throw TimetableDocumentError.unreadable
            }

            let result = pages.enumerated().map { index, page in
                TimetableDocumentPage(
                    id: index,
                    title: TimetableGridReconstructor.title(of: page.runs),
                    draft: TimetableGridReconstructor.reconstruct(page.runs, sizesAreReliable: page.sizesAreReliable)
                )
            }
            guard result.contains(where: { $0.draft != nil }) else { throw TimetableDocumentError.noTimetable }
            return result
        }.value
    }

    // MARK: - PDF text layer

    /// Characters grouped into runs: a new run starts at whitespace gaps wider
    /// than about half a letter, or when the text jumps to another line.
    static func textRuns(on page: PDFPage) -> [TimetableTextRun] {
        guard let string = page.string, !string.isEmpty else { return [] }
        let text = string as NSString
        let attributed = page.attributedString
        let display = page.bounds(for: .mediaBox).applying(page.transform(for: .mediaBox))
        let transform = page.transform(for: .mediaBox)

        var runs: [TimetableTextRun] = []
        var current: (text: String, frame: CGRect, size: CGFloat)?

        func flush() {
            if let run = current, !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runs.append(TimetableTextRun(
                    text: run.text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping,
                    frame: run.frame,
                    fontSize: run.size
                ))
            }
            current = nil
        }

        for index in 0..<text.length {
            let character = text.substring(with: NSRange(location: index, length: 1))
            // Browsers break text into chunks with newlines in odd places, so
            // only the geometry decides where a run ends. `characterBounds(at:)`
            // drifts after an inline image (U+FFFC); a one-character selection
            // stays on the right glyph.
            guard character.rangeOfCharacter(from: .newlines) == nil, character != "\u{FFFC}",
                  let selection = page.selection(for: NSRange(location: index, length: 1)),
                  selection.string == character
            else { continue }
            let bounds = selection.bounds(for: page).applying(transform)
            guard bounds.width > 0 || bounds.height > 0 else {
                // Combining marks come without a box; keep them with their letter.
                current?.text += character
                continue
            }
            let frame = CGRect(x: bounds.minX - display.minX, y: display.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
            let size = fontSize(in: attributed, at: index) ?? frame.height
            let isSpace = character.trimmingCharacters(in: .whitespaces).isEmpty

            if var run = current {
                let sameLine = abs(frame.midY - run.frame.midY) <= max(frame.height, run.frame.height) * 0.5
                let gap = frame.minX - run.frame.maxX
                if sameLine, gap > -frame.height * 0.3, gap < max(frame.height, run.frame.height) * 0.55, abs(size - run.size) < run.size * 0.2 {
                    run.text += character
                    if !isSpace { run.frame = run.frame.union(frame) }
                    current = run
                    continue
                }
                flush()
            }
            if !isSpace {
                current = (character, frame, size)
            }
        }
        flush()
        return runs
    }

    private static func fontSize(in attributed: NSAttributedString?, at index: Int) -> CGFloat? {
        guard let attributed, index < attributed.length else { return nil }
        #if os(macOS)
        return (attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize
        #else
        return (attributed.attribute(.font, at: index, effectiveRange: nil) as? UIFont)?.pointSize
        #endif
    }

    private static func rendered(_ page: PDFPage) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox).applying(page.transform(for: .mediaBox))
        let scale = 2400 / max(bounds.width, bounds.height, 1)
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw TimetableDocumentError.unreadable }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw TimetableDocumentError.unreadable }
        return image
    }

    // MARK: - OCR

    /// Vision reads lines; each line is split into words with their own boxes
    /// and re-joined where the gap is small, so neighbouring cells stay apart.
    static func recognizedRuns(in image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [TimetableTextRun] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["cs-CZ", "en-US"].filter { supported.contains($0) }

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])

        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = CGFloat(rotated ? image.height : image.width)
        let height = CGFloat(rotated ? image.width : image.height)

        var runs: [TimetableTextRun] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var words: [TimetableTextRun] = []
            var index = string.startIndex
            while index < string.endIndex {
                guard let start = string[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let end = string[start...].firstIndex(where: \.isWhitespace) ?? string.endIndex
                if let box = try? candidate.boundingBox(for: start..<end)?.boundingBox {
                    let frame = CGRect(
                        x: box.minX * width, y: (1 - box.maxY) * height,
                        width: box.width * width, height: box.height * height
                    )
                    words.append(TimetableTextRun(text: String(string[start..<end]), frame: frame, fontSize: frame.height))
                }
                index = end
            }

            var current: TimetableTextRun?
            for word in words {
                if var run = current, word.frame.minX - run.frame.maxX < run.frame.height * 0.6 {
                    run.text += " " + word.text
                    run.frame = run.frame.union(word.frame)
                    current = run
                } else {
                    current.map { runs.append($0) }
                    current = word
                }
            }
            current.map { runs.append($0) }
        }
        return runs
    }
}
