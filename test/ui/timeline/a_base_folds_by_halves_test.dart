import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:anicel/src/models/track_conte.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';

import '../../helpers/a_folder_made_by_hand.dart';
import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️I-175 (유저 2026-11-15): 「레이어의 어태치 접기/펼치기버튼을 위아래로
/// 나눠서 위 펼치기 아래 펼치기 이렇게 두개 두고싶음. 위에만 어태치있으면
/// 아래쪽은 비어있고. 그리고 내부 비지블 상황이 반영되게하고싶음」, and the
/// same evening: 「펼치기버튼은 그걸 기본으로 하고싶으니까(fx펼치기는 제외)
/// … 폴더 비지블off시키면 해당 버튼 비활성화색으로」.
///
/// The answers: Q1 (가) the colour speaks folded or open · Q2 (나) a
/// folder's twirl by the folder's own eye · Q3 (가) a half pressed across
/// a selection folds that side of every base, and the folders too · Q4 (나)
/// an open half points at its side, the sheet's turned a quarter · Q5 (가)
/// a folder's twirl folds a selected base on both sides, as before.
void main() {
  group('the press', () {
    test('a half folds the rows on its side, and only them', () {
      final r = _Rig();

      r.press(r.a, AttachedPlacement.above);
      expect(r.away(), {r.aAbove});
      expect(r.sides(r.a), {AttachedPlacement.above});

      r.press(r.a, AttachedPlacement.below);
      expect(r.away(), {r.aAbove, r.aBelow});

      r.press(r.a, AttachedPlacement.above);
      expect(r.away(), {r.aBelow}, reason: 'the upper half opens alone');
      expect(r.sides(r.a), {AttachedPlacement.below});
    });

    test('🚨Q3: a half pressed in the selection folds that side of every '
        'selected base, and every selected folder — as one undo', () {
      final r = _Rig();
      r.select([r.a, r.b, r.folder]);
      final depth = r.s.historyManager.undoCount;

      r.press(r.a, AttachedPlacement.above);

      expect(r.away(), {r.aAbove, r.bAbove}, reason: '「누른 반쪽은 같은 쪽」');
      expect(r.folderShut(), isTrue, reason: '「폴더도 접힌다」');
      expect(r.s.historyManager.undoCount, depth + 1);

      r.s.undo();
      expect(r.away(), isEmpty);
      expect(r.folderShut(), isFalse);
    });

    test('Q3: the press SETS what the pressed half turns to — a selected '
        'base whose side was folded already stays folded', () {
      final r = _Rig();
      r.press(r.b, AttachedPlacement.above);
      r.select([r.a, r.b]);

      r.press(r.a, AttachedPlacement.above);

      expect(r.away(), {r.aAbove, r.bAbove});
    });

    test('🚨Q5: a folder\'s twirl folds a selected base on both sides', () {
      final r = _Rig();
      r.select([r.folder, r.a]);

      r.press(r.folder, null);

      expect(r.folderShut(), isTrue);
      expect(r.away(), {r.aAbove, r.aBelow});
      expect(r.sides(r.a), AttachedPlacement.values.toSet());
    });

    test('a fold hands the stand on only when it hides the row stood on', () {
      final r = _Rig();
      r.s.selectLayer(r.aBelow);

      r.press(r.a, AttachedPlacement.above);
      expect(r.s.activeLayerId, r.aBelow, reason: 'its side is still shown');

      r.press(r.a, AttachedPlacement.below);
      expect(r.s.activeLayerId, r.a, reason: 'handed to the base');
    });

    test('a walk onto a folded row opens its side, and no other', () {
      final r = _Rig();
      r.press(r.a, AttachedPlacement.above);
      r.press(r.a, AttachedPlacement.below);

      r.s.standing.standOn((cut: r.cut, layer: r.aBelow, frame: 0));

      expect(r.s.activeLayerId, r.aBelow);
      expect(r.sides(r.a), {AttachedPlacement.above});
      expect(r.away(), {r.aAbove});
    });
  });

  group('the file', () {
    test('a row keeps its folded sides — and says nothing while none is', () {
      final row = Layer(id: const LayerId('r'), name: 'r', frames: const []);
      expect(row.toJson().containsKey('foldedAttaches'), isFalse);

      final folded = row.copyWith(foldedAttaches: {AttachedPlacement.below});
      final read = Layer.fromJson(folded.toJson());
      expect(read.foldedAttaches, {AttachedPlacement.below});
      expect(read, folded);
    });

    test('a conte head wears the folded sides it carries', () {
      final row = Layer(
        id: const LayerId('r'),
        name: 'r',
        frames: const [],
        foldedAttaches: {AttachedPlacement.above},
      );
      final head = ConteHead.of(row);
      expect(head.foldedAttaches, {AttachedPlacement.above});
      expect(ConteHead.fromJson(head.toJson()), head);
      expect(
        head.wornBy(row.copyWith(foldedAttaches: const {})).foldedAttaches,
        {AttachedPlacement.above},
      );
      expect(
        head.editedBy(row, row.copyWith(foldedAttaches: const {})),
        isNot(head),
        reason: 'a fold the row changed reaches its head',
      );
    });
  });

  group('the halves on the rail', () {
    tearDown(debugClearValueControlPointers);

    testWidgets('🚨Q4: open, a half points at its side — ▴ above, ▾ below — '
        'and shut it is ▸; a side with no rows is an empty place', (
      tester,
    ) async {
      await _pump(tester);

      expect(_icon(tester, 'above', 'b'), Icons.arrow_drop_up);
      expect(_icon(tester, 'below', 'b'), Icons.arrow_drop_down);
      expect(
        tester.getCenter(_half('above', 'b')).dy,
        lessThan(tester.getCenter(_half('below', 'b')).dy),
        reason: '「위 펼치기 아래 펼치기」 — the upper half folds the rows above',
      );

      await tester.tap(_half('above', 'b'));
      await tester.pumpAndSettle();
      expect(_icon(tester, 'above', 'b'), Icons.arrow_right);
      expect(_icon(tester, 'below', 'b'), Icons.arrow_drop_down);
      expect(_rowOf('b+1'), findsNothing);
      expect(_rowOf('b-1'), findsOneWidget);

      expect(_half('above', 'o'), findsOneWidget);
      expect(_half('below', 'o'), findsNothing, reason: '「아래쪽은 비어있고」');
      double fromItsRow(String side, String base) =>
          tester.getRect(_half(side, base)).top -
          tester.getRect(_rowOf(base)).top;
      expect(
        fromItsRow('above', 'o'),
        fromItsRow('above', 'b'),
        reason: '⛔없다가 생기는 UI 금지 — the empty half keeps its place',
      );
    });

    testWidgets('🚨a half says in colour whether a row on its side shows — '
        'the base\'s own eye is not asked', (tester) async {
      final session = await _pump(tester);
      final lit = tester.glyphInkOf(_half('above', 'b'));
      expect(tester.glyphInkOf(_half('below', 'b')), lit, reason: '⛔전제');

      await _eye(tester, session, 'b+1');
      final off = tester.glyphInkOf(_half('above', 'b'));
      expect(off, isNot(lit), reason: '「진짜 아무것도 안보이는 상황」');
      expect(off!.a, closeTo(AppColors.offAlpha, 0.01));
      expect(tester.glyphInkOf(_half('below', 'b')), lit, reason: 'its side');

      await _eye(tester, session, 'b');
      expect(
        tester.glyphInkOf(_half('below', 'b')),
        lit,
        reason: 'a base\'s eye hides no rider (UI-R24 #5): b-1 still shows',
      );

      await _eye(tester, session, 'b+1');
      expect(tester.glyphInkOf(_half('above', 'b')), lit, reason: 'back on');
    });

    testWidgets('🚨Q1: folded, a half still says in colour whether a row on '
        'its side shows', (tester) async {
      final session = await _pump(tester);
      final lit = tester.glyphInkOf(_half('above', 'o'));
      await tester.tap(_half('above', 'o'));
      await tester.pumpAndSettle();
      expect(tester.glyphInkOf(_half('above', 'o')), lit, reason: '⛔전제');

      await _eye(tester, session, 'o+1');

      expect(tester.glyphInkOf(_half('above', 'o')), isNot(lit));
    });

    testWidgets('🚨Q2: a folder\'s twirl by the folder\'s own eye — not the '
        'rows inside it', (tester) async {
      final session = await _pump(tester);
      final lit = tester.glyphInkOf(_folderTwirl);

      await _eye(tester, session, 'm');
      expect(tester.glyphInkOf(_folderTwirl), lit, reason: '「폴더는 … 괜찮음」');

      await _eye(tester, session, 'f');
      expect(
        tester.glyphInkOf(_folderTwirl),
        isNot(lit),
        reason: '「눈이 꺼져있는데 안이 보이는상황이 문제」',
      );
    });

    testWidgets('⛔the lanes\' twirl keeps its colour — 「fx펼치기는 제외」', (
      tester,
    ) async {
      final session = await _pump(tester);
      final lanes = find.named('timeline-lane-toggle-c');
      expect(lanes, findsOneWidget, reason: '⛔전제: the row has lanes');
      final lit = tester.glyphInkOf(lanes);

      await _eye(tester, session, 'c');

      expect(tester.glyphInkOf(lanes), lit);
    });

    testWidgets('🚨Q4: the sheet\'s halves are the rail\'s turned a quarter — '
        'the upper on the side the sheet sets the rows above', (
      tester,
    ) async {
      await _pump(tester, orientation: TimelineOrientation.vertical);
      Rect at(String name) => tester.getRect(find.named(name));
      final above = at('xsheet-attach-twirl-above-b');
      final below = at('xsheet-attach-twirl-below-b');

      expect(above.center.dy, closeTo(below.center.dy, 0.01));
      expect(
        above.center.dx < below.center.dx,
        at('xsheet-layer-name-b+1').center.dx <
            at('xsheet-layer-name-b').center.dx,
        reason: 'each half on the side of the columns it folds',
      );
      expect(
        tester
            .widget<RotatedBox>(
              find
                  .ancestor(
                    of: find.named('xsheet-attach-twirl-above-b'),
                    matching: find.byType(RotatedBox),
                  )
                  .first,
            )
            .quarterTurns,
        1,
        reason: '「90도 회전」 — the glyph turns with it',
      );
    });
  });

  group('the sweep', () {
    tearDown(debugClearValueControlPointers);

    testWidgets('🚨Q3: a sweep from a half folds that side of the bases it '
        'crosses, and the folders', (tester) async {
      final session = await _pump(tester);

      await _sweep(tester, _half('below', 'b'), _folderTwirl);

      expect(_sides(session, 'b'), {AttachedPlacement.below});
      expect(_row(session, 'f').collapsed, isTrue);
    });

    testWidgets('🚨Q3: a sweep from a half folds only that side of a base it '
        'crosses — one holding rows on both sides keeps the other', (
      tester,
    ) async {
      final session = await _pump(tester);

      await _sweep(tester, _half('above', 'o'), _half('above', 'b'));

      expect(_sides(session, 'o'), {AttachedPlacement.above});
      expect(_sides(session, 'b'), {AttachedPlacement.above});
      expect(_rowOf('b-1'), findsOneWidget, reason: 'its side stays open');
    });

    testWidgets('🚨Q5: a sweep from a folder\'s twirl folds the bases it '
        'crosses on every side they have rows on', (tester) async {
      final session = await _pump(tester);

      await _sweep(tester, _folderTwirl, _half('above', 'o'));

      expect(_row(session, 'f').collapsed, isTrue);
      expect(_sides(session, 'b'), AttachedPlacement.values.toSet());
      expect(_sides(session, 'o'), {AttachedPlacement.above});
    });
  });
}

/// A cut of two bases with riders on both sides and a folder holding a
/// cel, stood on the first base.
class _Rig {
  _Rig() : s = EditorSessionManager(initialProject: createDefaultProject()) {
    addTearDown(s.dispose);
    cut = s.requireActiveCut.id;
    a = s.layers.firstWhere((layer) => layer.kind == LayerKind.animation).id;
    b = _added();
    final filed = _added();
    for (final base in [a, b]) {
      for (final side in AttachedPlacement.values) {
        s.selectLayer(base);
        s.folders.addAttachedLayer(side);
      }
    }
    s.selectLayer(filed);
    groupTheActiveRowIntoAFolder(s);
    folder = s.requireActiveCut.layers.folderLayers.single.id;
    s.selectLayer(a);
    expect(away(), isEmpty, reason: '⛔전제: everything open');
  }

  final EditorSessionManager s;
  late final CutId cut;
  late final LayerId a;
  late final LayerId b;
  late final LayerId folder;

  LayerId get aAbove => _rider(a, AttachedPlacement.above);
  LayerId get aBelow => _rider(a, AttachedPlacement.below);
  LayerId get bAbove => _rider(b, AttachedPlacement.above);

  LayerId _rider(LayerId base, AttachedPlacement side) => s.layers
      .firstWhere(
        (layer) =>
            layer.attachedToLayerId == base && layer.attachedPlacement == side,
      )
      .id;

  LayerId _added() {
    final before = {for (final layer in s.layers) layer.id};
    s.layerStack.addLayerOfKind(LayerKind.animation);
    return s.layers.firstWhere((layer) => !before.contains(layer.id)).id;
  }

  void press(LayerId row, AttachedPlacement? side) =>
      SessionRowButtonPresses(s).toggleGroupFold(row, side);

  void select(List<LayerId> ids) =>
      s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

  Set<LayerId> away() => s.railView.attachFoldedRowIds.value;

  Set<AttachedPlacement> sides(LayerId id) =>
      requireLayerAnywhere(s.repository.requireProject(), id).foldedAttaches;

  bool folderShut() =>
      requireLayerAnywhere(s.repository.requireProject(), folder).collapsed;
}

/// Rail top to bottom: c · o+1 · o · b+1 · b · b-1 · f · m — a base with
/// a rider each side, one with a rider above only, a folder with a cel.
Project _film() {
  Layer row(
    String id, {
    String? rides,
    AttachedPlacement side = AttachedPlacement.above,
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    attachedToLayerId: rides == null ? null : LayerId(rides),
    attachedPlacement: side,
    folderId: folder == null ? null : LayerId(folder),
  );
  return Project(
    id: const ProjectId('halves'),
    name: 'Halves',
    createdAt: DateTime.utc(2026, 11, 16),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              row('m', folder: 'f'),
              createFolderLayer(id: const LayerId('f'), name: 'f'),
              row('b-1', rides: 'b', side: AttachedPlacement.below),
              row('b'),
              row('b+1', rides: 'b'),
              row('o'),
              row('o+1', rides: 'o'),
              row('c'),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<EditorSessionManager> _pump(
  WidgetTester tester, {
  TimelineOrientation orientation = TimelineOrientation.horizontal,
}) => pumpTimelineHost(
  tester,
  _film(),
  surface: const Size(1400, 700),
  orientation: orientation,
);

Finder _half(String side, String base) =>
    find.named('timeline-attach-twirl-$side-$base');

final Finder _folderTwirl = find.named('timeline-folder-twirl-f');

Finder _rowOf(String id) => find.named('timeline-layer-row-$id');

IconData? _icon(WidgetTester tester, String side, String base) =>
    tester.appIconButton(_half(side, base)).icon;

Layer _row(EditorSessionManager session, String id) =>
    requireLayerAnywhere(session.repository.requireProject(), LayerId(id));

Set<AttachedPlacement> _sides(EditorSessionManager session, String id) =>
    _row(session, id).foldedAttaches;

/// Flips [id]'s eye as its button does, the selection empty.
Future<void> _eye(
  WidgetTester tester,
  EditorSessionManager session,
  String id,
) async {
  SessionRowButtonPresses(session).toggleVisibility(LayerId(id));
  await tester.pumpAndSettle();
}

/// Presses [from] and drags to where [to] stands after the press moved it.
Future<void> _sweep(WidgetTester tester, Finder from, Finder to) async {
  final start = tester.getCenter(from);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  final end = tester.getCenter(to);
  for (var step = 1; step <= 8; step += 1) {
    await gesture.moveTo(Offset.lerp(start, end, step / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}
