import 'package:flutter/material.dart';

import '../../widgets/pill_toast.dart';
import '../../../data/prefs/recipient_memory.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../copy/settings_copy.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/error_notes.dart';
import '../../widgets/help_sheet.dart';
import '../../widgets/palette_alert_dialog.dart';
import '../add/recipient_chooser.dart' show recipientTypeName;
import 'remembered_extra_tab.dart';
import 'remembered_tab_pills.dart';

/// §SCREEN.REMEMBERED — 0.1.2 S9a (signed mock remembered.html): the names the
/// user told us are Send Money or Pochi. Lists [RecipientMemory.list] newest
/// first with the stored (upper case) name and type; Change to the other type
/// (the row keeps its place), Forget one, Forget all (asks first; a tap outside
/// and Back both mean Cancel); an empty state. 0.2.2 U-FORGET (B-5): Forget all is enabled when names +
/// the extra tab's people ([rememberedForgetAllExtra], each person once) > 0, disabled-looking only at 0.
///
/// PRIVACY: a name never goes into a snackbar, an error line or a log. The
/// only places a name is drawn are the row itself and its screen-reader label.
/// Messages carry counts ("Forgot 2 recipients").
class RememberedScreen extends StatefulWidget {
  const RememberedScreen({super.key, this.memory, this.extraTab, this.openExtraTab = false});

  /// A second tab for the page. Null keeps the page as it was: no tabs.
  final RememberedExtraTab? extraTab;

  /// Open on the second tab (a deep link). Ignored when there is no second tab.
  final bool openExtraTab;

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
  late int _tab = widget.openExtraTab && widget.extraTab != null ? 1 : 0;

  /// 0.2.2 U-FORGET (B-5): people Forget all removes on top of the names (the extra tab's count, each
  /// person once; 0 = names only). Null = the count could not be taken: the button stays enabled and the
  /// dialog's own count decides. Never a name, never shown.
  int? _extra = 0;
  int _countRun = 0;
  bool _tabChosen = false;

  /// Forget all has someone to forget: names + the extra tab's people > 0 (an unknown extra count counts
  /// as someone). The disabled look is only for a true 0.
  bool get _anyoneToForget => _entries.isNotEmpty || (_extra ?? 1) > 0;

  @override
  void initState() {
    super.initState();
    widget.extraTab?.listenable.addListener(_recount);
    _reload();
    _openOnPeople();
  }

  /// 0.2.2: with no deep link, open on the second tab when it holds people (the recipients tab is often
  /// empty while the people are one tap away). A tab the person already chose is never overridden.
  Future<void> _openOnPeople() async {
    final t = widget.extraTab;
    if (t is! RememberedOpensOnPeople || widget.openExtraTab) return;
    var holds = false;
    try {
      holds = await (t as RememberedOpensOnPeople).holdsPeople();
    } catch (_) {}
    if (holds && mounted && !_tabChosen) setState(() => _tab = 1);
  }

  @override
  void dispose() {
    widget.extraTab?.listenable.removeListener(_recount);
    super.dispose();
  }

  Future<void> _reload() async {
    final all = await _memory.list();
    if (!mounted) return;
    setState(() {
      _entries = all;
      _loaded = true;
    });
    await _recount();
  }

  /// Takes the extra tab's count again (after a load, a tab switch, or when the tab says it changed).
  /// Only the latest run is kept.
  Future<void> _recount() async {
    final run = ++_countRun;
    int? extra;
    try {
      extra = await rememberedForgetAllExtra(widget.extraTab, [for (final e in _entries) e.key]);
    } catch (_) {
      extra = null;
    }
    if (!mounted || run != _countRun || extra == _extra) return;
    setState(() => _extra = extra);
  }

  void _toast(String text) {
    // Counts only, never a name.
    // The pill stays at least 6 s (it sits at the top, clear of the pinned Forget all button).
    PillToast.show(text);
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
    return _run(() async {
      final ok = await _memory.retype(e.key, other);
      if (ok && other == SmsSourceType.sendMoney) await _hooks?.onNameChangedToSendMoney(e.key);
      return ok;
    });
  }

  Future<void> _forget(RecipientEntry e) => _run(() async {
        final ok = await _memory.forget(e.key);
        if (ok) await _hooks?.onNameForgotten(e.key);
        return ok;
      }, done: forgotRecipientsText(1));

  /// The second tab's own clean-up, when it has one (what it keeps about a name goes with the name).
  RememberedForgetHooks? get _hooks {
    final t = widget.extraTab;
    return t is RememberedForgetHooks ? t as RememberedForgetHooks : null;
  }

  /// The second tab's own Forget all words, when it has them (0.2.2; null = the page's words).
  Future<RememberedForgetAllText?> _forgetAllText() async {
    final t = widget.extraTab;
    if (t is! RememberedForgetAllCopy) return null;
    return (t as RememberedForgetAllCopy).forgetAllText([for (final e in _entries) e.key]);
  }

  Future<void> _forgetAll() async {
    final n = _entries.length;
    RememberedForgetAllText? got; // counts only, never a name
    try {
      got = await _forgetAllText();
    } catch (_) {
      if (mounted) setState(() => _error = true); // no true count = no dialog
      return;
    }
    if (!mounted) return;
    final own = got;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return PaletteAlertDialog(
          key: const Key('forgetAllDialog'),
          title: Text(own?.title ?? kForgetAllTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: own != null
              ? Text(own.body)
              : widget.extraTab == null
              ? const Text(kForgetAllBody)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const Text(kForgetAllBody), const SizedBox(height: 8), Text(widget.extraTab!.forgetAllNote)],
                ),
          actions: [
            TextButton(
              key: const Key('forgetAllCancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(kRememberedCancel, style: TextStyle(fontWeight: FontWeight.w700, color: palette.primary)),
            ),
            TextButton(
              key: const Key('forgetAllConfirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(own?.ok ?? kForgetAll, style: TextStyle(fontWeight: FontWeight.w700, color: palette.error)),
            ),
          ],
        );
      },
    );
    if (go != true || !mounted) return; // outside tap and Back arrive here as null
    await _run(() async {
      final ok = await _memory.forgetAll();
      if (ok) await _hooks?.onAllNamesForgotten();
      return ok;
    }, done: own?.toast ?? forgotRecipientsText(n));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final extra = widget.extraTab;
    final recipients = Column(children: [Expanded(child: _list(palette)), _forgetBar(palette)]);
    return SecondaryScaffold(
      title: extra?.pageTitle ?? kRememberedTitle,
      followPalette: true,
      // ONE "?" per screen; on the second tab it explains that tab.
      actions: [
        if (extra != null && _tab == 1)
          HelpPageButton(title: extra.help.title, paragraphs: extra.help.paragraphs)
        else
          const HelpPageButton(title: kRememberedHelpTitle, paragraphs: kRememberedHelpParagraphs),
      ],
      body: extra == null
          ? recipients
          : Column(
              children: [
                ListenableBuilder(
                  listenable: extra.listenable,
                  builder: (context, _) => RememberedTabPills(
                    palette: palette,
                    labels: [extra.recipientsTabLabel, extra.tabLabel()],
                    selected: _tab,
                    onSelect: (i) {
                      setState(() {
                        _tab = i;
                        _tabChosen = true;
                      });
                      _recount(); // rules may have changed on the second tab
                    },
                  ),
                ),
                // Both tabs stay built, so each keeps its own scroll place.
                Expanded(child: IndexedStack(index: _tab, children: [recipients, extra.buildBody(context)])),
              ],
            ),
    );
  }

  Widget _list(AppPalette palette) {
    return ListView(
              key: const Key('rememberedScroll'),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: palette.mutedInk),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          kRememberedIntro,
                          key: const Key('rememberedIntro'),
                          style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: palette.mutedInk),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
    );
  }

  Widget _forgetBar(AppPalette palette) {
    return Container(
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
                // B-5: enabled when names + the extra tab's people > 0 (rule people with no names too).
                onPressed: !_anyoneToForget || _busy ? null : _forgetAll,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.error,
                  disabledForegroundColor: palette.mutedInk,
                  side: BorderSide(color: _anyoneToForget ? palette.error : palette.line, width: 1.5),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  widget.extraTab?.forgetAllLabel ?? kForgetAll,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
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
