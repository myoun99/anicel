/// What a timeline index records: a drawing (a cel block start with an
/// explicit length). Inbetween dots live INSIDE drawing entries as
/// `TimelineExposure.breakdownOffsets` — there is no standalone mark
/// entry.
///
/// Emptiness is NOT a timeline entry: cells not covered by any drawing
/// block are simply uncovered, and the UI renders them with the timesheet
/// "X" glyph.
///
/// ↩️It had a second value, `mark`, kept only so the standalone dots of
/// older files parsed — and those files are refused by their format number
/// now (`anicelOldestReadFormatVersion`; the save law, 유저 2026-10-06).
enum TimelineExposureType {
  drawing;

  String toJson() => name;

  static TimelineExposureType fromJson(Object? value) {
    if (value == 'drawing') {
      return TimelineExposureType.drawing;
    }
    throw FormatException('Unknown timeline exposure type: $value');
  }
}
