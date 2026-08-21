import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MemoryConsentCoordinator {
    private let store: MemoryStore
    var isPresented = false
    private var waiters: [CheckedContinuation<ConsentGateResult, Never>] = []

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
            waiters.append(continuation)
        }
    }

    func chooseEnabled() { finish(set: .enabled) }
    func chooseDisabled() { finish(set: .disabled) }

    private func finish(set state: MemoryConsentState) {
        guard !waiters.isEmpty else { return }
        let ok = store.setConsent(state)
        isPresented = false
        let result: ConsentGateResult = ok ? .proceed : .aborted
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume(returning: result)
        }
    }
}

struct MemoryConsentGateModifier: ViewModifier {
    @Environment(MemoryConsentCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator
        content
            .fullScreenCover(isPresented: $coordinator.isPresented, onDismiss: {
                coordinator.chooseDisabled()
            }) {
                MemoryConsentSheet(
                    onEnable: { coordinator.chooseEnabled() },
                    onDecline: { coordinator.chooseDisabled() }
                )
                .interactiveDismissDisabled(false)
            }
    }
}

extension View {
    func memoryConsentGate() -> some View {
        modifier(MemoryConsentGateModifier())
    }
}
