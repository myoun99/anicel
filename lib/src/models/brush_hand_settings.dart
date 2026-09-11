/// What the hand changed on one brush: the keys of that brush's settings
/// JSON that it left at other values than the brush's own file holds.
///
/// 🚨H25 (유저 2026-08-23): 「클튜보면 브러시크기가 브러시마다 다르게
/// 설정가능하던데, 그거 따라가도록. 브러시 고르고 브러시크기 설정하면 다음에
/// 같은 브러시 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」.
/// The BLEND joined on 2026-09-08 by the same request — 「블렌드모드도 어차피
/// 브러시/툴마다 다르게 저장되도록. 사이즈나 불투명도처럼 그렇게 되도록」 —
/// and 🚨H25-again (2026-09-11) made it every setting: 「사이즈말고도
/// 불투명도나 필압이나 이런거 … 싹 다 확인하고 법 하나로 통일」.
///
/// ⇒ It is no longer a list of fields. A list is what let the pressure
/// curves, the flow and the tips go back to the file on every re-pick while
/// size, opacity and blend came back: each setting had to be added by hand,
/// and only three ever were. An overlay over `BrushSettings.toJson` has no
/// list to forget — `services/brush_hand_overlay.dart` writes and reads it.
/// It is still the app remembering an unsaved edit between sessions instead
/// of rewriting the brush file under you.
///
/// ⚠️A key the file has and the overlay does not is a setting nobody
/// touched, and it keeps following the file (Q-brush-param: a brush the hand
/// has never set reads what is baked into its own file). A key mapped to
/// NULL is one the hand removed — a pressure curve switched off, a tip
/// cleared.
///
/// ⚠️The three keys the bank held before (`size`, `opacity`, `blendMode`)
/// are spelled exactly as `BrushSettings.toJson` spells them, so every bank
/// and every brush file written before this reads as an overlay already.
///
/// ⚠️IT LIVES IN `models/` because two layers need it: the store that keeps
/// it between sessions (`ui/brush`) and the brush-pack codec that writes it
/// into a shared file (`services/`), which cannot import `ui/`.
typedef BrushHandSettings = Map<String, Object?>;

/// A whole BANK — `{key: overlay}` — which is the shape BOTH homes store:
/// the app's own file and an exported brush file.
///
/// ⚠️The wrapper is shared, not written per home. It was written twice for
/// one day and the clone scan named the pair; there is nothing to reconcile
/// between them, because the map is the same map.
Map<String, dynamic> brushHandSettingsBankToJson(
  Map<String, BrushHandSettings> bank,
) => {for (final entry in bank.entries) entry.key: entry.value};

/// The inverse. ⚠️An entry that is not a map is SKIPPED rather than failing
/// the bank — one brush loses what the hand set on it, the rest still load.
/// A value its setting cannot read degrades the same way, later, where the
/// overlay is laid over the file (`brushSettingsUnderHand`).
Map<String, BrushHandSettings> brushHandSettingsBankFromJson(
  Map<String, dynamic>? json,
) => {
  for (final entry in (json ?? const <String, dynamic>{}).entries)
    if (entry.value is Map<String, dynamic>)
      entry.key: Map<String, Object?>.of(entry.value as Map<String, dynamic>),
};

/// The bank once an older one — the file the last session left — arrives
/// under [live]: every brush [saved] remembers, except where [live] already
/// holds something.
///
/// ⚠️WHAT THE HAND SET SINCE THE APP OPENED WINS. A size set in the first
/// second of a session is the newer fact, and the bank on disk is older than
/// it by definition; a late load that wrote over it would put the file's
/// value back under the hand (H25-again).
Map<String, BrushHandSettings> brushHandSettingsRecalled({
  required Map<String, BrushHandSettings> live,
  required Map<String, BrushHandSettings> saved,
}) => {...saved, ...live};
