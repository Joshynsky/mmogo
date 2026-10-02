/// B31: which app versions have a bundled What's-new text. Add a version here
/// (and its copy) when a release has something to tell; a version not listed
/// never shows the modal.
const _versionsWithContent = {'0.1.1'};

bool hasWhatsNewContentFor(String versionName) => _versionsWithContent.contains(versionName);
