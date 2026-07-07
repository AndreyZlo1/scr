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
        ViewmodelFOV              = 0,                           -- FOV камеры (0 = не трогать)

        --== 2 · GUNMODEL — подсветка МОДЕЛИ ОРУЖИЯ. Хоткей: Numpad 2 ==
        GunModelEnabled           = false,
        GunModelKey               = Enum.KeyCode.KeypadTwo,
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
        --   НЕ радуга: цвет пингпонг-лерпит ColorA ⇆ ColorB (по умолчанию
        --   светло-фиолетовый ⇆ голубой). Работает поверх перекраски рук/оружия/
        --   тела. Для оружия «умный»: фаза бежит волной по частям (GradientSpread),
        --   поэтому части переливаются постепенно, а не все разом.
        ViewmodelGradientEnabled   = false,   -- переливать руки (Viewmodel)
        GunModelGradientEnabled    = false,   -- переливать оружие (GunModel)
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
    local vmHooked    = false
    local vmOrigRef   = nil   -- ← значение, ВОЗВРАЩЁННОЕ hookfunction (НЕ исходный rawget)

    -- Список стилизованных частей: { [part] = { M, C, T } } для restore
    local vmStyledParts = {}
    local vmStyledVM    = nil

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
    local function tickGradientStore(store, spread, baseHue)
        -- 1) Собираем пары (part, rec) где нужно посчитать gp
        local needPhase = {}
        local total = 0
        for part, rec in pairs(store) do
            if part and part.Parent then
                total = total + 1
                if rec.gp == nil then needPhase[part] = rec end
            end
        end
        if total == 0 then return end
        -- 2) Для частей без фазы — назначаем по сортировке idx/total
        if next(needPhase) then
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
                local col = gradientColorAt(baseHue + (rec.gp or 0))
                pcall(function() part.Color = col end)
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

    local function applyViewmodelStyle(vm)
        if vmStyledVM ~= nil and vmStyledVM ~= vm then restoreViewmodelStyle() end
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
    local gunStyledParts = {}     -- [part] = { M, C, T, tex, sa }
    local gunStyledModel = nil
    local function restoreGunStyle()
        restoreStore(gunStyledParts)
        gunStyledModel = nil
    end
    local function applyGunStyle(vm)
        local weapon = rawget(vm, "CurrentModel")
        if not (typeof(weapon) == "Instance" and weapon.Parent) then
            if gunStyledModel then restoreGunStyle() end
            return
        end
        if gunStyledModel ~= nil and gunStyledModel ~= weapon then
            restoreGunStyle()   -- сменили ствол → вернуть старый
        end
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
            local r = table.pack(vmOrigRef(self, dt, ...))   -- ← vmOrigRef, не origFn!
            pcall(function()
                if V.ViewmodelEnabled then
                    local root = rawget(self, "Root")
                    if root and root.Parent then
                        local o = V.ViewmodelOffset or Vector3.new()
                        local tilt = V.ViewmodelTilt or 0
                        if o.Magnitude > 0.001 or math.abs(tilt) > 0.001 then
                            root.CFrame = root.CFrame
                                * CFrame.new(o.X, o.Y, -o.Z)
                                * CFrame.Angles(0, 0, math.rad(tilt))
                        end
                    end
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
                    if container and weapon and weapon.Parent then
                        if not (gunHighlight and gunHighlight.Parent) then
                            gunHighlight = Instance.new("Highlight")
                            gunHighlight.Name = "BRM5_GunHL"
                            gunHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        end
                        gunHighlight.FillColor          = V.GunModelFill
                        gunHighlight.OutlineColor       = V.GunModelOutline
                        gunHighlight.FillTransparency   = V.GunModelFillTransparency
                        gunHighlight.OutlineTransparency = V.GunModelOutlineTransparency
                        if gunHighlight.Adornee ~= weapon then gunHighlight.Adornee = weapon end
                        gunHighlight.Parent = container
                    elseif gunHighlight then
                        gunHighlight.Adornee = nil  -- оружие не экипировано сейчас
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
            vmOrigRef = ret
            vmHooked  = true
            log("Viewmodel hook OK (hookfunction)")
            return true
        end

        -- Fallback: заменяем метод в таблице
        -- В ����том случае origFn и есть оригинал — кладём его в vmOrigRef
        vmOrigRef = origFn
        local ok2 = pcall(function() cls.Update = wrapped end)
        if ok2 then
            vmHooked = true
            log("Viewmodel hook OK (table replace fallback)")
            return true
        end
        log("Viewmodel hook FAILED")
        return false
    end

    local gunHighlight -- объявлен здесь (до newUpdate замыкания использован выше)

    ---------------------------------------------------------------------------
    -- FOV override (после камеры каждый кадр)
    ---------------------------------------------------------------------------
    local FOV_BIND = "BRM5_FOV"
    local fovBound = false
    local fovApplied = false  -- флаг: мы изменили FOV → надо восстановить при выключении
    local function fovStep()
        local fov = V.ViewmodelFOV or 0
        if V.ViewmodelEnabled and fov > 0 then
            local cam = Workspace.CurrentCamera
            if cam then
                pcall(function() cam.FieldOfView = fov end)
                fovApplied = true
            end
        else
            -- FOV выключен или равен 0 → восстановить стандартный FOV игры
            if fovApplied then
                local cam = Workspace.CurrentCamera
                if cam then pcall(function() cam.FieldOfView = 70 end) end
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
        local la = getLA()
        if type(la) ~= "table" then return nil end
        if rawget(la, "Alive") == false then return nil end
        local ok, char = pcall(function() return la.Character end)
        if ok and typeof(char) == "Instance" and char:IsA("Model") then
            return char
        end
        -- fallback на штатный путь, если он вдруг есть
        return LP.Character
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
                pcall(function()
                    part.Material    = s.M
                    part.Color       = s.C
                    part.Transparency = s.T
                end)
            end
        end
        tpOrig = {}
        tpStyledChar = nil
    end

    local function styleSelfBody(char)
        restoreSelfBody()
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("MeshPart")) then
                tpOrig[d] = { M = d.Material, C = d.Color, T = d.Transparency }
                pcall(function()
                    if V.ThirdPersonMaterial then d.Material = V.ThirdPersonMaterial end
                    d.Color = V.ThirdPersonBodyColor
                    if d.Transparency < 1 then d.Transparency = V.ThirdPersonBodyTransparency end
                end)
            end
        end
        tpStyledChar = char
    end

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
        if tpStyledChar ~= char then styleSelfBody(char) end
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
                    log("FreeGun: _canEquip перехвачен (field)")
                    return true
                end
                -- 2) таблица заморожена → hookfunction (origRef = callable оригинал)
                if type(hookfunction) == "function" then
                    local hookOk, origRef = pcall(hookfunction, fn, wrapper)
                    if hookOk then
                        _canEquipCallOrig = (type(origRef) == "function") and origRef or fn
                        _canEquipHooked = true
                        log("FreeGun: _canEquip перехвачен (hookfunction)")
                        return true
                    end
                end
            end
        end
        return false
    end

    local function freeGunStep()
        if not V.FreeGunEnabled then return end
        if not _canEquipHooked then installFreeGunHook() end
        -- лёгкий фолбэк для транспорта: разрешаем экипировку в сиденье
        local la = getLA()
        if type(la) == "table" and rawget(la, "SeatCanEquip") ~= true then
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
        end)
    end

    local function lightingStep()
        if V.AmbientEnabled or V.FullbrightEnabled or V.NoFogEnabled then saveLighting() end
        if V.AmbientEnabled then
            pcall(function()
                Lighting.ClockTime  = V.AmbientClockTime
                Lighting.Brightness = V.AmbientBrightness
            end)
        end
        if V.FullbrightEnabled then
            pcall(function()
                Lighting.Brightness     = math.max(Lighting.Brightness, 2)
                Lighting.Ambient        = Color3.fromRGB(178, 178, 178)
                Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
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
    local running = false

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
        restoreViewmodelStyle()
        if gunHighlight then pcall(function() gunHighlight:Destroy() end); gunHighlight = nil end
        clearSelfHighlight()
        restoreSelfBody()
        V.FreeGunEnabled = false  -- хук _canEquip остаётся, но инертен (гейт по флагу)
        disableNoFWait()
        restoreLighting(); lightSavedOK = false
        pcall(function()
            local cam = Workspace.CurrentCamera
            if cam then cam.FieldOfView = 70 end
        end)
        log("Visuals/World остановлен")
    end

    -- ─────────────────────────────────────────────────────────────────────
    -- UI-интеграция (MacLib). Visuals-модуль раскидывает контролы по табам:
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
        local flag = ui.flag or function(s) return "VIS_" .. s end
        local tabV   = ui.tabs and ui.tabs.Visuals
        local tabMov = ui.tabs and ui.tabs.Movement
        local tabGM  = ui.tabs and ui.tabs.GunMods
        local tabMisc = ui.tabs and ui.tabs.Misc
        local tabDbg  = ui.tabs and ui.tabs.Debug
        local ntf = ui.notify or function() end

        -- Sync a MacLib toggle's visual state with V[<key>] (used by keybinds).
        local function syncToggle(f, val)
            local ML = ui.MacLib
            if ML and ML.Options and ML.Options[f] then
                pcall(function() ML.Options[f]:UpdateState(val) end)
            end
        end
        -- Keybind that toggles a V[key] boolean and updates its paired toggle.
        local function kbToggle(section, name, key, toggleFlag, label)
            if not ui.keybind then return end
            ui.keybind(section, { Name = name, Flag = flag(key .. "_KB"),
                Toggle = function()
                    V[key] = not V[key]
                    syncToggle(flag(toggleFlag), V[key])
                    ntf(label or name, V[key] and "Enabled" or "Disabled")
                end })
        end

        if tabV then
            -- ── Viewmodel (hands) ──────────────────────────────────────────
            local S = tabV:Section({ Name = "Viewmodel", Side = "Left" })
            S:Header({ Name = "Viewmodel (hands)" })
            S:Toggle({ Name = "Enabled", Default = V.ViewmodelEnabled,
                Callback = function(v)
                    V.ViewmodelEnabled = v
                    ntf("Viewmodel", v and "Enabled" or "Disabled")
                end }, flag("VM"))
            kbToggle(S, "Keybind", "ViewmodelEnabled", "VM", "Viewmodel")
            S:SubLabel({ Text = "Recolors/re-materializes your first-person arms." })
            S:Toggle({ Name = "Recolor", Default = V.ViewmodelColorEnabled,
                Callback = function(v) V.ViewmodelColorEnabled = v end }, flag("VMColorOn"))
            S:Colorpicker({ Name = "Color", Default = V.ViewmodelColor,
                Callback = function(c) V.ViewmodelColor = c end }, flag("VMColor"))
            S:Toggle({ Name = "Change Material", Default = V.ViewmodelMaterialEnabled,
                Callback = function(v) V.ViewmodelMaterialEnabled = v end }, flag("VMMatOn"))
            S:Dropdown({ Name = "Material", Options = MATERIALS, Default = matName(V.ViewmodelMaterial),
                Callback = function(n)
                    V.ViewmodelMaterial = matFromName(n)
                    ntf("Viewmodel Material", n)
                end }, flag("VMMat"))
            S:Slider({ Name = "Transparency", Default = math.floor((V.ViewmodelTransparency or 0) * 100),
                Minimum = 0, Maximum = 100, Precision = 0, Suffix = "%",
                Callback = function(v)
                    V.ViewmodelTransparency = v / 100
                    -- при изменении прозрачности сбросить кэш store чтобы переприменить
                    restoreViewmodelStyle()
                end }, flag("VMTransp"))
            S:Slider({ Name = "Custom FOV", Default = V.ViewmodelFOV or 0, Minimum = 0, Maximum = 120,
                Precision = 0, Callback = function(v) V.ViewmodelFOV = v end }, flag("VMFov"))
            S:SubLabel({ Text = "0 = don't change camera FOV." })
            S:Divider()
            S:Header({ Name = "Viewmodel Gradient" })
            S:Toggle({ Name = "Gradient", Default = V.ViewmodelGradientEnabled,
                Callback = function(v)
                    V.ViewmodelGradientEnabled = v
                    ntf("VM Gradient", v and "Enabled" or "Disabled")
                end }, flag("VMGrad"))
            S:SubLabel({ Text = "Two-color gradient (set colors on the right)." })

            -- ── Gun Model ──────────────────────────────────────────────────
            local G = tabV:Section({ Name = "Gun Model", Side = "Left" })
            G:Header({ Name = "Gun Model" })
            G:Toggle({ Name = "Enabled", Default = V.GunModelEnabled,
                Callback = function(v)
                    V.GunModelEnabled = v
                    ntf("Gun Model", v and "Enabled" or "Disabled")
                end }, flag("GM"))
            kbToggle(G, "Keybind", "GunModelEnabled", "GM", "Gun Model")
            G:Toggle({ Name = "Recolor", Default = V.GunModelColorEnabled,
                Callback = function(v) V.GunModelColorEnabled = v end }, flag("GMColorOn"))
            G:Colorpicker({ Name = "Color", Default = V.GunModelColor,
                Callback = function(c) V.GunModelColor = c end }, flag("GMColor"))
            G:Toggle({ Name = "Change Material", Default = V.GunModelMaterialEnabled,
                Callback = function(v) V.GunModelMaterialEnabled = v end }, flag("GMMatOn"))
            G:Dropdown({ Name = "Material", Options = MATERIALS, Default = matName(V.GunModelMaterial),
                Callback = function(n)
                    V.GunModelMaterial = matFromName(n)
                    ntf("Gun Model Material", n)
                end }, flag("GMMat"))
            G:Slider({ Name = "Transparency", Default = math.floor((V.GunModelTransparency or 0) * 100),
                Minimum = 0, Maximum = 100, Precision = 0, Suffix = "%",
                Callback = function(v)
                    V.GunModelTransparency = v / 100
                    restoreGunStyle()
                end }, flag("GMTransp"))
            G:Divider()
            G:Header({ Name = "Gun Model Gradient" })
            G:Toggle({ Name = "Gradient", Default = V.GunModelGradientEnabled,
                Callback = function(v)
                    V.GunModelGradientEnabled = v
                    ntf("GM Gradient", v and "Enabled" or "Disabled")
                end }, flag("GMGrad"))
            G:SubLabel({ Text = "Wave flows part-to-part (see Wave Spread on the right)." })

            -- ── Third person + shared gradient colors ──────────────────────
            local S2 = tabV:Section({ Name = "Third Person", Side = "Right" })
            S2:Header({ Name = "Third Person Model" })
            S2:Toggle({ Name = "Enabled", Default = V.ThirdPersonEnabled,
                Callback = function(v)
                    V.ThirdPersonEnabled = v
                    ntf("Third Person", v and "Enabled" or "Disabled")
                end }, flag("TP"))
            kbToggle(S2, "Keybind", "ThirdPersonEnabled", "TP", "Third Person")
            S2:SubLabel({ Text = "Styles your own body (visible in third person camera)." })
            S2:Colorpicker({ Name = "Body Color", Default = V.ThirdPersonBodyColor,
                Callback = function(c) V.ThirdPersonBodyColor = c end }, flag("TPColor"))
            S2:Slider({ Name = "Body Transparency", Default = math.floor((V.ThirdPersonBodyTransparency or 0) * 100),
                Minimum = 0, Maximum = 100, Precision = 0, Suffix = "%",
                Callback = function(v) V.ThirdPersonBodyTransparency = v / 100 end }, flag("TPTransp"))
            S2:Toggle({ Name = "Gradient", Default = V.ThirdPersonGradientEnabled,
                Callback = function(v)
                    V.ThirdPersonGradientEnabled = v
                    ntf("TP Gradient", v and "Enabled" or "Disabled")
                end }, flag("TPGrad"))

            local GC = tabV:Section({ Name = "Gradient Colors", Side = "Right" })
            GC:Header({ Name = "Gradient (2-color)" })
            GC:SubLabel({ Text = "Smoothly blends Color A into Color B and back. Not a rainbow." })
            GC:Colorpicker({ Name = "Color A", Default = V.GradientColorA,
                Callback = function(c) V.GradientColorA = c end }, flag("GradA"))
            GC:Colorpicker({ Name = "Color B", Default = V.GradientColorB,
                Callback = function(c) V.GradientColorB = c end }, flag("GradB"))
            GC:Slider({ Name = "Speed", Default = V.GradientSpeed, Minimum = 0.05, Maximum = 2,
                Precision = 2, Suffix = " Hz",
                Callback = function(v) V.GradientSpeed = v end }, flag("GradSpeed"))
            GC:Slider({ Name = "Gun Wave Spread", Default = V.GunModelGradientSpread, Minimum = 0,
                Maximum = 5, Precision = 1,
                Callback = function(v)
                    V.GunModelGradientSpread = v
                    -- сбросить кэш фаз частей (gp) чтобы волна пересчиталась
                    for _, rec in pairs(gunStyledParts) do rec.gp = nil end
                end }, flag("GradSpread"))
            GC:SubLabel({ Text = "0 = all gun parts change color together." })
        end

        if tabMov then
            local S = tabMov:Section({ Name = "Vehicle", Side = "Right" })
            S:Header({ Name = "Vehicle" })
            S:Toggle({ Name = "Enabled", Default = V.VehicleFlyEnabled,
                Callback = function(v)
                    V.VehicleFlyEnabled = v
                    ntf("Vehicle Fly", v and "Enabled" or "Disabled")
                end }, flag("VehFly"))
            kbToggle(S, "Fly Keybind", "VehicleFlyEnabled", "VehFly", "Vehicle Fly")
            S:Slider({ Name = "Fly Speed", Default = V.VehicleFlySpeed, Minimum = 20, Maximum = 400,
                Precision = 0, Suffix = " st/s",
                Callback = function(v) V.VehicleFlySpeed = v end }, flag("VehFlySpeed"))
            S:Divider()
            S:Header({ Name = "Vehicle Speed" })
            S:Toggle({ Name = "Enabled", Default = V.VehicleSpeedEnabled,
                Callback = function(v)
                    V.VehicleSpeedEnabled = v
                    ntf("Vehicle Speed", v and "Enabled" or "Disabled")
                end }, flag("VehSpeed"))
            kbToggle(S, "Speed Keybind", "VehicleSpeedEnabled", "VehSpeed", "Vehicle Speed")
            S:Slider({ Name = "Speed Multiplier", Default = V.VehicleSpeedMult, Minimum = 1, Maximum = 6,
                Precision = 1, Suffix = "x",
                Callback = function(v) V.VehicleSpeedMult = v end }, flag("VehSpeedMult"))
        end

        if tabGM then
            local S = tabGM:Section({ Name = "Free Gun", Side = "Left" })
            S:Header({ Name = "Free Gun" })
            S:Toggle({ Name = "Enabled", Default = V.FreeGunEnabled,
                Callback = function(v)
                    V.FreeGunEnabled = v
                    ntf("Free Gun", v and "Enabled" or "Disabled")
                end }, flag("FreeGun"))
            kbToggle(S, "Keybind", "FreeGunEnabled", "FreeGun", "Free Gun")
            S:SubLabel({ Text = "Removes the equip block (e.g. lets you draw a weapon inside vehicles)." })
        end

        if tabMisc then
            local SFB = tabMisc:Section({ Name = "Fullbright", Side = "Left" })
            SFB:Header({ Name = "Fullbright" })
            SFB:Toggle({ Name = "Enabled", Default = V.FullbrightEnabled,
                Callback = function(v)
                    V.FullbrightEnabled = v
                    ntf("Fullbright", v and "Enabled" or "Disabled")
                end }, flag("Fullbright"))
            kbToggle(SFB, "Keybind", "FullbrightEnabled", "Fullbright", "Fullbright")

            local SNF = tabMisc:Section({ Name = "No Fog", Side = "Left" })
            SNF:Header({ Name = "No Fog" })
            SNF:Toggle({ Name = "Enabled", Default = V.NoFogEnabled,
                Callback = function(v)
                    V.NoFogEnabled = v
                    ntf("No Fog", v and "Enabled" or "Disabled")
                end }, flag("NoFog"))

            local SA = tabMisc:Section({ Name = "Ambient", Side = "Left" })
            SA:Header({ Name = "Ambient (time of day)" })
            SA:Toggle({ Name = "Enabled", Default = V.AmbientEnabled,
                Callback = function(v)
                    V.AmbientEnabled = v
                    ntf("Ambient", v and "Enabled" or "Disabled")
                end }, flag("Ambient"))
            SA:Slider({ Name = "Clock Time", Default = V.AmbientClockTime, Minimum = 0, Maximum = 24,
                Precision = 0, Suffix = "h",
                Callback = function(v) V.AmbientClockTime = v end }, flag("ClockTime"))
            SA:Slider({ Name = "Brightness", Default = V.AmbientBrightness or 2, Minimum = 0, Maximum = 10,
                Precision = 1,
                Callback = function(v) V.AmbientBrightness = v end }, flag("AmbBright"))

            local SIN = tabMisc:Section({ Name = "Interactions", Side = "Left" })
            SIN:Header({ Name = "Interactions" })
            SIN:Toggle({ Name = "No Prompt Hold", Default = V.NoFWaitEnabled,
                Callback = function(v)
                    V.NoFWaitEnabled = v
                    ntf("No Prompt Hold", v and "Enabled" or "Disabled")
                end }, flag("NoFWait"))
            SIN:SubLabel({ Text = "Interactions trigger instantly instead of holding F." })
            SIN:Toggle({ Name = "Lockpick Bypass", Default = V.LockpickBypassEnabled,
                Callback = function(v)
                    V.LockpickBypassEnabled = v
                    ntf("Lockpick Bypass", v and "Enabled" or "Disabled")
                end }, flag("Lockpick"))
            SIN:SubLabel({ Text = "Auto-completes the lockpick minigame." })
        end

        if tabDbg then
            local D = tabDbg:Section({ Name = "Visuals", Side = "Left" })
            D:Header({ Name = "Visuals — Intervals" })
            D:Slider({ Name = "Lockpick Scan Interval", Default = math.floor((V.LockpickScanInterval or 0.4) * 1000),
                Minimum = 100, Maximum = 2000, Precision = 0, Suffix = " ms",
                Callback = function(v) V.LockpickScanInterval = v / 1000 end }, flag("DbgLockpick"))
        end
    end

    return M
end
