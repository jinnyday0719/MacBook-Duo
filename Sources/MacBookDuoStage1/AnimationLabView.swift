import AppKit

final class AnimationLabView: NSView {
    private let renderer: FoldRendererView
    private let slider: NSSlider
    private let progressLabel: NSTextField
    private let sensorToggle = NSButton(checkboxWithTitle: "힌지 센서 연결", target: nil, action: nil)
    private var latestSample = LidSample()
    private let referenceAngle: Float = 129

    override init(frame frameRect: NSRect) {
        renderer = FoldRendererView(frame: .zero)
        slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        progressLabel = NSTextField(labelWithString: "0.00")
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 1).cgColor

        renderer.autoresizingMask = [.width, .height]
        addSubview(renderer)

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.autoresizingMask = [.width, .minYMargin]
        addSubview(slider)

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        progressLabel.alignment = .right
        progressLabel.textColor = .white
        progressLabel.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(progressLabel)
        sensorToggle.state = .on
        sensorToggle.target = self
        sensorToggle.action = #selector(modeChanged)
        addSubview(sensorToggle)
        slider.isEnabled = false
        updateSensor(latestSample)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let controlHeight: CGFloat = 96
        renderer.frame = NSRect(
            x: 0,
            y: controlHeight,
            width: bounds.width,
            height: max(0, bounds.height - controlHeight)
        )
        slider.frame = NSRect(
            x: 28,
            y: 20,
            width: max(80, bounds.width - 56),
            height: 24
        )
        progressLabel.frame = NSRect(
            x: 190,
            y: 58,
            width: max(0, bounds.width - 218),
            height: 22
        )
        sensorToggle.frame = NSRect(x: 28, y: 56, width: 155, height: 24)
    }

    func updateSensor(_ sample: LidSample) {
        latestSample = sample
        guard sensorToggle.state == .on else { return }
        // Keep physical rotation equal to reference minus measured angle.
        renderer.maxTilt = referenceAngle * .pi / 180
        guard let angle = sample.angle else {
            renderer.setTargetProgress(0)
            slider.doubleValue = 0
            progressLabel.stringValue = "기준 129° · 센서 대기/중지 · 효과 해제"
            return
        }
        let rotation = min(referenceAngle, max(0, referenceAngle - Float(angle)))
        let progress = rotation / referenceAngle
        renderer.setTargetProgress(progress)
        slider.doubleValue = Double(progress)
        progressLabel.stringValue = String(format: "현재 %d° · 기준 129° · 회전 %.0f° · %.0f%%", Int(angle), rotation, progress * 100)
    }

    @objc private func modeChanged() {
        slider.isEnabled = sensorToggle.state == .off
        if sensorToggle.state == .on {
            updateSensor(latestSample)
        } else {
            renderer.maxTilt = .pi / 2
            sliderChanged(slider)
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let progress = Float(sender.doubleValue)
        renderer.setTargetProgress(progress)
        progressLabel.stringValue = String(format: "수동 슬라이더 · %.0f%%", progress * 100)
    }
}
