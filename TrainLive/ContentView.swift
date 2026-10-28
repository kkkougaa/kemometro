import ActivityKit
import CoreLocation
import SwiftUI

struct ContentView: View {
    /// 메인 화면에서 시트로 열 때 닫기 버튼을 보인다
    var showClose = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var location: LocationMonitor
    @EnvironmentObject var controller: ActivityController
    @ObservedObject private var master = StationMaster.shared
    @State private var showLog = false
    @State private var routeTesting = false
    @State private var routeTestMessage = ""
    @State private var routeRaw = ""
    @State private var path: [String] = LaunchFlags.preview ? ["preview"] : []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    SecureField("실시간 지하철 인증키", text: $store.config.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("일반 인증키", text: $store.config.generalKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await testRouteAPI() }
                    } label: {
                        HStack {
                            Label("경로 API 확인", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            Spacer()
                            if routeTesting { ProgressView() }
                        }
                    }.tapHaptic()
                    .disabled(routeTesting || store.config.staticKey.isEmpty)
                    if !routeTestMessage.isEmpty {
                        Text(routeTestMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if !routeRaw.isEmpty {
                        DisclosureGroup("응답 원문") {
                            Text(routeRaw).font(.caption2.monospaced()).textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("API 키")
                }

                Section("역 목록") {
                    Button {
                        Task { await master.refresh(apiKey: store.config.staticKey) }
                    } label: {
                        HStack {
                            Label("새로고침", systemImage: "arrow.clockwise")
                            Spacer()
                            if master.loading { ProgressView() }
                        }
                    }.tapHaptic()
                    .disabled(master.loading || store.config.staticKey.isEmpty)
                    LabeledContent("받은 역") {
                        Text(master.stations.isEmpty ? "없음" : "\(master.stations.count)개 · " + (master.updatedAt?.formatted(date: .abbreviated, time: .omitted) ?? ""))
                    }
                    if master.learnedCount > 0 {
                        LabeledContent("이름 맞춤") { Text("\(master.learnedCount)개") }
                    }
                    if !master.unmatched.isEmpty {
                        DisclosureGroup("순서표에 없는 역 \(master.unmatched.count)개") {
                            ForEach(master.unmatched, id: \.self) { Text($0).font(.caption) }
                        }
                    }
                    if !master.message.isEmpty { Text(master.message).font(.caption).foregroundStyle(.red) }
                }

                Section {
                    ForEach($store.config.places) { $place in
                        NavigationLink {
                            PlaceEditorView(place: $place)
                        } label: {
                            PlaceRow(place: place)
                        }.tapHaptic()
                    }
                    .onDelete { store.config.places.remove(atOffsets: $0) }
                    .onMove { store.config.places.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        var p = Place(name: "", apiName: "", lineId: "1002", dest: "", updn: "상행",
                                      latitude: location.lastLocation?.coordinate.latitude ?? 37.5665,
                                      longitude: location.lastLocation?.coordinate.longitude ?? 126.9780)
                        p.name = "새 역"
                        store.config.places.append(p)
                    } label: {
                        Label("역 추가", systemImage: "plus")
                    }.tapHaptic()
                } header: {
                    Text("감시할 역")
                }

                Section("단축어 자동화") {
                    Button {
                        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                    } label: {
                        Label("단축어 앱 열기", systemImage: "arrow.up.forward.app")
                    }.tapHaptic()
                    DisclosureGroup("설정 방법") {
                        Text("1. 단축어 앱 → 자동화 → 새 자동화 → 도착")
                        Text("2. 위치에서 역을 고르고 \"즉시 실행\"")
                        Text("3. 동작 추가 → kemometro → \"역 열차 추적 시작\" → 감시할 역 선택")
                        Text("안 뜨면 \"(앱 열기)\" 동작으로 바꾸거나 \"앱 열기 → kemometro\"")
                    }
                    .font(.footnote)
                }

                Section("권한") {
                    HStack {
                        Text("위치")
                        Spacer()
                        Text(authText).foregroundStyle(location.authorization == .authorizedAlways ? .green : .orange)
                    }
                    if location.authorization != .authorizedAlways {
                        Button("위치 권한 요청") { location.requestAlways() }.tapHaptic()
                        Button("설정 앱에서 \"항상\"으로 바꾸기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.tapHaptic()
                    }
                    HStack {
                        Text("라이브 액티비티")
                        Spacer()
                        Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "켜짐" : "꺼짐")
                            .foregroundStyle(ActivityAuthorizationInfo().areActivitiesEnabled ? .green : .orange)
                    }
                    HStack {
                        Text("지오펜스")
                        Spacer()
                        Text("\(location.manager.monitoredRegions.count)개").foregroundStyle(.secondary)
                    }
                    if !location.lastEvent.isEmpty {
                        HStack { Text("마지막 이벤트"); Spacer(); Text(location.lastEvent).foregroundStyle(.secondary) }
                    }
                }

                Section("표시") {
                    NavigationLink("디자인 미리보기", value: "preview").tapHaptic()
                    Stepper("선로에 이전 역 \(store.config.slots)칸", value: $store.config.slots, in: 3...6).changeHaptic(store.config.slots)
                    Stepper("열차 \(store.config.trainsPerDirection)대", value: $store.config.trainsPerDirection, in: 1...4).changeHaptic(store.config.trainsPerDirection)
                    Stepper("갱신 \(secondsText(store.config.refreshSeconds))초마다", value: $store.config.refreshSeconds, in: 1...60, step: 1).changeHaptic(store.config.refreshSeconds)
                    Toggle("캐릭터 애니메이션", isOn: $store.config.runnerEnabled).changeHaptic(store.config.runnerEnabled)
                    if store.config.runnerEnabled {
                        Stepper("탑승 중 애니메이션 \(secondsText(store.config.animSeconds))초마다", value: $store.config.animSeconds, in: 0.5...5, step: 0.5).changeHaptic(store.config.animSeconds)
                    }
                    Stepper("탑승 중 지하철 갱신 \(secondsText(store.config.rideRefreshSeconds))초마다",
                            value: $store.config.rideRefreshSeconds, in: store.config.rideUnit...60, step: store.config.rideUnit).changeHaptic(store.config.rideRefreshSeconds)
                    Stepper("탑승 추적 최대 \(Int(store.config.rideMaxMinutes))분", value: $store.config.rideMaxMinutes, in: 15...180, step: 15).changeHaptic(store.config.rideMaxMinutes)
                    Stepper("같은 역 재시작 간격 \(Int(store.config.cooldownSeconds / 60))분",
                            value: $store.config.cooldownSeconds, in: 60...1800, step: 60).changeHaptic(store.config.cooldownSeconds)
                }

                Section {
                    DisclosureGroup("기록", isExpanded: $showLog) {
                        if controller.log.isEmpty {
                            Text("아직 없음").foregroundStyle(.secondary)
                        }
                        ForEach(controller.log, id: \.self) { line in
                            Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("kemometro")
            .onChange(of: store.config.animSeconds) { _, _ in store.config.snapRideRefresh() }
            .onChange(of: store.config.runnerEnabled) { _, _ in store.config.snapRideRefresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showClose { Button("완료") { dismiss() }.tapHaptic() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .navigationDestination(for: String.self) { key in
                if key == "preview" { DesignPreviewView() }
            }
            .onAppear {
                if location.authorization == .notDetermined { location.requestAlways() }
            }
        }
    }

    private var authText: String {
        switch location.authorization {
        case .authorizedAlways: return "항상"
        case .authorizedWhenInUse: return "사용 중에만 (항상으로 바꿔야 합니다)"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        default: return "미정"
        }
    }
}

struct PlaceRow: View {
    let place: Place
    var body: some View {
        HStack(spacing: 10) {
            LineMark(lineId: place.lineId, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name.isEmpty ? "이름 없음" : place.name).font(.body.weight(.semibold))
                Text("\(place.directionLabel) · \(Int(place.radius))m")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !place.enabled { Text("꺼짐").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct DirOption: Identifiable {
    var label: String
    var dest: String
    var updn: String
    var id: String { label }
}

struct PlaceEditorView: View {
    @Binding var place: Place
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var location: LocationMonitor
    @State private var testing = false
    @State private var dirOptions: [DirOption] = []
    @State private var checkMessage = ""

    var body: some View {
        Form {
            Section("역") {
                TextField("역 이름", text: $place.name)
                TextField("API 역명 (비우면 역 이름)", text: $place.apiName)
                Picker("노선", selection: $place.lineId) {
                    ForEach(Lines.all) { l in
                        Label { Text(l.name) } icon: { Image(uiImage: Lines.menuMark(l.id)) }.tag(l.id)
                    }
                }.changeHaptic(place.lineId)
                Toggle("감시", isOn: $place.enabled).changeHaptic(place.enabled)
            }

            Section {
                TextField("종착역 (예: 신사)", text: $place.dest)
                Picker("상행/하행", selection: $place.updn) {
                    Text("상행").tag("상행"); Text("하행").tag("하행")
                    Text("내선").tag("내선"); Text("외선").tag("외선")
                }.changeHaptic(place.updn)
                Button(testing ? "확인 중…" : "지금 열차로 방면 확인") { Task { await checkDirections() } }.tapHaptic()
                    .disabled(testing || store.config.apiKey.isEmpty)
                ForEach(dirOptions) { opt in
                    Button {
                        place.dest = opt.dest; place.updn = opt.updn
                    } label: {
                        HStack {
                            Text(opt.label)
                            Spacer()
                            if place.dest == opt.dest { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }.tapHaptic()
                }
                if !checkMessage.isEmpty { Text(checkMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("방면")
            }

            Section("위치") {
                LabeledContent("위도") { TextField("위도", value: $place.latitude, format: .number.precision(.fractionLength(6))).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                LabeledContent("경도") { TextField("경도", value: $place.longitude, format: .number.precision(.fractionLength(6))).multilineTextAlignment(.trailing).keyboardType(.decimalPad) }
                Button("현재 위치로 채우기") {
                    location.requestOneShot { loc in
                        if let c = loc?.coordinate { place.latitude = c.latitude; place.longitude = c.longitude }
                    }
                }.tapHaptic()
                VStack(alignment: .leading) {
                    Text("반경 \(Int(place.radius))m")
                    Slider(value: $place.radius, in: 100...1500, step: 50).changeHaptic(place.radius)
                }
                VStack(alignment: .leading) {
                    Text("보여줄 시간 " + durationText(place.showSeconds))
                    Slider(value: $place.showSeconds, in: 15...600, step: 15).changeHaptic(place.showSeconds)
                }
            }

            Section {
                GlassPillButton(title: "지금 미리보기", systemImage: "play.fill", tint: Lines.info(place.lineId).color, prominent: true) {
                    let p = place
                    Task { @MainActor in await ActivityController.shared.trigger(place: p, reason: "미리보기", force: true) }
                }
                .disabled(store.config.apiKey.isEmpty)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle(place.name.isEmpty ? "역" : place.name)
    }

    private func durationText(_ s: Double) -> String {
        let sec = Int(s)
        if sec < 60 { return "\(sec)초" }
        return sec % 60 == 0 ? "\(sec / 60)분" : "\(sec / 60)분 \(sec % 60)초"
    }

    private func checkDirections() async {
        testing = true
        defer { testing = false }
        do {
            let name = place.apiName.isEmpty ? place.name : place.apiName
            let rows = try await SubwayAPI.arrivalsSmart(station: name, apiKey: store.config.apiKey)
            let mine = rows.filter { $0.subwayId == place.lineId && $0.arvlCd != "2" }
            var dest: [String: String] = [:]
            var count: [String: Int] = [:]
            var order: [String] = []
            for r in mine {
                let k = r.updnLine
                if dest[k] == nil { dest[k] = TrainStatus.dest(of: r.trainLineNm).name; order.append(k) }
                count[k, default: 0] += 1
            }
            dirOptions = order.map { k in
                let d = dest[k] ?? ""
                return DirOption(label: "\(d.isEmpty ? k : d + "행") · \(k) · \(count[k] ?? 0)대", dest: d, updn: k)
            }
            checkMessage = mine.isEmpty ? "이 역·노선으로 지금 접근 중인 열차가 없습니다 (역명·노선을 확인)" : ""
        } catch {
            dirOptions = []
            checkMessage = error.localizedDescription
        }
    }
}

/// 0.5 단위 초를 "1", "0.5", "2.5" 처럼
private func secondsText(_ v: Double) -> String { String(format: "%g", v) }

extension ContentView {
    /// 판교 → 합정으로 경로 API 를 불러 보고, 읽은 결과와 응답 원문을 보여 준다
    @MainActor func testRouteAPI() async {
        routeTesting = true
        defer { routeTesting = false }
        let out = await RouteSearch.search(from: "판교", to: "합정", key: store.config.staticKey)
        routeRaw = RouteAPI.lastRaw
        var msg = "\(out.source) · 경로 \(out.routes.count)개"
        if let r = out.routes.first {
            msg += " · \(r.minutes)분 · 환승 \(r.transfers)회"
            if let fare = r.fare { msg += " · \(fare)원" }
        }
        if !out.note.isEmpty { msg += "\n\(out.note)" }
        routeTestMessage = msg
    }
}
