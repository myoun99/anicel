import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🚨F-414 (유저 2026-10-19): 「레이어의 fx에서 변형에는 헤더에 이름지으면
/// 보이는데 흐림 효과fx에는 헤더에 이름지어도 안보임 … 다른거도 확인하고 법
/// 통일」.
///
/// A named key shows its name on its lane, and a group header shows its
/// members' names the way it shows their marks — one union over whichever
/// family's members ([unionKeyNames]).
void main() {
  PropertyTrack<double> namedAtThree() =>
      PropertyTrack<double>().withKey(3, 1).withKeyName(3, 'A');
  PropertyTrack<CanvasPoint> placeNamedAtThree() => PropertyTrack<CanvasPoint>()
      .withKey(3, CanvasPoint(x: 1, y: 1))
      .withKeyName(3, 'A');

  test('the Transform header', () {
    final track = TransformTrack.empty().copyWith(rotation: namedAtThree());
    expect(
      transformUnionHeader(track: track, expanded: false).keyNames,
      {3: 'A'},
    );
  });

  for (final kind in EffectKind.values) {
    test('${kind.name}: the header and every member', () {
      final effect = LayerEffect(
        id: const EffectId('e'),
        kind: kind,
        parameters: {
          for (final spec in effectParametersOf(kind))
            spec.id: EffectParameter(track: namedAtThree()),
        },
        // I-65: where a cel number stands is among its members too.
        stand: TransformTrack.empty().copyWith(
          position: placeNamedAtThree(),
          scale: placeNamedAtThree(),
        ),
        // F-477: and the colour it is written in.
        ink: PropertyTrack<int>().withKey(3, 0xFF000000).withKeyName(3, 'A'),
      );
      final lanes = effectPropertyLanes([effect], isExpanded: (_) => true);
      expect(lanes.first.isGroupHeader, isTrue, reason: '⛔전제');
      for (final lane in lanes) {
        expect(lane.keyNames, {3: 'A'}, reason: lane.laneId);
      }
    });
  }

  test('the name tag: the header and the member keyed', () {
    final tag = SeNameTag(
      track: SeNameTagTrack(fontSize: namedAtThree()),
    );
    final lanes = seNameTagPropertyLanes(
      tag,
      expanded: true,
      resolveAt: (_) => tag,
    );
    expect(lanes.first.isGroupHeader, isTrue, reason: '⛔전제');
    expect(lanes.first.keyNames, {3: 'A'}, reason: 'the header');
    expect(
      lanes.singleWhere((lane) => lane.laneId == seNameTagSizeLaneId)
          .keyNames,
      {3: 'A'},
    );
  });
}
