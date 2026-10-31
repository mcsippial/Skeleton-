import SkeletonCore
import SwiftUI

/// Every logged pain, newest first, grouped by day.
struct HistoryView: View {
    let model: BodyViewModel
    @State private var pendingDelete: PainEntry?

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [PainEntry]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: model.entries) { cal.startOfDay(for: $0.onsetAt) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0]!.sorted { $0.onsetAt > $1.onsetAt }) }
    }

    var body: some View {
        List {
            if model.entries.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(Theme.Color.secondaryText)
                    .listRowBackground(Color.clear)
            }
            ForEach(days) { group in
                Section {
                    ForEach(group.entries) { e in
                        NavigationLink(value: Route.pain(e.id)) { HistoryRow(model: model, entry: e) }
                            .listRowBackground(Color.white.opacity(0.7))
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDelete = e }
                            }
                    }
                } header: {
                    Text(sectionTitle(group.day)).font(Theme.Font.label).tracking(1.1)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlowBackground())
        .navigationTitle("History")
        .confirmationDialog("Delete this pain?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let e = pendingDelete { Task { await model.delete(e.id) } }
                pendingDelete = nil
            }
        }
    }

    private func sectionTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}

/// One pain in a list: dot coloured by intensity, area, and type · intensity · time.
struct HistoryRow: View {
    let model: BodyViewModel
    let entry: PainEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.Color.pain(intensity: entry.intensity)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.regionIDs.map { model.regionName($0) }.joined(separator: ", "))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(entry.painType.label) · \(entry.intensity)/10 · \(entry.onsetAt.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
