import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';

/// A canvas being resized ON the canvas (I-79, 유저 2026-10-06: 「캔버스에서
/// 직접 변 끌면서 조정하는 기능」): its edges where they stand now, in the
/// canvas's own coordinates — the canvas as it is spans (0, 0) to its size,
/// and an edge pulled out lies past it.
///
/// The PROJECT's (a project per tab), like its framing: the box and its
/// pill stand on that project's canvas, and the size window that opens it
/// is that project's.
class CanvasAdjust extends ChangeNotifier {
  CutId? _cut;
  Rect? _edges;
  Rect? _showing;

  /// The cut whose canvas is being adjusted; null when none is.
  CutId? get cut => _cut;

  bool get isOpen => _edges != null;

  /// Whether it is open on [cut]'s canvas. Its edges are that canvas's
  /// alone: one left open on a cut the canvas no longer shows is let go of,
  /// never shown or landed on the cut it shows now.
  bool isOpenOn(CutId? cut) => isOpen && _cut == cut;

  /// The edges as the canvas shows them — mid-drag where the hand has them.
  Rect? get shown => _showing ?? _edges;

  /// The size the edges make, in whole pixels.
  CanvasSize? get size {
    final edges = _edges;
    return edges == null
        ? null
        : CanvasSize(
            width: edges.width.round(),
            height: edges.height.round(),
          );
  }

  /// Where the picture moves on the canvas the edges make
  /// (`ResizeCutCanvasCommand.contentOffset`): an edge pulled out to the
  /// left by 50 moves it 50 to the right.
  ({double dx, double dy})? get contentOffset {
    final edges = _edges;
    return edges == null ? null : (dx: -edges.left, dy: -edges.top);
  }

  /// Opens the adjust on [cut]'s canvas of [size], its edges where the
  /// canvas's are.
  void begin(CutId cut, CanvasSize size) {
    _cut = cut;
    _edges =
        Offset.zero & Size(size.width.toDouble(), size.height.toDouble());
    _showing = null;
    notifyListeners();
  }

  /// Where a grab has the edges, before it lets go.
  void show(Rect edges) {
    _showing = edges;
    notifyListeners();
  }

  /// Where a grab let the edges go.
  void move(Rect edges) {
    _edges = edges;
    _showing = null;
    notifyListeners();
  }

  /// A grab went away with nothing to keep.
  void dropShowing() {
    if (_showing == null) {
      return;
    }
    _showing = null;
    notifyListeners();
  }

  /// Closes the adjust — after it landed, or for nothing (✕, Escape).
  void end() {
    if (_edges == null) {
      return;
    }
    _cut = null;
    _edges = null;
    _showing = null;
    notifyListeners();
  }
}
