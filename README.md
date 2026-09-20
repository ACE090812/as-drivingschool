# as-drivingschool

DVLA portal for QBCore: theory test, AI-examiner practical tests, MOT inspections, penalty points and licence replacement. This copy is connected to the government site on **lsgov.co.uk** (`as-browser`), where players see their licence, book and pay for tests, and replace a lost licence.

## What was changed for the website

- **Fees** (`Config.Fees`, whole pounds): theory £25, practical £75 per category, MOT £40, replacement £20. The replacement button in the portal used to charge `2000` while the screen said £20; it now charges the configured fee.
- **Replacement licences** (`Config.Replace`) work like passports: ordered on lsgov.co.uk, paid from the bank, picked locker, ready after `waitSeconds` (30 minutes), then sent to a Postal Prime locker with a pickup code (needs `as-postalprime` with the `createParcel` edit; without it, or with `mode = 'inventory'`, the licence goes to the inventory). An order in progress blocks a second one. If nobody collects the parcel it is sent again. The in-world portal no longer hands out licences; its Replace page points to the website. Each licence item carries a card serial: ordering a replacement (or passing a new practical test) cancels older licence items straight away, so a lost licence cannot be used. New tables/columns: `dvla_replacements` and `dvla_licences.card_serial` (added automatically). Licence items issued before this update have no serial and keep working until the licence is next replaced or a new category is passed.
- **Booking** (`Config.Booking`):
  - `required = true`: a theory or practical test can only be taken after booking and paying on lsgov.co.uk. A booking is used up when the test is taken, pass or fail. The portal shows "Book on lsgov.co.uk" or "BOOKED" on each test. Set `false` to leave tests open to everyone as before (the site still shows the licence).
  - `requirePassport = true`: booking needs a valid passport from `as-passport`. This check is skipped if `as-passport` is not running.
- **Bookings table** `dvla_bookings` is created automatically (also in `sql/dvla.sql`).
- **Practical test start** now asks the server first (`dvla:server:canStartPractical`), so the examiner does not spawn if the player has no booking, the theory test is not passed, or the licence is suspended. The client calls it before spawning.
- **MOT**: booking the MOT in the portal now charges `Config.Fees.mot` (cash first, then bank). Finished inspections are pushed to the vehicle checker on lsgov.co.uk with `exports['as-browser']:setMotResult(plate, passed, expiryUnix, notes)`. This is wrapped in a `pcall`, so nothing breaks if `as-browser` is stopped.
- **Fix**: a failed MOT saved a `nil` expiry date, which made the database insert fail. It now saves an empty string.

- **Portal location and target** (`Config.Portal`): works with ox_target, qb-target, or a plain "Press E" prompt. `target = 'auto'` picks ox_target, then qb-target, and falls back to the prompt if the target export is missing (some qb-target builds have no `AddBoxZone`). The location is `Config.Portal.coords`.

- **Licence card** (`Config.Card`): using the `driver_license` item opens the script's own card (photo, licence number, categories, dates, valid / provisional / suspended / expired) with a "Show to person nearby" button. It is built from the licence record, so it is always current (no need to reissue the item when a category is passed). The mugshot (MugShotBase64) is taken the first time the licence is looked at and kept in `dvla_photos`; a replacement licence clears it so a new one is taken. This replaces `qbx_idcard` for licences: remove the `driver_license` block from `qbx_idcard/config/shared.lua` so it cannot take the item back if it restarts (this script takes the item over a few seconds after it starts).
- **ox_inventory tooltip** now also lists Categories, Issued and Expires.

Changed files: `config.lua`, `fxmanifest.lua`, `server/main.lua`, `client/main.lua`, `html/index.html`, `html/js/app.js`, `sql/dvla.sql`. New files: `html/css/card.css`, `html/js/card.js`.

## Exports (used by as-browser)

```lua
exports['as-drivingschool']:getLicenceSummary(source)      -- licence, points, test history, penalties
exports['as-drivingschool']:getBookingState(source)        -- fees, what can be booked, and why not
exports['as-drivingschool']:bookTest(source, 'theory')     -- or 'practical', 'B'. Paid from the bank. Returns booking or nil, message
exports['as-drivingschool']:replaceLicence(source, { lockerId = '...' })   -- paid from the bank. Returns { fee, readyAt, ... } or nil + reason
```

## Start order

```
ensure oxmysql
ensure qb-core
ensure as-passport      # optional, only for the passport rule
ensure as-postalprime  # for locker delivery
ensure as-browser
ensure as-drivingschool
```

If `as-drivingschool` is stopped the licence pages on lsgov.co.uk say the service is not available. The resource name is set in `sites/gov/config.lua` (`Config.gov.licence.resource`) if you rename the folder.

## Known limitation

The theory test is checked on the client: the questions and answers are sent to the player's game and the client reports the score, so a cheater could send a pass. Bookings still cost money and are used up, but if you need the theory test to be cheat-proof the marking has to move to the server.
