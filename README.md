# mmogo

An offline Android app that turns your M-Pesa messages into a clear picture of where your money goes. Paste a message (or type an entry, or log cash) and mmogo sorts it, totals it and charts it. Everything stays on your phone: no account, no server, no tracking.

mmogo is an independent project. It is not made by, or connected to, Safaricom or M-Pesa.

Built with Flutter. Android only for now (Android id `io.github.joshynsky.mmogo`).

## What it does

- **First run**: a short Welcome, then a four-step walkthrough with screenshots. You can skip it and enter your name for the Home greeting.
- **Add** an entry by tapping **Parse M-Pesa message** and pasting the SMS: mmogo reads the amount, receiver, code, date and transaction cost for Send Money, Paybill and Buy Goods, and fills the form in. You check it before it is saved. You can also type an entry yourself, or log a **cash** payment.
- **Classify** every entry (Groceries, Rent, Transport, ...). Tick "Always use" to remember a classification for a receiver, so the next payment to them is filled in for you. Turn on "Auto-recognize classifications" in Settings to get a suggestion for repeat receivers. Manage your own list (create, rename, delete, restore) per type.
- **Home** shows this month at a glance (or Today, This week and more): total spent, how it compares with the last period, a bar per type (Send Money, Paybill, Buy Goods, Cash), transaction costs and your recent transactions. Tap a transaction to see its day in Analytics.
- **Analytics** shows spending by day, week, month, year, all time or a custom range, with a chart you can tap and swipe, a "by type" and "where it went" breakdown with tap-to-filter chips, and a transaction list. Swipe a row right to edit it, left to delete it (with Undo).
- **Paid to** ranks the people, paybills and shops you pay most, with search, filter and sort. Tap one to see every payment to them in Analytics.
- **Recently deleted** keeps deleted entries so you can restore them.
- **Settings** lets you pick a colour palette (Ocean & Sun, Leaf & Gold, Indigo & Peach; light and dark follow your phone), manage classifications, restore deleted entries, replay the tips, and **export your data as CSV** through the share sheet.
- **Profile** holds your name (used in the Home greeting), a summary of the data stored on the device, and the app version.
- **Tips**: each page has a short guided tour the first time you open it ("1 of 4", Next, Back, Skip). Tap the **?** at the top of any page to replay it, or use Settings > Show tips again.

## Privacy

- Your data is stored in a local SQLite database on the device. There are no accounts and no server.
- mmogo does **not** read your SMS inbox. You paste the message yourself.
- The release app requests **no permissions** (not even internet). `INTERNET` appears only in the debug and profile manifests that Flutter's tooling needs.
- Android auto-backup is switched **off**, so your data is not copied to Google Drive. The flip side: there is no automatic restore on a new phone, and uninstalling the app erases your data. Use **Export CSV** to keep a copy. Backup and import are planned for a later version.

## Install (Android)

Download `mmogo.apk` from the latest GitHub Release, open it on your phone and allow "Install unknown apps" for your browser or file manager when Android asks. Play Protect may show a warning for apps that are not from the Play Store; this is expected for a directly shared APK. To check your download, compare its SHA-256 with the value published next to the release:

```
sha256sum mmogo.apk        # Linux / macOS / Git Bash
certutil -hashfile mmogo.apk SHA256     # Windows
```

## Run it from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.10.7`).

```
flutter pub get
flutter run                # a connected Android device, or -d windows
flutter analyze
flutter test -j 1          # run the tests one file at a time
```

A debug build fills an empty database with sample entries so you can explore the screens without real messages. Release builds never do this.

## Releasing

Release builds are signed with a private key that lives **outside** this repository.

1. Create a keystore once (`keytool -genkeypair ... -alias mmogo`) and keep the file and its passwords somewhere safe, with a backup in a second place. If the key is lost, installed apps can never be updated.
2. Create `android/key.properties` (gitignored) with `storePassword`, `keyPassword`, `keyAlias` and `storeFile` (the path to the keystore).
3. Bump `version:` in `pubspec.yaml` and `AppInfo.version` in `lib/app_info.dart` together (a test fails if they drift).
4. `flutter build apk --release`, then name the result `mmogo.apk` and publish its SHA-256 next to it.

Without `android/key.properties` a release build is left unsigned; it never falls back to the debug key.

## Project layout

```
lib/
  data/        SQLite access: schema, DAOs (transactions, classifications, counterparties, analytics, export) and prefs
  domain/      pure Dart logic: SMS parsing, period maths, counterparty keys, formatting, Paid to grouping
  ui/
    screens/   one folder per busy screen (add/, analytics/, paid_to/, home/) plus the smaller screens
    shell/     the tab bar and page scaffolds
    theme/     palettes (light and dark) and the palette switch
    widgets/   shared widgets (cards, chips, bottom sheet, the guided-tour overlay, pickers)
test/          mirrors lib/
assets/        onboarding walkthrough images and the app icon
brand/         icon sources and the script that builds them
```

Each large screen is a small "shell" that owns the state and data loading, with its sections in separate files. Files start with a `§AREA.PIECE` marker in their doc comment so you can search for a section by name.

## Status

Version `0.1.0`, preparing its first release. Still to do: publish the signed APK. Licensed under the [MIT License](LICENSE).

Planned for later: Profile in the bottom bar with Settings inside it, backup and import, money-in tracking, and a lighter Add form.

## Tests

The suite covers the SMS parser, the period and grouping logic, every DAO against an in-memory SQLite database, and the screens as widget tests (light and dark). `flutter analyze` is kept clean.
