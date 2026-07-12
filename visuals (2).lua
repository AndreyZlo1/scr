--
-- Visuals module (Syllinse — BRM5 / japanese street RP-PvP).
-- Builds its whole UI into ctx.tabs.Visuals via buildUI(ctx). Read-only: it never
-- writes game attributes or hooks combat — it only READS replicated state and draws
-- on top, so there is no anti-cheat surface here.
--
--   • ESP (Drawing API): 2D box, name, distance, health bar, combat State
--     (Attacking / Blocking / Parry / Stunned / Downed / Grappling), combat Style
--     (char.PlayerData.CombatStyle), optional skeleton lines and screen tracer.
--
--   • Indicators (Neverlose-style GUI): a smooth animated stack of capsule bars for
--     the LOCAL player — Health, Stamina, IFrame, Heavy (M2) cooldown, Dodge
--     (Evasive) cooldown, Block cooldown. Each bar slides + fades in when relevant
--     and collapses out when not; values are lerped for smooth motion. Cooldown
--     durations come from ReplicatedStorage.Shared.Config.CombatConfig (exact) with a
--     dynamic-measurement fallback if the module can't be required.
--
--   • Hit Direction: fading directional arrows around the crosshair pointing at the
--     source of incoming damage (nearest attacker on a health drop).
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService      = game:GetService("TweenService")
    local UserInputService  = game:GetService("UserInputService")

    local LocalPlayer = Players.LocalPlayer

    -- cloneref hides our references to Camera/CoreGui from naive scans (harmless if absent)
    local cref = (type(cloneref) == "function") and cloneref or function(x) return x end
    local Camera = cref(Workspace.CurrentCamera)
    Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        if Workspace.CurrentCamera then Camera = cref(Workspace.CurrentCamera) end
    end)

    -- ── Config (all OFF at start; M.start enforces it) ───────────────────────
    local Config = {
        -- ESP
        ESP_On       = false,
        ESP_Box      = true,
        ESP_Name     = true,
        ESP_Distance = true,
        ESP_State    = true,
        ESP_Style    = true,
        ESP_Health   = true,
        ESP_M2Bar    = true,     -- purple vertical bar (right of box) = target's M2 cooldown
        ESP_Skeleton = false,
        ESP_Tracer   = false,
        ESP_MaxDist  = 1200,
        ESP_Box_Color  = Color3.fromRGB(90, 150, 255),
        ESP_Text_Color = Color3.fromRGB(235, 235, 240),
        ESP_M2_Color   = Color3.fromRGB(170, 110, 255),

        -- Indicators
        Ind_On      = false,
        Ind_Health  = true,
        Ind_Stamina = true,
        Ind_IFrame  = true,
        Ind_M2      = true,
        Ind_Dodge   = true,
        Ind_Block   = true,
        Ind_Accent  = Color3.fromRGB(90, 150, 255),

        -- Hit direction
        HitDir_On    = false,
        HitDir_Color = Color3.fromRGB(255, 74, 74),
    }

    -- ── Combat config (exact cooldown durations; optional) ───────────────────
    local CombatConfig
    pcall(function()
        local m = ReplicatedStorage:FindFirstChild("CombatConfig", true)
        if m and m:IsA("ModuleScript") then CombatConfig = require(m) end
    end)
    local function styleKeyOf(char)
        local pd = char and char:FindFirstChild("PlayerData")
        local s = pd and pd:GetAttribute("CombatStyle")
        return (type(s) == "string" and s ~= "") and s or "default"
    end
    local function cfgM2Cooldown(char)
        if CombatConfig and CombatConfig.GetStyleM2Cooldown then
            local ok, v = pcall(CombatConfig.GetStyleM2Cooldown, styleKeyOf(char))
            if ok and type(v) == "number" then return v end
        end
        return 7
    end
    local function cfgEvasiveCooldown(char)
        if CombatConfig and CombatConfig.GetStyleEvasiveCooldown then
            local ok, v = pcall(CombatConfig.GetStyleEvasiveCooldown, styleKeyOf(char))
            if ok and type(v) == "number" then return v end
        end
        return 1.5
    end
    -- M2Cooldown is a boolean attribute → mirror it into a timed ratio per target,
    -- using the exact duration from CombatConfig. `trk` is the per-esp o.m2t table.
    -- Returns remaining ratio (0..1) while on cooldown, or nil when ready.
    local function readTargetM2Ratio(char, trk)
        local on = char:GetAttribute("M2Cooldown") == true
        if on and not trk.active then
            trk.active = true; trk.t0 = time(); trk.dur = cfgM2Cooldown(char)
        elseif not on and trk.active then
            trk.active = false
        end
        if not on then return nil end
        local remaining = math.max(0, trk.dur - (time() - trk.t0))
        return math.clamp(remaining / math.max(trk.dur, 0.01), 0, 1)
    end

    -- ── Small helpers ────────────────────────────────────────────────────────
    local function lerp(a, b, t) return a + (b - a) * t end
    local function lerpColor(a, b, t) return a:Lerp(b, t) end

    local function getChar(plr)
        local c = plr.Character
        if not c or not c.Parent then return nil end
        return c
    end
    local function getHum(char)
        return char and char:FindFirstChildOfClass("Humanoid") or nil
    end
    local function getRoot(char)
        return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")) or nil
    end
    local function isAlive(char)
        local h = getHum(char)
        return h ~= nil and h.Health > 0
    end

    -- combat State read (replicated attributes on the character), by priority
    local function readState(char)
        local function a(n) return char:GetAttribute(n) end
        if a("Dead") == true                            then return "Dead",       Color3.fromRGB(120, 120, 120) end
        if a("Downed") == true or a("Ragdoll") == true  then return "Downed",     Color3.fromRGB(255, 90,  90) end
        if a("Grappling") == true                       then return "Grappling",  Color3.fromRGB(255, 150, 60) end
        if a("Stunned") == true or a("GuardBroken") == true then return "Stunned", Color3.fromRGB(255, 210, 70) end
        if a("PerfectBlocking") == true or a("Parried") == true then return "Parry", Color3.fromRGB(120, 220, 255) end
        if a("Blocking") == true                        then return "Blocking",   Color3.fromRGB(90,  180, 255) end
        if a("CombatAttacking") == true                 then return "Attacking",  Color3.fromRGB(255, 120, 120) end
        return nil
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- ESP  (Drawing API)
    -- ═══════════════════════════════════════════════════════════════════════
    local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

    -- R15 + R6 skeleton bone pairs (by part name; missing parts are skipped)
    local BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
        -- R6 fallback
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    local espPool = {}   -- [player] = { objects... }

    local function newDrawing(class, props)
        local d = Drawing.new(class)
        for k, v in pairs(props) do d[k] = v end
        return d
    end

    -- One factory so EVERY ESP label shares IDENTICAL font + outline settings. The
    -- name used to look crisper than the rest simply because the props weren't shared;
    -- now name/info/state/style all render with the same Plex font (2) and outline.
    local function newText(size, color)
        return newDrawing("Text", {
            Size    = size,
            Font    = 2,                      -- Plex (the nice-looking one)
            Center  = true,
            Outline = true,
            OutlineColor = Color3.new(0, 0, 0),
            Visible = false,
            Color   = color,
            ZIndex  = 3,
        })
    end

    local TEXT_KEYS = { "name", "info", "state", "style" }
    local BAR_KEYS  = { "box", "boxOutline", "hpBg", "hp", "m2Bg", "m2", "tracer" }

    local function createEsp(plr)
        if espPool[plr] then return espPool[plr] end
        local o = {}
        o.box = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false, Color = Config.ESP_Box_Color, ZIndex = 2 })
        o.boxOutline = newDrawing("Square", { Thickness = 3, Filled = false, Visible = false, Color = Color3.new(0, 0, 0), ZIndex = 1 })
        o.name  = newText(14, Config.ESP_Text_Color)
        o.info  = newText(13, Config.ESP_Text_Color)
        o.state = newText(13, Color3.new(1, 1, 1))
        o.style = newText(13, Color3.fromRGB(200, 200, 210))
        o.hpBg = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false, Color = Color3.new(0, 0, 0), ZIndex = 1 })
        o.hp   = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false, Color = Color3.fromRGB(90, 220, 90), ZIndex = 2 })
        -- purple M2-cooldown bar, mirrored on the RIGHT side of the box
        o.m2Bg = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false, Color = Color3.new(0, 0, 0), ZIndex = 1 })
        o.m2   = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false, Color = Config.ESP_M2_Color, ZIndex = 2 })
        o.tracer = newDrawing("Line", { Thickness = 1, Visible = false, Color = Config.ESP_Box_Color })
        o.m2t = { active = false, t0 = 0, dur = 7 }   -- per-player M2 timer (boolean attr → timed)
        o.bones = {}
        for i = 1, #BONES do
            o.bones[i] = newDrawing("Line", { Thickness = 1, Visible = false, Color = Color3.fromRGB(255, 255, 255) })
        end
        espPool[plr] = o
        return o
    end

    local function hideEsp(o)
        if not o then return end
        for _, key in ipairs(TEXT_KEYS) do if o[key] then o[key].Visible = false end end
        for _, key in ipairs(BAR_KEYS)  do if o[key] then o[key].Visible = false end end
        for _, b in ipairs(o.bones) do b.Visible = false end
    end

    local function destroyEsp(plr)
        local o = espPool[plr]
        if not o then return end
        for _, key in ipairs(TEXT_KEYS) do if o[key] then pcall(function() o[key]:Remove() end) end end
        for _, key in ipairs(BAR_KEYS)  do if o[key] then pcall(function() o[key]:Remove() end) end end
        for _, b in ipairs(o.bones) do pcall(function() b:Remove() end) end
        espPool[plr] = nil
    end

    local function updateEspFor(plr)
        local o = espPool[plr] or createEsp(plr)
        local char = getChar(plr)
        if not (Config.ESP_On and char and isAlive(char)) then hideEsp(o); return end

        local hum  = getHum(char)
        local root = getRoot(char)
        if not (hum and root) then hideEsp(o); return end

        local lpChar = getChar(LocalPlayer)
        local lpRoot = lpChar and getRoot(lpChar)
        local dist = lpRoot and (root.Position - lpRoot.Position).Magnitude or 0
        if Config.ESP_MaxDist > 0 and dist > Config.ESP_MaxDist then hideEsp(o); return end

        -- 2D box from the model bounding box. Corners are built AXIS-ALIGNED in world
        -- space (NOT rotated by the model CFrame): shiftlock forces the character to
        -- yaw toward the camera, and an orientation-locked box would shift/breathe with
        -- that yaw. Using world axes + the max horizontal extent keeps the box steady.
        local cf, size = char:GetBoundingBox()
        local center = cf.Position
        local hx = math.max(size.X, size.Z) * 0.5
        local hy = size.Y * 0.5
        local hz = hx
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        local anyOn = false
        for _, cx in ipairs({ -1, 1 }) do
            for _, cy in ipairs({ -1, 1 }) do
                for _, cz in ipairs({ -1, 1 }) do
                    local world = center + Vector3.new(hx * cx, hy * cy, hz * cz)
                    local sp, on = Camera:WorldToViewportPoint(world)
                    if on then anyOn = true end
                    if sp.X < minX then minX = sp.X end
                    if sp.Y < minY then minY = sp.Y end
                    if sp.X > maxX then maxX = sp.X end
                    if sp.Y > maxY then maxY = sp.Y end
                end
            end
        end
        if not anyOn then hideEsp(o); return end

        local bx, by = minX, minY
        local bw, bh = maxX - minX, maxY - minY

        -- Box
        if Config.ESP_Box then
            o.box.Color = Config.ESP_Box_Color
            o.box.Position = Vector2.new(bx, by); o.box.Size = Vector2.new(bw, bh); o.box.Visible = true
            o.boxOutline.Position = Vector2.new(bx, by); o.boxOutline.Size = Vector2.new(bw, bh); o.boxOutline.Visible = true
        else
            o.box.Visible = false; o.boxOutline.Visible = false
        end

        -- Health bar (left of the box)
        if Config.ESP_Health then
            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local hbx = bx - 5
            o.hpBg.Position = Vector2.new(hbx - 1, by - 1); o.hpBg.Size = Vector2.new(4, bh + 2); o.hpBg.Visible = true
            local fillH = bh * ratio
            o.hp.Position = Vector2.new(hbx, by + (bh - fillH)); o.hp.Size = Vector2.new(2, fillH)
            o.hp.Color = lerpColor(Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 220, 90), ratio)
            o.hp.Visible = true
        else
            o.hpBg.Visible = false; o.hp.Visible = false
        end

        -- M2 (heavy) cooldown bar — purple, mirrored on the RIGHT side of the box.
        -- Fills from the bottom up and drains as the target's heavy attack recharges.
        if Config.ESP_M2Bar then
            local ratio = readTargetM2Ratio(char, o.m2t)
            if ratio then
                local mbx = bx + bw + 3
                o.m2Bg.Position = Vector2.new(mbx - 1, by - 1); o.m2Bg.Size = Vector2.new(4, bh + 2); o.m2Bg.Visible = true
                local fillH = bh * ratio
                o.m2.Position = Vector2.new(mbx, by + (bh - fillH)); o.m2.Size = Vector2.new(2, fillH)
                o.m2.Color = Config.ESP_M2_Color
                o.m2.Visible = true
            else
                o.m2Bg.Visible = false; o.m2.Visible = false
            end
        else
            o.m2Bg.Visible = false; o.m2.Visible = false
        end

        -- Name (above box)
        if Config.ESP_Name then
            o.name.Color = Config.ESP_Text_Color
            o.name.Text = plr.DisplayName or plr.Name
            o.name.Position = Vector2.new(bx + bw / 2, by - 16); o.name.Visible = true
        else
            o.name.Visible = false
        end

        -- Distance + style stacked under the box; state just below the box
        local belowY = by + bh + 2
        if Config.ESP_Distance then
            o.info.Color = Config.ESP_Text_Color
            o.info.Text = string.format("%dm", math.floor(dist))
            o.info.Position = Vector2.new(bx + bw / 2, belowY); o.info.Visible = true
            belowY = belowY + 13
        else
            o.info.Visible = false
        end
        if Config.ESP_State then
            local st, col = readState(char)
            if st then
                o.state.Text = st; o.state.Color = col
                o.state.Position = Vector2.new(bx + bw / 2, belowY); o.state.Visible = true
                belowY = belowY + 13
            else
                o.state.Visible = false
            end
        else
            o.state.Visible = false
        end
        if Config.ESP_Style then
            local sk = styleKeyOf(char)
            if sk and sk ~= "default" then
                o.style.Text = sk:sub(1, 1):upper() .. sk:sub(2)
                o.style.Position = Vector2.new(bx + bw / 2, belowY); o.style.Visible = true
            else
                o.style.Visible = false
            end
        else
            o.style.Visible = false
        end

        -- Tracer (from bottom-center of screen to box bottom)
        if Config.ESP_Tracer then
            local vp = Camera.ViewportSize
            o.tracer.Color = Config.ESP_Box_Color
            o.tracer.From = Vector2.new(vp.X / 2, vp.Y)
            o.tracer.To = Vector2.new(bx + bw / 2, by + bh)
            o.tracer.Visible = true
        else
            o.tracer.Visible = false
        end

        -- Skeleton
        if Config.ESP_Skeleton then
            for i, pair in ipairs(BONES) do
                local line = o.bones[i]
                local p0 = char:FindFirstChild(pair[1])
                local p1 = char:FindFirstChild(pair[2])
                if p0 and p1 then
                    local s0, on0 = Camera:WorldToViewportPoint(p0.Position)
                    local s1, on1 = Camera:WorldToViewportPoint(p1.Position)
                    if on0 and on1 then
                        line.From = Vector2.new(s0.X, s0.Y)
                        line.To = Vector2.new(s1.X, s1.Y)
                        line.Color = Config.ESP_Box_Color
                        line.Visible = true
                    else
                        line.Visible = false
                    end
                else
                    line.Visible = false
                end
            end
        else
            for _, b in ipairs(o.bones) do b.Visible = false end
        end
    end

    -- ═══════════════════════════════════════════════════════════════��═══════
    -- INDICATORS  (Neverlose-style animated GUI)
    -- ═══════════════════════════════════════════════════════════════════════
    local function guiParent()
        local ok, hui = pcall(function() return (type(gethui) == "function") and gethui() or nil end)
        if ok and hui then return hui end
        return cref(game:GetService("CoreGui"))
    end

    local screenGui, indHolder
    local rows = {}       -- [key] = row object
    local rowOrder = { "Health", "Stamina", "IFrame", "M2", "Dodge", "Block" }

    local ROW_H, ROW_GAP = 26, 6
    local TW_IN  = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local TW_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

    -- ── Drag + persistence state (position saved via MacLib FAL Data API) ────
    local MacLibRef                       -- captured from ctx.MacLib in buildUI
    local POS_FLAG                        -- FAL key for the saved HUD position
    local IND_W = 214                     -- HUD width (px)
    local drag = {
        target  = Vector2.new(0, 0),      -- desired top-left offset (px)
        disp    = Vector2.new(0, 0),      -- smoothed actual offset (px)
        active  = false,
        startIn = Vector2.new(0, 0),
        startPos = Vector2.new(0, 0),
    }
    local dragConns = {}                  -- UIS connections owned by the HUD (cleaned in stop)
    local clampPos, savePos               -- forward decls (row handlers use them)

    local function mkRow(key, label)
        local frame = Instance.new("Frame")
        frame.Name = key
        frame.BackgroundColor3 = Color3.fromRGB(13, 13, 17)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Size = UDim2.new(1, 0, 0, ROW_H)
        frame.ClipsDescendants = true
        frame.AutomaticSize = Enum.AutomaticSize.None
        frame.Active = true               -- catches drag input (grab any row to move)
        frame.Visible = false
        frame.Parent = indHolder

        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = frame

        -- subtle top→bottom glass gradient over the panel
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Color = ColorSequence.new(Color3.fromRGB(34, 34, 44), Color3.fromRGB(12, 12, 16))
        grad.Parent = frame

        -- thin outline (cheat-HUD signature)
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Color = Color3.fromRGB(255, 255, 255)
        stroke.Transparency = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = frame

        -- left accent chip
        local accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.BackgroundColor3 = Config.Ind_Accent
        accent.BorderSizePixel = 0
        accent.AnchorPoint = Vector2.new(0, 0.5)
        accent.Position = UDim2.new(0, 6, 0.5, -1)
        accent.Size = UDim2.new(0, 3, 1, -13)
        accent.Parent = frame
        local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1, 0); ac.Parent = accent

        -- label (uppercase, left)
        local lab = Instance.new("TextLabel")
        lab.Name = "Label"
        lab.BackgroundTransparency = 1
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 11
        lab.TextColor3 = Color3.fromRGB(178, 180, 194)
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.TextTransparency = 1
        lab.Position = UDim2.new(0, 16, 0, -2)
        lab.Size = UDim2.new(1, -84, 1, -5)
        lab.Text = label
        lab.Parent = frame

        -- value (right, heavy)
        local val = Instance.new("TextLabel")
        val.Name = "Value"
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.GothamBlack
        val.TextSize = 12
        val.TextColor3 = Color3.fromRGB(255, 255, 255)
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.TextTransparency = 1
        val.Position = UDim2.new(0, 0, 0, -2)
        val.Size = UDim2.new(1, -12, 1, -5)
        val.Text = ""
        val.Parent = frame

        -- bottom progress track + glossy fill
        local track = Instance.new("Frame")
        track.Name = "Track"
        track.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        track.BackgroundTransparency = 0.4
        track.BorderSizePixel = 0
        track.AnchorPoint = Vector2.new(0, 1)
        track.Position = UDim2.new(0, 6, 1, -4)
        track.Size = UDim2.new(1, -12, 0, 3)
        track.Parent = frame
        local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = track

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.BackgroundColor3 = Config.Ind_Accent
        fill.BorderSizePixel = 0
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.Parent = track
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill
        -- vertical gloss (colour stays solid; this is just a brightness gradient)
        local fgrad = Instance.new("UIGradient")
        fgrad.Rotation = 90
        fgrad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(1, 0.5),
        })
        fgrad.Parent = fill

        -- start a drag when this row is pressed
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                drag.active   = true
                drag.startIn  = Vector2.new(input.Position.X, input.Position.Y)
                drag.startPos = drag.target
            end
        end)
        frame.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                if drag.active then drag.active = false; savePos() end
            end
        end)

        return {
            key = key, frame = frame, accent = accent, fill = fill, track = track,
            stroke = stroke, label = lab, value = val, shown = false, dispRatio = 0,
        }
    end

    function clampPos(x, y)
        local vp = Camera.ViewportSize
        local h = #rowOrder * (ROW_H + ROW_GAP)
        x = math.clamp(x, 0, math.max(0, vp.X - IND_W))
        y = math.clamp(y, 0, math.max(0, vp.Y - h))
        return x, y
    end

    function savePos()
        if MacLibRef and POS_FLAG then
            pcall(function() MacLibRef:FALSetData(POS_FLAG, { x = drag.target.X, y = drag.target.Y }) end)
        end
    end

    local function buildIndicatorGui()
        if screenGui then return end
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "\0SylVis"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.DisplayOrder = 9999
        pcall(function() screenGui.Parent = guiParent() end)
        if not screenGui.Parent then screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        indHolder = Instance.new("Frame")
        indHolder.Name = "Indicators"
        indHolder.BackgroundTransparency = 1
        indHolder.AnchorPoint = Vector2.new(0, 0)
        indHolder.Size = UDim2.new(0, IND_W, 0, 0)
        indHolder.AutomaticSize = Enum.AutomaticSize.Y
        indHolder.Parent = screenGui

        -- default position: near the bottom-right; overwritten by the saved pos in buildUI
        local vp = Camera.ViewportSize
        local dx, dy = clampPos(vp.X - IND_W - 24, vp.Y - (#rowOrder * (ROW_H + ROW_GAP)) - 24)
        drag.target = Vector2.new(dx, dy)
        drag.disp   = Vector2.new(dx, dy)
        indHolder.Position = UDim2.fromOffset(dx, dy)

        -- global pointer-move drives the drag while a row is held
        dragConns[#dragConns + 1] = UserInputService.InputChanged:Connect(function(input)
            if not drag.active then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                local cur = Vector2.new(input.Position.X, input.Position.Y)
                local delta = cur - drag.startIn
                local nx, ny = clampPos(drag.startPos.X + delta.X, drag.startPos.Y + delta.Y)
                drag.target = Vector2.new(nx, ny)
            end
        end)

        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.VerticalAlignment = Enum.VerticalAlignment.Top
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, ROW_GAP)
        list.Parent = indHolder

        local labels = { Health = "HEALTH", Stamina = "STAMINA", IFrame = "IFRAME", M2 = "HEAVY", Dodge = "DODGE", Block = "BLOCK" }
        for i, key in ipairs(rowOrder) do
            local r = mkRow(key, labels[key])
            r.frame.LayoutOrder = i
            rows[key] = r
        end
    end

    -- restore the saved HUD position (called from buildUI once MacLib is available)
    local function restoreSavedPos()
        if not (MacLibRef and POS_FLAG) then return end
        pcall(function()
            local saved = MacLibRef.FALGetData and MacLibRef:FALGetData(POS_FLAG, nil)
            if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
                local nx, ny = clampPos(saved.x, saved.y)
                drag.target = Vector2.new(nx, ny)
                drag.disp   = Vector2.new(nx, ny)
                if indHolder then indHolder.Position = UDim2.fromOffset(nx, ny) end
            end
        end)
    end

    -- reset HUD back to the default bottom-right position
    local function resetPos()
        local vp = Camera.ViewportSize
        local dx, dy = clampPos(vp.X - IND_W - 24, vp.Y - (#rowOrder * (ROW_H + ROW_GAP)) - 24)
        drag.target = Vector2.new(dx, dy)
        savePos()
    end

    -- appear / disappear animation for a row
    local function setRowShown(r, shown)
        if r.shown == shown then return end
        r.shown = shown
        if shown then
            r.frame.Visible = true
            TweenService:Create(r.frame, TW_IN, { BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, ROW_H) }):Play()
            TweenService:Create(r.stroke, TW_IN, { Transparency = 0.75 }):Play()
            TweenService:Create(r.label, TW_IN, { TextTransparency = 0 }):Play()
            TweenService:Create(r.value, TW_IN, { TextTransparency = 0 }):Play()
        else
            TweenService:Create(r.frame, TW_OUT, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) }):Play()
            TweenService:Create(r.stroke, TW_OUT, { Transparency = 1 }):Play()
            TweenService:Create(r.label, TW_OUT, { TextTransparency = 1 }):Play()
            local t = TweenService:Create(r.value, TW_OUT, { TextTransparency = 1 })
            t.Completed:Connect(function() if not r.shown then r.frame.Visible = false end end)
            t:Play()
        end
    end

    -- dynamic-measured cooldown state (for boolean-attribute cooldowns like M2)
    local m2Track   = { active = false, t0 = 0, dur = 7 }
    local staminaMax = 100

    -- read every LOCAL indicator's { show, ratio, text, color }
    local function readIndicator(key, char, hum)
        local A = function(n) return char:GetAttribute(n) end

        if key == "Health" then
            if not Config.Ind_Health or not hum then return false end
            local r = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local col = lerpColor(Color3.fromRGB(255, 70, 70), Color3.fromRGB(90, 220, 90), r)
            return true, r, string.format("%d", math.floor(hum.Health + 0.5)), col

        elseif key == "Stamina" then
            if not Config.Ind_Stamina then return false end
            local s = A("Stamina")
            if type(s) ~= "number" then return false end
            if s > staminaMax then staminaMax = s end
            local r = math.clamp(s / math.max(staminaMax, 1), 0, 1)
            return true, r, string.format("%d", math.floor(s + 0.5)), Config.Ind_Accent

        elseif key == "IFrame" then
            if not Config.Ind_IFrame then return false end
            if A("IFRAMES") == true then
                return true, 1, "ACTIVE", Color3.fromRGB(150, 120, 255)
            end
            local cd = A("IFRAMECD")
            if type(cd) == "number" and cd > 0.02 then
                return true, math.clamp(cd / 0.3, 0, 1), string.format("%.1fs", cd), Color3.fromRGB(150, 120, 255)
            end
            return false

        elseif key == "M2" then
            if not Config.Ind_M2 then return false end
            -- boolean attribute → mirror the client's own timer (exact dur from config)
            local on = A("M2Cooldown") == true
            if on and not m2Track.active then
                m2Track.active = true; m2Track.t0 = time(); m2Track.dur = cfgM2Cooldown(char)
            elseif not on and m2Track.active then
                m2Track.active = false
            end
            if not on then return false end
            local remaining = math.max(0, m2Track.dur - (time() - m2Track.t0))
            return true, math.clamp(remaining / math.max(m2Track.dur, 0.01), 0, 1),
                   string.format("%.1fs", remaining), Color3.fromRGB(255, 150, 60)

        elseif key == "Dodge" then
            if not Config.Ind_Dodge then return false end
            local rem = A("EvasiveCooldownRemaining")
            if type(rem) == "number" and rem > 0.02 then
                local dur = cfgEvasiveCooldown(char)
                return true, math.clamp(rem / math.max(dur, 0.01), 0, 1),
                       string.format("%.1fs", rem), Color3.fromRGB(120, 220, 255)
            end
            return false

        elseif key == "Block" then
            if not Config.Ind_Block then return false end
            local bc = A("BlockCooldown")
            if type(bc) == "number" and bc > 0.02 then
                return true, math.clamp(bc / 1.5, 0, 1), string.format("%.1fs", bc), Color3.fromRGB(90, 180, 255)
            elseif bc == true then
                return true, 1, "CD", Color3.fromRGB(90, 180, 255)
            end
            return false
        end
        return false
    end

    local function updateIndicators(dt)
        -- smooth drag follow (runs whenever the HUD exists so it eases into place)
        if indHolder then
            drag.disp = drag.disp:Lerp(drag.target, math.clamp(dt * 16, 0, 1))
            indHolder.Position = UDim2.fromOffset(math.floor(drag.disp.X + 0.5), math.floor(drag.disp.Y + 0.5))
        end
        if not (Config.Ind_On and indHolder) then
            if indHolder then for _, r in pairs(rows) do setRowShown(r, false) end end
            return
        end
        local char = getChar(LocalPlayer)
        local hum  = getHum(char)
        if not char then for _, r in pairs(rows) do setRowShown(r, false) end return end

        local a = math.clamp(dt * 12, 0, 1)  -- lerp factor for smooth value motion
        for _, key in ipairs(rowOrder) do
            local r = rows[key]
            local show, ratio, text, color = readIndicator(key, char, hum)
            setRowShown(r, show and true or false)
            if show then
                r.dispRatio = lerp(r.dispRatio, ratio, a)
                r.fill.Size = UDim2.new(math.clamp(r.dispRatio, 0, 1), 0, 1, 0)
                r.fill.BackgroundColor3 = color
                r.accent.BackgroundColor3 = color
                r.value.Text = text
            end
        end
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- HIT DIRECTION  (fading arrows around the crosshair)
    -- ═══════════════════════════════════════════════════════════════════════
    local hitArrows = {}          -- active { tri, born, angle }
    local ARROW_LIFE = 1.1
    local lastHealth = nil

    local function spawnHitArrow(angle)
        if not hasDrawing then return end
        local tri = newDrawing("Triangle", { Thickness = 1, Filled = true, Visible = true, Color = Config.HitDir_Color })
        hitArrows[#hitArrows + 1] = { tri = tri, born = os.clock(), angle = angle }
    end

    local function nearestAttackerAngle()
        local char = getChar(LocalPlayer)
        local root = char and getRoot(char)
        if not root then return nil end
        local best, bestD
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local c = getChar(plr); local r = c and getRoot(c)
                if r and isAlive(c) then
                    local d = (r.Position - root.Position).Magnitude
                    if d < 60 and (not bestD or d < bestD) then bestD = d; best = r end
                end
            end
        end
        if not best then return nil end
        local rel = best.Position - root.Position
        local look = Camera.CFrame.LookVector
        local flatRel  = Vector3.new(rel.X, 0, rel.Z)
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatRel.Magnitude < 0.01 or flatLook.Magnitude < 0.01 then return 0 end
        flatRel = flatRel.Unit; flatLook = flatLook.Unit
        local dot = math.clamp(flatLook:Dot(flatRel), -1, 1)
        local ang = math.acos(dot)
        if flatLook:Cross(flatRel).Y < 0 then ang = -ang end
        return ang
    end

    local function updateHitDir()
        if not hasDrawing then return end
        local vp = Camera.ViewportSize
        local cx, cy = vp.X / 2, vp.Y / 2
        local radius = 90
        local now = os.clock()
        for i = #hitArrows, 1, -1 do
            local h = hitArrows[i]
            local age = now - h.born
            if age > ARROW_LIFE or not Config.HitDir_On then
                pcall(function() h.tri:Remove() end)
                table.remove(hitArrows, i)
            else
                local a = h.angle
                -- angle 0 = attacker in front (arrow at top), positive = to the right
                local dirx, diry = math.sin(a), -math.cos(a)
                local tipx, tipy = cx + dirx * (radius + 14), cy + diry * (radius + 14)
                local bx, by = cx + dirx * radius, cy + diry * radius
                local perpx, perpy = -diry, dirx
                local w = 9
                h.tri.PointA = Vector2.new(tipx, tipy)
                h.tri.PointB = Vector2.new(bx + perpx * w, by + perpy * w)
                h.tri.PointC = Vector2.new(bx - perpx * w, by - perpy * w)
                local t = 1 - (age / ARROW_LIFE)
                h.tri.Transparency = t
                h.tri.Color = Config.HitDir_Color
                h.tri.Visible = true
            end
        end
    end

    local function onLocalDamage()
        if not Config.HitDir_On then return end
        local ang = nearestAttackerAngle()
        if ang then spawnHitArrow(ang) end
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- Lifecycle wiring
    -- ═══════════════════════════════════════════════════════════════════════
    local conns = {}
    local function track(sig, fn) conns[#conns + 1] = sig:Connect(fn) end

    local function hookLocalHumanoid()
        local char = getChar(LocalPlayer)
        local hum = getHum(char)
        if not hum then return end
        lastHealth = hum.Health
        track(hum.HealthChanged, function(h)
            if lastHealth and h < lastHealth - 0.5 then onLocalDamage() end
            lastHealth = h
        end)
    end

    local started = false
    local function startRuntime()
        if started then return end
        started = true

        buildIndicatorGui()
        hookLocalHumanoid()

        track(LocalPlayer.CharacterAdded, function()
            task.wait(0.4)
            m2Track.active = false
            hookLocalHumanoid()
        end)
        track(Players.PlayerRemoving, function(plr) destroyEsp(plr) end)

        -- master render loop
        track(RunService.RenderStepped, function(dt)
            -- ESP
            if hasDrawing then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then updateEspFor(plr) end
                end
            end
            -- Indicators + hit direction
            updateIndicators(dt)
            updateHitDir()
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- Module contract
    -- ═══════════════════════════════════════════════════════════════════════
    local M = {}

    function M.start()
        Config.ESP_On    = false
        Config.Ind_On    = false
        Config.HitDir_On = false
        startRuntime()
    end

    function M.buildUI(ctx)
        local uiReady = false
        local function notify(title, body)
            if uiReady then pcall(ctx.notify, title, body) end
        end

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

        local function boolToggle(section, name, title, get, set)
            section:Toggle({
                Name = name, Default = get(),
                Callback = function(v)
                    set(v and true or false)
                    notify(title, v and "Enabled" or "Disabled")
                end,
            }, ctx.flag(name:gsub("%s+", "") .. "_T"))
        end

        local function slider(section, o)
            section:Slider({
                Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
                Precision = o.Precision or 0, Suffix = o.Suffix, Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        local function colorpick(section, name, flag, default, set)
            section:Colorpicker({ Name = name, Default = default, Callback = function(c) set(c) end }, ctx.flag(flag))
        end

        -- Persist the HUD position via MacLib's FAL Data API, then restore it.
        MacLibRef = ctx.MacLib
        POS_FLAG  = ctx.flag("VIS_IND_Pos")
        restoreSavedPos()

        local V = ctx.tabs.Visuals

        -- ─────────────── Section 1: ESP (Left) ───────────────
        local sEsp = V:Section({ Side = "Left" })
        sEsp:Header({ Name = "ESP" })
        feature(sEsp, {
            Title = "ESP", Flag = "VIS_ESP",
            get = function() return Config.ESP_On end,
            set = function(v) Config.ESP_On = v end,
            Desc = "Draws players through the world: box, name, distance, health, combat state & style.",
        })
        boolToggle(sEsp, "Box",      "ESP Box",      function() return Config.ESP_Box end,      function(v) Config.ESP_Box = v end)
        boolToggle(sEsp, "Name",     "ESP Name",     function() return Config.ESP_Name end,     function(v) Config.ESP_Name = v end)
        boolToggle(sEsp, "Distance", "ESP Distance", function() return Config.ESP_Distance end, function(v) Config.ESP_Distance = v end)
        boolToggle(sEsp, "Health Bar", "ESP Health", function() return Config.ESP_Health end,   function(v) Config.ESP_Health = v end)
        boolToggle(sEsp, "Heavy (M2) Bar", "ESP M2Bar", function() return Config.ESP_M2Bar end, function(v) Config.ESP_M2Bar = v end)
        boolToggle(sEsp, "Combat State", "ESP State", function() return Config.ESP_State end,    function(v) Config.ESP_State = v end)
        boolToggle(sEsp, "Combat Style", "ESP Style", function() return Config.ESP_Style end,    function(v) Config.ESP_Style = v end)
        boolToggle(sEsp, "Skeleton", "ESP Skeleton", function() return Config.ESP_Skeleton end, function(v) Config.ESP_Skeleton = v end)
        boolToggle(sEsp, "Tracer",   "ESP Tracer",   function() return Config.ESP_Tracer end,   function(v) Config.ESP_Tracer = v end)
        slider(sEsp, { Name = "Max Distance", Flag = "VIS_ESP_Dist", Default = Config.ESP_MaxDist,
            Min = 100, Max = 3000, Suffix = "m", Callback = function(v) Config.ESP_MaxDist = v end })
        colorpick(sEsp, "Box Color", "VIS_ESP_BoxCol", Config.ESP_Box_Color, function(c) Config.ESP_Box_Color = c end)
        colorpick(sEsp, "Text Color", "VIS_ESP_TxtCol", Config.ESP_Text_Color, function(c) Config.ESP_Text_Color = c end)
        colorpick(sEsp, "Heavy (M2) Bar Color", "VIS_ESP_M2Col", Config.ESP_M2_Color, function(c) Config.ESP_M2_Color = c end)
        if not hasDrawing then
            sEsp:SubLabel({ Text = "Drawing API not available in this executor - ESP/Hit Direction disabled." })
        end

        -- ─────────────── Section 2: Indicators (Right) ───────────────
        local sInd = V:Section({ Side = "Right" })
        sInd:Header({ Name = "Indicators" })
        feature(sInd, {
            Title = "Indicators", Flag = "VIS_IND",
            get = function() return Config.Ind_On end,
            set = function(v) Config.Ind_On = v end,
            Desc = "Animated HUD stack of your own combat data - slides in when relevant, out when not.",
        })
        boolToggle(sInd, "Health",       "Ind Health",  function() return Config.Ind_Health end,  function(v) Config.Ind_Health = v end)
        boolToggle(sInd, "Stamina",      "Ind Stamina", function() return Config.Ind_Stamina end, function(v) Config.Ind_Stamina = v end)
        boolToggle(sInd, "IFrame",       "Ind IFrame",  function() return Config.Ind_IFrame end,  function(v) Config.Ind_IFrame = v end)
        boolToggle(sInd, "Heavy (M2) CD", "Ind Heavy",  function() return Config.Ind_M2 end,      function(v) Config.Ind_M2 = v end)
        boolToggle(sInd, "Dodge CD",     "Ind Dodge",   function() return Config.Ind_Dodge end,   function(v) Config.Ind_Dodge = v end)
        boolToggle(sInd, "Block CD",     "Ind Block",   function() return Config.Ind_Block end,   function(v) Config.Ind_Block = v end)
        colorpick(sInd, "Accent Color", "VIS_IND_Accent", Config.Ind_Accent, function(c) Config.Ind_Accent = c end)
        pcall(function()
            sInd:Button({ Name = "Reset HUD Position", Callback = function() resetPos() end })
        end)
        sInd:SubLabel({ Text = "Drag the HUD anywhere to move it - the position is saved automatically." })
        sInd:SubLabel({ Text = "Heavy/Dodge cooldowns are read from the game's own combat config for exact timing." })

        -- ─────────────── Section 3: Hit Direction (Right) ───────────────
        local sHit = V:Section({ Side = "Right" })
        sHit:Header({ Name = "Hit Direction" })
        feature(sHit, {
            Title = "Hit Direction", Flag = "VIS_HITDIR",
            get = function() return Config.HitDir_On end,
            set = function(v) Config.HitDir_On = v end,
            Desc = "Fading arrows around the crosshair pointing at whoever is hitting you.",
        })
        colorpick(sHit, "Arrow Color", "VIS_HIT_Col", Config.HitDir_Color, function(c) Config.HitDir_Color = c end)

        uiReady = true
    end

    function M.stop()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        for _, c in ipairs(dragConns) do pcall(function() c:Disconnect() end) end
        dragConns = {}
        for plr in pairs(espPool) do destroyEsp(plr) end
        for _, h in ipairs(hitArrows) do pcall(function() h.tri:Remove() end) end
        hitArrows = {}
        if screenGui then pcall(function() screenGui:Destroy() end); screenGui = nil end
    end

    return M
end
