import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// R5 — AE's group Reset, in the user's words: **키를 삭제하진 않고 값만
/// 리셋**, scoped to the playhead or, with a lane range live, to the keys it
/// covers.
void main() {
  final identity = TransformPose(
    center: CanvasPoint(x: 640, y: 360),
    zoom: 1,
    rotationDegrees: 0,
  );
  final centre = CanvasPoint(x: 640, y: 360);

  group('transformTrackWithGroupReset', () {
    test('an UNKEYED lane is left alone — it already sits at its default, '
        'and keying it would author animation nobody asked for', () {
      final reset = transformTrackWithGroupReset(
        TransformTrack.empty(),
        frameIndexes: const [3],
        identity: identity,
        defaultAnchorPoint: centre,
      );
      expect(reset, isNull, reason: 'nothing to do is not a commit');
    });

    test('a KEYED lane takes the default at the playhead, keeping every key '
        'it had — including the one being reset', () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<double>()
            .withKey(0, 2.0, interpolation: PropertyKeyInterpolation.hold)
            .withKey(8, 3.0),
      );
      final reset = transformTrackWithGroupReset(
        track,
        frameIndexes: const [0],
        identity: identity,
        defaultAnchorPoint: centre,
      )!;
      expect(reset.scale.keys.keys.toList(), [0, 8]);
      expect(reset.scale.keyAt(0)!.value, 1.0);
      expect(
        reset.scale.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'a reset changes the value, not how it is reached',
      );
      expect(reset.scale.keyAt(8)!.value, 3.0, reason: 'out of scope');
    });

    test('the playhead scope KEYS a frame that had none — the only way the '
        'value THERE can be the default on an animated lane', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(0, 45),
      );
      final reset = transformTrackWithGroupReset(
        track,
        frameIndexes: const [5],
        identity: identity,
        defaultAnchorPoint: centre,
      )!;
      expect(reset.rotation.keys.keys.toList(), [0, 5]);
      expect(reset.rotation.keyAt(5)!.value, 0);
    });

    test('a SELECTION resets the keys it covers and invents none', () {
      final track = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(0, 45).withKey(4, 90),
      );
      final reset = transformTrackWithGroupReset(
        track,
        frameIndexes: const [0, 1, 2, 3, 4],
        identity: identity,
        defaultAnchorPoint: centre,
        keyedFramesOnly: true,
      )!;
      expect(
        reset.rotation.keys.keys.toList(),
        [0, 4],
        reason: 'frames 1-3 had no key and must not grow one',
      );
      expect(reset.rotation.keyAt(0)!.value, 0);
      expect(reset.rotation.keyAt(4)!.value, 0);
    });

    test('every member of the group answers, not just the one that moved', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          2,
          CanvasPoint(x: 10, y: 20),
        ),
        opacity: PropertyTrack<double>().withKey(2, 0.25),
        anchorPoint: PropertyTrack<CanvasPoint>().withKey(
          2,
          CanvasPoint(x: 1, y: 2),
        ),
      );
      final reset = transformTrackWithGroupReset(
        track,
        frameIndexes: const [2],
        identity: identity,
        defaultAnchorPoint: centre,
      )!;
      expect(reset.position.keyAt(2)!.value, identity.center);
      expect(reset.opacity.keyAt(2)!.value, 1);
      expect(reset.anchorPoint.keyAt(2)!.value, centre);
    });
  });

  group('effectsWithGroupReset', () {
    const effectId = EffectId('blur-1');
    LayerEffect blur({Map<String, EffectParameter> parameters = const {}}) =>
        LayerEffect(
          id: effectId,
          kind: EffectKind.blur,
          parameters: parameters,
        );

    test('an UNKEYED parameter resets its STATIC slot — no key is authored, '
        'because an effect has a real static value to put back', () {
      final spec = effectParametersOf(EffectKind.blur).first;
      final effects = [
        blur(parameters: {spec.id: EffectParameter(value: 12)}),
      ];
      final reset = effectsWithGroupReset(
        effects,
        laneId: effectGroupLaneId(effectId),
        frameIndexes: const [4],
      )!;
      final parameter = reset.single.parameterOf(spec.id);
      expect(parameter.value, spec.defaultValue);
      expect(parameter.track.isEmpty, isTrue);
    });

    test('a KEYED parameter takes the spec default at the scope frames', () {
      final spec = effectParametersOf(EffectKind.blur).first;
      final effects = [
        blur(
          parameters: {
            spec.id: EffectParameter(
              value: spec.defaultValue,
              track: PropertyTrack<double>().withKey(0, 30).withKey(6, 40),
            ),
          },
        ),
      ];
      final reset = effectsWithGroupReset(
        effects,
        laneId: effectGroupLaneId(effectId),
        frameIndexes: const [0],
      )!;
      final track = reset.single.parameterOf(spec.id).track;
      expect(track.keys.keys.toList(), [0, 6]);
      expect(track.keyAt(0)!.value, spec.defaultValue);
      expect(track.keyAt(6)!.value, 40);
    });

    test('a MEMBER lane id is refused — reset is the GROUP header\'s verb', () {
      expect(
        effectsWithGroupReset(
          [blur()],
          laneId: effectLaneId(effectId, 'radius'),
          frameIndexes: const [0],
        ),
        isNull,
      );
    });
  });

  testWidgets('the header button resets the group at the playhead, in ONE '
      'undo, and the key survives', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layerId = session.activeLayerId!;
    final toggle = find.byKey(
      ValueKey<String>('timeline-lane-toggle-$layerId'),
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Animate rotation off its default at the playhead.
    session.selectFrameIndex(0);
    session.updateLayerTransformTrack(
      layerId,
      session.activeLayer!.transformTrack.copyWith(
        rotation: PropertyTrack<double>().withKey(0, 45),
      ),
      description: 'seed',
    );
    await tester.pumpAndSettle();

    final reset = find.byKey(
      ValueKey<String>('timeline-lane-group-reset-$layerId-transform-group'),
    );
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();

    PropertyTrack<double> rotationOf() => session.layers
        .firstWhere((layer) => layer.id == layerId)
        .transformTrack
        .rotation;
    expect(rotationOf().keyAt(0)!.value, 0, reason: 'reset to the default');
    expect(rotationOf().keys, isNotEmpty, reason: 'the KEY survives');

    session.undo();
    expect(
      rotationOf().keyAt(0)!.value,
      45,
      reason: 'one undo step, not one per member',
    );
  });
}
