import AppKit

@main
struct CodexQuotaWidgetMain {
    static func main() {
        if let widgetBundleURL = guardianWidgetBundleURL(from: ProcessInfo.processInfo.arguments) {
            do {
                let guardian = try CodexGuardianController(widgetBundleURL: widgetBundleURL)
                guardian.run()
                return
            } catch {
                fputs("Guardian 启动失败：\(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }

        MainActor.assumeIsolated {
            let application = NSApplication.shared
            let delegate = AppDelegate()
            application.delegate = delegate
            application.run()
        }
    }

    private static func guardianWidgetBundleURL(from arguments: [String]) -> URL? {
        guard arguments.contains("--codex-guardian") else {
            return nil
        }

        if
            let pathFlagIndex = arguments.firstIndex(of: "--widget-bundle-path"),
            arguments.indices.contains(pathFlagIndex + 1)
        {
            return URL(fileURLWithPath: arguments[pathFlagIndex + 1])
        }

        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        return bundleURL.pathExtension == "app" ? bundleURL : nil
    }
}
