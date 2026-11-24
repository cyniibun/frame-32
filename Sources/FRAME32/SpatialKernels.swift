import Foundation

/// Inverts circle-within-square coverage, including overlap at high ink coverage.
enum HalftoneCoverage {
    static func area(radius: Double) -> Double {
        let r = max(0,min(sqrt(0.5),radius))
        if r <= 0.5 { return .pi*r*r }
        let cap = r*r*acos(0.5/r)-0.5*sqrt(max(0,r*r-0.25))
        return min(1,max(0,.pi*r*r-4*cap))
    }
    static func table(count: Int = 256) -> [Float] {
        (0..<count).map { index in
            let target = Double(index)/Double(count-1)
            var low = 0.0, high = sqrt(0.5)
            for _ in 0..<24 { let mid = (low+high)/2; if area(radius: mid) < target { low = mid } else { high = mid } }
            return Float((low+high)/2)
        }
    }
}

enum SpatialKernels {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    float spatialLuma(float3 c) { return dot(c,float3(0.2126,0.7152,0.0722)); }
    kernel void edgeGradient(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::write> dst [[texture(1)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        constexpr sampler smp(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 sz=float2(dst.get_width(),dst.get_height()), q=(float2(id)+0.5)/sz; q.y=1.0-q.y;
        float a=spatialLuma(src.sample(smp,q+float2(-1,-1)/sz).rgb);
        float b=spatialLuma(src.sample(smp,q+float2(0,-1)/sz).rgb);
        float c=spatialLuma(src.sample(smp,q+float2(1,-1)/sz).rgb);
        float d=spatialLuma(src.sample(smp,q+float2(-1,0)/sz).rgb);
        float f=spatialLuma(src.sample(smp,q+float2(1,0)/sz).rgb);
        float g=spatialLuma(src.sample(smp,q+float2(-1,1)/sz).rgb);
        float h=spatialLuma(src.sample(smp,q+float2(0,1)/sz).rgb);
        float i=spatialLuma(src.sample(smp,q+float2(1,1)/sz).rgb);
        float gx=(3*c+10*f+3*i)-(3*a+10*d+3*g);
        float gy=(3*g+10*h+3*i)-(3*a+10*b+3*c);
        float magnitude=length(float2(gx,gy))/16.0;
        float mask=smoothstep(p[2]-p[3],p[2]+p[3],magnitude);
        dst.write(float4(mask,0,0,1),id);
    }
    kernel void edgeHorizontal(texture2d<float,access::read> src [[texture(0)]],texture2d<float,access::write> dst [[texture(1)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float radius=(p[4]-1.0)*0.5; int lower=int(floor(radius)), upper=int(ceil(radius));
        float lo=0,hi=0;
        for(int dx=-3;dx<=3;dx++) {
            int x=clamp(int(id.x)+dx,0,int(src.get_width())-1);
            float v=src.read(uint2(x,id.y)).r;
            if(abs(dx)<=lower) lo=max(lo,v);
            if(abs(dx)<=upper) hi=max(hi,v);
        }
        dst.write(float4(lo,hi,0,1),id);
    }
    kernel void edgeVertical(texture2d<float,access::read> src [[texture(0)]],texture2d<float,access::write> dst [[texture(1)]],constant float *p [[buffer(0)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=dst.get_width() || id.y>=dst.get_height()) return;
        float radius=(p[4]-1.0)*0.5; int lower=int(floor(radius)), upper=int(ceil(radius));
        float lo=0,hi=0;
        for(int dy=-3;dy<=3;dy++) {
            int y=clamp(int(id.y)+dy,0,int(src.get_height())-1);
            float2 v=src.read(uint2(id.x,y)).rg;
            if(abs(dy)<=lower) lo=max(lo,v.r);
            if(abs(dy)<=upper) hi=max(hi,v.g);
        }
        dst.write(float4(mix(lo,hi,fract(radius)),0,0,1),id);
    }
    kernel void matrixCells(texture2d<float,access::sample> src [[texture(0)]],texture2d<float,access::read> history [[texture(1)]],texture2d<float,access::write> target [[texture(2)]],constant float *p [[buffer(0)]],constant uint &hasHistory [[buffer(1)]],uint2 id [[thread_position_in_grid]]) {
        if(id.x>=target.get_width() || id.y>=target.get_height()) return;
        constexpr sampler smp(coord::normalized,address::clamp_to_edge,filter::linear);
        float2 cellSize=float2(p[2],p[2]*1.5), sz=float2(src.get_width(),src.get_height());
        float2 center=(float2(id)+0.5)*cellSize/sz; center.y=1.0-center.y;
        float luma=spatialLuma(src.sample(smp,center).rgb);
        float old=hasHistory!=0 ? history.read(id).r : luma;
        float movement=clamp(abs(luma-old)/(max(0.004,p[10])*6.0),0.0,1.0);
        float4 previous=hasHistory!=0 ? history.read(id) : float4(luma,0,luma,0);
        float decay=p[11]>0.0 ? exp2(-p[10]/p[11]) : 0.0;
        float ghostLuma=max(luma,previous.b*decay);
        float ghostMotion=p[11]>0.0 ? max(movement,previous.a*decay) : 0.0;
        target.write(float4(luma,movement,ghostLuma,ghostMotion),id);
    }
    float3 printScreen(texture2d<float,access::sample> src,texture1d<float,access::sample> coverage,float2 uv,float2 sz,constant float *p) {
        constexpr sampler smp(coord::normalized,address::clamp_to_edge,filter::linear);
        float pitch=p[2], density=p[3], rotation=p[4]*0.01745329252, black=p[8], registration=p[9];
        const float angles[4]={0.2617993878,1.308996939,0.0,0.7853981634};
        const float2 shifts[4]={float2(1,0),float2(-0.5,0.866),float2(-0.5,-0.866),float2(0,0)};
        float ink[4];
        for(int channel=0;channel<4;channel++) {
            float angle=angles[channel]+rotation, cs=cos(angle), sn=sin(angle);
            float2 shift=shifts[channel]*registration;
            float2 pos=uv*sz+shift;
            float2 lattice=float2(cs*pos.x-sn*pos.y,sn*pos.x+cs*pos.y)/pitch;
            float2 center=(floor(lattice)+0.5)*pitch;
            float2 sourceCenter=float2(cs*center.x+sn*center.y,-sn*center.x+cs*center.y)-shift;
            float3 rgb=src.sample(smp,sourceCenter/sz).rgb;
            float3 cmy=1.0-rgb;
            float k=min(cmy.r,min(cmy.g,cmy.b))*black;
            float tone=channel==3 ? k : max(0.0,(cmy[channel]-k)/max(1.0-k,0.0001));
            tone=clamp(tone*density,0.0,1.0);
            float radius=coverage.sample(smp,(tone*255.0+0.5)/256.0).r;
            float dist=length(fract(lattice)-0.5), aa=0.65/pitch;
            ink[channel]=tone<=0.0 ? 0.0 : (tone>=1.0 ? 1.0 : 1.0-smoothstep(radius-aa,radius+aa,dist));
        }
        return float3((1.0-ink[0])*(1.0-ink[3]),(1.0-ink[1])*(1.0-ink[3]),(1.0-ink[2])*(1.0-ink[3]));
    }
    """
}
