/// What a measurement hands `testWidgets` as `semanticsEnabled`: no
/// semantics tree, as the app runs.
///
/// 🚨The app builds none on this machine: on Windows it refuses the
/// platform's ask unless a screen reader runs, and in a debug build even
/// then (`PlatformSemanticsGate`, 유저 2026-09-24 · 2026-10-15); elsewhere
/// the platform asks only for an assistive technology that runs.
/// `testWidgets` builds one unless told not to, and a frame then pays a
/// walk the app never does — in a debug build all of it, every frame
/// (`flushSemantics`'s asserts). 🔬127 of 1,844 ms sampled over a stroke
/// on S5_BA cut 352 (브러시/렌더링 2026-11-18).
const bool semanticsAsTheAppRuns = false;
