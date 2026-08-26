import Foundation
import Testing
@testable import Gradely

struct IntercomConfigurationTests {
    @Test func credentialsRequireApiKeyAndAppID() {
        #expect(
            IntercomConfiguration.credentials(from: [
                "IntercomIOSAPIKey": "",
                "IntercomAppID": "hmnqm0t6"
            ]) == nil
        )
        #expect(
            IntercomConfiguration.credentials(from: [
                "IntercomIOSAPIKey": "$(INTERCOM_IOS_API_KEY)",
                "IntercomAppID": "hmnqm0t6"
            ]) == nil
        )
        #expect(
            IntercomConfiguration.credentials(from: [
                "IntercomIOSAPIKey": "ios_sdk-local-placeholder",
                "IntercomAppID": ""
            ]) == nil
        )

        let credentials = IntercomConfiguration.credentials(from: [
            "IntercomIOSAPIKey": " ios_sdk-local-placeholder ",
            "IntercomAppID": " hmnqm0t6 "
        ])
        #expect(credentials?.apiKey == "ios_sdk-local-placeholder")
        #expect(credentials?.appID == "hmnqm0t6")
    }

    @Test func messengerHelpersAreSafeBeforeConfiguration() {
        IntercomIdentity.presentMessenger()
        IntercomIdentity.loginUnidentified()
        IntercomIdentity.reset()
    }

    @Test func unidentifiedLoginRequiresAgeAttestation() throws {
        #expect(!AgeAttestationKind.underThirteen.allowsAppUse)
        #expect(AgeAttestationKind.sixteenOrOlder.allowsAppUse)
        #expect(AgeAttestationKind.thirteenToFifteenWithParent.allowsAppUse)
    }
}
