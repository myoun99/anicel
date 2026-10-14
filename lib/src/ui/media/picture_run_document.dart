import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/in_flight.dart';
import '../../models/media_asset.dart';
import '../../services/media/media_byte_source.dart';
import '../../services/media/viewer_document.dart';
import 'open_viewer_document.dart';

/// A NUMBERED RUN AS ONE DOCUMENT — a page per picture (`A1` · `A2` · `A3`
/// …), so the import window's preview pages through the run and its
/// transport's IN/OUT pick the pictures that come in, as a movie's pick its
/// frames.
///
/// 🗣️F-282 (유저 2026-10-09, 시안 ③ · ④): 「연번은 들어갈 범위만(A2–A3) —
/// 미리보기의 IN/OUT, 동영상과 같은 법」.
///
/// Each picture opens through the viewer's door ([openViewerDocument]) —
/// the still the window shows a picture alone as — and only when its page
/// is asked for: a run can be hundreds of scans, and an open picture holds
/// its encoded file. The few asked for last stay open ([keptOpen]); the
/// rest are let go, and opened again if they are asked for again.
///
/// ⚠️A page's size is its picture's once that has opened — until then the
/// first picture's (the scans of one sheet are one size). A page is drawn
/// in its own picture's shape whatever size it was asked at, and the
/// preview stands its loading widget until the page lands, by which time
/// the size it reads is the picture's own: nothing is ever shown stretched
/// to a neighbour's shape.
final class PictureRunDocument implements ViewerDocument {
  PictureRunDocument._(this._files, this._openOne, ViewerDocument first) {
    _keep(0, first);
  }

  /// Opens the run of [files], in order — null when its first picture
  /// cannot be read.
  static Future<PictureRunDocument?> open(
    List<String> files, {
    required HoldMediaBytes hold,
  }) => openThrough(
    files,
    (file) => openViewerDocument(
      mediaAssetKindForPath(file) ?? MediaAssetKind.image,
      file,
      hold: hold,
      soundPeaks: (_) async => null,
    ),
  );

  /// [open], each picture through [openOne] — the viewer's door there.
  @visibleForTesting
  static Future<PictureRunDocument?> openThrough(
    List<String> files,
    Future<ViewerDocument?> Function(String file) openOne,
  ) async {
    if (files.isEmpty) {
      return null;
    }
    final first = await openOne(files.first);
    if (first == null || first.pageCount == 0) {
      await first?.dispose();
      return null;
    }
    return PictureRunDocument._(files, openOne, first);
  }

  /// How many pictures stay open at once.
  static const int keptOpen = 3;

  final List<String> _files;
  final Future<ViewerDocument?> Function(String file) _openOne;

  /// The pictures open, the one asked for last at the end.
  final LinkedHashMap<int, ViewerDocument> _open = LinkedHashMap();

  /// Each picture's size, from the moment it first opened.
  final Map<int, ui.Size> _sizes = {};

  /// Pictures on their way open — one open per picture, however many asks.
  final InFlight<int, ViewerDocument> _opening = InFlight();

  /// Pages being rendered: their pictures are not let go under them.
  final Map<int, int> _rendering = {};

  bool _disposed = false;

  @override
  int get pageCount => _files.length;

  /// A run turns no pages by itself: it is paged by hand, as a book is.
  @override
  double? get framesPerSecond => null;

  @override
  ui.Size pageSize(int pageIndex) => _sizes[pageIndex] ?? _sizes[0]!;

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    // The size the ask was worked out from — the first picture's, for one
    // that has not opened yet.
    final asked = pageSize(pageIndex);
    _rendering[pageIndex] = (_rendering[pageIndex] ?? 0) + 1;
    try {
      final picture = await _picture(pageIndex);
      final own = picture.pageSize(0);
      final at = width / asked.width;
      return await picture.renderPage(
        0,
        width: (own.width * at).round().clamp(1, 1 << 13).toInt(),
        height: (own.height * at).round().clamp(1, 1 << 13).toInt(),
      );
    } finally {
      final left = _rendering[pageIndex]! - 1;
      if (left == 0) {
        _rendering.remove(pageIndex);
      } else {
        _rendering[pageIndex] = left;
      }
      _letGoOfTheFarthest();
    }
  }

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) async => (await _picture(pageIndex)).readRegionRgba(0, box);

  @override
  Future<void> dispose() async {
    _disposed = true;
    final open = [..._open.values];
    _open.clear();
    for (final picture in open) {
      await picture.dispose();
    }
  }

  /// [pageIndex]'s picture, opened if it is not — and asked for last.
  Future<ViewerDocument> _picture(int pageIndex) {
    final open = _open.remove(pageIndex);
    if (open != null) {
      _open[pageIndex] = open;
      return Future.value(open);
    }
    return _opening.join(pageIndex, () => _openAndKeep(pageIndex));
  }

  /// Opens [pageIndex]'s picture and keeps it — ONCE however many asks
  /// wait on it, so one that cannot stay is let go once.
  Future<ViewerDocument> _openAndKeep(int pageIndex) async {
    final opened = await _openOne(_files[pageIndex]);
    if (opened == null || opened.pageCount == 0) {
      await opened?.dispose();
      throw StateError('the picture ${_files[pageIndex]} could not be read');
    }
    if (_disposed) {
      await opened.dispose();
      throw StateError('the run was let go of while it opened');
    }
    _keep(pageIndex, opened);
    return opened;
  }

  void _keep(int pageIndex, ViewerDocument picture) {
    _open.remove(pageIndex);
    _open[pageIndex] = picture;
    _sizes[pageIndex] = picture.pageSize(0);
  }

  /// Lets go of the pictures asked for longest ago, past [keptOpen] — never
  /// one a render is still reading.
  void _letGoOfTheFarthest() {
    for (final page in [..._open.keys]) {
      if (_open.length <= keptOpen) {
        return;
      }
      if (_rendering.containsKey(page)) {
        continue;
      }
      final picture = _open.remove(page)!;
      unawaited(picture.dispose());
    }
  }
}
