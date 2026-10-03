#!/usr/bin/env swift
//
// Renders the vector sources in Design/ into the asset catalog:
//   dotquit-icon.svg  -> AppIcon.appiconset   (10 sizes)
//   menubar-icon.svg  -> MenuBarIcon.imageset (1x / 2x, template)
//
//   swift Scripts/generate-icons.swift
//
// Every size is rasterised straight from the vector rather than downscaled
// from a single 1024 master — at 16 and 32 px that is the difference between
// crisp edges and mush.
//
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = repoRoot.appending(path: "DotQuit/Assets.xcassets")
let source = repoRoot.appending(path: "Design/dotquit-icon.svg")
let outputSet = catalog.appending(path: "AppIcon.appiconset")

/// idiom size, scale -> emitted pixel dimension
let variants: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("cannot load \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.createDirectory(at: outputSet, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

var entries: [[String: String]] = []

for variant in variants {
    let pixels = variant.size * variant.scale
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.size)x\(variant.size)\(suffix).png"

    guard let data = render(pixels: pixels) else {
        FileHandle.standardError.write("render failed at \(pixels)px\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: outputSet.appending(path: name))
    print(String(format: "  %-26s %4dx%-4d  %6d bytes", (name as NSString).utf8String!, pixels, pixels, data.count))

    entries.append([
        "idiom": "mac",
        "size": "\(variant.size)x\(variant.size)",
        "scale": "\(variant.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = [
    "images": entries,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(
    withJSONObject: contents,
    options: [.prettyPrinted, .sortedKeys]
)
try json.write(to: outputSet.appending(path: "Contents.json"))
print("\nwrote \(entries.count) images + Contents.json")


// MARK: - Menu bar icon
//
// Emitted as a template image: the PNGs carry only an alpha mask, and macOS
// tints them for light mode, dark mode and wallpaper-tinted menu bars.

let menuSource = repoRoot.appending(path: "Design/menubar-icon.svg")
let menuSet = catalog.appending(path: "MenuBarIcon.imageset")

guard let menuImage = NSImage(contentsOf: menuSource) else {
    FileHandle.standardError.write("cannot load \(menuSource.path)\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(at: menuSet, withIntermediateDirectories: true)

func renderMenu(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    menuImage.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

print("")
var menuEntries: [[String: String]] = []
for scale in [1, 2] {
    let pixels = 22 * scale
    let name = scale == 1 ? "menubar-icon.png" : "menubar-icon@\(scale)x.png"
    guard let data = renderMenu(pixels: pixels) else {
        FileHandle.standardError.write("menu bar render failed at \(pixels)px\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: menuSet.appending(path: name))
    print(String(format: "  %-26s %4dx%-4d  %6d bytes", (name as NSString).utf8String!, pixels, pixels, data.count))
    menuEntries.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
}

let menuContents: [String: Any] = [
    "images": menuEntries,
    "info": ["version": 1, "author": "xcode"],
    "properties": ["template-rendering-intent": "template"],
]
try JSONSerialization
    .data(withJSONObject: menuContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: menuSet.appending(path: "Contents.json"))
print("wrote MenuBarIcon.imageset (template rendering intent)")
