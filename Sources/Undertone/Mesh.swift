import Foundation

/// One control point of the Mesh style's grid. Each point owns its color, like a mesh fill in a
/// design tool. Positions are fractions of the canvas; an empty `hex` is an unpainted point.
nonisolated struct MeshVertex: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var hex: String = ""
}

/// How mesh points were saved before they owned their colors (recipe version 4): a pinned tray color
/// or none, meaning the automatic fill.
nonisolated struct LegacyMeshVertex: Decodable {
    var x: Double
    var y: Double
    var hex: String?
    var stopID: UUID?
}

/// Geometry for the Mesh style: a square grid of points, row by row from the top left, joined by a
/// Catmull-Rom surface so the grid bends smoothly when a point moves. The renderer and the canvas
/// handles share these functions, so the grid lines on screen follow the rendered seams.
nonisolated enum MeshGrid {
    static let sizes = [3, 4]

    static func clampedSize(_ size: Int) -> Int { min(4, max(3, size)) }

    static func regular(size: Int) -> [MeshVertex] {
        let last = Double(size - 1)
        return (0..<size * size).map { MeshVertex(x: Double($0 % size) / last, y: Double($0 / size) / last) }
    }

    /// The recipe's points. Until the mesh is edited none are stored, and an even grid is seeded from
    /// the gradient's colors.
    static func vertices(for recipe: GradientRecipe) -> [MeshVertex] {
        let size = clampedSize(recipe.meshSize)
        return recipe.meshVertices.count == size * size ? recipe.meshVertices : seeded(size: size, colors: recipe.stops.map(\.hex))
    }

    /// An even grid painted with `colors` by the automatic fill.
    static func seeded(size: Int, colors: [String]) -> [MeshVertex] {
        regular(size: size).enumerated().map { index, vertex in
            var painted = vertex
            if !colors.isEmpty { painted.hex = colors[automaticStopIndex(at: index, size: size, count: colors.count)] }
            return painted
        }
    }

    /// Resolves points saved before they owned their colors: a pinned tray color, else the automatic fill.
    static func resolved(_ legacy: [LegacyMeshVertex], size: Int, stops: [ColorStop]) -> [MeshVertex] {
        legacy.enumerated().map { index, vertex in
            var hex = vertex.hex ?? ""
            if hex.isEmpty, !stops.isEmpty {
                hex = stops.first { $0.id == vertex.stopID }?.hex ?? stops[automaticStopIndex(at: index, size: size, count: stops.count)].hex
            }
            return MeshVertex(x: vertex.x, y: vertex.y, hex: hex)
        }
    }

    /// The automatic fill: the colors, in order, each take an equal, connected run of points
    /// along a zigzag through the grid's diagonals. Any number of colors on either grid reads as a
    /// deliberate diagonal flow from the top left, never a scatter of repeats.
    static func automaticStopIndex(at index: Int, size: Int, count: Int) -> Int {
        guard count > 0, let position = fillOrder(size: size).firstIndex(of: index) else { return 0 }
        return position * count / (size * size)
    }

    /// Points in fill order: diagonal by diagonal, alternating direction so each step is to a neighbor.
    static func fillOrder(size: Int) -> [Int] {
        (0...(2 * size - 2)).flatMap { diagonal -> [Int] in
            let cells = (0..<size).compactMap { row -> Int? in
                let column = diagonal - row
                return (0..<size).contains(column) ? row * size + column : nil
            }
            return diagonal.isMultiple(of: 2) ? cells : cells.reversed()
        }
    }

    /// Mesh used to blend free-floating points as soft cells. Old files open as an even grid where
    /// each point takes the color of the nearest original point, so the layout reads the same.
    static func migrated(from stops: [ColorStop], size: Int = 3) -> [MeshVertex] {
        guard !stops.isEmpty else { return [] }
        return regular(size: size).map { vertex in
            var mapped = vertex
            mapped.hex = stops.min { lhs, rhs in
                hypot(lhs.x - vertex.x, lhs.y - vertex.y) < hypot(rhs.x - vertex.x, rhs.y - vertex.y)
            }?.hex ?? ""
            return mapped
        }
    }

    /// Changes the grid size, keeping its bends: the new points sit on the current surface and keep
    /// the nearest point's color.
    static func resampled(_ vertices: [MeshVertex], from oldSize: Int, to newSize: Int) -> [MeshVertex] {
        let xs = vertices.map(\.x), ys = vertices.map(\.y)
        let last = Double(newSize - 1), oldLast = Double(oldSize - 1)
        return (0..<newSize * newSize).map { index in
            let u = Double(index % newSize) / last, v = Double(index / newSize) / last
            let nearest = Int((v * oldLast).rounded()) * oldSize + Int((u * oldLast).rounded())
            return MeshVertex(
                x: min(1, max(0, surface(xs, size: oldSize, u: u, v: v, monotone: true))),
                y: min(1, max(0, surface(ys, size: oldSize, u: u, v: v, monotone: true))),
                hex: vertices[nearest].hex
            )
        }
    }

    /// Keeps the grid in order so it never folds over itself: corners stay put, edge points slide only
    /// along their edge, and every point stays between its neighbors in its row and column. The mesh
    /// therefore always covers the whole canvas without creases.
    static func constrained(_ index: Int, x: Double, y: Double, in vertices: [MeshVertex], size: Int) -> (x: Double, y: Double) {
        let column = index % size, row = index / size, last = size - 1
        var x = min(1, max(0, x)), y = min(1, max(0, y))
        let onVerticalEdge = column == 0 || column == last, onHorizontalEdge = row == 0 || row == last
        if column == 0 { x = 0 } else if column == last { x = 1 }
        if row == 0 { y = 0 } else if row == last { y = 1 }
        let spacing = 0.06
        if !onVerticalEdge {
            let lower = vertices[index - 1].x + spacing, upper = vertices[index + 1].x - spacing
            x = min(max(x, lower), max(lower, upper))
        }
        if !onHorizontalEdge {
            let lower = vertices[index - size].y + spacing, upper = vertices[index + size].y - spacing
            y = min(max(y, lower), max(lower, upper))
        }
        return (x, y)
    }

    /// A point on the bent grid, for drawing its lines. `u` runs across and `v` down, both 0...1.
    static func point(on vertices: [MeshVertex], size: Int, u: Double, v: Double) -> (x: Double, y: Double) {
        (surface(vertices.map(\.x), size: size, u: u, v: v, monotone: true), surface(vertices.map(\.y), size: size, u: u, v: v, monotone: true))
    }

    // MARK: - Splines

    /// A cubic Hermite curve through `values` with Catmull-Rom tangents scaled by `tension`: 1 is a
    /// Catmull-Rom spline, 0 holds flat at every value. `extrapolate` carries each end on in a straight
    /// line (used for positions, so straight edges stay straight); otherwise the ends hold (colors).
    /// `sharpness` above 1 steepens each segment's middle, so values hold longer at the points.
    /// `monotone` limits the tangents (Fritsch–Carlson) so the curve never overshoots its values;
    /// positions use it so unevenly spaced points can't loop the grid back over itself.
    /// `approximation` blends toward a uniform B-spline, which no longer passes through the values
    /// but is far smoother: the soft end of Mesh's Softness.
    static func spline(_ values: [Double], at t: Double, tension: Double = 1, sharpness: Double = 1, monotone: Bool = false, approximation: Double = 0, extrapolate: Bool = true) -> Double {
        let count = values.count
        guard count > 1 else { return values.first ?? 0 }
        let scaled = min(max(t, 0), 1) * Double(count - 1)
        let index = min(count - 2, Int(scaled))
        var u = scaled - Double(index)
        if sharpness != 1, u > 0, u < 1 {
            let rising = pow(u, sharpness)
            u = rising / (rising + pow(1 - u, sharpness))
        }
        let p1 = values[index], p2 = values[index + 1]
        let p0 = index > 0 ? values[index - 1] : (extrapolate ? 2 * p1 - p2 : p1)
        let p3 = index + 2 < count ? values[index + 2] : (extrapolate ? 2 * p2 - p1 : p2)
        var m1 = tension * (p2 - p0) / 2, m2 = tension * (p3 - p1) / 2
        if monotone {
            m1 = limited(m1, p1 - p0, p2 - p1)
            m2 = limited(m2, p2 - p1, p3 - p2)
        }
        let u2 = u * u, u3 = u2 * u
        let hermite = (2 * u3 - 3 * u2 + 1) * p1 + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * p2 + (u3 - u2) * m2
        guard approximation > 0 else { return hermite }
        let inverse = 1 - u
        let bSpline = (inverse * inverse * inverse * p0 + (3 * u3 - 6 * u2 + 4) * p1 + (-3 * u3 + 3 * u2 + 3 * u + 1) * p2 + u3 * p3) / 6
        return hermite + (bSpline - hermite) * approximation
    }

    /// Softens a row-major grid of values with a [1 2 1] blur along rows and columns (ends held),
    /// mixed in by `amount`.
    static func smoothed(_ grid: [Double], size: Int, amount: Double) -> [Double] {
        guard amount > 0 else { return grid }
        func value(_ source: [Double], _ row: Int, _ column: Int) -> Double {
            source[min(size - 1, max(0, row)) * size + min(size - 1, max(0, column))]
        }
        let across = (0..<grid.count).map { index -> Double in
            let row = index / size, column = index % size
            return (value(grid, row, column - 1) + 2 * value(grid, row, column) + value(grid, row, column + 1)) / 4
        }
        return (0..<grid.count).map { index -> Double in
            let row = index / size, column = index % size
            let blurred = (value(across, row - 1, column) + 2 * value(across, row, column) + value(across, row + 1, column)) / 4
            return grid[index] + (blurred - grid[index]) * amount
        }
    }

    /// A tangent kept within three times each neighboring slope and flat at a turn, so a monotone run
    /// of values stays monotone.
    private static func limited(_ tangent: Double, _ before: Double, _ after: Double) -> Double {
        guard before * after > 0 else { return 0 }
        let bound = 3 * min(abs(before), abs(after))
        return max(-bound, min(bound, tangent))
    }

    /// The tensor-product surface through a row-major grid of values, at one point.
    static func surface(_ grid: [Double], size: Int, u: Double, v: Double, tension: Double = 1, monotone: Bool = false, extrapolate: Bool = true) -> Double {
        let rows = (0..<size).map { row in spline(Array(grid[row * size..<(row + 1) * size]), at: u, tension: tension, monotone: monotone, extrapolate: extrapolate) }
        return spline(rows, at: v, tension: tension, monotone: monotone, extrapolate: extrapolate)
    }

    /// The same surface sampled on an even `samples` × `samples` lattice, row-major. Separable, so it
    /// splines each grid row once and then each lattice column.
    static func sampledSurface(_ grid: [Double], size: Int, samples: Int, tension: Double = 1, sharpness: Double = 1, monotone: Bool = false, approximation: Double = 0, extrapolate: Bool = true) -> [Double] {
        let steps = (0..<samples).map { Double($0) / Double(samples - 1) }
        let rows = (0..<size).map { row -> [Double] in
            let values = Array(grid[row * size..<(row + 1) * size])
            return steps.map { spline(values, at: $0, tension: tension, sharpness: sharpness, monotone: monotone, approximation: approximation, extrapolate: extrapolate) }
        }
        var result = [Double](repeating: 0, count: samples * samples)
        for column in 0..<samples {
            let values = rows.map { $0[column] }
            for (row, v) in steps.enumerated() {
                result[row * samples + column] = spline(values, at: v, tension: tension, sharpness: sharpness, monotone: monotone, approximation: approximation, extrapolate: extrapolate)
            }
        }
        return result
    }
}
