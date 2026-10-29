import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/fx_plugin_description.dart';
import '../../services/fx_plugins/installed_fx_plugins.dart';
import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// I-132: the fx plugin file [name], holding [bytes], installed into
/// [plugins] once the person has seen what it says of itself and said yes
/// — what the one door says of it (F-282), nothing where they said no.
Future<String?> installFxPluginFile(
  BuildContext context,
  InstalledFxPlugins plugins,
  String name,
  Uint8List bytes,
) async {
  final strings = AppText.strings;
  final outcome = await plugins.install(
    bytes,
    confirm: (description, {required native, required replacing}) async {
      if (!context.mounted) {
        return false;
      }
      final answer = await askConfirm(
        context,
        ConfirmQuestion(
          keys: confirmDialogKeys('install-fx-plugin'),
          title: strings.fxPluginInstallTitle,
          message: _questionOf(
            description,
            native: native,
            replacing: replacing,
          ),
        ),
        accept: ConfirmChoice(strings.fxPluginInstall),
      );
      return answer ?? false;
    },
  );
  return switch (outcome) {
    FxPluginInstalled(:final description) => strings.fxPluginInstalled(
      description.name,
    ),
    FxPluginDeclined() => null,
    FxPluginUnreadable() => strings.fxPluginUnreadable(name),
    FxPluginUnopened(:final why) => strings.fxPluginUnopened(name, why),
  };
}

/// Who the plugin says it is, the version it replaces, and — a warning —
/// that a native build of it runs outside the sandbox.
String _questionOf(
  FxPluginDescription description, {
  required bool native,
  required FxPluginDescription? replacing,
}) {
  final strings = AppText.strings;
  return [
    strings.fxPluginInstallBody(
      description.name,
      description.vendor,
      description.version,
    ),
    if (replacing != null) strings.fxPluginReplaces(replacing.version),
    if (native) strings.fxPluginRunsNatively,
  ].join('\n\n');
}
