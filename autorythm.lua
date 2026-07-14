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
            Detail     = 100,    -- vertical resolution (rows) — higher = finer + slower
            Speed      = 45,     -- strokes sent per SECOND (higher = faster, riskier)
            Threshold  = 16,     -- brightness (0-255) below which a pixel is skipped
            SkipBg     = true,   -- skip near-black pixels (board background is black)
            Mono       = false,  -- draw everything in chalk white instead of colour
            Preserve   = true,   -- preserve the image aspect ratio on the board
            Sync       = true,   -- also fire the draw remote (persist + show to others)
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
    -- hold). The engine's _step then auto-finalizes the sustain at t+len as PERFECT.
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

        -- Lanes with a hold in progress must never be tap-released.
        for _, note in ipairs(active) do
            if (note.len or 0) > 0 and note.hit and not note.holdJudgment then
                _laneHolding[note.lane] = true
            end
        end

        -- Clear tracking of holds the engine has already scored; safety-release any
        -- hold stuck well past its end (e.g. engine paused).
        for lane, note in pairs(_heldLane) do
            if note.holdJudgment ~= nil then
                _heldLane[lane] = nil
                _allowRelease[lane] = nil
            elseif now > (note.t + (note.len or 0) + 0.5) then
                _allowRelease[lane] = true
                pcall(engine._handleLaneRelease, engine, lane)
                _allowRelease[lane] = nil
                _heldLane[lane] = nil
            end
        end

        -- Press notes that have arrived.
        for _, note in ipairs(active) do
            local lane = note.lane
            if type(lane) == "number" and lane >= 1 and lane <= lanes
               and not note.hit and not note.attempted then
                if (note.len or 0) > 0 then
                    -- Hold: press only at/after note.t (an early press never sets holding).
                    local holdOffset = (offset > 0) and offset or 0
                    if now >= note.t + holdOffset and not _heldLane[lane] then
                        pcall(engine._handleLanePress, engine, lane)
                        _heldLane[lane] = note
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
    -- board. Returns UV rect u0,v0,u1,v1.
    local function computeRegion(preserve, imgW, imgH)
        local drawW, drawH
        if preserve and imgW and imgH and imgW > 0 and imgH > 0 then
            local imgA, boardA = imgW / imgH, BOARD_W / BOARD_H
            if imgA > boardA then drawW, drawH = BOARD_W, BOARD_W / imgA
            else drawW, drawH = BOARD_H * imgA, BOARD_H end
        else
            drawW, drawH = BOARD_W, BOARD_H
        end
        local offX, offY = (BOARD_W - drawW) / 2, (BOARD_H - drawH) / 2
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
    -- We locate that board map by scanning the GC for the table whose entries look
    -- like { part = BasePart, editableImage = <EditableImage>, surfaceGui = ... }.
    local _boardMap
    local function resolveBoardMap()
        if _boardMap then
            -- Validate the cache still holds live entries.
            local k, v = next(_boardMap)
            if type(v) == "table" and typeof(v.part) == "Instance" then return _boardMap end
            _boardMap = nil
        end
        if type(getgc) ~= "function" then
            adlog("resolveBoardMap: getgc unavailable")
            return nil
        end
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" then
                local k, v = next(o)
                if type(k) == "number" and type(v) == "table"
                   and typeof(v.part) == "Instance" and v.editableImage ~= nil
                   and v.surfaceGui ~= nil then
                    _boardMap = o
                    adlog("resolveBoardMap: found board map (%s entries)", tostring(#o))
                    return o
                end
            end
        end
        adlog("resolveBoardMap: board map NOT found in GC")
        return nil
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
    local function localStroke(boardId, brush, r, g, b, u1, v1, u2, v2)
        local map = resolveBoardMap()
        local entry = map and map[boardId]
        if not entry or not entry.editableImage then return false end
        local img = entry.editableImage
        local col = Color3.fromRGB(b8(r), b8(g), b8(b))
        local ok = pcall(function()
            if u1 == u2 and v1 == v2 then
                img:DrawCircle(Vector2.new(math.round(uvClamp(u1) * 512), math.round(uvClamp(v1) * 384)),
                    brush, col, 0.05 + math.random() * 0.18, Enum.ImageCombineType.AlphaBlend)
            else
                chalkSegmentLocal(img, uvClamp(u1), uvClamp(v1), uvClamp(u2), uvClamp(v2), brush, col)
            end
        end)
        return ok
    end

    -- Draw a stroke: always render locally (so WE see it) and, when sync is on, also
    -- fire the remote so the server persists it and other players see it too.
    local function drawStroke(boardId, brush, r, g, b, u1, v1, u2, v2, sync)
        local shown = localStroke(boardId, brush, r, g, b, u1, v1, u2, v2)
        if sync then fireRun(boardId, brush, r, g, b, u1, v1, u2, v2) end
        return shown
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

        return nil, "CreateEditableImage failed — " .. table.concat(attempts, " | ")
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

    -- Load an image file → { w, h, buf|arr }. Prefers the pure-Lua PNG decoder
    -- (dependable across executors); falls back to the EditableImage pipeline for
    -- non-PNG formats (e.g. JPG). Sets _adYield during decode to avoid script timeouts.
    local function decodeImage(path)
        _adYield = function() RunService.Heartbeat:Wait() end
        local cleanup = function() _adYield = nil end

        -- 1) Pure-Lua PNG via readfile (no getcustomasset needed).
        if type(readfile) == "function" then
            local okR, bytes = pcall(readfile, path)
            if okR and type(bytes) == "string" and #bytes > 8 then
                if bytes:sub(1, 8) == PNG_SIG then
                    local px, perr = decodePNG(bytes)
                    cleanup()
                    if px then
                        adlog("decodeImage: PNG decoded %dx%d (pure-Lua)", px.w, px.h)
                        return px
                    end
                    adlog("decodeImage: pure-Lua PNG failed: %s — trying EditableImage", tostring(perr))
                    _adYield = function() RunService.Heartbeat:Wait() end
                else
                    adlog("decodeImage: not PNG (magic %d,%d,%d) — trying EditableImage",
                        bytes:byte(1) or 0, bytes:byte(2) or 0, bytes:byte(3) or 0)
                end
            else
                adlog("decodeImage: readfile failed (%s) — trying EditableImage", tostring(bytes))
            end
        else
            adlog("decodeImage: no readfile — trying EditableImage")
        end

        -- 2) EditableImage fallback (JPG / anything the decoder can't handle).
        local img, err = loadEditableImage(path)
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
        adlog("runDraw: start boardId=%s path='%s' detail=%d speed=%d",
            tostring(board.id), tostring(opts.path), opts.detail, opts.speed)
        local px, err = decodeImage(opts.path)
        if not px then _drawing = false; adlog("runDraw: image load FAILED: %s", tostring(err)); notify("Auto Draw", tostring(err)); return end

        local token = _drawToken
        local iw, ih = px.w, px.h
        adlog("runDraw: image %dx%d, pixels read via %s", iw, ih, px.buf and "buffer" or "array")

        -- Fit the image onto the board, preserving aspect if requested.
        local u0, v0, u1v, v1v = computeRegion(opts.preserve, iw, ih)
        local drawW, drawH = (u1v - u0) * BOARD_W, (v1v - v0) * BOARD_H
        local offX, offY = u0 * BOARD_W, v0 * BOARD_H
        adlog("runDraw: region uv[%.3f,%.3f]-[%.3f,%.3f] (%.0fx%.0f px)", u0, v0, u1v, v1v, drawW, drawH)

        -- Show the live preview (highlight board + region outline) while drawing.
        showPreview(board, u0, v0, u1v, v1v, nil)

        -- Detail = number of horizontal scanlines. With a fixed 4px-thick brush,
        -- rows >= ~96 fully cover the 384px canvas; lower rows give a sketchier look.
        local rows    = math.clamp(math.floor(opts.detail), 16, 300)
        local rowStep = drawH / rows
        local colStep = math.max(1.5, rowStep)          -- ~square sampling cells
        local cols    = math.max(1, math.floor(drawW / colStep + 0.5))
        colStep = drawW / cols

        -- Colour quantisation buckets so flat regions merge into long runs.
        local qstep = 40
        local function quant(v)
            local q = math.floor(v / qstep) * qstep + math.floor(qstep / 2)
            if q > 255 then q = 255 end
            return q
        end
        local monoR, monoG, monoB = b8(CHALK_COLOR.R * 255), b8(CHALK_COLOR.G * 255), b8(CHALK_COLOR.B * 255)

        -- ── Phase 1: rasterise into a flat stroke list (fast; occasional yield) ──
        -- Each stroke is a horizontal same-colour run: {r,g,b,u1,u2,v}.
        local strokes = {}
        local capped = false
        for r = 0, rows - 1 do
            if token ~= _drawToken then break end
            local py = offY + (r + 0.5) * rowStep
            local v  = py / BOARD_H
            local iy = math.floor((py - offY) / drawH * ih)

            local runActive, rr, rg, rb, runU1, runU2 = false, 0, 0, 0, 0, 0
            local function flush()
                if runActive then
                    strokes[#strokes + 1] = { r = rr, g = rg, b = rb, u1 = runU1, u2 = runU2, v = v }
                    runActive = false
                end
            end

            for c = 0, cols - 1 do
                local pxx = offX + (c + 0.5) * colStep
                local ix  = math.floor((pxx - offX) / drawW * iw)
                local sr, sg, sb = samplePix(px, ix, iy)
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
        -- Every stroke is rendered LOCALLY onto the board's EditableImage so we
        -- actually see it (the server never echoes our own batches back to us).
        -- When Sync is on we ALSO fire the draw remote so the server persists the
        -- drawing and other players see it — that path is rate-limited because the
        -- unreliable channel drops packets if flooded. With Sync off we just blast
        -- the local render as fast as possible (yielding to keep the frame alive).
        local sync = opts.sync
        local sent = 0
        local drewLocal = false

        if not sync then
            for i = 1, total do
                if token ~= _drawToken then break end
                local s = strokes[i]
                if localStroke(board.id, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v) then
                    drewLocal = true
                end
                if (i % 120) == 0 then RunService.Heartbeat:Wait() end
            end
        else
            local perSec   = math.clamp(math.floor(opts.speed), 5, 200)
            local burstCap = math.clamp(math.floor(perSec / 12), 2, 8)
            local budget, lastClock = 0, os.clock()
            for i = 1, total do
                if token ~= _drawToken then break end
                local nowc = os.clock()
                budget = budget + (nowc - lastClock) * perSec
                lastClock = nowc
                if budget > burstCap then budget = burstCap end
                while budget < 1 do
                    RunService.Heartbeat:Wait()
                    if token ~= _drawToken then break end
                    nowc = os.clock()
                    budget = budget + (nowc - lastClock) * perSec
                    lastClock = nowc
                end
                if token ~= _drawToken then break end
                budget = budget - 1

                local s = strokes[i]
                if localStroke(board.id, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v) then
                    drewLocal = true
                end
                if fireRun(board.id, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v) then
                    sent = sent + 1
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
        local path

        if ad.File and ad.File ~= "" and not ad.File:match("^%(") then
            path = ad.File
            if type(isfile) == "function" and not isfile(path) then
                notify("Auto Draw", "file not found: " .. path); return
            end
        elseif ad.Url and ad.Url:match("^https?://") then
            local data
            local ok = pcall(function()
                if type(request) == "function" then
                    local res = request({ Url = ad.Url, Method = "GET" })
                    data = res and res.Body
                elseif type(game.HttpGetAsync) == "function" then
                    data = game:HttpGetAsync(ad.Url)
                end
            end)
            if not ok or not data or #data == 0 then
                notify("Auto Draw", "download failed — check the URL"); return
            end
            local ext = ad.Url:match("%.([%a]%a%a%a?)%f[%A]") or "png"
            path = "syllinse_autodraw_temp." .. ext:lower()
            if type(writefile) ~= "function" then
                notify("Auto Draw", "executor has no writefile"); return
            end
            if not pcall(writefile, path, data) then
                notify("Auto Draw", "could not save the downloaded image"); return
            end
        else
            notify("Auto Draw", "select a workspace file or paste an image URL first"); return
        end

        _drawToken = _drawToken + 1
        _drawing = true
        notify("Auto Draw", "drawing… press Stop to cancel")

        local opts = {
            path = path, detail = ad.Detail, speed = ad.Speed, threshold = ad.Threshold,
            skipbg = ad.SkipBg, mono = ad.Mono, preserve = ad.Preserve, sync = ad.Sync,
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

        local u0, v0, u1v, v1v = computeRegion(ad.Preserve, iw, ih)
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
        shown = drawStroke(id, 2, W, W, W, 0.05, 0.05, 0.95, 0.95, sync) or shown
        drawStroke(id, 2, W, W, W, 0.95, 0.05, 0.05, 0.95, sync)
        drawStroke(id, 2, W, W, W, 0.05, 0.05, 0.95, 0.05, sync)
        drawStroke(id, 2, W, W, W, 0.95, 0.05, 0.95, 0.95, sync)
        drawStroke(id, 2, W, W, W, 0.95, 0.95, 0.05, 0.95, sync)
        drawStroke(id, 2, W, W, W, 0.05, 0.95, 0.05, 0.05, sync)
        showPreview(board, 0, 0, 1, 1, 8)
        if shown then
            notify("Auto Draw", ("test X drawn on board #%s (%.0f studs)"):format(tostring(id), dist or 0))
        else
            notify("Auto Draw", "could not access the board image (local render failed) — see debug log")
        end
    end

    -- List image files in the executor workspace root (for the file dropdown).
    local IMG_EXT = { png = true, jpg = true, jpeg = true, jfif = true, bmp = true, tga = true, webp = true }
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
        sAD:SubLabel({ Text = "Draws an image on the nearest chalk whiteboard. Equip Chalk and stand within ~16 studs of a board." })

        sAD:Input({
            Name = "Image URL", Placeholder = "https://.../image.png", Default = ad.Url,
            Callback = function(t) ad.Url = t or "" end,
        }, ctx.flag("Misc_AutoDraw_Url"))

        local fileDD = sAD:Dropdown({
            Name = "Workspace File", Search = true,
            Options = (function()
                local list = scanImageFiles()
                if #list == 0 then return { "(no images in workspace)" } end
                return list
            end)(),
            Callback = function(v) ad.File = v or "" end,
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
            Name = "Detail", Flag = "Misc_AutoDraw_Detail",
            Default = ad.Detail, Min = 16, Max = 200, Precision = 0, Suffix = " rows",
            Callback = function(v) ad.Detail = v end,
        })
        sAD:SubLabel({ Text = "Vertical resolution. Higher = finer image but more strokes and slower drawing." })
        slider(sAD, {
            Name = "Speed", Flag = "Misc_AutoDraw_Speed",
            Default = ad.Speed, Min = 5, Max = 200, Precision = 0, Suffix = " /sec",
            Callback = function(v) ad.Speed = v end,
        })
        sAD:SubLabel({ Text = "Strokes sent per second. The draw remote is unreliable, so very high rates drop packets (gaps) or risk a kick. 30-60 is a safe sweet spot." })
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
        sAD:SubLabel({ Text = "ON: also sends strokes to the server so the drawing persists and other players see it (slower, rate-limited). OFF: renders instantly on your screen only." })

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

        uiReady = true
    end

    return M
end
