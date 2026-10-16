/// B31: which app versions have a bundled What's-new pager. Add a version here
/// (and its copy) when a release has something to tell; a version not listed
/// never shows the pop-up. 0.1.2 S11a: the 0.1.1 text was retired (it is no
/// longer true), so only 0.1.2 is listed.
const _versionsWithContent = {'0.1.2'};

bool hasWhatsNewContentFor(String versionName) => _versionsWithContent.contains(versionName);
