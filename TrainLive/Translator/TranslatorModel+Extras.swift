import Foundation
import SwiftUI
import UIKit

// 2단계 동작: 역번역 · 독음 · TTS · 문법/맞춤법 · 사진 번역 · 부분 바꾸기

extension TranslatorModel {

    func resetExtras() {
        btText = nil; btOpen = false; btLoading = false; btWarn = ""; btMarks = []
        pronText = nil; pronOpen = false; pronLoading = false
        overlay = []; overlayImage = nil; madeImage = nil
        makeTask?.cancel(); makeTask = nil; makingImage = false
        if TLAudio.shared.playing == "result" { TLAudio.shared.stop() }
    }

    private func needKey() -> Bool {
        if store.hasKey { return true }
        error = "설정에서 Gemini API 키를 넣어주세요."
        return false
    }

    // MARK: 역번역

    /// 번역문을 한국어로 다시 읽어 원문과 어긋나는지 본다. 한국어 → 외국어일 때만.
    var showBackTranslation: Bool { mode == .translate && succeeded && srcLang == "ko" }

    func toggleBackTranslation() {
        if btText != nil { withAnimation(.snappy(duration: 0.25)) { btOpen.toggle() }; return }
        guard !result.isEmpty, !btLoading, store.hasKey else { return }
        btLoading = true
        let src = result, origin = originalText
        let model = store.effectiveModel, key = store.apiKey.trimmed
        Task { [weak self] in
            var text = "역번역을 가져오지 못했어요."
            var warn = "", marks: [String] = []
            if let bt = try? await Gemini.ask(model: model, key: key, prompt: TLExtras.backTranslatePrompt(src),
                                              maxTokens: 1024, temperature: 0.1) {
                text = bt
                let d = TLExtras.divergence(source: origin, bt: bt)
                warn = d.message; marks = d.marks
                if !warn.isEmpty { TLHaptic.warn() }
            }
            guard let self else { return }
            self.btLoading = false
            guard self.result == src else { return }
            withAnimation(.snappy(duration: 0.25)) {
                self.btText = text; self.btWarn = warn; self.btMarks = marks; self.btOpen = true
            }
        }
    }

    // MARK: 독음

    /// 같은 결과에 독음을 껐다 켜면 다시 부르지 않는다
    func togglePron() {
        if pronOpen { withAnimation(.snappy(duration: 0.22)) { pronOpen = false }; return }
        guard !result.isEmpty, !pronLoading else { return }
        let src = result
        let key = srcLang + ">" + tgtLang + "|" + src
        if let hit = pronCache[key] {
            pronText = hit
            withAnimation(.snappy(duration: 0.22)) { pronOpen = true }
            return
        }
        if outLang == "ja" {
            // 일본어는 iOS 형태소 분석기로 기기 안에서 바로 읽는다
            let out = TLLocal.japaneseReading(src)
            pronCache[key] = out
            pronText = out
            withAnimation(.snappy(duration: 0.22)) { pronOpen = true }
            TLHaptic.tick()
            return
        }
        guard TLLocal.aiAvailable || needKey() else { return }
        pronLoading = true
        let prompt = TLExtras.pronPrompt(tgtName: outName, text: src)
        Task { [weak self] in
            var out = "독음을 가져오지 못했어요."
            if let r = try? await TLLocal.askLocalFirst(prompt, maxTokens: 2048), !r.trimmed.isEmpty {
                out = r.trimmed
                guard let self else { return }
                if self.pronCache.count >= 40 { self.pronCache.removeAll() }
                self.pronCache[key] = out
            }
            guard let self else { return }
            self.pronLoading = false
            guard self.result == src else { return }
            self.pronText = out
            withAnimation(.snappy(duration: 0.22)) { self.pronOpen = true }
        }
    }

    // MARK: TTS

    var ttsPlaying: Bool { TLAudio.shared.playing == "result" }

    func toggleTTS() {
        if TLAudio.shared.playing == "result" { TLAudio.shared.stop(); return }
        guard !result.isEmpty, !ttsLoading, needKey() else { return }
        let spoken = TLText.cleanForCopy(result)
        let voice = store.ttsVoice
        if !TLTTS.cached(spoken, voice: voice) { ttsLoading = true }
        Task { [weak self] in
            do {
                let wav = try await TLTTS.synthesize(spoken, voice: voice)
                try TLAudio.shared.play(wav, tag: "result")
            } catch {
                self?.error = "TTS 오류: " + error.localizedDescription
            }
            self?.ttsLoading = false
        }
    }

    // MARK: 문법 · 맞춤법

    enum SideAction { case image, grammar, spell }

    /// 번역 버튼 왼쪽 버튼. 사진이 붙으면 이미지 번역, 일본어 → 한국어면 일본어 문법, 한국어를 칠 땐 맞춤법.
    var sideAction: SideAction? {
        if attached != nil { return .image }
        if srcLang != "ko" { return tgtLang == "ja" ? .grammar : nil }
        return .spell
    }

    func runSideAction() {
        switch sideAction {
        case .image: translateImageOverlay()
        case .grammar: checkText(.grammar)
        case .spell: checkText(.spell)
        case nil: break
        }
    }

    private func checkText(_ kind: ResultMode) {
        let text = input.trimmed
        guard !text.isEmpty, !busy, needKey() else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        busy = true; streaming = false; error = ""; usedPriority = false; succeeded = false
        result = ""; comment = ""; fbMessages = []; conversation = []
        resetExtras()
        mode = kind
        reqSeq += 1
        let my = reqSeq
        let prompt = kind == .grammar ? TLExtras.grammarPrompt(text) : TLExtras.spellPrompt(text)
        let model = store.effectiveModel, key = store.apiKey.trimmed
        task = Task { [weak self] in
            do {
                let out = try await Gemini.ask(model: model, key: key, prompt: prompt,
                                               maxTokens: kind == .grammar ? 1024 : 2048, temperature: 0.2)
                guard let self, my == self.reqSeq else { return }
                self.result = out.trimmed
                if kind == .grammar {
                    // 문법 결과에도 피드백을 이어서 할 수 있다
                    self.originalText = text
                    self.conversation = [
                        ["role": "user", "parts": [["text": TLExtras.grammarFeedbackSystem(out)]]],
                        ["role": "model", "parts": [["text": "네, 결과를 기억했습니다. 수정 요청을 말씀해주세요."]]]
                    ]
                    self.succeeded = true
                }
                TLHaptic.done()
            } catch is CancellationError {
            } catch {
                guard let self, my == self.reqSeq else { return }
                self.error = "오류: " + error.localizedDescription
            }
            if let self, my == self.reqSeq { self.busy = false }
        }
    }

    // MARK: 사진

    func attach(_ image: UIImage) {
        guard let p = TLExtras.prepare(image) else { error = "이미지를 열지 못했어요."; return }
        withAnimation(.snappy(duration: 0.25)) { attached = p.image }
        attachedData = p.data
        attachedMime = p.mime
    }

    func removeAttachment() {
        withAnimation(.snappy(duration: 0.25)) { attached = nil }
        attachedData = nil
    }

    /// 사진 안의 글 위치를 받아 원본 위에 번역만 덮는다
    func translateImageOverlay() {
        guard let data = attachedData, let image = attached, !busy, needKey() else { return }
        busy = true; streaming = false; error = ""; usedPriority = false; succeeded = false
        result = ""; comment = ""; fbMessages = []; conversation = []
        resetExtras()
        mode = .image
        reqSeq += 1
        let my = reqSeq
        let thinking = store.thinking
        var gen: [String: Any] = ["temperature": 0.1, "maxOutputTokens": 4096,
                                  "responseMimeType": "application/json", "responseSchema": TLExtras.overlaySchema]
        if !thinking { gen["thinkingConfig"] = ["thinkingBudget": 0] }
        let parts: [[String: Any]] = [
            ["inline_data": ["mime_type": attachedMime, "data": data.base64EncodedString()]],
            ["text": TLExtras.overlayPrompt(tgtName: outName)]
        ]
        let body: [String: Any] = ["contents": [["parts": parts]], "generationConfig": gen]
        let model = store.effectiveModel, key = store.apiKey.trimmed
        let tgtName = outName
        let glossaryText = Glossary.instr(Glossary.serialize(store.glossary(tgtLang)), pairs: store.glossary(tgtLang), toKO: toKO)
        task = Task { [weak self] in
            do {
                var items: [OverlayItem] = []
                // ① 기기 안 글자 인식 → 글만 번역
                let ocr = await TLLocal.recognize(image)
                if !ocr.isEmpty {
                    var g: [String: Any] = ["temperature": 0.2, "maxOutputTokens": 4096, "responseMimeType": "application/json",
                                            "responseSchema": ["type": "ARRAY", "items": ["type": "STRING"]] as [String: Any]]
                    if !thinking { g["thinkingConfig"] = ["thinkingBudget": 0] }
                    let prompt = TLLocal.overlayTranslatePrompt(ocr.map(\.text), tgtName: tgtName, glossary: glossaryText)
                    let tb: [String: Any] = ["contents": [["parts": [["text": prompt]]]], "generationConfig": g]
                    if let obj = try? await Gemini.generate(model: model, key: key, body: tb, timeout: thinking ? 90 : 40),
                       let data = Gemini.parts(obj).compactMap({ $0["text"] as? String }).joined().data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [String], arr.count == ocr.count {
                        items = zip(ocr, arr).compactMap { o, t in
                            let dst = t.trimmed
                            return dst.isEmpty ? nil : OverlayItem(box: o.box, src: o.text, dst: dst)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                // ② 글자를 못 찾았거나 번역이 어긋나면 사진째 보내 위치까지 받는다
                if items.isEmpty {
                    let obj = try await Gemini.generate(model: model, key: key, body: body, timeout: thinking ? 120 : 60)
                    let raw = Gemini.parts(obj).compactMap { $0["text"] as? String }.joined()
                    items = TLExtras.parseOverlay(raw)
                }
                guard let self, my == self.reqSeq else { return }
                if items.isEmpty { throw GeminiError(message: "이미지에서 글자를 찾지 못했어요.") }
                self.overlayImage = image
                self.overlay = items
                self.result = items.map(\.dst).joined(separator: "\n")
                self.originalText = items.map(\.src).filter { !$0.isEmpty }.joined(separator: "\n")
                self.conversation = [
                    ["role": "user", "parts": [["text": TLPrompt.feedbackSystem(source: self.originalText, result: self.result)]]],
                    ["role": "model", "parts": [["text": "네, 번역 결과를 기억했습니다. 수정 요청을 말씀해주세요."]]]
                ]
                self.succeeded = true
                TLHaptic.done()
            } catch is CancellationError {
            } catch {
                guard let self, my == self.reqSeq else { return }
                self.error = "오류: " + error.localizedDescription
                TLHaptic.error()
            }
            if let self, my == self.reqSeq { self.busy = false }
        }
    }

    /// 원본의 폰트·배치를 살려 번역된 이미지를 새로 그린다. 오래 걸려서 중간에 끊을 수 있다.
    func toggleMakeImage() {
        if makingImage { makeTask?.cancel(); makeTask = nil; makingImage = false; return }
        guard let image = overlayImage, let data = image.jpegData(compressionQuality: 0.92), needKey() else { return }
        makingImage = true
        let parts: [[String: Any]] = [
            ["inline_data": ["mime_type": "image/jpeg", "data": data.base64EncodedString()]],
            ["text": TLExtras.makeImagePrompt(tgtName: outName)]
        ]
        let gen: [String: Any] = ["responseModalities": ["TEXT", "IMAGE"], "imageConfig": ["imageSize": store.imageSize]]
        let body: [String: Any] = ["contents": [["parts": parts]], "generationConfig": gen]
        let model = store.effectiveImageModel, key = store.apiKey.trimmed
        makeTask = Task { [weak self] in
            do {
                let obj = try await Gemini.generate(model: model, key: key, body: body, timeout: 180)
                guard !Task.isCancelled, let self else { return }
                guard let d = Gemini.inlineData(obj), let im = UIImage(data: d.data) else {
                    throw GeminiError(message: "이미지를 만들지 못했어요.")
                }
                withAnimation(.snappy(duration: 0.3)) { self.madeImage = im }
                TLHaptic.done()
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.error = "오류: " + error.localizedDescription }
            }
            if !Task.isCancelled { self?.makingImage = false }
        }
    }

    func saveMadeImage() {
        guard let im = madeImage else { return }
        UIImageWriteToSavedPhotosAlbum(im, nil, nil, nil)
        show("사진에 저장했어요")
        TLHaptic.copy()
    }

    // MARK: 부분 바꾸기

    /// 결과 본문에서 고른 구간만 바꾼다. 범위가 어긋났으면 같은 글을 찾아 바꾼다.
    @discardableResult
    func replaceInResult(_ fragment: String, with replacement: String, hint: NSRange?) -> Bool {
        let ns = result as NSString
        var r = NSRange(location: NSNotFound, length: 0)
        if let h = hint, h.location != NSNotFound, NSMaxRange(h) <= ns.length, ns.substring(with: h) == fragment { r = h }
        else { r = ns.range(of: fragment) }
        guard r.location != NSNotFound else { return false }
        result = ns.replacingCharacters(in: r, with: replacement)
        // 본문이 바뀌었으니 역번역·독음은 다시 받아야 한다
        btText = nil; btOpen = false; btWarn = ""; btMarks = []
        pronText = nil; pronOpen = false
        TLHaptic.done()
        return true
    }
}
