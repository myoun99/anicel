import '../../models/canvas_point.dart';
import '../../services/canvas_selection.dart' show StampRect;
import '../../services/selection_affine.dart';
import '../brush/transform_tool_options.dart' show TransformMode;

/// The whole of an open box's edit, as one step back.
///
/// ⛔**ALL THREE OR NONE.** The affine and the two warps are what an
/// operation can change, and a step that carried only the affine would
/// give 퍼스/메쉬 a step that restores nothing — a law that works in one
/// mode and quietly does not in the others.
typedef TransformStep = ({
  SelectionAffine affine,
  List<CanvasPoint>? cornerOffsets,
  List<CanvasPoint>? meshOffsets,
});

/// THE OPEN TRANSFORM BOX — every value that means something only while a
/// Ctrl+T (or Move-tool) box is up: the affine it applies, the base box it
/// manipulates, its step history and its warp.
///
/// ⛔**ITS PRESENCE IS 「A BOX IS OPEN」.** The layer holds one or none, and
/// closing the box drops it — so no value of a closed box can outlive it
/// ([[make-the-invariant-unrepresentable]]). They were thirteen fields on
/// the layer, each cleared by name in `_clearTransform`, and a base size
/// that was set before any box existed (the Move tool's handle hit test)
/// and zeroed again by hand when the press did not open one.
///
/// ⚠️**NOT A DRAG.** A box outlives every drag inside it and closes on
/// Enter or Escape; `SelectionDrag` is the object that dies with a gesture
/// (its note: what survives a release stays on the layer — this is that).
class TransformBox {
  TransformBox({
    required this.affine,
    required this.baseWidth,
    required this.baseHeight,
  });

  /// The composite affine (P9b); its pivot is the base box's centre.
  SelectionAffine affine;

  /// The base box it manipulates — the shape's AABB when the box opened. A
  /// walk onto another cel re-aims it at that cel's shape, keeping the
  /// values the user set.
  double baseWidth;
  double baseHeight;

  /// The base box on the canvas, before the affine: [baseWidth] ×
  /// [baseHeight] about the pivot.
  StampRect get baseRect => (
    left: affine.pivot.x - baseWidth / 2,
    top: affine.pivot.y - baseHeight / 2,
    width: baseWidth,
    height: baseHeight,
  );

  /// 🚨★★★**ONE OPERATION INSIDE AN OPEN BOX = ONE STEP BACK.**
  ///
  /// 🗣️유저 2026-09-20: 「클튜 보니 좋은점이 있는데, **변형도구 사용시
  /// 변형에 대한 조작마다 언두로 기록**된단거야. 즉 변형도구 사용중에
  /// **앵커포인트 이동하거나, 확대하거나. 이런 동작마다 언두 기록**되고
  /// **확정하면 변형 하나로서의 언두만 작동**. 지금처럼 변형전으로
  /// 돌아가는거지」.
  ///
  /// ⛔**VALUES, NEVER PIXELS.** A step is what an operation changed — the
  /// affine and the warp — and undoing one re-solves the preview from
  /// them. Keeping rasters here would put a copy of the picture on the
  /// stack per drag, which is the memory the whole session model exists to
  /// avoid.
  ///
  /// ⚠️It holds the value BEFORE each operation, so the stack is empty
  /// exactly when the box stands as it opened. It dies with the box, because
  /// a confirmed transform is ONE document entry and a cancelled one never
  /// happened.
  final List<TransformStep> steps = [];

  /// The per-point freedom the box carries on top of the affine.
  final BoxWarp warp = BoxWarp();

  /// Whether the box would change any pixel.
  bool get isTransformed => !affine.isIdentity || !warp.isFlat;

  /// Remembers where the box stands, just before an operation moves it.
  ///
  /// ⚠️Called at the START of an operation rather than its end, so the
  /// stack always holds 「what undo goes back to」 and never has to guess
  /// when a gesture finished.
  void pushStep() => steps.add((
    affine: affine,
    cornerOffsets: warp.corners == null ? null : List.of(warp.corners!),
    meshOffsets: warp.mesh == null ? null : List.of(warp.mesh!),
  ));

  /// Takes one operation back. False when there is nothing left to take.
  bool popStep() {
    if (steps.isEmpty) {
      return false;
    }
    final step = steps.removeLast();
    affine = step.affine;
    warp.corners = step.cornerOffsets;
    warp.mesh = step.meshOffsets;
    return true;
  }
}

/// Freedom above the affine: perspective and mesh.
///
/// The box is ALWAYS an affine plus a list of per-point displacements in
/// the box's own (pre-affine) frame:
///
///     final point i = affine.apply(base point i + offset i)
///
/// 일반 keeps every offset at zero, 퍼스 lets the four corners move, 메쉬
/// lets every grid point move. Two consequences are the whole reason for
/// the shape:
///
/// - the numeric channels, the rotate knob and the edge handles all write
///   the AFFINE, so they keep working with a warp open and carry it along
///   instead of fighting it. (Before this, opening a mesh threw away a
///   scale the box already had, because the grid was seeded from the
///   untransformed base rect.)
/// - switching 일반 → 퍼스 → 메쉬 only adds freedom, so it costs nothing
///   and changes no pixel. Narrowing stashes what it drops, so switching
///   back restores the warp rather than losing it.
///
/// Non-zero offsets are what puts the resample on the quad or mesh path;
/// all-zero offsets fall through to the affine one, so an untouched
/// perspective box produces the same bytes an 일반 box would. Two
/// computations that ought to agree is the weaker promise.
class BoxWarp {
  /// Base-local displacements for the four corners (TL/TR/BR/BL), or null
  /// outside 퍼스 mode.
  List<CanvasPoint>? corners;

  /// Base-local displacements for the mesh grid, row-major, or null outside
  /// 메쉬 mode. [meshColumns]/[meshRows] record the grid they were built for
  /// — changing the grid size rebuilds them.
  List<CanvasPoint>? mesh;
  int meshColumns = 0;
  int meshRows = 0;

  // What a narrowing mode switch put aside, so widening again restores the
  // warp instead of starting flat.
  List<CanvasPoint>? _stashedCorners;
  List<CanvasPoint>? _stashedMesh;
  int _stashedMeshColumns = 0;
  int _stashedMeshRows = 0;

  /// The points last taken in hand — pressed on the canvas, or written from
  /// the tool settings — by their place in the mode's offsets ([corners] or
  /// [mesh]): what the canvas and the settings' list both light.
  ///
  /// 🗣️F-586 (유저 2026-11-12): 「다시말하지만 화면에서 조작하는건 설정쪽에서도
  /// 보여야함. 지금 중간 왼쪽아래 사각형 조작했는데 도구설정패널에서 바뀌는게
  /// 없는거 보고 확인함. 포인트별로 좌표 둔다거나. 최대한 알기쉽게」 — and
  /// F-586-Q1 (11-14) 「모든 점 목록」. A grid sixteen cells a side lists 289
  /// points, so the one just moved has to be told from the rest on both
  /// sides.
  ///
  /// ⚠️ON THE WARP, so it goes with the box and with the points it names: a
  /// mode or a grid that changes them leaves nothing in hand
  /// ([syncToMode]), and neither does 리셋 ([reset]).
  List<int> inHand = const [];

  static bool offsetsAreZero(List<CanvasPoint>? offsets) =>
      offsets == null ||
      !offsets.any((offset) => offset.x != 0 || offset.y != 0);

  static List<CanvasPoint> zeroOffsets(int count) =>
      List<CanvasPoint>.generate(count, (_) => CanvasPoint(x: 0, y: 0));

  /// Whether no point is displaced — the affine alone says where it lands.
  bool get isFlat => offsetsAreZero(corners) && offsetsAreZero(mesh);

  /// 리셋's half of the warp: every displacement back to zero in the mode
  /// that holds one, and nothing kept aside to restore.
  void reset() {
    corners = corners == null ? null : zeroOffsets(4);
    mesh = mesh == null
        ? null
        : zeroOffsets((meshColumns + 1) * (meshRows + 1));
    _stashedCorners = null;
    _stashedMesh = null;
    inHand = const [];
  }

  /// Brings the offset lists in line with [mode] over an OPEN box.
  ///
  /// Widening restores whatever the last narrowing stashed (so a mode
  /// round-trip is not a way to lose a warp), and carries the corners
  /// across the 퍼스 ↔ 메쉬 boundary so the outline survives the switch.
  ///
  /// ⚠️ 퍼스 → 메쉬 keeps the OUTLINE, not the pixels: the quad maps
  /// through a homography and the mesh through a triangulation, so the
  /// interior lands slightly differently. The corners are what the eye is
  /// holding onto, so they are what is preserved.
  void syncToMode(
    TransformMode mode, {
    required int columns,
    required int rows,
  }) {
    switch (mode) {
      case TransformMode.normal:
        _stash();
        corners = null;
        mesh = null;
      case TransformMode.perspective:
        if (corners != null) {
          return;
        }
        final fromMesh = meshCornerOffsets();
        _stash();
        mesh = null;
        corners =
            fromMesh ??
            (_stashedCorners == null
                ? zeroOffsets(4)
                : List.of(_stashedCorners!));
      case TransformMode.mesh:
        if (mesh != null && meshColumns == columns && meshRows == rows) {
          return;
        }
        final seed = corners ?? _stashedCorners;
        _stash();
        corners = null;
        mesh =
            _stashedMesh != null &&
                _stashedMeshColumns == columns &&
                _stashedMeshRows == rows
            ? List.of(_stashedMesh!)
            : _meshFromCorners(seed, columns: columns, rows: rows);
        meshColumns = columns;
        meshRows = rows;
    }
    // The points are other points now — every branch that kept them as they
    // were has returned.
    inHand = const [];
  }

  void _stash() {
    if (corners != null && !offsetsAreZero(corners)) {
      _stashedCorners = List.of(corners!);
    }
    if (mesh != null && !offsetsAreZero(mesh)) {
      _stashedMesh = List.of(mesh!);
      _stashedMeshColumns = meshColumns;
      _stashedMeshRows = meshRows;
    }
  }

  /// Where each point a list reads stands in [corners]: the quad is kept
  /// TL/TR/BR/BL, the way its outline walks it, and read as the two rows of
  /// two it is — top left, top right, bottom left, bottom right. Its own
  /// inverse.
  static const List<int> _quadAsRead = [0, 1, 3, 2];

  /// The mode's displacements as a list reads them — row by row from the
  /// top, each row left to right: the 메쉬 grid as it is kept, the 퍼스 quad
  /// through [_quadAsRead]. Null in 일반, which holds none.
  List<CanvasPoint>? get asRead {
    final quad = corners;
    return mesh ??
        (quad == null ? null : [for (final kept in _quadAsRead) quad[kept]]);
  }

  /// [inHand] as places in [asRead].
  List<int> get inHandAsRead => mesh != null
      ? inHand
      : [for (final kept in inHand) _quadAsRead[kept]];

  /// Puts the point [asRead] lists [index]-th where [change] says — handed
  /// where it stands now — and takes it in hand. Nothing in 일반, or past
  /// the list's end.
  ///
  /// ⚠️A NEW LIST, as a drag leaves one: a step back holds the list it was
  /// handed ([TransformBox.pushStep] copies, the live reading does not).
  void moveRead(int index, CanvasPoint Function(CanvasPoint now) change) {
    final grid = mesh;
    final offsets = grid ?? corners;
    if (offsets == null || index < 0 || index >= offsets.length) {
      return;
    }
    final kept = grid != null ? index : _quadAsRead[index];
    final moved = List.of(offsets)..[kept] = change(offsets[kept]);
    if (grid != null) {
      mesh = moved;
    } else {
      corners = moved;
    }
    inHand = [kept];
  }

  /// The mesh grid's four corner displacements, in TL/TR/BR/BL order.
  List<CanvasPoint>? meshCornerOffsets() {
    final offsets = mesh;
    if (offsets == null) {
      return null;
    }
    CanvasPoint at(int column, int row) =>
        offsets[row * (meshColumns + 1) + column];
    return [
      at(0, 0),
      at(meshColumns, 0),
      at(meshColumns, meshRows),
      at(0, meshRows),
    ];
  }

  /// A fresh grid whose CORNERS carry [corners] and whose interior is flat
  /// — bilinear would only pretend the homography came along.
  static List<CanvasPoint> _meshFromCorners(
    List<CanvasPoint>? corners, {
    required int columns,
    required int rows,
  }) {
    final flat = zeroOffsets((columns + 1) * (rows + 1));
    if (corners == null || corners.length != 4) {
      return flat;
    }
    flat[0] = corners[0];
    flat[columns] = corners[1];
    flat[rows * (columns + 1) + columns] = corners[2];
    flat[rows * (columns + 1)] = corners[3];
    return flat;
  }
}
