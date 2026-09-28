import CoreGraphics
import Dispatch
import Foundation

enum GradientRenderer {
    enum RenderError: Error, Equatable {
        case invalidDimensions(width: Int, height: Int)
        case imageTooLarge(width: Int, height: Int)
        case insufficientColorStops
        case imageCreationFailed
    }

    static let maximumDimension = 8_192
    static let maximumPixelCount = 33_554_432
    static let lookupTableSize = 2_048
    /// Grain is sized relative to this reference (the preview's longest side), so it looks identical
    /// in the preview and the full-resolution export.
    static let grainReferenceSize = 1_280

    static func render(_ recipe: GradientRecipe, width: Int, height: Int) throws -> CGImage {
        let scene = try Scene(recipe, width: width, height: height)
        let byteCount = width * height * 4
        let storage = PixelStorage(byteCount: byteCount)
        DispatchQueue.concurrentPerform(iterations: height) { row in
            let rowOffset = row * width * 4
            for column in 0..<width {
                let color = scene.color(column: column, row: row)
                let noise = scene.grainNoise(column: column, row: row)
                let offset = rowOffset + column * 4
                storage.pointer[offset] = byte(color.red + noise + dither(column: column, row: row, channel: 0))
                storage.pointer[offset + 1] = byte(color.green + noise + dither(column: column, row: row, channel: 1))
                storage.pointer[offset + 2] = byte(color.blue + noise + dither(column: column, row: row, channel: 2))
                storage.pointer[offset + 3] = 255
            }
        }
        return try image(from: Data(bytes: storage.pointer, count: byteCount), width: width, height: height)
    }

    /// An invisible dither: a triangular ±1/255 offset per channel before 8-bit rounding, so long, dark
    /// ramps (Coldwell Banker Blue into Midnight) break up instead of stepping into visible bands. It
    /// never depends on the seed, and the Metal kernel computes the identical value.
    static func dither(column: Int, row: Int, channel: UInt32) -> Double {
        func unit(_ salt: UInt32) -> Double {
            Double(hash32(UInt32(truncatingIfNeeded: column) &+ hash32(UInt32(truncatingIfNeeded: row) &+ hash32(0x5EED_0000 &+ salt))) >> 8) / 16_777_216
        }
        return (unit(channel * 2) + unit(channel * 2 + 1) - 1) / 255
    }

    /// Wraps 8-bit RGBA pixels as an sRGB image.
    static func image(from data: Data, width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { throw RenderError.imageCreationFailed }
        return image
    }

    /// Everything a recipe works out to at one output size. The CPU renderer and the Metal renderer
    /// both start from the same scene, so only the per-pixel math exists twice (here and in
    /// `MetalShaders`), and the two stay in step.
    struct Scene: Sendable {
        static let emptyColor = RGB(red: 0.13, green: 0.14, blue: 0.17)

        let width: Int, height: Int
        let mode: GradientMode
        let hasColors: Bool
        // Texture
        let grain: Double
        let grainCellSize: Int
        let grainSeed: UInt32
        // Linear, Glow and Aurora read a lookup table along one coordinate.
        let palette: [RGB]
        let lineStartX: Double, lineStartY: Double, lineDX: Double, lineDY: Double, lineLengthSquared: Double
        let centerX: Double, centerY: Double, fadeWidth: Double
        let axisX: Double, axisY: Double, crossX: Double, crossY: Double, position: Double, flow: Double, phase: Double
        // Tonal
        let tonalStops: [RenderStop]
        let softnessCore: Double
        let swirlStrength: Double, swirlCenterX: Double, swirlCenterY: Double
        let xWarp: [Double], yWarp: [Double]
        // Organic and Mesh
        let organic: OrganicField?
        let mesh: MeshRaster?

        init(_ recipe: GradientRecipe, width: Int, height: Int) throws {
            guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension else {
                throw RenderError.invalidDimensions(width: width, height: height)
            }
            let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
            guard !overflow, pixelCount <= maximumPixelCount else {
                throw RenderError.imageTooLarge(width: width, height: height)
            }
            self.width = width
            self.height = height
            mode = recipe.mode
            let suppliedStops = recipe.stops.map(RenderStop.init)
            // A mesh has color once any point is painted, whether or not the tray has colors.
            hasColors = recipe.mode == .mesh ? MeshGrid.vertices(for: recipe).contains { !$0.hex.isEmpty } : !suppliedStops.isEmpty
            let stops = recipe.mode == .tonal && hasColors
                ? magicSingleStops(base: suppliedStops[0], variation: recipe.colorArc, seed: recipe.seed)
                : suppliedStops
            let flow = clamp(recipe.flow, lower: 0, upper: 1)
            let softness = clamp(recipe.softness, lower: 0, upper: 1)
            self.flow = flow
            grain = recipe.textureEnabled ? clamp(recipe.grain, lower: 0, upper: 1) : 0
            grainCellSize = Int(clamp(recipe.grainSize, lower: 1, upper: 128).rounded())
            grainSeed = UInt32(truncatingIfNeeded: recipe.seed ^ (recipe.seed >> 32))
            let angle = recipe.angleDegrees * .pi / 180
            axisX = cos(angle); axisY = sin(angle)
            crossX = -axisY; crossY = axisX
            position = clamp(recipe.gradientPosition, lower: 0, upper: 1)
            fadeWidth = clamp(recipe.fadeWidth, lower: 0.05, upper: 6)
            // Linear runs from start to end; project each pixel onto that line for its palette position.
            lineStartX = recipe.startX; lineStartY = recipe.startY
            lineDX = recipe.endX - recipe.startX; lineDY = recipe.endY - recipe.startY
            lineLengthSquared = max(1e-9, lineDX * lineDX + lineDY * lineDY)
            centerX = clamp(recipe.centerX, lower: -1, upper: 2)
            centerY = clamp(recipe.centerY, lower: -1, upper: 2)
            // Swirl: a vortex domain-warp for Tonal. Strength eases in; the seed picks the center
            // and spin direction, so shuffling reshuffles the swirl too.
            let swirlAmount = clamp(recipe.swirl, lower: 0, upper: 1)
            // The twist compresses the field where it rotates hardest, which reads as harder edges; widen
            // the blend core with swirl so the softness setting keeps its dreaminess.
            softnessCore = (0.0025 + softness * softness * 1.20) * (1 + swirlAmount * 6.0)
            let phase = Double(recipe.seed % 10_000) / 10_000 * .pi * 2
            self.phase = phase
            swirlStrength = swirlAmount * swirlAmount * 8.0 * ((recipe.seed & 2) == 0 ? 1.0 : -1.0)
            swirlCenterX = 0.5 + (seedUnit(recipe.seed, salt: 91) - 0.5) * 0.5
            swirlCenterY = 0.5 + (seedUnit(recipe.seed, salt: 92) - 0.5) * 0.5
            tonalStops = recipe.mode == .tonal ? stops : []

            organic = recipe.mode == .organic && hasColors ? OrganicField(recipe: recipe, stops: suppliedStops) : nil
            mesh = recipe.mode == .mesh && hasColors ? MeshRaster(recipe: recipe, width: width, height: height) : nil
            let usesPalette = recipe.mode == .linear || recipe.mode == .aurora || recipe.mode == .radial
            palette = hasColors && usesPalette
                ? makePalette(
                    stops: stops,
                    magic: recipe.mode == .linear || recipe.mode == .aurora,
                    smooth: recipe.mode == .linear && recipe.smoothBlend,
                    easing: recipe.easing,
                    colorArc: recipe.colorArc,
                    seed: recipe.seed
                )
                : [Self.emptyColor]
            // The seed shifts Tonal's flow field phases, so it can be reshuffled without changing color.
            let tonal = recipe.mode == .tonal
            xWarp = tonal ? (0..<height).map { row -> Double in
                let y = normalizedCoordinate(row, count: height)
                return flow * 0.14 * (sin((y * 1.73 + 0.11) * .pi * 2 + phase) * 0.68 + sin((y * 3.91 + 0.63) * .pi * 2 + phase * 1.7) * 0.32)
            } : []
            yWarp = tonal ? (0..<width).map { column -> Double in
                let x = normalizedCoordinate(column, count: width)
                return flow * 0.14 * (sin((x * 1.37 + 0.47) * .pi * 2 + phase * 1.3) * 0.72 + sin((x * 3.23 + 0.19) * .pi * 2 + phase * 0.6) * 0.28)
            } : []
        }

        func color(column: Int, row: Int) -> RGB {
            guard hasColors else { return Self.emptyColor }
            let x = normalizedCoordinate(column, count: width), y = normalizedCoordinate(row, count: height)
            switch mode {
            case .organic:
                return organic?.color(x: x, y: y) ?? Self.emptyColor
            case .mesh:
                return mesh?.color(x: x, y: y, column: column, row: row) ?? Self.emptyColor
            case .tonal:
                var sx = x + xWarp[row]
                var sy = y + yWarp[column]
                if swirlStrength != 0 {
                    let dx = sx - swirlCenterX, dy = sy - swirlCenterY
                    let twist = swirlStrength * exp(-(dx * dx + dy * dy) * 3.2)
                    let cosT = cos(twist), sinT = sin(twist)
                    sx = swirlCenterX + dx * cosT - dy * sinT
                    sy = swirlCenterY + dx * sinT + dy * cosT
                }
                return tonalColor(stops: tonalStops, x: sx, y: sy, softnessCore: softnessCore)
            case .linear:
                let projection = ((x - lineStartX) * lineDX + (y - lineStartY) * lineDY) / lineLengthSquared
                return paletteColor(palette, at: projection)
            case .radial:
                let dx = x - centerX, dy = y - centerY
                return paletteColor(palette, at: sqrt(dx * dx + dy * dy) / fadeWidth)
            case .aurora:
                let axis = 0.5 + (x - 0.5) * axisX + (y - 0.5) * axisY
                let cross = (x - 0.5) * crossX + (y - 0.5) * crossY
                let ribbon = sin(cross * .pi * 2.4 + phase) * 0.18 + sin(cross * .pi * 5.2 - phase * 0.7) * 0.055
                return paletteColor(palette, at: 0.5 + (axis + ribbon * flow - position) / fadeWidth)
            }
        }

        /// Monochrome film grain, added equally to each channel. It's sampled in a fixed 1280-pixel
        /// reference space (integer math, so every renderer lands on the same cell) and looks the same
        /// in the preview and a full-size export.
        func grainNoise(column: Int, row: Int) -> Double {
            guard grain > 0 else { return 0 }
            let longSide = max(width, height, 1)
            let x = column * grainReferenceSize / longSide, y = row * grainReferenceSize / longSide
            return GradientRenderer.grainNoise(x: x, y: y, cellSize: grainCellSize, seed: grainSeed) * grain * 0.105
        }
    }

    /// Tonal's blend: an inverse-square field of its derived tones, averaged in RGB.
    private static func tonalColor(stops: [RenderStop], x: Double, y: Double, softnessCore: Double) -> RGB {
        var weightTotal = 0.0, red = 0.0, green = 0.0, blue = 0.0
        for stop in stops {
            let dx = x - stop.x, dy = y - stop.y
            let distance = dx * dx + dy * dy + softnessCore
            let weight = stop.weight / (distance * distance)
            weightTotal += weight
            red += stop.color.red * weight
            green += stop.color.green * weight
            blue += stop.color.blue * weight
        }
        return RGB(red: red / weightTotal, green: green / weightTotal, blue: blue / weightTotal)
    }

    /// Organic: color that flows like ink in water. The canvas is bent by a fractal noise field that is
    /// itself bent by noise (nested domain warping), so borders curl into ribbons and tendrils in every
    /// direction; the points only set where each color roughly lives. Blending is in OKLab with lost
    /// saturation partly restored, so mixes stay vivid. Flow sets how far the color travels, Softness
    /// how wide the blends are, Swirl adds a vortex, and every seed is its own marbling.
    struct OrganicField: Sendable {
        static let octaves = 3

        let labs: [OKLab]
        let chromas: [Double]
        let xs: [Double], ys: [Double], weights: [Double]
        let core: Double
        let flowAmount: Double
        /// How much each finer octave keeps: softness smooths the fine detail out of the flow.
        let persistence: Double
        let noiseSeed: UInt32
        let swirlStrength: Double, swirlCenterX: Double, swirlCenterY: Double

        init(recipe: GradientRecipe, stops: [RenderStop]) {
            let labs = stops.map { OKLab($0.color) }
            self.labs = labs
            chromas = labs.map { sqrt($0.a * $0.a + $0.b * $0.b) }
            xs = stops.map(\.x); ys = stops.map(\.y); weights = stops.map(\.weight)
            let softness = GradientRenderer.clamp(recipe.softness, lower: 0, upper: 1)
            core = 0.0015 + softness * softness * 0.4
            flowAmount = GradientRenderer.clamp(recipe.flow, lower: 0, upper: 1) * 0.5
            persistence = 0.42 - softness * 0.22
            noiseSeed = UInt32(truncatingIfNeeded: recipe.seed ^ (recipe.seed >> 32)) &+ 0x0A11_CE00
            let swirl = GradientRenderer.clamp(recipe.swirl, lower: 0, upper: 1)
            swirlStrength = swirl * swirl * 8.0 * ((recipe.seed & 2) == 0 ? 1.0 : -1.0)
            swirlCenterX = 0.5 + (GradientRenderer.seedUnit(recipe.seed, salt: 91) - 0.5) * 0.5
            swirlCenterY = 0.5 + (GradientRenderer.seedUnit(recipe.seed, salt: 92) - 0.5) * 0.5
        }

        /// Smooth value noise in -1...1 on an integer-hashed lattice (quintic fade, so no creases).
        static func noise(_ x: Double, _ y: Double, _ seed: UInt32) -> Double {
            let cellX = floor(x), cellY = floor(y)
            let fx = x - cellX, fy = y - cellY
            let ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10), uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
            let ix = Int(cellX), iy = Int(cellY)
            let a = GradientRenderer.hashNoise(x: ix, y: iy, seed: seed), b = GradientRenderer.hashNoise(x: ix + 1, y: iy, seed: seed)
            let c = GradientRenderer.hashNoise(x: ix, y: iy + 1, seed: seed), d = GradientRenderer.hashNoise(x: ix + 1, y: iy + 1, seed: seed)
            return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
        }

        /// Fractal noise: octaves at doubling frequency, each rotated so no lattice direction shows.
        static func fbm(_ x: Double, _ y: Double, _ seed: UInt32, persistence: Double) -> Double {
            var px = x, py = y, amplitude = 0.6, total = 0.0
            for octave in 0..<octaves {
                total += amplitude * noise(px, py, seed &+ UInt32(octave))
                let rx = 0.8 * px - 0.6 * py, ry = 0.6 * px + 0.8 * py
                px = rx * 2.03 + 1.7; py = ry * 2.03 + 9.2
                amplitude *= persistence
            }
            return total
        }

        func color(x: Double, y: Double) -> RGB {
            var px = x, py = y
            if flowAmount > 0 {
                // Nested warp: q bends the space r is sampled in, and r bends the canvas.
                let bx = x * 1.35, by = y * 1.35, p = persistence
                let qx = Self.fbm(bx, by, noiseSeed, persistence: p), qy = Self.fbm(bx + 5.2, by + 1.3, noiseSeed &+ 17, persistence: p)
                let rx = Self.fbm(bx + 2.6 * qx + 1.7, by + 2.6 * qy + 9.2, noiseSeed &+ 31, persistence: p)
                let ry = Self.fbm(bx + 2.6 * qx + 8.3, by + 2.6 * qy + 2.8, noiseSeed &+ 47, persistence: p)
                px += rx * flowAmount
                py += ry * flowAmount
            }
            if swirlStrength != 0 {
                let dx = px - swirlCenterX, dy = py - swirlCenterY
                let twist = swirlStrength * exp(-(dx * dx + dy * dy) * 3.2)
                let cosT = cos(twist), sinT = sin(twist)
                px = swirlCenterX + dx * cosT - dy * sinT
                py = swirlCenterY + dx * sinT + dy * cosT
            }
            var total = 0.0, lightness = 0.0, a = 0.0, b = 0.0, chroma = 0.0
            for index in xs.indices {
                let dx = px - xs[index], dy = py - ys[index]
                let distance = dx * dx + dy * dy + core
                let weight = weights[index] / (distance * distance)
                total += weight
                lightness += labs[index].lightness * weight
                a += labs[index].a * weight
                b += labs[index].b * weight
                chroma += chromas[index] * weight
            }
            a /= total; b /= total
            // Averaging hues cancels saturation; give back part of what the mix lost (capped).
            let mixed = sqrt(a * a + b * b)
            if mixed > 1e-4 {
                let restore = 1 + (min(chroma / total / mixed, 1.8) - 1) * 0.6
                a *= restore; b *= restore
            }
            return OKLab(lightness: lightness / total, a: a, b: b).rgb
        }
    }

    /// Mesh: a true gradient mesh. The tray colors sit on a grid of points and a Catmull-Rom surface
    /// in OKLab runs smoothly through them. Moving a point bends the grid, so transitions follow curved,
    /// directional seams. The surface is cut into small triangles; each pixel interpolates the one it
    /// falls in (the last one drawn wins where a fold overlaps).
    struct MeshRaster: Sendable {
        static let tileSize = 16
        static let subdivisions = 24

        let samples: Int
        let px: [Double], py: [Double]
        let lightness: [Double], aChannel: [Double], bChannel: [Double]
        let triangles: [Int32]
        let tiles: [[Int32]]
        let tileColumns: Int, tileRows: Int
        let scaleX: Double, scaleY: Double

        init(recipe: GradientRecipe, width: Int, height: Int) {
            let size = MeshGrid.clampedSize(recipe.meshSize)
            let vertices = MeshGrid.vertices(for: recipe)
            let labs = vertices.map { vertex -> OKLab in
                guard Hex.normalized(vertex.hex) != nil else { return OKLab(Scene.emptyColor) }
                let rgb = Hex.components(vertex.hex)
                return OKLab(RGB(red: rgb.red, green: rgb.green, blue: rgb.blue))
            }
            let samples = (size - 1) * Self.subdivisions + 1
            // Softness: the lower half sets how long each color holds around its point (crisp seams
            // up to a classic mesh gradient that runs exactly through its points); the upper half
            // eases into a blurred B-spline for a hazy, dreamy blend.
            let softness = GradientRenderer.clamp(recipe.softness, lower: 0, upper: 1)
            let crisp = min(1, softness / 0.5), dreamy = max(0, (softness - 0.5) / 0.5)
            let tension = 0.6 + crisp * 0.4
            let sharpness = 1 + (1 - crisp) * (1 - crisp) * 0.45
            func channel(_ values: [Double]) -> [Double] {
                MeshGrid.sampledSurface(MeshGrid.smoothed(values, size: size, amount: dreamy * 0.3), size: size, samples: samples, tension: tension, sharpness: sharpness, approximation: dreamy, extrapolate: false)
            }
            self.samples = samples
            scaleX = Double(max(width - 1, 1)); scaleY = Double(max(height - 1, 1))
            px = MeshGrid.sampledSurface(vertices.map(\.x), size: size, samples: samples, monotone: true).map { $0 * Double(max(width - 1, 1)) }
            py = MeshGrid.sampledSurface(vertices.map(\.y), size: size, samples: samples, monotone: true).map { $0 * Double(max(height - 1, 1)) }
            lightness = channel(labs.map(\.lightness))
            aChannel = channel(labs.map(\.a))
            bChannel = channel(labs.map(\.b))

            var triangles: [Int32] = []
            triangles.reserveCapacity((samples - 1) * (samples - 1) * 6)
            for row in 0..<(samples - 1) {
                for column in 0..<(samples - 1) {
                    let a = Int32(row * samples + column), b = a + 1, c = a + Int32(samples), d = c + 1
                    triangles += [a, b, d, a, d, c]
                }
            }
            self.triangles = triangles
            tileColumns = (width + Self.tileSize - 1) / Self.tileSize
            tileRows = (height + Self.tileSize - 1) / Self.tileSize
            var tiles = [[Int32]](repeating: [], count: tileColumns * tileRows)
            let px = self.px, py = self.py
            for triangle in 0..<(triangles.count / 3) {
                let a = Int(triangles[triangle * 3]), b = Int(triangles[triangle * 3 + 1]), c = Int(triangles[triangle * 3 + 2])
                let lowX = min(px[a], px[b], px[c]) - 1, highX = max(px[a], px[b], px[c]) + 1
                let lowY = min(py[a], py[b], py[c]) - 1, highY = max(py[a], py[b], py[c]) + 1
                let minColumn = max(0, Int(max(0, lowX)) / Self.tileSize), maxColumn = min(tileColumns - 1, Int(max(0, highX)) / Self.tileSize)
                let minRow = max(0, Int(max(0, lowY)) / Self.tileSize), maxRow = min(tileRows - 1, Int(max(0, highY)) / Self.tileSize)
                guard minColumn <= maxColumn, minRow <= maxRow else { continue }
                for tileRow in minRow...maxRow {
                    for tileColumn in minColumn...maxColumn { tiles[tileRow * tileColumns + tileColumn].append(Int32(triangle)) }
                }
            }
            self.tiles = tiles
        }

        func color(x: Double, y: Double, column: Int, row: Int) -> RGB {
            let pointX = x * scaleX, pointY = y * scaleY
            let tile = tiles[min(tileRows - 1, row / Self.tileSize) * tileColumns + min(tileColumns - 1, column / Self.tileSize)]
            for triangle in tile.reversed() {
                let base = Int(triangle) * 3
                let a = Int(triangles[base]), b = Int(triangles[base + 1]), c = Int(triangles[base + 2])
                let e0x = px[b] - px[a], e0y = py[b] - py[a]
                let e1x = px[c] - px[a], e1y = py[c] - py[a]
                let area = e0x * e1y - e1x * e0y
                guard abs(area) > 1e-12 else { continue }
                let qx = pointX - px[a], qy = pointY - py[a]
                let wb = (qx * e1y - e1x * qy) / area
                let wc = (e0x * qy - qx * e0y) / area
                let wa = 1 - wb - wc
                let tolerance = -1e-6
                guard wa >= tolerance, wb >= tolerance, wc >= tolerance else { continue }
                return OKLab(
                    lightness: wa * lightness[a] + wb * lightness[b] + wc * lightness[c],
                    a: wa * aChannel[a] + wb * aChannel[b] + wc * aChannel[c],
                    b: wa * bChannel[a] + wb * bChannel[b] + wc * bChannel[c]
                ).rgb
            }
            // Numerical slivers along a seam: fall back to the nearest surface sample.
            var nearest = 0, best = Double.greatestFiniteMagnitude
            for index in px.indices {
                let dx = px[index] - pointX, dy = py[index] - pointY
                let distance = dx * dx + dy * dy
                if distance < best { best = distance; nearest = index }
            }
            return OKLab(lightness: lightness[nearest], a: aChannel[nearest], b: bChannel[nearest]).rgb
        }
    }

    private static func makePalette(stops: [RenderStop], magic: Bool, smooth: Bool = false, easing: Double, colorArc: Double, seed: UInt64) -> [RGB] {
        let colors = stops.map(\.color)
        guard let first = colors.first else { return [] }
        guard colors.count > 1 else { return Array(repeating: first, count: lookupTableSize) }
        if smooth { return smoothPalette(colors) }
        let ease = clamp(easing, lower: 0, upper: 1)
        let arc = clamp(colorArc, lower: 0, upper: 1)
        return (0..<lookupTableSize).map { index in
            let t = Double(index) / Double(lookupTableSize - 1)
            let scaled = t * Double(colors.count - 1)
            let segment = min(colors.count - 2, Int(scaled))
            let raw = scaled - Double(segment)
            let smooth = raw * raw * (3 - 2 * raw)
            let amount = interpolate(raw, smooth, by: ease)
            if magic {
                let sign = ((UInt64(segment) &+ seed) & 1) == 0 ? 1.0 : -1.0
                return magicInterpolate(colors[segment], colors[segment + 1], by: amount, arc: arc * sign)
            }
            return RGB(
                red: interpolate(colors[segment].red, colors[segment + 1].red, by: amount),
                green: interpolate(colors[segment].green, colors[segment + 1].green, by: amount),
                blue: interpolate(colors[segment].blue, colors[segment + 1].blue, by: amount)
            )
        }
    }

    /// A rounded blend that runs a Catmull-Rom spline through the colors in OKLab, so transitions
    /// have no sharp corners at the stops — softer than straight segment-to-segment interpolation.
    private static func smoothPalette(_ colors: [RGB]) -> [RGB] {
        let labs = colors.map(OKLab.init)
        let count = labs.count
        return (0..<lookupTableSize).map { index in
            let scaled = Double(index) / Double(lookupTableSize - 1) * Double(count - 1)
            let segment = min(count - 2, Int(scaled))
            let u = scaled - Double(segment)
            let c0 = labs[max(0, segment - 1)]
            let c1 = labs[segment]
            let c2 = labs[segment + 1]
            let c3 = labs[min(count - 1, segment + 2)]
            return OKLab(
                lightness: catmullRom(c0.lightness, c1.lightness, c2.lightness, c3.lightness, u),
                a: catmullRom(c0.a, c1.a, c2.a, c3.a, u),
                b: catmullRom(c0.b, c1.b, c2.b, c3.b, u)
            ).rgb
        }
    }

    private static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ u: Double) -> Double {
        let u2 = u * u, u3 = u2 * u
        return 0.5 * (2 * p1 + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
    }

    private static func paletteColor(_ palette: [RGB], at amount: Double) -> RGB {
        palette[Int((clamp(amount, lower: 0, upper: 1) * Double(palette.count - 1)).rounded())]
    }

    private static func magicInterpolate(_ start: RGB, _ end: RGB, by amount: Double, arc: Double) -> RGB {
        let first = OKLab(start), second = OKLab(end)
        let curve = sin(amount * .pi)
        let da = second.a - first.a, db = second.b - first.b
        let length = max(0.0001, sqrt(da * da + db * db))
        let arcAmount = arc * 0.055 * curve
        return OKLab(
            lightness: interpolate(first.lightness, second.lightness, by: amount) + abs(arc) * 0.025 * curve,
            a: interpolate(first.a, second.a, by: amount) - db / length * arcAmount,
            b: interpolate(first.b, second.b, by: amount) + da / length * arcAmount
        ).rgb
    }

    private static func magicSingleStops(base: RenderStop, variation: Double, seed: UInt64) -> [RenderStop] {
        let strength = 0.25 + clamp(variation, lower: 0, upper: 1) * 0.75
        let lab = OKLab(base.color)
        let phase = Double(seed % 10_000) / 10_000 * .pi * 2
        let specifications: [(Double, Double, Double, Double, Double)] = [
            (-0.24 * strength, -0.22 * strength, 1.08, 0.14, 0.18),
            (0.22 * strength, 0.12 * strength, 0.72, 0.82, 0.20),
            (0, 0, 1, 0.25, 0.82),
            (-0.09 * strength, 0.34 * strength, 1.16, 0.80, 0.78),
        ]
        return specifications.enumerated().map { index, spec in
            let positionX = seedUnit(seed, salt: UInt64(index * 2 + 1))
            let positionY = seedUnit(seed, salt: UInt64(index * 2 + 2))
            let tone = seedUnit(seed, salt: UInt64(index + 11))
            let hue = spec.1 + (tone - 0.5) * 0.34 * strength
            let lightness = spec.0 + (positionY - 0.5) * 0.13 * strength
            let chroma = spec.2 * (0.84 + tone * 0.32)
            let color = lab.adjusted(lightness: lightness, hue: hue, chromaScale: chroma).rgb
            let x = spec.3 + (positionX - 0.5) * 0.34 + sin(phase + Double(index) * 1.7) * 0.06
            let y = spec.4 + (positionY - 0.5) * 0.28 + cos(phase + Double(index) * 1.3) * 0.05
            return RenderStop(color: color, x: clamp(x, lower: 0.05, upper: 0.95), y: clamp(y, lower: 0.05, upper: 0.95))
        }
    }

    static func normalizedCoordinate(_ value: Int, count: Int) -> Double { count == 1 ? 0.5 : Double(value) / Double(count - 1) }
    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double { min(upper, max(lower, value.isFinite ? value : lower)) }
    /// Rounds half up, the same formula the Metal kernel uses.
    static func byte(_ value: Double) -> UInt8 { UInt8((min(1, max(0, value)) * 255 + 0.5).rounded(.down)) }
    private static func interpolate(_ start: Double, _ end: Double, by amount: Double) -> Double { start + (end - start) * amount }

    private static func grainNoise(x: Int, y: Int, cellSize: Int, seed: UInt32) -> Double {
        if cellSize == 1 { return hashNoise(x: x, y: y, seed: seed) }
        let cellX = x / cellSize, cellY = y / cellSize
        let fractionX = Double(x % cellSize) / Double(cellSize), fractionY = Double(y % cellSize) / Double(cellSize)
        let smoothX = fractionX * fractionX * (3 - 2 * fractionX), smoothY = fractionY * fractionY * (3 - 2 * fractionY)
        let top = interpolate(hashNoise(x: cellX, y: cellY, seed: seed), hashNoise(x: cellX + 1, y: cellY, seed: seed), by: smoothX)
        let bottom = interpolate(hashNoise(x: cellX, y: cellY + 1, seed: seed), hashNoise(x: cellX + 1, y: cellY + 1, seed: seed), by: smoothX)
        return interpolate(top, bottom, by: smoothY)
    }

    /// A 32-bit integer hash (lowbias32) of a grain cell, as a value in -1...1. It's 32-bit so the GPU
    /// computes exactly the same value; the top 24 bits convert to a float without rounding.
    static func hashNoise(x: Int, y: Int, seed: UInt32) -> Double {
        let value = hash32(UInt32(truncatingIfNeeded: x) &+ hash32(UInt32(truncatingIfNeeded: y) &+ hash32(seed)))
        return Double(value >> 8) / 16_777_216 * 2 - 1
    }

    static func hash32(_ input: UInt32) -> UInt32 {
        var value = input
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return value
    }

    private static func seedUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed &+ salt &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    struct RGB: Sendable { let red: Double; let green: Double; let blue: Double }

    struct OKLab: Sendable {
        let lightness: Double
        let a: Double
        let b: Double

        init(lightness: Double, a: Double, b: Double) { self.lightness = lightness; self.a = a; self.b = b }
        init(_ color: RGB) {
            let red = Self.linear(color.red), green = Self.linear(color.green), blue = Self.linear(color.blue)
            let lRoot = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
            let mRoot = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
            let sRoot = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
            lightness = 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot
            a = 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot
            b = 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        }
        func adjusted(lightness offset: Double, hue: Double, chromaScale: Double) -> OKLab {
            let chroma = sqrt(a * a + b * b) * chromaScale
            let angle = atan2(b, a) + hue
            return OKLab(lightness: GradientRenderer.clamp(lightness + offset, lower: 0.03, upper: 0.98), a: cos(angle) * chroma, b: sin(angle) * chroma)
        }
        var rgb: RGB {
            let lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b
            let mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b
            let sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b
            let l = lRoot * lRoot * lRoot, m = mRoot * mRoot * mRoot, s = sRoot * sRoot * sRoot
            return RGB(
                red: Self.srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                green: Self.srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                blue: Self.srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
            )
        }
        private static func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        private static func srgb(_ value: Double) -> Double {
            let converted = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(max(0, value), 1 / 2.4) - 0.055
            return GradientRenderer.clamp(converted, lower: 0, upper: 1)
        }
    }

    struct RenderStop: Sendable {
        let color: RGB
        let x: Double
        let y: Double
        let weight: Double
        init(_ stop: ColorStop) {
            let value = UInt32(stop.hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
            color = RGB(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
            x = GradientRenderer.clamp(stop.x, lower: 0, upper: 1)
            y = GradientRenderer.clamp(stop.y, lower: 0, upper: 1)
            weight = GradientRenderer.clamp(stop.weight, lower: 0.05, upper: 4)
        }
        init(color: RGB, x: Double, y: Double, weight: Double = 1) { self.color = color; self.x = x; self.y = y; self.weight = weight }
    }

    private final class PixelStorage: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<UInt8>
        init(byteCount: Int) { pointer = .allocate(capacity: byteCount) }
        deinit { pointer.deallocate() }
    }
}
