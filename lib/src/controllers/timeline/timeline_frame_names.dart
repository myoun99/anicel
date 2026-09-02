part of '../timeline_controller.dart';

/// THE FRAME NAMES — whether a frame can be renamed, the frame a new
/// name would collide with, and renaming it — as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). It reaches the controller through `_controller`.
class _TimelineFrameNames {
  _TimelineFrameNames(this._controller);

  final TimelineController _controller;

  bool canRenameFrameAt({required Layer layer, required int frameIndex}) {
    // Ghost cells RESOLVE to their anchor cel deliberately (UI-R19b,
    // user decision): renaming from a repeat instance renames the
    // source — a feature, not a leak. Only DELETE stays refused on
    // ghosts (they are derived; there is no block to remove).
    return _controller.resolveFrameForLayer(
          layer: layer,
          frameIndex: frameIndex,
        ) !=
        null;
  }

  FrameId? conflictingFrameIdForRename({
    required Layer layer,
    required FrameId frameId,
    required String? name,
  }) {
    _controller._requireFrameInLayer(layer: layer, frameId: frameId);
    final normalizedName = normalizeFrameName(name);
    if (normalizedName == null) {
      return null;
    }

    for (final frame in layer.frames) {
      if (frame.id != frameId && frame.name == normalizedName) {
        return frame.id;
      }
    }

    return null;
  }

  void renameFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required String? name,
    bool allowDuplicateName = false,
    String? seName,
    bool updateSeName = false,
  }) {
    final before = _controller._requireLayer(layerId);
    _controller._requireFrameInLayer(layer: before, frameId: frameId);
    if (!allowDuplicateName) {
      final conflictingFrameId = conflictingFrameIdForRename(
        layer: before,
        frameId: frameId,
        name: name,
      );
      if (conflictingFrameId != null) {
        return;
      }
    }

    final normalizedName = normalizeFrameName(name);
    final normalizedSeName = normalizeFrameName(seName);
    final nextFrames = before.frames
        .map(
          (frame) => frame.id == frameId
              ? (updateSeName
                    // Name + SE speaker name land in the same edit — the SE
                    // dialog commits both as ONE undo step.
                    ? frame.copyWith(
                        name: normalizedName,
                        seName: normalizedSeName,
                      )
                    : frame.copyWith(name: normalizedName))
              : frame,
        )
        .toList(growable: false);
    final after = before.copyWith(frames: nextFrames);
    if (after == before) {
      return;
    }

    _controller._applyLayerEdit(before: before, after: after);
  }

  String? normalizeFrameName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
