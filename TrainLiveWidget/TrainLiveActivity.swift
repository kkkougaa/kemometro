import ActivityKit
import SwiftUI
import WidgetKit

/// 잠금화면 배너와 다이내믹 아일랜드. 그림은 Shared/ActivityViews.swift 에 있고 여기선 자리만 잡는다.
struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            ActivityLockView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Lines.info(context.state.lineId ?? context.attributes.lineId).color)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ActivityIslandParts.leading(a, s) }
                DynamicIslandExpandedRegion(.trailing) { ActivityIslandParts.trailing(a, s) }
                DynamicIslandExpandedRegion(.bottom) { ActivityIslandParts.bottom(a, s) }
            } compactLeading: {
                ActivityIslandParts.compactLeading(a, s)
            } compactTrailing: {
                ActivityIslandParts.compactTrailing(a, s)
            } minimal: {
                ActivityIslandParts.minimal(a, s)
            }
            .keylineTint(Lines.info(s.lineId ?? a.lineId).color)
        }
    }
}
