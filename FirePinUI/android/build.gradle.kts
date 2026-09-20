allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // tesseract_ocr 0.5.0 leaves Java at 1.8 while its Kotlin compilation is
    // inherited as JVM 17 by the current toolchain. Align only that legacy
    // plugin so Android builds remain reproducible; FirePin bypasses its
    // runtime channel on Android in favor of the checked app-owned channel.
    if (name == "tesseract_ocr") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
            // The published archive contains Java and Kotlin classes with the
            // exact same fully-qualified name. Keep the functional Java
            // implementation and exclude the unused template Kotlin class.
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
                .configureEach {
                    exclude("**/TesseractOcrPlugin.kt")
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
