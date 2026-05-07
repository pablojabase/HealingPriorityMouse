HealingPriorityMouseNS = HealingPriorityMouseNS or {}
local ns = HealingPriorityMouseNS

ns.modules = ns.modules or {}

local function isTaintSafeNumber(candidate)
    if type(candidate) ~= "number" then
        return nil
    end

    -- Secret numbers can throw when compared; reject those up-front.
    local okCompare = pcall(function()
        return candidate <= 0
    end)
    if not okCompare then
        return nil
    end

    local okMath, numeric = pcall(function()
        return candidate + 0
    end)
    if okMath and type(numeric) == "number" then
        local okNumericCompare = pcall(function()
            return numeric <= 0
        end)
        if okNumericCompare then
            return numeric
        end
    end
    return nil
end

local function safeNumber(value)
    if value == nil then
        return nil
    end

    local numeric = isTaintSafeNumber(value)
    if numeric ~= nil then
        return numeric
    end

    local okToNumber, fallback = pcall(tonumber, value)
    if okToNumber then
        local numericFallback = isTaintSafeNumber(fallback)
        if numericFallback ~= nil then
            return numericFallback
        end
    end

    return nil
end

local function normalizeSpellID(value)
    local numeric = safeNumber(value)
    if numeric == nil then
        return nil
    end
    local okPositive, isPositive = pcall(function()
        return numeric > 0
    end)
    if not okPositive or not isPositive then
        return nil
    end

    local okRound, rounded = pcall(function()
        return math.floor(numeric + 0.5)
    end)
    if okRound and type(rounded) == "number" then
        return rounded
    end
    return nil
end

local function getNow()
    if not GetTime then
        return 0
    end
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then
        return now
    end
    return 0
end

local function addUniqueSpellID(list, seen, spellID)
    local normalized = normalizeSpellID(spellID)
    if not normalized then
        return false
    end
    if seen[normalized] then
        return false
    end
    seen[normalized] = true
    list[#list + 1] = normalized
    return true
end

ns.safeNumber = ns.safeNumber or safeNumber
ns.normalizeSpellID = ns.normalizeSpellID or normalizeSpellID
ns.getNow = ns.getNow or getNow
ns.addUniqueSpellID = ns.addUniqueSpellID or addUniqueSpellID
