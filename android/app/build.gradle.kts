import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The key lives outside the repository, in
// ~/.tcode-release/key.properties (override with TCODE_SIGNING=/path/to/file).
// Without it, release builds fall back to the debug key, so anyone who clones
// the project can still build and run it. Only the published APKs need the
// real key: Android refuses an update signed with a different one.
val signingFile = file(
    System.getenv("TCODE_SIGNING")
        ?: "${System.getProperty("user.home")}/.tcode-release/key.properties",
)
val signing = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}

android {
    namespace = "dev.tcode.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.tcode.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signing.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Two distribution channels with genuinely different storage permissions.
    //
    //  play — what goes to Google Play. Reaches files outside the app sandbox
    //         only through the Storage Access Framework, so it needs no broad
    //         storage permission at all. Play restricts MANAGE_EXTERNAL_STORAGE
    //         to a narrow set of app categories, and a code editor is not one.
    //
    //  full — for direct APK distribution. Everything `play` has, plus an
    //         opt-in "All files access" mode behind an explanation screen,
    //         which lets the faster dart:io provider serve arbitrary paths.
    //
    // The permission lives only in the `full` source set's manifest, so it
    // cannot leak into the Play build by accident.
    flavorDimensions += "distribution"

    productFlavors {
        create("play") {
            dimension = "distribution"
            // No applicationIdSuffix: this is the canonical package id.
        }
        create("full") {
            dimension = "distribution"
            // A distinct id so both builds can be installed side by side while
            // testing, and so a sideloaded build never overwrites a Play one.
            applicationIdSuffix = ".full"
            versionNameSuffix = "-full"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
