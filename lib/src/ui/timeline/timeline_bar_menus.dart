import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_input_settings.dart' show AppInput;
import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/pixel_clipboard_verb.dart';
import '../../services/cel_pixel_overwrite.dart' show CelPixelVerb;
import '../cut_command_group.dart';
import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../widgets/panel_flyout.dart';
import 'layer_label_controls.dart' show layerKindDisplayName, layerKindIcon;
import 'rasterize_reference_rows.dart';
import 'toolbar_panel_context.dart';

/// The frame pill's standing switch, pressed — 「빈 칸에 그리면 프레임 자동
/// 생성」 on or off, through the setting's own door, which writes it down
/// (F-191). The button's press and its key's (I-40): one sentence, so the
/// two cannot come to flip different things.
void toggleAutoCreateFrameOnDraw(EditorSessionManager session) {
  final input = AppInput.settings.value;
  session.setInputSettings(
    input.copyWith(autoCreateFrameOnDraw: !input.autoCreateFrameOnDraw),
  );
}

/// The timeline bar's menus as they open, for ONE panel: the layer pill's
/// two, the frame pill's, the shared pill's colour edit list and the
/// effects' here, and with the cut pill's ([cutMenuEntries],
/// [cutAddEntries]) every row of the bar ([rows]).
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
/// 버튼같은거나 … 뭐든 모든 버튼」. ★A KEY AND ITS MENU ROW ARE ONE PRESS
/// ([pressFlyoutRow]): the pills show these lists and the shell presses a
/// row of them by its action, on the panel being worked in — the same
/// builder for both, so a key cannot act where its row is dim, and a row
/// given its action's name is reachable by key with nothing more written.
///
/// ↩️The builders were private methods of the toolbar widget, which only a
/// mounted bar could ask; they are the same lines, moved. The colour edit
/// list's rows were actions before any of the others (2026-09-13) and the
/// shell ran their verbs on a road of its own; they are pressed as rows now
/// like the rest — the third list on the one rule.
class TimelineBarMenus {
  const TimelineBarMenus({required this.session, required this.panel});

  final EditorSessionManager session;

  /// B8 — WHICH PANEL is asking: every row's gate and verb is that panel's.
  final ToolbarPanelContext panel;

  /// Every row of the bar's menus as they would open right now
  /// ([flyoutRowsOf]) — the cut pill's two, then the layer pill's two, the
  /// frame pill's, the shared pill's colour edit list and the effects'.
  /// [context] is where a row's window opens.
  List<PanelFlyoutItem> rows(BuildContext context) => flyoutRowsOf([
    ...cutMenuEntries(context, session),
    ...cutAddEntries(session),
    ...layer(context),
    ...addLayer(),
    ...frame(),
    ...colourEdit(),
    ...effects(),
  ]).toList();

  /// The key suffix each kind's Add entry has always used — spelled out
  /// rather than derived from `kind.name`, so a rename of the enum cannot
  /// silently move a widget key the tests aim at.
  static String _addLayerKeySuffix(LayerKind kind) => switch (kind) {
    LayerKind.animation => 'animation',
    LayerKind.storyboard => 'storyboard',
    LayerKind.image => 'image',
    LayerKind.se => 'se',
    LayerKind.instruction => 'instruction',
    LayerKind.adjustment => 'adjustment',
    LayerKind.folder => 'folder',
    LayerKind.camera => 'camera',
    LayerKind.transition => 'transition',
  };

  /// The band over the layer pill's ＋ — every kind it can add.
  List<PanelFlyoutEntry> addLayer() {
    return [
      PanelFlyoutHeader(editorActionLabel(EditorActionIds.layerAdd)),
      // Which kinds, and why no 「현재 선택한 레이어와 같은 종류」 entry: at
      // the list ([addLayerKinds]) — its rows and their actions are both
      // made from it.
      //
      // ★EVERY entry wears its kind's own icon, and they come from
      // [layerKindIcon] rather than being chosen here (유저: 「레이어 생성,
      // 아이콘이 있고없고 그러는데, 다 아이콘 앞에 붙임」). Three of these
      // used to carry a hand-picked glyph and the rest carried none — which
      // is how the list came to disagree with the rail it creates rows for.
      // One table, so the menu and the row can never show different pictures
      // of the same noun.
      for (final kind in addLayerKinds)
        PanelFlyoutItem(
          keyValue: 'add-layer-kind-${_addLayerKeySuffix(kind)}',
          // The kind's ONE name ([layerKindDisplayName]) — the rail's and
          // the kind flyout's. ↩️This menu kept a switch of its own over the
          // same table, which answered the same until a kind was added.
          // The row's ACTION is named over it: 「레이어 추가: 애니메이션」.
          label: layerKindDisplayName(kind),
          shortcuts: [addLayerKindActionId(kind)],
          icon: layerKindIcon(kind),
          // R9 #7: one storyboard row per cut — the entry greys out once the
          // cut has it, instead of accepting the tap and doing nothing.
          // B8: and the PANEL answers first — on the storyboard only the S
          // row is this rail's to add, so the cut-scoped kinds grey out.
          enabled: panel.canAddLayerOfKind(kind),
          onSelected: () => panel.addLayerOfKind(kind),
        ),
      // Attach layers (W5, UI-R20 #8 / UI-R21 #3): the same entrance the
      // Layer menu has — own cels riding the base's FX. FREE authors its
      // own timeline; SYNCED mirrors the base's exposures (ghost rows).
      const PanelFlyoutDivider(),
      // ① (유저 확정): the SAME glyph the rail draws on an attached row
      // ([LayerAttachArrowCell]), flipped the same way for the above
      // placement. These used to be `north_east`/`south_east` — a second
      // vocabulary for attachment, so the menu that MAKES the row and the
      // row it makes did not look like the same idea.
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-above',
        label: editorActionLabel(EditorActionIds.layerAttachFreeAbove),
        shortcuts: const [EditorActionIds.layerAttachFreeAbove],
        icon: Icons.subdirectory_arrow_right,
        iconFlipY: true,
        enabled: panel.canAddAttachedLayer,
        onSelected: () => panel.addAttachedLayer(
          AttachedPlacement.above,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-below',
        label: editorActionLabel(EditorActionIds.layerAttachFreeBelow),
        shortcuts: const [EditorActionIds.layerAttachFreeBelow],
        icon: Icons.subdirectory_arrow_right,
        enabled: panel.canAddAttachedLayer,
        onSelected: () => panel.addAttachedLayer(
          AttachedPlacement.below,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-above',
        label: editorActionLabel(EditorActionIds.layerAttachSyncedAbove),
        shortcuts: const [EditorActionIds.layerAttachSyncedAbove],
        icon: Icons.subdirectory_arrow_right,
        iconFlipY: true,
        enabled: panel.canAddAttachedLayer,
        onSelected: () =>
            panel.addAttachedLayer(AttachedPlacement.above),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-below',
        label: editorActionLabel(EditorActionIds.layerAttachSyncedBelow),
        shortcuts: const [EditorActionIds.layerAttachSyncedBelow],
        icon: Icons.subdirectory_arrow_right,
        enabled: panel.canAddAttachedLayer,
        onSelected: () =>
            panel.addAttachedLayer(AttachedPlacement.below),
      ),
    ];
  }

  /// The EFFECTS button's list (R5 #6): add one of each kind, and take away
  /// the ones this row already carries.
  ///
  /// Adding one changes nothing until a value moves — the work happens in
  /// the row's FX lanes, which is why this is a menu and not a control on
  /// an already crowded row.
  List<PanelFlyoutEntry> effects() {
    // B8: the chain shown and edited here is the CUT's active layer's — the
    // timeline panel's noun. On the storyboard every entry greys out
    // honestly (its rows' chains have no add entrance on this pill yet, and
    // a lit entry would edit a row that panel is not showing).
    final serves = panel.servesActiveLayerVerbs;
    // ⛔NO REMOVE ENTRIES (F-87, 유저 2026-09-12: 「fx 헤더 선택범위로 선택한채로
    // 삭제누르면 해당 fx 삭제. 그리고 fx버튼에 있는 해당 fx 삭제버튼은
    // 필요없으니 삭제하고 관련로직 싹 제거」): an effect is removed by a range
    // over its header and the one Delete.
    return [
      PanelFlyoutHeader(AppText.strings.tlEffects),
      // ⛔EVERY KIND IS LISTED, ALWAYS; the ones this row cannot take are
      // DIMMED. Same rule the two pixel verbs on the shared pill follow
      // ("Dimmed with nothing to act on, never hidden") — a menu that grew
      // and shrank under the pointer would make the artist look for an
      // entry that is simply not there today.
      for (final kind in EffectKind.values)
        PanelFlyoutItem(
          keyValue: 'add-effect-${kind.jsonValue}',
          label: editorActionLabel(addEffectActionId(kind)),
          shortcuts: [addEffectActionId(kind)],
          icon: Icons.auto_fix_high_outlined,
          enabled: serves && session.effectsAndFx.canAddEffectToActiveLayer,
          onSelected: () => session.effectsAndFx.addEffectToActiveLayer(kind),
        ),
    ];
  }

  /// A track's fixture row takes no row verb from here
  /// ([LayerKind.isTrackFixture]) — selecting the transition row must not
  /// light up duplicate.
  ///
  /// A getter because ① moved rename OUT of the menu: the pill's button and
  /// the entries that stayed behind have to answer the same question, and
  /// two copies of this line would eventually stop agreeing.
  bool get canEditActiveLayer {
    final active = session.activeLayer;
    return active != null && !active.kind.isTrackFixture;
  }

  /// The layer pill's menu. [context] is where a row's window opens
  /// from — the pill's, or the shell's when a key presses the row.
  List<PanelFlyoutEntry> layer(BuildContext context) {
    final active = session.activeLayer;
    // B8: every verb below acts on the CUT's active layer — the timeline
    // panel's noun — so the storyboard's menu greys them all out honestly
    // instead of editing a row that panel is not showing.
    final serves = panel.servesActiveLayerVerbs;
    final editable = serves && canEditActiveLayer;
    return [
      // ⛔RENAME IS NOT HERE — ① moved it onto the pill itself (유저 확정:
      // 「레이어 알약 밖으로: 레이어 이름변경」). "밖으로" means out of the
      // MENU and onto that pill, which is where 컷 삭제 went for the same
      // sentence; it does not mean the shared pill, whose residents 확정 #11
      // fixes at four.
      PanelFlyoutItem(
        keyValue: 'duplicate-layer-button',
        label: editorActionLabel(EditorActionIds.layerDuplicate),
        shortcuts: const [EditorActionIds.layerDuplicate],
        icon: Icons.copy_outlined,
        enabled: editable,
        onSelected: session.layerVerbs.duplicateActiveLayer,
      ),
      // ⛔COPY AND PASTE ARE NOT HERE, AND NEITHER IS 「링크해서 복제」
      // (I-77, 유저 2026-10-06: 「복사/붙여넣기버튼 레이어도 연결 … 그러고
      // 레이어버튼의 레이어복사/붙여넣기는 필요없으니 삭제」 · 「링크해서
      // 복제도 필요없어지니 삭제」). The shared pill's copy takes the selected
      // rows and its two pastes put them down — independent, or linked.
      // R5 #5: the row-order STEP verbs are gone, session methods and all
      // (user: "단축키로도 남기지마 일단"). The drag is the whole answer
      // now; the one thing the step could reach that a drop cannot — the
      // inside of an EMPTY folder — is the drop mode this round adds
      // instead, where dropping ON a folder row puts the layer in it.
      // 분리 (P3). MAKING an attach is the drag's alone: dropping a row
      // strictly inside a group mounts it, and R5 #15 gave the one case a gap
      // cannot reach — the first rider on a base — its own door, dropping ON
      // the row. The two "위/아래 레이어에 장착" entries that used to stand
      // here were that door before it existed, so R5 deleted them rather than
      // keep a second way to say the same thing.
      //
      // The RELEASE stays: it must not be a one-way door (user 2026-08-07).
      PanelFlyoutItem(
        keyValue: 'timeline-detach-layer-button',
        label: editorActionLabel(EditorActionIds.layerDetach),
        shortcuts: const [EditorActionIds.layerDetach],
        icon: Icons.link_off,
        enabled: serves && session.folders.canDetachActiveLayer,
        onSelected: session.folders.detachActiveLayer,
      ),
      // R5 #5: IMPORT AUDIO left. The media pool is the one entrance —
      // it links an audio asset onto a frame block, which is the shape the
      // work actually has; this entry offered a second, thinner door.
      const PanelFlyoutDivider(),
      // R5 #6: the EFFECT chain moved out to a button of its own — the
      // effect list is going to be what that button shows, so it stopped
      // being a tail on the layer menu.
      //
      // R5 #14: and the two FOLDER-making commands went with it. "Group
      // into folder" wrapped the active layer; a folder is made EMPTY from
      // the Add Layer menu now and filled by dropping rows on it, which is
      // how every other app this user works in behaves. "New attach folder"
      // goes for the same reason — the drag makes those too.
      PanelFlyoutItem(
        keyValue: 'timeline-rasterize-layer-button',
        label: editorActionLabel(EditorActionIds.layerRasterize),
        shortcuts: const [EditorActionIds.layerRasterize],
        icon: Icons.texture_outlined,
        enabled: serves && session.editingCanvas.canRasterizeActiveLayer,
        // A movie reference is decoded frame by frame behind the wait
        // window ([rasterizeActiveRow]); every other row is the session's
        // own verb, unchanged.
        onSelected: () => unawaited(rasterizeActiveRow(context, session)),
      ),
      // 'SE name tag…' opened a window. R5 #7 put every control it held on
      // the SE row's Name Tag lane group, so the entry would only lead
      // somewhere that changes the same thing a second way.
      // ↩️「링크 해제」 stood here. 🗣️I-25 (유저 2026-09-14): 「레이어 버튼의
      // 링크해제는 필요없어졌으니 삭제」 — the link badge on the row opens the
      // link window, and its button unlinks.
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'toggle-storyboard-layer-button',
        label: editorActionLabel(EditorActionIds.layerStoryboard),
        shortcuts: const [EditorActionIds.layerStoryboard],
        icon: Icons.auto_stories_outlined,
        enabled: serves && session.layerSwitches.canToggleTargetLayerKind,
        checked: active?.kind == LayerKind.storyboard,
        onSelected: session.layerSwitches.toggleTargetLayerKind,
      ),
      // R5 #5: the SE and CAMERA section switches left. The legend's own
      // sections cell has shown and hidden both since UI-R7, so this pair
      // was a second door to one setting — and the one further from where
      // the rows are.
      // ⛔The layer DELETE left this menu (유저 2026-08-12: 「밖에 딜리트
      // 레이어있으니 버튼내부에있는 딜리트레이어 삭제」) — and then left the
      // bar entirely, because delete is ONE verb now that asks what is
      // selected. See the shared pill and [EditorSessionManager.deleteSubject].
    ];
  }

  /// The frame pill's menu.
  List<PanelFlyoutEntry> frame() {
    return [
      // ⛔EDIT INSTANCE IS NOT HERE — ① moved it onto the frame pill (유저
      // 확정: 「프레임 알약 밖으로: 딜리트 · Edit Instance」). The delete half
      // of that sentence went further, to the shared pill, but ⑰ sent it
      // there — 「밖으로」 on its own means out of the menu.
      // ⛔COPY AND THE PASTES ARE NOT HERE — ㉕ put them on the SHARED pill
      // (확정 #11), beside the one delete. They belong to no noun: what they
      // act on is whatever is selected, which is exactly the sentence that
      // pill exists to say.
      // ⛔DELETE IS NOT HERE EITHER (T24, 유저 2026-08-13: 「프레임알약
      // 삭제버튼 … 일단 삭제. 공통버튼에 존재하니까」). It was the last
      // duplicate: the shared pill's one delete falls through to this exact
      // verb when nothing else is selected, so the menu item reached
      // `deleteCellAtCurrentFrame` by a second road under a second gate.
      //
      // ⚠️The ladder is the difference, and it is the confirmed law rather
      // than a loss: with rows selected the one delete deletes ROWS
      // (확정 D2, 컷 > 레이어 > 셀), so deleting just the cell now means
      // clearing the row selection first. That is what "하나의 딜리트"
      // means — the button asks what is selected instead of the reach
      // deciding for it.
      //
      // ⛔THE FRAME'S DUPLICATE PAIR IS GONE (유저 2026-09-01, F-62):
      // 「프레임 버튼 안에 있는 **복제/링크복제 버튼삭제. 쓸일없음.**
      // 잔재도제거」.
      //
      // ⚠️This REVERSES 유저 확정 2026-08-13 (「복제는 현재 액티브인 대상을
      // 상대로 적용하는 것 … 각각 독립복제 / 링크복제」, per noun) and T24's
      // 「남기고 나중에 기능추가할거야」 — kept here rather than deleted
      // silently, because the next reader would otherwise find the old
      // decision and put the pair back.
      //
      // ⚠️`duplicateActiveBlock` STAYS. It is not the button's leftover: the
      // splice tests drive it directly, and F-62's other half (「프레임
      // 복사후 독립붙여넣기시 그림이 복제되지 않는다」) is about the same
      // machinery. A verb with no button is not dead code here — it is the
      // verb the paste path needs.
      // D40: the whole-row select. ⛔NOT gated on servesActiveLayerVerbs —
      // the storyboard half is the point (컷블록도 동일 작동): each panel
      // context resolves its OWN standing row, cut row included.
      PanelFlyoutItem(
        keyValue: 'select-row-span-button',
        label: editorActionLabel(EditorActionIds.frameSelectRowSpan),
        shortcuts: const [EditorActionIds.frameSelectRowSpan],
        icon: Icons.select_all,
        enabled: panel.canSelectRowSpan,
        onSelected: panel.selectRowSpan,
      ),
    ];
  }

  /// The 색 편집 popover's four verbs, in the order the artist reaches for
  /// them: the two that keep the drawing, then the two that take it away.
  ///
  /// ⛔NO TOLERANCE KNOB HERE. 유저 2026-08-27 (I-8-Q2): 「허용차 같은
  /// 고급설정은 fx의 색 제거 이펙트에서 하라하고 여기서는 간편하게만
  /// 하고싶음」 — the buttons match the colour exactly, and the graded
  /// version is the Delete Color / Keep Color EFFECT.
  ///
  /// ↩️The four were live whenever the head was — one gate for all of them.
  /// I-55 put a second kind of verb in the list, so the head opens when any
  /// row can run (`canOpenColourEdit`) and each row dims on its own gate:
  /// the four on theirs, the clipboard rows on theirs.
  ///
  /// 🗣️I-55 (유저 2026-10-01): 「색편집버튼에 새 기능으로서 … 픽셀복사/픽셀
  /// 아래 붙여넣기/픽셀 위 붙여넣기」 — after the four, as their own group.
  List<PanelFlyoutEntry> colourEdit() => [
    PanelFlyoutHeader(AppText.strings.tlSharedColourEdit),
    for (final verb in CelPixelVerb.values)
      PanelFlyoutItem(
        keyValue: switch (verb) {
          // The retired buttons' own key strings, kept.
          CelPixelVerb.replaceColour => 'shared-replace-colour-button',
          CelPixelVerb.clearPixels => 'shared-clear-pixels-button',
          CelPixelVerb.deleteColour => 'shared-delete-colour-button',
          CelPixelVerb.keepColour => 'shared-keep-colour-button',
        },
        // 🗣️유저 2026-09-13: 「색변환의 픽셀비우기를 백스페이스로 하란건, 그
        // 외 같이있는 버튼들도 다 숏컷 지정가능하게 등록하란거는 앞으로의
        // 규칙이야」 — every verb here is an action, so every row wears its
        // action's name and prints its key.
        label: editorActionLabel(pixelVerbActionIdFor(verb)),
        icon: switch (verb) {
          CelPixelVerb.replaceColour => Icons.format_color_fill,
          CelPixelVerb.clearPixels => Icons.cleaning_services_outlined,
          CelPixelVerb.deleteColour => Icons.format_color_reset,
          CelPixelVerb.keepColour => Icons.colorize_outlined,
        },
        shortcuts: [pixelVerbActionIdFor(verb)],
        enabled: session.pixelVerbs.canRunPixelVerb,
        onSelected: () => session.pixelVerbs.runPixelVerb(verb),
      ),
    const PanelFlyoutDivider(),
    for (final verb in PixelClipboardVerb.values)
      PanelFlyoutItem(
        keyValue: switch (verb) {
          PixelClipboardVerb.copy => 'shared-copy-pixels-button',
          PixelClipboardVerb.pasteAbove => 'shared-paste-pixels-above-button',
          PixelClipboardVerb.pasteBelow => 'shared-paste-pixels-below-button',
        },
        label: editorActionLabel(pixelClipboardActionIdFor(verb)),
        icon: switch (verb) {
          PixelClipboardVerb.copy => Icons.content_copy,
          PixelClipboardVerb.pasteAbove => Icons.flip_to_front,
          PixelClipboardVerb.pasteBelow => Icons.flip_to_back,
        },
        shortcuts: [pixelClipboardActionIdFor(verb)],
        enabled: session.pixelVerbs.canRunPixelClipboardVerb(verb),
        onSelected: () => session.pixelVerbs.runPixelClipboardVerb(verb),
      ),
  ];
}
