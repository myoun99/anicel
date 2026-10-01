part of '../timeline_controller.dart';

/// THE FRAME NAMES — whether a frame can be renamed, the frames new names
/// would collide with, and naming and joining them — as their own object.
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

  /// The drawings of [layer] already holding a name [names] would give —
  /// each drawing [names] renames, to the one holding its new name. An
  /// emptied name clashes with nothing: no name, no identity to share.
  ///
  /// ⚠️A clash INSIDE the batch is no conflict. The drawing holding the
  /// name is renamed by the same edit, so the name is free by the time it
  /// lands — numbering `3 4` as `4 5` moves 4 out of 5's way (I-18).
  Map<FrameId, FrameId> nameConflicts(
    Layer layer,
    Map<FrameId, String?> names,
  ) {
    final holders = <String, FrameId>{};
    for (final frame in layer.frames) {
      final held = frame.name;
      if (held != null && !names.containsKey(frame.id)) {
        holders.putIfAbsent(held, () => frame.id);
      }
    }
    return {
      for (final MapEntry(key: frameId, value: name) in names.entries)
        frameId: ?holders[normalizeFrameName(name)],
    };
  }

  /// ⛔The SE rows' door, and theirs alone: a name and a speaker in ONE
  /// undo step (the SE instance window, `SeEntries`). Every other rename —
  /// the frame rename, its link, 자동 이름 지정 — is [nameFramesForLayer].
  void renameFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required String? name,
    bool allowDuplicateName = false,
    SeEntryFields? seEntry,
  }) {
    final before = _controller._requireLayer(layerId);
    _controller._requireFrameInLayer(layer: before, frameId: frameId);
    if (!allowDuplicateName &&
        nameConflicts(before, {frameId: name}).isNotEmpty) {
      return;
    }

    final normalizedName = normalizeFrameName(name);
    final nextFrames = before.frames
        .map(
          (frame) => frame.id != frameId
              ? frame
              : switch (seEntry) {
                  // The SE block's own fields land in the same edit as its
                  // dialogue — the SE dialog commits them as ONE undo step.
                  // ↩️It was a name plus an `updateSeName` flag; I-20's
                  // delivery would have made that one flag answer for two
                  // fields, so the fields travel as one record instead.
                  (:final seName, :final seType) => frame.copyWith(
                    name: normalizedName,
                    seName: normalizeFrameName(seName),
                    seType: seType,
                  ),
                  null => frame.copyWith(name: normalizedName),
                },
        )
        .toList(growable: false);
    final after = before.copyWith(frames: nextFrames);
    if (after == before) {
      return;
    }

    _controller._applyLayerEdit(before: before, after: after);
  }

  /// Names [layerId]'s drawings and JOINS others onto the drawing already
  /// holding their name — ONE layer edit, so ONE undo step.
  ///
  /// [names] gives each drawing its name; an emptied one unnames it, the
  /// rename's own rule. [joins] moves every block of THIS lane that shows a
  /// key drawing onto the drawing its value names — 「같은 이름 = 같은 그림」
  /// said by the blocks, never by two drawings answering to one name — and
  /// the drawing left behind goes from the bank unless another lane of the
  /// bank still shows it (F-136, [bankLanesOf]).
  ///
  /// ⚠️A JOINED drawing is never renamed. One that another lane still shows
  /// stays in the bank under its own name; given the new one it would be the
  /// second drawing of that name, which is the thing the join exists to
  /// avoid.
  ///
  /// ★ONE body for the frame rename, its link and 자동 이름 지정 (I-18): the
  /// single rename and the single link are its one-entry calls. It was the
  /// rename and `linkFrameForLayer` — a name, and a join written a frame at
  /// a time — until a press had to do both across many drawings at once.
  void nameFramesForLayer({
    required LayerId layerId,
    Map<FrameId, String?> names = const {},
    Map<FrameId, FrameId> joins = const {},
  }) {
    final before = _controller._requireLayer(layerId);
    for (final frameId in {...names.keys, ...joins.keys, ...joins.values}) {
      _controller._requireFrameInLayer(layer: before, frameId: frameId);
    }
    final lane = joins.isEmpty ? before.timeline : _joined(before, joins);
    final bank = _controller.bankLanesOf(layerId);
    final frames = <Frame>[];
    for (final frame in before.frames) {
      if (!joins.containsKey(frame.id)) {
        frames.add(
          names.containsKey(frame.id)
              ? frame.copyWith(name: normalizeFrameName(names[frame.id]))
              : frame,
        );
      } else if (bank.exposes(frame.id, lane: lane)) {
        frames.add(frame);
      }
    }
    final after = before.copyWith(
      frames: frames,
      timeline: lane,
      audioClips: _controller._audioClipsForFrames(before, frames),
    );
    if (after != before) {
      _controller._applyLayerEdit(before: before, after: after);
    }
  }

  /// [layer]'s lane with every drawing block of a key of [joins] showing
  /// that key's value instead.
  SplayTreeMap<int, TimelineExposure> _joined(
    Layer layer,
    Map<FrameId, FrameId> joins,
  ) => SplayTreeMap.of({
    for (final MapEntry(key: index, value: exposure) in layer.timeline.entries)
      index: switch (exposure.isDrawing ? joins[exposure.frameId] : null) {
        final target? => exposure.copyWith(frameId: target),
        null => exposure,
      },
  });

  String? normalizeFrameName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
