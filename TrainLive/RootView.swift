import SwiftUI

// 한 앱 안에 번역기와 kemometro 를 같이 둔다. 둘 다 띄워 둔 채로 보이는 쪽만 바꿔서
// 전환해도 입력 중이던 글·스크롤·열차 목록이 그대로 남는다. 설정은 앱마다 따로다.

enum AppKind: String {
    case translator, metro

    var title: String { self == .translator ? "번역기" : "kemometro" }
    var symbol: String { self == .translator ? "character.bubble.fill" : "tram.fill" }
}

@MainActor
final class AppSwitch: ObservableObject {
    static let shared = AppSwitch()
    /// 켤 때는 늘 번역기가 먼저 나온다
    @Published var current: AppKind = .translator

    func go(_ kind: AppKind) {
        guard kind != current else { return }
        Haptics.selection()
        current = kind
    }

    func toggle() { go(current == .translator ? .metro : .translator) }
}

struct RootView: View {
    @ObservedObject private var sw = AppSwitch.shared

    var body: some View {
        ZStack {
            MainView()
                .opacity(sw.current == .metro ? 1 : 0)
                .allowsHitTesting(sw.current == .metro)
                .accessibilityHidden(sw.current != .metro)
            TranslatorView()
                .opacity(sw.current == .translator ? 1 : 0)
                .allowsHitTesting(sw.current == .translator)
                .accessibilityHidden(sw.current != .translator)
        }
        .animation(.easeInOut(duration: 0.22), value: sw.current)
    }
}

/// 오른쪽 위 앱 전환 버튼. 누르면 다른 앱으로, 길게 누르면 목록.
struct AppSwitcherButton: View {
    @ObservedObject private var sw = AppSwitch.shared

    private var other: AppKind { sw.current == .translator ? .metro : .translator }

    var body: some View {
        Menu {
            ForEach([AppKind.translator, .metro], id: \.self) { kind in
                Button { sw.go(kind) } label: {
                    if kind == sw.current { Label(kind.title, systemImage: "checkmark") }
                    else { Label(kind.title, systemImage: kind.symbol) }
                }
            }
        } label: {
            Image(systemName: other.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .liquidGlass()
                .contentShape(Circle())
        } primaryAction: {
            sw.toggle()
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("\(other.title)로 전환")
    }
}
