import AppKit

let folder = CommandLine.arguments[1]
let ios = CommandLine.arguments.contains("--ios")
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in ios ? [1024] : [16, 32, 128, 256, 512] {
    for scale in ios ? [1] : [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.29, alpha: 1).setFill()
        if ios { NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill() }
        else { NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill() }
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 185, y: 235, width: 654, height: 460), xRadius: 80, yRadius: 80).fill()
        let antenna = NSBezierPath()
        antenna.move(to: NSPoint(x: 620, y: 695)); antenna.line(to: NSPoint(x: 765, y: 840))
        antenna.lineWidth = 30; antenna.lineCapStyle = .round; NSColor.darkGray.setStroke(); antenna.stroke()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 250, y: 570, width: 525, height: 60), xRadius: 18, yRadius: 18).fill()
        NSColor(calibratedRed: 1, green: 0.55, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 552, y: 568, width: 14, height: 64)).fill()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 610, y: 330, width: 140, height: 140)).fill()
        for row in 0..<4 {
            for col in 0..<6 {
                NSBezierPath(ovalIn: NSRect(x: 265 + col * 42, y: 330 + row * 42, width: 15, height: 15)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let path = ios ? "\(folder)/AppIcon.png" : "\(folder)/icon_\(size)x\(size)\(suffix).png"
        if ios {
            let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<pixels {
                for x in 0..<pixels {
                    let source = rep.bitmapData! + y * rep.bytesPerRow + x * 4
                    let target = opaque.bitmapData! + y * opaque.bytesPerRow + x * 3
                    target[0] = source[0]; target[1] = source[1]; target[2] = source[2]
                }
            }
            try opaque.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        } else {
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
    }
}
