import 'package:flutter/foundation.dart';

import '../../models/se_audio_spans.dart';

/// Why a sound cannot be played (playback-says-the-sound-it-cannot-play,
/// 유저 2026-10-17: 「이유(형식 · 파일 없음 · 출력)는 툴팁으로」) — what
/// `AudioConformStore.cannotPlayAt` answers, the one question a run and the
/// screen both ask. The output refusing every sound is the transport's,
/// not a sound's (`AudioDeviceTransport.outputRefused`).
enum SoundCannotPlay {
  /// The file is not there.
  missing,

  /// The file is there and could not be read yet — a cloud copy still
  /// coming down. It is tried again.
  notReadYet,

  /// No decoder reads its format.
  format,

  /// Its conversion for playback failed.
  conform,

  /// It could not be brought to the rate the output plays at.
  deviceRate,
}

/// What a run plays without (playback-says-the-sound-it-cannot-play, 유저
/// 2026-10-17: the cells, the meter's seat and a warning at the front of
/// the transport) — the sounds nothing will make ready, and why, and
/// whether the output refused every sound.
///
/// ⚠️Equal by content, so a run that re-plans to the same answer tells the
/// screen nothing.
@immutable
final class PlaysWithout {
  const PlaysWithout({this.sounds = const {}, this.output = false});

  /// A run that plays everything — and no run at all.
  static const nothing = PlaysWithout();

  final Map<String, SoundCannotPlay> sounds;

  /// The output would not open, or not take the run: no sound plays.
  final bool output;

  @override
  bool operator ==(Object other) =>
      other is PlaysWithout &&
      other.output == output &&
      mapEquals(other.sounds, sounds);

  @override
  int get hashCode => Object.hash(
    output,
    Object.hashAllUnordered(
      sounds.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Why a sound the block [spans] lay over [frameIndex] carries cannot be
/// played — [cannotPlay]'s first answer for the sounds there, null where
/// each can or none is there. [spans] in block order ([seAudioSpans]).
///
/// THE ONE READING of 「this block's sound」 for both rows that paint an SE
/// block red: the timeline's (`LayerStack.soundCannotPlayAt`) and the
/// storyboard's.
SoundCannotPlay? soundCannotPlayIn(
  List<SeAudioSpan> spans,
  int frameIndex,
  SoundCannotPlay? Function(String filePath) cannotPlay,
) {
  for (final span in spans) {
    if (span.startFrame > frameIndex) {
      break;
    }
    if (frameIndex < span.endFrameExclusive) {
      final why = cannotPlay(span.clip.filePath);
      if (why != null) {
        return why;
      }
    }
  }
  return null;
}
