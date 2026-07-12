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
--      "combo reset". Instead we HOOK scheduleM1SwingTimers with TWO edits: (1) lie
--      about `combo`, passing 1 when it is 4 so the 1.25s finisher cooldown collapses
--      to the 0.45s cadence; (2) right after the original runs (it just set u21=false)
--      force the shared u21 gate upvalue back to true via debug.setupvalue, so tryM1's
--      `if not u21` never blocks → the 0.45s inter-hit wait is gone too. Reset timer is
--      left intact. Nothing server-visible; the server M1 rate still caps real hits.
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
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local LocalPlayer = Players.LocalPlayer

    -- ── Executor globals (guarded — never hard-crash on a weak executor) ─────
    local _filtergc     = rawget(getfenv(0), "filtergc")      or (getgenv and getgenv().filtergc)
    local _getgc        = rawget(getfenv(0), "getgc")          or (getgenv and getgenv().getgc)
    local _hookfunction = rawget(getfenv(0), "hookfunction")  or (getgenv and getgenv().hookfunction)
    local _hookmeta     = rawget(getfenv(0), "hookmetamethod") or (getgenv and getgenv().hookmetamethod)
    local _namecall     = rawget(getfenv(0), "getnamecallmethod") or (getgenv and getgenv().getnamecallmethod)
    local _checkcaller  = rawget(getfenv(0), "checkcaller")   or (getgenv and getgenv().checkcaller) or function() return false end
    local _getupvalues  = (debug and rawget(debug, "getupvalues")) or rawget(getfenv(0), "getupvalues")
    local _setupvalue   = (debug and rawget(debug, "setupvalue"))  or rawget(getfenv(0), "setupvalue")
    local _hasHookFn    = type(_hookfunction) == "function"
    local _hasHookMeta  = type(_hookmeta) == "function" and type(_namecall) == "function"
    local _hasUpval     = type(_getupvalues) == "function" and type(_setupvalue) == "function"
    local _writefile    = rawget(getfenv(0), "writefile")  or (getgenv and getgenv().writefile)
    local _getconstants = (debug and rawget(debug, "getconstants")) or rawget(getfenv(0), "getconstants")
    local _getinfo      = (debug and rawget(debug, "getinfo"))      or rawget(getfenv(0), "getinfo")

    -- ── Debug logger ─────────────────────────────────────────────────────────
    -- Every dbg() line is printed to the executor console AND appended to a buffer.
    -- Press K in-game to flush the buffer to  Syllinse_Movement_Log.txt  (workspace
    -- folder of your executor) so it can be shared. Also mirrors to setclipboard.
    local _logBuf = {}
    local _logStart = os.clock()
    local function dbg(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        local line = string.format("[%.2fs] ", os.clock() - _logStart) .. table.concat(parts, " ")
        _logBuf[#_logBuf + 1] = line
        print("[Movement] " .. line)
    end
    local function dbgEnv()
        dbg("=== ENV CAPABILITIES ===")
        dbg("filtergc:", _filtergc ~= nil, "| hookfunction:", _hasHookFn,
            "| hookmeta:", _hasHookMeta, "| getupvalues/setupvalue:", _hasUpval)
        dbg("getconstants:", _getconstants ~= nil, "| getinfo:", _getinfo ~= nil,
            "| writefile:", _writefile ~= nil)
        dbg("executor:", (identifyexecutor and select(1, identifyexecutor())) or "unknown")
    end
    local function saveLog()
        local body = "Syllinse Movement debug log\n"
            .. "generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
            .. string.rep("-", 60) .. "\n"
            .. table.concat(_logBuf, "\n") .. "\n"
        if _writefile then
            local ok, err = pcall(_writefile, "Syllinse_Movement_Log.txt", body)
            if ok then
                dbg(">>> LOG SAVED to Syllinse_Movement_Log.txt (" .. #_logBuf .. " lines)")
            else
                dbg(">>> writefile FAILED:", err)
            end
        else
            dbg(">>> no writefile in this executor")
        end
        if setclipboard then pcall(setclipboard, body); dbg(">>> log copied to clipboard") end
    end

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

        -- No Slowdown (master + per-type) — hooks MovementServiceUtils.SetSpeed
        NS_On     = false,
        NS_Attack = true,         -- M1/M2/windup movement lock
        NS_Block  = true,         -- Blocking / GuardBroken
        NS_GetHit = true,         -- CantAnything / Stunned (lock from taking a hit)
        NS_Speed  = 0,            -- restore target used ONLY during those states: 0 = game base (12/25), 1..25 = exact

        -- No Combo Wait (AnimationPlayed: match M1 id -> AdjustSpeed x NCW_Speed)
        NCW_On    = false,
        NCW_Speed = 20,           -- animSpeed multiplier fed to the scheduler (higher = shorter waits)

        -- Ping Spoof (hook the REAL CombatPingAnimUtils.GetPingAnimSpeedMultiplier)
        Ping_On    = false,
        Ping_Value = 0,           -- spoofed ping in ms (0 = no slowdown; high = test slowdown)

        -- Sprint
        Sprint_On     = false,    -- AutoSprint (hold sprint on)
        Sprint_Bypass = false,    -- keep sprint speed through combat locks (SetSpeed hook)
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

    -- ═══════════════════ HOOK-BASED FEATURES ════════════════════════════════
    -- filtergc by CONSTANTS (string literals baked into the proto) — reliable even
    -- when the production bytecode ships with stripped function debug-names, which
    -- is why {Name=...} lookups silently returned nil before.
    -- PERF: ALWAYS filterOne = true. The old fallback filtergc(...,false) collected
    -- EVERY matching object on the heap into a table on every call — that full-heap
    -- sweep was the 10-second freeze. filterOne stops at the first match.
    local function findFn(constants, upvals)
        if not _filtergc then return nil end
        local opts = { IgnoreExecutor = true }
        if constants then opts.Constants = constants end
        if upvals   then opts.Upvalues  = upvals   end
        local ok, res = pcall(_filtergc, "function", opts, true)  -- filterOne = true
        if ok and type(res) == "function" then return res end
        return nil
    end

    local notifyFn  -- set inside buildUI so hooks can report status

    -- ---- No Slowdown / Get-Hit: hook MovementServiceUtils.SetSpeed(inst, speed) --
    -- THE REAL ROOT CAUSE (finally): the client _setSpeed pipeline does NOTHING while
    -- IsLocked is true (it early-returns), so hooking IsLocked never affected combat
    -- speed. The slowdowns are written DIRECTLY by the combat scripts themselves:
    --   M2  startCapoeiraRootLock → MovementServiceUtils.SetSpeed(humanoid, 0) EVERY Heartbeat
    --   M2  windup                → SetSpeed(humanoid, 0)
    --   Block engage/hold         → SetSpeed(humanoid, <reduced>)
    -- Every path funnels through MovementServiceUtils.SetSpeed, which sets
    -- Humanoid.WalkSpeed + ControllerManager GroundSpeed. So we hook SetSpeed itself:
    -- when the target is OUR humanoid and the requested speed is a slowdown, we
    -- substitute our desired speed instead of letting the write through. Because the
    -- combat scripts call SetSpeed LAST every frame, our hook always wins the race —
    -- no PostStep write-fight, no fling. IsMoveSpeedAuthorized skips the anti-cheat
    -- while locked, so raising speed during a combat lock is safe.
    -- Found by its unique constants "GroundSpeed" + "WalkSpeed".
    -- resolve the character that owns whatever instance SetSpeed was handed
    local function ownerChar(inst)
        if typeof(inst) ~= "Instance" then return nil end
        if inst:IsA("Humanoid") or inst:IsA("ControllerManager") then
            local m = inst.Parent
            return (m and m:IsA("Model")) and m or nil
        end
        if inst:IsA("Model") then return inst end
        return nil
    end
    -- the speed we should move at WHILE a slowdown is being suppressed:
    -- NS_Speed>0 forces an exact value (capped), else the game's natural base.
    local function naturalSpeed()
        return Config.Sprint_On and SPRINT_WALK or BASE_WALK
    end
    local function restoreTarget()
        if Config.NS_Speed and Config.NS_Speed > 0 then
            return math.clamp(Config.NS_Speed, 1, SPEED_CAP)
        end
        return naturalSpeed()
    end

    local setSpeedHooked = false
    local function installSetSpeedHook()
        if setSpeedHooked then return true end
        if not _hasHookFn then return false end
        local fn = findFn({ "GroundSpeed", "WalkSpeed" })
        if not fn then return false end
        local orig
        orig = _hookfunction(fn, function(inst, speed, ...)
            -- FIX: only ever act while an actual combat-lock STATE is active on us, so
            -- the Restore Speed value can NEVER leak into normal walking. When idle we
            -- do nothing and the game's own speed writes pass straight through.
            if type(speed) == "number" and (Config.NS_On or Config.Sprint_Bypass) then
                local char = ownerChar(inst)
                if char and char == LocalPlayer.Character then
                    -- which slowdown-causing state is active right now?
                    local inAttack = char:GetAttribute("M1") == true or char:GetAttribute("M2") == true
                        or char:GetAttribute("M1Hold") == true or char:GetAttribute("PendingM2") == true
                        or char:GetAttribute("CombatAttacking") == true
                    local inBlock  = char:GetAttribute("Blocking") == true or char:GetAttribute("GuardBroken") == true
                    local inGetHit = char:GetAttribute("CantAnything") == true or char:GetAttribute("Stunned") == true

                    local suppress
                    if Config.Sprint_Bypass then
                        suppress = inAttack or inBlock or inGetHit
                    elseif Config.NS_On then
                        suppress = (inAttack and Config.NS_Attack)
                                or (inBlock and Config.NS_Block)
                                or (inGetHit and Config.NS_GetHit)
                    else
                        suppress = false
                    end

                    if suppress then
                        local want = restoreTarget()
                        -- only raise an actual slowdown; never lower a legit higher speed
                        if speed < want - 0.05 then
                            return orig(inst, want, ...)
                        end
                    end
                end
            end
            return orig(inst, speed, ...)
        end)
        setSpeedHooked = true
        return true
    end

    -- ═══════════════════════════════════════════════════════════════════════════
    -- REAL COMBO LEVER: patch scheduleM1SwingTimers' cooldown upvalues (debug.setupvalue)
    -- ═══════════════════════════════════════════════════════════════════════════
    -- The user's actual complaint: after the 4th (finisher) M1 there is a long stall
    -- before you can attack again. Reading M1.lua bytecode nailed the cause:
    --
    --   scheduleM1SwingTimers(comboIdx, animSpeed):        -- M1.lua line 289
    --     u21 = false                                       -- u21 = "can attack" gate
    --     u22 = task.delay((comboIdx==4 and FinisherCooldown or AttackDuration)/animSpeed,
    --                      function() u21 = true end)        -- unlock after the wait
    --   tryM1(): if not u21 then return false end            -- input blocked until unlock
    --
    -- After the 4th hit the unlock waits FinisherCooldown (1.25s) instead of the normal
    -- AttackDuration (0.45s) → that IS the post-combo delay. CombatConfig.ClientPredict.M1
    -- = { AttackDuration=0.45, FinisherCooldown=1.25, ComboResetTime=1.55 }. These are
    -- module-level locals captured as UPVALUES of scheduleM1SwingTimers.
    --
    -- Why the old ComboSpeed (AnimationTrack:AdjustSpeed) was useless: the timer divisor
    -- is `animSpeed = getFinalM1AnimSpeed(...)`, the ORIGINAL value — our track-speed
    -- override never touched it, so the 1.25s gate stayed. We must change the GATE.
    --
    -- Fix: find scheduleM1SwingTimers by its unique upvalue value-set {1.25,0.45,1.55}
    -- (filtergc "function" Upvalues, verified by its "M1AttackCooldownTask" constant),
    -- then debug.setupvalue the FinisherCooldown upvalue down to AttackDuration (so the
    -- finisher gates like a normal swing) and divide both by Combo Speed. ONE persistent
    -- write to the real config the game reads — no per-frame hammering, no anim tricks.
    -- Do NOT touch ComboResetTime (1.55) — shrinking it would drop the combo early.
    --
    -- Dead ends already proven (do NOT retry): (1) hookfunction on M1 internals fired 0×.
    -- (2) AnimationHandler.LoadAnim table override caught the wrong table copy. (3) no
    -- Actors (getactors=0). (4) __namecall never sees LoadAnimation/AdjustSpeed (cached).
    -- (5) AnimationTrack:AdjustSpeed only speeds the VISUAL anim, not the cooldown gate.
    -- The AnimationPlayed/AdjustSpeed path below is kept ONLY as an optional visual
    -- speed-up so fast combos look fast; the wait removal is 100% the upvalue patch.
    local ncwHooked = false
    local pingHooked = false
    local animHookInstalled = false
    local ATTACK_DELAY = 0.45    -- CombatConfig ClientPredict M1 AttackDuration (approx)

    -- diagnostics
    local _apPlays, _apM1, _apApply = 0, 0, 0
    local _playedIds = {}        -- id -> { name, count, m1 }
    local _m1Ids, _m1Count = {}, 0
    local _apInstalled = false

    local function pingSpeedFactor()
        if not Config.Ping_On then return 1 end
        local realPing = 0
        pcall(function() realPing = LocalPlayer:GetNetworkPing() end)  -- seconds
        if type(realPing) ~= "number" then realPing = 0 end
        local spoof = math.max(0, (Config.Ping_Value or 0) / 1000)
        local d = ATTACK_DELAY
        local mReal  = d / (d + math.clamp(realPing * 0.5, 0, 0.35))
        local mSpoof = d / (d + math.clamp(spoof   * 0.5, 0, 0.35))
        if mReal <= 0 then return 1 end
        return mSpoof / mReal
    end

    local function speedMul()
        local mul = 1
        if Config.NCW_On  then mul = mul * math.max(1, Config.NCW_Speed or 20) end
        if Config.Ping_On then mul = mul * pingSpeedFactor() end
        return mul
    end

    -- pull the trailing numeric id out of "rbxassetid://123" / ".../?id=123"
    local function extractId(s)
        if type(s) ~= "string" then return nil end
        local d = string.match(s, "(%d+)%s*$") or string.match(s, "(%d+)")
        return d and tonumber(d) or nil
    end

    -- Build the set of M1 attack ids from the LIVE style folders (same source the game
    -- uses: CombatAnimationUtils → ReplicatedStorage.Animations.Combat.<Style>Anims →
    -- children 1stM1..4thM1). These AnimationIds are the ground truth and only exist at
    -- runtime (the static dump doesn't carry Animation.AnimationId), so we read them
    -- live. NOTE: NO AnimationRemap — that module is used only by Seats.lua (seat/emote
    -- anims), never by combat; the earlier remap theory was wrong. Rebuild on respawn.
    local function buildM1Ids()
        _m1Ids, _m1Count = {}, 0
        local function addId(x)
            if x and not _m1Ids[x] then _m1Ids[x] = true; _m1Count = _m1Count + 1 end
        end
        local anims  = ReplicatedStorage:FindFirstChild("Animations")
        local combat = anims and anims:FindFirstChild("Combat")
        if not combat then dbg("buildM1Ids: no ReplicatedStorage.Animations.Combat"); return 0 end
        for _, styleFolder in ipairs(combat:GetChildren()) do
            if styleFolder:IsA("Folder") then
                for _, nm in ipairs({ "1stM1", "2ndM1", "3rdM1", "4thM1" }) do
                    local a = styleFolder:FindFirstChild(nm)
                    if a and a:IsA("Animation") then addId(extractId(a.AnimationId)) end
                end
            end
        end
        dbg("buildM1Ids: collected", _m1Count, "M1 ids from live style folders")
        return _m1Count
    end

    -- called for every track the local Humanoid plays
    local function onAnimPlayed(track)
        _apPlays = _apPlays + 1
        local okA, anim = pcall(function() return track.Animation end)
        local id  = (okA and anim) and extractId(anim.AnimationId) or nil
        local nm  = (okA and anim) and anim.Name or "?"
        if id then
            local rec = _playedIds[id]
            if not rec then
                rec = { name = nm, count = 0, m1 = (_m1Ids[id] == true) }
                _playedIds[id] = rec
                dbg("AnimPlayed NEW id=" .. id .. " name='" .. tostring(nm) .. "' M1=" .. tostring(rec.m1))
            end
            rec.count = rec.count + 1
        end
        if not (Config.NCW_On or Config.Ping_On) then return end
        if not (id and _m1Ids[id]) then return end
        _apM1 = _apM1 + 1
        local mul = speedMul()
        if mul == 1 then return end
        local okS, base = pcall(function() return track.Speed end)
        if not okS or type(base) ~= "number" or base <= 0 then base = 1 end
        local target = base * mul
        _apApply = _apApply + 1
        if _apApply <= 10 or _apApply % 15 == 0 then
            dbg("M1 speed x" .. string.format("%.1f", mul) .. " id=" .. id ..
                " base=" .. string.format("%.2f", base) .. " -> " .. string.format("%.2f", target))
        end
        -- re-assert for a short window so the game's own AdjustSpeed can't override us
        task.spawn(function()
            local t0 = os.clock()
            while os.clock() - t0 < 0.3 do
                local playing = true
                pcall(function() playing = track.IsPlaying end)
                if not playing then break end
                pcall(function() track:AdjustSpeed(target) end)
                task.wait()
            end
        end)
    end

    -- (re)connect AnimationPlayed on the local character's Animator
    local _animator, _animConn
    local function hookAnimator()
        local char = LocalPlayer.Character
        if not char then return false end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return false end
        if _animator == animator and _animConn then return true end
        if _animConn then pcall(function() _animConn:Disconnect() end) end
        _animator = animator
        _animConn = animator.AnimationPlayed:Connect(function(track)
            pcall(onAnimPlayed, track)
        end)
        _apInstalled = true
        dbg("AnimationPlayed connected on", (pcall(function() return animator:GetFullName() end)) and animator:GetFullName() or "Animator")
        return true
    end

    -- ── Combo cooldown lever (THE fix) ─────────────────────────────────────────
    -- Read from M1.lua bytecode (verified, not grep):
    --   scheduleM1SwingTimers(comboIdx, animSpeed)  -- upvalues (exact order):
    --     [1]u21(bool) [2]u22(nil) [3]u31(table) [4]FinisherCooldown(1.25)
    --     [5]AttackDuration(0.45) [6]u20(nil) [7]ComboResetTime(1.55) [8]resetCombo(fn)
    --   body: u21=false ; u22=task.delay((comboIdx==4 and FinisherCooldown or
    --         AttackDuration)/animSpeed, function() u21=true end)
    --   Constants include "M1AttackCooldownTask" and "M1ComboResetTask".
    -- Config (CombatConfig.ClientPredict.M1) verified: AttackDuration=0.45,
    --   FinisherCooldown=1.25, ComboResetTime=1.55.
    --
    -- WHY the previous attempt did nothing (fixed here):
    --   • primary used filtergc{Upvalues={1.25,0.45,1.55}} — number-value upvalue
    --     matching is NOT reliably supported by Potassium's filtergc; likely returned
    --     nil so nothing was ever patched.
    --   • fallback searched module keys {"OnM1Activated","ServerResponse",
    --     "PerfectBlocked","GuardBroken"} — PerfectBlocked/GuardBroken are NOT keys of
    --     the M1 module (real keys: OnM1Activated, OnHoldSwing, Hold, ServerResponse),
    --     so the fallback never matched either.
    -- New finder: (1) grab the M1 module table by its REAL keys, then read
    --   scheduleM1SwingTimers straight out of v1.OnHoldSwing's upvalues (OnHoldSwing
    --   captures it directly — unambiguous). (2) Fallback: filtergc by string
    --   Constants (always matchable) then disambiguate by upvalue signature.
    local _schedFn = nil
    local _cd = { attackIdx = nil, finIdx = nil, comboIdx = nil,
                  origAttack = nil, origFin = nil, origCombo = nil }
    local _cdPatched, _cdMapped = false, false

    -- a fn is scheduleM1SwingTimers if its constants contain BOTH cooldown-task strings
    -- AND it has >=2 numeric upvalues (resetLocalCombatState has 0, ServerResponse 1).
    local function isScheduleFn(fn)
        if type(fn) ~= "function" or not _getconstants then return false end
        local okc, consts = pcall(_getconstants, fn)
        if not (okc and type(consts) == "table") then return false end
        local a, b = false, false
        for _, c in ipairs(consts) do
            if c == "M1AttackCooldownTask" then a = true
            elseif c == "M1ComboResetTask" then b = true end
        end
        if not (a and b) then return false end
        local nNum = 0
        local ups = _getupvalues(fn)
        if type(ups) == "table" then
            for _, v in pairs(ups) do if type(v) == "number" then nNum = nNum + 1 end end
        end
        return nNum >= 2
    end

    -- PRIMARY: M1 module table (real keys) → OnHoldSwing upvalues → scheduleM1SwingTimers.
    local function findViaModule()
        local ok, mod = pcall(_filtergc, "table",
            { Keys = { "OnM1Activated", "OnHoldSwing", "Hold", "ServerResponse" } }, true)
        if not (ok and type(mod) == "table") then dbg("combo lever: M1 module table NOT found"); return nil end
        -- OnHoldSwing captures scheduleM1SwingTimers directly (1-hop, unambiguous)
        local ohs = rawget(mod, "OnHoldSwing")
        if type(ohs) == "function" then
            local ups = _getupvalues(ohs)
            if type(ups) == "table" then
                for _, v in pairs(ups) do
                    if isScheduleFn(v) then dbg("combo lever: FOUND via module.OnHoldSwing"); return v end
                end
            end
        end
        -- 2-hop fallback: OnM1Activated → tryM1 → scheduleM1SwingTimers
        local oma = rawget(mod, "OnM1Activated")
        if type(oma) == "function" then
            for _, tryM1 in pairs(_getupvalues(oma) or {}) do
                if type(tryM1) == "function" then
                    for _, v in pairs(_getupvalues(tryM1) or {}) do
                        if isScheduleFn(v) then dbg("combo lever: FOUND via OnM1Activated->tryM1"); return v end
                    end
                end
            end
        end
        dbg("combo lever: module drill found no schedule fn")
        return nil
    end

    -- FALLBACK: string-Constants filter (multiple fns match → disambiguate via isScheduleFn).
    local function findViaConstants()
        local ok, res = pcall(_filtergc, "function",
            { Constants = { "M1AttackCooldownTask", "M1ComboResetTask" } }, false)
        if not (ok and type(res) == "table") then dbg("combo lever: Constants filter failed"); return nil end
        for _, fn in ipairs(res) do
            if isScheduleFn(fn) then dbg("combo lever: FOUND via Constants filter"); return fn end
        end
        dbg("combo lever: Constants filter matched " .. #res .. " fn(s), none qualified")
        return nil
    end

    local function findScheduleFn()
        if _schedFn then return _schedFn end
        if not (_filtergc and _getupvalues and _getconstants) then
            dbg("combo lever: missing filtergc/getupvalues/getconstants -> cannot find fn"); return nil
        end
        _schedFn = findViaModule() or findViaConstants()
        dbg("combo lever: scheduleM1SwingTimers " .. (_schedFn and "FOUND" or "NOT found"))
        return _schedFn
    end

    -- identify which upvalue index is which by proximity to the known config values.
    local function mapCooldownUpvalues()
        if _cdMapped then return true end
        local fn = findScheduleFn()
        if not fn then return false end
        local ups = _getupvalues(fn)
        if type(ups) ~= "table" then dbg("combo lever: getupvalues returned non-table"); return false end
        local nums = {}
        for i, v in pairs(ups) do if type(v) == "number" then nums[#nums + 1] = { idx = i, val = v } end end
        if #nums < 2 then dbg("combo lever: <2 numeric upvalues (" .. #nums .. ")"); return false end
        -- pick by closeness to config: finisher~1.25, attack~0.45, comboReset~1.55
        local function pick(target)
            local best, bestd
            for _, e in ipairs(nums) do
                local d = math.abs(e.val - target)
                if not bestd or d < bestd then best, bestd = e, d end
            end
            return best
        end
        local fin  = pick(1.25)
        local atk  = pick(0.45)
        local cmb  = pick(1.55)
        if not (fin and atk) or fin.idx == atk.idx then
            dbg("combo lever: could not disambiguate finisher/attack upvalues"); return false
        end
        _cd.finIdx,  _cd.origFin    = fin.idx, fin.val
        _cd.attackIdx, _cd.origAttack = atk.idx, atk.val
        if cmb and cmb.idx ~= fin.idx and cmb.idx ~= atk.idx then
            _cd.comboIdx, _cd.origCombo = cmb.idx, cmb.val
        end
        _cdMapped = true
        dbg("combo lever: MAPPED Finisher=" .. tostring(fin.val) .. "(#" .. fin.idx ..
            ") Attack=" .. tostring(atk.val) .. "(#" .. atk.idx ..
            ") Combo=" .. (cmb and (tostring(cmb.val) .. "(#" .. cmb.idx .. ")") or "n/a"))
        return true
    end

    local function applyComboCooldowns()
        if not mapCooldownUpvalues() then return false end
        local mul = math.max(1, Config.NCW_Speed or 1)
        -- kill the EXTRA finisher wait: finisher gates like a normal swing, then both
        -- shrink by Combo Speed. Floor keeps it sane (avoid exactly 0).
        local newAttack = math.max(0.02, _cd.origAttack / mul)
        local newFin    = math.max(0.02, math.min(_cd.origAttack, _cd.origFin) / mul)
        pcall(_setupvalue, _schedFn, _cd.attackIdx, newAttack)
        pcall(_setupvalue, _schedFn, _cd.finIdx, newFin)
        _cdPatched = true
        -- read-back verification (proves the write landed)
        local ups = _getupvalues(_schedFn)
        local rbFin = ups and ups[_cd.finIdx]
        local rbAtk = ups and ups[_cd.attackIdx]
        dbg("combo lever: APPLIED finisher " .. tostring(_cd.origFin) .. "->" .. string.format("%.3f", newFin) ..
            " attack " .. tostring(_cd.origAttack) .. "->" .. string.format("%.3f", newAttack) ..
            " | read-back finisher=" .. tostring(rbFin) .. " attack=" .. tostring(rbAtk) ..
            " (Combo Speed=" .. mul .. ")")
        return true
    end

    local function restoreComboCooldowns()
        if not (_cdPatched and _schedFn and _cd.attackIdx) then return end
        pcall(_setupvalue, _schedFn, _cd.attackIdx, _cd.origAttack)
        pcall(_setupvalue, _schedFn, _cd.finIdx, _cd.origFin)
        _cdPatched = false
        dbg("combo lever: RESTORED originals (attack=" .. tostring(_cd.origAttack) ..
            " finisher=" .. tostring(_cd.origFin) .. ")")
    end

    local _charConnDone = false
    local function installAnimHook()
        if animHookInstalled then return true end
        dbg("=== install combat lever (cooldown upvalue patch + optional anim speed) ===")
        buildM1Ids()
        local okAnim = hookAnimator()
        local okCd   = mapCooldownUpvalues()
        if not _charConnDone then
            _charConnDone = true
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)
                buildM1Ids()          -- style/anim ids may differ after respawn
                hookAnimator()
                -- scheduleM1SwingTimers is module-cached (survives respawn), but re-assert
                -- the patch if the player still has NCW enabled.
                if Config.NCW_On then applyComboCooldowns() end
            end)
        end
        animHookInstalled = true
        ncwHooked = okCd            -- NCW is "real" only if we mapped the cooldown upvalues
        pingHooked = true
        dbg("combat lever installed (animator=" .. tostring(okAnim) ..
            ", cooldownMapped=" .. tostring(okCd) .. ", m1Ids=" .. _m1Count .. ")")
        return true
    end

    local function installNCW()  return installAnimHook() and ncwHooked  end
    local function installPing() return installAnimHook() and pingHooked end

    -- ---- Background bootstrap ---------------------------------------------------
    -- All heavy scans run ONCE here, spread across frames with task.wait(), while
    -- every Config flag is still false (hooks are inert passthroughs). Toggles then
    -- only set a boolean → zero scanning on click → no freeze.
    local bootstrapStarted, bootstrapDone = false, false
    local function bootstrapHooks()
        if bootstrapStarted then return end
        bootstrapStarted = true
        task.spawn(function()
            dbg("bootstrap: starting hook installs")
            dbgEnv()
            local a = installSetSpeedHook(); dbg("installSetSpeedHook ->", a); task.wait()
            local b = installNCW();          dbg("installNCW ->", b);          task.wait()
            local c = installPing();         dbg("installPing ->", c)
            bootstrapDone = true
            dbg("bootstrap: DONE  (SetSpeed=" .. tostring(a) .. " NCW=" .. tostring(b) .. " Ping=" .. tostring(c) .. ")")
            dbg("Press K in-game to save this log to a file you can send.")
        end)
    end
    local function combatHooksReady()
        bootstrapHooks()
        return _hasHookFn
    end

    -- ══════════════════════════ AUTO SPRINT ══════════��══════════════════════
    local sprintSingleton
    local function getSprint()
        if sprintSingleton then return sprintSingleton end
        if not _filtergc then return nil end
        -- filterOne = true: grab the first table carrying _sprintInputDesired instead
        -- of collecting every matching table on the heap (the old full sweep froze).
        local ok, res = pcall(_filtergc, "table", { Keys = { "_sprintInputDesired" } }, true)
        if ok and type(res) == "table" and rawget(res, "_sprintInputDesired") ~= nil then
            sprintSingleton = res
        end
        return sprintSingleton
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

    -- No Combo Wait per-frame driver: the animation speed / 4th->1st are handled by the
    -- hooks; here we also drop the SERVER-set post-combo gate locally. tryM1 refuses when
    -- Character:GetAttribute("M1Cooldown") is truthy (M1.lua:409); the client never sets
    -- it, so clearing it locally lets the next swing fire immediately after a combo. The
    -- server re-replicates it, so we clear every frame to win the race. Real damage is
    -- still server rate-capped; this only removes the client-side stall.
    local _ncwCdClears = 0
    local function driveNCW()
        if not Config.NCW_On then return end
        local c = LocalPlayer.Character
        if not c then return end
        if c:GetAttribute("M1Cooldown") ~= nil then
            pcall(function() c:SetAttribute("M1Cooldown", nil) end)
            _ncwCdClears = _ncwCdClears + 1
            if _ncwCdClears <= 8 or _ncwCdClears % 25 == 0 then
                dbg("NCW: cleared M1Cooldown attribute (#" .. _ncwCdClears .. ")")
            end
        end
    end

    -- ═════════════════════════ MASTER LOOPS ═════════════════════════════════
    PreStep:Connect(function(dt)
        dt = (typeof(dt) == "number" and dt > 0) and dt or (1 / 60)
        pcall(stepSpeed, dt)
        pcall(stepFly, dt)
    end)
    PostStep:Connect(function()
        driveNCW()
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
        Config.NS_On, Config.NCW_On, Config.Ping_On = false, false, false
        Config.Sprint_On, Config.Sprint_Bypass = false, false
        -- Warm up the hooks in the background now, so toggling a feature later never
        -- triggers a heap scan on the click (that was the freeze). Inert until a flag flips.
        bootstrapHooks()

        -- DEBUG: press K to dump the debug log to a file (and clipboard) to share.
        UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.K then
                dbg("=== K pressed: current status ===")
                -- COMBO COOLDOWN LEVER (the real fix) — the important lines
                dbg("--- combo cooldown lever ---")
                dbg("schedFnFound=", _schedFn ~= nil, "mapped=", _cdMapped, "patched=", _cdPatched)
                if _cdMapped then
                    dbg("   origFinisher=", _cd.origFin, "(#" .. tostring(_cd.finIdx) .. ")",
                        "origAttack=", _cd.origAttack, "(#" .. tostring(_cd.attackIdx) .. ")")
                    local ups = _schedFn and _getupvalues(_schedFn)
                    dbg("   LIVE finisher=", ups and ups[_cd.finIdx], "LIVE attack=", ups and ups[_cd.attackIdx])
                end
                dbg("animHook=", animHookInstalled, "animatorHooked=", _apInstalled, "M1 idSet=", _m1Count)
                dbg("AnimationPlayed total=", _apPlays, "M1 matched=", _apM1, "speed applied=", _apApply, "cdClears=", _ncwCdClears)
                dbg("NCW_On=", Config.NCW_On, "NCW_Speed=", Config.NCW_Speed, "SpeedMul=", string.format("%.2f", speedMul()))
                dbg("Ping_On=", Config.Ping_On, "spoof=", Config.Ping_Value .. "ms | NS_On=", Config.NS_On, "setSpeedHooked=", setSpeedHooked)
                -- every played track id + whether it matched the M1 set (spot mismatches)
                dbg("--- played tracks (id / name / M1? / count) ---")
                local anyN = false
                for pid, rec in pairs(_playedIds) do
                    anyN = true
                    dbg("   id=" .. pid .. " '" .. tostring(rec.name) .. "' M1=" .. tostring(rec.m1) .. " x" .. rec.count)
                end
                if not anyN then dbg("   (none - AnimationPlayed never fired; animator not hooked?)") end
                saveLog()
            end
        end)
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

        -- ─────────��───── Section 2: Fly (Left) ───────────────
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
                if v and not combatHooksReady() then
                    notify("No Slowdown", "needs hookfunction + filtergc")
                    Config.NS_On = false
                end
            end,
            Desc = "hooks MovementServiceUtils.SetSpeed - combat scripts\nno longer force your WalkSpeed down during actions",
        })
        boolToggle(sNS, "Attack", "NoSlow Attack",
            function() return Config.NS_Attack end, function(v) Config.NS_Attack = v end)
        boolToggle(sNS, "Block", "NoSlow Block",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        boolToggle(sNS, "Get Hit", "NoSlow GetHit",
            function() return Config.NS_GetHit end, function(v) Config.NS_GetHit = v end)
        slider(sNS, { Name = "Restore Speed", Flag = "MV_NSSpeed", Default = Config.NS_Speed,
            Min = 0, Max = 25, Suffix = " spd", Callback = function(v) Config.NS_Speed = v end })
        sNS:SubLabel({ Text = "Attack = M1/M2 windup + root locks · Block = blocking/guard-broken\nGet Hit = the slow applied when you take a hit (CantAnything / Stunned).\nRestore Speed 0 = your default base (12 walk / 25 sprint); 1-25 forces that\nexact speed whenever a slowdown is suppressed. Anti-cheat is skipped while locked." })

        -- ────────��────── Section 4: Combat exploits (Right) ───────────────
        local sCbt = MV:Section({ Side = "Right" })
        sCbt:Header({ Name = "No Combo Wait" })
        feature(sCbt, {
            Title = "No Combo Wait", Flag = "MV_NCW",
            get = function() return Config.NCW_On end,
            set = function(v)
                Config.NCW_On = v
                if v then
                    bootstrapHooks()  -- non-blocking; installs in the background
                    if applyComboCooldowns() then
                        notify("No Combo Wait", "combo cooldown removed")
                    else
                        notify("No Combo Wait", "cooldown fn not mapped yet - will retry on spawn")
                    end
                else
                    restoreComboCooldowns()
                end
            end,
            Desc = "removes the delay after the 4th M1 by rewriting the game's own\nFinisherCooldown (1.25s) down to a normal swing via debug.setupvalue",
        })
        slider(sCbt, { Name = "Combo Speed", Flag = "MV_NCWSpeed", Default = Config.NCW_Speed,
            Min = 1, Max = 50, Suffix = "x", Callback = function(v)
                Config.NCW_Speed = v
                if Config.NCW_On then applyComboCooldowns() end  -- re-scale live
            end })
        sCbt:SubLabel({ Text = "Finds scheduleM1SwingTimers (M1.lua) by its {1.25,0.45,1.55} upvalue set and\nrewrites FinisherCooldown+AttackDuration with debug.setupvalue, dividing by Combo\nSpeed. This changes the real attack gate (u21), not the animation. Server may still\nrate-cap real damage, but the client-side post-combo wait is gone." })

        sCbt:Divider()
        sCbt:Header({ Name = "Ping Spoof" })
        feature(sCbt, {
            Title = "Ping Spoof", Flag = "MV_Ping",
            get = function() return Config.Ping_On end,
            set = function(v)
                Config.Ping_On = v
                if v then
                    bootstrapHooks()  -- non-blocking; installs in the background
                    if bootstrapDone and not _apInstalled then
                        notify("Ping Spoof", "no Animator yet - will hook on spawn")
                    end
                end
            end,
            Desc = "rescales M1 swing anim speed by spoofed-vs-real ping via AdjustSpeed.\nspoof 0 = removes ping slowdown (faster); 1000ms = obvious slow (test)",
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
                if v and not combatHooksReady() then
                    notify("Sprint Bypass", "needs hookfunction + filtergc")
                    Config.Sprint_Bypass = false
                end
            end)
        sSpr:SubLabel({ Text = "keeps your sprint speed through combat locks via the SetSpeed hook -\nany forced slowdown gets raised back to 25 studs while this is on." })

        uiReady = true
    end

    return M
end
