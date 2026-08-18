// Per-lane key edits on an SE row's NAME TAG (R5 #7), keyed by the lane
// ids [seNameTagPropertyLanes] emits. Every function returns the edited tag
// (or null when the edit is a no-op / not a name-tag lane) — callers commit
// it as ONE undo step, exactly like the transform and effect helpers.

import '../../models/property_track.dart';
import '../../models/se_name_tag.dart';
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
          : lane.withKey(
              frameIndex,
              resolvedValue,
              interpolation: PropertyKeyInterpolation.hold,
            ),
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

/// Applies a value typed into a member's value editor.
///
/// A member with NO keys writes its STATIC slot — the effect-parameter rule
/// (an unkeyed property is a plain value, and typing into it must not turn
/// the tag into an animated one behind the user's back). A member that IS
/// keyed takes a key at [frameIndex], AE-style.
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
    SeNameTag Function(double) putStatic,
    SeNameTagTrack Function(PropertyTrack<double>) putKey,
  ) {
    final value = double.tryParse(text.replaceAll('%', '').trim());
    if (value == null) {
      return null;
    }
    if (lane.isEmpty) {
      return putStatic(value);
    }
    return tag.copyWith(
      track: putKey(
        lane.withKey(
          frameIndex,
          value,
          interpolation:
              lane.keyAt(frameIndex)?.interpolation ??
              PropertyKeyInterpolation.linear,
        ),
      ),
    );
  }

  SeNameTag? argb(
    PropertyTrack<int> lane,
    SeNameTag? Function(int?) putStatic,
    SeNameTagTrack Function(PropertyTrack<int>) putKey, {
    bool allowNone = false,
  }) {
    if (allowNone && text.toLowerCase() == 'none') {
      // "none" is a STATIC state — a key holding "no colour" has no value
      // to interpolate, so the box is turned off on the slot instead.
      return lane.isEmpty ? putStatic(null) : null;
    }
    final value = parseArgbInput(text);
    if (value == null) {
      return null;
    }
    if (lane.isEmpty) {
      return putStatic(value);
    }
    return tag.copyWith(
      track: putKey(
        lane.withKey(
          frameIndex,
          value,
          interpolation:
              lane.keyAt(frameIndex)?.interpolation ??
              PropertyKeyInterpolation.linear,
        ),
      ),
    );
  }

  SeNameTag? flag(
    PropertyTrack<bool> lane,
    SeNameTag Function(bool) putStatic,
    SeNameTagTrack Function(PropertyTrack<bool>) putKey,
  ) {
    final value = parseBoolInput(text);
    if (value == null) {
      return null;
    }
    if (lane.isEmpty) {
      return putStatic(value);
    }
    return tag.copyWith(
      track: putKey(
        lane.withKey(
          frameIndex,
          value,
          interpolation: PropertyKeyInterpolation.hold,
        ),
      ),
    );
  }

  switch (laneId) {
    case seNameTagSizeLaneId:
      return number(
        keys.fontSize,
        (value) => tag.copyWith(
          style: tag.style.copyWith(fontSize: value),
          lineStyle: tag.lineStyle.copyWith(fontSize: value),
        ),
        (lane) => keys.copyWith(fontSize: lane),
      );
    case seNameTagTrackingLaneId:
      return number(
        keys.letterSpacing,
        (value) => tag.copyWith(
          style: tag.style.copyWith(letterSpacing: value),
          lineStyle: tag.lineStyle.copyWith(letterSpacing: value),
        ),
        (lane) => keys.copyWith(letterSpacing: lane),
      );
    case seNameTagBoldLaneId:
      return flag(
        keys.bold,
        (value) => tag.copyWith(
          style: tag.style.copyWith(bold: value),
          lineStyle: tag.lineStyle.copyWith(bold: value),
        ),
        (lane) => keys.copyWith(bold: lane),
      );
    case seNameTagNameInkLaneId:
      return argb(
        keys.nameInk,
        (value) => value == null
            ? null
            : tag.copyWith(style: tag.style.copyWith(color: value)),
        (lane) => keys.copyWith(nameInk: lane),
      );
    case seNameTagBoxColorLaneId:
      return argb(
        keys.boxColor,
        // `null` really means "no box" here, and `copyWith`'s sentinel is
        // what tells that apart from "leave it alone".
        (value) =>
            tag.copyWith(style: tag.style.copyWith(backgroundColor: value)),
        (lane) => keys.copyWith(boxColor: lane),
        allowNone: true,
      );
    case seNameTagLineInkLaneId:
      return argb(
        keys.lineInk,
        (value) => value == null
            ? null
            : tag.copyWith(lineStyle: tag.lineStyle.copyWith(color: value)),
        (lane) => keys.copyWith(lineInk: lane),
      );
    case seNameTagShowLineLaneId:
      return flag(
        keys.showLine,
        (value) => tag.copyWith(showLine: value),
        (lane) => keys.copyWith(showLine: lane),
      );
  }
  return null;
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

/// Shifts EVERY key of ONE name-tag lane inside [rangeStartIndex,
/// [rangeEndIndexExclusive]) by [frameDelta] — the family's arm of the
/// lane-scoped range move (UI-R23 #3 part 2), through the shared
/// [PropertyTrack.withRangedKeysShifted] loop. Null when nothing moves or
/// the landing is blocked.
SeNameTagTrack? seNameTagTrackWithLaneKeysShifted(
  SeNameTagTrack track, {
  required String laneId,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  PropertyTrack<T>? shifted<T>(PropertyTrack<T> lane) =>
      lane.withRangedKeysShifted(
        rangeStartIndex: rangeStartIndex,
        rangeEndIndexExclusive: rangeEndIndexExclusive,
        frameDelta: frameDelta,
      );

  switch (laneId) {
    case seNameTagSizeLaneId:
      final next = shifted(track.fontSize);
      return next == null ? null : track.copyWith(fontSize: next);
    case seNameTagTrackingLaneId:
      final next = shifted(track.letterSpacing);
      return next == null ? null : track.copyWith(letterSpacing: next);
    case seNameTagBoldLaneId:
      final next = shifted(track.bold);
      return next == null ? null : track.copyWith(bold: next);
    case seNameTagNameInkLaneId:
      final next = shifted(track.nameInk);
      return next == null ? null : track.copyWith(nameInk: next);
    case seNameTagBoxColorLaneId:
      final next = shifted(track.boxColor);
      return next == null ? null : track.copyWith(boxColor: next);
    case seNameTagLineInkLaneId:
      final next = shifted(track.lineInk);
      return next == null ? null : track.copyWith(lineInk: next);
    case seNameTagShowLineLaneId:
      final next = shifted(track.showLine);
      return next == null ? null : track.copyWith(showLine: next);
  }
  return null;
}

/// Shifts every ranged key of EVERY [laneIds] lane by [frameDelta] — the
/// MULTI-LANE range move (R26 #3), the name-tag twin of
/// `transformTrackWithLaneSpanKeysShifted`: rigid group, one delta,
/// all-or-nothing ACROSS lanes. A lane with no key in the range rides
/// along; a lane whose landing is blocked vetoes the WHOLE move.
SeNameTagTrack? seNameTagTrackWithLaneSpanKeysShifted(
  SeNameTagTrack track, {
  required List<String> laneIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
}) {
  if (frameDelta == 0) {
    return null;
  }
  var current = track;
  var movedAny = false;
  for (final laneId in laneIds) {
    final hasRangedKey = seNameTagLaneKeyFrames(current, laneId).any(
      (frame) => frame >= rangeStartIndex && frame < rangeEndIndexExclusive,
    );
    if (!hasRangedKey) {
      continue; // Nothing of this lane in the range — it rides along.
    }
    final next = seNameTagTrackWithLaneKeysShifted(
      current,
      laneId: laneId,
      rangeStartIndex: rangeStartIndex,
      rangeEndIndexExclusive: rangeEndIndexExclusive,
      frameDelta: frameDelta,
    );
    if (next == null) {
      return null; // This lane HAD keys, so null here means blocked.
    }
    current = next;
    movedAny = true;
  }
  return movedAny ? current : null;
}
