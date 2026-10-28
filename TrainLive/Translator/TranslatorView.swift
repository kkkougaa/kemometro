import SwiftUI
import UIKit

// 번역기 메인 화면. translator.html 의 배치를 그대로 옮겼다:
// 헤더 → 언어 바 → 입력 카드 → 번역 옵션 → 결과 → 피드백. 메뉴는 왼쪽 서랍.

enum TLRoute: Hashable { case history, glossary, settings, tones, chips }

struct TranslatorView: View {
    @StateObject private var m = TranslatorModel()
    @ObservedObject private var store = TLStore.shared
    @State private var path: [TLRoute] = []
    @State private var drawerOpen = false
    @State private var optOpen = false
    @State private var fbText = ""
    @FocusState private var focus: Field?
    @AppStorage("tl.result_size") private var rsize = TLResultSize.md.rawValue
    @Environment(\.openURL) private var openURL
    @Namespace private var pillNS

    enum Field { case input, extra, charPrompt, feedback }

    private var resultFont: CGFloat { (TLResultSize(rawValue: rsize) ?? .md).points }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color.tlBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        langBar
                        inputCard
                        optionsCard
                        resultCard
                        if m.succeeded { feedbackCard.transition(.opacity.combined(with: .move(edge: .bottom))) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                    .animation(.snappy(duration: 0.28), value: m.succeeded)
                }
                .scrollDismissesKeyboard(.interactively)

                if let t = m.toast {
                    Text(t)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .liquidGlass()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focus == .input {
                        Spacer()
                        Button { m.translateOrCancel() } label: {
                            Text(m.busy ? "취소" : "번역").fontWeight(.semibold)
                        }
                        .disabled(!m.busy && m.input.trimmed.isEmpty)
                    }
                }
            }
            .navigationDestination(for: TLRoute.self) { r in
                switch r {
                case .history: TLHistoryPage { h in m.loadHistory(h); path = [] }
                case .glossary: TLGlossaryPage(lang: m.tgtLang)
                case .settings: TLSettingsPage(tgtLang: m.tgtLang)
                case .tones: TLTonesPage()
                case .chips: TLChipsPage(outLang: m.outLang)
                }
            }
        }
        .overlay {
            TLDrawer(open: $drawerOpen) { route in path = [route] }
        }
        .tint(.tlAccent)
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 8) {
            TLCircleButton(symbol: "line.3.horizontal", label: "메뉴") {
                focus = nil
                drawerOpen = true
            }
            Text("번역기")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.7)
                .padding(.leading, 2)
            Spacer()
            TLCircleButton(symbol: "clock.arrow.circlepath", label: "번역 기록") { path = [.history] }
            AppSwitcherButton()
        }
        .padding(.top, 2)
    }

    // MARK: 언어 바

    private var langBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button { withAnimation(.spring(duration: 0.32, bounce: 0.15)) { m.pickKorean() } } label: {
                    langLabel("한국어", active: m.srcLang == "ko")
                }
                .buttonStyle(.plain)
                .tapHaptic()

                Menu {
                    ForEach(TLLang.order, id: \.self) { l in
                        Button {
                            withAnimation(.spring(duration: 0.32, bounce: 0.15)) { m.pickTarget(l) }
                        } label: {
                            if l == m.tgtLang { Label(TLLang.cfg(l).label, systemImage: "checkmark") }
                            else { Text(TLLang.cfg(l).label) }
                        }
                    }
                } label: {
                    langLabel(TLLang.cfg(m.tgtLang).label, active: m.srcLang != "ko", chevron: true)
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .frame(height: 48)
            .liquidGlassCard(cornerRadius: 14)

            TLCircleButton(symbol: "arrow.left.arrow.right", size: 38, label: "방향 바꾸기") {
                withAnimation(.spring(duration: 0.32, bounce: 0.15)) { m.swap() }
            }
        }
    }

    private func langLabel(_ text: String, active: Bool, chevron: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(active ? Color.primary : Color.tlText2)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.tlText3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.tlFill)
                    .matchedGeometryEffect(id: "langPill", in: pillNS)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: 입력

    private var inputCard: some View {
        VStack(spacing: 0) {
            TextField(m.placeholder, text: $m.input, axis: .vertical)
                .font(.system(size: 17))
                .lineSpacing(3)
                .lineLimit(4...14)
                .focused($focus, equals: .input)
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 12)
                .frame(minHeight: 124, alignment: .topLeading)

            Divider().padding(.horizontal, 10)

            HStack(spacing: 2) {
                toolButton("doc.on.clipboard", "붙여넣기") { m.paste() }
                toolButton("xmark", "지우기") { m.clearInput(); focus = .input }
                Spacer()
                Text("\(m.input.count) / 2000")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.tlText3)
                    .padding(.trailing, 6)
            }
            .frame(height: 44)
            .padding(.horizontal, 10)

            translateButton
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .tlCard()
    }

    private func toolButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.tlText2)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .accessibilityLabel(label)
    }

    private var translateButton: some View {
        Button { m.translateOrCancel() } label: {
            HStack(spacing: 8) {
                if m.busy {
                    ProgressView().tint(Color.tlOnAccent).controlSize(.small)
                    Text("취소")
                } else {
                    Text("번역")
                    Image(systemName: "play.fill").font(.system(size: 11)).opacity(0.7)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.tlOnAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .tlAccentGlass(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .opacity(!m.busy && m.input.trimmed.isEmpty ? 0.5 : 1)
        .disabled(!m.busy && m.input.trimmed.isEmpty)
    }

    // MARK: 번역 옵션

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !m.toKO else { return }
                withAnimation(.snappy(duration: 0.28)) { optOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text("번역 옵션").font(.system(size: 16)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if m.toKO {
                        Text("역방향 번역 시 비활성").font(.system(size: 13)).foregroundStyle(Color.tlText3)
                    } else {
                        Text(m.optionsSummary)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.tlText2)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.tlText3)
                        .rotationEffect(.degrees(optOpen && !m.toKO ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optOpen && !m.toKO {
                optionsBody
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .tlCard()
        .opacity(m.toKO ? 0.6 : 1)
        .clipped()
    }

    private var optionsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            optLabel("말투")
            TLFlow(spacing: 7) {
                ForEach(store.tones) { t in toneChip(t) }
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        m.extraOn.toggle()
                        if !m.extraOn { m.extraText = "" }
                    }
                    if m.extraOn { focus = .extra }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(m.extraOn ? Color.tlOnAccent : Color.tlText2)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(m.extraOn ? Color.tlAccent : Color.tlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .tapHaptic()
                .accessibilityLabel("추가 옵션")
            }

            if m.extraOn {
                optLabel("추가 옵션").padding(.top, 14)
                fieldBox("예) 번역 결과에 후리가나(フリガナ)를 같이 달아줘 / 경어는 쓰지 말고 반말로만 해줘",
                         text: $m.extraText, field: .extra)
            }
            if m.tone == "character" {
                optLabel("캐릭터 프롬프트").padding(.top, 14)
                fieldBox("예: 고양이 캐릭터, 어미에 ~냥 붙임, 귀엽고 장난스러운 말투",
                         text: $store.charPrompt, field: .charPrompt)
            }

            toggleRow("원문 충실 번역",
                      m.strict ? "on — 원문 그대로 충실하게 번역" : "off — 내용을 정리·보완하며 번역",
                      isOn: $m.strict)
            toggleRow("Thinking 모드",
                      store.thinking ? "on — 느리지만 정확하게" : "off — 빠른 번역",
                      isOn: $store.thinking)
            toggleRow("우선 처리",
                      store.priority ? "on — 표준의 1.75~2배" : "off — 표준 요금",
                      isOn: $store.priority)
        }
    }

    private func optLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(Color.tlText2).padding(.bottom, 9)
    }

    private func fieldBox(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(.system(size: 16))
            .lineLimit(2...8)
            .focused($focus, equals: field)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.tlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toneChip(_ t: Tone) -> some View {
        let on = m.tone == t.id
        let ok = m.toneAvailable(t.id)
        return Button {
            withAnimation(.snappy(duration: 0.22)) { m.tone = on ? "none" : t.id }
        } label: {
            HStack(spacing: 6) {
                if t.id == "character" {
                    Image("kouga")
                        .resizable().scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                    Text(store.charName + " 말투")
                } else {
                    Text(t.name)
                }
            }
            .font(.system(size: 14, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Color.tlOnAccent : Color.primary)
            .padding(.horizontal, t.id == "character" ? 8 : 13)
            .frame(height: 34)
            .background(on ? Color.tlAccent : Color.tlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .disabled(!ok)
        .opacity(ok ? 1 : 0.35)
    }

    private func toggleRow(_ name: String, _ desc: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.top, 14)
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 16))
                    Text(desc).font(.system(size: 12.5)).foregroundStyle(Color.tlText3)
                }
            }
            .tint(.tlAccent)
            .changeHaptic(isOn.wrappedValue)
            .padding(.top, 14)
        }
    }

    // MARK: 결과

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(m.resultLabel)
                .font(.system(size: 13))
                .foregroundStyle(Color.tlText2)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            if m.busy && !m.streaming {
                TLLoadingDots()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else if !m.result.isEmpty {
                Text(m.result)
                    .font(.system(size: resultFont))
                    .lineSpacing(resultFont * 0.42)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            } else if m.error.isEmpty {
                Text("번역 결과가 여기에 표시됩니다.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.tlText3)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }

            if !m.error.isEmpty {
                Text(m.error)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.tlRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.tlRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }

            if m.succeeded { metaPills }

            if !m.comment.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("번역 코멘트").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.tlAccentDark)
                    Text(m.comment).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Color.tlAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            resultFooter
        }
        .tlCard()
        .animation(.easeOut(duration: 0.2), value: m.comment.isEmpty)
    }

    @ViewBuilder
    private var metaPills: some View {
        let pol = m.politeness
        let sugs = m.glossarySuggestions
        if !pol.isEmpty || m.usedPriority || !sugs.isEmpty {
            TLFlow(spacing: 5) {
                if !pol.isEmpty { pill(pol) }
                if m.usedPriority { pill("우선 처리") }
                ForEach(sugs, id: \.self) { s in
                    HStack(spacing: 0) {
                        Button { m.acceptSuggestion(s) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 9, weight: .heavy))
                                Text(s.x + " → " + s.k)
                            }
                            .padding(.leading, 10).padding(.trailing, 6)
                            .frame(height: 24)
                        }
                        .buttonStyle(.plain)
                        Button { withAnimation { m.dismissSuggestion(s) } } label: {
                            Text("×").padding(.leading, 2).padding(.trailing, 9).frame(height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("다시 묻지 않기")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tlAccentDark)
                    .background(Color.tlAccent.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func pill(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(Color.tlText2)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.tlFill, in: Capsule())
    }

    private var resultFooter: some View {
        HStack(spacing: 6) {
            brandButton("LINE", color: Color(red: 0x06 / 255, green: 0xC7 / 255, blue: 0x55 / 255), url: "line://")
            brandButton("𝕏", color: .black, url: "twitter://")
            Spacer()
            TLFillButton(title: "원문+번역") { m.copyBoth() }
            TLFillButton(title: "복사") { m.copyResult() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 복사한 뒤 바로 대화하러 넘어간다
    private func brandButton(_ text: String, color: Color, url: String) -> some View {
        Button {
            if !m.result.isEmpty { UIPasteboard.general.string = TLText.cleanForCopy(m.result) }
            if let u = URL(string: url) { openURL(u) }
        } label: {
            Text(text)
                .font(.system(size: text.count > 2 ? 9 : 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .accessibilityLabel(text == "LINE" ? "LINE" : "X")
    }

    // MARK: 피드백

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("번역 피드백")
                .font(.system(size: 13))
                .foregroundStyle(Color.tlText2)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, m.fbMessages.isEmpty ? 6 : 0)

            if !m.fbMessages.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(m.fbMessages.enumerated()), id: \.element.id) { i, msg in
                        fbRow(msg)
                        if i < m.fbMessages.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 16)
            }

            if m.fbBusy {
                TLLoadingDots(size: 6).padding(.horizontal, 16).padding(.vertical, 8)
            }

            TLFlow(spacing: 6) {
                ForEach(store.chips(m.outLang)) { c in
                    Button { m.sendFeedback(c.prompt) } label: {
                        Text(c.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.tlFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .tapHaptic()
                    .disabled(m.fbBusy || m.busy)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $fbText, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .focused($focus, equals: .feedback)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.tlFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    let t = fbText
                    fbText = ""
                    m.sendFeedback(t)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.tlOnAccent)
                        .frame(width: 36, height: 36)
                        .tlAccentGlass()
                }
                .buttonStyle(.plain)
                .tapHaptic()
                .disabled(fbText.trimmed.isEmpty || m.fbBusy || m.busy)
                .opacity(fbText.trimmed.isEmpty ? 0.5 : 1)
                .padding(.bottom, 1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .tlCard()
    }

    private func fbRow(_ msg: FbMsg) -> some View {
        let user = msg.role == "user"
        return (Text(user ? "나  " : "AI  ")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(user ? Color.tlText3 : Color.tlAccent)
                + Text(msg.text)
                    .font(.system(size: 14))
                    .foregroundColor(user ? Color.tlText2 : Color.primary))
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
    }
}
