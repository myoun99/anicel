import 'dart:async' show unawaited;

import '../../models/audio_clip.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/cut_frame_composite_plan.dart'
    show resolveExposedFrameAt;
import '../../services/project_lookup.dart' show requireLayerAnywhere;
import 'active_cut_controllers.dart';
import 'media_pool.dart';
import 'se_entries.dart';
import 'session_roles.dart';

/// The SOUNDS AN SE ROW CARRIES — importing one onto the row under the
/// playhead, linking one off the media pool, the clip edits the block edit
/// window makes (remove, slide, gain), and the unlink it offers.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// G3, 2026-09-07). It names the roles and siblings it needs in its
/// constructor. ↩️It also owned the in-flight slide drag — the one host field
/// this cluster wrote — and the fade, fade-curve and envelope edits, until
/// the audio lane went: a row's volume keys carry the fades now (I-140).
class AudioClips {
  AudioClips({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required MediaPool pool,
    required SeEntries seEntries,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _pool = pool,
       _seEntries = seEntries;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final MediaPool _pool;
  final SeEntries _seEntries;

  /// Whether the active layer can take an audio clip (SE rows only).
  bool get canImportAudioToActiveLayer =>
      _selection.activeLayer?.kind == LayerKind.se;

  /// Links [filePath] to the SE instance under the playhead — sounds are
  /// FRAME-LINKED like drawings: the carrying block is the sound's window
  /// (start, length) and deleting the block silences it. Importing onto an
  /// empty cell creates the SE instance first (its own undo step), then
  /// links the sound (one more).
  void addAudioClipToActiveSeLayer(
    String filePath, {
    required bool copyIntoProject,
  }) {
    final layer = _selection.activeLayer;
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    // Conform from scratch — the file may have changed on disk since a
    // previous import.
    final effectivePath = _pool.importAudioFile(filePath);
    final current = _controllers.timelineController.currentFrameIndex;
    final frameIndex = current < 0 ? 0 : current;
    var frame = resolveExposedFrameAt(layer, frameIndex);
    if (frame == null) {
      _seEntries.createSeEntryAtCurrentFrame(name: '');
      final created = _selection.activeLayer;
      frame = created == null
          ? null
          : resolveExposedFrameAt(created, frameIndex);
      if (frame == null) {
        return;
      }
    }
    final carrier = _selection.activeLayer ?? layer;
    // The pool learns every imported file (its own undo step, like the
    // SE-instance creation above) so the browser can offer it for reuse.
    // The choice travels WITH it: the pool entry is what the save reads to
    // decide whose bytes go inside the archive, so an import that dropped
    // it here would leave a carried sound outside the file it was carried
    // into.
    unawaited(_pool.addMediaAssets([effectivePath], carried: copyIntoProject));
    _project.cutCommandCoordinator.updateLayerAudioClips(
      cutId: _project.requireActiveCut.id,
      layerId: carrier.id,
      audioClips: [
        ...carrier.audioClips,
        AudioClip(filePath: effectivePath, frameId: frame.id),
      ],
      description: 'Import audio',
    );
    _changes.notifyChanged();
  }

  /// ⛔THE SHAPE EVERY AUDIO-CLIP EDIT HAS, WRITTEN ONCE. Seven of them
  /// spelled out the same guard — an SE row, an index inside its clip list
  /// — and the same write, and one of them checked the no-op inside the
  /// guard while its neighbours checked it after. [change] returns the new
  /// clip list, or null for "nothing moved".
  void _editAudioClips(
    LayerId layerId,
    int clipIndex,
    String description,
    List<AudioClip>? Function(List<AudioClip> clips) change,
  ) {
    final layer = _project.layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final next = change(layer.audioClips);
    // ⚠️MUTANT SURVIVES HERE — an inner guard already answers (2026-09-07).
    // Deleting any edit's `== value ? null :` still spends no undo step,
    // because `updateLayerAudioClips` returns early on `listEquals`. What
    // these guards still buy is the `notifyChanged()` below, which the
    // coordinator's guard cannot suppress; a test that watches undo steps
    // can never see the difference.
    if (next == null) {
      return;
    }
    _project.cutCommandCoordinator.updateLayerAudioClips(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: description,
    );
    _changes.notifyChanged();
  }

  /// [_editAudioClips] for the edits that replace ONE clip.
  void _editAudioClip(
    LayerId layerId,
    int clipIndex,
    String description,
    AudioClip? Function(AudioClip clip) change,
  ) => _editAudioClips(layerId, clipIndex, description, (clips) {
    final changed = change(clips[clipIndex]);
    return changed == null ? null : ([...clips]..[clipIndex] = changed);
  });

  /// Removes the [clipIndex]th clip of [layerId]; one undo step.
  void removeAudioClipAt(LayerId layerId, int clipIndex) => _editAudioClips(
    layerId,
    clipIndex,
    'Remove audio',
    (clips) => [...clips]..removeAt(clipIndex),
  );

  /// Sets the [clipIndex]th clip's offset trim (frames skipped into the
  /// file where its block starts) — the block edit window's slide; one undo
  /// step, clamped non-negative, no-op when unchanged.
  void setAudioClipOffset(LayerId layerId, int clipIndex, int offsetFrames) {
    final clamped = offsetFrames < 0 ? 0 : offsetFrames;
    _editAudioClip(
      layerId,
      clipIndex,
      'Slide sound',
      (clip) => clip.offsetFrames == clamped
          ? null
          : clip.copyWith(offsetFrames: clamped),
    );
  }

  /// Sets the [clipIndex]th clip's gain (the block edit window's, I-140);
  /// one undo step, clamped non-negative, no-op when unchanged.
  void setAudioClipGain(LayerId layerId, int clipIndex, double gain) {
    final clamped = gain < 0 ? 0.0 : gain;
    _editAudioClip(
      layerId,
      clipIndex,
      'Sound gain',
      (clip) => clip.gain == clamped ? null : clip.copyWith(gain: clamped),
    );
  }

  /// The sounds the SELECTED SE instance carries, each with the index it
  /// sits at in its layer's clip list (R5 #19 — the instance editor shows
  /// what a block is linked to, and lets you take it off).
  ///
  /// The index travels with the clip because [removeAudioClipAt] addresses
  /// by position: a clip has no id of its own, and looking it up again
  /// afterwards would search a list that just changed.
  List<({AudioClip clip, int index})> get selectedSeAudioClips {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null || frame == null) {
      return const [];
    }
    return [
      for (var index = 0; index < layer.audioClips.length; index += 1)
        if (layer.audioClips[index].frameId == frame.id)
          (clip: layer.audioClips[index], index: index),
    ];
  }

  /// Takes the sounds at [clipIndexes] off the ACTIVE layer in one step —
  /// the instance editor's unlink, which can drop several at once and must
  /// be one undo with them.
  ///
  /// Descending removal: every index is into the list as it stands NOW, and
  /// removing a low one would shift the rest.
  void unlinkAudioClipsFromActiveLayer(Iterable<int> clipIndexes) {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return;
    }
    unlinkAudioClipsFromLayer(layer.id, clipIndexes);
  }

  /// The same unlink addressed by ROW (B6 2026-08-17): the storyboard's SE
  /// instance editor takes sounds off a TRACK fixture whose row is never
  /// the drawing target. One removal body with the active form above.
  void unlinkAudioClipsFromLayer(LayerId layerId, Iterable<int> clipIndexes) {
    final layer = requireLayerAnywhere(
      _project.repository.requireProject(),
      layerId,
    );
    final ordered = clipIndexes.toList()..sort((a, b) => b.compareTo(a));
    final next = [...layer.audioClips];
    for (final index in ordered) {
      if (index >= 0 && index < next.length) {
        next.removeAt(index);
      }
    }
    if (next.length == layer.audioClips.length) {
      return;
    }
    _project.cutCommandCoordinator.updateLayerAudioClips(
      cutId: _project.activeCutOrNull?.id,
      layerId: layerId,
      audioClips: next,
      description: 'Unlink audio',
    );
    _changes.notifyChanged();
  }
}
