import Foundation
import IOKit.hid

struct LidSample {
    var status = "센서를 찾는 중…"
    var angle: UInt16?
    var bytes = "—"
    var device = "—"
    var reads = 0
    var failures = 0
    var latency = 0.0
    var date: Date?
}

// All HID handles and mutable sampling state belong to this serial queue.
final class LidSensor {
    var onUpdate: ((LidSample) -> Void)?
    var onReading: ((LidSample) -> Void)?
    private let queue = DispatchQueue(label: "MacBookDuo.lid-sensor")
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var sample = LidSample()
    private var consecutiveFailures = 0
    private var lastDelivery = Date.distantPast

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            connect()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(2))
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            disconnect()
            sample.angle = nil
            sample.status = "일시 정지"
            publish(force: true)
        }
    }

    func reconnect() {
        queue.async { [self] in
            disconnect()
            connect()
        }
    }

    private func disconnect() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }

    private func connect() {
        sample.angle = nil
        sample.bytes = "—"
        sample.device = "—"
        consecutiveFailures = 0
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Match only the Apple sensor collection, never keyboards or mice.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDPrimaryUsagePageKey: 0x0020,
            kIOHIDPrimaryUsageKey: 0x008A
        ] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            sample.status = "지원하는 센서를 찾지 못했어요. 다시 연결을 눌러 주세요."
            publish(force: true)
            return
        }
        var lastError: IOReturn = kIOReturnNotFound
        for candidate in devices {
            let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else { lastError = result; continue }
            // Validate the known feature report before accepting a device.
            var bytes = [UInt8](repeating: 0, count: 8)
            var length = bytes.count
            let read = IOHIDDeviceGetReport(candidate, kIOHIDReportTypeFeature, 1, &bytes, &length)
            if read == kIOReturnSuccess, length >= 3, bytes[0] == 1 {
                device = candidate
                let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String ?? "Apple 힌지 센서"
                let pid = IOHIDDeviceGetProperty(candidate, kIOHIDProductIDKey as CFString) as? NSNumber
                sample.device = product + String(format: " · PID 0x%04X", pid?.intValue ?? 0)
                sample.status = "연결됨 · 읽는 중"
                publish(force: true)
                return
            }
            lastError = read == kIOReturnSuccess ? kIOReturnBadArgument : read
            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        sample.status = "센서 열기/보고서 확인 실패 · \(errorText(lastError))"
        publish(force: true)
    }

    private func poll() {
        guard let device else { return }
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = bytes.count
        let start = ProcessInfo.processInfo.systemUptime
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        sample.latency = (ProcessInfo.processInfo.systemUptime - start) * 1000
        sample.bytes = bytes.prefix(max(0, min(length, bytes.count))).map { String(format: "%02X", $0) }.joined(separator: " ")
        if result == kIOReturnSuccess, length >= 3, bytes[0] == 1 {
            let angle = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
            if angle <= 360 {
                sample.angle = angle
                sample.reads += 1
                sample.date = Date()
                sample.status = "정상 · 초당 30회 읽기 요청"
                consecutiveFailures = 0
                publish()
                return
            }
        }
        sample.angle = nil
        sample.failures += 1
        consecutiveFailures += 1
        sample.status = result == kIOReturnSuccess ? "예상하지 못한 센서 데이터" : "읽기 실패 · \(errorText(result))"
        if consecutiveFailures >= 30 {
            disconnect()
            sample.status += " · 다시 연결을 눌러 주세요"
        }
        publish(force: true)
    }

    private func errorText(_ code: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }

    private func publish(force: Bool = false) {
        let reading = sample
        DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
        // Keep diagnostic text readable without tying rendering to sensor polling.
        guard force || Date().timeIntervalSince(lastDelivery) >= 0.1 else { return }
        lastDelivery = Date()
        let value = sample
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(value) }
    }
}
