import SwiftUI

struct LessonProgressArc: View {
    var progress: Double
    var isCanceled: Bool

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(90))

            if isCanceled {
                Circle()
                    .trim(from: 0.12, to: 0.12 + (0.76 * min(max(progress, 0), 1)))
                    .stroke(WatchBrand.canceled, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(90))
            } else {
                Circle()
                    .trim(from: 0.12, to: 0.12 + (0.76 * min(max(progress, 0), 1)))
                    .stroke(WatchBrand.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(90))
            }

            if isCanceled {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(WatchBrand.canceled, in: Circle())
                    .offset(x: -42, y: 28)
            }
        }
    }
}
