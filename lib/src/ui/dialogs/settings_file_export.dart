import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter/widgets.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart' show showAppNotice;
import 'folder_pick_flow.dart';
import 'handed_text_file.dart';

/// A settings file (I-142) holding what [contents] makes — one palette's,
/// one shortcut preset's — named for [name] and of [type], put in the
/// person's hands by the door every finished file leaves by
/// ([handWrittenFileToUser]), and what came of it said; nothing where the
/// person would not have it.
Future<void> handSettingsFileToUser(
  BuildContext context, {
  required String name,
  required XTypeGroup type,
  required String Function() contents,
}) async {
  final handed = await handTextFile(
    name,
    type.extensions!.single,
    contents,
    hand: (suggestedName, write) => handWrittenFileToUser(
      context,
      suggestedName: suggestedName,
      acceptedTypeGroups: [type],
      write: write,
    ),
  );
  final strings = AppText.strings;
  final said = switch (handed) {
    TextFileNotPlaced(:final error) => strings.fileExportPlaceUnchosen(error),
    TextFileNotWritten(:final error) => strings.settingsExportNotWritten(error),
    TextFileDeclined() => null,
    TextFileLanded() => strings.settingsExported(name),
  };
  if (said != null && context.mounted) {
    await showAppNotice(context, title: strings.commonNotice, message: said);
  }
}
