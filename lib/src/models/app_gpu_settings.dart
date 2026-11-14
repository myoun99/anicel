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

/// What each pixel of a GPU fx plugin's run may spend on this machine — a
/// count of the plugin's instructions, the same on every device; a run one
/// of whose pixels spends it is cut and shown as failed.
///
/// 🗣️an-endless-plugin-stalls-the-app-Q3 (유저 2026-11-08): 「설정에 두고
/// 유저가 바꾼다」 · -Q13: 열 배씩 고르는 칸 · -Q19 (11-10 16:36): 「화소
/// 하나의 몫으로 고정」 — 1만 · 10만 · 100만(기본) · 1,000만 · 1억 · -Q18
/// (11-10): 「기본은 끊고, 설정에 『끊지 않음』을 더한다」.
enum FxPluginShare {
  tenThousand(10000),
  hundredThousand(100000),
  million(1000000),
  tenMillion(10000000),
  hundredMillion(100000000),

  /// No run is cut on the device — the plugin is compiled with no count,
  /// so moving to or from this one opens the plugins again. Its reach, on
  /// the CPU, is handed all a share holds.
  uncut(null);

  const FxPluginShare(this._spends);

  final int? _spends;

  /// -Q19's 100만.
  static const FxPluginShare standard = million;

  /// Whether the device cuts a run whose pixel spends [share].
  bool get cuts => _spends != null;

  /// What a pixel may spend. ⛔[uncut] has no such thing: its run goes in
  /// the chunks [standard]'s makes — a plugin within the standard keeps
  /// the device no longer than there, and one past it may keep it longer
  /// (an-endless-plugin-stalls-the-app 11-10 16:44: chunks cannot cut an
  /// endless chunk; the driver's reset stays this choice's).
  int get share => _spends ?? standard._spends!;

  /// What the reach may spend: [share], or all a share's 32 bits hold
  /// where the device cuts nothing.
  int get reachShare => _spends ?? 0xFFFFFFFF;
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
  const AppGpuSettings({
    this.preference = AppGpuPreference.auto,
    this.pluginShare = FxPluginShare.standard,
  });

  final AppGpuPreference preference;

  /// Dart's alone: the runner reads [preference].
  final FxPluginShare pluginShare;

  AppGpuSettings copyWith({
    AppGpuPreference? preference,
    FxPluginShare? pluginShare,
  }) => AppGpuSettings(
    preference: preference ?? this.preference,
    pluginShare: pluginShare ?? this.pluginShare,
  );

  Map<String, dynamic> toJson() => {
    'preference': preference.name,
    'pluginShare': pluginShare.name,
  };

  /// A name this build does not know reads as [AppGpuPreference.auto] — as
  /// the runner reads it — and as [FxPluginShare.standard].
  static AppGpuSettings fromJson(Map<String, dynamic> json) => AppGpuSettings(
    preference:
        AppGpuPreference.values.asNameMap()[json['preference']] ??
        AppGpuPreference.auto,
    pluginShare:
        FxPluginShare.values.asNameMap()[json['pluginShare']] ??
        FxPluginShare.standard,
  );

  @override
  bool operator ==(Object other) =>
      other is AppGpuSettings &&
      other.preference == preference &&
      other.pluginShare == pluginShare;

  @override
  int get hashCode => Object.hash(preference, pluginShare);
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
