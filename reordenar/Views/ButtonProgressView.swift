import SwiftUI

/// A small progress view optimized for use in buttons
struct ButtonProgressView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(0.4)
            .frame(width: 12, height: 12)
    }
}

#Preview {
    HStack {
        Button("Test") {
            // Action
        }
        
        Button(action: {}) {
            HStack {
                ButtonProgressView()
                Text("Loading")
            }
        }
        
        Button(action: {}) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
        }
    }
    .padding()
} 