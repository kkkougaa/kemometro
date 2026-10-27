import Foundation

/// 서울시 지하철 실시간 도착정보 명세서의 "역조회시 참조" 이름 규칙.
/// 도착정보 API 는 아래 역을 일반 표기가 아니라 오른쪽 이름으로 조회해야 열차가 나온다.
enum StationNames {
    /// 일반 표기 → API 조회 이름
    static let query: [String: String] = [
        "응암": "응암순환(상선)",
        "공릉": "공릉(서울산업대입구)",
        "춘의": "춘의",
        "남한산성입구": "남한산성입구(성남법원, 검찰청)",
        "대모산입구": "대모산",
        "천호": "천호(풍납토성)",
        "몽촌토성": "몽촌토성(평화의문)",
    ]

    /// 이름 비교용 별칭(괄호와 '역'을 뗀 뒤): API 쪽 이름 → 순서표 쪽 이름
    static let alias: [String: String] = [
        "응암순환": "응암",
        "대모산": "대모산입구",
        "이수": "총신대입구",
    ]

    /// 역 목록을 내려받을 때 기억한 별칭(앱 안에서만 바뀐다)
    nonisolated(unsafe) static var learned: [String: String] = [:]

    /// 조회에 쓸 이름 후보. 명세서 규칙 → 입력 그대로 → '역'을 뗀 이름 순서
    static func queryCandidates(_ station: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !s.isEmpty, !out.contains(s) { out.append(s) } }
        let base = station.trimmingCharacters(in: .whitespaces)
        add(query[base] ?? "")
        add(base)
        if base.hasSuffix("역") { let t = String(base.dropLast()); add(query[t] ?? ""); add(t) }
        return out
    }
}
