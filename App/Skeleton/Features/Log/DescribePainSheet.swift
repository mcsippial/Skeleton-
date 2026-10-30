import SwiftUI

/// Text mode: "sharp pain in my left jaw since Tuesday" → regions highlighted on the body → confirm in the log sheet.
struct DescribePainSheet: View {
    let model: BodyViewModel
    @State private var text = ""
    @State private var busy = false
    @State private var notFound = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Describe it").font(Theme.Font.title).tracking(-0.4)
                Spacer()
                Button("Cancel") { model.isDescribeSheetPresented = false }
                    .buttonStyle(.secondaryPill)
            }
            Text("Where it hurts, what it feels like and since when. You'll check everything before it's saved.")
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Color.secondaryText)
            TextField("e.g. sharp pain in my left jaw since Tuesday, 6/10", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(Theme.Font.body)
                .focused($focused)
                .padding(14)
                .glass(cornerRadius: Theme.Radius.small, rainbow: focused, tint: 0.7)
                .submitLabel(.done)
            if notFound {
                Text("Couldn't place that on the body. Try naming the area (e.g. \u{201C}lower back\u{201D}), or tap the body instead.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.redFlag)
            }
            Button(busy ? "Reading…" : "Find it on my body") {
                busy = true
                notFound = false
                Task {
                    let ok = await model.describe(text)
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
    }
}
