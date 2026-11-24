import AppKit
import AVFoundation
import MetalKit
import CoreImage
import CoreImage.CIFilterBuiltins

// All camera, effect and writer state belongs to this serial queue. UI receives snapshots only.
final class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "FRAME32.capture", qos: .userInitiated)
    let session = AVCaptureSession()
    let device = MTLCreateSystemDefaultDevice()!
    lazy var context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    var onFrame: ((CIImage) -> Void)?
    var onStatus: ((String) -> Void)?
    var settings = SignalSettings()
    var failedEffect: EffectID?
    var generation: UInt64 = 0
    var clock = FrameClock()
    var referenceFrames = 0
    var onReferenceFrame: ((CIImage)->Void)?
    lazy var processor: SignalProcessor? = {
        do {
            let processor=try SignalProcessor(device: device)
            processor.onError = { [weak self] message in
                guard let self else { return }
                self.queue.async {
                    guard self.failedEffect == nil else { return }
                    self.failedEffect=self.settings.activeEffect
                    self.generation &+= 1; self.processor?.resetTemporal()
                    self.status("EFFECT UNAVAILABLE / LIVE CLEAN PREVIEW / " + message)
                }
            }
            return processor
        }
        catch { status("GPU initialization failed: \(error.localizedDescription)"); return nil }
    }()
    var writer: AVAssetWriter?
    var writerInput: AVAssetWriterInput?
    var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var destination: URL?
    var recordingRequested = false
    var lastPTS = CMTime.invalid
    var frameCount = 0
    var dropped = 0
    func status(_ value: String) { DispatchQueue.main.async { self.onStatus?(value) } }
    func start(_ camera: AVCaptureDevice) {
        queue.async {
            guard !self.recordingRequested && self.writer == nil else { self.status("Stop recording before changing camera"); return }
            self.generation &+= 1; self.processor?.resetTemporal(); self.clock = FrameClock(); self.referenceFrames = 0
            self.session.stopRunning()
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else { throw EngineError.message("Camera input unavailable") }
                self.session.addInput(input)
                if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                else { self.session.sessionPreset = .high }
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                let formats = output.availableVideoPixelFormatTypes
                let preferred = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                if let format = preferred.first(where: { formats.contains($0) }) {
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
                }
                guard self.session.canAddOutput(output) else { throw EngineError.message("Camera output unavailable") }
                self.session.addOutput(output)
                output.setSampleBufferDelegate(self, queue: self.queue)
                self.session.commitConfiguration()
                self.session.startRunning()
                self.status(camera.localizedName)
            } catch {
                self.session.commitConfiguration()
                self.status(error.localizedDescription)
            }
        }
    }
    func clearHistory() {
        queue.async { self.generation &+= 1; self.processor?.resetTemporal() }
    }
    func update(_ settings: SignalSettings) {
        let normalized = settings.normalized()
        queue.async {
            if self.settings.activeEffect != normalized.activeEffect { self.generation &+= 1; self.processor?.resetTemporal() }
            self.failedEffect = nil
            self.settings = normalized
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard let processor else { return }
        let timing = clock.advance(CMTimeGetSeconds(pts))
        if timing.discontinuity { generation &+= 1; processor.resetTemporal() }
        let submittedGeneration = generation
        referenceFrames += 1
        if referenceFrames == 30 { onReferenceFrame?(CIImage(cvPixelBuffer: buffer)) }
        var renderSettings=settings
        if failedEffect != nil { renderSettings.activeEffect = .clean }
        processor.submit(CIImage(cvPixelBuffer: buffer), settings: renderSettings, time: timing.elapsed) { target in
            self.queue.async {
                guard submittedGeneration == self.generation, let target else { self.dropped += 1; return }
                self.onFrame?(CIImage(cvPixelBuffer: target))
                // Failed-effect preview recovery must never be written as the requested look.
                if self.failedEffect == nil { self.appendProcessed(target, pts: pts) }
            }
        }
    }
    func appendProcessed(_ buffer: CVPixelBuffer, pts: CMTime) {
        if recordingRequested {
            do {
                if writer == nil { try prepareWriter(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), pts: pts) }
                guard let writer, let input = writerInput, let adaptor else { return }
                guard writer.status == .writing else { throw EngineError.message(writer.error?.localizedDescription ?? "Encoder stopped") }
                guard input.isReadyForMoreMediaData else { dropped += 1; return }
                guard !lastPTS.isValid || pts > lastPTS else { dropped += 1; return }
                guard adaptor.append(buffer, withPresentationTime: pts) else { throw EngineError.message(writer.error?.localizedDescription ?? "Frame write failed") }
                lastPTS = pts
                frameCount += 1
            } catch { failRecording(error.localizedDescription) }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didDrop sample: CMSampleBuffer, from connection: AVCaptureConnection) { dropped += 1 }
    func beginRecording(_ url: URL) {
        queue.async {
            guard !self.recordingRequested && self.writer == nil else { return }
            self.destination = url; self.recordingRequested = true; self.frameCount = 0; self.dropped = 0; self.lastPTS = .invalid
            self.status("REC • waiting for camera frame")
        }
    }
    func prepareWriter(width: Int, height: Int, pts: CMTime) throws {
        guard let destination else { throw EngineError.message("No save destination") }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 18_000_000], AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw EngineError.message("Unsupported recording settings") }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.startWriting() else { throw EngineError.message(writer.error?.localizedDescription ?? "Cannot start encoder") }
        writer.startSession(atSourceTime: pts)
        self.writer = writer; self.writerInput = input; self.adaptor = adaptor
        status("REC • \(width)×\(height) • H.264 • no audio")
    }
    func stopRecording(completion: @escaping (URL?) -> Void) {
        queue.async {
            self.recordingRequested = false
            guard let writer = self.writer else { self.status("Ready"); DispatchQueue.main.async { completion(nil) }; return }
            self.writerInput?.markAsFinished()
            writer.finishWriting {
                self.queue.async {
                    let url = writer.status == .completed ? self.destination : nil
                    self.status(url == nil ? (writer.error?.localizedDescription ?? "Recording failed") : "Saved • \(self.frameCount) frames • \(self.dropped) drops")
                    self.writer = nil; self.writerInput = nil; self.adaptor = nil
                    DispatchQueue.main.async { completion(url) }
                }
            }
        }
    }
    func failRecording(_ message: String) {
        recordingRequested = false; writer?.cancelWriting(); writer = nil; writerInput = nil; adaptor = nil
        status("Recording error • \(message)")
    }
    enum EngineError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
    }
}

// Latest-frame mailbox: capture never enqueues an unbounded sequence of UI callbacks.
final class Preview: MTKView, MTKViewDelegate {
    let lock = NSLock()
    var latest: CIImage?
    var pendingDraw = false
    var fillsWindow = false { didSet { needsDisplay = true } }
    let ci: CIContext
    let commands: MTLCommandQueue
    let slots = DispatchSemaphore(value: 2)
    init(device: MTLDevice) {
        ci = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        commands = device.makeCommandQueue()!
        super.init(frame: .zero, device: device)
        framebufferOnly = false; isPaused = true; enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm; clearColor = MTLClearColorMake(0, 0, 0, 1)
        delegate = self
    }
    required init(coder: NSCoder) { fatalError() }
    func receive(_ image: CIImage) {
        lock.lock(); latest = image
        let schedule = !pendingDraw; pendingDraw = true; lock.unlock()
        if schedule { DispatchQueue.main.async { self.needsDisplay = true } }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { needsDisplay = true }
    func draw(in view: MTKView) {
        lock.lock(); let image = latest; pendingDraw = false; lock.unlock()
        guard let image, slots.wait(timeout: .now()) == .success else { return }
        guard let drawable = currentDrawable, let command = commands.makeCommandBuffer() else { slots.signal(); return }
        let size = drawableSize
        guard let placement=PreviewLayout.placement(source: image.extent.size,target: size,fill: fillsWindow) else { slots.signal(); return }
        let scale=placement.width/image.extent.width
        let adjusted=image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale,y: scale))
            .transformed(by: CGAffineTransform(translationX: placement.minX,y: placement.minY))
        let bounds = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: bounds)
        ci.render(adjusted.composited(over: black), to: drawable.texture, commandBuffer: command, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        command.addCompletedHandler { [slots] _ in slots.signal() }
        command.present(drawable); command.commit()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let app = App()
application.delegate = app
application.run()
