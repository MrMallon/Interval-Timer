import SwiftUI
import TimerKit
import WidgetKit

struct QuickStartEntry: TimelineEntry {
    let date: Date
    let timers: [WidgetTimer]
}

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry {
        QuickStartEntry(date: Date(), timers: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) {
        let timers = WidgetStore.load()
        completion(QuickStartEntry(date: Date(), timers: timers.isEmpty && context.isPreview ? Self.sample : timers))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        // The app reloads this timeline whenever the timer list changes.
        completion(Timeline(entries: [QuickStartEntry(date: Date(), timers: WidgetStore.load())], policy: .never))
    }

    static let sample: [WidgetTimer] = [
        WidgetTimer(id: UUID(), name: "Tabata", colorName: ThemeColor.red.rawValue, summary: "8 × 0:20 / 0:10 · 4:00"),
        WidgetTimer(id: UUID(), name: "HIIT 40/20", colorName: ThemeColor.orange.rawValue, summary: "10 × 0:40 / 0:20 · 10:50"),
        WidgetTimer(id: UUID(), name: "Boxing", colorName: ThemeColor.blue.rawValue, summary: "12 × 3:00 / 1:00 · 47:10")
    ]
}

/// Home Screen widget: tap a saved timer to start it.
struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.widgetKind, provider: QuickStartProvider()) { entry in
            QuickStartView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick start")
        .description("Start a saved timer with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickStartView: View {
    let entry: QuickStartEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        default: return 6
        }
    }

    var body: some View {
        if entry.timers.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.title)
                Text("Open Interval Timer to add timers.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        } else if family == .systemSmall, let timer = entry.timers.first {
            SmallTimerView(timer: timer)
                .widgetURL(DeepLink.start(timer.id).url)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick start")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entry.timers.prefix(limit)) { timer in
                    Link(destination: DeepLink.start(timer.id).url) {
                        TimerRow(timer: timer)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SmallTimerView: View {
    let timer: WidgetTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(timer.name)
                .font(.headline)
                .lineLimit(2)
            Text(timer.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var color: Color { (ThemeColor(rawValue: timer.colorName) ?? .red).color }
}

private struct TimerRow: View {
    let timer: WidgetTimer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle((ThemeColor(rawValue: timer.colorName) ?? .red).color)
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(timer.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
