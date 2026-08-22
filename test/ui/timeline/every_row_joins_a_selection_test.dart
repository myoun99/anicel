import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🚨B4-3 (유저, 몇 번째인지 세지 않겠다고 했다) — **EVERY ROW JOINS A
/// SELECTION.**
///
/// > 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의 다른 행
/// > 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고. 몇번이나 말하는지
/// > 모르겠는데**」
///
/// ⚠️The span RESOLVER never had a rule about lanes — it is a plain slice of
/// the drawn row list, and it was already right. What was missing was
/// WIRING, in three places: a lane row that heads no fx chain got no drag
/// target at all, the one that DOES head a chain was handed `onCrossed` and
/// never `onSelectCrossed` (the only thing that grows a selection mid-drag),
/// and the x-sheet repeated both.
///
/// ⚠️A row-selection test that only ever builds LAYER rows cannot see any of
/// this. That is what the existing ones do, which is how the wiring stayed
/// missing while the file that owns the law stayed green.
void main() {
  const trackId = TrackId('fx-track');
  const layerA = LayerId('fx-a');
  const layerB = LayerId('fx-b');

  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('fx'),
        name: 'FX',
        createdAt: DateTime.utc(2026, 8, 22),
        tracks: [
          Track(
            id: trackId,
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: '1',
                duration: 8,
                canvasSize: const CanvasSize(width: 32, height: 32),
                layers: [
                  Layer(id: layerA, name: 'A', frames: const [], timeline: {}),
                  Layer(id: layerB, name: 'B', frames: const [], timeline: {}),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  /// A rail that twirls BOTH layers open — the shape the user is looking at
  /// and the shape no existing selection test builds.
  List<TimelineDisplayRow> railRows(EditorSessionManager s) {
    final rows = <TimelineDisplayRow>[];
    for (var index = 0; index < s.layers.length; index += 1) {
      final layer = s.layers[index];
      rows.add(TimelineDisplayRow.layer(layer, layerIndex: index));
      rows.add(
        TimelineDisplayRow.lane(
          layer,
          transformGroupHeaderLane,
          layerIndex: index,
        ),
      );
    }
    return rows;
  }

  /// The display indices of the fx rows — never a hard-coded count, because
  /// a cut's layer list is longer than the two this fixture names.
  List<int> laneIndices(List<TimelineDisplayRow> rows) => [
    for (var i = 0; i < rows.length; i += 1)
      if (rows[i].address is LaneRowAddress) i,
  ];

  test('the premise: more than one layer shows an fx row, with a layer row '
      'between them', () {
    final s = session();
    final rows = railRows(s);
    final lanes = laneIndices(rows);
    expect(
      lanes.length,
      greaterThanOrEqualTo(2),
      reason: 'two fx rows to span between',
    );
    expect(
      lanes[1] - lanes[0],
      greaterThanOrEqualTo(2),
      reason: 'and at least one ordinary row in between, which is the '
          'crossing the user could not make',
    );
  });

  test('a span anchored on one layer\'s fx row reaches the OTHER layer\'s '
      'fx row', () {
    final s = session();
    final rows = railRows(s);
    final lanes = laneIndices(rows);
    final from = lanes[0];
    final to = lanes[1];

    s.beginRowSelection(rows[from].address);
    s.updateRowSelection(rows, to - from);

    expect(
      s.rowSelection.value,
      [for (var i = from; i <= to; i += 1) rows[i].address],
      reason: '「행의 다른 fx끼리 넘어서 선택범위가 불가능」 — it must be. The '
          'span is a slice of the drawn rows, and nothing about a lane makes '
          'it a different kind of row to slice',
    );
  });

  test('and it reads the same way backwards', () {
    final s = session();
    final rows = railRows(s);
    final lanes = laneIndices(rows);
    final from = lanes[1];
    final to = lanes[0];

    s.beginRowSelection(rows[from].address);
    s.updateRowSelection(rows, to - from);

    expect(s.rowSelection.value, [
      for (var i = to; i <= from; i += 1) rows[i].address,
    ]);
  });

  test('a span that stops ON a lane keeps it — no snapping out to the layer', () {
    final s = session();
    final rows = railRows(s);
    final lane = laneIndices(rows).first;

    s.beginRowSelection(rows[lane - 1].address);
    s.updateRowSelection(rows, 1);

    expect(
      s.rowSelection.value,
      [rows[lane - 1].address, rows[lane].address],
      reason: 'the head is a lane and stays one — 「선택범위는 어떤 레이어를 '
          '건너든 자유롭게, 규칙 두지 말 것」',
    );
  });

  /// ⚠️Everything above passes WITHOUT the fix — the resolver was already
  /// right, and driving the session directly walks straight past the part
  /// that was broken. What follows is the part that was: both grids must
  /// hand every lane row a target that can grow a selection.
  ///
  /// 🚨This is why a green law file proved nothing. The gap was one hook
  /// not being passed, in a widget file no selection test opened.
  group('the WIRING, which the session-level tests cannot see', () {
    String source(String path) => File(path).readAsStringSync();

    for (final path in [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]) {
      test('$path hands a lane row a selection target', () {
        final text = source(path);
        expect(
          text,
          contains('LaneRowSubject('),
          reason: 'a lane row that heads no fx chain used to get NO drag '
              'target at all, so a span could neither start on it nor stop '
              'on it',
        );
        expect(
          RegExp(r'onSelectCrossed:').allMatches(text).length,
          greaterThanOrEqualTo(3),
          reason: 'the layer row had one; the fx CHAIN HEADER and the '
              'select-only lane each need their own. The header was handed '
              'onCrossed and never this — an unremarked omission, and the '
              'whole bug',
        );
      });
    }

    test('and the subject maps to the lane\'s own address', () {
      // ⚠️A5-3② moved this switch OUT of the timeline's host and beside the
      // subjects, because both rails have to give the same answer and a
      // surface with no way to name its subjects could not offer row
      // selection at all. This pin follows it rather than being deleted:
      // the arm it guards is the same arm, and it now guards it for every
      // rail at once instead of for one host.
      expect(
        source('lib/src/ui/timeline/layer_row_drag.dart'),
        contains('LaneRowSubject(:final layerId, :final laneId)'),
        reason: 'a select-only lane anchors where it is drawn; without this '
            'arm the switch would not compile, which is the point of a '
            'sealed subject',
      );
    });

    test('and BOTH rails reach that one map', () {
      // 🚨A5-3② — the storyboard passed null for the selection hooks, and
      // null means "this surface takes no part in row selection". The rail
      // that cannot name its subjects is the rail that skips the select
      // step, so naming and offering are pinned together.
      for (final path in [
        'lib/src/ui/timeline_tab_host.dart',
        'lib/src/ui/storyboard_tab_host.dart',
      ]) {
        expect(
          source(path),
          contains('timelineRowAddressOfDragSubject'),
          reason: '$path must reach the shared map, not keep its own',
        );
        expect(
          source(path),
          contains('isInRowSelection:'),
          reason: '$path must offer the select-first phase (A5-3②)',
        );
      }
    });
  });
}
