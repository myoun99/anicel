import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A PARAMETER BOTH GRIDS TAKE LIVES IN THE HOOKS.
///
/// The rail and the x-sheet each declared the same seventy-odd constructor
/// parameters — what the session answers to a grid — and the panel passed
/// them twice. Two lists that must agree are how the sheet came to lack the
/// link badge, the camera column's live opacity, the onion and blend
/// columns, the live twirl read: one per round, each found by the user
/// (F-26: 「몇번째인지 모를 통일화 미스」). And the panel's `layerEyeOnOf` —
/// "forwarded to the grids", said its doc — reached neither.
///
/// `TimelineGridHooks` is the one list. This scan says the two grids' own
/// constructors share nothing but the bundle and the four facts that are
/// genuinely a surface's own — its layer ORDER, its rail WINDOW, where its
/// FRAME AXIS stands, and its METRICS. A hook added to one grid by hand is
/// red here.
void main() {
  const gridPath = 'lib/src/ui/timeline/layer_timeline_grid.dart';
  const sheetPath = 'lib/src/ui/timeline/xsheet_timeline_grid.dart';
  const hooksPath = 'lib/src/ui/timeline/timeline_grid_hooks.dart';

  /// The four a surface keeps for itself, each for a stated reason.
  const perSurface = {
    // The rail's display order and the sheet's are different reversals.
    'layers',
    // Persisted per surface by the workspace.
    'railExtent',
    // Where the frame axis stands, kept per surface by the workspace so a
    // fold does not throw it away (F-143). NOT a hook: the two axes run in
    // different directions at different zooms, so one shared notifier
    // would be wrong for both — it is `railExtent`'s kind, not the bundle's.
    'frameAxisOffset',
    // The sheet's metrics are the timeline's turned on their side.
    'metrics',
  };

  /// The names in `const Widget({ ... })` — every `this.x` inside it.
  Set<String> ctorParams(String path, String className) {
    final text = File(path).readAsStringSync();
    final start = text.indexOf('  const $className({');
    expect(start, greaterThanOrEqualTo(0), reason: '$className has a ctor');
    final end = text.indexOf('  });', start);
    return RegExp(
      r'this\.([a-zA-Z]+)',
    ).allMatches(text.substring(start, end)).map((m) => m[1]!).toSet();
  }

  test('premise: the bundle is large and both grids take it', () {
    final hooks = ctorParams(hooksPath, 'TimelineGridHooks');
    expect(hooks.length, greaterThan(60), reason: 'the bundle is the list');
    expect(ctorParams(gridPath, 'LayerTimelineGrid'), contains('hooks'));
    expect(ctorParams(sheetPath, 'XSheetTimelineGrid'), contains('hooks'));
  });

  test('the grids share only the bundle and the four per-surface facts', () {
    final grid = ctorParams(gridPath, 'LayerTimelineGrid');
    final sheet = ctorParams(sheetPath, 'XSheetTimelineGrid');
    final shared = grid.intersection(sheet)..remove('hooks');
    expect(
      shared,
      perSurface,
      reason:
          'a parameter both grids take belongs in TimelineGridHooks — '
          'declaring it on each grid is the two-list drift this round closed',
    );
  });

  test('no bundled name is declared on a grid as well', () {
    final hooks = ctorParams(hooksPath, 'TimelineGridHooks');
    for (final (path, name) in [
      (gridPath, 'LayerTimelineGrid'),
      (sheetPath, 'XSheetTimelineGrid'),
    ]) {
      final own = ctorParams(path, name);
      expect(
        own.intersection(hooks),
        isEmpty,
        reason: '$name re-declares a hook the bundle already carries',
      );
    }
  });
}
