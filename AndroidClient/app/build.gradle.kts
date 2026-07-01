plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val appVersion = rootProject.file("../VERSION").readText().trim()
val versionParts = appVersion.split(".")
val computedVersionCode = versionParts[0].toInt() * 10000 + versionParts[1].toInt() * 100 + versionParts[2].toInt()
val releaseStoreFile = providers.environmentVariable("SIDESCREEN_RELEASE_STORE_FILE").orNull
val releaseStorePassword = providers.environmentVariable("SIDESCREEN_RELEASE_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("SIDESCREEN_RELEASE_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("SIDESCREEN_RELEASE_KEY_PASSWORD").orNull
val requireReleaseSigning = providers.environmentVariable("SIDESCREEN_REQUIRE_RELEASE_SIGNING").orNull == "1"
val hasReleaseSigning =
    listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
        .all { !it.isNullOrBlank() }

if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Release signing is required. Set SIDESCREEN_RELEASE_STORE_FILE, SIDESCREEN_RELEASE_STORE_PASSWORD, SIDESCREEN_RELEASE_KEY_ALIAS, and SIDESCREEN_RELEASE_KEY_PASSWORD.")
}

android {
    namespace = "com.sidescreen.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.sidescreen.app"
        minSdk = 26
        targetSdk = 34
        versionCode = computedVersionCode
        versionName = appVersion
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // Wireless mode (0.8.0)
    implementation("androidx.camera:camera-core:1.6.1")
    implementation("androidx.camera:camera-camera2:1.6.1")
    implementation("androidx.camera:camera-lifecycle:1.6.1")
    implementation("androidx.camera:camera-view:1.6.1")
    implementation("com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
