-- ═══════════════════════════════════════════════════════════════════════════
--  Misc module for the Syllinse loader (AutoParry game, UniverseId 9199655655).
--  Two features, both built into ctx.tabs.Misc:
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
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local CoreGui           = game:GetService("CoreGui")
    local AssetService      = game:GetService("AssetService")
    local CollectionService = game:GetService("CollectionService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace         = game:GetService("Workspace")

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
            Quality    = 60,     -- 1-100: single knob for detail + colour fidelity
            Speed      = 45,     -- segments/second sent to the server (Sync on)
            Threshold  = 16,     -- brightness (0-255) below which a pixel is skipped
            SkipBg     = true,   -- skip near-black pixels (board background is black)
            Mono       = false,  -- draw everything in chalk white instead of colour
            Preserve   = true,   -- preserve the image aspect ratio on the board
            Sync       = true,   -- also fire the draw remote (persist + show to others)
            Scale      = 100,    -- % of the board the drawing occupies (10-100)
            AlignX     = 50,     -- horizontal placement: 0 = left, 50 = center, 100 = right
            AlignY     = 50,     -- vertical placement: 0 = top, 50 = middle, 100 = bottom
            Debug      = false,  -- print step-by-step diagnostics to the console
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
    local function installReleaseGuard(engine)
        if rawget(engine, "__ar_relGuard") then return end
        local realRelease = engine._handleLaneRelease
        if type(realRelease) ~= "function" then return end
        rawset(engine, "_handleLaneRelease", function(self, lane)
            if _heldLane[lane] and not _allowRelease[lane] then return end
            return realRelease(self, lane)
        end)
        rawset(engine, "__ar_relGuard", true)
    end

    local function step()
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

        -- WHY THE OLD APPROACH FAILED, AND WHAT WE DO NOW
        -- ------------------------------------------------
        -- A hold is scored ONLY inside RhythmEngine._step, at t+len, by calling
        -- _judgeHoldNote(ratio, initialTiming) + _applyScore (RhythmEngine:1594-1601).
        -- BUT that finalize is nested inside `if note.inst then` and guarded by despawn
        -- checks — timing we don't control. If the note gets despawned (offscreen / past
        -- t+len+BAD) before that branch runs, or its instance is gone, the sustain is
        -- silently removed WITH NO SCORE. Merely forcing note.holding = true (previous
        -- attempt) didn't help because the finalize branch never executed for it.
        --
        -- FIX: `active` IS the engine's live _active array and _judgeHoldNote/_applyScore
        -- are real methods. So we FINALIZE THE HOLD OURSELVES at t+len by calling those
        -- same methods on the live note. This banks the score no matter what the engine's
        -- despawn/instance timing does. We set note.holdJudgment first, so the engine's
        -- own finalize branch (RhythmEngine:1583 `if holdJudgment then`) just cleans up
        -- the instance instead of scoring again — no double count.

        -- 1) Maintain / finalize notes we're currently holding.
        for lane, note in pairs(_heldLane) do
            local holdEnd = note.t + (note.len or 0)
            if note.holdJudgment ~= nil then
                -- Already scored (by us on a previous frame, or by the engine) — release
                -- the key so the lane is free for future notes, then stop tracking.
                _allowRelease[lane] = true
                pcall(engine._handleLaneRelease, engine, lane)
                _allowRelease[lane] = nil
                _heldLane[lane] = nil
            elseif now >= holdEnd then
                -- Reached the end of the sustain: score it ourselves exactly like the
                -- engine would. Full hold => ratio ~= 1.0 and PERFECT initial timing =>
                -- PERFECT judgment.
                note.holdStartTime = note.holdStartTime or note.t
                local held  = now - note.holdStartTime
                local ratio = (note.len and note.len > 0) and (held / note.len) or 1
                if ratio > 1 then ratio = 1 end
                local judged
                local okJ = pcall(function()
                    judged = engine._judgeHoldNote(engine, ratio, note.initialTiming or 0)
                end)
                if not okJ or type(judged) ~= "string" then judged = "PERFECT" end
                note.holding      = false
                note.holdEndTime  = now
                note.holdDuration = held
                note.holdJudgment = judged
                pcall(engine._applyScore, engine, judged, note.initialTiming or 0, note.lane)
                -- Now release the (logical) key and stop tracking.
                _allowRelease[lane] = true
                pcall(engine._handleLaneRelease, engine, lane)
                _allowRelease[lane] = nil
                _heldLane[lane] = nil
            else
                -- Still within the sustain: keep the lane marked held (so the tap branch
                -- never releases it) and keep the engine's visual state consistent.
                _laneHolding[lane] = true
                note.holdStartTime = note.holdStartTime or note.t
                if note.holding ~= true then note.holding = true end
            end
        end

        -- 2) Press notes that have arrived.
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes
               and not note.hit and not note.attempted then
                if (note.len or 0) > 0 then
                    -- Hold: press once at note.t for the receptor visual, then FORCE the
                    -- note into a valid held state so our own finalize (block 1) will
                    -- score it — independent of whether the engine's press judged it.
                    if now >= note.t + offset and not _heldLane[lane] then
                        pcall(engine._handleLanePress, engine, lane)
                        note.hit          = true
                        note.initialTiming = note.initialTiming or 0
                        note.holdStartTime = note.holdStartTime or note.t
                        note.holding      = true
                        _heldLane[lane]   = note
                        _laneHolding[lane] = true
                    end
                elseif now >= note.t + offset and not _laneHolding[lane] then
                    pcall(engine._handleLanePress, engine, lane)
                    pcall(engine._handleLaneRelease, engine, lane)
                end
            end
        end
    end

    -- ═══════════════════════════ AUTO DRAW ══════════════════════════════════
    local CHALK_COLOR = Color3.fromRGB(242, 242, 238)
    local BOARD_W, BOARD_H = 512, 384   -- EditableImage canvas (WhiteboardServiceClient:189)

    -- Debug logging, gated by the UI toggle. Prints to the executor console with a
    -- clear prefix so the user can trace exactly which step succeeds or fails.
    local function adlog(fmt, ...)
        if not Config.AutoDraw.Debug then return end
        local ok, msg = pcall(string.format, fmt, ...)
        print("[AutoDraw] " .. (ok and msg or tostring(fmt)))
    end

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

    -- ── Local rendering ──────────────────────────────────────────────────────
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
    local _eiCache = setmetatable({}, { __mode = "k" })
    local function getBoardImage(part)
        if typeof(part) ~= "Instance" then return nil end
        local cached = _eiCache[part]
        if cached then return cached end

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
        adlog("getBoardImage: resolved EditableImage for '%s'", part.Name)
        return img
    end

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

        -- Show the live preview (highlight board + region outline) while drawing.
        showPreview(board, u0, v0, u1v, v1v, nil)

        -- ── Quality → concrete knobs ────────────────────────────────────────
        -- A single 1-100 dial drives BOTH how many scanlines we lay down (spatial
        -- detail) and how finely colour is quantised (tonal fidelity). The brush is
        -- 4px thick, so ~96 rows already fully cover the 384px canvas; we scale rows
        -- from a sketchy 48 up to a dense 240 (oversampled = crisp). Colour buckets
        -- shrink from very coarse (72) to near-lossless (6) so high quality removes
        -- the banding the old fixed qstep=40 produced.
        local q = math.clamp(math.floor(opts.quality or 60), 1, 100)
        local qf = (q - 1) / 99
        local rows    = math.floor(48 + qf * (240 - 48) + 0.5)
        local rowStep = drawH / rows
        local colStep = math.max(1.0, rowStep)          -- ~square sampling cells
        local cols    = math.max(1, math.floor(drawW / colStep + 0.5))
        colStep = drawW / cols

        -- Colour quantisation buckets so flat regions merge into long runs.
        local qstep = math.floor(72 - qf * (72 - 6) + 0.5)
        local half  = math.floor(qstep / 2)
        local function quant(v)
            local qb = math.floor(v / qstep) * qstep + half
            if qb > 255 then qb = 255 end
            return qb
        end
        local monoR, monoG, monoB = b8(CHALK_COLOR.R * 255), b8(CHALK_COLOR.G * 255), b8(CHALK_COLOR.B * 255)

        -- Cell-averaged sampler: instead of one nearest-neighbour pixel per cell
        -- (which aliases badly when a big photo is squeezed onto the board — the main
        -- cause of the "quality dropped" look), average a small grid over the cell's
        -- source footprint. Sample count scales with quality (1..3 per axis).
        local srcCellW = (drawW > 0) and (iw / cols) or 1
        local srcCellH = (drawH > 0) and (ih / rows) or 1
        local aa = 1 + math.floor(qf * 2 + 0.5)          -- 1, 2 or 3 samples per axis
        local function sampleCell(cx, cy)
            local x0 = math.floor(cx * srcCellW)
            local y0 = math.floor(cy * srcCellH)
            local x1 = math.max(x0, math.floor((cx + 1) * srcCellW) - 1)
            local y1 = math.max(y0, math.floor((cy + 1) * srcCellH) - 1)
            local nx = math.min(aa, x1 - x0 + 1)
            local ny = math.min(aa, y1 - y0 + 1)
            local sr, sg, sb, n = 0, 0, 0, 0
            for sy = 0, ny - 1 do
                local iy = (ny == 1) and y0 or (y0 + math.floor(sy * (y1 - y0) / (ny - 1)))
                for sx = 0, nx - 1 do
                    local ix = (nx == 1) and x0 or (x0 + math.floor(sx * (x1 - x0) / (nx - 1)))
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
                    strokes[#strokes + 1] = { r = rr, g = rg, b = rb, u1 = runU1, u2 = runU2, v = v }
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

        -- ── Phase 2: draw the strokes ────────────────────────────────────────
        -- GOAL: what you see on YOUR screen must equal what actually reached the
        -- server (and therefore other players + the persisted board).
        --
        -- WhiteboardDrawBatch is an UNRELIABLE remote, and the game itself never
        -- sends more than one batch per ~0.08s (WhiteboardServiceClient flushStroke,
        -- lines 394/485). If we blast strokes with no limit, the flooded unreliable
        -- channel silently DROPS packets: the server ends up with fewer strokes than
        -- our screen shows — exactly the "local looks right, server looks wrong"
        -- mismatch. So when Sync is on we PACE the sends with a token-bucket
        -- (Speed = segments/second) and render each stroke LOCALLY in lockstep, i.e.
        -- only in the same step we fire it. Screen and server advance together.
        --
        -- With Sync OFF there is no server involved, so we render at full speed.
        local sync = opts.sync
        local sent = 0
        local drewLocal = false

        if not sync then
            -- Local-only preview: no server to match, so use the fast (faithful=false)
            -- path and render at full speed.
            local lastYield = os.clock()
            for i = 1, total do
                if token ~= _drawToken then break end
                local s = strokes[i]
                if localStroke(board.part, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v, false) then
                    drewLocal = true
                end
                -- Yield by wall-clock so tiny images finish in one frame and huge
                -- ones stay responsive.
                if os.clock() - lastYield >= 0.010 then
                    RunService.Heartbeat:Wait()
                    lastYield = os.clock()
                end
            end
        else
            -- Token-bucket: refill `perSec` tokens/second, spend one per stroke.
            -- burstCap ≈ one heartbeat's worth so we never dump a huge burst that
            -- the unreliable channel would drop.
            local perSec   = math.clamp(math.floor(opts.speed or 45), 3, 300)
            local burstCap = math.max(4, math.floor(perSec * 0.12))
            local budget, last = 0, os.clock()
            for i = 1, total do
                if token ~= _drawToken then break end
                while budget < 1 do
                    RunService.Heartbeat:Wait()
                    if token ~= _drawToken then break end
                    local now = os.clock()
                    budget = math.min(burstCap, budget + (now - last) * perSec)
                    last = now
                end
                if token ~= _drawToken then break end
                budget = budget - 1

                local s = strokes[i]
                -- LOCKSTEP: fire to the server, then — ONLY if the fire succeeded —
                -- mirror the exact same stroke locally with the FAITHFUL renderer, so
                -- our screen shows precisely what the server received and what other
                -- players see (soft alpha-blended chalk, not a hard local fill). If the
                -- fire fails we skip the local paint so no "phantom" stroke appears that
                -- isn't actually on the server.
                if fireRun(board.id, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v) then
                    sent = sent + 1
                    if localStroke(board.part, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v, true) then
                        drewLocal = true
                    end
                end
            end
        end

        _drawing = false
        adlog("runDraw: DONE local=%s synced=%d/%d (fireErr=%s)", tostring(drewLocal), sent, total, tostring(_fireErrLogged))
        if token == _drawToken then
            if not drewLocal then
                notify("Auto Draw", "could not access the board image (local render failed) — see debug log")
            elseif sync then
                notify("Auto Draw", ("done — %d/%d strokes synced%s"):format(sent, total, capped and " (detail capped)" or ""))
            else
                notify("Auto Draw", ("done — %d strokes (local only)%s"):format(total, capped and " (detail capped)" or ""))
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
        if dist and dist > 22 then
            notify("Auto Draw", ("too far from a whiteboard (%.0f studs) — move closer"):format(dist))
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
    local function previewBoard(notify)
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
        showPreview(board, u0, v0, u1v, v1v, 12)
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

    -- ═══════════════════════════════ MODULE ═════════════════════════════════
    local M = {}
    local _conn

    function M.start()
        Config.AutoRythm_On = false
        if not _conn then
            _conn = RunService.RenderStepped:Connect(function()
                if Config.AutoRythm_On then pcall(step) end
            end)
        end
        pcall(function()
            if Core and Core.On then
                Core:On("unload", function()
                    Config.AutoRythm_On = false
                    stopAutoDraw()
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

        -- ─────────────── Section: Auto Draw (Right) ──���────────────
        local ad = Config.AutoDraw
        local sAD = Misc:Section({ Side = "Right" })
        sAD:Header({ Name = "Auto Draw" })
        sAD:SubLabel({ Text = "Draws a PNG or JPEG on the nearest chalk whiteboard. Equip Chalk and stand within ~16 studs of a board." })

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

        sAD:Divider()
        sAD:Header({ Name = "Quality" })
        slider(sAD, {
            Name = "Quality", Flag = "Misc_AutoDraw_Quality",
            Default = ad.Quality, Min = 1, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.Quality = v end,
        })
        sAD:SubLabel({ Text = "One dial for the whole image: higher = more scanlines, finer colour and anti-aliased sampling (sharper, slower); lower = coarse and fast." })
        slider(sAD, {
            Name = "Sync Speed", Flag = "Misc_AutoDraw_Speed",
            Default = ad.Speed, Min = 3, Max = 300, Precision = 0, Suffix = " /s",
            Callback = function(v) ad.Speed = v end,
        })
        sAD:SubLabel({ Text = "Segments per second sent to the server when Sync is on. The draw remote is UNRELIABLE and the game itself sends ~1 batch per 0.08s, so high values flood it and the server drops strokes (your screen would show more than everyone else). ~45 keeps your view and the server identical; raise it to trade fidelity for speed. Ignored when Sync is off (local render is always full-speed)." })
        slider(sAD, {
            Name = "Skip Threshold", Flag = "Misc_AutoDraw_Threshold",
            Default = ad.Threshold, Min = 0, Max = 80, Precision = 0,
            Callback = function(v) ad.Threshold = v end,
        })
        sAD:Toggle({
            Name = "Skip Dark Pixels", Default = ad.SkipBg,
            Callback = function(v) ad.SkipBg = v end,
        }, ctx.flag("Misc_AutoDraw_SkipBg"))
        sAD:SubLabel({ Text = "Leaves near-black pixels unpainted (the board is black), so dark areas show through." })
        sAD:Toggle({
            Name = "Monochrome (chalk white)", Default = ad.Mono,
            Callback = function(v) ad.Mono = v end,
        }, ctx.flag("Misc_AutoDraw_Mono"))
        sAD:Toggle({
            Name = "Preserve Aspect Ratio", Default = ad.Preserve,
            Callback = function(v) ad.Preserve = v end,
        }, ctx.flag("Misc_AutoDraw_Preserve"))
        sAD:Toggle({
            Name = "Sync to Server", Default = ad.Sync,
            Callback = function(v) ad.Sync = v end,
        }, ctx.flag("Misc_AutoDraw_Sync"))
        sAD:SubLabel({ Text = "ON: also sends strokes to the server so the drawing persists and other players see it — requires ANY chalk equipped in your hand. OFF: renders instantly on your screen only." })

        sAD:Divider()
        sAD:Header({ Name = "Size & Position" })
        slider(sAD, {
            Name = "Scale", Flag = "Misc_AutoDraw_Scale",
            Default = ad.Scale, Min = 10, Max = 100, Precision = 0, Suffix = " %",
            Callback = function(v) ad.Scale = v end,
        })
        sAD:SubLabel({ Text = "How much of the board the drawing fills. 100% = as large as fits; lower to draw a smaller image. Use Preview Board to see the exact region." })
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

        sAD:Divider()
        sAD:Header({ Name = "Preview & Debug" })
        sAD:Button({ Name = "Preview Board", Callback = function() previewBoard(notify) end })
        sAD:SubLabel({ Text = "Highlights the nearest board (blue) and outlines where the image will be drawn (green). Auto-clears after ~12s." })
        sAD:Button({ Name = "Test Stroke (X)", Callback = function() testStroke(notify) end })
        sAD:SubLabel({ Text = "Draws a white X + border on the board (renders locally, and syncs if Sync is on). If this shows up, the draw path works and only image loading is the problem." })
        sAD:Button({ Name = "Clear Preview", Callback = function() clearPreview(); notify("Auto Draw", "preview cleared") end })
        sAD:Toggle({
            Name = "Debug Logging", Default = ad.Debug,
            Callback = function(v) ad.Debug = v end,
        }, ctx.flag("Misc_AutoDraw_Debug"))
        sAD:SubLabel({ Text = "Prints step-by-step diagnostics to the executor console (prefixed [AutoDraw]). Enable this if nothing draws." })

        sAD:Divider()
        sAD:Button({ Name = "Draw", Callback = function() startAutoDraw(notify) end })
        sAD:Button({ Name = "Stop", Callback = function() stopAutoDraw(); notify("Auto Draw", "stopped") end })
        sAD:Button({
            Name = "Clear Board",
            Callback = function()
                local board, dist = findNearestBoard()
                if not board then notify("Auto Draw", "no whiteboard found — stand near one"); return end
                if dist and dist > 22 then
                    notify("Auto Draw", ("too far from a whiteboard (%.0f studs) — move closer"):format(dist)); return
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
        sAD:SubLabel({ Text = "Wipes the nearest board. Clears your local view instantly; also clears it for everyone if Sync is on and chalk is equipped." })

        uiReady = true
    end

    return M
end
