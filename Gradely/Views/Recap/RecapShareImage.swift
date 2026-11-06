import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A 1080 × 1920 PNG of one slide for Instagram stories and the like. It
/// carries the Gradey wordmark and the period, never a name or school.
enum RecapShareImage {
    static let size = CGSize(width: 360, height: 640)

    static func render(_ recap: Recap, slide: RecapSlide, number: Int) -> URL? {
        let renderer = ImageRenderer(content: RecapShareCanvas(recap: recap, slide: slide))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { return nil }

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Gradey Recap", directoryHint: .isDirectory)
            .appending(path: recap.period.id, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Gradey Recap \(number).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}

private struct RecapShareCanvas: View {
    let recap: Recap
    let slide: RecapSlide

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RecapSlideView(recap: recap, slide: slide, animated: false, showsLogo: false)
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                // The logo is the wordmark itself.
                Image("GradeyLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
                    .accessibilityLabel(Text(verbatim: "Gradey"))
                Spacer()
                if slide != .intro && slide != .summary {
                    Text(verbatim: RecapText.title(recap.period))
                        .font(.gradely(.subheadline).weight(.semibold))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(RecapPalette.ink)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, 48)
        .padding(.bottom, Spacing.xl)
        .frame(width: RecapShareImage.size.width, height: RecapShareImage.size.height)
        .background(RecapPalette.background(for: slide, in: recap))
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }
}
