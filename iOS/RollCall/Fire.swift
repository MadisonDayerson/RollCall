import CoreGraphics
import Metal
import simd

/// The splash's fire, on the graphics chip: a burst of flame and embers the letters appear out of, then a front that
/// crosses them from left to right like a bush fire, in air moving as a fluid, and embers with weight that the air
/// carries, that knock each other about and bounce off the screen's edges.
final class Fire {
    /// Seconds from the burst.
    static let wipe = 1.5  // the letters have been still long enough to read, and the bush fire starts
    static let opens = wipe + 1.15  // it has reached the end and the app starts to show
    static let seconds = wipe + 2.7  // the last ember's out

    /// The same as `Now` in `FireShaders`.
    private struct Now {
        var size: SIMD2<Float>, middle: SIMD2<Float>, logo: SIMD4<Float>, across: SIMD2<Float>, down: SIMD2<Float>
        var cell: Float, time: Float = 0, dt: Float = Fire.step
        var ground: Float = 1
        var embers: UInt32
    }

    /// The same as `Ember` in `FireShaders`.
    struct Ember {
        var place: SIMD2<Float>, speed: SIMD2<Float> = .zero
        var radius: Float, depth: Float
        /// Below 0 while it's still part of a letter, and 0 once it's out.
        var heat: Float = -1
        var seed: Float
    }

    /// One letter picture and where it is, in points.
    typealias Letters = (picture: CGImage, frame: CGRect)

    private static let step: Float = 1 / 60
    private static let count = 1800, bursting = 600
    static let format = MTLPixelFormat.bgra8Unorm
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let kernels: [String: MTLComputePipelineState]
    private let flames, glowing, finish: MTLRenderPipelineState
    private var air, airNext, fire, fireNext, press, pressNext: MTLTexture
    private let spins, spreads, mask, logo, scene: MTLTexture
    private var embers, embersNext: MTLBuffer
    private var now: Now

    /// `lit` is a picture of the letters on black as they are before they catch, filling `frame`. Nil where Metal isn't
    /// available.
    init?(size: CGSize, scale: CGFloat, lit: CGImage, frame: CGRect, letters: [Letters]) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: FireShaders.source, options: nil) else { return nil }
        (self.device, self.queue) = (device, queue)
        func texture(_ width: Int, _ height: Int, _ format: MTLPixelFormat, mips: Bool = false, _ usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: mips)
            d.usage = usage
            return device.makeTexture(descriptor: d)
        }
        // A cell every 2 points, or a little more on a large screen.
        let cell = max(2, max(size.width, size.height) / 600)
        let w = Int(size.width / cell), h = Int(size.height / cell)
        func field(_ format: MTLPixelFormat) -> MTLTexture? { texture(w, h, format) }
        guard let air = field(.rg16Float), let airNext = field(.rg16Float), let fire = field(.rg16Float), let fireNext = field(.rg16Float),
              let press = field(.r16Float), let pressNext = field(.r16Float), let spins = field(.r16Float), let spreads = field(.r16Float),
              let mask = texture(Int(size.width), Int(size.height), .r8Unorm, mips: true, [.shaderRead]),
              let logo = texture(lit.width, lit.height, .bgra8Unorm, [.shaderRead]),
              let scene = texture(Int(size.width * scale), Int(size.height * scale), .rgba16Float, mips: true, [.shaderRead, .renderTarget]) else { return nil }
        (self.air, self.airNext, self.fire, self.fireNext, self.press, self.pressNext) = (air, airNext, fire, fireNext, press, pressNext)
        (self.spins, self.spreads, self.mask, self.logo, self.scene) = (spins, spreads, mask, logo, scene)

        do {
            var kernels: [String: MTLComputePipelineState] = [:]
            for name in ["advect", "spin", "curl", "spread", "relax", "settle", "moveEmbers"] {
                kernels[name] = try device.makeComputePipelineState(function: library.makeFunction(name: name)!)
            }
            self.kernels = kernels
            func drawing(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat, adding: Bool = false) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: vertex)
                d.fragmentFunction = library.makeFunction(name: fragment)
                let a = d.colorAttachments[0]!
                a.pixelFormat = format
                a.isBlendingEnabled = adding
                (a.sourceRGBBlendFactor, a.destinationRGBBlendFactor) = (.one, .one)
                (a.sourceAlphaBlendFactor, a.destinationAlphaBlendFactor) = (.one, .one)
                return try device.makeRenderPipelineState(descriptor: d)
            }
            flames = try drawing("wholeScreen", "flames", .rgba16Float)
            glowing = try drawing("emberPoint", "emberGlow", .rgba16Float, adding: true)
            finish = try drawing("wholeScreen", "finish", Self.format)
        } catch { return nil }

        func ember(at place: SIMD2<Float>, larger: Float = 0) -> Ember {
            // Many tiny, few small.
            let size = Float.random(in: 0...1)
            return Ember(place: place, radius: 0.26 + larger + 0.2 * size + 0.4 * size * size * size * size, depth: .random(in: 0.7...1.2), seed: .random(in: 0...1))
        }
        let inLetters = Self.scatter(Self.count, over: letters).map { ember(at: SIMD2(Float($0.x), Float($0.y))) }
        // The burst's, thrown out from the middle.
        let middle = SIMD2(Float(frame.midX), Float(frame.midY))
        let thrown: [Ember] = inLetters.isEmpty ? [] : (0..<Self.bursting).map { _ in
            let way = Float.random(in: 0..<2 * .pi), far = Float.random(in: 0...1)
            var e = ember(at: middle + SIMD2(cos(way), sin(way)) * 24 * far, larger: 0.25)
            e.speed = SIMD2(cos(way), sin(way)) * (250 + 800 * far * far)
            e.heat = .random(in: 0.8...1.4)
            return e
        }
        let start = inLetters + thrown
        guard !start.isEmpty,
              let embers = device.makeBuffer(bytes: start, length: MemoryLayout<Ember>.stride * start.count, options: .storageModeShared),
              let embersNext = device.makeBuffer(length: MemoryLayout<Ember>.stride * start.count, options: .storageModeShared) else { return nil }
        (self.embers, self.embersNext) = (embers, embersNext)
        now = Now(size: SIMD2(Float(size.width), Float(size.height)), middle: middle,
                  logo: SIMD4(Float(frame.minX), Float(frame.minY), Float(frame.width), Float(frame.height)),
                  across: SIMD2(Float(letters.map(\.frame.minX).min() ?? 0), Float(letters.map(\.frame.maxX).max() ?? 0)),
                  down: SIMD2(Float(letters.map(\.frame.minY).min() ?? 0), Float(letters.map(\.frame.maxY).max() ?? 0)), cell: Float(cell), embers: UInt32(start.count))

        fill(mask, letters: letters)
        fill(logo, with: lit)
        if let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: mask)
            for t in [air, fire, press] { clear(t) }
            blit.endEncoding()
            commands.commit()
        }
    }

    // MARK: - Running

    /// Moves the fire on to `time` (in seconds from the burst), then draws it into `target`.
    func draw(at time: Double, into target: MTLTexture, finally: (MTLCommandBuffer) -> Void = { _ in }) {
        guard let commands = queue.makeCommandBuffer() else { return }
        while now.time + Self.step <= Float(time) { advance(commands) }
        render(commands, target)
        finally(commands)
        commands.commit()
    }

    /// The embers as they are after all the steps so far.
    func embersNow() -> [Ember] {
        // Waits for them.
        let commands = queue.makeCommandBuffer()
        commands?.commit()
        commands?.waitUntilCompleted()
        let pointer = embers.contents().bindMemory(to: Ember.self, capacity: Int(now.embers))
        return Array(UnsafeBufferPointer(start: pointer, count: Int(now.embers)))
    }

    private func advance(_ commands: MTLCommandBuffer) {
        now.time += now.dt
        now.ground = 1 - simd_smoothstep(Float(Self.opens), Float(Self.opens) + 0.5, now.time)

        guard let e = commands.makeComputeCommandEncoder() else { return }
        run(e, "advect", [air, fire, mask, airNext, fireNext])
        swap(&air, &airNext)
        swap(&fire, &fireNext)
        run(e, "spin", [air, spins])
        run(e, "curl", [air, spins, airNext])
        swap(&air, &airNext)
        run(e, "spread", [air, fire, spreads])
        for _ in 0..<26 {
            run(e, "relax", [press, spreads, pressNext])
            swap(&press, &pressNext)
        }
        run(e, "settle", [air, press, airNext])
        swap(&air, &airNext)
        // Two smaller steps, so embers that collide don't pass through each other.
        var half = now
        half.dt /= 2
        for _ in 0..<2 {
            e.setComputePipelineState(kernels["moveEmbers"]!)
            e.setBuffer(embers, offset: 0, index: 0)
            e.setBuffer(embersNext, offset: 0, index: 1)
            e.setBytes(&half, length: MemoryLayout<Now>.stride, index: 2)
            e.setTexture(air, index: 0)
            e.dispatchThreads(MTLSize(width: Int(now.embers), height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            swap(&embers, &embersNext)
        }
        e.endEncoding()
    }

    private func run(_ e: MTLComputeCommandEncoder, _ name: String, _ textures: [MTLTexture]) {
        e.setComputePipelineState(kernels[name]!)
        e.setTextures(textures, range: 0..<textures.count)
        e.setBytes(&now, length: MemoryLayout<Now>.stride, index: 0)
        e.dispatchThreads(MTLSize(width: air.width, height: air.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    private func render(_ commands: MTLCommandBuffer, _ target: MTLTexture) {
        func pass(_ into: MTLTexture, _ draw: (MTLRenderCommandEncoder) -> Void) {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = into
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].storeAction = .store
            guard let e = commands.makeRenderCommandEncoder(descriptor: d) else { return }
            e.setVertexBytes(&now, length: MemoryLayout<Now>.stride, index: 1)
            e.setFragmentBytes(&now, length: MemoryLayout<Now>.stride, index: 0)
            draw(e)
            e.endEncoding()
        }
        pass(scene) { e in
            e.setRenderPipelineState(flames)
            e.setFragmentTextures([fire, logo], range: 0..<2)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.setRenderPipelineState(glowing)
            e.setVertexBuffer(embers, offset: 0, index: 0)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: Int(now.embers))
        }
        if let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: scene)
            blit.endEncoding()
        }
        pass(target) { e in
            e.setRenderPipelineState(finish)
            e.setFragmentTexture(scene, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    // MARK: - Pictures

    /// `count` places spread over the drawn parts of the letters.
    static func scatter(_ count: Int, over letters: [Letters]) -> [CGPoint] {
        let inside = letters.flatMap { drawn($0.picture, in: $0.frame) }
        guard !inside.isEmpty else { return [] }
        return (0..<count).map { _ in
            let p = inside.randomElement()!
            return CGPoint(x: p.x + .random(in: 0..<1), y: p.y + .random(in: 0..<1))
        }
    }

    /// The points of the picture that are drawn on, one for each point of its frame.
    private static func drawn(_ picture: CGImage, in frame: CGRect) -> [CGPoint] {
        let width = Int(frame.width), height = Int(frame.height)
        let alpha = pixels(width, height, each: 1, CGColorSpaceCreateDeviceGray(), .alphaOnly) {
            $0.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return alpha.indices.filter { alpha[$0] > 128 }.map {
            CGPoint(x: frame.minX + CGFloat($0 % width), y: frame.minY + CGFloat($0 / width))
        }
    }

    private static func pixels(_ width: Int, _ height: Int, each bytes: Int, _ space: CGColorSpace, _ alpha: CGImageAlphaInfo,
                               order: CGBitmapInfo = [], _ draw: (CGContext) -> Void) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * bytes)
        data.withUnsafeMutableBytes {
            if let c = CGContext(data: $0.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * bytes,
                                 space: space, bitmapInfo: alpha.rawValue | order.rawValue) { draw(c) }
        }
        return data
    }

    private func fill(_ mask: MTLTexture, letters: [Letters]) {
        let data = Self.pixels(mask.width, mask.height, each: 1, CGColorSpaceCreateDeviceGray(), .alphaOnly) { c in
            for l in letters {
                c.draw(l.picture, in: CGRect(x: l.frame.minX, y: CGFloat(mask.height) - l.frame.maxY, width: l.frame.width, height: l.frame.height))
            }
        }
        put(data, into: mask, each: 1)
    }

    private func fill(_ logo: MTLTexture, with lit: CGImage) {
        let data = Self.pixels(logo.width, logo.height, each: 4, CGColorSpace(name: CGColorSpace.sRGB)!, .premultipliedFirst, order: .byteOrder32Little) {
            $0.draw(lit, in: CGRect(x: 0, y: 0, width: logo.width, height: logo.height))
        }
        put(data, into: logo, each: 4)
    }

    private func clear(_ t: MTLTexture) { put([UInt8](repeating: 0, count: t.width * t.height * 4), into: t, each: t.pixelFormat == .r16Float ? 2 : 4) }

    private func put(_ data: [UInt8], into t: MTLTexture, each bytes: Int) {
        t.replace(region: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0, withBytes: data, bytesPerRow: t.width * bytes)
    }
}
