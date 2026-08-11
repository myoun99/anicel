import 'dart:io';


import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors, instantMenuAnimation;
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
    required this.onImportPaths,
    required this.onRenameAsset,
    required this.onRelinkAsset,
    required this.onRemoveAsset,
    this.onOpenAsset,
    this.audioFilePicker,
    this.fileExists,
  });

  final List<MediaAsset> assets;

  /// Whether any clip still references the path (usage badge + remove
  /// guard messaging).
  final bool Function(String path) isAssetReferenced;

  final void Function(List<String> paths) onImportPaths;
  final void Function(String path, String name) onRenameAsset;
  final void Function(String oldPath, String newPath) onRelinkAsset;

  /// Returns false when the asset is still referenced (kept in the pool).
  final bool Function(String path) onRemoveAsset;

  /// Opens the asset in the media viewer (double-click or the row menu);
  /// null hides both entrances.
  final void Function(MediaAsset asset)? onOpenAsset;

  /// Injectable file dialog; defaults to the platform audio picker.
  final Future<String?> Function()? audioFilePicker;

  /// Injectable existence probe; defaults to the real file system.
  final bool Function(String path)? fileExists;

  static const List<String> _mediaExtensions = [
    'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg',
    'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif',
    'mp4', 'mov', 'avi', 'mkv', 'webm',
    'pdf',
  ];

  static Future<String?> _pickAudioFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Media', extensions: _mediaExtensions),
      ],
    );
    return file?.path;
  }

  Future<void> _import() async {
    final path = await (audioFilePicker ?? _pickAudioFile)();
    if (path == null) {
      return;
    }
    onImportPaths([path]);
  }

  Future<void> _relink(String path) async {
    final next = await (audioFilePicker ?? _pickAudioFile)();
    if (next == null) {
      return;
    }
    onRelinkAsset(path, next);
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
                onPressed: _import,
              ),
              const Spacer(),
            ],
          ),
        ),
        const Divider(height: 1),
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
    final exists = (fileExists ?? (path) => File(path).existsSync())(
      asset.path,
    );
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
          PopupMenuButton<String>(
            key: ValueKey<String>('media-asset-menu-${asset.path}'),
            tooltip: AppText.strings.mediaActions,
            popUpAnimationStyle: instantMenuAnimation,
            iconSize: 16,
            onSelected: (action) {
              switch (action) {
                case 'open':
                  onOpenAsset?.call(asset);
                case 'rename':
                  _rename(context, asset);
                case 'relink':
                  _relink(asset.path);
                case 'remove':
                  _remove(context, asset);
              }
            },
            itemBuilder: (context) => [
              if (onOpenAsset != null)
                PopupMenuItem<String>(
                  key: const ValueKey<String>('media-asset-menu-open'),
                  value: 'open',
                  child: Text(AppText.strings.mediaOpenInViewer),
                ),
              PopupMenuItem<String>(
                key: const ValueKey<String>('media-asset-menu-rename'),
                value: 'rename',
                child: Text(AppText.strings.commonRename),
              ),
              PopupMenuItem<String>(
                key: const ValueKey<String>('media-asset-menu-relink'),
                value: 'relink',
                child: Text(AppText.strings.mediaRelink),
              ),
              PopupMenuItem<String>(
                key: const ValueKey<String>('media-asset-menu-remove'),
                value: 'remove',
                child: Text(AppText.strings.mediaRemove),
              ),
            ],
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
