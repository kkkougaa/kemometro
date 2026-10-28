import SwiftUI
import UIKit

// 번역기 화면 공용 조각

/// 칩을 가로로 늘어놓다가 넘치면 다음 줄로
struct TLFlow: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat? = nil

    private func size(_ s: LayoutSubview, _ maxW: CGFloat) -> CGSize {
        s.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let ls = lineSpacing ?? spacing
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = size(s, maxW)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + ls; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ls = lineSpacing ?? spacing
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = size(s, bounds.width)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + ls; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

extension View {
    /// HTML 판의 흰 카드 (다크에선 #1C1C1E)
    func tlCard(_ radius: CGFloat = 14) -> some View {
        background(Color.tlCard, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 강조색 글래스. iOS 26 이전엔 글래스가 색을 못 받아 흰 글씨가 묻히니 단색으로 칠한다.
    @ViewBuilder
    func tlAccentGlass(cornerRadius: CGFloat? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let r = cornerRadius {
                self.glassEffect(.regular.tint(.tlAccent).interactive(), in: RoundedRectangle(cornerRadius: r, style: .continuous))
            } else {
                self.glassEffect(.regular.tint(.tlAccent).interactive(), in: Capsule())
            }
        } else {
            tlAccentSolid(cornerRadius)
        }
        #else
        tlAccentSolid(cornerRadius)
        #endif
    }

    @ViewBuilder
    private func tlAccentSolid(_ r: CGFloat?) -> some View {
        if let r { self.background(Color.tlAccent, in: RoundedRectangle(cornerRadius: r, style: .continuous)) }
        else { self.background(Color.tlAccent, in: Capsule()) }
    }
}

/// 헤더·언어바의 둥근 글래스 버튼
struct TLCircleButton: View {
    let symbol: String
    var size: CGFloat = 40
    var label: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .liquidGlass()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .accessibilityLabel(label)
    }
}

/// 통통 튀는 점 셋
struct TLLoadingDots: View {
    var size: CGFloat = 7
    @State private var on = false

    var body: some View {
        HStack(spacing: size * 0.7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.tlAccent)
                    .frame(width: size, height: size)
                    .offset(y: on ? -size * 0.6 : size * 0.3)
                    .opacity(on ? 1 : 0.45)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: on)
            }
        }
        .frame(height: size * 2.4)
        .onAppear { on = true }
    }
}

/// 회색 바탕 작은 버튼 (복사 · 원문+번역 · 칩)
struct TLFillButton: View {
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.tlOnAccent : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(active ? Color.tlAccent : Color.tlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .tapHaptic()
    }
}

extension Color {
    static let tlText2 = Color(UIColor.secondaryLabel)
    static let tlText3 = Color(UIColor.tertiaryLabel)
    static let tlWarn = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xE0 / 255, green: 0xA4 / 255, blue: 0x6A / 255, alpha: 1)
        : UIColor(red: 0xA6 / 255, green: 0x55 / 255, blue: 0x1A / 255, alpha: 1) })
}

/// 결과 글자 크기 (설정 → 결과 글자 크기)
enum TLResultSize: String, CaseIterable, Identifiable {
    case sm, md, lg
    var id: String { rawValue }
    var label: String { self == .sm ? "작게" : self == .md ? "보통" : "크게" }
    var points: CGFloat { self == .sm ? 15 : self == .md ? 17 : 20 }
}
