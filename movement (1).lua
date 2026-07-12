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

        -- No Combo Wait (hook scheduleM1SwingTimers: combo 4->1 + shrink cooldown/reset)
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

    -- ---- No Combo Wait: HOOK M1.scheduleM1SwingTimers(combo, animSpeed) ----------
    -- Definitive read of M1.lua (line numbers):
    --   scheduleM1SwingTimers(p47 combo, p48 animSpeed) (295): sets u21=false, then
    --       u22 = task.delay((p47==4 and FinisherCooldown or AttackDuration)/p48, ()->u21=true)
    --       u20 = task.delay(ComboResetTime/p48, resetCombo)
    --   tryM1 (349): `if not u21 then return false` → the ONLY client swing gate.
    -- The log proved setupvalue-on-upvalues does NOT change runtime cadence (stayed
    -- ~0.45/animSpeed). But filtergc finds THE scheduler reliably (exactly 1 match,
    -- name confirmed) and it IS called every swing. So we HOOK it: hookfunction fires
    -- deterministically for a found+called closure (unlike the ping hook, which had
    -- hit the wrong object). In the hook we:
    --   • pass combo = 1  → the finisher branch (1.25s) is never taken  → this is the
    --     "make the 4th hit behave like the 1st" the user asked for.
    --   • pass animSpeed * NCW_Speed → BOTH task.delay durations collapse toward 0, so
    --     u21 reopens almost instantly (no inter-hit wait) AND resetCombo fires fast so
    --     the counter returns to 1 (you keep swinging the 1st attack, no finisher stall).
    -- scheduleM1SwingTimers is pure client-prediction (Janitor timers); the server fire
    -- is a separate counter at tryM1:484, so nothing bad is sent. Server still rate-caps.
    local ncwHooked = false
    local _ncwCalls = 0
    local function installNCW()
        if ncwHooked then return true end
        dbg("=== installNCW ===")
        if not _hasHookFn then dbg("installNCW ABORT: no hookfunction"); return false end
        if not _filtergc  then dbg("installNCW ABORT: no filtergc");     return false end

        -- diagnostic: how many functions match the upvalue fingerprint?
        local okAll, all = pcall(_filtergc, "function", { Upvalues = { 1.25, 0.45, 1.55 }, IgnoreExecutor = true }, false)
        if okAll and type(all) == "table" then dbg("filtergc Upvalues{1.25,0.45,1.55} matched", #all, "function(s)") end

        local fn = findFn(nil, { 1.25, 0.45, 1.55 })
        if not fn then dbg("installNCW ABORT: scheduleM1SwingTimers not found"); return false end
        if _getinfo then
            local okI, info = pcall(_getinfo, fn)
            if okI and type(info) == "table" then
                dbg("NCW fn: name=", info.name, "nparams=", info.numparams, "source=", info.short_src)
            end
        end

        local orig
        orig = _hookfunction(fn, function(combo, animSpeed, ...)
            if not Config.NCW_On then return orig(combo, animSpeed, ...) end
            _ncwCalls = _ncwCalls + 1
            local mult = math.max(1, Config.NCW_Speed or 20)
            local spd  = (type(animSpeed) == "number" and animSpeed > 0) and animSpeed * mult or mult
            if _ncwCalls <= 10 or _ncwCalls % 25 == 0 then
                dbg("NCW sched #" .. _ncwCalls, "combo", tostring(combo), "->1  animSpeed",
                    tostring(animSpeed), "->", string.format("%.2f", spd))
            end
            return orig(1, spd, ...)   -- combo 4->1, inflate animSpeed => tiny cooldown/reset
        end)
        ncwHooked = true
        dbg("installNCW SUCCESS (hooked scheduleM1SwingTimers)")
        return true
    end

    -- ---- Ping Spoof: hook the REAL CombatPingAnimUtils.GetPingAnimSpeedMultiplier --
    -- Root cause of the last failure (from the dumps): the strings
    -- "NetworkAnimPingCompensation"/"MaxEstimatedOneWaySeconds" ALSO live in
    -- CombatConfig.lua, so findFn(constants) matched the WRONG function → hookfunction
    -- patched something never called during M1 → pingCalls=0.
    -- Deterministic fix: require the module by its known path
    -- (ReplicatedStorage.Shared.Utils.CombatPingAnimUtils). require() is cached, so we
    -- get the EXACT table + function object that getFinalM1AnimSpeed captured
    -- (M1.lua:88 `CombatPingAnimUtils.GetPingAnimSpeedMultiplier(...)`). We then
    -- hookfunction that real function object, so every caller (M1 + both M2 paths)
    -- dispatches to our hook, plus we overwrite the table field as a belt-and-braces.
    -- The hook recomputes the multiplier from the SPOOFED ping:
    --   delay <= 0 or spoof <= 0  → 1  (no slowdown)
    --   else  delay/(delay + clamp(spoofSec*0.5, 0, 0.35))   (spoof 1000ms => big slow).
    local pingHooked = false
    local _pingCallCount = 0
    local function computeMult(delay)
        if type(delay) ~= "number" or delay <= 0 then return 1 end
        local pingSec = math.max(0, (Config.Ping_Value or 0) / 1000)
        if pingSec <= 0 then return 1 end
        return delay / (delay + math.clamp(pingSec * 0.5, 0, 0.35))
    end
    local function pingHookBody(orig, delay, player, ...)
        if Config.Ping_On then
            local m = computeMult(delay)
            _pingCallCount = _pingCallCount + 1
            if _pingCallCount <= 10 or _pingCallCount % 25 == 0 then
                dbg("Ping mult() #" .. _pingCallCount, "delay=", tostring(delay),
                    "spoof=", Config.Ping_Value .. "ms -> mult=", string.format("%.3f", m))
            end
            return m
        end
        return orig(delay, player, ...)
    end
    local function installPing()
        if pingHooked then return true end
        dbg("=== installPing ===")
        if not _hasHookFn then dbg("installPing ABORT: no hookfunction"); return false end

        -- require the module directly (cached => same object the game uses)
        local mod
        local okReq = pcall(function()
            local inst = ReplicatedStorage:FindFirstChild("Shared")
                and ReplicatedStorage.Shared:FindFirstChild("Utils")
                and ReplicatedStorage.Shared.Utils:FindFirstChild("CombatPingAnimUtils")
            if inst then mod = require(inst) end
        end)
        dbg("Ping require ok=", okReq, "mod type=", type(mod))
        if type(mod) ~= "table" or type(mod.GetPingAnimSpeedMultiplier) ~= "function" then
            -- fallback: locate the table on the heap by its key
            local ok, tbl = pcall(_filtergc, "table", { Keys = { "GetPingAnimSpeedMultiplier" } }, true)
            if ok and type(tbl) == "table" and type(tbl.GetPingAnimSpeedMultiplier) == "function" then
                mod = tbl; dbg("Ping: got module via filtergc fallback")
            end
        end
        if type(mod) ~= "table" or type(mod.GetPingAnimSpeedMultiplier) ~= "function" then
            dbg("installPing ABORT: CombatPingAnimUtils not resolved"); return false
        end

        local orig = mod.GetPingAnimSpeedMultiplier
        if _getinfo then
            local okI, info = pcall(_getinfo, orig)
            if okI and type(info) == "table" then dbg("Ping fn source=", info.short_src, "nups=", info.nups) end
        end

        -- 1) hook the function object (covers callers that captured it directly)
        local hooked
        hooked = _hookfunction(orig, function(delay, player, ...)
            return pingHookBody(hooked, delay, player, ...)
        end)
        -- 2) overwrite the table field too (covers callers that index the table)
        pcall(function()
            mod.GetPingAnimSpeedMultiplier = function(delay, player, ...)
                return pingHookBody(orig, delay, player, ...)
            end
        end)
        pingHooked = true
        dbg("installPing SUCCESS (hookfunction + field overwrite)")
        return true
    end

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

    -- No Combo Wait needs no per-frame driver: the scheduleM1SwingTimers hook does
    -- everything (combo 4->1 + inflated animSpeed => tiny cooldown/reset) on each swing.

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
                dbg("NCW_On=", Config.NCW_On, "ncwHooked=", ncwHooked, "schedCalls=", _ncwCalls, "NCW_Speed=", Config.NCW_Speed)
                dbg("Ping_On=", Config.Ping_On, "pingHooked=", pingHooked, "pingCalls=", _pingCallCount, "spoof=", Config.Ping_Value .. "ms")
                dbg("NS_On=", Config.NS_On, "setSpeedHooked=", setSpeedHooked)
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
                    if not (_hasHookFn and _filtergc) then
                        notify("No Combo Wait", "needs hookfunction + filtergc")
                        Config.NCW_On = false
                    elseif bootstrapDone and not ncwHooked then
                        notify("No Combo Wait", "failed - scheduleM1SwingTimers not found")
                        Config.NCW_On = false
                    end
                end
            end,
            Desc = "hooks scheduleM1SwingTimers: forces the 4th (finisher) hit\nto behave as the 1st and speeds up the cooldown/reset timers",
        })
        slider(sCbt, { Name = "Combo Speed", Flag = "MV_NCWSpeed", Default = Config.NCW_Speed,
            Min = 1, Max = 50, Suffix = "x", Callback = function(v) Config.NCW_Speed = v end })
        sCbt:SubLabel({ Text = "Intercepts scheduleM1SwingTimers(combo, animSpeed): passes combo=1 so the\n1.25s finisher cooldown never fires, and multiplies animSpeed by Combo Speed\nso the inter-hit + reset delays collapse toward zero. Server still rate-caps." })

        sCbt:Divider()
        sCbt:Header({ Name = "Ping Spoof" })
        feature(sCbt, {
            Title = "Ping Spoof", Flag = "MV_Ping",
            get = function() return Config.Ping_On end,
            set = function(v)
                Config.Ping_On = v
                if v then
                    bootstrapHooks()  -- non-blocking; installs in the background
                    if not _hasHookFn then
                        notify("Ping Spoof", "needs hookfunction")
                        Config.Ping_On = false
                    elseif bootstrapDone and not pingHooked then
                        notify("Ping Spoof", "failed - CombatPingAnimUtils not found")
                        Config.Ping_On = false
                    end
                end
            end,
            Desc = "hooks the real CombatPingAnimUtils.GetPingAnimSpeedMultiplier.\nlow spoof = no anim slowdown; high spoof (1000ms) = obvious slow (test)",
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
