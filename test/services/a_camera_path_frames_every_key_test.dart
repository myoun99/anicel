import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/camera_work_marks.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/key_path.dart' show KeyPathKind;
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/camera_path.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart'
    show resolveCameraPoseAtTime;

import '../helpers/camera_key_names.dart';

/// I-89 ④⑥ — a camera's path as the canvas and the export write it (유저
/// 2026-10-11: 「캔버스랑 출력쪽은 키마다 전부 사각형 그리는거야. 사각형이랑
/// 십자랑 한 세트로. 위치도 다 통일」 · 「24f도 사각형존재하게되니까
/// 왼쪽위」): the trail each corner of its frame draws, and at every key its
/// frame, the cross at its centre and its label — and on the canvas, crosses
/// in time, each with its frame beside it.
void main() {
  /// A 160×90 camera over a 640×360 canvas.
  const frameSize = CanvasSize(width: 160, height: 90);

  CameraPose at(double x, double y, {double turn = 0}) => CameraPose(
    center: CanvasPoint(x: x, y: y),
    rotationDegrees: turn,
  );

  Cut cutWith(CutCamera camera) => Cut(
    id: const CutId('c'),
    name: '1',
    layers: const [],
    duration: 48,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: camera,
  );

  CameraPath pathOf(CutCamera camera) =>
      CameraPath.of(cutWith(camera), frameSize)!;

  /// Right, then down: frame 0 → 12 → 24.
  final three = CutCamera(
    keyframes: {0: at(80, 45), 12: at(320, 45), 24: at(320, 180)},
  );

  /// The camera's frame on the canvas with its centre at ([x], [y]).
  List<Offset> frameAround(double x, double y) => [
    Offset(x - 80, y - 45),
    Offset(x + 80, y - 45),
    Offset(x + 80, y + 45),
    Offset(x - 80, y + 45),
  ];

  const sizes = CameraMarkSizes(
    frameWidth: 1.8,
    trailWidth: 1.4,
    labelSize: 12,
    crossArm: 5,
    crossWidth: 1.6,
    labelInset: 4,
  );

  Offset same(Offset point) => point;

  List<SheetMark> marksOf(CameraPath path, {int? from, int? to}) =>
      cameraPathMarks(
        path,
        place: same,
        sizes: sizes,
        layer: SheetPaintLayer.picture,
        from: from,
        to: to,
      ).toList();

  List<SheetStroke> framesIn(List<SheetMark> marks) => [
    for (final mark in marks)
      if (mark is SheetStroke && mark.closed) mark,
  ];

  /// The two-point strokes — a cross's arms.
  List<SheetStroke> armsIn(List<SheetMark> marks) => [
    for (final mark in marks)
      if (mark is SheetStroke && !mark.closed && mark.points.length == 2)
        mark,
  ];

  List<SheetWords> wordsIn(List<SheetMark> marks) =>
      marks.whereType<SheetWords>().toList();

  void expectPoints(List<Offset> actual, List<Offset> expected) {
    expect(actual, hasLength(expected.length));
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-9), reason: '#$index');
      expect(actual[index].dy, closeTo(point.dy, 1e-9), reason: '#$index');
    }
  }

  Offset middleOf(SheetStroke arm) => (arm.points[0] + arm.points[1]) / 2;

  test('every key is framed, crossed at its centre and labelled at its '
      'top-left corner — the first in IN\'s green, a key between in ink, '
      'the last in OUT\'s red', () {
    final marks = marksOf(pathOf(three));
    final frames = framesIn(marks);
    expect(frames.map((frame) => frame.argb), [
      cameraInArgb,
      cameraBetweenArgb,
      cameraOutArgb,
    ], reason: 'a frame at EVERY key — the conte frames its ends alone');
    expectPoints(frames[0].points, frameAround(80, 45));
    expectPoints(frames[1].points, frameAround(320, 45));
    expectPoints(frames[2].points, frameAround(320, 180));

    final arms = armsIn(marks);
    expect(arms, hasLength(6), reason: 'two arms a key');
    for (final (index, centre) in const [
      Offset(80, 45),
      Offset(320, 45),
      Offset(320, 180),
    ].indexed) {
      for (final arm in arms.sublist(index * 2, index * 2 + 2)) {
        expect(middleOf(arm).dx, closeTo(centre.dx, 1e-9));
        expect(middleOf(arm).dy, closeTo(centre.dy, 1e-9));
        expect(arm.argb, frames[index].argb, reason: 'the frame\'s set');
      }
    }

    final words = wordsIn(marks);
    expect(words.map((label) => label.argb), [
      cameraInArgb,
      cameraBetweenArgb,
      cameraOutArgb,
    ]);
    for (final (index, label) in words.indexed) {
      final topLeft = frames[index].points.first;
      expect(label.slot.left, closeTo(topLeft.dx + 4, 1e-9));
      expect(label.slot.top, closeTo(topLeft.dy + 4, 1e-9));
    }
  });

  test('an unnamed key is written by the frame it stands on as the cursor '
      'counts it, a named one by its name, and one whose lanes disagree on '
      'it — the header\'s 「...」 — as an unnamed one', () {
    expect(wordsIn(marksOf(pathOf(three))).map((label) => label.text), [
      '1f',
      '13f',
      '25f',
    ]);
    final called = cameraKeyNamed(
      cameraKeyNamed(three, 0, position: 'A', scale: 'A', rotation: 'A'),
      24,
      position: 'B',
      scale: 'C',
      rotation: 'B',
    );
    expect(wordsIn(marksOf(pathOf(called))).map((label) => label.text), [
      'A',
      '13f',
      '25f',
    ]);
  });

  test('each corner of the frame draws a trail — four, top-left first, the '
      'conte\'s (I-89-Q13 「콘티처럼 꼭짓점 4개 궤적」 · 「이 궤도 시스템은 '
      '콘티용지패널이랑 정확히 동일」) — through every frame from the first '
      'key to the last, and the half between, as playback shows it', () {
    final trails = [
      for (final mark in marksOf(pathOf(three)))
        if (mark is SheetStroke && mark.argb == cameraTrailArgb) mark,
    ];
    expect(trails, hasLength(4), reason: 'a corner each — not the centre');
    for (final (corner, trail) in trails.indexed) {
      expect(trail.points, hasLength(49), reason: 'corner $corner');
      expect(trail.width, sizes.trailWidth);
      expectPoints(
        [for (final half in [12, 13, 36, 37]) trail.points[half]],
        [
          for (final centre in const [
            Offset(200, 45),
            Offset(210, 45),
            Offset(320, 112.5),
            Offset(320, 118.125),
          ])
            frameAround(centre.dx, centre.dy)[corner],
        ],
      );
    }
  });

  test('along a path bent through its keys, a half between two frames '
      'stands where the camera does then — off the line the two frames '
      'draw', () {
    final bent = CutCamera.fromTrack(
      three.track.copyWith(
        position: three.track.position.withKeyPaths(
          frames: {12},
          kind: KeyPathKind.autoBezier,
        ),
      ),
    );
    expect(bent.track.position.keyAt(12)!.path.curved, isTrue, reason: '⛔전제');
    final trail = marksOf(pathOf(bent)).whereType<SheetStroke>().firstWhere(
      (mark) => mark.argb == cameraTrailArgb,
    );
    final half = trail.points[2 * 10 + 1];
    final camera = resolveCameraPoseAtTime(
      camera: bent,
      canvasSize: cutWith(bent).canvasSize,
      time: 10.5,
    ).center;
    expectPoints([half], [frameAround(camera.x, camera.y).first]);
    final chord = (trail.points[2 * 10] + trail.points[2 * 11]) / 2;
    expect((half - chord).distance, greaterThan(0.01));
  });

  test('a key whose time roves is framed where the camera passes it — at '
      'its value — and labelled by the cell it stands on', () {
    final roving = CutCamera.fromTrack(
      TransformTrack.empty().copyWith(
        position: three.track.position.withKeysRoving(
          frames: {12},
          roving: true,
        ),
      ),
    );
    final path = pathOf(roving);
    // The way from 0 to 24 is 240 + 135 long and the key 240 along it:
    // passed at 24 × 240 / 375 = 15.36, the cell nearest is 15.
    expect(
      [for (final key in path.keys) key.frameIndex],
      [0, 15, 24],
      reason: '⛔전제: placed',
    );
    final marks = marksOf(path);
    expectPoints(framesIn(marks)[1].points, frameAround(320, 45));
    expect(wordsIn(marks)[1].text, '16f');
  });

  test('a camera that frames one place at every key — or has one key, or '
      'none — has no path, as the conte gives it none', () {
    CameraPath? of(CutCamera camera) =>
        CameraPath.of(cutWith(camera), frameSize);
    expect(of(CutCamera(keyframes: {0: at(80, 45), 12: at(80, 45)})), isNull);
    expect(of(CutCamera(keyframes: {0: at(80, 45)})), isNull);
    expect(of(CutCamera()), isNull);
    expect(of(three), isNotNull, reason: '⛔전제: a moving one has one');
  });

  test('kept to some frames, a surface writes only the keys and the trail '
      'inside them — and nothing for frames the path never reaches', () {
    final marks = marksOf(pathOf(three), from: 6, to: 18);
    expect(framesIn(marks).map((frame) => frame.argb), [cameraBetweenArgb]);
    expect(wordsIn(marks).map((label) => label.text), ['13f']);
    final trail = marks.whereType<SheetStroke>().first;
    expect(trail.argb, cameraTrailArgb);
    expect(trail.points, hasLength(25), reason: 'frames 6 to 18, every half');
    expect(
      trail.points.first.dx,
      closeTo(200 - 80, 1e-9),
      reason: 'the top-left corner at frame 6',
    );

    final early = marksOf(pathOf(three), from: -6, to: 6);
    expect(wordsIn(early).map((label) => label.text), ['1f']);
    expect(
      early.whereType<SheetStroke>().first.points,
      hasLength(13),
      reason: 'frames 0 to 6, every half — nothing before the first key',
    );

    // Asked for frames past either end, the trails keep to the path's.
    final asked = pathOf(three).cornerTrailsBetween(-6, 30);
    expect(asked, hasLength(4));
    expect(asked.first, hasLength(49), reason: 'frames 0 to 24, every half');
    expect(pathOf(three).cornerTrailsBetween(-6, 0), isEmpty);

    final touching = marksOf(pathOf(three), from: 24, to: 30);
    expect(wordsIn(touching).map((label) => label.text), ['25f']);
    expect(
      touching.whereType<SheetStroke>().where(
        (mark) => mark.argb == cameraTrailArgb,
      ),
      isEmpty,
      reason: 'the last key alone: no travel, no trail',
    );

    expect(marksOf(pathOf(three), from: 30, to: 40), isEmpty);
  });

  test('every point is laid on the surface by its place — the frames, the '
      'trail, the labels and the crosses in time — at the surface\'s own '
      'sizes', () {
    Offset laid(Offset point) => Offset(point.dx * 2 + 10, point.dy * 2 - 5);
    final path = pathOf(three);
    final marks = cameraPathMarks(
      path,
      place: laid,
      sizes: sizes,
      layer: SheetPaintLayer.picture,
    ).toList();
    expectPoints(framesIn(marks)[1].points, [
      for (final corner in frameAround(320, 45)) laid(corner),
    ]);
    final trail = marks.whereType<SheetStroke>().first;
    expect(trail.argb, cameraTrailArgb, reason: '⛔전제');
    expectPoints([trail.points[12]], [laid(frameAround(200, 45).first)]);
    final topLeft = laid(frameAround(320, 45).first);
    expect(wordsIn(marks)[1].slot.left, closeTo(topLeft.dx + 4, 1e-9));
    expect(wordsIn(marks)[1].slot.top, closeTo(topLeft.dy + 4, 1e-9));
    final arm = armsIn(marks).first;
    expect(
      (arm.points[1] - arm.points[0]).distance,
      closeTo(2 * sizes.crossArm, 1e-9),
      reason: 'an arm as long however the canvas is laid',
    );
    final ticks = cameraPathTicks(
      path,
      place: laid,
      every: 5,
      playhead: 0,
      arm: 3,
      width: 1.1,
      labelSize: 10,
      labelGap: 2,
      layer: SheetPaintLayer.picture,
    ).toList();
    final tick = ticks.whereType<SheetStroke>().first;
    expectPoints([middleOf(tick)], [laid(const Offset(180, 45))]);
    expectPoints(
      [ticks.whereType<SheetWords>().first.slot.topLeft],
      [laid(const Offset(180, 45)) + const Offset(2, 2)],
    );
  });

  group('in time', () {
    /// The spec's grey behind the playhead and blue ahead of it (2026-10-10,
    /// the mock's 5판).
    const grey = 0xFF8E9093;
    const blue = 0xFF3A78C8;

    List<SheetMark> inTime(
      CameraPath path, {
      required int every,
      required int playhead,
      int? from,
      int? to,
    }) => cameraPathTicks(
      path,
      place: same,
      every: every,
      playhead: playhead,
      arm: 3,
      width: 1.1,
      labelSize: 10,
      labelGap: 2,
      layer: SheetPaintLayer.picture,
      from: from,
      to: to,
    ).toList();

    List<SheetStroke> ticksOf(
      CameraPath path, {
      required int every,
      required int playhead,
      int? from,
      int? to,
    }) => inTime(
      path,
      every: every,
      playhead: playhead,
      from: from,
      to: to,
    ).whereType<SheetStroke>().toList();

    List<SheetWords> labelsOf(
      CameraPath path, {
      required int every,
      required int playhead,
    }) => wordsIn(inTime(path, every: every, playhead: playhead));

    test('a cross every N frames — none where a key wears its own — grey '
        'where the playhead has passed, blue where it is yet to go, ink '
        'where it stands', () {
      final ticks = ticksOf(pathOf(three), every: 5, playhead: 10);
      expect(ticks, hasLength(8), reason: 'frames 5, 10, 15, 20 — 0 is a key');
      expect([for (var i = 0; i < 8; i += 2) ticks[i].argb], [
        grey,
        cameraBetweenArgb,
        blue,
        blue,
      ]);
      expect(middleOf(ticks[0]).dx, closeTo(180, 1e-9), reason: 'frame 5');
      expect(middleOf(ticks[6]).dy, closeTo(45 + 135 * 8 / 12, 1e-9));
      expect(
        ticksOf(pathOf(three), every: 12, playhead: 0),
        isEmpty,
        reason: 'every tick on a key',
      );
    });

    test('each wears the frame it stands on, in its own colour (유저 '
        '2026-10-12: 「그 상황에서 십자가쪽에도 프레임번호 아까말한대로 '
        '보여주도록」) — below and right of it, where the crosses either side '
        'leave that free', () {
      final labels = labelsOf(pathOf(three), every: 5, playhead: 10);
      expect(labels.map((label) => label.text), [
        '6f',
        '11f',
        '16f',
        '21f',
        ...['1f', '13f', '25f'],
      ]);
      expect(labels.map((label) => label.argb), [
        grey,
        cameraBetweenArgb,
        blue,
        blue,
        ...[cameraInArgb, cameraBetweenArgb, cameraOutArgb],
      ]);
      // Frame 5 at (180, 45): 0 and 10 level with it.
      expectPoints([labels[0].slot.topLeft], const [Offset(182, 47)]);
      expect((labels[0].h, labels[0].v), (SheetAlign.start, SheetAlign.start));
      expect(labels[0].size, 10);
      // Frame 15 at (320, 78.75): 10 above and left of it, 20 below it.
      expectPoints([labels[2].slot.topLeft], const [Offset(322, 80.75)]);
    });

    test('a key\'s own cross wears its frame too, by the same rule, in the '
        'key\'s colour (I-89-Q16 B, 유저 2026-10-12: 「키의 십자에도」)', () {
      // A peak at 12, (320, 45): the path off it either side — frame 11
      // below and left of it, 13 below and right — leaves above and right.
      final peak = CutCamera(
        keyframes: {0: at(80, 180), 12: at(320, 45), 24: at(560, 180)},
      );
      final labels = labelsOf(pathOf(peak), every: 5, playhead: 0);
      final key = labels.singleWhere((label) => label.text == '13f');
      expect(key.argb, cameraBetweenArgb);
      expect(key.size, 10);
      expect(key.slot.left, closeTo(320 + 2, 1e-9));
      expect(key.slot.bottom, closeTo(45 - 2, 1e-9));
      expect((key.h, key.v), (SheetAlign.start, SheetAlign.end));
    });

    test('a roving key\'s frame stands beside its cross, where the camera '
        'passes it — not where the cell it stands on would put it', () {
      final roving = CutCamera.fromTrack(
        TransformTrack.empty().copyWith(
          position: three.track.position.withKeysRoving(
            frames: {12},
            roving: true,
          ),
        ),
      );
      final key = labelsOf(
        pathOf(roving),
        every: 5,
        playhead: 0,
      ).singleWhere((label) => label.text == '16f');
      // Passed at (320, 45), 15.36 — frame 14 level before it, 16 straight
      // below. The camera at frame 15 is short of the corner, with 16 below
      // and right of it.
      expectPoints([key.slot.topLeft], const [Offset(322, 47)]);
    });

    test('where the path takes the quarter below and right, the frame stands '
        'in the first free of below-left, above-right and above-left (「십자가 '
        '오른쪽아래,왼쪽아래,오른쪽위,왼쪽위 우선순위는 이 순서대로 '
        '빈공간에」)', () {
      // Frame 10 at (280, 45): 5 level on its left, 15 below and right —
      // past the turn at 12.
      final turning = labelsOf(pathOf(three), every: 5, playhead: 0)[1];
      expect(turning.text, '11f', reason: '⛔전제');
      expect(turning.slot.right, closeTo(280 - 2, 1e-9));
      expect(turning.slot.top, closeTo(45 + 2, 1e-9));
      expect((turning.h, turning.v), (SheetAlign.end, SheetAlign.start));

      // A peak at 12: frame 10 at (280, 67.5) has 5 below and left of it
      // and 15 below and right.
      final peak = CutCamera(
        keyframes: {0: at(80, 180), 12: at(320, 45), 24: at(560, 180)},
      );
      final top = labelsOf(pathOf(peak), every: 5, playhead: 0)[1];
      expect(top.text, '11f', reason: '⛔전제');
      expect(top.slot.left, closeTo(280 + 2, 1e-9));
      expect(top.slot.bottom, closeTo(67.5 - 2, 1e-9));
      expect((top.h, top.v), (SheetAlign.start, SheetAlign.end));
    });

    test('counted from the cut\'s first frame, not the camera\'s first key',
        () {
      final late = CutCamera(keyframes: {2: at(80, 45), 14: at(320, 45)});
      final ticks = ticksOf(pathOf(late), every: 4, playhead: 0);
      expect(ticks, hasLength(6), reason: 'frames 4, 8 and 12');
      for (final (index, frame) in const [4, 8, 12].indexed) {
        expect(
          middleOf(ticks[index * 2]).dx,
          closeTo(80 + 240 * (frame - 2) / 12, 1e-9),
          reason: 'frame $frame',
        );
      }
    });

    test('kept to some frames, as the keys and the trail are', () {
      expect(
        ticksOf(pathOf(three), every: 1, playhead: 0, from: 10, to: 14),
        hasLength(8),
        reason: 'frames 10, 11, 13, 14 — 12 is a key',
      );
      expect(
        ticksOf(pathOf(three), every: 1, playhead: 0, from: -3, to: 2),
        hasLength(4),
        reason: 'frames 1 and 2 — nothing before the first key',
      );
      expect(
        wordsIn(
          inTime(pathOf(three), every: 1, playhead: 0, from: 10, to: 14),
        ).map((label) => label.text),
        ['11f', '12f', '14f', '15f', '13f'],
        reason: 'and the key\'s frame of the keys among them',
      );
    });

    test('a turned camera\'s crosses turn with its frame, a key\'s and a '
        'tick\'s alike, and a tick\'s frame with them — the set stands '
        'square', () {
      final turned = CutCamera(
        keyframes: {0: at(80, 45, turn: 30), 12: at(320, 45, turn: 30)},
      );
      final path = pathOf(turned);
      final along = path.keys.first.corners[1] - path.keys.first.corners[0];
      final turn = math.atan2(along.dy, along.dx);
      expect(turn, closeTo(30 * math.pi / 180, 1e-9), reason: '⛔전제');
      for (final arm in [
        armsIn(marksOf(path)).first,
        ticksOf(path, every: 6, playhead: 0).first,
      ]) {
        final run = arm.points[1] - arm.points[0];
        expect(math.atan2(run.dy, run.dx), closeTo(turn, 1e-9));
      }
      // Frame 6 at (200, 45), between keys level with it: below and right
      // as the frame stands, two along its sides.
      final label = labelsOf(path, every: 6, playhead: 0).first;
      expect(label.text, '7f', reason: '⛔전제');
      expect(label.turn, closeTo(turn, 1e-9));
      final right = Offset(math.cos(turn), math.sin(turn));
      final down = Offset(-math.sin(turn), math.cos(turn));
      expectPoints(
        [label.slot.topLeft],
        [const Offset(200, 45) + (right + down) * 2],
      );
    });
  });
}
