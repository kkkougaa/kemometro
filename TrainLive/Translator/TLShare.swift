import Foundation
import UIKit

// 공유 시트 번역(TrainLiveAction 확장)에 설정을 넘긴다.
// 확장은 앱의 UserDefaults 를 못 읽는다. 앱 그룹이 살아 있으면 그쪽으로, 무료 서명에서 앱 그룹이
// 안 되면 같은 팀끼리만 보이는 이름 붙은 클립보드로 넘긴다. 확장은 둘 다 없으면 키를 직접 받는다.

@MainActor
enum TLShare {
    static let group = "group.kr.neogul.trainlive"
    static let pasteboard = UIPasteboard.Name("kr.neogul.trainlive.shared")
    private static var pending = false

    /// 설정이 바뀔 때마다 부른다. 0.5초 묶어서 한 번만 쓴다.
    static func publish() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pending = false
            write()
        }
    }

    static func setLastTarget(_ lang: String) {
        UserDefaults.standard.set(lang, forKey: "tl.last_tgt")
        publish()
    }

    private static func write() {
        let s = TLStore.shared
        var dict: [String: String] = [
            "gemini_api_key": s.apiKey.trimmed,
            "gemini_model": s.model.trimmed,
            "thinking": s.thinking ? "1" : "0",
            "char_prompt_default": s.charPrompt,
            "last_tgt": UserDefaults.standard.string(forKey: "tl.last_tgt") ?? "ja"
        ]
        for l in TLLang.order {
            dict["glossary_" + l] = Glossary.serialize(s.glossary(l))
            dict["banned_" + l] = s.banned(l)
        }
        if let g = UserDefaults(suiteName: group) {
            for (k, v) in dict {
                if k == "thinking" { g.set(v == "1", forKey: "tl.thinking") } else { g.set(v, forKey: "tl." + k) }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8),
           let pb = UIPasteboard(name: pasteboard, create: true) {
            pb.string = str
        }
    }
}
