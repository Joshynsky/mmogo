import 'package:flutter/material.dart';

import '../shell/secondary_scaffold.dart';
import '../theme/app_colors.dart';

/// T25 — reached via the new bell button, immediately left of Profile, in
/// every primary page's top bar (`primary_scaffold.dart`). Nothing is
/// implemented yet: reminders to capture M-Pesa messages, and a countdown
/// before deleted transactions are gone for good, are both planned for
/// v0.2.0 — this is a placeholder page on the two-tier secondary chrome
/// (`SecondaryScaffold(followPalette: true)`, T24), so it already tracks
/// light/dark via the palette.
class NotificationsComingSoonScreen extends StatelessWidget {
  const NotificationsComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Notifications',
      followPalette: true,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.notifications_none_rounded, color: palette.tintInk, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Coming soon',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: palette.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'Reminders to capture your M-Pesa messages, and a countdown before '
                'deleted transactions are gone for good.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: palette.mutedInk, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  'Planned for v0.2.0',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.tintInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
