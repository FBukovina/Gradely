import Foundation

extension PreviewData {
    static let gradeyAccount = GradeyAccount(
        id: "preview-gradey-user",
        email: "student@example.com",
        fullName: "Preview Student",
        avatarURL: nil,
        createdAt: Date(timeIntervalSince1970: 1_756_000_000)
    )

    static let gradeyAuthSession = GradeyAuthSession(
        accessToken: "preview-gradey-access",
        refreshToken: "preview-gradey-refresh",
        tokenType: "Bearer",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        account: gradeyAccount
    )

    static let linkedSchoolAccount = LinkedAccount(
        id: "preview-school",
        provider: .bakalari,
        providerUserID: "preview-student",
        displayName: "Preview Student",
        schoolName: "Demo Gymnazium",
        canteenName: nil,
        status: .active,
        notificationsEnabled: true,
        lastPolledAt: nil,
        lastSyncedAt: Date(timeIntervalSince1970: 1_756_001_000),
        actionRequiredReason: nil
    )
}
