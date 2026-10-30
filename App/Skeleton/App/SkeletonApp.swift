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
            } else if let user = model.user {
                BodyScreen(app: model, userID: user.id)
                    .id(user.id)
                    .transition(.opacity)
            } else {
                SignInView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: model.user)
        .task { await model.restore() }
    }
}
