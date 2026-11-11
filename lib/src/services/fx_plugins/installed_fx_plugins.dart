import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/app_gpu_settings.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/project.dart';
import '../../native/gpu_fx_plugin.dart';
import '../project_lookup.dart' show projectLayersAnywhere;
import 'fx_plugin_bundle.dart';
import 'fx_plugin_library_service.dart';
import 'fx_plugin_outcomes.dart';

/// Opens a plugin's file on the device to see that it would run: null
/// where it opens, the engine's words of why not where it does not.
typedef FxPluginChecker = String? Function(FxPluginBundle bundle);

/// Opens [plugin], as [library] keeps it, to run — null where it will not
/// open.
typedef FxPluginOpener =
    FxPluginRunner? Function(
      InstalledFxPlugin plugin,
      FxPluginLibraryService library,
    );

/// Asks the person whether to install the plugin that says [description]
/// of itself — [replacing]: the version of it this device has now.
typedef FxPluginConfirm =
    Future<bool> Function(
      FxPluginDescription description, {
      required FxPluginDescription? replacing,
    });

/// What installing a plugin's file came to.
sealed class FxPluginInstall {
  const FxPluginInstall();
}

/// No plugin's file, or one whose description is not a whole one.
final class FxPluginUnreadable extends FxPluginInstall {
  const FxPluginUnreadable();
}

/// The engine would not open its WGSL — [why], in the engine's words.
final class FxPluginUnopened extends FxPluginInstall {
  const FxPluginUnopened(this.why);
  final String why;
}

/// The person said no.
final class FxPluginDeclined extends FxPluginInstall {
  const FxPluginDeclined();
}

/// Installed — in place of the version [replaced], where there was one.
final class FxPluginInstalled extends FxPluginInstall {
  const FxPluginInstalled(this.description, {this.replaced});
  final FxPluginDescription description;
  final FxPluginDescription? replaced;
}

/// THE FX PLUGINS INSTALLED ON THIS DEVICE (I-132), as the app reads them:
/// the list, and installing one more from its file.
///
/// The files and their index are [FxPluginLibraryService]'s. A plugin says
/// who it is in its description, and is opened on the device — checked,
/// its loops counted, compiled — before it is shown to the person; nothing
/// is kept before they say yes (fx spec 2).
class InstalledFxPlugins extends ChangeNotifier {
  InstalledFxPlugins({
    FxPluginLibraryService? service,
    FxPluginChecker? check,
    FxPluginOpener? open,
  }) : _service = service ?? FxPluginLibraryService(),
       _check = check ?? checkFxPluginOnTheDevice,
       _open = open ?? openInstalledFxPlugin {
    AppGpu.settings.addListener(_onGpuSettings);
  }

  final FxPluginLibraryService _service;
  final FxPluginChecker _check;
  final FxPluginOpener _open;

  /// The plugins opened to run, by id — one that would not open kept as
  /// such ([_Unopened]), so it is not tried again each frame.
  final Map<String, FxPluginRunner> _runners = {};
  List<InstalledFxPlugin> _plugins = const [];
  bool _disposed = false;

  /// Whether the plugins [_runners] holds were opened to be cut.
  bool _openedCutting = AppGpu.settings.value.pluginShare.cuts;

  /// 🗣️an-endless-plugin-stalls-the-app-Q18 「끊지 않음」: a plugin is
  /// compiled with its count or without it, so moving to or from that
  /// choice lets every opened one go — each opens again, the new way, the
  /// next time a frame asks it.
  void _onGpuSettings() {
    final cuts = AppGpu.settings.value.pluginShare.cuts;
    if (cuts == _openedCutting) {
      return;
    }
    _openedCutting = cuts;
    for (final id in [..._runners.keys]) {
      _letGo(id);
    }
    notifyListeners();
  }

  Future<void>? _loading;

  /// In the order they were installed.
  List<InstalledFxPlugin> get plugins => _plugins;

  /// Reads which plugins this device has — once: a caller after the first
  /// waits for the same read, as [missingFrom] does.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final plugins = await _service.loadIndex();
    if (_disposed) {
      return;
    }
    _plugins = plugins;
    notifyListeners();
  }

  /// Whether this device has [plugin]: one of its id, whatever its
  /// version — as an install of a plugin takes the place of the one of its
  /// id ([install]).
  bool has(FxPluginDescription plugin) =>
      _plugins.any((installed) => installed.description.id == plugin.id);

  /// How the runs of this device's plugins went, frame by frame — what a
  /// plugin effect's header shows ([FxPluginOutcomes]).
  final FxPluginOutcomes outcomes = FxPluginOutcomes();

  /// This device's build of [plugin] opened to run ([openInstalledFxPlugin])
  /// — null where the device has it not ([has]).
  ///
  /// Opened the first time it is asked, and kept until the plugin is
  /// replaced, uninstalled or this list goes: a frame that runs it pays no
  /// open. One that will not open fails every ask, as a run that fails does
  /// — shown as failed (🗣️a-failed-plugin-shows-the-cel-silently-Q1), and
  /// not opened again each frame. ↩️It answered null, and its effect drew
  /// as if off with nothing to say why.
  FxPluginRunner? runnerFor(FxPluginDescription plugin) {
    final installed = _plugins
        .where((installed) => installed.description.id == plugin.id)
        .firstOrNull;
    if (installed == null) {
      return null;
    }
    return _runners.putIfAbsent(
      plugin.id,
      () => _open(installed, _service) ?? const _Unopened(),
    );
  }

  /// Closes plugin [id]'s opened build, if it has one, and lets go of what
  /// its runs told ([FxPluginOutcomes.forget]).
  void _letGo(String id) {
    _runners.remove(id)?.close();
    outcomes.forget(id);
  }

  /// The plugins [project]'s effects are of that this device has not
  /// ([has]) — each once, as the project first names it — asked once the
  /// device is read: what the open door says of a project as it opens
  /// (🗣️I-132-Q28 a, 「열 때 경고 한 줄」), which may be before the app's
  /// first read is done.
  Future<List<FxPluginDescription>> missingFrom(Project project) async {
    await load();
    final missing = <String, FxPluginDescription>{};
    for (final effect in [
      for (final track in project.tracksOfEveryTimeline) ...track.effects,
      for (final row in projectLayersAnywhere(project)) ...row.effects,
    ]) {
      if (effect.plugin case final plugin? when !has(plugin)) {
        missing.putIfAbsent(plugin.id, () => plugin);
      }
    }
    return List.unmodifiable(missing.values);
  }

  /// Installs the plugin [bytes] hold, once [confirm] says yes — one this
  /// device has already (the same id) is replaced where it stood.
  Future<FxPluginInstall> install(
    Uint8List bytes, {
    required FxPluginConfirm confirm,
  }) async {
    final bundle = readFxPluginBundle(bytes);
    if (bundle == null) {
      return const FxPluginUnreadable();
    }
    if (_check(bundle) case final why?) {
      return FxPluginUnopened(why);
    }
    final description = bundle.description;
    final previous = _plugins
        .where((plugin) => plugin.description.id == description.id)
        .firstOrNull;
    final yes = await confirm(description, replacing: previous?.description);
    if (!yes || _disposed) {
      return const FxPluginDeclined();
    }
    final kept = await _service.keep(bundle);
    _plugins = List.unmodifiable([
      for (final plugin in _plugins)
        if (identical(plugin, previous)) kept else plugin,
      if (previous == null) kept,
    ]);
    await _service.saveIndex(_plugins);
    if (previous != null) {
      _letGo(previous.description.id);
      await _service.delete(previous);
    }
    if (!_disposed) {
      notifyListeners();
    }
    return FxPluginInstalled(description, replaced: previous?.description);
  }

  /// Takes plugin [id] off this device: its files go, and an effect of it
  /// keeps its lanes as one of a plugin this device has not
  /// (🗣️I-132-Q28). The index is written first, so a device stopped in
  /// between is left a stray file, never a plugin without one.
  Future<void> uninstall(String id) async {
    final gone = _plugins
        .where((plugin) => plugin.description.id == id)
        .firstOrNull;
    if (gone == null) {
      return;
    }
    _plugins = List.unmodifiable([
      for (final plugin in _plugins)
        if (!identical(plugin, gone)) plugin,
    ]);
    _letGo(id);
    notifyListeners();
    await _service.saveIndex(_plugins);
    await _service.delete(gone);
  }

  @override
  void dispose() {
    _disposed = true;
    AppGpu.settings.removeListener(_onGpuSettings);
    for (final id in [..._runners.keys]) {
      _letGo(id);
    }
    outcomes.dispose();
    super.dispose();
  }
}

/// An installed plugin that would not open: every ask fails.
final class _Unopened implements FxPluginRunner {
  const _Unopened();

  @override
  int? reach(Float64List values, FxPluginMoment moment) => null;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) => null;

  @override
  void close() {}
}

/// [plugin] opened on the app's GPU engine — null where its WGSL is gone,
/// unreadable, or will not open.
///
/// ⚠️The WGSL is read here, at once: what asks for a runner is a frame
/// being drawn, and it is read the first time only
/// ([InstalledFxPlugins.runnerFor]).
FxPluginRunner? openInstalledFxPlugin(
  InstalledFxPlugin plugin,
  FxPluginLibraryService library,
) {
  final path = library.pathOf(plugin.source);
  if (path == null) {
    return null;
  }
  try {
    final source = File(path).readAsStringSync();
    return GpuFxPlugin.open(
      source,
      plugin.description,
      cut: AppGpu.settings.value.pluginShare.cuts,
    ).plugin;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// [bundle]'s WGSL opened on the app's GPU engine and let go of: what an
/// install asks before the person is shown the plugin.
String? checkFxPluginOnTheDevice(FxPluginBundle bundle) {
  final (:plugin, :refusal) = GpuFxPlugin.open(
    bundle.source,
    bundle.description,
    cut: AppGpu.settings.value.pluginShare.cuts,
  );
  plugin?.close();
  return refusal;
}
