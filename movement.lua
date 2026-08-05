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
    -- Luraph macro PRELUDE — string keys only (bare `function LPH_*` aborts Luraph).
    -- Per-frame Connects, __namecall and combat hooks must stay native after obfuscation.
    do
        local _E = (getgenv and getgenv()) or _G
        if not _E["LPH_NO_VIRTUALIZE"] then
            local id, nop = function(f) return f end, function() end
            _E["LPH_NO_VIRTUALIZE"] = id
            _E["LPH_JIT_MAX"] = id
            _E["LPH_JIT"] = id
            _E["LPH_ENCFUNC"] = id
            _E["LPH_NO_UPVALUES"] = id
            _E["LPH_ENCSTR"] = id
            _E["LPH_ENCNUM"] = id
            _E["LPH_SKIP"] = id
            _E["LPH_CRASH"] = nop
        end
    end

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

        -- NoClip — CanCollide=false on our own parts each PreSimulation frame (before physics),
        -- so we phase through walls/floors. Carry-aware: when we're carrying/gripping an enemy
        -- (they're welded to us), their parts collide with the wall and would block/rubberband us,
        -- so we un-collide the carried victim's parts too → pass through even with someone on our
        -- shoulders. Restores original CanCollide on disable.
        NoClip_On    = false,
        NoClip_Carry = true,      -- also un-collide an enemy we're carrying/gripping

        -- No Slowdown (master + per-type) — hooks MovementServiceUtils.SetSpeed
        NS_On     = false,
        NS_Attack = true,         -- M1/M2/windup movement lock
        NS_Block  = true,         -- Blocking / GuardBroken
        NS_GetHit = true,         -- CantAnything / Stunned (lock from taking a hit)
        NS_Speed  = 0,            -- restore target used ONLY during those states: 0 = game base (12/25), 1..25 = exact

        -- No Delay (direct hookfunction(task.delay) → collapse combat cooldown/reset waits)
        -- [V112] Ключи NoDelay_Attrs и NoDelay_Anim УДАЛЕНЫ. Первый чистил атрибуты,
        -- которых tryM1 не читает вообще (isCombatInputBlocked проверяет другой набор),
        -- второй был косметическим костылём под неработавший фикс. Лишние настройки =
        -- признак ненайденной причины; причина найдена, настройки не нужны.
        NoDelay_On    = false,

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

        -- Dodge tweaks — applied to the game Evasive module (config field + module upvalue), so
        -- the player's OWN natural dodges use these values. Defaults = the real in-game numbers,
        -- so leaving the sliders alone behaves EXACTLY like vanilla (we only write when changed).
        Dodge_On         = false,   -- master: resolve Evasive module + apply patches
        Dodge_Everywhere = false,   -- dodge in ANY state (hook hides the action-lock attributes)
        Dodge_Speed      = 30,      -- game default DashSpeed (studs/sec)
        Dodge_Cooldown   = 1.5,     -- game default Evasive.Cooldown (seconds)

        -- Anti-Ragdoll / Auto-getup — force getup while Ragdoll is active and NOT a managed
        -- ragdoll (Downed / carried / dead). Best-effort: server owns the real ragdoll state.
        AntiRagdoll_On = false,

        -- [V112] No Blur — глушим ТОЛЬКО боевой/эффектный блюр, подменяя поле
        -- ScreenEffects.SetBlur. Блюр меню/интерфейса (Menu, PlayerList, Profile, Stats,
        -- ServerList, Book, Rules, Reroll, RhythmResults, PanelKit) НЕ трогаем — он часть
        -- нормального UI, и его снятие сделало бы меню визуально сломанным.
        NoBlur_On = false,

        -- [V112] Respawn / Auto Respawn. Порог HP в ПРОЦЕНТАХ от MaxHealth: 0 = только
        -- по факту смерти/Downed, >0 = респавн при падении HP ниже порога.
        AutoRespawn_On   = false,
        AutoRespawn_HP   = 0,
    }

    -- ═════════════════════════ Character helpers ═════════════════════�����══════
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

    -- ══════════════════������ IMMOBILE-STATE DETECTOR (NoSlowdown fix) ══════════�����═
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
    -- The M2 wrestling GRAB (M2.lua applyWrestlingGrabNoCollision) welds you to the attacker and
    -- creates NoCollisionConstraints named "WrestlingM2GrabNoCollide" across your parts, then the
    -- server positions you — you are genuinely locked WITHOUT Anchored / the Grappling attribute /
    -- a named Carry/Grip weld. That's the case the user hit: NS raised WalkSpeed but the server
    -- held them in place → rubberband ("на месте для сервера"). This constraint is the reliable
    -- marker for it. Scanning descendants is a bit heavy, so cache the whole isImmobile result for
    -- one frame (both stepSpeed and the SetSpeed hook call it, sometimes many times per frame).
    local _immCacheT, _immCacheV = 0, false

    -- [V112] PERF: детект grab-констрейнта переведён со СКАНИРОВАНИЯ на СОБЫТИЯ.
    -- ПОЧЕМУ ПРЕЖНИЙ КОД БЫЛ ТЯЖЁЛЫМ: hasGrabConstraint звал char:GetDescendants(), а это
    -- аллокация НОВОЙ таблицы со ВСЕМИ потомками персонажа (у R15 с аксессуарами — сотни
    -- инстансов) плюс :IsA на каждом. Кэш на 0.05с прятал частоту вызовов, но всё равно
    -- давал ~20 полных обходов в секунду ПОСТОЯННО, даже когда нас никто не хватал. Это
    -- ровно тот тип работы, что копит мусор и даёт просадки со временем.
    -- КАК ТЕПЕРЬ: держим счётчик живых констрейнтов и правим его по DescendantAdded /
    -- DescendantRemoving. Проверка становится сравнением числа с нулём — то есть бесплатной.
    local _grabCount, _grabConns = 0, {}
    local function isGrabConstraint(d)
        return d:IsA("NoCollisionConstraint") and d.Name == "WrestlingM2GrabNoCollide"
    end
    local function bindGrabWatch(char)
        for i = #_grabConns, 1, -1 do
            pcall(function() _grabConns[i]:Disconnect() end)
            _grabConns[i] = nil
        end
        _grabCount = 0
        if not char then return end
        -- Стартовый пересчёт делаем ОДИН раз на персонажа (а не каждый кадр): констрейнт
        -- мог уже существовать до того, как мы подписались.
        for _, d in ipairs(char:GetDescendants()) do
            if isGrabConstraint(d) then _grabCount = _grabCount + 1 end
        end
        _grabConns[#_grabConns + 1] = char.DescendantAdded:Connect(function(d)
            if isGrabConstraint(d) then _grabCount = _grabCount + 1 end
        end)
        _grabConns[#_grabConns + 1] = char.DescendantRemoving:Connect(function(d)
            if isGrabConstraint(d) then
                _grabCount = _grabCount - 1
                if _grabCount < 0 then _grabCount = 0 end
            end
        end)
    end
    local function hasGrabConstraint()
        return _grabCount > 0
    end
    local function isImmobile(char, root)
        if not Config.NS_RespectImmobile then return false end
        local now = os.clock()
        if (now - _immCacheT) < 0.05 then return _immCacheV end
        _immCacheT = now
        char = char or getChar(); if not char then _immCacheV = false; return false end
        if not root then
            root = char:FindFirstChild("HumanoidRootPart")
        end
        local result = false
        if root and root.Anchored then
            result = true
        else
            for _, a in ipairs(IMMOBILE_ATTRS) do
                if char:GetAttribute(a) == true then result = true; break end
            end
            if not result then
                local states = char:FindFirstChild("States")
                if states then
                    local bc = states:FindFirstChild("BeingCarried")
                    local bg = states:FindFirstChild("BeingGripped")
                    if (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil) then result = true end
                end
            end
            if not result and root and (root:FindFirstChild("CarryWeld") or root:FindFirstChild("GripWeld")) then
                result = true
            end
            -- being wrestled/grabbed (server-positioned, no anchor/attr) → the reported bug
            if not result and hasGrabConstraint() then result = true end
        end
        _immCacheV = result
        return result
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

    -- ═════════════�����═════════════════ SPEED ══════════════════════════════════
    -- CFrame  → shift the root by moveVec*speed*dt (positional, beats the WalkSpeed
    --           anti-cheat since WalkSpeed itself is untouched).
    -- Velocity→ set horizontal AssemblyLinearVelocity, keep gravity on Y.
    -- [LURAPH] per-frame speed step — kept native under Luraph.
    local stepSpeed = LPH_NO_VIRTUALIZE(function(dt)
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
    end)

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

    -- [LURAPH] per-frame fly step — kept native under Luraph.
    local stepFly = LPH_NO_VIRTUALIZE(function(dt)
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
    end)

    -- ═══════════════════════════════ NOCLIP ═════════════════════════════════
    -- Standard client noclip: force CanCollide=false on our parts every PreSimulation frame
    -- (before physics resolves), so the world can't stop us. We remember each part's original
    -- CanCollide so disabling NoClip restores it exactly (HRP is normally false, Torso/Head true).
    --
    -- [V130] PERF: the old version called model:GetDescendants() EVERY FRAME (allocates a fresh
    -- table + walks the whole instance tree, ~20 parts) → constant GC churn = stutter. Now we CACHE
    -- the BasePart list per model and only rebuild it on a throttle (parts almost never change mid-
    -- life). Per frame we just walk a plain array and write CanCollide=false (cheap, no allocation).
    local _noclipTouched = {}     -- [BasePart] = originalCanCollide (for restore)
    local _partCache     = {}     -- [Model]   = { parts = {BasePart...}, t = lastScan }
    local PART_RESCAN    = 1.0     -- seconds between descendant rescans per model
    local function collideParts(model)
        local entry = _partCache[model]
        local now = os.clock()
        if not entry or (now - entry.t) >= PART_RESCAN then
            local parts = entry and entry.parts or {}
            table.clear(parts)
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then parts[#parts + 1] = d end
            end
            entry = { parts = parts, t = now }
            _partCache[model] = entry
        end
        return entry.parts
    end
    local function unCollide(model)
        if not model then return end
        local parts = collideParts(model)
        for i = 1, #parts do
            local d = parts[i]
            if d.Parent then
                if _noclipTouched[d] == nil then _noclipTouched[d] = d.CanCollide end
                if d.CanCollide then d.CanCollide = false end
            end
        end
    end
    -- [PERF] persistent wrapper: the pcall below allocated a closure PER PART (~10 per call),
    -- and restoreCollide fires on every noclip toggle AND every ragdoll start/end — a burst of
    -- allocations at exactly the worst moment for frame time.
    local function _setCollide(p, v) p.CanCollide = v end
    local function restoreCollide()
        for part, orig in pairs(_noclipTouched) do
            if typeof(part) == "Instance" and part.Parent then
                pcall(_setCollide, part, orig)
            end
        end
        table.clear(_noclipTouched)
        table.clear(_partCache)
    end

    -- Find an enemy character we are CARRYING/GRIPPING (they're welded to us). The carry/grip
    -- weld lives under the VICTIM's HRP (CarryWeld/GripWeld — RagdollServiceClient.isCarriedOrGripped),
    -- and one of its Part0/Part1 belongs to OUR character. Cached ~0.25s (carry state rarely
    -- flips) so we don't scan every player every frame.
    --
    -- Detection (verified against KnockedService): a downed victim being carried/gripped has an
    -- ObjectValue States.BeingCarried / States.BeingGripped whose .Value is set (line 80/86 confirm
    -- IsA("ObjectValue")). We match the victim to US two ways, name-independent so it survives
    -- whatever the server names the weld:
    --   1) the ObjectValue .Value references our character/HRP/player (authoritative link), OR
    --   2) ANY weld/Motor6D under the victim connects Part0/Part1 to our character (physical link).
    -- The old code only checked a hard-coded "CarryWeld"/"GripWeld" name under HRP → it missed the
    -- real weld and Carry-Aware never fired. This is the fix.
    local function refsMe(inst, myChar)
        if not inst then return false end
        if inst == myChar or inst == LocalPlayer then return true end
        if typeof(inst) == "Instance" then
            if inst:IsA("Player") then return inst.Character == myChar end
            local ok, desc = pcall(function() return inst:IsDescendantOf(myChar) end)
            if ok and desc then return true end
        end
        return false
    end
    local function weldLinksMe(char, myChar)
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Motor6D") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 and p0:IsDescendantOf(myChar)) or (p1 and p1:IsDescendantOf(myChar)) then
                    return true
                end
            end
        end
        return false
    end
    local _carryCacheT, _carryVictim = 0, nil
    local function getCarriedVictim(myChar)
        local now = os.clock()
        if (now - _carryCacheT) < 0.25 then
            return (_carryVictim and _carryVictim.Parent) and _carryVictim or nil
        end
        _carryCacheT = now
        _carryVictim = nil
        for _, pl in ipairs(Players:GetPlayers()) do
            local oc = pl.Character
            if oc and oc ~= myChar then
                local states = oc:FindFirstChild("States")
                local bc = states and states:FindFirstChild("BeingCarried")
                local bg = states and states:FindFirstChild("BeingGripped")
                local carried = (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil)
                if carried then
                    -- carried by SOMEONE; is it me? (authoritative value ref OR physical weld)
                    if refsMe(bc and bc.Value, myChar) or refsMe(bg and bg.Value, myChar)
                       or weldLinksMe(oc, myChar) then
                        _carryVictim = oc
                        break
                    end
                end
            end
        end
        return _carryVictim
    end

    -- Are WE currently ragdolled / downed? While ragdolled the physics ragdoll needs real
    -- collisions (otherwise you clip through the floor and the game's get-up can break/desync),
    -- so NoClip must PAUSE for the whole ragdoll and auto-resume once it clears.
    -- Robust ragdoll/knock detection. The Ragdoll/Downed ATTRIBUTES are correct (that's what the
    -- game reads everywhere), BUT they get set a frame or two AFTER the physics ragdoll engages —
    -- and in that gap our per-frame CanCollide=false makes the loose body fall through the floor.
    -- So we ALSO watch signals that flip at the very start of the ragdoll:
    --   • Humanoid.PlatformStand == true  (game uses this as a ragdoll signal — SmoothShiftLock:792)
    --   • Humanoid state Physics / FallingDown / Ragdoll / GettingUp / Seated
    --   • RagdollLaunchApplied attribute (the cinematic knockback fling)
    local RAGDOLL_STATES = {
        [Enum.HumanoidStateType.Physics]     = true,
        [Enum.HumanoidStateType.FallingDown] = true,
        [Enum.HumanoidStateType.Ragdoll]     = true,
        [Enum.HumanoidStateType.GettingUp]   = true,
        [Enum.HumanoidStateType.Seated]      = true,
    }
    local function _humGetState(h) return h:GetState() end
    local function selfRagdolled(char)
        if char:GetAttribute("Ragdoll") == true or char:GetAttribute("Downed") == true
           or char:GetAttribute("RagdollLaunchApplied") == true then
            return true
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            if hum.PlatformStand == true then return true end
            -- [PERF] pcall with an inline closure allocated a fresh closure EVERY PreSimulation
            -- frame while noclip was on. Persistent wrapper → zero allocation.
            local ok, st = pcall(_humGetState, hum)
            if ok and RAGDOLL_STATES[st] then return true end
        end
        return false
    end

    local RAGDOLL_GRACE = 0.5     -- keep collisions this long AFTER ragdoll clears (let get-up finish)
    local _noclipActive, _ragdollClearedAt = false, 0
    -- [LURAPH] per-frame noclip step — kept native under Luraph.
    local stepNoClip = LPH_NO_VIRTUALIZE(function()
        if not Config.NoClip_On then
            if _noclipActive then restoreCollide(); _noclipActive = false end
            return
        end
        local char = getChar(); if not char then return end
        -- Ragdoll pause: restore real collisions and wait until we're fully out of ragdoll +
        -- a short grace window (so the get-up animation settles on the floor, not through it).
        if selfRagdolled(char) then
            _ragdollClearedAt = os.clock() + RAGDOLL_GRACE
            if _noclipActive then restoreCollide(); _noclipActive = false end
            return
        end
        if os.clock() < _ragdollClearedAt then
            if _noclipActive then restoreCollide(); _noclipActive = false end
            return
        end
        _noclipActive = true
        unCollide(char)
        -- carry-aware: also phase the enemy we're carrying so their body can't wedge on the wall
        if Config.NoClip_Carry then
            local victim = getCarriedVictim(char)
            if victim then unCollide(victim) end
        end
    end)

    -- ══════════��════════ HOOK-BASED FEATURES ════════��════���════════════��═════
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
        orig = hookfunction(fn, LPH_NO_VIRTUALIZE(function(inst, speed, ...)
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
        end))
        setSpeedHooked = true
        return true
    end

    -- ═══════════════════════════════════════════════════════════════════════════
    -- COMBAT MODULE RESOLVERS — require the game's OWN cached modules → LIVE upvalues
    -- ═══════════════════════════════════════════════════════════════════════════
    -- require() on a ModuleScript the game already required returns the SAME cached table,
    -- so Evasive.Evasive / M1.OnM1Activated are the live functions and debug.setupvalue
    -- patches the very upvalues the combat system reads. No filtergc heap sweep needed.
    -- [V112] ПЕРЕНЕСЕНО СЮДА (было ниже, после Dodge). Причина строго техническая:
    -- mapNoDelay/mapEvasive вызывают tryRequire и hasDebugUpvalues, а Lua связывает
    -- local-функцию по ЛЕКСИЧЕСКОЙ позиции. Пока объявление стояло ниже, замыкание
    -- захватывало глобальный nil → вызов падал в pcall и фича «просто не работала».
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
    local _evasiveMod, _combatConfig
    local function getEvasive()
        if _evasiveMod == nil then
            _evasiveMod = tryRequire({ "CombatSystemClient", "Combat", "Base", "Evasive" }) or false
        end
        return _evasiveMod or nil
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
            and type(debug.getupvalue) == "function"
    end

    -- ═════════════════════════��═�����═══════════════════════════════════════════════
    -- NO DELAY — [V112] ПЕРЕПИСАНО С НУЛЯ: патч upvalue'ов M1 вместо хука task.delay
    -- ═══════════════════════════════════════════════════════════════════════════
    -- ПОЧЕМУ ПРЕЖНИЙ КОД БЫЛ НЕВЕРЕН. Три независимые ошибки, каждая подтверждена дампом
    -- (M1_ModuleScript.lua + CombatConfig). Прежний подход фильтровал задержки по их
    -- ЧИСЛОВОМУ ЗНАЧЕНИЮ — и именно это его и погубило:
    --
    -- 1) ОСНОВНЫЕ ЗАДЕРЖКИ — ЭТО ВООБЩЕ НЕ task.delay, поэтому хук их не видел.
    --    Гейт свинга в tryM1 (M1.lua:356 и 362) выглядит так:
    --        if os.clock() < u32 then u29 = false; return false end   -- lockout после парирования
    --        if os.clock() < u33 then u29 = false; return false end   -- lockout после блока
    --    u32/u33 — это ДЕДЛАЙНЫ-ЧИСЛА, их ставят напрямую:
    --        M1.lua:656-657  u32 = math.max(u32, os.clock() + LocalParryAttackLockoutSeconds)
    --        M1.lua:629-630  u33 = math.max(u33, os.clock() + LocalBlockAttackLockoutSeconds)
    --        M1.lua:645-646  u33 = math.max(u33, os.clock() + LocalBlockAttackLockoutSeconds)
    --    (оба Lockout = 0.15с, CombatConfig:120-121). Ни одного task.delay здесь нет →
    --    хук ФИЗИЧЕСКИ не мог их снять. Это и есть «микро задержки не убираются вовсе».
    --
    -- 2) ПЕРЕЗАРЯДКА ПОСЛЕ КОМБО НЕ СНИМАЛАСЬ ИЗ-ЗА АРИФМЕТИКИ ФИЛЬТРА.
    --    Игра пишет task.delay(FinisherCooldown/spd, …), FinisherCooldown = 1.25
    --    (CombatConfig:119). Фильтр сравнивал значение с {0.45,1.25,1.55}, допуск 0.12.
    --    При spd = 1.2 → 1.25/1.2 = 1.0417, а |1.0417 − 1.25| = 0.208 > 0.12 →
    --    задержка НЕ распознавалась и оставалась целой. Ровно симптом «основная задержка
    --    после окончания комбо (перезарядка) не убирается».
    --
    -- 3) ЭФФЕКТ ПАРИРОВАНИЯ ЛОМАЛ САМ ХУК. В v1.PerfectBlocked затухание FX сделано так:
    --        M1.lua:699  task.delay(0.44999999999999996, function() … end)
    --        M1.lua:713  task.delay(0.44999999999999996, function() … end)
    --    0.45 — это AttackDuration (CombatConfig:118), то есть РОВНО одно из значений
    --    фильтра, отличие 0.0. Хук схлопывал его в 0 → искры/PerfectBlockFX умирали в том
    --    же кадре, в котором родились. Отсюда «��ффе��т парирования какой-то сломанный».
    --
    -- КОРЕНЬ ВСЕГО: по числовому значению кулдаун боя и таймер визуального эффекта
    -- НЕОТЛИЧИМЫ (оба 0.45). Значит фильтровать по значению нельзя в принципе.
    -- Поэтому task.delay больше НЕ ХУКАЕТСЯ ВООБЩЕ — FX остаются целыми сами собой,
    -- и заодно исчезает глобальный хук на каждом task.delay игры (это ещё и лаги).
    --
    -- КАК СДЕЛАНО ТЕПЕРЬ: правим ровно те три переменные, которые tryM1 читает как гейт.
    -- Список upvalue'ов tryM1 (M1.lua:322) в точном порядке даёт индексы:
    --        [4] = u21  (boolean «можно бить»)   [5] = u32   [6] = u33
    --   u21 = true → снимает и кулдаун свинга, и перезарядку после комбо: её ставит
    --                scheduleM1SwingTimers как `u21 = false` + task.delay(…, ()->u21=true),
    --                так что открытый гейт делает саму задержку бессмысленной.
    --   u32 = 0    → снимает 0.15с lockout после парирования.
    --   u33 = 0    → снимает 0.15с lockout после блока.
    -- Сама tryM1 достаётся честно и без filtergc: у v1.OnM1Activated (M1.lua:494) ровно
    -- ОДИН upvalue — это и есть tryM1.
    -- Честный предел: серверный рейт M1 по-прежнему ограничивает РЕАЛЬНЫЙ урон; мы
    -- убираем только клиентский стопор/ощущение задержки.

    -- [V112] Резолвер M1 → tryM1 → индексы гейтов. Выполняется ОДИН раз (ленивая карта).
    local _tryM1 = nil
    local _ndGateIdx, _ndParryIdx, _ndBlockIdx = nil, nil, nil
    -- Персистентные обёртки для pcall — БЕЗ аллокации замыкания на кадр.
    local function _getUp(fn, i) return debug.getupvalue(fn, i) end
    local function _setUp(fn, i, v) return debug.setupvalue(fn, i, v) end

    local function mapNoDelay()
        if _tryM1 then return true end
        if not hasDebugUpvalues() then return false end
        local m1 = tryRequire({ "CombatSystemClient", "Combat", "Base", "M1" })
        if not m1 or type(m1.OnM1Activated) ~= "function" then return false end
        -- OnM1Activated замыкает ровно одну функцию — tryM1. Ищем по типу, а не по индексу,
        -- чтобы правка игрой порядка upvalue'ов ничего не сломала.
        local ok, ups = pcall(debug.getupvalues, m1.OnM1Activated)
        if not (ok and type(ups) == "table") then return false end
        local fn
        for _, v in pairs(ups) do
            if type(v) == "function" then fn = v; break end
        end
        if not fn then return false end
        -- Проверяем ОЖИДАЕМУЮ подпись из дампа: [4] boolean, [5] и [6] числа.
        -- Если совпало — берём эти индексы. Если игра сдвинула upvalue'ы, ищем ту же
        -- подпись сканированием (первый boolean + два числа сразу за ним).
        local okS, g = pcall(_getUp, fn, 4)
        local okP, p = pcall(_getUp, fn, 5)
        local okB, b = pcall(_getUp, fn, 6)
        if okS and okP and okB and type(g) == "boolean" and type(p) == "number" and type(b) == "number" then
            _ndGateIdx, _ndParryIdx, _ndBlockIdx = 4, 5, 6
        else
            local info = select(2, pcall(debug.getinfo, fn))
            local n = (type(info) == "table" and tonumber(info.nups)) or 32
            for i = 1, n - 2 do
                local o1, v1u = pcall(_getUp, fn, i)
                local o2, v2u = pcall(_getUp, fn, i + 1)
                local o3, v3u = pcall(_getUp, fn, i + 2)
                if o1 and o2 and o3 and type(v1u) == "boolean"
                   and type(v2u) == "number" and type(v3u) == "number" then
                    _ndGateIdx, _ndParryIdx, _ndBlockIdx = i, i + 1, i + 2
                    break
                end
            end
        end
        if not _ndGateIdx then return false end
        _tryM1 = fn
        return true
    end

    -- [V112] УДАЛЕНО ЦЕЛИКОМ: extractId / buildM1Ids / onAnimPlayed / hookAnimator,
    -- хук task.delay (installNoDelayHook) и список GATE_ATTRS.
    -- ПОЧЕМУ ПРЕЖНИЙ КОД БЫЛ НЕВЕРЕН И ПОЧЕМУ ОН ЖЕ ДАВАЛ ЛАГИ:
    --
    --   • Хук task.delay — разобран выше: фильтр по числовому значению не мог отличить
    --     кулдаун боя от таймера визуального эффекта (у обоих 0.45), поэтому одновременно
    --     ЛОМАЛ эффект парирования (M1.lua:699/713) и НЕ ЛОВИЛ перезарядку после комбо
    --     (1.25/spd не попадала в допуск). Плюс это глобальный хук: он выполнялся на
    --     КАЖДЫЙ task.delay всей игры, а не только на боевые.
    --
    --   • Слайдер «Anim Speed» был КОСТЫЛЁМ под неработающий No Delay — он ускорял
    --     анимацию, чтобы быстрая серия хотя бы «выглядела» быстрой. Он же был одним из
    --     источников накопительных лагов: на КАЖДЫЙ свинг запускался task.spawn с циклом
    --     `while os.clock() - t0 < 0.3 do … task.wait() end` — это ~18 итераций по два
    --     pcall каждая, и при быстрых комбо несколько таких циклов жили одновременно.
    --     Теперь гейт открыт по-настоящему, анимация идёт со своей скоростью, костыль и
    --     его настройка удалены (лишняя настройка = признак ненайденной причины).
    --
    --   • GATE_ATTRS чистился КАЖДЫЙ Heartbeat — и это была работа полностью впустую.
    --     Атрибуты tryM1 читает ровно одним вызовом isCombatInputBlocked (M1.lua:131-133),
    --     а она проверяет только Downed / Ragdoll / Stunned / GrappleWinnerStun /
    --     Grappling / CantAnything. Ни M1Cooldown, ни ComboCooldown, ни Attacking, ни
    --     Casting, ни CannotAttack там не упоминаются ВООБЩЕ — 5 из 8 атрибутов не влияли
    --     ни на что. Оставшиеся — это СОСТОЯНИЯ (лежишь/схвачен), а не задержки, поэтому
    --     к No Delay они не относятся. Настройка «Clear Gate Attributes» удалена.

    -- [V112] Единственный драйвер No Delay: держим три гейта tryM1 открытыми.
    -- ═════════ [V113] ПОЧЕМУ НЕ УБИРАЛАСЬ ЗАДЕРЖКА ПОСЛЕ КОМБО ═════════
    -- Я УДАЛИЛ НУЖНЫЙ КОД, опираясь на неверное утверждение. В V112 я написал, что
    -- «tryM1 не читает эти атрибуты вовсе», и выбросил очистку атрибутов. Дамп говорит
    -- обратное: tryM1 проверяет их подряд и выходит по каждому (M1.lua:397-436):
    --        M1Cooldown, M1, CombatAttacking, ParryAttackLockout, BlockAttackLockout,
    --        Blocking, Greenzone, RpCombatLocked, CantAnything, GuardBroken, M2, PendingM2
    -- Ни одного SetAttribute для них в клиентском дампе нет — их ставит СЕРВЕР. То есть
    -- задержка после последнего удара комбо приходит ДВУМЯ независимыми путями:
    --   1) клиентский гейт u21: scheduleM1SwingTimers (M1.lua:295-306) делает u21 = false и
    --      task.delay(FinisherCooldown / spd) → u21 = true. FinisherCooldown = 1.25
    --      (CombatConfig:120) против AttackDuration = 0.45 — это и есть «долгая» задержка
    --      именно после 4-го удара (`p47 == 4 and FinisherCooldown or AttackDuration`).
    --   2) серверный атрибут M1Cooldown (и M1 / CombatAttacking).
    -- V112 закрывал только путь (1), поэтому путь (2) ��родол����ал д��рж����ть комбо. Симптом
    -- «после последнего удара долгая задержка» описывал ровно это.
    --
    -- ЧТО ЧИСТИМ И ЧЕГО НЕ КАСАЕМСЯ. Только кулдауны и локауты атаки. Осознанно НЕ трогаем:
    --   Blocking            — снятие сломало бы собственный блок;
    --   Greenzone/RpCombatLocked — это безопасные зоны, ими занимается Dodge Everywhere;
    --   CantAnything/GuardBroken/M2/PendingM2 — это состояния стана и M2, а не задержка;
    --   Equip               — tryM1 ТРЕБУЕТ его истинным, снятие запретило бы удар вообще.
    -- Отдельного тумблера для этого нет: это не выбор, а часть работы No Delay.
    local M1_GATE_ATTRS = {
        "M1Cooldown", "M1", "CombatAttacking", "ParryAttackLockout", "BlockAttackLockout",
    }
    local function _clearAttr(c, k) c:SetAttribute(k, nil) end
    local function clearM1GateAttrs()
        local c = LocalPlayer.Character
        if not c then return end
        for i = 1, #M1_GATE_ATTRS do
            local k = M1_GATE_ATTRS[i]
            -- Пишем только если атрибут реально стоит: запись в nil уже-пустого атрибута
            -- бессмысленна, а лишние SetAttribute на кадр — та самая мелкая нагрузка.
            if c:GetAttribute(k) ~= nil then pcall(_clearAttr, c, k) end
        end
    end

    -- Стоимость кадра: три чтения upvalue; запись — только если значение реально другое.
    local _ndNextTry = 0
    local function driveNoDelay()
        if not Config.NoDelay_On then return end
        -- [V113] Чистим атрибуты ПЕРВЫМ делом: они серверные и не зависят от того, удалось ли
        -- разрешить upvalue'ы M1. Ниже стоит ранний return по неудачному резолву — если
        -- вызывать очистку после него, серверный кулдаун не снимался бы вообще, пока модуль
        -- M1 не подгрузится.
        clearM1GateAttrs()
        if not _tryM1 then
            -- Резолв может не удаться (модуль ещё не загружен). Без этого бэкоффа
            -- tryRequire дёргал бы FindFirstChild+require КАЖДЫЙ кадр — свой источник лагов.
            local nowc = os.clock()
            if nowc < _ndNextTry then return end
            _ndNextTry = nowc + 1.0
            if not mapNoDelay() then return end
        end
        local okG, g = pcall(_getUp, _tryM1, _ndGateIdx)
        if okG and g ~= true then pcall(_setUp, _tryM1, _ndGateIdx, true) end
        local okP, p = pcall(_getUp, _tryM1, _ndParryIdx)
        if okP and type(p) == "number" and p ~= 0 then pcall(_setUp, _tryM1, _ndParryIdx, 0) end
        local okB, b = pcall(_getUp, _tryM1, _ndBlockIdx)
        if okB and type(b) == "number" and b ~= 0 then pcall(_setUp, _tryM1, _ndBlockIdx, 0) end
    end
    -- [V111] PERF: персистентная fn для pcall БЕЗ аллокации замыкания. clearGateAttrs к��утится
    -- КАЖДЫЙ Heartbeat при No Delay → прежний `pcall(function() ... end)` на каждый очищаемый
    -- атрибут = до 8 closure/кадр = лишний GC. Персистентная fn не аллоциру��т ничего.
    -- [V112] Комментарий [V111] выше относился к clearGateAttrs — она удалена (разбор
    -- причины см. выше), поэтому её персистентная обёртка _clearAttr тоже больше не нужна.
    -- Комментарий оставлен как история решений.

    -- [V112] Вместо installAnimHook — простой резолв карты upvalue'ов No Delay.
    -- Хуков здесь больше НЕТ: ни task.delay, ни Animator-коннекта. Респавн ничего не
    -- ломает — upvalue'ы принадлежат МОДУЛЮ M1 (он живёт всю сессию), а не персонажу,
    -- поэтому переподключение после CharacterAdded не требуется.
    local noDelayMapped = false
    local function installNoDelay()
        if noDelayMapped then return true end
        noDelayMapped = mapNoDelay()
        return noDelayMapped
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
            installNoDelay()   -- [V112] было installAnimHook (хук task.delay + Animator)
        end)
    end
    local function combatHooksReady()
        bootstrapHooks()
        return type(hookfunction) == "function"
    end

    -- ══════════════════════════ AUTO SPRINT ══════════��══════════════════════
    local sprintSingleton
    -- [V97/PERF] RATE-LIMITED MISS. filterOne stops at the first HIT, but a MISS still walks the
    -- whole heap — and getSprint is called from THREE per-frame drivers (InfStamina, the sprint
    -- re-assert, setSprint). Before the singleton exists (menu, respawn, or a game that simply has
    -- no sprint controller) that meant a full heap sweep EVERY FRAME, forever. That is the movement
    -- stutter. Now a failed lookup backs off for a second, so the miss path costs one compare.
    local _sprintNextTry = 0
    local function getSprint()
        if sprintSingleton then return sprintSingleton end
        if type(filtergc) ~= "function" then return nil end
        local nowc = os.clock()
        if nowc < _sprintNextTry then return nil end
        _sprintNextTry = nowc + 1.0
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

    -- [V112] Прежний driveNoDelay вызывал clearGateAttrs() — удалён вместе с ним, см.
    -- разбор в блоке NO DELAY: тот список атрибутов tryM1 вообще не читает.
    -- Резолверы боевых модулей ПЕРЕНЕСЕНЫ ВЫШЕ (перед блоком NO DELAY): mapNoDelay
    -- использует tryRequire/hasDebugUpvalues, а в Lua local-функция обязана быть
    -- объявлена ЛЕКСИЧЕСКИ раньше места использования — иначе замыкание захватило бы
    -- глобальный nil вместо нашей функции, и No Delay молча не работал бы.

    -- ══════════════════ INFINITE SPRINT (stamina, client field) ═════════════
    -- The game only STOPS sprint on Stamina<=0 when the sprint singleton's
    -- _staminaSeenPositive is TRUE (StartSprint gate @ line 2072 + render loop @ 2170).
    -- Held at false → sprint never dies. Written on Heartbeat (after the game's RenderStep,
    -- which only re-latches it true when Stamina>0), so on a drained frame it stays false.
    -- We NEVER touch the Stamina ATTRIBUTE (server-authoritative → detectable). Pure client.
    local function _clearStaminaSeen(s) s._staminaSeenPositive = false end
    local function driveInfStamina()
        if not Config.InfStamina_On then return end
        local s = getSprint(); if not s then return end
        if rawget(s, "_staminaSeenPositive") ~= false then
            pcall(_clearStaminaSeen, s)   -- reused fn ref → no per-frame closure allocation
        end
    end

    -- Cached local character — updated on CharacterAdded. Used by the combat __namecall hook so
    -- the hot path is a cheap pointer compare instead of an Instance property index per call.
    local _myChar = LocalPlayer.Character

    -- ══════════════════════════ DODGE TWEAKS ═══════════════════════════════
    -- [V112] БАГ «СКОРОСТЬ DODGE РАСТЁТ ДАЖЕ НА ДЕФОЛТНОМ ЗНАЧЕНИИ» — НАЙДЕН И ИСПРАВЛЕН.
    --
    -- КОРЕНЬ. Игра сама умножает скорость дэша, когда активен grant. Evasive.lua:693-697:
    --        if u51 then  v63 = DashSpeed * OutnumberedDashSpeedMultiplier
    --        else         v63 = DashSpeed
    -- и то же для длительности (Evasive.lua:701-705, OutnumberedDashDurationMultiplier).
    -- Множители в CombatConfig: OutnumberedDashSpeedMultiplier = 1.5,
    -- OutnumberedDashDurationMultiplier = 1.2. А u51 взводится ровно нашим же тумблером
    -- Dodge Everywhere: driveDodge ставит атрибут OutnumberedEvasiveGrant = true, из него
    -- получается u51 (Evasive.lua:529-531). Итог: слайдер стоит на вани*льных 30, а дэш
    -- летит 30 × 1.5 = 45 studs/s и длится на 20% дольше. Никакой «утечки» скорости не
    -- было — игра штатно применяла бонус «в м��н��шинстве», про��то мы ��а��и его и включали.
    -- Решение (выбрано пользователем): при активном Dodge зануляе�� множитель до 1.0, так
    -- что ��лайдер снова означает РОВНО studs/s, а на дефолте 30 дэш вани*льный.
    --
    -- ВТОРОЙ БАГ, НАЙДЕННЫЙ ЗДЕСЬ ЖЕ: КАРТА UPVALUE'ОВ БЫЛА НЕДЕТЕРМИНИРОВАННОЙ.
    -- Прежний mapEvasive искал upvalue'ы ПО ЗНАЧЕНИЮ и обходил их через `pairs(ups)`.
    -- Две фатальные проблемы:
    --   • `pairs` по таблице НЕ ГАРАНТИРУЕТ порядок обхода. Порядок мог отличаться между
    --     запусками, то есть баг был плавающим.
    --   • Cooldown = 1.5 и OutnumberedDashSpeedMultiplier = 1.5 — ОДНО И ТО ЖЕ ЧИСЛО.
    --     Поиск «первое число, равное 1.5» с равной вероятностью попадал в множитель
    --     вместо кулдауна, после чего driveDodge писал 1.5 не туда, а настоящий кулдаун
    --     уезжал в список «дедлайнов».
    -- Теперь идём по ИНДЕКСАМ (упорядоченно) и опираемся на то����ный порядок upvalue'ов из
    -- дампа (Evasive.lua:508), проверяя ожидаемые значения по конфигу. Индексы:
    --   [15] ServerConfirmTimeout  [16] DashDuration  [22] DashSpeed
    --   [23] OutnumberedDashSpeedMultiplier  [24] OutnumberedDashDurationMultiplier
    --   [27] Cooldown              [4,5,6,7,8] = u6/u5/u4/u7/u8 — дедлайны os.clock
    --
    -- ТРЕТЬЕ: ЗАПИСЬ В CombatConfig БЫЛА БЕСПОЛЕЗНОЙ. Прежний комментарий утверждал, что
    -- дэш читает «и upvalue, и поле конфига». Это неверно: Evasive.lua:20-24 КОПИРУЕТ
    -- значения конфига в локальные переменные ОДИН РАЗ при загрузке модуля, и дальше
    -- CombatConfig.Evasive не читается вообще ни разу. Значит работал только патч
    -- upvalue; запись в конфиг оставлена лишь как безвредная страховка на случай, если
    -- модуль будет перезагружен (тогда он подхватит наши значения при копировании).
    --
    -- COOLDOWN — client-authoritative, exactly like infinite sprint: the server validates a real
    -- dodge ~once/1.5s, but nothing stops us driving the CLIENT dash at our own rate. Every prior
    -- attempt (patching the Cooldown const / clamping deadline upvalues per-frame / clamping the
    -- EvasiveCooldownRemaining attribute) fought the game's own logic and lost — and the Everywhere
    -- grant (u51) zeroes u5/u6/u7/u8 EVERY call (Evasive.lua:557-561), wiping the cooldown entirely
    -- regardless of the slider (that was the "removed immediately even at 1.5s" bug).
    -- Fix: WRAP Evasive.Evasive (hookfunction) and make OUR `_nextDodgeAllowed` deadline the single
    -- source of truth (installEvasiveHook). It swallows dodges inside the window and, when reducing
    -- below vanilla, zeroes the game's native deadline gate so a faster re-dodge goes through. Works
    -- for ANY value in [0, 1.5] and RE-IMPOSES the cooldown on top of the Everywhere grant.
    -- Honest ceiling: i-frames/dash confirmation below ~1.5s are client-prediction; the server still
    -- owns the authoritative i-frame grant.
    --
    -- DODGE-EVERYWHERE ���� two layers, matching how Evasive() gates itself (verified Evasive.lua):
    --   1) OutnumberedEvasiveGrant=true → u51 bypass (line 529). When set, Evasive INTERNALLY
    --      zeroes cooldown deadlines (u5/u6/u7/u8=0, line 557-560) AND skips the `if not u51`
    --      gates: IFRAMECD / Stunned / GuardBroken / CantAnything (line 567-597). So "dodge when
    --      HIT / stunned / guard-broken" works via the game's OWN bypass — no global attribute
    --      spoof needed for those (which would leak into other systems). driveDodge asserts it.
    --   2) The remaining gates are OUTSIDE the u51 guard (line 599-617): Ragdoll / Blocking /
    --      CombatAttacking / Greenzone / RpCombatLocked. Ragdoll is handled by anti-ragdoll;
    --      the other four we hide via the __namecall GetAttribute hook (synchronous, no race).
    -- [V112] Гейты, которые лежат ВНЕ обхода u51 (Evasive.lua:605-618) и потому не
    -- покрываются grant'ом. Раньше их прятал глобальный __namecall-спуф GetAttribute;
    -- теперь снимаем их СИНХРОННО внутри обёртки Evasive — см. installEvasiveHook.
    -- Список — именно порядковый, чтобы восстанавливать ровно то, что сняли.
    local DODGE_GATE_ATTRS = { "Blocking", "CombatAttacking", "Greenzone", "RpCombatLocked" }
    -- Map Evasive base values ONCE: config-table defaults + (if debug API present) the upvalue
    -- indices for DashSpeed / Cooldown (Evasive.lua:506 upvalue list).
    local _evMapped, _evSpeedIdx, _evCdIdx = false, nil, nil
    local _evMultIdx, _evDurMultIdx        = nil, nil   -- [V112] индексы множителей outnumbered
    local _evSpeedBase, _evCdBase          = nil, nil
    local _evMultBase, _evDurMultBase      = nil, nil   -- [V112] вани*льные 1.5 / 1.2 для restore
    local _appliedSpeed, _appliedCd        = nil, nil
    local _appliedMult                     = nil        -- [V112] что уже записано в множитель
    local _evDeadlineIdxs = {}   -- numeric upvalue indices that may hold os.clock cooldown deadlines
    local _evFn           = nil  -- the real Evasive.Evasive closure (for upvalue access)

    -- ═══════════════ [V113] ПОЧЕМУ DODGE ВСЁ ЕЩЁ БЫЛ БЫСТРЕЕ ═══════════════
    -- Это НАСТОЯЩАЯ причина, а не та, что я назвал в V112. Обнуление множителя
    -- OutnumberedDashSpeedMultiplier было верным по смыслу, но применялось НЕ К ТОМУ
    -- ОБЪЕКТУ ФУНКЦИИ, поэтому не имело никакого эффекта — как и патч самого DashSpeed.
    --
    -- Документация Potassium (closure.md): «hookfunction(target, hook) — Hooks a Lua or C
    -- function. Returns a COPY OF THE ORIGINAL function.» То есть после
    --        _origEvasive = hookfunction(_evFn, наш_обработчик)
    -- объект `_evFn` (он же поле `Evasive.Evasive`) СТАНОВИТСЯ нашим обработчиком, а
    -- оригинальный код дэша живёт в возвращённой копии `_origEvasive` — и именно её мы
    -- вызываем. Все debug.setupvalue(_evFn, 22, …) писали в upvalue'ы НАШЕГО замыкания
    -- (Config, _origEvasive, …), а не в игровые DashSpeed / множители. Игровые константы
    -- оставались вани*льными: DashSpeed = 30 и множитель = 1.5 → дэш 45 studs/s.
    -- Именно поэтому симптом «додж быстрее, чем должен» пережил правку V112.
    --
    -- ЧТО ТЕПЕРЬ: все чтения и записи upvalue'ов идут через evTarget() — исполняемую
    -- копию. До установки хука это ещё оригинал (_evFn), поэтому mapEvasive, которая
    -- работает ДО хука, продолжает верно сверять значения с конфигом.
    -- Список upvalue'ов подтверждён дампом (Evasive.lua:508), индексы 22/23/24/27 верны —
    -- ошибка была только в объекте, а не в индексах.
    local _evHooked, _origEvasive = false, nil
    local function evTarget() return _origEvasive or _evFn end
    local _nextDodgeAllowed = 0  -- OUR client-authoritative cooldown deadline (os.clock)

    -- [V112] Точный порядок upvalue'ов функции Evasive (Evasive.lua:508). Держим таблицу
    -- ИМЕНОВАННОЙ и упорядоченной: индекс → ожидаемое значение из конфига. Так привязка
    -- детерминирована и коллизия «Cooldown 1.5 против множителя 1.5» невозможна в принципе.
    local EV_UPV = {
        SpeedIdx   = 22,   -- DashSpeed
        MultIdx    = 23,   -- OutnumberedDashSpeedMultiplier
        DurMultIdx = 24,   -- OutnumberedDashDurationMultiplier
        CdIdx      = 27,   -- Cooldown
    }
    local EV_DEADLINE_IDXS = { 4, 5, 6, 7, 8 }   -- u6, u5, u4, u7, u8 — метки os.clock

    -- [V112] Персистентная обёртка записи атрибут���� (использу��тся о��ходом ��ейтов Dodge).
    -- Отдельная функция, а не замыкание на месте: обход выполняется на каждый дэш.
    local function _setAttr(inst, key, val) inst:SetAttribute(key, val) end

    local function mapEvasive()
        if _evMapped then return true end
        local ev = getEvasive(); if not ev or type(ev.Evasive) ~= "function" then return false end
        _evFn = ev.Evasive
        local cfg = getCombatConfig()
        local ev2 = cfg and cfg.Evasive
        _evSpeedBase   = ev2 and type(ev2.DashSpeed) == "number" and ev2.DashSpeed or nil
        _evCdBase      = ev2 and type(ev2.Cooldown)  == "number" and ev2.Cooldown  or nil
        _evMultBase    = ev2 and type(ev2.OutnumberedDashSpeedMultiplier) == "number"
                         and ev2.OutnumberedDashSpeedMultiplier or nil
        _evDurMultBase = ev2 and type(ev2.OutnumberedDashDurationMultiplier) == "number"
                         and ev2.OutnumberedDashDurationMultiplier or nil
        if hasDebugUpvalues() then
            -- ВЕРИФИКАЦИЯ, а не угадывание: берём upvalue по ожидаемому индексу и сверяем с
            -- значением из конфига. Совпало — привязка верна. Не совпало (игра обновилась и
            -- порядок поехал) — ищем по значению, но УПОРЯДОЧЕННО (i = 1..n) и с учётом
            -- того, что множитель лежит РАНЬШЕ кулдауна, поэтому одинаковые 1.5 больше не
            -- путаются: первое совпадение 1.5 — множитель, второе — Cooldown.
            local function probe(idx, want)
                if not (idx and want) then return false end
                local ok, v = pcall(_getUp, _evFn, idx)
                return ok and type(v) == "number" and math.abs(v - want) < 1e-4
            end
            if probe(EV_UPV.SpeedIdx, _evSpeedBase) and probe(EV_UPV.CdIdx, _evCdBase)
               and probe(EV_UPV.MultIdx, _evMultBase) then
                _evSpeedIdx   = EV_UPV.SpeedIdx
                _evCdIdx      = EV_UPV.CdIdx
                _evMultIdx    = EV_UPV.MultIdx
                if probe(EV_UPV.DurMultIdx, _evDurMultBase) then _evDurMultIdx = EV_UPV.DurMultIdx end
            else
                local info = select(2, pcall(debug.getinfo, _evFn))
                local n = (type(info) == "table" and tonumber(info.nups)) or 40
                for i = 1, n do
                    local ok, v = pcall(_getUp, _evFn, i)
                    if ok and type(v) == "number" then
                        if _evSpeedBase and not _evSpeedIdx and math.abs(v - _evSpeedBase) < 1e-4 then
                            _evSpeedIdx = i
                        elseif _evMultBase and not _evMultIdx and math.abs(v - _evMultBase) < 1e-4 then
                            _evMultIdx = i          -- множитель встречается ПЕРВЫМ
                        elseif _evDurMultBase and not _evDurMultIdx and math.abs(v - _evDurMultBase) < 1e-4 then
                            _evDurMultIdx = i
                        elseif _evCdBase and not _evCdIdx and math.abs(v - _evCdBase) < 1e-4 then
                            _evCdIdx = i            -- и только потом Cooldown
                        end
                    end
                end
            end
            -- Дедлайны больше НЕ «все прочие числ��»: берём заранее известные индексы. Прежний
            -- код мог случайно записать в список сам Cooldown или множитель.
            for _, idx in ipairs(EV_DEADLINE_IDXS) do
                _evDeadlineIdxs[#_evDeadlineIdxs + 1] = idx
            end
        end
        _evMapped = true
        return true
    end

    -- Zero the game's own cooldown deadline upvalues (u6/u7/u8 = os.clock timestamps) so the
    -- native `os.clock() < u6` gate (Evasive.lua:573-581) won't reject a re-dodge that comes
    -- sooner than the game's 1.5s. Only os.clock-scale values (>60) are touched, so the small
    -- constants (DashSpeed/Cooldown/DashDuration/ServerConfirmTimeout) are never corrupted.
    local function zeroGameDeadlines()
        if not (evTarget() and hasDebugUpvalues()) then return end
        local tgt = evTarget()   -- [V113] исполняемая копия, а не подменённый объект
        for _, idx in ipairs(_evDeadlineIdxs) do
            local ok, v = pcall(_getUp, tgt, idx)
            if ok and type(v) == "number" and v > 60 then
                pcall(_setUp, tgt, idx, 0)
            end
        end
    end

    -- ── CUSTOM DODGE COOLDOWN — client-authoritative, like infinite sprint ──────────────────
    -- The server validates a real dodge ~once per 1.5s, but nothing stops us from driving the
    -- CLIENT dash at our own rate. We wrap Evasive.Evasive and make OUR `_nextDodgeAllowed`
    -- deadline the single source of truth. This works WITH the Everywhere grant (which zeroes
    -- the game's deadlines) AND without it, and enforces ANY value in [0, base] — not just 0/1.5.
    -- ROOT-CAUSE FIX: previously the Everywhere grant (OutnumberedEvasiveGrant→u51) zeroed
    -- u6/u5/u7/u8 every call (Evasive.lua:557-561), so cooldown vanished entirely regardless of
    -- the slider. Now the wrapper RE-IMPOSES the cooldown on top of the grant.
    -- [V113] _evHooked/_origEvasive объявлены выше (рядом с evTarget), т.к. zeroGameDeadlines
    -- и driveDodge должны обращаться к исполняемой копии, а они определены раньше этой строки.
    local function installEvasiveHook()
        if _evHooked then return true end
        if type(hookfunction) ~= "function" then return false end
        if not mapEvasive() then return false end
        _origEvasive = hookfunction(_evFn, LPH_NO_VIRTUALIZE(function(...)
            if not Config.Dodge_On then return _origEvasive(...) end
            local base  = _evCdBase or 1.5
            local effCd = math.clamp(Config.Dodge_Cooldown or base, 0, base)
            local custom = effCd < base - 1e-4          -- reducing below vanilla?
            -- If we're NOT reducing AND the Everywhere grant isn't nuking the native cooldown,
            -- let the game own the cooldown entirely (pure vanilla — including its correct
            -- "don't arm cooldown on a state-rejected dodge" behaviour).
            if not custom and not Config.Dodge_Everywhere then
                return _origEvasive(...)
            end
            local now = os.clock()
            if now < _nextDodgeAllowed then
                return                                  -- still on OUR custom cooldown → swallow
            end
            if custom then
                zeroGameDeadlines()                     -- allow a faster-than-vanilla re-dodge
            end
            _nextDodgeAllowed = now + effCd             -- arm our client-side cooldown

            -- [V112] DODGE EVERYWHERE без глобального хука. Гейты Blocking /
            -- CombatAttacking / Greenzone / RpCombatLocked читаются на Evasive.lua:605-618
            -- обычным GetAttribute. Единственный yield во всей функции до этих проверок —
            -- строка 510 (`LocalPlayer.Character or CharacterAdded:Wait()`), и он не
            -- срабатывает, когда персонаж есть. Значит снять атрибуты, вызвать оригинал и
            -- вернуть их обратно можно СИНХРОННО: между нашим снятием и чте��и��м игрой
            -- никакой другой код ��сполниться не может — гонки нет by design.
            -- Записи локальные (на сервер не репл*ицируются), а сами гейты проверяются на
            -- клиенте, поэтому этого достаточно.
            if Config.Dodge_Everywhere then
                local c = _myChar
                if c then
                    local saved
                    for i = 1, #DODGE_GATE_ATTRS do
                        local k = DODGE_GATE_ATTRS[i]
                        local v = c:GetAttribute(k)
                        if v ~= nil then
                            saved = saved or {}
                            saved[k] = v
                            pcall(_setAttr, c, k, nil)
                        end
                    end
                    -- pcall вокруг оригинала обязателен: без него ошибка внутри Evasive
                    -- оставила бы атрибуты снятыми навсегда и сломала блок/грин-зону.
                    local okE, r1, r2 = pcall(_origEvasive, ...)
                    if saved then
                        for k, v in pairs(saved) do pcall(_setAttr, c, k, v) end
                    end
                    if okE then return r1, r2 end
                    return
                end
            end
            return _origEvasive(...)
        end))
        _evHooked = (_origEvasive ~= nil)
        -- [V113] ОБЯЗАТЕЛЬНЫЙ СБРОС КЭШЕЙ. driveDodge пишет upvalue'ы только когда значение
        -- «ещё не применено» (_appliedSpeed/_appliedCd/_appliedMult). Но цель патча только
        -- что сменилась с _evFn на _origEvasive: без сброса кэш сказал бы «уже применено»,
        -- и в новую (реально исполняемую) копию мы бы не записали НИЧЕГО. Это тот же класс
        -- ошибки, что и сам баг V112 — молчаливый промах мимо объекта.
        if _evHooked then _appliedSpeed, _appliedCd, _appliedMult = nil, nil, nil end
        return _evHooked
    end
    local function _setGrant(c) c:SetAttribute("OutnumberedEvasiveGrant", true) end
    -- Cheap per-frame keeper: writes only when the desired value actually changed.
    local function driveDodge()
        if not Config.Dodge_On then return end
        if not mapEvasive() then return end
        -- [V113] Хук ставим ДО патчей, а не после них. Прежде он стоял в конце функции, из-за
        -- чего на кадре установки все записи уходили в ещё-неподменённый _evFn, а на
        -- следующем кадре кэши уже считали работу сделанной. Теперь цель патча (evTarget)
        -- корректна с первой же записи.
        if not _evHooked then installEvasiveHook() end
        local cfg = getCombatConfig()
        local wantSpeed = (Config.Dodge_Speed and Config.Dodge_Speed > 0) and Config.Dodge_Speed or _evSpeedBase
        if wantSpeed and wantSpeed ~= _appliedSpeed then
            if cfg and cfg.Evasive then cfg.Evasive.DashSpeed = wantSpeed end
            if _evSpeedIdx then pcall(_setUp, evTarget(), _evSpeedIdx, wantSpeed) end
            _appliedSpeed = wantSpeed
        end

        -- [V112] ИСПРАВЛЕНИЕ БАГА «скорость растёт ��ама»: зануляем множитель до 1.0.
        -- Пока Dodge включён, ветка `if u51 then v63 = DashSpeed * Multiplier` (Evasive.lua:695)
        -- перестаёт менять результат, и слайдер означает РОВНО итоговые studs/s — в том числе
        -- на дефолте 30. Длительность тоже нормализуем (Evasive.lua:703), иначе дэш оставался
        -- бы на 20% длиннее вани*льного, то есть тем же «незапрошенным бонусом», только в
        -- другой величине. Запись — только при фактическом изменении.
        if _appliedMult ~= 1 then
            if cfg and cfg.Evasive then
                cfg.Evasive.OutnumberedDashSpeedMultiplier    = 1
                cfg.Evasive.OutnumberedDashDurationMultiplier = 1
            end
            if _evMultIdx    then pcall(_setUp, evTarget(), _evMultIdx, 1) end
            if _evDurMultIdx then pcall(_setUp, evTarget(), _evDurMultIdx, 1) end
            _appliedMult = 1
        end
        -- CUSTOM COOLDOWN is enforced by the Evasive.Evasive wrapper (installEvasiveHook), whose
        -- `_nextDodgeAllowed` gate is the single source of truth for ANY value in [0, base]. We
        -- keep the Cooldown constant / config field at the vanilla base (the game scales it per
        -- style; corrupting it caused the old "stuck at 0" bug) — the wrapper does the real work.
        local base = _evCdBase or 1.5
        if base ~= _appliedCd then
            if cfg and cfg.Evasive then cfg.Evasive.Cooldown = base end
            if _evCdIdx then pcall(_setUp, evTarget(), _evCdIdx, base) end
            _appliedCd = base
        end
        -- [PERF] installEvasiveHook was called on EVERY Heartbeat. It early-returns once hooked,
        -- but that's still a call + upvalue read every frame forever; latch it instead.
        -- [V113] Сам вызов перенесён в НАЧАЛО driveDodge (причина — в комментарии там же).

        -- DODGE EVERYWHERE — assert the game's own u51 bypass (skips the hit/stun/guard-broken/
        -- cant-anything gates internally). It ALSO zeroes the game's deadlines, but that no longer
        -- wipes the cooldown because the Evasive wrapper re-imposes `_nextDodgeAllowed` on top.
        -- The __namecall hook covers the remaining Blocking/CombatAttacking/Greenzone/RpCombatLocked.
        if Config.Dodge_Everywhere then
            local c = _myChar
            if c and c:GetAttribute("OutnumberedEvasiveGrant") ~= true then
                pcall(_setGrant, c)   -- [PERF] persistent wrapper, was a closure per Heartbeat
            end
        end
    end
    -- Clear the u51 grant we asserted (called when Everywhere / Dodge is toggled off).
    local function clearDodgeGrant()
        local c = _myChar
        if c and c:GetAttribute("OutnumberedEvasiveGrant") == true then
            pcall(function() c:SetAttribute("OutnumberedEvasiveGrant", nil) end)
        end
    end
    -- Restore the game's own numbers (called when Dodge is toggled off).
    local function restoreDodge()
        clearDodgeGrant()
        if not _evMapped then return end
        -- [V113] Локальная `ev` убрана: после перехода на evTarget() она больше нигде не
        -- использовалась, а её наличие подсказывало неверное «патчим ev.Evasive» — ровно то
        -- заблуждение, из которого вырос баг со скоростью дэша.
        local cfg = getCombatConfig()
        if _evSpeedBase then
            if cfg and cfg.Evasive then cfg.Evasive.DashSpeed = _evSpeedBase end
            if _evSpeedIdx then pcall(_setUp, evTarget(), _evSpeedIdx, _evSpeedBase) end
        end
        if _evCdBase then
            if cfg and cfg.Evasive then cfg.Evasive.Cooldown = _evCdBase end
            if _evCdIdx then pcall(_setUp, evTarget(), _evCdIdx, _evCdBase) end
        end
        -- [V112] Возвращаем вани*льные множители outnumbered (1.5 / 1.2). Без этого после
        -- выключения ��умбле��а иг��а ост��лась бы БЕЗ легитимного бонуса «в меньшинстве»,
        -- который сервер даёт честно, когда вас реально окружили.
        if _evMultBase and _evMultIdx then
            if cfg and cfg.Evasive then cfg.Evasive.OutnumberedDashSpeedMultiplier = _evMultBase end
            pcall(_setUp, evTarget(), _evMultIdx, _evMultBase)
        end
        if _evDurMultBase and _evDurMultIdx then
            if cfg and cfg.Evasive then cfg.Evasive.OutnumberedDashDurationMultiplier = _evDurMultBase end
            pcall(_setUp, evTarget(), _evDurMultIdx, _evDurMultBase)
        end
        _appliedSpeed, _appliedCd, _appliedMult = nil, nil, nil
    end

    -- ═══════════════════════ ANTI-RAGDOLL / AUTO-GETUP ══════════════════════
    -- Verified in RagdollServiceClient: while attr Ragdoll==true the game runs a Heartbeat that
    -- calls sustainClientRagdoll (GettingUp=false + ChangeState(Ragdoll) + PlatformStand=true).
    -- Clearing the attribute from our own loop LOSES the race — the server re-replicates
    -- Ragdoll=true and their Heartbeat re-sustains the same frame → flicker.
    --
    -- Robust fix: a __namecall hook on GetAttribute that reports Ragdoll as nil on OUR character,
    -- synchronously with every read the ragdoll code makes. onRagdollChanged / the sustain
    -- Heartbeat / isManagedRagdoll then all see "no ragdoll" → the game runs its OWN clean getup
    -- (u7) and never re-sustains, even if the server keeps the attribute set. We EXEMPT managed
    -- ragdolls (Downed / carried / gripped / dead) so carry & downed states are untouched.
    local function isManagedRagdoll(char, hum)
        if char:GetAttribute("Downed") == true then return true end
        local states = char:FindFirstChild("States")
        if states then
            local bc = states:FindFirstChild("BeingCarried")
            local bg = states:FindFirstChild("BeingGripped")
            if (bc and bc.Value ~= nil) or (bg and bg.Value ~= nil) then return true end
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if root and (root:FindFirstChild("CarryWeld") or root:FindFirstChild("GripWeld")) then
            return true
        end
        hum = hum or char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        return false
    end
    -- ── [V112] ГЛОБАЛЬНЫЙ __namecall-ХУК УДАЛЁН — ЭТО И БЫЛ ГЛАВНЫЙ ИСТОЧНИК ЛАГОВ ──
    -- ПОЧЕМУ ПРЕЖНИЙ КОД БЫЛ НЕВЕРЕН (по стоимости, не по логике — логика работала):
    -- hookmetamethod(game, "__namecall") ставит наш Lua-обработчик на КАЖДЫЙ вызов метода
    -- ЛЮБОГО объекта во всей игре: каждый :FindFirstChild, :IsA, :GetAttribute, :Connect,
    -- :FireServer — десятки тысяч вызовов в секунду. Даже «дешёвый» путь (сравнение
    -- self == _myChar) платится на всём этом трафике, а сам переход C→Lua на каждый
    -- namecall не бесплатен. Хук ставился НАВСЕГДА (_combatHookDone) и не снимался даже
    -- когда обе фичи выключены, то есть налог шёл всю сессию. Ровно это и даёт
    -- «накапливающиеся лаги» и падения: чем дольше сессия и чем больше объектов, тем
    -- больше namecall-трафика через наш обработчик.
    -- Ниже — два ТОЧЕЧНЫХ решения, каждое стоит ноль на холостом ходу.

    -- [V112] ANTI-RAGDOLL: точечный хук ОДНОЙ функции вместо слежки за GetAttribute.
    -- Дамп RagdollServiceClient показывает, ЧТО именно держит нас лежащим —
    -- sustainClientRagdoll (строки 67-80) делает ровно три вещи:
    --      Humanoid:SetStateEnabled(GettingUp, false)
    --      if GetState() ~= Ragdoll then ChangeState(Ragdoll) end
    --      Humanoid.PlatformStand = true
    -- и её зовёт Heartbeat через stepClientRagdollSustain (строка 116). Поэтому прежний
    -- комментарий «мы проигрываем гонку» был верен по факту: сколько бы мы ни поднимали
    -- персонажа, эта функция возвращала его в рэгдолл в тот же кадр.
    -- Решение: хукнуть саму sustainClientRagdoll. Функция локальная, но она лежит
    -- upvalue'ом #5 у экспортированной u1.Init (список upvalue'ов, строка 295:
    -- Players, CombatRemote, isManagedRagdoll, Workspace, sustainClientRagdoll, …).
    -- ВАЖНО: правим не upvalue, а САМ ОБЪЕКТ ФУНКЦИИ через hookfunction — копии upvalue
    -- в разных замыканиях (stepClientRagdollSustain, Init, _bindCharacter) ссылаются на
    -- ОДИН объект, поэтому одного hookfunction достаточно для всех вызывающих. Патч
    -- отдельного upvalue у Init не сработал бы: у stepClientRagdollSustain своя копия.
    -- Managed-рэгдоллы (Downed / carry / grip / смерть) пропускаем к оригиналу, чтобы не
    -- сломать переноску и добивание.
    local _ragHooked, _origSustain = false, nil
    local function installAntiRagdollHook()
        if _ragHooked then return true end
        if type(hookfunction) ~= "function" or not hasDebugUpvalues() then return false end
        local rag = tryRequire({ "Shared", "Services", "RagdollService", "RagdollServiceClient" })
        if not rag or type(rag.Init) ~= "function" then return false end
        -- Берём upvalue #5 и ПРОВЕРЯЕМ, что это функция; если игра сдвинула порядок —
        -- ищем перебором ту, у ко��орой н��т upvalue'ов (sustainClientRagdoll их н�� имеет,
        -- в отличие от isManagedRagdoll/stepClientRagdollSustain).
        local fn
        local ok5, v5 = pcall(_getUp, rag.Init, 5)
        if ok5 and type(v5) == "function" then
            fn = v5
        else
            local info = select(2, pcall(debug.getinfo, rag.Init))
            local n = (type(info) == "table" and tonumber(info.nups)) or 12
            for i = 1, n do
                local oki, vi = pcall(_getUp, rag.Init, i)
                if oki and type(vi) == "function" then
                    local inf = select(2, pcall(debug.getinfo, vi))
                    if type(inf) == "table" and tonumber(inf.nups) == 0 then fn = vi; break end
                end
            end
        end
        if not fn then return false end
        local okh, ref = pcall(hookfunction, fn, LPH_NO_VIRTUALIZE(function(char, ...)
            if Config.AntiRagdoll_On and char and not isManagedRagdoll(char) then
                return    -- глушим удержание рэгдолла: наш getup ниже теперь выигрывает гонку
            end
            return _origSustain(char, ...)
        end))
        if not okh or not ref then return false end
        _origSustain = ref
        _ragHooked = true
        return true
    end

    -- Собственно под��ём. Персистентные обёртки — без аллокации замыкан��й на кадр.
    local function _clearRagAttr(c) c:SetAttribute("Ragdoll", nil) end
    local function _forceGetup(hum)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
        hum.PlatformStand = false
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown
           or st == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    -- ══════════════════════════ [V112] NO BLUR ══════════════════════════════
    -- ЧТО ИМЕННО МЫЛИТ ЭКРАН. В игре ровно ОДИН BlurEffect: ScreenEffects создаёт его
    -- сам (ScreenEffects.lua:166-171 — Instance.new("BlurEffect"), Name =
    -- "ScreenEffectsBlur", Parent = Lighting) и держит в upvalue u6. Все источники
    -- работают слоями: SetBlur(key, size, …) кладёт слой в таблицу u32, а
    -- applyCompositeBlur (ScreenEffects.lua:247-273) берёт МАКСИМУМ по слоям и пишет
    -- u6.Size / u6.Enabled. То есть единая воронка — душить надо её, а не искать блюры
    -- по Lighting.
    --
    -- ПОЧЕМУ НЕ НУЖЕН hookfunction. Все 20+ мест вызывают его как
    -- `ScreenEffects.SetBlur("HealthHit", …)` — то есть ИНДЕКСИРУЮТ таблицу модуля в
    -- момент вызова, и ни один потребитель не кэширует функцию в local (проверено
    -- поиском по всему дампу). Внутренние вызовы самого модуля тоже идут через `u1.SetBlur`
    -- (ScreenEffects.lua:474) — а `u1` и есть возвращаемая таблица. Значит достаточно
    -- подменить ПОЛЕ таблицы: работает на любом executor'е, без хуков и без слежки за
    -- namecall. require() отдаёт тот же кэшированный объект, что и у игры.
    --
    -- ПОЧЕМУ ФИЛЬТР ПО КЛЮЧУ, А НЕ «ВЫКЛЮЧИТЬ ВСЁ». key — первый аргумент SetBlur, и по
    -- нему видно природу блюра. Боевой/эффектный блюр (удары, Downed, захват, смерть,
    -- Black Flash, падение) мешает играть — его глушим. Блюр меню и панелей — часть
    -- нормального UI, его снятие сделало бы интерфейс визуально сломанным, поэтому он
    -- проходит к оригиналу. Отдельная настройка для этого не нужна: разделение выводится
    -- из самих данных игры.
    local BLUR_BLOCK_KEYS = {
        HealthHit = true, HealthDowned = true, HealthGripped = true, GlassesMissing = true,
        Death = true, HakariBlackFlash = true, __Impact = true, Fall = true,
    }
    local _blurPatched, _origSetBlur, _screenFx = false, nil, nil
    local function installNoBlur()
        if _blurPatched then return true end
        _screenFx = tryRequire({ "Packages", "ScreenEffects" })
        if not _screenFx or type(_screenFx.SetBlur) ~= "function" then return false end
        _origSetBlur = _screenFx.SetBlur
        _screenFx.SetBlur = function(key, ...)
            if Config.NoBlur_On and BLUR_BLOCK_KEYS[key] then
                -- Слой не регистрируем вовсе → applyCompositeBlur не увидит его в максимуме.
                -- Симметричный ClearBlur НЕ подменяем: он просто не найдёт слой и выйдет,
                -- а на UI-ключах продолжит работать штатно.
                return
            end
            return _origSetBlur(key, ...)
        end
        _blurPatched = true
        return true
    end
    -- Мгновенно убрать блюр, который уже висит на экране в момент включения тумблера.
    -- Зовём штатный ClearBlur(key, 0) — так же, как это делает сама игра при сбросе
    -- (HealthServiceClient.lua:1462-1463, 1493-1494), поэтому состояние слоёв остаётся
    -- согласованным и игра потом не «вспомнит» старый размер.
    local function clearActiveBlur()
        if not _screenFx or type(_screenFx.ClearBlur) ~= "function" then return end
        for key in pairs(BLUR_BLOCK_KEYS) do
            pcall(_screenFx.ClearBlur, key, 0)
        end
    end

    -- ══════════════════ [V112] RESPAWN / AUTO RESPAWN ═══════════════════════
    -- КАК РЕСПАВН УСТРОЕН В ИГРЕ (проверено по дампу, не по догадке):
    --   SpawnServiceUtils.lua:11  REMOTE_NAME      = "SpawnRequest"
    --   SpawnServiceUtils.lua:12  PLAYER_DEAD_ATTR = "Dead"
    --   SpawnServiceClient.lua:410  _spawnRemote:FireServer()   ← весь респавн это ОДИН
    --                                                             пустой FireServer
    --   SpawnServiceClient.lua:596  remote = ReplicatedStorage.Remotes["SpawnRequest"]
    -- Поэтому мы шлём ровно тот же ремоут напрямую. Через клиентский модуль (_doRespawn)
    -- идти НЕЛЬЗЯ: он в первой же строке выходит, если нет UI смерти (_light/_main) или
    -- если _respawnInFlight — то есть кнопка работала бы только на экране смерти.
    --
    -- ═══════ [V116] НАСТОЯЩАЯ ПРИЧИНА: Я ВСЁ ВРЕМЯ ДЁРГАЛ НЕ ТОТ РЕМОУТ ═══════
    -- Ты сказал «убивает, но респавна нет» — и это ровно то, что должно было происходить.
    -- Смерть работала, а respawn я отправлял в `Remotes.SpawnRequest`, который к экрану
    -- смерти отношения не имеет. В дампе нашёлся ОТДЕЛЬНЫЙ скрипт респавна:
    --   dumped/PlayerScripts/respawnstuff_LocalScript.lua
    --     :15   local RespawnRE = ReplicatedStorage:WaitForChild("RespawnRE")
    --     :385  Character:GetAttributeChangedSignal("Dead") → startdeath()
    --     :303  u4.Text = "RESTART YOUR HEART"       ← тот самый экран смерти
    --     :354  if u10 >= 7 then dorespawn() end     ← нужно СЕМЬ нажатий по сердцу
    --     :227  dorespawn(): RespawnRE:FireServer()  ← и только тут реальный респавн
    -- То есть возрождение делает `ReplicatedStorage.RespawnRE`, а не SpawnRequest. Игра
    -- гейтит его семью кликами по кнопке, между которыми ещё и анимация с task.wait(0.6)
    -- (:339-353) — суммарно около пяти секунд «ожидания», которое ты и описывал.
    --
    -- ЭКСПЛОИТ: шлём RespawnRE:FireServer() напрямую, минуя счётчик кликов u10. Аргументов
    -- у него нет (:227 — вызов пустой), поэтому подделывать нечего.
    --
    -- ВАЖНО про порядок: экран смерти поднимается по атрибуту "Dead" на ПЕРСОНАЖЕ (:385),
    -- и respawn имеет смысл только после смерти. Поэтому цепочка: убить → дождаться Dead →
    -- RespawnRE. Респавн даёт полное HP, т.к. сервер создаёт персонажа заново
    -- (dorespawn ждёт именно LocalPlayer.CharacterAdded, :229).
    --
    -- RespawnRE В ДАМПЕ ОТСУТСТВУЕТ в списке ReplicatedStorage — его создаёт сервер в
    -- рантайме (клиентский скрипт ждёт его через WaitForChild). Поэтому резолвим лениво и
    -- терпимо к отсутствию, а SpawnRequest оставляем запасным вариантом.
    local _respawnRemote, _spawnRemote = nil, nil
    -- Главный ремоут возрождения (кнопка "RESTART YOUR HEART").
    local function getRespawnRemote()
        if _respawnRemote and _respawnRemote.Parent then return _respawnRemote end
        local re = ReplicatedStorage:FindFirstChild("RespawnRE")
        if re and re:IsA("RemoteEvent") then _respawnRemote = re end
        return _respawnRemote
    end
    -- Запасной: ремоут спавн-сервиса. Оставлен на случай, если RespawnRE ещё не
    -- отреплицировался — но основную работу делает именно RespawnRE.
    local function getSpawnRemote()
        if _spawnRemote and _spawnRemote.Parent then return _spawnRemote end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local re = remotes and remotes:FindFirstChild("SpawnRequest")
        if re and re:IsA("RemoteEvent") then _spawnRemote = re end
        return _spawnRemote
    end
    -- ═══════ [V124] ТВОЯ ЗАЦЕПКА С РЕРОЛЛОМ ОКАЗАЛАСЬ ТОЧНЫМ ПОПАДАНИЕМ ═══════
    -- Ты сказал: «в реролле роста происходит что-то типа респавна, здоровье не меняется».
    -- Пошёл смотреть, что делает реролл, и нашёл ровно то, чего не хватало всё это время.
    --
    -- ЦЕПОЧКА РЕРОЛЛА (по дампу, файлы и строки):
    --   RerollCurrencyServiceClient:105  Remotes.RerollSpin:InvokeServer(...)   ← сам реролл
    --   ProfileServiceClient:621         CharacterServiceUtils.WaitForCharacterGenReady(...)
    --   ProfileServiceClient:628-638     Remotes.LoadCharacter:InvokeServer()   ← ПЕРЕСБОРКА
    --   Helpers:69                       Remotes.LoadCharacter (кэшируется как RemoteFunction)
    --
    -- ВОТ ОНО: `Remotes.LoadCharacter` — это **RemoteFunction БЕЗ АРГУМЕНТОВ** (:638 вызов
    -- пустой), и сервер по нему ПЕРЕСОЗДАЁТ персонажа. Именно это ты и видел в реролле:
    -- «вроде здоровье не меняется, но всё же похоже на респавн» — потому что это не смерть и
    -- не лечение, а полная пересборка модели сервером.
    --
    -- ПОЧЕМУ ЭТО РЕШАЕТ ВСЁ, С ЧЕМ Я БОРОЛСЯ V116-V123. Все прежние пути требовали, чтобы
    -- сервер СНАЧАЛА признал тебя мёртвым: SpawnRequest, RespawnRE и _doRespawn — это кнопка
    -- «RESTART YOUR HEART» с экрана смерти. Пока сервер держит тебя живым (`Downed=true`),
    -- он их молча отбрасывает — отсюда «при нажатии ничего не происходит». А LoadCharacter
    -- смерти НЕ ТРЕБУЕТ вообще: реролл дёргает его на полностью живом персонаже.
    -- Поэтому убивать себя больше не нужно — ни ломать джойнты, ни падать под карту.
    --
    -- ВАЖНО: это RemoteFunction, а не RemoteEvent. Нужен InvokeServer (не FireServer), и он
    -- БЛОКИРУЕТ поток до ответа сервера — значит звать только из отдельного потока.
    local _loadCharRemote = nil
    local function getLoadCharacterRemote()
        if _loadCharRemote and _loadCharRemote.Parent then return _loadCharRemote end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local rf = remotes and remotes:FindFirstChild("LoadCharacter")
        -- Проверка класса обязательна: игра сама её делает (ProfileServiceClient:147),
        -- потому что под этим именем может лежать не тот объект.
        if rf and rf:IsA("RemoteFunction") then _loadCharRemote = rf end
        return _loadCharRemote
    end

    -- Есть ли вообще чем возрождаться.
    local function hasRespawnRemote()
        return (getLoadCharacterRemote() or getRespawnRemote() or getSpawnRemote()) ~= nil
    end
    local _lastRespawnFire = 0
    -- Персистентная обёртка вместо замыкания на каждый вызов.
    local function _fireRe(re) re:FireServer() end
    -- ВАЖНО: здесь НЕЛЬЗЯ звать notify — она объявлена локально внутри M.buildUI и на этом
    -- уровне разрешилась бы в глобальный nil (падение при первом же вызове). Функция
    -- возвращает результат, а уведомляет пусть вызывающая сторона из UI.
    local function fireRespawn()
        -- [V116] СНАЧАЛА RespawnRE — это и есть респавн. SpawnRequest только как запасной.
        local re = getRespawnRemote() or getSpawnRemote()
        if not re then return false end
        -- Троттлинг обязателен: спам ремоута — верный путь к кику за флуд. Но 3с было
        -- слишком много: игра сама позволяет нажать кнопку повторно примерно раз в 0.7с
        -- (:353 task.wait(0.6) + твины), поэтому 1с безопасно и не мешает «моментально».
        local now = os.clock()
        if now - _lastRespawnFire < 1 then return false end
        _lastRespawnFire = now
        return (pcall(_fireRe, re))
    end

    -- Мёртв/сбит по тем же флагам, что читает сама игра (SpawnServiceClient.lua:97-101).
    local function isDeadOrDowned()
        local c = LocalPlayer.Character
        if LocalPlayer:GetAttribute("Dead") == true then return true end
        if c and c:GetAttribute("Dead") == true then return true end
        if c and c:GetAttribute("Downed") == true then return true end
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
        return false
    end

    -- ═══════ [V115] ВТОРАЯ ДОКАЗУЕМАЯ ПРИЧИНА, ПОЧЕМУ РЕСПАВН «НЕ РАБОТАЛ» ═══════
    -- isDeadOrDowned() возвращает true И на Downed. Сервер же обслуживает SpawnRequest
    -- только при флаге СМЕРТИ (IsDeathFlagged читает атрибут Dead, SpawnServiceUtils.lua:25).
    -- Из-за этого цепочка V114 вела себя ровно так, как ты описал: Player.Kill сбивал тебя
    -- в Downed, isDeadOrDowned говорил «мёртв», скрипт слал SpawnRequest, сервер молча
    -- отказывал (ты жив, ты просто лежишь) — и оставалось только штатное ожидание подъёма
    -- по HP. Downed — это состояние ЖИВОГО персонажа, а не смерть.
    -- ═══════ [V116] ЭТА ФУНКЦИЯ И БЫЛА ЛОВУШКОЙ ═══════
    -- В V115 здесь стояло «нет персонажа → значит мёртв» и «нет Humanoid → значит мёртв».
    -- Вместе с destroySelf(), который уничтожал ЛОКАЛЬНУЮ копию персонажа, это давало
    -- мгновенное ложное true: персонаж исчезал у меня на клиенте, функция объявляла смерть,
    -- цикл ожидания в тот же кадр слал RespawnRE — а сервер в этот момент ещё считал меня
    -- живым и запрос отбрасывал. После этого цикл делал break и больше НЕ повторял попытку.
    -- Отсюда ровно твой симптом: «умираю, а зареспавниться не могу».
    --
    -- Теперь смерть определяем ТОЛЬКО так, как её определяет сама игра:
    --   respawnstuff_LocalScript.lua:385  Character:GetAttributeChangedSignal("Dead")
    -- Атрибут "Dead" ставит СЕРВЕР, поэтому это единственный авторитетный признак.
    -- Отсутствие локальной модели больше смертью НЕ считается — это лишь потеря копии.
    local function isTrulyDead()
        local c = LocalPlayer.Character
        if LocalPlayer:GetAttribute("Dead") == true then return true end
        if c and c:GetAttribute("Dead") == true then return true end
        if not c then return false end
        local hum = c:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        -- HP<=0 считаем смертью ТОЛЬКО если это не Downed: в Downed игра держит 0 HP.
        return hum.Health <= 0 and c:GetAttribute("Downed") ~= true
    end

    -- ═══════ [V119] РАЗОБРАЛ ТВОЙ УНИВЕРСАЛЬНЫЙ RESET — Я БЫЛ НЕПРАВ ВЕЗДЕ ═══════
    -- Снял обфускацию LuaObfuscator (пейлоад "LOL!" = hex-пары + RLE через "NQ"), достал
    -- таблицу констант. Ядро скрипта — одна функция, её константы идут ровно так:
    --     workspace · FindFirstChildOfClass · ChangeState · Enum · HumanoidStateType
    --     GettingUp · Character · CharacterAdded · Wait · MoveTo · Position · Vector3 · warn
    -- И это ВСЁ. В скрипте НЕТ: Kill, LoadCharacter, SetCore, Health, BreakJoints, ремоутов.
    -- Значит универсальный ресет — это чистая state-машина Humanoid'а:
    --     Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    -- Работает в лю��ой игре имен��о потому, что это движковый Humanoid, а не механика игры —
    -- ты это и говорил. Состояние своего персонажа клиент меняет авторитетно (у него network
    -- ownership своих частей), поэтому смена реплицируется и поднимает из Dead/Ragdoll.
    --
    -- ЧЕМ БЫЛ ПЛОХ МОЙ ПОДХОД (по пунктам, всё это мои ошибки):
    --   • replicatesignal(Player.Kill) — это УБИЙСТВО. Оно не может «возродить с фулл HP»,
    --     я выдавал смерть за респавн. Отсюда твоё «я просто сдыхаю».
    --   • SetCore("ResetButtonCallback", fn) — это СЕТТЕР, он лишь переопределяет кнопку и
    --     ничего не вызывает; а сама кнопка Reset всё равно только убивает.
    --   • Опора на SpawnRequest/_doRespawn — привязка к механике конкретной игры там, где
    --     достаточно движкового Humanoid. Плюс про U0 ты прав: модули инициализируются и
    --     удаляются из дерева, живут в памяти — поэтому мой вывод «мёртвый код» тоже неверен.
    --
    -- ПОЧЕМУ ОДНОГО ChangeState МАЛО ИМЕННО ЗДЕСЬ (проверено по дампу игры).
    -- Downed эта игра держит принудительно (наш же разбор, movement.lua:1402-1404):
    --     Humanoid:SetStateEnabled(GettingUp, false)   ← состояние ЗАПРЕЩЕНО
    --     Humanoid:ChangeState(Ragdoll)
    --     Humanoid.PlatformStand = true
    -- ChangeState(GettingUp) по ЗАПРЕЩЁННОМУ состоянию движок просто игнорирует. Поэтому
    -- порядок обязателен: сначала РАЗРЕШИТЬ GettingUp и снять Ragdoll/PlatformStand, и только
    -- потом менять состояние. Именно этого не хватало, чтобы «встать», а не «лежать и ждать».
    -- [V121] Функция reviveViaHumanoidState УДАЛЕНА из пути респавна. Причина по твоему диагу:
    -- её `pcall(ChangeState)` возвращал true даже когда состояние не менялось, и цикл респавна
    -- принимал это за успех («via GettingUp -> OK» при state Running). И по сути: подъём даёт
    -- ноги, но НЕ полное HP, а нужен именно новый персонаж. Разбор выше оставлен как история.

    -- ═══════ [V120] РЕАНИМАЦИЯ: КАК ОНА РЕАЛЬНО РАБОТАЕТ ═══════
    -- Ты сказал искать в интернете — нашёл, и это опровергает моё прежнее утверждение
    -- «Destroy с клиента не реплицируется». Механика reanimate-скриптов:
    -- удаление ДЖОЙНТОВ/частей локально РЕПЛИЦИРУЕТСЯ на сервер через network ownership
    -- (клиент — владелец частей своего персонажа, поэтому сервер принимает их и��чезновение).
    -- Именно поэтому разработчики защищаются серверными проверками «пропал ли core joint».
    -- Мой прошлый вывод был неверен: не реплицируется удаление ЧУЖИХ/серверных объектов,
    -- а свои части персонажа — реплицируются.
    --
    -- ДВИЖКОВЫЙ МЕХАНИЗМ СМЕРТИ. Humanoid.RequiresNeck (по умолчанию true): персонаж УМИРАЕТ,
    -- если удалить/отсоединить джойнт, связывающий Head с торсом. Причём движку неважно имя и
    -- тип джойнта — достаточно, чтобы он соединял голову с торсом. Это не механика игры, а
    -- поведение движка, поэтому Downed-система его не перехватывает: она перехватывает УРОН,
    -- а тут смерть наступает от отсутствия шеи. Дальше сервер видит настоящую Humanoid.Died и
    -- возрождает штатно, с полным HP. Ровно то, что ты описал: форсируем смерть → респавн.
    --
    -- НО В ЭТОЙ ИГРЕ СТОИТ РОВНО ЭТА ЗАЩИТА (нашёл в дампе, RagdollService:360-361):
    --     v48.BreakJointsOnDeath = false;
    --     v48.RequiresNeck = false;      ← из-за этого слом шеи НЕ убивает
    -- Игра выставляет их на Humanoid при ragdoll/Downed. Поэтому порядок обязателен:
    -- СНАЧАЛА вернуть RequiresNeck = true, и только ПОТОМ рвать шею. Без этого трюк молча
    -- ничего не делает — что и объясняет, почему «просто лежу».
    -- ═══════ [V122] ПОЧЕМУ V121 «ТОЛЬКО ТЕЛЕПОРТИЛ ПОД ЗЕМЛЮ» ═══════
    -- Твой диаг: `last: via void>void>void>...` — в списке НИ ОДНОГО "neck". Значит breakNeck()
    -- возвращал false на каждой из 40 попыток: он не нашёл джойнт и молча ничего не ломал,
    -- а работал только шаг 2 (бездна). Отсюда «тычусь под землю, но не ресетаюсь».
    --
    -- Ошибка была в СЛИШКОМ УЗКОМ фильтре поиска:
    --     d:IsA("JointInstance") or d:IsA("Motor6D") or d:IsA("Weld")   + условие Part0/Part1 == Head
    -- Ragdoll-системы (и RagdollService этой игры) на ragdoll УДАЛЯЮТ Motor6D и заменяют их
    -- констрейнтами (BallSocket/Weld*Constraint*). WeldConstraint НЕ является ни Weld, ни
    -- JointInstance — мой фильтр их не видел. Плюс если часть головы называется не "Head",
    -- условие `== head` не выполнялось никогда, и функция превращалась в пустышку.
    --
    -- Новый подход — как в настоящих reanimate-скриптах: не искать ОДИН «правильный» джойнт,
    -- а разобрать связи персонажа целиком (это и есть BreakJoints) и снести саму голову.
    -- Удаление своих частей реплицируется через network ownership, поэтому сервер видит
    -- настоящую Humanoid.Died и возрождает штатно с полным HP.
    -- ═══════ [V123] ВЕСЬ ПОДХОД «ФОРСИРОВАТЬ СМЕРТЬ» ОТМЕНЁН ═══════
    -- Твой диаг: `state: Ragdoll | Downed: true | paths=neck>void death[joints=0 head=false]`
    -- плюс твои слова «удаляет всё, из-за чего я визуально невидим, и это всё ещё не респавн».
    -- Что это доказывает: удаление частей ВЫПОЛНЯЛОСЬ (иначе ты бы не стал невидимым), но
    -- се��вер смерть не признал — `no CharacterAdded in 12s`. Значит удаление своих частей в
    -- ЭТОЙ игре на сервер не влияет: у сервера собственное состояние персонажа (Downed=true
    -- держится), а локально снесённая модель — только визуал у тебя на экране.
    -- Вывод: разрушать модель нельзя, это калечит клиент и не даёт респавна. Убрано целиком.
    --
    -- Заодно объясняю `joints=0 head=false` в последнем замере: первые попытки всё снесли,
    -- поэтому на 39-й находить было уже нечего — счётчик показывал ноль на пустой модели.
    --
    -- ═══════ ИГРОВОЙ ПУТЬ: ДОСТАЁМ СЕРВИС ИЗ ПАМЯТИ ═══════
    -- Ты прав: U0 удаляется, но модуль уже был выполнен и его результат ЖИВЁТ в памяти.
    -- Ключевой факт из дампа (SpawnServiceClient:640): `return u1:Get()` — модуль отдаёт
    -- СИНГЛТОН, а `Get` (:68-95) создаёт его один раз с полями:
    --     _spawnRemote, _light, _main, _dead, _clicks, _busy, _respawnInFlight, _janitor
    -- Эта таблица достижима через filtergc даже после удаления скриптов из дерева.
    --
    -- И главное — я ОШИБАЛСЯ в V116, когда написал «через _doRespawn идти НЕЛЬЗЯ, он выходит
    -- без UI смерти». Перепроверил `_doRespawn` (:397-421) и `Init` (:589+):
    --     if not _light or (not _main or (not _spawnRemote or _respawnInFlight)) then return end
    --     ... _spawnRemote:FireServer()
    -- Проверки `_dead` и `_clicks` в нём НЕТ ВООБЩЕ — семь кликов по сердцу гейтятся только в
    -- `_onHeartClick` (:508). А `_light`/`_main` создаются в `_makeDeathUi`, который вызывается
    -- из `Init` СРАЗУ при загрузке, а не в момент смерти. То есть `_doRespawn` доступен всегда,
    -- и вызов его напрямую обходит счётчик кликов. Это и есть игровой способ.
    local _deathInfo = "not attempted"
    local _svc = nil
    -- Ищем синглтон по НАБОРУ уникальных ключей: такая комбинация есть только у него,
    -- поэтому ложных совпадений не будет. filtergc — предпочтительный способ (быстрее getgc).
    local function findSpawnService()
        if type(_svc) == "table" and rawget(_svc, "_spawnRemote") ~= nil then return _svc end
        local ok, res = pcall(function()
            return filtergc("table", {
                Keys = { "_spawnRemote", "_respawnInFlight", "_clicks", "_dead" },
            }, true)
        end)
        if ok and type(res) == "table" then _svc = res end
        return _svc
    end

    -- Достаём сам RemoteEvent. Берём его ИЗ синглтона, а не по имени из ReplicatedStorage:
    -- ссылка живёт в памяти, даже если ремоут уже убрали из дерева.
    local function getMemoryRemote()
        local s = findSpawnService()
        local re = s and rawget(s, "_spawnRemote")
        if typeof(re) == "Instance" and re:IsA("RemoteEvent") then return re end
        return nil
    end

    -- Игровой респавн: тот же путь, которым идёт сама игра после 7 кликов по сердцу.
    local function gameRespawn()
        local s = findSpawnService()
        if not s then _deathInfo = "svc not found in memory"; return false end
        local re = getMemoryRemote()
        -- _respawnInFlight остаётся true после нашей же неудачной попытки (сбрасывается только
        -- в _abortRespawnTransition, :346). Если его не снять, _doRespawn молча выйдет в первой
        -- строке — ровно тот тип «тихого отказа», на котором я уже прогорал. Снимаем принудительно.
        pcall(function() s._respawnInFlight = false end)
        pcall(function() s._busy = false end)
        -- Игра требует _dead для показа UI; ставим, чтобы её же логика не откатила переход.
        pcall(function() s._dead = true end)
        local viaModule = false
        if type(rawget(getmetatable(s) or {}, "_doRespawn")) == "function"
            or type(s._doRespawn) == "function" then
            viaModule = pcall(function() s:_doRespawn() end)
        end
        -- Дублируем прямым выстрелом ремоута из памяти: если _doRespawn упёрся в отсутствие
        -- _light/_main (UI мог быть уничтожен вместе с U0), сервер всё равно получит запрос.
        local viaRemote = false
        if re then viaRemote = pcall(function() re:FireServer() end) end
        _deathInfo = "svc=yes doRespawn=" .. tostring(viaModule)
            .. " remote=" .. tostring(re ~= nil and viaRemote)
        return viaModule or viaRemote
    end

    -- [V124] ГЛАВНЫЙ путь: пересборка персонажа через реролловый LoadCharacter.
    -- Диагностика тут подробная намеренно — прошлые версии молча возвращали false, и я тратил
    -- твоё время на догадки. Теперь каждая причина отказа пишется словами.
    local _lcInfo, _lcBusy = "not attempted", false
    local function loadCharacter()
        if _lcBusy then return false end          -- InvokeServer уже летит, второй не нужен
        local rf = getLoadCharacterRemote()
        if not rf then _lcInfo = "no Remotes.LoadCharacter (RemoteFunction)"; return false end
        _lcBusy = true
        -- Отдельный поток обязателен: InvokeServer БЛОКИРУЕТ поток до ответа сервера, и вызов
        -- из цикла ожидания заморозил бы сам цикл (а с ним и проверку CharacterAdded).
        task.spawn(function()
            local ok, err = pcall(function() return rf:InvokeServer() end)
            _lcInfo = ok and "invoked ok" or ("invoke error: " .. tostring(err))
            _lcBusy = false
        end)
        return true
    end

    -- [V122] ИСПРАВЛЯЮ СВОЁ ЖЕ УТВЕРЖДЕНИЕ ИЗ V120. Я написал, что void-монитор игры зовёт
    -- сервер. Это была ДОГАДКА, и она неверна — перепроверил по всему дампу:
    --     GetVoidThresholdY определён в SpawnServiceUtils:19-21 и не вызывается НИ РАЗУ,
    --     FallenPartsDestroyHeight упоминается только там же.
    -- То есть void-логика игры — мёртвый код, никто тебя за падение не убивает. Работает лишь
    -- движковое уничтожение частей ниже workspace.FallenPartsDestroyHeight, и на него нельзя
    -- опираться как на основной путь. Поэтому бездна теперь — ПОСЛЕДНИЙ резерв, а не второй шаг.
    --
    -- И вторая причина, почему это «тыкало под землю» без результата: старый код дёргал телепорт
    -- КАЖДЫЕ 0.3с. Каждый вызов заново ставил CFrame и сбрасывал набранную скорость падения,
    -- поэтому персонаж болтался под картой вместо того, чтобы провалиться ниже порога.
    -- Теперь телепорт делается ОДИН раз за попытку респавна.
    -- [V123] dropToVoid УДАЛЁН. Он и был причиной «тычусь под землю»: телепортировал тебя под
    -- карту, а убить не мог — void-логика игры это мёртвый код (разбор выше). Толку ноль, вреда
    -- много: ты терял позицию. Разбор оставлен как история решений.

    -- ═══════════════ [V113] ПОЧЕМУ RESPAWN НЕ РАБОТАЛ ═══════════════
    -- Ремоут и путь были верны — я это перепроверил по дампу:
    --   ReplicatedStorage/Remotes/SpawnRequest.RE сущ��ствует и это RemoteEvent
    --   (_remotes_index.json: "ReplicatedStorage.Remotes.SpawnRequest").
    -- Не работал не вызов, а СМЫСЛ: `SpawnRequest` — это не «заспавни меня», а «я мёртв,
    -- верни меня в игру». Сервер обслуживает его только для мёртвого игрока
    -- (IsDeathFlagged по атрибуту Dead, SpawnServiceUtils.lua:25). Живому игроку пустой
    -- FireServer() отклоняется — снаружи это выглядит как «кнопка ничего не делает».
    -- Убить себя обычным способом тоже нель��я: Health серверный, а штатную кнопку
    -- Roblox Reset игра отключает (CoreGuiPolicy.lua:109 SetCore("ResetButtonCallback", false)).
    --
    -- ═══════ [V114] ПУСТОТА БЫЛА НЕВЕРНЫМ ПОДХОДОМ — НУЖЕН ЭКСПЛОИТ ════════
    -- V113 пытался «умереть по правилам игры»: телепорт ниже FallenPartsDestroyHeight, чтобы
    -- сработал монитор пустоты. Не сработало, и это объяснимо — я опирался на вывод, а не на
    -- факт. Порог пустоты (SpawnServiceUtils.lua:19) в клиентском дампе не читает никто, то
    -- есть монитор серверный, и он вправе просто вернуть персонажа назад или вообще
    -- игнорировать телепорт: серверу позиция клиента не указ, он её валидирует. Плюс это
    -- медленно (интервал проверки 0.2с) — «моментально» так не получится.
    --
    -- ПРАВИЛЬНЫЙ ПУТЬ — ЭКСПЛОИТ РЕПЛИКАЦИИ ��ИГНАЛА, а не механика игры.
    -- У Roblox есть whitelist сигналов, которые КЛИЕНТ вправе поднять НА СЕРВЕРЕ. В нём
    -- лежит `Player.Kill`. Документация Potassium (signal.md, replicatesignal) даёт ровно
    -- наш случай как пример «Example without arguments»:
    --        local player = game.Players.LocalPlayer
    --        replicatesignal(player.Kill)   -- "This example will kill the LocalPlayer."
    -- Это настоящая серверная смерть, мгновенная и не тр��бующая ни урона, ни падения,
    -- ни разрешения игры. Именно поэтому обходятся оба прежних тупика: и серверный Health,
    -- и отключённая кнопка Reset (CoreGuiPolicy.lua:109).
    --
    -- ВАЖНО ПРО ПОРЯДОК: авто-респавна в игре НЕТ (в SpawnServiceClient нет ни одного
    -- слушателя Humanoid.Died, ни CharacterAutoLoads), поэтому после смерти обязателен
    -- SpawnRequest. Отсюда цепочка: Kill → ждём флаг Dead → SpawnRequest.
    -- Ремоут дёргаем НАПРЯМУЮ, а не через _doRespawn: тот выходит, если нет UI смерти или
    -- если уже _respawnInFlight (SpawnServiceClient.lua:401).
    local _respawnBusy = false

    -- Достаём сигнал Kill безопасно: в отдельных версиях клиента свойства может не быть,
    -- и тогда простое обращение LocalPlayer.Kill выбросит ошибку.
    local function getKillSignal()
        local ok, sig = pcall(function() return LocalPlayer.Kill end)
        if ok and typeof(sig) == "RBXScriptSignal" then return sig end
        return nil
    end

    -- Есть ли рабочий эксплоит смерти. Проверяем ИМЕННО через cansignalreplicate: без него
    -- мы бы гадали, лежит ли Kill в whitelist'е у этой сборки executor'а/Roblox.
    -- Результат кэшируем: он не меняется в течение сессии (executor и whitelist Roblox
    -- статичны), а Auto Respawn зовёт это каждый кадр — без кэша мы бы вызывали
    -- cansignalreplicate 60 раз в секунду впустую.
    local _canKill = nil
    local function canKillSelf()
        if _canKill ~= nil then return _canKill end
        -- Пишем В КЭШ, а не просто return: иначе положительный результат терялся бы и
        -- проверка вы��олнялась заново каждый кадр (ровно то, от чего кэш и заводился).
        _canKill = false
        if type(replicatesignal) ~= "function" then return _canKill end
        local sig = getKillSignal()
        if not sig then return _canKill end
        if type(cansignalreplicate) == "function" then
            local ok, res = pcall(cansignalreplicate, sig)
            if ok then _canKill = (res == true); return _canKill end
        end
        -- cansignalreplicate может отсутствовать — тогда просто пробуем.
        _canKill = true
        return _canKill
    end

    local function killSelf()
        local sig = getKillSignal()
        if not sig then return false end
        return (pcall(replicatesignal, sig))
    end

    -- ═══════ [V117] ПОЧЕМУ БЫЛО «ПРОСТО ПОДЫХАЮ» БЕЗ РЕСПАВНА ═══════
    -- Проверил дамп, а не предположил:
    --     grep 'SetAttribute("Dead"' по ВСЕМУ клиентскому дампу → НИ ОДНОГО совпадения.
    -- Значит атрибут "Dead" ставит исключительно СЕРВЕР, в своём обработчике смерти.
    -- Убийство через движковый replicatesignal(Player.Kill) идёт МИМО боевой логики игры,
    -- поэтому серверный обработчик может этот атрибут и не выставить. А я в V116 поставил
    -- отправку RespawnRE под условие `if isTrulyDead()`, которое читает ровно этот атрибут.
    -- Итог: персонаж умирает, атрибут не приходит, условие никогда не истинно, RespawnRE
    -- не отправляется ВООБЩЕ. Ровно то, что ты описал: «просто подыхаю».
    -- Гейт убран: RespawnRE шлём безусловно и повторно. Лишний запрос сервер просто
    -- проигнорирует, а вот пропущенный стоит нам всего респавна.
    --
    -- ПРО РЕПЛИКАЦИЮ, где я был неправ, а где нет. Ты прав, что удалять персонажа — тупик,
    -- и destroySelf я удалил ещё в V116. Но причина другая: Instance:Destroy() с клиента НЕ
    -- реплицируется на сервер (репликация Instance-операций односторонняя, server→client;
    -- клиент авторитетно шлёт серверу только физику своих собственных частей и ремоуты).
    -- Поэтому для остальных игроков персонаж НЕ исчезал — он исчезал только у меня, и это
    -- было даже хуже: я терял ту модель, за которой следит watchchar (respawnstuff:385).
    --
    -- ТВОЯ ПОДСКАЗКА ПРО СИГНАЛ РЕСПАВНА — реализована как ПОИСК, а не как догадка.
    -- signal.md даёт getsignalwhitelist(): он возвращает список всех сигналов, которые
    -- Roblox разрешает реплицировать на сервер (поля Parent и Event). Перечисляем его в
    -- рантайме и ищем что-либо respawn/spawn/load-подобное на LocalPlayer. Имя сигнала не
    -- выдумываем — берём из списка, который вернул сам executor.
    --
    -- ПЛЮС ГЛАВНОЕ: ты виде��, как враг ис��езал и появлялся с полным HP — это штатная
    -- dorespawn() игры. Её можно вызвать НАПРЯМУЮ: filtergc ищет функцию по upvalue'ам
    -- (environment.md: поле Upvalues), а у dorespawn ремоут RespawnRE лежит именно в
    -- upvalue (respawnstuff:224). Вызов игровой функции надёжнее ручного FireServer:
    -- вместе с ремоутом она возвращает CoreGui, курсор и снимает эффекты смерти (:232-255).
    -- ═══════ [V118] ЧЕСТНО: В V116/V117 Я ОПИРАЛСЯ НА МЁРТВЫЙ КОД ═══════
    -- Проверил то, что должен был проверить сразу:
    --     ls dumped/ReplicatedStorage        → 141 ребёнок
    --     ls dumped/ReplicatedStorage | grep -i respawn → 0 совпадений
    --     find .v0/gamedump -iname "RespawnRE*"          → 0 совпадений
    -- Инстанса `RespawnRE` в игре НЕТ. А `respawnstuff_LocalScript.lua:15` делает
    --     local RespawnRE = ReplicatedStorage:WaitForChild("RespawnRE")
    -- БЕЗ таймаута — то есть скрипт навсегда висит на этой строке и НИКОГДА не доходит до
    -- своего кода. Весь respawnstuff (экран "RESTART YOUR HEART", 7 кликов, dorespawn) —
    -- мёртвый легаси, который не исполняется. Значит вся моя «находка» V116 и поиск
    -- dorespawn через filtergc в V117 не могли сработать ни при каких ус��овиях:
    -- getRespawnRemote() всегда nil → фильтр по upvalue всегда nil.
    --
    -- ЖИВАЯ система респавна — другая:
    --     U0/.../SpawnService/SpawnServiceClient_ModuleScript.lua
    --       :596  ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SpawnRequest", 60)
    --       :604  u39._spawnRemote = v40          ← ремоут лежит на самом модуле-синглтоне
    --       :397  function u1._doRespawn(u27)     ← реальный респавн
    --       :410  u27._spawnRemote:FireServer()   ← без аргументов (единственный FireServer)
    -- И ремоут `Remotes/SpawnRequest.RE` в дампе РЕАЛЬНО есть. То есть правильный ремоут я
    -- всё это время держал лишь в запасной ветке.
    --
    -- ПОЧЕМУ ТЕПЕРЬ ЗОВЁМ _doRespawn, А НЕ FireServer НАПРЯМУЮ. В :401 стоит гейт:
    --     if not _light or not _main or not _spawnRemote or u27._respawnInFlight then return end
    -- Флаг `_respawnInFlight` ставится в true перед отправкой (:405) и снимается только по
    -- завершении/аборту (:413-420, таймаут 65 секунд). Если он «залип» — а он залипает, если
    -- прошлый респавн не довёл дело до конца, — то ЛЮБОЙ следующий респавн молча выходит.
    -- Это ровно «я просто сдыхаю»: смерть есть, UI смерти есть, а запрос не уходит.
    -- Поэтому перед вызовом флаг принудительно сбрасываем, а затем зовём штатную функцию:
    -- она сама и ремоут дёрнет, и UI/эффекты/курсор вернёт (:406-421).
    --
    -- Синглтон ищем по КЛЮЧАМ таблицы (environment.md, Table filter options → Keys):
    -- у модуля есть и `_spawnRemote`, и `_doRespawn` — такая пара уникальна.
    local _spawnSvc = nil
    local function findSpawnService()
        if _spawnSvc and _spawnSvc._doRespawn then return _spawnSvc end
        if type(filtergc) ~= "function" then return nil end
        local ok, res = pcall(filtergc, "table", { Keys = { "_spawnRemote", "_doRespawn" } }, true)
        if ok and type(res) == "table" and type(res._doRespawn) == "function" then
            _spawnSvc = res
        end
        return _spawnSvc
    end

    -- Вызов штатного респавна игры. Возвращает true, если функция реально вызвана.
    local function callGameRespawn()
        local svc = findSpawnService()
        if not svc then return false end
        -- Снимаем залипший флаг: без этого _doRespawn выйдет на :401 и ничего не сделает.
        pcall(function() svc._respawnInFlight = false end)
        return (pcall(function() svc:_doRespawn() end))
    end

    -- Поиск сигнала возрождения в whitelist'е Roblox (по подсказке пользователя).
    local _respawnSignal, _respawnSignalTried = nil, false
    local function findRespawnSignal()
        if _respawnSignalTried then return _respawnSignal end
        _respawnSignalTried = true
        if type(getsignalwhitelist) ~= "function" or type(replicatesignal) ~= "function" then
            return nil
        end
        local ok, list = pcall(getsignalwhitelist)
        if not ok or type(list) ~= "table" then return nil end
        for _, info in ipairs(list) do
            local ev = tostring(info and info.Event or "")
            local parent = tostring(info and info.Parent or "")
            -- Нас интересуют сигналы игрока, отвечающие за появлени��/загрузку персонажа.
            if parent == "Player" and (ev:find("[Rr]espawn") or ev:find("[Ss]pawn")
                or ev:find("LoadCharacter") or ev:find("[Rr]eset")) then
                local got = pcall(function() _respawnSignal = LocalPlayer[ev] end)
                if got and _respawnSignal then return _respawnSignal end
                _respawnSignal = nil
            end
        end
        return nil
    end

    -- Одна попытка возрождения. Порядок — от самого «родного» к самому грубому.
    -- [V118] Первым идёт ЖИВОЙ _doRespawn игры (со сбросом залипшего _respawnInFlight),
    -- вторым — прямой SpawnRequest:FireServer(), третьим — сигнал из whitelist.
    -- Возвращает вторым значением строку с тем, что реально сработало: без этого мы опять
    -- гадали б��, какой из путей доступен на твоём клиенте.
    -- ═══════ [V121] ТВОЙ ДИАГ ДОКАЗАЛ МОЮ ОШИБКУ В V119/V120 ═══════
    -- На скриншоте: `state: Running | PlatformStand: false | last: via GettingUp -> OK`.
    -- Это и есть ответ, почему «ничего не делает вообще»:
    --   1) reviveViaHumanoidState() возвращал true всегда, когда есть Humanoid — pcall на
    --      ChangeState успешен даже если состояние ничего не поменяло.
    --   2) isUpAgain() возвращал true всегда, когда мы просто ЖИВЫ (state Running).
    --   3) В pushRespawnUntilAlive стояло `if isUpAgain() and attempt <= 2 then up = true`.
    -- Итог: на ПЕРВОЙ попытке цикл объявлял успех и выходил. До эскалации (шея с попытки 3,
    -- бездна с 6-й) дело не доходило НИКОГДА. Скрипт честно писал «OK» и не делал ничего.
    --
    -- Плюс концептуальная ошибка: «подъём» и «респавн» — разные вещи. GettingUp максимум
    -- поднимает на ноги с тем же HP, а тебе нужен НОВЫЙ персонаж с полным HP. Поэтому из
    -- пути респавна GettingUp убран совсем: респавн = форсировать НАСТОЯЩУЮ смерть и дать
    -- серверу возродить нас. Слом шеи идёт сразу с 1-й попытки, без разогрева.
    -- [V123] Ничего не ломаем и не телепортируем. Только игровой путь.
    local function tryRespawnOnce(attempt)
        local via = {}
        -- [V124] Шаг 0 и ГЛАВНЫЙ: LoadCharacter — путь реролла. Единственный, который НЕ
        -- требует, чтобы сервер сначала признал нас мёртвыми. Идёт первым и на 1-й попытке.
        if attempt == 1 and loadCharacter() then via[#via + 1] = "LoadChar" end
        -- Шаг 1: сервис из памяти → s:_doRespawn() + выстрел его же ремоута. Это ровно то,
        -- что делает игра после 7 кликов по сердцу, но без гейта кликов.
        -- Раз в ~0.9с, а не каждые 0.3с: FireServer в цикле — прямой путь к кику за флуд,
        -- а сама игра между нажатиями ждёт 0.6с (_onHeartClick:508).
        -- [V124] Сдвинуто на попытку 4+ (~1.2с): даём LoadCharacter отработать в одиночку.
        -- Иначе в диаге опять была бы каша из путей, и мы не узнали бы, что именно сработало.
        if attempt >= 4 and attempt % 3 == 1 and gameRespawn() then via[#via + 1] = "memSvc" end
        -- Шаг 2: ремоуты, найденные обычным путём в дереве (RespawnRE / Remotes.SpawnRequest) —
        -- на случай, если синглтон в памяти не нашёлся. Условие isTrulyDead убрано: сервер
        -- держит Downed=true, и «мёртв ли я» решает он, а не наша догадка.
        if attempt >= 4 and fireRespawn() then via[#via + 1] = "remote" end
        return #via > 0, table.concat(via, "+")
    end

    -- [V118] Диагностика вместо догадок: сюда пишем, какие пути были доступны и чем всё
    -- закончилось. Кнопка Respawn это показывает, поэтому в следующий раз мы будем разбирать
    -- ФАКТ («_doRespawn не найден», «пути есть, но персонаж не пришёл»), а не мои гипотезы.
    local _respawnDiag = "not attempted yet"

    -- [V121] isUpAgain() УДАЛЁН. Он был причиной «ничего не делает»: возвращал true при любом
    -- живом персонаже (state Running), из-за чего первая же попытка считалась успешной.
    -- Единственный честный признак респавна — CharacterAdded: сервер выдаёт НОВУЮ модель.
    -- Ниже критерий успеха только он, поэтому ложного «OK» больше быть не может.

    local function pushRespawnUntilAlive()
        local up = false
        -- [V120] Настоящий респавн — это НОВЫЙ персонаж, поэтому CharacterAdded здесь главный
        -- критерий успеха: слом шеи и бездна ведут именно к нему.
        local conn = LocalPlayer.CharacterAdded:Connect(function() up = true end)
        _lastRespawnFire = 0            -- снимаем троттлинг для первого выстрела
        _deathInfo = "not attempted"    -- [V123] чистим диаг перед новой серией попыток
        local t0, attempt, seen, order = os.clock(), 0, {}, {}
        while not up and os.clock() - t0 < 12 do
            attempt = attempt + 1
            local _, v = tryRespawnOnce(attempt)
            -- [V122] Логируем каждый путь ОДИН раз. Раньше строка забивалась «void>void>void...»
            -- на 40 повторов, и в ней не было видно ни одного реально сработавшего шага.
            if v ~= "" and not seen[v] then seen[v] = true; order[#order + 1] = v end
            -- [V121] Выходим ТОЛЬКО по CharacterAdded (up ставится в обработчике выше).
            task.wait(0.3)
        end
        if conn then conn:Disconnect() end
        -- [V124] Диаг переписан под новый путь. Раньше он показывал death[joints/head] от
        -- удалённого кода — ты правильно заметил, что информация старая. Теперь главное поле
        -- это LoadChar[...]: по нему сразу видно, найден ли RemoteFunction и что ответил сервер.
        _respawnDiag = "tries=" .. attempt
            .. " paths=" .. (#order > 0 and table.concat(order, ">") or "NONE")
            .. " LoadChar[" .. tostring(_lcInfo) .. "]"
            .. " svc[" .. tostring(_deathInfo) .. "]"
            .. (up and " -> respawned" or " -> no CharacterAdded in 12s")
        return up
    end

    -- Единая точка входа. Возвращает true, если попытка реально начата.
    local function requestRespawn()
        if _respawnBusy then return false end
        -- [V119] Больше НЕ убиваем себя и не требуем ремоута: основной путь — движковый
        -- подъём Humanoid'а, для него нужен только сам Humanoid. Прежние гейты (canKillSelf,
        -- hasRespawnRemote) молча блокировали работу, хотя к подъёму отношения не имеют.
        local c = LocalPlayer.Character
        if not (c and c:FindFirstChildOfClass("Humanoid")) then
            _respawnDiag = "no Humanoid in Character"
            return false
        end
        _respawnBusy = true
        task.spawn(function()
            pushRespawnUntilAlive()
            _respawnBusy = false
        end)
        return true
    end

    local function driveAutoRespawn()
        if not Config.AutoRespawn_On then return end
        -- [V116] И при смерти, и при Downed идём через requestRespawn: он повторяет отправку
        -- до реального CharacterAdded. Одиночный fireRespawn() здесь был ошибкой — если
        -- сервер отбросил первый запрос, второй уже никто не посылал.
        if isTrulyDead() then requestRespawn(); return end
        local c = LocalPlayer.Character
        if c and c:GetAttribute("Downed") == true then requestRespawn(); return end
        -- Порог HP: 0 = выключен (респавн только по смерти/Downed).
        local thr = Config.AutoRespawn_HP or 0
        if thr <= 0 then return end
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if not hum or hum.MaxHealth <= 0 then return end
        if (hum.Health / hum.MaxHealth) * 100 <= thr then requestRespawn() end
    end

    local function driveAntiRagdoll()
        if not Config.AntiRagdoll_On then return end
        local char, hum = getParts()
        if not hum then return end
        -- [V112] Дешёвый выход: пока мы не в рэгдолле, кадр не стоит ничего (одно чтение
        -- атрибута). Прежняя версия при активном хуке возвращалась ещё раньше, но тогда
        -- подъёмом занимался сам GetAttribute-спуф; теперь работу делаем мы.
        if char:GetAttribute("Ragdoll") ~= true then return end
        if isManagedRagdoll(char, hum) then return end
        pcall(_clearRagAttr, char)
        pcall(_forceGetup, hum)
    end

    -- ═════════════════════════ MASTER LOOPS ═════════════════════════════════
    PreStep:Connect(LPH_NO_VIRTUALIZE(function(dt)
        dt = (typeof(dt) == "number" and dt > 0) and dt or (1 / 60)
        pcall(stepSpeed, dt)
        pcall(stepFly, dt)
        pcall(stepNoClip)
    end))
    -- [V112] ЛЕНИВЫЙ PostStep. Преж��е все драйверы вызывались КАЖДЫЙ кадр безусловно, и
    -- каждый сам решал, работать ему или нет — то ес��ь на выключенных фичах мы всё равно
    -- платили за 4 вызова функций на кадр. Теперь проверяем флаги ДО вызова: пока фичи
    -- выключен��, тело цикла — это несколько сравнений булевых полей.
    -- driveDodge вызывается только при Dodge_On (внутри он и так первым делом это проверял),
    -- driveAutoRespawn — новый драйвер респавна по порогу HP.
    PostStep:Connect(LPH_NO_VIRTUALIZE(function()
        if Config.NoDelay_On      then driveNoDelay() end
        if Config.InfStamina_On   then driveInfStamina() end   -- _staminaSeenPositive=false
        if Config.Dodge_On        then driveDodge() end        -- патч DashSpeed/Cooldown
        if Config.AntiRagdoll_On  then driveAntiRagdoll() end  -- подъём из чужого рэгдолла
        if Config.AutoRespawn_On  then driveAutoRespawn() end
        -- keep sprint desired asserted (game clears it after combat cancels)
        if Config.Sprint_On then
            local s = getSprint()
            if s and rawget(s, "_sprintInputDesired") ~= true then
                pcall(_desireOn, s)
            end
        end
    end))

    -- Reset transient state on respawn.
    LocalPlayer.CharacterAdded:Connect(function(char)
        _myChar = char       -- keep the hook's fast-path pointer compare valid after respawn
        flyActive = false
        clearFlyInput()
        table.clear(_noclipTouched)   -- old parts are gone; new char re-uncollides while NoClip on
        table.clear(_partCache)       -- [PERF/leak] the part cache is keyed by the character MODEL
                                      -- with strong keys, so without this the previous character
                                      -- (and its part list) stayed referenced for the whole session
        _carryVictim, _carryCacheT = nil, 0
        _noclipActive = Config.NoClip_On
        -- [V112] Перепривязываем событийный счётчик grab-констрейнтов: подписки жили на
        -- СТАРОМ персонаже, после респавна они мертвы, а счётчик остался бы с прошлым
        -- значением (в т.ч. «нас держат», если нас схватили перед смертью).
        bindGrabWatch(char)
        task.wait(0.5)
        if Config.Sprint_On then setSprint(true) end
    end)

    -- ═════════���═════════���══════════�� UI ══���══════════════════════════════════
    local M = {}

    function M.start()
        Config.Speed_On, Config.Fly_On = false, false
        Config.NS_On, Config.NoDelay_On = false, false
        Config.Sprint_On, Config.Sprint_Bypass = false, false
        -- [V112] Auto Respawn гасим на старте принудительно. Если он приедет включённым из
        -- сохранённого конфига MacLib, скрипт начнёт слать SpawnRequest сразу после
        -- инжекта — то есть будет убивать сессию до того, как игрок вообще увидит меню.
        Config.AutoRespawn_On = false
        -- Warm up the hooks in the background now, so toggling a feature later never
        -- triggers a heap scan on the click (that was the freeze). Inert until a flag flips.
        bootstrapHooks()
        -- [V112] Первичная привязка событийного счётчика grab-констрейнтов для персонажа,
        -- который УЖЕ существует на момент запуска (CharacterAdded для него не сработает).
        bindGrabWatch(LocalPlayer.Character)
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

        -- ─────────────── Section: NoClip (Left) ───────────────
        local sNoClip = MV:Section({ Side = "Left" })
        sNoClip:Header({ Name = "NoClip" })
        feature(sNoClip, {
            Title = "NoClip", Flag = "MV_NoClip",
            get = function() return Config.NoClip_On end,
            set = function(v) Config.NoClip_On = v end,
            Desc = "phase through walls/floors",
        })
        boolToggle(sNoClip, "Carry-Aware", "NoClip Carry-Aware",
            function() return Config.NoClip_Carry end, function(v) Config.NoClip_Carry = v end)
        sNoClip:SubLabel({ Text = "u can carry someone w noclip" })

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

        -- ─���──────��────── Section 4: Combat exploits (Right) ��──────────────
        local sCbt = MV:Section({ Side = "Right" })
        sCbt:Header({ Name = "No Delay" })
        feature(sCbt, {
            Title = "No Delay", Flag = "MV_NoDelay",
            get = function() return Config.NoDelay_On end,
            set = function(v)
                Config.NoDelay_On = v
                if v then
                    -- [V112] Прежний код ждал флаг `_delayHooked` — переменную удалённого
                    -- хука task.delay. После удаления хука она стала ГЛОБАЛЬНЫМ nil, то е��ть
                    -- условие всегда ложно и тумблер врал «hookfunction unavailable» даже
                    -- когда No Delay реально работал. Теперь ждём настоящий признак —
                    -- успешный резолв карты upvalue'ов tryM1 (installNoDelay).
                    bootstrapHooks()
                    task.spawn(function()
                        local ok = false
                        for _ = 1, 8 do
                            ok = installNoDelay()
                            if ok then break end
                            task.wait(0.4)
                        end
                        notify("No Delay", ok and "ON (M1 cooldowns cleared)"
                            or "нужен debug.getupvalue / модуль M1 не найден")
                    end)
                else
                    notify("No Delay", "Disabled")
                end
            end,
            Desc = "clears M1 cooldowns (0.45/1.25/1.55s) via tryM1 upvalues\nplus the server gate attributes, parry FX stays intact",
        })
        sCbt:SubLabel({ Text = "Damage is server-side \u{00b7} only the client-side wait is removed" })

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

        -- ─────────────── Section: Infinite Stamina (Right) ───────────────
        local sStam = MV:Section({ Side = "Right" })
        sStam:Header({ Name = "Infinite Stamina" })
        feature(sStam, {
            Title = "Infinite Stamina", Flag = "MV_InfStamina",
            get = function() return Config.InfStamina_On end,
            set = function(v) Config.InfStamina_On = v end,
            Desc = "wow is this inf stamina??",
        })
        sStam:SubLabel({ Text = "inf stamina (ud)" })

        -- ─────────────── Section 6: Dodge (Left) ───────────────
        local sDodge = MV:Section({ Side = "Left" })
        sDodge:Header({ Name = "Dodge" })
        feature(sDodge, {
            Title = "Dodge", Flag = "MV_Dodge",
            get = function() return Config.Dodge_On end,
            set = function(v)
                if v then
                    if not getEvasive() then
                        notify("Dodge", "Evasive module not found yet"); Config.Dodge_On = false; return
                    end
                    Config.Dodge_On = true
                    if not installEvasiveHook() then
                        notify("Dodge", "custom cooldown needs hookfunction (speed still works)")
                    end
                    driveDodge()          -- apply current slider values immediately
                else
                    Config.Dodge_On = false
                    restoreDodge()        -- put the game's own numbers back
                end
            end,
            Desc = "tweaks ur OWN dodge",
        })
        boolToggle(sDodge, "Dodge Everywhere", "Dodge Everywhere",
            function() return Config.Dodge_Everywhere end,
            function(v)
                if v then
                    -- [V112] Больше не требуется hookmetamethod/getnamecallmethod: обход
                    -- гейтов делает обёртка Evasive (installEvasiveHook), а её ставит
                    -- сам тумблер Dodge. Требуем только её.
                    if not installEvasiveHook() then
                        notify("Dodge Everywhere", "hookfunction required (Evasive wrapper failed)")
                        return
                    end
                    Config.Dodge_Everywhere = true
                    driveDodge()          -- assert the grant immediately
                else
                    Config.Dodge_Everywhere = false
                    clearDodgeGrant()     -- drop the bypass → cooldown/gates return to normal
                end
            end)
        sDodge:SubLabel({ Text = "Enable it to set cooldown (hook startup)" })
        slider(sDodge, { Name = "Dodge Speed", Flag = "MV_DodgeSpeed", Default = Config.Dodge_Speed,
            Min = 1, Max = 150, Suffix = " studs", Callback = function(v)
                Config.Dodge_Speed = v; driveDodge() end })
        slider(sDodge, { Name = "Cooldown", Flag = "MV_DodgeCD", Default = Config.Dodge_Cooldown,
            Min = 0, Max = 1.5, Precision = 2, Suffix = " s", Callback = function(v)
                Config.Dodge_Cooldown = v; driveDodge() end })
        sDodge:SubLabel({ Text = "client-side cooldown" })

        -- ─────────────── Section: Anti-Ragdoll (Right) ���──────────────
        local sAR = MV:Section({ Side = "Right" })
        sAR:Header({ Name = "Anti-Ragdoll" })
        feature(sAR, {
            Title = "Anti-Ragdoll", Flag = "MV_AntiRagdoll",
            get = function() return Config.AntiRagdoll_On end,
            set = function(v)
                Config.AntiRagdoll_On = v
                -- [V112] Точечный хук sustainClientRagdoll вместо глобального __namecall.
                -- ��ез него подъём всё равно работает, но игра может утаскивать назад в
                -- рэгдолл (та самая гонка), поэтому предупреждаем честно.
                if v and not installAntiRagdollHook() then
                    notify("Anti-Ragdoll", "hookfunction + debug.getupvalue required")
                end
            end,
            Desc = "forces getup out of ragdolls by muting sustainClientRagdoll\ncarry / grip / Downed are left alone",
        })
        sAR:SubLabel({ Text = "Downed / carry / finisher are skipped to keep gameplay intact" })

        -- ─────────────── [V112] Section: No Blur (Left) ───────────────
        local sBlur = MV:Section({ Side = "Left" })
        sBlur:Header({ Name = "No Blur" })
        feature(sBlur, {
            Title = "No Blur", Flag = "MV_NoBlur",
            get = function() return Config.NoBlur_On end,
            set = function(v)
                Config.NoBlur_On = v
                if v then
                    if not installNoBlur() then
                        notify("No Blur", "ScreenEffects module not found")
                        Config.NoBlur_On = false
                        return
                    end
                    clearActiveBlur()   -- снять блюр, который уже висит на экране
                end
            end,
            Desc = "removes combat blur: hits, Downed, grip,\ndeath, Black Flash, falling",
        })
        sBlur:SubLabel({ Text = "Menu and panel blur is untouched, it is part of the normal UI" })

        -- ─────────────── [V112] Section: Respawn (Left) ───────────────
        local sResp = MV:Section({ Side = "Left" })
        sResp:Header({ Name = "Respawn" })
        sResp:Button({
            Name = "Respawn Now",
            Callback = function()
                -- [V119] Единственное реальное требование — наличие Humanoid'а: подъём делает
                -- движковая state-машина, а не механика игры. Проверки ремоутов убраны, они
                -- лишь молча блокировали кнопку.
                local _c = LocalPlayer.Character
                if not (_c and _c:FindFirstChildOfClass("Humanoid")) then
                    notify("Respawn", "no Humanoid in Character"); return
                end
                -- [V116] Жив → нужен Player.Kill, иначе умереть нечем и врать «отправлено»
                -- нельзя. destroySelf удалён, поэтому обходного пути без него больше нет.
                if not isTrulyDead() and not canKillSelf() then
                    notify("Respawn", "replicatesignal(Player.Kill) unavailable on this executor")
                    return
                end
                if isTrulyDead() then
                    notify("Respawn", requestRespawn() and "Respawning"
                        or "Too soon, wait a couple of seconds")
                else
                    notify("Respawn", requestRespawn() and "Resetting character"
                        or "Already in progress")
                end
            end,
        })
        boolToggle(sResp, "Auto Respawn", "Auto Respawn",
            function() return Config.AutoRespawn_On end,
            function(v) Config.AutoRespawn_On = v end)
        slider(sResp, { Name = "HP Threshold", Flag = "MV_AutoRespawnHP",
            Default = Config.AutoRespawn_HP, Min = 0, Max = 99, Suffix = "%",
            Callback = function(v) Config.AutoRespawn_HP = v end })
        -- [V118] Кнопка диагностики: показывает, какие пути респавна реально нашлись на твоём
        -- клиенте и чем закончилась последняя попытка. Нужна, чтобы в следующий раз разбирать
        -- факт, а не мои предположения.
        sResp:Button({
            Name = "Respawn Diag",
            Callback = function()
                -- [V124] ДЕБАГ ОБНОВЛЁН — ты верно сказал, что тут была старая информация.
                -- Убрал RequiresNeck / BreakJoints: они относились к слому шеи, а этого кода
                -- больше нет (V123 доказал, что форсировать смерть с клиента бесполезно).
                -- Теперь показываем то, что решает СЕЙЧАС: есть ли RemoteFunction LoadCharacter
                -- (главный путь реролла), готов ли персонаж по атрибуту самой игры, и что
                -- вернула последняя попытка.
                local c = LocalPlayer.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                local st = hum and tostring(hum:GetState()):gsub("^Enum.HumanoidStateType%.", "") or "no humanoid"
                -- CharacterGenReady — атрибут ИГРОКА, по которому сама игра понимает, что
                -- персонаж собран (CharacterServiceUtils:1464, ждёт его после реролла).
                notify("Respawn Diag", "state: " .. st
                    .. " | Downed: " .. tostring(c and c:GetAttribute("Downed"))
                    .. " | Dead: " .. tostring(LocalPlayer:GetAttribute("Dead"))
                    .. " | GenReady: " .. tostring(LocalPlayer:GetAttribute("CharacterGenReady"))
                    .. " | LoadCharacter RF: " .. tostring(getLoadCharacterRemote() ~= nil)
                    .. " | last: " .. tostring(_respawnDiag))
            end,
        })
        sResp:SubLabel({ Text = "0% = on death/Downed only \u{00b7} rebuilds character via Remotes.LoadCharacter (the reroll path)" })

        uiReady = true
    end

    return M
end
