import 'package:flutter/foundation.dart';

import '../../models/font_face_facts.dart';
import '../../services/font_file_reader.dart';
import '../../services/font_library_service.dart';
import '../brush/picked_file.dart';
import 'app_strings.dart';
import 'canvas_letter_faces.dart';

/// ONE FONT FILE LETTERS CAN BE SET WITH: the [name] its bytes are kept
/// under, what the file said of itself, and how to read it now.
///
/// 🚨THE NAME IS THE BYTES (`mintFontLibraryFileName`): a file this
/// device's library keeps and a font a project carries under the same name
/// are one file, read from wherever it is at hand. So the name is all the
/// engine's side is told of a file ([CanvasLetterFaces.setHeld]) — and a
/// font registered with a project from this device, saved into the
/// project's file, opened in another tab, is handed to the engine once.
typedef LetterFaceFile = ({
  String name,
  FontFaceFacts facts,
  Future<Uint8List?> Function() read,
});

/// THE PROJECT ON SCREEN, AS THE FONTS KNOW IT (R9-rest): the font files it
/// carries that can be read now ([files] — what its families are set
/// with), the families its own list names, readable or not ([families] —
/// what a list of faces shows as the project's), and the taking of one out
/// of it ([takeOut], a step of that project's history).
///
/// Functions, asked when the answer is wanted: all three move with the
/// project, and the first with this device's library too.
typedef ProjectFontsOnScreen = ({
  List<LetterFaceFile> Function() files,
  List<String> Function() families,
  void Function(String family) takeOut,
});

/// How a list puts the names of font families in order: as a person looks
/// for one — 「alpha」 before 「Beta」 — and the same on every run.
int compareFontFamilyNames(String a, String b) {
  final folded = a.toLowerCase().compareTo(b.toLowerCase());
  return folded != 0 ? folded : a.compareTo(b);
}

/// One family of the device's fonts, as a list shows it: its name, and
/// whether every file of it may ride inside a project
/// ([FontFaceFacts.ridesInEditedDocuments]).
typedef ImportedFontFamily = ({String name, bool ridesInEditedDocuments});

/// What bringing a font file came to: the [family] it is a face of, or the
/// sentence that says why it was refused — and neither, when no file was
/// picked after all.
typedef FontImportOutcome = ({String? family, String? refusal});

/// THE FONTS A PERSON BROUGHT TO THIS DEVICE (R9-rest, the text tool's
/// faces), as the app reads them: the families a list shows, bringing one
/// more from a file, and taking one away.
///
/// 🗣️유저 2026-10-06: 「유저가 알아서 자기가 가지고있는 글꼴 넣는게
/// 아니야?」 — a face is a file its owner hands over. The app's own two
/// (`AppTypography`) are not here: they are in every copy of the app.
///
/// The files and their index are [FontLibraryService]'s; which faces the
/// engine has been handed, and when, is [faces]' — this stands it as the
/// run's faces ([CanvasLetterFaces.current]) and tells it what the device
/// holds, so letters are set in a family from the moment it is brought and
/// in the app's own face from the moment it is taken away.
class ImportedFonts extends ChangeNotifier {
  ImportedFonts({
    FontLibraryService? service,
    FilePicker? picker,
    FontFaceRegistrar? register,
    Future<void> Function(Set<String> files)? beforeLettingGo,
  }) : _service = service ?? FontLibraryService(),
       _beforeLettingGo = beforeLettingGo,
       // Every file is offered ([pickAnyFile]); one that is not a font is
       // refused by the read in [importBytes], which says so.
       _picker = picker ?? pickAnyFile {
    faces = CanvasLetterFaces(files: _filesOf, register: register);
    CanvasLetterFaces.current = faces;
  }

  final FontLibraryService _service;
  final FilePicker _picker;

  /// Waited for before font files — named by the names they are kept under
  /// — are taken off this device: whoever still needs their bytes takes
  /// them first.
  ///
  /// 🚨★★★HOW A FONT A PROJECT CARRIES KEEPS 「품은 순간 데이터를
  /// 가지고있고 **불변**」 (유저 2026-08-30, of everything a project
  /// carries). A font registered with a project is not copied when it is
  /// registered — a CJK font is tens of megabytes, and the text that
  /// registers it lands in the middle of somebody's typing. Its bytes are
  /// ALREADY in the app's keeping: in this library, under a name that means
  /// them for good. They stay there until the project is saved; and the
  /// only thing that takes a file out of this library is this class — so it
  /// asks first, and every open project that carries the file and has it
  /// nowhere else takes its own copy then (`ProjectFonts.holdBytesOf`).
  final Future<void> Function(Set<String> files)? _beforeLettingGo;

  /// The engine's side of these fonts.
  late final CanvasLetterFaces faces;

  List<FontLibraryEntry> _entries = const [];
  bool _disposed = false;

  /// The families, by name — as a person looks for one.
  List<ImportedFontFamily> get families {
    final rides = <String, bool>{};
    for (final entry in _entries) {
      rides[entry.facts.family] =
          (rides[entry.facts.family] ?? true) &&
          entry.facts.ridesInEditedDocuments;
    }
    return [
      for (final name in rides.keys.toList()..sort(compareFontFamilyNames))
        (name: name, ridesInEditedDocuments: rides[name]!),
    ];
  }

  /// The family called [name], if this device holds it.
  ImportedFontFamily? familyNamed(String name) =>
      families.where((family) => family.name == name).firstOrNull;

  /// The project on screen ([showCarried]) — null with none.
  ProjectFontsOnScreen? _carried;

  /// What each family is set with, as the engine's side was last told.
  Map<String, List<LetterFaceFile>> _setWith = const {};

  /// Stands [carried] as THE PROJECT ON SCREEN (R9-rest): letters in a
  /// family it carries a face of are set with ITS file of that
  /// face, and with this device's for any other — so a project opened on a
  /// machine that was never brought its fonts is edited in the letters it
  /// was written in, and one whose font this device holds as other bytes
  /// keeps its own.
  ///
  /// Its files are asked for again whenever the families are reckoned:
  /// which of a project's fonts can be READ moves with this device's
  /// library too (a font registered from here lives in this library until
  /// the project is saved). Whoever shows the project says so again when
  /// its list of fonts is another.
  void showCarried(ProjectFontsOnScreen? carried) {
    _carried = carried;
    _tell();
  }

  /// The families the project on screen carries a file of, by name, as its
  /// own list says them — whether or not their bytes can be read here
  /// ([CanvasLetterFaces.holds] says that).
  List<String> get carriedFamilies => _carried?.families() ?? const [];

  /// Takes [family] out of the project on screen — a step of that
  /// project's history, which an undo takes back.
  void takeOutOfProject(String family) => _carried?.takeOut(family);

  /// The files [family] is set with now — the project on screen's and this
  /// device's, as [showCarried] says — none for a family nobody holds.
  List<LetterFaceFile> filesSetWith(String family) =>
      _setWith[family] ?? const [];

  /// The files each family is set with: the project's, and of this
  /// device's those of a face the project carries no file of.
  Map<String, List<LetterFaceFile>> _familiesNow() {
    final families = <String, List<LetterFaceFile>>{};
    for (final file in _carried?.files() ?? const <LetterFaceFile>[]) {
      // The app's own faces are in every copy of the app: a project that
      // names a file for one is not what the interface is written in.
      if (!CanvasLetterFaces.isAppFace(file.facts.family)) {
        (families[file.facts.family] ??= []).add(file);
      }
    }
    for (final entry in _entries) {
      final family = families[entry.facts.family] ??= [];
      if (!family.any((held) => held.facts.isSameFaceAs(entry.facts))) {
        family.add((
          name: entry.file,
          facts: entry.facts,
          read: () => _service.readFont(entry.file),
        ));
      }
    }
    return families;
  }

  @override
  void dispose() {
    _disposed = true;
    _carried = null;
    if (identical(CanvasLetterFaces.current, faces)) {
      CanvasLetterFaces.current = CanvasLetterFaces();
    }
    faces.dispose();
    super.dispose();
  }

  /// Reads the index: the families are on screen, and none of their files
  /// has been opened ([CanvasLetterFaces]: a face is read when letters are
  /// first asked for in it).
  ///
  /// Once, whoever asks and however often: a font brought before the index
  /// was read waits for this ([importBytes]), so nothing is ever done to a
  /// library that has not been read.
  Future<void> load() => _indexRead ??= _readIndex();

  Future<void>? _indexRead;

  Future<void> _readIndex() async {
    final read = await _service.loadIndex();
    if (_disposed) {
      return;
    }
    _entries = read;
    _tell();
  }

  /// Picks a file and brings it as a font ([importBytes]).
  Future<FontImportOutcome> importFromFile() async {
    String? family;
    final refusal = await importPickedFile(
      pick: _picker,
      disposed: () => _disposed,
      import: (pick) async {
        final outcome = await importBytes(pick.bytes);
        family = outcome.family;
        return outcome.refusal;
      },
    );
    return (family: family, refusal: refusal);
  }

  /// Brings [bytes] as a font file: kept in the library, and its family one
  /// letters can be set in from here on.
  ///
  /// A file that is the face a family already has — the same weight, the
  /// same slant — takes that face's place; any other joins the family, so
  /// a bold brought after its regular is what the regular's bold is set in.
  ///
  /// ⛔A file that names one of the APP'S OWN families is refused: the
  /// engine would hear it as more faces of the family the whole interface
  /// is written in.
  Future<FontImportOutcome> importBytes(Uint8List bytes) async {
    final strings = AppText.strings;
    final facts = readFontFaceFacts(bytes);
    if (facts == null) {
      return (family: null, refusal: strings.textToolFontUnreadable);
    }
    if (CanvasLetterFaces.isAppFace(facts.family)) {
      return (family: null, refusal: strings.textToolFontIsTheApps);
    }
    // The index is read before the library is added to: what this face
    // replaces, and what is written back, is what the index says.
    await load();
    if (_disposed) {
      return (family: null, refusal: null);
    }
    final file = _service.mintFileName(
      facts,
      extension: fontFileExtensionOf(bytes),
    );
    try {
      await _service.writeFont(file, bytes);
    } on Object {
      return (family: null, refusal: strings.textToolFontNotKept);
    }
    if (_disposed) {
      return (family: null, refusal: null);
    }
    final replaced = [
      for (final entry in _entries)
        if (entry.facts.isSameFaceAs(facts)) entry,
    ];
    _entries = [
      for (final entry in _entries)
        if (!entry.facts.isSameFaceAs(facts)) entry,
      (file: file, facts: facts),
    ];
    // The family's files are others now, and so is the name of their set:
    // what the engine was handed for it before is not the family any more.
    _tell();
    // Letters can be set in it already; the answer waits for the disk to
    // say the same.
    await _letGoOf(replaced);
    return (family: facts.family, refusal: null);
  }

  /// Takes [family] off this device: its files go, and letters written in
  /// it are set in the app's own face from here on.
  Future<void> delete(String family) async {
    final gone = [
      for (final entry in _entries)
        if (entry.facts.family == family) entry,
    ];
    if (gone.isEmpty) {
      return;
    }
    _entries = [
      for (final entry in _entries)
        if (entry.facts.family != family) entry,
    ];
    _tell();
    await _letGoOf(gone);
  }

  /// Writes the index as it stands, and takes the files of [gone] — entries
  /// it no longer lists — off this device, once whoever still needs their
  /// bytes has them ([_beforeLettingGo]).
  Future<void> _letGoOf(List<FontLibraryEntry> gone) async {
    if (gone.isNotEmpty) {
      await _beforeLettingGo?.call({for (final entry in gone) entry.file});
    }
    await Future.wait([
      _persistIndex(),
      for (final entry in gone) _service.deleteFont(entry.file),
    ]);
  }

  /// The files of [family], as they are now ([filesSetWith]) — read.
  Future<List<Uint8List>> _filesOf(String family) async {
    final files = filesSetWith(family);
    return [for (final file in files) ?await file.read()];
  }

  /// Reckons what each family is set with, and tells the engine's side and
  /// whoever lists the families.
  ///
  /// The engine's side hears each family's set of files BY NAME — the
  /// files' own names, in one order — so the same files are the same set
  /// whoever holds them, and a set it was handed before is not read again.
  void _tell() {
    _setWith = _familiesNow();
    faces.setHeld({
      for (final MapEntry(key: family, value: files) in _setWith.entries)
        family: ([for (final file in files) file.name]..sort()).join('|'),
    });
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The index as it stands — behind any write still on its way, and never
  /// reaching the editor when it fails (`saveVersionedSettings`).
  Future<void> _persistIndex() => _service.saveIndex(_entries);
}
