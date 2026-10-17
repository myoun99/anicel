import 'dart:typed_data';

import '../../core/byte_needle.dart';

/// Whether a layer's `LayerEffectInfo` turns on an effect CLIP STUDIO
/// draws over the layer's own pixels — of its layer properties' effects,
/// a border (フチ · 水彩境界), a tone, extracted lines or an overlaid
/// texture (memory `csp-clip-format-notes` §2).
///
/// The blob is named records, big-endian (as `GradationFillInfo` is):
/// `u32 size · u32`, then each record's `u32 letters · UTF-16BE name` and
/// its body — the two oldest a fixed body, every later one led by a
/// `u32 size` that counts itself. An effect's switch is its body's first
/// word, past that size.
///
/// ⚠️READ FROM ONE LAYER OF ONE SAMPLE (s12, 10-17), every effect off: the
/// switch is the word that read 0 where each body begins, the settings
/// after it in the order the manual lists them (水彩境界: range 5, opacity
/// 50, darkness 20, blur 10 — CLIP STUDIO's defaults). `EffectEdge`'s is
/// also the word the public reader `clip_to_psd` (MIT) reads. No sample
/// has an effect on, so a switch read in the wrong place says nothing of
/// an effect that is on — the silence there was before this read.
///
/// ⛔`EffectApplyOpacity` · `EffectToneAreaColor` · `EffectTonePosterize`
/// are no effects of their own: they are the tone's settings — the
/// manual's 「Reflect layer opacity」, 「Area color」 and 「Posterization」
/// — and the sample's first reflects the opacity (1) with its tone off.
bool clipEffectsOn(Uint8List info) {
  final data = ByteData.sublistView(info);
  for (final (name, :sized) in _switches) {
    final at = _bodyOf(info, name);
    if (at == null) {
      continue;
    }
    final word = sized ? at + 4 : at;
    if (word + 4 <= info.length && data.getUint32(word) != 0) {
      return true;
    }
  }
  return false;
}

/// The records whose body opens with an effect's switch, and whether a
/// size stands before it.
const _switches = <(String, {bool sized})>[
  ('EffectEdge', sized: false),
  ('EffectTone', sized: false),
  ('EffectWaterEdge', sized: true),
  ('EffectLine', sized: true),
  ('EffectTextureMap', sized: true),
];

/// Where the record named [name] begins its body in [info] — past the
/// count of its letters and the letters — or null where there is none.
/// The count makes `EffectTone` no prefix of `EffectTonePosterize`.
int? _bodyOf(Uint8List info, String name) {
  final key = ByteData(4 + 2 * name.length)..setUint32(0, name.length);
  for (var i = 0; i < name.length; i += 1) {
    key.setUint16(4 + 2 * i, name.codeUnitAt(i));
  }
  final needle = key.buffer.asUint8List();
  final at = indexOfBytes(info, needle, 0);
  return at < 0 ? null : at + needle.length;
}
