import 'dart:typed_data';

/// A picked file: display name plus raw bytes. One record type for every
/// brush-side pick (the round-8 audit, 2026-09-06 — the preset and tip
/// libraries each declared it under a name of their own).
typedef PickedFile = ({String name, Uint8List bytes});

/// Opens a file picker; `null` when the user cancels.
typedef FilePicker = Future<PickedFile?> Function();

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
