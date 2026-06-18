import AppKit
import XCTest
@testable import QuietCooling

final class MenuBarStatusItemImageTests: XCTestCase {
    func testRenderedStatusItemImageUsesFixedCompactSize() {
        let image = MenuBarStatusItemImage.make(filledBladeCount: 2, temperatureText: "87°")

        XCTAssertEqual(image.size.width, 24)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.nonTransparentPixelCount(), 80)
    }

    func testRenderedStatusItemImageReservesTemperatureSpaceWhenUnavailable() {
        let image = MenuBarStatusItemImage.make(filledBladeCount: 0, temperatureText: nil)

        XCTAssertEqual(image.size.width, 24)
        XCTAssertEqual(image.size.height, 22)
        XCTAssertTrue(image.isTemplate)
    }
}

private extension NSImage {
    func nonTransparentPixelCount() -> Int {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.1 {
                    count += 1
                }
            }
        }
        return count
    }
}
