import Foundation

/// 서울 열린데이터광장 "서울시 교통공사 지하철역 최단경로이동정보 현황"(getShtrmPath).
/// 도착정보와 같은 서울 열린데이터광장 인증키를 쓴다. 응답은 header/body 구조이고
/// body.paths 에 역 구간이 순서대로 들어 있다(trsitYn 이 Y 인 줄은 환승 이동).
enum RouteAPI {
    enum Kind: String, CaseIterable {
        case duration, transfer, distance
    }

    /// 마지막 응답 앞부분(설정 화면에서 보여 준다)
    nonisolated(unsafe) static var lastRaw = ""

    static func fetch(from: String, to: String, kind: Kind, key: String, at date: Date = Date()) async throws -> Route {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { throw SubwayAPIError.noKey }
        var lastError: Error = SubwayAPIError.badResponse
        for (a, b) in nameVariants(from, to) {
            do {
                return try await request(from: a, to: b, kind: kind, key: k, at: date)
            } catch SubwayAPIError.server(let msg) where msg.contains("존재하지") {
                lastError = SubwayAPIError.server(msg)
            }
        }
        throw lastError
    }

    /// 역 이름 표기 후보: 입력 그대로 → '역'을 뗀/붙인 것 ("서울역"은 역이 붙은 이름이 맞고 "판교역"은 틀린 이름이다)
    private static func nameVariants(_ a: String, _ b: String) -> [(String, String)] {
        func alt(_ s: String) -> String { s.hasSuffix("역") ? String(s.dropLast()) : s + "역" }
        return [(a, b), (alt(a), b), (a, alt(b)), (alt(a), alt(b))]
    }

    private static func request(from: String, to: String, kind: Kind, key: String, at date: Date) async throws -> Route {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func p(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s }
        let last = key == "sample" ? 5 : 1000
        let urlString = "http://openapi.seoul.go.kr:8088/\(p(key))/json/getShtrmPath/1/\(last)/\(p(from))/\(p(to))/\(p(f.string(from: date)))/\(kind.rawValue)"
        guard let url = URL(string: urlString) else { throw SubwayAPIError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        lastRaw = String(String(data: data, encoding: .utf8)?.prefix(1500) ?? "")
        return try parse(data, searchedAt: date)
    }

    // MARK: 읽기

    private static func int(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func str(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    /// "HH:mm:ss" → 초(자정 넘김은 호출 쪽에서 처리)
    private static func seconds(_ t: String?) -> Int? {
        guard let t else { return nil }
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + (parts.count > 2 ? parts[2] : 0)
    }

    private static let extraLineIds: [String: String] = [
        "경의선": "1063", "중앙선": "1063", "경의·중앙선": "1063",
        "공항철도1호선": "1065", "인천공항철도": "1065", "공항철도 1호선": "1065",
        "수인선": "1075", "분당선": "1075", "수인·분당선": "1075",
        "수도권 광역급행철도 A노선": "1032", "GTX-A선": "1032", "A노선": "1032",
    ]

    static func lineId(for name: String) -> String {
        if let l = Lines.all.first(where: { $0.name == name }) { return l.id }
        if let id = extraLineIds[name] { return id }
        return "x:" + name
    }

    static func parse(_ data: Data, searchedAt: Date = Date()) throws -> Route {
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let first = text.first(where: { !$0.isWhitespace }), first == "{" else {
            throw SubwayAPIError.server(xmlMessage(text))
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SubwayAPIError.badResponse }
        let header = root["header"] as? [String: Any]
        let code = "\(header?["resultCode"] ?? "")"
        if code != "00" { throw SubwayAPIError.server(str(header?["resultMsg"]) ?? "오류 \(code)") }
        guard let body = root["body"] as? [String: Any], let paths = body["paths"] as? [[String: Any]], !paths.isEmpty else {
            throw SubwayAPIError.badResponse
        }

        struct Draft {
            var lineName: String
            var stations: [String]
            var sec = 0
            var direction: String?
            var terminal: String?
            var express = false
            var dep: String?
            var arr: String?
            var trainNo: String?
        }
        var drafts: [Draft] = []
        var cur: Draft?
        for row in paths {
            let dep = row["dptreStn"] as? [String: Any]
            let arv = row["arvlStn"] as? [String: Any]
            if str(row["trsitYn"]) == "Y" {
                if let c = cur { drafts.append(c); cur = nil }
                continue
            }
            guard let depName = str(dep?["stnNm"]), let arvName = str(arv?["stnNm"]) else { continue }
            let line = str(dep?["lineNm"]) ?? ""
            if cur == nil || cur?.lineName != line {
                if let c = cur { drafts.append(c) }
                cur = Draft(lineName: line, stations: [depName], direction: str(row["upbdnbSe"]), terminal: str(row["tmnlStnNm"]),
                            express: false, dep: str(row["trainDptreTm"]), arr: nil, trainNo: str(row["trainno"]))
            }
            cur?.stations.append(arvName)
            cur?.sec += int(row["reqHr"]) ?? 0
            cur?.arr = str(row["trainArvlTm"]) ?? cur?.arr
            if str(row["etrnYn"]) == "Y" { cur?.express = true }
        }
        if let c = cur { drafts.append(c) }
        guard !drafts.isEmpty else { throw SubwayAPIError.badResponse }

        var legs: [Leg] = []
        for d in drafts {
            let lid = lineId(for: d.lineName)
            var minutes = Double(d.sec) / 60
            if let a = seconds(d.dep), var b = seconds(d.arr) {
                if b < a { b += 86400 }
                minutes = Double(b - a) / 60
            }
            var loop: String?
            var beyond = Set<String>()
            if let term = d.terminal { beyond.insert(StationOrders.norm(term)) }
            if let orders = StationOrders.orders[Lines.canonical(lid)], let from = d.stations.first, let to = d.stations.last {
                let f = StationOrders.norm(from), t = StationOrders.norm(to)
                for o in orders {
                    let names = o.names
                    guard let fi = names.firstIndex(of: f), let ti = names.firstIndex(of: t), fi != ti else { continue }
                    if o.kind == .line {
                        if ti > fi { beyond.formUnion(names[ti...]) } else { beyond.formUnion(names[...ti]) }
                    } else if d.direction == "내선" || d.direction == "외선" {
                        loop = d.direction
                    }
                    break
                }
            }
            if loop != nil { beyond = [] }
            legs.append(Leg(lineId: lid, stations: d.stations, minutes: minutes, loopUpdn: loop, beyond: beyond,
                            direction: d.direction, terminal: d.terminal, express: d.express,
                            departTime: d.dep, arriveTime: d.arr, trainNo: d.trainNo, lineName: d.lineName))
        }
        var route = Route(legs: legs)
        if let s = int(body["totalReqHr"]) { route.apiMinutes = Int((Double(s) / 60).rounded()) }
        route.fare = int(body["totalCardCrg"])
        route.distance = int(body["totalDstc"])
        route.searchedAt = searchedAt
        return route
    }

    /// 키 오류 등은 XML(<RESULT><CODE>…)로 온다
    private static func xmlMessage(_ s: String) -> String {
        var code = "", msg = ""
        if let a = s.range(of: "<CODE>"), let b = s.range(of: "</CODE>"), a.upperBound < b.lowerBound { code = String(s[a.upperBound..<b.lowerBound]) }
        if let a = s.range(of: "<MESSAGE>"), let b = s.range(of: "</MESSAGE>"), a.upperBound < b.lowerBound {
            msg = String(s[a.upperBound..<b.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let out = [code, msg].filter { !$0.isEmpty }.joined(separator: " ")
        return out.isEmpty ? (s.isEmpty ? "응답이 비었습니다" : String(s.prefix(120))) : out
    }
}

/// 경로 검색: 경로 API 로 세 가지(최소 시간·최소 환승·최단 거리)를 받아 합치고,
/// 키가 없거나 못 받으면 내장 노선표로 계산한다.
enum RouteSearch {
    struct Outcome {
        var routes: [Route]
        /// "경로 API" 또는 "내장 노선표"
        var source: String
        var note: String
    }

    static func search(from: String, to: String, key: String) async -> Outcome {
        var note = ""
        if !key.trimmingCharacters(in: .whitespaces).isEmpty {
            var found: [Route] = []
            var seen = Set<String>()
            for kind in RouteAPI.Kind.allCases {
                do {
                    let r = try await RouteAPI.fetch(from: from, to: to, kind: kind, key: key)
                    if seen.insert(r.id).inserted { found.append(r) }
                } catch {
                    if note.isEmpty { note = error.localizedDescription }
                }
            }
            if !found.isEmpty { return Outcome(routes: found.sorted { $0.minutes < $1.minutes }, source: "경로 API", note: "") }
        } else {
            note = "API 키가 없습니다"
        }
        return Outcome(routes: Router.routes(from: from, to: to), source: "내장 노선표", note: note)
    }
}
