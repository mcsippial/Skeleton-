import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var createAccount = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Skeleton").titleStyle()
                Text("See where your pain moves, and why.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            PillSegmentedControl(options: [(value: false, title: "Sign in"), (value: true, title: "Create account")], selection: $createAccount)

            VStack(spacing: 10) {
                field("Email", text: $email, secure: false)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                field("Password", text: $password, secure: true)
                    .textContentType(createAccount ? .newPassword : .password)
            }

            if let error {
                Text(error).font(Theme.Font.caption).foregroundStyle(Theme.Color.redFlag)
            }

            Button(createAccount ? "Create account" : "Sign in") { submit() }
                .buttonStyle(.primaryPill)
                .disabled(busy || email.isEmpty || password.isEmpty)

            if model.isDemoMode {
                Button("Continue with demo data") {
                    Task { await model.continueAsDemo() }
                }
                .buttonStyle(.secondaryPill)
                .frame(maxWidth: .infinity)
                Text("Demo mode: no backend keys are set, so sign-in is simulated on this device.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer()
            Text("Skeleton shows patterns and possible contributors, not a diagnosis. It is not medical advice; see a professional about your pain.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
        }
        .font(Theme.Font.body)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glass(cornerRadius: Theme.Radius.small, tint: 0.7)
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.signIn(email: email, password: password, createAccount: createAccount)
            } catch AuthError.confirmEmail(let address) {
                self.error = AuthError.confirmEmail(address).localizedDescription
                createAccount = false
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
