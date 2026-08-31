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

abstract class VerifyComposeCompilerPluginsTask : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val composeKotlinSources: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val androidModuleBuildScripts: ConfigurableFileCollection

    @get:Input
    abstract val composePluginModules: SetProperty<String>

    @TaskAction
    fun verify() {
        val composeMarkers = listOf(
            "@Composable",
            "import androidx.compose.",
            "import androidx.glance.",
            "provideContent {",
        )
        val composeModules = composeKotlinSources.files
            .filter { source ->
                val text = source.readText()
                composeMarkers.any(text::contains)
            }
            .mapNotNull { source ->
                androidModuleBuildScripts.files
                    .firstOrNull { script -> source.toPath().startsWith(script.parentFile.toPath()) }
                    ?.parentFile
                    ?.name
            }
            .toSortedSet()
        val missingPlugin = composeModules - composePluginModules.get()

        check(missingPlugin.isEmpty()) {
            "Compose compiler plugin missing from: ${missingPlugin.joinToString()}. " +
                "Every module containing Compose or Glance source must apply " +
                "org.jetbrains.kotlin.plugin.compose."
        }
    }
}

val verifyComposeCompilerPlugins = tasks.register<VerifyComposeCompilerPluginsTask>("verifyComposeCompilerPlugins") {
    group = "verification"
    description = "Fails when a module contains Compose or Glance Kotlin source without the Compose compiler plugin."
    composeKotlinSources.from(fileTree(layout.projectDirectory) { include("*/src/**/*.kt") })
    androidModuleBuildScripts.from(fileTree(layout.projectDirectory) { include("*/build.gradle.kts") })
    composePluginModules.convention(emptySet())
}

subprojects {
    val moduleName = name
    pluginManager.withPlugin("org.jetbrains.kotlin.plugin.compose") {
        verifyComposeCompilerPlugins.configure {
            composePluginModules.add(moduleName)
        }
    }
}
