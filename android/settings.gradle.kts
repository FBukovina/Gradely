pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "GradeyAndroid"

include(
    ":app",
    ":core-model",
    ":core-domain",
    ":core-network",
    ":core-data",
    ":core-ui",
    ":feature-auth",
    ":feature-login",
    ":feature-today",
    ":feature-subjects",
    ":feature-absence",
    ":feature-timetable",
    ":feature-stravacz",
    ":feature-account",
    ":glance-widgets",
    ":wear",
)
