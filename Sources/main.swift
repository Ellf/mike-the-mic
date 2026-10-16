import AppKit
import SwiftUI

/// Hosting view that lets you drag the window by clicking anywhere on the face.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// One face window. Each has its own style and remembers its own position (and monitor).
@MainActor
final class FaceWindow: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let id: Int
    let window: NSWindow
    var onClose: ((FaceWindow) -> Void)?
    var style: FaceStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey(id)) }
    }

    /// Window 0 keeps the original keys so existing settings carry over.
    private static func styleKey(_ id: Int) -> String { id == 0 ? "faceStyle" : "faceStyle.\(id)" }
    private static func frameName(_ id: Int) -> String { id == 0 ? "TalkingFaceWindow" : "TalkingFaceWindow.\(id)" }

    init(id: Int, menu: (FaceWindow) -> NSMenu) {
        self.id = id
        let all = FaceStyle.allCases
        style = FaceStyle(rawValue: UserDefaults.standard.string(forKey: Self.styleKey(id)) ?? "") ?? all[id % all.count]
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "Talking Face"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.contentAspectRatio = NSSize(width: 2, height: 1)
        window.minSize = NSSize(width: 160, height: 80)
        window.delegate = self
        let face = DraggableHostingView(rootView: FaceView(face: self))
        face.menu = menu(self)
        window.contentView = face
        window.setFrameAutosaveName(Self.frameName(id))
        if !window.setFrameUsingName(Self.frameName(id)) {
            window.center()
            window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat(id * 40), y: window.frame.minY - CGFloat(id * 40)))
        }
        window.level = Prefs.stayOnTop ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) { onClose?(self) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(pickStyle(_:)) {
            item.state = item.representedObject as? String == style.rawValue ? .on : .off
        }
        return true
    }

    @objc func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = FaceStyle(rawValue: raw) { self.style = style }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var faces: [FaceWindow] = []
    private var server: HookServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Speaker.clearTempFiles()

        let saved = (UserDefaults.standard.array(forKey: "faceWindows") ?? []).compactMap { Int("\($0)") }
        for id in saved.isEmpty ? [0] : saved { openFace(id: id) }

        buildMainMenu()

        // A bare Esc never reaches the menu, so catch it directly.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            Speaker.shared.stop()
            return nil
        }

        server = HookServer(port: HookServer.defaultPort)
        server?.start()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Windows

    private func openFace(id: Int) {
        let face = FaceWindow(id: id) { [unowned self] in self.makeFaceMenu(title: "Face", faceTarget: $0) }
        face.onClose = { [weak self] closed in
            guard let self else { return }
            self.faces.removeAll { $0 === closed }
            // Closing the last window quits; keep it in the list so it comes back next time.
            if !self.faces.isEmpty { self.saveWindows() }
        }
        faces.append(face)
        face.window.makeKeyAndOrderFront(nil)
    }

    private func saveWindows() {
        UserDefaults.standard.set(faces.map(\.id), forKey: "faceWindows")
    }

    @objc private func newFace() {
        openFace(id: (faces.map(\.id).max() ?? -1) + 1)
        saveWindows()
    }

    // MARK: Menus

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Talking Face", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Talking Face", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let faceItem = NSMenuItem()
        faceItem.submenu = makeFaceMenu(title: "Face", faceTarget: nil)
        main.addItem(faceItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let newItem = windowMenu.addItem(withTitle: "New Face Window", action: #selector(newFace), keyEquivalent: "n")
        newItem.target = self
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    /// Shared between the menu bar and each face's right-click menu.
    /// Face styles go to `faceTarget`, or to the front window when nil.
    private func makeFaceMenu(title: String, faceTarget: FaceWindow?) -> NSMenu {
        let menu = NSMenu(title: title)
        func add(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command,
                 target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target ?? self
            menu.addItem(item)
        }
        add("Stay on Top", #selector(toggleOnTop), "t")
        add("Mute", #selector(toggleMute), "m", [.command, .shift])
        menu.addItem(.separator())
        add("Stop Talking", #selector(stopTalking), ".")  // Esc is also caught in applicationDidFinishLaunching
        add("Say Something", #selector(sayTest), "j")
        add("Pull a Face", #selector(pullAFace), "f")
        add("New Face Window", #selector(newFace), "n")
        menu.addItem(.separator())
        for (i, style) in FaceStyle.allCases.enumerated() {
            add(style.title, #selector(FaceWindow.pickStyle(_:)), "\(i + 1)")
            menu.items.last?.target = faceTarget  // nil = responder chain = front window
            menu.items.last?.representedObject = style.rawValue
        }
        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleOnTop): item.state = Prefs.stayOnTop ? .on : .off
        case #selector(toggleMute): item.state = Prefs.muted ? .on : .off
        default: break
        }
        return true
    }

    @objc private func toggleOnTop() {
        Prefs.stayOnTop.toggle()
        for face in faces { face.window.level = Prefs.stayOnTop ? .floating : .normal }
    }

    @objc private func toggleMute() {
        Prefs.muted.toggle()
        if Prefs.muted { Speaker.shared.stop() }
    }

    @objc private func pullAFace() { Quirks.pullAFace() }

    @objc private func stopTalking() { Speaker.shared.stop() }

    @objc private func sayTest() {
        Speaker.shared.speak("Hello! I'm your talking face. When Claude finishes an answer, I'll read it out loud.")
    }
}

enum Prefs {
    static var stayOnTop: Bool {
        get { UserDefaults.standard.object(forKey: "stayOnTop") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "stayOnTop") }
    }
    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }
    /// Optional `say` voice name, e.g. `defaults write io.purplehippo.talkingface voice Samantha`.
    static var voice: String? { UserDefaults.standard.string(forKey: "voice") }
    /// Seconds to shift the mouth vs. the audio; positive = mouth earlier.
    /// e.g. `defaults write io.purplehippo.talkingface lipSyncOffset -float 0.05`
    static var lipSyncOffset: Double { UserDefaults.standard.double(forKey: "lipSyncOffset") }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
