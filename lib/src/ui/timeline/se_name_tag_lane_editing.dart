// Per-lane key edits on an SE row's NAME TAG (R5 #7), keyed by the lane
// ids [seNameTagPropertyLanes] emits. Every function returns the edited tag
// (or null when the edit is a no-op / not a name-tag lane) — callers commit
// it as ONE undo step, exactly like the transform and effect helpers.

import '../../models/property_track.dart';
import '../../models/se_name_tag.dart';
import '../../models/text_cel_style.dart' show TextCelStyle;
import '../text/readout_text.dart' show columnValueOf;
import 'se_name_tag_lane_policy.dart';

/// Adds a key at [frameIndex] holding the member's RESOLVED value there
/// (AE: keying a property freezes what it currently shows), or removes the
/// existing one — the keyframe navigator's diamond toggle.
SeNameTag? seNameTagWithLaneKeyToggled(
  SeNameTag tag, {
  required String laneId,
  required int frameIndex,
}) {
  if (frameIndex < 0) {
    return null;
  }
  final resolved = tag.resolveAt(frameIndex);
  final keys = tag.track ?? SeNameTagTrack.empty();

  SeNameTag? toggleNumber(
    PropertyTrack<double> lane,
    double resolvedValue,
    SeNameTagTrack Function(PropertyTrack<double>) put,
  ) => tag.copyWith(
    track: put(
      lane.keyAt(frameIndex) != null
          ? lane.withoutKey(frameIndex)
          : lane.withKey(frameIndex, resolvedValue),
    ),
  );

  SeNameTag? toggleArgb(
    PropertyTrack<int> lane,
    int resolvedValue,
    SeNameTagTrack Function(PropertyTrack<int>) put,
  ) => tag.copyWith(
    track: put(
      lane.keyAt(frameIndex) != null
          ? lane.withoutKey(frameIndex)
          : lane.withKey(frameIndex, resolvedValue),
    ),
  );

  SeNameTag? toggleFlag(
    PropertyTrack<bool> lane,
    bool resolvedValue,
    SeNameTagTrack Function(PropertyTrack<bool>) put,
  ) => tag.copyWith(
    track: put(
      lane.keyAt(frameIndex) != null
          ? lane.withoutKey(frameIndex)
          // Booleans hold by nature (a half-shown line is not a state), so
          // the key is authored HOLD rather than left to tween.
          : lane.withKey(frameIndex, resolvedValue, outgoing: KeyExit.hold),
    ),
  );

  switch (laneId) {
    case seNameTagSizeLaneId:
      return toggleNumber(
        keys.fontSize,
        resolved.style.fontSize,
        (lane) => keys.copyWith(fontSize: lane),
      );
    case seNameTagTrackingLaneId:
      return toggleNumber(
        keys.letterSpacing,
        resolved.style.letterSpacing,
        (lane) => keys.copyWith(letterSpacing: lane),
      );
    case seNameTagBoldLaneId:
      return toggleFlag(
        keys.bold,
        resolved.style.bold,
        (lane) => keys.copyWith(bold: lane),
      );
    case seNameTagItalicLaneId:
      return toggleFlag(
        keys.italic,
        resolved.style.italic,
        (lane) => keys.copyWith(italic: lane),
      );
    case seNameTagUnderlineLaneId:
      return toggleFlag(
        keys.underline,
        resolved.style.underline,
        (lane) => keys.copyWith(underline: lane),
      );
    case seNameTagStrikethroughLaneId:
      return toggleFlag(
        keys.strikethrough,
        resolved.style.strikethrough,
        (lane) => keys.copyWith(strikethrough: lane),
      );
    case seNameTagNameInkLaneId:
      return toggleArgb(
        keys.nameInk,
        resolved.style.color,
        (lane) => keys.copyWith(nameInk: lane),
      );
    case seNameTagBoxColorLaneId:
      // No box means nothing to freeze: keying a colour that is not there
      // would author the red box back on, which the toggle never promised.
      final box = resolved.style.backgroundColor;
      if (box == null && keys.boxColor.keyAt(frameIndex) == null) {
        return null;
      }
      return toggleArgb(
        keys.boxColor,
        box ?? 0,
        (lane) => keys.copyWith(boxColor: lane),
      );
    case seNameTagLineInkLaneId:
      return toggleArgb(
        keys.lineInk,
        resolved.lineStyle.color,
        (lane) => keys.copyWith(lineInk: lane),
      );
    case seNameTagShowLineLaneId:
      return toggleFlag(
        keys.showLine,
        resolved.showLine,
        (lane) => keys.copyWith(showLine: lane),
      );
  }
  return null;
}

/// Applies a value typed into a member's value editor: it KEYS the member
/// at [frameIndex] — always, as an effect's parameter and a transform's
/// lane are keyed (R9 #18 — one rule: a value the user typed is a key). The
/// tag does not move on the first edit: a member with one key resolves to
/// it at every frame, exactly as the static slot did.
///
/// 🗣️F-407 (유저 2026-10-19): 「굵게같은 멤버 변경해도 키가 안찍힘. fx는
/// 키가 찍히는게 규칙인데 사본 만든듯함. 법 통일」. ↩️An unkeyed member
/// wrote its STATIC slot — the effect parameters' old rule, copied here
/// and left behind when R9 #18 retired it there.
///
/// ⚠️`none` alone still writes the slot: a box turned off is no colour,
/// and a key holding no colour has nothing to tween towards — so it turns
/// an unkeyed box off, and a keyed box is turned off by its keys.
///
/// Accepted input: numbers plainly; colours as `#RRGGBB`, `RRGGBB` or
/// `none` (the box only); booleans as `on`/`off`. Null on parse failure.
SeNameTag? seNameTagWithLaneValueEdited(
  SeNameTag tag, {
  required String laneId,
  required int frameIndex,
  required String input,
}) {
  if (frameIndex < 0) {
    return null;
  }
  final keys = tag.track ?? SeNameTagTrack.empty();
  final text = input.trim();

  SeNameTag? number(
    PropertyTrack<double> lane,
    SeNameTagTrack Function(PropertyTrack<double>) putKey,
  ) {
    final value = columnValueOf(text);
    if (value == null) {
      return null;
    }
    return tag.copyWith(track: putKey(lane.withKey(frameIndex, value)));
  }

  SeNameTag? argb(
    PropertyTrack<int> lane,
    SeNameTagTrack Function(PropertyTrack<int>) putKey, {
    bool allowNone = false,
  }) {
    if (allowNone && text.toLowerCase() == 'none') {
      return lane.isEmpty
          ? tag.copyWith(style: tag.style.copyWith(backgroundColor: null))
          : null;
    }
    final value = parseArgbInput(text);
    if (value == null) {
      return null;
    }
    return tag.copyWith(track: putKey(lane.withKey(frameIndex, value)));
  }

  SeNameTag? flag(
    PropertyTrack<bool> lane,
    SeNameTagTrack Function(PropertyTrack<bool>) putKey,
  ) {
    final value = parseBoolInput(text);
    if (value == null) {
      return null;
    }
    // Booleans hold by nature, as the toggle keys them.
    return tag.copyWith(
      track: putKey(lane.withKey(frameIndex, value, outgoing: KeyExit.hold)),
    );
  }

  return switch (laneId) {
    seNameTagSizeLaneId => number(
      keys.fontSize,
      (lane) => keys.copyWith(fontSize: lane),
    ),
    seNameTagTrackingLaneId => number(
      keys.letterSpacing,
      (lane) => keys.copyWith(letterSpacing: lane),
    ),
    seNameTagBoldLaneId => flag(
      keys.bold,
      (lane) => keys.copyWith(bold: lane),
    ),
    seNameTagItalicLaneId => flag(
      keys.italic,
      (lane) => keys.copyWith(italic: lane),
    ),
    seNameTagUnderlineLaneId => flag(
      keys.underline,
      (lane) => keys.copyWith(underline: lane),
    ),
    seNameTagStrikethroughLaneId => flag(
      keys.strikethrough,
      (lane) => keys.copyWith(strikethrough: lane),
    ),
    seNameTagNameInkLaneId => argb(
      keys.nameInk,
      (lane) => keys.copyWith(nameInk: lane),
    ),
    seNameTagBoxColorLaneId => argb(
      keys.boxColor,
      (lane) => keys.copyWith(boxColor: lane),
      allowNone: true,
    ),
    seNameTagLineInkLaneId => argb(
      keys.lineInk,
      (lane) => keys.copyWith(lineInk: lane),
    ),
    seNameTagShowLineLaneId => flag(
      keys.showLine,
      (lane) => keys.copyWith(showLine: lane),
    ),
    _ => null,
  };
}

/// The key window's write on member lane [laneId] (F-374): the keys inside
/// [frames] named as [naming] says — all collapsed onto ONE value, the key
/// the name already holds on [adoptFrom] where it holds one — and given
/// [pick]'s sides where the lane's keys take them
/// ([seNameTagLaneTakesSides]): a member's keys walk no path. ONE write of
/// the lane, the transform's (`PropertyLaneLens.keysWritten`). Null when
/// nothing changed.
SeNameTagTrack? seNameTagTrackWithLaneKeysWritten(
  SeNameTagTrack keys, {
  required String laneId,
  required Set<int> frames,
  ({String? name, int? preferredFrame})? naming,
  SeNameTagTrack? adoptFrom,
  KeyTypePick pick = const KeyTypePick(),
}) => seNameTagLaneLens(laneId)?.keysWritten(
  keys,
  frames: frames,
  naming: naming,
  adoptFrom: adoptFrom,
  pick: seNameTagLaneTakesSides(laneId)
      ? pick.sidesAlone
      : const KeyTypePick(),
);

/// AE's group Reset for the NAME TAG header — the rule an effect header's
/// takes (`effectsWithGroupReset`): **키를 삭제하진 않고 값만 리셋**. A member
/// with no keys puts its static slot back to the look a new tag has; a
/// keyed one takes that value at [frameIndexes] — at every one at the
/// playhead, on the keys a lane range covers alone ([keyedFramesOnly]).
/// ↩️The header drew the reset button and nothing answered it (F-374).
///
/// Null when nothing changed.
SeNameTag? seNameTagWithGroupReset(
  SeNameTag tag, {
  required Iterable<int> frameIndexes,
  bool keyedFramesOnly = false,
}) {
  final frames = frameIndexes.where((frame) => frame >= 0).toSet();
  if (frames.isEmpty) {
    return null;
  }
  const fresh = SeNameTag();
  final keys = tag.track ?? SeNameTagTrack.empty();
  PropertyTrack<T> keyed<T>(PropertyTrack<T> lane, T value, {KeyExit? out}) {
    var track = lane;
    for (final frame in frames) {
      if (lane.isNotEmpty && (!keyedFramesOnly || lane.keyAt(frame) != null)) {
        track = track.withKey(frame, value, outgoing: out);
      }
    }
    return track;
  }

  // Booleans hold by nature, as the toggle keys them.
  PropertyTrack<bool> held(PropertyTrack<bool> lane, bool value) =>
      keyed(lane, value, out: KeyExit.hold);

  // A member both runs share goes back to what each run of a new tag has.
  TextCelStyle shared(TextCelStyle run, TextCelStyle fresh) => run.copyWith(
    fontSize: keys.fontSize.isEmpty ? fresh.fontSize : null,
    letterSpacing: keys.letterSpacing.isEmpty ? fresh.letterSpacing : null,
    bold: keys.bold.isEmpty ? fresh.bold : null,
    italic: keys.italic.isEmpty ? fresh.italic : null,
    underline: keys.underline.isEmpty ? fresh.underline : null,
    strikethrough: keys.strikethrough.isEmpty ? fresh.strikethrough : null,
  );

  final ink = fresh.style.backgroundColor;
  final next = tag.copyWith(
    style: shared(tag.style, fresh.style).copyWith(
      color: keys.nameInk.isEmpty ? fresh.style.color : null,
      backgroundColor: keys.boxColor.isEmpty ? ink : tag.style.backgroundColor,
    ),
    lineStyle: shared(tag.lineStyle, fresh.lineStyle).copyWith(
      color: keys.lineInk.isEmpty ? fresh.lineStyle.color : null,
    ),
    showLine: keys.showLine.isEmpty ? fresh.showLine : null,
    track: tag.track == null
        ? null
        : keys.copyWith(
            fontSize: keyed(keys.fontSize, fresh.style.fontSize),
            letterSpacing: keyed(keys.letterSpacing, fresh.style.letterSpacing),
            bold: held(keys.bold, fresh.style.bold),
            italic: held(keys.italic, fresh.style.italic),
            underline: held(keys.underline, fresh.style.underline),
            strikethrough: held(keys.strikethrough, fresh.style.strikethrough),
            nameInk: keyed(keys.nameInk, fresh.style.color),
            boxColor: ink == null ? null : keyed(keys.boxColor, ink),
            lineInk: keyed(keys.lineInk, fresh.lineStyle.color),
            showLine: held(keys.showLine, fresh.showLine),
          ),
  );
  return next == tag ? null : next;
}

/// `#RRGGBB` / `RRGGBB` / `#AARRGGBB` → an opaque ARGB int. Null when the
/// text is not a colour.
int? parseArgbInput(String input) {
  final text = input.trim().replaceFirst('#', '');
  if (text.length != 6 && text.length != 8) {
    return null;
  }
  final value = int.tryParse(text, radix: 16);
  if (value == null) {
    return null;
  }
  return text.length == 6 ? 0xFF000000 | value : value;
}

/// `on`/`off` — and the spellings a person actually types.
bool? parseBoolInput(String input) => switch (input.trim().toLowerCase()) {
  'on' || 'true' || 'yes' || '1' => true,
  'off' || 'false' || 'no' || '0' => false,
  _ => null,
};
