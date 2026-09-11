import AppKit
import Metal
import MetalKit
import simd
import CoreVideo

struct FoldUniforms {
    var progress: Float
    var aspect: Float
    var maxTilt: Float
    var blurStrength: Float
    var darkening: Float
    var voidStrength: Float
    var effectBlend: Float
}

final class FoldRendererView: MTKView, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private var sourceTexture: MTLTexture?
    private var capturedFrame: CVPixelBuffer?
    private var textureReference: CVMetalTexture?
    private var textureCache: CVMetalTextureCache?
    private let samplerState: MTLSamplerState

    private(set) var progress: Float = 0
    var effectBlend: Float = 0
    var maxTilt: Float = .pi / 2
    var transitionBlur: Float = 0
    private var targetProgress: Float = 0
    private var progressVelocity: Float = 0
    private var lastDrawTime: CFTimeInterval = 0
    // A short critically damped response smooths 30 Hz sensor steps without
    // making the screen feel detached from the hinge.
    private let motionResponse: Float = 0.08

    init(frame frameRect: NSRect) {
        guard let metalDevice = MTLCreateSystemDefaultDevice(),
              let queue = metalDevice.makeCommandQueue(),
              let pipeline = try? Self.makePipeline(device: metalDevice),
              let sampler = Self.makeSampler(device: metalDevice),
              let vertices = Self.makeVertexBuffer(device: metalDevice) else {
            fatalError("Metal 초기화에 실패했습니다.")
        }

        commandQueue = queue
        pipelineState = pipeline
        samplerState = sampler
        vertexBuffer = vertices

        super.init(frame: frameRect, device: metalDevice)
        CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)

        colorPixelFormat = .bgra8Unorm_srgb
        framebufferOnly = true
        clearColor = MTLClearColor(red: 0.002, green: 0.004, blue: 0.008, alpha: 1)
        // Stage 1 targets the MacBook Pro built-in ProMotion panel.
        preferredFramesPerSecond = 120
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    func setTargetProgress(_ value: Float, immediately: Bool = false) {
        let clamped = min(max(value, 0), 1)
        targetProgress = clamped
        if immediately {
            progress = clamped
            progressVelocity = 0
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func updateFrame(_ buffer: CVPixelBuffer) -> Bool {
        guard let textureCache else { return false }
        var reference: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil,
            .bgra8Unorm_srgb, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &reference)
        guard result == kCVReturnSuccess, let reference,
              let texture = CVMetalTextureGetTexture(reference) else { return false }
        capturedFrame = buffer
        textureReference = reference
        sourceTexture = texture
        return true
    }

    func draw(in view: MTKView) {
        guard let sourceTexture, let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        let now = CACurrentMediaTime()
        if lastDrawTime == 0 || now - lastDrawTime > 0.1 {
            progress = targetProgress
            progressVelocity = 0
        } else {
            // Keep the presentation value and its velocity continuous when a
            // new 30 Hz sensor sample changes the target.
            let deltaTime = min(Float(max(0, now - lastDrawTime)), 1.0 / 30.0)
            let omega = 2.0 / motionResponse
            let displacement = progress - targetProgress
            let decay = Float(exp(-Double(omega * deltaTime)))
            let temporary = (progressVelocity + omega * displacement) * deltaTime
            progressVelocity = (progressVelocity - omega * temporary) * decay
            progress = targetProgress + (displacement + temporary) * decay
            if abs(progress - targetProgress) < 0.0005 && abs(progressVelocity) < 0.0005 {
                progress = targetProgress
                progressVelocity = 0
            }
        }
        lastDrawTime = now

        var uniforms = FoldUniforms(
            progress: progress,
            aspect: Float(drawableSize.width / max(drawableSize.height, 1)),
            maxTilt: maxTilt,
            blurStrength: 1 + transitionBlur,
            darkening: 0.42,
            voidStrength: 1,
            effectBlend: effectBlend
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        // Keep the IOSurface and its CV wrapper alive until GPU sampling ends.
        let heldFrame = capturedFrame
        let heldTexture = textureReference
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(heldFrame) {}
            withExtendedLifetime(heldTexture) {}
        }
        commandBuffer.commit()
    }

    static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: FoldShaderSource.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fold_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fold_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private static func makeVertexBuffer(device: MTLDevice) -> MTLBuffer? {
        let vertices = [
            Vertex(position: SIMD2(-1, -1), uv: SIMD2(0, 1)),
            Vertex(position: SIMD2(1, -1), uv: SIMD2(1, 1)),
            Vertex(position: SIMD2(-1, 1), uv: SIMD2(0, 0)),
            Vertex(position: SIMD2(1, 1), uv: SIMD2(1, 0))
        ]
        return device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: []
        )
    }
}
