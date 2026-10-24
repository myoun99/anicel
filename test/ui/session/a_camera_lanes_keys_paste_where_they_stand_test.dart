import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames;

/// F-388 on the CAMERA row (관제 10-22: the Surface's run copied the
/// camera's position lane over 1–8, stood on 4 and pasted — and nothing
/// came). The camera's keys live on the cut's camera, not on its row, and
/// inside its cut: 🗣️F-388-Q3 (유저 2026-10-22) 「끝 키는 끝에 남고, 밖으로
/// 밀린 나머지는 버린다」.
void main() {
  late EditorSessionManager s;
  late Layer camera;
  late ToolbarPanelContext pill;
  late int last;

  setUp(() {
    s = EditorSessionManager(initialProject: createDefaultProject());
    camera = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.camera,
    );
    s.selectLayer(camera.id);
    pill = TimelineToolbarPanelContext(s);
    last = s.requireActiveCut.duration - 1;
    expect(last, greaterThan(20), reason: '⛔전제: room past the copy');
  });
  tearDown(() => s.dispose());

  Set<int> keys() =>
      transformLaneKeyFrames(s.requireActiveCut.camera.track, 'position');

  CanvasPoint? at(int frame) =>
      s.requireActiveCut.camera.track.position.keys[frame]?.value;

  void standOn(int at, Layer row) {
    s.selectFrameIndex(at);
    s.standOnRow(LaneRowAddress(row.id, 'position'));
  }

  void keyAt(int frame, Layer row) {
    standOn(frame, row);
    expect(s.cellInstances.createInstancesForSelection(), isTrue);
  }

  /// The camera keyed at [frame] to a place of its own.
  void typed(int frame, String place) => s.laneVerbs.setLaneValueAt(
    camera.id,
    'position',
    frame,
    place,
    frameIsGlobal: false,
    description: 'Type',
    scaleLinked: false,
  );

  void select(Layer row, int start, int endExclusive) {
    standOn(start, row);
    s.laneRangeSelection.value = TimelineLaneSelection(
      layerId: row.id,
      laneId: 'position',
      startIndex: start,
      endIndexExclusive: endExclusive,
    );
  }

  /// [row]'s position lane copied over 1–8 — its keys there on 0, 4 and 7
  /// of the copy — and nothing selected after.
  void copyOneToEight(Layer row) {
    select(row, 1, 9);
    pill.copyFrame();
    expect(s.keyClipboard.holdsKeys, isTrue, reason: '⛔전제');
    s.laneRangeSelection.value = null;
  }

  test('a band copied off the camera\'s position lane goes in where the '
      'lane is stood on, the keys after it moved back', () {
    for (final frame in [1, 5, 8, 12]) {
      keyAt(frame, camera);
    }
    expect(keys(), {1, 5, 8, 12}, reason: '⛔전제');
    copyOneToEight(camera);
    standOn(4, camera);

    expect(pill.canPasteIndependentFrame, isTrue, reason: '⛔전제');
    pill.pasteIndependentFrame();

    expect(keys(), {1, 4, 8, 11, 13, 16, 20});
  });

  test('🚨keys pushed past the cut\'s end go — but the end key stays on the '
      'end, against a key pushed onto it too', () {
    for (final frame in [1, 5, 8, last - 2]) {
      keyAt(frame, camera);
    }
    typed(last - 8, '100, 100');
    typed(last, '300, 200');
    final end = at(last);
    expect(at(last - 8), isNot(end), reason: '⛔전제');
    copyOneToEight(camera);
    standOn(4, camera);

    expect(pill.canPasteIndependentFrame, isTrue);
    expect(pill.canPasteLinkedFrame, isFalse, reason: 'no names to keep');
    pill.pasteIndependentFrame();

    expect(keys(), {1, 4, 8, 11, 13, 16, last});
    expect(at(last), end);
  });

  test('a key pushed past the end goes where no key holds the end', () {
    for (final frame in [1, 5, 8, last - 2]) {
      keyAt(frame, camera);
    }
    copyOneToEight(camera);
    standOn(4, camera);
    pill.pasteIndependentFrame();

    expect(keys(), {1, 4, 8, 11, 13, 16});
  });

  test('a pasted key past the end goes too', () {
    for (final frame in [1, 5, 8]) {
      keyAt(frame, camera);
    }
    typed(last, '300, 200');
    final end = at(last);
    copyOneToEight(camera);
    standOn(last - 3, camera);
    pill.pasteIndependentFrame();

    expect(keys(), {1, 5, 8, last - 3, last});
    expect(at(last), end);
  });

  test('stood on the end key, a paste lands nothing — both buttons dark, '
      'the press writing nothing', () {
    for (final frame in [1, 5, 8, last]) {
      keyAt(frame, camera);
    }
    copyOneToEight(camera);
    standOn(last, camera);

    expect(
      (pill.canPasteIndependentFrame, pill.canPasteLinkedFrame),
      (false, false),
    );
    pill.pasteIndependentFrame();
    expect(keys(), {1, 5, 8, last});
  });

  test('the end key selected is replaced as any key is; pulled in by a '
      'shorter paste it moves in as any key does', () {
    for (final frame in [1, 5, 8, last]) {
      keyAt(frame, camera);
    }
    copyOneToEight(camera);

    select(camera, last - 1, last + 1);
    pill.pasteIndependentFrame();
    expect(keys(), {1, 5, 8, last - 1});

    s.undo();
    expect(keys(), {1, 5, 8, last}, reason: '⛔전제');
    select(camera, last - 12, last - 2);
    pill.pasteIndependentFrame();
    expect(keys(), {1, 5, 8, last - 12, last - 8, last - 5, last - 2});
  });

  test('a drawing row\'s keys are not the camera\'s: pushed past the cut\'s '
      'end they go there — the end is the camera row\'s alone', () {
    final row = s.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind != LayerKind.camera,
    );
    s.selectLayer(row.id);
    Set<int> rowKeys() => transformLaneKeyFrames(
      s.requireActiveCut.layers
          .firstWhere((layer) => layer.id == row.id)
          .transformTrack,
      'position',
    );
    for (final frame in [1, 5, 8, last]) {
      keyAt(frame, row);
    }
    expect(rowKeys(), {1, 5, 8, last}, reason: '⛔전제');
    copyOneToEight(row);
    standOn(4, row);

    expect(pill.canPasteIndependentFrame, isTrue);
    pill.pasteIndependentFrame();
    expect(rowKeys(), {1, 4, 8, 11, 13, 16, last + 8});
  });
}
