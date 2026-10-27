import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// TimeBlockKit in Kotlin: plain JVM code, no Android, so it's tested on the JVM and the app depends on it as is.
plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    // The fixtures the Swift tests read too; `-PwriteFixtures` writes this app's again.
    systemProperty("fixtures", rootDir.resolve("../fixtures").absolutePath)
    if (project.hasProperty("writeFixtures")) systemProperty("writeFixtures", "true")
    outputs.upToDateWhen { !project.hasProperty("writeFixtures") }
}
