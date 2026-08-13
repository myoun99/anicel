import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart' show FolderGrant;
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/panel_flyout.dart';
import 'media_asset_drag_data.dart';

/// The dockable media browser (the Resolve Media Pool counterpart): every
/// sound the project knows, importable ahead of use, draggable onto SE
/// blocks to link (footsteps reuse), renamable, and relinkable when the
/// file moved (missing files get a badge instead of silently breaking).
///
/// Pure widget: the workspace wires it to the session's pool API; pickers
/// and the file-existence probe are injectable for tests.
class MediaBrowserPanel extends StatelessWidget {
  const MediaBrowserPanel({
    super.key,
    required this.assets,
    required this.isAssetReferenced,
    required this.onImportRequested,
    required this.onRenameAsset,
    required this.onRelinkAsset,
    required this.onRemoveAsset,
    required this.onPromoteAsset,
    this.onOpenAsset,
    this.onOpenAssetInSubViewer,
    this.audioFilePicker,
    this.missingPaths = const <String>{},
    this.onRelinkMissing,
  });

  final List<MediaAsset> assets;

  /// Whether any clip still references the path (usage badge + remove
  /// guard messaging).
  final bool Function(String path) isAssetReferenced;

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
  final void Function(
    String oldPath,
    String newPath,
    List<FolderGrant> grants,
  )
  onRelinkAsset;

  /// Returns false when the asset is still referenced (kept in the pool).
  final bool Function(String path) onRemoveAsset;

  /// Marks a referenced file as one the project carries, so the next save
  /// writes its bytes inside the `.anicel`. Nothing on disk moves. False
  /// when there was nothing to promote.
  final bool Function(String path) onPromoteAsset;

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
      acceptedTypeGroups: const [FileTypeGroups.poolMedia],
    );
    final next = grants.isEmpty ? null : grants.first.path;
    if (next == null) {
      return;
    }
    onRelinkAsset(path, next, grants);
  }

  Future<void> _rename(BuildContext context, MediaAsset asset) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameMediaDialog(initialName: asset.name),
    );
    if (name == null || name.isEmpty || name == asset.name) {
      return;
    }
    onRenameAsset(asset.path, name);
  }

  void _promote(BuildContext context, MediaAsset asset) {
    if (onPromoteAsset(asset.path)) {
      return;
    }
    // Already carried, or a kind that never is. Saying nothing would read
    // as a menu item that does not work.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppText.strings.mediaAlreadyInProject)),
    );
  }

  void _remove(BuildContext context, MediaAsset asset) {
    if (onRemoveAsset(asset.path)) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppText.strings.mediaStillLinked)),
    );
  }

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
  /// panel. The user chose that over an app-wide strip: 「미디어 브라우저
  /// 관련된거니까 미디어 브라우저에」.
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
            TextButton(
              key: const ValueKey<String>('media-relink-missing'),
              onPressed: onRelinkMissing,
              child: Text(strings.mediaFindInFolder),
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
              IconButton(
                key: const ValueKey<String>('media-import-button'),
                tooltip: AppText.strings.mediaImportAudio,
                // 「＋가 있는 모든 곳, 공통적으로」.
                icon: Icon(
                  Icons.add,
                  size: 18,
                  color: AppColors.addGlyph(enabled: true),
                ),
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
    final referenced = isAssetReferenced(asset.path);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          exists
              ? Icon(
                  switch (asset.kind) {
                    MediaAssetKind.audio => Icons.music_note_outlined,
                    MediaAssetKind.image => Icons.image_outlined,
                    MediaAssetKind.video => Icons.movie_outlined,
                    MediaAssetKind.pdf => Icons.picture_as_pdf_outlined,
                  },
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                )
              : Tooltip(
                  message: 'File missing — relink it',
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
                  Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    asset.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (referenced)
            Tooltip(
              message: 'Linked on SE rows',
              child: Icon(
                key: ValueKey<String>('media-asset-linked-${asset.path}'),
                Icons.link,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
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
              // Offered on every row rather than only on references — a
              // file already carried answers "nothing to do" honestly,
              // and hiding it would mean the row's menu changes shape for
              // a reason the user cannot see.
              PanelFlyoutItem(
                keyValue: 'media-asset-menu-promote',
                label: AppText.strings.mediaRegisterInProject,
                onSelected: () => _promote(context, asset),
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
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note_outlined, size: 14),
              const SizedBox(width: 4),
              Text(asset.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: row,
    );
  }
}

class _RenameMediaDialog extends StatelessWidget {
  const _RenameMediaDialog({required this.initialName});

  final String initialName;

  @override
  Widget build(BuildContext context) {
    return AppPromptDialog(
      windowKey: const ValueKey<String>('media-rename-dialog'),
      title: AppText.strings.mediaRename,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: 'Name',
      initialValue: initialName,
      confirmLabel: 'Rename',
      emptyError: 'Media name cannot be empty.',
      fieldKey: const ValueKey<String>('media-rename-field'),
      cancelKey: const ValueKey<String>('media-rename-cancel-button'),
      confirmKey: const ValueKey<String>('media-rename-save-button'),
    );
  }
}
