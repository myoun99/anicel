part of '../interactive_brush_edit_canvas_view.dart';

/// PRESSURE AND THE STAMP — a pointer's pressure normalised for the
/// device and applied to the dab's dynamics, and the masked stamp the
/// brush paints with — as their own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state`.
class _BrushEditPressure {
  _BrushEditPressure(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  List<BrushDab> withPressureDynamics(List<BrushDab> dabs) {
    final settings =
        _state._activeStrokeInputSettings ?? _state.widget.inputSettings;
    if (!settings.hasPressureDynamics) {
      return dabs;
    }
    return <BrushDab>[
      for (final dab in dabs)
        applyBrushPressureDynamics(
          dab,
          sizeCurve: settings.sizePressureCurve,
          opacityCurve: settings.opacityPressureCurve,
          flowCurve: settings.flowPressureCurve,
          hardnessCurve: settings.hardnessPressureCurve,
        ),
    ];
  }

  /// Normalizes a pointer's pressure into 0..1.
  ///
  /// Only stylus devices report meaningful pressure. A mouse claims a 0..1
  /// pressure range on some platforms while always reporting 0.0 — trusting
  /// it made pressure-sized strokes invisible — and touch pressure is
  /// unreliable across devices, so both paint at full pressure.
  ///
  /// Wintab sidecar (PEN-2): while the user has picked the Wintab tablet
  /// service and the driver stream is LIVE, the driver's pressure wins for
  /// EVERY kind — that is the point of the switch: a pen the OS pipeline
  /// misreports (touch, or mouse with Ink unchecked) paints with real
  /// pressure anyway. Stale/absent stream falls through unchanged.
  double normalizedPressure(PointerEvent event) {
    // The response curve (PEN-3) shapes REAL pressure from either source
    // — the full-pressure fallbacks stay 1.0 through any gamma.
    final wintab = PenSidecars.freshContactPressure();
    if (wintab != null) {
      return AppInput.applyPressureCurve(wintab);
    }
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return 1.0;
    }
    final range = event.pressureMax - event.pressureMin;
    if (!range.isFinite || range <= 0.0) {
      return 1.0;
    }
    return AppInput.applyPressureCurve(
      ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0),
    );
  }

  /// [rgba] with the live selection applied, or [rgba] itself when there
  /// is no selection (no copy, no scan).
  Uint8List _maskedStampRgba({
    required Uint8List rgba,
    required int left,
    required int top,
    required int width,
    required int height,
    double opacity = 1.0,
  }) {
    final region = _state.widget.selectionRegion;
    if (region == null && opacity >= 1.0) {
      return rgba;
    }
    final masked = Uint8List.fromList(rgba);
    // TP1: the fill has an opacity now, and this preview does NOT go
    // through the pre-blend kernel (see the caller) — so the multiply the
    // commit will do has to be done here too, or a 50% fill previews at
    // 100% and lands at 50%. The commit's own expression is
    // `(stampA / 255) * dabOpacity`; scaling the alpha byte is that, in the
    // one place this path has to say it.
    if (opacity < 1.0) {
      for (var offset = 3; offset < masked.length; offset += 4) {
        masked[offset] = (masked[offset] * opacity).round().clamp(0, 255);
      }
    }
    if (region == null) {
      return masked;
    }
    // The same rule the pre-blend kernel and the commit's clip run — a
    // fill only reaches a different function, never a different rule.
    applySelectionMaskToStrokeAlpha(
      pixels: masked,
      mask: region.maskFor(left: left, top: top, width: width, height: height),
      pixelCount: width * height,
    );
    return masked;
  }
}
