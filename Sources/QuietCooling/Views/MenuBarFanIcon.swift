import AppKit
import SwiftUI

struct MenuBarFanIcon: View {
    var filledBladeCount: Int

    var body: some View {
        Image(nsImage: MenuBarFanTemplateImage.make(filledBladeCount: clampedFilledBladeCount))
            .interpolation(.high)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
        .frame(width: 18, height: 18)
        .accessibilityLabel("Fan strength")
        .accessibilityValue("\(clampedFilledBladeCount) of 4")
    }

    private var clampedFilledBladeCount: Int {
        min(4, max(0, filledBladeCount))
    }
}

private enum MenuBarFanTemplateImage {
    private static let size = CGSize(width: 18, height: 18)
    private static let bladeAngles: [CGFloat] = [135, 45, -45, -135]

    static func make(filledBladeCount: Int) -> NSImage {
        let clampedCount = min(4, max(0, filledBladeCount))
        let image = NSImage(size: size)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setLineJoin(.round)
            context.setLineCap(.round)

            for (index, angle) in bladeAngles.enumerated() {
                drawBlade(
                    in: context,
                    angle: angle * .pi / 180,
                    filled: index < clampedCount
                )
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawBlade(in context: CGContext, angle: CGFloat, filled: Bool) {
        let bladeRect = CGRect(x: -2.55, y: 2.35, width: 5.1, height: 7.8)
        let bladePath = CGPath(
            roundedRect: bladeRect,
            cornerWidth: 2.55,
            cornerHeight: 2.55,
            transform: nil
        )

        context.saveGState()
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.rotate(by: angle)

        if filled {
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(bladePath)
            context.fillPath()
        }

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1.25)
        context.addPath(bladePath)
        context.strokePath()
        context.restoreGState()
    }
}
