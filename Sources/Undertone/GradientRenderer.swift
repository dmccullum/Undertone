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

    private static let maximumDimension = 8_192
    private static let maximumPixelCount = 33_554_432
    private static let lookupTableSize = 2_048

    static func render(_ recipe: GradientRecipe, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension else {
            throw RenderError.invalidDimensions(width: width, height: height)
        }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount <= maximumPixelCount else {
            throw RenderError.imageTooLarge(width: width, height: height)
        }
        let minimumStops = recipe.mode == .magicSingle ? 1 : 2
        guard recipe.stops.count >= minimumStops else { throw RenderError.insufficientColorStops }

        let suppliedStops = recipe.stops.map(RenderStop.init)
        let stops = recipe.mode == .magicSingle
            ? magicSingleStops(base: suppliedStops[0], variation: recipe.colorArc, seed: recipe.seed)
            : suppliedStops
        let flow = clamp(recipe.flow, lower: 0, upper: 1)
        let softness = clamp(recipe.softness, lower: 0, upper: 1)
        let grain = clamp(recipe.grain, lower: 0, upper: 1)
        let grainCellSize = Int(clamp(recipe.grainSize, lower: 1, upper: 128).rounded())
        let angle = recipe.angleDegrees * .pi / 180
        let axisX = cos(angle), axisY = sin(angle)
        let crossX = -axisY, crossY = axisX
        let position = clamp(recipe.gradientPosition, lower: 0, upper: 1)
        let fadeWidth = clamp(recipe.fadeWidth, lower: 0.05, upper: 2)
        let centerX = clamp(recipe.centerX, lower: 0, upper: 1)
        let centerY = clamp(recipe.centerY, lower: 0, upper: 1)
        let softnessCore = 0.0025 + softness * softness * 0.30
        let phase = Double(recipe.seed % 10_000) / 10_000 * .pi * 2

        let palette = makePalette(
            stops: stops,
            magic: recipe.mode == .magicLinear || recipe.mode == .aurora,
            easing: recipe.easing,
            colorArc: recipe.colorArc,
            seed: recipe.seed
        )
        let xWarp = (0..<height).map { row -> Double in
            let y = normalizedCoordinate(row, count: height)
            return flow * 0.14 * (sin((y * 1.73 + 0.11) * .pi * 2) * 0.68 + sin((y * 3.91 + 0.63) * .pi * 2) * 0.32)
        }
        let yWarp = (0..<width).map { column -> Double in
            let x = normalizedCoordinate(column, count: width)
            return flow * 0.14 * (sin((x * 1.37 + 0.47) * .pi * 2) * 0.72 + sin((x * 3.23 + 0.19) * .pi * 2) * 0.28)
        }

        let byteCount = pixelCount * 4
        let storage = PixelStorage(byteCount: byteCount)
        DispatchQueue.concurrentPerform(iterations: height) { row in
            let y = normalizedCoordinate(row, count: height)
            let rowOffset = row * width * 4
            for column in 0..<width {
                let x = normalizedCoordinate(column, count: width)
                let color: RGB
                switch recipe.mode {
                case .organic, .magicSingle:
                    color = organicColor(stops: stops, x: x + xWarp[row], y: y + yWarp[column], softnessCore: softnessCore)
                case .linear, .magicLinear:
                    let coordinate = 0.5 + (x - 0.5) * axisX + (y - 0.5) * axisY
                    color = paletteColor(palette, at: 0.5 + (coordinate - position) / fadeWidth)
                case .radial:
                    let dx = x - centerX, dy = y - centerY
                    color = paletteColor(palette, at: sqrt(dx * dx + dy * dy) / fadeWidth)
                case .aurora:
                    let axis = 0.5 + (x - 0.5) * axisX + (y - 0.5) * axisY
                    let cross = (x - 0.5) * crossX + (y - 0.5) * crossY
                    let ribbon = sin(cross * .pi * 2.4 + phase) * 0.18 + sin(cross * .pi * 5.2 - phase * 0.7) * 0.055
                    color = paletteColor(palette, at: 0.5 + (axis + ribbon * flow - position) / fadeWidth)
                }
                let noise = grain == 0 ? 0 : grainNoise(x: column, y: row, cellSize: grainCellSize, seed: recipe.seed) * grain * 0.105
                let offset = rowOffset + column * 4
                storage.pointer[offset] = byte(color.red + noise)
                storage.pointer[offset + 1] = byte(color.green + noise)
                storage.pointer[offset + 2] = byte(color.blue + noise)
                storage.pointer[offset + 3] = 255
            }
        }

        let data = Data(bytes: storage.pointer, count: byteCount)
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

    private static func organicColor(stops: [RenderStop], x: Double, y: Double, softnessCore: Double) -> RGB {
        var weightTotal = 0.0, red = 0.0, green = 0.0, blue = 0.0
        for stop in stops {
            let dx = x - stop.x, dy = y - stop.y
            let distance = dx * dx + dy * dy + softnessCore
            let weight = 1 / (distance * distance)
            weightTotal += weight
            red += stop.color.red * weight
            green += stop.color.green * weight
            blue += stop.color.blue * weight
        }
        return RGB(red: red / weightTotal, green: green / weightTotal, blue: blue / weightTotal)
    }

    private static func makePalette(stops: [RenderStop], magic: Bool, easing: Double, colorArc: Double, seed: UInt64) -> [RGB] {
        let colors = stops.map(\.color)
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
            let color = lab.adjusted(lightness: spec.0, hue: spec.1, chromaScale: spec.2).rgb
            let wobble = sin(phase + Double(index) * 1.7) * 0.08
            return RenderStop(color: color, x: clamp(spec.3 + wobble, lower: 0.05, upper: 0.95), y: spec.4)
        }
    }

    private static func normalizedCoordinate(_ value: Int, count: Int) -> Double { count == 1 ? 0.5 : Double(value) / Double(count - 1) }
    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double { min(upper, max(lower, value.isFinite ? value : lower)) }
    private static func byte(_ value: Double) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
    private static func interpolate(_ start: Double, _ end: Double, by amount: Double) -> Double { start + (end - start) * amount }

    private static func grainNoise(x: Int, y: Int, cellSize: Int, seed: UInt64) -> Double {
        if cellSize == 1 { return hashNoise(x: x, y: y, seed: seed) }
        let cellX = x / cellSize, cellY = y / cellSize
        let fractionX = Double(x % cellSize) / Double(cellSize), fractionY = Double(y % cellSize) / Double(cellSize)
        let smoothX = fractionX * fractionX * (3 - 2 * fractionX), smoothY = fractionY * fractionY * (3 - 2 * fractionY)
        let top = interpolate(hashNoise(x: cellX, y: cellY, seed: seed), hashNoise(x: cellX + 1, y: cellY, seed: seed), by: smoothX)
        let bottom = interpolate(hashNoise(x: cellX, y: cellY + 1, seed: seed), hashNoise(x: cellX + 1, y: cellY + 1, seed: seed), by: smoothX)
        return interpolate(top, bottom, by: smoothY)
    }

    private static func hashNoise(x: Int, y: Int, seed: UInt64) -> Double {
        var value = seed
        value &+= UInt64(truncatingIfNeeded: x) &* 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(truncatingIfNeeded: y) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0) * 2 - 1
    }

    private struct RGB: Sendable { let red: Double; let green: Double; let blue: Double }

    private struct OKLab: Sendable {
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

    private struct RenderStop: Sendable {
        let color: RGB
        let x: Double
        let y: Double
        init(_ stop: ColorStop) {
            let value = UInt32(stop.hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
            color = RGB(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
            x = GradientRenderer.clamp(stop.x, lower: 0, upper: 1)
            y = GradientRenderer.clamp(stop.y, lower: 0, upper: 1)
        }
        init(color: RGB, x: Double, y: Double) { self.color = color; self.x = x; self.y = y }
    }

    private final class PixelStorage: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<UInt8>
        init(byteCount: Int) { pointer = .allocate(capacity: byteCount) }
        deinit { pointer.deallocate() }
    }
}
