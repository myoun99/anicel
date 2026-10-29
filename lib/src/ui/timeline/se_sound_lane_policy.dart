import 'dart:ui' show Offset;

import '../../models/key_mark.dart';
import '../../models/se_sound.dart';
import '../text/app_strings.dart' show AppText;
import '../text/readout_text.dart';
import '../theme/lane_curve_palette.dart';
import 'property_lane_lens.dart';
import 'property_lane_model.dart';

/// The SE row's 「오디오」 group (I-140) — a fixed group, sibling of its
/// name tag and its Transform, on every SE row and never removable.
///
/// 🗣️I-140-Q1 (유저 2026-10-28): 「행에 늘 있는 「오디오」 그룹」 — the row
/// HAS a sound the way it has a name tag, so there is no add, no delete and
/// no reorder to offer, and its lane ids are plain names: a row has one
/// sound. ↩️The SE row's waveform lane stood here, a strip of its blocks'
/// sounds the row's own band already draws (「중복되니까 없애고」).
const String seSoundGroupLaneId = 'sound-group';

/// The member lane ids, in display order.
const String seSoundVolumeLaneId = 'sound:volume';
const String seSoundPanLaneId = 'sound:pan';

const List<String> seSoundLaneDisplayOrder = [
  seSoundVolumeLaneId,
  seSoundPanLaneId,
];

/// Whether [laneId] belongs to the sound group (header included) — the
/// predicate every routing switch asks instead of matching every member's.
bool laneIsSeSound(String? laneId) =>
    laneId == seSoundGroupLaneId ||
    (laneId != null && laneId.startsWith('sound:'));

/// The sound group's lane table: where each member's keys live on the row's
/// sound — the sound's twin of `seNameTagLaneLens`, and the group's arm of
/// every lane verb over a span. The Volume alone: the Pan is ONE value
/// (I-140-Q3 「이번엔 한 값」), so it holds no keys to reach. Null for the
/// header and for any id that is not a member lane.
PropertyLaneLens<SeSound, Object?>? seSoundLaneLens(String laneId) =>
    switch (laneId) {
      seSoundVolumeLaneId => PropertyLaneLens<SeSound, double>(
        get: (sound) => sound.volume,
        set: (sound, lane) => sound.copyWith(volume: lane),
        numbers: volumeLaneNumbers,
      ),
      _ => null,
    };

/// How the Volume lane reads its numbers: held as a share of the sound,
/// shown ·100 % (I-140-Q2 「%」), a number given it clamped to 0–200 % —
/// the one reading its value column, its graph, its value editor and a key
/// pasted from another lane go by. The Opacity lane's reading with its own
/// top (`opacityLaneNumbers`).
const LaneNumbers volumeLaneNumbers = (shown: _percentOf, held: _shareOf);

double _percentOf(double share) => share * 100;

double _shareOf(double percent) =>
    (percent / 100).clamp(0.0, SeSound.maxVolume).toDouble();

/// Whether [name] is already used by member lane [laneId] in [sound] — the
/// read a rename does before it commits, as `seNameTagLaneUsesName` is a
/// name tag's: a row's sound names on that sound alone. [excludeFrames]
/// drops the keys a RANGE rename is about to name.
bool seSoundLaneUsesName(
  SeSound sound,
  String laneId,
  String name, {
  Set<int> excludeFrames = const {},
}) =>
    seSoundLaneLens(
      laneId,
    )?.get(sound).keyForName(name, excludeFrames: excludeFrames) !=
    null;

/// A pan as the lane prints it: a SIDE and a distance in whole per cents,
/// `L50` / `R50`, and `C` in the middle — the sign becomes a letter, never
/// a minus (the F-34 card's exception, which the speaker's mixer bar wore
/// until the pan came here).
String panLaneText(double pan) {
  if (pan == 0) {
    return 'C';
  }
  return pan < 0
      ? 'L${readoutText(-pan * 100, decimals: 0)}'
      : 'R${readoutText(pan * 100, decimals: 0)}';
}

/// [panLaneText] read back — `L50`, `R50`, `C`, or a plain per cent with
/// its sign (`-50`) — as the pan it holds, in whole per cents as it prints
/// them (a lane holds the numbers it writes, F-488). Null when the text is
/// not a pan.
double? panOfLaneText(String text) {
  final typed = text.trim().toUpperCase();
  if (typed == 'C') {
    return 0;
  }
  final side = switch (typed.isEmpty ? '' : typed[0]) {
    'L' => -1,
    'R' => 1,
    _ => null,
  };
  final percent = columnValueOf(side == null ? typed : typed.substring(1));
  if (percent == null) {
    return null;
  }
  return ((side ?? 1) * percent).round().clamp(-100, 100) / 100;
}

/// The lane rows for one SE row's sound: the header, and its members while
/// the group is twirled open. [volumeAt] reads the row's volume at a time
/// on the rail — null where the rail has nothing to read it in, which hides
/// the value and the line with it.
List<PropertyLaneRow> seSoundPropertyLanes(
  SeSound sound, {
  required bool expanded,
  required double Function(double time)? volumeAt,
}) {
  final volume = sound.volume;
  return [
    PropertyLaneRow(
      laneId: seSoundGroupLaneId,
      label: AppText.strings.tlAudioGroup,
      // The members' key union, the summary every group header shows.
      keyMarks: unionKeyMarks([keyMarksOf(volume)]),
      keyNames: unionKeyNames([volume]),
      showsKeyNavigator: false,
      isGroupHeader: true,
      groupExpanded: expanded,
      // NO bypass switch: the row's speaker already mutes it.
      headsAGraph: true,
    ),
    if (expanded) ...[
      PropertyLaneRow(
        laneId: seSoundVolumeLaneId,
        label: AppText.strings.tlSoundVolume,
        keyMarks: keyMarksOf(volume),
        keyNames: volume.namedKeysByFrame,
        valueLabel: volumeAt == null
            ? null
            : (frame) =>
                  '${columnValueText(_percentOf(volumeAt(frame.toDouble())))}%',
        scrubValue: scrubSeSoundVolume,
        // The group is the row's audio fx: its one line takes an effect's
        // first parameter's colour, as a Blur's width does.
        curve: volumeAt == null
            ? null
            : (
                parts: [LaneCurvePalette.effectParameter(0)],
                at: (time) => [_percentOf(volumeAt(time))],
                sides: volume.sidesByFrame,
                way: null,
              ),
      ),
      PropertyLaneRow(
        laneId: seSoundPanLaneId,
        label: AppText.strings.audioPanLabel,
        keyMarks: const {},
        // One value (I-140-Q3): nothing to key, so no ◀ ◆ ▶.
        showsKeyNavigator: false,
        valueLabel: (_) => panLaneText(sound.pan),
        scrubValue: scrubSeSoundPan,
      ),
    ],
  ];
}

/// The Volume scrubbed by a drag on its readout, at the rate every number
/// lane scrubs at ([scrubbedNumber]), held inside 0–200 %.
String? scrubSeSoundVolume(String currentLabel, Offset dragDelta) {
  final percent = columnValueOf(currentLabel);
  if (percent == null) {
    return null;
  }
  final scrubbed = scrubbedNumber(
    percent,
    dragDelta,
  ).clamp(0.0, _percentOf(SeSound.maxVolume));
  return '${columnValueText(scrubbed)}%';
}

/// The Pan scrubbed by a drag on its readout — its per cents at the one
/// rate, across from left to right.
///
/// A move that writes the per cent it started from moves it one per cent
/// instead: a step that writes the same number is no step (F-488, the
/// settings bars' law — `FieldSlider`). The Pan writes whole per cents and
/// the one rate is half of one a pixel, so a ± press — one pixel — rounded
/// R2 back to R2 (🤖AI 검증 10-29: 「R2 에서 − 를 네 번 눌러도 R2」).
String? scrubSeSoundPan(String currentLabel, Offset dragDelta) {
  final pan = panOfLaneText(currentLabel);
  if (pan == null) {
    return null;
  }
  final now = (pan * 100).round();
  final next = scrubbedNumber(now.toDouble(), dragDelta).round();
  final moved = next != now ? next : now + dragDelta.dx.sign.toInt();
  return panLaneText(moved.clamp(-100, 100) / 100);
}
