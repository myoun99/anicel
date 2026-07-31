import '../../models/layer_kind.dart';

/// Entrance unification: EVERY layer kind opens the shared instance-edit
/// dialog on cell double-tap — animation/storyboard/image edit the frame
/// name, SE its name/dialogue, instruction its event, camera its keys.
/// Kept as a function (not a constant) so the gate stays declarative at
/// the call sites and future kinds opt in/out in one place.
///
/// Trade-off (accepted for consistency): a non-null onDoubleTap delays
/// single-tap selection by the double-tap window on every cell, as SE and
/// instruction rows already did.
///
/// EXCEPT the rows that own no cel of their own (R10): a folder row shows
/// its subtree's union and an adjustment row shows its effects — there is
/// nothing there to edit, which is the user's "폴더 행 편집 조작 = 무시"
/// said at the entrance instead of left to the host to no-op. It also
/// buys those rows their single tap back, since no double-tap is armed.
bool layerKindOpensCellEditorOnDoubleTap(LayerKind kind) =>
    !layerKindGroupsLayers(kind) && kind != LayerKind.adjustment;
