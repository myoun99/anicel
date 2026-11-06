import 'package:flutter/foundation.dart';

/// Which GPU the app asks the OS for when it starts — Preferences ▸ System.
///
/// 🗣️connection-round-checklist-Q4 (유저 2026-11-06): 「환경설정에 GPU 고르기를
/// 넣는다 — 자동 · 절전 · 고성능」, asked as 「gpu가 여러개일때 이 gpu쓰고싶은데
/// 같은상황에서 대응못한다거나 그러잖아」. Three, not a list of GPUs: Flutter's
/// Windows embedder takes a PREFERENCE when the engine is made
/// (`flutter::GpuPreference` in `dart_project.h`) and has no door for 「this
/// GPU」. The GPU engine follows the adapter Flutter opens (the plugin's
/// LUID), so this one answer reaches both.
enum AppGpuPreference {
  /// No preference — the OS picks, as before there was a choice.
  auto,

  /// The energy-saving GPU (an integrated one), the other when there is none.
  lowPower,

  /// The fast GPU (a discrete one), the other when there is none.
  highPerformance,
}

/// The GPU choice as its settings file holds it.
///
/// 🚨READ BEFORE DART RUNS. The engine is made by the runner, so the runner
/// reads this file itself (`windows/runner/main.cpp` — the file
/// `AppGpuSettingsStore` writes, the `preference` key, the names of
/// [AppGpuPreference]) and a change takes effect the next launch. ⛔No copy
/// of it for the runner: the settings file IS what the runner reads, so the
/// two can never say different things. `the_runner_reads_the_gpu_setting_test`
/// holds the spelling on both sides.
///
/// App state of this machine — its GPUs — so it does not travel in the
/// whole-settings file (`settingsBoundToThisMachine`).
@immutable
class AppGpuSettings {
  const AppGpuSettings({this.preference = AppGpuPreference.auto});

  final AppGpuPreference preference;

  Map<String, dynamic> toJson() => {'preference': preference.name};

  /// A name this build does not know reads as [AppGpuPreference.auto] — as
  /// the runner reads it.
  static AppGpuSettings fromJson(Map<String, dynamic> json) => AppGpuSettings(
    preference:
        AppGpuPreference.values.asNameMap()[json['preference']] ??
        AppGpuPreference.auto,
  );

  @override
  bool operator ==(Object other) =>
      other is AppGpuSettings && other.preference == preference;

  @override
  int get hashCode => preference.hashCode;
}

/// The app-wide GPU choice, on the same idiom as `AppMemory.settings`.
abstract final class AppGpu {
  static final ValueNotifier<AppGpuSettings> settings =
      ValueNotifier<AppGpuSettings>(const AppGpuSettings());

  /// What this run's engine was made with: the choice as the settings file
  /// first held it — the file the runner read before Dart ran. Null until
  /// that first restore lands.
  static AppGpuPreference? get startedWith => _startedWith;
  static AppGpuPreference? _startedWith;

  /// Takes [preference] as [startedWith] — once a run; a later restore (a
  /// settings file read back) is not what the engine was made with.
  static void noteStartedWith(AppGpuPreference preference) =>
      _startedWith ??= preference;

  /// Whether this platform's Flutter takes a GPU preference at all. Only the
  /// Windows embedder has the door (2026-11-06, the Flutter engine source on
  /// this machine): the macOS one picks the unified-memory GPU first
  /// (`FlutterRenderer.mm`'s `SelectMetalDevice`) and the Linux one takes the
  /// GPU the graphics driver gives its EGL display. 🗣️Elsewhere the row
  /// stands dimmed, its reason in its tooltip (gpu-choice-in-preferences-Q1,
  /// 유저 2026-11-06: 「맥 · 리눅스에도 줄은 두되 흐리게(고를 수 없음)」 ·
  /// 「호버 툴팁으로 이유 표시」).
  static bool get choosableHere =>
      defaultTargetPlatform == TargetPlatform.windows;

  @visibleForTesting
  static void debugReset() {
    settings.value = const AppGpuSettings();
    _startedWith = null;
  }
}
