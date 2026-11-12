import 'package:flutter/material.dart';

import '../../copy/settings_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// §SETTINGS.REMEMBERED_HOOK: the Adding entries row that opens Remembered when
/// the auto-read build passes a hook (the standard build keeps today's row).
///
/// What the auto-read build tells the Settings row: how many airtime switches
/// are on (0 to 2) and how many remembered names there are. A null part is
/// left out of the sub-line. Plain Dart: this file imports nothing from the
/// auto-read folder, so the standard build never sees it used.
class RememberedRowInfo {
  const RememberedRowInfo({this.autoOn, this.names});
  final int? autoOn;
  final int? names;
}

/// The hook the auto-read build passes into Settings. [load] is read when the
/// row first shows, when [changes] fires, and again when the page closes.
class RememberedRowHook {
  const RememberedRowHook({required this.load, this.changes});
  final Future<RememberedRowInfo> Function() load;
  final Listenable? changes;
}

/// The sub-line for [info]; today's line when nothing is supplied.
String rememberedRowSub(RememberedRowInfo? info) {
  if (info == null || (info.autoOn == null && info.names == null)) return kRememberedRowSubtitle;
  final parts = <String>[
    if (info.autoOn != null) kRememberedRowAutoPart(info.autoOn!),
    if (info.names != null) kRememberedRowNamesPart(info.names!),
  ];
  return '${parts.join(' · ')}$kRememberedRowTail';
}

/// The one Adding entries row used when the hook is present: opens the
/// Remembered page and refreshes its sub-line when you come back.
class RememberedHookRow extends StatefulWidget {
  const RememberedHookRow({super.key, required this.palette, required this.hook});
  final AppPalette palette;
  final RememberedRowHook hook;

  @override
  State<RememberedHookRow> createState() => _RememberedHookRowState();
}

class _RememberedHookRowState extends State<RememberedHookRow> {
  RememberedRowInfo? _info;

  @override
  void initState() {
    super.initState();
    widget.hook.changes?.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.hook.changes?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    RememberedRowInfo? next;
    try {
      next = await widget.hook.load();
    } catch (_) {
      next = null;
    }
    if (mounted) setState(() => _info = next);
  }

  Future<void> _open() async {
    await Navigator.of(context).pushNamed(Routes.rememberedRecipients);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final sub = rememberedRowSub(_info);
    return Semantics(
      button: true,
      label: '$kRememberedAutoRowLabel. $sub',
      excludeSemantics: true,
      onTap: _open,
      child: SettingsLink(
        palette: widget.palette,
        icon: Icons.people_outline,
        label: kRememberedAutoRowLabel,
        subtitle: sub,
        onTap: _open,
      ),
    );
  }
}
