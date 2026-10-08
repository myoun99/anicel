import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_name_commands.dart';

/// 🚨F-303 (유저 2026-10-06): 「ui 공용 리스트화 사용안하는거 연결. 지금 레이어
/// 삭제시 아직도 하나하나 묻고있음. 여러 프레임 링크하는 창에서 쓰는 공용
/// 리스트창 그대로 사용해서 **아래 레이어 삭제할까요하고 리스트 보여주는
/// 것처럼** 하도록」.
///
/// The delete window named its rows INSIDE its sentence — 「레이어 "A, B, C"
/// 을(를) 삭제할까요?」 — and listed only what a folder among them held. It
/// asks ONE sentence now, and everything that goes stands in the shared
/// list under it: the rows named, a folder's rows, a base's attach rows.
///
/// The collaborator the list's contents come from — named so
/// `tool/mutation_run.dart` runs this file for it.
LayerVerbs rowsOf(EditorSessionManager session) => session.layerVerbs;

Layer _row(
  String id, {
  String? inside,
  String? rides,
  AttachedPlacement side = AttachedPlacement.above,
  LayerKind kind = LayerKind.animation,
}) => Layer(
  id: LayerId(id),
  name: id,
  kind: kind,
  folderId: inside == null ? null : LayerId(inside),
  attachedToLayerId: rides == null ? null : LayerId(rides),
  attachedPlacement: side,
  frames: const [],
  timeline: const {},
);

/// A cut whose rows are [layers], bottom → top.
EditorSessionManager _session(List<Layer> layers) {
  final session = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('f303'),
      name: 'F-303',
      createdAt: DateTime.utc(2026, 10, 7),
      tracks: [
        Track(
          id: const TrackId('f303-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('f303-cut'),
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

/// x · a base with a rider on each side · y · z, bottom → top.
List<Layer> _withABase() => [
  _row('x'),
  _row('under', rides: 'base', side: AttachedPlacement.below),
  _row('base'),
  _row('over', rides: 'base'),
  _row('y'),
  _row('z'),
];

List<String> _stack(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.animation || layer.kind.groupsLayers)
      layer.id.value,
];

void _select(EditorSessionManager session, List<String> ids) {
  session.rowSelectionVerbs.beginRowSelection(
    LayerRowAddress(LayerId(ids.first)),
  );
  session.rowSelectionVerbs.rowSelection.value = [
    for (final id in ids) LayerRowAddress(LayerId(id)),
  ];
}

Future<void> _pressDelete(
  WidgetTester tester,
  EditorSessionManager session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => deleteRowSelectionWithDialog(context, session),
            child: const Text('delete'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('delete'));
  await tester.pumpAndSettle();
}

void main() {
  group('what a delete takes along', () {
    test('a base takes its attach rows, top first', () {
      final session = _session(_withABase());

      expect(
        [
          for (final row in rowsOf(session).rowsHeldBy([const LayerId('base')]))
            row.id.value,
        ],
        ['over', 'under'],
        reason: '↩️only a FOLDER\'s rows were held: a base went and took '
            'rows the list never showed',
      );
      expect(rowsOf(session).rowsHeldBy([const LayerId('x')]), isEmpty);
    });

    test('and the folder that organizes them', () {
      final session = _session([
        _row('base'),
        _row('r', rides: 'base', inside: 'ORG'),
        _row('ORG', kind: LayerKind.folder),
        _row('y'),
      ]);

      expect(
        [
          for (final row in rowsOf(session).rowsHeldBy([const LayerId('base')]))
            row.id.value,
        ],
        ['ORG', 'r'],
      );
    });

    test('a row named beside what it holds is not listed twice', () {
      final session = _session(_withABase());

      expect(
        [
          for (final row in rowsOf(session).rowsHeldBy([
            const LayerId('base'),
            const LayerId('over'),
          ]))
            row.id.value,
        ],
        ['under'],
      );
    });

    test('one undo brings back the rows named and the rows they took', () {
      final session = _session(_withABase());
      _select(session, ['x', 'base']);

      rowsOf(session).deleteSelectedLayers();
      expect(_stack(session), ['y', 'z'], reason: '⛔전제');
      session.undo();

      expect(_stack(session), ['x', 'under', 'base', 'over', 'y', 'z']);
    });

    test('the hand-off stands on a row that STAYS', () {
      // ↩️It stood on `over` — the row that takes the base's index — which
      // goes with the base.
      final session = _session(_withABase());
      _select(session, ['base']);

      rowsOf(session).deleteSelectedLayers();

      expect(_stack(session), ['x', 'y', 'z']);
      expect(session.activeLayerId, const LayerId('y'));
    });
  });

  testWidgets('several rows are asked about ONCE: one sentence, and '
      'everything that goes listed under it as the rail lists it', (
    tester,
  ) async {
    final session = _session(_withABase());
    // Selected in no order at all.
    _select(session, ['x', 'z', 'base']);
    final steps = session.historyManager.undoCount;

    await _pressDelete(tester, session);

    final strings = AppText.strings;
    expect(find.text(strings.deleteLayersMessage), findsOneWidget);
    expect(
      find.text('${strings.deleteLayersHeading} (5)'),
      findsOneWidget,
      reason: 'the three named, and the two rows the base takes along',
    );
    final listed = ['z', 'over', 'base', 'under', 'x'];
    for (final name in listed) {
      expect(find.text(name), findsOneWidget, reason: 'row $name');
    }
    expect(find.text('y'), findsNothing, reason: 'y stays');
    final tops = [
      for (final name in listed) tester.getTopLeft(find.text(name)).dy,
    ];
    expect(
      tops,
      [...tops]..sort(),
      reason: 'top first, as the rail lists them — not the order selected',
    );
    expect(_stack(session), hasLength(6), reason: 'nothing goes before Yes');

    await tester.tap(
      find.byKey(const ValueKey<String>('delete-layer-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(_stack(session), ['y']);
    expect(
      find.text(strings.deleteLayersMessage),
      findsNothing,
      reason: 'asked once — no second window for the next row',
    );
    expect(session.historyManager.undoCount, steps + 1, reason: 'ONE step');
  });

  testWidgets('declining leaves every row where it was', (tester) async {
    final session = _session(_withABase());
    _select(session, ['x', 'z']);

    await _pressDelete(tester, session);
    await tester.tap(
      find.byKey(const ValueKey<String>('delete-layer-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(_stack(session), ['x', 'under', 'base', 'over', 'y', 'z']);
  });
}
