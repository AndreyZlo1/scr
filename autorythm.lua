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
        -- Diagnostic logging. When on, prints [AutoRythm] traces to the executor
        -- console so we can see exactly where the chain breaks.
        Debug = false,
    }

    -- ── Debug logging ────────────────────────────────────────────────────────
    local function dbg(...)
        if Config.Debug then print("[AutoRythm]", ...) end
    end
    -- Throttled logger: same key logs at most once per `gap` seconds (avoids
    -- flooding the console from the per-frame step loop).
    local _dbgStamps = {}
    local function dbgT(key, gap, ...)
        if not Config.Debug then return end
        local t = os.clock()
        if (t - (_dbgStamps[key] or 0)) < (gap or 1) then return end
        _dbgStamps[key] = t
        print("[AutoRythm]", ...)
    end
    -- List the string keys of a table (for discovering the real field names).
    local function dumpKeys(o)
        if type(o) ~= "table" then return "<not a table: " .. type(o) .. ">" end
        local names, n = {}, 0
        local ok = pcall(function()
            for k in pairs(o) do
                if type(k) == "string" then n = n + 1; names[n] = k end
            end
        end)
        if not ok then return "<pairs() blocked by metatable>" end
        table.sort(names)
        return "{ " .. table.concat(names, ", ") .. " }"
    end

    -- ── Engine acquisition — client._session (freeze-free) + gated getgc ─────
    -- The RhythmServiceClient singleton DOES hold the live session in ._session:
    -- set when a song starts (RhythmServiceClient:767) and cleared to nil when it
    -- ends (:398/:501). It's just absent in the constructor, which is why an idle
    -- dump shows no _session key. So the freeze-free primary path is:
    --   1) find the client ONCE via filtergc (cheap, cached forever),
    --   2) read client._session every frame — zero scanning while playing.
    -- Only if that fails do we fall back to a direct getgc scan for the engine,
    -- and even then ONLY while the client says a song is active (_session set,
    -- _ampRelayActive, or inside the start gate) so we never freeze at idle.
    local rawgetFn = rawget

    -- Client singleton signature (real keys, RhythmServiceClient:117-129).
    local CLIENT_KEYS = { "_startPlaySeq", "_characterJanitor", "_janitor" }
    local function looksLikeClient(o)
        if type(o) ~= "table" then return false end
        local ok, yes = pcall(function()
            return rawgetFn(o, "_characterJanitor") ~= nil
               and rawgetFn(o, "_janitor") ~= nil
               and rawgetFn(o, "_startPlaySeq") ~= nil
        end)
        return ok and yes
    end

    -- Engine (RhythmPlaySession) signature (real instance keys, RhythmEngine:100-160).
    local function looksLikeEngine(o)
        if type(o) ~= "table" then return false end
        local ok, yes = pcall(function()
            return rawgetFn(o, "_liveNotes") ~= nil
               and type(rawgetFn(o, "_active")) == "table"
               and rawgetFn(o, "_windows") ~= nil
               and rawgetFn(o, "_lanes") ~= nil
               and rawgetFn(o, "_judgeCounts") ~= nil
               and rawgetFn(o, "_destroyed") ~= true
        end)
        if not (ok and yes) then return false end
        local mok, hasM = pcall(function()
            return type(o._now) == "function"
               and type(o._handleLanePress) == "function"
               and type(o._handleLaneRelease) == "function"
        end)
        return mok and hasM
    end

    local function engineAlive(e)
        if type(e) ~= "table" then return false end
        local ok, alive = pcall(function()
            return e._destroyed ~= true and type(e._active) == "table"
        end)
        return ok and alive
    end

    -- Find the client singleton once, cache forever.
    local _client, _lastClientScan = nil, 0
    local function getClient()
        if _client then return _client end
        if type(filtergc) ~= "function" then return nil end
        local t = os.clock()
        if t - _lastClientScan < 1.0 then return nil end
        _lastClientScan = t
        local ok, res = pcall(filtergc, "table", { Keys = CLIENT_KEYS }, true)
        if ok and looksLikeClient(res) then
            _client = res
            dbg("CLIENT FOUND. keys=", dumpKeys(res))
            return _client
        end
        -- list form fallback
        local ok2, list = pcall(filtergc, "table", { Keys = CLIENT_KEYS }, false)
        if ok2 and type(list) == "table" then
            for i = 1, #list do
                if looksLikeClient(list[i]) then
                    _client = list[i]; dbg("CLIENT FOUND (list). keys=", dumpKeys(_client)); return _client
                end
            end
        end
        dbgT("no_client", 2, "client not found yet (filtergc). Retrying...")
        return nil
    end

    -- Cheap "is the rhythm minigame open right now?" gate. The client fields turned
    -- out unreliable on this build (the found singleton never showed _session), so
    -- we detect the minigame's ScreenGui instead: it's named "RhythmServiceUI" and
    -- lives in PlayerGui while a song is open (RhythmServiceClient:73). This is a
    -- single FindFirstChild — no GC work — so we gate the getgc fallback on it and
    -- never scan while idle.
    local CoreGui = game:GetService("CoreGui")
    local function minigameOpen()
        local ok, found = pcall(function()
            local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg and pg:FindFirstChild("RhythmServiceUI") then return true end
            -- executors sometimes reparent protected UI under gethui()
            if type(gethui) == "function" then
                local hui = gethui()
                if hui and hui:FindFirstChild("RhythmServiceUI") then return true end
            end
            for _, g in ipairs(CoreGui:GetChildren()) do
                if g.Name == "RhythmServiceUI" then return true end
            end
            return false
        end)
        return ok and found == true
    end

    local _engine, _lastScan = nil, 0
    local SCAN_GAP = 0.5
    local function getEngine()
        if engineAlive(_engine) then return _engine end
        _engine = nil

        local client = getClient()

        -- Primary path: read the session straight off the client — no GC scan.
        if client then
            local ok, sess = pcall(function() return client._session end)
            if ok and looksLikeEngine(sess) then
                _engine = sess
                dbg("ENGINE via client._session. keys=", dumpKeys(sess))
                return _engine
            end
        end

        -- Fallback: direct getgc scan, but ONLY while the minigame UI is open (so we
        -- never freeze at idle) and throttled (one brief hitch, then cached for song).
        if not minigameOpen() then
            dbgT("idle", 3, "RhythmServiceUI not open — no song, not scanning")
            return nil
        end

        local nowClock = os.clock()
        if nowClock - _lastScan < SCAN_GAP then return nil end
        _lastScan = nowClock

        if type(getgc) == "function" then
            local ok, gc = pcall(getgc, true)
            dbgT("scan_ggc", 2, "getgc(true): ok=" .. tostring(ok)
                .. " count=" .. (type(gc) == "table" and #gc or -1))
            if ok and type(gc) == "table" then
                for i = 1, #gc do
                    local o = gc[i]
                    if type(o) == "table" and looksLikeEngine(o) then
                        _engine = o
                        dbg("ENGINE via getgc. keys=", dumpKeys(o))
                        return _engine
                    end
                end
            end
        end

        dbgT("no_engine", 2, "song seems active but engine not found this scan. Retrying...")
        return nil
    end

    -- ── The autoplay step (one pass over the on-screen notes) ────────────────
    -- Strategy: mimic a real player. Press a note's lane exactly when it arrives
    -- (now >= note.t); for a hold, keep the key logically down and RELEASE it when
    -- the hold duration completes (now >= note.t + note.len). The engine's own
    -- _onReleaseLane then finalizes the hold with fraction = (release - start)/len
    -- ≈ 1.0 → PERFECT (RhythmEngine:1178). We do NOT poke internal fields — genuine
    -- press/release through the real handlers is what the engine trusts.
    local _laneHolding, _pressTap = {}, {}      -- reused scratch tables
    local _heldLane = {}   -- lane -> hold note we are currently holding (persists across frames)
    local _gradeSeen = setmetatable({}, { __mode = "k" })  -- note -> true once we've logged its grade
    local _lastEngine  -- detect song changes to drop stale hold tracking

    local function step()
        if not Config.AutoRythm_On then return end
        local engine = getEngine()
        if not engine then return end

        -- New song / new engine → forget any hold we thought we were holding.
        if engine ~= _lastEngine then
            _lastEngine = engine
            table.clear(_heldLane)
        end

        local okNow, now = pcall(engine._now, engine)
        if not okNow or type(now) ~= "number" then return end

        local active = engine._active
        if type(active) ~= "table" then return end
        local lanes  = engine._lanes or 0
        local offset = (Config.Offset or 0) / 1000

        dbgT("step_alive", 2, ("step: now=%.2f lanes=%d activeNotes=%d"):format(now, lanes, #active))

        table.clear(_laneHolding); table.clear(_pressTap)

        -- Lanes with a hold currently in progress must never be tap-released.
        for _, note in ipairs(active) do
            if (note.len or 0) > 0 and note.hit and not note.holdJudgment then
                _laneHolding[note.lane] = true
            end
            -- Lifecycle logging: report the ACTUAL grade the engine assigns a hold.
            if (note.len or 0) > 0 and note.holdJudgment and not _gradeSeen[note] then
                _gradeSeen[note] = true
                local frac = note.holdDuration and note.len and (note.holdDuration / note.len) or -1
                dbg(("HOLD GRADE lane=%d judgment=%s frac=%.3f start=%.3f end=%.3f len=%.2f")
                    :format(note.lane or -1, tostring(note.holdJudgment), frac,
                            note.holdStartTime or -1, note.holdEndTime or -1, note.len or -1))
            end
        end

        local nHoldStart, nHoldEnd, nTap = 0, 0, 0

        -- 1) RELEASE holds whose duration has elapsed (now >= t + len). This is the
        --    finalize a real player triggers — gives fraction ≈ 1.0 → PERFECT.
        for lane, note in pairs(_heldLane) do
            local finalized = note.holdJudgment ~= nil
            local elapsed   = now >= (note.t + (note.len or 0))
            if finalized then
                _heldLane[lane] = nil                       -- engine already scored it
            elseif elapsed then
                local ok = pcall(engine._handleLaneRelease, engine, lane)
                _heldLane[lane] = nil
                nHoldEnd = nHoldEnd + 1
                dbg(("HOLD RELEASE lane=%d ok=%s at now=%.3f (t+len=%.3f) holding=%s")
                    :format(lane, tostring(ok), now, note.t + (note.len or 0), tostring(note.holding)))
            end
        end

        -- 2) PRESS notes that have arrived. Holds start a sustain we release later;
        --    taps are pressed+released immediately.
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes
               and not note.hit and not note.attempted then
                if (note.len or 0) > 0 then
                    -- Hold: press only at/after note.t (an early press takes the
                    -- "future note" branch and never sets holding — _onPressLane:1154).
                    local holdOffset = (offset > 0) and offset or 0
                    if now >= note.t + holdOffset and not _heldLane[lane] then
                        local ok = pcall(engine._handleLanePress, engine, lane)
                        _heldLane[lane] = note
                        _laneHolding[lane] = true
                        nHoldStart = nHoldStart + 1
                        dbg(("HOLD START  lane=%d ok=%s -> hit=%s holding=%s dt=%.3f len=%.2f")
                            :format(lane, tostring(ok), tostring(note.hit), tostring(note.holding),
                                    now - note.t, note.len or -1))
                    end
                elseif now >= note.t + offset and not _laneHolding[lane] then
                    local ok1 = pcall(engine._handleLanePress, engine, lane)
                    local ok2 = pcall(engine._handleLaneRelease, engine, lane)
                    nTap = nTap + 1
                    dbg(("TAP  lane=%d press=%s release=%s"):format(lane, tostring(ok1), tostring(ok2)))
                end
            end
        end

        if nHoldStart > 0 or nHoldEnd > 0 or nTap > 0 then
            dbgT("frame_fire", 1, ("frame: %d hold-start, %d hold-release, %d tap")
                :format(nHoldStart, nHoldEnd, nTap))
        end
    end

    -- ═══════════════════════════════ MODULE ═════════════════════════════════
    local M = {}
    local _conn

    function M.start()
        Config.AutoRythm_On = false
        dbg("module start() — filtergc available:", type(filtergc) == "function")
        -- Drive on RenderStepped (the same signal the engine steps on). Timing is
        -- taken from the engine's own audio clock, so signal order is irrelevant.
        if not _conn then
            _conn = RunService.RenderStepped:Connect(function()
                if Config.AutoRythm_On then
                    -- swallow errors: a transient nil during song teardown must never spam
                    local ok, err = pcall(step)
                    if not ok then dbgT("step_err", 1, "step ERROR:", tostring(err)) end
                end
            end)
            dbg("RenderStepped connected")
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

        -- ─────────────── Section: AutoRythm (Left) ─��─────────────
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
        sAR:Header({ Name = "Debug" })
        sAR:Toggle({
            Name = "Debug Logs", Default = Config.Debug,
            Callback = function(v)
                Config.Debug = v
                if v then print("[AutoRythm]", "debug logging ENABLED — open a song, enable AutoRythm, and watch the console") end
            end,
        }, ctx.flag("Misc_AutoRythm_Debug"))
        sAR:SubLabel({ Text = "Prints [AutoRythm] traces to the executor console so we can see where it stops (client found? session live? notes seen? presses fired?)." })
        sAR:Divider()
        sAR:SubLabel({ Text = "Grabs the live RhythmEngine and plays it directly, so the game sees a clean PERFECT run. Just start a song and enable." })

        uiReady = true
    end

    return M
end
