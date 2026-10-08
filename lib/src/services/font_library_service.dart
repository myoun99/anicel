import 'dart:io';
import 'dart:typed_data';

import '../models/font_face_facts.dart';
import '../models/media_asset.dart' show isOneStoredName, mintMediaCarry;
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

  /// Where the library keeps a file called [file] — or null when [file] is
  /// not a name of its own ([isFontLibraryFileName]): nothing is kept, read
  /// or deleted under such a name.
  ///
  /// ⛔THE ONE LINE THAT JOINS THE FOLDER AND A NAME IT WAS HANDED (board
  /// `law-저장`, as the room's `_pathInTheRoom` is its): an index is a file
  /// on a disk and a project is a file from anywhere, and what either says
  /// reaches the disk through here or not at all.
  String? _pathOf(String file) =>
      isFontLibraryFileName(file) ? '$directoryPath/$file' : null;

  /// A name to keep a file of [facts]' face under, [extension] at its end
  /// ([mintFontLibraryFileName]) — minted, so never one a file was kept
  /// under before.
  String mintFileName(FontFaceFacts facts, {required String extension}) =>
      mintFontLibraryFileName(
        facts,
        extension: extension,
        directoryPath: directoryPath,
      );

  /// Where the library keeps the file called [file] — null when it keeps
  /// none by that name, or [file] is not a name of its own
  /// ([isFontLibraryFileName]).
  ///
  /// What a project that carries the file under this name asks, to read
  /// its bytes on the device they were brought to (`ProjectFontFile`). The
  /// DISK is asked, not the index: the bytes are what is wanted, and a
  /// name means one set of them for good.
  String? pathOfFontHeld(String file) {
    final path = _pathOf(file);
    return path != null && File(path).existsSync() ? path : null;
  }

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
  ///
  /// ⚠️[file] is a name the library minted ([mintFileName]); one that is
  /// not a name of its own is the caller's mistake and is refused, rather
  /// than written where nothing would read it back.
  Future<void> writeFont(String file, Uint8List bytes) async {
    final path = _pathOf(file);
    if (path == null) {
      throw ArgumentError.value(file, 'file', 'is not a name of the library');
    }
    final target = File(path);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  /// The bytes of [file], or null when it is gone or unreadable — a face
  /// that cannot be read is a face this device does not have.
  Future<Uint8List?> readFont(String file) async {
    final path = _pathOf(file);
    if (path == null) {
      return null;
    }
    try {
      return await File(path).readAsBytes();
    } on Object {
      return null;
    }
  }

  /// Removes a face's file. A missing file is not an error — the index is
  /// the record that matters, and it is written by the caller.
  Future<void> deleteFont(String file) async {
    final path = _pathOf(file);
    if (path == null) {
      return;
    }
    try {
      final target = File(path);
      if (await target.exists()) {
        await target.delete();
      }
    } on Object {
      // A file that will not delete stays on disk; the index has already
      // dropped it, so nothing reads it.
    }
  }
}

/// A name for a font file the library at [directoryPath] is about to keep:
/// of this app's own making, so nothing of a picked file's name — a path,
/// a `..` — ever reaches the disk.
///
/// 🚨★★★**MINTED WHOLE, AS A CARRIED MEDIUM'S NAME IS** ([mintMediaCarry]:
/// `<path hash>-<random>-<name>`), so that A NAME MEANS ONE SET OF BYTES
/// FOR GOOD — on this device and on any other. A project that carries a
/// font keeps it under this very name (`ProjectFontFile.carriedAs`), and
/// that is what lets everybody ask 「are these the same bytes」 without
/// reading one: the save, which finds the file a project registered by
/// its name ([FontLibraryService.pathOfFontHeld]), and the engine's side,
/// which is handed a file once whether it is read from this folder or out
/// of a project (`CanvasLetterFaces`) — a CJK font is ten to thirty
/// megabytes, and the engine never lets go of one.
///
/// ↩️It was a COUNT (`font-<n>`, 2026-10-06, so a test could say which
/// file was which). A count means one file on ONE device: a project from
/// another machine naming `font-3` would have been read as this machine's
/// third font. The fake library of the tests still counts
/// (`FontLibraryInMemory`) — it stands in for a place, not for the name.
///
/// The face rides in the name — its family and weight, made safe by the
/// one algorithm that makes a stored name safe (`mediaNameParts`) — so a
/// person looking in the folder, or inside a project file, can tell what
/// they are looking at. ⚠️Where the family is named in the letters a stored
/// name keeps: one named in Korean or Japanese rides as that many `_`, and
/// the name is still one of a kind by what is minted before it.
String mintFontLibraryFileName(
  FontFaceFacts facts, {
  required String extension,
  required String directoryPath,
}) {
  final family = facts.family;
  final kept = family.length > _familyLettersKept
      ? family.substring(0, _familyLettersKept)
      : family;
  final face = '$kept-${facts.weight}${facts.italic ? 'i' : ''}';
  return mintMediaCarry('$directoryPath/$face.$extension');
}

/// How much of a family's name rides in a file's: enough to tell two
/// apart, and never enough to make a path too long to open.
const int _familyLettersKept = 40;

/// Whether [file] is a name a font file of the library can be kept under —
/// the only names it reads, writes and deletes. An index is a file on a
/// disk and a project is a file from anywhere, and what either says is not
/// let name a path: `deleteFont` deletes what it is handed.
///
/// ONE NAME, WITH NOTHING OF A PATH IN IT ([isOneStoredName] — the law
/// every name that becomes a path in this app is asked, board `law-저장`:
/// a place that makes a path of a file's name asks that predicate and does
/// not write the rule again) — and, of those, one that ends in a font's
/// extension and is no longer than a name this app mints.
bool isFontLibraryFileName(String file) =>
    file.length <= _longestName &&
    isOneStoredName(file) &&
    _endsAsAFontFile.hasMatch(file);

/// Longer than any name this app mints, shorter than what a path can hold
/// beside its folder.
const int _longestName = 120;

final RegExp _endsAsAFontFile = RegExp(r'\.(ttf|otf|ttc)$');
