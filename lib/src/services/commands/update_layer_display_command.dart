import '../../models/layer.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// 🚨★★★A LAYER'S DISPLAY STATE IS AN EDIT, so it undoes.
///
/// 유저 2026-08-28: 「무언가를 바꾸는 동작은 기본 이럼. 프레임블록 편집도
/// 언두 되는게 보통이고 지금 그렇게 되있는데 왜 레이어편집이라고 언두에
/// 안넣은건지 애초에 이해할수없음. 눈을 껏다키든 뭐든 다 언두고 그리는동안
/// 눈 껏다켠뒤 컨트롤z면 당연히 눈이 바뀌는게 맞는거임.」
///
/// The audit behind that answer found the inconsistency in the code: this
/// repo already had eighteen undoable layer commands — name, mark, kind,
/// effects, timesheet, timeline, transform, instructions — while the eye,
/// the opacity, the blend and the mute wrote straight through the
/// repository. Renaming a layer undid; hiding it did not.
///
/// ⛔THE PRECEDENT THIS REVERSES IS NARROWER THAN ITS NAME. Two other
/// writers cite "the visibility-toggle precedent" and both must KEEP
/// writing directly: export scope is a setting, and paging a reference
/// "must never be undoable" (유저 확정 ⑤㉑). What they actually rely on is
/// that VIEW STATE and SETTINGS are not document edits — still true. Only
/// the eye was misfiled, because it changes what the film looks like.
///
/// ⛔PER-USE, deliberately: this does NOT walk `linkMirrorTargets` the way
/// [UpdateLayerNameCommand] does. T9 decided a linked layer's eye, static
/// opacity and blend belong to the USE and not to the group ("this one
/// stopped reaching across the link"), and making them undoable does not
/// reopen that. Propagating here would silently reverse a decision nobody
/// asked about.
///
/// ⛔ONE LAYER. A sweep down the eye column, Solo and the master opacity
/// bar all change many rows and must undo in ONE press (유저: 「일괄로 버튼
/// 조작하고 언두하면 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」) — but
/// [CompositeCommand] is already how this repo does that, and the legend's
/// sheet/mark actions already land that way. A second batching mechanism
/// here would be a copy of one that works.
class UpdateLayerDisplayCommand implements Command {
  UpdateLayerDisplayCommand({
    required this.repository,
    required this.layerId,
    required this.apply,
    required this.debugLabel,
  });

  final ProjectRepository repository;
  final LayerId layerId;

  /// The change itself. Returning the layer unchanged is allowed and
  /// costs nothing — [execute] still records the previous state, and
  /// undoing a no-op is a no-op.
  final Layer Function(Layer layer) apply;

  /// 🚨A DEBUG LINE, NOT A LABEL — and the name mattered. `Command.description`
  /// is read by no UI in this repo (grepped 2026-08-31); it exists for a
  /// history dump and for reading a stack trace. Calling this `label` made it
  /// look like a word on screen, and F-37's scan for untranslated UI counted
  /// it as debt four times over. ⛔It must NOT be translated: a diagnostic
  /// that changes with the reading language is a diagnostic nobody can grep.
  final String debugLabel;

  _DisplayState? _previous;

  @override
  String get description => '$debugLabel $layerId';

  @override
  void execute() {
    // ⛔CAPTURED ONCE. Redo re-runs execute, and re-reading the layer then
    // would record the state the redo is about to overwrite — the undo
    // after it would restore the wrong thing.
    _previous ??= _DisplayState.of(
      requireLayerAnywhere(repository.requireProject(), layerId),
    );
    repository.updateLayer(layerId: layerId, update: apply);
  }

  @override
  void undo() {
    final previous = _previous;
    if (previous == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateLayer(layerId: layerId, update: previous.restoreOnto);
  }
}

/// The four fields this command owns, captured together.
///
/// Restoring all four rather than just the one that changed is correct
/// BECAUSE they are set one at a time: each command's snapshot is the
/// state immediately before its own change, so the other three in it are
/// already whatever the previous commands left. Tracking which single
/// field moved would be a second thing to keep in sync for no gain.
class _DisplayState {
  const _DisplayState({
    required this.isVisible,
    required this.opacity,
    required this.blendMode,
    required this.muted,
    required this.collapsed,
  });

  factory _DisplayState.of(Layer layer) => _DisplayState(
    isVisible: layer.isVisible,
    opacity: layer.opacity,
    blendMode: layer.blendMode,
    muted: layer.muted,
    collapsed: layer.collapsed,
  );

  final bool isVisible;
  final double opacity;
  final LayerBlendMode blendMode;
  final bool muted;
  final bool collapsed;

  Layer restoreOnto(Layer layer) => layer.copyWith(
    isVisible: isVisible,
    opacity: opacity,
    blendMode: blendMode,
    muted: muted,
    collapsed: collapsed,
  );
}
