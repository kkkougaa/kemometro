import Foundation

/// 서울시 실시간 지하철 도착정보 한 줄
struct ArrivalRow: Decodable {
    var subwayId: String = ""
    var updnLine: String = ""
    var trainLineNm: String = ""
    var statnNm: String = ""
    var btrainSttus: String = ""
    var barvlDt: String = ""
    var btrainNo: String = ""
    var bstatnNm: String = ""
    var recptnDt: String = ""
    var arvlMsg2: String = ""
    var arvlMsg3: String = ""
    var arvlCd: String = ""
    var lstcarAt: String = ""
    /// 이 역을 지나는 노선들 "1002,1009" (환승 후보)
    var subwayList: String = ""

    private enum CodingKeys: String, CodingKey {
        case subwayId, updnLine, trainLineNm, statnNm, btrainSttus, barvlDt, btrainNo, bstatnNm, recptnDt, arvlMsg2, arvlMsg3, arvlCd, lstcarAt, subwayList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subwayId = (try? c.decode(String.self, forKey: .subwayId)) ?? ""
        updnLine = (try? c.decode(String.self, forKey: .updnLine)) ?? ""
        trainLineNm = (try? c.decode(String.self, forKey: .trainLineNm)) ?? ""
        statnNm = (try? c.decode(String.self, forKey: .statnNm)) ?? ""
        btrainSttus = (try? c.decode(String.self, forKey: .btrainSttus)) ?? ""
        barvlDt = (try? c.decode(String.self, forKey: .barvlDt)) ?? ""
        btrainNo = (try? c.decode(String.self, forKey: .btrainNo)) ?? ""
        bstatnNm = (try? c.decode(String.self, forKey: .bstatnNm)) ?? ""
        recptnDt = (try? c.decode(String.self, forKey: .recptnDt)) ?? ""
        arvlMsg2 = (try? c.decode(String.self, forKey: .arvlMsg2)) ?? ""
        arvlMsg3 = (try? c.decode(String.self, forKey: .arvlMsg3)) ?? ""
        arvlCd = (try? c.decode(String.self, forKey: .arvlCd)) ?? ""
        lstcarAt = (try? c.decode(String.self, forKey: .lstcarAt)) ?? ""
        subwayList = (try? c.decode(String.self, forKey: .subwayList)) ?? ""
    }
}

private struct ArrivalResponse: Decodable {
    struct ErrorMessage: Decodable {
        var status: Int?
        var code: String?
        var message: String?
    }
    var errorMessage: ErrorMessage?
    var realtimeArrivalList: [ArrivalRow]?
    // 오류일 때는 최상위에 바로 code/message 가 온다
    var code: String?
    var message: String?
}

enum SubwayAPIError: LocalizedError {
    case noKey
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return "API 키가 없습니다"
        case .server(let m): return m
        case .badResponse: return "응답을 읽지 못했습니다"
        }
    }
}

enum SubwayAPI {
    /// 역명으로 접근 중인 열차 목록. 데이터 없음(INFO-200)은 빈 배열.
    static func arrivals(station: String, apiKey: String) async throws -> [ArrivalRow] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SubwayAPIError.noKey }
        let rows = key == "sample" ? 5 : 60
        let encoded = station.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? station
        let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        guard let url = URL(string: "http://swopenAPI.seoul.go.kr/api/subway/\(keyEncoded)/json/realtimeStationArrival/0/\(rows)/\(encoded)") else {
            throw SubwayAPIError.badResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded: ArrivalResponse
        do {
            decoded = try JSONDecoder().decode(ArrivalResponse.self, from: data)
        } catch {
            throw SubwayAPIError.badResponse
        }
        if let list = decoded.realtimeArrivalList { return list }
        let code = decoded.errorMessage?.code ?? decoded.code ?? ""
        let msg = decoded.errorMessage?.message ?? decoded.message ?? "응답에 열차 목록이 없습니다"
        if code.contains("INFO-200") { return [] }
        throw SubwayAPIError.server(code.isEmpty ? msg : "\(code) \(msg)")
    }

    /// 명세서의 조회 이름 규칙(응암 → 응암순환(상선) 등)과 "서울역" 의 '역' 떼기를 차례로 시도
    static func arrivalsSmart(station: String, apiKey: String) async throws -> [ArrivalRow] {
        var last: [ArrivalRow] = []
        for name in StationNames.queryCandidates(station) {
            let list = try await arrivals(station: name, apiKey: apiKey)
            if !list.isEmpty { return list }
            last = list
        }
        return last
    }
}

// ── 노선별 실시간 열차 위치 ───────────────────────────────────
/// `realtimePosition/0/100/{노선명}` 한 줄
struct PositionRow: Decodable {
    var trainNo: String = ""
    var statnNm: String = ""
    var statnId: String = ""
    /// 0 상행·내선, 1 하행·외선
    var updnLine: String = ""
    /// 0 진입 · 1 도착 · 2 출발
    var trainSttus: String = ""
    var directAt: String = ""
    /// 종착역
    var statnTnm: String = ""
    var lstcarAt: String = ""

    private enum CodingKeys: String, CodingKey { case trainNo, statnNm, statnId, updnLine, trainSttus, directAt, statnTnm, lstcarAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trainNo = (try? c.decode(String.self, forKey: .trainNo)) ?? ""
        statnNm = (try? c.decode(String.self, forKey: .statnNm)) ?? ""
        statnId = (try? c.decode(String.self, forKey: .statnId)) ?? ""
        updnLine = (try? c.decode(String.self, forKey: .updnLine)) ?? ""
        trainSttus = (try? c.decode(String.self, forKey: .trainSttus)) ?? ""
        directAt = (try? c.decode(String.self, forKey: .directAt)) ?? ""
        statnTnm = (try? c.decode(String.self, forKey: .statnTnm)) ?? ""
        lstcarAt = (try? c.decode(String.self, forKey: .lstcarAt)) ?? ""
    }
}

private struct PositionResponse: Decodable {
    struct ErrorMessage: Decodable { var code: String?; var message: String? }
    var errorMessage: ErrorMessage?
    var realtimePositionList: [PositionRow]?
    var code: String?
    var message: String?
}

extension SubwayAPI {
    /// 노선 전체 열차의 현재 역. 데이터 없음은 빈 배열.
    static func positions(lineName: String, apiKey: String) async throws -> [PositionRow] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SubwayAPIError.noKey }
        let rows = key == "sample" ? 5 : 100
        let line = lineName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? lineName
        let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        guard let url = URL(string: "http://swopenAPI.seoul.go.kr/api/subway/\(keyEncoded)/json/realtimePosition/0/\(rows)/\(line)") else {
            throw SubwayAPIError.badResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded: PositionResponse
        do { decoded = try JSONDecoder().decode(PositionResponse.self, from: data) } catch { throw SubwayAPIError.badResponse }
        if let list = decoded.realtimePositionList { return list }
        let code = decoded.errorMessage?.code ?? decoded.code ?? ""
        let msg = decoded.errorMessage?.message ?? decoded.message ?? "응답에 열차 목록이 없습니다"
        if code.contains("INFO-200") { return [] }
        throw SubwayAPIError.server(code.isEmpty ? msg : "\(code) \(msg)")
    }

    /// 열차 번호 비교: 앞의 0 을 떼고 숫자면 숫자로
    static func sameTrain(_ a: String, _ b: String) -> Bool {
        let x = a.trimmingCharacters(in: .whitespaces), y = b.trimmingCharacters(in: .whitespaces)
        if x == y { return true }
        if let i = Int(x), let j = Int(y) { return i == j }
        return x.drop { $0 == "0" } == y.drop { $0 == "0" }
    }
}
