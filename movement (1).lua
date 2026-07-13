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
--    • No Delay — kills EVERY combat cooldown/reset wait at the SOURCE with a single
--      direct hookfunction(task.delay). All combat delays funnel through task.delay in
--      CombatSystemClient.Combat.Base.M1:
--        u22 = task.delay((combo==4 and 1.25 or 0.45)/spd, ()->u21=true)  -- swing chain gate
--        u20 = task.delay(ComboResetTime(1.55)/spd, resetCombo)           -- combo reset
--        + StopAnim / fx delays (0.1, 0.2, 0.45)
--      Our task.delay hook, while No Delay is on, collapses those combat cooldown values
--      to ~0 so u21 re-opens instantly and the next swing fires with no wait. No upvalue
--      hunting, no filtergc, no rawget — just the global hook. We ALSO clear the server-
--      set gate attributes (M1Cooldown/M1/CantAnything/…) locally each frame. The server
--      M1 rate still caps REAL damage — this removes the client-side stall/feel only.
--
--    • No Stun — hookfunction on StateHandler.SetStun(char, apply, dur, speed),
--      found via filtergc {Name="SetStun"}. When it tries to APPLY a stun to us we
--      never call the original, so it never writes our WalkSpeed/GroundSpeed down.
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

        -- No Delay (direct hookfunction(task.delay) → collapse combat cooldown/reset waits)
        NoDelay_On    = false,
        NoDelay_Attrs = true,     -- also clear server gate attributes (M1Cooldown/M1/…) each frame
        NoDelay_Anim  = 1,        -- OPTIONAL visual: multiply M1 swing anim playback speed (1 = off)

        -- Sprint
        Sprint_On     = false,    -- AutoSprint (hold sprint on)
        Sprint_Bypass = false,    -- keep sprint speed through combat locks (SetSpeed hook)

        -- No Slowdown: respect "cannot move" states (grapple/ragdoll/carry/anchor).
        -- FIX for the reported bug — while immobile, NONE of our speed writes fire, so we
        -- never fight the game's HRP anchor/snap (that was the rubberband during grapples).
        NS_RespectImmobile = true,

        -- Infinite Sprint — hold the client sprint singleton's _staminaSeenPositive at false.
        -- Both stamina cutoffs (StartSprint + render loop) require that flag TRUE to stop
        -- sprinting on Stamina<=0. Keeping it false = endless sprint. We NEVER touch the
        -- Stamina attribute (server-authoritative, would be detectable) — pure client field.
        InfStamina_On = false,

        -- No M2 Cooldown — zero the client attempt-lockout upvalues in M2.OnM2Activated,
        -- clear the M2Cooldown gate attribute each frame, and expose a direct-fire trigger
        -- (CombatRemoteClient.Fire("M2","ServerCheck")). Server still caps REAL M2 damage.
        NoM2CD_On = false,

        -- Dodge tweaks (patches the game Evasive module's own upvalues + drives it)
        Dodge_On         = false,   -- master: resolve Evasive module + enable our trigger
        Dodge_Everywhere = false,   -- fire in ANY state (grant + clear inline state gates)
        Dodge_Speed      = 0,       -- 0 = game DashSpeed, else exact studs/sec (setupvalue)
        Dodge_Cooldown   = 0,       -- 0 = game cooldown, else OUR min spacing between dodges (s)

        -- Anti-Ragdoll / Auto-getup — force getup while Ragdoll is active and NOT a managed
        -- ragdoll (Downed / carried / dead). Best-effort: server owns the real ragdoll state.
        AntiRagdoll_On = false,
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

    -- ═══════════════════ IMMOBILE-STATE DETECTOR (NoSlowdown fix) ════════════
    -- The bug: during a grapple the game ANCHORS HumanoidRootPart and re-snaps its CFrame
    -- every frame (RagdollService / Grapple.lua enforcePreAnimationAlignment), and combat
    -- also carries/gits/ragdolls you. Our Speed / Fly CFrame writes and the SetSpeed hook's
    -- speed restore fought that anchor → the "changes speed when it shouldn't" rubberband.
    -- These are states where the player is NOT meant to move at all, verified in the dump:
    --   • HRP.Anchored              → grapple root-lock (Grapple.lua)
    --   • attr Grappling            → M2.lua wrestling/grapple gate
    --   • attr Ragdoll / Downed     → RagdollServiceClient managed ragdoll
    --   • States.BeingCarried / BeingGripped (Value ~= nil)  → carry / grip
    --   • HRP.CarryWeld / GripWeld  → physical carry/grip weld (RagdollServiceClient.isCarriedOrGripped)
    -- While ANY is active we suppress every speed write so the game's lock wins cleanly.
    local IMMOBILE_ATTRS = { "Grappling", "Ragdoll", "Downed" }
    local function isImmobile(char, root)
        if not Config.NS_RespectImmobile then return false end
        char = char or getChar(); if not char then return false end
        if not root then
            root = char:FindFirstChild("HumanoidRootPart")
        end
        if root and root.Anchored then return true end
        for _, a in ipairs(IMMOBILE_ATTRS) do
            if char:GetAttribute(a) == true then return true end
        end
        local states = char:FindFirstChild("States")
        if states then
            local bc = states:FindFirstChild("BeingCarried")
            local bg = states:FindFirstChild("BeingGripped")
            if (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil) then return true end
        end
        if root and (root:FindFirstChild("CarryWeld") or root:FindFirstChild("GripWeld")) then
            return true
        end
        return false
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
        local char, hum, root = getParts(); if not hum then return end
        -- FIX: never shove the root while the game has us locked/anchored (grapple, ragdoll,
        -- carry, grip) — that write-fight was the erratic speed the user reported.
        if isImmobile(char, root) then return end
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
        local char, hum, root = getParts()
        if not hum then return end
        -- FIX: while grappled/ragdolled/carried the game anchors us; don't fly-fight it.
        if isImmobile(char, root) then return end
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

    -- ═══════════════════ HOOK-BASED FEATURES ══════════════════════════��═════
    -- filtergc by CONSTANTS (string literals baked into the proto) — reliable even
    -- when the production bytecode ships with stripped function debug-names, which
    -- is why {Name=...} lookups silently returned nil before.
    -- PERF: ALWAYS filterOne = true. The old fallback filtergc(...,false) collected
    -- EVERY matching object on the heap into a table on every call — that full-heap
    -- sweep was the 10-second freeze. filterOne stops at the first match.
    local function findFn(constants, upvals)
        if type(filtergc) ~= "function" then return nil end
        local opts = { IgnoreExecutor = true }
        if constants then opts.Constants = constants end
        if upvals   then opts.Upvalues  = upvals   end
        local ok, res = pcall(filtergc, "function", opts, true)  -- filterOne = true
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
        if type(hookfunction) ~= "function" then return false end
        local fn = findFn({ "GroundSpeed", "WalkSpeed" })
        if not fn then return false end
        local orig
        orig = hookfunction(fn, function(inst, speed, ...)
            -- FIX: only ever act while an actual combat-lock STATE is active on us, so
            -- the Restore Speed value can NEVER leak into normal walking. When idle we
            -- do nothing and the game's own speed writes pass straight through.
            if type(speed) == "number" and (Config.NS_On or Config.Sprint_Bypass) then
                local char = ownerChar(inst)
                if char and char == LocalPlayer.Character then
                    -- FIX: if the game has us in a no-move state (grapple/ragdoll/carry/anchor),
                    -- let its speed write through UNTOUCHED. Restoring speed here is exactly what
                    -- made movement go weird during grapples — suppress our override instead.
                    if isImmobile(char, nil) then
                        return orig(inst, speed, ...)
                    end
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
    -- NO DELAY: collapse every combat cooldown/reset wait via hookfunction(task.delay)
    -- ═══════════════════════════════════════════════════════════════════════════
    -- Reading M1.lua bytecode: EVERY combat wait is a task.delay. The one that gates the
    -- next swing (the felt post-combo stall) is:
    --   scheduleM1SwingTimers(comboIdx, spd):
    --     u21 = false                                                  -- "can attack" = closed
    --     u22 = task.delay((comboIdx==4 and 1.25 or 0.45)/spd, ()->u21=true)  -- re-open gate
    --     u20 = task.delay(1.55/spd, resetCombo)                       -- combo reset
    --   tryM1(): if not u21 then return end  (+ M1Cooldown/M1/CantAnything attribute gates)
    --
    -- So a SINGLE direct hookfunction(task.delay) that shrinks the combat cooldown values
    -- to ~0 makes u21 re-open instantly → no wait. No upvalue hunting, no filtergc/rawget:
    -- task.delay is a global, hooking it is enough (exactly the simple approach). We match
    -- the known combat cooldown durations (0.45 / 1.25 / 1.55, tolerant of the /spd scale)
    -- so unrelated game timers are untouched. The gate ATTRIBUTES the server sets
    -- (M1Cooldown/M1/CantAnything/…) are cleared locally each frame (NoDelay_Attrs).
    -- Honest ceiling: the server M1 rate still caps REAL damage; this removes the client
    -- stall/feel and lets the animation chain freely.
    local animHookInstalled = false
    local _m1Ids = {}            -- set of live M1 animation ids (for the optional anim-speed visual)

    -- known M1 combat cooldown/reset durations (CombatConfig.ClientPredict.M1)
    local COMBAT_DELAYS = { 0.45, 1.25, 1.55 }   -- AttackDuration, FinisherCooldown, ComboResetTime
    local function isCombatDelay(t)
        -- match the base values AND their /spd-scaled forms (spd is usually ~1; a faster
        -- anim only makes t smaller, so we also treat any small positive t <= 1.6 that is
        -- close to a base value / integer-ish speed as combat). Tolerance keeps it precise.
        for _, v in ipairs(COMBAT_DELAYS) do
            if math.abs(t - v) <= 0.12 then return true end
        end
        return false
    end

    -- optional VISUAL: multiply the M1 swing animation playback speed (so a fast chain
    -- also looks fast). Purely cosmetic (AdjustSpeed on the track), never the wait fix.
    local function animSpeedMul()
        if not Config.NoDelay_On then return 1 end
        return math.max(1, Config.NoDelay_Anim or 1)
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
        _m1Ids = {}
        local anims  = ReplicatedStorage:FindFirstChild("Animations")
        local combat = anims and anims:FindFirstChild("Combat")
        if not combat then return end
        for _, styleFolder in ipairs(combat:GetChildren()) do
            if styleFolder:IsA("Folder") then
                for _, nm in ipairs({ "1stM1", "2ndM1", "3rdM1", "4thM1" }) do
                    local a = styleFolder:FindFirstChild(nm)
                    if a and a:IsA("Animation") then
                        local x = extractId(a.AnimationId)
                        if x then _m1Ids[x] = true end
                    end
                end
            end
        end
    end

    -- called for every track the local Humanoid plays (optional M1 anim-speed visual)
    local function onAnimPlayed(track)
        if not Config.NoDelay_On then return end
        local mul = animSpeedMul()
        if mul == 1 then return end
        local okA, anim = pcall(function() return track.Animation end)
        local id = (okA and anim) and extractId(anim.AnimationId) or nil
        if not (id and _m1Ids[id]) then return end
        local okS, base = pcall(function() return track.Speed end)
        if not okS or type(base) ~= "number" or base <= 0 then base = 1 end
        local target = base * mul
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
        return true
    end

    -- ── No Delay: ONE direct hookfunction(task.delay) kills every combat wait ───
    -- Every M1 cooldown/reset is a task.delay in M1.lua. We hook the GLOBAL task.delay
    -- directly (no rawget alias, no filtergc, no upvalue hunting — the simple call the
    -- user asked for) and, while No Delay is on, collapse the combat-cooldown durations
    -- (0.45/1.25/1.55) to ~0 so the "can attack" gate re-opens instantly. Other game
    -- timers are matched by value and left alone. Installed once; a flag toggles it.
    local _delayHooked = false
    local _origDelay = nil
    local function installNoDelayHook()
        if _delayHooked then return true end
        if type(hookfunction) ~= "function" then return false end
        local ok = pcall(function()
            _origDelay = hookfunction(task.delay, function(t, fn, ...)
                if Config.NoDelay_On and type(t) == "number" and isCombatDelay(t) then
                    t = 0
                end
                return _origDelay(t, fn, ...)
            end)
        end)
        if not (ok and _origDelay) then return false end
        _delayHooked = true
        return true
    end

    -- clear the server-set gate attributes locally each frame (best-effort; server may
    -- re-set them). tryM1 refuses while any of these are truthy on the character.
    local GATE_ATTRS = { "M1Cooldown", "M1", "CantAnything", "CannotAttack", "Stunned",
                         "Attacking", "Casting", "ComboCooldown" }
    -- [V111] PERF: персистентная fn для pcall БЕЗ аллокации замыкания. clearGateAttrs крутится
    -- КАЖДЫЙ Heartbeat при No Delay → прежний `pcall(function() ... end)` на каждый очищаемый
    -- атрибут = до 8 closure/кадр = лишний GC. Персистентная fn не аллоцирует ничего.
    local function _clearAttr(c, a) c:SetAttribute(a, nil) end
    local function clearGateAttrs()
        if not (Config.NoDelay_On and Config.NoDelay_Attrs) then return end
        local c = LocalPlayer.Character
        if not c then return end
        for _, a in ipairs(GATE_ATTRS) do
            if c:GetAttribute(a) ~= nil then pcall(_clearAttr, c, a) end
        end
    end

    local _charConnDone = false
    local function installAnimHook()
        if animHookInstalled then return true end
        buildM1Ids()
        hookAnimator()
        installNoDelayHook()
        if not _charConnDone then
            _charConnDone = true
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)
                buildM1Ids()          -- style/anim ids may differ after respawn
                hookAnimator()
                -- task.delay hook is global (survives respawn) and inert unless
                -- Config.NoDelay_On → nothing to re-apply.
            end)
        end
        animHookInstalled = true
        return true
    end

    -- ---- Background bootstrap ---------------------------------------------------
    -- All heavy scans run ONCE here, spread across frames with task.wait(), while
    -- every Config flag is still false (hooks are inert passthroughs). Toggles then
    -- only set a boolean → zero scanning on click → no freeze.
    local bootstrapStarted = false
    local function bootstrapHooks()
        if bootstrapStarted then return end
        bootstrapStarted = true
        task.spawn(function()
            installSetSpeedHook()
            task.wait()
            installAnimHook()
        end)
    end
    local function combatHooksReady()
        bootstrapHooks()
        return type(hookfunction) == "function"
    end

    -- ══════════════════════════ AUTO SPRINT ══════════��══════════════════════
    local sprintSingleton
    local function getSprint()
        if sprintSingleton then return sprintSingleton end
        if type(filtergc) ~= "function" then return nil end
        -- filterOne = true: grab the first table carrying _sprintInputDesired instead
        -- of collecting every matching table on the heap (the old full sweep froze).
        local ok, res = pcall(filtergc, "table", { Keys = { "_sprintInputDesired" } }, true)
        if ok and type(res) == "table" and rawget(res, "_sprintInputDesired") ~= nil then
            sprintSingleton = res
        end
        return sprintSingleton
    end
    -- [V111] PERF: персистентные fn для pcall БЕЗ аллокации замыкания. _assertDesired крутится
    -- КАЖДЫЙ Heartbeat пока Sprint включён — прежний `pcall(function() ... end)` = closure/кадр.
    local function _desireOn(s)  s:SetSprintInputDesired(true)  end
    local function _desireOff(s) s:SetSprintInputDesired(false) end
    local function _startSprint(s) s:StartSprint() end
    local function _stopSprint(s)  s:StopSprint()  end
    local function setSprint(on)
        local s = getSprint(); if not s then return false end
        if on then
            pcall(_desireOn, s)
            pcall(_startSprint, s)
        else
            pcall(_desireOff, s)
            -- StopSprint(self, playCooldown, fromCancel); no extra args = clean stop
            pcall(_stopSprint, s)
        end
        return true
    end

    -- No Delay per-frame driver: the actual wait removal is the task.delay hook; here we
    -- only clear the SERVER-set gate attributes locally (best-effort; the server re-sets
    -- them, so we clear each frame). Real damage stays server-authoritative.
    local function driveNoDelay()
        clearGateAttrs()
    end

    -- ═══════════════════════════════════════════════════════════════════════════
    -- COMBAT MODULE RESOLVERS — require the game's OWN cached modules → LIVE upvalues
    -- ═══════════════════════════════════════════════════════════════════════════
    -- require() on a ModuleScript the game already required returns the SAME cached table,
    -- so Evasive.Evasive / M2.OnM2Activated are the live functions and debug.setupvalue
    -- patches the very upvalues the combat system reads. No filtergc heap sweep needed.
    local function tryRequire(pathParts)
        local node = ReplicatedStorage
        for _, name in ipairs(pathParts) do
            if not node then return nil end
            node = node:FindFirstChild(name)
        end
        if not node then return nil end
        local ok, mod = pcall(require, node)
        return ok and mod or nil
    end
    local _evasiveMod, _m2Mod, _combatRemote, _combatConfig
    local function getEvasive()
        if _evasiveMod == nil then
            _evasiveMod = tryRequire({ "CombatSystemClient", "Combat", "Base", "Evasive" }) or false
        end
        return _evasiveMod or nil
    end
    local function getM2()
        if _m2Mod == nil then
            _m2Mod = tryRequire({ "CombatSystemClient", "Combat", "Base", "M2" }) or false
        end
        return _m2Mod or nil
    end
    local function getCombatRemote()
        if _combatRemote == nil then
            _combatRemote = tryRequire({ "Shared", "Network", "CombatRemoteClient" }) or false
        end
        return _combatRemote or nil
    end
    local function getCombatConfig()
        if _combatConfig == nil then
            _combatConfig = tryRequire({ "Shared", "Config", "CombatConfig" }) or false
        end
        return _combatConfig or nil
    end
    local function hasDebugUpvalues()
        return type(debug) == "table" and type(debug.getupvalues) == "function"
            and type(debug.setupvalue) == "function"
    end

    -- ══════════════════ INFINITE SPRINT (stamina, client field) ═════════════
    -- The game only STOPS sprint on Stamina<=0 when the sprint singleton's
    -- _staminaSeenPositive is TRUE (StartSprint gate @ line 2072 + render loop @ 2170).
    -- Held at false → sprint never dies. Written on Heartbeat (after the game's RenderStep,
    -- which only re-latches it true when Stamina>0), so on a drained frame it stays false.
    -- We NEVER touch the Stamina ATTRIBUTE (server-authoritative → detectable). Pure client.
    local function driveInfStamina()
        if not Config.InfStamina_On then return end
        local s = getSprint(); if not s then return end
        if rawget(s, "_staminaSeenPositive") ~= false then
            pcall(function() s._staminaSeenPositive = false end)
        end
    end

    -- ══════════════════════════ DODGE TWEAKS ════════════════════════════════
    -- Custom Speed  = patch the Evasive module's DashSpeed upvalue (setupvalue).
    -- Everywhere    = set the OutnumberedEvasiveGrant attribute (Evasive()'s canDodge returns
    --                 true on that path, line 245) + clear the state attributes it rejects on.
    -- Custom CD     = zero the module's runtime cooldown timers (u5/u6/u7/u8) so its own gate
    --                 can't block us; OUR _lastDodge spacing becomes the real cooldown.
    -- Honest ceiling: the SERVER still owns i-frames — a dash fired in an invalid state moves
    -- you but may not grant invulnerability.
    -- Map u1.Evasive's upvalues ONCE. Verified upvalue list (Evasive.lua line 506) contains the
    -- module-level locals DashSpeed / DashDuration / Cooldown / ServerConfirmTimeout (matched by
    -- their CombatConfig values) plus the runtime cooldown/stun timers u4/u5/u6/u7/u8 (all start
    -- at 0, mutate at runtime). We patch DashSpeed for custom speed, and zero the runtime timers
    -- to bypass the module's own cooldown for custom-CD / everywhere.
    local _evMapped, _evSpeedIdx, _evSpeedBase, _evTimerIdx = false, nil, nil, {}
    local function mapEvasive()
        if _evMapped then return _evSpeedIdx ~= nil or #_evTimerIdx > 0 end
        local ev = getEvasive(); if not ev or type(ev.Evasive) ~= "function" then return false end
        if not hasDebugUpvalues() then return false end
        local ok, ups = pcall(debug.getupvalues, ev.Evasive)
        if not (ok and type(ups) == "table") then return false end
        local cfg = getCombatConfig()
        local ev2 = cfg and cfg.Evasive
        local named = {}   -- config-sourced numeric constants we must NOT treat as timers
        if ev2 then
            for _, key in ipairs({ "DashSpeed", "DashDuration", "Cooldown" }) do
                if type(ev2[key]) == "number" then named[ev2[key]] = key end
            end
        end
        -- ServerConfirmTimeout lives under CombatConfig.ClientPredict.Evasive (not cfg.Evasive)
        local cp = cfg and cfg.ClientPredict and cfg.ClientPredict.Evasive
        if cp and type(cp.ServerConfirmTimeout) == "number" then
            named[cp.ServerConfirmTimeout] = "ServerConfirmTimeout"
        end
        for i, v in pairs(ups) do
            if type(v) == "number" then
                local asName = named[v]
                if asName == "DashSpeed" and not _evSpeedIdx then
                    _evSpeedIdx, _evSpeedBase = i, v
                elseif asName == nil then
                    -- not a known config constant → runtime timer (u4..u8), safe to zero
                    _evTimerIdx[#_evTimerIdx + 1] = i
                end
            end
        end
        _evMapped = true
        return true
    end
    local function applyDodgeSpeed()
        local ev = getEvasive(); if not ev then return end
        if not mapEvasive() or not _evSpeedIdx then return end
        local target = (Config.Dodge_Speed and Config.Dodge_Speed > 0) and Config.Dodge_Speed or _evSpeedBase
        if target then pcall(debug.setupvalue, ev.Evasive, _evSpeedIdx, target) end
    end
    -- state attributes Evasive() rejects on unless the OutnumberedEvasiveGrant path is taken
    local DODGE_STATE_GATES = { "Ragdoll", "Blocking", "CombatAttacking", "Greenzone",
                                "RpCombatLocked", "Downed", "Stunned", "GuardBroken" }
    local _lastDodge = 0
    local function fireDodge()
        if not Config.Dodge_On then return end
        local ev = getEvasive(); if not ev or type(ev.Evasive) ~= "function" then return end
        local now = os.clock()
        local cd  = (Config.Dodge_Cooldown and Config.Dodge_Cooldown > 0) and Config.Dodge_Cooldown or 0
        -- OUR spacing (custom cooldown). 0 = defer entirely to the game's internal cooldown.
        if cd > 0 and (now - _lastDodge) < cd then return end
        mapEvasive()
        local char = LocalPlayer.Character
        if Config.Dodge_Everywhere and char then
            pcall(function() char:SetAttribute("OutnumberedEvasiveGrant", true) end)
            for _, a in ipairs(DODGE_STATE_GATES) do
                if char:GetAttribute(a) ~= nil then pcall(function() char:SetAttribute(a, nil) end) end
            end
        end
        -- Custom cooldown OR everywhere → clear the module's runtime cooldown timers so its own
        -- gate can't block our faster cadence (our _lastDodge spacing is the real limiter).
        if (cd > 0 or Config.Dodge_Everywhere) and #_evTimerIdx > 0 then
            for _, i in ipairs(_evTimerIdx) do pcall(debug.setupvalue, ev.Evasive, i, 0) end
        end
        applyDodgeSpeed()
        _lastDodge = now
        pcall(function() ev.Evasive() end)
        if Config.Dodge_Everywhere and char then
            task.defer(function() pcall(function() char:SetAttribute("OutnumberedEvasiveGrant", nil) end) end)
        end
    end

    -- ═══════════════════════════ NO M2 COOLDOWN ═════════════════════════════
    -- Zero the client attempt-lockout upvalues in M2.OnM2Activated (all numeric upvalues here
    -- are the u125/u126/u127 lockout timers + LocalAttemptLockoutSeconds → safe to 0; the lone
    -- boolean is the "ready" flag → true), clear the server M2Cooldown attribute each frame,
    -- and expose a direct fire that skips ALL client gates. Server still caps REAL M2.
    -- Map once (getupvalues is heavy → don't run it every frame). Verified upvalue list of
    -- OnM2Activated: u125/u126/u127 (os.clock lockout deadlines) + LocalAttemptLockoutSeconds
    -- are the ONLY numbers → force 0; u122 is the ready flag (boolean) → force true. Every
    -- other upvalue is a module/table copy and is left alone.
    local _m2NumIdx, _m2BoolIdx, _m2Mapped = {}, {}, false
    local function mapM2Lockouts()
        if _m2Mapped then return true end
        local m2 = getM2(); if not m2 or type(m2.OnM2Activated) ~= "function" then return false end
        if not hasDebugUpvalues() then return false end
        local ok, ups = pcall(debug.getupvalues, m2.OnM2Activated)
        if not (ok and type(ups) == "table") then return false end
        for i, v in pairs(ups) do
            if type(v) == "number" then _m2NumIdx[#_m2NumIdx + 1] = i
            elseif type(v) == "boolean" then _m2BoolIdx[#_m2BoolIdx + 1] = i end
        end
        _m2Mapped = true
        return true
    end
    local function patchM2Lockouts()
        if not mapM2Lockouts() then return false end
        local m2 = getM2(); if not m2 then return false end
        for _, i in ipairs(_m2NumIdx)  do pcall(debug.setupvalue, m2.OnM2Activated, i, 0) end
        for _, i in ipairs(_m2BoolIdx) do pcall(debug.setupvalue, m2.OnM2Activated, i, true) end
        return true
    end
    local function driveNoM2CD()
        if not Config.NoM2CD_On then return end
        patchM2Lockouts()
        local c = LocalPlayer.Character; if not c then return end
        if c:GetAttribute("M2Cooldown") ~= nil then
            pcall(function() c:SetAttribute("M2Cooldown", nil) end)
        end
    end
    local function fireM2Direct()
        local cr = getCombatRemote(); if not cr or type(cr.Fire) ~= "function" then return false end
        pcall(function() cr.Fire("M2", "ServerCheck") end)
        return true
    end

    -- ═══════════════════════ ANTI-RAGDOLL / AUTO-GETUP ══════════════════════
    -- While Ragdoll is active and it's NOT a managed ragdoll (Downed / carried / gripped —
    -- legit states we must not fight), force getup and clear the local Ragdoll attribute.
    -- RagdollServiceClient sustains ragdoll on Heartbeat via the attribute + ChangeState;
    -- we counter it each frame. Best-effort — the server owns authoritative ragdoll.
    local function driveAntiRagdoll()
        if not Config.AntiRagdoll_On then return end
        local char, hum = getParts()
        if not hum then return end
        if char:GetAttribute("Ragdoll") ~= true then return end
        if char:GetAttribute("Downed") == true then return end
        local states = char:FindFirstChild("States")
        if states then
            local bc = states:FindFirstChild("BeingCarried")
            local bg = states:FindFirstChild("BeingGripped")
            if (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil) then return end
        end
        pcall(function() char:SetAttribute("Ragdoll", nil) end)
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
            hum.PlatformStand = false
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown
               or st == Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end

    -- ═════════════════════════ MASTER LOOPS ═════════════════════════════════
    PreStep:Connect(function(dt)
        dt = (typeof(dt) == "number" and dt > 0) and dt or (1 / 60)
        pcall(stepSpeed, dt)
        pcall(stepFly, dt)
    end)
    PostStep:Connect(function()
        driveNoDelay()
        driveInfStamina()   -- hold _staminaSeenPositive=false → endless sprint (no attr writes)
        driveNoM2CD()       -- zero client M2 lockouts + clear M2Cooldown attr
        driveAntiRagdoll()  -- force getup out of non-managed ragdolls
        -- keep sprint desired asserted (game clears it after combat cancels)
        if Config.Sprint_On then
            local s = getSprint()
            if s and rawget(s, "_sprintInputDesired") ~= true then
                pcall(_desireOn, s)
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

    -- ═══════════════════���═══════════ UI ═════════════════════════════════════
    local M = {}

    function M.start()
        Config.Speed_On, Config.Fly_On = false, false
        Config.NS_On, Config.NoDelay_On = false, false
        Config.Sprint_On, Config.Sprint_Bypass = false, false
        -- Warm up the hooks in the background now, so toggling a feature later never
        -- triggers a heap scan on the click (that was the freeze). Inert until a flag flips.
        bootstrapHooks()
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
            Desc = "cframe/velocity speedhack\ndriven by ur move input",
        })
        sSpeed:Dropdown({
            Name = "Method", Options = { "CFrame", "Velocity" },
            Default = Config.Speed_Mode,
            Callback = function(v) Config.Speed_Mode = v; notify("Speed Method", v) end,
        }, ctx.flag("MV_SpeedMode"))
        sSpeed:SubLabel({ Text = "CFrame uhhhh · Velocity is smoother." })
        slider(sSpeed, { Name = "Speed", Flag = "MV_SpeedVal", Default = Config.Speed_Value,
            Min = 16, Max = 150, Suffix = " studs", Callback = function(v) Config.Speed_Value = v end })

        -- ─────────��───── Section 2: Fly (Left) ───────────────
        local sFly = MV:Section({ Side = "Left" })
        sFly:Header({ Name = "Fly" })
        feature(sFly, {
            Title = "Fly", Flag = "MV_Fly",
            get = function() return Config.Fly_On end,
            set = function(v) Config.Fly_On = v end,
            Desc = "space = up, left ctrl = down (no shiftlock clash)\nmobile: jump button = up",
        })
        sFly:Dropdown({
            Name = "Method", Options = { "CFrame", "Velocity" },
            Default = Config.Fly_Mode,
            Callback = function(v) Config.Fly_Mode = v; notify("Fly Method", v) end,
        }, ctx.flag("MV_FlyMode"))
        boolToggle(sFly, "Face Camera", "Fly Face Camera",
            function() return Config.Fly_Face end, function(v) Config.Fly_Face = v end)
        sFly:SubLabel({ Text = "Face Camera makes the body follow your aim." })
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
            Desc = "hooks slowdowns \nno longer force ur WalkSpeed down during actions",
        })
        boolToggle(sNS, "Attack", "NoSlow Attack",
            function() return Config.NS_Attack end, function(v) Config.NS_Attack = v end)
        boolToggle(sNS, "Block", "NoSlow Block",
            function() return Config.NS_Block end, function(v) Config.NS_Block = v end)
        boolToggle(sNS, "Get Hit", "NoSlow GetHit",
            function() return Config.NS_GetHit end, function(v) Config.NS_GetHit = v end)
        slider(sNS, { Name = "Restore Speed", Flag = "MV_NSSpeed", Default = Config.NS_Speed,
            Min = 0, Max = 25, Suffix = " spd", Callback = function(v) Config.NS_Speed = v end })
        sNS:SubLabel({ Text = "Suppresses combat slowdowns · Restore Speed 0 = game default (12)" })

        -- ────────��────── Section 4: Combat exploits (Right) ───────────────
        local sCbt = MV:Section({ Side = "Right" })
        sCbt:Header({ Name = "No Delay" })
        feature(sCbt, {
            Title = "No Delay", Flag = "MV_NoDelay",
            get = function() return Config.NoDelay_On end,
            set = function(v)
                Config.NoDelay_On = v
                if v then
                    bootstrapHooks()  -- non-blocking; installs task.delay hook in background
                    task.spawn(function()
                        for _ = 1, 8 do if _delayHooked then break end task.wait(0.4) end
                        notify("No Delay", _delayHooked and "ON (combat cooldowns collapsed)"
                            or "hookfunction unavailable")
                    end)
                else
                    notify("No Delay", "Disabled")
                end
            end,
            Desc = "removes EVERY combat cooldown/reset wai\nand collapsing the M1 cooldown timers (0.45/1.25/1.55s) to zero",
        })
        boolToggle(sCbt, "Clear Gate Attributes", "NoDelay Attrs",
            function() return Config.NoDelay_Attrs end, function(v) Config.NoDelay_Attrs = v end)
        slider(sCbt, { Name = "Anim Speed (visual)", Flag = "MV_NoDelayAnim", Default = Config.NoDelay_Anim,
            Min = 1, Max = 10, Suffix = "x", Callback = function(v) Config.NoDelay_Anim = v end })
        sCbt:SubLabel({ Text = "ServerSided caps real damage - this removes the client-side wait/feel" })

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
            Desc = "holds sprint on. needs HP ≥ 10.\nturning off truly stops sprinting",
        })
        boolToggle(sSpr, "Bypass Restrictions", "Sprint Bypass",
            function() return Config.Sprint_Bypass end,
            function(v)
                Config.Sprint_Bypass = v
                if v and not combatHooksReady() then
                    notify("Sprint Bypass", "applied?")
                    Config.Sprint_Bypass = false
                end
            end)
        sSpr:SubLabel({ Text = "Keeps sprint speed through combat locks" })

        -- Infinite Sprint lives in the Sprint section (same subsystem)
        feature(sSpr, {
            Title = "Infinite Sprint", Flag = "MV_InfStamina",
            get = function() return Config.InfStamina_On end,
            set = function(v) Config.InfStamina_On = v end,
            Desc = "endless sprint via client stamina-gate flag\nNEVER writes the Stamina attribute (undetectable)",
        })

        -- ─────────────── Section 6: Dodge (Left) ───────────────
        local sDodge = MV:Section({ Side = "Left" })
        sDodge:Header({ Name = "Dodge" })
        feature(sDodge, {
            Title = "Dodge", Flag = "MV_Dodge",
            get = function() return Config.Dodge_On end,
            set = function(v)
                Config.Dodge_On = v
                if v and not getEvasive() then
                    notify("Dodge", "Evasive module not found yet")
                    Config.Dodge_On = false
                elseif v and not hasDebugUpvalues() then
                    notify("Dodge", "needs debug.getupvalues/setupvalue")
                end
            end,
            Desc = "patches the game's Evasive module\nuse the keybind below to dodge on demand",
        })
        boolToggle(sDodge, "Dodge Everywhere", "Dodge Everywhere",
            function() return Config.Dodge_Everywhere end,
            function(v) Config.Dodge_Everywhere = v end)
        sDodge:SubLabel({ Text = "Everywhere = grants dodge in any state (attack/stun/etc). i-frames still server-owned." })
        slider(sDodge, { Name = "Dodge Speed", Flag = "MV_DodgeSpeed", Default = Config.Dodge_Speed,
            Min = 0, Max = 150, Suffix = " studs", Callback = function(v)
                Config.Dodge_Speed = v; applyDodgeSpeed() end })
        slider(sDodge, { Name = "Custom Cooldown", Flag = "MV_DodgeCD", Default = Config.Dodge_Cooldown,
            Min = 0, Max = 5, Precision = 2, Suffix = " s", Callback = function(v)
                Config.Dodge_Cooldown = v end })
        sDodge:SubLabel({ Text = "Speed 0 = game default · Cooldown 0 = game default (our min spacing otherwise)" })
        ctx.keybind(sDodge, {
            Name = "Dodge Now",
            Flag = ctx.flag("MV_DodgeFire_KB"),
            Toggle = function()
                if not Config.Dodge_On then notify("Dodge", "enable Dodge first"); return end
                fireDodge()
            end,
        })

        -- ─────────────── Section 7: No M2 Cooldown (Left) ───────────────
        local sM2 = MV:Section({ Side = "Left" })
        sM2:Header({ Name = "No M2 Cooldown" })
        feature(sM2, {
            Title = "No M2 Cooldown", Flag = "MV_NoM2CD",
            get = function() return Config.NoM2CD_On end,
            set = function(v)
                Config.NoM2CD_On = v
                if v then
                    if not getM2() then
                        notify("No M2 CD", "M2 module not found yet"); Config.NoM2CD_On = false
                    elseif not hasDebugUpvalues() then
                        notify("No M2 CD", "needs debug upvalue API")
                    end
                end
            end,
            Desc = "zeros client M2 attempt-lockouts + clears M2Cooldown attr\nServer still caps REAL M2 damage",
        })
        ctx.keybind(sM2, {
            Name = "M2 Now (direct fire)",
            Flag = ctx.flag("MV_M2Fire_KB"),
            Toggle = function()
                if not fireM2Direct() then notify("M2", "CombatRemoteClient not found") end
            end,
        })
        sM2:SubLabel({ Text = "Direct fire skips ALL client gates (sends M2/ServerCheck straight to server)" })

        -- ─────────────── Section 8: Anti-Ragdoll (Right) ───────────────
        local sAR = MV:Section({ Side = "Right" })
        sAR:Header({ Name = "Anti-Ragdoll" })
        feature(sAR, {
            Title = "Anti-Ragdoll", Flag = "MV_AntiRagdoll",
            get = function() return Config.AntiRagdoll_On end,
            set = function(v) Config.AntiRagdoll_On = v end,
            Desc = "auto-getup out of ragdolls each frame\nskips managed ones (downed / carried / gripped)",
        })
        sAR:SubLabel({ Text = "Best-effort: server owns authoritative ragdoll state" })

        uiReady = true
    end

    return M
end
