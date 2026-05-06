local ns = HealingPriorityMouseNS or {}
HealingPriorityMouseNS = ns

local runtimeServices = ns.runtimeServices or {}
ns.runtimeServices = runtimeServices

local normalizeSpellID
normalizeSpellID = function(value)
    local normalizeProvider = ns.normalizeSpellID
    if type(normalizeProvider) == "function" and normalizeProvider ~= normalizeSpellID then
        local okNormalize, normalizedValue = pcall(normalizeProvider, value)
        if okNormalize and type(normalizedValue) == "number" and normalizedValue > 0 then
            return math.floor(normalizedValue + 0.5)
        end
    end

    local numberProvider = ns.safeNumber
    local numeric = nil
    if type(numberProvider) == "function" then
        local okNumber, numberValue = pcall(numberProvider, value)
        if okNumber and type(numberValue) == "number" then
            numeric = numberValue
        end
    end
    if numeric == nil then
        numeric = tonumber(value)
    end
    if not numeric or numeric <= 0 then
        return nil
    end
    return math.floor(numeric + 0.5)
end

local getNow
getNow = function()
    local nowProvider = ns.getNow
    if type(nowProvider) == "function" and nowProvider ~= getNow then
        local okNow, nowValue = pcall(nowProvider)
        if okNow and type(nowValue) == "number" then
            return nowValue
        end
    end
    if not GetTime then
        return 0
    end
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then
        return now
    end
    return 0
end

local state = runtimeServices.combatHardeningState or {
    auraLookupDirty = true,
    auraLookup = {},
    auraLookupCount = 0,
    auraInstanceSpellByUnit = {},
    skipCounter = 0,
    processCounter = 0,
    castVerifyDelays = { 0.07, 0.18 },
    castVerifyRevision = 0,
    castVerifyRevisionBySpell = {},
}
runtimeServices.combatHardeningState = state

local function wipeMap(map)
    if type(map) ~= "table" then
        return
    end
    for key in pairs(map) do
        map[key] = nil
    end
end

local function getSafeTableField(tbl, key)
    if type(tbl) ~= "table" then
        return nil
    end
    local ok, value = pcall(function()
        return tbl[key]
    end)
    if ok then
        return value
    end
    return nil
end

local function getUnitAuraInstanceMap(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local byUnit = state.auraInstanceSpellByUnit
    local map = byUnit[unit]
    if type(map) ~= "table" then
        map = {}
        byUnit[unit] = map
    end
    return map
end

local function trackAuraInstanceSpell(unit, auraInstanceID, spellID)
    local normalizedAuraInstanceID = normalizeSpellID(auraInstanceID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedAuraInstanceID or not normalizedSpellID then
        return
    end
    local map = getUnitAuraInstanceMap(unit)
    if map then
        map[normalizedAuraInstanceID] = normalizedSpellID
    end
end

local function untrackAuraInstanceSpell(unit, auraInstanceID)
    local normalizedAuraInstanceID = normalizeSpellID(auraInstanceID)
    if not normalizedAuraInstanceID then
        return
    end
    local map = getUnitAuraInstanceMap(unit)
    if map then
        map[normalizedAuraInstanceID] = nil
    end
end

local function getTrackedAuraSpellForInstance(unit, auraInstanceID)
    local normalizedAuraInstanceID = normalizeSpellID(auraInstanceID)
    if not normalizedAuraInstanceID then
        return nil
    end
    local map = getUnitAuraInstanceMap(unit)
    if not map then
        return nil
    end
    return map[normalizedAuraInstanceID]
end

local function isRelevantAuraSpellID(spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID then
        return false
    end
    return state.auraLookup[normalizedSpellID] == true
end

local function rebuildAuraLookup()
    if state.auraLookupDirty ~= true then
        return
    end

    wipeMap(state.auraLookup)
    state.auraLookupCount = 0

    local provider = state.auraRelevanceProvider
    if type(provider) == "function" then
        local ok, spellIDs = pcall(provider)
        if ok and type(spellIDs) == "table" then
            for index = 1, #spellIDs do
                local spellID = normalizeSpellID(spellIDs[index])
                if spellID and state.auraLookup[spellID] ~= true then
                    state.auraLookup[spellID] = true
                    state.auraLookupCount = state.auraLookupCount + 1
                end
            end
        end
    end

    state.auraLookupDirty = false
end

runtimeServices.setAuraRelevanceProvider = function(provider)
    if type(provider) == "function" then
        state.auraRelevanceProvider = provider
    else
        state.auraRelevanceProvider = nil
    end
    state.auraLookupDirty = true
end

runtimeServices.invalidateAuraRelevanceLookup = function()
    state.auraLookupDirty = true
end

runtimeServices.resetAuraInstanceTracking = function(unit)
    if type(unit) == "string" and unit ~= "" then
        state.auraInstanceSpellByUnit[unit] = nil
        return
    end
    wipeMap(state.auraInstanceSpellByUnit)
end

runtimeServices.shouldSkipUnitAuraRefresh = function(unit, updateInfo)
    if type(updateInfo) ~= "table" then
        state.processCounter = (state.processCounter or 0) + 1
        return false
    end

    rebuildAuraLookup()

    if (state.auraLookupCount or 0) <= 0 then
        state.skipCounter = (state.skipCounter or 0) + 1
        return true
    end

    if getSafeTableField(updateInfo, "isFullUpdate") == true then
        state.processCounter = (state.processCounter or 0) + 1
        runtimeServices.resetAuraInstanceTracking(unit)
        return false
    end

    local addedAuras = getSafeTableField(updateInfo, "addedAuras")
    if type(addedAuras) == "table" then
        for index = 1, #addedAuras do
            local auraInfo = addedAuras[index]
            local spellID = getSafeTableField(auraInfo, "spellId")
            if isRelevantAuraSpellID(spellID) then
                trackAuraInstanceSpell(unit, getSafeTableField(auraInfo, "auraInstanceID"), spellID)
                state.processCounter = (state.processCounter or 0) + 1
                return false
            end
        end
    end

    local updatedAuraInstanceIDs = getSafeTableField(updateInfo, "updatedAuraInstanceIDs")
    if type(updatedAuraInstanceIDs) == "table" then
        for index = 1, #updatedAuraInstanceIDs do
            local auraInstanceID = updatedAuraInstanceIDs[index]
            local knownSpellID = getTrackedAuraSpellForInstance(unit, auraInstanceID)
            if knownSpellID and isRelevantAuraSpellID(knownSpellID) then
                state.processCounter = (state.processCounter or 0) + 1
                return false
            end

            if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
                local okAura, auraInfo = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
                local auraSpellID = getSafeTableField(auraInfo, "spellId")
                if okAura and type(auraInfo) == "table" and isRelevantAuraSpellID(auraSpellID) then
                    trackAuraInstanceSpell(unit, auraInstanceID, auraSpellID)
                    state.processCounter = (state.processCounter or 0) + 1
                    return false
                end
            end
        end
    end

    local removedAuraInstanceIDs = getSafeTableField(updateInfo, "removedAuraInstanceIDs")
    if type(removedAuraInstanceIDs) == "table" then
        for index = 1, #removedAuraInstanceIDs do
            local auraInstanceID = removedAuraInstanceIDs[index]
            local knownSpellID = getTrackedAuraSpellForInstance(unit, auraInstanceID)
            if knownSpellID and isRelevantAuraSpellID(knownSpellID) then
                untrackAuraInstanceSpell(unit, auraInstanceID)
                state.processCounter = (state.processCounter or 0) + 1
                return false
            end
            untrackAuraInstanceSpell(unit, auraInstanceID)
        end
    end

    state.skipCounter = (state.skipCounter or 0) + 1
    return true
end

runtimeServices.scheduleCastVerificationRefresh = function(spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID then
        return
    end

    state.castVerifyRevision = (state.castVerifyRevision or 0) + 1
    local revisionBySpell = state.castVerifyRevisionBySpell
    if type(revisionBySpell) ~= "table" then
        revisionBySpell = {}
        state.castVerifyRevisionBySpell = revisionBySpell
    end
    local revision = (revisionBySpell[normalizedSpellID] or 0) + 1
    revisionBySpell[normalizedSpellID] = revision

    local delays = state.castVerifyDelays
    if type(delays) ~= "table" or #delays == 0 then
        delays = { 0.07, 0.18 }
        state.castVerifyDelays = delays
    end

    for index = 1, #delays do
        local delay = delays[index]
        if type(delay) == "number" and delay > 0 and C_Timer and C_Timer.After then
            C_Timer.After(delay, function()
                if (state.castVerifyRevisionBySpell or {})[normalizedSpellID] ~= revision then
                    return
                end
                if type(runtimeServices.invalidateSpellRuntimeCache) == "function" then
                    runtimeServices.invalidateSpellRuntimeCache()
                end
                if type(runtimeServices.queueRefresh) == "function" then
                    runtimeServices.queueRefresh({
                        reason = "cast-verify:" .. tostring(normalizedSpellID) .. ":" .. tostring(index),
                    })
                end
            end)
        end
    end
end

runtimeServices.getCombatHardeningStats = function()
    rebuildAuraLookup()
    return {
        auraLookupCount = state.auraLookupCount or 0,
        skipCounter = state.skipCounter or 0,
        processCounter = state.processCounter or 0,
        castVerifyRevision = state.castVerifyRevision or 0,
        now = getNow(),
    }
end
