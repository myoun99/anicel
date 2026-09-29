import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';

/// A conte cell's camera work, read off its cut's camera (유저 2026-09-29/30):
/// every key inside the cell, what the sheet calls each one, and the canvas
/// their frames sweep.
void main() {
  CameraPose at(double x, double y, {double zoom = 1}) =>
      CameraPose(center: CanvasPoint(x: x, y: y), zoom: zoom);

  /// [camera] with the key at [frame] called [position], [scale] and
  /// [rotation] on those lanes.
  CutCamera named(
    CutCamera camera,
    int frame, {
    String? position,
    String? scale,
    String? rotation,
  }) {
    final track = camera.track;
    return CutCamera.fromTrack(
      track.copyWith(
        position: track.position.withKeyName(frame, position),
        scale: track.scale.withKeyName(frame, scale),
        rotation: track.rotation.withKeyName(frame, rotation),
      ),
    );
  }

  CutCamera calledEverywhere(CutCamera camera, int frame, String name) =>
      named(camera, frame, position: name, scale: name, rotation: name);

  /// The one cell of a 24-frame cut whose camera is [camera] — a 160×90
  /// camera over a 640×360 canvas.
  ConteCellSource cellOf(CutCamera camera, {bool bypassed = false}) {
    final project = Project(
      id: const ProjectId('camera-work'),
      name: 'Camera work',
      cameraSize: const CanvasSize(width: 160, height: 90),
      createdAt: DateTime.utc(2026, 9, 30),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 24,
              canvasSize: const CanvasSize(width: 640, height: 360),
              camera: camera,
              layers: [
                Layer(
                  id: const LayerId('sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(
                      id: const FrameId('f'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: const {
                    0: TimelineExposure.drawing(FrameId('f'), length: 24),
                  },
                ),
                Layer(
                  id: const LayerId('camera'),
                  name: 'Camera',
                  kind: LayerKind.camera,
                  frames: const [],
                  timeline: const {},
                  transformEnabled: !bypassed,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    return buildConteSheetSource(project).cuts.single.cells.single;
  }

  final pan = CutCamera(keyframes: {0: at(80, 45), 12: at(240, 45)});

  void expectPoints(
    List<Offset> actual,
    List<Offset> expected, {
    String? reason,
  }) {
    expect(actual, hasLength(expected.length), reason: reason);
    for (final (index, point) in expected.indexed) {
      expect(actual[index].dx, closeTo(point.dx, 1e-9), reason: reason);
      expect(actual[index].dy, closeTo(point.dy, 1e-9), reason: reason);
    }
  }

  test('two keys in the cell: the first is IN and the last OUT, each with '
      'the camera\'s frame there, and the cell shows the canvas they sweep',
      () {
    final work = cellOf(pan).camera!;
    expect(work.keys.map((key) => key.role), [
      ConteCameraKeyRole.first,
      ConteCameraKeyRole.last,
    ]);
    expect(work.keys.map((key) => key.label), ['IN', 'OUT']);
    expectPoints(work.keys.first.corners, const [
      Offset.zero,
      Offset(160, 0),
      Offset(160, 90),
      Offset(0, 90),
    ]);
    expect(work.field, const Rect.fromLTRB(0, 0, 320, 90));
    expect(work.screen.width, 160);
    expect(work.screen.height, 90);
    expect(work.trails, hasLength(4));
    expectPoints(
      work.trails.first,
      const [Offset.zero, Offset(160, 0)],
      reason: 'the top-left corner\'s trail, key to key',
    );
  });

  test('a named key is called by its name, in the place IN or OUT would take '
      '— 「카메라 마크 이름있으면 A,B 이런식으로 이름 따라가고 없으면 … IN '
      'OUT」', () {
    final work = cellOf(calledEverywhere(pan, 0, 'A')).camera!;
    expect(work.keys.map((key) => key.label), ['A', 'OUT']);
    expect(work.keys.first.role, ConteCameraKeyRole.first);
  });

  test('a key between is written only when it has a name — its frame is '
      'never drawn, its name stands where it would be', () {
    final three = CutCamera(
      keyframes: {0: at(80, 45), 6: at(160, 90), 12: at(240, 45)},
    );
    final unnamed = cellOf(three).camera!;
    expect(unnamed.keys.map((key) => key.role), [
      ConteCameraKeyRole.first,
      ConteCameraKeyRole.between,
      ConteCameraKeyRole.last,
    ]);
    expect(unnamed.keys.map((key) => key.label), ['IN', null, 'OUT']);
    final named = cellOf(calledEverywhere(three, 6, 'B')).camera!;
    expect(named.keys.map((key) => key.label), ['IN', 'B', 'OUT']);
  });

  test('a key whose lanes disagree on its name — the header\'s 「...」 — is '
      'as good as unnamed (「레인끼리 달라서 헤더가 ...으로 표시되는 경우 … '
      '이름 안정해진거랑 같은 규칙으로 IN OUT」)', () {
    final mixed = named(pan, 0, position: 'A', scale: 'B', rotation: 'A');
    expect(cellOf(mixed).camera!.keys.map((key) => key.label), ['IN', 'OUT']);
  });

  test('a camera that holds still in the cell, or whose work is switched '
      'off on the camera row, shows its own view', () {
    expect(
      cellOf(CutCamera(keyframes: {0: at(80, 45), 30: at(240, 45)})).camera,
      isNull,
      reason: 'one key in the cell: nothing moves while it is on screen',
    );
    expect(
      cellOf(pan, bypassed: true).camera,
      isNull,
      reason: 'a bypassed camera shows the canvas centred, whatever its keys',
    );
  });

  test('keys that all frame one place are a camera holding still — the '
      'cell shows the camera\'s own view', () {
    expect(
      cellOf(CutCamera(keyframes: {0: at(80, 45), 12: at(80, 45)})).camera,
      isNull,
    );
  });

  test('a window shows the widest of the key frames: each frame of a zoomed '
      'pan takes a window, and a push-in\'s closer frame lies inside the '
      'wider', () {
    final zoomedPan = cellOf(
      CutCamera(
        keyframes: {0: at(80, 45, zoom: 2), 12: at(160, 45, zoom: 2)},
      ),
    ).camera!;
    expect(zoomedPan.screen.width, closeTo(80, 1e-9));
    expect(zoomedPan.screen.height, closeTo(45, 1e-9));
    expect(
      zoomedPan.field.width / zoomedPan.screen.width,
      closeTo(2, 1e-9),
      reason: 'a frame across: two windows wide',
    );
    final pushIn = cellOf(
      CutCamera(keyframes: {0: at(80, 45), 12: at(80, 45, zoom: 2)}),
    ).camera!;
    expect(pushIn.screen.width, closeTo(160, 1e-9));
    expect(pushIn.field, const Rect.fromLTRB(0, 0, 160, 90));
  });

  test('the canvas it sweeps is whole pixels, around every corner', () {
    final work = cellOf(
      CutCamera(keyframes: {0: at(80.4, 45.3), 12: at(240.6, 45.3)}),
    ).camera!;
    final field = work.field;
    for (final edge in [field.left, field.top, field.right, field.bottom]) {
      expect(edge, edge.roundToDouble(), reason: 'a whole pixel');
    }
    expect(field, const Rect.fromLTRB(0, 0, 321, 91));
  });
}
