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

  /// 🚨결정 8 (유저 확정 2026-08-22): 「①**창 폭의 절반의 3/4** (=37.5%)」.
  ///
  /// ⚠️This group used to assert `3/7 · rest`, where `rest` had the OTHER
  /// dock taken out. It was a faithful reading of 「중간의 3/4」 — and it was
  /// the bug: 「한쪽 띠 크기를 바꿀 때 **반대쪽도 바뀐다**」. A ceiling that
  /// names the other side makes the two sides one quantity.
  group('the ceiling is a share of the WINDOW', () {
    test('one dock may take 37.5% of it', () {
      expect(
        EditorWorkspace.sideDockCeiling(
          availableWidth: 1400,
          gaps: 0,
          minCentreWidth: 120,
        ),
        closeTo(525, 0.5),
      );
    });

    test('★the answer does not move when the other dock does — which is the '
        'whole complaint', () {
      // The signature carries no other-dock argument at all, so the only
      // way to state this is that the same window gives the same number to
      // both sides. That IS the fix: two rails at 37.5% leave 25% for the
      // centre, so neither has to ask about the other.
      const available = 1400.0;
      final ceiling = EditorWorkspace.sideDockCeiling(
        availableWidth: available,
        gaps: 16,
        minCentreWidth: 120,
      );
      expect(ceiling * 2 + 16, lessThan(available));
      expect(
        available - ceiling * 2 - 16,
        greaterThanOrEqualTo(120),
        reason: 'the pair always fits with the centre above its floor, so '
            'the proportional squeeze that scaled BOTH sides is gone',
      );
    });

    test('and on a NARROW window it halves the room rather than naming a '
        'dock', () {
      // Below roughly 550 the 37.5% pair would crowd the centre out. The
      // second term binds — and it still mentions no dock, so the two sides
      // stay independent where the coupling used to show itself.
      const available = 400.0;
      final ceiling = EditorWorkspace.sideDockCeiling(
        availableWidth: available,
        gaps: 16,
        minCentreWidth: 120,
      );
      expect(ceiling, closeTo((400 - 16 - 120) / 2, 1e-9));
      expect(ceiling, lessThan(available * 0.375));
    });

    test('a window too small for a centre yields a ceiling of zero, not '
        'a negative one', () {
      expect(
        EditorWorkspace.sideDockCeiling(
          availableWidth: 100,
          gaps: 40,
          minCentreWidth: 200,
        ),
        0,
      );
    });
  });
}
