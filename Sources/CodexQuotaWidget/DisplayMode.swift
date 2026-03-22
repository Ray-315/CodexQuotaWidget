import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case menuBarOnly
    case floatingOnly
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBarOnly:
            return "菜单栏"
        case .floatingOnly:
            return "悬浮窗"
        case .both:
            return "同时显示"
        }
    }
}
