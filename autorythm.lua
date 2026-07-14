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
--    • RhythmServiceClient is a SINGLETON — its ModuleScript ends with
--      `return u12:Get()`, so require() hands us the singleton directly (cached,
--      no side effects). The singleton's ._session field is the LIVE play session
--      (== the engine: _active / _now / _handleLanePress), or nil when no song is
--      running. We cache the singleton once and just read ._session per frame.
--      NO getgc heap sweep (that was the freeze); a filtergc(filterOne) grab is
--      only used as a one-time fallback if the module path was stripped after boot.
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

    -- ── Engine acquisition — filtergc for the client singleton ───────────────
    -- IMPORTANT: we canNOT require the module. RhythmServiceClient lives under
    -- ReplicatedStorage.Shared.Services, and that folder is DESTROYED right after
    -- bootstrap (the module itself errors "require during bootstrap before
    -- Shared.Services is destroyed" — see RhythmServiceClient:99-103). So the
    -- Instance path is dead at runtime and require() can't reach it.
    --
    -- But the RhythmServiceClient SINGLETON object still lives in memory forever
    -- (held by UserInputService connections + janitors). We grab it once with
    -- filtergc(filterOne) — cheap, stops at the first match, no full-heap copy
    -- like the old getgc(true) that froze — then cache it FOREVER. Its ._session
    -- field is the live play session (the engine); it's recreated per song, so we
    -- read it fresh each frame. Signature keys are non-nil direct fields:
    -- _startPlaySeq (=0), _characterJanitor, _janitor (RhythmServiceClient:117-129).
    -- NB: _session is nil at construction, so it is NOT a usable match key.
    local rawgetFn = rawget

    local function looksLikeClient(o)
        if type(o) ~= "table" then return false end
        local ok, yes = pcall(function()
            return rawgetFn(o, "_characterJanitor") ~= nil
               and rawgetFn(o, "_janitor") ~= nil
               and rawgetFn(o, "_startPlaySeq") ~= nil
        end)
        return ok and yes
    end

    local _client            -- cached singleton (forever, once found)
    local _lastScan = 0
    local SCAN_GAP = 1.0     -- min seconds between scans while still searching
    local function getClient()
        if _client then return _client end
        if type(filtergc) ~= "function" then return nil end
        -- Throttle scans until found. The singleton exists from client startup, so
        -- this normally succeeds on the very first scan and then never runs again.
        local nowClock = os.clock()
        if nowClock - _lastScan < SCAN_GAP then return nil end
        _lastScan = nowClock
        local ok, res = pcall(filtergc, "table",
            { Keys = { "_startPlaySeq", "_characterJanitor", "_janitor" } }, true)
        if ok and looksLikeClient(res) then _client = res end
        return _client
    end

    -- Read the live engine (play session) off the singleton; nil when no song.
    local function getEngine()
        local client = getClient()
        if not client then return nil end
        local e = client._session
        if type(e) ~= "table" then return nil end
        if type(e._active) ~= "table" or type(e._now) ~= "function"
           or type(e._handleLanePress) ~= "function" then
            return nil
        end
        return e
    end

    -- ── The autoplay step (one pass over the on-screen notes) ────────────────
    local _laneHolding, _pressHold, _pressTap = {}, {}, {}   -- reused scratch tables
    local function step()
        if not Config.AutoRythm_On then return end
        local engine = getEngine()
        if not engine then return end

        local okNow, now = pcall(engine._now, engine)
        if not okNow or type(now) ~= "number" then return end

        local active = engine._active
        if type(active) ~= "table" then return end
        local lanes  = engine._lanes or 0
        local offset = (Config.Offset or 0) / 1000

        -- Reused scratch tables (cleared each frame → no per-frame allocation).
        table.clear(_laneHolding); table.clear(_pressHold); table.clear(_pressTap)

        -- First figure out which lanes currently have a hold in progress — we must
        -- never tap-release those (it would EARLY_RELEASE and wreck the hold).
        for _, note in ipairs(active) do
            if note.holding then _laneHolding[note.lane] = true end
        end

        -- Decide presses this frame. A note is due when now >= its hit time.
        --
        -- CRITICAL for holds: the engine only starts a hold (holding = true) if the
        -- press lands at/after the note time. If you press even slightly EARLY it
        -- takes the "future note" branch (_onPressLane:1154) — the tap is credited
        -- but holding never turns on, so the sustain scores nothing. Taps don't care
        -- about early vs late (any press inside the window counts), so ONLY holds
        -- must be protected: we clamp their offset so a negative (press-earlier)
        -- Offset can never drag a hold press before note.t.
        local holdOffset = (offset > 0) and offset or 0
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes then
                if not note.hit and not note.attempted then
                    if (note.len or 0) > 0 then
                        if not note.holding and now >= note.t + holdOffset then
                            _pressHold[lane] = true
                        end
                    elseif now >= note.t + offset then
                        _pressTap[lane] = true
                    end
                end
            end
        end

        -- Holds: press ONCE and DO NOT release. The engine auto-finalizes the held
        -- note at t+len with fraction ≈ 1.0 → PERFECT (RhythmEngine._step:1582). A
        -- manual early release would score EARLY_RELEASE and tank the grade.
        -- (pcall(fn, engine, lane) forwards args → no per-frame closure allocation.)
        for lane in pairs(_pressHold) do
            pcall(engine._handleLanePress, engine, lane)
        end
        -- Taps: quick press + release. Skip lanes that are mid-hold or just pressed.
        for lane in pairs(_pressTap) do
            if not _pressHold[lane] and not _laneHolding[lane] then
                pcall(engine._handleLanePress, engine, lane)
                pcall(engine._handleLaneRelease, engine, lane)
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
