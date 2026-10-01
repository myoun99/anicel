import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/brush_dab.dart';
import '../../models/canvas_point.dart';
import '../../models/dirty_region.dart';
import '../../services/canvas_selection.dart';
import '../../services/resample/resample_kernel.dart';
import '../../services/straight_rgba_image.dart'
    show decodeStraightRgbaImage, decodedImageStillWanted;
import '../brush/transform_tool_options.dart';
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

/// The open box laid over the float: where the box's points sit on the
/// canvas, the rect the float lands in through it, and the float resampled
/// through it.
///
/// A view of the selection layer's state at one moment — built on demand
/// from the box, the pending lift stamp and the tool's knobs, owning none
/// of them. The box's warp and its LAW live on [BoxWarp]; this is where
/// that warp puts the float.
class FloatWarp {
  const FloatWarp({
    required this.box,
    required this.float,
    required this.options,
    required this.pasteboard,
  });

  /// The open box, or null when no box is up.
  final TransformBox? box;

  /// The pending lift stamp — the float — or null outside a move session.
  final BrushDab? float;

  /// Which of 일반/퍼스/메쉬 is armed, and how pixels are resampled.
  final TransformToolOptions options;

  /// The pasteboard wall: nothing lands past it, so nothing is resampled
  /// past it either ([_withinPasteboard]).
  final DirtyRegion pasteboard;

  /// The open box's affine; null when no box is up.
  SelectionAffine? get _affine => box?.affine;

  /// The pending stamp's canvas rect corners (TL/TR/BR/BL) — the quad's
  /// BASE. Initializing corners as affine(base) makes an untouched quad
  /// exactly identity for [transformStampDabQuad].
  List<CanvasPoint>? stampRectCorners() {
    final pending = float;
    final stamp = pending?.stamp;
    if (pending == null || stamp == null) {
      return null;
    }
    final left = pending.center.x - stamp.width / 2;
    final top = pending.center.y - stamp.height / 2;
    return [
      CanvasPoint(x: left, y: top),
      CanvasPoint(x: left + stamp.width, y: top),
      CanvasPoint(x: left + stamp.width, y: top + stamp.height),
      CanvasPoint(x: left, y: top + stamp.height),
    ];
  }

  /// The mesh grid's BASE points over the pending stamp's rect, row-major
  /// — the mesh's equivalent of [stampRectCorners].
  List<CanvasPoint>? meshBasePoints({
    required int columns,
    required int rows,
  }) {
    final base = stampRectCorners();
    if (base == null) {
      return null;
    }
    final left = base[0].x;
    final top = base[0].y;
    final width = base[1].x - base[0].x;
    final height = base[3].y - base[0].y;
    return [
      for (var row = 0; row <= rows; row += 1)
        for (var column = 0; column <= columns; column += 1)
          CanvasPoint(
            x: left + column * width / columns,
            y: top + row * height / rows,
          ),
    ];
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
        : _placedPoints(stampRectCorners(), corners);
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

  /// The output rect the open warp would produce — the same rect the
  /// three transform functions compute for themselves.
  ///
  /// The layer needs it to answer one question before resampling: would a
  /// window actually be smaller than the whole? If not, it asks for NO
  /// window, and then the cache entry is one the commit can reuse. Most
  /// selections are that case, and losing the reuse for all of them
  /// would have traded a big win on the whole picture for a second full
  /// resample on every ordinary Enter.
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
    final base = stampRectCorners();
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
    return _ResampleKey(options.resampleMode, stamp.rgba, shape.toString());
  }

  /// The float through whatever warp is open — the ONE place the three
  /// warp functions are called from during a session.
  BrushDab? _resample({SelectionVisibleRect? visible}) {
    final pending = float;
    if (pending == null) {
      return null;
    }
    // 🚨Nothing is resampled past the pasteboard wall, because nothing
    // lands past it (C-ipad-crash, 2026-09-11). The landing clips at the
    // wall (`bitmap_surface_brush_commit`), but the resample covered the
    // WHOLE transformed box: a picture scaled past the stage built,
    // uploaded and decoded pixels the commit then threw away — 1.9× of a
    // pasteboard-wide lift was a 13338×9428 buffer, 503MB, and every
    // larger scale a larger one. A preview's window is cut to it as well.
    final window = _withinPasteboard(visible);
    final mesh = meshPoints;
    if (mesh != null) {
      return transformStampDabMesh(
        pending,
        columns: box!.warp.meshColumns,
        rows: box!.warp.meshRows,
        points: mesh,
        mode: options.resampleMode,
        visible: window,
      );
    }
    final quad = warpCorners;
    if (quad != null) {
      return transformStampDabQuad(
        pending,
        quad,
        mode: options.resampleMode,
        visible: window,
      );
    }
    final affine = _affine;
    if (affine != null && !affine.isIdentity) {
      return transformStampDab(
        pending,
        affine,
        mode: options.resampleMode,
        visible: window,
      );
    }
    return null;
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

/// What a cached resample belongs to: the mode, the source buffer, and the
/// warp's numbers.
///
/// The source is compared by IDENTITY. A lift stamp's bytes never change
/// in place — a new lift means a new buffer — so identity is the exact
/// question, and comparing multi-megabyte cels by value on every drag
/// frame would cost more than the resample this is guarding.
class _ResampleKey {
  const _ResampleKey(this.mode, this.source, this.shape);

  final ResampleMode mode;
  final Uint8List source;
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

/// What the resample preview asks of the layer: the open warp as the layer
/// holds it, the window a drag clips it to, and a way to say the picture
/// changed.
abstract interface class FloatWarpHost {
  bool get mounted;

  /// The open box over the float, as the layer holds it right now.
  FloatWarp get floatWarp;

  /// The visible rect the PREVIEW clips to mid-drag; null means all of it.
  SelectionVisibleRect? previewVisibleRect();

  /// The decoded picture changed — repaint.
  void previewChanged();
}

/// The float's RESAMPLED preview while a warp is open (Ctrl+T, a quad, a
/// mesh): the newest resample of the pending stamp through the warp, and
/// the decoded copy of the last resample that finished — the picture the
/// screen draws.
///
/// Owned by the layer for the layer's lifetime, and EMPTY outside a warp
/// session: every session end calls [discard], which is also what lets go
/// of a whole-picture image (tens of megabytes on a big cel). The layer
/// keeps the warp's geometry and answers for it through [FloatWarpHost];
/// this keeps the pictures, and the coalescing that makes them.
class FloatResamplePreview {
  FloatResamplePreview(this._host);

  final FloatWarpHost _host;

  /// The newest resample, keyed by what it belongs to. Computed and stored
  /// before its decode is even requested.
  ({_ResampleKey key, BrushDab dab})? _resampled;

  /// The premultiplied copy for display, and the dab it was decoded FROM.
  ///
  /// Kept as a pair, and deliberately NOT compared against [_resampled]:
  /// the newest resample is computed and stored before its decode is even
  /// requested, so a guard demanding the two agree would hide the preview
  /// for the whole time a decode is in flight — which is most of a drag.
  /// The float would blink back to its untransformed self on every
  /// pointer move.
  ///
  /// Showing the last COMPLETED resample instead is both the honest
  /// picture (it is a real state the transform passed through) and the
  /// whole point of coalescing. The last scheduling always runs, so the
  /// picture just before Enter is always the exact one.
  ui.Image? _image;
  BrushDab? _imageDab;

  /// The decoded picture, or null while nothing has decoded.
  ui.Image? get image => _image;

  /// The dab [image] was decoded from — where it goes, and what it is.
  BrushDab? get imageDab => _imageDab;

  int _imageRequest = 0;
  bool _inFlight = false;
  bool _dirty = false;

  /// Ask for the preview to catch up.
  ///
  /// Safe to call from inside a setState: it never calls setState itself.
  /// The decode callback does, and that is always a later turn.
  void schedule() {
    _dirty = true;
    _runIfIdle();
  }

  /// Coalescing is the whole design. One resample may be in flight; every
  /// pointer move that arrives while it is only sets the dirty flag, and
  /// the decode callback runs the LAST state rather than each intermediate
  /// one. Without it a drag would queue one full-canvas resample per
  /// pointer event and fall further behind with every frame.
  ///
  /// It also degrades honestly. On a machine with no native engine the
  /// Dart reference is roughly fifteen times slower, so the preview
  /// updates a few times a second while the handles and the ants stay at
  /// 60 fps — and the state just before Enter is always the exact one,
  /// because the last scheduling always runs.
  void _runIfIdle() {
    if (_inFlight || !_dirty) {
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
    final warp = _host.floatWarp;
    final key = warp._resampleKey(visible: visible);
    if (key == null) {
      _dirty = false;
      if (_resampled != null || _image != null) {
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

    // decodeImageFromPixels wants premultiplied bytes; the resampler
    // produces straight alpha, which is the app's storage convention and
    // must stay that way — premultiplying the RESULT would round the very
    // colours Pick exists to carry through untouched. So the copy is for
    // display only and the dab keeps its own bytes.
    //
    // The copy and the multiply are ONE native pass into native memory,
    // the same fused kernel the fill overlay uses. Doing it as a Dart
    // `Uint8List.fromList` plus a per-pixel loop cost a second full-size
    // allocation and a second full traversal on every frame of a drag,
    // which on a whole-picture transform is tens of megabytes per pointer
    // move.
    //
    // 🪦It was written out here until 2026-09-09, ending 「The scratch is
    // freed in the decode callback, on every path」 — which was true of
    // every path THROUGH the callback, and the callback has a road that
    // never reaches it. [decodeStraightRgbaImage] is the same pass with
    // the release in a `finally`, and hand-rolling it beside it was a copy.
    final request = ++_imageRequest;
    _inFlight = true;
    unawaited(() async {
      final ui.Image? image;
      try {
        image = await decodedImageStillWanted(
          decodeStraightRgbaImage(
            rgba: stamp.rgba,
            width: stamp.width,
            height: stamp.height,
          ),
          wanted: () => _host.mounted && request == _imageRequest,
        );
      } finally {
        // 🚨★★★**THE GATE IS EXACTLY THE UPLOAD'S LIFETIME, and it is
        // released structurally so it cannot be skipped.** A refused
        // decode used to leave it closed for ever: the handles and the
        // marching ants kept running at 60 fps while the transformed
        // pixels stopped, permanently, for that widget.
        //
        // ⛔It is NOT folded into [_imageRequest], and the two are not two
        // spellings of one fact. The request says WHICH ask is current;
        // this says whether an upload is outstanding — see the throughput
        // rule this function's header states. That is why [discard]
        // invalidates the ask and deliberately leaves the gate CLOSED: a
        // discarded upload is still holding a whole-picture scratch and
        // still occupying the engine. Making one field answer both would
        // start a second full-canvas upload on every crossing back
        // through identity.
        _inFlight = false;
      }
      if (image == null) {
        return;
      }
      _image?.dispose();
      _image = image;
      _imageDab = dab;
      _host.previewChanged();
      _runIfIdle();
    }());
  }

  /// Lets go of everything: the cache, the decoded image, an in-flight
  /// decode's claim on the result. Every session end, and the layer's
  /// dispose — the image is a GPU allocation the size of the selection.
  void discard() {
    _imageRequest += 1; // Invalidate an in-flight decode.
    _dirty = false;
    _resampled = null;
    _imageDab = null;
    _image?.dispose();
    _image = null;
    // The hook holds a whole resampled cel. Letting it outlive the session
    // that made it would keep that buffer resident for as long as the app
    // runs, which is the same defect in a debug build that the assert
    // guard prevents in a release one.
    assert(_recordResampledFloat(null));
  }

  /// The cached resample, or a fresh one — what every COMMIT path calls.
  ///
  /// Deliberately asks for no window. The preview clips to the viewport
  /// and its cache entry is keyed on that, so this cannot hit it: the
  /// commit gets the whole picture or computes it, and never lands a
  /// rectangle of one.
  BrushDab? warped() {
    final warp = _host.floatWarp;
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
