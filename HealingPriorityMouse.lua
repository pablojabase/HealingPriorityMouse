local ADDON_NAME = ...
local ADDON_VERSION = "1.0.13-beta.2"

HealingPriorityMouseDB = HealingPriorityMouseDB or {}

local defaults = {
    enabled = true,
    scale = 1.0,
    opacity = 1.0,
    showSpellNames = false,
    spellNamePosition = "bottom", -- bottom | top
    undergrowthMode = "auto", -- auto | on | off
    showCharges = true,
    debugLogEnabled = false,
    debugLogMax = 300,
    debugLog = {},
}

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
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffHealingPriorityMouse|r: " .. tostring(text))
end

local function pushDebugLog(line)
    if not HealingPriorityMouseDB.debugLogEnabled then
        return
    end
    if type(HealingPriorityMouseDB.debugLog) ~= "table" then
        HealingPriorityMouseDB.debugLog = {}
    end

    local ts = date("%H:%M:%S")
    local record = "[" .. ts .. "] " .. tostring(line)
    table.insert(HealingPriorityMouseDB.debugLog, record)

    local maxEntries = tonumber(HealingPriorityMouseDB.debugLogMax) or 300
    if maxEntries < 50 then
        maxEntries = 50
    end
    while #HealingPriorityMouseDB.debugLog > maxEntries do
        table.remove(HealingPriorityMouseDB.debugLog, 1)
    end
end

local function clearDebugLog()
    HealingPriorityMouseDB.debugLog = {}
end

local function dumpDebugLog(limit)
    local logs = HealingPriorityMouseDB.debugLog
    if type(logs) ~= "table" or #logs == 0 then
        msg("debug log is empty")
        return
    end

    local n = tonumber(limit) or 40
    if n < 1 then
        n = 1
    end
    if n > 200 then
        n = 200
    end

    local startIndex = math.max(1, #logs - n + 1)
    msg("debug log dump (" .. tostring(#logs - startIndex + 1) .. "/" .. tostring(#logs) .. "):")
    for i = startIndex, #logs do
        msg(logs[i])
    end
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
    UndergrowthTalent = { 203374 },

    Consecration = { 26573 },
    ConsecrationAura = { 188370 },
    InfusionOfLight = { 54149 },
    HolyBulwark = { 432459, 432472 },

    RenewingMist = { 115151 },
    StrengthOfTheBlackOx = { 443112 },

    WaterShield = { 52127, 79949, 36816, 52128, 79950, 127939, 173164, 235976, 289211, 412686, 412687 },
    HealingRain = { 73920 },
    Riptide = { 61295 },
    -- Cloudburst Totem (157153) was removed in patch 12.0.0.
    CloudburstTotem = { 157153 },

    Reversion = { 366155 },
    Echo = { 364343 },
    Lifespark = { 443176 },

    Atonement = { 194384 },
    PowerWordShield = { 17 },
    PrayerOfMending = { 33076 },
    Halo = { 120517 },
    Lightweaver = { 390993 },
    Premonitions = { 428933, 428934, 438733, 438855 },
}

local resolvedSpells = {}
local cooldownCache = {}
local pwsDebugGate = {
    lastKey = nil,
    lastAt = 0,
}

local function isPowerWordShieldSpell(spellID)
    local pwsID = resolveSpellID("PowerWordShield")
    return pwsID and spellID == pwsID
end

local function logPwsDecision(key, text)
    if not HealingPriorityMouseDB.debugLogEnabled then
        return
    end
    local now = GetTime()
    local dedupeKey = tostring(key or "") .. ":" .. tostring(text or "")
    if pwsDebugGate.lastKey == dedupeKey and (now - (pwsDebugGate.lastAt or 0)) < 0.25 then
        return
    end
    pwsDebugGate.lastKey = dedupeKey
    pwsDebugGate.lastAt = now
    pushDebugLog("PWS " .. tostring(text))
end

local function resolveSpellID(key)
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
    local filter = helpful and "HELPFUL" or "HARMFUL"
    if fromPlayer then
        filter = filter .. "|PLAYER"
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, filter)
        if not ok then
            return false
        end
        local nilOk, isNil = pcall(function()
            return aura == nil
        end)
        return nilOk and (not isNil) or false
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

local function getSafeCharges(spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then
        return nil
    end

    local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
    if not ok or type(charges) ~= "table" then
        return nil
    end

    local current = plainNumber(charges.currentCharges)
    local max = plainNumber(charges.maxCharges)

    if current and max then
        return {
            current = current,
            max = max,
            unknown = false,
        }
    end

    if not isNilValue(charges.currentCharges) or not isNilValue(charges.maxCharges) then
        return {
            unknown = true,
        }
    end

    return nil
end

local function isSpellKnownSafe(spellID)
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

local function isCooldownDurationReady(duration, isOnGCD)
    if duration and numberLE(duration, 0) then
        return true
    end
    if isOnGCD and duration and numberLE(duration, 1.7) then
        return true
    end
    return false
end

local function updateCooldownCache(spellID)
    if not spellID then
        return
    end
    if not (C_Spell and C_Spell.GetSpellCooldown) then
        return
    end

    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or not info then
        return
    end

    local duration = plainNumber(info.duration)
    local startTime = plainNumber(info.startTime)
    local isOnGCD = isTrueFlag(info.isOnGCD, false)
    local ready = isCooldownDurationReady(duration, isOnGCD)
    local endTime = nil

    if startTime and duration then
        endTime = startTime + duration
        if numberLE(endTime, GetTime()) then
            ready = true
        end
    end

    cooldownCache[spellID] = {
        ready = ready,
        endTime = endTime,
        updatedAt = GetTime(),
    }

    if isPowerWordShieldSpell(spellID) then
        logPwsDecision("cache-update", "cache update: ready=" .. tostring(ready)
            .. ", start=" .. tostring(startTime)
            .. ", duration=" .. tostring(duration)
            .. ", isOnGCD=" .. tostring(isOnGCD)
            .. ", inCombat=" .. tostring(UnitAffectingCombat("player")))
    end
end

local function getCachedCooldownReady(spellID)
    local cached = cooldownCache[spellID]
    if not cached then
        return nil
    end

    if cached.endTime and numberLE(cached.endTime, GetTime()) then
        return true
    end

    return cached.ready and true or false
end

local function refreshTrackedCooldownCaches()
    local pwsID = resolveSpellID("PowerWordShield")
    if pwsID then
        updateCooldownCache(pwsID)
    end
end

local function getCooldownReady(spellID, options)
    options = options or {}
    local allowCacheFallback = options.allowCacheFallback and true or false

    local isPws = isPowerWordShieldSpell(spellID)

    if not isSpellKnownSafe(spellID) then
        if isPws then
            logPwsDecision("known", "blocked: spell not known")
        end
        return false
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if not ok or not info then
            if allowCacheFallback then
                local cached = getCachedCooldownReady(spellID)
                if cached ~= nil then
                    if isPws then
                        logPwsDecision("api-fail-cache", "api read failed -> cache=" .. tostring(cached))
                    end
                    return cached
                end
            end
            local usableFallback = isSpellUsableSafe(spellID)
            if isPws then
                logPwsDecision("api-fail-usable", "api read failed -> usable=" .. tostring(usableFallback))
            end
            return usableFallback
        end
        -- Midnight can return secret booleans; avoid direct truth tests on API fields.
        if isFalseFlag(info.isEnabled, false) then
            if allowCacheFallback then
                local cached = getCachedCooldownReady(spellID)
                if cached ~= nil then
                    if isPws then
                        logPwsDecision("disabled-cache", "isEnabled=false -> cache=" .. tostring(cached))
                    end
                    return cached
                end
            end
            local usableFallback = isSpellUsableSafe(spellID)
            if isPws then
                logPwsDecision("disabled-usable", "isEnabled=false -> usable=" .. tostring(usableFallback))
            end
            return usableFallback
        end
        local duration = plainNumber(info.duration)
        local isOnGCD = isTrueFlag(info.isOnGCD, false)
        if isCooldownDurationReady(duration, isOnGCD) then
            if allowCacheFallback then
                updateCooldownCache(spellID)
            end
            if isPws then
                logPwsDecision("live-ready", "live ready: duration=" .. tostring(duration) .. ", isOnGCD=" .. tostring(isOnGCD))
            end
            return true
        end

        if allowCacheFallback then
            updateCooldownCache(spellID)
            local cached = getCachedCooldownReady(spellID)
            if cached ~= nil then
                if isPws then
                    logPwsDecision("not-ready-cache", "live not ready -> cache=" .. tostring(cached)
                        .. ", duration=" .. tostring(duration) .. ", isOnGCD=" .. tostring(isOnGCD))
                end
                return cached
            end
        end

        local usableFallback = isSpellUsableSafe(spellID)
        if isPws then
            logPwsDecision("not-ready-usable", "live not ready -> usable=" .. tostring(usableFallback)
                .. ", duration=" .. tostring(duration) .. ", isOnGCD=" .. tostring(isOnGCD))
        end
        return usableFallback
    end

    if allowCacheFallback then
        local cached = getCachedCooldownReady(spellID)
        if cached ~= nil then
            if isPws then
                logPwsDecision("no-cspell-cache", "no C_Spell -> cache=" .. tostring(cached))
            end
            return cached
        end
    end

    local usableFallback = isSpellUsableSafe(spellID)
    if isPws then
        logPwsDecision("no-cspell-usable", "no C_Spell -> usable=" .. tostring(usableFallback))
    end
    return usableFallback
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

local function getSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return specID
end

local function getLifebloomTargetThreshold()
    local mode = HealingPriorityMouseDB.undergrowthMode
    if mode == "on" then
        return 2
    end
    if mode == "off" then
        return 1
    end
    -- Auto detection: try modern talent node first, then older spell-based fallback.
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if configID and C_Traits and C_Traits.GetNodeInfo then
        -- NodeID observed in the WA load.talent mapping for Undergrowth.
        local nodeInfo = C_Traits.GetNodeInfo(configID, 103133)
        if isNodeRankActive(nodeInfo) then
            return 2
        end
    end

    -- Legacy fallback for old spell-based talent IDs.
    local undergrowthID = resolveSpellID("UndergrowthTalent")
    if undergrowthID and isSpellKnownSafe(undergrowthID) then
        return 2
    end
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

    iconFrames[index] = frame
    return frame
end

local function hideAllIcons()
    for _, frame in ipairs(iconFrames) do
        frame:Hide()
    end
end

local function getEssenceCount()
    -- 19 is Essence power type in modern retail.
    local essence = UnitPower("player", 19)
    return essence or 0
end

local function buildEntries()
    local specID = getSpecID()
    if not specID then
        return {}
    end

    local mouseover = getFriendlyMouseover()
    local entries = {}

    local function addEntry(name, spellID, iconCount)
        if not spellID then
            return
        end
        entries[#entries + 1] = {
            name = name,
            spellID = spellID,
            icon = getSpellTexture(spellID) or 136243,
            iconCount = iconCount,
        }
    end

    if specID == 105 then
        local lifebloomID = resolveSpellID("Lifebloom")
        local lbCount = lifebloomID and countAuraInGroup(lifebloomID, true) or 0
        local threshold = getLifebloomTargetThreshold()
        if lifebloomID and lbCount < threshold then
            addEntry("Lifebloom", lifebloomID)
        end
        local cenWardID = resolveSpellID("CenarionWard")
        if mouseover and cenWardID and getCooldownReady(cenWardID) then
            addEntry("Cenarion Ward", cenWardID)
        end
    elseif specID == 65 then
        local consecrationID = resolveSpellID("Consecration")
        local consecrationAuraID = resolveSpellID("ConsecrationAura")
        if consecrationID and getCooldownReady(consecrationID)
            and (not consecrationAuraID or not isAuraActive("player", consecrationAuraID, true, true)) then
            addEntry("Consecration", consecrationID)
        end
        local infusionID = resolveSpellID("InfusionOfLight")
        if infusionID and isAuraActive("player", infusionID, true, true) then
            addEntry("Infusion of Light", infusionID)
        end
        local holyBulwarkID = resolveSpellID("HolyBulwark")
        if holyBulwarkID and getCooldownReady(holyBulwarkID) then
            addEntry("Holy Bulwark", holyBulwarkID)
        end
    elseif specID == 270 then
        local renewingMistID = resolveSpellID("RenewingMist")
        if renewingMistID and getCooldownReady(renewingMistID) then
            addEntry("Renewing Mist", renewingMistID)
        end
        local blackOxID = resolveSpellID("StrengthOfTheBlackOx")
        if blackOxID and isAuraActive("player", blackOxID, true, true) then
            addEntry("Strength of the Black Ox", blackOxID)
        end
    elseif specID == 264 then
        local waterShieldID = resolveSpellID("WaterShield")
        if waterShieldID and not isAuraActive("player", waterShieldID, true, true) and getCooldownReady(waterShieldID) then
            addEntry("Water Shield", waterShieldID)
        end
        local healingRainID = resolveSpellID("HealingRain")
        if healingRainID and getCooldownReady(healingRainID) then
            addEntry("Healing Rain", healingRainID)
        end
        local riptideID = resolveSpellID("Riptide")
        if riptideID and getCooldownReady(riptideID) then
            addEntry("Riptide", riptideID)
        end
        local cloudburstID = resolveSpellID("CloudburstTotem")
        if cloudburstID and getCooldownReady(cloudburstID) then
            addEntry("Cloudburst Totem", cloudburstID)
        end
    elseif specID == 1468 then
        local reversionID = resolveSpellID("Reversion")
        if reversionID and getCooldownReady(reversionID) then
            if mouseover then
                if not isAuraActive(mouseover, reversionID, true, true) then
                    addEntry("Reversion", reversionID)
                end
            else
                local alive = countAliveGroupUnits()
                local activeReversions = countAuraInGroup(reversionID, true)
                if activeReversions < alive then
                    addEntry("Reversion", reversionID)
                end
            end
        end
        local echoID = resolveSpellID("Echo")
        if echoID and getCooldownReady(echoID) and getEssenceCount() >= 2 then
            addEntry("Echo", echoID)
        end
        local lifesparkID = resolveSpellID("Lifespark")
        if lifesparkID and isAuraActive("player", lifesparkID, true, true) then
            addEntry("Lifespark", lifesparkID)
        end
    elseif specID == 256 then
        local atonementID = resolveSpellID("Atonement")
        local atonementCount = atonementID and countAuraInGroup(atonementID, true) or 0
        if atonementID then
            addEntry("Atonement", atonementID, tostring(atonementCount))
        end

        local pwsID = resolveSpellID("PowerWordShield")
        local pwsReady = pwsID and getCooldownReady(pwsID, { allowCacheFallback = true })
        if pwsID and pwsReady then
            addEntry("Power Word: Shield", pwsID)
        end
        if pwsID then
            logPwsDecision("entry", "entry decision: ready=" .. tostring(pwsReady)
                .. ", inCombat=" .. tostring(UnitAffectingCombat("player"))
                .. ", atonementCount=" .. tostring(atonementCount))
        end
    elseif specID == 257 then
        local pomID = resolveSpellID("PrayerOfMending")
        if pomID and getCooldownReady(pomID) then
            addEntry("Prayer of Mending", pomID)
        end
        local haloID = resolveSpellID("Halo")
        if haloID and getCooldownReady(haloID) then
            addEntry("Halo", haloID)
        end
        local lightweaverID = resolveSpellID("Lightweaver")
        if lightweaverID and isAuraActive("player", lightweaverID, true, true) then
            addEntry("Lightweaver", lightweaverID)
        end
        local premonitionsReadyID = resolveAnySpellID({ "Premonitions" })
        if premonitionsReadyID and getCooldownReady(premonitionsReadyID) then
            addEntry("Premonitions", premonitionsReadyID)
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
            local info = C_Spell.GetSpellCooldown(entries[i].spellID)
            local startTime = info and plainNumber(info.startTime)
            local duration = info and plainNumber(info.duration)
            local isOnGCD = info and isTrueFlag(info.isOnGCD, false)
            if info and startTime and duration and numberGT(duration, 1.5) and not isOnGCD then
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
            local charges = getSafeCharges(entries[i].spellID)
            if charges and charges.unknown then
                f.chargeText:SetText("?")
                f.chargeText:Show()
            elseif charges and charges.max and numberGT(charges.max, 1) then
                f.chargeText:SetText(tostring(charges.current or 0))
                f.chargeText:Show()
            else
                f.chargeText:Hide()
            end
        else
            f.chargeText:Hide()
        end

        f:Show()
    end

    for i = #entries + 1, #iconFrames do
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
    layoutEntries(buildEntries())
end

local function refreshOptionsControls()
    if not optionsFrame or not optionsControls then
        return
    end

    local db = HealingPriorityMouseDB
    optionsControls.enabled:SetChecked(db.enabled and true or false)
    optionsControls.charges:SetChecked(db.showCharges and true or false)
    optionsControls.showNames:SetChecked(db.showSpellNames and true or false)

    UIDropDownMenu_SetSelectedValue(optionsControls.undergrowth, db.undergrowthMode)
    UIDropDownMenu_SetSelectedValue(optionsControls.namePosition, db.spellNamePosition)

    local scaleValue = clampScale(tonumber(db.scale) or 1.0) or 1.0
    optionsControls.scaleSlider:SetValue(scaleValue)
    optionsControls.scaleInput:SetText(string.format("%.2f", scaleValue))

    local opacityValue = clampOpacity(tonumber(db.opacity) or 1.0) or 1.0
    optionsControls.opacitySlider:SetValue(opacityValue)
    optionsControls.opacityInput:SetText(tostring(math.floor((opacityValue * 100) + 0.5)))
end

local function createOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local frame = CreateFrame("Frame", "HealingPriorityMouseOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(430, 470)
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
    frame.title:SetText("HealingPriorityMouse Options")

    local enabled = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    enabled:SetPoint("TOPLEFT", 16, -36)
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

    local showNames = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
    showNames:SetPoint("TOPLEFT", charges, "BOTTOMLEFT", 0, -8)
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

    local undergrowthLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    undergrowthLabel:SetPoint("TOPLEFT", namePosition, "BOTTOMLEFT", 16, -18)
    undergrowthLabel:SetText("Undergrowth mode")

    local undergrowth = CreateFrame("Frame", "HealingPriorityMouseUndergrowthDropdown", frame, "UIDropDownMenuTemplate")
    undergrowth:SetPoint("TOPLEFT", undergrowthLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(undergrowth, 120)
    UIDropDownMenu_Initialize(undergrowth, function(self, level)
        local function addOption(label, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = value
            info.checked = (HealingPriorityMouseDB.undergrowthMode == value)
            info.func = function()
                HealingPriorityMouseDB.undergrowthMode = value
                UIDropDownMenu_SetSelectedValue(self, value)
                refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        addOption("Auto", "auto")
        addOption("On", "on")
        addOption("Off", "off")
    end)

    local scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", undergrowth, "BOTTOMLEFT", 16, -20)
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

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(90, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    optionsControls = {
        enabled = enabled,
        charges = charges,
        showNames = showNames,
        namePosition = namePosition,
        undergrowth = undergrowth,
        scaleSlider = scaleSlider,
        scaleInput = scaleInput,
        opacitySlider = opacitySlider,
        opacityInput = opacityInput,
    }

    frame:SetScript("OnShow", function()
        refreshOptionsControls()
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
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end
        copyDefaults(HealingPriorityMouseDB, defaults)
        refreshTrackedCooldownCaches()
        msg("loaded v" .. ADDON_VERSION)
        refresh()
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "TRAIT_CONFIG_UPDATED" then
        refreshTrackedCooldownCaches()
    end

    if event == "UNIT_AURA" and arg1 and arg1 ~= "player" and arg1 ~= "mouseover" then
        if not arg1:match("^party") and not arg1:match("^raid") then
            return
        end
    end

    if event == "UNIT_POWER_UPDATE" and arg1 ~= "player" then
        return
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

    if cmd == "undergrowth" then
        if rest == "on" or rest == "off" or rest == "auto" then
            HealingPriorityMouseDB.undergrowthMode = rest
            msg("undergrowthMode = " .. rest)
            refresh()
            refreshOptionsControls()
            return
        end
        msg("usage: /hpm undergrowth on|off|auto")
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
            "Lifebloom", "CenarionWard", "UndergrowthTalent",
            "Consecration", "ConsecrationAura", "InfusionOfLight", "HolyBulwark",
            "RenewingMist", "StrengthOfTheBlackOx",
            "WaterShield", "HealingRain", "Riptide", "CloudburstTotem",
            "Reversion", "Echo", "Lifespark",
            "Atonement", "PowerWordShield", "PrayerOfMending", "Halo", "Lightweaver", "Premonitions",
        }
        for _, key in ipairs(keys) do
            local spellID = resolveSpellID(key)
            if key == "CloudburstTotem" and not spellID then
                msg(key .. " -> removed in 12.0.0 (expected missing)")
            elseif key == "UndergrowthTalent" and not spellID then
                local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
                if configID and C_Traits and C_Traits.GetNodeInfo then
                    local nodeInfo = C_Traits.GetNodeInfo(configID, 103133)
                    if isNodeRankActive(nodeInfo) then
                        msg(key .. " -> node 103133 active (ok)")
                    else
                        msg(key .. " -> node 103133 not active (ok if not talented)")
                    end
                else
                    msg(key .. " -> missing spell id; node-based detection unavailable")
                end
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

    if cmd == "debug" then
        if rest == "on" then
            HealingPriorityMouseDB.debugLogEnabled = true
            msg("debug log enabled")
            pushDebugLog("debug enabled")
            return
        end
        if rest == "off" then
            pushDebugLog("debug disabled")
            HealingPriorityMouseDB.debugLogEnabled = false
            msg("debug log disabled")
            return
        end
        if rest == "clear" then
            clearDebugLog()
            msg("debug log cleared")
            return
        end
        local dumpCount = rest:match("^dump%s*(%d*)$")
        if dumpCount ~= nil then
            if dumpCount == "" then
                dumpDebugLog(40)
            else
                dumpDebugLog(tonumber(dumpCount))
            end
            return
        end
        msg("usage: /hpm debug on|off|dump [n]|clear")
        return
    end

    msg("enabled=" .. tostring(HealingPriorityMouseDB.enabled)
        .. ", scale=" .. tostring(HealingPriorityMouseDB.scale)
        .. ", opacity=" .. tostring(math.floor(((HealingPriorityMouseDB.opacity or 1.0) * 100) + 0.5)) .. "%"
        .. ", undergrowthMode=" .. tostring(HealingPriorityMouseDB.undergrowthMode)
        .. ", showCharges=" .. tostring(HealingPriorityMouseDB.showCharges)
        .. ", showSpellNames=" .. tostring(HealingPriorityMouseDB.showSpellNames)
        .. ", spellNamePosition=" .. tostring(HealingPriorityMouseDB.spellNamePosition))
end
