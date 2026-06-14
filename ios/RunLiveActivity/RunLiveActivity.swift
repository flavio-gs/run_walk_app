import ActivityKit
import WidgetKit
import SwiftUI

public struct LiveActivitiesAppAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var emoji: String
    }
}

struct RunLiveActivity: Widget {

    var body: some WidgetConfiguration {

        ActivityConfiguration(
            for: LiveActivitiesAppAttributes.self
        ) { context in

            Text(context.state.emoji)

        } dynamicIsland: { context in

            DynamicIsland {

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.emoji)
                }

            } compactLeading: {
                Text("😀")
            } compactTrailing: {
                Text("😀")
            } minimal: {
                Text("😀")
            }
        }
    }
}
