import AppIntents
import Foundation

/// 단축어 앱에서 고를 수 있는 "감시할 역"(설정에 넣어 둔 역·노선·방면)
struct PlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "감시할 역"
    static let defaultQuery = PlaceQuery()

    var id: UUID
    var name: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ p: Place) {
        id = p.id
        name = p.name
        detail = "\(Lines.info(p.lineId).name) \(p.directionLabel)"
    }
}

struct PlaceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlaceEntity] {
        await MainActor.run {
            ConfigStore.shared.config.places.filter { identifiers.contains($0.id) }.map { PlaceEntity($0) }
        }
    }

    func suggestedEntities() async throws -> [PlaceEntity] {
        await MainActor.run { ConfigStore.shared.config.places.map { PlaceEntity($0) } }
    }
}

/// 단축어 자동화("도착" 등)에서 부르는 동작. 앱을 열지 않고 그 역에 오는 열차를 라이브 액티비티로 띄운다.
struct StartStationIntent: AppIntent {
    static var title: LocalizedStringResource = "역 열차 추적 시작"
    static var description = IntentDescription("고른 역에 오는 열차를 라이브 액티비티로 띄웁니다")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "역") var place: PlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$place) 열차 추적 시작")
    }

    init() {}
    init(place: PlaceEntity) { self.place = place }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let p = ConfigStore.shared.place(id: place.id.uuidString) {
            await ActivityController.shared.trigger(place: p, reason: "단축어", force: true)
        }
        return .result()
    }
}

/// 위 동작이 백그라운드에서 막힐 때 쓰는 대안: 앱이 잠깐 열리고 라이브 액티비티를 띄운다.
struct StartStationOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "역 열차 추적 시작 (앱 열기)"
    static var description = IntentDescription("앱을 열고 고른 역에 오는 열차를 라이브 액티비티로 띄웁니다")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "역") var place: PlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$place) 열차 추적 시작(앱 열기)")
    }

    init() {}
    init(place: PlaceEntity) { self.place = place }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let p = ConfigStore.shared.place(id: place.id.uuidString) {
            await ActivityController.shared.trigger(place: p, reason: "단축어(앱 열기)", force: true)
        }
        return .result()
    }
}

/// 단축어 앱의 앱 단축어 목록에 자동으로 올라간다.
struct KemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStationIntent(),
            phrases: ["\(.applicationName) 열차 추적"],
            shortTitle: "열차 추적",
            systemImageName: "tram.fill"
        )
    }
}
