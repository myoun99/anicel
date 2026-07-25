import 'package:flutter/material.dart';

import '../../models/project_background.dart';
import '../editor_session_manager.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';

/// File > Project Background… (R10-⑥): the paper/background choice —
/// white, black, a custom hex color, or the transparent checkerboard
/// (display-only; exports bake white). One undo step on Apply.
class ProjectBackgroundDialog extends StatefulWidget {
  const ProjectBackgroundDialog({super.key, required this.session});

  final EditorSessionManager session;

  @override
  State<ProjectBackgroundDialog> createState() =>
      _ProjectBackgroundDialogState();
}

enum _BackgroundChoice { defaultPaper, white, black, transparent, custom }

class _ProjectBackgroundDialogState extends State<ProjectBackgroundDialog> {
  late _BackgroundChoice _choice;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    final background = widget.session.projectBackground;
    _choice = background.transparent
        ? _BackgroundChoice.transparent
        : background == ProjectBackground.defaultBackground
        ? _BackgroundChoice.defaultPaper
        : background == ProjectBackground.white
        ? _BackgroundChoice.white
        : background == ProjectBackground.black
        ? _BackgroundChoice.black
        : _BackgroundChoice.custom;
    _hexController = TextEditingController(
      text: (background.argb & 0xFFFFFF)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase(),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  ProjectBackground? _resolved() {
    switch (_choice) {
      case _BackgroundChoice.defaultPaper:
        return ProjectBackground.defaultBackground;
      case _BackgroundChoice.white:
        return ProjectBackground.white;
      case _BackgroundChoice.black:
        return ProjectBackground.black;
      case _BackgroundChoice.transparent:
        return const ProjectBackground.transparent();
      case _BackgroundChoice.custom:
        final parsed = int.tryParse(_hexController.text.trim(), radix: 16);
        if (parsed == null || _hexController.text.trim().length != 6) {
          return null;
        }
        return ProjectBackground.color(0xFF000000 | parsed);
    }
  }

  void _apply() {
    final background = _resolved();
    if (background == null) {
      return;
    }
    widget.session.setProjectBackground(background);
    Navigator.of(context).pop();
  }

  Widget _option(
    _BackgroundChoice choice,
    String label, {
    Widget? trailing,
    Key? key,
  }) {
    return RadioListTile<_BackgroundChoice>(
      key: key,
      dense: true,
      title: trailing == null
          ? Text(label)
          : Row(
              children: [
                Text(label),
                const SizedBox(width: 8),
                Expanded(child: trailing),
              ],
            ),
      value: choice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('project-background-dialog'),
      title: strings.backgroundTitle,
      titleIcon: Icons.wallpaper_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 400,
      body: SizedBox(
        width: 340,
        child: RadioGroup<_BackgroundChoice>(
          groupValue: _choice,
          onChanged: (next) => setState(() => _choice = next!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _option(
                _BackgroundChoice.defaultPaper,
                strings.backgroundPaper,
                key: const ValueKey<String>('background-default'),
              ),
              _option(
                _BackgroundChoice.white,
                strings.backgroundWhite,
                key: const ValueKey<String>('background-white'),
              ),
              _option(
                _BackgroundChoice.black,
                strings.backgroundBlack,
                key: const ValueKey<String>('background-black'),
              ),
              _option(
                _BackgroundChoice.transparent,
                strings.backgroundTransparent,
                key: const ValueKey<String>('background-transparent'),
              ),
              _option(
                _BackgroundChoice.custom,
                strings.backgroundCustom,
                key: const ValueKey<String>('background-custom'),
                trailing: TextField(
                  key: const ValueKey<String>('background-custom-hex'),
                  controller: _hexController,
                  decoration: const InputDecoration(
                    prefixText: '#',
                    isDense: true,
                  ),
                  maxLength: 6,
                  buildCounter:
                      (
                        context, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  // Touching the hex field IS choosing "custom".
                  onTap: () =>
                      setState(() => _choice = _BackgroundChoice.custom),
                  onChanged: (_) =>
                      setState(() => _choice = _BackgroundChoice.custom),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.backgroundHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('background-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: const ValueKey<String>('background-apply-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _apply,
        ),
      ],
    );
  }
}
