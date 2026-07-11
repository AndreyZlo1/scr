-- ═══════════════════════════════════════════════════════════════════════════
--  Movement — standalone module for the Syllinse loader (AutoParry game,
--  UniverseId 9199655655 — the "so you're challenging me" combat game).
--
--  Loader contract:
--    • file body returns function(Lib, Core) → returns a handle table with
--      optional start() and buildUI(ctx).
--    • ctx gives: tabs (keyed by Tab.Key), flag(name), keybind(section,opts),
--      notify(title,desc). We build everything into ctx.tabs.Movement.
--
--  EVERYTHING here is derived from the game's OWN decompiled client, not guessed:
--    • MovementServiceUtils.WALK_SPEED         = 12   (base)
--    • MovementServiceUtils.GetSprintSpeed(h)  = 25 - clamp((h-.983)/.467,0,1)*6
--      → default height 0.983  → sprint speed = 25 studs
--    • MOVE_SPEED_ANTICHEAT_TOLERANCE ≈ 1.35   → server rejects WalkSpeed above
--      ~ (sprint 25 + 1.35) ≈ 26.35. THAT is why raw WalkSpeed hacks get you
--      flagged, and why Speed here is CFrame-based (position), like the vape ref.
--    • Sprint is driven by MovementServiceClient._sprintInputDesired; the client
--      auto-resumes sprint via _tryResumeSprintFromInput whenever _wantsSprintInput
--      is true → AutoSprint = keep that flag true (health must be ≥ 10).
--    • Attack/Block slowdown = M2 windup & root-locks writing WalkSpeed=0 each
--      Heartbeat; ParryStun drops you to speed 4 via StateHandler.SetStun.
--    • M1 combo gate (CombatSystemClient.Combat.Base.M1 → scheduleM1SwingTimers):
--      task.delay((combo==4 and FinisherCooldown(1.25) or AttackDuration(0.45))
--      / animSpeed) re-arms the local canAttack flag. The 4th-hit FinisherCooldown
--      is the ONLY purely-client pause we can shrink. tryM1 ALSO checks the
--      SERVER attribute "M1Cooldown", which we cannot remove client-side.
-- ═══════════════════════════════════════════════════════════════════════════

return function(Lib, Core)
    local Players          = game:GetService("Players")
    local RunService       = game:GetService("RunService")
    local UserInputService  = game:GetService("UserInputService")
    local Workspace        = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer

    -- Executor globals (guarded — never hard-crash on a weak executor).
    local _getgc      = rawget(getfenv(0), "getgc") or (getgenv and getgenv().getgc)
    local _filtergc   = rawget(getfenv(0), "filtergc") or (getgenv and getgenv().filtergc)
    local _iscclosure = iscclosure
    local _hasDebug   = (debug and debug.getupvalues and debug.setupvalue and debug.getupvalue) and true or false

    -- PreSimulation runs BEFORE the physics step (successor to RunService.Stepped),
    -- exactly what the vape reference uses — our CFrame writes win the frame.
    local PreStep = RunService.PreSimulation or RunService.Stepped

    -- ── Runtime state (MacLib restores flags through the config manager) ─────
    local Config = {
        -- CFrame speedhack
        Speed_On     = false,
        Speed_Value  = 45,      -- studs/sec added to horizontal movement

        -- Fly (CFrame based)
        Fly_On       = false,
        Fly_Value    = 60,      -- horizontal studs/sec
        Fly_Vertical = 60,      -- vertical studs/sec
        Fly_Face     = true,    -- PlatformStand + face the camera

        -- No Slowdown (master + per-type)
        NS_On     = false,
        NS_Attack = true,       -- M2 windup / style root-locks that pin WalkSpeed to 0
        NS_Block  = true,       -- movement penalty while Blocking
        NS_Stun   = false,      -- Stunned / ParryStun (BLATANT — server fights it)
        NS_Force  = 0,          -- 0 = restore to game base (12); capped at ~25 to stay legit

        -- No Combo Wait
        NCW_On   = false,
        NCW_Keep = 0,           -- % of the finisher pause to keep (0 = normal M1 spacing)

        -- Sprint / jump extras
        Sprint_Always = false,
        InfJump       = false,
        JumpPower_On  = false,
        JumpPower_Value = 50,
    }

    -- ── Character helpers ────────────────────────────────────────────────────
    local function getChar() return LocalPlayer.Character end
    local function getHum()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid") or nil
    end
    local function getHRP()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart") or nil
    end
    -- Some rigs drive speed through Humanoid.ControllerManager.GroundSpeed, which
    -- overrides WalkSpeed — write BOTH when we force a speed.
    local function setSpeed(hum, v)
        if not hum then return end
        hum.WalkSpeed = v
        local cm = hum:FindFirstChildOfClass("ControllerManager")
        if cm then cm.GroundSpeed = v end
    end
    local function gameBaseSpeed()
        return 12   -- MovementServiceUtils.WALK_SPEED
    end

    -- Slowdown attribute groups (straight from the decompiled combat client).
    local ATTACK_ATTRS = { "CombatAttacking", "M1", "M2", "M1Hold", "PendingM1", "PendingM2", "CantAnything" }
    local STUN_ATTRS   = { "Stunned", "ParryStun", "GuardBroken" }
    local function anyAttr(c, list)
        for _, a in ipairs(list) do
            if c:GetAttribute(a) == true then return true end
        end
        return false
    end

    -- ═══════════════════════════════════════════════════════════════════════
    --  Mobile jump detection — the game's touch UI JumpButton flips its
    --  ImageRectOffset.X to 146 while held (same trick the vape reference uses).
    --  We watch it so Fly "ascend" works on phones with no keyboard.
    -- ═══════════════════════════════════════════════════════════════════════
    local mobileJumpHeld = false
    task.spawn(function()
        if not UserInputService.TouchEnabled then return end
        while true do
            local ok = pcall(function()
                local btn = LocalPlayer:WaitForChild("PlayerGui")
                    :WaitForChild("TouchGui"):WaitForChild("TouchControlFrame")
                    :WaitForChild("JumpButton")
                btn:GetPropertyChangedSignal("ImageRectOffset"):Connect(function()
                    mobileJumpHeld = btn.ImageRectOffset.X == 146
                end)
            end)
            if ok then break end
            task.wait(2)   -- TouchGui may not exist yet; retry a few times, then give up
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  CFrame SPEED  (matches the vape reference's "CFrame" method)
    --  Translate the root each frame by the camera-relative move vector. We take
    --  Humanoid.MoveDirection, which is filled by BOTH keyboard AND the mobile
    --  thumbstick → zero extra buttons on phones. Vertical velocity (gravity) is
    --  preserved so you still fall/step normally.
    -- ═══════════════════════════════════════════════════════════════════════
    PreStep:Connect(function(dt)
        if not Config.Speed_On or Config.Fly_On then return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 or hum.Sit then return end
        -- Climbing / non-grounded states: skip so we don't fling off ladders.
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Climbing then return end
        local move = hum.MoveDirection
        if move.Magnitude > 0.05 then
            local flat = Vector3.new(move.X, 0, move.Z)
            hrp.CFrame = hrp.CFrame + (flat.Unit * Config.Speed_Value * dt)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  CFrame FLY  (matches the vape reference's CFrame float)
    --  No BodyMovers: we move the root by CFrame every frame and zero its
    --  vertical velocity so there is no gravity fight → no rubberbanding.
    --  Horizontal follows MoveDirection (camera-relative, PC + mobile).
    --  Vertical: PC Space/Ctrl-Shift, mobile Jump button (ascend).
    -- ═══════════════════════════════════════════════════════════════════════
    local function stopFly()
        local hum = getHum()
        if hum and Config.Fly_Face then hum.PlatformStand = false end
    end
    PreStep:Connect(function(dt)
        if not Config.Fly_On then return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 then return end
        local cam = Workspace.CurrentCamera

        if Config.Fly_Face and cam then
            hum.PlatformStand = true
            hrp.RotVelocity = Vector3.zero
            hrp.CFrame = CFrame.lookAlong(hrp.Position, cam.CFrame.LookVector)
        end

        -- Horizontal (camera-relative move vector).
        local move = hum.MoveDirection
        local flat = Vector3.new(move.X, 0, move.Z)

        -- Vertical intent: +1 up, -1 down.
        local vert = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or mobileJumpHeld then vert += 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
           or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vert -= 1 end

        -- Kill gravity, then translate by CFrame.
        hrp.AssemblyLinearVelocity = Vector3.zero
        local delta = (flat.Unit.Magnitude == flat.Unit.Magnitude and flat.Magnitude > 0.05
                        and flat.Unit * Config.Fly_Value * dt or Vector3.zero)
                    + Vector3.new(0, vert * Config.Fly_Vertical * dt, 0)
        hrp.CFrame = hrp.CFrame + delta
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  No Slowdown (per-type).  Written on PreSimulation (before physics) so our
    --  value beats the WalkSpeed=0 the combat client stamped on the previous
    --  Heartbeat. We cap the target at 25 (the game's own sprint speed) so we
    --  restore movement WITHOUT tripping the move-speed anticheat.
    -- ═══════════════════════════════════════════════════════════════════════
    PreStep:Connect(function()
        if not Config.NS_On then return end
        local c, hum = getChar(), getHum()
        if not (c and hum) or hum.Health <= 0 then return end
        local slowed = false
        if Config.NS_Attack and anyAttr(c, ATTACK_ATTRS)      then slowed = true end
        if Config.NS_Block  and c:GetAttribute("Blocking") == true then slowed = true end
        if Config.NS_Stun   and anyAttr(c, STUN_ATTRS)        then slowed = true end
        if slowed then
            local target = (Config.NS_Force > 0) and Config.NS_Force or gameBaseSpeed()
            target = math.min(target, 25)   -- stay at/under the game's sprint cap
            setSpeed(hum, target)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  Sprint tweaks + Infinite Jump + JumpPower (all cheap, no gc scans).
    --  AutoSprint drives the game's OWN sprint: we cache the MovementServiceClient
    --  singleton once and keep _sprintInputDesired = true. The client's update
    --  loop (_tryResumeSprintFromInput) then re-starts sprint after every combat
    --  cancel exactly as if you were holding Shift.
    -- ═══════════════════════════════════════════════════════════════════════
    local moveSvc          -- cached singleton
    local moveSvcSearched = false
    local function findMoveService()
        if moveSvc or moveSvcSearched then return moveSvc end
        moveSvcSearched = true
        -- Prefer filtergc (fast + precise), fall back to a single getgc pass.
        local ok = pcall(function()
            if _filtergc then
                moveSvc = _filtergc("table",
                    { Keys = { "_sprintInputDesired", "_combatSprintLockUntil" } }, true)
            end
        end)
        if (not moveSvc) and _getgc then
            pcall(function()
                for _, o in pairs(_getgc(true)) do
                    if type(o) == "table"
                       and rawget(o, "_sprintInputDesired") ~= nil
                       and rawget(o, "_combatSprintLockUntil") ~= nil then
                        moveSvc = o
                        break
                    end
                end
            end)
        end
        return moveSvc
    end

    RunService.Heartbeat:Connect(function()
        local hum = getHum()
        if not hum or hum.Health <= 0 then return end
        if Config.Sprint_Always then
            local svc = moveSvc or findMoveService()
            if svc then svc._sprintInputDesired = true end
        end
        if Config.JumpPower_On then
            pcall(function()
                if hum.UseJumpPower ~= nil then hum.UseJumpPower = true end
                hum.JumpPower = Config.JumpPower_Value
            end)
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
    --  No Combo Wait — shrink ONLY the client-side finisher pause.
    --  scheduleM1SwingTimers captures FinisherCooldown(1.25), AttackDuration(0.45)
    --  and ComboResetTime(1.55) as upvalues; that triple uniquely identifies the
    --  closure. We scan getgc EXACTLY ONCE (cached) — the old per-3s rescan was
    --  what froze the game — and lower FinisherCooldown toward AttackDuration so
    --  the 4th-hit pause matches normal M1 spacing.
    --  NOTE: tryM1 also checks the SERVER attribute "M1Cooldown", so a full
    --  0-delay chain is not possible client-side; this removes the extra
    --  finisher stall only.
    -- ═══════════════════════════════════════════════════════════════════════
    local FIN, ATK, CMB = 1.25, 0.45, 1.55
    local comboFn          -- cached scheduleM1SwingTimers closure
    local comboFinIdx      -- upvalue index of FinisherCooldown inside it

    local function locateComboClosure()
        if comboFn then return true end
        if not (_hasDebug and (_getgc or _filtergc)) then return false end
        -- Try filtergc first (single targeted pass).
        if _filtergc then
            pcall(function()
                local f = _filtergc("function",
                    { Upvalues = { FIN, ATK, CMB }, IgnoreExecutor = true }, true)
                if type(f) == "function" then comboFn = f end
            end)
        end
        -- Fallback: one getgc sweep.
        if not comboFn and _getgc then
            pcall(function()
                for _, fn in pairs(_getgc(true)) do
                    if type(fn) == "function"
                       and not (_iscclosure and _iscclosure(fn)) then
                        local ok, ups = pcall(debug.getupvalues, fn)
                        if ok and type(ups) == "table" then
                            local hFin, hAtk, hCmb = false, false, false
                            for _, v in pairs(ups) do
                                if v == FIN then hFin = true
                                elseif v == ATK then hAtk = true
                                elseif v == CMB then hCmb = true end
                            end
                            if hFin and hAtk and hCmb then comboFn = fn break end
                        end
                    end
                end
            end)
        end
        -- Resolve the FinisherCooldown upvalue index once.
        if comboFn then
            pcall(function()
                local ups = debug.getupvalues(comboFn)
                for i, v in pairs(ups) do
                    if v == FIN then comboFinIdx = i break end
                end
            end)
            return comboFinIdx ~= nil
        end
        return false
    end

    -- keepFraction 0 → finisher pause == normal M1 spacing (AttackDuration);
    -- 1 → original 1.25s. We never touch AttackDuration/ComboResetTime (doing so
    -- desyncs animations and trips the move anticheat).
    local function applyComboWait(keepFraction)
        if not locateComboClosure() then return false, 0 end
        local target = ATK + (FIN - ATK) * math.clamp(keepFraction, 0, 1)
        local ok = pcall(debug.setupvalue, comboFn, comboFinIdx, target)
        return ok, ok and target or 0
    end

    -- ═══════════════════════════════════════════════════════════════════════
    --  MODULE HANDLE
    -- ═══════════════════════════════════════════════════════════════════════
    local M = {}

    function M.start()
        LocalPlayer.CharacterAdded:Connect(function()
            mobileJumpHeld = false
            -- A respawn rebuilds combat closures → let the next enable re-locate.
            comboFn, comboFinIdx = nil, nil
        end)
    end

    function M.buildUI(ctx)
        local MV = ctx.tabs.Movement
        if not MV then return end

        local uiReady = false
        local function notify(title, body)
            if uiReady then pcall(ctx.notify, title, body) end
        end

        -- ── UI helpers (same formatting as the AutoParry reference module) ────
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
                Callback = function(v) if not guard then commit(v) end end,
            }, ctx.flag(o.Flag))
            if o.Desc then section:SubLabel({ Text = o.Desc }) end
            ctx.keybind(section, {
                Name   = "Keybind",
                Flag   = ctx.flag(o.Flag .. "_KB"),
                Toggle = function() commit(not o.get()) end,
            })
            return { commit = commit }
        end

        local function boolToggle(section, name, title, get, set, cb)
            section:Toggle({
                Name = name, Default = get(),
                Callback = function(v)
                    set(v and true or false)
                    notify(title, v and "Enabled" or "Disabled")
                    if cb then cb(v and true or false) end
                end,
            }, ctx.flag(name:gsub("%s+", "") .. "_T"))
        end

        local function slider(section, o)
            section:Slider({
                Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
                Precision = o.Precision or 0, Suffix = o.Suffix, Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        -- ═══════════════════ Section 1 — Speed (Left) ═══════════════════
        local secSpeed = MV:Section({ Side = "Left" })
        secSpeed:Header({ Name = "CFrame Speed" })
        feature(secSpeed, {
            Title = "CFrame Speed", Flag = "MV_Speed",
            get = function() return Config.Speed_On end,
            set = function(v) Config.Speed_On = v end,
            Desc = "moves ur root by CFrame each frame (no WalkSpeed)\nfollows ur stick/WASD - works on mobile\nbind works on PC + mobile FAB",
        })
        slider(secSpeed, { Name = "Speed", Flag = "MV_SpeedVal", Default = Config.Speed_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Speed_Value = v end })
        secSpeed:SubLabel({ Text = "CFrame method dodges the WalkSpeed anticheat\n(game caps authorized WalkSpeed ~26). high values\ncan still trip position checks - tune it down if u ping-lag" })

        -- ═══════════════════ Section 2 — Fly (Right) ═══════════════════
        local secFly = MV:Section({ Side = "Right" })
        secFly:Header({ Name = "Fly" })
        feature(secFly, {
            Title = "Fly", Flag = "MV_Fly",
            get = function() return Config.Fly_On end,
            set = function(v)
                Config.Fly_On = v
                if not v then stopFly() end
            end,
            Desc = "CFrame fly, no rubberband\nPC: WASD + Space (up) / Shift (down)\nMobile: stick to move, hold Jump to rise",
        })
        slider(secFly, { Name = "Fly Speed", Flag = "MV_FlyVal", Default = Config.Fly_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Fly_Value = v end })
        slider(secFly, { Name = "Vertical Speed", Flag = "MV_FlyVert", Default = Config.Fly_Vertical,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Fly_Vertical = v end })
        boolToggle(secFly, "Face Camera", "Fly Face Camera",
            function() return Config.Fly_Face end,
            function(v) Config.Fly_Face = v end,
            function(v) if not v then local h = getHum(); if h then h.PlatformStand = false end end end)
        secFly:SubLabel({ Text = "Face Camera = PlatformStand + aim ur body where u look\nturn off to keep upright" })
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
        secNS:SubLabel({ Text = "when parried/stunned the game drops u to speed 4\nBLATANT - server may correct u, use carefully" })
        secNS:Divider()
        slider(secNS, { Name = "Force Speed (0 = game base 12)", Flag = "MV_NSForce", Default = Config.NS_Force,
            Min = 0, Max = 25, Callback = function(v) Config.NS_Force = v end })
        secNS:SubLabel({ Text = "0 = restore ur normal 12\ncapped at 25 (the game's sprint speed) to stay legit" })

        -- ═══════════════════ Section 4 — Combat / Sprint (Right) ═══════════════════
        local secCombat = MV:Section({ Side = "Right" })
        secCombat:Header({ Name = "No Combo Wait" })
        feature(secCombat, {
            Title = "No Combo Wait", Flag = "MV_NoComboWait",
            get = function() return Config.NCW_On end,
            set = function(v)
                Config.NCW_On = v
                if v then
                    if not (_hasDebug and (_getgc or _filtergc)) then
                        notify("No Combo Wait", "Executor lacks getgc/debug - unsupported")
                        return
                    end
                    local ok = applyComboWait(math.clamp(Config.NCW_Keep, 0, 100) / 100)
                    notify("No Combo Wait", ok and "Finisher pause shortened" or "Combat not loaded yet - use Re-apply")
                else
                    -- Restore the original finisher pause when disabled.
                    if comboFn and comboFinIdx then pcall(debug.setupvalue, comboFn, comboFinIdx, FIN) end
                end
            end,
            Desc = "kills the extra pause after a full M1 combo (finisher)\nrestarts the chain at normal M1 speed",
        })
        slider(secCombat, { Name = "Keep Pause", Flag = "MV_NCWKeep", Default = Config.NCW_Keep,
            Min = 0, Max = 100, Suffix = " %", Callback = function(v)
                Config.NCW_Keep = v
                if Config.NCW_On then applyComboWait(math.clamp(v, 0, 100) / 100) end
            end })
        secCombat:SubLabel({ Text = "0% = finisher pause gone (normal M1 spacing)\n100% = original 1.25s\nNOTE: server 'M1Cooldown' still applies - full 0-delay\nspam isn't possible client-side" })
        secCombat:Button({ Name = "Re-apply Patch", Callback = function()
            if not (_hasDebug and (_getgc or _filtergc)) then
                notify("No Combo Wait", "Executor lacks getgc/debug - unsupported")
                return
            end
            comboFn, comboFinIdx = nil, nil   -- force a fresh single scan
            local ok = applyComboWait(math.clamp(Config.NCW_Keep, 0, 100) / 100)
            notify("No Combo Wait", ok and "Re-applied" or "M1 closure not found yet")
        end })
        secCombat:Divider()
        secCombat:Header({ Name = "Sprint" })
        boolToggle(secCombat, "Always Sprint", "Always Sprint",
            function() return Config.Sprint_Always end,
            function(v) Config.Sprint_Always = v end,
            function(v)
                if v then
                    local svc = findMoveService()
                    notify("Always Sprint", svc and "Driving the game's own sprint" or "Movement service not found yet")
                end
            end)
        secCombat:SubLabel({ Text = "holds the game's sprint input for u (speed 25)\nauto-resumes after combat cancels it\nneeds HP >= 10, uses the legit sprint path" })

        task.defer(function() uiReady = true end)
    end

    return M
end
