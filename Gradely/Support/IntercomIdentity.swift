import Foundation
#if os(iOS) && canImport(Intercom)
import Intercom
#endif

enum IntercomIdentity {
    static func loginUnidentified() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured, AgeAttestationStore.allowsAppUse() else { return }
        Intercom.loginUnidentifiedUser { _ in }
        #endif
    }

    static func identify(account: GradeyAccount) {
        identify(userID: account.id, email: account.email, name: account.fullName)
    }

    static func identify(userID _: String, email _: String?, name _: String?) {
        // Intercom Messenger Security (JWT / identity verification) rejects
        // identified iOS sessions that have no user_hash/JWT. That shows
        // "Something's gone wrong / Content could not be loaded" on device.
        // Stay unidentified until a server-issued JWT exists.
        loginUnidentified()
    }

    static func reset() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured else { return }
        if Intercom.isUserLoggedIn() {
            Intercom.logout()
        }
        #endif
    }

    static func presentMessenger() {
        #if os(iOS) && canImport(Intercom)
        guard IntercomConfiguration.isConfigured, AgeAttestationStore.allowsAppUse() else { return }
        if Intercom.isUserLoggedIn() {
            Intercom.logout()
        }
        Intercom.loginUnidentifiedUser { result in
            DispatchQueue.main.async {
                guard case .success = result else { return }
                Intercom.present()
            }
        }
        #endif
    }
}
