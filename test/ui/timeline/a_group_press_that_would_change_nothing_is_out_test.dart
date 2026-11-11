// 🗣️F-583 (유저 2026-11-11): 「fx 래스터라이즈. 변형fx 지금 아무런 변경 없는데
// 래스터라이즈가 활성화되있어서 누르면 작동함. 값이 안바뀌었으면 비활성화로.
// 동일하게 리셋버튼도 값 안바뀌었으면 동일하게 통일해서 비활성화」 — a group
// header's RESET, and the Transform's RASTERIZE, are out while the values
// they act on stand where a reset puts them: one question, the reset's,
// asked over each one's frames.
import '../../helpers/a_canvas_standing_on_a_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/se_sound.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart'
    show effectsWithGroupReset;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_editing.dart'
    show seNameTagWithGroupReset;
import 'package:anicel/src/ui/timeline/se_sound_lane_editing.dart'
    show seSoundWithGroupReset;
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show laneResetAt, transformTrackWithGroupReset;
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/named_finders.dart';

void main() {
  opensTheEnginesScreens();
  final identity = TransformPose.uniform(
    center: CanvasPoint(x: 640, y: 360),
    zoom: 1,
    rotationDegrees: 0,
  );
  final centre = CanvasPoint(x: 640, y: 360);

  group('the one step every group Reset takes', () {
    test('a lane already showing the value there with no key takes none; '
        'one showing another, or keyed there, takes it', () {
      final held = PropertyTrack<double>().withKey(0, 0);
      expect(laneResetAt(held, 5, 0.0, space: doubleKeySpace), held);

      final turning = PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(10, 45);
      expect(
        laneResetAt(turning, 5, 0.0, space: doubleKeySpace).keyAt(5)!.value,
        0,
        reason: 'it shows 22.5 there',
      );
      final keyed = PropertyTrack<double>().withKey(5, 0);
      expect(
        laneResetAt(keyed, 5, 0.0, space: doubleKeySpace).keyAt(5),
        keyed.keyAt(5),
        reason: 'its key there is the value already',
      );
    });

    test('🎯a transform reset back to rest stands at rest at every frame — '
        'a key left at its default — so a reset over them changes nothing',
        () {
      final reset = transformTrackWithGroupReset(
        TransformTrack.empty().copyWith(
          rotation: PropertyTrack<double>().withKey(0, 45),
        ),
        frameIndexes: const [0],
        identity: identity,
        defaultAnchorPoint: centre,
      )!;
      expect(reset.rotation.keyAt(0)!.value, 0, reason: '⛔premise');

      expect(
        transformTrackWithGroupReset(
          reset,
          frameIndexes: [for (var frame = 0; frame < 24; frame += 1) frame],
          identity: identity,
          defaultAnchorPoint: centre,
        ),
        isNull,
      );
    });

    test('every group\'s Reset takes that step: an fx\'s, a name tag\'s and '
        'a sound\'s keyed lane already at its default there is left as it '
        'is', () {
      const blurId = EffectId('blur');
      final spec = LayerEffect(
        id: blurId,
        kind: EffectKind.blur,
      ).specs.firstWhere((spec) => spec.id == 'blurriness');
      final keyed = LayerEffect(
        id: blurId,
        kind: EffectKind.blur,
        parameters: {
          'blurriness': EffectParameter(
            track: PropertyTrack<double>().withKey(0, spec.defaultValue),
          ),
        },
      );
      expect(
        effectsWithGroupReset(
          [keyed],
          laneId: effectGroupLaneId(blurId),
          frameIndexes: const [5],
        ),
        isNull,
      );
      expect(
        seNameTagWithGroupReset(
          SeNameTag(
            track: SeNameTagTrack(
              fontSize: PropertyTrack<double>().withKey(
                0,
                SeNameTag.defaultStyle.fontSize,
              ),
            ),
          ),
          frameIndexes: const [5],
        ),
        isNull,
      );
      expect(
        seSoundWithGroupReset(
          SeSound(volume: PropertyTrack<double>().withKey(0, 1.0)),
          frameIndexes: const [5],
        ),
        isNull,
      );
      const keyId = EffectId('key');
      final keyColour = EffectKind.colorKey.parameters.firstWhere(
        (spec) => spec.id == 'keyColor',
      );
      expect(
        effectsWithGroupReset(
          [
            LayerEffect(id: keyId, kind: EffectKind.colorKey).withColor(
              'keyColor',
              PropertyTrack<int>().withKey(0, keyColour.defaultValue.toInt()),
            ),
          ],
          laneId: effectGroupLaneId(keyId),
          frameIndexes: const [5],
        ),
        isNull,
        reason: 'a colour, keyed at its default',
      );
    });
  });

  Future<EditorSessionManager> theApp(WidgetTester tester) async {
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
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  String resetOf(LayerId row, String header) =>
      'timeline-lane-group-reset-$row-$header';
  String rasterizeOf(LayerId row, String header) =>
      'timeline-lane-group-rasterize-$row-$header';

  /// [name]'s press, as the rail draws it now.
  VoidCallback? pressOf(WidgetTester tester, String name) =>
      tester.widget<RailGlyphButton>(find.named(name)).onPressed;

  /// [row]'s lanes twirled open, where they are not yet.
  Future<void> openLanes(
    WidgetTester tester,
    EditorSessionManager session,
    LayerId row,
  ) async {
    if (find.named(resetOf(row, 'transform-group')).evaluate().isNotEmpty) {
      return;
    }
    final toggle = find.named('timeline-lane-toggle-$row');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  void rotated(EditorSessionManager session, PropertyTrack<double> keys) =>
      session.laneVerbs.updateLayerTransformTrack(
        session.activeLayerId!,
        session.activeLayer!.transformTrack.copyWith(rotation: keys),
        description: 'seed',
      );

  testWidgets('🎯the Transform\'s Reset and Rasterize are out on a row at '
      'rest, lit by a key off its default, and out again once its Reset '
      'puts it back — the key kept', (tester) async {
    final session = await theApp(tester);
    final row = session.activeLayerId!;
    await openLanes(tester, session, row);
    final reset = resetOf(row, 'transform-group');
    final rasterize = rasterizeOf(row, 'transform-group');
    expect(pressOf(tester, reset), isNull);
    expect(pressOf(tester, rasterize), isNull);

    session.selectFrameIndex(0);
    rotated(session, PropertyTrack<double>().withKey(0, 45));
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNotNull);
    expect(pressOf(tester, rasterize), isNotNull);

    pressOf(tester, reset)!();
    await tester.pumpAndSettle();
    expect(_rowOf(session, row).transformTrack.rotation.keyAt(0)!.value, 0);
    expect(pressOf(tester, reset), isNull);
    expect(
      pressOf(tester, rasterize),
      isNull,
      reason: 'at rest at every frame, though keyed',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the Reset is asked again as the playhead moves — out where '
      'the group stands at rest, lit where it is moved — and as a lane span '
      'is laid over its keys', (tester) async {
    final session = await theApp(tester);
    final row = session.activeLayerId!;
    await openLanes(tester, session, row);
    final reset = resetOf(row, 'transform-group');
    session.selectFrameIndex(0);
    rotated(
      session,
      PropertyTrack<double>().withKey(0, 0).withKey(10, 45),
    );
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNull, reason: 'at rest at frame 0');

    session.selectFrameIndex(5);
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNotNull, reason: '22.5° there');

    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNull, reason: '⛔premise');
    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row,
      laneId: 'transform-group',
      startIndex: 8,
      endIndexExclusive: 12,
    );
    await tester.pumpAndSettle();
    expect(
      pressOf(tester, reset),
      isNotNull,
      reason: 'the key it covers stands the row at 45°',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the X-sheet\'s Reset is asked again as a lane span is laid '
      'over its keys, as the timeline\'s is', (tester) async {
    final session = await theApp(tester);
    final row = session.activeLayerId!;
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final toggle = find.named('xsheet-lane-toggle-$row');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final reset = 'xsheet-lane-group-reset-$row-transform-group';
    session.selectFrameIndex(0);
    rotated(
      session,
      PropertyTrack<double>().withKey(0, 0).withKey(10, 45),
    );
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNull, reason: 'at rest at frame 0');

    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row,
      laneId: 'transform-group',
      startIndex: 8,
      endIndexExclusive: 12,
    );
    await tester.pumpAndSettle();
    expect(
      pressOf(tester, reset),
      isNotNull,
      reason: 'the key it covers stands the row at 45°',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('an fx header\'s Reset is out at its defaults and lit off '
      'them', (tester) async {
    final session = await theApp(tester);
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    final row = session.activeLayerId!;
    await openLanes(tester, session, row);
    final blur = _rowOf(session, row).effects.single.id;
    final reset = resetOf(row, effectGroupLaneId(blur));
    expect(pressOf(tester, reset), isNull);

    session.effectsAndFx.updateLayerEffects(row, [
      LayerEffect(
        id: blur,
        kind: EffectKind.blur,
        parameters: {'blurriness': EffectParameter(value: 12)},
      ),
    ]);
    await tester.pumpAndSettle();
    expect(pressOf(tester, reset), isNotNull);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the Transform\'s Rasterize is asked over the band that scopes '
      'it: out over frames it stands at rest on, lit over every frame', (
    tester,
  ) async {
    final session = await theApp(tester);
    final row = session.activeLayerId!;
    await openLanes(tester, session, row);
    final rasterize = rasterizeOf(row, 'transform-group');
    session.selectFrameIndex(0);
    rotated(
      session,
      PropertyTrack<double>()
          .withKey(0, 0, outgoing: KeyExit.hold)
          .withKey(5, 45),
    );
    await tester.pumpAndSettle();
    expect(pressOf(tester, rasterize), isNotNull, reason: '45° at frame 5');

    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row,
      laneId: 'transform-group',
      startIndex: 1,
      endIndexExclusive: 4,
    );
    await tester.pumpAndSettle();
    expect(pressOf(tester, rasterize), isNull, reason: 'held at 0° there');
    session.playbackRig.prerenderScheduler.cancel();
  });
}

/// The row as the project holds it now — what every write lands in.
Layer _rowOf(EditorSessionManager session, LayerId id) =>
    requireLayerAnywhere(session.repository.requireProject(), id);
