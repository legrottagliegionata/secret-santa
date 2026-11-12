// Disegna l'icona di Secret Santa (albero di Natale con stella e regalo) in PNG.
// Uso: swift disegna.swift <uscita.png> <lato> <margine-relativo>
//   margine 0.098 = griglia delle icone macOS, 0.02 = icona Windows quasi a tutto campo
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icona.png"
let S = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let marg = CGFloat(args.count > 3 ? Double(args[3])! : 0.098)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// coordinate con origine in alto a sinistra, unità = 1/1024 del lato
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: S / 1024, y: -S / 1024)

func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                         CGFloat(hex & 0xFF) / 255, a])!
}
func gradiente(_ c1: UInt32, _ c2: UInt32) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: [col(c1), col(c2)] as CFArray, locations: [0, 1])!
}

// sfondo: quadrato arrotondato rosso con gradiente
let m = 1024 * marg, lato = 1024 - 2 * m
let sfondo = CGPath(roundedRect: CGRect(x: m, y: m, width: lato, height: lato),
                    cornerWidth: lato * 0.225, cornerHeight: lato * 0.225, transform: nil)
ctx.saveGState()
ctx.addPath(sfondo); ctx.clip()
ctx.drawLinearGradient(gradiente(0xE0393E, 0x8C1520), start: CGPoint(x: 512, y: m),
                       end: CGPoint(x: 512, y: 1024 - m), options: [])
// alone chiaro dietro l'albero
ctx.drawRadialGradient(CGGradient(colorsSpace: cs, colors: [col(0xFFFFFF, 0.22), col(0xFFFFFF, 0)] as CFArray,
                                  locations: [0, 1])!,
                       startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 430), endRadius: 420, options: [])
// fiocchi di neve
let neve: [(CGFloat, CGFloat, CGFloat)] = [
    (190, 230, 10), (300, 170, 7), (760, 200, 9), (850, 300, 6), (170, 420, 6), (880, 470, 8),
    (230, 600, 8), (820, 640, 6), (140, 760, 7), (400, 140, 5), (640, 150, 6), (900, 820, 5),
]
for (x, y, r) in neve {
    ctx.setFillColor(col(0xFFFFFF, 0.75))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
}
// neve a terra
ctx.setFillColor(col(0xFFFFFF, 0.95))
ctx.addPath(CGPath(ellipseIn: CGRect(x: 60, y: 800, width: 904, height: 260), transform: nil))
ctx.fillPath()
ctx.restoreGState()

// tronco
ctx.setFillColor(col(0x6B3E1F))
ctx.fill(CGRect(x: 472, y: 735, width: 80, height: 95))

// albero: tre livelli
func livello(_ yTop: CGFloat, _ yBase: CGFloat, _ mezzaBase: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: yTop))
    p.addQuadCurve(to: CGPoint(x: 512 + mezzaBase, y: yBase), control: CGPoint(x: 512 + mezzaBase * 0.45, y: yBase - 60))
    p.addQuadCurve(to: CGPoint(x: 512 - mezzaBase, y: yBase), control: CGPoint(x: 512, y: yBase + 40))
    p.addQuadCurve(to: CGPoint(x: 512, y: yTop), control: CGPoint(x: 512 - mezzaBase * 0.45, y: yBase - 60))
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    ctx.drawLinearGradient(gradiente(0x3CC46E, 0x17693A), start: CGPoint(x: 400, y: yTop),
                           end: CGPoint(x: 600, y: yBase), options: [])
    ctx.restoreGState()
}
livello(470, 770, 270)
livello(340, 610, 215)
livello(230, 460, 160)

// palline
let palline: [(CGFloat, CGFloat, UInt32)] = [
    (455, 400, 0xFFD34D), (580, 430, 0xFFFFFF), (420, 560, 0xFFFFFF), (600, 575, 0xFFD34D),
    (360, 725, 0xFFD34D), (510, 690, 0xE0393E), (660, 730, 0xFFFFFF), (520, 505, 0xE0393E),
]
for (x, y, c) in palline {
    ctx.setFillColor(col(c))
    ctx.fillEllipse(in: CGRect(x: x - 19, y: y - 19, width: 38, height: 38))
    ctx.setFillColor(col(0xFFFFFF, 0.6))
    ctx.fillEllipse(in: CGRect(x: x - 10, y: y - 12, width: 9, height: 9))
}

// stella
func stella(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<10 {
        let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
        let rr = i % 2 == 0 ? r : r * 0.45
        let pt = CGPoint(x: cx + rr * cos(a), y: cy + rr * sin(a))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}
ctx.setShadow(offset: .zero, blur: 30, color: col(0xFFE27A, 0.9))
ctx.setFillColor(col(0xFFD34D))
ctx.addPath(stella(cx: 512, cy: 215, r: 78)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// regalo in basso a destra
let box = CGRect(x: 640, y: 720, width: 190, height: 150)
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: col(0x000000, 0.25))
ctx.setFillColor(col(0xFFD34D))
ctx.addPath(CGPath(roundedRect: box, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setFillColor(col(0xE8B92E))
ctx.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: 34))
ctx.setFillColor(col(0xC81E2C))
ctx.fill(CGRect(x: box.midX - 17, y: box.minY, width: 34, height: box.height))
// fiocco
for dx in [-1.0, 1.0] as [CGFloat] {
    let f = CGMutablePath()
    f.move(to: CGPoint(x: box.midX, y: box.minY))
    f.addCurve(to: CGPoint(x: box.midX + dx * 60, y: box.minY - 50), control1: CGPoint(x: box.midX + dx * 10, y: box.minY - 60),
               control2: CGPoint(x: box.midX + dx * 40, y: box.minY - 75))
    f.addCurve(to: CGPoint(x: box.midX, y: box.minY), control1: CGPoint(x: box.midX + dx * 80, y: box.minY - 25),
               control2: CGPoint(x: box.midX + dx * 30, y: box.minY - 5))
    ctx.addPath(f)
}
ctx.fillPath()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("scrittura PNG fallita") }
