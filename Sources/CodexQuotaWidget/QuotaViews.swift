import AppKit
import SwiftUI

struct QuotaDashboardView: View {
    @ObservedObject var quotaStore: QuotaStore
    @ObservedObject var modeStore: DisplayModeStore
    @ObservedObject var bindingManager: CodexBindingManager
    let actions: AppActions

    var body: some View {
        VStack(spacing: 10) {
            ForEach(quotaStore.compactRows, id: \.label) { row in
                CompactQuotaRowView(row: row)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 236)
        .background {
            GlassBackgroundView()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            Button("菜单栏") {
                modeStore.mode = .menuBarOnly
            }
            Button("悬浮窗") {
                modeStore.mode = .floatingOnly
            }
            Button("同时显示") {
                modeStore.mode = .both
            }
            Divider()
            Text(quotaStore.statusMenuText)
            Divider()
            Button("重新登录 ChatGPT", action: actions.onLogin)
            Button("退出云端登录", action: actions.onLogout)
                .disabled(!quotaStore.canLogoutCloudSession)
            Button("立即刷新", action: actions.onRefresh)
                .disabled(quotaStore.isLoading)
            Toggle("绑定 Codex 启动退出", isOn: Binding(
                get: { bindingManager.isEnabled },
                set: { _ in actions.onToggleCodexBinding() }
            ))
            Divider()
            Button("退出软件", action: actions.onQuit)
        }
    }
}

private struct CompactQuotaRowView: View {
    let row: CompactQuotaRow

    var body: some View {
        HStack(spacing: 10) {
            Text(row.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 22, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.14))
                        .frame(height: 5)

                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.92))
                        .frame(width: geometry.size.width * max(0, min(row.progress, 1)), height: 5)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            Text(row.remainingText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
