/// A hand a mounted view holds up to whoever keeps it — the shape tool's
/// `ShapeShow`, the save's `StrokeLander` — held [up] from the view's
/// `initState` and put [down] from its `dispose`; and which hand is up now.
///
/// 🚨A VIEW BUILT ANEW COMES UP BEFORE THE ONE IT REPLACES GOES DOWN.
/// Flutter runs the new view's `initState` in the build that replaces the
/// old one, and the old view's `dispose` only when that frame's tree is
/// finalized — so a keeper handed a callback took the old view's null as
/// the last word. The main canvas's view was built anew whenever the
/// active row's opacity crossed 1 (the panel's `Opacity` wrap came and
/// went around it), and from then on, for the rest of the session, every
/// shape the shape tool traced showed its marching ants and laid nothing,
/// and a save no longer landed the pen or the text in hand (F-419 — 유저
/// 2026-10-20: 「도형도구가 개미행렬 나와도 그림이 안나오길래 … 끄고 다시 앱
/// 키니까 되길래」).
///
/// ⛔Each view puts down ITS OWN hand, not a count: a count kept the hand
/// of a view that went down while an older one was still up — a lander
/// into tiles already given back. The hand up now is the one of the view
/// that came up last among those still up, whatever order they go in.
///
/// ★The one keeping every keeper of a view's hand does: the main canvas
/// panel's shape and lander, each sheet window's shape (F-420, which
/// counted first, by hand) and the session's lander. A view hands its
/// keeper this, not a callback — the type leaves no keeper that can take
/// the last word, and `a_view_holds_its_hand_up_in_a_view_hand_test`
/// scans for a `dispose` that hands a callback null.
class ViewHand<T extends Object> {
  final List<T> _up = [];

  /// The hand of the view that came up last, of those still up.
  T? get now => _up.isEmpty ? null : _up.last;

  /// A view coming up holds up [hand].
  void up(T hand) => _up.add(hand);

  /// A view going down puts down [hand], the one it held up.
  void down(T hand) => _up.remove(hand);
}
