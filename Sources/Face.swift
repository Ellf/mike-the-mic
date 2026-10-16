import SwiftUI

struct FaceView: View {
    let face: FaceWindow

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            // Offset each window's clock so several faces blink and glance independently.
            let t = now + Double(face.id) * 2.3
            let mouth = Speaker.shared.mouth()
            let style = face.style
            let blink = t.truncatingRemainder(dividingBy: 4.3) < 0.13
            let expression = Quirks.expression(at: now, blink: blink, seed: face.id)
            Canvas { context, size in
                var pixels = Pixels()
                style.draw(&pixels, t: t, mouth: mouth, expression: expression)
                pixels.render(in: context, size: size)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// Where a face's two eyes sit and how to draw one open eye.
struct EyeSpec {
    var centers: [Int]
    var top: Int
    var width: Int
    var height: Int
    var color: RGB
    var glance: Int
    var drawOpen: (inout Pixels, _ cx: Int, _ top: Int) -> Void
}

enum FaceStyle: String, CaseIterable {
    case bot, kawaii, visor, pumpkin, trippy, creepy

    var title: String {
        switch self {
        case .bot: "Classic Bot"
        case .kawaii: "Kawaii"
        case .visor: "Visor"
        case .pumpkin: "Jack-o'-lantern"
        case .trippy: "Psychedelic"
        case .creepy: "Creepy"
        }
    }

    func draw(_ p: inout Pixels, t: Double, mouth: Mouth, expression e: Expression) {
        let glance = [0, -2, 0, 2, 0, 0][Int(t / 3.1) % 6]
        let open = Double(mouth.open), wide = Double(mouth.wide)
        let mouthCenter: (x: Int, y: Int)
        let faceColor: RGB
        // Creepy face: a quick red jolt every ~11 seconds.
        let glitch = t.truncatingRemainder(dividingBy: 11) < 0.22

        switch self {
        case .bot:
            let c = RGB(41, 230, 255)
            faceColor = c; mouthCenter = (32, 25)
            p.eyes(EyeSpec(centers: [18, 46], top: 7, width: 8, height: 8, color: c, glance: glance) { p, cx, top in
                p.rect(cx - 4, top, 8, 8, c)
            }, e)
            // 9 bars outlining the opening: round and tall for "oh", wide and flat for "ee"/"s".
            for i in 0..<9 {
                let x = Double(i - 4) / 4.5
                let profile = (1 - x * x).squareRoot() * (1 - wide) + (1 - 0.25 * abs(x)) * wide
                let h = max(1, Int((open * (9 - 4 * wide) * profile).rounded()))
                p.rect(14 + i * 4, 25 - h / 2, 3, h, c)
            }

        case .kawaii:
            let white = RGB(255, 255, 255), pink = RGB(255, 79, 138), lips = RGB(255, 122, 168)
            faceColor = lips; mouthCenter = (32, 24)
            p.eyes(EyeSpec(centers: [18, 46], top: 7, width: 10, height: 11, color: white, glance: glance) { p, cx, top in
                p.disc(cx, top + 5, 5, white)
                p.disc(cx, top + 5, 3, RGB(58, 107, 255))
                p.dot(cx + 1, top + 3, white)
            }, e)
            p.disc(10, 20, 2.5, pink)
            p.disc(54, 20, 2.5, pink)
            let rx = 2 + open * 1.5 + wide * 3
            let ry = 1 + open * 3 * (1 - 0.5 * wide)
            p.ellipse(32, 24, rx, ry, lips)
            if open > 0.3 { p.ellipse(32, 24, rx - 1, ry - 1, RGB(60, 0, 10)) }

        case .visor:
            let red = RGB(255, 48, 32)
            faceColor = red; mouthCenter = (32, 24)
            // Each "eye" is one half of the visor band; the scanner sweeps across both.
            let sx = 32 + sin(t * 2) * 22
            p.eyes(EyeSpec(centers: [19, 45], top: 8, width: 26, height: 7, color: red, glance: 0) { p, cx, top in
                p.rect(cx - 13, top, 26, 7, RGB(40, 0, 0))
                for i in -6...6 {
                    let x = Int((sx + Double(i)).rounded())
                    guard x >= cx - 13, x < cx + 13 else { continue }
                    let v = 1 - Double(abs(i)) / 7
                    p.rect(x, top + 1, 1, 5, RGB(255 * v, 40 * v * v, 20 * v))
                }
            }, e)
            // Waveform mouth: flat when silent, taller when loud, faster wiggle on hissy sounds.
            let speed = 0.35 + 0.4 * wide
            for x in 8..<56 {
                let envelope = sin(Double(x - 8) / 48 * .pi)
                let y = 24 + Int((sin(Double(x) * speed + t * 14) * open * 6 * envelope).rounded())
                p.dot(x, y, red)
            }

        case .pumpkin:
            let flicker = 0.75 + 0.25 * sin(t * 20) * sin(t * 7)
            let c = RGB(255, 140 * flicker, 0)
            faceColor = c; mouthCenter = (32, 22)
            p.eyes(EyeSpec(centers: [18, 46], top: 6, width: 12, height: 8, color: c, glance: glance / 2) { p, cx, top in
                for r in 0..<8 {
                    let hw = Int(Double(r) * 0.75)
                    p.rect(cx - hw, top + r, hw * 2 + 1, 1, c)
                }
            }, e)
            // Jagged grin: teeth stay put, the jaw drops as it talks.
            let left = 12 - Int(wide * 2), right = 52 + Int(wide * 2)
            let drop = Int((open * 5).rounded())
            for x in left..<right {
                let tooth = (x - 12) % 8 < 4
                let top = tooth ? 21 : 20
                let bottom = 22 + drop + (tooth ? 0 : 1)
                p.rect(x, top, 1, bottom - top, c)
            }

        case .trippy:
            let base = t * 0.25
            faceColor = .hue(base); mouthCenter = (32, 25)
            // Rainbow spirals: hue follows the angle and radius, and the whole thing spins.
            p.eyes(EyeSpec(centers: [18, 46], top: 5, width: 13, height: 13, color: .hue(base), glance: glance / 2) { p, cx, top in
                let cy = top + 6
                for y in -6...6 {
                    for x in -6...6 {
                        let r = Double(x * x + y * y).squareRoot()
                        guard r <= 6.3 else { continue }
                        let angle = atan2(Double(y), Double(x)) / (2 * .pi)
                        p.dot(cx + x, cy + y, .hue(angle + r * 0.14 - t * 0.6))
                    }
                }
            }, e)
            // Rainbow bars that ripple through the colours as it talks.
            for i in 0..<11 {
                let x = Double(i - 5) / 5.5
                let profile = (1 - x * x).squareRoot() * (1 - wide) + (1 - 0.25 * abs(x)) * wide
                let wobble = open > 0.05 ? 0 : sin(t * 3 + Double(i) * 0.7) * 0.6 + 0.6
                let h = max(1, Int((open * (9 - 4 * wide) * profile + wobble).rounded()))
                p.rect(11 + i * 4, 25 - h / 2, 3, h, .hue(base + Double(i) * 0.09))
            }

        case .creepy:
            let c = glitch ? RGB(255, 30, 30) : RGB(205, 225, 200)
            faceColor = c; mouthCenter = (32, 24)
            // Faint static in the dark.
            let frame = Int(t * 12)
            for i in 0..<7 {
                let n = Double(frame * 7 + i)
                p.dot(Int(fract(sin(n * 12.9898) * 43758.5) * 64), Int(fract(sin(n * 78.233) * 12345.6) * 32), RGB(45, 45, 45))
            }
            // Hollow sockets with tiny pupils that wander on their own.
            p.eyes(EyeSpec(centers: [19, 45], top: 6, width: 11, height: 9, color: c, glance: 0) { p, cx, top in
                p.ellipse(cx, top + 4, 5.5, 4.5, c)
                p.ellipse(cx, top + 4, 4.5, 3.5, RGB(30, 0, 0))
                let px = cx + Int((sin(t * 0.7) * 2.4).rounded())
                let py = top + 4 + Int((sin(t * 0.43 + 1) * 1.4).rounded())
                p.dot(px, py, glitch ? RGB(255, 255, 255) : RGB(255, 40, 40))
            }, e)
            // Long stitched grin that curls up at the ends and splits open to talk.
            for x in 10...54 {
                let d = Double(x - 32) / 22
                let y = 24 - Int((d * d * 5).rounded())
                let gap = Int((open * 6 * (1 - d * d)).rounded())
                if gap > 0 {
                    p.rect(x, y + 1, 1, gap, RGB(80, 0, 0))
                    if x % 3 == 0 { p.dot(x, y + 1, c) }      // teeth
                    p.dot(x, y + gap + 1, c)
                } else if x % 4 == 0, x > 12, x < 52 {
                    p.dot(x, y - 1, c); p.dot(x, y + 1, c)     // stitches
                }
                p.dot(x, y, c)
            }
        }

        if self == .creepy, glitch { p.shift(t.truncatingRemainder(dividingBy: 11) < 0.11 ? 3 : -2) }

        // Silly mouths only while it isn't talking.
        guard mouth.open < 0.05 else { return }
        switch e.mouth {
        case .none: break
        case .oh:
            p.clear(13, mouthCenter.y - 5, 39, 11)
            p.ring(mouthCenter.x, mouthCenter.y, 3, faceColor)
        case .tongue:
            let tongue = RGB(255, 70, 110)
            p.rect(mouthCenter.x - 2, mouthCenter.y + 1, 5, 3, tongue)
            p.rect(mouthCenter.x - 1, mouthCenter.y + 4, 3, 1, tongue)
        }
    }
}

extension Pixels {
    static let heart = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]

    /// Draws both eyes (and eyebrows) for the current expression.
    mutating func eyes(_ spec: EyeSpec, _ e: Expression) {
        for (index, baseX) in spec.centers.enumerated() {
            let isLeft = index == 0
            let state = isLeft ? e.left : e.right
            let brow = isLeft ? e.leftBrow : e.rightBrow
            let cx = baseX + spec.glance + (isLeft ? e.crossDX : -e.crossDX)
            let top = spec.top + e.dy
            let w = spec.width, h = spec.height
            let mid = top + h / 2

            switch state {
            case .open:
                spec.drawOpen(&self, cx, top)
            case .half:
                spec.drawOpen(&self, cx, top)
                clear(cx - w / 2 - 1, top - 1, w + 3, h / 2 + 1)
            case .shut:
                rect(cx - w / 2, mid, w, 1, spec.color)
            case .closed:
                for i in 0..<w { dot(cx - w / 2 + i, mid + 1 - min(i, w - 1 - i) / 2, spec.color) }
            case .heart:
                for (y, row) in Self.heart.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "X" { dot(cx - 3 + x, mid - 3 + y, RGB(255, 40, 90)) }
                }
            case .cross:
                let size = min(w, h, 7)
                for k in 0..<size {
                    dot(cx - size / 2 + k, mid - size / 2 + k, spec.color)
                    dot(cx - size / 2 + k, mid + size / 2 - k, spec.color)
                }
            }

            // Eyebrows only appear when an expression calls for them.
            guard brow != .none else { continue }
            let browY = top - 3 - (brow == .raised ? 2 : 0)
            let span = w + 2
            for i in 0..<span {
                let towardNose = Double(isLeft ? i : span - 1 - i) / Double(span - 1)
                var y = browY
                if brow == .angry { y += Int((towardNose * 2).rounded()) }
                if brow == .sad { y -= Int((towardNose * 2).rounded()) }
                dot(cx - w / 2 - 1 + i, y, spec.color)
            }
        }
    }

    mutating func ring(_ cx: Int, _ cy: Int, _ r: Double, _ c: RGB) {
        for y in -Int(r)...Int(r) {
            for x in -Int(r)...Int(r) {
                let d = Double(x * x + y * y).squareRoot()
                if d <= r + 0.3, d >= r - 1.2 { dot(cx + x, cy + y, c) }
            }
        }
    }
}

private func fract(_ v: Double) -> Double { v - v.rounded(.down) }

struct RGB: Hashable {
    let r: UInt8, g: UInt8, b: UInt8
    init(_ r: Double, _ g: Double, _ b: Double) {
        func clamp(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        self.r = clamp(r); self.g = clamp(g); self.b = clamp(b)
    }
    /// Fully saturated rainbow colour; `h` wraps every 1.0. Quantised so the LED paths stay batched.
    static func hue(_ h: Double) -> RGB {
        let h6 = ((h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 36).rounded() / 6
        func channel(_ n: Double) -> Double {
            let k = (n + h6).truncatingRemainder(dividingBy: 6)
            return 255 * (1 - max(0, min(k, 4 - k, 1)))
        }
        return RGB(channel(5), channel(3), channel(1))
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

    mutating func clear(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        for j in 0..<max(0, h) {
            for i in 0..<max(0, w) where x + i >= 0 && x + i < Self.cols && y + j >= 0 && y + j < Self.rows {
                lit[(y + j) * Self.cols + x + i] = nil
            }
        }
    }

    /// Slides every row sideways (wrapping), for glitch effects.
    mutating func shift(_ dx: Int) {
        let old = lit
        for y in 0..<Self.rows {
            for x in 0..<Self.cols {
                lit[y * Self.cols + x] = old[y * Self.cols + ((x - dx) % Self.cols + Self.cols) % Self.cols]
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
