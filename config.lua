Config = {}

-- ─────────────────────────────────────────────────────────────
--  JOB PERMISSIONS
-- ─────────────────────────────────────────────────────────────

-- Jobs that can perform MOT Inspections
Config.MOTInspectorJobs = { 'mechanic', 'dvla' }

-- Jobs that can issue Penalty Points
Config.PenaltyJobs = { 'police', 'bcso', 'sasp', 'dvla' }

-- ─────────────────────────────────────────────────────────────
--  THEORY TEST
-- ─────────────────────────────────────────────────────────────
Config.TheoryTest = {
    totalQuestions = 15,
    passMark       = 12,
    timeLimit      = 480,
}

-- ─────────────────────────────────────────────────────────────
--  AI PRACTICAL TEST — SHARED SETTINGS
-- ─────────────────────────────────────────────────────────────
Config.AIPractical = {
    examinerName    = 'Mr. Ahmed',
    examinerPed     = 'a_m_m_business_01',
    maxMinorFaults  = 15,
    collisionMinor  = 150,
    collisionMajor  = 500,
    warningCooldown = 6000,
    minorSpeedOver  = 10,
    majorSpeedMph   = 70,

    -- Where the examiner/vehicle spawns
    spawnPoint = vector4(279.22, -1351.21, 31.82, 138.90),
}

-- ─────────────────────────────────────────────────────────────
--  LICENCE CATEGORIES
--
--  Each category defines:
--    label       - short code shown on licence card (e.g. "B")
--    name        - full name shown in UI
--    description - shown under the category card in the portal
--    icon        - emoji icon for the UI card
--    requires    - table of category labels that must be held first
--                  (empty table = no prerequisites)
--    vehicle     - GTA vehicle model to spawn for the test
--    vehiclePlate- plate text on the test vehicle
--    colour1/2   - primary/secondary paint colour index
--    seatIndex   - examiner seat (-1=driver 0=front-passenger)
--                  motorbike categories set this to -1 so player
--                  is placed on the bike alone (examiner follows in a car -- future)
--                  For now motorbike tests have no passenger seat so
--                  we skip spawning the examiner ped on the bike.
--    duration    - max test time in seconds
--    checkpoints - ordered list of waypoints for this category's route
-- ─────────────────────────────────────────────────────────────
Config.Categories = {

    -- ── AM ─ Moped (max 45km/h, 2 or 3 wheels / light quad) ───────────────
    {
        label       = 'AM',
        name        = 'Moped Licence',
        description = 'Ride 2/3-wheeled vehicles and light quads up to 45 km/h (28 mph).',
        icon        = '🛵',
        requires    = {},                   -- no prerequisites
        vehicle     = 'faggio3',
        vehiclePlate= 'LEARNER',
        colour1     = 111,                  -- yellow
        colour2     = 111,
        examinerInVehicle = false,          -- bike has no pillion for examiner
        duration    = 300,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },



    -- ── A1 ─ Light motorbike (up to 125cc, 11kW) ──────────────────────────
    {
        label       = 'A1',
        name        = 'Light Motorcycle Licence',
        description = 'Ride light motorbikes up to 125cc and 11 kW. Includes motor tricycles up to 15 kW.',
        icon        = '🏍️',
        requires    = { 'AM' },
        vehicle     = 'bati',
        vehiclePlate= 'LEARNER',
        colour1     = 0,                    -- black
        colour2     = 0,
        examinerInVehicle = false,
        duration    = 360,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── B ─ Car licence (no prerequisites) ─────────────────────────────────
    {
        label       = 'B',
        name        = 'Car Licence',
        description = 'Full car driving licence. Examiner rides in the passenger seat.',
        icon        = '🚗',
        requires    = {},
        vehicle     = 'sultan',
        vehiclePlate= 'LEARNER',
        colour1     = 3,                    -- white
        colour2     = 3,
        examinerInVehicle = true,           -- examiner sits in front passenger seat
        duration    = 480,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },


    -- ── A ─ Full motorcycle licence (over 35kW / over 0.2kW/kg) ──────────
    {
        label       = 'A',
        name        = 'Full Motorcycle Licence',
        description = 'Ride any motorcycle over 35 kW or power-to-weight ratio over 0.2 kW/kg. Also covers A1.',
        icon        = '🏍️',
        requires    = { 'A1' },
        vehicle     = 'bati2',
        vehiclePlate= 'LEARNER',
        colour1     = 0,
        colour2     = 0,
        examinerInVehicle = false,
        duration    = 420,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── B1 ─ Light 4-wheeled vehicle (up to 400kg / 550kg goods) ──────────
    {
        label       = 'B1',
        name        = 'Light Vehicle Licence',
        description = 'Drive 4-wheeled motor vehicles up to 400 kg unladen (550 kg if designed for goods).',
        icon        = '🚙',
        requires    = {},
        vehicle     = 'rumpo',
        vehiclePlate= 'LEARNER',
        colour1     = 66,
        colour2     = 66,
        examinerInVehicle = true,
        duration    = 420,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── BE ─ Car with trailer (up to 3,500kg MAM) ─────────────────────────
    {
        label       = 'BE',
        name        = 'Car with Trailer Licence',
        description = 'Tow a trailer up to 3,500 kg MAM with a category B vehicle.',
        icon        = '🚗',
        requires    = { 'B' },
        vehicle     = 'sultan',
        vehiclePlate= 'LEARNER',
        colour1     = 3,
        colour2     = 3,
        examinerInVehicle = true,
        -- ── Trailer config (BE-specific) ─────────────────────────────────
        trailer            = 'trailers',    -- GTA model for the test trailer
        trailerPlate       = 'TRAILER',     -- plate shown on trailer
        trailerHookTimeout = 90,            -- seconds player has to hook up trailer
        duration    = 540,                  -- slightly longer to allow hook-up time
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── C1 ─ Medium vehicle (3,500–7,500kg MAM) ───────────────────────────
    {
        label       = 'C1',
        name        = 'Medium Vehicle Licence',
        description = 'Drive vehicles between 3,500 kg and 7,500 kg MAM (with a trailer up to 750 kg).',
        icon        = '🚚',
        requires    = { 'B' },
        vehicle     = 'mule',
        vehiclePlate= 'LEARNER',
        colour1     = 28,
        colour2     = 28,
        examinerInVehicle = true,
        duration    = 480,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── C1E ─ Medium vehicle with heavy trailer (combined max 12,000kg) ───
    {
        label       = 'C1E',
        name        = 'Medium Vehicle + Trailer Licence',
        description = 'Drive C1 vehicles with a trailer over 750 kg. Combined MAM must not exceed 12,000 kg.',
        icon        = '🚚',
        requires    = { 'C1', 'BE' },
        vehicle     = 'mule',
        vehiclePlate= 'LEARNER',
        colour1     = 29,
        colour2     = 29,
        examinerInVehicle = true,
        duration    = 480,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── C ─ Large vehicle / HGV (over 3,500kg with trailer up to 750kg) ───
    {
        label       = 'C',
        name        = 'Large Vehicle Licence (HGV)',
        description = 'Drive vehicles over 3,500 kg MAM with a trailer up to 750 kg.',
        icon        = '🚛',
        requires    = { 'B' },
        vehicle     = 'phantom',
        vehiclePlate= 'LEARNER',
        colour1     = 27,
        colour2     = 0,
        examinerInVehicle = true,
        duration    = 540,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── CE ─ Large vehicle with heavy trailer ─────────────────────────────
    {
        label       = 'CE',
        name        = 'Large Vehicle + Trailer Licence',
        description = 'Drive category C vehicles with a trailer over 750 kg MAM.',
        icon        = '🚛',
        requires    = { 'C', 'BE' },
        vehicle     = 'phantom',
        vehiclePlate= 'LEARNER',
        colour1     = 27,
        colour2     = 27,
        examinerInVehicle = true,
        duration    = 540,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

    -- ── D1 ─ Minibus (up to 16 passengers, max 8 metres) ─────────────────
    {
        label       = 'D1',
        name        = 'Minibus Licence',
        description = 'Drive minibuses with up to 16 passenger seats, max length 8 metres, with a trailer up to 750 kg.',
        icon        = '🚐',
        requires    = { 'B' },
        vehicle     = 'airbus',
        vehiclePlate= 'LEARNER',
        colour1     = 55,
        colour2     = 55,
        examinerInVehicle = true,
        duration    = 540,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },


    -- ── D ─ Full bus licence (more than 8 passenger seats) ────────────────
    {
        label       = 'D',
        name        = 'Bus Licence',
        description = 'Drive any bus with more than 8 passenger seats with a trailer up to 750 kg MAM.',
        icon        = '🚌',
        requires    = { 'D1' },
        vehicle     = 'bus',
        vehiclePlate= 'LEARNER',
        colour1     = 40,
        colour2     = 40,
        examinerInVehicle = true,
        duration    = 600,
        checkpoints = {
            {
                coords      = vector3(179.89, -1402.18, 29.23),
                radius      = 16.0,
                instruction = 'Move off and head West. Keep your speed down — max 40 mph.',
                limit       = 40,
            },
            {
                coords      = vector3(72.80, -1490.12, 29.23),
                radius      = 16.0,
                instruction = 'Turn left at the junction and head South.',
                limit       = 40,
            },
            {
                coords      = vector3(79.98, -1654.76, 29.25),
                radius      = 16.0,
                instruction = 'Continue South West. Observe road markings.',
                limit       = 35,
            },
            {
                coords      = vector3(-196.79, -1445.14, 31.29),
                radius      = 16.0,
                instruction = 'Turn left here and head back North West.',
                limit       = 35,
            },
            {
                coords      = vector3(212.57, -1368.44, 30.58),
                radius      = 18.0,
                instruction = 'Return to the test centre and stop the vehicle. Well done.',
                limit       = 40,
            },
        },
    },

}
-- ─────────────────────────────────────────────────────────────
--  MOT TEST
-- ─────────────────────────────────────────────────────────────
Config.MOTTest = {
    validityMonths = 12,
}

-- ─────────────────────────────────────────────────────────────
--  PRACTICAL TEST (record label only — used in DB)
-- ─────────────────────────────────────────────────────────────
Config.PracticalTest = {
    centre = 'Driving License Centre',
}

-- ─────────────────────────────────────────────────────────────
--  PORTAL LOCATION (where players open the licence portal and take the theory test)
--  target: 'auto' (ox_target, then qb-target, then a plain "Press E" prompt), or force
--          'ox_target', 'qb-target' or 'none' (Press E prompt only)
-- ─────────────────────────────────────────────────────────────
Config.Portal = {
    target  = 'auto',
    coords  = vector3(217.99, -1390.96, 30.58),
    size    = vector3(1.5, 1.5, 3.0),   -- width, length, height
    heading = 0.0,
    label   = 'Access Licenses',
    icon    = 'fas fa-id-card',
    distance = 2.0,
}

-- ─────────────────────────────────────────────────────────────
--  LICENCE CARD (the driver_license item opens this card instead of qbx_idcard)
--  photo      = take the character's mugshot (MugShotBase64) the first time the licence is looked at
--  validYears = years a licence lasts from its issue date (0 = never expires)
-- ─────────────────────────────────────────────────────────────
Config.Card = {
    photo        = true,
    mugshotResource = 'MugShotBase64',
    authority    = 'DVLA',
    validYears   = 10,
    nationality  = 'British',     -- used when the character has no nationality
    showDistance = 3.0,
}

-- ─────────────────────────────────────────────────────────────
--  REPLACEMENT LICENCES (ordered on lsgov.co.uk, like passports)
--  mode = 'locker' sends the new licence to a Postal Prime locker the player picks (needs as-postalprime with
--         the createParcel edit). Without Postal Prime, or with mode = 'inventory', it is added to the inventory.
--  The old licence stops working as soon as the replacement is ordered.
-- ─────────────────────────────────────────────────────────────
Config.Replace = {
    mode          = 'locker',
    waitSeconds   = 1800,       -- processing time before it is sent
    prepSeconds   = 180,        -- time the locker parcel takes to be ready
    expireSeconds = 172800,     -- how long it waits in the locker. If nobody collects it, it is sent again
    sender        = 'DVLA',
    mailFrom      = { name = 'DVLA', email = 'noreply@lsgov.co.uk' },
}

-- ─────────────────────────────────────────────────────────────
--  FEES AND BOOKING (lsgov.co.uk)
--  Whole pounds. Test and replacement fees taken on lsgov.co.uk come from the bank account.
--  The MOT fee and the in-world replacement button take cash first, then bank.
-- ─────────────────────────────────────────────────────────────
Config.Fees = {
    theory    = 25,
    practical = 75,     -- per category
    mot       = 40,
    replace   = 20,
}

Config.Booking = {
    -- true = a theory or practical test can only be taken after booking (and paying) on lsgov.co.uk.
    -- false = tests stay open to everyone as before (the site still shows the licence).
    required        = true,
    -- true = a valid passport (as-passport) is needed to book a test. Skipped if as-passport isn't running.
    requirePassport = true,
}

-- ─────────────────────────────────────────────────────────────
--  PENALTY POINTS
-- ─────────────────────────────────────────────────────────────
Config.PenaltyPoints = {
    maxPoints      = 12,
    autoDisqualify = true,
}

Config.PenaltyOffences = {
    { code = 'SP30', offence = 'Exceeding statutory speed limit on a public road',            points = 3 },
    { code = 'SP50', offence = 'Exceeding speed limit on a motorway',                         points = 3 },
    { code = 'SP60', offence = 'Exceeding speed limit in a restricted road',                  points = 3 },
    { code = 'CD10', offence = 'Driving without due care and attention',                      points = 3 },
    { code = 'CD30', offence = 'Driving without reasonable consideration for other persons',  points = 3 },
    { code = 'IN10', offence = 'Using a vehicle uninsured against third party risks',         points = 6 },
    { code = 'DR10', offence = 'Driving with alcohol above the legal limit',                  points = 3 },
    { code = 'CU80', offence = 'Using a hand-held mobile phone while driving',                points = 6 },
    { code = 'TS10', offence = 'Failing to comply with traffic light signals',                points = 3 },
    { code = 'MS10', offence = 'Leaving a vehicle in a dangerous position',                   points = 3 },
    { code = 'MW10', offence = 'Contravening a motorway regulation',                          points = 3 },
    { code = 'AC10', offence = 'Failing to stop after an accident',                           points = 5 },
    { code = 'AC20', offence = 'Failing to report an accident',                               points = 5 },
    { code = 'UT50', offence = 'Aggravated taking of a vehicle',                              points = 3 },
}

Config.TheoryQuestions = {
    { question = 'What is the national speed limit on a single carriageway road for cars and motorcycles?', answers = { '50 mph', '60 mph', '70 mph', '80 mph' }, correct = 2 },
    { question = 'What does a red traffic light mean?', answers = { 'Prepare to go', 'Stop and wait behind the line', 'Slow down', 'Proceed with caution' }, correct = 2 },
    { question = 'What is the overall stopping distance at 70 mph in dry conditions?', answers = { '53 metres', '73 metres', '96 metres', '116 metres' }, correct = 3 },
    { question = 'What is the minimum legal tread depth for car tyres?', answers = { '1 mm', '1.6 mm', '2 mm', '3 mm' }, correct = 2 },
    { question = 'What shape are warning signs on UK roads?', answers = { 'Circle', 'Rectangle', 'Triangle', 'Octagon' }, correct = 3 },
    { question = 'What does a solid white centre line on the road mean?', answers = { 'You may overtake if safe', 'Do not cross or straddle it', 'Park on the left only', 'Road narrows ahead' }, correct = 2 },
    { question = 'When are you permitted to use your horn?', answers = { 'To greet someone you know', 'To warn others of your presence', 'When stationary in a traffic jam', 'When another driver annoys you' }, correct = 2 },
    { question = 'What is the speed limit in a built-up area unless otherwise signed?', answers = { '20 mph', '30 mph', '40 mph', '50 mph' }, correct = 2 },
    { question = 'Which lane should you use on a motorway when not overtaking?', answers = { 'Any available lane', 'The middle lane', 'The right-hand lane', 'The left-hand lane' }, correct = 4 },
    { question = 'What does a flashing amber beacon on a slow-moving vehicle indicate?', answers = { 'Emergency vehicle', 'Maintenance or slow-moving vehicle', 'Police vehicle', 'Road closure ahead' }, correct = 2 },
    { question = 'What does a yellow box junction mean?', answers = { 'Free to enter at all times', 'Do not enter unless your exit is clear', 'Yield to pedestrians only', 'No waiting at any time' }, correct = 2 },
    { question = 'How far from a junction must you not park?', answers = { '5 metres', '10 metres', '15 metres', '20 metres' }, correct = 2 },
    { question = 'At a pelican crossing showing a flashing amber light, you must:', answers = { 'Stop and wait for green', 'Proceed if road is clear', 'Give way to pedestrians on the crossing', 'Sound your horn and proceed' }, correct = 3 },
    { question = 'What is the legal breath alcohol limit for drivers in England and Wales?', answers = { '35 micrograms per 100 ml of breath', '50 micrograms per 100 ml of breath', '80 micrograms per 100 ml of breath', '20 micrograms per 100 ml of breath' }, correct = 1 },
    { question = 'What is the purpose of the two-second rule while driving?', answers = { 'Minimum overtaking distance', 'Safe following distance in dry conditions', 'Reaction time for emergency braking', 'Time required to check all mirrors' }, correct = 2 },
    { question = 'A circular sign with a red border and a number indicates:', answers = { 'Minimum speed limit', 'Maximum speed limit', 'Advisory speed', 'End of speed restriction' }, correct = 2 },
    { question = 'When should you use rear fog lights?', answers = { 'Whenever it rains', 'When visibility drops below 100 metres', 'During dusk and dawn', 'On unlit rural roads at night' }, correct = 2 },
    { question = 'What is the maximum speed limit on a motorway for cars?', answers = { '60 mph', '70 mph', '80 mph', '90 mph' }, correct = 2 },
    { question = 'Who has priority at a roundabout?', answers = { 'Vehicles entering the roundabout', 'Vehicles already on the roundabout', 'The largest vehicle', 'Vehicles from the right' }, correct = 2 },
    { question = 'What should you do if you feel drowsy while driving on a motorway?', answers = { 'Open the window and continue', 'Turn up the radio', 'Pull off at the next services and rest', 'Increase speed to reach your destination faster' }, correct = 3 },
    { question = 'A zebra crossing is identified by:', answers = { 'Traffic lights and a bleep', 'Black and white poles with zigzag lines', 'A push-button panel for pedestrians', 'Green paint on the road' }, correct = 2 },
    { question = 'When leaving a roundabout, when should you signal left?', answers = { 'No signal needed', 'After passing the exit before yours', 'As soon as you join the roundabout', 'Only if traffic is waiting to enter' }, correct = 2 },
    { question = 'A red X sign above a motorway lane means:', answers = { 'Lane reserved for HGVs', 'Lane closed — do not use', 'Reduced speed limit applies in this lane', 'Merge into adjacent lane' }, correct = 2 },
    { question = 'In icy conditions, stopping distances can be up to how many times greater?', answers = { 'Two times', 'Five times', 'Ten times', 'Twenty times' }, correct = 3 },
    { question = 'From what age can you apply for a provisional driving licence?', answers = { '15', '15 years and 9 months', '16', '17' }, correct = 2 },
    { question = 'What is the minimum legal insurance requirement to drive on UK roads?', answers = { 'Fully comprehensive', 'Third party, fire and theft', 'Third party only', 'No insurance is required for short journeys' }, correct = 3 },
    { question = 'You are approaching a level crossing with no barriers. You should:', answers = { 'Accelerate to cross quickly', 'Sound horn and proceed', 'Look, listen and give way to trains', 'Flash lights to warn any train' }, correct = 3 },
    { question = 'A broken white line in the centre of the road means:', answers = { 'No overtaking permitted', 'Overtaking permitted if it is safe to do so', 'One-way road ahead', 'Lane reserved for turning right' }, correct = 2 },
    { question = 'When joining a motorway from a slip road, you should:', answers = { 'Stop and wait for a gap', 'Match speed with motorway traffic and merge', 'Flash your lights to signal your intention', 'Sound your horn before merging' }, correct = 2 },
    { question = 'You must not use a hand-held mobile phone while driving because:', answers = { 'It may damage the phone', 'It is illegal and significantly increases crash risk', 'It affects your GPS signal', 'It drains the vehicle battery' }, correct = 2 },
}
