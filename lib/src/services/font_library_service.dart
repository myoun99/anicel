import 'dart:io';
import 'dart:typed_data';

import '../models/font_face_facts.dart';
import 'persistence/app_support_path.dart';
import 'persistence/versioned_settings_file.dart';

/// One font file in the library: the name it is kept under in the library's
/// folder, and what it said of itself when it was brought in.
typedef FontLibraryEntry = ({String file, FontFaceFacts facts});

/// Reads and writes THE FONTS A PERSON BROUGHT TO THIS DEVICE (R9-rest, the
/// text tool's faces): a folder of font files, as they were picked, plus a
/// small index of what each says of itself — the brush tips' layout
/// (`BrushTipLibraryService`), for the same reason: they are files a person
/// can look at, copy and back up.
///
/// 🗣️유저 2026-10-06: 「유저가 알아서 자기가 가지고있는 글꼴 넣는게 아니야?」
/// — a face is a file its owner hands the app, and this is where the app
/// keeps its copy.
///
/// The index is what lets the list of faces be shown without opening a file:
/// a CJK font runs to tens of megabytes, and reading every one to learn its
/// name would be paid at every launch.
///
/// Fonts here are this DEVICE's, for ever (the 유저설정 room of
/// `appSettingsFilePath`). What of them rides inside a project is that
/// project's business (`FontFaceFacts.ridesInEditedDocuments`).
class FontLibraryService {
  FontLibraryService({String? directoryPath})
    : directoryPath = directoryPath ?? defaultFontDirectoryPath();

  /// Folder holding `index.json` and one file per face.
  final String directoryPath;

  /// ⚠️Sandboxed under `FLUTTER_TEST`: the workspace builds this library
  /// itself, so a widget test reaches it through the production wiring —
  /// and would list, and WRITE INTO, the developer's own fonts without the
  /// redirect.
  static String defaultFontDirectoryPath() =>
      testRedirectedAppSettingsPath('fonts', sandbox: 'fonts');

  /// Index file format version.
  static const int indexVersion = 1;

  String get indexPath => '$directoryPath/index.json';

  String _pathOf(String file) => '$directoryPath/$file';

  /// The faces of the library, in the order they were brought. A missing or
  /// unreadable index is an empty library, never an error.
  Future<List<FontLibraryEntry>> loadIndex() async =>
      await loadVersionedSettings(
        filePath: indexPath,
        version: indexVersion,
        fromJson: (json) => [
          for (final entry in json['fonts'] as List<dynamic>)
            if (entry case {'file': final String file}
                when isFontLibraryFileName(file))
              (
                file: file,
                facts: FontFaceFacts.fromJson(entry as Map<String, dynamic>),
              ),
        ],
      ) ??
      const [];

  Future<void> saveIndex(List<FontLibraryEntry> entries) =>
      saveVersionedSettings(
        filePath: indexPath,
        version: indexVersion,
        json: {
          'fonts': [
            for (final entry in entries)
              {'file': entry.file, ...entry.facts.toJson()},
          ],
        },
      );

  /// Writes [bytes] as the library's copy of a face, under [file]. The
  /// caller owns the index; this only puts the file on disk.
  Future<void> writeFont(String file, Uint8List bytes) async {
    final target = File(_pathOf(file));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  /// The bytes of [file], or null when it is gone or unreadable — a face
  /// that cannot be read is a face this device does not have.
  Future<Uint8List?> readFont(String file) async {
    try {
      return await File(_pathOf(file)).readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Removes a face's file. A missing file is not an error — the index is
  /// the record that matters, and it is written by the caller.
  Future<void> deleteFont(String file) async {
    try {
      final target = File(_pathOf(file));
      if (await target.exists()) {
        await target.delete();
      }
    } on Object {
      // A file that will not delete stays on disk; the index has already
      // dropped it, so nothing reads it.
    }
  }
}

/// The name the library keeps its [number]th font file under: a name of
/// this app's own making, so nothing of a picked file's name — a path, a
/// `..` — ever reaches the disk.
///
/// A COUNT, and not the clock the brush tips' names are made of: two files
/// brought in one millisecond are two numbers, and which name a file gets
/// is the same on every run of a test.
String fontLibraryFileName(int number, {required String extension}) =>
    'font-$number.$extension';

/// The number in a name this app minted ([fontLibraryFileName]) — null for
/// any other name.
int? fontLibraryFileNumber(String file) {
  final minted = _minted.firstMatch(file);
  return minted == null ? null : int.parse(minted.group(1)!);
}

/// Whether [file] is a name this app mints for a library font — the only
/// names the library reads, writes and deletes. An index is a file on a
/// disk, and what it says is not let name a path: `deleteFont` deletes
/// what it is handed.
bool isFontLibraryFileName(String file) => fontLibraryFileNumber(file) != null;

/// Nine digits at most: a number an index can say and an `int` can hold.
final RegExp _minted = RegExp(r'^font-([0-9]{1,9})\.(ttf|otf|ttc)$');
