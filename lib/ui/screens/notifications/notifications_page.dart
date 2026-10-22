/// §NOTIF.PAGE — the Notifications page: header with Back, the chip bar with
/// live counts, the list of the chosen chip, empty states and the quiet line.
///
/// Shared by both flavors. Without auto-read (`kAutoReadCompiled == false`)
/// the page is News only: no chip bar, no waiting rows, no auto-read words.
/// Everything auto-read is reached inside `if (kAutoReadCompiled)`. Data comes
/// from the two repository interfaces only (no bridge, no store).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../autoread/autoread_feature.dart';
import '../../../autoread/logic/all_view_logic.dart' as all;
import '../../../autoread/logic/waiting_logic.dart';
import '../../../autoread/model/waiting_item.dart';
import '../../../autoread/model/waiting_repository.dart';
import '../../../autoread/ui/notifications_autoread_copy.dart';
import '../../../autoread/ui/waiting_section.dart';
import '../../../domain/notifications/news_item.dart';
import '../../../domain/notifications/news_logic.dart';
import '../../../domain/notifications/notif_chip.dart';
import '../../../domain/notifications/notifications_repository.dart';
import '../../../app_constants.dart';
import '../../../platform/storage_bridge.dart';
import '../../copy/notifications_copy.dart';
import '../../copy/other_version_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';
import 'news_heading_bar.dart';
import 'news_row.dart';
import 'notif_chip_bar.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.news,
    this.waiting,
    this.initialChip = NotifChip.all,
    this.focusId,
    this.clock,
    this.onBack,
    this.onOpenNews,
    this.onUpdate,
    this.waitingActions = const WaitingActions(),
    this.readingOn = true,
    this.onTurnOnReading,
  });

  final NotificationsRepository news;

  /// The auto-read side. Never read when `kAutoReadCompiled` is false.
  final AutoReadWaitingRepository? waiting;

  /// The chip to open on. A chip that is not available in this flavor opens News.
  final NotifChip initialChip;

  /// A waiting row to scroll to and highlight (autoread build only).
  final String? focusId;

  /// "Now" for ages, expiry and the 30-day read window. Default: the real clock.
  final DateTime Function()? clock;

  /// Back button. Default: `Navigator.maybePop`.
  final VoidCallback? onBack;

  /// A tap on the text part of a news row (the caller decides what opens).
  final void Function(NewsItem item)? onOpenNews;

  /// Update pressed on an update row. Default: `news.completeUpdate(id)`.
  final void Function(NewsItem item)? onUpdate;

  /// Parse, Categorize, Paste, Remove on waiting rows (wired in slice F6;
  /// unwired = no-op). Autoread build only.
  final WaitingActions waitingActions;

  /// Reading M-Pesa messages is on. When off, the quiet line shows (autoread only).
  final bool readingOn;
  final VoidCallback? onTurnOnReading;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late NotifChip _chip;
  bool _readView = false;
  List<NewsItem>? _news;
  List<WaitingItem>? _waiting;
  StreamSubscription<List<NewsItem>>? _newsSub;
  StreamSubscription<List<WaitingItem>>? _waitingSub;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final chips = availableChips(autoReadCompiled: kAutoReadCompiled);
    _chip = chips.contains(widget.initialChip) ? widget.initialChip : NotifChip.news;
    _newsSub = widget.news.watchNews().listen((v) => setState(() => _news = v));
    if (kAutoReadCompiled) {
      _waitingSub = widget.waiting?.watch().listen((v) => setState(() => _waiting = v));
    }
  }

  @override
  void dispose() {
    _newsSub?.cancel();
    _waitingSub?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// The permanent other-version item: opens the mmogo page (a constant) and
  /// counts as read, so the bell never lights for it again.
  Future<void> _seeMore(NewsItem n) async {
    var opened = false;
    try {
      opened = await StorageBridge.instance.openUrl(AppConstants.siteUrl);
    } catch (_) {}
    if (!opened && mounted) _toast(kOtherVersionCouldNotOpen);
    await widget.news.markRead(n.id, _now());
  }

  Widget _newsRow(NewsItem n, DateTime now) => NewsRow(
        n,
        now,
        onOpen: widget.onOpenNews == null ? null : () => widget.onOpenNews!(n),
        onRead: () => n.kind == NewsKind.whatsNew && widget.onOpenNews != null
            ? widget.onOpenNews!(n)
            : widget.news.markRead(n.id, _now()),
        onSeeMore: n.permanent ? () => _seeMore(n) : null,
        onUpdate: () => widget.onUpdate != null ? widget.onUpdate!(n) : widget.news.completeUpdate(n.id),
        onDismiss: () {
          widget.news.remove(n.id);
          _toast(kNewsToastDismissed);
        },
        onRemove: () {
          widget.news.remove(n.id);
          _toast(kNewsToastRemoved);
        },
      );

  List<NotifChipSpec> _specs(DateTime now) {
    final news = _news ?? const <NewsItem>[];
    final specs = <NotifChipSpec>[];
    if (kAutoReadCompiled) {
      final w = _waiting ?? const <WaitingItem>[];
      specs.addAll([
        NotifChipSpec(
            chip: NotifChip.all, label: kChipAll, spokenName: kChipAll, count: all.allCount(w, news, now)),
        NotifChipSpec(
            chip: NotifChip.parse, label: kChipParse, spokenName: kHeadingToParse, count: parseCount(w, now)),
        NotifChipSpec(
            chip: NotifChip.categorize,
            label: kChipCategorize,
            spokenName: kHeadingToCategorize,
            count: categorizeCount(w, now)),
      ]);
    }
    specs.add(NotifChipSpec(
        chip: NotifChip.news, label: kChipNews, spokenName: kChipNews, count: unreadNewsCount(news)));
    return specs;
  }

  List<Widget> _body(DateTime now) {
    final news = _news ?? const <NewsItem>[];
    if (kAutoReadCompiled && _chip != NotifChip.news) {
      return [
        if (!widget.readingOn) _readingOff(),
        WaitingSection(
          chip: _chip,
          waiting: _waiting ?? const <WaitingItem>[],
          news: news,
          now: now,
          newsRowBuilder: (n) => _newsRow(n, now),
          actions: widget.waitingActions,
          focusId: widget.focusId,
        ),
      ];
    }
    final visible = visibleNews(news, now, readView: _readView);
    return [
      if (kAutoReadCompiled && !widget.readingOn) _readingOff(),
      NewsHeadingBar(
        unreadCount: unreadNewsCount(news),
        readView: _readView,
        onChanged: (v) => setState(() => _readView = v),
      ),
      const SizedBox(height: 8),
      if (visible.isEmpty)
        _NewsEmpty(readView: _readView)
      else
        for (final n in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeyedSubtree(key: Key('news-row-${n.id}'), child: _newsRow(n, now)),
          ),
    ];
  }

  Widget _readingOff() {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kReadingOffLine,
              key: const Key('notif-reading-off'),
              style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: p.mutedInk)),
          TextButton(
            onPressed: widget.onTurnOnReading,
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
            child: const Text(kTurnOnReading),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final now = _now();
    final specs = _specs(now);
    void back() => (widget.onBack ?? () => Navigator.maybePop(context))();
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: kNotificationsBackLabel,
                    excludeSemantics: true,
                    onTap: back,
                    child: SizedBox(
                      width: kMinTapTarget,
                      height: kMinTapTarget,
                      child: InkWell(
                        key: const Key('notif-back'),
                        customBorder: const CircleBorder(),
                        onTap: back,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                            child: Icon(Icons.arrow_back, size: 20, color: p.onPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        kNotificationsTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800, color: p.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (specs.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: NotifChipBar(
                  chips: specs,
                  selected: _chip,
                  onSelected: (c) => setState(() {
                    _chip = c;
                    _readView = false;
                  }),
                ),
              ),
            Expanded(
              child: _news == null
                  ? const SizedBox.shrink()
                  : ListView(
                      key: const Key('notif-list'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      children: _body(now),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsEmpty extends StatelessWidget {
  const _NewsEmpty({required this.readView});
  final bool readView;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Semantics(
        container: true,
        child: Column(
          children: [
            Text(readView ? kNewsEmptyReadTitle : kNewsEmptyUnreadTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 4),
            Text(readView ? kNewsEmptyReadBody : kNewsEmptyUnreadBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
          ],
        ),
      ),
    );
  }
}
