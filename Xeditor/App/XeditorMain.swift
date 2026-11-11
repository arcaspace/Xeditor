import AppKit

@main
enum XeditorMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // NSApplication.delegate 是非持有引用，必须由这里强持有，直到 run() 返回。
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
