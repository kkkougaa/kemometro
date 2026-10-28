import SwiftUI

// 서랍과 서랍에서 여는 페이지들 (기록 · 용어집 · 설정 · 말투 관리 · 피드백 칩)

// MARK: 서랍

struct TLDrawer: View {
    @Binding var open: Bool
    @ObservedObject var store = TLStore.shared
    let go: (TLRoute) -> Void

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if open {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { open = false }
                    .transition(.opacity)
                panel
                    .transition(.move(edge: .leading))
                    .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                        if v.translation.width < -60 { open = false }
                    })
            }
        }
        .animation(.spring(duration: 0.34, bounce: 0.08), value: open)
    }

    private func pick(_ r: TLRoute) {
        Haptics.light()
        open = false
        // 서랍이 물러난 뒤에 페이지가 들어와야 둘이 겹치지 않는다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { go(r) }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { pick(.settings) } label: {
                HStack(spacing: 12) {
                    Image("kouga")
                        .resizable().scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("반가워요!").font(.system(size: 13)).foregroundStyle(Color.tlText2)
                        HStack(spacing: 4) {
                            Text(store.hasKey ? store.charName : "API 설정 해주세요")
                                .font(.system(size: 19, weight: .bold))
                                .tracking(-0.5)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.tlText3)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)

            HStack(spacing: 8) {
                quick("번역 기록") { pick(.history) }
                quick("대화 모드") { pick(.talk) }
            }
            .padding(.bottom, 14)

            item("checkmark.circle", "공부") { pick(.study) }
            item("note.text", "표현 노트") { pick(.words) }
            item("character.book.closed", "용어집") { pick(.glossary) }
            item("gearshape", "설정") { pick(.settings) }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("v" + version).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.tlText3)
                Text("© 空間").font(.system(size: 12)).foregroundStyle(Color.tlText3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.tlCard.ignoresSafeArea())
        .shadow(color: .black.opacity(0.18), radius: 20, x: 4)
    }

    private func quick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .liquidGlassRect(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private func item(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.tlText2)
                    .frame(width: 26)
                Text(title).font(.system(size: 17)).foregroundStyle(.primary)
                Spacer()
            }
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: 짝 편집 시트 (용어 · 말투 · 칩)

struct TLPairEditor: View {
    let title: String
    let firstPlaceholder: String
    let secondPlaceholder: String
    var secondMultiline = false
    var secondRequired = true
    @State var first: String
    @State var second: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(firstPlaceholder, text: $first)
                if secondMultiline {
                    TextField(secondPlaceholder, text: $second, axis: .vertical).lineLimit(3...12)
                } else {
                    TextField(secondPlaceholder, text: $second)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Haptics.light()
                        onSave(first.trimmed, second.trimmed)
                        dismiss()
                    }
                    .disabled(first.trimmed.isEmpty || (secondRequired && second.trimmed.isEmpty))
                }
            }
        }
        .presentationDetents(secondMultiline ? [.large] : [.medium])
        .tint(.tlAccent)
    }
}

/// 시트를 띄울 때 넘기는 편집 대상. index 가 nil 이면 새로 추가.
struct TLEditTarget: Identifiable {
    let id = UUID()
    var index: Int?
    var first: String
    var second: String
}

// MARK: 번역 기록

struct TLHistoryPage: View {
    @ObservedObject var store = TLStore.shared
    let onPick: (HistoryItem) -> Void
    @State private var askClear = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 a h:mm"
        return f
    }()

    var body: some View {
        List {
            if store.history.isEmpty {
                Text("아직 번역 기록이 없어요")
                    .foregroundStyle(Color.tlText3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
            }
            ForEach(store.history) { h in
                Button { Haptics.light(); onPick(h) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text("\(h.srcName) → \(h.tgtName)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.tlAccentDark)
                            Text(Self.fmt.string(from: Date(timeIntervalSince1970: h.ts / 1000)))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.tlText3)
                        }
                        Text(h.src).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(3)
                        Text(h.tgt).font(.system(size: 15)).foregroundStyle(Color.tlText2).lineLimit(3)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("번역 기록")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("전체 삭제", role: .destructive) { askClear = true }
                    .foregroundStyle(Color.tlRed)
                    .disabled(store.history.isEmpty)
            }
        }
        .confirmationDialog("번역 기록을 모두 지울까요?", isPresented: $askClear, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) { store.clearHistory() }
        }
    }
}

// MARK: 용어집

struct TLGlossaryPage: View {
    let lang: String
    @ObservedObject var store = TLStore.shared
    @State private var editing: TLEditTarget?

    private var list: [GlossaryPair] { store.glossary(lang) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    if list.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 32, weight: .light))
                            Text("아직 등록한 용어가 없어요")
                        }
                        .foregroundStyle(Color.tlText3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                        Button { editing = TLEditTarget(index: i, first: p.from, second: p.to) } label: {
                            HStack(spacing: 10) {
                                Text(p.from).foregroundStyle(.primary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.tlText3)
                                Text(p.to).foregroundStyle(Color.tlAccentDark)
                                Spacer()
                            }
                            .font(.system(size: 16))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { idx in
                        var l = list
                        l.remove(atOffsets: idx)
                        store.setGlossary(l, lang: lang)
                    }
                } header: {
                    Text("한국어 → " + TLLang.cfg(lang).label)
                }
            }

            Button { editing = TLEditTarget(index: nil, first: "", second: "") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.tlOnAccent)
                    .frame(width: 58, height: 58)
                    .tlAccentGlass()
            }
            .buttonStyle(.plain)
            .tapHaptic()
            .padding(.trailing, 20)
            .padding(.bottom, 24)
            .accessibilityLabel("용어 추가")
        }
        .navigationTitle("용어집")
        .sheet(item: $editing) { t in
            TLPairEditor(title: t.index == nil ? "용어 추가" : "용어 편집",
                         firstPlaceholder: "원문", secondPlaceholder: "번역",
                         first: t.first, second: t.second) { from, to in
                var l = list
                let pair = GlossaryPair(from: from, to: to)
                if let i = t.index, i < l.count { l[i] = pair } else { l.append(pair) }
                store.setGlossary(l, lang: lang)
            }
        }
    }
}

// MARK: 설정

struct TLSettingsPage: View {
    let tgtLang: String
    @ObservedObject var store = TLStore.shared
    @AppStorage("tl.result_size") private var rsize = TLResultSize.md.rawValue
    @State private var banned = ""
    @State private var loaded = false
    @State private var keyVisible = false
    @ObservedObject private var audio = TLAudio.shared
    @State private var previewLoading = false

    /// 고른 목소리·스타일로 짧은 문장을 들려준다
    private func previewVoice() {
        if audio.playing == "preview" { audio.stop(); return }
        guard store.hasKey, !previewLoading else { return }
        previewLoading = true
        let text = TLTTS.samples[tgtLang] ?? TLTTS.samples["ja"]!
        Task {
            do {
                let wav = try await TLTTS.synthesize(text, voice: store.ttsVoice)
                try audio.play(wav, tag: "preview")
            } catch {}
            previewLoading = false
        }
    }

    var body: some View {
        Form {
            Section("Gemini API 키") {
                HStack {
                    Group {
                        if keyVisible { TextField("AIzaSy...", text: $store.apiKey) }
                        else { SecureField("AIzaSy...", text: $store.apiKey) }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, design: .monospaced))
                    Button { keyVisible.toggle() } label: {
                        Image(systemName: keyVisible ? "eye.slash" : "eye").foregroundStyle(Color.tlText3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("번역") {
                LabeledContent("번역 모델") {
                    TextField(TLStore.defaultModel, text: $store.model)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Toggle("Thinking 모드", isOn: $store.thinking)
                Toggle("우선 처리", isOn: $store.priority)
                Toggle("입력 언어 자동 감지", isOn: $store.autoDetect)
                NavigationLink("말투 관리", value: TLRoute.tones)
                NavigationLink("피드백 칩", value: TLRoute.chips)
                Picker("결과 글자 크기", selection: $rsize) {
                    ForEach(TLResultSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }

            Section {
                TextField("〜っす\n〜だぜ → 〜だよ", text: $banned, axis: .vertical)
                    .lineLimit(3...12)
                    .font(.system(size: 16))
                    .onChange(of: banned) { _, v in if loaded { store.setBanned(v, lang: tgtLang) } }
            } header: {
                Text("금지 표현 · " + TLLang.cfg(tgtLang).label)
            }

            Section("캐릭터") {
                LabeledContent("이름") {
                    TextField("예: 코우가", text: $store.charName).multilineTextAlignment(.trailing)
                }
                TextField("캐릭터 프롬프트", text: $store.charPrompt, axis: .vertical)
                    .lineLimit(4...14)
                    .font(.system(size: 15))
                Button("기본 프롬프트로 되돌리기") { store.charPrompt = TLPrompt.kougaPrompt }
                    .disabled(store.charPrompt == TLPrompt.kougaPrompt)
            }

            Section("음성") {
                LabeledContent("TTS 모델") {
                    TextField(TLStore.defaultTTSModel, text: $store.ttsModel)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack {
                    Picker("TTS 목소리", selection: $store.ttsVoice) {
                        ForEach(TLTTS.voices, id: \.id) { v in Text(v.id + " — " + v.desc).tag(v.id) }
                    }
                    Button { previewVoice() } label: {
                        Group {
                            if previewLoading { ProgressView().controlSize(.small) }
                            else { Image(systemName: audio.playing == "preview" ? "stop.fill" : "play.fill") }
                        }
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("미리듣기")
                }
                Picker("읽기 스타일", selection: $store.ttsStyle) {
                    ForEach(TLTTS.styles, id: \.id) { s in Text(s.name).tag(s.id) }
                }
            }

            Section("이미지") {
                LabeledContent("이미지 번역 모델") {
                    TextField(TLStore.defaultImageModel, text: $store.imageModel)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("이미지 번역 출력 크기", selection: $store.imageSize) {
                    ForEach(TLStore.imageSizesAccepted, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Soniox API 키") {
                SecureField("대화 모드·말로 입력", text: $store.sonioxKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, design: .monospaced))
            }

            TLBackupSection()

            Section {
                Link(destination: URL(string: "https://ai.google.dev/gemini-api/docs/models")!) {
                    Label("모델 목록 보기", systemImage: "arrow.up.right.square")
                }
            }
        }
        .tint(.tlAccent)
        .navigationTitle("설정")
        .onDisappear { if audio.playing == "preview" { audio.stop() } }
        .onAppear {
            banned = store.banned(tgtLang)
            DispatchQueue.main.async { loaded = true }
        }
    }
}

// MARK: 말투 관리

struct TLTonesPage: View {
    @ObservedObject var store = TLStore.shared
    @State private var editing: TLEditTarget?
    @State private var askReset = false

    var body: some View {
        List {
            ForEach(Array(store.tones.enumerated()), id: \.element.id) { i, t in
                Button {
                    let p = t.id == "character" ? store.charPrompt : t.prompt
                    editing = TLEditTarget(index: i, first: t.name, second: p)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(.system(size: 16)).foregroundStyle(.primary)
                        Text(t.id == "character" ? "캐릭터 프롬프트" : (t.prompt.isEmpty ? "기본 설정" : t.prompt))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tlText3)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in
                var l = store.tones
                l.remove(atOffsets: idx)
                store.setTones(l)
            }
            .onMove { from, to in
                var l = store.tones
                l.move(fromOffsets: from, toOffset: to)
                store.setTones(l)
            }

            Button { editing = TLEditTarget(index: nil, first: "", second: "") } label: {
                Label("새 말투 추가", systemImage: "plus")
            }
        }
        .navigationTitle("말투 관리")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("초기화") { askReset = true } }
        }
        .confirmationDialog("말투를 처음 상태로 돌릴까요?", isPresented: $askReset, titleVisibility: .visible) {
            Button("초기화", role: .destructive) { store.resetTones() }
        }
        .sheet(item: $editing) { t in
            TLPairEditor(title: t.index == nil ? "새 말투" : "말투 편집",
                         firstPlaceholder: "말투 이름 (예: 츤데레)",
                         secondPlaceholder: "프롬프트 (비워두면 기본 설정 사용)",
                         secondMultiline: true, secondRequired: false,
                         first: t.first, second: t.second) { name, prompt in
                var l = store.tones
                let id = t.index.flatMap { $0 < l.count ? l[$0].id : nil } ?? "custom_\(Int(Date().timeIntervalSince1970 * 1000))"
                if id == "character" { store.charPrompt = prompt }
                let tone = Tone(id: id, name: name, prompt: id == "character" ? "USE_CHAR_PROMPT" : prompt)
                if let i = t.index, i < l.count { l[i] = tone } else { l.append(tone) }
                store.setTones(l)
            }
        }
    }
}

// MARK: 피드백 칩

struct TLChipsPage: View {
    let outLang: String
    @ObservedObject var store = TLStore.shared
    @State private var editing: TLEditTarget?

    private var langName: String { outLang == "ko" ? "한국어" : TLLang.cfg(outLang).label }

    var body: some View {
        List {
            Section {
                ForEach(Array(store.chips(outLang).enumerated()), id: \.offset) { i, c in
                    Button { editing = TLEditTarget(index: i, first: c.label, second: c.prompt) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.label).font(.system(size: 16)).foregroundStyle(.primary)
                            Text(c.prompt).font(.system(size: 12)).foregroundStyle(Color.tlText3).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in
                    var l = store.chips(outLang)
                    l.remove(atOffsets: idx)
                    store.setChips(l, outLang: outLang)
                }
                .onMove { from, to in
                    var l = store.chips(outLang)
                    l.move(fromOffsets: from, toOffset: to)
                    store.setChips(l, outLang: outLang)
                }
                Button { editing = TLEditTarget(index: nil, first: "", second: "") } label: {
                    Label("새 칩 추가", systemImage: "plus")
                }
            } header: {
                Text(langName + " 결과")
            }
        }
        .navigationTitle("피드백 칩")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("초기화") { store.resetChips(outLang) } }
        }
        .sheet(item: $editing) { t in
            TLPairEditor(title: t.index == nil ? "새 칩" : "칩 편집",
                         firstPlaceholder: "칩에 쓸 이름 (예: 더 짧게)",
                         secondPlaceholder: "누르면 보낼 요청 (예: 뜻은 그대로 두고 더 짧게 줄여줘)",
                         secondMultiline: true,
                         first: t.first, second: t.second) { label, prompt in
                var l = store.chips(outLang)
                let chip = FbChip(label: label, prompt: prompt)
                if let i = t.index, i < l.count { l[i] = chip } else { l.append(chip) }
                store.setChips(l, outLang: outLang)
            }
        }
    }
}
