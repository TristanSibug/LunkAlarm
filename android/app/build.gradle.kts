import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "online.reeeserve.lunkalarm"
    compileSdk = 36
    defaultConfig {
        applicationId = "online.reeeserve.lunkalarm"
        minSdk = 26
        targetSdk = 36
        versionCode = providers.gradleProperty("lunkVersionCode").orNull?.toInt() ?: 5
        versionName = providers.gradleProperty("lunkVersionName").orNull ?: "1.3.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    androidResources { noCompress += "wav" }
    val signingPath = System.getenv("LUNK_ANDROID_SIGNING_PROPERTIES")
    if (System.getenv("LUNK_ANDROID_REQUIRE_SIGNING") == "true" && signingPath == null) {
        error("Permanent signing is required. Run prepare_signing.py with ANDROID_SIGNING_BUNDLE first.")
    }
    signingConfigs.getByName("debug") {
        if (signingPath != null) {
            val signing = Properties().apply { file(signingPath).reader(Charsets.UTF_8).use { load(it) } }
            storeFile = file(signing.getProperty("storeFile"))
            storePassword = signing.getProperty("storePassword")
            keyPassword = signing.getProperty("keyPassword")
            keyAlias = signing.getProperty("keyAlias")
        } else {
            System.getenv("LUNK_ANDROID_KEYSTORE")?.let { storeFile = file(it) }
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildTypes { release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.10.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:rules:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
