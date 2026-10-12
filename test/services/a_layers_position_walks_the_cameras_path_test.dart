import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_work_marks.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/services/camera_path.dart';

/// I-89-Q9 — a layer's position walks a path by the camera's code (유저
/// 2026-10-12: 「같은 코드로 레이어 위치 레인에도」): a point where the
/// camera has its frame, crossed square to the surface at every key, its
/// label beside the cross where the path leaves room — below and right,
/// below and left, above and right, above and left (「이름 내가 카메라에서
/// 말한대로 오른쪽아래,왼쪽아래 이런순으로 두려고 시도」).
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  /// Right, then down and right: frame 0 → 10 → 20.
  final lane = PropertyTrack<CanvasPoint>()
      .withKey(0, p(0, 0))
      .withKey(10, p(100, 0))
      .withKey(20, p(200, 100));

  CameraPath pathOf(PropertyTrack<CanvasPoint> lane, {int axisOffset = 0}) =>
      CameraPath.ofPosition(lane, axisOffset: axisOffset)!;

  const sizes = CameraMarkSizes(
    frameWidth: 1.8,
    trailWidth: 1.4,
    labelSize: 12,
    crossArm: 5,
    crossWidth: 1.6,
    labelInset: 4,
  );

  Offset same(Offset point) => point;

  List<SheetMark> marksOf(CameraPath path) => cameraPathMarks(
    path,
    place: same,
    sizes: sizes,
    layer: SheetPaintLayer.picture,
  ).toList();

  List<SheetWords> wordsIn(Iterable<SheetMark> marks) =>
      marks.whereType<SheetWords>().toList();

  void expectPoints(List<Offset> actual, List<Offset> expected) {
    expect(actual, hasLength(expected.length));
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-9), reason: '#$index');
      expect(actual[index].dy, closeTo(point.dy, 1e-9), reason: '#$index');
    }
  }

  test('its keys stand at their values, and between them it is where the '
      'lane takes it at that time — one trail, through every frame and the '
      'half between', () {
    final path = pathOf(lane);
    expect([for (final key in path.keys) key.frameIndex], [0, 10, 20]);
    expect([for (final key in path.keys) key.corners], [
      [Offset.zero],
      [const Offset(100, 0)],
      [const Offset(200, 100)],
    ]);
    expect([for (final key in path.keys) key.role], [
      CameraKeyRole.first,
      CameraKeyRole.between,
      CameraKeyRole.last,
    ]);
    expectPoints(path.frameAt(5), const [Offset(50, 0)]);

    final trails = [
      for (final mark in marksOf(path))
        if (mark is SheetStroke && mark.argb == cameraTrailArgb) mark,
    ];
    expect(trails, hasLength(1), reason: 'a point draws one');
    expect(trails.single.points, hasLength(41));
    expectPoints(
      [for (final half in [10, 11, 30]) trails.single.points[half]],
      const [Offset(50, 0), Offset(55, 0), Offset(150, 50)],
    );
  });

  test('a point has no frame to draw: its cross stands square to the '
      'surface, and its label beside it where the path either side leaves '
      'room', () {
    final marks = marksOf(pathOf(lane));
    expect(
      [for (final mark in marks) if (mark is SheetStroke && mark.closed) mark],
      isEmpty,
    );
    final arms = [
      for (final mark in marks)
        if (mark is SheetStroke && !mark.closed && mark.points.length == 2)
          mark,
    ];
    expect(arms, hasLength(6), reason: 'two arms a key');
    for (final arm in arms) {
      final run = arm.points[1] - arm.points[0];
      expect(
        run.dx == 0 || run.dy == 0,
        isTrue,
        reason: 'square to the surface: $run',
      );
    }

    final labels = wordsIn(marks);
    expect(labels.map((label) => label.text), ['1f', '11f', '21f']);
    expect(labels.map((label) => label.argb), [
      cameraInArgb,
      cameraBetweenArgb,
      cameraOutArgb,
    ]);
    expect(labels.first.size, sizes.labelSize);
    // Frame 0: frame 1 level on its right — below and right is free.
    expectPoints([labels[0].slot.topLeft], const [Offset(4, 4)]);
    expect((labels[0].h, labels[0].v), (SheetAlign.start, SheetAlign.start));
    // Frame 10 at (100, 0): 9 level on its left, 11 below and right of it —
    // below and left.
    expect(labels[1].slot.right, closeTo(100 - 4, 1e-9));
    expect(labels[1].slot.top, closeTo(4, 1e-9));
    expect((labels[1].h, labels[1].v), (SheetAlign.end, SheetAlign.start));
    // Frame 20 at (200, 100): 19 above and left of it.
    expectPoints([labels[2].slot.topLeft], const [Offset(204, 104)]);
  });

  test('a named key is called by its name, and shown in time its frame '
      'stands in the next quarter the path leaves free; an unnamed key\'s '
      'label is its frame already', () {
    final named = pathOf(lane.withKeyName(10, 'A'));
    final label = wordsIn(marksOf(named))[1];
    expect(label.text, 'A');
    expect(label.slot.right, closeTo(100 - 4, 1e-9), reason: 'below-left');

    final inTime = wordsIn(
      cameraPathTicks(
        named,
        place: same,
        every: 5,
        playhead: 0,
        arm: 3,
        width: 1.1,
        labelSize: 10,
        labelGap: 2,
        layer: SheetPaintLayer.picture,
      ),
    );
    expect(
      inTime.map((label) => label.text),
      ['6f', '16f', '11f'],
      reason: 'frames 5 and 15, and the named key\'s',
    );
    final frame = inTime.last;
    expect(frame.argb, cameraBetweenArgb);
    expect(frame.slot.left, closeTo(100 + 2, 1e-9), reason: 'above-right');
    expect(frame.slot.bottom, closeTo(0 - 2, 1e-9));
    expect((frame.h, frame.v), (SheetAlign.start, SheetAlign.end));
  });

  test('a named key\'s frame never stands on its name: both read the path a '
      'frame either side of the key, not the crosses in time either side', () {
    // A peak at 10 between 9 below-left and 11 below-right of it — where
    // the crosses in time, at 5 and 15, both lie below and right.
    final peak = pathOf(
      PropertyTrack<CanvasPoint>()
          .withKey(5, p(30, 40))
          .withKey(8, p(-20, 20))
          .withKey(10, p(0, 0))
          .withKey(11, p(10, 10))
          .withKey(15, p(60, 40))
          .withKeyName(10, 'A'),
    );
    final name = wordsIn(marksOf(peak)).singleWhere((w) => w.text == 'A');
    expect(name.slot.left, closeTo(4, 1e-9), reason: 'above-right');
    expect(name.slot.bottom, closeTo(-4, 1e-9));

    final frame = wordsIn(
      cameraPathTicks(
        peak,
        place: same,
        every: 5,
        playhead: 0,
        arm: 3,
        width: 1.1,
        labelSize: 10,
        labelGap: 2,
        layer: SheetPaintLayer.picture,
      ),
    ).singleWhere((w) => w.text == '11f');
    expect(frame.slot.right, closeTo(-2, 1e-9), reason: 'above-left');
    expect(frame.slot.bottom, closeTo(-2, 1e-9));
    expect((frame.h, frame.v), (SheetAlign.end, SheetAlign.end));
  });

  test('a lane whose frames run ahead of the cut\'s — a track-SE row\'s — '
      'is read back on the cut\'s', () {
    final ahead = PropertyTrack<CanvasPoint>()
        .withKey(100, p(0, 0))
        .withKey(110, p(100, 0));
    final path = pathOf(ahead, axisOffset: 100);
    expect([for (final key in path.keys) key.frameIndex], [0, 10]);
    expectPoints(path.frameAt(5), const [Offset(50, 0)]);
    expect(wordsIn(marksOf(path)).map((label) => label.text), ['1f', '11f']);
  });

  test('one that walks nowhere has no path: one key, or none, or every key '
      'at one place', () {
    expect(
      CameraPath.ofPosition(
        PropertyTrack<CanvasPoint>().withKey(0, p(5, 5)).withKey(9, p(5, 5)),
      ),
      isNull,
    );
    expect(
      CameraPath.ofPosition(PropertyTrack<CanvasPoint>().withKey(0, p(5, 5))),
      isNull,
    );
    expect(CameraPath.ofPosition(PropertyTrack<CanvasPoint>()), isNull);
    expect(CameraPath.ofPosition(lane), isNotNull, reason: '⛔전제');
  });
}
