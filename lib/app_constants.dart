/// App-wide constants that more than one layer needs.
class AppConstants {
  AppConstants._();

  /// The mmogo site. One of the only two URLs `StorageBridge.openUrl` accepts.
  static const siteUrl = 'https://joshynsky.github.io/mmogo/';

  /// Where feedback goes. The other URL `StorageBridge.openUrl` accepts.
  static const issuesUrl = 'https://github.com/Joshynsky/mmogo/issues';

  /// The site opened at the version cards, highlighting the standard build.
  static const siteStdUrl = '$siteUrl?build=std#versions';

  /// The same, highlighting the other build.
  static const siteOtherUrl = '$siteUrl?build=auto#versions';

  /// The page name of the auto-read install guide, beside [siteUrl].
  static const installHelpPage = 'install-auto-read.html';

  /// The auto-read install guide (the install-help notice's button).
  static const installHelpUrl = '$siteUrl$installHelpPage';

  /// The exact set the Kotlin side accepts; anything else is refused.
  static const allowedUrls = <String>{siteUrl, issuesUrl, siteStdUrl, siteOtherUrl, installHelpUrl};
}
