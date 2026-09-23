const int defaultCutDurationFrames = 24;

/// The post-cut allowance: the frames past a frame axis's END LINE that its
/// scroll range always reaches — on the timeline, the x-sheet and the
/// storyboard alike.
///
/// ↩️UI-R10 #23 retired the old 24-frame tail to zero: the endless frame axis
/// (scroll-driven growth + ruler edge auto-pan) supplies every frame past the
/// cut instead of a canned tail.
///
/// 🚨F-174 (유저 2026-09-21): 「컷길이 엔드라인에 딱 맞추면 스크롤 쭉 해도
/// 엔드라인 안보이고 룰러 살짝 움직여야 엔드라인 보이니까, 스크롤바는
/// 엔드라인+1콤마? 를 기본 최소치로」. At zero the scrollbar stopped exactly
/// ON the end line, and the line is drawn just past its frame, so the far end
/// of the scrollbar showed everything but it. ONE comma: the line, and a
/// comma of paper after it. The endless axis still owns everything beyond.
const int defaultTimelineSafetyFrameCount = 1;
