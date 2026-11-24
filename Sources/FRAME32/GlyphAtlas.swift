import CoreGraphics
import CoreText
import Metal
import Foundation

/// Immutable initialization-only glyph rasterization. Live frames only sample this texture.
enum GlyphAtlas {
    static let width = 256, height = 48
    static let characters = Array("0123456789ABCDEF@#$%&*+<>[]{}?/\\=|")
    static func make(device: MTLDevice) throws -> MTLTexture {
        var pixels = [UInt8](repeating: 0,count: width*height)
        let font = CTFontCreateWithName("Menlo-Regular" as CFString,18,nil)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw AtlasError.allocation }
            context.setFillColor(gray: 0,alpha: 1); context.fill(CGRect(x: 0,y: 0,width: width,height: height))
            context.setShouldAntialias(true)
            for (index,character) in characters.prefix(32).enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1,alpha: 1)]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character),attributes: attributes))
                // First texture row is top; invert the glyph's local CoreText coordinate system.
                context.saveGState()
                context.translateBy(x: CGFloat(index%16)*16+2,y: CGFloat(index/16)*24+19)
                context.scaleBy(x: 1,y: -1); context.textPosition = .zero
                CTLineDraw(line,context); context.restoreGState()
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,width: width,height: height,mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw AtlasError.allocation }
        pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0,0,width,height),mipmapLevel: 0,withBytes: $0.baseAddress!,bytesPerRow: width) }
        return texture
    }
    enum AtlasError: LocalizedError { case allocation; var errorDescription: String? { "Glyph atlas allocation failed" } }
}
