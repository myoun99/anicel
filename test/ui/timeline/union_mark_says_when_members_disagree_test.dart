import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_range_move.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// **F-17 — the union mark had two shapes and three cases.**
///
/// 유저: 「**멤버 타입이 서로 다르면 헤더에 동그라미**」.
///
/// ■ where every keyed member holds, ◆ everywhere else — so "they all
/// interpolate" and "they disagree" drew the same mark, and the header
/// claimed an agreement that was not there.
///
/// ⚠️A ○ used to exist: the camera row's summary was a text glyph channel
/// with its own ◆/■/○ table, and the 2026-08-17 unification folded it into
/// the hold union, which has no room for a third answer. It comes back as
/// ONE derivation both the camera row and the fx header read — which is
/// what that unification was for.
void main() {
  TransformTrack trackWith({
    PropertyKeyInterpolation? position,
    PropertyKeyInterpolation? scale,
    PropertyKeyInterpolation? rotation,
  }) {
    var track = TransformTrack.empty();
    if (position != null) {
      track = track.copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          4,
          CanvasPoint(x: 1, y: 1),
          interpolation: position,
        ),
      );
    }
    if (scale != null) {
      track = track.copyWith(
        scale: PropertyTrack<double>().withKey(4, 2, interpolation: scale),
      );
    }
    if (rotation != null) {
      track = track.copyWith(
        rotation: PropertyTrack<double>().withKey(
          4,
          90,
          interpolation: rotation,
        ),
      );
    }
    return track;
  }

  const hold = PropertyKeyInterpolation.hold;
  const smooth = PropertyKeyInterpolation.linear;

  group('the derivation', () {
    test('every member holds — the frame is HOLD, not mixed', () {
      final track = trackWith(position: hold, scale: hold);
      expect(transformKeyHoldUnion(track), {4});
      expect(transformKeyMixedUnion(track), isEmpty);
    });

    test('no member holds — the frame is neither', () {
      final track = trackWith(position: smooth, scale: smooth);
      expect(transformKeyHoldUnion(track), isEmpty);
      expect(
        transformKeyMixedUnion(track),
        isEmpty,
        reason: 'agreeing on "not hold" is still agreeing',
      );
    });

    test('🚨they DISAGREE — the frame is mixed, and NOT hold', () {
      final track = trackWith(position: hold, scale: smooth);
      expect(
        transformKeyHoldUnion(track),
        isEmpty,
        reason:
            'this is the case that used to draw the same ◆ as "all smooth"',
      );
      expect(transformKeyMixedUnion(track), {4});
    });

    test('⛔a frame can never be in BOTH sets, however the keys fall', () {
      for (final position in [hold, smooth, null]) {
        for (final scale in [hold, smooth, null]) {
          for (final rotation in [hold, smooth, null]) {
            final track = trackWith(
              position: position,
              scale: scale,
              rotation: rotation,
            );
            expect(
              transformKeyHoldUnion(
                track,
              ).intersection(transformKeyMixedUnion(track)),
              isEmpty,
              reason: '$position/$scale/$rotation claimed both',
            );
          }
        }
      }
    });

    test('a lone keyed member agrees with itself', () {
      expect(transformKeyMixedUnion(trackWith(position: hold)), isEmpty);
      expect(transformKeyHoldUnion(trackWith(position: hold)), {4});
      expect(transformKeyMixedUnion(trackWith(position: smooth)), isEmpty);
    });
  });

  group('what the row says', () {
    PropertyLaneRow headerFor(TransformTrack track) =>
        transformUnionHeader(track: track, expanded: false);

    test('the shape is resolved from the sets, once', () {
      expect(
        headerFor(trackWith(position: hold, scale: smooth)).keyShapeAt(4),
        PropertyLaneKeyShape.mixed,
      );
      expect(
        headerFor(trackWith(position: hold, scale: hold)).keyShapeAt(4),
        PropertyLaneKeyShape.hold,
      );
      expect(
        headerFor(trackWith(position: smooth, scale: smooth)).keyShapeAt(4),
        PropertyLaneKeyShape.smooth,
      );
    });

    test('⛔a MEMBER lane can never be mixed — there is nothing to disagree '
        'with', () {
      final lanes = transformPropertyLanes(
        trackWith(position: hold, scale: smooth),
      );
      for (final lane in lanes.where((lane) => !lane.isGroupHeader)) {
        expect(
          lane.mixedFrames,
          isEmpty,
          reason:
              '${lane.laneId}: a single key holds or it does not, and only a '
              'SUMMARY can be mixed',
        );
      }
    });
  });

  group('what it draws', () {
    const labelColor = Color(0xFF123456);

    Future<void> pumpMarker(
      WidgetTester tester,
      PropertyLaneKeyShape shape, {
      bool selected = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: TimelineLaneKeyMarker(
                  shape: shape,
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
    }

    /// ⚠️Scoped to the marker's OWN subtree: `find.byType(Transform)` alone
    /// matches the ones MaterialApp puts up the tree, so "is it rotated"
    /// came back true for every shape — the instrument, not the code.
    ({BoxShape shape, bool rotated}) drawn(WidgetTester tester) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(TimelineLaneKeyMarker),
          matching: find.byType(Container),
        ),
      );
      return (
        shape: (container.decoration! as BoxDecoration).shape,
        rotated: find
            .descendant(
              of: find.byType(TimelineLaneKeyMarker),
              matching: find.byType(Transform),
            )
            .evaluate()
            .isNotEmpty,
      );
    }

    testWidgets('the mark is the row\'s COLOUR LABEL with no outline of its '
        'own — only the selection rings it (유저 2026-09-12)', (tester) async {
      await pumpMarker(tester, PropertyLaneKeyShape.smooth);
      final plain = tester.widget<Container>(
        find.descendant(
          of: find.byType(TimelineLaneKeyMarker),
          matching: find.byType(Container),
        ),
      );
      expect((plain.decoration! as BoxDecoration).color, labelColor);
      expect(
        (plain.decoration! as BoxDecoration).border,
        isNull,
        reason: '「그냥 심플하게 바탕색만 남겨서」',
      );

      await pumpMarker(tester, PropertyLaneKeyShape.smooth, selected: true);
      final ringed = tester.widget<Container>(
        find.descendant(
          of: find.byType(TimelineLaneKeyMarker),
          matching: find.byType(Container),
        ),
      );
      expect((ringed.decoration! as BoxDecoration).color, labelColor);
      expect(
        (ringed.decoration! as BoxDecoration).border,
        isNotNull,
        reason: 'the selection still speaks — in accent, colour alone',
      );
    });

    testWidgets('mixed is a CIRCLE, and never rotated', (tester) async {
      await pumpMarker(tester, PropertyLaneKeyShape.mixed);
      final mark = drawn(tester);
      expect(mark.shape, BoxShape.circle);
      expect(mark.rotated, isFalse, reason: 'a turned circle is the same');
    });

    testWidgets('hold is a SQUARE (the AE convention, unchanged)', (
      tester,
    ) async {
      await pumpMarker(tester, PropertyLaneKeyShape.hold);
      final mark = drawn(tester);
      expect(mark.shape, BoxShape.rectangle);
      expect(mark.rotated, isFalse);
    });

    testWidgets('smooth is a DIAMOND — the square, turned', (tester) async {
      await pumpMarker(tester, PropertyLaneKeyShape.smooth);
      final mark = drawn(tester);
      expect(mark.shape, BoxShape.rectangle);
      expect(mark.rotated, isTrue, reason: 'a diamond IS the square, turned');
    });
  });
}
