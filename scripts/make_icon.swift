// 生成 app 图标:蓝色 squircle 底 + 双显示器(左亮=开,右暗=关)。
// 用法:swift make_icon.swift <输出iconset目录>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawMonitor(_ ctx: CGContext, screen: CGRect, alpha: CGFloat) {
    let r = screen.width * 0.11
    ctx.setFillColor(NSColor(white: 1, alpha: alpha).cgColor)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.fillPath()
    // 支架:细颈 + 底座
    let stemW = screen.width * 0.12, stemH = screen.height * 0.16
    let stem = CGRect(x: screen.midX - stemW/2, y: screen.minY - stemH, width: stemW, height: stemH)
    ctx.fill(stem)
    let baseW = screen.width * 0.46, baseH = screen.height * 0.075
    let base = CGRect(x: screen.midX - baseW/2, y: stem.minY - baseH, width: baseW, height: baseH)
    ctx.addPath(CGPath(roundedRect: base, cornerWidth: baseH/2, cornerHeight: baseH/2, transform: nil)); ctx.fillPath()
}

func renderPNG(size: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let s = size
    let margin = s * 0.094
    let rect = CGRect(x: margin, y: margin, width: s - 2*margin, height: s - 2*margin)
    let radius = rect.width * 0.2237

    // squircle 渐变底
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    let colors = [NSColor(srgbRed: 0.29, green: 0.56, blue: 1.0, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.13, green: 0.31, blue: 0.85, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()

    // 双显示器:左亮(开)、右暗(关)
    let A = rect.width
    let mw = A * 0.34, mh = mw * 0.62, gap = A * 0.085
    let screenCY = rect.midY + A * 0.055
    let leftX = rect.midX - (mw + gap) / 2 - mw/2
    let rightX = rect.midX + (mw + gap) / 2 - mw/2
    drawMonitor(ctx, screen: CGRect(x: leftX,  y: screenCY - mh/2, width: mw, height: mh), alpha: 1.0)
    drawMonitor(ctx, screen: CGRect(x: rightX, y: screenCY - mh/2, width: mw, height: mh), alpha: 0.34)

    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

// 完整 iconset + 一张预览
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in sizes { renderPNG(size: px, to: "\(outDir)/\(name).png") }
renderPNG(size: 1024, to: "/tmp/icon_preview.png")
print("已生成 iconset 到 \(outDir) + 预览 /tmp/icon_preview.png")
