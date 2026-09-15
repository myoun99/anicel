import '../widgets/app_icon_button.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart' show FolderGrant;
import '../dialogs/app_confirm_dialog.dart'
    show
        ConfirmChoice,
        ConfirmQuestion,
        askConfirm,
        confirmDialogKeys,
        showAppNotice;
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/folder_pick_flow.dart';

import '../text/app_strings.dart';
import '../text/byte_size_label.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_window.dart' show AppWindowActionEmphasis;
import '../widgets/panel_flyout.dart';
import 'media_asset_drag_chip.dart';
import 'media_asset_drag_data.dart';
import 'media_asset_kind_icon.dart';
import 'media_asset_pool_state.dart';
import 'media_drop_verdict.dart';
import '../input/control_press_claim.dart';

/// The dockable MEDIA POOL: every file the project knows, importable
/// ahead of use, draggable onto SE blocks to link (footsteps reuse),
/// renamable, and relinkable when the file moved (missing files get a
/// badge instead of silently breaking).
///
/// 🚨★★★**IT WAS CALLED A BROWSER, AND THAT MEANT THE OPPOSITE THING.**
/// 유저 확정 2026-08-30: 「그럼 미디어풀패널로 가자」.
///
/// A browser is where you go looking through the DISK for something not
/// yet imported — that is exactly what Premiere's Media Browser is, and
/// it is the panel beside this one, not this one. This holds what the
/// project ALREADY has, and does things to it: import, rename, relink,
/// remove, promote to carried, place on the timeline. Premiere calls that
/// the Project panel and Resolve calls it the Media Pool; this file's own
/// doc had said「the Resolve Media Pool counterpart」while the class said
/// browser, and the session API has always called it the pool.
///
/// Pure widget: the workspace wires it to the session's pool API; pickers
/// and the file-existence probe are injectable for tests.
class MediaPoolPanel extends StatelessWidget {
  const MediaPoolPanel({
    super.key,
    required this.assets,
    required this.usesOf,
    required this.onImportRequested,
    required this.onRenameAsset,
    required this.onRelinkAsset,
    required this.onRemoveAsset,
    required this.onPromoteAsset,
    required this.onExportAssetWav,
    this.onOpenAsset,
    this.onOpenAssetInSubViewer,
    this.onPlaceAsset,
    this.audioFilePicker,
    this.missingPaths = const <String>{},
    this.modifiedTimes = const <String, DateTime>{},
    this.storedBytes = const <String, int>{},
    this.conformBytes = const <String, int>{},
    this.onRelinkMissing,
  });

  final List<MediaAsset> assets;

  /// Where the project uses each asset, one line per use — empty when
  /// nothing does (F-118). The row's in-use mark is this list not being
  /// empty, the window the mark opens shows it, and a remove asks about it:
  /// ONE answer, so the three cannot disagree.
  final Iterable<String> Function(String path) usesOf;

  /// Opens the import window on the media pool.
  ///
  /// The ＋ used to open an OS picker and copy whatever came back — no
  /// window, no choice, and a 3GB movie duplicated before anyone could
  /// say otherwise. It now goes where every other import already went.
  final VoidCallback onImportRequested;
  final void Function(String path, String name) onRenameAsset;

  /// The grants come along because relinking is a PICK: the token minted
  /// for the file the user just chose is the only thing that makes the new
  /// path outlive the session on Apple, and this is the flow a broken
  /// reference lands in.
  final void Function(String oldPath, String newPath, List<FolderGrant> grants)
  onRelinkAsset;

  /// Removes the asset and every use of it with it — the panel has asked
  /// first when [usesOf] names any.
  final void Function(String path) onRemoveAsset;

  /// Marks a referenced file as one the project carries, so the next save
  /// writes its bytes inside the `.anicel`. Nothing on disk moves. False
  /// when there was nothing to promote.
  final Future<bool> Function(String path) onPromoteAsset;

  /// Writes the asset's conformed audio out as a plain WAV; false when the
  /// asset has none. The panel only reports the answer — where the file
  /// goes is the flow's law, not this widget's.
  final Future<bool> Function(MediaAsset asset) onExportAssetWav;

  /// Opens the asset in the MAIN viewer (double-click or the row menu);
  /// null hides both entrances.
  ///
  /// 유저 확정 ①: the double-click keeps meaning the main viewer, which
  /// is the one on the floor — so it still swaps the drawing away. That
  /// is the point of the second entry below.
  final void Function(MediaAsset asset)? onOpenAsset;

  /// Opens the asset in the SUB viewer — the row menu only, because it is
  /// the deliberate choice and the double-click is the reflex one.
  final void Function(MediaAsset asset)? onOpenAssetInSubViewer;

  /// Puts this asset on the timeline — the import window in its PLACE
  /// mode, so the answers are the same ones a fresh import gives.
  final void Function(MediaAsset asset)? onPlaceAsset;

  /// Injectable file dialog; defaults to the platform audio picker.
  final Future<String?> Function()? audioFilePicker;

  /// Starts the batch relink: pick a folder, match, preview, apply. Null
  /// hides the banner's button (the banner itself still counts).
  final VoidCallback? onRelinkMissing;

  /// RELINK-2: pool paths the session found missing at its last refresh.
  ///
  /// Replaces the per-row `File.existsSync()` this panel used to call while
  /// BUILDING each row. The loss banner counts the whole pool, so keeping
  /// the probe here would have turned one repaint into one disk hit per
  /// asset — and a panel is repainted for reasons that have nothing to do
  /// with the file system.
  ///
  /// Counted against [assets] rather than trusted wholesale: an entry the
  /// user removed can linger here until the next refresh, and a banner that
  /// counts ghosts is worse than one that is a beat late.
  final Set<String> missingPaths;

  /// When each pool file was last written — the session's sweep fills it,
  /// so a row never stats the disk to draw itself.
  final Map<String, DateTime> modifiedTimes;

  /// What each carried asset ACTUALLY occupies — compressed, in the
  /// project file or in staging. Empty for assets the project only
  /// references, whose own file length is the honest answer.
  final Map<String, int> storedBytes;

  /// Pool path → what its CONFORM occupies, for the assets that have one.
  /// Empty for every non-audio asset, and for audio nobody has played yet.
  final Map<String, int> conformBytes;

  /// PICK-5: through the grant flow rather than `file_selector`, which
  /// copies the chosen file into a temporary directory on both mobile
  /// platforms — relinking to a copy that the next cache sweep deletes is
  /// worse than not relinking at all.
  Future<void> _relink(BuildContext context, String path) async {
    // 🚨 Relink is the answer this app gives when a reference stops
    // resolving, so it is exactly where a durable grant matters most —
    // and it used to throw the picker's bookmark away, which made the
    // relink work for one session and be refused at the next launch. The
    // injected picker (tests) still answers in paths and mints nothing.
    final injected = audioFilePicker;
    if (injected != null) {
      final next = await injected();
      if (next != null) {
        onRelinkAsset(path, next, const []);
      }
      return;
    }
    final grants = await pickFileGrantsForUser(
      context,
      supportedExtensions: FileTypeGroups.poolMedia.extensions ?? const [],
    );
    final next = grants.isEmpty ? null : grants.first.path;
    if (next == null) {
      return;
    }
    onRelinkAsset(path, next, grants);
  }

  /// `55 MB + 1.2 GB · 08-12 19:41` — as much of it as is known.
  ///
  /// 🪦The example used to read `2.1 MB`, which [byteSizeLabel] never
  /// produces: megabytes are whole there and only gigabytes carry a
  /// decimal.
  ///
  /// 🚨★★★**THE SIZE SHOWN IS THE SIZE TAKEN** (유저 2026-08-30: 「파일이
  /// 보여주는 크기는 압축된 크기를 보여주는게 맞겟지? … 아무튼 실제크기」).
  /// For a carried asset that is what it occupies compressed — in the
  /// project file, or in the staging area before the first save. The
  /// import dialog still shows the file's own length, and correctly:
  /// nothing has been compressed yet at that point.
  ///
  /// ⛔[MediaAsset.identity] is the FALLBACK, not the answer. It is the
  /// length the file had when it was registered — which for a compressed
  /// asset matches nothing on any disk — and it stays untouched because
  /// relink uses it to tell one `A1.png` from another.
  ///
  /// The date comes from the session's sweep, and neither number makes a
  /// row touch the disk to draw itself.
  String _subtitleFor(MediaAsset asset) {
    final parts = <String>[];
    // 🚨★★★**WHICH ONE IT IS, FIRST.** 유저 2026-08-31: 「해당 파일이
    // 품어진 상태인지 참조인지 모르겠음. **그걸 텍스트로 적어두고**」.
    //
    // Every other fact on this line — the size, the date — reads the same
    // whether the project owns the bytes or merely points at them, and
    // that is the one difference that decides what happens when the
    // original moves. It leads because it is the row's subject, not a
    // detail of it.
    parts.add(mediaAssetPoolState(asset));
    final bytes = storedBytes[asset.path] ?? asset.identity?.lengthBytes;
    // 🚨The CONFORM, asked for by name (유저 2026-08-30: 「가시화정책에 따라
    // 미디어풀 패널에서 해당파일의 컨폼파일 크기 표시할것」). It is several
    // times the sound itself and was invisible per-asset until now.
    //
    // ⛔`+` and nothing else. It says「and this much more」, which is
    // exactly what a conform is, and a word here would be the explanatory
    // caption this app does not put under things.
    //
    // ⚠️ONE part, not two. The parts below are joined with `·`, which
    // separates KINDS of fact — a size from a date. The conform is not
    // another kind of fact; it is more of the same one, and `55 MB · +
    // 660 MB` reads as a list of two sizes rather than as a total.
    final conform = conformBytes[asset.path];
    if (bytes != null && bytes > 0) {
      parts.add(
        conform != null && conform > 0
            ? '${byteSizeLabel(bytes)} + ${byteSizeLabel(conform)}'
            : byteSizeLabel(bytes),
      );
    } else if (conform != null && conform > 0) {
      parts.add('+ ${byteSizeLabel(conform)}');
    }
    final modified = modifiedTimes[asset.path];
    if (modified != null) {
      parts.add(
        '${modified.month.toString().padLeft(2, '0')}-'
        '${modified.day.toString().padLeft(2, '0')} '
        '${modified.hour.toString().padLeft(2, '0')}:'
        '${modified.minute.toString().padLeft(2, '0')}',
      );
    }
    // Nothing known yet (a fresh pool before the first sweep): the path is
    // better than an empty line.
    //
    // ⚠️Counted against ONE, not zero. The carried/linked word above always
    // lands, so「empty」stopped being reachable the moment it was added —
    // and a row that said only「Linked」would have dropped the path a fresh
    // pool has nothing else to show.
    if (parts.length == 1) {
      parts.add(asset.path);
    }
    return parts.join(' · ');
  }

  Future<void> _rename(BuildContext context, MediaAsset asset) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameMediaDialog(
        initialName: asset.name,
        extension: mediaFileNameParts(asset.path).extension,
      ),
    );
    if (name == null || name.isEmpty || name == asset.name) {
      return;
    }
    onRenameAsset(asset.path, name);
  }

  /// 🪦**The「already carried」notice is GONE, not reworded.**
  ///
  /// It said「이미 파일 안에 있거나, **항상 참조로 남는 종류(동영상)**
  /// 입니다」— and that second half had been false since 2026-08-14, when
  /// the per-kind ceiling died and every kind became carryable. 유저
  /// 2026-08-31 met it and reported it as a 낡은 안내창.
  ///
  /// Rewording it would have kept a notice whose only remaining job was to
  /// explain a menu item that should not have been there. The item is now
  /// hidden on a carried row, so the false branch below cannot be reached
  /// by pressing anything — and an answer nobody can ask for is not an
  /// answer worth translating into five languages.
  ///
  /// ⚠️Async because carrying secures the bytes in an isolate and the
  /// answer waits for that.
  Future<void> _promote(BuildContext context, MediaAsset asset) =>
      onPromoteAsset(asset.path);

  /// Hands the asset's conformed audio out as a plain 16-bit WAV.
  ///
  /// The panel asks the session for the conform and the flow for the
  /// destination; neither half lives here. What DOES live here is the
  /// honest answer when there is nothing to export — a row with no audio
  /// still shows the item, so it has to say why rather than do nothing.
  Future<void> _exportWav(BuildContext context, MediaAsset asset) async {
    final done = await onExportAssetWav(asset);
    if (done || !context.mounted) {
      return;
    }
    unawaited(
      showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: AppText.strings.mediaExportWavNoAudio,
      ),
    );
  }

  /// Removes [asset] — asking first when something uses it (F-118, 유저
  /// 2026-09-12: 「풀에서 그냥 제거버튼 누르면 사용중인데 제거하겠습니까?
  /// 배치한 레이어/프레임이 삭제됩니다. 라고 표시해서 강제삭제할수있게」). The
  /// uses ride in the question's fold; a yes removes them with the asset.
  Future<void> _remove(BuildContext context, MediaAsset asset) async {
    final uses = usesOf(asset.path).toList();
    if (uses.isNotEmpty) {
      final strings = AppText.strings;
      final remove = await askConfirm(
        context,
        ConfirmQuestion(
          keys: confirmDialogKeys('media-remove-in-use'),
          title: strings.mpInUseOnTimeline,
          message: strings.mediaRemoveInUse,
          details: uses,
          detailsHeading: strings.mediaUsesHeading,
        ),
        accept: ConfirmChoice(
          strings.mediaRemove,
          emphasis: AppWindowActionEmphasis.danger,
        ),
      );
      if (remove != true) {
        return;
      }
    }
    onRemoveAsset(asset.path);
  }

  /// The in-use mark's window: where [asset] is used, the list open.
  void _showUses(BuildContext context, MediaAsset asset) => unawaited(
    showAppNotice(
      context,
      title: AppText.strings.mpInUseOnTimeline,
      message: asset.name,
      details: usesOf(asset.path).toList(),
      detailsHeading: AppText.strings.mediaUsesHeading,
      detailsOpen: true,
      windowKey: const ValueKey<String>('media-asset-uses-notice'),
    ),
  );

  /// Below this width the asset rows' FIXED parts (status icon, link
  /// badge, actions menu) no longer fit — the panel then scrolls
  /// horizontally at this width instead of overflowing (R10-①).
  static const double _minBodyWidth = 132;

  /// The toolbar row plus its rule — below this the body has no room for
  /// its own fixed parts and would overflow, the same rule
  /// [_minBodyWidth] states for the other axis (R9 #17 hit it: the tool
  /// rail's narrowing reflowed the docks and squeezed this panel).
  static const double _minBodyHeight = 37;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tooNarrow =
            constraints.hasBoundedWidth && constraints.maxWidth < _minBodyWidth;
        final tooShort =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < _minBodyHeight;
        if (!tooNarrow && !tooShort) {
          return _body(context);
        }
        Widget content = SizedBox(
          width: tooNarrow ? _minBodyWidth : null,
          height: tooShort
              ? _minBodyHeight
              : (constraints.hasBoundedHeight ? constraints.maxHeight : null),
          child: _body(context),
        );
        // Each axis takes its own viewport, innermost first: the vertical
        // one is what gives the SizedBox room to be its minimum instead of
        // being squeezed back to the constraint it is escaping.
        if (tooShort) {
          content = SingleChildScrollView(child: content);
        }
        if (tooNarrow) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        }
        return content;
      },
    );
  }

  /// RELINK-2: the loss banner — one line, above the list, INSIDE this
  /// panel. The user chose that over an app-wide strip: 「미디어 풀
  /// 관련된거니까 미디어 풀에」.
  ///
  /// ONE kind, not two. An earlier draft counted "the reference broke" and
  /// "the copy inside the project vanished" separately; the single-file
  /// save format removes the second, because a copy then lives inside the
  /// document and shares its fate.
  ///
  /// Counted against [assets] rather than against [missingPaths] wholesale
  /// — an entry the user just removed can linger in the session's cache
  /// until its next refresh, and a banner that counts ghosts is worse than
  /// one that is a beat late.
  Widget _missingBanner(ColorScheme colorScheme) {
    final count = assets
        .where((asset) => missingPaths.contains(asset.path))
        .length;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final strings = AppText.strings;
    return Container(
      key: const ValueKey<String>('media-missing-banner'),
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 32,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // The count's position differs by language, so the string
              // carries the slot rather than the call site carrying the
              // word order.
              strings.mediaMissingCount.replaceAll('{n}', '$count'),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRelinkMissing != null)
            ControlPressClaim(
              onPressed: onRelinkMissing,
              child: TextButton(
                key: const ValueKey<String>('media-relink-missing'),
                onPressed: silentPress(onRelinkMissing),
                child: Text(strings.mediaFindInFolder),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey<String>('media-browser-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              const SizedBox(width: 4),
              AppIconButton(
                keyValue: 'media-import-button',
                tooltip: AppText.strings.mediaImportAudio,
                // 「＋가 있는 모든 곳, 공통적으로」.
                icon: Icon(Icons.add, color: AppColors.addGlyph(enabled: true)),
                onPressed: onImportRequested,
              ),
              const Spacer(),
            ],
          ),
        ),
        const Divider(height: 1),
        _missingBanner(colorScheme),
        Expanded(
          child: assets.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No media yet.\nImport a sound, or drag one from here '
                      'onto an SE block to reuse it.',
                      key: ValueKey<String>('media-browser-empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: assets.length,
                  itemBuilder: (context, index) =>
                      _assetRow(context, colorScheme, assets[index]),
                ),
        ),
      ],
    );
  }

  Widget _assetRow(
    BuildContext context,
    ColorScheme colorScheme,
    MediaAsset asset,
  ) {
    final exists = !missingPaths.contains(asset.path);
    final uses = usesOf(asset.path);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (exists) Icon(
                  mediaAssetKindIcon(asset.kind),
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ) else Tooltip(
                  message: AppText.strings.mpFileMissing,
                  child: Icon(
                    key: ValueKey<String>('media-asset-missing-${asset.path}'),
                    Icons.error_outline,
                    size: 16,
                    color: colorScheme.error,
                  ),
                ),
          const SizedBox(width: 6),
          Expanded(
            // The double-click zone is the NAME AREA only: a double-tap
            // recognizer over the whole row would hold the menu button's
            // taps in the gesture arena for the double-tap window.
            child: GestureDetector(
              onDoubleTap: onOpenAsset == null
                  ? null
                  : () => onOpenAsset!(asset),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The NAME and its EXTENSION apart, as the import window's
                  // table shows a file (유저 2026-09-12: 「풀에서 이름이랑
                  // 확장자 나누고」): the name is what gets cut short, the
                  // extension never is.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        mediaFileNameParts(asset.path).extension,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  // SIZE and DATE, not the path. The path was here because
                  // it was what the pool knew; what a person scanning a
                  // pool actually asks is how big a file is and whether it
                  // is the one they exported an hour ago. The path is one
                  // hover away and no longer the only thing on offer.
                  Tooltip(
                    message: asset.path,
                    child: Text(
                      _subtitleFor(asset),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // F-118 — the mark is a way to WHERE: 「해당 버튼 누르면 공용창
          // 띄워서 어디서 쓰는지 리스트로 표시하도록」. On a row nothing uses
          // it stays in its place, dimmed with nothing to open (「없다가
          // 생기는 UI 금지」), so the name does not move when the last use
          // goes — and its tooltip names what it opens, which is true of both.
          AppIconButton(
            keyValue: 'media-asset-in-use-${asset.path}',
            tooltip: AppText.strings.mediaUsesHeading,
            icon: const Icon(Icons.link),
            size: AppIconButtonSize.micro,
            onPressed: uses.isEmpty ? null : () => _showUses(context, asset),
          ),
          // R6 #4: the shared flyout. These rows had no `height` at all, so
          // they came out at Material's `kMinInteractiveDimension` — 48px
          // beside the app's 32.
          PanelFlyoutTrigger(
            key: ValueKey<String>('media-asset-menu-${asset.path}'),
            tooltip: AppText.strings.mediaActions,
            entriesBuilder: () => [
              if (onOpenAsset != null)
                PanelFlyoutItem(
                  keyValue: 'media-asset-menu-open',
                  label: AppText.strings.mediaOpenInViewer,
                  onSelected: () => onOpenAsset?.call(asset),
                ),
              if (onOpenAssetInSubViewer != null)
                PanelFlyoutItem(
                  keyValue: 'media-asset-menu-open-sub',
                  label: AppText.strings.mediaOpenInSubViewer,
                  onSelected: () => onOpenAssetInSubViewer?.call(asset),
                ),
              // The pool's way onto the timeline. A row can be DRAGGED
              // there too, but a menu entry is what a tablet hand and a
              // long list want — and it is the only route that exists at
              // all until the timeline grows its drop targets.
              if (onPlaceAsset != null)
                PanelFlyoutItem(
                  keyValue: 'media-asset-menu-place',
                  label: AppText.strings.mediaPlace,
                  onSelected: () => onPlaceAsset?.call(asset),
                ),
              PanelFlyoutItem(
                keyValue: 'media-asset-menu-rename',
                label: AppText.strings.commonRename,
                onSelected: () => _rename(context, asset),
              ),
              PanelFlyoutItem(
                keyValue: 'media-asset-menu-relink',
                label: AppText.strings.mediaRelink,
                onSelected: () => _relink(context, asset.path),
              ),
              // The other half of importing by reference: the moment the
              // user decides the project should own this file after all.
              //
              // 🪦It used to be offered on EVERY row, on the grounds that
              // hiding it would change the menu's shape「for a reason the
              // user cannot see」. 유저 2026-08-31 removed that ground and
              // asked for both halves together: 「그걸 텍스트로 적어두고
              // **품어진 파일이면 프로젝트 파일에 품기 안뜨도록**」. The
              // row now SAYS which one it is, so the reason is on screen —
              // and an item whose only possible answer is「nothing to do」
              // is not a verb.
              if (!asset.carried)
                PanelFlyoutItem(
                  keyValue: 'media-asset-menu-promote',
                  label: AppText.strings.mediaRegisterInProject,
                  onSelected: () => _promote(context, asset),
                ),
              // 🚨What compression took away, handed back on demand. A
              // conform stopped being a WAV on 2026-08-30 and the user
              // accepted that trade naming this as the replacement:
              // 「압축해제시켜서 내보내기 기능 만들면 되는거아닌가?」.
              //
              // ⛔On every row, like promote above and for the same reason:
              // a menu that changes shape per row is a menu the user cannot
              // learn. An asset with no audio answers so out loud.
              PanelFlyoutItem(
                keyValue: 'media-asset-menu-export-wav',
                label: AppText.strings.mediaExportWav,
                onSelected: () => _exportWav(context, asset),
              ),
              PanelFlyoutItem(
                keyValue: 'media-asset-menu-remove',
                label: AppText.strings.mediaRemove,
                onSelected: () => _remove(context, asset),
              ),
            ],
            child: const Icon(Icons.more_vert, size: 16),
          ),
        ],
      ),
    );

    // The row IS the drag source: dropping it on an SE block links the
    // sound to that block's frame.
    return Draggable<MediaAssetDragData>(
      key: ValueKey<String>('media-asset-row-${asset.path}'),
      data: MediaAssetDragData(path: asset.path, name: asset.name),
      // 🚨The chip hangs at the POINTER, and a drop target depends on it:
      // the only position a target is given is `details.offset`, which is
      // the pointer minus this anchor. Anchored to the child instead — the
      // default — that offset is short by however far into this row the
      // grab happened, and the timeline's layer row would name a frame up
      // to a row's width off. It also reads better: a small chip that
      // follows the finger rather than one hanging off to the left.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // The chip is built in the drag overlay, which the verdict's scope
      // does not reach — so the row hands it the channel from here.
      feedback: MediaAssetDragChip(
        kind: asset.kind,
        name: asset.name,
        verdict: MediaDropVerdictScope.maybeOf(context),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }
}

class _RenameMediaDialog extends StatelessWidget {
  const _RenameMediaDialog({
    required this.initialName,
    required this.extension,
  });

  final String initialName;

  /// The file's extension, beside the field and out of it: a rename changes
  /// the NAME only (유저 2026-09-12: 「이름변경시 이름만 변경」).
  final String extension;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: const ValueKey<String>('media-rename-dialog'),
      title: AppText.strings.mediaRename,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: AppText.strings.commonNameField,
      fieldTrailing: Text(
        extension,
        key: const ValueKey<String>('media-rename-extension'),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      initialValue: initialName,
      confirmLabel: AppText.strings.commonRename,
      emptyError: AppText.strings.mpNameEmpty,
      fieldKey: const ValueKey<String>('media-rename-field'),
      cancelKey: const ValueKey<String>('media-rename-cancel-button'),
      confirmKey: const ValueKey<String>('media-rename-save-button'),
    );
  }
}
