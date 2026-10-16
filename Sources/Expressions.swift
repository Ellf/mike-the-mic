import Foundation

enum EyeState { case open, shut, closed, half, heart, cross }  // shut = blink line, closed = happy "^" wink
enum Brow { case none, normal, raised, angry, sad }
enum MouthExtra { case none, oh, tongue }

struct Expression {
    var left: EyeState = .open
    var right: EyeState = .open
    var leftBrow: Brow = .none
    var rightBrow: Brow = .none
    var dy = 0           // eyes up (-) / down (+)
    var crossDX = 0      // eyes pulled toward the nose
    var mouth: MouthExtra = .none
}

/// Random faces pulled every so often to keep people watching on their toes.
enum Quirk: CaseIterable {
    case winkLeft, winkRight, surprised, skeptical, angry, sad, hearts, dizzy, sleepy, crossEyed, browWiggle

    static let duration = 1.8

    func expression(at local: Double) -> Expression {
        var e = Expression()
        switch self {
        case .winkLeft: e.left = .closed; e.rightBrow = .raised
        case .winkRight: e.right = .closed; e.leftBrow = .raised
        case .surprised: e.leftBrow = .raised; e.rightBrow = .raised; e.dy = -1; e.mouth = .oh
        case .skeptical: e.leftBrow = .raised; e.rightBrow = .angry; e.right = .half
        case .angry: e.leftBrow = .angry; e.rightBrow = .angry; e.left = .half; e.right = .half
        case .sad: e.leftBrow = .sad; e.rightBrow = .sad; e.dy = 1
        case .hearts: e.left = .heart; e.right = .heart
        case .dizzy: e.left = .cross; e.right = .cross; e.mouth = .tongue
        case .sleepy: e.left = local < 0.9 ? .half : .shut; e.right = e.left
        case .crossEyed: e.crossDX = 2; e.mouth = .tongue
        case .browWiggle:
            let up = Int(local * 7) % 2 == 0
            e.leftBrow = up ? .raised : .normal
            e.rightBrow = e.leftBrow
        }
        return e
    }
}

@MainActor
enum Quirks {
    /// Set by the "Pull a Face" menu item to show a quirk right now.
    static var forced: (quirk: Quirk, start: Double)?

    /// `seed` gives each window its own random quirks; "Pull a Face" hits them all at once.
    static func expression(at now: Double, blink: Bool, seed: Int = 0) -> Expression {
        if let forced, now - forced.start < Quirk.duration {
            return forced.quirk.expression(at: now - forced.start)
        }
        let t = now + Double(seed) * 3.7
        let salt = UInt64(seed) * 10
        // Every 8s slot has a ~70% chance of a quirk at a random moment within it.
        let slotLength = 8.0
        let slot = Int(t / slotLength)
        if random(slot, salt + 1) < 0.7 {
            let start = Double(slot) * slotLength + 1 + random(slot, salt + 2) * 4
            if t >= start, t < start + Quirk.duration {
                let all = Quirk.allCases
                return all[Int(random(slot, salt + 3) * Double(all.count))].expression(at: t - start)
            }
        }
        var e = Expression()
        if blink { e.left = .shut; e.right = .shut }
        return e
    }

    static func pullAFace() {
        forced = (Quirk.allCases.randomElement()!, Date().timeIntervalSinceReferenceDate)
    }

    /// Deterministic 0..<1 noise so a slot's quirk stays the same every frame.
    private static func random(_ n: Int, _ salt: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        x ^= x >> 31; x &*= 0x94D049BB133111EB; x ^= x >> 29
        return Double(x % 1_000_000) / 1_000_000
    }
}
