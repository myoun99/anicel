import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';

/// 유저 확정 (2026-08-12): 「프레임셀은 다 똑같은 규칙으로 여러개 선택가능하도록.
/// 헤더니까 뭐 다르게한다거나 제발좀 절대로좀 그만좀하자.」
///
/// The span is the DISPLAY row list sliced — so these tests build rows the
/// way the rail does (a transition clone that no model walk would find, lane
/// rows, a group header) and assert that every one of them is spannable and
/// anchorable. That is the whole contract: seen ⇒ selectable.
Layer _layer(String id, LayerKind kind) =>
    Layer(id: LayerId(id), name: id, frames: const [], kind: kind);

PropertyLaneRow _lane(String id, {bool isGroupHeader = false}) =>
    PropertyLaneRow(
      laneId: id,
      label: id,
      keyedFrames: const {},
      isGroupHeader: isGroupHeader,
    );

/// The rail's row list for a cut holding one drawing layer with its transform
/// group open, plus the track-owned transition clone the rail inserts above
/// the camera. `cut.layers` contains NEITHER the clone nor any lane row.
List<TimelineDisplayRow> _railRows() {
  final a = _layer('A', LayerKind.animation);
  final transition = _layer('T', LayerKind.transition);
  final camera = _layer('CAM', LayerKind.camera);
  return [
    TimelineDisplayRow.layer(a, layerIndex: 0),
    TimelineDisplayRow.lane(a, _lane('transform', isGroupHeader: true),
        layerIndex: 0),
    TimelineDisplayRow.lane(a, _lane('position'), layerIndex: 0),
    TimelineDisplayRow.layer(transition, layerIndex: 1),
    TimelineDisplayRow.layer(camera, layerIndex: 2),
  ];
}

void main() {
  final rows = _railRows();
  final aRow = LayerRowAddress(LayerId('A'));
  final header = LaneRowAddress(LayerId('A'), 'transform');
  final position = LaneRowAddress(LayerId('A'), 'position');
  final transition = LayerRowAddress(LayerId('T'));
  final camera = LayerRowAddress(LayerId('CAM'));

  test('a display row states its own address — lanes and headers included', () {
    expect(rows.map((row) => row.address).toList(), [
      aRow,
      header,
      position,
      transition,
      camera,
    ]);
  });

  test('the span sweeps EVERY row it crosses — the header is not skipped', () {
    // 유저: 「레이어부터 포지션까지 선택하면 트랜스폼헤더만 선택범위에서 빠진다」.
    // The header sat between the layer domain and the lane domain and fell
    // through both; sliced off the drawn list it simply cannot.
    expect(resolveSelectionSpanRows(rows: rows, anchor: aRow, rowDelta: 2), [
      aRow,
      header,
      position,
    ]);
  });

  test('the TRANSITION row anchors a span, and it reaches other rows', () {
    // The symptom that opened this round: starting here collapsed the span
    // to one row, because the model walk it was matched against does not
    // contain the clone at all.
    expect(
      resolveSelectionSpanRows(rows: rows, anchor: transition, rowDelta: 1),
      [transition, camera],
    );
    expect(
      resolveSelectionSpanRows(rows: rows, anchor: transition, rowDelta: -3),
      [aRow, header, position, transition],
    );
  });

  test('a HEADER anchors a span too — no row kind is a second-class anchor', () {
    expect(resolveSelectionSpanRows(rows: rows, anchor: header, rowDelta: 2), [
      header,
      position,
      transition,
    ]);
  });

  test('an upward drag still reads in display order', () {
    // The selection is a run of rows on screen, not a direction of travel:
    // every consumer walks it top-to-bottom.
    expect(resolveSelectionSpanRows(rows: rows, anchor: camera, rowDelta: -2), [
      position,
      transition,
      camera,
    ]);
  });

  test('the delta clamps at the ends instead of dropping the span', () {
    expect(resolveSelectionSpanRows(rows: rows, anchor: aRow, rowDelta: 99), [
      aRow,
      header,
      position,
      transition,
      camera,
    ]);
    expect(resolveSelectionSpanRows(rows: rows, anchor: camera, rowDelta: -99), [
      aRow,
      header,
      position,
      transition,
      camera,
    ]);
  });

  test('an anchor that is NOT on screen is the one honest empty span', () {
    // A folded-away row: refusing here is right, because the drag never
    // started on anything the user can see.
    expect(
      resolveSelectionSpanRows(
        rows: rows,
        anchor: LayerRowAddress(LayerId('hidden')),
        rowDelta: 1,
      ),
      isEmpty,
    );
    expect(
      resolveSelectionSpanRows(rows: const [], anchor: aRow, rowDelta: 1),
      isEmpty,
    );
  });
}
