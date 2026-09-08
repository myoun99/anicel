import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_mask.dart';
import '../../services/brush_tip_defaults.dart';
import '../../services/brush_tip_image_codec.dart';
import '../../services/brush_tip_library_service.dart';
import 'picked_file.dart';

Future<PickedFile?> _openTipImageDialog() async {
  final file = await openFile(
    // 🚨Every file (유저 2026-08-29); a non-image is refused by the decode
    // below, which already reports failure.
    acceptedTypeGroups: const [],
  );
  if (file == null) {
    return null;
  }
  return (name: file.name, bytes: await File(file.path).readAsBytes());
}

/// The shared brush tip library: every sampled tip the app can put on a
/// brush, whether it was generated, imported with a brush pack, or added by
/// the user from an image.
///
/// Tips are a resource in their own right, not preset payload. That is what
/// lets one tip serve many brushes without repeating its bytes, and what
/// lets a tip that arrived with an import outlive the brush it came with —
/// deleting a preset never deletes a tip.
class BrushTipLibrary extends ChangeNotifier {
  BrushTipLibrary({BrushTipLibraryService? service, FilePicker? picker})
    : _service = service ?? BrushTipLibraryService(),
      _picker = picker ?? _openTipImageDialog;

  final BrushTipLibraryService _service;
  final FilePicker _picker;

  List<BrushTipEntry> _tips = List.of(defaultBrushTipEntries);
  var _userSequence = 0;
  bool _disposed = false;

  /// Built-in tips first, then the user's, in index order.
  List<BrushTipEntry> get tips => _tips;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// The mask behind [id], or `null` when the library has no such tip (or
  /// has not finished decoding it). Callers treat null as "use the
  /// parametric round tip" — a tip that cannot be found must never take a
  /// brush down with it.
  BrushTipMask? maskFor(String id) {
    for (final tip in _tips) {
      if (tip.id == id) {
        return tip.mask;
      }
    }
    return null;
  }

  /// Loads in two passes: the index first, so names and thumbnails are on
  /// screen immediately, then the images. Decoding a folder of PNGs is
  /// asynchronous, and a grid that fills in after the user has already
  /// reached for it is worse than one that starts complete and sharpens.
  Future<void> load() async {
    final indexed = await _service.loadIndex();
    if (_disposed) {
      return;
    }
    _tips = [...defaultBrushTipEntries, ...indexed];
    _notify();

    if (indexed.isEmpty) {
      return;
    }
    final loaded = <String, BrushTipMask>{};
    for (final entry in indexed) {
      final mask = await _service.loadMask(entry.id);
      if (mask != null) {
        loaded[entry.id] = mask;
      }
    }
    if (_disposed || loaded.isEmpty) {
      return;
    }
    _tips = [
      for (final tip in _tips)
        loaded[tip.id] == null ? tip : tip.copyWith(mask: loaded[tip.id]),
    ];
    _notify();
  }

  /// Adds [mask] to the library under [name], writing its image. Used by
  /// brush-pack import (which brings its own ids, so re-importing replaces
  /// rather than duplicates) and by the user adding an image by hand.
  Future<BrushTipEntry> register(
    BrushTipMask mask, {
    required String name,
  }) async {
    final entry = await _service.writeImage(mask, name: name);
    if (_disposed) {
      return entry;
    }
    _tips = [
      for (final tip in _tips)
        if (tip.id != entry.id) tip,
      entry,
    ];
    _notify();
    unawaited(_persistIndex());
    return entry;
  }

  /// Reads an image the user picked and registers it as a tip. Returns a
  /// user-facing message when it could not be read OR could not be written;
  /// `null` on success.
  ///
  /// 🪦The second half of that sentence is new (2026-09-08) and so is the
  /// arm below it. `encodeBrushTipImage` used to wait on a decode callback
  /// the engine never invokes when it refuses, so a tip whose image the
  /// engine would not take made this function never return at all — the
  /// dialog simply stayed busy. Now the refusal arrives, and a function
  /// whose whole contract is 「a sentence or null」 is where it belongs.
  Future<String?> registerImageBytes(
    Uint8List bytes, {
    required String name,
  }) async {
    _userSequence += 1;
    final id = sanitizeBrushTipId(nextUserBrushTipId(sequence: _userSequence));
    final BrushTipMask mask;
    try {
      mask = await decodeBrushTipImage(bytes, id: id);
    } on Object catch (_) {
      return 'That image could not be read as a brush tip.';
    }
    if (!mask.alpha.any((value) => value > 0)) {
      // An all-transparent tip paints nothing at all; saying so beats
      // handing the user a brush that silently does not work.
      return 'That image has no visible shape to use as a tip.';
    }
    try {
      await register(mask, name: name);
    } on Object {
      return 'That tip could not be saved.';
    }
    return null;
  }

  /// Picks an image and registers it as a tip, naming it after the file.
  /// Returns a user-facing message on failure, `null` on success, and
  /// `null` when the picker was simply cancelled.
  Future<String?> importFromFile() => importPickedFile(
    pick: _picker,
    disposed: () => _disposed,
    import: (pick) => registerImageBytes(pick.bytes, name: pick.stem),
  );

  void rename(String id, String name) {
    _tips = [
      for (final tip in _tips)
        tip.id == id && !tip.builtIn ? tip.copyWith(name: name) : tip,
    ];
    _notify();
    unawaited(_persistIndex());
  }

  /// Removes a user tip. Built-ins are generated on every launch, so there
  /// is nothing to remove; presets still pointing at a deleted tip fall back
  /// to the round tip rather than breaking.
  Future<void> delete(String id) async {
    final target = _tips.where((tip) => tip.id == id).firstOrNull;
    if (target == null || target.builtIn) {
      return;
    }
    _tips = [
      for (final tip in _tips)
        if (tip.id != id) tip,
    ];
    _notify();
    await _service.deleteImage(id);
    unawaited(_persistIndex());
  }

  Future<void> _persistIndex() async {
    try {
      await _service.saveIndex(_tips);
    } on Object catch (_) {
      // Index persistence must never take the editor down; the in-memory
      // library stays correct until the next successful write.
    }
  }
}
