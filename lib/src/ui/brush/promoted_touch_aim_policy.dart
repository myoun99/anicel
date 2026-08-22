import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// 🚨★★D34 — **A MOUSE THAT A FINGER PRODUCED DOES NOT AIM A TOOL.**
///
/// 유저 (2026-08-21 재개 → 2026-08-23 실기):
///
/// > 「커서가 있는 툴을 사용하는 경우(브러시/스포이드). 터치조작시 **해당
/// > 커서가 보임.** 위치는 **터치의 중앙부분**」 · 「**1핑거로 플립해서 마우스가
/// > 이동해버리는건 확인**했어」 · 「**어떤거든 터치면 안생기게 하고싶은데.
/// > 툴 묻지않고. 1핑거 드로잉일때 커서생기는건 ok**」
///
/// ## The chain, each link established rather than assumed
///
/// 1. 🧪Flutter's Windows embedder handles `WM_POINTERDOWN` and then falls
///    through to `DefWindowProc` without ever calling
///    `SkipPointerFrameMessages` — zero hits in the entire engine at
///    3.44.2. Windows therefore also synthesizes the LEGACY mouse messages
///    for that touch, and synthesizing a `WM_MOUSEMOVE` **physically moves
///    the system cursor** to the contact (a pinch parks it at the focal
///    point — 「터치의 중앙부분」). The desktop escapes because the shell
///    suppresses the promotion, which is the difference the user spotted.
/// 2. 🧪The user confirmed the movement directly: 「1핑거로 플립해서 마우스가
///    이동해버리는건 확인했어」.
/// 3. 🧪The promoted messages themselves do NOT reach the framework —
///    `flutter_window.cc:40` filters them by `GetMessageExtraInfo()`'s
///    `0xFF515700` signature, and the user's Input Inspector capture of a
///    two-finger pinch shows `touch` rows and **no `mouse` row at all**.
/// 4. ⇒ So the ring is not raised by the promotion. It is raised by the
///    NEXT genuine mouse event, which honestly reports the position the
///    cursor was dragged to. That is why it is 「가끔」 — only when one
///    follows — and why it lands where the fingers were.
///
/// ## The rule
///
/// While a NAVIGATING finger is on the glass, a mouse sample is the
/// promotion's aftermath, not a hand. It may not move the tool's aim.
///
/// ⛔MOUSE ONLY. The fingers are already refused upstream
/// (`AppInput.toolAcceptsPointer`), so this can only reach a kind that
/// passes that gate — and a STYLUS writing while a finger is down is the
/// ordinary case of a hand steadying the tablet under a hovering pen.
/// Blocking every kind froze the pen's ring under a resting palm, which
/// trades the reported bug for a worse one.
///
/// ⛔AND NO TIME WINDOW. An earlier attempt kept refusing for 400ms after
/// the last lift — a number I invented, with nothing behind it, which then
/// swallowed legitimate mouse hovers and broke two pinned tests. The
/// contacts being DOWN is a fact; "recently" was a guess.
///
/// ⛔It refuses the WRITE, never clearing what is already aimed: 「a finger
/// never displaces the cursor the pen put down」 is a law of its own.
///
/// ⚠️**WHAT THIS DOES NOT FIX**: the system cursor is still left parked
/// where the touch landed. Stopping that needs `SkipPointerFrameMessages`
/// in the embedder — the file is in the SDK, and the runner-level
/// workaround risks killing Windows touch outright (the user declined it).
bool aimIsPromotedTouch({
  required PointerDeviceKind kind,
  required int touchContacts,
  required bool touchDraws,
}) => kind == PointerDeviceKind.mouse && touchContacts > 0 && !touchDraws;
