import Foundation

/// API 키 없이 모양을 볼 때 쓰는 가짜 열차. CI 시뮬레이터 스크린샷과 앱 안 디자인 미리보기가 쓴다.
enum DemoData {
    static let attributes = TrainActivityAttributes(
        placeId: "demo", stationName: "판교", lineId: "1077", lineName: "신분당선", lineShort: "신분당",
        lineColorHex: "#D4003B", directionLabel: "신사 방면", slots: 4)

    static let trains: [TrainInfo] = [
        TrainInfo(id: "d1", status: "전역", n: 1, level: 1, dest: "신사행", at: "정자", tags: [], approx: false),
        TrainInfo(id: "d2", status: "4역 전", n: 4, level: 0, dest: "신사행", at: "동천", tags: [], approx: false),
    ]

    /// 몇 초 뒤 상태: 열차가 한 칸씩 다가온 모습(영상에서 움직임을 보여주기 위해)
    static let trainsLater: [TrainInfo] = [
        TrainInfo(id: "d1", status: "진입", n: 0.15, level: 2, dest: "신사행", at: "", tags: [], approx: false),
        TrainInfo(id: "d2", status: "3역 전", n: 3, level: 0, dest: "신사행", at: "수지구청", tags: [], approx: false),
    ]

    static func state(phase: Int, slots: Int, endsAt: Date, later: Bool = false) -> TrainActivityAttributes.ContentState {
        let base = later ? trainsLater : trains
        let trains = phase == 0 ? base.map { t -> TrainInfo in var c = t; c.n = Double(slots) + 1.2; return c } : base
        return TrainActivityAttributes.ContentState(trains: trains, fetchedAt: Date(), phase: phase, message: nil, endsAt: endsAt)
    }

    /// 탑승 추적 데모: 판교 → 신논현. step 이 커질수록 한 역씩 간다.
    static let ridePath = ["판교", "청계산입구", "양재시민의숲", "양재", "강남", "신논현", "논현", "신사"]
    /// 한 역마다 4걸음: 도착 → 출발 → 이동중 → 다음 역 진입중
    static func ride(step: Int) -> RideInfo {
        let last = ridePath.count - 1
        let i = min(step / 4 + (step % 4 == 3 ? 1 : 0), last)
        let phase = i >= last ? 0 : step % 4
        let status = phase == 0 ? 1 : (phase == 3 ? 0 : 2)
        return RideInfo(trainNo: "3", current: ridePath[i], status: status,
                        next: i + 1 < ridePath.count ? ridePath[i + 1] : nil,
                        path: ridePath, pathIndex: i, dest: "신사행", moving: phase == 2)
    }
    static func rideState(step: Int) -> TrainActivityAttributes.ContentState {
        var s = TrainActivityAttributes.ContentState(trains: trainsLater, fetchedAt: Date(), phase: 1, message: nil, endsAt: Date().addingTimeInterval(3600))
        s.mode = 1
        s.ride = ride(step: step)
        return s
    }

    /// 환승 선택 데모: 신논현에서 9호선
    static func transferState(stage: Int) -> TrainActivityAttributes.ContentState {
        var s = TrainActivityAttributes.ContentState(trains: [], fetchedAt: Date(), phase: 1, message: nil, endsAt: Date().addingTimeInterval(3600))
        s.stationName = "신논현"
        if stage == 2 {
            s.mode = 2
            s.choices = [ChoiceOption(id: "1009", title: "9호선", lineId: "1009")]
        } else {
            s.mode = 3
            s.lineId = "1009"
            s.choices = [ChoiceOption(id: "a", title: "중앙보훈병원행", lineId: "1009", dest: "중앙보훈병원", updn: "하행"),
                         ChoiceOption(id: "b", title: "개화행", lineId: "1009", dest: "개화", updn: "상행")]
        }
        return s
    }
}

/// 실행 인자·환경변수. CI 가 시뮬레이터에서 띄울 때 쓴다.
///   -preview            : 앱 안 디자인 미리보기 화면으로 바로 들어간다
///   -demo / TRAINLIVE_DEMO=1 : 가짜 열차로 첫 번째 역 액티비티를 바로 띄운다
enum LaunchFlags {
    static var preview: Bool { CommandLine.arguments.contains("-preview") }
    static var demo: Bool {
        CommandLine.arguments.contains("-demo") || ProcessInfo.processInfo.environment["TRAINLIVE_DEMO"] == "1"
    }
}
