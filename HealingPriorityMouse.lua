local ADDON_NAME = ...
local ADDON_VERSION = "1.0.14"

HealingPriorityMouseDB = HealingPriorityMouseDB or {}

local defaults = {
    enabled = true,
    scale = 1.0,
    opacity = 1.0,
    showSpellNames = false,
    spellNamePosition = "bottom", -- bottom | top
    showCharges = true,
    showGlows = true,
    glowDebug = false,
    devLiveLogging = false,
    customTrackedSpells = {},
    customTrackedSpellsByCharacter = {},
    customTrackedSpecsInitializedByCharacter = {},
}

local DEV_LOG_MAX_LINES = 300
local devLogLines = {}
local debugLogWindow
local debugLogScroll
local debugLogEditBox
local lastLiveLogSignature

local function getLogTimestamp()
    if date then
        local ok, stamp = pcall(date, "%H:%M:%S")
        if ok and stamp then
            return stamp
        end
    end
    return "--:--:--"
end

local function updateDebugLogWindowText()
    if not (debugLogEditBox and debugLogScroll) then
        return
    end

    debugLogEditBox:SetText(table.concat(devLogLines, "\n"))

    local scrollHeight = debugLogScroll:GetHeight() or 0
    local textHeight = debugLogEditBox:GetHeight() or 0
    debugLogScroll:SetVerticalScroll(math.max(0, textHeight - scrollHeight))
end

local function appendDevLogLine(text)
    local line = "[" .. getLogTimestamp() .. "] " .. tostring(text or "")
    devLogLines[#devLogLines + 1] = line
    while #devLogLines > DEV_LOG_MAX_LINES do
        table.remove(devLogLines, 1)
    end
    updateDebugLogWindowText()
end

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function msg(text)
    appendDevLogLine("MSG: " .. tostring(text))
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffHealingPriorityMouse|r: " .. tostring(text))
end

local function getSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if GetSpellInfo then
        return GetSpellInfo(spellID)
    end
end

local function getSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return GetSpellTexture(spellID)
end

-- Candidate spell IDs per concept. First valid spell on current client is used.
local SPELLS = {
    Lifebloom = { 33763 },
    CenarionWard = { 102351 },

    Consecration = { 26573 },
    ConsecrationAura = { 188370 },
    InfusionOfLight = { 54149 },
    HolyBulwark = { 432459, 432472 },

    RenewingMist = { 115151 },
    StrengthOfTheBlackOx = { 443112 },

    WaterShield = { 52127, 79949, 36816, 52128, 79950, 127939, 173164, 235976, 289211, 412686, 412687 },
    HealingStreamTotem = { 5394, 392915, 392916 },
    HealingRain = { 73920 },
    Riptide = { 61295 },
    -- Cloudburst Totem (157153) was removed in patch 12.0.0.
    CloudburstTotem = { 157153 },

    Reversion = { 366155 },
    Echo = { 364343 },
    Lifespark = { 443176 },

    Atonement = { 194384 },
    PowerWordShield = { 17 },
    PowerWordRadiance = { 194509 },
    Penance = { 47540 },
    PrayerOfMending = { 33076 },
    Halo = { 120517 },
    Lightweaver = { 390993 },
    Premonitions = { 428933, 428934, 438733, 438855 },
}

local resolvedSpells = {}

local GLOW_RULES = {
    RenewingMist = {
        mode = "chargesAtMax",
    },
    PowerWordRadiance = {
        mode = "chargesAtMax",
    },
    Penance = {
        mode = "chargesAtMax",
    },
    Lightweaver = {
        mode = "stackAtLeast",
        threshold = 2,
        stackSource = "entry",
    },
}

local glowDebugState = {}
local glowStateCache = {}
local GLOW_CACHE_TTL = 120.0
local CHARGE_CACHE_TTL = 12.0
local CHARGE_SPEND_DISPLAY_WINDOW = 1.2
local POWER_WORD_SHIELD_CAST_GUARD_WINDOW = 0.9
local GROUP_AURA_REFRESH_INTERVAL = 0.12
local lastGroupAuraRefresh = 0
local updateCachedGlowState
local getSafeCharges
local resolveSpellID

local function getNowTime()
    if GetTime then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then
            return now
        end
    end
    return 0
end

local function getCachedGlowState(spellID)
    local state = glowStateCache[spellID]
    if not state then
        return nil
    end
    local age = getNowTime() - (state.time or 0)
    if age > GLOW_CACHE_TTL then
        return nil
    end
    return state
end

local function getRecentChargeState(spellID)
    local state = getCachedGlowState(spellID)
    if not state then
        return nil
    end
    if not (state.current and state.max) then
        return nil
    end

    local chargeTime = state.chargeTime or state.time or 0
    local age = getNowTime() - chargeTime
    local ttl = CHARGE_CACHE_TTL
    local rechargeDuration = state.rechargeDuration
    local current = state.current
    local max = state.max
    local chargeModRate = state.chargeModRate
    if not chargeModRate or chargeModRate <= 0 then
        chargeModRate = 1
    end
    if rechargeDuration and rechargeDuration > 0 and current and max and max >= current then
        local missingCharges = max - current
        if missingCharges > 0 then
            ttl = math.max(ttl, ((rechargeDuration / chargeModRate) * missingCharges) + 1)
        end
    end
    if age > ttl then
        return nil
    end
    return state
end

local function estimateChargeStateFromCache(spellID)
    local state = getRecentChargeState(spellID)
    if not state then
        return nil
    end

    local function gt(left, right)
        local ok, result = pcall(function()
            return left > right
        end)
        return ok and result or false
    end

    local function le(left, right)
        local ok, result = pcall(function()
            return left <= right
        end)
        return ok and result or false
    end

    local current = state.current
    local max = state.max
    if not (current and max and gt(max, 0)) then
        return state
    end

    local rechargeStart = state.rechargeStart
    local rechargeDuration = state.rechargeDuration
    if not (rechargeStart and rechargeDuration and gt(rechargeDuration, 0)) then
        return state
    end
    if le(rechargeStart, 0) then
        return state
    end

    local chargeModRate = state.chargeModRate
    if not (chargeModRate and gt(chargeModRate, 0)) then
        chargeModRate = 1
    end

    local now = getNowTime()
    if le(now, rechargeStart) then
        return state
    end

    local elapsed = now - rechargeStart
    local effectiveElapsed = elapsed * chargeModRate
    local gainedCharges = math.floor(effectiveElapsed / rechargeDuration)
    if gainedCharges <= 0 then
        return state
    end

    local newCurrent = math.min(max, current + gainedCharges)
    local patch = {
        current = newCurrent,
        max = max,
        chargeTime = now,
        chargeModRate = chargeModRate,
    }

    if newCurrent < max then
        local elapsedAfterGain = effectiveElapsed - (gainedCharges * rechargeDuration)
        patch.rechargeStart = now - (elapsedAfterGain / chargeModRate)
        patch.rechargeDuration = rechargeDuration
    else
        patch.rechargeStart = nil
        patch.rechargeDuration = nil
    end

    updateCachedGlowState(spellID, patch)
    return getRecentChargeState(spellID)
end

local function cacheChargeState(spellID, chargeState)
    if not spellID or not chargeState then
        return
    end
    local current = chargeState.current
    local max = chargeState.max
    if not (current and max) then
        return
    end
    updateCachedGlowState(spellID, {
        current = current,
        max = max,
        rechargeStart = chargeState.rechargeStart,
        rechargeDuration = chargeState.rechargeDuration,
        chargeModRate = chargeState.chargeModRate,
        chargeTime = getNowTime(),
    })
end

updateCachedGlowState = function(spellID, patch)
    if not spellID then
        return
    end
    local state = glowStateCache[spellID] or {}
    for key, value in pairs(patch) do
        state[key] = value
    end
    state.time = getNowTime()
    glowStateCache[spellID] = state
end

resolveSpellID = function(key)
    if resolvedSpells[key] ~= nil then
        return resolvedSpells[key]
    end
    local ids = SPELLS[key]
    if not ids then
        resolvedSpells[key] = false
        return false
    end
    for _, spellID in ipairs(ids) do
        local name = getSpellName(spellID)
        if name and name ~= "" then
            resolvedSpells[key] = spellID
            return spellID
        end
    end
    resolvedSpells[key] = false
    return false
end

local function resolveAnySpellID(keys)
    for _, key in ipairs(keys) do
        local spellID = resolveSpellID(key)
        if spellID then
            return spellID
        end
    end
    return false
end

local function isAuraActive(unit, spellID, helpful, fromPlayer)
    if not unit or not UnitExists(unit) then
        return false
    end
    local spellName = getSpellName(spellID)
    if not spellName then
        return false
    end
    local baseFilter = helpful and "HELPFUL" or "HARMFUL"

    local function hasAuraForFilter(filter)
        if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
            return false
        end
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, filter)
        if not ok then
            return false
        end
        local nilOk, isNil = pcall(function()
            return aura == nil
        end)
        if not nilOk or isNil then
            return false
        end

        if not fromPlayer then
            return true
        end

        if type(filter) == "string" and string.find(filter, "|PLAYER", 1, true) then
            return true
        end

        local sourceOk, isPlayerSource = pcall(function()
            return aura and aura.sourceUnit == "player"
        end)
        return sourceOk and isPlayerSource or false
    end

    if fromPlayer and hasAuraForFilter(baseFilter .. "|PLAYER") then
        return true
    end

    if hasAuraForFilter(baseFilter) then
        return true
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return false
    end
    return false
end

local function isPlayerTotemActive(spellID)
    if not spellID or not GetTotemInfo then
        return false
    end

    local spellName = getSpellName(spellID)
    if not spellName or spellName == "" then
        return false
    end

    local now = 0
    if GetTime then
        local okNow, nowValue = pcall(GetTime)
        if okNow and type(nowValue) == "number" then
            now = nowValue
        end
    end

    for slot = 1, 4 do
        local ok, haveTotem, totemName, startTime, duration = pcall(GetTotemInfo, slot)
        if ok and haveTotem and totemName == spellName then
            local startN = tonumber(startTime) or 0
            local durationN = tonumber(duration) or 0
            if durationN > 0 and (startN + durationN) > now then
                return true
            end
            return true
        end
    end

    return false
end

local function getFriendlyMouseover()
    if not UnitExists("mouseover") then
        return nil
    end
    if not UnitCanAssist("player", "mouseover") then
        return nil
    end
    if UnitIsDeadOrGhost("mouseover") then
        return nil
    end
    return "mouseover"
end

local function plainNumber(value)
    local isNilOk, isNil = pcall(function()
        return value == nil
    end)
    if isNilOk and isNil then
        return nil
    end
    -- Midnight can return protected/secret numeric values; force a plain number safely.
    local ok, n = pcall(function()
        return value + 0
    end)
    if ok and type(n) == "number" then
        local cmpOk = pcall(function()
            return n <= 0
        end)
        if cmpOk then
            return n
        end
    end

    local ok2, n2 = pcall(tonumber, value)
    if ok2 and type(n2) == "number" then
        local cmpOk = pcall(function()
            return n2 <= 0
        end)
        if cmpOk then
            return n2
        end
    end
    return nil
end

local function isNilValue(value)
    local ok, result = pcall(function()
        return value == nil
    end)
    if ok then
        return result
    end
    return false
end

local function numberLE(value, limit)
    local ok, result = pcall(function()
        return value <= limit
    end)
    return ok and result or false
end

local function numberGT(value, limit)
    local ok, result = pcall(function()
        return value > limit
    end)
    return ok and result or false
end

local function numberGE(value, limit)
    local ok, result = pcall(function()
        return value >= limit
    end)
    return ok and result or false
end

local function isTrueFlag(value, default)
    local ok, result = pcall(function()
        return value == true
    end)
    if ok then
        return result
    end
    return default or false
end

local function isFalseFlag(value, default)
    local ok, result = pcall(function()
        return value == false
    end)
    if ok then
        return result
    end
    return default or false
end

local function isNodeRankActive(nodeInfo)
    if not nodeInfo then
        return false
    end
    -- Talent node ranks can also be protected/secret values in Midnight.
    local ranksPurchased = plainNumber(nodeInfo.ranksPurchased) or 0
    local activeRank = plainNumber(nodeInfo.activeRank) or 0
    return numberGT(ranksPurchased, 0) or numberGT(activeRank, 0)
end

getSafeCharges = function(spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then
        if GetSpellCharges then
            local okLegacy, currentLegacy, maxLegacy, cooldownStartLegacy, cooldownDurationLegacy, chargeModRateLegacy = pcall(GetSpellCharges, spellID)
            if okLegacy then
                local currentLegacyN = plainNumber(currentLegacy)
                local maxLegacyN = plainNumber(maxLegacy)
                local cooldownStartLegacyN = plainNumber(cooldownStartLegacy)
                local cooldownDurationLegacyN = plainNumber(cooldownDurationLegacy)
                local chargeModRateLegacyN = plainNumber(chargeModRateLegacy)
                if currentLegacyN and maxLegacyN then
                    return {
                        current = currentLegacyN,
                        max = maxLegacyN,
                        rechargeStart = cooldownStartLegacyN,
                        rechargeDuration = cooldownDurationLegacyN,
                        chargeModRate = chargeModRateLegacyN,
                        unknown = false,
                    }
                end
            end
        end
        return nil
    end

    local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or type(charges) ~= "table" then
        return nil
    end

    local current = plainNumber(charges.currentCharges)
    local max = plainNumber(charges.maxCharges)
    local cooldownStart = plainNumber(charges.cooldownStartTime)
    local cooldownDuration = plainNumber(charges.cooldownDuration)
    local chargeModRate = plainNumber(charges.chargeModRate)

    if current and max then
        return {
            current = current,
            max = max,
            rechargeStart = cooldownStart,
            rechargeDuration = cooldownDuration,
            chargeModRate = chargeModRate,
            unknown = false,
        }
    end

    if GetSpellCharges then
        local okLegacy, currentLegacy, maxLegacy, cooldownStartLegacy, cooldownDurationLegacy, chargeModRateLegacy = pcall(GetSpellCharges, spellID)
        if okLegacy then
            local currentLegacyN = plainNumber(currentLegacy)
            local maxLegacyN = plainNumber(maxLegacy)
            local cooldownStartLegacyN = plainNumber(cooldownStartLegacy)
            local cooldownDurationLegacyN = plainNumber(cooldownDurationLegacy)
            local chargeModRateLegacyN = plainNumber(chargeModRateLegacy)
            if currentLegacyN and maxLegacyN then
                return {
                    current = currentLegacyN,
                    max = maxLegacyN,
                    rechargeStart = cooldownStartLegacyN,
                    rechargeDuration = cooldownDurationLegacyN,
                    chargeModRate = chargeModRateLegacyN,
                    unknown = false,
                }
            end
        end
    end

    if not isNilValue(charges.currentCharges) or not isNilValue(charges.maxCharges) then
        return {
            unknown = true,
        }
    end

    return nil
end

local function getDisplayChargeState(spellID)
    local estimated = estimateChargeStateFromCache(spellID)
    local cached = getCachedGlowState(spellID)
    local charges = getSafeCharges(spellID)
    local current = charges and charges.current
    local max = charges and charges.max
    local recentSpend = false

    if cached and cached.lastSpendTime then
        recentSpend = numberLE(getNowTime() - cached.lastSpendTime, CHARGE_SPEND_DISPLAY_WINDOW)
    end

    if charges and not charges.unknown and current and max then
        if estimated and estimated.current and estimated.max
            and numberGT(estimated.max, 1)
            and estimated.max == max then
            if numberGT(estimated.current, current) then
                return estimated
            end
            if recentSpend and numberGT(current, estimated.current) then
                return estimated
            end
        end
        cacheChargeState(spellID, charges)
        return charges
    end

    if estimated and estimated.current and estimated.max and numberGT(estimated.max, 1) then
        return estimated
    end

    return charges
end

local function shouldShowCooldownSwipe(spellID)
    local charges = getDisplayChargeState(spellID)
    local max = charges and charges.max
    if charges and not charges.unknown and max and numberGT(max, 1) then
        return false
    end
    return true
end

local function sanitizeCustomTrackedSpellsInDB()
    local db = HealingPriorityMouseDB

    local playerName, realmName = UnitFullName("player")
    playerName = playerName or UnitName("player") or "Unknown"
    realmName = realmName or GetRealmName() or "Unknown"
    local characterKey = tostring(playerName) .. "-" .. tostring(realmName)

    if type(db.customTrackedSpellsByCharacter) ~= "table" then
        db.customTrackedSpellsByCharacter = {}
    end
    if type(db.customTrackedSpecsInitializedByCharacter) ~= "table" then
        db.customTrackedSpecsInitializedByCharacter = {}
    end
    if type(db.customTrackedSpecsInitializedByCharacter[characterKey]) ~= "table" then
        db.customTrackedSpecsInitializedByCharacter[characterKey] = {}
    end

    local activeList = db.customTrackedSpellsByCharacter[characterKey]
    if type(activeList) ~= "table" then
        activeList = {}
        db.customTrackedSpellsByCharacter[characterKey] = activeList
    end

    local migrationList = db.customTrackedSpells
    if type(migrationList) == "table" and #migrationList > 0 and #activeList == 0 then
        for _, value in ipairs(migrationList) do
            activeList[#activeList + 1] = value
        end
        db.customTrackedSpells = {}
    elseif type(db.customTrackedSpells) ~= "table" then
        db.customTrackedSpells = {}
    end

    local normalized = {}
    local seen = {}
    for _, value in ipairs(activeList) do
        local spellID = plainNumber(value)
        if spellID
            and numberGT(spellID, 0)
            and not seen[spellID]
            and not (isReservedCoreTrackedSpellID and isReservedCoreTrackedSpellID(spellID)) then
            seen[spellID] = true
            normalized[#normalized + 1] = spellID
        end
    end

    db.customTrackedSpellsByCharacter[characterKey] = normalized
    return db.customTrackedSpellsByCharacter[characterKey]
end

local function getCustomTrackedSpells()
    if not HealingPriorityMouseDB then
        return {}
    end
    return sanitizeCustomTrackedSpellsInDB()
end

local function isSpellInTrackedList(spellID)
    if not spellID then
        return false
    end
    local tracked = getCustomTrackedSpells()
    for _, existing in ipairs(tracked) do
        if existing == spellID then
            return true
        end
    end
    return false
end

local function isValidSpellID(spellID)
    if not spellID then
        return false
    end
    local name = getSpellName(spellID)
    if name and name ~= "" then
        return true
    end
    return false
end

local function getSpellLabel(spellID)
    local name = getSpellName(spellID)
    if name and name ~= "" then
        return name .. " (" .. tostring(spellID) .. ")"
    end
    return "Unknown spell (" .. tostring(spellID) .. ")"
end

local isSpellKnownSafe

local function addSpellOption(options, seen, spellID)
    local id = plainNumber(spellID)
    if not id or not numberGT(id, 0) or seen[id] then
        return
    end
    if isReservedCoreTrackedSpellID and isReservedCoreTrackedSpellID(id) then
        return
    end
    if isSpellInTrackedList(id) then
        return
    end
    if not isSpellKnownSafe(id) then
        return
    end
    local isPassive = false
    if IsPassiveSpell then
        local okPassive, resultPassive = pcall(IsPassiveSpell, id)
        if okPassive and resultPassive then
            isPassive = true
        end
    end
    if isPassive then
        return
    end

    seen[id] = true
    options[#options + 1] = {
        spellID = id,
        label = getSpellLabel(id),
    }
end

local CLASS_SPELL_KEYS = {
    DRUID = { "Lifebloom", "CenarionWard" },
    PALADIN = { "Consecration", "HolyBulwark" },
    MONK = { "RenewingMist", "StrengthOfTheBlackOx" },
    SHAMAN = { "WaterShield", "HealingStreamTotem", "HealingRain", "Riptide", "CloudburstTotem" },
    EVOKER = { "Reversion", "Echo", "Lifespark" },
    PRIEST = { "Atonement", "PowerWordShield", "PrayerOfMending", "Halo", "Lightweaver", "Premonitions" },
}

local getSpecID
local isReservedCoreTrackedSpellID

local SPEC_CUSTOM_SPELL_IDS = {
    [105] = { -- Restoration Druid
        774,    -- Rejuvenation
        8936,   -- Regrowth
        18562,  -- Swiftmend
        48438,  -- Wild Growth
        33763,  -- Lifebloom
        145205, -- Efflorescence
        102342, -- Ironbark
        740,    -- Tranquility
        102351, -- Cenarion Ward
        188550, -- Lifebloom (Photosynthesis interactions still same spell id)
    },
    [65] = { -- Holy Paladin
        82326,  -- Holy Light
        19750,  -- Flash of Light
        85673,  -- Word of Glory
        20473,  -- Holy Shock
        53563,  -- Beacon of Light
        1022,   -- Blessing of Protection
        633,    -- Lay on Hands
        26573,  -- Consecration
    },
    [270] = { -- Mistweaver Monk
        115151, -- Renewing Mist
        116670, -- Vivify
        124682, -- Enveloping Mist
        115175, -- Soothing Mist
        116849, -- Life Cocoon
        322101, -- Invoke Yu'lon
    },
    [264] = { -- Restoration Shaman
        5394,   -- Healing Stream Totem
        61295,  -- Riptide
        73920,  -- Healing Rain
        1064,   -- Chain Heal
        77472,  -- Healing Wave
        8004,   -- Healing Surge
        98008,  -- Spirit Link Totem
        108280, -- Healing Tide Totem
    },
    [1468] = { -- Preservation Evoker
        366155, -- Reversion
        364343, -- Echo
        355936, -- Dream Breath
        361469, -- Living Flame
        367226, -- Spiritbloom
        370537, -- Stasis
    },
    [256] = { -- Discipline Priest
        17,     -- Power Word: Shield
        194509, -- Power Word: Radiance
        47540,  -- Penance
        585,    -- Smite
        194384, -- Atonement
        62618,  -- Power Word: Barrier
    },
    [257] = { -- Holy Priest
        2061,   -- Flash Heal
        2050,   -- Holy Word: Serenity
        34861,  -- Holy Word: Sanctify
        33076,  -- Prayer of Mending
        120517, -- Halo
        596,    -- Prayer of Healing
    },
}

local CORE_SPELL_KEYS_BY_SPEC = {
    [105] = { "Lifebloom", "CenarionWard" },
    [65] = { "Consecration", "InfusionOfLight", "HolyBulwark" },
    [270] = { "RenewingMist", "StrengthOfTheBlackOx" },
    [264] = { "WaterShield", "HealingStreamTotem", "HealingRain", "Riptide", "CloudburstTotem" },
    [1468] = { "Reversion", "Echo", "Lifespark" },
    [256] = { "Atonement", "PowerWordShield", "PowerWordRadiance", "Penance" },
    [257] = { "PrayerOfMending", "Halo", "Lightweaver", "Premonitions" },
}

isReservedCoreTrackedSpellID = function(spellID)
    local id = plainNumber(spellID)
    if not id or not numberGT(id, 0) then
        return false
    end

    for _, keys in pairs(CORE_SPELL_KEYS_BY_SPEC) do
        for _, key in ipairs(keys) do
            local resolvedID = resolveSpellID(key)
            if resolvedID and resolvedID == id then
                return true
            end
        end
    end

    return false
end

local function collectKnownClassSpellOptions()
    local options = {}
    local seen = {}

    local specID = getSpecID()
    local specSpellIDs = SPEC_CUSTOM_SPELL_IDS[specID] or {}
    for _, spellID in ipairs(specSpellIDs) do
        addSpellOption(options, seen, spellID)
    end

    local classToken = select(2, UnitClass("player"))
    local classKeys = CLASS_SPELL_KEYS[classToken] or {}

    for _, key in ipairs(classKeys) do
        local spellID = resolveSpellID(key)
        addSpellOption(options, seen, spellID)
    end

    table.sort(options, function(left, right)
        return string.lower(left.label or "") < string.lower(right.label or "")
    end)

    return options
end

local function addCustomTrackedSpell(spellID)
    local id = plainNumber(spellID)
    if not id or not numberGT(id, 0) then
        return false, "invalid"
    end
    if isReservedCoreTrackedSpellID and isReservedCoreTrackedSpellID(id) then
        return false, "core-managed"
    end
    if not isValidSpellID(id) then
        return false, "not-found"
    end

    local spells = getCustomTrackedSpells()
    for _, existing in ipairs(spells) do
        if existing == id then
            return false, "duplicate"
        end
    end

    spells[#spells + 1] = id
    return true
end

local function ensureDefaultTrackedSpellsForActiveSpec()
    sanitizeCustomTrackedSpellsInDB()
end

local function removeCustomTrackedSpell(spellID)
    local id = plainNumber(spellID)
    if not id then
        return false
    end

    local spells = getCustomTrackedSpells()
    local removed = false
    local filtered = {}
    for _, existing in ipairs(spells) do
        if existing == id and not removed then
            removed = true
        else
            filtered[#filtered + 1] = existing
        end
    end

    if removed then
        local activeSpells = getCustomTrackedSpells()
        for i = #activeSpells, 1, -1 do
            activeSpells[i] = nil
        end
        for _, value in ipairs(filtered) do
            activeSpells[#activeSpells + 1] = value
        end
    end
    return removed
end

local function getAuraStackCountSafe(unit, spellID, helpful, fromPlayer)
    if not unit or not UnitExists(unit) then
        return nil
    end

    local spellName = getSpellName(spellID)
    if not spellName then
        return nil
    end

    local filter = helpful and "HELPFUL" or "HARMFUL"
    if fromPlayer then
        filter = filter .. "|PLAYER"
    end

    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return nil
    end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, filter)
    if not ok then
        return nil
    end

    local nilOk, isNil = pcall(function()
        return aura == nil
    end)
    if nilOk and isNil then
        return 0
    end

    if type(aura) ~= "table" then
        return nil
    end

    local applications = plainNumber(aura.applications)
    if applications then
        return applications
    end

    if not isNilValue(aura.applications) then
        return nil
    end

    return 1
end

local function logGlowDecision(entry, shouldGlow, reason)
    if not (HealingPriorityMouseDB and HealingPriorityMouseDB.glowDebug) then
        return
    end

    local key = tostring(entry and entry.name or "?") .. ":" .. tostring(entry and entry.spellID or "?")
    local signature = tostring(shouldGlow and true or false) .. "|" .. tostring(reason or "")
    if glowDebugState[key] == signature then
        return
    end
    glowDebugState[key] = signature
    msg("glow " .. key .. " => " .. (shouldGlow and "on" or "off") .. " (" .. tostring(reason or "n/a") .. ")")
end

local function shouldGlowEntry(entry)
    if not (HealingPriorityMouseDB and HealingPriorityMouseDB.showGlows) then
        return false
    end

    if not entry or not entry.glowRule then
        return false
    end

    local rule = GLOW_RULES[entry.glowRule]
    if not rule then
        return false
    end

    if rule.mode == "chargesAtMax" then
        local charges = getDisplayChargeState(entry.spellID)
        local current = charges and charges.current
        local max = charges and charges.max

        if charges and not charges.unknown and current and max then
            cacheChargeState(entry.spellID, charges)
        elseif not charges then
            logGlowDecision(entry, false, "charges-missing")
            return false
        elseif charges.unknown then
            if InCombatLockdown and InCombatLockdown() then
                local cached = estimateChargeStateFromCache(entry.spellID)
                if cached and cached.current and cached.max then
                    current = cached.current
                    max = cached.max
                    logGlowDecision(entry, false, "charges-unknown-use-cached")
                else
                    logGlowDecision(entry, false, "charges-unknown")
                    return false
                end
            else
                logGlowDecision(entry, false, "charges-unknown")
                return false
            end
        end

        if not (current and max and numberGT(max, 1)) then
            logGlowDecision(entry, false, "charges-not-multi")
            return false
        end

        local shouldGlow = numberGE(current, max)
        updateCachedGlowState(entry.spellID, {
            shouldGlow = shouldGlow,
        })
        logGlowDecision(entry, shouldGlow, shouldGlow and "charges-at-max" or "charges-below-max")
        return shouldGlow
    end

    if rule.mode == "alwaysWhenShown" then
        logGlowDecision(entry, true, "always-when-shown")
        return true
    end

    if rule.mode == "stackAtLeast" then
        local stackCount
        if rule.stackSource == "entry" then
            stackCount = entry.glowContext and plainNumber(entry.glowContext.stackCount)
        end

        if stackCount then
            updateCachedGlowState(entry.spellID, {
                stackCount = stackCount,
            })
        else
            local cached = getCachedGlowState(entry.spellID)
            if cached and cached.stackCount then
                stackCount = cached.stackCount
            end
        end

        if not stackCount then
            local auraActive = isAuraActive("player", entry.spellID, true, true)
            local cached = getCachedGlowState(entry.spellID)
            if auraActive and cached and cached.shouldGlow ~= nil then
                logGlowDecision(entry, cached.shouldGlow, "stack-missing-use-cached-decision")
                return cached.shouldGlow
            end
            logGlowDecision(entry, false, auraActive and "stack-missing-aura-active" or "stack-missing")
            return false
        end

        local threshold = plainNumber(rule.threshold) or 1
        local shouldGlow = numberGE(stackCount, threshold)
        updateCachedGlowState(entry.spellID, {
            shouldGlow = shouldGlow,
            stackCount = stackCount,
        })
        logGlowDecision(entry, shouldGlow, shouldGlow and "stack-threshold-met" or "stack-threshold-not-met")
        return shouldGlow
    end

    logGlowDecision(entry, false, "rule-unsupported")
    return false
end

isSpellKnownSafe = function(spellID)
    if not spellID then
        return false
    end

    if IsSpellKnownOrOverridesKnown then
        local ok, known = pcall(IsSpellKnownOrOverridesKnown, spellID)
        if ok and known then
            return true
        end
    end

    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then
            return true
        end
    end

    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and known then
            return true
        end
    end

    return false
end

local function isSpellUsableSafe(spellID)
    if not IsUsableSpell then
        return false
    end
    local ok, usable = pcall(function()
        return IsUsableSpell(spellID)
    end)
    if ok then
        return usable and true or false
    end
    return false
end

local function isSpellResourceUsableSafe(spellID)
    if not IsUsableSpell then
        return true
    end
    local ok, usable, noMana = pcall(IsUsableSpell, spellID)
    if not ok then
        return true
    end
    if usable then
        return true
    end
    if noMana then
        return false
    end
    return true
end

local function isCooldownDurationReady(duration, isOnGCD)
    if duration and numberLE(duration, 0) then
        return true
    end
    if isOnGCD and duration and numberLE(duration, 1.7) then
        return true
    end
    return false
end

local function getCooldownReady(spellID)
    if not isSpellKnownSafe(spellID) then
        return false
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if not ok or not info then
            return isSpellUsableSafe(spellID)
        end
        -- Midnight can return secret booleans; avoid direct truth tests on API fields.
        if isFalseFlag(info.isEnabled, false) then
            return isSpellUsableSafe(spellID)
        end
        local duration = plainNumber(info.duration)
        if duration and numberLE(duration, 0) then
            return true
        end
        if isTrueFlag(info.isOnGCD, false) and duration and numberLE(duration, 1.7) then
            return true
        end
        return isSpellUsableSafe(spellID)
    end
    return isSpellUsableSafe(spellID)
end

local function getCooldownReadyByTimer(spellID, failOpen)
    if not isSpellKnownSafe(spellID) then
        return false
    end

    local allowFailOpen = true
    if failOpen == false then
        allowFailOpen = false
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if not ok or not info then
            info = nil
        end
        if info then
            if isFalseFlag(info.isEnabled, false) then
                info = nil
            else
                local startTime = plainNumber(info.startTime)
                local duration = plainNumber(info.duration)
                local modRate = plainNumber(info.modRate)
                if not (modRate and numberGT(modRate, 0)) then
                    modRate = 1
                end
                if duration and numberLE(duration, 0) then
                    return true
                end
                if isTrueFlag(info.isOnGCD, false) and duration and numberLE(duration, 1.7) then
                    return true
                end
                if startTime and duration and numberGT(duration, 0) then
                    local now = getNowTime()
                    local effectiveDuration = duration / modRate
                    if numberLE((startTime + effectiveDuration), now + 0.05) then
                        return true
                    end
                    return false
                end
                if duration and numberGT(duration, 0) then
                    return false
                end
            end
        end
    end

    if GetSpellCooldown then
        local okLegacy, startTime, duration, enabled, modRate = pcall(GetSpellCooldown, spellID)
        if okLegacy then
            local startN = plainNumber(startTime)
            local durationN = plainNumber(duration)
            local modRateN = plainNumber(modRate)
            if not (modRateN and numberGT(modRateN, 0)) then
                modRateN = 1
            end
            if enabled == 0 then
                return allowFailOpen
            end
            if durationN and numberLE(durationN, 0) then
                return true
            end
            if startN and durationN and numberGT(durationN, 0) then
                local now = getNowTime()
                local effectiveDuration = durationN / modRateN
                if numberLE((startN + effectiveDuration), now + 0.05) then
                    return true
                end
                return false
            end
        end
    end

    return allowFailOpen
end

local function getGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
        end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
    else
        units[#units + 1] = "player"
    end
    return units
end

local function countAuraInGroup(spellID, fromPlayerOnly)
    local n = 0
    for _, unit in ipairs(getGroupUnits()) do
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and isAuraActive(unit, spellID, true, fromPlayerOnly) then
            n = n + 1
        end
    end
    return n
end

local function countAliveGroupUnits()
    local n = 0
    for _, unit in ipairs(getGroupUnits()) do
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            n = n + 1
        end
    end
    return n
end

getSpecID = function()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

local function getLifebloomTargetThreshold()
    return 1
end

local root = CreateFrame("Frame", "HealingPriorityMouseFrame", UIParent)
root:SetSize(1, 1)
root:SetFrameStrata("HIGH")
root:Hide()

local iconFrames = {}
local optionsFrame
local optionsControls

local function clampScale(value)
    if not value then
        return nil
    end
    if value < 0.6 then
        return 0.6
    end
    if value > 3.0 then
        return 3.0
    end
    return value
end

local function clampOpacity(value)
    if not value then
        return nil
    end
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function setScaleValue(value)
    local clamped = clampScale(value)
    if not clamped then
        return false
    end
    HealingPriorityMouseDB.scale = clamped
    return true
end

local function setOpacityPercent(value)
    if not value then
        return false
    end
    local pct = value
    if pct > 1 then
        pct = pct / 100
    end
    local clamped = clampOpacity(pct)
    if not clamped then
        return false
    end
    HealingPriorityMouseDB.opacity = clamped
    return true
end

local function ensureIcon(index)
    if iconFrames[index] then
        return iconFrames[index]
    end
    local frame = CreateFrame("Frame", nil, root, "BackdropTemplate")
    frame:SetSize(26, 26)
    frame:SetBackdrop(nil)
    frame:SetClipsChildren(false)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = tex

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawBling(false)
    cd:SetDrawSwipe(true)
    frame.cooldown = cd

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", frame, "BOTTOM", 0, -1)
    label:SetJustifyH("CENTER")
    label:Hide()
    frame.label = label

    local chargeText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    chargeText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    chargeText:SetJustifyH("RIGHT")
    chargeText:SetTextColor(1, 1, 1, 1)
    frame.chargeText = chargeText

    local glow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER", frame, "CENTER", 0, 0)
    glow:SetSize(58, 58)
    glow:SetVertexColor(1.0, 0.95, 0.35, 1.0)
    glow:SetAlpha(1.0)
    glow:Hide()
    frame.glow = glow

    local glowAnim = glow:CreateAnimationGroup()
    local fadeIn = glowAnim:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetDuration(0.45)
    fadeIn:SetFromAlpha(0.7)
    fadeIn:SetToAlpha(1.0)
    local fadeOut = glowAnim:CreateAnimation("Alpha")
    fadeOut:SetOrder(2)
    fadeOut:SetDuration(0.45)
    fadeOut:SetFromAlpha(1.0)
    fadeOut:SetToAlpha(0.7)
    glowAnim:SetLooping("REPEAT")
    frame.glowAnim = glowAnim

    iconFrames[index] = frame
    return frame
end

local function hideAllIcons()
    for _, frame in ipairs(iconFrames) do
        if frame.glowAnim and frame.glowAnim:IsPlaying() then
            frame.glowAnim:Stop()
        end
        if frame.glow then
            frame.glow:Hide()
        end
        frame.glowEnabled = false
        frame:Hide()
    end
end

local function setIconGlow(frame, enabled)
    if not frame then
        return
    end
    if frame.glowEnabled == enabled then
        return
    end
    frame.glowEnabled = enabled
    if enabled then
        if frame.glow then
            frame.glow:Show()
        end
        if frame.glowAnim and not frame.glowAnim:IsPlaying() then
            frame.glowAnim:Play()
        end
        return
    end

    if frame.glowAnim and frame.glowAnim:IsPlaying() then
        frame.glowAnim:Stop()
    end
    if frame.glow then
        frame.glow:Hide()
    end
end

local function getEssenceCount()
    -- 19 is Essence power type in modern retail.
    local essence = UnitPower("player", 19)
    return essence or 0
end

local function isAuraMissingOnMouseover(spellID)
    local mouseover = getFriendlyMouseover()
    if not mouseover then
        return true
    end
    return not isAuraActive(mouseover, spellID, true, true)
end

local function isSpellAtMaxCharges(spellID)
    local charges = getDisplayChargeState(spellID)
    local current = charges and charges.current
    local max = charges and charges.max
    return charges
        and (not charges.unknown)
        and current
        and max
        and numberGT(max, 1)
        and numberGE(current, max)
end

local LIFE_COCOON_SPELL_ID = 116849
local LIFE_COCOON_CAST_GUARD_WINDOW = 1.0

local function isRenewingMistReady(spellID)
    local charges = getSafeCharges(spellID)
    if charges and not charges.unknown then
        local current = charges.current
        local max = charges.max
        if current and max and numberGT(max, 1) then
            cacheChargeState(spellID, charges)
            return numberGT(current, 0)
        end
    end

    local cached = estimateChargeStateFromCache(spellID)
    if cached and cached.current and cached.max and numberGT(cached.max, 1) then
        return numberGT(cached.current, 0)
    end

    return getCooldownReadyByTimer(spellID, true)
end

local function isPowerWordShieldSpell(spellID)
    if not spellID then
        return false
    end

    local resolved = resolveSpellID("PowerWordShield")
    if resolved and spellID == resolved then
        return true
    end

    for _, candidate in ipairs(SPELLS.PowerWordShield or {}) do
        if candidate == spellID then
            return true
        end
    end

    local resolvedName = getSpellName(resolved or 17)
    local spellName = getSpellName(spellID)
    if resolvedName and spellName and resolvedName == spellName then
        return true
    end

    return false
end

local function isLifeCocoonSpell(spellID)
    return spellID == LIFE_COCOON_SPELL_ID
end

local function getCachedRechargeTimerReady(state)
    if not state then
        return nil
    end

    local rechargeStart = state.rechargeStart
    if not (rechargeStart and numberGT(rechargeStart, 0)) then
        rechargeStart = state.lastSpendTime
    end
    local rechargeDuration = state.rechargeDuration
    if not (rechargeStart and rechargeDuration and numberGT(rechargeDuration, 0)) then
        return nil
    end

    local chargeModRate = state.chargeModRate
    if not (chargeModRate and numberGT(chargeModRate, 0)) then
        chargeModRate = 1
    end

    local elapsed = (getNowTime() - rechargeStart) * chargeModRate
    if numberGE(elapsed + 0.05, rechargeDuration) then
        return true
    end
    return false
end

local function getPowerWordShieldCacheKeys(spellID)
    local keys = {}
    local seen = {}

    local function addKey(value)
        if not value or seen[value] then
            return
        end
        seen[value] = true
        keys[#keys + 1] = value
    end

    addKey(resolveSpellID("PowerWordShield"))
    addKey(spellID)
    for _, candidate in ipairs(SPELLS.PowerWordShield or {}) do
        addKey(candidate)
    end

    return keys
end

local function getPowerWordShieldCachedState(spellID)
    local freshest
    for _, key in ipairs(getPowerWordShieldCacheKeys(spellID)) do
        local state = getCachedGlowState(key)
        if state and ((not freshest) or ((state.time or 0) > (freshest.time or 0))) then
            freshest = state
        end
    end
    return freshest
end

local function updatePowerWordShieldCachedState(spellID, patch)
    for _, key in ipairs(getPowerWordShieldCacheKeys(spellID)) do
        updateCachedGlowState(key, patch)
    end
end

local function getPowerWordShieldDurationObjectValue(durationObject, methodName)
    if not durationObject or type(methodName) ~= "string" then
        return nil
    end
    local method = durationObject[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, durationObject)
    if not ok then
        return nil
    end
    return plainNumber(value)
end

local function getPowerWordShieldObservedCooldownDuration(state)
    if not state then
        return nil
    end

    local duration = plainNumber(state.lastObservedCooldownDuration)
    if duration and numberGT(duration, 0) then
        return duration
    end

    local rechargeDuration = plainNumber(state.rechargeDuration)
    local chargeModRate = plainNumber(state.chargeModRate)
    if rechargeDuration and numberGT(rechargeDuration, 0) then
        if not (chargeModRate and numberGT(chargeModRate, 0)) then
            chargeModRate = 1
        end
        return rechargeDuration / chargeModRate
    end

    return nil
end

local function getPowerWordShieldBaseCooldownDuration(spellID)
    if not GetSpellBaseCooldown then
        return nil
    end

    local ok, cooldownMS = pcall(GetSpellBaseCooldown, spellID)
    if not ok then
        return nil
    end

    local cooldownSeconds = plainNumber(cooldownMS)
    if cooldownSeconds and numberGT(cooldownSeconds, 0) then
        return cooldownSeconds / 1000
    end

    return nil
end

local function getPowerWordShieldCachedCooldownEndTime(state)
    if not state then
        return nil
    end

    local cooldownEndTime = plainNumber(state.cooldownEndTime)
    if cooldownEndTime and numberGT(cooldownEndTime, 0) then
        return cooldownEndTime
    end

    local rechargeStart = plainNumber(state.rechargeStart)
    local rechargeDuration = plainNumber(state.rechargeDuration)
    local chargeModRate = plainNumber(state.chargeModRate)
    if rechargeStart and rechargeDuration and numberGT(rechargeStart, 0) and numberGT(rechargeDuration, 0) then
        if not (chargeModRate and numberGT(chargeModRate, 0)) then
            chargeModRate = 1
        end
        return rechargeStart + (rechargeDuration / chargeModRate)
    end

    return nil
end

local function readPowerWordShieldLiveCooldownState(spellID)
    local now = getNowTime()

    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local okDuration, durationObject = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if okDuration and durationObject then
            local remaining = getPowerWordShieldDurationObjectValue(durationObject, "GetRemainingDuration")
            local startTime = getPowerWordShieldDurationObjectValue(durationObject, "GetStartTime")
            local duration = getPowerWordShieldDurationObjectValue(durationObject, "GetDuration")
            local modRate = getPowerWordShieldDurationObjectValue(durationObject, "GetModRate")
            if not (modRate and numberGT(modRate, 0)) then
                modRate = 1
            end

            if remaining and numberGT(remaining, 0.05) then
                local effectiveDuration = duration and numberGT(duration, 0) and (duration / modRate) or remaining
                local cooldownEndTime = now + remaining
                if startTime and numberGT(startTime, 0) and effectiveDuration and numberGT(effectiveDuration, 0) then
                    cooldownEndTime = startTime + effectiveDuration
                end
                return {
                    ready = false,
                    cooldownEndTime = cooldownEndTime,
                    effectiveDuration = effectiveDuration,
                    startTime = startTime,
                    source = "durationObject",
                }
            end

            if remaining and numberLE(remaining, 0.05) then
                return {
                    ready = true,
                    source = "durationObject",
                }
            end
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local okCooldown, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if okCooldown and type(info) == "table" and not isFalseFlag(info.isEnabled, false) then
            local startTime = plainNumber(info.startTime)
            local duration = plainNumber(info.duration)
            local modRate = plainNumber(info.modRate)
            if not (modRate and numberGT(modRate, 0)) then
                modRate = 1
            end

            if duration and numberLE(duration, 0) then
                return {
                    ready = true,
                    source = "cooldownInfo",
                }
            end

            if isTrueFlag(info.isOnGCD, false) and duration and numberLE(duration, 1.7) then
                return {
                    ready = true,
                    source = "cooldownInfo",
                }
            end

            if duration and numberGT(duration, 0) then
                local effectiveDuration = duration / modRate
                local cooldownEndTime = now + effectiveDuration
                if startTime and numberGT(startTime, 0) then
                    cooldownEndTime = startTime + effectiveDuration
                end
                if numberLE(cooldownEndTime, now + 0.05) then
                    return {
                        ready = true,
                        source = "cooldownInfo",
                    }
                end
                return {
                    ready = false,
                    cooldownEndTime = cooldownEndTime,
                    effectiveDuration = effectiveDuration,
                    startTime = startTime,
                    source = "cooldownInfo",
                }
            end
        end
    end

    if GetSpellCooldown then
        local okLegacy, startTime, duration, enabled, modRate = pcall(GetSpellCooldown, spellID)
        if okLegacy and enabled ~= 0 then
            local startN = plainNumber(startTime)
            local durationN = plainNumber(duration)
            local modRateN = plainNumber(modRate)
            if not (modRateN and numberGT(modRateN, 0)) then
                modRateN = 1
            end

            if durationN and numberLE(durationN, 0) then
                return {
                    ready = true,
                    source = "legacyCooldown",
                }
            end

            if durationN and numberGT(durationN, 0) then
                local effectiveDuration = durationN / modRateN
                local cooldownEndTime = now + effectiveDuration
                if startN and numberGT(startN, 0) then
                    cooldownEndTime = startN + effectiveDuration
                end
                if numberLE(cooldownEndTime, now + 0.05) then
                    return {
                        ready = true,
                        source = "legacyCooldown",
                    }
                end
                return {
                    ready = false,
                    cooldownEndTime = cooldownEndTime,
                    effectiveDuration = effectiveDuration,
                    startTime = startN,
                    source = "legacyCooldown",
                }
            end
        end
    end

    return nil
end

local function isLifeCocoonReady(spellID)
    local now = getNowTime()
    local cached = getCachedGlowState(spellID)
    local lastSpendTime = cached and cached.lastSpendTime
    if lastSpendTime and numberLE((now - lastSpendTime), LIFE_COCOON_CAST_GUARD_WINDOW) then
        return false
    end

    local determinedReady = nil

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and info then
            local duration = plainNumber(info.duration)
            if duration then
                if numberLE(duration, 0) then
                    determinedReady = true
                elseif isTrueFlag(info.isOnGCD, false) and numberLE(duration, 1.7) then
                    determinedReady = true
                elseif numberGT(duration, 0) then
                    determinedReady = false
                end
            end
        end
    end

    if determinedReady == nil and GetSpellCooldown then
        local okLegacy, startTime, duration = pcall(GetSpellCooldown, spellID)
        if okLegacy then
            local startN = plainNumber(startTime)
            local durationN = plainNumber(duration)
            if durationN and numberLE(durationN, 0) then
                determinedReady = true
            elseif startN and durationN and numberGT(durationN, 0) then
                local now = getNowTime()
                if numberLE((startN + durationN), now + 0.05) then
                    determinedReady = true
                else
                    determinedReady = false
                end
            end
        end
    end

    local charges = getSafeCharges(spellID)
    if charges and not charges.unknown then
        local current = charges.current
        local max = charges.max
        if current and max then
            cacheChargeState(spellID, charges)
            if numberLE(current, 0) then
                determinedReady = false
            end
        end
    end

    if determinedReady ~= nil then
        updateCachedGlowState(spellID, {
            cooldownReady = determinedReady,
        })
        return determinedReady
    end

    local cachedTimerReady = getCachedRechargeTimerReady(cached)
    if cachedTimerReady ~= nil then
        updateCachedGlowState(spellID, {
            cooldownReady = cachedTimerReady,
        })
        return cachedTimerReady
    end

    if cached and cached.cooldownReady ~= nil then
        return cached.cooldownReady and true or false
    end

    return false
end

local function isPowerWordShieldReady(spellID)
    if not isSpellKnownSafe(spellID) then
        return false
    end

    local now = getNowTime()
    local cached = getPowerWordShieldCachedState(spellID)
    local cachedEndTime = getPowerWordShieldCachedCooldownEndTime(cached)
    local lastSpendTime = cached and plainNumber(cached.lastSpendTime)
    local inCombat = InCombatLockdown and InCombatLockdown() or false
    local withinCastGuard = lastSpendTime and numberLE(now - lastSpendTime, POWER_WORD_SHIELD_CAST_GUARD_WINDOW)
    local cacheForcesHidden = false
    if cachedEndTime and numberGT(cachedEndTime, now + 0.05) and (inCombat or withinCastGuard) then
        cacheForcesHidden = true
    end

    local liveState = readPowerWordShieldLiveCooldownState(spellID)
    if liveState then
        if liveState.ready == false then
            local liveCooldownEndTime = liveState.cooldownEndTime or 0
            if cachedEndTime and numberGT(cachedEndTime, liveCooldownEndTime) then
                liveCooldownEndTime = cachedEndTime
            end
            updatePowerWordShieldCachedState(spellID, {
                cooldownReady = false,
                cooldownEndTime = liveCooldownEndTime,
                rechargeStart = liveState.startTime or 0,
                rechargeDuration = liveState.effectiveDuration or 0,
                chargeModRate = 1,
                lastObservedCooldownDuration = liveState.effectiveDuration or 0,
            })
            return false
        end

        if cacheForcesHidden then
            updatePowerWordShieldCachedState(spellID, {
                cooldownReady = false,
            })
            return false
        end

        updatePowerWordShieldCachedState(spellID, {
            cooldownReady = true,
            cooldownEndTime = 0,
            rechargeStart = 0,
            rechargeDuration = 0,
            chargeModRate = 1,
        })
        return true
    end

    if cacheForcesHidden then
        updatePowerWordShieldCachedState(spellID, {
            cooldownReady = false,
        })
        return false
    end

    if cachedEndTime then
        if numberGT(cachedEndTime, now + 0.05) then
            updatePowerWordShieldCachedState(spellID, {
                cooldownReady = false,
            })
            return false
        end

        updatePowerWordShieldCachedState(spellID, {
            cooldownReady = true,
            cooldownEndTime = 0,
            rechargeStart = 0,
            rechargeDuration = 0,
            chargeModRate = 1,
        })
        return true
    end

    if cached and cached.cooldownReady ~= nil then
        return cached.cooldownReady and true or false
    end

    return false
end

local function getAvailableMultiChargeState(spellID)
    local charges = getDisplayChargeState(spellID)
    if not charges then
        return nil
    end

    if charges.unknown then
        return false
    end

    local current = charges.current
    local max = charges.max
    if current and max and numberGT(max, 1) then
        cacheChargeState(spellID, charges)
        return numberGT(current, 0)
    end

    return nil
end

local function applyChargeSpendToCache(spellID, liveCharges)
    local displayCharges = getDisplayChargeState(spellID)
    if not displayCharges then
        return
    end

    local current = displayCharges.current
    local max = displayCharges.max
    if not (current and max and numberGT(max, 1)) then
        return
    end

    local now = getNowTime()
    local newCurrent = current
    local liveCurrent = liveCharges and liveCharges.current
    local liveMax = liveCharges and liveCharges.max
    if liveCurrent and liveMax and liveMax == max and numberGT(current, liveCurrent) then
        newCurrent = liveCurrent
    elseif numberGT(newCurrent, 0) then
        newCurrent = newCurrent - 1
    end

    local rechargeDuration = (liveCharges and liveCharges.rechargeDuration) or displayCharges.rechargeDuration
    local rechargeStart = (liveCharges and liveCharges.rechargeStart) or displayCharges.rechargeStart
    local chargeModRate = (liveCharges and liveCharges.chargeModRate) or displayCharges.chargeModRate
    local patch = {
        current = newCurrent,
        max = max,
        rechargeDuration = rechargeDuration,
        chargeModRate = chargeModRate,
        chargeTime = now,
        lastSpendTime = now,
    }

    if newCurrent < max then
        if rechargeStart and numberGT(rechargeStart, 0) then
            patch.rechargeStart = rechargeStart
        else
            patch.rechargeStart = now
        end
    else
        patch.rechargeStart = nil
        patch.rechargeDuration = nil
    end

    updateCachedGlowState(spellID, patch)
end

local function hasAvailableChargeOrReady(spellID)
    local chargeAvailable = getAvailableMultiChargeState(spellID)
    if chargeAvailable ~= nil then
        return chargeAvailable
    end
    return getCooldownReadyByTimer(spellID, true)
end

local function hasAvailableChargeOrReadyStrict(spellID)
    local chargeAvailable = getAvailableMultiChargeState(spellID)
    if chargeAvailable ~= nil then
        return chargeAvailable
    end
    local strictReady = getCooldownReadyByTimer(spellID, false)
    if strictReady then
        updateCachedGlowState(spellID, {
            cooldownReady = true,
        })
        return true
    end

    local permissiveReady = getCooldownReadyByTimer(spellID, true)
    if permissiveReady then
        local cached = getCachedGlowState(spellID)
        if cached and cached.cooldownReady ~= nil then
            return cached.cooldownReady and true or false
        end
        return false
    end

    updateCachedGlowState(spellID, {
        cooldownReady = false,
    })
    return false
end

local function formatDiagnosticValue(value)
    if value == nil then
        return "nil"
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    return tostring(value)
end

local function appendDiagnosticField(parts, label, value)
    parts[#parts + 1] = tostring(label) .. "=" .. formatDiagnosticValue(value)
end

local function emitDiagnosticLine(prefix, fields)
    local parts = { prefix }
    for _, field in ipairs(fields) do
        parts[#parts + 1] = field
    end
    msg(table.concat(parts, " | "))
end

local function getDurationObjectValue(durationObject, methodName, ...)
    if not durationObject then
        return nil
    end
    local method = durationObject[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, durationObject, ...)
    if ok then
        return value
    end
    return nil
end

local function dumpSpellAPIDiagnostics(spellID)
    if not spellID then
        return false
    end

    local spellName = getSpellName(spellID)
    if not spellName or spellName == "" then
        spellName = "unknown"
    end

    msg("apidump start -> " .. tostring(spellID) .. " (" .. tostring(spellName) .. ")")

    local stateFields = {}
    appendDiagnosticField(stateFields, "spellID", spellID)
    appendDiagnosticField(stateFields, "name", spellName)
    appendDiagnosticField(stateFields, "known", isSpellKnownSafe(spellID))
    appendDiagnosticField(stateFields, "usable", isSpellUsableSafe(spellID))
    appendDiagnosticField(stateFields, "resourceUsable", isSpellResourceUsableSafe(spellID))
    appendDiagnosticField(stateFields, "inCombat", InCombatLockdown and InCombatLockdown() or false)
    emitDiagnosticLine("apidump state", stateFields)

    local cooldownInfo
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, result = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(result) == "table" then
            cooldownInfo = result
        end
    end

    local cooldownFields = {}
    appendDiagnosticField(cooldownFields, "startTime", cooldownInfo and cooldownInfo.startTime)
    appendDiagnosticField(cooldownFields, "duration", cooldownInfo and cooldownInfo.duration)
    appendDiagnosticField(cooldownFields, "isEnabled", cooldownInfo and cooldownInfo.isEnabled)
    appendDiagnosticField(cooldownFields, "modRate", cooldownInfo and cooldownInfo.modRate)
    appendDiagnosticField(cooldownFields, "isOnGCD", cooldownInfo and cooldownInfo.isOnGCD)
    appendDiagnosticField(cooldownFields, "activeCategory", cooldownInfo and cooldownInfo.activeCategory)
    appendDiagnosticField(cooldownFields, "timeUntilEndOfStartRecovery", cooldownInfo and cooldownInfo.timeUntilEndOfStartRecovery)
    emitDiagnosticLine("apidump cooldown", cooldownFields)

    local legacyStartTime
    local legacyDuration
    local legacyEnabled
    local legacyModRate
    if GetSpellCooldown then
        local ok, startTime, duration, enabled, modRate = pcall(GetSpellCooldown, spellID)
        if ok then
            legacyStartTime = startTime
            legacyDuration = duration
            legacyEnabled = enabled
            legacyModRate = modRate
        end
    end

    local legacyCooldownFields = {}
    appendDiagnosticField(legacyCooldownFields, "startTime", legacyStartTime)
    appendDiagnosticField(legacyCooldownFields, "duration", legacyDuration)
    appendDiagnosticField(legacyCooldownFields, "enabled", legacyEnabled)
    appendDiagnosticField(legacyCooldownFields, "modRate", legacyModRate)
    emitDiagnosticLine("apidump legacyCooldown", legacyCooldownFields)

    local chargeInfo = getSafeCharges(spellID)
    local chargeFields = {}
    appendDiagnosticField(chargeFields, "current", chargeInfo and chargeInfo.current)
    appendDiagnosticField(chargeFields, "max", chargeInfo and chargeInfo.max)
    appendDiagnosticField(chargeFields, "rechargeStart", chargeInfo and chargeInfo.rechargeStart)
    appendDiagnosticField(chargeFields, "rechargeDuration", chargeInfo and chargeInfo.rechargeDuration)
    appendDiagnosticField(chargeFields, "chargeModRate", chargeInfo and chargeInfo.chargeModRate)
    appendDiagnosticField(chargeFields, "unknown", chargeInfo and chargeInfo.unknown)
    emitDiagnosticLine("apidump charges", chargeFields)

    local legacyCurrentCharges
    local legacyMaxCharges
    local legacyChargeStart
    local legacyChargeDuration
    local legacyChargeModRate
    if GetSpellCharges then
        local ok, currentCharges, maxCharges, chargeStart, chargeDuration, chargeModRate = pcall(GetSpellCharges, spellID)
        if ok then
            legacyCurrentCharges = currentCharges
            legacyMaxCharges = maxCharges
            legacyChargeStart = chargeStart
            legacyChargeDuration = chargeDuration
            legacyChargeModRate = chargeModRate
        end
    end

    local legacyChargeFields = {}
    appendDiagnosticField(legacyChargeFields, "current", legacyCurrentCharges)
    appendDiagnosticField(legacyChargeFields, "max", legacyMaxCharges)
    appendDiagnosticField(legacyChargeFields, "rechargeStart", legacyChargeStart)
    appendDiagnosticField(legacyChargeFields, "rechargeDuration", legacyChargeDuration)
    appendDiagnosticField(legacyChargeFields, "chargeModRate", legacyChargeModRate)
    emitDiagnosticLine("apidump legacyCharges", legacyChargeFields)

    local durationObject
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, result = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok then
            durationObject = result
        end
    end

    local durationFields = {}
    appendDiagnosticField(durationFields, "startTime", getDurationObjectValue(durationObject, "GetStartTime"))
    appendDiagnosticField(durationFields, "duration", getDurationObjectValue(durationObject, "GetDuration"))
    appendDiagnosticField(durationFields, "remaining", getDurationObjectValue(durationObject, "GetRemainingDuration"))
    appendDiagnosticField(durationFields, "modRate", getDurationObjectValue(durationObject, "GetModRate"))
    emitDiagnosticLine("apidump durationObject", durationFields)

    local readyFields = {}
    appendDiagnosticField(readyFields, "readyShared", getCooldownReady(spellID))
    appendDiagnosticField(readyFields, "readyTimerStrict", getCooldownReadyByTimer(spellID, false))
    appendDiagnosticField(readyFields, "readyTimerFailOpen", getCooldownReadyByTimer(spellID, true))
    appendDiagnosticField(readyFields, "readyCustomStrict", hasAvailableChargeOrReadyStrict(spellID))
    appendDiagnosticField(readyFields, "atMaxCharges", isSpellAtMaxCharges(spellID))
    if resolveSpellID("RenewingMist") == spellID then
        appendDiagnosticField(readyFields, "readyRenewingMist", isRenewingMistReady(spellID))
    end
    if isLifeCocoonSpell(spellID) then
        appendDiagnosticField(readyFields, "readyLifeCocoon", isLifeCocoonReady(spellID))
    end
    emitDiagnosticLine("apidump readiness", readyFields)

    local cached = getCachedGlowState(spellID)
    local cachedFields = {}
    appendDiagnosticField(cachedFields, "current", cached and cached.current)
    appendDiagnosticField(cachedFields, "max", cached and cached.max)
    appendDiagnosticField(cachedFields, "rechargeStart", cached and cached.rechargeStart)
    appendDiagnosticField(cachedFields, "rechargeDuration", cached and cached.rechargeDuration)
    appendDiagnosticField(cachedFields, "chargeModRate", cached and cached.chargeModRate)
    appendDiagnosticField(cachedFields, "chargeTime", cached and cached.chargeTime)
    appendDiagnosticField(cachedFields, "cooldownReady", cached and cached.cooldownReady)
    appendDiagnosticField(cachedFields, "lastSpendTime", cached and cached.lastSpendTime)
    appendDiagnosticField(cachedFields, "shouldGlow", cached and cached.shouldGlow)
    appendDiagnosticField(cachedFields, "stackCount", cached and cached.stackCount)
    emitDiagnosticLine("apidump cache", cachedFields)

    local estimated = estimateChargeStateFromCache(spellID)
    local estimatedFields = {}
    appendDiagnosticField(estimatedFields, "current", estimated and estimated.current)
    appendDiagnosticField(estimatedFields, "max", estimated and estimated.max)
    appendDiagnosticField(estimatedFields, "rechargeStart", estimated and estimated.rechargeStart)
    appendDiagnosticField(estimatedFields, "rechargeDuration", estimated and estimated.rechargeDuration)
    appendDiagnosticField(estimatedFields, "chargeModRate", estimated and estimated.chargeModRate)
    appendDiagnosticField(estimatedFields, "chargeTime", estimated and estimated.chargeTime)
    emitDiagnosticLine("apidump estimated", estimatedFields)

    msg("apidump end -> " .. tostring(spellID))
    return true
end

local SPELL_POLICIES = {
    Lifebloom = {
        label = "Lifebloom",
        condition = "groupAuraBelowThreshold",
        fromPlayerOnly = true,
        threshold = function()
            return getLifebloomTargetThreshold()
        end,
    },
    CenarionWard = {
        label = "Cenarion Ward",
        condition = "auraMissingOnMouseover",
        readiness = "cooldown",
        requireMouseover = true,
    },
    Consecration = {
        label = "Consecration",
        condition = "playerAuraMissing",
        readiness = "cooldown",
        auraKey = "ConsecrationAura",
    },
    InfusionOfLight = {
        label = "Infusion of Light",
        condition = "playerAuraActive",
    },
    HolyBulwark = {
        label = "Holy Bulwark",
        condition = "playerAuraMissing",
        readiness = "cooldown",
    },
    RenewingMist = {
        label = "Renewing Mist",
        condition = "chargeOrAuraMissingOnMouseover",
        readiness = "renewingMist",
        glowRule = "RenewingMist",
    },
    StrengthOfTheBlackOx = {
        label = "Strength of the Black Ox",
        condition = "playerAuraActive",
    },
    WaterShield = {
        label = "Water Shield",
        condition = "playerAuraMissing",
        readiness = "cooldown",
    },
    HealingStreamTotem = {
        label = "Healing Stream Totem",
        condition = "totemInactive",
        readiness = "cooldown",
    },
    HealingRain = {
        label = "Healing Rain",
        condition = "readyAlways",
        readiness = "cooldown",
    },
    Riptide = {
        label = "Riptide",
        condition = "chargeOrAuraMissingOnMouseover",
        readiness = "chargeOrCooldown",
    },
    CloudburstTotem = {
        label = "Cloudburst Totem",
        condition = "readyAlways",
        readiness = "cooldown",
    },
    Reversion = {
        label = "Reversion",
        condition = "reversionCoverage",
        readiness = "chargeOrCooldown",
    },
    Echo = {
        label = "Echo",
        condition = "readyAlways",
        readiness = "cooldown",
        essenceMin = 2,
    },
    Lifespark = {
        label = "Lifespark",
        condition = "playerAuraActive",
    },
    Atonement = {
        label = "Atonement",
        condition = "counterAlways",
        fromPlayerOnly = true,
        iconCount = function(_, spellID, policy)
            local count = countAuraInGroup(spellID, policy.fromPlayerOnly)
            return tostring(count)
        end,
    },
    PowerWordShield = {
        label = "Power Word: Shield",
        condition = "readyAlways",
        readiness = "powerWordShield",
    },
    PowerWordRadiance = {
        label = "Power Word: Radiance",
        condition = "readyAlways",
        readiness = "chargeOrCooldown",
        glowRule = "PowerWordRadiance",
    },
    Penance = {
        label = "Penance",
        condition = "readyAlways",
        readiness = "chargeOrCooldown",
        glowRule = "Penance",
    },
    PrayerOfMending = {
        label = "Prayer of Mending",
        condition = "auraMissingOnMouseover",
        readiness = "cooldown",
    },
    Halo = {
        label = "Halo",
        condition = "readyAlways",
        readiness = "cooldown",
    },
    Lightweaver = {
        label = "Lightweaver",
        condition = "playerAuraActive",
        glowRule = "Lightweaver",
        glowContext = function(_, spellID)
            return {
                stackCount = getAuraStackCountSafe("player", spellID, true, true),
            }
        end,
    },
    Premonitions = {
        label = "Premonitions",
        condition = "readyAlways",
        readiness = "cooldown",
    },
}

local function getPolicyValue(value, context, spellID, policy)
    if type(value) == "function" then
        return value(context, spellID, policy)
    end
    return value
end

local function resolvePolicySpellID(policyKey, policy)
    if policy and policy.resolveAnyKeys then
        return resolveAnySpellID(policy.resolveAnyKeys)
    end
    if policy and policy.resolveKey then
        return resolveSpellID(policy.resolveKey)
    end
    return resolveSpellID(policyKey)
end

local function resolvePolicyAuraSpellID(policyKey, policy, spellID)
    if policy and policy.auraKey then
        return resolveSpellID(policy.auraKey) or spellID
    end
    if policy and policy.auraSpellID then
        return policy.auraSpellID or spellID
    end
    return spellID or resolveSpellID(policyKey)
end

local function isSpellReadyForPolicy(policyKey, policy, spellID)
    local readiness = policy and policy.readiness
    if readiness == nil then
        return true
    end
    if readiness == "cooldown" then
        return getCooldownReadyByTimer(spellID, true)
    end
    if readiness == "cooldownStrict" then
        return getCooldownReadyByTimer(spellID, false)
    end
    if readiness == "chargeOrCooldown" then
        return hasAvailableChargeOrReady(spellID)
    end
    if readiness == "chargeOrCooldownStrict" then
        return hasAvailableChargeOrReadyStrict(spellID)
    end
    if readiness == "renewingMist" then
        return isRenewingMistReady(spellID)
    end
    if readiness == "lifeCocoon" then
        return isLifeCocoonReady(spellID)
    end
    if readiness == "powerWordShield" then
        return isPowerWordShieldReady(spellID)
    end
    return getCooldownReadyByTimer(spellID, true)
end

local function getSpellPolicyBySpellID(spellID)
    if not spellID then
        return nil, nil
    end
    for policyKey, policy in pairs(SPELL_POLICIES) do
        local resolved = resolvePolicySpellID(policyKey, policy)
        if resolved and resolved == spellID then
            return policyKey, policy
        end
    end
    return nil, nil
end

local function evaluateSpellPolicy(policyKey, context, addEntry)
    local policy = SPELL_POLICIES[policyKey]
    if not policy then
        return false
    end

    local spellID = resolvePolicySpellID(policyKey, policy)
    if not spellID then
        return false
    end

    local auraSpellID = resolvePolicyAuraSpellID(policyKey, policy, spellID)
    local label = getPolicyValue(policy.label, context, spellID, policy) or getSpellName(spellID) or policyKey
    local glowRule = getPolicyValue(policy.glowRule, context, spellID, policy)
    local glowContext = getPolicyValue(policy.glowContext, context, spellID, policy)
    local iconCount = getPolicyValue(policy.iconCount, context, spellID, policy)
    local ready = isSpellReadyForPolicy(policyKey, policy, spellID)

    if policy.essenceMin and getEssenceCount() < policy.essenceMin then
        return false
    end

    if policy.condition == "groupAuraBelowThreshold" then
        local threshold = getPolicyValue(policy.threshold, context, spellID, policy) or 1
        local count = countAuraInGroup(auraSpellID, policy.fromPlayerOnly ~= false)
        if count < threshold then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "auraMissingOnMouseover" then
        if not ready then
            return false
        end
        if policy.requireMouseover then
            if not context.mouseover then
                return false
            end
            if not isAuraActive(context.mouseover, auraSpellID, true, true) then
                return addEntry(label, spellID, iconCount, glowRule, glowContext)
            end
            return false
        end
        if isAuraMissingOnMouseover(auraSpellID) then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "playerAuraMissing" then
        if ready and not isAuraActive("player", auraSpellID, true, true) then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "playerAuraActive" then
        if isAuraActive("player", auraSpellID, true, true) then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "readyAlways" then
        if ready then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "chargeOrAuraMissingOnMouseover" then
        if ready and (isSpellAtMaxCharges(spellID) or isAuraMissingOnMouseover(auraSpellID)) then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "totemInactive" then
        if ready and not isPlayerTotemActive(spellID) then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "reversionCoverage" then
        if not ready then
            return false
        end
        if context.mouseover then
            if isSpellAtMaxCharges(spellID) or not isAuraActive(context.mouseover, auraSpellID, true, true) then
                return addEntry(label, spellID, iconCount, glowRule, glowContext)
            end
            return false
        end
        local alive = countAliveGroupUnits()
        local active = countAuraInGroup(auraSpellID, true)
        if active < alive then
            return addEntry(label, spellID, iconCount, glowRule, glowContext)
        end
        return false
    end

    if policy.condition == "counterAlways" then
        return addEntry(label, spellID, iconCount, glowRule, glowContext)
    end

    return false
end

local function buildEntries()
    local specID = getSpecID()
    if not specID then
        return {}
    end

    local mouseover = getFriendlyMouseover()
    local entries = {}
    local addedSpellIDs = {}

    local function isHandledByCoreSpecLogic(spellID)
        if not specID or not spellID then
            return false
        end
        local keys = CORE_SPELL_KEYS_BY_SPEC[specID] or {}
        for _, key in ipairs(keys) do
            local coreSpellID = resolveSpellID(key)
            if coreSpellID and coreSpellID == spellID then
                return true
            end
        end
        return false
    end

    local function addEntry(name, spellID, iconCount, glowRule, glowContext)
        if not spellID then
            return false
        end
        if (not isHandledByCoreSpecLogic(spellID)) and (not isSpellInTrackedList(spellID)) then
            return false
        end
        if addedSpellIDs[spellID] then
            return false
        end
        entries[#entries + 1] = {
            name = name,
            spellID = spellID,
            icon = getSpellTexture(spellID) or 136243,
            iconCount = iconCount,
            glowRule = glowRule,
            glowContext = glowContext,
        }
        addedSpellIDs[spellID] = true
        return true
    end

    local corePolicyKeys = CORE_SPELL_KEYS_BY_SPEC[specID] or {}
    local policyContext = {
        specID = specID,
        mouseover = mouseover,
    }
    for _, policyKey in ipairs(corePolicyKeys) do
        evaluateSpellPolicy(policyKey, policyContext, addEntry)
    end

    local customSpells = getCustomTrackedSpells()
    for _, customSpellID in ipairs(customSpells) do
        local readyForCustomSpell = hasAvailableChargeOrReadyStrict(customSpellID)
        local customPolicyKey, customPolicy = getSpellPolicyBySpellID(customSpellID)
        if customPolicy and (customPolicy.readiness == "renewingMist" or customPolicy.readiness == "lifeCocoon") then
            readyForCustomSpell = isSpellReadyForPolicy(customPolicyKey, customPolicy, customSpellID)
        elseif isLifeCocoonSpell(customSpellID) then
            readyForCustomSpell = isLifeCocoonReady(customSpellID)
        end
        if not isHandledByCoreSpecLogic(customSpellID)
            and isSpellKnownSafe(customSpellID)
            and readyForCustomSpell
            and isSpellResourceUsableSafe(customSpellID) then
            addEntry(getSpellName(customSpellID) or ("Spell " .. tostring(customSpellID)), customSpellID)
        end
    end

    return entries
end

local function layoutEntries(entries)
    if not HealingPriorityMouseDB.enabled then
        root:Hide()
        hideAllIcons()
        return
    end

    if #entries == 0 then
        root:Hide()
        hideAllIcons()
        return
    end

    root:Show()

    local spacing = 4
    local size = 26 * (HealingPriorityMouseDB.scale or 1)
    for i = 1, #entries do
        local f = ensureIcon(i)
        f:SetScale(HealingPriorityMouseDB.scale or 1)
        f:ClearAllPoints()
        f:SetPoint("LEFT", root, "LEFT", (i - 1) * (size + spacing), 0)
        f.icon:SetTexture(entries[i].icon)

        local opacity = clampOpacity(tonumber(HealingPriorityMouseDB.opacity) or 1.0) or 1.0
        f.icon:SetAlpha(opacity)
        f.cooldown:SetAlpha(opacity)

        if HealingPriorityMouseDB.showSpellNames then
            f.label:ClearAllPoints()
            if HealingPriorityMouseDB.spellNamePosition == "top" then
                f.label:SetPoint("BOTTOM", f, "TOP", 0, 1)
            else
                f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)
            end
            f.label:SetText(entries[i].name or "")
            f.label:Show()
        else
            f.label:SetText("")
            f.label:Hide()
        end

        if C_Spell and C_Spell.GetSpellCooldown then
            local ok, info = pcall(C_Spell.GetSpellCooldown, entries[i].spellID)
            if not ok then
                info = nil
            end
            local startTime = info and plainNumber(info.startTime)
            local duration = info and plainNumber(info.duration)
            local isOnGCD = info and isTrueFlag(info.isOnGCD, false)
            if info and startTime and duration and numberGT(duration, 1.5) and not isOnGCD and shouldShowCooldownSwipe(entries[i].spellID) then
                f.cooldown:SetCooldown(startTime, duration)
            else
                f.cooldown:Clear()
            end
        else
            f.cooldown:Clear()
        end

        if entries[i].iconCount then
            f.chargeText:SetText(entries[i].iconCount)
            f.chargeText:Show()
        elseif HealingPriorityMouseDB.showCharges then
            local charges = getDisplayChargeState(entries[i].spellID)
            if charges and charges.unknown then
                local cached = estimateChargeStateFromCache(entries[i].spellID)
                if cached and cached.current and cached.max and numberGT(cached.max, 1) then
                    f.chargeText:SetText(tostring(cached.current))
                    f.chargeText:Show()
                else
                    if InCombatLockdown and InCombatLockdown() then
                        local staleCached = getCachedGlowState(entries[i].spellID)
                        if staleCached and staleCached.current and staleCached.max and numberGT(staleCached.max, 1) then
                            f.chargeText:SetText(tostring(staleCached.current))
                            f.chargeText:Show()
                        else
                            f.chargeText:SetText("?")
                            f.chargeText:Show()
                        end
                    else
                        f.chargeText:Hide()
                    end
                end
            elseif charges and charges.max and numberGT(charges.max, 1) then
                f.chargeText:SetText(tostring(charges.current or 0))
                f.chargeText:Show()
            else
                f.chargeText:Hide()
            end
        else
            f.chargeText:Hide()
        end

        setIconGlow(f, shouldGlowEntry(entries[i]))

        f:Show()
    end

    for i = #entries + 1, #iconFrames do
        setIconGlow(iconFrames[i], false)
        iconFrames[i]:Hide()
    end
end

root:SetScript("OnUpdate", function()
    if not HealingPriorityMouseDB.enabled then
        root:Hide()
        return
    end

    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x / scale) + 18, (y / scale) + 18)
end)

local function refresh()
    local entries = buildEntries()
    layoutEntries(entries)

    if HealingPriorityMouseDB and HealingPriorityMouseDB.devLiveLogging then
        local parts = {}
        for _, entry in ipairs(entries) do
            parts[#parts + 1] = tostring(entry.name or "?") .. "(" .. tostring(entry.spellID or "?") .. ")"
        end
        local signature = (#parts > 0) and table.concat(parts, ", ") or "none"
        if signature ~= lastLiveLogSignature then
            appendDevLogLine("LIVE recommendations: " .. signature)
            lastLiveLogSignature = signature
        end
    end
end

local refreshOptionsControls

local function safeRefreshOptionsControls()
    if refreshOptionsControls then
        refreshOptionsControls()
    end
end

local function ensureCustomSpellRow(index)
    if not optionsControls or not optionsControls.customSpellListContent then
        return nil
    end

    local rows = optionsControls.customSpellRows
    if rows[index] then
        return rows[index]
    end

    local content = optionsControls.customSpellListContent
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(20)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local rowLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    rowLabel:SetJustifyH("LEFT")

    local rowSpellID = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowSpellID:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    rowSpellID:SetJustifyH("RIGHT")

    local removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeButton:SetSize(64, 18)
    removeButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    removeButton:SetText("Remove")
    removeButton:SetScript("OnClick", function()
        if row.spellID and removeCustomTrackedSpell(row.spellID) then
            refresh()
            safeRefreshOptionsControls()
        end
    end)

    row.icon = icon
    row.label = rowLabel
    row.idLabel = rowSpellID
    row.removeBtn = removeButton
    row:Hide()
    rows[index] = row
    return row
end

refreshOptionsControls = function()
    if not optionsFrame or not optionsControls then
        return
    end

    local db = HealingPriorityMouseDB
    optionsControls.enabled:SetChecked(db.enabled and true or false)
    optionsControls.charges:SetChecked(db.showCharges and true or false)
    optionsControls.glows:SetChecked(db.showGlows and true or false)
    optionsControls.showNames:SetChecked(db.showSpellNames and true or false)

    UIDropDownMenu_SetSelectedValue(optionsControls.namePosition, db.spellNamePosition)

    local scaleValue = clampScale(tonumber(db.scale) or 1.0) or 1.0
    optionsControls.scaleSlider:SetValue(scaleValue)
    optionsControls.scaleInput:SetText(string.format("%.2f", scaleValue))

    local opacityValue = clampOpacity(tonumber(db.opacity) or 1.0) or 1.0
    optionsControls.opacitySlider:SetValue(opacityValue)
    optionsControls.opacityInput:SetText(tostring(math.floor((opacityValue * 100) + 0.5)))

    if optionsControls.liveLoggingToggle then
        optionsControls.liveLoggingToggle:SetChecked(db.devLiveLogging and true or false)
    end

    if optionsControls.customSpellDropdown then
        local spellOptions = collectKnownClassSpellOptions()
        optionsControls.customSpellOptions = spellOptions

        local selectedSpellID = optionsControls.selectedCustomSpellID
        local hasSelected = false
        if selectedSpellID then
            for _, option in ipairs(spellOptions) do
                if option.spellID == selectedSpellID then
                    hasSelected = true
                    break
                end
            end
        end

        if not hasSelected then
            selectedSpellID = spellOptions[1] and spellOptions[1].spellID or nil
            optionsControls.selectedCustomSpellID = selectedSpellID
        end

        if selectedSpellID then
            UIDropDownMenu_SetText(optionsControls.customSpellDropdown, getSpellLabel(selectedSpellID))
            optionsControls.addSpellButton:Enable()
        else
            UIDropDownMenu_SetText(optionsControls.customSpellDropdown, "All addable spells already tracked")
            optionsControls.addSpellButton:Disable()
        end
    end

    if optionsControls.customSpellRows then
        local spells = getCustomTrackedSpells()
        local rows = optionsControls.customSpellRows
        local rowWidth = math.max(220, (optionsControls.customSpellListScroll:GetWidth() or 260) - 24)

        for index, spellID in ipairs(spells) do
            local row = ensureCustomSpellRow(index)
            if row then
                row:ClearAllPoints()
                if index == 1 then
                    row:SetPoint("TOPLEFT", optionsControls.customSpellListContent, "TOPLEFT", 0, -4)
                else
                    row:SetPoint("TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, -4)
                end

                row:SetWidth(rowWidth)
                row.spellID = spellID
                row.icon:SetTexture(getSpellTexture(spellID) or 136243)

                local spellName = getSpellName(spellID)
                if spellName and spellName ~= "" then
                    row.label:SetText(spellName)
                else
                    row.label:SetText("Spell")
                end

                row.idLabel:SetText("(" .. tostring(spellID) .. ")")
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.label:SetPoint("RIGHT", row.idLabel, "LEFT", -6, 0)
                row.removeBtn:Enable()
                row:Show()
            end
        end

        for index = #spells + 1, #rows do
            rows[index].spellID = nil
            rows[index]:Hide()
        end

        local contentHeight = math.max((#spells * 24) + 8, (optionsControls.customSpellListScroll:GetHeight() or 120) - 4)
        optionsControls.customSpellListContent:SetHeight(contentHeight)

        if optionsControls.customSpellEmpty then
            if #spells == 0 then
                optionsControls.customSpellEmpty:Show()
            else
                optionsControls.customSpellEmpty:Hide()
            end
        end
    end
end

local function createDebugLogWindow()
    if debugLogWindow then
        return debugLogWindow
    end

    local frame = CreateFrame("Frame", "HealingPriorityMouseDebugLogFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(700, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 8, 0)
    frame.title:SetText("HealingPriorityMouse Dev Logs")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -34)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(620)
    edit:SetHeight(1)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:EnableMouse(true)
    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local lines = 1
        for _ in string.gmatch(text, "\n") do
            lines = lines + 1
        end
        local _, lineHeight = self:GetFont()
        lineHeight = tonumber(lineHeight) or 12
        local estimatedHeight = (lines * lineHeight) + 8
        self:SetHeight(math.max((scroll:GetHeight() or 1) - 4, estimatedHeight))
    end)
    scroll:SetScrollChild(edit)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(90, 24)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        for i = #devLogLines, 1, -1 do
            devLogLines[i] = nil
        end
        lastLiveLogSignature = nil
        updateDebugLogWindowText()
    end)

    debugLogWindow = frame
    debugLogScroll = scroll
    debugLogEditBox = edit
    updateDebugLogWindowText()
    return debugLogWindow
end

local function createOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local frame = CreateFrame("Frame", "HealingPriorityMouseOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(640, 500, 1100, 900)
    else
        if frame.SetMinResize then
            frame:SetMinResize(640, 500)
        end
        if frame.SetMaxResize then
            frame:SetMaxResize(1100, 900)
        end
    end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 8, 0)
    frame.title:SetText("HealingPriorityMouse Options")

    local tabGeneral = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    tabGeneral:SetID(1)
    tabGeneral:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -30)
    tabGeneral:SetText("General")
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tabGeneral, 0)
    else
        tabGeneral:SetWidth(90)
    end

    local tabDevtools = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    tabDevtools:SetID(2)
    tabDevtools:SetPoint("LEFT", tabGeneral, "RIGHT", -14, 0)
    tabDevtools:SetText("Devtools")
    if PanelTemplates_TabResize then
        PanelTemplates_TabResize(tabDevtools, 0)
    else
        tabDevtools:SetWidth(90)
    end

    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(frame, 2)
    end

    local contentTopY = -62

    local enabled = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", 16, contentTopY)
    enabled.Text:SetText("Enable addon display")
    enabled:SetScript("OnClick", function(self)
        HealingPriorityMouseDB.enabled = self:GetChecked() and true or false
        refresh()
    end)

    local charges = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    charges:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -8)
    charges.Text:SetText("Show charges overlay")
    charges:SetScript("OnClick", function(self)
        HealingPriorityMouseDB.showCharges = self:GetChecked() and true or false
        refresh()
    end)

    local glows = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    glows:SetPoint("TOPLEFT", charges, "BOTTOMLEFT", 0, -8)
    glows.Text:SetText("Show glows")
    glows:SetScript("OnClick", function(self)
        HealingPriorityMouseDB.showGlows = self:GetChecked() and true or false
        refresh()
    end)

    local showNames = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    showNames:SetPoint("TOPLEFT", glows, "BOTTOMLEFT", 0, -8)
    showNames.Text:SetText("Show spell names")
    showNames:SetScript("OnClick", function(self)
        HealingPriorityMouseDB.showSpellNames = self:GetChecked() and true or false
        refresh()
    end)

    local namePositionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    namePositionLabel:SetPoint("TOPLEFT", showNames, "BOTTOMLEFT", 0, -22)
    namePositionLabel:SetText("Spell name position")

    local namePosition = CreateFrame("Frame", "HealingPriorityMouseNamePositionDropdown", frame, "UIDropDownMenuTemplate")
    namePosition:SetPoint("TOPLEFT", namePositionLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(namePosition, 120)
    UIDropDownMenu_Initialize(namePosition, function(self, level)
        local function addOption(label, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = value
            info.checked = (HealingPriorityMouseDB.spellNamePosition == value)
            info.func = function()
                HealingPriorityMouseDB.spellNamePosition = value
                UIDropDownMenu_SetSelectedValue(self, value)
                refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        addOption("Under icon", "bottom")
        addOption("Above icon", "top")
    end)

    local scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", namePosition, "BOTTOMLEFT", 16, -20)
    scaleLabel:SetText("Scale")

    local scaleSlider = CreateFrame("Slider", "HealingPriorityMouseScaleSlider", frame, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -18)
    scaleSlider:SetMinMaxValues(0.6, 3.0)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider:SetWidth(240)
    _G[scaleSlider:GetName() .. "Low"]:SetText("0.6")
    _G[scaleSlider:GetName() .. "High"]:SetText("3.0")
    _G[scaleSlider:GetName() .. "Text"]:SetText("")

    local scaleInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    scaleInput:SetSize(56, 24)
    scaleInput:SetPoint("LEFT", scaleSlider, "RIGHT", 16, 0)
    scaleInput:SetAutoFocus(false)
    scaleInput:SetNumeric(false)
    scaleInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if setScaleValue(val) then
            local value = HealingPriorityMouseDB.scale
            scaleSlider:SetValue(value)
            self:SetText(string.format("%.2f", value))
            refresh()
        else
            self:SetText(string.format("%.2f", HealingPriorityMouseDB.scale or 1.0))
            msg("usage: scale 0.6-3.0")
        end
        self:ClearFocus()
    end)
    scaleInput:SetScript("OnEscapePressed", function(self)
        self:SetText(string.format("%.2f", HealingPriorityMouseDB.scale or 1.0))
        self:ClearFocus()
    end)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor((value * 100) + 0.5) / 100
        if setScaleValue(rounded) then
            scaleInput:SetText(string.format("%.2f", HealingPriorityMouseDB.scale))
            refresh()
        end
    end)

    local opacityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacityLabel:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -24)
    opacityLabel:SetText("Icon opacity (%)")

    local opacitySlider = CreateFrame("Slider", "HealingPriorityMouseOpacitySlider", frame, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -18)
    opacitySlider:SetMinMaxValues(0, 1)
    opacitySlider:SetValueStep(0.01)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetWidth(240)
    _G[opacitySlider:GetName() .. "Low"]:SetText("0")
    _G[opacitySlider:GetName() .. "High"]:SetText("100")
    _G[opacitySlider:GetName() .. "Text"]:SetText("")

    local opacityInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    opacityInput:SetSize(56, 24)
    opacityInput:SetPoint("LEFT", opacitySlider, "RIGHT", 16, 0)
    opacityInput:SetAutoFocus(false)
    opacityInput:SetNumeric(false)
    opacityInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if setOpacityPercent(val) then
            local value = HealingPriorityMouseDB.opacity or 1.0
            opacitySlider:SetValue(value)
            self:SetText(tostring(math.floor((value * 100) + 0.5)))
            refresh()
        else
            local current = HealingPriorityMouseDB.opacity or 1.0
            self:SetText(tostring(math.floor((current * 100) + 0.5)))
            msg("usage: /hpm opacity 0-100")
        end
        self:ClearFocus()
    end)
    opacityInput:SetScript("OnEscapePressed", function(self)
        local current = HealingPriorityMouseDB.opacity or 1.0
        self:SetText(tostring(math.floor((current * 100) + 0.5)))
        self:ClearFocus()
    end)

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor((value * 100) + 0.5) / 100
        if setOpacityPercent(rounded) then
            local current = HealingPriorityMouseDB.opacity or 1.0
            opacityInput:SetText(tostring(math.floor((current * 100) + 0.5)))
            refresh()
        end
    end)

    local customSpellsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customSpellsLabel:SetText("Custom tracked spells")

    local customSpellDropdown = CreateFrame("Frame", "HealingPriorityMouseCustomSpellDropdown", frame, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(customSpellDropdown, 220)
    UIDropDownMenu_Initialize(customSpellDropdown, function(self, level)
        local options = (optionsControls and optionsControls.customSpellOptions) or {}
        if #options == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "All addable spells already tracked"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.label
            info.value = option.spellID
            info.checked = (optionsControls and optionsControls.selectedCustomSpellID == option.spellID)
            info.func = function()
                if optionsControls then
                    optionsControls.selectedCustomSpellID = option.spellID
                    UIDropDownMenu_SetText(customSpellDropdown, option.label)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local addSpellButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSpellButton:SetSize(64, 24)
    addSpellButton:SetText("Add")

    local customSpellHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customSpellHint:SetText("Dropdown shows additional known spells you can track for this character.")

    local customSpellListScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    local customSpellListContent = CreateFrame("Frame", nil, customSpellListScroll)
    customSpellListContent:SetSize(1, 1)
    customSpellListScroll:SetScrollChild(customSpellListContent)

    local customSpellEmpty = customSpellListContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customSpellEmpty:SetPoint("TOPLEFT", customSpellListContent, "TOPLEFT", 2, -6)
    customSpellEmpty:SetText("No additional tracked spells added.")

    local customSpellRows = {}

    local devtoolsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    devtoolsTitle:SetPoint("TOPLEFT", 16, contentTopY)
    devtoolsTitle:SetText("Developer tools")

    local liveLoggingToggle = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    liveLoggingToggle:SetPoint("TOPLEFT", devtoolsTitle, "BOTTOMLEFT", 0, -10)
    liveLoggingToggle.Text:SetText("Enable live logging")
    liveLoggingToggle:SetScript("OnClick", function(self)
        HealingPriorityMouseDB.devLiveLogging = self:GetChecked() and true or false
        lastLiveLogSignature = nil
        appendDevLogLine("LIVE logging " .. (HealingPriorityMouseDB.devLiveLogging and "enabled" or "disabled"))
    end)

    local openLogsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    openLogsBtn:SetSize(180, 24)
    openLogsBtn:SetPoint("TOPLEFT", liveLoggingToggle, "BOTTOMLEFT", 4, -12)
    openLogsBtn:SetText("Open log display")
    openLogsBtn:SetScript("OnClick", function()
        local logFrame = createDebugLogWindow()
        logFrame:Show()
        logFrame:Raise()
        updateDebugLogWindowText()
    end)

    local devtoolsHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    devtoolsHint:SetPoint("TOPLEFT", openLogsBtn, "BOTTOMLEFT", 0, -10)
    devtoolsHint:SetText("Shows a live tail of addon logs for troubleshooting.")

    local function applyOptionsLayout()
        local width = frame:GetWidth()
        local rightColumnLeft = math.max(330, math.floor(width * 0.56))

        customSpellsLabel:ClearAllPoints()
        customSpellsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", rightColumnLeft, contentTopY)

        customSpellDropdown:ClearAllPoints()
        customSpellDropdown:SetPoint("TOPLEFT", customSpellsLabel, "BOTTOMLEFT", -16, -2)

        local dropdownWidth = math.max(170, width - rightColumnLeft - 134)
        UIDropDownMenu_SetWidth(customSpellDropdown, dropdownWidth)

        addSpellButton:ClearAllPoints()
        addSpellButton:SetPoint("LEFT", customSpellDropdown, "RIGHT", -4, 2)

        customSpellHint:ClearAllPoints()
        customSpellHint:SetPoint("TOPLEFT", customSpellDropdown, "BOTTOMLEFT", 16, -6)

        customSpellListScroll:ClearAllPoints()
        customSpellListScroll:SetPoint("TOPLEFT", customSpellHint, "BOTTOMLEFT", 0, -8)
        customSpellListScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 46)
    end

    local function setOptionsTab(tab)
        local showGeneral = (tab == "general")
        frame.activeTab = tab

        local generalWidgets = optionsControls and optionsControls.generalWidgets or {}
        local devWidgets = optionsControls and optionsControls.devWidgets or {}

        for _, widget in ipairs(generalWidgets) do
            if widget and widget.SetShown then
                widget:SetShown(showGeneral)
            end
        end
        for _, widget in ipairs(devWidgets) do
            if widget and widget.SetShown then
                widget:SetShown(not showGeneral)
            end
        end

        if PanelTemplates_SetTab then
            PanelTemplates_SetTab(frame, showGeneral and 1 or 2)
        else
            if PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
                if showGeneral then
                    PanelTemplates_SelectTab(tabGeneral)
                    PanelTemplates_DeselectTab(tabDevtools)
                else
                    PanelTemplates_SelectTab(tabDevtools)
                    PanelTemplates_DeselectTab(tabGeneral)
                end
            else
                tabGeneral:Enable(not showGeneral)
                tabDevtools:Enable(showGeneral)
            end
        end
    end

    local function handleAddCustomSpell()
        local spellID = optionsControls and optionsControls.selectedCustomSpellID
        local ok, reason = addCustomTrackedSpell(spellID)
        if ok then
            refresh()
            refreshOptionsControls()
            return
        end
        if reason == "duplicate" then
            msg("custom spell already tracked")
        elseif reason == "core-managed" then
            msg("that spell is already handled by the built-in core logic")
        elseif reason == "not-found" then
            msg("selected spell is not available on this client")
        else
            msg("select a spell from the dropdown first")
        end
    end

    addSpellButton:SetScript("OnClick", function()
        handleAddCustomSpell()
    end)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function()
        if frame:IsResizable() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)
    frame.resizeButton = resizeHandle

    optionsControls = {
        enabled = enabled,
        charges = charges,
        glows = glows,
        showNames = showNames,
        namePosition = namePosition,
        scaleSlider = scaleSlider,
        scaleInput = scaleInput,
        opacitySlider = opacitySlider,
        opacityInput = opacityInput,
        customSpellDropdown = customSpellDropdown,
        customSpellOptions = {},
        selectedCustomSpellID = nil,
        addSpellButton = addSpellButton,
        customSpellListScroll = customSpellListScroll,
        customSpellListContent = customSpellListContent,
        customSpellRows = customSpellRows,
        customSpellEmpty = customSpellEmpty,
        liveLoggingToggle = liveLoggingToggle,
        generalWidgets = {
            enabled, charges, glows, showNames,
            namePositionLabel, namePosition,
            scaleLabel, scaleSlider, scaleInput,
            opacityLabel, opacitySlider, opacityInput,
            customSpellsLabel, customSpellDropdown, addSpellButton,
            customSpellHint, customSpellListScroll,
        },
        devWidgets = {
            devtoolsTitle, liveLoggingToggle, openLogsBtn, devtoolsHint,
        },
    }

    tabGeneral:SetScript("OnClick", function()
        setOptionsTab("general")
    end)
    tabDevtools:SetScript("OnClick", function()
        setOptionsTab("devtools")
    end)

    frame:SetScript("OnShow", function()
        applyOptionsLayout()
        refreshOptionsControls()
        setOptionsTab(frame.activeTab or "general")
    end)

    frame:SetScript("OnSizeChanged", function()
        applyOptionsLayout()
        refreshOptionsControls()
        setOptionsTab(frame.activeTab or "general")
    end)

    optionsFrame = frame
    return frame
end

local function openOptionsFrame()
    local frame = createOptionsFrame()
    refreshOptionsControls()
    frame:Show()
    frame:Raise()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end
        copyDefaults(HealingPriorityMouseDB, defaults)
        sanitizeCustomTrackedSpellsInDB()
        ensureDefaultTrackedSpellsForActiveSpec()
        msg("loaded v" .. ADDON_VERSION)
        refresh()
        return
    end

    if event == "UNIT_AURA" and arg1 and arg1 ~= "player" and arg1 ~= "mouseover" then
        if not arg1:match("^party") and not arg1:match("^raid") then
            return
        end

        local now = getNowTime()
        if (now - lastGroupAuraRefresh) < GROUP_AURA_REFRESH_INTERVAL then
            return
        end
        lastGroupAuraRefresh = now
    end

    if event == "UNIT_POWER_UPDATE" and arg1 ~= "player" then
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        local castSpellID = plainNumber(arg3)
        if castSpellID then
            local liveCharges = getSafeCharges(castSpellID)
            local hasLiveChargeState = liveCharges and not liveCharges.unknown and liveCharges.current and liveCharges.max
            if hasLiveChargeState and liveCharges.max and numberGT(liveCharges.max, 1) then
                applyChargeSpendToCache(castSpellID, liveCharges)
            elseif hasLiveChargeState then
                cacheChargeState(castSpellID, liveCharges)
            end

            local cachedCharges = nil
            if not hasLiveChargeState then
                cachedCharges = estimateChargeStateFromCache(castSpellID)
            end
            if cachedCharges and cachedCharges.current and cachedCharges.max and numberGT(cachedCharges.max, 1) then
                applyChargeSpendToCache(castSpellID, cachedCharges)
            end

            if isLifeCocoonSpell(castSpellID) then
                local cooldownStart
                local cooldownDuration
                local cooldownModRate
                if C_Spell and C_Spell.GetSpellCooldown then
                    local okCooldown, cooldownInfo = pcall(C_Spell.GetSpellCooldown, castSpellID)
                    if okCooldown and type(cooldownInfo) == "table" then
                        cooldownStart = plainNumber(cooldownInfo.startTime)
                        cooldownDuration = plainNumber(cooldownInfo.duration)
                        cooldownModRate = plainNumber(cooldownInfo.modRate)
                    end
                end
                local cocoonState = {
                    current = 0,
                    max = 1,
                    chargeTime = getNowTime(),
                    cooldownReady = false,
                    lastSpendTime = getNowTime(),
                }
                if cooldownDuration and numberGT(cooldownDuration, 0) then
                    cocoonState.rechargeStart = cooldownStart or getNowTime()
                    cocoonState.rechargeDuration = cooldownDuration
                    cocoonState.chargeModRate = cooldownModRate
                elseif liveCharges and liveCharges.rechargeDuration then
                    cocoonState.rechargeDuration = liveCharges.rechargeDuration
                    cocoonState.chargeModRate = liveCharges.chargeModRate
                end
                if cocoonState.rechargeDuration and not cocoonState.rechargeStart then
                    cocoonState.rechargeStart = getNowTime()
                end
                updateCachedGlowState(castSpellID, cocoonState)
            end

            if isPowerWordShieldSpell(castSpellID) then
                local previousShieldState = getPowerWordShieldCachedState(castSpellID)
                local observedShieldDuration = getPowerWordShieldObservedCooldownDuration(previousShieldState)
                local cooldownStart
                local cooldownDuration
                local cooldownModRate
                if C_Spell and C_Spell.GetSpellCooldown then
                    local okCooldown, cooldownInfo = pcall(C_Spell.GetSpellCooldown, castSpellID)
                    if okCooldown and type(cooldownInfo) == "table" then
                        cooldownStart = plainNumber(cooldownInfo.startTime)
                        cooldownDuration = plainNumber(cooldownInfo.duration)
                        cooldownModRate = plainNumber(cooldownInfo.modRate)
                    end
                end
                if cooldownDuration and numberGT(cooldownDuration, 0) then
                    if not (cooldownModRate and numberGT(cooldownModRate, 0)) then
                        cooldownModRate = 1
                    end
                    observedShieldDuration = cooldownDuration / cooldownModRate
                end
                if not (observedShieldDuration and numberGT(observedShieldDuration, 0)) then
                    observedShieldDuration = getPowerWordShieldBaseCooldownDuration(castSpellID)
                end
                local shieldNow = getNowTime()
                local shieldState = {
                    cooldownReady = false,
                    lastSpendTime = shieldNow,
                }
                if observedShieldDuration and numberGT(observedShieldDuration, 0) then
                    local cooldownStartTime = cooldownStart
                    if not (cooldownStartTime and numberGT(cooldownStartTime, 0)) then
                        cooldownStartTime = shieldNow
                    end
                    shieldState.rechargeStart = cooldownStartTime
                    shieldState.rechargeDuration = observedShieldDuration
                    shieldState.chargeModRate = 1
                    shieldState.cooldownEndTime = cooldownStartTime + observedShieldDuration
                    shieldState.lastObservedCooldownDuration = observedShieldDuration
                elseif previousShieldState and previousShieldState.lastObservedCooldownDuration then
                    shieldState.lastObservedCooldownDuration = previousShieldState.lastObservedCooldownDuration
                end
                updatePowerWordShieldCachedState(castSpellID, shieldState)
            end
        end
    end

    if event == "SPELLS_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        ensureDefaultTrackedSpellsForActiveSpec()
        refreshOptionsControls()
    end

    refresh()
end)

SLASH_HEALINGPRIORITYMOUSE1 = "/hpm"
SLASH_HEALINGPRIORITYMOUSE2 = "/healingprioritymouse"
SlashCmdList.HEALINGPRIORITYMOUSE = function(msgText)
    local cmd, rest = msgText:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = (rest or ""):lower()

    if cmd == "toggle" then
        HealingPriorityMouseDB.enabled = not HealingPriorityMouseDB.enabled
        msg("enabled = " .. tostring(HealingPriorityMouseDB.enabled))
        refresh()
        refreshOptionsControls()
        return
    end

    if cmd == "version" then
        msg("v" .. ADDON_VERSION)
        return
    end

    if cmd == "options" then
        openOptionsFrame()
        return
    end

    if cmd == "names" then
        if rest == "on" then
            HealingPriorityMouseDB.showSpellNames = true
            msg("showSpellNames = true")
            refresh()
            refreshOptionsControls()
            return
        end
        if rest == "off" then
            HealingPriorityMouseDB.showSpellNames = false
            msg("showSpellNames = false")
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm names on|off")
        return
    end

    if cmd == "namepos" then
        if rest == "top" or rest == "bottom" then
            HealingPriorityMouseDB.spellNamePosition = rest
            msg("spellNamePosition = " .. rest)
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm namepos top|bottom")
        return
    end

    if cmd == "charges" then
        if rest == "on" then
            HealingPriorityMouseDB.showCharges = true
            msg("showCharges = true")
            refresh()
            refreshOptionsControls()
            return
        end
        if rest == "off" then
            HealingPriorityMouseDB.showCharges = false
            msg("showCharges = false")
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm charges on|off")
        return
    end

    if cmd == "glow" then
        if rest == "on" then
            HealingPriorityMouseDB.showGlows = true
            msg("showGlows = true")
            refresh()
            refreshOptionsControls()
            return
        end
        if rest == "off" then
            HealingPriorityMouseDB.showGlows = false
            msg("showGlows = false")
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm glow on|off")
        return
    end

    if cmd == "glowdebug" then
        if rest == "on" then
            HealingPriorityMouseDB.glowDebug = true
            msg("glowDebug = true")
            refresh()
            return
        end
        if rest == "off" then
            HealingPriorityMouseDB.glowDebug = false
            msg("glowDebug = false")
            refresh()
            return
        end
        msg("usage: /hpm glowdebug on|off")
        return
    end

    if cmd == "scale" then
        local val = tonumber(rest)
        if setScaleValue(val) then
            msg("scale = " .. tostring(HealingPriorityMouseDB.scale))
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm scale 0.6-3.0")
        return
    end

    if cmd == "opacity" then
        local val = tonumber(rest)
        if setOpacityPercent(val) then
            local pct = math.floor(((HealingPriorityMouseDB.opacity or 1.0) * 100) + 0.5)
            msg("opacity = " .. pct .. "%")
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm opacity 0-100")
        return
    end

    if cmd == "audit" then
        resolvedSpells = {}
        msg("spell audit for current client:")
        local keys = {
            "Lifebloom", "CenarionWard",
            "Consecration", "ConsecrationAura", "InfusionOfLight", "HolyBulwark",
            "RenewingMist", "StrengthOfTheBlackOx",
            "WaterShield", "HealingStreamTotem", "HealingRain", "Riptide", "CloudburstTotem",
            "Reversion", "Echo", "Lifespark",
            "Atonement", "PowerWordShield", "PowerWordRadiance", "Penance", "PrayerOfMending", "Halo", "Lightweaver", "Premonitions",
        }
        for _, key in ipairs(keys) do
            local spellID = resolveSpellID(key)
            if key == "CloudburstTotem" and not spellID then
                msg(key .. " -> removed in 12.0.0 (expected missing)")
            elseif spellID then
                local known = isSpellKnownSafe(spellID)
                if known then
                    msg(key .. " -> " .. spellID .. " (known)")
                else
                    msg(key .. " -> " .. spellID .. " (exists, not known on this character)")
                end
            else
                msg(key .. " -> missing on this client")
            end
        end
        return
    end

    if cmd == "apidump" then
        local foundAny = false
        for token in string.gmatch(rest or "", "%d+") do
            local spellID = tonumber(token)
            if spellID and dumpSpellAPIDiagnostics(spellID) then
                foundAny = true
            end
        end
        if foundAny then
            return
        end
        msg("usage: /hpm apidump <spellID> [moreSpellIDs]")
        return
    end

    msg("enabled=" .. tostring(HealingPriorityMouseDB.enabled)
        .. ", scale=" .. tostring(HealingPriorityMouseDB.scale)
        .. ", opacity=" .. tostring(math.floor(((HealingPriorityMouseDB.opacity or 1.0) * 100) + 0.5)) .. "%"
        .. ", showCharges=" .. tostring(HealingPriorityMouseDB.showCharges)
        .. ", showGlows=" .. tostring(HealingPriorityMouseDB.showGlows)
        .. ", glowDebug=" .. tostring(HealingPriorityMouseDB.glowDebug)
        .. ", showSpellNames=" .. tostring(HealingPriorityMouseDB.showSpellNames)
        .. ", spellNamePosition=" .. tostring(HealingPriorityMouseDB.spellNamePosition))
end
