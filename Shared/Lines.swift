import SwiftUI
import UIKit

/// 노선 코드(subwayId) → 이름·배지 글자·노선색. 서울교통공사·코레일 공식 노선색.
struct LineInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let colorHex: String
    var color: Color { Color(hex: colorHex) }
}

enum Lines {
    static let all: [LineInfo] = [
        LineInfo(id: "1001", name: "1호선", short: "1", colorHex: "#0052A4"),
        LineInfo(id: "1002", name: "2호선", short: "2", colorHex: "#00A84D"),
        LineInfo(id: "1003", name: "3호선", short: "3", colorHex: "#EF7C1C"),
        LineInfo(id: "1004", name: "4호선", short: "4", colorHex: "#00A5DE"),
        LineInfo(id: "1005", name: "5호선", short: "5", colorHex: "#996CAC"),
        LineInfo(id: "1006", name: "6호선", short: "6", colorHex: "#CD7C2F"),
        LineInfo(id: "1007", name: "7호선", short: "7", colorHex: "#747F00"),
        LineInfo(id: "1008", name: "8호선", short: "8", colorHex: "#E6186C"),
        LineInfo(id: "1009", name: "9호선", short: "9", colorHex: "#BDB092"),
        LineInfo(id: "1063", name: "경의중앙선", short: "경의", colorHex: "#77C4A3"),
        LineInfo(id: "1065", name: "공항철도", short: "공항", colorHex: "#0090D2"),
        LineInfo(id: "1067", name: "경춘선", short: "경춘", colorHex: "#0C8E72"),
        LineInfo(id: "1075", name: "수인분당선", short: "수인", colorHex: "#F5A200"),
        LineInfo(id: "1077", name: "신분당선", short: "신분당", colorHex: "#D4003B"),
        LineInfo(id: "1081", name: "경강선", short: "경강", colorHex: "#003DA5"),
        LineInfo(id: "1092", name: "우이신설선", short: "우이", colorHex: "#B0CE18"),
        LineInfo(id: "1093", name: "서해선", short: "서해", colorHex: "#8FC31F"),
        LineInfo(id: "1032", name: "GTX-A", short: "GTX", colorHex: "#9A6292"),
    ]

    static func info(_ id: String) -> LineInfo {
        all.first { $0.id == id } ?? LineInfo(id: id, name: id, short: "?", colorHex: "#8B95A1")
    }

    /// 자산 카탈로그의 공식 마크(line-1077 등). 없으면 nil.
    static func markImage(_ id: String) -> UIImage? {
        UIImage(named: "line-\(id)")
    }
}

extension Color {
    /// "#RRGGBB" → Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// 공식 노선 마크(Shared/Assets.xcassets, 위키미디어 공용의 공식 디자인 PNG). 없는 노선(GTX-A)은 글자 배지.
struct LineMark: View {
    let lineId: String
    var size: CGFloat = 22

    var body: some View {
        if let ui = Lines.markImage(lineId) {
            Image(uiImage: ui)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            LineBadge(line: Lines.info(lineId), size: size)
        }
    }
}

/// 글자 배지(공식 마크가 없을 때만)
struct LineBadge: View {
    let line: LineInfo
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().fill(line.color)
            Text(line.short)
                .font(.system(size: line.short.count > 1 ? size * 0.36 : size * 0.58, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}
