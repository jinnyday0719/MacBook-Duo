import AppKit

final class SensorLabView: NSView {
    private let sensor = LidSensor()
    private let angle = NSTextField(labelWithString: "—°")
    private let status = NSTextField(wrappingLabelWithString: "센서를 찾는 중…")
    private let details = NSTextField(wrappingLabelWithString: "")
    private let pause = NSButton(title: "일시 정지", target: nil, action: nil)
    private var paused = false
    private var observers: [NSObjectProtocol] = []
    var openAnimation: (() -> Void)?
    var onReading: ((LidSample) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let title = NSTextField(labelWithString: "힌지 센서 확인")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "화면을 천천히 움직이며 각도와 데이터 변화를 확인하세요.")
        subtitle.textColor = .secondaryLabelColor
        angle.font = .monospacedDigitSystemFont(ofSize: 76, weight: .medium)
        details.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        details.maximumNumberOfLines = 0
        status.maximumNumberOfLines = 0
        let reconnect = NSButton(title: "다시 연결", target: self, action: #selector(reconnectSensor))
        pause.target = self
        pause.action = #selector(togglePause)
        let animation = NSButton(title: "Stage 1 애니메이션 열기", target: self, action: #selector(showAnimation))
        let buttons = NSStackView(views: [pause, reconnect, animation])
        buttons.spacing = 12
        let note = NSTextField(wrappingLabelWithString: "각도는 센서의 정수 값입니다. 30회/초는 앱의 요청 주기이며 센서의 실제 갱신 속도를 뜻하지 않습니다. 테스트 애니메이션은 임시 기준 129°로 연결됩니다.")
        note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, subtitle, angle, status, details, buttons, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            details.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        sensor.onUpdate = { [weak self] sample in self?.display(sample) }
        sensor.onReading = { [weak self] sample in self?.onReading?(sample) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sensor.stop() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.paused else { return }
            self.sensor.start()
        })
        sensor.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        sensor.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func display(_ sample: LidSample) {
        angle.stringValue = sample.angle.map { "\($0)°" } ?? "—°"
        status.stringValue = sample.status
        let time = sample.date.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "—"
        details.stringValue = "장치  \(sample.device)\n\n원시 바이트  \(sample.bytes)\n\n읽기 성공  \(sample.reads)회    실패  \(sample.failures)회\n\n최근 읽기 소요  \(String(format: "%.2f", sample.latency)) ms\n\n마지막 성공  \(time)"
    }

    @objc private func togglePause() {
        paused.toggle()
        pause.title = paused ? "읽기 재개" : "일시 정지"
        if paused { sensor.stop() } else { sensor.start() }
    }

    @objc private func reconnectSensor() {
        if paused { togglePause() } else { sensor.reconnect() }
    }

    @objc private func showAnimation() { openAnimation?() }
}
