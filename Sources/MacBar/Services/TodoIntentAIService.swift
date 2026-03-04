import CryptoKit
import Foundation
import MLXLLM
import MLXLMCommon

enum TodoAIModelSource: String, Codable, CaseIterable, Hashable {
    case embedded = "embedded"
    case huggingFace = "huggingface"
    case localPath = "local_path"
    case directURL = "direct_url"
}

struct TodoAIModelConfig: Codable, Hashable {
    static let defaultModelReference = "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    static let embeddedModelDirectoryName = "Qwen3.5-0.8B-MLX-4bit"

    var source: TodoAIModelSource
    var reference: String

    init(
        source: TodoAIModelSource = .embedded,
        reference: String = TodoAIModelConfig.defaultModelReference
    ) {
        self.source = source
        self.reference = reference
    }

    var normalizedReference: String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultModelReference : trimmed
    }
}

struct TodoAIMessage: Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct TodoAIDraft: Hashable {
    let title: String
    let notes: String?
    let priority: TodoPriority?
    let dueDate: Date?
    let reminderDate: Date?
}

struct TodoAIIntentResult: Hashable {
    enum Intent: Hashable {
        case addTodo
        case clarify
        case chat
        case unknown(String)
    }

    let intent: Intent
    let assistantReply: String
    let draft: TodoAIDraft?
}

@MainActor
protocol TodoIntentAIService {
    func interpret(
        userInput: String,
        conversation: [TodoAIMessage],
        localeIdentifier: String,
        timeZone: TimeZone,
        modelConfig: TodoAIModelConfig
    ) async throws -> TodoAIIntentResult
}

enum TodoAIServiceError: LocalizedError {
    case runtimeUnavailable(String)
    case executionFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message):
            return message
        case let .executionFailed(message):
            return message
        case let .invalidResponse(message):
            return message
        }
    }
}

@MainActor
final class LocalMLXTodoIntentService: TodoIntentAIService {
    private let runtime = LocalMLXRuntime()

    private struct ModelResponse: Decodable {
        let intent: String
        let assistantReply: String
        let todo: TodoPayload?

        enum CodingKeys: String, CodingKey {
            case intent
            case assistantReply = "assistant_reply"
            case todo
        }
    }

    private struct TodoPayload: Decodable {
        let title: String?
        let notes: String?
        let priority: String?
        let dueAt: String?
        let remindAt: String?

        enum CodingKeys: String, CodingKey {
            case title
            case notes
            case priority
            case dueAt = "due_at"
            case remindAt = "remind_at"
        }
    }

    func interpret(
        userInput: String,
        conversation: [TodoAIMessage],
        localeIdentifier: String,
        timeZone: TimeZone,
        modelConfig: TodoAIModelConfig
    ) async throws -> TodoAIIntentResult {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw TodoAIServiceError.invalidResponse("请输入待办内容。")
        }

        let prompt = Self.buildPrompt(
            userInput: trimmedInput,
            conversation: Array(conversation.suffix(8)),
            localeIdentifier: localeIdentifier,
            timeZone: timeZone,
            now: Date()
        )

        let rawOutput = try await runtime.generate(
            prompt: prompt,
            modelConfig: modelConfig,
            maxTokens: 320
        )
        let decoded = try decodeModelResponse(from: rawOutput)

        let draft = makeDraft(from: decoded.todo)
        let intent = mapIntent(decoded.intent)
        let reply = decoded.assistantReply.trimmingCharacters(in: .whitespacesAndNewlines)

        return TodoAIIntentResult(
            intent: intent,
            assistantReply: reply.isEmpty ? "我已读取你的输入，请继续补充细节。" : reply,
            draft: draft
        )
    }

    private func decodeModelResponse(from rawOutput: String) throws -> ModelResponse {
        let normalized = extractJSONObjectString(from: rawOutput)
        guard let data = normalized.data(using: .utf8) else {
            throw TodoAIServiceError.invalidResponse("本地 AI 返回了无效文本。")
        }

        do {
            var response = try JSONDecoder().decode(ModelResponse.self, from: data)
            response = normalizeModelResponse(response)
            return response
        } catch {
            throw TodoAIServiceError.invalidResponse("本地 AI 返回了无法解析的数据：\(normalized)")
        }
    }

    private func normalizeModelResponse(_ response: ModelResponse) -> ModelResponse {
        let normalizedIntent: String
        switch response.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "add_todo":
            normalizedIntent = "add_todo"
        case "clarify":
            normalizedIntent = "clarify"
        case "chat":
            normalizedIntent = "chat"
        default:
            normalizedIntent = "chat"
        }

        let normalizedReply = response.assistantReply
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = normalizedReply.isEmpty ? "我已收到你的输入。" : normalizedReply

        let todo: TodoPayload?
        if let responseTodo = response.todo {
            let title = normalizedText(responseTodo.title)
            let notes = normalizedText(responseTodo.notes)
            let priority = normalizedPriority(responseTodo.priority)
            let dueAt = normalizedText(responseTodo.dueAt)
            let remindAt = normalizedText(responseTodo.remindAt)
            todo = TodoPayload(
                title: title,
                notes: notes,
                priority: priority,
                dueAt: dueAt,
                remindAt: remindAt
            )
        } else {
            todo = nil
        }

        if normalizedIntent == "add_todo", (todo?.title ?? "").isEmpty {
            return ModelResponse(
                intent: "clarify",
                assistantReply: reply,
                todo: todo
            )
        }

        return ModelResponse(
            intent: normalizedIntent,
            assistantReply: reply,
            todo: todo
        )
    }

    private func extractJSONObjectString(from rawOutput: String) -> String {
        var text = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start ... end])
        }

        return text
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedPriority(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "medium", "low":
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return nil
        }
    }

    private func mapIntent(_ rawIntent: String) -> TodoAIIntentResult.Intent {
        switch rawIntent.lowercased() {
        case "add_todo":
            return .addTodo
        case "clarify":
            return .clarify
        case "chat":
            return .chat
        default:
            return .unknown(rawIntent)
        }
    }

    private func makeDraft(from todo: TodoPayload?) -> TodoAIDraft? {
        guard let todo else {
            return nil
        }

        let title = todo.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return nil
        }

        let notes = todo.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = parsePriority(todo.priority)
        let dueDate = parseISODate(todo.dueAt)
        let reminderDate = parseISODate(todo.remindAt)

        let normalizedReminderDate: Date?
        if let dueDate, let reminderDate, reminderDate > dueDate {
            normalizedReminderDate = dueDate
        } else {
            normalizedReminderDate = reminderDate
        }

        return TodoAIDraft(
            title: title,
            notes: notes?.isEmpty == true ? nil : notes,
            priority: priority,
            dueDate: dueDate,
            reminderDate: normalizedReminderDate
        )
    }

    private func parsePriority(_ rawPriority: String?) -> TodoPriority? {
        guard let rawPriority else {
            return nil
        }

        switch rawPriority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            return .high
        case "medium":
            return .medium
        case "low":
            return .low
        default:
            return nil
        }
    }

    private func parseISODate(_ rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let date = makeFractionalInternetDateFormatter().date(from: trimmed) {
            return date
        }

        if let date = makeInternetDateFormatter().date(from: trimmed) {
            return date
        }

        return nil
    }

    private func makeInternetDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func makeFractionalInternetDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func buildPrompt(
        userInput: String,
        conversation: [TodoAIMessage],
        localeIdentifier: String,
        timeZone: TimeZone,
        now: Date
    ) -> String {
        let history = conversation
            .compactMap { message -> TodoAIMessage? in
                let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return TodoAIMessage(role: message.role, content: trimmed)
            }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let historyJSON: String
        if let data = try? encoder.encode(history),
           let text = String(data: data, encoding: .utf8)
        {
            historyJSON = text
        } else {
            historyJSON = "[]"
        }

        let nowFormatter = ISO8601DateFormatter()
        nowFormatter.formatOptions = [.withInternetDateTime]
        nowFormatter.timeZone = timeZone
        let nowISO = nowFormatter.string(from: now)

        return """
        You are a local todo assistant running on a Mac.
        You MUST help parse user intent for todos and optionally chat briefly.

        Current local time: \(nowISO)
        Current timezone: \(timeZone.identifier)
        Current locale: \(localeIdentifier)

        Conversation history (JSON):
        \(historyJSON)

        User message:
        \(userInput)

        Return ONLY one JSON object (no markdown, no explanations) with this schema:
        {
          "intent": "add_todo" | "clarify" | "chat",
          "assistant_reply": "short reply in user's language",
          "todo": {
            "title": "string or null",
            "notes": "string or null",
            "priority": "high" | "medium" | "low" | null,
            "due_at": "ISO8601 datetime with timezone or null",
            "remind_at": "ISO8601 datetime with timezone or null"
          }
        }

        Rules:
        1) If user gives enough info to create/update a todo item, use "add_todo" and fill todo fields.
        2) Convert relative times (tomorrow morning, next Friday, etc.) to absolute ISO8601 using the current time/timezone above.
        3) If info is incomplete for creation, use "clarify" and ask ONE short follow-up question.
        4) For pure conversation, use "chat"; todo fields can be null.
        5) Keep reply concise and practical.
        6) If both due_at and remind_at exist, remind_at must be <= due_at.
        """
    }
}

private actor LocalMLXRuntime {
    private enum ArchiveKind {
        case zip
        case tar
        case tarGz
    }

    private enum ResolvedModel {
        case huggingFaceID(String)
        case localDirectory(URL)

        var cacheKey: String {
            switch self {
            case let .huggingFaceID(id):
                return "hf:\(id)"
            case let .localDirectory(url):
                return "local:\(url.path)"
            }
        }

        var modelConfiguration: ModelConfiguration {
            switch self {
            case let .huggingFaceID(id):
                return ModelConfiguration(id: id)
            case let .localDirectory(url):
                return ModelConfiguration(directory: url)
            }
        }
    }

    private let fileManager = FileManager.default
    private let modelCacheRoot: URL
    private var loadedModelKey: String?
    private var loadedModelContainer: ModelContainer?

    init() {
        modelCacheRoot = fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".macbar/mlx_models", isDirectory: true)
    }

    func generate(
        prompt: String,
        modelConfig: TodoAIModelConfig,
        maxTokens: Int
    ) async throws -> String {
        let resolvedModel = try await resolveModelReference(modelConfig)
        let container = try await loadContainer(for: resolvedModel)

        let boundedMaxTokens = max(64, min(maxTokens, 768))
        let parameters = GenerateParameters(
            maxTokens: boundedMaxTokens,
            temperature: 0.2,
            topP: 0.95
        )

        let input = try await container.prepare(input: UserInput(prompt: prompt))
        let stream = try await container.generate(input: input, parameters: parameters)

        var output = ""
        for await generation in stream {
            if case let .chunk(chunk) = generation {
                output += chunk
            }
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TodoAIServiceError.invalidResponse("本地 AI 没有返回结果。")
        }

        return trimmed
    }

    private func loadContainer(for resolvedModel: ResolvedModel) async throws -> ModelContainer {
        let key = resolvedModel.cacheKey
        if loadedModelKey == key, let loadedModelContainer {
            return loadedModelContainer
        }

        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: resolvedModel.modelConfiguration
            )
            loadedModelKey = key
            loadedModelContainer = container
            return container
        } catch {
            throw TodoAIServiceError.runtimeUnavailable("本地 AI 模型加载失败：\(error.localizedDescription)")
        }
    }

    private func resolveModelReference(_ modelConfig: TodoAIModelConfig) async throws -> ResolvedModel {
        let reference = modelConfig.normalizedReference

        switch modelConfig.source {
        case .embedded:
            guard let embeddedDirectory = embeddedModelDirectoryURL() else {
                throw TodoAIServiceError.runtimeUnavailable(
                    "内置 AI 模型缺失：请确认应用包内包含 EmbeddedModels/\(TodoAIModelConfig.embeddedModelDirectoryName) 目录。"
                )
            }
            return .localDirectory(embeddedDirectory)
        case .huggingFace:
            if shouldPreferEmbeddedModel(for: reference),
               let embeddedDirectory = embeddedModelDirectoryURL()
            {
                return .localDirectory(embeddedDirectory)
            }
            return .huggingFaceID(extractHuggingFaceRepoID(from: reference))
        case .localPath:
            let expanded = NSString(string: reference).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            else {
                throw TodoAIServiceError.runtimeUnavailable("本地模型目录不存在：\(url.path)")
            }
            return .localDirectory(url)
        case .directURL:
            guard let url = URL(string: reference),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                throw TodoAIServiceError.runtimeUnavailable("模型下载地址无效：\(reference)")
            }

            if isHuggingFaceURL(url) {
                return .huggingFaceID(extractHuggingFaceRepoID(from: reference))
            }

            let directory = try await ensureArchiveExtracted(at: url)
            return .localDirectory(directory)
        }
    }

    private func shouldPreferEmbeddedModel(for reference: String) -> Bool {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == TodoAIModelConfig.defaultModelReference
            || normalized == TodoAIModelConfig.embeddedModelDirectoryName
    }

    private func embeddedModelDirectoryURL() -> URL? {
        guard let resourceRoot = Bundle.module.resourceURL else {
            return nil
        }

        let embeddedModelDirectory = resourceRoot
            .appendingPathComponent("EmbeddedModels", isDirectory: true)
            .appendingPathComponent(TodoAIModelConfig.embeddedModelDirectoryName, isDirectory: true)
            .standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: embeddedModelDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        guard isModelDirectory(embeddedModelDirectory) else {
            return nil
        }

        return embeddedModelDirectory
    }

    private func ensureArchiveExtracted(at remoteURL: URL) async throws -> URL {
        guard let kind = archiveKind(for: remoteURL) else {
            throw TodoAIServiceError.runtimeUnavailable(
                "direct_url 仅支持 .zip / .tar / .tar.gz / .tgz 压缩包。"
            )
        }

        let slug = sha256Hex(remoteURL.absoluteString).prefix(16)
        let baseDirectory = modelCacheRoot.appendingPathComponent(String(slug), isDirectory: true)
        let extractionDirectory = baseDirectory.appendingPathComponent("model", isDirectory: true)
        let resolvedPathFile = baseDirectory.appendingPathComponent(".resolved-model-path")

        if let cached = try? String(contentsOf: resolvedPathFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty
        {
            let cachedURL = URL(fileURLWithPath: cached).standardizedFileURL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: cachedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return cachedURL
            }
        }

        if fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.removeItem(at: baseDirectory)
        }

        do {
            try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        } catch {
            throw TodoAIServiceError.runtimeUnavailable("无法创建模型缓存目录：\(baseDirectory.path)")
        }

        let fileExtension = archiveFileExtension(for: remoteURL)
        let archiveURL = baseDirectory.appendingPathComponent("archive\(fileExtension)")

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode)
            {
                throw TodoAIServiceError.executionFailed(
                    "模型下载失败：HTTP \(httpResponse.statusCode)"
                )
            }

            if fileManager.fileExists(atPath: archiveURL.path) {
                try? fileManager.removeItem(at: archiveURL)
            }
            try fileManager.moveItem(at: tempURL, to: archiveURL)
        } catch let error as TodoAIServiceError {
            throw error
        } catch {
            throw TodoAIServiceError.executionFailed("模型下载失败：\(error.localizedDescription)")
        }

        do {
            try validateArchiveEntries(at: archiveURL, kind: kind)
            try extractArchive(at: archiveURL, to: extractionDirectory, kind: kind)
            let modelDirectory = try locateModelDirectory(in: extractionDirectory)
            try modelDirectory.path.write(toFile: resolvedPathFile.path, atomically: true, encoding: .utf8)
            return modelDirectory
        } catch let error as TodoAIServiceError {
            throw error
        } catch {
            throw TodoAIServiceError.executionFailed("模型解压失败：\(error.localizedDescription)")
        }
    }

    private func locateModelDirectory(in extractionDirectory: URL) throws -> URL {
        if isModelDirectory(extractionDirectory) {
            return extractionDirectory
        }

        let topLevelItems = (try? fileManager.contentsOfDirectory(
            at: extractionDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let topLevelDirectories = topLevelItems.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        if topLevelDirectories.count == 1, isModelDirectory(topLevelDirectories[0]) {
            return topLevelDirectories[0]
        }

        if let enumerator = fileManager.enumerator(
            at: extractionDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator where url.lastPathComponent == "config.json" {
                let candidate = url.deletingLastPathComponent()
                if isModelDirectory(candidate) {
                    return candidate
                }
            }
        }

        throw TodoAIServiceError.runtimeUnavailable(
            "解压后的模型目录无效：未找到 config.json。"
        )
    }

    private func isModelDirectory(_ directory: URL) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent("config.json").path)
    }

    private func validateArchiveEntries(at archiveURL: URL, kind: ArchiveKind) throws {
        let output: String
        switch kind {
        case .zip:
            output = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-Z1", archiveURL.path]
            )
        case .tar:
            output = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-tf", archiveURL.path]
            )
        case .tarGz:
            output = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-tzf", archiveURL.path]
            )
        }

        let entries = output.split(separator: "\n").map(String.init)
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
            if normalized.hasPrefix("/") {
                throw TodoAIServiceError.runtimeUnavailable("压缩包包含非法绝对路径：\(trimmed)")
            }

            if normalized.split(separator: "/").contains("..") {
                throw TodoAIServiceError.runtimeUnavailable("压缩包包含非法路径跳转：\(trimmed)")
            }
        }
    }

    private func extractArchive(at archiveURL: URL, to extractionDirectory: URL, kind: ArchiveKind) throws {
        switch kind {
        case .zip:
            _ = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-oq", archiveURL.path, "-d", extractionDirectory.path]
            )
        case .tar:
            _ = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xf", archiveURL.path, "-C", extractionDirectory.path]
            )
        case .tarGz:
            _ = try runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xzf", archiveURL.path, "-C", extractionDirectory.path]
            )
        }
    }

    @discardableResult
    private func runCommand(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TodoAIServiceError.runtimeUnavailable(
                "无法执行系统命令：\(executableURL.lastPathComponent)"
            )
        }

        process.waitUntilExit()

        let stdoutText = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderrText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty
                ? "\(executableURL.lastPathComponent) 退出码 \(process.terminationStatus)"
                : detail
            throw TodoAIServiceError.executionFailed(message)
        }

        return stdoutText
    }

    private func archiveKind(for remoteURL: URL) -> ArchiveKind? {
        let lowercasedPath = remoteURL.path.lowercased()
        if lowercasedPath.hasSuffix(".tar.gz") || lowercasedPath.hasSuffix(".tgz") {
            return .tarGz
        }
        if lowercasedPath.hasSuffix(".tar") {
            return .tar
        }
        if lowercasedPath.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }

    private func archiveFileExtension(for remoteURL: URL) -> String {
        let lowercasedPath = remoteURL.path.lowercased()
        if lowercasedPath.hasSuffix(".tar.gz") {
            return ".tar.gz"
        }
        if lowercasedPath.hasSuffix(".tgz") {
            return ".tgz"
        }
        if lowercasedPath.hasSuffix(".tar") {
            return ".tar"
        }
        if lowercasedPath.hasSuffix(".zip") {
            return ".zip"
        }
        return ".archive"
    }

    private func extractHuggingFaceRepoID(from reference: String) -> String {
        var trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmed.isEmpty else {
            return TodoAIModelConfig.defaultModelReference
        }

        if let url = URL(string: trimmed), isHuggingFaceURL(url) {
            var components = url.pathComponents
                .filter { $0 != "/" && !$0.isEmpty }

            if components.first?.lowercased() == "models" {
                components.removeFirst()
            }

            if components.count >= 2 {
                return "\(components[0])/\(components[1])"
            }

            if let first = components.first {
                return first
            }

            return TodoAIModelConfig.defaultModelReference
        }

        return trimmed
    }

    private func isHuggingFaceURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host.contains("huggingface.co")
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
