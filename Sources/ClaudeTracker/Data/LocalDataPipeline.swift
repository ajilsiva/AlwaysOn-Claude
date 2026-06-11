import Foundation

/// Builds a SessionSnapshot from local Claude Code data. Shared by the
/// RefreshCoordinator and the `--dump` CLI mode so both exercise the same
/// code path. Call from one serial queue (owns a ProjectTimeAggregator).
final class LocalDataPipeline {
    let indexer: TranscriptIndexer
    private let aggregator = ProjectTimeAggregator()

    init(indexer: TranscriptIndexer = TranscriptIndexer()) {
        self.indexer = indexer
    }

    func buildSessionSnapshot() -> SessionSnapshot {
        var snapshot = SessionSnapshot()
        guard let active = indexer.findActiveSession() else { return snapshot }

        snapshot.sessionFileURL = active.url
        snapshot.lastActivity = active.mtime

        let usage = TranscriptParser.lastAssistantUsage(in: active.url)
        let meta = TranscriptParser.sessionMeta(in: active.url)
        snapshot.modelId = usage?.model
        snapshot.contextTokens = usage?.contextTokens
        snapshot.projectPath = meta.cwd

        let configuredModel = SettingsReader.configuredModel(projectCwd: meta.cwd)
        snapshot.contextLimit = TranscriptParser.contextLimit(
            modelId: usage?.model, configuredModel: configuredModel)
        snapshot.effortLevel = SettingsReader.effortLevel(projectCwd: meta.cwd)
        snapshot.projectActiveSeconds = aggregator.activeSeconds(forProjectDir: active.projectDir)

        return snapshot
    }

    func claudeCodeVersion() -> String? {
        guard let active = indexer.findActiveSession() else { return nil }
        return TranscriptParser.sessionMeta(in: active.url).version
    }
}
