// Renders the app icon (a screen with the notch playing music) to a 1024 px PNG.
// Usage: swift scripts/make-icon.swift <out.png>   (scripts/make-icon.sh builds the .icns)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Rect in top-left coordinates, which is easier to reason about for a notch.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: size - y - h, width: w, height: h)
}

// Body: macOS icon grid, 824 pt squircle centred with a soft drop shadow.
let body = rect(100, 100, 824, 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = .black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
color(0x0E1220).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x2A2F45), ending: color(0x0B0D16))!.draw(in: bodyPath, angle: -90)

// Screen: a wallpaper-like gradient inset in the body.
let screen = rect(150, 150, 724, 724)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 140, yRadius: 140)
NSGradient(colors: [color(0x5B5BF7), color(0x8A4FE0), color(0xE0569B)])!.draw(in: screenPath, angle: -60)
// Subtle top glare.
NSGradient(starting: .white.withAlphaComponent(0.18), ending: .white.withAlphaComponent(0))!
    .draw(in: screenPath, angle: -90)

// Notch: hangs from the top edge of the screen, rounded at the bottom.
NSGraphicsContext.saveGraphicsState()
screenPath.addClip()
let notch = rect(232, 150, 560, 210)
let r: CGFloat = 70
let notchPath = NSBezierPath()
notchPath.move(to: NSPoint(x: notch.minX, y: notch.maxY + 40))
notchPath.line(to: NSPoint(x: notch.minX, y: notch.minY + r))
notchPath.appendArc(withCenter: NSPoint(x: notch.minX + r, y: notch.minY + r), radius: r, startAngle: 180, endAngle: 270)
notchPath.line(to: NSPoint(x: notch.maxX - r, y: notch.minY))
notchPath.appendArc(withCenter: NSPoint(x: notch.maxX - r, y: notch.minY + r), radius: r, startAngle: 270, endAngle: 360)
notchPath.line(to: NSPoint(x: notch.maxX, y: notch.maxY + 40))
notchPath.close()
NSGraphicsContext.saveGraphicsState()
let notchShadow = NSShadow()
notchShadow.shadowColor = .black.withAlphaComponent(0.45)
notchShadow.shadowBlurRadius = 30
notchShadow.shadowOffset = NSSize(width: 0, height: -10)
notchShadow.set()
NSColor.black.setFill()
notchPath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

// Live activity inside the notch: artwork tile on the left, equalizer on the right.
let art = NSBezierPath(roundedRect: rect(282, 222, 110, 110), xRadius: 26, yRadius: 26)
NSGradient(colors: [color(0xFFB34D), color(0xFF5E7E), color(0xA24DFF)])!.draw(in: art, angle: -45)

let bars: [CGFloat] = [0.55, 1.0, 0.7, 0.4]
let barWidth: CGFloat = 26, gap: CGFloat = 18, maxHeight: CGFloat = 120, centerY: CGFloat = 277
for (i, h) in bars.enumerated() {
    let height = maxHeight * h
    let x = 742 - CGFloat(bars.count - i) * (barWidth + gap) + gap
    let bar = NSBezierPath(roundedRect: rect(x, centerY - height / 2, barWidth, height),
                           xRadius: barWidth / 2, yRadius: barWidth / 2)
    NSGradient(starting: color(0x6FE3FF), ending: color(0x3D7BFF))!.draw(in: bar, angle: -90)
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
