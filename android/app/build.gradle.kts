plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_chat_demo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_chat_demo"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Disable code shrinking to prevent icon font issues
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// Workaround: ensure Flutter tool can always find APKs under <project>/build/app/outputs/flutter-apk.
val flutterExpectedApkDir = rootProject.projectDir.resolve("../build/app/outputs/flutter-apk")

val copyDebugApkForFlutter by tasks.registering(Copy::class) {
    dependsOn("assembleDebug")
    from(layout.buildDirectory.file("outputs/apk/debug/app-debug.apk"))
    from(layout.buildDirectory.file("outputs/apk/debug/output-metadata.json"))
    into(flutterExpectedApkDir)
}

val copyReleaseApkForFlutter by tasks.registering(Copy::class) {
    dependsOn("assembleRelease")
    from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
    from(layout.buildDirectory.file("outputs/apk/release/output-metadata.json"))
    into(flutterExpectedApkDir)
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy(copyDebugApkForFlutter)
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy(copyReleaseApkForFlutter)
}
