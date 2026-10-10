import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// F-195 on the STORYBOARD's rail: a value scrubbed on an S row's lane or on
/// the V row's fx chain is shown by the label itself through the one drag
/// channel — the label no longer prints a scrubbed text of its own, so a
/// rail that did not read the channel would sit still under the hand.
///
/// The storyboard builds its lane labels from lists of its own rather than
/// through the timeline's row gate, which is why this rail needs pinning
/// apart from the timeline's (`an_edit_shows_while_it_is_dragged_test`).
void main() {
  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String label(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// Scrubs the value cell [key] by [steps] × 10px to the right and leaves
  /// the pointer down.
  Future<TestGesture> scrub(WidgetTester tester, String key, int steps) async {
    final cell = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(cell),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < steps; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    return gesture;
  }

  testWidgets('an S row\'s value, scrubbed on the storyboard, moves its label '
      'before the release — and writes nothing until it', (tester) async {
    final session = await pumpStoryboard(tester);
    final track = session.activeTrack.id.value;
    final se = session.activeTrack.seLayers.first.id.value;
    await tapKey(tester, 'storyboard-se-lane-toggle-$track-1');
    await tapKey(tester, 'storyboard-lane-group-toggle-$se-transform-group');
    final value = 'storyboard-lane-value-$se-rotation';
    final before = label(tester, value);

    final gesture = await scrub(tester, value, 4);

    expect(session.dragPreview.value, isA<LaneEditPreview>());
    expect(
      label(tester, value),
      isNot(before),
      reason: 'the label reads the edit in flight — the rail follows it',
    );
    expect(
      session.activeTrack.seLayers.first.transformTrack.rotation.isEmpty,
      isTrue,
      reason: 'DISPLAY only',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.dragPreview.value, isNull);
    expect(
      session.activeTrack.seLayers.first.transformTrack.rotation.isEmpty,
      isFalse,
      reason: 'the release is the one write',
    );
  });

  testWidgets('the V row\'s fx value, scrubbed on the storyboard, moves its '
      'label before the release', (tester) async {
    final session = await pumpStoryboard(tester);
    final trackId = session.activeTrack.id;
    const effectId = EffectId('sb-v-blur');
    session.effectsAndFx.updateTrackEffects(trackId, [
      LayerEffect.defaults(id: effectId, kind: EffectKind.blur),
    ]);
    await tester.pumpAndSettle();
    final carrier = trackTransformLaneCarrierId(trackId).value;
    await tapKey(tester, 'storyboard-track-lane-toggle-${trackId.value}');
    await tapKey(
      tester,
      'storyboard-lane-group-toggle-$carrier-${effectGroupLaneId(effectId)}',
    );
    final value =
        'storyboard-lane-value-$carrier-${effectLaneId(effectId, 'blurX')}';
    final before = label(tester, value);

    final gesture = await scrub(tester, value, 4);

    expect(session.dragPreview.value, isA<LaneEditPreview>());
    expect(label(tester, value), isNot(before));
    expect(
      effectParameterValueAt(
        session.activeTrack.effects,
        effectId,
        'blurX',
        0,
      ),
      effectParameterValueAt(
        [LayerEffect.defaults(id: effectId, kind: EffectKind.blur)],
        effectId,
        'blurX',
        0,
      ),
      reason: 'the track itself is untouched until the release',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.dragPreview.value, isNull);
  });
}
