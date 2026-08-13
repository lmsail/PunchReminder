import Foundation

enum Persistence {
    static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PunchReminder", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("state.json")
    }

    static func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else {
            return PersistedState(
                rules: PunchRule.makeDefaultRules(),
                soundEnabled: true,
                overrides: [],
                history: [],
                dayRuntime: nil
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let state = try? decoder.decode(PersistedState.self, from: data) {
            return state
        }
        return PersistedState(
            rules: PunchRule.makeDefaultRules(),
            soundEnabled: true,
            overrides: [],
            history: [],
            dayRuntime: nil
        )
    }

    static func save(_ state: PersistedState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
