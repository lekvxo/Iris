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
stackInfo["layers"] = ["Front", "Back"].map { ["filename": "\($0).solidimagestacklayer"] }
try json(stackInfo, at: stack.appendingPathComponent("Contents.json"))
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func canvas(opaque: Bool = false) -> CGContext {
    CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
              space: space, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}
var images: [String: CGImage] = [:]
for name in ["Back", "Front"] {
    let context = canvas(opaque: name == "Back")
    let sourceName = name == "Back" ? "Frosted-Background" : "Frosted-Aperture"
    let sourceURL = root.appendingPathComponent("Design/Icon/\(sourceName).png")
    guard let source = NSImage(contentsOf: sourceURL),
          let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Missing approved frosted icon source: \(sourceURL.path)")
    }
    if name == "Back" {
        context.setFillColor(color(1, 1, 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    context.interpolationQuality = .high
    // Leave room for visionOS's circular crop and gaze-driven foreground motion.
    let bounds = name == "Back" ? CGRect(x: 0, y: 0, width: 1024, height: 1024)
                                : CGRect(x: 72, y: 72, width: 880, height: 880)
    context.draw(sourceImage, in: bounds)
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
preview.addEllipse(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
preview.clip()
for name in ["Back", "Front"] { preview.draw(images[name]!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
try NSBitmapImageRep(cgImage: preview.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/iris-icon-preview.png"))
print("Prepared two 1024 × 1024 frosted icon layers and circular preview.")
