import Foundation

/// arvlMsg2 / arvlCd 를 짧은 상태로. Scriptable 위젯의 statusOf 와 같은 규칙.
struct ParsedStatus {
    var text: String
    var level: Int
    var order: Double
    var n: Double?
    var approx: Bool = false
}

enum TrainStatus {
    private static let nthRegex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]\\s*번째\\s*전역")

    static func parse(_ r: ArrivalRow) -> ParsedStatus {
        let msg = r.arvlMsg2
        switch r.arvlCd {
        case "1": return ParsedStatus(text: "도착", level: 2, order: 0, n: 0)
        case "0": return ParsedStatus(text: "진입", level: 2, order: 1, n: 0.15)
        case "5": return ParsedStatus(text: "전역", level: 1, order: 2, n: 1)
        case "4": return ParsedStatus(text: "전역", level: 1, order: 3, n: 1.15)
        case "3": return ParsedStatus(text: "전역 출발", level: 1, order: 4, n: 0.6)
        default: break
        }
        if let m = nthRegex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)),
           let range = Range(m.range(at: 1), in: msg),
           let n = Int(msg[range]) {
            return ParsedStatus(text: n <= 1 ? "전역" : "\(n)역 전", level: n <= 1 ? 1 : 0, order: 10 + Double(n), n: Double(n))
        }
        if let sec = Int(r.barvlDt), sec > 0 {
            let text = sec < 60 ? "곧 도착" : "\(Int((Double(sec) / 60).rounded()))분 후"
            return ParsedStatus(text: text, level: sec < 90 ? 1 : 0, order: 10 + Double(sec) / 90, n: max(0.3, Double(sec) / 90), approx: true)
        }
        var plain = msg
        if let open = plain.firstIndex(of: "("), let close = plain.lastIndex(of: ")"), open < close {
            plain.removeSubrange(open...close)
        }
        plain = plain.trimmingCharacters(in: .whitespaces)
        return ParsedStatus(text: plain.isEmpty ? "운행 중" : plain, level: 0, order: 99, n: nil)
    }

    /// "성수행 - 신촌방면" → ("성수행", "성수")
    static func dest(of lineNm: String) -> (full: String, name: String) {
        let first = lineNm.components(separatedBy: " - ").first ?? lineNm
        var d = first.trimmingCharacters(in: .whitespaces)
        if let open = d.firstIndex(of: "(") { d = String(d[..<open]).trimmingCharacters(in: .whitespaces) }
        let name = d.hasSuffix("행") ? String(d.dropLast()) : d
        return (d, name)
    }

    static func tags(of r: ArrivalRow) -> [String] {
        var t: [String] = []
        if r.btrainSttus.contains("급행") { t.append("급행") }
        else if r.btrainSttus.uppercased().contains("ITX") { t.append("ITX") }
        if r.lstcarAt == "1" { t.append("막차") }
        return t
    }

    /// 노선·방면으로 거르고 가까운 순으로 정렬한 열차 목록과 방면 라벨.
    /// dest 종착역이 맞는 열차가 있으면 그쪽, 없으면 updn 키로.
    static func trains(from rows: [ArrivalRow], lineId: String, dest: String, updn: String, limit: Int) -> (label: String, trains: [TrainInfo]) {
        let usable = rows.filter { $0.subwayId == lineId && $0.arvlCd != "2" }
        // 방향별로 묶기
        var byDir: [String: [ArrivalRow]] = [:]
        var order: [String] = []
        var seen = Set<String>()
        for r in usable {
            let k = r.updnLine.isEmpty ? "?" : r.updnLine
            let dup = k + "|" + r.btrainNo
            if !r.btrainNo.isEmpty {
                if seen.contains(dup) { continue }
                seen.insert(dup)
            }
            if byDir[k] == nil { byDir[k] = []; order.append(k) }
            byDir[k]?.append(r)
        }
        func matchesDest(_ r: ArrivalRow) -> Bool {
            guard !dest.isEmpty else { return false }
            let d = TrainStatus.dest(of: r.trainLineNm)
            return d.name == dest || d.full.hasPrefix(dest)
        }
        var picked: String? = order.first { byDir[$0]?.contains(where: matchesDest) ?? false }
        if picked == nil, !updn.isEmpty { picked = order.first { $0 == updn } }
        if picked == nil, dest.isEmpty, updn.isEmpty { picked = order.first }
        let label = dest.isEmpty ? (picked ?? updn) : dest + " 방면"
        guard let key = picked, let group = byDir[key] else { return (label, []) }

        let infos: [TrainInfo] = group.map { r in
            let s = parse(r)
            let d = TrainStatus.dest(of: r.trainLineNm)
            return TrainInfo(
                id: r.btrainNo.isEmpty ? UUID().uuidString : r.btrainNo,
                status: s.text,
                n: s.n,
                level: s.level,
                dest: d.full,
                at: s.level == 2 ? "" : r.arvlMsg3,
                tags: tags(of: r),
                approx: s.approx
            )
        }
        let sorted = zip(group.map(parse), infos).sorted { $0.0.order < $1.0.order }.map { $0.1 }
        return (label, Array(sorted.prefix(max(1, limit))))
    }
}
