import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/font_face_facts.dart';
import '../../services/font_file_reader.dart';
import '../../services/font_library_service.dart';
import '../brush/picked_file.dart';
import 'app_strings.dart';
import 'canvas_letter_faces.dart';

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
  }) : _service = service ?? FontLibraryService(),
       // Every file is offered ([pickAnyFile]); one that is not a font is
       // refused by the read in [importBytes], which says so.
       _picker = picker ?? pickAnyFile {
    faces = CanvasLetterFaces(files: _filesOf, register: register);
    CanvasLetterFaces.current = faces;
  }

  final FontLibraryService _service;
  final FilePicker _picker;

  /// The engine's side of these fonts.
  late final CanvasLetterFaces faces;

  List<FontLibraryEntry> _entries = const [];

  /// The highest number a font file has been kept under, that this run
  /// knows of ([_nextFile]).
  int _lastNumber = 0;
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
      for (final name in rides.keys.toList()..sort(_byName))
        (name: name, ridesInEditedDocuments: rides[name]!),
    ];
  }

  static int _byName(String a, String b) {
    final folded = a.toLowerCase().compareTo(b.toLowerCase());
    return folded != 0 ? folded : a.compareTo(b);
  }

  /// The family called [name], if this device holds it.
  ImportedFontFamily? familyNamed(String name) =>
      families.where((family) => family.name == name).firstOrNull;

  @override
  void dispose() {
    _disposed = true;
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
    // The index is read before a name is minted: a file's name is one past
    // the highest there is, and what there is, is what the index says.
    await load();
    if (_disposed) {
      return (family: null, refusal: null);
    }
    final file = _nextFile(fontFileExtensionOf(bytes));
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
    // The family's files are others now: what the engine was handed for it
    // before is not the family any more.
    _tell(renewed: {facts.family});
    // Letters can be set in it already; the answer waits for the disk to
    // say the same.
    await Future.wait([
      _persistIndex(),
      for (final entry in replaced) _service.deleteFont(entry.file),
    ]);
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
    await Future.wait([
      _persistIndex(),
      for (final entry in gone) _service.deleteFont(entry.file),
    ]);
  }

  /// The name the next font file is kept under: one past the highest this
  /// run has minted or the index holds — so a file brought while another
  /// is still being written does not take its name.
  String _nextFile(String extension) {
    for (final entry in _entries) {
      _lastNumber = math.max(
        _lastNumber,
        fontLibraryFileNumber(entry.file) ?? 0,
      );
    }
    _lastNumber += 1;
    return fontLibraryFileName(_lastNumber, extension: extension);
  }

  /// The files of [family], as they are now.
  Future<List<Uint8List>> _filesOf(String family) async {
    final files = [
      for (final entry in _entries)
        if (entry.facts.family == family) entry.file,
    ];
    return [for (final file in files) ?await _service.readFont(file)];
  }

  /// Tells the engine's side, and whoever lists the families, that they are
  /// others — [renewed] the ones whose files are.
  void _tell({Set<String> renewed = const {}}) {
    faces.setOnDevice({
      for (final entry in _entries) entry.facts.family,
    }, renewed: renewed);
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The index as it stands — behind any write still on its way, and never
  /// reaching the editor when it fails (`saveVersionedSettings`).
  Future<void> _persistIndex() => _service.saveIndex(_entries);
}
