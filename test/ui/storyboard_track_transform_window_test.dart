import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// The V lanes speak the TRACK's global axis, driven through the real
/// rail (R4a window adapter → R4b track-direct): a key toggled while the
/// SECOND cut is active lands at the PLAYHEAD's global frame — the second
/// cut's start, never a raw local 0 — and the fade handles still write
/// through the cut's window, leaving neighbors alone.
void main() {
  Future<EditorSessionManager> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    manager.createCut(); // Two cuts; the NEW (second) one is active.
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([manager, manager.frameSeekCommitted]),
            builder: (context, _) => StoryboardTabHost(
              session: manager,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  Future<void> twirlOpenTransformLanes(
    WidgetTester tester,
    String trackId,
  ) async {
    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-lane-toggle-$trackId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:$trackId-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a key toggled on the ACTIVE second cut\'s lane lands at the '
      'cut\'s GLOBAL start on the track — and toggles back off there', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final trackId = manager.activeTrack.id;
    final secondCut = manager.activeTrack.cuts[1];
    expect(manager.activeCutId, secondCut.id, reason: 'createCut selects it');
    final secondStart = manager
        .trackFrameAxis()
        .entryFor(secondCut.id)!
        .startFrame;
    expect(secondStart, greaterThan(0));

    await twirlOpenTransformLanes(tester, trackId.value);

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-key-toggle-v-track:${trackId.value}-position',
        ),
      ),
    );
    await tester.pumpAndSettle();

    var lane = manager.activeTrack.transformTrack.position;
    expect(
      lane.keyAt(secondStart),
      isNotNull,
      reason: 'local frame 0 of the second cut = global $secondStart',
    );
    expect(lane.keyAt(0), isNull, reason: 'NOT at the raw local frame');

    // The same toggle removes it — the round-trip stays in the window.
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-key-toggle-v-track:${trackId.value}-position',
        ),
      ),
    );
    await tester.pumpAndSettle();
    lane = manager.activeTrack.transformTrack.position;
    expect(lane.keyAt(secondStart), isNull);
    expect(lane.isEmpty, isTrue);
  });

  testWidgets('a rail toggle keys the track with NO cut under the playhead '
      '— parked past the last cut, "keys exist with no cut under them"', (
    tester,
  ) async {
    final manager = await pumpHost(tester);
    final trackId = manager.activeTrack.id;
    final lastEnd = manager
        .trackFrameAxis()
        .entryFor(manager.activeTrack.cuts[1].id)!
        .endFrame;
    final parked = lastEnd + 3;

    seekStoryboardGlobalFrame(manager, parked);
    await tester.pumpAndSettle();
    expect(manager.activeCutOrNull, isNull, reason: 'parked in the open');

    await twirlOpenTransformLanes(tester, trackId.value);
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'storyboard-lane-key-toggle-v-track:${trackId.value}-position',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      manager.activeTrack.transformTrack.position.keyAt(parked),
      isNotNull,
      reason: 'the toggle keys the GLOBAL playhead frame, cut or no cut',
    );
  });

  testWidgets('a band drag on a V lane row SELECTS the track lane range '
      '(carrier route), shows the storyboard band, and a drag inside '
      'MOVES the keys as one undo', (tester) async {
    final manager = await pumpHost(tester);
    final trackId = manager.activeTrack.id;
    manager.updateTrackTransformTrack(
      trackId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          2,
          CanvasPoint(x: 10, y: 20),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await twirlOpenTransformLanes(tester, trackId.value);

    // Select frames 1..4 on the Position lane band (12 px/frame).
    final row = find.byKey(
      const ValueKey<String>('storyboard-track-lane-row-0-position'),
    );
    final rowTopLeft = tester.getTopLeft(row);
    final rowCenterY = tester.getCenter(row).dy;
    final select = await tester.startGesture(
      Offset(rowTopLeft.dx + 1 * 12 + 6, rowCenterY),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await select.moveBy(const Offset(36, 0));
    await tester.pump();
    await select.up();
    await tester.pumpAndSettle();

    final selection = manager.laneRangeSelection.value;
    expect(selection, isNotNull);
    expect(selection!.layerId, trackTransformLaneCarrierId(trackId));
    expect(selection.laneId, 'position');
    expect(selection.contains(2), isTrue, reason: 'the key sits in the span');
    expect(
      find.byKey(const ValueKey<String>('storyboard-lane-range-selection')),
      findsOneWidget,
      reason: 'the storyboard draws the timeline\'s one band language',
    );

    // Drag INSIDE the selection (frame 3, off the key marker) 2 frames
    // right: the spanned keys move 2 → 4, committed as ONE undo.
    final move = await tester.startGesture(
      Offset(rowTopLeft.dx + 3 * 12 + 6, rowCenterY),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await move.moveBy(const Offset(24, 0));
    await tester.pump();
    await move.up();
    await tester.pumpAndSettle();

    var lane = manager.activeTrack.transformTrack.position;
    expect(lane.keyAt(4), isNotNull, reason: 'moved +2');
    expect(lane.keyAt(2), isNull);

    manager.undo();
    lane = manager.activeTrack.transformTrack.position;
    expect(lane.keyAt(2), isNotNull, reason: 'one undo restores the move');
    expect(lane.keyAt(4), isNull);

    // Let the tap/long-press arena timers of the layered gestures expire
    // before teardown (translucent layers race several recognizers).
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the fade handles write into the ACTIVE cut\'s window at its '
      'global offset (setCutFade through the host)', (tester) async {
    final manager = await pumpHost(tester);
    final secondCut = manager.activeTrack.cuts[1];
    final secondStart = manager
        .trackFrameAxis()
        .entryFor(secondCut.id)!
        .startFrame;

    await twirlOpenTransformLanes(tester, manager.activeTrack.id.value);

    // 3 frames rightward on the fade-in handle (12 px/frame).
    await tester.drag(
      find.byKey(
        ValueKey<String>(
          'storyboard-cut-fade-in-handle-${secondCut.id.value}',
        ),
      ),
      const Offset(36, 0),
    );
    await tester.pumpAndSettle();

    final opacity = manager.activeTrack.transformTrack.opacity;
    expect(opacity.keyAt(secondStart)?.value, 0.0);
    expect(opacity.keyAt(secondStart + 3)?.value, 1.0);
    expect(opacity.keyAt(0), isNull, reason: 'first cut\'s window untouched');
  });
}
