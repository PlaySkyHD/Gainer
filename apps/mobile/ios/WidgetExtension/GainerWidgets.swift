import ActivityKit
import SwiftUI
import WidgetKit

private struct GainerWidgetEntry: TimelineEntry {
  let date: Date
  let destination: GainerRoute
}

private struct GainerWidgetProvider: TimelineProvider {
  let destination: GainerRoute

  func placeholder(in context: Context) -> GainerWidgetEntry {
    GainerWidgetEntry(date: .now, destination: destination)
  }

  func getSnapshot(in context: Context, completion: @escaping (GainerWidgetEntry) -> Void) {
    completion(GainerWidgetEntry(date: .now, destination: destination))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GainerWidgetEntry>) -> Void) {
    let entry = GainerWidgetEntry(date: .now, destination: destination)
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 60 * 60))))
  }
}

private struct GainerWidgetView: View {
  let entry: GainerWidgetEntry
  @Environment(\.widgetFamily) private var family

  private var title: String {
    switch entry.destination {
    case .training: "Training öffnen"
    case .checkIn: "Check-in öffnen"
    case .nutrition: "Ernährung öffnen"
    }
  }

  private var symbol: String {
    switch entry.destination {
    case .training: "figure.strengthtraining.traditional"
    case .checkIn: "scalemass"
    case .nutrition: "fork.knife"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .accessibilityHidden(true)
      Text("Gainer")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      Text(title)
        .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
        .minimumScaleFactor(0.8)
        .lineLimit(2)
      Spacer(minLength: 0)
      Text("Öffnet die App zur Prüfung")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(.background, for: .widget)
    .widgetURL(GainerExtensionURL.route(entry.destination, source: "widget"))
    .accessibilityElement(children: .combine)
  }
}

private struct GainerTrainingWidget: Widget {
  let kind = "GainerTrainingWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: GainerWidgetProvider(destination: .training)) { entry in
      GainerWidgetView(entry: entry)
    }
    .configurationDisplayName("Training öffnen")
    .description("Öffnet Gainer und prüft die aktuelle Sitzung.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct GainerCheckInWidget: Widget {
  let kind = "GainerCheckInWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: GainerWidgetProvider(destination: .checkIn)) { entry in
      GainerWidgetView(entry: entry)
    }
    .configurationDisplayName("Check-in öffnen")
    .description("Öffnet Gainer und prüft die aktuelle Sitzung.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private struct GainerWorkoutLiveActivity: Widget {
  let kind = "GainerWorkoutLiveActivity"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GainerWorkoutActivityAttributes.self) { context in
      GainerActivityView(state: context.state)
        .widgetURL(GainerExtensionURL.route(.training, source: "liveActivity"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.state.status == "rest" ? "Pause" : "Training", systemImage: "figure.strengthtraining.traditional")
        }
        DynamicIslandExpandedRegion(.trailing) {
          GainerActivityClock(state: context.state)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.status == "rest" ? "Pausentimer" : "Workout läuft")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: "figure.strengthtraining.traditional")
      } compactTrailing: {
        GainerActivityClock(state: context.state)
      } minimal: {
        Image(systemName: "figure.strengthtraining.traditional")
      }
      .widgetURL(GainerExtensionURL.route(.training, source: "liveActivity"))
    }
  }
}

private struct GainerActivityView: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "figure.strengthtraining.traditional")
        .font(.title2)
      VStack(alignment: .leading, spacing: 4) {
        Text(state.status == "rest" ? "Trainingspause" : "Workout läuft")
          .font(.headline)
        GainerActivityClock(state: state)
          .font(.title3.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding()
    .activityBackgroundTint(.black.opacity(0.88))
    .activitySystemActionForegroundColor(.white)
    .foregroundStyle(.white)
    .accessibilityElement(children: .combine)
  }
}

private struct GainerActivityClock: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    if state.status == "rest", let restEndsAt = state.restEndsAt {
      Text(restEndsAt, style: .timer)
        .accessibilityLabel("Verbleibende Pausenzeit")
    } else {
      Text(state.startedAt, style: .timer)
        .accessibilityLabel("Vergangene Trainingszeit")
    }
  }
}

private enum GainerExtensionURL {
  static func route(_ route: GainerRoute, source: String) -> URL {
    var components = URLComponents()
    components.scheme = "gainer"
    components.host = "route"
    components.path = "/\(route.rawValue)"
    components.queryItems = [URLQueryItem(name: "source", value: source)]
    return components.url!
  }
}

@main
struct GainerWidgetBundle: WidgetBundle {
  var body: some Widget {
    GainerTrainingWidget()
    GainerCheckInWidget()
    GainerWorkoutLiveActivity()
  }
}
