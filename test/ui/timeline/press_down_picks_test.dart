import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨D/T10 — **the press picks; the release clears.**
///
/// 유저 확정 2026-08-14: 「탭다운 하면 **먼저 기존 선택된거 삭제**하게 하면,
/// 바꾸면 선택삭제고 거기서 이동하면 선택 새로 추가니까 문제없을거같은데」 ·
/// 「**클릭하고 떼면 뭐든 비우게**」 · 「행이든 뭐든 동일하게」.
///
/// This file pins the half that decides everything else: **whether standing
/// clears.** The widget-level halves (which device acts on the down, and
/// that the release fires at all) live in
/// `instant_tap_settled_test` and `timeline_cell_select_replay_test`; what
/// is here is the law those two feed.
///
/// ⛔The guard is not a nicety. Measured: with clearing unconditional,
/// turning the press-pick on made an SE row move stop committing — the pick
/// wiped the very rows the move was about to carry.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  /// The default project's rows carry no cels, and a range selection does
  /// not need one — the span is about POSITIONS, not about what is drawn
  /// there. So this is simply the row the session is standing on.
  LayerRowAddress drawingRow() => LayerRowAddress(
    session.layers.firstWhere((layer) => layer.kind == LayerKind.animation).id,
  );

  test('standing OUTSIDE the selection clears it', () {
    final row = drawingRow();
    session.updateFrameRangeSelectionDrag(
      layerId: row.layerId,
      anchorIndex: 0,
      headIndex: 3,
    );
    expect(session.frameRangeSelection.value, isNotNull);

    // Frame 9 is past the span's last cell (0..3).
    session.standOnRow(row, frameIndex: 9);

    expect(
      session.frameRangeSelection.value,
      isNull,
      reason: '「바꾸면 선택삭제」 — the press moved you somewhere else',
    );
  });

  test('standing INSIDE the selection keeps it', () {
    final row = drawingRow();
    session.updateFrameRangeSelectionDrag(
      layerId: row.layerId,
      anchorIndex: 0,
      headIndex: 3,
    );

    session.standOnRow(row, frameIndex: 2);

    expect(
      session.frameRangeSelection.value,
      isNotNull,
      reason: 'that press is most likely the start of a MOVE, and clearing '
          'here is what stopped an SE row move from committing',
    );
  });

  test('the span BOUNDARY belongs to the selection', () {
    final row = drawingRow();
    session.updateFrameRangeSelectionDrag(
      layerId: row.layerId,
      anchorIndex: 0,
      headIndex: 3,
    );

    // The last covered cell, and the first uncovered one. A half-open range
    // read as closed (or the other way) would put the edge on the wrong
    // side, and the edge is where a move drag is most often grabbed.
    session.standOnRow(row, frameIndex: 3);
    expect(session.frameRangeSelection.value, isNotNull, reason: '3 is in');

    session.standOnRow(row, frameIndex: 4);
    expect(session.frameRangeSelection.value, isNull, reason: '4 is out');
  });

  test('a row that is itself selected keeps its selection', () {
    // The ROW axis asks the same question without a frame — and the rail
    // row reaches this verb through a callback that carries none, which is
    // why the frame argument has a playhead fallback rather than a null.
    final row = drawingRow();
    session.beginRowSelection(row);
    expect(session.rowSelection.value, [row]);

    session.standOnRow(row);

    expect(
      session.rowSelection.value,
      [row],
      reason: 'pressing a row you already selected does not drop it — the '
          'drag that press might become is the whole point of ⑨',
    );
  });

  test('a press with NO selection anywhere is simply a stand', () {
    final row = drawingRow();
    expect(session.frameRangeSelection.value, isNull);
    expect(session.rowSelection.value, isEmpty);

    session.standOnRow(row, frameIndex: 2);

    expect(session.currentFrameIndex, 2);
    expect(session.frameRangeSelection.value, isNull);
  });
}
