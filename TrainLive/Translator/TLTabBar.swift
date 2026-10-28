import SwiftUI
import UIKit

// 번역기 하단 바. iOS 기본 탭 바는 글래스에 색을 넣을 수도, 모양을 바꿀 수도 없어서 직접 그린다.
// · 바 글래스에 설정 색(하단 바)을 칠한다. 아이콘 색·이름 표시도 설정에서.
// · 번역 화면을 아래로 내리면 바가 오른쪽으로 녹아들며 노란 쓰기 버튼 하나로 바뀐다
//   (iOS 26 GlassEffectContainer + glassEffectID 로 같은 글래스가 모양만 바꾼다).

struct TLTabItem: Identifiable {
    let id: TLTab
    let title: String
    let symbol: String

    static let all: [TLTabItem] = [
        TLTabItem(id: .home, title: "번역", symbol: "character.bubble.fill"),
        TLTabItem(id: .screen, title: "PIP 번역", symbol: "pip.fill"),
        TLTabItem(id: .talk, title: "대화 모드", symbol: "bubble.left.and.text.bubble.right.fill"),
        TLTabItem(id: .settings, title: "설정", symbol: "gearshape.fill")
    ]
}

struct TLTabBar: View {
    @Binding var tab: TLTab
    /// 접힘 — 쓰기 버튼 하나만 남는다
    let collapsed: Bool
    let onWrite: () -> Void
    @ObservedObject private var store = TLStore.shared
    @Namespace private var ns

    /// 바 높이 (이름을 끄면 낮아진다)
    static func height(labels: Bool) -> CGFloat { labels ? 62 : 54 }

    private var iconColor: Color { Color(tlHex: store.tabIconTint) ?? .white }
    private var barTint: Color { TLPalette.barColor.opacity(0.85 * store.tintStrength) }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassBar
        } else {
            plainBar
        }
        #else
        plainBar
        #endif
    }

    // MARK: iOS 26 — 리퀴드 글래스

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glassBar: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 0) {
                if collapsed {
                    Spacer(minLength: 0)
                    writeLabel
                        .glassEffect(.regular.tint(TLPalette.writeColor).interactive(), in: Circle())
                        .glassEffectID("bar", in: ns)
                        .onTapGesture { onWrite() }
                } else {
                    items
                        .glassEffect(.regular.tint(barTint).interactive(), in: Capsule())
                        .glassEffectID("bar", in: ns)
                }
            }
        }
    }
    #endif

    // MARK: iOS 26 이전 — 반투명 재질 + 같은 자리 옮기기

    private var plainBar: some View {
        HStack(spacing: 0) {
            if collapsed {
                Spacer(minLength: 0)
                writeLabel
                    .background(Circle().fill(TLPalette.writeColor))
                    .matchedGeometryEffect(id: "bar", in: ns)
                    .onTapGesture { onWrite() }
            } else {
                items
                    .background(Capsule().fill(.ultraThinMaterial))
                    .background(Capsule().fill(barTint))
                    .matchedGeometryEffect(id: "bar", in: ns)
            }
        }
    }

    // MARK: 조각

    private var items: some View {
        HStack(spacing: 0) {
            ForEach(TLTabItem.all) { it in
                let on = tab == it.id
                Button {
                    guard tab != it.id else { return }
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { tab = it.id }
                    TLHaptic.select()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: it.symbol)
                            .font(.system(size: store.tabLabels ? 18 : 20, weight: .semibold))
                        if store.tabLabels {
                            Text(it.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(iconColor.opacity(on ? 1 : 0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.height(labels: store.tabLabels) - 10)
                    .background {
                        if on {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .matchedGeometryEffect(id: "selected", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(it.title)
            }
        }
        .padding(5)
        .frame(height: Self.height(labels: store.tabLabels))
    }

    private var writeLabel: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(TLPalette.ink(on: store.writeTint, strength: store.tintStrength))
            .frame(width: Self.height(labels: store.tabLabels), height: Self.height(labels: store.tabLabels))
            .contentShape(Circle())
            .accessibilityLabel("쓰기")
            .accessibilityAddTraits(.isButton)
    }
}
