/// §AUTOREAD.PAUSE_NOTICE_BRIDGE - 0.2.2 item 2 (B-PAUSE): the Dart side of the pinned "Auto-record is paused"
/// phone notice. Its own method channel ([kPauseNoticeChannel]), registered by the autoread FeatureHooks.kt and
/// handled by PauseNotice.kt; the auto-read bridge channel (`app.mmogo/autoread`) is not touched.
///
/// Dart passes every word (Kotlin writes none). Every call swallows its failure: a missing notice is never an
/// error the user sees, and the pause itself lives in preferences (lib/autoread/rules/prefs_hard_rule_pause.dart),
/// not in the notice. Autoread flavor only.
library;

import 'package:flutter/services.dart';

/// Kotlin mirror: PauseNotice.CHANNEL.
const String kPauseNoticeChannel = 'app.mmogo/pause_notice';

abstract class PauseNoticeBridge {
  /// Posts (or silently re-posts) the pinned notice. True when Kotlin posted it. Kotlin refuses (and removes an
  /// existing notice) while Read is off, consent or a permission is missing, notifications are blocked, the
  /// stored pause reads as not paused, or Auto-record is not live.
  Future<bool> show({required String title, required String resume, required String channelName});

  /// Removes the notice. Nothing else.
  Future<void> cancel();
}

class MethodChannelPauseNoticeBridge implements PauseNoticeBridge {
  MethodChannelPauseNoticeBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(kPauseNoticeChannel);

  final MethodChannel _channel;

  @override
  Future<bool> show({required String title, required String resume, required String channelName}) async {
    try {
      final r = await _channel.invokeMethod<Object?>('show', {'title': title, 'resume': resume, 'channelName': channelName});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<Object?>('cancel');
    } catch (_) {}
  }
}
