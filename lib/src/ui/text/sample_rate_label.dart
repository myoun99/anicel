/// `48kHz` / `44.1kHz` — a sample rate the way every surface says it:
/// kilohertz reads at a glance, the raw hertz number is a spec sheet.
///
/// ⛔ONE spelling: the project settings' rate menu said it alone until the
/// media pool's 오디오 정보 (asset-placement-presets Q4) said a file's rate
/// too.
String sampleRateLabel(int rate) => rate % 1000 == 0
    ? '${rate ~/ 1000}kHz'
    : '${(rate / 1000).toStringAsFixed(1)}kHz';
