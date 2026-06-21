import SwiftUI

/// The unified fan instrument: one track showing the quiet/audible field, the live
/// fan speed as a draggable throttle (white bar), the user-calibrated audible line
/// (amber), and what macOS would set the fan to (muted dot) with a connector that
/// makes the gap read as the pre-cool boost.
struct QuietGaugeView: View {
    let range: FanRange
    let fanRPM: Int
    let audibleRPM: Int
    let macOSMarkerRPM: Int?
    let isEnabled: Bool
    let onSetFan: (Int) -> Void
    let onSetAudible: (Int) -> Void

    private let bandY: CGFloat = 28
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fanX = x(forRPM: fanRPM, width: w)
            let audX = x(forRPM: audibleRPM, width: w)

            ZStack(alignment: .topLeading) {
                // Quiet (teal) / audible (amber) field, split at the audible line.
                HStack(spacing: 0) {
                    Rectangle().fill(Color.teal.opacity(0.50)).frame(width: max(0, audX))
                    Rectangle().fill(Color.orange.opacity(0.42))
                }
                .frame(width: w, height: trackHeight)
                .clipShape(Capsule())
                .position(x: w / 2, y: bandY)

                // Boost connector: macOS dot -> fan bar.
                if let macOSMarkerRPM {
                    let macX = x(forRPM: macOSMarkerRPM, width: w)
                    Path { p in
                        p.move(to: CGPoint(x: min(macX, fanX), y: bandY))
                        p.addLine(to: CGPoint(x: max(macX, fanX), y: bandY))
                    }
                    .stroke(Color.primary.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        .position(x: macX, y: bandY)
                    Text("macOS")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: macX, y: bandY + 14)
                }

                // Audible line — user calibration. Draggable.
                ZStack {
                    Rectangle().fill(Color.orange).frame(width: 2, height: 26)
                    Circle().fill(Color.orange).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        .offset(y: 17)
                    Text("audible")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize()
                        .offset(y: -22)
                }
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
                .position(x: audX, y: bandY)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("gauge"))
                        .onChanged { value in
                            guard isEnabled else { return }
                            onSetAudible(rpm(forX: value.location.x, width: w))
                        }
                )

                // Live fan speed + manual throttle. Draggable.
                ZStack {
                    Capsule().fill(Color.primary).frame(width: 9, height: 22)
                        .overlay(Capsule().stroke(.background, lineWidth: 3))
                    Text(DisplayFormatters.plainRPM(fanRPM))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .offset(y: -19)
                }
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
                .position(x: fanX, y: bandY)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("gauge"))
                        .onChanged { value in
                            guard isEnabled else { return }
                            onSetFan(rpm(forX: value.location.x, width: w))
                        }
                )
            }
            .coordinateSpace(name: "gauge")
        }
        .frame(height: 50)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan gauge")
        .accessibilityValue("Fan \(fanRPM) RPM, audible above \(audibleRPM) RPM")
    }

    private func x(forRPM rpm: Int, width: CGFloat) -> CGFloat {
        guard range.maximumRPM > range.minimumRPM else { return 0 }
        let frac = Double(rpm - range.minimumRPM) / Double(range.maximumRPM - range.minimumRPM)
        return CGFloat(min(max(frac, 0), 1)) * width
    }

    private func rpm(forX x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return range.minimumRPM }
        let frac = Double(min(max(x / width, 0), 1))
        let raw = Double(range.minimumRPM) + frac * Double(range.maximumRPM - range.minimumRPM)
        return range.clamped(Int((raw / 50).rounded() * 50))
    }
}
