enum LayerKind {
  animation('animation'),
  storyboard('storyboard'),

  /// A PICTURE layer (BG/BOOK, imported stills): ONE cel by definition,
  /// held over the whole cut — the covering grammar the storyboard row
  /// speaks ("the row end IS the cut end"), minus the conte semantics.
  /// Frame names default to none (the layer's own name addresses the
  /// picture); a normal image layer is drawn on like any cel, a
  /// REFERENCED one ([Layer.mediaReference]) shows a library asset and
  /// refuses the brush. Replaces the old `art` kind, which drew and
  /// composited exactly like animation and only differed in icon.
  image('image'),

  /// A GROUP: a layer that holds structure instead of a picture — "그림만
  /// 못 그릴 뿐인 레이어" (user, 2026-07-23). It has no cels, no timesheet
  /// column and takes no brush, but it carries an eye, a static opacity, a
  /// blend mode and FX lanes exactly like any other layer, and its members
  /// composite into ITS buffer before those apply. Membership is the
  /// members' [Layer.folderId] pointer; the stack list stays the single
  /// truth of order, with the folder row sitting directly ABOVE its
  /// contiguous member run.
  folder('folder'),

  /// Sound-effect track: rows for the timesheet's SE column. Drawable like
  /// an animation layer (exposure blocks mark SE timing; frame names carry
  /// the labels); sorts into its own timeline section between the drawing
  /// cels and the camera. Every cut keeps at least two (the sheet's S1·S2).
  se('se'),

  /// Camera-work instruction row (FI/FO/PAN … chips): carries instruction
  /// events, never drawing frames, and sorts into the camera section. Every
  /// cut keeps at least one.
  instruction('instruction'),

  /// The cut's camera track: selecting it puts the canvas into camera
  /// manipulation mode and its timeline row shows camera keyframes. Exactly
  /// one per cut, auto-created, holds no drawing frames.
  camera('camera');

  const LayerKind(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  static LayerKind fromJson(Object? json) {
    // Legacy alias: the retired `art` kind drew and composited exactly
    // like animation (its enum doc said as much) — old dev files load as
    // what they always behaved as.
    if (json == 'art') {
      return LayerKind.animation;
    }
    for (final kind in LayerKind.values) {
      if (json == kind.jsonValue) {
        return kind;
      }
    }

    throw ArgumentError.value(
      json,
      'kind',
      'Layer kind must be one of '
          '${LayerKind.values.map((kind) => '"${kind.jsonValue}"').join(', ')}.',
    );
  }
}

/// Whether rows of [kind] hold drawing frames on the cel timeline (exposure
/// blocks, X cells, marks, comma drags). Camera rows mirror keyframes,
/// instruction rows carry instruction events and folder rows hold other
/// rows instead.
bool layerKindHoldsDrawings(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.se => true,
    LayerKind.instruction || LayerKind.camera || LayerKind.folder => false,
  };
}

/// The ACTION-section DRAWING kinds: the rows whose cels hold pen artwork.
/// Everything that means "a real drawing row" — brush targets, attach
/// bases, cel export — asks this rather than listing the three kinds again.
bool layerKindIsDrawingCel(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation || LayerKind.storyboard || LayerKind.image => true,
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.camera ||
    LayerKind.folder => false,
  };
}

/// Whether [kind] holds OTHER rows rather than a picture of its own — the
/// group kinds. Membership is [Layer.folderId]; the group row sits directly
/// above its contiguous member run.
bool layerKindGroupsLayers(LayerKind kind) => kind == LayerKind.folder;

/// Whether the brush may land on [kind]'s cels (R6-④): only the
/// drawing-section kinds. SE cels exist for timing/dialogue data (the
/// upcoming on-canvas dialogue display is driven by their transform, not
/// strokes) and instruction/camera rows carry notation — the pen must
/// never draw on any of them.
bool layerKindAcceptsBrushInput(LayerKind kind) => layerKindIsDrawingCel(kind);

// ---------------------------------------------------------------------------
// Semantic row predicates.
//
// Every one of these used to be written inline as `kind == LayerKind.camera`
// at ~35 call sites, which meant each new "layer that is not quite a drawing
// layer" had to re-walk all of them. They are named for what the caller
// actually MEANS, so a new kind answers each question once, here.
// ---------------------------------------------------------------------------

/// Whether [kind] takes part in the composited picture at all — the walk
/// [resolveCutFrameCompositeEntries] makes over the stack. The camera is
/// the frame, not a thing inside it; every other row either paints
/// ([layerKindPaintsArtwork]) or groups rows that do.
bool layerKindComposites(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder => true,
    LayerKind.camera => false,
  };
}

/// Whether [kind] contributes PIXELS of its own to the composite (a cel
/// surface). SE and instruction rows composite (they carry FX and can host
/// the canvas dialogue) but resolve no artwork today; they still answer
/// true because their frames, if any, paint like a cel. Folder rows
/// composite their MEMBERS' buffer, never a surface of their own.
bool layerKindPaintsArtwork(LayerKind kind) =>
    layerKindComposites(kind) && !layerKindGroupsLayers(kind);

/// Whether [kind]'s [Layer.opacity] is the row's own picture opacity — the
/// thing the master-opacity bar and "set all layers" write. The camera
/// row's slider drives the camera-view DIM instead (a display notifier, not
/// layer state), so bulk opacity edits must not touch it.
bool layerKindHasPictureOpacity(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder => true,
    LayerKind.camera => false,
  };
}

/// Whether [kind] authors its transform through [Layer.transformTrack].
/// The camera moves through the cut's camera track instead, so writing a
/// layer transform onto it is a programming error.
bool layerKindHasLayerTransform(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder => true,
    LayerKind.camera => false,
  };
}

/// Whether a row of [kind] can be copied to the layer clipboard,
/// duplicated or pasted. The camera is a fixture (exactly one per cut) and
/// SE rows are track-owned — duplicating either would recreate a shape the
/// model retired. Folders stand down in v1: a folder copy has to carry its
/// members, which the single-layer payload cannot express.
bool layerKindIsClipboardCopyable(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.instruction => true,
    LayerKind.se || LayerKind.camera || LayerKind.folder => false,
  };
}

/// Whether [kind] is a FIXED kind — one the user can neither convert a
/// layer into nor convert away from (the camera fixture and folders, whose
/// kind is their structure; instruction rows carry their own guard
/// alongside).
bool layerKindIsFixed(LayerKind kind) =>
    kind == LayerKind.camera || layerKindGroupsLayers(kind);

/// Whether [kind] can be exported as a cel image (the cel-export scope).
/// The camera has no artwork, SE rows are timing data and folders hold
/// their members' cels rather than one of their own.
bool layerKindExportsCels(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.instruction => true,
    LayerKind.se || LayerKind.camera || LayerKind.folder => false,
  };
}

/// Whether [kind] takes a CEL column on the printed timesheet. The camera
/// prints in the CAM group (its own column, driven by the cut's camera
/// track), rows that only group other rows print nothing, and an IMAGE
/// row is one nameless held picture — a column of blank cells would say
/// nothing (the real sheets keep BG out of the cel columns).
bool layerKindTakesTimesheetColumn(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.se ||
    LayerKind.instruction => true,
    LayerKind.image || LayerKind.camera || LayerKind.folder => false,
  };
}

/// Whether [kind]'s exposures leave NO GAPS: every block runs to the next
/// one's start and the last runs to the cut's end (design E).
///
/// The storyboard row is the conte sheet lying down, and a conte has no
/// holes — a panel covers frames until the next panel begins. So a block's
/// length is not stored so much as implied: growing the cut extends the last
/// block, deleting a block hands its frames to the one before it, and an
/// edge drag is the ordinary comma resize with the cut's length riding the
/// row end (edge unification — the row has no front-edge grips, so no drag
/// can open a hole).
///
/// Every other drawing kind keeps real gaps — an animation row with nothing
/// on frame 7 means nothing is drawn on frame 7.
///
/// The IMAGE row speaks the same covering grammar: one cel by definition,
/// held from the cut's first frame to its last (a BG has no "off"
/// frames). The single block is the degenerate no-divisions case, and the
/// repository's covering normalization keeps the stored block equal to
/// the cut length through every duration change.
bool layerKindCoversWithoutGaps(LayerKind kind) =>
    kind == LayerKind.storyboard || kind == LayerKind.image;

/// Whether [kind] holds ONE cel by definition — the image layer's
/// contract: the picture is the layer, so a second cel (and the
/// create-drawing verb once one exists) has nothing to mean. Cross-cut
/// paper switching happens through cel NAMES and the 겸용 link banks,
/// never through a second cel in the same cut.
bool layerKindHoldsSingleCel(LayerKind kind) => kind == LayerKind.image;

/// Whether [kind] may carry REPEAT/hold regions (the `N/H/R` run edges).
///
/// The storyboard row refuses them (design E, user's rule): a conte panel is
/// a thing you draw on and write memos against, and a repeat instance is
/// derived — it would own no memo of its own while looking exactly like a
/// panel that does. Copy the frames instead and the copies are real blocks.
bool layerKindAcceptsRepeatRegions(LayerKind kind) =>
    layerKindHoldsDrawings(kind) && !layerKindCoversWithoutGaps(kind);
