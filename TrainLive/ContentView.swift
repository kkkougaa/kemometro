import ActivityKit
import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var location: LocationMonitor
    @EnvironmentObject var controller: ActivityController
    @State private var showLog = false
    @State private var path: [String] = LaunchFlags.preview ? ["preview"] : []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    SecureField("서울 열린데이터광장 인증키", text: $store.config.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API 키")
                }

                Section {
                    ForEach($store.config.places) { $place in
                        NavigationLink {
                            PlaceEditorView(place: $place)
                        } label: {
                            PlaceRow(place: place)
                        }
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
                    }
                } header: {
                    Text("감시할 역")
                }

                Section("권한") {
                    HStack {
                        Text("위치")
                        Spacer()
                        Text(authText).foregroundStyle(location.authorization == .authorizedAlways ? .green : .orange)
                    }
                    if location.authorization != .authorizedAlways {
                        Button("위치 권한 요청") { location.requestAlways() }
                        Button("설정 앱에서 \"항상\"으로 바꾸기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
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
                    NavigationLink("디자인 미리보기", value: "preview")
                    Stepper("선로에 이전 역 \(store.config.slots)칸", value: $store.config.slots, in: 3...6)
                    Stepper("열차 \(store.config.trainsPerDirection)대", value: $store.config.trainsPerDirection, in: 1...4)
                    Stepper("갱신 \(Int(store.config.refreshSeconds))초마다", value: $store.config.refreshSeconds, in: 3...60, step: 1)
                    Stepper("탑승 중 갱신 \(Int(store.config.rideRefreshSeconds))초마다", value: $store.config.rideRefreshSeconds, in: 5...60, step: 5)
                    Stepper("탑승 추적 최대 \(Int(store.config.rideMaxMinutes))분", value: $store.config.rideMaxMinutes, in: 15...180, step: 15)
                    Stepper("같은 역 재시작 간격 \(Int(store.config.cooldownSeconds / 60))분",
                            value: $store.config.cooldownSeconds, in: 60...1800, step: 60)
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
            .navigationTitle("열차 위치")
            .toolbar { EditButton() }
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
                        HStack { LineMark(lineId: l.id, size: 20); Text(l.name) }.tag(l.id)
                    }
                }
                Toggle("감시", isOn: $place.enabled)
            }

            Section {
                TextField("종착역 (예: 신사)", text: $place.dest)
                Picker("상행/하행", selection: $place.updn) {
                    Text("상행").tag("상행"); Text("하행").tag("하행")
                    Text("내선").tag("내선"); Text("외선").tag("외선")
                }
                Button(testing ? "확인 중…" : "지금 열차로 방면 확인") { Task { await checkDirections() } }
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
                    }
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
                }
                VStack(alignment: .leading) {
                    Text("반경 \(Int(place.radius))m")
                    Slider(value: $place.radius, in: 100...1500, step: 50)
                }
                VStack(alignment: .leading) {
                    Text("보여줄 시간 " + durationText(place.showSeconds))
                    Slider(value: $place.showSeconds, in: 15...600, step: 15)
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
