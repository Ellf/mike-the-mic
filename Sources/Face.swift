import SwiftUI

struct FaceView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let mouth = Speaker.shared.mouth()
            let style = Prefs.faceStyle
            Canvas { context, size in
                var pixels = Pixels()
                style.draw(&pixels, t: t, mouth: mouth)
                pixels.render(in: context, size: size)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

enum FaceStyle: String, CaseIterable {
    case bot, kawaii, visor, pumpkin

    var title: String {
        switch self {
        case .bot: "Classic Bot"
        case .kawaii: "Kawaii"
        case .visor: "Visor"
        case .pumpkin: "Jack-o'-lantern"
        }
    }

    func draw(_ p: inout Pixels, t: Double, mouth: Mouth) {
        // Shared timing: blink every ~4.3s, glance left/right now and then.
        let blink = t.truncatingRemainder(dividingBy: 4.3) < 0.13
        let glance = [0, -2, 0, 2, 0, 0][Int(t / 3.1) % 6]
        let open = Double(mouth.open), wide = Double(mouth.wide)

        switch self {
        case .bot:
            let c = RGB(41, 230, 255)
            let eyeHeight = blink ? 1 : 8
            for x in [14, 42] { p.rect(x + glance, 7 + (8 - eyeHeight) / 2, 8, eyeHeight, c) }
            // 9 bars outlining the opening: round and tall for "oh", wide and flat for "ee"/"s".
            for i in 0..<9 {
                let x = Double(i - 4) / 4.5
                let profile = (1 - x * x).squareRoot() * (1 - wide) + (1 - 0.25 * abs(x)) * wide
                let h = max(1, Int((open * (9 - 4 * wide) * profile).rounded()))
                p.rect(14 + i * 4, 25 - h / 2, 3, h, c)
            }

        case .kawaii:
            let white = RGB(255, 255, 255), pink = RGB(255, 79, 138)
            for x in [18 + glance, 46 + glance] {
                if blink {
                    p.rect(x - 5, 12, 10, 1, white)
                } else {
                    p.disc(x, 12, 5, white)
                    p.disc(x, 12, 3, RGB(58, 107, 255))
                    p.dot(x + 1, 10, white)
                }
            }
            p.disc(10, 20, 2.5, pink)
            p.disc(54, 20, 2.5, pink)
            let rx = 2 + open * 1.5 + wide * 3
            let ry = 1 + open * 3 * (1 - 0.5 * wide)
            p.ellipse(32, 24, rx, ry, RGB(255, 122, 168))
            if open > 0.3 { p.ellipse(32, 24, rx - 1, ry - 1, RGB(60, 0, 10)) }

        case .visor:
            p.rect(6, 8, 52, 7, RGB(40, 0, 0))
            let sx = 32 + sin(t * 2) * 22
            for i in -6...6 {
                let v = 1 - Double(abs(i)) / 7
                p.rect(Int((sx + Double(i)).rounded()), 9, 1, 5, RGB(255 * v, 40 * v * v, 20 * v))
            }
            // Waveform mouth: flat when silent, taller when loud, faster wiggle on hissy sounds.
            let speed = 0.35 + 0.4 * wide
            for x in 8..<56 {
                let envelope = sin(Double(x - 8) / 48 * .pi)
                let y = 24 + Int((sin(Double(x) * speed + t * 14) * open * 6 * envelope).rounded())
                p.dot(x, y, RGB(255, 48, 32))
            }

        case .pumpkin:
            let flicker = 0.75 + 0.25 * sin(t * 20) * sin(t * 7)
            let c = RGB(255, 140 * flicker, 0)
            for x in [17 + glance / 2, 45 + glance / 2] {
                if blink { p.rect(x - 5, 12, 10, 1, c); continue }
                for r in 0..<8 { p.rect(Int(Double(x) - Double(r) / 1.3), 6 + r, 1 + Int(Double(r) * 1.5), 1, c) }
            }
            // Jagged grin: teeth stay put, the jaw drops as it talks.
            let left = 12 - Int(wide * 2), right = 52 + Int(wide * 2)
            let drop = Int((open * 5).rounded())
            for x in left..<right {
                let tooth = (x - 12) % 8 < 4
                let top = tooth ? 21 : 20
                let bottom = 22 + drop + (tooth ? 0 : 1)
                p.rect(x, top, 1, bottom - top, c)
            }
        }
    }
}

struct RGB: Hashable {
    let r: UInt8, g: UInt8, b: UInt8
    init(_ r: Double, _ g: Double, _ b: Double) {
        func clamp(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        self.r = clamp(r); self.g = clamp(g); self.b = clamp(b)
    }
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// A 64x32 LED grid.
struct Pixels {
    static let cols = 64
    static let rows = 32
    private var lit = [RGB?](repeating: nil, count: cols * rows)

    mutating func dot(_ x: Int, _ y: Int, _ c: RGB) {
        if x >= 0, x < Self.cols, y >= 0, y < Self.rows { lit[y * Self.cols + x] = c }
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB) {
        guard w > 0, h > 0 else { return }
        for j in 0..<h { for i in 0..<w { dot(x + i, y + j, c) } }
    }

    mutating func ellipse(_ cx: Int, _ cy: Int, _ rx: Double, _ ry: Double, _ c: RGB) {
        guard rx > 0, ry > 0 else { return }
        for y in -Int(ry)...Int(ry) {
            for x in -Int(rx)...Int(rx) where Double(x * x) / (rx * rx) + Double(y * y) / (ry * ry) <= 1 {
                dot(cx + x, cy + y, c)
            }
        }
    }

    mutating func disc(_ cx: Int, _ cy: Int, _ r: Double, _ c: RGB) { ellipse(cx, cy, r, r, c) }

    /// Draws round glowing LEDs, letterboxed to keep the 2:1 grid.
    func render(in context: GraphicsContext, size: CGSize) {
        let pitch = min(size.width / CGFloat(Self.cols), size.height / CGFloat(Self.rows))
        let ox = (size.width - pitch * CGFloat(Self.cols)) / 2
        let oy = (size.height - pitch * CGFloat(Self.rows)) / 2
        let r = pitch * 0.38
        var off = Path()
        var on: [RGB: Path] = [:]
        for y in 0..<Self.rows {
            for x in 0..<Self.cols {
                let dot = CGRect(x: ox + (CGFloat(x) + 0.5) * pitch - r,
                                 y: oy + (CGFloat(y) + 0.5) * pitch - r,
                                 width: r * 2, height: r * 2)
                if let c = lit[y * Self.cols + x] { on[c, default: Path()].addEllipse(in: dot) } else { off.addEllipse(in: dot) }
            }
        }
        context.fill(off, with: .color(Color(white: 0.08)))
        var glow = context
        glow.addFilter(.blur(radius: pitch * 0.6))
        for (c, path) in on { glow.fill(path, with: .color(c.color.opacity(0.7))) }
        for (c, path) in on { context.fill(path, with: .color(c.color)) }
    }
}
