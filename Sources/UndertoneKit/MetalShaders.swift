import Foundation

/// Slots in the float parameter buffer the Metal kernel reads. The shader's `#define`s are generated
/// from these cases, so Swift and Metal can't disagree about the layout.
nonisolated enum MetalFloat: Int, CaseIterable {
    case grain
    case lineStartX, lineStartY, lineDX, lineDY, lineLengthSquared
    case centerX, centerY, fadeWidth
    case axisX, axisY, crossX, crossY, position, flow, phase
    case softnessCore, swirlStrength, swirlCenterX, swirlCenterY
    case organicCore, organicSwirlStrength, organicSwirlCenterX, organicSwirlCenterY
    case organicPullStretch, organicWaveX, organicWaveY, organicWavePhaseA, organicWavePhaseB, organicWaveHeight
    case meshScaleX, meshScaleY
    case emptyRed, emptyGreen, emptyBlue
}

/// Slots in the integer parameter buffer.
nonisolated enum MetalInt: Int, CaseIterable {
    case width, height, mode, hasColors, grainCellSize, grainSeed
    case stopCount, paletteCount, organicClassic
    case tileColumns, tileRows, tileSize, latticeCount
}

/// Buffer indices shared by every kernel.
nonisolated enum MetalBuffer: Int, CaseIterable {
    case floats, ints, stops, palette, xWarp, yWarp, lattice, latticeColors, triangles, tileOffsets, tileIndices, output
}

/// The mode numbers the kernel switches on.
nonisolated extension GradientMode {
    var metalIndex: Int32 {
        switch self {
        case .organic: 0
        case .mesh: 1
        case .linear: 2
        case .tonal: 3
        case .radial: 4
        case .aurora: 5
        }
    }
}

/// The Metal source for the renderer, compiled at runtime with `makeLibrary(source:)` because a plain
/// `swift build` doesn't reliably compile `.metal` files in a Swift package. Every function mirrors
/// its Swift counterpart in `GradientRenderer`; keep the two in step (the parity tests check).
nonisolated enum MetalShaders {
    static var source: String {
        let floats = MetalFloat.allCases.map { "#define F_\($0) \($0.rawValue)" }
        let ints = MetalInt.allCases.map { "#define I_\($0) \($0.rawValue)" }
        let buffers = MetalBuffer.allCases.map { "#define B_\($0) \($0.rawValue)" }
        return (floats + ints + buffers).joined(separator: "\n") + "\n" + body
    }

    private static let body = """
    #include <metal_stdlib>
    using namespace metal;

    struct Inputs {
        constant float *f;
        constant int *i;
        constant float4 *stops;
        constant float4 *palette;
        constant float *xWarp;
        constant float *yWarp;
        constant float4 *lattice;
        constant float4 *latticeColors;
        constant uint *triangles;
        constant uint *tileOffsets;
        constant uint *tileIndices;
    };

    static float normalizedCoordinate(int value, int count) {
        return count == 1 ? 0.5f : float(value) / float(count - 1);
    }

    static float srgbEncode(float value) {
        float converted = value <= 0.0031308f ? value * 12.92f : 1.055f * pow(max(0.0f, value), 1.0f / 2.4f) - 0.055f;
        return clamp(converted, 0.0f, 1.0f);
    }

    static float3 oklabToSRGB(float3 lab) {
        float lRoot = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
        float mRoot = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
        float sRoot = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
        float l = lRoot * lRoot * lRoot, m = mRoot * mRoot * mRoot, s = sRoot * sRoot * sRoot;
        return float3(
            srgbEncode(4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s),
            srgbEncode(-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s),
            srgbEncode(-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s)
        );
    }

    static float3 paletteColor(const thread Inputs &in, float amount) {
        int count = in.i[I_paletteCount];
        int index = int(floor(clamp(amount, 0.0f, 1.0f) * float(count - 1) + 0.5f));
        return in.palette[index].rgb;
    }

    static uint hash32(uint value) {
        value ^= value >> 16;
        value *= 0x7FEB352Du;
        value ^= value >> 15;
        value *= 0x846CA68Bu;
        value ^= value >> 16;
        return value;
    }

    static float hashNoise(int x, int y, uint seed) {
        uint value = hash32(uint(x) + hash32(uint(y) + hash32(seed)));
        return float(value >> 8) / 16777216.0f * 2.0f - 1.0f;
    }

    static float3 organicColor(const thread Inputs &in, int column, int row, float x, float y) {
        float px = x, py = y;
        if (in.i[I_organicClassic] != 0) {
            px += in.xWarp[row];
            py += in.yWarp[column];
        }
        float waveHeight = in.f[F_organicWaveHeight];
        if (waveHeight > 0) {
            float waveX = in.f[F_organicWaveX], waveY = in.f[F_organicWaveY];
            float across = -px * waveY + py * waveX;
            float push = (sin(across * 6.9f + in.f[F_organicWavePhaseA]) * 0.7f + sin(across * 3.6f + in.f[F_organicWavePhaseB]) * 0.3f) * waveHeight;
            px += waveX * push;
            py += waveY * push;
        }
        float swirl = in.f[F_organicSwirlStrength];
        if (swirl != 0) {
            float cx = in.f[F_organicSwirlCenterX], cy = in.f[F_organicSwirlCenterY];
            float dx = px - cx, dy = py - cy;
            float twist = swirl * exp(-(dx * dx + dy * dy) * 3.2f);
            float cosT = cos(twist), sinT = sin(twist);
            px = cx + dx * cosT - dy * sinT;
            py = cy + dx * sinT + dy * cosT;
        }
        float total = 0, chroma = 0;
        float3 lab = float3(0);
        float core = in.f[F_organicCore];
        float stretch = in.f[F_organicPullStretch];
        for (int s = 0; s < in.i[I_stopCount]; s++) {
            float4 place = in.stops[s * 2 + 1];
            float dx = px - place.x, dy = py - place.y;
            if (stretch != 1) {
                float cosA = cos(place.w), sinA = sin(place.w);
                float along = dx * cosA + dy * sinA, across = -dx * sinA + dy * cosA;
                dx = along / stretch;
                dy = across * sqrt(stretch);
            }
            float distance = dx * dx + dy * dy + core;
            float weight = place.z / (distance * distance);
            total += weight;
            lab += in.stops[s * 2].xyz * weight;
            chroma += in.stops[s * 2].w * weight;
        }
        lab /= total;
        float mixed = sqrt(lab.y * lab.y + lab.z * lab.z);
        if (mixed > 1e-4f) {
            float restore = 1 + (min(chroma / total / mixed, 1.8f) - 1) * 0.6f;
            lab.yz *= restore;
        }
        return oklabToSRGB(lab);
    }

    static float3 tonalColor(const thread Inputs &in, int column, int row, float x, float y) {
        float sx = x + in.xWarp[row];
        float sy = y + in.yWarp[column];
        float swirl = in.f[F_swirlStrength];
        if (swirl != 0) {
            float cx = in.f[F_swirlCenterX], cy = in.f[F_swirlCenterY];
            float dx = sx - cx, dy = sy - cy;
            float twist = swirl * exp(-(dx * dx + dy * dy) * 3.2f);
            float cosT = cos(twist), sinT = sin(twist);
            sx = cx + dx * cosT - dy * sinT;
            sy = cy + dx * sinT + dy * cosT;
        }
        float core = in.f[F_softnessCore];
        float total = 0;
        float3 color = float3(0);
        for (int s = 0; s < in.i[I_stopCount]; s++) {
            float4 place = in.stops[s * 2 + 1];
            float dx = sx - place.x, dy = sy - place.y;
            float distance = dx * dx + dy * dy + core;
            float weight = place.z / (distance * distance);
            total += weight;
            color += in.stops[s * 2].rgb * weight;
        }
        return color / total;
    }

    static float3 meshColor(const thread Inputs &in, int column, int row, float x, float y) {
        float pointX = x * in.f[F_meshScaleX], pointY = y * in.f[F_meshScaleY];
        int size = in.i[I_tileSize];
        int tile = min(in.i[I_tileRows] - 1, row / size) * in.i[I_tileColumns] + min(in.i[I_tileColumns] - 1, column / size);
        uint start = in.tileOffsets[tile], end = in.tileOffsets[tile + 1];
        for (uint index = end; index > start; index--) {
            uint base = in.tileIndices[index - 1] * 3;
            uint a = in.triangles[base], b = in.triangles[base + 1], c = in.triangles[base + 2];
            float2 pa = in.lattice[a].xy, pb = in.lattice[b].xy, pc = in.lattice[c].xy;
            float2 e0 = pb - pa, e1 = pc - pa;
            float area = e0.x * e1.y - e1.x * e0.y;
            if (abs(area) <= 1e-6f) { continue; }
            float2 q = float2(pointX, pointY) - pa;
            float wb = (q.x * e1.y - e1.x * q.y) / area;
            float wc = (e0.x * q.y - q.x * e0.y) / area;
            float wa = 1 - wb - wc;
            float tolerance = -1e-5f;
            if (wa < tolerance || wb < tolerance || wc < tolerance) { continue; }
            return oklabToSRGB(wa * in.latticeColors[a].xyz + wb * in.latticeColors[b].xyz + wc * in.latticeColors[c].xyz);
        }
        int nearest = 0;
        float best = INFINITY;
        for (int index = 0; index < in.i[I_latticeCount]; index++) {
            float2 d = in.lattice[index].xy - float2(pointX, pointY);
            float distance = dot(d, d);
            if (distance < best) { best = distance; nearest = index; }
        }
        return oklabToSRGB(in.latticeColors[nearest].xyz);
    }

    static float grainNoise(int x, int y, int cell, uint seed) {
        if (cell == 1) { return hashNoise(x, y, seed); }
        int cellX = x / cell, cellY = y / cell;
        float fx = float(x % cell) / float(cell), fy = float(y % cell) / float(cell);
        float sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
        float top = mix(hashNoise(cellX, cellY, seed), hashNoise(cellX + 1, cellY, seed), sx);
        float bottom = mix(hashNoise(cellX, cellY + 1, seed), hashNoise(cellX + 1, cellY + 1, seed), sx);
        return mix(top, bottom, sy);
    }

    static float ditherUnit(int column, int row, uint salt) {
        return float(hash32(uint(column) + hash32(uint(row) + hash32(0x5EED0000u + salt))) >> 8) / 16777216.0f;
    }

    /// Mirrors `GradientRenderer.dither`: a triangular ±1/255 offset per channel against banding.
    static float3 dither(int column, int row) {
        float3 result;
        for (uint channel = 0; channel < 3; channel++) {
            result[channel] = (ditherUnit(column, row, channel * 2) + ditherUnit(column, row, channel * 2 + 1) - 1.0f) / 255.0f;
        }
        return result;
    }

    /// The color of one pixel before 8-bit quantization, grain and dither included.
    static float3 pixel(const thread Inputs &in, int column, int row) {
        int width = in.i[I_width], height = in.i[I_height];
        float x = normalizedCoordinate(column, width), y = normalizedCoordinate(row, height);
        float3 color;
        if (in.i[I_hasColors] == 0) {
            color = float3(in.f[F_emptyRed], in.f[F_emptyGreen], in.f[F_emptyBlue]);
        } else {
            switch (in.i[I_mode]) {
            case 0: color = organicColor(in, column, row, x, y); break;
            case 1: color = meshColor(in, column, row, x, y); break;
            case 3: color = tonalColor(in, column, row, x, y); break;
            case 2: {
                float projection = ((x - in.f[F_lineStartX]) * in.f[F_lineDX] + (y - in.f[F_lineStartY]) * in.f[F_lineDY]) / in.f[F_lineLengthSquared];
                color = paletteColor(in, projection);
                break;
            }
            case 4: {
                float dx = x - in.f[F_centerX], dy = y - in.f[F_centerY];
                color = paletteColor(in, sqrt(dx * dx + dy * dy) / in.f[F_fadeWidth]);
                break;
            }
            default: {
                float axis = 0.5f + (x - 0.5f) * in.f[F_axisX] + (y - 0.5f) * in.f[F_axisY];
                float cross = (x - 0.5f) * in.f[F_crossX] + (y - 0.5f) * in.f[F_crossY];
                float phase = in.f[F_phase];
                float ribbon = sin(cross * M_PI_F * 2.4f + phase) * 0.18f + sin(cross * M_PI_F * 5.2f - phase * 0.7f) * 0.055f;
                color = paletteColor(in, 0.5f + (axis + ribbon * in.f[F_flow] - in.f[F_position]) / in.f[F_fadeWidth]);
                break;
            }
            }
        }
        float grain = in.f[F_grain];
        if (grain > 0) {
            int longSide = max(max(width, height), 1);
            int gx = column * 1280 / longSide, gy = row * 1280 / longSide;
            color += grainNoise(gx, gy, in.i[I_grainCellSize], uint(in.i[I_grainSeed])) * grain * 0.105f;
        }
        return color + dither(column, row);
    }

    #define INPUTS \\
        constant float *f [[buffer(B_floats)]], \\
        constant int *i [[buffer(B_ints)]], \\
        constant float4 *stops [[buffer(B_stops)]], \\
        constant float4 *palette [[buffer(B_palette)]], \\
        constant float *xWarp [[buffer(B_xWarp)]], \\
        constant float *yWarp [[buffer(B_yWarp)]], \\
        constant float4 *lattice [[buffer(B_lattice)]], \\
        constant float4 *latticeColors [[buffer(B_latticeColors)]], \\
        constant uint *triangles [[buffer(B_triangles)]], \\
        constant uint *tileOffsets [[buffer(B_tileOffsets)]], \\
        constant uint *tileIndices [[buffer(B_tileIndices)]]

    #define GATHER Inputs in = { f, i, stops, palette, xWarp, yWarp, lattice, latticeColors, triangles, tileOffsets, tileIndices };

    /// Export: 8-bit sRGB bytes, rounded half up exactly like the CPU renderer.
    kernel void renderBytes(INPUTS, device uchar4 *output [[buffer(B_output)]], uint2 gid [[thread_position_in_grid]]) {
        GATHER
        if (int(gid.x) >= in.i[I_width] || int(gid.y) >= in.i[I_height]) { return; }
        float3 color = pixel(in, int(gid.x), int(gid.y));
        uchar3 bytes = uchar3(floor(clamp(color, 0.0f, 1.0f) * 255.0f + 0.5f));
        output[gid.y * uint(in.i[I_width]) + gid.x] = uchar4(bytes, 255);
    }

    /// Preview: the same pixels written straight into a drawable texture.
    kernel void renderTexture(INPUTS, texture2d<float, access::write> output [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        GATHER
        if (int(gid.x) >= in.i[I_width] || int(gid.y) >= in.i[I_height]) { return; }
        output.write(float4(clamp(pixel(in, int(gid.x), int(gid.y)), 0.0f, 1.0f), 1.0f), gid);
    }
    """
}
