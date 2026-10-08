import 'package:flutter/widgets.dart';

import '../../models/app_input_settings.dart';
import '../../models/canvas_viewport.dart';
import '../../models/viewport_point.dart';
import '../effective_device_pixel_ratio.dart';

/// The two units a document view's zoom is spoken in, and the one number
/// that converts between them.
///
/// ## The convention (유저 확정 2026-08-21)
///
/// **100% means one artwork pixel per DEVICE pixel** — the Photoshop /
/// Clip Studio / Krita convention, which the user chose explicitly
/// ("맞추는쪽으로") after asking what the other tools do. So the zoom a
/// user reads, types and drags is measured in DEVICE pixels per artwork
/// pixel, while [CanvasViewport.zoom] stays what every painter and every
/// hit test needs: LOGICAL pixels per artwork pixel.
///
///     render = display / effectiveRatio
///
/// ## The same division also excludes document views from the UI scale
///
/// The user drew the scale's boundary by KIND: the chrome scales, the
/// document views do not — "캔버스패널 베이스패널은 안 걸리는게
/// 맞을거같아", naming the canvas, the media viewer, the conte, the cut
/// envelope and the timesheet. Because the UI scale multiplies into the
/// effective ratio, one division answers both requirements at once: raise
/// the scale and the render zoom drops by exactly the factor the root
/// matrix just gained, so the artwork covers the same device pixels it
/// did before.
///
/// ⛔That is why there is no second, separate "is this panel excluded?"
/// flag. A document view is excluded by asking for its zoom in display
/// units; a chrome surface never asks at all.
@immutable
class CanvasZoomScale {
  const CanvasZoomScale(double effectiveRatio, {double? ceilingPercent})
    // Normalized in the constructor, like [DeviceGrid], so `==` stays
    // reflexive (NaN != NaN) and no consumer divides by zero.
    : ratio = effectiveRatio > 0 && effectiveRatio < double.infinity
          ? effectiveRatio
          : 1.0,
      // A lock is a stop INSIDE the advertised range: whatever number was
      // typed, the view can stand on it.
      ceilingPercent = ceilingPercent == null
          ? null
          : ceilingPercent < minDisplayZoom * 100
          ? minDisplayZoom * 100
          : ceilingPercent > maxDisplayZoom * 100
          ? maxDisplayZoom * 100
          : ceilingPercent;

  /// The effective device-pixel ratio: monitor × UI scale.
  final double ratio;

  /// 🗣️I-27 (유저 2026-09-13): 「최대 줌 제한기능. 100%이면 100% 넘어서
  /// 확대하지 못하게 락 거는용도. 축소는 이전처럼 자유」. The DISPLAY percent
  /// this view may not be zoomed past, or null where nothing is locked.
  ///
  /// It is the view's, not the app's: asked where the lock holds, 유저 wrote
  /// 「그리기 캔버스만」 (I-27-Q1) — so the drawing canvas says it for what
  /// is under it ([CanvasZoomCeiling]) and a viewer or a sheet, which share
  /// every line of this law, never hears of it.
  final double? ceilingPercent;

  /// The scale in force for [context] — the same source every quantizer
  /// reads. ⛔Not `MediaQuery`, which reports the monitor's raw ratio and
  /// would leave a scaled UI showing a zoom percentage that means nothing.
  static CanvasZoomScale of(BuildContext context) => CanvasZoomScale(
    EffectiveDevicePixelRatio.of(context),
    ceilingPercent: CanvasZoomCeiling.of(context),
  );

  /// What the readout shows for [renderZoom] — device pixels per artwork
  /// pixel.
  double display(double renderZoom) => renderZoom * ratio;

  /// The viewport zoom that renders [displayZoom].
  double render(double displayZoom) => displayZoom / ratio;

  /// The user-facing zoom range, as the readout has always advertised it:
  /// 10% to 1600%, in DEVICE pixels per artwork pixel.
  ///
  /// 🚨It lives here rather than on [CanvasViewport] because it is a
  /// DISPLAY-unit limit, and the render zoom that reaches it moves with the
  /// effective ratio. The model's own `minZoom`/`maxZoom` stayed behind as
  /// a wide sanity rail — if that rail is ever the binding one again, the
  /// exclusion breaks silently at the ends of the range.
  static const double minDisplayZoom = 0.1;
  static const double maxDisplayZoom = 16.0;

  /// 🚨★★★ONE LAW FOR WHERE A ZOOM LANDS (F-122 · I-27): [renderZoom] inside
  /// the advertised range, on the grid the pill writes —
  /// [CanvasViewport.readoutDecimals] digits of a DISPLAY percent.
  ///
  /// 유저 2026-09-13 (F-122): 「알약에 있는 줌 텍스트도 터치로 조작하면 미세하게
  /// 조작되서 55%랑 56% 사이 숫자가 존재하는데 … **변형가능한만큼 텍스트로도
  /// 표시** … **세자리째는 막는게**」 · 2026-09-17: 「캔버스 베이스 패널
  /// 많을테니 **다 법 통일해서** 적용되면되」 · 「**근본/구조적으로**
  /// 해결해줘. 증상만 해결말고」. 유저 2026-09-13 (I-27): 「확대 축소 로직이
  /// 터치랑 추가될 키보드 숏컷이랑 여러곳에 나뉘어져있을 가능성 높으니 **법
  /// 하나로 통일**」.
  ///
  /// It WAS two laws. The pill's verbs — the ± buttons and their keys, the
  /// readout's drag, a typed percentage — stopped at the advertised range
  /// (🪦`clampRender`, which this replaces: 「all three stop at the same
  /// number the label promises」). The pinch, the wheel and the trackpad
  /// stopped only at the model's sanity rail, so a wheel reached 2200% and
  /// the readout's next one-percent nudge threw the view back to 1600%. And
  /// NONE of them landed anywhere the pill could write: it rounded to a
  /// whole percent, so `55%` stood for every zoom from 54.5 to 55.5.
  ///
  /// ⛔Widening the text alone would only move that gap to the third digit.
  /// The ZOOM lands, and the pill writes every digit it has — what it says
  /// IS the view.
  ///
  /// 🆕And under the lock, where one is set ([ceilingPercent], I-27): the
  /// top of the range is the user's number there, for every verb at once —
  /// which is what 「법 하나로 통일」 bought.
  double landed(double renderZoom) {
    final percent = (display(renderZoom) * 100)
        .clamp(minDisplayZoom * 100, ceilingPercent ?? maxDisplayZoom * 100)
        .toDouble();
    return render(CanvasViewport.onReadoutGrid(percent) / 100);
  }

  /// Where a FIT lands: DOWN onto the same grid. The next digit up would put
  /// the edge of what was asked to fit outside the window it was fitted
  /// into.
  ///
  /// ⛔Not held to the advertised range. A Fit has always been free to go
  /// past it — a page far larger than its window fits below 10% — and
  /// nobody has decided otherwise; an invented stop here would make Fit not
  /// fit.
  ///
  /// ↩️Decided since, for a LOCKED view and upward only (유저 2026-10-08,
  /// I-27-Q2: 「화면에 맞추기도 최대 줌에서 멈춘다」): a small canvas fitted
  /// under a lock stands at the lock, smaller than its window. Downward a
  /// Fit is as free as it was.
  double landedToFit(double renderZoom) {
    final asked = display(renderZoom) * 100;
    final ceiling = ceilingPercent;
    final percent = CanvasViewport.belowOnReadoutGrid(
      ceiling != null && asked > ceiling ? ceiling : asked,
    );
    // Below the grid's first line there is nothing to land on.
    return percent > 0 ? render(percent / 100) : renderZoom;
  }

  /// [view] zoomed to where [nextZoom] LANDS ([landed]), the artwork under
  /// [anchor] held still.
  ///
  /// 🚨THE ONE ROAD A ZOOM VERB TAKES — the pinch, the wheel, the trackpad,
  /// the ± buttons and their keys, the readout's drag, a typed percentage.
  /// The anchor is solved AFTER the landing, at the zoom the view keeps:
  /// rounding a view that was already anchored leaves the point under the
  /// fingers anchored for a zoom the view no longer has (🧪0.007px off its
  /// finger in the pin, a pinch at 142% — and it grows with the distance
  /// from the canvas origin).
  ///
  /// ⛔Nothing under `lib/` calls [CanvasViewport.zoomedAround] but this —
  /// `test/architecture/a_zoom_lands_through_one_law_test.dart`.
  CanvasViewport zoomedTo(
    CanvasViewport view, {
    required double nextZoom,
    required ViewportPoint anchor,
  }) => view.zoomedAround(nextZoom: landed(nextZoom), anchor: anchor);

  /// [view] as a locked view may show it (I-27): brought back to the lock
  /// around [anchor] when it stands past it — a view stored before the lock
  /// was set, or written by an owner — and [view] ITSELF otherwise, so a
  /// caller tells 「nothing was held」 by identity.
  ///
  /// ⚠️Asked with a hair of slack: a view that LANDED on the lock reads a
  /// rounding error past it after the trip through render units, and
  /// holding that again would hand back a new view for no change.
  CanvasViewport heldUnderCeiling(
    CanvasViewport view, {
    required ViewportPoint anchor,
  }) {
    final ceiling = ceilingPercent;
    if (ceiling == null || display(view.zoom) * 100 <= ceiling + _hair) {
      return view;
    }
    return zoomedTo(view, nextZoom: view.zoom, anchor: anchor);
  }

  static const double _hair = 1e-6;

  /// THE USER'S ZOOM STOPS (`AppInputSettings.zoomSnapPercents`), as the
  /// zooms the view can actually be on.
  ///
  /// The list is the user's own text: it is written in DISPLAY percent and
  /// it takes any digits — the settings field parses `33.333` and shows it
  /// as `33`. Its two readers ([steppedThroughStops], [snappedToStops]) each
  /// converted the unit for themselves, and one of them got it wrong once
  /// (audit 2026-09-15: snapped as a RENDER zoom, a 150% stop read 225% on a
  /// 150% monitor). Both read it HERE now, in its own unit, on the grid a
  /// zoom lands on.
  List<double> _stopsTheViewCanBeOn(List<double> stopPercents) => [
    for (final stop in stopPercents) CanvasViewport.onReadoutGrid(stop),
  ];

  /// The next of the user's stops past [renderZoom], [up] or down — null
  /// where the list ends, which is where a step stops (I-19).
  ///
  /// 🚨READ ON THE GRID. From 33.33% the next stop "up" in a list holding
  /// `33.333` was 33.333 — which lands on 33.33 again, so the + button did
  /// nothing at that rung for ever.
  double? steppedThroughStops(
    double renderZoom,
    List<double> stopPercents, {
    required bool up,
  }) {
    final next = AppInput.stepThroughList(
      display(renderZoom) * 100,
      _stopsTheViewCanBeOn(stopPercents),
      up: up,
    );
    // A stop past the lock is no stop: the list ends there (I-27-Q1: 「잠금
    // 보다 큰 칸에는 ±가 닿지 않는다」).
    final ceiling = ceilingPercent;
    if (next == null || (ceiling != null && next > ceiling + _hair)) {
      return null;
    }
    return render(next / 100);
  }

  /// [renderZoom] held on the nearest of the user's stops — the constrained
  /// pinch.
  double snappedToStops(double renderZoom, List<double> stopPercents) => render(
    AppInput.snapToList(
          display(renderZoom) * 100,
          _stopsTheViewCanBeOn(stopPercents),
        ) /
        100,
  );

  /// The identity view: artwork 1px = device 1px, whatever the monitor and
  /// the UI scale are.
  ///
  /// This is what "reset" means now. ⛔It is NOT `CanvasViewport()`: a bare
  /// 1.0 is one artwork pixel per LOGICAL pixel, which on a 1.5 display put
  /// the artwork at 150% and called it 100%.
  CanvasViewport get identityViewport => CanvasViewport(zoom: render(1));

  /// The view measured in DEVICE pixels — the form it is STORED in.
  ///
  /// 🎯**The whole transform is a uniform scale by [ratio].** Not just the
  /// zoom: [CanvasViewport.panX]/[CanvasViewport.panY] are viewport-space
  /// offsets, so they carry the same factor, while the rotation and the
  /// flips are angles and signs and carry none. Read the forward map and
  /// it falls out —
  ///
  ///     canvasToViewport(p) · ratio = p · (zoom · ratio) + (pan · ratio)
  ///
  /// — the device-space answer IS the logical one scaled, with no residue.
  ///
  /// 🚨Which is why a view kept in these units survives a ratio change by
  /// doing NOTHING. Convert out at the new ratio and every artwork pixel
  /// lands on the device pixel it was already on: no re-zoom, no anchor to
  /// choose, and nothing to get wrong while a panel is unmounted.
  ///
  /// ⛔The device zoom IS the percentage the user reads — [display] and
  /// [render] are the same conversion, and the readout stops converting.
  CanvasViewport toDevice(CanvasViewport view) => view.copyWith(
    zoom: view.zoom * ratio,
    panX: view.panX * ratio,
    panY: view.panY * ratio,
  );

  /// [device] mapped back into the LOGICAL units every painter and hit test
  /// works in — the inverse of [toDevice].
  CanvasViewport fromDevice(CanvasViewport device) => device.copyWith(
    zoom: device.zoom / ratio,
    panX: device.panX / ratio,
    panY: device.panY / ratio,
  );

  // ⛔There is no `rescaledFrom` here any more, and adding one back would be
  // a regression. It re-zoomed a stored view when the effective ratio moved,
  // around a chosen anchor, and it had three problems the unit does not:
  // it could only hold ONE point exactly, it needed a mounted panel to run,
  // and it needed each panel to remember the ratio it last framed against.
  // A view stored in device units survives a ratio change by doing nothing.

  @override
  bool operator ==(Object other) =>
      other is CanvasZoomScale &&
      other.ratio == ratio &&
      other.ceilingPercent == ceilingPercent;

  @override
  int get hashCode => Object.hash(ratio, ceilingPercent);

  @override
  String toString() => ceilingPercent == null
      ? 'CanvasZoomScale($ratio)'
      : 'CanvasZoomScale($ratio, locked at $ceilingPercent%)';
}

/// The lock on zooming in that is in force for the document view under it
/// (I-27) — null, or no such widget above, where nothing is locked.
///
/// ⛔ONE view places it: the drawing canvas (`MainCanvasBrushHost`), because
/// that is where 유저 said the lock holds — 「그리기 캔버스만」. The law it
/// feeds ([CanvasZoomScale]) is every document view's, so a second place
/// that set this would lock a view nobody asked to lock.
class CanvasZoomCeiling extends InheritedWidget {
  const CanvasZoomCeiling({
    super.key,
    required this.percent,
    required super.child,
  });

  final double? percent;

  static double? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CanvasZoomCeiling>()
      ?.percent;

  @override
  bool updateShouldNotify(CanvasZoomCeiling oldWidget) =>
      oldWidget.percent != percent;
}
