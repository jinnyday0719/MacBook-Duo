import AppKit
import Metal
import MetalKit
import simd

struct FoldUniforms {
    var progress: Float
    var aspect: Float
    var maxTilt: Float
    var blurStrength: Float
    var darkening: Float
    var voidStrength: Float
}

final class FoldRendererView: MTKView, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let sourceTexture: MTLTexture
    private let samplerState: MTLSamplerState

    private(set) var progress: Float = 0
    var maxTilt: Float = .pi / 2
    private var targetProgress: Float = 0
    private var lastDrawTime: CFTimeInterval = 0

    init(frame frameRect: NSRect) {
        guard let metalDevice = MTLCreateSystemDefaultDevice(),
              let queue = metalDevice.makeCommandQueue(),
              let pipeline = try? Self.makePipeline(device: metalDevice),
              let texture = TestTexture.makeTexture(device: metalDevice),
              let sampler = Self.makeSampler(device: metalDevice),
              let vertices = Self.makeVertexBuffer(device: metalDevice) else {
            fatalError("Metal 초기화에 실패했습니다.")
        }

        commandQueue = queue
        pipelineState = pipeline
        sourceTexture = texture
        samplerState = sampler
        vertexBuffer = vertices

        super.init(frame: frameRect, device: metalDevice)

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
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              drawableSize.width > 0,
              drawableSize.height > 0 else {
            return
        }

        let now = CACurrentMediaTime()
        if lastDrawTime == 0 || now - lastDrawTime > 0.1 {
            progress = targetProgress
        } else {
            // Sensor samples arrive at 30 Hz. Move toward each new sample over
            // one sample interval so every display frame has a new value.
            let deltaTime = Float(max(0, now - lastDrawTime))
            let interpolation = min(1, deltaTime / (1.0 / 30.0))
            progress += (targetProgress - progress) * interpolation
        }
        lastDrawTime = now

        var uniforms = FoldUniforms(
            progress: progress,
            aspect: Float(drawableSize.width / max(drawableSize.height, 1)),
            maxTilt: maxTilt,
            blurStrength: 1,
            darkening: 0.42,
            voidStrength: 1
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
