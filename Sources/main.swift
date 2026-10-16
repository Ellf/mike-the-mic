import AppKit
import SwiftUI

/// Hosting view that lets you drag the window by clicking anywhere on the face.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private var server: HookServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Speaker.clearTempFiles()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Talking Face"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.contentAspectRatio = NSSize(width: 2, height: 1)
        window.minSize = NSSize(width: 160, height: 80)
        let face = DraggableHostingView(rootView: FaceView())
        face.menu = makeFaceMenu(title: "Face")
        window.contentView = face
        window.setFrameAutosaveName("TalkingFaceWindow")
        if !window.setFrameUsingName("TalkingFaceWindow") { window.center() }
        window.level = Prefs.stayOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        self.window = window

        buildMainMenu()

        server = HookServer(port: HookServer.defaultPort)
        server?.start()

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
        faceItem.submenu = makeFaceMenu(title: "Face")
        main.addItem(faceItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    /// Shared between the menu bar and the right-click menu on the face.
    private func makeFaceMenu(title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        func add(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = self
            menu.addItem(item)
        }
        add("Stay on Top", #selector(toggleOnTop), "t")
        add("Mute", #selector(toggleMute), "m", [.command, .shift])
        menu.addItem(.separator())
        add("Stop Talking", #selector(stopTalking), "\u{1b}", [])
        add("Say Something", #selector(sayTest), "j")
        add("Pull a Face", #selector(pullAFace), "f")
        menu.addItem(.separator())
        for (i, style) in FaceStyle.allCases.enumerated() {
            add(style.title, #selector(pickStyle(_:)), "\(i + 1)")
            menu.items.last?.representedObject = style.rawValue
        }
        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleOnTop): item.state = Prefs.stayOnTop ? .on : .off
        case #selector(toggleMute): item.state = Prefs.muted ? .on : .off
        case #selector(pickStyle(_:)): item.state = item.representedObject as? String == Prefs.faceStyle.rawValue ? .on : .off
        default: break
        }
        return true
    }

    @objc private func toggleOnTop() {
        Prefs.stayOnTop.toggle()
        window.level = Prefs.stayOnTop ? .floating : .normal
    }

    @objc private func toggleMute() {
        Prefs.muted.toggle()
        if Prefs.muted { Speaker.shared.stop() }
    }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = FaceStyle(rawValue: raw) { Prefs.faceStyle = style }
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
    static var faceStyle: FaceStyle {
        get { FaceStyle(rawValue: UserDefaults.standard.string(forKey: "faceStyle") ?? "") ?? .bot }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "faceStyle") }
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
