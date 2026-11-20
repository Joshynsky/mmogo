/// The Settings areas a What's new link can open and outline (0.2.1 #10). The id travels in
/// `HighlightRequest`; Settings wraps the area in a `HighlightPulse` that is active for its id.
library;

/// The "Record receiver details" switch (Adding entries).
const kSettingsTargetCaptureReceiver = 'settings.captureReceiver';

/// The "Remembered" row (Adding entries): where the auto-record airtime switches now are.
const kSettingsTargetRemembered = 'settings.remembered';

/// The Reading section (auto-read build only): where the Read switch and its status are.
const kSettingsTargetReading = 'settings.reading';
