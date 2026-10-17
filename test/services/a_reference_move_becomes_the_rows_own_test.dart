// F-374-Q3 (유저 2026-10-17, 「움직임을 그 행의 트랜스폼 키로 옮긴다
// (추천)」): rasterizing a reference keeps the picture where its fx stood it
// — the cels hold the file as it was laid, and the move is the row's own
// keys now. F-374-Q7 (유저 2026-10-17, 「①은 스위치를 켜고 키로, ②③만
// 굽는다」): which rows take it as keys, which bake it, and which wait.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show layerPlacementAt;
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show picturePlacement;
import 'package:anicel/src/services/reference_move_carried.dart';

void main() {
  const canvas = CanvasSize(width: 400, height: 300);
  const picture = CanvasSize(width: 100, height: 60);
  final middle = CanvasPoint(x: 200, y: 150);
  final offMiddle = CanvasPoint(x: 130, y: 110);

  /// A row showing a 100×60 paper from frame [from], laid at [laid] and
  /// stood at [pose] — or where [fx] keys it — its own transform [own].
  Layer paper({
    required TransformPose laid,
    TransformPose? pose,
    TransformTrack? fx,
    TransformTrack? own,
    int from = 0,
    bool transformEnabled = true,
    LayerId? attachedTo,
    String file = '/paper.png',
  }) => Layer(
    id: const LayerId('paper'),
    name: 'paper',
    frames: [Frame(id: const FrameId('p'), duration: 1, strokes: const [])],
    timeline: {from: const TimelineExposure.drawing(FrameId('p'), length: 1)},
    mediaReference: MediaReference(
      assetPath: file,
      pose: pose ?? laid,
      pictureSize: picture,
      laid: laid,
      fx: fx,
    ),
    transformTrack: own,
    transformEnabled: transformEnabled,
    attachedToLayerId: attachedTo,
  );

  Cut cutOf(Layer layer) => Cut(
    id: const CutId('cut'),
    name: 'cut',
    layers: [layer],
    duration: 48,
    canvasSize: canvas,
  );

  ({TransformTrack track, bool enabled})? carriedWithSwitch(
    Layer row, {
    bool Function(TransformPropertyId property, String name)? nameIsFree,
  }) => transformCarryingReferenceMove(
    cut: cutOf(row),
    layer: row,
    nameIsFree: nameIsFree ?? (property, name) => true,
  );

  TransformTrack? carried(
    Layer row, {
    bool Function(TransformPropertyId property, String name)? nameIsFree,
  }) => carriedWithSwitch(row, nameIsFree: nameIsFree)?.track;

  CanvasPoint shownAt(Layer layer, int frame, CanvasPoint point) =>
      layerPlacementAt(
        cut: cutOf(layer),
        layer: layer,
        frameIndex: frame,
      )?.apply(point) ??
      point;

  /// How far the picture's farthest corner strays over [frames] from where
  /// [row] — still the reference — showed it, once [track] stands the row's
  /// cel with the reference let go, the row's transform switched on.
  double strayed(Layer row, TransformTrack track, Iterable<int> frames) {
    final baked = row.copyWith(
      transformTrack: track,
      transformEnabled: true,
      mediaReference: null,
    );
    final laid = picturePlacement(row.mediaReference!.laid, picture);
    var worst = 0.0;
    for (final frame in frames) {
      for (final (x, y) in const [
        (0.0, 0.0),
        (100.0, 0.0),
        (100.0, 60.0),
        (0.0, 60.0),
      ]) {
        final onCel = laid.apply(CanvasPoint(x: x, y: y));
        final was = shownAt(row, frame, onCel);
        final now = shownAt(baked, frame, onCel);
        worst = math.max(
          worst,
          math.max((was.x - now.x).abs(), (was.y - now.y).abs()),
        );
      }
    }
    return worst;
  }

  Map<int, T> valuesOf<T>(PropertyTrack<T> lane) =>
      lane.keys.map((frame, key) => MapEntry(frame, key.value));

  Iterable<int> frames(int count) => Iterable<int>.generate(count);

  test('🎯the fit a file laid 1:1 stood at is ONE Scale key where the row '
      'starts — and nothing else, the file laid on the canvas\'s middle', () {
    final row = paper(
      laid: TransformPose(center: middle),
      pose: TransformPose.uniform(center: middle, zoom: 2),
      from: 3,
    );

    final track = carried(row)!;

    expect(valuesOf(track.scale), {3: CanvasPoint(x: 2, y: 2)});
    for (final lane in [track.anchorPoint, track.position, track.rotation]) {
      expect(lane.isEmpty, isTrue, reason: 'each lane at its identity');
    }
    expect(strayed(row, track, frames(8)), lessThan(1e-9));
  });

  test('a file laid off the middle turns and scales about where it was '
      'laid — the row\'s Anchor Point — and a pose no key moves is one key '
      'a lane', () {
    final row = paper(
      laid: TransformPose(center: offMiddle),
      pose: TransformPose(
        center: CanvasPoint(x: 160, y: 120),
        scaleX: 1.5,
        scaleY: 1.5,
        rotationDegrees: 30,
      ),
    );

    final track = carried(row)!;

    expect(valuesOf(track.anchorPoint), {0: offMiddle});
    expect(valuesOf(track.position), {0: CanvasPoint(x: 160, y: 120)});
    expect(valuesOf(track.scale), {0: CanvasPoint(x: 1.5, y: 1.5)});
    expect(valuesOf(track.rotation), {0: 30.0});
    expect(strayed(row, track, frames(4)), lessThan(1e-9));
  });

  test('a lane the fx leaves as the row had it stays the row\'s own — its '
      'key where the row keyed it', () {
    final own = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(7, 15),
    );
    final row = paper(
      laid: TransformPose(center: middle),
      pose: TransformPose(center: CanvasPoint(x: 260, y: 150)),
      own: own,
    );

    final track = carried(row)!;

    expect(valuesOf(track.rotation), {7: 15.0});
    expect(track.scale.isEmpty, isTrue);
    expect(track.position.keys.keys, [0]);
    expect(strayed(row, track, frames(10)), lessThan(1e-9));
  });

  test('🎯the fx\'s keys are carried AS THEY ARE through the row\'s one '
      'pose — their frames, sides, ways and names — and the picture stands '
      'where it stood between them too', () {
    final row = paper(
      laid: TransformPose(center: offMiddle),
      fx: TransformTrack.properties(
        anchorPoint: PropertyTrack.empty(),
        position: PropertyTrack(
          keys: {
            0: PropertyKey(
              offMiddle,
              outgoing: const EaseSide(influence: 0.5),
              path: HandledPath(CanvasPoint(x: 40, y: -20)),
              name: 'up',
            ),
            12: PropertyKey(
              CanvasPoint(x: 250, y: 170),
              incoming: const EaseSide(speed: 2),
              path: KeyPath.auto,
            ),
          },
        ),
        scale: PropertyTrack(
          keys: {6: PropertyKey(CanvasPoint(x: 1.5, y: 1.5))},
        ),
        rotation: PropertyTrack(
          keys: {
            0: const PropertyKey(0.0),
            12: const PropertyKey(45.0, name: 'tilt'),
          },
        ),
        opacity: PropertyTrack.empty(),
      ),
      // Its own pose, keyed once: turned a quarter about the canvas's
      // middle, twice as big, moved.
      own: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 230, y: 170),
        ),
        scale: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 2, y: 2),
        ),
        rotation: PropertyTrack<double>().withKey(0, 90),
      ),
    );

    final track = carried(row)!;

    expect(valuesOf(track.anchorPoint), {0: offMiddle});
    expect(track.position.keys, {
      0: PropertyKey(
        CanvasPoint(x: 310, y: 30),
        outgoing: const EaseSide(influence: 0.5),
        path: HandledPath(CanvasPoint(x: 40, y: 80)),
        name: 'up',
      ),
      12: PropertyKey(
        CanvasPoint(x: 190, y: 270),
        incoming: const EaseSide(speed: 2),
        path: KeyPath.auto,
      ),
    });
    expect(valuesOf(track.scale), {6: CanvasPoint(x: 3, y: 3)});
    expect(track.rotation.keys, {
      0: const PropertyKey(90.0),
      12: const PropertyKey(135.0, name: 'tilt'),
    });
    expect(strayed(row, track, frames(20)), lessThan(1e-6));
  });

  test('a carried key keeps its name where the row\'s naming space is free '
      'of it — one another use of the row holds is dropped, lane by lane',
      () {
    final row = paper(
      laid: TransformPose(center: middle),
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {
            0: PropertyKey(middle, name: 'up'),
            12: PropertyKey(CanvasPoint(x: 260, y: 150), name: 'down'),
          },
        ),
        rotation: PropertyTrack(
          keys: {12: const PropertyKey(20.0, name: 'down')},
        ),
      ),
    );

    final track = carried(
      row,
      nameIsFree: (property, name) =>
          property != TransformPropertyId.position || name != 'down',
    )!;

    expect(track.position.keys[0]!.name, 'up');
    expect(track.position.keys[12]!.name, isNull);
    expect(track.rotation.keys[12]!.name, 'down');
  });

  test('🎯a row that moves on its own as well carries the two moves frame '
      'by frame — the keys of both on their frames, a key more wherever a '
      'way would stray by more than a pixel (유저 10-13 「1px 까지 허용」), and '
      'a lane neither keys left as a still one is', () {
    final row = paper(
      laid: TransformPose(center: offMiddle),
      pose: TransformPose.uniform(center: offMiddle, zoom: 2),
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, offMiddle)
            .withKey(24, CanvasPoint(x: 190, y: 110)),
      ),
      own: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(0, 0).withKey(24, 90),
      ),
      from: 2,
    );

    final track = carried(row)!;

    expect(
      track.position.keys.keys,
      containsAll(<int>[0, 24]),
      reason: 'the keys of both, on their frames',
    );
    expect(
      track.position.keys.length,
      greaterThan(2),
      reason: 'the row\'s turn swings the picture\'s middle along an arc',
    );
    expect(valuesOf(track.rotation), {0: 0.0, 24: 90.0});
    expect(
      valuesOf(track.scale),
      {2: CanvasPoint(x: 2, y: 2)},
      reason: 'a lane neither keys, ONE key where the row starts',
    );
    expect(valuesOf(track.anchorPoint), {2: offMiddle});
    expect(strayed(row, track, frames(30)), lessThanOrEqualTo(1 + 1e-9));
  });

  test('a row scaled unevenly carries a picture turned a quarter with its '
      'two axes swapped', () {
    final row = paper(
      laid: TransformPose(center: offMiddle),
      pose: TransformPose(center: offMiddle, rotationDegrees: 90),
      own: TransformTrack.empty().copyWith(
        scale: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 2, y: 1),
        ),
      ),
    );

    final track = carried(row)!;

    expect(valuesOf(track.scale), {0: CanvasPoint(x: 1, y: 2)});
    expect(valuesOf(track.rotation), {0: 90.0});
    expect(valuesOf(track.position), {0: CanvasPoint(x: 60, y: 110)});
    expect(strayed(row, track, frames(4)), lessThan(1e-9));
  });

  test('a row scaled unevenly under a picture turned other than by a '
      'quarter would SHEAR it, which no pose does — nothing carries it '
      '(F-374-Q7)', () {
    final uneven = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 2, y: 1)),
    );
    final turned = TransformPose(center: offMiddle, rotationDegrees: 30);

    expect(
      carried(
        paper(
          laid: TransformPose(center: offMiddle),
          pose: turned,
          own: uneven,
        ),
      ),
      isNull,
    );
    expect(
      carried(
        paper(
          laid: TransformPose(center: offMiddle),
          fx: TransformTrack.empty().copyWith(
            rotation: PropertyTrack<double>().withKey(0, 0).withKey(12, 90),
          ),
          own: uneven,
        ),
      ),
      isNull,
      reason: 'a quarter turn keyed over frames passes every turn between',
    );
    expect(
      carried(
        paper(
          laid: TransformPose(center: offMiddle),
          pose: turned,
          own: uneven.copyWith(
            position: PropertyTrack<CanvasPoint>()
                .withKey(0, middle)
                .withKey(10, CanvasPoint(x: 220, y: 150)),
          ),
        ),
      ),
      isNull,
      reason: 'frame by frame, as key by key',
    );
  });

  test('🎯a row whose transform is switched off carries the move over NONE '
      'of its own — the switch comes on, and the keys it kept while it '
      'showed nothing give way (F-374-Q7 ①)', () {
    final moved = TransformPose.uniform(
      center: CanvasPoint(x: 260, y: 150),
      zoom: 2,
    );
    final laid = TransformPose(center: middle);
    final hidden = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(0, 40).withKey(9, 80),
      opacity: PropertyTrack<double>().withKey(0, 0.2),
    );
    final off = paper(
      laid: laid,
      pose: moved,
      own: hidden,
      transformEnabled: false,
    );

    final after = carriedWithSwitch(off)!;

    expect(after.enabled, isTrue);
    expect(
      after.track,
      carried(paper(laid: laid, pose: moved)),
      reason: 'the move over an empty transform — none of the hidden keys',
    );
    expect(strayed(off, after.track, frames(12)), lessThan(1e-9));
  });

  test('an attach row stands where its base\'s transform puts it — its own '
      'transform cannot carry the move (F-374-Q7 ②)', () {
    expect(
      carried(
        paper(
          laid: TransformPose(center: middle),
          pose: TransformPose(center: CanvasPoint(x: 260, y: 150)),
          attachedTo: const LayerId('a'),
        ),
      ),
      isNull,
    );
  });

  test('a file laid turned or collapsed has no move the row carries', () {
    final moved = TransformPose(center: CanvasPoint(x: 260, y: 150));

    expect(
      carried(
        paper(
          laid: TransformPose(center: middle, rotationDegrees: 10),
          pose: moved,
        ),
      ),
      isNull,
    );
    expect(
      carried(
        paper(laid: TransformPose(center: middle, scaleX: 0), pose: moved),
      ),
      isNull,
    );
  });

  test('a reference standing where its file is laid leaves the row\'s '
      'transform as it is — and its switch, off as well', () {
    final own = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>().withKey(
        4,
        CanvasPoint(x: 210, y: 150),
      ),
    );

    expect(
      carried(paper(laid: TransformPose(center: offMiddle), own: own)),
      same(own),
    );
    final off = carriedWithSwitch(
      paper(
        laid: TransformPose(center: offMiddle),
        own: own,
        transformEnabled: false,
      ),
    )!;
    expect(off.track, same(own));
    expect(off.enabled, isFalse);
  });

  group('referenceLetGo — keys, the cels, or waiting (F-374-Q7)', () {
    final laid = TransformPose(center: middle);
    final fitted = TransformPose.uniform(center: middle, zoom: 0.5);
    final uneven = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 1, y: 2)),
    );
    final moving = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>()
          .withKey(0, middle)
          .withKey(24, CanvasPoint(x: 260, y: 150)),
    );

    ReferenceLetGo wayOf(
      Layer row, {
      bool othersKeepKeys = false,
      bool celsShared = false,
    }) => referenceLetGo(
      cut: cutOf(row),
      layer: row,
      others: (keys: othersKeepKeys, cels: celsShared),
      nameIsFree: (property, name) => true,
    );

    test('a row its transform carries the move of takes it as keys — the '
        'track the carry makes, its switch on', () {
      final row = paper(laid: laid, pose: fitted);

      final way = wayOf(row);

      expect(way, isA<ReferenceMoveKeyed>());
      way as ReferenceMoveKeyed;
      expect(way.track, carried(row));
      expect(way.enabled, isTrue);
    });

    test('🎯① the switch comes on where it shows nothing new on the rows '
        'wearing the head with it; where one keeps keys of its own the row '
        'bakes instead — and waits where its cels are shared too '
        '(F-374-Q10)', () {
      final off = paper(laid: laid, pose: fitted, transformEnabled: false);

      final alone = wayOf(off);
      expect(alone, isA<ReferenceMoveKeyed>());
      expect((alone as ReferenceMoveKeyed).enabled, isTrue);
      expect(wayOf(off, othersKeepKeys: true), isA<ReferenceMoveBaked>());
      expect(
        wayOf(off, othersKeepKeys: true, celsShared: true),
        isA<ReferenceMoveWaits>(),
      );
    });

    test('a switch that stays as it is shows no other row anything — keys '
        'kept on the rows wearing the head do not stop the keys', () {
      expect(
        wayOf(paper(laid: laid, pose: fitted), othersKeepKeys: true),
        isA<ReferenceMoveKeyed>(),
      );
      final standing = wayOf(
        paper(laid: laid, transformEnabled: false),
        othersKeepKeys: true,
        celsShared: true,
      );
      expect(standing, isA<ReferenceMoveKeyed>());
      expect((standing as ReferenceMoveKeyed).enabled, isFalse);
    });

    test('🎯②③ a still reference its transform cannot carry bakes — an '
        'attach row, a shear — and one that MOVES waits (F-374-Q9)', () {
      final attached = paper(
        laid: laid,
        pose: fitted,
        attachedTo: const LayerId('a'),
      );
      final sheared = paper(
        laid: laid,
        pose: TransformPose(center: middle, rotationDegrees: 30),
        own: uneven,
      );

      expect(wayOf(attached), isA<ReferenceMoveBaked>());
      expect(wayOf(sheared), isA<ReferenceMoveBaked>());
      expect(
        wayOf(
          paper(
            laid: laid,
            fx: moving,
            attachedTo: const LayerId('a'),
          ),
        ),
        isA<ReferenceMoveWaits>(),
      );
    });

    test('a movie its transform cannot carry bakes moving or not — a cel '
        'a position — and waits only where its cels are shared', () {
      final movie = paper(
        laid: laid,
        fx: moving,
        attachedTo: const LayerId('a'),
        file: '/clip.mp4',
      );

      expect(wayOf(movie), isA<ReferenceMoveBaked>());
      expect(wayOf(movie, celsShared: true), isA<ReferenceMoveWaits>());
    });

    test('shared cels stop a bake, never the keys', () {
      expect(
        wayOf(paper(laid: laid, pose: fitted), celsShared: true),
        isA<ReferenceMoveKeyed>(),
      );
      expect(
        wayOf(
          paper(laid: laid, pose: fitted, attachedTo: const LayerId('a')),
          celsShared: true,
        ),
        isA<ReferenceMoveWaits>(),
      );
    });
  });
}
