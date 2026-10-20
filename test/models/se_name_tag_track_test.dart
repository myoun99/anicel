import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/transform_track.dart'
    show lerpArgb, lerpBoolHold;
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show PropertyLaneValueKind;
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
          outgoing: hold
              ? KeyExit.hold
              : KeySide.linear,
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
        back.track!.showLine.keyAt(3)!.outgoing,
        KeyExit.hold,
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
        keyedTag.track!.showLine.keyAt(0)!.outgoing,
        KeyExit.hold,
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

    test('🎯typing into an UNKEYED member KEYS it at the playhead, as an '
        'effect\'s parameter is — and the tag reads it at every frame '
        '(F-407)', () {
      final edited = seNameTagWithLaneValueEdited(
        const SeNameTag(),
        laneId: seNameTagSizeLaneId,
        frameIndex: 6,
        input: '48',
      )!;
      expect(edited.track!.fontSize.keyAt(6)!.value, 48);
      for (final frame in [0, 6, 30]) {
        final resolved = edited.resolveAt(frame);
        expect(resolved.style.fontSize, 48, reason: 'frame $frame');
        expect(
          resolved.lineStyle.fontSize,
          48,
          reason: 'one lane, both runs',
        );
      }
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

    test('🎯the group\'s Reset puts an UNKEYED member back to a new tag\'s '
        'look in its static slot — and keys none (F-374)', () {
      final edited = SeNameTag(
        style: SeNameTag.defaultStyle.copyWith(fontSize: 48),
        lineStyle: SeNameTag.defaultLineStyle.copyWith(fontSize: 48),
      );

      final reset = seNameTagWithGroupReset(edited, frameIndexes: const [3])!;

      expect(reset.style.fontSize, SeNameTag.defaultStyle.fontSize);
      expect(reset.lineStyle.fontSize, SeNameTag.defaultLineStyle.fontSize);
      expect(reset.track, isNull, reason: 'no key was authored');
    });

    test('a KEYED member takes the default AT the playhead, keeping its '
        'keys — and on a span, only the keys the span covers', () {
      final tag = SeNameTag(
        track: SeNameTagTrack(
          nameInk: keyed({0: 0xFF000000, 10: 0xFF00FF00}),
        ),
      );
      final ink = SeNameTag.defaultStyle.color;

      final atPlayhead = seNameTagWithGroupReset(
        tag,
        frameIndexes: const [5],
      )!;
      expect(atPlayhead.track!.nameInk.keyAt(5)!.value, ink);
      expect(
        atPlayhead.track!.nameInk.keyAt(0)!.value,
        0xFF000000,
        reason: 'no key deleted',
      );

      final spanned = seNameTagWithGroupReset(
        tag,
        frameIndexes: const [0, 1, 2, 3, 4, 5],
        keyedFramesOnly: true,
      )!;
      expect(spanned.track!.nameInk.keyAt(0)!.value, ink);
      expect(
        spanned.track!.nameInk.keyAt(5),
        isNull,
        reason: 'a span resets the keys it covers and authors none',
      );
    });

    test('a tag that already looks as a new one does is not reset — no '
        'step', () {
      expect(
        seNameTagWithGroupReset(const SeNameTag(), frameIndexes: const [0]),
        isNull,
      );
    });
  });

  group('🗣️the letter switches — bold, the lean, the lines under and '
      'through — are each ONE lane on both runs '
      '(text-letters-lean-and-underline-Q1, 유저 2026-10-17: 「일곱 전부」)', () {
    TextCelStyle allOff(TextCelStyle run) => run.copyWith(
      bold: false,
      italic: false,
      underline: false,
      strikethrough: false,
    );
    List<bool> switches(TextCelStyle run) => [
      run.bold,
      run.italic,
      run.underline,
      run.strikethrough,
    ];
    // Every switch off, so a verb that reads or writes another switch than
    // its own is seen.
    final off = SeNameTag(
      style: allOff(SeNameTag.defaultStyle),
      lineStyle: allOff(SeNameTag.defaultLineStyle),
    );

    for (final (laneId, label, read, write, lane) in [
      (
        seNameTagBoldLaneId,
        () => AppText.strings.seNameTagBoldLabel,
        (TextCelStyle run) => run.bold,
        (TextCelStyle run, bool on) => run.copyWith(bold: on),
        (SeNameTagTrack keys) => keys.bold,
      ),
      (
        seNameTagItalicLaneId,
        () => AppText.strings.seNameTagItalicLabel,
        (TextCelStyle run) => run.italic,
        (TextCelStyle run, bool on) => run.copyWith(italic: on),
        (SeNameTagTrack keys) => keys.italic,
      ),
      (
        seNameTagUnderlineLaneId,
        () => AppText.strings.seNameTagUnderlineLabel,
        (TextCelStyle run) => run.underline,
        (TextCelStyle run, bool on) => run.copyWith(underline: on),
        (SeNameTagTrack keys) => keys.underline,
      ),
      (
        seNameTagStrikethroughLaneId,
        () => AppText.strings.seNameTagStrikethroughLabel,
        (TextCelStyle run) => run.strikethrough,
        (TextCelStyle run, bool on) => run.copyWith(strikethrough: on),
        (SeNameTagTrack keys) => keys.strikethrough,
      ),
    ]) {
      // Only this switch on, on both runs.
      final lit = off.copyWith(
        style: write(off.style, true),
        lineStyle: write(off.lineStyle, true),
      );

      test('$laneId: a key freezes what it shows, HELD, and toggles away', () {
        final keyedTag = seNameTagWithLaneKeyToggled(
          lit,
          laneId: laneId,
          frameIndex: 4,
        )!;
        final key = lane(keyedTag.track!).keyAt(4)!;
        expect(key.value, isTrue);
        expect(key.outgoing, KeyExit.hold);

        final cleared = seNameTagWithLaneKeyToggled(
          keyedTag,
          laneId: laneId,
          frameIndex: 4,
        )!;
        expect(lane(cleared.track!).isEmpty, isTrue);
      });

      test('$laneId: keyed, it drives BOTH runs', () {
        final keyedTag = seNameTagWithLaneKeyToggled(
          lit,
          laneId: laneId,
          frameIndex: 0,
        )!;
        final resolved = keyedTag
            .copyWith(style: off.style, lineStyle: off.lineStyle)
            .resolveAt(3);

        expect(switches(resolved.style), switches(lit.style));
        expect(switches(resolved.lineStyle), switches(lit.lineStyle));
      });

      test('$laneId: typed into while unkeyed, it keys at the playhead, '
          'HELD — and both runs read it (F-407)', () {
        final edited = seNameTagWithLaneValueEdited(
          off,
          laneId: laneId,
          frameIndex: 6,
          input: 'on',
        )!;
        final key = lane(edited.track!).keyAt(6)!;
        final resolved = edited.resolveAt(0);

        expect(key.value, isTrue);
        expect(key.outgoing, KeyExit.hold);
        expect(switches(resolved.style), switches(lit.style));
        expect(switches(resolved.lineStyle), switches(lit.lineStyle));
      });

      test('$laneId: typed into while keyed, it keys at the playhead, '
          'HELD', () {
        final keyedTag = seNameTagWithLaneKeyToggled(
          off,
          laneId: laneId,
          frameIndex: 0,
        )!;
        final edited = seNameTagWithLaneValueEdited(
          keyedTag,
          laneId: laneId,
          frameIndex: 6,
          input: 'on',
        )!;
        final key = lane(edited.track!).keyAt(6)!;

        expect(key.value, isTrue);
        expect(key.outgoing, KeyExit.hold);
        expect(edited.style, off.style, reason: 'the plain value stays');
      });

      test('$laneId: the Reset takes it back to what a new tag has — the '
          'plain value on both runs, a key at the playhead, HELD', () {
        final fresh = read(SeNameTag.defaultStyle);
        final away = SeNameTag(
          style: write(SeNameTag.defaultStyle, !fresh),
          lineStyle: write(
            SeNameTag.defaultLineStyle,
            !read(SeNameTag.defaultLineStyle),
          ),
        );

        final reset = seNameTagWithGroupReset(away, frameIndexes: const [0])!;
        expect(reset.style, SeNameTag.defaultStyle);
        expect(reset.lineStyle, SeNameTag.defaultLineStyle);

        final keyed = seNameTagWithGroupReset(
          seNameTagWithLaneKeyToggled(away, laneId: laneId, frameIndex: 0)!,
          frameIndexes: const [5],
        )!;
        final key = lane(keyed.track!).keyAt(5)!;
        expect(key.value, fresh);
        expect(key.outgoing, KeyExit.hold);
        expect(
          lane(keyed.track!).keyAt(0)!.value,
          !fresh,
          reason: 'no key deleted',
        );
      });

      test('$laneId: keyed, the tag is another one, and comes back from its '
          'file', () {
        final keyed = seNameTagWithLaneKeyToggled(
          lit,
          laneId: laneId,
          frameIndex: 3,
        )!;

        expect(keyed.track, isNot(SeNameTagTrack.empty()));
        expect(keyed.track!.hashCode, isNot(SeNameTagTrack.empty().hashCode));
        expect(SeNameTag.fromJson(keyed.toJson()), keyed);
      });

      test('$laneId: reads on or off, takes a switch, and has its name', () {
        expect(formatSeNameTagLaneValue(laneId, lit.resolveAt(0)), 'on');
        expect(formatSeNameTagLaneValue(laneId, off.resolveAt(0)), 'off');
        expect(seNameTagLaneValueKind(laneId), PropertyLaneValueKind.boolean);
        expect(seNameTagLaneLabel(laneId), label());
      });
    }
  });
}
