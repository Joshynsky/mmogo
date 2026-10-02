/// App-wide constants that more than one layer needs.
class AppConstants {
  AppConstants._();

  /// The mmogo site. One of the only two URLs `StorageBridge.openUrl` accepts.
  static const siteUrl = 'https://joshynsky.github.io/mmogo/';

  /// Where feedback goes. The other URL `StorageBridge.openUrl` accepts.
  static const issuesUrl = 'https://github.com/Joshynsky/mmogo/issues';

  /// The exact set the Kotlin side accepts; anything else is refused.
  static const allowedUrls = <String>{siteUrl, issuesUrl};
}
