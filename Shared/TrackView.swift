import AppIntents
import SwiftUI

/// 전동차 마커: 흰 원 안에 노선색 전동차(SF Symbol tram.fill). 노선 로고를 쓰지 않고 선 위에 얹는다.
struct TrainMarker: View {
    let color: Color
    var size: CGFloat = 26
    var ring: Color = Color.black.opacity(0.9)

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: "tram.fill")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(ring, lineWidth: 2).padding(-2))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1.5)
    }
}

/// 열차종류·막차 칩. 마커 위에 얹는다.
struct TrainTagChip: View {
    let text: String

    private var fill: Color {
        switch text {
        case "막차": return Color(hex: "#5E5CE6")
        case "ITX": return Color(hex: "#0A84FF")
        default: return Color(hex: "#E5483C")
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(fill, in: Capsule())
            .fixedSize()
    }
}

struct TagChips: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tags, id: \.self) { TrainTagChip(text: $0) }
        }
    }

    /// 칩 묶음의 대략적인 너비(가장자리에서 잘리지 않게 위치를 조정할 때 쓴다)
    static func width(_ tags: [String]) -> CGFloat { CGFloat(tags.count) * 29 + CGFloat(max(0, tags.count - 1)) * 3 }
    /// 칩이 있을 때 진행선 위쪽에 더 두는 높이
    static func room(_ tags: [String]) -> CGFloat { tags.isEmpty ? 0 : 15 }
}

/// 접근 진행선: 오른쪽 끝이 이 역, 왼쪽으로 한 칸이 한 역 전. 지나온 구간은 노선색 그라데이션.
/// `reveal` 이 false→true 로 바뀌면 오른쪽 바깥에서 그려져 들어오고, n 이 바뀌면 마커가 스프링으로 미끄러진다.
struct RouteProgressView: View {
    let trains: [TrainInfo]
    let slots: Int
    let lineId: String
    let stationName: String
    var markerSize: CGFloat = 26
    var pulse: Bool = false
    var reveal: Bool = true
    var tags: [String] = []
    /// 고른 열차. 열차 마커를 누르면 SelectTrainIntent 로 바뀐다
    var selectedId: String? = nil
    var placeId: String = ""

    private var color: Color { Lines.info(lineId).color }
    private var live: [TrainInfo] { trains.filter { !$0.departed } }
    private var gone: TrainInfo? { trains.first { $0.departed } }
    private var positions: [Double] { live.map { $0.n ?? Double(slots) + 1.3 } }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pad = markerSize / 2 + 2
            // 막 떠난 열차가 있으면 오른쪽에 자리를 비운다
            let extra: CGFloat = gone == nil ? 0 : markerSize * 0.9
            let inner = w - pad * 2 - extra
            let top = TagChips.room(tags)
            let y = top + (geo.size.height - top) * 0.4
            let lead = min(positions.first ?? Double(slots) + 0.6, Double(slots) + 0.6)
            let fillW = max(0, inner * CGFloat(1 - lead / Double(slots)))

            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.primary.opacity(0.16))
                    .frame(width: inner, height: 4)
                    .position(x: w / 2, y: y)
                Capsule().fill(LinearGradient(colors: [color.opacity(0.18), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fillW, 4), height: 4)
                    .position(x: pad + max(fillW, 4) / 2, y: y)
                    .opacity(fillW > 0 ? 1 : 0)
                ForEach(1...max(slots, 1), id: \.self) { i in
                    Circle().fill(Color.primary.opacity(0.35))
                        .frame(width: 5, height: 5)
                        .position(x: xOf(Double(i), w: w, pad: pad, inner: inner), y: y)
                }
                Circle().fill(Color.primary)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.25 : 1)
                    .position(x: pad + inner, y: y)
                Text(stationName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: pad + inner, y: y + 17)
                ForEach(Array(live.prefix(2).enumerated()), id: \.element.id) { idx, t in
                    let n = t.n ?? Double(slots) + 1.3
                    let x = xOf(n, w: w, pad: pad, inner: inner)
                    let chosen = t.id == (selectedId ?? live.first?.id)
                    let hidden = n > Double(slots) + 0.5
                    Button(intent: SelectTrainIntent(placeId: placeId, trainId: t.id)) {
                        TrainMarker(color: color, size: chosen ? markerSize : markerSize * 0.7)
                            .frame(width: markerSize + 8, height: markerSize + 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hidden ? 0 : (chosen ? 1 : 0.8))
                    .allowsHitTesting(!hidden)
                    .position(x: x, y: y)
                    if chosen, !tags.isEmpty {
                        let half = TagChips.width(tags) / 2
                        TagChips(tags: tags)
                            .opacity(hidden ? 0 : 1)
                            .position(x: min(max(x, half), w - half), y: y - markerSize / 2 - 11)
                    }
                    if chosen, !t.at.isEmpty, n > 1.1 {
                        Text(t.at)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .position(x: x, y: y + 19)
                            .opacity(hidden ? 0 : 1)
                    }
                }
                if let g = gone {
                    let gx = pad + inner + extra * 0.72
                    let chosenGone = selectedId == g.id
                    Button(intent: SelectTrainIntent(placeId: placeId, trainId: g.id)) {
                        TrainMarker(color: color, size: chosenGone ? markerSize : markerSize * 0.7)
                            .frame(width: markerSize + 8, height: markerSize + 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(chosenGone ? 1 : 0.55)
                    .position(x: gx, y: y)
                    if chosenGone, !tags.isEmpty {
                        let half = TagChips.width(tags) / 2
                        TagChips(tags: tags)
                            .position(x: min(max(gx, half), w - half), y: y - markerSize / 2 - 11)
                    }
                }
            }
            .mask(alignment: .trailing) {
                Rectangle().frame(width: reveal ? w + 40 : 0)
            }
            .opacity(reveal ? 1 : 0)
            .animation(.spring(duration: 0.95, bounce: 0.18), value: positions)
            .animation(.spring(duration: 0.6, bounce: 0.3), value: pulse)
            .animation(.easeOut(duration: 0.8), value: reveal)
        }
    }

    private func xOf(_ n: Double, w: CGFloat, pad: CGFloat, inner: CGFloat) -> CGFloat {
        let clamped = min(n, Double(slots) + 0.6)
        return pad + inner * CGFloat(1 - clamped / Double(slots))
    }
}

/// 탑승 진행선: 마커는 둘째 칸에 고정이고 4정거장 창이 옆으로 흐른다. 양끝은 부드럽게 사라진다.
struct RideProgressView: View {
    let ride: RideInfo
    let lineId: String
    var markerSize: CGFloat = 26
    var tags: [String] = []

    private var color: Color { Lines.info(lineId).color }
    /// 역 사이(출발 상태)면 반 칸 앞으로
    private var position: Double {
        guard ride.pathIndex >= 0 else { return 0 }
        return Double(ride.pathIndex) + (ride.status == 2 && ride.pathIndex < ride.path.count - 1 ? 0.5 : 0)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pad: CGFloat = 14
            let step = (w - pad * 2) / 3
            let top = TagChips.room(tags)
            let y = top + (geo.size.height - top) * 0.4
            let trainX = pad + step
            let lo = max(0, Int(position.rounded(.down)) - 2)
            let hi = min(ride.path.count - 1, Int(position.rounded(.up)) + 3)

            ZStack(alignment: .topLeading) {
                // 선: 마커 왼쪽은 노선색, 오른쪽은 회색
                Capsule().fill(Color.primary.opacity(0.16))
                    .frame(width: w, height: 4)
                    .position(x: w / 2, y: y)
                Capsule().fill(LinearGradient(colors: [color.opacity(0), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: trainX, height: 4)
                    .position(x: trainX / 2, y: y)
                if ride.path.isEmpty {
                    Text("지금 " + ride.current)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: w / 2, y: y + 19)
                } else {
                    ForEach(lo...max(lo, hi), id: \.self) { i in
                        let x = pad + step * (CGFloat(i) - CGFloat(position) + 1)
                        Circle().fill(Double(i) <= position ? color : Color.primary.opacity(0.35))
                            .frame(width: 5, height: 5)
                            .position(x: x, y: y)
                        Text(ride.path[i])
                            .font(.system(size: 10, weight: i == ride.pathIndex ? .bold : .medium))
                            .foregroundStyle(i == ride.pathIndex ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: step - 6)
                            .position(x: x, y: y + 19)
                    }
                }
                TrainMarker(color: color, size: markerSize)
                    .position(x: trainX, y: y)
                if !tags.isEmpty {
                    TagChips(tags: tags)
                        .position(x: trainX, y: y - markerSize / 2 - 11)
                }
            }
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.17),
                                       .init(color: .black, location: 0.83), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .animation(.spring(duration: 0.95, bounce: 0.12), value: position)
        }
    }
}

/// 상태 칩(설정 화면·목록용)
struct StatusChip: View {
    let status: String
    let level: Int
    let color: Color
    var height: CGFloat = 20

    var body: some View {
        Text(status)
            .font(.system(size: height * 0.58, weight: .heavy))
            .lineLimit(1)
            .padding(.horizontal, height * 0.42)
            .frame(height: height)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
            .contentTransition(.numericText())
    }

    private var background: Color {
        switch level {
        case 2: return color
        case 1: return color.opacity(0.18)
        default: return Color.primary.opacity(0.09)
        }
    }

    private var foreground: Color {
        switch level {
        case 2: return .white
        case 1: return color
        default: return .primary
        }
    }
}
