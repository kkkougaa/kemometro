import Foundation
import UIKit

// 공유 시트 확장의 설정 읽기. 확장은 본 앱의 UserDefaults 를 못 읽는다.
// 본 앱이 두 군데에 같이 써 두고, 확장은 아래 순서로 읽는다. 키가 먼저 나오는 쪽을 쓴다.
//   1) 앱 그룹 UserDefaults (group.kr.neogul.trainlive) — 키 이름은 앱과 같은 "tl.*"
//   2) 이름 붙은 클립보드 (kr.neogul.trainlive.shared) — "tl." 을 뗀 키의 JSON 하나, 값은 전부 문자열
//   3) 확장 자신의 UserDefaults "ta.gemini_api_key" — 위 둘 다 없으면 카드에서 한 번 붙여 넣는다

struct TLActionSettings {
    var apiKey = ""
    var model = ""
    var thinking = false
    var charPrompt = ""
    var lastTgt = "ja"
    /// 대상 언어별 용어집 원문 ('원문=번역' 줄)
    var glossary: [String: String] = [:]
    /// 대상 언어별 금지 표현 원문
    var banned: [String: String] = [:]

    static let defaultModel = "gemini-3.6-flash"
    var effectiveModel: String { model.trimmed.isEmpty ? Self.defaultModel : model.trimmed }
    var hasKey: Bool { !apiKey.trimmed.isEmpty }
}

enum TLActionStore {
    static let groupID = "group.kr.neogul.trainlive"
    static let pasteboardName = "kr.neogul.trainlive.shared"
    static let ownKey = "ta.gemini_api_key"
    static let langs = ["ja", "en", "zh-cn", "zh-tw"]

    static func load() -> TLActionSettings {
        if let s = fromGroup(), s.hasKey { return s }
        if let s = fromPasteboard(), s.hasKey { return s }
        // 둘 다 키가 없으면 다른 설정이라도 살리고, 키만 확장 자신의 것을 쓴다
        var s = fromGroup() ?? fromPasteboard() ?? TLActionSettings()
        s.apiKey = UserDefaults.standard.string(forKey: ownKey) ?? ""
        return s
    }

    static func saveOwnKey(_ key: String) {
        UserDefaults.standard.set(key.trimmed, forKey: ownKey)
    }

    private static func fromGroup() -> TLActionSettings? {
        guard let d = UserDefaults(suiteName: groupID) else { return nil }
        var s = TLActionSettings()
        s.apiKey = d.string(forKey: "tl.gemini_api_key") ?? ""
        s.model = d.string(forKey: "tl.gemini_model") ?? ""
        if let b = d.object(forKey: "tl.thinking") as? Bool { s.thinking = b }
        else { s.thinking = d.string(forKey: "tl.thinking") == "1" }
        s.charPrompt = d.string(forKey: "tl.char_prompt_default") ?? ""
        s.lastTgt = valid(d.string(forKey: "tl.last_tgt"))
        for l in langs {
            if let g = d.string(forKey: "tl.glossary_" + l), !g.isEmpty { s.glossary[l] = g }
            if let b = d.string(forKey: "tl.banned_" + l), !b.isEmpty { s.banned[l] = b }
        }
        return s
    }

    private static func fromPasteboard() -> TLActionSettings? {
        guard let pb = UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: false),
              let raw = pb.string, let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ k: String) -> String {
            if let v = obj[k] as? String { return v }
            if let v = obj[k] as? NSNumber { return v.stringValue }
            return ""
        }
        var s = TLActionSettings()
        s.apiKey = str("gemini_api_key")
        s.model = str("gemini_model")
        let th = str("thinking").lowercased()
        s.thinking = th == "1" || th == "true"
        s.charPrompt = str("char_prompt_default")
        s.lastTgt = valid(str("last_tgt"))
        for l in langs {
            let g = str("glossary_" + l), b = str("banned_" + l)
            if !g.isEmpty { s.glossary[l] = g }
            if !b.isEmpty { s.banned[l] = b }
        }
        return s
    }

    private static func valid(_ l: String?) -> String {
        guard let l, langs.contains(l) else { return "ja" }
        return l
    }
}
