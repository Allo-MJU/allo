import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun quoted(v: String) = "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "ai.allo.car"
    compileSdk = 35
    defaultConfig {
        applicationId = "ai.allo.preview"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "ui-preview"
        // Local cloud-voice testing: loopback gateway + TTS_DEV_TOKEN from car/local.properties (debug only).
        buildConfigField("String", "ALLO_TTS_BASE_URL", quoted(localProps.getProperty("ALLO_TTS_BASE_URL", "")))
        buildConfigField("String", "ALLO_TTS_VOICE_REVISION", quoted(localProps.getProperty("ALLO_TTS_VOICE_REVISION", "1")))
        buildConfigField("String", "ALLO_TTS_DEV_TOKEN", quoted(localProps.getProperty("ALLO_TTS_DEV_TOKEN", "")))
    }
    sourceSets["main"].apply {
        java.srcDirs("../app/src/main/java/ai/allo/car/ui", "../app/src/main/java/ai/allo/car/model", "../app/src/main/java/ai/allo/car/dialogue", "../app/src/main/java/ai/allo/car/voice")
        res.srcDir("../app/src/main/res")
        assets.srcDirs("../../data", "../../phone/assets", "../app/src/main/assets")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.material3)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(libs.pleos.tts)
    implementation(libs.pleos.stt)
    implementation(libs.zxing.core)
}
