import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Iris/Assets.xcassets")
let stack = assets.appendingPathComponent("AppIcon.solidimagestack")
let info: [String: Any] = ["info": ["author": "com.max.iris", "version": 1]]
func json(_ object: [String: Any], at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
try json(info, at: assets.appendingPathComponent("Contents.json"))
var stackInfo = info
stackInfo["layers"] = ["Front", "Middle", "Back"].map { ["filename": "\($0).solidimagestacklayer"] }
try json(stackInfo, at: stack.appendingPathComponent("Contents.json"))
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func canvas() -> CGContext {
    CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
var images: [String: CGImage] = [:]
for name in ["Back", "Middle", "Front"] {
    let context = canvas()
    if name == "Back" {
        let gradient = CGGradient(colorsSpace: space, colors: [color(0.055, 0.09, 0.21), color(0.22, 0.16, 0.40)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 130, y: 950), end: CGPoint(x: 900, y: 80), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    } else if name == "Middle" {
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: 180, y: 512))
        eye.addCurve(to: CGPoint(x: 844, y: 512), control1: CGPoint(x: 370, y: 790), control2: CGPoint(x: 654, y: 790))
        eye.addCurve(to: CGPoint(x: 180, y: 512), control1: CGPoint(x: 654, y: 234), control2: CGPoint(x: 370, y: 234))
        eye.closeSubpath()
        context.addPath(eye)
        context.setFillColor(color(0.80, 0.95, 1, 0.13))
        context.setStrokeColor(color(0.80, 0.95, 1, 0.85))
        context.setLineWidth(23)
        context.drawPath(using: .fillStroke)
    } else {
        context.saveGState()
        context.addEllipse(in: CGRect(x: 338, y: 338, width: 348, height: 348))
        context.clip()
        let gradient = CGGradient(colorsSpace: space, colors: [color(0.39, 1, 0.81), color(0.07, 0.56, 0.76)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 686), end: CGPoint(x: 512, y: 338), options: [])
        context.setStrokeColor(color(0.76, 1, 0.96, 0.25))
        context.setLineWidth(3)
        for ray in 0..<48 {
            let angle = CGFloat(ray) * .pi / 24
            context.move(to: CGPoint(x: 512 + cos(angle) * 92, y: 512 + sin(angle) * 92))
            context.addLine(to: CGPoint(x: 512 + cos(angle) * 164, y: 512 + sin(angle) * 164))
            context.strokePath()
        }
        context.restoreGState()
        context.setFillColor(color(0.035, 0.10, 0.22))
        context.fillEllipse(in: CGRect(x: 426, y: 426, width: 172, height: 172))
        context.setFillColor(color(0.92, 1, 1, 0.96))
        context.fillEllipse(in: CGRect(x: 459, y: 548, width: 47, height: 47))
    }
    let image = context.makeImage()!
    images[name] = image
    let layer = stack.appendingPathComponent("\(name).solidimagestacklayer")
    try json(info, at: layer.appendingPathComponent("Contents.json"))
    var contentInfo = info
    contentInfo["images"] = [["filename": "\(name).png", "idiom": "vision", "scale": "2x"]]
    let content = layer.appendingPathComponent("Content.imageset")
    try json(contentInfo, at: content.appendingPathComponent("Contents.json"))
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: content.appendingPathComponent("\(name).png"))
}
let preview = canvas()
for name in ["Back", "Middle", "Front"] { preview.draw(images[name]!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
try NSBitmapImageRep(cgImage: preview.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/iris-icon-preview.png"))
print("Generated three 1024 × 1024 icon layers.")
