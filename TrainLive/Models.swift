import Combine
import Foundation

/// 감시할 역 하나. 반경 안에 들어오면 이 방면 열차를 띄운다.
struct Place: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 화면에 보일 이름
    var name: String
    /// 실시간 API 에 보낼 역명(보통 name 과 같고, "서울역"→"서울" 같은 경우만 다르다)
    var apiName: String
    var lineId: String
    /// 종착역 이름("신사"). 이 종착역으로 가는 방향을 고른다
    var dest: String
    /// 종착역으로 못 고를 때 쓰는 상행/하행 키
    var updn: String
    var latitude: Double
    var longitude: Double
    /// 지오펜스 반경(m)
    var radius: Double = 500
    /// 라이브 액티비티를 띄워 둘 시간(초)
    var showSeconds: Double = 180
    var enabled: Bool = true

    var directionLabel: String { dest.isEmpty ? updn : dest + " 방면" }

    private enum CodingKeys: String, CodingKey {
        case id, name, apiName, lineId, dest, updn, latitude, longitude, radius, showSeconds, enabled
    }

    init(id: UUID = UUID(), name: String, apiName: String, lineId: String, dest: String, updn: String,
         latitude: Double, longitude: Double, radius: Double = 500, showSeconds: Double = 180, enabled: Bool = true) {
        self.id = id; self.name = name; self.apiName = apiName; self.lineId = lineId; self.dest = dest; self.updn = updn
        self.latitude = latitude; self.longitude = longitude; self.radius = radius; self.showSeconds = showSeconds
        self.enabled = enabled
    }

    // 예전 저장분에 없는 키는 기본값으로
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        apiName = (try? c.decode(String.self, forKey: .apiName)) ?? ""
        lineId = (try? c.decode(String.self, forKey: .lineId)) ?? ""
        dest = (try? c.decode(String.self, forKey: .dest)) ?? ""
        updn = (try? c.decode(String.self, forKey: .updn)) ?? ""
        latitude = (try? c.decode(Double.self, forKey: .latitude)) ?? 0
        longitude = (try? c.decode(Double.self, forKey: .longitude)) ?? 0
        radius = (try? c.decode(Double.self, forKey: .radius)) ?? 500
        showSeconds = (try? c.decode(Double.self, forKey: .showSeconds)) ?? 180
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }
}

struct AppConfig: Codable {
    var apiKey: String = ""
    var places: [Place] = AppConfig.defaultPlaces
    /// 선로 그림에 보여줄 이전 역 수
    var slots: Int = 4
    /// 방면마다 띄울 열차 수
    var trainsPerDirection: Int = 2
    /// 같은 역에서 다시 띄우기까지 최소 간격(초)
    var cooldownSeconds: Double = 300
    /// 띄워 둔 동안 다시 조회하는 간격(초)
    var refreshSeconds: Double = 5
    /// 탑승 추적 중 조회 간격(초)
    var rideRefreshSeconds: Double = 15
    /// 탑승 추적 최대 시간(분)
    var rideMaxMinutes: Double = 90

    static let defaultPlaces: [Place] = [
        Place(name: "판교", apiName: "판교", lineId: "1077", dest: "신사", updn: "상행",
              latitude: 37.394761, longitude: 127.111217),
        Place(name: "논현", apiName: "논현", lineId: "1077", dest: "광교", updn: "하행",
              latitude: 37.511093, longitude: 127.021415),
    ]

    private enum CodingKeys: String, CodingKey {
        case apiKey, places, slots, trainsPerDirection, cooldownSeconds, refreshSeconds, rideRefreshSeconds, rideMaxMinutes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
        places = (try? c.decode([Place].self, forKey: .places)) ?? AppConfig.defaultPlaces
        slots = (try? c.decode(Int.self, forKey: .slots)) ?? 4
        trainsPerDirection = (try? c.decode(Int.self, forKey: .trainsPerDirection)) ?? 2
        cooldownSeconds = (try? c.decode(Double.self, forKey: .cooldownSeconds)) ?? 300
        refreshSeconds = (try? c.decode(Double.self, forKey: .refreshSeconds)) ?? 5
        rideRefreshSeconds = (try? c.decode(Double.self, forKey: .rideRefreshSeconds)) ?? 15
        rideMaxMinutes = (try? c.decode(Double.self, forKey: .rideMaxMinutes)) ?? 90
    }
}

/// UserDefaults 에 JSON 으로 저장. 바뀌면 지오펜스도 다시 건다.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()
    private let key = "train-live.config"

    @Published var config: AppConfig {
        didSet {
            save()
            LocationMonitor.shared.sync(places: config.places)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = cfg
        } else {
            config = AppConfig()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func place(id: String) -> Place? {
        config.places.first { $0.id.uuidString == id }
    }
}
