# My Money Go

An offline Flutter app (short name `mymog`, Android id `app.mymog`) that turns your M-Pesa messages into a clear picture of where your money goes. Paste a message (or type an entry, or log cash) and the app sorts it, totals it and charts it. Everything stays on your phone.

## What it does

- **Add** an entry by pasting an M-Pesa message: the app reads the amount, receiver, code, date and transaction cost for Send Money, Paybill and Buy Goods. You can also type an entry or log a **cash** payment.
- **Classify** every entry (Groceries, Rent, Fuel, ...). Tick "Always use" to remember a classification for a receiver so the next payment to them is filled in for you. Manage your own list of classifications.
- **Home** shows this month at a glance: total spent, a bar per type (Send Money, Paybill, Buy Goods, Cash), transaction costs and your recent transactions.
- **Analytics** shows spending by day, week, month, year, all time or a custom range, with a chart, a "by type" and "where it went" breakdown, filters, and swipe-to-edit or swipe-to-delete with undo.
- **Paid to** ranks the people, paybills and shops you pay most, with search, filter and sort. Tap one to see every payment to them in Analytics.
- **Recently deleted** keeps deleted entries so you can restore them.
- **Settings** lets you pick a colour palette (Ocean & Sun, Leaf & Gold, Indigo & Peach; light and dark follow your phone) and export your data as CSV through the share sheet.

## Privacy

- Your data is stored in a local SQLite database on the device. There are no accounts and no server.
- The app does **not** read your SMS inbox. You paste the message yourself.
- The release Android manifest requests no permissions. (`INTERNET` appears only in the debug and profile manifests that Flutter's tooling needs.)

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.10.7`).

```
flutter pub get
flutter run                # a connected Android device, or -d windows
flutter analyze
flutter test -j 1          # run the tests one file at a time
```

A debug build fills an empty database with sample entries so you can explore the screens without real messages. Release builds never do this.

## Project layout

```
lib/
  data/        SQLite access: schema, DAOs (transactions, classifications, counterparties, analytics, export) and prefs
  domain/      pure Dart logic: SMS parsing, period maths, counterparty keys, formatting, Paid to grouping
  ui/
    screens/   one folder per busy screen (add/, analytics/, paid_to/, home/) plus the smaller screens
    shell/     the tab bar and page scaffolds
    theme/     palettes (light and dark) and the palette switch
    widgets/   shared widgets (cards, chips, bottom sheet, type icons, pickers)
test/          mirrors lib/
assets/onboarding/   the first-run walkthrough images
```

Each large screen is a small "shell" that owns the state and data loading, with its sections in separate files. Files start with a `§AREA.PIECE` marker in their doc comment so you can search for a section by name.

## Status

Version `0.1.0`, in development. Still to do before a release:

- launcher icon (still the default Flutter one);
- release signing key;
- choose a licence.

## Tests

The suite covers the SMS parser, the period and grouping logic, every DAO against an in-memory SQLite database, and the screens as widget tests (light and dark). `flutter analyze` is kept clean.
