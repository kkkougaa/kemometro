import Foundation

/// 노선별 역 순서. 열차 위치 API 의 역 ID 는 순서가 아니라서 남은 역 수·다음 역 계산에 이 표를 쓴다.
/// 없는 노선은 "지금 역"만 보여주고 남은 역 수는 생략한다. 필요한 노선은 여기 한 줄씩 추가.
enum StationOrders {
    static let orders: [String: [String]] = [
        // 신분당선 (북 → 남)
        "1077": ["신사", "논현", "신논현", "강남", "양재", "양재시민의숲", "청계산입구", "판교", "정자", "미금", "동천", "수지구청", "성복", "상현", "광교중앙", "광교"],
    ]

    static func norm(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "역", with: "")
    }

    /// 탑승역 → 내릴 역 경로. 종착역(dest)으로 방향을 정한다. 내릴 역이 없으면 종착역까지.
    static func path(lineId: String, from: String, to: String?, dest: String) -> [String]? {
        guard let order = orders[lineId] else { return nil }
        let n = order.map(norm)
        guard let fi = n.firstIndex(of: norm(from)) else { return nil }
        let destName = norm(dest.replacingOccurrences(of: "행", with: ""))
        var toIdx: Int? = to.flatMap { n.firstIndex(of: norm($0)) }
        if toIdx == nil { toIdx = n.firstIndex(of: destName) }
        guard let ti = toIdx, ti != fi else {
            // 방향만이라도: 종착역 쪽 끝까지
            if let di = n.firstIndex(of: destName), di != fi {
                return di > fi ? Array(order[fi...]) : Array(order[...fi].reversed())
            }
            return nil
        }
        return ti > fi ? Array(order[fi...ti]) : Array(order[ti...fi].reversed())
    }

    static func index(of station: String, in path: [String]) -> Int {
        let s = norm(station)
        return path.firstIndex { norm($0) == s } ?? -1
    }
}
