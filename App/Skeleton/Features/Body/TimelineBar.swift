import SwiftUI

/// Scrubber under the body: drag through days and watch pain appear, move and fade.
struct TimelineBar: View {
    let model: BodyViewModel

    var body: some View {
        let range = model.timelineRange
        let span = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.Color.text))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play pain history")

            Slider(value: Binding(get: { model.displayDate.timeIntervalSince(range.lowerBound) / span },
                                  set: { model.scrub(to: range.lowerBound.addingTimeInterval($0 * span)) }),
                   in: 0...1)
                .tint(Theme.Color.text)
                .accessibilityLabel("Timeline")
                .accessibilityValue(label)

            Text(label)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 62, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private var label: String {
        if model.timelineDate == nil { return "Today" }
        let d = model.displayDate
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
