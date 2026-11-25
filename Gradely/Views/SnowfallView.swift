import SwiftUI

/// Light snow falling behind the top of Today while `ChristmasSeason` is on.
/// Purely decorative: no hit testing, hidden from VoiceOver, gone with
/// Reduce Motion, and still while the scene isn't active.
struct SnowfallView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private static let flakes: [Flake] = (0..<42).map(Flake.init(seed:))

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { context in
                Canvas { canvas, size in
                    let time = context.date.timeIntervalSinceReferenceDate
                    for flake in Self.flakes {
                        let rect = flake.frame(at: time, in: size)
                        canvas.fill(
                            Path(ellipseIn: rect),
                            with: .color(flakeColor.opacity(flake.opacity))
                        )
                    }
                }
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// White disappears on the light background, so light mode gets a cool
    /// grey-blue.
    private var flakeColor: Color {
        colorScheme == .dark
            ? .white
            : Color(.sRGB, red: 0.62, green: 0.69, blue: 0.80)
    }
}

private struct Flake {
    let x: Double
    let phase: Double
    let diameter: Double
    let speed: Double
    let sway: Double
    let swaySpeed: Double
    let opacity: Double

    /// The same flakes every launch: values come from the index.
    init(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed + 1))
        x = .random(in: 0...1, using: &generator)
        phase = .random(in: 0...1, using: &generator)
        diameter = .random(in: 2...5, using: &generator)
        speed = .random(in: 18...40, using: &generator)
        sway = .random(in: 4...14, using: &generator)
        swaySpeed = .random(in: 0.4...1.1, using: &generator)
        opacity = .random(in: 0.45...0.9, using: &generator)
    }

    func frame(at time: TimeInterval, in size: CGSize) -> CGRect {
        let travel = size.height + diameter * 2
        let y = (phase * travel + time * speed).truncatingRemainder(dividingBy: travel) - diameter
        let x = x * size.width + sin(time * swaySpeed + phase * .pi * 2) * sway
        return CGRect(x: x - diameter / 2, y: y, width: diameter, height: diameter)
    }
}

/// SplitMix64, so the flakes don't depend on the system random source.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
