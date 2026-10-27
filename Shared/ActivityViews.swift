import AppIntents
import SwiftUI

/// 라이브 액티비티의 실제 그림. 위젯 익스텐션이 그대로 쓰고, 앱 안 디자인 미리보기도 같은 뷰를 그린다.
/// 머리: 왼쪽 [마크][역 / OO행], 오른쪽 [히어로 / 한 줄]. 두 줄의 아랫선을 맞춘다. 아래: 진행선 + 버튼.
typealias ActivityState = TrainActivityAttributes.ContentState

extension ActivityState {
    var first: TrainInfo? { trains.first }
    var riding: Bool { mode == 1 && ride != nil }
    var choosing: Bool { mode == 2 || mode == 3 }
}

/// 화면에 쓸 역·노선·방면. 환승 뒤에는 state 쪽 값이 attributes 를 덮는다.
struct ActivityContext {
    let a: TrainActivityAttributes
    let s: ActivityState
    var lineId: String { s.lineId ?? a.lineId }
    var line: LineInfo { Lines.info(lineId) }
    var color: Color { line.color }
    var stationName: String { s.stationName ?? a.stationName }

    /// 왼쪽 큰 글자
    var title: String {
        switch s.mode {
        case 1: return "탑승 중"
        case 2: return "환승"
        case 3: return line.name
        default: return stationName
        }
    }
    /// 왼쪽 작은 칩 "OO행"(접근·탑승)
    var destChip: String? {
        switch s.mode {
        case 1: return s.ride?.dest
        case 2, 3: return nil
        default: return s.first?.dest ?? (s.directionLabel ?? a.directionLabel)
        }
    }
    /// 환승 선택 중 왼쪽 작은 글자(역 이름)
    var plainSub: String? { s.choosing ? stationName : nil }
    /// 오른쪽 큰 글자
    var hero: String? {
        switch s.mode {
        case 1: return s.ride?.current ?? "–"
        case 2, 3: return nil
        default: return s.first?.status ?? (s.message == nil ? "열차 없음" : "–")
        }
    }
    var heroAccent: Bool { s.mode == 0 && (s.first?.level ?? 0) == 2 }
    /// 오른쪽 작은 글자
    var heroSub: String {
        switch s.mode {
        case 1:
            return s.ride?.next.map { "다음 " + $0 } ?? (s.message ?? "")
        case 2: return "어느 노선으로?"
        case 3: return "어디행?"
        default:
            guard let f = s.first else { return s.message ?? "" }
            if f.level == 2 { return "곧 도착" }
            return f.at.isEmpty ? "" : "지금 " + f.at
        }
    }
}

/// 머리 줄
struct ActivityTitleRow: View {
    let attributes: TrainActivityAttributes
    let state: ActivityState
    var nameSize: CGFloat = 17
    var heroSize: CGFloat = 24

    var body: some View {
        let c = ActivityContext(a: attributes, s: state)
        HStack(alignment: .lastTextBaseline, spacing: 9) {
            LineMark(lineId: c.lineId, size: 28)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 6 }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title)
                    .font(.system(size: nameSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                subLine(c)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if let h = c.hero {
                    Text(h)
                        .font(.system(size: h.count > 4 ? heroSize * 0.8 : heroSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(c.heroAccent ? c.color : .primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(c.heroSub)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// "OO행" 칩. 노선색 연한 배경
struct DestChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 17)
            .background(color.opacity(0.22), in: Capsule())
            .lineLimit(1)
    }
}

private func subLine(_ c: ActivityContext) -> some View {
    Group {
        if let chip = c.destChip {
            DestChip(text: chip, color: c.color)
        } else if let t = c.plainSub {
            Text(t).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// 탑승 / 하차 버튼. LiveActivityIntent 라 앱 프로세스에서 실행된다.
struct RideButton: View {
    let attributes: TrainActivityAttributes
    let state: ActivityState
    var height: CGFloat = 30

    var body: some View {
        let c = ActivityContext(a: attributes, s: state)
        if state.riding {
            Button(intent: EndRideIntent(placeId: attributes.placeId)) {
                label("하차", fill: Color.primary.opacity(0.14), fg: .primary)
            }
            .buttonStyle(.plain)
        } else if state.mode == 0, let t = state.first {
            Button(intent: BoardTrainIntent(placeId: attributes.placeId, trainNo: t.id)) {
                label("탑승", fill: c.color, fg: .white)
            }
            .buttonStyle(.plain)
        }
    }

    private func label(_ s: String, fill: Color, fg: Color) -> some View {
        Text(s)
            .font(.system(size: height * 0.44, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, height * 0.47)
            .frame(height: height)
            .background(fill, in: Capsule())
    }
}

/// 환승 선택 버튼들(mode 2: 노선, mode 3: 방면)
struct ChoiceRow: View {
    let attributes: TrainActivityAttributes
    let state: ActivityState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(state.choices.prefix(3)) { opt in
                if state.mode == 2 {
                    Button(intent: ChooseLineIntent(placeId: attributes.placeId, lineId: opt.lineId)) {
                        HStack(spacing: 6) {
                            LineMark(lineId: opt.lineId, size: 22)
                            Text(opt.title).font(.system(size: 13, weight: .bold))
                        }
                        .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(intent: ChooseDirectionIntent(placeId: attributes.placeId, lineId: opt.lineId, dest: opt.dest, updn: opt.updn)) {
                        Text(opt.title).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if state.mode == 2 {
                Button(intent: DismissIntent(placeId: attributes.placeId)) {
                    Text("그냥 내림").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 진행선 + 버튼 한 줄
struct ActivityBottomRow: View {
    let attributes: TrainActivityAttributes
    let state: ActivityState
    var height: CGFloat = 48
    var markerSize: CGFloat = 24

    var body: some View {
        let c = ActivityContext(a: attributes, s: state)
        if state.choosing {
            ChoiceRow(attributes: attributes, state: state)
        } else {
            HStack(spacing: 10) {
                if state.riding, let r = state.ride {
                    RideProgressView(ride: r, lineId: c.lineId, markerSize: markerSize)
                        .frame(height: height)
                } else if state.trains.isEmpty {
                    Text(state.message ?? "접근 중인 열차가 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: height * 0.7)
                } else {
                    RouteProgressView(trains: state.trains, slots: attributes.slots, lineId: c.lineId,
                                      stationName: c.stationName, markerSize: markerSize,
                                      pulse: (state.first?.level ?? 0) == 2, reveal: state.phase == 1)
                        .frame(height: height)
                }
                RideButton(attributes: attributes, state: state)
            }
        }
    }
}

/// 잠금화면·알림센터 배너
struct ActivityLockView: View {
    let attributes: TrainActivityAttributes
    let state: ActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActivityTitleRow(attributes: attributes, state: state, nameSize: 18, heroSize: 27)
            ActivityBottomRow(attributes: attributes, state: state, height: 50, markerSize: 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
    }
}

/// 다이내믹 아일랜드 조각
enum ActivityIslandParts {
    static func leading(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        let c = ActivityContext(a: a, s: s)
        return HStack(alignment: .lastTextBaseline, spacing: 9) {
            LineMark(lineId: c.lineId, size: 28)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 6 }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                subLine(c)
            }
        }
        .padding(.leading, 4)
        .padding(.top, 3)
    }

    static func trailing(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        let c = ActivityContext(a: a, s: s)
        return VStack(alignment: .trailing, spacing: 3) {
            if let h = c.hero {
                Text(h)
                    .font(.system(size: h.count > 4 ? 19 : 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(c.heroAccent ? c.color : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(c.heroSub)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.trailing, 4)
        .padding(.top, 3)
    }

    static func bottom(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        ActivityBottomRow(attributes: a, state: s, height: 48, markerSize: 26)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    static func compactLeading(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        LineMark(lineId: s.lineId ?? a.lineId, size: 22)
            .padding(.leading, 2)
    }

    static func compactTrailing(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        let c = ActivityContext(a: a, s: s)
        return Text(s.choosing ? "환승" : (c.hero ?? "–"))
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(c.color)
            .contentTransition(.numericText())
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 66, alignment: .trailing)
            .padding(.trailing, 2)
    }

    static func minimal(_ a: TrainActivityAttributes, _ s: ActivityState) -> some View {
        let c = ActivityContext(a: a, s: s)
        let text: String = {
            if s.riding { return "탑승" }
            if s.choosing { return "환승" }
            guard let t = s.first else { return "–" }
            return t.level == 2 ? "곧" : t.status.replacingOccurrences(of: " 전", with: "")
        }()
        return Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(c.color)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}
