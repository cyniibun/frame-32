import AppKit
import AVFoundation
import CoreImage
import CoreText

let paper = NSColor(calibratedWhite: 0.95, alpha: 1)
let dim = NSColor(calibratedWhite: 0.46, alpha: 1)
// Fixed-face CTFont rendering avoids the NSFont descriptor copy that crashed in
// CoreText TAttributes::ApplyFont while drawing a custom button.
private var drawingFonts: [String: CTFont] = [:]
func text(_ string: String, _ rect: NSRect, size: CGFloat = 10, color: NSColor = paper, weight: NSFont.Weight = .regular) {
    guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
    let face = weight.rawValue >= NSFont.Weight.medium.rawValue ? "Menlo-Bold" : "Menlo-Regular"
    let key = "\(face)-\(size)"
    let font: CTFont
    if let cached = drawingFonts[key] { font = cached }
    else { font = CTFontCreateWithName(face as CFString,size,nil); drawingFonts[key] = font }
    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string,attributes: attributes))
    let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…",attributes: attributes))
    let drawn = CTLineCreateTruncatedLine(line,Double(rect.width),.end,ellipsis) ?? line
    context.saveGState(); context.clip(to: rect)
    context.textMatrix = .identity
    context.translateBy(x: rect.minX,y: rect.minY+size)
    context.scaleBy(x: 1,y: -1); context.textPosition = .zero
    CTLineDraw(drawn,context); context.restoreGState()
}

func rule(_ a: NSPoint, _ b: NSPoint, color: NSColor = NSColor(white: 0.19, alpha: 1)) {
    color.setStroke(); let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = 1; p.stroke()
}
class BlackPanel: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirty: NSRect) { NSColor(white: 0.025, alpha: 1).setFill(); bounds.fill(); NSColor(white: 0.22, alpha: 1).setStroke(); bounds.insetBy(dx: 0.5, dy: 0.5).frame() }
}
final class SignalButton: NSControl {
    var title: String { didSet { setAccessibilityLabel(title); needsDisplay = true } }
    var active = false { didSet { needsDisplay = true } }
    var icon: String
    var invoke: (() -> Void)?
    var hover = false
    init(_ title: String, icon: String = "", action: (() -> Void)? = nil) {
        self.title = title; self.icon = icon; invoke = action
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() { trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited,.activeInKeyWindow], owner: self)); super.updateTrackingAreas() }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); invoke?() }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 || event.keyCode == 36 { invoke?() } else { super.keyDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { invoke?(); return true }
    override func draw(_ dirty: NSRect) {
        (active ? paper : NSColor(white: hover ? 0.12 : 0.035, alpha: 1)).setFill(); bounds.fill()
        (active ? paper : NSColor(white: hover ? 0.65 : 0.23, alpha: 1)).setStroke(); bounds.insetBy(dx: 0.5, dy: 0.5).frame()
        let ink: NSColor = active ? .black : paper
        if !icon.isEmpty {
            let x: CGFloat = 12, y = bounds.midY-7
            ink.setStroke(); ink.setFill()
            let path = NSBezierPath(); path.lineWidth = 1.2
            switch icon {
            case "●":
                if active { NSRect(x: x+2,y: y+2,width: 10,height: 10).fill() }
                else { NSBezierPath(ovalIn: NSRect(x: x+1,y: y+1,width: 12,height: 12)).fill() }
            case "▦":
                for row in 0..<2 { for col in 0..<2 { NSRect(x: x+CGFloat(col)*8,y: y+CGFloat(row)*8,width: 5,height: 5).frame() } }
            case "◐":
                let oval = NSRect(x: x,y: y,width: 14,height: 14); NSBezierPath(ovalIn: oval).stroke()
                NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: NSRect(x: x,y: y,width: 7,height: 14)).addClip(); NSBezierPath(ovalIn: oval).fill(); NSGraphicsContext.restoreGraphicsState()
            case "≡":
                for i in 0..<3 {
                    let yy = y+CGFloat(i)*6
                    path.move(to: NSPoint(x: x,y: yy)); path.line(to: NSPoint(x: x+15,y: yy))
                    NSRect(x: x+CGFloat([4,11,7][i]),y: yy-2,width: 2,height: 5).fill()
                }; path.stroke()
            default:
                path.move(to: NSPoint(x: x+1,y: y+5)); path.line(to: NSPoint(x: x+7,y: y+11)); path.line(to: NSPoint(x: x+13,y: y+5)); path.stroke()
            }
        }
        text(title,NSRect(x: icon.isEmpty ? 10 : 37,y: (bounds.height-13)/2,width: bounds.width-(icon.isEmpty ? 18 : 43),height: 15),size: 10,color: ink,weight: .medium)
    }
}
final class ParameterTrack: NSControl, NSTextFieldDelegate {
    let name: String
    let limits: ClosedRange<Float>
    let initial: Float
    var value: Float { didSet { needsDisplay = true; setAccessibilityValue(formatted) } }
    var changed: ((Float)->Void)?
    var valueDisplay: ((Float)->String)? { didSet { setAccessibilityValue(formatted); needsDisplay = true } }
    var editor: NSTextField?
    var formatted: String { if let valueDisplay { return valueDisplay(value) }; return name == "TEMP" ? String(format: "%.0f K",value) : String(format: "%+.2f",value) }
    init(_ name: String, range: ClosedRange<Float>, value: Float, defaultValue: Float, changed: @escaping (Float)->Void) {
        self.name = name; limits = range; initial = defaultValue; self.value = value; self.changed = changed
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.slider); setAccessibilityLabel(name); setAccessibilityValue(formatted)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirty: NSRect) {
        text(name,NSRect(x: 0,y: 0,width: bounds.width-90,height: 13),size: 9,color: dim)
        text(formatted,NSRect(x: bounds.width-76,y: 0,width: 76,height: 13),size: 10)
        let y: CGFloat = 27
        rule(NSPoint(x: 0,y: y),NSPoint(x: bounds.width,y: y))
        let x = CGFloat((value-limits.lowerBound)/(limits.upperBound-limits.lowerBound)) * bounds.width
        rule(NSPoint(x: 0,y: y),NSPoint(x: x,y: y),color: paper)
        paper.setFill(); NSRect(x: max(0,min(bounds.width-3,x-1)),y: y-4,width: 3,height: 9).fill()
    }
    func update(_ event: NSEvent) {
        let x = convert(event.locationInWindow,from: nil).x
        value = limits.lowerBound + Float(max(0,min(1,x / max(1,bounds.width)))) * (limits.upperBound-limits.lowerBound)
        changed?(value)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow,from: nil)
        if point.x > bounds.width-90 && point.y < 16 { beginEditing(); return }
        if event.clickCount == 2 { value = initial; changed?(value) } else { update(event) }
    }
    func beginEditing() {
        guard editor == nil else { return }
        let field = NSTextField(frame: NSRect(x: bounds.width-85,y: -2,width: 85,height: 19))
        field.stringValue = String(value); field.isBordered = false; field.drawsBackground = true; field.backgroundColor = NSColor(white: 0.12,alpha: 1); field.textColor = paper; field.font = .monospacedSystemFont(ofSize: 10,weight: .regular)
        field.target = self; field.action = #selector(commitEditing); field.delegate = self; editor = field; addSubview(field); window?.makeFirstResponder(field); field.selectText(nil)
    }
    @objc func commitEditing() { finishEditing(restoreFocus: true) }
    func controlTextDidEndEditing(_ notification: Notification) { finishEditing(restoreFocus: false) }
    func finishEditing(restoreFocus: Bool) {
        guard let field = editor else { return }; editor = nil
        if let number = Float(field.stringValue), number.isFinite { value = min(limits.upperBound,max(limits.lowerBound,number)); changed?(value) }
        field.removeFromSuperview()
        if restoreFocus { window?.makeFirstResponder(self) }
    }

    override func mouseDragged(with event: NSEvent) { update(event) }
    func step(_ delta: Float) { value = max(limits.lowerBound,min(limits.upperBound,value + delta*(limits.upperBound-limits.lowerBound)/100)); changed?(value) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 123 { step(-1) } else if event.keyCode == 124 { step(1) } else { super.keyDown(with: event) } }
    override func accessibilityPerformIncrement() -> Bool { step(1); return true }
    override func accessibilityPerformDecrement() -> Bool { step(-1); return true }
}
final class EffectCard: NSControl {
    let index: Int
    let title: String
    let subtitle: String
    var image: NSImage? { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var invoke: (() -> Void)?
    init(_ index: Int, _ title: String, _ subtitle: String) {
        self.index = index; self.title = title; self.subtitle = subtitle
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { invoke?() }
    override func accessibilityPerformPress() -> Bool { invoke?(); return true }
    override func draw(_ dirty: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        let art = NSRect(x: 1,y: 1,width: bounds.width-2,height: bounds.height-44)
        if let image { image.draw(in: art,from: .zero,operation: .copy,fraction: 1,respectFlipped: true,hints: nil) }
        else { text("SIGNAL / LOADING",NSRect(x: 12,y: 30,width: 160,height: 14),color: dim) }
        (selected ? paper : NSColor(white: 0.22,alpha: 1)).setStroke(); let p = NSBezierPath(rect: bounds.insetBy(dx: 1,dy: 1)); p.lineWidth = selected ? 2 : 1; p.stroke()
        text(title,NSRect(x: 10,y: bounds.height-35,width: bounds.width-20,height: 14),size: 10,weight: .bold)
        text(subtitle,NSRect(x: 10,y: bounds.height-19,width: bounds.width-20,height: 12),size: 8,color: dim)
        if selected { paper.setFill(); NSRect(x: bounds.width-17,y: 9,width: 7,height: 7).fill() }
    }
}
final class StageMarks: NSView {
    var effectName = "CLEAN SIGNAL" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirty: NSRect) {
        let inset: CGFloat = 16, length: CGFloat = 16
        for x in [inset,bounds.width-inset] { for y in [inset,bounds.height-inset] {
            rule(NSPoint(x: x,y: y),NSPoint(x: x+(x<bounds.midX ? length : -length),y: y),color: NSColor(white: 0.7,alpha: 0.7))
            rule(NSPoint(x: x,y: y),NSPoint(x: x,y: y+(y<bounds.midY ? length : -length)),color: NSColor(white: 0.7,alpha: 0.7))
        } }
        text("01 / LIVE INPUT",NSRect(x: 27,y: 25,width: 180,height: 15),size: 9)
        text(effectName,NSRect(x: 27,y: bounds.height-39,width: 250,height: 15),size: 10)
    }

}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let engine = CameraEngine()
    var settings = SignalSettings()
    let settingsStore = SettingsStore()
    let presetStore = PresetStore()
    var presetPanel: PresetPanel!
    var presetsOpen = false
    let presetsButton = SignalButton("PRESETS")
    var pendingSave: DispatchWorkItem?
    var window: NSWindow!
    var preview: Preview!
    let header = BlackPanel(), rail = BlackPanel(), browser = BlackPanel(), inspector = BlackPanel()
    let marks = StageMarks()
    let brand = NSTextField(labelWithString: "FRAME//32")
    let status = NSTextField(labelWithString: "INITIALIZING SIGNAL")
    var recordButton = SignalButton("REC",icon: "●")
    var effectsButton = SignalButton("EFFECTS",icon: "▦")
    var colorsButton = SignalButton("COLOR",icon: "◐")
    var paramsButton = SignalButton("TUNE",icon: "≡")
    var cameraButton = SignalButton("CAMERA",icon: "⌄")
    var cards: [EffectCard] = []
    var tracks: [NSControl] = []
    let browserScroll = NSScrollView()
    let browserContent = BlackPanel()
    let parameterScroll = NSScrollView()
    let parameterContent = BlackPanel()
    var thumbnailProcessor: SignalProcessor?
    var cameras: [AVCaptureDevice] = []
    var selectedCamera = ""
    var fillsWindow = UserDefaults.standard.bool(forKey: "previewFillsWindow")
    var stageMarksVisible = true
    var cameraOnly = false, browserOpen = false, inspectorMode = 0, recording = false, finishing = false
    var lastFile: URL?
    var monitor: Any?
    let effects = EffectRegistry.all
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { settings = try settingsStore.load() } catch { status.stringValue = error.localizedDescription.uppercased() }
        do { try presetStore.load() } catch { status.stringValue = error.localizedDescription.uppercased() }
        engine.update(settings)
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 960,height: 650),styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
        window.title = "FRAME//32"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = .black; window.minSize = NSSize(width: 560,height: 420); window.delegate = self
        window.isMovableByWindowBackground = true
        let root = BlackPanel(); window.contentView = root
        preview = Preview(device: engine.device)
        preview.fillsWindow=fillsWindow
        presetPanel = PresetPanel(store: presetStore)
        presetPanel.currentSettings = { [weak self] in self?.settings ?? SignalSettings() }
        presetPanel.recall = { [weak self] preset in
            guard let self else { return }
            self.settings = preset.applying(to: self.settings); self.commitSettings()
            self.cards.forEach { $0.selected = self.effects[$0.index].id == self.settings.activeEffect }
            self.marks.effectName = self.settings.definition.title
            if self.inspectorMode != 0 { self.buildInspector() }
        }
        presetPanel.close = { [weak self] in self?.presetsOpen = false; self?.layout() }
        presetsButton.invoke = { [weak self] in self?.togglePresets() }
        for view in [preview!,marks,header,rail,browser,inspector,presetPanel!] { root.addSubview(view) }
        brand.font = .monospacedSystemFont(ofSize: 17,weight: .heavy); brand.textColor = paper
        header.addSubview(brand)
        status.font = .monospacedSystemFont(ofSize: 9,weight: .regular); status.textColor = dim; status.lineBreakMode = .byTruncatingMiddle
        header.addSubview(status)
        header.addSubview(presetsButton)
        recordButton.invoke = { [weak self] in self?.toggleRecording() }
        effectsButton.invoke = { [weak self] in self?.toggleEffects() }
        colorsButton.invoke = { [weak self] in self?.showInspector(1) }
        paramsButton.invoke = { [weak self] in self?.showInspector(2) }
        cameraButton.invoke = { [weak self] in self?.chooseCamera() }
        for button in [recordButton,effectsButton,colorsButton,paramsButton,cameraButton] { rail.addSubview(button) }
        let close = SignalButton("CLOSE ×"); close.invoke = { [weak self] in self?.toggleEffects() }; close.identifier = NSUserInterfaceItemIdentifier("close"); browser.addSubview(close)
        browserScroll.drawsBackground = false; browserScroll.hasVerticalScroller = false
        browserScroll.documentView = browserContent; browser.addSubview(browserScroll)
        for i in effects.indices {
            let effect = effects[i]
            let card = EffectCard(i,effect.title,effect.subtitle); card.selected = effect.id == settings.activeEffect
            card.invoke = { [weak self] in self?.selectEffect(i) }; browserContent.addSubview(card); cards.append(card)
        }
        marks.effectName = settings.definition.title
        engine.onFrame = { [weak self] image in self?.preview.receive(image) }
        engine.onReferenceFrame = { [weak self] image in
            guard let self else { return }
            let scale = 384 / image.extent.width
            let small = image.transformed(by: CGAffineTransform(scaleX: scale,y: scale))
            self.engine.queue.async {
                do {
                    if self.thumbnailProcessor == nil { self.thumbnailProcessor = try SignalProcessor(device: self.engine.device) }
                    self.thumbnail(0,small)
                } catch { self.engine.status("Thumbnail initialization failed") }
            }
        }
        engine.onStatus = { [weak self] message in
            self?.status.stringValue = message.uppercased()
            if message.hasPrefix("Recording error") { self?.recording = false; self?.recordButton.title = "REC"; self?.recordButton.active = false }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow, self.window.attachedSheet == nil else { return event }
            if event.keyCode == 53 { self.browserOpen = false; self.inspectorMode = 0; self.presetsOpen = false; self.layout(); return nil }
            return event
        }
        layout(); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let fingerprint=Bundle.main.infoDictionary?["FRAME32GPUFingerprint"] as? String
        let verified=UserDefaults.standard.string(forKey: "lastPassedGPUFingerprint")
        if CommandLine.arguments.contains("--verify-effects") || fingerprint == nil || fingerprint != verified { runGPUChecks() }
        AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async {
            if granted { self.discoverCameras() } else { self.status.stringValue = "CAMERA ACCESS DENIED / CHECK SYSTEM SETTINGS" }
        } }
    }
    func windowDidResize(_ notification: Notification) { layout() }
    func layout() {
        guard let root = window?.contentView else { return }
        let w = root.bounds.width, h = root.bounds.height
        header.frame = NSRect(x: 0,y: 0,width: w,height: 54)
        rail.frame = NSRect(x: 0,y: h-76,width: w,height: 76)
        brand.frame = NSRect(x: 82,y: 17,width: 155,height: 24)
        status.frame = NSRect(x: 248,y: 23,width: max(70,w-390),height: 14)
        presetsButton.frame = NSRect(x: w-132,y: 15,width: 116,height: 28)
        presetsButton.active = presetsOpen
        presetPanel.frame = NSRect(x: 16,y: 66,width: w-32,height: min(480,h-154))
        presetPanel.isHidden = cameraOnly || !presetsOpen
        presetPanel.needsLayout = true
        preview.frame = cameraOnly ? root.bounds : NSRect(x: 0,y: 54,width: w,height: max(1,h-130))
        marks.frame = preview.frame
        header.isHidden = cameraOnly; rail.isHidden = cameraOnly; marks.isHidden = !stageMarksVisible
        let widths: [CGFloat] = [88,110,100,90,max(110,w-468)]
        var x: CGFloat = 16
        for (i,button) in [recordButton,effectsButton,colorsButton,paramsButton,cameraButton].enumerated() { button.frame = NSRect(x: x,y: 18,width: widths[i],height: 38); x += widths[i]+8 }
        effectsButton.active = browserOpen; colorsButton.active = inspectorMode == 1; paramsButton.active = inspectorMode == 2
        browser.isHidden = cameraOnly || !browserOpen
        inspector.isHidden = cameraOnly || inspectorMode == 0
        let cols = w < 760 ? 2 : 3
        let cardW = (w-64-CGFloat(cols-1)*10)/CGFloat(cols)
        let cardH: CGFloat = min(138,max(94,(h-240)/3))
        let rows = Int(ceil(Double(cards.count)/Double(cols)))
        let bh = min(h-170,55+CGFloat(rows)*(cardH+10)+12)
        browser.frame = NSRect(x: 16,y: max(65,h-76-bh-12),width: w-32,height: bh)
        browser.subviews.first?.frame = NSRect(x: browser.bounds.width-104,y: 10,width: 90,height: 28)
        browserScroll.frame = NSRect(x: 16,y: 50,width: w-64,height: max(60,bh-62))
        browserContent.frame = NSRect(x: 0,y: 0,width: w-64,height: CGFloat(rows)*(cardH+10))
        for (i,card) in cards.enumerated() { card.frame = NSRect(x: CGFloat(i%cols)*(cardW+10),y: CGFloat(i/cols)*(cardH+10),width: cardW,height: cardH) }
        let ih = min(h-150, inspectorMode == 1 ? 555 : 360)
        inspector.frame = NSRect(x: w-302,y: 66,width: 286,height: ih)
        layoutInspector()
        root.needsDisplay = true
    }
    func makeMenu() {
        let menu = NSMenu(); let ar = NSMenuItem(); menu.addItem(ar); ar.submenu = NSMenu()
        let hideApp=ar.submenu?.addItem(withTitle: "Hide FRAME//32",action: #selector(NSApplication.hide(_:)),keyEquivalent: "h")
        hideApp?.target=NSApp
        ar.submenu?.addItem(withTitle: "Quit FRAME//32",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q")
        let editRoot = NSMenuItem(); menu.addItem(editRoot)
        let edit = NSMenu(title: "Edit"); editRoot.submenu = edit
        for (name,selector,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            edit.addItem(withTitle: name,action: NSSelectorFromString(selector),keyEquivalent: key)
        }
        let vr = NSMenuItem(); menu.addItem(vr); let view = NSMenu(title: "View"); vr.submenu = view
        for (name,action,key) in [("Toggle Camera Only",#selector(toggleUI),"u"),("Effects",#selector(toggleEffects),"e"),("User Presets",#selector(togglePresets),"p"),("Color Controls",#selector(toggleColors),"k"),("Always on Top",#selector(togglePin(_:)),""),("Reveal Last Recording",#selector(revealLast),""),("Run GPU Effect Checks",#selector(runGPUChecks),"")] {
            let item = NSMenuItem(title: name,action: action,keyEquivalent: key); item.target = self; view.addItem(item)
        }
        let marksItem=NSMenuItem(title: "Show Camera Labels & Marks",action: #selector(toggleStageMarks(_:)),keyEquivalent: "h")
        marksItem.keyEquivalentModifierMask = [.command,.shift]
        marksItem.target=self; marksItem.state=stageMarksVisible ? .on : .off
        view.addItem(marksItem)
        let fillItem=NSMenuItem(title: "Fill Window",action: #selector(toggleFillWindow(_:)),keyEquivalent: "f")
        fillItem.keyEquivalentModifierMask = [.command,.shift]
        fillItem.target=self; fillItem.state=fillsWindow ? .on : .off
        view.addItem(fillItem)
        NSApp.mainMenu = menu
    }
    func discoverCameras() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera,.external],mediaType: .video,position: .unspecified).devices
        if let camera = cameras.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cameras.first { activate(camera) }
        else { status.stringValue = "NO CAMERA CONNECTED" }
    }
    func activate(_ camera: AVCaptureDevice) { selectedCamera = camera.uniqueID; cameraButton.title = camera.localizedName.uppercased(); engine.start(camera) }
    func chooseCamera() {
        guard !recording && !finishing else { status.stringValue = "STOP RECORDING TO CHANGE CAMERA"; return }
        let menu = NSMenu()
        for (i,camera) in cameras.enumerated() {
            let item = NSMenuItem(title: camera.localizedName,action: #selector(cameraItem(_:)),keyEquivalent: ""); item.target = self; item.tag = i; item.state = camera.uniqueID == selectedCamera ? .on : .off; menu.addItem(item)
        }
        menu.popUp(positioning: nil,at: NSPoint(x: 0,y: 0),in: cameraButton)
    }
    @objc func cameraItem(_ item: NSMenuItem) { activate(cameras[item.tag]) }
    func selectEffect(_ index: Int) {
        settings.activeEffect = effects[index].id; commitSettings(); cards.forEach { $0.selected = $0.index == index }
        marks.effectName = settings.definition.title; browserOpen = false
        if inspectorMode == 2 { buildInspector() }; layout()
    }
    @objc func toggleEffects() { browserOpen.toggle(); if browserOpen { inspectorMode = 0; presetsOpen = false }; layout() }
    @objc func togglePresets() { presetsOpen.toggle(); if presetsOpen { browserOpen = false; inspectorMode = 0; presetPanel.reload() }; layout() }
    @objc func toggleColors() { showInspector(1) }
    func showInspector(_ mode: Int) { inspectorMode = inspectorMode == mode ? 0 : mode; browserOpen = false; presetsOpen = false; buildInspector(); layout() }
    @objc func toggleFillWindow(_ item: NSMenuItem) {
        fillsWindow.toggle()
        preview.fillsWindow=fillsWindow
        item.state=fillsWindow ? .on : .off
        UserDefaults.standard.set(fillsWindow,forKey: "previewFillsWindow")
    }
    @objc func toggleStageMarks(_ item: NSMenuItem) {
        stageMarksVisible.toggle()
        item.state=stageMarksVisible ? .on : .off
        layout()
    }
    @objc func toggleUI() {
        let frame = window.frame
        cameraOnly.toggle()
        // Removing titled style removes system titlebar material too, within the same NSWindow.
        if cameraOnly { window.styleMask.remove(.titled) } else { window.styleMask.insert(.titled) }
        window.setFrame(frame,display: true); window.isMovableByWindowBackground = true
        layout()
    }
    @objc func togglePin(_ item: NSMenuItem) { item.state = item.state == .on ? .off : .on; window.level = item.state == .on ? .floating : .normal }
    func buildInspector() {
        inspector.subviews.forEach { $0.removeFromSuperview() }; tracks.removeAll()
        let close = SignalButton("×"); close.invoke = { [weak self] in self?.inspectorMode = 0; self?.layout() }; inspector.addSubview(close)
        let reset = SignalButton("RESET"); reset.invoke = { [weak self] in self?.resetParameters() }; inspector.addSubview(reset)
        parameterContent.subviews.forEach { $0.removeFromSuperview() }
        parameterScroll.drawsBackground = false; parameterScroll.hasVerticalScroller = false
        parameterScroll.documentView = parameterContent; inspector.addSubview(parameterScroll)
        func add(_ name: String,_ range: ClosedRange<Float>,_ path: WritableKeyPath<SignalSettings,Float>) {
            let track = ParameterTrack(name,range: range,value: settings[keyPath: path],defaultValue: SignalSettings()[keyPath: path]) { [weak self] value in guard let self else { return }; self.settings[keyPath: path] = value; self.commitSettings() }
            tracks.append(track); parameterContent.addSubview(track)
        }
        if inspectorMode == 1 {
            add("EXPOSURE",-3...3,\.exposure); add("CONTRAST",0.5...2,\.contrast); add("SATURATION",0...2,\.saturation); add("HUE",-180...180,\.hue)
            add("GAMMA",0.3...2.5,\.gamma); add("TEMP",2500...10000,\.temperature); add("HIGHLIGHTS",0...1,\.highlights); add("SHADOWS",0...1,\.shadows)
            add("SHARPEN",0...2,\.sharpen); add("GRAIN",0...1,\.grain); add("DITHER",0...1,\.dither)
        } else {
            add("INTENSITY",0...1,\.intensity)
            if settings.effect >= 10 || settings.activeEffect == .matrix {
                let clear=SignalButton("CLEAR HISTORY / RESEED")
                clear.invoke = { [weak self] in self?.engine.clearHistory() }
                tracks.append(clear); parameterContent.addSubview(clear)
            }
            for parameter in settings.definition.parameters {
                let key = parameter.key
                switch parameter.kind {
                case let .choices(options):
                    let control = ChoiceParameter(parameter.label,options: options,selection: Int(settings.value(key))) { [weak self] index in
                        guard let self else { return }; self.settings.set(key,Float(index)); self.commitSettings(); self.syncParameterTracks()
                    }
                    tracks.append(control); parameterContent.addSubview(control)
                case .seed:
                    let control = SeedParameter(value: settings.seed) { [weak self] value in
                        self?.settings.seed = value; self?.commitSettings()
                    }
                    tracks.append(control); parameterContent.addSubview(control)
                default:
                    let track = ParameterTrack(parameter.label,range: parameter.range,value: settings.value(key),defaultValue: parameter.defaultValue) { [weak self] value in
                        guard let self else { return }; self.settings.set(key,value); self.commitSettings(); self.syncParameterTracks()
                    }
                    track.identifier = NSUserInterfaceItemIdentifier(key); track.valueDisplay = parameter.display
                    tracks.append(track); parameterContent.addSubview(track)
                }
            }
        }

        let hint = NSTextField(labelWithString: "SCROLL FOR MORE")
        hint.font = .monospacedSystemFont(ofSize: 8,weight: .regular); hint.textColor = dim; hint.identifier = NSUserInterfaceItemIdentifier("scrollHint"); inspector.addSubview(hint)
        let label = NSTextField(labelWithString: inspectorMode == 1 ? "COLOR // GLOBAL" : settings.definition.title); label.font = .monospacedSystemFont(ofSize: 11,weight: .bold); label.textColor = paper; label.identifier = NSUserInterfaceItemIdentifier("heading"); inspector.addSubview(label)
        layoutInspector()
    }
    func layoutInspector() {
        guard inspector.subviews.count >= 3 else { return }
        inspector.subviews[0].frame = NSRect(x: 246,y: 9,width: 28,height: 27)
        inspector.subviews[1].frame = NSRect(x: 200,y: inspector.bounds.height-37,width: 70,height: 25)
        inspector.subviews.last?.frame = NSRect(x: 16,y: 16,width: 222,height: 17)
        parameterScroll.frame = NSRect(x: 12,y: 46,width: 262,height: max(25,inspector.bounds.height-92))
        parameterContent.frame = NSRect(x: 0,y: 0,width: 262,height: CGFloat(tracks.count)*43)
        for (i,track) in tracks.enumerated() { track.frame = NSRect(x: 4,y: CGFloat(i)*43,width: 254,height: 37) }
        if let hint = inspector.subviews.first(where: { $0.identifier?.rawValue == "scrollHint" }) {
            hint.frame = NSRect(x: 16,y: inspector.bounds.height-31,width: 175,height: 13)
            hint.isHidden = parameterContent.frame.height <= parameterScroll.bounds.height
        }

    }
    func syncParameterTracks() {
        guard inspectorMode == 2 else { return }
        for case let track as ParameterTrack in tracks {
            if let key = track.identifier?.rawValue { track.value = settings.value(key) }
        }
    }
    func commitSettings() {
        settings = settings.normalized(); engine.update(settings)
        pendingSave?.cancel()
        let snapshot = settings
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { try self.settingsStore.save(snapshot) }
            catch { self.status.stringValue = "SETTINGS / " + error.localizedDescription.uppercased() }
        }
        pendingSave = item; DispatchQueue.main.asyncAfter(deadline: .now()+0.4,execute: item)
    }
    func resetParameters() {
        if inspectorMode == 1 { settings.resetColor() } else { settings.resetEffect(); engine.clearHistory() }
        commitSettings(); buildInspector()
    }
    func thumbnail(_ index: Int,_ chart: CIImage) {
        guard index < effects.count, let processor = thumbnailProcessor else { return }
        var s = SignalSettings(); s.activeEffect = effects[index].id; s.intensity = 1
        processor.submit(chart,settings: s,time: 3.7) { buffer in
            if let buffer, let cg = processor.context.createCGImage(CIImage(cvPixelBuffer: buffer),from: chart.extent) {
                let image = NSImage(cgImage: cg,size: chart.extent.size)
                DispatchQueue.main.async { self.cards[index].image = image }
            }
            self.engine.queue.async { self.thumbnail(index+1,chart) }
        }
    }
    @objc func toggleRecording() {
        guard !finishing else { return }
        if recording {
            recording = false; finishing = true; recordButton.title = "WAIT"
            engine.stopRecording { url in self.lastFile = url; self.finishing = false; self.recordButton.title = "REC"; self.recordButton.active = false }
        } else {
            guard !cameras.isEmpty else { return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.quickTimeMovie]; panel.nameFieldStringValue = "FRAME32-\(Int(Date().timeIntervalSince1970)).mov"
            panel.beginSheetModal(for: window) { result in
                guard result == .OK, let url = panel.url else { return }
                guard !FileManager.default.fileExists(atPath: url.path) else { self.status.stringValue = "CHOOSE A NEW FILENAME"; return }
                self.recording = true; self.recordButton.title = "STOP"; self.recordButton.active = true; self.engine.beginRecording(url)
            }
        }
    }
    @objc func runGPUChecks() {
        status.stringValue = "RUNNING SYNTHETIC GPU CHECKS"
        DispatchQueue.global(qos: .utility).async {
            let message: String
            do { message = try EffectVerification.run(device: self.engine.device) }
            catch { message = "GPU CHECK FAILED / " + error.localizedDescription }
            let reportURL: URL
            if let index = CommandLine.arguments.firstIndex(of: "--verification-report"), CommandLine.arguments.indices.contains(index+1) {
                reportURL = URL(fileURLWithPath: CommandLine.arguments[index+1])
            } else { reportURL = self.settingsStore.url.deletingLastPathComponent().appendingPathComponent("verification-report.txt") }
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
            let fingerprint=Bundle.main.infoDictionary?["FRAME32GPUFingerprint"] as? String ?? "unknown"
            let report = "FRAME32 " + version + "\n" + ISO8601DateFormatter().string(from: Date()) + "\nGPU SOURCE " + fingerprint + "\n" + message + "\n"
            try? FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(),withIntermediateDirectories: true)
            try? report.write(to: reportURL,atomically: true,encoding: .utf8)
            if message.hasPrefix("PASS / "),fingerprint != "unknown" {
                UserDefaults.standard.set(fingerprint,forKey: "lastPassedGPUFingerprint")
            }
            DispatchQueue.main.async { self.status.stringValue = message; self.status.toolTip = message }
        }
    }
    @objc func revealLast() { if let lastFile { NSWorkspace.shared.activateFileViewerSelecting([lastFile]) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pendingSave?.cancel()
        do { try settingsStore.save(settings) } catch { /* Preserve incompatible settings on disk. */ }
        if finishing { return .terminateCancel }
        if recording { finishing = true; engine.stopRecording { _ in sender.reply(toApplicationShouldTerminate: true) }; return .terminateLater }
        return .terminateNow
    }
}
