import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★P8: PAINTERS TAKE THE ONE TRANSFORM, AND THE HOST SNAPS ONCE.
///
/// `viewport_canvas_transform.dart` has said the first half since it was
/// written — "the ONE way painters take canvas-space geometry to the
/// screen … Painters call this instead of hand-rolling translate/scale
/// pairs" — and the base panels hand-rolled anyway. The 2026-08-28 audit
/// found five sites and measured the consequence: not one of those four
/// files contained the word `snap`, so the pan-phase snap the helper
/// exists for never reached the sheets, and rotation and flip were
/// dropped in silence.
///
/// ⛔THE SNAP HAPPENS ONCE, AT THE HOST (유저 답 `host`). A painter that
/// snaps for itself and an ink window that snaps for itself land on the
/// same device grid from DIFFERENT starting values — `round(pan) +
/// zoom*left` versus `round(pan + zoom*left)` — and part company by up to
/// a whole device pixel at fractional pans, which reads as the ink
/// jumping off its box the moment the pen lifts. One value handed to both
/// cannot drift from itself, and that is the whole reason the answer was
/// `host` rather than "convert the painters".
///
/// ⛔THE DRAWING CANVAS IS OUT OF SCOPE ON PURPOSE. `contentOverride` is
/// also how the main canvas and the editor canvas area mount, and the
/// helper reserves the exact mapping for pointer math: "stored pan/gesture
/// state stays a free float". Snapping there would move the pen on the
/// surface where precision matters most. On a sheet the same shift is
/// half a device pixel — the snap's own stated budget — and it buys the
/// paper and the ink agreeing.
void main() {
  /// Hosts that feed a PAINTER and INK WINDOWS from one viewport: the ones
  /// with something to keep in agreement.
  ///
  /// ⛔The media viewer is deliberately absent. It has a single consumer,
  /// so its viewport has nothing to drift from, and its painter's own
  /// `applyViewportTransform` supplies the pan-phase snap. Listing it
  /// would turn this test into a headcount instead of a rule.
  const sheetHosts = <String>[
    'lib/src/ui/timesheet_tab_host.dart',
    'lib/src/ui/conte/conte_tab_host.dart',
    'lib/src/ui/envelope/cut_envelope_tab_host.dart',
  ];

  test('every sheet host snaps its viewport once, itself', () {
    for (final path in sheetHosts) {
      expect(
        File(path).readAsStringSync().contains('renderSnappedViewport'),
        isTrue,
        reason:
            '$path hands its viewport to a painter AND to ink windows; '
            'both must come from ONE snapped value or they drift a device '
            'pixel apart at fractional pans',
      );
    }
  });

  test('no sheet painter hand-rolls the viewport transform', () {
    // 🚨SCANNED, not asserted through behaviour: a hand-rolled
    // translate/scale pair draws correctly at whole-pixel pans and only
    // parts company from its siblings at fractional ones. Every test that
    // pans by an integer passes either way, which is how five of these
    // survived until someone diffed the files.
    final offenders = <String>[];
    const dirs = [
      'lib/src/ui/timesheet',
      'lib/src/ui/conte',
      'lib/src/ui/envelope',
      'lib/src/ui/media',
    ];
    for (final dir in dirs) {
      final root = Directory(dir);
      if (!root.existsSync()) {
        continue;
      }
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll(r'\', '/');
        final rel = path.substring(path.indexOf('lib/'));
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) {
            continue;
          }
          if (RegExp(
            r'canvas\.translate\([^)]*[Vv]iewport\.pan',
          ).hasMatch(line)) {
            offenders.add('$rel:${i + 1}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'call applyViewportTransform — it carries the snap, the '
          'rotation and the flip that a translate/scale pair drops',
    );
  });
}
