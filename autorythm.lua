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
    local BOARD_W, BOARD_H = 512, 384

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
        return (pcall(function() net.WhiteboardDrawBatch.Fire(buf) end))
    end

    -- Nearest tagged whiteboard with a valid WhiteboardId; returns board + distance.
    local function findNearestBoard()
        local root
        local char = LocalPlayer.Character
        if char then root = char:FindFirstChild("HumanoidRootPart") end
        local best, bestD
        local ok, tagged = pcall(function() return CollectionService:GetTagged("Whiteboard") end)
        if not ok or type(tagged) ~= "table" then return nil end
        for _, part in ipairs(tagged) do
            if typeof(part) == "Instance" and part:IsA("BasePart") then
                local id = part:GetAttribute("WhiteboardId")
                if type(id) == "number" then
                    local d = root and (root.Position - part.Position).Magnitude or math.huge
                    if not bestD or d < bestD then best, bestD = { id = id, part = part }, d end
                end
            end
        end
        return best, bestD
    end

    -- Load an image file (workspace-relative path) into an EditableImage.
    local function loadEditableImage(path)
        local getAsset = getcustomasset or getsynasset
        if type(getAsset) ~= "function" then
            return nil, "executor has no getcustomasset"
        end
        local asset
        if not pcall(function() asset = getAsset(path) end) or not asset then
            return nil, "getcustomasset failed for '" .. tostring(path) .. "'"
        end
        local content
        pcall(function() content = Content.fromUri(asset) end)

        local img
        local ok1 = content and pcall(function()
            img = AssetService:CreateEditableImageAsync(content)
        end)
        if not (ok1 and img) then
            local ok2 = pcall(function()
                img = AssetService:CreateEditableImageAsync(asset)
            end)
            if not (ok2 and img) then
                return nil, "CreateEditableImageAsync failed (format unsupported or image too large; max 1024x1024)"
            end
        end
        return img
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

    local _drawing = false
    local _drawToken = 0

    local function stopAutoDraw()
        _drawing = false
        _drawToken = _drawToken + 1
    end

    -- The game always draws chalk at brush radius 2 (WhiteboardServiceClient:406
    -- hardcodes it), so the server expects that value — we send exactly 2 and let
    -- Detail (row count) control how finely the image is reproduced.
    local BRUSH = 2
    local MAX_STROKES = 60000   -- safety cap against pathological (noisy) images

    -- opts: { path, detail, speed, threshold, skipbg, mono, preserve }, notify(title,body)
    local function runDraw(board, opts, notify)
        local img, err = loadEditableImage(opts.path)
        if not img then _drawing = false; notify("Auto Draw", tostring(err)); return end
        local px = readPixels(img)
        pcall(function() img:Destroy() end)
        if not px then _drawing = false; notify("Auto Draw", "could not read image pixels"); return end

        local token = _drawToken
        local iw, ih = px.w, px.h

        -- Fit the image onto the board, preserving aspect if requested.
        local drawW, drawH
        if opts.preserve then
            local imgA, boardA = iw / ih, BOARD_W / BOARD_H
            if imgA > boardA then drawW, drawH = BOARD_W, BOARD_W / imgA
            else drawW, drawH = BOARD_H * imgA, BOARD_H end
        else
            drawW, drawH = BOARD_W, BOARD_H
        end
        local offX, offY = (BOARD_W - drawW) / 2, (BOARD_H - drawH) / 2

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
        if token ~= _drawToken then _drawing = false; return end
        if total == 0 then
            _drawing = false
            notify("Auto Draw", "nothing to draw (try lowering Skip Threshold)"); return
        end

        -- ── Phase 2: send strokes, rate-limited (unreliable remote drops if flooded) ──
        -- opts.speed = strokes per SECOND. A budget accumulator paces sends against
        -- real time regardless of frame rate, with a small burst cap so a lag spike
        -- can't dump a flood of packets (which the unreliable channel would drop).
        local perSec   = math.clamp(math.floor(opts.speed), 5, 200)
        local burstCap = math.clamp(math.floor(perSec / 12), 2, 8)
        local budget, lastClock = 0, os.clock()
        local sent = 0

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
            if fireRun(board.id, BRUSH, s.r, s.g, s.b, s.u1, s.v, s.u2, s.v) then
                sent = sent + 1
            end
        end

        _drawing = false
        if token == _drawToken then
            notify("Auto Draw", ("done — %d/%d strokes%s"):format(sent, total, capped and " (detail capped)" or ""))
        end
    end

    -- Resolve the image source (file or URL), then kick off the draw coroutine.
    local function startAutoDraw(notify)
        if _drawing then notify("Auto Draw", "already drawing — press Stop first"); return end

        local net = getNet()
        if not net or not net.WhiteboardDrawBatch then
            notify("Auto Draw", "whiteboard network remote unavailable"); return
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
            skipbg = ad.SkipBg, mono = ad.Mono, preserve = ad.Preserve,
        }
        task.spawn(function()
            local ok, err = pcall(runDraw, board, opts, notify)
            if not ok then _drawing = false; notify("Auto Draw", "error: " .. tostring(err)) end
        end)
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

        -- ─────────────── Section: Auto Draw (Right) ───────────────
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

        sAD:Divider()
        sAD:Button({ Name = "Draw", Callback = function() startAutoDraw(notify) end })
        sAD:Button({ Name = "Stop", Callback = function() stopAutoDraw(); notify("Auto Draw", "stopped") end })

        uiReady = true
    end

    return M
end
