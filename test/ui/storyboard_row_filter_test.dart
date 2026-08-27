import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

/// R5 #9 — the legend's chips on the storyboard, judged FACET BY FACET.
///
/// The user's rule was "있는거면 다 달아서 통일" and "차이두지마": one
/// predicate, applied to whatever the row carries. A chip hides only rows
/// that have the field it reads — a track has `fxEnabled` and no mark, so
/// the fx chip filters it like a layer and the mark chip leaves it alone,
/// because a track has no mark rather than because it is a track.
void main() {
  Layer layer({
    LayerMark mark = LayerMark.none,
    LayerKind kind = LayerKind.animation,
    bool onTimesheet = true,
    bool isFillReference = false,
  }) => Layer(
    id: const LayerId('row'),
    name: 'A',
    frames: const [],
    timeline: const {},
    mark: mark,
    kind: kind,
    onTimesheet: onTimesheet,
    isFillReference: isFillReference,
  );

  group('a row that CARRIES the facet is judged by it', () {
    test('mark', () {
      final filter = TimelineRowFilter(markColors: {const LayerMark(process: LayerProcess.layout)});
      expect(
        filter.allows(layer(mark: const LayerMark(process: LayerProcess.layout)), fxEnabled: true),
        isTrue,
      );
      expect(
        filter.allows(layer(mark: const LayerMark(process: LayerProcess.conte)), fxEnabled: true),
        isFalse,
      );
    });

    test('fx — the one facet a TRACK also carries', () {
      final filter = TimelineRowFilter(fxOnly: true);
      expect(filter.allows(layer(), fxEnabled: true), isTrue);
      expect(filter.allows(layer(), fxEnabled: false), isFalse);
      // Same chip, same answer, on a row with nothing but fx.
      expect(filter.allowsFacets(fxEnabled: true), isTrue);
      expect(filter.allowsFacets(fxEnabled: false), isFalse);
    });
  });

  group('a row that LACKS the facet is left alone by that chip', () {
    test('the mark chip does not hide a track — a track has no mark, so '
        'failing it would empty the storyboard for every mark alike', () {
      final filter = TimelineRowFilter(markColors: {const LayerMark(process: LayerProcess.layout)});
      expect(filter.allowsFacets(fxEnabled: true), isTrue);
    });

    test('kind, sheet-only and fill-reference behave the same way', () {
      expect(
        TimelineRowFilter(
          kinds: {LayerKind.animation},
        ).allowsFacets(fxEnabled: true),
        isTrue,
      );
      expect(
        TimelineRowFilter(
          onTimesheetOnly: true,
        ).allowsFacets(fxEnabled: true),
        isTrue,
      );
      expect(
        TimelineRowFilter(
          fillReferenceOnly: true,
        ).allowsFacets(fxEnabled: true),
        isTrue,
      );
    });

    test('but a row that carries the facet and FAILS it still hides — the '
        'chip is not disabled, it is inapplicable', () {
      final filter = TimelineRowFilter(onTimesheetOnly: true);
      expect(filter.allowsFacets(fxEnabled: true, onTimesheet: false), isFalse);
      expect(filter.allowsFacets(fxEnabled: true, onTimesheet: true), isTrue);
    });
  });

  test('the facets AND together, and an inactive filter allows everything',
      () {
    final filter = TimelineRowFilter(
      markColors: {const LayerMark(process: LayerProcess.layout)},
      fxOnly: true,
    );
    expect(
      filter.allows(layer(mark: const LayerMark(process: LayerProcess.layout)), fxEnabled: false),
      isFalse,
      reason: 'the mark passes, the fx does not',
    );
    expect(
      filter.allows(layer(mark: const LayerMark(process: LayerProcess.layout)), fxEnabled: true),
      isTrue,
    );
    expect(TimelineRowFilter.none.isActive, isFalse);
  });

  test('`allows` is `allowsFacets` with every field present — one rule, not '
      'two implementations', () {
    final filter = TimelineRowFilter(
      markColors: {const LayerMark(process: LayerProcess.layout)},
      onTimesheetOnly: true,
    );
    final row = layer(mark: const LayerMark(process: LayerProcess.layout), onTimesheet: false);
    expect(
      filter.allows(row, fxEnabled: true),
      filter.allowsFacets(
        mark: row.mark,
        kind: row.kind,
        onTimesheet: row.onTimesheet,
        fxEnabled: true,
        isFillReference: row.isFillReference,
      ),
    );
  });
}
