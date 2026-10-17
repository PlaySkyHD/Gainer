import ActivityKit
import SwiftUI
import WidgetKit

private struct GainerWidgetEntry: TimelineEntry {
  let date: Date
  let destination: GainerRoute
}

private struct GainerWidgetProvider: TimelineProvider {
  let destination: GainerRoute

  func placeholder(in _: Context) -> GainerWidgetEntry {
    GainerWidgetEntry(date: .now, destination: destination)
  }

  func getSnapshot(in _: Context, completion: @escaping (GainerWidgetEntry) -> Void) {
    completion(GainerWidgetEntry(date: .now, destination: destination))
  }

  func getTimeline(in _: Context, completion: @escaping (Timeline<GainerWidgetEntry>) -> Void) {
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
        .foregroundStyle(Color("GainerAccent"))
        .accessibilityHidden(true)
      Text("Gainer")
        .font(.caption.weight(.medium))
        .foregroundStyle(Color("GainerSecondaryText"))
      Text(title)
        .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
        .foregroundStyle(Color("GainerPrimaryText"))
        .minimumScaleFactor(0.8)
        .lineLimit(2)
      Spacer(minLength: 0)
      Text("Öffnet die App zur Prüfung")
        .font(.caption2)
        .foregroundStyle(Color("GainerSecondaryText"))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(Color("GainerSurface"), for: .widget)
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
          HStack(spacing: 6) {
            GainerAppIconImage(size: 22)
            Text(GainerActivityText.title(for: context.state))
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          GainerActivityClock(state: context.state)
            .font(.subheadline)
        }
        DynamicIslandExpandedRegion(.center) {
          if let detail = context.state.detail {
            VStack(spacing: 2) {
              Text(detail.exerciseName)
                .font(.headline)
                .lineLimit(1)
              Text("Satz \(detail.setIndex) von \(detail.setCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          GainerMiddleLine(state: context.state, large: false)
        }
      } compactLeading: {
        GainerAppIconImage(size: 18)
      } compactTrailing: {
        GainerCompactTimer(state: context.state)
      } minimal: {
        GainerAppIconImage(size: 18)
      }
      .widgetURL(GainerExtensionURL.route(.training, source: "liveActivity"))
    }
  }
}

private struct GainerActivityView: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        GainerAppIconImage(size: 24)
        Text(GainerActivityText.title(for: state))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color("GainerPrimaryText"))
          .lineLimit(1)
        Spacer(minLength: 8)
        GainerActivityClock(state: state)
          .font(.subheadline)
          .foregroundStyle(Color("GainerSecondaryText"))
      }
      Spacer(minLength: 0)
      VStack(spacing: 6) {
        if let detail = state.detail {
          Text(detail.exerciseName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color("GainerPrimaryText"))
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        GainerMiddleLine(state: state, large: true)
      }
      .frame(maxWidth: .infinity)
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color("GainerSurface"))
    .activityBackgroundTint(Color("GainerSurface"))
    .activitySystemActionForegroundColor(.white)
    // Die Karte bleibt dunkel, unabhängig vom Systemmodus.
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .contain)
  }
}

/// Satzzeile, bei laufender Pause der Countdown und nach Ablauf 0:00.
private struct GainerMiddleLine: View {
  let state: GainerWorkoutActivityAttributes.ContentState
  let large: Bool

  var body: some View {
    if state.expired {
      Text("0:00")
        .font(large ? .system(size: 44, weight: .bold) : .title3.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(Color("GainerAccent"))
        .accessibilityLabel("Pause abgelaufen")
    } else if let targetAt = state.timerTargetAt {
      GainerCountdown(targetAt: targetAt)
        .font(large ? .system(size: 44, weight: .bold) : .title3.weight(.bold))
        .foregroundStyle(Color("GainerAccent"))
    } else if let detail = state.detail {
      Text("Satz \(detail.setIndex) von \(detail.setCount)")
        .font(large ? .title3 : .caption)
        .foregroundStyle(Color("GainerSecondaryText"))
    }
  }
}

/// Kompakte Zeile in der Dynamic Island: Countdown, 0:00 oder Trainingszeit.
private struct GainerCompactTimer: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    if state.expired {
      Text("0:00")
        .monospacedDigit()
        .foregroundStyle(Color("GainerAccent"))
    } else if let targetAt = state.timerTargetAt {
      GainerCountdown(targetAt: targetAt)
    } else {
      GainerActivityClock(state: state)
    }
  }
}

/// Countdown bis zum Pausenende. Das System zählt selbst; die App läuft dafür nicht.
private struct GainerCountdown: View {
  let targetAt: Date

  var body: some View {
    let now = Date.now
    Text(timerInterval: now...max(targetAt, now), countsDown: true)
      .monospacedDigit()
      .accessibilityLabel("Verbleibende Pausenzeit")
  }
}

private struct GainerActivityClock: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    Text(state.startedAt, style: .timer)
      .monospacedDigit()
      .accessibilityLabel("Vergangene Trainingszeit")
  }
}

/// Titel ohne Freigabe nur „Training“ oder „Pause“, mit Freigabe der Trainingstitel.
private enum GainerActivityText {
  static func title(for state: GainerWorkoutActivityAttributes.ContentState) -> String {
    if let detail = state.detail { return detail.title }
    return state.timerPhase == "ready" ? "Training" : "Pause"
  }
}

private struct GainerAppIconImage: View {
  let size: CGFloat

  var body: some View {
    Image("GainerAppIcon")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
      .accessibilityHidden(true)
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
