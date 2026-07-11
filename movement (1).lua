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
--    • NoComboWait — THE real fix (previous anim-speed approach was wrong). In
--      CombatSystemClient.Combat.Base.M1, scheduleM1SwingTimers(combo, animSpeed):
--        u21 = false
--        u22 = task.delay((combo==4 and 1.25 or 0.45)/animSpeed, ()->u21=true) -- chain gate
--        u20 = task.delay(ComboResetTime/animSpeed, resetCombo)                -- INDEPENDENT of combo
--      Speeding animSpeed shrinks the RESET window too → the chain drops and prints
--      "combo reset" (the symptom you saw). Instead we HOOK scheduleM1SwingTimers
--      and lie about `combo`: pass 1 when it is 4, so the 1.25s finisher cooldown
--      collapses to the normal 0.45s cadence while the reset timer stays intact.
--      Nothing here is server-visible; the server M1 rate still caps real hits.
--
--    • No Stun — hookfunction on StateHandler.SetStun(char, apply, dur, speed),
--      found via filtergc {Name="SetStun"}. When it tries to APPLY a stun to us we
--      never call the original, so it never writes our WalkSpeed/GroundSpeed down.
--
--    • Ping Spoof — we deceive the script instead of writing a value: hook
--      __namecall on "GetNetworkPing" (newcclosure-wrapped) and return the spoofed
--      seconds. CombatPingAnimUtils.GetPingAnimSpeedMultiplier returns 1 (no
--      slowdown) when ping<=0, so a 0ms spoof kills the ping anim penalty at source.
--
--    • AutoSprint — MovementServiceClient singleton (has _sprintInputDesired).
--      ON  → SetSprintInputDesired(true) + StartSprint(); the game auto-resumes.
--      OFF → SetSprintInputDesired(false) + StopSprint() → truly stops.
--      Bypass Restrictions → hookfunction on the sprint gate predicates
--      (_isLocked, _isLocomotionSuppressed, _isSprintBlockedByItem,
--      ShouldApplyCombatBackpedal) so they report "clear" → sprint through combat
--      locks / weapons / backpedal, without touching any server-read value.
--      Sprint speed = 25, base walk = 12, needs HP ≥ 10.
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

        -- No Slowdown (master + per-type) — all via the IsLocked hook, no writes
        NS_On     = false,
        NS_Attack = true,         -- M1/M2/windup movement lock
        NS_Block  = true,         -- Blocking / GuardBroken
        NS_GetHit = true,         -- CantAnything (movement lock from taking a hit)

        -- No Combo Wait (hook scheduleM1SwingTimers → drop the finisher pause)
        NCW_On   = false,

        -- No Stun (stun immunity) — same IsLocked hook, Stunned category
        NoStun_On = false,

        -- Ping Spoof
        Ping_On    = false,
        Ping_Value = 0,           -- spoofed ping in ms

        -- Sprint
        Sprint_On     = false,    -- AutoSprint (hold sprint on)
        Sprint_Bypass = false,    -- bypass the game's sprint restrictions
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

    -- ═══════════════════ HOOK-BASED FEATURES (installed lazily) ══════════════
    -- filtergc by CONSTANTS (string literals baked into the proto) — reliable even
    -- when the production bytecode ships with stripped function debug-names, which
    -- is exactly why the old {Name=...} lookups silently returned nil (→ "nothing
    -- worked"). Constants survive optimisation, so this is the stable fingerprint.
    local function findFn(constants, upvals)
        if not _filtergc then return nil end
        local opts = { IgnoreExecutor = true }
        if constants then opts.Constants = constants end
        if upvals   then opts.Upvalues  = upvals   end
        local ok, res = pcall(_filtergc, "function", opts, true)  -- filterOne = true
        if ok and type(res) == "function" then return res end
        local ok2, res2 = pcall(_filtergc, "function", opts, false)
        if ok2 and type(res2) == "table" and type(res2[1]) == "function" then
            return res2[1]
        end
        return nil
    end

    local notifyFn  -- set inside buildUI so hooks can report status

    -- ---- Combat lock categories (what MovementServiceUtils.IsLocked checks) ----
    local ATTACK_ATTRS = { "M1", "M2", "M1Hold", "PendingM1", "PendingM2", "CombatAttacking" }
    local BLOCK_ATTRS  = { "Blocking", "GuardBroken" }
    local STUN_ATTRS   = { "Stunned" }
    local GETHIT_ATTRS = { "CantAnything" }  -- movement lock applied when you take a hit
    local function anyAttr(char, list)
        for _, a in ipairs(list) do
            if char:GetAttribute(a) == true then return true end
        end
        return false
    end

    -- ---- No Slowdown / No Stun / Get-Hit: hook MovementServiceUtils.IsLocked ----
    -- ROOT CAUSE (previous versions): SetStun is never called client-side, and the
    -- WalkSpeed write-fight was fragile. The real client gate is IsLocked(char):
    -- MovementServiceClient._isLocked (line 412) returns
    --   tick() < _combatSprintLockUntil OR MovementServiceUtils.IsLocked(char)
    -- and IsLocked reads Stunned / Blocking / M1 / M2 / CantAnything… to decide
    -- whether to kill your movement (and sprint). We hook IsLocked and, for OUR
    -- character, return false when the ONLY active lock reasons are categories the
    -- user chose to bypass. We never call the original for a real hard-lock
    -- (Ragdoll/Dead/Downed/Screening/Carry), and we write NOTHING — we only lie
    -- about the predicate result, so no attribute/property is touched.
    -- Found by its unique string constants "Screening" + "BeingCarried".
    local isLockedHooked = false
    local function installIsLockedHook()
        if isLockedHooked then return true end
        if not _hasHookFn then return false end
        local fn = findFn({ "Screening", "BeingCarried", "Stunned" })
        if not fn then return false end
        local orig
        orig = _hookfunction(fn, function(char)
            local res = orig(char)
            if res ~= true or char ~= LocalPlayer.Character then return res end
            if not (Config.NS_On or Config.NoStun_On or Config.Sprint_Bypass) then return res end

            -- hard locks: never bypass these
            if char:GetAttribute("Ragdoll") == true or char:GetAttribute("Dead") == true
               or char:GetAttribute("Downed") == true or char:GetAttribute("Screening") == true then
                return res
            end
            local States = char:FindFirstChild("States")
            if States then
                local bc = States:FindFirstChild("BeingCarried")
                local bg = States:FindFirstChild("BeingGripped")
                if (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil) then return res end
            end

            -- which categories are we allowed to bypass right now?
            local byAttack = Config.Sprint_Bypass or (Config.NS_On and Config.NS_Attack)
            local byBlock  = Config.Sprint_Bypass or (Config.NS_On and Config.NS_Block)
            local byGetHit = Config.Sprint_Bypass or (Config.NS_On and Config.NS_GetHit)
            local byStun   = Config.Sprint_Bypass or Config.NoStun_On

            -- stay locked if ANY active reason is one we are NOT allowed to bypass
            local stillLocked = false
            if anyAttr(char, ATTACK_ATTRS) and not byAttack then stillLocked = true end
            if anyAttr(char, BLOCK_ATTRS)  and not byBlock  then stillLocked = true end
            if anyAttr(char, GETHIT_ATTRS) and not byGetHit then stillLocked = true end
            if anyAttr(char, STUN_ATTRS)   and not byStun   then stillLocked = true end
            return stillLocked
        end)
        isLockedHooked = true
        return true
    end

    -- ---- No Combo Wait: hook M1's scheduleM1SwingTimers(combo, animSpeed) ----
    -- The chain pause is task.delay((combo==4 and FinisherCooldown or AttackDuration)
    -- /animSpeed) before it re-opens the u21 gate; the combo-RESET timer is
    -- ComboResetTime/animSpeed, scheduled in the SAME function but INDEPENDENT of
    -- combo. Speeding animSpeed shrinks the reset window → the chain drops and
    -- prints "combo reset" (the bug you saw). So we DON'T touch anim speed — we lie
    -- about the combo index: pass 1 instead of 4 so the finisher cooldown collapses
    -- to the normal inter-hit cadence while the reset timer stays intact. Nothing
    -- here is server-visible. Found by its unique task-name constants.
    local ncwHooked = false
    local function installNCW()
        if ncwHooked then return true end
        if not _hasHookFn then return false end
        local fn = findFn({ "M1AttackCooldownTask", "M1ComboResetTask" })
        if not fn then return false end
        local orig
        orig = _hookfunction(fn, function(combo, animSpeed)
            if Config.NCW_On and combo == 4 then
                return orig(1, animSpeed)  -- treat the finisher as a normal swing
            end
            return orig(combo, animSpeed)
        end)
        ncwHooked = true
        return true
    end

    -- ---- Ping Spoof: hook __namecall for GetNetworkPing ----
    -- We don't write any value — we make the game's OWN ping reads return what we
    -- want. CombatPingAnimUtils.GetPingAnimSpeedMultiplier does `plr:GetNetworkPing()`
    -- (a namecall) and returns 1 (no slowdown) when the result is <= 0, so a 0 ms
    -- spoof kills the ping-based anim slowdown at the source. Plain hookmetamethod
    -- per the executor API (no extra newcclosure wrapper — that was breaking it);
    -- executor-origin calls pass through via checkcaller.
    local pingHooked = false
    local function installPing()
        if pingHooked then return true end
        if not _hasHookMeta then return false end
        local ncOld
        ncOld = _hookmeta(game, "__namecall", function(self, ...)
            if Config.Ping_On and not _checkcaller() and _namecall() == "GetNetworkPing" then
                return Config.Ping_Value / 1000  -- GetNetworkPing() is in seconds
            end
            return ncOld(self, ...)
        end)
        pingHooked = true
        return true
    end

    -- Any of NoSlowdown / NoStun / GetHit / Sprint-Bypass need the IsLocked hook.
    local function ensureCombatHook(label)
        if installIsLockedHook() then return true end
        if notifyFn then notifyFn(label, "failed - need filtergc + hookfunction") end
        return false
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
            -- StopSprint(self, playCooldown, fromCancel); no extra args = clean stop
            pcall(function() s:StopSprint() end)
        end
        return true
    end

    -- ---- Bypass Restrictions ----
    -- MovementServiceClient._isLocked (line 412) = tick() < _combatSprintLockUntil
    -- OR MovementServiceUtils.IsLocked(char). The dominant reason sprint is denied
    -- is IsLocked returning true during combat states, so our IsLocked hook (above)
    -- already clears those when Sprint_Bypass is on — no separate, name-based hook
    -- needed (those debug-names are stripped, which is why the old one never took).

    -- ═════════════════════════ MASTER LOOPS ═════════════════════════════════
    PreStep:Connect(function(dt)
        dt = (typeof(dt) == "number" and dt > 0) and dt or (1 / 60)
        pcall(stepSpeed, dt)
        pcall(stepFly, dt)
    end)
    PostStep:Connect(function()
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
        Config.Sprint_On, Config.Sprint_Bypass = false, false
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
            set = function(v)
                Config.NS_On = v
                if v and not ensureCombatHook("No Slowdown") then Config.NS_On = false end
            end,
            Desc = "neutralises MovementServiceUtils.IsLocked for you\nso combat states stop killing your movement",
        })
        boolToggle(sNS, "Attack", "NoSlow Attack",
            function() return Config.NS_Attack end, function(v) Config.NS_Attack = v end)
        boolToggle(sNS, "Block", "NoSlow Block",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        boolToggle(sNS, "Get Hit", "NoSlow GetHit",
            function() return Config.NS_GetHit end, function(v) Config.NS_GetHit = v end)
        sNS:SubLabel({ Text = "Attack = M1/M2 windup locks · Block = blocking/guard-broken\nGet Hit = the movement lock applied when you take damage (CantAnything).\nHard locks (ragdoll/carry/downed/screening) are never bypassed." })

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
            Desc = "removes the finisher pause after the 4th hit so\na new combo starts with no extra delay",
        })
        sCbt:SubLabel({ Text = "hooks scheduleM1SwingTimers and makes the 4th swing use the normal\n0.45s cadence instead of the 1.25s finisher cooldown. The combo-reset\ntimer is left intact, so the chain no longer prints 'combo reset'." })

        sCbt:Divider()
        sCbt:Header({ Name = "No Stun" })
        feature(sCbt, {
            Title = "No Stun", Flag = "MV_NoStun",
            get = function() return Config.NoStun_On end,
            set = function(v)
                Config.NoStun_On = v
                if v and not ensureCombatHook("No Stun") then Config.NoStun_On = false end
            end,
            Desc = "clears the 'Stunned' lock in IsLocked for you →\nparry/stun no longer freezes your movement",
        })
        sCbt:SubLabel({ Text = "SetStun is never called client-side, so this hooks the real client\ngate (IsLocked) that reads the Stunned attribute for speed - deception only, no writes." })

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

        -- ─────────────── Section 5: Sprint (Right) ───��───────────
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
        boolToggle(sSpr, "Bypass Restrictions", "Sprint Bypass",
            function() return Config.Sprint_Bypass end,
            function(v)
                Config.Sprint_Bypass = v
                if v and not ensureCombatHook("Sprint Bypass") then Config.Sprint_Bypass = false end
            end)
        sSpr:SubLabel({ Text = "sprint through combat locks by clearing IsLocked for you (same hook\nas No Slowdown). the game's _combatSprintLockUntil timer still applies briefly." })

        uiReady = true
    end

    return M
end
