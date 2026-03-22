import AppKit
import Foundation

enum CodexBindingConstants {
    static let serviceLabel = "local.codex.quota.widget.guardian"
    static let codexBundleIdentifier = "com.openai.codex"
}

@MainActor
final class CodexBindingManager: ObservableObject {
    @Published private(set) var isEnabled = false

    private let fileManager: FileManager
    private let commandRunner: CommandRunner
    private let launchAgentURL: URL

    init(
        fileManager: FileManager = .default,
        commandRunner: CommandRunner = CommandRunner()
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.launchAgentURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(CodexBindingConstants.serviceLabel).plist")
        refreshState()
    }

    func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }

    func refreshState() {
        isEnabled = fileManager.fileExists(atPath: launchAgentURL.path)
    }

    func enable() throws {
        let launchAgentsDirectory = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let appBundleURL = try currentAppBundleURL()
        let executableURL = try currentExecutableURL()
        let plist = try makeLaunchAgentPlist(
            executableURL: executableURL,
            widgetBundleURL: appBundleURL
        )
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: launchAgentURL, options: .atomic)

        try? bootOut()
        try commandRunner.run("/bin/launchctl", arguments: [
            "bootstrap",
            launchDomain,
            launchAgentURL.path
        ])

        isEnabled = true
    }

    func disable() throws {
        try? bootOut()

        if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }

        isEnabled = false
    }

    private var launchDomain: String {
        "gui/\(getuid())"
    }

    private func bootOut() throws {
        try commandRunner.run("/bin/launchctl", arguments: [
            "bootout",
            "\(launchDomain)/\(CodexBindingConstants.serviceLabel)"
        ])
    }

    private func currentAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app" else {
            throw CodexBindingError.mustRunFromAppBundle
        }

        return bundleURL
    }

    private func currentExecutableURL() throws -> URL {
        guard let executableURL = Bundle.main.executableURL?.standardizedFileURL else {
            throw CodexBindingError.missingExecutablePath
        }

        return executableURL
    }

    private func makeLaunchAgentPlist(executableURL: URL, widgetBundleURL: URL) throws -> [String: Any] {
        [
            "Label": CodexBindingConstants.serviceLabel,
            "RunAtLoad": true,
            "KeepAlive": true,
            "LimitLoadToSessionType": ["Aqua"],
            "ProgramArguments": [
                executableURL.path,
                "--codex-guardian",
                "--widget-bundle-path",
                widgetBundleURL.path
            ]
        ]
    }
}

enum CodexBindingError: LocalizedError {
    case mustRunFromAppBundle
    case missingExecutablePath
    case invalidWidgetBundlePath
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .mustRunFromAppBundle:
            return "只有从 .app 启动时才能启用 Codex 绑定。"
        case .missingExecutablePath:
            return "无法定位当前应用的可执行文件路径。"
        case .invalidWidgetBundlePath:
            return "找不到可用的小组件应用路径。"
        case .commandFailed(let message):
            return message
        }
    }
}

final class CodexGuardianController {
    private let workspace: NSWorkspace
    private let processInspector: ProcessInspector
    private let widgetBundleURL: URL
    private let widgetExecutablePath: String
    private let guardianPID: Int32

    private var codexRunning = false
    private var suppressLaunchUntilNextCodexLaunch = false
    private var observers: [NSObjectProtocol] = []

    init(
        widgetBundleURL: URL,
        workspace: NSWorkspace = .shared,
        processInspector: ProcessInspector = ProcessInspector()
    ) throws {
        let standardizedBundleURL = widgetBundleURL.standardizedFileURL
        guard standardizedBundleURL.pathExtension == "app" else {
            throw CodexBindingError.invalidWidgetBundlePath
        }

        let executableURL = standardizedBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("CodexQuotaWidget")

        self.widgetBundleURL = standardizedBundleURL
        self.widgetExecutablePath = executableURL.path
        self.workspace = workspace
        self.processInspector = processInspector
        self.guardianPID = getpid()
    }

    func run() {
        codexRunning = isCodexRunning()
        installObservers()

        if codexRunning {
            launchWidgetIfNeeded()
        }

        RunLoop.main.run()
    }

    private func installObservers() {
        let notificationCenter = workspace.notificationCenter

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationLaunched(notification)
        })

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleApplicationTerminated(notification)
        })
    }

    private func handleApplicationLaunched(_ notification: Notification) {
        guard let application = application(from: notification) else {
            return
        }

        if application.bundleIdentifier == CodexBindingConstants.codexBundleIdentifier {
            codexRunning = true
            suppressLaunchUntilNextCodexLaunch = false
            launchWidgetIfNeeded()
        }
    }

    private func handleApplicationTerminated(_ notification: Notification) {
        guard let application = application(from: notification) else {
            return
        }

        if application.bundleIdentifier == CodexBindingConstants.codexBundleIdentifier {
            codexRunning = false
            terminateWidgetForCodexShutdown()
            return
        }

        if application.bundleIdentifier == Bundle.main.bundleIdentifier, application.processIdentifier != guardianPID, codexRunning {
            suppressLaunchUntilNextCodexLaunch = true
        }
    }

    private func application(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func isCodexRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: CodexBindingConstants.codexBundleIdentifier).isEmpty
    }

    private func launchWidgetIfNeeded() {
        guard codexRunning, suppressLaunchUntilNextCodexLaunch == false else {
            return
        }

        guard processInspector.isWidgetUIRunning(
            executablePath: widgetExecutablePath,
            guardianPID: guardianPID
        ) == false else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        workspace.openApplication(at: widgetBundleURL, configuration: configuration) { _, _ in }
    }

    private func terminateWidgetForCodexShutdown() {
        let widgetPIDs = processInspector.widgetUIPIDs(
            executablePath: widgetExecutablePath,
            guardianPID: guardianPID
        )

        for pid in widgetPIDs {
            try? processInspector.terminate(pid: pid)
        }
    }
}

struct ProcessInspector {
    private let commandRunner: CommandRunner

    init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func isWidgetUIRunning(executablePath: String, guardianPID: Int32) -> Bool {
        widgetUIPIDs(executablePath: executablePath, guardianPID: guardianPID).isEmpty == false
    }

    func widgetUIPIDs(executablePath: String, guardianPID: Int32) -> [Int32] {
        let entries = (try? processEntries()) ?? []
        return entries.compactMap { entry in
            guard
                entry.pid != guardianPID,
                entry.command.contains(executablePath),
                entry.command.contains("--codex-guardian") == false
            else {
                return nil
            }

            return entry.pid
        }
    }

    func terminate(pid: Int32) throws {
        try commandRunner.run("/bin/kill", arguments: ["\(pid)"])
    }

    private func processEntries() throws -> [ProcessEntry] {
        let output = try commandRunner.run("/bin/ps", arguments: ["-ax", "-o", "pid=,command="])

        return output
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else {
                    return nil
                }

                let pieces = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard pieces.count == 2, let pid = Int32(pieces[0]) else {
                    return nil
                }

                return ProcessEntry(pid: pid, command: String(pieces[1]))
            }
    }
}

private struct ProcessEntry {
    let pid: Int32
    let command: String
}

struct CommandRunner {
    @discardableResult
    func run(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw CodexBindingError.commandFailed(error.isEmpty ? "命令执行失败：\(launchPath)" : error)
        }

        return output
    }
}
