import Foundation
import Observation

enum SupportTipLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
@Observable
final class SupportTipViewModel {
    var loadState: SupportTipLoadState = .idle
    var tips: [SupportTipOption] = []
    var purchasingTipID: String?
    var purchaseErrorMessage: String?
    var didCompletePurchase = false

    private let supportTipProvider: any SupportTipProviding
    private var hasLoaded = false

    init(supportTipProvider: any SupportTipProviding) {
        self.supportTipProvider = supportTipProvider
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        hasLoaded = true
        loadState = .loading
        purchaseErrorMessage = nil
        didCompletePurchase = false

        do {
            tips = try await supportTipProvider.loadTips()
            loadState = tips.isEmpty ? .empty : .loaded
        } catch {
            tips = []
            loadState = .failed(userFacingMessage(for: error))
        }
    }

    func purchase(_ tip: SupportTipOption) async {
        guard purchasingTipID == nil else { return }

        purchasingTipID = tip.id
        purchaseErrorMessage = nil
        defer { purchasingTipID = nil }

        do {
            let outcome = try await supportTipProvider.purchase(tip)
            if outcome == .success {
                didCompletePurchase = true
            }
        } catch {
            purchaseErrorMessage = userFacingMessage(for: error)
        }
    }

    func dismissThankYou() {
        didCompletePurchase = false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let message = localizedError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
