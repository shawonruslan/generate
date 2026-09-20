import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

// v28.2: rootProject.name has a space ("Content Studio"); without an explicit group the Compose resources
// generator would emit package `content studio.desktop...` and the build fails.
group = "com.zedge.contentstudio"
version = "1.0.0"

compose.resources {
    packageOfResClass = "com.zedge.contentstudio.desktop.generated.resources"
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.addAll(
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
            "-opt-in=androidx.compose.foundation.ExperimentalFoundationApi",
            "-opt-in=androidx.compose.foundation.layout.ExperimentalLayoutApi",
            "-opt-in=androidx.compose.ui.ExperimentalComposeUiApi",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=kotlinx.coroutines.FlowPreview",
        )
    }
}

dependencies {
    implementation(compose.desktop.currentOs)
    implementation(compose.runtime)
    implementation(compose.foundation)
    implementation(compose.animation)
    implementation(compose.ui)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
    implementation(compose.components.resources)

    // Multiplatform lifecycle: ViewModel / viewModelScope / collectAsStateWithLifecycle (same API as Android)
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose:2.8.3")
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.8.3")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.json:json:20240303")
    implementation("com.github.junrar:junrar:7.5.5")

    // Media: webp/jpeg decoders, mp3 preview, inline video (libvlc when VLC is installed)
    implementation("com.twelvemonkeys.imageio:imageio-webp:3.11.0")
    implementation("com.twelvemonkeys.imageio:imageio-jpeg:3.11.0")
    implementation("com.googlecode.soundlibs:mp3spi:1.9.5.4")
    implementation("uk.co.caprica:vlcj:4.8.3")
}

compose.desktop {
    application {
        mainClass = "com.zedge.contentstudio.DesktopMainKt"
        jvmArgs += listOf("-Dfile.encoding=UTF-8", "-Dsun.java2d.uiScale.enabled=true", "-Xmx1024m")

        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Exe)
            packageName = "Meta Hawladar"
            packageVersion = "1.0.0"
            description = "Meta Hawladar - Zedge automation control panel for Windows"
            vendor = "Meta Hawladar"
            copyright = "\u00a9 2026 Meta Hawladar"
            modules("java.desktop", "java.naming", "java.net.http", "java.sql", "jdk.unsupported", "jdk.crypto.ec", "java.prefs", "java.logging", "java.management")
            appResourcesRootDir.set(project.layout.projectDirectory.dir("resources"))
            windows {
                menu = true
                menuGroup = "Meta Hawladar"
                shortcut = true
                dirChooser = true
                perUserInstall = true
                console = false
                upgradeUuid = "6e7c1b2a-3c1a-4b9e-9d3f-2c5a8f1e0b77"
                iconFile.set(project.file("icon.ico"))
            }
        }

        buildTypes.release.proguard { isEnabled.set(false) }
    }
}
