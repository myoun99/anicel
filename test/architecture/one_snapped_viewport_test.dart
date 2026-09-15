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
/// The snap now has ONE site: `SheetCanvasPanel`, the paper shell the
/// four sheet panels mount. Round 8 found the recipe — and this decision
/// with it — typed out three times, so the rule reads the same way it
/// always did and lands in one place: a sheet host takes its viewport
/// through the shell, and the shell snaps it once.
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

  const shell = 'lib/src/ui/brush/sheet_canvas_panel.dart';

  test('every sheet host snaps its viewport once, through the one shell', () {
    for (final path in sheetHosts) {
      expect(
        File(path).readAsStringSync().contains('SheetCanvasPanel'),
        isTrue,
        reason:
            '$path hands its viewport to a painter AND to ink windows; '
            'both must come from ONE snapped value or they drift a device '
            'pixel apart at fractional pans',
      );
    }
  });

  test('the shell snaps ONCE — one call, and the hosts have none', () {
    // ⛔ONCE is the whole decision, so it is counted, not looked for: a
    // second call in the shell would be the same two-starting-values bug
    // the P8 answer removed, and a call left behind in a host would snap
    // an already-snapped viewport.
    expect(
      'renderSnappedViewport('
          .allMatches(File(shell).readAsStringSync())
          .length,
      1,
      reason:
          '$shell is the one place a sheet viewport is snapped — the paper '
          'below and the ink windows above both read what it returns',
    );
    for (final path in sheetHosts) {
      expect(
        File(path).readAsStringSync().contains('renderSnappedViewport'),
        isFalse,
        reason:
            '$path snaps for itself again — a value snapped twice is a '
            'value with two starting points',
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

  test('🚨★★★F-32 · F-95: whatever follows a scroll offset moves through '
      'ScrollFollower', () {
    // 🚨SCANNED, and for the same reason as the case above: a raw
    // `Transform.translate(-offset)` looks right at whole-pixel offsets
    // and only parts company from its siblings at fractional ones. Three
    // of these survived until someone measured at ratio 1.5.
    //
    // The halves that move with a scroll offset must take the SAME
    // correction. `DeviceGridScrollBody` cancels the offset's
    // sub-device-pixel fraction; a translate outside it keeps that
    // fraction, and the ruler comes off the cells it numbers:
    //
    //   x-sheet             rail 360.0   vs cells 359.667
    //   horizontal timeline ruler 453.5  vs cells 453.667
    //   storyboard          ruler 453.5  vs cells 453.667
    //
    // ⛔A behavioural test per grid cannot close this — it passes the day
    // a FOURTH surface is written without the correction. This is the
    // ratchet ([[no-copy-to-share]]: 「소스 스캔 래칫으로 닫는다」).
    //
    // ↩️F-95 (유저 2026-09-12) retired the NEIGHBOURHOOD rule this check
    // used to apply — a scroll-offset translate was fine if a
    // `DeviceGridScrollBody(` stood within 24 lines above it (and before
    // that, a file-wide 「does it mention DeviceGridScrollBody」 check had
    // PASSED while the bug was reinstated, because the other two covered
    // for the one taken away). All three translates did sit inside the
    // body, and they still came 600px off their cells: the offset they
    // moved by was a notifier fed from the controller's listeners, and a
    // viewport that grows past its content's end corrects its position
    // during layout without calling one. `ScrollFollower` reads the
    // position when it paints and wears the body's correction, so a
    // scroll-offset translate written anywhere else is wrong whatever
    // surrounds it.
    final offenders = <String>[];
    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final rel = path.substring(path.indexOf('lib/'));
      // The file that DOES the following and the correcting is where a
      // position-driven translate belongs — the one place allowed to write
      // one.
      if (rel.endsWith('layout/device_grid_scroll_controller.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('Transform.translate(')) {
          continue;
        }
        // Is this one driven by a scroll offset? Its `Offset(...)` is on
        // this line or the next few.
        final head = lines.sublist(i, (i + 4).clamp(0, lines.length)).join(' ');
        if (RegExp(
          r'Offset\(\s*-?offset\b|Offset\(\s*0,\s*-offset\b',
        ).hasMatch(head)) {
          offenders.add('$rel:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'mount it through ScrollFollower — it reads the scroll position '
          'when it paints and takes DeviceGridScrollBody\'s correction; an '
          'offset carried in a notifier misses the corrections a viewport '
          'makes during layout (F-95), and a raw translate keeps the '
          'fraction the cells cancelled (F-32)',
    );
  });
}
