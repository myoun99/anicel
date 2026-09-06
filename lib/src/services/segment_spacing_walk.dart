/// Points along ONE segment of [length]: the first at [firstAt], then every
/// [spacing], never past the end. [place] receives each point as a fraction
/// `t` of the segment (distance ÷ length).
///
/// Returns the distance of the last point placed — `firstAt - spacing` when
/// none fit — so a polyline caller's carry into the next segment is
/// `length - returned`.
///
/// The one spacing stepper: the brush dab walk (first at `spacing − carry`)
/// and the cut-stamp drag (first at `spacing`, no carry) each spelled it
/// (the audit's clone scan, 2026-09-06). What differs between them is the
/// first distance — a number — and the polyline laws (emit the first
/// sample, emit the last, carry the remainder) stay with the caller.
double placeAlongSegment({
  required double length,
  required double spacing,
  required double firstAt,
  required void Function(double t) place,
}) {
  var distance = firstAt;
  while (distance <= length) {
    place(distance / length);
    distance += spacing;
  }
  return distance - spacing;
}
