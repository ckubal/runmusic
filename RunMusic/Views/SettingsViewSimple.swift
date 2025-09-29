import SwiftUI

struct SettingsViewSimple: View {
    var body: some View {
        NavigationView {
            List {
                Section("test") {
                    Text("Simple test view")
                }
            }
            .navigationTitle("settings")
        }
    }
}

#Preview {
    SettingsViewSimple()
}