import AppKit

@main
enum SpindleApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // A menu bar agent: no Dock icon, no app switcher entry. Info.plist says the same with
        // LSUIElement; setting it here too keeps `swift run` from flashing a Dock icon.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
