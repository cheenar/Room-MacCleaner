import AppKit
import Foundation

let resources = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = resources.appendingPathComponent("Room.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  let scale = CGFloat(size) / 1024
  let inset = CGFloat(size) * 0.075
  let rect = NSRect(
    x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
  let shape = NSBezierPath(roundedRect: rect, xRadius: 195 * scale, yRadius: 195 * scale)
  NSGradient(
    starting: NSColor(red: 1, green: 0.72, blue: 0.36, alpha: 1),
    ending: NSColor(red: 0.97, green: 0.30, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -70)
  let center = NSPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
  let ring = NSBezierPath()
  ring.appendArc(withCenter: center, radius: 224 * scale, startAngle: 60, endAngle: 355)
  ring.lineWidth = 87 * scale
  ring.lineCapStyle = .round
  NSColor.white.setStroke()
  ring.stroke()
  NSColor.white.withAlphaComponent(0.40).setFill()
  NSBezierPath(
    ovalIn: NSRect(x: 636 * scale, y: 617 * scale, width: 90 * scale, height: 90 * scale)
  ).fill()
  image.unlockFocus()
  let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
  let data = bitmap.representation(using: .png, properties: [:])!
  let names: [String]
  switch size {
  case 16: names = ["icon_16x16.png"]
  case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
  case 64: names = ["icon_32x32@2x.png"]
  case 128: names = ["icon_128x128.png"]
  case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
  case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
  default: names = ["icon_512x512@2x.png"]
  }
  for name in names { try data.write(to: iconset.appendingPathComponent(name)) }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = [
  "-c", "icns", iconset.path, "-o", resources.appendingPathComponent("Room.icns").path,
]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
