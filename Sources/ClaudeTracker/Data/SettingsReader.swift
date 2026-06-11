import Foundation

/// Reads Claude Code settings with the same cascade Claude Code uses:
/// project settings.local.json -> project settings.json -> user settings.json.
enum SettingsReader {
    static func effortLevel(projectCwd: String?) -> String? {
        stringValue(forKey: "effortLevel", projectCwd: projectCwd)
    }

    static func configuredModel(projectCwd: String?) -> String? {
        stringValue(forKey: "model", projectCwd: projectCwd)
    }

    private static func stringValue(forKey key: String, projectCwd: String?) -> String? {
        for url in cascade(projectCwd) {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = object[key] as? String
            else { continue }
            return value
        }
        return nil
    }

    private static func cascade(_ projectCwd: String?) -> [URL] {
        var urls: [URL] = []
        if let cwd = projectCwd {
            let base = URL(fileURLWithPath: cwd).appendingPathComponent(".claude", isDirectory: true)
            urls.append(base.appendingPathComponent("settings.local.json"))
            urls.append(base.appendingPathComponent("settings.json"))
        }
        urls.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"))
        return urls
    }
}
