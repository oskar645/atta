import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

val releaseKeystoreKeys =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

val isReleaseBuildRequested =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("Release", ignoreCase = true)
    }

if (isReleaseBuildRequested) {
    require(keystorePropertiesFile.exists()) {
        "Missing android/key.properties. Copy android/key.properties.example and fill it with your upload keystore settings before building release."
    }

    val missingReleaseKeys =
        releaseKeystoreKeys.filter { key ->
            (keystoreProperties.getProperty(key) ?: "").isBlank()
        }

    require(missingReleaseKeys.isEmpty()) {
        "android/key.properties is missing required values: ${missingReleaseKeys.joinToString(", ")}"
    }
}

android {
    namespace = "online.attomarket.atta"
    // Some AndroidX dependencies pulled in by geocoding_android now require API 34+ at compile time.
    compileSdk = maxOf(flutter.compileSdkVersion, 34)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "online.attomarket.atta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists() &&
            releaseKeystoreKeys.all { !(keystoreProperties.getProperty(it) ?: "").isBlank() }) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
