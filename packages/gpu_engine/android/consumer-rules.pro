# GpuEnginePlugin.kt asks Flutter for createHardwareBufferTexture BY NAME
# (patch 0006 alone has it, and a name keeps the app building on Flutter's
# own engine). No Java code calls it, so a release's R8 removed it from
# FlutterRenderer and the plugin then found an Anicel engine "not Anicel's"
# (board the-galaxy-tab-canvas-went-slow-on-build-1095, 검증 2026-11-24
# 01:42: the QA APK's canvas stood empty, `check failed: … no_texture`).
# Kept here, beside the one who asks, on whatever registry has it.
-keepclassmembers class * implements io.flutter.view.TextureRegistry {
    public *** createHardwareBufferTexture(android.hardware.HardwareBuffer);
}
