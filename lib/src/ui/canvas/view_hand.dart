/// A hand a mounted view holds up to whoever keeps it — the shape tool's
/// `ShapeShow`, the save's `StrokeLander` — handed over from the view's
/// `initState` and taken back, as null, from its `dispose`; and which hand
/// is up now.
///
/// 🚨A VIEW BUILT ANEW COMES UP BEFORE THE ONE IT REPLACES GOES DOWN.
/// Flutter runs the new view's `initState` in the build that replaces the
/// old one, and the old view's `dispose` only when that frame's tree is
/// finalized — so a keeper that took the last word kept the null. The main
/// canvas's view is built anew whenever the active row's opacity crosses 1
/// (the panel's `Opacity` wrap comes and goes around it), and from then on,
/// for the rest of the session, every shape the shape tool traced showed
/// its marching ants and laid nothing, and a save no longer landed the pen
/// or the text in hand (F-419 — 유저 2026-10-20: 「도형도구가 개미행렬
/// 나와도 그림이 안나오길래 … 끄고 다시 앱 키니까 되길래」). Counted, a view
/// going down takes the hand away only when no other view holds one up.
///
/// ★The one count every keeper of a view's hand keeps: the main canvas
/// panel's shape, each sheet window's shape (F-420, which counted first,
/// by hand) and the session's stroke lander.
class ViewHand<T extends Object> {
  T? _hand;
  int _up = 0;

  /// The hand of the view that came up last, while any view is up.
  T? get now => _hand;

  /// What a view says: its [hand] as it comes up, null as it goes down.
  void call(T? hand) {
    if (hand != null) {
      _up += 1;
      _hand = hand;
      return;
    }
    _up -= 1;
    if (_up <= 0) {
      _up = 0;
      _hand = null;
    }
  }
}
