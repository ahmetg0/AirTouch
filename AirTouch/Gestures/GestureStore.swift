import Foundation

// MARK: - Gesture Store

@Observable
final class GestureStore: @unchecked Sendable {
    private(set) var templates: [GestureTemplate] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let airTouchDir = appSupport.appendingPathComponent("AirTouch", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: airTouchDir, withIntermediateDirectories: true)

        fileURL = airTouchDir.appendingPathComponent("gestures.json")
        loadFromDisk()
    }

    // MARK: - CRUD

    func add(_ template: GestureTemplate) {
        templates.append(template)
        saveToDisk()
    }

    func update(_ template: GestureTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        saveToDisk()
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        saveToDisk()
    }

    func template(byID id: UUID) -> GestureTemplate? {
        templates.first { $0.id == id }
    }

    func enabledTemplates() -> [GestureTemplate] {
        templates.filter(\.isEnabled)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            templates = try JSONDecoder().decode([GestureTemplate].self, from: data)
        } catch {
            // Corrupted file — start fresh
            templates = []
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(templates)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Save failed — log but don't crash
        }
    }
}
