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
local safeNumber = ns.safeNumber or tonumber

local RefreshQueue = {}
RefreshQueue.__index = RefreshQueue

local function mergePending(pending, options)
    if type(options) ~= "table" then
        return
    end
    for key, value in pairs(options) do
        if type(value) == "boolean" then
            if value then
                pending[key] = true
            end
        else
            pending[key] = value
        end
    end
end

function RefreshQueue:new(config)
    local instance = {
        onDispatch = config and config.onDispatch or nil,
        frame = CreateFrame("Frame"),
        queued = false,
        running = false,
        rerun = false,
        pending = {},
        wakeTimer = nil,
        wakeAt = nil,
        lastDispatch = 0,
    }
    instance.frame:Hide()
    setmetatable(instance, RefreshQueue)
    instance:bindFrame()
    return instance
end

function RefreshQueue:bindFrame()
    self.frame:SetScript("OnUpdate", function(frame)
        if not self.queued then
            frame:Hide()
            return
        end

        self.queued = false

        if self.running then
            self.rerun = true
            return
        end

        self.running = true
        local pending = self.pending
        self.pending = {}

        if type(self.onDispatch) == "function" then
            self.onDispatch(pending)
        end

        self.lastDispatch = getNow()
        self.running = false

        if self.rerun then
            self.rerun = false
            self.queued = true
        end

        if not self.queued then
            frame:Hide()
        end
    end)
end

function RefreshQueue:Request(options)
    mergePending(self.pending, options)

    if self.running then
        self.rerun = true
        return
    end

    if self.queued then
        return
    end

    self.queued = true
    self.frame:Show()
end

function RefreshQueue:CancelWake()
    if self.wakeTimer and type(self.wakeTimer.Cancel) == "function" then
        self.wakeTimer:Cancel()
    end
    self.wakeTimer = nil
    self.wakeAt = nil
end

function RefreshQueue:RequestAt(timestamp, options)
    local wakeTimestamp = safeNumber(timestamp)
    if type(wakeTimestamp) ~= "number" then
        return
    end

    local now = getNow()
    if wakeTimestamp <= (now + 0.01) then
        self:Request(options)
        return
    end

    if self.wakeAt and math.abs(self.wakeAt - wakeTimestamp) <= 0.03 then
        return
    end

    self:CancelWake()
    self.wakeAt = wakeTimestamp

    if C_Timer and C_Timer.NewTimer then
        local delay = math.max(0.01, wakeTimestamp - now)
        self.wakeTimer = C_Timer.NewTimer(delay, function()
            self.wakeTimer = nil
            self.wakeAt = nil
            self:Request(options)
        end)
    end
end

function RefreshQueue:GetState()
    return {
        queued = self.queued and true or false,
        running = self.running and true or false,
        rerun = self.rerun and true or false,
        wakeAt = self.wakeAt,
        lastDispatch = self.lastDispatch,
    }
end

ns.RefreshQueueFactory = ns.RefreshQueueFactory or {}
ns.RefreshQueueFactory.Create = function(config)
    return RefreshQueue:new(config or {})
end

