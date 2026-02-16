import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirects build artifacts to the root build folder to keep the project clean
val newBuildDir: Directory = rootProject.layout.buildDirectory
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

/**
 * FIX: Namespace Not Specified
 * This block forces a namespace onto older Flutter plugins that haven't 
 * updated for Gradle 8.0+. It prevents the build from crashing.
 */
subprojects {
    val project = this
    val fixNamespace = Action<Project> {
        if (plugins.hasPlugin("com.android.application") || 
            plugins.hasPlugin("com.android.library")) {
            
            configure<com.android.build.gradle.BaseExtension> {
                if (namespace == null) {
                    // Fallback to the project's group name (package name)
                    namespace = project.group.toString()
                }
            }
        }
    }

    // Safety check: Apply immediately if evaluated, otherwise wait
    if (state.executed) {
        fixNamespace.execute(project)
    } else {
        afterEvaluate {
            fixNamespace.execute(project)
        }
    }
}