import 'package:flutter/foundation.dart' show nonVirtual, protected;

import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../command.dart';
import '../project_repository.dart';

/// THE UNDO SCAFFOLD OF EVERY COMMAND THAT EDITS THE LINK REGISTRY BY
/// SNAPSHOT: refuse to undo what was never executed, run the command's own
/// inverse, then put the registry back exactly as it stood before the
/// first execute.
///
/// Four commands wrote that out by hand — 폴더 생성, 레이어 삭제, 폴더 해체,
/// 링크 해제 — and what varies between them is only the inverse walk, which
/// is a subclass hook rather than a flag.
///
/// ⚠️Remove the command's own payload FIRST, then restore the registry.
/// [UnlinkLayerCommand] is where the order is load-bearing and says so:
/// 「Remove the forked cels FIRST (keys still self-resolving), then restore
/// the registry — reads flow back to the canonical cels.」 The template
/// fixes that order for everyone.
///
/// ⛔THE SNAPSHOT IS TAKEN ONCE, on the first execute. Redo re-runs
/// execute(), and re-reading the registry then would record the state the
/// redo is about to overwrite — the same reasoning
/// [ToggleIdInSetCommand] states about its captured membership.
///
/// ⛔The three commands that fold the registry into ONE `updateProject`
/// (LinkDuplicateLayerCommand, ConvertToLinkedCutCommand,
/// CreateLinkedCutCommand) are a DIFFERENT write law — one atomic project
/// write, no snapshot — and are deliberately not here. Neither is
/// [DeleteCutCommand]: its undo has steps AFTER the registry restore (the
/// cel re-keys and the active-cut seat), so its tail is not this tail.
/// None of the four is a straggler for the next audit to collect.
abstract class LinkRegistrySnapshotCommand implements Command {
  LinkRegistrySnapshotCommand({required this.repository});

  final ProjectRepository repository;

  LayerLinkRegistry? _registryBefore;
  bool _hasExecuted = false;

  /// Takes the registry as it stands now, unless a previous execute
  /// already took it.
  ///
  /// 🧪MUTATION: turning `??=` into `=` survives every test today, and is
  /// EQUIVALENT for the four current subclasses — undo restores the
  /// registry to the snapshot, so a redo's second read finds the same
  /// value. It stops being equivalent the moment a subclass executes
  /// twice without an undo between, which is why the rule is stated here
  /// rather than left to each subclass to rediscover.
  @protected
  void snapshotRegistry(Project project) {
    _registryBefore ??= project.linkRegistry;
  }

  /// The last line of a successful [execute].
  @protected
  void markExecuted() {
    _hasExecuted = true;
  }

  @override
  @nonVirtual
  void undo() {
    final before = _registryBefore;
    if (!_hasExecuted || before == null) {
      throw StateError('Command has not been executed.');
    }
    undoBeforeRegistry();
    repository.restoreLinkRegistry(before);
  }

  /// This command's own inverse — everything but the registry. Runs only
  /// after [undo] has established that the command executed, so a payload
  /// captured in execute() may be read non-null here.
  @protected
  void undoBeforeRegistry();
}
