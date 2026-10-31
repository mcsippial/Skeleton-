import SwiftUI

/// Text mode: "sharp pain in my left jaw since Tuesday" → regions highlighted on the body → confirm in the log sheet.
struct DescribePainSheet: View {
    let model: BodyViewModel
    @State private var text = ""
    @State private var busy = false
    @State private var notFound = false
    @State private var listening = false
    @State private var usedVoice = false
    @State private var voiceError: String?
    @State private var transcriber = SpeechTranscriber()
    @State private var voice = VoiceTranscript()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Describe it").font(Theme.Font.title).tracking(-0.4)
                Spacer()
                Button("Cancel") { model.isDescribeSheetPresented = false }
                    .buttonStyle(.secondaryPill)
            }
            Text("Where, what it feels like, and since when.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.secondaryText)
            HStack(alignment: .top, spacing: 10) {
                TextField("e.g. sharp pain in my left jaw since Tuesday, 6/10", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .font(Theme.Font.body)
                    .focused($focused)
                    .submitLabel(.done)
                Button { toggleListening() } label: {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(listening ? .white : Theme.Color.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(listening ? Theme.Color.pain : Color.white.opacity(0.7)))
                        .symbolEffect(.pulse, isActive: listening)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(listening ? "Stop listening" : "Describe by voice")
            }
            .padding(14)
            .glass(cornerRadius: Theme.Radius.small, rainbow: focused || listening, tint: 0.7)
            if let voiceError {
                Text(voiceError).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
            }
            if notFound {
                Text("Couldn't place that. Try naming the area, like \u{201C}lower back\u{201D}.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.redFlag)
            }
            Button(busy ? "Reading…" : "Find it on my body") {
                stopListening()
                busy = true
                notFound = false
                Task {
                    let ok = await model.describe(text, method: usedVoice ? .voice : .text)
                    busy = false
                    notFound = !ok
                }
            }
            .buttonStyle(.primaryPill)
            .disabled(busy || text.trimmingCharacters(in: .whitespaces).count < 3)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .onAppear { focused = true }
        .onDisappear { stopListening() }
        .onChange(of: voice.text) { _, new in text = new }
    }

    private func toggleListening() {
        if listening { stopListening(); return }
        voiceError = nil
        Task {
            guard await SpeechTranscriber.requestPermission() else {
                voiceError = SpeechTranscriber.TranscriberError.notAuthorized.localizedDescription
                return
            }
            do {
                focused = false
                try transcriber.start { [voice] transcript in voice.text = transcript }
                listening = true
                usedVoice = true
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }

    private func stopListening() {
        guard listening else { return }
        transcriber.stop()
        listening = false
    }
}

/// Running transcript, updated from the recogniser's callback. A main-actor class (Sendable),
/// so the callback never captures the view itself.
@MainActor @Observable
final class VoiceTranscript {
    var text = ""
}
