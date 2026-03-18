#!/usr/bin/swift

import AppKit
import Foundation

struct Paths {
    let root: URL
    let assetsDirectory: URL
    let iconsetDirectory: URL
    let appIconICNS: URL
    let volumeIconICNS: URL
    let readmeIcon: URL
    let dmgBackground: URL
    let docsImagesDirectory: URL

    init(root: URL) {
        self.root = root
        assetsDirectory = root.appendingPathComponent("Assets/Brand", isDirectory: true)
        iconsetDirectory = assetsDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        appIconICNS = assetsDirectory.appendingPathComponent("AppIcon.icns")
        volumeIconICNS = assetsDirectory.appendingPathComponent("VolumeIcon.icns")
        docsImagesDirectory = root.appendingPathComponent("docs/images", isDirectory: true)
        readmeIcon = docsImagesDirectory.appendingPathComponent("app-icon.png")
        dmgBackground = assetsDirectory.appendingPathComponent("dmg-background.png")
    }
}

enum BrandAssetError: Error {
    case invalidRoot
    case commandFailed(String)
}

let fileManager = FileManager.default

func appRoot() throws -> URL {
    let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    if fileManager.fileExists(atPath: currentDirectory.appendingPathComponent("Package.swift").path) {
        return currentDirectory
    }

    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let candidate = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    if fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
        return candidate
    }

    throw BrandAssetError.invalidRoot
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw BrandAssetError.commandFailed(output)
    }
    return output
}

func ensureDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func savePNG(_ image: NSImage, to destination: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw BrandAssetError.commandFailed("Could not encode PNG for \(destination.path)")
    }

    try pngData.write(to: destination, options: .atomic)
}

func withGraphicsContext<T>(size: CGSize, drawing: (NSRect) -> T) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    defer { image.unlockFocus() }
    let rect = NSRect(origin: .zero, size: size)
    _ = drawing(rect)
    return image
}

func roundedRectPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBackground(in rect: NSRect) {
    NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.12, alpha: 1).setFill()
    rect.fill()

    let baseRect = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03)
    let basePath = roundedRectPath(baseRect, radius: rect.width * 0.22)
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.17, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.12, alpha: 1),
    ])!
    backgroundGradient.draw(in: basePath, angle: -45)

    let outerStroke = roundedRectPath(baseRect.insetBy(dx: 2, dy: 2), radius: rect.width * 0.20)
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    outerStroke.lineWidth = max(2, rect.width * 0.008)
    outerStroke.stroke()

    let topGlow = NSBezierPath(ovalIn: NSRect(
        x: rect.width * 0.14,
        y: rect.height * 0.60,
        width: rect.width * 0.72,
        height: rect.height * 0.42
    ))
    NSGraphicsContext.saveGraphicsState()
    topGlow.addClip()
    let glowGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.23, green: 0.46, blue: 0.99, alpha: 0.35),
        NSColor(calibratedRed: 0.23, green: 0.46, blue: 0.99, alpha: 0.02),
    ])!
    glowGradient.draw(in: topGlow.bounds, relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    let bottomGlow = NSBezierPath(ovalIn: NSRect(
        x: rect.width * 0.18,
        y: rect.height * 0.08,
        width: rect.width * 0.64,
        height: rect.height * 0.32
    ))
    NSGraphicsContext.saveGraphicsState()
    bottomGlow.addClip()
    let bottomGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.86, blue: 0.52, alpha: 0.20),
        NSColor(calibratedRed: 0.08, green: 0.86, blue: 0.52, alpha: 0.01),
    ])!
    bottomGradient.draw(in: bottomGlow.bounds, relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()
}

func drawGlassCard(in rect: NSRect) {
    let cardRect = NSRect(
        x: rect.width * 0.17,
        y: rect.height * 0.14,
        width: rect.width * 0.66,
        height: rect.height * 0.72
    )
    let cardPath = roundedRectPath(cardRect, radius: rect.width * 0.14)
    let cardGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.24),
        NSColor(calibratedWhite: 1, alpha: 0.11),
    ])!
    cardGradient.draw(in: cardPath, angle: 90)

    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    cardPath.lineWidth = max(1.5, rect.width * 0.006)
    cardPath.stroke()

    let highlightRect = NSRect(
        x: cardRect.minX + cardRect.width * 0.07,
        y: cardRect.maxY - cardRect.height * 0.28,
        width: cardRect.width * 0.86,
        height: cardRect.height * 0.18
    )
    let highlightPath = roundedRectPath(highlightRect, radius: rect.width * 0.08)
    NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
    highlightPath.fill()
}

func drawBattery(in rect: NSRect) {
    let bodyRect = NSRect(
        x: rect.width * 0.27,
        y: rect.height * 0.31,
        width: rect.width * 0.46,
        height: rect.height * 0.34
    )
    let capRect = NSRect(
        x: rect.midX - rect.width * 0.07,
        y: bodyRect.maxY + rect.height * 0.03,
        width: rect.width * 0.14,
        height: rect.height * 0.05
    )

    let bodyPath = roundedRectPath(bodyRect, radius: rect.width * 0.085)
    let capPath = roundedRectPath(capRect, radius: rect.width * 0.028)

    let shellGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.90),
        NSColor(calibratedWhite: 0.93, alpha: 0.64),
    ])!
    shellGradient.draw(in: bodyPath, angle: 90)

    NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
    bodyPath.lineWidth = max(2.5, rect.width * 0.01)
    bodyPath.stroke()

    NSColor(calibratedWhite: 1, alpha: 0.84).setFill()
    capPath.fill()

    let innerRect = bodyRect.insetBy(dx: rect.width * 0.032, dy: rect.width * 0.032)
    let fillRect = NSRect(
        x: innerRect.minX,
        y: innerRect.minY,
        width: innerRect.width * 0.72,
        height: innerRect.height
    )
    let fillPath = roundedRectPath(fillRect, radius: rect.width * 0.052)
    let fillGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.49, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.11, green: 0.90, blue: 0.52, alpha: 1),
    ])!
    fillGradient.draw(in: fillPath, angle: 0)

    let shineRect = NSRect(
        x: fillRect.minX,
        y: fillRect.midY,
        width: fillRect.width,
        height: fillRect.height * 0.45
    )
    let shinePath = roundedRectPath(shineRect, radius: rect.width * 0.04)
    NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
    shinePath.fill()

    let chartRect = NSRect(
        x: innerRect.minX + innerRect.width * 0.04,
        y: innerRect.minY + innerRect.height * 0.24,
        width: innerRect.width * 0.92,
        height: innerRect.height * 0.48
    )
    let chartPath = NSBezierPath()
    chartPath.move(to: NSPoint(x: chartRect.minX, y: chartRect.midY))
    chartPath.curve(
        to: NSPoint(x: chartRect.minX + chartRect.width * 0.27, y: chartRect.midY + chartRect.height * 0.18),
        controlPoint1: NSPoint(x: chartRect.minX + chartRect.width * 0.08, y: chartRect.midY + chartRect.height * 0.02),
        controlPoint2: NSPoint(x: chartRect.minX + chartRect.width * 0.15, y: chartRect.midY + chartRect.height * 0.26)
    )
    chartPath.line(to: NSPoint(x: chartRect.minX + chartRect.width * 0.42, y: chartRect.midY - chartRect.height * 0.24))
    chartPath.curve(
        to: NSPoint(x: chartRect.maxX, y: chartRect.midY + chartRect.height * 0.08),
        controlPoint1: NSPoint(x: chartRect.minX + chartRect.width * 0.58, y: chartRect.midY - chartRect.height * 0.12),
        controlPoint2: NSPoint(x: chartRect.minX + chartRect.width * 0.83, y: chartRect.midY + chartRect.height * 0.14)
    )
    chartPath.lineCapStyle = .round
    chartPath.lineJoinStyle = .round
    chartPath.lineWidth = max(4, rect.width * 0.018)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.16, green: 0.57, blue: 1, alpha: 0.45)
    shadow.shadowBlurRadius = rect.width * 0.03
    shadow.shadowOffset = .zero
    shadow.set()
    NSColor(calibratedWhite: 1, alpha: 0.94).setStroke()
    chartPath.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawBrandIcon(size: CGSize) -> NSImage {
    withGraphicsContext(size: size) { rect in
        drawBackground(in: rect)
        drawGlassCard(in: rect)
        drawBattery(in: rect)
    }
}

func drawDMGBackground(size: CGSize) -> NSImage {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left

    return withGraphicsContext(size: size) { rect in
        let backgroundGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.10, alpha: 1),
        ])!
        backgroundGradient.draw(in: rect, angle: -30)

        let leftGlow = NSBezierPath(ovalIn: NSRect(x: -120, y: 240, width: 560, height: 420))
        NSGraphicsContext.saveGraphicsState()
        leftGlow.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.42, blue: 1, alpha: 0.45),
            NSColor(calibratedRed: 0.16, green: 0.42, blue: 1, alpha: 0.02),
        ])!.draw(in: leftGlow.bounds, relativeCenterPosition: .zero)
        NSGraphicsContext.restoreGraphicsState()

        let rightGlow = NSBezierPath(ovalIn: NSRect(x: 740, y: 80, width: 460, height: 360))
        NSGraphicsContext.saveGraphicsState()
        rightGlow.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.88, blue: 0.53, alpha: 0.26),
            NSColor(calibratedRed: 0.05, green: 0.88, blue: 0.53, alpha: 0.01),
        ])!.draw(in: rightGlow.bounds, relativeCenterPosition: .zero)
        NSGraphicsContext.restoreGraphicsState()

        let glassPanel = roundedRectPath(NSRect(x: 64, y: 72, width: 1072, height: 576), radius: 42)
        NSGradient(colors: [
            NSColor(calibratedWhite: 1, alpha: 0.10),
            NSColor(calibratedWhite: 1, alpha: 0.04),
        ])!.draw(in: glassPanel, angle: 90)
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        glassPanel.lineWidth = 2
        glassPanel.stroke()

        let icon = drawBrandIcon(size: CGSize(width: 280, height: 280))
        icon.draw(in: NSRect(x: 116, y: 246, width: 220, height: 220))

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72),
            .paragraphStyle: paragraph,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.92),
            .paragraphStyle: paragraph,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.62),
            .paragraphStyle: paragraph,
        ]

        "Maco Power Monitor".draw(in: NSRect(x: 368, y: 438, width: 420, height: 56), withAttributes: titleAttributes)
        "Real menu bar battery and power telemetry".draw(in: NSRect(x: 368, y: 402, width: 520, height: 28), withAttributes: subtitleAttributes)
        "真实状态栏电源与充电遥测".draw(in: NSRect(x: 368, y: 372, width: 520, height: 28), withAttributes: subtitleAttributes)

        "Drag the app into Applications".draw(in: NSRect(x: 770, y: 446, width: 320, height: 34), withAttributes: bodyAttributes)
        "拖动到 Applications 完成安装".draw(in: NSRect(x: 770, y: 416, width: 320, height: 28), withAttributes: secondaryAttributes)
        "Native menu bar utility • No fake data • Apple Silicon ready".draw(in: NSRect(x: 368, y: 256, width: 560, height: 32), withAttributes: bodyAttributes)
        "原生轻量 • 无虚拟数据 • 适配 Apple Silicon".draw(in: NSRect(x: 368, y: 224, width: 560, height: 26), withAttributes: secondaryAttributes)

        let arrowPath = NSBezierPath()
        arrowPath.move(to: NSPoint(x: 716, y: 328))
        arrowPath.curve(
            to: NSPoint(x: 828, y: 328),
            controlPoint1: NSPoint(x: 748, y: 320),
            controlPoint2: NSPoint(x: 796, y: 336)
        )
        arrowPath.line(to: NSPoint(x: 808, y: 350))
        arrowPath.move(to: NSPoint(x: 828, y: 328))
        arrowPath.line(to: NSPoint(x: 808, y: 306))
        arrowPath.lineCapStyle = .round
        arrowPath.lineJoinStyle = .round
        arrowPath.lineWidth = 9

        NSGraphicsContext.saveGraphicsState()
        let arrowShadow = NSShadow()
        arrowShadow.shadowColor = NSColor(calibratedRed: 0.14, green: 0.45, blue: 1, alpha: 0.45)
        arrowShadow.shadowBlurRadius = 16
        arrowShadow.shadowOffset = .zero
        arrowShadow.set()
        NSColor(calibratedRed: 0.35, green: 0.67, blue: 1, alpha: 0.95).setStroke()
        arrowPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func writeIconset(to destination: URL) throws {
    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }
    try ensureDirectory(destination)

    let sizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for (dimension, filename) in sizes {
        let sizedIcon = drawBrandIcon(size: CGSize(width: dimension, height: dimension))
        try savePNG(sizedIcon, to: destination.appendingPathComponent(filename))
    }

}

do {
    let root = try appRoot()
    let paths = Paths(root: root)

    try ensureDirectory(paths.assetsDirectory)
    try ensureDirectory(paths.docsImagesDirectory)

    try writeIconset(to: paths.iconsetDirectory)
    try run("/usr/bin/iconutil", ["-c", "icns", paths.iconsetDirectory.path, "-o", paths.appIconICNS.path])
    if fileManager.fileExists(atPath: paths.volumeIconICNS.path) {
        try fileManager.removeItem(at: paths.volumeIconICNS)
    }
    try fileManager.copyItem(at: paths.appIconICNS, to: paths.volumeIconICNS)
    try savePNG(drawBrandIcon(size: CGSize(width: 512, height: 512)), to: paths.readmeIcon)
    try savePNG(drawDMGBackground(size: CGSize(width: 1200, height: 720)), to: paths.dmgBackground)

    print("Generated brand assets:")
    print(paths.appIconICNS.path)
    print(paths.volumeIconICNS.path)
    print(paths.readmeIcon.path)
    print(paths.dmgBackground.path)
} catch {
    fputs("Brand asset generation failed: \(error)\n", stderr)
    exit(1)
}
