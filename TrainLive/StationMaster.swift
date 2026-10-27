import CoreLocation
import Foundation

/// 서울시 역사마스터(subwayStationMaster)의 역 한 줄
struct MasterStation: Codable, Hashable {
    var name: String
    var lineId: String
    var lat: Double
    var lng: Double
}

/// 역 목록 내려받기·보관. 새로고침 버튼이 refresh 를 부른다.
/// 내려받은 이름 중 순서표에 없는 것은 비슷한 이름을 찾아 별칭으로 기억하고, 못 찾은 것은 목록으로 남긴다.
@MainActor
final class StationMaster: ObservableObject {
    static let shared = StationMaster()

    @Published private(set) var stations: [MasterStation] = []
    @Published private(set) var updatedAt: Date?
    /// 순서표에서 못 찾은 역("3호선 OO")
    @Published private(set) var unmatched: [String] = []
    @Published private(set) var learnedCount = 0
    @Published private(set) var loading = false
    @Published private(set) var message = ""

    private struct Saved: Codable {
        var at: Date
        var stations: [MasterStation]
        var learned: [String: String]
    }

    private static let routeToId: [String: String] = [
        "1호선": "1001", "2호선": "1002", "3호선": "1003", "4호선": "1004", "5호선": "1005",
        "6호선": "1006", "7호선": "1007", "8호선": "1008", "9호선": "1009",
        "경의중앙선": "1063", "경의선": "1063", "중앙선": "1063",
        "공항철도": "1065", "공항철도1호선": "1065", "인천공항철도": "1065",
        "경춘선": "1067", "수인분당선": "1075", "분당선": "1075", "수인선": "1075",
        "신분당선": "1077", "경강선": "1081", "우이신설선": "1092", "우이신설경전철": "1092",
        "서해선": "1093", "GTX-A": "1032", "GTX-A선": "1032",
    ]

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stationMaster.json")
    }

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        stations = saved.stations
        updatedAt = saved.at
        StationNames.learned = saved.learned
        learnedCount = saved.learned.count
        unmatched = Self.findUnmatched(saved.stations)
    }

    /// 역 목록을 새로 받는다. 키가 sample 이면 5개만 온다.
    func refresh(apiKey: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "API 키가 없습니다"; return }
        loading = true
        defer { loading = false }
        let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let last = key == "sample" ? 5 : 1000
        guard let url = URL(string: "http://openapi.seoul.go.kr:8088/\(keyEncoded)/json/subwayStationMaster/1/\(last)/") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: req)
            let rows = try Self.parse(data)
            guard !rows.isEmpty else { message = "역 목록 응답이 비었습니다"; return }
            let learned = Self.learn(rows)
            StationNames.learned = learned
            stations = rows
            updatedAt = Date()
            learnedCount = learned.count
            unmatched = Self.findUnmatched(rows)
            message = ""
            let saved = Saved(at: Date(), stations: rows, learned: learned)
            if let out = try? JSONEncoder().encode(saved) { try? out.write(to: fileURL, options: .atomic) }
        } catch {
            message = error.localizedDescription
        }
    }

    private static func parse(_ data: Data) throws -> [MasterStation] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SubwayAPIError.badResponse }
        guard let box = root["subwayStationMaster"] as? [String: Any], let rows = box["row"] as? [[String: Any]] else {
            let r = (root["RESULT"] as? [String: Any]) ?? ((root["subwayStationMaster"] as? [String: Any])?["RESULT"] as? [String: Any])
            throw SubwayAPIError.server((r?["MESSAGE"] as? String) ?? "역 목록 응답이 비었습니다")
        }
        var out: [MasterStation] = []
        for r in rows {
            let name = (r["BLDN_NM"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let route = (r["ROUTE"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard let lineId = routeToId[route], !name.isEmpty else { continue }
            let lat = Double("\(r["LAT"] ?? "")") ?? 0
            let lng = Double("\(r["LOT"] ?? "")") ?? 0
            guard lat != 0, lng != 0 else { continue }
            out.append(MasterStation(name: name, lineId: lineId, lat: lat, lng: lng))
        }
        return out
    }

    private static func orderNames(_ lineId: String) -> Set<String> {
        var s = Set<String>()
        for o in StationOrders.orders[Lines.canonical(lineId)] ?? [] { for n in o.names { s.insert(n) } }
        return s
    }

    /// 순서표에 없는 이름 중 한쪽이 다른 쪽을 포함하는 후보가 하나뿐이면 별칭으로 기억
    private static func learn(_ rows: [MasterStation]) -> [String: String] {
        var learned: [String: String] = [:]
        var cache: [String: Set<String>] = [:]
        for r in rows {
            let names = cache[r.lineId] ?? orderNames(r.lineId)
            cache[r.lineId] = names
            if names.isEmpty { continue }
            let n = StationOrders.normBase(r.name)
            if names.contains(n) || StationNames.alias[n] != nil { continue }
            let hits = names.filter { $0.count >= 2 && n.count >= 2 && ($0.hasPrefix(n) || n.hasPrefix($0)) }
            if hits.count == 1, let h = hits.first { learned[n] = h }
        }
        return learned
    }

    private static func findUnmatched(_ rows: [MasterStation]) -> [String] {
        var out: [String] = []
        var cache: [String: Set<String>] = [:]
        for r in rows {
            let names = cache[r.lineId] ?? orderNames(r.lineId)
            cache[r.lineId] = names
            if names.isEmpty { continue }
            if !names.contains(StationOrders.norm(r.name)) { out.append("\(Lines.info(r.lineId).name) \(r.name)") }
        }
        return out
    }

    /// 가까운 역(이름 기준으로 묶음). 같은 역의 여러 노선은 lineIds 에 모은다.
    func nearest(to loc: CLLocation, limit: Int = 3) -> [(name: String, meters: Double, lineIds: [String])] {
        var best: [String: Double] = [:]
        var lines: [String: [String]] = [:]
        var shown: [String: String] = [:]
        for s in stations {
            let key = StationOrders.norm(s.name)
            let m = loc.distance(from: CLLocation(latitude: s.lat, longitude: s.lng))
            if let b = best[key] { if m < b { best[key] = m } } else { best[key] = m }
            if !(lines[key]?.contains(s.lineId) ?? false) { lines[key, default: []].append(s.lineId) }
            if shown[key] == nil { shown[key] = s.name }
        }
        return best.sorted { $0.value < $1.value }.prefix(limit).map { (shown[$0.key] ?? $0.key, $0.value, lines[$0.key] ?? []) }
    }
}
