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
/// and name its own; every other key stays — and a shrink the hand drives
/// stops short of the last of those, so none is ever put out.
///
/// 🗣️I-73-camera-row-Q7 (유저 2026-10-09): 「OL삭제한다거나 하면 키를 컷
/// 길이 줄이는거랑 동일하게 그 사라진 코마만큼 컷길이 움직인거랑 동일한
/// 규칙으로 키를 앞당긴다」 — a shrink that comes at once brings in every key
/// on the frames that went, by as many frames as went.
void main() {
  /// A camera whose POSITION lane keys [x]'s frames (x being the frame) and
  /// whose ROTATION lane keys [turns]'.
  CutCamera cameraOf(
    List<int> x, {
    List<int> turns = const [],
    Map<int, String> names = const {},
    Map<int, KeyExit> types = const {},
  }) => CutCamera.fromTrack(
    TransformTrack.empty().copyWith(
      position: PropertyTrack(
        keys: {
          for (final frame in x)
            frame: PropertyKey(
              CanvasPoint(x: frame.toDouble(), y: 0),
              outgoing: types[frame] ?? KeySide.linear,
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
      final moved = cameraFollowingItsEnd(
        cameraOf(
          [0, 12, 23],
          turns: [0, 23],
          names: {23: 'OUT'},
          types: {23: KeyExit.hold},
        ),
        lastFrame: 29,
        previousLastFrame: 23,
      );

      expect(positions(moved), {0: 0, 12: 12, 29: 23});
      expect(moved.track.rotation.keys.keys, [0, 29]);
      final key = moved.track.position.keys[29]!;
      expect(key.name, 'OUT');
      expect(key.outgoing, KeyExit.hold);
    });

    test('🚨comes in with the end when the cut shrinks', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([0, 12, 23]),
            lastFrame: 15,
            previousLastFrame: 23,
          ),
        ),
        {0: 0, 12: 12, 15: 23},
      );
    });

    test('and back again is the same move the other way', () {
      final out = cameraFollowingItsEnd(
        cameraOf([0, 12, 23]),
        lastFrame: 29,
        previousLastFrame: 23,
      );
      expect(
        cameraFollowingItsEnd(out, lastFrame: 23, previousLastFrame: 29),
        cameraOf([0, 12, 23]),
      );
    });
  });

  test('a camera with no key on its last frame is the very camera back', () {
    final camera = cameraOf([0, 20]);
    expect(
      cameraFollowingItsEnd(camera, lastFrame: 29, previousLastFrame: 23),
      same(camera),
    );
    expect(
      cameraFollowingItsEnd(camera, lastFrame: 23, previousLastFrame: 23),
      same(camera),
      reason: 'nothing moved',
    );
  });

  test('a lane already keyed on the new last frame, as the cut GROWS, keeps '
      'both where they are', () {
    expect(
      positions(
        cameraFollowingItsEnd(
          cameraOf([0, 15, 29]),
          lastFrame: 29,
          previousLastFrame: 15,
        ),
      ),
      {0: 0, 15: 15, 29: 29},
    );
  });

  // 🗣️F-541 (유저 2026-11-02): 「그냥 안멈추고 만나면 밀어버리면 되지않나」 ·
  // I-21 「불도저로 쭉 미는느낌」. ↩️Keys came in by the frames that went,
  // one landing on another taking its frame (I-73-camera-row-Q7 · Q8).
  group('a shrink pushes the keys it meets', () {
    test('🚨each on a frame of its own, the end key leading them, on every '
        'lane', () {
      final moved = cameraFollowingItsEnd(
        cameraOf([0, 20, 27, 29], turns: [0, 27]),
        lastFrame: 23,
        previousLastFrame: 29,
      );

      expect(positions(moved), {0: 0, 20: 20, 22: 27, 23: 29});
      expect(moved.track.rotation.keys.keys, [0, 22]);
    });

    test('🚨a key with no key behind it is pushed as soon as the end reaches '
        'it', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([0, 12]),
            lastFrame: 8,
            previousLastFrame: 23,
          ),
        ),
        {0: 0, 8: 12},
      );
    });

    test('it stands where it stood until the end reaches it', () {
      final camera = cameraOf([0, 12]);
      expect(
        identical(
          cameraFollowingItsEnd(
            camera,
            lastFrame: 12,
            previousLastFrame: 23,
          ),
          camera,
        ),
        isTrue,
      );
    });

    test('a key the end meets is pushed, never lost', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([0, 15, 23]),
            lastFrame: 15,
            previousLastFrame: 23,
          ),
        ),
        {0: 0, 14: 15, 15: 23},
      );
    });

    test('a key two lanes share stays one key, whatever else a lane has', () {
      final moved = cameraFollowingItsEnd(
        cameraOf([0, 10, 12], turns: [0, 10]),
        lastFrame: 8,
        previousLastFrame: 12,
      );

      expect(positions(moved), {0: 0, 7: 10, 8: 12});
      expect(moved.track.rotation.keys.keys, [0, 7]);
    });

    test('a key that stood past the old end already is not for this write to '
        'move', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([0, 23, 40]),
            lastFrame: 15,
            previousLastFrame: 23,
          ),
        ),
        {0: 0, 15: 23, 40: 40},
      );
    });

    test('a key before the end\'s reach stays', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([1, 20]),
            lastFrame: 5,
            previousLastFrame: 29,
          ),
        ),
        {1: 1, 5: 20},
      );
    });

    test('out of frames — only a shrink at once gets there — the last pushed '
        'onto frame 0 takes it (Q8)', () {
      expect(
        positions(
          cameraFollowingItsEnd(
            cameraOf([0, 1, 2, 3]),
            lastFrame: 1,
            previousLastFrame: 3,
          ),
        ),
        {0: 2, 1: 3},
      );
    });
  });

  test('⚠️a cut of one frame keeps its key on the first', () {
    final camera = cameraOf([0]);
    expect(
      cameraFollowingItsEnd(camera, lastFrame: 4, previousLastFrame: 0),
      same(camera),
    );
  });

  group('the shortest a cut may become', () {
    test('leaves every key a frame of its own', () {
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 12, 23]), drawnFrameCount: 24),
        3,
      );
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 23]), drawnFrameCount: 24),
        2,
      );
    });

    test('with no key on the end, as much', () {
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 20]), drawnFrameCount: 24),
        2,
      );
    });

    test('a key already past the end bounds nothing — the others still '
        'do', () {
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 12, 40]), drawnFrameCount: 24),
        2,
      );
      expect(
        cameraDrawnFrameFloor(cameraOf([0, 23, 40]), drawnFrameCount: 24),
        2,
        reason: 'the end key past one other inside',
      );
      expect(
        cameraDrawnFrameFloor(cameraOf([23, 40]), drawnFrameCount: 24),
        1,
        reason: 'a lone end key inside',
      );
    });

    test('a lone end key, or no key at all, bounds nothing', () {
      expect(cameraDrawnFrameFloor(cameraOf([23]), drawnFrameCount: 24), 1);
      expect(cameraDrawnFrameFloor(cameraOf([]), drawnFrameCount: 24), 1);
    });
  });
}
