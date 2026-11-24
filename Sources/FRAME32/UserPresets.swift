import Foundation

struct UserPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var updatedAt = Date()
    var deletedAt: Date?
    var settings: SignalSettings

    /// Recall the saved look without erasing unsaved tunings for unrelated effects.
    func applying(to current: SignalSettings) -> SignalSettings {
        var result = settings.normalized()
        let selected = result.current
        result.perEffect = current.perEffect
        result.perEffect[result.activeEffect.rawValue] = selected
        return result.normalized()
    }
}
struct PresetDocument: Codable { var schemaVersion = 1; var presets: [UserPreset] = [] }
final class PresetStore {
    let url: URL
    private var records: [UserPreset] = []
    private(set) var canSave = true
    var presets: [UserPreset] { records.filter { $0.deletedAt == nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("FRAME32/presets.json")
    }
    func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard envelope?["schemaVersion"] as? Int == 1 else { throw PresetError.invalidFile }
            let document = try JSONDecoder().decode(PresetDocument.self,from: data)
            guard Set(document.presets.map(\.id)).count == document.presets.count else { throw PresetError.invalidFile }
            var names = Set<String>()
            for record in document.presets where record.deletedAt == nil {
                let name = try validName(record.name)
                guard names.insert(fold(name)).inserted else { throw PresetError.invalidFile }
            }
            records = document.presets
        } catch { canSave = false; throw error }
    }
    func validName(_ name: String) throws -> String {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty, clean.count <= 64, !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw PresetError.name }
        return clean
    }
    private func fold(_ name: String) -> String { name.folding(options: [.caseInsensitive,.diacriticInsensitive],locale: Locale(identifier: "en_US_POSIX")) }
    private func uniqueName(_ name: String, excluding: UUID? = nil) throws -> String {
        let clean = try validName(name)
        guard !records.contains(where: { $0.deletedAt == nil && $0.id != excluding && fold($0.name) == fold(clean) }) else { throw PresetError.duplicate }
        return clean
    }
    private func snapshot(_ settings: SignalSettings) -> SignalSettings {
        var result = settings.normalized()
        result.perEffect = [result.activeEffect.rawValue: result.current]
        return result
    }
    private func commit(_ candidate: [UserPreset]) throws {
        guard canSave else { throw PresetError.invalidFile }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(PresetDocument(presets: candidate)).write(to: url,options: .atomic)
        records = candidate // Publish only after a successful atomic write.
    }
    @discardableResult func saveNew(name: String, settings: SignalSettings) throws -> UserPreset {
        let name = try uniqueName(name)
        let record = UserPreset(name: name,settings: snapshot(settings))
        try commit(records + [record]); return record
    }
    func update(_ id: UUID,settings: SignalSettings) throws {
        guard let i = records.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw PresetError.missing }
        var next = records; next[i].settings = snapshot(settings); next[i].updatedAt = Date(); try commit(next)
    }
    func rename(_ id: UUID,to name: String) throws {
        let name = try uniqueName(name,excluding: id)
        guard let i = records.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw PresetError.missing }
        var next = records; next[i].name = name; next[i].updatedAt = Date(); try commit(next)
    }
    func delete(_ id: UUID) throws {
        guard let i = records.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw PresetError.missing }
        var next = records; next[i].deletedAt = Date(); try commit(next)
    }
    func restore(_ id: UUID) throws {
        guard let i = records.firstIndex(where: { $0.id == id && $0.deletedAt != nil }) else { throw PresetError.missing }
        _ = try uniqueName(records[i].name)
        var next = records; next[i].deletedAt = nil; try commit(next)
    }
    enum PresetError: LocalizedError {
        case name, duplicate, missing, invalidFile
        var errorDescription: String? {
            switch self {
            case .name: return "Use a preset name from 1 to 64 characters"
            case .duplicate: return "A preset with that name already exists"
            case .missing: return "Select a saved preset first"
            case .invalidFile: return "Preset file is incompatible or damaged; existing file preserved"
            }
        }
    }
}
