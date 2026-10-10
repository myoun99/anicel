import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// **F-17 — a union mark says when its members disagree** (유저: 「**멤버
/// 타입이 서로 다르면 헤더에 동그라미**」), and since I-89 ② every mark is
/// After Effects' (유저 2026-10-10: 「ae식 반반등은 검증된 업계기준이라 아주
/// 마음에들어」): its left half the side arriving at the key, its right half
/// the side leaving it, the disagreement a hollow ring.
///
/// ↩️The union was a set of the keyed frames beside a set of the holding
/// ones and a set of the disagreeing ones, and a test walked every way the
/// keys could fall to prove no frame claimed two. A frame holds ONE mark
/// now ([PropertyLaneRow.keyMarks]), so that claim cannot be made.
void main() {
  TransformTrack trackWith({
    KeyExit? position,
    KeyExit? scale,
    KeyExit? rotation,
  }) {
    var track = TransformTrack.empty();
    if (position != null) {
      track = track.copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1, y: 1),
          outgoing: position,
        ),
      );
    }
    if (scale != null) {
      track = track.copyWith(
        scale: PropertyTrack<CanvasPoint>().withKey(
          4,
          uniformScale(2),
          outgoing: scale,
        ),
      );
    }
    if (rotation != null) {
      track = track.copyWith(
        rotation: PropertyTrack<double>().withKey(
          4,
          90,
          outgoing: rotation,
        ),
      );
    }
    return track;
  }

  const hold = KeyExit.hold;
  const linear = KeySide.linear;

  group('the derivation', () {
    test('every member holds — the frame holds', () {
      expect(transformKeyMarkUnion(trackWith(position: hold, scale: hold)), {
        4: _heldOut,
      });
    });

    test('no member holds — the frame is straight', () {
      expect(
        transformKeyMarkUnion(trackWith(position: linear, scale: linear)),
        {4: KeyMark.linear},
        reason: 'agreeing on "straight" is still agreeing',
      );
    });

    test('🚨they DISAGREE — the frame is mixed', () {
      expect(
        transformKeyMarkUnion(trackWith(position: hold, scale: linear)),
        {4: KeyMark.mixed},
      );
    });

    test('members that differ only in the side ARRIVING disagree too — a '
        'key\'s mark is both of its sides', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1, y: 1),
          incoming: const EaseSide(),
        ),
        scale: PropertyTrack<CanvasPoint>().withKey(4, uniformScale(2)),
      );
      expect(transformKeyMarkUnion(track), {4: KeyMark.mixed});
    });

    test('eases of different numbers are one kind — they agree', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1, y: 1),
          incoming: const EaseSide(),
        ),
        scale: PropertyTrack<CanvasPoint>().withKey(
          4,
          uniformScale(2),
          incoming: const EaseSide(influence: 0.5, speed: 0.2),
        ),
      );
      expect(transformKeyMarkUnion(track), {
        4: const SidesKeyMark(
          incoming: KeySideKind.ease,
          outgoing: KeySideKind.linear,
        ),
      });
    });

    test('a lone keyed member agrees with itself', () {
      expect(transformKeyMarkUnion(trackWith(position: hold)), {4: _heldOut});
      expect(transformKeyMarkUnion(trackWith(position: linear)), {
        4: KeyMark.linear,
      });
    });
  });

  group('what the rows say — every group header, one union', () {
    test('the Transform header', () {
      PropertyLaneRow headerFor(TransformTrack track) =>
          transformUnionHeader(track: track, expanded: false);
      expect(
        headerFor(trackWith(position: hold, scale: linear)).keyMarkAt(4),
        KeyMark.mixed,
      );
      expect(
        headerFor(trackWith(position: hold, scale: hold)).keyMarkAt(4),
        _heldOut,
      );
    });

    test('an effect\'s header', () {
      final effect = LayerEffect(
        id: const EffectId('e1'),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                3: const PropertyKey<double>(4, outgoing: KeyExit.hold),
                7: const PropertyKey<double>(2, outgoing: KeyExit.hold),
              },
            ),
          ),
          'blurY': EffectParameter(
            track: PropertyTrack<double>(
              keys: {7: const PropertyKey<double>(1)},
            ),
          ),
        },
      );
      final header = effectPropertyLanes(
        [effect],
        isExpanded: (_) => false,
      ).single;
      expect(header.isGroupHeader, isTrue);
      expect(header.keyMarks, {3: _heldOut, 7: KeyMark.mixed});
    });

    test('the name tag\'s header — and its flag lanes draw their holds', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(
          fontSize: PropertyTrack<double>().withKey(4, 12),
          bold: PropertyTrack<bool>()
              .withKey(4, true, outgoing: KeyExit.hold)
              .withKey(9, false, outgoing: KeyExit.hold),
        ),
      );
      final lanes = seNameTagPropertyLanes(
        tag,
        expanded: true,
        resolveAt: (_) => tag,
      );
      expect(lanes.first.keyMarks, {4: KeyMark.mixed, 9: _heldOut});
      expect(
        lanes.singleWhere((lane) => lane.laneId == seNameTagBoldLaneId)
            .keyMarks,
        {4: _heldOut, 9: _heldOut},
        reason: 'the flag lane used to draw every key it held as a diamond',
      );
    });

    test('⛔a MEMBER lane is never mixed — there is nothing to disagree '
        'with', () {
      final lanes = transformPropertyLanes(
        trackWith(position: hold, scale: linear),
        scaleForm: const TwoScales(),
      );
      for (final lane in lanes.where((lane) => !lane.isGroupHeader)) {
        expect(
          lane.keyMarks.values.whereType<MixedKeyMark>(),
          isEmpty,
          reason:
              '${lane.laneId}: a single key is what it is, and only a '
              'SUMMARY can be mixed',
        );
      }
    });
  });

  group('what it draws', () {
    const labelColor = Color(0xFF123456);

    /// The marker's painting, at a 12px box — the mark's own 12-unit grid,
    /// so a point below is a point of the drawing.
    Future<RenderObject> pumpMarker(
      WidgetTester tester,
      KeyMark mark, {
      bool selected = false,
      Axis axis = Axis.horizontal,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: TimelineLaneKeyMarker(
                  mark: mark,
                  axis: axis,
                  markerSize: 12,
                  color: labelColor,
                  selected: selected,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.renderObject(
        find.descendant(
          of: find.byType(TimelineLaneKeyMarker),
          matching: find.byType(CustomPaint),
        ),
      );
    }

    SidesKeyMark sides(KeySideKind incoming, KeySideKind outgoing) =>
        SidesKeyMark(incoming: incoming, outgoing: outgoing);

    testWidgets('the mark is the row\'s COLOUR LABEL with no outline of its '
        'own — only the selection rings it, inside (유저 2026-09-12)', (
      tester,
    ) async {
      final plain = await pumpMarker(tester, KeyMark.linear);
      expect(plain, paints..path(color: labelColor));
      expect(
        plain,
        paintsExactlyCountTimes(#drawPath, 1),
        reason: '「그냥 심플하게 바탕색만 남겨서」',
      );

      final ringed = await pumpMarker(tester, KeyMark.linear, selected: true);
      expect(
        ringed,
        paints
          ..path(color: labelColor)
          ..clipPath(
            pathMatcher: isPathThat(
              includes: [const Offset(5, 6)],
              excludes: [const Offset(1, 1)],
            ),
          )
          ..path(style: PaintingStyle.stroke, color: AppColors.accent),
        reason: 'the selection still speaks — in accent, inside the mark',
      );
    });

    testWidgets('on the X-sheet the mark STANDS: the half arriving faces the '
        'frames before the key, up the sheet — as the flip window\'s '
        'standing view turns the timeline', (tester) async {
      final drawn = await pumpMarker(tester, _heldOut, axis: Axis.vertical);
      expect(
        drawn,
        paints
          ..path(
            includes: const [Offset(1, 11), Offset(11, 11), Offset(6, 1)],
            excludes: const [Offset(1, 1), Offset(11, 1)],
          ),
        reason: 'the hold leaves DOWN the sheet; the straight side arrives '
            'from above',
      );
    });

    testWidgets('a straight key is a DIAMOND — two halves meeting', (
      tester,
    ) async {
      final drawn = await pumpMarker(tester, KeyMark.linear);
      expect(
        drawn,
        paints
          ..path(
            includes: const [
              Offset(5, 6),
              Offset(1, 6),
              Offset(11, 6),
              Offset(5.5, 1),
              Offset(6.5, 11),
            ],
            excludes: const [
              Offset(1, 1),
              Offset(11, 1),
              Offset(1, 11),
              Offset(11, 11),
            ],
          ),
      );
    });

    testWidgets('a hold is the RIGHT half a square — the side leaving', (
      tester,
    ) async {
      final drawn = await pumpMarker(tester, _heldOut);
      expect(
        drawn,
        paints
          ..path(
            includes: const [Offset(11, 1), Offset(11, 11), Offset(1, 6)],
            excludes: const [Offset(1, 1), Offset(1, 11)],
          ),
      );
    });

    testWidgets('an ease is half an HOURGLASS — corners on the key\'s line, '
        'none at its middle', (tester) async {
      final drawn = await pumpMarker(
        tester,
        sides(KeySideKind.ease, KeySideKind.ease),
      );
      expect(
        drawn,
        paints
          ..path(
            includes: const [
              Offset(5, 1),
              Offset(7, 1),
              Offset(5, 11),
              Offset(7, 11),
            ],
            excludes: const [Offset(1, 6), Offset(11, 6), Offset(1, 3)],
          ),
      );
    });

    testWidgets('a smooth pass is half a DISC', (tester) async {
      final drawn = await pumpMarker(
        tester,
        sides(KeySideKind.auto, KeySideKind.auto),
      );
      expect(
        drawn,
        paints
          ..path(
            includes: const [Offset(5, 6), Offset(1, 6), Offset(5.5, 1)],
            excludes: const [Offset(1, 1), Offset(11, 11)],
          ),
      );
    });

    testWidgets('mixed is a HOLLOW circle — a disc is a smooth pass now '
        '(유저 10-10 「추천대로」)', (tester) async {
      final drawn = await pumpMarker(tester, KeyMark.mixed);
      expect(
        drawn,
        paints
          ..path(
            includes: const [Offset(1, 6), Offset(5.5, 11)],
            excludes: const [Offset(6, 6), Offset(0.5, 0.5)],
          ),
      );
    });

    testWidgets('every half reaches the top and the bottom of ONE box, so the '
        'halves of any two kinds meet down the middle (유저 10-10 「모양의 '
        '크기는 동일한 느낌이 좋으니 찬성」)', (tester) async {
      for (final incoming in [
        KeySideKind.linear,
        KeySideKind.ease,
        KeySideKind.auto,
      ]) {
        for (final outgoing in KeySideKind.values) {
          final drawn = await pumpMarker(tester, sides(incoming, outgoing));
          expect(
            drawn,
            paints
              ..path(
                includes: const [Offset(5.9, 0.6), Offset(6.1, 11.4)],
              ),
            reason: '$incoming → $outgoing',
          );
        }
      }
    });
  });
}

/// A straight key that holds from there on — AE's Toggle Hold Keyframe.
const _heldOut = SidesKeyMark(
  incoming: KeySideKind.linear,
  outgoing: KeySideKind.hold,
);
