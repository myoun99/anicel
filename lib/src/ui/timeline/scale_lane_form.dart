import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/transform_pose.dart' show uniformScale;
import '../../models/transform_values.dart' show scaleCarriedBy;
import '../text/trimmed_decimal.dart';

/// WHAT A ROW'S SCALE LANE HOLDS — and so how it is printed, typed and
/// scrubbed. The three are one law, kept in one place: what the lane
/// prints is the text its own editor hands back, and a scrub writes that
/// same text.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「**가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)**」, of the option whose own terms were 「카메라는 줌 하나 그대로」.
/// So there are two forms, and a row is one or the other by what it is.
sealed class ScaleLaneForm {
  const ScaleLaneForm();

  /// [scale] as the lane's value column prints it.
  String label(CanvasPoint scale);

  /// What [input], typed where the lane showed [current], makes the scale —
  /// null when it is not a scale this form holds.
  ///
  /// [linked] is the chain. 🗣️F-256-Q2 (유저 2026-10-06): 「**연동 스위치(AE
  /// 의 사슬)** — 켜면 한 칸을 바꿀 때 다른 칸도 같은 비율로」 · 「이걸
  /// 트랜스폼등 fx에도 적용하고싶음」 — the ONE switch the transform tool's
  /// 「배율 연동」 is (`transform-fx-scale-x-y-Q1`, 유저 2026-10-07: 「Scale
  /// 행에 사슬 버튼 — 변형 도구의 「배율 연동」과 한 스위치」). One zoom has
  /// nothing to link.
  CanvasPoint? typed(
    String input, {
    required CanvasPoint current,
    required bool linked,
  });

  /// [label] with [dragDelta] scrubbed into it, in the text form [typed]
  /// reads — null when [label] is not this form's.
  String? scrubbed(String label, Offset dragDelta);

  /// Whether this form has two numbers a chain can link — the lane wears
  /// the chain when it does (`PropertyLaneRow.linkable`).
  bool get links;
}

/// The form [row]'s Scale takes: a camera's one zoom, every other row's
/// two scales — asked by the lane that prints it and by the verb that
/// writes it, so the two cannot come to read one row two ways.
ScaleLaneForm scaleLaneFormOf(Layer row) =>
    row.kind == LayerKind.camera ? const OneZoom() : const TwoScales();

/// Display percent per pixel of a scrub — the rate the lane has always
/// scrubbed at.
const double _percentPerPixel = 0.5;

double? _percent(String text) =>
    double.tryParse(text.replaceAll('%', '').trim());

/// A CAMERA's scale: ONE zoom, above zero — `150%`.
final class OneZoom extends ScaleLaneForm {
  const OneZoom();

  @override
  String label(CanvasPoint scale) => '${formatTrimmedDecimal(scale.x * 100)}%';

  @override
  CanvasPoint? typed(
    String input, {
    required CanvasPoint current,
    required bool linked,
  }) {
    final percent = _percent(input);
    return percent == null || !percent.isFinite || percent <= 0
        ? null
        : uniformScale(percent / 100);
  }

  @override
  String? scrubbed(String label, Offset dragDelta) {
    final percent = _percent(label);
    return percent == null
        ? null
        : '${formatTrimmedDecimal(percent + dragDelta.dx * _percentPerPixel)}%';
  }

  @override
  bool get links => false;
}

/// A LAYER's scale: across and down — `150, 80%`, After Effects' own print.
/// Either may be a minus (that axis flipped) or zero (the layer shown as
/// nothing, `TransformPose.scaleX`).
final class TwoScales extends ScaleLaneForm {
  const TwoScales();

  @override
  String label(CanvasPoint scale) =>
      '${formatTrimmedDecimal(scale.x * 100)}, '
      '${formatTrimmedDecimal(scale.y * 100)}%';

  /// ONE number is both axes (`150` — the layer at one and a half its
  /// size). TWO are across and down; [linked], the one the editor's two
  /// boxes left as it was shown is carried by the step of the other — the
  /// transform tool's own arithmetic ([scaleCarriedBy]). Both typed, or
  /// neither, there is no one step to follow: they are what was typed.
  ///
  /// ⚠️「As it was shown」 is asked of the PRINT, not of the number: the lane
  /// prints 133.3 for a scale of 1.3333…, and the box that was not touched
  /// hands 133.3 back. The carry is still taken from the scale itself.
  @override
  CanvasPoint? typed(
    String input, {
    required CanvasPoint current,
    required bool linked,
  }) {
    final percents = [for (final piece in input.split(',')) _percent(piece)];
    if (percents.length > 2 ||
        percents.any((percent) => percent == null || !percent.isFinite)) {
      return null;
    }
    if (percents.length == 1) {
      return uniformScale(percents.single! / 100);
    }
    final across = percents[0]!;
    final down = percents[1]!;
    final asTyped = CanvasPoint(x: across / 100, y: down / 100);
    final acrossMoved = !_printsAs(across, current.x);
    final downMoved = !_printsAs(down, current.y);
    if (!linked || acrossMoved == downMoved) {
      return asTyped;
    }
    return acrossMoved
        ? CanvasPoint(
            x: asTyped.x,
            y: scaleCarriedBy(current.y, from: current.x, to: asTyped.x),
          )
        : CanvasPoint(
            x: scaleCarriedBy(current.x, from: current.y, to: asTyped.y),
            y: asTyped.y,
          );
  }

  static bool _printsAs(double percent, double scale) =>
      formatTrimmedDecimal(percent) == formatTrimmedDecimal(scale * 100);

  /// ONE drag scrubs ONE number, as After Effects' two numbers are each
  /// scrubbed on their own: across drives the scale across, down the scale
  /// down, and the drag is the one it runs along more. The other number is
  /// handed back as it was shown — so, linked, [typed] carries it, and a
  /// hand that drifts off its line does not move both.
  @override
  String? scrubbed(String label, Offset dragDelta) {
    final pieces = label.split(',');
    if (pieces.length != 2) {
      return null;
    }
    final across = _percent(pieces[0]);
    final down = _percent(pieces[1]);
    if (across == null || down == null) {
      return null;
    }
    final alongAcross = dragDelta.dx.abs() >= dragDelta.dy.abs();
    final dx = alongAcross ? dragDelta.dx : 0.0;
    final dy = alongAcross ? 0.0 : dragDelta.dy;
    return '${formatTrimmedDecimal(across + dx * _percentPerPixel)}, '
        '${formatTrimmedDecimal(down + dy * _percentPerPixel)}%';
  }

  @override
  bool get links => true;
}
