import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
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
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerVisibilityToggleButton;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

/// 🗣️F-322 (유저 2026-10-09): 「콘티패널 간편오버레이가 제대로 서있는곳
/// 행에 맞춰서 안보여주고 V행고정인데 서있는곳 보여주도록. 타임라인패널이랑
/// 통일」.
///
/// The folded storyboard is the row its rail stands on — that row's own
/// label and strip, as the panel draws them, chromeless and at the row's
/// own height — as the folded timeline is the row it stands on. ↩️It was
/// the V row whatever row stood.
const _trackId = TrackId('t1');

Layer _drawn(
  String id, {
  required String name,
  LayerKind kind = LayerKind.storyboard,
  String? ridesOn,
}) => Layer(
  id: LayerId(id),
  name: name,
  kind: kind,
  attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
  attachedPlacement: AttachedPlacement.above,
  attachedMode: AttachedMode.free,
  frames: const [],
);

/// Cut [id]; its conte filed in a folder that hides it when [conteHidden].
Cut _cut(String id, {bool conteHidden = false}) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  camera: CutCamera.empty(),
  layers: [
    _drawn('$id-cel', name: 'Cel', kind: LayerKind.animation),
    _drawn('$id-conte', name: 'Conte').copyWith(
      folderId: conteHidden ? LayerId('$id-folder') : null,
    ),
    _drawn('$id-cam', name: 'Camera', kind: LayerKind.camera),
    if (conteHidden)
      Layer(
        id: LayerId('$id-folder'),
        name: 'F',
        kind: LayerKind.folder,
        isVisible: false,
        frames: const [],
      ),
  ],
);

Project _project({bool conteHidden = false}) => Project(
  id: const ProjectId('folded-stand'),
  name: 'Folded stand',
  createdAt: DateTime.utc(2026, 10, 10),
  tracks: [
    Track(
      id: _trackId,
      name: 'V1',
      cuts: [_cut('a', conteHidden: conteHidden), _cut('b')],
      seLayers: [_drawn('s1', name: 'S1', kind: LayerKind.se)],
    ),
  ],
);

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<EditorSessionManager> _pumpFolded(
  WidgetTester tester, {
  bool conteHidden = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(initialProject: _project(conteHidden: conteHidden)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -420),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
  return _sessionOf(tester);
}

final _overlay = find.byType(CollapsedRowOverlay);

Finder _inOverlay(String key) => find.descendant(
  of: _overlay,
  matching: find.byKey(ValueKey<String>(key)),
);

Future<void> _standOn(
  WidgetTester tester,
  EditorSessionManager session,
  TimelineRowAddress row,
) async {
  session.standOnRow(
    row,
    panel: WorkingPanel.storyboard,
    globalFrameIndex: 3,
  );
  await tester.pumpAndSettle();
  expect(session.storyboardStandingRow, row, reason: '⛔전제');
}

void main() {
  testWidgets('⛔전제 — standing on the V row, the folded row is the track', (
    tester,
  ) async {
    final session = await _pumpFolded(tester);
    await _standOn(tester, session, const TrackRowAddress(_trackId));

    expect(_inOverlay('collapsed-storyboard-cut-blocks'), findsOneWidget);
  });

  testWidgets('🚨standing on the conte row, the folded row is the conte row — '
      'its head and its panels, at its own height', (tester) async {
    final session = await _pumpFolded(tester);
    await _standOn(
      tester,
      session,
      LayerRowAddress(trackConteRowId(_trackId)),
    );

    expect(_inOverlay('collapsed-storyboard-cut-blocks'), findsNothing);
    expect(_inOverlay('storyboard-conte-label-t1'), findsOneWidget);
    expect(_inOverlay('storyboard-conte-row-t1'), findsOneWidget);
    final head = tester.widget<TimelineLayerControlsRow>(
      find.descendant(
        of: _overlay,
        matching: find.byType(TimelineLayerControlsRow),
      ),
    );
    expect(head.chromeless, isTrue, reason: 'the folded row keeps no ground');
    final folded = tester.widget<CollapsedRowOverlay>(_overlay);
    expect(
      folded.height,
      isNot(StoryboardPanel.defaultTrackLaneHeight),
      reason: 'not the V row\'s',
    );
    expect(
      tester.getSize(_inOverlay('storyboard-conte-label-t1')).height,
      closeTo(folded.height, 0.5),
      reason: 'the row\'s own height (D15: 「해당 행 높이에따라서 맞춤」)',
    );
  });

  testWidgets('…an S row\'s, and the camera row\'s, the same way', (
    tester,
  ) async {
    final session = await _pumpFolded(tester);
    await _standOn(tester, session, const LayerRowAddress(LayerId('s1')));
    expect(_inOverlay('storyboard-se-label-t1-1'), findsOneWidget);
    expect(_inOverlay('storyboard-se-row-0-1'), findsOneWidget);

    await _standOn(tester, session, LayerRowAddress(trackCameraRowId(_trackId)));
    expect(_inOverlay('storyboard-camera-label-t1'), findsOneWidget);
    expect(_inOverlay('storyboard-se-label-t1-1'), findsNothing);
  });

  testWidgets('🚨a stand made while folded moves the folded row with it', (
    tester,
  ) async {
    final session = await _pumpFolded(tester);
    await _standOn(tester, session, const TrackRowAddress(_trackId));
    expect(_inOverlay('collapsed-storyboard-cut-blocks'), findsOneWidget);

    await _standOn(
      tester,
      session,
      LayerRowAddress(trackConteRowId(_trackId)),
    );

    expect(_inOverlay('collapsed-storyboard-cut-blocks'), findsNothing);
    expect(_inOverlay('storyboard-conte-label-t1'), findsOneWidget);
    expect(
      tester.getSize(_overlay).height,
      closeTo(tester.widget<CollapsedRowOverlay>(_overlay).height, 0.5),
      reason: 'the room the fold keeps is the row\'s, read again',
    );
  });

  testWidgets('🚨the folded conte row wears the eye its row has on the '
      'timeline: a folder above that hides the row dims it (F-185)', (
    tester,
  ) async {
    final session = await _pumpFolded(tester, conteHidden: true);
    await _standOn(
      tester,
      session,
      LayerRowAddress(trackConteRowId(_trackId)),
    );

    final eye = tester.widget<LayerVisibilityToggleButton>(
      find.descendant(
        of: _inOverlay('storyboard-conte-label-t1'),
        matching: find.byType(LayerVisibilityToggleButton),
      ),
    );
    expect(eye.hiddenAbove, isTrue);
    expect(eye.isVisible, isTrue, reason: 'its own switch keeps its value');
  });
}
