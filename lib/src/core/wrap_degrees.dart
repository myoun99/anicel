/// [degrees] folded into [-180, 180] — the same turn, the short way round.
///
/// ⛔ONE FOLD (F-222 ①). The transform box's rotation, the camera lever and
/// the view's own rotation gesture each carried this loop, and a turn drag
/// stays continuous across the ±180° seam only while every one of them folds
/// a step the same way.
double wrapDegrees(double degrees) {
  var wrapped = degrees;
  while (wrapped > 180) {
    wrapped -= 360;
  }
  while (wrapped < -180) {
    wrapped += 360;
  }
  return wrapped;
}
