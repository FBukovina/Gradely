plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt.android) apply false
    alias(libs.plugins.google.services) apply false
}

val localBuildRoot = File(System.getProperty("user.home"), "Library/Caches/GradeyAndroid-build")

allprojects {
    val projectBuildPath = if (path == ":") "root" else path.removePrefix(":").replace(':', '/')
    layout.buildDirectory.set(localBuildRoot.resolve(projectBuildPath))
}

tasks.register<Delete>("clean") {
    delete(localBuildRoot)
}
