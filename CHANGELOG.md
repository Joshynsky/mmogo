# Changelog

What changed in each version of mmogo, newest first. Written for the people who use the app, so it says what you will notice, not how it was built. Dates are when the version was released.

## 0.1.1 (2 October 2026)

### Added
- **Backup and restore.** Profile, Settings, Backup and restore. Save your data to a file you keep, and restore it later on this phone or a new one. Restore can merge the file into what is on the phone, or replace everything on the phone with the file (a safety copy is made first, and Undo is offered).
- **Auto-backup to a folder you pick.** After every few saved entries (you choose how many) mmogo saves a new backup file there and keeps the newest few (you choose how many). If the folder stops working, auto-backup pauses and tells you.
- **Update check.** When you open the app, at most once a week, mmogo asks GitHub whether a newer version exists. You can switch this off on the Updates page. This is why mmogo now asks Android for the internet permission, and it is the only thing the internet is used for.
- **Updates page and notices.** News from mmogo shows on the Updates page, with a dot on the bell on Home. There are no Android notifications.
- **Privacy and your data.** A page that says what is stored on your phone and what leaves it.
- **Send feedback.** A row in Settings that opens the mmogo issues page on GitHub.
- **What's new message.** A short note the first time you open the app after an update.
- **Welcome note** on a first install, saying that update checks are on and how to turn them off.

### Changed
- **Profile is now in the bottom bar**, and Settings opens from it. Help and tips moved into Profile.
- Dialog boxes now follow your phone's dark mode and your chosen colours.
- Names, phone numbers and accounts you type now stop at a sensible length.

### Fixed
- Paybill messages whose account has spaces in it (for example data bundle purchases to SAFARICOM DATA BUNDLES) are now read correctly.

### Good to know
- A backup file is **not encrypted**. It holds your transactions, including names and phone numbers, so keep it somewhere private.
- Uninstalling mmogo erases its data. Android's phone-to-phone transfer does not carry it either. A backup file is the way to move to a new phone.
- Some M-Pesa messages are not understood yet: Pochi la Biashara payments, agent withdrawals and airtime purchases. You can still add them by hand.

## 0.1.0 (1 October 2026)

First public version.

- Add an entry by pasting an M-Pesa message (Send Money, Paybill and Buy Goods are read for you), by typing it, or as a cash payment. You check every entry before it is saved.
- Categories for your spending, your own included, with "Always use" to fill in repeat payments.
- Home, Analytics and Paid to to see where the money went.
- Edit and delete with Undo, and Recently deleted.
- Export CSV, three colour palettes, and a short guide on each page.
- Your entries stay on your phone. (0.1.1 adds one thing that leaves it: the update check.)
