import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_camera_row.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// 🚨THE CONTE PANEL'S RAIL ROWS ARE THE TIMELINE'S (I-89 ①, 유저
/// 2026-10-13: 「다시 말하지만 이런건 다 콘티패널에도 동일하게 있어야해.
/// 같은 법으로」) — two laws the timeline's rows keep, kept here:
///
/// * 「**레이어 쪽 버튼은 탭다운**」 (유저 확정 2026-08-30): every button on a
///   rail row acts on the press, a column's or not. The S and transition
///   rows were this rail's own labels, and only their swipe columns stood
///   on the press — the colour label, the type button and the speaker
///   waited for the release.
/// * 「**클릭하고 떼면 뭐든 비우게**」 (T10): a press inside the selection
///   holds it — it may be the start of a move — and when it turns out to
///   be a tap, the selection goes. No row of this rail let go.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  Future<EditorSessionManager> pumpRail(
    WidgetTester tester, {
    Project? project,
  }) => pumpStoryboardHost(
    tester,
    project ?? createDefaultProject(),
    surface: const Size(1600, 900),
    pixelsPerFrame: 12,
  );

  Track trackOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.first;

  testWidgets('an S row\'s speaker has opened its mixer before it is '
      'released', (tester) async {
    final session = await pumpRail(tester);
    final se = trackOf(session).seLayers.first.id;
    final mixer = find.byKey(const ValueKey<String>('se-layer-mixer'));

    final gesture = await tester.startGesture(
      tester.getCenter(find.named('storyboard-layer-mute-$se')),
    );
    await tester.pumpAndSettle();
    expect(
      mixer,
      findsOneWidget,
      reason: '「레이어 쪽 버튼은 탭다운」 — the speaker is no swipe column, '
          'so only the ROW puts it on the press',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(mixer, findsOneWidget, reason: 'and the release keeps it open');
  });

  testWidgets('every row of the rail puts its buttons on the press — the S '
      'row, the transition row and the V row', (tester) async {
    final session = await pumpRail(tester);
    final track = trackOf(session);
    // Each one's TYPE button: in the row, and no swipe column — so only
    // the row can put it on the press (the timeline's own pin's reading,
    // `layer_side_acts_on_the_press_header_on_the_release_test`).
    for (final name in [
      'storyboard-layer-type-button-${track.seLayers.first.id}',
      'storyboard-layer-type-button-${track.transitionLayer.id}',
      'storyboard-layer-type-button-v-${track.id.value}',
    ]) {
      final button = find.named(name);
      expect(button, findsOneWidget, reason: '$name is not on the rail');
      expect(
        find.ancestor(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is PressFireScope && widget.fireOn == PressFire.down,
          ),
        ),
        findsWidgets,
        reason: '$name waits for the release',
      );
    }
  });

  /// Taps [name] on the row keyed [label] with [selection] — the row among
  /// it — selected, and says whether the selection went.
  Future<void> tapInside(
    WidgetTester tester,
    EditorSessionManager session, {
    required List<TimelineRowAddress> selection,
    required String label,
    required String name,
  }) async {
    session.rowSelection.value = selection;
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey<String>(label)),
        matching: find.text(name),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      session.rowSelection.value,
      isEmpty,
      reason: '「클릭하고 떼면 뭐든 비우게」 — $label held it on the press, and '
          'nothing let it go on the release',
    );
  }

  testWidgets('a tap inside the selection lets it go — on an S row and on '
      'the V row', (tester) async {
    final session = await pumpRail(tester);
    final track = trackOf(session);
    final selection = <TimelineRowAddress>[
      for (final se in track.seLayers) LayerRowAddress(se.id),
      TrackRowAddress(track.id),
    ];

    // Its NAME — the row's own ground, no control on it.
    await tapInside(
      tester,
      session,
      selection: selection,
      label: 'storyboard-se-label-${track.id.value}-1',
      name: track.seLayers.first.name,
    );
    // And the V row, which wears no layer, the same.
    session.rowSelection.value = selection;
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('storyboard-track-label-${track.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(
      session.rowSelection.value,
      isEmpty,
      reason: 'the V row held it on the press, and nothing let it go',
    );
  });

  testWidgets('…and on the camera row, the conte row and the transition '
      'row — and on a row with no head to wear, in a gap', (tester) async {
    const trackId = TrackId('t1');
    // Cut a [0, 24), four frames of gap, then b [28, 52) — each with a
    // conte layer and a camera.
    Cut cutOf(String id, {int gap = 0}) => Cut(
      id: CutId(id),
      name: id,
      duration: 24,
      leadingGapFrames: gap,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        Layer(
          id: LayerId('$id-conte'),
          name: 'Conte',
          kind: LayerKind.storyboard,
          frames: const [],
        ),
        Layer(
          id: LayerId('$id-cam'),
          name: 'Camera',
          kind: LayerKind.camera,
          frames: const [],
        ),
      ],
    );
    final session = await pumpRail(
      tester,
      project: Project(
        id: const ProjectId('rail-rows'),
        name: 'Rail rows',
        createdAt: DateTime.utc(2026, 10, 16),
        tracks: [
          Track(
            id: trackId,
            name: 'V1',
            cuts: [cutOf('a'), cutOf('b', gap: 4)],
          ),
        ],
      ),
    );
    final track = trackOf(session);
    final camera = LayerRowAddress(trackCameraRowId(trackId));
    final selection = <TimelineRowAddress>[
      camera,
      LayerRowAddress(trackConteRowId(trackId)),
      LayerRowAddress(track.transitionLayer.id),
    ];
    final cameraLabel = find.byKey(
      const ValueKey<String>('storyboard-camera-label-t1'),
    );
    expect(
      find.descendant(
        of: cameraLabel,
        matching: find.byType(TimelineLayerControlsRow),
      ),
      findsOneWidget,
      reason: '⛔전제: stood in a cut, the camera row wears its camera',
    );

    for (final (label, name) in [
      ('storyboard-camera-label-t1', 'Camera'),
      ('storyboard-conte-label-t1', 'Conte'),
      ('storyboard-transition-label-t1', track.transitionLayer.name),
    ]) {
      await tapInside(
        tester,
        session,
        selection: selection,
        label: label,
        name: name,
      );
    }

    // In the gap there is no camera to wear: the row keeps its slots, and
    // its name — and lets go the same.
    session.standOnRow(
      camera,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 26,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: cameraLabel,
        matching: find.byType(TimelineLayerControlsRow),
      ),
      findsNothing,
      reason: '⛔전제: in the gap, no head',
    );
    await tapInside(
      tester,
      session,
      selection: selection,
      label: 'storyboard-camera-label-t1',
      name: 'Camera',
    );
  });
}
