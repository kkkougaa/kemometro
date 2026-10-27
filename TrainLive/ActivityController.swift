import ActivityKit
import Foundation
import UIKit

/// 라이브 액티비티 시작·갱신·종료.
///  · 접근 모드(0): 지오펜스 진입/미리보기/환승 → 역에 다가오는 열차를 refreshSeconds 마다 갱신, showSeconds 뒤 종료
///  · 탑승 모드(1): "탑승" 버튼 → 노선 열차 위치 API 로 rideRefreshSeconds 마다 추적, 내릴 역 도착·"하차"·rideMaxMinutes 에 종료
///  · 환승 선택(2·3): "하차" 뒤 그 역의 다른 노선 → 방면 → 접근 모드로 다시
@MainActor
final class ActivityController: ObservableObject {
    static let shared = ActivityController()

    typealias State = TrainActivityAttributes.ContentState

    @Published var log: [String] = []
    private var lastFired: [String: Date] = [:]
    private var running: [String: Activity<TrainActivityAttributes>] = [:]
    private var lastState: [String: State] = [:]
    private var rideTasks: [String: Task<Void, Never>] = [:]
    /// 환승 뒤 쓰는 임시 역(설정의 역과 같은 id)
    private var transient: [String: Place] = [:]
    /// 환승 선택 중 역의 도착 응답(방면 후보 계산용)
    private var transferRows: [String: (station: String, rows: [ArrivalRow])] = [:]
    /// 하차 알림을 받을 역(메인 화면에서 목적지를 정했을 때만 있다)
    private var rideTargets: [String: String] = [:]
    /// 접근 모드에서 사용자가 노선도에서 고른 열차
    private var selected: [String: String] = [:]
    /// 탑승 추적 중인 열차 번호와, 같은 방향 열차의 진행 순서(앞·뒤 열차 변경용)
    private var rideNo: [String: String] = [:]
    private var rideCands: [String: [(no: String, key: Double)]] = [:]
    private var refreshNow = Set<String>()
    private var demoFetchCount = 0
    private var demoRideStep = 0

    private init() {}

    func note(_ s: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(stamp) \(s)", at: 0)
        if log.count > 80 { log.removeLast() }
    }
    private func hhmm(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    private func place(for id: String) -> Place? {
        transient[id] ?? ConfigStore.shared.place(id: id)
    }

    /// 앱이 죽었다 살아날 때 남아 있는 액티비티 정리
    func endLeftovers() async {
        for a in Activity<TrainActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 데모 모드(-demo / TRAINLIVE_DEMO=1): 키 없이 첫 번째 역을 가짜 열차로 띄운다. CI 영상용.
    func startDemoIfNeeded() {
        guard LaunchFlags.demo, let place = ConfigStore.shared.config.places.first else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            await trigger(place: place, reason: "데모", force: true)
        }
    }

    private func attributes(for place: Place, label: String?, cfg: AppConfig) -> TrainActivityAttributes {
        let line = Lines.info(place.lineId)
        let dir = (label?.isEmpty == false) ? label! : place.directionLabel
        return TrainActivityAttributes(
            placeId: place.id.uuidString, stationName: place.name, lineId: line.id, lineName: line.name,
            lineShort: line.short, lineColorHex: line.colorHex, directionLabel: dir, slots: cfg.slots)
    }

    private func content(_ s: State, stale: Date?) -> ActivityContent<State> {
        ActivityContent(state: s, staleDate: stale, relevanceScore: 100)
    }

    private func isRiding(_ placeId: String) -> Bool { rideTasks[placeId] != nil }

    private func endActivity(_ pid: String) async {
        if let a = running[pid] {
            await a.end(nil, dismissalPolicy: .immediate)
            running[pid] = nil
        }
    }

    // MARK: 접근 모드

    func trigger(placeId: String, reason: String, force: Bool = false) async {
        guard let place = place(for: placeId) else { note("모르는 역 id: \(placeId)"); return }
        await trigger(place: place, reason: reason, force: force)
    }

    func trigger(place: Place, reason: String, force: Bool = false) async {
        let cfg = ConfigStore.shared.config
        let pid = place.id.uuidString
        if isRiding(pid) { note("\(place.name): 탑승 추적 중이라 접근 알림은 건너뜀"); return }
        if !force, let last = lastFired[pid], Date().timeIntervalSince(last) < cfg.cooldownSeconds {
            note("\(place.name): \(Int(cfg.cooldownSeconds))초 안에 또 들어와서 건너뜀")
            return
        }
        lastFired[pid] = Date()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            note("라이브 액티비티가 꺼져 있습니다(설정 > kemometro)")
            return
        }

        LocationMonitor.shared.beginKeepAlive()
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        var expired = false
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "train-live") {
            expired = true
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        }
        defer {
            LocationMonitor.shared.endKeepAlive()
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        }

        note("\(place.name) 시작 (\(reason))")
        let endsAt = Date().addingTimeInterval(place.showSeconds)

        // 1) 열차를 화면 밖에 둔 상태로 띄운다 → 시스템 등장 애니메이션 + 선로가 오른쪽에서 그려져 들어온다
        let (label0, trains0, err0) = await fetchApproach(place: place, cfg: cfg)
        let attrs = attributes(for: place, label: label0, cfg: cfg)
        let offscreen = trains0.map { t -> TrainInfo in var c = t; c.n = Double(cfg.slots) + 1.2; return c }
        let state0 = State(trains: offscreen, fetchedAt: Date(), phase: 0, message: err0, endsAt: endsAt)

        let activity: Activity<TrainActivityAttributes>
        do {
            await endActivity(pid)
            activity = try Activity<TrainActivityAttributes>.request(
                attributes: attrs, content: content(state0, stale: endsAt.addingTimeInterval(60)), pushType: nil)
            running[pid] = activity
        } catch {
            note("띄우기 실패: \(error.localizedDescription)")
            return
        }

        // 2) 잠깐 뒤 실제 위치로
        try? await Task.sleep(nanoseconds: 350_000_000)
        var state = State(trains: trains0, fetchedAt: Date(), phase: 1, message: err0, endsAt: endsAt)
        lastState[pid] = state
        await activity.update(content(state, stale: endsAt.addingTimeInterval(60)))

        // 3) refreshSeconds 마다 갱신
        let interval = max(1, cfg.refreshSeconds)
        while Date() < endsAt {
            let remain = endsAt.timeIntervalSinceNow
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, min(interval, remain)) * 1_000_000_000))
            if isRiding(pid) || running[pid] !== activity { note("\(place.name) 접근 루프 종료(전환)"); return }
            if Date() >= endsAt { break }
            if expired {
                await activity.end(content(state, stale: nil), dismissalPolicy: .after(endsAt))
                running[pid] = nil
                note("\(place.name) 백그라운드 만료, \(hhmm(endsAt)) 에 자동 제거")
                return
            }
            let (_, trains, err) = await fetchApproach(place: place, cfg: cfg)
            if err == nil {
                state = State(trains: trains, fetchedAt: Date(), phase: 1, message: nil, endsAt: endsAt)
                // 고른 열차가 아직 보이면 유지, 지나갔으면 가장 가까운 열차로
                if let id = selected[pid], trains.contains(where: { $0.id == id }) { state.selectedId = id } else { selected[pid] = nil }
                lastState[pid] = state
                await activity.update(content(state, stale: endsAt.addingTimeInterval(60)))
            }
        }
        if isRiding(pid) || running[pid] !== activity { return }

        // 4) 치운다
        await activity.end(content(state, stale: nil), dismissalPolicy: .immediate)
        running[pid] = nil
        transient[pid] = nil
        note("\(place.name) 종료")
    }

    private func fetchApproach(place: Place, cfg: AppConfig) async -> (String, [TrainInfo], String?) {
        if LaunchFlags.demo {
            demoFetchCount += 1
            return (DemoData.attributes.directionLabel, demoFetchCount >= 2 ? DemoData.trainsLater : DemoData.trains, nil)
        }
        do {
            let rows = try await SubwayAPI.arrivalsSmart(station: place.apiName.isEmpty ? place.name : place.apiName, apiKey: cfg.apiKey)
            let r = TrainStatus.trains(from: rows, lineId: place.lineId, dest: place.dest, updn: place.updn, limit: cfg.trainsPerDirection)
            return (r.label, r.trains, nil)
        } catch {
            note("조회 실패: \(error.localizedDescription)")
            return ("", [], error.localizedDescription)
        }
    }

    // MARK: 탑승 모드

    /// "탑승" 버튼. trainNo 가 비어 있으면 탑승역에 있는 열차를 고른다.
    func board(placeId: String, trainNo: String) async {
        guard let place = place(for: placeId) else { note("탑승: 모르는 역 id"); return }
        rideTasks[placeId]?.cancel()
        let existing = running[placeId]
        note("\(place.name) 탑승 (열차 \(trainNo.isEmpty ? "자동" : trainNo))")
        rideTasks[placeId] = Task { @MainActor [weak self] in
            await self?.rideLoop(place: place, activity: existing, trainNo: trainNo)
        }
    }

    /// 탑승 중 추적 열차를 앞(+1)·뒤(-1) 열차로 바꾼다
    func shiftTrain(placeId: String, delta: Int) async {
        guard let list = rideCands[placeId], let cur = rideNo[placeId],
              let i = list.firstIndex(where: { SubwayAPI.sameTrain($0.no, cur) }) else { note("열차 변경: 후보 없음"); return }
        let j = i + (delta > 0 ? 1 : -1)
        guard list.indices.contains(j) else { note("열차 변경: 그쪽에 열차 없음"); return }
        rideNo[placeId] = list[j].no
        refreshNow.insert(placeId)
        note("열차 변경 \(list[i].no) → \(list[j].no)")
    }

    /// 노선도의 열차 마커를 눌렀을 때: 그 열차를 탑승 대상으로 표시한다. 같은 열차를 다시 누르면 해제.
    func select(placeId: String, trainId: String) async {
        guard let activity = running[placeId], var state = lastState[placeId], state.mode == 0,
              state.trains.contains(where: { $0.id == trainId }) else { return }
        let next: String? = (state.selected?.id == trainId && selected[placeId] != nil) ? nil : trainId
        selected[placeId] = next
        state.selectedId = next
        lastState[placeId] = state
        await activity.update(content(state, stale: state.endsAt.addingTimeInterval(60)))
        note("열차 선택 \(trainId)")
    }

    /// 메인 화면에서 열차를 골라 추적을 시작한다. target 이 있으면 그 역 2정거장 전·다음 역·도착에 알림을 준다.
    func startTracking(place: Place, trainNo: String, target: String?) async {
        let pid = place.id.uuidString
        transient[pid] = place
        rideTargets[pid] = target
        await board(placeId: pid, trainNo: trainNo)
    }

    /// 하차 알림 문구. 단계 2: 두 정거장 전, 1: 다음 역, 0: 도착
    private func alertConfig(_ stage: Int, target: String) -> AlertConfiguration {
        let body: String
        switch stage {
        case 2: body = "\(target)까지 두 정거장 남았어요"
        case 1: body = "다음 역 \(target)에서 내려요"
        default: body = "\(target)에 도착했어요"
        }
        return AlertConfiguration(title: "하차 알림", body: LocalizedStringResource(stringLiteral: body), sound: .default)
    }

    /// "하차" 버튼: 추적을 멈추고, 그 역에 다른 노선이 있으면 환승을 묻는다
    func endRide(placeId: String) async {
        rideNo[placeId] = nil
        rideCands[placeId] = nil
        rideTargets[placeId] = nil
        selected[placeId] = nil
        rideTasks[placeId]?.cancel()
        rideTasks[placeId] = nil
        guard let place = place(for: placeId), let activity = running[placeId] else { note("하차"); return }
        let station = lastState[placeId]?.ride?.current ?? place.name
        let cfg = ConfigStore.shared.config
        var rows: [ArrivalRow] = []
        if LaunchFlags.demo {
            rows = []
        } else {
            rows = (try? await SubwayAPI.arrivalsSmart(station: station, apiKey: cfg.apiKey)) ?? []
        }
        // 이 역을 지나는 다른 노선(도착 응답의 subwayList)
        var lineIds: [String] = []
        for r in rows {
            for id in r.subwayList.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }) {
                if id != place.lineId, Lines.all.contains(where: { $0.id == id }), !lineIds.contains(id) { lineIds.append(id) }
            }
        }
        if LaunchFlags.demo && station == "신논현" { lineIds = ["1009"] }
        guard !lineIds.isEmpty else {
            await endActivity(placeId)
            transient[placeId] = nil
            note("하차 · \(station) (환승 노선 없음)")
            return
        }
        transferRows[placeId] = (station, rows)
        var state = lastState[placeId] ?? State(trains: [], fetchedAt: Date(), phase: 1, message: nil, endsAt: Date().addingTimeInterval(600))
        state.mode = 2
        state.ride = nil
        state.trains = []
        state.stationName = station
        state.choices = lineIds.map { ChoiceOption(id: $0, title: Lines.info($0).name, lineId: $0) }
        lastState[placeId] = state
        await activity.update(content(state, stale: nil))
        note("하차 · \(station): 환승 \(lineIds.map { Lines.info($0).name }.joined(separator: ", "))")
    }

    /// 환승 노선 선택 → 방면 후보
    func chooseLine(placeId: String, lineId: String) async {
        guard let activity = running[placeId], var state = lastState[placeId] else { return }
        let station = transferRows[placeId]?.station ?? state.stationName ?? ""
        let rows = transferRows[placeId]?.rows ?? []
        var options: [ChoiceOption] = []
        var seen: [String] = []
        for r in rows where r.subwayId == lineId && r.arvlCd != "2" {
            let k = r.updnLine
            if seen.contains(k) { continue }
            seen.append(k)
            let d = TrainStatus.dest(of: r.trainLineNm)
            if lineId == "1002", let t = Lines.loopText(k) {
                // 2호선 순환: 성수행/성수행 대신 내선(시계), 외선(반시계)
                options.append(ChoiceOption(id: k, title: t, lineId: lineId, dest: "", updn: k))
            } else {
                options.append(ChoiceOption(id: k, title: d.full.isEmpty ? k : d.full, lineId: lineId, dest: d.name, updn: k))
            }
        }
        if options.isEmpty {
            if LaunchFlags.demo {
                options = [ChoiceOption(id: "a", title: "중앙보훈병원행", lineId: lineId, dest: "중앙보훈병원", updn: "하행"),
                           ChoiceOption(id: "b", title: "개화행", lineId: lineId, dest: "개화", updn: "상행")]
            } else {
                options = [ChoiceOption(id: "상행", title: "상행", lineId: lineId, dest: "", updn: "상행"),
                           ChoiceOption(id: "하행", title: "하행", lineId: lineId, dest: "", updn: "하행")]
            }
        }
        state.mode = 3
        state.lineId = lineId
        state.stationName = station
        state.choices = options
        lastState[placeId] = state
        await activity.update(content(state, stale: nil))
        note("환승 \(Lines.info(lineId).name) 선택")
    }

    /// 방면 선택 → 그 승강장으로 오는 열차를 접근 모드로 다시
    func chooseDirection(placeId: String, lineId: String, dest: String, updn: String) async {
        guard let base = place(for: placeId) else { return }
        let station = transferRows[placeId]?.station ?? lastState[placeId]?.stationName ?? base.name
        let p = Place(id: base.id, name: station, apiName: station, lineId: lineId, dest: dest, updn: updn,
                      latitude: base.latitude, longitude: base.longitude, radius: base.radius, showSeconds: base.showSeconds,
                      enabled: base.enabled)
        transient[placeId] = p
        transferRows[placeId] = nil
        note("환승 \(Lines.info(lineId).name) \(dest.isEmpty ? updn : dest + "행")")
        await trigger(place: p, reason: "환승", force: true)
    }

    /// "그냥 내림"
    func dismiss(placeId: String) async {
        rideNo[placeId] = nil
        rideCands[placeId] = nil
        rideTargets[placeId] = nil
        selected[placeId] = nil
        rideTasks[placeId]?.cancel()
        rideTasks[placeId] = nil
        transferRows[placeId] = nil
        transient[placeId] = nil
        await endActivity(placeId)
        note("닫음")
    }

    private func rideLoop(place: Place, activity initial: Activity<TrainActivityAttributes>?, trainNo initialNo: String) async {
        let cfg = ConfigStore.shared.config
        let pid = place.id.uuidString
        LocationMonitor.shared.beginKeepAlive()
        defer { LocationMonitor.shared.endKeepAlive(); if rideTasks[pid] != nil, Task.isCancelled == false { rideTasks[pid] = nil } }

        var trainNo = initialNo
        let deadline = Date().addingTimeInterval(cfg.rideMaxMinutes * 60)
        var state = lastState[pid] ?? State(trains: [], fetchedAt: Date(), phase: 1, message: nil, endsAt: deadline)
        state.mode = 1
        state.showRunner = cfg.runnerEnabled
        state.endsAt = deadline
        state.choices = []

        var activity = initial
        if activity == nil {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { note("라이브 액티비티가 꺼져 있습니다"); return }
            do {
                activity = try Activity<TrainActivityAttributes>.request(
                    attributes: attributes(for: place, label: nil, cfg: cfg), content: content(state, stale: nil), pushType: nil)
                running[pid] = activity
            } catch { note("탑승 액티비티 실패: \(error.localizedDescription)"); return }
        }
        guard let activity else { return }

        // 애니메이션 tick 마다 화면을 갱신하고, every 번째 tick 에만 지하철 조회를 겸한다
        // 캐릭터를 끄면 화면 갱신은 지하철 갱신 때만
        let tick = cfg.runnerEnabled ? max(0.5, cfg.animSeconds) : max(1, cfg.rideRefreshSeconds)
        let every = cfg.runnerEnabled ? max(1, Int((cfg.rideRefreshSeconds / tick).rounded())) : 1
        let staleAfter = max(cfg.rideRefreshSeconds, tick) * 3
        var departedKey = ""
        var alerted = Set<Int>()
        var n = 0
        rideNo[pid] = trainNo
        while !Task.isCancelled && Date() < deadline {
            let started = Date()
            let forced = refreshNow.remove(pid) != nil
            if forced { departedKey = "" }
            if n % every == 0 || forced {
                if let want = rideNo[pid], want != trainNo { trainNo = want }
                let (ride, err) = await fetchRide(place: place, cfg: cfg, trainNo: &trainNo)
                if Task.isCancelled { return }
                if var ride {
                    // 출발 상태가 같은 역에서 두 번째로 읽히면 이동 중
                    let key = ride.trainNo + "|" + ride.current
                    if ride.status == 2 {
                        ride.moving = (key == departedKey)
                        departedKey = key
                    } else {
                        departedKey = ""
                    }
                    state.ride = ride
                    state.message = nil
                    state.fetchedAt = Date()
                    rideNo[pid] = trainNo
                } else if let err {
                    state.message = err
                }
            }
            state.frame = (state.frame + 1) % 4
            lastState[pid] = state
            var alert: AlertConfiguration?
            if let target = rideTargets[pid], let r = state.ride, r.pathIndex >= 0 {
                let ti = StationOrders.index(of: target, in: r.path)
                if ti >= 0 {
                    let remain = ti - r.pathIndex
                    let stage = remain <= 0 ? 0 : (remain <= 2 ? remain : 9)
                    if stage < 9, !alerted.contains(stage) {
                        alerted.insert(stage)
                        alert = alertConfig(stage, target: target)
                        note("하차 알림 · \(target) \(stage == 0 ? "도착" : "\(stage)정거장 전")")
                    }
                }
            }
            await activity.update(content(state, stale: state.message == nil ? Date().addingTimeInterval(staleAfter) : nil),
                                  alertConfiguration: alert)
            n += 1
            let wait = max(0.05, tick - Date().timeIntervalSince(started))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        if Task.isCancelled { return }
        await activity.end(content(state, stale: nil), dismissalPolicy: .immediate)
        running[pid] = nil
        transient[pid] = nil
        rideTasks[pid] = nil
        rideTargets[pid] = nil
        rideNo[pid] = nil
        rideCands[pid] = nil
        note("\(place.name) 탑승 추적 종료")
    }

    /// 노선 열차 위치에서 내 열차를 찾아 RideInfo 로. trainNo 를 못 찾으면 탑승역 기준으로 다시 고른다.
    private func fetchRide(place: Place, cfg: AppConfig, trainNo: inout String) async -> (RideInfo?, String?) {
        let line = Lines.info(place.lineId)
        let destName = place.dest
        let path = StationOrders.path(lineId: place.lineId, from: place.name, to: nil, dest: destName, updn: place.updn) ?? []

        if LaunchFlags.demo {
            let r = DemoData.ride(step: demoRideStep)
            demoRideStep += 1
            return (r, nil)
        }

        let rows: [PositionRow]
        do { rows = try await SubwayAPI.positions(lineName: line.name, apiKey: cfg.apiKey) }
        catch { return (nil, error.localizedDescription) }

        let wantUpdn = (place.updn == "상행" || place.updn == "내선") ? "0" : "1"
        var cands = rows.filter { $0.updnLine == wantUpdn }
        if !destName.isEmpty {
            let byDest = cands.filter { StationOrders.norm($0.statnTnm) == StationOrders.norm(destName) }
            if !byDest.isEmpty { cands = byDest }
        }
        if cands.isEmpty { cands = rows }

        var row = cands.first { SubwayAPI.sameTrain($0.trainNo, trainNo) }
        if row == nil {
            if let at = cands.first(where: { StationOrders.norm($0.statnNm) == StationOrders.norm(place.name) }) { row = at }
            else if !path.isEmpty {
                row = cands.filter { StationOrders.index(of: $0.statnNm, in: path) >= 0 }
                    .min { StationOrders.index(of: $0.statnNm, in: path) < StationOrders.index(of: $1.statnNm, in: path) }
            }
            if row == nil { row = cands.first }
            if let r = row { trainNo = r.trainNo; note("열차 \(r.trainNo) 로 추적") }
        }
        guard let r = row else { return (nil, "노선에 열차 정보가 없습니다") }

        // 같은 방향 열차를 진행 순서로 늘어놓는다(앞·뒤 열차 변경용)
        if let ori = StationOrders.oriented(lineId: place.lineId, from: place.name, dest: destName, updn: place.updn) {
            let names = ori.stations.map(StationOrders.norm)
            var list: [(no: String, key: Double)] = []
            for c in cands {
                guard let i = names.firstIndex(of: StationOrders.norm(c.statnNm)) else { continue }
                let st = Int(c.trainSttus) ?? 2
                list.append((c.trainNo, Double(i) + (st == 0 ? -0.25 : (st == 2 ? 0.5 : 0))))
            }
            rideCands[place.id.uuidString] = list.sorted { $0.key < $1.key }
        }

        let status = Int(r.trainSttus) ?? 2
        let idx = StationOrders.index(of: r.statnNm, in: path)
        let next: String? = (idx >= 0 && idx + 1 < path.count) ? path[idx + 1] : nil
        var destLabel = r.statnTnm.isEmpty ? (destName.isEmpty ? "" : destName + "행") : r.statnTnm + "행"
        if place.lineId == "1002", let t = Lines.loopText(place.updn) { destLabel = t }
        var tags: [String] = []
        if r.directAt == "1" { tags.append("급행") } else if r.directAt == "7" { tags.append("특급") }
        if r.lstcarAt == "1" { tags.append("막차") }
        return (RideInfo(trainNo: r.trainNo, current: r.statnNm, status: status, next: next,
                         path: path, pathIndex: idx, dest: destLabel, tags: tags), nil)
    }
}
