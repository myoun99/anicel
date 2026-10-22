import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/session/drags/lane_range_move_drag.dart';
import 'package:anicel/src/ui/session/lane_edit_subject.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart'
    show effectLaneKeyFrames;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectLaneId;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show LaneKeyValues;
import 'package:anicel/src/ui/timeline/scale_lane_form.dart' show TwoScales;
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// The lane-key range MOVE drag — nothing named it (the audit's
/// untested-file pass, 2026-09-05).
///
/// 🚨F-374: ONE drag moves every home the span holds lanes of — the row's
/// own transform, its reference fx, its effect chain, its name tag — as
/// ONE rigid group: a home whose landing is blocked holds the whole move,
/// and a home with no key in the span rides along. ↩️It moved ONE family,
/// picked at begin by whether an effect lane was in the span, so a span
/// over a transform lane and an fx lane moved the fx's keys alone.
///
/// 🚨A BLOCKED landing HOLDS: the last valid preview and outline stay
/// where they were, rather than snapping back mid-drag.
void main() {
  TransformTrack trackWithKeysAt(List<int> frames) => TransformTrack(
    keyframes: {
      for (final frame in frames)
        frame: TransformPose(center: CanvasPoint(x: frame.toDouble(), y: 0)),
    },
  );

  final blurLane = effectLaneId(const EffectId('e1'), 'blurX');

  List<LayerEffect> blurWithKeysAt(List<int> frames) => [
    LayerEffect(
      id: const EffectId('e1'),
      kind: EffectKind.blur,
      parameters: {
        'blurX': EffectParameter(
          track: PropertyTrack<double>(
            keys: {
              for (final frame in frames)
                frame: PropertyKey<double>(frame.toDouble()),
            },
          ),
        ),
      },
    ),
  ];

  ({
    LaneRangeMoveDrag? drag,
    ValueNotifier<TimelineDragPreview?> preview,
    ValueNotifier<TimelineLaneSelection?> outline,
    List<LaneEdit> commits,
    List<String> descriptions,
  })
  open({
    TransformTrack? track,
    List<LayerEffect> effects = const [],
    List<String> laneIds = const ['position'],
    bool previewRefuses = false,
    LaneValuesWrite? write,
  }) {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    final outline = ValueNotifier<TimelineLaneSelection?>(null);
    addTearDown(preview.dispose);
    addTearDown(outline.dispose);
    final commits = <LaneEdit>[];
    final descriptions = <String>[];
    final before = TimelineLaneSelection(
      layerId: const LayerId('l'),
      laneId: laneIds.first,
      startIndex: 2,
      endIndexExclusive: 5,
      laneIds: laneIds,
    );
    outline.value = before;
    return (
      drag: LaneRangeMoveDrag.begin(
        selection: before,
        subject: LaneEditSubject(
          transformTrack: track ?? trackWithKeysAt([0, 3, 4, 9]),
          effects: effects,
          commit: (next, why) {
            commits.add(next);
            descriptions.add(why);
          },
          // What a camera key put out of its cut shows: nothing.
          preview: (next) => previewRefuses
              ? null
              : LaneEditPreview.track(
                  trackId: const TrackId('t'),
                  trackEffects: next.effects ?? const [],
                ),
        ),
        laneVerbTargets: (spanLaneIds, {effects = const []}) => spanLaneIds,
        preview: preview,
        selectionChannel: outline,
        write: write ?? (_, _) => null,
      ),
      preview: preview,
      outline: outline,
      commits: commits,
      descriptions: descriptions,
    );
  }

  test('⛔a selection covering NO key on any spanned lane gives no object — '
      'nothing to move, no drag', () {
    expect(open(track: trackWithKeysAt([0, 9])).drag, isNull);
  });

  test('a selection that does cover a key begins', () {
    expect(open().drag, isNotNull);
  });

  test('a shift moves the keys inside the range and leaves the rest', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(
      transformLaneKeyFrames(
        session.commits.single.transform.own!,
        'position',
      ),
      {0, 5, 6, 9},
      reason: 'the keys at 3 and 4 moved; 0 and 9 were outside the range',
    );
  });

  test('🎯a span over a transform lane and an fx lane moves BOTH — one step '
      '(F-374)', () {
    final session = open(
      effects: blurWithKeysAt([3, 9]),
      laneIds: ['position', blurLane],
    );

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    final landed = session.commits.single;
    expect(transformLaneKeyFrames(landed.transform.own!, 'position'), {
      0,
      5,
      6,
      9,
    });
    expect(effectLaneKeyFrames(landed.effects!, blurLane), {5, 9});
  });

  test('🚨a home whose landing is blocked holds the WHOLE move — the homes '
      'are one rigid group', () {
    // The fx key at 3 lands on the one at 5, which the range does not
    // cover; the transform's keys could land.
    final session = open(
      effects: blurWithKeysAt([3, 5]),
      laneIds: ['position', blurLane],
    );

    session.drag!.update(frameDelta: 2);
    expect(session.preview.value, isNull);
    expect(session.outline.value?.startIndex, 2, reason: 'it held');

    session.drag!.commit();
    expect(session.commits, isEmpty);
  });

  test('a home with no key in the span rides along, left as it was', () {
    final session = open(
      effects: blurWithKeysAt([0, 9]),
      laneIds: ['position', blurLane],
    );

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(session.commits.single.effects, isNull);
    expect(session.commits.single.transform.own, isNotNull);
  });

  test('a span whose keys are all in ONE home of several begins and moves '
      'that home alone', () {
    final session = open(
      track: trackWithKeysAt([0, 9]),
      effects: blurWithKeysAt([3]),
      laneIds: ['position', blurLane],
    );

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(session.commits.single.transform.own, isNull);
    expect(effectLaneKeyFrames(session.commits.single.effects!, blurLane), {
      5,
    });
  });

  test('🚨a landing the subject will not take HOLDS as a blocked one does — '
      'a camera key put out of its cut', () {
    final session = open(previewRefuses: true);

    session.drag!.update(frameDelta: 2);
    expect(session.outline.value?.startIndex, 2);

    session.drag!.commit();
    expect(session.commits, isEmpty);
  });

  test('🚨the OUTLINE rides the shift, so the selection lands on what it '
      'moved', () {
    final session = open();

    session.drag!.update(frameDelta: 2);

    expect(session.outline.value?.startIndex, 4);
    expect(session.outline.value?.endIndexExclusive, 7);
  });

  test('⛔the outline never rides BELOW zero, even when the KEYS can still '
      'move — the span would name frames that do not exist', () {
    // Keys at 3 and 4 slide to 0 and 1, which is legal; the outline's own
    // start would be -1, which is not.
    final session = open(track: trackWithKeysAt([3, 4, 9]));

    session.drag!.update(frameDelta: -3);

    expect(session.outline.value?.startIndex, 2, reason: 'it did not ride');
  });

  test('🚨a BLOCKED landing HOLDS the last valid preview and outline — it '
      'does not snap back mid-drag', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    final held = session.outline.value;

    // Landing on top of the key at 9 is refused all-or-nothing.
    session.drag!.update(frameDelta: 6);

    expect(session.outline.value, held);
  });

  test('a delta of ZERO puts the outline back and previews nothing', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.update(frameDelta: 0);

    expect(session.preview.value, isNull);
    expect(session.outline.value?.startIndex, 2);
  });

  test('🚨a drag that never produced a valid shift writes NOTHING and puts '
      'the outline back where it started', () {
    final session = open();

    session.drag!.update(frameDelta: 0);
    session.drag!.commit();

    expect(session.commits, isEmpty);
    expect(session.outline.value?.startIndex, 2);
  });

  test('commit lands ONE step and leaves the outline on the landed span', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.commit();

    expect(session.commits, hasLength(1));
    expect(
      session.descriptions,
      ['Move lane keys'],
      reason: 'the subject is every lane edit\'s now (F-195) — the undo line '
          'names the move, which only the drag knows',
    );
    expect(session.outline.value?.startIndex, 4);
    expect(session.preview.value, isNull);
  });

  group('🎯I-3 ② — a header graph\'s key carries the keys\' values', () {
    // What a key carried up the graph hands the drag: the key at 3's
    // Position, as its value editor reads it.
    const carried = (
      inputs: {
        'position': {3: '30, 0'},
      },
      scaleLinked: false,
    );

    // The value editor's own write ([LaneVerbs.laneValuesWritten]).
    LaneEdit? written(LaneEditSubject subject, LaneKeyValues values) {
      final MapEntry(key: frame, value: input) =
          values.inputs['position']!.entries.single;
      return LaneEdit(
        transform: (
          own: transformTrackWithLaneValueEdited(
            subject.transformTrack,
            laneId: 'position',
            frameIndex: frame,
            input: input,
            scaleForm: const TwoScales(),
            scaleLinked: values.scaleLinked,
          ),
          reference: null,
        ),
      );
    }

    test('a step that carries values writes them, then shifts the row it '
        'wrote — ONE step', () {
      final session = open(write: written);

      session.drag!.update(frameDelta: 2, values: carried);
      session.drag!.commit();

      final own = session.commits.single.transform.own!;
      expect(transformLaneKeyFrames(own, 'position'), {0, 5, 6, 9});
      expect(own.position.keys[5]!.value.x, 30, reason: 'it rode the shift');
    });

    test('carried straight up, no frame moved, the values are shown and '
        'land', () {
      final session = open(write: written);

      session.drag!.update(frameDelta: 0, values: carried);
      expect(session.preview.value, isNotNull);
      expect(session.outline.value?.startIndex, 2);
      session.drag!.commit();

      final own = session.commits.single.transform.own!;
      expect(transformLaneKeyFrames(own, 'position'), {0, 3, 4, 9});
      expect(own.position.keys[3]!.value.x, 30);
    });
  });

  test('cancel writes nothing and puts the outline back', () {
    final session = open();

    session.drag!.update(frameDelta: 2);
    session.drag!.cancel();

    expect(session.commits, isEmpty);
    expect(session.outline.value?.startIndex, 2);
    expect(session.preview.value, isNull);
  });
}
