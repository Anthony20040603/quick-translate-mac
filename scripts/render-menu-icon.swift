import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Read the supplied vector paths rather than maintaining a second copy of the artwork.
final class SVGPaths: NSObject, XMLParserDelegate {
    var paths: [String] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if name == "path", let data = attributes["d"] { paths.append(data) }
    }
}

enum IconError: Error { case invalidSVG(String) }

func readPaths(_ url: URL) throws -> [CGPath] {
    let delegate = SVGPaths()
    guard let parser = XMLParser(contentsOf: url) else { throw IconError.invalidSVG(url.lastPathComponent) }
    parser.delegate = delegate
    guard parser.parse(), !delegate.paths.isEmpty else { throw IconError.invalidSVG(url.lastPathComponent) }
    return try delegate.paths.map { source in
        let expression = try NSRegularExpression(pattern: #"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?|[A-Za-z]"#)
        let tokens = expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range, in: source)!])
        }
        let path = CGMutablePath()
        var index = 0
        var command = ""
        func number() throws -> CGFloat {
            guard index < tokens.count, let value = Double(tokens[index]) else {
                throw IconError.invalidSVG(url.lastPathComponent)
            }
            index += 1
            return CGFloat(value)
        }
        while index < tokens.count {
            if Double(tokens[index]) == nil { command = tokens[index]; index += 1 }
            let start = path.currentPoint
            let relative = command == command.lowercased()
            func point() throws -> CGPoint {
                let x = try number()
                let y = try number()
                return CGPoint(x: x + (relative ? start.x : 0), y: y + (relative ? start.y : 0))
            }
            switch command.uppercased() {
            case "M":
                path.move(to: try point())
                command = relative ? "l" : "L"
            case "L": path.addLine(to: try point())
            case "C":
                let first = try point(), second = try point(), end = try point()
                path.addCurve(to: end, control1: first, control2: second)
            case "Q":
                let control = try point(), end = try point()
                path.addQuadCurve(to: end, control: control)
            case "H":
                let x = try number()
                path.addLine(to: CGPoint(x: x + (relative ? start.x : 0), y: start.y))
            case "V":
                let y = try number()
                path.addLine(to: CGPoint(x: start.x, y: y + (relative ? start.y : 0)))
            case "Z": path.closeSubpath(); command = ""
            default: throw IconError.invalidSVG("Unsupported path command in \(url.lastPathComponent): \(command)")
            }
        }
        return path
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fatalError("Usage: render-menu-icon.swift Resources output.pdf [preview.png]")
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let back = try readPaths(root.appendingPathComponent("02-Aqua.svg"))
let front = try readPaths(root.appendingPathComponent("01-Cobalt.svg"))
let bounds = (back + front).reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
let canvas: CGFloat = 18
let scale = min(14.4 / bounds.width, 14.4 / bounds.height)
let separation: CGFloat = 0.65

func draw(_ context: CGContext) {
    context.saveGState()
    context.translateBy(x: canvas / 2, y: canvas / 2)
    context.scaleBy(x: scale, y: -scale)
    context.translateBy(x: -bounds.midX, y: -bounds.midY)
    // Solid shapes, with a transparent gap cut out of the rear shape along
    // the foreground contour. Keep the gap transparent on both menu themes.
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.setAlpha(1)
    context.saveGState()
    let outsideForegroundEdge = CGMutablePath()
    outsideForegroundEdge.addRect(bounds.insetBy(dx: -100, dy: -100))
    for path in front {
        let edge = path.copy(strokingWithWidth: 2 * separation / scale,
            lineCap: .round, lineJoin: .round, miterLimit: 10)
        outsideForegroundEdge.addPath(edge)
    }
    context.addPath(outsideForegroundEdge)
    context.clip(using: .evenOdd)
    for path in back { context.addPath(path); context.fillPath() }
    context.restoreGState()
    for path in front { context.addPath(path); context.fillPath() }
    context.restoreGState()
}

var media = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let destination = URL(fileURLWithPath: arguments[2])
guard let pdf = CGContext(destination as CFURL, mediaBox: &media, nil) else { fatalError("Could not create PDF") }
pdf.beginPDFPage(nil)
draw(pdf)
pdf.endPDFPage()
pdf.closePDF()

if arguments.count >= 4 {
    let pixels = 180
    let bitmap = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    bitmap.scaleBy(x: 10, y: 10)
    draw(bitmap)
    let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[3]) as CFURL,
        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, bitmap.makeImage()!, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Could not write preview") }
}
