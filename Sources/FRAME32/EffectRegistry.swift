import Foundation

enum EffectID: String, Codable, CaseIterable {
    case clean = "clean.signal"
    case chroma = "chroma.shift"
    case poster = "poster.eight"
    case crt = "scan.crt"
    case glitch = "glitch.wave"
    case solar = "solar.neg"
    case displace = "displace.noise"
    case edge = "edge.vector"
    case halftone = "halftone.print"
    case matrix = "matrix.rain"
    case raster = "raster.relief"
    case contour = "contour.flow"
    case hatch = "vector.hatch"
    case particles = "particle.skin"
    case fluid = "fluid.ghost"
    case growth = "ink.growth"
    case paint = "paint.flow"
    case cells = "cells.shatter"
    case echo = "echo.frame"
    case block = "block.error"
    case ascii = "ascii.grid"
    case sort = "pixel.sort"
    case slit = "motion.slit"
    case mosh = "mosh.flow"
    case dataveil = "dataveil"

}

enum ParameterKind {
    case scalar
    case integer
    case choices([String])
    case seed
}
struct EffectParameter {
    let key: String
    let label: String
    let range: ClosedRange<Float>
    let defaultValue: Float
    var unit = ""
    var decimals = 2
    var kind: ParameterKind = .scalar
    func validated(_ value: Float) -> Float {
        let finite = value.isFinite ? value : defaultValue
        let bounded = min(range.upperBound,max(range.lowerBound,finite))
        switch kind { case .integer, .choices: return bounded.rounded(); default: return bounded }
    }
    func display(_ value: Float) -> String {
        if case let .choices(options) = kind { return options[Int(validated(value))] }
        return String(format: "%.*f",decimals,validated(value)) + (unit.isEmpty ? "" : " " + unit)
    }
}
struct EffectDefinition {
    let id: EffectID
    let title: String
    let subtitle: String
    let bank: String
    let gpuMode: Int
    let parameters: [EffectParameter]
}
struct EffectValues: Codable, Equatable {
    var intensity: Float = 0.7
    var parameters: [String: Float] = [:]
    var seed: UInt32 = 3201
}

enum EffectRegistry {
    static let all: [EffectDefinition] = legacy + advanced
    static let advanced: [EffectDefinition] = [
        EffectDefinition(id: .raster,title: "RASTER//RELIEF",subtitle: "LUMA GEOMETRY / SCAN SURFACE",bank: "GEOMETRY",gpuMode: 10,parameters: [
            EffectParameter(key: "density",label: "LINE DENSITY",range: 24...160,defaultValue: 72,decimals: 0,kind: .integer),
            EffectParameter(key: "depth",label: "EXTRUSION",range: 0...1,defaultValue: 0.5),
            EffectParameter(key: "perspective",label: "SURFACE TILT",range: 0...1,defaultValue: 0.3),
            EffectParameter(key: "style",label: "GEOMETRY",range: 0...2,defaultValue: 0,decimals: 0,kind: .choices(["SCANLINES","WIRE MESH","POINTS"])),
            EffectParameter(key: "fade",label: "TRAIL HALF LIFE",range: 0...2,defaultValue: 0.25),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 185)]),
        EffectDefinition(id: .contour,title: "CONTOUR//FLOW",subtitle: "FLOW GUIDED / LUMINOUS INK",bank: "CONTOUR",gpuMode: 11,parameters: [
            EffectParameter(key: "radius",label: "LINE SCALE",range: 1...4,defaultValue: 1.8),
            EffectParameter(key: "threshold",label: "INK THRESHOLD",range: 0.01...0.3,defaultValue: 0.05),
            EffectParameter(key: "coherence",label: "FLOW COHERENCE",range: 1...6,defaultValue: 3),
            EffectParameter(key: "fade",label: "TRAIL HALF LIFE",range: 0...2,defaultValue: 0.2),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 190),
            EffectParameter(key: "paper",label: "PAPER / DARK",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["LIGHT PAPER","DARK GLOW"])),
            EffectParameter(key: "glow",label: "INK GLOW",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "cameraColor",label: "CAMERA COLOR",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["SOURCE COLOR","MONOCHROME"]))]),
        EffectDefinition(id: .hatch,title: "VECTOR//HATCH",subtitle: "STRUCTURE / CROSSHATCH ENGRAVING",bank: "CONTOUR",gpuMode: 12,parameters: [
            EffectParameter(key: "spacing",label: "STROKE SPACING",range: 3...48,defaultValue: 12),
            EffectParameter(key: "width",label: "STROKE WIDTH",range: 0.5...8,defaultValue: 1.8),
            EffectParameter(key: "cross",label: "CROSSHATCH",range: 0...1,defaultValue: 0.6),
            EffectParameter(key: "contrast",label: "TONE DEPTH",range: 0.3...2,defaultValue: 1),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 220),
            EffectParameter(key: "paper",label: "PAPER / DARK",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["LIGHT PAPER","DARK INK"])),
            EffectParameter(key: "length",label: "STROKE LENGTH",range: 6...240,defaultValue: 48),
            EffectParameter(key: "scale",label: "STROKE SCALE",range: 0.5...12,defaultValue: 3,unit: "x")]),
        EffectDefinition(id: .particles,title: "PARTICLE//SKIN",subtitle: "DIRECTIONAL FLIGHT / PIXEL REGROWTH",bank: "GEOMETRY",gpuMode: 13,parameters: [
            EffectParameter(key: "density",label: "PARTICLE COLUMNS",range: 48...160,defaultValue: 96,decimals: 0,kind: .integer),
            EffectParameter(key: "scatter",label: "MOTION SCATTER",range: 0...4,defaultValue: 1.5),
            EffectParameter(key: "flight",label: "FLIGHT LIFETIME",range: 0.3...5,defaultValue: 1.6,unit: "s"),
            EffectParameter(key: "size",label: "POINT SIZE",range: 1...10,defaultValue: 3),
            EffectParameter(key: "fade",label: "TRAIL HALF LIFE",range: 0...2,defaultValue: 0.15),
            EffectParameter(key: "hue",label: "TINT HUE",range: 0...360,defaultValue: 185),
            EffectParameter(key: "color",label: "COLOR",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["CAMERA","TINT"])),
            EffectParameter(key: "regrow",label: "REPLACEMENT GROW TIME",range: 0.1...3,defaultValue: 0.9,unit: "s"),
            EffectParameter(key: "drag",label: "FLIGHT DRAG",range: 0...3,defaultValue: 0.2),
            EffectParameter(key: "trigger",label: "LAUNCH SPEED",range: 1...400,defaultValue: 35)]),
        EffectDefinition(id: .fluid,title: "FLUID//GHOST",subtitle: "MOTION ADVECTION / LIQUID WAKES",bank: "TEMPORAL",gpuMode: 14,parameters: [
            EffectParameter(key: "flow",label: "FLOW STRENGTH",range: 0...6,defaultValue: 2),
            EffectParameter(key: "refresh",label: "CAMERA REFRESH",range: 0...1,defaultValue: 0.15),
            EffectParameter(key: "diffusion",label: "DIFFUSION",range: 0...1,defaultValue: 0.3),
            EffectParameter(key: "fade",label: "WAKE HALF LIFE",range: 0.1...5,defaultValue: 1.3),
            EffectParameter(key: "swirl",label: "CURL SWIRL",range: 0...2,defaultValue: 0.5)]),
        EffectDefinition(id: .growth,title: "INK//GROWTH",subtitle: "CAMERA SEEDED / REACTION DIFFUSION",bank: "SIMULATION",gpuMode: 15,parameters: [
            EffectParameter(key: "feed",label: "FEED",range: 0.01...0.08,defaultValue: 0.0367,decimals: 4),
            EffectParameter(key: "kill",label: "KILL",range: 0.03...0.075,defaultValue: 0.0649,decimals: 4),
            EffectParameter(key: "seeding",label: "EDGE SEEDING",range: 0...1,defaultValue: 0.4),
            EffectParameter(key: "speed",label: "GROWTH RATE",range: 0.1...2,defaultValue: 1),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 275),
            EffectParameter(key: "reveal",label: "CAMERA REVEAL",range: 0...1,defaultValue: 0.15),
            EffectParameter(key: "relief",label: "RELIEF LIGHT",range: 0...2,defaultValue: 0.7),
            EffectParameter(key: "motion",label: "MOTION REACTIVITY",range: 0...4,defaultValue: 1.5),
            EffectParameter(key: "direction",label: "GROWTH DIRECTION",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["OUTWARD","INWARD"])),
            EffectParameter(key: "travel",label: "PROPAGATION",range: 0...3,defaultValue: 0.7)]),
        EffectDefinition(id: .paint,title: "PAINT//FLOW",subtitle: "ANISOTROPIC KUWAHARA / INK",bank: "CONTOUR",gpuMode: 16,parameters: [
            EffectParameter(key: "radius",label: "BRUSH RADIUS",range: 1...6,defaultValue: 3),
            EffectParameter(key: "anisotropy",label: "DIRECTIONALITY",range: 0...1,defaultValue: 0.7),
            EffectParameter(key: "sharpness",label: "REGION SHARPNESS",range: 1...12,defaultValue: 5),
            EffectParameter(key: "ink",label: "CONTOUR INK",range: 0...1,defaultValue: 0.3),
            EffectParameter(key: "fade",label: "PERSISTENCE HALF LIFE",range: 0...0.5,defaultValue: 0.08),
            EffectParameter(key: "saturation",label: "PAINT SATURATION",range: 0...2,defaultValue: 1.2),
            EffectParameter(key: "threshold",label: "PAINT THRESHOLD",range: 0...1,defaultValue: 1),
            EffectParameter(key: "softness",label: "MASK SOFTNESS",range: 0.001...0.3,defaultValue: 0.04),
            EffectParameter(key: "fill",label: "PAINT FILL",range: 0...4,defaultValue: 0,decimals: 0,kind: .choices(["PAINT","INK","GREENSCREEN","BLUESCREEN","WHITE"])),
            EffectParameter(key: "hue",label: "FILL INK HUE",range: 0...360,defaultValue: 190),
            EffectParameter(key: "invert",label: "MASK SELECTION",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["DARK TO LIGHT","LIGHT TO DARK"]))]),
        EffectDefinition(id: .cells,title: "CELLS//SHATTER",subtitle: "VORONOI / MOTION FRACTURE",bank: "GEOMETRY",gpuMode: 17,parameters: [
            EffectParameter(key: "density",label: "CELL COLUMNS",range: 8...160,defaultValue: 24,decimals: 0,kind: .integer),
            EffectParameter(key: "scatter",label: "SEPARATION",range: 0...2,defaultValue: 1),
            EffectParameter(key: "return",label: "RETURN STIFFNESS",range: 1...30,defaultValue: 9),
            EffectParameter(key: "border",label: "BORDER WIDTH",range: 0...4,defaultValue: 1),
            EffectParameter(key: "hue",label: "BORDER HUE",range: 0...360,defaultValue: 195),
            EffectParameter(key: "seed",label: "SEED",range: 0...1,defaultValue: 0,decimals: 0,kind: .seed),
            EffectParameter(key: "shape",label: "CELL SHAPE",range: 0...4,defaultValue: 0,decimals: 0,kind: .choices(["VORONOI","SQUARE","DIAMOND","HEXAGON","ROUND"]))]),
        EffectDefinition(id: .echo,title: "ECHO//FRAME",subtitle: "LINEAR LIGHT / CAMERA FEEDBACK",bank: "TEMPORAL",gpuMode: 18,parameters: [
            EffectParameter(key: "fade",label: "ECHO HALF LIFE",range: 0.05...4,defaultValue: 0.6),
            EffectParameter(key: "zoom",label: "FEEDBACK ZOOM",range: -0.2...0.2,defaultValue: 0.025),
            EffectParameter(key: "rotation",label: "ROTATION",range: -30...30,defaultValue: 3),
            EffectParameter(key: "drift",label: "HORIZONTAL DRIFT",range: -80...80,defaultValue: 0),
            EffectParameter(key: "mix",label: "HISTORY MIX",range: 0...1,defaultValue: 0.7),
            EffectParameter(key: "ink",label: "ECHO INK",range: 0...7,defaultValue: 0,decimals: 0,kind: .choices(["CAMERA","MONOCHROME","TINT","NEGATIVE","POSTER","THERMAL","CHROMA SPLIT","CONTOUR"])),
            EffectParameter(key: "hue",label: "ECHO INK HUE",range: 0...360,defaultValue: 280),
            EffectParameter(key: "inkAmount",label: "ECHO INK AMOUNT",range: 0...1,defaultValue: 1)]),
        EffectDefinition(id: .block,title: "BLOCK//ERROR",subtitle: "HELD MACROBLOCKS / RESIDUALS",bank: "CORRUPTION",gpuMode: 19,parameters: [
            EffectParameter(key: "tile",label: "TILE SIZE",range: 8...96,defaultValue: 32,decimals: 0,kind: .integer),
            EffectParameter(key: "probability",label: "ERROR DENSITY",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "hold",label: "HOLD PERIOD",range: 0.05...2,defaultValue: 0.4,unit: "s"),
            EffectParameter(key: "offset",label: "TILE DISPLACEMENT",range: 0...4,defaultValue: 1),
            EffectParameter(key: "levels",label: "RESIDUAL LEVELS",range: 2...32,defaultValue: 8),
            EffectParameter(key: "seed",label: "SEED",range: 0...1,defaultValue: 0,decimals: 0,kind: .seed),
            EffectParameter(key: "preset",label: "ERROR PRESET",range: 0...4,defaultValue: 0,decimals: 0,kind: .choices(["STANDARD","CRUSHED","POSTER DAMAGE","CHROMA LOSS","RESIDUAL HEAT"]))]),
        EffectDefinition(id: .ascii,title: "ASCII//GRID",subtitle: "COVERAGE RANKED / TONE GLYPHS",bank: "DIGITAL",gpuMode: 20,parameters: [
            EffectParameter(key: "cell",label: "GLYPH WIDTH",range: 6...24,defaultValue: 10),
            EffectParameter(key: "contrast",label: "TONE CONTRAST",range: 0.5...2,defaultValue: 1),
            EffectParameter(key: "color",label: "INK",range: 0...2,defaultValue: 0,decimals: 0,kind: .choices(["CAMERA","MONOCHROME","TINT"])),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 145),
            EffectParameter(key: "invert",label: "POLARITY",range: 0...2,defaultValue: 0,decimals: 0,kind: .choices(["DARK BACKGROUND","LIGHT PAPER","DARK PAPER"]))]),
        EffectDefinition(id: .sort,title: "PIXEL//SORT",subtitle: "BOUNDED / LUMINANCE SEGMENTS",bank: "CORRUPTION",gpuMode: 21,parameters: [
            EffectParameter(key: "length",label: "SEGMENT LENGTH",range: 8...256,defaultValue: 32,decimals: 0,kind: .integer),
            EffectParameter(key: "low",label: "LOWER LUMA",range: 0...1,defaultValue: 0.2),
            EffectParameter(key: "high",label: "UPPER LUMA",range: 0...1,defaultValue: 0.85),
            EffectParameter(key: "direction",label: "DIRECTION",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["HORIZONTAL","VERTICAL"])),
            EffectParameter(key: "reverse",label: "ORDER",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["DARK TO LIGHT","LIGHT TO DARK"])),
            EffectParameter(key: "stretch",label: "STREAK STRETCH",range: 1...8,defaultValue: 2.5),
            EffectParameter(key: "key",label: "SORT KEY",range: 0...3,defaultValue: 0,decimals: 0,kind: .choices(["LUMINANCE","RED","SATURATION","HUE"])),
            EffectParameter(key: "style",label: "STREAK STYLE",range: 0...3,defaultValue: 1,decimals: 0,kind: .choices(["SORT","STRETCH","COMB","SHRED"]))]),
        EffectDefinition(id: .slit,title: "MOTION//SLIT",subtitle: "EIGHT SLICE / TIME DISPLACEMENT",bank: "TEMPORAL",gpuMode: 22,parameters: [
            EffectParameter(key: "delay",label: "HISTORY SPAN",range: 0.1...2,defaultValue: 0.8),
            EffectParameter(key: "direction",label: "TIME DIRECTION",range: 0...3,defaultValue: 0,decimals: 0,kind: .choices(["HORIZONTAL","VERTICAL","RADIAL","REVERSE HORIZONTAL"])),
            EffectParameter(key: "blend",label: "SLICE BLEND",range: 0...1,defaultValue: 1),
            EffectParameter(key: "ink",label: "INK",range: 0...5,defaultValue: 0,decimals: 0,kind: .choices(["CAMERA","MONOCHROME","TINT","NEGATIVE","POSTER","THERMAL"])),
            EffectParameter(key: "hue",label: "INK HUE",range: 0...360,defaultValue: 190),
            EffectParameter(key: "inkAmount",label: "INK AMOUNT",range: 0...1,defaultValue: 1)]),
        EffectDefinition(id: .mosh,title: "MOSH//FLOW",subtitle: "BLOCK MOTION / GATED REFRESH",bank: "TEMPORAL",gpuMode: 23,parameters: [
            EffectParameter(key: "flow",label: "MOTION MULTIPLIER",range: 0...4,defaultValue: 1.5),
            EffectParameter(key: "threshold",label: "REFRESH THRESHOLD",range: 0...0.5,defaultValue: 0.12),
            EffectParameter(key: "refresh",label: "KEYFRAME LEAK",range: 0...1,defaultValue: 0.05),
            EffectParameter(key: "blocks",label: "BLOCK SIZE",range: 4...48,defaultValue: 16,decimals: 0,kind: .integer),
            EffectParameter(key: "fade",label: "HISTORY HALF LIFE",range: 0.1...8,defaultValue: 3),
            EffectParameter(key: "interval",label: "KEYFRAME INTERVAL",range: 0...10,defaultValue: 0,unit: "s"),
            EffectParameter(key: "hold",label: "SMEAR HOLD TIME",range: 0...3,defaultValue: 0.35,unit: "s"),
            EffectParameter(key: "window",label: "REFRESH WINDOW",range: 0.02...1,defaultValue: 0.12,unit: "s"),
            EffectParameter(key: "cadence",label: "REFRESH CADENCE",range: 1...60,defaultValue: 30)]),
        EffectDefinition(id: .dataveil,title: "DATAVEIL",subtitle: "LUMA SILHOUETTE / GLOW FEEDBACK",bank: "TEMPORAL",gpuMode: 24,parameters: [
            EffectParameter(key: "threshold",label: "SILHOUETTE THRESHOLD",range: 0...1,defaultValue: 0.4),
            EffectParameter(key: "softness",label: "MASK SOFTNESS",range: 0.01...0.3,defaultValue: 0.08),
            EffectParameter(key: "fade",label: "VEIL HALF LIFE",range: 0.05...4,defaultValue: 0.8),
            EffectParameter(key: "drift",label: "FEEDBACK DRIFT",range: -80...80,defaultValue: 12),
            EffectParameter(key: "hue",label: "VEIL HUE",range: 0...360,defaultValue: 280),
            EffectParameter(key: "reveal",label: "CAMERA REVEAL",range: 0...1,defaultValue: 0.2),
            EffectParameter(key: "angle",label: "DRIFT ANGLE",range: -180...180,defaultValue: 0)])
    ]
    static let legacy: [EffectDefinition] = [
        EffectDefinition(id: .clean,title: "CLEAN SIGNAL",subtitle: "UNPROCESSED / COLOR ACTIVE",bank: "CLEAN",gpuMode: 0,parameters: []),
        EffectDefinition(id: .chroma,title: "CHROMA//SHIFT",subtitle: "RGB DISPLACEMENT",bank: "COLOR",gpuMode: 1,parameters: [
            EffectParameter(key: "separation",label: "SEPARATION",range: 0...1,defaultValue: 0.5),
            EffectParameter(key: "drift",label: "DRIFT RATE",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "radial",label: "RADIAL",range: 0...1,defaultValue: 0.5)]),
        EffectDefinition(id: .poster,title: "POSTER//8",subtitle: "PALETTE / ORDERED DITHER",bank: "COLOR",gpuMode: 2,parameters: [
            EffectParameter(key: "reduction",label: "PALETTE REDUCTION",range: 0...1,defaultValue: 0.5),
            EffectParameter(key: "dither",label: "DITHER",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "cell",label: "CELL SIZE",range: 0...1,defaultValue: 0.5)]),
        EffectDefinition(id: .crt,title: "SCAN//CRT",subtitle: "PHOSPHOR / SCANLINES",bank: "DISPLAY",gpuMode: 3,parameters: [
            EffectParameter(key: "depth",label: "CURVATURE / DEPTH",range: 0...1,defaultValue: 0.5),
            EffectParameter(key: "flicker",label: "FLICKER",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "spacing",label: "LINE SPACING",range: 0...1,defaultValue: 0.5)]),
        EffectDefinition(id: .glitch,title: "GLITCH//WAVE",subtitle: "TEAR / SIGNAL CORRUPTION",bank: "CORRUPTION",gpuMode: 4,parameters: [
            EffectParameter(key: "corruption",label: "CORRUPTION",range: 0...1,defaultValue: 0.5),
            EffectParameter(key: "rate",label: "UPDATE RATE",range: 0...1,defaultValue: 0.35),
            EffectParameter(key: "bands",label: "BAND DENSITY",range: 0...1,defaultValue: 0.5)]),
        EffectDefinition(id: .solar,title: "SOLAR//NEG",subtitle: "SOLARIZATION / SPLIT NEGATIVE",bank: "COLOR",gpuMode: 5,parameters: [
            EffectParameter(key: "low",label: "LOWER THRESHOLD",range: 0...0.995,defaultValue: 0.35),
            EffectParameter(key: "high",label: "UPPER THRESHOLD",range: 0.005...1,defaultValue: 0.65),
            EffectParameter(key: "curve",label: "CURVE",range: 0...2,defaultValue: 0,decimals: 0,kind: .choices(["SOLAR","NEGATIVE","SPLIT NEGATIVE"])),
            EffectParameter(key: "chroma",label: "CHROMA RETENTION",range: 0...1,defaultValue: 0.75),
            EffectParameter(key: "hue",label: "HUE OFFSET",range: -180...180,defaultValue: 0,unit: "deg",decimals: 0)]),
        EffectDefinition(id: .displace,title: "DISPLACE//NOISE",subtitle: "NOISE SWIM / PHASE JITTER",bank: "CORRUPTION",gpuMode: 6,parameters: [
            EffectParameter(key: "amplitude",label: "AMPLITUDE",range: 0...64,defaultValue: 12,unit: "px",decimals: 1),
            EffectParameter(key: "frequency",label: "NOISE FREQUENCY",range: 1...40,defaultValue: 8,unit: "cycles",decimals: 1),
            EffectParameter(key: "tears",label: "TEAR DENSITY",range: 0...1,defaultValue: 0.25),
            EffectParameter(key: "speed",label: "ANIMATION SPEED",range: 0...4,defaultValue: 0.8,unit: "Hz",decimals: 2),
            EffectParameter(key: "seed",label: "SEED",range: 0...1,defaultValue: 0,decimals: 0,kind: .seed)]),
        EffectDefinition(id: .edge,title: "EDGE//VECTOR",subtitle: "SCHARR / INK CONTOURS",bank: "CONTOUR",gpuMode: 7,parameters: [
            EffectParameter(key: "threshold",label: "THRESHOLD",range: 0...1,defaultValue: 0.18),
            EffectParameter(key: "softness",label: "SOFTNESS",range: 0.005...0.2,defaultValue: 0.04),
            EffectParameter(key: "width",label: "STROKE WIDTH",range: 1...7,defaultValue: 2,unit: "px",decimals: 1),
            EffectParameter(key: "surface",label: "SURFACE",range: 0...2,defaultValue: 0,decimals: 0,kind: .choices(["PAPER","ORIGINAL","POSTER"])),
            EffectParameter(key: "polarity",label: "POLARITY",range: 0...1,defaultValue: 0,decimals: 0,kind: .choices(["DARK INK","LIGHT INK"]))]),
        EffectDefinition(id: .halftone,title: "HALFTONE//PRINT",subtitle: "CMYK / ROTATED DOT SCREENS",bank: "CONTOUR",gpuMode: 8,parameters: [
            EffectParameter(key: "pitch",label: "DOT PITCH",range: 4...24,defaultValue: 8,unit: "px",decimals: 1),
            EffectParameter(key: "density",label: "INK DENSITY",range: 0...1.5,defaultValue: 1),
            EffectParameter(key: "rotation",label: "SCREEN ROTATION",range: -45...45,defaultValue: 0,unit: "deg",decimals: 1),
            EffectParameter(key: "black",label: "BLACK GENERATION",range: 0...1,defaultValue: 0.6),
            EffectParameter(key: "registration",label: "REGISTRATION",range: 0...6,defaultValue: 0.8,unit: "px",decimals: 1)]),
        EffectDefinition(id: .matrix,title: "MATRIX//RAIN",subtitle: "GLYPH FACECAM / DIGITAL RAIN",bank: "DIGITAL",gpuMode: 9,parameters: [
            EffectParameter(key: "cell",label: "GLYPH WIDTH",range: 6...24,defaultValue: 10,unit: "px",decimals: 1),
            EffectParameter(key: "speed",label: "RAIN SPEED",range: 0...30,defaultValue: 10,unit: "rows/s",decimals: 1),
            EffectParameter(key: "trail",label: "TRAIL LENGTH",range: 4...60,defaultValue: 24,unit: "rows",decimals: 0),
            EffectParameter(key: "ink",label: "INK",range: 0...10,defaultValue: 0,decimals: 0,kind: .choices(["TERMINAL GREEN","MONOCHROME","SOURCE COLOR","CYBER CYAN","ICE BLUE","ULTRAVIOLET","HOT PINK","AMBER","RED ALERT","ACID LIME","CUSTOM HUE"])),
            EffectParameter(key: "reveal",label: "CAMERA REVEAL",range: 0...1,defaultValue: 0.8),
            EffectParameter(key: "fade",label: "GHOST FADE HALF LIFE",range: 0...3,defaultValue: 0.6,unit: "s",decimals: 2),
            EffectParameter(key: "ghost",label: "CAMERA TRAIL",range: 0...1,defaultValue: 0.7),
            EffectParameter(key: "hue",label: "CUSTOM INK HUE",range: 0...360,defaultValue: 145,unit: "deg",decimals: 0)])

    ]
    static func definition(_ id: EffectID) -> EffectDefinition { all.first { $0.id == id }! }
    static func mode(_ mode: Int) -> EffectID { all.first { $0.gpuMode == mode }?.id ?? .clean }
}

struct SignalSettings: Codable, Equatable {
    var activeEffect: EffectID = .clean
    var perEffect: [String: EffectValues] = [:]
    var exposure: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var hue: Float = 0
    var gamma: Float = 1
    var temperature: Float = 6500
    var highlights: Float = 1
    var shadows: Float = 0
    var sharpen: Float = 0
    var grain: Float = 0
    var dither: Float = 0
    var definition: EffectDefinition { EffectRegistry.definition(activeEffect) }
    var current: EffectValues { perEffect[activeEffect.rawValue] ?? EffectValues() }
    // GPU mode is an implementation detail; files and UI use stable IDs.
    var effect: Int { get { definition.gpuMode } set { activeEffect = EffectRegistry.mode(newValue) } }
    var intensity: Float {
        get { current.intensity }
        set { var values = current; values.intensity = newValue.isFinite ? min(1,max(0,newValue)) : 0.7; perEffect[activeEffect.rawValue] = values }
    }
    var seed: UInt32 {
        get { current.seed }
        set { var values = current; values.seed = newValue; perEffect[activeEffect.rawValue] = values }
    }
    func value(_ key: String) -> Float {
        guard let p = definition.parameters.first(where: { $0.key == key }) else { return 0 }
        return p.validated(current.parameters[key] ?? p.defaultValue)
    }
    mutating func set(_ key: String, _ value: Float) {
        guard let descriptor = definition.parameters.first(where: { $0.key == key }) else { return }
        var values = current
        values.parameters[key] = descriptor.validated(value)
        perEffect[activeEffect.rawValue] = values
        if activeEffect == .block && key == "preset" {
            let levels: [Float] = [8,2,4,6,12]
            values.parameters["levels"] = levels[Int(descriptor.validated(value))]
            perEffect[activeEffect.rawValue] = values
        }
        if activeEffect == .solar {
            if key == "low", self.value("high") < self.value("low") + 0.005 { values.parameters["high"] = min(1,self.value("low") + 0.005) }
            if key == "high", self.value("low") > self.value("high") - 0.005 { values.parameters["low"] = max(0,self.value("high") - 0.005) }
            perEffect[activeEffect.rawValue] = values
        }
    }
    func parameter(_ index: Int) -> Float {
        guard definition.parameters.indices.contains(index) else { return 0 }
        return value(definition.parameters[index].key)
    }
    mutating func resetEffect() { perEffect[activeEffect.rawValue] = EffectValues() }
    mutating func resetColor() {
        let id = activeEffect, saved = perEffect
        self = SignalSettings(); activeEffect = id; perEffect = saved
    }
    func normalized() -> SignalSettings {
        var result = self
        let global: [(WritableKeyPath<SignalSettings,Float>,ClosedRange<Float>,Float)] = [
            (\.exposure,-3...3,0),(\.contrast,0.5...2,1),(\.saturation,0...2,1),(\.hue,-180...180,0),
            (\.gamma,0.3...2.5,1),(\.temperature,2500...10000,6500),(\.highlights,0...1,1),(\.shadows,0...1,0),
            (\.sharpen,0...2,0),(\.grain,0...1,0),(\.dither,0...1,0)]
        for (path,range,fallback) in global {
            let v = result[keyPath: path]; result[keyPath: path] = v.isFinite ? min(range.upperBound,max(range.lowerBound,v)) : fallback
        }
        let active = activeEffect
        for definition in EffectRegistry.all {
            result.activeEffect = definition.id
            result.intensity = result.current.intensity
            for parameter in definition.parameters {
                if case .seed = parameter.kind { continue }
                // Validation must not reapply recipes over a saved custom residual level.
                if definition.id == .block && parameter.key == "preset" {
                    var values=result.current
                    values.parameters[parameter.key]=parameter.validated(result.value(parameter.key))
                    result.perEffect[definition.id.rawValue]=values
                } else { result.set(parameter.key,result.value(parameter.key)) }
            }
        }
        result.activeEffect = active
        return result
    }
}

struct SettingsDocument: Codable { var schemaVersion = 1; var settings: SignalSettings }
final class SettingsStore {
    let url: URL
    private(set) var canSave = true
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("FRAME32/settings.json")
    }
    func load() throws -> SignalSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return SignalSettings() }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard envelope?["schemaVersion"] as? Int == 1 else { throw StoreError.newerVersion }
            return try JSONDecoder().decode(SettingsDocument.self,from: data).settings.normalized()
        } catch { canSave = false; throw error }
    }

    func save(_ settings: SignalSettings) throws {
        guard canSave else { throw StoreError.newerVersion }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(SettingsDocument(settings: settings.normalized())).write(to: url,options: .atomic)
    }
    enum StoreError: LocalizedError {
        case newerVersion
        var errorDescription: String? { "Settings file could not be loaded safely; existing file preserved" }
    }
}
