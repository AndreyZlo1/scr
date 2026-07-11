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
--  Speed & Fly are ported 1:1 from the vape reference you sent (SpeedMethods +
--  PreSimulation + Humanoid.MoveDirection). vape's entitylib/SpeedMethods are
--  reimplemented standalone here since we don't have that library.
--
--  Everything else is derived from the game's OWN decompiled client:
--    • MovementServiceUtils.WALK_SPEED = 12 (base); GetSprintSpeed → 25 studs.
--    • Sprint = MovementServiceClient singleton: SetSprintInputDesired(true) +
--      StartSprint(); StopSprint() to end it. AutoSprint OFF now truly stops.
--    • Attack/Block slowdown = M2 windup & root-locks writing WalkSpeed=0 each
--      Heartbeat; ParryStun drops you to speed 4 via StateHandler.SetStun.
--    • M1 combo gate (CombatSystemClient.Combat.Base.M1 → scheduleM1SwingTimers):
--        u21 = false                              -- locks attacking
--        u22 = task.delay((combo==4 and FinisherCooldown(1.25)
--                           or AttackDuration(0.45)) / animSpeed, ()->u21=true)
--        u20 = task.delay(ComboResetTime(1.55)/animSpeed, resetCombo)
--      tryM1 returns early `if not u21`. THAT boolean is the wait before the next
--      hit / new combo. NoComboWait shrinks BOTH delay constants AND force-holds
--      u21 = true each frame → the pause is gone. tryM1 still honours the SERVER
--      "M1Cooldown" attribute, so this speeds the chain to the server limit, it
--      does not enable impossible 0ms spam.
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

    -- PreSimulation runs BEFORE the physics step (what the vape reference uses),
    -- so our CFrame / velocity writes win the frame.
    local PreStep = RunService.PreSimulation or RunService.Stepped

    -- ── Runtime state (MacLib restores flags through the config manager) ─────
    local Config = {
        -- Speed (vape-style, method-based)
        Speed_On     = false,
        Speed_Mode   = "CFrame",   -- CFrame | Velocity | TP
        Speed_Value  = 45,         -- studs/sec

        -- Fly (vape-style, method-based)
        Fly_On       = false,
        Fly_Mode     = "CFrame",   -- CFrame | Velocity
        Fly_Value    = 60,         -- horizontal studs/sec
        Fly_Vertical = 60,         -- vertical studs/sec
        Fly_Face     = true,       -- PlatformStand + face the camera

        -- No Slowdown (master + per-type)
        NS_On     = false,
        NS_Attack = true,
        NS_Block  = true,
        NS_Stun   = false,
        NS_Force  = 0,             -- 0 = restore to game base (12); capped ~25

        -- No Combo Wait
        NCW_On   = false,
        NCW_Keep = 0,              -- % of the pause to keep (0 = instant)

        -- Sprint / jump extras
        Sprint_Always = false,
        BunnyHop      = false,
        BunnyPower    = 0,         -- 0 = use game jump; >0 = custom Y velocity
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
    local function setSpeed(hum, v)
        if not hum then return end
        hum.WalkSpeed = v
        local cm = hum:FindFirstChildOfClass("ControllerManager")
        if cm then cm.GroundSpeed = v end
    end
    local function gameBaseSpeed() return 12 end   -- MovementServiceUtils.WALK_SPEED

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
    --  Mobile jump detection — the touch UI JumpButton flips its
    --  ImageRectOffset.X to 146 while held (same trick the vape reference uses).
    -- ═══════════════════════════════════════════════════════════════════════
    local mobileJumpHeld = false
    task.spawn(function()
        if not UserInputService.TouchEnabled then return end
        for _ = 1, 15 do
            local ok = pcall(function()
                local btn = LocalPlayer:WaitForChild("PlayerGui", 9)
                    :WaitForChild("TouchGui", 9):WaitForChild("TouchControlFrame", 9)
                    :WaitForChild("JumpButton", 9)
                btn:GetPropertyChangedSignal("ImageRectOffset"):Connect(function()
                    mobileJumpHeld = btn.ImageRectOffset.X == 146
                end)
            end)
            if ok then break end
            task.wait(2)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  SpeedMethods — reimplementation of vape's table. Each takes
    --  (moveVec, speed, dt). moveVec = Humanoid.MoveDirection (camera-relative,
    --  filled by WASD AND the mobile thumbstick), so no extra buttons on phones.
    -- ═══════════════════════════════════════════════════════════════════════
    local rayParams = RaycastParams.new()
    rayParams.RespectCanCollide = true

    local tpAccrue = 0
    local SpeedMethods = {
        -- Smooth physics-based: overwrite horizontal velocity, keep gravity Y.
        Velocity = function(hrp, move, speed, dt)
            if move.Magnitude < 0.05 then return end
            local flat = Vector3.new(move.X, 0, move.Z).Unit
            hrp.AssemblyLinearVelocity = Vector3.new(
                flat.X * speed, hrp.AssemblyLinearVelocity.Y, flat.Z * speed)
        end,
        -- Positional: shift the root each frame (dodges WalkSpeed anticheat).
        CFrame = function(hrp, move, speed, dt)
            if move.Magnitude < 0.05 then return end
            local flat = Vector3.new(move.X, 0, move.Z).Unit
            local delta = flat * speed * dt
            rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
            local hit = Workspace:Raycast(hrp.Position, delta, rayParams)
            if hit then delta = (hit.Position - hrp.Position) end
            hrp.CFrame = hrp.CFrame + delta
        end,
        -- Large teleports at ~0.08s intervals — snappier but blockier.
        TP = function(hrp, move, speed, dt)
            if move.Magnitude < 0.05 then return end
            tpAccrue = tpAccrue + dt
            if tpAccrue < 0.08 then return end
            local flat = Vector3.new(move.X, 0, move.Z).Unit
            hrp.CFrame = hrp.CFrame + flat * speed * tpAccrue
            tpAccrue = 0
        end,
    }

    -- ── Speed loop ────────────────────────────────────────────────────────
    PreStep:Connect(function(dt)
        if not Config.Speed_On or Config.Fly_On then return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 or hum.Sit then return end
        if hum:GetState() == Enum.HumanoidStateType.Climbing then return end
        local fn = SpeedMethods[Config.Speed_Mode] or SpeedMethods.CFrame
        fn(hrp, hum.MoveDirection, Config.Speed_Value, dt)
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  FLY — ported from the vape reference (CFrame float + PlatformStand look).
    --  YLevel tracks the target height; vertical velocity is zeroed so gravity
    --  never fights us (no rubberband). Horizontal reuses SpeedMethods.
    -- ═══════════════════════════════════════════════════════════════════════
    local flyYLevel = nil
    local function stopFly()
        flyYLevel = nil
        local hum = getHum()
        if hum then pcall(function() hum.PlatformStand = false end) end
    end

    PreStep:Connect(function(dt)
        if not Config.Fly_On then flyYLevel = nil return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 then flyYLevel = nil return end
        local cam = Workspace.CurrentCamera

        if Config.Fly_Face and cam then
            hum.PlatformStand = true
            hrp.RotVelocity = Vector3.zero
            hrp.CFrame = CFrame.lookAlong(hrp.Position, cam.CFrame.LookVector)
        end

        -- Vertical intent (+up / -down): PC keys + mobile jump = up.
        local up, down = 0, 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or mobileJumpHeld then up = 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
           or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then down = -1 end

        if not flyYLevel then flyYLevel = hrp.Position.Y end
        flyYLevel = flyYLevel + ((up + down) * Config.Fly_Vertical * dt)

        -- Kill assembly vertical velocity so gravity can't pull us.
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)

        local move = hum.MoveDirection
        if Config.Fly_Mode == "Velocity" then
            -- Physics fly: horizontal velocity + vertical velocity toward YLevel.
            local flat = (move.Magnitude > 0.05) and Vector3.new(move.X, 0, move.Z).Unit or Vector3.zero
            local vy = (flyYLevel - hrp.Position.Y) / math.max(dt, 1/240)
            hrp.AssemblyLinearVelocity = Vector3.new(
                flat.X * Config.Fly_Value, math.clamp(vy, -120, 120), flat.Z * Config.Fly_Value)
        else
            -- CFrame fly (default): translate the root directly.
            local delta = Vector3.new(0, flyYLevel - hrp.Position.Y, 0)
            if move.Magnitude > 0.05 then
                delta = delta + Vector3.new(move.X, 0, move.Z).Unit * Config.Fly_Value * dt
            end
            hrp.CFrame = hrp.CFrame + delta
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  No Slowdown (per-type). Written on PreSimulation so our value beats the
    --  WalkSpeed=0 the combat client stamped on the previous Heartbeat. Capped at
    --  25 (the game's sprint speed) to stay under the move-speed anticheat.
    -- ═══════════════════════════════════════════════════════════════════════
    PreStep:Connect(function()
        if not Config.NS_On then return end
        local c, hum = getChar(), getHum()
        if not (c and hum) or hum.Health <= 0 then return end
        local slowed = false
        if Config.NS_Attack and anyAttr(c, ATTACK_ATTRS)          then slowed = true end
        if Config.NS_Block  and c:GetAttribute("Blocking") == true then slowed = true end
        if Config.NS_Stun   and anyAttr(c, STUN_ATTRS)            then slowed = true end
        if slowed then
            local target = (Config.NS_Force > 0) and Config.NS_Force or gameBaseSpeed()
            setSpeed(hum, math.min(target, 25))
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  Sprint singleton (MovementServiceClient). Cached once (no gc loops).
    -- ═══════════════════════════════════════════════════════════════════════
    local moveSvc, moveSvcSearched = nil, false
    local function findMoveService()
        if moveSvc or moveSvcSearched then return moveSvc end
        moveSvcSearched = true
        pcall(function()
            if _filtergc then
                moveSvc = _filtergc("table",
                    { Keys = { "_sprintInputDesired" } }, true)
            end
        end)
        if (not moveSvc) and _getgc then
            pcall(function()
                for _, o in pairs(_getgc(true)) do
                    if type(o) == "table"
                       and rawget(o, "_sprintInputDesired") ~= nil
                       and rawget(o, "_combatSprintLockUntil") ~= nil then
                        moveSvc = o break
                    end
                end
            end)
        end
        return moveSvc
    end
    local function svcCall(svc, method, ...)
        if not svc then return end
        pcall(function(...) svc[method](svc, ...) end, ...)
    end

    -- AutoSprint: keep the game's OWN sprint input held; the client auto-resumes
    -- sprint after each combat cancel. OFF → clear the flag AND StopSprint.
    RunService.Heartbeat:Connect(function()
        local hum = getHum()
        if not hum or hum.Health <= 0 then return end
        if Config.Sprint_Always then
            local svc = moveSvc or findMoveService()
            if svc then
                svc._sprintInputDesired = true
                if svc._isSprinting == false then svcCall(svc, "StartSprint") end
            end
        end
        if Config.JumpPower_On then
            pcall(function()
                if hum.UseJumpPower ~= nil then hum.UseJumpPower = true end
                hum.JumpPower = Config.JumpPower_Value
            end)
        end
    end)

    local function setAutoSprint(on)
        Config.Sprint_Always = on
        local svc = findMoveService()
        if not svc then return end
        if on then
            svc._sprintInputDesired = true
            svcCall(svc, "StartSprint")
        else
            svc._sprintInputDesired = false
            svcCall(svc, "SetSprintInputDesired", false)
            svcCall(svc, "StopSprint")   -- <-- the fix: actually end the sprint
        end
    end

    -- Infinite Jump + BunnyHop.
    UserInputService.JumpRequest:Connect(function()
        if not Config.InfJump then return end
        local hum = getHum()
        if hum and hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
    RunService.Heartbeat:Connect(function()
        if not Config.BunnyHop then return end
        local hum, hrp = getHum(), getHRP()
        if not (hum and hrp) or hum.Health <= 0 then return end
        if hum.MoveDirection.Magnitude < 0.05 then return end
        if hum.FloorMaterial == Enum.Material.Air then return end
        if Config.BunnyPower > 0 then
            local v = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, Config.BunnyPower, v.Z)
        else
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════════════
    --  No Combo Wait — the real fix.
    --  Locate scheduleM1SwingTimers ONCE (unique upvalue triple 1.25/0.45/1.55).
    --  Then: (a) shrink FinisherCooldown + AttackDuration so future scheduled
    --  re-arms are ~instant, and (b) force-hold the shared u21 boolean = true
    --  every frame (cheap, cached closure) so the CURRENTLY pending pause — the
    --  stall you feel before the next hit / new combo — is cleared immediately.
    --  Server "M1Cooldown" still gates real damage, so this caps at the server
    --  rate, it can't do impossible instant spam.
    -- ═══════════════════════════════════════════════════════════════════════
    local FIN, ATK, CMB = 1.25, 0.45, 1.55
    local comboFn                    -- scheduleM1SwingTimers closure
    local idxFin, idxAtk, idxBool    -- upvalue indices (FinisherCooldown / AttackDuration / u21)

    local function locateComboClosure()
        if comboFn then return idxBool ~= nil end
        if not (_hasDebug and (_getgc or _filtergc)) then return false end
        if _filtergc then
            pcall(function()
                local f = _filtergc("function",
                    { Upvalues = { FIN, ATK, CMB }, IgnoreExecutor = true }, true)
                if type(f) == "function" then comboFn = f end
            end)
        end
        if not comboFn and _getgc then
            pcall(function()
                for _, fn in pairs(_getgc(true)) do
                    if type(fn) == "function" and not (_iscclosure and _iscclosure(fn)) then
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
        if comboFn then
            pcall(function()
                for i, v in pairs(debug.getupvalues(comboFn)) do
                    if v == FIN then idxFin = i
                    elseif v == ATK then idxAtk = i
                    elseif type(v) == "boolean" then idxBool = i end
                end
            end)
        end
        return idxBool ~= nil
    end

    -- Push the shrunk constants. keepFraction 0 → ~instant, 1 → original.
    local function pushComboConstants(keepFraction)
        if not comboFn then return false end
        local k = math.clamp(keepFraction, 0, 1)
        local okA = idxFin and pcall(debug.setupvalue, comboFn, idxFin, math.max(FIN * k, 0.03))
        local okB = idxAtk and pcall(debug.setupvalue, comboFn, idxAtk, math.max(ATK * k, 0.03))
        return okA or okB
    end

    -- Bound loop that holds u21 = true (only alive while NCW is on).
    local ncwConn
    local function startComboForce()
        if ncwConn then return end
        ncwConn = RunService.Heartbeat:Connect(function()
            if not Config.NCW_On or not comboFn or not idxBool then return end
            pcall(debug.setupvalue, comboFn, idxBool, true)
        end)
    end
    local function stopComboForce()
        if ncwConn then ncwConn:Disconnect() ncwConn = nil end
    end
    local function restoreComboConstants()
        if comboFn then
            if idxFin then pcall(debug.setupvalue, comboFn, idxFin, FIN) end
            if idxAtk then pcall(debug.setupvalue, comboFn, idxAtk, ATK) end
        end
    end

    -- ═══════════════════════════════════════════════════════════════════════
    --  MODULE HANDLE
    -- ═══════════════════════════════════════════════════════════════════════
    local M = {}

    function M.start()
        LocalPlayer.CharacterAdded:Connect(function()
            mobileJumpHeld = false
            flyYLevel = nil
            comboFn, idxFin, idxAtk, idxBool = nil, nil, nil, nil   -- closures rebuild on respawn
            if Config.NCW_On then
                task.delay(1.2, function()
                    if Config.NCW_On and locateComboClosure() then
                        pushComboConstants(math.clamp(Config.NCW_Keep, 0, 100) / 100)
                    end
                end)
            end
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

        local function dropdown(section, o)
            section:Dropdown({
                Name = o.Name, Options = o.Options, Default = o.Default,
                Callback = o.Callback,
            }, ctx.flag(o.Flag))
        end

        -- ═══════════════════ Section 1 — Speed (Left) ═══════════════════
        local secSpeed = MV:Section({ Side = "Left" })
        secSpeed:Header({ Name = "Speed" })
        feature(secSpeed, {
            Title = "Speed", Flag = "MV_Speed",
            get = function() return Config.Speed_On end,
            set = function(v) Config.Speed_On = v end,
            Desc = "vape-style speed on ur move vector (WASD + mobile stick)\nbind works on PC + mobile FAB",
        })
        dropdown(secSpeed, { Name = "Method", Flag = "MV_SpeedMode",
            Options = { "CFrame", "Velocity", "TP" }, Default = Config.Speed_Mode,
            Callback = function(v) Config.Speed_Mode = v end })
        slider(secSpeed, { Name = "Speed", Flag = "MV_SpeedVal", Default = Config.Speed_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Speed_Value = v end })
        secSpeed:SubLabel({ Text = "CFrame = positional, dodges the WalkSpeed anticheat (best)\nVelocity = smooth physics\nTP = snappy teleports\ngame caps authorized WalkSpeed ~26, so keep it sane" })

        -- ═══════════════════ Section 2 — Fly (Right) ═══════════════════
        local secFly = MV:Section({ Side = "Right" })
        secFly:Header({ Name = "Fly" })
        feature(secFly, {
            Title = "Fly", Flag = "MV_Fly",
            get = function() return Config.Fly_On end,
            set = function(v) Config.Fly_On = v if not v then stopFly() end end,
            Desc = "vape CFrame fly, no rubberband\nPC: WASD + Space (up) / Shift (down)\nMobile: stick to move, hold Jump to rise",
        })
        dropdown(secFly, { Name = "Method", Flag = "MV_FlyMode",
            Options = { "CFrame", "Velocity" }, Default = Config.Fly_Mode,
            Callback = function(v) Config.Fly_Mode = v end })
        slider(secFly, { Name = "Fly Speed", Flag = "MV_FlyVal", Default = Config.Fly_Value,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Fly_Value = v end })
        slider(secFly, { Name = "Vertical Speed", Flag = "MV_FlyVert", Default = Config.Fly_Vertical,
            Min = 10, Max = 250, Suffix = " studs/s", Callback = function(v) Config.Fly_Vertical = v end })
        boolToggle(secFly, "Face Camera", "Fly Face Camera",
            function() return Config.Fly_Face end,
            function(v) Config.Fly_Face = v end,
            function(v) if not v then local h = getHum(); if h then pcall(function() h.PlatformStand = false end) end end end)
        secFly:SubLabel({ Text = "Face Camera = PlatformStand + aim body where u look\nturn off to stay upright" })
        secFly:Divider()
        secFly:Header({ Name = "Jump" })
        boolToggle(secFly, "Infinite Jump", "Infinite Jump",
            function() return Config.InfJump end, function(v) Config.InfJump = v end)
        boolToggle(secFly, "Bunny Hop", "Bunny Hop",
            function() return Config.BunnyHop end, function(v) Config.BunnyHop = v end)
        secFly:SubLabel({ Text = "auto-jumps while u move on the ground" })
        slider(secFly, { Name = "Hop Power (0 = normal)", Flag = "MV_Bunny", Default = Config.BunnyPower,
            Min = 0, Max = 120, Callback = function(v) Config.BunnyPower = v end })
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
        secNS:SubLabel({ Text = "M2 windup + style root-locks pin ur speed to 0" })
        boolToggle(secNS, "Block Slowdown", "No Block Slow",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        secNS:SubLabel({ Text = "move at full speed while holding block" })
        boolToggle(secNS, "Stun / Parry Slowdown", "No Stun Slow",
            function() return Config.NS_Stun end, function(v) Config.NS_Stun = v end)
        secNS:SubLabel({ Text = "parry/stun drops u to speed 4 - BLATANT, server may correct u" })
        secNS:Divider()
        slider(secNS, { Name = "Force Speed (0 = base 12)", Flag = "MV_NSForce", Default = Config.NS_Force,
            Min = 0, Max = 25, Callback = function(v) Config.NS_Force = v end })
        secNS:SubLabel({ Text = "0 = restore ur normal 12\ncapped at 25 (sprint speed) to stay legit" })

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
                        Config.NCW_On = false
                        return
                    end
                    if locateComboClosure() then
                        pushComboConstants(math.clamp(Config.NCW_Keep, 0, 100) / 100)
                        startComboForce()
                        notify("No Combo Wait", "Active - combo pause removed")
                    else
                        startComboForce()   -- will kick in once M1 loads / after a swing
                        notify("No Combo Wait", "M1 not loaded yet - throw a hit or use Re-apply")
                    end
                else
                    stopComboForce()
                    restoreComboConstants()
                end
            end,
            Desc = "kills the pause before the next hit / new combo\n(incl. the 4th-hit finisher stall)",
        })
        slider(secCombat, { Name = "Keep Pause", Flag = "MV_NCWKeep", Default = Config.NCW_Keep,
            Min = 0, Max = 100, Suffix = " %", Callback = function(v)
                Config.NCW_Keep = v
                if Config.NCW_On and comboFn then pushComboConstants(math.clamp(v, 0, 100) / 100) end
            end })
        secCombat:SubLabel({ Text = "0% = instant chain, 100% = original timing\nNOTE: server 'M1Cooldown' still applies - this speeds\nthe chain to the server limit, not to literal 0ms" })
        secCombat:Button({ Name = "Re-apply Patch", Callback = function()
            if not (_hasDebug and (_getgc or _filtergc)) then
                notify("No Combo Wait", "Executor lacks getgc/debug - unsupported")
                return
            end
            comboFn, idxFin, idxAtk, idxBool = nil, nil, nil, nil
            local ok = locateComboClosure()
            if ok then pushComboConstants(math.clamp(Config.NCW_Keep, 0, 100) / 100) end
            notify("No Combo Wait", ok and "Re-applied" or "M1 closure not found - swing once then retry")
        end })
        secCombat:Divider()
        secCombat:Header({ Name = "Sprint" })
        boolToggle(secCombat, "Always Sprint", "Always Sprint",
            function() return Config.Sprint_Always end,
            function(v) setAutoSprint(v) end,
            function(v)
                if v then
                    local svc = findMoveService()
                    if not svc then notify("Always Sprint", "Movement service not found yet") end
                end
            end)
        secCombat:SubLabel({ Text = "holds the game's sprint (speed 25), auto-resumes after\ncombat cancels. OFF now actually stops sprinting.\nneeds HP >= 10 - uses the legit sprint path" })

        task.defer(function() uiReady = true end)
    end

    return M
end
