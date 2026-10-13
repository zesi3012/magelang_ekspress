import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    FileInputStream(signingPropertiesFile).use(signingProperties::load)
}

val requestedReleaseBundle = gradle.startParameter.taskNames.any { task ->
    task.contains("release", ignoreCase = true) &&
        (task.contains("bundle", ignoreCase = true) ||
            task.contains("assemble", ignoreCase = true))
}
val playStoreApplicationId = System.getenv("MAGELANG_APPLICATION_ID")
if (requestedReleaseBundle && playStoreApplicationId.isNullOrBlank()) {
    throw GradleException(
        "Set MAGELANG_APPLICATION_ID to the permanent Play Store package ID before building a release.",
    )
}
if (requestedReleaseBundle && !signingPropertiesFile.exists()) {
    throw GradleException(
        "Create android/key.properties with the Play upload keystore before building a release.",
    )
}

android {
    namespace = "com.example.magelang_express"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = playStoreApplicationId ?: "com.example.magelang_express"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (signingPropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                val storePath = signingProperties.getProperty("storeFile")
                    ?: throw GradleException("key.properties is missing storeFile.")
                storeFile = rootProject.file(storePath)
                storePassword = signingProperties.getProperty("storePassword")
                    ?: throw GradleException("key.properties is missing storePassword.")
                keyAlias = signingProperties.getProperty("keyAlias")
                    ?: throw GradleException("key.properties is missing keyAlias.")
                keyPassword = signingProperties.getProperty("keyPassword")
                    ?: throw GradleException("key.properties is missing keyPassword.")
            }
        }
    }

    buildTypes {
        release {
            if (signingPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
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
