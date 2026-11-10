import SwiftUI

/// The Recap mark: a ring that rewinds, with a solid head at the top that
/// points back. One colour, so it sits on every slide and tile colour.
struct RecapMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let radius = side * 0.335
        // Off centre, so the head stays inside the frame.
        let center = CGPoint(x: origin.x + side * 0.52, y: origin.y + side * 0.58)

        var ring = Path()
        // SwiftUI's y axis points down, so this runs clockwise on screen:
        // from the top, around the right and the bottom, up the left side.
        ring.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(198), clockwise: false)
        var path = ring.strokedPath(StrokeStyle(lineWidth: side * 0.14, lineCap: .round))

        let half = side * 0.2
        let corner = side * 0.035
        let baseX = center.x + side * 0.01
        let middle = center.y - radius
        let top = CGPoint(x: baseX, y: middle - half)
        let bottom = CGPoint(x: baseX, y: middle + half)
        let apex = CGPoint(x: baseX - side * 0.25, y: middle)

        var head = Path()
        head.move(to: CGPoint(x: baseX, y: middle))
        head.addArc(tangent1End: top, tangent2End: apex, radius: corner)
        head.addArc(tangent1End: apex, tangent2End: bottom, radius: corner)
        head.addArc(tangent1End: bottom, tangent2End: top, radius: corner)
        head.closeSubpath()
        path.addPath(head)
        return path
    }
}

/// The Gradey Recap logo: the mark next to "Recap", in the foreground colour
/// around it. A fixed size, like any logo, so the mark and the word stay in
/// proportion at every text size.
struct RecapLogo: View {
    /// The point size of "Recap". The mark is as tall.
    var size: CGFloat = 18
    /// A small "Gradey" above, where the logo stands alone.
    var showsGradey = false

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.08) {
            if showsGradey {
                Text(verbatim: "Gradey")
                    .font(.gradely(size: size * 0.5, weight: .bold))
                    .opacity(0.7)
            }
            HStack(spacing: size * 0.25) {
                RecapMark()
                    .frame(width: size, height: size)
                Text(verbatim: "Recap")
                    .font(.gradely(size: size, weight: .bold))
            }
        }
        .dynamicTypeSize(.large)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Gradey Recap"))
    }
}
