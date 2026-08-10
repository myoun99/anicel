import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
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
        if (_allowed.any((allowed) => line.contains(allowed))) {
          continue;
        }
        offenders.add('$path:${i + 1}  ${line.trim()}');
      }
    }
    // A RATCHET, not a wall. There were 84 of these when the app's corner
    // reached the theme, spread over dialogs, the brush panels and the
    // export rows — converting them all in one change would have been a
    // bigger diff than the round that created the corner. So the number
    // may only ever go DOWN: a new circular corner fails immediately, and
    // every round that converts a few lowers the bound.
    //
    // When it reaches zero, replace this with `expect(offenders, isEmpty)`
    // and delete the number.
    expect(
      offenders.length,
      lessThanOrEqualTo(_knownOffenders),
      reason:
          'A circular corner was added. Use AppShapes.control(size) for a '
          'control, AppShapes.container(radius) for a surface, and '
          'AppShapes.clipper(shape) to CLIP to it — a shape that is only '
          'painted leaves square corners behind, which is exactly how the '
          'floating region looked square while its silhouette was right. If '
          'a site genuinely cannot take the app shape, add it to _allowed '
          'with the reason.\n${offenders.join('\n')}',
    );
    // And the bound has to stay honest: if a round converts some, it lowers
    // the number in the same commit rather than banking the slack.
    expect(
      offenders.length,
      greaterThanOrEqualTo(_knownOffenders),
      reason:
          'Corners were converted — lower _knownOffenders to '
          '${offenders.length} so the ratchet keeps its grip.',
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
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
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

/// The debt the app's corner arrived to. Only ever goes down.
/// 84 at R1e. **81** since R4 #8 folded the anchored popup's three
/// hand-rolled `Material(borderRadius: circular(6))` surfaces into one
/// `AppShapes.container(AppShapes.windowRadius)` inside the shell itself.
/// **77** since the V row's transform teardown took the cut-fade envelope span
/// with it — one corner fewer to convert, banked here rather than left as slack.
/// **75** since the command-pill round retired `SplitIconButton` — its
/// hand-typed corners went with it, and the pill that replaced it wears
/// `AppShapes.control` on both its border and its splash.
///
/// ⚠️Those two rounds ran in parallel and each lowered this to 77 for its own
/// reason, so the merge had to RE-COUNT rather than take either number: two
/// independent subtractions from the same total are not the same subtraction.
const int _knownOffenders = 75;

final RegExp _offending = RegExp(
  r'BorderRadius\.circular|RoundedRectangleBorder|ClipRRect',
);

/// Line-level exceptions, each with its reason.
const _allowed = <String>[
  // A 4px-thick thumb's corner is its own radius; the app's ratio would be
  // sub-pixel and the superellipse would be invisible.
  'BorderRadius.circular(2)',
];

/// Whole files the rule cannot reach.
const _allowedFiles = <String>{
  // Material requires an InputBorder for a field, and InputBorder is not an
  // OutlinedBorder — the app's ShapeBorder cannot be handed to it.
  'lib/src/ui/theme/app_theme.dart',
};
