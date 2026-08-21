import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/layout/device_grid.dart';

/// D37 (유저, 2026-08-17): 「사이드띠 패널 가로가 고정px → 화면 비율로
/// (중간 크기의 3/4까지 확대 가능), 타임라인 세로 = 화면 절반」.
///
/// 🚨What is proportional is the OPENING and the CEILING — a dock the user
/// has dragged keeps its pixels. Making the width track the window would
/// move it under them on every resize, which no editor does; the complaint
/// was that one number was wrong at both ends of the monitor range and that
/// the drag stopped too early.
void main() {
  const grid = DeviceGrid(2);

  group('the opening size is a fraction of the window', () {
    test('a wide window opens the rail wider than the old fixed number', () {
      // 0.18 × 2560 = 460.8 — the number the fraction exists to produce.
      expect(
        EditorWorkspace.sideDockWidthFor(2560, grid),
        greaterThan(EditorWorkspace.sideDockWidth),
      );
      expect(EditorWorkspace.sideDockWidthFor(2560, grid), closeTo(460.5, 1));
    });

    test('⛔a narrow window does NOT open it narrower than usable', () {
      // 🚨The floor is load-bearing and was found as a red test: 0.18 of an
      // 800-wide window is 144, at which the timesheet's own pill folds its
      // buttons away. A fraction says how a dock should GROW; it is not a
      // licence to open one too narrow to use.
      expect(
        EditorWorkspace.sideDockWidthFor(800, grid),
        EditorWorkspace.sideDockWidth,
      );
      expect(
        EditorWorkspace.bottomDockHeightFallbackFor(400, grid),
        EditorWorkspace.bottomPanelHeight,
      );
    });

    test('the timeline opens at half a tall window', () {
      expect(
        EditorWorkspace.bottomDockHeightFallbackFor(1400, grid),
        closeTo(700, 0.5),
      );
    });

    test('★the opening lands on the device grid', () {
      // A fraction of a window is a fraction of a pixel almost always, and
      // R11's whole chain rests on the boundaries between docks being
      // integral device positions. 0.18 × 1366 = 245.88 — which is under
      // the floor, so reach for a width where the fraction actually wins.
      for (final ratio in <double>[1.25, 1.5, 1.875, 3]) {
        final scale = DeviceGrid(ratio);
        for (final width in <double>[1600, 1712, 2133, 2560]) {
          final opening = EditorWorkspace.sideDockWidthFor(width, scale);
          final device = opening * ratio;
          expect(
            (device - device.roundToDouble()).abs(),
            lessThan(1e-6),
            reason: 'width $width at ratio $ratio landed at $device device px',
          );
        }
      }
    });
  });

  group('the ceiling is ¾ of the centre', () {
    test('one dock may take 3/7 of what is left', () {
      // d ≤ ¾·(rest − d) solves to d ≤ 3/7 · rest.
      expect(
        EditorWorkspace.sideDockCeiling(
          availableWidth: 1400,
          gaps: 0,
          otherDockWidth: 0,
        ),
        closeTo(600, 0.5),
      );
    });

    test('★and the pair honours the same promise the single one does', () {
      // With the other dock already taking 300, the centre this one must
      // leave is measured against what remains — not against the window.
      const available = 1400.0;
      const other = 300.0;
      final ceiling = EditorWorkspace.sideDockCeiling(
        availableWidth: available,
        gaps: 0,
        otherDockWidth: other,
      );
      final centre = available - other - ceiling;
      expect(
        ceiling,
        closeTo(centre * 0.75, 1e-9),
        reason: 'at the ceiling the dock is exactly ¾ of the centre',
      );
    });

    test('a window too small for a centre yields a ceiling of zero, not '
        'a negative one', () {
      expect(
        EditorWorkspace.sideDockCeiling(
          availableWidth: 100,
          gaps: 40,
          otherDockWidth: 200,
        ),
        0,
      );
    });
  });
}
