import AppKit

// Draw each icon size from vector paths to keep small Finder icons sharp.
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(calibratedRed: 0.49, green: 0.46, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.68, alpha: 1))!.draw(in: tile, angle: -65)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        tile.lineWidth = 4
        tile.stroke()
        let back = NSBezierPath(roundedRect: NSRect(x: 410, y: 256, width: 370, height: 380), xRadius: 84, yRadius: 84)
        NSColor(calibratedRed: 0.73, green: 0.92, blue: 0.98, alpha: 1).setFill()
        back.fill()
        let front = NSBezierPath(roundedRect: NSRect(x: 232, y: 418, width: 394, height: 350), xRadius: 84, yRadius: 84)
        NSColor.white.setFill()
        front.fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 294, y: 460))
        tail.line(to: NSPoint(x: 294, y: 352))
        tail.line(to: NSPoint(x: 415, y: 460))
        tail.close()
        tail.fill()
        ("A" as NSString).draw(in: NSRect(x: 310, y: 446, width: 270, height: 285), withAttributes: [.font: NSFont.systemFont(ofSize: 236, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.78, alpha: 1)])
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 506, y: 353))
        arrow.line(to: NSPoint(x: 688, y: 353))
        arrow.move(to: NSPoint(x: 640, y: 400))
        arrow.line(to: NSPoint(x: 688, y: 353))
        arrow.line(to: NSPoint(x: 640, y: 306))
        arrow.lineWidth = 26
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.51, alpha: 1).setStroke()
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
