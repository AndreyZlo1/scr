-- ═══════════════════════════════════════════════════════════════════════════
--  Misc module for the Syllinse loader (AutoParry game, UniverseId 9199655655).
--  Misc features, all built into ctx.tabs.Misc:
--
--    1. AutoRythm  — auto-plays the in-game RHYTHM MINIGAME
--       (ReplicatedStorage.Shared.Services.RhythmService) with frame-perfect
--       timing by driving the live RhythmEngine's own methods.
--
--    2. Auto Draw  — draws an image (from a URL or a file in the executor
--       workspace) onto the nearest chalk whiteboard
--       (ReplicatedStorage.Shared.Services.WhiteboardService) by firing the
--       game's own WhiteboardDrawBatch remote with raster stroke data.
--
--    3. ChessEngine — reads the chess client's authoritative live FEN, sends it
--       to chess-api.com over WebSocket, validates the returned move against the
--       live legal-move generator, and highlights the source/destination cells.
--
--  Loader contract (same as movement/visuals):
--    • file body returns function(Lib, Core) → returns a handle with
--      optional start() and buildUI(ctx).
--    • ctx gives: tabs (keyed by Tab.Key), flag(name), keybind(section,opts),
--      notify(title,desc).
--
--  ── AutoRythm, how it works (verified against the decompiled dump) ──────────
--    • The RhythmServiceClient singleton holds the live play session in
--      ._session while a song runs (set at start, cleared at end). We find the
--      client once via filtergc and read ._session per frame — no heap sweeps.
--      Fallback: a getgc scan gated on the RhythmServiceUI ScreenGui being open,
--      so we never scan (never freeze) while idle.
--    • engine._active = on-screen notes: t (hit time, engine audio-clock), lane,
--      len (0 = tap, >0 = hold), hit/attempted/holding flags.
--    • TAPS: press+release the moment now >= note.t → PERFECT (window is 43ms,
--      our error is one frame ~16ms).
--    • HOLDS: press once at note.t and keep the lane "held". A spurious InputEnded
--      would EARLY_RELEASE the hold, so we install an instance-level guard over
--      _handleLaneRelease that drops any release we didn't authorize; the engine's
--      own _step then auto-finalizes the sustain at t+len as PERFECT.
--
--  ── Auto Draw, how it works (verified against WhiteboardServiceClient) ──────
--    • Boards are CollectionService-tagged "Whiteboard" BaseParts carrying a
--      numeric WhiteboardId attribute. Canvas is a 512×384 EditableImage.
--    • The client sends strokes through Client.WhiteboardDrawBatch.Fire(buf):
--        u32 boardId | u8 brushRadius | u8 R | u8 G | u8 B | N×(f32 u, f32 v)
--      where u,v are 0..1 canvas coordinates. Consecutive points in one batch are
--      connected into a line of one colour (server interpolates via chalkSegment).
--    • We load the image into an EditableImage (getcustomasset + AssetService),
--      read its pixels, fit it to the board preserving aspect, then walk it row by
--      row emitting horizontal same-colour runs. The remote is UNRELIABLE, so we
--      rate-limit sends to a user-set strokes-per-second budget (with a burst cap)
--      to avoid dropped packets and anti-cheat kicks. Brush radius is fixed at 2
--      (the value the game itself always sends).
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    -- Luraph macro raw shim. The per-frame rhythm step is wrapped in
    -- LPH_NO_VIRTUALIZE(function() ... end) so Luraph keeps the frame-perfect
    -- timing native. You CANNOT declare a local/variable named LPH_* — Luraph
    -- reserves the prefix and errors ("cannot be used as a variable name"). So when
    -- run raw we install an identity fallback under that name via a STRING key
    -- (concat so the reserved token never appears). After Luraph this line is dead.
    do
        local k = "LPH" .. "_NO_VIRTUALIZE"
        local G = (type(getgenv) == "function") and getgenv() or _G
        if not G[k] then G[k] = function(f) return f end end
    end

    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local CoreGui           = game:GetService("CoreGui")
    local AssetService      = game:GetService("AssetService")
    local CollectionService = game:GetService("CollectionService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace         = game:GetService("Workspace")
    local HttpService       = game:GetService("HttpService")
    local TweenService      = game:GetService("TweenService")

    local LocalPlayer = Players.LocalPlayer

    -- ── Runtime config (MacLib restores flags through the config manager) ────
    local Config = {
        AutoRythm_On = false,

        -- Timing nudge (ms). 0 = frame-perfect. Negative = press earlier, positive
        -- = later. Only change for audio/display latency; PERFECT window is ±43ms.
        Offset = 0,

        AutoDraw = {
            Url        = "",     -- image URL to download and draw
            File       = "",     -- image file in the executor workspace
            Source     = "",     -- "url" | "file": which input the user touched last
            Quality    = 80,     -- 1-100: single knob for detail + colour fidelity
            Speed      = 400,    -- points/second painted (local+server together); batched into ≤24-pt packets so few packets are sent
            Threshold  = 16,     -- brightness (0-255) below which a pixel is skipped
            SkipBg     = false,  -- OFF by default so black pixels ARE drawn (was skipping them)
            Mono       = false,  -- draw everything in chalk white instead of colour
            Preserve   = true,   -- preserve the image aspect ratio on the board
            Sync       = true,   -- also fire the draw remote (persist + show to others)
            Scale      = 100,    -- % of the board the drawing occupies (10-100)
            AlignX     = 50,     -- horizontal placement: 0 = left, 50 = center, 100 = right
            AlignY     = 50,     -- vertical placement: 0 = top, 50 = middle, 100 = bottom
            Preview    = false,  -- show the board/region preview overlay while ON
        },

        Chalk = {
            Auto     = false,       -- endlessly take + drop items
            Items    = "Alternate", -- "Alternate" (chalk<->sponge) | "Chalk" | "Sponge"
            Mode     = "Rainbow",   -- chalk colour: "Rainbow" | "Random" | a color key
            Delay    = 0.35,        -- seconds between take/drop actions
            Cooldown = 3,           -- seconds a rate-limited item type is skipped
        },

        Chess = {
            Enabled          = false,
            AutoAnalyze      = true,
            OnlyMyTurn       = true,
            Progressive      = true,
            Depth            = 12,
            ThinkingTime     = 50,
            PollRate         = 0.20,
            ReconnectDelay   = 2,
            FromColor        = Color3.fromRGB(66, 166, 255),
            ToColor          = Color3.fromRGB(85, 255, 135),
            FillTransparency = 0.42,
            AlwaysOnTop      = false,
            NotifyMove       = true,
            ShowOverlay      = true,   -- 2D board + eval bar overlay
        },
    }

    -- ═══════════════════════════ AUTORYTHM ══════════════════════════════════
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

    -- Engine (play session) signature (real instance keys, RhythmEngine:100-160).
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
        if ok and looksLikeClient(res) then _client = res; return _client end
        local ok2, list = pcall(filtergc, "table", { Keys = CLIENT_KEYS }, false)
        if ok2 and type(list) == "table" then
            for i = 1, #list do
                if looksLikeClient(list[i]) then _client = list[i]; return _client end
            end
        end
        return nil
    end

    -- Cheap "is the rhythm minigame open?" gate: the RhythmServiceUI ScreenGui
    -- lives in PlayerGui while a song is open (RhythmServiceClient:73). A single
    -- FindFirstChild — no GC work — gates the getgc fallback so we never scan idle.
    local function minigameOpen()
        local ok, found = pcall(function()
            local pg = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg and pg:FindFirstChild("RhythmServiceUI") then return true end
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
        if client then
            local ok, sess = pcall(function() return client._session end)
            if ok and looksLikeEngine(sess) then _engine = sess; return _engine end
        end

        if not minigameOpen() then return nil end

        local nowClock = os.clock()
        if nowClock - _lastScan < SCAN_GAP then return nil end
        _lastScan = nowClock

        if type(getgc) == "function" then
            local ok, gc = pcall(getgc, true)
            if ok and type(gc) == "table" then
                for i = 1, #gc do
                    local o = gc[i]
                    if type(o) == "table" and looksLikeEngine(o) then _engine = o; return _engine end
                end
            end
        end
        return nil
    end

    -- ── Autoplay step ─────────────────────────────────────────────────────────
    local _laneHolding = {}                -- reused scratch table (cleared each frame)
    local _heldLane    = {}                -- lane -> hold note currently held
    local _allowRelease = {}               -- lane -> true when WE authorize a release
    local _lastEngine

    -- Instance-level guard over _handleLaneRelease: while a lane is auto-held, drop
    -- any release we didn't authorize (a stray InputEnded would EARLY_RELEASE the
    -- hold before the engine auto-finalizes it at t+len). We only allow the single
    -- cleanup release we fire ourselves after the hold has already been scored.
    -- Unique per SCRIPT LOAD. If the user re-executes the script, the engine object may
    -- persist with an OLD guard installed whose closures capture the OLD (dead) _heldLane
    -- table — that stale guard blocks nothing and every release slips through as an
    -- EARLY_RELEASE. Tagging the engine with this token lets us detect "my guard isn't the
    -- live one" and reinstall fresh closures bound to THIS load's tables.
    local GUARD_TOKEN = {}
    local function installReleaseGuard(engine)
        if rawget(engine, "__ar_guardToken") == GUARD_TOKEN then return end

        -- Capture the TRUE originals once (never chain onto a previous guard).
        if type(rawget(engine, "__ar_realRelease")) ~= "function" then
            local r = engine._handleLaneRelease
            if type(r) == "function" then rawset(engine, "__ar_realRelease", r) end
        end
        if type(rawget(engine, "__ar_realOnRelease")) ~= "function" then
            local r = engine._onReleaseLane
            if type(r) == "function" then rawset(engine, "__ar_realOnRelease", r) end
        end
        local realRelease   = rawget(engine, "__ar_realRelease")
        local realOnRelease = rawget(engine, "__ar_realOnRelease")
        if type(realRelease) ~= "function" then return end

        -- Guard _handleLaneRelease: drop unauthorized releases on held lanes.
        rawset(engine, "_handleLaneRelease", function(self, lane)
            if _heldLane[lane] and not _allowRelease[lane] then return end
            return realRelease(self, lane)
        end)

        -- Guard _onReleaseLane: THE real protection. This is the only function that sets
        -- EARLY_RELEASE and applies its score (RhythmEngine:1183-1184). No matter what
        -- calls it (keyboard/gamepad/touch InputEnded), block it on a lane we are
        -- deliberately auto-holding so the engine finalizes the sustain as PERFECT at
        -- t+len instead.
        if type(realOnRelease) == "function" then
            rawset(engine, "_onReleaseLane", function(self, lane, t)
                if _heldLane[lane] and not _allowRelease[lane] then return end
                return realOnRelease(self, lane, t)
            end)
        end

        rawset(engine, "__ar_guardToken", GUARD_TOKEN)
    end

    -- [LURAPH] per-frame rhythm autoplay step — the frame-perfect timing path.
    -- Kept native under Luraph so tap/hold timing isn't slowed by virtualization.
    local step = LPH_NO_VIRTUALIZE(function()
        if not Config.AutoRythm_On then return end
        local engine = getEngine()
        if not engine then return end

        if engine ~= _lastEngine then
            _lastEngine = engine
            table.clear(_heldLane)
            table.clear(_allowRelease)
        end

        installReleaseGuard(engine)

        local okNow, now = pcall(engine._now, engine)
        if not okNow or type(now) ~= "number" then return end

        local active = engine._active
        if type(active) ~= "table" then return end
        local lanes  = engine._lanes or 0
        local offset = (Config.Offset or 0) / 1000

        table.clear(_laneHolding)

        -- HOW HOLDS WORK IN THIS ENGINE (fully verified in RhythmEngine._step):
        --   • _onPressLane (called by _handleLanePress) judges the tap and, for a hold
        --     pressed on time, sets hit=true, holding=true, holdStartTime (RhythmEngine
        --     :1150-1163).
        --   • Every frame _step AUTO-PROMOTES any hit hold to holding once note.t <= now
        --     (RhythmEngine:1463-1471) — so even a hair-early press is fixed up.
        --   • At note.t+note.len, _step AUTO-FINALIZES the hold: ratio=(now-holdStart)/len
        --     ≈ 1.0 → PERFECT (RhythmEngine:1582-1601). This runs whether or not the note
        --     still has a visual instance, and BEFORE the miss/despawn cutoff at
        --     note.t+note.len+BAD. It is NOT gated by physical key state.
        --
        -- => The ONLY thing autoplay must do for a hold is PRESS IT ONCE at note.t and
        --    NOT release it. The engine holds and scores it. Previously we also forced
        --    note fields and called _applyScore ourselves; that raced the engine's own
        --    per-frame promote/finalize and mis-scored the note (the immediate MISS).
        --    So we no longer touch note fields or score manually — we just press and wait.

        -- 1) Track notes we're holding: release ONLY after the engine has finalized them
        --    (holdJudgment set) so a future note on that lane starts from a clean key
        --    state. A safety timeout releases anything stuck well past its end.
        for lane, note in pairs(_heldLane) do
            local holdEnd = note.t + (note.len or 0)
            if note.holdJudgment ~= nil or now > holdEnd + 0.5 then
                _allowRelease[lane] = true
                pcall(engine._handleLaneRelease, engine, lane)
                _allowRelease[lane] = nil
                _heldLane[lane] = nil
            else
                -- Still holding: mark the lane so the tap branch never releases it, and
                -- let the engine keep/advance the hold on its own.
                _laneHolding[lane] = true
            end
        end

        -- 2) Press notes that have arrived.
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes
               and not note.hit and not note.attempted then
                if (note.len or 0) > 0 then
                    -- Hold: press ONCE at note.t and leave the key logically down. The
                    -- engine promotes it to holding and auto-finalizes it as PERFECT.
                    if now >= note.t + offset and not _heldLane[lane] then
                        pcall(engine._handleLanePress, engine, lane)
                        _heldLane[lane]    = note
                        _laneHolding[lane] = true
                    end
                elseif now >= note.t + offset and not _laneHolding[lane] then
                    -- Tap: press + immediate release.
                    pcall(engine._handleLanePress, engine, lane)
                    pcall(engine._handleLaneRelease, engine, lane)
                end
            end
        end
    end)

    -- ═══════════════════════════ AUTO DRAW ══════════════════════════════════
    local CHALK_COLOR = Color3.fromRGB(242, 242, 238)
    local BOARD_W, BOARD_H = 512, 384   -- EditableImage canvas (WhiteboardServiceClient:189)

    -- Debug logging removed — kept as a no-op so the existing call sites stay valid.
    local function adlog() end

    -- Replicates WhiteboardServiceClient.uvToWorldPos (dump line 176): maps a board
    -- UV (0..1) to a world position on the correct face. Used purely for the visual
    -- preview so the user can see WHERE the image will land before drawing.
    local function uvToWorldPos(part, face, u, v)
        local S = part.Size
        local off
        if face == Enum.NormalId.Front then
            off = Vector3.new((0.5 - u) * S.X, (0.5 - v) * S.Y, -S.Z / 2)
        elseif face == Enum.NormalId.Back then
            off = Vector3.new((u - 0.5) * S.X, (0.5 - v) * S.Y, S.Z / 2)
        elseif face == Enum.NormalId.Left then
            off = Vector3.new(-S.X / 2, (0.5 - v) * S.Y, (u - 0.5) * S.Z)
        elseif face == Enum.NormalId.Right then
            off = Vector3.new(S.X / 2, (0.5 - v) * S.Y, (0.5 - u) * S.Z)
        elseif face == Enum.NormalId.Top then
            off = Vector3.new((u - 0.5) * S.X, S.Y / 2, (v - 0.5) * S.Z)
        else -- Bottom
            off = Vector3.new((u - 0.5) * S.X, -S.Y / 2, (0.5 - v) * S.Z)
        end
        return part.CFrame:PointToWorldSpace(off)
    end

    -- Discover which SurfaceGui face a board draws on (defaults to Front).
    local function boardFace(part)
        local sg = part:FindFirstChildOfClass("SurfaceGui")
        if sg and sg.Face then return sg.Face end
        return Enum.NormalId.Front
    end

    -- ── Visual preview: highlight the detected board + outline the draw region ──
    local _previewFolder
    local function clearPreview()
        if _previewFolder then
            pcall(function() _previewFolder:Destroy() end)
            _previewFolder = nil
        end
    end

    -- Build a thin neon beam between two world points (one wireframe edge).
    local function edgePart(parent, a, b, color)
        local mid = (a + b) / 2
        local len = (a - b).Magnitude
        local p = Instance.new("Part")
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Material = Enum.Material.Neon
        p.Color = color
        p.Size = Vector3.new(0.15, 0.15, math.max(len, 0.05))
        p.CFrame = CFrame.lookAt(mid, b)
        p.Parent = parent
        return p
    end

    -- Compute the aspect-preserving letterbox region (in board pixels), exactly as
    -- runDraw does. Pass imgW/imgH when known; nil → assume the region fills the
    -- board. `scale` (0-1) shrinks the region so it covers only part of the board;
    -- `ax`/`ay` (0-1) place it (0 = left/top, .5 = center, 1 = right/bottom).
    -- Returns UV rect u0,v0,u1,v1.
    local function computeRegion(preserve, imgW, imgH, scale, ax, ay)
        scale = math.clamp(scale or 1, 0.05, 1)
        ax = math.clamp(ax == nil and 0.5 or ax, 0, 1)
        ay = math.clamp(ay == nil and 0.5 or ay, 0, 1)
        local drawW, drawH
        if preserve and imgW and imgH and imgW > 0 and imgH > 0 then
            local imgA, boardA = imgW / imgH, BOARD_W / BOARD_H
            if imgA > boardA then drawW, drawH = BOARD_W, BOARD_W / imgA
            else drawW, drawH = BOARD_H * imgA, BOARD_H end
        else
            drawW, drawH = BOARD_W, BOARD_H
        end
        drawW, drawH = drawW * scale, drawH * scale
        local offX, offY = (BOARD_W - drawW) * ax, (BOARD_H - drawH) * ay
        return offX / BOARD_W, offY / BOARD_H, (offX + drawW) / BOARD_W, (offY + drawH) / BOARD_H
    end

    -- Draw a highlight over the board + a green outline of the UV rect (u0,v0,u1,v1).
    local function showPreview(board, u0, v0, u1, v1, ttl)
        clearPreview()
        local part = board.part
        local face = boardFace(part)

        local folder = Instance.new("Folder")
        folder.Name = "SyllinseAutoDrawPreview"
        folder.Parent = Workspace

        -- Highlight the whole board so the user sees which one was picked.
        local hl = Instance.new("Highlight")
        hl.FillColor = Color3.fromRGB(70, 170, 255)
        hl.FillTransparency = 0.7
        hl.OutlineColor = Color3.fromRGB(120, 200, 255)
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = part
        hl.Parent = folder

        -- Outline the draw region on the board face (4 corners → 4 edges).
        local green = Color3.fromRGB(80, 255, 120)
        local TL = uvToWorldPos(part, face, u0, v0)
        local TR = uvToWorldPos(part, face, u1, v0)
        local BR = uvToWorldPos(part, face, u1, v1)
        local BL = uvToWorldPos(part, face, u0, v1)
        edgePart(folder, TL, TR, green)
        edgePart(folder, TR, BR, green)
        edgePart(folder, BR, BL, green)
        edgePart(folder, BL, TL, green)

        _previewFolder = folder

        if ttl and ttl > 0 then
            task.delay(ttl, function()
                if _previewFolder == folder then clearPreview() end
            end)
        end
    end

    -- Lazily grab the game's network Client (cached ModuleScript singleton).
    local _netClient
    local function getNet()
        if _netClient ~= nil then return _netClient or nil end
        local ok, mod = pcall(function()
            local shared  = ReplicatedStorage:FindFirstChild("Shared")
            local network = shared and shared:FindFirstChild("Network")
            local client  = network and network:FindFirstChild("Client")
            return client and require(client)
        end)
        _netClient = (ok and mod) or false
        adlog("getNet: ok=%s hasClient=%s hasRemote=%s",
            tostring(ok), tostring(_netClient ~= false),
            tostring(_netClient and _netClient.WhiteboardDrawBatch ~= nil))
        return _netClient or nil
    end

    -- Is ANY chalk currently equipped on our character? The game stores the equipped
    -- item's name on the Character as the "ItemEquipped" attribute and its state as
    -- "ItemPhase" (== "Equipped" when fully out). The server only replicates whiteboard
    -- strokes while chalk is equipped, so we check this before syncing. (Verified in
    -- ItemServiceClient: char:GetAttribute("ItemEquipped") / "ItemPhase".)
    local function hasChalkEquipped()
        local char = LocalPlayer and LocalPlayer.Character
        if not char then return false end
        local ok, equipped = pcall(function() return char:GetAttribute("ItemEquipped") end)
        if not ok or type(equipped) ~= "string" then return false end
        if not equipped:lower():find("chalk") then return false end
        local okP, phase = pcall(function() return char:GetAttribute("ItemPhase") end)
        -- Accept any phase except an explicit "Unequipping"; some builds leave phase nil.
        if okP and phase == "Unequipping" then return false end
        return true
    end

    local function b8(v)
        v = math.floor(v + 0.5)
        if v < 0 then return 0 elseif v > 255 then return 255 end
        return v
    end
    local function uvClamp(v)
        if v < 0 then return 0 elseif v > 1 then return 1 end
        return v
    end

    -- Fire one stroke (a line from (u1,v1) to (u2,v2), or a dot if identical).
    local _fireErrLogged = false
    local function fireRun(boardId, brush, r, g, b, u1, v1, u2, v2)
        local net = getNet()
        if not net or not net.WhiteboardDrawBatch then return false end
        local single = (u1 == u2 and v1 == v2)
        local n = single and 1 or 2
        local buf = buffer.create(n * 8 + 8)
        buffer.writeu32(buf, 0, math.floor(boardId))
        buffer.writeu8(buf, 4, math.clamp(math.floor(brush), 1, 255))
        buffer.writeu8(buf, 5, b8(r))
        buffer.writeu8(buf, 6, b8(g))
        buffer.writeu8(buf, 7, b8(b))
        buffer.writef32(buf, 8,  uvClamp(u1))
        buffer.writef32(buf, 12, uvClamp(v1))
        if not single then
            buffer.writef32(buf, 16, uvClamp(u2))
            buffer.writef32(buf, 20, uvClamp(v2))
        end
        local ok, err = pcall(function() net.WhiteboardDrawBatch.Fire(buf) end)
        if not ok and not _fireErrLogged then
            _fireErrLogged = true
            adlog("fireRun: Fire() ERROR: %s", tostring(err))
        end
        return ok
    end

    -- ── Local rendering ─────────��────────────��───────────────────────────────
    -- CRITICAL: the game renders each board CLIENT-SIDE onto an EditableImage held
    -- in a module-local board map (WhiteboardServiceClient `u2`). When we fire the
    -- draw remote, the server only broadcasts to OTHER players — it never echoes to
    -- the sender, because the sender is expected to have already drawn locally. So
    -- firing alone shows NOTHING on our own screen. To actually SEE the drawing we
    -- must render onto the board's EditableImage ourselves, exactly like the game.
    --
    -- We reach that EditableImage through the INSTANCE TREE (never getgc — a full GC
    -- scan on the main thread hard-freezes the client). The game builds each board
    -- as: part → SurfaceGui → Canvas(Frame) → ImageLabel, where the ImageLabel's
    -- ImageContent wraps the EditableImage via Content.fromObject (dump line 204).
    -- The new Content datatype exposes the wrapped instance as `.Object`, so we can
    -- pull the live EditableImage straight out of the ImageLabel. Cached per part.
    -- Resolve the GAME'S OWN canonical EditableImage for a board.
    --
    -- WHY THIS MATTERS (the "what I see ≠ what others see, even the size" bug):
    -- the game creates ONE EditableImage per board — AssetService:CreateEditableImage
    -- {Size=512x384} — stores it in a board record `{ part, canvas, surfaceGui, face,
    -- editableImage }`, and renders BOTH its own drawing AND every received broadcast
    -- onto THAT instance (WhiteboardServiceClient u2[id].editableImage). That is the
    -- surface every other player sees. Our old code instead re-derived an image by
    -- walking part→SurfaceGui→Canvas→ImageLabel→ImageContent.Object, which can resolve
    -- a different/rescaled image object — so our local view diverged in size + look
    -- from the real board. Now we grab the game's exact record (matched by our part)
    -- from memory, so local render == the true board == what others see.
    local _eiCache   = setmetatable({}, { __mode = "k" })
    local _recCache  = setmetatable({}, { __mode = "k" })

    -- Find the game's board record whose `.part` is exactly this part, using the
    -- executor GC scanners. A record is a table carrying editableImage + part + face.
    local function gameRecordForPart(part)
        local cached = _recCache[part]
        if cached ~= nil then return cached or nil end
        local G = (getgenv and getgenv()) or _G
        local found
        local function scan(list)
            for _, t in ipairs(list) do
                if type(t) == "table" then
                    local ei = rawget(t, "editableImage")
                    if ei ~= nil and rawget(t, "part") == part and rawget(t, "face") ~= nil then
                        found = t; return true
                    end
                end
            end
            return false
        end
        if type(G.filtergc) == "function" then
            pcall(function()
                local list = G.filtergc("table", { Keys = { "editableImage", "part", "face" } }, false)
                if type(list) == "table" then scan(list) end
            end)
        end
        if not found and type(G.getgc) == "function" then
            pcall(function() scan(G.getgc(true)) end)
        end
        _recCache[part] = found or false
        return found
    end

    local function getBoardImage(part)
        if typeof(part) ~= "Instance" then return nil end
        local cached = _eiCache[part]
        if cached then return cached end

        -- 1) Preferred: the game's own canonical EditableImage (matches every client).
        local rec = gameRecordForPart(part)
        if rec and typeof(rec.editableImage) == "Instance" then
            _eiCache[part] = rec.editableImage
            adlog("getBoardImage: using GAME canonical EditableImage for '%s'", part.Name)
            return rec.editableImage
        end

        -- 2) Fallback: derive it from the GUI tree (previous behaviour).
        local sg = part:FindFirstChildOfClass("SurfaceGui")
        if not sg then adlog("getBoardImage: no SurfaceGui on '%s'", part.Name); return nil end
        local root = sg:FindFirstChild("Canvas") or sg

        local label = root:FindFirstChildOfClass("ImageLabel")
        if not label then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ImageLabel") then label = d; break end
            end
        end
        if not label then adlog("getBoardImage: no ImageLabel under SurfaceGui"); return nil end

        local img
        pcall(function()
            local content = label.ImageContent
            if content and content.Object then img = content.Object end
        end)
        if not img then
            adlog("getBoardImage: ImageContent has no .Object (unexpected Content form)")
            return nil
        end
        _eiCache[part] = img
        adlog("getBoardImage: resolved EditableImage (GUI fallback) for '%s'", part.Name)
        return img
    end

    -- The game hardcodes the chalk radius to 2 everywhere (chalkSegment / DrawCircle
    -- calls) and sends it as byte 4 of every draw buffer, so we use the identical value.
    local BRUSH_R = 2

    -- Replica of the game's chalkSegment (WhiteboardServiceClient:245): draw a dotted
    -- line between two UV points onto an EditableImage.
    local function chalkSegmentLocal(img, x1, y1, x2, y2, brush, col)
        local ax, ay = x1 * 512, y1 * 384
        local dx, dy = x2 * 512 - ax, y2 * 384 - ay
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 0.5 then return end
        local steps = math.max(1, math.floor(dist / 2))
        for i = 0, steps do
            local t = i / steps
            img:DrawCircle(
                Vector2.new(math.round(ax + dx * t), math.round(ay + dy * t)),
                brush, col, 0.05 + math.random() * 0.18, Enum.ImageCombineType.AlphaBlend)
        end
    end

    -- Render one stroke locally onto the board's EditableImage. Returns true on success.
    --
    -- `faithful` controls HOW we paint, and it matters a lot:
    --   * faithful = true  → paint EXACTLY like the server does when it broadcasts our
    --     batch to everyone else (applyDrawBuffer → a polyline of alpha-blended chalk
    --     dots, radius 2, AlphaBlend, alpha 0.05-0.23). This makes OUR screen identical
    --     to what other players see. Use this whenever Sync is on — otherwise the server
    --     render (soft, textured, blended) looks "way better" than a crude local fill,
    --     and any hard local fill would show a picture the server doesn't actually have.
    --   * faithful = false → fast path: horizontal runs become ONE solid DrawRectangle.
    --     Only safe for local-only preview (Sync off), where there is no server to match
    --     and raw speed matters.
    local function localStroke(part, brush, r, g, b, u1, v1, u2, v2, faithful)
        local img = getBoardImage(part)
        if not img then return false end
        local col = Color3.fromRGB(b8(r), b8(g), b8(b))
        local ok = pcall(function()
            if faithful then
                -- Identical to the game's own rendering of the batch we just sent.
                chalkSegmentLocal(img, uvClamp(u1), uvClamp(v1), uvClamp(u2), uvClamp(v2), brush, col)
            elseif v1 == v2 then
                local x0 = uvClamp(math.min(u1, u2)) * 512
                local x1 = uvClamp(math.max(u1, u2)) * 512
                local h  = math.max(1, brush * 2)
                local w  = math.max(1, x1 - x0)
                local y  = uvClamp(v1) * 384 - h / 2
                img:DrawRectangle(
                    Vector2.new(math.round(x0), math.round(y)),
                    Vector2.new(math.round(w), math.round(h)),
                    col, 0, Enum.ImageCombineType.Overwrite)
            else
                chalkSegmentLocal(img, uvClamp(u1), uvClamp(v1), uvClamp(u2), uvClamp(v2), brush, col)
            end
        end)
        return ok
    end

    -- Draw a stroke: always render locally (so WE see it) and, when sync is on, also
    -- fire the remote so the server persists it and other players see it too.
    -- `board` is the { id, part } table from findNearestBoard.
    local function drawStroke(board, brush, r, g, b, u1, v1, u2, v2, sync)
        -- When syncing, render faithfully (matches the server broadcast); otherwise use
        -- the fast local path.
        local shown = localStroke(board.part, brush, r, g, b, u1, v1, u2, v2, sync and true or false)
        if sync then fireRun(board.id, brush, r, g, b, u1, v1, u2, v2) end
        return shown
    end

    -- Draw a whole POLYLINE (up to 24 points) in one go — the exact unit the game
    -- itself uses (WhiteboardServiceClient.flushStroke / applyDrawBuffer): one colour,
    -- a connected path of {x=u, y=v} points. This is the key to both fidelity and
    -- speed:
    --   • LOCAL render walks the same connected path with the same chalkSegment the
    --     game runs for received broadcasts, so what WE see is produced by the exact
    --     same code as what everyone else sees — not a separate "all at once" pass.
    --   • ONE Fire() carries up to 23 segments instead of one, so a drawing that used
    --     to need thousands of packets now needs a fraction as many (the "compression"
    --     — far less load, far faster, and the unreliable remote drops far less).
    -- pts must have 1..24 entries. Returns (renderedOk, firedOk).
    local function drawBatch(board, r, g, b, pts, sync)
        local n = #pts
        if n < 1 then return false, false end
        local col = Color3.fromRGB(b8(r), b8(g), b8(b))

        -- Local render: mirror applyDrawBuffer exactly (first point = a dot, then each
        -- subsequent point connected to the previous with chalkSegment).
        local img = getBoardImage(board.part)
        local rendered = false
        if img then
            rendered = pcall(function()
                local p1 = pts[1]
                img:DrawCircle(
                    Vector2.new(math.round(uvClamp(p1.x) * 512), math.round(uvClamp(p1.y) * 384)),
                    BRUSH_R, col, 0.05 + math.random() * 0.18, Enum.ImageCombineType.AlphaBlend)
                for i = 2, n do
                    local a, b2 = pts[i - 1], pts[i]
                    chalkSegmentLocal(img, uvClamp(a.x), uvClamp(a.y), uvClamp(b2.x), uvClamp(b2.y), BRUSH_R, col)
                end
            end)
        end

        -- Server fire: pack the game's exact buffer (u32 boardId, u8 radius=2, RGB,
        -- then f32 x,y per point).
        local fired = false
        if sync then
            local net = getNet()
            if net and net.WhiteboardDrawBatch then
                fired = pcall(function()
                    local buf = buffer.create(n * 8 + 8)
                    buffer.writeu32(buf, 0, math.floor(board.id))
                    buffer.writeu8(buf, 4, BRUSH_R)
                    buffer.writeu8(buf, 5, b8(r))
                    buffer.writeu8(buf, 6, b8(g))
                    buffer.writeu8(buf, 7, b8(b))
                    for i = 1, n do
                        local off = (i - 1) * 8 + 8
                        buffer.writef32(buf, off, uvClamp(pts[i].x))
                        buffer.writef32(buf, off + 4, uvClamp(pts[i].y))
                    end
                    net.WhiteboardDrawBatch.Fire(buf)
                end)
            end
        end
        return rendered, fired
    end

    -- Clear the board both locally (paint the whole EditableImage black, exactly like
    -- the game's clearImage, WhiteboardServiceClient:243) and on the server via the
    -- WhiteboardClear remote so it persists / other players see it cleared too.
    local function clearBoard(board, serverToo)
        local cleared = false
        local img = getBoardImage(board.part)
        if img then
            local ok = pcall(function()
                img:DrawRectangle(Vector2.new(0, 0), Vector2.new(BOARD_W, BOARD_H),
                    Color3.new(0, 0, 0), 0, Enum.ImageCombineType.Overwrite)
            end)
            cleared = cleared or ok
        end
        if serverToo then
            local net = getNet()
            if net and net.WhiteboardClear then
                pcall(function() net.WhiteboardClear.Fire({ BoardId = math.floor(board.id) }) end)
                cleared = true
            end
        end
        return cleared
    end

    -- Nearest tagged whiteboard with a valid WhiteboardId; returns board + distance.
    local function findNearestBoard()
        local root
        local char = LocalPlayer.Character
        if char then root = char:FindFirstChild("HumanoidRootPart") end
        local best, bestD
        local ok, tagged = pcall(function() return CollectionService:GetTagged("Whiteboard") end)
        if not ok or type(tagged) ~= "table" then
            adlog("findNearestBoard: GetTagged('Whiteboard') failed or empty")
            return nil
        end
        local withId = 0
        for _, part in ipairs(tagged) do
            if typeof(part) == "Instance" and part:IsA("BasePart") then
                local id = part:GetAttribute("WhiteboardId")
                if type(id) == "number" then
                    withId = withId + 1
                    local d = root and (root.Position - part.Position).Magnitude or math.huge
                    if not bestD or d < bestD then best, bestD = { id = id, part = part }, d end
                end
            end
        end
        adlog("findNearestBoard: tagged=%d withId=%d nearestId=%s dist=%s root=%s",
            #tagged, withId, best and tostring(best.id) or "nil",
            bestD and string.format("%.1f", bestD) or "nil", tostring(root ~= nil))
        return best, bestD
    end

    -- ═══════════════════ PURE-LUA PNG DECODER ═══════════════════════════════
    -- The executor's getcustomasset + AssetService:CreateEditableImageAsync path is
    -- unreliable ("Failed to load texture, unexpected format" on many builds even
    -- for valid PNGs). To make loading dependable we decode PNG bytes ourselves —
    -- DEFLATE inflate + scanline unfilter — and hand back RGBA pixels directly. No
    -- Roblox image pipeline involved, so it works regardless of executor quirks.

    local PNG_SIG = string.char(137, 80, 78, 71, 13, 10, 26, 10)
    local _adYield  -- optional yield callback set during a decode to avoid timeouts

    -- RFC 1951 length/distance base + extra-bit tables.
    local LEN_BASE  = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
    local LEN_EXTRA = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
    local DIST_BASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
    local DIST_EXTRA= {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
    local CL_ORDER  = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

    -- Build a canonical Huffman table (puff-style) from 0-based code lengths.
    local function huffConstruct(lengths, n)
        local count = {}
        for l = 0, 15 do count[l] = 0 end
        for s = 0, n - 1 do count[lengths[s] or 0] = count[lengths[s] or 0] + 1 end
        count[0] = 0
        local offs = {}
        offs[1] = 0
        for l = 1, 15 do offs[l + 1] = offs[l] + count[l] end
        local symbol = {}
        for s = 0, n - 1 do
            local l = lengths[s] or 0
            if l ~= 0 then symbol[offs[l]] = s; offs[l] = offs[l] + 1 end
        end
        return { count = count, symbol = symbol }
    end

    -- Prebuilt fixed Huffman tables.
    local FIXED_LIT, FIXED_DIST
    do
        local lit = {}
        for i = 0, 143 do lit[i] = 8 end
        for i = 144, 255 do lit[i] = 9 end
        for i = 256, 279 do lit[i] = 7 end
        for i = 280, 287 do lit[i] = 8 end
        FIXED_LIT = huffConstruct(lit, 288)
        local dist = {}
        for i = 0, 31 do dist[i] = 5 end
        FIXED_DIST = huffConstruct(dist, 32)
    end

    -- Inflate a zlib/deflate stream starting at 1-based `startPos` in `data`,
    -- writing exactly `expected` bytes into a fresh buffer (PNG output size is known).
    local function inflate(data, startPos, expected)
        local byte = string.byte
        local pos = startPos
        local bitbuf, bitcnt = 0, 0

        local function getbit()
            if bitcnt == 0 then
                bitbuf = byte(data, pos) or 0
                pos = pos + 1
                bitcnt = 8
            end
            local b = bitbuf % 2
            bitbuf = (bitbuf - b) * 0.5
            bitcnt = bitcnt - 1
            return b
        end
        local function getbits(nn)
            local v, m = 0, 1
            for _ = 1, nn do v = v + getbit() * m; m = m + m end
            return v
        end
        local function decode(h)
            local code, first, index = 0, 0, 0
            local count = h.count
            for len = 1, 15 do
                code = code + getbit()
                local c = count[len]
                if code - c < first then return h.symbol[index + (code - first)] end
                index = index + c
                first = (first + c) * 2
                code = code * 2
            end
            return -1
        end

        local out = buffer.create(expected)
        local outLen = 0
        local sinceYield = 0
        local function putbyte(b)
            buffer.writeu8(out, outLen, b)
            outLen = outLen + 1
        end
        local function maybeYield()
            sinceYield = sinceYield + 1
            if sinceYield >= 24000 then
                sinceYield = 0
                if _adYield then _adYield() end
            end
        end

        repeat
            local final = getbit()
            local btype = getbits(2)
            if btype == 0 then                     -- stored
                bitbuf, bitcnt = 0, 0
                local len = (byte(data, pos) or 0) + (byte(data, pos + 1) or 0) * 256
                pos = pos + 4
                for _ = 1, len do putbyte(byte(data, pos) or 0); pos = pos + 1 end
                maybeYield()
            elseif btype == 1 or btype == 2 then
                local litH, distH
                if btype == 1 then
                    litH, distH = FIXED_LIT, FIXED_DIST
                else
                    local hlit  = getbits(5) + 257
                    local hdist = getbits(5) + 1
                    local hclen = getbits(4) + 4
                    local clLen = {}
                    for i = 0, 18 do clLen[i] = 0 end
                    for i = 1, hclen do clLen[CL_ORDER[i]] = getbits(3) end
                    local clH = huffConstruct(clLen, 19)
                    local lens = {}
                    local nn = 0
                    while nn < hlit + hdist do
                        local sym = decode(clH)
                        if sym < 16 then
                            lens[nn] = sym; nn = nn + 1
                        elseif sym == 16 then
                            local prev = lens[nn - 1] or 0
                            for _ = 1, getbits(2) + 3 do lens[nn] = prev; nn = nn + 1 end
                        elseif sym == 17 then
                            for _ = 1, getbits(3) + 3 do lens[nn] = 0; nn = nn + 1 end
                        elseif sym == 18 then
                            for _ = 1, getbits(7) + 11 do lens[nn] = 0; nn = nn + 1 end
                        else
                            error("bad code-length symbol")
                        end
                    end
                    local litLen, distLen = {}, {}
                    for i = 0, hlit - 1 do litLen[i] = lens[i] or 0 end
                    for i = 0, hdist - 1 do distLen[i] = lens[hlit + i] or 0 end
                    litH  = huffConstruct(litLen, hlit)
                    distH = huffConstruct(distLen, hdist)
                end
                while true do
                    local sym = decode(litH)
                    if sym == 256 then break
                    elseif sym >= 0 and sym < 256 then
                        putbyte(sym); maybeYield()
                    elseif sym > 256 then
                        local li = sym - 256
                        local length = LEN_BASE[li] + getbits(LEN_EXTRA[li])
                        local dsym = decode(distH) + 1
                        local dist = DIST_BASE[dsym] + getbits(DIST_EXTRA[dsym])
                        local from = outLen - dist
                        for k = 0, length - 1 do
                            buffer.writeu8(out, outLen, buffer.readu8(out, from + k))
                            outLen = outLen + 1
                        end
                        maybeYield()
                    else
                        error("bad literal/length symbol")
                    end
                end
            else
                error("bad block type " .. tostring(btype))
            end
        until final == 1 or outLen >= expected

        return out
    end

    -- Decode PNG bytes → { w, h, buf } (RGBA u8 buffer), or nil,err. Non-interlaced,
    -- 8/16-bit, colour types 0/2/3/4/6.
    local function decodePNG(bytes)
        local byte = string.byte
        if #bytes < 8 or bytes:sub(1, 8) ~= PNG_SIG then return nil, "not a PNG" end
        local function u32(p)
            return byte(bytes, p) * 16777216 + byte(bytes, p + 1) * 65536
                 + byte(bytes, p + 2) * 256 + byte(bytes, p + 3)
        end
        local pos = 9
        local width, height, bitDepth, colorType, interlace, palette
        local idat = {}
        while pos + 7 <= #bytes do
            local len = u32(pos)
            local ctype = bytes:sub(pos + 4, pos + 7)
            local dstart = pos + 8
            if ctype == "IHDR" then
                width, height = u32(dstart), u32(dstart + 4)
                bitDepth  = byte(bytes, dstart + 8)
                colorType = byte(bytes, dstart + 9)
                interlace = byte(bytes, dstart + 12)
            elseif ctype == "PLTE" then
                palette = bytes:sub(dstart, dstart + len - 1)
            elseif ctype == "IDAT" then
                idat[#idat + 1] = bytes:sub(dstart, dstart + len - 1)
            elseif ctype == "IEND" then
                break
            end
            pos = dstart + len + 4
        end
        if not width then return nil, "no IHDR" end
        if interlace ~= 0 then return nil, "interlaced PNG unsupported (re-save without interlace)" end
        if bitDepth ~= 8 and bitDepth ~= 16 then
            return nil, ("bit depth %d unsupported (re-save as 8-bit)"):format(bitDepth or -1)
        end
        local channelsByType = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }
        local channels = channelsByType[colorType]
        if not channels then return nil, "colour type " .. tostring(colorType) .. " unsupported" end
        if colorType == 3 and not palette then return nil, "palette PNG missing PLTE" end
        if width * height > 4000000 then
            return nil, ("image too large (%dx%d) — resize under ~2000px"):format(width, height)
        end
        if #idat == 0 then return nil, "no IDAT data" end

        local comp = table.concat(idat)
        local flg = byte(comp, 2) or 0
        local startPos = (math.floor(flg / 32) % 2 == 1) and 7 or 3   -- skip zlib hdr (+dict)

        local sampleBytes = (bitDepth == 16) and 2 or 1
        local bpp = channels * sampleBytes
        local stride = width * bpp
        local expected = height * (1 + stride)

        local px
        local ok, err = pcall(function()
            local raw = inflate(comp, startPos, expected)
            local out = buffer.create(width * height * 4)
            local prev = buffer.create(stride)
            local cur  = buffer.create(stride)
            local rpos = 0
            local abs, floor = math.abs, math.floor
            local rB, wB = buffer.readu8, buffer.writeu8
            for y = 0, height - 1 do
                local ft = rB(raw, rpos); rpos = rpos + 1
                for i = 0, stride - 1 do
                    local x = rB(raw, rpos + i)
                    local val
                    if ft == 0 then
                        val = x
                    elseif ft == 1 then
                        val = x + (i >= bpp and rB(cur, i - bpp) or 0)
                    elseif ft == 2 then
                        val = x + rB(prev, i)
                    elseif ft == 3 then
                        local a = i >= bpp and rB(cur, i - bpp) or 0
                        val = x + floor((a + rB(prev, i)) / 2)
                    elseif ft == 4 then
                        local a = i >= bpp and rB(cur, i - bpp) or 0
                        local b = rB(prev, i)
                        local c = i >= bpp and rB(prev, i - bpp) or 0
                        local p = a + b - c
                        local pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                        local pr = (pa <= pb and pa <= pc) and a or (pb <= pc and b or c)
                        val = x + pr
                    else
                        error("bad filter type " .. tostring(ft))
                    end
                    wB(cur, i, val % 256)
                end
                rpos = rpos + stride
                local orow = y * width * 4
                for xp = 0, width - 1 do
                    local sp = xp * bpp
                    local r, g, b
                    if colorType == 2 or colorType == 6 then
                        r = rB(cur, sp); g = rB(cur, sp + sampleBytes); b = rB(cur, sp + 2 * sampleBytes)
                    elseif colorType == 0 or colorType == 4 then
                        r = rB(cur, sp); g = r; b = r
                    else -- palette (bitDepth 8)
                        local pp = rB(cur, sp) * 3
                        r = palette:byte(pp + 1) or 0
                        g = palette:byte(pp + 2) or 0
                        b = palette:byte(pp + 3) or 0
                    end
                    local o = orow + xp * 4
                    wB(out, o, r); wB(out, o + 1, g); wB(out, o + 2, b); wB(out, o + 3, 255)
                end
                prev, cur = cur, prev
                if (y % 32) == 0 and _adYield then _adYield() end
            end
            px = { w = width, h = height, buf = out }
        end)
        if not ok then return nil, "PNG decode error: " .. tostring(err) end
        return px
    end

    -- Load an image file into an EditableImage. Roblox reworked this API twice, and
    -- CreateEditableImageAsync now RETURNS NIL (no error) on failure, so we try every
    -- known call form and surface the REAL error/reason instead of guessing.
    local function loadEditableImage(path)
        local getAsset = getcustomasset or getsynasset
        if type(getAsset) ~= "function" then
            return nil, "executor has no getcustomasset/getsynasset"
        end
        local okA, asset = pcall(getAsset, path)
        if not okA or not asset then
            return nil, "getcustomasset failed: " .. tostring(asset)
        end
        adlog("loadImage: getcustomasset ok, asset='%s'", tostring(asset))

        local attempts = {}
        local function tryCreate(label, arg)
            local okI, res = pcall(function()
                return AssetService:CreateEditableImageAsync(arg)
            end)
            if okI and res then
                adlog("loadImage: [%s] SUCCESS size=%s", label, tostring(res.Size))
                return res
            end
            local why = okI and "returned nil (over memory budget / bad format)" or tostring(res)
            adlog("loadImage: [%s] failed: %s", label, why)
            attempts[#attempts + 1] = label .. " -> " .. why
            return nil
        end

        -- Strategy 1 (current API): CreateEditableImageAsync(Content.fromUri(asset))
        local ContentT
        pcall(function() ContentT = Content end)
        if ContentT and type(ContentT.fromUri) == "function" then
            local okC, content = pcall(ContentT.fromUri, asset)
            if okC and content then
                local img = tryCreate("Content.fromUri", content)
                if img then return img end
            else
                adlog("loadImage: Content.fromUri ctor failed: %s", tostring(content))
                attempts[#attempts + 1] = "Content.fromUri ctor -> " .. tostring(content)
            end
        else
            attempts[#attempts + 1] = "Content.fromUri unavailable"
        end

        -- Strategy 2 (legacy API): CreateEditableImageAsync(assetUriString)
        do
            local img = tryCreate("direct-string", asset)
            if img then return img end
        end

        return nil, "CreateEditableImage failed ��� " .. table.concat(attempts, " | ")
    end

    -- Read every pixel; returns { w, h, buf|arr } for O(1) sampling.
    local function readPixels(img)
        local size = img.Size
        local w, h = math.floor(size.X), math.floor(size.Y)
        if w < 1 or h < 1 then return nil end
        local buf
        if pcall(function() buf = img:ReadPixelsBuffer(Vector2.zero, size) end) and buf then
            return { w = w, h = h, buf = buf }
        end
        local arr
        if pcall(function() arr = img:ReadPixels(Vector2.zero, size) end) and type(arr) == "table" then
            return { w = w, h = h, arr = arr }
        end
        return nil
    end

    -- Sample a pixel (0-based ix,iy), returns r,g,b in 0-255.
    local function samplePix(px, ix, iy)
        local w, h = px.w, px.h
        if ix < 0 then ix = 0 elseif ix >= w then ix = w - 1 end
        if iy < 0 then iy = 0 elseif iy >= h then iy = h - 1 end
        local idx = (iy * w + ix) * 4
        if px.buf then
            return buffer.readu8(px.buf, idx),
                   buffer.readu8(px.buf, idx + 1),
                   buffer.readu8(px.buf, idx + 2)
        else
            local a = px.arr
            return (a[idx + 1] or 0) * 255, (a[idx + 2] or 0) * 255, (a[idx + 3] or 0) * 255
        end
    end

    -- ═══════════════════ PURE-LUA JPEG DECODER ══════════════════════════════
    -- Baseline (sequential DCT + Huffman) JPEG decoder. Same rationale as the PNG
    -- decoder: the executor's getcustomasset + CreateEditableImageAsync pipeline
    -- fails on real photos ("unexpected format"), so we decode the bytes ourselves.
    -- Supports greyscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0 subsampling, and restart
    -- markers. Progressive JPEGs are rejected with a clear message.
    local ZIGZAG = {
        [0]=0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
        12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,
        35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,
        58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63,
    }
    local IDCT_M = {}
    do
        local cos, pi, sqrt = math.cos, math.pi, math.sqrt
        for x = 0, 7 do
            IDCT_M[x] = {}
            for u = 0, 7 do
                local cu = (u == 0) and (1 / sqrt(2)) or 1
                IDCT_M[x][u] = 0.5 * cu * cos((2 * x + 1) * u * pi / 16)
            end
        end
    end
    local function decodeJPEG(data)
        local byte = string.byte
        local n = #data
        if n < 2 or byte(data,1) ~= 0xFF or byte(data,2) ~= 0xD8 then return nil,"not a JPEG" end
        local pos = 3
        local quant, huffDC, huffAC = {}, {}, {}
        local width, height, components = nil, nil, {}
        local restartInterval, progressive, frameFound = 0, false, false
        local sosFound = false
        local function buildHuff(counts, symbols)
            local mincode, maxcode, valptr = {}, {}, {}
            local code, p = 0, 1
            for l = 1, 16 do
                if counts[l] > 0 then
                    valptr[l] = p; mincode[l] = code
                    code = code + counts[l]; maxcode[l] = code - 1; p = p + counts[l]
                else maxcode[l] = -1 end
                code = code * 2
            end
            return { mincode=mincode, maxcode=maxcode, valptr=valptr, values=symbols }
        end
        while pos < n do
            if byte(data,pos) ~= 0xFF then pos = pos + 1
            else
                local marker = byte(data,pos+1); pos = pos + 2
                if marker == 0xD9 then break
                elseif marker == 0x01 or (marker and marker >= 0xD0 and marker <= 0xD7) then
                elseif marker == nil then break
                else
                    local len = byte(data,pos)*256 + byte(data,pos+1)
                    local seg, segEnd = pos+2, pos+len
                    if marker == 0xDB then
                        local q = seg
                        while q < segEnd do
                            local pqtq = byte(data,q); q = q + 1
                            local pq, tq = math.floor(pqtq/16), pqtq%16
                            local t = {}
                            for i=0,63 do
                                local v
                                if pq==0 then v=byte(data,q); q=q+1 else v=byte(data,q)*256+byte(data,q+1); q=q+2 end
                                t[ZIGZAG[i]] = v
                            end
                            quant[tq] = t
                        end
                    elseif marker == 0xC0 or marker == 0xC1 then
                        frameFound = true
                        local p = seg
                        height = byte(data,p+1)*256+byte(data,p+2)
                        width  = byte(data,p+3)*256+byte(data,p+4)
                        local ncc = byte(data,p+5); p = p + 6
                        components = {}
                        for _=1,ncc do
                            local id,hv,qt = byte(data,p),byte(data,p+1),byte(data,p+2)
                            components[#components+1] = { id=id, h=math.floor(hv/16), v=hv%16, qt=qt }
                            p = p + 3
                        end
                    elseif marker == 0xC2 then progressive = true
                    elseif marker == 0xC4 then
                        local q = seg
                        while q < segEnd do
                            local tcth = byte(data,q); q=q+1
                            local tc,th = math.floor(tcth/16), tcth%16
                            local counts, tot = {}, 0
                            for l=1,16 do counts[l]=byte(data,q); tot=tot+counts[l]; q=q+1 end
                            local symbols = {}
                            for i=1,tot do symbols[i]=byte(data,q); q=q+1 end
                            local tbl = buildHuff(counts, symbols)
                            if tc==0 then huffDC[th]=tbl else huffAC[th]=tbl end
                        end
                    elseif marker == 0xDD then
                        restartInterval = byte(data,seg)*256+byte(data,seg+1)
                    elseif marker == 0xDA then
                        local p = seg
                        local ns = byte(data,p); p=p+1
                        local scan = {}
                        for _=1,ns do
                            local cs,tdta = byte(data,p),byte(data,p+1)
                            scan[#scan+1] = { id=cs, td=math.floor(tdta/16), ta=tdta%16 }
                            p = p + 2
                        end
                        p = p + 3
                        pos = p
                        for _,sc in ipairs(scan) do
                            for _,c in ipairs(components) do
                                if c.id==sc.id then c.td=sc.td; c.ta=sc.ta end
                            end
                        end
                        sosFound = true
                    end
                    if sosFound then break end
                    pos = segEnd
                end
            end
        end
        if not frameFound or not width then return nil,"no SOF frame" end
        if progressive then return nil,"progressive JPEG unsupported (re-save as baseline)" end
        if width*height > 6000000 then return nil,("image too large (%dx%d)"):format(width,height) end

        local bitBuf, bitCnt = 0, 0
        local bpos, eod = pos, false
        local function resetBits() bitBuf,bitCnt = 0,0 end
        local function nextByte()
            if bpos > n then eod=true; return 0 end
            local b = byte(data,bpos); bpos=bpos+1
            if b == 0xFF then
                local b2 = byte(data,bpos)
                if b2 == 0x00 then bpos=bpos+1
                else bpos=bpos-1; eod=true; return 0 end
            end
            return b
        end
        local POW2 = {[0]=1,2,4,8,16,32,64,128,256}
        local MASK = {[0]=0,1,3,7,15,31,63,127,255}
        local band, rshift = bit32.band, bit32.rshift
        local function getBit()
            if bitCnt==0 then bitBuf=nextByte(); bitCnt=8 end
            bitCnt = bitCnt - 1
            return band(rshift(bitBuf, bitCnt), 1)
        end
        local function getBits(s)
            local v = 0
            while s > 0 do
                if bitCnt==0 then bitBuf=nextByte(); bitCnt=8 end
                local take = s < bitCnt and s or bitCnt
                bitCnt = bitCnt - take
                v = v * POW2[take] + band(rshift(bitBuf, bitCnt), MASK[take])
                s = s - take
            end
            return v
        end
        local function receiveExtend(s)
            if s==0 then return 0 end
            local v = getBits(s)
            if v < 2^(s-1) then v = v - 2^s + 1 end
            return v
        end
        local function huffDecode(tbl)
            local code = 0
            for l=1,16 do
                code = code*2 + getBit()
                if tbl.maxcode[l] >= 0 and code <= tbl.maxcode[l] then
                    return tbl.values[tbl.valptr[l] + (code - tbl.mincode[l])]
                end
            end
            return nil
        end
        local function consumeRestart()
            resetBits(); eod=false
            while bpos <= n do
                if byte(data,bpos)==0xFF then
                    local m = byte(data,bpos+1)
                    if m and m>=0xD0 and m<=0xD7 then bpos=bpos+2; return end
                    if m==0xD9 then return end
                end
                bpos = bpos + 1
            end
        end

        local maxH, maxV = 1, 1
        for _,c in ipairs(components) do if c.h>maxH then maxH=c.h end if c.v>maxV then maxV=c.v end end
        local mcuW, mcuH = 8*maxH, 8*maxV
        local mcusX, mcusY = math.ceil(width/mcuW), math.ceil(height/mcuH)
        for _,c in ipairs(components) do
            c.planeW = mcusX*c.h*8; c.planeH = mcusY*c.v*8
            c.plane = buffer.create(c.planeW*c.planeH); c.pred = 0
        end
        local coef, tmp = {}, {}
        for i=0,63 do coef[i]=0; tmp[i]=0 end
        local dirty = {}
        local function decodeBlock(c, bx, by)
            local qt = quant[c.qt]
            local t = huffDecode(huffDC[c.td]); if t==nil then return false end
            c.pred = c.pred + receiveExtend(t)
            local dc = c.pred * qt[0]
            coef[0] = dc
            local k = 1
            local dirtyN = 0
            while k < 64 do
                local rs = huffDecode(huffAC[c.ta]); if rs==nil then return false end
                local r,s = math.floor(rs/16), rs%16
                if s==0 then if r==15 then k=k+16 else break end
                else
                    k=k+r; if k>63 then break end
                    local p2 = ZIGZAG[k]
                    coef[p2] = receiveExtend(s)*qt[p2]; k=k+1
                    dirtyN = dirtyN + 1; dirty[dirtyN] = p2
                end
            end
            local plane,pw = c.plane, c.planeW
            local ox,oy = bx*8, by*8
            -- Fast path: no AC coefficients → the whole 8x8 block is one flat value.
            -- (Very common in smooth photo regions; skips the ~1k-op IDCT entirely.)
            if dirtyN == 0 then
                local val = dc * 0.125 + 128
                if val<0 then val=0 elseif val>255 then val=255 end
                for y=0,7 do
                    local rowoff=(oy+y)*pw+ox
                    buffer.writeu8(plane,rowoff,val);   buffer.writeu8(plane,rowoff+1,val)
                    buffer.writeu8(plane,rowoff+2,val); buffer.writeu8(plane,rowoff+3,val)
                    buffer.writeu8(plane,rowoff+4,val); buffer.writeu8(plane,rowoff+5,val)
                    buffer.writeu8(plane,rowoff+6,val); buffer.writeu8(plane,rowoff+7,val)
                end
                coef[0] = 0
                return true
            end
            local M = IDCT_M
            for y=0,7 do
                local base=y*8
                local c0,c1,c2,c3,c4,c5,c6,c7 = coef[base],coef[base+1],coef[base+2],coef[base+3],coef[base+4],coef[base+5],coef[base+6],coef[base+7]
                for x=0,7 do
                    local Mx=M[x]
                    tmp[base+x]=Mx[0]*c0+Mx[1]*c1+Mx[2]*c2+Mx[3]*c3+Mx[4]*c4+Mx[5]*c5+Mx[6]*c6+Mx[7]*c7
                end
            end
            for x=0,7 do
                local t0,t1,t2,t3,t4,t5,t6,t7 = tmp[x],tmp[8+x],tmp[16+x],tmp[24+x],tmp[32+x],tmp[40+x],tmp[48+x],tmp[56+x]
                for y=0,7 do
                    local My=M[y]
                    local val = My[0]*t0+My[1]*t1+My[2]*t2+My[3]*t3+My[4]*t4+My[5]*t5+My[6]*t6+My[7]*t7 + 128
                    if val<0 then val=0 elseif val>255 then val=255 end
                    buffer.writeu8(plane,(oy+y)*pw+(ox+x),val)
                end
            end
            coef[0] = 0
            for i=1,dirtyN do coef[dirty[i]] = 0 end
            return true
        end
        local mcuCount = 0
        local aborted = false
        for my=0,mcusY-1 do
            for mx=0,mcusX-1 do
                if restartInterval>0 and mcuCount>0 and (mcuCount%restartInterval)==0 then
                    consumeRestart()
                    for _,c in ipairs(components) do c.pred=0 end
                end
                for _,c in ipairs(components) do
                    for by=0,c.v-1 do
                        for bx=0,c.h-1 do
                            if not decodeBlock(c, mx*c.h+bx, my*c.v+by) then aborted=true; break end
                        end
                        if aborted then break end
                    end
                    if aborted then break end
                end
                if aborted then break end
                mcuCount = mcuCount + 1
            end
            if aborted then break end
            if _adYield and (my % 8)==0 then _adYield() end
        end
        local out = buffer.create(width*height*4)
        local rB,wB = buffer.readu8, buffer.writeu8
        local floor = math.floor
        if #components == 1 then
            local c = components[1]; local plane,pw = c.plane,c.planeW
            for y=0,height-1 do for x=0,width-1 do
                local g = rB(plane, y*pw+x); local o=(y*width+x)*4
                wB(out,o,g);wB(out,o+1,g);wB(out,o+2,g);wB(out,o+3,255)
            end
            if _adYield and (y % 48)==0 then _adYield() end
            end
        else
            local cY,cB,cR = components[1],components[2],components[3]
            local yhx,yhy = cY.h/maxH, cY.v/maxV
            local bhx,bhy = cB.h/maxH, cB.v/maxV
            local rhx,rhy = cR.h/maxH, cR.v/maxV
            local Yp,Ypw = cY.plane,cY.planeW
            local Bp,Bpw = cB.plane,cB.planeW
            local Rp,Rpw = cR.plane,cR.planeW
            for y=0,height-1 do
                local rowY,rowB,rowR = floor(y*yhy)*Ypw, floor(y*bhy)*Bpw, floor(y*rhy)*Rpw
                for x=0,width-1 do
                    local Y = rB(Yp,rowY+floor(x*yhx))
                    local Cb = rB(Bp,rowB+floor(x*bhx))-128
                    local Cr = rB(Rp,rowR+floor(x*rhx))-128
                    local r = Y+1.402*Cr
                    local g = Y-0.344136*Cb-0.714136*Cr
                    local b = Y+1.772*Cb
                    if r<0 then r=0 elseif r>255 then r=255 end
                    if g<0 then g=0 elseif g>255 then g=255 end
                    if b<0 then b=0 elseif b>255 then b=255 end
                    local o=(y*width+x)*4
                    wB(out,o,r);wB(out,o+1,g);wB(out,o+2,b);wB(out,o+3,255)
                end
                if _adYield and (y % 32)==0 then _adYield() end
            end
        end
        return { w=width, h=height, buf=out }
    end

    -- Load an image file → { w, h, buf }. Uses the pure-Lua PNG/JPEG decoders first
    -- (dependable across executors, since getcustomasset + CreateEditableImageAsync
    -- fails on real photos on many builds); falls back to the EditableImage pipeline
    -- only for other formats. Sets _adYield during decode to avoid script timeouts.
    -- decodeImage(path, bytes):
    --   * If `bytes` is given (e.g. a freshly downloaded URL image) we decode it entirely
    --     IN MEMORY — nothing is written to the executor workspace. This is what the user
    --     wants: a pasted link should just be drawn, not saved as a file.
    --   * Otherwise we readfile(path) for a workspace file.
    -- The EditableImage fallback (used only when the pure-Lua PNG/JPEG decoders can't
    -- handle the format) does need a file on disk for getcustomasset, so for the
    -- in-memory case we write a short-lived temp with a SAFE extension and delete it
    -- immediately afterwards.
    local function decodeImage(path, bytes)
        _adYield = function() RunService.Heartbeat:Wait() end
        local cleanup = function() _adYield = nil end

        -- Obtain the raw bytes: prefer the in-memory buffer, else read the file.
        if not bytes and type(readfile) == "function" and path then
            local okR, r = pcall(readfile, path)
            if okR and type(r) == "string" then bytes = r
            else adlog("decodeImage: readfile failed (%s)", tostring(r)) end
        end

        -- 1) Pure-Lua PNG / JPEG decode straight from the byte string (no getcustomasset).
        if type(bytes) == "string" and #bytes > 8 then
            local b1, b2, b3 = bytes:byte(1), bytes:byte(2), bytes:byte(3)
            if bytes:sub(1, 8) == PNG_SIG then
                local px, perr = decodePNG(bytes)
                if px then cleanup(); adlog("decodeImage: PNG decoded %dx%d (pure-Lua)", px.w, px.h); return px end
                cleanup(); adlog("decodeImage: pure-Lua PNG failed: %s", tostring(perr))
                return nil, tostring(perr)
            elseif b1 == 0xFF and b2 == 0xD8 then
                local px, jerr = decodeJPEG(bytes)
                if px then cleanup(); adlog("decodeImage: JPEG decoded %dx%d (pure-Lua)", px.w, px.h); return px end
                cleanup(); adlog("decodeImage: pure-Lua JPEG failed: %s", tostring(jerr))
                return nil, tostring(jerr)
            else
                adlog("decodeImage: unknown format (magic %d,%d,%d) — trying EditableImage",
                    b1 or 0, b2 or 0, b3 or 0)
            end
        end

        -- 2) EditableImage fallback — needs a file on disk. If we only have bytes,
        -- write a temp file with a safe extension, then delete it once loaded.
        local loadPath, tempPath = path, nil
        if not loadPath and bytes and type(writefile) == "function" then
            tempPath = "syllinse_autodraw_temp.png"  -- fixed SAFE ext (never a URL-derived one)
            local wok = pcall(writefile, tempPath, bytes)
            if wok then loadPath = tempPath
            else cleanup(); return nil, "could not stage image for decoding" end
        end
        if not loadPath then cleanup(); return nil, "no readfile/writefile to load this image format" end

        local img, err = loadEditableImage(loadPath)
        if tempPath and type(delfile) == "function" then pcall(delfile, tempPath) end
        if not img then cleanup(); return nil, err end
        local px = readPixels(img)
        pcall(function() img:Destroy() end)
        cleanup()
        if not px then return nil, "could not read image pixels" end
        adlog("decodeImage: %dx%d via EditableImage", px.w, px.h)
        return px
    end

    local _drawing = false
    local _drawToken = 0

    local function stopAutoDraw()
        _drawing = false
        _drawToken = _drawToken + 1
        clearPreview()
    end

    -- The game always draws chalk at brush radius 2 (WhiteboardServiceClient:406
    -- hardcodes it), so the server expects that value �� we send exactly 2 and let
    -- Detail (row count) control how finely the image is reproduced.
    local BRUSH = 2
    local MAX_STROKES = 60000   -- safety cap against pathological (noisy) images

    -- opts: { path, detail, speed, threshold, skipbg, mono, preserve }, notify(title,body)
    local function runDraw(board, opts, notify)
        _fireErrLogged = false
        adlog("runDraw: start boardId=%s path='%s' bytes=%s quality=%d speed=%d",
            tostring(board.id), tostring(opts.path), opts.bytes and #opts.bytes or "nil",
            opts.quality or 60, opts.speed or 45)
        local px, err = decodeImage(opts.path, opts.bytes)
        if not px then _drawing = false; adlog("runDraw: image load FAILED: %s", tostring(err)); notify("Auto Draw", tostring(err)); return end

        local token = _drawToken
        local iw, ih = px.w, px.h
        adlog("runDraw: image %dx%d, pixels read via %s", iw, ih, px.buf and "buffer" or "array")

        -- Fit the image onto the board, preserving aspect if requested, then apply
        -- the user's scale / alignment so the drawing can cover only part of the board.
        local u0, v0, u1v, v1v = computeRegion(opts.preserve, iw, ih, opts.scale, opts.alignx, opts.aligny)
        local drawW, drawH = (u1v - u0) * BOARD_W, (v1v - v0) * BOARD_H
        local offX, offY = u0 * BOARD_W, v0 * BOARD_H
        adlog("runDraw: region uv[%.3f,%.3f]-[%.3f,%.3f] (%.0fx%.0f px)", u0, v0, u1v, v1v, drawW, drawH)

        -- Show the board/region outline while drawing ONLY if the Preview toggle is on.
        -- (Previously this always fired, so the overlay appeared on Draw even with
        -- Preview off.)
        if Config.AutoDraw.Preview then
            showPreview(board, u0, v0, u1v, v1v, nil)
        end

        -- ── Quality → concrete knobs ────────────────────────────────────────
        -- A single 1-100 dial drives BOTH how many scanlines we lay down (spatial
        -- detail) and how finely colour is quantised (tonal fidelity). The brush is
        -- 4px thick, so ~96 rows already fully cover the 384px canvas; we scale rows
        -- from a sketchy 48 up to a dense 240 (oversampled = crisp). Colour buckets
        -- shrink from very coarse (72) to near-lossless (6) so high quality removes
        -- the banding the old fixed qstep=40 produced.
        local q = math.clamp(math.floor(opts.quality or 60), 1, 100)
        local qf = (q - 1) / 99
        -- Spatial detail is tied to ACTUAL pixel size on the board, not a fixed row
        -- count. The chalk brush has radius 2 (⌀4px), so scanlines spaced ~2px already
        -- overlap and fully cover the canvas — spacing tighter than that is pure
        -- redundant work (the old "up to 384 rows" oversampled a 384px board 2-3x,
        -- which is a big chunk of why it drew so slowly). Spacing goes 4px (q=1, fast
        -- sketch) → 1.5px (q=100, crisp). Because it scales with drawH/drawW, drawing
        -- into a small (scaled-down) region also does proportionally less work.
        local spacing = 4.0 - qf * 2.5                   -- px between scanlines / cells
        local rows    = math.clamp(math.floor(drawH / spacing + 0.5), 8, 384)
        local cols    = math.clamp(math.floor(drawW / spacing + 0.5), 8, 512)
        local rowStep = drawH / rows
        local colStep = drawW / cols

        -- Colour quantisation buckets. This ONLY exists to merge truly-flat regions
        -- into longer runs (fewer strokes); it must NOT posterise the photo. The old
        -- code used huge buckets (qstep 32 at default quality → 8 levels/channel),
        -- which is exactly the banded, washed-out "old phone" look. Now buckets are
        -- small: qstep 12 (q=1) down to 1 (q=100, lossless). And quant() ROUNDS and
        -- clamps so the top bucket reaches a true 255 — the previous floor()+half
        -- capped whites at ~240, killing highlights and glare. Default quality gives
        -- ~50+ levels/channel, so smooth gradients stay smooth.
        local qstep = math.max(1, math.floor(12 - qf * 11 + 0.5))
        local function quant(v)
            if qstep <= 1 then
                local iv = math.floor(v + 0.5)
                return iv < 0 and 0 or (iv > 255 and 255 or iv)
            end
            local qb = math.floor(v / qstep + 0.5) * qstep
            if qb > 255 then qb = 255 elseif qb < 0 then qb = 0 end
            return qb
        end
        local monoR, monoG, monoB = b8(CHALK_COLOR.R * 255), b8(CHALK_COLOR.G * 255), b8(CHALK_COLOR.B * 255)

        -- Proper AREA-AVERAGE downscaler. The old sampler took at most a 3x3 grid of
        -- nearest pixels per cell, so when a big photo was squeezed onto the board most
        -- source pixels were never looked at — small highlights/specular dots simply
        -- vanished ("some pixels not seen"). Here we average EVERY source pixel in the
        -- cell footprint (capped at a generous grid that still SPANS the whole cell, so
        -- nothing between sample points is skipped). This is the correct box filter for
        -- downscaling and preserves bright detail as a proper average instead of luck.
        local srcCellW = (drawW > 0) and (iw / cols) or 1
        local srcCellH = (drawH > 0) and (ih / rows) or 1
        local aaCap = 4 + math.floor(qf * 8 + 0.5)        -- 4..12 samples per axis, spanning the cell
        local function sampleCell(cx, cy)
            local x0 = math.floor(cx * srcCellW)
            local y0 = math.floor(cy * srcCellH)
            local x1 = math.max(x0, math.floor((cx + 1) * srcCellW) - 1)
            local y1 = math.max(y0, math.floor((cy + 1) * srcCellH) - 1)
            local fw, fh = x1 - x0 + 1, y1 - y0 + 1
            local nx = math.min(aaCap, fw)
            local ny = math.min(aaCap, fh)
            local sr, sg, sb, n = 0, 0, 0, 0
            for sy = 0, ny - 1 do
                local iy = (ny == 1) and y0 or (y0 + math.floor((sy + 0.5) * fh / ny))
                for sx = 0, nx - 1 do
                    local ix = (nx == 1) and x0 or (x0 + math.floor((sx + 0.5) * fw / nx))
                    local pr, pg, pb = samplePix(px, ix, iy)
                    sr = sr + pr; sg = sg + pg; sb = sb + pb; n = n + 1
                end
            end
            if n == 0 then return 0, 0, 0 end
            return sr / n, sg / n, sb / n
        end

        -- ── Phase 1: rasterise into a flat stroke list (fast; occasional yield) ──
        -- Each stroke is a horizontal same-colour run: {r,g,b,u1,u2,v}.
        local strokes = {}
        local capped = false
        for r = 0, rows - 1 do
            if token ~= _drawToken then break end
            local py = offY + (r + 0.5) * rowStep
            local v  = py / BOARD_H

            local runActive, rr, rg, rb, runU1, runU2 = false, 0, 0, 0, 0, 0
            local function flush()
                if runActive then
                    strokes[#strokes + 1] = { r = rr, g = rg, b = rb, u1 = runU1, u2 = runU2, v = v, row = r }
                    runActive = false
                end
            end

            for c = 0, cols - 1 do
                local pxx = offX + (c + 0.5) * colStep
                local sr, sg, sb = sampleCell(c, r)
                local bright = 0.299 * sr + 0.587 * sg + 0.114 * sb
                if opts.skipbg and bright < opts.threshold then
                    flush()
                else
                    local cr, cg, cb
                    if opts.mono then cr, cg, cb = monoR, monoG, monoB
                    else cr, cg, cb = quant(sr), quant(sg), quant(sb) end
                    if runActive and cr == rr and cg == rg and cb == rb then
                        runU2 = pxx / BOARD_W               -- extend current run
                    else
                        flush()
                        runActive, rr, rg, rb = true, cr, cg, cb
                        runU1 = pxx / BOARD_W
                        runU2 = runU1
                    end
                end
            end
            flush()

            if #strokes >= MAX_STROKES then capped = true; break end
            if (r % 8) == 0 then RunService.Heartbeat:Wait() end   -- keep frame alive
        end

        local total = #strokes
        adlog("runDraw: rasterised %d strokes (rows=%d cols=%d capped=%s)", total, rows, cols, tostring(capped))
        if token ~= _drawToken then _drawing = false; adlog("runDraw: cancelled after rasterise"); return end
        if total == 0 then
            _drawing = false
            adlog("runDraw: 0 strokes — everything skipped (SkipBg=%s Threshold=%s)", tostring(opts.skipbg), tostring(opts.threshold))
            notify("Auto Draw", "nothing to draw (try lowering Skip Threshold)"); return
        end
        if opts.skipbg then
            adlog("runDraw: first stroke sample rgb=(%d,%d,%d) at v=%.3f", strokes[1].r, strokes[1].g, strokes[1].b, strokes[1].v)
        end

        -- ── Phase 1b: chain runs into POLYLINES (compression) ───────────────
        -- A single horizontal run is only 2 points, but the game's draw unit is a
        -- connected polyline of up to 24 points, and applyDrawBuffer connects
        -- consecutive points. So we SNAKE-chain vertically-adjacent runs of the SAME
        -- colour whose x-ranges overlap: the connector between them stays inside the
        -- filled region (correct fill, no stray lines), and a solid area that used to
        -- cost dozens of packets collapses into a handful of 24-point polylines.
        -- This is the "compression" — it slashes both packets and draw calls.
        local COLOR = function(s) return s.r * 65536 + s.g * 256 + s.b end
        local byColor = {}
        for _, s in ipairs(strokes) do
            local key = COLOR(s)
            local c = byColor[key]
            if not c then c = { rows = {}, order = {} }; byColor[key] = c end
            local rl = c.rows[s.row]; if not rl then rl = {}; c.rows[s.row] = rl end
            rl[#rl + 1] = s
            c.order[#c.order + 1] = s
        end
        -- deterministic start order: top-to-bottom, then left-to-right
        for _, c in pairs(byColor) do
            table.sort(c.order, function(a, b)
                if a.row ~= b.row then return a.row < b.row end
                return a.u1 < b.u1
            end)
        end

        local batches = {}
        for _, c in pairs(byColor) do
            if token ~= _drawToken then break end
            for _, seed in ipairs(c.order) do
                if not seed.used then
                    local pts = { { x = seed.u1, y = seed.v }, { x = seed.u2, y = seed.v } }
                    seed.used = true
                    local cur, endedRight = seed, true
                    while #pts <= 22 do
                        local nrow = c.rows[cur.row + 1]
                        local px = endedRight and cur.u2 or cur.u1
                        local best, bestd
                        if nrow then
                            for _, cand in ipairs(nrow) do
                                if not cand.used and cand.u2 >= cur.u1 and cand.u1 <= cur.u2 then
                                    local d = math.min(math.abs(cand.u1 - px), math.abs(cand.u2 - px))
                                    if not bestd or d < bestd then best, bestd = cand, d end
                                end
                            end
                        end
                        if not best then break end
                        if math.abs(best.u1 - px) <= math.abs(best.u2 - px) then
                            pts[#pts + 1] = { x = best.u1, y = best.v }
                            pts[#pts + 1] = { x = best.u2, y = best.v }
                            endedRight = true
                        else
                            pts[#pts + 1] = { x = best.u2, y = best.v }
                            pts[#pts + 1] = { x = best.u1, y = best.v }
                            endedRight = false
                        end
                        best.used = true
                        cur = best
                    end
                    batches[#batches + 1] = { r = seed.r, g = seed.g, b = seed.b, pts = pts }
                end
            end
        end
        local nbatch = #batches
        adlog("runDraw: %d runs → %d polyline batches", total, nbatch)

        -- ── Phase 2: draw the batches PROGRESSIVELY ─────────────────────────
        -- Each batch is rendered locally AND fired to the server together, through the
        -- SAME polyline path the game uses for broadcasts (drawBatch). So the picture
        -- builds up the same way everyone else sees it — not "all at once" with a
        -- separate local look. Pacing is by POINTS/second (opts.speed): the unreliable
        -- WhiteboardDrawBatch remote drops packets if flooded, but because each packet
        -- now carries up to 23 segments we send far fewer packets for the same paint
        -- rate, so it finishes much faster and cleaner than the old 1-segment-per-fire.
        local sync     = opts.sync
        local sent, rendered = 0, false
        local perSec   = math.clamp(math.floor(opts.speed or 400), 30, 4000)
        local burstCap = math.max(24, math.floor(perSec * 0.15))
        local budget, last = 0, os.clock()
        for bi = 1, nbatch do
            if token ~= _drawToken then break end
            local batch = batches[bi]
            local cost = #batch.pts
            while budget < cost do
                RunService.Heartbeat:Wait()
                if token ~= _drawToken then break end
                local now = os.clock()
                budget = math.min(burstCap, budget + (now - last) * perSec)
                last = now
            end
            if token ~= _drawToken then break end
            budget = budget - cost
            local rok, fok = drawBatch(board, batch.r, batch.g, batch.b, batch.pts, sync)
            if rok then rendered = true end
            if fok then sent = sent + 1 end
        end

        _drawing = false
        adlog("runDraw: DONE local=%s firedPackets=%d/%d (fireErr=%s)", tostring(rendered), sent, nbatch, tostring(_fireErrLogged))
        if token == _drawToken then
            if not rendered then
                notify("Auto Draw", "could not access the board image (local render failed) — see debug log")
            elseif sync then
                notify("Auto Draw", ("done — %d runs in %d packets synced%s"):format(total, sent, capped and " (detail capped)" or ""))
            else
                notify("Auto Draw", ("done — %d runs (local only)%s"):format(total, capped and " (detail capped)" or ""))
            end
        end
    end

    -- Resolve the image source (file or URL), then kick off the draw coroutine.
    local function startAutoDraw(notify)
        if _drawing then notify("Auto Draw", "already drawing — press Stop first"); return end

        -- Only the server-sync path needs the remote; local-only drawing does not.
        if Config.AutoDraw.Sync then
            local net = getNet()
            if not net or not net.WhiteboardDrawBatch then
                notify("Auto Draw", "whiteboard network remote unavailable (turn off Sync to draw locally)"); return
            end
        end

        local board, dist = findNearestBoard()
        if not board then notify("Auto Draw", "no whiteboard found — stand near one"); return end
        -- The server itself only accepts draws within ~16 studs (WhiteboardServiceClient
        -- isNearBoard), so require ≤15 before we even start — otherwise every stroke is
        -- silently rejected and nothing appears for other players.
        if dist and dist > 15 then
            notify("Auto Draw", ("too far from the whiteboard (%.0f studs) — move within 15"):format(dist))
            return
        end

        local ad = Config.AutoDraw
        local path, imgBytes

        -- Decide which source to use. Previously the Workspace File was ALWAYS checked
        -- first, so a leftover dropdown selection silently overrode a freshly pasted URL
        -- (the reported bug: "loaded the old workspace file instead of my link"). Now we
        -- honour whichever input the user edited most recently (ad.Source), and only fall
        -- back to "any valid source" when that is unset.
        local urlOk  = ad.Url and ad.Url:match("^https?://") ~= nil
        local fileOk = ad.File and ad.File ~= "" and not ad.File:match("^%(")
        local useUrl
        if ad.Source == "url" and urlOk then
            useUrl = true
        elseif ad.Source == "file" and fileOk then
            useUrl = false
        elseif urlOk then           -- no clear intent: prefer an explicit URL
            useUrl = true
        elseif fileOk then
            useUrl = false
        else
            notify("Auto Draw", "select a workspace file or paste an image URL first"); return
        end

        if not useUrl then
            path = ad.File
            if type(isfile) == "function" and not isfile(path) then
                notify("Auto Draw", "file not found: " .. path); return
            end
        else
            -- Download the image straight into memory and draw from there — we do NOT
            -- save anything to the executor workspace (the user asked for this, and it
            -- also sidesteps the old "invalid file path" bug: the previous code derived
            -- the file extension from the URL with a regex that matched ".com" in
            -- "discordapp.com", producing a blocked ".com" file that writefile rejected).
            --
            -- httpget() is the UNC-standard binary-safe HTTP getter; request()/http_request
            -- can truncate binary bodies at null bytes on some builds, so they are last.
            local dlOk = pcall(function()
                if type(httpget) == "function" then
                    imgBytes = httpget(ad.Url)
                elseif type(http_request) == "function" then
                    local res = http_request({ Url = ad.Url, Method = "GET" })
                    imgBytes = res and res.Body
                elseif type(request) == "function" then
                    local res = request({ Url = ad.Url, Method = "GET" })
                    imgBytes = res and res.Body
                end
            end)
            if not dlOk or type(imgBytes) ~= "string" or #imgBytes == 0 then
                notify("Auto Draw", "download failed — check the URL and that HTTP is enabled"); return
            end
        end

        _drawToken = _drawToken + 1
        _drawing = true
        notify("Auto Draw", "drawing… press Stop to cancel")

        -- Server replication requires an equipped chalk (server-side gate). If the
        -- user wants Sync but no chalk is out, warn and fall back to a local-only
        -- render so they still see the image instead of getting nothing.
        local syncWanted = ad.Sync
        if syncWanted and not hasChalkEquipped() then
            notify("Auto Draw", "equip any chalk for it to replicate — drawing locally only for now")
            syncWanted = false
        end

        local opts = {
            path = path, bytes = imgBytes, quality = ad.Quality, speed = ad.Speed, threshold = ad.Threshold,
            skipbg = ad.SkipBg, mono = ad.Mono, preserve = ad.Preserve, sync = syncWanted,
            scale = (ad.Scale or 100) / 100, alignx = (ad.AlignX or 50) / 100, aligny = (ad.AlignY or 50) / 100,
        }
        task.spawn(function()
            local ok, err = pcall(runDraw, board, opts, notify)
            if not ok then _drawing = false; adlog("runDraw: pcall ERROR: %s", tostring(err)); notify("Auto Draw", "error: " .. tostring(err)) end
        end)
    end

    -- Preview WITHOUT drawing: highlight the nearest board and outline the region the
    -- image will occupy. If a workspace file is set we load it briefly to get the
    -- exact aspect-ratio letterbox; otherwise we outline the whole board.
    local function previewBoard(notify, persist)
        local board, dist = findNearestBoard()
        if not board then notify("Auto Draw", "no whiteboard found — stand near one"); return end
        adlog("preview: boardId=%s dist=%s part='%s' face=%s size=%s",
            tostring(board.id), dist and string.format("%.1f", dist) or "?",
            board.part:GetFullName(), tostring(boardFace(board.part)), tostring(board.part.Size))

        local ad = Config.AutoDraw
        local iw, ih
        if ad.File and ad.File ~= "" and not ad.File:match("^%(")
           and type(isfile) == "function" and isfile(ad.File)
           and type(readfile) == "function" then
            -- Cheap: read just the PNG IHDR (bytes 17-24) for width/height.
            local okR, bytes = pcall(readfile, ad.File)
            if okR and type(bytes) == "string" and #bytes >= 24 and bytes:sub(1, 8) == PNG_SIG then
                local b = string.byte
                iw = b(bytes,17)*16777216 + b(bytes,18)*65536 + b(bytes,19)*256 + b(bytes,20)
                ih = b(bytes,21)*16777216 + b(bytes,22)*65536 + b(bytes,23)*256 + b(bytes,24)
            end
        end

        local u0, v0, u1v, v1v = computeRegion(ad.Preserve, iw, ih,
            (ad.Scale or 100) / 100, (ad.AlignX or 50) / 100, (ad.AlignY or 50) / 100)
        -- persist == true (toggle-driven) keeps the overlay up until toggled off;
        -- otherwise it auto-clears after 12s (one-shot button behaviour).
        showPreview(board, u0, v0, u1v, v1v, persist and nil or 12)
        notify("Auto Draw", ("preview: board #%s at %.0f studs%s")
            :format(tostring(board.id), dist or 0, iw and (" ("..iw.."x"..ih..")") or ""))
    end

    -- Diagnostic: draw a big white "X" + border on the nearest board. It renders
    -- LOCALLY (so you see it immediately) and, when Sync is on, also fires the remote.
    -- If the X shows up, the draw path works and any Draw failure is purely image
    -- loading. If it does NOT show up, the board map / EditableImage access failed.
    local function testStroke(notify)
        local board, dist = findNearestBoard()
        if not board then notify("Auto Draw", "no whiteboard found — stand near one"); return end
        local W = b8(CHALK_COLOR.R * 255)
        local id = board.id
        local sync = Config.AutoDraw.Sync
        adlog("testStroke: drawing X on boardId=%s dist=%.1f sync=%s", tostring(id), dist or -1, tostring(sync))
        -- Two diagonals + a rectangle border, all as connected 2-point strokes.
        local shown = false
        shown = drawStroke(board, 2, W, W, W, 0.05, 0.05, 0.95, 0.95, sync) or shown
        drawStroke(board, 2, W, W, W, 0.95, 0.05, 0.05, 0.95, sync)
        drawStroke(board, 2, W, W, W, 0.05, 0.05, 0.95, 0.05, sync)
        drawStroke(board, 2, W, W, W, 0.95, 0.05, 0.95, 0.95, sync)
        drawStroke(board, 2, W, W, W, 0.95, 0.95, 0.05, 0.95, sync)
        drawStroke(board, 2, W, W, W, 0.05, 0.95, 0.05, 0.05, sync)
        showPreview(board, 0, 0, 1, 1, 8)
        if shown then
            notify("Auto Draw", ("test X drawn on board #%s (%.0f studs)"):format(tostring(id), dist or 0))
        else
            notify("Auto Draw", "could not access the board image (local render failed) — see debug log")
        end
    end

    -- List image files in the executor workspace root (for the file dropdown).
    local IMG_EXT = { png = true, jpg = true, jpeg = true, jfif = true, jpe = true }
    local function scanImageFiles()
        local out = {}
        if type(listfiles) ~= "function" then return out end
        local ok, files = pcall(listfiles, "")
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local ext = tostring(f):match("%.([%w]+)$")
                if ext and IMG_EXT[ext:lower()] then table.insert(out, f) end
            end
        end
        return out
    end

    -- ═══════════════════════════ CHALK SPAMMER ══════════════════════════════
    -- Endlessly takes chalk from the NEAREST chalk box and drops it, littering the
    -- floor. The naive "fire a request every N seconds" approach caused the game's
    -- own "Something went wrong" popup: the auth tokens (Token/Check/Nonce) form a
    -- ROLLING SEQUENCE per key, and the game only ever has ONE dispense request in
    -- flight (_pendingRequest guard, DispenserServiceClient:72-101) — it waits for
    -- Client.DispenserResult before sending the next. Spamming requests interleaves
    -- nonces out of order, so the server rejects them.
    --
    -- Fix: we DRIVE THE GAME'S OWN dispenser singleton — call its :_requestDispense
    -- directly so we inherit its exact token flow, its single-in-flight guard and
    -- its result handling. We pace purely on its _pendingRequest flag (never fire
    -- while a request is outstanding), which eliminates the nonce races entirely.
    --   • take:  disp:_requestDispense(<nearestBoxName>, <colorKey>)
    --   • drop:  Remotes.ItemUnequip:FireServer(Token/Check/Nonce) — auth via
    --            AuthServiceClient:NextForKey("Item.Unequip"). Drops into workspace.Items.
    -- Both the auth client and the dispenser client are DESTROYED from the tree
    -- after load (anti-tamper), so we resolve them from memory (getloadedmodules).
    -- You must still be standing next to a chalk box (the server checks proximity).
    local CHALK_COLORS = { "White", "Red", "Orange", "Yellow", "Green", "Blue", "Indigo", "Violet" }
    -- item     : the item type used on the last take ("chalk" | "eraser") — Alternate flips off this
    -- cool     : os.clock() until which a type is rate-limited (set when a request is rejected)
    -- pendType : the item type of a take we fired but haven't seen resolve yet
    -- pendAt   : when that take was fired (for a timeout safeguard)
    local ChalkState = { conn = nil, idx = 0, nextAt = 0, item = "chalk",
        cool = { chalk = 0, eraser = 0 }, pendType = nil, pendAt = 0 }

    -- A valid AuthServiceClient is any table exposing a NextForKey function.
    local function authIsValid(v)
        return type(v) == "table" and type(rawget(v, "NextForKey") or v.NextForKey) == "function"
    end

    -- The game DESTROYS the AuthServiceClient ModuleScript after requiring it
    -- (anti-tamper), so it is gone from the normal tree — that's why the plain
    -- FindFirstChild path returned "unavailable". It still lives in memory, so we
    -- resolve it through executor globals, trying the cheapest paths first:
    --   1) normal tree require (works if not yet destroyed)
    --   2) getloadedmodules() — every loaded ModuleScript, incl. destroyed ones
    --   3) getnilinstances() — instances parented to nil (destroyed)
    --   4) filtergc/getgc — grab the returned table directly by its NextForKey key
    local _authClient
    local function chalkAuth()
        if _authClient ~= nil then return _authClient or nil end
        local G = (getgenv and getgenv()) or _G

        -- 1) Normal require via the tree.
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            local svc    = shared and shared:FindFirstChild("Services")
            local auth   = svc and svc:FindFirstChild("AuthService")
            local client = auth and auth:FindFirstChild("AuthServiceClient")
            if client then
                local mod = require(client)
                if authIsValid(mod) then _authClient = mod end
            end
        end)

        -- 2) getloadedmodules(): find the (possibly destroyed) ModuleScript and
        --    re-require it — require is cached per instance, so this returns the
        --    same live table the game uses.
        if not _authClient and type(G.getloadedmodules) == "function" then
            pcall(function()
                for _, m in ipairs(G.getloadedmodules()) do
                    if m and m.Name == "AuthServiceClient" then
                        local mod = require(m)
                        if authIsValid(mod) then _authClient = mod break end
                    end
                end
            end)
        end

        -- 3) getnilinstances(): destroyed modules are parented to nil.
        if not _authClient and type(G.getnilinstances) == "function" then
            pcall(function()
                for _, inst in ipairs(G.getnilinstances()) do
                    if inst and inst.ClassName == "ModuleScript" and inst.Name == "AuthServiceClient" then
                        local mod = require(inst)
                        if authIsValid(mod) then _authClient = mod break end
                    end
                end
            end)
        end

        -- 4) filtergc / getgc: pull the returned auth table straight out of the GC
        --    by matching its NextForKey key (bypasses the ModuleScript entirely).
        if not _authClient and type(G.filtergc) == "function" then
            pcall(function()
                local t = G.filtergc("table", { Keys = { "NextForKey" } }, true)
                if authIsValid(t) then _authClient = t end
            end)
        end
        if not _authClient and type(G.getgc) == "function" then
            pcall(function()
                for _, obj in ipairs(G.getgc(true)) do
                    if authIsValid(obj) then _authClient = obj break end
                end
            end)
        end

        _authClient = _authClient or false
        return _authClient or nil
    end

    local function chalkCharAttr(name)
        local char = LocalPlayer and LocalPlayer.Character
        return char and char:GetAttribute(name)
    end

    -- Pick the next color per the chosen mode (Rainbow cycles, Random rolls, else a
    -- fixed color key stored in Config.Chalk.Mode).
    local function chalkNextColor()
        local mode = Config.Chalk.Mode or "Rainbow"
        if mode == "Rainbow" then
            ChalkState.idx = (ChalkState.idx % #CHALK_COLORS) + 1
            return CHALK_COLORS[ChalkState.idx]
        elseif mode == "Random" then
            return CHALK_COLORS[math.random(1, #CHALK_COLORS)]
        end
        return mode  -- a specific color key
    end

    -- Each action returns (ok, reason) so the UI can report the ACTUAL failure
    -- point instead of a vague "failed". reason is nil on success. Fallback path
    -- used only when the game's dispenser singleton can't be resolved.
    local function chalkRequestRaw(dispName, optionKey)
        local net = getNet()
        if not net then return false, "network Client unavailable" end
        if not net.DispenserRequest then return false, "DispenserRequest remote missing" end
        local auth = chalkAuth()
        if not auth then return false, "AuthServiceClient unavailable" end
        local token, check, nonce = auth:NextForKey("Dispenser.Request")
        if nonce == 0 then return false, "auth returned no token (rate limited?)" end
        local ok, err = pcall(function()
            net.DispenserRequest.Fire({
                DispenserName = dispName,
                OptionKey     = optionKey,
                Token         = token,
                Check         = check,
                Nonce         = nonce,
            })
        end)
        if not ok then return false, "Fire error: " .. tostring(err) end
        return true
    end

    local function chalkDrop()
        local auth = chalkAuth()
        if not auth then return false, "AuthServiceClient unavailable" end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local unequip = remotes and remotes:FindFirstChild("ItemUnequip")
        if not remotes then return false, "Remotes folder missing" end
        if not (unequip and unequip:IsA("RemoteEvent")) then return false, "ItemUnequip remote missing" end
        local token, check, nonce = auth:NextForKey("Item.Unequip")
        if nonce == 0 then return false, "auth returned no token (rate limited?)" end
        local ok, err = pcall(function() unequip:FireServer(token, check, nonce) end)
        if not ok then return false, "FireServer error: " .. tostring(err) end
        return true
    end

    -- The dispenser SINGLETON instance (not the metatable) exposes _requestDispense
    -- (via __index) and owns a _pendingRequest field. Match both so getgc can't hand
    -- us the metatable by mistake (which would take a wrong `self`).
    local function dispIsValid(v)
        return type(v) == "table"
            and type(v._requestDispense) == "function"
            and rawget(v, "_pendingRequest") ~= nil
    end

    -- Resolve the game's DispenserServiceClient singleton from memory (same reasons
    -- as chalkAuth: the ModuleScript is destroyed from the tree after load).
    local _dispClient
    local function chalkDispenser()
        if _dispClient ~= nil then return _dispClient or nil end
        local G = (getgenv and getgenv()) or _G
        pcall(function()
            local shared = ReplicatedStorage:FindFirstChild("Shared")
            local svc    = shared and shared:FindFirstChild("Services")
            local ds     = svc and svc:FindFirstChild("DispenserService")
            local client = ds and ds:FindFirstChild("DispenserServiceClient")
            if client then
                local mod = require(client)
                if dispIsValid(mod) then _dispClient = mod end
            end
        end)
        if not _dispClient and type(G.getloadedmodules) == "function" then
            pcall(function()
                for _, m in ipairs(G.getloadedmodules()) do
                    if m and m.Name == "DispenserServiceClient" then
                        local mod = require(m)
                        if dispIsValid(mod) then _dispClient = mod break end
                    end
                end
            end)
        end
        if not _dispClient and type(G.getgc) == "function" then
            pcall(function()
                for _, obj in ipairs(G.getgc(true)) do
                    if dispIsValid(obj) then _dispClient = obj break end
                end
            end)
        end
        _dispClient = _dispClient or false
        return _dispClient or nil
    end

    -- Find the NEAREST dispenser under workspace.Dispensers whose name contains the
    -- keyword ("chalk" or "eraser"). Returns (name, distance). Falls back to the
    -- canonical carton name if none is found yet.
    local function chalkNearestByKind(keyword, fallback)
        local folder = workspace:FindFirstChild("Dispensers")
        local char   = LocalPlayer and LocalPlayer.Character
        local root   = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        local origin = root and root.Position
        local bestName, bestDist = fallback, nil
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m.Name:lower():find(keyword) then
                    local d = 0
                    if origin then
                        local ok, pos = pcall(function() return m:GetPivot().Position end)
                        if ok and pos then d = (pos - origin).Magnitude end
                    end
                    if not bestDist or d < bestDist then bestName, bestDist = m.Name, d end
                end
            end
        end
        return bestName, bestDist
    end

    -- Take one item of the given type ("chalk" | "eraser"). Chalk uses a colour
    -- OptionKey (ColorWheel dispenser); eraser/sponge is a Direct dispenser and uses
    -- the fixed "default" OptionKey (DispenserCatalog + DispenserServiceClient:124).
    -- Prefer driving the game's own singleton (correct rolling-token flow +
    -- single-in-flight guard); fall back to a manual request if it can't be resolved.
    local function chalkTake(itemType)
        local name, optionKey
        if itemType == "eraser" then
            name = chalkNearestByKind("eraser", "EraserCarton")
            optionKey = "default"
        else
            name = chalkNearestByKind("chalk", "ChalkCarton")
            optionKey = chalkNextColor()
        end
        local disp = chalkDispenser()
        if disp then
            if rawget(disp, "_pendingRequest") == true then
                return false, "waiting for previous request"
            end
            local ok, err = pcall(function() disp:_requestDispense(name, optionKey) end)
            if not ok then return false, "request error: " .. tostring(err) end
            return true
        end
        return chalkRequestRaw(name, optionKey)
    end

    -- Choose which item type to take next, honouring the Items mode and per-type
    -- cooldowns. In Alternate mode we flip off the last-used type each time (so both
    -- dispensers share the load) and, when one type is rate-limited, we use the other
    -- until its cooldown expires. Returns nil if BOTH types are currently cooling down.
    local function chalkPickItem(now)
        local mode      = Config.Chalk.Items or "Alternate"
        local chalkOk   = now >= (ChalkState.cool.chalk or 0)
        local eraserOk  = now >= (ChalkState.cool.eraser or 0)
        if mode == "Chalk"  then return chalkOk  and "chalk"  or nil end
        if mode == "Sponge" then return eraserOk and "eraser" or nil end
        -- Alternate: prefer the opposite of what we used last time.
        local prefer = (ChalkState.item == "chalk") and "eraser" or "chalk"
        local other  = (prefer == "chalk") and "eraser" or "chalk"
        local function okOf(t) return (t == "chalk" and chalkOk) or (t == "eraser" and eraserOk) end
        if okOf(prefer) then return prefer end
        if okOf(other)  then return other  end
        return nil
    end

    -- One full cycle driver. Held item -> drop it; empty hands -> take an item.
    -- Pacing comes from the singleton's _pendingRequest flag (never fire mid-flight),
    -- which is what fixes the "something went wrong" nonce races. When a take is
    -- rejected (the request resolved but no item ended up in hand — i.e. a rate
    -- limit), we put that item type on cooldown so the picker switches to the other.
    local function chalkTick()
        local now      = os.clock()
        local equipped = chalkCharAttr("ItemEquipped")
        local disp     = chalkDispenser()
        local pending  = disp and rawget(disp, "_pendingRequest") == true

        -- Resolve an outstanding take before doing anything else.
        if ChalkState.pendType then
            if equipped ~= nil then
                ChalkState.pendType = nil            -- got the item: success
            elseif not pending then
                -- Server responded but our hands are empty → rejected (rate limited).
                ChalkState.cool[ChalkState.pendType] = now + math.max(0.5, Config.Chalk.Cooldown or 3)
                ChalkState.pendType = nil
            elseif now - ChalkState.pendAt > 4 then
                -- Safeguard: never wait forever on a lost result.
                ChalkState.cool[ChalkState.pendType] = now + math.max(0.5, Config.Chalk.Cooldown or 3)
                ChalkState.pendType = nil
            end
            if ChalkState.pendType then return end   -- still waiting
        end

        if now < ChalkState.nextAt then return end
        local interval = math.max(0.1, Config.Chalk.Delay or 0.35)

        if equipped ~= nil then
            if chalkDrop() then ChalkState.nextAt = now + interval end
            return
        end

        if pending then return end                   -- a request is still outstanding

        local item = chalkPickItem(now)
        if not item then                             -- both types cooling down
            ChalkState.nextAt = now + 0.25
            return
        end
        if chalkTake(item) then
            ChalkState.item     = item
            ChalkState.pendType = item
            ChalkState.pendAt   = now
            ChalkState.nextAt   = now + interval
        end
    end

    -- Manual one-shot: hold something -> drop it; empty hands -> take one item
    -- (respects the Items mode / cooldowns). Returns (ok, reason).
    local function chalkTakeAndDropOnce()
        local equipped = chalkCharAttr("ItemEquipped")
        if equipped ~= nil then return chalkDrop() end
        local item = chalkPickItem(os.clock()) or "chalk"
        ChalkState.item = item
        return chalkTake(item)
    end

    local function chalkStop()
        Config.Chalk.Auto = false
        if ChalkState.conn then ChalkState.conn:Disconnect(); ChalkState.conn = nil end
    end

    local function chalkStart()
        if ChalkState.conn then return end
        ChalkState.conn = RunService.Heartbeat:Connect(function()
            if not Config.Chalk.Auto then return end
            pcall(chalkTick)
        end)
    end

    -- ═══════════════════════════ CHESS ENGINE ══════════════════════════════
    local function squareFromName(name)
        if type(name) ~= "string" or not name:match("^[a-h][1-8]$") then return nil end
        return (tonumber(name:sub(2, 2)) - 1) * 8 + (string.byte(name, 1) - 97)
    end

    local function squareName(index)
        if type(index) ~= "number" or index % 1 ~= 0 or index < 0 or index > 63 then return nil end
        return ("abcdefgh"):sub(index % 8 + 1, index % 8 + 1) .. tostring(math.floor(index / 8) + 1)
    end

    -- Build FEN directly from the live mirror state. Do not trust mirror:fen() as the
    -- only source: the shipped Board.toFEN path can produce a syntactically valid but
    -- engine-invalid FEN after moves (the API then answers type="error").
    local function chessStateToFEN(state)
        if type(state) ~= "table" or type(state.squares) ~= "table" then return nil end
        local ranks = {}
        for rank = 7, 0, -1 do
            local row, empty = "", 0
            for file = 0, 7 do
                local piece = state.squares[rank * 8 + file]
                if piece == nil then
                    empty = empty + 1
                elseif type(piece) == "string" and piece:match("^[prnbqkPRNBQK]$") then
                    if empty > 0 then row = row .. tostring(empty); empty = 0 end
                    row = row .. piece
                else
                    return nil
                end
            end
            if empty > 0 then row = row .. tostring(empty) end
            ranks[#ranks + 1] = row
        end
        local rights = type(state.castling) == "table" and state.castling or {}
        local castling = ""
        if rights.wk then castling = castling .. "K" end
        if rights.wq then castling = castling .. "Q" end
        if rights.bk then castling = castling .. "k" end
        if rights.bq then castling = castling .. "q" end
        if castling == "" then castling = "-" end
        local side = state.side == "b" and "b" or "w"
        -- chess-api (and Stockfish) reject a FEN where the ep square is set but no
        -- enemy pawn can actually capture en passant. The game engine stores the ep
        -- transit square after every double push, even when there is no capturing pawn.
        -- We must validate it before encoding it in the FEN.
        local ep = "-"
        if state.ep ~= nil then
            local epIdx = state.ep
            local epFile = epIdx % 8
            local epRank = math.floor(epIdx / 8)
            -- The capturing pawn does NOT sit on the ep square's rank; it sits on the
            -- rank the just-moved enemy pawn landed on (one rank further from ep, in
            -- the direction that pawn just travelled). side == state.side (side to
            -- move now) tells us who moved last: if it's now black's turn, white just
            -- pushed up (landed rank = epRank + 1); if it's now white's turn, black
            -- just pushed down (landed rank = epRank - 1).
            local capturerRank = side == "b" and (epRank + 1) or (epRank - 1)
            local canCapture = false
            local capturerPiece = side == "w" and "P" or "p"
            if capturerRank >= 0 and capturerRank <= 7 then
                for _, df in ipairs({-1, 1}) do
                    local adjFile = epFile + df
                    if adjFile >= 0 and adjFile <= 7 then
                        local sq = state.squares[capturerRank * 8 + adjFile]
                        if sq == capturerPiece then canCapture = true; break end
                    end
                end
            end
            if canCapture then
                ep = squareName(epIdx) or "-"
            end
        end
        return string.format("%s %s %s %s %d %d", table.concat(ranks, "/"), side, castling, ep,
            math.max(0, math.floor(tonumber(state.halfmove) or 0)),
            math.max(1, math.floor(tonumber(state.fullmove) or 1)))
    end

    local function parseMove(value)
        if type(value) ~= "string" then return nil end
        value = value:lower():gsub("%s+", "")
        local fromName, toName, promo = value:match("^([a-h][1-8])([a-h][1-8])([qrbn]?)$")
        if not fromName then return nil end
        return {
            raw = value,
            fromName = fromName,
            toName = toName,
            from = squareFromName(fromName),
            to = squareFromName(toName),
            promo = promo ~= "" and promo or nil,
        }
    end

    local function validFEN(fen)
        if type(fen) ~= "string" then return false end
        local fields = {}
        for field in fen:gmatch("%S+") do fields[#fields + 1] = field end
        if #fields ~= 6 then return false end

        local ranks = {}
        for rank in fields[1]:gmatch("[^/]+") do ranks[#ranks + 1] = rank end
        if #ranks ~= 8 then return false end
        for _, rank in ipairs(ranks) do
            local width = 0
            for ch in rank:gmatch(".") do
                local digit = tonumber(ch)
                if digit then
                    if digit < 1 or digit > 8 then return false end
                    width = width + digit
                elseif ch:match("[prnbqkPRNBQK]") then
                    width = width + 1
                else
                    return false
                end
            end
            if width ~= 8 then return false end
        end

        if fields[2] ~= "w" and fields[2] ~= "b" then return false end
        if fields[3] ~= "-" then
            local seen = {}
            if #fields[3] > 4 then return false end
            for ch in fields[3]:gmatch(".") do
                if not ch:match("[KQkq]") or seen[ch] then return false end
                seen[ch] = true
            end
        end
        if fields[4] ~= "-" and not fields[4]:match("^[a-h][36]$") then return false end
        local halfmove, fullmove = tonumber(fields[5]), tonumber(fields[6])
        if not halfmove or halfmove < 0 or halfmove % 1 ~= 0 then return false end
        if not fullmove or fullmove < 1 or fullmove % 1 ~= 0 then return false end
        return true
    end

    local function acceptResponse(data, pending, currentDepth)
        if type(data) ~= "table" or type(pending) ~= "table" then return nil end
        if data.type ~= "move" and data.type ~= "bestmove" then return nil end
        if data.fen ~= pending.fen then return nil end
        -- chess-api currently IGNORES a caller-supplied taskId and assigns its own
        -- random id (verified against the live WS endpoint). The old strict comparison
        -- rejected every single actionable packet, so no hint could ever render.
        -- Learn the server id from the first matching-FEN move, then require that id
        -- for the remaining progressive packets of this request.
        local serverTaskId = tostring(data.taskId or "")
        if pending.serverTaskId then
            if serverTaskId ~= pending.serverTaskId then return nil end
        elseif serverTaskId ~= "" then
            pending.serverTaskId = serverTaskId
        end
        local move = parseMove(data.move or data.lan)
        if not move then return nil end
        local depth = tonumber(data.depth) or 0
        if data.type ~= "bestmove" and depth < (tonumber(currentDepth) or 0) then return nil end
        return {
            move = move.raw,
            parsed = move,
            depth = depth,
            final = data.type == "bestmove",
            -- chess-api has used both `eval` (pawns) and `centipawns` across
            -- response shapes. Normalize them once for the overlay's white-centric bar.
            eval = tonumber(data.eval) or ((tonumber(data.centipawns) or 0) / 100),
            mate = tonumber(data.mate),
            san = type(data.san) == "string" and data.san or nil,
            text = type(data.text) == "string" and data.text or nil,
        }
    end

    local function pieceColor(piece)
        if type(piece) ~= "string" or #piece ~= 1 then return nil end
        return piece == piece:upper() and "w" or "b"
    end

    -- Independent fallback validator for the pawn two-square advance ("double push").
    -- The game's own Moves_ModuleScript.pseudoLegal has a confirmed decompile-shadowing
    -- bug in exactly this branch (a `v18` local is read before it is declared, then
    -- re-declared inside the `if`), which can make the live legalMovesFrom() reject or
    -- miscompute a perfectly legal double push. We do NOT reimplement the game's whole
    -- move generator (king-safety/pins for every piece stays the game's job); this is a
    -- narrow, from-scratch check using only our own already-independently-built FEN
    -- state (squares/side), scoped to the one move shape the game engine is known to
    -- mishandle. It is only ever consulted as a fallback after the primary game-engine
    -- check has already rejected the move.
    local function ownDoublePushLegal(squares, side, parsed)
        if type(squares) ~= "table" or type(parsed) ~= "table" then return false end
        if parsed.promo then return false end -- a double push can never be a promotion
        local piece = squares[parsed.from]
        if type(piece) ~= "string" or piece:lower() ~= "p" or pieceColor(piece) ~= side then return false end

        local fromFile, fromRank = parsed.from % 8, math.floor(parsed.from / 8)
        local toFile, toRank = parsed.to % 8, math.floor(parsed.to / 8)
        local dir = side == "w" and 1 or -1
        local startRank = side == "w" and 1 or 6
        if fromFile ~= toFile or fromRank ~= startRank or toRank ~= fromRank + 2 * dir then return false end

        local midSquare = (fromRank + dir) * 8 + fromFile
        if squares[midSquare] ~= nil then return false end -- path blocked
        if squares[parsed.to] ~= nil then return false end -- destination occupied
        return true
    end

    local function validateLiveMove(mirror, myColor, parsed)
        if type(mirror) ~= "table" or type(parsed) ~= "table" then return false end
        local state = rawget(mirror, "state")
        if type(state) ~= "table" or state.side ~= myColor then return false end
        local squares = rawget(state, "squares")
        if type(squares) ~= "table" or pieceColor(squares[parsed.from]) ~= myColor then return false end
        if type(mirror.legalMovesFrom) ~= "function" then return false end
        local ok, legal = pcall(mirror.legalMovesFrom, mirror, parsed.from)
        if not ok or type(legal) ~= "table" then
            -- The game's own legal-move call errored; still allow the narrow, safe
            -- double-push fallback rather than unconditionally rejecting the move.
            if ownDoublePushLegal(squares, myColor, parsed) then
                return true, "engine legalMovesFrom errored; accepted via independent double-push check"
            end
            return false
        end
        for _, move in ipairs(legal) do
            if type(move) == "table" and move.from == parsed.from and move.to == parsed.to then
                local expected = parsed.promo
                local actual = type(move.promo) == "string" and move.promo:lower() or nil
                if expected == actual or (expected == nil and actual == nil) then return true end
            end
        end
        -- legalMovesFrom did not list this move. Before rejecting, check for the one
        -- documented game-engine bug we can safely route around: a two-square pawn
        -- advance from its starting rank with both intervening squares empty.
        if ownDoublePushLegal(squares, myColor, parsed) then
            return true, "engine legalMovesFrom rejected a structurally legal double push; accepted via independent check"
        end
        return false
    end


    local State = {
        running = false,
        chess = nil,
        lastScan = 0,
        lastFen = nil,
        sentFen = nil,
        pending = nil,
        bestDepth = 0,
        ws = nil,
        wsMessageConn = nil,
        wsCloseConn = nil,
        connecting = false,
        nextConnect = 0,
        requestSeq = 0,
        folder = nil,
        hintFen = nil,
        hintMove = nil,
        loopToken = 0,
        status = "idle",
        lastError = nil,
        lastPacket = nil,
        eval = nil,
        evalMate = nil,
        overlay = nil,
        overlayFen = nil,
        overlayVisible = false,
        notify = function() end,
    }

    local PIECE_IMAGES = {
        P = "rbxassetid://12414175509", p = "rbxassetid://12446604722",
        K = "rbxassetid://12414181580", k = "rbxassetid://12446620898",
        Q = "rbxassetid://12414180706", q = "rbxassetid://12446617367",
        R = "rbxassetid://12414179583", r = "rbxassetid://12446625094",
        B = "rbxassetid://12414178467", b = "rbxassetid://12446612440",
        N = "rbxassetid://12414177497", n = "rbxassetid://12446609273",
    }

    local function destroyOverlay()
        local overlay = State.overlay
        State.overlay = nil
        State.overlayFen = nil
        State.overlayVisible = false
        if overlay and overlay.gui then pcall(function() overlay.gui:Destroy() end) end
    end

    local function setOverlayVisible(visible)
        local overlay = State.overlay
        if not overlay or State.overlayVisible == visible then return end
        State.overlayVisible = visible
        overlay.group.Visible = true
        local tween = TweenService:Create(overlay.group, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            GroupTransparency = visible and 0 or 1,
        })
        tween:Play()
        if not visible then
            task.delay(0.24, function()
                if State.overlay == overlay and not State.overlayVisible then overlay.group.Visible = false end
            end)
        end
    end

    local function makeOverlay()
        if State.overlay then return State.overlay end
        local parent = (type(gethui) == "function" and gethui()) or CoreGui
        local old = parent:FindFirstChild("SyllinseChessOverlay")
        if old then old:Destroy() end

        local gui = Instance.new("ScreenGui")
        gui.Name = "SyllinseChessOverlay"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 40
        gui.Parent = parent

        local group = Instance.new("CanvasGroup")
        group.Name = "Overlay"
        group.GroupTransparency = 1
        group.Visible = false
        group.BackgroundTransparency = 1
        group.Size = UDim2.fromOffset(300, 300)
        group.Position = UDim2.new(0, 28, 0.5, -150)
        group.Parent = gui

        local shell = Instance.new("Frame")
        shell.Size = UDim2.fromScale(1, 1)
        shell.BackgroundColor3 = Color3.fromRGB(20, 24, 31)
        shell.BackgroundTransparency = 0.08
        shell.BorderSizePixel = 0
        shell.Parent = group
        local shellCorner = Instance.new("UICorner")
        shellCorner.CornerRadius = UDim.new(0, 7)
        shellCorner.Parent = shell
        local shellStroke = Instance.new("UIStroke")
        shellStroke.Color = Color3.fromRGB(88, 169, 255)
        shellStroke.Thickness = 1
        shellStroke.Transparency = 0.3
        shellStroke.Parent = shell

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -34, 0, 20)
        title.Position = UDim2.fromOffset(25, 5)
        title.BackgroundTransparency = 1
        title.Text = "CHESS ENGINE"
        title.TextColor3 = Color3.fromRGB(210, 230, 255)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = shell

        local evalText = Instance.new("TextLabel")
        evalText.Size = UDim2.fromOffset(34, 20)
        evalText.Position = UDim2.fromOffset(258, 5)
        evalText.BackgroundTransparency = 1
        evalText.Text = "0.00"
        evalText.TextColor3 = Color3.fromRGB(235, 240, 248)
        evalText.Font = Enum.Font.GothamBold
        evalText.TextSize = 10
        evalText.TextXAlignment = Enum.TextXAlignment.Right
        evalText.Parent = shell

        local evalBar = Instance.new("Frame")
        evalBar.Size = UDim2.fromOffset(8, 248)
        evalBar.Position = UDim2.fromOffset(10, 34)
        evalBar.BackgroundColor3 = Color3.fromRGB(26, 30, 37)
        evalBar.BorderSizePixel = 0
        evalBar.Parent = shell
        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 4)
        barCorner.Parent = evalBar
        local black = Instance.new("Frame")
        black.Name = "Black"
        black.AnchorPoint = Vector2.new(0, 0)
        black.Position = UDim2.fromScale(0, 0)
        black.Size = UDim2.fromScale(1, 0.5)
        black.BackgroundColor3 = Color3.fromRGB(31, 35, 43)
        black.BorderSizePixel = 0
        black.Parent = evalBar
        local blackCorner = Instance.new("UICorner")
        blackCorner.CornerRadius = UDim.new(0, 4)
        blackCorner.Parent = black
        local white = Instance.new("Frame")
        white.Name = "White"
        white.AnchorPoint = Vector2.new(0, 1)
        white.Position = UDim2.fromScale(0, 1)
        white.Size = UDim2.fromScale(1, 0.5)
        white.BackgroundColor3 = Color3.fromRGB(232, 238, 245)
        white.BorderSizePixel = 0
        white.Parent = evalBar
        local whiteCorner = Instance.new("UICorner")
        whiteCorner.CornerRadius = UDim.new(0, 4)
        whiteCorner.Parent = white

        local board = Instance.new("Frame")
        board.Size = UDim2.fromOffset(258, 258)
        board.Position = UDim2.fromOffset(27, 30)
        board.BackgroundTransparency = 1
        board.Parent = shell
        local cells = {}
        for rank = 7, 0, -1 do
            for file = 0, 7 do
                local cell = Instance.new("Frame")
                local displayRank = 7 - rank
                cell.Size = UDim2.fromOffset(32.25, 32.25)
                cell.Position = UDim2.fromOffset(file * 32.25, displayRank * 32.25)
                cell.BackgroundColor3 = ((file + rank) % 2 == 0)
                    and Color3.fromRGB(232, 215, 184) or Color3.fromRGB(151, 108, 76)
                cell.BorderSizePixel = 0
                cell.Parent = board
                local image = Instance.new("ImageLabel")
                image.Size = UDim2.fromScale(0.86, 0.86)
                image.Position = UDim2.fromScale(0.5, 0.5)
                image.AnchorPoint = Vector2.new(0.5, 0.5)
                image.BackgroundTransparency = 1
                image.ScaleType = Enum.ScaleType.Fit
                image.Parent = cell
                cells[rank * 8 + file] = image
            end
        end
        State.overlay = { gui = gui, group = group, cells = cells, white = white, black = black, evalText = evalText }
        return State.overlay
    end

    local function updateOverlay(fen)
        if not Config.Chess.ShowOverlay then
            if State.overlay then setOverlayVisible(false) end
            return
        end
        local overlay = makeOverlay()
        if State.overlayFen ~= fen then
            local placement = type(fen) == "string" and fen:match("^(%S+)") or nil
            if not placement then return end
            -- A full 64-cell clear is cheap and runs only when the FEN changes.
            -- It prevents a captured/moved piece from remaining on the 2D board.
            for _, image in pairs(overlay.cells) do image.Image = "" end
            local rank, file = 7, 0
            for ch in placement:gmatch(".") do
                if ch == "/" then rank = rank - 1; file = 0
                else
                    local count = tonumber(ch)
                    if count then file = file + count
                    else
                        local image = overlay.cells[rank * 8 + file]
                        if image then image.Image = PIECE_IMAGES[ch] or "" end
                        file = file + 1
                    end
                end
            end
            State.overlayFen = fen
        end
        local eval = tonumber(State.eval) or 0
        local whiteShare = State.evalMate and (State.evalMate > 0 and 1 or 0)
            or math.clamp(0.5 + math.atan(eval / 3) / math.pi, 0.03, 0.97)
        overlay.white.Size = UDim2.fromScale(1, whiteShare)
        overlay.black.Size = UDim2.fromScale(1, 1 - whiteShare)
        overlay.evalText.Text = State.evalMate and ("M" .. tostring(State.evalMate)) or string.format("%+.2f", eval)
        setOverlayVisible(true)
    end

    local function chessLog(...)
        print("[ChessEngine]", ...)
    end

    local function looksLikeChess(value)
        if type(value) ~= "table" then return false end
        if type(rawget(value, "legalTargets")) ~= "table" then return false end
        if type(rawget(value, "spectating")) ~= "table" then return false end
        if rawget(value, "ctx") == nil then return false end
        local mirror = rawget(value, "mirror")
        if mirror ~= nil and type(mirror) ~= "table" then return false end
        return rawget(value, "active") ~= nil and rawget(value, "seated") ~= nil
    end

    local CHESS_KEYS = { "ctx", "boardView", "mirror", "myColor", "tableId", "active", "seated", "legalTargets", "spectating" }
    local function atChessSeat()
        local character = LocalPlayer and LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local seat = humanoid and humanoid.SeatPart
        if not seat then return false end
        if seat:GetAttribute("ChessSeatID") ~= nil then return true end
        local value = seat:FindFirstChild("ChessSeatID")
        return value ~= nil and value:IsA("ValueBase")
    end

    local function findChessState(force)
        if looksLikeChess(State.chess) then return State.chess end
        State.chess = nil
        -- The full state lives in GC, but there is no reason to touch GC while the
        -- player is not even sitting at a tagged chess seat. This cheap Instance-tree
        -- gate keeps the expensive fallback completely idle during normal gameplay.
        if not force and not atChessSeat() then return nil end
        local now = os.clock()
        if not force and now - State.lastScan < 2 then return nil end
        State.lastScan = now

        local G = (type(getgenv) == "function" and getgenv()) or _G
        if type(G.filtergc) == "function" then
            local ok, result = pcall(G.filtergc, "table", { Keys = CHESS_KEYS }, false)
            if ok and type(result) == "table" then
                if looksLikeChess(result) then State.chess = result; return result end
                for _, value in ipairs(result) do
                    if looksLikeChess(value) then State.chess = value; return value end
                end
            end
        end
        -- Full GC is a last resort and is rate-limited to the same one-second scan.
        if type(G.getgc) == "function" then
            local ok, values = pcall(G.getgc, true)
            if ok and type(values) == "table" then
                for _, value in ipairs(values) do
                    if looksLikeChess(value) then State.chess = value; return value end
                end
            end
        end
        return nil
    end

    local function liveSnapshot(force)
        local chess = findChessState(force)
        if not chess or rawget(chess, "active") ~= true then return nil end
        local mirror = rawget(chess, "mirror")
        if type(mirror) ~= "table" then return nil end
        local fen = chessStateToFEN(rawget(mirror, "state"))
        if not validFEN(fen) then return nil end
        local color = rawget(chess, "myColor") or rawget(chess, "seatColor")
        if color ~= "w" and color ~= "b" then color = nil end
        return chess, mirror, fen, color
    end

    local function disconnectSignal(conn)
        if conn then pcall(function() conn:Disconnect() end) end
    end

    local function dropSocket(closeIt)
        disconnectSignal(State.wsMessageConn)
        disconnectSignal(State.wsCloseConn)
        State.wsMessageConn, State.wsCloseConn = nil, nil
        local old = State.ws
        State.ws = nil
        State.connecting = false
        if closeIt and old then pcall(function() old:Close() end) end
        if old then chessLog(closeIt and "socket closed" or "socket dropped") end
    end

    local function clearHint()
        if State.folder then pcall(function() State.folder:Destroy() end) end
        State.folder = nil
        State.hintFen = nil
        State.hintMove = nil
    end

    local function ensureHintFolder()
        clearHint()
        local camera = Workspace and Workspace.CurrentCamera
        if not camera then return nil end
        local folder = Instance.new("Folder")
        folder.Name = "SyllinseChessEngineHint"
        folder.Parent = camera
        State.folder = folder
        return folder
    end

    local function makeCellAdornee(folder, geo, index)
        local tiles = type(geo) == "table" and rawget(geo, "squareToTile")
        local tile = type(tiles) == "table" and tiles[index] or nil
        if typeof(tile) == "Instance" then return tile end
        if type(geo) ~= "table" or type(geo.squareToWorld) ~= "function" then return nil end
        local ok, world = pcall(geo.squareToWorld, geo, index)
        if not ok or typeof(world) ~= "Vector3" then return nil end
        local cell = tonumber(rawget(geo, "cell"))
        local plate = rawget(geo, "plateCFrame")
        if not cell or typeof(plate) ~= "CFrame" then return nil end
        local part = Instance.new("Part")
        part.Name = "Cell_" .. tostring(squareName(index) or index)
        part.Size = Vector3.new(cell, 0.06, cell)
        part.CFrame = plate.Rotation + world
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Transparency = 1
        part.Parent = folder
        return part
    end

    local function addCellHighlight(folder, adornee, name, color, destination)
        if not adornee then return false end
        local h = Instance.new("Highlight")
        h.Name = name
        h.Adornee = adornee
        h.FillColor = color
        h.OutlineColor = color
        h.FillTransparency = math.clamp(Config.Chess.FillTransparency or 0.42, 0, 1)
        h.OutlineTransparency = destination and 0 or 0.15
        h.DepthMode = Config.Chess.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        h.Parent = folder
        return true
    end

    local function renderHint(chess, fen, parsed)
        local boardView = rawget(chess, "boardView")
        local geo = type(boardView) == "table" and rawget(boardView, "geo") or nil
        if type(geo) ~= "table" then return false, "board geometry unavailable" end
        local folder = ensureHintFolder()
        if not folder then return false, "camera unavailable" end
        local fromAdornee = makeCellAdornee(folder, geo, parsed.from)
        local toAdornee = makeCellAdornee(folder, geo, parsed.to)
        local fromOk = addCellHighlight(folder, fromAdornee, "From_" .. parsed.fromName, Config.Chess.FromColor, false)
        local toOk = addCellHighlight(folder, toAdornee, "To_" .. parsed.toName, Config.Chess.ToColor, true)
        if not fromOk or not toOk then clearHint(); return false, "could not resolve board cells" end
        State.hintFen = fen
        State.hintMove = parsed.raw
        return true
    end

    local function currentSocketConnector()
        local G = (type(getgenv) == "function" and getgenv()) or _G
        local wsLib = rawget(G, "WebSocket") or rawget(G, "websocket")
        if type(wsLib) == "table" then
            return wsLib.connect or wsLib.Connect
        end
        return nil
    end

    local function sendPosition(force)
        local chess, mirror, fen, color = liveSnapshot(force)
        if not chess then
            State.status = "no live chess state"
            chessLog("send skipped: no active live state")
            return false, "no active chess game"
        end
        if Config.Chess.OnlyMyTurn and (not color or mirror.state.side ~= color) then
            clearHint()
            State.sentFen = nil
            State.pending = nil
            State.status = "waiting for my turn"
            return false, "waiting for your turn"
        end
        if not State.ws then State.status = "socket disconnected"; return false, "websocket is not connected" end
        if not force and State.sentFen == fen then return true, "already analyzed" end

        State.requestSeq = State.requestSeq + 1
        local taskId = string.format("syllinse-%d-%d", State.requestSeq, math.floor(os.clock() * 1000))
        local payload = {
            fen = fen,
            variants = 1,
            depth = math.clamp(math.floor(Config.Chess.Depth or 12), 1, 18),
            maxThinkingTime = math.clamp(math.floor(Config.Chess.ThinkingTime or 50), 1, 100),
            taskId = taskId,
        }
        local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
        if not okEncode then return false, "JSON encode failed" end
        local okSend, err = pcall(State.ws.Send, State.ws, encoded)
        if not okSend then
            dropSocket(false)
            State.nextConnect = os.clock() + (Config.Chess.ReconnectDelay or 2)
            return false, "websocket send failed: " .. tostring(err)
        end
        State.lastFen = fen
        State.sentFen = fen
        State.pending = { clientTaskId = taskId, serverTaskId = nil, fen = fen }
        State.bestDepth = 0
        State.status = "position sent"
        chessLog("sent", fen, "color=" .. tostring(color), "turn=" .. tostring(mirror.state.side),
            "depth=" .. tostring(payload.depth), "time=" .. tostring(payload.maxThinkingTime))
        clearHint()
        return true, "position sent"
    end

    local function onSocketMessage(message)
        if type(message) ~= "string" then return end
        local okDecode, data = pcall(HttpService.JSONDecode, HttpService, message)
        if not okDecode or type(data) ~= "table" then
            State.lastError = "invalid websocket JSON"
            chessLog("invalid JSON:", tostring(message):sub(1, 300))
            return
        end
        State.lastPacket = tostring(data.type or "unknown") .. " depth=" .. tostring(data.depth or "-")
        if data.type == "error" then
            State.status = "API error"
            State.lastError = tostring(data.text or data.error or message)
            chessLog("API ERROR:", State.lastError, "fen=" .. tostring(data.fen or (State.pending and State.pending.fen)))
            return
        elseif data.type == "log" or data.type == "info" then
            chessLog(string.upper(tostring(data.type)), tostring(data.text or ""))
            return
        end
        if not State.pending then
            chessLog("ignored actionable packet without pending request", tostring(data.type), tostring(data.move))
            return
        end
        if not Config.Chess.Progressive and data.type ~= "bestmove" then return end
        local accepted = acceptResponse(data, State.pending, State.bestDepth)
        if not accepted then
            chessLog("rejected packet", tostring(data.type), tostring(data.move), "depth=" .. tostring(data.depth),
                "task=" .. tostring(data.taskId))
            return
        end

        local chess, mirror, fen, color = liveSnapshot(false)
        if not chess or fen ~= State.pending.fen then
            State.status = "stale position rejected"
            chessLog("stale result rejected", accepted.move)
            return
        end
        local liveOk, liveReason = false, nil
        if color then liveOk, liveReason = validateLiveMove(mirror, color, accepted.parsed) end
        if not liveOk then
            State.status = "API move failed live validation"
            chessLog("live validation rejected", accepted.move, "color=" .. tostring(color), "turn=" .. tostring(mirror.state.side))
            return
        elseif liveReason then
            chessLog("live validation fallback:", liveReason, "move=" .. tostring(accepted.move))
        end
        if accepted.depth < State.bestDepth and not accepted.final then return end
        State.bestDepth = math.max(State.bestDepth, accepted.depth)
        State.eval = accepted.eval
        State.evalMate = accepted.mate
        updateOverlay(fen)

        local previousMove = State.hintMove
        local shown, renderErr = renderHint(chess, fen, accepted.parsed)
        State.status = shown and ("hint " .. accepted.move) or ("render failed: " .. tostring(renderErr))
        chessLog(shown and "hint" or "render failed", accepted.move, "depth=" .. tostring(accepted.depth), tostring(renderErr or ""))
        if shown and Config.Chess.NotifyMove and (accepted.final or previousMove ~= accepted.move) then
            local suffix = accepted.mate and (" | mate " .. tostring(accepted.mate))
                or (accepted.eval and string.format(" | eval %.2f", accepted.eval) or "")
            State.notify("ChessEngine", string.format("%s -> %s | depth %d%s",
                accepted.parsed.fromName, accepted.parsed.toName, accepted.depth, suffix))
        end
    end

    local function connectSocket(force)
        if State.ws or State.connecting then return State.ws ~= nil end
        -- Do not establish a network connection merely because the feature is enabled.
        -- A live active chess state is the in-game gate, so outside a match there is
        -- no socket, no event connection, and no reconnect loop.
        if not liveSnapshot(false) then
            State.status = "waiting for chess game"
            return false
        end
        local now = os.clock()
        if not force and now < State.nextConnect then return false end
        local connect = currentSocketConnector()
        if type(connect) ~= "function" then
            State.nextConnect = now + 10
            State.status = "WebSocket API unavailable"
            chessLog("WebSocket.connect unavailable")
            return false
        end
        State.connecting = true
        local ok, socket = pcall(connect, "wss://chess-api.com/v1")
        State.connecting = false
        if not ok or not socket then
            State.nextConnect = now + (Config.Chess.ReconnectDelay or 2)
            State.status = "connection failed"
            State.lastError = tostring(socket)
            chessLog("connection failed:", tostring(socket))
            return false
        end
        State.ws = socket
        State.nextConnect = 0
        State.status = "websocket connected"
        chessLog("websocket connected")
        if socket.OnMessage and type(socket.OnMessage.Connect) == "function" then
            State.wsMessageConn = socket.OnMessage:Connect(onSocketMessage)
        end
        if socket.OnClose and type(socket.OnClose.Connect) == "function" then
            State.wsCloseConn = socket.OnClose:Connect(function()
                chessLog("websocket OnClose")
                dropSocket(false)
                State.nextConnect = os.clock() + (Config.Chess.ReconnectDelay or 2)
            end)
        end
        State.sentFen = nil
        State.pending = nil
        task.defer(function()
            if Config.Chess.Enabled and Config.Chess.AutoAnalyze then sendPosition(false) end
        end)
        return true
    end

    local function tick()
        if not Config.Chess.Enabled then return end
        local chess, mirror, fen, color = liveSnapshot(false)
        if not chess then
            if State.hintFen then clearHint() end
            if State.overlay then destroyOverlay() end
            if State.ws then dropSocket(true) end
            State.lastFen = nil
            return
        end
        updateOverlay(fen)
        if not State.ws then connectSocket(false) end
        if State.lastFen ~= fen then
            chessLog("position changed", State.lastFen and "old=" .. State.lastFen or "initial", "new=" .. fen)
            State.lastFen = fen
            State.pending = nil
            State.bestDepth = 0
            if State.hintFen ~= fen then clearHint() end
            if Config.Chess.AutoAnalyze and (not Config.Chess.OnlyMyTurn or (color and mirror.state.side == color)) then
                sendPosition(false)
            else
                State.sentFen = nil
            end
        elseif Config.Chess.AutoAnalyze and State.ws and State.sentFen ~= fen
            and (not Config.Chess.OnlyMyTurn or (color and mirror.state.side == color)) then
            sendPosition(false)
        end
    end

    local function startLoop()
        if State.running then return end
        State.running = true
        State.loopToken = State.loopToken + 1
        local token = State.loopToken
        task.spawn(function()
            while State.running and token == State.loopToken do
                local ok, err = pcall(tick)
                if not ok then State.chess = nil; State.lastError = tostring(err); State.status = "runtime error" end
                task.wait(math.clamp(Config.Chess.PollRate or 0.20, 0.10, 1.00))
            end
        end)
    end

    local function stopAll()
        State.running = false
        State.loopToken = State.loopToken + 1
        clearHint()
        dropSocket(true)
        State.chess = nil
        State.pending = nil
        State.sentFen = nil
        State.lastFen = nil
        State.eval = nil
        State.evalMate = nil
        destroyOverlay()
    end


    -- ═══════════════════════════════ MODULE ════════════════════════════════��
    local M = {}
    local _conn

    function M.start()
        Config.AutoRythm_On = false
        if not _conn then
            _conn = RunService.RenderStepped:Connect(function()
                if Config.AutoRythm_On then pcall(step) end
            end)
        end
        chalkStart()
        pcall(function()
            if Core and Core.On then
                Core:On("unload", function()
                    Config.AutoRythm_On = false
                    stopAutoDraw()
                    chalkStop()
                    stopAll()
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

        State.notify = notify

        -- ─────────────── Section: ChessEngine (Left) ───────────────
        local chessCfg = Config.Chess
        local sCE = Misc:Section({ Side = "Left" })
        sCE:Header({ Name = "ChessEngine" })
        feature(sCE, {
            Title = "ChessEngine", Flag = "Misc_ChessEngine",
            get = function() return chessCfg.Enabled end,
            set = function(v)
                chessCfg.Enabled = v and true or false
                if chessCfg.Enabled then
                    startLoop()
                    connectSocket(true)
                else
                    stopAll()
                end
            end,
            Desc = "Gets the best move from chess-api and highlights both cells locally",
        })
        sCE:SubLabel({ Text = "Uses the games live FEN and validates every API move before showing it" })
        sCE:Toggle({
            Name = "Auto Analyze", Default = chessCfg.AutoAnalyze,
            Callback = function(v)
                chessCfg.AutoAnalyze = v and true or false
                State.sentFen = nil
                if chessCfg.Enabled and chessCfg.AutoAnalyze then sendPosition(true) end
            end,
        }, ctx.flag("Misc_ChessEngine_Auto"))
        sCE:Toggle({
            Name = "Only My Turn", Default = chessCfg.OnlyMyTurn,
            Callback = function(v) chessCfg.OnlyMyTurn = v and true or false; State.sentFen = nil end,
        }, ctx.flag("Misc_ChessEngine_MyTurn"))
        sCE:Toggle({
            Name = "Progressive Results", Default = chessCfg.Progressive,
            Callback = function(v) chessCfg.Progressive = v and true or false end,
        }, ctx.flag("Misc_ChessEngine_Progressive"))
        sCE:Button({ Name = "Clear Hint", Callback = clearHint })

        sCE:Divider()
        sCE:Header({ Name = "Engine" })
        slider(sCE, {
            Name = "Depth", Flag = "Misc_ChessEngine_Depth",
            Default = chessCfg.Depth, Min = 1, Max = 18, Precision = 0,
            Callback = function(v) chessCfg.Depth = v; State.sentFen = nil end,
        })
        slider(sCE, {
            Name = "Thinking Time", Flag = "Misc_ChessEngine_Time",
            Default = chessCfg.ThinkingTime, Min = 1, Max = 100, Precision = 0, Suffix = " ms",
            Callback = function(v) chessCfg.ThinkingTime = v; State.sentFen = nil end,
        })
        slider(sCE, {
            Name = "Position Poll", Flag = "Misc_ChessEngine_Poll",
            Default = chessCfg.PollRate, Min = 0.1, Max = 1, Precision = 2, Suffix = "s",
            Callback = function(v) chessCfg.PollRate = v end,
        })
        sCE:SubLabel({ Text = "GC lookup runs only at a chess seat, then the live state is cached" })

        sCE:Divider()
        sCE:Header({ Name = "Highlights" })
        sCE:Colorpicker({
            Name = "From Cell", Default = chessCfg.FromColor,
            Callback = function(c) chessCfg.FromColor = c; State.sentFen = nil end,
        }, ctx.flag("Misc_ChessEngine_FromColor"))
        sCE:Colorpicker({
            Name = "To Cell", Default = chessCfg.ToColor,
            Callback = function(c) chessCfg.ToColor = c; State.sentFen = nil end,
        }, ctx.flag("Misc_ChessEngine_ToColor"))
        slider(sCE, {
            Name = "Fill Transparency", Flag = "Misc_ChessEngine_Transparency",
            Default = chessCfg.FillTransparency, Min = 0, Max = 1, Precision = 2,
            Callback = function(v) chessCfg.FillTransparency = v; State.sentFen = nil end,
        })
        sCE:Toggle({
            Name = "Always On Top", Default = chessCfg.AlwaysOnTop,
            Callback = function(v) chessCfg.AlwaysOnTop = v and true or false; State.sentFen = nil end,
        }, ctx.flag("Misc_ChessEngine_AlwaysOnTop"))
        sCE:Toggle({
            Name = "Overlay", Default = chessCfg.ShowOverlay,
            Callback = function(v)
                chessCfg.ShowOverlay = v and true or false
                if not chessCfg.ShowOverlay and State.overlay then setOverlayVisible(false) end
            end,
        }, ctx.flag("Misc_ChessEngine_Overlay"))
        sCE:Toggle({
            Name = "Move Notifications", Default = chessCfg.NotifyMove,
            Callback = function(v) chessCfg.NotifyMove = v and true or false end,
        }, ctx.flag("Misc_ChessEngine_Notify"))

        -- ─────────────── Section: AutoRythm (Left) ───────────────
        local sAR = Misc:Section({ Side = "Left" })
        sAR:Header({ Name = "AutoRythm" })
        feature(sAR, {
            Title = "AutoRythm", Flag = "Misc_AutoRythm",
            get = function() return Config.AutoRythm_On end,
            set = function(v) Config.AutoRythm_On = v end,
            Desc = "auto-plays the rhythm minigame",
        })
        sAR:Divider()
        sAR:Header({ Name = "Timing" })
        slider(sAR, {
            Name = "Offset", Flag = "Misc_AutoRythm_Offset",
            Default = Config.Offset, Min = -60, Max = 60, Precision = 0, Suffix = " ms",
            Callback = function(v) Config.Offset = v end,
        })
        sAR:SubLabel({ Text = "0 = frame-perfect. Only nudge if ur client has audio/display lag. Taps stay PERFECT within about +-43ms." })

        -- ─────────────── Section: Chalk Spammer (Right) ───────────────
        local chk = Config.Chalk
        local sCH = Misc:Section({ Side = "Right" })
        sCH:Header({ Name = "Chalk Spammer" })
        sCH:SubLabel({ Text = "useless shit, just added it to test my auth bypass" })
        sCH:Button({
            Name = "Take & Drop Once",
            Callback = function()
                local ok, reason = chalkTakeAndDropOnce()
                if ok then
                    notify("Chalk Spammer", "took / dropped item")
                else
                    notify("Chalk Spammer", "failed: " .. tostring(reason or "unknown"))
                end
            end,
        })
        feature(sCH, {
            Title = "Auto Spam", Flag = "Misc_Chalk_Auto",
            get = function() return chk.Auto end,
            set = function(v) chk.Auto = v and true or false end,
            Desc = "idk why u need it",
        })
        sCH:Divider()
        sCH:Dropdown({
            Name = "Item", Default = chk.Items,
            Options = { "Alternate", "Chalk", "Sponge" },
            Callback = function(v) chk.Items = v or "Alternate" end,
        }, ctx.flag("Misc_Chalk_Items"))
        sCH:SubLabel({ Text = "Alternate = switch between chalk and sponge each grab" })
        sCH:Dropdown({
            Name = "Chalk Color", Default = chk.Mode,
            Options = { "Rainbow", "Random", "White", "Red", "Orange", "Yellow", "Green", "Blue", "Indigo", "Violet" },
            Callback = function(v) chk.Mode = v or "Rainbow" end,
        }, ctx.flag("Misc_Chalk_Mode"))
        sCH:SubLabel({ Text = "Colour used when taking chalk. Rainbow cycles all 8; Random rolls each time; or pick one" })
        slider(sCH, {
            Name = "Delay", Flag = "Misc_Chalk_Delay",
            Default = chk.Delay, Min = 0.1, Max = 2, Precision = 2, Suffix = "s",
            Callback = function(v) chk.Delay = v end,
        })
        sCH:SubLabel({ Text = "Time between each take/drop action. Lower = faster mess, but too fast trips the rate limit sooner" })
        slider(sCH, {
            Name = "Rate-limit Cooldown", Flag = "Misc_Chalk_Cooldown",
            Default = chk.Cooldown, Min = 0.5, Max = 10, Precision = 1, Suffix = "s",
            Callback = function(v) chk.Cooldown = v end,
        })

        -- ─────────────── Section: Auto Draw (Right) ──���────────────
        local ad = Config.AutoDraw
        local sAD = Misc:Section({ Side = "Right" })
        sAD:Header({ Name = "Auto Draw" })
        sAD:SubLabel({ Text = "Draws a PNG or JPEG on the nearest chalk whiteboard. Equip Chalk and stand within ~16 studs of a board" })

        sAD:Input({
            Name = "Image URL", Placeholder = "https://.../image.png", Default = ad.Url,
            Callback = function(t)
                ad.Url = t or ""
                -- Remember that the URL was the most recent choice so it wins over a
                -- stale Workspace File dropdown selection when we resolve the source.
                if ad.Url:match("^https?://") then ad.Source = "url" end
            end,
        }, ctx.flag("Misc_AutoDraw_Url"))

        local fileDD = sAD:Dropdown({
            Name = "Workspace File", Search = true,
            Options = (function()
                local list = scanImageFiles()
                if #list == 0 then return { "(no images in workspace)" } end
                return list
            end)(),
            Callback = function(v)
                ad.File = v or ""
                -- Picking a real file (not the "(no images…)" placeholder) makes the
                -- file the most recent choice, so it wins over a stale URL.
                if ad.File ~= "" and not ad.File:match("^%(") then ad.Source = "file" end
            end,
        }, ctx.flag("Misc_AutoDraw_File"))

        sAD:Button({
            Name = "Refresh Files",
            Callback = function()
                local list = scanImageFiles()
                pcall(function() fileDD:ClearOptions() end)
                pcall(function() fileDD:InsertOptions(#list > 0 and list or { "(no images in workspace)" }) end)
                notify("Auto Draw", (#list) .. " image file(s) found")
            end,
        })

        -- Primary actions right under the image picker so Draw is one click away.
        sAD:Button({ Name = "Draw", Callback = function() startAutoDraw(notify) end })
        sAD:Button({ Name = "Stop", Callback = function() stopAutoDraw(); notify("Auto Draw", "stopped") end })
        sAD:SubLabel({ Text = "Pick a URL or workspace file above, then press Draw. Equip chalk + stand near a board if Sync is on" })

        -- ── Image quality ──────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Image" })
        slider(sAD, {
            Name = "Quality", Flag = "Misc_AutoDraw_Quality",
            Default = ad.Quality, Min = 1, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.Quality = v end,
        })
        sAD:SubLabel({ Text = "higher = more scanlines + finer colour, lower = coarse and fast." })
        sAD:Toggle({
            Name = "Colour", Default = not ad.Mono,
            Callback = function(v) ad.Mono = not v end,
        }, ctx.flag("Misc_AutoDraw_Colour"))
        sAD:SubLabel({ Text = "draw everything in chalk white." })
        sAD:Toggle({
            Name = "Preserve Aspect Ratio", Default = ad.Preserve,
            Callback = function(v) ad.Preserve = v end,
        }, ctx.flag("Misc_AutoDraw_Preserve"))
        sAD:SubLabel({ Text = "Keep the images proportions instead of stretching it to fill the board" })

        -- ── Dark pixels ────────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Dark Pixels" })
        sAD:Toggle({
            Name = "Skip Dark Pixels", Default = ad.SkipBg,
            Callback = function(v) ad.SkipBg = v end,
        }, ctx.flag("Misc_AutoDraw_SkipBg"))
        sAD:SubLabel({ Text = "OFF: black/dark pixels ARE drawn. ON: leaves near-black pixels unpainted so the black board shows through (useful for line art / logos)" })
        slider(sAD, {
            Name = "Dark Threshold", Flag = "Misc_AutoDraw_Threshold",
            Default = ad.Threshold, Min = 0, Max = 80, Precision = 0,
            Callback = function(v) ad.Threshold = v end,
        })
        sAD:SubLabel({ Text = "Only used when Skip Dark Pixels is ON: pixels darker than this brightness (0-255) are skipped" })

        -- ── Sync ───────────────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Sync" })
        sAD:Toggle({
            Name = "Sync to Server", Default = ad.Sync,
            Callback = function(v) ad.Sync = v end,
        }, ctx.flag("Misc_AutoDraw_Sync"))
        sAD:SubLabel({ Text = "ON: sends strokes to the server so the drawing persists and others see it" })
        slider(sAD, {
            Name = "Draw Speed", Flag = "Misc_AutoDraw_Speed",
            Default = ad.Speed, Min = 30, Max = 4000, Precision = 0, Suffix = " pts/s",
            Callback = function(v) ad.Speed = v end,
        })
        sAD:SubLabel({ Text = "Points/second painted. Your screen and the server fill in together through the game's own draw path, so both look identical" })

        -- ── Size & position ────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Size & Position" })
        slider(sAD, {
            Name = "Scale", Flag = "Misc_AutoDraw_Scale",
            Default = ad.Scale, Min = 10, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.Scale = v end,
        })
        sAD:SubLabel({ Text = "How much of the board the drawing fills" })
        slider(sAD, {
            Name = "Horizontal Align", Flag = "Misc_AutoDraw_AlignX",
            Default = ad.AlignX, Min = 0, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.AlignX = v end,
        })
        sAD:SubLabel({ Text = "0 = left, 50 = center, 100 = right." })
        slider(sAD, {
            Name = "Vertical Align", Flag = "Misc_AutoDraw_AlignY",
            Default = ad.AlignY, Min = 0, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.AlignY = v end,
        })
        sAD:SubLabel({ Text = "0 = top, 50 = middle, 100 = bottom." })

        -- ── Preview ────────────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Preview" })
        sAD:Toggle({
            Name = "Preview", Default = ad.Preview,
            Callback = function(v)
                ad.Preview = v and true or false
                if ad.Preview then previewBoard(notify, true) else clearPreview() end
            end,
        }, ctx.flag("Misc_AutoDraw_Preview"))
        sAD:SubLabel({ Text = "ON: highlights the nearest board (blue)" })
        sAD:Button({
            Name = "Refresh Preview",
            Callback = function()
                if ad.Preview then previewBoard(notify, true) else notify("Auto Draw", "turn Preview on first") end
            end,
        })
        sAD:Button({ Name = "Test Stroke (X)", Callback = function() testStroke(notify) end })
        sAD:SubLabel({ Text = "Draws a white X" })

        -- ── Board tools ────────────────────────────────────────────────
        sAD:Divider()
        sAD:Header({ Name = "Board" })
        sAD:Button({
            Name = "Clear Board",
            Callback = function()
                local board, dist = findNearestBoard()
                if not board then notify("Auto Draw", "no whiteboard found — stand near one"); return end
                if dist and dist > 15 then
                    notify("Auto Draw", ("too far from the whiteboard (%.0f studs) — move within 15"):format(dist)); return
                end
                stopAutoDraw()
                local wantServer = Config.AutoDraw.Sync and hasChalkEquipped()
                local ok = clearBoard(board, wantServer)
                if ok then
                    notify("Auto Draw", wantServer and "board cleared (synced)" or "board cleared locally")
                else
                    notify("Auto Draw", "could not clear the board — see debug log")
                end
            end,
        })
        sAD:SubLabel({ Text = "Wipes the nearest board" })

        uiReady = true
    end

    return M
end
