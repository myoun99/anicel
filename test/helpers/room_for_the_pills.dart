import 'dart:ui' show Size;

/// 🗣️F-111-Q2 (유저 2026-10-25 「그대로 — 알약은 남는 만큼」): a frame
/// panel's transport and its counter and zoom keep their size, and the pills
/// between them get what is left — 34px on the bar the app's 800 × 600
/// window lays out, less than one button, reached by scrolling the strip. A
/// test that presses a pill stands on a window wide enough that the pill it
/// presses can be scrolled into view.
///
/// 🔬Measured (2026-10-25): the timeline tab alone at this size leaves its
/// pills 418px.
const timelineTabWithRoomForItsPills = Size(1024, 320);

/// The app's window at this size leaves the timeline's pills 397px (🔬
/// 2026-10-25).
const appWindowWithRoomForItsPills = Size(1600, 900);
