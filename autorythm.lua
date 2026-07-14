-- ═══════════════════════════════════════════════════════════════════════════
--  AutoRythm — standalone module for the Syllinse loader (AutoParry game,
--  UniverseId 9199655655). Auto-plays the in-game RHYTHM MINIGAME
--  (ReplicatedStorage.Shared.Services.RhythmService) with frame-perfect timing.
--
--  Loader contract (same as movement/visuals):
--    • file body returns function(Lib, Core) → returns a handle with
--      optional start() and buildUI(ctx).
--    • ctx gives: tabs (keyed by Tab.Key), flag(name), keybind(section,opts),
--      notify(title,desc). Everything is built into ctx.tabs.Misc.
--
--  HOW IT WORKS — everything below is derived from the game's OWN decompiled
--  RhythmEngine (verified against the dump, no guessing):
--
--    • The minigame runs an OO engine instance (RhythmEngine, `u21.new`). We grab
--      the LIVE instance from the GC (getgc) by its field signature (_liveNotes,
--      _active, _windows, _lanes, _judgeCounts + methods _now/_handleLanePress).
--      The instance is re-created per song, so we cache it and re-scan only when
--      the cached one is gone/destroyed — never every frame.
--
--    • Notes on screen live in engine._active. Each has: t (target hit time, in
--      the engine's own audio-clock seconds), lane, len (0 = tap, >0 = hold),
--      hit / attempted / holding flags.
--
--    • Scoring (RhythmEngine._onPressLane / _judge): judgment = |note.t - now|*1000
--      vs windows. PERFECT window is 43ms (RhythmConfig.DEFAULT_WINDOWS_MS). We
--      press the moment now >= note.t, so the error is at most ONE frame (~16ms at
--      60fps, far under 43ms) → PERFECT every time, using the engine's EXACT clock.
--
--    • TAPS  (len <= 0): call engine:_handleLanePress(lane) then _handleLaneRelease
--      — a clean tap that the engine judges PERFECT and scores immediately.
--
--    • HOLDS (len > 0): call engine:_handleLanePress(lane) ONCE at t and DO NOT
--      release. RhythmEngine._step auto-finalizes a still-held note at t+len with
--      fraction = (now - holdStartTime)/len ≈ 1.0 → PERFECT hold. Releasing early
--      would trigger EARLY_RELEASE and LOWER the score, so we deliberately hold.
--
--  We drive the engine's OWN methods (not synthetic key input), so the client
--  computes and reports a legit perfect run exactly as if a human nailed it.
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")

    local LocalPlayer = Players.LocalPlayer

    -- ── Runtime config (MacLib restores flags through the config manager) ────
    local Config = {
        AutoRythm_On = false,
        -- Timing nudge (ms). 0 = frame-perfect PERFECT. Negative = press earlier,
        -- positive = later. Only change if your client has audio/display latency;
        -- taps stay PERFECT within ±43ms, holds stay PERFECT at any small offset.
        Offset = 0,
    }

    -- ── Executor GC access (for grabbing the live engine instance) ───────────
    -- We only rely on getgc (getreg is NOT an equivalent). getgcFn stays nil on
    -- executors without it, and the module simply no-ops there.
    local getgcFn  = getgc
    local rawgetFn = rawget

    -- Field signature that uniquely identifies a RhythmEngine instance.
    local function looksLikeEngine(o)
        local ok, yes = pcall(function()
            return rawgetFn(o, "_liveNotes") ~= nil
               and rawgetFn(o, "_active") ~= nil
               and rawgetFn(o, "_windows") ~= nil
               and rawgetFn(o, "_lanes") ~= nil
               and rawgetFn(o, "_judgeCounts") ~= nil
        end)
        if not (ok and yes) then return false end
        if rawgetFn(o, "_destroyed") == true then return false end
        local mok, hasM = pcall(function()
            return type(o._handleLanePress) == "function"
               and type(o._handleLaneRelease) == "function"
               and type(o._now) == "function"
        end)
        return mok and hasM
    end

    -- Scan the GC once for a live engine instance. Only called on a throttle when
    -- we don't already hold a valid reference (see acquireEngine).
    local function scanForEngine()
        if type(getgcFn) ~= "function" then return nil end
        local ok, gc = pcall(getgcFn, true)
        if not ok or type(gc) ~= "table" then
            ok, gc = pcall(getgcFn)
            if not ok or type(gc) ~= "table" then return nil end
        end
        for i = 1, #gc do
            local o = gc[i]
            if type(o) == "table" and looksLikeEngine(o) then
                return o
            end
        end
        return nil
    end

    -- Cached engine + validity check. Re-scans at most every RESCAN_INTERVAL while
    -- no valid engine is held; once held, we skip scanning entirely (cheap).
    local RESCAN_INTERVAL = 0.5
    local _engine, _lastScan = nil, 0
    local function engineValid(e)
        if type(e) ~= "table" then return false end
        local ok, alive = pcall(function()
            return e._destroyed ~= true and type(e._active) == "table"
        end)
        return ok and alive
    end
    local function acquireEngine()
        if engineValid(_engine) then return _engine end
        _engine = nil
        local nowClock = os.clock()
        if nowClock - _lastScan < RESCAN_INTERVAL then return nil end
        _lastScan = nowClock
        local e = scanForEngine()
        if e then _engine = e end
        return _engine
    end

    -- ── The autoplay step (one pass over the on-screen notes) ────────────────
    local function step()
        if not Config.AutoRythm_On then return end
        local engine = acquireEngine()
        if not engine then return end

        local okNow, now = pcall(function() return engine:_now() end)
        if not okNow or type(now) ~= "number" then return end

        local active = engine._active
        if type(active) ~= "table" then return end
        local lanes  = engine._lanes or 0
        local offset = (Config.Offset or 0) / 1000

        -- First figure out which lanes currently have a hold in progress — we must
        -- never tap-release those (it would EARLY_RELEASE and wreck the hold).
        local laneHolding = {}
        for _, note in ipairs(active) do
            if note.holding then laneHolding[note.lane] = true end
        end

        -- Decide presses this frame.
        local pressHold, pressTap = {}, {}
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes then
                local len = note.len or 0
                if not note.hit and not note.attempted and now >= note.t + offset then
                    if len > 0 then
                        if not note.holding then pressHold[lane] = true end
                    else
                        pressTap[lane] = true
                    end
                end
            end
        end

        -- Holds: press once, DO NOT release (engine auto-finalizes at t+len = PERFECT).
        for lane in pairs(pressHold) do
            pcall(function() engine:_handleLanePress(lane) end)
        end
        -- Taps: quick press + release. Skip lanes that just started / are holding.
        for lane in pairs(pressTap) do
            if not pressHold[lane] and not laneHolding[lane] then
                pcall(function()
                    engine:_handleLanePress(lane)
                    engine:_handleLaneRelease(lane)
                end)
            end
        end
    end

    -- ═══════════════════════════════ MODULE ═════════════════════════════════
    local M = {}
    local _conn

    function M.start()
        Config.AutoRythm_On = false
        -- Drive on RenderStepped (the same signal the engine steps on). Timing is
        -- taken from the engine's own audio clock, so signal order is irrelevant.
        if not _conn then
            _conn = RunService.RenderStepped:Connect(function()
                if Config.AutoRythm_On then
                    -- swallow errors: a transient nil during song teardown must never spam
                    pcall(step)
                end
            end)
        end
        -- Clean up on loader unload.
        pcall(function()
            if Core and Core.On then
                Core:On("unload", function()
                    Config.AutoRythm_On = false
                    if _conn then _conn:Disconnect(); _conn = nil end
                end)
            end
        end)
    end

    function M.buildUI(ctx)
        local uiReady = false
        local function notify(title, body)
            if uiReady then pcall(ctx.notify, title, body) end
        end

        -- notify-once boolean feature (Header + "Enabled" toggle + Keybind)
        local function feature(section, o)
            local guard, togEl = false, nil
            local function commit(val)
                val = val and true or false
                o.set(val)
                notify(o.Title, val and "Enabled" or "Disabled")
                guard = true
                if togEl then pcall(function() togEl:UpdateState(val) end) end
                guard = false
            end
            togEl = section:Toggle({
                Name = "Enabled", Default = o.get(),
                Callback = function(v) if guard then return end commit(v) end,
            }, ctx.flag(o.Flag))
            if o.Desc then section:SubLabel({ Text = o.Desc }) end
            ctx.keybind(section, {
                Name = "Keybind",
                Flag = ctx.flag(o.Flag .. "_KB"),
                Toggle = function() commit(not o.get()) end,
            })
            return { commit = commit }
        end

        local function slider(section, o)
            section:Slider({
                Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
                Precision = o.Precision or 0, Suffix = o.Suffix, Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        local Misc = ctx.tabs.Misc

        -- ─────────────── Section: AutoRythm (Left) ───────────────
        local sAR = Misc:Section({ Side = "Left" })
        sAR:Header({ Name = "AutoRythm" })
        feature(sAR, {
            Title = "AutoRythm", Flag = "Misc_AutoRythm",
            get = function() return Config.AutoRythm_On end,
            set = function(v) Config.AutoRythm_On = v end,
            Desc = "auto-plays the rhythm minigame\nframe-perfect PERFECT on every note (taps + holds)",
        })
        sAR:Divider()
        sAR:Header({ Name = "Timing" })
        slider(sAR, {
            Name = "Offset", Flag = "Misc_AutoRythm_Offset",
            Default = Config.Offset, Min = -60, Max = 60, Precision = 0, Suffix = " ms",
            Callback = function(v) Config.Offset = v end,
        })
        sAR:SubLabel({ Text = "0 = frame-perfect. Only nudge if your client has audio/display lag. Taps stay PERFECT within about +-43ms." })
        sAR:Divider()
        sAR:SubLabel({ Text = "Grabs the live RhythmEngine and plays it directly, so the game sees a clean PERFECT run. Just start a song and enable." })

        uiReady = true
    end

    return M
end
