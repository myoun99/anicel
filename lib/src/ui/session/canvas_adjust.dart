import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';

/// What is being adjusted ON the canvas — a cut's canvas by its edges
/// (I-79) or the project camera's frame by its size (I-80). ONE at a time:
/// the canvas holds one box and one pill, and 확정 lands one thing.
///
/// ⛔Two kinds, not one draft with a flag beside it: the canvas's edges
/// move the picture where an edge is pulled out, and the camera's size
/// keeps its frame's middle, so they say different things about the same
/// drag.
sealed class AdjustDraft {
  const AdjustDraft();
}

/// A cut's canvas being resized on the canvas (I-79, 유저 2026-10-06:
/// 「캔버스에서 직접 변 끌면서 조정하는 기능」): its edges where they stand,
/// in the canvas's own coordinates — the canvas as it is spans (0, 0) to its
/// size, and an edge pulled out lies past it.
final class CanvasEdgesDraft extends AdjustDraft {
  const CanvasEdgesDraft({required this.cut, required this.edges});

  /// [cut]'s canvas of [size], its edges where the canvas's are.
  CanvasEdgesDraft.of(CutId cut, CanvasSize size)
    : this(
        cut: cut,
        edges:
            Offset.zero & Size(size.width.toDouble(), size.height.toDouble()),
      );

  /// The cut whose canvas is being adjusted.
  final CutId cut;
  final Rect edges;

  /// The size the edges make, in whole pixels.
  CanvasSize get size =>
      CanvasSize(width: edges.width.round(), height: edges.height.round());

  /// Where the picture moves on the canvas the edges make
  /// (`ResizeCutCanvasCommand.contentOffset`): an edge pulled out to the
  /// left by 50 moves it 50 to the right.
  ({double dx, double dy}) get contentOffset =>
      (dx: -edges.left, dy: -edges.top);
}

/// What the camera's frame keeps while it is adjusted on the canvas
/// (I-80-Q2, 유저 2026-10-08: 「알약에 비율 버튼 — 리스트 팝오버」): nothing,
/// the ratio it had when 「지금 비율」 was picked, or a screen's.
///
/// 🗣️「비율 프리셋은 영화나 tv나 그런곳에서 사용하는 공식적인 비율 그대로 사용.
/// 21:9가 시네마스코프 공식비율이면 문제없음」 — it is not: 21:9 names TV and
/// monitor panels, and the anamorphic scope's ratio is 2.39:1, so that is
/// the one here.
enum CameraRatioLock {
  free,
  current,
  wide(16 / 9),
  scope(2.39),
  standard(4 / 3),
  square(1);

  const CameraRatioLock([this.fixed]);

  /// The ratio (width over height) this lock holds when it holds one of
  /// its own — null for [free], and for [current], whose ratio is the
  /// frame's.
  final double? fixed;
}

/// The project camera's frame being resized on the canvas (I-80, 유저
/// 2026-10-06: 「캔버스에서 카메라 사이즈 보면서 변경 … 용지에 카메라 프레임
/// 그려져있는데, 거기 1:1로 맞추기 위해서」): its [size], and the ratio it
/// keeps ([lock], [ratio]).
final class CameraSizeDraft extends AdjustDraft {
  const CameraSizeDraft({
    required this.size,
    this.lock = CameraRatioLock.free,
    this.ratio,
  });

  final CanvasSize size;
  final CameraRatioLock lock;

  /// What [lock] keeps, width over height — null while it keeps nothing.
  final double? ratio;

  /// This frame keeping [to]: a ratio of its own, or the one the frame has
  /// now — the width staying and the height following.
  CameraSizeDraft locked(CameraRatioLock to) {
    final keeps =
        to.fixed ??
        (to == CameraRatioLock.current ? size.width / size.height : null);
    return CameraSizeDraft(
      size: _kept(size, keeps, acrossLeads: true),
      lock: to,
      ratio: keeps,
    );
  }

  /// This frame scaled [across] and [down] about its middle — what the
  /// transform box's two scales give a drag (I-80-Q1: 「가운데가 그대로 —
  /// 크기만 바뀐다」; 유저: 「카메라 사이즈 변경은 변형도구 규칙 그대로」) — in
  /// whole pixels, at least one, still keeping [ratio]: the side the drag
  /// moved leads, the other follows.
  CameraSizeDraft scaled(double across, double down) => CameraSizeDraft(
    size: _kept(
      CanvasSize(
        width: math.max(1, (size.width * across.abs()).round()),
        height: math.max(1, (size.height * down.abs()).round()),
      ),
      ratio,
      // An edge's middle moves its one side; a corner moves both alike.
      acrossLeads: across != 1 || down == 1,
    ),
    lock: lock,
    ratio: ratio,
  );

  static CanvasSize _kept(
    CanvasSize size,
    double? ratio, {
    required bool acrossLeads,
  }) {
    if (ratio == null) {
      return size;
    }
    return acrossLeads
        ? CanvasSize(
            width: size.width,
            height: math.max(1, (size.width / ratio).round()),
          )
        : CanvasSize(
            width: math.max(1, (size.height * ratio).round()),
            height: size.height,
          );
  }
}

/// The ONE thing being adjusted on the canvas ([AdjustDraft]), while it is.
///
/// The PROJECT's (a project per tab), like its framing: the box and its
/// pill stand on that project's canvas, and the window that opens it is
/// that project's.
class CanvasAdjust extends ChangeNotifier {
  AdjustDraft? _draft;
  AdjustDraft? _showing;

  /// What is being adjusted, as the last grab let it go; null when nothing
  /// is.
  AdjustDraft? get draft => _draft;

  /// What is being adjusted as the canvas shows it — mid-drag where the
  /// hand has it.
  AdjustDraft? get shown => _showing ?? _draft;

  bool get isOpen => _draft != null;

  /// The camera frame's size as the canvas shows it while it is adjusted
  /// (I-80) — what the frame's dim and hairline stand on then; null while
  /// the camera is not being adjusted.
  CanvasSize? get cameraSizeShown => switch (shown) {
    CameraSizeDraft(:final size) => size,
    _ => null,
  };

  /// Whether it is open on [cut]'s canvas. A canvas's edges are that
  /// canvas's alone: one left open on a cut the canvas no longer shows is
  /// let go of, never shown or landed on the cut it shows now. The camera's
  /// frame is every cut's.
  bool isOpenOn(CutId? cut) => switch (_draft) {
    CanvasEdgesDraft(cut: final open) => open == cut,
    CameraSizeDraft() => true,
    null => false,
  };

  /// Opens [draft] — and so closes whatever was open.
  void begin(AdjustDraft draft) {
    _draft = draft;
    _showing = null;
    notifyListeners();
  }

  /// Where a grab has it, before it lets go.
  void show(AdjustDraft draft) {
    _showing = draft;
    notifyListeners();
  }

  /// Where a grab let it go.
  void move(AdjustDraft draft) {
    _draft = draft;
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
    if (_draft == null) {
      return;
    }
    _draft = null;
    _showing = null;
    notifyListeners();
  }
}
