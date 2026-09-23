import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';
import '../helpers/dart_sources.dart';

/// 🚨THE LANE AND THE THUMB ARE NUMBERS WITH NAMES.
///
/// CLAUDE.md: 「레인 16px, **썸 최소 32px**」 — and the thumb minimum is
/// load-bearing past the scrollbar itself: `editor_workspace` sizes the
/// x-sheet's floor around it, and the timeline and storyboard panels reason
/// from it. A layout computing against a number the scrollbar no longer
/// uses is a layout that is wrong and still compiles.
///
/// The thumb minimum was written out three times before it had a name
/// (`layer_rail_window`, `timeline_horizontal_scrollbar_rail`,
/// `timeline_vertical_scrollbar_rail`). This is the ratchet that stops a
/// fourth: every `minThumbExtent` in the app reads the shared constant, and
/// the values themselves are pinned so a change has to be deliberate.
void main() {
  test('the values are the ones CLAUDE.md names', () {
    expect(AppScrollbarLane.wide, 16, reason: '레인 16px');
    expect(AppScrollbarThumb.minimum, 32, reason: '썸 최소 32px');
  });

  test('the three lane steps are ordered, and distinct — a step that '
      'collapsed into its neighbour would be a vocabulary with a word '
      'that means nothing', () {
    expect(AppScrollbarLane.wide, greaterThan(AppScrollbarLane.medium));
    expect(AppScrollbarLane.medium, greaterThan(AppScrollbarLane.narrow));
  });

  test('🚨every minThumbExtent in lib/ reads the shared constant — three '
      'private copies of this number is how it drifts', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'minThumbExtent:\s*([^,\n)]+)',
      ).allMatches(source)) {
        final value = match.group(1)!.trim();
        if (!value.contains('AppScrollbarThumb') &&
            !value.contains('minThumbExtent')) {
          offenders.add('${file.path}: $value');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a thumb minimum written as a literal is a fourth copy of a '
          'law the workspace floor also reasons from',
    );
  });

  test('🚨the scrollbar lane widths are not written as literals either — a '
      'reserved column is a decision with a name', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.path.endsWith('app_scrollbar_lane.dart')) {
        continue; // Where the numbers live.
      }
      final source = file.readAsStringSync();
      for (final match in RegExp(
        '(?:ScrollbarLaneExtent|ScrollbarWidth|ScrollbarRailHeight)'
        r'\s*=\s*([^;\n]+)',
      ).allMatches(source)) {
        final value = match.group(1)!.trim();
        // A NUMBER is the drift; a name — the shared constant, or one of
        // the timeline's own aliases for it — is the law travelling.
        if (RegExp(r'^-?\d').hasMatch(value)) {
          offenders.add('${file.path}: $value');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
