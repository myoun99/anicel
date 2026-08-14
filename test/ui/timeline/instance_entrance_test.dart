import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../flyout_test_helpers.dart';
import 'timeline_cell_probe.dart';

/// The toolbar scrolls horizontally when squeezed (narrow surfaces), so
/// bring Add into its viewport before tapping.
Future<void> _tapToolbarAdd(WidgetTester tester) async {
  final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
  await tester.ensureVisible(addButton);
  await tester.pumpAndSettle();
  await tester.tap(addButton);
  await tester.pumpAndSettle();
}

/// Entrance unification: EVERY layer kind opens its instance editor on
/// double-tap, and the toolbar Add / Edit Instance buttons dispatch by
/// kind. Fixture: a drawing layer with a named 4-frame entry, an empty SE
/// layer and a camera layer.
Project _project() {
  return Project(
    id: const ProjectId('entrance-project'),
    name: 'Entrance Project',
    createdAt: DateTime.utc(2026, 7, 9),
    tracks: [
      Track(
        id: const TrackId('entrance-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('entrance-cut'),
            name: 'Entrance Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('draw'),
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('draw-f1'),
                    duration: 4,
                    name: 'A1',
                    strokes: const [],
                  ),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(
                    FrameId('draw-f1'),
                    length: 4,
                  ),
                },
              ),
              Layer(
                id: const LayerId('voice'),
                name: 'S1',
                kind: LayerKind.se,
                frames: const [],
                timeline: const {},
              ),
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<ProjectRepository> _pumpHome(WidgetTester tester) async {
  late ProjectRepository repository;
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(),
        onRepositoryCreated: (repo) => repository = repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _doubleTapCell(WidgetTester tester, String cellKey) async {
  // EVERY row paints its cells now (UI-R9 #12b for the drawing rows, R28 #4
  // for SE / camera / instruction), so the tap point comes from the painter
  // probe rather than a cell widget's box.
  final cell = parseTimelineCellKey(cellKey);
  final target = timelineCellCenter(tester, cell.layerId, cell.frameIndex);
  await tester.tapAt(target);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(target);
  await tester.pumpAndSettle();
}

Cut _cut(ProjectRepository repository) =>
    repository.requireProject().tracks.single.cuts.single;

void main() {
  testWidgets('drawing cell double-tap opens the frame-name editor; single '
      'tap still selects', (tester) async {
    final repository = await _pumpHome(tester);

    // Single tap: selection only, no dialog.
    await tapTimelineCell(tester, 'draw', 2);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('rename-frame-dialog')),
      findsNothing,
    );
    // The selection ring lives on the grid cursor layer and sits exactly
    // over the tapped cell.
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey<String>('timeline-selected-cell')),
      ),
      timelineCellGlobalRect(tester, 'draw', 2).topLeft,
    );

    await _doubleTapCell(tester, 'timeline-cell-draw-1');
    expect(
      find.byKey(const ValueKey<String>('rename-frame-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-frame-text-field')),
      'A2',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(_cut(repository).layers.first.frames.single.name, 'A2');
  });

  testWidgets('camera cell double-tap opens the key dialog; keying a lane '
      'commits ONE undo step', (tester) async {
    final repository = await _pumpHome(tester);

    await _doubleTapCell(tester, 'timeline-cell-cam-2');
    expect(find.text('Camera keys — frame 3'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('camera-key-toggle-position')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();

    expect(_cut(repository).camera.track.position.keyAt(2), isNotNull);
    expect(_cut(repository).camera.track.scale.keyAt(2), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_cut(repository).camera.track.position.keyAt(2), isNull);
  });

  testWidgets('toolbar Add on the camera layer keys the current pose at '
      'the playhead', (tester) async {
    final repository = await _pumpHome(tester);

    await tapTimelineCell(tester, 'cam', 4);
    await tester.pumpAndSettle();
    await _tapToolbarAdd(tester);

    final track = _cut(repository).camera.track;
    expect(track.position.keyAt(4), isNotNull);
    expect(track.scale.keyAt(4), isNotNull);
    expect(track.rotation.keyAt(4), isNotNull);
  });

  testWidgets('toolbar Add on an empty SE cell creates a DEFAULT entry '
      'directly — no dialog (UI-R25 #2); the Edit Instance dialog labels '
      'it afterwards', (tester) async {
    final repository = await _pumpHome(tester);

    await tapTimelineCell(tester, 'voice', 3);
    await tester.pumpAndSettle();
    await _tapToolbarAdd(tester);
    expect(find.text('New SE'), findsNothing, reason: 'creation is silent');

    final seLayer = _cut(
      repository,
    ).layers.firstWhere((layer) => layer.kind == LayerKind.se);
    expect(seLayer.timeline[3], isNotNull, reason: 'the entry just exists');

    // Editing stays the dialog's job (the unified edit entrance).
    await tapCommandButton(
      tester,
      const ValueKey<String>('rename-frame-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('se-dialogue-field')),
      '쿵',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    expect(
      _cut(repository)
          .layers
          .firstWhere((layer) => layer.kind == LayerKind.se)
          .frames
          .single
          .name,
      '쿵',
    );
  });

  /// 🚨T25 caught its own bug here. When Edit Instance moved to the shared
  /// pill the DISPATCH started asking `editInstanceSubject`, while the
  /// button's enablement kept the toolbar's private kind switch — and the
  /// subject's cell rung read `canRenameFrameAtCurrentFrame`, which is false
  /// for a camera row. Lit button, silent press: the worst of the three
  /// answers, because nothing on screen says the verb declined. The two
  /// predicates for 「이 셀에 열 게 있나」 are one getter now
  /// (`canEditCellInstanceAtCurrentFrame`), and this test is what fails if
  /// they ever come apart again.
  testWidgets('toolbar Edit Instance opens the camera key dialog for the '
      'camera layer', (tester) async {
    await _pumpHome(tester);

    await tapTimelineCell(tester, 'cam', 0);
    await tester.pumpAndSettle();
    // Edit Instance lives in the Frame ▾ flyout (R-toolbar round).
    await tapCommandButton(
      tester,
      const ValueKey<String>('rename-frame-button'),
    );

    expect(find.text('Camera keys — frame 1'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
    );
    await tester.pumpAndSettle();
  });
}
