local QBCore = exports['qb-core']:GetCoreObject()

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

    cb({
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
        if lic[1] and lic[1].practical_passed == 1 then
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

    table.insert(pendingMOT, {
        citizenid = citizenid,
        name      = name,
        plate     = plate,
        source    = source,
        bookedAt  = getDateTime(),
    })

    notifyOnlinePlayers(Config.MOTInspectorJobs, 'New MOT booking: ' .. plate .. ' — Owner: ' .. name, 'primary')
    TriggerClientEvent('QBCore:Notify', source, 'MOT booked for ' .. plate .. '. An inspector has been notified.', 'success')

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
        { citizenid, plate, passed and 1 or 0, inspectorName, notes or '', expiryDate, getDateTime() }
    )

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
    if not lic[1] or lic[1].theory_passed == 0 then
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
--  CALLBACK: REPLACE LOST LICENCE
-- ──────────────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('dvla:server:replaceLicence', function(source, cb)
    CreateThread(function()
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return cb({ success = false, reason = 'Player not found.' }) end

        local citizenid = Player.PlayerData.citizenid

        -- Must have a full licence on record
        local lic = MySQL.query.await('SELECT * FROM dvla_licences WHERE citizenid = ?', { citizenid })
        if not lic or not lic[1] or lic[1].practical_passed == 0 then
            return cb({ success = false, reason = 'No qualifying licence found on record.' })
        end

        -- Charge £20 — deduct from cash first, remainder from bank
        local REPLACE_FEE = 2000
        local cash = Player.Functions.GetMoney('cash') or 0
        local bank = Player.Functions.GetMoney('bank') or 0
        if (cash + bank) < REPLACE_FEE then
            return cb({ success = false, reason = 'Insufficient funds. You need £20 to replace your licence.' })
        end
        if cash >= REPLACE_FEE then
            Player.Functions.RemoveMoney('cash', REPLACE_FEE, 'dvla-licence-replacement')
        else
            Player.Functions.RemoveMoney('cash', cash, 'dvla-licence-replacement')
            Player.Functions.RemoveMoney('bank', REPLACE_FEE - cash, 'dvla-licence-replacement')
        end

        -- Remove any existing driver_license item to avoid duplicates (qb-inventory)
        local existingLic = Player.Functions.GetItemByName('driver_license')
        if existingLic then
            Player.Functions.RemoveItem('driver_license', 1)
        end

        -- Re-issue with current categories
        local charinfo   = Player.PlayerData.charinfo
        local cats       = lic[1].categories or '[]'
        local catList    = {}
        for c in cats:gmatch('"([^"]+)"') do table.insert(catList, c) end
        local catDisplay = table.concat(catList, ' · ')
        if catDisplay == '' then catDisplay = lic[1].licence_type or 'full' end

        local expiryDate = os.date('%d/%m/%Y', os.time() + (10 * 365 * 24 * 3600))

        local licenceInfo = {
            firstname   = charinfo.firstname or '',
            lastname    = charinfo.lastname  or '',
            birthdate   = charinfo.birthdate or '',
            gender      = charinfo.gender    or 0,
            nationality = 'BRITISH CITIZEN',
            issuedate   = lic[1].issue_date  or getDate(),
            expirydate  = expiryDate,
            type        = 'Full UK Driving Licence',
            categories  = catDisplay,
        }

        Player.Functions.AddItem('driver_license', 1, false, licenceInfo)
        TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['driver_license'], 'add')
        TriggerClientEvent('QBCore:Notify', source, 'Replacement driving licence issued. £20 fee deducted.', 'success')

        cb({ success = true })
    end)
end)
