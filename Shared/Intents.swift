import AppIntents
import Foundation

/// 라이브 액티비티 버튼이 부르는 인텐트. LiveActivityIntent 는 위젯이 아니라 앱 프로세스에서 실행되므로
/// 앱이 시작할 때 RideIntentHandler 에 실제 동작을 꽂아 둔다. 위젯 타깃에도 같은 파일이 들어가지만 거기선 실행되지 않는다.
enum RideIntentHandler {
    static var board: ((String, String) async -> Void)?
    static var end: ((String) async -> Void)?
    static var chooseLine: ((String, String) async -> Void)?
    static var chooseDirection: ((String, String, String, String) async -> Void)?
    static var dismiss: ((String) async -> Void)?
    static var select: ((String, String) async -> Void)?
    static var shift: ((String, Int) async -> Void)?
}

/// "탑승": 이 열차를 추적 모드로
struct BoardTrainIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "탑승"
    static var description = IntentDescription("가장 가까운 열차를 타고 가는 동안 지금 역을 계속 보여줍니다")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String
    @Parameter(title: "열차 번호") var trainNo: String

    init() { placeId = ""; trainNo = "" }
    init(placeId: String, trainNo: String) { self.placeId = placeId; self.trainNo = trainNo }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.board?(placeId, trainNo)
        return .result()
    }
}

/// "하차": 추적을 끝내고, 환승 노선이 있으면 묻는다
struct EndRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "하차"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String

    init() { placeId = "" }
    init(placeId: String) { self.placeId = placeId }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.end?(placeId)
        return .result()
    }
}

/// 환승할 노선 선택
struct ChooseLineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "환승 노선"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String
    @Parameter(title: "노선") var lineId: String

    init() { placeId = ""; lineId = "" }
    init(placeId: String, lineId: String) { self.placeId = placeId; self.lineId = lineId }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.chooseLine?(placeId, lineId)
        return .result()
    }
}

/// 환승 방면 선택 → 그 승강장으로 오는 열차를 다시 보여준다
struct ChooseDirectionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "환승 방면"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String
    @Parameter(title: "노선") var lineId: String
    @Parameter(title: "종착역") var dest: String
    @Parameter(title: "상하행") var updn: String

    init() { placeId = ""; lineId = ""; dest = ""; updn = "" }
    init(placeId: String, lineId: String, dest: String, updn: String) {
        self.placeId = placeId; self.lineId = lineId; self.dest = dest; self.updn = updn
    }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.chooseDirection?(placeId, lineId, dest, updn)
        return .result()
    }
}

/// "그냥 내림": 액티비티를 치운다
struct DismissIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "닫기"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String

    init() { placeId = "" }
    init(placeId: String) { self.placeId = placeId }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.dismiss?(placeId)
        return .result()
    }
}

/// 노선도의 열차 마커를 눌러 탑승할 열차를 고른다
struct SelectTrainIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "열차 선택"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String
    @Parameter(title: "열차 번호") var trainId: String

    init() { placeId = ""; trainId = "" }
    init(placeId: String, trainId: String) { self.placeId = placeId; self.trainId = trainId }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.select?(placeId, trainId)
        return .result()
    }
}

/// 탑승 중 추적할 열차를 앞 열차(+1) 또는 뒤 열차(-1)로 바꾼다
struct ShiftTrainIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "열차 변경"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역 설정 ID") var placeId: String
    @Parameter(title: "방향") var delta: Int

    init() { placeId = ""; delta = 1 }
    init(placeId: String, delta: Int) { self.placeId = placeId; self.delta = delta }

    func perform() async throws -> some IntentResult {
        await RideIntentHandler.shift?(placeId, delta)
        return .result()
    }
}
