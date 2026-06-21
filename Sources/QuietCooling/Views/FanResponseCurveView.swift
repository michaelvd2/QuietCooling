import SwiftUI

/// Nerd-mode visualization: what macOS would do (dashed) versus your QuietCooling
/// ramp (floor + gain·boost, started `lead` °C earlier), capped at the audible line
/// and rejoining macOS at real heat. Illustrative — not the exact controller output.
struct FanResponseCurveView: View {
    let strength: PreCoolingStrength
    let audibleRPM: Int
    let range: FanRange

    private let t0: Double = 45
    private let t1: Double = 85

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 16

            let audibleY = y(Double(audibleRPM), h: h)
            let floorY = y(Double(strength.floorRPM), h: h)

            ZStack(alignment: .topLeading) {
                // Audible cap.
                line(yValue: audibleY, width: w, color: .orange, dash: [5, 3])
                Text("audible").font(.system(size: 10)).foregroundStyle(.orange)
                    .position(x: w - 22, y: max(8, audibleY - 8))

                // Raised floor.
                line(yValue: floorY, width: w, color: .blue.opacity(0.4), dash: [2, 3])

                // macOS curve (dashed) and the QuietCooling ramp (solid blue).
                curvePath(width: w, h: h) { macOS($0) }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                curvePath(width: w, h: h) { qc($0) }
                    .stroke(Color.blue, lineWidth: 2)
            }
            .frame(width: w, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private func line(yValue: CGFloat, width: CGFloat, color: Color, dash: [CGFloat]) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: yValue))
            p.addLine(to: CGPoint(x: width, y: yValue))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1, dash: dash))
    }

    private func curvePath(width: CGFloat, h: CGFloat, _ fn: (Double) -> Double) -> Path {
        Path { p in
            var first = true
            var t = t0
            while t <= t1 {
                let pt = CGPoint(x: x(t, width: width), y: y(fn(t), h: h))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                t += 2
            }
        }
    }

    private func macOS(_ t: Double) -> Double {
        let lo = Double(range.minimumRPM)
        let hi = Double(range.maximumRPM)
        let denominator: Double = 1 + exp(-0.30 * (t - 78))
        return lo + (hi - lo) / denominator
    }

    private func qc(_ t: Double) -> Double {
        let idle = Double(range.minimumRPM)
        let extra = max(0, macOS(t + Double(strength.leadC)) - idle)
        var v = Double(strength.floorRPM) + strength.gain * extra
        v = min(v, Double(audibleRPM))
        return max(v, macOS(t))
    }

    private func x(_ t: Double, width: CGFloat) -> CGFloat {
        CGFloat((t - t0) / (t1 - t0)) * width
    }

    private func y(_ rpm: Double, h: CGFloat) -> CGFloat {
        let lo = Double(range.minimumRPM)
        let hi = Double(range.maximumRPM)
        guard hi > lo else { return h }
        let frac = (rpm - lo) / (hi - lo)
        return h - CGFloat(min(max(frac, 0), 1)) * h
    }
}
