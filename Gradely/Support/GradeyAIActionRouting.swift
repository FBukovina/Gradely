import SwiftUI

/// Gradey AI is switched off while it moves from Microsoft Azure OpenAI to
/// the OpenAI API (November 2026). `false` hides every AI entry point on
/// iPhone, iPad and Mac and skips the AI backend calls; the Watch has its own
/// copy in GradelyWatch/ContentView.swift. Flip both back together.
enum GradeyAIAvailability {
    static let isEnabled = false
}

private struct GradeyAIActionHandlerKey: EnvironmentKey {
    static let defaultValue: (GradeyAIAction, String?, UUID?) -> Void = { _, _, _ in }
}
extension EnvironmentValues {
    var requestGradeyAIAction: (GradeyAIAction, String?, UUID?) -> Void {
        get { self[GradeyAIActionHandlerKey.self] }
        set { self[GradeyAIActionHandlerKey.self] = newValue }
    }
}
