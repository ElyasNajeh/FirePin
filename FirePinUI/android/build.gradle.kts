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

    // tesseract_ocr 0.5.0 declares the same Android plugin class in Java and
    // Kotlin. FirePin uses its own Android OCR channel and supplies a tracked
    // no-op registration class in :app. Exclude both upstream variants so the
    // generated registrant always resolves exactly one class on every host.
    if (name == "tesseract_ocr") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
                // The published Android module has only this Java source.
                // Remove its source root before AGP creates compile inputs.
                sourceSets.getByName("main").java.setSrcDirs(emptyList<String>())
            }
            tasks.withType<JavaCompile>().configureEach {
                exclude("**/TesseractOcrPlugin.java")
            }
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
