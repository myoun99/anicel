part of '../timeline_controller.dart';

/// COPY AND PASTE — a run copied off a layer, and a frame pasted back
/// linked or independent — as their own object.
///
/// 🚨A collaborator carved out of `TimelineController` (the audit's SRP
/// cut, 2026-09-02). It reaches the controller through `_controller`.
class _TimelinePaste {
  _TimelinePaste(this._controller);

  final TimelineController _controller;

  bool canPasteLinkedFrameAt({
    required Layer layer,
    required int frameIndex,
    required FrameId copiedFrameId,
  }) {
    if (frameIndex < 0) {
      return false;
    }
    return _controller._frameOrNull(layer: layer, frameId: copiedFrameId) !=
        null;
  }

  void pasteLinkedFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
  }) {
    final before = _controller._requireLayer(layerId);
    if (!canPasteLinkedFrameAt(
      layer: before,
      frameIndex: _controller._editFrameIndexFor(layerId),
      copiedFrameId: frameId,
    )) {
      return;
    }
    _pasteFrameForLayer(layerId: layerId, frameId: frameId);
  }

  /// ㉕ 독립 붙여넣기: the copied cel's CONTENT here, as a cel of its OWN.
  ///
  /// The only difference from the linked paste is which cel the exposure
  /// ends up pointing at — a new one rather than the copied one — so the
  /// placement rules (relink on a block start, split inside a hold, fill an
  /// empty cell up to the next block) are shared rather than restated.
  /// Drawing on the result must not reach the frame it came from; that is
  /// the whole of what "독립" means here.
  void pasteIndependentFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    required FrameId newFrameId,
  }) {
    final before = _controller._requireLayer(layerId);
    if (!canPasteLinkedFrameAt(
      layer: before,
      frameIndex: _controller._editFrameIndexFor(layerId),
      copiedFrameId: frameId,
    )) {
      return;
    }
    final source = _controller._frameOrNull(layer: before, frameId: frameId);
    if (source == null) {
      return;
    }
    _pasteFrameForLayer(
      layerId: layerId,
      frameId: newFrameId,
      // 🚨IT COMES OUT UNNAMED, and that is the point rather than an
      // omission. A cel's name is its IDENTITY inside the layer — the
      // rename path REFUSES a duplicate and offers to merge instead, which
      // is this app's 「같은 이름 = 같은 그림」 rule. Carrying the source's
      // name would assert the very link this verb exists to avoid, and do
      // it behind that dialog's back: two cels claiming one name, a state
      // no rename could ever produce.
      //
      // Unnamed cels coexist freely, so "not named yet" is a legal answer
      // and the animator gives it one when they mean to. `seName` DOES
      // travel — a speaker label is a property, not a name that links.
      bornFrame: duplicateFrameContent(
        frame: source,
        newFrameId: newFrameId,
      ).copyWith(name: null),
    );
  }

  /// Puts [frameId]'s exposure at the edit index. [bornFrame] is the
  /// independent paste's new cel, which joins the layer before anything
  /// points at it; null is the linked paste, where reuse IS the point.
  ///
  /// 🚨T3 — this is [_controller.spliceRunsForLayers] with a one-cell clip and no lift.
  /// It used to hold the three placement rules of its own (relink on a block
  /// start, split inside a hold, fill an empty cell up to the next block),
  /// and ⛔those are RETIRED: 「내가 하고싶은건 프레임만 복붙이 아니라 코마까지
  /// 포함해서 블록 자체를 복붙한다는 느낌」. The clip brings its length and
  /// the tail moves aside. Kept as a named entry point because the one-cel
  /// paste is still a real verb, not because the old rules survive anywhere.
  void _pasteFrameForLayer({
    required LayerId layerId,
    required FrameId frameId,
    Frame? bornFrame,
  }) {
    _controller.spliceRunsForLayers(
      runs: [
        (
          layerId: layerId,
          index: _controller._editFrameIndexFor(layerId),
          liftCount: 0,
          clip: TimelineClipRow(
            exposures: {0: TimelineExposure.drawing(frameId, length: 1)},
            length: 1,
          ),
          bornFrames: bornFrame == null ? const <Frame>[] : [bornFrame],
        ),
      ],
      description: 'Paste frame',
    );
  }

  /// Reads [count] cells off [layerId] without changing the row.
  ///
  /// Indexes are the EDIT axis, the same one the paste and the playhead use,
  /// so a track-owned SE row reads at its shifted position rather than the
  /// cut-local one.
  TimelineClipRow copyRunForLayer({
    required LayerId layerId,
    required int index,
    required int count,
  }) {
    return captureTimelineRun(
      timeline: _controller._requireLayer(layerId).timeline,
      index: index,
      count: count,
    );
  }
}
