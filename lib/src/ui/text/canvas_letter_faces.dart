import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../theme/app_theme.dart' show AppTypography;

/// Hands the engine one font file, to be drawn with under [engineFamily].
typedef FontFaceRegistrar =
    Future<void> Function(Uint8List bytes, {required String engineFamily});

/// The files a family is set with now — none when they cannot be read.
typedef FontFaceFiles = Future<List<Uint8List>> Function(String family);

/// THE FACES A CANVAS LETTER CAN BE SET IN BESIDE THE APP'S OWN (R9-rest,
/// the text tool's faces): which families are held — by this device, or by
/// the project on screen — and what the engine calls each set of files it
/// has been handed.
///
/// 🚨A FACE IS HANDED TO THE ENGINE WHEN LETTERS ARE FIRST ASKED FOR IN IT,
/// and not at launch. A CJK font is ten to thirty megabytes and the engine
/// keeps every byte of every face it is handed for as long as the app runs
/// — while a text on a cel shows from its baked plate, which needs no face
/// at all. So a face costs its memory on the day somebody edits letters in
/// it (the save · memory session's note of 2026-10-06, under 유저's standing
/// rule that an old tablet is not made to carry what it does not use).
///
/// So a family is in one of three states, and only this knows which: NOT
/// HELD (letters in it are set in the app's own face — a project from
/// another machine that does not carry it, a face since deleted), ON ITS
/// WAY (asked for and still being read), and IN THE ENGINE. Whoever keeps
/// something measured in letters hears of every change through [changes],
/// or keeps the [generation] it was measured at.
///
/// ⚠️The engine cannot let go of a face, and a second file handed to it
/// under a name it knows JOINS the first. So the engine never hears a
/// family's own name: each SET OF FILES handed over gets a name minted
/// here.
///
/// 🚨★★★**AND A SET OF FILES IS HANDED OVER ONCE, WHOEVER HOLDS IT**
/// ([setHeld]). Which files a family is set with moves — a face brought
/// again as other bytes, another project on screen that carries its own —
/// and moves BACK: two projects in two tabs. Kept by the family, each move
/// read the files again and handed the engine one more copy it never lets
/// go of. Kept by the set, the files a family had before are still called
/// what they were called, and coming back to them reads nothing.
class CanvasLetterFaces {
  CanvasLetterFaces({FontFaceFiles? files, FontFaceRegistrar? register})
    : _files = files ?? _noFiles,
      _register = register ?? _handToEngine;

  /// The faces of this run. Whoever owns the device's fonts stands its own
  /// here (`ImportedFonts`); until then no family is held, and every letter
  /// is set in the app's own face.
  static CanvasLetterFaces get current => _current;
  static CanvasLetterFaces _current = CanvasLetterFaces();
  static set current(CanvasLetterFaces faces) {
    _current = faces;
    _changes.tell();
  }

  /// Tells of every change in what letters would be set in: a face arriving
  /// in the engine, a family no longer held, other faces standing as
  /// [current].
  static Listenable get changes => _changes;
  static final _FaceChanges _changes = _FaceChanges();

  static Future<List<Uint8List>> _noFiles(String family) async => const [];

  static Future<void> _handToEngine(
    Uint8List bytes, {
    required String engineFamily,
  }) => ui.loadFontFromList(bytes, fontFamily: engineFamily);

  /// Minted engine names, counted across every instance: the engine is one
  /// for the whole process, whoever is asking it.
  static int _minted = 0;

  /// Every [generation] there has been, of any instance — so the count one
  /// instance stands at is never the count another stood at, and a layout
  /// kept under [current] is not taken for one under its successor.
  static int _generations = 0;

  final FontFaceFiles _files;
  final FontFaceRegistrar _register;

  /// The families held now, each with the name its set of files is known
  /// by ([setHeld]).
  Map<String, String> _held = const {};

  /// What the engine calls each set of files it has been handed, by the
  /// set's name — kept for as long as the engine keeps the files, which is
  /// for good.
  final Map<String, String> _inEngine = {};

  /// The sets being read now, by name.
  final Map<String, Future<void>> _onTheirWay = {};

  /// The sets that could not be had after all — their files gone, or not
  /// ones the engine takes — until what is held is said again ([setHeld]).
  final Set<String> _notHad = {};
  int _generation = _generations += 1;
  bool _disposed = false;

  /// Whether [family] is one of the app's own faces, which every letter can
  /// always be set in — null is the first of them.
  static bool isAppFace(String? family) =>
      family == null ||
      family == AppTypography.bundledFamily ||
      AppTypography.bundledFallback.contains(family);

  /// Counts every change in what letters would be set in. A layout kept
  /// from an earlier count is a layout in other faces.
  int get generation => _generation;

  /// Whether [family] is held — in the engine or not yet.
  bool holds(String family) {
    final files = _held[family];
    return files != null && !_notHad.contains(files);
  }

  /// What the engine calls [family] — null when letters in it are set in
  /// the app's own face: the family is not held, or is on its way.
  ///
  /// 🚨Asking for a family that is held and not in the engine yet SENDS FOR
  /// IT ([sendFor]). Whoever lays letters out is thereby whoever causes
  /// their face to be read, and nobody has to remember to.
  String? engineFamilyOf(String? family) {
    if (family == null) {
      return null;
    }
    if (isAppFace(family)) {
      return family;
    }
    sendFor(family);
    return _inEngine[_held[family]];
  }

  /// Whether [family] is held and not in the engine yet — sent for, if
  /// nobody had.
  bool isOnItsWay(String? family) {
    sendFor(family);
    return _onTheirWay.containsKey(_held[family]);
  }

  /// Completes when none of [families] is on its way any more — null when
  /// none of them is now, so that whoever asks goes on without a pause.
  Future<void>? whenHere(Iterable<String?> families) {
    final waits = [
      for (final family in families)
        if (isOnItsWay(family)) _onTheirWay[_held[family]]!,
    ];
    return waits.isEmpty ? null : Future.wait(waits);
  }

  /// Has [family]'s files read and handed to the engine, if it is held and
  /// that has not been done or begun. Nothing, for any other.
  void sendFor(String? family) {
    final files = _held[family];
    if (_disposed ||
        family == null ||
        files == null ||
        _notHad.contains(files) ||
        _inEngine.containsKey(files) ||
        _onTheirWay.containsKey(files)) {
      return;
    }
    _onTheirWay[files] = _fetch(family, files).whenComplete(() {
      // What is taken off is this very future, done as of now.
      unawaited(_onTheirWay.remove(files));
      _changed();
    });
  }

  /// Reads [family]'s files — the set called [files], as it stands at this
  /// call — and hands them to the engine under one fresh name.
  ///
  /// What is kept is kept for the SET: a family said to be set with other
  /// files while these were being read is simply not called by this name,
  /// and is read again when next asked for — while these are in the engine
  /// all the same, and are what the family is called if it comes back to
  /// them.
  Future<void> _fetch(String family, String files) async {
    final engineFamily = 'anicel-face-${_minted += 1}';
    var handed = 0;
    try {
      for (final bytes in await _files(family)) {
        await _register(bytes, engineFamily: engineFamily);
        handed += 1;
      }
    } on Object {
      // A face the engine would not take is a face nobody holds, as one
      // whose file is gone is.
      handed = 0;
    }
    if (_disposed) {
      return;
    }
    if (handed == 0) {
      _notHad.add(files);
    } else {
      _inEngine[files] = engineFamily;
    }
  }

  /// Says which families are held now, and — for each — the name its SET OF
  /// FILES is known by: the same name for the same files, another for any
  /// other (`ImportedFonts` makes it of the names the files are kept
  /// under, and one of those means one set of bytes for good).
  ///
  /// A family that is not in [held] is no longer drawn with. One whose set
  /// is another now is drawn with the app's face until that set is in the
  /// engine — read when next asked for, unless it was handed over before.
  void setHeld(Map<String, String> held) {
    if (_notHad.isEmpty && mapEquals(held, _held)) {
      return;
    }
    // Said again, what could not be had is asked for once more: its files
    // may be somewhere they were not.
    _notHad.clear();
    _held = Map.of(held);
    _changed();
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    _generation = _generations += 1;
    if (identical(this, _current)) {
      _changes.tell();
    }
  }

  /// Stops reading: what is on its way is let finish and comes to nothing.
  void dispose() {
    _disposed = true;
  }
}

class _FaceChanges extends ChangeNotifier {
  void tell() => notifyListeners();
}
