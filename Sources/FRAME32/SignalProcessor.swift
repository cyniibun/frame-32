import AppKit
import CoreImage
import Metal
import CoreVideo

/// Two frames in flight. One color pass and one fused signal pass; output is shared by preview and writer.
final class SignalProcessor {
    var onError: ((String)->Void)?
    let device: MTLDevice
    let context: CIContext
    let commands: MTLCommandQueue
    let pipeline: MTLComputePipelineState
    let edgePipelines: [MTLComputePipelineState]
    let coverage: MTLTexture
    let advanced: AdvancedEffects?
    let advancedInitializationError: Error?
    let glyphs: MTLTexture
    let matrixPipeline: MTLComputePipelineState
    final class MatrixResources {
        let textures: [MTLTexture]
        let cell: Float
        var next = 0
        var valid = false
        var lastTime: Float?
        init(textures: [MTLTexture],cell: Float) { self.textures = textures; self.cell = cell }
    }
    var matrixResources: MatrixResources?
    struct EdgeResources { let mask: MTLTexture; let horizontal: MTLTexture; let width: Int; let height: Int }
    var edgeResources: EdgeResources?
    var cache: CVMetalTextureCache!
    var pool: CVPixelBufferPool?
    var dimensions = CGSize.zero
    let slots = DispatchSemaphore(value: 2)
    init(device: MTLDevice) throws {
        self.device = device
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        commands = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: SpatialKernels.source + "\n" + Self.shader, options: nil)
        pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "signal")!)
        matrixPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "matrixCells")!)
        edgePipelines = try ["edgeGradient","edgeHorizontal","edgeVertical"].map { name in
            try device.makeComputePipelineState(function: library.makeFunction(name: name)!)
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D; descriptor.pixelFormat = .r32Float; descriptor.width = 256; descriptor.height = 1; descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let lookup = device.makeTexture(descriptor: descriptor) else { throw GPUError.allocation }
        var radii = HalftoneCoverage.table()
        lookup.replace(region: MTLRegionMake1D(0,256),mipmapLevel: 0,withBytes: &radii,bytesPerRow: radii.count*MemoryLayout<Float>.size)
        coverage = lookup
        glyphs = try GlyphAtlas.make(device: device)
        do {
            advanced = try AdvancedEffects(device: device,glyphs: glyphs)
            advancedInitializationError = nil
        } catch {
            // A failed experimental pipeline must not take down the accepted camera/effect bank.
            advanced = nil; advancedInitializationError = error
            Self.recordGPUFailure(error.localizedDescription,stage: "ADVANCED INITIALIZATION")
        }
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }
    func color(_ image: CIImage, _ s: SignalSettings) -> CIImage {
        var result = image
        if s.exposure != 0 { result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: s.exposure]) }
        if s.contrast != 1 || s.saturation != 1 { result = result.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: s.contrast, kCIInputSaturationKey: s.saturation]) }
        if s.hue != 0 { result = result.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: s.hue * .pi / 180]) }
        if s.gamma != 1 { result = result.applyingFilter("CIGammaAdjust", parameters: ["inputPower": s.gamma]) }
        if s.temperature != 6500 { result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: CGFloat(s.temperature), y: 0)]) }
        if s.highlights != 1 || s.shadows != 0 { result = result.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": s.highlights, "inputShadowAmount": s.shadows]) }
        if s.sharpen > 0 { result = result.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: s.sharpen]) }
        return result.cropped(to: image.extent)
    }
    func submit(_ image: CIImage, settings: SignalSettings, time: Float, completion: @escaping (CVPixelBuffer?) -> Void) {
        guard slots.wait(timeout: .now()) == .success else { completion(nil); return }
        let width = Int(image.extent.width), height = Int(image.extent.height)
        if dimensions != image.extent.size {
            dimensions = image.extent.size
            CVPixelBufferPoolCreate(nil, nil, [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height, kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pool)
        }
        guard let pool else { slots.signal(); completion(nil); return }
        var input: CVPixelBuffer?, output: CVPixelBuffer?
        let aux = [kCVPixelBufferPoolAllocationThresholdKey: 8] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, aux, &input) == kCVReturnSuccess,
              CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, aux, &output) == kCVReturnSuccess,
              let input, let output else { slots.signal(); completion(nil); return }
        var sourceWrapper: CVMetalTexture?, targetWrapper: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, input, nil, .bgra8Unorm, width, height, 0, &sourceWrapper)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, output, nil, .bgra8Unorm, width, height, 0, &targetWrapper)
        guard let sourceWrapper, let targetWrapper, let source = CVMetalTextureGetTexture(sourceWrapper), let target = CVMetalTextureGetTexture(targetWrapper), let command = commands.makeCommandBuffer() else { slots.signal(); completion(nil); return }
        context.render(color(image, settings), to: source, commandBuffer: command, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        var uniforms: [Float] = [Float(settings.effect), settings.intensity, settings.parameter(0), settings.parameter(1), settings.parameter(2), time, settings.grain, settings.dither, settings.parameter(3), settings.parameter(4), 1.0/30.0, settings.parameter(5), settings.parameter(6), settings.parameter(7)]
        uniforms += (8..<16).map { settings.parameter($0) }
        var seed = settings.seed
        var currentEdge: EdgeResources?
        if settings.activeEffect == .edge && settings.intensity > 0 {
            do { currentEdge = try prepareEdge(width: width,height: height) }
            catch { slots.signal(); completion(nil); return }
            guard let resources = currentEdge else { slots.signal(); completion(nil); return }
            let inputs = [source,resources.mask,resources.horizontal]
            let outputs = [resources.mask,resources.horizontal,resources.mask]
            for index in 0..<3 {
                guard let pass = command.makeComputeCommandEncoder() else { slots.signal(); completion(nil); return }
                let state = edgePipelines[index]
                pass.setComputePipelineState(state); pass.setTexture(inputs[index],index: 0); pass.setTexture(outputs[index],index: 1)
                pass.setBytes(&uniforms,length: uniforms.count*MemoryLayout<Float>.size,index: 0)
                dispatch(pass,pipeline: state,width: width,height: height); pass.endEncoding()
            }
        } else { edgeResources = nil }
        var currentMatrix: MatrixResources?
        var matrixTexture: MTLTexture?
        if settings.activeEffect == .matrix {
            do { currentMatrix = try prepareMatrix(width: width,height: height,cell: settings.parameter(0)) }
            catch { slots.signal(); completion(nil); return }
            guard let resources = currentMatrix, let pass = command.makeComputeCommandEncoder() else { slots.signal(); completion(nil); return }
            let next = resources.textures[resources.next], previous = resources.textures[1-resources.next]
            let delta = resources.lastTime.map { time-$0 } ?? (1.0/30.0)
            if delta <= 0 || delta > 0.5 { resources.valid = false }
            uniforms[10] = min(0.5,max(1.0/240.0,delta > 0 ? delta : 1.0/30.0))
            resources.lastTime = time
            var hasHistory: UInt32 = resources.valid ? 1 : 0
            pass.setComputePipelineState(matrixPipeline)
            pass.setTexture(source,index: 0); pass.setTexture(previous,index: 1); pass.setTexture(next,index: 2)
            pass.setBytes(&uniforms,length: uniforms.count*MemoryLayout<Float>.size,index: 0)
            pass.setBytes(&hasHistory,length: MemoryLayout<UInt32>.size,index: 1)
            dispatch(pass,pipeline: matrixPipeline,width: next.width,height: next.height); pass.endEncoding()
            matrixTexture = next; resources.next = 1-resources.next; resources.valid = true
        } else { matrixResources = nil }
        var advancedOutput: MTLTexture?
        var currentAdvanced: AdvancedEffects.State?
        if settings.effect >= 10 && settings.intensity > 0 {
            do {
                guard let advanced else { throw advancedInitializationError ?? GPUError.allocation }
                let result = try advanced.encode(source: source,command: command,settings: settings,time: time,glyphs: glyphs)
                advancedOutput=result.0; currentAdvanced=result.1
            } catch {
                advanced?.state=nil
                Self.recordGPUFailure(error.localizedDescription,stage: "ENCODE " + settings.definition.title)
                onError?(error.localizedDescription); slots.signal(); completion(nil); return
            }
        } else { advanced?.state=nil }
        guard let encoder = command.makeComputeCommandEncoder() else { slots.signal(); completion(nil); return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(target, index: 1)
        encoder.setTexture(currentEdge?.mask ?? source,index: 2)
        encoder.setTexture(coverage,index: 3)
        encoder.setTexture(glyphs,index: 4)
        encoder.setTexture(matrixTexture ?? source,index: 5)
        encoder.setTexture(advancedOutput ?? source,index: 6)
        encoder.setBytes(&uniforms, length: uniforms.count * MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&seed,length: MemoryLayout<UInt32>.size,index: 1)
        dispatch(encoder,pipeline: pipeline,width: width,height: height)
        encoder.endEncoding()
        let errorHandler=onError
        command.addCompletedHandler { [slots] command in
            withExtendedLifetime((input, sourceWrapper, targetWrapper, currentEdge, currentMatrix, currentAdvanced)) {
                if command.status != .completed {
                    let message=command.error?.localizedDescription ?? "GPU command failed"
                    Self.recordGPUFailure(message,stage: "COMMAND BUFFER")
                    errorHandler?(message)
                }
                completion(command.status == .completed ? output : nil)
                slots.signal()
            }
        }
        command.commit()
    }
    func dispatch(_ encoder: MTLComputeCommandEncoder,pipeline: MTLComputePipelineState,width: Int,height: Int) {
        let groupWidth = min(16,pipeline.threadExecutionWidth)
        let groupHeight = min(16,max(1,pipeline.maxTotalThreadsPerThreadgroup/groupWidth))
        encoder.dispatchThreads(MTLSize(width: width,height: height,depth: 1),threadsPerThreadgroup: MTLSize(width: groupWidth,height: groupHeight,depth: 1))
    }
    func prepareEdge(width: Int,height: Int) throws -> EdgeResources {
        if let existing = edgeResources, existing.width == width && existing.height == height { return existing }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float,width: width,height: height,mipmapped: false)
        descriptor.storageMode = .private; descriptor.usage = [.shaderRead,.shaderWrite]
        guard let mask = device.makeTexture(descriptor: descriptor) else { throw GPUError.allocation }
        descriptor.pixelFormat = .rg16Float
        guard let horizontal = device.makeTexture(descriptor: descriptor) else { throw GPUError.allocation }
        let result = EdgeResources(mask: mask,horizontal: horizontal,width: width,height: height)
        edgeResources = result; return result
    }
    func resetTemporal() { matrixResources = nil; advanced?.state = nil }
    func prepareMatrix(width: Int,height: Int,cell: Float) throws -> MatrixResources {
        let columns = Int(ceil(Float(width)/cell)), rows = Int(ceil(Float(height)/(cell*1.5)))
        if let existing = matrixResources, existing.textures[0].width == columns, existing.textures[0].height == rows, existing.cell == cell { return existing }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,width: columns,height: rows,mipmapped: false)
        descriptor.storageMode = .private; descriptor.usage = [.shaderRead,.shaderWrite]
        guard let a = device.makeTexture(descriptor: descriptor), let b = device.makeTexture(descriptor: descriptor) else { throw GPUError.allocation }
        let resources = MatrixResources(textures: [a,b],cell: cell); matrixResources = resources; return resources
    }
    static func recordGPUFailure(_ message: String,stage: String) {
        let folder=FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("FRAME32")
        let version=Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "command-line"
        let fingerprint=Bundle.main.infoDictionary?["FRAME32GPUFingerprint"] as? String ?? "unknown"
        let report="FRAME32 " + version + "\n" + ISO8601DateFormatter().string(from: Date()) + "\nGPU SOURCE " + fingerprint + "\nSTAGE " + stage + "\n" + message + "\n"
        do {
            try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
            try report.write(to: folder.appendingPathComponent("gpu-error-report.txt"),atomically: true,encoding: .utf8)
        } catch { NSLog("FRAME32 diagnostic write failed: %@",error.localizedDescription) }
    }
    enum GPUError: LocalizedError {
        case allocation
        var errorDescription: String? { "GPU texture allocation failed" }
    }
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    float hash(float2 p) { return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }
    uint ihash(uint x) { x ^= x>>16; x *= 0x7feb352du; x ^= x>>15; x *= 0x846ca68bu; return x^(x>>16); }
    float seeded(int2 p, uint seed) { return float(ihash(as_type<uint>(p.x)*0x9e3779b9u ^ as_type<uint>(p.y)*0x85ebca6bu ^ seed)>>8) / 16777216.0; }
    float noise(float2 p, uint seed) {
        int2 cell=int2(floor(p)); float2 f=fract(p); f=f*f*(3.0-2.0*f);
        return mix(mix(seeded(cell,seed),seeded(cell+int2(1,0),seed),f.x),mix(seeded(cell+int2(0,1),seed),seeded(cell+int2(1,1),seed),f.x),f.y);
    }
    float3 hueRotate(float3 c,float angle) {
        // YIQ rotation retains neutral grays; clamp occurs after the final blend.
        float y=dot(c,float3(0.299,0.587,0.114));
        float i=dot(c,float3(0.596,-0.274,-0.322)), q=dot(c,float3(0.211,-0.523,0.312));
        float ii=i*cos(angle)-q*sin(angle), qq=i*sin(angle)+q*cos(angle);
        return float3(y+0.956*ii+0.621*qq,y-0.272*ii-0.647*qq,y-1.106*ii+1.703*qq);
    }
    kernel void signal(texture2d<float,access::sample> src [[texture(0)]], texture2d<float,access::write> dst [[texture(1)]], constant float *p [[buffer(0)]], constant uint &seed [[buffer(1)]], texture2d<float,access::read> edgeMask [[texture(2)]], texture1d<float,access::sample> coverage [[texture(3)]], texture2d<float,access::sample> glyphs [[texture(4)]], texture2d<float,access::read> matrixState [[texture(5)]], texture2d<float,access::sample> advancedOutput [[texture(6)]], uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        constexpr sampler smp(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 sz=float2(dst.get_width(),dst.get_height()), uv=(float2(id)+0.5)/sz;
        uv.y=1.0-uv.y;
        float3 clean=src.sample(smp,uv).rgb, c=clean;
        int mode=int(p[0]); float strength=p[1], amount=p[2], speed=p[3], scale=p[4], t=p[5];
        if(mode==1) {
            float2 radial=(uv-0.5)*(0.25+scale*1.75);
            float2 shift=float2((2.0+amount*30.0)/sz.x,0)*(0.75+0.25*sin(t*(0.3+speed*4.0)));
            shift+=radial*(amount*0.018);
            c=float3(src.sample(smp,uv+shift).r,clean.g,src.sample(smp,uv-shift).b);
        } else if(mode==2) {
            float levels=round(2.0+(1.0-amount)*14.0);
            const float bayer[16]={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5};
            uint cell=max(1u,uint(1.0+scale*5.0));
            float d=(bayer[((id.y/cell)%4)*4+((id.x/cell)%4)]/16.0-0.5)*(0.25+speed*0.75);
            c=floor(clamp(clean+d/levels,0.0,1.0)*(levels-1.0)+0.5)/(levels-1.0);
        } else if(mode==3) {
            float2 xy=uv*2.0-1.0; xy*=1.0+dot(xy,xy)*0.035*amount;
            float2 q=xy*0.5+0.5;
            c=src.sample(smp,q).rgb;
            float scan=0.5+0.5*cos(uv.y*sz.y*3.14159265/(1.0+scale*2.0));
            c*=1.0-scan*(0.15+amount*0.5);
            uint channel=id.x%3;
            c*=float3(channel==0?1.0:0.78,channel==1?1.0:0.78,channel==2?1.0:0.78);
            c*=1.0-0.18*dot(xy,xy);
            c*=1.0+0.018*speed*sin(t*47.0);
            if(any(q<0.0)||any(q>1.0)) c=0;
        } else if(mode==4) {
            float tick=floor(t*(2.0+speed*22.0));
            float band=floor(uv.y*(12.0+scale*90.0));
            float rnd=hash(float2(band,tick));
            float gate=step(0.66-amount*0.35,rnd);
            float offset=(rnd-0.5)*amount*0.26*gate;
            float2 q=float2(fract(uv.x+offset),uv.y);
            c=src.sample(smp,q).rgb;
            float rgb=(amount*0.012+0.001)*gate;
            c.r=src.sample(smp,q+float2(rgb,0)).r;
            c.b=src.sample(smp,q-float2(rgb,0)).b;
            float line=step(0.985,hash(float2(floor(uv.y*sz.y),tick)));
            c=mix(c,float3(hash(float2(id)+tick)),line*amount*0.7);
        }
        if(mode==5) {
            float y=dot(clean,float3(0.2126,0.7152,0.0722));
            float low=p[2], high=max(low+0.005,p[3]);
            float gate=smoothstep(low,high,y);
            int curve=int(p[4]);
            if(curve==0) {
                float sy=mix(y,1.0-y,gate);
                c=clamp(clean*(sy/max(y,0.001)),0.0,1.0);
                c=mix(float3(sy),c,p[8]);
            } else {
                c=curve==1 ? 1.0-clean : mix(clean,1.0-clean,gate);
                c=mix(float3(dot(c,float3(0.2126,0.7152,0.0722))),c,p[8]);
            }
            c=hueRotate(c,p[9]*0.01745329252);
        } else if(mode==6) {
            float amplitude=p[2], frequency=p[3], tears=p[4], speedHz=p[8];
            float phase=t*speedHz;
            float2 pos=float2(uv.x*frequency*0.35,uv.y*frequency);
            float swim=(noise(pos+float2(phase*0.27,phase*0.13),seed)-0.5)*1.35;
            swim+=(noise(pos*2.03+float2(-phase*0.19,phase*0.31),seed^0xa511e9b3u)-0.5)*0.65;
            int band=int(floor(uv.y*(12.0+frequency*2.0)));
            int tick=int(floor(phase*4.0));
            float event=seeded(int2(band,tick),seed^0x63d83595u);
            float tear=event>1.0-tears ? (seeded(int2(band,tick+97),seed)-0.5)*2.0 : 0.0;
            float jitter=sin(phase*6.2831853+uv.y*17.0)*0.12;
            float2 shift=float2(amplitude*(swim+tear+jitter)/sz.x,0.0);
            c=src.sample(smp,uv+shift).rgb;
        }
        if(mode==7 && strength>0.0) {
            float mask=edgeMask.read(id).r;
            int surface=int(p[8]); bool light=p[9]>0.5;
            float3 background=surface==0 ? float3(light ? 0.025 : 0.95) : clean;
            if(surface==2) background=floor(clean*3.0+0.5)/3.0;
            c=mix(background,float3(light ? 0.95 : 0.015),mask);
        } else if(mode==8) {
            c=printScreen(src,coverage,uv,sz,p);
        }
        if(mode==9) {
            float2 cellSize=float2(p[2],p[2]*1.5);
            float2 screen=float2(id)+0.5;
            int2 cell=int2(floor(screen/cellSize));
            float rows=ceil(sz.y/cellSize.y);
            float columnRandom=seeded(int2(cell.x,71),seed);
            float columnSpeed=p[3]*(0.55+columnRandom*0.9);
            float cycle=rows+p[4];
            float head=fmod(t*columnSpeed+columnRandom*cycle,cycle);
            float age=fmod(head-float(cell.y)+cycle,cycle);
            float trail=age<p[4] ? exp(-age/max(1.0,p[4]*0.28)) : 0.0;
            float2 center=(float2(cell)+0.5)*cellSize/sz; center.y=1.0-center.y;
            float3 camera=src.sample(smp,center).rgb;
            float luma=dot(camera,float3(0.2126,0.7152,0.0722));
            float motion=floor(t*p[3]*0.8);
            float glyphChoice=seeded(cell+int2(int(motion),0),seed^0x94d049bbu);
            uint glyph=min(31u,uint(floor(glyphChoice*32.0)));
            float2 local=fract(screen/cellSize);
            float2 atlasPixel=float2(glyph%16*16,glyph/16*24)+float2(0.5)+local*float2(15,23);
            float mask=glyphs.sample(smp,atlasPixel/float2(256,48)).r;
            float4 history=matrixState.read(uint2(cell));
            float movement=history.g;
            float ghost=(max(0.0,history.b-luma)+history.a)*p[12];
            float brightness=clamp((0.06+pow(luma,0.7)*p[9])*0.8+trail*0.9+movement*0.4+ghost*0.65,0.0,1.0);
            int colorMode=int(p[8]);
            float3 ink=float3(0.04,1.0,0.24);
            if(colorMode==1) ink=float3(1.0);
            else if(colorMode==2) ink=camera*1.25+0.1;
            else if(colorMode==3) ink=float3(0.0,0.95,1.0);
            else if(colorMode==4) ink=float3(0.24,0.52,1.0);
            else if(colorMode==5) ink=float3(0.57,0.12,1.0);
            else if(colorMode==6) ink=float3(1.0,0.05,0.48);
            else if(colorMode==7) ink=float3(1.0,0.57,0.02);
            else if(colorMode==8) ink=float3(1.0,0.06,0.03);
            else if(colorMode==9) ink=float3(0.6,1.0,0.01);
            else if(colorMode==10) {
                float hue=fract(p[13]/360.0);
                float3 rgb=clamp(abs(fract(float3(hue)+float3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
                ink=mix(float3(1.0),rgb,0.94);
            }
            ink=mix(ink,float3(1.0),trail*0.25);
            c=ink*brightness*mask;
        }
        if(mode>=10 && strength>0) c=advancedOutput.sample(smp,uv).rgb;
        // The camera underneath contour ink can be monochrome independently of the glow hue.
        // Exact zero intensity remains the unmodified color-adjusted bypass.
        if(mode==11 && p[13]>0.5 && strength>0) clean=float3(dot(clean,float3(0.2126,0.7152,0.0722)));
        c=mix(clean,c,strength);
        // Interior key pixels remain exact key colors even at partial effect intensity.
        if(mode==16 && strength>0 && (p[14]==2 || p[14]==3)) {
            float3 key=p[14]==2 ? float3(0,1,0) : float3(0,0,1);
            if(distance(advancedOutput.sample(smp,uv).rgb,key)<0.001) c=key;
        }
        float n=hash(float2(id)+floor(t*30.0)*13.0)-0.5;
        c+=n*p[6]*0.15;
        c+=((float((id.x+id.y)%2)*2.0-1.0)/255.0)*p[7];
        dst.write(float4(clamp(c,0.0,1.0),1),id);
    }
    """
}
