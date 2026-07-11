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
}

subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null && android.namespace == null) {
            android.namespace = "com.example.${project.name.replace("-", ".")}"
        }
    }
    plugins.withId("com.android.application") {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null && android.namespace == null) {
            android.namespace = "com.example.${project.name.replace("-", ".")}"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            val targetCompatibilityVersion = android.compileOptions.targetCompatibility
            if (targetCompatibilityVersion != null) {
                val jvmTargetValue = when (targetCompatibilityVersion) {
                    JavaVersion.VERSION_1_8 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    JavaVersion.VERSION_11 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                    JavaVersion.VERSION_17 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                    JavaVersion.VERSION_21 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
                    else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                }
                compilerOptions {
                    jvmTarget.set(jvmTargetValue)
                }
            }
        }
    }
}

