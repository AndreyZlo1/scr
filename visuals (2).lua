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
    -- Luraph macro raw shim. Hot per-frame paths are wrapped in
    -- LPH_NO_VIRTUALIZE(function() ... end) so Luraph keeps them native-fast. You
    -- CANNOT declare a local/variable named LPH_* — Luraph reserves the prefix and
    -- errors ("cannot be used as a variable name"). So when run raw we install an
    -- identity fallback under that name via a STRING key (concat so the reserved
    -- token never appears as an identifier). After Luraph this line is dead.
    do
        local k = "LPH" .. "_NO_VIRTUALIZE"
        local G = (type(getgenv) == "function") and getgenv() or _G
        if not G[k] then G[k] = function(f) return f end end
    end

    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService      = game:GetService("TweenService")
    local UserInputService  = game:GetService("UserInputService")
	local Lighting           = game:GetService("Lighting")
	local SoundService       = game:GetService("SoundService")
	local Debris             = game:GetService("Debris")

    local LocalPlayer = Players.LocalPlayer
	local VisualCtl

    -- cloneref hides our references to Camera/CoreGui from naive scans (harmless if absent)
    local cref = (type(cloneref) == "function") and cloneref or function(x) return x end
    local Camera = cref(Workspace.CurrentCamera)
	local cameraConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if Workspace.CurrentCamera then
			Camera = cref(Workspace.CurrentCamera)
			if VisualCtl then VisualCtl.bindFOV() end
		end
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
		ESP_Range    = 1200,
        ESP_Box_Color  = Color3.fromRGB(90, 150, 255),
        ESP_Text_Color = Color3.fromRGB(235, 235, 240),
        ESP_M2_Color   = Color3.fromRGB(170, 110, 255),

        -- Indicators
        Ind_On      = false,
        Ind_Style   = "Panel",   -- "Panel" | "Free" | "Player" | "Simple"
        Ind_PlayerSide = "Left", -- "Left" | "Right" | "Bottom" (Player style only)
		Ind_PlayerDesign = "Neon", -- Neon | Cyber | Arc | Minimal
        Ind_PlayerTextY = 0,     -- vertical text offset (px) for the Player style
        Ind_Drag    = true,      -- allow dragging the HUD (Panel / Free)
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
        HitDir_Transparency = 0,   -- 0 = opaque, 1 = invisible

		-- Camera / local identity
		FOV_On      = false,
		FOV_Value   = 70,
		Name_On     = false,
		Name_Custom = false,
		Name_First  = "Syllinse",
		Name_Last   = "Project",
		Env_On=false, Env_Ambient=Color3.fromRGB(120,120,140), Env_Outdoor=Color3.fromRGB(100,105,120),
		Env_FogColor=Color3.fromRGB(170,180,200), Env_FogStart=0, Env_FogEnd=1000,
		Env_AtmosDensity=0.15, Env_AtmosColor=Color3.fromRGB(190,200,220), Env_Brightness=2, Env_ClockTime=14,
		HitFX_On=false, HitSound_On=true, HitParticles_On=true, HitFX_Color=Color3.fromRGB(88,165,255),
		HitParticleColorB=Color3.fromRGB(165,95,255), HitParticleCount=20, HitParticleDuration=1.1,
		HitParticleType="Sparks",  -- "Sparks" | "Orbs" | "Stars" | "Wireframe"
		HitParticlePhysics=false,  -- bounce off geometry (Raycast per particle)
		HitParticleWireframe=false, HitParticleWireScale=0.4, HitParticleSpeedMin=2, HitParticleSpeedMax=32,
		HitParticleGravity=-32, HitParticleMaxSystems=5, HitSound_Volume=0.75,

        -- [PERF] Render throttle. The whole visual pipeline (ESP loop + indicators + hit-dir)
        -- runs on Heartbeat, which fires at the monitor's refresh rate — so on a 144/240Hz screen
        -- we were doing 2.4–4x more WorldToViewportPoint + attribute reads than the eye can see.
        -- Capping the heavy redraw at MaxFPS (default 60) cuts that cost proportionally while
        -- animations stay smooth (we pass the REAL accumulated dt, so lerps are framerate-correct).
        MaxFPS = 60,
    }

	-- Event-driven camera/name controls: no per-frame enforcement. Both are client-only.
	VisualCtl = {
		originals = setmetatable({}, { __mode = "k" }),
		fovOriginals = setmetatable({}, { __mode = "k" }),
		nameConns = {}, fovConn = nil,
	}
	function VisualCtl.applyFOV()
		if not Camera then return end
		if VisualCtl.fovOriginals[Camera] == nil then VisualCtl.fovOriginals[Camera] = Camera.FieldOfView end
		if not Config.FOV_On then return end
		local wanted = math.clamp(tonumber(Config.FOV_Value) or 70, 1, 120)
		if math.abs(Camera.FieldOfView - wanted) > 0.01 then Camera.FieldOfView = wanted end
	end
	function VisualCtl.restoreFOV()
		if not Camera then return end
		local original = VisualCtl.fovOriginals[Camera]
		if original and math.abs(Camera.FieldOfView - original) > 0.01 then Camera.FieldOfView = original end
	end
	function VisualCtl.bindFOV()
		if VisualCtl.fovConn then VisualCtl.fovConn:Disconnect(); VisualCtl.fovConn = nil end
		if Camera then
			VisualCtl.fovConn = Camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
				VisualCtl.applyFOV()
			end)
		end
		VisualCtl.applyFOV()
	end
	function VisualCtl.clearNameConns()
		for _, c in ipairs(VisualCtl.nameConns) do pcall(function() c:Disconnect() end) end
		table.clear(VisualCtl.nameConns)
	end
	function VisualCtl.applyName(char)
		char = char or LocalPlayer.Character
		local pd = char and char:FindFirstChild("PlayerData")
		if not pd then return false end
		if not VisualCtl.originals[pd] then
			VisualCtl.originals[pd] = { first = pd:GetAttribute("FirstName"), last = pd:GetAttribute("LastName") }
		end
		local src = VisualCtl.originals[pd]
		local first = Config.Name_Custom and Config.Name_First or "Syllinse"
		local last  = Config.Name_Custom and Config.Name_Last  or "Project"
		if not Config.Name_On then first, last = src.first, src.last end
		if pd:GetAttribute("FirstName") ~= first then pd:SetAttribute("FirstName", first) end
		if pd:GetAttribute("LastName") ~= last then pd:SetAttribute("LastName", last) end
		return true
	end
	function VisualCtl.bindName(char)
		VisualCtl.clearNameConns()
		char = char or LocalPlayer.Character
		local pd = char and (char:FindFirstChild("PlayerData") or char:WaitForChild("PlayerData", 5))
		if not pd then return end
		VisualCtl.applyName(char)
		local guard = false
		local function enforce()
			if guard or not Config.Name_On then return end
			guard = true; VisualCtl.applyName(char); guard = false
		end
		VisualCtl.nameConns[1] = pd:GetAttributeChangedSignal("FirstName"):Connect(enforce)
		VisualCtl.nameConns[2] = pd:GetAttributeChangedSignal("LastName"):Connect(enforce)
	end
	function VisualCtl.restoreAll()
		Config.FOV_On = false
		VisualCtl.restoreFOV()
		Config.Name_On = false
		VisualCtl.applyName()
	end

	local EnvCtl={original=nil,atmosphere=nil,conns={},applying=false}
	local ENV_PROPS={"Ambient","OutdoorAmbient","FogColor","FogStart","FogEnd","Brightness","ClockTime"}
	function EnvCtl.apply()
		if not Config.Env_On or EnvCtl.applying then return end; EnvCtl.applying=true
		Lighting.Ambient=Config.Env_Ambient; Lighting.OutdoorAmbient=Config.Env_Outdoor; Lighting.FogColor=Config.Env_FogColor
		Lighting.FogStart=Config.Env_FogStart; Lighting.FogEnd=Config.Env_FogEnd; Lighting.Brightness=Config.Env_Brightness; Lighting.ClockTime=Config.Env_ClockTime
		local a=Lighting:FindFirstChildOfClass("Atmosphere"); if a then a.Density=Config.Env_AtmosDensity; a.Color=Config.Env_AtmosColor end
		EnvCtl.applying=false
	end
	function EnvCtl.set(on)
		for _,c in ipairs(EnvCtl.conns) do c:Disconnect() end; table.clear(EnvCtl.conns)
		if on and not EnvCtl.original then EnvCtl.original={}; for _,p in ipairs(ENV_PROPS) do EnvCtl.original[p]=Lighting[p] end; local a=Lighting:FindFirstChildOfClass("Atmosphere"); if a then EnvCtl.atmosphere=a; EnvCtl.original.ad=a.Density; EnvCtl.original.ac=a.Color end end
		Config.Env_On=on and true or false
		if Config.Env_On then EnvCtl.apply(); for _,p in ipairs(ENV_PROPS) do EnvCtl.conns[#EnvCtl.conns+1]=Lighting:GetPropertyChangedSignal(p):Connect(EnvCtl.apply) end
			local a=Lighting:FindFirstChildOfClass("Atmosphere"); if a then EnvCtl.conns[#EnvCtl.conns+1]=a:GetPropertyChangedSignal("Density"):Connect(EnvCtl.apply); EnvCtl.conns[#EnvCtl.conns+1]=a:GetPropertyChangedSignal("Color"):Connect(EnvCtl.apply) end
		elseif EnvCtl.original then EnvCtl.applying=true; for _,p in ipairs(ENV_PROPS) do Lighting[p]=EnvCtl.original[p] end; if EnvCtl.atmosphere and EnvCtl.atmosphere.Parent then EnvCtl.atmosphere.Density=EnvCtl.original.ad; EnvCtl.atmosphere.Color=EnvCtl.original.ac end; EnvCtl.applying=false; EnvCtl.original=nil; EnvCtl.atmosphere=nil end
	end

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
    -- [PERF] Cooldown durations are per-STYLE constants, but these were re-fetched (with a pcall
    -- into the game module) on EVERY frame the bar was visible. Cache the result per style key so
    -- each style incurs exactly one pcall for its lifetime.
    local _m2CdCache, _evCdCache = {}, {}
    local function cfgM2Cooldown(char)
        local k = styleKeyOf(char)
        local v = _m2CdCache[k]
        if v == nil then
            v = 7
            if CombatConfig and CombatConfig.GetStyleM2Cooldown then
                local ok, r = pcall(CombatConfig.GetStyleM2Cooldown, k)
                if ok and type(r) == "number" then v = r end
            end
            _m2CdCache[k] = v
        end
        return v
    end
    local function cfgEvasiveCooldown(char)
        local k = styleKeyOf(char)
        local v = _evCdCache[k]
        if v == nil then
            v = 1.5
            if CombatConfig and CombatConfig.GetStyleEvasiveCooldown then
                local ok, r = pcall(CombatConfig.GetStyleEvasiveCooldown, k)
                if ok and type(r) == "number" then v = r end
            end
            _evCdCache[k] = v
        end
        return v
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
        { "Hip", "HipL" }, { "Hip", "HipR" }, { "HipL", "HipR" }, -- pelvis (spread + bar)
        { "ShoulderL", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "ShoulderR", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "HipL", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "HipR", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
    }
    -- R6 fallback (Torso is a single part; shoulders/hips offset from it)
    local BONES_R6 = {
        { "ShoulderL", "ShoulderR" },
        { "Neck", "Chest" }, { "Chest", "Hip" },
        { "Hip", "HipL" }, { "Hip", "HipR" }, { "HipL", "HipR" }, -- pelvis line
        { "ShoulderL", "Left Arm" }, { "ShoulderR", "Right Arm" },
        { "HipL", "Left Leg" }, { "HipR", "Right Leg" },
    }

    -- Resolve world-space joint points for the character. Returns (points, bones, headPart).
    local skeletonPoints = LPH_NO_VIRTUALIZE(function(char, pts)
        local head = char:FindFirstChild("Head")
        local uT   = char:FindFirstChild("UpperTorso")
		pts = pts or {}
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
				local p = char:FindFirstChild(n); pts[n] = p and p.Position or nil
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
            pts.Hip       = hip
            pts.ShoulderL = neck - rt * hx
            pts.ShoulderR = neck + rt * hx
            pts.HipL      = hip - rt * (hx * 0.6)
            pts.HipR      = hip + rt * (hx * 0.6)
            for _, n in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
				local p = char:FindFirstChild(n); pts[n] = p and p.Position or nil
            end
            return pts, BONES_R6, head
        end
        return pts, BONES_R15, head
    end)

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
        -- [PERF] Skeleton is OFF by default, yet the old code eagerly built a Circle + 24 Line
        -- Drawing objects for EVERY player up front (~25 objects/player wasted). These are now
        -- created lazily by ensureSkeleton(o) the first time skeleton is actually drawn.
        o.headCircle = nil
        o.bones = {}
		o.skelPts = {}
        espPool[plr] = o
        return o
    end

    -- Lazily build the skeleton Drawings for an esp entry (head circle + bone lines). Called only
    -- while ESP_Skeleton is on, so executors never pay for skeleton objects unless the user uses it.
    local function ensureSkeleton(o)
        if not o.headCircle then
            o.headCircle = newDrawing("Circle", { Thickness = 1, Filled = false, NumSides = 24, Radius = 6, Visible = false, Color = Color3.fromRGB(255, 255, 255), ZIndex = 2 })
        end
        if #o.bones == 0 then
            for i = 1, SKELETON_MAX do
                o.bones[i] = newDrawing("Line", { Thickness = 1, Visible = false, Color = Color3.fromRGB(255, 255, 255) })
            end
        end
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

    -- Frame-scoped caches: the local player's root and the viewport are identical
    -- for EVERY tracked player within a single frame, so we resolve them ONCE per
    -- Heartbeat tick (see the render loop) instead of re-doing getChar/getRoot and
    -- a ViewportSize read for all N players every frame.
    local _frLpRoot, _frVP
	local _espPlayers = {}
	local _espCount = 0
	local function rebuildEspPlayers()
		table.clear(_espPlayers)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then _espPlayers[#_espPlayers + 1] = plr end
		end
		_espCount = #_espPlayers
	end
	rebuildEspPlayers()

    -- [LURAPH] Per-player ESP update — the hottest per-frame path (runs for every
    -- tracked player each tick). LPH_NO_VIRTUALIZE keeps it native under Luraph.
    local updateEspFor = LPH_NO_VIRTUALIZE(function(plr)
        local o = espPool[plr] or createEsp(plr)
        local char = getChar(plr)
        if not (Config.ESP_On and char and isAlive(char)) then hideEsp(o); return end

        local hum  = getHum(char)
        local root = getRoot(char)
        if not (hum and root) then hideEsp(o); return end

        local lpRoot = _frLpRoot
        local dist = lpRoot and (root.Position - lpRoot.Position).Magnitude or 0
        if (Config.ESP_Range or 0) > 0 and dist > Config.ESP_Range then hideEsp(o); return end

        -- STATIC 2D box, anchored to the ROOT PART world position (exactly like the
        -- "Player" indicator style, which the user confirmed does NOT drift under
        -- shiftlock). Height comes from the bounding-box vertical extent applied along
        -- WORLD-up from the root; width is a fixed portrait ratio of that height. Because
        -- nothing here reads the model's orientation/CFrame, shiftlock (which yaws the
        -- character toward the camera) can no longer shift or breathe the box.
		-- BoundingBox is expensive and body dimensions almost never change. Cache per character;
		-- invalidate only on respawn/model replacement instead of recomputing N×60 times/sec.
		if o.boundChar ~= char then
			o.boundChar = char
			local ok, _, size = pcall(char.GetBoundingBox, char)
			o.boundY = ok and size and size.Y or 6
		end
        local anchor = root.Position
		local halfH  = o.boundY * 0.5
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
            local vp = _frVP or Camera.ViewportSize   -- [PERF] frame-cached viewport
            o.tracer.Color = Config.ESP_Box_Color
            o.tracer.From = Vector2.new(vp.X / 2, vp.Y)
            o.tracer.To = Vector2.new(bx + bw / 2, by + bh)
            o.tracer.Visible = true
        else
            o.tracer.Visible = false
        end

        -- Skeleton (computed joints + head circle)
        if Config.ESP_Skeleton then
            ensureSkeleton(o)
            local pts, bones, headPart = skeletonPoints(char, o.skelPts)
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
            if o.headCircle then o.headCircle.Visible = false end
        end
    end)

    -- ═══════════════════════════════════════════════════════════════��═══════
    -- INDICATORS  (Neverlose-style animated GUI)
    -- ══════════════���════════════════════════════════════════════════════════
    local function guiParent()
        local ok, hui = pcall(function() return (type(gethui) == "function") and gethui() or nil end)
        if ok and hui then return hui end
        return cref(game:GetService("CoreGui"))
    end

    local screenGui, indHolder, indUIScale
    local panelBody       -- Panel chip container
    local dragHandle      -- invisible grab surface for the draggable "Free" text stack
    local rows = {}       -- [key] = Panel row object
    local beginDrag       -- forward decl (shared by every draggable surface)
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
    local posFrac = nil                   -- saved position as {fx,fy} fractions of the viewport
    local clampPos, savePos, restoreSavedPos, applyFracPos  -- forward decls

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

        -- grab any row to move the HUD (gated by the Drag toggle)
        frame.InputBegan:Connect(function(input) beginDrag(input) end)

        return {
            key = key, frame = frame, accent = accent, fill = fill,
            stroke = stroke, label = lab, value = val, shown = false, dispRatio = 0,
        }
    end

    -- Clamp against the HUD's ACTUAL rendered size (AbsoluteSize already includes the
    -- UIScale and only counts the rows that are currently visible). The old version
    -- reserved a fixed 6-row height, so a 2-row HUD could never reach the bottom edge —
    -- that's why the panel refused to sit in the lower corners.
    function clampPos(x, y)
        local vp = Camera.ViewportSize
        local w = (indHolder and indHolder.AbsoluteSize.X > 1) and indHolder.AbsoluteSize.X or IND_W
        local h = (indHolder and indHolder.AbsoluteSize.Y > 1) and indHolder.AbsoluteSize.Y or ROW_H
        x = math.clamp(x, 0, math.max(0, vp.X - w))
        y = math.clamp(y, 0, math.max(0, vp.Y - h))
        return x, y
    end

    -- Start dragging from any draggable surface (Panel rows or the Free handle).
    -- Honors the Drag toggle so the HUD can be locked in place.
    function beginDrag(input)
        if not Config.Ind_Drag then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            drag.active   = true
            drag.startIn  = Vector2.new(input.Position.X, input.Position.Y)
            drag.startPos = drag.target
        end
    end

    -- Persist the HUD position as VIEWPORT FRACTIONS (not absolute pixels) so it lands
    -- in the same relative spot on any resolution — same approach the watermark uses.
    function savePos()
        local vp = Camera.ViewportSize
        posFrac = { fx = drag.target.X / math.max(1, vp.X), fy = drag.target.Y / math.max(1, vp.Y) }
        if MacLibRef and POS_FLAG then
            pcall(function() MacLibRef:FALSetData(POS_FLAG, posFrac) end)
        end
    end

    -- Convert the stored fraction back into clamped pixels for the current viewport.
    function applyFracPos()
        if not posFrac then return end
        local vp = Camera.ViewportSize
        local nx, ny = clampPos(posFrac.fx * vp.X, posFrac.fy * vp.Y)
        drag.target = Vector2.new(nx, ny)
        drag.disp   = Vector2.new(nx, ny)
        if indHolder then indHolder.Position = UDim2.fromOffset(nx, ny) end
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

        -- default position: near the bottom-right...
        local vp = Camera.ViewportSize
        local dx, dy = clampPos(vp.X - IND_W - 24, vp.Y - (#rowOrder * (ROW_H + ROW_GAP)) - 24)
        drag.target = Vector2.new(dx, dy)
        drag.disp   = Vector2.new(dx, dy)
        indHolder.Position = UDim2.fromOffset(dx, dy)
        -- ...then immediately apply the saved position if MacLib is already available.
        -- (buildUI may run before OR after this, so we restore in both places.)
        restoreSavedPos()

        -- keep the HUD in its saved RELATIVE spot when the viewport/resolution changes
        pcall(function()
            dragConns[#dragConns + 1] = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if not drag.active then applyFracPos() end
            end)
        end)

        -- global pointer-move drives the drag while a surface is held
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
        -- global release ends the drag and persists the position
        dragConns[#dragConns + 1] = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                if drag.active then drag.active = false; savePos() end
            end
        end)

        -- friendly, non-uppercase labels shared by both GUI styles
        local labels = { Health = "HP", Stamina = "Stamina", IFrame = "I-Frame", M2 = "Heavy", Dodge = "Dodge", Block = "Block" }

        -- ── Panel body (stacked chips) ──────────────────────────────────────
        panelBody = Instance.new("Frame")
        panelBody.Name = "PanelBody"
        panelBody.BackgroundTransparency = 1
        panelBody.Size = UDim2.new(1, 0, 0, 0)
        panelBody.AutomaticSize = Enum.AutomaticSize.Y
        panelBody.Parent = indHolder

        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.VerticalAlignment = Enum.VerticalAlignment.Top
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, ROW_GAP)
        list.Parent = panelBody

        for i, key in ipairs(rowOrder) do
            local r = mkRow(key, labels[key])
            r.frame.LayoutOrder = i
            r.frame.Parent = panelBody
            rows[key] = r
        end

        -- ── Free body (invisible grab handle for the draggable text stack) ──
        -- The "Free" style renders the exact same Drawing text-stack as the Player
        -- style (so the two blend), but at a fixed, user-draggable screen position.
        -- Drawing objects don't receive input, so this transparent Active frame sits
        -- under the stack and captures the drag. Its size is refreshed each frame to
        -- match the stack, so the whole block is grabbable and clamps correctly.
        dragHandle = Instance.new("Frame")
        dragHandle.Name = "FreeHandle"
        dragHandle.BackgroundTransparency = 1
        dragHandle.BorderSizePixel = 0
        dragHandle.Active = true
        dragHandle.Visible = false
        dragHandle.Size = UDim2.new(0, IND_W, 0, ROW_H)
        dragHandle.Parent = indHolder
        dragHandle.InputBegan:Connect(function(input) beginDrag(input) end)
    end

    -- restore the saved HUD position (fraction-based, resolution-independent).
    -- Called from BOTH buildUI (once MacLib is available) and buildIndicatorGui (which
    -- sets a default first) so start-order never clobbers the saved spot.
    function restoreSavedPos()
        if not (MacLibRef and POS_FLAG) then return end
        pcall(function()
            local saved = MacLibRef.FALGetData and MacLibRef:FALGetData(POS_FLAG, nil)
            if type(saved) ~= "table" then return end
            local vp = Camera.ViewportSize
            if type(saved.fx) == "number" and type(saved.fy) == "number" then
                posFrac = { fx = saved.fx, fy = saved.fy }
            elseif type(saved.x) == "number" and type(saved.y) == "number" then
                -- legacy absolute-pixel save → convert to a fraction of the viewport
                posFrac = { fx = saved.x / math.max(1, vp.X), fy = saved.y / math.max(1, vp.Y) }
            else
                return
            end
            applyFracPos()
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
            -- [PERF] disconnect after it fires — the old code leaked one Completed connection per
            -- hide (they piled up every time a row toggled off).
            local cn; cn = t.Completed:Connect(function()
                if cn then cn:Disconnect(); cn = nil end
                if not r.shown then r.frame.Visible = false end
            end)
            t:Play()
        end
    end


    -- ── Client-side cooldown prediction ���────────────────────────────────────
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
    local readIndicator = LPH_NO_VIRTUALIZE(function(key, char, hum)
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
                return true, 1, "Active", Color3.fromRGB(150, 120, 255)
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
    end)

    -- short labels used by the minimalist Drawing styles
    local STAT_LABELS = { Health = "HP", Stamina = "Stamina", IFrame = "I-Frame", M2 = "Heavy", Dodge = "Dodge", Block = "Block" }

    -- ordered list of currently-active local stats { key, ratio, text, color }
	local statsBuf, statsN = {}, 0
    local function collectStats(char, hum)
		statsN = 0
		for _, key in ipairs(rowOrder) do
			local show, ratio, text, color = readIndicator(key, char, hum)
			if show then
				statsN = statsN + 1
				local s = statsBuf[statsN]
				if not s then s = {}; statsBuf[statsN] = s end
				s.key, s.ratio, s.text, s.color = key, ratio or 0, text or "", color or Config.Ind_Accent
			end
		end
		for i = statsN + 1, #statsBuf do statsBuf[i] = nil end
		return statsBuf
    end

    -- Drawing indicator STYLE definitions (clean, NO background panel — just text +
    -- a thin accent bar per row, white text). Only two Drawing styles exist:
    --   Simple – a centred stack near the middle-bottom of the screen
    --   Player – a stack pinned to the side of the local player (left/right/bottom)
    local STYLE_DEFS = {
		Simple  = { width = 205, row = 29, txt = 14 },
		Player  = { width = 170, row = 25, txt = 13 },
		Free    = { width = 185, row = 27, txt = 14 },
    }
    local DRAW_STYLES = { Simple = true, Player = true, Free = true }

    -- ── PlayerV2: BillboardGui attached to character — floating colored bar-stack ──
    -- Each stat is a vertical colored pill that grows from 0% to 100%. Floats above head.
    -- ── PlayerV3: ScreenGui anchor — circular arc gauges pinned to character 3D point ──
    -- Uses Drawing arcs (Line circles) for a radar-style circular mini-HUD.
    local v2Bill    -- BillboardGui for PlayerV2
    local v2Bars = {}  -- [key] = { frame, fill, label }
    local v3Arcs = {}  -- [key] = { ring, arc, label, value } Drawing objects
    local V2_BAR_W, V2_BAR_H, V2_GAP = 16, 70, 4
    local V3_RADIUS = 46  -- base screen radius for arc gauges

    local function buildV2(char)
        if v2Bill then pcall(function() v2Bill:Destroy() end) end
        v2Bill = nil; v2Bars = {}
        if not char then return end
        local hrp = getRoot(char)
        if not hrp then return end
        local bill = Instance.new("BillboardGui")
        bill.Name = "\0SylV2"
        bill.Adornee = hrp
        bill.AlwaysOnTop = false
        bill.Size = UDim2.fromOffset((V2_BAR_W + V2_GAP) * #rowOrder + V2_GAP, V2_BAR_H + 30)
        bill.StudsOffset = Vector3.new(0, 3.8, 0)
        bill.ResetOnSpawn = false
        pcall(function() bill.Parent = guiParent() end)
        if not bill.Parent then bill.Parent = LocalPlayer:WaitForChild("PlayerGui") end
        v2Bill = bill

        -- background frame
        local bg = Instance.new("Frame"); bg.Name = "BG"
        bg.BackgroundColor3 = Color3.fromRGB(8,8,14); bg.BackgroundTransparency = 0.3
        bg.BorderSizePixel = 0; bg.Size = UDim2.new(1,0,1,0); bg.Parent = bill
        Instance.new("UICorner", bg).CornerRadius = UDim.new(0,8)
        Instance.new("UIStroke", bg).Color = Color3.fromRGB(45,45,65); bg:FindFirstChildOfClass("UIStroke").Transparency = 0.5

        for i, key in ipairs(rowOrder) do
            local col = Instance.new("Frame"); col.Name = key
            col.BackgroundTransparency = 1; col.BorderSizePixel = 0
            col.Position = UDim2.fromOffset((i-1)*(V2_BAR_W+V2_GAP) + V2_GAP, 4)
            col.Size = UDim2.fromOffset(V2_BAR_W, V2_BAR_H + 14)
            col.Parent = bg

            -- bar track (background)
            local track = Instance.new("Frame"); track.Name = "Track"
            track.BackgroundColor3 = Color3.fromRGB(20,20,32); track.BorderSizePixel = 0
            track.Position = UDim2.new(0,0,0,0); track.Size = UDim2.fromOffset(V2_BAR_W, V2_BAR_H)
            Instance.new("UICorner", track).CornerRadius = UDim.new(0,4); track.Parent = col

            -- fill (anchored bottom, grows upward via Size)
            local fill = Instance.new("Frame"); fill.Name = "Fill"
            fill.BackgroundColor3 = Config.Ind_Accent; fill.BorderSizePixel = 0
            fill.AnchorPoint = Vector2.new(0,1)
            fill.Position = UDim2.new(0,0,1,0); fill.Size = UDim2.new(1,0,0,0)
            Instance.new("UICorner", fill).CornerRadius = UDim.new(0,4); fill.Parent = track

            -- short label at bottom
            local lab = Instance.new("TextLabel"); lab.Name = "Label"
            lab.BackgroundTransparency = 1; lab.Font = Enum.Font.GothamBold
            lab.TextSize = 8; lab.TextColor3 = Color3.fromRGB(180,180,210)
            lab.TextXAlignment = Enum.TextXAlignment.Center
            lab.Position = UDim2.fromOffset(0, V2_BAR_H + 2); lab.Size = UDim2.fromOffset(V2_BAR_W, 12)
            local ABBREV = {Health="HP",Stamina="ST",IFrame="IF",M2="M2",Dodge="DO",Block="BL"}
            lab.Text = ABBREV[key] or key:sub(1,2):upper(); lab.Parent = col

            v2Bars[key] = { fill = fill, track = track, col = col, label = lab, dispRatio = 0 }
        end
    end

    local function destroyV2()
        if v2Bill then pcall(function() v2Bill:Destroy() end); v2Bill = nil end
        v2Bars = {}
    end

    local function buildV3()
        -- Clean up old arcs
        for _, a in pairs(v3Arcs) do
            if a.ring  then pcall(function() a.ring:Remove()  end) end
            if a.arc   then pcall(function() a.arc:Remove()   end) end
            if a.label then pcall(function() a.label:Remove() end) end
            if a.value then pcall(function() a.value:Remove() end) end
        end
        v3Arcs = {}
        if not hasDrawing then return end
        local ABBREV = {Health="HP",Stamina="ST",IFrame="IF",M2="M2",Dodge="DO",Block="BL"}
        for _, key in ipairs(rowOrder) do
            v3Arcs[key] = {
                ring  = newDrawing("Circle",{Filled=false,NumSides=36,Thickness=2.5,Visible=false,Color=Color3.fromRGB(30,30,50),ZIndex=12}),
                arc   = newDrawing("Circle",{Filled=false,NumSides=36,Thickness=3,Visible=false,Color=Config.Ind_Accent,ZIndex=13}),
                label = newDrawing("Text",{Size=11,Font=2,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Visible=false,Color=Color3.fromRGB(200,200,220),ZIndex=14}),
                value = newDrawing("Text",{Size=10,Font=2,Center=true,Outline=true,OutlineColor=Color3.new(0,0,0),Visible=false,Color=Color3.fromRGB(255,255,255),ZIndex=14}),
                dispRatio=0, alpha=0,
                abbrev = ABBREV[key] or key:sub(1,2):upper(),
            }
        end
    end

    local function destroyV3()
        for _, a in pairs(v3Arcs) do
            for _, k2 in ipairs({"ring","arc","label","value"}) do
                if a[k2] then pcall(function() a[k2]:Remove() end) end
            end
        end
        v3Arcs = {}
    end

    local function updateV2(char, hum, dt)
        if not v2Bill or not v2Bill.Parent then
            buildV2(char); return
        end
        -- re-adorn if character changed (respawn)
        local hrp = getRoot(char)
        if hrp and v2Bill.Adornee ~= hrp then v2Bill.Adornee = hrp end
        local a = math.clamp(dt * 14, 0, 1)
        for _, key in ipairs(rowOrder) do
            local b = v2Bars[key]
            if not b then return end
            local show, ratio, text, color = readIndicator(key, char, hum)
            b.col.Visible = show and true or false
            if show then
                b.dispRatio = lerp(b.dispRatio, ratio or 0, a)
                b.fill.BackgroundColor3 = color or Config.Ind_Accent
                b.fill.Size = UDim2.new(1, 0, math.clamp(b.dispRatio, 0, 1), 0)
            end
        end
    end

    local function updateV3(char, hum, dt)
        if not hasDrawing then return end
        if next(v3Arcs) == nil then buildV3() end
        local root = getRoot(char)
        if not root then
            for _, a in pairs(v3Arcs) do a.ring.Visible=false; a.arc.Visible=false; a.label.Visible=false; a.value.Visible=false end
            return
        end
        -- project a point slightly above the character's head
        local wp  = root.Position + Vector3.new(0, 4.2, 0)
        local sp, on = Camera:WorldToViewportPoint(wp)
        if not on or sp.Z < 0.1 then
            for _, a in pairs(v3Arcs) do a.ring.Visible=false; a.arc.Visible=false; a.label.Visible=false; a.value.Visible=false end
            return
        end
        local sc   = uiScale()
        local fade = math.clamp(dt * 12, 0, 1)
        local cx, cy = sp.X, sp.Y
        -- arrange N arcs in a row, spaced by 2*r+gap
        local n    = #rowOrder
        local r    = math.clamp(V3_RADIUS * sc * 22 / math.max(sp.Z, 5), 14, 50)
        local gap  = r * 0.35
        local totalW = n * (2*r + gap) - gap
        local startX = cx - totalW * 0.5 + r

        for i, key in ipairs(rowOrder) do
            local a = v3Arcs[key]
            if not a then break end
            local show, ratio, text, color = readIndicator(key, char, hum)
            a.alpha = lerp(a.alpha, show and 1 or 0, fade)
            a.dispRatio = lerp(a.dispRatio, ratio or 0, fade)
            local ax = startX + (i-1) * (2*r + gap)
            local ay = cy

            if a.alpha < 0.02 then
                a.ring.Visible=false; a.arc.Visible=false; a.label.Visible=false; a.value.Visible=false
            else
                local col = color or Config.Ind_Accent
                local tr  = 1 - a.alpha
                -- outer ghost ring
                a.ring.Position = Vector2.new(ax, ay); a.ring.Radius = r
                a.ring.Transparency = tr + (1 - tr) * 0.65; a.ring.Visible = true
                -- filled arc simulated by adjusting NumSides proportional to ratio
                -- (Drawing Circle doesn't support arc directly; we use a small circle that
                --  visually overlaps — the ring does the outline, the arc dot shows progress)
                local arcR = r * math.clamp(a.dispRatio, 0, 1)
                a.arc.Position = Vector2.new(ax, ay); a.arc.Radius = math.max(2, arcR)
                a.arc.Color = col; a.arc.Transparency = tr; a.arc.Visible = arcR > 1
                -- center label
                a.label.Text = a.abbrev
                a.label.Position = Vector2.new(ax, ay - 6*sc)
                a.label.Color = Color3.fromRGB(160,160,200); a.label.Transparency = tr; a.label.Visible = true
                -- value below
                a.value.Text = text or ""
                a.value.Position = Vector2.new(ax, ay + 4*sc)
                a.value.Color = Color3.fromRGB(255,255,255); a.value.Transparency = tr; a.value.Visible = show == true
            end
        end
    end

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
            bg = newDrawing("Square", { Filled=true, Visible=false, Color=Color3.fromRGB(11,12,17), Transparency=0.72, ZIndex=5 }),
            edgeA = newDrawing("Line", { Visible=false, Thickness=1, Color=Config.Ind_Accent, ZIndex=8 }),
            edgeB = newDrawing("Line", { Visible=false, Thickness=1, Color=Config.Ind_Accent, ZIndex=8 }),
            node = newDrawing("Circle", { Filled=true, Visible=false, Radius=3, NumSides=20, Color=Config.Ind_Accent, ZIndex=8 }),
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
		c.bg.Visible=false; c.edgeA.Visible=false; c.edgeB.Visible=false; c.node.Visible=false; c.label.Visible = false; c.value.Visible = false; c.track.Visible = false; c.fill.Visible = false
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
	local activeStats = {}
    local renderDrawStack = LPH_NO_VIRTUALIZE(function(stats, dt, def, centerX, topY, sc)
        local width, step, txtSize = def.width * sc, def.row * sc, def.txt * sc
        local left, right = centerX - width / 2, centerX + width / 2
        local aA = math.clamp(dt * 12, 0, 1)

        for k in pairs(activeStats) do activeStats[k] = nil end
        for i, s in ipairs(stats) do s.idx = i; activeStats[s.key] = s end
        for _, key in ipairs(rowOrder) do
            local c  = getDrawCell(key)
            local am = activeStats[key]
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
                local ratio = am and am.ratio or c.dispRatio
                c.dispRatio = lerp(c.dispRatio, ratio, aA)
                local col   = am and am.color or Config.Ind_Accent
                -- Design applies to every Drawing-based style (Player/Free/Simple), not just Player,
                -- so the picker is meaningful whichever draw style is active.
                local design = Config.Ind_PlayerDesign or "Neon"
                c.edgeA.Visible=false; c.edgeB.Visible=false; c.node.Visible=false

                if design == "Neon" then
                    -- Neon: dark translucent pill bg + glowing colored left border strip + subtle inner glow line
                    c.bg.Position  = Vector2.new(left - 4*sc, rowY - 3*sc)
                    c.bg.Size      = Vector2.new(width + 8*sc, txtSize + 12*sc)
                    c.bg.Color     = Color3.fromRGB(6, 6, 14)
                    c.bg.Transparency = c.alpha * 0.55
                    c.bg.Visible   = true
                    -- left neon strip
                    c.edgeA.From  = Vector2.new(left - 4*sc, rowY - 3*sc)
                    c.edgeA.To    = Vector2.new(left - 4*sc, rowY + txtSize + 9*sc)
                    c.edgeA.Color = col; c.edgeA.Thickness = math.max(2, 3*sc)
                    c.edgeA.Transparency = 1 - c.alpha; c.edgeA.Visible = true
                    -- subtle right echo strip (dim)
                    c.edgeB.From  = Vector2.new(right + 4*sc, rowY - 3*sc)
                    c.edgeB.To    = Vector2.new(right + 4*sc, rowY + txtSize + 9*sc)
                    c.edgeB.Color = col; c.edgeB.Thickness = 1
                    c.edgeB.Transparency = 1 - c.alpha * 0.35; c.edgeB.Visible = true

                elseif design == "Cyber" then
                    -- Cyber: no bg, corner tick marks (top-left + bottom-right), scanline track
                    c.bg.Visible = false
                    local CW, CH = 7*sc, 4*sc
                    -- top-left horizontal tick
                    c.edgeA.From = Vector2.new(left - 2*sc, rowY - 2*sc)
                    c.edgeA.To   = Vector2.new(left - 2*sc + CW, rowY - 2*sc)
                    c.edgeA.Color = col; c.edgeA.Thickness = math.max(1, 1.5*sc)
                    c.edgeA.Transparency = 1 - c.alpha; c.edgeA.Visible = true
                    -- bottom-right horizontal tick
                    c.edgeB.From = Vector2.new(right + 2*sc - CW, rowY + txtSize + 5*sc)
                    c.edgeB.To   = Vector2.new(right + 2*sc, rowY + txtSize + 5*sc)
                    c.edgeB.Color = col; c.edgeB.Thickness = math.max(1, 1.5*sc)
                    c.edgeB.Transparency = 1 - c.alpha; c.edgeB.Visible = true
                    -- dot accent at top-left corner
                    c.node.Position = Vector2.new(left - 2*sc, rowY - 2*sc)
                    c.node.Radius   = math.max(2, 2.5*sc)
                    c.node.Color    = col; c.node.Transparency = 1 - c.alpha; c.node.Visible = true

                elseif design == "Arc" then
                    -- Arc: wide translucent bg, colored top edge bar that fills with progress
                    c.bg.Position  = Vector2.new(left - 6*sc, rowY - 4*sc)
                    c.bg.Size      = Vector2.new(width + 12*sc, txtSize + 14*sc)
                    c.bg.Color     = lerpColor(Color3.fromRGB(8,8,20), col, 0.07)
                    c.bg.Transparency = c.alpha * 0.70
                    c.bg.Visible   = true
                    -- top edge full-width ghost line
                    c.edgeA.From  = Vector2.new(left - 6*sc, rowY - 4*sc)
                    c.edgeA.To    = Vector2.new(right + 6*sc, rowY - 4*sc)
                    c.edgeA.Color = Color3.fromRGB(60, 60, 90)
                    c.edgeA.Thickness = math.max(1, 1.5*sc)
                    c.edgeA.Transparency = 1 - c.alpha * 0.5; c.edgeA.Visible = true
                    -- top edge colored progress line (driven by dispRatio)
                    local fillEndX = (left - 6*sc) + (width + 12*sc) * math.clamp(c.dispRatio, 0, 1)
                    c.edgeB.From  = Vector2.new(left - 6*sc, rowY - 4*sc)
                    c.edgeB.To    = Vector2.new(fillEndX, rowY - 4*sc)
                    c.edgeB.Color = col; c.edgeB.Thickness = math.max(2, 2.5*sc)
                    c.edgeB.Transparency = 1 - c.alpha; c.edgeB.Visible = true

                else -- "Minimal"
                    -- Minimal: zero chrome, just a colored diamond bullet + right-aligned value.
                    -- Ultra clean — no background, no box, no border. Pure text + accent dot.
                    c.bg.Visible = false; c.edgeA.Visible = false; c.edgeB.Visible = false
                    c.node.Position = Vector2.new(left - 8*sc, rowY + txtSize * 0.45)
                    c.node.Radius   = math.max(2, 3*sc)
                    c.node.Color    = col
                    c.node.Transparency = 1 - c.alpha; c.node.Visible = true
                end

                -- Drawing API: Transparency 0 = opaque, 1 = invisible. c.alpha goes 0→1 as
                -- the row fades IN, so element transparency must be (1 - c.alpha).
                c.label.Size = txtSize
                c.label.Text = STAT_LABELS[key] or key
                c.label.Position = Vector2.new(left, rowY)
                c.label.Color = WM.txtMute
                c.label.Transparency = 1 - c.alpha
                c.label.Visible = true

                if am then c.value.Text = am.text end
                c.value.Size = txtSize
                c.value.Position = Vector2.new(right - textWidth(c.value), rowY)
                c.value.Color = WM.txtMain
                c.value.Transparency = 1 - c.alpha
                c.value.Visible = true

                local lineY = rowY + txtSize + 5 * sc
                c.track.From = Vector2.new(left, lineY); c.track.To = Vector2.new(right, lineY)
                c.track.Thickness = math.max(1, 2 * sc)
                c.track.Color = WM.stroke; c.track.Transparency = 1 - c.alpha * 0.5; c.track.Visible = true

                local fillW = width * math.clamp(c.dispRatio, 0, 1)
                c.fill.From = Vector2.new(left, lineY); c.fill.To = Vector2.new(left + fillW, lineY)
                c.fill.Thickness = math.max(1, 2 * sc)
                c.fill.Color = col; c.fill.Transparency = 1 - c.alpha; c.fill.Visible = fillW > 0.5
            end
        end
    end)

    local updateIndicators = LPH_NO_VIRTUALIZE(function(dt)
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

        -- toggle which draggable surface is live (only one container is ever shown)
        if indHolder then
            if panelBody then panelBody.Visible = (style == "Panel") and char ~= nil end
            if dragHandle then dragHandle.Visible = (style == "Free") and char ~= nil end
        end

        -- ── PANEL style (stacked chips, draggable) ──────────────────────────
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

        -- ── Drawing styles (Simple / Player / Free) ───────────────��─────────
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
                -- Beside the local player, anchored to a real 3D point. We offset the
                -- root position by a FIXED number of world studs and re-project every
                -- frame — so the stack holds a true 3D position that tracks the player
                -- through space and depth. The horizontal offset uses the camera's right
                -- vector (not the character CFrame and not GetBoundingBox, whose world
                -- AABB size oscillated with player yaw and made the panel "rotate with"
                -- the character). Result: yaw-independent, shiftlock-safe, 3D-anchored.
                local root = getRoot(char)
                if root then
                    local side = Config.Ind_PlayerSide or "Left"
                    local gap  = 8 * sc
                    local SIDE_STUDS = 2.6    -- lateral world offset (close to the body)
                    local DOWN_STUDS = 3.6    -- vertical world offset for Bottom
                    local textY = (Config.Ind_PlayerTextY or 0) * sc  -- user vertical nudge
                    if side == "Bottom" then
                        local wp = root.Position - Vector3.new(0, DOWN_STUDS, 0)
                        local fsp, on = Camera:WorldToViewportPoint(wp)
                        if on then
                            renderDrawStack(stats, dt, def, fsp.X, fsp.Y + gap + textY, sc)
                            drawn = true
                        end
                    else
                        local dir = (side == "Right") and 1 or -1
                        local wp  = root.Position + Camera.CFrame.RightVector * (SIDE_STUDS * dir)
                        local esp, on = Camera:WorldToViewportPoint(wp)
                        if on then
                            local cx   = esp.X + dir * (gap + width / 2)
                            local topY = esp.Y - totalH / 2 + textY
                            renderDrawStack(stats, dt, def, cx, topY, sc)
                            drawn = true
                        end
                    end
                end

            elseif style == "Free" and indHolder then
                -- Same clean text-stack as Player, but pinned to the draggable HUD
                -- position (drag.disp = indHolder top-left in absolute px). The invisible
                -- dragHandle below the stack catches the grab; we resize it every frame
                -- to match so the whole block is grabbable and clamps to screen edges.
                local baseX, baseY = drag.disp.X, drag.disp.Y
                renderDrawStack(stats, dt, def, baseX + width / 2, baseY, sc)
                drawn = true
                if dragHandle then
                    local scGui = (indUIScale and indUIScale.Scale > 0) and indUIScale.Scale or 1
                    -- convert the drawn (already-scaled) size back to UIScale-local units
                    dragHandle.Size = UDim2.fromOffset(width / scGui, (totalH + def.txt * sc) / scGui)
                end
            end

            if not drawn then hideAllDrawCells() end
        else
            hideAllDrawCells()
        end

        -- ── PlayerV2: vertical bar-stack BillboardGui attached to character ──────
        if char and style == "PlayerV2" then
            updateV2(char, hum, dt)
        else
            -- destroy V2 when switching away to prevent ghost GUI
            if v2Bill then destroyV2() end
        end

        -- ── PlayerV3: circular arc gauges via Drawing, 3D-anchored ───────────────
        if char and style == "PlayerV3" then
            updateV3(char, hum, dt)
        else
            if next(v3Arcs) ~= nil then destroyV3() end
        end
    end)

    -- ═════════════════════════════════════════════════════════════════���═════
    -- HIT DIRECTION  (fading arrows around the crosshair)
    -- ══════════════════════════════════════════��════════════════════════════
    local hitArrows = {}          -- active { tri, born, angle }
    local ARROW_LIFE = 1.1
    local lastHealth = nil

    local function removeArrow(h)
        if h.tri then pcall(function() h.tri:Remove() end) end
    end

    local function spawnHitArrow(angle)
        if not hasDrawing then return end
        local tri = newDrawing("Triangle", { Thickness = 1, Filled = true, Visible = false, Color = Config.HitDir_Color, ZIndex = 90 })
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

    local updateHitDir = LPH_NO_VIRTUALIZE(function()
        if not hasDrawing then return end
        local vp = Camera.ViewportSize
        local cx, cy = vp.X / 2, vp.Y / 2
        local sc = math.clamp(vp.Y / 864, 0.85, 1.7)
        if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then sc = sc * 1.1 end
        local radius = 90 * sc
        -- user opacity: 0 = fully opaque, 1 = invisible
        local userAlpha = 1 - math.clamp(Config.HitDir_Transparency or 0, 0, 1)
        local now = os.clock()
        for i = #hitArrows, 1, -1 do
            local h = hitArrows[i]
            local age = now - h.born
            if age > ARROW_LIFE or not Config.HitDir_On then
                removeArrow(h)
                table.remove(hitArrows, i)
            else
                local a = h.angle
                -- outward screen direction: 0 = up (attacker in front), +pi/2 = right
                local dirx, diry = math.sin(a), -math.cos(a)
                local perpx, perpy = -diry, dirx

                -- simple clean triangle arrow that fades out over its lifetime
                local fade  = 1 - (age / ARROW_LIFE)
                local trans = fade * userAlpha
                local tipR  = radius + 16 * sc
                local baseR = radius
                local w     = 10 * sc

                local tipx, tipy   = cx + dirx * tipR, cy + diry * tipR
                local baseCx, baseCy = cx + dirx * baseR, cy + diry * baseR

                h.tri.PointA = Vector2.new(tipx, tipy)
                h.tri.PointB = Vector2.new(baseCx + perpx * w, baseCy + perpy * w)
                h.tri.PointC = Vector2.new(baseCx - perpx * w, baseCy - perpy * w)
                h.tri.Color = Config.HitDir_Color
                h.tri.Transparency = trans
                h.tri.Visible = trans > 0.02
            end
        end
    end)

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

	-- Server-authored successful hit broadcast. Subscribe to the URE directly so we do not
	-- overwrite CombatBroadcast.On's single callback used by the game's Evasive module.
	local HitFX={systems={}}
	local TETRA={Vector3.new(1,1,1),Vector3.new(1,-1,-1),Vector3.new(-1,1,-1),Vector3.new(-1,-1,1)}
	local TEDGES={{1,2},{1,3},{1,4},{2,3},{2,4},{3,4}}
	local function victimRoot(name)
		local p=Players:FindFirstChild(name); local c=p and p.Character or Workspace:FindFirstChild(name)
		return c and c:FindFirstChild("HumanoidRootPart")
	end
	local function particleColor(t) return Config.HitFX_Color:Lerp(Config.HitParticleColorB,t) end
	local function destroySystem(sys)
		for _,p in ipairs(sys.pts) do
			if p.lines then for _,l in ipairs(p.lines) do pcall(function() l:Remove() end) end end
			if p.dot  then pcall(function() p.dot:Remove()  end) end
			if p.ring then pcall(function() p.ring:Remove() end) end
		end
	end
	local function spawnParticles(pos)
		while #HitFX.systems >= (Config.HitParticleMaxSystems or 5) do destroySystem(table.remove(HitFX.systems,1)) end
		local pts={}; local count=math.clamp(Config.HitParticleCount or 20,6,40)
		local ptype = Config.HitParticleType or "Sparks"

		for i=1,count do
			local z=math.random()
			local dir=Vector3.new(math.random()-.5,math.random()*.9+.15,math.random()-.5).Unit
			local spd=(Config.HitParticleSpeedMin or 2)+z*((Config.HitParticleSpeedMax or 32)-(Config.HitParticleSpeedMin or 2))
			local pt={
				pos=pos+dir*.08, vel=dir*spd,
				ang=Vector3.new(math.random()*6.28,math.random()*6.28,math.random()*6.28),
				av=Vector3.new((math.random()-.5)*14,(math.random()-.5)*14,(math.random()-.5)*14),
				scale=(Config.HitParticleWireScale or .4)*(.65+z*.55), z=z,
				-- per-particle random for star/orb variation
				phase=math.random()*6.28, size=.7+z*1.3,
			}
			if ptype == "Wireframe" then
				local lines={}
				for e=1,6 do lines[e]=newDrawing("Line",{Visible=false,Thickness=.8,Color=Config.HitFX_Color,ZIndex=80}) end
				pt.lines=lines
			elseif ptype == "Orbs" then
				-- Orb: large glowing filled circle that fades slowly, depth-scaled
				pt.dot=newDrawing("Circle",{Filled=true,NumSides=20,Visible=false,Radius=5,Color=Config.HitFX_Color,ZIndex=80})
				-- inner glow ring (slightly different color/size)
				pt.ring=newDrawing("Circle",{Filled=false,NumSides=20,Visible=false,Radius=7,Thickness=1.5,Color=Config.HitParticleColorB,ZIndex=79})
			elseif ptype == "Stars" then
				-- Star: 4 crossing thin lines at a fixed 2D angle, rotates over time
				local lines={}
				for e=1,4 do lines[e]=newDrawing("Line",{Visible=false,Thickness=1.2,Color=Config.HitFX_Color,ZIndex=80}) end
				pt.lines=lines
			else -- "Sparks" (default)
				-- Spark: 2 lines forming a thin elongated flash that shrinks to a dot
				local lines={}
				for e=1,2 do lines[e]=newDrawing("Line",{Visible=false,Thickness=1.5,Color=Config.HitFX_Color,ZIndex=80}) end
				pt.lines=lines
			end
			pts[i]=pt
		end
		HitFX.systems[#HitFX.systems+1]={pts=pts,age=0,duration=Config.HitParticleDuration or 1.1,ptype=ptype}
	end
	local function confirmedHit(victim)
		if not Config.HitFX_On then return end
		if Config.HitSound_On then local s=Instance.new("Sound"); s.SoundId="rbxassetid://115982072912004"; s.Volume=math.clamp(Config.HitSound_Volume or 0.75,0,1); s.Parent=SoundService; Debris:AddItem(s,4); s:Play() end
		if Config.HitParticles_On and hasDrawing then local root=victimRoot(victim); if root then spawnParticles(root.Position) end end
	end
	local renderHitFX=LPH_NO_VIRTUALIZE(function(dt)
		local cam=Camera
		for si=#HitFX.systems,1,-1 do
			local sys=HitFX.systems[si]; sys.age=sys.age+dt; local age=sys.age
			if age>=sys.duration then
				destroySystem(sys); table.remove(HitFX.systems,si)
			else
				local alpha = age<sys.duration*.15 and age/(sys.duration*.15)
				              or math.clamp((sys.duration-age)/(sys.duration*.25),0,1)
				local step  = math.clamp(dt,.001,.05)
				local ptype = sys.ptype or "Sparks"

				for _,p in ipairs(sys.pts) do
					p.vel = p.vel + Vector3.new(0, Config.HitParticleGravity or -32, 0) * step
					p.vel = p.vel * (1 - step * 0.35)
					local newPos = p.pos + p.vel * step
					-- [Physics] bounce off geometry: raycast from old pos toward new pos
					if Config.HitParticlePhysics then
						local dir = newPos - p.pos
						local dist = dir.Magnitude
						if dist > 0.001 then
							local rp = RaycastParams.new()
							rp.FilterType = Enum.RaycastFilterType.Exclude
							-- exclude characters so sparks bounce off world geometry only
							local chars = {}
							for _, pl in ipairs(Players:GetPlayers()) do
								if pl.Character then chars[#chars+1] = pl.Character end
							end
							rp.FilterDescendantsInstances = chars
							local hit = Workspace:Raycast(p.pos, dir.Unit * (dist + 0.05), rp)
							if hit then
								-- reflect velocity around surface normal, lose 35% energy
								local n = hit.Normal
								p.vel = (p.vel - 2 * p.vel:Dot(n) * n) * 0.65
								newPos = hit.Position + n * 0.05
							end
						end
					end
					p.pos = newPos
					local sp, on = cam:WorldToViewportPoint(p.pos)
					local visible = on and sp.Z > 0.05

					if ptype == "Wireframe" then
						p.ang = p.ang + p.av*step
						local rot = CFrame.Angles(p.ang.X,p.ang.Y,p.ang.Z)
						local verts={}
						for vi,o in ipairs(TETRA) do
							local sv,ov=cam:WorldToViewportPoint(p.pos+rot:VectorToWorldSpace(o*p.scale))
							verts[vi]={sv,ov and sv.Z>.05}
						end
						for ei,edge in ipairs(TEDGES) do
							local a,b=verts[edge[1]],verts[edge[2]]; local l=p.lines[ei]
							if a[2] and b[2] then
								l.From=Vector2.new(a[1].X,a[1].Y); l.To=Vector2.new(b[1].X,b[1].Y)
								l.Color=particleColor((p.z+age*.7+ei*.06)%1)
								l.Transparency=alpha*(.35+.55*p.z); l.Visible=true
							else l.Visible=false end
						end

					elseif ptype == "Orbs" then
						if visible then
							local radius = math.max(2,(2+p.size*3)*15/sp.Z)
							p.dot.Position = Vector2.new(sp.X,sp.Y)
							p.dot.Radius   = radius
							p.dot.Color    = particleColor((p.z+age*.3)%1)
							p.dot.Transparency = alpha*(.2+.35*p.z); p.dot.Visible=true
							-- glow ring slightly larger, complementary color
							p.ring.Position = Vector2.new(sp.X,sp.Y)
							p.ring.Radius   = radius*1.55
							p.ring.Color    = particleColor((p.z+age*.3+.5)%1)
							p.ring.Transparency = alpha*(.55+.35*p.z); p.ring.Visible=true
						else p.dot.Visible=false; p.ring.Visible=false end

					elseif ptype == "Stars" then
						if visible then
							-- Symmetric 4-arm star: each arm grows from center outward equally.
							-- depth-clamp prevents blow-up at close range.
							local baseA   = age * 3 + p.phase
							local armLen  = math.clamp((1.2 + p.z * 2.5) * 14 / math.max(sp.Z, 4), 2, 28)
							local fadeLen = armLen * (1 - age / sys.duration * 0.6) -- arms shrink as they age
							local cx, cy  = sp.X, sp.Y
							for arm = 1, 4 do
								local a  = baseA + (arm - 1) * math.pi * 0.5  -- 90° apart = perfect cross
								local ex, ey = math.cos(a) * fadeLen, math.sin(a) * fadeLen
								local l  = p.lines[arm]
								-- from center outward symmetrically: tip = center ± arm
								l.From = Vector2.new(cx - ex, cy - ey)
								l.To   = Vector2.new(cx + ex, cy + ey)
								l.Color = particleColor((p.z + age * 0.5 + arm * 0.15) % 1)
								l.Thickness = math.max(1, (1.8 - age / sys.duration) * 1.2)
								l.Transparency = 1 - alpha * (0.55 + 0.4 * p.z)
								l.Visible = true
							end
						else for _, l in ipairs(p.lines) do l.Visible = false end end

					else -- "Sparks"
						if visible then
							-- Sparks: depth-clamped tail elongated in travel direction.
							-- sp.Z clamped to ≥4 to prevent blow-up when camera is very close.
							local sp2, on2 = cam:WorldToViewportPoint(p.pos + p.vel * 0.04)
							local tailX = on2 and (sp2.X - sp.X) or 0
							local tailY = on2 and (sp2.Y - sp.Y) or 0
							local tailLen = math.sqrt(tailX * tailX + tailY * tailY)
							if tailLen < 0.5 then tailX, tailY = 0, -2 end
							-- clamp depth: sp.Z ≥ 4 prevents enormous sparks at close range
							local depthSafe = math.max(sp.Z, 4)
							local tscale = math.clamp((1.5 + p.size * 1.5) * 12 / depthSafe, 0.5, 18)
							local l1 = p.lines[1]
							l1.From = Vector2.new(sp.X, sp.Y)
							l1.To   = Vector2.new(sp.X - tailX * tscale * 0.45, sp.Y - tailY * tscale * 0.45)
							l1.Color = particleColor((p.z + age * 0.6) % 1)
							l1.Thickness = math.max(1, tscale * 0.12)
							l1.Transparency = 1 - alpha * (0.75 + 0.2 * p.z)
							l1.Visible = true
							-- perpendicular cross-flash at tip
							local l2 = p.lines[2]
							local perpX, perpY = -tailY, tailX
							local pMag = math.sqrt(perpX * perpX + perpY * perpY) + 0.001
							perpX, perpY = perpX / pMag, perpY / pMag
							local w = math.clamp(tscale * 0.3, 0.5, 6)
							l2.From = Vector2.new(sp.X - perpX * w, sp.Y - perpY * w)
							l2.To   = Vector2.new(sp.X + perpX * w, sp.Y + perpY * w)
							l2.Color = particleColor((p.z + age * 0.6 + 0.25) % 1)
							l2.Thickness = math.max(1, tscale * 0.09)
							l2.Transparency = 1 - alpha * (0.6 + 0.3 * p.z)
							l2.Visible = true
						else for _, l in ipairs(p.lines) do l.Visible = false end end
					end
				end
			end
		end
	end)

    -- ═══════════════════════════════════════════════════════════════════════
    -- Lifecycle wiring
    -- ═══════════════════════════��═══════════════════════════════════════════
    local conns = {}
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
            VisualCtl.bindName(LocalPlayer.Character)
        end)
        track(Players.PlayerAdded, rebuildEspPlayers)
        track(Players.PlayerRemoving, function(plr) destroyEsp(plr); rebuildEspPlayers() end)
        VisualCtl.bindFOV()
        VisualCtl.bindName(LocalPlayer.Character)
		local net=ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Network")
		local ure=net and net:FindFirstChild("CombatBroadcastURE")
		if ure then track(ure.OnClientEvent,function(ev,attacker,victim)
			if (ev=="M1Hit" or ev=="M2Hit") and LocalPlayer.Character and attacker==LocalPlayer.Character.Name and victim~=attacker then confirmedHit(victim) end
		end) end

        -- master render loop — bound to Heartbeat, NOT RenderStepped.
        -- RenderStepped fires BEFORE Roblox's camera BindToRenderStep step, so under
        -- shiftlock (which offsets the camera to the shoulder every frame) we projected
        -- every enemy with a one-frame-stale camera → the persistent sideways drift.
        -- Heartbeat fires AFTER the whole render step (camera already updated), so
        -- Camera.CFrame is fully current and the shiftlock offset is baked in. This is
        -- exactly how the working BRM5 ESP avoids the shift. The one-frame draw latency
        -- is imperceptible and is the correct trade-off here.
        local _acc, _espWasOn, indicatorsWereOn = 0, false, false
        track(RunService.Heartbeat, LPH_NO_VIRTUALIZE(function(dt)
            -- [PERF] Throttle the heavy redraw to MaxFPS. We accumulate real time and only run the
            -- pipeline once per frame-budget, passing the ACCUMULATED dt so every lerp/animation
            -- advances by true elapsed time (smooth even though we tick fewer times/sec).
            _acc = _acc + dt
            local budget = (Config.MaxFPS and Config.MaxFPS > 0) and (1 / Config.MaxFPS) or 0
            if _acc < budget then return end
            local fdt = _acc
            _acc = 0

            if hasDrawing then
                if Config.ESP_On then
                    -- [PERF] Resolve the local player's root + viewport ONCE per tick.
                    -- These are identical for all N tracked players, so doing them
                    -- here (instead of inside updateEspFor per player) removes N-1
                    -- redundant getChar/getRoot/ViewportSize reads every frame.
                    local lpChar = getChar(LocalPlayer)
                    _frLpRoot = lpChar and getRoot(lpChar) or nil
                    _frVP = Camera and Camera.ViewportSize or nil
                    -- Only touch players (and lazily create their pools) while ESP is actually on.
                    for i = 1, _espCount do updateEspFor(_espPlayers[i]) end
                    _espWasOn = true
                elseif _espWasOn then
                    -- ESP just turned off → hide existing pools ONCE, then stop iterating entirely.
                    for _, o in pairs(espPool) do hideEsp(o) end
                    _espWasOn = false
                end
            end
			-- Avoid all indicator attribute reads/property writes while disabled. One transition
			-- tick hides any live rows/cells; subsequent frames skip the subsystem entirely.
			if Config.Ind_On then
				updateIndicators(fdt)
			elseif indicatorsWereOn then
				updateIndicators(fdt)
			end
			indicatorsWereOn = Config.Ind_On
			pollLocalDamage()
			if Config.HitDir_On or #hitArrows > 0 then updateHitDir() end
			if #HitFX.systems>0 then renderHitFX(fdt) end
            end))
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
        return section:Toggle({
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

        -- ─────────────── Camera + local nametag ───────────────
        local sLocal = V:Section({ Side = "Right" })
        sLocal:Header({ Name = "Camera" })
        sLocal:Toggle({
            Name = "FOV Changer", Default = Config.FOV_On,
            Callback = function(v)
                Config.FOV_On = v and true or false
                if Config.FOV_On then VisualCtl.applyFOV() else VisualCtl.restoreFOV() end
                notify("FOV Changer", Config.FOV_On and "Enabled" or "Disabled")
            end,
        }, ctx.flag("VIS_FOV_On"))
        sLocal:Slider({
            Name = "Field of View", Default = Config.FOV_Value,
            Minimum = 30, Maximum = 120, Precision = 0, Suffix = "°",
            Callback = function(v) Config.FOV_Value = v; VisualCtl.applyFOV() end,
        }, ctx.flag("VIS_FOV_Value"))
        sLocal:SubLabel({ Text = "Undetected local camera FOV. Held against the game's own writes only while enabled." })

        sLocal:Divider()
        sLocal:Header({ Name = "Name Changer" })
        sLocal:Toggle({
            Name = "Name Changer", Default = Config.Name_On,
            Callback = function(v)
                Config.Name_On = v and true or false
                VisualCtl.applyName()
                notify("Name Changer", Config.Name_On and "Enabled" or "Disabled")
            end,
        }, ctx.flag("VIS_Name_On"))
        sLocal:SubLabel({ Text = "Default: Syllinse Project. Local-only; updates the game's own billboard/nameplate." })
		local customInputs = {}
		local function setCustomInputVisibility(v)
			for _, el in ipairs(customInputs) do pcall(function() el:SetVisibility(v) end) end
		end
		sLocal:Toggle({
            Name = "Custom", Default = Config.Name_Custom,
			Callback = function(v)
				Config.Name_Custom = v and true or false
				setCustomInputVisibility(Config.Name_Custom)
				VisualCtl.applyName()
			end,
        }, ctx.flag("VIS_Name_Custom"))
		customInputs[1] = sLocal:Input({
            Name = "First Name", Default = Config.Name_First, Placeholder = "Syllinse",
            AcceptedCharacters = "All", CharacterLimit = 24,
            Callback = function(v) Config.Name_First = tostring(v or ""); VisualCtl.applyName() end,
            onChanged = function(v) Config.Name_First = tostring(v or ""); VisualCtl.applyName() end,
        }, ctx.flag("VIS_Name_First"))
        customInputs[2] = sLocal:Input({
            Name = "Last Name", Default = Config.Name_Last, Placeholder = "Project",
            AcceptedCharacters = "All", CharacterLimit = 24,
            Callback = function(v) Config.Name_Last = tostring(v or ""); VisualCtl.applyName() end,
            onChanged = function(v) Config.Name_Last = tostring(v or ""); VisualCtl.applyName() end,
        }, ctx.flag("VIS_Name_Last"))
		setCustomInputVisibility(Config.Name_Custom)

        -- ─────────────── Section 1: ESP (Left) ───────────────
        local sEsp = V:Section({ Side = "Left" })
        sEsp:Header({ Name = "ESP" })
        feature(sEsp, {
            Title = "ESP", Flag = "VIS_ESP",
            get = function() return Config.ESP_On end,
            set = function(v) Config.ESP_On = v end,
            Desc = "If u fr dont know wtf is that - kys",
        })
        sEsp:Divider()
        sEsp:Header({ Name = "Elements" })
        boolToggle(sEsp, "Box",      "ESP Box",      function() return Config.ESP_Box end,      function(v) Config.ESP_Box = v end)
        boolToggle(sEsp, "Name",     "ESP Name",     function() return Config.ESP_Name end,     function(v) Config.ESP_Name = v end)
        boolToggle(sEsp, "Distance", "ESP Distance", function() return Config.ESP_Distance end, function(v) Config.ESP_Distance = v end)
        boolToggle(sEsp, "Health Bar", "ESP Health", function() return Config.ESP_Health end,   function(v) Config.ESP_Health = v end)
        boolToggle(sEsp, "Heavy (M2) Bar", "ESP M2Bar", function() return Config.ESP_M2Bar end, function(v) Config.ESP_M2Bar = v end)
        boolToggle(sEsp, "Combat State", "ESP State", function() return Config.ESP_State end,    function(v) Config.ESP_State = v end)
        boolToggle(sEsp, "Combat Style", "ESP Style", function() return Config.ESP_Style end,    function(v) Config.ESP_Style = v end)
        boolToggle(sEsp, "Skeleton", "ESP Skeleton", function() return Config.ESP_Skeleton end, function(v) Config.ESP_Skeleton = v end)
        boolToggle(sEsp, "Tracer",   "ESP Tracer",   function() return Config.ESP_Tracer end,   function(v) Config.ESP_Tracer = v end)

        sEsp:Divider()
        sEsp:Header({ Name = "Colors" })
        colorpick(sEsp, "Box Color", "VIS_ESP_BoxCol", Config.ESP_Box_Color, function(c) Config.ESP_Box_Color = c end)
        colorpick(sEsp, "Text Color", "VIS_ESP_TxtCol", Config.ESP_Text_Color, function(c) Config.ESP_Text_Color = c end)
        colorpick(sEsp, "Heavy (M2) Bar Color", "VIS_ESP_M2Col", Config.ESP_M2_Color, function(c) Config.ESP_M2_Color = c end)

        sEsp:Divider()
        sEsp:Header({ Name = "Performance" })
		slider(sEsp,{Name="Range",Flag="VIS_ESP_Range",Default=Config.ESP_Range,Min=50,Max=3000,Suffix=" st",Callback=function(v) Config.ESP_Range=v end})
        sEsp:SubLabel({ Text = "Max render distance. Players farther than this are skipped entirely." })
        slider(sEsp, { Name = "Render FPS Cap", Flag = "VIS_MaxFPS", Default = Config.MaxFPS,
            Min = 30, Max = 240, Suffix = " fps", Callback = function(v) Config.MaxFPS = v end })
        sEsp:SubLabel({ Text = "Caps how often visuals redraw. Lower = less CPU/GPU (60 is smooth). Raise only if you have a high-refresh monitor and spare frames." })
        if not hasDrawing then
            sEsp:SubLabel({ Text = "Drawing API not available in this executor - ESP/Hit Direction disabled." })
        end
        -- ─────────────── Environment (Left) ───────────────
        local sEnv = V:Section({ Side = "Left" })
        sEnv:Header({ Name = "Environment" })
        sEnv:Toggle({ Name = "Enabled", Default = Config.Env_On,
            Callback = function(v) EnvCtl.set(v) end }, ctx.flag("VIS_ENV_On"))
        sEnv:SubLabel({ Text = "Local lighting override. Restores the game's original values when disabled." })

        sEnv:Divider()
        sEnv:Header({ Name = "Colors" })
        colorpick(sEnv, "Ambient", "VIS_ENV_Amb", Config.Env_Ambient, function(c) Config.Env_Ambient=c; EnvCtl.apply() end)
        colorpick(sEnv, "Outdoor Ambient", "VIS_ENV_Out", Config.Env_Outdoor, function(c) Config.Env_Outdoor=c; EnvCtl.apply() end)
        colorpick(sEnv, "Fog Color", "VIS_ENV_Fog", Config.Env_FogColor, function(c) Config.Env_FogColor=c; EnvCtl.apply() end)
        colorpick(sEnv, "Atmosphere Color", "VIS_ENV_Atm", Config.Env_AtmosColor, function(c) Config.Env_AtmosColor=c; EnvCtl.apply() end)

        sEnv:Divider()
        sEnv:Header({ Name = "Fog & Atmosphere" })
        slider(sEnv, { Name = "Fog Start", Flag = "VIS_ENV_FS", Default = Config.Env_FogStart, Min = 0, Max = 5000, Suffix = " st", Callback = function(v) Config.Env_FogStart=v; EnvCtl.apply() end })
        slider(sEnv, { Name = "Fog End", Flag = "VIS_ENV_FE", Default = Config.Env_FogEnd, Min = 10, Max = 10000, Suffix = " st", Callback = function(v) Config.Env_FogEnd=v; EnvCtl.apply() end })
        slider(sEnv, { Name = "Atmosphere Density", Flag = "VIS_ENV_AD", Default = Config.Env_AtmosDensity, Min = 0, Max = 1, Precision = 2, Callback = function(v) Config.Env_AtmosDensity=v; EnvCtl.apply() end })
        sEnv:SubLabel({ Text = "Density also overrides the game's weather Atmosphere so fog changes actually show." })

        sEnv:Divider()
        sEnv:Header({ Name = "Lighting" })
        slider(sEnv, { Name = "Brightness", Flag = "VIS_ENV_B", Default = Config.Env_Brightness, Min = 0, Max = 10, Precision = 2, Callback = function(v) Config.Env_Brightness=v; EnvCtl.apply() end })
        slider(sEnv, { Name = "Clock Time", Flag = "VIS_ENV_T", Default = Config.Env_ClockTime, Min = 0, Max = 24, Precision = 1, Callback = function(v) Config.Env_ClockTime=v; EnvCtl.apply() end })

        -- ─────────────── Hit Effects (Left) ───────────────
        local sFX = V:Section({ Side = "Left" })
        sFX:Header({ Name = "Hit Effects" })
        boolToggle(sFX, "Enabled", "Hit Effects", function() return Config.HitFX_On end, function(v) Config.HitFX_On=v end)
        sFX:SubLabel({ Text = "Plays on a server-confirmed hit YOU landed (M1Hit/M2Hit broadcast)." })

        sFX:Divider()
        sFX:Header({ Name = "Sound" })
        boolToggle(sFX, "Hit Sound", "Hit Sound", function() return Config.HitSound_On end, function(v) Config.HitSound_On=v end)
        slider(sFX, { Name = "Volume", Flag = "VIS_HITFX_VOL", Default = math.floor((Config.HitSound_Volume or 0.75)*100), Min = 0, Max = 100, Suffix = "%", Callback = function(v) Config.HitSound_Volume = v/100 end })

        sFX:Divider()
        sFX:Header({ Name = "Particles" })
        boolToggle(sFX, "Hit Particles", "Hit Particles", function() return Config.HitParticles_On end, function(v) Config.HitParticles_On=v end)

        -- particle type dropdown + per-type unique settings
        local particleTypeEls = {}
        local function applyParticleTypeVis()
            local cur = Config.HitParticleType or "Sparks"
            for el, types in pairs(particleTypeEls) do
                local vis = false
                if types == "*" then vis = true
                else for _, t in ipairs(types) do if t == cur then vis = true; break end end end
                pcall(function() el:SetVisibility(vis) end)
            end
        end
        pcall(function()
            sFX:Dropdown({
                Name = "Particle Type",
                Options = { "Sparks", "Orbs", "Stars", "Wireframe" },
                Default = Config.HitParticleType or "Sparks",
                Callback = function(v)
                    if type(v) == "string" and v ~= "" then
                        Config.HitParticleType = v
                        Config.HitParticleWireframe = (v == "Wireframe")
                        applyParticleTypeVis()
                    end
                end,
            }, ctx.flag("VIS_HITFX_PType"))
        end)
        sFX:SubLabel({ Text = "Sparks = chaotic elongated flashes | Orbs = glowing depth spheres | Stars = rotating 4-arm stars | Wireframe = spinning 3D tetra shards" })

        colorpick(sFX, "Primary Color",   "VIS_HITFX_C",  Config.HitFX_Color,         function(c) Config.HitFX_Color=c end)
        colorpick(sFX, "Secondary Color", "VIS_HITFX_C2", Config.HitParticleColorB,    function(c) Config.HitParticleColorB=c end)
        slider(sFX, { Name = "Particle Count", Flag = "VIS_HITFX_N", Default = Config.HitParticleCount,   Min = 6,   Max = 40,  Callback = function(v) Config.HitParticleCount=v end })
        slider(sFX, { Name = "Duration",       Flag = "VIS_HITFX_D", Default = Config.HitParticleDuration,Min = .3,  Max = 2.5, Precision = 1, Suffix = " s", Callback = function(v) Config.HitParticleDuration=v end })
        slider(sFX, { Name = "Speed",          Flag = "VIS_HITFX_V", Default = Config.HitParticleSpeedMax,Min = 5,   Max = 50,  Callback = function(v) Config.HitParticleSpeedMax=v end })
        slider(sFX, { Name = "Gravity",        Flag = "VIS_HITFX_G", Default = Config.HitParticleGravity, Min = -80, Max = 10,  Callback = function(v) Config.HitParticleGravity=v end })

        -- Wireframe-only: wire scale
        local wireScaleEl = slider(sFX, { Name = "Wire Scale", Flag = "VIS_HITFX_S",
            Default = Config.HitParticleWireScale, Min = .15, Max = 1, Precision = 2,
            Callback = function(v) Config.HitParticleWireScale=v end })
        particleTypeEls[wireScaleEl] = { "Wireframe" }

        boolToggle(sFX, "Physics Bounce", "Particle Physics",
            function() return Config.HitParticlePhysics end,
            function(v) Config.HitParticlePhysics = v and true or false end)
        sFX:SubLabel({ Text = "Particles bounce off world geometry (Raycast). More realistic but heavier on CPU." })

        applyParticleTypeVis()

        -- ─────────────── Section 2: Indicators (Right) ───────────────
        local sInd = V:Section({ Side = "Right" })
        sInd:Header({ Name = "Indicators" })
        feature(sInd, {
            Title = "Indicators", Flag = "VIS_IND",
            get = function() return Config.Ind_On end,
            set = function(v) Config.Ind_On = v end,
            Desc = "Animated HUD",
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
                Options = { "Panel", "Free", "Player", "Simple", "PlayerV2", "PlayerV3" },
                Default = Config.Ind_Style,
                Callback = function(v)
                    if type(v) == "string" and v ~= "" then Config.Ind_Style = v; applyStyleVis() end
                end,
            }, ctx.flag("VIS_IND_Style"))
        end)
        sInd:SubLabel({ Text = "Panel/Free/Player/Simple = Drawing-based | PlayerV2 = vertical bar pills above char | PlayerV3 = circular arc gauges above char." })

        sInd:Divider()
        sInd:Header({ Name = "Cooldowns" })
        boolToggle(sInd, "Health",       "Ind Health",  function() return Config.Ind_Health end,  function(v) Config.Ind_Health = v end)
        boolToggle(sInd, "Stamina",      "Ind Stamina", function() return Config.Ind_Stamina end, function(v) Config.Ind_Stamina = v end)
        boolToggle(sInd, "IFrame",       "Ind IFrame",  function() return Config.Ind_IFrame end,  function(v) Config.Ind_IFrame = v end)
        boolToggle(sInd, "Heavy (M2) CD", "Ind Heavy",  function() return Config.Ind_M2 end,      function(v) Config.Ind_M2 = v end)
        boolToggle(sInd, "Dodge CD",     "Ind Dodge",   function() return Config.Ind_Dodge end,   function(v) Config.Ind_Dodge = v end)
        boolToggle(sInd, "Block CD",     "Ind Block",   function() return Config.Ind_Block end,   function(v) Config.Ind_Block = v end)

        sInd:Divider()
        sInd:Header({ Name = "Appearance" })
        colorpick(sInd, "Accent Color", "VIS_IND_Accent", Config.Ind_Accent, function(c) Config.Ind_Accent = c end)

        -- ── Per-style settings (shown only for the relevant style) ──
        -- Draggable styles (Panel / Free): reset button + drag lock.
        local resetBtn = sInd:Button({ Name = "Reset HUD Position", Callback = function() resetPos() end })
        styleEls[resetBtn] = { "Panel", "Free" }
        local dragToggle = boolToggle(sInd, "Drag", "Ind Drag",
            function() return Config.Ind_Drag end, function(v) Config.Ind_Drag = v end)
        styleEls[dragToggle] = { "Panel", "Free" }
        local dragHint = sInd:SubLabel({ Text = "Grab the HUD to move it. Turn Drag off to lock it" })
        styleEls[dragHint] = { "Panel", "Free" }

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

        -- Design: one of four looks. Applies to every Drawing style (Player/Free/Simple).
        pcall(function()
            local designDd = sInd:Dropdown({
                Name = "Design",
                Options = { "Neon", "Cyber", "Arc", "Minimal" },
                Default = Config.Ind_PlayerDesign,
                Callback = function(v) if type(v) == "string" and v ~= "" then Config.Ind_PlayerDesign = v end end,
            }, ctx.flag("VIS_IND_PlayerDesign"))
            styleEls[designDd] = { "Player", "Free", "Simple" }
        end)
        local designHint = sInd:SubLabel({ Text = "Neon = dark pill + glowing border | Cyber = corner ticks + dot | Arc = progress top-edge bar | Minimal = clean bullet dot (Player, Free, Simple)." })
        styleEls[designHint] = { "Player", "Free", "Simple" }

        -- Player: vertical text nudge relative to the character.
        local playerTextY = slider(sInd, {
            Name = "Text Position", Flag = "VIS_IND_PlayerTextY", Default = math.floor(Config.Ind_PlayerTextY or 0),
            Min = -120, Max = 120, Suffix = "px", Callback = function(v) Config.Ind_PlayerTextY = v end,
        })
        styleEls[playerTextY] = { "Player" }

        -- Simple: vertical position on screen.
        local screenYSlider = slider(sInd, {
            Name = "Screen Position", Flag = "VIS_IND_ScreenY", Default = math.floor((Config.Ind_ScreenY or 0.6) * 100),
            Min = 20, Max = 92, Suffix = "%", Callback = function(v) Config.Ind_ScreenY = v / 100 end,
        })
        styleEls[screenYSlider] = { "Simple" }

        -- All styles: manual scale on top of the automatic mobile rescale.
        local scaleSlider = slider(sInd, {
            Name = "Scale", Flag = "VIS_IND_Scale", Default = math.floor((Config.Ind_Scale or 1) * 100),
            Min = 60, Max = 200, Suffix = "%", Callback = function(v) Config.Ind_Scale = v / 100 end,
        })
        styleEls[scaleSlider] = { "Panel", "Free", "Player", "Simple" }

        applyStyleVis()

        -- ─────────────── Hit Direction (Right) ───────────────
        local sHit = V:Section({ Side = "Right" })
        sHit:Header({ Name = "Hit Direction" })
        feature(sHit, {
            Title = "Hit Direction", Flag = "VIS_HITDIR",
            get = function() return Config.HitDir_On end,
            set = function(v) Config.HitDir_On = v end,
            Desc = "Fading arrows around the crosshair when you take a hit",
        })
        sHit:Divider()
        sHit:Header({ Name = "Appearance" })
        colorpick(sHit, "Arrow Color", "VIS_HIT_Col", Config.HitDir_Color, function(c) Config.HitDir_Color = c end)
        slider(sHit, {
            Name = "Transparency", Flag = "VIS_HIT_Transp", Default = math.floor((Config.HitDir_Transparency or 0) * 100),
            Min = 0, Max = 90, Suffix = "%", Callback = function(v) Config.HitDir_Transparency = v / 100 end,
        })

        uiReady = true
    end

    function M.stop()
		EnvCtl.set(false)
        VisualCtl.restoreAll()
        VisualCtl.clearNameConns()
        if VisualCtl.fovConn then VisualCtl.fovConn:Disconnect(); VisualCtl.fovConn = nil end
		if cameraConn then cameraConn:Disconnect(); cameraConn = nil end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        for _, c in ipairs(dragConns) do pcall(function() c:Disconnect() end) end
        dragConns = {}
        for plr in pairs(espPool) do destroyEsp(plr) end
        for _, h in ipairs(hitArrows) do removeArrow(h) end
        hitArrows = {}
		for _,sys in ipairs(HitFX.systems) do destroySystem(sys) end
		HitFX.systems={}
        for _, c in pairs(drawCells) do
            for _, key in ipairs({ "bg", "edgeA", "edgeB", "node", "label", "value", "track", "fill" }) do
                if c[key] then pcall(function() c[key]:Remove() end) end
            end
        end
        drawCells = {}
        indUIScale = nil
        destroyV2()
        destroyV3()
        if screenGui then pcall(function() screenGui:Destroy() end); screenGui = nil end
    end

    return M
end
