import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/key_mark_glyph.dart' show keyMarkPath;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/scale_lane_form.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// **F-17 — a union mark says when its members disagree** (유저: 「**멤버
/// 타입이 서로 다르면 헤더에 동그라미**」), and since I-89 ② every mark is
/// After Effects' (유저 2026-10-10: 「ae식 반반등은 검증된 업계기준이라 아주
/// 마음에들어」): its left half the side arriving at the key, its right half
/// the side leaving it, the disagreement a ◉ (F-367-Q2; ↩️a hollow ring).
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
    final row = Layer(
      id: const LayerId('row'),
      name: 'row',
      frames: const [],
      mark: const LayerMark(process: LayerProcess.finish),
    );
    final labelColor = layerMarkColor(row.mark);

    /// The marker's painting, at a 12px box unless [box] says otherwise —
    /// the mark's own 12-unit grid, so a point below is a point of the
    /// drawing.
    Future<RenderObject> pumpMarker(
      WidgetTester tester,
      KeyMark mark, {
      bool selected = false,
      Axis axis = Axis.horizontal,
      Size box = const Size.square(12),
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
                  markerSize: box,
                  layer: row,
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

    testWidgets('the selection rings the OUTLINE, as thin as UI-R23 #4 set it '
        '— never a bar down the middle where the halves meet', (tester) async {
      for (final mark in [
        KeyMark.linear,
        _heldOut,
        sides(KeySideKind.ease, KeySideKind.ease),
        sides(KeySideKind.auto, KeySideKind.linear),
      ]) {
        final ringed = await pumpMarker(tester, mark, selected: true);
        late Path ring;
        late Paint ink;
        expect(
          ringed,
          paints
            ..path(color: labelColor)
            ..clipPath()
            ..something((method, arguments) {
              if (method != #drawPath) {
                return false;
              }
              ring = arguments.first as Path;
              ink = arguments.last as Paint;
              return true;
            }),
        );
        expect(ink.style, PaintingStyle.stroke, reason: '$mark');
        // Twice the ring's 4/3, half of it clipped away — in the 32 bits a
        // paint keeps its width in.
        expect(
          ink.strokeWidth,
          moreOrLessEquals(8 / 3, epsilon: 1e-6),
          reason: '$mark',
        );
        expect(
          [
            for (final metric in ring.computeMetrics())
              for (var at = 0.0; at < metric.length; at += 0.1)
                if (metric.getTangentForOffset(at) case final tangent?
                    when (tangent.position.dx - 6).abs() < 1e-3 &&
                        tangent.vector.dx.abs() < 1e-3 &&
                        tangent.position.dy > 0.5 &&
                        tangent.position.dy < 11.5)
                  tangent.position,
          ],
          isEmpty,
          reason: '$mark: the ring runs down the middle there',
        );
      }
    });

    testWidgets('a key drawn again with another kind, ring or axis is '
        'painted again — the old mark never stays on screen', (tester) async {
      CustomPainter painter() => tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(TimelineLaneKeyMarker),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter!;
      await pumpMarker(tester, KeyMark.linear);
      var before = painter();
      for (final (what, pump) in [
        ('its kind', () => pumpMarker(tester, _heldOut)),
        ('its ring', () => pumpMarker(tester, _heldOut, selected: true)),
        (
          'its axis',
          () => pumpMarker(
            tester,
            _heldOut,
            selected: true,
            axis: Axis.vertical,
          ),
        ),
      ]) {
        await pump();
        expect(painter().shouldRepaint(before), isTrue, reason: what);
        before = painter();
      }
      await pumpMarker(tester, _heldOut, selected: true, axis: Axis.vertical);
      expect(
        painter().shouldRepaint(before),
        isFalse,
        reason: 'the same key is the same painting',
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

    // 🗣️F-367-Q4 (유저 2026-10-18 「세로 유지 · 가로만 줄임(프레임 블록처럼)」):
    // a box narrows along the frames and keeps its height across them.
    testWidgets('a box narrowed along the frames stands narrowed DOWN the '
        'sheet, its height across it kept', (tester) async {
      Size painted() => tester.getSize(
        find.descendant(
          of: find.byType(TimelineLaneKeyMarker),
          matching: find.byType(CustomPaint),
        ),
      );
      const box = Size(8, 12);
      final lying = await pumpMarker(tester, _heldOut, box: box);
      expect(painted(), box);
      expect(
        lying,
        paints
          ..path(
            includes: const [Offset(7, 1), Offset(7, 11), Offset(1, 6)],
            excludes: const [Offset(1, 1), Offset(1, 11)],
          ),
        reason: 'a diamond\'s half narrowed, its point on the box\'s edge',
      );
      final standing = await pumpMarker(
        tester,
        _heldOut,
        box: box,
        axis: Axis.vertical,
      );
      expect(painted(), box.flipped);
      expect(
        standing,
        paints
          ..path(
            includes: const [Offset(1, 7), Offset(11, 7), Offset(6, 1)],
            excludes: const [Offset(1, 1), Offset(11, 1)],
          ),
        reason: 'the same mark turned a quarter, in the box turned with it',
      );
    });

    test('🚨and EVERY mark fills its narrowed box, edge to edge — no shape '
        'keeps a square of its own inside it', () {
      const box = Size(8, 12);
      for (final mark in [
        for (final incoming in [
          KeySideKind.linear,
          KeySideKind.ease,
          KeySideKind.fast,
          KeySideKind.auto,
        ])
          for (final outgoing in KeySideKind.values) sides(incoming, outgoing),
        KeyMark.mixed,
      ]) {
        expect(
          keyMarkPath(mark, box).getBounds(),
          rectMoreOrLessEquals(Offset.zero & box, epsilon: 1e-5),
          reason: '$mark',
        );
      }
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

    testWidgets('「급하게」 is half a four-pointed STAR — a diamond\'s point, '
        'its sides drawn in toward the middle', (tester) async {
      final drawn = await pumpMarker(
        tester,
        sides(KeySideKind.fast, KeySideKind.fast),
      );
      expect(
        drawn,
        paints
          ..path(
            includes: const [
              Offset(1, 6),
              Offset(11, 6),
              Offset(6, 1),
              Offset(6, 11),
              Offset(4, 6),
            ],
            // Inside the straight side's diamond, outside the star.
            excludes: const [
              Offset(3.5, 3.5),
              Offset(8.5, 3.5),
              Offset(3.5, 8.5),
              Offset(8.5, 8.5),
            ],
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

    // 🗣️F-367-Q2 (유저 2026-10-16): 「혼합 ○도 고친다 — 구멍을 메우고 가는
    // 틈만 남긴다」 — 「로빙키로 착각했네. 혼합마크였네」: a name in the hole
    // sat on the band, black on dark. ↩️It was a HOLLOW circle (유저 10-10
    // 「추천대로」 — a disc is a smooth pass); the cut ring keeps it apart
    // from that disc still.
    testWidgets('mixed is a ring with a thin gap where its hole was, and a '
        'disc in it a name reads on', (tester) async {
      // The 12px box's middle is (6, 6); the ring's outside is 6 from it,
      // the gap from 4.8 in to 3.84, and the disc inside that.
      expect(
        await pumpMarker(tester, KeyMark.mixed),
        paints
          ..path(
            includes: const [
              Offset(6 - 5.4, 6),
              Offset(6, 6 + 5.4),
              Offset(6, 6),
              Offset(6 - 3.2, 6),
            ],
            excludes: const [Offset(6 - 4.3, 6), Offset(6, 6 + 4.3)],
          ),
      );
    });

    testWidgets('every half reaches the top and the bottom of ONE box, so the '
        'halves of any two kinds meet down the middle (유저 10-10 「모양의 '
        '크기는 동일한 느낌이 좋으니 찬성」)', (tester) async {
      for (final incoming in [
        KeySideKind.linear,
        KeySideKind.ease,
        KeySideKind.fast,
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
