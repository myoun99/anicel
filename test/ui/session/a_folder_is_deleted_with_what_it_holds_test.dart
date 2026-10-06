import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_name_commands.dart';

/// F-305 (유저 2026-10-06): 「타임라인에서 폴더 삭제할때 내용물도 함께 삭제.
/// 선택범위로 폴더/내용물 선택하고 삭제하는건 알아서 폴더만 삭제되도록 하는게
/// 로직적으로 깔끔하니 그렇게 한다던가? 클튜는 아마 내용물도 삭제하시겠습니까?
/// 라고 물어보는데 필요없어보임. 드래그로 밖으로 꺼내고 폴더삭제하는게 확실함.
/// 폴더 삭제한단건 내용물도 삭제하고싶다는것임. 다만 내용물도 삭제리스트에
/// 보여지게는 하면 될듯」.
///
/// A folder's delete DISSOLVED it until now — the row went and its members
/// stayed.
///
/// The collaborator the session's half lives in — named so
/// `tool/mutation_run.dart` runs this file for it.
LayerVerbs rowsOf(EditorSessionManager session) => session.layerVerbs;

const _cutId = CutId('f305-cut');

Layer _row(String id, {String? inside, LayerKind kind = LayerKind.animation}) =>
    Layer(
      id: LayerId(id),
      name: id,
      kind: kind,
      folderId: inside == null ? null : LayerId(inside),
      frames: const [],
      timeline: const {},
    );

/// A cut whose rows are [layers], bottom → top.
EditorSessionManager _session(List<Layer> layers) {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('f305'),
      name: 'F-305',
      createdAt: DateTime.utc(2026, 10, 7),
      tracks: [
        Track(
          id: const TrackId('f305-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: _cutId,
              name: 'c1',
              duration: 24,
              canvasSize: const CanvasSize(width: 320, height: 180),
              layers: layers,
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(session.dispose);
  return session;
}

/// The stack this file stands on, bottom → top:
///
///     over
///     F ─┬─ G ─── c
///        ├─ b
///        └─ a
///     under
///
/// A folder row sits directly above the run it holds.
List<Layer> _nested() => [
  _row('under'),
  _row('a', inside: 'F'),
  _row('b', inside: 'F'),
  _row('c', inside: 'G'),
  _row('G', inside: 'F', kind: LayerKind.folder),
  _row('F', kind: LayerKind.folder),
  _row('over'),
];

List<String> _stack(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers) layer.id.value,
];

void main() {
  test('the fixture is a well-formed stack', () {
    final session = _session(_nested());
    expect(folderStructureProblem(session.requireActiveCut.layers), isNull);
  });

  test('deleting a folder takes every row it holds, folders inside it '
      'too — and one undo brings them all back where they were', () {
    final session = _session(_nested());
    session.selectLayer(const LayerId('F'));

    rowsOf(session).deleteActiveLayer();

    expect(
      _stack(session),
      ['under', 'over'],
      reason: '「폴더 삭제한단건 내용물도 삭제하고싶다는것임」 — it dissolved, '
          'and a, b, c and the inner folder all stayed',
    );

    session.undo();
    expect(_stack(session), ['under', 'a', 'b', 'c', 'G', 'F', 'over']);
    final back = session.requireActiveCut.layers;
    expect(folderStructureProblem(back), isNull);
    expect(back.byId(const LayerId('a'))!.folderId, const LayerId('F'));
    expect(back.byId(const LayerId('c'))!.folderId, const LayerId('G'));
    expect(back.byId(const LayerId('G'))!.folderId, const LayerId('F'));
  });

  test('…and you are left standing on a row that is still there', () {
    final session = _session(_nested());
    session.selectLayer(const LayerId('F'));
    rowsOf(session).deleteActiveLayer();
    expect(session.activeLayerId, const LayerId('over'));

    // The TOP row a folder: the row under it in the stack is its own. Two
    // rows stay, so a hand-off that names a row no longer there — and falls
    // back to the bottom of the stack — cannot read as the right one.
    final topFolder = _session([
      _row('bottom'),
      _row('under'),
      _row('a', inside: 'F'),
      _row('F', kind: LayerKind.folder),
    ]);
    topFolder.selectLayer(const LayerId('F'));
    rowsOf(topFolder).deleteActiveLayer();
    expect(_stack(topFolder), ['bottom', 'under']);
    expect(
      topFolder.activeLayerId,
      const LayerId('under'),
      reason: 'the hand-off was made as if the folder row alone went, and '
          'named the row it had just deleted',
    );
  });

  test('a folder selected together with rows inside it is deleted as the '
      'folder alone — which takes all it holds, selected or not', () {
    final session = _session(_nested());
    session.rowSelection.value = [
      const LayerRowAddress(LayerId('F')),
      const LayerRowAddress(LayerId('a')),
      const LayerRowAddress(LayerId('c')),
      const LayerRowAddress(LayerId('over')),
    ];

    expect(
      rowsOf(session).deletableSelectedLayerIds().map((id) => id.value).toSet(),
      {'F', 'over'},
      reason: '「알아서 폴더만 삭제되도록」 — a and c are the folder\'s',
    );

    rowsOf(session).deleteSelectedLayers();

    expect(_stack(session), ['under']);
    expect(session.activeLayerId, const LayerId('under'));
    session.undo();
    expect(_stack(session), ['under', 'a', 'b', 'c', 'G', 'F', 'over']);
  });

  test('what a folder takes along is listed as the rail shows it, top '
      'first — and a row named for the delete is not listed twice', () {
    final session = _session(_nested());
    List<String> held(List<String> ids) => [
      for (final row in rowsOf(session).rowsHeldBy([
        for (final id in ids) LayerId(id),
      ]))
        row.id.value,
    ];

    expect(held(['F']), ['G', 'c', 'b', 'a']);
    expect(held(['G']), ['c']);
    expect(held(['over']), isEmpty, reason: 'a plain row holds nothing');
    expect(held(['F', 'G']), ['c', 'b', 'a']);
  });

  test('a row the cut may not lose stays, let out of the folder that '
      'went — its last instruction row', () {
    final session = _session([
      _row('a', inside: 'F'),
      _row('memo', inside: 'F', kind: LayerKind.instruction),
      _row('F', kind: LayerKind.folder),
    ]);
    session.selectLayer(const LayerId('F'));

    rowsOf(session).deleteActiveLayer();

    expect(_stack(session), ['memo']);
    expect(
      session.requireActiveCut.layers.single.folderId,
      isNull,
      reason: 'it stays for the reason it would have stayed alone, and the '
          'folder row it stood in is gone',
    );
    session.undo();
    expect(_stack(session), ['a', 'memo', 'F']);
  });

  test('an attach organizer goes the same way, with the attach rows it '
      'holds — its last row takes the organizer along, and the base stays', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final base = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.animation)
        .id;
    session.selectLayer(base);
    session.folders.addAttachedLayer(AttachedPlacement.above);
    final attached = session.activeLayer!.id;
    session.folders.groupActiveAttachIntoFolder();
    final organizer = session.requireActiveCut.layers.folderLayers.single.id;
    final before = _stack(session);
    expect(
      session.requireActiveCut.layers.byId(attached)!.folderId,
      organizer,
      reason: 'fixture: the attach row stands in its organizer',
    );
    session.selectLayer(organizer);

    rowsOf(session).deleteActiveLayer();

    expect(
      _stack(session),
      [...before]
        ..remove(attached.value)
        ..remove(organizer.value),
    );
    session.undo();
    expect(_stack(session), before);
    expect(folderStructureProblem(session.requireActiveCut.layers), isNull);
  });

  testWidgets('the delete window lists what the folder holds under its '
      'question — one question, no second one about the contents', (
    tester,
  ) async {
    final session = _session(_nested());
    session.selectLayer(const LayerId('F'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => deleteActiveLayerWithDialog(context, session),
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('${AppText.strings.deleteLayerHeldHeading} (4)'),
      findsOneWidget,
      reason: 'the list stands OPEN under the question, with its count',
    );
    for (final name in ['G', 'c', 'b', 'a']) {
      expect(find.text(name), findsOneWidget, reason: 'held row $name');
    }
    expect(_stack(session), hasLength(7), reason: 'nothing goes before Yes');

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-layer-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(_stack(session), ['under', 'over']);
  });

  testWidgets('a plain row\'s window has no list', (tester) async {
    final session = _session(_nested());
    session.selectLayer(const LayerId('over'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => deleteActiveLayerWithDialog(context, session),
              child: const Text('delete'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('over'), findsOneWidget);
    expect(
      find.textContaining(AppText.strings.deleteLayerHeldHeading),
      findsNothing,
    );
  });
}
