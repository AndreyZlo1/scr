--[[
    BRM5 Visuals / World  v2  (scripts/visuals.lua)
    Контракт загрузчика: файл возвращает function(Lib) -> { start=fn, stop=fn }

    ── ХОТКЕИ (Numpad) ─────────────────────────────────────────────────────────
      Num1  Viewmodel      — смещение рук, FOV, материал/цвет рук от 1-го лица
      Num2  GunModel       — подсветка оружия (как ResolveAngle-виз)
      Num3  ThirdPersonSkin— стилизация СВОЕЙ модели в 3-м лице (камера в movement)
      Num4  VehicleFly     — полёт на транспорте (WASD + Space/Ctrl)
      Num5  VehicleSpeed   — множитель скорости транспорта
      KpEnter FreeGun      — снять блок экипировки оружия (в транспорте и пр.)
      Num6  Ambient        — время суток и яркость (только клиент)
      Num7  NoFWait        — убирает hold-таймер ProximityPrompt
      Num8  LockpickBypass — авто-успех мини-игры взлома
      Num9  Fullbright     — максимальное освещение без теней
      Num0  NoFog          — убирает туман

    ── ЧТО ИГРА ХРАНИТ (дамп Flux, для справки) ────────────────────────────────
      _localActor : { UID, Alive, IsLocalPlayer, Character, CFrame, SimulatedPosition,
                      ForceNextPosition, HeightState, Zoom, CameraZoom, ViewModel,
                      Controller, CurrentState, Focused, Seat, Vehicle }
      ViewModel   : { Root(BasePart), Offset(CFrame), ADSOffset, ADSLerp, CQB,
                      SprintLerp, NVGFOV, Canted, Recoil, Material, :SetModel,
                      :Update }   ← Update() ставит Root.CFrame каждый кадр
      Camera      : FieldOfView пересчитывается КАЖДЫЙ кадр → FOV меняем через
                    BindToRenderStep (приоритет после камеры)
      Vehicle     : { Throttle, Steering, Seats, VehicleMain, _derivedVelocity }
      LockPickCtrl: { _picks(0..6), _speed, _expires, _cancelled, _localActor }
                    при _picks==6 шлёт FireServer("ActivateInteract","Picked")
]]

return function(Lib)
    local CONFIG = Lib.CONFIG
    local State  = Lib.State
    local Bridge = Lib.Bridge   -- нужен для общего UI-kit (Bridge.makeUiKit)

    local RunService = game:GetService("RunService")
    local UIS        = game:GetService("UserInputService")
    local Lighting   = game:GetService("Lighting")
    local Workspace  = game:GetService("Workspace")
    local Players    = game:GetService("Players")
    local PPS        = game:GetService("ProximityPromptService")
    local LP         = Players.LocalPlayer

    local function now() return os.clock() end
    local function log() end   -- logging disabled (was print("[VIS]", ...))

    ---------------------------------------------------------------------------
    -- ⚙️  НАСТРОЙКИ ВИЗУАЛОВ  ─────────────────────────────────────────────────
    --  Всё, что можно менять, лежит ЗДЕСЬ, в одной таблице SETTINGS.
    --  Формат: Ключ = значение,  -- пояснение.
    --  *Enabled  — включена ли фича (можно стартовать сразу включённой).
    --  *Key      — хоткей (Numpad). Меняй на любой Enum.KeyCode.
    --  Цвета: Color3.fromRGB(r,g,b).  Материалы: Enum.Material.*.
    ---------------------------------------------------------------------------
    CONFIG.Visuals = CONFIG.Visuals or {}
    local V = CONFIG.Visuals

    local SETTINGS = {
        --== 1 · VIEWMODEL — вид РУК от первого лица (перекраска/материал/сдвиг) ==
        --   Оружие красит отдельная фича GunModel (№2). Хоткей: Numpad 1.
        ViewmodelEnabled          = false,
        ViewmodelKey              = Enum.KeyCode.KeypadOne,
        ViewmodelColorEnabled     = true,                        -- красить руки (ВКЛ → эффект виден сразу)
        ViewmodelColor            = Color3.fromRGB(0, 200, 255), -- цвет рук
        -- ВКЛ по умолчанию: ForceField даёт красивое равномерное свечение и, что
        -- важно, ПЕРЕКРЫВАЕТ текстуры/SurfaceAppearance рукавов и перчаток —
        -- поэтому теперь рукав/перчатка красятся так же, как сама рука.
        ViewmodelMaterialEnabled  = true,                        -- менять материал рук
        ViewmodelMaterial         = Enum.Material.ForceField,
        ViewmodelTransparency     = 0,                           -- 0..1 прозрачность рук (0 = как есть)
        ViewmodelOffset           = Vector3.new(0, 0, 0),        -- сдвиг рук: право / верх / назад (studs)
        ViewmodelTilt             = 0,                           -- наклон рук (градусы)
        ViewmodelDepth            = 0,     -- приближение рук по Z, в сотых studs (0 = как в игре)
        WorldFOVEnabled           = false, -- мировой FOV камеры (отдельно от рук)
        WorldFOV                  = 70,

        --== 2 · GUNMODEL — подсветка МОДЕЛИ ОРУЖИЯ. Хоткей: Numpad 2 ==
        GunModelEnabled           = false,
        GunModelKey               = Enum.KeyCode.KeypadTwo,
        GunModelHighlightEnabled  = true,   -- show Highlight instance on gun
        GunModelFill              = Color3.fromRGB(0, 170, 255),
        GunModelOutline           = Color3.fromRGB(255, 255, 255),
        GunModelFillTransparency  = 0.5,
        GunModelOutlineTransparency = 0,
        -- Те же «визуалы», что и у рук (Viewmodel): реальная перекраска частей
        -- оружия + смена материала (ForceField перекрывает текстуры/камо).
        GunModelColorEnabled      = true,
        GunModelColor             = Color3.fromRGB(0, 170, 255),
        GunModelMaterialEnabled   = true,
        GunModelMaterial          = Enum.Material.ForceField,
        GunModelTransparency      = 0,                           -- 0..1 прозрачность оружия

        --== 3 · THIRD PERSON SKIN — стилизация СВОЕЙ модели в 3-м лице. Numpad 3 ==
        --   (камерой рулит movement; тут только внешний вид тела)
        ThirdPersonEnabled        = false,
        ThirdPersonKey            = Enum.KeyCode.KeypadThree,
        ThirdPersonFill           = Color3.fromRGB(120, 200, 255),
        ThirdPersonOutline        = Color3.fromRGB(180, 235, 255),
        ThirdPersonFillTransparency = 0.55,
        ThirdPersonMaterial       = Enum.Material.Glass,          -- nil = не менять материал
        ThirdPersonBodyColor      = Color3.fromRGB(120, 200, 255),
        ThirdPersonBodyTransparency = 0.35,

        --== 3b · GRADIENT — плавный градиент МЕЖДУ ДВУМЯ ЦВЕТАМИ ==
        --   НЕ радуга: цвет пингпонг-л��рпит ColorA ⇆ ColorB (по умолчанию
        --   светло-фиолетовый ⇆ голубой). Работает поверх перекраски рук/оружия/
        --   тела. Для оружия «умный»: фаза бежит волной по частям (GradientSpread),
        --   поэтому части переливаются постепенно, а не все разом.
        ViewmodelGradientEnabled   = false,   -- переливать руки (Viewmodel)
        GunModelGradientEnabled    = false,   -- переливать оружие (GunModel)
        GunModelHighlightGradient  = true,    -- и обводку тоже красить волной
        ThirdPersonGradientEnabled = false,   -- переливать тело (ThirdPerson)
        GradientSpeed              = 0.35,     -- скорость перелива (циклов A⇆B в секунду)
        GradientColorA             = Color3.fromRGB(190, 150, 255), -- светло-фиолетовый
        GradientColorB             = Color3.fromRGB(120, 210, 255), -- голубой
        GunModelGradientSpread     = 1.6,      -- «растяжение» волны по частям оружия (0 = все синхронно)

        --== 4 · VEHICLE FLY — полёт на транспорте (WASD + Space/Ctrl). Numpad 4 ==
        VehicleFlyEnabled         = false,
        VehicleFlyKey             = Enum.KeyCode.KeypadFour,
        VehicleFlySpeed           = 120,                          -- studs/сек

        --== 5 · VEHICLE SPEED — множитель скорости транспорта. Numpad 5 ==
        VehicleSpeedEnabled       = false,
        VehicleSpeedKey           = Enum.KeyCode.KeypadFive,
        VehicleSpeedMult          = 2.0,

        --== 5b · FREE GUN — снять блок экипировки оружия (в транспорте и пр.). KeypadEnter ==
        -- Игра гейтит экипировку в InventoryService._canEquip: в транспорте
        -- HeightState==Sitting и SeatCanEquip==false → оружие не достать.
        -- FreeGun хукает _canEquip (возвращает true) и держит SeatCanEquip=true.
        FreeGunEnabled            = false,
        FreeGunKey                = Enum.KeyCode.KeypadEnter,

        --== 6 · AMBIENT — время суток и яркость (только у тебя). Numpad 6 ==
        AmbientEnabled            = false,
        AmbientPreset             = "Custom",
        AmbientColor              = Color3.fromRGB(120, 120, 130),
        AmbientOutdoorColor       = Color3.fromRGB(140, 140, 150),
        AmbientTintTop            = Color3.fromRGB(0, 0, 0),
        AmbientTintBottom         = Color3.fromRGB(0, 0, 0),
        AmbientExposure           = 0,
        AmbientLatitude           = 45,
        AmbientDiffuse            = 1,
        AmbientSpecular           = 1,
        AmbientShadows            = true,
        AmbientFogEnabled         = false,
        AmbientFogColor           = Color3.fromRGB(150, 160, 175),
        AmbientFogStart           = 0,
        AmbientFogEnd             = 800,
        AmbientKey                = Enum.KeyCode.KeypadSix,
        AmbientClockTime          = 14,                           -- 0..24 (14 = день, 0 = ночь)
        AmbientBrightness         = 2,

        --== 7 · NO F WAIT — убирает hold-таймер взаимодействий (F). Numpad 7 ==
        NoFWaitEnabled            = false,
        NoFWaitKey                = Enum.KeyCode.KeypadSeven,

        --== 8 · LOCKPICK BYPASS — авто-успех мини-игры взлома. Numpad 8 ==
        LockpickBypassEnabled     = false,
        LockpickBypassKey         = Enum.KeyCode.KeypadEight,
        LockpickScanInterval      = 0.4,                          -- как часто (сек) искать активный замок, если стейт неизвестен

        --== 9 · FULLBRIGHT — максимум света без теней. Numpad 9 ==
        FullbrightEnabled         = false,
        FullbrightKey             = Enum.KeyCode.KeypadNine,

        --== 0 · NO FOG — убирает туман. Numpad 0 ==
        NoFogEnabled              = false,
        NoFogKey                  = Enum.KeyCode.KeypadZero,
    }

    -- применяем дефолты, не затирая уже заданные пользователем значения
    for k, val in pairs(SETTINGS) do if V[k] == nil then V[k] = val end end

    ---------------------------------------------------------------------------
    -- GC-ФАЙНДЕРЫ
    ---------------------------------------------------------------------------
    local function isCtrl(t)
        if type(t) ~= "table" then return false end
        if type(rawget(t, "MoveSpeed"))    ~= "number"  then return false end
        if type(rawget(t, "IsGrounded"))   ~= "boolean" then return false end
        if type(rawget(t, "IsSprinting"))  ~= "boolean" then return false end
        local la = rawget(t, "_localActor")
        return type(la) == "table" and rawget(la, "IsLocalPlayer") ~= false
    end
    local _scanCd, _lastScan = 1.0, -999
    local _ctrl
    local _ctrlRescan = -999
    -- жив ли актор этого контроллера?
    local function ctrlAlive(c)
        local la = c and rawget(c, "_localActor")
        return type(la) == "table" and rawget(la, "Alive") ~= false
    end
    local function rescanCtrl()
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "MoveSpeed", "VelocityGravity", "TrySprinting", "IsGrounded", "IsSprinting" } })
        if not ok then return nil end
        -- предпочитаем ЖИВОЙ контроллер (после респавна старый _ctrl мёртв, но
        -- его таблица ещё проходит isCtrl → без этого 3-е лицо не возвращалось)
        local firstValid
        for _, v in ipairs(gc) do
            if isCtrl(v) then
                firstValid = firstValid or v
                if ctrlAlive(v) then _ctrl = v; return v end
            end
        end
        if firstValid then _ctrl = firstValid end
        return firstValid
    end
    local function findCtrl()
        -- кэш валиден И актор жив → используем без сканов
        if _ctrl and isCtrl(_ctrl) and ctrlAlive(_ctrl) then return _ctrl end
        -- кэш есть, но актор мёртв (умерли/респавн): троттлим ре-скан на живой
        if _ctrl and isCtrl(_ctrl) then
            local t = now()
            if t - _ctrlRescan >= _scanCd then
                _ctrlRescan = t
                local fresh = rescanCtrl()
                if fresh then return fresh end
            end
            return _ctrl   -- пока живого нет — возвращаем мёртвый (мы реально мертвы)
        end
        _ctrl = nil
        return rescanCtrl()
    end
    local function getLA()
        local c = findCtrl(); return c and rawget(c, "_localActor") or nil
    end

    -- (поиск транспорта переехал в findVehicleController — секция VEHICLE FLY/SPEED)

    -- LockPickController (активная мини-игра)
    local function isLockPick(t)
        return type(t) == "table"
            and type(rawget(t, "_picks")) == "number"
            and rawget(t, "_expires") ~= nil
            and type(rawget(t, "_localActor")) == "table"
            and rawget(t, "_cancelled") ~= nil
    end
    local function findLockPick()
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "_picks", "_speed", "_expires", "_cancelled" } })
        if not ok then return nil end
        for _, v in ipairs(gc) do
            if isLockPick(v) and not rawget(v, "_cancelled") then return v end
        end
    end

    -- Net module (для LockpickBypass)
    local function isNetObj(v)
        if type(v) ~= "table" then return false end
        local ok, fs = pcall(function() return v.FireServer end)
        return ok and type(fs) == "function"
            and type(rawget(v, "_code")) == "string"
            and type(rawget(v, "_events")) == "table"
    end
    local function findNet()
        if isNetObj(State.networkModule) then return State.networkModule end
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "_code", "_key", "_events", "_functions" } })
        if not ok then return nil end
        for _, v in ipairs(gc) do
            if isNetObj(v) then State.networkModule = v; return v end
        end
    end

    ---------------------------------------------------------------------------
    -- 1. VIEWMODEL hook (пост-смещение ПОСЛЕ игрового Update)
    --
    -- ВАЖНО: hookfunction(orig, hook) -> origRef
    --   origRef — это безопасный вызываемый «оригинал». Вызов самого orig
    --   внутри hook уже перенаправлен на hook → бесконечная рекурсия.
    --   Всегда вызываем возвращённый origRef.
    ---------------------------------------------------------------------------
    -- Объявлен ЗДЕСЬ, до хука viewmodel: хук читает `running`, и если объявить
    -- локал ниже (у главного цикла), внутри хука он станет глобалом=nil и
    -- Viewmodel/GunModel перестанут применяться.
    local running     = false
    local vmHooked    = false
    local vmOrigRef   = nil   -- ← значение, ВОЗВРАЩЁННОЕ hookfunction (НЕ исходный rawget)
    local vmHookMode  = nil   -- "hookfunction" | "field" — как ставили, так и снимаем
    local vmHookTbl   = nil   -- таблица класса для field-режима (cls.Update = orig)
    local vmHookFn    = nil   -- исходная функция для hookfunction-режима
    -- FIX: раньше `local gunHighlight` объявлялся НИЖЕ (стр. 624) — уже после
    -- замыкания хука, которое его использует. Из-за этого обращения внутри
    -- хука компилировались как ГЛОБАЛ, а весь код очистки (хоткей, stop,
    -- тоггл в UI) захватывал пустой локал → gunHighlight:Destroy() никогда
    -- не выполнялся и Highlight утекал навсегда. Теперь объявлен ДО хука.
    local gunHighlight = nil

    -- Список стилизованных частей: { [part] = { M, C, T } } для restore
    local vmStyledParts  = {}
    local vmStyledVM     = nil
    local _vmStyleApplied = nil   -- FIX: declared here so restoreViewmodelStyle can reset it
    local _vmRestyleT     = 0     -- время последнего пере-обхода частей рук

    local function restoreViewmodelStyle()
        for part, s in pairs(vmStyledParts) do
            if part and part.Parent then
                pcall(function()
                    part.Material    = s.M
                    part.Color       = s.C
                    part.Transparency = s.T
                    if s.tex ~= nil then part.TextureID = s.tex end
                end)
            end
            -- вернуть отключённые SurfaceAppearance (иначе рукав останется без текстуры)
            if s.sa then
                for _, rec in ipairs(s.sa) do
                    pcall(function()
                        if rec.inst and rec.parent then rec.inst.Parent = rec.parent end
                    end)
                end
            end
        end
        vmStyledParts = {}
        vmStyledVM    = nil
        _vmStyleApplied = nil
    end

    -- ── ПОДХОД (переписан): красим ИМЕННО РУКИ ────────────────────────────
    -- По дампу ViewmodelClass руки — это _leftArm / _rightArm (MeshPart'ы) плюс
    -- приваренные к ним перчатки/рукава/часы (Part0 = _leftArm/_rightArm,
    -- Parent = _container). Оружие — это отдельная _container-модель CurrentModel.
    -- Раньше стилизация опиралась ТОЛЬКО на об��од контейнера, и если руки лежали
    -- не там / грузились позже — эффекта не было («не работает»). Теперь мы
    -- ЯВНО берём _leftArm/_rightArm + их потомков И добираем контейнер (минус
    -- оружие). Плюс каждый кадр ПЕРЕ-применяем цвет к уже пойманным частям, если
    -- игра/анимации его сбросили — так эффект реально держится и виден.
    -- Обобщённое ядро: красит одну часть и сохраняет оригинал в store.
    -- opts = { colorOn, color, matOn, mat, transp }. Возвращает true если тронул.
    local function stylePartInto(d, store, opts)
        if not (d:IsA("BasePart") or d:IsA("MeshPart")) then return false end
        local paint = opts.colorOn or opts.matOn
        if store[d] == nil then
            local rec = { M = d.Material, C = d.Color, T = d.Transparency }
            -- Текстуры/камо (TextureID у MeshPart, SurfaceAppearance/Decal/Texture)
            -- перекрывают наш цвет — снимаем их с сохранением для восстановления.
            if paint then
                if d:IsA("MeshPart") and d.TextureID ~= "" then rec.tex = d.TextureID end
                local sa = {}
                for _, ch in ipairs(d:GetChildren()) do
                    if ch:IsA("SurfaceAppearance") or ch:IsA("Decal") or ch:IsA("Texture") then
                        sa[#sa + 1] = { inst = ch, parent = ch.Parent }
                    end
                end
                if #sa > 0 then rec.sa = sa end
            end
            store[d] = rec
        end
        local rec = store[d]
        pcall(function()
            if opts.matOn   then d.Material = opts.mat   end
            if opts.colorOn then d.Color    = opts.color end
            if paint then
                if rec.tex ~= nil and d:IsA("MeshPart") and d.TextureID ~= "" then
                    d.TextureID = ""
                end
                if rec.sa then
                    for _, r in ipairs(rec.sa) do
                        if r.inst and r.inst.Parent then r.inst.Parent = nil end
                    end
                end
            end
            -- При transp > 0 → ставим, при transp == 0 → восстанавливаем оригинал (если часть не полностью невидима)
            if (opts.transp or 0) > 0 then
                if d.Transparency < 1 then d.Transparency = opts.transp end
            elseif rec and (rec.T or 0) < 1 then
                d.Transparency = rec.T or 0
            end
        end)
        return true
    end

    -- восстановление произвольного store (руки ИЛИ оружие)
    local function restoreStore(store)
        for part, s in pairs(store) do
            if part and part.Parent then
                pcall(function()
                    part.Material     = s.M
                    part.Color        = s.C
                    part.Transparency = s.T
                    if s.tex ~= nil then part.TextureID = s.tex end
                end)
            end
            if s.sa then
                for _, rec in ipairs(s.sa) do
                    pcall(function()
                        if rec.inst and rec.parent then rec.inst.Parent = rec.parent end
                    end)
                end
            end
        end
        table.clear(store)
    end

    -- ── GRADIENT (плавный перелив между ДВУМЯ цветами, НЕ радуга) ─────────────
    -- phase01 крутится 0..1; треугольная (пинг-понг) волна t: 0→1→0 даёт
    -- плавный ColorA → ColorB → ColorA без резкого скачка на стыке цикла.
    local function gradientColorAt(phase01)
        local a = V.GradientColorA or Color3.fromRGB(190, 150, 255)
        local b = V.GradientColorB or Color3.fromRGB(120, 210, 255)
        local p = phase01 % 1
        local t = (p < 0.5) and (p * 2) or (2 - p * 2)   -- ping-pong 0..1..0
        return a:Lerp(b, t)
    end
    -- Фаза части по её ИНДЕКСУ в store (не по мировой позиции — та меняется при движении и даёт джиттер).
    -- Индекс определяется один раз: сортируем части по начальной мировой Y+X, присваиваем idx.
    -- spread растягивает/сжимает волну по индексам; 0 → все части в фазе (синхронно).
    -- Вынесено из горячего цикла: одна функция вместо замыкания на часть/кадр.
    local function _setPartColor(part, col) part.Color = col end
    local function tickGradientStore(store, spread, baseHue)
        -- 1) Собираем пары (part, rec) где нужно посчитать gp
        -- FIX: таблица needPhase создавалась каждый вызов, даже когда все фазы
        -- уже посчитаны (обычный случай) — теперь только по факту необходимости.
        local needPhase = nil
        local total = 0
        for part, rec in pairs(store) do
            if part and part.Parent then
                total = total + 1
                if rec.gp == nil then
                    needPhase = needPhase or {}
                    needPhase[part] = rec
                end
            end
        end
        if total == 0 then return end
        -- 2) Для частей без фазы — назначаем по сортировке idx/total
        if needPhase then
            local arr = {}
            for part in pairs(needPhase) do arr[#arr + 1] = part end
            -- Сортировка по базовой позиции: стабильная, не меняется при движении игрока
            table.sort(arr, function(a, b)
                local pa = pcall(function() return a.Position end) and a.Position or Vector3.zero
                local pb = pcall(function() return b.Position end) and b.Position or Vector3.zero
                return (pa.Y + pa.X) < (pb.Y + pb.X)
            end)
            for i, part in ipairs(arr) do
                local rec = needPhase[part]
                if rec then
                    rec.gp = ((i - 1) / math.max(1, #arr)) * (spread or 1)
                end
            end
        end
        -- 3) Красим с кэшированными фазами
        for part, rec in pairs(store) do
            if part and part.Parent then
                -- FIX: было pcall(function() ... end) — новое замыкание на КАЖДУЮ
                -- часть КАЖДЫЙ кадр (2-4 тысячи аллокаций в секунду → GC-нагрузка
                -- и микрофризы). Теперь передаём аргументы в готовую функцию.
                pcall(_setPartColor, part, gradientColorAt(baseHue + (rec.gp or 0)))
            end
        end
    end

    local function styleOnePart(d, weapon)
        if weapon and d:IsDescendantOf(weapon) then return end   -- это оружие → мимо
        stylePartInto(d, vmStyledParts, {
            -- при включённом градиенте красим всегда (иначе текстуры перекроют цвет)
            colorOn = V.ViewmodelColorEnabled or V.ViewmodelGradientEnabled,
            color   = V.ViewmodelColor,
            matOn   = V.ViewmodelMaterialEnabled,
            mat     = V.ViewmodelMaterial,
            transp  = V.ViewmodelTransparency,
        })
    end

    -- FIX: стиль применяется один раз и кэшируется по (vm/оружие). Смена
    -- материала, цвета или тумблеров кэш НЕ сбрасывала — работал только
    -- слайдер прозрачности, потому что он единственный звал restore*Style().
    -- Отсюда «материал переприменяется только при смене прозрачности».
    -- Эти два хелпера вызываются из UI на любое изменение стиля.
    local function invalidateVmStyle()
        restoreViewmodelStyle()
    end

    local function applyViewmodelStyle(vm)
        if vmStyledVM ~= nil and vmStyledVM ~= vm then
            restoreViewmodelStyle()  -- resets _vmStyleApplied = nil
        end
        -- FIX FPS: обходим GetDescendants только при смене vm/оружия.
        -- Раньше при включённом градиенте этот ранний выход пропускался и весь
        -- обход дерева шёл КАЖДЫЙ кадр — тысячи Instance-вызовов в секунду,
        -- ровно отсюда и брался просад FPS при включении градиента.
        -- Перекраску градиента делает tickGradientStore по уже собранному
        -- списку частей, повторно собирать его не нужно.
        -- FIX («после смерти меняет руки, но не рукав»): стиль применялся
        -- РОВНО ОДИН раз на объект viewmodel. Части рук (перчатки, рукав,
        -- часы) досоздаются игрой асинхронно — те, что появились после
        -- первого прохода, так и оставались неокрашенными. При первом
        -- включении обычно успевало, после респавна — нет.
        -- Решение то же, что уже работает для тела в thirdPersonStep:
        -- периодический пере-обход раз в VmRestyleSec (дёшево, не каждый кадр).
        local nowT = now()
        if _vmStyleApplied == vm and (nowT - _vmRestyleT) < (V.VmRestyleSec or 3) then
            return
        end
        _vmRestyleT = nowT
        _vmStyleApplied = vm
        local weapon = rawget(vm, "CurrentModel")   -- модель оружия — НЕ трогаем

        -- 1) явные корни рук + всё, что к ним приварено/вложено (перчатки, рукав, часы)
        for _, key in ipairs({ "_leftArm", "_rightArm" }) do
            local arm = rawget(vm, key)
            if typeof(arm) == "Instance" then
                styleOnePart(arm, weapon)
                for _, d in ipairs(arm:GetDescendants()) do styleOnePart(d, weapon) end
            end
        end

        -- 2) добор по контейнеру (на случай перчаток, вложенных в _container, а не в руку)
        local root = rawget(vm, "Root")
        local container = root and root.Parent
        if container then
            for _, d in ipairs(container:GetDescendants()) do styleOnePart(d, weapon) end
        end

        vmStyledVM = vm
    end

    -- ── GUNMODEL: та же перекраска/материал, но для МОДЕЛИ ОРУЖИЯ ──────────────
    local gunStyledParts  = {}     -- [part] = { M, C, T, tex, sa }
    local gunStyledModel  = nil
    local _gunStyleApplied = nil  -- FIX: declared here so restoreGunStyle can reset it
    local _gunRestyleT     = 0
    local function restoreGunStyle()
        restoreStore(gunStyledParts)
        gunStyledModel = nil
        _gunStyleApplied = nil
    end
    local function invalidateGunStyle()
        restoreGunStyle()
    end

    local function applyGunStyle(vm)
        local weapon = rawget(vm, "CurrentModel")
        if not (typeof(weapon) == "Instance" and weapon.Parent) then
            if gunStyledModel then restoreGunStyle() end  -- resets _gunStyleApplied = nil
            return
        end
        if gunStyledModel ~= nil and gunStyledModel ~= weapon then
            restoreGunStyle()   -- сменили ствол → вернуть старый
            _gunStyleApplied = nil
        end
        -- FIX FPS: GetDescendants только при смене ствола (см. коммент в
        -- applyViewmodelStyle) — при градиенте кэш больше не обходится.
        -- Та же периодическая доводка, что и для рук: аттачменты/магазин
        -- могут досоздаться после первого прохода.
        local nowG = now()
        if _gunStyleApplied == weapon and (nowG - _gunRestyleT) < (V.VmRestyleSec or 3) then
            return
        end
        _gunRestyleT = nowG
        _gunStyleApplied = weapon
        local opts = {
            colorOn = V.GunModelColorEnabled or V.GunModelGradientEnabled,
            color   = V.GunModelColor,
            matOn   = V.GunModelMaterialEnabled,
            mat     = V.GunModelMaterial,
            transp  = V.GunModelTransparency,
        }
        stylePartInto(weapon, gunStyledParts, opts)   -- no-op если weapon это Model
        for _, d in ipairs(weapon:GetDescendants()) do
            stylePartInto(d, gunStyledParts, opts)
        end
        gunStyledModel = weapon
    end

    local function ensureViewmodelHook()
        if vmHooked then return true end
        if type(hookfunction) ~= "function" then return false end
        if type(filtergc)     ~= "function" then return false end

        -- Ищем ViewmodelClass (таблица методов, общая для всех экземпляров)
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "Update", "SetModel", "AddReticle", "LoadAnimation" } })
        if not ok then return false end
        local cls
        for _, v in ipairs(gc) do
            if type(rawget(v, "Update")) == "function"
            and type(rawget(v, "SetModel")) == "function"
            and type(rawget(v, "AddReticle")) == "function" then
                cls = v; break
            end
        end
        if not cls then return false end

        local origFn = rawget(cls, "Update")
        if type(origFn) ~= "function" then return false end

        -- hookfunction возвращает origRef — именно его вызываем внутри хука
        local function newUpdate(self, dt, ...)
            -- FIX: хук раньше не проверял `running`, поэтому после M.stop()
            -- продолжал каждый кадр перекрашивать руки/оружие — и откатывал
            -- restoreViewmodelStyle буквально на следующем кадре.
            if not running then return vmOrigRef(self, dt, ...) end
            local r = table.pack(vmOrigRef(self, dt, ...))   -- ← vmOrigRef, не origFn!
            pcall(function()
                -- ГЕОМЕТРИЯ РУК (offset / tilt / zoom) — ВНЕ гейта
                -- V.ViewmodelEnabled.
                -- FIX: раньше этот блок был внутри `if V.ViewmodelEnabled`,
                -- то есть Hand Zoom и смещение работали только когда включена
                -- ПЕРЕКРАСКА рук. Это НЕ связанные вещи: человек крутил ползунок
                -- при выключенном тумблере и не понимал, почему ничего нет.
                --
                -- Про сам зум: «Custom FOV» раньше писал в Camera.FieldOfView —
                -- это мировой FOV (отсюда ощущение смены чувствительности). В
                -- BRM5 руки рендерятся ОБЩЕЙ камерой (дамп ViewmodelClass:822,
                -- FOV там только масштабирует отдачу), отдельной камеры для
                -- viewmodel нет. Честный аналог «зума рук» — двигать сами руки
                -- по оси Z.
                do
                    local root = rawget(self, "Root")
                    if root and root.Parent then
                        local o = V.ViewmodelOffset or Vector3.new()
                        local tilt = V.ViewmodelTilt or 0
                        local depth = (V.ViewmodelDepth or 0) / 100   -- studs
                        if o.Magnitude > 0.001 or math.abs(tilt) > 0.001
                        or math.abs(depth) > 0.0001 then
                            root.CFrame = root.CFrame
                                * CFrame.new(o.X, o.Y, -o.Z + depth)
                                * CFrame.Angles(0, 0, math.rad(tilt))
                        end
                    end
                end
                if V.ViewmodelEnabled then
                    -- стилизация рук — только один раз (не каждый кадр)
                    if V.ViewmodelMaterialEnabled or V.ViewmodelColorEnabled
                    or (V.ViewmodelTransparency or 0) > 0 or V.ViewmodelGradientEnabled then
                        applyViewmodelStyle(self)
                        -- градиент — перекрас каждый кадр под текущую фазу
                        if V.ViewmodelGradientEnabled then
                            tickGradientStore(vmStyledParts, 0.4, now() * (V.GradientSpeed or 0.35))
                        end
                    elseif vmStyledVM then
                        restoreViewmodelStyle()
                    end
                else
                    if vmStyledVM then restoreViewmodelStyle() end
                end
                -- GunModel Highlight — ТОЛЬКО модель оружия (self.CurrentModel),
                -- НЕ руки. Highlight держим в контейнере, адорним само оружие;
                -- при смене ствола игра пересоздаёт CurrentModel — переадорним.
                if V.GunModelEnabled then
                    local root2 = rawget(self, "Root")
                    local container = root2 and root2.Parent
                    local weapon = rawget(self, "CurrentModel")
                    -- Highlight is optional — can be disabled without disabling full GunModel
                    if V.GunModelHighlightEnabled ~= false then
                        if container and weapon and weapon.Parent then
                            if not (gunHighlight and gunHighlight.Parent) then
                                gunHighlight = Instance.new("Highlight")
                                gunHighlight.Name = "BRM5_GunHL"
                                gunHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            end
                            -- FIX: у Highlight не было градиента вообще —
                            -- переливалась только сама модель, а обводка
                            -- оставалась статичной, из-за чего эффект выглядел
                            -- рассинхронизированным. Теперь Highlight берёт
                            -- тот же цвет волны, что и части оружия.
                            if V.GunModelGradientEnabled and V.GunModelHighlightGradient ~= false then
                                local gcol = gradientColorAt(now() * (V.GradientSpeed or 0.35))
                                gunHighlight.FillColor    = gcol
                                gunHighlight.OutlineColor = gcol
                            else
                                gunHighlight.FillColor    = V.GunModelFill
                                gunHighlight.OutlineColor = V.GunModelOutline
                            end
                            gunHighlight.FillTransparency   = V.GunModelFillTransparency
                            gunHighlight.OutlineTransparency = V.GunModelOutlineTransparency
                            if gunHighlight.Adornee ~= weapon then gunHighlight.Adornee = weapon end
                            gunHighlight.Parent = container
                        elseif gunHighlight then
                            gunHighlight.Adornee = nil  -- оружие не экипировано сейчас
                        end
                    elseif gunHighlight then
                        -- Highlight toggled off while GunModel is still on
                        pcall(function() gunHighlight:Destroy() end); gunHighlight = nil
                    end
                    -- та же перекраска/материал, что и у рук — но для оружия
                    if V.GunModelColorEnabled or V.GunModelMaterialEnabled
                    or (V.GunModelTransparency or 0) > 0 or V.GunModelGradientEnabled then
                        applyGunStyle(self)
                        -- умный градиент: волна фазы бежит по частям (spread из конфига)
                        if V.GunModelGradientEnabled then
                            tickGradientStore(gunStyledParts, V.GunModelGradientSpread or 1.6,
                                now() * (V.GradientSpeed or 0.35))
                        end
                    elseif gunStyledModel then
                        restoreGunStyle()
                    end
                else
                    if gunHighlight then
                        pcall(function() gunHighlight:Destroy() end)
                        gunHighlight = nil
                    end
                    if gunStyledModel then restoreGunStyle() end
                end
            end)
            return table.unpack(r, 1, r.n)
        end

        local wrapped = (type(newcclosure) == "function")
            and newcclosure(newUpdate, "ViewmodelClass.Update")
            or newUpdate

        -- hookfunction возвращает оригинальный безопасный callable
        local hookOk, ret = pcall(hookfunction, origFn, wrapped)
        if hookOk and type(ret) == "function" then
            vmOrigRef  = ret
            vmHooked   = true
            vmHookMode = "hookfunction"
            vmHookFn   = origFn
            vmHookTbl  = cls
            log("Viewmodel hook OK (hookfunction)")
            return true
        end

        -- Fallback: заменяем метод в таблице
        -- В этом случае origFn и есть оригинал — кладём его в vmOrigRef
        vmOrigRef = origFn
        local ok2 = pcall(function() cls.Update = wrapped end)
        if ok2 then
            vmHooked   = true
            vmHookMode = "field"
            vmHookFn   = origFn
            vmHookTbl  = cls
            log("Viewmodel hook OK (table replace fallback)")
            return true
        end
        log("Viewmodel hook FAILED")
        return false
    end

    -- FIX: раньше хук не снимался НИКОГДА. После unload он продолжал жить и
    -- каждый кадр перекрашивал руки/оружие, а повторный запуск скрипта вешал
    -- хук поверх хука. Теперь снимаем ровно тем способом, каким ставили.
    local function unhookViewmodel()
        if not vmHooked then return end
        if vmHookMode == "hookfunction" and vmHookFn and vmOrigRef then
            pcall(hookfunction, vmHookFn, vmOrigRef)
        elseif vmHookMode == "field" and vmHookTbl and vmHookFn then
            pcall(function() vmHookTbl.Update = vmHookFn end)
        end
        vmHooked, vmHookMode, vmHookTbl, vmHookFn, vmOrigRef = false, nil, nil, nil, nil
    end

    -- (gunHighlight объявлен выше, до хука — см. FIX там)

    ---------------------------------------------------------------------------
    -- FOV override (после камеры каждый кадр)
    ---------------------------------------------------------------------------
    local FOV_BIND = "BRM5_FOV"
    local fovBound = false
    local fovApplied = false  -- флаг: мы изменили FOV → надо восстановить при выключении
    -- FIX: восстанавливали жёстко 70. Запоминаем настоящий FOV до первой правки.
    local _origFov = nil
    -- Мировой FOV камеры. ОТДЕЛЬНАЯ фича от «зума рук»: она реально меняет
    -- угол обзора всей сцены (и да, ощущается как смена чувствительности —
    -- это нормально и ожидаемо для FOV, поэтому вынесено в свой тумблер).
    local function fovStep()
        local fov = V.WorldFOV or 0
        if V.WorldFOVEnabled and fov > 0 then
            local cam = Workspace.CurrentCamera
            if cam then
                if not _origFov then _origFov = cam.FieldOfView end
                pcall(function() cam.FieldOfView = fov end)
                fovApplied = true
            end
        else
            if fovApplied then
                local cam = Workspace.CurrentCamera
                if cam then pcall(function() cam.FieldOfView = _origFov or 70 end) end
                fovApplied = false
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 3. THIRD PERSON SKIN
    ---------------------------------------------------------------------------
    local selfHighlight  = nil
    local tpOrig         = {}   -- [part] = { M, C, T }
    local tpStyledChar   = nil

    -- В этой игре НЕТ Roblox-персонажа (LP.Character почти всегда nil). Тело
    -- живёт на кастомном акторе: _localActor.Character. Берём его И только пока
    -- мы ЖИВЫ (la.Alive) — иначе после смерти будем стилизовать рэгдолл/чужие
    -- модели каждый кадр → просадка FPS.
    local function getSelfCharacter()
        -- FIX (Self Skin «вообще не работает»): раньше функция ВЫХОДИЛА, если
        -- не резолвился Flux-контроллер (getLA). findCtrl зависит от filtergc
        -- и на части экзекуторов/в лобби просто не находит контроллер — и
        -- фича молча ничего не делала, даже когда персонаж есть.
        -- Теперь Flux-путь опционален, а базовый LP.Character работает всегда.
        local la = getLA()
        if type(la) == "table" then
            if rawget(la, "Alive") == false then return nil end
            local ok, char = pcall(function() return la.Character end)
            if ok and typeof(char) == "Instance" and char:IsA("Model") and char.Parent then
                return char
            end
        end
        local c = LP.Character
        if typeof(c) == "Instance" and c:IsA("Model") and c.Parent then
            -- если есть Humanoid и он мёртв — не стилизуем труп
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then return nil end
            return c
        end
        return nil
    end

    local function applySelfHighlight(char)
        char = char or getSelfCharacter()
        if not char then return end
        if not (selfHighlight and selfHighlight.Parent) then
            selfHighlight = Instance.new("Highlight")
            selfHighlight.Name = "BRM5_SelfHL"
            selfHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
        selfHighlight.FillColor          = V.ThirdPersonFill
        selfHighlight.OutlineColor       = V.ThirdPersonOutline
        selfHighlight.FillTransparency   = V.ThirdPersonFillTransparency
        selfHighlight.OutlineTransparency = 0
        if selfHighlight.Adornee ~= char then selfHighlight.Adornee = char end
        selfHighlight.Parent = char
    end

    local function clearSelfHighlight()
        if selfHighlight then
            pcall(function() selfHighlight:Destroy() end)
            selfHighlight = nil
        end
    end

    local function restoreSelfBody()
        for part, s in pairs(tpOrig) do
            if part and part.Parent then
                pcall(function() part.Material     = s.M end)
                pcall(function() part.Color        = s.C end)
                pcall(function() part.Transparency = s.T end)
            end
        end
        tpOrig = {}
        tpStyledChar = nil
    end

    local function styleSelfBody(char)
        restoreSelfBody()
        local bodyTranp = V.ThirdPersonBodyTransparency or 0
        local styled = 0
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("MeshPart")) then
                local origT = d.Transparency
                -- FIX (Self Skin «вообще не работает»): здесь стоял
                -- `if origT >= 1 then continue end`. Игра сама выставляет
                -- Transparency = 1 частям тела (дамп ActorClass:1029 Model,
                -- :1419 Head; ViewmodelClass:334/366) — особенно в первом
                -- лице. То есть под условие попадали ПРАКТИЧЕСКИ ВСЕ части, и
                -- фича молча не делала ничего.
                --
                -- Смысл у старой проверки был: не записать T=1 как «оригинал»,
                -- иначе после restore часть осталась бы невидимой. Решаем
                -- иначе — часть стилизуем, но в оригинал пишем 0, чтобы
                -- restore вернул её видимой, а не спрятанной.
                local restoreT = (origT >= 1) and 0 or origT
                tpOrig[d] = { M = d.Material, C = d.Color, T = restoreT }
                -- Каждое свойство отдельно: отказ на одном (некоторые mesh
                -- в BRM5 не принимают Material) не блокирует остальные.
                if V.ThirdPersonMaterial then
                    pcall(function() d.Material = V.ThirdPersonMaterial end)
                end
                pcall(function() d.Color = V.ThirdPersonBodyColor end)
                pcall(function() d.Transparency = bodyTranp end)
                styled += 1
            end
        end
        tpStyledChar = char
        State._tpStyledCount = styled
    end

    local _tpRestyeT = 0
    local function thirdPersonStep()
        if not V.ThirdPersonEnabled then
            if tpStyledChar then restoreSelfBody() end
            clearSelfHighlight()
            return
        end
        local char = getSelfCharacter()
        if not char then
            -- мертвы / модели ещё нет: чистим виз, НЕ работаем каждый кадр
            if tpStyledChar then restoreSelfBody() end
            clearSelfHighlight()
            return
        end
        applySelfHighlight(char)
        -- FIX: check if character changed OR re-style every 3s to catch late-spawning parts
        -- (avoids calling styleSelfBody / GetDescendants on every single heartbeat frame)
        local t = now()
        if tpStyledChar ~= char or (t - _tpRestyeT) > 3 then
            _tpRestyeT = t
            styleSelfBody(char)
        end
        -- градиент по телу: перекрас каждый кадр под текущую фазу
        if V.ThirdPersonGradientEnabled then
            tickGradientStore(tpOrig, 0.5, now() * (V.GradientSpeed or 0.35))
        end
    end

    ---------------------------------------------------------------------------
    -- 4 + 5. VEHICLE FLY / SPEED
    ---------------------------------------------------------------------------
    -- ── КАК УСТРОЕН ТРАНСПОРТ (по дампу GroundController/VehicleClass) ─────────
    -- Активный контроллер машины (LocalActor.Controller) — это GroundController
    -- с полями: _solver, _tune, _vehicle, _throttle, _localActor. Игра меняет
    -- поведение машины ИМЕННО через _tune + _solver:NewTune() (так работают её
    -- собственные дебаг-слайдеры: AccelerationFactor, Mass, Grip …), а
    -- телепортирует машину методом _solver:SetState(cf, vel, angvel, compRep).
    -- Поэтому:
    --   • VehicleSpeed = увеличить _tune.AccelerationFactor и вызвать NewTune()
    --     (реально меняем параметры транспорта, как и просил юзер);
    --   • VehicleFly  = каждый кадр solver:SetState(новый CFrame, 0, 0, compRep).
    -- Старый код искал несуществующие поля (Throttle/Steering/Seats у объекта
    -- машины, LocalActor.Vehicle) → findVehicle никогда не находил → не работало.
    local function isVehicleController(t)
        if type(t) ~= "table" then return false end
        if type(rawget(t, "_solver")) ~= "table" then return false end
        if type(rawget(t, "_tune"))   ~= "table" then return false end
        local veh = rawget(t, "_vehicle")
        if type(veh) ~= "table" then return false end
        if rawget(veh, "Controlling") == false then return false end -- вышли из машины
        return true
    end
    local _vehCtrl
    local function findVehicleController()
        if isVehicleController(_vehCtrl) then return _vehCtrl end
        _vehCtrl = nil
        -- 1) через LocalActor.Controller — без сканов
        local la = getLA()
        if type(la) == "table" then
            local c = rawget(la, "Controller")
            if isVehicleController(c) then _vehCtrl = c; return c end
        end
        -- 2) GC-скан (троттлится) — персонажный контроллер в машине уничтожен,
        --    поэтому getLA() может не сработать; ищем контроллер напрямую.
        local t = now()
        if t - _lastScan < _scanCd then return nil end
        _lastScan = t
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "_solver", "_tune", "_vehicle", "_throttle" } })
        if not ok then return nil end
        for _, v in ipairs(gc) do
            if isVehicleController(v) then _vehCtrl = v; return v end
        end
        return nil
    end

    -- восстановление оригинальных параметров машины после VehicleSpeed.
    -- Храним снимок всех тронутых полей tune, чтобы вернуть штатное поведение.
    local _spdTune, _spdOrig, _spdSolver = nil, nil, nil
    local function restoreVehicleSpeed()
        if _spdTune and type(_spdOrig) == "table" then
            pcall(function()
                if _spdOrig.Accel ~= nil then _spdTune.AccelerationFactor = _spdOrig.Accel end
                if _spdOrig.Mass  ~= nil then _spdTune.Mass = _spdOrig.Mass end
                local fw, rw = rawget(_spdTune, "FrontWheels"), rawget(_spdTune, "RearWheels")
                if type(fw) == "table" and _spdOrig.FGrip ~= nil then fw.Grip = _spdOrig.FGrip end
                if type(rw) == "table" and _spdOrig.RGrip ~= nil then rw.Grip = _spdOrig.RGrip end
                if _spdSolver then _spdSolver:NewTune() end
            end)
        end
        _spdTune, _spdOrig, _spdSolver = nil, nil, nil
    end

    local function vehicleStep(dt)
        local wantAny = V.VehicleFlyEnabled or V.VehicleSpeedEnabled
        local ctrl = wantAny and findVehicleController() or nil

        -- вернуть оригинальную скорость, если SpeedHack выключен / сменилась машина
        if _spdTune and not (V.VehicleSpeedEnabled and ctrl and rawequal(rawget(ctrl, "_tune"), _spdTune)) then
            restoreVehicleSpeed()
        end
        if not ctrl then return end

        dt = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
        local solver  = rawget(ctrl, "_solver")
        local vehicle = rawget(ctrl, "_vehicle")
        local tune    = rawget(ctrl, "_tune")

        -- VEHICLE SPEED — меняем параметры транспорта (как дебаг-слайдеры игры).
        -- Прошлый вариант трогал только AccelerationFactor (в игре капается ~1) —
        -- он влияет на РАЗГОН, но почти не на максималку → эффект был незаметен.
        -- Главный рычаг максимальной скорости — Mass: при фиксированной силе движка
        -- и сопротивлении лёгкая машина имеет и выше разгон, и выше терминальную
        -- скорость. Дополнительно поднимаем Grip, чтобы на скорости не срывало.
        if V.VehicleSpeedEnabled and type(tune) == "table" then
            local mult = V.VehicleSpeedMult or 2
            if mult < 1 then mult = 1 end
            if not rawequal(_spdTune, tune) then
                restoreVehicleSpeed()
                _spdTune, _spdSolver = tune, solver
                local fw, rw = rawget(tune, "FrontWheels"), rawget(tune, "RearWheels")
                _spdOrig = {
                    Accel = rawget(tune, "AccelerationFactor"),
                    Mass  = rawget(tune, "Mass"),
                    FGrip = type(fw) == "table" and rawget(fw, "Grip") or nil,
                    RGrip = type(rw) == "table" and rawget(rw, "Grip") or nil,
                }
            end
            local o = _spdOrig
            -- целевые значения
            local wantMass  = (type(o.Mass) == "number") and (o.Mass / mult) or nil
            local wantAccel = (type(o.Accel) == "number") and math.min(o.Accel * mult, 1) or nil
            local wantFGrip = (type(o.FGrip) == "number") and (o.FGrip * math.min(mult, 3)) or nil
            local wantRGrip = (type(o.RGrip) == "number") and (o.RGrip * math.min(mult, 3)) or nil
            local dirty = false
            pcall(function()
                if wantMass and rawget(tune, "Mass") ~= wantMass then tune.Mass = wantMass; dirty = true end
                if wantAccel and rawget(tune, "AccelerationFactor") ~= wantAccel then tune.AccelerationFactor = wantAccel; dirty = true end
                local fw, rw = rawget(tune, "FrontWheels"), rawget(tune, "RearWheels")
                if type(fw) == "table" and wantFGrip and rawget(fw, "Grip") ~= wantFGrip then fw.Grip = wantFGrip; dirty = true end
                if type(rw) == "table" and wantRGrip and rawget(rw, "Grip") ~= wantRGrip then rw.Grip = wantRGrip; dirty = true end
                if dirty then solver:NewTune() end
            end)
        end

        -- VEHICLE FLY — репозиционируем машину штатным solver:SetState
        if V.VehicleFlyEnabled then
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local baseCF = rawget(vehicle, "CFrame")
            if typeof(baseCF) ~= "CFrame" then
                local st = rawget(solver, "_state")
                if type(st) == "table" and typeof(st.CFrame) == "CFrame" then
                    baseCF = st.CFrame
                end
            end
            if typeof(baseCF) ~= "CFrame" then return end
            local dir = Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W)           then dir += cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S)           then dir -= cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A)           then dir -= cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D)           then dir += cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            local step = (dir.Magnitude > 0.001)
                and (dir.Unit * (V.VehicleFlySpeed or 120) * dt)
                or  Vector3.zero
            local newCF = baseCF.Rotation + (baseCF.Position + step)
            local compRep = rawget(vehicle, "ComponentReplicates")
            pcall(function()
                solver:SetState(newCF, Vector3.zero, Vector3.zero, compRep)
            end)
            -- двигаем и VehicleMain, чтобы визуально не «резинило»
            local vm = rawget(vehicle, "VehicleMain")
            if typeof(vm) == "Instance" then
                pcall(function()
                    local p = vm:IsA("BasePart") and vm or vm.PrimaryPart
                    if p then p.CFrame = newCF end
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 5b. FREE GUN — снять блок экипировки оружия
    ---------------------------------------------------------------------------
    -- Блок находится в InventoryService._canEquip(self, localActor):
    --   • HeightState == Sitting (в транспорте) и not SeatCanEquip → false
    --   • Climbing/Vaulting/Swimming/Skydiving/Parachuting → false
    -- Хукаем сам метод: пока FreeGunEnabled — возвращаем true (живым, с контроллером).
    -- Хук ставится один раз и гейтится флагом, поэтому при выкле остаётся инертным
    -- (та же схема, что и у Viewmodel-хука выше).
    local _canEquipHooked = false
    local _canEquipCallOrig = nil        -- вызываемый оригинал
    local _fgScanCd = 0
    -- FIX: не хранили ни таблицу, ни режим установки → снять хук было нечем.
    local _fgTbl, _fgMode, _fgRawFn = nil, nil, nil
    -- FIX: SeatCanEquip форсился в true и никогда не возвращался обратно —
    -- фича «выключена», а оружие в транспорте всё равно достаётся.
    local _fgSeatOrig = nil
    local function installFreeGunHook()
        if _canEquipHooked then return true end
        local t = now()
        if t - _fgScanCd < 2.0 then return false end
        _fgScanCd = t
        if type(filtergc) ~= "function" then return false end
        local ok, res = pcall(filtergc, "table",
            { Keys = { "_canEquip", "_cycle", "_sync" } })
        if not ok or type(res) ~= "table" then return false end
        for _, tbl in ipairs(res) do
            local fn = rawget(tbl, "_canEquip")
            if type(fn) == "function" then
                _canEquipCallOrig = fn
                local wrapper = function(self, la)
                    if V.FreeGunEnabled and la and la.Alive
                        and la.Controller and not la.Downed then
                        return true
                    end
                    return _canEquipCallOrig(self, la)
                end
                -- 1) замена поля класса (обратимо и без детуров)
                local setOk = pcall(function() tbl._canEquip = wrapper end)
                if setOk and rawget(tbl, "_canEquip") == wrapper then
                    _canEquipHooked = true
                    _fgTbl, _fgMode, _fgRawFn = tbl, "field", fn
                    log("FreeGun: _canEquip перехвачен (field)")
                    return true
                end
                -- 2) таблица заморожена → hookfunction (origRef = callable оригинал)
                if type(hookfunction) == "function" then
                    local hookOk, origRef = pcall(hookfunction, fn, wrapper)
                    if hookOk then
                        _canEquipCallOrig = (type(origRef) == "function") and origRef or fn
                        _canEquipHooked = true
                        _fgTbl, _fgMode, _fgRawFn = tbl, "hookfunction", fn
                        log("FreeGun: _canEquip перехвачен (hookfunction)")
                        return true
                    end
                end
            end
        end
        return false
    end

    -- FIX: полностью снимаем FreeGun — и хук, и форс SeatCanEquip.
    local function restoreFreeGunHook()
        V.FreeGunEnabled = false
        if _fgSeatOrig ~= nil then
            pcall(function()
                local la = getLA()
                if type(la) == "table" then la.SeatCanEquip = _fgSeatOrig end
            end)
            _fgSeatOrig = nil
        end
        if not _canEquipHooked then return end
        if _fgMode == "field" and _fgTbl and _canEquipCallOrig then
            pcall(function() _fgTbl._canEquip = _canEquipCallOrig end)
        elseif _fgMode == "hookfunction" and _fgRawFn and _canEquipCallOrig then
            pcall(hookfunction, _fgRawFn, _canEquipCallOrig)
        end
        _canEquipHooked = false
        _fgTbl, _fgMode, _fgRawFn = nil, nil, nil
    end

    local function freeGunStep()
        if not V.FreeGunEnabled then return end
        if not _canEquipHooked then installFreeGunHook() end
        -- лёгкий фолбэк для транспорта: разрешаем экипировку в сиденье
        local la = getLA()
        if type(la) == "table" and rawget(la, "SeatCanEquip") ~= true then
            -- запоминаем исходное значение ОДИН раз, чтобы вернуть его в stop
            if _fgSeatOrig == nil then _fgSeatOrig = rawget(la, "SeatCanEquip") or false end
            pcall(function() la.SeatCanEquip = true end)
        end
    end

    ---------------------------------------------------------------------------
    -- 6 + bonus. AMBIENT / FULLBRIGHT / NOFOG
    ---------------------------------------------------------------------------
    local lightSaved, lightSavedOK = {}, false
    local function saveLighting()
        if lightSavedOK then return end
        lightSaved = {
            ClockTime    = Lighting.ClockTime,
            Brightness   = Lighting.Brightness,
            Ambient      = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            FogEnd       = Lighting.FogEnd,
            FogStart     = Lighting.FogStart,
            GlobalShadows = Lighting.GlobalShadows,
            -- расширенная атмосфера
            FogColor        = Lighting.FogColor,
            ColorShift_Top  = Lighting.ColorShift_Top,
            ColorShift_Bottom = Lighting.ColorShift_Bottom,
            ExposureCompensation = Lighting.ExposureCompensation,
            GeographicLatitude = Lighting.GeographicLatitude,
            EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        }
        lightSavedOK = true
    end
    local function restoreLighting()
        if not lightSavedOK then return end
        pcall(function()
            Lighting.ClockTime     = lightSaved.ClockTime
            Lighting.Brightness    = lightSaved.Brightness
            Lighting.Ambient       = lightSaved.Ambient
            Lighting.OutdoorAmbient = lightSaved.OutdoorAmbient
            Lighting.FogEnd        = lightSaved.FogEnd
            Lighting.FogStart      = lightSaved.FogStart
            Lighting.GlobalShadows  = lightSaved.GlobalShadows
            Lighting.FogColor       = lightSaved.FogColor
            Lighting.ColorShift_Top = lightSaved.ColorShift_Top
            Lighting.ColorShift_Bottom = lightSaved.ColorShift_Bottom
            Lighting.ExposureCompensation = lightSaved.ExposureCompensation
            Lighting.GeographicLatitude   = lightSaved.GeographicLatitude
            Lighting.EnvironmentDiffuseScale  = lightSaved.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = lightSaved.EnvironmentSpecularScale
        end)
    end

    -- Константа: раньше два Color3 создавались каждый кадр при Fullbright
    local FULLBRIGHT_COL = Color3.fromRGB(178, 178, 178)

    -- ── Готовые атмосферы ──────────────────────────────────────────────
    -- Крутить 12 ползунков вручную, чтобы получить нормальный вайб, —
    -- неудобно. Пресет ставит всё разом, дальше можно доводить руками
    -- (любая правка ползунка переводит пресет в "Custom").
    local AMBIENT_PRESETS = {
        Midnight = {
            ClockTime = 0, Brightness = 1.2, Exposure = 0.15,
            Ambient = Color3.fromRGB(38, 44, 70),
            Outdoor = Color3.fromRGB(48, 56, 88),
            TintTop = Color3.fromRGB(20, 28, 60), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = true, FogColor = Color3.fromRGB(18, 22, 40), FogStart = 0, FogEnd = 420,
            Shadows = true, Latitude = 20,
        },
        Sunset = {
            ClockTime = 17.6, Brightness = 2.4, Exposure = 0.2,
            Ambient = Color3.fromRGB(120, 78, 62),
            Outdoor = Color3.fromRGB(178, 108, 70),
            TintTop = Color3.fromRGB(255, 150, 70), TintBottom = Color3.fromRGB(40, 20, 30),
            Fog = true, FogColor = Color3.fromRGB(220, 130, 85), FogStart = 40, FogEnd = 1400,
            Shadows = true, Latitude = 60,
        },
        Overcast = {
            ClockTime = 11, Brightness = 1.8, Exposure = -0.1,
            Ambient = Color3.fromRGB(120, 124, 132),
            Outdoor = Color3.fromRGB(150, 155, 165),
            TintTop = Color3.fromRGB(180, 190, 200), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = true, FogColor = Color3.fromRGB(168, 175, 185), FogStart = 20, FogEnd = 700,
            Shadows = false, Latitude = 45,
        },
        Toxic = {
            ClockTime = 14, Brightness = 2.2, Exposure = 0.35,
            Ambient = Color3.fromRGB(70, 105, 55),
            Outdoor = Color3.fromRGB(120, 165, 70),
            TintTop = Color3.fromRGB(150, 255, 90), TintBottom = Color3.fromRGB(20, 40, 10),
            Fog = true, FogColor = Color3.fromRGB(110, 160, 70), FogStart = 0, FogEnd = 520,
            Shadows = true, Latitude = 45,
        },
        Nightvision = {
            ClockTime = 12, Brightness = 4.5, Exposure = 0.6,
            Ambient = Color3.fromRGB(90, 190, 90),
            Outdoor = Color3.fromRGB(110, 220, 110),
            TintTop = Color3.fromRGB(120, 255, 120), TintBottom = Color3.fromRGB(0, 30, 0),
            Fog = false, FogColor = Color3.fromRGB(40, 90, 40), FogStart = 0, FogEnd = 2000,
            Shadows = false, Latitude = 45,
        },
        Clear = {
            ClockTime = 13, Brightness = 2.6, Exposure = 0,
            Ambient = Color3.fromRGB(130, 135, 145),
            Outdoor = Color3.fromRGB(160, 168, 180),
            TintTop = Color3.fromRGB(0, 0, 0), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = false, FogColor = Color3.fromRGB(180, 190, 200), FogStart = 0, FogEnd = 5000,
            Shadows = true, Latitude = 45,
        },
    }
    local AMBIENT_PRESET_ORDER = {
        "Custom", "Clear", "Midnight", "Sunset", "Overcast", "Toxic", "Nightvision",
    }

    local function applyAmbientPreset(name)
        local pr = AMBIENT_PRESETS[name]
        if not pr then return false end
        V.AmbientClockTime      = pr.ClockTime
        V.AmbientBrightness     = pr.Brightness
        V.AmbientExposure       = pr.Exposure
        V.AmbientColor          = pr.Ambient
        V.AmbientOutdoorColor   = pr.Outdoor
        V.AmbientTintTop        = pr.TintTop
        V.AmbientTintBottom     = pr.TintBottom
        V.AmbientFogEnabled     = pr.Fog
        V.AmbientFogColor       = pr.FogColor
        V.AmbientFogStart       = pr.FogStart
        V.AmbientFogEnd         = pr.FogEnd
        V.AmbientShadows        = pr.Shadows
        V.AmbientLatitude       = pr.Latitude
        V.AmbientPreset         = name
        return true
    end
    local function lightingStep()
        if V.AmbientEnabled or V.FullbrightEnabled or V.NoFogEnabled then saveLighting() end
        -- Atmosphere: полноценная кастомизация вайба (время суток, оттенки,
        -- экспозиция, туман). Раньше тут было только время + яркость.
        if V.AmbientEnabled then
            pcall(function()
                Lighting.ClockTime  = V.AmbientClockTime
                Lighting.Brightness = V.AmbientBrightness
                Lighting.Ambient        = V.AmbientColor
                Lighting.OutdoorAmbient = V.AmbientOutdoorColor
                Lighting.ColorShift_Top    = V.AmbientTintTop
                Lighting.ColorShift_Bottom = V.AmbientTintBottom
                Lighting.ExposureCompensation = V.AmbientExposure or 0
                Lighting.GeographicLatitude   = V.AmbientLatitude or 45
                Lighting.EnvironmentDiffuseScale  = V.AmbientDiffuse  or 1
                Lighting.EnvironmentSpecularScale = V.AmbientSpecular or 1
                Lighting.GlobalShadows = V.AmbientShadows ~= false
                if V.AmbientFogEnabled then
                    Lighting.FogColor = V.AmbientFogColor
                    Lighting.FogStart = V.AmbientFogStart or 0
                    Lighting.FogEnd   = V.AmbientFogEnd or 800
                end
            end)
        end
        -- Fullbright — отдельная простая фича: просто «видно всё».
        if V.FullbrightEnabled then
            pcall(function()
                Lighting.Brightness     = math.max(Lighting.Brightness, 2)
                Lighting.Ambient        = FULLBRIGHT_COL
                Lighting.OutdoorAmbient = FULLBRIGHT_COL
                Lighting.GlobalShadows  = false
            end)
        end
        if V.NoFogEnabled then
            pcall(function()
                Lighting.FogEnd   = 1e9
                Lighting.FogStart = 1e9
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- 7. NO F WAIT
    ---------------------------------------------------------------------------
    -- ВАЖНО: игра НЕ использует HoldDuration прокси-промпта для тайминга.
    -- InteractionInterface при нажатии читает АТРИБУТ "Timer" промпта и держит
    -- задачу PromptTask ровно Timer секунд (см. дамп InteractionInterface:Enable
    -- → prompt:GetAttribute("Timer")). Поэтому чтобы убрать ожидание, обнуляем
    -- атрибут "Timer" (0 → задача финиширует в тот же кадр). HoldDuration тоже
    -- зануляем — на случай промптов со штатным нативным триггеро��.
    local promptConn = nil
    local promptAttrConn = {}
    local function zeroPrompt(p)
        if not (p and p:IsA("ProximityPrompt")) then return end
        pcall(function()
            local t = p:GetAttribute("Timer")
            if type(t) == "number" and t > 0 and p:GetAttribute("BRM5_timer") == nil then
                p:SetAttribute("BRM5_timer", t)
            end
            if p:GetAttribute("BRM5_hold") == nil then
                p:SetAttribute("BRM5_hold", p.HoldDuration)
            end
            if p:GetAttribute("Timer") ~= nil then p:SetAttribute("Timer", 0) end
            p.HoldDuration = 0
        end)
        -- сервер/игра могут переустановить Timer → держим его в 0, пока фича вкл
        if not promptAttrConn[p] then
            promptAttrConn[p] = p:GetAttributeChangedSignal("Timer"):Connect(function()
                if V.NoFWaitEnabled and p:GetAttribute("Timer") and p:GetAttribute("Timer") ~= 0 then
                    pcall(function() p:SetAttribute("Timer", 0) end)
                end
            end)
        end
    end
    local function enableNoFWait()
        if promptConn then return end
        for _, d in ipairs(Workspace:GetDescendants()) do zeroPrompt(d) end
        promptConn = PPS.PromptShown:Connect(function(p)
            if V.NoFWaitEnabled then zeroPrompt(p) end
        end)
    end
    local function disableNoFWait()
        if promptConn then promptConn:Disconnect(); promptConn = nil end
        for p, c in pairs(promptAttrConn) do
            pcall(function() c:Disconnect() end)
            promptAttrConn[p] = nil
        end
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local st = d:GetAttribute("BRM5_timer")
                if st ~= nil then pcall(function() d:SetAttribute("Timer", st) end) end
                local s = d:GetAttribute("BRM5_hold")
                if s ~= nil then pcall(function() d.HoldDuration = s end) end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 8. LOCKPICK BYPASS
    --
    -- ФИКС ПРОСАДКИ FPS: раньше lockpickStep() дёргал findLockPick() (это
    -- filtergc — полный проход по GC) КАЖДЫЙ кадр, даже когда никакого замка
    -- рядом нет. Полный GC-скан 60 раз/сек = дикая просадка.
    --
    -- Теперь:
    --   1) СНАЧАЛА дешёвая проверка стейта актора — CurrentState.LockPick
    --      (по дампу LockPickController:new вызывает localActor:State("LockPick",
    --      true), а :State пишет в CurrentState[name]). Нет мини-игры → мгновенно
    --      выходим, БЕЗ единого GC-скана.
    --   2) Только когда мини-игра реально активна — ищем её экземпляр (и то не
    --      чаще LockpickScanInterval), кэшируем, шлём успех ОДИН раз.
    ---------------------------------------------------------------------------
    local lpLastScan = -999
    local function lockpickActive()
        local la = getLA()
        if type(la) ~= "table" then return false end
        local cs = rawget(la, "CurrentState")
        return type(cs) == "table" and cs.LockPick and true or false
    end
    local function lockpickStep()
        if not V.LockpickBypassEnabled then return end
        -- дешёвый гейт: пока замок не открыт игрой — никаких GC-сканов
        if not lockpickActive() then return end
        local t = now()
        if t - lpLastScan < (V.LockpickScanInterval or 0.4) then return end
        lpLastScan = t
        local lp = findLockPick()          -- filtergc только во время активной мини-игры
        if not lp then return end
        local net = findNet()
        if net then
            pcall(function() lp._cancelled = true end)
            pcall(function() net:FireServer("ActivateInteract", "Picked") end)
        end
    end

    ---------------------------------------------------------------------------
    -- ГЛАВНЫЙ ЦИКЛ
    ---------------------------------------------------------------------------
    local hbConn  = nil
    -- ВАЖНО: `running` объявлен в самом верху модуля (рядом с vmHooked), а НЕ
    -- здесь. Хук viewmodel читает его на ~548 — если объявить локал тут, внутри
    -- хука это будет глобал (=nil), и Viewmodel/GunModel молча перестанут
    -- работать. Ровно та же ловушка, что была с gunHighlight.

    local function heartbeat(dt)
        if not running then return end
        pcall(function()
            if V.ViewmodelEnabled or V.GunModelEnabled then ensureViewmodelHook() end
        thirdPersonStep()
        vehicleStep(dt)
        freeGunStep()
            lightingStep()
            lockpickStep()
        end)
    end

    ---------------------------------------------------------------------------
    -- ХОТКЕИ
    ---------------------------------------------------------------------------
    local inputConn = nil
    local function toggle(name, label)
        V[name] = not V[name]
        log(label, V[name] and "ВКЛ" or "выкл")
        return V[name]
    end

    local function onInput(input, gpe)
        if gpe then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kc = input.KeyCode
        if kc == V.ViewmodelKey then
            if not toggle("ViewmodelEnabled", "Viewmodel") then restoreViewmodelStyle() end
        elseif kc == V.GunModelKey then
            if not toggle("GunModelEnabled", "GunModel") then
                if gunHighlight then pcall(function() gunHighlight:Destroy() end); gunHighlight = nil end
            end
        elseif kc == V.ThirdPersonKey then
            if not toggle("ThirdPersonEnabled", "ThirdPersonSkin") then
                clearSelfHighlight(); restoreSelfBody()
            end
        elseif kc == V.VehicleFlyKey   then toggle("VehicleFlyEnabled",    "VehicleFly")
        elseif kc == V.VehicleSpeedKey then toggle("VehicleSpeedEnabled",   "VehicleSpeed")
        elseif kc == V.FreeGunKey then
            if toggle("FreeGunEnabled", "FreeGun") then installFreeGunHook() end
        elseif kc == V.AmbientKey then
            if not toggle("AmbientEnabled", "Ambient") then restoreLighting(); lightSavedOK = false end
        elseif kc == V.NoFWaitKey then
            if toggle("NoFWaitEnabled", "NoFWait") then enableNoFWait() else disableNoFWait() end
        elseif kc == V.LockpickBypassKey then
            toggle("LockpickBypassEnabled", "LockpickBypass")
        elseif kc == V.FullbrightKey then
            if not toggle("FullbrightEnabled", "Fullbright") then restoreLighting(); lightSavedOK = false end
        elseif kc == V.NoFogKey then
            if not toggle("NoFogEnabled", "NoFog") then restoreLighting(); lightSavedOK = false end
        end
    end

    ---------------------------------------------------------------------------
    -- START / STOP
    ---------------------------------------------------------------------------
    local M = {}

    function M.start()
        if running then return end
        running = true
        hbConn = RunService.Heartbeat:Connect(heartbeat)
        pcall(function()
            RunService:BindToRenderStep(FOV_BIND,
                Enum.RenderPriority.Camera.Value + 1, fovStep)
            fovBound = true
        end)
        inputConn = UIS.InputBegan:Connect(onInput)
        log("Visuals/World v2 запущен | Numpad1..0 = тумблеры | CONFIG.Visuals для настройки")
    end

    function M.stop()
        running = false
        if hbConn    then hbConn:Disconnect();    hbConn    = nil end
        if inputConn then inputConn:Disconnect(); inputConn = nil end
        if fovBound  then
            pcall(function() RunService:UnbindFromRenderStep(FOV_BIND) end)
            fovBound = false
        end
        -- Снимаем хук ДО restore — иначе живой хук вернёт стиль обратно
        -- на следующем же кадре (ровно так и было раньше).
        unhookViewmodel()
        restoreViewmodelStyle()
        restoreGunStyle()        -- FIX: не вызывался → оружие оставалось перекрашенным
        restoreVehicleSpeed()    -- FIX: не вызывался → тачка навсегда с изменённой массой
        if gunHighlight then pcall(function() gunHighlight:Destroy() end); gunHighlight = nil end
        clearSelfHighlight()
        restoreSelfBody()
        restoreFreeGunHook()     -- FIX: снимаем _canEquip и возвращаем SeatCanEquip
        disableNoFWait()
        restoreLighting(); lightSavedOK = false
        pcall(function()
            local cam = Workspace.CurrentCamera
            -- FIX: было жёстко 70 — теперь возвращаем реально захваченный FOV
            if cam then cam.FieldOfView = _origFov or 70 end
        end)
        log("Visuals/World остановлен")
    end

    -- ─────────────────────────────────────────────────────────────────────
    -- UI-интеграция (MacLib). Visuals-модуль раскидывает ко��тролы по табам:
    --   Visuals  → Viewmodel / GunModel / Gradient / ThirdPerson
    --   Movement → Vehicle (fly/speed) — это движение
    --   GunMods  → FreeGun — это изменение оружия
    --   Misc     → Fullbright / Ambient / NoFog / NoFWait
    -- Все колбэки пишут в V (= CONFIG.Visuals), heartbeat применяет каждый кадр.
    -- ─────────────────────────────────────────────────────────────────────
    -- Материалы для дропдаунов (строка ⇄ Enum.Material).
    local MATERIALS = { "ForceField", "Neon", "Glass", "SmoothPlastic", "Plastic", "Metal", "Marble" }
    local function matName(m) return (typeof(m) == "EnumItem") and m.Name or tostring(m or "ForceField") end
    local function matFromName(n) return Enum.Material[n] or Enum.Material.ForceField end

    function M.buildUI(ui)
        local tabV    = ui.tabs and ui.tabs.Visuals
        local tabMov  = ui.tabs and ui.tabs.Movement
        local tabGM   = ui.tabs and ui.tabs.GunMods
        local tabMisc = ui.tabs and ui.tabs.Misc
        local tabDbg  = ui.tabs and ui.tabs.Debug
        local K = Bridge.makeUiKit(ui)

        if tabV then
            -- ═══ Viewmodel ═════════════════════════════════════════════
            local S = tabV:Section({ Side = "Left" })
            -- Настройки видны ВСЕГДА, даже когда фича выключена: иначе панель
            -- выглядит пустой и непонятно, что она вообще умеет.
            K.feature(S, {
                Title = "Viewmodel", Flag = "VM",
                get = function() return V.ViewmodelEnabled end,
                set = function(v) V.ViewmodelEnabled = v end,
                Desc = "restyles ur first person arms",
            })
            K.toggle(S, { Name = "Recolor", Flag = "VMColorOn", Title = "VM Recolor",
                get = function() return V.ViewmodelColorEnabled end,
                set = function(v) V.ViewmodelColorEnabled = v end,
                after = invalidateVmStyle })
            K.color(S, { Name = "Color", Flag = "VMColor",
                Default = V.ViewmodelColor,
                Callback = function(c) V.ViewmodelColor = c; invalidateVmStyle() end })
            K.toggle(S, { Name = "Change Material", Flag = "VMMatOn",
                Title = "VM Material",
                get = function() return V.ViewmodelMaterialEnabled end,
                set = function(v) V.ViewmodelMaterialEnabled = v end,
                after = invalidateVmStyle })
            K.dropdown(S, { Name = "Material", Flag = "VMMat",
                Options = MATERIALS, Default = matName(V.ViewmodelMaterial),
                -- FIX: смена материала не применялась, пока не дёрнешь
                -- прозрачность — только она сбрасывала кэш стиля.
                Callback = function(n) V.ViewmodelMaterial = matFromName(n); invalidateVmStyle() end })
            K.slider(S, { Name = "Transparency", Flag = "VMTransp",
                Default = math.floor((V.ViewmodelTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)
                    V.ViewmodelTransparency = v / 100
                    invalidateVmStyle()
                end })
            K.toggle(S, { Name = "Gradient", Flag = "VMGrad", Title = "VM Gradient",
                get = function() return V.ViewmodelGradientEnabled end,
                set = function(v) V.ViewmodelGradientEnabled = v end,
                after = invalidateVmStyle,
                Desc = "colors set in Gradient on the right" })

            K.group(S, "Placement")
            K.slider(S, { Name = "Hand Zoom", Flag = "VMDepth",
                Default = math.floor(V.ViewmodelDepth or 0) + 100, Min = 0, Max = 200,
                Callback = function(v) V.ViewmodelDepth = v - 100 end,
                Desc = "100 = stock. pulls the arms closer or pushes em away\nthis is NOT camera fov, that one lives in Misc" })

            -- ═══ Gun Model ═════════════════════════════════════════════
            local G = tabV:Section({ Side = "Left" })
            K.feature(G, {
                Title = "Gun Model", Flag = "GM",
                get = function() return V.GunModelEnabled end,
                set = function(v) V.GunModelEnabled = v end,
                Desc = "same styling but for the gun in ur hands",
            })
            K.toggle(G, { Name = "Recolor", Flag = "GMColorOn", Title = "Gun Recolor",
                get = function() return V.GunModelColorEnabled end,
                set = function(v) V.GunModelColorEnabled = v end,
                after = invalidateGunStyle })
            K.color(G, { Name = "Color", Flag = "GMColor",
                Default = V.GunModelColor,
                Callback = function(c) V.GunModelColor = c; invalidateGunStyle() end })
            K.toggle(G, { Name = "Change Material", Flag = "GMMatOn",
                Title = "Gun Material",
                get = function() return V.GunModelMaterialEnabled end,
                set = function(v) V.GunModelMaterialEnabled = v end,
                after = invalidateGunStyle })
            K.dropdown(G, { Name = "Material", Flag = "GMMat",
                Options = MATERIALS, Default = matName(V.GunModelMaterial),
                Callback = function(n) V.GunModelMaterial = matFromName(n); invalidateGunStyle() end })
            K.slider(G, { Name = "Transparency", Flag = "GMTransp",
                Default = math.floor((V.GunModelTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)
                    V.GunModelTransparency = v / 100
                    invalidateGunStyle()
                end })
            K.toggle(G, { Name = "Gradient", Flag = "GMGrad", Title = "Gun Gradient",
                get = function() return V.GunModelGradientEnabled end,
                set = function(v) V.GunModelGradientEnabled = v end,
                after = invalidateGunStyle,
                Desc = "wave runs part to part, see Wave Spread" })

            K.group(G, "Highlight")
            K.toggle(G, { Name = "Enabled", Flag = "GMHighlight",
                Title = "Gun Highlight",
                get = function() return V.GunModelHighlightEnabled ~= false end,
                set = function(v)
                    V.GunModelHighlightEnabled = v
                    if not v and gunHighlight then
                        pcall(function() gunHighlight:Destroy() end); gunHighlight = nil
                    end
                end,
                Desc = "glowing outline around the gun" })
            K.color(G, { Name = "Fill", Flag = "GMFill",
                Default = V.GunModelFill,
                Callback = function(c) V.GunModelFill = c end })
            K.color(G, { Name = "Outline", Flag = "GMOutline",
                Default = V.GunModelOutline,
                Callback = function(c) V.GunModelOutline = c end })
            K.slider(G, { Name = "Fill Transparency", Flag = "GMFillT",
                Default = math.floor((V.GunModelFillTransparency or 0.5) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v) V.GunModelFillTransparency = v / 100 end })
            K.toggle(G, { Name = "Follow Gradient", Flag = "GMHlGrad",
                Title = "Highlight Gradient",
                get = function() return V.GunModelHighlightGradient ~= false end,
                set = function(v) V.GunModelHighlightGradient = v end,
                Desc = "outline rides the same wave as the gun\noff = keeps the fixed colors above" })

            -- ═══ Third Person ══════════════════════════════════════════
            local S2 = tabV:Section({ Side = "Right" })
            -- Честное имя: фича НЕ включает камеру от третьего лица (та живёт
            -- в модуле Movement). Она красит твою собственную модель, которую
            -- видно, когда камера уже отъехала.
            K.feature(S2, {
                Title = "Self Skin", Flag = "TP",
                get = function() return V.ThirdPersonEnabled end,
                set = function(v) V.ThirdPersonEnabled = v end,
                Desc = "recolors ur own body\nu see it in third person or spectate",
            })
            K.color(S2, { Name = "Body Color", Flag = "TPColor",
                Default = V.ThirdPersonBodyColor,
                Callback = function(c) V.ThirdPersonBodyColor = c end })
            K.slider(S2, { Name = "Transparency", Flag = "TPTransp",
                Default = math.floor((V.ThirdPersonBodyTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v) V.ThirdPersonBodyTransparency = v / 100 end })
            K.dropdown(S2, { Name = "Material", Flag = "TPMat",
                Options = MATERIALS, Default = matName(V.ThirdPersonMaterial),
                Callback = function(n) V.ThirdPersonMaterial = matFromName(n) end })
            K.toggle(S2, { Name = "Gradient", Flag = "TPGrad", Title = "TP Gradient",
                get = function() return V.ThirdPersonGradientEnabled end,
                set = function(v) V.ThirdPersonGradientEnabled = v end })

            -- ═══ Общие цвета градиента ═════════════════════════════════
            local GC = tabV:Section({ Side = "Right" })
            GC:Header({ Name = "Gradient" })
            GC:SubLabel({ Text = "blends A into B n back, its not a rainbow" })
            K.color(GC, { Name = "Color A", Flag = "GradA", Default = V.GradientColorA,
                Callback = function(c) V.GradientColorA = c end })
            K.color(GC, { Name = "Color B", Flag = "GradB", Default = V.GradientColorB,
                Callback = function(c) V.GradientColorB = c end })
            K.slider(GC, { Name = "Speed", Flag = "GradSpeed",
                Default = math.floor((V.GradientSpeed or 0.5) * 100),
                Min = 5, Max = 200, Suffix = "%",
                Callback = function(v) V.GradientSpeed = v / 100 end })
            K.slider(GC, { Name = "Wave Spread", Flag = "GradSpread",
                Default = math.floor((V.GunModelGradientSpread or 1.6) * 10),
                Min = 0, Max = 50,
                Callback = function(v)
                    V.GunModelGradientSpread = v / 10
                    -- сбрасываем фазы частей, иначе волна не пересчитается
                    for _, rec in pairs(gunStyledParts) do rec.gp = nil end
                end,
                Desc = "0 = whole gun changes color at once" })
        end

        -- ═══ TAB: Movement ═════════════════════════════════════════════
        if tabMov then
            -- Транспорт — правая колонка. Модуль Movement теперь раскладывает
            -- свои фичи по обеим сторонам (перемещение слева, камера/десинк
            -- справа), так что vehicle встаёт третьим блоком справа и колонки
            -- остаются сбалансированными.
            local S = tabMov:Section({ Side = "Right" })
            K.feature(S, {
                Title = "Vehicle Fly", Flag = "VehFly",
                get = function() return V.VehicleFlyEnabled end,
                set = function(v) V.VehicleFlyEnabled = v end,
                Desc = "flies whatever ur driving",
            })
            K.slider(S, { Name = "Fly Speed", Flag = "VehFlySpeed",
                Default = V.VehicleFlySpeed, Min = 20, Max = 400, Suffix = " st/s",
                Callback = function(v) V.VehicleFlySpeed = v end })

            K.group(S, "Vehicle Speed")
            K.toggle(S, { Name = "Enabled", Flag = "VehSpeed", Title = "Vehicle Speed",
                get = function() return V.VehicleSpeedEnabled end,
                set = function(v) V.VehicleSpeedEnabled = v end })
            if ui.keybind then
                ui.keybind(S, { Name = "Keybind", Flag = (ui.flag or tostring)("VehSpeed_KB"),
                    Toggle = function()
                        V.VehicleSpeedEnabled = not V.VehicleSpeedEnabled
                        K.syncToggle((ui.flag or tostring)("VehSpeed"), V.VehicleSpeedEnabled)
                        K.notify("Vehicle Speed", V.VehicleSpeedEnabled and "Enabled" or "Disabled")
                    end })
            end
            K.slider(S, { Name = "Multiplier", Flag = "VehSpeedMult",
                Default = math.floor((V.VehicleSpeedMult or 1) * 10), Min = 10, Max = 60,
                Callback = function(v) V.VehicleSpeedMult = v / 10 end,
                Desc = "10 = stock, 60 = 6x" })
        end

        -- ═══ TAB: Gun Mods ═════════════════════════════════════════════
        if tabGM then
            local S = tabGM:Section({ Side = "Left" })
            K.feature(S, {
                Title = "Free Gun", Flag = "FreeGun",
                get = function() return V.FreeGunEnabled end,
                set = function(v) V.FreeGunEnabled = v end,
                Desc = "lets u draw a weapon where the game blocks it\nlike inside a vehicle",
            })
        end

        -- ═══ TAB: Misc ═════════════════════════════════════════════════
        if tabMisc then
            local SL = tabMisc:Section({ Side = "Left" })
            K.feature(SL, {
                Title = "Fullbright", Flag = "Fullbright",
                get = function() return V.FullbrightEnabled end,
                set = function(v) V.FullbrightEnabled = v end,
                Desc = "flat max light, no shadows anywhere\nfor mood lighting use Atmosphere instead",
            })

            K.group(SL, "No Fog")
            K.toggle(SL, { Name = "Enabled", Flag = "NoFog", Title = "No Fog",
                get = function() return V.NoFogEnabled end,
                set = function(v) V.NoFogEnabled = v end,
                Desc = "strips fog entirely — see the whole map" })

            K.group(SL, "Camera FOV")
            K.toggle(SL, { Name = "Enabled", Flag = "WorldFOVOn", Title = "Camera FOV",
                get = function() return V.WorldFOVEnabled end,
                set = function(v) V.WorldFOVEnabled = v end,
                Desc = "real field of view — wider = see more but aim feels faster" })
            K.slider(SL, { Name = "FOV", Flag = "WorldFOV",
                Default = V.WorldFOV or 70, Min = 40, Max = 120, Suffix = "°",
                Callback = function(v) V.WorldFOV = v end,
                Desc = "70 = game default" })

            -- ═══ Atmosphere: свой вайб ═════════════════════════════════
            local SA = tabMisc:Section({ Side = "Left" })
            K.feature(SA, {
                Title = "Atmosphere", Flag = "Ambient",
                get = function() return V.AmbientEnabled end,
                set = function(v) V.AmbientEnabled = v end,
                Desc = "ur own time of day n mood\noverrides whatever the map sets",
            })
            -- Пресет ставит всю атмосферу разом. Ползунки ниже остаются
            -- доступны — любая правка переводит пресет в Custom.
            local ambRefresh
            K.dropdown(SA, { Name = "Preset", Flag = "AmbPreset",
                Options = AMBIENT_PRESET_ORDER,
                Default = V.AmbientPreset or "Custom",
                Callback = function(v)
                    if v ~= "Custom" and applyAmbientPreset(v) then
                        V.AmbientEnabled = true
                        if ambRefresh then ambRefresh() end
                    else
                        V.AmbientPreset = "Custom"
                    end
                end,
                Desc = "ready-made vibes\ntweak anything below n it flips to Custom" })

            -- Любое ручное изменение сбрасывает пресет в Custom
            local function manual() V.AmbientPreset = "Custom" end

            local elTime = K.slider(SA, { Name = "Time", Flag = "ClockTime",
                Default = V.AmbientClockTime, Min = 0, Max = 24, Suffix = "h",
                Callback = function(v) V.AmbientClockTime = v; manual() end,
                Desc = "0 = midnight, 12 = noon, 18 = sunset" })
            local elBright = K.slider(SA, { Name = "Brightness", Flag = "AmbBright",
                Default = math.floor((V.AmbientBrightness or 2) * 10), Min = 0, Max = 100,
                Callback = function(v) V.AmbientBrightness = v / 10; manual() end })
            local elExp = K.slider(SA, { Name = "Exposure", Flag = "AmbExposure",
                Default = math.floor((V.AmbientExposure or 0) * 100) + 200, Min = 0, Max = 400,
                Callback = function(v) V.AmbientExposure = (v - 200) / 100; manual() end,
                Desc = "200 = neutral, lower = darker, higher = blown out" })
            local elLat = K.slider(SA, { Name = "Sun Angle", Flag = "AmbLat",
                Default = math.floor(V.AmbientLatitude or 45) + 90, Min = 0, Max = 180,
                Callback = function(v) V.AmbientLatitude = v - 90; manual() end,
                Desc = "moves where the sun sits in the sky" })

            K.group(SA, "Colors")
            local elAmb = K.color(SA, { Name = "Shadow Tint", Flag = "AmbColor",
                Default = V.AmbientColor,
                Callback = function(c) V.AmbientColor = c; manual() end,
                Desc = "color of everything in shade" })
            local elOut = K.color(SA, { Name = "Outdoor Tint", Flag = "AmbOutColor",
                Default = V.AmbientOutdoorColor,
                Callback = function(c) V.AmbientOutdoorColor = c; manual() end })
            local elTintT = K.color(SA, { Name = "Highlight Tint", Flag = "AmbTintTop",
                Default = V.AmbientTintTop,
                Callback = function(c) V.AmbientTintTop = c; manual() end,
                Desc = "tints lit surfaces — keep it subtle" })
            local elTintB = K.color(SA, { Name = "Shade Tint", Flag = "AmbTintBottom",
                Default = V.AmbientTintBottom,
                Callback = function(c) V.AmbientTintBottom = c; manual() end })
            local elShadows = K.toggle(SA, { Name = "Shadows", Flag = "AmbShadows", Title = "Shadows",
                get = function() return V.AmbientShadows ~= false end,
                set = function(v) V.AmbientShadows = v end })

            K.group(SA, "Fog")
            local elFogOn = K.toggle(SA, { Name = "Custom Fog", Flag = "AmbFogOn", Title = "Custom Fog",
                get = function() return V.AmbientFogEnabled end,
                set = function(v) V.AmbientFogEnabled = v end,
                Desc = "for haze n distance mood\nuse No Fog instead if u just want it gone" })
            local elFogCol = K.color(SA, { Name = "Fog Color", Flag = "AmbFogColor",
                Default = V.AmbientFogColor,
                Callback = function(c) V.AmbientFogColor = c; manual() end })
            local elFogStart = K.slider(SA, { Name = "Fog Start", Flag = "AmbFogStart",
                Default = V.AmbientFogStart or 0, Min = 0, Max = 2000, Suffix = " st",
                Callback = function(v) V.AmbientFogStart = v; manual() end })
            local elFogEnd = K.slider(SA, { Name = "Fog End", Flag = "AmbFogEnd",
                Default = V.AmbientFogEnd or 800, Min = 50, Max = 5000, Suffix = " st",
                Callback = function(v) V.AmbientFogEnd = v; manual() end })

            -- Пресет меняет V.*, но ползунки/пикеры об этом не знают —
            -- синхронизируем их отображение, иначе они показывают старые числа.
            ambRefresh = function()
                local function setV(el, val)
                    if el and val then pcall(function() el:UpdateValue(val, true) end) end
                end
                local function setC(el, col)
                    if el and col then pcall(function() el:SetColor(col) end) end
                end
                setV(elTime,    V.AmbientClockTime)
                setV(elBright,  math.floor((V.AmbientBrightness or 2) * 10))
                setV(elExp,     math.floor((V.AmbientExposure or 0) * 100) + 200)
                setV(elLat,     math.floor(V.AmbientLatitude or 45) + 90)
                setV(elFogStart, V.AmbientFogStart or 0)
                setV(elFogEnd,  V.AmbientFogEnd or 800)
                setC(elAmb,     V.AmbientColor)
                setC(elOut,     V.AmbientOutdoorColor)
                setC(elTintT,   V.AmbientTintTop)
                setC(elTintB,   V.AmbientTintBottom)
                setC(elFogCol,  V.AmbientFogColor)
                if elShadows then pcall(function() elShadows:UpdateState(V.AmbientShadows ~= false) end) end
                if elFogOn   then pcall(function() elFogOn:UpdateState(V.AmbientFogEnabled == true) end) end
            end

            local SIN = tabMisc:Section({ Side = "Right" })
            SIN:Header({ Name = "Interactions" })
            K.toggle(SIN, { Name = "No Prompt Hold", Flag = "NoFWait", Title = "No Prompt Hold",
                get = function() return V.NoFWaitEnabled end,
                set = function(v) V.NoFWaitEnabled = v end,
                Desc = "prompts fire instantly instead of holding F" })
            K.toggle(SIN, { Name = "Lockpick Bypass", Flag = "Lockpick", Title = "Lockpick Bypass",
                get = function() return V.LockpickBypassEnabled end,
                set = function(v) V.LockpickBypassEnabled = v end,
                Desc = "solves the lockpick minigame for u" })
        end

        -- ═══ DEBUG ═════════════════════════════════════════════════════
        if tabDbg then
            local D = tabDbg:Section({ Side = "Left" })
            D:Header({ Name = "Visuals" })
            K.slider(D, { Name = "Lockpick Scan", Flag = "DbgLockpick",
                Default = math.floor((V.LockpickScanInterval or 0.4) * 1000),
                Min = 100, Max = 2000, Suffix = " ms",
                Callback = function(v) V.LockpickScanInterval = v / 1000 end })
        end

        K.ready()
    end

    return M
end
