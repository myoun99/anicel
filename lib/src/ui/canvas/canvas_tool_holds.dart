/// WHO HOLDS THE TOOL ON A CANVAS RIGHT NOW, besides the hand on the keys.
///
/// A pen's tail and a mapped button each switch the tool for as long as
/// they last, through the one hold the shell keeps (`TemporaryTool`), and
/// whichever engaged first keeps it: a barrel press that took the tool
/// mid-flip would leave the tail with nothing to spring back to when the
/// pen is turned upright, and a flip under a held button would do the same
/// to the button.
///
/// They are read in two places. The tail is the DRAWING VIEW's — it erases,
/// and a stroke starting now carries that in its own settings. A button
/// held for a pick draws nothing, so the canvas panel reads it where every
/// press on the canvas passes: under every tool, with or without a cel
/// (F-299, 유저 2026-10-05: 「어떤 도구 들고있던 규칙 만들지말고 법 통일해서
/// 작동하도록」). This is what each of the two tells the other.
///
/// A panel hands its own to the view it builds; a view nobody handed one —
/// a sheet's ink — keeps its own, and no button ever holds a pick there.
final class CanvasToolHolds {
  /// The pen is turned over and its tail's mapping holds the tool. Written
  /// by the drawing view, which reads the tail at every hover and contact.
  bool penTail = false;

  /// A mapped button holds the tool for a pick — pressed while the pen
  /// hovers, or in contact. Written by the panel's reader of mapped
  /// buttons.
  bool pick = false;
}
