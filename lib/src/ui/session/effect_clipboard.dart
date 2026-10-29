import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import 'effects_and_fx.dart';
import 'lane_verbs.dart';
import 'session_roles.dart';

/// THE EFFECT BOARD — the effects the last copy of a rail selection's fx
/// headers took, the APP's like the boards beside it (`AppClipboard`: one
/// copy in hand, whichever board took it). By value: an effect holds only
/// numbers and keys, so it pastes into any open project.
class EffectBoard {
  List<LayerEffect>? _copy;

  /// What this board taking a copy lets go of: the pill's other boards
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(List<LayerEffect> copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of another kind.
  void letGo() => _copy = null;
}

/// The EFFECT CLIPBOARD — the shared pill's copy, cut, paste and duplicate
/// of the effects a rail selection names by their header rows.
///
/// 🗣️F-476-Q1 (유저 2026-10-27): 「b + 복제도」 — 「고른 fx 를 복사(잘라내기)
/// 하고, 다른 레이어에 서서 붙여넣으면 그 레이어의 fx 끝에 붙는다(AE 의
/// 이펙트 복사 · 붙여넣기)」, and 「복제 버튼이 고른 fx 를 같은 레이어에 하나
/// 더 만든다(바로 아래에)」.
///
/// ★WHAT IT TAKES IS WHAT DELETE TAKES of the same rows
/// ([LaneVerbs.effectsNamedByRows], F-476): an fx header names its effect,
/// Transform and a parameter row name none.
class EffectClipboard {
  EffectClipboard({
    required EffectBoard board,
    required LaneVerbs laneVerbs,
    required EffectsAndFx effectsAndFx,
    required ChangeSink changes,
  }) : _board = board,
       _laneVerbs = laneVerbs,
       _effectsAndFx = effectsAndFx,
       _changes = changes;

  /// The app's effect board — every open project's clipboard reads and
  /// writes the same one (I-7).
  final EffectBoard _board;
  final LaneVerbs _laneVerbs;
  final EffectsAndFx _effectsAndFx;
  final ChangeSink _changes;

  /// The effects the rail's selection names, row by row.
  List<({Layer row, List<EffectId> effects})> get _named =>
      _laneVerbs.effectsNamedBySelectedRows;

  /// What a copy here takes: the named effects, each row's in the order its
  /// chain holds them.
  List<LayerEffect> get _copyHere => [
    for (final (:row, :effects) in _named)
      ...row.effects.where((effect) => effects.contains(effect.id)),
  ];

  /// Whether the rail's selection names an effect — what a copy, a cut and
  /// a duplicate here act on.
  bool get namesEffects => _named.isNotEmpty;

  void copy() {
    final copy = _copyHere;
    if (copy.isEmpty) {
      return;
    }
    _board._take(copy);
    _changes.notifyChanged();
  }

  /// 잘라내기 of effects: the copy in hand, and those effects off their
  /// rows — as Delete takes them ([LaneVerbs.removeEffectsNamedByRows]) —
  /// as ONE step.
  void cut() {
    final named = _named;
    final copy = _copyHere;
    if (copy.isEmpty) {
      return;
    }
    _board._take(copy);
    _laneVerbs.removeEffectsNamedByRows(named, step: 'Cut effects');
    _changes.notifyChanged();
  }

  /// Whether the hand holds effects.
  bool get holdsEffects => _board._copy != null;

  /// Whether a paste onto [holder] puts effects down: the hand holds some
  /// its chain takes ([EffectsAndFx.canAddEffectCopies]).
  bool canPasteOnto(EffectChainHolder holder) => switch (_board._copy) {
    final copy? => _effectsAndFx.canAddEffectCopies(holder, copy),
    null => false,
  };

  /// 독립 붙여넣기 of the effects in hand: at the end of [holder]'s chain,
  /// each an effect of its own.
  ///
  /// ⛔No 링크 붙여넣기: what links two uses of one effect is its id, shared
  /// by rows made by copying one row — a link group's, never a paste's — so
  /// a link has nothing of the copy to keep and the independent paste alone
  /// is lit (F-115).
  void pasteOnto(EffectChainHolder holder) {
    if (_board._copy case final copy?) {
      _effectsAndFx.addEffectCopies(holder, copy);
    }
  }

  /// 복제 of the named effects, each right below itself
  /// ([LaneVerbs.duplicateEffectsNamedByRows]).
  void duplicate() => _laneVerbs.duplicateEffectsNamedByRows(_named);
}
