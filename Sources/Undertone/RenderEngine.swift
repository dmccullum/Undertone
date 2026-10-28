import CoreGraphics
import Foundation

/// Picks the renderer for this Mac. The GPU draws the canvas, exports and thumbnails when this Mac's
/// GPU matches the CPU reference: on first use it renders a set of fixtures both ways and requires
/// every channel of every pixel within 2/255, the same gate the tests use. GPUs differ slightly in
/// how they compute `exp`, `cos` and `pow`, so the check runs on each Mac; one that doesn't pass stays
/// on the CPU. Either way, every Mac produces the same image within 2/255.
nonisolated enum RenderEngine {
    static let tolerance = 2

    /// The Metal renderer, or nil when this Mac has none or it didn't pass the self-test.
    static let metal: MetalRenderer? = {
        guard let renderer = MetalRenderer.shared, let worst = try? selfTest(renderer), worst <= tolerance else { return nil }
        return renderer
    }()

    static var usesGPU: Bool { metal != nil }

    static func render(_ recipe: GradientRecipe, width: Int, height: Int) throws -> CGImage {
        if let metal, let image = try? metal.render(recipe, width: width, height: height) { return image }
        return try GradientRenderer.render(recipe, width: width, height: height)
    }

    /// Renders every fixture with both renderers and returns the largest channel difference.
    static func selfTest(_ renderer: MetalRenderer) throws -> Int {
        var worst = 0
        for recipe in fixtures {
            let cpu = try pixels(GradientRenderer.render(recipe, width: 96, height: 128))
            let gpu = try pixels(renderer.render(recipe, width: 96, height: 128))
            guard cpu.count == gpu.count else { return .max }
            for index in cpu.indices { worst = max(worst, abs(Int(cpu[index]) - Int(gpu[index]))) }
        }
        return worst
    }

    /// One recipe per style plus the heaviest cases: grain, swirl, eight colors, a bent 4 × 4 mesh.
    static var fixtures: [GradientRecipe] {
        let stops = [
            ColorStop(hex: "E78670", x: 0.12, y: 0.18), ColorStop(hex: "6445A8", x: 0.82, y: 0.24),
            ColorStop(hex: "F2C66D", x: 0.31, y: 0.86), ColorStop(hex: "012169", x: 0.7, y: 0.7),
        ]
        let base = GradientRecipe(stops: stops, swirl: 0.4, grain: 0.3, grainSize: 2, seed: 8_675_309)
        var recipes = GradientMode.allCases.map { mode -> GradientRecipe in
            var recipe = base
            recipe.mode = mode
            return recipe
        }
        var crowded = base
        crowded.stops += ["FF006E", "3A86FF", "FFBE0B", "8338EC"].enumerated().map { ColorStop(hex: $1, x: 0.2 * Double($0 + 1), y: 0.5) }
        crowded.flow = 1
        crowded.softness = 0.1
        crowded.organicFlow = .pull
        recipes.append(crowded)
        var wave = base
        wave.organicFlow = .wave
        wave.flow = 1
        recipes.append(wave)
        var classic = base
        classic.organicFlow = .classic
        classic.flow = 0.8
        recipes.append(classic)
        var mesh = base
        mesh.mode = .mesh
        mesh.meshSize = 4
        mesh.softness = 1
        mesh.meshVertices = MeshGrid.seeded(size: 4, colors: stops.map(\.hex)).enumerated().map { index, vertex in
            var bent = vertex
            if (5...10).contains(index) { bent.x += 0.07; bent.y -= 0.05 }
            return bent
        }
        recipes.append(mesh)
        return recipes
    }

    private static func pixels(_ image: CGImage) throws -> [UInt8] {
        guard let data = image.dataProvider?.data else { throw CocoaError(.fileReadCorruptFile) }
        return [UInt8](data as Data)
    }
}
