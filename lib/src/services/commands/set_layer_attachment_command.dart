import '../../models/attached_layer_mount.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// 장착·분리: makes one row an attach row of a base, or turns it back into an
/// ordinary row.
///
/// The command carries the finished [LayerAttachment] rather than the intent
/// that produced it. That is deliberate: the BAKE a detach performs and the
/// cell LINKS a synced mount stores are read off the base's timeline at plan
/// time, and a redo has to write exactly what the first execute wrote — not
/// re-derive it against whatever the timeline looks like later.
///
/// One row per command. A group-wide change (the 겸용 link mirror, an
/// organizer folder's members leaving together) is a [CompositeCommand] of
/// these, because the BAKE differs per cut: cuts share the cel bank but each
/// re-exposes it, so one cut's baked timing is not another's.
class SetLayerAttachmentCommand implements Command {
  SetLayerAttachmentCommand({
    required this.repository,
    required this.layerId,
    required this.attachment,
    this.description = 'Attach layer',
  });

  final ProjectRepository repository;
  final LayerId layerId;
  final LayerAttachment attachment;

  @override
  final String description;

  LayerAttachment? _before;
  bool _hasExecuted = false;

  @override
  void execute() {
    _before ??= LayerAttachment.of(
      requireLayerAnywhere(repository.requireProject(), layerId),
    );
    repository.setLayerAttachment(layerId: layerId, attachment: attachment);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final before = _before;
    if (!_hasExecuted || before == null) {
      throw StateError('Command has not been executed.');
    }
    repository.setLayerAttachment(layerId: layerId, attachment: before);
  }
}
