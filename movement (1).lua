-- ═══════════════════════════════════════════════════════════════════════════
--  Movement — standalone module for the Syllinse loader (AutoParry game,
--  UniverseId 9199655655 — the "so you're challenging me" combat game).
--
--  Loader contract (see the loader's §11 / §13):
--    • The file body returns `function(Lib, Core)` → called with (Lib, Core).
--    • That returns a handle table with optional `start()` and `buildUI(ctx)`.
--    • start() runs first (for every module), buildUI(ctx) builds the tab UI.
--    • ctx gives us: tabs (keyed by Tab.Key), flag(name), keybind(section,opts),
--      notify(title,desc). We build everything into ctx.tabs.Movement.
--
--  Everything here is derived from the game's OWN decompiled client code:
--    • WALK_SPEED = 12                         (MovementServiceUtils)
--    • M2 windup / Capoeira root-lock set WalkSpeed = 0 each Heartbeat
--      (CombatSystemClient.Combat.Base.M2)     → "Attack" slowdown
--    • Blocking lowers speed (CombatBackwardWalkSpeed) → "Block" slowdown
--    • StateHandler.SetStun / ParryStunSpeed{M1=4,M2=4} → "Stun/Parry" slowdown
--    • M1 combo gate: scheduleM1SwingTimers sets the local `canAttack` flag
--      false, then task.delay((combo==4 and FinisherCooldown(1.25)
--      or AttackDuration(0.45)) / animSpeed) flips it back → the "combo wait".
--      ComboResetTime = 1.55. All three are ClientPredict.M1 values.
--    • Sprint: SPRINT_COOLDOWN=0.5, MIN_SPRINT_HEALTH=10, and sprint is cancelled
--      by SPRINT_LOCK_CANCEL_ATTRIBUTES {Blocking,M1,M2,...,Stunned,...}.
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    local Players           = game:GetService("Players")
    local RunService        = game:GetService("RunService")
    local UserInputService  = game:GetService("UserInputService")
    local Workspace         = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer

    -- Executor globals (guarded — this module must not hard-crash on a weak exec).
    local _getgc        = (getgc or (getgenv and getgenv().getgc))
    local _iscclosure   = iscclosure
    local _hasDebug     = (debug and debug.getupvalues and debug.setupvalue) and true or false

    -- ── Runtime state (defaults; the config manager restores flags via MacLib) ──
    local Config = {
        -- CFrame speedhack
        Speed_On        = false,
        Speed_Value     = 45,      -- studs/sec added ON TOP of normal movement

        -- Fly
        Fly_On          = false,
        Fly_Value       = 60,      -- studs/sec

        -- WalkSpeed override (0 = leave the game's value alone)
        WS_On           = false,
        WS_Value        = 24,

        -- No Slowdown (master + per-type)
        NS_On           = false,
        NS_Attack       = true,    -- M2 windup / root-locks that pin WalkSpeed to 0
        NS_Block        = true,    -- movement penalty while Blocking
        NS_Stun         = false,   -- Stunned / ParryStun / GuardBroken (BLATANT — server may fight it)
        NS_Force        = 0,       -- 0 = restore to game base (BaseWalkSpeed or 12)

        -- No Combo Wait
        NCW_On          = false,
        NCW_Keep        = 8,       -- % of the original gate to keep (8% ≈ near-instant, safer than 0)

        -- Sprint / jump extras
        Sprint_Always   = false,
        Sprint_NoCd     = false,
        InfJump         = false,
        JumpPower_On    = false,
        JumpPower_Value = 50,
    }

    -- ── Small character helpers ─────────────────────────────────────────────
    local function getChar()   return LocalPlayer.Character end
    local function getHum()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid") or nil
    end
    local function getHRP()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart") or nil
    end
    -- The game uses a Humanoid.ControllerManager on some rigs; GroundSpeed there
    -- overrides Humanoid.WalkSpeed, so we always write BOTH.
    local function getCM(hum)
        return hum and hum:FindFirstChildOfClass("ControllerManager") or nil
    end
    local function gameBaseSpeed()
        local c = getChar()
        local b = c and c:GetAttribute("BaseWalkSpeed")
        return (type(b) == "number" and b > 0) and b or 12   -- MovementServiceUtils.WALK_SPEED
    end
    local function setSpeed(hum, v)
        if not hum then return end
        hum.WalkSpeed = v
        local cm = getCM(hum)
        if cm then cm.GroundSpeed = v end
    end

    -- Attribute groups (straight from the decompiled combat client).
    local ATTACK_ATTRS = { "CombatAttacking", "M1", "M2", "M1Hold", "PendingM1", "PendingM2", "CantAnything" }
    local STUN_ATTRS   = { "Stunned", "ParryStun", "GuardBroken" }
    local function anyAttr(c, list)
        for _, a in ipairs(list) do
            if c:GetAttribute(a) == true then return true end
        end
        return false
    end

    -- ═══════════════════════════════════════════════════════════════════════
    --  CFrame Speedhack  — add camera-relative movement each frame ON TOP of the
    --  Humanoid so it stacks over whatever WalkSpeed the game allows. MoveDirection
    --  is populated by BOTH keyboard AND the mobile thumbstick, so this works on
    --  phones with zero extra buttons.
    -- ═══════════════════════════════════════════════════════════════════════
    RunService.Heartbeat:Connect(function(dt)
        if not Config.Speed_On or Config.Fly_On then return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) then return end
        if hum.Health <= 0 or hum.Sit then return end
        local dir = hum.MoveDirection
        if dir.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + (dir * Config.Speed_Value * dt)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  Fly  — BodyVelocity + PlatformStand. Horizontal direction follows
    --  Humanoid.MoveDirection (camera-relative, PC + mobile). Vertical: PC uses
    --  Space (up) / LeftShift (down); mobile taps the Jump button for a short
    --  ascend pulse. The BodyVelocity is created on enable and cleaned on disable
    --  or death, and re-created after a respawn while Fly stays on.
    -- ═══════════════════════════════════════════════════════════════════════
    local flyBV
    local ascendPulseUntil = 0
    UserInputService.JumpRequest:Connect(function()
        if Config.Fly_On then ascendPulseUntil = os.clock() + 0.25 end   -- mobile ascend
    end)
    local function destroyFly()
        if flyBV then flyBV:Destroy(); flyBV = nil end
        local hum = getHum()
        if hum then hum.PlatformStand = false end
    end
    local function ensureFly()
        local hrp = getHRP()
        if not hrp then return end
        if flyBV and flyBV.Parent == hrp then return end
        if flyBV then flyBV:Destroy() end
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        flyBV.P = 1e4
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = hrp
    end
    RunService.RenderStepped:Connect(function()
        if not Config.Fly_On then
            if flyBV then destroyFly() end
            return
        end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 then
            if flyBV then destroyFly() end
            return
        end
        hum.PlatformStand = true
        ensureFly()
        local cam = Workspace.CurrentCamera
        local move = hum.MoveDirection                 -- world-space, camera-relative
        local dir = Vector3.new(move.X, 0, move.Z)
        if cam then
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or os.clock() < ascendPulseUntil then
                dir += Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
               or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                dir -= Vector3.new(0, 1, 0)
            end
        end
        if flyBV then
            flyBV.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * Config.Fly_Value
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  No Slowdown (per-type) + WalkSpeed override.
    --  We write on RunService.Stepped (start of frame, BEFORE the physics step),
    --  so our value wins over the WalkSpeed=0 the combat client writes on the
    --  PREVIOUS Heartbeat (after physics). That's what makes the un-slow stick.
    -- ═══════════════════════════════════════════════════════════════════════
    RunService.Stepped:Connect(function()
        local c, hum = getChar(), getHum()
        if not (c and hum) or hum.Health <= 0 then return end

        -- No-Slowdown wins first: pick the restore target.
        if Config.NS_On then
            local slowed = false
            if Config.NS_Attack and anyAttr(c, ATTACK_ATTRS) then slowed = true end
            if Config.NS_Block  and c:GetAttribute("Blocking") == true then slowed = true end
            if Config.NS_Stun   and anyAttr(c, STUN_ATTRS) then slowed = true end
            if slowed then
                local target = (Config.NS_Force > 0) and Config.NS_Force
                    or (Config.WS_On and Config.WS_Value or gameBaseSpeed())
                setSpeed(hum, target)
                return
            end
        end

        -- Plain WalkSpeed override when not currently un-slowing.
        if Config.WS_On then
            if math.abs(hum.WalkSpeed - Config.WS_Value) > 0.05 then
                setSpeed(hum, Config.WS_Value)
            end
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  Sprint tweaks + Infinite Jump + JumpPower.
    --  Sprint is client-cancelled by combat attributes; "Always Sprint" simply
    --  re-asserts the sprint speed, "No Sprint Cooldown" clears the cooldown
    --  attribute the movement client stamps on the character.
    -- ═══════════════════════════════════════════════════════════════════════
    RunService.Heartbeat:Connect(function()
        local c, hum = getChar(), getHum()
        if not (c and hum) or hum.Health <= 0 then return end
        if Config.Sprint_NoCd then
            -- The movement client gates re-sprint behind these; clearing them locally
            -- lets you sprint again immediately.
            if c:GetAttribute("SprintCooldown") ~= nil then c:SetAttribute("SprintCooldown", nil) end
            if c:GetAttribute("SprintCd")       ~= nil then c:SetAttribute("SprintCd", nil) end
        end
        if Config.JumpPower_On then
            if hum.UseJumpPower ~= nil then hum.UseJumpPower = true end
            hum.JumpPower = Config.JumpPower_Value
        end
    end)
    UserInputService.JumpRequest:Connect(function()
        if not Config.InfJump then return end
        local hum = getHum()
        if hum and hum.Health > 0 then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  No Combo Wait — shrink the client-side M1 combo gate.
    --  scheduleM1SwingTimers (CombatSystemClient.Combat.Base.M1) captures the
    --  numeric upvalues FinisherCooldown(1.25), AttackDuration(0.45) and
    --  ComboResetTime(1.55). That triple uniquely identifies the closure among
    --  everything in getgc. We patch FinisherCooldown/AttackDuration to a small
    --  fraction (keep%) so the delay that re-arms the "can attack" flag is
    --  near-instant. ComboResetTime is left alone (shrinking it would drop your
    --  combo faster, which we do NOT want).
    -- ═══════════════════════════════════════════════════════════════════════
    local FIN, ATK, CMB = 1.25, 0.45, 1.55
    local comboPatched = false
    local function patchComboWait(keepFraction)
        if not (_getgc and _hasDebug) then
            return false, "executor lacks getgc/debug"
        end
        local patched = 0
        for _, fn in pairs(_getgc(true)) do
            if type(fn) == "function" and not (_iscclosure and _iscclosure(fn)) then
                local ok, ups = pcall(debug.getupvalues, fn)
                if ok and type(ups) == "table" then
                    local iFin, iAtk, iCmb
                    for i, v in pairs(ups) do
                        if v == FIN then iFin = i
                        elseif v == ATK then iAtk = i
                        elseif v == CMB then iCmb = i end
                    end
                    -- Require all three → this is scheduleM1SwingTimers, nothing else.
                    if iFin and iAtk and iCmb then
                        pcall(debug.setupvalue, fn, iFin, FIN * keepFraction)
                        pcall(debug.setupvalue, fn, iAtk, ATK * keepFraction)
                        patched += 1
                    end
                end
            end
        end
        return patched > 0, patched
    end

    -- Keep it applied: the module may load before the combat closures exist, and
    -- a respawn can rebuild them. Re-apply on a light loop while the toggle is on.
    task.spawn(function()
        while true do
            task.wait(3)
            if Config.NCW_On then
                comboPatched = select(1, patchComboWait(math.clamp(Config.NCW_Keep, 0, 100) / 100))
            end
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  MODULE HANDLE
    -- ═══════════════════════════════════════════════════════════════════════
    local M = {}

    function M.start()
        -- Re-assert cleanup on respawn so a stale BodyVelocity never lingers.
        LocalPlayer.CharacterAdded:Connect(function()
            if flyBV then flyBV:Destroy(); flyBV = nil end
            ascendPulseUntil = 0
        end)
    end

    function M.buildUI(ctx)
        local MV = ctx.tabs.Movement
        if not MV then return end   -- tab missing (older loader) → nothing to build

        local uiReady = false
        local function notify(title, body)
            if uiReady then pcall(ctx.notify, title, body) end
        end

        -- ── UI helpers (same pattern/formatting as the AutoParry module) ──────
        -- feature: Header-adjacent "Enabled" toggle + an unbound Keybind whose
        -- Callback fires on PC AND the mobile FAB (via ctx.keybind), kept in sync
        -- with one notify. Use right after section:Header.
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
                Name = "Enabled",
                Default = o.get(),
                Callback = function(v)
                    if guard then return end
                    commit(v)
                end,
            }, ctx.flag(o.Flag))
            if o.Desc then section:SubLabel({ Text = o.Desc }) end
            ctx.keybind(section, {
                Name   = "Keybind",
                Flag   = ctx.flag(o.Flag .. "_KB"),
                Toggle = function() commit(not o.get()) end,
            })
            return { commit = commit }
        end

        -- Secondary bool toggle (own label, notifies once).
        local function boolToggle(section, name, title, get, set)
            local guard, togEl = false, nil
            togEl = section:Toggle({
                Name = name, Default = get(),
                Callback = function(v)
                    if guard then return end
                    set(v and true or false)
                    notify(title, v and "Enabled" or "Disabled")
                end,
            }, ctx.flag(name:gsub("%s+", "") .. "_T"))
            return togEl
        end

        -- Slider (never notifies, matching the reference module).
        local function slider(section, o)
            section:Slider({
                Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
                Precision = o.Precision or 0, Suffix = o.Suffix,
                Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        -- ═══════════════════ Section 1 — Speed (Left) ═══════════════════
        local secSpeed = MV:Section({ Side = "Left" })
        secSpeed:Header({ Name = "CFrame Speed" })
        feature(secSpeed, {
            Title = "CFrame Speed", Flag = "MV_Speed",
            get = function() return Config.Speed_On end,
            set = function(v) Config.Speed_On = v end,
            Desc = "adds movement on top of ur walk each frame\nfollows ur stick/WASD - works on mobile\nbind works on PC + mobile FAB",
        })
        slider(secSpeed, { Name = "Speed", Flag = "MV_SpeedVal", Default = Config.Speed_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Speed_Value = v end })
        secSpeed:SubLabel({ Text = "CFrame method = fast but can rubberband at high values\nauto-off while Fly is on" })
        secSpeed:Divider()
        secSpeed:Header({ Name = "WalkSpeed" })
        boolToggle(secSpeed, "Override WalkSpeed", "WalkSpeed Override",
            function() return Config.WS_On end, function(v) Config.WS_On = v end)
        secSpeed:SubLabel({ Text = "hard-sets ur Humanoid WalkSpeed\ngame base is 12" })
        slider(secSpeed, { Name = "WalkSpeed", Flag = "MV_WS", Default = Config.WS_Value,
            Min = 12, Max = 120, Callback = function(v) Config.WS_Value = v end })

        -- ═══════════════════ Section 2 — Fly (Right) ═══════════════════
        local secFly = MV:Section({ Side = "Right" })
        secFly:Header({ Name = "Fly" })
        feature(secFly, {
            Title = "Fly", Flag = "MV_Fly",
            get = function() return Config.Fly_On end,
            set = function(v)
                Config.Fly_On = v
                if not v then Config.Speed_On = Config.Speed_On end   -- speed loop resumes when fly off
            end,
            Desc = "PC: WASD + Space (up) / Shift (down)\nMobile: stick to move, tap Jump to rise\nbind works on PC + mobile FAB",
        })
        slider(secFly, { Name = "Fly Speed", Flag = "MV_FlyVal", Default = Config.Fly_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Fly_Value = v end })
        secFly:SubLabel({ Text = "uses BodyVelocity + PlatformStand\nauto-cleans on death / respawn" })
        secFly:Divider()
        secFly:Header({ Name = "Jump" })
        boolToggle(secFly, "Infinite Jump", "Infinite Jump",
            function() return Config.InfJump end, function(v) Config.InfJump = v end)
        boolToggle(secFly, "Override JumpPower", "JumpPower Override",
            function() return Config.JumpPower_On end, function(v) Config.JumpPower_On = v end)
        slider(secFly, { Name = "JumpPower", Flag = "MV_JumpPow", Default = Config.JumpPower_Value,
            Min = 30, Max = 200, Callback = function(v) Config.JumpPower_Value = v end })

        -- ═══════════════════ Section 3 — No Slowdown (Left) ═══════════════════
        local secNS = MV:Section({ Side = "Left" })
        secNS:Header({ Name = "No Slowdown" })
        feature(secNS, {
            Title = "No Slowdown", Flag = "MV_NoSlow",
            get = function() return Config.NS_On end,
            set = function(v) Config.NS_On = v end,
            Desc = "removes the WalkSpeed penalties combat puts on u\npick which ones below",
        })
        boolToggle(secNS, "Attack Slowdown", "No Attack Slow",
            function() return Config.NS_Attack end, function(v) Config.NS_Attack = v end)
        secNS:SubLabel({ Text = "M2 windup + style root-locks pin ur speed to 0\nthis keeps u moving through swings" })
        boolToggle(secNS, "Block Slowdown", "No Block Slow",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        secNS:SubLabel({ Text = "move at full speed while holding block" })
        boolToggle(secNS, "Stun / Parry Slowdown", "No Stun Slow",
            function() return Config.NS_Stun end, function(v) Config.NS_Stun = v end)
        secNS:SubLabel({ Text = "when parried/stunned the game drops u to speed 4\nBLATANT - the server may fight this, use carefully" })
        secNS:Divider()
        slider(secNS, { Name = "Force Speed (0 = game base)", Flag = "MV_NSForce", Default = Config.NS_Force,
            Min = 0, Max = 120, Callback = function(v) Config.NS_Force = v end })
        secNS:SubLabel({ Text = "0 = restore to ur normal base (12 / BaseWalkSpeed)\nabove 0 = force this speed during the slow" })

        -- ═══════════════════ Section 4 — Combat / Sprint (Right) ═══════════════════
        local secCombat = MV:Section({ Side = "Right" })
        secCombat:Header({ Name = "No Combo Wait" })
        feature(secCombat, {
            Title = "No Combo Wait", Flag = "MV_NoComboWait",
            get = function() return Config.NCW_On end,
            set = function(v)
                Config.NCW_On = v
                if v then
                    local ok, n = patchComboWait(math.clamp(Config.NCW_Keep, 0, 100) / 100)
                    comboPatched = ok
                    notify("No Combo Wait", ok and ("Patched (" .. tostring(n) .. ")") or "Waiting for combat to load…")
                end
            end,
            Desc = "kills the pause after a full M1 combo (finisher)\nlets u restart the chain instantly",
        })
        slider(secCombat, { Name = "Keep Delay", Flag = "MV_NCWKeep", Default = Config.NCW_Keep,
            Min = 0, Max = 60, Suffix = " %", Callback = function(v)
                Config.NCW_Keep = v
                if Config.NCW_On then patchComboWait(math.clamp(v, 0, 100) / 100) end
            end })
        secCombat:SubLabel({ Text = "% of the original gate to keep\n0 = fully instant, ~8% = near-instant but safer" })
        secCombat:Button({ Name = "Re-apply Patch", Callback = function()
            if not (_getgc and _hasDebug) then
                notify("No Combo Wait", "Executor lacks getgc/debug — unsupported")
                return
            end
            local ok, n = patchComboWait(math.clamp(Config.NCW_Keep, 0, 100) / 100)
            notify("No Combo Wait", ok and ("Patched " .. tostring(n) .. " closure(s)") or "M1 closures not found yet")
        end })
        secCombat:Divider()
        secCombat:Header({ Name = "Sprint" })
        boolToggle(secCombat, "Always Sprint", "Always Sprint",
            function() return Config.Sprint_Always end, function(v) Config.Sprint_Always = v end)
        secCombat:SubLabel({ Text = "re-asserts sprint speed even when combat tries to cancel it" })
        boolToggle(secCombat, "No Sprint Cooldown", "No Sprint Cooldown",
            function() return Config.Sprint_NoCd end, function(v) Config.Sprint_NoCd = v end)

        -- Always-Sprint runs off the same base-speed logic: when enabled we push the
        -- sprint speed via the WalkSpeed pipeline so it survives combat cancels.
        RunService.Heartbeat:Connect(function()
            if not Config.Sprint_Always then return end
            local c, hum = getChar(), getHum()
            if not (c and hum) or hum.Health <= 0 then return end
            -- Sprint speed in this game ≈ base * ~1.6; use a safe fixed boost unless
            -- the user already overrides WalkSpeed higher.
            local target = math.max(Config.WS_On and Config.WS_Value or 0, gameBaseSpeed() * 1.6)
            if hum.WalkSpeed < target - 0.05 then setSpeed(hum, target) end
        end)

        task.defer(function() uiReady = true end)
    end

    return M
end
