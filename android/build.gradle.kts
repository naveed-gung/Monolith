allprojects {
    repositories {
        maven {
            url = uri("../third_party/android-maven")
        }
        maven {
            url = uri("../third_party/flutter-engine-maven")
        }
        google()
        mavenCentral()
        maven {
            url = uri("https://repo1.maven.org/maven2")
        }
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

// Compatibility shims for legacy pub.dev plugins (e.g. on_audio_query_android
// 1.x, audio_session) that pin old Java targets and/or still declare `package`
// in their Android manifest instead of the AGP-8 `namespace` DSL property.
// Must be registered BEFORE any evaluationDependsOn forces subproject
// evaluation, so these hooks run (in registration order) prior to AGP's own
// afterEvaluate creating variants/tasks. Reflection is required because AGP/KGP
// types are not on the root buildscript classpath under the plugins-in-settings
// layout.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate

        // Tolerant reflective setter: AGP decorates its DSL objects and may
        // expose overloads taking either org.gradle.api.JavaVersion or a raw
        // string/object, so try each candidate until one sticks.
        fun forceSet(target: Any, methodName: String, candidates: List<Any>): Boolean {
            for (method in target.javaClass.methods.filter { it.name == methodName }) {
                for (candidate in candidates) {
                    if (runCatching { method.invoke(target, candidate) }.isSuccess) return true
                }
            }
            return false
        }

        // (a) Fill in a missing namespace so AGP 8 can create variants.
        val currentNamespace = runCatching {
            androidExtension.javaClass.methods
                .firstOrNull { it.name == "getNamespace" }
                ?.invoke(androidExtension) as? String
        }.getOrNull()
        if (currentNamespace.isNullOrEmpty()) {
            val derivedNamespace = group.toString().ifEmpty {
                "io.flutter.plugins.${name.replace('-', '_')}"
            }
            forceSet(androidExtension, "setNamespace", listOf(derivedNamespace))
        }

        // (b) Align Java bytecode target to 17 (matches :app) at the
        // extension level — the value AGP snapshots into every JavaCompile
        // task, immune to task-registration-order races.
        runCatching {
            val compileOptions = androidExtension.javaClass.methods
                .firstOrNull { it.name == "getCompileOptions" }
                ?.invoke(androidExtension)
            if (compileOptions != null) {
                val candidates = listOf(org.gradle.api.JavaVersion.VERSION_17, "17")
                forceSet(compileOptions, "setSourceCompatibility", candidates)
                forceSet(compileOptions, "setTargetCompatibility", candidates)
            }
        }

        // (c) Align Kotlin JVM target to 17 via KGP's classic `kotlinOptions`
        // extension hanging off the android extension.
        runCatching {
            val kotlinOptions = (androidExtension as? ExtensionAware)
                ?.extensions?.findByName("kotlinOptions")
            if (kotlinOptions != null) {
                forceSet(kotlinOptions, "setJvmTarget", listOf("17"))
            }
        }

        // (d) Fallback for newer KGP versions without `kotlinOptions`:
        // KotlinAndroidProjectExtension.getCompilerOptions().getJvmTarget().set().
        runCatching {
            val kotlinExtension = (androidExtension as? ExtensionAware)
                ?.extensions?.findByName("kotlin") ?: return@runCatching
            val compilerOptions = kotlinExtension.javaClass.methods
                .firstOrNull { it.name == "getCompilerOptions" }
                ?.invoke(kotlinExtension) ?: return@runCatching
            val jvmTargetProperty = compilerOptions.javaClass.methods
                .firstOrNull { it.name == "getJvmTarget" }
                ?.invoke(compilerOptions) ?: return@runCatching
            jvmTargetProperty.javaClass.methods
                .firstOrNull { it.name == "set" }
                ?.invoke(jvmTargetProperty, "17")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
