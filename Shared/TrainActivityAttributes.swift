import ActivityKit
import Foundation

/// 라이브 액티비티에 실리는 데이터. 앱과 위젯 익스텐션이 똑같은 정의를 써야 한다.
struct TrainActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 가까운 순으로 정렬된 열차(접근 모드)
        var trains: [TrainInfo]
        /// 조회 시각
        var fetchedAt: Date
        /// 0 = 등장 직후(열차를 화면 밖에 둔다), 1 = 실제 위치. 0→1 갱신으로 들어오는 애니메이션을 만든다.
        var phase: Int
        /// 조회 실패 등 안내 문구
        var message: String?
        /// 이 시각에 사라진다(접근 모드)
        var endsAt: Date
        /// 0 = 접근(역에서 기다리는 중), 1 = 탑승 추적, 2 = 환승 노선 선택, 3 = 환승 방면 선택
        var mode: Int = 0
        /// 탑승 추적 정보
        var ride: RideInfo? = nil
        /// 환승 선택지(mode 2·3)
        var choices: [ChoiceOption] = []
        /// 환승 뒤 접근 모드의 역·노선·방면(처음 attributes 와 다를 수 있다)
        var stationName: String? = nil
        var lineId: String? = nil
        var directionLabel: String? = nil
    }

    /// 어느 설정(역)에서 띄웠는지. 버튼 인텐트가 이 id 로 돌아온다
    var placeId: String
    var stationName: String
    var lineId: String
    var lineName: String
    var lineShort: String
    var lineColorHex: String
    /// "신사 방면"
    var directionLabel: String
    /// 선로 그림에 보여줄 이전 역 수
    var slots: Int
}

struct TrainInfo: Codable, Hashable, Identifiable {
    var id: String
    /// "전역", "3역 전", "진입", "도착", "4분 후"
    var status: String
    /// 몇 역 전 자리에 그릴지. nil 이면 선로 왼쪽 끝
    var n: Double?
    /// 2 = 이 역 진입·도착, 1 = 바로 전역, 0 = 그 밖
    var level: Int
    /// "신사행"
    var dest: String
    /// 현재 위치 역명
    var at: String
    var tags: [String]
    var approx: Bool
}

/// 탑승한 열차의 현재 상태(목적지 없이 지금 위치만)
struct RideInfo: Codable, Hashable {
    var trainNo: String
    /// 지금 역
    var current: String
    /// 0 진입 · 1 도착 · 2 출발 (열차 위치 API 의 trainSttus)
    var status: Int
    /// 다음 역(역 순서표가 있을 때)
    var next: String?
    /// 탑승역부터 종착역까지의 역 이름(순서대로). 4정거장 창이 이 위를 흐른다
    var path: [String]
    /// path 안에서 지금 역의 위치(없으면 -1)
    var pathIndex: Int
    /// 종착역 "신사행"
    var dest: String
}

/// 환승 선택지 하나. 노선 선택이면 lineId, 방면 선택이면 dest·updn
struct ChoiceOption: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var lineId: String
    var dest: String = ""
    var updn: String = ""
}
