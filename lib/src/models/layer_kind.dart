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

  /// A TEXT layer (R5, §6-s): the drawing layer's sibling — frames and
  /// exposure work exactly like animation, but a cel's PICTURE is text
  /// parameters ([Frame.textContent]) instead of pen strokes: the brush
  /// is refused, editing re-types the parameters, and the raster the
  /// stack composites is a projection baked into the ordinary cel store
  /// on every edit (the import-cel grammar). Rasterize converts the row
  /// into a plain animation layer — the pixels stay, the parameters go.
  text('text'),

  /// Sound-effect track: rows for the timesheet's SE column. Drawable like
  /// an animation layer (exposure blocks mark SE timing; frame names carry
  /// the labels); sorts into its own timeline section between the drawing
  /// cels and the camera. Every cut keeps at least two (the sheet's S1·S2).
  se('se'),

  /// Camera-work instruction row (FI/FO/PAN … chips): carries instruction
  /// events, never drawing frames, and sorts into the camera section. Every
  /// cut keeps at least one. Displayed as the "direction layer" — the
  /// camera section names three types apart (camera, direction, transition)
  /// and this is the CUT-scoped one.
  instruction('instruction'),

  /// The TRANSITION row: the same instruction events one level up —
  /// TRACK-owned with keys on the track's GLOBAL frame axis, exactly like
  /// [Track.seLayers], so a span may straddle a cut boundary. That is what
  /// an O.L is: the outgoing cut's F.O and the incoming cut's F.I over one
  /// shared span.
  ///
  /// It is the same machinery as [instruction] — the span create/edge-grip
  /// gestures, [InstructionEvent], the edit dialog and the bowtie painter
  /// all serve it unchanged. Only two things differ: its vocabulary picker
  /// is filtered to the transition terms
  /// ([cameraInstructionIsTransition]), and inside a CUT's timeline it is
  /// READ-ONLY — the cut view windows it for reading, authoring happens on
  /// the global axis ("글로벌 트랙이 메인, 컷 타임라인은 보여주기만").
  transition('transition'),

  /// The cut's camera track: selecting it puts the canvas into camera
  /// manipulation mode and its timeline row shows camera keyframes. Exactly
  /// one per cut, auto-created, holds no drawing frames.
  camera('camera'),

  /// An ADJUSTMENT layer (R6b, §6-z): a row with no picture of its own
  /// whose EFFECT CHAIN applies to everything composited BELOW it — the
  /// 4th cel-less kind after [folder], [instruction] and [camera].
  ///
  /// Its SCOPE follows the folder rules Photoshop and CSP already taught
  /// the stack (§6-z3): an adjustment inside a PASS-THROUGH folder leaks
  /// out and keeps filtering below the folder, while a BUFFERING folder
  /// (a real blend, opacity < 1, or effects of its own) stops it — put the
  /// adjustment in a buffered folder and it filters that group alone.
  ///
  /// It carries effects but NO transform: there is nothing of its own to
  /// move, and moving what it filters is not a thing a transform could
  /// mean. Its OPACITY is the effect MIX (Photoshop's rule), not a fade —
  /// 50 % means half-strength grade, never a half-transparent stack.
  adjustment('adjustment');

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
    LayerKind.text ||
    LayerKind.se => true,
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
  };
}

/// The ACTION-section DRAWING kinds: the rows whose cels hold artwork.
/// Everything that means "a real drawing row" — attach bases, cel export —
/// asks this rather than listing the kinds again. The TEXT row belongs:
/// its cels are pictures (typed, not penned), it carries attaches and
/// exports cels; only the brush itself asks the narrower
/// [layerKindAcceptsBrushInput].
bool layerKindIsDrawingCel(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text => true,
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
  };
}

/// Whether [kind] holds OTHER rows rather than a picture of its own — the
/// group kinds. Membership is [Layer.folderId]; the group row sits directly
/// above its contiguous member run.
bool layerKindGroupsLayers(LayerKind kind) => kind == LayerKind.folder;

/// Whether the brush may land on [kind]'s cels (R6-④). Narrower than
/// [layerKindIsDrawingCel] since the TEXT kind: a text cel's picture is
/// typed parameters, so the pen is refused there the way it is on a
/// referenced image — the kind-level version of the same "derived
/// content" rule. SE cels exist for timing/dialogue data and
/// instruction/camera rows carry notation — the pen must never draw on
/// any of them.
bool layerKindAcceptsBrushInput(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation || LayerKind.storyboard || LayerKind.image => true,
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
  };
}

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
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder ||
    LayerKind.adjustment => true,
    // The TRANSITION row carries no pixels and no chain of its own: what it
    // holds is a boundary annotation the compositor READS, never a surface
    // in a cut's stack. It sits with the camera for the same reason — it is
    // about the picture rather than in it.
    LayerKind.transition || LayerKind.camera => false,
  };
}

/// Whether [kind] FILTERS what is composited below it instead of adding a
/// picture — the adjustment layer's whole contract (R6b).
///
/// The composite treats such a row like a folder in one respect and unlike
/// it in another: neither contributes a surface, but a folder collects the
/// rows that POINT AT IT while an adjustment collects everything below it
/// in its scope. Both answers live here so no walk has to name the kind.
bool layerKindFiltersBelow(LayerKind kind) => kind == LayerKind.adjustment;

/// Whether [kind] contributes PIXELS of its own to the composite (a cel
/// surface). SE and instruction rows composite (they carry FX and can host
/// the canvas dialogue) but resolve no artwork today; they still answer
/// true because their frames, if any, paint like a cel. Folder rows
/// composite their MEMBERS' buffer, and ADJUSTMENT rows the stack below
/// them — never a surface of their own.
bool layerKindPaintsArtwork(LayerKind kind) =>
    layerKindComposites(kind) &&
    !layerKindGroupsLayers(kind) &&
    !layerKindFiltersBelow(kind);

/// Whether [kind]'s [Layer.opacity] is the row's own picture opacity — the
/// thing the master-opacity bar and "set all layers" write. The camera
/// row's slider drives the camera-view DIM instead (a display notifier, not
/// layer state), so bulk opacity edits must not touch it.
bool layerKindHasPictureOpacity(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder ||
    // The adjustment's slider IS its own opacity — it just means MIX
    // rather than fade (Photoshop's rule), so the bulk-opacity commands
    // may write it like any other row's.
    LayerKind.adjustment => true,
    // Read-only in a cut, so there is no picture opacity for a bulk sweep
    // to write. Answering true here is what made "set all layers" try to
    // write a row the cut does not own.
    LayerKind.transition || LayerKind.camera => false,
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
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder => true,
    // An ADJUSTMENT row has no picture of its own to move, and moving what
    // it filters is not something a transform could mean — its twirl-down
    // shows the Effects groups alone.
    // Nothing of the TRANSITION row's own to move either — it is notation
    // on the track's axis, read-only where a cut can see it.
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.adjustment => false,
  };
}

/// The kinds of row a rail can show, for the ONE question "does this row own a
/// Transform group?".
///
/// A layer row answers through its [LayerKind]; the V row is a TRACK and has no
/// layer kind — which is exactly why it used to answer nowhere and had its
/// group hardcoded on.
enum TimelineTransformSubject { layer, track }

/// THE answer to "does this row own a Transform group" — pose lanes, an
/// opacity/fade lane, keys of its own — for every kind of row a rail shows.
///
/// ★Stated as a rule rather than settled by deleting one row's lanes, because
/// it is a rule that may be wanted for OTHER rows (user, 2026-08-10: "혹시
/// 다른 행에서도 추가할수있는 규칙이거든? 그러니 공통사용가능하게 해줘"). A row
/// that should not own a transform says so HERE, in one case, instead of having
/// its lanes removed by hand at every rail that draws them.
///
/// The V row answers NO since the O.L round. `Track.transformTrack` was AE
/// PRECOMP semantics — a whole track's finished output moved and scaled on the
/// camera's stage — which only means something when several tracks stack. With
/// no V-track authoring there is never a second track, and moving the only one
/// is moving the film, which is the camera's job. Its opacity lane carried the
/// cut fade; F.I/F.O spans on the transition row carry that now, where the
/// span's length IS the ramp and two overlapping cuts can hold different values
/// — the one thing a single lane per track could not do.
bool timelineRowOwnsTransform({
  required TimelineTransformSubject subject,
  LayerKind? layerKind,
}) {
  return switch (subject) {
    TimelineTransformSubject.layer =>
      layerKind != null && layerKindHasLayerTransform(layerKind),
    TimelineTransformSubject.track => false,
  };
}

/// A row's FX switches read as ONE answer, for the layer-label master
/// button (R8): every group on, every group off, or a mix of the two.
///
/// [mixed] is what makes that button a master rather than a second
/// independent bypass — it says "some of this row's FX are off" and a tap
/// resolves the whole row one way.
enum LayerFxState { on, off, mixed }

/// Whether [kind]'s [Layer.transformEnabled] switch means anything (R8).
///
/// Everything but the ADJUSTMENT row, which has no transform at all — so
/// its master switch reads its effects alone, and counting a meaningless
/// `transformEnabled: true` would make an all-effects-off adjustment
/// report [LayerFxState.mixed].
///
/// The CAMERA row is in: its transform lives on [Cut.camera] rather than
/// on the row, but the switch that bypasses that work is still the row's
/// own — so the flag is where it is stored.
bool layerKindHasTransformFxSwitch(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder ||
    LayerKind.camera => true,
    // No transform and no chain to bypass, so the master switch would read
    // an always-on flag and report every row mixed.
    LayerKind.transition || LayerKind.adjustment => false,
  };
}

/// Whether [kind] authors its own composite-time EFFECT chain
/// ([Layer.effects], R6). Everything but the camera — which is the frame,
/// not a thing inside it, so it has no picture of its own to filter (a
/// camera-wide grade would belong to the track's FX, not to this row).
///
/// This is where the ADJUSTMENT row parts company with
/// [layerKindHasLayerTransform]: it is the one kind that carries effects
/// and no transform, which is the whole point of it.
bool layerKindHasLayerEffects(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.folder ||
    LayerKind.adjustment => true,
    // A grade on a boundary annotation has nothing to filter — and the row
    // is read-only where a cut can reach it anyway.
    LayerKind.transition || LayerKind.camera => false,
  };
}

/// Whether a row of [kind] copies into a NEW 겸용컷 (겸용컷 생성) — the
/// ACTION-section rows whose content is shared between the cuts that reuse
/// the same drawing ("액션란은 다 공유", user 2026-07-30).
///
/// Animation, image and text rows share their pictures (§6-z5); the folder
/// rows that hold them share so the structure matches; and an ADJUSTMENT
/// row shares too (R6b) — see [layerKindMirrorsEffects] for what that has
/// to mean for a row whose only content is FX.
///
/// The STORYBOARD row is the deliberate exception: a cut holds at most one,
/// and a conte panel belongs to its own cut. SE/instruction/camera rows are
/// per-use fixtures.
bool layerKindLinksIntoLinkedCut(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.folder ||
    LayerKind.adjustment => true,
    LayerKind.storyboard ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera => false,
  };
}

/// Whether a row of [kind] joins a 겸용 변경 (converting two EXISTING cuts
/// to share) — a NARROWER question than [layerKindLinksIntoLinkedCut].
///
/// ★ The difference is whether POSITION survives. 겸용컷 생성 copies a
/// stack wholesale, so every row lands exactly where it was. A CONVERT
/// unions two different stacks: a row the other side lacks is APPENDED at
/// the end and stripped of its folder. For a drawing row that is a z-order
/// choice. For an ADJUSTMENT row the position IS the meaning — appended at
/// the top it grades the entire stack instead of the two rows it was
/// scoped to, so one "shared" row would render two different pictures and
/// the effect mirror would keep feeding both. It stays per-cut here; make
/// the linked cut with 겸용컷 생성 to share a grade, or add an adjustment
/// to the joined cut yourself.
bool layerKindJoinsLinkedCutConvert(LayerKind kind) =>
    layerKindLinksIntoLinkedCut(kind) && !layerKindFiltersBelow(kind);

/// Whether [kind]'s EFFECT CHAIN mirrors across a 겸용 link group.
///
/// For every drawing row the answer is NO: the chain is per-use 연출, the
/// same rule the transform lanes follow ("레인만 각자"). The ADJUSTMENT row
/// inverts it, because its chain is not decoration ON a picture — it IS the
/// row's entire content. A shared adjustment whose chain stayed local would
/// arrive in the other cuts as an empty shell that filters nothing, so for
/// this kind the chain is what "그림은 공유" means. Diverging per cut is
/// still available the ordinary way: 독립시키기.
bool layerKindMirrorsEffects(LayerKind kind) => layerKindFiltersBelow(kind);

/// Whether a cut may hold at most ONE row of [kind] (R9 #7).
///
/// The STORYBOARD row is the cut's picture of itself — the conte panel, the
/// V-row strip and the cut thumbnail all resolve "the cut's storyboard" as
/// a single answer, so a second one would make that question ambiguous
/// everywhere it is asked. The CAMERA row was already a singleton by
/// construction ([LayerList.cameraLayer] says "exactly one per cut"); it
/// joins the predicate so the rule has one name instead of two habits.
///
/// This gates every route that can MAKE a row — Add Layer, duplicate,
/// paste and link-duplicate — not just the menu.
bool layerKindIsSingletonPerCut(LayerKind kind) {
  return switch (kind) {
    LayerKind.storyboard || LayerKind.camera => true,
    LayerKind.animation ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
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
    LayerKind.text ||
    LayerKind.instruction => true,
    // The TRANSITION row is track-owned like SE: duplicating it would
    // recreate a shape the model retired (one row per track).
    LayerKind.transition ||
    // The adjustment stands down with the folder for a STRUCTURAL reason,
    // not a payload one (the payload carries composite state now): what an
    // adjustment does is decided by WHERE it sits, and a paste lands it
    // wherever the paste lands. Its grade would be a different picture
    // there, so the row is made in place instead of pasted.
    LayerKind.se ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
  };
}

/// Whether a row of [kind] is READ-ONLY where a cut can see it — the
/// user's law for the transition row: "글로벌 트랙이 메인, 컷 타임라인은
/// 보여주기만".
///
/// Selection may still land on it (arrow-walking the rows must not skip a
/// row the eye can see), but every verb that would CHANGE it — rename,
/// move, delete, edge drag — refuses. Those verbs live on the global axis,
/// in the storyboard panel, where the span really is; here the row's local
/// placement is a projection and editing it would be editing a lie.
bool layerKindIsReadOnlyInCut(LayerKind kind) => kind == LayerKind.transition;

/// Whether a row of [kind] may be RE-ORDERED by dragging it in a cut's rail.
///
/// 🚨A5-4 (유저 2026-08-22): 「위에서부터 **카메라/트랜지션/디렉션** 고정 …
/// 카메라·트랜지션 = **드래그 불가**, 디렉션 = **디렉션끼리만**」
///
/// The camera row's place is the top of its section and the transition's is
/// under it; neither is a preference, so neither offers a grip. Direction
/// rows still drag — among themselves, which the drop policy's rank check
/// enforces (`timelineCameraSectionRank`).
///
/// ⚠️Not the same question as [layerKindIsReadOnlyInCut]. That one is about
/// a row whose truth lives on another axis, and the transition answers yes
/// to both for different reasons; the camera row is fully editable here and
/// simply has nowhere else to be.
bool layerKindReordersInCut(LayerKind kind) =>
    kind != LayerKind.camera && kind != LayerKind.transition;

/// Whether a row of [kind] carries INSTRUCTION EVENTS rather than cels — the
/// sheet's CAM column shape: named spans with a bar arrow or an O.L bowtie,
/// their writing on the row overlay instead of in the cells.
///
/// 🚨This is a PREDICATE because two kinds answer yes and the timeline used to
/// ask `kind == LayerKind.instruction` at eight separate sites (user 2026-08-11:
/// the transition row's spans drew nothing in a cut, and a range selection on it
/// covered nothing). A row that carries instructions needs all eight: the span
/// overlays, the def-table identity, the exposure adapter that turns events into
/// paper blocks, the glyph and semantics suppression that keeps the cells blank
/// under a span, and the cursor layer's exposure read — which is what a range
/// selection measures. Miss one and the row is half-drawn.
///
/// ⚠️It does NOT license editing. The EDGE GRIPS ask this AND
/// [layerKindIsReadOnlyInCut]: the transition row's local placement is a
/// projection, so a grip there would be dragging a lie.
bool layerKindCarriesInstructions(LayerKind kind) {
  return switch (kind) {
    LayerKind.instruction || LayerKind.transition => true,
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.se ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
  };
}

/// Whether [kind] is a FIXED kind — one the user can neither convert a
/// layer into nor convert away from (the camera fixture, folders and
/// adjustments, whose kind IS their structure; instruction rows carry
/// their own guard alongside).
bool layerKindIsFixed(LayerKind kind) =>
    kind == LayerKind.camera ||
    layerKindGroupsLayers(kind) ||
    layerKindFiltersBelow(kind);

/// Whether [kind] can be exported as a cel image (the cel-export scope).
/// The camera has no artwork, SE rows are timing data and folders hold
/// their members' cels rather than one of their own.
bool layerKindExportsCels(LayerKind kind) {
  return switch (kind) {
    LayerKind.animation ||
    LayerKind.storyboard ||
    LayerKind.image ||
    LayerKind.text ||
    LayerKind.instruction => true,
    // Track-owned rows are not part of a cut's cel scope.
    LayerKind.se ||
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
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
    LayerKind.instruction ||
    // The TRANSITION row is why it is a row at all: the sheet's camera
    // group needs a column to print O.L/F.I/F.O into, and a column is what
    // a row gets. (A ruler mark would have had no column to print in.)
    LayerKind.transition => true,
    // Text rows annotate the picture (cut numbers on paper), not the
    // sheet — printed cel columns stay the field's vocabulary. An
    // adjustment is 촬영 direction with no cel to print at all.
    LayerKind.text ||
    LayerKind.image ||
    LayerKind.camera ||
    LayerKind.folder ||
    LayerKind.adjustment => false,
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
/// frames). Its STORED form says that as ONE real 1-frame block plus a
/// fixed end-side HOLD (D22), and the repository's covering
/// normalization re-tiles that hold's ghosts through every duration
/// change — the coverage is the row's law, not any block's length.
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
