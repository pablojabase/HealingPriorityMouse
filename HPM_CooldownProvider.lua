local ns = HealingPriorityMouseNS or {}
HealingPriorityMouseNS = ns

local normalizeSpellID = ns.normalizeSpellID or function(value)
    local numberValue = tonumber(value)
    if not numberValue or numberValue <= 0 then
        return nil
    end
    return math.floor(numberValue + 0.5)
end
local addUniqueSpellID = ns.addUniqueSpellID or function(list, seen, spellID)
    local normalized = normalizeSpellID(spellID)
    if not normalized or seen[normalized] then
        return false
    end
    seen[normalized] = true
    list[#list + 1] = normalized
    return true
end
local getNow = ns.getNow or function()
    if not GetTime then
        return 0
    end
    local ok, now = pcall(GetTime)
    if ok and type(now) == "number" then
        return now
    end
    return 0
end

local REBUILD_THROTTLE_SECONDS = 0.20

local PROVIDER_MODE_NATIVE = "native"
local PROVIDER_MODE_CDM_HYBRID = "cdm-hybrid"

local PROVIDER_EVENTS = {
    COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = true,
    COOLDOWN_VIEWER_TABLE_HOTFIXED = true,
    COOLDOWN_VIEWER_DATA_LOADED = true,
    SPELLS_CHANGED = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
}

local ALERT_NAME_BY_VALUE = {
    [1] = "Available",
    [2] = "PandemicTime",
    [3] = "OnCooldown",
    [4] = "ChargeGained",
    [5] = "OnAuraApplied",
    [6] = "OnAuraRemoved",
}
local ALERT_VALUE_BY_NAME = {
    Available = 1,
    PandemicTime = 2,
    OnCooldown = 3,
    ChargeGained = 4,
    OnAuraApplied = 5,
    OnAuraRemoved = 6,
}

local SPELL_FLAG_HIDE_AURA = 1
local SPELL_FLAG_HIDE_BY_DEFAULT = 2

local bitBand = nil
local bitBor = nil
if bit and type(bit.band) == "function" then
    bitBand = bit.band
    bitBor = bit.bor
elseif bit32 and type(bit32.band) == "function" then
    bitBand = bit32.band
    bitBor = bit32.bor
end

local hasCDMApi

local function safeTableField(tbl, key)
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

local function addAliasEdge(aliasGraph, sourceSpellID, aliasSpellID)
    local sourceID = normalizeSpellID(sourceSpellID)
    local aliasID = normalizeSpellID(aliasSpellID)
    if not sourceID or not aliasID or sourceID == aliasID then
        return false
    end

    local sourceAliases = aliasGraph[sourceID]
    if type(sourceAliases) ~= "table" then
        sourceAliases = {}
        aliasGraph[sourceID] = sourceAliases
    end
    if sourceAliases[aliasID] == true then
        return false
    end
    sourceAliases[aliasID] = true
    return true
end

local function normalizeAlertTypeValue(value)
    if type(value) == "number" then
        local normalized = math.floor(value + 0.5)
        if ALERT_NAME_BY_VALUE[normalized] then
            return normalized
        end
        return nil
    end
    if type(value) == "string" then
        return ALERT_VALUE_BY_NAME[value]
    end
    return nil
end

local function getTrackedCategories()
    local enum = Enum and Enum.CooldownViewerCategory
    if type(enum) ~= "table" then
        return {}
    end

    local categories = {}
    local seen = {}
    local function push(value)
        if type(value) == "number" and not seen[value] then
            seen[value] = true
            categories[#categories + 1] = value
        end
    end

    push(enum.Essential)
    push(enum.Utility)
    push(enum.TrackedBuff)
    push(enum.TrackedBar)

    return categories
end

local function collectInfoSpellIDs(info)
    local spellIDs = {}
    local seen = {}

    addUniqueSpellID(spellIDs, seen, safeTableField(info, "spellID"))
    addUniqueSpellID(spellIDs, seen, safeTableField(info, "overrideSpellID"))
    addUniqueSpellID(spellIDs, seen, safeTableField(info, "overrideTooltipSpellID"))

    local linkedSpellIDs = safeTableField(info, "linkedSpellIDs")
    if type(linkedSpellIDs) == "table" then
        for index = 1, #linkedSpellIDs do
            addUniqueSpellID(spellIDs, seen, linkedSpellIDs[index])
        end
    end

    return spellIDs
end

local function tryLoadBlizzardCooldownViewer()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
        return
    end
    if UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_CooldownViewer")
    end
end

local function getCDMAvailability()
    if not hasCDMApi() then
        return false, "api_missing"
    end

    if not (C_CooldownViewer and type(C_CooldownViewer.IsCooldownViewerAvailable) == "function") then
        return true, nil
    end

    local ok, available, failureReason = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    if not ok then
        return false, "availability_call_failed"
    end
    if available == true then
        return true, nil
    end
    if type(failureReason) == "string" and failureReason ~= "" then
        return false, failureReason
    end
    return false, "unavailable"
end

hasCDMApi = function()
    if type(C_CooldownViewer) ~= "table" then
        return false
    end
    return type(C_CooldownViewer.GetCooldownViewerCategorySet) == "function"
        and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function"
end

local CooldownProvider = {}
CooldownProvider.__index = CooldownProvider

function CooldownProvider:new(config)
    local instance = {
        mode = PROVIDER_MODE_CDM_HYBRID,
        dirty = true,
        loaded = false,
        lastRebuild = 0,
        revision = 0,
        totalCooldownIDs = 0,
        totalSpellLinks = 0,
        trackedSpellIDs = {},
        aliasGraph = {},
        cooldownMap = {},
        spellAlertTypeMap = {},
        spellSelfAuraMap = {},
        spellFlagsMap = {},
        cdmAvailable = false,
        cdmFailureReason = "unknown",
        hasAvailabilityCheck = false,
        hasValidAlertTypesApi = false,
        supportsAllowUnlearnedArg = true,
        logger = config and config.logger or nil,
    }

    if config and config.mode == PROVIDER_MODE_NATIVE then
        instance.mode = PROVIDER_MODE_NATIVE
    end

    return setmetatable(instance, CooldownProvider)
end

function CooldownProvider:log(message)
    if type(self.logger) == "function" then
        self.logger("PROVIDER: " .. tostring(message))
    end
end

function CooldownProvider:GetMode()
    return self.mode
end

function CooldownProvider:SetMode(mode)
    if mode ~= PROVIDER_MODE_NATIVE and mode ~= PROVIDER_MODE_CDM_HYBRID then
        return
    end
    if self.mode ~= mode then
        self.mode = mode
        self:Invalidate()
    end
end

function CooldownProvider:Invalidate()
    self.dirty = true
end

function CooldownProvider:HandleEvent(event, arg1, arg2)
    if not PROVIDER_EVENTS[event] then
        return
    end

    if event ~= "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        self:Invalidate()
        return
    end

    local baseSpellID = normalizeSpellID(arg1)
    local overrideSpellID = normalizeSpellID(arg2)
    if not baseSpellID then
        self:Invalidate()
        return
    end

    if not overrideSpellID then
        -- Override removal can remove previously valid links; rebuild for correctness.
        self:Invalidate()
        return
    end

    local addedForward = addAliasEdge(self.aliasGraph, baseSpellID, overrideSpellID)
    local addedReverse = addAliasEdge(self.aliasGraph, overrideSpellID, baseSpellID)
    if addedForward or addedReverse then
        self.trackedSpellIDs[baseSpellID] = true
        self.trackedSpellIDs[overrideSpellID] = true
        self.totalSpellLinks = (self.totalSpellLinks or 0) + ((addedForward and 1 or 0) + (addedReverse and 1 or 0))
        self.revision = (self.revision or 0) + 1
        return
    end

    -- If nothing changed, avoid forcing a full rebuild.
end

function CooldownProvider:Initialize()
    if self.loaded then
        return
    end
    self.loaded = true
    self:Invalidate()
end

function CooldownProvider:IsCDMEnabled()
    return self.mode == PROVIDER_MODE_CDM_HYBRID
end

function CooldownProvider:Rebuild(force)
    if not self:IsCDMEnabled() then
        return false
    end

    if not force and not self.dirty then
        return false
    end

    local now = getNow()
    if not force and self.lastRebuild > 0 and (now - self.lastRebuild) < REBUILD_THROTTLE_SECONDS then
        return false
    end

    if not hasCDMApi() then
        tryLoadBlizzardCooldownViewer()
    end

    self.hasAvailabilityCheck = (C_CooldownViewer and type(C_CooldownViewer.IsCooldownViewerAvailable) == "function") and true or false
    self.hasValidAlertTypesApi = (C_CooldownViewer and type(C_CooldownViewer.GetValidAlertTypes) == "function") and true or false
    self.supportsAllowUnlearnedArg = true

    local available, failureReason = getCDMAvailability()
    self.cdmAvailable = available and true or false
    self.cdmFailureReason = failureReason
    if not available then
        self.lastRebuild = now
        return false
    end

    local aliasGraph = {}
    local cooldownMap = {}
    local trackedSpellIDs = {}
    local spellAlertTypeMap = {}
    local spellSelfAuraMap = {}
    local spellFlagsMap = {}
    local totalCooldownIDs = 0
    local totalSpellLinks = 0

    local categories = getTrackedCategories()
    for index = 1, #categories do
        local category = categories[index]
        local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if not okSet then
            self.supportsAllowUnlearnedArg = false
            okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category)
        end
        if okSet and type(cooldownIDs) == "table" then
            for cooldownIndex = 1, #cooldownIDs do
                local cooldownID = cooldownIDs[cooldownIndex]
                local normalizedCooldownID = normalizeSpellID(cooldownID)
                if normalizedCooldownID then
                    local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, normalizedCooldownID)
                    if okInfo and type(info) == "table" then
                        local linkedSpellIDs = collectInfoSpellIDs(info)
                        if #linkedSpellIDs > 0 then
                            totalCooldownIDs = totalCooldownIDs + 1
                            cooldownMap[normalizedCooldownID] = linkedSpellIDs

                            local validAlerts = nil
                            if self.hasValidAlertTypesApi then
                                local okAlerts, alertTypes = pcall(C_CooldownViewer.GetValidAlertTypes, normalizedCooldownID)
                                if okAlerts and type(alertTypes) == "table" and #alertTypes > 0 then
                                    validAlerts = {}
                                    for alertIndex = 1, #alertTypes do
                                        local normalizedAlertType = normalizeAlertTypeValue(alertTypes[alertIndex])
                                        if normalizedAlertType then
                                            validAlerts[normalizedAlertType] = true
                                        end
                                    end
                                end
                            end

                            local selfAura = safeTableField(info, "selfAura") == true
                            local spellFlags = normalizeSpellID(safeTableField(info, "flags")) or 0
                            for spellIdx = 1, #linkedSpellIDs do
                                local spellID = linkedSpellIDs[spellIdx]
                                trackedSpellIDs[spellID] = true
                                if selfAura then
                                    spellSelfAuraMap[spellID] = true
                                end
                                if spellFlags and spellFlags > 0 then
                                    local previousFlags = spellFlagsMap[spellID] or 0
                                    if bitBor and type(previousFlags) == "number" then
                                        spellFlagsMap[spellID] = bitBor(previousFlags, spellFlags)
                                    elseif previousFlags == 0 then
                                        spellFlagsMap[spellID] = spellFlags
                                    else
                                        spellFlagsMap[spellID] = previousFlags
                                    end
                                end
                                if validAlerts then
                                    local spellAlerts = spellAlertTypeMap[spellID]
                                    if type(spellAlerts) ~= "table" then
                                        spellAlerts = {}
                                        spellAlertTypeMap[spellID] = spellAlerts
                                    end
                                    for alertType in pairs(validAlerts) do
                                        spellAlerts[alertType] = true
                                    end
                                end
                                for aliasIdx = 1, #linkedSpellIDs do
                                    local aliasID = linkedSpellIDs[aliasIdx]
                                    if addAliasEdge(aliasGraph, spellID, aliasID) then
                                        totalSpellLinks = totalSpellLinks + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    self.aliasGraph = aliasGraph
    self.cooldownMap = cooldownMap
    self.trackedSpellIDs = trackedSpellIDs
    self.spellAlertTypeMap = spellAlertTypeMap
    self.spellSelfAuraMap = spellSelfAuraMap
    self.spellFlagsMap = spellFlagsMap
    self.totalCooldownIDs = totalCooldownIDs
    self.totalSpellLinks = totalSpellLinks
    self.lastRebuild = now
    self.dirty = false
    self.revision = self.revision + 1

    return true
end

function CooldownProvider:GetSpellMetadata(spellID)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID then
        return nil
    end

    self:Rebuild(false)

    local flags = self.spellFlagsMap and self.spellFlagsMap[normalizedSpellID] or 0
    local hideAura = false
    local hideByDefault = false
    if bitBand and type(flags) == "number" then
        hideAura = bitBand(flags, SPELL_FLAG_HIDE_AURA) ~= 0
        hideByDefault = bitBand(flags, SPELL_FLAG_HIDE_BY_DEFAULT) ~= 0
    end

    local alerts = self.spellAlertTypeMap and self.spellAlertTypeMap[normalizedSpellID] or nil
    return {
        spellID = normalizedSpellID,
        trackedByCDM = self.trackedSpellIDs and self.trackedSpellIDs[normalizedSpellID] == true or false,
        selfAura = self.spellSelfAuraMap and self.spellSelfAuraMap[normalizedSpellID] == true or false,
        hideAura = hideAura,
        hideByDefault = hideByDefault,
        alertTypes = alerts,
    }
end

function CooldownProvider:SpellSupportsAlertType(spellID, alertType)
    local metadata = self:GetSpellMetadata(spellID)
    if type(metadata) ~= "table" then
        return false
    end
    local alertTypeValue = normalizeAlertTypeValue(alertType)
    if not alertTypeValue then
        return false
    end
    local alerts = metadata.alertTypes
    return type(alerts) == "table" and alerts[alertTypeValue] == true or false
end

function CooldownProvider:GetCandidateSpellIDs(spellID, fallbackCandidates)
    local normalizedSpellID = normalizeSpellID(spellID)
    if not normalizedSpellID then
        return {}
    end

    local candidates = {}
    local seen = {}

    local function addList(list)
        if type(list) ~= "table" then
            return
        end
        for index = 1, #list do
            addUniqueSpellID(candidates, seen, list[index])
        end
    end

    addUniqueSpellID(candidates, seen, normalizedSpellID)
    addList(fallbackCandidates)

    if not self:IsCDMEnabled() then
        return candidates
    end

    self:Rebuild(false)

    local queue = {}
    local visited = {}
    for index = 1, #candidates do
        queue[#queue + 1] = candidates[index]
    end

    local head = 1
    while head <= #queue and head <= 64 do
        local current = queue[head]
        head = head + 1
        if not visited[current] then
            visited[current] = true
            local aliases = self.aliasGraph[current]
            if type(aliases) == "table" then
                for aliasID in pairs(aliases) do
                    if addUniqueSpellID(candidates, seen, aliasID) then
                        queue[#queue + 1] = aliasID
                    end
                end
            end
        end
    end

    return candidates
end

function CooldownProvider:GetStatus()
    local trackedSpellCount = 0
    if type(self.trackedSpellIDs) == "table" then
        for _ in pairs(self.trackedSpellIDs) do
            trackedSpellCount = trackedSpellCount + 1
        end
    end

    return {
        mode = self.mode,
        dirty = self.dirty and true or false,
        revision = self.revision,
        lastRebuild = self.lastRebuild,
        cooldownCount = self.totalCooldownIDs or 0,
        aliasLinks = self.totalSpellLinks or 0,
        trackedSpellCount = trackedSpellCount,
        cdmAvailable = self.cdmAvailable == true,
        cdmFailureReason = self.cdmFailureReason,
        hasAvailabilityCheck = self.hasAvailabilityCheck == true,
        hasValidAlertTypesApi = self.hasValidAlertTypesApi == true,
        supportsAllowUnlearnedArg = self.supportsAllowUnlearnedArg == true,
    }
end

ns.CooldownProviderFactory = ns.CooldownProviderFactory or {}
ns.CooldownProviderFactory.Create = function(config)
    return CooldownProvider:new(config)
end

