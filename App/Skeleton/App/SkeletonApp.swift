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
                switch model.profileState {
                case .unknown:
                    ProgressView()
                case .missing:
                    OnboardingView(userID: user.id, existing: nil)
                        .transition(.opacity)
                case .failed(let message):
                    VStack(spacing: Theme.Spacing.m) {
                        Text("Couldn't load your profile.").font(Theme.Font.headline)
                        Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Color.secondaryText)
                        Button("Try again") { Task { await model.loadProfile() } }.buttonStyle(.primaryPill)
                    }
                    .padding(Theme.Spacing.l)
                case .loaded(let profile):
                    // Re-created when proportions change, so the body is rebuilt to fit.
                    MainView(app: model, profile: profile)
                        .id(profile)
                        .transition(.opacity)
                }
            } else {
                SignInView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: model.user)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: model.profileState)
        .task { await model.restore() }
    }
}
