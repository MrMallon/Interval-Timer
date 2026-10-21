import SwiftData
import SwiftUI

enum WatchEditorTarget: Identifiable {
    case new
    case existing(TimerTemplate)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let template): return template.id.uuidString
        }
    }
}

struct WatchLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: [SortDescriptor(\TimerTemplate.sortOrder), SortDescriptor(\TimerTemplate.createdAt)])
    private var templates: [TimerTemplate]

    @State private var editorTarget: WatchEditorTarget?
    @State private var activeRun: WatchRunSession?

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Text("Tap + to make a timer, or add one on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    Button { start(template) } label: {
                        WatchTemplateRow(template: template)
                    }
                    .listItemTint(template.color.color.opacity(0.25))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(template) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editorTarget = .existing(template) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }

                Section {
                    NavigationLink {
                        WatchHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Timers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editorTarget = .new } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New timer")
                }
            }
            .sheet(item: $editorTarget) { target in
                WatchEditorView(target: target)
            }
            .fullScreenCover(item: $activeRun) { session in
                WatchRunView(session: session)
            }
        }
    }

    private func start(_ template: TimerTemplate) {
        template.lastUsedAt = Date()
        activeRun = WatchRunSession(
            name: template.name,
            color: template.color,
            definition: template.definition,
            settings: settings
        )
    }

    private func delete(_ template: TimerTemplate) {
        SyncCoordinator.shared.recordDeletion(of: template.id)
        modelContext.delete(template)
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
    }
}

private struct WatchTemplateRow: View {
    let template: TimerTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(template.color.color)
                    .frame(width: 8, height: 8)
                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(TimerSummary.describe(template.definition))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts the timer")
    }
}
