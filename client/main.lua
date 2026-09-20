local QBCore = exports['qb-core']:GetCoreObject()
local isOpen = false

-- ──────────────────────────────────────────────────────────────────────────────
--  OPEN PORTAL
-- ──────────────────────────────────────────────────────────────────────────────

local function openPortal()
    if isOpen then return end

    QBCore.Functions.TriggerCallback('dvla:server:getData', function(data)
        if not data then
            QBCore.Functions.Notify('Unable to connect to DVLA services.', 'error')
            return
        end
        isOpen = true
        data.questions = Config.TheoryQuestions
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openUI', data = data })
    end)
end

-- ──────────────────────────────────────────────────────────────────────────────
--  PORTAL ZONE  (ox_target, qb-target, or a plain "Press E" prompt; set in Config.Portal)
-- ──────────────────────────────────────────────────────────────────────────────

local P = Config.Portal

local function useOxTarget()
    exports.ox_target:addBoxZone({
        name     = 'dvla_portal',
        coords   = vector3(P.coords.x, P.coords.y, P.coords.z + 0.5),
        size     = P.size,
        rotation = P.heading,
        debug    = false,
        options  = { {
            name     = 'dvla_portal_open',
            icon     = P.icon,
            label    = P.label,
            distance = P.distance,
            onSelect = function() openPortal() end,
        } },
    })
end

local function useQbTarget()
    exports['qb-target']:AddBoxZone('dvla_portal', P.coords, P.size.x, P.size.y, {
        name      = 'dvla_portal',
        heading   = P.heading,
        debugPoly = false,
        minZ      = P.coords.z - 1.0,
        maxZ      = P.coords.z + 2.0,
    }, {
        options = { {
            type  = 'client',
            event = 'dvla:client:openPortal',
            icon  = P.icon,
            label = P.label,
        } },
        distance = P.distance,
    })
end

--- Fallback with no target resource: show a hint and open on E.
local function usePrompt()
    CreateThread(function()
        while true do
            local wait = 1000
            local dist = #(GetEntityCoords(PlayerPedId()) - P.coords)
            if dist < 10.0 then
                wait = 0
                DrawMarker(2, P.coords.x, P.coords.y, P.coords.z + 0.3, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.25, 0, 112, 60, 160, false, true, 2, false, nil, nil, false)
                if dist < P.distance and not isOpen then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ - ' .. P.label)
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, 38) then openPortal() end
                end
            end
            Wait(wait)
        end
    end)
end

local function started(name) return GetResourceState(name) == 'started' end

CreateThread(function()
    local mode = P.target or 'auto'
    if mode == 'auto' then
        if started('ox_target') then mode = 'ox_target'
        elseif started('qb-target') then mode = 'qb-target'
        else mode = 'none' end
    end

    if mode == 'ox_target' and pcall(useOxTarget) then return end
    if mode == 'qb-target' then
        if pcall(useQbTarget) then return end
        -- some qb-target versions are missing AddBoxZone; try ox_target before giving up
        if started('ox_target') and pcall(useOxTarget) then return end
    end
    print('^3[DVLA] ^7No working target resource, using the "Press E" prompt at the portal instead.')
    usePrompt()
end)

RegisterNetEvent('dvla:client:openPortal', function() openPortal() end)

-- ──────────────────────────────────────────────────────────────────────────────
--  AI PRACTICAL TEST
-- ──────────────────────────────────────────────────────────────────────────────

local practicalActive    = false
local practicalVehicle   = 0
local practicalTrailer   = 0       -- BE category: spawned trailer entity
local practicalPed       = 0
local practicalCheckpoint = 1
local practicalMinorFaults = 0
local practicalMajorFaults = 0
local practicalCpBlip    = nil
local practicalEnded     = false   -- guard against double-end

-- Convert m/s to mph
local function toMph(mps) return mps * 2.23694 end

-- Load a model, yielding until ready
local function loadModel(hash)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) do
        Wait(100)
        t = t + 100
        if t > 10000 then return false end
    end
    return true
end

-- Show a subtitle-style message attributed to the examiner
local function examinerSay(text, duration)
    duration = duration or 5000
    local cfg = Config.AIPractical
    local msg = '[' .. cfg.examinerName .. ']: ' .. text
    -- Display as help text (top-left hint style) for duration ms
    local endTime = GetGameTimer() + duration
    CreateThread(function()
        while GetGameTimer() < endTime do
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(msg)
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        end
    end)
end

-- Draw the fault HUD on screen every frame during test
local function startHUD(catCfg)
    local cfg = Config.AIPractical
    CreateThread(function()
        while practicalActive do
            local total = #catCfg.checkpoints
            local cp    = math.min(practicalCheckpoint, total)
            local label = 'DVLA Practical [' .. catCfg.label .. ']  |  Checkpoint: ' .. cp .. '/' .. total
                       .. '  |  Minor Faults: ' .. practicalMinorFaults .. '/' .. cfg.maxMinorFaults

            -- Draw top-centre text
            SetTextFont(4)
            SetTextScale(0.0, 0.38)
            SetTextColour(255, 255, 255, 220)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(label)
            EndTextCommandDisplayText(0.5, 0.01)

            Wait(0)
        end
    end)
end

-- Set the GPS blip + route to the current checkpoint
local function setCheckpointBlip(catCfg)
    if practicalCpBlip then RemoveBlip(practicalCpBlip) practicalCpBlip = nil end

    if practicalCheckpoint > #catCfg.checkpoints then return end

    local cp = catCfg.checkpoints[practicalCheckpoint]
    practicalCpBlip = AddBlipForCoord(cp.coords.x, cp.coords.y, cp.coords.z)
    SetBlipSprite(practicalCpBlip, 1)
    SetBlipColour(practicalCpBlip, 2) -- green
    SetBlipScale(practicalCpBlip, 1.0)
    SetBlipRoute(practicalCpBlip, true)
    SetBlipRouteColour(practicalCpBlip, 3)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Checkpoint ' .. practicalCheckpoint .. '/' .. #catCfg.checkpoints)
    EndTextCommandSetBlipName(practicalCpBlip)

    examinerSay(cp.instruction, 6000)
end

-- Clean up all test entities/blips and optionally submit result
local function endPracticalTest(passed, failReason, categoryLabel)
    if practicalEnded then return end
    practicalEnded = true
    practicalActive = false

    if practicalCpBlip then RemoveBlip(practicalCpBlip) practicalCpBlip = nil end

    local minor = practicalMinorFaults
    local major = practicalMajorFaults

    Wait(2500)

    -- Delete ped then vehicle
    if DoesEntityExist(practicalPed) then
        DeleteEntity(practicalPed)
    end
    practicalPed = 0

    if DoesEntityExist(practicalVehicle) then
        -- Let player get out first if they're still inside
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == practicalVehicle then
            TaskLeaveVehicle(ped, practicalVehicle, 0)
            Wait(2000)
        end
        DeleteEntity(practicalVehicle)
    end
    practicalVehicle = 0

    -- Delete trailer if one was spawned (BE category)
    if DoesEntityExist(practicalTrailer) then
        DeleteEntity(practicalTrailer)
    end
    practicalTrailer = 0

    -- Submit to server — explicitly cast passed to bool so QBCore serialises it correctly
    local passedBool = (passed == true)
    QBCore.Functions.TriggerCallback('dvla:server:completeAIPractical', function(result)
        if result and result.success then
            if passedBool then
                QBCore.Functions.Notify(
                    'Practical Test PASSED! Minor faults: ' .. minor .. '. Full UK Driving Licence issued.',
                    'success', 8000)
            else
                local reason = failReason and (' | ' .. failReason) or ''
                QBCore.Functions.Notify(
                    'Practical Test FAILED.' .. reason .. ' Minor faults: ' .. minor,
                    'error', 8000)
            end
        end
    end, passedBool, minor, major, categoryLabel)
end

-- Main test launcher
local function startAIPracticalTest(categoryLabel)
    if practicalActive then
        QBCore.Functions.Notify('A practical test is already in progress.', 'error')
        return
    end

    -- Find category config
    local catCfg = nil
    for _, c in ipairs(Config.Categories) do
        if c.label == categoryLabel then catCfg = c break end
    end
    if not catCfg then
        QBCore.Functions.Notify('Unknown licence category: ' .. tostring(categoryLabel), 'error')
        return
    end

    local cfg = Config.AIPractical

    -- Reset state
    practicalActive      = true
    practicalEnded       = false
    practicalCheckpoint  = 1
    practicalMinorFaults = 0
    practicalMajorFaults = 0

    QBCore.Functions.Notify('Your examiner is preparing the ' .. catCfg.name .. ' test vehicle...', 'primary', 4000)
    Wait(1500)

    -- ── Spawn vehicle ──────────────────────────────────────
    local vehHash = GetHashKey(catCfg.vehicle)
    if not loadModel(vehHash) then
        QBCore.Functions.Notify('Failed to load test vehicle. Please try again.', 'error')
        practicalActive = false
        return
    end

    local sp  = cfg.spawnPoint
    local veh = CreateVehicle(vehHash, sp.x, sp.y, sp.z, sp.w, false, false)
    SetVehicleNumberPlateText(veh, catCfg.vehiclePlate)
    SetVehicleColours(veh, catCfg.colour1, catCfg.colour2)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleDirtLevel(veh, 0.0)
    practicalVehicle = veh
    SetModelAsNoLongerNeeded(vehHash)

    -- ── BE: Spawn trailer & require player to hook it up ──────────────────
    if catCfg.trailer then
        local trailerHash = GetHashKey(catCfg.trailer)
        if not loadModel(trailerHash) then
            QBCore.Functions.Notify('Failed to load test trailer. Please try again.', 'error')
            DeleteEntity(veh)
            practicalVehicle = 0
            practicalActive  = false
            return
        end

        -- Place the trailer directly behind the tow vehicle
        local trailerCoords = GetOffsetFromEntityInWorldCoords(veh, 0.0, -7.5, 0.0)
        local trlr = CreateVehicle(trailerHash,
            trailerCoords.x, trailerCoords.y, trailerCoords.z,
            GetEntityHeading(veh), false, false)
        if catCfg.trailerPlate then
            SetVehicleNumberPlateText(trlr, catCfg.trailerPlate)
        end
        SetEntityAsMissionEntity(trlr, true, true)
        SetVehicleDirtLevel(trlr, 0.0)
        practicalTrailer = trlr
        SetModelAsNoLongerNeeded(trailerHash)

        -- Add a blip so the player can see the trailer on the map
        local trailerBlip = AddBlipForEntity(trlr)
        SetBlipSprite(trailerBlip, 479)     -- trailer icon
        SetBlipColour(trailerBlip, 5)       -- yellow
        SetBlipScale(trailerBlip, 0.9)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Test Trailer')
        EndTextCommandSetBlipName(trailerBlip)

        -- Seat player in the tow vehicle first so they can reverse onto the trailer
        SetPedIntoVehicle(PlayerPedId(), veh, -1)
        Wait(800)

        QBCore.Functions.Notify(
            '🚗 Reverse slowly onto the trailer hitch to couple it before the test begins.',
            'primary', 10000)
        examinerSay(
            'Before we start — please reverse your vehicle onto the trailer behind you until you feel it couple.',
            9000)

        -- Poll until the trailer is attached or timeout expires
        local timeout    = (catCfg.trailerHookTimeout or 90) * 1000
        local deadline   = GetGameTimer() + timeout
        local hookTick   = 0

        while GetGameTimer() < deadline do
            Wait(400)
            if not practicalActive then break end   -- aborted externally

            local attached, _ = GetVehicleTrailerVehicle(veh)
            if attached then
                -- Coupled!
                RemoveBlip(trailerBlip)
                examinerSay('Good — trailer is coupled. Let\'s begin the test. Follow the GPS route.', 7000)
                Wait(1500)
                break
            end

            -- Remind player every 20 s
            hookTick = hookTick + 400
            if hookTick >= 20000 then
                hookTick = 0
                local remaining = math.ceil((deadline - GetGameTimer()) / 1000)
                QBCore.Functions.Notify(
                    'Trailer not yet hooked — ' .. remaining .. 's remaining. Reverse onto the hitch.',
                    'error', 5000)
            end
        end

        -- Final check after loop — did they actually hook it?
        local finalAttached, _ = GetVehicleTrailerVehicle(veh)
        if not finalAttached then
            RemoveBlip(trailerBlip)
            examinerSay('You failed to couple the trailer in time. Test cancelled.', 6000)
            Wait(3000)
            endPracticalTest(false, 'Failed to couple trailer before test start', categoryLabel)
            return
        end
    end

    -- ── Spawn examiner NPC (only for vehicles with a passenger seat) ──────
    if catCfg.examinerInVehicle then
        local pedHash = GetHashKey(cfg.examinerPed)
        if loadModel(pedHash) then
            local examPed = CreatePedInsideVehicle(veh, 26, pedHash, 0, false, false)
            SetEntityAsMissionEntity(examPed, true, true)
            SetBlockingOfNonTemporaryEvents(examPed, true)
            SetPedCanBeTargetted(examPed, false)
            SetPedFleeAttributes(examPed, 0, false)
            SetPedCombatAttributes(examPed, 17, false)
            SetPedConfigFlag(examPed, 292, true)
            practicalPed = examPed
            SetModelAsNoLongerNeeded(pedHash)
        end
    end

    -- ── Seat player (skip if already seated during trailer hook-up phase) ──
    local playerPed = PlayerPedId()
    if GetVehiclePedIsIn(playerPed, false) ~= veh then
        SetPedIntoVehicle(playerPed, veh, -1)
        Wait(1000)
    end

    -- Opening examiner line (BE trailer greeting already given above)
    if not catCfg.trailer then
        if catCfg.examinerInVehicle then
            examinerSay("Good morning. I'm " .. cfg.examinerName .. ", your DVLA examiner for the " .. catCfg.name .. " test. Follow the GPS route.", 7000)
        else
            QBCore.Functions.Notify('[' .. cfg.examinerName .. ']: Good morning. I will observe your ' .. catCfg.name .. ' test remotely. Follow the GPS route carefully.', 'primary', 7000)
        end
    end

    Wait(2000)
    setCheckpointBlip(catCfg)
    startHUD(catCfg)

    -- ── Monitoring thread ──────────────────────────────────
    local prevBodyHealth = GetVehicleBodyHealth(veh)
    local testStart      = GetGameTimer()
    local lastSpeedWarn  = 0
    local abandonTimer   = nil

    CreateThread(function()
        while practicalActive do
            Wait(500)
            if not practicalActive then break end

            local ped    = PlayerPedId()
            local inVeh  = GetVehiclePedIsIn(ped, false)
            local now    = GetGameTimer()

            -- Abandonment check
            if inVeh ~= veh then
                if not abandonTimer then
                    abandonTimer = now
                    QBCore.Functions.Notify('Please return to the test vehicle!', 'error', 4000)
                elseif now - abandonTimer > 12000 then
                    examinerSay('You have left the test vehicle. Test terminated.', 5000)
                    endPracticalTest(false, 'Left the test vehicle', categoryLabel)
                    break
                end
            else
                abandonTimer = nil
            end

            if inVeh == veh then
                local speed = toMph(GetEntitySpeed(veh))
                local cp    = catCfg.checkpoints[practicalCheckpoint]
                local limit = cp and cp.limit or 30

                -- Speed faults
                if speed > cfg.majorSpeedMph then
                    practicalMajorFaults = practicalMajorFaults + 1
                    examinerSay('That speed is extremely dangerous. Test terminated — major fault.', 6000)
                    endPracticalTest(false, 'Dangerous speed (' .. math.floor(speed) .. ' mph)', categoryLabel)
                    break
                elseif speed > (limit + cfg.minorSpeedOver) then
                    if now - lastSpeedWarn > cfg.warningCooldown then
                        practicalMinorFaults = practicalMinorFaults + 1
                        lastSpeedWarn        = now
                        examinerSay('You are exceeding the speed limit. Minor fault recorded.', 5000)
                        QBCore.Functions.Notify('Minor fault — speeding (' .. math.floor(speed) .. ' mph in ' .. limit .. ' mph zone)', 'error', 3000)
                    end
                end

                -- Collision faults
                local bodyHealth = GetVehicleBodyHealth(veh)
                local drop       = prevBodyHealth - bodyHealth
                if drop >= cfg.collisionMajor then
                    practicalMajorFaults = practicalMajorFaults + 1
                    examinerSay('That collision was unacceptable. Major fault — test terminated.', 6000)
                    endPracticalTest(false, 'Serious collision', categoryLabel)
                    prevBodyHealth = bodyHealth
                    break
                elseif drop >= cfg.collisionMinor then
                    practicalMinorFaults = practicalMinorFaults + 1
                    examinerSay('Please be more careful. Minor fault noted.', 5000)
                    QBCore.Functions.Notify('Minor fault — vehicle contact', 'error', 3000)
                    prevBodyHealth = bodyHealth
                else
                    prevBodyHealth = bodyHealth
                end

                -- BE: trailer detachment check ─────────────────────────────
                if DoesEntityExist(practicalTrailer) then
                    local stillAttached, _ = GetVehicleTrailerVehicle(veh)
                    if not stillAttached then
                        practicalMajorFaults = practicalMajorFaults + 1
                        examinerSay('You have decoupled the trailer during the test — major fault. Test terminated.', 7000)
                        endPracticalTest(false, 'Trailer decoupled during test', categoryLabel)
                        break
                    end
                end

                -- Too many minor faults
                if practicalMinorFaults > cfg.maxMinorFaults then
                    examinerSay('Too many minor faults. Test failed.', 6000)
                    endPracticalTest(false, 'Too many minor faults (' .. practicalMinorFaults .. ')', categoryLabel)
                    break
                end

                -- Checkpoint detection
                if practicalCheckpoint <= #catCfg.checkpoints then
                    local pedCoords = GetEntityCoords(ped)
                    local dist = #(vector3(pedCoords.x, pedCoords.y, pedCoords.z) - cp.coords)
                    if dist < cp.radius then
                        practicalCheckpoint = practicalCheckpoint + 1
                        if practicalCheckpoint > #catCfg.checkpoints then
                            if practicalCpBlip then RemoveBlip(practicalCpBlip) practicalCpBlip = nil end
                            local testPassed = practicalMajorFaults == 0 and practicalMinorFaults <= cfg.maxMinorFaults
                            if testPassed then
                                examinerSay('You have completed the route! I am pleased to tell you that you have PASSED the ' .. catCfg.name .. ' test. Congratulations!', 8000)
                            else
                                examinerSay('You have completed the route. Unfortunately you have FAILED. Please see your fault summary.', 8000)
                            end
                            Wait(4000)
                            endPracticalTest(testPassed, nil, categoryLabel)
                            break
                        else
                            QBCore.Functions.Notify('Checkpoint ' .. (practicalCheckpoint - 1) .. ' reached ✓', 'success', 2500)
                            Wait(500)
                            setCheckpointBlip(catCfg)
                        end
                    end
                end
            end

            -- Time limit
            if (GetGameTimer() - testStart) > (catCfg.duration * 1000) then
                examinerSay('Time limit reached. Test terminated.', 5000)
                Wait(3000)
                endPracticalTest(false, 'Test time limit exceeded', categoryLabel)
                break
            end
        end
    end)
end

-- ──────────────────────────────────────────────────────────────────────────────
--  NUI CALLBACKS
-- ──────────────────────────────────────────────────────────────────────────────

RegisterNUICallback('closeUI', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('submitTheoryTest', function(data, cb)
    QBCore.Functions.TriggerCallback('dvla:server:submitTheory', function(result)
        cb(result)
    end, data.score, data.passed)
end)

-- Starts the AI practical test for a specific category
RegisterNUICallback('startAIPractical', function(data, cb)
    local categoryLabel = data and data.category or 'B'
    -- The server checks the test is booked (lsgov.co.uk) before the examiner spawns.
    QBCore.Functions.TriggerCallback('dvla:server:canStartPractical', function(result)
        if not result or not result.success then
            QBCore.Functions.Notify((result and result.reason) or 'You cannot start this test.', 'error', 6000)
            cb({ success = false })
            return
        end
        isOpen = false
        SendNUIMessage({ action = 'closeUI' })
        cb({ success = true })
        SetNuiFocus(false, false)
        Wait(600)
        startAIPracticalTest(categoryLabel)
    end, categoryLabel)
end)

-- Get current vehicle plate (for MOT)
RegisterNUICallback('getVehiclePlate', function(_, cb)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle ~= 0 then
        local plate = GetVehicleNumberPlateText(vehicle)
        cb({ plate = plate:match('^%s*(.-)%s*$') })
    else
        cb({ plate = '' })
    end
end)

-- Book MOT
RegisterNUICallback('bookMOT', function(data, cb)
    QBCore.Functions.TriggerCallback('dvla:server:bookMOT', function(result)
        cb(result)
    end, data.plate)
end)

-- Refresh MOT Queue (inspector)
RegisterNUICallback('getPendingMOT', function(_, cb)
    QBCore.Functions.TriggerCallback('dvla:server:getPendingMOT', function(result)
        cb(result or {})
    end)
end)

-- Complete MOT (inspector)
RegisterNUICallback('completeMOT', function(data, cb)
    QBCore.Functions.TriggerCallback('dvla:server:completeMOT', function(result)
        cb(result)
    end, data.citizenid, data.plate, data.passed, data.notes)
end)

-- Replace lost/stolen licence
RegisterNUICallback('replaceLicence', function(_, cb)
    QBCore.Functions.TriggerCallback('dvla:server:replaceLicence', function(result)
        cb(result)
    end)
end)

-- ──────────────────────────────────────────────────────────────────────────────
--  SERVER → CLIENT
-- ──────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('dvla:client:refreshPoints', function(totalPoints)
    if isOpen then
        SendNUIMessage({ action = 'updatePoints', points = totalPoints })
    end
end)

print('^2[DVLA] ^7Client script loaded.')

-- driver_license display is handled by qb-idcard — no client event needed here

-- ──────────────────────────────────────────────────────────────────────────────
--  ox_inventory: show the licence categories (and dates) in the item tooltip.
--  ox_inventory only lists metadata keys it has been told about.
-- ──────────────────────────────────────────────────────────────────────────────

local function registerLicenceMetadata()
    if GetResourceState('ox_inventory') ~= 'started' then return end
    pcall(function()
        exports.ox_inventory:displayMetadata({
            categories = 'Categories',
            issuedate  = 'Issued',
            expirydate = 'Expires',
        })
    end)
end

CreateThread(function() Wait(2000) registerLicenceMetadata() end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'ox_inventory' then Wait(1500) registerLicenceMetadata() end
end)


-- ──────────────────────────────────────────────────────────────────────────────
--  LICENCE CARD  (opens when the driver_license item is used; own design, no qbx_idcard)
-- ──────────────────────────────────────────────────────────────────────────────

local cardOpen = false

local function closeCard()
    if not cardOpen then return end
    cardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeCard' })
end

local function openCard(card, own, from)
    if isOpen then return end            -- the portal is open
    cardOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openCard', card = card, own = own == true, from = from })
end

--- Mugshot of the player, taken the first time the licence is looked at.
local function takePhoto()
    local res = (Config.Card and Config.Card.mugshotResource) or 'MugShotBase64'
    if GetResourceState(res) ~= 'started' then return nil end
    local ok, img = pcall(function() return exports[res]:GetMugShotBase64(PlayerPedId(), true) end)
    if ok and type(img) == 'string' and img ~= '' then return img end
    return nil
end

RegisterNetEvent('dvla:client:useItem', function()
    if cardOpen or isOpen then return end
    QBCore.Functions.TriggerCallback('dvla:server:getCard', function(res)
        if not res or not res.card then
            QBCore.Functions.Notify((res and res.error) or 'This licence is not readable.', 'error')
            return
        end
        if res.needPhoto then
            local img = takePhoto()
            if img then
                TriggerServerEvent('dvla:server:savePhoto', img)
                res.card.photo = img
            end
        end
        openCard(res.card, true)
    end)
end)

-- Another player held their licence up to us.
RegisterNetEvent('dvla:client:showCard', function(card, fromName)
    if cardOpen then closeCard() end
    openCard(card, false, fromName)
end)

RegisterNUICallback('closeCard', function(_, cb)
    closeCard()
    cb('ok')
end)

RegisterNUICallback('showCardNearby', function(_, cb)
    TriggerServerEvent('dvla:server:showCard')
    cb('ok')
end)

CreateThread(function()
    while true do
        Wait(cardOpen and 500 or 2000)
        if cardOpen and IsEntityDead(PlayerPedId()) then closeCard() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and cardOpen then SetNuiFocus(false, false) end
end)
