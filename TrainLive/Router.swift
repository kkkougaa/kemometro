import Foundation

/// 한 노선을 타고 가는 구간 하나
struct Leg: Hashable, Identifiable {
    var id: String { lineId + "|" + from + "|" + to }
    let lineId: String
    /// 탑승역부터 하차역까지 표시용 역 이름
    let stations: [String]
    let minutes: Double
    /// 2호선 순환이면 "내선"/"외선"
    let loopUpdn: String?
    /// 이 방향으로 가는 열차의 종착역 후보(하차역 이후 역, 정규화된 이름)
    let beyond: Set<String>
    /// 경로 API 가 알려 준 값(내장 계산이면 비어 있다)
    var direction: String? = nil
    var terminal: String? = nil
    var express: Bool = false
    var departTime: String? = nil
    var arriveTime: String? = nil
    var trainNo: String? = nil
    var lineName: String? = nil

    var from: String { stations.first ?? "" }
    var to: String { stations.last ?? "" }
    var count: Int { max(0, stations.count - 1) }

    /// 도착정보의 종착역("신사")·방향이 이 구간에 맞는지
    func serves(dest: String, updn: String) -> Bool {
        if let loopUpdn { return updn == loopUpdn }
        let d = StationOrders.norm(dest.replacingOccurrences(of: "행", with: ""))
        if !beyond.isEmpty { return d.isEmpty || beyond.contains(d) }
        if let direction { return updn.isEmpty || updn == direction }
        return true
    }
}

/// 길찾기 결과 한 가지
struct Route: Hashable, Identifiable {
    let legs: [Leg]
    /// 공공데이터 API 가 알려 준 총 소요시간(분). 없으면 역 사이 평균으로 계산한 값을 쓴다
    var apiMinutes: Int? = nil
    /// 경로 API 가 알려 준 카드 요금(원)·총 거리(m)·검색 시각
    var fare: Int? = nil
    var distance: Int? = nil
    var searchedAt: Date? = nil
    var id: String { legs.map(\.id).joined(separator: ">") }
    var transfers: Int { max(0, legs.count - 1) }
    var minutes: Int {
        if let apiMinutes { return apiMinutes }
        var m = legs.reduce(0) { $0 + $1.minutes }
        for (a, b) in zip(legs, legs.dropFirst()) { m += a.lineId == b.lineId ? Router.branchChange : Router.transfer }
        return Int(m.rounded())
    }
}

/// 내장 순서표 위에서 도는 길찾기. 소요 시간은 역 사이 평균과 환승 시간으로 잡은 대략값이다.
/// 노선 안에서 갈라지는 구간은 줄(variant)마다 다른 노선처럼 다루고, 줄을 바꿀 때만 환승 시간을 더한다.
enum Router {
    static let transfer = 5.0
    static let branchChange = 3.0
    private static let hop: [String: Double] = ["1032": 5, "1081": 4, "1065": 3, "1077": 2.5, "1093": 3, "1063": 2.5]
    static func hopMinutes(_ lineId: String) -> Double { hop[lineId] ?? 2.2 }

    private struct Node: Hashable {
        let lineId: String
        let variant: Int
        let name: String
    }

    private struct Graph {
        var adj: [Node: [Node]] = [:]
        var byName: [String: [Node]] = [:]
        var shown: [String: String] = [:]
        var variantNodes: [Node: [String]] = [:]
    }

    private static let graph: Graph = {
        var g = Graph()
        func link(_ a: Node, _ b: Node) {
            if a == b { return }
            g.adj[a, default: []].append(b)
            g.adj[b, default: []].append(a)
        }
        for (lineId, orders) in StationOrders.orders {
            for (vi, o) in orders.enumerated() {
                let names = o.names
                for (i, st) in o.stations.enumerated() {
                    let n = Node(lineId: lineId, variant: vi, name: names[i])
                    if g.adj[n] == nil { g.adj[n] = [] }
                    if !(g.byName[names[i]]?.contains(n) ?? false) { g.byName[names[i], default: []].append(n) }
                    if g.shown[names[i]] == nil { g.shown[names[i]] = st }
                }
                for i in 0..<max(0, names.count - 1) {
                    link(Node(lineId: lineId, variant: vi, name: names[i]), Node(lineId: lineId, variant: vi, name: names[i + 1]))
                }
                if o.kind != .line, names.count > 2 {
                    link(Node(lineId: lineId, variant: vi, name: names[names.count - 1]), Node(lineId: lineId, variant: vi, name: names[0]))
                }
            }
        }
        return g
    }()

    /// 입력한 역 이름이 순서표에 있는지
    static func knows(_ station: String) -> Bool { graph.byName[StationOrders.norm(station)] != nil }

    /// 그 역을 지나는 노선(앱 노선 순서)
    static func lineIds(of station: String) -> [String] {
        var ids: [String] = []
        for n in graph.byName[StationOrders.norm(station)] ?? [] where !ids.contains(n.lineId) { ids.append(n.lineId) }
        let order = Lines.all.map(\.id)
        return ids.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }

    /// 이름 앞부분·포함으로 고른 역 후보(자동완성용)
    static func suggestions(_ text: String, limit: Int = 8) -> [String] {
        let q = StationOrders.normBase(text)
        guard !q.isEmpty else { return [] }
        let all = graph.shown.values.sorted()
        let starts = all.filter { StationOrders.normBase($0).hasPrefix(q) }
        let contains = all.filter { !StationOrders.normBase($0).hasPrefix(q) && StationOrders.normBase($0).contains(q) }
        return Array((starts + contains).prefix(limit))
    }

    /// 출발역에서 도착역까지 가능한 경로를 빠른 순으로 최대 limit 가지
    static func routes(from: String, to: String, limit: Int = 3) -> [Route] {
        let a = StationOrders.norm(from), b = StationOrders.norm(to)
        guard a != b, graph.byName[a] != nil, graph.byName[b] != nil else { return [] }
        var out: [Route] = []
        var seen = Set<String>()
        for penalty in [0.0, 6.0, 14.0] {
            guard let path = search(a, b, penalty) else { continue }
            let legs = makeLegs(path)
            guard !legs.isEmpty else { continue }
            let r = Route(legs: legs)
            if seen.insert(r.id).inserted { out.append(r) }
        }
        return Array(out.sorted { $0.minutes < $1.minutes }.prefix(limit))
    }

    /// 역 순서(공공데이터 API 응답)를 내장 노선표에 대어 구간·환승을 다시 만든다. 이웃하지 않은 역이 끼면 nil.
    static func route(through names: [String]) -> Route? {
        let ns = names.map(StationOrders.norm)
        guard ns.count >= 2 else { return nil }
        var path: [Node] = []
        var cur: Node?
        for i in 0..<(ns.count - 1) {
            let a = ns[i], b = ns[i + 1]
            if a == b { continue }
            let cands = (graph.byName[a] ?? []).filter { n in
                (graph.adj[n] ?? []).contains { $0.name == b && $0.lineId == n.lineId && $0.variant == n.variant }
            }
            guard !cands.isEmpty else { return nil }
            let pick = cands.first { c in cur.map { $0.lineId == c.lineId && $0.variant == c.variant } ?? false }
                ?? cands.first { c in cur.map { $0.lineId == c.lineId } ?? false }
                ?? cands[0]
            if path.last != pick { path.append(pick) }
            let next = Node(lineId: pick.lineId, variant: pick.variant, name: b)
            path.append(next)
            cur = next
        }
        let legs = makeLegs(path)
        return legs.isEmpty ? nil : Route(legs: legs)
    }

    private static func search(_ src: String, _ dst: String, _ penalty: Double) -> [Node]? {
        var dist: [Node: Double] = [:]
        var prev: [Node: Node] = [:]
        var frontier: [Node] = []
        var done = Set<Node>()
        for n in graph.byName[src] ?? [] { dist[n] = 0; frontier.append(n) }
        var goal: Node?
        while !frontier.isEmpty {
            var bi = 0
            for i in 1..<max(1, frontier.count) where dist[frontier[i]]! < dist[frontier[bi]]! { bi = i }
            let u = frontier.remove(at: bi)
            if done.contains(u) { continue }
            done.insert(u)
            if u.name == dst { goal = u; break }
            let d = dist[u]!
            func relax(_ v: Node, _ w: Double) {
                if done.contains(v) { return }
                if d + w < (dist[v] ?? .infinity) {
                    dist[v] = d + w
                    prev[v] = u
                    frontier.append(v)
                }
            }
            for v in graph.adj[u] ?? [] { relax(v, hopMinutes(u.lineId)) }
            for v in graph.byName[u.name] ?? [] where v != u {
                relax(v, (v.lineId == u.lineId ? branchChange : transfer) + penalty)
            }
        }
        guard var cur = goal else { return nil }
        var path = [cur]
        while let p = prev[cur] { path.append(p); cur = p }
        return path.reversed()
    }

    private static func makeLegs(_ path: [Node]) -> [Leg] {
        var groups: [[Node]] = []
        for n in path {
            if let last = groups.last?.last, last.lineId == n.lineId, last.variant == n.variant, last.name != n.name {
                groups[groups.count - 1].append(n)
            } else {
                groups.append([n])
            }
        }
        return groups.filter { $0.count > 1 }.compactMap { g -> Leg? in
            guard let first = g.first, let last = g.last,
                  let order = StationOrders.orders[first.lineId]?[first.variant] else { return nil }
            let names = order.names
            guard let fi = names.firstIndex(of: first.name), let ti = names.firstIndex(of: last.name) else { return nil }
            let shown = g.map { graph.shown[$0.name] ?? $0.name }
            var loopUpdn: String?
            var beyond = Set<String>()
            if order.kind == .line {
                if ti > fi { beyond = Set(names[ti...]) } else { beyond = Set(names[...ti]) }
            } else if order.kind == .loop {
                loopUpdn = g.count > 1 && g[1].name == names[(fi + 1) % names.count] ? "내선" : "외선"
            } else {
                beyond = Set(names)
            }
            return Leg(lineId: first.lineId, stations: shown, minutes: Double(g.count - 1) * hopMinutes(first.lineId),
                       loopUpdn: loopUpdn, beyond: beyond)
        }
    }
}
