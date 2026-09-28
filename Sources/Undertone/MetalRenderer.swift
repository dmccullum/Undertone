import CoreGraphics
import Foundation
import Metal

/// Renders on the GPU with one compute kernel for every style, from the same `Scene` the CPU
/// renderer uses. Export reads the kernel's 8-bit sRGB bytes back into a `CGImage`; the preview can
/// run the same kernel straight into a drawable. `GradientRenderer` stays the reference and fallback.
final class MetalRenderer: @unchecked Sendable {
    enum MetalError: Error { case noDevice, setupFailed, renderFailed(String) }

    /// Nil when this Mac has no usable Metal device or the shader fails to compile.
    static let shared: MetalRenderer? = try? MetalRenderer()

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bytesPipeline: MTLComputePipelineState
    let texturePipeline: MTLComputePipelineState

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw MetalError.noDevice }
        let options = MTLCompileOptions()
        // Precise math, so the GPU tracks the CPU reference.
        if #available(macOS 15.0, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: MetalShaders.source, options: options)
        guard let bytesFunction = library.makeFunction(name: "renderBytes"),
              let textureFunction = library.makeFunction(name: "renderTexture") else { throw MetalError.setupFailed }
        self.device = device
        self.queue = queue
        bytesPipeline = try device.makeComputePipelineState(function: bytesFunction)
        texturePipeline = try device.makeComputePipelineState(function: textureFunction)
    }

    func render(_ recipe: GradientRecipe, width: Int, height: Int) throws -> CGImage {
        let scene = try GradientRenderer.Scene(recipe, width: width, height: height)
        let length = width * height * 4
        guard let output = device.makeBuffer(length: length, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { throw MetalError.setupFailed }
        encoder.setComputePipelineState(bytesPipeline)
        try bind(scene, to: encoder)
        encoder.setBuffer(output, offset: 0, index: MetalBuffer.output.rawValue)
        dispatch(encoder, pipeline: bytesPipeline, width: width, height: height)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if let error = commands.error { throw MetalError.renderFailed(error.localizedDescription) }
        return try GradientRenderer.image(from: Data(bytes: output.contents(), count: length), width: width, height: height)
    }

    /// Encodes the preview: the same kernel math written straight into a texture (a drawable), with no
    /// readback. The texture must be `.bgra8Unorm` or `.rgba8Unorm` with shader-write usage.
    func encodePreview(_ scene: GradientRenderer.Scene, into texture: MTLTexture, on commands: MTLCommandBuffer) throws {
        guard let encoder = commands.makeComputeCommandEncoder() else { throw MetalError.setupFailed }
        encoder.setComputePipelineState(texturePipeline)
        try bind(scene, to: encoder)
        encoder.setTexture(texture, index: 0)
        dispatch(encoder, pipeline: texturePipeline, width: min(scene.width, texture.width), height: min(scene.height, texture.height))
        encoder.endEncoding()
    }

    func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threadWidth = pipeline.threadExecutionWidth
        let threads = MTLSize(width: threadWidth, height: max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth), depth: 1)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: threads)
    }

    /// Packs a scene into the kernel's buffers. Unused inputs get a small placeholder buffer, since
    /// every declared buffer must be bound.
    func bind(_ scene: GradientRenderer.Scene, to encoder: MTLComputeCommandEncoder) throws {
        var floats = [Float](repeating: 0, count: MetalFloat.allCases.count)
        var ints = [Int32](repeating: 0, count: MetalInt.allCases.count)
        func set(_ slot: MetalFloat, _ value: Double) { floats[slot.rawValue] = Float(value) }
        func set(_ slot: MetalInt, _ value: Int) { ints[slot.rawValue] = Int32(truncatingIfNeeded: value) }

        set(.width, scene.width); set(.height, scene.height)
        ints[MetalInt.mode.rawValue] = scene.mode.metalIndex
        set(.hasColors, scene.hasColors ? 1 : 0)
        set(.grainCellSize, scene.grainCellSize)
        ints[MetalInt.grainSeed.rawValue] = Int32(bitPattern: scene.grainSeed)
        set(.grain, scene.grain)
        set(.lineStartX, scene.lineStartX); set(.lineStartY, scene.lineStartY)
        set(.lineDX, scene.lineDX); set(.lineDY, scene.lineDY); set(.lineLengthSquared, scene.lineLengthSquared)
        set(.centerX, scene.centerX); set(.centerY, scene.centerY); set(.fadeWidth, scene.fadeWidth)
        set(.axisX, scene.axisX); set(.axisY, scene.axisY); set(.crossX, scene.crossX); set(.crossY, scene.crossY)
        set(.position, scene.position); set(.flow, scene.flow); set(.phase, scene.phase)
        set(.softnessCore, scene.softnessCore); set(.swirlStrength, scene.swirlStrength)
        set(.swirlCenterX, scene.swirlCenterX); set(.swirlCenterY, scene.swirlCenterY)
        let empty = GradientRenderer.Scene.emptyColor
        set(.emptyRed, empty.red); set(.emptyGreen, empty.green); set(.emptyBlue, empty.blue)

        var stops: [SIMD4<Float>] = []
        var waves: [SIMD4<Float>] = []
        if let organic = scene.organic {
            for index in organic.xs.indices {
                stops.append(SIMD4(Float(organic.labs[index].lightness), Float(organic.labs[index].a), Float(organic.labs[index].b), 0))
                stops.append(SIMD4(Float(organic.xs[index]), Float(organic.ys[index]), Float(organic.weights[index]), 0))
            }
            waves = organic.waves.map { SIMD4(Float($0.dx), Float($0.dy), Float($0.frequency), Float($0.phase)) }
            set(.organicFalloff, organic.falloff); set(.organicFlowStep, organic.flowStep)
            set(.organicSwirlStrength, organic.swirlStrength)
            set(.organicSwirlCenterX, organic.swirlCenterX); set(.organicSwirlCenterY, organic.swirlCenterY)
            set(.flowSteps, GradientRenderer.OrganicField.flowSteps)
        } else {
            for stop in scene.tonalStops {
                stops.append(SIMD4(Float(stop.color.red), Float(stop.color.green), Float(stop.color.blue), 0))
                stops.append(SIMD4(Float(stop.x), Float(stop.y), Float(stop.weight), 0))
            }
        }
        set(.stopCount, stops.count / 2)
        set(.waveCount, waves.count)
        let palette = scene.palette.map { SIMD4(Float($0.red), Float($0.green), Float($0.blue), 0) }
        set(.paletteCount, palette.count)

        var lattice: [SIMD4<Float>] = [], latticeColors: [SIMD4<Float>] = []
        var triangles: [UInt32] = [], tileOffsets: [UInt32] = [0], tileIndices: [UInt32] = []
        if let mesh = scene.mesh {
            lattice = mesh.px.indices.map { SIMD4(Float(mesh.px[$0]), Float(mesh.py[$0]), 0, 0) }
            latticeColors = mesh.px.indices.map { SIMD4(Float(mesh.lightness[$0]), Float(mesh.aChannel[$0]), Float(mesh.bChannel[$0]), 0) }
            triangles = mesh.triangles.map { UInt32($0) }
            for tile in mesh.tiles {
                tileIndices += tile.map { UInt32($0) }
                tileOffsets.append(UInt32(tileIndices.count))
            }
            set(.tileColumns, mesh.tileColumns); set(.tileRows, mesh.tileRows)
            set(.tileSize, GradientRenderer.MeshRaster.tileSize)
            set(.latticeCount, lattice.count)
            set(.meshScaleX, mesh.scaleX); set(.meshScaleY, mesh.scaleY)
        }

        try setBuffer(floats, .floats, encoder)
        try setBuffer(ints, .ints, encoder)
        try setBuffer(stops, .stops, encoder)
        try setBuffer(palette, .palette, encoder)
        try setBuffer(waves, .waves, encoder)
        try setBuffer(scene.xWarp.map(Float.init), .xWarp, encoder)
        try setBuffer(scene.yWarp.map(Float.init), .yWarp, encoder)
        try setBuffer(lattice, .lattice, encoder)
        try setBuffer(latticeColors, .latticeColors, encoder)
        try setBuffer(triangles, .triangles, encoder)
        try setBuffer(tileOffsets, .tileOffsets, encoder)
        try setBuffer(tileIndices, .tileIndices, encoder)
    }

    private func setBuffer<Element>(_ values: [Element], _ slot: MetalBuffer, _ encoder: MTLComputeCommandEncoder) throws {
        let length = values.count * MemoryLayout<Element>.stride
        // Small inputs go inline; larger ones (mesh tiles, warp tables) get their own buffer.
        if length == 0 {
            var placeholder = SIMD4<Float>(repeating: 0)
            encoder.setBytes(&placeholder, length: MemoryLayout<SIMD4<Float>>.stride, index: slot.rawValue)
        } else if length <= 4_096 {
            values.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: length, index: slot.rawValue) }
        } else {
            guard let buffer = values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: length, options: .storageModeShared) }) else {
                throw MetalError.setupFailed
            }
            encoder.setBuffer(buffer, offset: 0, index: slot.rawValue)
        }
    }
}
