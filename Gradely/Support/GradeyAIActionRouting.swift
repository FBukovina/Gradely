import SwiftUI

private struct GradeyAIActionHandlerKey: EnvironmentKey {
    static let defaultValue: (GradeyAIAction, String?, UUID?) -> Void = { _, _, _ in }
}
extension EnvironmentValues {
    var requestGradeyAIAction: (GradeyAIAction, String?, UUID?) -> Void {
        get { self[GradeyAIActionHandlerKey.self] }
        set { self[GradeyAIActionHandlerKey.self] = newValue }
    }
}
