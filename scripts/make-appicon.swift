#!/usr/bin/env swift
// Usage: swift scripts/make-appicon.swift <source.png> <AppIcon.appiconset dir> [--preview <path>]
import AppKit
import CoreGraphics

enum IconGrid {
    static let canvasSize = 1024
    static let tileSize: CGFloat = 824
    static let cornerRadius: CGFloat = 185.4
}

// Coefficients of the continuous-curvature corner used by UIKit/AppKit squircles, in units of the corner radius.
enum ContinuousCorner {
    static let extent: CGFloat = 1.52866483
    static let control1: CGFloat = 1.08849299
    static let control2: CGFloat = 0.86840006
    static let joinA = CGPoint(x: 0.66993427, y: 0.06549600)
    static let joinB = CGPoint(x: 0.63149399, y: 0.07491100)
    static let arcControl1 = CGPoint(x: 0.37282392, y: 0.16905899)
    static let arcControl2 = CGPoint(x: 0.16906001, y: 0.37282401)
}

// The source has a neutral gray drop shadow (down to ~160) below the tile, so "non-white" alone overshoots.
// Tile pixels are either dark or visibly tinted (the light top rim is lavender); the shadow is neither.
enum Detection {
    static let darkThreshold: UInt8 = 128
    static let chromaTolerance: UInt8 = 24
}

enum Preview {
    static let iconSize = 128
    static let padding = 32
    static let darkBackground = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let lightBackground = CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
}

struct IconSlot {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let slots: [IconSlot] = [16, 32, 128, 256, 512].flatMap { [IconSlot(points: $0, scale: 1), IconSlot(points: $0, scale: 2)] }

let bytesPerPixel = 4
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func makeContext(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * bytesPerPixel, space: colorSpace, bitmapInfo: bitmapInfo)
    else { fail("cannot create \(width)x\(height) bitmap context") }
    context.interpolationQuality = .high
    return context
}

func loadImage(_ path: String) -> CGImage {
    guard let rep = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()),
          let image = rep.cgImage
    else { fail("cannot load image at \(path)") }
    return image
}

/// Returns the tile bounds in top-down pixel coordinates (inclusive min, exclusive max).
func detectTileBounds(_ image: CGImage) -> CGRect {
    let width = image.width, height = image.height
    let context = makeContext(width: width, height: height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { fail("no bitmap data") }

    var minX = width, minY = height, maxX = -1, maxY = -1
    // Bitmap context memory is stored top row first.
    for y in 0..<height {
        let row = data + y * context.bytesPerRow
        for x in 0..<width {
            let pixel = row + x * bytesPerPixel
            let high = max(pixel[0], pixel[1], pixel[2]), low = min(pixel[0], pixel[1], pixel[2])
            if high < Detection.darkThreshold || high - low > Detection.chromaTolerance {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { fail("no tile found in source") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / ContinuousCorner.extent)
    let path = CGMutablePath()
    // Each corner is described by its vertex, the direction back along the incoming edge and the direction of the outgoing edge.
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]
    for (index, (vertex, back, forward)) in corners.enumerated() {
        func point(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: vertex.x + r * (a * back.dx + b * forward.dx), y: vertex.y + r * (a * back.dy + b * forward.dy))
        }
        let c = ContinuousCorner.self
        let start = point(c.extent, 0)
        if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
        path.addCurve(to: point(c.joinA.x, c.joinA.y), control1: point(c.control1, 0), control2: point(c.control2, 0))
        path.addLine(to: point(c.joinB.x, c.joinB.y))
        path.addCurve(to: point(c.joinB.y, c.joinB.x), control1: point(c.arcControl1.x, c.arcControl1.y),
                      control2: point(c.arcControl2.x, c.arcControl2.y))
        path.addLine(to: point(c.joinA.y, c.joinA.x))
        path.addCurve(to: point(0, c.extent), control1: point(0, c.control2), control2: point(0, c.control1))
    }
    path.closeSubpath()
    return path
}

func renderMaster(source: CGImage, tile: CGRect) -> CGImage {
    let size = IconGrid.canvasSize
    let canvas = CGFloat(size)
    let context = makeContext(width: size, height: size)
    let tileRect = CGRect(x: (canvas - IconGrid.tileSize) / 2, y: (canvas - IconGrid.tileSize) / 2,
                          width: IconGrid.tileSize, height: IconGrid.tileSize)
    context.addPath(continuousRoundedRect(tileRect, radius: IconGrid.cornerRadius))
    context.clip()

    // Uniform scale on the shorter side so the tile overfills the clip instead of leaving white gaps.
    let scale = IconGrid.tileSize / min(tile.width, tile.height)
    let sourceHeight = CGFloat(source.height)
    let tileCenterUp = CGPoint(x: tile.midX, y: sourceHeight - tile.midY)
    let drawRect = CGRect(x: tileRect.midX - tileCenterUp.x * scale, y: tileRect.midY - tileCenterUp.y * scale,
                          width: CGFloat(source.width) * scale, height: sourceHeight * scale)
    context.draw(source, in: drawRect)
    print(String(format: "scale %.4f, source drawn at %.1f,%.1f %.1fx%.1f", scale,
                 drawRect.minX, drawRect.minY, drawRect.width, drawRect.height))
    guard let image = context.makeImage() else { fail("cannot render master") }
    return image
}

func resized(_ image: CGImage, to pixels: Int) -> CGImage {
    if image.width == pixels { return image }
    let context = makeContext(width: pixels, height: pixels)
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    guard let result = context.makeImage() else { fail("cannot resize to \(pixels)") }
    return result
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fail("cannot encode \(url.path)")
    }
    do { try data.write(to: url) } catch { fail("cannot write \(url.path): \(error)") }
}

func writeContents(to directory: URL) {
    let images: [[String: String]] = slots.map {
        ["idiom": "mac", "size": "\($0.points)x\($0.points)", "scale": "\($0.scale)x", "filename": $0.filename]
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    do {
        let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: directory.appendingPathComponent("Contents.json"))
    } catch { fail("cannot write Contents.json: \(error)") }
}

func writePreview(master: CGImage, to url: URL) {
    let icon = resized(master, to: Preview.iconSize)
    let cell = Preview.iconSize + 2 * Preview.padding
    let context = makeContext(width: 2 * cell, height: cell)
    for (index, background) in [Preview.darkBackground, Preview.lightBackground].enumerated() {
        context.setFillColor(background)
        context.fill(CGRect(x: index * cell, y: 0, width: cell, height: cell))
        context.draw(icon, in: CGRect(x: index * cell + Preview.padding, y: Preview.padding,
                                      width: Preview.iconSize, height: Preview.iconSize))
    }
    guard let image = context.makeImage() else { fail("cannot render preview") }
    writePNG(image, to: url)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var previewPath: String?
if let flag = arguments.firstIndex(of: "--preview") {
    guard flag + 1 < arguments.count else { fail("--preview needs a path") }
    previewPath = arguments[flag + 1]
    arguments.removeSubrange(flag...(flag + 1))
}
guard arguments.count == 2 else {
    fail("usage: swift scripts/make-appicon.swift <source.png> <appiconset dir> [--preview <path>]")
}

let source = loadImage(arguments[0])
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let tile = detectTileBounds(source)
print("detected tile bounds (top-down px): x \(Int(tile.minX))..<\(Int(tile.maxX)), y \(Int(tile.minY))..<\(Int(tile.maxY)), size \(Int(tile.width))x\(Int(tile.height))")

let master = renderMaster(source: source, tile: tile)
for slot in slots {
    writePNG(resized(master, to: slot.pixels), to: outputDirectory.appendingPathComponent(slot.filename))
}
writeContents(to: outputDirectory)
if let previewPath { writePreview(master: master, to: URL(fileURLWithPath: previewPath)) }
print("wrote \(slots.count) icons to \(outputDirectory.path)")
