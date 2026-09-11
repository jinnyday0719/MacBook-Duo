import AppKit
import Metal
import ServiceManagement

private final class EffectWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var calibration = AngleCalibration()
    private var baseline: Double?
    private var displayedBaseline: Double?
    private var baselineTransition: (from: Double, to: Double, started: CFTimeInterval)?
    private var effectEngagementStarted: CFTimeInterval?
    private var effectDeadZone: Float = 2
    private var permissionPrompted = false
    private let deadZoneChoice = NSPopUpButton()
    private let loginButton = NSButton(checkboxWithTitle: "로그인 시 자동 시작", target: nil, action: nil)
    private let loginSettingsButton = NSButton(title: "로그인 항목 승인하기…", target: nil, action: nil)
    private let permissionButton = NSButton(title: "화면 기록 권한 설정 열기", target: nil, action: nil)
    private var menuIsOpen = false
    private var window: NSWindow!
    private var overlay: EffectWindow?
    private var renderer: FoldRendererView?
    private var overlayAlphaTarget: CGFloat = 0
    private let sensor = LidSensor()
    private var capture: ScreenCapture?
    private var generation = 0
    private var starting = false
    private var running = false
    private var frameReady = false
    private var angle: UInt16?
    private var sensorTime = Date.distantPast
    private var watchdog: Timer?
    private var automaticStartTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let state = NSTextField(wrappingLabelWithString: "앱 실행 중 · 화면 기록 권한을 확인합니다.")
    private let angleLabel = NSTextField(labelWithString: "현재 각도 —° · 기준 자동 설정 중")

    static func main() {
        if CommandLine.arguments.contains("--check-shaders") {
            do {
                guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain: "Metal", code: 1) }
                _ = try FoldRendererView.makePipeline(device: device)
                print("Metal shader compilation and pipeline creation succeeded.")
            } catch { fputs("\(error)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "MacBook Duo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "MacBook Duo")
        statusItem.button?.toolTip = "MacBook Duo"
        let statusMenu = NSMenu()
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        let settings = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        statusMenu.addItem(settings)
        statusMenu.addItem(.separator())
        let quit = NSMenuItem(title: "MacBook Duo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusMenu.addItem(quit)
        statusItem.menu = statusMenu
        let saved = UserDefaults.standard.object(forKey: "baselineAngle") as? Double
        baseline = saved.flatMap { (0...180).contains($0) ? $0 : nil }
        displayedBaseline = baseline
        if let savedDeadZone = UserDefaults.standard.object(forKey: "effectDeadZone") as? Double,
           [0.0, 1, 2].contains(savedDeadZone) { effectDeadZone = Float(savedDeadZone) }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        let title = NSTextField(labelWithString: "MacBook Duo")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        let note = NSTextField(wrappingLabelWithString: "앱을 켜면 자동으로 권한과 힌지 각도를 확인합니다.\n특정 각도가 안정적으로 유지되면 그 각도를 기준으로 저장하고 효과를 시작합니다.")
        note.textColor = .secondaryLabelColor
        permissionButton.target = self
        permissionButton.action = #selector(openScreenRecordingSettings)
        loginButton.target = self
        loginButton.action = #selector(loginSettingChanged)
        loginSettingsButton.target = self
        loginSettingsButton.action = #selector(openLoginSettings)
        let loginRow = NSStackView(views: [loginButton, loginSettingsButton])
        loginRow.spacing = 12
        refreshLoginSetting()
        deadZoneChoice.addItems(withTitles: ["0°", "1°", "2°"])
        deadZoneChoice.selectItem(at: Int(effectDeadZone))
        deadZoneChoice.target = self
        deadZoneChoice.action = #selector(effectDeadZoneChanged)
        let calibrationRow = NSStackView(views: [
            NSTextField(labelWithString: "유지 시간 1.5초"),
            NSTextField(labelWithString: "효과 데드존"), deadZoneChoice])
        calibrationRow.spacing = 12
        let quitButton = NSButton(title: "MacBook Duo 종료", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let stack = NSStackView(views: [title, note, angleLabel, calibrationRow, loginRow, permissionButton, state, quitButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            state.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MacBook Duo"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.center()
        sensor.onReading = { [weak self] sample in
            guard let self else { return }
            self.angle = sample.angle
            self.sensorTime = Date()
            let measured = sample.angle.map(Double.init)
            self.updateBaselineTransition()
            // Opening beyond the reference is an intentional new posture.
            // Apply it immediately after the dead zone instead of waiting.
            if let baseline = self.baseline, let measured,
               measured > baseline + Double(self.effectDeadZone) {
                self.setBaseline(measured.rounded(), animated: false)
            } else if let candidate = self.calibration.ingest(measured,
                at: ProcessInfo.processInfo.systemUptime) {
                // Closing below the reference still requires the stability
                // interval, then settles into the new reference gracefully.
                self.setBaseline(candidate, animated: true)
            }
            self.refreshAngle()
            self.attemptAutomaticStart()
            self.updateEffect()
        }
        sensor.start()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.sensorTime) > 0.5 else { return }
            self.angle = nil
            self.calibration.reset()
            self.refreshAngle()
            self.updateEffect()
        }
        automaticStartTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.attemptAutomaticStart()
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopEffect()
            self?.angle = nil
            self?.sensorTime = .distantPast
            self?.sensor.stop()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sensor.start()
            self?.attemptAutomaticStart()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopEffect()
            self?.attemptAutomaticStart()
        })
        DispatchQueue.main.async { [weak self] in self?.attemptAutomaticStart() }
    }

    private func refreshAngle() {
        let reference = baseline.map { "\(Int($0))°" } ?? "자동 설정 중"
        angleLabel.stringValue = "현재 각도 \(angle.map(String.init) ?? "—")° · 기준 \(reference)"
    }

    private func setBaseline(_ value: Double, animated: Bool) {
        guard baseline != value else { return }
        let now = CACurrentMediaTime()
        let current = updateBaselineTransition(at: now)
        baseline = value
        UserDefaults.standard.set(value, forKey: "baselineAngle")
        calibration.reset()

        guard animated, let current, value < current, renderer != nil, running else {
            displayedBaseline = value
            baselineTransition = nil
            renderer?.transitionBlur = 0
            return
        }
        baselineTransition = (from: current, to: value, started: now)
    }

    @discardableResult
    private func updateBaselineTransition(at now: CFTimeInterval = CACurrentMediaTime()) -> Double? {
        guard let transition = baselineTransition else {
            displayedBaseline = displayedBaseline ?? baseline
            renderer?.transitionBlur = 0
            return displayedBaseline ?? baseline
        }
        let progress = min(1, max(0, (now - transition.started) / 0.32))
        let eased = progress * progress * (3 - 2 * progress)
        displayedBaseline = transition.from + (transition.to - transition.from) * eased
        // Peak blur in the middle of the reference change, then clear again.
        renderer?.transitionBlur = Float(sin(Double.pi * progress) * 1.8)
        if progress >= 1 {
            displayedBaseline = transition.to
            baselineTransition = nil
            renderer?.transitionBlur = 0
        }
        return displayedBaseline
    }

    private func refreshLoginSetting() {
        let status = SMAppService.mainApp.status
        loginButton.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginSettingsButton.isHidden = status != .requiresApproval
    }

    @objc private func loginSettingChanged() {
        do {
            if loginButton.state == .on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 시 자동 시작 설정을 변경하지 못했어요."
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
        refreshLoginSetting()
    }

    @objc private func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshLoginSetting()
    }

    @objc private func effectDeadZoneChanged() {
        effectDeadZone = Float(deadZoneChoice.indexOfSelectedItem)
        UserDefaults.standard.set(Double(effectDeadZone), forKey: "effectDeadZone")
        updateEffect()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        updateEffect()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        updateEffect()
    }

    @objc private func showSettings() {
        refreshLoginSetting()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateEffect()
    }

    private func attemptAutomaticStart() {
        guard !starting, !running else { return }
        guard CGPreflightScreenCaptureAccess() else {
            if !permissionPrompted {
                permissionPrompted = true
                _ = CGRequestScreenCaptureAccess()
            }
            state.stringValue = "화면 기록 권한을 허용하면 자동으로 시작합니다."
            return
        }
        guard baseline != nil else {
            state.stringValue = "현재 화면 각도를 1.5초 동안 유지하면 기준을 자동으로 정합니다."
            return
        }
        guard angle != nil else {
            state.stringValue = "힌지 센서가 연결되면 자동으로 시작합니다."
            return
        }
        startEffect()
    }

    private func startEffect() {
        guard !starting, !running else { return }
        guard let baseline else { return }
        guard angle != nil else { state.stringValue = "힌지 센서가 연결된 뒤 다시 시작해 주세요."; return }
        guard let screen = NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            state.stringValue = "MacBook 본체 디스플레이를 찾지 못했어요."
            return
        }
        generation += 1
        let token = generation
        starting = true
        state.stringValue = "실제 화면을 준비하는 중…"
        let view = FoldRendererView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.maxTilt = Float(baseline) * .pi / 180
        view.isPaused = true
        let effect = EffectWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        effect.isReleasedWhenClosed = false
        effect.ignoresMouseEvents = true
        effect.hasShadow = false
        effect.backgroundColor = .black
        effect.level = .screenSaver
        effect.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        effect.contentView = view
        // Register the window for capture exclusion without showing its pixels.
        effect.alphaValue = 0
        overlayAlphaTarget = 0
        effect.orderFrontRegardless()
        overlay = effect
        renderer = view
        let capture = ScreenCapture()
        self.capture = capture
        capture.onFrame = { [weak self] frame in
            guard let self, self.generation == token else { return }
            guard self.renderer?.updateFrame(frame) == true else {
                self.stopEffect()
                self.state.stringValue = "캡처 화면을 표시하지 못했어요. 다시 시작해 주세요."
                return
            }
            self.frameReady = true
            self.updateEffect()
        }
        capture.onError = { [weak self] error in
            guard let self, self.generation == token else { return }
            self.stopEffect()
            self.state.stringValue = "화면 캡처 중단: \(error.localizedDescription)"
        }
        Task { @MainActor in
            do {
                try await capture.start(displayID: id.uint32Value)
                guard self.generation == token else { await capture.stop(); return }
                self.starting = false
                self.running = true
                self.window.orderOut(nil)
                self.state.stringValue = "자동 실행 중 · 펼치면 효과 해제"
                self.updateEffect()
            } catch {
                guard self.generation == token else { return }
                self.stopEffect()
                self.state.stringValue = "시작하지 못했어요: \(error.localizedDescription)"
            }
        }
    }

    private func updateEffect() {
        let visualBaseline = updateBaselineTransition()
        // Keep menu/settings readable and reachable above the full-screen effect.
        guard !menuIsOpen, !window.isVisible, running, frameReady, let angle,
              let visualBaseline, visualBaseline > 0 else {
            setOverlayAlpha(0, animated: false)
            renderer?.isPaused = true
            return
        }
        renderer?.maxTilt = Float(visualBaseline) * .pi / 180
        // Subtract the dead zone so crossing its boundary starts at zero,
        // rather than jumping directly to a two-degree fold.
        let closing = max(0, Float(visualBaseline) - Float(angle) - effectDeadZone)
        let progress = min(1, closing / max(1, Float(visualBaseline) - effectDeadZone))
        guard progress > 0 else {
            effectEngagementStarted = nil
            renderer?.effectBlend = 0
            setOverlayAlpha(0, animated: true)
            renderer?.setTargetProgress(0, immediately: true)
            renderer?.isPaused = true
            return
        }
        if effectEngagementStarted == nil {
            effectEngagementStarted = CACurrentMediaTime()
        }
        let engagementTime = CACurrentMediaTime() - (effectEngagementStarted ?? CACurrentMediaTime())
        let engagementProgress = min(1, max(0, engagementTime / 0.22))
        renderer?.effectBlend = Float(engagementProgress * engagementProgress * (3 - 2 * engagementProgress))
        renderer?.setTargetProgress(progress)
        renderer?.isPaused = false
        setOverlayAlpha(1, animated: true)
    }

    private func setOverlayAlpha(_ value: CGFloat, animated: Bool) {
        guard let overlay else { return }
        let target = min(1, max(0, value))
        guard abs(overlayAlphaTarget - target) > 0.001 else { return }
        overlayAlphaTarget = target
        guard animated else {
            overlay.alphaValue = target
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            overlay.animator().alphaValue = target
        }
    }

    private func stopEffect() {
        generation += 1
        calibration.reset()
        running = false
        starting = false
        frameReady = false
        overlay?.orderOut(nil)
        renderer?.isPaused = true
        overlay = nil
        renderer = nil
        overlayAlphaTarget = 0
        effectEngagementStarted = nil
        let previous = capture
        capture = nil
        Task { await previous?.stop() }
        state.stringValue = "자동 실행을 준비하는 중…"
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateEffect() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopEffect()
        sensor.stop()
        watchdog?.invalidate()
        automaticStartTimer?.invalidate()
    }
}
