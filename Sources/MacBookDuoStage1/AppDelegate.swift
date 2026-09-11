import AppKit
import Metal

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var contentView: AnimationLabView!
    private var sensorWindow: NSWindow!
    private var latestReading = LidSample()

    static func main() {
        if CommandLine.arguments.contains("--check-shaders") {
            do {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    throw NSError(domain: "Stage1", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"])
                }
                _ = try FoldRendererView.makePipeline(device: device)
                print("Metal shader compilation and pipeline creation succeeded.")
                return
            } catch {
                fputs("Metal build failed: \(error)\n", stderr)
                exit(1)
            }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sensorView = SensorLabView(frame: NSRect(x: 0, y: 0, width: 720, height: 640))
        sensorView.openAnimation = { [weak self] in self?.showAnimation() }
        sensorView.onReading = { [weak self] sample in
            self?.latestReading = sample
            self?.contentView?.updateSensor(sample)
        }
        sensorWindow = NSWindow(contentRect: sensorView.frame,
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: false)
        sensorWindow.title = "MacBook Duo · 힌지 센서 확인"
        sensorWindow.isReleasedWhenClosed = false
        sensorWindow.contentMinSize = NSSize(width: 680, height: 640)
        sensorWindow.contentView = sensorView
        sensorWindow.center()
        sensorWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAnimation() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let initialSize = NSSize(width: 1_024, height: 700)
        let contentView = AnimationLabView(
            frame: NSRect(origin: .zero, size: initialSize)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "MacBook Duo · Stage 1"
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 800, height: 520)
        window.contentView = contentView
        window.setContentSize(initialSize)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.contentView = contentView
        contentView.updateSensor(latestReading)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
