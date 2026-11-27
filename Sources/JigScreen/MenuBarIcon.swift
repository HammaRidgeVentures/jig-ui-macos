import AppKit

/// The menu bar icon: a small agent's head. While agents run, three dots move inside it and a count sits beside it.
final class MenuBarIcon {
    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var phase = 0
    private var running = 0

    init(button: NSStatusBarButton?) {
        self.button = button
        button?.imagePosition = .imageLeading
        button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        show()
    }

    /// `running`: agents at work and not stalled. `waiting`: what waits on the owner. Nil: the data is old or missing.
    func update(running: Int?, waiting: Int?) {
        self.running = running ?? 0
        var words: [String] = []
        if let running { words.append(running == 1 ? "1 agent working" : "\(running) agents working") }
        if let waiting, waiting > 0 { words.append("\(waiting) waiting on you") }
        button?.toolTip = words.isEmpty ? "Jig Screen" : words.joined(separator: " · ")

        // No animation when the owner asked macOS to reduce motion: the count alone says agents run.
        let animate = self.running > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate, timer == nil {
            let t = Timer(timeInterval: 0.32, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase = (self.phase + 1) % 4
                self.show()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !animate {
            timer?.invalidate()
            timer = nil
            phase = 0
        }
        show()
    }

    private func show() {
        button?.image = MenuBarIcon.image(phase: running > 0 ? phase : nil)
        button?.title = running > 0 ? "\(running)" : ""
    }

    /// One frame, as a template image (the menu bar colors it).
    /// `phase` nil: the head at rest, with two eyes. 0 to 3: the three dots, one lit and lifted in turn, then a rest.
    static func image(phase: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            // The antenna.
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 9, y: 13.5))
            stem.line(to: NSPoint(x: 9, y: 15.2))
            stem.lineWidth = 1.4
            stem.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.8, y: 15, width: 2.4, height: 2.4)).fill()
            // The head, and an ear on each side.
            let head = NSBezierPath(roundedRect: NSRect(x: 3.2, y: 2.7, width: 11.6, height: 10.8), xRadius: 3.2, yRadius: 3.2)
            head.lineWidth = 1.5
            head.stroke()
            NSBezierPath(roundedRect: NSRect(x: 0.9, y: 6.4, width: 1.5, height: 3.6), xRadius: 0.7, yRadius: 0.7).fill()
            NSBezierPath(roundedRect: NSRect(x: 15.6, y: 6.4, width: 1.5, height: 3.6), xRadius: 0.7, yRadius: 0.7).fill()

            guard let phase else {
                NSBezierPath(ovalIn: NSRect(x: 5.5, y: 6.9, width: 2.6, height: 2.6)).fill()
                NSBezierPath(ovalIn: NSRect(x: 9.9, y: 6.9, width: 2.6, height: 2.6)).fill()
                return true
            }
            for dot in 0..<3 {
                let lit = dot == phase
                NSColor.black.withAlphaComponent(lit ? 1 : 0.38).setFill()
                let x = 5.0 + CGFloat(dot) * 2.9
                NSBezierPath(ovalIn: NSRect(x: x, y: lit ? 7.9 : 6.9, width: 2.2, height: 2.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jig Screen"
        return image
    }

    /// Every frame side by side, large, black on white. `--icon-frames out.png` writes it, to look at the drawing.
    static func writeFrames(to path: String) -> Bool {
        let frames: [Int?] = [nil, 0, 1, 2, 3]
        let scale: CGFloat = 8, cell: CGFloat = 18 * scale + 16
        let strip = NSImage(size: NSSize(width: cell * CGFloat(frames.count), height: cell), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, phase) in frames.enumerated() {
                image(phase: phase).draw(in: NSRect(x: CGFloat(index) * cell + 8, y: 8, width: 18 * scale, height: 18 * scale))
            }
            return true
        }
        guard let tiff = strip.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
