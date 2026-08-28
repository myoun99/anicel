import 'package:flutter/foundation.dart';

import '../../models/layer_id.dart';
import '../command.dart';

/// 🚨★★★A LAYER-ROW BUTTON WHOSE STATE LIVES IN A SET, not in the layer.
///
/// 유저 2026-08-29: 「fx접기도 마찬가지고. 아무튼 **레이어에 있는 버튼
/// 싹다**」. Nine buttons sit on a layer row; seven of them change a field
/// on the `Layer` and undo through [UpdateLayerDisplayCommand] or a
/// command of their own. Two do not: onion skin and the lane twirl are
/// each a `ValueNotifier<Set<LayerId>>` — membership, not a field.
///
/// ⛔THE DISTINCTION IS MINE, NOT THE USER'S. I started to explain that
/// undoing these "only changes session state, not the project file", and
/// 유저 cut it off: 「프로젝트 파일이 바뀌란건 무슨소리지? 아무튼 어니언
/// 적용 미적용만 되면 되는건데」. Right — press the button, press Ctrl+Z,
/// the onion comes back. Where the bit is stored is plumbing.
///
/// ⚠️Undo restores the MEMBERSHIP this id had, not the whole set: another
/// row toggled after this command must keep its own state when this one
/// is undone. Snapshotting the set would quietly revert those too.
class ToggleIdInSetCommand implements Command {
  ToggleIdInSetCommand({
    required this.notifier,
    required this.layerId,
    required this.label,
  });

  final ValueNotifier<Set<LayerId>> notifier;
  final LayerId layerId;

  /// What this reads as in the history — "Toggle onion skin".
  final String label;

  bool? _wasMember;

  @override
  String get description => '$label $layerId';

  @override
  void execute() {
    // ⛔CAPTURED ONCE, like every other display command: redo re-runs this,
    // and re-reading membership then would record the state redo is about
    // to overwrite.
    _wasMember ??= notifier.value.contains(layerId);
    _apply(!_wasMember!);
  }

  @override
  void undo() {
    final was = _wasMember;
    if (was == null) {
      throw StateError('Command has not been executed.');
    }
    _apply(was);
  }

  void _apply(bool member) {
    final next = Set<LayerId>.of(notifier.value);
    if (member) {
      next.add(layerId);
    } else {
      next.remove(layerId);
    }
    notifier.value = next;
  }
}
