import SwiftData
import SwiftUI
import TimerKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var records: [WorkoutRecord]

    @State private var activeRun: RunSession?

    private struct DayGroup: Identifiable {
        let day: Date
        let records: [WorkoutRecord]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        return grouped
            .map { DayGroup(day: $0.key, records: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    private var thisWeek: [WorkoutRecord] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return records.filter { interval.contains($0.startedAt) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished workouts and stopwatch sessions show up here.")
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                WeekStat(title: "Workouts this week", value: "\(thisWeek.count)")
                                Divider()
                                WeekStat(
                                    title: "Time this week",
                                    value: TimeFormat.clock(Int(thisWeek.reduce(0) { $0 + $1.totalSeconds }))
                                )
                            }
                            .padding(.vertical, 4)
                        }

                        ForEach(days) { group in
                            Section(group.day.formatted(date: .complete, time: .omitted)) {
                                ForEach(group.records) { record in
                                    row(for: record)
                                }
                                .onDelete { offsets in
                                    for index in offsets { modelContext.delete(group.records[index]) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .fullScreenCover(item: $activeRun) { session in
                RunView(session: session)
            }
        }
    }

    @ViewBuilder
    private func row(for record: WorkoutRecord) -> some View {
        switch record.kind {
        case .interval:
            HistoryRow(record: record)
                .swipeActions(edge: .leading) {
                    if let definition = record.definition {
                        Button {
                            startAgain(record, definition: definition)
                        } label: {
                            Label("Start again", systemImage: "play.fill")
                        }
                        .tint(.green)
                    }
                }
                .contextMenu {
                    if let definition = record.definition {
                        Button("Start again", systemImage: "play.fill") { startAgain(record, definition: definition) }
                    }
                }
        case .stopwatch:
            NavigationLink {
                LapsDetailView(record: record)
            } label: {
                HistoryRow(record: record)
            }
        }
    }

    private func startAgain(_ record: WorkoutRecord, definition: TimerDefinition) {
        activeRun = RunSession(name: record.name, color: record.color, definition: definition, templateID: nil, settings: settings)
    }
}

private struct WeekStat: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind == .stopwatch ? "stopwatch" : (record.completed ? "checkmark.circle.fill" : "flag.checkered"))
                .font(.title2)
                .foregroundStyle(record.color.color)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let total = TimeFormat.clock(Int(record.totalSeconds.rounded()))
        switch record.kind {
        case .stopwatch:
            return total + " · " + String(localized: "\(record.laps.count) laps")
        case .interval:
            let rounds = String(localized: "\(record.roundsCompleted)/\(record.totalRounds) rounds")
            return record.completed ? "\(total) · \(rounds)" : String(localized: "\(total) · \(rounds) · ended early")
        }
    }
}

private struct LapsDetailView: View {
    let record: WorkoutRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: TimeFormat.stopwatch(record.totalSeconds))
            }
            Section("Laps") {
                ForEach(Array(record.laps.enumerated()), id: \.offset) { index, lap in
                    LabeledContent(String(localized: "Lap \(index + 1)"), value: TimeFormat.stopwatch(lap))
                }
            }
        }
        .monospacedDigit()
        .navigationTitle(record.name)
    }
}
