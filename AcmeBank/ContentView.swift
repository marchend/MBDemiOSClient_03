import SwiftUI

/// Root content view for AcmeBank.
/// Presents `LoginView` as the initial screen.
/// The `onSignIn` closure will be replaced with real Okta auth in a future PR.
struct ContentView: View {
    var body: some View {
        LoginView(onSignIn: { _, _ in })
    }
}

#Preview {
    ContentView()
}
