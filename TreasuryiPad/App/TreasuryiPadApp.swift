import SwiftUI
import TreasuryKernel
import TreasuryTrading
import TreasuryUI

@main
struct TreasuryiPadApp: App {
    @State private var state: AppState? = nil
    @State private var bootError: String? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let state {
                    RootView()
                        .environment(state)
                } else if let err = bootError {
                    BootErrorView(message: err) { boot() }
                } else {
                    ProgressView("Opening ledger…")
                        .task { boot() }
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
    }

    private func boot() {
        do {
            state = try AppState.makeDefault()
            bootError = nil
        } catch {
            bootError = "\(error)"
        }
    }
}

private struct BootErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("Could not open the ledger").font(.title2.bold())
            Text(message).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
