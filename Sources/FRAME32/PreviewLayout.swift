import CoreGraphics

enum PreviewLayout {
    /// Centered placement without distortion. Fill crops; fit leaves space around the image.
    static func placement(source: CGSize,target: CGSize,fill: Bool) -> CGRect? {
        guard source.width.isFinite,source.height.isFinite,target.width.isFinite,target.height.isFinite,
              source.width>0,source.height>0,target.width>0,target.height>0 else { return nil }
        let horizontal=target.width/source.width,vertical=target.height/source.height
        let scale=fill ? max(horizontal,vertical) : min(horizontal,vertical)
        let width=source.width*scale,height=source.height*scale
        return CGRect(x: (target.width-width)/2,y: (target.height-height)/2,width: width,height: height)
    }
}
