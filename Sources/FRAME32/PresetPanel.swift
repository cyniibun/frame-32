import AppKit

final class PresetRow: NSControl {
    let preset: UserPreset
    let selected: Bool
    var invoke: (() -> Void)?
    init(_ preset: UserPreset,selected: Bool) {
        self.preset = preset; self.selected = selected; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(preset.name + " / " + preset.settings.definition.title)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { invoke?() }
    override func accessibilityPerformPress() -> Bool { invoke?(); return true }
    override func draw(_ dirty: NSRect) {
        NSColor(white: selected ? 0.12 : 0.03,alpha: 1).setFill(); bounds.fill()
        (selected ? paper : NSColor(white: 0.18,alpha: 1)).setStroke(); bounds.insetBy(dx: 0.5,dy: 0.5).frame()
        text(preset.name,NSRect(x: 12,y: 9,width: bounds.width-24,height: 16),size: 12,weight: .medium)
        text(preset.settings.definition.title + " / EFFECT + COLOR",NSRect(x: 12,y: 29,width: bounds.width-24,height: 14),size: 9,color: dim)
    }
}

final class PresetPanel: BlackPanel {
    let store: PresetStore
    var currentSettings: (() -> SignalSettings)?
    var recall: ((UserPreset)->Void)?
    var close: (() -> Void)?
    var selectedID: UUID?
    var lastDeletedID: UUID?
    let heading = NSTextField(labelWithString: "USER PRESETS // SAVED LOOKS")
    let help = NSTextField(labelWithString: "SELECT TO RECALL  /  EFFECT TUNING + GLOBAL COLOR")
    let message = NSTextField(labelWithString: "Name your look, then SAVE NEW.")
    let nameField = NSTextField()
    let scroll = NSScrollView()
    let list = BlackPanel()
    let closeButton = SignalButton("CLOSE ×")
    let saveButton = SignalButton("SAVE NEW")
    let updateButton = SignalButton("UPDATE")
    let renameButton = SignalButton("RENAME")
    let deleteButton = SignalButton("DELETE")
    let undoButton = SignalButton("UNDO")
    var rows: [PresetRow] = []
    init(store: PresetStore) {
        self.store = store; super.init(frame: .zero)
        heading.font = .monospacedSystemFont(ofSize: 12,weight: .bold); heading.textColor = paper
        help.font = .monospacedSystemFont(ofSize: 8,weight: .regular); help.textColor = dim
        message.font = .monospacedSystemFont(ofSize: 9,weight: .regular); message.textColor = dim; message.maximumNumberOfLines = 2
        nameField.placeholderString = "PRESET NAME"; nameField.isBordered = false; nameField.drawsBackground = true; nameField.backgroundColor = NSColor(white: 0.1,alpha: 1); nameField.textColor = paper; nameField.font = .monospacedSystemFont(ofSize: 13,weight: .regular); nameField.setAccessibilityLabel("Preset name")
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.documentView = list
        for view in [heading,help,message,nameField,scroll,closeButton,saveButton,updateButton,renameButton,deleteButton,undoButton] { addSubview(view) }
        closeButton.invoke = { [weak self] in self?.close?() }
        saveButton.invoke = { [weak self] in self?.saveNew() }
        updateButton.invoke = { [weak self] in self?.updateSelected() }
        renameButton.invoke = { [weak self] in self?.renameSelected() }
        deleteButton.invoke = { [weak self] in self?.deleteSelected() }
        undoButton.invoke = { [weak self] in self?.undoDelete() }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    func reload() {
        list.subviews.forEach { $0.removeFromSuperview() }; rows.removeAll()
        for preset in store.presets {
            let row = PresetRow(preset,selected: preset.id == selectedID)
            row.invoke = { [weak self] in
                guard let self else { return }; self.selectedID = preset.id; self.nameField.stringValue = preset.name
                self.recall?(preset); self.message.stringValue = "LOADED / " + preset.name; self.reload()
            }
            list.addSubview(row); rows.append(row)
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        heading.frame = NSRect(x: 16,y: 17,width: w-120,height: 20)
        closeButton.frame = NSRect(x: w-101,y: 12,width: 87,height: 28)
        help.frame = NSRect(x: 16,y: 44,width: w-32,height: 16)
        scroll.frame = NSRect(x: 16,y: 68,width: w-32,height: max(50,h-210))
        list.frame = NSRect(x: 0,y: 0,width: w-32,height: max(scroll.bounds.height,CGFloat(rows.count)*58))
        for (i,row) in rows.enumerated() { row.frame = NSRect(x: 0,y: CGFloat(i)*58,width: w-32,height: 52) }
        nameField.frame = NSRect(x: 16,y: h-128,width: w-32,height: 30)
        let buttons = [saveButton,updateButton,renameButton,deleteButton,undoButton]
        let bw = (w-32-32)/5
        for (i,button) in buttons.enumerated() { button.frame = NSRect(x: 16+CGFloat(i)*(bw+8),y: h-85,width: bw,height: 31) }
        message.frame = NSRect(x: 16,y: h-43,width: w-32,height: 34)
    }
    func perform(_ body: () throws -> String) {
        do { message.stringValue = try body(); message.textColor = paper; reload() }
        catch { message.stringValue = error.localizedDescription; message.textColor = NSColor(calibratedRed: 1,green: 0.55,blue: 0.55,alpha: 1) }
    }
    func saveNew() {
        guard let settings = currentSettings?() else { return }
        perform {
            let saved = try store.saveNew(name: nameField.stringValue,settings: settings)
            selectedID = saved.id; nameField.stringValue = saved.name
            return "SAVED / " + saved.name
        }
    }
    func updateSelected() {
        guard let id = selectedID, let settings = currentSettings?() else { message.stringValue = "Select a saved preset first."; return }
        perform { try store.update(id,settings: settings); return "UPDATED / SAVED EFFECT AND COLOR" }
    }
    func renameSelected() {
        guard let id = selectedID else { message.stringValue = "Select a saved preset first."; return }
        perform { try store.rename(id,to: nameField.stringValue); return "RENAMED / " + nameField.stringValue }
    }
    func deleteSelected() {
        guard let id = selectedID else { message.stringValue = "Select a saved preset first."; return }
        perform { try store.delete(id); lastDeletedID = id; selectedID = nil; nameField.stringValue = ""; return "REMOVED / UNDO RESTORES THIS PRESET" }
    }
    func undoDelete() {
        guard let id = lastDeletedID else { message.stringValue = "No preset removed in this session."; return }
        perform { try store.restore(id); selectedID = id; lastDeletedID = nil; return "PRESET RESTORED" }
    }
}
