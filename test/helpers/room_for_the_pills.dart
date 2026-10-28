import 'dart:ui' show Size;

/// 🗣️F-463 ⑥ (유저 2026-10-25): a frame panel's bar is two groups, and the
/// pills give way first — down to the cut pill — while the transport and the
/// zoom at its end keep their size. A pill past what is left is reached by
/// scrolling the strip, so a test that presses a pill stands on a window
/// wide enough that the pill it presses can be scrolled into view.
///
/// ↩️F-111-Q2 (「그대로 — 알약은 남는 만큼」) left the pills 34px on the bar
/// the app's 800 × 600 window lays out, between the transport and the
/// counter and zoom; 🔬299px since F-463 (2026-10-27).
///
/// 🔬Measured (2026-10-27): the timeline tab alone at this size leaves its
/// pills 683px.
const timelineTabWithRoomForItsPills = Size(1024, 320);

/// The app's window at this size leaves the timeline's pills 662px (🔬
/// 2026-10-27).
const appWindowWithRoomForItsPills = Size(1600, 900);
