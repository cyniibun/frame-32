import Foundation
import Metal

/// Active-effect-only resources. All passes share the capture queue's ordered command buffers.
/// Upstream snapshots are research references; these are native FRAME32 implementations.
final class AdvancedEffects {
    let device: MTLDevice
    let compute: [String: MTLComputePipelineState]
    let geometry: MTLRenderPipelineState
    let dummyRing: MTLTexture
    let glyphOrder: MTLBuffer
    var state: State?
    final class State {
        let id: EffectID
        let seed: UInt32
        let width: Int, height: Int
        let output: [MTLTexture]
        let previous: MTLTexture
        let field: MTLTexture
        let geometry: MTLTexture?
        let life: [MTLTexture]
        let colors: [MTLTexture]
        let shape: Int
        let simulation: [MTLTexture]
        let slit: MTLTexture?
        var next = 0, simulationNext = 0, slitNext = 0
        var valid = false
        var lastTime: Float?
        var slitTimes = [Float](repeating: -1,count: 8)
        let structural: Int
        init(id: EffectID,seed: UInt32,width: Int,height: Int,output: [MTLTexture],previous: MTLTexture,field: MTLTexture,geometry: MTLTexture?,simulation: [MTLTexture],life: [MTLTexture],colors: [MTLTexture],slit: MTLTexture?,structural: Int,shape: Int) {
            self.life=life; self.colors=colors; self.shape=shape; self.id=id; self.seed=seed; self.width=width; self.height=height; self.output=output; self.previous=previous; self.field=field; self.geometry=geometry; self.simulation=simulation; self.slit=slit; self.structural=structural
        }
        var allocatedBytes: Int {
            let textures=output+[previous,field]+simulation+life+colors+[geometry,slit].compactMap{$0}
            return textures.reduce(0) { total,t in
                let bytes: Int = t.pixelFormat == .rgba32Float ? 16 : (t.pixelFormat == .rgba16Float ? 8 : 4)
                return total+t.width*t.height*t.arrayLength*bytes
            }
        }
    }
    init(device: MTLDevice,glyphs: MTLTexture) throws {
        self.device=device
        let library=try device.makeLibrary(source: Self.shader,options: nil)
        var states: [String: MTLComputePipelineState]=[:]
        for name in ["analysisField","advancedImage","updateSites","updateParticles","growInk","boundedSort"] {
            guard let f=library.makeFunction(name: name) else { throw SignalProcessor.GPUError.allocation }
            states[name]=try device.makeComputePipelineState(function: f)
        }
        compute=states
        let descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name: "portraitVertex")
        descriptor.fragmentFunction=library.makeFunction(name: "portraitFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.colorAttachments[0].isBlendingEnabled=true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        geometry=try device.makeRenderPipelineState(descriptor: descriptor)
        // Measured atlas coverage, computed once. No glyph analysis/readback during capture.
        var bytes=[UInt8](repeating: 0,count: GlyphAtlas.width*GlyphAtlas.height)
        glyphs.getBytes(&bytes,bytesPerRow: GlyphAtlas.width,from: MTLRegionMake2D(0,0,GlyphAtlas.width,GlyphAtlas.height),mipmapLevel: 0)
        let ranked=(0..<32).sorted { a,b in
            func coverage(_ n: Int)->Int {
                var sum=0
                for y in 0..<24 { for x in 0..<16 { sum+=Int(bytes[(n/16*24+y)*256+n%16*16+x]) } }
                return sum
            }
            return coverage(a)<coverage(b)
        }.map(UInt32.init)
        guard let order=device.makeBuffer(bytes: ranked,length: ranked.count*4,options: .storageModeShared) else { throw SignalProcessor.GPUError.allocation }
        glyphOrder=order
        let ringDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,width: 1,height: 1,mipmapped: false)
        ringDescriptor.textureType = .type2DArray; ringDescriptor.arrayLength=2; ringDescriptor.usage = .shaderRead
        guard let ring=device.makeTexture(descriptor: ringDescriptor) else { throw SignalProcessor.GPUError.allocation }
        dummyRing=ring
    }
    func texture(_ width: Int,_ height: Int,format: MTLPixelFormat = .rgba16Float,array: Int = 1,render: Bool = false) throws -> MTLTexture {
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,width: width,height: height,mipmapped: false)
        d.storageMode = .private; d.usage=[.shaderRead,.shaderWrite]
        if render { d.usage.insert(.renderTarget) }
        if array>1 { d.textureType = .type2DArray; d.arrayLength=array }
        guard let t=device.makeTexture(descriptor: d) else { throw SignalProcessor.GPUError.allocation }
        return t
    }
    func prepare(_ s: SignalSettings,width: Int,height: Int) throws -> State {
        let structural = [.particles,.cells,.raster].contains(s.activeEffect) ? Int(s.parameter(0)) : 0
        if let r=state,r.id == s.activeEffect,r.width == width,r.height == height,r.structural == structural,r.seed == s.seed,r.shape == Int(s.value("shape")) { return r }
        let fieldWidth=min(320,width), fieldHeight=max(1,Int(Float(height)*Float(fieldWidth)/Float(width)))
        let temporal: Set<EffectID>=[.raster,.contour,.particles,.fluid,.paint,.echo,.block,.mosh,.dataveil]
        let motion: Set<EffectID>=[.particles,.fluid,.growth,.cells,.mosh]
        let output=try (0..<(temporal.contains(s.activeEffect) ? 2 : 1)).map { _ in try texture(width,height) }
        let previous=try texture(motion.contains(s.activeEffect) ? width : 1,motion.contains(s.activeEffect) ? height : 1,format: .bgra8Unorm)
        let field=try texture(fieldWidth,fieldHeight)
        let drawn = [.raster,.particles].contains(s.activeEffect) ? try texture(width,height,render: true) : nil
        var simulation: [MTLTexture]=[]
        if [.particles,.cells].contains(s.activeEffect) {
            let columns=max(1,structural)
            let baseRows=Float(columns)*Float(height)/Float(width)
            let shape=s.activeEffect == .cells ? Int(s.value("shape")) : 0
            let rows=max(1,Int(ceil(baseRows*(shape == 2 ? 2 : (shape == 3 ? 1.1547005 : 1)))))
            simulation=try [texture(columns,rows,format: .rgba32Float),texture(columns,rows,format: .rgba32Float)]
        } else if s.activeEffect == .growth {
            simulation=try [texture(fieldWidth,fieldHeight),texture(fieldWidth,fieldHeight)]
        }
        let life = s.activeEffect == .particles ? try [texture(simulation[0].width,simulation[0].height),texture(simulation[0].width,simulation[0].height)] : []
        let colors = s.activeEffect == .particles ? try [texture(simulation[0].width,simulation[0].height),texture(simulation[0].width,simulation[0].height)] : []
        let slit = s.activeEffect == .slit ? try texture(width,height,format: .bgra8Unorm,array: 8) : nil
        let r=State(id: s.activeEffect,seed: s.seed,width: width,height: height,output: output,previous: previous,field: field,geometry: drawn,simulation: simulation,life: life,colors: colors,slit: slit,structural: structural,shape: Int(s.value("shape")))
        state=r; return r
    }
    func encode(source: MTLTexture,command: MTLCommandBuffer,settings s: SignalSettings,time: Float,glyphs: MTLTexture) throws -> (MTLTexture,State) {
        let r=try prepare(s,width: source.width,height: source.height)
        let delta=r.lastTime.map { time-$0 } ?? 1/30
        if delta<=0 || delta>0.5 { r.valid=false; r.slitTimes=Array(repeating: -1,count: 8) }
        let dt=min(0.5,max(1/240,delta>0 ? delta : 1/30))
        if !r.valid && r.previous.width == source.width && r.previous.height == source.height {
            guard let clear=command.makeBlitCommandEncoder() else { throw SignalProcessor.GPUError.allocation }
            // Initialize the camera history by copy; output history is never sampled on first use.
            clear.copy(from: source,sourceSlice: 0,sourceLevel: 0,sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),sourceSize: MTLSize(width: source.width,height: source.height,depth: 1),to: r.previous,destinationSlice: 0,destinationLevel: 0,destinationOrigin: MTLOrigin(x: 0,y: 0,z: 0))
            clear.endEncoding()
        }
        var p: [Float]=[Float(s.effect),time,dt,r.valid ? 1 : 0,Float(source.width),Float(source.height)]
        p+=(0..<16).map { s.parameter($0) }
        p+=r.slitTimes
        var seed=s.seed
        func run(_ name: String,_ inputs: [(Int,MTLTexture)],width: Int,height: Int) throws {
            guard let pass=command.makeComputeCommandEncoder(),let pipeline=compute[name] else { throw SignalProcessor.GPUError.allocation }
            pass.setComputePipelineState(pipeline)
            for (index,t) in inputs { pass.setTexture(t,index: index) }
            pass.setBytes(&p,length: p.count*4,index: 0); pass.setBytes(&seed,length: 4,index: 1)
            pass.setBuffer(glyphOrder,offset: 0,index: 2)
            let w=min(16,pipeline.threadExecutionWidth),h=min(16,max(1,pipeline.maxTotalThreadsPerThreadgroup/w))
            if name == "boundedSort" {
                let length=Int(s.value("length")),vertical=s.value("direction")>0.5
                let extent=vertical ? height : width,lines=vertical ? width : height
                var lanes=8
                while lanes<length { lanes*=2 }
                guard pipeline.maxTotalThreadsPerThreadgroup>=lanes else { pass.endEncoding(); throw SignalProcessor.GPUError.allocation }
                pass.dispatchThreadgroups(MTLSize(width: (extent+length-1)/length,height: lines,depth: 1),threadsPerThreadgroup: MTLSize(width: lanes,height: 1,depth: 1))
            } else {
                pass.dispatchThreads(MTLSize(width: width,height: height,depth: 1),threadsPerThreadgroup: MTLSize(width: w,height: h,depth: 1))
            }
            pass.endEncoding()
        }
        let needsField: Set<EffectID>=[.contour,.hatch,.paint,.particles,.fluid,.growth,.cells,.mosh]
        if needsField.contains(s.activeEffect) {
            try run("analysisField",[(0,source),(1,r.previous),(2,r.field)],width: r.field.width,height: r.field.height)
        }
        if [.particles,.cells].contains(s.activeEffect) {
            let next=r.simulation[r.simulationNext],old=r.simulation[1-r.simulationNext]
            if s.activeEffect == .particles {
                try run("updateParticles",[(0,old),(1,r.field),(2,next),(3,r.life[1-r.simulationNext]),(4,r.life[r.simulationNext]),(5,source),(6,r.colors[1-r.simulationNext]),(7,r.colors[r.simulationNext])],width: next.width,height: next.height)
            } else {
                try run("updateSites",[(0,old),(1,r.field),(2,next)],width: next.width,height: next.height)
            }
            r.simulationNext=1-r.simulationNext
        }
        if s.activeEffect == .growth {
            // At most eight stable diffusion steps. Never integrate a long discontinuity.
            let steps=max(1,min(8,Int(ceil(dt*120*s.value("speed")))))
            p[2]=dt/Float(steps)
            for step in 0..<steps {
                let next=r.simulation[r.simulationNext],old=r.simulation[1-r.simulationNext]
                p[3]=(r.valid || step>0) ? 1 : 0
                try run("growInk",[(0,source),(1,old),(2,next),(3,r.field)],width: next.width,height: next.height)
                r.simulationNext=1-r.simulationNext
            }
            p[3]=r.valid ? 1 : 0; p[2]=dt
        }
        if let target=r.geometry {
            let descriptor=MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture=target
            descriptor.colorAttachments[0].loadAction = .clear; descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor=MTLClearColorMake(0.006,0.008,0.012,1)
            guard let pass=command.makeRenderCommandEncoder(descriptor: descriptor) else { throw SignalProcessor.GPUError.allocation }
            pass.setRenderPipelineState(geometry)
            pass.setVertexTexture(source,index: 0)
            pass.setVertexTexture(r.simulation.isEmpty ? source : r.simulation[1-r.simulationNext],index: 1)
            pass.setVertexTexture(r.life.isEmpty ? source : r.life[1-r.simulationNext],index: 2)
            pass.setVertexTexture(r.colors.isEmpty ? source : r.colors[1-r.simulationNext],index: 3)
            pass.setVertexBytes(&p,length: p.count*4,index: 0)
            let columns=s.activeEffect == .particles ? r.simulation[0].width : Int(s.value("density"))*2
            let rows=s.activeEffect == .particles ? r.simulation[0].height : Int(s.value("density"))
            let points=s.activeEffect == .particles || Int(s.value("style")) == 2
            let mesh=s.activeEffect == .raster && Int(s.value("style")) == 1
            pass.drawPrimitives(type: points ? .point : .line,vertexStart: 0,vertexCount: points ? columns*rows*(s.activeEffect == .particles ? 2 : 1) : ((columns-1)*rows+(mesh ? columns*(rows-1) : 0))*2)
            pass.endEncoding()
        }
        if let ring=r.slit {
            let last=r.slitTimes.max() ?? -1
            if !r.valid || time-last >= s.value("delay")/7 {
                guard let blit=command.makeBlitCommandEncoder() else { throw SignalProcessor.GPUError.allocation }
                blit.copy(from: source,sourceSlice: 0,sourceLevel: 0,sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),sourceSize: MTLSize(width: source.width,height: source.height,depth: 1),to: ring,destinationSlice: r.slitNext,destinationLevel: 0,destinationOrigin: MTLOrigin(x: 0,y: 0,z: 0))
                blit.endEncoding(); r.slitTimes[r.slitNext]=time; r.slitNext=(r.slitNext+1)%8
            }
            p.replaceSubrange(22..<30,with: r.slitTimes)
        }
        let next=r.output[r.next],old=r.output.count>1 ? r.output[1-r.next] : source
        if s.activeEffect == .sort {
            try run("boundedSort",[(0,source),(2,next)],width: source.width,height: source.height)
        } else {
            // Unused textures are valid bindings; branches never sample their uninitialized contents.
            try run("advancedImage",[(0,source),(1,old),(2,next),(3,r.field),(4,r.geometry ?? source),(5,r.simulation.last.map { _ in r.simulation[1-r.simulationNext] } ?? source),(6,glyphs),(7,r.slit ?? dummyRing)],width: source.width,height: source.height)
        }
        if r.previous.width == source.width && r.previous.height == source.height {
            guard let blit=command.makeBlitCommandEncoder() else { throw SignalProcessor.GPUError.allocation }
            blit.copy(from: source,sourceSlice: 0,sourceLevel: 0,sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),sourceSize: MTLSize(width: source.width,height: source.height,depth: 1),to: r.previous,destinationSlice: 0,destinationLevel: 0,destinationOrigin: MTLOrigin(x: 0,y: 0,z: 0)); blit.endEncoding()
        }
        r.next=(r.next+1)%r.output.count; r.valid=true; r.lastTime=time
        return (next,r)
    }
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    constexpr sampler nearestSampler(coord::normalized,address::clamp_to_edge,filter::nearest);
    constexpr sampler linearSampler(coord::normalized,address::clamp_to_edge,filter::linear);
    float lum(float3 c) { return dot(c,float3(0.2126,0.7152,0.0722)); }
    uint mixBits(uint v) { v^=v>>16; v*=0x7feb352du; v^=v>>15; v*=0x846ca68bu; return v^(v>>16); }
    float randomAt(uint2 pos,uint seed) { return float(mixBits(pos.x*0x9e3779b9u^pos.y*0x85ebca6bu^seed)>>8)/16777216.0; }
    float3 inkHue(float degrees) {
        return mix(float3(1),clamp(abs(fract(float3(degrees/360.0)+float3(0,2.0/3,1.0/3))*6-3)-1,0.0,1.0),0.9);
    }
    float3 applyInk(float3 color,int mode,float hue) {
        float gray=lum(color);
        if(mode==1) return float3(gray);
        if(mode==2) return inkHue(hue)*gray;
        if(mode==3) return 1-color;
        if(mode==4) return floor(color*4+0.5)/4;
        if(mode==5) return clamp(float3(1.5-abs(gray*4-3),1.5-abs(gray*4-2),1.5-abs(gray*4-1)),0.0,1.0);
        return color;
    }
    float retainHalf(float dt,float halfLife) { return halfLife>0 ? exp2(-dt/halfLife) : 0; }
    float3 toLinear(float3 c) { return select(c/12.92,pow((c+0.055)/1.055,float3(2.4)),c>0.04045); }
    float3 toDisplay(float3 c) { c=max(c,0.0); return select(c*12.92,1.055*pow(c,float3(1.0/2.4))-0.055,c>0.0031308); }
    float sampleY(texture2d<float,access::sample> src,float2 uv) { return lum(src.sample(linearSampler,uv).rgb); }
    kernel void analysisField(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::sample> previous [[texture(1)]],texture2d<float,access::write> field [[texture(2)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=field.get_width() || id.y>=field.get_height()) return;
        float2 size=float2(field.get_width(),field.get_height()),uv=(float2(id)+0.5)/size,px=1.0/size;
        float3 tensor=0;
        for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
            float2 q=uv+float2(x,y)*px;
            float gx=sampleY(src,q+float2(px.x,0))-sampleY(src,q-float2(px.x,0));
            float gy=sampleY(src,q+float2(0,px.y))-sampleY(src,q-float2(0,px.y));
            float weight=(x==0 ? 2.0 : 1.0)*(y==0 ? 2.0 : 1.0);
            tensor+=float3(gx*gx,gy*gy,gx*gy)*weight/16.0;
        }
        float angle=0.5*atan2(2*tensor.z,tensor.x-tensor.y)+1.5707963268;
        float2 tangent=float2(cos(angle),sin(angle));
        int mode=int(p[0]); float2 motion=0;
        if(p[3]>0 && (mode==13 || mode==14 || mode==15 || mode==17 || mode==23)) {
            float minimum=1e6,zeroError=1e6; int2 best=0;
            // Bounded 5x5 block search on a reduced map, with stationary tie preference.
            for(int dy=-2;dy<=2;dy++) for(int dx=-2;dx<=2;dx++) {
                float error=0;
                for(int yy=-1;yy<=1;yy++) for(int xx=-1;xx<=1;xx++) {
                    float2 q=uv+float2(xx,yy)*px*2;
                    error+=abs(sampleY(src,q)-sampleY(previous,q+float2(dx,dy)*px*2));
                }
                if(dx==0 && dy==0) zeroError=error;
                error+=float(dx*dx+dy*dy)*0.003;
                if(error<minimum) { minimum=error; best=int2(dx,dy); }
            }
            float confidence=smoothstep(0.01,0.12,zeroError-minimum);
            motion=-float2(best)*px*2*confidence;
        }
        field.write(float4(tangent,motion),id);
    }
    float2 tangentAt(texture2d<float,access::sample> field,float2 uv,float2 reference) {
        float2 tangent=field.sample(linearSampler,uv).xy;
        return dot(tangent,reference)<0 ? -tangent : tangent;
    }
    float flowLine(texture2d<float,access::sample> src,texture2d<float,access::sample> field,float2 uv,float radius,float threshold,float coherence) {
        float2 px=1.0/float2(src.get_width(),src.get_height());
        float2 tangent=field.sample(linearSampler,uv).xy;
        float response=0;
        // Integrate a normal DoG response along the local, sign-aligned tangent.
        for(int step=-3;step<=3;step++) {
            float2 q=uv+tangent*px*float(step)*coherence;
            float2 direction=tangentAt(field,q,tangent),normal=float2(-direction.y,direction.x)*px*radius;
            float inner=sampleY(src,q)*0.4+(sampleY(src,q+normal)+sampleY(src,q-normal))*0.3;
            float outer=(sampleY(src,q+normal*2)+sampleY(src,q-normal*2))*0.5;
            response+=abs(inner-outer)/7;
        }
        return smoothstep(threshold*0.4,threshold,response);
    }
    kernel void updateSites(texture2d<float,access::read> old [[texture(0)]],texture2d<float,access::sample> field [[texture(1)]],texture2d<float,access::write> dst [[texture(2)]],constant float *p [[buffer(0)]],constant uint &seed [[buffer(1)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float2 size=float2(dst.get_width(),dst.get_height()),anchor=(float2(id)+0.5)/size;
        bool cells=int(p[0])==17;
        if(cells && p[12]<0.5) anchor+=(float2(randomAt(id,seed),randomAt(id,seed^0x41u))-0.5)*0.6/size;
        if(cells && (int(p[12])==2 || int(p[12])==3)) anchor.x+=float(id.y%2)*0.5/size.x;
        float4 state=p[3]>0 ? old.read(id) : float4(anchor,0,0);
        float2 motion=field.sample(linearSampler,state.xy).zw;
        float dt=p[2],scatter=p[7],spring=p[8];
        int steps=max(1,int(ceil(dt*120))); float h=dt/float(steps);
        for(int step=0;step<steps;step++) {
            float2 acceleration=(anchor-state.xy)*spring*spring+motion/max(dt,0.004)*scatter*20;
            state.zw=(state.zw+acceleration*h)*exp(-spring*1.3*h);
            state.xy+=state.zw*h;
        }
        float2 limit=cells ? 1.2/size : float2(0.18);
        state.xy=clamp(state.xy,anchor-limit,anchor+limit);
        dst.write(state,id);
    }
    kernel void updateParticles(texture2d<float,access::read> old [[texture(0)]],texture2d<float,access::sample> field [[texture(1)]],texture2d<float,access::write> dst [[texture(2)]],texture2d<float,access::read> oldLife [[texture(3)]],texture2d<float,access::write> newLife [[texture(4)]],texture2d<float,access::sample> camera [[texture(5)]],texture2d<float,access::read> oldColor [[texture(6)]],texture2d<float,access::write> newColor [[texture(7)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float2 grid=float2(dst.get_width(),dst.get_height()),anchor=(float2(id)+0.5)/grid;
        float4 state=p[3]>0 ? old.read(id) : float4(anchor,0,0);
        float4 life=p[3]>0 ? oldLife.read(id) : float4(0);
        float4 color=p[3]>0 ? oldColor.read(id) : camera.sample(linearSampler,anchor);
        float2 motion=field.sample(linearSampler,anchor).zw;
        float dt=p[2],speed=length(motion*float2(p[4],p[5]))/max(dt,0.004);
        if(life.y<0.5 && speed>p[15]) {
            state=float4(anchor,motion/max(dt,0.004)*p[7]*1.8);
            life=float4(0,1,0,0); color=camera.sample(linearSampler,anchor);
        }
        if(life.y>0.5) {
            // Inertia only: no spring pulling the flying fragment back to its old slot.
            state.xy+=state.zw*dt;
            state.zw*=exp(-p[14]*dt); life.x+=dt;
            if(life.x>=p[8] || any(state.xy<float2(-1)) || any(state.xy>float2(2))) {
                state=float4(anchor,0,0); life=float4(0); color=camera.sample(linearSampler,anchor);
            }
        }
        dst.write(state,id); newLife.write(life,id); newColor.write(color,id);
    }
    kernel void growInk(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::sample> old [[texture(1)]],texture2d<float,access::write> dst [[texture(2)]],texture2d<float,access::sample> field [[texture(3)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float2 uv=(float2(id)+0.5)/float2(dst.get_width(),dst.get_height());
        float2 px=1.0/float2(dst.get_width(),dst.get_height());
        float edge=abs(sampleY(src,uv+float2(px.x,0))-sampleY(src,uv-float2(px.x,0)))+abs(sampleY(src,uv+float2(0,px.y))-sampleY(src,uv-float2(0,px.y)));
        float2 radial=uv-0.5;
        radial=length(radial)>0.001 ? normalize(radial) : float2(0);
        float direction=p[14]>0.5 ? -1.0 : 1.0;
        float2 advected=uv-radial*direction*p[15]*p[2]*0.08;
        float2 chemical=float2(1,0);
        if(p[3]>0) chemical=old.sample(linearSampler,advected).xy;
        else chemical.y=edge>0.04 ? 0.8 : 0;
        float2 lap=0;
        if(p[3]>0) {
            lap=-chemical;
            for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
                if(x==0 && y==0) continue;
                lap+=old.sample(linearSampler,advected+float2(x,y)*px).xy*((x==0 || y==0) ? 0.2 : 0.05);
            }
        }
        float reaction=chemical.x*chemical.y*chemical.y;
        chemical+=float2(lap.x-reaction+p[6]*(1-chemical.x),0.5*lap.y+reaction-(p[7]+p[6])*chemical.y)*0.8;
        chemical.y+=smoothstep(0.04,0.18,edge)*p[8]*0.012;
        float movement=length(field.sample(linearSampler,uv).zw*float2(p[4],p[5]));
        chemical.y+=smoothstep(0.2,8.0,movement)*p[13]*p[2]*1.4;
        dst.write(float4(clamp(chemical,0.0,1.0),0,1),id);
    }
    struct PortraitVertex { float4 position [[position]]; float4 color; float pointSize [[point_size]]; };
    vertex PortraitVertex portraitVertex(uint vertexIndex [[vertex_id]],texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::read> particles [[texture(1)]],texture2d<float,access::read> particleLife [[texture(2)]],texture2d<float,access::read> particleColor [[texture(3)]],constant float *p [[buffer(0)]]) {
        PortraitVertex out;
        bool particle=int(p[0])==13; int style=int(p[9]);
        uint columns=particle ? particles.get_width() : uint(p[6])*2;
        uint rows=particle ? particles.get_height() : uint(p[6]);
        uint2 cell;
        uint particleIndex=particle ? vertexIndex%(columns*rows) : vertexIndex;
        uint layer=particle ? vertexIndex/(columns*rows) : 0;
        if(particle || style==2) cell=uint2(particleIndex%columns,particleIndex/columns);
        else {
            uint segment=vertexIndex/2,endpoint=vertexIndex%2,horizontal=(columns-1)*rows;
            if(segment<horizontal) cell=uint2(segment%(columns-1)+endpoint,segment/(columns-1));
            else { segment-=horizontal; cell=uint2(segment%columns,segment/columns+endpoint); }
        }
        float2 anchor=(float2(cell)+0.5)/float2(columns,rows),position=anchor;
        float3 camera=src.sample(linearSampler,anchor).rgb;
        float y=lum(camera);
        float opacity=1.0,growth=1.0;
        if(particle) {
            float4 life=particleLife.read(cell);
            bool flying=life.y>0.5;
            if(layer==0) {
                position=particles.read(cell).xy; camera=particleColor.read(cell).rgb;
                opacity=flying ? 1-smoothstep(p[8]*0.4,p[8],life.x) : 0;
                growth=max(0.1,1-life.x/max(p[8],0.01)*0.65);
            } else {
                growth=flying ? smoothstep(0.0,p[13],life.x) : 1;
                opacity=growth;
            }
            y=lum(camera);
        } else {
            // Smooth camera noise before extrusion. Orthographic X keeps each grid column fixed;
            // a global tilt replaces the old per-vertex radial magnification/lens-like distortion.
            float2 texel=1.0/float2(src.get_width(),src.get_height());
            float smoothY=(y*2+sampleY(src,anchor+float2(texel.x*2,0))+sampleY(src,anchor-float2(texel.x*2,0))
                +sampleY(src,anchor+float2(0,texel.y*2))+sampleY(src,anchor-float2(0,texel.y*2)))/6;
            float depth=(smoothY-0.5)*p[7],tilt=p[8]*0.7853981634;
            position.y=0.5+(anchor.y-0.5)*cos(tilt)+depth*(0.12+sin(tilt)*0.16);
        }
        // Raw texture row zero is the render target's top; the final signal pass normalizes orientation.
        out.position=float4(position.x*2-1,1-position.y*2,0,1);
        float3 color=particle && p[12]<0.5 ? camera : inkHue(p[11])*mix(0.25,1.0,y);
        out.color=float4(color,opacity); out.pointSize=particle ? max(0.1,p[9]*growth) : 2;
        return out;
    }
    fragment float4 portraitFragment(PortraitVertex in [[stage_in]]) { return in.color; }
    kernel void boundedSort(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::write> dst [[texture(2)]],constant float *p [[buffer(0)]],uint lane [[thread_index_in_threadgroup]],uint3 group [[threadgroup_position_in_grid]],uint3 groupSize [[threads_per_threadgroup]]) {
        threadgroup float4 colors[256];
        threadgroup float keys[256];
        threadgroup uint positions[256];
        threadgroup uint eligible[256];
        bool vertical=p[9]>0.5,reverse=p[10]>0.5;
        uint length=uint(clamp(int(p[6]),8,256));
        uint coordinate=group.x*length+lane;
        uint limit=vertical ? dst.get_height() : dst.get_width();
        bool active=lane<length && coordinate<limit;
        uint2 id=vertical ? uint2(group.y,coordinate) : uint2(coordinate,group.y);
        float2 size=float2(dst.get_width(),dst.get_height());
        float3 color=active ? src.sample(linearSampler,(float2(id)+0.5)/size).rgb : float3(0);
        float value=lum(color),lower=min(p[7],p[8]),upper=max(p[7],p[8]);
        eligible[lane]=active && value>=lower && value<=upper ? 1u : 0u;
        colors[lane]=float4(color,1); positions[lane]=lane;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint first=lane;
        if(eligible[lane]) { while(first>0 && eligible[first-1]) first--; }
        // Ineligible pixels are fixed separators. Eligible runs have disjoint key ranges.
        float maxChannel=max(color.r,max(color.g,color.b)),minChannel=min(color.r,min(color.g,color.b));
        float sortValue=value;
        if(p[12]>0.5 && p[12]<1.5) sortValue=color.r;
        else if(p[12]>1.5 && p[12]<2.5) sortValue=(maxChannel-minChannel)/max(0.001,maxChannel);
        else if(p[12]>2.5) sortValue=fract(atan2(1.7320508*(color.g-color.b),2*color.r-color.g-color.b)/6.2831853+1);
        keys[lane]=!active ? 1e6+float(lane) : (eligible[lane] ? float(first)*2+(reverse ? 1-sortValue : sortValue)*0.99 : float(lane)*2);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for(uint width=2;width<=groupSize.x;width*=2) for(uint stride=width/2;stride>0;stride/=2) {
            uint other=lane^stride;
            if(other>lane) {
                bool ascending=(lane&width)==0;
                bool greater=keys[lane]>keys[other] || (keys[lane]==keys[other] && positions[lane]>positions[other]);
                if(greater==ascending) {
                    float key=keys[lane]; keys[lane]=keys[other]; keys[other]=key;
                    uint position=positions[lane]; positions[lane]=positions[other]; positions[other]=position;
                    float4 c=colors[lane]; colors[lane]=colors[other]; colors[other]=c;
                }
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        uint outputLane=lane;
        if(eligible[lane] && p[13]>0.5) {
            uint last=lane; while(last+1<length && eligible[last+1]) last++;
            uint runLength=last-first+1,offset=lane-first;
            if(p[13]<1.5) outputLane=first+uint(floor(float(offset)/p[11]));
            else if(p[13]<2.5) outputLane=first+min(runLength-1,uint(floor(float(offset)/p[11]))*2);
            else outputLane=first+((offset%2==0) ? offset/2 : runLength-1-offset/2);
        }
        if(active) dst.write(colors[outputLane],id);
    }
    kernel void advancedImage(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::sample> previous [[texture(1)]],texture2d<float,access::write> dst [[texture(2)]],texture2d<float,access::sample> field [[texture(3)]],texture2d<float,access::sample> geometry [[texture(4)]],texture2d<float,access::sample> simulation [[texture(5)]],texture2d<float,access::sample> glyphs [[texture(6)]],texture2d_array<float,access::sample> slices [[texture(7)]],constant float *p [[buffer(0)]],constant uint &seed [[buffer(1)]],constant uint *glyphOrder [[buffer(2)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float2 size=float2(dst.get_width(),dst.get_height()),uv=(float2(id)+0.5)/size,px=1.0/size;
        float3 camera=src.sample(linearSampler,uv).rgb,result=camera;
        float y=lum(camera),dt=p[2]; bool valid=p[3]>0; int mode=int(p[0]);
        if(mode==10 || mode==13) {
            result=geometry.sample(linearSampler,uv).rgb;
            float halfLife=p[10];
            if(valid) result=max(result,previous.sample(linearSampler,uv).rgb*retainHalf(dt,halfLife));
        } else if(mode==11) {
            float line=flowLine(src,field,uv,p[6],p[7],p[8]);
            float3 ink=inkHue(p[10]); bool dark=p[11]>0.5;
            float halo=dark && p[12]>0 ? flowLine(src,field,uv,p[6]*2.5,p[7]*0.5,p[8])*p[12]*0.25 : 0;
            result=dark ? ink*(line+halo) : mix(float3(0.96),ink*0.16,line);
            if(valid && p[9]>0) {
                float keep=retainHalf(dt,p[9]);
                float3 history=previous.sample(linearSampler,uv).rgb;
                result=dark ? max(result,history*keep) : min(result,mix(float3(0.96),history,keep));
            }
        } else if(mode==12) {
            float2 tangent=field.sample(linearSampler,uv).xy;
            // Coherent direction blends toward a fixed paper grid in featureless regions.
            float2 pixel=uv*size;
            float phase=dot(pixel,float2(-tangent.y,tangent.x));
            // Controls use 1080p reference pixels, so thumbnails and live output share a look.
            float unit=max(0.1,size.y/1080.0)*p[13];
            float spacing=p[6]*unit,width=min(p[7]*unit,spacing*0.42),aa=max(0.6,size.y/1080.0);
            float tone=clamp((1-y)*p[9],0.0,1.0);
            float wave=abs(fract(phase/spacing)-0.5)*spacing;
            float stroke=(1-smoothstep(width,width+aa,wave))*smoothstep(0.08,0.65,tone);
            float second=abs(fract(dot(pixel,tangent)/spacing)-0.5)*spacing;
            stroke=max(stroke,(1-smoothstep(width,width+aa,second))*smoothstep(0.5,0.95,tone)*p[8]);
            float along=fract(dot(pixel,tangent)/(p[12]*unit));
            stroke*=smoothstep(0.0,0.08,along)*(1-smoothstep(0.85,1.0,along));
            float3 ink=inkHue(p[10]);
            result=p[11]>0.5 ? ink*stroke : mix(float3(0.96,0.94,0.9),ink*0.12,stroke);
        } else if(mode==14 || mode==23) {
            float2 sampleUV=uv;
            if(mode==23) sampleUV=(floor(uv*size/p[9])+0.5)*p[9]/size;
            float2 motion=field.sample(linearSampler,sampleUV).zw;
            sampleUV=uv-motion*p[6];
            if(mode==14) {
                float angle=sin(uv.y*20+p[1]*0.3)*cos(uv.x*17-p[1]*0.2);
                sampleUV+=float2(cos(angle*6.28),sin(angle*6.28))*p[10]*dt*0.015;
            }
            float3 history=valid ? previous.sample(linearSampler,sampleUV).rgb : camera;
            if(mode==14) {
                float3 blur=(previous.sample(linearSampler,sampleUV+px).rgb+previous.sample(linearSampler,sampleUV-px).rgb)*0.5;
                if(valid) history=mix(history,blur,p[8]*0.35);
                float keep=retainHalf(dt,p[9]);
                float refresh=1-pow(1-p[7],dt*30);
                result=toDisplay(mix(toLinear(history)*keep,toLinear(camera),refresh));
            } else {
                float difference=abs(lum(history)-y);
                float gate=smoothstep(p[7],p[7]+0.04,difference);
                bool cadence=floor(p[1]*p[14])!=floor((p[1]-dt)*p[14]);
                float phase=p[11]>0 ? fmod(p[1],p[11]) : 1e6;
                bool crossedKeyframe=p[11]>0 && floor(p[1]/p[11])!=floor((p[1]-dt)/p[11]);
                bool keyframe=p[11]>0 && (phase<p[13] || crossedKeyframe);
                bool held=p[11]>0 && phase>=p[13] && phase<p[13]+p[12];
                float refresh=1-pow(1-p[8],dt*30);
                if(cadence && !held) refresh=max(refresh,gate);
                if(held) refresh=0;
                if(keyframe) refresh=1;
                result=mix(history*retainHalf(dt,p[10]),camera,refresh);
            }
        } else if(mode==15) {
            float2 chemical=simulation.sample(linearSampler,uv).xy;
            float pigment=smoothstep(0.04,0.42,chemical.y);
            float2 sp=1.0/float2(simulation.get_width(),simulation.get_height());
            float slope=simulation.sample(linearSampler,uv+sp).y-simulation.sample(linearSampler,uv-sp).y;
            result=mix(float3(0.025),inkHue(p[10]),pigment)*(1+slope*p[12]*3);
            result=mix(result,camera,p[11]);
        } else if(mode==16) {
            float2 tangent=field.sample(linearSampler,uv).xy,normal=float2(-tangent.y,tangent.x);
            float3 means[4]; float variances[4];
            int radius=clamp(int(p[6]),1,6);
            for(int sector=0;sector<4;sector++) {
                float3 sum=0,squared=0; float count=0;
                for(int yy=0;yy<=6;yy++) for(int xx=0;xx<=6;xx++) {
                    if(xx>radius || yy>radius) continue;
                    float2 offset=float2(float(xx)*(sector%2==0 ? -1 : 1),float(yy)*(sector<2 ? -1 : 1));
                    float2 directed=tangent*offset.x*(1+p[7])+normal*offset.y*(1-p[7]*0.7);
                    float3 sample=src.sample(linearSampler,uv+directed*px).rgb;
                    sum+=sample; squared+=sample*sample; count++;
                }
                means[sector]=sum/count; variances[sector]=max(0.0,lum(squared/count-means[sector]*means[sector]));
            }
            float total=0; result=0;
            for(int sector=0;sector<4;sector++) { float weight=1.0/pow(0.01+variances[sector],p[8]*0.5); result+=means[sector]*weight; total+=weight; }
            result/=total;
            result=mix(float3(lum(result)),result,p[11]);
            float selection=1-smoothstep(p[12]-p[13],p[12]+p[13],lum(result));
            if(p[12]>=0.999) selection=1;
            if(p[16]>0.5) selection=1-selection;
            result*=1-p[9]*flowLine(src,field,uv,1.5,0.05,2);
            if(valid && p[14]<0.5) result=mix(result,previous.sample(linearSampler,uv).rgb,retainHalf(dt,p[10]));
            if(p[14]>0.5) {
                float3 fill=inkHue(p[15]);
                if(p[14]<2.5 && p[14]>1.5) fill=float3(0,1,0);
                else if(p[14]<3.5 && p[14]>2.5) fill=float3(0,0,1);
                else if(p[14]>3.5) fill=float3(1);
                result=mix(camera,fill,selection);
            } else result=mix(camera,result,selection);
        } else if(mode==17) {
            int2 dimensions=int2(simulation.get_width(),simulation.get_height());
            int2 center=int2(uv*float2(dimensions)); float nearest=1e6,second=1e6; float2 selected=uv;
            for(int yy=-2;yy<=2;yy++) for(int xx=-2;xx<=2;xx++) {
                int2 index=center+int2(xx,yy); if(any(index<0) || any(index>=dimensions)) continue;
                float2 site=simulation.sample(nearestSampler,(float2(index)+0.5)/float2(dimensions)).xy;
                float2 difference=abs((uv-site)*size);
                float distance=length(difference);
                if(int(p[12])==1) distance=max(difference.x,difference.y);
                if(distance<nearest) {
                    second=nearest; nearest=distance; selected=(float2(index)+0.5)/float2(dimensions);
                    if(int(p[12])==0) selected+=(float2(randomAt(uint2(index),seed),randomAt(uint2(index),seed^0x41u))-0.5)*0.6/float2(dimensions);
                    if(int(p[12])==2 || int(p[12])==3) selected.x+=float(index.y%2)*0.5/float(dimensions.x);
                }
                else second=min(second,distance);
            }
            result=src.sample(linearSampler,selected).rgb;
            float border=(1-smoothstep(p[9],p[9]+1,second-nearest))*step(0.001,p[9]);
            result=mix(result,inkHue(p[10])*0.4,border);
            if(int(p[12])==4) result*=1-smoothstep(size.x/float(dimensions.x)*0.42,size.x/float(dimensions.x)*0.46,nearest);
        } else if(mode==18) {
            float angle=p[8]*0.01745329252*dt;
            float2 q=uv-0.5;
            q=float2(q.x*cos(angle)-q.y*sin(angle),q.x*sin(angle)+q.y*cos(angle));
            q=q*exp(-p[7]*dt)+0.5-float2(p[9]*dt/size.x,0);
            if(valid && all(q>=0) && all(q<=1)) {
                float3 echo=previous.sample(linearSampler,q).rgb;
                int inkMode=int(p[11]);
                if(inkMode<=5) echo=mix(echo,applyInk(echo,inkMode,p[12]),p[13]);
                else if(inkMode==6) {
                    float2 offset=float2(4.0/size.x,0);
                    float3 split=float3(previous.sample(linearSampler,q+offset).r,echo.g,previous.sample(linearSampler,q-offset).b);
                    echo=mix(echo,split,p[13]);
                } else {
                    float outline=abs(sampleY(previous,q+px*2)-sampleY(previous,q-px*2));
                    echo=mix(echo,inkHue(p[12])*smoothstep(0.01,0.1,outline),p[13]);
                }
                float3 history=toLinear(echo);
                float weight=retainHalf(dt,p[6])*pow(p[10],dt);
                result=toDisplay(mix(toLinear(camera),history,weight));
            }
        } else if(mode==19) {
            uint2 tile=uint2(floor(float2(id)/p[6]));
            uint tick=uint(floor(p[1]/p[8]));
            bool error=randomAt(tile,seed^mixBits(tick))<p[7];
            bool samePeriod=uint(floor((p[1]-dt)/p[8]))==tick;
            if(error) {
                if(valid && samePeriod) result=previous.sample(linearSampler,uv).rgb;
                else {
                    float2 shift=(float2(randomAt(tile,seed^tick^0x71u),randomAt(tile,seed^tick^0x92u))-0.5)*p[9]*p[6]/size;
                    float levels=p[10]-1;
                    float3 displaced=src.sample(linearSampler,uv+shift).rgb;
                    result=floor(displaced*levels+0.5)/levels;
                    int recipe=int(p[12]);
                    if(recipe==1) result=float3(floor(lum(displaced)*levels+0.5)/levels);
                    else if(recipe==2) result=clamp(result+float3(0.08,-0.03,0.04),0.0,1.0);
                    else if(recipe==3) {
                        float gray=lum(displaced),chromaLevels=max(1.0,levels*0.35);
                        result=clamp(float3(gray)+round((displaced-gray)*chromaLevels)/chromaLevels,0.0,1.0);
                    } else if(recipe==4) {
                        float3 prior=valid ? previous.sample(linearSampler,uv).rgb : camera;
                        float residual=floor(clamp(length(displaced-prior)*2,0.0,1.0)*levels+0.5)/levels;
                        result=mix(result,applyInk(float3(residual),5,0),0.7);
                    }
                }
            }
        } else if(mode==20) {
            float2 cellSize=float2(p[6],p[6]*1.5),screen=uv*size;
            float2 cell=floor(screen/cellSize);
            float3 average=0;
            for(int yy=0;yy<4;yy++) for(int xx=0;xx<4;xx++) average+=src.sample(linearSampler,(cell+(float2(xx,yy)+0.5)/4)*cellSize/size).rgb/16;
            float tone=clamp((lum(average)-0.5)*p[7]+0.5,0.0,1.0);
            bool paper=p[10]>0.5; if(paper) tone=1-tone;
            uint glyph=glyphOrder[min(31u,uint(tone*31))];
            float2 local=fract(screen/cellSize); local.y=1-local.y;
            float2 atlas=(float2(glyph%16*16,glyph/16*24)+0.5+local*float2(15,23))/float2(256,48);
            float mask=glyphs.sample(linearSampler,atlas).r*(tone<0.04 ? 0 : 1);
            float3 color=p[8]<0.5 ? clamp(average*2,0.0,1.0) : (p[8]<1.5 ? float3(1) : inkHue(p[9]));
            result=paper ? mix(float3(0.96),color*0.1,mask) : color*mask;
            if(p[10]>1.5) result=1-result;
        } else if(mode==22) {
            float fraction=p[7]<0.5 ? uv.y : (p[7]<1.5 ? uv.x : (p[7]<2.5 ? clamp(length(uv-0.5)*1.4142,0.0,1.0) : 1-uv.y));
            float target=p[1]-fraction*p[6],bestDistance=1e6; uint layer=0; bool found=false;
            for(uint i=0;i<8;i++) if(p[22+i]>=0) { float distance=abs(p[22+i]-target); if(distance<bestDistance) { bestDistance=distance; layer=i; found=true; } }
            if(found) {
                float3 history=slices.sample(linearSampler,uv,layer).rgb;
                history=mix(history,applyInk(history,int(p[9]),p[10]),p[11]);
                result=mix(camera,history,p[8]);
            }
        } else if(mode==24) {
            float mask=smoothstep(p[6]-p[7],p[6]+p[7],y);
            float3 ink=inkHue(p[10]);
            float edge=abs(sampleY(src,uv+px)-sampleY(src,uv-px));
            result=ink*(mask*0.5+smoothstep(0.02,0.15,edge)*0.5);
            if(valid) {
                float angle=p[12]*0.01745329252;
                float2 q=uv-float2(cos(angle),-sin(angle))*p[9]*dt/size;
                float3 feedback=previous.sample(linearSampler,q).rgb;
                float3 glow=(previous.sample(linearSampler,q+px*3).rgb+previous.sample(linearSampler,q-px*3).rgb)*0.5;
                result=max(result,mix(feedback,glow,0.15)*retainHalf(dt,p[8]));
            }
            result=mix(result,camera,p[11]);
        }
        dst.write(float4(clamp(result,0.0,1.0),1),id);
    }
    """
}
