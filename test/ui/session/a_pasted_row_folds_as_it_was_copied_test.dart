import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/clipboard/layer_copy_payload.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🗣️F-579 (유저 2026-11-10): 「폴더 복사해서 붙여넣을때, 접어둔 폴더
/// 복사한건데 펼친채로 붙여넣어지니까 제대로 상태 기억해서 복사하도록」.
///
/// How the rail is laid out around a row — its group fold, its twirl-down
/// and the lane groups open in it ([Layer.foldsLike]) — is the row's own
/// (F-360), so its copy's. Every door a copy lands through keeps it: the
/// independent paste, the paste after a 잘라내기, and the linked paste,
/// which lands a folder as the independent one does (F-532-Q2) and every
/// other row as a linked copy of it.
void main() {
  TimelineToolbarPanelContext pill(EditorSessionManager s) =>
      TimelineToolbarPanelContext(s);

  Layer row(
    String id, {
    String? inside,
    LayerKind kind = LayerKind.animation,
  }) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    folderId: inside == null ? null : LayerId(inside),
    frames: const [],
    timeline: const {},
  );

  /// Bottom → top:
  ///
  ///     over
  ///     F ─┬─ G ─── c
  ///        └─ a
  ///     under
  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('f579'),
        name: 'F-579',
        createdAt: DateTime.utc(2026, 11, 11),
        tracks: [
          Track(
            id: const TrackId('f579-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('c1'),
                name: 'c1',
                duration: 24,
                canvasSize: const CanvasSize(width: 320, height: 180),
                layers: [
                  row('under'),
                  row('a', inside: 'F'),
                  row('c', inside: 'G'),
                  row('G', inside: 'F', kind: LayerKind.folder),
                  row('F', kind: LayerKind.folder),
                  row('over'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  void select(EditorSessionManager s, String id) =>
      s.rowSelection.value = [LayerRowAddress(LayerId(id))];

  /// The rows of the cut named [name], bottom → top — the original first.
  List<Layer> named(EditorSessionManager s, String name) => [
    for (final layer in s.requireActiveCut.layers)
      if (layer.name == name) layer,
  ];

  /// [name]'s copy: the row of that name that is not the original.
  Layer copyOf(EditorSessionManager s, String name) {
    final rows = named(s, name);
    expect(rows, hasLength(2), reason: 'the original and its copy');
    return rows.firstWhere((layer) => layer.id != LayerId(name));
  }

  String transform() => transformGroupHeaderLane.laneId;

  /// F folded shut, G (inside it) left open, and `a` twirled down with its
  /// Transform group open.
  void foldAndTwirl(EditorSessionManager s) {
    s.folders.toggleLayerCollapsed(const LayerId('F'));
    s.layerSwitches.toggleLayerLanes(const LayerId('a'));
    s.layerSwitches.setLayerLaneGroupExpanded(
      const LayerId('a'),
      transform(),
      expanded: true,
    );
    final rows = s.requireActiveCut.layers;
    expect(rows.byId(const LayerId('F'))!.collapsed, isTrue, reason: 'CONTROL');
    expect(rows.byId(const LayerId('G'))!.collapsed, isFalse, reason: 'CONTROL');
    expect(rows.byId(const LayerId('a'))!.lanesExpanded, isTrue);
    expect(rows.byId(const LayerId('a'))!.expandedLaneGroups, {transform()});
  }

  void expectFoldedAsCopied(EditorSessionManager s) {
    expect(copyOf(s, 'F').collapsed, isTrue, reason: '🎯the folder folded');
    expect(copyOf(s, 'G').collapsed, isFalse, reason: 'its open one open');
    final a = copyOf(s, 'a');
    expect(a.lanesExpanded, isTrue, reason: 'the twirl down');
    expect(a.expandedLaneGroups, {transform()}, reason: 'its groups open');
    expect(copyOf(s, 'c').foldsLike(named(s, 'c').first), isTrue);
  }

  test('🎯a folded folder pastes folded, each row inside as it was', () {
    final s = sessionOf();
    foldAndTwirl(s);
    select(s, 'F');
    pill(s).copyFrame();

    s.selectLayer(const LayerId('over'));
    pill(s).pasteIndependentFrame();

    expectFoldedAsCopied(s);
  });

  test('a row pasted open stays open — the copy is the row, not a rule', () {
    final s = sessionOf();
    select(s, 'F');
    pill(s).copyFrame();

    s.selectLayer(const LayerId('over'));
    pill(s).pasteIndependentFrame();

    expect(copyOf(s, 'F').collapsed, isFalse);
    expect(copyOf(s, 'a').lanesExpanded, isFalse);
  });

  test('the paste after a 잘라내기 puts it back folded', () {
    final s = sessionOf();
    foldAndTwirl(s);
    select(s, 'F');
    pill(s).cutRun();
    expect(named(s, 'F'), isEmpty, reason: 'CONTROL: it went');

    s.selectLayer(const LayerId('over'));
    pill(s).pasteIndependentFrame();

    expect(named(s, 'F').single.collapsed, isTrue);
    expect(named(s, 'G').single.collapsed, isFalse);
    expect(named(s, 'a').single.lanesExpanded, isTrue);
    expect(named(s, 'a').single.expandedLaneGroups, {transform()});
  });

  test('the linked paste lands it folded too (F-532-Q2)', () {
    final s = sessionOf();
    foldAndTwirl(s);
    select(s, 'F');
    pill(s).copyFrame();

    s.selectLayer(const LayerId('over'));
    expect(pill(s).canPasteLinkedFrame, isTrue, reason: 'CONTROL');
    pill(s).pasteLinkedFrame();

    expectFoldedAsCopied(s);
  });

  // The payload re-spelled — how a paste into another project writes its
  // terms (I-7), and how a conte rider lands with no base under it — is
  // the payload still: it folds as the row did.
  test('a payload re-spelled keeps the fold and the twirl', () {
    final source = row('F', kind: LayerKind.folder).copyWith(
      collapsed: true,
      lanesExpanded: true,
      expandedLaneGroups: {transform()},
    );

    final respelled = copyLayerToPayload(
      source,
    ).copyWith(kind: LayerKind.animation, timeline: const {});

    expect(respelled.collapsed, isTrue);
    expect(respelled.lanesExpanded, isTrue);
    expect(respelled.expandedLaneGroups, {transform()});
  });

  test('a twirled row alone, pasted either way, twirls as it did', () {
    for (final linked in [false, true]) {
      final s = sessionOf();
      foldAndTwirl(s);
      select(s, 'a');
      pill(s).copyFrame();

      s.selectLayer(const LayerId('over'));
      linked ? pill(s).pasteLinkedFrame() : pill(s).pasteIndependentFrame();

      final a = copyOf(s, 'a');
      expect(a.lanesExpanded, isTrue, reason: 'linked: $linked');
      expect(a.expandedLaneGroups, {transform()}, reason: 'linked: $linked');
    }
  });
}
