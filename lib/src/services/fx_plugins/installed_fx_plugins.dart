import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/fx_plugin_description.dart';
import '../../models/fx_plugin_run.dart';
import '../../models/project.dart';
import '../../native/qa_fx_plugin_host.dart';
import '../project_lookup.dart' show projectLayersAnywhere;
import 'fx_plugin_bundle.dart';
import 'fx_plugin_library_service.dart';

/// What a plugin's module said when it was asked who it is: its
/// description's text, or why the engine would not open it.
typedef FxPluginDescribed = ({String? text, String? refusal});

/// Asks a plugin's module who it is.
typedef FxPluginDescriber = FxPluginDescribed Function(Uint8List wasm);

/// Opens [plugin], as [library] keeps it, to run — null where it will not
/// open.
typedef FxPluginOpener =
    FxPluginRunner? Function(
      InstalledFxPlugin plugin,
      FxPluginLibraryService library,
    );

/// Asks the person whether to install the plugin that says [description]
/// of itself — [native]: its file has a native build for this device,
/// which runs outside the sandbox; [replacing]: the version of it this
/// device has now.
typedef FxPluginConfirm =
    Future<bool> Function(
      FxPluginDescription description, {
      required bool native,
      required FxPluginDescription? replacing,
    });

/// What installing a plugin's file came to.
sealed class FxPluginInstall {
  const FxPluginInstall();
}

/// No plugin's file, or one whose module describes itself as the spec
/// does not.
final class FxPluginUnreadable extends FxPluginInstall {
  const FxPluginUnreadable();
}

/// The engine would not open its module — [why], in the engine's words.
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
/// The files and their index are [FxPluginLibraryService]'s. A plugin is
/// asked who it is by its MODULE, in the sandbox, and shown to the person
/// before anything is kept; its native build is opened only to run it, once
/// they have said yes (anicel_fx_plugin.h, THE FILE).
class InstalledFxPlugins extends ChangeNotifier {
  InstalledFxPlugins({
    FxPluginLibraryService? service,
    FxPluginDescriber? describe,
    FxPluginOpener? open,
  }) : _service = service ?? FxPluginLibraryService(),
       _describe = describe ?? describeFxPluginModule,
       _open = open ?? openInstalledFxPlugin;

  final FxPluginLibraryService _service;
  final FxPluginDescriber _describe;
  final FxPluginOpener _open;

  /// The plugins opened to run, by id — null for one that would not open,
  /// so it is not tried again each frame.
  final Map<String, FxPluginRunner?> _runners = {};
  List<InstalledFxPlugin> _plugins = const [];
  bool _disposed = false;

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

  /// This device's build of [plugin] opened to run ([openInstalledFxPlugin])
  /// — null where the device has it not ([has]) or it will not open.
  ///
  /// Opened the first time it is asked, and kept until the plugin is
  /// replaced, uninstalled or this list goes: a frame that runs it pays no
  /// open.
  FxPluginRunner? runnerFor(FxPluginDescription plugin) {
    final installed = _plugins
        .where((installed) => installed.description.id == plugin.id)
        .firstOrNull;
    if (installed == null) {
      return null;
    }
    return _runners.putIfAbsent(plugin.id, () => _open(installed, _service));
  }

  /// Closes plugin [id]'s opened build, if it has one.
  void _letGo(String id) => _runners.remove(id)?.close();

  /// The plugins [project]'s effects are of that this device has not
  /// ([has]) — each once, as the project first names it — asked once the
  /// device is read: what the open door says of a project as it opens
  /// (🗣️I-132-Q28 a, 「열 때 경고 한 줄」), which may be before the app's
  /// first read is done.
  Future<List<FxPluginDescription>> missingFrom(Project project) async {
    await load();
    final missing = <String, FxPluginDescription>{};
    for (final effect in [
      for (final track in project.tracks) ...track.effects,
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
    final (:text, :refusal) = _describe(bundle.wasm);
    final description = text == null ? null : FxPluginDescription.read(text);
    if (description == null) {
      return refusal == null
          ? const FxPluginUnreadable()
          : FxPluginUnopened(refusal);
    }
    final previous = _plugins
        .where((plugin) => plugin.description.id == description.id)
        .firstOrNull;
    final yes = await confirm(
      description,
      native: bundle.native != null,
      replacing: previous?.description,
    );
    if (!yes || _disposed) {
      return const FxPluginDeclined();
    }
    final kept = await _service.keep(bundle, description);
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
    for (final id in [..._runners.keys]) {
      _letGo(id);
    }
    super.dispose();
  }
}

/// [plugin] opened through the engine's host: its native build where this
/// device has one (🗣️I-132-Q5 b), its module everywhere else — null where
/// there is no host, or it will not open.
///
/// ⚠️The module is read here, at once: what asks for a runner is a frame
/// being drawn, and it is read the first time only
/// ([InstalledFxPlugins.runnerFor]).
FxPluginRunner? openInstalledFxPlugin(
  InstalledFxPlugin plugin,
  FxPluginLibraryService library,
) {
  final host = QaFxPluginHost.instance;
  if (host == null) {
    return null;
  }
  if (plugin.native case final native?) {
    if (library.pathOf(native) case final path?) {
      return host.openNative(path).plugin;
    }
  }
  final path = library.pathOf(plugin.wasm);
  if (path == null) {
    return null;
  }
  try {
    return host.openWasm(File(path).readAsBytesSync()).plugin;
  } on FileSystemException {
    return null;
  }
}

/// [wasm] asked who it is through the engine's host, in its sandbox.
FxPluginDescribed describeFxPluginModule(Uint8List wasm) {
  final host = QaFxPluginHost.instance;
  if (host == null) {
    return (text: null, refusal: 'the engine has no plugin host');
  }
  final (:plugin, :error) = host.openWasm(wasm);
  if (plugin == null) {
    return (text: null, refusal: error);
  }
  try {
    return (text: plugin.describe(), refusal: null);
  } finally {
    plugin.close();
  }
}
