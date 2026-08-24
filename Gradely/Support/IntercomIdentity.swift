import Foundation
#if os(iOS) && canImport(Intercom)
import Intercom
#endif

enum IntercomIdentity {
    static func loginUnidentified() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured else { return }
        Intercom.loginUnidentifiedUser { _ in }
        #endif
    }

    static func identify(account: GradeyAccount) {
        identify(userID: account.id, email: account.email, name: account.fullName)
    }

    static func identify(userID: String, email: String?, name: String?) {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured else { return }
        let trimmedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        let attributes = ICMUserAttributes()
        attributes.userId = trimmedID
        if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            attributes.email = email
        }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            attributes.name = name
        }

        Intercom.loginUser(with: attributes) { _ in }
        #endif
    }

    static func reset() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured else { return }
        if Intercom.isUserLoggedIn {
            let attributes = Intercom.fetchLoggedInUserAttributes()
            if attributes?.userId != nil || attributes?.email != nil {
                Intercom.logout()
            }
        }
        loginUnidentified()
        #endif
    }

    static func presentMessenger() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured else { return }
        Intercom.present()
        #endif
    }
}
