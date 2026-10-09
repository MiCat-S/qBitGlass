import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Claude 橘漸層背景
let top = NSColor(red: 0xE8/255, green: 0x8E/255, blue: 0x6E/255, alpha: 1)
let bottom = NSColor(red: 0xC2/255, green: 0x5E/255, blue: 0x40/255, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: -90)

// 柔和高光
NSColor(white: 1, alpha: 0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: -200, y: 520, width: 1100, height: 700)).fill()

// 襯線字 qB
let base = NSFont.systemFont(ofSize: 520, weight: .semibold)
let font = NSFont(descriptor: base.fontDescriptor.withDesign(.serif)!, size: 520)!
let para = NSMutableParagraphStyle(); para.alignment = .center
let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.18); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(red: 0xFA/255, green: 0xF9/255, blue: 0xF5/255, alpha: 1), .paragraphStyle: para, .shadow: shadow]
let str = NSAttributedString(string: "qB", attributes: attrs)
let h = str.size().height
str.draw(in: NSRect(x: 0, y: (CGFloat(size) - h) / 2 + 85, width: CGFloat(size), height: h))

// 下載箭頭
let arrow = NSBezierPath()
arrow.lineWidth = 34; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 512, y: 215)); arrow.line(to: NSPoint(x: 512, y: 100))
arrow.move(to: NSPoint(x: 455, y: 157)); arrow.line(to: NSPoint(x: 512, y: 100)); arrow.line(to: NSPoint(x: 569, y: 157))
NSColor(white: 1, alpha: 0.9).setStroke(); arrow.stroke()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments[1]
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
