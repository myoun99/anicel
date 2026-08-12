import '../../models/canvas_point.dart';
import '../../services/resample/resample_kernel.dart';

/// How much freedom the transform box hands the pointer.
///
/// The three are not three implementations — they are one state at three
/// levels of freedom. The box always carries an affine plus a per-point
/// OFFSET list, and the mode only decides how many of those offsets the
/// user may move:
///
///   final point i = affine.apply(base point i + offset i)
///
///   normal      offsets pinned at zero
///   perspective the four corners may move (a homography)
///   mesh        every grid point may move (a triangulated warp)
///
/// That is what makes a mode switch cheap and lossless in the widening
/// direction: promoting adds freedom without touching a pixel, so nothing
/// has to be baked and resampled on the way through. Narrowing drops the
/// offsets it can no longer hold, and the session caches them so switching
/// back restores the warp.
///
/// TVPaint's tool has 일반변형 and 퍼스펙티브 변형 with 일반 as the default
/// (유저 08-13), and the mesh is our third rung.
enum TransformMode {
  /// 일반변형: scale (aspect locked), rotate, move. Corner handles only —
  /// no edge handles, because a mid-edge handle can only ever mean the
  /// non-uniform scale this mode does not do.
  normal,

  /// 퍼스변형: the four corners move freely, no modifier needed. The edge
  /// handles keep their affine scale, which is where non-uniform scaling
  /// lives now that Shift no longer unlocks the aspect (유저 08-13: 수정자
  /// 기각 — "어차피 일반변형이 종횡비 유지해서").
  perspective,

  /// 메쉬워프: an N×M control grid over the lifted pixels.
  mesh,
}

/// Which point of the box stays put while a scale handle is dragged.
///
/// A HOLD (Alt) cannot be the whole answer on a tablet: the pen is already
/// dragging the handle, so holding a second thing means a second hand on
/// the glass for the length of the drag. So the anchor is a persistent
/// setting and Alt merely inverts it for one drag — the desktop habit
/// keeps working and the tablet gets the same reach without a keyboard.
enum TransformAnchor {
  /// The handle opposite the grabbed one stays fixed (the default).
  oppositeCorner,

  /// The box centre stays fixed — both sides move outward together.
  center,
}

/// Everything the transform tool remembers between drags: the mode, the
/// scale anchor, the resampler, and the mesh grid.
///
/// One object rather than four notifiers threaded through five widgets:
/// the canvas layer reads all of it and the tool settings panel writes all
/// of it, so splitting them would only multiply the plumbing. This is the
/// shape [SelectionMaskOptions] and the fill options already use.
class TransformToolOptions {
  const TransformToolOptions({
    this.mode = TransformMode.normal,
    this.anchor = TransformAnchor.oppositeCorner,
    this.resampleMode = ResampleMode.blend,
    this.meshColumns = defaultMeshCells,
    this.meshRows = defaultMeshCells,
  });

  static const TransformToolOptions defaults = TransformToolOptions();

  /// Mesh grid bounds, in CELLS per axis (points are cells + 1).
  ///
  /// Three is what the mesh shipped with and stays the default; sixteen is
  /// the ceiling because the control points are hit-tested and drawn one
  /// by one, and 17×17 = 289 of them is already a dense thing to aim a pen
  /// at.
  static const int minMeshCells = 2;
  static const int maxMeshCells = 16;
  static const int defaultMeshCells = 3;

  /// 일반 / 퍼스 / 메쉬 — the tool library's three tiles.
  final TransformMode mode;

  /// The scale anchor; Alt inverts it for the duration of one drag.
  final TransformAnchor anchor;

  /// How a transform turns pixels into other pixels: the tent mean that
  /// smooths (AA on), or the coverage argmax that copies source words
  /// through untouched so a two-value drawing stays two-valued (AA off).
  final ResampleMode resampleMode;

  final int meshColumns;
  final int meshRows;

  /// True when the mode pins every offset at zero — the box is a pure
  /// affine and the aspect ratio is locked.
  bool get isUniform => mode == TransformMode.normal;

  TransformToolOptions copyWith({
    TransformMode? mode,
    TransformAnchor? anchor,
    ResampleMode? resampleMode,
    int? meshColumns,
    int? meshRows,
  }) {
    return TransformToolOptions(
      mode: mode ?? this.mode,
      anchor: anchor ?? this.anchor,
      resampleMode: resampleMode ?? this.resampleMode,
      meshColumns: clampMeshCells(meshColumns ?? this.meshColumns),
      meshRows: clampMeshCells(meshRows ?? this.meshRows),
    );
  }

  static int clampMeshCells(int cells) =>
      cells.clamp(minMeshCells, maxMeshCells);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformToolOptions &&
          other.mode == mode &&
          other.anchor == anchor &&
          other.resampleMode == resampleMode &&
          other.meshColumns == meshColumns &&
          other.meshRows == meshRows;

  @override
  int get hashCode =>
      Object.hash(mode, anchor, resampleMode, meshColumns, meshRows);
}

/// The last committed transform, replayed by 재현.
///
/// 유저 확정 08-13: **전역 하나** · 수명은 세션(프로젝트를 닫으면 사라져도
/// 된다) · 재현은 **지금 선택된 모드에** 적용한다(모드를 되돌리지 않는다) ·
/// 🚨**어떤 크기의 소재든 같은 값을 준다.**
///
/// That last clause is why this stores PARAMETERS and not a result: a
/// scale of 120% and a corner pushed 40 px mean the same thing on a
/// thumbnail and on a whole cel, where "the size it came out last time"
/// would not. Everything here is either a ratio, an angle, or a canvas-
/// pixel displacement.
///
/// It lives on the selection channel rather than in the canvas layer
/// because the layer unmounts on every tool switch (R28-S) and a recall
/// that forgets itself the moment you pick the brush is not a recall.
class TransformRecall {
  const TransformRecall({
    required this.tx,
    required this.ty,
    required this.rotationDegrees,
    required this.scale,
    this.cornerOffsets = const [],
    this.meshOffsets = const [],
    this.meshColumns = 0,
    this.meshRows = 0,
  });

  final double tx;
  final double ty;
  final double rotationDegrees;
  final double scale;

  /// Four base-local displacements (TL/TR/BR/BL), empty when the recorded
  /// transform had no perspective.
  final List<CanvasPoint> cornerOffsets;

  /// Base-local displacements for a `(meshColumns + 1) * (meshRows + 1)`
  /// grid, empty when the recorded transform had no mesh warp.
  final List<CanvasPoint> meshOffsets;

  final int meshColumns;
  final int meshRows;

  /// The affine half alone — what 일반변형 can hold, and what a mesh of a
  /// DIFFERENT grid size falls back to (offsets recorded for a 3×3 grid
  /// have nowhere to land on a 5×5 one, so they are dropped rather than
  /// guessed at).
  bool get hasPerspective => cornerOffsets.length == 4;

  bool hasMeshFor({required int columns, required int rows}) =>
      meshColumns == columns &&
      meshRows == rows &&
      meshOffsets.length == (columns + 1) * (rows + 1);

  /// True when replaying this would change nothing — an identity recall is
  /// worth recording (it is a real state the tool passed through) but not
  /// worth offering.
  bool get isIdentity =>
      tx == 0 &&
      ty == 0 &&
      rotationDegrees == 0 &&
      scale == 1 &&
      !cornerOffsets.any((offset) => offset.x != 0 || offset.y != 0) &&
      !meshOffsets.any((offset) => offset.x != 0 || offset.y != 0);
}
