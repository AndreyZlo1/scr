-- ═══════════════════════════════════════════════════════════════════════════
--  Movement — standalone module for the Syllinse loader (AutoParry game,
--  UniverseId 9199655655 — the "so you're challenging me" combat game).
--
--  Loader contract:
--    • file body returns function(Lib, Core) → returns a handle with
--      optional start() and buildUI(ctx).
--    • ctx gives: tabs (keyed by Tab.Key), flag(name), keybind(section,opts),
--      notify(title,desc). Everything is built into ctx.tabs.Movement.
--
--  Everything below is derived from the game's OWN decompiled client, verified
--  against the dump — no guessing:
--
--    • Speed / Fly are the vape-style CFrame/Velocity methods on PreSimulation,
--      driven by Humanoid.MoveDirection (works on PC WASD + mobile thumbstick).
--      Fly is camera-relative: thumbstick + camera pitch = full 3D (mobile
--      friendly). Vertical keys are Space (up) / LeftControl (down) — NOT Shift,
--      so it never fights Roblox shiftlock. Mobile jump button = ascend.
--
--    • NoComboWait — THE fix. The M1 chain gate (CombatSystemClient.Combat.Base.M1):
--        v51   = getFinalM1AnimSpeed(char, combo)
--                = AttackSpeedMult * CombatPingAnimUtils.GetPingAnimSpeedMultiplier(...)
--        line 464:  if AnimationHandler.IsAnim(char,"M1",nextAnim) then return end  -- blocks WHILE the swing anim still plays
--        scheduleM1SwingTimers: u21=false; task.delay((combo==4 and 1.25 or 0.45)/v51, ()->u21=true)
--      Both the "anim still playing" gate AND the wait length scale with v51.
--      So we HOOK GetPingAnimSpeedMultiplier and multiply its result: the M1
--      animation plays faster → IsAnim clears almost instantly AND the delay
--      (/v51) collapses. That removes the pause before the next hit / new combo.
--      The server "M1Cooldown" attribute still applies, so this speeds the chain
--      up to the server limit — not literal 0 ms spam.
--
--    • No Stun — StateHandler.SetStun(char, apply, dur, speed) sets the "Stunned"
--      attribute and writes WalkSpeed/GroundSpeed down, restoring later. We hook
--      it and no-op when apply==true for OUR character → we are never stunned.
--
--    • Ping Spoof — CombatPingAnimUtils and other systems read player:GetNetworkPing().
--      We hook __namecall on "GetNetworkPing" and return a spoofed value (seconds).
--      Low spoof → ping anim-compensation stops slowing your combat anims. This is
--      a client-side ping-value spoof (affects the game's ping-based logic/anim),
--      not a true network lag switch.
--
--    • AutoSprint — MovementServiceClient singleton (has _sprintInputDesired).
--      ON  → SetSprintInputDesired(true) + StartSprint(); the game auto-resumes.
--      OFF → SetSprintInputDesired(false) + StopSprint(false) → truly stops.
--      Sprint speed = 25 (GetSprintSpeed), base walk = 12, needs HP ≥ 10.
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    local Players          = game:GetService("Players")
    local RunService       = game:GetService("RunService")
    local UserInputService  = game:GetService("UserInputService")
    local Workspace        = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer

    -- ── Executor globals (guarded — never hard-crash on a weak executor) ─────
    local _filtergc     = rawget(getfenv(0), "filtergc")      or (getgenv and getgenv().filtergc)
    local _getgc        = rawget(getfenv(0), "getgc")          or (getgenv and getgenv().getgc)
    local _hookfunction = rawget(getfenv(0), "hookfunction")  or (getgenv and getgenv().hookfunction)
    local _hookmeta     = rawget(getfenv(0), "hookmetamethod") or (getgenv and getgenv().hookmetamethod)
    local _namecall     = rawget(getfenv(0), "getnamecallmethod") or (getgenv and getgenv().getnamecallmethod)
    local _checkcaller  = rawget(getfenv(0), "checkcaller")   or (getgenv and getgenv().checkcaller) or function() return false end
    local _hasHookFn    = type(_hookfunction) == "function"
    local _hasHookMeta  = type(_hookmeta) == "function" and type(_namecall) == "function"

    -- PreSimulation runs BEFORE physics (what the vape reference uses), so our
    -- CFrame / velocity writes win the frame. Heartbeat runs AFTER the game's
    -- combat WalkSpeed writes, so NoSlowdown re-asserts there and wins.
    local PreStep   = RunService.PreSimulation or RunService.Stepped
    local PostStep  = RunService.Heartbeat

    -- Game constants (from MovementServiceUtils / CombatConfig).
    local BASE_WALK   = 12
    local SPRINT_WALK = 25
    local SPEED_CAP   = 25    -- move anti-cheat authorises ≈ sprint + 1.35

    -- ── Runtime config (MacLib restores flags through the config manager) ────
    local Config = {
        -- Speed (vape-style, method-based)
        Speed_On    = false,
        Speed_Mode  = "CFrame",   -- CFrame | Velocity
        Speed_Value = 45,         -- studs/sec

        -- Fly (vape-style, method-based, camera-relative)
        Fly_On       = false,
        Fly_Mode     = "CFrame",  -- CFrame | Velocity
        Fly_Value    = 60,        -- horizontal studs/sec
        Fly_Vertical = 60,        -- vertical studs/sec
        Fly_Face     = true,      -- PlatformStand + move relative to camera pitch

        -- No Slowdown (master + per-type)
        NS_On     = false,
        NS_Attack = true,
        NS_Block  = true,
        NS_Stun   = false,
        NS_Force  = 0,            -- 0 = restore to game base; >0 = force this speed (capped 25)

        -- No Combo Wait (animation-speed method)
        NCW_On   = false,
        NCW_Mult = 2.0,           -- multiplies M1 anim speed → shrinks the chain wait

        -- No Stun (stun immunity)
        NoStun_On = false,

        -- Ping Spoof
        Ping_On    = false,
        Ping_Value = 0,           -- spoofed ping in ms

        -- Sprint
        Sprint_On   = false,      -- AutoSprint (hold sprint on)
    }

    -- ═════════════════════════ Character helpers ════════════════════════════
    local function getChar()
        local c = LocalPlayer.Character
        if not c or not c.Parent then return nil end
        return c
    end
    local function getParts()
        local c = getChar(); if not c then return nil end
        local hum  = c:FindFirstChildOfClass("Humanoid")
        local root = c:FindFirstChild("HumanoidRootPart") or (hum and hum.RootPart)
        if not hum or not root or hum.Health <= 0 then return nil end
        return c, hum, root
    end

    -- ══════════════════════════ Move-vector math ════════════════════════════
    -- MoveDirection is world-space horizontal input, already camera-relative
    -- (PC WASD + mobile thumbstick). For Fly we optionally remap it onto the
    -- camera basis so camera PITCH gives vertical movement → full 3D from a
    -- single thumbstick (the mobile-friendly part).
    local function cameraRelative(moveDir)
        local cam = Workspace.CurrentCamera
        if not cam or moveDir.Magnitude < 1e-3 then return moveDir end
        local cf = cam.CFrame
        local flatFwd   = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
        local flatRight = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
        if flatFwd.Magnitude   < 1e-3 then return moveDir end
        if flatRight.Magnitude < 1e-3 then return moveDir end
        flatFwd, flatRight = flatFwd.Unit, flatRight.Unit
        local f = moveDir:Dot(flatFwd)      -- forward / back amount
        local r = moveDir:Dot(flatRight)    -- strafe amount
        local dir = (cf.LookVector * f) + (cf.RightVector * r)
        if dir.Magnitude < 1e-3 then return moveDir end
        return dir.Unit
    end

    -- ═══════════════════════════════ SPEED ══════════════════════════════════
    -- CFrame  → shift the root by moveVec*speed*dt (positional, beats the WalkSpeed
    --           anti-cheat since WalkSpeed itself is untouched).
    -- Velocity→ set horizontal AssemblyLinearVelocity, keep gravity on Y.
    local function stepSpeed(dt)
        if not Config.Speed_On then return end
        local _, hum, root = getParts(); if not hum then return end
        local moveDir = hum.MoveDirection
        if moveDir.Magnitude < 1e-3 then return end
        local speed = Config.Speed_Value
        if Config.Speed_Mode == "Velocity" then
            local y = root.AssemblyLinearVelocity.Y
            root.AssemblyLinearVelocity = (moveDir * speed) + Vector3.new(0, y, 0)
        else -- CFrame
            root.CFrame = root.CFrame + (moveDir * speed * dt)
        end
    end

    -- ════════════════════════════════ FLY ═══════════════════════════════════
    local flyUp, flyDown = 0, 0        -- vertical input state
    local flyConns = {}                -- input connections active only while flying

    local function clearFlyInput()
        for _, c in ipairs(flyConns) do pcall(function() c:Disconnect() end) end
        table.clear(flyConns)
        flyUp, flyDown = 0, 0
    end

    local function bindFlyInput()
        clearFlyInput()
        -- PC: Space = up, LeftControl = down (Shift avoided → no shiftlock clash).
        for _, ev in ipairs({ "InputBegan", "InputEnded" }) do
            flyConns[#flyConns + 1] = UserInputService[ev]:Connect(function(input, gpe)
                if gpe then return end
                local began = (ev == "InputBegan")
                if input.KeyCode == Enum.KeyCode.Space then
                    flyUp = began and 1 or 0
                elseif input.KeyCode == Enum.KeyCode.LeftControl then
                    flyDown = began and -1 or 0
                end
            end)
        end
        -- Mobile: watch the touch jump button (ImageRectOffset.X == 146 while held).
        if UserInputService.TouchEnabled then
            pcall(function()
                local jb = LocalPlayer:WaitForChild("PlayerGui", 5)
                    :WaitForChild("TouchGui"):WaitForChild("TouchControlFrame"):WaitForChild("JumpButton")
                flyConns[#flyConns + 1] = jb:GetPropertyChangedSignal("ImageRectOffset"):Connect(function()
                    flyUp = (jb.ImageRectOffset.X == 146) and 1 or 0
                end)
            end)
        end
    end

    local flyActive = false
    local function stopFlyPhysics()
        local _, hum = getParts()
        if hum then pcall(function() hum.PlatformStand = false end) end
        flyActive = false
    end

    local function stepFly(dt)
        if not Config.Fly_On then
            if flyActive then stopFlyPhysics(); clearFlyInput() end
            return
        end
        local _, hum, root = getParts()
        if not hum then return end
        if not flyActive then flyActive = true; bindFlyInput() end

        -- Face-camera: PlatformStand + look along camera (also gives 3D via pitch).
        if Config.Fly_Face then
            hum.PlatformStand = true
            root.RotVelocity = Vector3.zero
            local cam = Workspace.CurrentCamera
            if cam then
                root.CFrame = CFrame.lookAlong(root.Position, cam.CFrame.LookVector)
            end
        end

        local moveDir = hum.MoveDirection
        local dir = Config.Fly_Face and cameraRelative(moveDir) or moveDir
        local horizontal = dir * Config.Fly_Value
        local vertical   = Vector3.new(0, (flyUp + flyDown) * Config.Fly_Vertical, 0)

        if Config.Fly_Mode == "Velocity" then
            root.AssemblyLinearVelocity = horizontal + vertical
        else -- CFrame (no rubberbanding — velocity zeroed each frame)
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = root.CFrame + ((horizontal + vertical) * dt)
        end
    end

    -- ══════════════════════════ NO SLOWDOWN ═════════════════════════════════
    -- Runs on Heartbeat (after the game's combat WalkSpeed writes) so our value
    -- is the final one for the frame. Per-type gating via character attributes.
    local function sprintingWanted()
        return Config.Sprint_On
    end
    local function stepNoSlow()
        if not Config.NS_On then return end
        local c, hum = getParts(); if not hum then return end
        local base = Config.NS_Force > 0 and math.clamp(Config.NS_Force, 1, SPEED_CAP)
                     or (sprintingWanted() and SPRINT_WALK or BASE_WALK)
        local stunned  = c:GetAttribute("Stunned")  == true
        local blocking = c:GetAttribute("Blocking") == true

        local override
        if stunned then
            override = Config.NS_Stun
        elseif blocking then
            override = Config.NS_Block
        else
            -- attack windups / root-locks write WalkSpeed near 0 with no attribute
            override = Config.NS_Attack and (hum.WalkSpeed < base - 0.1)
        end
        if override and math.abs(hum.WalkSpeed - base) > 0.05 then
            hum.WalkSpeed = base
        end
    end

    -- ═══════════════════ HOOK-BASED FEATURES (installed lazily) ══════════════
    -- Finds a game function by its decompiled debug name via filtergc.
    local function findFn(name, upvals)
        if not _filtergc then return nil end
        local opts = { Name = name, IgnoreExecutor = true }
        if upvals then opts.Upvalues = upvals end
        local ok, res = pcall(_filtergc, "function", opts, false)
        if ok and res then
            if type(res) == "table" then return res[1] else return res end
        end
        return nil
    end

    local notifyFn  -- set inside buildUI so hooks can report status

    -- ---- No Combo Wait: hook CombatPingAnimUtils.GetPingAnimSpeedMultiplier ----
    local ncwHooked = false
    local function installNCW()
        if ncwHooked then return true end
        if not _hasHookFn then return false end
        local fn = findFn("GetPingAnimSpeedMultiplier")
        if not fn then return false end
        local orig
        orig = _hookfunction(fn, function(len, plr)
            local base = orig(len, plr)
            if Config.NCW_On and type(base) == "number" then
                return base * Config.NCW_Mult
            end
            return base
        end)
        ncwHooked = true
        return true
    end

    -- ---- No Stun: hook StateHandler.SetStun ----
    local noStunHooked = false
    local function installNoStun()
        if noStunHooked then return true end
        if not _hasHookFn then return false end
        local fn = findFn("SetStun")
        if not fn then return false end
        local orig
        orig = _hookfunction(fn, function(char, apply, dur, spd)
            if Config.NoStun_On and apply == true and char == LocalPlayer.Character then
                return -- skip applying the stun to us
            end
            return orig(char, apply, dur, spd)
        end)
        noStunHooked = true
        return true
    end

    -- ---- Ping Spoof: hook __namecall for GetNetworkPing ----
    local pingHooked = false
    local function installPing()
        if pingHooked then return true end
        if not _hasHookMeta then return false end
        local ncOld
        ncOld = _hookmeta(game, "__namecall", function(self, ...)
            if Config.Ping_On and not _checkcaller() then
                if _namecall() == "GetNetworkPing" then
                    return Config.Ping_Value / 1000  -- GetNetworkPing returns seconds
                end
            end
            return ncOld(self, ...)
        end)
        pingHooked = true
        return true
    end

    -- ══════════════════════════ AUTO SPRINT ═════════════════════════════════
    local sprintSingleton
    local function getSprint()
        if sprintSingleton then return sprintSingleton end
        if not _filtergc then return nil end
        local ok, res = pcall(_filtergc, "table", { Keys = { "_sprintInputDesired" } }, false)
        if ok and type(res) == "table" then
            for _, t in ipairs(res) do
                if type(t) == "table" and rawget(t, "_sprintInputDesired") ~= nil then
                    sprintSingleton = t
                    return t
                end
            end
        end
        return nil
    end
    local function setSprint(on)
        local s = getSprint(); if not s then return false end
        if on then
            pcall(function() s:SetSprintInputDesired(true) end)
            pcall(function() s:StartSprint() end)
        else
            pcall(function() s:SetSprintInputDesired(false) end)
            pcall(function() s:StopSprint(false) end)
        end
        return true
    end

    -- ═════════════════════════ MASTER LOOPS ═════════════════════════════════
    PreStep:Connect(function(dt)
        dt = (typeof(dt) == "number" and dt > 0) and dt or (1 / 60)
        pcall(stepSpeed, dt)
        pcall(stepFly, dt)
    end)
    PostStep:Connect(function()
        pcall(stepNoSlow)
        -- keep sprint desired asserted (game clears it after combat cancels)
        if Config.Sprint_On then
            local s = getSprint()
            if s and rawget(s, "_sprintInputDesired") ~= true then
                pcall(function() s:SetSprintInputDesired(true) end)
            end
        end
    end)

    -- Reset transient state on respawn.
    LocalPlayer.CharacterAdded:Connect(function()
        flyActive = false
        clearFlyInput()
        task.wait(0.5)
        if Config.Sprint_On then setSprint(true) end
    end)

    -- ═══════════════════════════════ UI ═════════════════════════════════════
    local M = {}

    function M.start()
        Config.Speed_On, Config.Fly_On = false, false
        Config.NS_On, Config.NCW_On, Config.NoStun_On, Config.Ping_On = false, false, false, false
        Config.Sprint_On = false
    end

    function M.buildUI(ctx)
        local uiReady = false
        local function notify(title, body)
            if uiReady then pcall(ctx.notify, title, body) end
        end
        notifyFn = notify

        -- notify-exactly-once boolean feature (Header + "Enabled" toggle + Keybind)
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

        local MV = ctx.tabs.Movement

        -- ─────────────── Section 1: Speed (Left) ───────────────
        local sSpeed = MV:Section({ Side = "Left" })
        sSpeed:Header({ Name = "Speed" })
        feature(sSpeed, {
            Title = "Speed", Flag = "MV_Speed",
            get = function() return Config.Speed_On end,
            set = function(v) Config.Speed_On = v end,
            Desc = "cframe/velocity speedhack\ndriven by your move input (PC + mobile)",
        })
        sSpeed:Dropdown({
            Name = "Method", Options = { "CFrame", "Velocity" },
            Default = Config.Speed_Mode,
            Callback = function(v) Config.Speed_Mode = v; notify("Speed Method", v) end,
        }, ctx.flag("MV_SpeedMode"))
        sSpeed:SubLabel({ Text = "CFrame - positional, bypasses the WalkSpeed anti-cheat\nVelocity - smooth physics, keeps gravity" })
        slider(sSpeed, { Name = "Speed", Flag = "MV_SpeedVal", Default = Config.Speed_Value,
            Min = 16, Max = 150, Suffix = " studs", Callback = function(v) Config.Speed_Value = v end })

        -- ─────────────── Section 2: Fly (Left) ───────────────
        local sFly = MV:Section({ Side = "Left" })
        sFly:Header({ Name = "Fly" })
        feature(sFly, {
            Title = "Fly", Flag = "MV_Fly",
            get = function() return Config.Fly_On end,
            set = function(v) Config.Fly_On = v end,
            Desc = "space = up, left ctrl = down (no shiftlock clash)\nmobile: jump button = up, camera + stick = full 3D",
        })
        sFly:Dropdown({
            Name = "Method", Options = { "CFrame", "Velocity" },
            Default = Config.Fly_Mode,
            Callback = function(v) Config.Fly_Mode = v; notify("Fly Method", v) end,
        }, ctx.flag("MV_FlyMode"))
        boolToggle(sFly, "Face Camera", "Fly Face Camera",
            function() return Config.Fly_Face end, function(v) Config.Fly_Face = v end)
        sFly:SubLabel({ Text = "Face Camera - body follows the camera; aim + move stick to climb/dive" })
        slider(sFly, { Name = "Horizontal Speed", Flag = "MV_FlyVal", Default = Config.Fly_Value,
            Min = 10, Max = 250, Suffix = " studs", Callback = function(v) Config.Fly_Value = v end })
        slider(sFly, { Name = "Vertical Speed", Flag = "MV_FlyVert", Default = Config.Fly_Vertical,
            Min = 10, Max = 250, Suffix = " studs", Callback = function(v) Config.Fly_Vertical = v end })

        -- ─────────────── Section 3: No Slowdown (Right) ───────────────
        local sNS = MV:Section({ Side = "Right" })
        sNS:Header({ Name = "No Slowdown" })
        feature(sNS, {
            Title = "No Slowdown", Flag = "MV_NS",
            get = function() return Config.NS_On end,
            set = function(v) Config.NS_On = v end,
            Desc = "removes combat move-speed penalties\ntoggle which sources below",
        })
        boolToggle(sNS, "Attack", "NoSlow Attack",
            function() return Config.NS_Attack end, function(v) Config.NS_Attack = v end)
        boolToggle(sNS, "Block", "NoSlow Block",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        boolToggle(sNS, "Stun / Parry", "NoSlow Stun",
            function() return Config.NS_Stun end, function(v) Config.NS_Stun = v end)
        sNS:SubLabel({ Text = "Stun/Parry is risky - dropping to 4 studs is server-driven; use No Stun for a cleaner immunity" })
        slider(sNS, { Name = "Force Speed (0 = base)", Flag = "MV_NSForce", Default = Config.NS_Force,
            Min = 0, Max = SPEED_CAP, Suffix = " studs", Callback = function(v) Config.NS_Force = v end })
        sNS:SubLabel({ Text = "0 keeps the game's base (12 walk / 25 sprint). Above ~26 the move anti-cheat flags you." })

        -- ─────────────── Section 4: Combat exploits (Right) ───────────────
        local sCbt = MV:Section({ Side = "Right" })
        sCbt:Header({ Name = "No Combo Wait" })
        feature(sCbt, {
            Title = "No Combo Wait", Flag = "MV_NCW",
            get = function() return Config.NCW_On end,
            set = function(v)
                Config.NCW_On = v
                if v and not installNCW() then
                    notify("No Combo Wait", "failed - need filtergc + hookfunction")
                    Config.NCW_On = false
                end
            end,
            Desc = "speeds the M1 swing anim so the pause before\nthe next hit / new combo is gone",
        })
        slider(sCbt, { Name = "Attack Speed", Flag = "MV_NCWMult", Default = math.floor(Config.NCW_Mult * 100),
            Min = 110, Max = 500, Suffix = "%", Callback = function(v) Config.NCW_Mult = v / 100 end })
        sCbt:SubLabel({ Text = "higher = shorter wait. server 'M1Cooldown' still caps real hits,\nso extreme values just waste swings (2-2.5x is the sweet spot)" })

        sCbt:Divider()
        sCbt:Header({ Name = "No Stun" })
        feature(sCbt, {
            Title = "No Stun", Flag = "MV_NoStun",
            get = function() return Config.NoStun_On end,
            set = function(v)
                Config.NoStun_On = v
                if v and not installNoStun() then
                    notify("No Stun", "failed - need filtergc + hookfunction")
                    Config.NoStun_On = false
                end
            end,
            Desc = "blocks StateHandler.SetStun on you → parry/hit\nstun never locks your movement",
        })

        sCbt:Divider()
        sCbt:Header({ Name = "Ping Spoof" })
        feature(sCbt, {
            Title = "Ping Spoof", Flag = "MV_Ping",
            get = function() return Config.Ping_On end,
            set = function(v)
                Config.Ping_On = v
                if v and not installPing() then
                    notify("Ping Spoof", "failed - need hookmetamethod")
                    Config.Ping_On = false
                end
            end,
            Desc = "spoofs GetNetworkPing (client-side). low ping =\nno anim slowdown from ping compensation",
        })
        slider(sCbt, { Name = "Spoofed Ping", Flag = "MV_PingVal", Default = Config.Ping_Value,
            Min = 0, Max = 1000, Suffix = " ms", Callback = function(v) Config.Ping_Value = v end })

        -- ─────────────── Section 5: Sprint (Right) ───────────────
        local sSpr = MV:Section({ Side = "Right" })
        sSpr:Header({ Name = "Sprint" })
        feature(sSpr, {
            Title = "Auto Sprint", Flag = "MV_Sprint",
            get = function() return Config.Sprint_On end,
            set = function(v)
                Config.Sprint_On = v
                if not setSprint(v) and v then
                    notify("Auto Sprint", "sprint controller not found yet")
                end
            end,
            Desc = "holds sprint on (25 studs). needs HP ≥ 10.\nturning off truly stops sprinting",
        })

        uiReady = true
    end

    return M
end
