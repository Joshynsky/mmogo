import 'package:flutter/material.dart';

import '../../../data/prefs/recipient_memory.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../copy/settings_copy.dart';
import '../../shell/app_messenger.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_notes.dart';
import '../../widgets/palette_alert_dialog.dart';
import '../add/recipient_chooser.dart' show recipientTypeName;

/// §SCREEN.REMEMBERED — 0.1.2 S9a (signed mock remembered.html): the names the
/// user told us are Send Money or Pochi. Lists [RecipientMemory.list] newest
/// first with the stored (upper case) name and type; Change to the other type
/// (the row keeps its place), Forget one, Forget all (asks first; a tap outside
/// and Back both mean Cancel); an empty state.
///
/// PRIVACY: a name never goes into a snackbar, an error line or a log. The
/// only places a name is drawn are the row itself and its screen-reader label.
/// Messages carry counts ("Forgot 2 recipients").
class RememberedScreen extends StatefulWidget {
  const RememberedScreen({super.key, this.memory});

  /// Test seam (defaults to the real prefs-backed memory).
  final RecipientMemory? memory;

  @override
  State<RememberedScreen> createState() => _RememberedScreenState();
}

class _RememberedScreenState extends State<RememberedScreen> {
  late final RecipientMemory _memory = widget.memory ?? RecipientMemory();
  List<RecipientEntry> _entries = const [];
  bool _loaded = false;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await _memory.list();
    if (!mounted) return;
    setState(() {
      _entries = all;
      _loaded = true;
    });
  }

  void _toast(String text) {
    // Counts only, never a name.
    final messenger = appMessengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    // R28 (F2): about 2 seconds, so it does not linger over the pinned Forget all button.
    messenger?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _run(Future<bool> Function() op, {String? done}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    var ok = false;
    try {
      ok = await op();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = !ok;
    });
    if (ok && done != null) _toast(done);
  }

  Future<void> _change(RecipientEntry e) {
    final other = e.rule.type == SmsSourceType.pochi ? SmsSourceType.sendMoney : SmsSourceType.pochi;
    return _run(() => _memory.retype(e.key, other));
  }

  Future<void> _forget(RecipientEntry e) => _run(() => _memory.forget(e.key), done: forgotRecipientsText(1));

  Future<void> _forgetAll() async {
    final n = _entries.length;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return PaletteAlertDialog(
          key: const Key('forgetAllDialog'),
          title: const Text(kForgetAllTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text(kForgetAllBody),
          actions: [
            TextButton(
              key: const Key('forgetAllCancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(kRememberedCancel, style: TextStyle(fontWeight: FontWeight.w700, color: palette.primary)),
            ),
            TextButton(
              key: const Key('forgetAllConfirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(kForgetAll, style: TextStyle(fontWeight: FontWeight.w700, color: palette.error)),
            ),
          ],
        );
      },
    );
    if (go != true || !mounted) return; // outside tap and Back arrive here as null
    await _run(_memory.forgetAll, done: forgotRecipientsText(n));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: kRememberedTitle,
      followPalette: true,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              key: const Key('rememberedScroll'),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    kRememberedIntro,
                    key: const Key('rememberedIntro'),
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.mutedInk),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
                  child: Text(
                    kRememberedStaySentence,
                    key: const Key('rememberedStay'),
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.ink, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_error)
                  FieldError(kRememberedCouldNot, padding: const EdgeInsets.fromLTRB(2, 0, 2, 10)),
                if (_loaded && _entries.isEmpty) _empty(palette),
                if (_entries.isNotEmpty)
                  AppCard(
                    palette: palette,
                    clip: true,
                    child: Column(
                      children: [
                        for (final (i, e) in _entries.indexed)
                          _RememberedRow(
                            key: ValueKey('row-${e.key}'),
                            entry: e,
                            palette: palette,
                            first: i == 0,
                            enabled: !_busy,
                            onChange: () => _change(e),
                            onForget: () => _forget(e),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: palette.background,
              border: Border(top: BorderSide(color: palette.line)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                key: const Key('rememberedForgetAll'),
                onPressed: _entries.isEmpty || _busy ? null : _forgetAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.error,
                  disabledForegroundColor: palette.mutedInk,
                  side: BorderSide(color: _entries.isEmpty ? palette.line : palette.error, width: 1.5),
                  shape: const StadiumBorder(),
                ),
                child: const Text(kForgetAll, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(AppPalette palette) {
    return AppCard(
      palette: palette,
      child: Padding(
        key: const Key('rememberedEmpty'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.person_add_alt_outlined, size: 26, color: palette.tintInk),
            ),
            const SizedBox(height: 8),
            Text(
              kRememberedEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.ink),
            ),
            const SizedBox(height: 8),
            Text(
              kRememberedEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: palette.mutedInk),
            ),
            const SizedBox(height: 8),
            Text(
              kRememberedEmptyNote,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.5, color: palette.mutedInk),
            ),
          ],
        ),
      ),
    );
  }
}

class _RememberedRow extends StatelessWidget {
  const _RememberedRow({
    super.key,
    required this.entry,
    required this.palette,
    required this.first,
    required this.enabled,
    required this.onChange,
    required this.onForget,
  });

  final RecipientEntry entry;
  final AppPalette palette;
  final bool first;
  final bool enabled;
  final VoidCallback onChange;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final type = entry.rule.type;
    final other = type == SmsSourceType.pochi ? SmsSourceType.sendMoney : SmsSourceType.pochi;
    final code = type.dbValue;
    final tagText = palette.typePillFill(code);
    return Container(
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: palette.line))),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.key,
                  key: const Key('rememberedName'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const Key('rememberedTag'),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: tagText.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagText.withValues(alpha: 0.45)),
                ),
                child: Text(
                  recipientTypeName(type),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: palette.ink),
                ),
              ),
            ],
          ),
          Wrap(
            children: [
              _RowButton(
                key: const Key('rememberedChange'),
                text: 'Change to ${recipientTypeName(other)}',
                semantics: 'Change ${entry.key} to ${recipientTypeName(other)}',
                color: palette.primary,
                onTap: enabled ? onChange : null,
              ),
              _RowButton(
                key: const Key('rememberedForget'),
                text: kForgetOne,
                semantics: 'Forget ${entry.key}',
                color: palette.error,
                onTap: enabled ? onForget : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({super.key, required this.text, required this.semantics, required this.color, required this.onTap});

  final String text;
  final String semantics;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Align(
              widthFactor: 1,
              alignment: Alignment.centerLeft,
              child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}
