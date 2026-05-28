import ActivityKit
import WidgetKit
import SwiftUI

// Estrutura de dados que o Flutter vai enviar
struct RunAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distance: String
        var pace: String
        var time: String
    }
}

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunAttributes.self) { context in
            // Layout da Tela de Bloqueio
            HStack {
                VStack(alignment: .leading) {
                    Text("Corrida em Andamento").font(.caption).foregroundColor(.orange)
                    Text(context.state.distance).font(.title2).bold()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Ritmo").font(.caption)
                    Text(context.state.pace).font(.title3)
                }
            }
            .padding()
        } dynamicIsland: { context in
            // Layout da Dynamic Island (Expandida e Compacta)
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.distance) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.time) }
            } compactLeading: {
                Text("🏃")
            } compactTrailing: {
                Text(context.state.distance)
            } minimal: {
                Text("🏃")
            }
        }
    }
}

