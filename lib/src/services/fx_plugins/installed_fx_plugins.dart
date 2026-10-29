import 'package:flutter/foundation.dart';

import '../../models/fx_plugin_description.dart';
import '../../native/qa_fx_plugin_host.dart';
import 'fx_plugin_bundle.dart';
import 'fx_plugin_library_service.dart';

/// What a plugin's module said when it was asked who it is: its
/// description's text, or why the engine would not open it.
typedef FxPluginDescribed = ({String? text, String? refusal});

/// Asks a plugin's module who it is.
typedef FxPluginDescriber = FxPluginDescribed Function(Uint8List wasm);

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
/// before anything is kept; its native build is never opened here
/// (anicel_fx_plugin.h, THE FILE).
class InstalledFxPlugins extends ChangeNotifier {
  InstalledFxPlugins({
    FxPluginLibraryService? service,
    FxPluginDescriber? describe,
  }) : _service = service ?? FxPluginLibraryService(),
       _describe = describe ?? describeFxPluginModule;

  final FxPluginLibraryService _service;
  final FxPluginDescriber _describe;
  List<InstalledFxPlugin> _plugins = const [];
  bool _disposed = false;

  /// In the order they were installed.
  List<InstalledFxPlugin> get plugins => _plugins;

  /// Reads which plugins this device has.
  Future<void> load() async {
    final plugins = await _service.loadIndex();
    if (_disposed) {
      return;
    }
    _plugins = plugins;
    notifyListeners();
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
      await _service.delete(previous);
    }
    if (!_disposed) {
      notifyListeners();
    }
    return FxPluginInstalled(description, replaced: previous?.description);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
