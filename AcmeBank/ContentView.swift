import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("AcmeBank")
            .font(.largeTitle)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
