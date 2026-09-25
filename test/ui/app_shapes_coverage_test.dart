import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// THE APP HAS ONE CORNER, AND THIS IS WHAT MAKES THAT TRUE.
///
/// `app_shapes_test.dart` checks that AppShapes produces the right paths. It
/// would pass identically if AppShapes were imported by zero files — which is
/// how a shape described as "the whole app" shipped applied at twelve call
/// sites while 94 hand-rolled circular corners and 71 stadium-shaped
/// IconButtons went on being what the user actually saw.
///
/// So this one is a CONTRACT over the source: any new circular corner has to
/// argue for itself in [_allowed] with a reason, or CI names the file and the
/// line. The allowlist is the point — it is small, and every entry is a place
/// where the app's corner genuinely cannot go.
void main() {
  test('no new circular corners escape the app shape', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      if (_allowedFiles.contains(path)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (!_offending.hasMatch(line)) {
          continue;
        }
        if (_allowed.any(line.contains)) {
          continue;
        }
        offenders.add('$path:${i + 1}  ${line.trim()}');
      }
    }
    // 🏆THE RATCHET GRADUATED. It carried a number for as long as there were
    // corners left — 84 when the app's shape reached the theme, then 74, 51,
    // 32 — and the file's own instruction was 「when it reaches zero, replace
    // this with `expect(offenders, isEmpty)` and delete the number」. It is
    // zero. ⛔The number is gone with it: a bound nobody has to lower is a
    // bound somebody will raise.
    expect(
      offenders,
      isEmpty,
      reason:
          'A circular corner was added. Use AppShapes.control(size) for a '
          'control, AppShapes.container(radius) for a surface, and '
          'SuperellipseClip to CLIP to it — a shape that is only painted '
          'leaves square corners behind, which is exactly how the floating '
          'region looked square while its silhouette was right. If a site '
          'genuinely cannot take the app shape, add it to _allowed with the '
          'reason.\n${offenders.join('\n')}',
    );
  });

  test('the forbidden lookalikes stay out', () {
    // ContinuousRectangleBorder is a cubic approximation at roughly half the
    // radius scale that never reaches the flat run — a lozenge, not a
    // squircle. ClipRSuperellipse hit-tests its outerRect only, so its four
    // corners would eat the canvas pointers underneath a floating panel.
    //
    // ⚠️THE BAN IS ON THE WIDGET, AND ONLY BECAUSE OF HIT TESTING. Two
    // names that merely start the same way are not it and are allowed:
    //
    //  * `pushClipRSuperellipse` — the PaintingContext op. It paints; it
    //    does not hit-test anything.
    //  * `ClipRSuperellipseLayer` — the layer that op pushes.
    //
    // `SuperellipseClip` is built on both, and it hit-tests with
    // `RSuperellipse.contains`, which is exact — so a pointer in a cut
    // corner misses, which is the entire thing this ban protects. It
    // exists because the alternative, `ClipPath`, allocates a fresh
    // `Path` per paint (`clipPath.shift(offset)`) and so misses the
    // engine's clip-mask cache on every frame, at every clip site.
    //
    // Stripping the two allowed names FIRST keeps the guard's teeth: a
    // bare `ClipRSuperellipse(...)` or a `RenderClipRSuperellipse` still
    // lands in `found`.
    final found = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('///')) {
          continue;
        }
        final probe = line
            .replaceAll('pushClipRSuperellipse', '')
            .replaceAll('ClipRSuperellipseLayer', '');
        if (probe.contains('ContinuousRectangleBorder') ||
            probe.contains('ClipRSuperellipse')) {
          found.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(found, isEmpty);
  });
}

final RegExp _offending = RegExp(
  r'BorderRadius\.circular|RoundedRectangleBorder|ClipRRect',
);

/// Line-level exceptions, each with its reason.
const _allowed = <String>[
  // A 4px-thick thumb's corner is its own radius; the app's ratio would be
  // sub-pixel and the superellipse would be invisible.
  'BorderRadius.circular(2)',
  // ⚠️THE SAME EXEMPTION, spelled as the arithmetic that produces it:
  // `AppScrollbar` writes `_thickness / 2` where `_thickness` is 4, so this
  // IS `circular(2)` — it was only ever flagged because the literal is not
  // in the source.
  'BorderRadius.circular(_thickness / 2)',
  // Not a corner at all: `StillRaster` READS the rounded clip a descendant
  // pushed, to notice it changing. A `ClipRRectLayer` BUILT anywhere would
  // still be caught — only the switch case that reads one is let through.
  'case ClipRRectLayer(',
];

/// Whole files the rule cannot reach.
const _allowedFiles = <String>{
  // Material requires an InputBorder for a field, and InputBorder is not an
  // OutlinedBorder — the app's ShapeBorder cannot be handed to it.
  'lib/src/ui/theme/app_theme.dart',
};
