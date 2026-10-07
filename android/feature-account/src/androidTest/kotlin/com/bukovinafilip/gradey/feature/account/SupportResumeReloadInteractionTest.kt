package com.bukovinafilip.gradey.feature.account

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bukovinafilip.gradey.ui.GradeyTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SupportResumeReloadInteractionTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun reloadsOnceInitiallyAndAgainOnlyAfterReturningFromPause() {
        val lifecycleOwner = FakeLifecycleOwner()
        val reloadCount = AtomicInteger()

        composeRule.setContent {
            CompositionLocalProvider(LocalLifecycleOwner provides lifecycleOwner) {
                GradeyTheme {
                    SupportScreen(
                        catalog = null,
                        isSignedIn = true,
                        isConfigured = true,
                        isLoading = false,
                        purchasingOptionID = null,
                        isRestoring = false,
                        message = null,
                        appVersion = "1.0",
                        appBuild = "1",
                        onBack = {},
                        onReload = { reloadCount.incrementAndGet() },
                        onPurchasePlan = {},
                        onPurchaseTip = {},
                        onRestore = {},
                        onManageSubscription = {},
                        onOpenHelpCenter = {},
                        onEmailDeveloper = {},
                        onOpenGitHub = {},
                        onOpenPrivacyPolicy = {},
                        onOpenTermsOfUse = {},
                        onOpenOpenSide = {},
                        onEmailGraphics = {},
                        onClearCache = {},
                        onRestartOnboarding = {},
                        onOpenDeveloperInstagram = {},
                    )
                }
            }
        }

        composeRule.waitForIdle()
        assertEquals(1, reloadCount.get())

        composeRule.runOnIdle {
            lifecycleOwner.handle(Lifecycle.Event.ON_CREATE)
            lifecycleOwner.handle(Lifecycle.Event.ON_START)
            lifecycleOwner.handle(Lifecycle.Event.ON_RESUME)
        }
        assertEquals(1, reloadCount.get())

        composeRule.runOnIdle {
            lifecycleOwner.handle(Lifecycle.Event.ON_PAUSE)
            lifecycleOwner.handle(Lifecycle.Event.ON_STOP)
            lifecycleOwner.handle(Lifecycle.Event.ON_START)
            lifecycleOwner.handle(Lifecycle.Event.ON_RESUME)
        }
        assertEquals(2, reloadCount.get())
    }

    private class FakeLifecycleOwner : LifecycleOwner {
        private val registry = LifecycleRegistry(this)

        override val lifecycle: Lifecycle = registry

        fun handle(event: Lifecycle.Event) {
            registry.handleLifecycleEvent(event)
        }
    }
}
