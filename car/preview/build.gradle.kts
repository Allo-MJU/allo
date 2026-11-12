plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "ai.allo.car"
    compileSdk = 35
    defaultConfig {
        applicationId = "ai.allo.preview"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "ui-preview"
    }
    sourceSets["main"].apply {
        java.srcDirs("../app/src/main/java/ai/allo/car/ui", "../app/src/main/java/ai/allo/car/model", "../app/src/main/java/ai/allo/car/dialogue")
        res.srcDir("../app/src/main/res")
        assets.srcDirs("../../data", "../../phone/assets")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
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
    implementation(libs.zxing.core)
}
