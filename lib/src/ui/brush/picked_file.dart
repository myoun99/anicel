import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// A picked file: display name plus raw bytes. One record type for every
/// brush-side pick (the round-8 audit, 2026-09-06 — the preset and tip
/// libraries each declared it under a name of their own).
typedef PickedFile = ({String name, Uint8List bytes});

/// Opens a file picker; `null` when the user cancels.
typedef FilePicker = Future<PickedFile?> Function();

/// The production picker of every import that reads a file itself: the
/// platform's open-file dialog, showing EVERY file.
///
/// 🚨유저 2026-08-29: 「픽커는 어떤플랫폼이든 어떤 확장자던 선택할수
/// 있게하고, 대응만 지원안되는 확장자면 그 때 해당 파일 지원안된다고 안내창
/// 띄우게」. The 「그 때」 is the import that is handed the file: each one
/// already answers with a sentence for a file it cannot read, so the refusal
/// has somewhere to go.
///
/// ↩️The brush presets and the brush tips each wrote this dialog out, and
/// the text tool's fonts would have written the third (2026-10-06).
Future<PickedFile?> pickAnyFile() async {
  final file = await openFile(acceptedTypeGroups: const []);
  if (file == null) {
    return null;
  }
  return (name: file.name, bytes: await File(file.path).readAsBytes());
}

extension PickedFileStem on PickedFile {
  /// The name without its last extension — what an import is called.
  ///
  /// ⚠️Not cut_folder_parse's `_stemOf`: that one keeps a leading-dot name
  /// (`.hidden`) whole. A separate law, kept separate.
  String get stem =>
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
}

/// The pick phase every brush import shares: [pick] the file, turn a
/// throwing picker into the one user-facing message, bail quietly on a
/// cancel or on a library disposed while the dialog was open, then hand
/// the file to [import] — the decode-and-merge step that is all that
/// differs between the libraries.
///
/// Returns [import]'s message (`null` for success) or `null` for a cancel.
Future<String?> importPickedFile({
  required FilePicker pick,
  required bool Function() disposed,
  required Future<String?> Function(PickedFile pick) import,
}) async {
  final PickedFile? picked;
  try {
    picked = await pick();
  } on Object catch (error) {
    return 'Could not open the file: $error';
  }
  if (picked == null || disposed()) {
    return null;
  }
  return import(picked);
}
