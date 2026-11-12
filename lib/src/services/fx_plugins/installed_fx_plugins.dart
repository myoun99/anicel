import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/app_gpu_settings.dart';
import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/project.dart';
import '../../native/app_gpu_engine.dart' show compiledHereOrOff;
import '../../native/gpu_fx_plugin.dart';
import '../project_lookup.dart' show projectLayersAnywhere;
import 'fx_plugin_bundle.dart';
import 'fx_plugin_library_service.dart';
import 'fx_plugin_outcomes.dart';

/// What opening a plugin's file on the device came to: the build it opened
/// — none where a stand-in opens nothing —, or the engine's words of why
/// not.
typedef FxPluginChecked = ({FxPluginRunner? opened, String? refusal});

/// Opens a plugin's file on the device to see that it would run.
typedef FxPluginChecker =
    Future<FxPluginChecked> Function(FxPluginBundle bundle);

/// Opens [plugin], as [library] keeps it, to run — off the isolate that
/// asks, at once where a test compiles there — null where it will not open.
typedef FxPluginOpener =
    FutureOr<FxPluginRunner?> Function(
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
  ///
  /// Answered at once, its build opened off the isolate that asks
  /// ([FxPluginRunner.toCome]) — ↩️opened right there till 2026-11-12,
  /// the frame that asked stopped meanwhile (an-endless-plugin-stalls-the-
  /// app ④, A5).
  FxPluginRunner? runnerFor(FxPluginDescription plugin) {
    final installed = _plugins
        .where((installed) => installed.description.id == plugin.id)
        .firstOrNull;
    if (installed == null) {
      return null;
    }
    return _runners.putIfAbsent(plugin.id, () {
      final opened = _open(installed, _service);
      return opened is Future<FxPluginRunner?>
          ? _Opening(opened)
          : opened ?? const _Unopened();
    });
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
    final cutting = _cutting;
    final (:opened, :refusal) = await _check(bundle);
    if (refusal != null) {
      return FxPluginUnopened(refusal);
    }
    final description = bundle.description;
    final previous = _plugins
        .where((plugin) => plugin.description.id == description.id)
        .firstOrNull;
    final yes = await confirm(description, replacing: previous?.description);
    if (!yes || _disposed) {
      opened?.close();
      return const FxPluginDeclined();
    }
    final kept = await _service.keep(bundle);
    _plugins = List.unmodifiable([
      for (final plugin in _plugins)
        if (identical(plugin, previous)) kept else plugin,
      if (previous == null) kept,
    ]);
    if (previous != null) {
      _letGo(previous.description.id);
    }
    // 🗣️관제 2026-11-12 22:25 (an-endless-plugin-stalls-the-app A5): 「A5 는
    // 설치 검사가 연 것을 러너로 쓴다」 — the build the check opened is the
    // one its frames run, so the device compiles it once. ↩️The check let
    // it go, and the first frame compiled it again. Kept as the list opens
    // now ([_openedCutting]) — one opened the other way is let go, and
    // opens again as asked.
    if (opened != null) {
      if (cutting == _openedCutting && !_disposed) {
        _runners[description.id] = opened;
      } else {
        opened.close();
      }
    }
    await _service.saveIndex(_plugins);
    if (previous != null) {
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
  Future<void>? get toCome => null;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => null;

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) async => null;

  @override
  void close() {}
}

/// An installed plugin whose build is opened off the isolate that asks
/// ([openInstalledFxPlugin]): it says so till it is ([toCome]), then it is
/// that build — or one that would not open ([_Unopened]). What a frame
/// bound meanwhile holds, so it is not bound again.
///
/// ⏳LET GO OF WITH THE APP'S ENGINE BY (C3) ④ (🗣️관제 2026-11-12 22:25:
/// 「놓기는 (C3) ④ 가 단다」, a-lost-gpu-device-keeps-the-unsaved-tiles):
/// its build is that engine's, and this list holds it past a loss till
/// then — as it holds one opened at once.
final class _Opening implements FxPluginRunner {
  _Opening(Future<FxPluginRunner?> opening) {
    _toCome = opening.then(
      _opened,
      onError: (Object error, StackTrace stack) {
        _opened(null);
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<void>? _toCome;
  FxPluginRunner _build = const _Unopened();
  bool _closed = false;

  void _opened(FxPluginRunner? build) {
    _toCome = null;
    if (_closed) {
      build?.close();
    } else if (build != null) {
      _build = build;
    }
  }

  @override
  Future<void>? get toCome => _toCome;

  @override
  int? reach(Float64List values, FxPluginMoment moment) =>
      _build.reach(values, moment);

  @override
  Future<Uint8List?> render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) => _build.render(
    input: input,
    values: values,
    layers: layers,
    moment: moment,
  );

  /// Lets its build go — one still to come as it comes.
  @override
  void close() {
    _closed = true;
    _build.close();
  }
}

/// [plugin] opened on the app's GPU engine — null where its WGSL is gone,
/// unreadable, or will not open: off the isolate that asks, where the file
/// is read too; at once where a test compiles there
/// ([compiledHereOrOff]).
///
/// ⚠️What asks for a runner is a frame being drawn, the first time only
/// ([InstalledFxPlugins.runnerFor]). ↩️It was read and opened right there
/// till 2026-11-12, the frame stopped for both (an-endless-plugin-stalls-
/// the-app ④).
FutureOr<FxPluginRunner?> openInstalledFxPlugin(
  InstalledFxPlugin plugin,
  FxPluginLibraryService library,
) {
  final path = library.pathOf(plugin.source);
  if (path == null) {
    return null;
  }
  return compiledHereOrOff(
    () => _openedHere(path, plugin.description),
    () => _openedOff(path, plugin.description),
  );
}

FxPluginRunner? _openedHere(String path, FxPluginDescription description) {
  try {
    return GpuFxPlugin.open(
      File(path).readAsStringSync(),
      description,
      cut: _cutting,
    ).plugin;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

Future<FxPluginRunner?> _openedOff(
  String path,
  FxPluginDescription description,
) async {
  try {
    final source = await File(path).readAsString();
    return (await GpuFxPlugin.opening(
      source,
      description,
      cut: _cutting,
    )).plugin;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// [bundle]'s WGSL opened on the app's GPU engine: what an install asks
/// before the person is shown the plugin — off the isolate that asks, at
/// once where a test compiles there ([compiledHereOrOff]).
Future<FxPluginChecked> checkFxPluginOnTheDevice(FxPluginBundle bundle) async {
  final (:plugin, :refusal) = await compiledHereOrOff(
    () => GpuFxPlugin.open(bundle.source, bundle.description, cut: _cutting),
    () => GpuFxPlugin.opening(bundle.source, bundle.description, cut: _cutting),
  );
  return (opened: plugin, refusal: refusal);
}

/// Whether a plugin is opened to be cut ([FxPluginShare.cuts]).
bool get _cutting => AppGpu.settings.value.pluginShare.cuts;
