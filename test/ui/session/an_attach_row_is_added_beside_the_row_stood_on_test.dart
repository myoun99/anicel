import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/a_folder_made_by_hand.dart';
import '../../helpers/room_for_the_pills.dart';

/// 🗣️I-159 (유저 2026-11-04): 「아래/위의 어태치레이어 추가는 서있는걸
/// 기준으로. 지금 위의 어태치행에 서있어도 아래 어태치레이어 추가하면
/// 무조건 기준레이어의 밑에 생기는데, 서있는 어태치행을 기준으로 그 아래나
/// 위에 생기게하도록. 이름도 그에 맞춰서 재정렬」.
///
/// ★The row stood on — the base or a row riding it — is what the new row
/// stands beside, on the side pressed; and every default name reads its
/// seat, counted out from the base.
void main() {
  const above = AttachedPlacement.above;
  const below = AttachedPlacement.below;

  /// The base and two rows on each side, made as the user makes them:
  /// `[B-2, B-1, B, B+1, B+2]` up the stack. Stood on the base.
  (EditorSessionManager, Layer) fiveRows() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!;
    for (final side in AttachedPlacement.values) {
      s.selectLayer(base.id);
      s.folders.addAttachedLayer(side);
      s.folders.addAttachedLayer(side);
    }
    s.selectLayer(base.id);
    return (s, base);
  }

  List<Layer> groupOf(EditorSessionManager s, Layer base) =>
      attachedGroupSlice(base.id, s.requireActiveCut.layers);

  String named(Layer base, int seat) => seat == 0
      ? base.name
      : '${base.name}${seat > 0 ? '+' : '-'}${seat.abs()}';

  /// What the stack says: each row's name, its side and its folder.
  List<String> read(EditorSessionManager s, Layer base) => [
    for (final row in groupOf(s, base))
      '${row.name} ${row.attachedPlacement.name} ${row.folderId?.value}',
  ];

  test('⛔전제: the five rows stand in their seats\' names', () {
    final (s, base) = fiveRows();
    expect(
      [for (final row in groupOf(s, base)) row.name],
      [for (var seat = -2; seat <= 2; seat += 1) named(base, seat)],
    );
  });

  for (final mode in AttachedMode.values) {
    for (var stood = -2; stood <= 2; stood += 1) {
      for (final side in AttachedPlacement.values) {
        test('stood on seat $stood, ${side.name} (${mode.name}): the new row '
            'stands right ${side.name} it, and every name reads its seat', () {
          final (s, base) = fiveRows();
          final before = [for (final row in groupOf(s, base)) row.id];
          final stoodOn = groupOf(s, base)[stood + 2];
          s.selectLayer(stoodOn.id);
          final shown = read(s, base);

          s.folders.addAttachedLayer(side, mode: mode);

          final made = s.activeLayer!;
          final group = groupOf(s, base);
          final at = group.indexWhere((row) => row.id == made.id);
          final baseAt = group.indexWhere((row) => row.id == base.id);
          expect(
            [for (final row in group) row.id],
            [...before]..insert(
              before.indexOf(stoodOn.id) + (side == above ? 1 : 0),
              made.id,
            ),
            reason: '「서있는 어태치행을 기준으로 그 아래나 위에」',
          );
          expect(
            made.attachedPlacement,
            at > baseAt ? above : below,
            reason: 'the side of the base it stands on',
          );
          expect(made.attachedToLayerId, base.id);
          expect(made.attachedMode, mode);
          expect(
            [for (final row in group) row.name],
            [
              for (var i = 0; i < group.length; i += 1)
                named(base, i - baseAt),
            ],
            reason: '「이름도 그에 맞춰서 재정렬」',
          );

          s.undo();
          expect(read(s, base), shown, reason: 'one undo takes it all back');
          s.redo();
          expect(
            [for (final row in groupOf(s, base)) row.name],
            [for (final row in group) row.name],
            reason: 'and one redo brings it all again',
          );
        });
      }
    }
  }

  test('a name of the user\'s own stays as written, and the default ones '
      'around it read their seats', () {
    final (s, base) = fiveRows();
    final glow = groupOf(s, base)[3];
    s.layerVerbs.renameLayer(glow.id, 'glow');
    s.selectLayer(glow.id);

    s.folders.addAttachedLayer(below);

    expect([for (final row in groupOf(s, base)) row.name], [
      named(base, -2),
      named(base, -1),
      base.name,
      named(base, 1),
      'glow',
      named(base, 2),
    ]);
  });

  test('a gap a deleted row left is filled where the new row stands', () {
    final (s, base) = fiveRows();
    s.selectLayer(groupOf(s, base)[3].id);
    s.layerVerbs.deleteActiveLayer();
    expect(
      [for (final row in groupOf(s, base)) row.name],
      [named(base, -2), named(base, -1), base.name, named(base, 2)],
      reason: '⛔전제: B+1 is gone, and B+2 keeps its number',
    );
    s.selectLayer(groupOf(s, base).last.id);

    s.folders.addAttachedLayer(above);

    expect(
      [for (final row in groupOf(s, base)) row.name],
      [
        named(base, -2),
        named(base, -1),
        base.name,
        named(base, 1),
        named(base, 2),
      ],
      reason: 'the numbers the side wears, and the first free, by seat',
    );
  });

  group('a 공정 folder', () {
    /// `[B, B+1 in F, F, B+2]`: the row nearest the base filed in a folder
    /// of its own.
    (EditorSessionManager, Layer, LayerId) filed() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final base = s.activeLayer!;
      s.folders.addAttachedLayer(above);
      final first = s.activeLayerId!;
      s.folders.addAttachedLayer(above);
      s.selectLayer(first);
      final folder = groupTheActiveAttachIntoAFolder(s);
      expect(
        [for (final row in groupOf(s, base)) row.id],
        [base.id, first, folder, groupOf(s, base).last.id],
        reason: '⛔전제: the folder files the row nearest the base',
      );
      return (s, base, folder);
    }

    for (final side in AttachedPlacement.values) {
      test('stood on a row filed in it, ${side.name}: the new row is filed '
          'beside it', () {
        final (s, base, folder) = filed();
        final stood = groupOf(s, base)[1];
        s.selectLayer(stood.id);

        s.folders.addAttachedLayer(side);

        final made = s.activeLayer!;
        final layers = s.requireActiveCut.layers;
        expect(made.folderId, folder, reason: 'beside it is in its folder');
        expect(made.attachedPlacement, above);
        expect(
          layers.indexWhere((row) => row.id == made.id),
          layers.indexWhere((row) => row.id == stood.id) +
              (side == above ? 1 : -1),
        );
        expect(folderStructureProblem(layers), isNull);
      });
    }

    test('stood on the row past it, below: the new row stands between the '
        'folder and that row, in neither', () {
      final (s, base, folder) = filed();
      final stood = groupOf(s, base).last;
      s.selectLayer(stood.id);

      s.folders.addAttachedLayer(below);

      final made = s.activeLayer!;
      final group = groupOf(s, base);
      expect(made.folderId, stood.folderId);
      expect(group.indexWhere((row) => row.id == made.id), 3);
      expect(group[2].id, folder);
      expect(folderStructureProblem(s.requireActiveCut.layers), isNull);
    });
  });

  test('in a 겸용 cut, the cut beside it takes the row on the same seat, '
      'under the same names — and takes them back with the undo', () {
    final (s, base) = fiveRows();
    final source = s.requireActiveCut.id;
    s.cutVerbs.createLinkedCutFromActiveCut();
    final linked = s.requireActiveCut.id;
    List<String> stack(CutId cut) => [
      for (final row in s.repository
          .requireProject()
          .tracks
          .expand((track) => track.cuts)
          .singleWhere((each) => each.id == cut)
          .layers)
        row.name,
    ];
    final before = stack(source);
    expect(stack(linked), before, reason: '⛔전제: the two stacks read alike');
    s.selectCut(source);
    s.selectLayer(groupOf(s, base)[3].id);

    s.folders.addAttachedLayer(below);

    expect(stack(source), isNot(before), reason: 'LIVENESS: a row was made');
    expect(stack(linked), stack(source));
    s.undo();
    expect([stack(source), stack(linked)], [before, before]);
  });

  test('on a track\'s conte, every cut takes the row on the same seat, '
      'under the same names', () {
    Cut cutOf(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 12,
      canvasSize: const CanvasSize(width: 32, height: 32),
      layers: [
        Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
        Layer(
          id: LayerId('$id-conte'),
          name: 'Conte',
          kind: LayerKind.storyboard,
          frames: const [],
        ),
      ],
    );
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-beside'),
        name: 'Conte beside',
        createdAt: DateTime.utc(2026, 11, 4),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [cutOf('a'), cutOf('b')],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    List<List<String>> seats() => [
      for (final cut in s.repository.requireProject().tracks.single.cuts)
        [for (final seat in conteGroupOf(cut)) '${seat.seat} ${seat.row.name}'],
    ];
    s.selectCut(const CutId('a'));
    s.selectLayer(const LayerId('a-conte'));
    s.folders.addAttachedLayer(above);
    final first = s.activeLayerId!;
    s.folders.addAttachedLayer(above);
    expect(seats(), [
      for (final _ in ['a', 'b']) ['2 Conte+2', '1 Conte+1', '0 Conte'],
    ], reason: '⛔전제: both cuts wear the two rows');
    s.selectLayer(first);

    s.folders.addAttachedLayer(below);

    expect(seats(), [
      for (final _ in ['a', 'b'])
        ['3 Conte+3', '2 Conte+2', '1 Conte+1', '0 Conte'],
    ]);
    expect(
      conteGroupOf(
        s.requireActiveCut,
      ).singleWhere((each) => each.seat == 1).row.id,
      s.activeLayerId,
      reason: 'the row made stands on seat 1, between the conte and the '
          'row stood on',
    );
  });

  // The conte's ＋ menu hands the timeline's own row to the same verb
  // (`the_conte_row_attaches_as_the_timelines_row_does_test`).
  for (final (key, side, mode) in [
    ('add-layer-attach-above', above, AttachedMode.synced),
    ('add-layer-attach-below', below, AttachedMode.synced),
    ('add-layer-attach-free-above', above, AttachedMode.free),
    ('add-layer-attach-free-below', below, AttachedMode.free),
  ]) {
    testWidgets('the ＋ menu\'s $key, pressed on B+1, stands the row beside '
        'it', (tester) async {
      await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: createDefaultProject())),
      );
      await tester.pumpAndSettle();
      final s = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      final base = s.activeLayer!;
      s.folders.addAttachedLayer(above);
      final stood = s.activeLayer!;
      s.folders.addAttachedLayer(above);
      s.selectLayer(stood.id);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-toolbar-add-layer-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pumpAndSettle();

      final made = s.activeLayer!;
      final group = [for (final row in groupOf(s, base)) row.id];
      expect(made.id, isNot(stood.id), reason: 'LIVENESS: a row was made');
      expect(made.attachedMode, mode);
      expect(
        group.indexOf(made.id) - group.indexOf(stood.id),
        side == above ? 1 : -1,
      );
      expect([for (final row in groupOf(s, base)) row.name], [
        for (var seat = 0; seat <= 3; seat += 1) named(base, seat),
      ]);
    });
  }
}
