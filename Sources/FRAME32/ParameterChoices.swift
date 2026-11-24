import AppKit

final class ChoiceParameter: NSControl {
    let title: String, options: [String]
    var selection: Int
    var changed: (Int)->Void
    init(_ title: String,options: [String],selection: Int,changed: @escaping (Int)->Void) {
        self.title = title; self.options = options; self.selection = selection; self.changed = changed
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(title); setAccessibilityValue(options[selection])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirty: NSRect) {
        text(title,NSRect(x: 0,y: 0,width: bounds.width,height: 12),size: 9,color: dim)
        text("‹  " + options[selection] + "  ›",NSRect(x: 0,y: 17,width: bounds.width,height: 17),size: 10)
        rule(NSPoint(x: 0,y: 36),NSPoint(x: bounds.width,y: 36))
    }
    func advance(_ step: Int) {
        selection = (selection+step+options.count)%options.count
        setAccessibilityValue(options[selection]); needsDisplay = true; changed(selection)
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); advance(convert(event.locationInWindow,from: nil).x < bounds.width/2 ? -1 : 1) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 123 { advance(-1) } else if [124,49,36].contains(event.keyCode) { advance(1) } else { super.keyDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { advance(1); return true }
    override func accessibilityPerformIncrement() -> Bool { advance(1); return true }
    override func accessibilityPerformDecrement() -> Bool { advance(-1); return true }
}

final class SeedParameter: NSControl, NSTextFieldDelegate {
    var value: UInt32
    var changed: (UInt32)->Void
    var editor: NSTextField?
    init(value: UInt32,changed: @escaping (UInt32)->Void) {
        self.value = value; self.changed = changed
        super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("SEED edit or regenerate"); setAccessibilityValue(String(value))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirty: NSRect) {
        text("SEED",NSRect(x: 0,y: 0,width: 80,height: 13),size: 9,color: dim)
        text(String(value),NSRect(x: 0,y: 17,width: bounds.width-48,height: 16),size: 11)
        text("NEW",NSRect(x: bounds.width-40,y: 17,width: 40,height: 16),size: 10)
        rule(NSPoint(x: 0,y: 36),NSPoint(x: bounds.width,y: 36))
    }
    func regenerate() { value = value &* 1664525 &+ 1013904223; publish() }
    func publish() { setAccessibilityValue(String(value)); needsDisplay = true; changed(value) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if convert(event.locationInWindow,from: nil).x > bounds.width-50 { regenerate(); return }
        guard editor == nil else { return }
        let field = NSTextField(frame: NSRect(x: 0,y: 15,width: bounds.width-50,height: 20))
        field.stringValue = String(value); field.isBordered = false; field.backgroundColor = NSColor(white: 0.12,alpha: 1); field.textColor = paper; field.font = .monospacedSystemFont(ofSize: 11,weight: .regular)
        field.target = self; field.action = #selector(commit); field.delegate = self; editor = field; addSubview(field); window?.makeFirstResponder(field); field.selectText(nil)
    }
    @objc func commit() { finishEditing(restoreFocus: true) }
    func controlTextDidEndEditing(_ notification: Notification) { finishEditing(restoreFocus: false) }
    func finishEditing(restoreFocus: Bool) {
        guard let field = editor else { return }; editor = nil
        if let number = UInt32(field.stringValue.trimmingCharacters(in: .whitespaces)) { value = number; publish() }
        field.removeFromSuperview()
        if restoreFocus { window?.makeFirstResponder(self) }
    }
    override func accessibilityPerformPress() -> Bool { regenerate(); return true }
    override func keyDown(with event: NSEvent) { if event.keyCode == 49 { regenerate() } else { super.keyDown(with: event) } }
}
