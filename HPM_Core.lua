HealingPriorityMouseNS = HealingPriorityMouseNS or {}
local ns = HealingPriorityMouseNS

ns.modules = ns.modules or {}

local function safeNumber(value)
    if value == nil then
        return nil
    end

    local okMath, numeric = pcall(function()
        return value + 0
    end)
    if okMath and type(numeric) == "number" then
        return numeric
    end

    local okToNumber, fallback = pcall(tonumber, value)
    if okToNumber and type(fallback) == "number" then
        return fallback
    end

    return nil
end

local function normalizeSpellID(value)
    local numeric = safeNumber(value)
    if not numeric or numeric <= 0 then
        return nil
    end
    return math.floor(numeric + 0.5)
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
