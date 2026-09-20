local QBCore = exports['qb-core']:GetCoreObject()

-- oxmysql can return TINYINT(1) columns as true/false or 1/0 depending on version, so never compare with == 1.
local function flag(v) return v == true or v == 1 or v == '1' end

-- In-memory queues (reset on resource restart)
local pendingMOT = {}

-- ──────────────────────────────────────────────────────────────────────────────
--  HELPERS
-- ──────────────────────────────────────────────────────────────────────────────

local function getDate()
    return os.date('%d/%m/%Y')
end

local function getDateTime()
    return os.date('%d/%m/%Y %H:%M')
end

local function hasJob(jobName, jobList)
    for _, v in ipairs(jobList) do
        if v == jobName then return true end
    end
    return false
end

local function notifyOnlinePlayers(jobList, msg, msgType)
    local players = QBCore.Functions.GetPlayers()
    for _, playerId in ipairs(players) do
        local p = QBCore.Functions.GetPlayer(playerId)
        if p and hasJob(p.PlayerData.job.name, jobList) then
            TriggerClientEvent('QBCore:Notify', playerId, msg, msgType or 'primary')
        end
    end
end

local function notifyByCitizenId(citizenid, msg, msgType)
    local players = QBCore.Functions.GetPlayers()
    for _, playerId in ipairs(players) do
        local p = QBCore.Functions.GetPlayer(playerId)
        if p and p.PlayerData.citizenid == citizenid then
            TriggerClientEvent('QBCore:Notify', playerId, msg, msgType or 'primary')
            return
        end
    end
end

local function initPlayer(citizenid)
    local existing = MySQL.query.await('SELECT id FROM dvla_licences WHERE citizenid = ?', { citizenid })
    if #existing == 0 then
        MySQL.insert.await(
            'INSERT INTO dvla_licences (citizenid, licence_type, theory_passed, practical_passed, penalty_points, suspended, issue_date) VALUES (?,?,0,0,0,0,?)',
            { citizenid, 'none', getDate() }
        )
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
--  FEES, BOOKINGS AND THE lsgov.co.uk SITE  (added for as-browser / as-passport)
--  Tests are booked and paid for on the website. A booking is spent when the test is taken.
--  Exports at the bottom of this file are used by the government site in as-browser.
-- ──────────────────────────────────────────────────────────────────────────────

Config.Fees    = Config.Fees    or { theory = 25, practical = 75, mot = 40, replace = 20 }
Config.Booking = Config.Booking or { required = true, requirePassport = true }

Config.Card = Config.Card or { photo = true, authority = 'DVLA', validYears = 10, nationality = 'British', showDistance = 3.0 }

local function bookingRequired() return Config.Booking.required == true end

local function heldCategories(lic)
    local held = {}
    for cat in tostring((lic and lic.categories) or '[]'):gmatch('"([^"]+)"') do held[cat] = true end
    return held
end

local function heldList(lic)
    local list = {}
    for cat in tostring((lic and lic.categories) or '[]'):gmatch('"([^"]+)"') do list[#list + 1] = cat end
    return list
end

local function findCategory(label)
    for _, cat in ipairs(Config.Categories) do
        if cat.label == label then return cat end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
--  CARD SERIALS, POSTAL PRIME AND PHONE HELPERS (used by licence replacement)
-- ──────────────────────────────────────────────────────────────────────────────

Config.Replace = Config.Replace or {
    mode = 'locker', waitSeconds = 1800, prepSeconds = 180, expireSeconds = 172800,
    sender = 'DVLA', mailFrom = { name = 'DVLA', email = 'noreply@lsgov.co.uk' },
}

pcall(function() math.randomseed(os.time() + (GetGameTimer and GetGameTimer() or 0)) end)

local function newSerial()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local t = {}
    for i = 1, 10 do local n = math.random(#chars); t[i] = chars:sub(n, n) end
    return table.concat(t)
end

--- Gives the licence a new card serial. Licence items carrying an older serial stop opening.
local function issueSerial(citizenid)
    local serial = newSerial()
    MySQL.update.await('UPDATE dvla_licences SET card_serial = ? WHERE citizenid = ?', { serial, citizenid })
    return serial
end

local function postalReady() return GetResourceState('as-postalprime') == 'started' end

local function lockers()
    if not postalReady() then return {} end
    local ok, list = pcall(function() return exports['as-postalprime']:getLockers() end)
    return ok and type(list) == 'table' and list or {}
end

local function lockerLabel(id)
    for _, l in ipairs(lockers()) do if l.id == id then return l.label end end
    return nil
end

local warnedLockers = false
--- 'locker' when Postal Prime is running with at least one locker, otherwise 'inventory'.
local function deliveryMode()
    if Config.Replace.mode == 'locker' and postalReady() then
        if #lockers() > 0 then return 'locker' end
        if not warnedLockers then
            warnedLockers = true
            print('^3[DVLA] ^7as-postalprime returned no lockers. Restart as-postalprime (it needs the createParcel edit). Replacement licences go to the inventory until then.')
        end
    end
    return 'inventory'
end

local function findSource(citizenid)
    local ok, p = pcall(function() return QBCore.Functions.GetPlayerByCitizenId(citizenid) end)
    return ok and p and p.PlayerData and p.PlayerData.source or nil
end

local function phoneNotify(source, title, body)
    if not source then return end
    pcall(function()
        exports['sd-phone']:notify(source, { app = 'as-browser', appId = 'as-browser', title = title, body = body, time = 'now' })
    end)
end

local function phoneMail(source, citizenid, subject, body)
    pcall(function()
        local email
        if source then
            local live = exports['sd-phone']:getMailAccounts(source)
            if type(live) == 'table' and live[1] then email = live[1].email end
        end
        if not email and citizenid then
            local saved = exports['sd-phone']:getMailAddresses(citizenid)
            if type(saved) == 'table' and saved[1] then email = saved[1].email end
        end
        if not email then return end
        local from = Config.Replace.mailFrom
        for _, sender in ipairs({ from, { name = from and from.name or 'DVLA' }, false }) do
            local mail = { to = email, subject = subject, body = body }
            if sender then mail.from = sender end
            local res = exports['sd-phone']:sendMail(mail)
            if type(res) == 'table' and res.delivered and res.delivered > 0 then return end
        end
    end)
end

local function pendingReplacement(citizenid)
    return MySQL.single.await(
        "SELECT * FROM dvla_replacements WHERE citizenid = ? AND status = 'processing' ORDER BY id DESC LIMIT 1", { citizenid })
end

--- Takes a fee. bankOnly = false takes cash first, then bank. Returns true when it was taken.
local function charge(Player, amount, reason, bankOnly)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local cash = bankOnly and 0 or (Player.Functions.GetMoney('cash') or 0)
    local bank = Player.Functions.GetMoney('bank') or 0
    if cash + bank < amount then return false end
    local fromCash = math.min(cash, amount)
    if fromCash > 0 then Player.Functions.RemoveMoney('cash', fromCash, reason) end
    if amount - fromCash > 0 then Player.Functions.RemoveMoney('bank', amount - fromCash, reason) end
    return true
end

--- Returns a message when the player may not book a test because of their passport, or nil.
local function passportProblem(source)
    if not Config.Booking.requirePassport then return nil end
    if GetResourceState('as-passport') ~= 'started' then return nil end
    local ok, valid = pcall(function() return exports['as-passport']:hasValidPassport(source) end)
    if not ok or valid then return nil end
    return 'You need a valid passport to book a driving test. Apply for one on lsgov.co.uk.'
end

local function unusedCount(citizenid, kind, category)
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM dvla_bookings WHERE citizenid = ? AND kind = ? AND category = ? AND used_at IS NULL',
        { citizenid, kind, category or '' })) or 0
end

--- Spends one booking. Returns true when there was one.
local function consumeBooking(citizenid, kind, category)
    local n = MySQL.update.await(
        'UPDATE dvla_bookings SET used_at = ? WHERE citizenid = ? AND kind = ? AND category = ? AND used_at IS NULL ORDER BY id LIMIT 1',
        { os.time(), citizenid, kind, category or '' })
    return n ~= nil and n > 0
end

--- Everything the booking pages need: fees, what can be booked, and why not.
local function bookingState(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, 'You are not signed in.' end
    local cid = Player.PlayerData.citizenid
    initPlayer(cid)
    local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { cid })
    local held = heldCategories(lic)
    local suspended = flag(lic.suspended) or lic.licence_type == 'suspended'
    local passportMsg = passportProblem(source)
    local theoryPassed = flag(lic.theory_passed)

    local function blocked()
        if suspended then return 'Your licence is suspended.' end
        return passportMsg
    end

    local theory = { fee = Config.Fees.theory, booked = unusedCount(cid, 'theory', ''), passed = theoryPassed }
    theory.canBook, theory.reason = true, nil
    local why = blocked()
    if why then theory.canBook, theory.reason = false, why
    elseif theoryPassed then theory.canBook, theory.reason = false, 'You have already passed your theory test.'
    elseif theory.booked > 0 then theory.canBook, theory.reason = false, 'You already have a theory test booked.' end

    local practical = {}
    for _, cat in ipairs(Config.Categories) do
        local e = {
            label = cat.label, name = cat.name, description = cat.description, icon = cat.icon,
            requires = cat.requires or {}, fee = Config.Fees.practical, held = held[cat.label] == true,
            booked = unusedCount(cid, 'practical', cat.label), canBook = true,
        }
        local missing
        for _, req in ipairs(e.requires) do if not held[req] then missing = req break end end
        if why then e.canBook, e.reason = false, why
        elseif e.held then e.canBook, e.reason = false, 'You already hold this category.'
        elseif not theoryPassed then e.canBook, e.reason = false, 'Pass your theory test first.'
        elseif missing then e.canBook, e.reason = false, ('You must hold category %s first.'):format(missing)
        elseif e.booked > 0 then e.canBook, e.reason = false, 'You already have this test booked.' end
        practical[#practical + 1] = e
    end

    return {
        required = bookingRequired(), fees = Config.Fees, centre = Config.PracticalTest.centre,
        passportOk = passportMsg == nil, passportMessage = passportMsg, suspended = suspended,
        theoryPassed = theoryPassed, theory = theory, practical = practical,
    }
end

local bookingBusy = {}

--- Books and pays for a test. kind = 'theory' or 'practical' (with a category label).
--- Returns { kind, category, label, price } or nil, message.
local function bookTest(source, kind, category)
    if bookingBusy[source] then return nil, 'Please wait, your last request is still being processed.' end
    bookingBusy[source] = true
    local ok, res, err = pcall(function()
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return nil, 'You are not signed in.' end
        local state, why = bookingState(source)
        if not state then return nil, why end

        local entry, label, price
        if kind == 'theory' then
            entry, label, price, category = state.theory, 'Theory test', Config.Fees.theory, ''
        elseif kind == 'practical' then
            for _, e in ipairs(state.practical) do if e.label == category then entry = e end end
            if not entry then return nil, 'Choose a licence category.' end
            label, price = ('Practical test - category %s'):format(category), Config.Fees.practical
        else
            return nil, 'Choose a test to book.'
        end
        if not entry.canBook then return nil, entry.reason or 'You cannot book this test.' end

        if not charge(Player, price, 'dvla-' .. kind .. '-test', true) then
            return nil, 'You do not have enough money in your bank account.'
        end
        local inserted = pcall(function()
            MySQL.insert.await(
                'INSERT INTO dvla_bookings (citizenid, kind, category, price, booked_at) VALUES (?,?,?,?,?)',
                { Player.PlayerData.citizenid, kind, category or '', price, os.time() })
        end)
        if not inserted then
            Player.Functions.AddMoney('bank', price, 'dvla-booking-refund')
            return nil, 'We could not book your test. You have not been charged, please try again.'
        end
        return { kind = kind, category = category or '', label = label, price = price }
    end)
    bookingBusy[source] = nil
    if not ok then print('^1[DVLA] ^7booking failed: ' .. tostring(res)); return nil, 'Something went wrong. Please try again.' end
    return res, err
end

--- The licence as the website shows it.
local function licenceSummary(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, 'You are not signed in.' end
    local cid = Player.PlayerData.citizenid
    initPlayer(cid)
    local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { cid })
    local theory = MySQL.query.await('SELECT score, max_score, passed, date FROM dvla_theory_tests WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { cid }) or {}
    local practical = MySQL.query.await('SELECT category, centre, minor_faults, major_faults, passed, date FROM dvla_practical_tests WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { cid }) or {}
    local penalties = MySQL.query.await('SELECT offence, points, issued_by, date FROM dvla_penalty_points WHERE citizenid = ? ORDER BY id DESC LIMIT 30', { cid }) or {}

    local out = {
        type = lic.licence_type, categories = heldList(lic), theoryPassed = flag(lic.theory_passed),
        practicalPassed = flag(lic.practical_passed), issueDate = lic.issue_date,
        points = tonumber(lic.penalty_points) or 0, maxPoints = Config.PenaltyPoints.maxPoints,
        suspended = flag(lic.suspended) or lic.licence_type == 'suspended',
        replaceFee = Config.Fees.replace, canReplace = false,
        theoryTests = {}, practicalTests = {}, penalties = {},
    }
    do
        local pending = pendingReplacement(cid)
        local mode = deliveryMode()
        local reason
        if not flag(lic.practical_passed) then reason = 'You need to pass a practical test first.'
        elseif pending then reason = 'You already have a replacement licence on its way.' end
        out.canReplace = reason == nil
        out.replace = {
            fee = Config.Fees.replace, canReplace = reason == nil, reason = reason, mode = mode,
            lockers = mode == 'locker' and lockers() or {}, waitSeconds = Config.Replace.waitSeconds,
            pending = pending and {
                readyAt = pending.ready_at, appliedAt = pending.applied_at,
                lockerLabel = pending.locker_id ~= '' and lockerLabel(pending.locker_id) or nil,
                late = pending.ready_at <= os.time(),
            } or nil,
        }
    end
    for i, t in ipairs(theory) do out.theoryTests[i] = { score = t.score, max = t.max_score, passed = flag(t.passed), date = t.date } end
    for i, t in ipairs(practical) do
        out.practicalTests[i] = { category = t.category, minor = t.minor_faults, major = t.major_faults, passed = flag(t.passed), date = t.date, centre = t.centre }
    end
    for i, t in ipairs(penalties) do out.penalties[i] = { offence = t.offence, points = t.points, by = t.issued_by, date = t.date } end
    return out
end

-- ──────────────────────────────────────────────────────────────────────────────
--  AUTO-EXECUTE SQL ON FIRST RUN
-- ──────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_licences` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `licence_type` VARCHAR(20) NOT NULL DEFAULT 'none',
            `theory_passed` TINYINT(1) NOT NULL DEFAULT 0,
            `practical_passed` TINYINT(1) NOT NULL DEFAULT 0,
            `issue_date` VARCHAR(20) DEFAULT NULL,
            `penalty_points` INT(11) NOT NULL DEFAULT 0,
            `suspended` TINYINT(1) NOT NULL DEFAULT 0,
            `categories` TEXT DEFAULT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- Add categories column to existing tables (safe on re-run)
    MySQL.query.await([[
        ALTER TABLE `dvla_licences` ADD COLUMN IF NOT EXISTS `categories` TEXT DEFAULT NULL
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_theory_tests` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `score` INT(11) NOT NULL,
            `max_score` INT(11) NOT NULL DEFAULT 15,
            `passed` TINYINT(1) NOT NULL,
            `date` VARCHAR(30) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_practical_tests` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `centre` VARCHAR(100) DEFAULT NULL,
            `minor_faults` INT(11) NOT NULL DEFAULT 0,
            `major_faults` INT(11) NOT NULL DEFAULT 0,
            `passed` TINYINT(1) NOT NULL,
            `examiner` VARCHAR(100) DEFAULT NULL,
            `category` VARCHAR(10) DEFAULT 'B',
            `date` VARCHAR(30) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        ALTER TABLE `dvla_practical_tests` ADD COLUMN IF NOT EXISTS `category` VARCHAR(10) DEFAULT 'B'
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_mot_tests` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `plate` VARCHAR(20) NOT NULL,
            `passed` TINYINT(1) NOT NULL,
            `inspector` VARCHAR(100) DEFAULT NULL,
            `notes` TEXT DEFAULT NULL,
            `expiry_date` VARCHAR(30) DEFAULT NULL,
            `date` VARCHAR(30) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `plate` (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_penalty_points` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `offence` VARCHAR(200) NOT NULL,
            `points` INT(11) NOT NULL,
            `issued_by` VARCHAR(100) DEFAULT NULL,
            `date` VARCHAR(30) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_bookings` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `kind` VARCHAR(16) NOT NULL,
            `category` VARCHAR(10) NOT NULL DEFAULT '',
            `price` INT(11) NOT NULL DEFAULT 0,
            `booked_at` INT(11) NOT NULL,
            `used_at` INT(11) DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `lookup` (`citizenid`, `kind`, `category`, `used_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_photos` (
            `citizenid` VARCHAR(50) NOT NULL,
            `photo` MEDIUMTEXT NOT NULL,
            `updated` INT(11) NOT NULL,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        ALTER TABLE `dvla_licences` ADD COLUMN IF NOT EXISTS `card_serial` VARCHAR(20) DEFAULT NULL
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `dvla_replacements` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `ref` VARCHAR(20) NOT NULL,
            `citizenid` VARCHAR(50) NOT NULL,
            `locker_id` VARCHAR(64) NOT NULL DEFAULT '',
            `status` VARCHAR(16) NOT NULL DEFAULT 'processing',
            `fee` INT(11) NOT NULL DEFAULT 0,
            `info` TEXT DEFAULT NULL,
            `applied_at` INT(11) NOT NULL,
            `ready_at` INT(11) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `ref` (`ref`),
            KEY `owner` (`citizenid`, `status`),
            KEY `ready` (`status`, `ready_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    print('^2[DVLA] ^7Database tables ready.')
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: GET ALL DATA
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:getData', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end

    local citizenid = Player.PlayerData.citizenid
    initPlayer(citizenid)

    local licence       = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
    local theoryTests   = MySQL.query.await('SELECT * FROM dvla_theory_tests WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { citizenid })
    local practicalTests= MySQL.query.await('SELECT * FROM dvla_practical_tests WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { citizenid })
    local penalties     = MySQL.query.await('SELECT * FROM dvla_penalty_points WHERE citizenid = ? ORDER BY id DESC', { citizenid })

    local job            = Player.PlayerData.job.name
    local isMOTInspector = hasJob(job, Config.MOTInspectorJobs)

    -- Build a safe categories list to send to the NUI (strip checkpoints to keep payload small)
    local categoriesForUI = {}
    for _, cat in ipairs(Config.Categories) do
        table.insert(categoriesForUI, {
            label       = cat.label,
            name        = cat.name,
            description = cat.description,
            icon        = cat.icon,
            requires    = cat.requires,
        })
    end

    local bookings = { theory = unusedCount(citizenid, 'theory', ''), practical = {} }
    for _, cat in ipairs(Config.Categories) do bookings.practical[cat.label] = unusedCount(citizenid, 'practical', cat.label) end

    cb({
        bookingRequired = bookingRequired(),
        bookings       = bookings,
        fees           = Config.Fees,
        licence        = licence[1],
        theoryTests    = theoryTests,
        practicalTests = practicalTests,
        penalties      = penalties,
        playerName     = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        job            = job,
        isMOTInspector = isMOTInspector,
        pendingMOT     = isMOTInspector and pendingMOT or {},
        categories     = categoriesForUI,
    })
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: SUBMIT THEORY TEST
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:submitTheory', function(source, cb, score, passed)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({ success = false }) end

    local citizenid = Player.PlayerData.citizenid

    -- A theory test has to be booked (and paid for) on lsgov.co.uk first. The booking is spent here.
    if bookingRequired() and not consumeBooking(citizenid, 'theory', '') then
        return cb({ success = false, reason = 'You need to book your theory test on lsgov.co.uk first.' })
    end

    MySQL.insert.await(
        'INSERT INTO dvla_theory_tests (citizenid, score, max_score, passed, date) VALUES (?,?,?,?,?)',
        { citizenid, score, Config.TheoryTest.totalQuestions, passed and 1 or 0, getDateTime() }
    )

    if passed then
        MySQL.update.await('UPDATE dvla_licences SET theory_passed = 1 WHERE citizenid = ?', { citizenid })
        -- Upgrade to provisional if still 'none'
        MySQL.update.await(
            "UPDATE dvla_licences SET licence_type = 'provisional' WHERE citizenid = ? AND licence_type = 'none'",
            { citizenid }
        )
        -- If practical also done, issue full licence
        local lic = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
        if lic[1] and flag(lic[1].practical_passed) then
            MySQL.update.await(
                "UPDATE dvla_licences SET licence_type = 'full', issue_date = ? WHERE citizenid = ?",
                { getDate(), citizenid }
            )
        end
        TriggerClientEvent('QBCore:Notify', source, 'Theory Test Passed! Score: ' .. score .. '/' .. Config.TheoryTest.totalQuestions, 'success')
    else
        TriggerClientEvent('QBCore:Notify', source, 'Theory Test Failed. Score: ' .. score .. '/' .. Config.TheoryTest.totalQuestions .. '. Pass mark: ' .. Config.TheoryTest.passMark, 'error')
    end

    local updatedTests = MySQL.query.await('SELECT * FROM dvla_theory_tests WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { citizenid })
    local updatedLic   = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })

    cb({ success = true, passed = passed, score = score, theoryTests = updatedTests, licence = updatedLic[1] })
end)



-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: BOOK MOT
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:bookMOT', function(source, cb, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({ success = false }) end

    if not plate or plate == '' then
        return cb({ success = false, reason = 'No vehicle plate provided.' })
    end

    local citizenid = Player.PlayerData.citizenid
    local name      = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

    -- Already in queue
    for _, v in ipairs(pendingMOT) do
        if v.plate == plate then
            return cb({ success = false, reason = 'This vehicle is already in the MOT queue.' })
        end
    end

    -- MOT fee (cash first, then bank)
    if not charge(Player, Config.Fees.mot, 'dvla-mot-fee', false) then
        return cb({ success = false, reason = ('You need %s%d to book an MOT.'):format('£', Config.Fees.mot or 0) })
    end

    table.insert(pendingMOT, {
        citizenid = citizenid,
        name      = name,
        plate     = plate,
        source    = source,
        bookedAt  = getDateTime(),
    })

    notifyOnlinePlayers(Config.MOTInspectorJobs, 'New MOT booking: ' .. plate .. ' — Owner: ' .. name, 'primary')
    TriggerClientEvent('QBCore:Notify', source, 'MOT booked for ' .. plate .. '. An inspector has been notified.', 'success')
    if (Config.Fees.mot or 0) > 0 then
        TriggerClientEvent('QBCore:Notify', source, ('MOT fee of £%d paid.'):format(Config.Fees.mot), 'primary')
    end

    cb({ success = true, pendingMOT = pendingMOT })
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: GET PENDING MOT (Inspector refresh)
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:getPendingMOT', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    if not hasJob(Player.PlayerData.job.name, Config.MOTInspectorJobs) then return cb({}) end
    cb(pendingMOT)
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: COMPLETE MOT INSPECTION
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:completeMOT', function(source, cb, citizenid, plate, passed, notes)
    local Inspector = QBCore.Functions.GetPlayer(source)
    if not Inspector then return cb({ success = false }) end
    if not hasJob(Inspector.PlayerData.job.name, Config.MOTInspectorJobs) then
        return cb({ success = false, reason = 'You are not an authorised MOT inspector.' })
    end

    local inspectorName = Inspector.PlayerData.charinfo.firstname .. ' ' .. Inspector.PlayerData.charinfo.lastname

    -- Remove from queue
    for i, v in ipairs(pendingMOT) do
        if v.plate == plate then table.remove(pendingMOT, i) break end
    end

    local expiryDate = nil
    if passed then
        expiryDate = os.date('%d/%m/%Y', os.time() + (Config.MOTTest.validityMonths * 30 * 24 * 3600))
    end

    MySQL.insert.await(
        'INSERT INTO dvla_mot_tests (citizenid, plate, passed, inspector, notes, expiry_date, date) VALUES (?,?,?,?,?,?,?)',
        { citizenid, plate, passed and 1 or 0, inspectorName, notes or '', expiryDate or '', getDateTime() }
    )

    -- Tell the government site (as-browser), so the vehicle checker shows the MOT.
    if GetResourceState('as-browser') == 'started' then
        local expiryUnix = passed and (os.time() + (Config.MOTTest.validityMonths * 30 * 24 * 3600)) or nil
        pcall(function() exports['as-browser']:setMotResult(plate, passed and true or false, expiryUnix, notes or '') end)
    end

    if passed then
        notifyByCitizenId(citizenid, 'MOT PASSED for ' .. plate .. '. Valid until: ' .. expiryDate, 'success')
    else
        notifyByCitizenId(citizenid, 'MOT FAILED for ' .. plate .. '. Reason: ' .. (notes ~= '' and notes or 'No reason provided'), 'error')
    end

    TriggerClientEvent('QBCore:Notify', source, 'MOT inspection result submitted.', 'success')
    cb({ success = true, pendingMOT = pendingMOT })
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  COMMAND: /addpoints [playerid] [offence_code]
--  Available to: Config.PenaltyJobs
-- ──────────────────────────────────────────────────────────────────────────────

RegisterCommand('addpoints', function(source, args)
    if source == 0 then return end
    local Officer = QBCore.Functions.GetPlayer(source)
    if not Officer then return end

    if not hasJob(Officer.PlayerData.job.name, Config.PenaltyJobs) then
        TriggerClientEvent('QBCore:Notify', source, 'You do not have permission to issue penalty points.', 'error')
        return
    end

    if not args[1] or not args[2] then
        TriggerClientEvent('QBCore:Notify', source, 'Usage: /addpoints [playerID] [offenceCode]  e.g. /addpoints 1 SP30', 'error')
        return
    end

    local targetId   = tonumber(args[1])
    local offenceCode = tostring(args[2]):upper()

    local Target = QBCore.Functions.GetPlayer(targetId)
    if not Target then
        TriggerClientEvent('QBCore:Notify', source, 'Player not found.', 'error')
        return
    end

    local offence = nil
    for _, v in ipairs(Config.PenaltyOffences) do
        if v.code == offenceCode then offence = v break end
    end

    if not offence then
        local codes = ''
        for _, v in ipairs(Config.PenaltyOffences) do codes = codes .. v.code .. ' ' end
        TriggerClientEvent('QBCore:Notify', source, 'Invalid offence code. Valid codes: ' .. codes, 'error')
        return
    end

    local citizenid    = Target.PlayerData.citizenid
    local officerName  = Officer.PlayerData.charinfo.firstname .. ' ' .. Officer.PlayerData.charinfo.lastname
    local targetName   = Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname

    MySQL.insert.await(
        'INSERT INTO dvla_penalty_points (citizenid, offence, points, issued_by, date) VALUES (?,?,?,?,?)',
        { citizenid, offence.code .. ' — ' .. offence.offence, offence.points, officerName, getDate() }
    )

    local result = MySQL.query.await('SELECT COALESCE(SUM(points),0) as total FROM dvla_penalty_points WHERE citizenid = ?', { citizenid })
    local totalPoints = tonumber(result[1].total) or 0

    MySQL.update.await('UPDATE dvla_licences SET penalty_points = ? WHERE citizenid = ?', { totalPoints, citizenid })

    if totalPoints >= Config.PenaltyPoints.maxPoints and Config.PenaltyPoints.autoDisqualify then
        MySQL.update.await("UPDATE dvla_licences SET suspended = 1, licence_type = 'suspended' WHERE citizenid = ?", { citizenid })
        notifyByCitizenId(citizenid, 'Your driving licence has been automatically DISQUALIFIED — 12 penalty points reached.', 'error')
    end

    TriggerClientEvent('QBCore:Notify', source,   offence.points .. ' penalty points issued to ' .. targetName .. ' (' .. offence.code .. ')', 'success')
    TriggerClientEvent('QBCore:Notify', targetId, 'You have received ' .. offence.points .. ' penalty points: ' .. offence.offence, 'error')
    TriggerClientEvent('dvla:client:refreshPoints', targetId, totalPoints)
end, false)

-- ──────────────────────────────────────────────────────────────────────────────
--  COMMAND: /dvlaoffences  — lists all offence codes in chat
-- ──────────────────────────────────────────────────────────────────────────────

RegisterCommand('dvlaoffences', function(source, args)
    if source == 0 then return end
    local Officer = QBCore.Functions.GetPlayer(source)
    if not Officer then return end
    if not hasJob(Officer.PlayerData.job.name, Config.PenaltyJobs) then
        TriggerClientEvent('QBCore:Notify', source, 'No permission.', 'error')
        return
    end
    for _, v in ipairs(Config.PenaltyOffences) do
        TriggerClientEvent('chat:addMessage', source, {
            color = { 255, 165, 0 },
            multiline = false,
            args = { 'DVLA', v.code .. ' (' .. v.points .. ' pts) — ' .. v.offence }
        })
    end
end, false)

print('^2[DVLA] ^7Server script loaded.')

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: COMPLETE AI PRACTICAL TEST (no examiner job required)
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:completeAIPractical', function(source, cb, passed, minorFaults, majorFaults, categoryLabel)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({ success = false }) end

    local citizenid = Player.PlayerData.citizenid
    categoryLabel = categoryLabel or 'B'

    -- Must have passed theory
    local lic = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
    if not lic[1] or not flag(lic[1].theory_passed) then
        return cb({ success = false, reason = 'Theory test not passed.' })
    end

    -- Decode existing categories (stored as JSON array string e.g. '["B","AM"]')
    local categoriesJson = lic[1].categories or '[]'
    local heldCategories = {}
    for cat in categoriesJson:gmatch('"([^"]+)"') do
        heldCategories[cat] = true
    end

    -- Already holds this category
    if heldCategories[categoryLabel] then
        return cb({ success = false, reason = 'You already hold the ' .. categoryLabel .. ' category.' })
    end

    -- Check prerequisites from config
    local categoryConfig = nil
    for _, cat in ipairs(Config.Categories) do
        if cat.label == categoryLabel then categoryConfig = cat break end
    end
    if not categoryConfig then
        return cb({ success = false, reason = 'Unknown category: ' .. categoryLabel })
    end
    for _, req in ipairs(categoryConfig.requires) do
        if not heldCategories[req] then
            return cb({ success = false, reason = 'You must hold the ' .. req .. ' category first.' })
        end
    end

    -- A practical test has to be booked on lsgov.co.uk first. The booking is spent here.
    if bookingRequired() and not consumeBooking(citizenid, 'practical', categoryLabel) then
        return cb({ success = false, reason = 'You need to book this practical test on lsgov.co.uk first.' })
    end

    -- Record the test attempt
    MySQL.insert.await(
        'INSERT INTO dvla_practical_tests (citizenid, centre, minor_faults, major_faults, passed, examiner, category, date) VALUES (?,?,?,?,?,?,?,?)',
        { citizenid, Config.PracticalTest.centre, minorFaults or 0, majorFaults or 0,
          passed and 1 or 0, 'AI Examiner (' .. Config.AIPractical.examinerName .. ')',
          categoryLabel, getDateTime() }
    )

    if passed then
        -- Add category to held list
        heldCategories[categoryLabel] = true
        local catList = {}
        for k, _ in pairs(heldCategories) do table.insert(catList, '"' .. k .. '"') end
        local newJson = '[' .. table.concat(catList, ',') .. ']'

        MySQL.update.await('UPDATE dvla_licences SET practical_passed = 1, categories = ? WHERE citizenid = ?',
            { newJson, citizenid })

        -- Issue full licence
        MySQL.update.await(
            "UPDATE dvla_licences SET licence_type = 'full', issue_date = ? WHERE citizenid = ? AND theory_passed = 1",
            { getDate(), citizenid }
        )

        -- Build category string for the item (e.g. "AM · A · B")
        local catDisplay = table.concat(catList, ' · '):gsub('"', '')

        -- Build licence metadata for qb-idcard
        local charinfo   = Player.PlayerData.charinfo
        local issueDate  = getDate()
        local expiryDate = os.date('%d/%m/%Y', os.time() + (10 * 365 * 24 * 3600))

        local licenceInfo = {
            firstname   = charinfo.firstname  or '',
            lastname    = charinfo.lastname   or '',
            birthdate   = charinfo.birthdate  or '',
            gender      = charinfo.gender     or 0,
            nationality = 'BRITISH CITIZEN',
            issuedate   = issueDate,
            expirydate  = expiryDate,
            type        = 'Full UK Driving Licence',
            categories  = catDisplay,
            serial      = issueSerial(citizenid),
        }

        -- Give / update the driver_license item (qb-inventory)
        local existingItem = Player.Functions.GetItemByName('driver_license')
        if existingItem then
            Player.Functions.RemoveItem('driver_license', 1)
        end
        Player.Functions.AddItem('driver_license', 1, false, licenceInfo)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['driver_license'], 'add')
        TriggerClientEvent('QBCore:Notify', source,
            'Category ' .. categoryLabel .. ' PASSED! 🎉 Your licence now includes: ' .. catDisplay, 'success')
    end

    local finalLic = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
    cb({ success = true, passed = passed, licence = finalLic[1] })
end)


-- driver_license useable item is handled by qb-idcard — do not register it here

-- ──────────────────────────────────────────────────────────────────────────────
--  REPLACE LOST LICENCE
--  Shared by the in-world portal and the website. Returns true, or false plus a reason.
-- ──────────────────────────────────────────────────────────────────────────────

--- Orders a replacement licence (website only). Paid from the bank, ready after Config.Replace.waitSeconds,
--- then delivered to a Postal Prime locker (or the inventory). The old licence stops working straight away.
--- data = { lockerId = '...' }. Returns { fee, readyAt, now, mode, lockerLabel } or nil, message.
local replaceBusy = {}
local function replaceLicence(source, data)
    data = type(data) == 'table' and data or {}
    if replaceBusy[source] then return nil, 'Please wait, your last request is still being processed.' end
    replaceBusy[source] = true
    local ok, res, err = pcall(function()
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return nil, 'You are not signed in.' end
        local citizenid = Player.PlayerData.citizenid
        initPlayer(citizenid)

        local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
        if not lic or not flag(lic.practical_passed) then return nil, 'No qualifying licence found on record.' end
        if pendingReplacement(citizenid) then return nil, 'You already have a replacement licence on its way.' end

        local mode = deliveryMode()
        local lockerId = ''
        if mode == 'locker' then
            lockerId = tostring(data.lockerId or '')
            if not lockerLabel(lockerId) then return nil, 'Choose where to collect your licence.' end
        end

        local fee = Config.Fees.replace or 20
        if not charge(Player, fee, 'dvla-licence-replacement', true) then
            return nil, 'You do not have enough money in your bank account.'
        end

        local ci = Player.PlayerData.charinfo or {}
        local serial = newSerial()
        local info = {
            firstname = ci.firstname or '', lastname = ci.lastname or '', birthdate = ci.birthdate or '',
            gender = ci.gender or 0, nationality = 'BRITISH CITIZEN',
            issuedate = lic.issue_date or getDate(),
            expirydate = os.date('%d/%m/%Y', os.time() + (10 * 365 * 24 * 3600)),
            type = 'Full UK Driving Licence',
        }
        local applied = os.time()
        local inserted = pcall(function()
            MySQL.insert.await(
                "INSERT INTO dvla_replacements (ref, citizenid, locker_id, status, fee, info, applied_at, ready_at) VALUES (?,?,?,'processing',?,?,?,?)",
                { serial, citizenid, lockerId, fee, json.encode(info), applied, applied + (Config.Replace.waitSeconds or 1800) })
        end)
        if not inserted then
            Player.Functions.AddMoney('bank', fee, 'dvla-replacement-refund')
            return nil, 'We could not process your application. You have not been charged, please try again.'
        end

        -- the old licence is cancelled now; the new one carries this serial when it arrives
        MySQL.update.await('UPDATE dvla_licences SET card_serial = ? WHERE citizenid = ?', { serial, citizenid })
        pcall(function() MySQL.update.await('DELETE FROM dvla_photos WHERE citizenid = ?', { citizenid }) end)
        return {
            fee = fee, readyAt = applied + (Config.Replace.waitSeconds or 1800), now = applied, mode = mode,
            lockerLabel = lockerId ~= '' and lockerLabel(lockerId) or nil,
        }
    end)
    replaceBusy[source] = nil
    if not ok then print('^1[DVLA] ^7replacement failed: ' .. tostring(res)); return nil, 'Something went wrong. Please try again.' end
    return res, err
end

--- Hands over a replacement whose waiting time is up. Returns true when it was handled.
local function deliverReplacement(row)
    local cid = row.citizenid
    local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { cid })
    if not lic then
        MySQL.update.await("UPDATE dvla_replacements SET status = 'done' WHERE id = ?", { row.id })
        return true
    end
    -- A newer licence was issued in the meantime (a practical test was passed): nothing left to send.
    if lic.card_serial ~= row.ref then
        MySQL.update.await("UPDATE dvla_replacements SET status = 'done' WHERE id = ?", { row.id })
        return true
    end

    local info = json.decode(row.info or '{}') or {}
    local cats = heldList(lic)
    table.sort(cats, function(a, b)
        local function ord(l) for i, c in ipairs(Config.Categories) do if c.label == l then return i end end return 999 end
        return ord(a) < ord(b)
    end)
    info.categories = #cats > 0 and table.concat(cats, ' · ') or (lic.licence_type or 'full')
    info.serial = row.ref

    local src = findSource(cid)
    local mode = deliveryMode()
    if mode == 'locker' then
        local lockerId = row.locker_id ~= '' and row.locker_id or (lockers()[1] or {}).id
        if not lockerId then return false end
        local ok, sent, why = pcall(function()
            return exports['as-postalprime']:createParcel(cid, {
                ref = row.ref, sender = Config.Replace.sender, lockerId = lockerId,
                prepSeconds = Config.Replace.prepSeconds, expireSeconds = Config.Replace.expireSeconds,
                items = { { item = 'driver_license', label = 'Driving licence', icon = '🪪', qty = 1, metadata = info } },
            })
        end)
        if not ok then print('^1[DVLA] ^7createParcel failed: ' .. tostring(sent)); return false end
        if not sent then
            if why ~= 'busy' then print('^1[DVLA] ^7could not send the licence to a locker: ' .. tostring(why)) end
            return false -- 'busy': the player has another Postal Prime order; try again next pass
        end
        MySQL.update.await("UPDATE dvla_replacements SET status = 'sent' WHERE id = ?", { row.id })
        local label = lockerLabel(lockerId) or 'your locker'
        phoneNotify(src, 'Driving licence sent', ('Your replacement driving licence has been sent to %s.'):format(label))
        phoneMail(src, cid, 'Your replacement driving licence is on its way',
            ('Hello,\n\nYour replacement driving licence has been sent to %s. Open Postal Prime for your pickup code, then collect it from the locker.'):format(label))
        return true
    end

    -- inventory delivery: needs the player online
    if not src then return false end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    Player.Functions.AddItem('driver_license', 1, false, info)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['driver_license'], 'add')
    MySQL.update.await("UPDATE dvla_replacements SET status = 'done' WHERE id = ?", { row.id })
    phoneNotify(src, 'Driving licence issued', 'Your replacement driving licence has been added to your inventory.')
    phoneMail(src, cid, 'Your replacement driving licence', 'Hello,\n\nYour replacement driving licence is ready and is in your inventory.')
    return true
end

CreateThread(function()
    Wait(5000)
    while true do
        local rows = MySQL.query.await(
            "SELECT * FROM dvla_replacements WHERE status = 'processing' AND ready_at <= ? ORDER BY ready_at LIMIT 20", { os.time() }) or {}
        for i = 1, #rows do
            local ok, err = pcall(deliverReplacement, rows[i])
            if not ok then print('^1[DVLA] ^7replacement delivery failed: ' .. tostring(err)) end
        end
        Wait(15000)
    end
end)

-- Postal Prime tells us when the parcel is picked up, or when nobody collected it in time.
AddEventHandler('as-postalprime:parcelCollected', function(cid, ref)
    MySQL.update.await("UPDATE dvla_replacements SET status = 'done' WHERE ref = ? AND citizenid = ?", { tostring(ref or ''), tostring(cid or '') })
end)

AddEventHandler('as-postalprime:parcelExpired', function(cid, ref)
    -- Send it again: back in the queue, ready straight away.
    MySQL.update.await("UPDATE dvla_replacements SET status = 'processing', ready_at = ? WHERE ref = ? AND citizenid = ? AND status = 'sent'",
        { os.time(), tostring(ref or ''), tostring(cid or '') })
end)

--- The in-world portal no longer hands out licences: replacements are ordered on the website.
QBCore.Functions.CreateCallback('dvla:server:replaceLicence', function(source, cb)
    cb({ success = false, reason = 'Replacement licences are ordered on lsgov.co.uk (Driving licence and tests) and delivered to a Postal Prime locker.' })
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  CALLBACK: CAN THIS PLAYER START A PRACTICAL TEST? (checked before the examiner spawns)
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:canStartPractical', function(source, cb, categoryLabel)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({ success = false, reason = 'Player not found.' }) end
    local citizenid = Player.PlayerData.citizenid
    categoryLabel = tostring(categoryLabel or 'B')

    local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
    if not lic or not flag(lic.theory_passed) then return cb({ success = false, reason = 'Theory test not passed.' }) end
    if flag(lic.suspended) then return cb({ success = false, reason = 'Your licence is suspended.' }) end

    local cat = findCategory(categoryLabel)
    if not cat then return cb({ success = false, reason = 'Unknown category: ' .. categoryLabel }) end
    local held = heldCategories(lic)
    if held[categoryLabel] then return cb({ success = false, reason = 'You already hold the ' .. categoryLabel .. ' category.' }) end
    for _, req in ipairs(cat.requires or {}) do
        if not held[req] then return cb({ success = false, reason = 'You must hold the ' .. req .. ' category first.' }) end
    end
    if bookingRequired() and unusedCount(citizenid, 'practical', categoryLabel) == 0 then
        return cb({ success = false, reason = 'Book this practical test on lsgov.co.uk first.' })
    end
    cb({ success = true })
end)

AddEventHandler('playerDropped', function() bookingBusy[source] = nil end)

-- ──────────────────────────────────────────────────────────────────────────────
--  LICENCE CARD  (the driver_license item opens this card; replaces qbx_idcard for licences)
--  The card is built from the licence record, so it is always up to date.
-- ──────────────────────────────────────────────────────────────────────────────

--- Metadata of every driver_license item the player carries.
local function licenceItemMetas(source)
    local metas = {}
    if GetResourceState('ox_inventory') == 'started' then
        local ok, slots = pcall(function() return exports.ox_inventory:Search(source, 'slots', 'driver_license') end)
        if ok and type(slots) == 'table' then
            for _, slot in pairs(slots) do metas[#metas + 1] = slot.metadata or {} end
            return metas
        end
    end
    local Player = QBCore.Functions.GetPlayer(source)
    local it = Player and Player.Functions.GetItemByName('driver_license')
    if it then metas[1] = it.info or it.metadata or {} end
    return metas
end

--- Returns true when the player carries a current licence item; otherwise false and a message.
--- Once a licence has a card serial (a replacement was ordered, or a test was passed) items with another serial are cancelled.
local function hasLicenceItem(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'You are not signed in.' end
    local metas = licenceItemMetas(source)
    if #metas == 0 then return false, 'You are not carrying a driving licence.' end
    local serial = MySQL.scalar.await('SELECT card_serial FROM dvla_licences WHERE citizenid = ?', { Player.PlayerData.citizenid })
    if serial == nil or serial == '' then return true end
    for _, m in ipairs(metas) do if m.serial == serial then return true end end
    return false, 'This driving licence has been cancelled and replaced.'
end

local function parseDob(dob)
    dob = tostring(dob or '')
    local y, m, d = dob:match('^(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)')
    if not y then d, m, y = dob:match('^(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)') end
    if not y then return nil end
    return tonumber(y), tonumber(m), tonumber(d)
end

--- UK style licence number: 5 letters of surname, date of birth digits, initials, 9, two letters.
local function licenceNumber(first, last, dob, citizenid)
    local function alpha(v) return (tostring(v or ''):upper():gsub('[^A-Z]', '')) end
    local sn = alpha(last):sub(1, 5)
    sn = sn .. string.rep('9', 5 - #sn)
    local y, m, d = parseDob(dob)
    local digits = '999999'
    if y then
        local ys = ('%04d'):format(y)
        digits = ys:sub(3, 3) .. ('%02d'):format(m) .. ('%02d'):format(d) .. ys:sub(4, 4)
    end
    local f = alpha(first)
    local initials = (f:sub(1, 1) ~= '' and f:sub(1, 1) or '9') .. '9'
    local h = 0
    for i = 1, #tostring(citizenid or '') do h = (h * 31 + tostring(citizenid):byte(i)) % 1000003 end
    local checks = string.char(65 + h % 26) .. string.char(65 + (h // 26) % 26)
    return sn .. digits .. initials .. '9' .. checks
end

local function addYears(dateStr, years)
    local d, m, y = tostring(dateStr or ''):match('^(%d+)/(%d+)/(%d+)$')
    if not y or (tonumber(years) or 0) <= 0 then return nil end
    return ('%02d/%02d/%04d'):format(tonumber(d), tonumber(m), tonumber(y) + years)
end

local function categoryOrder(label)
    for i, cat in ipairs(Config.Categories) do if cat.label == label then return i end end
    return 999
end

--- The licence as printed on the card. Returns the card, or nil and a message.
local function buildCard(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil, 'You are not signed in.' end
    local cid = Player.PlayerData.citizenid
    initPlayer(cid)
    local lic = MySQL.single.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { cid })
    if not lic then return nil, 'No licence on record.' end
    local ci = Player.PlayerData.charinfo or {}

    local cats = heldList(lic)
    table.sort(cats, function(a, b) return categoryOrder(a) < categoryOrder(b) end)

    local status = 'valid'
    if flag(lic.suspended) or lic.licence_type == 'suspended' then status = 'suspended'
    elseif lic.licence_type ~= 'full' then status = 'provisional' end

    local issued = lic.issue_date
    local expires = addYears(issued, Config.Card.validYears)
    if expires and status == 'valid' then
        local d, m, y = expires:match('^(%d+)/(%d+)/(%d+)$')
        if os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23 }) < os.time() then status = 'expired' end
    end

    local photo = MySQL.scalar.await('SELECT photo FROM dvla_photos WHERE citizenid = ?', { cid })
    local sexVal = ci.gender
    local sex = (sexVal == 1 or sexVal == '1' or tostring(sexVal):lower() == 'female' or tostring(sexVal):upper() == 'F') and 'F' or 'M'

    return {
        number = licenceNumber(ci.firstname, ci.lastname, ci.birthdate, cid),
        first = ci.firstname or '', last = ci.lastname or '', dob = ci.birthdate or '', sex = sex,
        nationality = (ci.nationality and ci.nationality ~= '') and ci.nationality or Config.Card.nationality,
        type = lic.licence_type, status = status, categories = cats,
        issued = issued, expires = expires, authority = Config.Card.authority,
        photo = photo,
    }
end

QBCore.Functions.CreateCallback('dvla:server:getCard', function(source, cb)
    local has, why = hasLicenceItem(source)
    if not has then return cb({ error = why }) end
    local card, err = buildCard(source)
    if not card then return cb({ error = err or 'This licence is not readable.' }) end
    cb({ card = card, needPhoto = Config.Card.photo == true and card.photo == nil })
end)

local lastPhoto = {}
--- The client takes the mugshot (MugShotBase64) the first time the licence is looked at.
RegisterNetEvent('dvla:server:savePhoto', function(img)
    local src = source
    if type(img) ~= 'string' or #img > 400000 or img:sub(1, 11) ~= 'data:image/' then return end
    if (lastPhoto[src] or 0) > os.time() - 20 then return end
    lastPhoto[src] = os.time()
    if not Config.Card.photo or not hasLicenceItem(src) then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    -- only the first photo is kept; a replacement licence clears it so a new one is taken
    MySQL.insert.await('INSERT IGNORE INTO dvla_photos (citizenid, photo, updated) VALUES (?,?,?)',
        { Player.PlayerData.citizenid, img, os.time() })
end)

local lastShow = {}
--- Hold the licence up to the nearest player.
RegisterNetEvent('dvla:server:showCard', function()
    local src = source
    if (lastShow[src] or 0) > os.time() - 3 then return end
    lastShow[src] = os.time()
    if not hasLicenceItem(src) then return end
    local card = buildCard(src)
    if not card then return end

    local myPed = GetPlayerPed(src)
    if not myPed or myPed == 0 then return end
    local me = GetEntityCoords(myPed)
    local best, bestDist = nil, (Config.Card.showDistance or 3.0)
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src then
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 then
                local dist = #(GetEntityCoords(ped) - me)
                if dist <= bestDist then best, bestDist = id, dist end
            end
        end
    end
    if not best then
        return TriggerClientEvent('QBCore:Notify', src, 'There is nobody close enough to show your licence to.', 'error')
    end
    local Player = QBCore.Functions.GetPlayer(src)
    local ci = Player and Player.PlayerData.charinfo or {}
    local fromName = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '')
    TriggerClientEvent('dvla:client:showCard', best, card, (fromName))
    TriggerClientEvent('QBCore:Notify', src, 'You showed your driving licence.', 'success')
end)

--- Using the driver_license item opens the card. Registered again a few seconds after start in case
--- another resource (qbx_idcard) registered the same item later.
local function registerLicenceItem()
    local function use(source) TriggerClientEvent('dvla:client:useItem', source) end
    if GetResourceState('qbx_core') == 'started' then
        pcall(function() exports.qbx_core:CreateUseableItem('driver_license', function(source) use(source) end) end)
    else
        pcall(function() QBCore.Functions.CreateUseableItem('driver_license', function(source) use(source) end) end)
    end
end
registerLicenceItem()
CreateThread(function() Wait(8000) registerLicenceItem() end)

AddEventHandler('playerDropped', function() lastPhoto[source] = nil; lastShow[source] = nil end)

-- ──────────────────────────────────────────────────────────────────────────────
--  EXPORTS for the government site (as-browser)
-- ──────────────────────────────────────────────────────────────────────────────

exports('getLicenceSummary', licenceSummary)          -- (source) -> summary table
exports('getBookingState',   bookingState)            -- (source) -> fees + what can be booked
exports('bookTest',          bookTest)                -- (source, 'theory' | 'practical', category) -> booking or nil, message
exports('replaceLicence',    replaceLicence)          -- (source, { lockerId }) -> { fee, readyAt, now, mode, lockerLabel } or nil, message. Paid from the bank.
