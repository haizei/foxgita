import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MemoryConsentCoordinator {
    private let store: MemoryStore
    var isPresented = false
    private var waiter: CheckedContinuation<ConsentGateResult, Never>?

    init(store: MemoryStore) {
        self.store = store
    }

    func ensureDecided() async -> ConsentGateResult {
        store.reload()
        if store.consent == .enabled || store.consent == .disabled {
            return .proceed
        }
        isPresented = true
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func chooseEnabled() { finish(set: .enabled) }
    func chooseDisabled() { finish(set: .disabled) }

    private func finish(set state: MemoryConsentState) {
        guard waiter != nil else { return }
        let ok = store.setConsent(state)
        isPresented = false
        waiter?.resume(returning: ok ? .proceed : .aborted)
        waiter = nil
    }
}

struct MemoryConsentGateModifier: ViewModifier {
    @Environment(MemoryConsentCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator
        content
            .sheet(isPresented: $coordinator.isPresented, onDismiss: {
                coordinator.chooseDisabled()
            }) {
                MemoryConsentSheet(
                    onEnable: { coordinator.chooseEnabled() },
                    onDecline: { coordinator.chooseDisabled() }
                )
            }
    }
}

extension View {
    func memoryConsentGate() -> some View {
        modifier(MemoryConsentGateModifier())
    }
}
