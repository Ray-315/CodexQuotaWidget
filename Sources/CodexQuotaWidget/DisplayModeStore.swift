import Combine
import Foundation

@MainActor
final class DisplayModeStore: ObservableObject {
    private enum Keys {
        static let displayMode = "codex.quota.widget.displayMode"
    }

    @Published var mode: DisplayMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.displayMode)
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let rawValue = defaults.string(forKey: Keys.displayMode),
            let savedMode = DisplayMode(rawValue: rawValue)
        {
            mode = savedMode
        } else {
            mode = .menuBarOnly
        }
    }
}
