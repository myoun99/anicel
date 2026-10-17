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
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show layerPlacementAt;
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show picturePlacement;
import 'package:anicel/src/services/project_repository.dart';
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
    String id = 'paper',
  }) => Layer(
    id: LayerId(id),
    name: id,
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

  ReferenceCarry carryOf(
    Layer row, {
    bool Function(TransformPropertyId property, String name)? nameIsFree,
  }) => transformCarryingReferenceMove(
    cut: cutOf(row),
    layer: row,
    nameIsFree: nameIsFree ?? (property, name) => true,
  );

  ({TransformTrack track, bool enabled})? carriedWithSwitch(
    Layer row, {
    bool Function(TransformPropertyId property, String name)? nameIsFree,
  }) => switch (carryOf(row, nameIsFree: nameIsFree)) {
    ReferenceCarried(:final track, :final enabled) => (
      track: track,
      enabled: enabled,
    ),
    ReferenceUncarried() => null,
  };

  /// Why [row]'s own transform cannot carry its move — null where it can.
  ReferenceWait? whyUncarried(Layer row) => switch (carryOf(row)) {
    ReferenceUncarried(:final why) => why,
    ReferenceCarried() => null,
  };

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
    expect(
      track.position.keys[0]!.path,
      KeyPath.auto,
      reason: 'written as every new Position key is (`positionLaneKeyed`)',
    );
    expect(valuesOf(track.scale), {0: CanvasPoint(x: 1.5, y: 1.5)});
    expect(valuesOf(track.rotation), {0: 30.0});
    expect(strayed(row, track, frames(4)), lessThan(1e-9));
  });

  test('a lane the fx leaves as the row had it stays the row\'s own — its '
      'key where the row keyed it, and its opacity', () {
    final own = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(7, 15),
      opacity: PropertyTrack<double>().withKey(3, 0.4),
    );
    final row = paper(
      laid: TransformPose(center: middle),
      pose: TransformPose(center: CanvasPoint(x: 260, y: 150)),
      own: own,
    );

    final track = carried(row)!;

    expect(valuesOf(track.rotation), {7: 15.0});
    expect(track.opacity, own.opacity);
    expect(track.scale.isEmpty, isTrue);
    expect(track.position.keys.keys, [0]);
    expect(strayed(row, track, frames(10)), lessThan(1e-9));
  });

  test('a lane the two moves together leave at its identity is none — the '
      'row\'s own key of it gives way', () {
    final row = paper(
      laid: TransformPose(center: offMiddle),
      pose: TransformPose(center: offMiddle, rotationDegrees: -15),
      own: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(7, 15),
      ),
    );

    final track = carried(row)!;

    expect(track.rotation.isEmpty, isTrue);
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

  test('🎯frame by frame, a lane is keyed on every frame either move keys '
      'it — the row\'s own keys as well, though no way between needs them '
      '— and a lane neither keys is ONE key where the row starts', () {
    final row = paper(
      laid: TransformPose(center: middle),
      pose: TransformPose(center: middle, rotationDegrees: 30),
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, middle)
            .withKey(24, CanvasPoint(x: 224, y: 150)),
        scale: PropertyTrack<CanvasPoint>().withKey(
          7,
          CanvasPoint(x: 1.5, y: 1.5),
        ),
      ),
      own: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>()
            .withKey(0, middle)
            .withKey(10, CanvasPoint(x: 210, y: 150))
            .withKey(24, CanvasPoint(x: 224, y: 150)),
      ),
      from: 2,
    );

    final track = carried(row)!;

    expect(
      valuesOf(track.position),
      {
        0: middle,
        10: CanvasPoint(x: 220, y: 150),
        24: CanvasPoint(x: 248, y: 150),
      },
      reason: 'the row\'s key on 10 stands, though the way is straight',
    );
    expect(
      valuesOf(track.scale),
      {7: CanvasPoint(x: 1.5, y: 1.5)},
      reason: 'the fx\'s one key, on its frame',
    );
    expect(valuesOf(track.rotation), {2: 30.0});
    expect(strayed(row, track, frames(30)), lessThan(1e-9));
  });

  test('frame by frame, the row\'s own turn and scale keep their keys where '
      'the row keyed them, and its opacity is its own', () {
    final own = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>()
          .withKey(0, CanvasPoint(x: 2, y: 2))
          .withKey(12, CanvasPoint(x: 2, y: 2))
          .withKey(24, CanvasPoint(x: 2, y: 2)),
      rotation: PropertyTrack<double>()
          .withKey(0, 0)
          .withKey(10, 10)
          .withKey(24, 24),
      opacity: PropertyTrack<double>().withKey(0, 0.5),
    );
    final row = paper(
      laid: TransformPose(center: middle),
      fx: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 210, y: 150),
        ),
      ),
      own: own,
    );

    final track = carried(row)!;

    expect(valuesOf(track.rotation), {0: 0.0, 10: 10.0, 24: 24.0});
    expect(valuesOf(track.scale), {
      0: CanvasPoint(x: 2, y: 2),
      12: CanvasPoint(x: 2, y: 2),
      24: CanvasPoint(x: 2, y: 2),
    });
    expect(track.opacity, own.opacity);
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

  test('a turn the fx keys ONCE is the turn it stands the picture at all '
      'along — a quarter of it swaps an uneven row\'s two axes, and any '
      'other would shear', () {
    final uneven = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 2, y: 1)),
    );
    Layer turnedOnceBy(double degrees) => paper(
      laid: TransformPose(center: offMiddle),
      fx: TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>().withKey(5, degrees),
      ),
      own: uneven,
    );
    final quarter = turnedOnceBy(90);

    final track = carried(quarter)!;

    expect(valuesOf(track.scale), {0: CanvasPoint(x: 1, y: 2)});
    expect(valuesOf(track.rotation), {5: 90.0});
    expect(strayed(quarter, track, frames(8)), lessThan(1e-9));
    expect(whyUncarried(turnedOnceBy(30)), ReferenceWait.sheared);
  });

  test('a row scaled unevenly under a picture turned other than by a '
      'quarter would SHEAR it, which no pose does — nothing carries it, '
      'and that is why (F-374-Q7 · Q11)', () {
    final uneven = TransformTrack.empty().copyWith(
      scale: PropertyTrack<CanvasPoint>().withKey(0, CanvasPoint(x: 2, y: 1)),
    );
    final turned = TransformPose(center: offMiddle, rotationDegrees: 30);

    expect(
      whyUncarried(
        paper(
          laid: TransformPose(center: offMiddle),
          pose: turned,
          own: uneven,
        ),
      ),
      ReferenceWait.sheared,
    );
    expect(
      whyUncarried(
        paper(
          laid: TransformPose(center: offMiddle),
          fx: TransformTrack.empty().copyWith(
            rotation: PropertyTrack<double>().withKey(0, 0).withKey(12, 90),
          ),
          own: uneven,
        ),
      ),
      ReferenceWait.sheared,
      reason: 'a quarter turn keyed over frames passes every turn between',
    );
    expect(
      whyUncarried(
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
      ReferenceWait.sheared,
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
      whyUncarried(
        paper(
          laid: TransformPose(center: middle),
          pose: TransformPose(center: CanvasPoint(x: 260, y: 150)),
          attachedTo: const LayerId('a'),
        ),
      ),
      ReferenceWait.attached,
    );
  });

  test('a file laid other than 1:1 and upright has no move the row carries',
      () {
    final moved = TransformPose(center: CanvasPoint(x: 260, y: 150));

    expect(
      whyUncarried(
        paper(
          laid: TransformPose(center: middle, rotationDegrees: 10),
          pose: moved,
        ),
      ),
      ReferenceWait.laidAsFitted,
    );
    expect(
      whyUncarried(
        paper(laid: TransformPose(center: middle, scaleX: 0), pose: moved),
      ),
      ReferenceWait.laidAsFitted,
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

  group('referenceLetGo — keys, the cels, or waiting, every use of the '
      'cel together (F-374-Q7 · Q10 · Q11)', () {
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
    final turning = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(0, 0).withKey(12, 30),
    );
    final kept = TransformTrack.empty().copyWith(
      rotation: PropertyTrack<double>().withKey(0, 45),
    );
    const base = LayerId('a');

    ReferenceLetGo wayOf(List<Layer> uses, {bool othersKeepKeys = false}) =>
        referenceLetGo(
          uses: [for (final use in uses) (cut: cutOf(use), layer: use)],
          othersKeepKeys: othersKeepKeys,
        );

    ReferenceMoveCarried goes(
      List<Layer> uses, {
      bool othersKeepKeys = false,
    }) => switch (wayOf(uses, othersKeepKeys: othersKeepKeys)) {
      final ReferenceMoveCarried way => way,
      ReferenceMoveWaits(:final why) => fail('the uses wait: $why'),
    };

    ReferenceWait? whyWaits(List<Layer> uses, {bool othersKeepKeys = false}) =>
        switch (wayOf(uses, othersKeepKeys: othersKeepKeys)) {
          ReferenceMoveWaits(:final why) => why,
          ReferenceMoveCarried() => null,
        };

    test('a row its transform carries the move of takes it as keys — the '
        'track the carry makes, the switch as it was', () {
      final row = paper(laid: laid, pose: fitted);

      final way = goes([row]);

      expect(way.uses.single.use.layer, row);
      expect(way.uses.single.track, carried(row));
      expect(way.bakes, isFalse);
      expect(way.switchOn, isFalse, reason: 'it is on already');
    });

    test('🎯① the switch comes on where it shows nothing new on the rows '
        'wearing the head with it; where a row that is no use of the cel '
        'keeps keys of its own the row bakes instead — and waits, saying '
        'so, where its cel cannot take the move (F-374-Q10)', () {
      final off = paper(laid: laid, pose: fitted, transformEnabled: false);

      expect(goes([off]).switchOn, isTrue);
      final baked = goes([off], othersKeepKeys: true);
      expect(baked.bakes, isTrue);
      expect(baked.switchOn, isFalse);
      expect(baked.uses.single.track, off.transformTrack);
      expect(
        whyWaits([
          paper(laid: laid, fx: moving, transformEnabled: false),
        ], othersKeepKeys: true),
        ReferenceWait.othersKeepKeys,
      );
    });

    test('a switch that stays as it is shows no other row anything — keys '
        'kept on the rows wearing the head do not stop the keys', () {
      expect(
        goes([paper(laid: laid, pose: fitted)], othersKeepKeys: true).bakes,
        isFalse,
      );
      final standing = goes([
        paper(laid: laid, transformEnabled: false),
      ], othersKeepKeys: true);
      expect(standing.bakes, isFalse);
      expect(standing.switchOn, isFalse);
    });

    test('🎯②③ a still reference its transform cannot carry bakes — an '
        'attach row, a shear — and one that MOVES waits, saying why '
        '(F-374-Q9 · Q11)', () {
      final attached = goes([
        paper(laid: laid, pose: fitted, attachedTo: base),
      ]);
      final sheared = goes([
        paper(
          laid: laid,
          pose: TransformPose(center: middle, rotationDegrees: 30),
          own: uneven,
        ),
      ]);

      expect(attached.bakes, isTrue);
      expect(sheared.bakes, isTrue);
      expect(
        whyWaits([paper(laid: laid, fx: moving, attachedTo: base)]),
        ReferenceWait.attached,
      );
      expect(
        whyWaits([paper(laid: laid, fx: turning, own: uneven)]),
        ReferenceWait.sheared,
      );
    });

    test('a movie its transform cannot carry bakes moving or not — a cel a '
        'position — and one it carries takes the keys', () {
      expect(
        goes([
          paper(laid: laid, fx: moving, attachedTo: base, file: '/clip.mp4'),
        ]).bakes,
        isTrue,
      );
      expect(
        goes([paper(laid: laid, pose: fitted, file: '/clip.mp4')]).bakes,
        isFalse,
      );
    });

    test('🎯every use of a still takes its own move as keys, and where the '
        'switch they share comes on, the keys each kept while it was off '
        'give way — a use with no move of its own as well (F-374-Q10)', () {
      final row = paper(laid: laid, pose: fitted, transformEnabled: false);
      final copy = paper(
        id: 'copy',
        laid: laid,
        pose: TransformPose(center: offMiddle),
        own: kept,
        transformEnabled: false,
      );
      final standing = paper(
        id: 'standing',
        laid: laid,
        own: kept,
        transformEnabled: false,
      );

      final way = goes([row, copy, standing]);

      expect(way.switchOn, isTrue);
      expect(way.bakes, isFalse);
      expect([for (final use in way.uses) use.track], [
        carried(row),
        carried(copy),
        TransformTrack.empty(),
      ]);
    });

    test('🎯a still whose one cel has to take the picture takes it where '
        'every use shows it at one place — and where they show it apart, '
        'a use that is no reference among them, every use waits '
        '(F-374-Q10: 「쓰임마다 참조 fx 가 다르면 한 셀에 담을 수 없어, '
        '그때는 막힙니다」)', () {
      final attached = paper(laid: laid, pose: fitted, attachedTo: base);
      final copy = paper(id: 'copy', laid: laid, pose: fitted, own: kept);

      final way = goes([attached, copy]);

      expect([for (final use in way.uses) use.asShown], [true, true]);
      expect([for (final use in way.uses) use.track], [
        attached.transformTrack,
        kept,
      ]);
      expect(way.switchOn, isFalse);
      expect(
        whyWaits([
          attached,
          paper(
            id: 'copy',
            laid: laid,
            pose: TransformPose.uniform(center: middle, zoom: 0.25),
          ),
        ]),
        ReferenceWait.usesApart,
      );
      expect(
        whyWaits([
          attached,
          paper(id: 'drawn', laid: laid).copyWith(mediaReference: null),
        ]),
        ReferenceWait.usesApart,
      );
    });

    test('a use whose still MOVES on a transform that cannot carry it holds '
        'every use back, a use whose own could — the keys are all or none '
        '(F-374-Q10 · Q11)', () {
      final carriable = paper(laid: laid, fx: moving);

      expect(
        whyWaits([
          carriable,
          paper(id: 'copy', laid: laid, fx: moving, attachedTo: base),
        ]),
        ReferenceWait.attached,
      );
      expect(
        whyWaits([
          carriable,
          paper(id: 'copy', laid: laid, pose: fitted, attachedTo: base),
        ]),
        ReferenceWait.attached,
        reason: 'the cel would have to take a move one use makes',
      );
    });

    test('🎯a movie\'s uses each take their own way — the keys where a '
        'transform carries the move, its frames as shown where none does — '
        'and where the switch comes on, the keys a use showing its frames '
        'kept while it was off give way (F-374-Q10)', () {
      final keyedMovie = paper(
        laid: laid,
        pose: fitted,
        file: '/clip.mp4',
        transformEnabled: false,
      );
      final attachedMovie = paper(
        id: 'copy',
        laid: laid,
        fx: moving,
        own: kept,
        attachedTo: base,
        file: '/clip.mp4',
        transformEnabled: false,
      );

      final way = goes([keyedMovie, attachedMovie]);

      expect(way.switchOn, isTrue);
      expect([for (final use in way.uses) use.asShown], [false, true]);
      expect([for (final use in way.uses) use.track], [
        carried(keyedMovie),
        TransformTrack.empty(),
      ]);

      final showing = goes([
        keyedMovie,
        attachedMovie,
      ], othersKeepKeys: true);
      expect(showing.switchOn, isFalse);
      expect([for (final use in showing.uses) use.asShown], [true, true]);
      expect([for (final use in showing.uses) use.track], [
        keyedMovie.transformTrack,
        kept,
      ]);
    });

    test('the uses are one naming space: a name two of them carry is '
        'neither\'s, one another use keeps on its own track stays its own, '
        'and one only keys that give way held is free', () {
      TransformTrack named(String name) => TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {
            0: PropertyKey(middle, name: name),
            12: PropertyKey(CanvasPoint(x: 260, y: 150)),
          },
        ),
      );
      String? nameOn(ReferenceUseLetGo use, int frame) =>
          use.track.position.keys[frame]?.name;
      final row = paper(laid: laid, fx: named('up'));
      final holding = TransformTrack.empty().copyWith(
        position: PropertyTrack(
          keys: {3: PropertyKey(offMiddle, name: 'up')},
        ),
      );

      final both = goes([row, paper(id: 'copy', laid: laid, fx: named('up'))]);
      expect([for (final use in both.uses) nameOn(use, 0)], [null, null]);

      final alone = goes([row, paper(id: 'copy', laid: laid)]);
      expect(nameOn(alone.uses.first, 0), 'up');

      final taken = goes([row, paper(id: 'copy', laid: laid, own: holding)]);
      expect(nameOn(taken.uses.first, 0), isNull);
      expect(nameOn(taken.uses.last, 3), 'up');

      final freed = goes([
        paper(laid: laid, fx: named('up'), transformEnabled: false),
        paper(id: 'copy', laid: laid, own: holding, transformEnabled: false),
      ]);
      expect(nameOn(freed.uses.first, 0), 'up');
      expect(freed.uses.last.track, TransformTrack.empty());
    });
  });

  group('referenceLetGoOf — a row that wears the uses\' head but shows none '
      'of their cels: the conte of another cut of the track (F-374-Q10)', () {
    final laid = TransformPose(center: middle);
    final fitted = TransformPose.uniform(center: middle, zoom: 0.5);

    /// How a rasterize lets go of cut `a`'s conte — a reference its fx fits,
    /// its switch off — on a track whose cut `b` has a conte keeping [kept]
    /// of its own: one head, two cuts' cels.
    ReferenceLetGo wayOfTheConte({TransformTrack? kept}) {
      final conte = paper(
        id: 'a-conte',
        laid: laid,
        pose: fitted,
        transformEnabled: false,
      ).copyWith(kind: LayerKind.storyboard);
      final other = Layer(
        id: const LayerId('b-conte'),
        name: 'Conte',
        kind: LayerKind.storyboard,
        frames: [
          Frame(id: const FrameId('b-panel'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('b-panel'), length: 1),
        },
        transformTrack: kept,
        transformEnabled: false,
      );
      Cut cut(String id, Layer layer) => Cut(
        id: CutId(id),
        name: id,
        layers: [layer],
        duration: 48,
        canvasSize: canvas,
      );
      final project = Project(
        id: const ProjectId('one-head'),
        name: 'One head',
        createdAt: DateTime.utc(2026, 10, 18),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [cut('a', conte), cut('b', other)],
          ),
        ],
      );
      return CutCommandCoordinator(
        repository: ProjectRepository(initialProject: project),
        editingSession: EditingSessionState(activeCutId: const CutId('a')),
        historyManager: HistoryManager(),
      ).referenceLetGoOf(
        cutId: const CutId('a'),
        layerId: const LayerId('a-conte'),
      );
    }

    test('🎯where that row keeps no keys of its own, the switch comes on '
        'with the keys — where it keeps some, the cel takes the picture '
        'instead, and the keys it kept are never shown', () {
      expect(
        wayOfTheConte(),
        isA<ReferenceMoveCarried>()
            .having((way) => way.switchOn, 'switchOn', isTrue)
            .having((way) => way.bakes, 'bakes', isFalse),
      );
      expect(
        wayOfTheConte(
          kept: TransformTrack.empty().copyWith(
            rotation: PropertyTrack<double>().withKey(0, 45),
          ),
        ),
        isA<ReferenceMoveCarried>()
            .having((way) => way.switchOn, 'switchOn', isFalse)
            .having((way) => way.bakes, 'bakes', isTrue),
      );
    });
  });
}
