import Foundation
import CoreImage
import CoreVideo
import Metal

/// Synthetic frames only. CPU readback exists here for diagnostics, never in live capture.
enum EffectVerification {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    static func run(device: MTLDevice) throws -> String {
        let processor = try SignalProcessor(device: device)
        let rect = CGRect(x: 0,y: 0,width: 192,height: 108)
        let base = CIFilter(name: "CILinearGradient",parameters: ["inputPoint0": CIVector(x: 0,y: 0),"inputPoint1": CIVector(x: 192,y: 108),"inputColor0": CIColor(red: 0.1,green: 0.2,blue: 0.8),"inputColor1": CIColor(red: 0.9,green: 0.5,blue: 0.2)])!.outputImage!.cropped(to: rect)
        func check(_ condition: Bool,_ message: String) throws { if !condition { throw Failure(message) } }
        func render(_ settings: SignalSettings,time: Float = 3.7,source: CIImage? = nil) throws -> [UInt8] {
            let done = DispatchSemaphore(value: 0)
            var result: CVPixelBuffer?
            processor.submit(source ?? base,settings: settings.normalized(),time: time) { result = $0; done.signal() }
            guard done.wait(timeout: .now()+10) == .success else { throw Failure("GPU completion timeout") }
            guard let result else { throw Failure(processor.advancedInitializationError?.localizedDescription ?? "GPU render failed") }
            CVPixelBufferLockBaseAddress(result,.readOnly)
            defer { CVPixelBufferUnlockBaseAddress(result,.readOnly) }
            let pointer = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(result)
            return (0..<108).flatMap { y in Array(UnsafeBufferPointer(start: pointer+y*rowBytes,count: 192*4)) }
        }
        let clean = try render(SignalSettings())
        try check(clean.contains { $0 > 0 && $0 < 255 },"Empty clean output")
        try check(clean[2] > clean[(107*192)*4+2],"Vertical orientation regression")
        for definition in EffectRegistry.all where definition.id != .clean {
            var settings = SignalSettings(); settings.activeEffect = definition.id; settings.intensity = 1
            processor.resetTemporal()
            let effect = try render(settings)
            if definition.id == .echo || definition.id == .slit {
                let black=CIImage(color: .black).cropped(to: rect)
                let delayed=try render(settings,time: 3.7+1/30,source: black)
                try check(stride(from: 0,to: delayed.count,by: 4).contains { delayed[$0]>5 || delayed[$0+1]>5 || delayed[$0+2]>5 },"\(definition.title) lost its historical image")
            } else {
                try check(effect != clean,"\(definition.title) does not change pixels")
            }
            try check(stride(from: 3,to: effect.count,by: 4).allSatisfy { effect[$0] == 255 },"\(definition.title) alpha is not opaque")
            settings.intensity = 0
            try check(try render(settings) == clean,"\(definition.title) bypass is not clean")
        }
        var solar = SignalSettings(); solar.activeEffect = .solar; solar.intensity = 1
        solar.set("curve",1); solar.set("chroma",1)
        let negative = try render(solar)
        try check(zip(clean,negative).enumerated().allSatisfy { index,pair in index%4 == 3 || abs(Int(pair.0)+Int(pair.1)-255) <= 2 },"Negative mode is not a photographic inversion")
        var displace = SignalSettings(); displace.activeEffect = .displace; displace.intensity = 1
        try check(try render(displace) == render(displace),"Displacement seed/time is nondeterministic")
        let first = try render(displace); displace.seed = UInt32.max
        try check(try render(displace) != first,"Different seeds did not change the field")
        displace.set("amplitude",0)
        try check(try render(displace) == clean,"Zero displacement amplitude changes pixels")
        displace.set("amplitude",12); displace.set("speed",0)
        try check(try render(displace,time: 1) == render(displace,time: 10),"Speed zero does not freeze displacement")
        var exposure = SignalSettings(); exposure.exposure = 1
        try check(try render(exposure) != clean,"Exposure does not change pixels")
        var edge = SignalSettings(); edge.activeEffect = .edge; edge.intensity = 1
        let uniform = CIImage(color: CIColor(red: 0.5,green: 0.5,blue: 0.5)).cropped(to: rect)
        let flatEdges = try render(edge,source: uniform)
        try check(stride(from: 0,to: flatEdges.count,by: 4).allSatisfy { flatEdges[$0] >= 240 },"Uniform frame produces ink contours")
        let step = CIImage(color: .white).cropped(to: CGRect(x: 96,y: 0,width: 96,height: 108)).composited(over: CIImage(color: .black).cropped(to: rect))
        edge.set("width",1)
        let thin = try render(edge,source: step)
        edge.set("width",7)
        let thick = try render(edge,source: step)
        func darkCount(_ bytes: [UInt8]) -> Int { stride(from: 0,to: bytes.count,by: 4).filter { bytes[$0] < 100 }.count }
        try check(darkCount(thick) > darkCount(thin) && darkCount(thin) > 0,"Stroke width does not expand contours")
        var printSettings = SignalSettings(); printSettings.activeEffect = .halftone; printSettings.intensity = 1
        let paper = try render(printSettings,source: CIImage(color: .white).cropped(to: rect))
        let solidInk = try render(printSettings,source: CIImage(color: .black).cropped(to: rect))
        try check(stride(from: 0,to: paper.count,by: 4).allSatisfy { paper[$0] == 255 && paper[$0+1] == 255 && paper[$0+2] == 255 },"Halftone white paper is not white")
        try check(stride(from: 0,to: solidInk.count,by: 4).allSatisfy { solidInk[$0] == 0 && solidInk[$0+1] == 0 && solidInk[$0+2] == 0 },"Halftone black leaves paper holes")
        var matrix = SignalSettings(); matrix.activeEffect = .matrix; matrix.intensity = 1; matrix.set("speed",0)
        processor.resetTemporal()
        let rain = try render(matrix,time: 1,source: CIImage(color: .white).cropped(to: rect))
        try check(stride(from: 0,to: rain.count,by: 4).contains { rain[$0+1] > 40 && Int(rain[$0+1]) > Int(rain[$0+2])*2 },"Matrix glyph atlas has no green ink")
        try check(stride(from: 0,to: rain.count,by: 4).contains { rain[$0+1] < 10 },"Matrix glyph atlas has no background space")
        let frozen = try render(matrix,time: 10,source: CIImage(color: .white).cropped(to: rect))
        try check(rain == frozen,"Zero matrix rain speed does not freeze its output")
        let white = CIImage(color: .white).cropped(to: rect), black = CIImage(color: .black).cropped(to: rect)
        func greenEnergy(_ bytes: [UInt8]) -> Int { stride(from: 1,to: bytes.count,by: 4).reduce(0) { $0+Int(bytes[$1]) } }
        func trailing(_ halfLife: Float) throws -> (Int,Int) {
            var tuning = matrix; tuning.set("fade",halfLife); tuning.set("ghost",1); tuning.set("reveal",0)
            processor.resetTemporal()
            _ = try render(tuning,time: 0,source: white)
            var early = 0, late = 0
            for frame in 1...16 {
                let output = try render(tuning,time: Float(frame)/30,source: black)
                if frame == 2 { early = greenEnergy(output) }
                if frame == 16 { late = greenEnergy(output) }
            }
            return (early,late)
        }
        let shortTrail = try trailing(0.12), longTrail = try trailing(1.2)
        try check(shortTrail.0 > shortTrail.1,"Ghost trail does not fade after source movement stops")
        try check(longTrail.1 > shortTrail.1,"Longer ghost half-life does not retain a longer trail")
        func channels(_ bytes: [UInt8]) -> [Int] {
            (0..<3).map { channel in stride(from: channel,to: bytes.count,by: 4).reduce(0) { $0+Int(bytes[$1]) } }
        }
        var tinted = matrix; tinted.set("ghost",0); tinted.set("ink",6)
        processor.resetTemporal()
        let pink = channels(try render(tinted,time: 1,source: white))
        try check(pink[2] > pink[1]*2 && pink[0] > pink[1]*2,"Hot pink ink does not tint glyphs")
        tinted.set("ink",10); tinted.set("hue",240)
        let blue = channels(try render(tinted,time: 1,source: white))
        try check(blue[0] > blue[1]*2 && blue[0] > blue[2]*2,"Custom hue does not produce blue ink")
        var contour=SignalSettings(); contour.activeEffect = .contour; contour.intensity=0.5
        contour.set("paper",1); contour.set("fade",0); contour.set("cameraColor",1)
        let coloredFlat=CIImage(color: CIColor(red: 0.8,green: 0.2,blue: 0.1)).cropped(to: rect)
        let monoCamera=try render(contour,source: coloredFlat)
        var neutralCamera=true
        for index in stride(from: 0,to: monoCamera.count,by: 4) {
            let blue=Int(monoCamera[index]),green=Int(monoCamera[index+1]),red=Int(monoCamera[index+2])
            if abs(blue-green)>1 || abs(green-red)>1 { neutralCamera=false; break }
        }
        try check(neutralCamera,"Contour monochrome camera leaks source chroma")
        contour.set("cameraColor",0)
        try check(try render(contour,source: coloredFlat) != monoCamera,"Contour camera color mode does not change the camera layer")
        contour.set("cameraColor",1); contour.intensity=0
        try check(try render(contour,source: coloredFlat) == render(SignalSettings(),source: coloredFlat),"Contour mono breaks intensity-zero bypass")
        var hatch=SignalSettings(); hatch.activeEffect = .hatch; hatch.intensity=1
        hatch.set("scale",1)
        let fineHatch=try render(hatch,source: uniform)
        hatch.set("scale",6)
        try check(try render(hatch,source: uniform) != fineHatch,"Hatch stroke scale does not enlarge the pattern")
        // Keyed fills must stay exact green at partial intensity, not mix into the camera.
        var keyed=SignalSettings(); keyed.activeEffect = .paint; keyed.intensity=0.4
        keyed.set("fill",2); keyed.set("threshold",1)
        let greenKey=try render(keyed)
        var exactKey=true
        for n in stride(from: 0,to: greenKey.count,by: 4) {
            if greenKey[n] != 0 || greenKey[n+1] != 255 || greenKey[n+2] != 0 { exactKey=false; break }
        }
        try check(exactKey,"Paint greenscreen fill is not exact green at partial intensity")
        keyed.intensity=1; keyed.set("fill",0); keyed.set("threshold",0)
        let selectivePaint=try render(keyed)
        keyed.set("threshold",1)
        processor.resetTemporal()
        try check(try render(keyed) != selectivePaint,"Paint threshold does not change coverage")
        var paperLook=SignalSettings(); paperLook.activeEffect = .ascii; paperLook.intensity=1
        paperLook.set("color",1); paperLook.set("invert",1)
        let lightPaper=try render(paperLook)
        paperLook.set("invert",2)
        let darkPaper=try render(paperLook)
        var inversePaper=true
        for n in lightPaper.indices where n%4 != 3 {
            if abs(Int(lightPaper[n])+Int(darkPaper[n])-255)>1 { inversePaper=false; break }
        }
        try check(inversePaper,"Dark paper is not the exact inverse of light paper")
        // Echo ink must leave the incoming first frame untouched.
        var echoInk=SignalSettings(); echoInk.activeEffect = .echo; echoInk.intensity=1
        echoInk.set("ink",3); processor.resetTemporal()
        try check(try render(echoInk,time: 0) == clean,"Echo-only ink changed the incoming camera on first use")
        var slitInk=SignalSettings(); slitInk.activeEffect = .slit; slitInk.intensity=1
        slitInk.set("ink",3); processor.resetTemporal()
        let negativeSlit=try render(slitInk,time: 0)
        slitInk.set("ink",0); processor.resetTemporal()
        try check(try render(slitInk,time: 0) != negativeSlit,"Slit ink does not affect historical slices")
        var shaped=SignalSettings(); shaped.activeEffect = .cells; shaped.intensity=1
        shaped.set("shape",1); let squareCells=try render(shaped)
        shaped.set("shape",4)
        try check(try render(shaped) != squareCells,"Cell shape selection has no visual effect")
        var movingVeil=SignalSettings(); movingVeil.activeEffect = .dataveil; movingVeil.intensity=1
        movingVeil.set("drift",80); movingVeil.set("reveal",0)
        func veilAtAngle(_ degrees: Float) throws -> [UInt8] {
            movingVeil.set("angle",degrees); processor.resetTemporal()
            _=try render(movingVeil,time: 0,source: step)
            return try render(movingVeil,time: 0.1,source: black)
        }
        let horizontalVeil=try veilAtAngle(0),verticalVeil=try veilAtAngle(90)
        try check(horizontalVeil != verticalVeil,"Dataveil angle does not change feedback drift")
        var timedMosh=SignalSettings(); timedMosh.activeEffect = .mosh; timedMosh.intensity=1
        timedMosh.set("interval",1); timedMosh.set("window",0.1); timedMosh.set("hold",0.5)
        processor.resetTemporal()
        _=try render(timedMosh,time: 0,source: white)
        let heldMosh=try render(timedMosh,time: 0.2,source: black)
        processor.resetTemporal()
        _=try render(timedMosh,time: 0.9,source: white)
        let refreshedMosh=try render(timedMosh,time: 1.02,source: black)
        try check(greenEnergy(heldMosh)>greenEnergy(refreshedMosh),"Mosh hold/keyframe timing does not control image refresh")
        // Download only diagnostic float particle state, never live capture pixels.
        func particleState(_ texture: MTLTexture) throws -> [SIMD4<Float>] {
            let rowBytes=((texture.width*16+255)/256)*256
            guard let buffer=device.makeBuffer(length: rowBytes*texture.height,options: .storageModeShared),
                  let command=processor.commands.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else { throw Failure("Particle diagnostic allocation failed") }
            blit.copy(from: texture,sourceSlice: 0,sourceLevel: 0,sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),sourceSize: MTLSize(width: texture.width,height: texture.height,depth: 1),to: buffer,destinationOffset: 0,destinationBytesPerRow: rowBytes,destinationBytesPerImage: rowBytes*texture.height)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed else { throw Failure("Particle diagnostic copy failed") }
            return (0..<texture.height).flatMap { y in
                Array(UnsafeBufferPointer(start: buffer.contents().advanced(by: y*rowBytes).assumingMemoryBound(to: SIMD4<Float>.self),count: texture.width))
            }
        }
        let checker=CIFilter(name: "CICheckerboardGenerator",parameters: ["inputWidth": 12,"inputSharpness": 1])!.outputImage!
        let shiftedChecker=checker.transformed(by: CGAffineTransform(translationX: 2,y: 0)).cropped(to: rect)
        var flight=SignalSettings(); flight.activeEffect = .particles; flight.intensity=1
        flight.set("trigger",1); flight.set("drag",0); flight.set("flight",2); flight.set("fade",0)
        processor.resetTemporal()
        _=try render(flight,time: 0,source: checker.cropped(to: rect))
        _=try render(flight,time: 1/30,source: shiftedChecker)
        guard let flying=processor.advanced?.state else { throw Failure("Particle state missing") }
        let firstFlight=try particleState(flying.simulation[1-flying.simulationNext])
        _=try render(flight,time: 2/30,source: shiftedChecker)
        let secondFlight=try particleState(flying.simulation[1-flying.simulationNext])
        var continuedFlight=false
        for n in firstFlight.indices {
            let v=firstFlight[n],next=secondFlight[n]
            let speedSquared=v.z*v.z+v.w*v.w
            let forward=(next.x-v.x)*v.z+(next.y-v.y)*v.w
            if speedSquared>0.001 && forward>0 { continuedFlight=true; break }
        }
        try check(continuedFlight,"Particles did not continue flying after the motion impulse stopped")
        // Bounded sorting must order eligible pixels and preserve exact separators.
        var sorted=SignalSettings(); sorted.activeEffect = .sort; sorted.intensity=1
        sorted.set("length",32); sorted.set("low",0); sorted.set("high",1); sorted.set("style",0)
        let ascending=try render(sorted)
        sorted.set("reverse",1)
        let descending=try render(sorted)
        try check(ascending != descending,"Sort order control has no effect")
        func byteLuma(_ bytes: [UInt8],_ x: Int,_ y: Int)->Float {
            let n=(y*192+x)*4
            return Float(bytes[n])*0.0722+Float(bytes[n+1])*0.7152+Float(bytes[n+2])*0.2126
        }
        for x in 1..<32 {
            try check(byteLuma(ascending,x,54)+1 >= byteLuma(ascending,x-1,54),"Pixel sort is not ascending inside its segment")
            try check(byteLuma(descending,x,54) <= byteLuma(descending,x-1,54)+1,"Pixel sort is not descending inside its segment")
        }
        sorted.set("low",1); sorted.set("high",1)
        try check(try render(sorted) == clean,"Sort modified an excluded segment")
        var echo=SignalSettings(); echo.activeEffect = .echo; echo.intensity=1
        echo.set("zoom",0); echo.set("rotation",0); echo.set("drift",0); echo.set("mix",1)
        echo.set("fade",0.5)
        processor.resetTemporal()
        _=try render(echo,time: 0,source: white)
        let earlier=try render(echo,time: 0.1,source: black)
        let later=try render(echo,time: 0.2,source: black)
        try check(greenEnergy(earlier)>greenEnergy(later) && greenEnergy(later)>0,"Echo history does not decay")
        processor.resetTemporal()
        let resetEcho=try render(echo,time: 0.3,source: black)
        try check(greenEnergy(resetEcho)==0,"Temporal reset retained an old image")
        var relief=SignalSettings(); relief.activeEffect = .raster; relief.intensity=1
        relief.set("fade",0)
        let reliefBefore=try render(relief,time: 1)
        relief.set("depth",0)
        let reliefFlat=try render(relief,time: 1)
        try check(reliefBefore != reliefFlat,"Relief extrusion has no geometry effect")
        // Exercise simulation initialization, discontinuity reset, extreme controls and resource cleanup.
        for id: EffectID in [.particles,.growth,.cells,.fluid,.paint,.mosh,.dataveil] {
            var tuning=SignalSettings(); tuning.activeEffect=id; tuning.intensity=1
            processor.resetTemporal()
            _=try render(tuning,time: 0)
            _=try render(tuning,time: 1/30,source: step)
            for parameter in tuning.definition.parameters { tuning.set(parameter.key,parameter.range.upperBound) }
            let extreme=try render(tuning,time: 2/30)
            try check(stride(from: 3,to: extreme.count,by: 4).allSatisfy { extreme[$0]==255 },"Simulation extreme produced invalid alpha")
            _=try render(tuning,time: 4) // Discontinuity must reinitialize active history.
            try check((processor.advanced?.state?.allocatedBytes ?? 0)<32*1024*1024,"Synthetic simulation resources exceeded their bound")
        }
        _ = try render(SignalSettings())
        try check(processor.advanced?.state == nil,"Inactive advanced effect resources were retained")
        try check(processor.matrixResources == nil && processor.edgeResources == nil,"Inactive effect resources were retained")
        let count = EffectRegistry.all.count-1
        return "PASS / \(count) EFFECTS / BYPASS / ORIENTATION / EDGE / PRINT / MATRIX / FADE / INK / COLOR / GEOMETRY / HISTORY / SORT / SIMULATION / INERTIA / KEYFILL / INK / TIMING"
    }
}
