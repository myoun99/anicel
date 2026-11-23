// 🚨THE APP IS BUILT ON ANICEL'S FLUTTER ENGINE, AND THIS IS THE ONE PLACE
// IT IS TAKEN FROM (🗣️관제 2026-11-24 00:3x, card the-galaxy-tab-canvas-went-
// slow-on-build-1095: the control tower's Play bundle, the user's Studio
// build and CI find it by the same code). The Android engine carries patch
// tool/flutter_engine/android_patch (0006: a texture shown from the hardware
// buffers its producer keeps); the Flutter plugin asks for the stock engine
// (`io.flutter:<module>_<mode>:1.0.0-<engine.stamp>`, FlutterPluginUtils.kt)
// and the embedding and each ABI's library are put on the patched engine's
// own version here, 1.0.0-<engine.stamp>-anicel.<patch>.
//
// 🚨EVERY ABI A BUILD SHIPS, OR NONE: the plugin clears the app's abiFilters
// and ships every ABI it targets (FlutterPlugin.kt configureAbiWithoutSplits
// — `flutter build` targets armeabi-v7a, arm64-v8a and x86_64 unless told
// otherwise), and the patched embedding calls a native the stock library has
// not got. 🔬공통 2026-11-24 01:2x: fb3a4010b's `flutter build apk --release`
// shipped arm64-v8a patched and the other two stock under the patched
// embedding. So a mode whose embedding is laid takes each ABI's library from
// the laid ones only, and one not laid stops the build by name — bake that
// ABI, or build only the ABIs laid (`--target-platform android-arm64`).
//
// ⛔NOT THE STOCK COORDINATES (관제 00:32): under them the stock jar a Gradle
// cache already holds could win without a word; under its own name a build
// that finds no patched engine fails by that name.
//
// WHERE: <Dropbox>/anicel-flutter-engine/maven, the folder Dropbox names in
// its info.json — the one folder both machines that build the app already
// sync (관제 00:3x: 「두 기계가 이미 같이 쓰는 폴더」). Laid there by
// tool/flutter_engine/lay_android.sh from a baked out folder.
//
// NONE LAID: a release fails (a Play bundle on the stock engine shows no
// canvas); a debug build warns and takes the stock engine — the plugin finds
// the patched method by name and says no by name (공통 5945e9733), so CI's
// `flutter build apk --debug`, which syncs no Dropbox, still compiles.
// 🗣️보드/인프라 · 공통 2026-11-24 00:29 / 00:33: what ships is stopped, the
// compile check lives.
val anicelEngineModules =
    setOf("flutter_embedding", "armeabi_v7a", "arm64_v8a", "x86_64")

fun anicelSharedFolder(): File? {
    val infos =
        listOfNotNull(
            System.getenv("LOCALAPPDATA")?.let { File(it, "Dropbox/info.json") },
            System.getenv("APPDATA")?.let { File(it, "Dropbox/info.json") },
            File(System.getProperty("user.home"), ".dropbox/info.json"),
        )
    val info = infos.firstOrNull { it.isFile } ?: return null
    val read = groovy.json.JsonSlurper().parse(info) as? Map<*, *> ?: return null
    val path = (read["personal"] as? Map<*, *>)?.get("path") as? String
    return path?.let { File(it, "anicel-flutter-engine/maven") }
}

val anicelEngineRepo: File? = anicelSharedFolder()?.takeIf { it.isDirectory }

val anicelEngineVersion: String =
    run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val sdk = File(properties.getProperty("flutter.sdk"))
        val stamp = File(sdk, "bin/cache/engine.stamp").readText().trim()
        val patch = file("../tool/flutter_engine/android_patch").readText().trim()
        "1.0.0-$stamp-anicel.$patch"
    }

fun anicelEngineLaid(name: String): Boolean =
    anicelEngineRepo != null &&
        File(
            anicelEngineRepo,
            "io/flutter/$name/$anicelEngineVersion/$name-$anicelEngineVersion.pom",
        ).isFile

var anicelStockSaid = false

allprojects {
    repositories {
        anicelEngineRepo?.let { repo ->
            exclusiveContent {
                forRepository { maven { url = repo.toURI() } }
                filter { includeVersionByRegex("io\\.flutter", ".*", ".*-anicel\\..*") }
            }
        }
        google()
        mavenCentral()
    }
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            val mode = requested.name.substringAfterLast('_')
            val module = requested.name.removeSuffix("_$mode")
            if (requested.group != "io.flutter" || module !in anicelEngineModules) {
                return@eachDependency
            }
            val embeddingLaid = anicelEngineLaid("flutter_embedding_$mode")
            when {
                embeddingLaid && anicelEngineLaid(requested.name) ->
                    useVersion(anicelEngineVersion)
                embeddingLaid ->
                    throw GradleException(
                        "no io.flutter:${requested.name}:$anicelEngineVersion in " +
                            "$anicelEngineRepo — its stock library would ship under " +
                            "Anicel's embedding; lay that ABI's bake " +
                            "(tool/flutter_engine/lay_android.sh) or build only the " +
                            "ABIs laid (--target-platform android-arm64)",
                    )
                mode == "release" ->
                    throw GradleException(
                        "no io.flutter:${requested.name}:$anicelEngineVersion in " +
                            "${anicelEngineRepo ?: "<Dropbox>/anicel-flutter-engine/maven"}" +
                            " — a release is built on Anicel's engine only; lay it " +
                            "with tool/flutter_engine/lay_android.sh",
                    )
                !anicelStockSaid -> {
                    anicelStockSaid = true
                    logger.warn(
                        "⚠️the STOCK Flutter engine ($mode): no $anicelEngineVersion " +
                            "laid — the app shows no canvas on Android " +
                            "(tool/flutter_engine/lay_android.sh)",
                    )
                }
            }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
