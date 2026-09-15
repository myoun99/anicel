import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
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
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart'
    show ExportPill;
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

    // ⚠️A PAUSE, on purpose. The single tap above is still inside Flutter's
    // double-tap window (kDoubleTapTimeout), so the next tap on a
    // neighbouring cell would PAIR with it — the R26 #37 gate rightly refuses
    // that pair (two different cells) and consumes its record, and the real
    // double tap then starts one tap late. A person pauses between selecting
    // and double-tapping. This passed without saying so only because
    // Material buttons animated their colour for ~200ms after the selection
    // and pumpAndSettle burned that time; the app's buttons change colour
    // instantly since 2026-09-10, so the pause is said out loud.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));
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

  /// 🚨★★★I-9 (유저 확정 2026-08-29, I-9-Q2 = `all-kinds`): 「빈 칸 더블클릭
  /// = 만들기」 on EVERY row kind. 유저 원문: 「타임라인의 se행이랑
  /// 트랜지션행이었는데 통일되서 사라졌을수도? 아무튼 **새로만들자.**」
  ///
  /// ONE gesture, two meanings. The pair below is what pins that: a double
  /// tap on the SAME empty camera cell creates the key, and a double tap on
  /// it AGAIN — now filled — opens the dialog. If the fork ever collapses
  /// into one meaning, exactly one of these two dies.
  testWidgets('an EMPTY camera cell double-tap KEYS it, and a second '
      'double-tap opens the dialog', (tester) async {
    final repository = await _pumpHome(tester);
    expect(
      _cut(repository).camera.track.position.keyAt(2),
      isNull,
      reason: 'the fixture camera row starts with no keys at all',
    );

    await _doubleTapCell(tester, 'timeline-cell-cam-2');
    expect(
      find.text('Rename key'),
      findsNothing,
      reason:
          'an empty cell has nothing to open — creation is silent, the '
          'same sentence the toolbar Add already spoke',
    );
    expect(
      _cut(repository).camera.track.position.keyAt(2),
      isNotNull,
      reason: 'the row created through ITS OWN verb (a camera key)',
    );

    // Filled now, so the very same gesture means the other thing — the
    // COMMON key window (F-17): the camera row is its transform header, and
    // its cell's instance is its key.
    await _doubleTapCell(tester, 'timeline-cell-cam-2');
    expect(find.text('Rename key'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
  });

  /// 🚨THE SE ROW ALREADY DID THIS, and that is the point of I-9.
  ///
  /// `_editSeLabel` has said 「covered cells edit; EMPTY cells create a
  /// default one-frame entry DIRECTLY」 since UI-R25 #2. So this row is not
  /// a mutation target for the new fork — turning the fork off leaves this
  /// case green, because the SE arm creates either way. It is a REGRESSION
  /// guard: the row the user remembered by name must not lose what it had
  /// while the others are catching up to it.
  ///
  /// 🧪The fork's own evidence is the camera and drawing pair above, which
  /// both die when it is off.
  ///
  /// ↩️No longer true of the SE row (F-105, 유저 2026-09-12: 「se행만 현재
  /// 인덱스 비어있을때 편집버튼이 활성화되는데다가, 누르면 프레임이 생김 …
  /// 기존 로직대로 법 통일하고 삭제」): `_editSeLabel` stopped creating, so the
  /// double tap's fork is now the SE row's only creator and this case dies
  /// with it too.
  testWidgets('an EMPTY SE cell double-tap creates the entry, not a dialog', (
    tester,
  ) async {
    final repository = await _pumpHome(tester);
    Layer se() => _cut(
      repository,
    ).layers.firstWhere((layer) => layer.kind == LayerKind.se);
    expect(se().frames, isEmpty, reason: 'the fixture SE row starts empty');

    await _doubleTapCell(tester, 'timeline-cell-voice-3');

    expect(
      se().frames,
      hasLength(1),
      reason: 'the SE row is one of the two the user remembered by name',
    );
    expect(
      se().timeline[3],
      isNotNull,
      reason: 'and the entry lands on the cell that was tapped',
    );
    expect(
      find.byKey(const ValueKey<String>('se-dialogue-field')),
      findsNothing,
      reason: 'creation never opens a dialog (UI-R25 #2)',
    );
  });

  testWidgets('an EMPTY drawing cell double-tap makes a cel, and does NOT '
      'rename the one next door', (tester) async {
    final repository = await _pumpHome(tester);
    // The fixture's drawing row is exposed over frames 0..3 only.
    expect(_cut(repository).layers.first.frames, hasLength(1));

    await _doubleTapCell(tester, 'timeline-cell-draw-5');

    expect(
      find.byKey(const ValueKey<String>('rename-frame-dialog')),
      findsNothing,
      reason: 'an empty cell has no name to edit',
    );
    expect(
      _cut(repository).layers.first.frames,
      hasLength(2),
      reason: 'it made a cel of its own through createDrawingAtCurrentFrame',
    );
  });

  testWidgets('a FILLED cell is untouched by I-9 — it still opens', (
    tester,
  ) async {
    // ⛔The control. A fork that fired on both sides would pass every
    // creation case above and quietly replace the editor everywhere.
    final repository = await _pumpHome(tester);
    final before = _cut(repository).layers.first.frames.length;

    await _doubleTapCell(tester, 'timeline-cell-draw-1');

    expect(
      find.byKey(const ValueKey<String>('rename-frame-dialog')),
      findsOneWidget,
    );
    expect(_cut(repository).layers.first.frames, hasLength(before));
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
  });

  /// 🗣️F-17 (유저 2026-09-01): 「카메라레이어 헤더에서 편집작동시키면 아직도
  /// 카메라 키 창 뜸. 이거 없애라고. 공통창 키 이름변경 창 뜨게하라고 … 해당
  /// 키 공용 편집창 손봐서 이름변경이랑 오른쪽에 유니언 타입 변경 두개
  /// 존재하도록. 물론 헤더에서 작동시 유니언타입 일괄변경되는건 기존이랑
  /// 조작감 동일」. The camera row is its transform header, so ONE name and
  /// ONE type land on every member key at the frame — as one undo step.
  testWidgets('the camera row edits its keys in the COMMON key window — a '
      'name and a type on every member, ONE undo step', (tester) async {
    final repository = await _pumpHome(tester);

    await tapTimelineCell(tester, 'cam', 2);
    await tester.pumpAndSettle();
    await _tapToolbarAdd(tester);
    expect(_cut(repository).camera.track.position.keyAt(2), isNotNull);

    await tapCommandButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    expect(
      find.text('Rename key'),
      findsOneWidget,
      reason: 'the common window — the camera no longer keeps one of its own',
    );
    ExportPill pill(String kind) => tester.widget<ExportPill>(
      find.byKey(ValueKey<String>('rename-key-interpolation-$kind')),
    );
    expect(
      pill('linear').selected,
      isTrue,
      reason: 'the window opens on the type the keys agree on',
    );
    expect(pill('hold').selected, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-frame-text-field')),
      'Wall',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-key-interpolation-hold')),
    );
    await tester.pumpAndSettle();
    expect(pill('hold').selected, isTrue, reason: 'the pick shows at once');
    expect(pill('linear').selected, isFalse);
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-ok-button')),
    );
    await tester.pumpAndSettle();

    final track = _cut(repository).camera.track;
    for (final key in [
      track.position.keyAt(2),
      track.scale.keyAt(2),
      track.rotation.keyAt(2),
    ]) {
      expect(key!.name, 'Wall', reason: 'the header names every member');
      expect(
        key.interpolation,
        PropertyKeyInterpolation.hold,
        reason: 'and types every member (「일괄변경」)',
      );
    }

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    final undone = _cut(repository).camera.track.position.keyAt(2)!;
    expect(undone.name, isNull, reason: 'ONE step took the name…');
    expect(
      undone.interpolation,
      PropertyKeyInterpolation.linear,
      reason: '…and the type with it',
    );
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
      const ValueKey<String>('shared-edit-button'),
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
      _cut(repository).layers
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
  testWidgets('toolbar Edit Instance on a camera KEY opens the COMMON key '
      'window — the camera row is its transform header (F-17)', (tester) async {
    await _pumpHome(tester);

    await tapTimelineCell(tester, 'cam', 0);
    await tester.pumpAndSettle();
    await _tapToolbarAdd(tester);
    // Edit Instance lives in the Frame ▾ flyout (R-toolbar round).
    await tapCommandButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );

    expect(find.text('Rename key'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
  });

  /// 🚨F-105 — EDIT INSTANCE EDITS WHAT THE CELL HOLDS, AND NEVER CREATES.
  ///
  /// 유저 2026-09-12: 「se행만 현재 인덱스 비어있을때 편집버튼이 활성화되는데다가,
  /// 누르면 프레임이 생김. 대체 누가 이딴거 만들라했는지? 기존 로직대로 법
  /// 통일하고 삭제」. The other rows' Edit went dark on an empty cell; the SE
  /// row's stayed lit there, and its editor made a one-frame entry. Creating
  /// is the double tap's fork (I-9, above) and the ＋'s (the Add test above) —
  /// both stay exactly as they were.
  testWidgets('toolbar Edit Instance is DARK on an EMPTY SE cell, and a press '
      'there makes nothing (F-105)', (tester) async {
    final repository = await _pumpHome(tester);
    await tapTimelineCell(tester, 'voice', 3);
    await tester.pumpAndSettle();

    expect(
      await readCommandEnabled(
        tester,
        const ValueKey<String>('shared-edit-button'),
      ),
      isFalse,
      reason: 'an empty cell has nothing to edit',
    );
    await tapCommandButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );

    expect(
      _cut(
        repository,
      ).layers.firstWhere((layer) => layer.kind == LayerKind.se).frames,
      isEmpty,
      reason: 'the Edit button made the entry here — creating is the double '
          'tap\'s and the ＋\'s',
    );
  });
}
