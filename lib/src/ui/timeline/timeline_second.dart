/// The frames one second takes on the time axis: the project's counting
/// rate — or 24 for a nonsense rate (zero or less) rather than dividing by
/// zero.
///
/// ⛔ONE answer for every mark of the second. The ruler wrote this fallback
/// out five times, and the grid's second lines kept an answer of their own
/// (a nonsense rate ruled no second at all) — the ruler marked seconds the
/// grid did not rule.
int timelineSecondFrames(int framesPerSecond) =>
    framesPerSecond > 0 ? framesPerSecond : 24;

/// Whether a second begins at [frameIndex] — where the ruler writes its
/// mark and the grid rules its second line.
bool timelineOnSecondBoundary(int frameIndex, int framesPerSecond) =>
    frameIndex % timelineSecondFrames(framesPerSecond) == 0;
