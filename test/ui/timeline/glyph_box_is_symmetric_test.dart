import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// **F-48 ② — THE CELL GLYPH SITS IN A SYMMETRIC BOX.**
///
/// 유저 2026-08-28: 「점·프레임 이름이 칸 중앙보다 미묘하게 아래」.
///
/// The centring is exact — `rect.center - glyph.size / 2`, snapped to
/// physical pixels. The drift is in the BOX. With no height set, a glyph's
/// box is the font's ascent + descent, and a Japanese face carries a tall
/// ascent for full-width forms while Latin digits ink only above the
/// baseline. Centre that lopsided box and the ink lands low. The report
/// arrived right after the app took BIZ UDPGothic — the same event seen
/// from the other side.
///
/// 🚨WHAT THIS TEST CANNOT DO, stated so nobody trusts it for more than it
/// is worth: it cannot see the drift. `flutter test` never loads the
/// bundled font; it draws the test face, whose metrics are symmetric, so
/// the before/after difference measures **zero** here. The same wall the
/// colour-label anti-aliasing probe hit.
///
/// What it CAN pin is the request: the style asks for a box of exactly the
/// font size, with the leading split evenly. That is the property the fix
/// consists of, and deleting either half turns this red.
void main() {
  TimelineRowCellsPainter painterAt({double cellWidth = 20}) =>
      TimelineRowCellsPainter(
        layer: Layer(
          id: const LayerId('a-1'),
          name: 'A',
          kind: LayerKind.animation,
          frames: const [],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: cellWidth,
          frameEndIndexExclusive: 8,
        ),
        crossAxisExtent: 26,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.drawingStart,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        baseTextStyle: const TextStyle(
          fontSize: 12,
          color: Color(0xFF000000),
        ),
      );

  test('the glyph box is the font size, with the leading split evenly', () {
    final painter = painterAt();
    final style = painter.glyphStyleFor(painter.cellModelAt(0));

    expect(
      style.height,
      1.0,
      reason:
          'a box taller than the type is the font\'s asymmetric '
          'ascent+descent, and centring it puts the ink low',
    );
    expect(
      style.leadingDistribution,
      TextLeadingDistribution.even,
      reason:
          'height alone is not enough — proportional leading hands the '
          'extra space out in the font\'s own lopsided ratio',
    );
  });

  test('and a squeezed cell keeps both the type and the box — the word '
      'narrows instead (B)', () {
    final painter = painterAt(cellWidth: 6);
    final style = painter.glyphStyleFor(painter.cellModelAt(0));
    expect(
      style.fontSize,
      12,
      reason: '유저 2026-09-24 (B): one type size at every zoom. ↩️A cell '
          'this narrow used to shrink it (#15)',
    );
    expect(style.height, 1.0, reason: 'the box rule holds at every width');
  });
}
