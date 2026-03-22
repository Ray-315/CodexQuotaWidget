import Foundation

struct AppActions {
    let onLogin: () -> Void
    let onLogout: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void
}
