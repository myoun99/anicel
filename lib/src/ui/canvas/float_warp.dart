import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/sync_image_upload.dart' show StraightRgbaRows, pictureOf;
import '../../models/bitmap_tile.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_stamp_image.dart';
import '../../models/canvas_point.dart';
import '../../models/dirty_region.dart';
import '../../models/tile_coord.dart';
import '../../services/bitmap_surface_geometry.dart' show tilesOfRegion;
import '../../services/canvas_selection.dart';
import '../../services/resample/resample_kernel.dart';
import '../../services/stamp_carry.dart';
import '../brush/transform_tool_options.dart';
import 'after_frame_once.dart';
import 'deferred_image_disposal.dart';
import 'transform_box.dart';

// ---------------------------------------------------------------
// The transform preview (P3a).
//
// What is on screen while a box is open is the RESAMPLED float —
// literally the bytes Enter will write — drawn at the rect it will
// land in, with no filtering. It used to be a Skia transform of the
// UNtransformed float: the affine and quad previews were a widget
// `Transform` over tiles drawn at FilterQuality.none, and the mesh
// preview was drawVertices through an ImageShader at
// FilterQuality.medium. So the picture on screen was nearest where
// the commit was bicubic, and smooth where the commit was hard.
//
// With a resampler that can elect to preserve colours exactly, that
// gap stops being cosmetic: the whole reason to turn AA off is to
// SEE what you are going to get, and a preview that shows something
// else defeats the feature it is previewing.
//
// Byte identity is made structural rather than numerical. The commit
// does not recompute — it reuses this exact dab when the key still
// matches. Two computations that ought to agree is a weaker promise,
// and its failure mode (native on one side, Dart on the other; two
// radius floors) is silent.

/// The open box laid over what floats: where the box's points sit on the
/// canvas, the rect a float lands in through it, and a float resampled
/// through it.
///
/// A view of the selection layer's state at one moment — built on demand
/// from the box, the pending lift stamps and the tool's knobs, owning none
/// of them. The box's warp and its LAW live on [BoxWarp]; this is where
/// that warp puts a float.
class FloatWarp {
  const FloatWarp({
    required this.box,
    required this.float,
    required this.options,
    required this.pasteboard,
  });

  /// The open box, or null when no box is up.
  final TransformBox? box;

  /// The rect the box stands on — the box's own ([TransformBox.baseRect]),
  /// in every mode. The quad's corners and the mesh's grid are laid over
  /// it, so every float rides the one mapping of the canvas ([carry]),
  /// a folder's and a range's alike (I-37 · F-329). Null when no box is up.
  ///
  /// 🚨★★★**THE BOX 일반 DRAWS, NOT THE PIXELS UNDER IT** (F-570, 유저
  /// 2026-11-06: 「선택도구 사용 후 변형도구의 자유변형시 제대로 왼쪽 중앙
  /// 꼭짓점 사각형 클릭했는데 안쪽 클릭한것처럼 그림 자체가 이동하는 동작
  /// 실행됨 … 자유변형만 뭔가 법이 다른가? 확인하고 통일」; F-570-Q1
  /// 「퍼스 · 메쉬도 선택 사각형 위에 세운다」).
  ///
  /// ↩️It was the rect holding every float, and a float is the lifted
  /// pixels' box: the selection's bounds rounded out to whole pixels and
  /// widened by a grow or a feather. 일반 stood on the selection's bounds,
  /// so pressing a 퍼스 grip opened the box onto a wider rect and the same
  /// press, asked again of the opened box, landed off the grip that had
  /// moved — inside, which is the move. What a float holds past the box
  /// follows the mapping on past its edge, as another cel's picture does
  /// (H41, [StampCarry]).
  StampRect? get base => box?.baseRect;

  /// The float THIS warp resamples — one of the session's — or null when
  /// only the box is asked about (its chrome, its carry).
  final BrushDab? float;

  /// Which of 일반/퍼스/메쉬 is armed, and how pixels are resampled.
  final TransformToolOptions options;

  /// The pasteboard wall: nothing lands past it, so nothing is resampled
  /// past it either ([_withinPasteboard]).
  final DirtyRegion pasteboard;

  /// The open box's affine; null when no box is up.
  SelectionAffine? get _affine => box?.affine;

  /// The [base]'s corners (TL/TR/BR/BL) — the quad's BASE. Initializing
  /// corners as affine(base) makes an untouched quad exactly identity for
  /// [transformStampDabQuad].
  List<CanvasPoint>? baseCorners() {
    final rect = base;
    return rect == null ? null : cornersOfStampRect(rect);
  }

  /// The mesh grid's BASE points over the [base], row-major — the mesh's
  /// equivalent of [baseCorners].
  List<CanvasPoint>? meshBasePoints({
    required int columns,
    required int rows,
  }) {
    final rect = base;
    return rect == null
        ? null
        : meshRestGrid(rect, columns: columns, rows: rows);
  }

  /// Base points + offsets through the affine — the control points as they
  /// sit on the canvas. Used for the chrome and hit-testing, which have to
  /// show handles even when every offset is still zero.
  List<CanvasPoint>? _placedPoints(
    List<CanvasPoint>? base,
    List<CanvasPoint>? offsets,
  ) {
    final affine = _affine;
    if (affine == null || base == null) {
      return null;
    }
    return [
      for (var i = 0; i < base.length; i += 1)
        affine.apply(
          offsets == null || i >= offsets.length
              ? base[i]
              : CanvasPoint(
                  x: base[i].x + offsets[i].x,
                  y: base[i].y + offsets[i].y,
                ),
        ),
    ];
  }

  /// The four quad corners as drawn — present whenever 퍼스 is armed over
  /// an open box, warped or not.
  List<CanvasPoint>? get placedCorners {
    final corners = box?.warp.corners;
    return options.mode != TransformMode.perspective || corners == null
        ? null
        : _placedPoints(baseCorners(), corners);
  }

  /// The mesh control points as drawn.
  List<CanvasPoint>? get placedMeshPoints {
    final warp = box?.warp;
    final mesh = warp?.mesh;
    return options.mode != TransformMode.mesh || warp == null || mesh == null
        ? null
        : _placedPoints(
            meshBasePoints(columns: warp.meshColumns, rows: warp.meshRows),
            mesh,
          );
  }

  /// The quad the RESAMPLE runs through, or null when the offsets are all
  /// zero and the affine path is exactly equivalent — see [BoxWarp] on why
  /// an untouched perspective box must not take the quad path.
  List<CanvasPoint>? get warpCorners =>
      BoxWarp.offsetsAreZero(box?.warp.corners) ? null : placedCorners;

  /// The mesh the RESAMPLE runs through; null on all-zero offsets, same
  /// reasoning as [warpCorners].
  List<CanvasPoint>? get meshPoints =>
      BoxWarp.offsetsAreZero(box?.warp.mesh) ? null : placedMeshPoints;

  /// The output rect the open warp makes of the box ([base]) — the rect
  /// the three transform functions compute for a float that stands on it.
  ///
  /// The layer needs it to answer one question before resampling: would a
  /// window actually be smaller than the whole? If not, it asks for NO
  /// window, and then the cache entry is one the commit can reuse. Most
  /// selections are that case, and losing the reuse for all of them
  /// would have traded a big win on the whole picture for a second full
  /// resample on every ordinary Enter.
  ///
  /// ⚠️A float reaching past the box (F-570 — the whole pixels its edge
  /// rounds out to, a grow, a feather) lands a little past this rect. That
  /// only ever answers 「no window」 for a picture whose last pixels are
  /// just off screen, and resamples it whole: the transform functions cut
  /// their own window from their own rect, so nothing shown is cut.
  ({int left, int top, int width, int height})? outputRect() {
    final mesh = placedMeshPoints;
    if (mesh != null) {
      return selectionWarpOutputRect(mesh);
    }
    final quad = placedCorners;
    if (quad != null && !BoxWarp.offsetsAreZero(box?.warp.corners)) {
      return selectionWarpOutputRect(quad);
    }
    final affine = _affine;
    final base = baseCorners();
    if (affine == null || base == null || affine.isIdentity) {
      return null;
    }
    return selectionWarpOutputRect([
      for (final corner in base) affine.apply(corner),
    ]);
  }

  /// What a resample of the open warp belongs to — null when there is
  /// nothing to resample (identity, or no box at all).
  _ResampleKey? _resampleKey({SelectionVisibleRect? visible}) {
    final stamp = float?.stamp;
    if (stamp == null) {
      return null;
    }
    final mesh = meshPoints;
    final quad = warpCorners;
    final affine = _affine;
    final shape = StringBuffer();
    if (mesh != null) {
      final warp = box!.warp;
      shape.write('m${warp.meshColumns},${warp.meshRows}');
      for (final point in mesh) {
        shape.write(':${point.x},${point.y}');
      }
    } else if (quad != null) {
      shape.write('q');
      for (final point in quad) {
        shape.write(':${point.x},${point.y}');
      }
    } else if (affine != null && !affine.isIdentity) {
      // ⛔THE AFFINE SPELLS ITSELF. This used to list its fields here, and
      // the list went stale the day the class grew an anchor — see
      // [SelectionAffine.cacheKey].
      shape.write('a${affine.cacheKey}');
    } else {
      // Identity, or no box at all: the untransformed float is already
      // the right picture and the resampler has nothing to do.
      return null;
    }
    // The window is PART of the key. A preview asks for one and a commit
    // does not, so the commit can never be handed the preview's window by
    // a cache hit — which matters, because a window holds only the pixels
    // on screen and landing it would drop the rest of the picture.
    if (visible != null) {
      shape.write(
        '|v${visible.left},${visible.top},${visible.right},${visible.bottom}',
      );
    }
    return _ResampleKey(options.resampleMode, stamp, shape.toString());
  }

  /// What the open warp does, as a mapping any stamp on the canvas can be
  /// carried through ([StampCarry]): every float, and the picture of every
  /// other cel a confirm over a frame range reaches. Null when there is
  /// nothing to resample — the identity, or no box at all.
  StampCarry? get carry {
    final rect = base;
    if (rect == null) {
      return null;
    }
    // 🚨Nothing is resampled past the pasteboard wall, because nothing
    // lands past it (C-ipad-crash, 2026-09-11). The landing clips at the
    // wall (`bitmap_surface_brush_commit`), but the resample covered the
    // WHOLE transformed box: a picture scaled past the stage built,
    // uploaded and decoded pixels the commit then threw away — 1.9× of a
    // pasteboard-wide lift was a 13338×9428 buffer, 503MB, and every
    // larger scale a larger one. A preview's window is cut to it as well.
    final wall = _withinPasteboard(null);
    final mode = options.resampleMode;
    final mesh = meshPoints;
    if (mesh != null) {
      return MeshCarry(
        (
          base: rect,
          columns: box!.warp.meshColumns,
          rows: box!.warp.meshRows,
          points: mesh,
        ),
        mode: mode,
        within: wall,
      );
    }
    final quad = warpCorners;
    if (quad != null) {
      return QuadCarry(
        base: cornersOfStampRect(rect),
        corners: quad,
        mode: mode,
        within: wall,
      );
    }
    final affine = _affine;
    if (affine != null && !affine.isIdentity) {
      return AffineCarry(affine, mode: mode, within: wall);
    }
    return null;
  }

  /// The float through whatever warp is open — through [carry], the one
  /// place the three warp functions are called from, for every float and
  /// for every other stamp alike.
  BrushDab? _resample({SelectionVisibleRect? visible}) {
    final pending = float;
    if (pending == null) {
      return null;
    }
    return carry?.through(pending, visible: _withinPasteboard(visible));
  }

  /// [visible] cut down to the pasteboard, or the whole pasteboard when
  /// the caller wants everything.
  SelectionVisibleRect _withinPasteboard(SelectionVisibleRect? visible) {
    final wall = pasteboard;
    final left = wall.left.toDouble();
    final top = wall.top.toDouble();
    final right = wall.rightExclusive.toDouble();
    final bottom = wall.bottomExclusive.toDouble();
    if (visible == null) {
      return (left: left, top: top, right: right, bottom: bottom);
    }
    return (
      left: math.max(visible.left, left),
      top: math.max(visible.top, top),
      right: math.min(visible.right, right),
      bottom: math.min(visible.bottom, bottom),
    );
  }

  /// The mesh's outer boundary ring (top row → right column → bottom row
  /// reversed → left column reversed) — the warped region polygon.
  ///
  /// Reads the grid the POINTS were built for, not the current setting:
  /// changing the grid size rebuilds the points, and until it does the two
  /// disagree by exactly enough to index out of the list.
  List<CanvasPoint> meshBoundary(List<CanvasPoint> points) {
    final columns = box!.warp.meshColumns;
    final rows = box!.warp.meshRows;
    CanvasPoint at(int column, int row) => points[row * (columns + 1) + column];
    return [
      for (var column = 0; column <= columns; column += 1) at(column, 0),
      for (var row = 1; row <= rows; row += 1) at(columns, row),
      for (var column = columns - 1; column >= 0; column -= 1) at(column, rows),
      for (var row = rows - 1; row >= 1; row -= 1) at(0, row),
    ];
  }
}

/// The float the transform preview last resampled.
///
/// A test hook. It exists because the contract P3a is built around — "what
/// the preview showed is what Enter writes" — is otherwise unobservable
/// from outside: the preview holds a decoded image and the commit writes
/// bytes, and only the layer sees that both came from one buffer.
///
/// Written and cleared inside `assert(() { ... }())`, which is stripped in
/// release. `@visibleForTesting` is an analyzer annotation and removes
/// nothing from a build, so an unguarded assignment here would pin the
/// last transform's straight-alpha buffer — tens of megabytes for a
/// whole-picture Ctrl+T — for the rest of the process, in every shipped
/// app, released by nothing.
@visibleForTesting
BrushDab? debugLastResampledFloat;

/// Records [dab] for the test hook and returns true, so it can sit inside
/// an assert and vanish from release builds.
bool _recordResampledFloat(BrushDab? dab) {
  debugLastResampledFloat = dab;
  return true;
}

/// What a cached resample belongs to: the mode, the source stamp, and the
/// warp's numbers.
///
/// The source is compared by IDENTITY. A lift stamp's bytes never change
/// in place — a new lift means a new stamp — so identity is the exact
/// question, and comparing multi-megabyte cels by value on every drag
/// frame would cost more than the resample this is guarding.
///
/// ↩️The stamp's bytes stood here, for their identity alone — and a stamp
/// the engine carried onto the canvas (a posed row's lift,
/// `EngineStampPictures.carried`) was read back from it at the first move
/// of the hand to be asked which one it was (2026-11-11).
class _ResampleKey {
  const _ResampleKey(this.mode, this.source, this.shape);

  final ResampleMode mode;
  final BrushStampImage source;
  final String shape;

  @override
  bool operator ==(Object other) =>
      other is _ResampleKey &&
      other.mode == mode &&
      identical(other.source, source) &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(mode, identityHashCode(source), shape);
}

/// What the resample preview asks of the layer: the window a drag clips it
/// to, and a way to say the picture changed.
abstract interface class FloatWarpHost {
  /// The visible rect the PREVIEW clips to mid-drag; null means all of it.
  SelectionVisibleRect? previewVisibleRect();

  /// The resample shown changed — repaint.
  void previewChanged();
}

/// A resample as the screen shows it ([FloatResamplePreview.shown]): the
/// [dab] it is, the rect it lands on ([BrushStampImage.landingRect]), its
/// pixels as tiles there — what the engine lays — and their [picture],
/// made only for a canvas that asks.
///
/// 🧭관제 2026-11-11 18:47 (a-float-premultiplies-in-the-c-each-step):
/// 「플로트를 엔진에 놓아(`EngineHeld` 길) Flutter 표시용 디코드 자체를
/// 없애는 쪽이다」. The canvas lays [tiles] and draws no picture, so none
/// is made for it — as a text in hand stands (`CelTextLanding.standing`).
/// ↩️Every resample was premultiplied by the C and uploaded whole for the
/// screen (`decodeStraightRgbaImage`), each step of the hand, while the
/// canvas laid its tiles and drew that picture nowhere.
final class FloatResampleShown {
  FloatResampleShown._(this.dab, this.landing, this.tiles);

  /// [dab] as the screen shows it: its pixels as tiles where its stamp
  /// lands.
  factory FloatResampleShown.of(BrushDab dab) {
    final stamp = dab.stamp!;
    final landing = stamp.landingRect(dab.center);
    return FloatResampleShown._(
      dab,
      landing,
      tilesOfRegion(landing, stamp.rgba),
    );
  }

  final BrushDab dab;
  final DirtyRegion landing;
  final Map<TileCoord, BitmapTile> tiles;

  ui.Image? _picture;

  /// [tiles]' picture through the door every tile takes ([pictureOf]),
  /// made the first time a canvas that draws pictures asks: a host with no
  /// composite behind it.
  ui.Image get picture => _picture ??= pictureOf(
    StraightRgbaRows(dab.stamp!.rgba, landing.width, landing.height),
  );

  /// Test seam: whether [picture] has been made.
  @visibleForTesting
  bool get debugPictured => _picture != null;

  /// Lets [picture] go, past the frames that may still draw it
  /// ([DeferredImageDisposer]).
  void _letGo() {
    if (_picture case final made?) {
      DeferredImageDisposer.instance.retire(made);
    }
  }
}

/// A float's RESAMPLED preview while a warp is open (Ctrl+T, a quad, a
/// mesh): the newest resample of its pending stamp through the warp, as
/// the screen shows it.
///
/// One per float, owned by the float for the session's lifetime, and
/// EMPTY outside a warp: every session end calls [discard], which is also
/// what lets go of a whole-picture resample (tens of megabytes on a big
/// cel). The layer keeps the warp's geometry and answers for it ([_warp],
/// and the window through [FloatWarpHost]); this keeps the resamples, and
/// the coalescing that makes them.
class FloatResamplePreview {
  FloatResamplePreview(this._host, this._warp);

  final FloatWarpHost _host;

  /// The open box over THIS float, as the layer holds it right now.
  final FloatWarp Function() _warp;

  /// The newest resample, keyed by what it belongs to.
  ({_ResampleKey key, BrushDab dab})? _resampled;

  /// The newest resample as the screen shows it — what the engine lays
  /// (`SelectionFloatPaint.heldTiles`): one field, so its dab, its landing
  /// and its tiles cannot belong to two resamples. Null where the float's
  /// own pixels show it: a move ([_runIfIdle]).
  ///
  /// ↩️It was the last resample whose decode had finished, a step or more
  /// behind [_resampled] — 「Deliberately NOT compared against
  /// [_resampled]」, for a guard demanding the two agree would have hidden
  /// the preview the whole time a decode was in flight — until nothing was
  /// decoded for it.
  FloatResampleShown? _shown;

  /// What the screen shows of the warp — the newest resample — or null
  /// while it shows none.
  FloatResampleShown? get shown => _shown;

  bool _dirty = false;

  /// The frame [_runIfIdle] waits on.
  final AfterFrameOnce _frame = AfterFrameOnce();

  /// Whether what is shown is what the box asks for now: none asked for
  /// since ([schedule]).
  bool get caughtUp => !_dirty;

  /// Ask for the preview to catch up.
  ///
  /// Safe to call from inside a setState: it never calls setState itself.
  /// The frame's job does, after the frame.
  void schedule() {
    _dirty = true;
    _frame.ask(_runIfIdle);
  }

  /// Coalescing is the whole design. One resample a frame ([_frame]): every
  /// pointer move before it ends only sets the dirty flag, and the job runs
  /// the LAST state rather than each intermediate one. Without it a drag
  /// would run one full-canvas resample per pointer event and fall further
  /// behind with every frame.
  ///
  /// ↩️One upload at a time was the gate — the resample shown waited on
  /// its decode, and the next ran when that ended — until the screen took
  /// the resample's tiles: nothing is decoded for it now, so nothing paces
  /// the hand but the frame. 「THE GATE IS EXACTLY THE UPLOAD'S LIFETIME,
  /// and it is released structurally」 — a refused decode had left it
  /// closed for ever, the handles and ants at 60 fps over pixels that
  /// stopped.
  ///
  /// It also degrades honestly. On a machine with no native engine the
  /// Dart reference is roughly fifteen times slower, so the preview
  /// updates a few times a second while the handles and the ants stay at
  /// 60 fps — and the state just before Enter is always the exact one,
  /// because the last scheduling always runs.
  void _runIfIdle() {
    if (!_dirty) {
      return;
    }
    // The PREVIEW clips to the viewport (ABI 26). A whole-picture
    // transform is millions of pixels and the screen holds under one, so
    // most of every pointer move used to go into pixels nobody could see.
    // The window keeps the whole rect's pixel grid, so what is drawn is
    // exactly what the commit will land there — measured byte for byte
    // over 70 transforms in `resample_clip_parity_test.dart`.
    //
    // A selection that already fits gets no window at all, and stays on
    // the path where the commit reuses this very buffer.
    final visible = _host.previewVisibleRect();
    final warp = _warp();
    final key = warp._resampleKey(visible: visible);
    if (key == null) {
      _dirty = false;
      if (_resampled != null || _shown != null) {
        discard();
      }
      return;
    }
    if (_resampled?.key == key) {
      _dirty = false;
      return;
    }
    _dirty = false;
    final dab = warp._resample(visible: visible);
    final stamp = dab?.stamp;
    if (dab == null || stamp == null) {
      return;
    }
    _resampled = (key: key, dab: dab);
    assert(_recordResampledFloat(dab));
    // 🚨A MOVE IS NOT UPLOADED (a-drag-in-an-open-box-resamples-a-move,
    // 2026-10-16). A warp that only moves the float — a translation, or a
    // quad or grid dragged whole — hands back the float's own picture at
    // another centre (`transformStampDab`, `stampDabMovedWholesale`), and
    // the float's own pixels already draw that, at that place. Uploading
    // it again cost a decode of the whole picture per move of the hand, and
    // on a row that keys a colour away it made every move a new landing.
    // ↩️Only the drag that OPENS a box knew this (`MoveDrag` skipped the
    // schedule); a drag inside an open box, and a typed X/Y, uploaded.
    // The resample is kept: it is what the confirm lands ([warped]).
    if (identical(stamp, warp.float?.stamp)) {
      _letGoOfTheShown();
      return;
    }
    // Straight, as the resampler made it: the app's storage convention,
    // which premultiplying the RESULT would round away — the very colours
    // Pick exists to carry through untouched. What a picture of it needs
    // multiplied, the door multiplies on a copy ([FloatResampleShown]).
    _shown?._letGo();
    _shown = FloatResampleShown.of(dab);
    _host.previewChanged();
  }

  /// Lets go of everything: the cache and what is shown. Every session
  /// end, and the layer's dispose — a resample is the size of the
  /// selection.
  void discard() {
    _dirty = false;
    _resampled = null;
    _letGoOfTheShown();
    // The hook holds a whole resampled cel. Letting it outlive the session
    // that made it would keep that buffer resident for as long as the app
    // runs, which is the same defect in a debug build that the assert
    // guard prevents in a release one.
    assert(_recordResampledFloat(null));
  }

  /// Lets go of what is shown, and of its picture if one was made.
  void _letGoOfTheShown() {
    _shown?._letGo();
    _shown = null;
  }

  /// The cached resample, or a fresh one — what every COMMIT path calls.
  ///
  /// Deliberately asks for no window. The preview clips to the viewport
  /// and its cache entry is keyed on that, so this cannot hit it: the
  /// commit gets the whole picture or computes it, and never lands a
  /// rectangle of one.
  BrushDab? warped() {
    final warp = _warp();
    final key = warp._resampleKey();
    if (key == null) {
      return null;
    }
    final cached = _resampled;
    if (cached != null && cached.key == key) {
      return cached.dab;
    }
    return warp._resample();
  }
}
