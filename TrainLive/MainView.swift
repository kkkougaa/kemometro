import CoreLocation
import SwiftUI

// MARK: 모델

/// 한 방면 카드: 같은 노선·같은 방향의 열차들
struct DirCard: Identifiable {
    let id: String
    let lineId: String
    let updn: String
    let trains: [TrainInfo]
}

struct LineGroup: Identifiable {
    var id: String { lineId }
    let lineId: String
    var cards: [DirCard]
}

@MainActor
final class MainModel: ObservableObject {
    @Published var station = ""
    @Published var meters: Double?
    @Published var groups: [LineGroup] = []
    @Published var message = ""
    @Published var loading = false
    /// 카드마다 고른 열차
    @Published var selection: [String: String] = [:]
    /// 위치 대신 사용자가 고른 역
    @Published var chosenStation: String?

    func refresh(config: AppConfig, location: CLLocation?) async {
        guard let pick = pickStation(config: config, location: location) else {
            message = "가까운 역을 찾지 못했습니다. 설정에서 역 목록을 새로고침하거나 감시할 역을 추가해 주세요."
            return
        }
        station = pick.name
        meters = pick.meters
        if config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            message = "설정에서 실시간 지하철 인증키를 넣어 주세요."
            groups = []
            return
        }
        loading = true
        defer { loading = false }
        do {
            let rows = try await SubwayAPI.arrivalsSmart(station: pick.name, apiKey: config.apiKey)
            groups = Self.group(rows)
            message = groups.isEmpty ? "지금 들어오는 열차가 없습니다" : ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func pickStation(config: AppConfig, location: CLLocation?) -> (name: String, meters: Double?)? {
        if let o = chosenStation { return (o, nil) }
        if let loc = location {
            if let n = StationMaster.shared.nearest(to: loc, limit: 1).first { return (n.name, n.meters) }
            let places = config.places.filter { $0.latitude != 0 }
            if let p = places.min(by: { dist($0, loc) < dist($1, loc) }) { return (p.name, dist(p, loc)) }
        }
        if let p = config.places.first { return (p.name, nil) }
        return nil
    }

    private func dist(_ p: Place, _ loc: CLLocation) -> Double {
        loc.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
    }

    /// 도착정보를 노선 → 방향별 카드로
    static func group(_ rows: [ArrivalRow]) -> [LineGroup] {
        var lineIds: [String] = []
        for r in rows {
            let id = Lines.canonical(r.subwayId)
            if Lines.all.contains(where: { $0.id == id }), !lineIds.contains(id) { lineIds.append(id) }
        }
        let order = Lines.all.map(\.id)
        lineIds.sort { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        var out: [LineGroup] = []
        for lid in lineIds {
            var keys: [String] = []
            for r in rows where Lines.canonical(r.subwayId) == lid && !r.updnLine.isEmpty && !keys.contains(r.updnLine) { keys.append(r.updnLine) }
            var cards: [DirCard] = []
            for k in keys {
                let res = TrainStatus.trains(from: rows, lineId: lid, dest: "", updn: k, limit: 3)
                if res.trains.isEmpty { continue }
                cards.append(DirCard(id: lid + "|" + k, lineId: lid, updn: k, trains: res.trains))
            }
            if !cards.isEmpty { out.append(LineGroup(lineId: lid, cards: cards)) }
        }
        return out
    }
}

// MARK: 메인 화면

struct MainView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var location: LocationMonitor
    @ObservedObject private var master = StationMaster.shared
    @ObservedObject private var appSwitch = AppSwitch.shared
    @StateObject private var model = MainModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var path: [String] = []
    @State private var banner: String?
    @State private var spins = 0

    private var suggestions: [String] { Router.suggestions(query, limit: 8) }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                MainBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        topBar
                        searchField
                        if searchFocused && !query.isEmpty {
                            suggestionList
                        } else {
                            content
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                if let banner {
                    Text(banner)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .liquidGlass()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { to in
                RouteResultView(from: model.station, to: to) { msg in show(msg) }
            }
        }
        .sheet(isPresented: $showSettings) {
            ContentView(showClose: true)
        }
        .onChange(of: scenePhase) { _, phase in
            // 단축어 등으로 앱이 앞으로 올라오면 지금 위치 기준 가까운 역으로 새로 보여 준다
            if phase == .active && appSwitch.current == .metro { refreshOnForeground() }
        }
        .onChange(of: appSwitch.current) { _, now in
            // 번역기에서 넘어오면 바로 새로 받는다
            if now == .metro { refreshOnForeground() }
        }
        .task {
            if master.stations.isEmpty && !store.config.staticKey.isEmpty { await master.refresh(apiKey: store.config.staticKey) }
            location.requestOneShot { _ in }
            while !Task.isCancelled {
                // 번역기가 앞에 있을 땐 쉰다. 뒤에서 도착정보를 계속 받을 이유가 없다.
                if appSwitch.current == .metro {
                    await model.refresh(config: store.config, location: location.lastLocation)
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func refreshOnForeground() {
        model.chosenStation = nil
        location.requestOneShot { loc in
            Task { @MainActor in await model.refresh(config: store.config, location: loc ?? location.lastLocation) }
        }
    }

    private func show(_ msg: String) {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { banner = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeOut(duration: 0.3)) { banner = nil }
        }
    }

    // MARK: 위

    private var topBar: some View {
        HStack {
            Button { refreshNearest() } label: {
                Image("logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                    .rotationEffect(.degrees(Double(spins) * 360))
            }.tapHaptic()
            .buttonStyle(.plain)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .liquidGlass()
            }.tapHaptic()
            .buttonStyle(.plain)
            AppSwitcherButton()
        }
    }

    /// 로고를 누르면 위치를 다시 받아 가까운 역을 새로 찾는다
    private func refreshNearest() {
        withAnimation(.spring(duration: 0.7, bounce: 0.25)) { spins += 1 }
        model.chosenStation = nil
        Task {
            if master.stations.isEmpty && !store.config.staticKey.isEmpty { await master.refresh(apiKey: store.config.staticKey) }
            location.requestOneShot { loc in
                Task { @MainActor in await model.refresh(config: store.config, location: loc ?? location.lastLocation) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tint)
            TextField("어디까지 가시나요?", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { if let first = suggestions.first { pick(first) } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.tapHaptic()
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .padding(.horizontal, 18).frame(height: 56)
        .liquidGlassRect(cornerRadius: 22)
    }

    private func pick(_ name: String) {
        query = ""
        searchFocused = false
        path.append(name)
    }

    /// 입력한 글자가 들어간 역을 드롭다운으로
    private var suggestionList: some View {
        VStack(spacing: 0) {
            if suggestions.isEmpty {
                Text("일치하는 역이 없어요").font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(suggestions.enumerated()), id: \.element) { i, name in
                Button { pick(name) } label: {
                    HStack(spacing: 10) {
                        Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        HStack(spacing: -4) {
                            ForEach(Router.lineIds(of: name).prefix(4), id: \.self) { LineMark(lineId: $0, size: 22) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }.tapHaptic()
                .buttonStyle(.plain)
                if i < suggestions.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .liquidGlassCard(cornerRadius: 24)
    }

    // MARK: 열차 카드

    @ViewBuilder private var content: some View {
        Text(model.station.isEmpty ? "" : "지금 \(model.station)역")
            .font(.system(size: 24, weight: .heavy)).tracking(-0.8)
            .padding(.horizontal, 4)
        if !model.message.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.message).font(.system(size: 15)).foregroundStyle(.secondary)
                if store.config.apiKey.isEmpty {
                    GlassPillButton(title: "설정 열기", systemImage: "gearshape", prominent: true) { showSettings = true }
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: 24)
        }
        ForEach(model.groups) { g in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LineMark(lineId: g.lineId, size: 22)
                    Text(Lines.info(g.lineId).name).font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                ForEach(g.cards) { card in
                    DirectionCardView(
                        card: card,
                        station: model.station,
                        selectedId: Binding(get: { model.selection[card.id] }, set: { model.selection[card.id] = $0 })
                    ) { train in track(card: card, train: train) }
                }
            }
        }
    }

    private func track(card: DirCard, train: TrainInfo) {
        let destName = train.dest.hasSuffix("행") ? String(train.dest.dropLast()) : train.dest
        let loop = card.lineId == "1002" && Lines.loopText(card.updn) != nil
        let place = Place(name: model.station, apiName: model.station, lineId: card.lineId, dest: loop ? "" : destName,
                          updn: card.updn, latitude: location.lastLocation?.coordinate.latitude ?? 0,
                          longitude: location.lastLocation?.coordinate.longitude ?? 0)
        let no = UUID(uuidString: train.id) == nil ? train.id : ""
        Task {
            await ActivityController.shared.startTracking(place: place, trainNo: no, target: nil)
            // 시작에 실패하면 이유를 바로 보여 준다(설정의 기록에도 남는다)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let log = ActivityController.shared.log.prefix(6)
            if let fail = log.first(where: { $0.contains("실패") || $0.contains("꺼져") || $0.contains("모르는") }) {
                show("추적을 시작하지 못했어요 · " + fail.components(separatedBy: " ").dropFirst(2).joined(separator: " "))
            } else {
                show("라이브 액티비티로 추적을 시작했어요")
            }
        }
    }
}

/// 은은한 색 번짐 위에 글래스가 떠 보이게
struct MainBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            Circle().fill(Color.blue.opacity(0.16)).frame(width: 320).blur(radius: 70).offset(x: -110, y: -260)
            Circle().fill(Color.pink.opacity(0.12)).frame(width: 280).blur(radius: 70).offset(x: 130, y: -120)
            Circle().fill(Color.mint.opacity(0.12)).frame(width: 300).blur(radius: 80).offset(x: -90, y: 260)
        }
        .ignoresSafeArea()
    }
}

// MARK: 방면 카드

struct DirectionCardView: View {
    let card: DirCard
    let station: String
    @Binding var selectedId: String?
    let onTrack: (TrainInfo) -> Void

    private var color: Color { Lines.info(card.lineId).color }
    private var live: [TrainInfo] { card.trains.filter { !$0.departed } }
    private var selected: TrainInfo? { card.trains.first { $0.id == selectedId } ?? live.first ?? card.trains.first }

    private var title: String {
        if card.lineId == "1002", let t = Lines.loopText(card.updn) { return t }
        guard let s = selected else { return card.updn }
        return s.dest.isEmpty ? card.updn : s.dest
    }

    private var heroText: String {
        guard let s = selected else { return "–" }
        return s.departed ? "출발" : s.status
    }

    private var heroSub: String {
        guard let s = selected else { return "" }
        if s.departed { return "방금 출발" }
        if s.level == 2 { return "곧 도착" }
        return s.at.isEmpty ? "" : "지금 " + s.at
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.system(size: 19, weight: .heavy)).tracking(-0.6).lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(heroText)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle((selected?.level ?? 0) == 2 ? color : Color.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    Text(heroSub).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                TrackStrip(trains: card.trains, selectedId: selected?.id, station: station, color: color, tags: selected?.tags ?? []) { selectedId = $0 }
                    .frame(height: 80)
                Button {
                    if let s = selected { onTrack(s) }
                } label: {
                    Text("추적")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 38)
                        .liquidGlassRect(cornerRadius: 19, tint: color)
                }.tapHaptic()
                .buttonStyle(.plain)
                .padding(.top, 27)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 26)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: selected?.id)
    }
}

/// 노선도 하나에 열차 여러 대. 열차를 누르면 고른다.
struct TrackStrip: View {
    let trains: [TrainInfo]
    let selectedId: String?
    let station: String
    let color: Color
    let tags: [String]
    let onSelect: (String) -> Void

    private let slots = 4

    private func xOf(_ n: Double, pad: CGFloat, inner: CGFloat) -> CGFloat {
        pad + inner * CGFloat(1 - min(n, Double(slots) + 0.6) / Double(slots))
    }

    private var live: [TrainInfo] { trains.filter { !$0.departed } }
    private var gone: TrainInfo? { trains.first { $0.departed } }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pad: CGFloat = 14
            let extra: CGFloat = gone == nil ? 0 : 28
            let inner = w - pad * 2 - extra
            let y: CGFloat = 46
            let leadN = min(live.first?.n ?? Double(slots) + 0.6, Double(slots) + 0.6)
            let fillW = max(0, inner * CGFloat(1 - leadN / Double(slots)))
            let chosen = trains.first { $0.id == selectedId } ?? live.first

            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: inner, height: 5).position(x: pad + inner / 2, y: y)
                Capsule().fill(LinearGradient(colors: [color.opacity(0.15), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fillW, 5), height: 5).position(x: pad + max(fillW, 5) / 2, y: y)
                    .opacity(fillW > 0 ? 1 : 0)
                ForEach(1...slots, id: \.self) { i in
                    Circle().fill(Color.primary.opacity(0.3)).frame(width: 5, height: 5).position(x: xOf(Double(i), pad: pad, inner: inner), y: y)
                }
                Circle().fill(Color.primary).frame(width: 13, height: 13).position(x: pad + inner, y: y)
                Text(station).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
                    .position(x: pad + inner, y: y + 19)

                ForEach(live.prefix(3)) { t in
                    let n = t.n ?? Double(slots) + 1.3
                    let isSel = t.id == chosen?.id
                    marker(isSel: isSel, dim: false)
                        .opacity(n > Double(slots) + 0.5 ? 0 : 1)
                        .position(x: xOf(n, pad: pad, inner: inner), y: y)
                        .onTapGesture { Haptics.selection(); onSelect(t.id) }
                    if isSel, !t.at.isEmpty, t.n ?? 9 > 1.1 {
                        Text(t.at).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).fixedSize()
                            .position(x: xOf(n, pad: pad, inner: inner), y: y + 30)
                    }
                    if isSel, !tags.isEmpty {
                        let half = TagChips.width(tags) / 2
                        TagChips(tags: tags).position(x: min(max(xOf(n, pad: pad, inner: inner), half), w - half), y: 14)
                    }
                }
                if let g = gone {
                    let gx = pad + inner + extra * 0.78
                    let isSel = g.id == chosen?.id
                    marker(isSel: isSel, dim: true)
                        .position(x: gx, y: y)
                        .onTapGesture { Haptics.selection(); onSelect(g.id) }
                    if isSel, !tags.isEmpty {
                        let half = TagChips.width(tags) / 2
                        TagChips(tags: tags).position(x: min(max(gx, half), w - half), y: 14)
                    }
                }
            }
            .animation(.spring(duration: 0.7, bounce: 0.18), value: live.map { $0.n ?? 0 })
        }
    }

    private func marker(isSel: Bool, dim: Bool) -> some View {
        TrainMarker(color: color, size: isSel ? 32 : 24, ring: isSel ? color : Color.primary.opacity(0.14))
            .opacity(dim && !isSel ? 0.5 : (isSel ? 1 : 0.8))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: 경로 검색 결과

struct ArrivalChoice: Identifiable, Hashable {
    let id: String
    let minutes: String
    let dest: String
    let via: String
    let updn: String
}

struct RouteResultView: View {
    enum Field { case from, to }

    let onStarted: (String) -> Void

    @EnvironmentObject var store: ConfigStore
    @State private var fromName: String
    @State private var toName: String
    @State private var editing: Field?
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: RouteSearch.Outcome?
    @State private var arrivals: [String: [ArrivalChoice]] = [:]
    @State private var picked: [String: String] = [:]
    @State private var alertOff: Set<String> = []
    @State private var startedId: String?
    @State private var loading = true

    init(from: String, to: String, onStarted: @escaping (String) -> Void) {
        self.onStarted = onStarted
        _fromName = State(initialValue: from)
        _toName = State(initialValue: to)
        _loading = State(initialValue: !from.isEmpty && !to.isEmpty)
    }

    private var searchedAt: Date { outcome?.routes.first?.searchedAt ?? Date() }

    private func shown(_ name: String) -> String { name.hasSuffix("역") ? name : name + "역" }

    var body: some View {
        ZStack {
            MainBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if outcome == nil {
                        Text("출발역과 도착역을 모두 고르면 경로를 찾아요")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlassCard(cornerRadius: 24)
                    } else if let o = outcome {
                        if o.routes.isEmpty {
                            Text(o.note.isEmpty ? "경로를 찾지 못했어요" : o.note)
                                .font(.system(size: 15)).foregroundStyle(.secondary)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlassCard(cornerRadius: 24)
                        }
                        ForEach(o.routes) { r in routeCard(r, fewestTransfers: isFewest(r, in: o.routes)) }
                        if !o.note.isEmpty && !o.routes.isEmpty {
                            Text(o.source == "내장 노선표" ? "경로 API를 쓰지 못해 내장 노선표로 계산했어요 · \(o.note)" : o.note)
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if toName.isEmpty || fromName.isEmpty {
                try? await Task.sleep(nanoseconds: 350_000_000)
                begin(toName.isEmpty ? .to : .from)
            }
            await load()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(.primary)
                        .frame(width: 40, height: 40).liquidGlass()
                }.tapHaptic()
                .buttonStyle(.plain)
                VStack(spacing: 0) {
                    stationRow(.from)
                    Divider()
                    stationRow(.to)
                }
                .padding(.horizontal, 14)
                .liquidGlassRect(cornerRadius: 18)
                Button { swapStations() } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                        .frame(width: 40, height: 40).liquidGlass()
                }.tapHaptic()
                .buttonStyle(.plain)
            }
            if editing != nil { suggestionList }
        }
    }

    private func stationRow(_ field: Field) -> some View {
        let isFrom = field == .from
        let name = isFrom ? fromName : toName
        return HStack(spacing: 10) {
            Circle().strokeBorder(isFrom ? Color.green : Color.red, lineWidth: 4).frame(width: 14, height: 14)
            if editing == field {
                TextField(isFrom ? "출발역" : "도착역", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { if let first = Router.suggestions(text, limit: 1).first { choose(first, field) } }
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            } else {
                Button { begin(field) } label: {
                    HStack {
                        Text(name.isEmpty ? (isFrom ? "출발역을 고르세요" : "도착역을 고르세요") : shown(name))
                            .lineLimit(1)
                            .foregroundStyle(name.isEmpty ? Color.secondary : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }.tapHaptic()
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .frame(height: 46)
    }

    private func begin(_ field: Field) {
        editing = field
        text = ""
        focused = true
    }

    private func choose(_ name: String, _ field: Field) {
        if field == .from { fromName = name } else { toName = name }
        editing = nil
        focused = false
        text = ""
        Task { await load() }
    }

    private func swapStations() {
        let f = fromName
        fromName = toName
        toName = f
        editing = nil
        focused = false
        Task { await load() }
    }

    /// 입력한 글자가 들어간 역을 드롭다운으로
    private var suggestionList: some View {
        let names = Router.suggestions(text, limit: 6)
        return VStack(spacing: 0) {
            if text.isEmpty {
                Text("역 이름을 입력해 주세요").font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else if names.isEmpty {
                Text("일치하는 역이 없어요").font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            ForEach(Array(names.enumerated()), id: \.element) { i, name in
                Button { if let f = editing { choose(name, f) } } label: {
                    HStack(spacing: 10) {
                        Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        HStack(spacing: -4) {
                            ForEach(Router.lineIds(of: name).prefix(4), id: \.self) { LineMark(lineId: $0, size: 20) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }.tapHaptic()
                .buttonStyle(.plain)
                if i < names.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .liquidGlassCard(cornerRadius: 22)
    }

    private func isFewest(_ r: Route, in all: [Route]) -> Bool {
        guard all.count > 1, let minT = all.map(\.transfers).min(), all.map(\.transfers).contains(where: { $0 != minT }) else { return false }
        return r.transfers == minT && all.first(where: { $0.transfers == minT })?.id == r.id
    }

    // MARK: 카드

    private func routeCard(_ r: Route, fewestTransfers: Bool) -> some View {
        let leg0 = r.legs.first
        return VStack(alignment: .leading, spacing: 0) {
            if fewestTransfers {
                Text("최소환승").font(.system(size: 13.5, weight: .bold)).foregroundStyle(.blue).padding(.bottom, 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(r.minutes)").font(.system(size: 36, weight: .heavy)).tracking(-1.5)
                Text("분").font(.system(size: 15, weight: .medium))
            }
            Text(metaText(r)).font(.system(size: 14.5)).lineLimit(1).minimumScaleFactor(0.85).padding(.top, 6).padding(.bottom, 14)
            SegmentBar(legs: r.legs).frame(height: 26).padding(.leading, 13).padding(.bottom, 14)
            ForEach(Array(r.legs.enumerated()), id: \.offset) { i, leg in
                legRow(leg, first: i == 0, routeId: r.id)
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle().strokeBorder(Color.secondary, lineWidth: 2.5).frame(width: 12, height: 12)
                    Text("하차").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(width: 112, alignment: .leading)
                Text(shown(toName)).font(.system(size: 16)).lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    if alertOff.contains(r.id) { alertOff.remove(r.id) } else { alertOff.insert(r.id) }
                } label: {
                    Text(alertOff.contains(r.id) ? "알림 끔" : "알림 켬")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(alertOff.contains(r.id) ? Color.secondary : Color.blue)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .liquidGlass(tint: alertOff.contains(r.id) ? nil : Color.blue.opacity(0.25))
                }.tapHaptic()
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            Button {
                Task { await start(r) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tram.fill")
                    Text(startedId == r.id ? "추적 중" : "바로 추적 시작")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(startedId == r.id ? Color.primary : Color.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .liquidGlassRect(cornerRadius: 24, tint: startedId == r.id ? nil : .blue)
            }.tapHaptic()
            .buttonStyle(.plain)
            .disabled(leg0 == nil || !Lines.all.contains { $0.id == leg0?.lineId })
            .padding(.top, 8)
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 26)
    }

    private func metaText(_ r: Route) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        let start = r.searchedAt ?? Date()
        var end = start.addingTimeInterval(Double(r.minutes) * 60)
        if let t = r.legs.last?.arriveTime {
            let parts = t.split(separator: ":").compactMap { Int($0) }
            if parts.count >= 2 {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
                if var d = cal.date(bySettingHour: parts[0] % 24, minute: parts[1], second: parts.count > 2 ? parts[2] : 0, of: start) {
                    if d < start { d = d.addingTimeInterval(86400) }
                    end = d
                }
            }
        }
        var s = "\(f.string(from: start)) - \(f.string(from: end))"
        if let fare = r.fare { s += "  ·  " + (NumberFormatter.localizedString(from: NSNumber(value: fare), number: .decimal)) + "원" }
        s += "  ·  환승 \(r.transfers)회"
        return s
    }

    private func legRow(_ leg: Leg, first: Bool, routeId: String) -> some View {
        let info = Lines.info(leg.lineId)
        let choices = first ? (arrivals[routeId] ?? []) : []
        let sel = picked[routeId] ?? choices.first?.id
        return HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                LineMark(lineId: leg.lineId, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(info.name).font(.system(size: 16, weight: .bold)).foregroundStyle(info.color).lineLimit(1).fixedSize()
                        if leg.express { Text("급행").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 6).frame(height: 16).background(Color(hex: "#E5483C"), in: Capsule()) }
                    }
                    if let t = (leg.loopUpdn ?? (leg.lineId == "1002" ? leg.direction : nil)).flatMap({ Lines.loopText($0) }) {
                        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }
            }
            .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(leg.from + (leg.from.hasSuffix("역") ? "" : "역")).font(.system(size: 16)).lineLimit(1)
                    Spacer(minLength: 6)
                    if first && !choices.isEmpty {
                        Text("실시간").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 3).liquidGlass()
                    }
                }
                ForEach(choices) { c in
                    Button { picked[routeId] = c.id } label: {
                        HStack(spacing: 6) {
                            Text(c.minutes).font(.system(size: 13, weight: .semibold)).foregroundStyle(info.color)
                            Text(c.dest).font(.system(size: 13))
                            Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1, height: 10)
                            Text(c.via).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            if sel == c.id { Text("탑승").font(.system(size: 11, weight: .heavy)).foregroundStyle(info.color) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(sel == c.id ? info.color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.tapHaptic()
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 동작

    private func load() async {
        arrivals = [:]
        picked = [:]
        startedId = nil
        alertOff = []
        guard !fromName.isEmpty, !toName.isEmpty else {
            outcome = nil
            loading = false
            return
        }
        if StationOrders.norm(fromName) == StationOrders.norm(toName) {
            outcome = RouteSearch.Outcome(routes: [], source: "", note: "출발역과 도착역이 같아요")
            loading = false
            return
        }
        loading = true
        let o = await RouteSearch.search(from: fromName, to: toName, key: store.config.staticKey)
        outcome = o
        loading = false
        // 첫 구간 실시간 도착
        var cache: [String: [ArrivalRow]] = [:]
        for r in o.routes {
            guard let leg = r.legs.first, Lines.all.contains(where: { $0.id == leg.lineId }) else { continue }
            if cache[leg.from] == nil {
                cache[leg.from] = (try? await SubwayAPI.arrivalsSmart(station: leg.from, apiKey: store.config.apiKey)) ?? []
            }
            let rows = (cache[leg.from] ?? []).filter {
                Lines.canonical($0.subwayId) == Lines.canonical(leg.lineId) && $0.arvlCd != "2"
                    && leg.serves(dest: TrainStatus.dest(of: $0.trainLineNm).name, updn: $0.updnLine)
            }
            let sorted = rows.map { ($0, TrainStatus.parse($0)) }.sorted { $0.1.order < $1.1.order }.prefix(2)
            arrivals[r.id] = sorted.map { row, st in
                let sec = Int(row.barvlDt) ?? 0
                let minutes = sec > 0 ? "\(max(1, Int((Double(sec) / 60).rounded())))분" : st.text
                let via = (row.trainLineNm.components(separatedBy: " - ").dropFirst().first ?? "").replacingOccurrences(of: "방면", with: " 방면")
                return ArrivalChoice(id: row.btrainNo.isEmpty ? UUID().uuidString : row.btrainNo, minutes: minutes,
                                     dest: TrainStatus.dest(of: row.trainLineNm).full, via: via, updn: row.updnLine)
            }
        }
    }

    private func start(_ r: Route) async {
        guard let leg = r.legs.first else { return }
        let choices = arrivals[r.id] ?? []
        let choice = choices.first { $0.id == (picked[r.id] ?? choices.first?.id) }
        let loop = leg.loopUpdn != nil
        let destName = choice.map { $0.dest.hasSuffix("행") ? String($0.dest.dropLast()) : $0.dest } ?? (leg.terminal ?? "")
        let updn = choice?.updn ?? leg.loopUpdn ?? leg.direction ?? ""
        let place = Place(name: leg.from, apiName: leg.from, lineId: leg.lineId, dest: loop ? "" : destName, updn: updn,
                          latitude: 0, longitude: 0)
        let no = (choice.map { UUID(uuidString: $0.id) == nil ? $0.id : "" }) ?? ""
        let target: String? = alertOff.contains(r.id) ? nil : leg.to
        if no.isEmpty {
            await ActivityController.shared.trigger(place: place, reason: "경로", force: true)
        } else {
            await ActivityController.shared.startTracking(place: place, trainNo: no, target: target)
        }
        startedId = r.id
        onStarted("라이브 액티비티로 추적을 시작했어요" + (target == nil ? "" : " · \(leg.to) 하차 알림 켜짐"))
    }
}

/// 구간 막대: 구간이 바뀌는 선이 다음 노선 아이콘 정중앙에 와서 이음매가 보이지 않는다.
struct SegmentBar: View {
    let legs: [Leg]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, legs.reduce(0) { $0 + $1.minutes })
            let weights = legs.map { max($0.minutes / total, 0.14) }
            let wsum = weights.reduce(0, +)
            let avail = max(0, geo.size.width - 13)
            HStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                    let info = Lines.info(leg.lineId)
                    let last = i == legs.count - 1
                    ZStack(alignment: .leading) {
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: last ? 13 : 0, topTrailing: last ? 13 : 0))
                            .fill(info.color)
                        Text("\(Int(leg.minutes.rounded()))분")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            .padding(.leading, 20)
                    }
                    .frame(width: avail * CGFloat(weights[i] / wsum), height: 26)
                    .overlay(alignment: .leading) { LineMark(lineId: leg.lineId, size: 26).offset(x: -13) }
                }
            }
        }
    }
}
