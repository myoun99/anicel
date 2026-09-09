import 'brush_blend_mode.dart';

/// What was last set on one brush, by hand, since the brush was loaded.
///
/// 🚨H25 (유저 2026-08-23): 「클튜보면 브러시크기가 브러시마다 다르게
/// 설정가능하던데, 그거 따라가도록. 브러시 고르고 브러시크기 설정하면 다음에
/// 같은 브러시 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」.
///
/// The BLEND joined them on 2026-09-08, by the same request and for the same
/// reason: 「블렌드모드도 어차피 브러시/툴마다 다르게 저장되도록. 사이즈나
/// 불투명도처럼 그렇게 되도록」. Every field here is a brush parameter that
/// the panel can change — this record is not a different KIND of value (that
/// split is gone), it is the app remembering an unsaved edit between
/// sessions instead of rewriting the brush file under you.
///
/// ⚠️Every entry is nullable and every reader treats null as "this brush was
/// never touched, use what its own file says". Adding a field therefore needs
/// no version bump: an older file simply has none of it.
///
/// ⚠️IT LIVES IN `models/` because two layers need it: the store that keeps
/// it between sessions (`ui/brush`) and the brush-pack codec that writes it
/// into a shared file (`services/`), which cannot import `ui/`.
typedef BrushHandSettings = ({
  double? size,
  double? opacity,
  BrushBlendMode? blendMode,
});

/// The JSON both homes use — the app's own bank and an exported brush file.
///
/// ⚠️ONE SPELLING, because the two files hold the same three values and a
/// second spelling would drift the moment a fourth arrives.
Map<String, dynamic> brushHandSettingsToJson(BrushHandSettings value) => {
  if (value.size != null) 'size': value.size,
  if (value.opacity != null) 'opacity': value.opacity,
  if (value.blendMode != null) 'blendMode': value.blendMode!.name,
};

/// The inverse. An unreadable field degrades to "never touched" rather than
/// failing the whole bank — one brush loses a remembered blend, everything
/// else still loads.
BrushHandSettings brushHandSettingsFromJson(Map<String, dynamic> json) => (
  size: (json['size'] as num?)?.toDouble(),
  opacity: (json['opacity'] as num?)?.toDouble(),
  blendMode: BrushBlendMode.named(json['blendMode'] as String?),
);

/// A whole BANK — `{preset id: settings}` — which is the shape BOTH homes
/// store: the app's own file and an exported brush file.
///
/// ⚠️The wrapper is shared too, not just the per-entry pair. It was written
/// twice for one day and the clone scan named the pair; there is nothing to
/// reconcile between them, because the map is the same map.
Map<String, dynamic> brushHandSettingsBankToJson(
  Map<String, BrushHandSettings> bank,
) => {
  for (final entry in bank.entries)
    entry.key: brushHandSettingsToJson(entry.value),
};

/// The inverse. ⚠️An entry that is not a map is SKIPPED rather than failing
/// the bank — one brush loses a remembered size, the rest still load.
Map<String, BrushHandSettings> brushHandSettingsBankFromJson(
  Map<String, dynamic>? json,
) => {
  for (final entry in (json ?? const <String, dynamic>{}).entries)
    if (entry.value is Map<String, dynamic>)
      entry.key: brushHandSettingsFromJson(entry.value as Map<String, dynamic>),
};
