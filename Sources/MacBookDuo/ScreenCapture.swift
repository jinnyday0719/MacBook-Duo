import AppKit
import ScreenCaptureKit
import CoreMedia

final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "MacBookDuo.capture")
    private let lock = NSLock()
    private var deliveryPending = false
    private var active = false

    func start(displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw NSError(domain: "MacBookDuo", code: 1, userInfo: [NSLocalizedDescriptionKey: "본체 화면 또는 효과 창을 찾지 못했어요. 다시 시작해 주세요."])
        }
        // Exclude this app, including an overlay that is initially invisible.
        let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = CGDisplayPixelsWide(displayID)
        config.height = CGDisplayPixelsHigh(displayID)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        lock.withLock { active = true }
        try await stream.startCapture()
    }

    func stop() async {
        lock.withLock { active = false }
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onError?(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        guard active, !deliveryPending else { lock.unlock(); return }
        deliveryPending = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldDeliver = self.active
            self.deliveryPending = false
            self.lock.unlock()
            if shouldDeliver { self.onFrame?(buffer) }
        }
    }
}
