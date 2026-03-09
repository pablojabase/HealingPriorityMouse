local ADDON_NAME = ...
local ADDON_VERSION = "1.0.7"

HealingPriorityMouseDB = HealingPriorityMouseDB or {}

local defaults = {
    enabled = true,
    scale = 1.0,
    undergrowthMode = "auto", -- auto | on | off
    showCharges = true,
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

local function getCooldownReady(spellID)
    if not IsPlayerSpell(spellID) then
        return false
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if not info then
            return false
        end
        -- Midnight can return secret booleans; avoid direct truth tests on API fields.
        if isFalseFlag(info.isEnabled, false) then
            return false
        end
        local duration = plainNumber(info.duration)
        if duration and numberLE(duration, 0) then
            return true
        end
        if isTrueFlag(info.isOnGCD, false) and duration and numberLE(duration, 1.7) then
            return true
        end
        return false
    end
    return IsUsableSpell(spellID)
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
    if undergrowthID and IsPlayerSpell(undergrowthID) then
        return 2
    end
    return 1
end

local root = CreateFrame("Frame", "HealingPriorityMouseFrame", UIParent)
root:SetSize(1, 1)
root:SetFrameStrata("HIGH")
root:Hide()

local iconFrames = {}

local function ensureIcon(index)
    if iconFrames[index] then
        return iconFrames[index]
    end
    local frame = CreateFrame("Frame", nil, root, "BackdropTemplate")
    frame:SetSize(26, 26)
    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropBorderColor(0.1, 0.45, 1.0, 0.95)

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
        if pwsID and getCooldownReady(pwsID) then
            addEntry("Power Word: Shield", pwsID)
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
        -- Intentionally hide spell names; only icon and in-icon counters are shown.
        f.label:SetText("")

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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
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
        msg("loaded v" .. ADDON_VERSION)
        refresh()
        return
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
        return
    end

    if cmd == "version" then
        msg("v" .. ADDON_VERSION)
        return
    end

    if cmd == "undergrowth" then
        if rest == "on" or rest == "off" or rest == "auto" then
            HealingPriorityMouseDB.undergrowthMode = rest
            msg("undergrowthMode = " .. rest)
            refresh()
            return
        end
        msg("usage: /hpm undergrowth on|off|auto")
        return
    end

    if cmd == "charges" then
        if rest == "on" then
            HealingPriorityMouseDB.showCharges = true
            msg("showCharges = true")
            refresh()
            return
        end
        if rest == "off" then
            HealingPriorityMouseDB.showCharges = false
            msg("showCharges = false")
            refresh()
            return
        end
        msg("usage: /hpm charges on|off")
        return
    end

    if cmd == "scale" then
        local val = tonumber(rest)
        if val and val >= 0.6 and val <= 2.0 then
            HealingPriorityMouseDB.scale = val
            msg("scale = " .. val)
            refresh()
            return
        end
        msg("usage: /hpm scale 0.6-2.0")
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
                local known = IsPlayerSpell and IsPlayerSpell(spellID)
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

    msg("enabled=" .. tostring(HealingPriorityMouseDB.enabled) .. ", scale=" .. tostring(HealingPriorityMouseDB.scale) .. ", undergrowthMode=" .. tostring(HealingPriorityMouseDB.undergrowthMode) .. ", showCharges=" .. tostring(HealingPriorityMouseDB.showCharges))
end
