import Foundation
import SwiftUI
import UIKit

// 번역기 설정·기록. kemometro 설정과 섞이지 않게 'tl.' 접두어를 붙여 따로 둔다.
// 키 이름은 translator.html 의 localStorage 키와 같게 맞춰서, 나중에 HTML 판 백업 파일을
// 그대로 가져올 수 있게 한다 (gemini_api_key → tl.gemini_api_key).

struct HistoryItem: Codable, Hashable, Identifiable {
    var src: String
    var tgt: String
    var srcName: String
    var tgtName: String
    var ts: Double
    var id: String { "\(ts)|\(src)" }
}

struct FbChip: Codable, Hashable, Identifiable {
    var label: String
    var prompt: String
    var id: String { label + "|" + prompt }
}

@MainActor
final class TLStore: ObservableObject {
    static let shared = TLStore()
    static let defaultModel = "gemini-3.6-flash"
    private let d = UserDefaults.standard
    private func k(_ key: String) -> String { "tl." + key }

    @Published var apiKey: String { didSet { d.set(apiKey.trimmed, forKey: k("gemini_api_key")) } }
    @Published var model: String { didSet { d.set(model.trimmed, forKey: k("gemini_model")) } }
    @Published var thinking: Bool { didSet { d.set(thinking, forKey: k("thinking")) } }
    @Published var priority: Bool { didSet { d.set(priority ? "1" : "0", forKey: k("gemini_priority")) } }
    @Published var autoDetect: Bool { didSet { d.set(autoDetect ? "1" : "0", forKey: k("auto_detect")) } }
    @Published var charName: String { didSet { d.set(charName, forKey: k("char_name")); _tones = nil } }
    @Published var charPrompt: String { didSet { d.set(charPrompt, forKey: k("char_prompt_default")) } }
    @Published private(set) var history: [HistoryItem] = []
    /// 화면을 다시 그리게 하는 신호 (용어집·금지어·칩·말투가 바뀌었을 때)
    @Published private(set) var revision = 0

    private init() {
        apiKey = d.string(forKey: "tl.gemini_api_key") ?? ""
        model = d.string(forKey: "tl.gemini_model") ?? ""
        thinking = d.bool(forKey: "tl.thinking")
        priority = d.string(forKey: "tl.gemini_priority") == "1"
        autoDetect = d.string(forKey: "tl.auto_detect") != "0"
        charName = d.string(forKey: "tl.char_name") ?? "코우가"
        charPrompt = d.string(forKey: "tl.char_prompt_default") ?? TLPrompt.kougaPrompt
        history = Self.decode([HistoryItem].self, d.data(forKey: "tl.trans_history")) ?? []
    }

    var effectiveModel: String { model.trimmed.isEmpty ? Self.defaultModel : model.trimmed }
    var hasKey: Bool { !apiKey.trimmed.isEmpty }

    private static func decode<T: Decodable>(_ t: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(t, from: data)
    }
    private func bump() { revision &+= 1 }

    // MARK: 기록

    /// 공부 출제 참고·용어집 제안도 여기서 뽑는다. 200개까지.
    func saveHistory(src: String, tgt: String, srcLang: String, tgtLang: String) {
        let cfg = TLLang.cfg(tgtLang)
        let item = HistoryItem(src: String(src.prefix(200)), tgt: String(tgt.prefix(200)),
                               srcName: srcLang == "ko" ? "한국어" : cfg.label,
                               tgtName: srcLang == "ko" ? cfg.label : "한국어",
                               ts: Date().timeIntervalSince1970 * 1000)
        history.insert(item, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        d.set(try? JSONEncoder().encode(history), forKey: k("trans_history"))
    }

    func clearHistory() {
        history = []
        d.removeObject(forKey: k("trans_history"))
    }

    // MARK: 용어집·금지어 (대상 언어별)

    func glossary(_ lang: String) -> [GlossaryPair] { Glossary.parse(d.string(forKey: k("glossary_" + lang)) ?? "") }
    func setGlossary(_ list: [GlossaryPair], lang: String) {
        let s = Glossary.serialize(list)
        if s.isEmpty { d.removeObject(forKey: k("glossary_" + lang)) } else { d.set(s, forKey: k("glossary_" + lang)) }
        bump()
    }
    func banned(_ lang: String) -> String { d.string(forKey: k("banned_" + lang)) ?? "" }
    func setBanned(_ s: String, lang: String) {
        if s.trimmed.isEmpty { d.removeObject(forKey: k("banned_" + lang)) } else { d.set(s, forKey: k("banned_" + lang)) }
        bump()
    }
    func glossarySkip(_ lang: String) -> [String] {
        Self.decode([String].self, d.string(forKey: k("glossary_skip_" + lang))?.data(using: .utf8)) ?? []
    }
    func addGlossarySkip(_ key: String, lang: String) {
        var s = glossarySkip(lang); s.append(key)
        if let data = try? JSONEncoder().encode(Array(s.suffix(200))) { d.set(String(data: data, encoding: .utf8), forKey: k("glossary_skip_" + lang)) }
        bump()
    }

    // MARK: 말투

    private var _tones: [Tone]?
    var tones: [Tone] {
        if let t = _tones { return t }
        var list = Self.decode([Tone].self, d.string(forKey: k("custom_tones"))?.data(using: .utf8)) ?? TLPrompt.defaultTones
        if let i = list.firstIndex(where: { $0.id == "character" }) { list[i].name = "🐺 \(charName) 말투" }
        _tones = list
        return list
    }
    func setTones(_ list: [Tone]) {
        if let data = try? JSONEncoder().encode(list) { d.set(String(data: data, encoding: .utf8), forKey: k("custom_tones")) }
        _tones = nil
        bump()
    }
    func resetTones() { d.removeObject(forKey: k("custom_tones")); _tones = nil; bump() }

    // MARK: 피드백 칩 (결과 언어별)

    func chips(_ outLang: String) -> [FbChip] {
        if let list = Self.decode([FbChip].self, d.string(forKey: k("fb_chips_" + outLang))?.data(using: .utf8)) {
            return list.filter { !$0.label.isEmpty && !$0.prompt.isEmpty }
        }
        return (TLPrompt.fbPresets[outLang] ?? TLPrompt.fbPresets["ko"]!).map { FbChip(label: $0.0, prompt: $0.1) }
    }
    func setChips(_ list: [FbChip], outLang: String) {
        if let data = try? JSONEncoder().encode(list) { d.set(String(data: data, encoding: .utf8), forKey: k("fb_chips_" + outLang)) }
        bump()
    }
    func resetChips(_ outLang: String) { d.removeObject(forKey: k("fb_chips_" + outLang)); bump() }
}

// MARK: 색

extension Color {
    /// 번역기 액센트 — HTML 판의 #0E8A6F / 다크 #3ECBA8
    static let tlAccent = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3E / 255, green: 0xCB / 255, blue: 0xA8 / 255, alpha: 1)
        : UIColor(red: 0x0E / 255, green: 0x8A / 255, blue: 0x6F / 255, alpha: 1) })
    static let tlAccentDark = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x6F / 255, green: 0xE0 / 255, blue: 0xC4 / 255, alpha: 1)
        : UIColor(red: 0x0B / 255, green: 0x6E / 255, blue: 0x58 / 255, alpha: 1) })
    static let tlOnAccent = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x04 / 255, green: 0x23 / 255, blue: 0x1B / 255, alpha: 1) : .white })
    static let tlBg = Color(UIColor.systemGroupedBackground)
    static let tlCard = Color(UIColor.secondarySystemGroupedBackground)
    static let tlFill = Color(UIColor.tertiarySystemFill)
    static let tlRed = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0x7A / 255, blue: 0x5C / 255, alpha: 1)
        : UIColor(red: 0xC1 / 255, green: 0x45 / 255, blue: 0x2A / 255, alpha: 1) })
}
