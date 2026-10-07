import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

abstract class SyncGradeyDisplayFontTask : DefaultTask() {
    @get:InputFile
    abstract val sourceFont: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun syncFont() {
        val target = outputDirectory.file("font/space_grotesk_bold.ttf").get().asFile
        target.parentFile.mkdirs()
        sourceFont.get().asFile.copyTo(target, overwrite = true)
    }
}

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

val syncGradeyDisplayFont = tasks.register<SyncGradeyDisplayFontTask>("syncGradeyDisplayFont") {
    sourceFont.set(rootProject.layout.projectDirectory.file("../Gradely/Resources/SpaceGrotesk-Bold.ttf"))
    outputDirectory.set(layout.buildDirectory.dir("generated/gradey-font-resources"))
}

android {
    namespace = "com.bukovinafilip.gradey.ui"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

androidComponents {
    onVariants(selector().all()) { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(
            syncGradeyDisplayFont,
            SyncGradeyDisplayFontTask::outputDirectory,
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(project(":core-model"))
    implementation(project(":core-domain"))
    implementation(enforcedPlatform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    testImplementation(libs.junit)
    androidTestImplementation(enforcedPlatform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
}
