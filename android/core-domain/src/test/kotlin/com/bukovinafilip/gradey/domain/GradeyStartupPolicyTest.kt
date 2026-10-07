package com.bukovinafilip.gradey.domain

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class GradeyStartupPolicyTest {
    @Test
    fun `configured cloud requires an explicit account or guest choice`() {
        assertThat(destination(cloud = true, guest = false, auth = false, school = true))
            .isEqualTo(GradeyStartupDestination.SIGNED_OUT)
    }

    @Test
    fun `persisted guest mode bypasses cloud without discarding school`() {
        assertThat(destination(cloud = true, guest = true, auth = false, school = true))
            .isEqualTo(GradeyStartupDestination.SIGNED_IN)
        assertThat(destination(cloud = true, guest = true, auth = false, school = false))
            .isEqualTo(GradeyStartupDestination.NEEDS_SCHOOL)
    }

    @Test
    fun `local-only builds never require a cloud session`() {
        assertThat(destination(cloud = false, guest = false, auth = false, school = true))
            .isEqualTo(GradeyStartupDestination.SIGNED_IN)
        assertThat(destination(cloud = false, guest = false, auth = false, school = false))
            .isEqualTo(GradeyStartupDestination.NEEDS_SCHOOL)
    }

    @Test
    fun `Gradey ID session still requires a school before the app shell`() {
        assertThat(destination(cloud = true, guest = false, auth = true, school = false))
            .isEqualTo(GradeyStartupDestination.NEEDS_SCHOOL)
        assertThat(destination(cloud = true, guest = false, auth = true, school = true))
            .isEqualTo(GradeyStartupDestination.SIGNED_IN)
    }

    private fun destination(
        cloud: Boolean,
        guest: Boolean,
        auth: Boolean,
        school: Boolean,
    ) = selectGradeyStartupDestination(
        isCloudConfigured = cloud,
        isGuestMode = guest,
        hasGradeySession = auth,
        hasSchoolSession = school,
    )
}
