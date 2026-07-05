// App 图标生成器：深色圆角方块 + 白色波形，其中一段绿色（打标绿段的隐喻），
// 右上角红色录音点。运行方式见 Assets/README（swiftc 编译后执行，输出 icon_1024.png）。
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// 圆角底（macOS 图标标准内缩与圆角比例）
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
let radius: CGFloat = rect.width * 0.2237
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()

// 深色渐变背景
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: 1024 - inset),
    end: CGPoint(x: 512, y: inset),
    options: []
)

// 波形：15 根圆角竖条，第 9–12 根为绿色（打标绿段）
let heights: [CGFloat] = [0.28, 0.45, 0.62, 0.40, 0.75, 0.55, 0.88, 0.68,
                          0.95, 0.80, 0.60, 0.72, 0.50, 0.38, 0.26]
let greenRange = 8...11
let barWidth: CGFloat = 34
let gap: CGFloat = 18
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
let startX = (1024 - totalWidth) / 2
let centerY: CGFloat = 512
let maxBarHeight: CGFloat = 400

let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95)
let green = CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1) // systemGreen

for (i, h) in heights.enumerated() {
    let barHeight = maxBarHeight * h
    let x = startX + CGFloat(i) * (barWidth + gap)
    let barRect = CGRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
    let barPath = CGPath(
        roundedRect: barRect,
        cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
        transform: nil
    )
    ctx.addPath(barPath)
    ctx.setFillColor(greenRange.contains(i) ? green : white)
    ctx.fillPath()
}

// 绿段下方的横条（时间轴上的绿标）
let greenStartX = startX + CGFloat(greenRange.lowerBound) * (barWidth + gap)
let greenEndX = startX + CGFloat(greenRange.upperBound) * (barWidth + gap) + barWidth
let underline = CGRect(
    x: greenStartX, y: centerY - maxBarHeight / 2 - 70,
    width: greenEndX - greenStartX, height: 26
)
ctx.addPath(CGPath(roundedRect: underline, cornerWidth: 13, cornerHeight: 13, transform: nil))
ctx.setFillColor(green)
ctx.fillPath()

// 右上角录音红点
ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 1)) // systemRed
let dotRadius: CGFloat = 46
ctx.fillEllipse(in: CGRect(
    x: rect.maxX - 150 - dotRadius, y: rect.maxY - 150 - dotRadius,
    width: dotRadius * 2, height: dotRadius * 2
))

// 输出 PNG
let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: "icon_1024.png")
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote icon_1024.png")
