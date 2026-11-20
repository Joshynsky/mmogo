import '../../../app_constants.dart';
import '../../../autoread/autoread_feature.dart';

/// The mmogo page opened at the version cards, highlighting the build this
/// phone has. A compile-time choice, so the other URL is folded away.
String updateSiteUrl() => kAutoReadCompiled ? AppConstants.siteOtherUrl : AppConstants.siteStdUrl;
