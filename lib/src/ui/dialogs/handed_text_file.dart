import 'dart:async';
import 'dart:io';

import '../export/export_plan.dart' show sanitizeExportFileComponent;

/// What came of handing a text file to the person ([handTextFile]).
sealed class TextFileHanded {
  const TextFileHanded();
}

/// It stands at [where].
final class TextFileLanded extends TextFileHanded {
  const TextFileLanded(this.where);

  final String where;
}

/// The person would not have it.
final class TextFileDeclined extends TextFileHanded {
  const TextFileDeclined();
}

/// No place for it could be asked — [error] says why.
final class TextFileNotPlaced extends TextFileHanded {
  const TextFileNotPlaced(this.error);

  final Object error;
}

/// It could not be written where it was to go — [error] says why.
final class TextFileNotWritten extends TextFileHanded {
  const TextFileNotWritten(this.error);

  final Object error;
}

/// The text [contents] makes, as a file named for [name] with [extension],
/// put in the person's hands by [hand] — which asks where, has its second
/// argument write the file at a path, and answers where it landed (null
/// when the person would not have it): the door every finished file leaves
/// by (`handWrittenFileToUser`), or a test's.
///
/// One road for every file of the app's own text a person takes away: a
/// brush pack, a palette, a shortcut preset, every setting (I-142) — each
/// says what came of it in its own words. [name] is the person's own, so it
/// is made a name a file can have, as an export's are. [contents] is made at
/// the write, so a person who backs out of the save window costs nothing,
/// and a text that cannot be made is a file not written.
Future<TextFileHanded> handTextFile(
  String name,
  String extension,
  FutureOr<String> Function() contents, {
  required Future<String?> Function(
    String suggestedName,
    Future<bool> Function(String path) write,
  )
  hand,
}) async {
  Object? notWritten;
  Future<bool> write(String path) async {
    try {
      await File(path).writeAsString(await contents(), flush: true);
      return true;
    } on Object catch (error) {
      notWritten = error;
      return false;
    }
  }

  final String? landed;
  try {
    landed = await hand(
      '${sanitizeExportFileComponent(name)}.$extension',
      write,
    );
  } on Object catch (error) {
    return TextFileNotPlaced(error);
  }
  if (notWritten case final error?) {
    return TextFileNotWritten(error);
  }
  return landed == null ? const TextFileDeclined() : TextFileLanded(landed);
}
