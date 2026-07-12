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
        Ind_Style   = "Panel",   -- "Panel" | "Player" | "Simple"
        Ind_PlayerSide = "Left", -- "Left" | "Right" | "Bottom" (Player style only)
        Ind_Health  = true,
        Ind_Stamina = true,
        Ind_IFrame  = true,
        Ind_M2      = true,
        Ind_Dodge   = true,
        Ind_Block   = true,
        Ind_Accent  = Color3.fromRGB(72, 138, 255),   -- watermark blue
        Ind_ScreenY = 0.60,      -- vertical position (frac) for screen-anchored styles
        Ind_Scale   = 1.0,       -- extra manual scale multiplier for Drawing styles

        -- Hit direction
        HitDir_On    = false,
        HitDir_Color = Color3.fromRGB(255, 74, 74),
    }

    -- ── Watermark palette (shared by every indicator style) ──────────────────
    local WM = {
        bgDark  = Color3.fromRGB(14, 14, 20),
        bgChip  = Color3.fromRGB(9, 9, 14),
        stroke  = Color3.fromRGB(52, 52, 74),
        txtMain = Color3.fromRGB(255, 255, 255),        -- value text: pure white
        txtMute = Color3.fromRGB(214, 216, 226),        -- label text: near-white
        accent2 = Color3.fromRGB(140, 90, 255),         -- watermark purple (secondary)
        bgTransp = 0.22,
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
    -- ���══════════════════════════════════════════════════════════════════════
    local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

    -- Skeleton is drawn from computed JOINT points, not raw part centres. Shoulders and
    -- hips are placed at the TOP / BOTTOM edge of the torso (offset along the torso's own
    -- up/right axes) so the shoulder line sits where real shoulders are — connecting arms
    -- to the torso centre (the old behaviour) put the shoulders far too low.
    local SKELETON_MAX = 24

    -- R15 bone list, referencing keys resolved by skeletonPoints()
    local BONES_R15 = {
        { "Neck", "ShoulderL" }, { "Neck", "ShoulderR" },   -- shoulder line
        { "Neck", "Chest" }, { "Chest", "Hip" },            -- spine
        { "ShoulderL", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "ShoulderR", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "HipL", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "HipR", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
    }
    -- R6 fallback (Torso is a single part; shoulders/hips offset from it)
    local BONES_R6 = {
        { "ShoulderL", "ShoulderR" },
        { "Neck", "Chest" },
        { "ShoulderL", "Left Arm" }, { "ShoulderR", "Right Arm" },
        { "HipL", "Left Leg" }, { "HipR", "Right Leg" },
    }

    -- Resolve world-space joint points for the character. Returns (points, bones, headPart).
    local function skeletonPoints(char)
        local head = char:FindFirstChild("Head")
        local uT   = char:FindFirstChild("UpperTorso")
        local pts  = {}
        local function pp(n) local p = char:FindFirstChild(n); return p and p.Position or nil end
        if uT then
            -- R15
            local cf = uT.CFrame
            local up, rt = cf.UpVector, cf.RightVector
            local hy, hx = uT.Size.Y * 0.5, uT.Size.X * 0.5
            local neck = uT.Position + up * hy
            local lT = char:FindFirstChild("LowerTorso")
            -- pelvis: bottom face of the LowerTorso (where the legs actually attach), and
            -- hip width from the LowerTorso's OWN size — using the UpperTorso size put the
            -- hips too high and too wide, so the thighs splayed out incorrectly.
            local hipCenter, lup, lrt, lhx, lhy
            if lT then
                lup, lrt = lT.CFrame.UpVector, lT.CFrame.RightVector
                lhx, lhy = lT.Size.X * 0.5, lT.Size.Y * 0.5
                hipCenter = lT.Position
            else
                lup, lrt, lhx, lhy, hipCenter = up, rt, hx, hy, uT.Position - up * hy
            end
            local pelvis = hipCenter - lup * lhy       -- bottom of the pelvis
            pts.Neck      = neck
            pts.Chest     = uT.Position
            pts.Hip       = hipCenter
            pts.ShoulderL = neck - rt * hx
            pts.ShoulderR = neck + rt * hx
            pts.HipL      = pelvis - lrt * (lhx * 0.5)
            pts.HipR      = pelvis + lrt * (lhx * 0.5)
            for _, n in ipairs({ "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }) do
                pts[n] = pp(n)
            end
            return pts, BONES_R15, head
        end
        local torso = char:FindFirstChild("Torso")
        if torso then
            -- R6
            local cf = torso.CFrame
            local up, rt = cf.UpVector, cf.RightVector
            local hy, hx = torso.Size.Y * 0.5, torso.Size.X * 0.5
            local neck = torso.Position + up * hy
            local hip  = torso.Position - up * hy
            pts.Neck      = neck
            pts.Chest     = torso.Position
            pts.ShoulderL = neck - rt * hx
            pts.ShoulderR = neck + rt * hx
            pts.HipL      = hip - rt * (hx * 0.6)
            pts.HipR      = hip + rt * (hx * 0.6)
            for _, n in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
                pts[n] = pp(n)
            end
            return pts, BONES_R6, head
        end
        return pts, BONES_R15, head
    end

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
        -- skeleton head circle
        o.headCircle = newDrawing("Circle", { Thickness = 1, Filled = false, NumSides = 24, Radius = 6, Visible = false, Color = Color3.fromRGB(255, 255, 255), ZIndex = 2 })
        o.bones = {}
        for i = 1, SKELETON_MAX do
            o.bones[i] = newDrawing("Line", { Thickness = 1, Visible = false, Color = Color3.fromRGB(255, 255, 255) })
        end
        espPool[plr] = o
        return o
    end

    local function hideEsp(o)
        if not o then return end
        for _, key in ipairs(TEXT_KEYS) do if o[key] then o[key].Visible = false end end
        for _, key in ipairs(BAR_KEYS)  do if o[key] then o[key].Visible = false end end
        if o.headCircle then o.headCircle.Visible = false end
        for _, b in ipairs(o.bones) do b.Visible = false end
    end

    local function destroyEsp(plr)
        local o = espPool[plr]
        if not o then return end
        for _, key in ipairs(TEXT_KEYS) do if o[key] then pcall(function() o[key]:Remove() end) end end
        for _, key in ipairs(BAR_KEYS)  do if o[key] then pcall(function() o[key]:Remove() end) end end
        if o.headCircle then pcall(function() o.headCircle:Remove() end) end
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

        -- STATIC 2D box, anchored to the ROOT PART world position (exactly like the
        -- "Player" indicator style, which the user confirmed does NOT drift under
        -- shiftlock). Height comes from the bounding-box vertical extent applied along
        -- WORLD-up from the root; width is a fixed portrait ratio of that height. Because
        -- nothing here reads the model's orientation/CFrame, shiftlock (which yaws the
        -- character toward the camera) can no longer shift or breathe the box.
        local _, size = char:GetBoundingBox()
        local anchor = root.Position
        local halfH  = size.Y * 0.5
        local topSp, onT = Camera:WorldToViewportPoint(anchor + Vector3.new(0, halfH, 0))
        local botSp, onB = Camera:WorldToViewportPoint(anchor - Vector3.new(0, halfH, 0))
        if not (onT or onB) then hideEsp(o); return end

        local topY = math.min(topSp.Y, botSp.Y)
        local botY = math.max(topSp.Y, botSp.Y)
        local bh = botY - topY
        local bw = bh * 0.62                    -- fixed aspect → constant, no breathing
        local cxs = (topSp.X + botSp.X) * 0.5
        local bx, by = cxs - bw * 0.5, topY

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

        -- Skeleton (computed joints + head circle)
        if Config.ESP_Skeleton then
            local pts, bones, headPart = skeletonPoints(char)
            local col = Config.ESP_Box_Color
            local used = 0
            for _, pair in ipairs(bones) do
                local a, b = pts[pair[1]], pts[pair[2]]
                used = used + 1
                local line = o.bones[used]
                if a and b then
                    local s0, on0 = Camera:WorldToViewportPoint(a)
                    local s1, on1 = Camera:WorldToViewportPoint(b)
                    if on0 or on1 then
                        line.From = Vector2.new(s0.X, s0.Y)
                        line.To   = Vector2.new(s1.X, s1.Y)
                        line.Color = col
                        line.Visible = true
                    else
                        line.Visible = false
                    end
                else
                    line.Visible = false
                end
            end
            for i = used + 1, #o.bones do o.bones[i].Visible = false end

            -- head circle: radius from the head part's projected vertical size
            if headPart then
                local hc = headPart.Position
                local hs = (headPart:IsA("BasePart") and headPart.Size.Y or 1) * 0.5
                local cS, onC = Camera:WorldToViewportPoint(hc)
                local tS      = Camera:WorldToViewportPoint(hc + Vector3.new(0, hs, 0))
                if onC then
                    o.headCircle.Position = Vector2.new(cS.X, cS.Y)
                    o.headCircle.Radius = math.max(2, math.abs(cS.Y - tS.Y) + 1)
                    o.headCircle.Color = col
                    o.headCircle.Visible = true
                else
                    o.headCircle.Visible = false
                end
            else
                o.headCircle.Visible = false
            end
        else
            for _, b in ipairs(o.bones) do b.Visible = false end
            o.headCircle.Visible = false
        end
    end

    -- ═══════════════════════════════════════════════════════════════��═══════
    -- INDICATORS  (Neverlose-style animated GUI)
    -- ══════════════���════════════════════════════════════════════════════════
    local function guiParent()
        local ok, hui = pcall(function() return (type(gethui) == "function") and gethui() or nil end)
        if ok and hui then return hui end
        return cref(game:GetService("CoreGui"))
    end

    local screenGui, indHolder, indUIScale
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

        frame.BackgroundColor3 = WM.bgDark
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = frame

        -- watermark-style border
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Color = WM.stroke
        stroke.Transparency = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = frame

        -- horizontal progress fill sits BEHIND the text as a dim backdrop (the look the
        -- user preferred). It never touches the accent bar, so nothing looks crooked.
        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.BackgroundColor3 = Config.Ind_Accent
        fill.BackgroundTransparency = 0.8
        fill.BorderSizePixel = 0
        fill.ZIndex = 2
        fill.Position = UDim2.new(0, 0, 0, 0)
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.Parent = frame
        local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 6); fc.Parent = fill

        -- left accent bar: clean vertical strip flush to the left edge, perfectly
        -- centered vertically. Rounded pill, sits above the fill.
        local accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.BackgroundColor3 = Config.Ind_Accent
        accent.BorderSizePixel = 0
        accent.ZIndex = 4
        accent.AnchorPoint = Vector2.new(0, 0.5)
        accent.Position = UDim2.new(0, 4, 0.5, 0)
        accent.Size = UDim2.new(0, 3, 1, -10)
        accent.Parent = frame
        local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1, 0); ac.Parent = accent

        -- label (uppercase, left)
        local lab = Instance.new("TextLabel")
        lab.Name = "Label"
        lab.BackgroundTransparency = 1
        lab.ZIndex = 4
        lab.Font = Enum.Font.GothamMedium
        lab.TextSize = 12
        lab.TextColor3 = WM.txtMute
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.TextTransparency = 1
        lab.Position = UDim2.new(0, 14, 0, 0)
        lab.Size = UDim2.new(1, -84, 1, 0)
        lab.Text = label
        lab.Parent = frame

        -- value (right, heavy)
        local val = Instance.new("TextLabel")
        val.Name = "Value"
        val.BackgroundTransparency = 1
        val.ZIndex = 4
        val.Font = Enum.Font.GothamBold
        val.TextSize = 12
        val.TextColor3 = WM.txtMain
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.TextTransparency = 1
        val.Position = UDim2.new(0, 0, 0, 0)
        val.Size = UDim2.new(1, -12, 1, 0)
        val.Text = ""
        val.Parent = frame

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
            key = key, frame = frame, accent = accent, fill = fill,
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

        -- auto-rescale for mobile / small screens
        indUIScale = Instance.new("UIScale")
        indUIScale.Scale = 1
        indUIScale.Parent = indHolder

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
            TweenService:Create(r.frame, TW_IN, { BackgroundTransparency = WM.bgTransp, Size = UDim2.new(1, 0, 0, ROW_H) }):Play()
            TweenService:Create(r.stroke, TW_IN, { Transparency = 0 }):Play()
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

    -- ── Client-side cooldown prediction ─────────────────────────────────────
    -- The game replicates most cooldowns as a value that is written ONCE at the
    -- start (or a plain boolean) and only cleared when it ends — it never counts
    -- down over the wire. So a raw read shows a frozen "1.5s". To make the number
    -- and bar actually tick (1.5 → 1.4 → ...), we snapshot the duration on the
    -- rising edge and interpolate the remainder locally with time().
    local cdTracks = {}   -- [key] = { active, deadline, dur, lastRaw, t0, measured }
    local function cdGet(key)
        local t = cdTracks[key]
        if not t then t = { active = false, deadline = 0, dur = 0, lastRaw = nil, t0 = 0, measured = nil }; cdTracks[key] = t end
        return t
    end

    -- Deadline-based cooldown, mirroring the game's own syncCooldownFromServer:
    --   • the cooldown is gated by a BOOLEAN attribute (M2Cooldown / IFRAMECD);
    --   • an optional NUMERIC "remaining" (EvasiveCooldownRemaining) is written once
    --     and re-synced occasionally — it does NOT tick over the wire;
    --   • so we snapshot a local deadline on the rising edge (and re-snapshot only when
    --     the numeric value actually CHANGES) and predict the countdown with os.clock().
    -- `fullDur` is the bar's 100% reference (kept constant so the bar doesn't jump).
    local function trackGate(key, gateActive, remRaw, fullDur)
        local t = cdGet(key)
        if not gateActive then t.active = false; t.lastRaw = nil; return nil end
        local now = os.clock()
        if type(remRaw) == "number" and remRaw > 0 then
            if remRaw ~= t.lastRaw then t.deadline = now + remRaw; t.lastRaw = remRaw end
            t.active = true
        elseif not t.active then
            t.active = true; t.deadline = now + fullDur; t.lastRaw = nil
        end
        t.dur = (fullDur and fullDur > 0) and fullDur or (t.deadline - t.t0)
        local rem = math.max(0, t.deadline - now)
        return rem, math.clamp(rem / math.max(fullDur, 0.01), 0, 1)
    end

    -- Boolean cooldown of UNKNOWN duration (BlockCooldown — the server never tells the
    -- client how long it lasts). We LEARN the duration by measuring the first full cycle,
    -- then show an accurate countdown on subsequent cooldowns. Returns rem, ratio, known.
    local function trackMeasured(key, active)
        local t = cdGet(key)
        local now = os.clock()
        if active then
            if not t.active then t.active = true; t.t0 = now end
            local elapsed = now - t.t0
            if t.measured and t.measured > 0.05 then
                local rem = math.max(0, t.measured - elapsed)
                return rem, math.clamp(rem / t.measured, 0, 1), true
            end
            return 0, 1, false            -- duration not learned yet → pulsing full bar
        else
            if t.active then t.measured = math.clamp(now - t.t0, 0.1, 10); t.active = false end
            return nil
        end
    end

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
            -- IFRAMES is the brief active-invulnerability window (boolean). Too short to
            -- count down meaningfully, so just flag it ACTIVE while it's up.
            if not Config.Ind_IFrame then return false end
            if A("IFRAMES") == true then
                return true, 1, "ACTIVE", Color3.fromRGB(150, 120, 255)
            end
            return false

        elseif key == "M2" then
            -- Heavy: boolean gate + exact duration from CombatConfig.
            if not Config.Ind_M2 then return false end
            local rem, r = trackGate("M2", A("M2Cooldown") == true, nil, cfgM2Cooldown(char))
            if rem and rem > 0.02 then return true, r, string.format("%.1fs", rem), Color3.fromRGB(255, 150, 60) end
            return false

        elseif key == "Dodge" then
            -- Dodge: gated by IFRAMECD(bool); EvasiveCooldownRemaining(number) seeds the
            -- deadline; full reference = config evasive cooldown. This is exactly how the
            -- game predicts it, so no more 1.4↔1.5 cycling while moving.
            if not Config.Ind_Dodge then return false end
            local rem, r = trackGate("Dodge", A("IFRAMECD") == true, A("EvasiveCooldownRemaining"), cfgEvasiveCooldown(char))
            if rem and rem > 0.02 then return true, r, string.format("%.1fs", rem), Color3.fromRGB(120, 220, 255) end
            return false

        elseif key == "Block" then
            -- Block: boolean of unknown duration → self-learning measured countdown.
            if not Config.Ind_Block then return false end
            local rem, r, known = trackMeasured("Block", A("BlockCooldown") == true)
            if rem ~= nil then
                if known then return true, r, string.format("%.1fs", rem), Color3.fromRGB(90, 180, 255) end
                return true, 1, "CD", Color3.fromRGB(90, 180, 255)
            end
            return false
        end
        return false
    end

    -- short labels used by the minimalist Drawing styles
    local STAT_LABELS = { Health = "HP", Stamina = "STAMINA", IFrame = "IFRAME", M2 = "HEAVY", Dodge = "DODGE", Block = "BLOCK" }

    -- ordered list of currently-active local stats { key, ratio, text, color }
    local function collectStats(char, hum)
        local list = {}
        for _, key in ipairs(rowOrder) do
            local show, ratio, text, color = readIndicator(key, char, hum)
            if show then
                list[#list + 1] = { key = key, ratio = ratio or 0, text = text or "", color = color or Config.Ind_Accent }
            end
        end
        return list
    end

    -- Drawing indicator STYLE definitions (clean, NO background panel — just text +
    -- a thin accent bar per row, white text). Only two Drawing styles exist:
    --   Simple – a centred stack near the middle-bottom of the screen
    --   Player – a stack pinned to the side of the local player (left/right/bottom)
    local STYLE_DEFS = {
        Simple = { width = 190, row = 27, txt = 15 },
        Player = { width = 150, row = 22, txt = 13 },
    }
    local DRAW_STYLES = { Simple = true, Player = true }

    -- ── Drawing-based cell pool (text + thin bar per row, no chrome) ─────────
    local drawCells = {}
    local function textWidth(d)
        local ok, b = pcall(function() return d.TextBounds end)
        if ok and b and b.X and b.X > 0 then return b.X end
        return #tostring(d.Text) * (d.Size * 0.55)
    end
    local function getDrawCell(key)
        local c = drawCells[key]
        if c then return c end
        c = {
            label = newDrawing("Text", { Size = 13, Font = 2, Center = false, Outline = true, OutlineColor = Color3.new(0,0,0), Visible = false, Color = WM.txtMute, ZIndex = 7 }),
            value = newDrawing("Text", { Size = 13, Font = 2, Center = false, Outline = true, OutlineColor = Color3.new(0,0,0), Visible = false, Color = WM.txtMain, ZIndex = 7 }),
            track = newDrawing("Line", { Thickness = 2, Visible = false, Color = WM.stroke, ZIndex = 6, Transparency = 0 }),
            fill  = newDrawing("Line", { Thickness = 2, Visible = false, Color = Config.Ind_Accent, ZIndex = 7, Transparency = 0 }),
            alpha = 0, dispRatio = 0, y = 0, hasY = false,
        }
        drawCells[key] = c
        return c
    end
    local function hideDrawCell(c)
        c.label.Visible = false; c.value.Visible = false; c.track.Visible = false; c.fill.Visible = false
    end
    local function hideAllDrawCells()
        for _, c in pairs(drawCells) do c.alpha = 0; c.hasY = false; hideDrawCell(c) end
    end

    -- viewport-relative UI scale so every Drawing style stays readable on phones
    local function uiScale()
        local vp = Camera.ViewportSize
        local s  = math.clamp(vp.Y / 864, 0.85, 1.7)
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then s = s * 1.18 end
        return s * math.clamp(Config.Ind_Scale or 1, 0.5, 2.5)
    end

    -- Animated vertical stack drawn as clean text rows with a thin accent progress bar
    -- underneath each. No background box. Rows ease into their slot and fade in/out.
    -- (centerX, topY) is the top-centre of the block.
    local function renderDrawStack(stats, dt, def, centerX, topY, sc)
        local width, step, txtSize = def.width * sc, def.row * sc, def.txt * sc
        local left, right = centerX - width / 2, centerX + width / 2
        local aA = math.clamp(dt * 12, 0, 1)

        local activeMap = {}
        for i, s in ipairs(stats) do activeMap[s.key] = { idx = i, stat = s } end
        for _, key in ipairs(rowOrder) do
            local c  = getDrawCell(key)
            local am = activeMap[key]
            c.alpha = lerp(c.alpha, am and 1 or 0, aA)
            if am then
                local slotY = topY + (am.idx - 1) * step
                if not c.hasY then c.y = slotY + 8 * sc; c.hasY = true end
                c.y = lerp(c.y, slotY, aA)
            end
            if c.alpha < 0.02 then
                hideDrawCell(c); if not am then c.hasY = false end
            else
                local rowY  = c.y
                local ratio = am and am.stat.ratio or c.dispRatio
                c.dispRatio = lerp(c.dispRatio, ratio, aA)
                local col   = am and am.stat.color or Config.Ind_Accent

                c.label.Size = txtSize
                c.label.Text = STAT_LABELS[key] or key
                c.label.Position = Vector2.new(left, rowY)
                c.label.Color = WM.txtMute
                c.label.Transparency = c.alpha
                c.label.Visible = true

                if am then c.value.Text = am.stat.text end
                c.value.Size = txtSize
                c.value.Position = Vector2.new(right - textWidth(c.value), rowY)
                c.value.Color = WM.txtMain
                c.value.Transparency = c.alpha
                c.value.Visible = true

                local lineY = rowY + txtSize + 4 * sc
                c.track.From = Vector2.new(left, lineY); c.track.To = Vector2.new(right, lineY)
                c.track.Thickness = math.max(1, 2 * sc)
                c.track.Color = WM.stroke; c.track.Transparency = c.alpha * 0.5; c.track.Visible = true

                local fillW = width * math.clamp(c.dispRatio, 0, 1)
                c.fill.From = Vector2.new(left, lineY); c.fill.To = Vector2.new(left + fillW, lineY)
                c.fill.Thickness = math.max(1, 2 * sc)
                c.fill.Color = col; c.fill.Transparency = c.alpha; c.fill.Visible = fillW > 0.5
            end
        end
    end

    local function updateIndicators(dt)
        -- smooth drag follow (runs whenever the HUD exists so it eases into place)
        if indHolder then
            drag.disp = drag.disp:Lerp(drag.target, math.clamp(dt * 16, 0, 1))
            indHolder.Position = UDim2.fromOffset(math.floor(drag.disp.X + 0.5), math.floor(drag.disp.Y + 0.5))
            -- keep the GUI panel readable on small screens
            if indUIScale then indUIScale.Scale = lerp(indUIScale.Scale, uiScale(), math.clamp(dt * 8, 0, 1)) end
        end

        local style = Config.Ind_Style
        local char  = Config.Ind_On and getChar(LocalPlayer) or nil
        local hum   = getHum(char)

        -- ── PANEL style (GUI, draggable) ────────────────────────────────────
        if char and style == "Panel" and indHolder then
            local a = math.clamp(dt * 12, 0, 1)
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
        elseif indHolder then
            for _, r in pairs(rows) do setRowShown(r, false) end
        end

        -- ── Drawing styles (Simple / Player) ────────────────────────────────
        local def = DRAW_STYLES[style] and STYLE_DEFS[style] or nil
        if char and hasDrawing and def then
            local stats = collectStats(char, hum)
            local sc    = uiScale()
            local vp    = Camera.ViewportSize
            local width = def.width * sc
            local n     = math.max(#stats, 1)
            local totalH = n * def.row * sc
            local drawn = false

            if style == "Simple" then
                local ay = math.clamp(Config.Ind_ScreenY or 0.60, 0.2, 0.92)
                renderDrawStack(stats, dt, def, vp.X * 0.5, vp.Y * ay, sc)
                drawn = true

            elseif style == "Player" then
                -- Beside the local player. Offsets are projected along CAMERA axes (never
                -- the character CFrame), so shiftlock yaw can't move the stack. "closer"
                -- => small gap. Side is user-selectable.
                local root = getRoot(char)
                if root then
                    local _, size = char:GetBoundingBox()
                    local halfW = math.max(size.X, size.Z) * 0.5
                    local halfH = size.Y * 0.5
                    local sp, on = Camera:WorldToViewportPoint(root.Position)
                    if on then
                        local side = Config.Ind_PlayerSide or "Left"
                        local gap  = 8 * sc
                        if side == "Bottom" then
                            local footSp = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, halfH, 0))
                            local topY   = footSp.Y + gap
                            renderDrawStack(stats, dt, def, sp.X, topY, sc)
                            drawn = true
                        else
                            local edge   = Camera:WorldToViewportPoint(root.Position + Camera.CFrame.RightVector * halfW)
                            local edgePx = math.abs(edge.X - sp.X)
                            local topY   = sp.Y - totalH / 2
                            local cx
                            if side == "Right" then cx = sp.X + edgePx + gap + width / 2
                            else                    cx = sp.X - edgePx - gap - width / 2 end
                            renderDrawStack(stats, dt, def, cx, topY, sc)
                            drawn = true
                        end
                    end
                end
            end

            if not drawn then hideAllDrawCells() end
        else
            hideAllDrawCells()
        end
    end

    -- ═════════════════════════════════════════════════════════════════���═════
    -- HIT DIRECTION  (fading arrows around the crosshair)
    -- ══════════════════════════════════════════��════════════════════════════
    local hitArrows = {}          -- active { head, headOut, stem, born, angle }
    local ARROW_LIFE = 1.25
    local lastHealth = nil

    local function removeArrow(h)
        for _, k in ipairs({ "head", "headOut", "stem" }) do
            if h[k] then pcall(function() h[k]:Remove() end) end
        end
    end

    local function spawnHitArrow(angle)
        if not hasDrawing then return end
        local h = {
            born = os.clock(), angle = angle,
            headOut = newDrawing("Triangle", { Thickness = 1, Filled = true, Visible = false, Color = Color3.new(0, 0, 0), ZIndex = 90 }),
            head    = newDrawing("Triangle", { Thickness = 1, Filled = true, Visible = false, Color = Config.HitDir_Color, ZIndex = 92 }),
            stem    = newDrawing("Line",     { Thickness = 3, Visible = false, Color = Config.HitDir_Color, ZIndex = 91 }),
        }
        hitArrows[#hitArrows + 1] = h
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
        -- Screen-relative bearing to the attacker, projected onto the camera's OWN
        -- flattened look/right axes. The previous version used a world cross-product with
        -- a fixed +Z assumption, so the left/right sign flipped whenever the camera faced
        -- a different world direction (arrows pointed the wrong way "in some moments").
        -- atan2(rightComponent, forwardComponent) is orientation-independent:
        --   0 = attacker straight ahead (arrow points up), +pi/2 = to the right, etc.
        local rel = best.Position - root.Position
        local flatRel = Vector3.new(rel.X, 0, rel.Z)
        if flatRel.Magnitude < 0.01 then return 0 end
        flatRel = flatRel.Unit
        local look  = Camera.CFrame.LookVector
        local right = Camera.CFrame.RightVector
        local lookF  = Vector3.new(look.X, 0, look.Z)
        local rightF = Vector3.new(right.X, 0, right.Z)
        if lookF.Magnitude < 0.01 or rightF.Magnitude < 0.01 then return 0 end
        lookF, rightF = lookF.Unit, rightF.Unit
        return math.atan2(flatRel:Dot(rightF), flatRel:Dot(lookF))
    end

    local function updateHitDir()
        if not hasDrawing then return end
        local vp = Camera.ViewportSize
        local cx, cy = vp.X / 2, vp.Y / 2
        local sc = math.clamp(vp.Y / 864, 0.85, 1.7)
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then sc = sc * 1.1 end
        local radius = 78 * sc
        local now = os.clock()
        for i = #hitArrows, 1, -1 do
            local h = hitArrows[i]
            local age = now - h.born
            if age > ARROW_LIFE or not Config.HitDir_On then
                removeArrow(h)
                table.remove(hitArrows, i)
            else
                local a = h.angle
                -- outward direction on screen: 0 = up (front), +pi/2 = right
                local dirx, diry = math.sin(a), -math.cos(a)
                local perpx, perpy = -diry, dirx

                local life = age / ARROW_LIFE
                -- quick pop-in (first 12%) then ease-out fade; also drift outward slightly
                local pop  = math.clamp(age / (ARROW_LIFE * 0.12), 0, 1)
                local ease = pop * pop * (3 - 2 * pop)                 -- smoothstep
                local fade = 1 - math.clamp((life - 0.12) / 0.88, 0, 1)
                local alpha = math.min(ease, fade)                     -- opacity 0..1
                local scale = (0.7 + 0.3 * ease)                       -- grows in
                local drift = radius + (6 + 10 * life) * sc            -- eases away from centre

                local headLen  = 18 * sc * scale
                local headHalf = 11 * sc * scale
                local tipR   = drift + headLen
                local baseR  = drift
                local stemR  = drift - 12 * sc * scale

                local tipx,  tipy  = cx + dirx * tipR,  cy + diry * tipR
                local baseCx, baseCy = cx + dirx * baseR, cy + diry * baseR
                local bLx, bLy = baseCx + perpx * headHalf, baseCy + perpy * headHalf
                local bRx, bRy = baseCx - perpx * headHalf, baseCy - perpy * headHalf

                -- head fill + slightly larger black outline behind it for contrast
                h.head.PointA = Vector2.new(tipx, tipy)
                h.head.PointB = Vector2.new(bLx, bLy)
                h.head.PointC = Vector2.new(bRx, bRy)
                h.head.Color = Config.HitDir_Color
                h.head.Transparency = alpha
                h.head.Visible = true

                local o = 2 * sc
                h.headOut.PointA = Vector2.new(tipx + dirx * o, tipy + diry * o)
                h.headOut.PointB = Vector2.new(bLx + perpx * o - dirx * o, bLy + perpy * o - diry * o)
                h.headOut.PointC = Vector2.new(bRx - perpx * o - dirx * o, bRy - perpy * o - diry * o)
                h.headOut.Transparency = alpha * 0.55
                h.headOut.Visible = true

                -- short tail
                h.stem.From = Vector2.new(cx + dirx * stemR, cy + diry * stemR)
                h.stem.To   = Vector2.new(baseCx, baseCy)
                h.stem.Thickness = math.max(2, 3 * sc)
                h.stem.Color = Config.HitDir_Color
                h.stem.Transparency = alpha
                h.stem.Visible = true
            end
        end
    end

    local function onLocalDamage()
        local ang = nearestAttackerAngle()
        spawnHitArrow(ang or 0)   -- always show something, even if no attacker is resolvable
    end

    -- Poll local health every frame (more reliable than Humanoid.HealthChanged, which
    -- can be missed when the character/humanoid instance is swapped on respawn).
    local function pollLocalDamage()
        if not Config.HitDir_On then return end
        local hum = getHum(getChar(LocalPlayer))
        if not hum then lastHealth = nil; return end
        local h = hum.Health
        if lastHealth and h < lastHealth - 0.5 and h > 0 then onLocalDamage() end
        lastHealth = h
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- Lifecycle wiring
    -- ═══════════════════════════════════════════════════════════════════════
    local conns = {}
    local renderBoundName = nil
    local function track(sig, fn) conns[#conns + 1] = sig:Connect(fn) end

    local function hookLocalHumanoid()
        local hum = getHum(getChar(LocalPlayer))
        lastHealth = hum and hum.Health or nil
    end

    local started = false
    local function startRuntime()
        if started then return end
        started = true

        buildIndicatorGui()
        hookLocalHumanoid()

        track(LocalPlayer.CharacterAdded, function()
            task.wait(0.4)
            for _, t in pairs(cdTracks) do t.active = false end   -- reset cooldown timers on respawn
            hookLocalHumanoid()
        end)
        track(Players.PlayerRemoving, function(plr) destroyEsp(plr) end)

        -- master render loop.
        -- IMPORTANT: bound AFTER the camera update (priority Camera+1) rather than a
        -- plain RenderStepped connection. RenderStepped fires BEFORE Roblox's camera
        -- BindToRenderStep step, so under shiftlock (which applies a constant camera
        -- offset) we would project every world point with a one-frame-stale camera —
        -- exactly the persistent horizontal shift the user saw. Running after the camera
        -- guarantees Camera.CFrame already includes the shiftlock offset.
        local RENDER_NAME = "MacVisuals_Render"
        local ok = pcall(function()
            RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
                if hasDrawing then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then updateEspFor(plr) end
                    end
                end
                updateIndicators(dt)
                pollLocalDamage()
                updateHitDir()
            end)
        end)
        if ok then
            renderBoundName = RENDER_NAME
        else
            -- fallback for executors without BindToRenderStep
            track(RunService.RenderStepped, function(dt)
                if hasDrawing then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then updateEspFor(plr) end
                    end
                end
                updateIndicators(dt)
                pollLocalDamage()
                updateHitDir()
            end)
        end
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
            return section:Slider({
                Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
                Precision = o.Precision or 0, Suffix = o.Suffix, Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        local function colorpick(section, name, flag, default, set)
            return section:Colorpicker({ Name = name, Default = default, Callback = function(c) set(c) end }, ctx.flag(flag))
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
        -- per-style setting elements (their visibility is driven by the Style dropdown)
        local styleEls = {}   -- element -> { style1, style2, ... } (nil/"*" = always visible)
        local function applyStyleVis()
            local cur = Config.Ind_Style
            for el, styles in pairs(styleEls) do
                local vis = false
                if styles == "*" then vis = true
                else for _, s in ipairs(styles) do if s == cur then vis = true break end end end
                pcall(function() el:SetVisibility(vis) end)
            end
        end

        pcall(function()
            sInd:Dropdown({
                Name = "Style",
                Options = { "Panel", "Player", "Simple" },
                Default = Config.Ind_Style,
                Callback = function(v)
                    if type(v) == "string" and v ~= "" then Config.Ind_Style = v; applyStyleVis() end
                end,
            }, ctx.flag("VIS_IND_Style"))
        end)
        sInd:SubLabel({ Text = "Panel = draggable HUD | Player = beside your character | Simple = clean centered stack." })

        boolToggle(sInd, "Health",       "Ind Health",  function() return Config.Ind_Health end,  function(v) Config.Ind_Health = v end)
        boolToggle(sInd, "Stamina",      "Ind Stamina", function() return Config.Ind_Stamina end, function(v) Config.Ind_Stamina = v end)
        boolToggle(sInd, "IFrame",       "Ind IFrame",  function() return Config.Ind_IFrame end,  function(v) Config.Ind_IFrame = v end)
        boolToggle(sInd, "Heavy (M2) CD", "Ind Heavy",  function() return Config.Ind_M2 end,      function(v) Config.Ind_M2 = v end)
        boolToggle(sInd, "Dodge CD",     "Ind Dodge",   function() return Config.Ind_Dodge end,   function(v) Config.Ind_Dodge = v end)
        boolToggle(sInd, "Block CD",     "Ind Block",   function() return Config.Ind_Block end,   function(v) Config.Ind_Block = v end)
        colorpick(sInd, "Accent Color", "VIS_IND_Accent", Config.Ind_Accent, function(c) Config.Ind_Accent = c end)

        -- ── Per-style settings (shown only for the relevant style) ──
        -- Panel: draggable, so it gets a reset-position button.
        local resetBtn = sInd:Button({ Name = "Reset HUD Position", Callback = function() resetPos() end })
        styleEls[resetBtn] = { "Panel" }
        local dragHint = sInd:SubLabel({ Text = "Drag the HUD anywhere - the position is saved automatically." })
        styleEls[dragHint] = { "Panel" }

        -- Player: which side of the character the stack sits on.
        pcall(function()
            local sideDd = sInd:Dropdown({
                Name = "Player Side",
                Options = { "Left", "Right", "Bottom" },
                Default = Config.Ind_PlayerSide,
                Callback = function(v) if type(v) == "string" and v ~= "" then Config.Ind_PlayerSide = v end end,
            }, ctx.flag("VIS_IND_PlayerSide"))
            styleEls[sideDd] = { "Player" }
        end)

        -- Simple: vertical position on screen.
        local screenYSlider = slider(sInd, {
            Name = "Screen Position", Flag = "VIS_IND_ScreenY", Default = math.floor((Config.Ind_ScreenY or 0.6) * 100),
            Min = 20, Max = 92, Suffix = "%", Callback = function(v) Config.Ind_ScreenY = v / 100 end,
        })
        styleEls[screenYSlider] = { "Simple" }

        -- Both Drawing styles: manual scale on top of the automatic mobile rescale.
        local scaleSlider = slider(sInd, {
            Name = "Scale", Flag = "VIS_IND_Scale", Default = math.floor((Config.Ind_Scale or 1) * 100),
            Min = 60, Max = 200, Suffix = "%", Callback = function(v) Config.Ind_Scale = v / 100 end,
        })
        styleEls[scaleSlider] = { "Player", "Simple" }

        applyStyleVis()
        sInd:SubLabel({ Text = "Cooldowns are predicted client-side from the game's own combat data, so they tick down accurately." })

        -- ─────────────── Section 3: Hit Direction (Right) ────���──────────
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
        if renderBoundName then
            pcall(function() RunService:UnbindFromRenderStep(renderBoundName) end)
            renderBoundName = nil
        end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        for _, c in ipairs(dragConns) do pcall(function() c:Disconnect() end) end
        dragConns = {}
        for plr in pairs(espPool) do destroyEsp(plr) end
        for _, h in ipairs(hitArrows) do removeArrow(h) end
        hitArrows = {}
        for _, c in pairs(drawCells) do
            for _, key in ipairs({ "label", "value", "track", "fill" }) do
                if c[key] then pcall(function() c[key]:Remove() end) end
            end
        end
        drawCells = {}
        indUIScale = nil
        if screenGui then pcall(function() screenGui:Destroy() end); screenGui = nil end
    end

    return M
end
