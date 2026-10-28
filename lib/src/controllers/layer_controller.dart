import '../core/identity_memo.dart';
import '../models/attached_layer_resolve.dart';
import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../services/command.dart';
import '../services/editing/default_layer_helpers.dart';
import '../services/commands/cut_command_input_planner.dart';
import '../services/commands/link_mirror.dart' show eyeMirrorRows;
import '../services/commands/update_layer_blend_mode_command.dart';
import '../services/commands/update_layer_collapsed_command.dart';
import '../services/commands/update_layer_display_command.dart';
import '../services/commands/update_layer_opacity_command.dart';
import '../services/history_manager.dart';
import '../services/project_lookup.dart';
import '../services/project_repository.dart';
import 'row_twirl_writer.dart';

class LayerController {
  LayerController({
    required ProjectRepository repository,
    required HistoryManager historyManager,
    required CutId? cutId,
    required FrameId frameId,
    LayerId? initialActiveLayerId,
    List<Layer> Function()? trackSeDisplayLayers,
    Layer Function()? trackTransitionDisplayLayer,
  }) : _repository = repository,
       _historyManager = historyManager,
       _cutId = cutId,
       _defaultFrameId = frameId,
       _trackSeDisplayLayers = trackSeDisplayLayers,
       _trackTransitionDisplayLayer = trackTransitionDisplayLayer,
       _activeLayerId = initialActiveLayerId {
    if (_activeLayerId != null && !_hasLayer(_activeLayerId!)) {
      throw StateError('Layer not found: $_activeLayerId');
    }
    _activeLayerId ??= layers.isEmpty ? null : layers.first.id;
  }

  final ProjectRepository _repository;
  final HistoryManager _historyManager;

  /// NULL = no active cut (gap state, UI-R9 #3): [layers] is empty and
  /// layer creation stands down.
  final CutId? _cutId;
  final FrameId _defaultFrameId;

  /// The track's SE rows as cut-local DISPLAY clones (the session windows
  /// them per active cut). They join [layers] so selection, row rendering
  /// and every read path see one composed list; mutations detect SE ids
  /// and edit the track's GLOBAL layers instead (never these clones).
  final List<Layer> Function()? _trackSeDisplayLayers;

  /// The track's ONE transition row, likewise a display clone.
  /// It is a PROJECTION rather than a window: a span crossing this cut's
  /// boundary shows at full length on the side it belongs to, so the clone
  /// deliberately disagrees with the global row about where the span sits.
  final Layer Function()? _trackTransitionDisplayLayer;

  LayerId? _activeLayerId;

  /// The cut's rows as every reader reads them: its own layers, the
  /// track's SE rows and its transition row.
  ///
  /// 🚨ONE LIST PER STATE (I-57, 10-14): composed once for the cut and the
  /// clones the session hands it, and handed back until one of them is
  /// another object ([IdentityMemo]). Composed per ask, it was composed
  /// 326 times a cut crossing on the AMMI OP — every `layerById` and every
  /// `activeLayerId` asks it — each ask walking the film for the cut.
  List<Layer> get layers {
    final cut = _cut.resolve(
      identity: _repository.requireProject(),
      build: () => (found: _findCutOrNull()),
    ).found;
    if (cut == null) {
      // Gap state: no rows at all — not even the track SE clones (the
      // timeline shows its empty state).
      return const <Layer>[];
    }
    final trackSe = _trackSeDisplayLayers?.call() ?? const <Layer>[];
    final transition = _trackTransitionDisplayLayer?.call();
    return _layers.resolve(
      identity: cut,
      key: (trackSe, transition),
      build: () => _composed(cut, trackSe, transition),
    );
  }

  final _cut = IdentityMemo<({Cut? found})>();
  final _layers = IdentityMemo<List<Layer>>();

  List<Layer> _composed(Cut cut, List<Layer> trackSe, Layer? transition) {
    final cutLayers = cut.layers;
    // SYNCED attach rows join as DISPLAY clones whose timeline mirrors
    // the base through the cell links (W5) — the same read-clone pattern
    // as the track SE rows below; writes address the real layers via
    // commands. FREE attach rows (UI-R21 #3) pass through untouched —
    // they own their timeline like any drawing layer.
    final displayed = [
      for (final layer in cutLayers) attachedRowAsShown(layer, cutLayers),
    ];
    // The TRANSITION row joins on the same terms as the SE rows: track
    // owned, read here through a display clone, written only on the global
    // axis. It sorts into the camera section by kind like any other row.
    if (trackSe.isEmpty && transition == null) {
      return List.unmodifiable(displayed);
    }
    final composed = [...displayed, ...trackSe];
    if (transition != null) {
      // Directly BEFORE the camera row in raw order, which puts the camera row
      // on TOP on screen: the horizontal timeline reverses raw order, so last
      // in the list is highest. The order is direction, transition, camera
      // with the camera highest (user 2026-08-10).
      //
      // Appending it — which is what this did — put the TRANSITION on top for
      // exactly that reason.
      final cameraIndex = composed.cameraIndex;
      composed.insert(
        cameraIndex < 0 ? composed.length : cameraIndex,
        transition,
      );
    }
    return List.unmodifiable(composed);
  }

  LayerId? get activeLayerId {
    _ensureActiveLayerExists();
    return _activeLayerId;
  }

  Layer? get activeLayer {
    final id = activeLayerId;
    if (id == null) {
      return null;
    }

    return layers.firstWhere((layer) => layer.id == id);
  }

  bool get hasActiveLayer => activeLayer != null;

  FrameId get frameId {
    final layer = activeLayer;
    if (layer == null) {
      return _defaultFrameId;
    }
    if (layer.frames.isEmpty) {
      throw StateError('Active layer has no frames: ${layer.id}');
    }
    return layer.frames.first.id;
  }

  Frame? get activeFrame {
    final layer = activeLayer;
    if (layer == null || layer.frames.isEmpty) {
      return null;
    }
    return layer.frames.first;
  }

  void selectLayer(LayerId layerId) {
    if (!_hasLayer(layerId)) {
      throw StateError('Layer not found: $layerId');
    }
    _activeLayerId = layerId;
  }

  void addLayer({required Layer layer, int? insertionIndex}) {
    final cutId = _cutId;
    if (cutId == null) {
      return; // Gap state: nowhere to add (the UI stands down too).
    }
    // Layer EXISTENCE is shared structure: a row created here appears in
    // every 겸용 sibling too, with ids planned up front so redo reuses
    // them.
    _historyManager.execute(
      plannedAddLayerCommand(
        repository: _repository,
        cutId: cutId,
        layer: layer,
        insertionIndex: insertionIndex ?? insertionIndexAboveActiveLayer(),
      ),
    );
    _activeLayerId = layer.id;
  }

  void addLayerWithDefaults({
    required LayerId layerId,
    LayerKind kind = LayerKind.animation,
  }) {
    final cut = _findCutOrNull();
    if (cut == null) {
      return;
    }
    addLayer(
      layer: createDefaultAnimationLayer(
        layerId: layerId,
        cut: cut,
      ).copyWith(kind: kind),
    );
  }

  /// 🚨T9 (유저 2026-08-13) — THE EYE IS PER-USE. So were static opacity and
  /// blend, and ⛔this REVERSED 「레인만 각자, 나머지는 하나」, which used to be
  /// quoted right here: 「링크레이어 … **비지블/정적불투명도는 독립되게
  /// 하고싶음.** 지금 하나 바꾸면 링크된 레이어들 바꿈. **겸용컷에서도 같은
  /// 로직 쓰지? 똑같이 적용되도록**」.
  ///
  /// ★What a link shares is the DRAWING — that is the whole of what it means
  /// for two rows to be one cel. How loudly a given cut shows that cel is
  /// that cut's own business, and mirroring it made one drawing impossible to
  /// use twice at two strengths, which is an ordinary reason to link.
  ///
  /// The 겸용 cut needed no separate answer because it never had one: both
  /// went through the same registry, so this is ONE deletion rather than two
  /// edits — and the mirror helper died with it, since these three were its
  /// only callers ([[duplication-program]]: the last step is removing the
  /// predecessor).
  ///
  /// ↩️THE BLEND AND THE STATIC OPACITY WENT BACK TO THE GROUP (유저
  /// 2026-10-04, F-278): 「겸용컷 블렌드모드도 공유하도록 하자 … 불투명도도
  /// 공유하도록할까 생각하는데 어떻지? 보이기만 독립적으로 하고」, then
  /// 「불투명도 공유도 같이 작업한거지? 블렌드 공유랑 같이?」. Of the three,
  /// the EYE alone is each use's own now — [setLayerBlendMode] ·
  /// [setLayerOpacity]. A use that shows the layer at its own strength keys
  /// the transform's opacity lane, which is each use's own.
  /// Sets visibility on MANY layers as ONE undo step.
  ///
  /// 🚨THE REPORT THAT STARTED THIS: 유저 「일괄로 버튼 조작하고 언두하면
  /// 바꼈던 레이어들 **다 한번에 언두되야하는데 안됨**」. A sweep down the
  /// eye column and Solo both change a screenful of rows; looping a
  /// single-layer call would make the undo one press per row, which is
  /// the same complaint in a new place.
  ///
  /// ↩️Solo no longer comes through here (F-125, 유저 2026-09-15: 「비지블
  /// 솔로모드 전환은 언두에 기록안되게」): it writes the eyes outside history,
  /// the way zoom changes the view. Show all / Hide all
  /// (`LayerSwitchVerbs.setAllLayersVisibility`) still does.
  ///
  /// ⛔[oneStepOf] is how this repo already collapses many edits into one
  /// entry (the legend's sheet/mark actions land that way), so the batch
  /// goes through it and is not a second mechanism.
  void setLayersVisible({
    required List<LayerId> layerIds,
    required bool visible,
  }) => _executeDisplayBatch(
    layerIds: eyeMirrorRows(_repository.requireProject(), layerIds),
    debugLabel: 'Set layer visibility',
    apply: (layer) =>
        layer.isVisible == visible ? layer : layer.copyWith(isVisible: visible),
  );

  /// Sets static opacity on MANY layers as ONE undo step — the master bar —
  /// each one's link group with it ([setLayerOpacity]).
  void setLayersOpacity({
    required List<LayerId> layerIds,
    required double opacity,
  }) {
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    _executeAcrossLinks(
      layerIds: layerIds,
      debugLabel: 'Set layer opacity',
      command: (cutId, layerId) => UpdateLayerOpacityCommand(
        repository: _repository,
        cutId: cutId,
        layerId: layerId,
        opacity: clamped,
      ),
    );
  }

  /// Sets the composite blend on MANY layers as ONE undo step — each one's
  /// link group with it ([setLayerBlendMode]).
  void setLayersBlendMode({
    required List<LayerId> layerIds,
    required LayerBlendMode blendMode,
  }) => _executeAcrossLinks(
    layerIds: layerIds,
    debugLabel: 'Set layer blend mode',
    command: (cutId, layerId) => UpdateLayerBlendModeCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layerId,
      blendMode: blendMode,
    ),
  );

  /// One [command] per layer of [layerIds] — each addressed in its own cut
  /// ([_cutOfRow]), so it reaches its link group — as ONE undo step. A row
  /// with no cut to be addressed in is passed by.
  void _executeAcrossLinks({
    required List<LayerId> layerIds,
    required String debugLabel,
    required Command Function(CutId cutId, LayerId layerId) command,
  }) {
    final commands = [
      for (final layerId in layerIds)
        if (_cutOfRow(layerId) case final cutId?) command(cutId, layerId),
    ];
    if (commands.isNotEmpty) {
      _executeAsOneStep(debugLabel, commands);
    }
  }

  /// The cut a row's command is addressed in ([cutWritingRow]): the cut
  /// that HOLDS it, else this controller's — a track's own row is held by
  /// none, and takes the active cut as it always did (null in a gap:
  /// nothing to address it in).
  ///
  /// ↩️It was this controller's cut for every row, 「nothing in the gap
  /// state」. The storyboard draws ONE head for a track's conte rows (I-73)
  /// and presses it under whichever cut is active, or in a gap: the row is
  /// some cut's, and that cut is where its link group and its seat are.
  CutId? _cutOfRow(LayerId layerId) =>
      cutWritingRow(_repository.requireProject(), layerId, standing: _cutId);

  /// [command] for one row, addressed in its own cut ([_cutOfRow]) so it
  /// reaches the row's head — nothing for a track's own row in a gap, which
  /// no cut addresses. What the row's opacity, blend, group fold and
  /// twirls are each written through (F-360 brought the third and fourth)
  /// — a track's own row's twirls aside ([RowTwirlWriter]).
  void _executeInItsCut(
    LayerId layerId,
    Command Function(CutId cutId) command,
  ) {
    final cutId = _cutOfRow(layerId);
    if (cutId != null) {
      _historyManager.execute(command(cutId));
    }
  }

  void _executeDisplayBatch({
    required List<LayerId> layerIds,
    required String debugLabel,
    required Layer Function(Layer layer) apply,
  }) => _executeAsOneStep(debugLabel, [
    for (final layerId in layerIds)
      UpdateLayerDisplayCommand(
        repository: _repository,
        layerId: layerId,
        debugLabel: debugLabel,
        apply: apply,
      ),
  ]);

  /// [commands], one per layer, as the ONE history entry a batch is — the
  /// batch of each use's own values ([_executeDisplayBatch]) and the batch
  /// of a link group's ([_executeAcrossLinks]) land the same way.
  void _executeAsOneStep(String debugLabel, List<Command> commands) =>
      _historyManager.executeAsOneStep(
        '$debugLabel (${commands.length} layers)',
        commands,
      );

  void toggleLayerVisibility(LayerId layerId) {
    final project = _repository.requireProject();
    final nextVisible = !requireLayerAnywhere(project, layerId).isVisible;
    // 🚨THROUGH HISTORY since 2026-08-29 (유저: 「눈을 껏다키든 뭐든 다
    // 언두」). It used to write straight to the repository under a rule
    // called "the visibility-toggle precedent" — but this repo already
    // undid eighteen other layer edits, including the layer's NAME, so
    // the eye was the outlier and not the rule.
    //
    // 🚨A TRACK'S CONTE ROWS WEAR ONE EYE (I-73, 유저 2026-10-08: 「6.
    // 이거만 눈이랑 불투명도조차 링크하도록. 그거마저 머리로서 하나로되도록
    // 통일」) — the one row whose eye is its head's, where a link group's is
    // still each use's own (T9, [UpdateLayerDisplayCommand]). The pressed
    // row takes it, and the track's conte structure lays it on the rest
    // (F-343, `trackWithItsConteLaid`) — ↩️where every row at the seat was
    // written here.
    //
    // 🚨AND A TRACK'S CAMERAS WEAR ONE EYE — the camera view's switch
    // (F-363, 유저 2026-10-15: 「레이어가 눈이랑 불투명도 바꾸면 언두
    // 저장되니까. 기본적으로 레이어 버튼은 그게 기준」): written to every one
    // of them ([eyeMirrorRows]) as any set of eyes is.
    setLayersVisible(layerIds: [layerId], visible: nextVisible);
  }

  /// The layer-list twirl, persisted like CSP — the LINK GROUP'S, one fold
  /// for every use of the row. Folder rows use it to swallow their members,
  /// bases their attach group (F-360); the eye, static opacity and blend a
  /// folder carries need no method of their own, because a folder IS a
  /// layer and rides [toggleLayerVisibility] / [setLayerOpacity] /
  /// [setLayerBlendMode] — the eye per-use since T9, the opacity and the
  /// blend its link group's (F-278).
  ///
  /// ↩️It was per-use like the eye. 유저 2026-10-05 (F-302): 「겸용컷 …
  /// 폴더/어태치 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친
  /// 상태 접힌 상태 공유하라는것. 법통일」 — the mirror is
  /// [UpdateLayerCollapsedCommand]'s.
  ///
  /// 🚨UNDOABLE too (유저 2026-08-29: 「접기도 마찬가지야. 폴더든
  /// 어태치든」). ⛔I had argued the twirl was the one to leave out —
  /// it changes no output, so it looked like paging a reference. 유저 said
  /// no: the rule is 「무언가를 바꾸는 동작은 기본 이럼」, and a fold is
  /// something you did and may want back. Attach rows need no separate
  /// answer: they fold through this same `collapsed` field.
  ///
  /// ↩️That last sentence was not so when it was written — the attach fold
  /// was a set on the rail's view (`RailView`), undone through a command of
  /// its own, and every reload opened it back up. It is so since F-360.
  void toggleLayerCollapsed(LayerId layerId) => _executeInItsCut(
    layerId,
    (cutId) => UpdateLayerCollapsedCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layerId,
      collapsed: !requireLayerAnywhere(
        _repository.requireProject(),
        layerId,
      ).collapsed,
    ),
  );

  /// Where this cut's rows' twirls are written — the property lanes and
  /// the groups among them, a track's own rows on their track.
  late final RowTwirlWriter twirls = RowTwirlWriter(
    repository: _repository,
    historyManager: _historyManager,
    cutOfRow: _cutOfRow,
  );

  /// The audio counterpart of [toggleLayerVisibility]: silences the SE
  /// row's sounds without touching them.
  void toggleLayerMuted(LayerId layerId) {
    // Mute changes what the film SOUNDS like, so it is an edit for the
    // same reason the eye is one — the old comment here called it "view
    // state, not undoable", which was the eye's rule and inherited its
    // mistake.
    _historyManager.execute(
      UpdateLayerDisplayCommand(
        repository: _repository,
        layerId: layerId,
        debugLabel: 'Toggle layer mute',
        apply: (layer) => layer.copyWith(muted: !layer.muted),
      ),
    );
  }

  /// R26 #30: the layer's composite blend — the LINK GROUP'S, one value
  /// for every use of the layer.
  ///
  /// ↩️It was per-use like the eye since T9. 유저 2026-10-04 (F-278):
  /// 「겸용컷 블렌드모드도 공유하도록 하자. 지금 블렌드모드 겸용컷끼리
  /// 같은레이어인데 독립적이야 … 보이기만 독립적으로 하고」 — the mirror is
  /// [UpdateLayerBlendModeCommand]'s.
  void setLayerBlendMode({
    required LayerId layerId,
    required LayerBlendMode blendMode,
  }) => _executeInItsCut(
    layerId,
    (cutId) => UpdateLayerBlendModeCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layerId,
      blendMode: blendMode,
    ),
  );

  /// Static opacity is the LINK GROUP'S, one value for every use of the
  /// layer, like the blend beside it. Per-use FADES belong to the local FX
  /// opacity lane — that split is unchanged.
  ///
  /// ↩️It was per-use like the eye (T9: 「this one stopped reaching across
  /// the link」). 유저 2026-10-04 (F-278): 「불투명도도 공유하도록 …
  /// 보이기만 독립적으로 하고」 — the mirror is [UpdateLayerOpacityCommand]'s.
  void setLayerOpacity({required LayerId layerId, required double opacity}) =>
      _executeInItsCut(
        layerId,
        (cutId) => UpdateLayerOpacityCommand(
          repository: _repository,
          cutId: cutId,
          layerId: layerId,
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
        ),
      );

  Cut? _findCutOrNull() {
    if (_cutId == null) {
      return null;
    }
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == _cutId) {
          return cut;
        }
      }
    }
    return null;
  }

  bool _hasLayer(LayerId layerId) {
    return layers.any((layer) => layer.id == layerId);
  }

  /// The cut-list slot directly above the active layer — where Add Layer
  /// puts a new row, and where a file dropped on the canvas lands.
  int insertionIndexAboveActiveLayer() {
    // Insertion is into the CUT's layer list; a track-SE active layer is
    // not in it and appends like no-selection does.
    final cutLayers = _findCutOrNull()?.layers ?? const <Layer>[];
    final id = _activeLayerId;
    if (id == null) {
      return cutLayers.length;
    }

    final index = cutLayers.indexWhere((layer) => layer.id == id);
    return index < 0 ? cutLayers.length : index + 1;
  }

  void _ensureActiveLayerExists() {
    final id = _activeLayerId;
    if (id == null) {
      _activeLayerId = layers.isEmpty ? null : layers.first.id;
      return;
    }

    if (!_hasLayer(id)) {
      _activeLayerId = layers.isEmpty ? null : layers.first.id;
    }
  }
}
