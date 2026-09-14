import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ajwadtahmid.apexlytics"
    // Ahead of flutter.compileSdkVersion (36): permission_handler_android 14.x
    // requires 37. Change only together with that dependency.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    signingConfigs {
        create("release") {
            val keyPropsFile = rootProject.file("key.properties")
            // Only fail release builds — debug builds (and any other task)
            // configure this block too, so gating on the task graph avoids
            // breaking `flutter run` on a machine with no signing set up.
            val buildingRelease = gradle.startParameter.taskNames.any {
                it.contains("Release", ignoreCase = true)
            }
            if (!keyPropsFile.exists()) {
                if (buildingRelease) {
                    throw GradleException(
                        "android/key.properties is missing — a release build would be " +
                            "unsigned. See the release runbook, or build a debug variant instead."
                    )
                }
            } else {
                val keyProps = Properties()
                keyProps.load(FileInputStream(keyPropsFile))
                storeFile = keyProps.getProperty("storeFile")?.let { path -> file(path) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.ajwadtahmid.apexlytics"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 shrink + obfuscate - cuts APK size and raises the reverse-
            // engineering bar (doesn't make the embedded client token secret;
            // abuse protection still must be server-side).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
