return function(Lib)
    local Bridge    = Lib.Bridge
    local CONFIG    = Lib.CONFIG
    local State     = Lib.State

    local Players    = game:GetService("Players")
    local RunService = Bridge._RunService or game:GetService("RunService")
    local UIS        = game:GetService("UserInputService")
    local Workspace  = game:GetService("Workspace")
    local LP         = Players.LocalPlayer

    -- Console spam disabled: shadow the global `print` with a no-op for this whole
    -- module. The diagnostic-file buffer (see log()/runDiagnostic) still records
    -- lines; only console output is silenced. `warn` is left intact for real errors.
    local print = function() end

    local MOV = {

        Speed          = true,
        SpeedToggleKey = Enum.KeyCode.X,
        SpeedValue     = 24,
        SprintKey      = Enum.KeyCode.LeftShift,
        SprintSpeed    = 42,
        AutoSprint     = false,

        FlyToggleKey   = Enum.KeyCode.G,
        FlySpeed       = 28,
        FlyUpKey       = Enum.KeyCode.Space,
        FlyDownKey     = Enum.KeyCode.LeftControl,
        FlyPersist     = true,
        FlyTPBypass    = true,

        -- v19.2: сохранять ВСЕ включённые фичи (fly/fakeangles/velocitydesync/
        -- noclip/speed/invis/tp) после смерти — не нужно включать заново.
        PreserveStateOnDeath = true,

        StraferKey     = Enum.KeyCode.V,

        SpeedStateKey   = Enum.KeyCode.C,
        SpeedStateOrder = { "Skydiving", "Parachuting", "Proning" },

        LeanLockKey    = Enum.KeyCode.L,
        LeanLockValue  = 1,

        InvisibleKey     = Enum.KeyCode.U,
        InvisibleYOffset = -2.8,
        InvisibleProne   = true,
        InvisibleLean    = true,
        InvisibleJitter  = 0,

        FakeAnglesKey      = Enum.KeyCode.J,
        FakeAnglesJitter   = 2.8,   -- yaw swing (rad) per packet flip
        FakeAnglesPitchAmp = 1.4,   -- pitch swing (rad) up/down
        -- ⚠ КЛЮЧЕВОЕ (фикс «десинк меня / урон не регистрируется»):
        --   Пакет ReplicateMovement несёт ОДИН набор углов, который сервер
        --   отдаёт другим игрокам И использует для валидации ТВОИХ выстрелов:
        --     a[6]=Orientation (yaw ТЕЛА) — что видят враги, для стрельбы НЕ важен.
        --     a[9]=CameraX (yaw ПРИЦЕЛА), a[10]=CameraY (pitch ПРИЦЕЛА) — твой
        --        реальный прицел; сервер по нему проверяет попадания. Если их
        --        подменить — сервер считает выстрел невозможным → урон не идёт,
        --        а античит откатывает позицию («телепорт назад»).
        --   Поэтому по умолчанию крутим ТОЛЬКО тело (a[6]) и наклон (a[11]),
        --   а ПРИЦЕЛ (a[9]/a[10]) оставляем настоящим. Враги всё равно
        --   десинкаются по интерполяции тела, а ты стреляешь и стоишь как надо.
        FakeAnglesYaw      = true,   -- крутить yaw ТЕЛА    (a[6])  — безопасно
        FakeAnglesLean     = true,   -- крутить наклон      (a[11]) — безопасно
        FakeAnglesAimYaw   = false,  -- крутить yaw ПРИЦЕЛА (a[9])  ⚠ ломает хитрег
        FakeAnglesPitch    = false,  -- крутить pitch ПРИЦЕЛА (a[10]) ⚠ ломает хитрег
        -- ⚠ ФИКС ФРИЗА (Jitter/Twitch/Break/Chaos): держим ВКЛ. Гарантирует, что
        --   каждый пакет валиден (конечные углы, реальный HeightState, позиция не
        --   тронута) → сервер не отбрасывает пакет → нет «стою на месте» и отката.
        --   Выключай только если точно знаешь, что делаешь.
        FakeAnglesClampSafe = true,
        FakeAnglesSpinStep = 0.9,   -- yaw advance per packet in Spin mode
        FakeAnglesGhost    = true,  -- show fake as a cloned model
        FakeAnglesGhostTransparency = 0.5,
        FakeAnglesGhostMaterial = Enum.Material.Glass,       -- «жидкое стекло»
        FakeAnglesGhostColor    = Color3.fromRGB(120, 200, 255),
        FakeAnglesGhostOutline  = Color3.fromRGB(180, 235, 255),
        -- ── State-спуф: подменяем HeightState (a[8]) чтобы сервер думал что мы
        --    сидим/лежим → десинк по высоте хитбокса.
        -- ⚠ ПОЧЕМУ ПО УМОЛЧАНИЮ ВЫКЛ: если сервер думает что мы Proning/Crouching,
        --    он применяет ограничения скорости этого стейта. Наша РЕАЛЬНАЯ скорость
        --    бега выглядит невозможной для прона → сервер откатывает нас назад
        --    (тот самый «телепорт при выключении»), а спуфнутый хитбокс ломает
        --    регистрацию ударов. Чистый yaw-jitter (только a[6]) этого не вызывает.
        --    Включай осознанно, если конкретный сервер это не валидирует.
        FakeAnglesStateSpoof  = false,          -- чередовать стейты в любом фейк-режиме
        FakeAnglesStateCycle  = { "Crouching", "Proning", "Standing" }, -- что чередовать
        FakeAnglesStateHold   = 8,              -- пакетов на один стейт (медленнее = виднее)
        FakeAnglesForceState  = nil,            -- "Crouching"/"Proning"/... — зафиксировать один
        FakeAnglesCrouchDrop  = 1.4,            -- насколько опустить гост в Crouch (studs)
        FakeAnglesProneDrop   = 2.4,            -- насколько опустить гост в Prone (studs)
        FakeAnglesGhostFirstPersonHide = true,  -- прятать гост в 1-м лице
        -- Порог первого лица: используем СОБСТВЕННЫЙ сигнал игры LocalActor.Zoom<=0
        -- (CharacterCamera:154 v36 = Zoom>0 = третье лицо). Camera-дистанция — fallback.
        FakeAnglesGhostFPZoom = 0.5,            -- Zoom < этого → первое лицо
        FakeAnglesGhostFPDist = 1.5,            -- fallback: камера ближе → первое лицо
        -- ── «Нереальные» тест-значения (Break/Chaos). ВНИМАНИЕ: транспорт —
        --    HttpService:JSONEncode (Flux_client:104). JSON НЕ кодирует inf/NaN →
        --    пакет бросает ошибку и НЕ уходит (= «стою на месте»). Поэтому шлём
        --    экстремальные КОНЕЧНЫЕ значения, которые JSON закодирует.
        FakeAnglesUnrealValue = 1e18,           -- «бесконечность» в конечном виде
        FakeAnglesUnrealState = 1e9,            -- «нереальный» HeightState

        -- ── Способ отправки фейк-углов ────────────────────────────────────────
        -- ВАЖНО (фикс «стою на месте»): раньше по умолчанию мы ГЛУШИЛИ штатный
        -- 10Гц-пакет игры и слали свой из отдельного Sender'а. Если Sender не мог
        -- прочитать живую позицию (ForceNextPosition обнулялся игрой, кэш
        -- контроллера устаревал) — уходило НИЧЕГО, и сервер видел нас застывшими.
        --
        -- Теперь по умолчанию модифицируем ПАКЕТ ИГРЫ НА МЕСТЕ (in-place): игра
        -- сама шлёт настоящую позицию каждые 0.1с, а мы лишь подменяем углы
        -- (a[6]=Orientation, a[10]=CameraY, a[11]=Lean) и стейт (a[8]). Позиция
        -- ВСЕГДА настоящая → jitter/unreal реально уходят на сервер.
        FakeAnglesSender       = false, -- (опц.) отдельный высокочастотный Sender
        FakeAnglesSendHz       = 22,    -- целевы��� Г�� Sender'а, если включён
        FakeAnglesSendBurstCap = 3,     -- макс пакетов за кадр Sender'а
        FakeAnglesSuppressGame = false, -- НЕ глушить штатный пакет (in-place десинк)

        -- ── ДИАГНОСТИКА (жми K чтобы вкл/выкл лог) ────────────────────────────
        -- Печатает первые FakeAnglesDiagCount ИСХОДЯЩИХ ReplicateMovement-пакетов:
        -- РЕАЛЬНЫЕ X/Y/Z (позиция — должна совпадать с настоящей!) и ОТПРАВЛЕННЫЙ
        -- Orientation/HeightState. Так видно: (1) пакеты реально уходят, (2) позиция
        -- не тронута, (3) угол/стейт действительно подменяются. Смотри консоль.
        FakeAnglesDiag      = false,
        FakeAnglesDiagKey   = Enum.KeyCode.K,
        FakeAnglesDiagCount = 20,       -- сколько пакетов залогировать после включения

        -- ── VelocityDesync ───────────────────────────────────────────────────
        -- Смещаем ОТПРАВЛЯЕМУЮ позицию вдоль вектора скорости, чередуя знак
        -- каждый пакет. Серверная модель «плывёт» по физике, локальный CFrame
        -- остаётся корректным → классический velocity-десинк.
        VelocityDesyncKey    = Enum.KeyCode.Y,  -- (V занят StraferKey)
        VelocityDesyncAmp    = 3.0,    -- амплитуда смещения (studs)
        VelocityDesyncUseVel = true,   -- масштабировать по скорости (иначе фикс. амп)
        VelocityDesyncVertical = 0.0,  -- доп. вертикальное смещение (studs)

        NoFallKey       = Enum.KeyCode.B,

        ThirdPersonKey       = Enum.KeyCode.T,
        ThirdPersonDist      = 16,
        ThirdPersonMax       = 25,
        ThirdPersonWheelStep = 1.5,
        ThirdPersonPinchSens = 10,
        ThirdPersonMobileGui = true,

        NoClip    = false,
        NoClipKey = Enum.KeyCode.N,

        InfiniteJump = false,
        BunnyHop     = false,
        SuperJumpKey = Enum.KeyCode.H,
        SuperJumpVel = 55,

        SpinBotKey = Enum.KeyCode.Z,
        SpinBotRPS = 6,

        AntiVoid      = false,
        AntiVoidY     = -50,
        AntiVoidSafeY = 50,

        LeanSprint = false,
        LeanAngle  = 4,

        DiagKey    = Enum.KeyCode.RightBracket,
        DebugKey   = Enum.KeyCode.LeftBracket,
        DumpNilKey = Enum.KeyCode.K,
    }

    local function now() return os.clock() end
    local function getCamera() return Workspace.CurrentCamera end

    local function isLiveInputActive()
        if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.A)
        or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.D) then
            return true
        end
        local ok, gp = pcall(function() return UIS:GetGamepadState(Enum.UserInputType.Gamepad1) end)
        if ok and gp then
            for _, s in ipairs(gp) do
                if s.KeyCode == Enum.KeyCode.Thumbstick1 and s.Position.Magnitude > 0.15 then
                    return true
                end
            end
        end
        if UIS.TouchEnabled then
            local okT, touches = pcall(function() return UIS:GetTouches() end)
            if okT and touches and #touches > 0 then return true end
        end
        return false
    end

    local knownGoodLA = nil

    local activeCtrlRef = nil

    local liveCtrl, liveCtrlT = nil, -999
    local liveCam,  liveCamT  = nil, -999
    local LIVE_TTL = 0.5  -- self считается "живым", если Update дёргал его < 0.5с назад (~30 кадров)

    local hooksSetup    = false
    local camHooksSetup = false

    local logBuf = {}
    local function log(...)
        local p = {}; for _, v in ipairs({...}) do p[#p+1] = tostring(v) end
        local line = table.concat(p, "\t"); logBuf[#logBuf+1] = line; print(line)
    end
    local function flushLog(f)
        local c = table.concat(logBuf, "\n")
        if type(writefile)    == "function" then pcall(writefile,    f, c) end
        if type(setclipboard) == "function" then pcall(setclipboard, c) end
        print("[MOV] Диагностика → " .. f); logBuf = {}
    end

    local function isCtrl(t)
        if type(t) ~= "table" then return false end
        if type(rawget(t,"MoveSpeed"))       ~= "number"  then return false end
        if type(rawget(t,"VelocityGravity")) ~= "number"  then return false end
        if type(rawget(t,"TrySprinting"))    ~= "boolean" then return false end
        if type(rawget(t,"IsGrounded"))      ~= "boolean" then return false end
        if type(rawget(t,"IsSprinting"))     ~= "boolean" then return false end
        local la = rawget(t, "_localActor")
        if type(la) ~= "table" then return false end

        local alive = rawget(la, "Alive")
        if alive == false then return false end

        local ilp = rawget(la, "IsLocalPlayer")
        if ilp == false then return false end

        local backRef = rawget(la, "Controller")
        if type(backRef) == "table" and not rawequal(backRef, t) then
            return false
        end

        return true
    end

    local function isCam(t)
        if type(t) ~= "table" then return false end
        if rawget(t,"_zoomLimit")   == nil then return false end
        if rawget(t,"_shoulderLerp") == nil then return false end
        if rawget(t,"_lastWalkAngle") == nil then return false end
        local la = rawget(t, "_localActor")
        if type(la) ~= "table" then return false end
        if knownGoodLA ~= nil and not rawequal(la, knownGoodLA) then
            return false
        end
        return true
    end

    local function isNetObj(v)
        if type(v) ~= "table" then return false end
        local code=rawget(v,"_code"); local key=rawget(v,"_key"); local evts=rawget(v,"_events")
        if not (type(code)=="string" and #code>4 and type(key)=="table" and type(evts)=="table") then return false end
        local ok, fs = pcall(function() return v.FireServer end)
        return ok and type(fs)=="function"
    end

    local nilCache, nilCacheT = nil, -999
    local function getNilInstances()
        local t = now()
        if nilCache and t-nilCacheT < 2.5 then return nilCache end
        if type(getnilinstances) ~= "function" then return nil end
        local ok, nils = pcall(getnilinstances)
        if not ok or type(nils) ~= "table" then return nil end
        nilCache=nils; nilCacheT=t; return nils
    end

    local function scanScriptForNet(inst)
        if type(getscriptclosure) ~= "function" then return nil end
        local ok, fn = pcall(getscriptclosure, inst)
        if not ok or type(fn) ~= "function" then return nil end
        for i = 1, 512 do
            local ou, _, uv = pcall(debug.getupvalue, fn, i)
            if not ou or uv == nil then break end
            if isNetObj(uv) then return uv end
        end
        return nil
    end

    local function findNetworkObj()
        if type(State.networkModule)=="table" and isNetObj(State.networkModule) then
            return State.networkModule
        end
        if type(filtergc)=="function" then
            local ok, gc = pcall(filtergc,"table",{Keys={"_code","_key","_events","_functions"}})
            if ok and type(gc)=="table" then
                for _, v in ipairs(gc) do
                    if isNetObj(v) then State.networkModule=v; return v end
                end
            end
        end
        local nils = getNilInstances()
        if nils then
            for _, inst in ipairs(nils) do
                local okC, cls = pcall(function() return inst.ClassName end)
                if okC and (cls=="LocalScript" or cls=="ModuleScript") then
                    local net = scanScriptForNet(inst)
                    if net then State.networkModule=net; return net end
                end
            end
        end
        return nil
    end

    local function findCtrlViaFiltergc()
        if type(filtergc) ~= "function" then return nil end
        if hooksSetup then return nil end
        local ok, gc = pcall(filtergc,"table",{
            Keys={"MoveSpeed","VelocityGravity","TrySprinting","IsGrounded","IsSprinting"}
        })
        if not ok or type(gc) ~= "table" then return nil end
        for _, v in ipairs(gc) do if isCtrl(v) then return v end end
        return nil
    end

    local lastExpensiveScanT = -999
    local EXPENSIVE_SCAN_CD = 0.75

    local function findCtrlViaGetgc()
        if type(getgc) ~= "function" then return nil end
        if hooksSetup then return nil end
        local t = now()
        if t - lastExpensiveScanT < EXPENSIVE_SCAN_CD then return nil end
        lastExpensiveScanT = t
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then return nil end
        for _, fn in ipairs(gc) do
            if type(fn) ~= "function" then continue end
            for i = 1, 64 do
                local ou, _, uv = pcall(debug.getupvalue, fn, i)
                if not ou or uv==nil then break end
                if isCtrl(uv) then return uv end
            end
        end
        return nil
    end

    local function findCamViaFiltergc()
        if type(filtergc) ~= "function" then return nil end
        if camHooksSetup then return nil end
        local ok, gc = pcall(filtergc,"table",{
            Keys={"_zoomLimit","_shoulderLerp","_lastWalkAngle"}
        })
        if not ok or type(gc) ~= "table" then return nil end
        for _, v in ipairs(gc) do if isCam(v) then return v end end
        return nil
    end

    local function findCamViaGetgc()
        if type(getgc) ~= "function" then return nil end
        if camHooksSetup then return nil end
        local t = now()
        if t - lastExpensiveScanT < EXPENSIVE_SCAN_CD then return nil end
        lastExpensiveScanT = t
        local ok, gc = pcall(getgc, true)
        if not ok or type(gc) ~= "table" then return nil end
        for _, fn in ipairs(gc) do
            if type(fn) ~= "function" then continue end
            for i = 1, 64 do
                local ou, _, uv = pcall(debug.getupvalue, fn, i)
                if not ou or uv==nil then break end
                if isCam(uv) then return uv end
            end
        end
        return nil
    end

    local flyActive      = false
    local wantFly        = false
    local straferActive  = false
    local tpActive       = false
    local spinBotActive  = false
    local spinPhase      = 0
    local bhopPrevGrounded = false
    local speedStateMode  = 0
    local speedU18        = nil
    local hsEnumByName    = nil   -- { ["Skydiving"]=enumVal, ["Proning"]=enumVal, ... }
    local forcedHS        = nil
    local proneHS         = nil
    local leanLockActive  = false
    local invisActive     = false
    local fakeAngMode     = 0
    local fakeAngPhase    = 0
    local faFakeLean      = 0
    local invPhase        = 0
    local noFallActive    = false
    local nfFalling       = false
    local nfGroundHS      = nil
    local faPacket        = 0
    local faRealYaw       = 0
    local faFakeYaw       = 0        -- a[6]  Orientation (body yaw), radians
    local faFakeAimYaw    = 0        -- a[9]  CameraX (aim yaw), radians
    local faRealPitch     = 0
    local faFakePitch     = 0        -- a[10] CameraY (pitch), radians
    local faFakeHS        = nil      -- a[8]  спуфнутый HeightState (для виза)
    local faFakeHSName    = nil      -- имя спуфнутого стейта ("Crouching"/...)
    local faStatePkt      = 0        -- счётчик для чередования стейтов
    local faDiagLeft      = 0        -- сколько диаг-пакетов ещё залогировать
    local faGhostModel    = nil
    local faGhostHidden   = false    -- скрыт ли гост (первое лицо)
    local faGhostHL       = nil
    local faGhostRoot     = nil      -- PrimaryPart/HRP клона
    local faGhostHead     = nil      -- голова клона (для показа aim yaw/pitch)
    local faGhostHeadOff  = nil      -- нейтральный оффсет головы относительно root
    local faGhostTorsoM   = nil      -- Motor6D UpperTorso (lean-roll как в игре)
    local faGhostHeadM    = nil      -- Motor6D Head (pitch как в игре)
    local lastMoveInputT = 0

    -- ── Sender / VelocityDesync state ──
    local velDesyncActive = false
    local faUid           = nil      -- uid из штатных пакетов игры (a[2])
    local faSenderAccum   = 0        -- аккумулятор для целевой частоты
    local faSenderFlip    = -1       -- знак флипа углов на каждый Sender-пакет
    local faSenderPkt     = 0
    local faLastPos       = nil      -- для численной оценки скорости
    local faLastPosT      = 0
    local faVelEst        = Vector3.zero
    local faSenderLastSendT = -999   -- когда Sender реально отправил пакет
    local faSenderArgs    = {}       -- переиспользуемая таблица пакета (0 аллокаций)
    local faRealState     = nil      -- реальный HeightState (a[8]) до подмены

    -- ── ФИКС ДЕСИНКА СЕБЯ (Jitter/Twitch/Break/Chaos) ─────────────────────────
    -- Причина фриза: сервер валидирует пакет ReplicateMovement ЦЕЛИКОМ. Если
    -- углы = мусор (1e18) или HeightState (a[8]) невалиден (1e9) — сервер
    -- ОТБРАСЫВАЕТ весь пакет, включая твою реальную позицию (a[3..5]). Позиция
    -- перестаёт обновляться на сервере → «стою на месте» → откат при выключении.
    --
    -- Решение: перед отправкой ГАРАНТИРУЕМ, что пакет всегда валиден:
    --   • углы — конечные и в разумном диапазоне (yaw/lean оборачиваем, pitch
    --     клампим) — враги всё равно видят «сломанную» ориентацию, но пакет
    --     принимается;
    --   • a[8] — всегда РЕАЛЬНЫЙ enum HeightState (никогда 1e9);
    --   • позицию (a[3..5]) НЕ трогаем — она уходит настоящей → нет отката.
    local TWO_PI = math.pi * 2
    local function wrapPi(x)          -- в диапазон [-π, π]
        if type(x) ~= "number" then return x end
        if x ~= x or x == math.huge or x == -math.huge then return 0 end  -- NaN/inf → 0
        x = x % TWO_PI
        if x > math.pi then x = x - TWO_PI end
        return x
    end
    local function isValidHS(v)       -- v входит в набор валидных HeightState?
        if type(v) ~= "number" or not hsEnumByName then return false end
        for _, hv in pairs(hsEnumByName) do if hv == v then return true end end
        return false
    end
    -- Финализатор: делает пакет гарантированно принимаемым сервером.
    local function sanitizeFakePacket(a, n)
        if MOV.FakeAnglesClampSafe == false then return end   -- можно отключить
        if type(a[6])  == "number" then a[6]  = wrapPi(a[6]) end
        if type(a[9])  == "number" then a[9]  = wrapPi(a[9]) end   -- yaw прицела (если крутим)
        if type(a[10]) == "number" then                            -- pitch: реальные пределы камеры
            local p = a[10]
            if p ~= p or p == math.huge or p == -math.huge then p = 0 end
            a[10] = math.clamp(p, -1.4, 1.4)
        end
        if n >= 11 and type(a[11]) == "number" then                -- lean: [-1, 1]
            local l = a[11]
            if l ~= l or l == math.huge or l == -math.huge then l = 0 end
            a[11] = math.clamp(l, -1, 1)
        end
        if n >= 8 and type(a[8]) == "number" and not isValidHS(a[8]) then
            -- невалидный стейт → возвращаем реальный (или Standing как fallback)
            a[8] = (isValidHS(faRealState) and faRealState)
                or (hsEnumByName and hsEnumByName.Standing)
                or faRealState
        end
    end

    -- Применяет текущий режим FakeAngles к args-пакету (a[6]=Orientation,
    -- a[9]=CameraX, a[10]=CameraY, a[11]=LeanGoal). Общий код для штатного
    -- хука и для высокочастотного Sender'а — единый источник истины.
    local function applyFakeAnglesToArgs(a, n, flip)
        if type(a[6])  == "number" then faRealYaw   = a[6]  end
        if type(a[10]) == "number" then faRealPitch = a[10] end
        if type(a[8])  == "number" and isValidHS(a[8]) then faRealState = a[8] end
        local realYaw = faRealYaw or (type(a[6]) == "number" and a[6]) or 0
        local jit  = MOV.FakeAnglesJitter or 2.8
        local pAmp = MOV.FakeAnglesPitchAmp or 1.4
        local TAU  = math.pi * 2
        if fakeAngMode == 1 then          -- Instant: max-rate flip
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = a[6] + flip * jit end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = a[9] + flip * jit end
            if MOV.FakeAnglesPitch  and type(a[10]) == "number" then a[10] = flip * pAmp end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = flip end
        elseif fakeAngMode == 2 then      -- Spin
            fakeAngPhase = (fakeAngPhase + (MOV.FakeAnglesSpinStep or 0.9)) % TAU
            if type(a[6]) == "number" then a[6] = fakeAngPhase end
            if MOV.FakeAnglesAimYaw and type(a[9]) == "number" then a[9] = fakeAngPhase end
            if MOV.FakeAnglesPitch and type(a[10]) == "number" then a[10] = pAmp * 0.6 end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = flip end
        elseif fakeAngMode == 3 then      -- Random
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = math.random() * TAU end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = math.random() * TAU end
            if MOV.FakeAnglesPitch and type(a[10]) == "number" then a[10] = (math.random() * 2 - 1) * pAmp end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = math.random() * 2 - 1 end
        elseif fakeAngMode == 4 then      -- Backwards: статичный разворот на 180°
            -- Самый БЛАТАНТНЫЙ: враги видят строго вашу спину, тело не дёргается.
            local back = realYaw + math.pi
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = back end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = back end
            if MOV.FakeAnglesPitch and type(a[10]) == "number" then a[10] = -pAmp * 0.5 end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = 0 end
        elseif fakeAngMode == 5 then      -- Jitter: ВЧ-тряска ±180° вокруг реального
            -- Блатантно и максимально сложно попасть: каждый пакет — новый угол.
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = realYaw + (math.random() * 2 - 1) * math.pi end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = realYaw + (math.random() * 2 - 1) * math.pi end
            if MOV.FakeAnglesPitch and type(a[10]) == "number" then a[10] = (math.random() * 2 - 1) * pAmp end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = math.random() * 2 - 1 end
        elseif fakeAngMode == 6 then      -- Twitch (LBY-breaker): снап реал↔180°
            -- Модель телепорт-щёлкает между «лицом» и «спиной» каждый пакет —
            -- на сервере угол не устаканивается → десинк-брейкер как в CS.
            local yaw = (flip > 0) and realYaw or (realYaw + math.pi)
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = yaw end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = yaw end
            if MOV.FakeAnglesPitch  and type(a[10]) == "number" then a[10] = flip * pAmp end
            if MOV.FakeAnglesLean  and n >= 11                  then a[11] = flip end
        elseif fakeAngMode == 7 then      -- Break: макс. десинк тела ВАЛИДНЫМИ углами
            -- Раньше слал 1e18 → сервер отбрасывал пакет вместе с позицией (фриз).
            -- Теперь — предельные, но КОНЕЧНЫЕ и принимаемые углы: тело вывернуто
            -- на 180° + макс. наклон. Прицел (a[9]/a[10]) не трогаем (own hitreg),
            -- если только явно не включён FakeAnglesAimYaw.
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = realYaw + math.pi end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = realYaw + math.pi end
            if MOV.FakeAnglesPitch  and type(a[10]) == "number" then a[10] = -pAmp end
            if MOV.FakeAnglesLean   and n >= 11                  then a[11] = flip end
        elseif fakeAngMode == 8 then      -- Chaos: случайные ВАЛИДНЫЕ углы + валидный стейт
            -- Раньше слал 1e18 и a[8]=1e9 (мусорный стейт) → пакет отбрасывался.
            -- Теперь — случайный полный круг для ТЕЛА и случайный РЕАЛЬНЫЙ стейт;
            -- всё проходит финализатор → с��рвер принимает, позиция не теряется.
            if MOV.FakeAnglesYaw    and type(a[6])  == "number" then a[6]  = math.random() * TAU end
            if MOV.FakeAnglesAimYaw and type(a[9])  == "number" then a[9]  = math.random() * TAU end
            if MOV.FakeAnglesPitch  and type(a[10]) == "number" then a[10] = (math.random() * 2 - 1) * pAmp end
            if MOV.FakeAnglesLean   and n >= 11                  then a[11] = math.random() * 2 - 1 end
            if n >= 8 and hsEnumByName then   -- случайный, но ВАЛИДНЫЙ HeightState
                local pool = {}
                for _, hv in pairs(hsEnumByName) do pool[#pool + 1] = hv end
                if #pool > 0 then a[8] = pool[math.random(#pool)] end
            end
        end
        -- ── State-спуф: чередуем HeightState (сидим/лежим/стоим) ──
        -- Работает во ВСЕХ фейк-режимах (кроме Chaos, который сам мусорит a[8]).
        -- FakeAnglesForceState фиксирует один стейт; иначе циклим StateCycle,
        -- держа каждый FakeAnglesStateHold пакетов (чтобы поза была ЗАМЕТНА).
        if fakeAngMode ~= 8 and n >= 8 and hsEnumByName then
            local wantName
            if MOV.FakeAnglesForceState then
                wantName = MOV.FakeAnglesForceState
            elseif MOV.FakeAnglesStateSpoof then
                local cyc  = MOV.FakeAnglesStateCycle or { "Crouching", "Proning", "Standing" }
                local hold = math.max(1, MOV.FakeAnglesStateHold or 8)
                faStatePkt = faStatePkt + 1
                wantName = cyc[(math.floor(faStatePkt / hold) % #cyc) + 1]
            end
            if wantName then
                local hv = hsEnumByName[wantName]
                if hv ~= nil then
                    a[8] = hv
                    faFakeHS = hv; faFakeHSName = wantName
                else
                    faFakeHS = nil; faFakeHSName = nil
                end
            else
                faFakeHS = nil; faFakeHSName = nil
            end
        else
            faFakeHS = nil; faFakeHSName = nil
        end
        -- ГАРАНТИЯ валидности пакета (углы конечные/в диапазоне, a[8] реальный
        -- HeightState, позиция a[3..5] нетронута) → сервер всегда принимает пакет,
        -- позиция уходит настоящей, нет фриза/отката при выключении фейк-углов.
        sanitizeFakePacket(a, n)
        if type(a[6])  == "number" then faFakeYaw    = a[6]  end
        if type(a[9])  == "number" then faFakeAimYaw = a[9]  end
        if type(a[10]) == "number" then faFakePitch  = a[10] end
        if n >= 11 and type(a[11]) == "number" then faFakeLean = a[11] end
    end

    -- VelocityDesync: смещает отправляемую позицию (a[3..5]) вдоль вектора
    -- скорости, чередуя знак — серверная модель «плывёт», клиентский CFrame ок.
    local function applyVelocityDesyncToArgs(a, n, flip)
        if not velDesyncActive then return end
        if type(a[3]) ~= "number" or type(a[4]) ~= "number" or type(a[5]) ~= "number" then return end
        local amp = MOV.VelocityDesyncAmp or 3.0
        local dir
        if MOV.VelocityDesyncUseVel and faVelEst.Magnitude > 0.1 then
            dir = faVelEst.Unit
            amp = amp * math.clamp(faVelEst.Magnitude / 16, 0.35, 2.5)
        else
            local yaw = (type(a[6]) == "number") and a[6] or (faRealYaw or 0)
            dir = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
        end
        local off = dir * (amp * flip)
        a[3] = a[3] + off.X
        a[4] = a[4] + off.Y + (MOV.VelocityDesyncVertical or 0) * flip
        a[5] = a[5] + off.Z
    end

    local origAccelerate, origDecelerate, origProcessNP, origJump, origCtrlUpdate = nil, nil, nil, nil, nil
    local origStateActor, hookedNet, hookedMt = nil, nil, nil
    local origFireUnrel = nil
    local noClipParts   = {}

    local origCamUpdate, hookedCamMt, hookedCamObj = nil, nil, nil

    local tpZoom = MOV.ThirdPersonDist

    local function currentZoomMax()
        if type(camCache) == "table" then
            local ok, zl = pcall(rawget, camCache, "_zoomLimit")
            if ok and type(zl) == "number" and zl > 0 then return zl end
        end
        return MOV.ThirdPersonMax
    end

    local function adjustTPZoom(delta)
        tpZoom = math.clamp(tpZoom + delta, 0, currentZoomMax())
    end

    local tpGui, tpGuiMinus, tpGuiPlus
    local function ensureTPGui()
        if tpGui or not MOV.ThirdPersonMobileGui then return end
        if not UIS.TouchEnabled then return end
        local ok = pcall(function()
            local sg = Instance.new("ScreenGui")
            sg.Name = "MOV_TPZoomGui"
            sg.ResetOnSpawn = false
            sg.IgnoreGuiInset = true
            sg.DisplayOrder = 999
            sg.Enabled = false

            local function mkBtn(text, offsetX)
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(0, 48, 0, 48)
                b.AnchorPoint = Vector2.new(1, 1)
                b.Position = UDim2.new(1, offsetX, 1, -160)
                b.Text = text
                b.TextScaled = true
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                b.BackgroundTransparency = 0.3
                b.TextColor3 = Color3.new(1, 1, 1)
                b.AutoButtonColor = true
                b.Parent = sg
                return b
            end

            tpGuiMinus = mkBtn("-", -64)
            tpGuiPlus  = mkBtn("+", -8)

            local parent = (type(gethui) == "function" and gethui()) or LP:WaitForChild("PlayerGui")
            sg.Parent = parent
            tpGui = sg

            tpGuiMinus.MouseButton1Click:Connect(newcclosure(function()
                adjustTPZoom(-MOV.ThirdPersonWheelStep)
            end))
            tpGuiPlus.MouseButton1Click:Connect(newcclosure(function()
                adjustTPZoom(MOV.ThirdPersonWheelStep)
            end))
        end)
        if not ok then warn("[MOV] TP GUI: не удалось создать") end
    end

    local function setTPGuiVisible(v)
        if tpGui then pcall(function() tpGui.Enabled = v end) end
    end

    local tpWheelConn = UIS.InputChanged:Connect(newcclosure(function(input)
        if not tpActive then return end
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            local z = input.Position.Z
            local sign = z > 0 and 1 or (z < 0 and -1 or 0)
            adjustTPZoom(-sign * MOV.ThirdPersonWheelStep)
        end
    end))

    local tpPinchConn = (UIS.TouchPinch and UIS.TouchPinch:Connect(newcclosure(function(_, scale, _, state)
        if not tpActive then return end
        if state == Enum.UserInputState.Change then
            adjustTPZoom(-(scale - 1) * MOV.ThirdPersonPinchSens)
        end
    end))) or nil

    local function unlockMt(mt)
        if type(setreadonly)    == "function" then pcall(setreadonly,    mt, false)
        elseif type(make_writeable) == "function" then pcall(make_writeable, mt) end
    end

    local function setCharPartsCollide(ctrl, enabled)
        local la = rawget(ctrl, "_localActor")
        if type(la) ~= "table" then return end
        local ok_c, char = pcall(function() return la.Character end)
        if not ok_c or not char then return end
        local ok, desc = pcall(function() return char:GetDescendants() end)
        if not ok then return end
        for _, p in ipairs(desc) do
            local okC, isBP = pcall(function() return p:IsA("BasePart") end)
            if okC and isBP then
                if not enabled then
                    local wasCC = p.CanCollide
                    noClipParts[p] = wasCC
                    pcall(function() p.CanCollide = false end)
                else
                    local was = noClipParts[p]
                    if was ~= nil then
                        pcall(function() p.CanCollide = was end)
                        noClipParts[p] = nil
                    end
                end
            end
        end
    end

    local function teardownHooks(ctrl)
        if not hooksSetup then return end
        local mt = hookedMt
        if mt then
            unlockMt(mt)
            if origAccelerate  then rawset(mt,"_accelerate",        origAccelerate)  end
            if origDecelerate  then rawset(mt,"_decelerate",        origDecelerate)  end
            if origProcessNP   then rawset(mt,"_processNewPosition", origProcessNP)  end
            if origJump        then rawset(mt,"Jump",                origJump)        end
            if origCtrlUpdate  then rawset(mt,"Update",              origCtrlUpdate)  end
        end
        if hookedNet and origFireUnrel then
            pcall(function() rawset(hookedNet, "FireUnreliableServer", nil) end)
            origFireUnrel = nil
        end
        if hookedNet and origStateActor then
            local evts = rawget(hookedNet,"_events")
            if type(evts)=="table" then rawset(evts,"StateActor",origStateActor) end
        end
        if ctrl then pcall(setCharPartsCollide, ctrl, true) end
        origAccelerate=nil; origDecelerate=nil; origProcessNP=nil; origJump=nil; origCtrlUpdate=nil
        origStateActor=nil; hookedNet=nil; hookedMt=nil; hooksSetup=false
        print("[MOV] Хуки контроллера сняты")
    end

    local function setupHooks(ctrl, net)
        local mt = (type(getrawmetatable)=="function" and getrawmetatable(ctrl))
                or getmetatable(ctrl)
        if not mt then warn("[MOV] setupHooks: metatable не найдена") return end

        if hooksSetup and mt == hookedMt then return end
        if hooksSetup and mt ~= hookedMt then
            pcall(teardownHooks, nil)
        end

        unlockMt(mt)
        hookedMt = mt

        local oAcc = rawget(mt, "_accelerate")
        if type(oAcc)=="function" then
            origAccelerate = oAcc
            rawset(mt, "_accelerate", newcclosure(function(self, dt, inputMag)
                if flyActive then self.MoveSpeed = 0; return end

                if MOV.Speed then
                    local live = isLiveInputActive()
                    if live then
                        lastMoveInputT = now()
                        local sprint = MOV.AutoSprint or UIS:IsKeyDown(MOV.SprintKey)
                        self.TrySprinting = sprint
                        self.IsSprinting  = sprint
                        self.MoveSpeed    = sprint and MOV.SprintSpeed or MOV.SpeedValue
                    else
                        self.MoveSpeed = 0
                        pcall(function() self._lastMovement = Vector2.new(0, 0) end)
                        pcall(function() self._groundedInputDirection = Vector3.new(0, 0, 0) end)
                    end
                else
                    oAcc(self, dt, inputMag)
                end
            end))
            print("[MOV] Hook: _accelerate ✓")
        end

        local oDecel = rawget(mt, "_decelerate")
        if type(oDecel)=="function" then
            origDecelerate = oDecel
            rawset(mt, "_decelerate", newcclosure(function(self, dt)
                if MOV.Speed then
                    self.MoveSpeed = 0
                else
                    oDecel(self, dt)
                end
            end))
            print("[MOV] Hook: _decelerate ✓")
        end

        local oPNP = rawget(mt, "_processNewPosition")
        if type(oPNP)=="function" then
            origProcessNP = oPNP
            rawset(mt, "_processNewPosition", newcclosure(function(self, newPos)
                if MOV.NoClip then
                    return newPos, true, Vector3.new(0,1,0), nil
                end
                return oPNP(self, newPos)
            end))
            print("[MOV] Hook: _processNewPosition ✓")
        end

        local oJump = rawget(mt, "Jump")
        if type(oJump)=="function" then
            origJump = oJump
            rawset(mt, "Jump", newcclosure(function(self)
                oJump(self)
            end))
            print("[MOV] Hook: Jump ✓")
        end

        local oUpdate = rawget(mt, "Update")
        if type(oUpdate) == "function" then
            origCtrlUpdate = oUpdate
            if not speedU18 then
                pcall(function()
                    local function isU18(t)
                        if type(t) ~= "table" then return false end
                        local count = 0
                        for _, v in pairs(t) do
                            if type(v) == "table"
                               and type(rawget(v, "SPEED_MULT")) == "number"
                               and type(rawget(v, "HEIGHT")) == "number" then
                                count = count + 1
                                if count >= 3 then return true end
                            end
                        end
                        return false
                    end

                    local function searchUpvalues(fn, depth)
                        if depth > 4 then return nil end
                        local ok, uvs = pcall(debug.getupvalues, fn)
                        if ok and type(uvs) == "table" then
                            if isU18(uvs["u18"]) then return uvs["u18"] end
                            for name, val in pairs(uvs) do
                                if isU18(val) then
                                    print("[MOV] u18 найден по структуре, upvalue:", name)
                                    return val
                                end
                            end
                        end
                        local ok2, protos = pcall(debug.getprotos, fn)
                        if ok2 and type(protos) == "table" then
                            for _, proto in ipairs(protos) do
                                if type(proto) == "function" then
                                    local res = searchUpvalues(proto, depth + 1)
                                    if res then return res end
                                end
                            end
                        end
                        return nil
                    end

                    local found = searchUpvalues(oUpdate, 0)
                    if not found then
                        for _, mfn in pairs(mt) do
                            if type(mfn) == "function" then
                                found = searchUpvalues(mfn, 0)
                                if found then break end
                            end
                        end
                    end

                    if not found then
                        local nils = getNilInstances()
                        if nils then
                            for _, inst in ipairs(nils) do
                                local okC, cls = pcall(function() return inst.ClassName end)
                                if okC and cls == "ModuleScript" then
                                    local okF, fn = pcall(getscriptclosure, inst)
                                    if okF and type(fn) == "function" then
                                        found = searchUpvalues(fn, 0)
                                        if found then break end
                                    end
                                end
                            end
                        end
                    end

                    if found then
                        speedU18 = found
                        hsEnumByName = {}
                        for enumKey, v in pairs(speedU18) do
                            if type(v) == "table" then
                                local sm = rawget(v, "SPEED_MULT")
                                local h  = rawget(v, "HEIGHT")
                                local ns = rawget(v, "NO_SPECIAL")
                                if     sm == 10  then hsEnumByName.Skydiving   = enumKey
                                elseif sm == 4   then hsEnumByName.Parachuting = enumKey
                                elseif sm == 0.3 then hsEnumByName.Proning     = enumKey
                                elseif sm == 0.8 then hsEnumByName.Swimming    = enumKey
                                elseif sm == 0.6 then hsEnumByName.Crouching   = enumKey
                                elseif sm == 1 and h == 6 and not ns then
                                    hsEnumByName.Standing = enumKey
                                end
                            end
                        end
                        proneHS = hsEnumByName.Proning
                        local names = {}
                        for n in pairs(hsEnumByName) do names[#names+1] = n end
                        print("[MOV] SpeedState: u18 найдена, стейты:", table.concat(names, ","))
                    else
                        warn("[MOV] SpeedState: u18 не найдена — SpeedState не будет работать")
                    end
                end)
            end
            rawset(mt, "Update", newcclosure(function(self, ...)
                liveCtrl  = self
                liveCtrlT = now()
                if not proneHS then
                    local hh = rawget(self, "_hullHeight")
                    if hh == 3 then
                        local hs = rawget(self, "HeightState")
                        if hs ~= nil then
                            proneHS = hs
                            print("[MOV] proneHS снят из Update (_hullHeight==3):", hs)
                        end
                    end
                end
                if flyActive and (self == activeCtrlRef or self == ctrlCache or self == liveCtrl) then
                    self.VelocityGravity = 0
                    self.IsGrounded = true
                    return
                end

                if straferActive then
                    local input = ...
                    if typeof(input) == "Vector2" then
                        self._lastMovement = input
                        self._groundedInputDirection = input
                    end
                end

                if forcedHS ~= nil then
                    pcall(function() self.HeightState = forcedHS end)
                end

                local ok, r1, r2, r3 = pcall(oUpdate, self, ...)
                if not ok then
                    warn("[MOV] CharacterController.Update: ошибка перехвачена (не критично):", r1)
                    return
                end
                return r1, r2, r3
            end))
            print("[MOV] Hook: Update (controller) ✓")
        end

        if net then
            local evts = rawget(net, "_events")
            if type(evts)=="table" then
                local oSA = rawget(evts, "StateActor")
                if type(oSA)=="function" then
                    origStateActor = oSA; hookedNet = net
                    rawset(evts, "StateActor", newcclosure(function(p76,p77,p78,p79)
                        if MOV.FlyTPBypass and (flyActive or MOV.NoClip) and p79 then
                            return
                        end
                        return oSA(p76,p77,p78,p79)
                    end))
                    print("[MOV] Hook: StateActor ✓")
                end
            end

            local oFU = rawget(net, "FireUnreliableServer")
            if type(oFU) ~= "function" then
                local nmt = getmetatable(net)
                if type(nmt) == "table" then
                    oFU = rawget(nmt, "FireUnreliableServer")
                          or (nmt.__index and rawget(nmt.__index, "FireUnreliableServer"))
                end
            end
            if type(oFU) == "function" then
                origFireUnrel = oFU
                rawset(net, "FireUnreliableServer", newcclosure(function(self, ...)
                    local isRM = (...) == "ReplicateMovement"
                    -- Всегда захватываем uid из штатных пакетов — нужен Sender'у.
                    if isRM then
                        local u = select(2, ...)
                        if u ~= nil then faUid = u end
                    end
                    local anyPacketFx = leanLockActive
                        or invisActive or noFallActive or (fakeAngMode ~= 0)
                        or velDesyncActive
                    if not anyPacketFx or not isRM then
                        return oFU(self, ...)
                    end
                    -- Если активен высокочастотный Sender и включено подавление —
                    -- глушим штатный 10Гц-пакет (Sender шлёт свой на макс частоте).
                    -- Safety: подавляем только если Sender реально слал недавно.
                    if MOV.FakeAnglesSender and MOV.FakeAnglesSuppressGame
                       and (fakeAngMode ~= 0 or velDesyncActive)
                       and (now() - faSenderLastSendT) < 0.2 then
                        return  -- drop
                    end
                    local n = select("#", ...)
                    local a = table.pack(...)
                    if noFallActive and n >= 8 then
                        if nfFalling then
                            if nfGroundHS ~= nil then a[8] = nfGroundHS end
                        else
                            nfGroundHS = a[8]
                        end
                    end
                    if invisActive then
                        if type(a[4]) == "number" then
                            a[4] = a[4] + (MOV.InvisibleYOffset or -2.8)
                        end
                        if MOV.InvisibleProne and proneHS ~= nil then
                            a[8] = proneHS
                        end
                        if MOV.InvisibleLean and n >= 11 then
                            a[11] = (invPhase % 2 < 1) and 1 or -1
                        end
                        local jit = MOV.InvisibleJitter or 0
                        if jit > 0 and type(a[3]) == "number" and type(a[5]) == "number" then
                            a[3] = a[3] + (math.random() * 2 - 1) * jit
                            a[5] = a[5] + (math.random() * 2 - 1) * jit
                        end
                    end
                    local flip
                    if fakeAngMode ~= 0 then
                        faPacket = faPacket + 1
                        flip = (faPacket % 2 == 0) and 1 or -1
                        applyFakeAnglesToArgs(a, n, flip)
                    elseif leanLockActive and n >= 11 then
                        a[11] = MOV.LeanLockValue
                    end
                    -- VelocityDesync смещает позицию (независимо от FakeAngles)
                    applyVelocityDesyncToArgs(a, n, flip or ((faPacket % 2 == 0) and 1 or -1))
                    -- ── ДИАГНОСТИКА: печатаем что реально уходит на сервер ──
                    if MOV.FakeAnglesDiag and faDiagLeft > 0 then
                        faDiagLeft = faDiagLeft - 1
                        local function f(v) return type(v)=="number" and string.format("%.2f", v) or tostring(v) end
                        print(string.format(
                            "[FA-DIAG] pos=(%s, %s, %s) orient=%s state=%s camY=%s lean=%s  [позиция=РЕАЛЬНАЯ, менять НЕ должны]",
                            f(a[3]), f(a[4]), f(a[5]), f(a[6]), f(a[8]), f(a[10]), f(a[11])))
                        if faDiagLeft == 0 then print("[FA-DIAG] — конец лога (жми K для нового) —") end
                    end
                    return oFU(self, table.unpack(a, 1, n))
                end))
                print("[MOV] Hook: FireUnreliableServer (Invisible/FakeAngles/NoFall/Lean) ✓")
            end
        end

        if not proneHS then
            pcall(function()
                local sh = rawget(getrenv and getrenv() or {}, "shared")
                        or rawget(getgenv and getgenv() or {}, "shared")
                if type(sh) ~= "table" then return end
                local en = rawget(sh, "Enum") or (type(sh.import) == "function"
                           and pcall(sh.import, "Enum") and nil)
                if type(en) ~= "table" then return end
                local chs = rawget(en, "CharacterHeightState")
                if type(chs) ~= "table" then return end
                local prone = rawget(chs, "Proning")
                if prone ~= nil then
                    proneHS = prone
                    print("[MOV] proneHS через shared.Enum ✓:", prone)
                end
            end)
        end

        hooksSetup = true
        print("[MOV] Все хуки контроллера установлены")
    end

    local _camLastT = now()
    local function camDt()
        local t = now()
        local d = t - _camLastT
        _camLastT = t
        if d <= 0 or d > 0.5 then d = 1/60 end
        return d
    end

    local function teardownCamHooks()
        if not camHooksSetup then return end
        if hookedCamMt and origCamUpdate then
            unlockMt(hookedCamMt)
            rawset(hookedCamMt, "Update", origCamUpdate)
        end
        origCamUpdate=nil; hookedCamMt=nil; hookedCamObj=nil; camHooksSetup=false
        print("[MOV] Хук камеры снят")
    end

    local function setupCamHooks(cam)
        if type(cam) ~= "table" then return end

        local mt = (type(getrawmetatable)=="function" and getrawmetatable(cam))
                or getmetatable(cam)
        if not mt then warn("[MOV] setupCamHooks: metatable камеры не найдена") return end

        if camHooksSetup and mt == hookedCamMt then return end
        if camHooksSetup and mt ~= hookedCamMt then
            pcall(teardownCamHooks)
        end

        unlockMt(mt)
        hookedCamMt  = mt
        hookedCamObj = cam

        local oUpd = rawget(mt, "Update")
        if type(oUpd) ~= "function" then
            warn("[MOV] setupCamHooks: Update не найден")
            return
        end
        origCamUpdate = oUpd

        local function forceCamState()
            if not (tpActive or spinBotActive) then return end
            local camObj = liveCam
            if type(camObj) ~= "table" then camObj = hookedCamObj end
            if type(camObj) ~= "table" then return end
            local la = rawget(camObj, "_localActor")
            if type(la) ~= "table" then return end
            if tpActive then
                local zl = rawget(camObj, "_zoomLimit")
                local z = tpZoom
                if type(zl) == "number" and zl > 0 then
                    z = math.clamp(z, 0, zl)
                else
                    z = math.max(z, 0)
                end
                la.Zoom          = z
                la.Focused       = z <= 0.01
                camObj._zoomLerp = z
            end
            if spinBotActive then
                la.Orientation = spinPhase
            end
        end

        rawset(mt, "Update", newcclosure(function(self, ...)
            liveCam  = self
            liveCamT = now()
            local ok, a, b, c = pcall(oUpd, self, ...)
            if not ok then
                warn("[MOV] CharacterCamera.Update: ошибка перехвачена (не критично):", a)
                pcall(forceCamState)
                return
            end

            if spinBotActive then
                spinPhase = spinPhase + camDt() * MOV.SpinBotRPS * math.pi * 2
            end
            pcall(forceCamState)

            return a, b, c
        end))

        camHooksSetup = true
        print("[MOV] Hook: CharacterCamera.Update ✓")
    end

    local ctrlCache, findLastT, FIND_CD = nil, -999, 2.5
    local camCache,  findCamLastT, FIND_CAM_CD = nil, -999, 2.5

    local _findCtrl = newcclosure(function()
        local c = findCtrlViaFiltergc()
        if c then print("[MOV] ctrl → filtergc"); return c end
        local c2 = findCtrlViaGetgc()
        if c2 then print("[MOV] ctrl → getgc"); return c2 end
        warn("[MOV] ctrl не найден — P для диагностики")
        return nil
    end)

    local _findCam = newcclosure(function()
        local c = findCamViaFiltergc()
        if c then print("[MOV] cam → filtergc"); return c end
        local c2 = findCamViaGetgc()
        if c2 then print("[MOV] cam → getgc"); return c2 end
        warn("[MOV] cam не найдена (TP/SpinBot недоступны)")
        return nil
    end)

    -- ── ДЕШЁВЫЙ ГЕЙТ «Я В МАШИНЕ» ─────────────────────────────────────────────
    -- В транспорте игра уничтожает CharacterController и ставит LocalActor.Controller
    -- на GroundController/HelicopterController/PassengerController (у них есть поля
    -- _solver/_vehicle/_tune вместо MoveSpeed/IsGrounded). Наш isCtrl их отвергает →
    -- _findCtrl каждые FIND_CD сек впустую гоняет filtergc/getgc (просадка + «Ctrl
    -- убирается»). Проверяем Controller живого актора — это чтение полей, без сканов.
    --
    -- Раньше опирались ТОЛЬКО на knownGoodLA (ставится лишь когда найден персонажный
    -- ctrl при жизни) — в машине он часто nil/устаревал → проверка не работала.
    -- Теперь берём актора из нескольких источников, включая камеру (её Update
    -- крутится и в транспорте), поэтому актор всегда свежий.
    local function getLiveLA()
        if type(knownGoodLA) == "table" then return knownGoodLA end
        -- камера обновляется каждый кадр даже в машине
        if type(liveCam) == "table" and (now() - liveCamT) < 1.0 then
            local la = rawget(liveCam, "_localActor")
            if type(la) == "table" then return la end
        end
        if type(activeCtrlRef) == "table" then
            local la = rawget(activeCtrlRef, "_localActor")
            if type(la) == "table" then return la end
        end
        return nil
    end
    -- точная проверка: это контроллер ТРАНСПОРТА? (совпадает с логикой visuals)
    local function isVehicleCtrl(c)
        return type(c) == "table"
            and type(rawget(c, "_solver"))  == "table"
            and type(rawget(c, "_vehicle")) == "table"
            and type(rawget(c, "_tune"))    == "table"
    end
    local function inVehicleNow()
        local la = getLiveLA()
        if type(la) ~= "table" then return false end
        return isVehicleCtrl(rawget(la, "Controller"))
    end

    local function getCtrl()
        if liveCtrl ~= nil and (now() - liveCtrlT) < LIVE_TTL and isCtrl(liveCtrl) then
            if not rawequal(ctrlCache, liveCtrl) then
                ctrlCache = liveCtrl
                activeCtrlRef = liveCtrl
                if not hooksSetup then
                    local net = findNetworkObj()
                    setupHooks(liveCtrl, net)
                end
            end
            return liveCtrl
        end
        if ctrlCache and isCtrl(ctrlCache) then return ctrlCache end
        -- В машине персонажного контроллера НЕ существует → не сканируем вообще.
        if inVehicleNow() then return nil end
        local t = now()
        if t - findLastT < FIND_CD then return nil end
        findLastT = t
        local c = _findCtrl()
        if c then
            ctrlCache = c
            activeCtrlRef = c
            if not hooksSetup then
                local net = findNetworkObj()
                setupHooks(c, net)
            end
        end
        return c
    end

    local function getCam()
        if liveCam ~= nil and (now() - liveCamT) < LIVE_TTL and isCam(liveCam) then
            if not rawequal(camCache, liveCam) then
                camCache = liveCam
                if not camHooksSetup then
                    setupCamHooks(liveCam)
                end
            end
            return liveCam
        end
        if camCache and isCam(camCache) then return camCache end
        local t = now()
        if t - findCamLastT < FIND_CAM_CD then return nil end
        findCamLastT = t
        local c = _findCam()
        if c then
            camCache = c
            if not camHooksSetup then
                setupCamHooks(c)
            end
        end
        return c
    end

    local function resetCtrlCache() ctrlCache=nil; activeCtrlRef=nil; findLastT=-999 end

    local function doJump(ctrl, velocityGravity, speedOverride)
        ctrl.IsGrounded = true
        local la = rawget(ctrl, "_localActor")
        if la then pcall(function() la:Jump() end) end
        local net = State.networkModule
        if net then pcall(function() net:FireServer("DoJump") end) end
        if speedOverride then ctrl.MoveSpeed = speedOverride end
        ctrl.VelocityGravity = velocityGravity or 25
    end

    local function applySpeedState()
        if speedStateMode == 0 then
            forcedHS = nil
            return true
        end
        if not hsEnumByName then return false end
        local order = MOV.SpeedStateOrder or { "Skydiving", "Parachuting", "Proning" }
        local name  = order[speedStateMode]
        local enumKey = name and hsEnumByName[name]
        if enumKey == nil then
            warn("[MOV] SpeedState: стейт '"..tostring(name).."' не найден в u18")
            forcedHS = nil
            return false
        end
        forcedHS = enumKey
        return true
    end

    local function destroyFakeGhost()
        faGhostHidden = false
        if faGhostModel then pcall(function() faGhostModel:Destroy() end); faGhostModel = nil end
        if faGhostHL    then pcall(function() faGhostHL:Destroy()    end); faGhostHL = nil end
        faGhostRoot    = nil
        faGhostHead    = nil
        faGhostHeadOff = nil
        faGhostTorsoM  = nil
        faGhostHeadM   = nil
    end

    -- v19.3: набор валидных имён частей R15. Всё, что НЕ входит сюда
    -- (аксессуары, шапки, оружие/Tool, gear-меши, hitbox'ы), в гост НЕ попадает.
    local R15_PARTS = {
        HumanoidRootPart = true, Head = true, UpperTorso = true, LowerTorso = true,
        LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
        RightUpperArm = true, RightLowerArm = true, RightHand = true,
        LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
        RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    }

    local function buildFakeGhost(char)
        local ok, clone = pcall(function() return char:Clone() end)
        if not ok or not clone then return end
        -- v19.2 FIX Lean: в игре lean — это РОЛЛ Motor6D UpperTorso (см. дамп
        -- ActorClass:2704), а не наклон всего тела. Чтобы Motor6D работали,
        -- нельзя якорить ВСЕ части (у якорёных Transform игнорируется). Якорим
        -- ТОЛЬКО root — остальные держатся на суставах, а мы крутим torso/head.
        local root = clone:FindFirstChild("HumanoidRootPart")
                     or clone:FindFirstChild("LowerTorso") or clone.PrimaryPart

        -- v19.3 «жидкое стекло»: оставляем ТОЛЬКО R15-меши/части тела, остальное
        -- (Accessory, Tool, одежда, декали, лишние MeshPart) вырезаем; телу даём
        -- полупрозрачный Glass-материал.
        local mat = MOV.FakeAnglesGhostMaterial or Enum.Material.Glass
        local tr  = MOV.FakeAnglesGhostTransparency or 0.5
        local col = MOV.FakeAnglesGhostColor or Color3.fromRGB(120, 200, 255)
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                if R15_PARTS[d.Name] then
                    d.Anchored    = (d == root)   -- якорим только root
                    d.CanCollide  = false
                    d.CanQuery    = false
                    d.CastShadow  = false
                    d.Material     = mat
                    d.Transparency = tr
                    d.Reflectance  = 0.12          -- лёгкий «стеклянный» блик
                    d.Color        = col
                    pcall(function() d.Massless = true end)
                    -- убираем «лицо»/текстуры/спец-меши, оставляя чистую геометрию
                    for _, s in ipairs(d:GetChildren()) do
                        if s:IsA("Decal") or s:IsA("Texture") or s:IsA("SurfaceAppearance")
                            or s:IsA("SpecialMesh") then
                            pcall(function() s:Destroy() end)
                        end
                    end
                else
                    -- не-R15 часть (шляпа/меш аксессуара/gear/оружие) — вон
                    pcall(function() d:Destroy() end)
                end
            elseif d:IsA("Accessory") or d:IsA("Tool") or d:IsA("Clothing")
                or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic")
                or d:IsA("Animator") or d:IsA("Humanoid") or d:IsA("Script")
                or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound")
                or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
                or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
                pcall(function() d:Destroy() end)
            elseif d:IsA("Motor6D") then
                pcall(function() d.Transform = CFrame.identity end)  -- нейтральная поза
            end
        end
        clone.Name = "_faGhost"
        pcall(function() clone.Parent = workspace end)
        faGhostModel = clone
        faGhostRoot  = root
        faGhostHead  = clone:FindFirstChild("Head")
        -- Находим суставы по Part1 (сустав именуется по ведомой части в R15).
        for _, m in ipairs(clone:GetDescendants()) do
            if m:IsA("Motor6D") and m.Part1 then
                if m.Part1.Name == "UpperTorso" then faGhostTorsoM = m
                elseif m.Part1.Name == "Head"    then faGhostHeadM  = m end
            end
        end
        if faGhostRoot and faGhostHead then
            pcall(function()
                faGhostHeadOff = faGhostRoot.CFrame:Inverse() * faGhostHead.CFrame
            end)
        end
        -- Тонкая стеклянная окантовка (не заливка) — подчёркивает силуэт.
        local ok2, hl = pcall(function()
            local h = Instance.new("Highlight")
            h.FillColor = col
            h.FillTransparency = math.clamp(tr + 0.35, 0, 1)
            h.OutlineColor = MOV.FakeAnglesGhostOutline or Color3.fromRGB(180, 235, 255)
            h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Adornee = clone
            h.Parent = clone
            return h
        end)
        if ok2 then faGhostHL = hl end
    end

    local function tickFakeGhost()
        if fakeAngMode == 0 or not MOV.FakeAnglesGhost then
            if faGhostModel then destroyFakeGhost() end
            return
        end
        local ctrl = ctrlCache
        if not ctrl then return end
        local la = rawget(ctrl, "_localActor")
        if not la then return end
        local char = rawget(la, "Character")
        if typeof(char) ~= "Instance" then return end
        if not faGhostModel or not faGhostModel.Parent then
            destroyFakeGhost()
            -- FIX: destroyFakeGhost resets faGhostHidden=false; buildFakeGhost
            -- creates fresh parts at ghostTr so the firstPerson re-check below
            -- will correctly apply hide/show on the very first tick.
            pcall(buildFakeGhost, char)
            if not faGhostModel then return end
        end
        local base = rawget(la, "Position") or rawget(la, "SimulatedPosition")
                     or rawget(ctrl, "_correctedPosition") or rawget(ctrl, "_position")
        if typeof(base) ~= "Vector3" then return end

        -- ── Прячем гост от 1-го лица (клон только у нас, скрываем локально) ──
        -- Надёжный сигнал = собственный игры: LocalActor.Zoom<=0 → первое лицо
        -- (CharacterCamera:153 v36 = Zoom>0 = третье лицо). Camera-дист — fallback.
        if MOV.FakeAnglesGhostFirstPersonHide ~= false then
            local firstPerson = false
            -- Zoom может быть raw-полем ИЛИ геттером через __index — пробуем оба.
            local zoom = rawget(la, "Zoom")
            if type(zoom) ~= "number" then
                local okZ, z = pcall(function() return la.Zoom end)
                if okZ and type(z) == "number" then zoom = z end
            end
            if type(zoom) == "number" then
                firstPerson = zoom <= (MOV.FakeAnglesGhostFPZoom or 0.5)
            else
                local cam = workspace.CurrentCamera
                local realHead = char:FindFirstChild("Head")
                if cam and realHead and realHead:IsA("BasePart") then
                    local d = (cam.CFrame.Position - realHead.Position).Magnitude
                    firstPerson = d < (MOV.FakeAnglesGhostFPDist or 1.5)
                end
            end
            if firstPerson ~= faGhostHidden then
                faGhostHidden = firstPerson
                -- FIX: LocalTransparencyModifier is unreliable in BRM5 (custom renderer).
                -- Use actual Transparency property instead. Store originals to restore.
                local ghostTr = MOV.FakeAnglesGhostTransparency or 0.5
                for _, d in ipairs(faGhostModel:GetDescendants()) do
                    if d:IsA("BasePart") then
                        pcall(function() d.Transparency = firstPerson and 1 or ghostTr end)
                    end
                end
                if faGhostHL then pcall(function() faGhostHL.Enabled = not firstPerson end) end
            end
            if firstPerson then return end   -- в 1-м лице не двигаем/не рисуем
        end

        -- v19.2 — воспроизводим РОВНО игровую позу (дамп ActorClass):
        --   root(HRP)        = CFrame.new(pos) * CFrame.Angles(0, Orientation, 0)  -- body yaw a[6]
        --   UpperTorso.Motor = Angles(0, -aimΔ, -rad(Lean*25)) * Angles(pitch/2, aimΔ, 0)  (2704)
        --   Head.Motor       = Angles(pitch/2, ...)                                 (2697)
        -- Тело НЕ наклоняется целиком: lean — это роль сустава торса, ноги стоят.
        local yaw   = faFakeYaw    or 0
        local lean  = faFakeLean   or 0
        local pitch = faFakePitch  or 0
        local aimDelta = (faFakeAimYaw or yaw) - yaw     -- взгляд относительно тела

        -- Отражаем спуфнутый стейт: сервер думает что мы сидим/лежим → показываем
        -- позу. Crouch: гост ниже; Prone: ниже + тело кладём горизонтально.
        local stateY, proneTilt = 0, 0
        local hsN = faFakeHSName
        if hsN == "Crouching" then
            stateY = -(MOV.FakeAnglesCrouchDrop or 1.4)
        elseif hsN == "Proning" then
            stateY = -(MOV.FakeAnglesProneDrop or 2.4)
            proneTilt = -math.rad(80)                 -- кладём тело на «живот»
        end

        -- 1) корпус: yaw тела + смещение/наклон по стейту (root анкорён → PivotTo)
        local bodyCF = CFrame.new(base + Vector3.new(0, stateY, 0))
            * CFrame.Angles(0, yaw, 0) * CFrame.Angles(proneTilt, 0, 0)
        pcall(function() faGhostModel:PivotTo(bodyCF) end)

        -- 2) lean-роль + твист на суставе UpperTorso (как строка 2704)
        if faGhostTorsoM then
            pcall(function()
                faGhostTorsoM.Transform =
                    CFrame.Angles(0, -aimDelta, -math.rad(lean * 25))
                    * CFrame.Angles(pitch * 0.5, aimDelta, 0)
            end)
        end
        -- 3) pitch головы на суставе Head (как строка 2697)
        if faGhostHeadM then
            pcall(function()
                faGhostHeadM.Transform = CFrame.Angles(pitch * 0.5, aimDelta, 0)
            end)
        elseif faGhostHead and faGhostHead.Parent and faGhostHeadOff and faGhostRoot then
            -- fallback: если сустав головы не найден — крутим часть напрямую
            local rootCF = faGhostRoot.CFrame
            pcall(function()
                faGhostHead.CFrame = rootCF * faGhostHeadOff
                    * CFrame.Angles(0, aimDelta, 0) * CFrame.Angles(pitch, 0, 0)
            end)
        end
    end

    -- Читает ЖИВЫЕ данные LocalActor (тот же объект, что шлёт репликатор) и
    -- обновляет численную оценку скорости для VelocityDesync.
    local function readLiveActorPacket()
        local ctrl = ctrlCache or liveCtrl
        if not ctrl then return nil end
        local la = rawget(ctrl, "_localActor")
        if type(la) ~= "table" then return nil end
        local pos = rawget(la, "ForceNextPosition") or rawget(la, "SimulatedPosition")
        if typeof(pos) ~= "Vector3" then return nil end
        -- оценка скорости ��з дельты позиции
        local t = now()
        if faLastPos and t > faLastPosT then
            local dt = t - faLastPosT
            if dt > 0 then
                local v = (pos - faLastPos) / dt
                -- сглаживание, чтобы не дёргалось
                faVelEst = faVelEst:Lerp(v, 0.35)
            end
        end
        faLastPos, faLastPosT = pos, t
        return la, pos
    end

    -- Высокочастотный Sender: шлёт ReplicateMovement напрямую через оригинальный
    -- FireUnreliableServer (в обход хука), с живой позицией + фейк-углами +
    -- velocity-десинком. Флипает углы КАЖДЫЙ пакет → на 60+ Гц это настоящий
    -- десинк, а не редкий 10Гц-джиттер.
    local function tickSender(dt)
        if not MOV.FakeAnglesSender then return end
        if fakeAngMode == 0 and not velDesyncActive then return end
        if not (hooksSetup and origFireUnrel and hookedNet and faUid ~= nil) then return end

        -- Кол-во отправок за этот кадр. hz=0 → одна на Heartbeat (~макс без фл����да).
        -- hz>fps → burst (несколько пакетов за кадр, «ускоряя» реплиацию), cap 8.
        local hz = MOV.FakeAnglesSendHz or 0
        local cap = MOV.FakeAnglesSendBurstCap or 3
        local sends = 1
        if hz > 0 then
            faSenderAccum = faSenderAccum + (dt or 0)
            local period = 1 / hz
            if faSenderAccum < period then return end
            sends = math.clamp(math.floor(faSenderAccum / period), 1, cap)
            faSenderAccum = faSenderAccum - sends * period
        end

        local la, pos = readLiveActorPacket()
        if not la or not pos then return end

        -- FPS FIX: переиспользуем ОДНУ таблицу args (без аллокаций каждый кадр).
        -- Базовые значения кэширу��м в локалы, т.к. applyFakeAngles мутирует a[]
        -- (в Instant-режиме через +=) → на burst-итерациях надо сбрасывать базу.
        local bOri  = rawget(la, "Orientation") or 0
        local bCamX = rawget(la, "CameraX") or 0
        local bCamY = rawget(la, "CameraY") or 0
        local bLean = rawget(la, "LeanGoal") or 0
        local a = faSenderArgs
        a[1] = "ReplicateMovement"; a[2] = faUid
        a[7]  = rawget(la, "Sprinting")
        a[8]  = rawget(la, "HeightState")
        a[12] = rawget(la, "Platform")
        local n = 12

        for _ = 1, sends do
            -- сбро�� базы каждую итерацию (позиция + углы), десинк/фейк меняют их
            a[3], a[4], a[5] = pos.X, pos.Y, pos.Z
            a[6], a[9], a[10], a[11] = bOri, bCamX, bCamY, bLean
            faSenderPkt  = faSenderPkt + 1
            faSenderFlip = -faSenderFlip
            if fakeAngMode ~= 0 then
                applyFakeAnglesToArgs(a, n, faSenderFlip)
            end
            applyVelocityDesyncToArgs(a, n, faSenderFlip)
            local ok = pcall(origFireUnrel, hookedNet, table.unpack(a, 1, n))
            if ok then faSenderLastSendT = now() end
        end
    end

    local function tickSpeedWatchdog(ctrl)
        if not MOV.Speed then return end
        if flyActive then return end

        if not isLiveInputActive() then
            ctrl.MoveSpeed = 0
            pcall(function() ctrl._lastMovement = Vector2.new(0, 0) end)
            pcall(function() ctrl._groundedInputDirection = Vector3.new(0, 0, 0) end)
        end
    end

    local flyLastPos = nil

    local function flyReadInputDir()
        local cam = getCamera()
        local dir = Vector3.zero
        if cam then
            local lk, rg = cam.CFrame.LookVector, cam.CFrame.RightVector
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir += lk end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= lk end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir += rg end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= rg end
        end
        if UIS:IsKeyDown(MOV.FlyUpKey)   then dir += Vector3.yAxis end
        if UIS:IsKeyDown(MOV.FlyDownKey) then dir -= Vector3.yAxis end
        return dir
    end

    local function flyResetState(ctrl)

        local la = ctrl and rawget(ctrl, "_localActor")
        if type(la) == "table" then
            local okR, rp = pcall(function() return la.RootPart end)
            if okR and typeof(rp) == "Instance" then
                local okP, pos = pcall(function() return rp.Position end)
                if okP and typeof(pos) == "Vector3" and pos.Magnitude > 0.1 then
                    flyLastPos = pos
                    return
                end
            end
        end

        if type(la) == "table" then
            local ok, pos = pcall(function() return la.Position end)
            if ok and typeof(pos) == "Vector3" and pos.Magnitude > 0.1 then
                flyLastPos = pos
                return
            end
        end

        if ctrl then
            local ok, pos = pcall(function() return ctrl._position end)
            if ok and typeof(pos) == "Vector3" and pos.Magnitude > 0.1 then
                flyLastPos = pos
            end
        end
    end

    local function tickFly(ctrl, dt)
        if not flyActive then flyLastPos = nil; return end
        -- В машине персонажного ctrl нет → флай неприменим; не трогаем ввод (Ctrl),
        -- чтобы не мешать управлению транспортом.
        if inVehicleNow() then flyLastPos = nil; return end
        if not ctrl then return end

        ctrl.VelocityGravity = 0
        ctrl.IsGrounded      = true
        ctrl.MoveSpeed       = 0

        pcall(function() ctrl._startPhysics = nil end)

        local la = rawget(ctrl, "_localActor")

        if flyLastPos == nil then
            flyResetState(ctrl)
            if flyLastPos == nil then return end
        end

        local dir = flyReadInputDir()
        local newPos = flyLastPos
        if dir.Magnitude > 0 then
            newPos = flyLastPos + dir.Unit * MOV.FlySpeed * dt
        end
        flyLastPos = newPos

        local curYaw = 0
        if type(la) == "table" then
            local okY, yaw = pcall(rawget, la, "Orientation")
            if okY and type(yaw) == "number" then curYaw = yaw end
        end
        local newCFrame = CFrame.new(newPos) * CFrame.Angles(0, curYaw, 0)

        pcall(function() ctrl:Teleport(newCFrame) end)
        pcall(function() ctrl._position = newPos end)

        pcall(function()
            local cyl = rawget(ctrl, "_cylinder")
            local hullH = rawget(ctrl, "_hullHeight") or 6
            if typeof(cyl) == "Instance" then
                cyl.CFrame = CFrame.new(newPos, newPos + Vector3.new(0, 1, 0))
                            * CFrame.Angles(0, math.pi / 2, 0)
                cyl.Size = Vector3.new(hullH - 3, 3, 3)
            end
        end)
        pcall(function() ctrl._lastSafePosition = newPos end)

        if type(la) == "table" then
            pcall(function()
                la.SimulatedPosition = newPos
                la.ForceNextPosition = newPos
                la.Position          = newPos
                la.CFrame            = newCFrame
                la._lastCFrame       = newCFrame
                la.Direction         = Vector2.new(0, 0)
            end)
        end

        if type(la) == "table" then
            local okR, rp = pcall(function() return la.RootPart end)
            if okR and typeof(rp) == "Instance" then
                pcall(function()
                    rp.CFrame = newCFrame
                end)
            end
        end
    end

    local function tickBunnyHop(ctrl)
        if not MOV.BunnyHop then bhopPrevGrounded=ctrl.IsGrounded; return end
        local grounded = ctrl.IsGrounded
        if not bhopPrevGrounded and grounded then
            doJump(ctrl, 25, nil)
        end
        bhopPrevGrounded = grounded
    end

    local ijConn = nil
    local function setupInfiniteJump()
        if ijConn then ijConn:Disconnect() end
        ijConn = UIS.JumpRequest:Connect(newcclosure(function()
            if not MOV.InfiniteJump then return end
            local ctrl = getCtrl()
            if ctrl then ctrl.IsGrounded=true end
        end))
    end

    local function tickAntiVoid(ctrl)
        if not MOV.AntiVoid then return end
        local pos = rawget(ctrl,"_position")
        if typeof(pos)=="Vector3" and pos.Y < MOV.AntiVoidY then
            local safe = Vector3.new(pos.X, MOV.AntiVoidSafeY, pos.Z)
            ctrl._position=safe; ctrl.VelocityGravity=0
            local la = rawget(ctrl,"_localActor")
            if la then la.SimulatedPosition=safe end
        end
    end

    local leanCur = 0
    local function tickLean(ctrl, dt)
        if not MOV.LeanSprint then leanCur=0; return end
        local cam=getCamera(); if not cam then return end
        local gid = rawget(ctrl,"_groundedInputDirection")
        local moving = gid and gid.Magnitude > 0.05 or false
        local target = (ctrl.IsSprinting and moving) and MOV.LeanAngle or 0
        leanCur = leanCur + (target-leanCur)*math.clamp(dt*12,0,1)
        if math.abs(leanCur)>0.02 then
            cam.CFrame = cam.CFrame * CFrame.Angles(0,0,math.rad(leanCur))
        end
    end

    local function runDiagnostic()
        logBuf = {}
        log("[DIAG] ═══════════════════════════════════════")
        log("[DIAG] os.clock:", now(), "| hooksSetup:", hooksSetup, "| camHooksSetup:", camHooksSetup)
        log("[DIAG] fly:", flyActive, "wantFly:", wantFly, "| NoClip:", MOV.NoClip,
            "| spinBot:", spinBotActive, "| tp:", tpActive)
        log("[DIAG] Speed:", MOV.Speed, MOV.SpeedValue, "/", MOV.SprintSpeed,
            "AutoSprint:", MOV.AutoSprint)
        log("[DIAG] net:", type(State.networkModule),
            isNetObj(State.networkModule) and "✓" or "✗")
        if type(filtergc)=="function" then
            local ok, gc = pcall(filtergc,"table",{Keys={"MoveSpeed","VelocityGravity","TrySprinting","IsGrounded","IsSprinting"}})
            if ok and gc then
                log("[DIAG] filtergc кандидатов ctrl:", #gc)
                for i, v in ipairs(gc) do
                    local okLa, la = pcall(rawget, v, "_localActor")
                    if not okLa or type(la) ~= "table" then la = nil end
                    log(("[DIAG]   [%d] isCtrl=%s alive=%s GID=%s Zoom=%s"):format(
                        i, tostring(isCtrl(v)),
                        la and tostring(rawget(la,"Alive")) or "?",
                        typeof(rawget(v,"_groundedInputDirection")),
                        la and tostring(rawget(la,"Zoom")) or "?"))
                end
            end
            local okC, gcC = pcall(filtergc,"table",{Keys={"_zoomLimit","_shoulderLerp","_lastWalkAngle"}})
            if okC and gcC then
                log("[DIAG] filtergc кандидатов cam:", #gcC)
                for i, v in ipairs(gcC) do
                    log(("[DIAG]   [%d] isCam=%s"):format(i, tostring(isCam(v))))
                end
            end
        end
        local ctrl = ctrlCache
        log("[DIAG] ctrlCache:", ctrl~=nil and isCtrl(ctrl) or false)
        if ctrl then
            log("[DIAG]   MoveSpeed:", ctrl.MoveSpeed,
                "IsGrounded:", ctrl.IsGrounded, "VG:", ctrl.VelocityGravity)
            local la = rawget(ctrl,"_localActor")
            log("[DIAG]   la.Zoom:", la and rawget(la,"Zoom") or "?",
                "la.Orientation:", la and rawget(la,"Orientation") or "?",
                "la.Alive:", la and rawget(la,"Alive") or "?")
            if hookedMt then
                log("[DIAG]   _accelerate:", type(rawget(hookedMt,"_accelerate")),
                    "| _decelerate:", type(rawget(hookedMt,"_decelerate")),
                    "| _pNP:", type(rawget(hookedMt,"_processNewPosition")))
            end

            if type(la) == "table" then
                log("[DIAG]   ── ПОЛНЫЙ ДАМП ПОЛЕЙ _localActor ──")
                local okIter, err = pcall(function()
                    local seen = {}
                    for k, v in next, la do
                        seen[k] = true
                        local tv = type(v)
                        local sv = (tv=="table") and ("<table>") or tostring(v)
                        log(("[DIAG]     %s = %s (%s)"):format(tostring(k), sv, tv))
                    end
                    for k, v in pairs(la) do
                        if not seen[k] then
                            local tv = type(v)
                            local sv = (tv=="table") and ("<table>") or tostring(v)
                            log(("[DIAG]     [pairs-only] %s = %s (%s)"):format(tostring(k), sv, tv))
                        end
                    end
                end)
                if not okIter then
                    log("[DIAG]   дамп полей упал:", tostring(err))
                end
                log("[DIAG]   ── КОНЕЦ ДАМП�� ──")
            end
        end
        log("[DIAG] camCache:", camCache~=nil and isCam(camCache) or false)
        if hookedCamMt then
            log("[DIAG]   cam.Update hooked:", type(rawget(hookedCamMt,"Update")))
        end
        if type(camCache) == "table" then
            log("[DIAG]   ── ПОЛНЫЙ ДАМП ПОЛЕЙ cam-ОБЪЕКТА ──")
            local okIter, err = pcall(function()
                local seen = {}
                for k, v in next, camCache do
                    seen[k] = true
                    local tv = type(v)
                    local sv = (tv=="table") and ("<table>") or tostring(v)
                    log(("[DIAG]     %s = %s (%s)"):format(tostring(k), sv, tv))
                end
                for k, v in pairs(camCache) do
                    if not seen[k] then
                        local tv = type(v)
                        local sv = (tv=="table") and ("<table>") or tostring(v)
                        log(("[DIAG]     [pairs-only] %s = %s (%s)"):format(tostring(k), sv, tv))
                    end
                end
            end)
            if not okIter then log("[DIAG]   дамп камеры упал:", tostring(err)) end
            log("[DIAG]   ─��� КОНЕЦ ДАМПА cam ──")
        end
        log("[DIAG] ══════════════════════════════════════")
        flushLog("brm5_diag.txt")
    end

    local function dumpNilInstances()
        local nils=getNilInstances(); if not nils then return end
        local lines={("Всего: %d"):format(#nils)}
        for i, inst in ipairs(nils) do
            local okC,cls=pcall(function() return inst.ClassName end)
            local okN,nm =pcall(function() return inst.Name end)
            lines[#lines+1]=("[%d] %s | %s"):format(i, okC and cls or "?", okN and nm or "?")
        end
        local c=table.concat(lines,"\n")
        if type(writefile)    =="function" then pcall(writefile,    "brm5_nilinstances_dump.txt",c) end
        if type(setclipboard) =="function" then pcall(setclipboard, c) end
        print("[MOV] Дамп → brm5_nilinstances_dump.txt")
    end

    local crAddedCount, crRemovingCount   = 0, 0
    local watchdogDeathCount, watchdogRecoverCount = 0, 0
    local wasCtrlAliveLastFrame = false
    local lastKnownCtrl = nil
    local knownGoodCtrl = nil
    local recovering = false
    local attemptRecovery

    local function handleLocalDeath(oldCtrl)
        -- v19.2 FIX «настройки сбрасываются п��сле смерти»:
        -- Раньше здесь обнулялись ВСЕ intent-флаги (flyActive, fakeAngMode,
        -- velDesyncActive, invisActive, NoClip …) → после респавна ��сё надо было
        -- включать заново. Теперь по умолчанию НАМЕРЕНИЕ пользователя сохраняется:
        -- tick-петля сама переприменит фичи, как только liveCtrl появится вновь.
        -- Сбрасываем только ТРАНЗИТНОЕ состояние, привязанное к мёртвому инстансу.
        if MOV.PreserveStateOnDeath == false then
            flyActive=false; straferActive=false; spinBotActive=false
            speedStateMode=0
            fakeAngMode=0; noFallActive=false
            velDesyncActive=false
            leanLockActive=false
            invisActive=false
            tpActive=false; MOV.NoClip=false
        end
        -- ��р��нзит (всегда): физ-якоря, кэш коллизий, клон, оценка скорости
        pcall(applySpeedState)
        fakeAngPhase=0; faPacket=0
        nfFalling=false; nfGroundHS=nil
        faLastPos=nil; faVelEst=Vector3.zero
        pcall(destroyFakeGhost)   -- клон ссылался на мёртвого чара → пересоберётся
        noClipParts={}
        flyLastPos = nil
        -- v19.1: хуки на ОБЩЕЙ метатаблице класса → переживают респавн. Не трогаем,
        -- лишь инвалидируем ссылки на мёртвый инстанс. Хукнутый Update нового
        -- контроллера сам заполнит liveCtrl в первом кадре — без getgc-сканов.
        ctrlCache      = nil
        activeCtrlRef  = nil
        liveCtrl       = nil
        liveCtrlT      = -999
        camCache       = nil
        liveCam        = nil
        liveCamT       = -999
        print("[MOV] Death detected -> инстанс сброшен, настройки сохранены (preserve="
              ..tostring(MOV.PreserveStateOnDeath ~= false)..")")
        if not recovering then
            task.spawn(attemptRecovery)
        end
    end

    attemptRecovery = function()
        if recovering then return end
        recovering = true

        local ok, err = pcall(function()
            noClipParts = {}
            setupInfiniteJump()

            -- Хуки живут на метатаблице → просто ждём, пока Update нового
            -- контроллера сам заполнит liveCtrl. Это дёшево (проверка ссылки
            -- раз в 50мс) и НЕ вызывает getgc/filtergc-сканы.
            local ctrl = nil
            for attempt = 1, 60 do
                if hooksSetup and liveCtrl ~= nil and isCtrl(liveCtrl) then
                    ctrl = liveCtrl
                    ctrlCache     = liveCtrl
                    activeCtrlRef = liveCtrl
                    print("[MOV] Respawn: liveCtrl подхвачен за попытку", attempt, "(без скана)")
                    break
                end
                task.wait(0.05)
            end

            -- Фолбэк (редкий): хуки реально слетели или mt пересоздалась —
            -- один раз восстанавливаем через скан.
            if not ctrl then
                print("[MOV] Respawn: liveCtrl не появился — фолбэк на скан")
                resetCtrlCache()
                ctrl = getCtrl()
                getCam()
                if ctrl and not hooksSetup then
                    pcall(setupHooks, ctrl, findNetworkObj())
                end
            end

            if not ctrl then
                warn("[MOV] Respawn: ctrl так и не найден!")
            else
                watchdogRecoverCount = watchdogRecoverCount + 1
            end

            if MOV.FlyPersist and wantFly then
                flyActive = true
                flyLastPos = nil
                print("[MOV] Fly восстановлен после респавна")
            end

            -- v19.2: переприменяем сохранённые настройки на НОВЫЙ контроллер.
            -- Флаги не сбрасывались (PreserveStateOnDeath), но часть фич требует
            -- явного повторного применения к новому инстансу.
            if ctrl and MOV.PreserveStateOnDeath ~= false then
                pcall(applySpeedState)
                if MOV.NoClip then pcall(setCharPartsCollide, ctrl, false) end
                faLastPos = nil; faVelEst = Vector3.zero   -- чистая оценка скорости
                faUid = faUid  -- uid переустановится из первых же пакетов игры
                print("[MOV] Настройки переприменены: fly="..tostring(flyActive)
                      .." fakeAng="..tostring(fakeAngMode).." velDesync="..tostring(velDesyncActive)
                      .." noclip="..tostring(MOV.NoClip).." speedState="..tostring(speedStateMode))
            end
        end)
        if not ok then
            warn("[MOV] attemptRecovery: ОШИБКА (перехвачена, recovering всё равно сброшен):", err)
        end
        recovering = false
    end

    local function onInput(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kc = input.KeyCode

        if kc == MOV.SpeedToggleKey then
            MOV.Speed = not MOV.Speed
            print("[MOV] Speed:", MOV.Speed, "→", MOV.SpeedValue, "/", MOV.SprintSpeed)
        end

        if kc == MOV.FlyToggleKey then
            flyActive = not flyActive
            wantFly = flyActive
            if not flyActive then
                local ctrl = getCtrl()
                if ctrl then ctrl.VelocityGravity = -10 end
            end
            print("[MOV] Fly:", flyActive)
        end

        if kc == MOV.StraferKey then
            straferActive = not straferActive
            print("[MOV] Strafer (free strafe):", straferActive)
        end

        if kc == MOV.SpeedStateKey then
            local order = MOV.SpeedStateOrder or { "Skydiving", "Parachuting", "Proning" }
            speedStateMode = (speedStateMode + 1) % (#order + 1)
            if not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            local applied = applySpeedState()
            if speedStateMode == 0 then
                print("[MOV] SpeedState: OFF")
            else
                local nm = order[speedStateMode]
                local mult = ({ Skydiving="x10", Parachuting="x4", Proning="x0.3",
                                Swimming="x0.8", Crouching="x0.6", Standing="x1" })[nm] or "?"
                print("[MOV] SpeedState:", nm, mult,
                      applied and "" or "(u18 ещё не найден — нажми ещё раз через кадр)")
            end
        end

        if kc == MOV.FakeAnglesKey then
            fakeAngMode = (fakeAngMode + 1) % 9
            fakeAngPhase = 0
            faPacket = 0
            faStatePkt = 0
            if fakeAngMode == 0 then pcall(destroyFakeGhost) end
            if fakeAngMode ~= 0 and not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            local names = { [0]="OFF", [1]="Instant", [2]="Spin", [3]="Random",
                            [4]="Backwards", [5]="Jitter", [6]="Twitch",
                            [7]="Break(1e18 TEST)", [8]="Chaos(rand TEST)" }
            print("[MOV] FakeAngles:", names[fakeAngMode])
        end

        if kc == (MOV.FakeAnglesDiagKey or Enum.KeyCode.K) then
            MOV.FakeAnglesDiag = not MOV.FakeAnglesDiag
            faDiagLeft = MOV.FakeAnglesDiag and (MOV.FakeAnglesDiagCount or 20) or 0
            print("[MOV] FakeAngles ДИАГНОСТИКА:", MOV.FakeAnglesDiag and "ВКЛ" or "выкл",
                  "— смотри [FA-DIAG] в консоли (pos должна быть РЕАЛЬНОЙ)")
        end

        if kc == MOV.VelocityDesyncKey then
            velDesyncActive = not velDesyncActive
            faLastPos = nil; faVelEst = Vector3.zero
            if velDesyncActive and not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            print("[MOV] VelocityDesync:", velDesyncActive,
                  "(amp="..tostring(MOV.VelocityDesyncAmp)..")")
        end

        if kc == MOV.LeanLockKey then
            leanLockActive = not leanLockActive
            if leanLockActive and not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            print("[MOV] LeanLock:", leanLockActive, "(LeanGoal="..tostring(MOV.LeanLockValue)..")")
        end

        if kc == MOV.InvisibleKey then
            invisActive = not invisActive
            if invisActive and not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            print("[MOV] Invisible:", invisActive,
                  "(Y offset "..tostring(MOV.InvisibleYOffset)..")")
        end

        if kc == MOV.SpinBotKey then
            spinBotActive = not spinBotActive; spinPhase = 0
            if spinBotActive and not camHooksSetup then
                local cam = getCam()
                if not cam then warn("[MOV] SpinBot: камера не ��айдена, повтори через ��екунду") end
            end
            print("[MOV] SpinBot:", spinBotActive)
        end

        if kc == MOV.ThirdPersonKey then
            tpActive = not tpActive
            if tpActive then
                if tpZoom <= 0.01 then
                    tpZoom = MOV.ThirdPersonDist
                end
                if not camHooksSetup then
                    local cam = getCam()
                    if not cam then warn("[MOV] ForceThirdPerson: камера не найдена, повтори через секунду") end
                end
                ensureTPGui()
                setTPGuiVisible(true)
            else
                setTPGuiVisible(false)
                local ctrl = getCtrl()
                if ctrl then
                    local la = rawget(ctrl,"_localActor")
                    if type(la)=="table" then pcall(function() la.Zoom=0 end) end
                end
            end
            print("[MOV] ForceThirdPerson:", tpActive, "| zoom:", tpZoom, "/", currentZoomMax())
        end

        if kc == MOV.NoClipKey then
            MOV.NoClip = not MOV.NoClip
            local ctrl = getCtrl()
            if ctrl then
                if not hooksSetup then
                    setupHooks(ctrl, findNetworkObj())
                end
                setCharPartsCollide(ctrl, not MOV.NoClip)
            end
            print("[MOV] NoClip:", MOV.NoClip)
        end

        if kc == MOV.NoFallKey then
            noFallActive = not noFallActive
            nfFalling = false; nfGroundHS = nil
            if noFallActive and not hooksSetup then
                local ctrl = getCtrl()
                if ctrl then setupHooks(ctrl, findNetworkObj()) end
            end
            print("[MOV] NoFall:", noFallActive, "(HeightState spoof)")
        end

        if kc == MOV.DumpNilKey  then dumpNilInstances() end
        if kc == MOV.DiagKey     then task.spawn(runDiagnostic) end

        if kc == MOV.DebugKey then
            local ctrl = getCtrl()
            print("━━━━━━━━ [MOV DIAG v29] ━━━━━━━━")

            print("  [HOOKS] hooksSetup:", hooksSetup, "| camHooksSetup:", camHooksSetup)
            if hookedMt then
                local curUpd = rawget(hookedMt, "Update")
                local hookInstalled = (curUpd ~= nil and curUpd ~= origCtrlUpdate)
                print("  [HOOKS] hookedMt: OK | ctrl.Update хук:", hookInstalled and "НАШ ✓" or "ОРИГИНАЛ ✗")
            else
                print("  [HOOKS] hookedMt: nil → setupHooks не вызывался или teardown случился")
            end

            print("  [CTRL] найден:", ctrl~=nil, "| ctrlCache:", ctrlCache~=nil,
                          "| identity:", ctrl and tostring(ctrl):match("0x%x+") or "nil")
            if ctrl then
                local la = rawget(ctrl, "_localActor")
                print("  [CTRL] la:", la~=nil, "| la type:", type(la))
                if type(la) == "table" then
                    local okLP  = LP.Character ~= nil
                    local okChr, char = pcall(function() return rawget(la,"Character") end)
                    local okRoot, root = pcall(function() return rawget(la,"RootPart") end)
                    local okIlp, ilp = pcall(function() return rawget(la,"IsLocalPlayer") end)
                    print("  [CTRL] LP.Character~=nil (ожидаем false):", okLP)
                    print("  [CTRL] la.Character:", okChr and tostring(char) or "ERR",
                                "| la.RootPart:", okRoot and tostring(root) or "ERR")
                    print("  [CTRL] la.IsLocalPlayer (новый фильтр isCtrl):", okIlp and tostring(ilp) or "ERR")
                    print("  [CTRL] la.Zoom:", rawget(la,"Zoom"),
                                "la.Alive:", rawget(la,"Alive"),
                                "la.Focused:", rawget(la,"Focused"))
                    print("  [CTRL] la.ADS:", rawget(la,"ADS"),
                                "la.CQB:", rawget(la,"CQB"),
                                "la.Downed:", rawget(la,"Downed"))
                end
                print("  [CTRL] MoveSpeed:", ctrl.MoveSpeed,
                              "VelocityGravity:", ctrl.VelocityGravity,
                              "IsGrounded:", ctrl.IsGrounded)
                local okCyl, cylCF = pcall(function() return ctrl._cylinder.CFrame end)
                if okCyl and type(la) == "table" then
                    local okPos, pos = pcall(function() return la.Position end)
                    if okPos then
                        local dist = (cylCF.Position - pos).Magnitude
                        print("  [CTRL] |_cylinder - la.Position| =", math.floor(dist*100)/100,
                                    dist > 5 and "⚠ РАССИНХРОН" or "OK")
                    end
                end
            end

            print("  [CAM] camCache:", camCache~=nil,
                          "| identity:", camCache and tostring(camCache):match("0x%x+") or "nil")
            if camCache then
                local cam = camCache
                local la  = rawget(cam, "_localActor")
                print("  [CAM] la:", la~=nil)
                if la then
                    local okZ, zoomVal = pcall(function() return la.Zoom end)
                    local okF, focVal  = pcall(function() return la.Focused end)
                    local okA, adsVal  = pcall(function() return la.ADS end)
                    print("  [CAM] la.Zoom:", okZ and tostring(zoomVal) or "ERR",
                                "la.Focused:", okF and tostring(focVal) or "ERR",
                                "la.ADS:", okA and tostring(adsVal) or "ERR")
                    print("  [CAM] _zoomLerp:", cam._zoomLerp,
                                "_zoomLimit:", cam._zoomLimit)
                end
            end
            print("  [CAM] tpActive:", tpActive, "| tpZoom:", tpZoom, "/", currentZoomMax())
            print("  [CAM] liveCam:", liveCam ~= nil,
                        "| свежесть:", liveCam and string.format("%.2fs", now() - liveCamT) or "n/a")

            print("  [FLY] flyActive:", flyActive, "| wantFly:", wantFly,
                          "| flyLastPos:", flyLastPos ~= nil and tostring(flyLastPos) or "nil")

            print("  [RESPAWN] watchdogDeathCount:", watchdogDeathCount,
                        "| watchdogRecoverCount:", watchdogRecoverCount,
                        "| recovering:", recovering)
            print("  [RESPAWN] LP.CharacterRemoving выстрелов:", crRemovingCount,
                        "| LP.CharacterAdded выстрелов:", crAddedCount,
                        (crRemovingCount == 0 and crAddedCount == 0)
                            and "⚠ ПОДТВЕРЖДЕНО: события Character* не стреляют в этой игре"
                            or "")

            print("  [MISC] Speed:", MOV.Speed, "| strafer:", straferActive,
                          "| spinBot:", spinBotActive, "| NoClip:", MOV.NoClip)
            print("  [MISC] InfJump:", MOV.InfiniteJump, "| BunnyHop:", MOV.BunnyHop)
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━��")
        end
    end

    local function onJumpInput(input, _processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kc = input.KeyCode

        if kc == MOV.SuperJumpKey then
            local ctrl = getCtrl()
            if ctrl then
                doJump(ctrl, MOV.SuperJumpVel, nil)
                print("[MOV] SuperJump ↑", MOV.SuperJumpVel)
            end
        end

    end

    local conns = {}

    local function tick(dt)
        if not State.running then return end
        local ctrl = getCtrl()
        getCam()

        -- В машине персонажного контроллера НЕТ (ctrl == nil), но мы ЖИВЫ. Без этой
        -- ветки tick принимал вход в транспорт за смерть (ctrl исчез) и дёргал
        -- handleLocalDeath → сброс ��ич/ложный «респавн». Считаем себя живыми, не
        -- трогаем персонажные тики и НЕ меняем wasCtrlAliveLastFrame (чтобы выход
        -- из машины тоже не читался как смерть).
        if ctrl == nil and inVehicleNow() then
            return
        end

        local aliveNow = ctrl ~= nil
        local la = aliveNow and rawget(ctrl, "_localActor") or nil

        local identitySwapped = aliveNow and knownGoodLA ~= nil and not rawequal(la, knownGoodLA)

        local ctrlSwapped = aliveNow and knownGoodCtrl ~= nil and not rawequal(ctrl, knownGoodCtrl)

        if (wasCtrlAliveLastFrame and not aliveNow) or identitySwapped or ctrlSwapped then
            watchdogDeathCount = watchdogDeathCount + 1
            pcall(handleLocalDeath, lastKnownCtrl)
        end
        wasCtrlAliveLastFrame = aliveNow
        if aliveNow then lastKnownCtrl = ctrl; knownGoodLA = la; knownGoodCtrl = ctrl end

        if not aliveNow or identitySwapped or ctrlSwapped then return end
        tickFly(ctrl, dt)
        if invisActive then invPhase = invPhase + dt * 12 end
        if noFallActive then
            local vg = ctrl.VelocityGravity
            local gr = ctrl.IsGrounded
            nfFalling = (gr == false) and type(vg) == "number" and vg < -18
        end
        tickSpeedWatchdog(ctrl)
        tickBunnyHop(ctrl)
        tickAntiVoid(ctrl)
    end

    local function renderTick(dt)
        if not State.running then return end
        if MOV.LeanSprint then
            local ctrl = ctrlCache
            if ctrl and isCtrl(ctrl) then tickLean(ctrl, dt) end
        end
        pcall(tickFakeGhost)
    end

    local _M = {}
    _M.CONFIG = MOV

    function _M.start()
        for k, v in pairs(MOV) do CONFIG[k] = v end

        conns[1] = RunService.Heartbeat:Connect(newcclosure(function(dt)
            pcall(tick, dt)
            pcall(tickSender, dt)   -- высокочастотный FakeAngles/VelocityDesync Sender
        end))
        conns[2] = RunService.RenderStepped:Connect(newcclosure(function(dt)
            pcall(renderTick, dt)
        end))
        -- NOTE: physical toggle-hotkeys are intentionally NOT connected here.
        -- All features are driven from the UI (toggles) and via user-assigned
        -- MacLib keybinds (empty by default, set in the Movement tab). onInput /
        -- onJumpInput remain as the shared dispatch used by _M.doAction / _M.superJump.
        -- Held movement keys (Sprint/FlyUp/FlyDown) are polled via IsKeyDown and are
        -- unaffected. To restore old always-on physical keys, reconnect them here.

        conns[5] = LP.CharacterRemoving:Connect(newcclosure(function()
            crRemovingCount = crRemovingCount + 1
            print("[MOV] LP.CharacterRemoving выстрелил (счётчик:", crRemovingCount, ")")
            handleLocalDeath(ctrlCache)
        end))

        conns[6] = LP.CharacterAdded:Connect(newcclosure(function()
            crAddedCount = crAddedCount + 1
            print("[MOV] LP.CharacterAdded выстрелил (счётчик:", crAddedCount, ")")
            task.spawn(attemptRecovery)
        end))

        setupInfiniteJump()

        local ctrl = getCtrl()
        getCam()
        if ctrl then
            print("[MOV v19.0] ✓ | hooks:", hooksSetup, "| camHooks:", camHooksSetup)
            local la = rawget(ctrl,"_localActor")
            if la then
                print("[MOV]   la.Zoom:", rawget(la,"Zoom"),
                      "| Alive:", rawget(la,"Alive"))
            end
        else
            warn("[MOV v19.0] ctrl не найден — P → brm5_diag.txt")
        end
        print("[MOV] G=Fly | V=Strafer | Z=SpinBot | T=TP | N=NoClip | X=Speed | C=SpeedState | L=LeanLock | J=FakeAngles | U=Invisible | H=SuperJump | B=NoFall")
    end

    function _M.stop()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        if ijConn then ijConn:Disconnect(); ijConn=nil end
        flyActive=false; wantFly=false; straferActive=false; spinBotActive=false
        tpActive=false; MOV.NoClip=false
        noFallActive=false; fakeAngMode=0; leanLockActive=false; invisActive=false
        nfFalling=false; nfGroundHS=nil
        pcall(destroyFakeGhost)
        teardownHooks(ctrlCache)
        teardownCamHooks()
        if ctrlCache then
            local la = rawget(ctrlCache,"_localActor")
            if type(la)=="table" then pcall(function() la.Zoom=0 end) end
        end
        print("[MOV] stopped")
    end

    -- Прогоняем синтетический input через onInput → переиспользуем ВСЮ логику
    -- тумблеров (fly/invis/fakeangles/…) вместе с их сайд-эффектами (setupHooks и т.п.).
    function _M.simulateKey(kc)
        if not kc then return end
        onInput({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = kc }, false)
    end

    -- ── UI state bridge ─────────────────────────────────────────────────────
    -- Toggle-state lives in module upvalues (flyActive, invisActive, …) and in a
    -- couple of MOV fields (Speed, NoClip). These helpers let buildUI read the
    -- real state and set it IDEMPOTENTLY (only fire the toggle key when the value
    -- actually needs to change), so UI toggles and keybinds never desync.
    local FEATURE_KEY = {
        Speed = MOV.SpeedToggleKey, Fly = MOV.FlyToggleKey, NoClip = MOV.NoClipKey,
        Strafer = MOV.StraferKey, Invisible = MOV.InvisibleKey,
        VelDesync = MOV.VelocityDesyncKey, LeanLock = MOV.LeanLockKey,
        SpinBot = MOV.SpinBotKey, NoFall = MOV.NoFallKey, ThirdPerson = MOV.ThirdPersonKey,
    }
    function _M.isActive(name)
        if name == "Speed" then return MOV.Speed == true end
        if name == "NoClip" then return MOV.NoClip == true end
        if name == "Fly" then return flyActive end
        if name == "Strafer" then return straferActive end
        if name == "Invisible" then return invisActive end
        if name == "VelDesync" then return velDesyncActive end
        if name == "LeanLock" then return leanLockActive end
        if name == "SpinBot" then return spinBotActive end
        if name == "NoFall" then return noFallActive end
        if name == "ThirdPerson" then return tpActive end
        return false
    end
    function _M.setFeature(name, want)
        want = want and true or false
        if _M.isActive(name) ~= want then
            _M.simulateKey(FEATURE_KEY[name])
        end
    end
    function _M.getSpeedStateMode() return speedStateMode end
    function _M.getFakeAngMode() return fakeAngMode end
    -- Cycle-based setters (SpeedState / FakeAngles advance by one per key press).
    function _M.setSpeedStateMode(target)
        local order = MOV.SpeedStateOrder or { "Skydiving", "Parachuting", "Proning" }
        local n = #order + 1
        for _ = 1, n do
            if speedStateMode == target % n then break end
            _M.simulateKey(MOV.SpeedStateKey)
        end
    end
    function _M.setFakeAngMode(target)
        for _ = 1, 9 do
            if fakeAngMode == target % 9 then break end
            _M.simulateKey(MOV.FakeAnglesKey)
        end
    end
    function _M.superJump()
        onJumpInput({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = MOV.SuperJumpKey }, false)
    end

    -- ─────────────────────────────────────────────────────────────────────
    -- UI-интеграция (MacLib). Movement-таб.
    --   Числовые настройки (SpeedValue/SprintSpeed/FlySpeed) читаются в рантайме
    --     из MOV → пишем прямо в MOV.
    --   Стейтовые тумблеры (fly/invis/…) переключаются через simulateKey, чтобы
    --     не дублировать логику onInput. UI-состояние стартует из фактического.
    -- ─────────────────────────────────────────────────────────────────────
    function _M.buildUI(ui)
        local flag = ui.flag or function(s) return "MOV_" .. s end
        local tab = ui.tabs and ui.tabs.Movement
        if not tab then return end
        local dtab = ui.tabs and ui.tabs.Debug
        local ntf = ui.notify or function() end

        local ML = ui.MacLib
        local function syncToggle(f, val)
            if ML and ML.Options and ML.Options[f] then
                pcall(function() ML.Options[f]:UpdateState(val) end)
            end
        end
        -- Feature toggle + keybind helper.
        -- FIX double-notify: syncToggle(flag) re-triggers the Toggle Callback which
        -- calls ntf() again. Block Toggle Callbacks during programmatic state sync.
        local _notifyBlocked = false
        local function feature(section, label, name, desc)
            section:Toggle({ Name = "Enabled", Default = _M.isActive(name),
                Callback = function(v)
                    _M.setFeature(name, v)
                    if not _notifyBlocked then
                        ntf(label, v and "Enabled" or "Disabled")
                    end
                end }, flag(name))
            if ui.keybind then
                ui.keybind(section, { Name = "Keybind", Flag = flag(name .. "_KB"),
                    Toggle = function()
                        local nv = not _M.isActive(name)
                        _M.setFeature(name, nv)
                        _notifyBlocked = true
                        syncToggle(flag(name), nv)
                        _notifyBlocked = false
                        ntf(label, nv and "Enabled" or "Disabled")
                    end })
            end
            if desc then section:SubLabel({ Text = desc }) end
        end

        -- ── Speed ─────────────────────────────────────────────────────────
        local LS = tab:Section({ Name = "Speed", Side = "Left" })
        LS:Header({ Name = "Speed" })
        feature(LS, "Speed", "Speed", "Overrides walk/sprint speed.")
        LS:Slider({ Name = "Walk Speed", Default = MOV.SpeedValue, Minimum = 16, Maximum = 120,
            Precision = 0, Callback = function(v) MOV.SpeedValue = v end }, flag("SpeedValue"))
        LS:Slider({ Name = "Sprint Speed", Default = MOV.SprintSpeed, Minimum = 16, Maximum = 200,
            Precision = 0, Callback = function(v) MOV.SprintSpeed = v end }, flag("SprintSpeed"))
        LS:Toggle({ Name = "Auto Sprint", Default = MOV.AutoSprint,
            Callback = function(v) MOV.AutoSprint = v end }, flag("AutoSprint"))

        -- ── Fly ───────────────────────────────────────────────────────────
        local LF = tab:Section({ Name = "Fly", Side = "Left" })
        LF:Header({ Name = "Fly" })
        feature(LF, "Fly", "Fly", "Free-cam style flight. Hold Space/Ctrl for up/down.")
        LF:Slider({ Name = "Fly Speed", Default = MOV.FlySpeed, Minimum = 8, Maximum = 200,
            Precision = 0, Callback = function(v) MOV.FlySpeed = v end }, flag("FlySpeed"))
        LF:Toggle({ Name = "TP Bypass", Default = MOV.FlyTPBypass ~= false,
            Callback = function(v)
                MOV.FlyTPBypass = v
                ntf("Fly TP Bypass", v and "Enabled" or "Disabled")
            end }, flag("FlyTPBypass"))
        LF:SubLabel({ Text = "Teleport-bypass: keeps the server position in sync while flying to avoid rubber-band kicks." })

        -- ── No Clip ───────────────────────────────────────────────────────
        local LC = tab:Section({ Name = "No Clip", Side = "Left" })
        LC:Header({ Name = "No Clip" })
        feature(LC, "No Clip", "NoClip", "Walk through walls and objects.")

        -- ── Jump ─────────────────────────────────────────────────────────
        local LJ = tab:Section({ Name = "Jump", Side = "Left" })
        LJ:Header({ Name = "Jump" })
        LJ:Toggle({ Name = "Infinite Jump", Default = MOV.InfiniteJump,
            Callback = function(v)
                MOV.InfiniteJump = v
                ntf("Infinite Jump", v and "Enabled" or "Disabled")
            end }, flag("InfJump"))
        LJ:Toggle({ Name = "Bunny Hop", Default = MOV.BunnyHop,
            Callback = function(v)
                MOV.BunnyHop = v
                ntf("Bunny Hop", v and "Enabled" or "Disabled")
            end }, flag("Bhop"))
        LJ:Slider({ Name = "Super Jump Power", Default = MOV.SuperJumpVel, Minimum = 20, Maximum = 200,
            Precision = 0, Callback = function(v) MOV.SuperJumpVel = v end }, flag("SJVel"))
        if ui.keybind then
            ui.keybind(LJ, { Name = "Super Jump Keybind", Flag = flag("SuperJump_KB"),
                Toggle = function()
                    _M.superJump()
                    ntf("Super Jump", "Fired")
                end })
        end
        LJ:SubLabel({ Text = "Super Jump fires once per press (bind a key above)." })

        -- ── No Fall ───────────────────────────────────────────────────────
        local RNF = tab:Section({ Name = "No Fall", Side = "Right" })
        RNF:Header({ Name = "No Fall" })
        feature(RNF, "No Fall", "NoFall", "Spoofs the height state to cancel fall damage.")
        RNF:Toggle({ Name = "Lean on Sprint", Default = MOV.LeanSprint,
            Callback = function(v) MOV.LeanSprint = v end }, flag("LeanSprint"))
        RNF:Slider({ Name = "Lean Angle", Default = MOV.LeanAngle, Minimum = 0, Maximum = 20,
            Precision = 0, Suffix = "°", Callback = function(v) MOV.LeanAngle = v end }, flag("LeanAngle"))

        -- ── Third Person Camera ───────────────────────────────────────────
        local RTP = tab:Section({ Name = "Third Person", Side = "Right" })
        RTP:Header({ Name = "Third Person Camera" })
        feature(RTP, "Force Third Person", "ThirdPerson", "Forces a third-person camera.")
        RTP:Slider({ Name = "Camera Distance", Default = MOV.ThirdPersonDist, Minimum = 5, Maximum = 40,
            Precision = 0, Callback = function(v) MOV.ThirdPersonDist = v end }, flag("TPDist"))

        -- ── Spin Bot ─────────────────────────────────────────────────────
        local RSB = tab:Section({ Name = "Spin Bot", Side = "Right" })
        RSB:Header({ Name = "Spin Bot" })
        feature(RSB, "Spin Bot", "SpinBot", "Spins your third-person model.")
        RSB:Slider({ Name = "Spin Speed (RPS)", Default = MOV.SpinBotRPS, Minimum = 1, Maximum = 30,
            Precision = 0, Callback = function(v) MOV.SpinBotRPS = v end }, flag("SpinRPS"))

        -- ── Strafer ───────────────────────────────────────────────────────
        local RST = tab:Section({ Name = "Strafer", Side = "Right" })
        RST:Header({ Name = "Strafer" })
        feature(RST, "Strafer", "Strafer", "Free air-strafe (turn without input).")

        -- ── Velocity Desync ───────────────────────────────────────────────
        local RVD = tab:Section({ Name = "Velocity Desync", Side = "Right" })
        RVD:Header({ Name = "Velocity Desync" })
        feature(RVD, "Velocity Desync", "VelDesync", "Jitters replicated velocity to confuse prediction.")
        RVD:Slider({ Name = "Desync Amplitude", Default = MOV.VelocityDesyncAmp, Minimum = 0.5, Maximum = 10,
            Precision = 1, Suffix = " st", Callback = function(v) MOV.VelocityDesyncAmp = v end }, flag("VelAmp"))

        -- ── Lean Lock ─────────────────────────────────────────────────────
        local RLL = tab:Section({ Name = "Lean Lock", Side = "Right" })
        RLL:Header({ Name = "Lean Lock" })
        feature(RLL, "Lean Lock", "LeanLock", "Locks the lean value for a fixed body angle.")
        RLL:Slider({ Name = "Lean Value", Default = MOV.LeanLockValue, Minimum = -1, Maximum = 1,
            Precision = 2, Callback = function(v) MOV.LeanLockValue = v end }, flag("LeanVal"))

        -- ── Fake Angles ───────────────────────────────────────────────────
        -- Вместо Dropdown+Keybind: простой Toggle ON/OFF (Keybind) + выбор режима через Dropdown.
        -- Keybind включает/выключает последний выбранный режим (не Off).
        local FA = tab:Section({ Name = "Fake Angles", Side = "Right" })
        FA:Header({ Name = "Fake Angles" })
        local FA_MODES = { "Instant", "Spin", "Random", "Backwards", "Jitter", "Twitch" }
        -- Enabled toggle: On = включает первый/последний режим, Off = режим 0 (Off)
        local _faNotifyBlocked = false
        FA:Toggle({ Name = "Enabled", Default = _M.getFakeAngMode() ~= 0,
            Callback = function(v)
                if v then
                    local mode = _M.getFakeAngMode()
                    if mode == 0 then _M.setFakeAngMode(1) end
                else
                    _M.setFakeAngMode(0)
                end
                if not _faNotifyBlocked then
                    ntf("Fake Angles", v and "Enabled" or "Disabled")
                end
            end }, flag("FAEnabled"))
        if ui.keybind then
            ui.keybind(FA, { Name = "Keybind", Flag = flag("FA_KB"),
                Toggle = function()
                    local mode = _M.getFakeAngMode()
                    _faNotifyBlocked = true
                    if mode ~= 0 then
                        _M.setFakeAngMode(0)
                        syncToggle(flag("FAEnabled"), false)
                        _faNotifyBlocked = false
                        ntf("Fake Angles", "Disabled")
                    else
                        _M.setFakeAngMode(1)
                        syncToggle(flag("FAEnabled"), true)
                        _faNotifyBlocked = false
                        ntf("Fake Angles", "Enabled")
                    end
                end })
        end
        FA:Dropdown({ Name = "Mode", Options = FA_MODES, Default = FA_MODES[math.max(1, _M.getFakeAngMode())] or "Instant",
            Callback = function(n)
                local idx = table.find(FA_MODES, n)
                if idx then
                    _M.setFakeAngMode(idx)
                    _faNotifyBlocked = true
                    syncToggle(flag("FAEnabled"), true)
                    _faNotifyBlocked = false
                    ntf("Fake Angles Mode", n)
                end
            end }, flag("FAMode"))
        FA:SubLabel({ Text = "Spoofs replicated body angles. Does NOT affect your aim/shots." })
        FA:Slider({ Name = "Jitter (yaw)", Default = MOV.FakeAnglesJitter, Minimum = 0, Maximum = 6.28,
            Precision = 2, Callback = function(v) MOV.FakeAnglesJitter = v end }, flag("FAJitter"))
        FA:Slider({ Name = "Pitch Amount", Default = MOV.FakeAnglesPitchAmp, Minimum = 0, Maximum = 3.14,
            Precision = 2, Callback = function(v) MOV.FakeAnglesPitchAmp = v end }, flag("FAPitch"))
        FA:Slider({ Name = "Spin Step", Default = MOV.FakeAnglesSpinStep, Minimum = 0.1, Maximum = 3.14,
            Precision = 2, Callback = function(v) MOV.FakeAnglesSpinStep = v end }, flag("FASpin"))
        FA:Divider()
        FA:Header({ Name = "Ghost" })
        FA:Toggle({ Name = "Show Ghost Model", Default = MOV.FakeAnglesGhost,
            Callback = function(v) MOV.FakeAnglesGhost = v end }, flag("FAGhost"))
        FA:Colorpicker({ Name = "Ghost Color", Default = MOV.FakeAnglesGhostColor,
            Callback = function(c) MOV.FakeAnglesGhostColor = c end }, flag("FAGhostCol"))
        FA:Slider({ Name = "Ghost Transparency", Default = math.floor((MOV.FakeAnglesGhostTransparency or 0.5) * 100),
            Minimum = 0, Maximum = 100, Precision = 0, Suffix = "%",
            Callback = function(v) MOV.FakeAnglesGhostTransparency = v / 100 end }, flag("FAGhostTr"))

        -- ── Speed State ───────────────────────────────────────────────────
        local RSS = tab:Section({ Name = "Speed State", Side = "Right" })
        RSS:Header({ Name = "Speed State" })
        local order = MOV.SpeedStateOrder or { "Skydiving", "Parachuting", "Proning" }
        local ssOpts = { "Off" }
        for _, n in ipairs(order) do ssOpts[#ssOpts + 1] = n end
        RSS:Dropdown({ Name = "State", Options = ssOpts, Default = ssOpts[(_M.getSpeedStateMode() or 0) + 1] or "Off",
            Callback = function(n)
                local idx = table.find(ssOpts, n)
                if idx then
                    _M.setSpeedStateMode(idx - 1)
                    ntf("Speed State", n)
                end
            end }, flag("SpeedState"))
        if ui.keybind then
            ui.keybind(RSS, { Name = "Cycle Keybind", Flag = flag("SSCycle_KB"),
                Toggle = function()
                    _M.simulateKey(MOV.SpeedStateKey)
                    ntf("Speed State", "Cycled")
                end })
        end
        RSS:SubLabel({ Text = "Applies a movement-state multiplier (e.g. Skydiving is very fast)." })

        -- ── Debug subsection ───────────────────────────────────────────────
        if dtab then
            local D = dtab:Section({ Name = "Movement", Side = "Right" })
            D:Header({ Name = "Movement — Fake Angles" })
            D:Slider({ Name = "Ghost Update Rate", Default = MOV.FakeAnglesSendHz or 22, Minimum = 5, Maximum = 60,
                Precision = 0, Suffix = " Hz", Callback = function(v) MOV.FakeAnglesSendHz = v end }, flag("DbgFAHz"))
            D:Slider({ Name = "State Hold (packets)", Default = MOV.FakeAnglesStateHold or 8, Minimum = 1, Maximum = 30,
                Precision = 0, Callback = function(v) MOV.FakeAnglesStateHold = v end }, flag("DbgFAHold"))
            D:Toggle({ Name = "Clamp Safe Angles", Default = MOV.FakeAnglesClampSafe,
                Callback = function(v) MOV.FakeAnglesClampSafe = v end }, flag("DbgFAClamp"))
            D:Toggle({ Name = "Suppress Game Packet", Default = MOV.FakeAnglesSuppressGame,
                Callback = function(v) MOV.FakeAnglesSuppressGame = v end }, flag("DbgFASuppress"))
            D:Divider()
            D:Header({ Name = "Movement — Logging" })
            D:SubLabel({ Text = "Console diagnostics. Leave off for normal play." })
            D:Toggle({ Name = "Fake Angles Diagnostics", Default = MOV.FakeAnglesDiag,
                Callback = function(v) MOV.FakeAnglesDiag = v end }, flag("DbgFADiag"))
            D:Slider({ Name = "Diagnostic Packet Count", Default = MOV.FakeAnglesDiagCount or 20, Minimum = 5, Maximum = 100,
                Precision = 0, Callback = function(v) MOV.FakeAnglesDiagCount = v end }, flag("DbgFADiagN"))
            D:Button({ Name = "Run Diagnostic (console)", Callback = function() task.spawn(runDiagnostic) end }, flag("DbgRunDiag"))
        end
    end

    return _M
end
