import SwiftUI
import UIKit

// 번역기 하단 바. iOS 기본 탭 바는 글래스에 색을 넣을 수도, 모양을 바꿀 수도 없어서 직접 그린다.
// 바 하나가 상황에 따라 세 모양으로 녹아들며 바뀐다 (iOS 26 GlassEffectContainer + glassEffectID):
// · 평소: 탭 네 개가 든 글래스 바 (하단 바 색)
// · 번역 화면을 내리면: 오른쪽 노란 쓰기 버튼
// · 입력칸을 누르면: 키보드 위 오른쪽 번역 버튼 (번역 버튼 색) — 쓰기 버튼에서 바로 이어진다

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

enum TLBarMode: Equatable { case full, write, translate }

struct TLTabBar: View {
    @Binding var tab: TLTab
    let mode: TLBarMode
    var busy = false
    var canTranslate = true
    let onWrite: () -> Void
    let onTranslate: () -> Void
    @ObservedObject private var store = TLStore.shared
    @Namespace private var ns

    /// 바 높이 — 이름을 꺼도 같은 높이를 지킨다
    static let height: CGFloat = 62
    /// 쓰기·번역 버튼 높이
    private let actionH: CGFloat = 54

    private var iconColor: Color { Color(tlHex: store.tabIconTint) ?? .white }
    private var barTint: Color { TLPalette.barGlassColor }
    private var actionTint: Color { mode == .write ? TLPalette.writeColor : TLPalette.buttonColor }
    private var actionInk: Color {
        mode == .write
            ? TLPalette.ink(on: store.writeTint, strength: store.writeStrength)
            : (store.buttonTint.isEmpty && store.buttonStrength >= 1
                ? Color.tlOnAccent : TLPalette.ink(on: store.buttonTint, strength: store.buttonStrength))
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.bottom, mode == .translate ? 12 : 6)
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
    /// 설정 → 모양 → 글래스: 맑은 · 일반
    @available(iOS 26.0, *)
    private var glass: Glass { store.glassClear ? .clear : .regular }

    @available(iOS 26.0, *)
    private var glassBar: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 0) {
                if mode == .full {
                    items
                        .glassEffect(glass.tint(barTint).interactive(), in: Capsule())
                        .glassEffectID("bar", in: ns)
                } else {
                    // 쓰기 ↔ 번역은 같은 버튼이 색·아이콘·폭만 바꾼다
                    Spacer(minLength: 0)
                    actionLabel
                        .glassEffect(glass.tint(actionTint).interactive(), in: Capsule())
                        .glassEffectID("bar", in: ns)
                        .onTapGesture { tapAction() }
                }
            }
        }
    }
    #endif

    // MARK: iOS 26 이전 — 반투명 재질 + 같은 자리 옮기기

    private var plainBar: some View {
        HStack(spacing: 0) {
            if mode == .full {
                items
                    .background(Capsule().fill(.ultraThinMaterial))
                    .background(Capsule().fill(barTint))
                    .matchedGeometryEffect(id: "bar", in: ns)
            } else {
                Spacer(minLength: 0)
                actionLabel
                    .background(Capsule().fill(actionTint))
                    .matchedGeometryEffect(id: "bar", in: ns)
                    .onTapGesture { tapAction() }
            }
        }
    }

    private func tapAction() {
        if mode == .write { onWrite() } else if busy || canTranslate { onTranslate() }
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
                    VStack(spacing: 3) {
                        Image(systemName: it.symbol)
                            .font(.system(size: store.tabLabels ? 18 : 21, weight: .semibold))
                        if store.tabLabels {
                            Text(it.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(iconColor.opacity(on ? 1 : 0.62))
                    // 이름을 꺼도 칸 높이는 그대로, 아이콘은 가운데
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(height: Self.height)
    }

    /// 쓰기(연필 동그라미) ↔ 번역(알약)
    private var actionLabel: some View {
        HStack(spacing: 6) {
            if mode == .write {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 21, weight: .semibold))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Text(busy ? "취소" : "번역")
                    .font(.system(size: 16, weight: .semibold))
                    .transition(.opacity)
                Image(systemName: busy ? "xmark" : "play.fill")
                    .font(.system(size: busy ? 12 : 11, weight: .bold))
                    .opacity(0.8)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .foregroundStyle(actionInk)
        .padding(.horizontal, mode == .write ? 0 : 22)
        .frame(minWidth: actionH)
        .frame(height: actionH)
        .contentShape(Capsule())
        .opacity(mode == .translate && !busy && !canTranslate ? 0.55 : 1)
        .accessibilityLabel(mode == .write ? "쓰기" : (busy ? "취소" : "번역"))
        .accessibilityAddTraits(.isButton)
    }
}
