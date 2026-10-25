import AppKit
import CoreGraphics
import Foundation

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let nsImage = NSImage(contentsOf: input) else {
    fputs("Could not load image\n", stderr)
    exit(1)
}

var proposed = CGRect(origin: .zero, size: nsImage.size)
guard let source = nsImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    fputs("Could not read pixels\n", stderr)
    exit(1)
}

let width = source.width
let height = source.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let bitmap = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    exit(1)
}

bitmap.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let data = bitmap.data else { exit(1) }
let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

func isArtwork(_ offset: Int) -> Bool {
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    return red < 200 || green < 200 || blue < 200
}

var minX = width
var minY = height
var maxX = 0
var maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let offset = (y * width + x) * 4
        if isArtwork(offset) {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

// CGContext rows start at the bottom. CGImage crops start at the top.
let cropRect = CGRect(
    x: minX,
    y: height - maxY - 1,
    width: maxX - minX + 1,
    height: maxY - minY + 1
)
guard let cropped = source.cropping(to: cropRect) else {
    fputs("Could not crop artwork\n", stderr)
    exit(1)
}

let canvasSize = 1024
guard let canvas = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: canvasSize * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    exit(1)
}

canvas.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
canvas.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

let margin = 0.12
let available = CGFloat(canvasSize) * (1 - margin * 2)
let scale = min(available / CGFloat(cropped.width), available / CGFloat(cropped.height))
let drawWidth = CGFloat(cropped.width) * scale
let drawHeight = CGFloat(cropped.height) * scale
let originX = (CGFloat(canvasSize) - drawWidth) / 2
let originY = (CGFloat(canvasSize) - drawHeight) / 2
canvas.interpolationQuality = .high
canvas.draw(cropped, in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))

guard let rendered = canvas.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: rendered)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
fputs(
    "wrote \(output.path) artwork=\(Int(cropRect.width))x\(Int(cropRect.height)) origin=\(Int(originX)),\(Int(originY))\n",
    stderr
)
