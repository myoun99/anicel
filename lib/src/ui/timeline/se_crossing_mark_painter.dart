import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show Axis;

import '../theme/app_theme.dart';
import 'axis_turn.dart';

/// How long the `~` an SE sound crossing a cut's edge wears runs ALONG the
/// flow — the one piece of SE chrome that must not scale with the zoom.
const double seCrossingMarkLength = 14;

/// How far its wave swings to either side of its centre line, across the
/// flow, and how thick it is drawn.
const double seCrossingMarkSwing = 3;
const double seCrossingMarkStroke = 2;

/// THE drawer of the `~` an SE sound crossing a cut's edge wears (UI-R7 #6):
/// the timeline's rows, the X-sheet's columns and the timesheet's SE columns
/// all draw it here — one wave, centred on [centre], running along [flow].
///
/// 🗣️F-358 (유저 2026-10-14): 「se블록이 컷을 넘을때 생기는 ~ 표시, 안보이고
/// 이상함. 앞부분에 빨간색으로 ~ 제대로 보이게 표시하고 … 뒤에도 넘어갈때 ~를
/// 빨간색으로 잘 보이게. 지금 ~가 있는거같긴한데 세로적으로 중앙도아니고 중앙
/// 살짝 위인것도 이상하고 … 중요한건 방향을 세로로 해야지 지금 가로로되있음.
/// 이는 x시트도 마찬가지」.
///
/// It is DRAWN, not printed. ↩️It was the face's `~` in the ink, which sits
/// where the face puts it — above the middle of its line — and lay across
/// a column. A wave is where its centre is and turns with the flow, the
/// reason the in-between mark is drawn too (`paintInbetweenMark`). Down a
/// column it turns the way vertical writing turns a `~`: a quarter turn
/// clockwise.
void paintSeCrossingMark(Canvas canvas, Offset centre, Axis flow) {
  const steps = 16;
  final wave = Path();
  for (var step = 0; step <= steps; step += 1) {
    final t = step / steps;
    final along = (t - 0.5) * seCrossingMarkLength;
    // The first hump stands up out of a row, as the glyph's does — and the
    // quarter turn puts a row's up on a column's right.
    final swing = math.sin(t * 2 * math.pi) * seCrossingMarkSwing;
    final point =
        centre +
        offsetAlong(
          flow,
          along: along,
          across: flow == Axis.horizontal ? -swing : swing,
        );
    if (step == 0) {
      wave.moveTo(point.dx, point.dy);
    } else {
      wave.lineTo(point.dx, point.dy);
    }
  }
  canvas.drawPath(
    wave,
    Paint()
      ..color = AppColors.danger
      ..style = PaintingStyle.stroke
      ..strokeWidth = seCrossingMarkStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}
