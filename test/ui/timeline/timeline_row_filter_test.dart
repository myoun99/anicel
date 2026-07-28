import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
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
      expect(filter.allows(_layer('a'), fxEnabled: true), isTrue);
    });

    test('mark set passes only matching marks', () {
      const filter = TimelineRowFilter(markColors: {LayerMark.red});
      expect(
        filter.allows(_layer('a', mark: LayerMark.red), fxEnabled: true),
        isTrue,
      );
      expect(
        filter.allows(_layer('b', mark: LayerMark.blue), fxEnabled: true),
        isFalse,
      );
      expect(filter.allows(_layer('c'), fxEnabled: true), isFalse);
    });

    test('facets combine with AND', () {
      const filter = TimelineRowFilter(
        markColors: {LayerMark.red},
        onTimesheetOnly: true,
      );
      // red + sheet-on passes.
      expect(
        filter.allows(
          _layer('a', mark: LayerMark.red, onTimesheet: true),
          fxEnabled: true,
        ),
        isTrue,
      );
      // red but sheet-off fails.
      expect(
        filter.allows(_layer('b', mark: LayerMark.red), fxEnabled: true),
        isFalse,
      );
    });

    test('fx-only reads the session fxEnabled parameter', () {
      const filter = TimelineRowFilter(fxOnly: true);
      expect(filter.allows(_layer('a'), fxEnabled: true), isTrue);
      expect(filter.allows(_layer('a'), fxEnabled: false), isFalse);
    });

    test('toggledMark flips membership', () {
      const filter = TimelineRowFilter();
      final withRed = filter.toggledMark(LayerMark.red);
      expect(withRed.markColors, {LayerMark.red});
      expect(withRed.toggledMark(LayerMark.red).markColors, isEmpty);
    });

    test('kind set passes only matching kinds and ANDs with the rest '
        '(R4 #8)', () {
      const filter = TimelineRowFilter(kinds: {LayerKind.se});
      expect(filter.isActive, isTrue);
      expect(
        filter.allows(_layer('s', kind: LayerKind.se), fxEnabled: true),
        isTrue,
      );
      expect(filter.allows(_layer('a'), fxEnabled: true), isFalse);

      const combined = TimelineRowFilter(
        kinds: {LayerKind.animation},
        markColors: {LayerMark.red},
      );
      expect(
        combined.allows(_layer('a', mark: LayerMark.red), fxEnabled: true),
        isTrue,
      );
      expect(
        combined.allows(
          _layer('s', kind: LayerKind.se, mark: LayerMark.red),
          fxEnabled: true,
        ),
        isFalse,
      );
    });

    test('toggledKind flips membership', () {
      const filter = TimelineRowFilter();
      final withSe = filter.toggledKind(LayerKind.se);
      expect(withSe.kinds, {LayerKind.se});
      expect(withSe.toggledKind(LayerKind.se).kinds, isEmpty);
    });
  });

  group('buildTimelineDisplayRows rowFilter', () {
    List<Layer> layers() => [
      _layer('a', mark: LayerMark.red),
      _layer('b', mark: LayerMark.blue),
      _layer('c', onTimesheet: true),
    ];

    test('an active filter drops rows that fail it', () {
      final rows = buildTimelineDisplayRows(
        layers: layers(),
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        rowFilter: const TimelineRowFilter(markColors: {LayerMark.red}),
      );
      expect(rows.map((r) => r.layer.id.value), ['a']);
    });

    test('the active layer is exempt from the filter', () {
      final rows = buildTimelineDisplayRows(
        layers: layers(),
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        rowFilter: const TimelineRowFilter(markColors: {LayerMark.red}),
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
        'active attach row excepted (UI-R20 #9)', () {
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

      final activeExempt = buildTimelineDisplayRows(
        layers: attachRows,
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        collapsedAttachBaseIds: {const LayerId('base')},
        activeLayerId: const LayerId('up1'),
      );
      expect(activeExempt.map((r) => r.layer.id.value), [
        'base',
        'up1',
        'other',
      ]);
    });
  });
}
