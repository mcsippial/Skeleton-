import SwiftUI

@main
struct SkeletonApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.light)
                .tint(Theme.Color.text)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            GlowBackground()
            if model.isRestoring {
                ProgressView()
            } else if model.user == nil {
                SignInView()
                    .transition(.opacity)
            } else {
                BodyScreen(data: model.data)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: model.user)
        .task { await model.restore() }
    }
}
