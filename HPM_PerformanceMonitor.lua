local ns = HealingPriorityMouseNS or {}
HealingPriorityMouseNS = ns

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

local function findAddonIndex(addonName)
    if type(addonName) ~= "string" or addonName == "" or not GetNumAddOns then
        return nil
    end

    local count = GetNumAddOns()
    for index = 1, count do
        local name = GetAddOnInfo(index)
        if name == addonName then
            return index
        end
    end
    return nil
end

local function safeGetMemoryKB(addonIndex)
    if not addonIndex or not GetAddOnMemoryUsage then
        return nil
    end
    if UpdateAddOnMemoryUsage then
        pcall(UpdateAddOnMemoryUsage)
    end
    local ok, value = pcall(GetAddOnMemoryUsage, addonIndex)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function safeGetCPUms(addonIndex)
    if not addonIndex or not GetAddOnCPUUsage then
        return nil
    end
    if UpdateAddOnCPUUsage then
        pcall(UpdateAddOnCPUUsage)
    end
    local ok, value = pcall(GetAddOnCPUUsage, addonIndex)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function isScriptProfilingEnabled()
    if not GetCVar then
        return false
    end
    local ok, value = pcall(GetCVar, "scriptProfile")
    if not ok then
        return false
    end
    return value == "1"
end

local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor

function PerformanceMonitor:new(config)
    local instance = {
        addonName = config and config.addonName or "",
        addonIndex = nil,
        enabled = false,
        interval = config and config.interval or 1.0,
        elapsed = 0,
        frame = CreateFrame("Frame"),
        onSample = config and config.onSample or nil,
        lastMetrics = nil,
    }

    instance.frame:Hide()
    setmetatable(instance, PerformanceMonitor)
    instance:bindFrame()
    return instance
end

function PerformanceMonitor:bindFrame()
    self.frame:SetScript("OnUpdate", function(_, elapsed)
        if not self.enabled then
            return
        end
        self.elapsed = self.elapsed + (elapsed or 0)
        if self.elapsed >= self.interval then
            self.elapsed = 0
            self:SampleNow()
        end
    end)
end

function PerformanceMonitor:RefreshAddonIndex()
    self.addonIndex = findAddonIndex(self.addonName)
end

function PerformanceMonitor:GetSnapshot()
    if not self.addonIndex then
        self:RefreshAddonIndex()
    end

    local memoryKB = safeGetMemoryKB(self.addonIndex)
    local cpuMs = safeGetCPUms(self.addonIndex)
    local metrics = {
        time = getNow(),
        addonName = self.addonName,
        addonIndex = self.addonIndex,
        memoryKB = memoryKB,
        cpuMs = cpuMs,
        scriptProfileEnabled = isScriptProfilingEnabled(),
    }
    self.lastMetrics = metrics
    return metrics
end

function PerformanceMonitor:SampleNow()
    local metrics = self:GetSnapshot()
    if type(self.onSample) == "function" then
        self.onSample(metrics)
    end
    return metrics
end

function PerformanceMonitor:SetEnabled(enabled)
    self.enabled = enabled and true or false
    self.elapsed = 0
    if self.enabled then
        self.frame:Show()
        self:SampleNow()
    else
        self.frame:Hide()
    end
end

function PerformanceMonitor:IsEnabled()
    return self.enabled and true or false
end

function PerformanceMonitor:GetLastMetrics()
    return self.lastMetrics
end

local function formatMetricLine(metrics)
    if type(metrics) ~= "table" then
        return "CPU: n/a | Memory: n/a"
    end

    local memoryText = "n/a"
    if type(metrics.memoryKB) == "number" then
        memoryText = string.format("%.1f MB", metrics.memoryKB / 1024)
    end

    local cpuText = "n/a"
    if type(metrics.cpuMs) == "number" then
        cpuText = string.format("%.1f ms", metrics.cpuMs)
    elseif metrics.scriptProfileEnabled == false then
        cpuText = "n/a (scriptProfile=0)"
    end

    return "CPU: " .. cpuText .. " | Memory: " .. memoryText
end

ns.PerformanceMonitorFactory = ns.PerformanceMonitorFactory or {}
ns.PerformanceMonitorFactory.Create = function(config)
    return PerformanceMonitor:new(config or {})
end
ns.PerformanceMonitorFormatLine = formatMetricLine

