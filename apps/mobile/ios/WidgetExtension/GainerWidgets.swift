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
            .multilineTextAlignment(.trailing)
            .frame(width: 64, alignment: .trailing)
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
              if let targetText = detail.targetText {
                Text(targetText)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          if GainerRestPhase(context.state).isPause {
            HStack(spacing: 10) {
              GainerTimeReadout(state: context.state, font: .title3.weight(.bold))
                .multilineTextAlignment(.leading)
              GainerRestProgress(state: context.state)
                .frame(maxWidth: .infinity)
            }
          }
        }
      } compactLeading: {
        GainerIslandLeading(state: context.state)
      } compactTrailing: {
        GainerCompactTimer(state: context.state)
          .multilineTextAlignment(.trailing)
          .frame(width: 44, alignment: .trailing)
      } minimal: {
        GainerIslandLeading(state: context.state)
      }
      .widgetURL(GainerExtensionURL.route(.training, source: "liveActivity"))
    }
  }
}

/// Sperrbildschirm: oben Icon, Titel und Trainingszeit; darunter links die Zeit
/// (Pause oder Training), rechts die Übung mit Satz und Ziel; unten Fortschritt.
private struct GainerActivityView: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        GainerAppIconImage(size: 20)
        Text(GainerActivityText.title(for: state))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color("GainerPrimaryText"))
          .lineLimit(1)
        Spacer(minLength: 8)
        // Ohne Pause steht die Trainingszeit bereits groß in der Karte.
        if GainerRestPhase(state).isPause {
          GainerActivityClock(state: state)
            .font(.subheadline)
            .foregroundStyle(Color("GainerSecondaryText"))
            .multilineTextAlignment(.trailing)
            .frame(width: 72, alignment: .trailing)
        }
      }
      if let detail = state.detail {
        HStack(alignment: .top, spacing: 12) {
          GainerTimeColumn(state: state)
          GainerExerciseColumn(detail: detail)
        }
        GainerFooter(state: state, detail: detail)
      } else {
        // Ohne Details nur der Status und die Zeit, ohne Übung und Satz.
        GainerTimeReadout(state: state, font: .system(size: 44, weight: .bold))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color("GainerSurface"))
    .activityBackgroundTint(Color("GainerSurface"))
    .activitySystemActionForegroundColor(.white)
    // Die Karte bleibt dunkel, unabhängig vom Systemmodus.
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .contain)
  }
}

/// Linke Spalte: Statusbeschriftung und die große Zeit.
private struct GainerTimeColumn: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(GainerRestPhase(state).label)
        .font(.caption2.weight(.semibold))
        .tracking(0.8)
        .foregroundStyle(Color("GainerSecondaryText"))
        .lineLimit(1)
      GainerTimeReadout(state: state, font: .system(size: 40, weight: .bold))
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(width: 140, alignment: .leading)
  }
}

/// Rechte Spalte: Übung, Satzposition mit Punkten und der Zielwert.
private struct GainerExerciseColumn: View {
  let detail: GainerWorkoutActivityAttributes.ContentState.Detail

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(detail.exerciseName)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color("GainerPrimaryText"))
        .lineLimit(2)
      HStack(spacing: 6) {
        Text("Satz \(detail.setIndex) von \(detail.setCount)")
          .font(.caption)
          .foregroundStyle(Color("GainerSecondaryText"))
          .lineLimit(1)
        if detail.setCount <= GainerSetDots.maxCount {
          GainerSetDots(current: detail.setIndex, count: detail.setCount)
        }
      }
      if let targetText = detail.targetText {
        Text(targetText)
          .font(.caption)
          .foregroundStyle(Color("GainerSecondaryText"))
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Unterer Streifen: Pausenfortschritt, rechts die Position „Übung x/y“.
private struct GainerFooter: View {
  let state: GainerWorkoutActivityAttributes.ContentState
  let detail: GainerWorkoutActivityAttributes.ContentState.Detail

  var body: some View {
    HStack(spacing: 10) {
      if GainerRestPhase(state).isPause {
        GainerRestProgress(state: state)
          .frame(maxWidth: .infinity)
      } else {
        Spacer(minLength: 0)
      }
      if let exerciseIndex = detail.exerciseIndex, let exerciseCount = detail.exerciseCount {
        Text("Übung \(exerciseIndex)/\(exerciseCount)")
          .font(.caption)
          .foregroundStyle(Color("GainerSecondaryText"))
          .monospacedDigit()
          .lineLimit(1)
      }
    }
  }
}

/// Satzpunkte: erledigte gefüllt, aktueller als Ring, offene gedämpft.
private struct GainerSetDots: View {
  static let maxCount = 8

  let current: Int
  let count: Int

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<count, id: \.self) { index in
        dot(at: index)
          .frame(width: 7, height: 7)
      }
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func dot(at index: Int) -> some View {
    let position = min(max(current, 1), count) - 1
    if index < position {
      Circle().fill(Color("GainerAccent"))
    } else if index == position {
      Circle().strokeBorder(Color("GainerAccent"), lineWidth: 1.5)
    } else {
      Circle().fill(Color("GainerSecondaryText").opacity(0.35))
    }
  }
}

/// Fortschrittsbalken der Pause. Läuft die Pause, zählt das System den Balken
/// selbst; pausiert ist er statisch, nach Ablauf leer.
private struct GainerRestProgress: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    switch GainerRestPhase(state) {
    case .training:
      EmptyView()
    case .running(let targetAt):
      ProgressView(
        timerInterval: Self.interval(to: targetAt, duration: state.restDurationSeconds),
        countsDown: true
      )
      .labelsHidden()
      .tint(Color("GainerAccent"))
      .accessibilityLabel("Pausenfortschritt")
    case .paused(let remaining):
      ProgressView(
        value: Double(remaining),
        total: Double(max(state.restDurationSeconds ?? remaining, remaining, 1))
      )
      .labelsHidden()
      .tint(Color("GainerAccent"))
      .accessibilityLabel("Pausenfortschritt")
    case .expired:
      ProgressView(value: 0, total: 1)
        .labelsHidden()
        .tint(Color("GainerAccent"))
        .accessibilityLabel("Pausenfortschritt")
    }
  }

  /// Der Balken beginnt beim Pausenbeginn (Ziel minus Dauer) und endet am Ziel.
  private static func interval(to targetAt: Date, duration: Int?) -> ClosedRange<Date> {
    guard let duration, duration > 0 else {
      let now = Date.now
      return now...max(targetAt, now)
    }
    return targetAt.addingTimeInterval(-Double(duration))...targetAt
  }
}

/// Anzeigezustand der Pause, aus dem Content-State abgeleitet.
private enum GainerRestPhase {
  case training
  case running(Date)
  case paused(Int)
  case expired

  init(_ state: GainerWorkoutActivityAttributes.ContentState) {
    if state.expired {
      self = .expired
    } else if let targetAt = state.timerTargetAt {
      self = .running(targetAt)
    } else if let remaining = state.pausedRemainingSeconds {
      self = .paused(remaining)
    } else {
      self = .training
    }
  }

  var isPause: Bool {
    switch self {
    case .training:
      return false
    case .running, .paused, .expired:
      return true
    }
  }

  var label: String {
    switch self {
    case .training: "TRAINING"
    case .running, .paused: "PAUSE"
    case .expired: "PAUSE VORBEI"
    }
  }
}

/// Die große Zeit: Trainingszeit ohne Pause, sonst Countdown, angehaltene Restzeit oder 0:00.
private struct GainerTimeReadout: View {
  let state: GainerWorkoutActivityAttributes.ContentState
  let font: Font

  var body: some View {
    switch GainerRestPhase(state) {
    case .training:
      GainerActivityClock(state: state)
        .font(font)
        .foregroundStyle(Color("GainerPrimaryText"))
    case .running(let targetAt):
      GainerCountdown(targetAt: targetAt)
        .font(font)
        .foregroundStyle(Color("GainerAccent"))
    case .paused(let remaining):
      Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
        .font(font)
        .monospacedDigit()
        .foregroundStyle(Color("GainerAccent"))
        .accessibilityLabel("Pausenzeit angehalten")
    case .expired:
      Text("0:00")
        .font(font)
        .monospacedDigit()
        .foregroundStyle(Color("GainerAccent"))
        .accessibilityLabel("Pause abgelaufen")
    }
  }
}

/// Linke Seite der kompakten und minimalen Dynamic Island: Pausenring oder Icon.
private struct GainerIslandLeading: View {
  let state: GainerWorkoutActivityAttributes.ContentState

  var body: some View {
    if case .running(let targetAt) = GainerRestPhase(state) {
      ProgressView(
        timerInterval: Date.now...max(targetAt, Date.now),
        countsDown: true
      )
      .progressViewStyle(.circular)
      .labelsHidden()
      .tint(Color("GainerAccent"))
      .frame(width: 18, height: 18)
    } else {
      GainerAppIconImage(size: 18)
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
