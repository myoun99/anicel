import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/transform_track.dart'
    show lerpArgb, lerpBoolHold;
import 'package:anicel/src/ui/timeline/se_name_tag_lane_editing.dart';
import 'package:anicel/src/ui/timeline/se_name_tag_lane_policy.dart';

/// R5 #7 — the name tag's keyable members.
///
/// Static slot plus track, the `EffectParameter` shape: an unkeyed member
/// is a plain value and keying is additive, so nothing about an untouched
/// tag changes.
void main() {
  PropertyTrack<T> keyed<T>(Map<int, T> keys, {bool hold = false}) =>
      keys.entries.fold<PropertyTrack<T>>(
        PropertyTrack<T>(),
        (track, entry) => track.withKey(
          entry.key,
          entry.value,
          interpolation: hold
              ? PropertyKeyInterpolation.hold
              : PropertyKeyInterpolation.linear,
        ),
      );

  group('the lerps the new value kinds need', () {
    test('colour interpolates per channel, and stays in range', () {
      expect(lerpArgb(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080);
      expect(lerpArgb(0xFF000000, 0xFFFFFFFF, 0), 0xFF000000);
      expect(lerpArgb(0xFF000000, 0xFFFFFFFF, 1), 0xFFFFFFFF);
      // Alpha is a channel like any other.
      expect(lerpArgb(0x00FF0000, 0xFFFF0000, 0.5) >> 24 & 0xFF, 0x80);
    });

    test('a boolean HOLDS — half a shown line is not a state', () {
      expect(lerpBoolHold(true, false, 0.99), isTrue);
      expect(lerpBoolHold(false, true, 0.99), isFalse);
    });
  });

  group('resolveAt', () {
    test('an unkeyed tag resolves to ITSELF — no copy, no change', () {
      const tag = SeNameTag();
      expect(identical(tag.resolveAt(7), tag), isTrue);
    });

    test('a keyed ink tweens through the frames between', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(
          nameInk: keyed({0: 0xFF000000, 10: 0xFFFFFFFF}),
        ),
      );
      expect(tag.resolveAt(0).style.color, 0xFF000000);
      expect(tag.resolveAt(5).style.color, 0xFF808080);
      expect(tag.resolveAt(10).style.color, 0xFFFFFFFF);
    });

    test('size, tracking and bold drive BOTH runs — one lane, two runs, '
        'which is the grouping the user asked for', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(
          fontSize: keyed({0: 20.0}),
          letterSpacing: keyed({0: 4.0}),
          bold: keyed({0: false}, hold: true),
        ),
      );
      final resolved = tag.resolveAt(0);
      expect(resolved.style.fontSize, 20);
      expect(resolved.lineStyle.fontSize, 20);
      expect(resolved.style.letterSpacing, 4);
      expect(resolved.lineStyle.letterSpacing, 4);
      expect(resolved.style.bold, isFalse);
      expect(resolved.lineStyle.bold, isFalse);
    });

    test('an UNKEYED member keeps the static slot while a keyed one moves',
        () {
      final tag = SeNameTag(track: SeNameTagTrack(fontSize: keyed({0: 20.0})));
      final resolved = tag.resolveAt(0);
      expect(resolved.style.fontSize, 20, reason: 'keyed');
      expect(
        resolved.style.color,
        SeNameTag.defaultStyle.color,
        reason: 'unkeyed members are still the plain value',
      );
    });

    test('showLine holds until its next key', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(showLine: keyed({0: true, 10: false})),
      );
      expect(tag.resolveAt(0).showLine, isTrue);
      expect(tag.resolveAt(9).showLine, isTrue, reason: 'held, not tweened');
      expect(tag.resolveAt(10).showLine, isFalse);
    });
  });

  group('JSON', () {
    test('an untouched tag writes NO keys field — keying is additive', () {
      const tag = SeNameTag();
      expect(tag.toJson().containsKey('keys'), isFalse);
      expect(SeNameTag.fromJson(tag.toJson()).track, isNull);
    });

    test('a keyed tag round-trips, interpolation included', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(
          nameInk: keyed({3: 0xFF123456}),
          showLine: keyed({3: false}, hold: true),
        ),
      );
      final back = SeNameTag.fromJson(tag.toJson());
      expect(back.track!.nameInk.keyAt(3)!.value, 0xFF123456);
      expect(back.track!.showLine.keyAt(3)!.value, isFalse);
      expect(
        back.track!.showLine.keyAt(3)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
      expect(back, tag, reason: 'equality carries the track');
    });
  });

  group('the lane verbs', () {
    test('toggling a key freezes the RESOLVED value, and toggling again '
        'removes it', () {
      const tag = SeNameTag();
      final keyedTag = seNameTagWithLaneKeyToggled(
        tag,
        laneId: seNameTagNameInkLaneId,
        frameIndex: 4,
      )!;
      expect(
        keyedTag.track!.nameInk.keyAt(4)!.value,
        SeNameTag.defaultStyle.color,
      );

      final cleared = seNameTagWithLaneKeyToggled(
        keyedTag,
        laneId: seNameTagNameInkLaneId,
        frameIndex: 4,
      )!;
      expect(cleared.track!.nameInk.isEmpty, isTrue);
    });

    test('a boolean key is authored HOLD, not left to tween', () {
      final keyedTag = seNameTagWithLaneKeyToggled(
        const SeNameTag(),
        laneId: seNameTagShowLineLaneId,
        frameIndex: 0,
      )!;
      expect(
        keyedTag.track!.showLine.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
    });

    test('keying the BOX when there is no box is refused — the toggle never '
        'promised to author the red box back on', () {
      const noBox = SeNameTag(
        style: TextCelStyle(color: 0xFFFFFFFF),
      );
      expect(
        seNameTagWithLaneKeyToggled(
          noBox,
          laneId: seNameTagBoxColorLaneId,
          frameIndex: 0,
        ),
        isNull,
      );
    });

    test('typing into an UNKEYED member writes the STATIC slot — it must '
        'not turn a plain value into an animated one', () {
      final edited = seNameTagWithLaneValueEdited(
        const SeNameTag(),
        laneId: seNameTagSizeLaneId,
        frameIndex: 6,
        input: '48',
      )!;
      expect(edited.style.fontSize, 48);
      expect(edited.lineStyle.fontSize, 48, reason: 'one lane, both runs');
      expect(edited.track, isNull, reason: 'no key was authored');
    });

    test('typing into a KEYED member keys at the playhead, AE-style', () {
      final tag = SeNameTag(track: SeNameTagTrack(fontSize: keyed({0: 20.0})));
      final edited = seNameTagWithLaneValueEdited(
        tag,
        laneId: seNameTagSizeLaneId,
        frameIndex: 6,
        input: '48',
      )!;
      expect(edited.track!.fontSize.keyAt(6)!.value, 48);
      expect(edited.style.fontSize, SeNameTag.defaultStyle.fontSize);
    });

    test('colours parse in the form the readout prints', () {
      expect(parseArgbInput('#123456'), 0xFF123456);
      expect(parseArgbInput('123456'), 0xFF123456);
      expect(parseArgbInput('80FF0000'), 0x80FF0000);
      expect(parseArgbInput('nope'), isNull);
      expect(formatSeNameTagLaneValue(
        seNameTagNameInkLaneId,
        const SeNameTag().resolveAt(0),
      ), '#FFFFFF');
    });

    test('a lane id from another group is refused', () {
      expect(
        seNameTagWithLaneValueEdited(
          const SeNameTag(),
          laneId: 'position',
          frameIndex: 0,
          input: '1, 2',
        ),
        isNull,
      );
      expect(laneIsSeNameTag('position'), isFalse);
      expect(laneIsSeNameTag(seNameTagGroupLaneId), isTrue);
      expect(laneIsSeNameTag(seNameTagSizeLaneId), isTrue);
    });
  });
}
