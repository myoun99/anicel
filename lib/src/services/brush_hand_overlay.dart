import 'dart:convert';

import '../models/brush_hand_settings.dart';
import '../models/brush_settings.dart';
import '../models/brush_tip_mask.dart';
import 'brush_preset_file_service.dart';

/// 🚨H25-again (유저 2026-09-11): 「사이즈말고도 불투명도나 필압이나 이런거
/// 문제있을수있으니 싹 다 확인하고 법 하나로 통일」.
///
/// The law, in one sentence: WHAT THE HAND SET ON A BRUSH COMES BACK WITH
/// THAT BRUSH, whichever setting it was. These functions are the whole of
/// it — one writes down what the hand changed, one lays it back over the
/// brush's file, one packs it for a file that leaves the machine — so a
/// setting `BrushSettings` gains tomorrow is remembered without anybody
/// listing it. (A list is what failed: see [BrushHandSettings].)
///
/// [byName] decides how a changed tip is written: by its id when the tip
/// library can hand it back — the app's own bank, the way the preset file
/// names tips — and whole when it cannot: a tip that arrived on a brush file
/// and was never adopted, or any tip in a file that leaves the machine.
///
/// ⛔`color` is never in it: the colour is shared by every tool and every
/// brush (R9 #2), which is why `BrushToolState.withPreset` re-asserts the
/// live one over whatever a brush carries.
BrushHandSettings brushHandOverlay({
  required BrushSettings file,
  required BrushSettings hand,
  required bool Function(BrushTipMask tip) byName,
}) {
  // Without the tips: this runs on every slider frame, and a tip writes its
  // pixels out as base64. The tips are compared by id below instead.
  final filed = file.toJson(withMasks: false);
  final held = hand.toJson(withMasks: false);
  final overlay = <String, Object?>{};
  for (final key in {...filed.keys, ...held.keys}) {
    if (key == 'color' || jsonEncode(filed[key]) == jsonEncode(held[key])) {
      continue;
    }
    // A null is kept on purpose: it is how a setting the hand REMOVED — a
    // pressure curve switched off, the blend put back to 通常 — stays so.
    overlay[key] = held[key];
  }
  for (final key in brushSettingsMaskKeys) {
    final tips = brushSettingsMasksAt(hand, key);
    if (_sameIds(tips, brushSettingsMasksAt(file, key))) {
      continue;
    }
    if (tips.isEmpty) {
      overlay[key] = null;
    } else if (tips.every(byName)) {
      overlay[brushSettingsMaskIdKey(key)] = brushSettingsMaskIdsJson(
        key,
        tips,
      );
    } else {
      // A list goes whole if any of it must: one entry is either names or
      // pixels, never a mix of the two.
      overlay[key] = brushSettingsMasksJson(key, tips);
    }
  }
  return overlay;
}

bool _sameIds(List<BrushTipMask> a, List<BrushTipMask> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index].id != b[index].id) {
      return false;
    }
  }
  return true;
}

/// [file] with [overlay] laid over it — the brush as the hand left it.
///
/// A tip the overlay names by id comes back through [resolveTip]; an id
/// nothing answers leaves the file's tip — a missing tip costs a brush its
/// texture, never the editor (the preset loader's rule).
///
/// ⚠️An overlay this build cannot read degrades to the FILE, whole: one
/// brush loses what the hand set on it, and picking it never fails.
BrushSettings brushSettingsUnderHand(
  BrushSettings file,
  BrushHandSettings overlay, {
  BrushTipResolver? resolveTip,
}) {
  try {
    final json = file.toJson(withMasks: false);
    for (final entry in overlay.entries) {
      if (entry.key != 'color' && !_namesATip(entry.key)) {
        json[entry.key] = entry.value;
      }
    }
    // Read WITHOUT tips, so a tip the hand cleared stays cleared: the setter
    // below cannot clear one (see [brushSettingsWithMasks]).
    var settings = BrushSettings.fromJson(json);
    for (final key in brushSettingsMaskKeys) {
      settings = brushSettingsWithMasks(
        settings,
        key,
        _tipsUnderHand(key, overlay, file: file, resolveTip: resolveTip),
      );
    }
    return settings;
  } on Object {
    return file;
  }
}

/// What a brush file that leaves the machine carries of [bank].
///
/// Every entry whose brush [fileOf] can name — the others (the eraser's own
/// entries, a brush since deleted) stay home — with each tip the hand
/// changed travelling WHOLE: the other side has no tip library to resolve
/// an id against, the reason the pack carries the presets' tips inline too.
Map<String, BrushHandSettings> brushHandSettingsToCarry(
  Map<String, BrushHandSettings> bank, {
  required BrushSettings? Function(String key) fileOf,
  BrushTipResolver? resolveTip,
}) => {
  for (final entry in bank.entries)
    if (fileOf(entry.key) case final file?)
      entry.key: brushHandOverlay(
        file: file,
        hand: brushSettingsUnderHand(
          file,
          entry.value,
          resolveTip: resolveTip,
        ),
        byName: (_) => false,
      ),
};

bool _namesATip(String key) =>
    brushSettingsMaskKeys.contains(key) ||
    brushSettingsMaskKeys.any((mask) => brushSettingsMaskIdKey(mask) == key);

/// The masks at [key] as the hand left them. Ids that are not ALL answered
/// leave the file's — the one-tip rule above, for a list.
List<BrushTipMask> _tipsUnderHand(
  String key,
  BrushHandSettings overlay, {
  required BrushSettings file,
  required BrushTipResolver? resolveTip,
}) {
  if (overlay.containsKey(key)) {
    return brushSettingsMasksFrom(overlay[key]);
  }
  final filed = brushSettingsMasksAt(file, key);
  final ids = brushSettingsMaskIdsFrom(overlay[brushSettingsMaskIdKey(key)]);
  final named = [for (final id in ids) ?resolveTip?.call(id)];
  return ids.isNotEmpty && named.length == ids.length ? named : filed;
}
