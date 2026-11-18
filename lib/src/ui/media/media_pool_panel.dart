import '../widgets/app_tooltip.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/empty_state_text.dart';
import '../widgets/app_icon_button.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
import '../../models/se_take_placement.dart' show placedSoundBlockOf;
import '../../services/media/media_facts.dart' show MediaPoolFacts;
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart' show FolderGrant;
import '../dialogs/app_confirm_dialog.dart'
    show
        ConfirmChoice,
        ConfirmQuestion,
        NoticeDetails,
        askConfirm,
        confirmDialogKeys,
        showAppNotice;
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/folder_pick_flow.dart';

import '../text/app_strings.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/app_window.dart' show AppWindowActionEmphasis;
import '../widgets/overflow_scrollers.dart';
import '../widgets/owning_draggable.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import 'media_asset_drag_chip.dart';
import 'media_asset_drag_data.dart';
import 'media_asset_kind_icon.dart';
import 'media_drop_verdict.dart';
import 'media_pool_list.dart';
import 'media_pool_icons.dart';
import 'media_pool_pictures.dart';
import 'media_pool_view.dart';
import 'media_pool_words.dart';
import '../timeline/se_name_tag_lane_preview.dart';
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
    this.onEditPreset,
    this.partsOf = _partsFromNothing,
    this.onSync,
    this.mediaFilePicker,
    this.missingPaths = const <String>{},
    this.modifiedTimes = const <String, DateTime>{},
    this.storedBytes = const <String, int>{},
    this.conformBytes = const <String, int>{},
    this.onRelinkMissing,
    this.view = const MediaPoolView(),
    this.onViewChanged,
    this.factsOf = _nothingRead,
    this.soundOf = _nothingHeard,
    this.frameRate = ProjectFrameRate.fps24,
    this.pictures,
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

  /// Opens the file's 배치 프리셋 window. Null leaves it off the menu.
  final void Function(MediaAsset asset)? onEditPreset;

  /// Whether a place of the file parts from its preset — the in-use mark
  /// then wears the sync in its own place, and opens [onSync] (시안 ③,
  /// `soundPartsFromItsPreset`).
  final bool Function(MediaAsset asset) partsOf;

  /// Opens the file's sync window.
  final void Function(MediaAsset asset)? onSync;

  /// Injectable file dialog for a relink; defaults to the platform picker
  /// over every kind the pool registers.
  final Future<String?> Function()? mediaFilePicker;

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

  /// When each pool file the project points at was last written — the
  /// session's sweep fills it, so a row never stats the disk to draw
  /// itself. A carried row shows its carry's date instead ([_dateOf]).
  final Map<String, DateTime> modifiedTimes;

  /// What each carried asset ACTUALLY occupies — compressed, in the
  /// project file or in staging. Empty for assets the project only
  /// references, whose own file length is the honest answer.
  final Map<String, int> storedBytes;

  /// Pool path → what its CONFORM occupies, for the assets that have one.
  /// Empty for every non-audio asset, and for audio nobody has played yet.
  final Map<String, int> conformBytes;

  /// How the pool shows its files — a line each or big pictures, each as
  /// it is or as its preset places it ([MediaPoolView]).
  final MediaPoolView view;

  /// Asks for another [view] — the two buttons right of the ＋. Null keeps
  /// the view as it is, the buttons with nothing to do.
  final ValueChanged<MediaPoolView>? onViewChanged;

  /// What the session has read of a file beyond its entry — its picture's
  /// size, its sound's rate and channels — null while it has not.
  final MediaPoolFacts? Function(String path) factsOf;

  /// A sound's waveform where its conform is held — never asking for one:
  /// how long it lasts in the list, its picture in the icon view.
  final AudioPeaks? Function(String path) soundOf;

  /// The project's rate, which a length is told in.
  final ProjectFrameRate frameRate;

  /// Where the icon view's pictures come from. Null draws each box by its
  /// file's kind alone.
  final MediaPoolPictures? pictures;

  static MediaPoolFacts? _nothingRead(String path) => null;
  static AudioPeaks? _nothingHeard(String path) => null;
  static bool _partsFromNothing(MediaAsset asset) => false;

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
    final injected = mediaFilePicker;
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

  /// [name], with where the file lies on hover — on a line whose file lives
  /// outside the project.
  ///
  /// 🗣️F-589 (유저 11-13: 「품었는데 이거 필요한지?」): a carried file's
  /// bytes are the project's, and nothing the person does with it goes to
  /// its first place again — relink is never offered for it (its original
  /// leaving is not「missing」, `MediaPool.refreshMediaExistence`) and the
  /// pool has no verb that opens or refreshes from it. The path stays the
  /// asset's key, which nothing shows. ↩️The hover named the path on every
  /// row since 2c5176b0f (08-30), when size and date took its place on the
  /// line — nobody asked for it on a carried row.
  Widget _placeOnHover(MediaAsset asset, Widget name) => asset.carried
      ? name
      : AppTooltip(message: asset.path, child: name);

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
  ///
  /// 🗣️I-58 (유저 2026-10-18): 「ㅁㅁ 삭제」 — the button is 「미디어 삭제」:
  /// it takes the media and what was placed from it out of the project, as
  /// 「레이어 삭제」 takes a layer, and leaves the file on the disk. The
  /// question asks in the button's word. ↩️Both said 「제거」, F-118's word
  /// for the button as it was.
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
          details: [NoticeDetails(uses, heading: strings.mediaUsesHeading)],
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
      details: [
        NoticeDetails(
          usesOf(asset.path).toList(),
          heading: AppText.strings.mediaUsesHeading,
          open: true,
        ),
      ],
      windowKey: const ValueKey<String>('media-asset-uses-notice'),
    ),
  );

  /// Below this width the asset rows' FIXED parts (status icon, link
  /// badge, actions menu) no longer fit — the panel then scrolls
  /// horizontally at this width instead of overflowing (R10-①).
  ///
  /// ⚠️PLUS the widest extension the list shows ([_extensionRoom]). Since a
  /// row's name and its extension stand apart (pool-name-without-extension)
  /// the extension is a fixed part too — the name is what gets cut short,
  /// never the extension — and a word's width is measured, not guessed.
  static const double _minBodyWidth = 132;

  /// The toolbar row plus its rule, and the list's head plus its rule —
  /// below this the body has no room for its own fixed parts and would
  /// overflow, the same rule [_minBodyWidth] states for the other axis (R9
  /// #17 hit it: the tool rail's narrowing reflowed the docks and squeezed
  /// this panel).
  static const double _minBodyHeight = 37 + MediaPoolList.headHeight + 1;

  /// A row's name line — its name and its extension — and what
  /// [_extensionRoom] measures the extensions in.
  static const TextStyle _nameLine = TextStyle(fontSize: 12);

  /// The widest extension among [assets], set the way a row's name line
  /// sets it.
  double _extensionRoom(BuildContext context) => TextMeasure(
    context,
    DefaultTextStyle.of(context).style.merge(_nameLine),
  ).widest({
    for (final asset in assets) mediaFileNameParts(asset.path).extension,
  }).ceilToDouble();

  // ★The bake goes INSIDE the floor's scrollers. They are always mounted
  // (a narrowing past the floor keeps the list where it was), and a
  // viewport is a repaint boundary — so the dock's bake around this panel
  // yields to this one, the placement `EditorPanelBody` explains.
  // ↩️A key pressed the ＋ (I-40) until F-580 (유저 2026-11-10: 「패널 안의
  // 미디어-임포트 이런식으로 패널 안 항목도 깔끔하게 삭제」).
  @override
  Widget build(BuildContext context) => OverflowScrollers(
    minWidth: _minBodyWidth + _extensionRoom(context),
    minHeight: _minBodyHeight,
    child: StaticRaster(debugLabel: 'body:media', child: _body(context)),
  );

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
            child: EllipsisText(
              // The count's position differs by language, so the string
              // carries the slot rather than the call site carrying the
              // word order.
              strings.mediaMissingCount.replaceAll('{n}', '$count'),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
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
        _toolbar(),
        const Divider(height: 1),
        _missingBanner(colorScheme),
        Expanded(child: _content(colorScheme)),
      ],
    );
  }

  /// The ＋, and right of it the two view buttons.
  Widget _toolbar() {
    final strings = AppText.strings;
    final changeView = onViewChanged;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 4),
          AppIconButton(
            keyValue: 'media-import-button',
            // The window it opens, by that window's own title: the pool
            // once held sound only, and 「오디오 불러오기」 outlived it
            // (유저 10-09).
            tooltip: strings.imImport,
            // 「＋가 있는 모든 곳, 공통적으로」.
            icon: Icon(Icons.add, color: AppColors.addGlyph(enabled: true)),
            onPressed: onImportRequested,
          ),
          const Spacer(),
          // 🗣️asset-placement-presets Q6 (유저 2026-11-17): 「시안대로 —
          // 위 툴바(＋ 줄 오른쪽)」. The preset face is a state, lit as
          // every on button is; the shape button draws the view a press
          // goes to.
          AppIconButton(
            keyValue: 'media-view-presets',
            tooltip: strings.mediaViewPresets,
            icon: const Icon(Icons.style_outlined),
            isSelected: view.presets,
            onPressed: changeView == null
                ? null
                : () => changeView(view.copyWith(presets: !view.presets)),
          ),
          AppIconButton(
            keyValue: 'media-view-icons',
            tooltip: view.icons
                ? strings.mediaViewList
                : strings.mediaViewIcons,
            icon: Icon(
              view.icons
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined,
            ),
            onPressed: changeView == null
                ? null
                : () => changeView(view.copyWith(icons: !view.icons)),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// The files as the view shows them — or the line that says there are
  /// none, where the first would be.
  Widget _content(ColorScheme colorScheme) {
    final strings = AppText.strings;
    return assets.isEmpty
        // 유저 2026-09-15: 「공용 위젯 하나 + 짧은 한 줄」 — the usage
        // sentence that followed went (「설명 문구 금지」), and the line
        // moved from the middle to where the first row would be
        // (「내용이 올 자리에」).
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: EmptyStateText(
              strings.mediaPoolEmpty,
              key: const ValueKey<String>('media-browser-empty'),
              place: EmptyStatePlace.list,
            ),
          )
        : view.icons
        ? MediaPoolIcons(
            assets: assets,
            pictures: pictures,
            markOf: (asset) => _markOf(asset, colorScheme),
            badgeOf: view.presets ? _words.spanWord : _words.lengthWord,
            captionOf: (context, asset) => Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _captionOf(context, asset),
            ),
            tileOf: _lineOf,
            soundOf: soundOf,
            frameRate: frameRate,
          )
        : MediaPoolList(
            assets: assets,
            columns: view.presets
                ? _words.presetColumns()
                : _words.fileColumns(),
            nameLabel: strings.commonNameField,
            nameOf: _nameOf,
            lineOf: _lineOf,
          );
  }

  /// What the lines say column by column, from what the session holds.
  MediaPoolWords get _words => MediaPoolWords(
    framesPerSecond: frameRate.countingBase,
    storedBytes: storedBytes,
    conformBytes: conformBytes,
    modifiedTimes: modifiedTimes,
    factsOf: factsOf,
    soundFramesOf: (path) => soundOf(path)?.durationFrames(frameRate),
  );

  /// The pinned part of [asset]'s line: what it is, its name — or what its
  /// preset places, in the preset face — and the two buttons on it.
  Widget _nameOf(BuildContext context, MediaAsset asset) => Row(
    children: [
      const SizedBox(width: 8),
      _markOf(asset, Theme.of(context).colorScheme),
      const SizedBox(width: 6),
      Expanded(child: _captionOf(context, asset)),
    ],
  );

  /// The line's name — or what its preset places — and the two buttons on
  /// it: the list's name cell after its mark, and an icon box's caption.
  Widget _captionOf(BuildContext context, MediaAsset asset) {
    final colorScheme = Theme.of(context).colorScheme;
    final uses = usesOf(asset.path);
    return Row(
      children: [
        Expanded(
          // The double-click zone is the NAME AREA only: a double-tap
          // recognizer over the whole line would hold the menu button's
          // taps in the gesture arena for the double-tap window.
          child: GestureDetector(
            onDoubleTap: onOpenAsset == null ? null : () => onOpenAsset!(asset),
            behavior: HitTestBehavior.opaque,
            child: view.presets
                ? _presetFaceOf(asset)
                : _placeOnHover(asset, _fileNameOf(asset, colorScheme)),
          ),
        ),
        // F-118 — the mark is a way to WHERE: 「해당 버튼 누르면 공용창
        // 띄워서 어디서 쓰는지 리스트로 표시하도록」. On a line nothing uses
        // it stays in its place, dimmed with nothing to open (「없다가
        // 생기는 UI 금지」), so the name does not move when the last use
        // goes — and its tooltip names what it opens, which is true of both.
        // 🗣️시안 ③ (card 「파일마다 배치 기본값」-Q6 「시안대로」): where a
        // place parts from the file's preset, the SAME button wears the
        // sync in the accent and opens the sync window instead.
        _inUseMark(context, asset, used: uses.isNotEmpty),
        _menuOf(context, asset),
      ],
    );
  }

  /// The line's in-use mark: where the file is used — or, where a place
  /// parts from its preset ([partsOf]), the sync.
  Widget _inUseMark(
    BuildContext context,
    MediaAsset asset, {
    required bool used,
  }) {
    final parts = used && onSync != null && partsOf(asset);
    return AppIconButton(
      keyValue: 'media-asset-in-use-${asset.path}',
      tooltip: parts
          ? AppText.strings.mediaSync
          : AppText.strings.mediaUsesHeading,
      icon: Icon(parts ? Icons.sync : Icons.link),
      isSelected: parts,
      size: AppIconButtonSize.micro,
      onPressed: switch ((used, parts)) {
        (false, _) => null,
        (true, true) => () => onSync!(asset),
        (true, false) => () => _showUses(context, asset),
      },
    );
  }

  /// The line's first mark: what the file is — by its type in the file
  /// face, by the layer its preset makes in the preset face — or that it is
  /// missing, in the same place in both.
  Widget _markOf(MediaAsset asset, ColorScheme colorScheme) {
    if (missingPaths.contains(asset.path)) {
      return AppTooltip(
        message: AppText.strings.mpFileMissing,
        child: Icon(
          key: ValueKey<String>('media-asset-missing-${asset.path}'),
          Icons.error_outline,
          size: 16,
          color: colorScheme.error,
        ),
      );
    }
    return Icon(
      view.presets
          ? _words.kindIconOf(asset)
          : mediaAssetKindIcon(asset.kind, path: asset.path),
      size: 16,
      color: colorScheme.onSurfaceVariant,
    );
  }

  /// The NAME and its EXTENSION apart, as the import window's table shows a
  /// file (유저 2026-09-12: 「풀에서 이름이랑 확장자 나누고」): the name is
  /// what gets cut short, the extension never is.
  Widget _fileNameOf(MediaAsset asset, ColorScheme colorScheme) => Row(
    children: [
      Flexible(child: EllipsisText(asset.name, maxLines: 1, style: _nameLine)),
      Text(
        mediaFileNameParts(asset.path).extension,
        maxLines: 1,
        style: _nameLine.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    ],
  );

  /// What [asset]'s preset places, in the preset face (시안 ①): a sound's
  /// block as the timeline draws it, in miniature — its name tag and its
  /// words — and a picture's layer by the name it is born with.
  Widget _presetFaceOf(MediaAsset asset) {
    if (asset.kind == MediaAssetKind.audio) {
      final block = placedSoundBlockOf(asset, named: asset.name);
      return Align(
        alignment: Alignment.centerLeft,
        child: SeNameTagLanePreview(
          key: ValueKey<String>('media-asset-preset-block-${asset.path}'),
          name: block.seName,
          line: block.words,
        ),
      );
    }
    return EllipsisText(
      mediaAssetNameFor(asset, asset.path),
      maxLines: 1,
      style: _nameLine,
    );
  }

  /// The line's actions — R6 #4: the shared flyout, at the line's height.
  Widget _menuOf(BuildContext context, MediaAsset asset) => PanelFlyoutTrigger(
    key: ValueKey<String>('media-asset-menu-${asset.path}'),
    tooltip: AppText.strings.mediaActions,
    padding: const EdgeInsets.all(4),
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
      // The pool's way onto the timeline. A line can be DRAGGED there too,
      // but a menu entry is what a tablet hand and a long list want.
      if (onPlaceAsset != null)
        PanelFlyoutItem(
          keyValue: 'media-asset-menu-place',
          label: AppText.strings.mediaPlace,
          onSelected: () => onPlaceAsset?.call(asset),
        ),
      // 🗣️asset-placement-presets Q6 (유저 2026-11-17 「시안대로」): under
      // 배치, what every placement of the file starts from.
      if (onEditPreset != null)
        PanelFlyoutItem(
          keyValue: 'media-asset-menu-preset',
          label: AppText.strings.mediaPresetMenu,
          onSelected: () => onEditPreset?.call(asset),
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
      // The other half of importing by reference: the moment the user
      // decides the project should own this file after all.
      //
      // 🪦It used to be offered on EVERY row, on the grounds that hiding it
      // would change the menu's shape「for a reason the user cannot see」.
      // 유저 2026-08-31 removed that ground and asked for both halves
      // together: 「그걸 텍스트로 적어두고 **품어진 파일이면 프로젝트 파일에
      // 품기 안뜨도록**」. The line now SAYS which one it is, so the reason is
      // on screen — and an item whose only possible answer is「nothing to
      // do」is not a verb.
      if (!asset.carried)
        PanelFlyoutItem(
          keyValue: 'media-asset-menu-promote',
          label: AppText.strings.mediaRegisterInProject,
          onSelected: () => _promote(context, asset),
        ),
      // 🚨What compression took away, handed back on demand. A conform
      // stopped being a WAV on 2026-08-30 and the user accepted that trade
      // naming this as the replacement: 「압축해제시켜서 내보내기 기능
      // 만들면 되는거아닌가?」.
      //
      // ⛔On every line, like promote above and for the same reason: a menu
      // that changes shape per line is a menu the user cannot learn. An
      // asset with no audio answers so out loud.
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
  );

  /// [line] as a drag source: dropping it on an SE block links the sound to
  /// that block's frame, and on a row places the file there. It lifts on the
  /// first move for every device (F-126, [OwningDraggable]).
  Widget _lineOf(MediaAsset asset, Widget line) => Builder(
    builder: (context) => OwningDraggable<MediaAssetDragData>(
      key: ValueKey<String>('media-asset-row-${asset.path}'),
      data: MediaAssetDragData(path: asset.path, name: asset.name),
      // 🚨The chip hangs at the POINTER, and a drop target depends on it:
      // the only position a target is given is `details.offset`, which is
      // the pointer minus this anchor. Anchored to the child instead — the
      // default — that offset is short by however far into this line the
      // grab happened, and the timeline's layer row would name a frame up
      // to a line's width off. It also reads better: a small chip that
      // follows the finger rather than one hanging off to the left.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // The chip is built in the drag overlay, which the verdict's scope
      // does not reach — so the line hands it the channel from here.
      feedback: MediaAssetDragChip(
        kind: asset.kind,
        name: asset.name,
        path: asset.path,
        verdict: MediaDropVerdictScope.maybeOf(context),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: line),
      child: line,
    ),
  );
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
