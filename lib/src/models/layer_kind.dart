// ---------------------------------------------------------------------------
// THE LAYER-KIND CAPABILITY TABLE.
//
// Every question the app asks about a row's kind is a COLUMN here, and every
// kind ANSWERS it in its own declaration. A caller reads the field
// (`kind.holdsDrawings`), never a switch of its own.
//
// Every one of these used to be written inline as `kind == LayerKind.camera`
// at ~35 call sites, which meant each new "layer that is not quite a drawing
// layer" had to re-walk all of them. They are named for what the caller
// actually MEANS, so a new kind answers each question once, here.
//
// ⛔THE CLONE SCAN FLAGS THESE AGAINST EACH OTHER AND THEY ARE NOT COPIES
// (audit, 2026-09-04, seventeen candidates read one by one). They share a
// SHAPE — an exhaustive switch over one enum returning a bool — and not an
// algorithm: each names a different fact, and the exhaustiveness is the
// point. Folding them into `Set<LayerKind>` constants would be shorter and
// would take away the compile error that makes a new kind answer here.
//
// 🆕The shape moved to a TABLE (audit round 8, 2026-09-07) and the comment
// above is why it moved to THIS shape and not to sets: the capabilities are
// REQUIRED NAMED PARAMETERS, so adding a kind is still a compile error until
// its author has answered every column — the exact protection the twenty-six
// exhaustive switches were there for, minus twenty-six switches.
//
// ⛔TWO COLUMNS THAT MATCH TODAY ARE STILL TWO COLUMNS. `composites`,
// `hasPictureOpacity` and `hasLayerEffects` hold the same trues right now and
// each keeps its own field: R27 #16 is the standing proof — a predicate two
// questions shared "only because nothing was ever both" had to be split later
// (see [carriesInstructions] and [bandIsInstructionsOnly]).
// ---------------------------------------------------------------------------

enum LayerKind {
  animation(
    'animation',
    holdsDrawings: true,
    isDrawingCel: true,
    acceptsBrushInput: true,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: false,
    exportsCels: true,
    linksIntoLinkedCut: true,
    isSingletonPerCut: false,
    isClipboardCopyable: true,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  ),

  storyboard(
    'storyboard',
    holdsDrawings: true,
    isDrawingCel: true,
    acceptsBrushInput: true,
    coversWithoutGaps: true,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: false,
    exportsCels: true,
    // 🗣️F-84 (유저 2026-09-11): 「확인말한거 그대로 맞아. 내가 원하던게 그거야」
    // — the conte row links like any drawing row: the pictures are one, and
    // each cut exposes them on its own. A cut holds ONE, so it pairs by kind.
    linksIntoLinkedCut: true,
    isSingletonPerCut: true,
    isClipboardCopyable: true,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  ),

  /// A PICTURE layer (BG/BOOK, imported stills): ONE cel by definition,
  /// held over the whole cut — the covering grammar the storyboard row
  /// speaks ("the row end IS the cut end"), minus the conte semantics.
  /// Frame names default to none (the layer's own name addresses the
  /// picture); a normal image layer is drawn on like any cel, a
  /// REFERENCED one ([Layer.mediaReference]) shows a library asset and
  /// refuses the brush. Replaces the old `art` kind, which drew and
  /// composited exactly like animation and only differed in icon.
  image(
    'image',
    holdsDrawings: true,
    isDrawingCel: true,
    acceptsBrushInput: true,
    coversWithoutGaps: true,
    holdsSingleCel: true,
    groupsLayers: false,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: false,
    exportsCels: true,
    linksIntoLinkedCut: true,
    isSingletonPerCut: false,
    isClipboardCopyable: true,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  ),

  /// A GROUP: a layer that holds structure instead of a picture — "그림만
  /// 못 그릴 뿐인 레이어" (user, 2026-07-23). It has no cels, no timesheet
  /// column and takes no brush, but it carries an eye, a static opacity, a
  /// blend mode and FX lanes exactly like any other layer, and its members
  /// composite into ITS buffer before those apply. Membership is the
  /// members' [Layer.folderId] pointer; the stack list stays the single
  /// truth of order, with the folder row sitting directly ABOVE its
  /// contiguous member run.
  folder(
    'folder',
    holdsDrawings: false,
    isDrawingCel: false,
    acceptsBrushInput: false,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: true,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: false,
    exportsCels: false,
    linksIntoLinkedCut: true,
    isSingletonPerCut: false,
    // Folders stand down in v1: a folder copy has to carry its members,
    // which the single-layer payload cannot express.
    isClipboardCopyable: false,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  ),

  /// Sound-effect track: rows for the timesheet's SE column. Drawable like
  /// an animation layer (exposure blocks mark SE timing; frame names carry
  /// the labels); sorts into its own timeline section between the drawing
  /// cels and the camera. Every cut keeps at least two (the sheet's S1·S2).
  se(
    'se',
    holdsDrawings: true,
    isDrawingCel: false,
    // SE cels exist for timing/dialogue data — the pen must never draw on
    // them.
    acceptsBrushInput: false,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: false,
    // Track-owned rows are not part of a cut's cel scope.
    exportsCels: false,
    linksIntoLinkedCut: false,
    isSingletonPerCut: false,
    // SE rows are track-owned — duplicating one would recreate a shape the
    // model retired.
    isClipboardCopyable: false,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: false,
  ),

  /// Camera-work instruction row (FI/FO/PAN … chips): carries instruction
  /// events, never drawing frames, and sorts into the camera section. Every
  /// cut keeps at least one. Displayed as the "direction layer" — the
  /// camera section names three types apart (camera, direction, transition)
  /// and this is the CUT-scoped one.
  instruction(
    'instruction',
    // 🚨R27 #16 (유저 확정 2026-08-25): 「**카메라랑 트랜지션은 지금처럼
    // 못그리는데 디렉션레이어는 그림 그릴수있는 행으로**」. It is a drawing
    // cel that carries instructions; [holdsDrawings] stayed false because
    // that column also answers "does this row wear the drawing row's
    // furniture" — see the field docs.
    holdsDrawings: false,
    isDrawingCel: true,
    acceptsBrushInput: true,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    composites: true,
    hasPictureOpacity: true,
    hasLayerTransform: true,
    hasTransformFxSwitch: true,
    hasLayerEffects: true,
    carriesInstructions: true,
    exportsCels: true,
    // A per-use fixture: every cut already has one, so it does not follow a
    // 겸용 link.
    linksIntoLinkedCut: false,
    isSingletonPerCut: false,
    isClipboardCopyable: true,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  ),

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
  transition(
    'transition',
    holdsDrawings: false,
    isDrawingCel: false,
    acceptsBrushInput: false,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    // The TRANSITION row carries no pixels and no chain of its own: what it
    // holds is a boundary annotation the compositor READS, never a surface
    // in a cut's stack. It sits with the camera for the same reason — it is
    // about the picture rather than in it.
    composites: false,
    // Read-only in a cut, so there is no picture opacity for a bulk sweep
    // to write. Answering true here is what made "set all layers" try to
    // write a row the cut does not own.
    hasPictureOpacity: false,
    // Nothing of the TRANSITION row's own to move — it is notation on the
    // track's axis, read-only where a cut can see it.
    hasLayerTransform: false,
    // No transform and no chain to bypass, so the master switch would read
    // an always-on flag and report every row mixed.
    hasTransformFxSwitch: false,
    // A grade on a boundary annotation has nothing to filter — and the row
    // is read-only where a cut can reach it anyway.
    hasLayerEffects: false,
    carriesInstructions: true,
    exportsCels: false,
    linksIntoLinkedCut: false,
    isSingletonPerCut: false,
    // The TRANSITION row is track-owned like SE: duplicating it would
    // recreate a shape the model retired (one row per track).
    isClipboardCopyable: false,
    isReadOnlyInCut: true,
    reordersInCut: false,
    celNameIsIdentity: true,
  ),

  /// The cut's camera track: selecting it puts the canvas into camera
  /// manipulation mode and its timeline row shows camera keyframes. Exactly
  /// one per cut, auto-created, holds no drawing frames.
  camera(
    'camera',
    holdsDrawings: false,
    isDrawingCel: false,
    acceptsBrushInput: false,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: false,
    composites: false,
    hasPictureOpacity: false,
    hasLayerTransform: false,
    // The CAMERA row is in: its transform lives on [Cut.camera] rather than
    // on the row, but the switch that bypasses that work is still the row's
    // own — so the flag is where it is stored.
    hasTransformFxSwitch: true,
    hasLayerEffects: false,
    carriesInstructions: false,
    exportsCels: false,
    // 🗣️F-84 (유저 2026-09-11): 「겸용컷 지금 카메라레이어가 없네」 and
    // 「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로 통일해줘」 — the camera row
    // links, and keeps the transform law across the group: its lanes are
    // each cut's own, and only a NAMED key carries its value to the others.
    linksIntoLinkedCut: true,
    isSingletonPerCut: true,
    isClipboardCopyable: false,
    isReadOnlyInCut: false,
    reordersInCut: false,
    celNameIsIdentity: true,
  ),

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
  adjustment(
    'adjustment',
    holdsDrawings: false,
    isDrawingCel: false,
    acceptsBrushInput: false,
    coversWithoutGaps: false,
    holdsSingleCel: false,
    groupsLayers: false,
    filtersBelow: true,
    composites: true,
    // The adjustment's slider IS its own opacity — it just means MIX
    // rather than fade (Photoshop's rule), so the bulk-opacity commands
    // may write it like any other row's.
    hasPictureOpacity: true,
    // An ADJUSTMENT row has no picture of its own to move, and moving what
    // it filters is not something a transform could mean — its twirl-down
    // shows the Effects groups alone.
    hasLayerTransform: false,
    // No transform and no chain to bypass, so the master switch would read
    // an always-on flag and report every row mixed.
    hasTransformFxSwitch: false,
    hasLayerEffects: true,
    carriesInstructions: false,
    exportsCels: false,
    linksIntoLinkedCut: true,
    isSingletonPerCut: false,
    // The adjustment stands down with the folder for a STRUCTURAL reason,
    // not a payload one (the payload carries composite state now): what an
    // adjustment does is decided by WHERE it sits, and a paste lands it
    // wherever the paste lands. Its grade would be a different picture
    // there, so the row is made in place instead of pasted.
    isClipboardCopyable: false,
    isReadOnlyInCut: false,
    reordersInCut: true,
    celNameIsIdentity: true,
  );

  const LayerKind(
    this.jsonValue, {
    required this.holdsDrawings,
    required this.isDrawingCel,
    required this.acceptsBrushInput,
    required this.coversWithoutGaps,
    required this.holdsSingleCel,
    required this.groupsLayers,
    required this.filtersBelow,
    required this.composites,
    required this.hasPictureOpacity,
    required this.hasLayerTransform,
    required this.hasTransformFxSwitch,
    required this.hasLayerEffects,
    required this.carriesInstructions,
    required this.exportsCels,
    required this.linksIntoLinkedCut,
    required this.isSingletonPerCut,
    required this.isClipboardCopyable,
    required this.isReadOnlyInCut,
    required this.reordersInCut,
    required this.celNameIsIdentity,
  });

  final String jsonValue;

  /// Whether rows of this kind hold drawing frames on the cel timeline
  /// (exposure blocks, X cells, marks, comma drags). Camera rows mirror
  /// keyframes, instruction rows carry instruction events and folder rows
  /// hold other rows instead.
  ///
  /// ⛔IT IS NOT [isDrawingCel] WITH ONE FEWER KIND. It answers a SECOND
  /// question wherever it is asked in the UI — 「does this row wear the
  /// drawing row's furniture」: the timesheet X in every empty cell, the run
  /// labels over the blocks, the comma-drag grips, the media drop target.
  final bool holdsDrawings;

  /// The ACTION-section DRAWING kinds: the rows whose cels hold artwork.
  /// Everything that means "a real drawing row" — attach bases, cel export —
  /// asks this rather than listing the kinds again; the brush itself asks
  /// [acceptsBrushInput].
  final bool isDrawingCel;

  /// Whether the brush may land on this kind's cels (R6-④). SE cels exist
  /// for timing/dialogue data and instruction/camera rows carry notation —
  /// the pen must never draw on any of them.
  ///
  /// ⚠️A question apart from [isDrawingCel] — what a row IS against whether
  /// a pen may touch it. The two answered differently while the TEXT kind
  /// lived (R5; removed by F-154) and agree on every kind today.
  final bool acceptsBrushInput;

  /// Whether this kind's rows can ghost (onion skin): the kinds the brush
  /// lands on — a ghost is the row's own hand-drawn frames.
  ///
  /// 🚨F-145 (유저 2026-09-17): 「폴더등 어니언스킨 활성화 불가능한 곳에
  /// 서있는데 왼쪽띠의 어니언스킨버튼이 활성화되있고 조작마저가능함.
  /// 비활성화하도록. 낡지않을구조로」. Four readers asked [acceptsBrushInput]
  /// for this and three doors — the rail button, the `O` key and the toggle
  /// itself — did not ask at all. One name answers every one of them now, and
  /// the toggle refuses on its own, so a door added later cannot forget.
  bool get takesOnionSkin => acceptsBrushInput;

  /// Whether this kind's exposures leave NO GAPS: every block runs to the
  /// next one's start and the last runs to the cut's end (design E).
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
  final bool coversWithoutGaps;

  /// Whether this kind holds ONE cel by definition — the image layer's
  /// contract: the picture is the layer, so a second cel (and the
  /// create-drawing verb once one exists) has nothing to mean. Cross-cut
  /// paper switching happens through cel NAMES and the 겸용 link banks,
  /// never through a second cel in the same cut.
  final bool holdsSingleCel;

  /// Whether this kind holds OTHER rows rather than a picture of its own —
  /// the group kinds. Membership is [Layer.folderId]; the group row sits
  /// directly above its contiguous member run.
  final bool groupsLayers;

  /// Whether this kind FILTERS what is composited below it instead of adding
  /// a picture — the adjustment layer's whole contract (R6b).
  ///
  /// The composite treats such a row like a folder in one respect and unlike
  /// it in another: neither contributes a surface, but a folder collects the
  /// rows that POINT AT IT while an adjustment collects everything below it
  /// in its scope. Both answers live here so no walk has to name the kind.
  final bool filtersBelow;

  /// Whether this kind takes part in the composited picture at all — the walk
  /// [resolveCutFrameCompositeEntries] makes over the stack. The camera is
  /// the frame, not a thing inside it; every other row either paints
  /// ([paintsArtwork]) or groups rows that do.
  final bool composites;

  /// Whether this kind's [Layer.opacity] is the row's own picture opacity —
  /// the thing the master-opacity bar and "set all layers" write. The camera
  /// row's slider drives the camera-view DIM instead (a display notifier, not
  /// layer state), so bulk opacity edits must not touch it.
  final bool hasPictureOpacity;

  /// Whether this kind authors its transform through [Layer.transformTrack].
  /// The camera moves through the cut's camera track instead, so writing a
  /// layer transform onto it is a programming error.
  final bool hasLayerTransform;

  /// Whether this kind's [Layer.transformEnabled] switch means anything (R8).
  ///
  /// Everything but the ADJUSTMENT row, which has no transform at all — so
  /// its master switch reads its effects alone, and counting a meaningless
  /// `transformEnabled: true` would make an all-effects-off adjustment
  /// report [LayerFxState.mixed].
  final bool hasTransformFxSwitch;

  /// Whether this kind authors its own composite-time EFFECT chain
  /// ([Layer.effects], R6). Everything but the camera — which is the frame,
  /// not a thing inside it, so it has no picture of its own to filter (a
  /// camera-wide grade would belong to the track's FX, not to this row).
  ///
  /// This is where the ADJUSTMENT row parts company with
  /// [hasLayerTransform]: it is the one kind that carries effects and no
  /// transform, which is the whole point of it.
  final bool hasLayerEffects;

  /// Whether a row of this kind carries INSTRUCTION EVENTS rather than cels —
  /// the sheet's CAM column shape: named spans with a bar arrow or an O.L
  /// bowtie, their writing on the row overlay instead of in the cells.
  ///
  /// 🚨This is a LAW OF ITS OWN because two kinds answer yes and the timeline
  /// used to ask `kind == LayerKind.instruction` at eight separate sites (user
  /// 2026-08-11: the transition row's spans drew nothing in a cut, and a range
  /// selection on it covered nothing). A row that carries instructions needs
  /// all eight: the span overlays, the def-table identity, the exposure adapter
  /// that turns events into paper blocks, the glyph and semantics suppression
  /// that keeps the cells blank under a span, and the cursor layer's exposure
  /// read — which is what a range selection measures. Miss one and the row is
  /// half-drawn.
  ///
  /// ⚠️It does NOT license editing. The EDGE GRIPS ask this AND
  /// [isReadOnlyInCut]: the transition row's local placement is a
  /// projection, so a grip there would be dragging a lie.
  ///
  /// 🆕And since R27 #16 it does not answer for the BAND either — see
  /// [bandIsInstructionsOnly]. Six of the eight facilities above are
  /// really the same question one level down ("does this row have a timeline
  /// of its own?"), and they only looked like this one because nothing had
  /// ever been both.
  final bool carriesInstructions;

  /// Whether this kind can be exported as a cel image (the cel-export scope).
  /// The camera has no artwork, SE rows are timing data and folders hold
  /// their members' cels rather than one of their own.
  final bool exportsCels;

  /// Whether a row of this kind copies into a NEW 겸용컷 (겸용컷 생성) — the
  /// ACTION-section rows whose content is shared between the cuts that reuse
  /// the same drawing ("액션란은 다 공유", user 2026-07-30).
  ///
  /// Animation and image rows share their pictures (§6-z5); the folder
  /// rows that hold them share so the structure matches; and an ADJUSTMENT
  /// row shares too (R6b) — see [mirrorsEffects] for what that has
  /// to mean for a row whose only content is FX.
  ///
  /// The STORYBOARD and CAMERA rows link too (F-84, 유저 2026-09-11). ⛔This
  /// REVERSES the exception that kept them out ("a conte panel belongs to its
  /// own cut", `6ca95e34`, which quoted no one). A cut holds ONE of each
  /// ([isSingletonPerCut]), so they pair by KIND rather than by name; the
  /// conte row shares its pictures, and the camera row keeps the transform
  /// law — lanes each cut's own, a NAMED key one value across the group.
  /// SE/instruction rows stay per-use fixtures.
  ///
  /// IMAGE rows are included (the shared BG is the classic 겸용 case; the
  /// linked copy shares the cel id and the covering normalization re-covers
  /// it) — plus the folder rows that hold them ("폴더 존재/멤버십은 공유
  /// 구조").
  final bool linksIntoLinkedCut;

  /// Whether a cut may hold at most ONE row of this kind (R9 #7).
  ///
  /// The STORYBOARD row is the cut's picture of itself — the conte panel, the
  /// V-row strip and the cut thumbnail all resolve "the cut's storyboard" as
  /// a single answer, so a second one would make that question ambiguous
  /// everywhere it is asked. The CAMERA row was already a singleton by
  /// construction ([LayerList.cameraLayer] says "exactly one per cut"); it
  /// joins the table so the rule has one name instead of two habits.
  ///
  /// This gates every route that can MAKE a row — Add Layer, duplicate,
  /// paste and link-duplicate — not just the menu.
  final bool isSingletonPerCut;

  /// Whether a row of this kind can be copied to the layer clipboard,
  /// duplicated or pasted. The camera is a fixture (exactly one per cut) and
  /// SE rows are track-owned — duplicating either would recreate a shape the
  /// model retired. Folders stand down in v1: a folder copy has to carry its
  /// members, which the single-layer payload cannot express.
  final bool isClipboardCopyable;

  /// Whether a row of this kind is READ-ONLY where a cut can see it — the
  /// user's law for the transition row: "글로벌 트랙이 메인, 컷 타임라인은
  /// 보여주기만".
  ///
  /// Selection may still land on it (arrow-walking the rows must not skip a
  /// row the eye can see), but every verb that would CHANGE it — rename,
  /// move, delete, edge drag — refuses. Those verbs live on the global axis,
  /// in the storyboard panel, where the span really is; here the row's local
  /// placement is a projection and editing it would be editing a lie.
  final bool isReadOnlyInCut;

  /// Whether a row of this kind may be RE-ORDERED by dragging it in a cut's
  /// rail.
  ///
  /// 🚨A5-4 (유저 2026-08-22): 「위에서부터 **카메라/트랜지션/디렉션** 고정 …
  /// 카메라·트랜지션 = **드래그 불가**, 디렉션 = **디렉션끼리만**」
  ///
  /// The camera row's place is the top of its section and the transition's is
  /// under it; neither is a preference, so neither offers a grip. Direction
  /// rows still drag — among themselves, which the drop policy's rank check
  /// enforces (`timelineCameraSectionRank`).
  ///
  /// ⚠️Not the same question as [isReadOnlyInCut]. That one is about
  /// a row whose truth lives on another axis, and the transition answers yes
  /// to both for different reasons; the camera row is fully editable here and
  /// simply has nowhere else to be.
  final bool reordersInCut;

  /// Whether a cel's NAME is its identity on a row of this kind: the rename
  /// REFUSES a second cel under a name already taken and offers to merge
  /// instead (「같은 이름 = 같은 그림」), so a copy that means a NEW cel has to
  /// come out unnamed (F-62: 「그림 복제되고 이름만 없는상태로」).
  ///
  /// 🚨An SE row answers NO. An entry's name is its DIALOGUE, and the same
  /// line may repeat on a sheet — the rename has always let it
  /// (`renameSelectedFrame`). So an SE entry copied independently keeps its
  /// words (F-115, 유저 2026-09-12: 「내용은 이름/대사/링크된 오디오 등 모든
  /// 정보가 똑같음」). ONE column, read by the rename's duplicate check and by
  /// the independent-copy kernel, so the two cannot disagree again.
  final bool celNameIsIdentity;

  /// Whether this kind contributes PIXELS of its own to the composite (a cel
  /// surface). SE and instruction rows composite (they carry FX and can host
  /// the canvas dialogue) but resolve no artwork today; they still answer
  /// true because their frames, if any, paint like a cel. Folder rows
  /// composite their MEMBERS' buffer, and ADJUSTMENT rows the stack below
  /// them — never a surface of their own.
  bool get paintsArtwork => composites && !groupsLayers && !filtersBelow;

  /// Whether a row of this kind joins a 겸용 변경 (converting two EXISTING
  /// cuts to share) — a NARROWER question than [linksIntoLinkedCut].
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
  bool get joinsLinkedCutConvert => linksIntoLinkedCut && !filtersBelow;

  /// Whether this kind's EFFECT CHAIN mirrors across a 겸용 link group.
  ///
  /// For every drawing row the answer is NO: the chain is per-use 연출, the
  /// same rule the transform lanes follow ("레인만 각자"). The ADJUSTMENT row
  /// inverts it, because its chain is not decoration ON a picture — it IS the
  /// row's entire content. A shared adjustment whose chain stayed local would
  /// arrive in the other cuts as an empty shell that filters nothing, so for
  /// this kind the chain is what "그림은 공유" means. Diverging per cut is
  /// still available the ordinary way: 독립시키기.
  bool get mirrorsEffects => filtersBelow;

  /// Whether a row's frame BAND is the instruction adapter and nothing else —
  /// no timeline of its own, so no cels, no names, no marks.
  ///
  /// 🚨R27 #16 (유저 확정 2026-08-25): 「**카메라랑 트랜지션은 지금처럼
  /// 못그리는데 디렉션레이어는 그림 그릴수있는 행으로**」.
  ///
  /// ★A DIRECTION row carries instructions AND has cels now, so "carries
  /// instructions" stopped being the same question as "has no timeline of its
  /// own". They had been one predicate only because nothing was ever both:
  /// the transition row is instructions-only and still is, and every drawing
  /// row carries no instructions. Splitting them here is what lets the
  /// direction row's band show its own drawings with the spans still over
  /// them, and it is why the SPAN OVERLAYS keep asking
  /// [carriesInstructions] — that half did not change.
  bool get bandIsInstructionsOnly => carriesInstructions && !isDrawingCel;

  /// Whether a row can be GIVEN a cel — a frame authored at a timeline index,
  /// which is the thing a brush then writes into.
  ///
  /// 🚨R27 #16 FLIPPED ONE PREDICATE AND NOT THIS ONE (유저 2026-08-27: 「그림은
  /// 그려지지도않아. **프레임이 없다고 뜨거든**」). The direction row became a
  /// drawing cel, but `canCreateDrawingAtCurrentFrame` asks
  /// [holdsDrawings] — false for `instruction` — so there was no way
  /// to make the frame the brush then refused for want of.
  ///
  /// ⛔IT IS NOT [holdsDrawings] WITH ONE MORE KIND. That column
  /// answers a SECOND question wherever it is asked in the UI — 「does this row
  /// wear the drawing row's furniture」: the timesheet X in every empty cell,
  /// the run labels over the blocks, the comma-drag grips, the media drop
  /// target. A direction row wearing those is exactly the kind of thing the
  /// feedback above was about. So the split is here, and the furniture keeps
  /// asking the old one.
  ///
  /// ⚠️SCOPED TO CREATION, deliberately, because the user's sentence was:
  /// 「**그림 그릴 수 있는 기능**(추가로 없으면 블록을 회색으로. 로직은 통일)
  /// **만** 추가하라했지」. Blanking an exposure, duplicating a block, pasting
  /// and marking are other verbs on other rows' terms; widening them together
  /// would be answering a question nobody asked.
  ///
  /// ⛔DERIVED, and the derivation is pinned by a test — the same discipline
  /// [bandIsInstructionsOnly] follows, so the two halves cannot drift
  /// apart the way these two just did.
  bool get takesAuthoredCels => holdsDrawings || isDrawingCel;

  /// Whether this kind is a FIXED kind — one the user can neither convert a
  /// layer into nor convert away from (the camera fixture, folders and
  /// adjustments, whose kind IS their structure; instruction rows carry
  /// their own guard alongside).
  bool get isFixed => this == LayerKind.camera || groupsLayers || filtersBelow;

  /// Whether this kind may carry REPEAT/hold regions (the `N/H/R` run edges).
  ///
  /// The storyboard row refuses them (design E, user's rule): a conte panel is
  /// a thing you draw on and write memos against, and a repeat instance is
  /// derived — it would own no memo of its own while looking exactly like a
  /// panel that does. Copy the frames instead and the copies are real blocks.
  bool get acceptsRepeatRegions => holdsDrawings && !coversWithoutGaps;

  String toJson() => jsonValue;

  static LayerKind fromJson(Object? json) {
    // Legacy aliases: old dev files load as what their rows always were. The
    // retired `art` kind drew and composited exactly like animation (its
    // enum doc said as much); a retired TEXT row's pictures were ordinary
    // baked cels, which is all rasterizing one ever left (F-154).
    if (json == 'art' || json == 'text') {
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
      layerKind != null && layerKind.hasLayerTransform,
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

/// Whether a row's FX apply, read off its master [state]: only OFF means
/// no — a MIXED row is still doing something. Null (no resolver, the host
/// hides the master) reads as applied.
///
/// The one spelling: the session's `isLayerFxEnabled`, the grid hooks and
/// the storyboard's rail rows each wrote `state != LayerFxState.off` with
/// the null-means-on default (the audit's clone scan, 2026-09-06).
bool fxEnabledFromState(LayerFxState? state) =>
    (state ?? LayerFxState.on) != LayerFxState.off;
