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

local function hasCDMApi()
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

function CooldownProvider:HandleEvent(event)
    if PROVIDER_EVENTS[event] then
        self:Invalidate()
    end
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

    if not hasCDMApi() then
        self.lastRebuild = now
        return false
    end

    local aliasGraph = {}
    local cooldownMap = {}
    local trackedSpellIDs = {}
    local totalCooldownIDs = 0
    local totalSpellLinks = 0

    local categories = getTrackedCategories()
    for index = 1, #categories do
        local category = categories[index]
        local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
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
                            for spellIdx = 1, #linkedSpellIDs do
                                local spellID = linkedSpellIDs[spellIdx]
                                trackedSpellIDs[spellID] = true
                                aliasGraph[spellID] = aliasGraph[spellID] or {}
                                for aliasIdx = 1, #linkedSpellIDs do
                                    local aliasID = linkedSpellIDs[aliasIdx]
                                    if aliasID ~= spellID then
                                        if not aliasGraph[spellID][aliasID] then
                                            aliasGraph[spellID][aliasID] = true
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
    end

    self.aliasGraph = aliasGraph
    self.cooldownMap = cooldownMap
    self.trackedSpellIDs = trackedSpellIDs
    self.totalCooldownIDs = totalCooldownIDs
    self.totalSpellLinks = totalSpellLinks
    self.lastRebuild = now
    self.dirty = false
    self.revision = self.revision + 1

    return true
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
    return {
        mode = self.mode,
        dirty = self.dirty and true or false,
        revision = self.revision,
        lastRebuild = self.lastRebuild,
        cooldownCount = self.totalCooldownIDs or 0,
        aliasLinks = self.totalSpellLinks or 0,
        trackedSpellCount = self.trackedSpellIDs and (function()
            local count = 0
            for _ in pairs(self.trackedSpellIDs) do
                count = count + 1
            end
            return count
        end)() or 0,
    }
end

ns.CooldownProviderFactory = ns.CooldownProviderFactory or {}
ns.CooldownProviderFactory.Create = function(config)
    return CooldownProvider:new(config)
end

