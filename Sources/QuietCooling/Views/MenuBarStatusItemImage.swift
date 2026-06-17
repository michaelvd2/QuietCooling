import AppKit

enum MenuBarStatusItemImage {
    private static let imageSize = CGSize(width: 24, height: 22)
    private static let fanSize: CGFloat = 13
    private static let fanCenter = CGPoint(x: 12, y: 14.7)
    private static let bladeAngles: [CGFloat] = [135, 45, -45, -135]

    static func make(filledBladeCount: Int, temperatureText: String?) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.setLineJoin(.round)
            context.setLineCap(.round)

            let clampedCount = min(4, max(0, filledBladeCount))
            for (index, angle) in bladeAngles.enumerated() {
                drawBlade(
                    in: context,
                    angle: angle * .pi / 180,
                    filled: index < clampedCount
                )
            }
        }

        if let temperatureText {
            drawTemperature(temperatureText)
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawBlade(in context: CGContext, angle: CGFloat, filled: Bool) {
        let scale = fanSize / 18
        let bladeRect = CGRect(
            x: -2.55 * scale,
            y: 2.35 * scale,
            width: 5.1 * scale,
            height: 7.8 * scale
        )
        let bladePath = CGPath(
            roundedRect: bladeRect,
            cornerWidth: 2.55 * scale,
            cornerHeight: 2.55 * scale,
            transform: nil
        )

        context.saveGState()
        context.translateBy(x: fanCenter.x, y: fanCenter.y)
        context.rotate(by: angle)

        if filled {
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(bladePath)
            context.fillPath()
        }

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1.05)
        context.addPath(bladePath)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawTemperature(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.4, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        attributedText.draw(in: CGRect(x: 0, y: 0.6, width: imageSize.width, height: 8))
    }
}
