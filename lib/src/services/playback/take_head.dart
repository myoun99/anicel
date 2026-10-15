/// How many of a take's samples come before its anchor: what the microphone
/// had taken in at the moment the anchor was HEARD.
///
/// 🚨THE TAKE LANDS BY WHAT WAS HEARD (take-head-trims-at-the-playback-
/// start, 10-15; 유저 2026-10-08: 「소리 싱크나 영상이나 뭐 그런거
/// 정확하기만하면되. 그게 제일 최우선」). One who records speaks against what
/// they hear — and see: the picture is shown at what is heard. The sample
/// the microphone took in at the moment the anchor was heard belongs on the
/// anchor, and everything before it is the head that comes off. Below
/// nothing, the anchor was heard before the microphone opened — a take
/// begun mid-roll — and that much silence goes before the take instead.
///
/// [captured] is what the microphone had taken in at one moment, at
/// [captureRate]; the anchor was heard [sinceTheAnchor] of the playback
/// device's samples before that moment, at [deviceRate], and the microphone
/// had taken in that much less of its own by then.
///
/// ↩️The head was ESTIMATED — the device's output latency, plus the run-up
/// to a punch and the count-in — as if the roll started the instant the
/// microphone did, and as if the microphone held nothing of its own. The
/// roll starts after it (🔬the AMMI OP press: the device opened in 63ms and
/// its window uploaded in 37ms, 10-15, and the device starts on the clock's
/// first look), and the microphone hands over what it took in a buffer
/// later: every take landed late by all of it. One reading of two clocks
/// on one clock replaces all four terms.
int samplesBeforeTheAnchor({
  required int captured,
  required int captureRate,
  required int sinceTheAnchor,
  required int deviceRate,
}) => captured - (sinceTheAnchor * captureRate / deviceRate).round();
