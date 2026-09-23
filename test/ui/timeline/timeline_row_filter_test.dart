import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

Layer _layer(
  String id, {
  LayerKind kind = LayerKind.animation,
  LayerMark mark = LayerMark.none,
  bool onTimesheet = false,
  bool isFillReference = false,
}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    mark: mark,
    onTimesheet: onTimesheet,
    isFillReference: isFillReference,
    frames: const [],
    timeline: const {},
  );
}

void main() {
  group('TimelineRowFilter.allows (AND)', () {
    test('empty filter is inactive and passes everything', () {
      const filter = TimelineRowFilter.none;
      expect(filter.isActive, isFalse);
      expect(filter.allowsLayerRow(_layer('a'), standing: false, fxEnabled: true), isTrue);
    });

    test('mark set passes only matching marks', () {
      final filter = TimelineRowFilter(markColors: {const LayerMark(process: LayerProcess.layout)});
      expect(
        filter.allowsLayerRow(_layer('a', mark: const LayerMark(process: LayerProcess.layout)), standing: false, fxEnabled: true),
        isTrue,
      );
      expect(
        filter.allowsLayerRow(_layer('b', mark: const LayerMark(process: LayerProcess.conte)), standing: false, fxEnabled: true),
        isFalse,
      );
      expect(filter.allowsLayerRow(_layer('c'), standing: false, fxEnabled: true), isFalse);
    });

    test('facets combine with AND', () {
      final filter = TimelineRowFilter(
        markColors: {const LayerMark(process: LayerProcess.layout)},
        onTimesheetOnly: true,
      );
      // red + sheet-on passes.
      expect(
        filter.allowsLayerRow(
          _layer('a', mark: const LayerMark(process: LayerProcess.layout), onTimesheet: true),
          standing: false,
          fxEnabled: true,
        ),
        isTrue,
      );
      // red but sheet-off fails.
      expect(
        filter.allowsLayerRow(_layer('b', mark: const LayerMark(process: LayerProcess.layout)), standing: false, fxEnabled: true),
        isFalse,
      );
    });

    test('fx-only reads the session fxEnabled parameter', () {
      const filter = TimelineRowFilter(fxOnly: true);
      expect(filter.allowsLayerRow(_layer('a'), standing: false, fxEnabled: true), isTrue);
      expect(filter.allowsLayerRow(_layer('a'), standing: false, fxEnabled: false), isFalse);
    });

    test('toggledMark flips membership', () {
      const filter = TimelineRowFilter.none;
      final withRed = filter.toggledMark(const LayerMark(process: LayerProcess.layout));
      expect(withRed.markColors, {const LayerMark(process: LayerProcess.layout)});
      expect(withRed.toggledMark(const LayerMark(process: LayerProcess.layout)).markColors, isEmpty);
    });

    test('kind set passes only matching kinds and ANDs with the rest '
        '(R4 #8)', () {
      const filter = TimelineRowFilter(kinds: {LayerKind.se});
      expect(filter.isActive, isTrue);
      expect(
        filter.allowsLayerRow(_layer('s', kind: LayerKind.se), standing: false, fxEnabled: true),
        isTrue,
      );
      expect(filter.allowsLayerRow(_layer('a'), standing: false, fxEnabled: true), isFalse);

      final combined = TimelineRowFilter(
        kinds: {LayerKind.animation},
        markColors: {const LayerMark(process: LayerProcess.layout)},
      );
      expect(
        combined.allowsLayerRow(_layer('a', mark: const LayerMark(process: LayerProcess.layout)), standing: false, fxEnabled: true),
        isTrue,
      );
      expect(
        combined.allowsLayerRow(
          _layer('s', kind: LayerKind.se, mark: const LayerMark(process: LayerProcess.layout)),
          standing: false,
          fxEnabled: true,
        ),
        isFalse,
      );
    });

    test('toggledKind flips membership', () {
      const filter = TimelineRowFilter.none;
      final withSe = filter.toggledKind(LayerKind.se);
      expect(withSe.kinds, {LayerKind.se});
      expect(withSe.toggledKind(LayerKind.se).kinds, isEmpty);
    });
  });

  group('TimelineRowFilter.allowsRow — the standing row is exempt', () {
    final filter = TimelineRowFilter(
      markColors: {const LayerMark(process: LayerProcess.layout)},
    );
    final failing = _layer('b', mark: const LayerMark(process: LayerProcess.conte));

    test('a failing row hides, the standing one shows, an inactive filter '
        'shows both', () {
      expect(
        filter.allowsLayerRow(failing, standing: false, fxEnabled: true),
        isFalse,
      );
      expect(
        filter.allowsLayerRow(failing, standing: true, fxEnabled: true),
        isTrue,
      );
      expect(
        TimelineRowFilter.none.allowsLayerRow(
          failing,
          standing: false,
          fxEnabled: false,
        ),
        isTrue,
      );
    });

    test('a row with no facets but fx is judged on fx alone, standing '
        'exempt', () {
      const fx = TimelineRowFilter(fxOnly: true);
      expect(fx.allowsRow(standing: false, fxEnabled: false), isFalse);
      expect(fx.allowsRow(standing: true, fxEnabled: false), isTrue);
      expect(filter.allowsRow(standing: false, fxEnabled: false), isTrue);
    });
  });

  group('buildTimelineDisplayRows rowFilter', () {
    List<Layer> layers() => [
      _layer('a', mark: const LayerMark(process: LayerProcess.layout)),
      _layer('b', mark: const LayerMark(process: LayerProcess.conte)),
      _layer('c', onTimesheet: true),
    ];

    test('an active filter drops rows that fail it', () {
      final rows = buildTimelineDisplayRows(
        layers: layers(),
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        rowFilter: TimelineRowFilter(markColors: {const LayerMark(process: LayerProcess.layout)}),
      );
      expect(rows.map((r) => r.layer.id.value), ['a']);
    });

    test('the active layer is exempt from the filter', () {
      final rows = buildTimelineDisplayRows(
        layers: layers(),
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        rowFilter: TimelineRowFilter(markColors: {const LayerMark(process: LayerProcess.layout)}),
        activeLayerId: const LayerId('c'),
      );
      // c fails the red filter but is active → kept, alongside the matching a.
      expect(rows.map((r) => r.layer.id.value), ['a', 'c']);
    });

    test('an inactive filter changes nothing', () {
      final rows = buildTimelineDisplayRows(
        layers: layers(),
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
      );
      expect(rows.map((r) => r.layer.id.value), ['a', 'b', 'c']);
    });

    test('collapsedAttachBaseIds folds a base\'s attach rows out — the '
        'active one too (UI-R20 #9, ↩️F-169)', () {
      final attachRows = [
        _layer('base'),
        Layer(
          id: const LayerId('up1'),
          name: '+1',
          frames: const [],
          timeline: const {},
          attachedToLayerId: const LayerId('base'),
        ),
        _layer('other'),
      ];
      final folded = buildTimelineDisplayRows(
        layers: attachRows,
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        collapsedAttachBaseIds: {const LayerId('base')},
      );
      expect(folded.map((r) => r.layer.id.value), ['base', 'other']);

      // ↩️The active attach row used to be exempt from its group's fold.
      // F-169 (유저 2026-09-24) took that out: it is what put a handed-off
      // row on the screen inside a shut group. Nothing stands inside a fold
      // now — the standing law hands off to the base or opens the group.
      final activeInside = buildTimelineDisplayRows(
        layers: attachRows,
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        collapsedAttachBaseIds: {const LayerId('base')},
        activeLayerId: const LayerId('up1'),
      );
      expect(activeInside.map((r) => r.layer.id.value), ['base', 'other']);
    });
  });
}
