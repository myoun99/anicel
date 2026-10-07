/// The SHAPE a drag-out tool traces on the canvas.
///
/// Deliberately orthogonal to the VERB that consumes the outline. Select,
/// cut and fill all drag out the same geometry and then do different
/// things with it, so the shape vocabulary is declared ONCE here and every
/// verb speaks it. Add a shape and all three verbs get it.
///
/// ↩️Every verb spoke every shape until the SHAPE tool (I-69, 2026-10-07),
/// whose verb DRAWS what is traced and whose line has no inside: a shape
/// with one ([canvasShapeEncloses]) still reaches select, cut and fill
/// from one entry, and which shapes a verb speaks is the verb's to say
/// (`canvasToolShapes`).
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

  /// Drag two opposite corners; the outline is the ellipse inscribed in
  /// the box between them.
  ellipse,

  /// Freehand — the outline follows the pointer and closes on release.
  lasso,

  /// Tapped out vertex by vertex, joined by straight lines, and closed by
  /// tapping the first vertex again or pressing confirm.
  ///
  /// The only shape with no drag verb, and the only one whose outline
  /// exists between gestures — which is why the open trace lives on the
  /// selection channel rather than inside the layer that draws it.
  polygon,

  /// Drag from one end to the other; the shape is the segment between
  /// them. The one shape with no inside, so nothing that acts on what an
  /// outline encloses speaks it.
  line,
}

/// Whether [kind] is an outline with an inside — what select, cut and fill
/// act on.
///
/// Exhaustive on purpose: a new shape fails to compile here until it has
/// said which it is.
bool canvasShapeEncloses(CanvasShapeKind kind) => switch (kind) {
  CanvasShapeKind.rect ||
  CanvasShapeKind.ellipse ||
  CanvasShapeKind.lasso ||
  CanvasShapeKind.polygon => true,
  CanvasShapeKind.line => false,
};
