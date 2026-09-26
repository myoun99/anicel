import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/brush_stamp_image.dart';
import 'brush_stroke_commit_data.dart';

/// The last drawing action, held so 확정 can lay it down again.
///
/// 🗣️유저 2026-09-24 (confirm-button-Q2): 「일반상태=마지막 스트로크 재입력」,
/// and how: 「그냥 브러시로 다시 그린다기보단 **그린걸 픽셀 보관해서 덮는게**
/// 가장 쉽고 깔끔하고 가벼운 근본적인 방법」. So this holds what the stroke
/// funnel LANDED — the brush, the eraser, the bucket, a shape fill and a
/// stamp all go through it — with the blend it landed with, so an erase lays
/// down as an erase. Laying it down again is one step and one undo.
///
/// Lifetime (유저 08-27): until the app closes. It survives cuts and
/// projects, like [CutPieceSlot] and for the same reason: it holds dabs and
/// pixels, nothing that belongs to the project it came from.
class LastStrokeSlot extends ChangeNotifier {
  LastStrokeSlot() {
    census.add(this);
  }

  /// Every slot alive — one per app — for [allStrokeBytes].
  static final Set<LastStrokeSlot> census = <LastStrokeSlot>{};

  /// What every held stroke costs, read by the memory census directly —
  /// counted once, like the cut piece and for its reason
  /// ([CutPieceSlot.allPieceBytes]).
  static int get allStrokeBytes {
    var total = 0;
    for (final slot in census) {
      total += slot.strokeBytes;
    }
    return total;
  }

  BrushStrokeCommitData? _stroke;

  BrushStrokeCommitData? get stroke => _stroke;

  /// Remembers [stroke] as the last drawing action.
  ///
  /// ⛔Without its promotion. Those tiles were blended against the cel the
  /// stroke landed on, so they could never be laid down anywhere else — and
  /// holding them would keep that cel's pictures alive for as long as the
  /// app runs.
  void hold(BrushStrokeCommitData stroke) {
    _stroke = BrushStrokeCommitData(
      sourceDabs: stroke.sourceDabs,
      strokePixels: stroke.strokePixels,
      strokeBounds: stroke.strokeBounds,
      blendMode: stroke.blendMode,
      strokeOpacity: stroke.strokeOpacity,
    );
    notifyListeners();
  }

  /// What the held stroke costs resident: its rasterized pixels and the
  /// pictures its dabs stamp (a bucket fill or a cut piece is one dab
  /// carrying the whole picture). Each picture counts once, however many
  /// dabs stamp it.
  int get strokeBytes {
    final stroke = _stroke;
    if (stroke == null) {
      return 0;
    }
    final stamps = <BrushStampImage>{
      for (final dab in stroke.sourceDabs) ?dab.stamp,
    };
    var bytes = stroke.strokePixels?.lengthInBytes ?? 0;
    for (final stamp in stamps) {
      bytes += stamp.rgba.lengthInBytes;
    }
    return bytes;
  }

  /// Installed by the mounted canvas panel, which is the only thing that
  /// can reach a cel to lay the stroke on. Null while no canvas is up — the
  /// same channel shape [CutPieceSlot.pasteAtOriginHandler] has.
  void Function()? get reinputHandler => _reinputHandler;
  void Function()? _reinputHandler;

  /// ⚠️It changes [canReinput], so it is news — sent a microtask later,
  /// because a panel installs it from its own lifecycle, inside a build.
  set reinputHandler(void Function()? handler) {
    if (identical(handler, _reinputHandler)) {
      return;
    }
    _reinputHandler = handler;
    scheduleMicrotask(() {
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  bool _disposed = false;

  /// Whether there is a stroke to lay down and a canvas to lay it on.
  bool get canReinput => _stroke != null && _reinputHandler != null;

  void reinput() => _reinputHandler?.call();

  @override
  void dispose() {
    _disposed = true;
    census.remove(this);
    super.dispose();
  }
}
