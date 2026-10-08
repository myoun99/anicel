import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

/// 🗣️I-73-camera-row-Q4 (유저 2026-10-09): 「끝 칸의 키는 늘릴때나 줄일때
/// 컷 끝에 붙어있기만 하면되. 위치만 이동되도록. 밖엔 애초에
/// 존재못하게하는게 지금구조잖아」.
///
/// The key on a camera's last frame moves with that frame, its pose, type
/// and name its own; every other key stays — and a shrink stops short of
/// the last of those, so none is ever put out.
void main() {
  /// A camera whose POSITION lane keys [x]'s frames (x being the frame) and
  /// whose ROTATION lane keys [turns]'.
  CutCamera cameraOf(
    List<int> x, {
    List<int> turns = const [],
    Map<int, String> names = const {},
    Map<int, PropertyKeyInterpolation> types = const {},
  }) => CutCamera.fromTrack(
    TransformTrack.empty().copyWith(
      position: PropertyTrack(
        keys: {
          for (final frame in x)
            frame: PropertyKey(
              CanvasPoint(x: frame.toDouble(), y: 0),
              interpolation: types[frame] ?? PropertyKeyInterpolation.linear,
              name: names[frame],
            ),
        },
      ),
      rotation: PropertyTrack(
        keys: {for (final frame in turns) frame: PropertyKey(frame * 10.0)},
      ),
    ),
  );

  Map<int, double> positions(CutCamera camera) => {
    for (final entry in camera.track.position.keys.entries)
      entry.key: entry.value.value.x,
  };

  group('the key on the last frame', () {
    test('🚨comes out with the end when the cut grows — pose, type, name and '
        'every lane', () {
      final moved = cameraWithItsEndKeyAt(
        cameraOf(
          [0, 12, 23],
          turns: [0, 23],
          names: {23: 'OUT'},
          types: {23: PropertyKeyInterpolation.hold},
        ),
        lastFrame: 29,
        previousLastFrame: 23,
      );

      expect(positions(moved), {0: 0, 12: 12, 29: 23});
      expect(moved.track.rotation.keys.keys, [0, 29]);
      final key = moved.track.position.keys[29]!;
      expect(key.name, 'OUT');
      expect(key.interpolation, PropertyKeyInterpolation.hold);
    });

    test('🚨comes in with the end when the cut shrinks', () {
      expect(
        positions(
          cameraWithItsEndKeyAt(
            cameraOf([0, 12, 23]),
            lastFrame: 15,
            previousLastFrame: 23,
          ),
        ),
        {0: 0, 12: 12, 15: 23},
      );
    });

    test('and back again is the same move the other way', () {
      final out = cameraWithItsEndKeyAt(
        cameraOf([0, 12, 23]),
        lastFrame: 29,
        previousLastFrame: 23,
      );
      expect(
        cameraWithItsEndKeyAt(out, lastFrame: 23, previousLastFrame: 29),
        cameraOf([0, 12, 23]),
      );
    });
  });

  test('a camera with no key on its last frame is the very camera back', () {
    final camera = cameraOf([0, 20]);
    expect(
      cameraWithItsEndKeyAt(camera, lastFrame: 29, previousLastFrame: 23),
      same(camera),
    );
    expect(
      cameraWithItsEndKeyAt(camera, lastFrame: 23, previousLastFrame: 23),
      same(camera),
      reason: 'nothing moved',
    );
  });

  test('a lane already keyed on the new last frame keeps both where they '
      'are', () {
    expect(
      positions(
        cameraWithItsEndKeyAt(
          cameraOf([0, 15, 23]),
          lastFrame: 15,
          previousLastFrame: 23,
        ),
      ),
      {0: 0, 15: 15, 23: 23},
    );
  });

  test('⚠️a cut of one frame keeps its key on the first', () {
    final camera = cameraOf([0]);
    expect(
      cameraWithItsEndKeyAt(camera, lastFrame: 4, previousLastFrame: 0),
      same(camera),
    );
  });

  group('the shortest a cut may become', () {
    test('stops one frame past the last key but the one on the end', () {
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 12, 23]), drawnFrameCount: 24),
        14,
        reason: 'key 12 stays; the end key needs frame 13',
      );
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 23]), drawnFrameCount: 24),
        2,
      );
    });

    test('with no key on the end, keeps the last key inside', () {
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 20]), drawnFrameCount: 24),
        21,
      );
    });

    test('a lone end key, or no key at all, bounds nothing', () {
      expect(cameraDrawnFrameFloor(cameraOf([23]), drawnFrameCount: 24), 1);
      expect(cameraDrawnFrameFloor(cameraOf([]), drawnFrameCount: 24), 1);
    });
  });
}
