/// The SHAPE a drag-out tool traces on the canvas.
///
/// Deliberately orthogonal to the VERB that consumes the outline. Select,
/// cut and fill all drag out the same geometry and then do different
/// things with it, so the shape vocabulary is declared ONCE here and every
/// verb speaks it. Add a shape and all three verbs get it.
///
/// The alternative — encoding the pair as tool values (`selectRect`,
/// `cutLasso`, …) — is a cross product, and it grows like one: three verbs
/// by four shapes is twelve tool values, twelve library tiles, twelve
/// action ids and twelve labels in five languages, for four shapes.
///
/// Adding a value here is a deliberately LOUD change: the drawing code
/// switches on this enum exhaustively, so the analyzer names every place
/// that has to learn the new shape.
enum CanvasShapeKind {
  /// Drag two opposite corners; the outline is the box between them.
  rect,

  /// Freehand — the outline follows the pointer and closes on release.
  lasso,
}
