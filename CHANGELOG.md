# Changelog

What changed in each version of mmogo, newest first. Written for the people who use the app, so it says what you will notice, not how it was built. Dates are when the version was released.

## 0.1.3 (not released)

0.1.3 was a fix-and-verify version. It was built and checked on phones as "mmogo next" but never published as an APK. Everything below is carried into 0.2.0.

### Fixed
- **Bottom bar.** On phones with three-button navigation the bar now sits fully above the system buttons.
- **Paid to now matches Home.** Airtime purchases are counted in "Paid out", so the total agrees with "This month" on Home.
- **Settings.** The Appearance row shows the icon for the mode you picked (phone, sun or moon). The Notifications back arrow lines up with the one in Settings.
- **Recently deleted.** A Settings row restores a transaction you removed, within 1 hour. The "companion web page" row that led nowhere is gone.
- **Privacy page.** It now lists exactly what the version you installed asks for, and says a message waiting to be categorized in the auto-read version also holds the receiver's name and number until you categorize or remove it.
- **Export CSV.** The temporary file made for sharing is removed after you share, and Delete data removes any left over.
- **Wording.** The README and website now say that in the auto-read version a message waiting to be parsed is held on your phone as it arrived, that it keeps only messages from a sender named MPESA (a sender name can be copied), and that "Check for updates now" is the one request made when update checks are off.

### Added
- **Record receiver details.** A Settings switch (Adding entries) controls whether the name, phone and account of who you paid are kept. It is the same choice as the tick on the Add screen.

## 0.1.2 (22 October 2026)

### Added
- **A second version: auto-read.** mmogo auto-read (mmogo-autoread.apk) reads your M-Pesa messages as they arrive and puts them on a waiting list. A notification tells you one is ready; it shows no amount and no name. Tap it to parse the message, then categorize it. Nothing counts in your totals until you categorize it. You can still paste messages as before. It asks for SMS permission and your consent, it is off until you switch it on, and the standard version (mmogo.apk) works without any of it.
- **Notifications.** The bell now opens Notifications, where updates and notices appear and anything new shows on the bell. In the auto-read version your M-Pesa messages wait there too. The Updates page is now in Settings, under About.
- **Withdrawals, airtime and Pochi.** mmogo now understands these M-Pesa messages. Home and Paid to show how many you made and what they cost. A withdrawal adds 0 to what you spent; only its Transaction cost counts toward costs. Airtime bought for another number is read as airtime, and the other number is not kept.
- **Messages with a name but no phone number.** mmogo asks once whether it is Pochi or Send Money, and can remember your answer if you tick the box. Remembered recipients are listed in Settings, where you can forget them, and they are not part of a backup.
- **Weeks.** Home and Analytics group days into calendar weeks, starting on the day you choose in Settings. Past weeks are regrouped to match. No transactions change.
- **Manage categories.** In Settings: create, rename, delete and restore your categories.
- **Delete data.** In Settings, with two levels: delete your transactions, or reset the app to first launch. You type DELETE to confirm, and backup files you saved earlier are not touched.
- **What's new.** A short set of cards about what changed in this version, shown when you first open the app after an update and available later from Notifications and the Updates page.
- **A screen for when mmogo cannot open.** It says so, offers Try again, and lists what to do next.

### Changed
- **Settings is grouped, and has Appearance.** The groups are Look, Adding entries, Your data and About. Appearance is three icons on one row: System, Light or Dark.
- **Restoring with Replace tells you more first.** It shows what would be lost and asks you to confirm. A safety copy is made first and Undo is offered afterwards.
- **Easier to read and tap.** Text size, button sizes, colour contrast of the payment-type labels and screen-reader labels were checked and fixed, and M-Pesa no longer splits across two lines at its hyphen.

### Fixed
- **Same phone number, one person.** Earlier versions counted one number as two people when it was written two ways, for example 0712 345 678 and +254 712 345 678 (07 and 01 numbers alike). We have corrected that: they now count as one person on Paid to, and their totals are added together. The numbers saved on your entries do not change.

### Good to know
- **Backups.** Backups from 0.1.1 still restore. A backup made with 0.1.2 cannot be restored by 0.1.1 or older. Uninstalling mmogo erases your data from this phone. Only a backup you saved can bring it back.
- **Privacy.** No permissions except internet, used only to check for updates (switchable off). The internet is used only to check for updates. GitHub sees your IP address and that the request comes from the mmogo app. No entries, names or messages are sent. The auto-read version also asks for SMS and notification permission, only if you switch reading on, and keeps only messages from a sender named MPESA on your phone. A sender name can be copied by someone else, so a forged message can look genuine; check what mmogo reads before you save it.

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
