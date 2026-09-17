import 'dart:math' as math;

import 'canvas_point.dart';
import 'viewport_point.dart';

class CanvasViewport {
  /// The absolute RENDER-zoom rail — a sanity guard, not the user-facing
  /// limit.
  ///
  /// 🚨R11 moved the user-facing zoom to DISPLAY units (100% = one artwork
  /// pixel per DEVICE pixel), so the reachable percentage is
  /// `render × effectiveRatio` and a rail expressed in render units binds
  /// at a different percentage on every display. At 0.1/16.0 it bound
  /// INSIDE the advertised 10%–1600%: on a 2× tablet the readout's bottom
  /// half did not exist, and — worse — a UI-scale change at either end
  /// silently clamped, so the document view absorbed the scale factor in
  /// full and grew on screen. That is the one thing the exclusion promises
  /// will not happen.
  ///
  /// The rail is now wide enough that it cannot bind for any effective
  /// ratio the ladder can produce (0.75 × 1.0 through 1.5 × 4.0), and
  /// `CanvasZoomScale` carries the real 10%–1600% limit in display units,
  /// where the readout already advertises it.
  static const double minZoom = 0.0125;
  static const double maxZoom = 22.0;

  /// 🚨THE DIGITS A VIEW'S NUMBERS TAKE AFTER THE POINT (F-122).
  ///
  /// 유저 2026-09-13: 「알약에 있는 줌 텍스트도 터치로 조작하면 미세하게
  /// 조작되서 55%랑 56% 사이 숫자가 존재하는데 … **변형가능한만큼 텍스트로도
  /// 표시** … 10.85 까진 가능해도 10.858 이렇게 **세자리째는 막는게**」 ·
  /// 「소수점 조작하는 동작은 기본적으로 **최대치를 소수점 두자리로**」.
  ///
  /// The pill rounded the zoom and the angle to whole numbers while every
  /// verb moved them continuously, so `55%` stood for every zoom from 54.5
  /// to 55.5 and the number you read was not the view you had. ⛔Writing
  /// more digits alone only moves that gap to the next place. So the VALUES
  /// land on the grid their readouts write ([onReadoutGrid]) and the
  /// readouts write every digit: what the pill says IS the view.
  ///
  /// The angle lands right here, in [rotatedAround]. The zoom is read in
  /// DISPLAY percent, which takes a ratio this model does not have — it
  /// lands in `CanvasZoomScale.landed`, on this same grid.
  static const int readoutDecimals = 2;

  static final double _readoutLinesPerUnit = math
      .pow(10, readoutDecimals)
      .toDouble();

  /// [value] on the nearest line of the readout grid.
  static double onReadoutGrid(double value) =>
      (value * _readoutLinesPerUnit).roundToDouble() / _readoutLinesPerUnit;

  /// [value] on the last line of the readout grid AT OR BELOW it — for a
  /// number that must not grow by landing (a Fit).
  ///
  /// ⚠️The hair added before the floor is a float's worth, not a rule: a
  /// value that IS on a line comes back through a multiply as
  /// 4999.999999999999, and flooring that reads 49.99 for a fit of exactly
  /// 50. A millionth of a line is far below anything a view can show.
  static double belowOnReadoutGrid(double value) =>
      (value * _readoutLinesPerUnit + 1e-6).floorToDouble() /
      _readoutLinesPerUnit;

  CanvasViewport({
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    this.rotationDegrees = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
  }) {
    _validateZoom(zoom);
    _validateFinitePan(panX, 'panX');
    _validateFinitePan(panY, 'panY');
    _validateFinitePan(rotationDegrees, 'rotationDegrees');
  }

  final double zoom;
  final double panX;
  final double panY;

  /// View-only canvas rotation (P8), clockwise degrees in y-down screen
  /// space. Applied AFTER the flips, before zoom/pan: viewport =
  /// translate · scale · rotate · flip · canvas. Never touches artwork or
  /// export — pure navigation state like zoom/pan.
  final double rotationDegrees;

  /// View-only horizontal mirror (P8): applied first, about the canvas
  /// x=0 axis (UI toggles keep the view anchored, so the pivot choice is
  /// invisible to the user).
  final bool flipHorizontal;

  /// View-only vertical mirror (UI-R18 #19), the y-axis sibling of
  /// [flipHorizontal].
  final bool flipVertical;

  double get rotationRadians => rotationDegrees * math.pi / 180;

  /// Whether the view transform is more than zoom/pan (rotation or flip
  /// active) — the panbar/reframe AABB paths key off this.
  bool get hasRotationOrFlip =>
      rotationDegrees != 0 || flipHorizontal || flipVertical;

  CanvasViewport copyWith({
    double? zoom,
    double? panX,
    double? panY,
    double? rotationDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
  }) {
    return CanvasViewport(
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
    );
  }

  CanvasViewport clamped() {
    return copyWith(zoom: zoom.clamp(minZoom, maxZoom).toDouble());
  }

  CanvasViewport translated({required double dx, required double dy}) {
    return copyWith(panX: panX + dx, panY: panY + dy);
  }

  CanvasViewport zoomedAround({
    required double nextZoom,
    required ViewportPoint anchor,
  }) {
    return _withAnchorPreserved(
      zoom: nextZoom.clamp(minZoom, maxZoom).toDouble(),
      rotationDegrees: rotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      anchor: anchor,
    );
  }

  /// Rotates the VIEW to where [nextRotationDegrees] LANDS on the readout
  /// grid ([readoutDecimals]), keeping the canvas point under [anchor] (e.g.
  /// the viewport center or the gesture focal) fixed.
  ///
  /// 🚨Every road that turns the view comes through here — the twist, the
  /// trackpad, the pill's buttons, its drag and a typed angle — so the
  /// landing is HERE and none of them can keep an angle the pill cannot
  /// write. The anchor is solved at the angle that was kept.
  CanvasViewport rotatedAround({
    required double nextRotationDegrees,
    required ViewportPoint anchor,
  }) {
    _validateFinitePan(nextRotationDegrees, 'nextRotationDegrees');
    return _withAnchorPreserved(
      zoom: zoom,
      rotationDegrees: onReadoutGrid(nextRotationDegrees),
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
      anchor: anchor,
    );
  }

  /// Toggles the horizontal mirror, keeping the canvas point under
  /// [anchor] fixed. The whole VIEW mirrors — a rotated view's tilt
  /// mirrors with it (Photoshop flip behavior).
  CanvasViewport flippedAround({required ViewportPoint anchor}) {
    return _withAnchorPreserved(
      zoom: zoom,
      rotationDegrees: rotationDegrees,
      flipHorizontal: !flipHorizontal,
      flipVertical: flipVertical,
      anchor: anchor,
    );
  }

  /// Toggles the vertical mirror around [anchor] (UI-R18 #19).
  CanvasViewport flippedVerticalAround({required ViewportPoint anchor}) {
    return _withAnchorPreserved(
      zoom: zoom,
      rotationDegrees: rotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: !flipVertical,
      anchor: anchor,
    );
  }

  /// The viewport with the given view parameters and pan solved so the
  /// canvas point currently under [anchor] stays under it.
  CanvasViewport _withAnchorPreserved({
    required double zoom,
    required double rotationDegrees,
    required bool flipHorizontal,
    required bool flipVertical,
    required ViewportPoint anchor,
  }) {
    final canvasAnchor = viewportToCanvas(anchor);
    final unpanned = CanvasViewport(
      zoom: zoom,
      rotationDegrees: rotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
    final mapped = unpanned.canvasToViewport(canvasAnchor);
    return CanvasViewport(
      zoom: zoom,
      panX: anchor.x - mapped.x,
      panY: anchor.y - mapped.y,
      rotationDegrees: rotationDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical,
    );
  }

  factory CanvasViewport.fitToView({
    required double canvasWidth,
    required double canvasHeight,
    required double viewportWidth,
    required double viewportHeight,
    double padding = 24.0,
  }) {
    return CanvasViewport.fitToCanvasRect(
      left: 0,
      top: 0,
      width: canvasWidth,
      height: canvasHeight,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      padding: padding,
    );
  }

  /// Fits an arbitrary canvas-space rectangle (e.g. the camera frame's
  /// bounds) centered into the viewport. Rotation and flip RESET (v1: Fit
  /// is also the "straighten the view" gesture).
  ///
  /// [zoomLanding] is the caller's law for which zooms EXIST
  /// (`CanvasZoomScale.landedToFit` — the unit it is written in takes a
  /// ratio this model does not have). 🚨It runs BEFORE the rect is centred:
  /// a zoom rounded afterwards leaves the rect centred for a zoom the view
  /// no longer has.
  factory CanvasViewport.fitToCanvasRect({
    required double left,
    required double top,
    required double width,
    required double height,
    required double viewportWidth,
    required double viewportHeight,
    double padding = 24.0,
    double Function(double zoom)? zoomLanding,
  }) {
    _validateFinitePan(left, 'left');
    _validateFinitePan(top, 'top');
    _validatePositiveFinite(width, 'width');
    _validatePositiveFinite(height, 'height');
    _validatePositiveFinite(viewportWidth, 'viewportWidth');
    _validatePositiveFinite(viewportHeight, 'viewportHeight');
    if (!padding.isFinite || padding < 0) {
      throw ArgumentError.value(
        padding,
        'padding',
        'CanvasViewport.fitToCanvasRect padding must be finite and '
            'non-negative.',
      );
    }

    final usableWidth = (viewportWidth - padding * 2).clamp(1.0, viewportWidth);
    final usableHeight = (viewportHeight - padding * 2).clamp(
      1.0,
      viewportHeight,
    );
    final zoom = (usableWidth / width) < (usableHeight / height)
        ? usableWidth / width
        : usableHeight / height;
    final railedZoom = zoom.clamp(minZoom, maxZoom).toDouble();
    final clampedZoom = zoomLanding == null
        ? railedZoom
        : zoomLanding(railedZoom);

    return CanvasViewport(
      zoom: clampedZoom,
      panX: (viewportWidth - width * clampedZoom) / 2 - left * clampedZoom,
      panY: (viewportHeight - height * clampedZoom) / 2 - top * clampedZoom,
    );
  }

  ViewportPoint canvasToViewport(CanvasPoint point) {
    if (!hasRotationOrFlip) {
      return ViewportPoint(x: point.x * zoom + panX, y: point.y * zoom + panY);
    }
    final d = _rotatedFlippedScaled(point.x, point.y);
    return ViewportPoint(x: d.x + panX, y: d.y + panY);
  }

  /// Maps a canvas-space DELTA into viewport space (the linear forward
  /// transform — no pan): what a canvas-space vector measures on screen.
  /// The mirror of [viewportDeltaToCanvasDelta], and the authority for
  /// anything that has to draw a canvas-sized shape in screen coordinates.
  ViewportPoint canvasDeltaToViewportDelta({
    required double dx,
    required double dy,
  }) {
    if (!hasRotationOrFlip) {
      return ViewportPoint(x: dx * zoom, y: dy * zoom);
    }
    return _rotatedFlippedScaled(dx, dy);
  }

  /// The flip, rotation and zoom half of both canvas→viewport conversions
  /// — everything but the pan.
  ///
  /// ⛔TWO CONVERSIONS SHARE IT — the point (which adds pan last) and the
  /// DELTA (which does not, because a delta has no origin) — and the six
  /// lines of trigonometry were written twice. A sign flipped in one of
  /// them and not the other is a drag that fights the pointer only while
  /// the canvas is turned. The inverse pair shares [_rotatedFlipped] for
  /// the same reason.
  ViewportPoint _rotatedFlippedScaled(double cx, double cy) {
    final x = flipHorizontal ? -cx : cx;
    final y = flipVertical ? -cy : cy;
    final radians = rotationRadians;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return ViewportPoint(
      x: (x * cos - y * sin) * zoom,
      y: (x * sin + y * cos) * zoom,
    );
  }

  /// The rotation and flip half of both viewport→canvas conversions,
  /// applied to an already-unzoomed vector.
  ///
  /// ⛔TWO CONVERSIONS SHARE IT — the point (which subtracts pan first)
  /// and the DELTA (which does not, because a delta has no origin) — and
  /// the six lines of trigonometry were written twice. A sign flipped in
  /// one of them and not the other is a drag that fights the pointer only
  /// while the canvas is turned.
  CanvasPoint _rotatedFlipped(double ux, double uy) {
    final radians = rotationRadians;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    final rx = ux * cos + uy * sin;
    final ry = -ux * sin + uy * cos;
    return CanvasPoint(
      x: flipHorizontal ? -rx : rx,
      y: flipVertical ? -ry : ry,
    );
  }

  CanvasPoint viewportToCanvas(ViewportPoint point) {
    if (!hasRotationOrFlip) {
      return CanvasPoint(
        x: (point.x - panX) / zoom,
        y: (point.y - panY) / zoom,
      );
    }
    return _rotatedFlipped((point.x - panX) / zoom, (point.y - panY) / zoom);
  }

  /// Maps a viewport-space pointer DELTA into canvas space (the linear
  /// inverse — no pan): what a drag by (dx, dy) on screen moves in canvas
  /// coordinates. The single authority for every drag-delta conversion
  /// that used to divide by zoom.
  CanvasPoint viewportDeltaToCanvasDelta({
    required double dx,
    required double dy,
  }) {
    if (!hasRotationOrFlip) {
      return CanvasPoint(x: dx / zoom, y: dy / zoom);
    }
    return _rotatedFlipped(dx / zoom, dy / zoom);
  }

  Map<String, dynamic> toJson() => {
    'zoom': zoom,
    'panX': panX,
    'panY': panY,
    if (rotationDegrees != 0) 'rotation': rotationDegrees,
    if (flipHorizontal) 'flipH': flipHorizontal,
    if (flipVertical) 'flipV': flipVertical,
  };

  factory CanvasViewport.fromJson(Map<String, dynamic> json) {
    return CanvasViewport(
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panX: (json['panX'] as num?)?.toDouble() ?? 0.0,
      panY: (json['panY'] as num?)?.toDouble() ?? 0.0,
      rotationDegrees: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: json['flipH'] as bool? ?? false,
      flipVertical: json['flipV'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasViewport &&
          other.zoom == zoom &&
          other.panX == panX &&
          other.panY == panY &&
          other.rotationDegrees == rotationDegrees &&
          other.flipHorizontal == flipHorizontal &&
          other.flipVertical == flipVertical;

  @override
  int get hashCode => Object.hash(
    zoom,
    panX,
    panY,
    rotationDegrees,
    flipHorizontal,
    flipVertical,
  );

  @override
  String toString() =>
      'CanvasViewport(zoom: $zoom, panX: $panX, panY: $panY, '
      'rotationDegrees: $rotationDegrees, flipHorizontal: $flipHorizontal, '
      'flipVertical: $flipVertical)';
}

void _validateZoom(double value) {
  if (!value.isFinite || value <= 0.0) {
    throw ArgumentError.value(
      value,
      'zoom',
      'CanvasViewport.zoom must be finite and greater than 0.',
    );
  }
}

void _validateFinitePan(double value, String fieldName) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      fieldName,
      'CanvasViewport.$fieldName must be finite.',
    );
  }
}

void _validatePositiveFinite(double value, String fieldName) {
  if (!value.isFinite || value <= 0.0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'CanvasViewport.$fieldName must be finite and greater than 0.',
    );
  }
}
