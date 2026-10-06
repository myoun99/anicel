import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../theme/app_theme.dart' show AppTypography;

/// Hands the engine one font file, to be drawn with under [engineFamily].
typedef FontFaceRegistrar =
    Future<void> Function(Uint8List bytes, {required String engineFamily});

/// The files of one family on this device — none when they cannot be read.
typedef FontFaceFiles = Future<List<Uint8List>> Function(String family);

/// THE FACES A CANVAS LETTER CAN BE SET IN BESIDE THE APP'S OWN (R9-rest,
/// the text tool's faces): which families this device holds, and what the
/// engine calls each one it has been handed.
///
/// 🚨A FACE IS HANDED TO THE ENGINE WHEN LETTERS ARE FIRST ASKED FOR IN IT,
/// and not at launch. A CJK font is ten to thirty megabytes and the engine
/// keeps every byte of every face it is handed for as long as the app runs
/// — while a text on a cel shows from its baked plate, which needs no face
/// at all. So a face costs its memory on the day somebody edits letters in
/// it (the save · memory session's note of 2026-10-06, under 유저's standing
/// rule that an old tablet is not made to carry what it does not use).
///
/// So a family is in one of three states, and only this knows which:
/// NOT ON THE DEVICE (letters in it are set in the app's own face — a
/// project from another machine, a face since deleted), ON ITS WAY (asked
/// for and still being read), and IN THE ENGINE. Whoever keeps something
/// measured in letters hears of every change through [changes], or keeps
/// the [generation] it was measured at.
///
/// ⚠️The engine cannot let go of a face, and a second file handed to it
/// under a name it knows JOINS the first. So the engine never hears a
/// family's own name: each time a family is handed over it gets a name
/// minted here, and a family deleted, or brought again as other bytes,
/// simply stops being called by the old one. (What the old name held stays
/// in the engine until the app closes — the price of a face replaced, paid
/// once per replacement.)
class CanvasLetterFaces {
  CanvasLetterFaces({FontFaceFiles? files, FontFaceRegistrar? register})
    : _files = files ?? _noFiles,
      _register = register ?? _handToEngine;

  /// The faces of this run. Whoever owns the device's fonts stands its own
  /// here (`ImportedFonts`); until then no family is on the device, and
  /// every letter is set in the app's own face.
  static CanvasLetterFaces get current => _current;
  static CanvasLetterFaces _current = CanvasLetterFaces();
  static set current(CanvasLetterFaces faces) {
    _current = faces;
    _changes.tell();
  }

  /// Tells of every change in what letters would be set in: a face arriving
  /// in the engine, a family leaving the device, other faces standing as
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

  Set<String> _onDevice = const {};
  final Map<String, String> _inEngine = {};
  final Map<String, Future<void>> _onTheirWay = {};

  /// How many times each family's files have been said to be others — what
  /// a read that was under way when they changed finds out by.
  final Map<String, int> _renewals = {};
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

  /// Whether this device holds [family] — in the engine or not yet.
  bool holds(String family) => _onDevice.contains(family);

  /// What the engine calls [family] — null when letters in it are set in
  /// the app's own face: the family is not on this device, or is on its way.
  ///
  /// 🚨Asking for a family that is on the device and not in the engine yet
  /// SENDS FOR IT ([sendFor]). Whoever lays letters out is thereby whoever
  /// causes their face to be read, and nobody has to remember to.
  String? engineFamilyOf(String? family) {
    if (family == null) {
      return null;
    }
    if (isAppFace(family)) {
      return family;
    }
    sendFor(family);
    return _inEngine[family];
  }

  /// Whether [family] is on this device and not in the engine yet — sent
  /// for, if nobody had.
  bool isOnItsWay(String? family) {
    sendFor(family);
    return _onTheirWay.containsKey(family);
  }

  /// Completes when none of [families] is on its way any more — null when
  /// none of them is now, so that whoever asks goes on without a pause.
  Future<void>? whenHere(Iterable<String?> families) {
    final waits = [
      for (final family in families)
        if (isOnItsWay(family)) _onTheirWay[family]!,
    ];
    return waits.isEmpty ? null : Future.wait(waits);
  }

  /// Has [family] read and handed to the engine, if this device holds it
  /// and that has not been done or begun. Nothing, for any other.
  void sendFor(String? family) {
    if (_disposed ||
        family == null ||
        !_onDevice.contains(family) ||
        _inEngine.containsKey(family) ||
        _onTheirWay.containsKey(family)) {
      return;
    }
    _onTheirWay[family] = _fetch(family).whenComplete(() {
      // What is taken off is this very future, done as of now.
      unawaited(_onTheirWay.remove(family));
      _changed();
    });
  }

  Future<void> _fetch(String family) async {
    final engineFamily = 'anicel-face-${_minted += 1}';
    final renewal = _renewals[family];
    var handed = 0;
    try {
      for (final bytes in await _files(family)) {
        await _register(bytes, engineFamily: engineFamily);
        handed += 1;
      }
    } on Object {
      // A face the engine would not take is a face this device does not
      // have, as one whose file is gone is.
      handed = 0;
    }
    if (_disposed ||
        !_onDevice.contains(family) ||
        _renewals[family] != renewal) {
      // Gone, or other files now: what was read is not the family any more,
      // and the next to ask for it sends again.
      return;
    }
    if (handed == 0) {
      _onDevice = {..._onDevice}..remove(family);
    } else {
      _inEngine[family] = engineFamily;
    }
  }

  /// Says which families this device holds now. One that has left is no
  /// longer drawn with; one whose FILES changed is named in [renewed] and
  /// is read again when next asked for.
  void setOnDevice(Set<String> families, {Set<String> renewed = const {}}) {
    final gone = [
      for (final family in _inEngine.keys)
        if (!families.contains(family) || renewed.contains(family)) family,
    ];
    if (gone.isEmpty && renewed.isEmpty && setEquals(families, _onDevice)) {
      return;
    }
    gone.forEach(_inEngine.remove);
    for (final family in renewed) {
      _renewals[family] = (_renewals[family] ?? 0) + 1;
    }
    _onDevice = Set.of(families);
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
