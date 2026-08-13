import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🚨T4 (유저 2026-08-13): 「선택된게 풀리는거, **어떤 행이든 액티브 바꾸면
/// 풀리도록.** 지금 레이어 액티브 바꾸면 풀리는데 **트랜스폼 멤버 행
/// 액티브로하면 안풀림**」.
///
/// The law was right and its ADDRESS was wrong: 「클릭하면 선택이 사라진다」
/// hung off the timeline host's `onSelectLayer` wrapper, so it covered the
/// doors that went through that wrapper and missed the ones calling the
/// session directly. Standing on a property lane was one of those.
///
/// ★A wrapper is a PLACE and every new door has to be told about it; a verb
/// cannot be walked around. So the test is not "the lane case works now" —
/// it is that EVERY kind of row address clears, one case per kind, which is
/// what keeps a fourth kind from quietly opting out.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);
  });

  /// A live row selection, made with the real verb — assigning
  /// `rowSelection.value` skips `claimSelection` and leaves the rest of the
  /// session behind.
  void selectARow() {
    session.beginRowSelection(LayerRowAddress(session.activeLayer!.id));
    session.endRowSelection();
    expect(session.rowSelection.value, isNotEmpty);
  }

  test('standing on a LAYER row clears', () {
    final layerId = session.activeLayer!.id;
    selectARow();
    session.standOnRow(LayerRowAddress(layerId));
    expect(session.rowSelection.value, isEmpty);
  });

  test('standing on a transform MEMBER lane clears — the case that did not', () {
    final layerId = session.activeLayer!.id;
    selectARow();

    session.standOnRow(
      LaneRowAddress(layerId, transformLaneDisplayOrder.first),
    );

    expect(
      session.rowSelection.value,
      isEmpty,
      reason: 'this is the report: 「트랜스폼 멤버 행 액티브로하면 안풀림」',
    );
    // And it really did stand there — a clear that also failed to move would
    // pass this test for the wrong reason.
    expect(session.currentRow, isA<LaneRowAddress>());
  });

  test('a CELL range selection goes the same way', () {
    final layerId = session.activeLayer!.id;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    session.updateFrameRangeSelectionDrag(
      layerId: layerId,
      anchorIndex: 0,
      headIndex: 0,
    );
    expect(session.frameRangeSelection.value, isNotNull);

    session.standOnRow(
      LaneRowAddress(layerId, transformLaneDisplayOrder.first),
    );

    expect(session.frameRangeSelection.value, isNull);
  });

  test('the storyboard stands without taking the layer active, and still '
      'clears', () {
    final layerId = session.activeLayer!.id;
    final activeBefore = session.activeLayerId;
    selectARow();

    session.standOnRow(
      LayerRowAddress(layerId),
      takesLayerActive: false,
    );

    expect(session.rowSelection.value, isEmpty);
    expect(
      session.activeLayerId,
      activeBefore,
      reason: 'the storyboard\'s standing row and its drawing target are two '
          'states (유저 2026-07-27) — the clearing law is what they share',
    );
  });
}
