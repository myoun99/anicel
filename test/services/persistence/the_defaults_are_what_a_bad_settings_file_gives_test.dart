import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_lead_edge_plan.dart';
import 'package:anicel/src/models/cut_move_plan.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

/// Two laws the audit pulled out of copies that no test named.
void main() {
  group('a settings file that cannot be read must not stop the app', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('anicel-settings');
    });

    tearDown(() => directory.delete(recursive: true));

    String pathFor(String name) => '${directory.path}/$name';

    Map<String, dynamic>? asIs(Map<String, dynamic> json) => json;

    test('a round trip returns what was written, under its version', () async {
      final path = pathFor('a.json');
      await saveVersionedSettings(
        filePath: path,
        version: 3,
        json: {'lane': 'audio'},
      );

      expect(
        await loadVersionedSettings(filePath: path, version: 3, fromJson: asIs),
        {'version': 3, 'lane': 'audio'},
      );
    });

    test('the save CREATES the directory — a first run has none', () async {
      final path = pathFor('deep/and/deeper/b.json');
      await saveVersionedSettings(filePath: path, version: 1, json: const {});
      expect(File(path).existsSync(), isTrue);
    });

    test('a MISSING file is null', () async {
      expect(
        await loadVersionedSettings(
          filePath: pathFor('nothing.json'),
          version: 1,
          fromJson: asIs,
        ),
        isNull,
      );
    });

    test('🚨CORRUPT bytes are null, not a throw — the same situation as '
        'missing, on purpose', () async {
      final path = pathFor('torn.json');
      File(path).writeAsStringSync('{"lane": ');

      expect(
        await loadVersionedSettings(filePath: path, version: 1, fromJson: asIs),
        isNull,
      );
    });

    test('a file holding a JSON LIST is null too — the cast throws inside '
        'the same catch', () async {
      final path = pathFor('list.json');
      File(path).writeAsStringSync('[1, 2, 3]');

      expect(
        await loadVersionedSettings(filePath: path, version: 1, fromJson: asIs),
        isNull,
      );
    });

    test('a NEWER version is null — this build does not know it', () async {
      final path = pathFor('future.json');
      File(path).writeAsStringSync(jsonEncode({'version': 9, 'lane': 'x'}));

      expect(
        await loadVersionedSettings(filePath: path, version: 2, fromJson: asIs),
        isNull,
      );
    });

    test('an OLDER version still loads — fromJson is what migrates', () async {
      final path = pathFor('old.json');
      File(path).writeAsStringSync(jsonEncode({'version': 1, 'lane': 'x'}));

      expect(
        await loadVersionedSettings(filePath: path, version: 5, fromJson: asIs),
        isNotNull,
      );
    });

    test('a fromJson that THROWS is null as well — a decoder that cannot '
        'make sense of the document is the same as a torn one', () async {
      final path = pathFor('bad-shape.json');
      await saveVersionedSettings(filePath: path, version: 1, json: const {});

      expect(
        await loadVersionedSettings<String>(
          filePath: path,
          version: 1,
          fromJson: (_) => throw StateError('nope'),
        ),
        isNull,
      );
    });

    test('the SYNC reader answers identically, for the callers that cannot '
        'await (the export dialog, the launcher list)', () async {
      final missing = pathFor('none.json');
      final future = pathFor('future.json');
      final torn = pathFor('torn.json');
      final good = pathFor('good.json');
      File(future).writeAsStringSync(jsonEncode({'version': 9}));
      File(torn).writeAsStringSync('{');
      await saveVersionedSettings(
        filePath: good,
        version: 2,
        json: {'lane': 'audio'},
      );

      for (final path in [missing, future, torn]) {
        expect(
          loadVersionedSettingsSync(filePath: path, version: 2, fromJson: asIs),
          isNull,
          reason: path,
        );
      }
      expect(
        loadVersionedSettingsSync(filePath: good, version: 2, fromJson: asIs),
        {'version': 2, 'lane': 'audio'},
      );
    });
  });

  group('a cut lead-edge drag is the frame axis, stated in cuts', () {
    List<CutMoveSlot> slots(List<(String, int, int)> rows) => [
      for (final (id, gap, duration) in rows)
        (id: CutId(id), leadingGapFrames: gap, duration: duration),
    ];

    test('🚨a GLUED predecessor rides the boundary, and the emptiness ends '
        'up at the HEAD of the film', () {
      // The documented rule, and the surprising half: two cuts touching,
      // drag the second one's front edge in, and the FIRST cut moves with
      // it rather than a hole opening between them.
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 0, 12)]),
        targetIndex: 1,
        frameDelta: 3,
      );

      expect(plan.durations, {const CutId('b'): 9});
      expect(
        plan.gaps,
        {const CutId('a'): 3},
        reason:
            'a stayed glued and translated wholesale; the head absorbed '
            'the difference, and b keeps no gap of its own',
      );
    });

    test('a SEPARATED predecessor holds its ground and its own gap absorbs '
        'the move', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 5, 12)]),
        targetIndex: 1,
        frameDelta: 3,
      );

      expect(plan.durations, {const CutId('b'): 9});
      expect(plan.gaps, {const CutId('b'): 8});
    });

    test('the END holds still — that is what makes everything after it hold '
        'still too, by arithmetic rather than by a rule', () {
      final before = slots([('a', 0, 12), ('b', 5, 12)]);
      final plan = planCutLeadEdge(
        slots: before,
        targetIndex: 1,
        frameDelta: 3,
      );

      const startBefore = 12 + 5;
      final startAfter = plan.gaps[const CutId('b')]! + 12;
      expect(
        startAfter + plan.durations[const CutId('b')]!,
        startBefore + 12,
        reason: 'same back boundary, which is the whole point',
      );
    });

    test('dragging the front edge OUT grows the cut into the gap ahead of '
        'it', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 5, 12)]),
        targetIndex: 1,
        frameDelta: -3,
      );

      expect(plan.durations, {const CutId('b'): 15});
      expect(plan.gaps, {const CutId('b'): 2});
    });

    test('growing stops at the head of the axis — there is no frame -1', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 5, 12)]),
        targetIndex: 1,
        frameDelta: -400,
      );

      expect(plan.durations, {const CutId('b'): 17});
      expect(plan.gaps, {const CutId('b'): 0});
    });

    test('the dragged cut is ALWAYS in durations, even when the clamp left '
        'it unchanged — a missing key would read as a change', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12)]),
        targetIndex: 0,
        frameDelta: 400,
      );

      expect(plan.durations.keys, [const CutId('a')]);
      expect(plan.durations[const CutId('a')], 1, reason: 'the minimum');
    });

    test('minDuration is the floor the drag stops at', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12)]),
        targetIndex: 0,
        frameDelta: 400,
        minDuration: 4,
      );

      expect(plan.durations[const CutId('a')], 4);
    });

    test('the gaps map is SPARSE — a cut whose gap did not move stays out '
        'of it, so a drag does not read as re-timing the track', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 5, 12), ('c', 5, 12)]),
        targetIndex: 1,
        frameDelta: 2,
      );

      expect(plan.gaps.keys, [const CutId('b')]);
      expect(plan.gaps[const CutId('b')], 7);
    });

    test('a zero drag plans nothing but the target duration', () {
      final plan = planCutLeadEdge(
        slots: slots([('a', 0, 12), ('b', 0, 12)]),
        targetIndex: 1,
        frameDelta: 0,
      );

      expect(plan.gaps, isEmpty);
      expect(plan.durations, {const CutId('b'): 12});
      expect(plan.isEmpty, isFalse, reason: 'the target duration is always in');
    });

    test('an EMPTY plan is empty on both maps', () {
      expect(const CutLeadEdgePlan(durations: {}, gaps: {}).isEmpty, isTrue);
    });
  });
}
