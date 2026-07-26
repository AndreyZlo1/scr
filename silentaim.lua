--[[
	BRM5SilentAim_v22 — CHANGELOG от v21:

	FIX MELEE HANDS:
	  weaponContextValid в delayed rediscover — melee не требует tune.

	BRM5SilentAim_v21 — CHANGELOG от v20:

	FIX HANDS AFTER RESPAWN (weapon unchanged in slots):
	  schedulePostRespawnWeaponRediscover + tickHandRediscoverIfNeeded — polling без MoveItem/Equip.
	  Сброс lastInventoryGcResult — stale GC inventory после смерти.

	BRM5SilentAim_v20 — CHANGELOG от v19:

	FIX WEAPON STUCK AFTER DEATH:
	  installCharacterLifecycle(resetAfterRespawn) — Died сбрасывает HUD/ctx, respawn переустанавливает хуки.
	  Ранее resetAfterRespawn был определён, но нигде не вызывался.

	FIX FPS (без оружия в руках):
	  FOV circle weapon check throttled 0.12s — getLiveWeaponContext не каждый Heartbeat.

	BRM5SilentAim_v19 — CHANGELOG от v18:

	FIX WEAPON NOT DETECTED AFTER DEATH:
	  ПАТЧ A: hookSharedInventoryTable теперь сохраняет si ref в State.sharedInventorySiRef.
	  resetAfterRespawn делает rawset(si, "__brm5Hooked", nil) — хуки переустанавливаются.
	  Ранее: require кэшировал si, __brm5Hooked оставался true → hookSharedInventoryTable
	  делал early return → PerformEquipCalls не перехватывался → handItem не обновлялся.

	FIX FPS DROP ON EQUIP/DEATH:
	  ПАТЧ B: debounce в hookOwnerChange.Change.
	  При rebuild инвентаря Change зовётся N раз подряд → было N task.defer.
	  Теперь только ОДИН defer выполняется, остальные пропускаются.
	  ПАТЧ C: State.trackHandPending сбрасывается в resetAfterRespawn.

	BRM5SilentAim_v18 — CHANGELOG:
	  FIX: HitParticle smooth fade (fadeStart 45%→65%, _fadeOverlap=0.06)
	  FIX: getLocalMuzzleCFrame TP — Focused=false → HRP + Camera.LookVector
	  REMOVED: Backtrack (getBacktrackSec=0, shouldUseBacktrackAim=false)
	  FIX: combatAimActive → проверяет getLiveWeaponContext (требует firearm)
]]
--[[
	BRM5SilentAim_v1 — Silent Aim module
	Загружает BRM5Lib и добавляет хуки прицеливания.
	Запускать ПОСЛЕ BRM5Lib:
	  local Lib = loadstring(readfile("BRM5Lib.lua"))()
	  local SA  = loadstring(readfile("BRM5SilentAim.lua"))()(Lib)
]]
return function(Lib)
local Bridge = Lib.Bridge
local CONFIG = Lib.CONFIG
local State  = Lib.State

-- Local aliases для internal функций из BRM5Lib
local getCamera           = function(...) return Bridge._getCamera(...) end
local log                 = function(...) return Bridge._log(...) end
local mpActive            = function(...) return Bridge._mpActive(...) end
local LP                  = game:GetService("Players").LocalPlayer
local tableField          = function(...) return Bridge._tableField(...) end
local getGcCached        = function(...) return Bridge._getGcCached(...) end
local resolveLocalClient  = function(...) return Bridge._resolveLocalClient(...) end
local resolveLocalPlayer  = function(...) return Bridge._resolveLocalPlayer(...) end
local RS             = Bridge._RS
local RF             = Bridge._RF
local RunService     = Bridge._RunService
local HttpService    = Bridge._HttpService
local Players        = Bridge._Players
local FIREMODE       = Bridge._FIREMODE

local function brm5Global()
	local g = (type(getgenv) == "function" and getgenv()) or _G
	g.__BRM5 = g.__BRM5 or {}
	if not g.__BRM5.State then
		g.__BRM5.State = State
	end
	return g.__BRM5
end

local function saState()
	local g = brm5Global()
	return g.State or State
end

local function markCombatDischarge()
	local S = saState()
	S.lastDischargeAimTime = os.clock()
	S.localDischargePending = true
end

-- Compat-шимы удалены: library.lua безусловно определяет isLocalPlayerShot,
-- isOurBulletEvent, logBulletHit и экспортирует _getGcCached ДО загрузки
-- модулей, поэтому все четыре проверки `if type(...) ~= "function"` были
-- заведомо ложными, а их тела — недостижимы.

-- SA-specific configuration
local SA_CONFIG = {
	AimTargetRefreshInterval = 0.06,
	AimVisualInterval = 0.1,
	AimVisualDrawInterval = 0.055,
	CombatAimRefreshInterval = 0.08,
	AimScanMaxActors = 14,
	MultiPointCacheSec = 0.28,
	MultiPointStickySec = 0.35,
	MultiPointRequireLos = false,
	MuzzlePeekMaxOffset = 6,
	SpoofMuzzleCacheSec = 0.12,
	LosRaycastCacheSec = 0.1,
	MuzzleVisual = true,
	MuzzleLineColor = Color3.fromRGB(80, 220, 255),
	MuzzleLineThickness = 2.0,
	MuzzleLineTransparency = 0.15,
	ClientMuzzleSpoof = true,
	ServerFirstBullet = false,
	ServerOnlyAimPatch = false,
	ServerAimDebug = false,
	SilentAim = false,           -- master OFF by default
	SilentAimFOV = 120,
	FovCircle = true,            -- FOV v11: показывать FOV circle
	FovCircleColor = Color3.fromRGB(255, 255, 255),
	FovCircleThickness = 1,
	FovCircleFilled = false,
	FovCircleTransparency = 0.6, -- 0=непрозрачный, 1=невидимый
	SilentAimBone = "Head",
	SilentAimTargetHostile = true,
	SilentAimTargetPlayers = true,
	SilentAimMaxDistance = 500,
	SilentAimOnlySafe = false,
	TeamCheck = true,
	-- Prediction: ballistic flight time (g=32.2) + root velocity lead; PingCompensation — доп. lead по RTT.
	Prediction = true,
	-- ЛЁГКИЙ предикт (тест): pos + velocity * t, без оружия/баллистики/гравитации.
	-- Когда включён — полностью подменяет обычный предикт (см. library.predictAimPoint).
	PredictionLite = false,
	PredictionLiteTime = 0.12,    -- секунд упреждения для лёгкого предикта
	PingCompensation = true,      -- на высоком пинге без неё выстрел не регается
	PredictionIterations = 3,     -- итераций сходимости времени полёта (2-4)
	PredictionVertical = false,    -- учитывать вертикальную скорость (прыжки/падения)
	PredictionVertCap = 10,       -- кап вертикальной скорости (studs/s)
	PredictionMaxVelCap = 35,     -- кап горизонтальной скорости (studs/s)
	PingCompensationScale = 1.0,  -- доля RTT (1.0 = полный RTT)
	PingCompensationMax = 0.5,    -- потолок упреждения по пингу, сек
	DefaultBulletSpeed = 920,
	ForceZeroSpread = true,
	MultiPoint = false,
	LiteMultiPoint = true,
	LiteMultiPointCacheSec = 0.55,
	LiteMultiPointMaxDist = 8,
	LiteMultiPointMaxActors = 3,
	LiteMultiPointBinarySteps = 2,
	LiteMultiPointRefreshInterval = 0.09,
	MultiPointMaxMuzzleDist = 8,
	ResolverLite = true,
	ResolverLiteMode = "Aim",
	ResolverLiteInset = 0.08,
	ResolverScanInterval = 0.18,
	ForceClientHit = true,
	ForceHit = true,
	IgnoreTeammates = true,
	AimSkipDeadHP = true,
	AimVisuals = true,
	ShotTracers = true,
	TracerDuration = 1.4,
	TracerFadeIn = 0.12,
	TracerThickness = 0.9,
	TracerColor = Color3.fromRGB(255, 90, 35),
	TracerTransparency = 0,
	AimVisualStyle = "Swastika",
	AimVisualScale = 0.5,
	HitSound = true,
	HitSoundName = "Default",   -- имя из HIT_SOUNDS (см. ниже)
	HitSoundId = nil,           -- override: числовой id, если нужен свой звук
	HitSoundVolume = 0.85,
	HitSoundPitch = 1.0,
	HitParticles = true,
	HitParticleCount = 20,
	HitParticleMaxSystems = 5,
	HitParticleDuration = 1.1,
	HitParticleConnectDist = 14,
	HitParticleSpeedMin = 2,
	HitParticleSpeedMax = 32,
	HitParticleGravity = -32,
	HitParticleTickSec = 0.022,
	HitParticleOpacityMin = 0.08,
	HitParticleOpacityMax = 0.55,
	HitParticleWireScale = 0.4,
	HitParticleWireframe = true,
	-- FIX v8: показ игроков в PVE/ZMP
	EspShowPlayersInPve   = true,
	ForceShowAllPlayers   = true,
	SwastikaRGB = true,
	ForceHitTimeOff = 0,
	-- ── Backtrack УДАЛЁН v23 ──────────────────────────────────────
	-- Причина: премис бэктрека ошибочен. По дампу Flux (ReplicatorService
	-- ._bulletProcess → GetFromBodyPart → ActorClass:GetSelf) 3-й возврат,
	-- который код принимал за "Unix" снапшота lag-comp, на деле = solveIK(part)
	-- (ActorClass: `local u23 = v1("solveIK")` → `return UID, self, u23(part)`).
	-- Это ге��метрия IK текущей позы, а НЕ индекс серверной истории для отмотки.
	-- Хит-рег клиент-авторитетный по {UID, Part}; переигрыш старого значения
	-- ничего не отматывает и лишь рискует провалить валидацию попадания.
	-- ── Resolver/MultiPoint FPS-бюджет (масштабирование по игрокам) ──
	ResolverBudgetPerFrame  = 4,        -- макс. тяжёлых резолвов не-целей за окно
	ResolverBudgetWindow    = 1 / 60,   -- длина окна бюджета (сек)
	ResolverDistScale       = 140,      -- дистанц. троттлинг ResolverLite (studs)
	LiteMultiPointDistScale = 200,      -- дистанц. троттлинг LiteMultiPoint (studs)
	SilentAimIgnoreNpc = false,
	SilentAimPreferPlayers = true,
	-- В PVE-режимах игроки — кооп-союзники: silent aim их пропускает (ESP не трогаем).
	SilentAimIgnorePlayersInPve = true,
	DrawingHighTransparencyMeansVisible = true,
	LogBulletPayload = false,
	LogBulletEvent = false,
	LogV138Patch = false,
	ForceHitDebug = false,  -- OPT: было true → печатал FH-диагностику каждый выстрел (обход QuietLogs)
	QuietLogs = true,
	BulletLogHitsOnly = true,
	LocalBulletsOnly = true,
	TracerLocalOnly = true,
	ModifyEnabled = false,       -- weapon mods OFF by default
	ModifyReapplyInterval = 0.5, -- как часто (сек) переприменять моды (ловит смену оружия для ВСЕХ пушек)
	ModifyPassInterval = 0.5,    -- троттл полного прохода по всем стволам инвентаря
	ModifyRPMValue = 1200,
	ModifyBulletSpeedValue = 2000,
	ModifyPresets = {
		-- NoSpread: обнуляет Barrel_Spread, cal.Spread и все *Spread* в Tune
		-- NoRecoil: обнуляет Recoil_X/Z, RecoilForce, ViewModel Recoil
		-- NoViewKick: только камера/отдача визуально (Recoil_Camera, KickBack)
		NoViewKick = true,
		-- RPM: выставляет tune.RPM = ModifyRPMValue
		RPM = true,
		-- FullAuto: принудительно Auto firemode + handler._auto
		FullAuto = true,
		-- InstantBolt: Bolt_Action_Pause/Shell = 0, NoPause = true
		InstantBolt = true,
		-- FastEquip: только Tune (Equip_Delay=0), без runtime-хуков
		FastEquip = true,
		-- NoSway: обнуляет Sway/Shake/Bob в Tune и ViewModel
		NoSway = true,
		-- NoSpeedPenalty: убирает замедление при стрельбе (Tune.Speed_Penalty)
		NoSpeedPenalty = true,
		-- LightWeight: снижает вес оружия в Tune/Meta
		LightWeight = true,
		-- FlatBallistics: ниже BallisticCoeff, ровнее траектория
		FlatBallistics = true,
		-- BulletSpeed: override скорости пули (ModifyBulletSpeedValue)
		BulletSpeed = false,
	},
}
for k, v in pairs(SA_CONFIG) do
	Lib.CONFIG[k] = v
end
local CONFIG = Lib.CONFIG


function Bridge.isSilentAimTargetClass(class)
	if class == "self" then return false end
	if CONFIG.SilentAimIgnoreNpc == true and (
		class == "npc" or class == "npc_hostile" or class == "npc_zombie" or class == "npc_friendly"
	) then
		return false
	end
	if class == "player" then
		if Bridge.isPveMode and Bridge.isPveMode() then return false end
		return CONFIG.SilentAimTargetPlayers ~= false
	end
	if CONFIG.SilentAimTargetHostile ~= false then
		return class == "npc_hostile" or class == "npc" or class == "npc_zombie"
	end
	return class ~= "npc_friendly"
end

function Bridge.getSilentAimPart(data)
	if not data or not data.model or not data.model.Parent then return nil end
	local bone = CONFIG.SilentAimBone or "Head"
	local part = data.model:FindFirstChild(bone)
	if part and part:IsA("BasePart") then return part end
	return data.root
end

-- Дубль удалён: та же математика, что в library.lua, но БЕЗ проверки cam
-- на nil. Загружаясь, silentaim затирал библиотечную версию — и терял
-- защиту от отсутствующей камеры. Используется библиотечная.
function Bridge.getSilentAimTarget(originForLos, forceRefresh)
	return Bridge.refreshAimTarget(originForLos, forceRefresh == true)
end

function Bridge.forceSpoofOriginCFrame(originCFrame, targetPart, aimWorldPos)
	if typeof(originCFrame) ~= "CFrame" then return originCFrame end
	if not Bridge.shouldClientSpoofMuzzlePosition() then return originCFrame end
	local target = targetPart or State.shotAimTarget
	if not target or not target.Parent then return originCFrame end
	local look = aimWorldPos or State.forceHitPoint or State.aimAimPoint
	if typeof(look) ~= "Vector3" then return originCFrame end
	local origin = originCFrame.Position
	if not Bridge.needsMuzzleOffset(origin, look, target) then
		return originCFrame
	end
	local spoofPos = Bridge.resolveCombatMuzzleOffset(origin, look, target)
	if typeof(spoofPos) ~= "Vector3" or (spoofPos - origin).Magnitude < 0.05 then
		return originCFrame
	end
	if (look - spoofPos).Magnitude < 0.01 then
		return originCFrame
	end
	local cf = CFrame.lookAt(spoofPos, look)
	State.combatMuzzleCf = cf
	State.spoofedMuzzlePos = spoofPos
	return cf
end

function Bridge.retargetOriginCFrame(originCFrame, targetPart, aimWorldPos)
	if typeof(originCFrame) ~= "CFrame" or not targetPart then
		return originCFrame
	end
	local look = aimWorldPos or State.forceHitPoint or State.aimAimPoint or targetPart.Position
	if typeof(look) ~= "Vector3" then
		return originCFrame
	end
	if Bridge.shouldSpoofMuzzlePosition()
		and Bridge.needsMuzzleOffset(originCFrame.Position, look, targetPart) then
		return Bridge.forceSpoofOriginCFrame(originCFrame, targetPart, look)
	end
	if (look - originCFrame.Position).Magnitude < 0.01 then
		return originCFrame
	end
	local cf = CFrame.lookAt(originCFrame.Position, look)
	if State.inDischargeHook then
		State.combatMuzzleCf = cf
	end
	return cf
end

function Bridge.spawnShotTracer(origin, targetPos, opts)
	if not CONFIG.ShotTracers or not Drawing then return end
	opts = type(opts) == "table" and opts or {}
	if opts.bulletUid and not Bridge.isMyBulletUid(opts.bulletUid) then
		return
	end
	if CONFIG.TracerLocalOnly ~= false and not opts.bulletUid and opts.verifiedLocal ~= true then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(targetPos) ~= "Vector3" then return end
	if (targetPos - origin).Magnitude < 0.05 then return end
	local line = Drawing.new("Line")
	line.Thickness = CONFIG.TracerThickness or 0.9
	line.Color = CONFIG.TracerColor or Color3.fromRGB(255, 90, 35)
	line.ZIndex = 30
	line.Visible = true
	Bridge.setDrawingAlpha(line, 0)
	State.shotLines[#State.shotLines + 1] = {
		a = origin,
		b = targetPos,
		born = os.clock(),
		line = line,
	}
	local maxLines = 20
	while #State.shotLines > maxLines do
		local old = table.remove(State.shotLines, 1)
		if old and old.line then Bridge.destroyDrawing(old.line) end
	end
end

function Bridge.tracerAlpha(age, life, fadeIn)
	fadeIn = fadeIn or CONFIG.TracerFadeIn or 0.12
	if age < fadeIn then
		return (age / fadeIn) * (age / fadeIn)
	end
	local tail = life - fadeIn
	if tail <= 0.01 then return 0 end
	local t = (age - fadeIn) / tail
	return (1 - t) * (1 - t)
end

function Bridge.updateShotTracers()
	if not CONFIG.ShotTracers or not Drawing or #State.shotLines == 0 then return end
	local cam = getCamera()
	if not cam then return end
	local life = CONFIG.TracerDuration or 1.4
	local now = os.clock()
	for i = #State.shotLines, 1, -1 do
		local e = State.shotLines[i]
		local age = now - (e.born or now)
		if age >= life then
			Bridge.destroyDrawing(e.line)
			table.remove(State.shotLines, i)
		else
			local sp1, on1 = cam:WorldToViewportPoint(e.a)
			local sp2, on2 = cam:WorldToViewportPoint(e.b)
			local alpha = Bridge.tracerAlpha(age, life, CONFIG.TracerFadeIn)
			if (on1 or on2) and sp1.Z > 0.01 and sp2.Z > 0.01 then
				e.line.From = Vector2.new(sp1.X, sp1.Y)
				e.line.To = Vector2.new(sp2.X, sp2.Y)
				e.line.Thickness = (CONFIG.TracerThickness or 0.9) + alpha * 0.5
				local tracerBaseColor = CONFIG.TracerColor or Color3.fromRGB(255, 90, 35)
				e.line.Color = tracerBaseColor:Lerp(Color3.new(1, 1, 1), alpha * 0.18)
				local tracerVis = 1 - (CONFIG.TracerTransparency or 0)
				Bridge.showDrawing(e.line, alpha * tracerVis)
			else
				e.line.Visible = false
			end
		end
	end
end

function Bridge.clearShotTracers()
	for _, e in ipairs(State.shotLines) do
		if e.line then Bridge.destroyDrawing(e.line) end
	end
	table.clear(State.shotLines)
end

-- legacy alias
function Bridge.clearBulletTracers()
	Bridge.clearShotTracers()
end

-- BACKTRACK удалён v23 — см. заметку в SA_CONFIG.
-- Премис (3-й возврат GetSelf = "Unix" lag-comp) неверен: это solveIK(part).
-- Хит-рег клиент-авторитетный по {UID, Part}; отмотка невозможна/вредна.

function Bridge.shouldRetargetClientMuzzle()
	if mpActive() then return true end
	if CONFIG.MuzzleVisual and CONFIG.SilentAim then return true end
	if CONFIG.SilentAim then return true end
	return false
end

function Bridge.ensureGameBulletPayload(payload, ctx)
	if type(payload) ~= "table" or payload.Local ~= true then return end
	if CONFIG.SilentAim or mpActive() then
		Bridge.patchBulletPayload(payload)
	end
	local aimPt = State.forceHitPoint or State.aimAimPoint
	local target = State.shotAimTarget or State.aimTargetPart
	local origin = typeof(payload.OriginCFrame) == "CFrame" and payload.OriginCFrame.Position or nil
	if typeof(origin) == "Vector3" and typeof(aimPt) == "Vector3" and target and target.Parent then
		payload.Ignore = Bridge.applyCombatBulletIgnore(payload.Ignore, origin, aimPt, target)
	else
		payload.Ignore = Bridge.applyTeammateBulletIgnore(payload.Ignore)
	end
	if CONFIG.SilentAim or Bridge.shouldForceClientHit() then
		local snap = Bridge.buildBulletForceHitSnapshot(origin, payload.UID)
		if snap then
			snap.replicate = payload.Replicate ~= nil and payload.Replicate or true
			payload._brm5Fh = snap
		end
	end
end

function Bridge.prepareSilentAimShot(originCFrame)
	if typeof(originCFrame) ~= "CFrame" then
		return nil, originCFrame
	end
	if not CONFIG.SilentAim and not mpActive() then
		return nil, originCFrame
	end
	if CONFIG.LiteMultiPoint and not State.mpShotReady and not Bridge.shouldForceClientHit() then
		return nil, originCFrame
	end
	if State.inShotPrep or State.inDischargeHook or State.inGetMuzzleHook then
		local target = State.shotAimTarget
		local aimLook = State.forceHitPoint or State.aimAimPoint
		local aimCf = originCFrame
		if target and target.Parent and typeof(aimLook) == "Vector3"
			and Bridge.shouldRetargetClientMuzzle() then
			aimCf = Bridge.retargetOriginCFrame(originCFrame, target, aimLook)
		end
		if Bridge.shouldSpoofMuzzlePosition() and target and target.Parent
			and typeof(aimLook) == "Vector3"
			and Bridge.needsMuzzleOffset(aimCf.Position, aimLook, target) then
			aimCf = Bridge.applyShotOriginSpoof(aimCf)
		end
		return target, aimCf
	end
	local target = Bridge.getCombatAimTarget(originCFrame.Position, State.forceCombatAimRefresh)
	State.forceCombatAimRefresh = false
	if not target then
		return nil, originCFrame
	end
	State.shotAimTarget = target
	State.shotAimTargetTime = os.clock()
	if Bridge.needsServerAimPatch() then
		Bridge.prepareServerAimShot(originCFrame.Position, target)
	end
	local aimLook = State.forceHitPoint or State.aimAimPoint
	local aimCf = originCFrame
	if Bridge.shouldRetargetClientMuzzle() then
		aimCf = Bridge.retargetOriginCFrame(originCFrame, target, aimLook)
	end
	if Bridge.shouldSpoofMuzzlePosition() and typeof(aimLook) == "Vector3"
		and Bridge.needsMuzzleOffset(aimCf.Position, aimLook, target) then
		aimCf = Bridge.applyShotOriginSpoof(aimCf)
	end
	return target, aimCf
end

function Bridge.patchHitPartAndPos(hitPos, part, originPos)
	if part and Bridge.isEnemyHitPart(part) then
		local nh, np = Bridge.redirectEnemyHitToAimBone(hitPos, part, originPos, nil)
		return nh, np
	end
	local S = saState()
	local patchClient = CONFIG.SilentAim or mpActive() or Bridge.shouldForceClientHit()
	if not patchClient then
		return hitPos, part
	end
	local target = S.shotAimTarget or S.aimTargetPart
	if (not target or not target.Parent) and typeof(originPos) == "Vector3" then
		target = Bridge.getCombatAimTarget(originPos, false)
	end
	if not target or not target.Parent then
		return hitPos, part
	end
	if mpActive() and CONFIG.MultiPointTestBlatant then
		local head = Bridge.getHeadPart(target.Parent, target)
		if head and head.Parent then
			return head.Position, head
		end
	end
	local aimPos = S.forceHitPoint or S.aimAimPoint or target.Position
	if typeof(aimPos) ~= "Vector3" then
		return hitPos, part
	end
	local model = target.Parent
	local bonePart = (model and model:IsA("Model"))
		and Bridge.resolveAimBonePart(model, target) or target
	return aimPos, bonePart or target
end

local function applyDischargeAim(originCFrame)
	if typeof(originCFrame) ~= "CFrame" then
		return originCFrame
	end
	local now = os.clock()
	local target = State.shotAimTarget
	local aimPt = State.forceHitPoint or State.aimAimPoint
	if target and target.Parent and typeof(aimPt) == "Vector3"
		and now - (State.shotAimTargetTime or 0) < 0.15 then
		if Bridge.shouldRetargetClientMuzzle() then
			originCFrame = Bridge.retargetOriginCFrame(originCFrame, target, aimPt)
		end
	elseif not (State.inShotPrep or State.inGetMuzzleHook) then
		local _, aimCf = Bridge.prepareSilentAimShot(originCFrame)
		if typeof(aimCf) == "CFrame" then
			originCFrame = aimCf
		end
		target = State.shotAimTarget
		aimPt = State.forceHitPoint or State.aimAimPoint
		if target and target.Parent and typeof(aimPt) == "Vector3"
			and Bridge.shouldRetargetClientMuzzle() then
			originCFrame = Bridge.retargetOriginCFrame(originCFrame, target, aimPt)
		end
	end
	if Bridge.shouldSpoofMuzzlePosition() and target and target.Parent
		and typeof(aimPt) == "Vector3"
		and Bridge.needsMuzzleOffset(originCFrame.Position, aimPt, target) then
		return Bridge.applyShotOriginSpoof(originCFrame)
	end
	return originCFrame
end

function Bridge.patchBulletEventOp2(originPos, hitPos, part, normal, isLocal)
	if not Bridge.shouldPatchClientBullet() and not Bridge.shouldForceClientHit() then
		return originPos, hitPos, part, normal, false
	end
	local isLocalShot = isLocal == true
	if not isLocalShot then
		return originPos, hitPos, part, normal, false
	end
	if part and Bridge.isEnemyHitPart(part) then
		local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(hitPos, part, originPos, nil)
		if changed then
			hitPos, part = nh, np
			if nn then normal = nn end
		end
		local spoofed = changed
		if typeof(originPos) == "Vector3" and Bridge.shouldSpoofMuzzlePosition() then
			local S = saState()
			local aimPos = S.forceHitPoint or S.aimAimPoint
			local target = S.shotAimTarget or S.aimTargetPart
			if typeof(aimPos) == "Vector3" and target and target.Parent
				and Bridge.needsMuzzleOffset(originPos, aimPos, target) then
				originPos = Bridge.resolveSpoofedMuzzleOrigin(originPos, aimPos, target)
				spoofed = true
			end
		end
		return originPos, hitPos, part, normal, spoofed
	end
	if Bridge.shouldForceClientHit() and (not part or not Bridge.isEnemyHitPart(part)) then
		local fOrigin, fHit, fPart, fNormal = Bridge.applyForceHitOp2(
			originPos, hitPos, part, normal, nil, nil, nil
		)
		if fPart and fPart.Parent then
			originPos, hitPos, part, normal = fOrigin, fHit, fPart, fNormal
			return originPos, hitPos, part, normal, true
		end
	end
	if not Bridge.shouldPatchClientBullet() then
		return originPos, hitPos, part, normal, false
	end
	local S = saState()
	if typeof(originPos) == "Vector3" and Bridge.shouldSpoofMuzzlePosition() then
		local aimPos = S.forceHitPoint or S.aimAimPoint
		local target = S.shotAimTarget or S.aimTargetPart
		if typeof(aimPos) == "Vector3" and target and target.Parent
			and Bridge.needsMuzzleOffset(originPos, aimPos, target) then
			originPos = Bridge.resolveSpoofedMuzzleOrigin(originPos, aimPos, target)
		end
	end
	hitPos, part = Bridge.patchHitPartAndPos(hitPos, part, originPos)
	if typeof(originPos) == "Vector3" and part then
		local n = originPos - (hitPos or part.Position)
		if n.Magnitude > 0.01 then
			normal = n.Unit
		end
	end
	return originPos, hitPos, part, normal, true
end

State.lastHitFxAt = State.lastHitFxAt or 0

-- Каталог хитсаундов. Раньше звук был один и захардкожен — теперь выбирается
-- по имени из UI, плюс регулируется громкость.
local HIT_SOUNDS = {
	["Default"]        = 106586644436584,
	["Fatality"]       = 115982072912004,
	["Minecraft XP"]   = 15181891182,
	["Minecraft Hit"]  = 73571339886360,
	["Minecraft Egg"]  = 134530432300459,
	["Minecraft Bow"]  = 111481862692779,
	["Click"]          = 95635059379804,
	["Bell"]           = 124010691633262,
	["Neverlose"]      = 139452805868562,
	["Primordial"]     = 97511223764004,
}
local HIT_SOUND_ORDER = {
	"Default", "Fatality", "Minecraft XP", "Minecraft Hit", "Minecraft Egg",
	"Minecraft Bow", "Click", "Bell", "Neverlose", "Primordial",
}
Bridge.HIT_SOUNDS      = HIT_SOUNDS
Bridge.HIT_SOUND_ORDER = HIT_SOUND_ORDER

function Bridge.resolveHitSoundId()
	-- Приоритет: явный числовой/строковый override → выбранное имя → Default
	local raw = CONFIG.HitSoundId
	if type(raw) == "number" then return "rbxassetid://" .. tostring(raw) end
	if type(raw) == "string" and raw ~= "" then
		if raw:match("^rbxassetid://") then return raw end
		if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	end
	local name = CONFIG.HitSoundName or "Default"
	local id = HIT_SOUNDS[name] or HIT_SOUNDS.Default
	return "rbxassetid://" .. tostring(id)
end

function Bridge.playLocalHitSound()
	if CONFIG.HitSound == false then return end
	local sid = Bridge.resolveHitSoundId()
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = sid
		s.Volume = math.clamp(CONFIG.HitSoundVolume or 0.85, 0, 1)
		s.PlaybackSpeed = math.clamp(CONFIG.HitSoundPitch or 1, 0.5, 2)
		-- SoundService надёжнее workspace: не привязан к 3D-позиции
		s.Parent = game:GetService("SoundService")
		s:Play()
		game:GetService("Debris"):AddItem(s, 4)
	end)
end

-- Цвета частиц держим в CONFIG, а не в локалах: так они попадают в систему
-- конфигов MacLib и сохраняются между сессиями.
CONFIG.HitParticleColorA = CONFIG.HitParticleColorA or Color3.fromRGB(88, 165, 255)
CONFIG.HitParticleColorB = CONFIG.HitParticleColorB or Color3.fromRGB(165, 95, 255)
local HIT_WF_TETRA = {
	Vector3.new(1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, -1, 1),
}
local HIT_WF_EDGES = { {1, 2}, {1, 3}, {1, 4}, {2, 3}, {2, 4}, {3, 4} }

local function hitPtLerpColor(t)
	t = math.clamp(t, 0, 1)
	return Color3.new(
		CONFIG.HitParticleColorA.R + (CONFIG.HitParticleColorB.R - CONFIG.HitParticleColorA.R) * t,
		CONFIG.HitParticleColorA.G + (CONFIG.HitParticleColorB.G - CONFIG.HitParticleColorA.G) * t,
		CONFIG.HitParticleColorA.B + (CONFIG.HitParticleColorB.B - CONFIG.HitParticleColorA.B) * t
	)
end

local function wfRotateOffset(off, ang)
	local cf = CFrame.Angles(ang.X, ang.Y, ang.Z)
	return cf:VectorToWorldSpace(off)
end

-- FIX v8: destroy helper — удаляет все Drawing-объекты системы частиц
local function destroyParticleSystem(sys)
	for _, p in ipairs(sys.pts) do
		if p.dot then Bridge.destroyDrawing(p.dot) end
		if p.ring then Bridge.destroyDrawing(p.ring) end
		for _, e in ipairs(p.edges or {}) do
			Bridge.destroyDrawing(e.line)
		end
	end
	for _, e in ipairs(sys.links or {}) do
		Bridge.destroyDrawing(e.line)
	end
end

local function ensureFovCircle()
	if State.fovCircle then return end
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return end
	local c = Drawing.new("Circle")
	c.NumSides    = 64
	c.Thickness   = CONFIG.FovCircleThickness or 1
	c.Filled      = CONFIG.FovCircleFilled == true
	c.Color       = CONFIG.FovCircleColor or Color3.fromRGB(255, 255, 255)
	c.Transparency = CONFIG.FovCircleTransparency or 0.5
	c.Visible     = false
	c.ZIndex      = 10
	State.fovCircle = c
end

local function ensureHitParticleDriver()
	if State.hitParticleDriver then return end
	local RSvc = game:GetService("RunService")
	State.hitParticleDriver = RSvc.Heartbeat:Connect(function(dt)
		local list = State.hitParticleSystems
		if not list or #list == 0 then
			State.hitParticleDriver:Disconnect()
			State.hitParticleDriver = nil
			return
		end
		for i = #list, 1, -1 do
			local sys = list[i]
			-- FIX: убран tickSec throttle — каждый Heartbeat обновляем напрямую
			local step = math.clamp(dt, 0.001, 0.05)
			sys.age = (sys.age or 0) + step
			local age, cam = sys.age, sys.cam
			-- FIX: уничтожаем если age > 110% duration (небольшой буфер для анимации)
			if age >= sys.duration * 1.1 or not cam then
				destroyParticleSystem(sys)
				table.remove(list, i)
				continue
			end
			-- FIX: плавный fadeIn первые 15% жизни + fadeOut последние 25% жизни
			-- Исчезновение: alpha → 0 за 0.275s (при duration=1.1s)
			local fadeInEnd    = sys.duration * 0.15
			local fadeOutStart = sys.duration * 0.75
			local alpha
			if age < fadeInEnd then
				-- Плавное появление: ease-out квадрат (быстро набирает, медленно выходит на 1.0)
				local t = age / math.max(fadeInEnd, 0.001)
				alpha = t * (2 - t)  -- ease-out quad: 0 → 1
			elseif age < fadeOutStart then
				alpha = 1.0
			else
				-- Плавное исчезновение: ease-in квадрат (медленно начинает, быстро уходит в 0)
				local t = (age - fadeOutStart) / math.max(sys.duration - fadeOutStart, 0.001)
				t = math.clamp(t, 0, 1)
				alpha = (1 - t) * (1 - t)  -- ease-in quad: 1 → 0
			end
			local pulseT = (math.sin(age * 3.2) + 1) * 0.5
			local drag = math.clamp(1 - step * 0.35, 0.55, 1)

			if sys.wireframe then
			for _, p in ipairs(sys.pts) do
				p.vel += sys.gravity * step
				p.vel *= drag
				p.pos += p.vel * step
				p.ang += p.angVel * step
				local wfScale = p.scale * (0.85 + 0.15 * math.sin(age * 4 + p.phase))
				local verts = {}
				local allOn = true
				for vi, localOff in ipairs(HIT_WF_TETRA) do
					local worldOff = wfRotateOffset(localOff * wfScale, p.ang)
					local wp = p.pos + worldOff
					local sp, onScreen = cam:WorldToViewportPoint(wp)
					verts[vi] = { sp = sp, on = onScreen and sp.Z > 0.05 }
					if not verts[vi].on then allOn = false end
				end
				local opMin = sys.opMin or 0.08
				local opMax = sys.opMax or 0.55
				local fallMul = p.vel.Y < -2 and math.clamp(1 + p.vel.Y * 0.025, 0.15, 1) or 1
				local baseOp = (opMin + p.z * (opMax - opMin)) * alpha * fallMul
				p.onScreen = allOn
				if allOn then
					p.sx = (verts[1].sp.X + verts[2].sp.X + verts[3].sp.X + verts[4].sp.X) * 0.25
					p.sy = (verts[1].sp.Y + verts[2].sp.Y + verts[3].sp.Y + verts[4].sp.Y) * 0.25
				end
				-- FIX v6: Particles — при невидимой прозрачности ставим Visible=false
				-- Drawing.Line с Visible=true но Transparency=1 всё равно в render pass
				for ei, edge in ipairs(p.edges) do
						local l = edge.line
						local ia, ib = HIT_WF_EDGES[ei][1], HIT_WF_EDGES[ei][2]
						local va, vb = verts[ia], verts[ib]
						local finalOp = baseOp * (0.75 + 0.25 * pulseT)
						if va.on and vb.on and finalOp > 0.015 then
							l.From = Vector2.new(va.sp.X, va.sp.Y)
							l.To = Vector2.new(vb.sp.X, vb.sp.Y)
							l.Thickness = 0.65 + p.z * 0.45
							l.Color = hitPtLerpColor((pulseT + p.phase * 0.2 + ei * 0.04) % 1)
							-- FIX: у Potassium Transparency инвертирован (1=видимо). Ручной
							-- `1 - finalOp` работал наоборот ��� при fadeOut частицы наоборот
							-- становились ярче, а потом резко гасли по Visible=false. Идём
							-- через showDrawing (учитывает DrawingHighTransparencyMeansVisible),
							-- поэтому finalOp плавно ведёт непрозрачность к нулю.
							Bridge.showDrawing(l, finalOp)
						else
							l.Visible = false
						end
					end
			end

			-- FIX v6: links — Visible=false когда alpha практически нулевой
			for _, link in ipairs(sys.links or {}) do
				local pa, pb = sys.pts[link.a], sys.pts[link.b]
				local l = link.line
				if pa and pb and pa.onScreen and pb.onScreen then
					local dx, dy = pa.sx - pb.sx, pa.sy - pb.sy
					local dist = math.sqrt(dx * dx + dy * dy)
					if dist < sys.connectDist then
						local prox = 1 - dist / sys.connectDist
						local linkOp = (sys.opMin or 0.08) * prox * alpha * (sys.wireframe and 0.35 or 0.55)
						if linkOp > 0.015 then
							l.From = Vector2.new(pa.sx, pa.sy)
								l.To = Vector2.new(pb.sx, pb.sy)
								l.Thickness = sys.wireframe and 0.35 or 0.55
								l.Color = hitPtLerpColor(pulseT)
								-- FIX: та же инверсия — идём через showDrawing для плавного fade
								Bridge.showDrawing(l, linkOp)
							else
								l.Visible = false
							end
					else
						l.Visible = false
					end
				else
					l.Visible = false
				end
			end
			elseif sys.ptype == "Sparks" then
				-- Искры: короткий штрих ВДОЛЬ вектора скорости + перпендикулярный
				-- блик на конце. Читается как настоящая вспышка от попадания.
				for _, p in ipairs(sys.pts) do
					p.vel += sys.gravity * step
					p.vel *= drag
					p.pos += p.vel * step
					local spd = p.vel.Magnitude
					local dirv = spd > 0.01 and (p.vel / spd) or Vector3.new(0, 1, 0)
					local tailLen = math.clamp(spd * 0.035, 0.05, 0.9) * (p.size or 1)
					local tail = p.pos - dirv * tailLen
					local spA, onA = cam:WorldToViewportPoint(p.pos)
					local spB, onB = cam:WorldToViewportPoint(tail)
					local opMin = sys.opMin or 0.08
					local opMax = sys.opMax or 0.55
					local fallMul = p.vel.Y < -2 and math.clamp(1 + p.vel.Y * 0.025, 0.15, 1) or 1
					local op = (opMin + p.z * (opMax - opMin)) * alpha * fallMul
					local vis = onA and onB and spA.Z > 0.05 and spB.Z > 0.05 and op > 0.015
					local col = hitPtLerpColor((pulseT + p.phase * 0.15) % 1)
					local e1 = p.edges[1] and p.edges[1].line
					local e2 = p.edges[2] and p.edges[2].line
					if vis then
						if e1 then
							e1.From = Vector2.new(spA.X, spA.Y)
							e1.To   = Vector2.new(spB.X, spB.Y)
							e1.Color = col
							Bridge.showDrawing(e1, op)
						end
						-- перпендикулярный блик на «голове» искры
						if e2 then
							local dx, dy = spA.X - spB.X, spA.Y - spB.Y
							local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
							local nx, ny = -dy / len, dx / len
							local w = math.clamp(len * 0.22, 0.6, 4) * (p.size or 1)
							e2.From = Vector2.new(spA.X - nx * w, spA.Y - ny * w)
							e2.To   = Vector2.new(spA.X + nx * w, spA.Y + ny * w)
							e2.Color = col
							Bridge.showDrawing(e2, op * 0.8)
						end
						p.sx, p.sy, p.onScreen = spA.X, spA.Y, true
					else
						if e1 then e1.Visible = false end
						if e2 then e2.Visible = false end
						p.onScreen = false
					end
				end
			else
				for _, p in ipairs(sys.pts) do
					p.vel += sys.gravity * step
					p.vel *= drag
					p.pos += p.vel * step
					local sp, onScreen = cam:WorldToViewportPoint(p.pos)
					if onScreen and sp.Z > 0.05 then
						local depth = sp.Z
						local r = (0.28 + p.z * 0.62) * (p.size or 1)
						local screenR = math.max(0.45, r * 17 / depth)
						local fallMul = p.vel.Y < -2 and math.clamp(1 + p.vel.Y * 0.025, 0.15, 1) or 1
						local opMin = sys.opMin or 0.08
						local opMax = sys.opMax or 0.55
						local op = (opMin + p.z * (opMax - opMin)) * alpha * fallMul
						-- FIX v6: при op < threshold — скрываем вместо Transparency=1
						if op > 0.015 then
							p.dot.Position = Vector2.new(sp.X, sp.Y)
							p.dot.Radius = screenR * (0.90 + 0.10 * math.sin(age * 3 + p.phase))
							p.dot.Color = hitPtLerpColor((pulseT + p.phase * 0.15) % 1)
							-- FIX: инвертированная прозрачность Potassium — через showDrawing
							Bridge.showDrawing(p.dot, op)
							-- Glow-кольцо вокруг орба (цвет B, чуть больше радиус)
							if p.ring then
								p.ring.Position = p.dot.Position
								p.ring.Radius = screenR * 1.6
								p.ring.Color = CONFIG.HitParticleColorB
								Bridge.showDrawing(p.ring, op * 0.45)
							end
						else
							p.dot.Visible = false
							if p.ring then p.ring.Visible = false end
						end
						p.sx, p.sy, p.onScreen = sp.X, sp.Y, true
					else
						p.dot.Visible = false
						if p.ring then p.ring.Visible = false end
						p.onScreen = false
					end
				end
				for _, link in ipairs(sys.links or {}) do
					local pa, pb = sys.pts[link.a], sys.pts[link.b]
					local l = link.line
					if not pa or not pb or not pa.onScreen or not pb.onScreen then
						l.Visible = false
						continue
					end
					local dx, dy = pa.sx - pb.sx, pa.sy - pb.sy
					local dist = math.sqrt(dx * dx + dy * dy)
					if dist < sys.connectDist then
						local prox = 1 - dist / sys.connectDist
						local opMin = sys.opMin or 0.08
						local opMax = sys.opMax or 0.55
						local lineOp = (opMin + prox * (opMax - opMin) * 0.55) * alpha
						l.From = Vector2.new(pa.sx, pa.sy)
						l.To = Vector2.new(pb.sx, pb.sy)
						l.Color = hitPtLerpColor(pulseT)
						-- FIX: инвертированная прозрачность Potassium — через showDrawing
						Bridge.showDrawing(l, lineOp)
					else
						l.Visible = false
					end
				end
			end
		end
	end)
end

function Bridge.spawnHitParticles3D(hitPos, normal)
	if CONFIG.HitParticles == false or typeof(hitPos) ~= "Vector3" then return end
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return end
	State.hitParticleSystems = State.hitParticleSystems or {}
	local maxSys = CONFIG.HitParticleMaxSystems or 5
	while #State.hitParticleSystems >= maxSys do
		local old = table.remove(State.hitParticleSystems, 1)
		if old then
			for _, p in ipairs(old.pts or {}) do
				if p.dot then Bridge.destroyDrawing(p.dot) end
		if p.ring then Bridge.destroyDrawing(p.ring) end
				for _, e in ipairs(p.edges or {}) do Bridge.destroyDrawing(e.line) end
			end
			for _, e in ipairs(old.links or {}) do Bridge.destroyDrawing(e.line) end
		end
	end
	normal = (typeof(normal) == "Vector3" and normal.Magnitude > 0.01) and normal.Unit or Vector3.new(0, 1, 0)
	do
		local count = math.clamp(CONFIG.HitParticleCount or 40, 8, 48)
		local spdMin = CONFIG.HitParticleSpeedMin or 8
		local spdMax = CONFIG.HitParticleSpeedMax or 22
		local wfScale = CONFIG.HitParticleWireScale or 0.55
		-- Тип частиц: Sparks (искры-штрихи), Orbs (светящиеся шарики),
		-- Wireframe (вращающиеся каркасные тетраэдры). Раньше был только
		-- булев Wireframe → либо каркасы, либо точки.
		local ptype = CONFIG.HitParticleType or "Wireframe"
		if CONFIG.HitParticleWireframe == false and ptype == "Wireframe" then
			ptype = "Orbs"   -- обратная совместимость со старым тумблером
		end
		local useWireframe = (ptype == "Wireframe")
		local up = math.abs(normal.Y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
		local right = normal:Cross(up).Unit
		local fwd = normal:Cross(right).Unit
		local pts = {}
		for i = 1, count do
			local theta = math.random() * math.pi * 2
			local phi = math.acos(math.clamp(1 - math.random() * 1.85, -1, 1))
			local sinPhi = math.sin(phi)
			local dir = (normal * math.cos(phi)
				+ right * (sinPhi * math.cos(theta))
				+ fwd * (sinPhi * math.sin(theta))
				+ Vector3.new((math.random() - 0.5) * 0.35, (math.random() - 0.2) * 0.25, (math.random() - 0.5) * 0.35)).Unit
			local z = math.random()
			local pt = {
				pos = hitPos + dir * (math.random() * 0.12),
				vel = dir * (spdMin + z * (spdMax - spdMin))
					+ Vector3.new((math.random() - 0.5) * 5, math.random() * 4, (math.random() - 0.5) * 5),
				z = z,
				phase = math.random() * math.pi * 2,
			}
			if useWireframe then
				pt.ang = Vector3.new(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
				pt.angVel = Vector3.new((math.random() - 0.5) * 14, (math.random() - 0.5) * 14, (math.random() - 0.5) * 14)
				pt.scale = wfScale * (0.65 + z * 0.55)
				local edges = {}
				for ei = 1, #HIT_WF_EDGES do
					local l = Drawing.new("Line")
					l.Thickness = 0.7
					l.ZIndex = 9
					l.Transparency = 1
					l.Visible = false
					edges[ei] = { line = l }
				end
				pt.edges = edges
			elseif ptype == "Sparks" then
				-- Искра: два коротких штриха, летящих по направлению движения
				local edges = {}
				for ei = 1, 2 do
					local l = Drawing.new("Line")
					l.Thickness = CONFIG.HitParticleSparkThickness or 1.5
					l.ZIndex = 9
					l.Transparency = 1
					l.Visible = false
					edges[ei] = { line = l }
				end
				pt.edges = edges
				pt.spark = true
				pt.size = (0.7 + z * 1.3) * (CONFIG.HitParticleSparkSize or 1)
			else
				-- Orb: заполненный кружок + тусклое кольцо-подсветка
				local dot = Drawing.new("Circle")
				dot.Filled = true
				dot.Thickness = 1
				dot.NumSides = 12
				dot.ZIndex = 9
				dot.Radius = 1
				dot.Transparency = 1
				dot.Visible = false
				pt.dot = dot
				if CONFIG.HitParticleOrbGlow ~= false then
					local ring = Drawing.new("Circle")
					ring.Filled = false
					ring.Thickness = 1.5
					ring.NumSides = 12
					ring.ZIndex = 8
					ring.Radius = 1
					ring.Transparency = 1
					ring.Visible = false
					pt.ring = ring
				end
				pt.size = (0.7 + z * 1.3) * (CONFIG.HitParticleOrbSize or 1)
			end
			pts[i] = pt
		end
		local links = {}
		for i = 1, count do
			for j = i + 1, math.min(i + 3, count) do
				local l = Drawing.new("Line")
				l.Thickness = useWireframe and 0.35 or 0.55
				l.ZIndex = 8
				l.Transparency = 1
				l.Visible = false
				links[#links + 1] = { a = i, b = j, line = l }
			end
		end
		State.hitParticleSystems[#State.hitParticleSystems + 1] = {
			pts = pts,
			links = links,
			wireframe = useWireframe,
			ptype = ptype,
			age = 0,
			acc = 0,
			duration = CONFIG.HitParticleDuration or 1.1,
		_fadeOverlap = 0.06, -- небольшой overlap чтобы Drawing.Visible=false до Remove()
			connectDist = CONFIG.HitParticleConnectDist or 22,
			gravity = Vector3.new(0, CONFIG.HitParticleGravity or -32, 0),
			tickSec = CONFIG.HitParticleTickSec or 0.022,
			opMin = CONFIG.HitParticleOpacityMin or 0.08,
			opMax = CONFIG.HitParticleOpacityMax or 0.55,
			cam = workspace.CurrentCamera,
		}
		ensureHitParticleDriver()
	end
end

function Bridge.onLocalEnemyHit(hitPos, part, normal)
	-- FIX v12: не блокируем если part не определён — hitPos может быть валидным
	if part and type(Bridge.isEnemyHitPart) == "function" and not Bridge.isEnemyHitPart(part) then return end
	local now = os.clock()
	if now - (State.lastHitFxAt or 0) < 0.045 then return end
	State.lastHitFxAt = now
	local pos = typeof(hitPos) == "Vector3" and hitPos or part.Position
	Bridge.playLocalHitSound()
	Bridge.spawnHitParticles3D(pos, normal)
end

function Bridge.tryLocalEnemyHitFx(op, hitPos, part, normal, isLocalFlag, uid)
	if not (CONFIG.HitSound or CONFIG.HitParticles) then return end
	if op == 2 then
		if isLocalFlag ~= true then return end
	elseif op == 1 then
		if type(uid) ~= "string" then return end
		if not Bridge.isMyBulletUid(uid) and Bridge.getPendingBulletShot(uid) == nil then return end
	else
		return
	end
	Bridge.onLocalEnemyHit(hitPos, part, normal)
end

local function bulletEventIsLocalShot(op, args)
	if type(args) ~= "table" then return false end
	if op == 2 then
		return args[7] == true
	end
	if op == 1 then
		local uid = args[1]
		return type(uid) == "string"
			and (Bridge.isMyBulletUid(uid) or Bridge.getPendingBulletShot(uid) ~= nil)
	end
	return false
end

function Bridge.installHitFxListener()
	if State.hitFxConn then return true end
	if not (CONFIG.HitSound or CONFIG.HitParticles) then return false end
	local bulletEvent = RF:FindFirstChild("BulletEvent")
	if not bulletEvent or not bulletEvent:IsA("BindableEvent") then
		return false
	end
	State.hitFxConn = bulletEvent.Event:Connect(function(op, ...)
		if not (CONFIG.HitSound or CONFIG.HitParticles) then return end
		if op ~= 1 and op ~= 2 then return end
		local args = { ... }
		local hitPos, part, normal, isLocalFlag, uid
		if op == 2 then
			hitPos, part, normal = args[2], args[3], args[4]
			isLocalFlag = args[7]
		else
			uid = args[1]
			hitPos, part, normal = args[3], args[4], args[5]
		end
		-- FIX v12: relaxed local-shot check
		-- Сначала строгая проверка, если не прошла — пробуем по isEnemyHitPart + recent shot
		local isLocal = bulletEventIsLocalShot(op, args)
		if not isLocal and op == 1 and part and type(Bridge.isEnemyHitPart) == "function" then
			-- Если попали в enemy part и недавно был наш выстрел — считаем локальным
			local recentUid = type(Bridge.getRecentPendingBulletUid) == "function"
				and Bridge.getRecentPendingBulletUid(0.35)
			if recentUid and Bridge.isEnemyHitPart(part) then
				isLocal = true
				uid = recentUid
			end
		end
		if not isLocal then return end
		Bridge.tryLocalEnemyHitFx(op, hitPos, part, normal, isLocalFlag, uid)
	end)
	log("AIM", "HitFx listener on BulletEvent.Event")
	return true
end

function Bridge.patchNetworkDischargeArgs(args, fromIndex)
	if type(args) ~= "table" or not Bridge.needsServerAimPatch() then return false end
	local route, action = args[fromIndex], args[fromIndex + 1]
	if route ~= "InventoryAction" or action ~= "Discharge" then return false end
	local v138 = args[fromIndex + 2]
	if type(v138) ~= "table" then return false end
	local origin
	for _, entry in pairs(v138) do
		if type(entry) == "table" and type(entry[2]) == "number" then
			origin = Vector3.new(entry[2], entry[3], entry[4])
			break
		end
	end
	Bridge.ensureShotTargetForPatch(origin)
	if typeof(origin) == "Vector3" then
		State.forceCombatAimRefresh = true
		Bridge.prepareCombatShot(origin)
	end
	return Bridge.patchV138ServerAim(v138)
end

function Bridge.classifyAimVisibility(losOrigin, part, aimPoint, model)
	if not part then return 3 end
	local viewOrigin = Bridge.getLocalViewOrigin() or losOrigin
	local pt = aimPoint or part.Position
	if Bridge.hasVisiblePath(viewOrigin, pt, part, false) then
		return 0
	end
	if CONFIG.ResolverLite ~= false and model and model:IsA("Model") then
		local muzzle = Bridge.getAimLosOrigin(losOrigin)
		local expPart = Bridge.resolveResolverLite(muzzle, model, nil, getCamera(), CONFIG.SilentAimFOV)
		if expPart then return 1 end
	end
	return 3
end

function Bridge.applyShotOriginSpoof(originCFrame)
	if typeof(originCFrame) ~= "CFrame" then return originCFrame end
	if not Bridge.shouldSpoofMuzzlePosition() then
		return originCFrame
	end
	local target = State.shotAimTarget
	local aim = State.forceHitPoint or State.aimAimPoint
	if target and target.Parent and typeof(aim) == "Vector3" then
		if type(Bridge.forceSpoofOriginCFrame) == "function" then
			return Bridge.forceSpoofOriginCFrame(originCFrame, target, aim)
		end
	end
	return originCFrame
end

function Bridge.scanGcForNetwork()
	if type(getgc) ~= "function" then return nil end
	local best, bestScore = nil, 0
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "table" then continue end
		if type(rawget(obj, "FireServer")) ~= "function" then continue end
		if type(rawget(obj, "ConnectEvents")) ~= "function" then continue end
		local score = 40
		if type(rawget(obj, "ConnectEvents")) == "function" then score += 8 end
		if score > bestScore then
			best, bestScore = obj, score
		end
	end
	return best
end

function Bridge.resolveNetworkModule(force)
	if not force and Bridge.isFluxNetwork(State.networkModule) then
		return State.networkModule
	end
	if State.networkModule and not Bridge.isFluxNetwork(State.networkModule) then
		State.networkModule = nil
		State.networkModuleSource = nil
	end
	return Bridge.loadNetworkModule(force ~= false)
end

function Bridge.scanAllDischargeClosures()
	if type(getgc) ~= "function" or type(debug) ~= "table" then return {} end
	local getconstants = rawget(debug, "getconstants") or debug.getconstants
	if type(getconstants) ~= "function" then return {} end
	local out = {}
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "function" then continue end
		local ok, consts = pcall(getconstants, obj)
		if not ok or type(consts) ~= "table" then continue end
		local hasRoute, hasAction = false, false
		for _, c in ipairs(consts) do
			if c == "InventoryAction" then hasRoute = true end
			if c == "Discharge" then hasAction = true end
		end
		if hasRoute and hasAction then
			out[#out + 1] = obj
		end
	end
	return out
end

function Bridge.scanGcForFireServerClosure()
	if type(getgc) ~= "function" or type(debug) ~= "table" then return nil end
	local getconstants = rawget(debug, "getconstants") or debug.getconstants
	if type(getconstants) ~= "function" then return nil end
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "function" then continue end
		local ok, consts = pcall(getconstants, obj)
		if not ok or type(consts) ~= "table" then continue end
		local hasRoute, hasAction = false, false
		for _, c in ipairs(consts) do
			if c == "InventoryAction" then hasRoute = true end
			if c == "Discharge" then hasAction = true end
		end
		if hasRoute and hasAction then return obj end
	end
	return nil
end

function Bridge.hookDischargeClosure()
	-- ����тключено: дубли����ует namecall FireServer patch.
	return false
end

function Bridge.hookNetworkMethod(net, methodName, tag)
	if not Bridge.isFluxNetwork(net) or type(rawget(net, methodName)) ~= "function" then
		return false
	end
	if type(hookfunction) ~= "function" then return false end
	local G = brm5Global()
	G.networkHookedKeys = G.networkHookedKeys or {}
	if type(State.networkHookedKeys) ~= "table" then
		State.networkHookedKeys = {}
	end
	local hookKey = tostring(net) .. ":" .. methodName
	if G.networkHookedKeys[hookKey] or State.networkHookedKeys[hookKey] then
		State.networkHookedKeys[hookKey] = true
		return true
	end

	local ok, err = pcall(function()
		local orig = rawget(net, methodName)
		local ref
			local hookFn = function(...)
				if Bridge.needsServerAimPatch() then
				local argc = select("#", ...)
				local args = table.pack(...)
				local from
				for i = 1, math.min(args.n, 5) do
					if args[i] == "InventoryAction" and args[i + 1] == "Discharge" then
						from = i
						break
					end
				end
				if from then
					Bridge.patchNetworkDischargeArgs(args, from)
					return ref(table.unpack(args, 1, argc))
				end
			end
			return ref(...)
		end
		if type(newcclosure) == "function" then
			hookFn = newcclosure(hookFn, "FireServer")
		end
		ref = hookfunction(orig, hookFn)
		State.networkHookedKeys[hookKey] = true
		G.networkHookedKeys[hookKey] = true
		State["network_" .. methodName .. "_ref"] = ref
	end)
	if ok then
		log("AIM", "network Discharge hooked", tag or methodName)
		return true
	end
	if CONFIG.LogV138Patch then
		log("AIM", "network hook failed:", tostring(err))
	end
	return false
end

function Bridge.hookNetworkDischarge()
	if State.networkDischargeHooked then return true end
	local net = Bridge.getNetworkModule and Bridge.getNetworkModule(false)
		or Bridge.resolveNetworkModule(false)
	if not Bridge.isFluxNetwork(net) then
		net = Bridge.getNetworkModule and Bridge.getNetworkModule(true)
			or Bridge.resolveNetworkModule(true)
	end
	if not Bridge.isFluxNetwork(net) then return false end
	-- Flux: Discharge идёт через network:FireServer (table), не RemoteEvent — namecall не видит v138.
	if Bridge.hookNetworkMethod(net, "FireServer", "network") then
		State.networkDischargeHooked = true
		return true
	end
	return false
end

function Bridge.isFluxFireInstance(inst)
	if typeof(inst) ~= "Instance" then return false end
	return inst:IsA("Camera")
		or inst:IsA("RemoteEvent")
		or inst:IsA("UnreliableRemoteEvent")
		or inst:IsA("Player")
end

function Bridge.shouldPatchFireValue(v)
	if typeof(v) == "CFrame" then return "cframe" end
	if typeof(v) == "Vector3" then return "vector" end
	if typeof(v) == "Instance" and v:IsA("BasePart") and v:GetAttribute("ActorUID") then
		return "part"
	end
	if type(v) == "table" then return "table" end
	return nil
end

function Bridge.patchFireTable(t, target, depth, originHint)
	if not Bridge.shouldClientSpoofMuzzlePosition() then return end
	if type(t) ~= "table" or depth > 5 then return end
	local aimPos = State.forceHitPoint or State.aimAimPoint or target.Position
	local origin = originHint
	if typeof(t.OriginCFrame) == "CFrame" then
		t.OriginCFrame = Bridge.retargetOriginCFrame(t.OriginCFrame, target, aimPos)
		origin = t.OriginCFrame.Position
	elseif typeof(t.Origin) == "CFrame" then
		t.Origin = Bridge.retargetOriginCFrame(t.Origin, target, aimPos)
		origin = t.Origin.Position
	end
	if typeof(t.Direction) == "Vector3" and origin then
		local d = aimPos - origin
		if d.Magnitude > 0.01 then
			t.Direction = d.Unit
		end
	end
	if typeof(t.LookVector) == "Vector3" and origin then
		local d = aimPos - origin
		if d.Magnitude > 0.01 then
			t.LookVector = d.Unit
		end
	end
	for _, key in ipairs({ "Hit", "Part", "hitPart", "HitPart" }) do
		local v = rawget(t, key)
		if typeof(v) == "Instance" and v:IsA("BasePart") and v:GetAttribute("ActorUID") then
			rawset(t, key, target)
		end
	end
	for k, v in pairs(t) do
		if Bridge.isFluxFireInstance(v) then continue end
		local kind = Bridge.shouldPatchFireValue(v)
		if kind == "cframe" then
			t[k] = Bridge.retargetOriginCFrame(v, target, aimPos)
		elseif kind == "part" then
			t[k] = target
		elseif kind == "table" then
			Bridge.patchFireTable(v, target, depth + 1, origin)
		end
	end
end

function Bridge.patchFireArgs(args, target)
	if not Bridge.shouldClientSpoofMuzzlePosition() then return end
	local originHint = nil
	for _, a in ipairs(args) do
		if typeof(a) == "CFrame" then
			originHint = a.Position
			break
		end
		if type(a) == "table" and typeof(a.OriginCFrame) == "CFrame" then
			originHint = a.OriginCFrame.Position
			break
		end
	end
	for i, a in ipairs(args) do
		if Bridge.isFluxFireInstance(a) then continue end
		local kind = Bridge.shouldPatchFireValue(a)
		local aimPos = State.forceHitPoint or State.aimAimPoint or target.Position
		if kind == "cframe" then
			args[i] = Bridge.retargetOriginCFrame(a, target, aimPos)
		elseif kind == "part" then
			args[i] = target
		elseif kind == "table" then
			Bridge.patchFireTable(a, target, 0, originHint)
		end
	end
end

function Bridge.resolveShotTarget(originPos)
	if State.shotAimTarget and State.shotAimTarget.Parent then
		return State.shotAimTarget
	end
	if typeof(originPos) == "Vector3" then
		local target = Bridge.getCombatAimTarget(originPos, false)
		if target then
			State.shotAimTarget = target
			State.shotAimTargetTime = os.clock()
		end
		return target
	end
	return nil
end

function Bridge.resolveFirearmInventoryModule()
	if State.firearmModule then return State.firearmModule end
	local mod = select(1, Bridge.resolveLiveGameModule("FirearmInventory"))
	if type(mod) == "table" and type(mod.GetMuzzleCFrame) == "function" then
		return mod
	end
	if type(shared) == "table" and type(shared.import) == "function" then
		local ok, req = pcall(shared.import, "require")
		if ok and type(req) == "function" then
			local ok2, mod = pcall(req, "FirearmInventory")
			if ok2 and type(mod) == "table" and type(mod.GetMuzzleCFrame) == "function" then
				State.firearmModule = mod
				return mod
			end
		end
	end
	local mod = Bridge.importFluxModule("FirearmInventory")
	if type(mod) == "table" then
		State.firearmModule = mod
		return mod
	end
	local now = os.clock()
	if type(getgc) ~= "function" or now - (State.lastHookGcScan or 0) < (State.hookGcCooldown or 4) then
		return nil
	end
	State.lastHookGcScan = now
	for _, obj in ipairs(getGcCached()) do
		if type(obj) == "table"
			and type(rawget(obj, "GetMuzzleCFrame")) == "function"
			and type(rawget(obj, "Discharge")) == "function"
			and type(rawget(obj, "UpdateHUD")) == "function" then
			State.firearmModule = obj
			return obj
		end
	end
	return nil
end

function Bridge.hookFirearmInventory()
	if type(hookfunction) ~= "function" then return false end
	local G = brm5Global()
	if G.firearmMuzzleHooked then
		State.firearmMuzzleHooked = true
		State.firearmDischargeHooked = true
		State.firearmHooked = true
		return true
	end
	local mod = Bridge.resolveFirearmInventoryModule()
	if not mod or type(mod.GetMuzzleCFrame) ~= "function" then return false end
	if State.firearmMuzzleHooked and (State.firearmDischargeHooked or type(mod.Discharge) ~= "function") then
		return true
	end
	local ok = false
	if not State.firearmMuzzleHooked then
		ok = pcall(function()
		local orig = mod.GetMuzzleCFrame
		local ref
		local muzzleHookFn = function(self, ...)
			local cf, hit, ray = ref(self, ...)
			if State.inGetMuzzleHook then
				return cf, hit, ray
			end
			if (CONFIG.SilentAim or mpActive())
				and typeof(cf) == "CFrame" then
				State.inGetMuzzleHook = true
				State.inShotPrep = true
				local okPrep, prepErr = pcall(function()
					local now = os.clock()
					local stale = not State.shotAimTarget or not State.shotAimTarget.Parent
						or now - (State.shotAimTargetTime or 0) > 0.15
					if stale and now - (State.lastMuzzlePrep or 0) >= 0.07 then
						State.lastMuzzlePrep = now
						if type(Bridge.prepareCombatShotOnce) == "function" then
							Bridge.prepareCombatShotOnce(cf.Position)
						else
							Bridge.prepareCombatShot(cf.Position)
						end
					end
					local target = State.shotAimTarget
					if target and target.Parent then
						local aimPt = State.forceHitPoint or State.aimAimPoint
						if typeof(aimPt) == "Vector3" and Bridge.shouldRetargetClientMuzzle() then
							cf = CFrame.lookAt(cf.Position, aimPt)
						end
					else
						State.combatMuzzleCf = nil
						State.spoofedMuzzlePos = nil
					end
				end)
				State.inShotPrep = false
				State.inGetMuzzleHook = false
				if not okPrep then
					log("AIM", "GetMuzzleCFrame prep error: " .. tostring(prepErr))
				end
			end
			return cf, hit, ray
		end
		if type(newcclosure) == "function" then
			muzzleHookFn = newcclosure(muzzleHookFn, "GetMuzzleCFrame")
		end
		ref = hookfunction(orig, muzzleHookFn)
	end)
		if ok then
			State.firearmMuzzleHooked = true
			State.firearmHooked = true
			G.firearmMuzzleHooked = true
			log("AIM", "FirearmInventory.GetMuzzleCFrame hooked")
		end
	end
	if type(mod.Discharge) == "function" and not State.firearmDischargeHooked then
		-- FirearmInventory.Discharge не хукаем: ломает _discharge → Discharge цепочку (C stack overflow).
		-- v138 патчится через namecall FireServer + BulletService.Discharge.
		State.firearmDischargeHooked = true
		G.firearmDischargeHooked = true
	end
	return State.firearmMuzzleHooked == true
end

function Bridge.getGameShared()
	if type(shared) == "table" and type(shared.import) == "function" then
		return shared, "executor.shared"
	end
	if type(getrenv) == "function" then
		local ok, renv = pcall(getrenv)
		if ok and type(renv) == "table" and type(renv.shared) == "table" then
			if type(renv.shared.import) == "function" then
				return renv.shared, "getrenv.shared"
			end
		end
	end
	return nil, nil
end

function Bridge.isAliveModuleScript(inst)
	return typeof(inst) == "Instance" and inst:IsA("ModuleScript") and inst.Parent ~= nil
end

function Bridge.findLoadedModuleScript(name)
	if type(getloadedmodules) ~= "function" then return nil end
	local best, bestScore = nil, -1
	for _, inst in ipairs(getloadedmodules()) do
		if inst:IsA("ModuleScript") and inst.Name == name then
			local fn = inst:GetFullName()
			local score = 0
			if fn:find("Flux", 1, true) then score += 10 end
			if fn:find("client", 1, true) then score += 6 end
			if fn:find("Shared", 1, true) then score += 4 end
			if fn:find("Packages", 1, true) then score += 2 end
			if score > bestScore then
				best, bestScore = inst, score
			end
		end
	end
	return best
end

function Bridge.findRequireRegistry()
	local gshared = Bridge.getGameShared()
	if gshared then
		local ok, req = pcall(gshared.import, "require")
		if ok and type(req) == "table" then
			local mods = rawget(req, "_modules") or req._modules
			if type(mods) == "table" then
				return req, mods, "shared.import(require)"
			end
		end
	end
	local inst = Bridge.findLoadedModuleScript("require")
	if inst then
		local ok2, req2 = pcall(require, inst)
		if ok2 and type(req2) == "table" then
			local mods2 = rawget(req2, "_modules") or req2._modules
			if type(mods2) == "table" then
				return req2, mods2, "loaded require"
			end
		end
	end
	if type(getgc) == "function" then
		for _, obj in ipairs(getGcCached()) do
			if type(obj) ~= "table" then continue end
			local mods3 = rawget(obj, "_modules")
			if type(mods3) ~= "table" then continue end
			local netInst = mods3.network or mods3.Network
			if typeof(netInst) == "Instance" and netInst:IsA("ModuleScript") then
				return obj, mods3, "getgc._modules"
			end
		end
	end
	return nil, nil, nil
end

function Bridge.scanGcForFirearmClass()
	if type(getgc) ~= "function" then return nil end
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "table" then continue end
		if type(rawget(obj, "GetMuzzleCFrame")) == "function"
			and type(rawget(obj, "Discharge")) == "function"
			and type(rawget(obj, "_discharge")) == "function" then
			return obj
		end
	end
	return nil
end

function Bridge.resolveLiveGameModule(name)
	if name == "network" and Bridge.isFluxNetwork(State.networkModule) then
		return State.networkModule, State.networkModuleSource or "cache"
	end
	if name == "network" and State.networkModule and not Bridge.isFluxNetwork(State.networkModule) then
		State.networkModule = nil
		State.networkModuleSource = nil
	end

	local gshared, sharedSrc = Bridge.getGameShared()
	if gshared then
		local ok, mod = pcall(gshared.import, name)
		if ok and mod ~= nil then
			if name == "network" and Bridge.isFluxNetwork(mod) then
				State.networkModule = mod
				State.networkModuleSource = sharedSrc
				return mod, sharedSrc
			elseif name ~= "network" then
				return mod, sharedSrc
			end
		end
		local ok2, req = pcall(gshared.import, "require")
		if ok2 and req ~= nil then
			local ok3, mod2 = pcall(function() return req(name) end)
			if ok3 and mod2 ~= nil then
				if name == "network" and Bridge.isFluxNetwork(mod2) then
					State.networkModule = mod2
					State.networkModuleSource = sharedSrc .. "→require"
					return mod2, sharedSrc .. "→require"
				elseif name ~= "network" then
					return mod2, sharedSrc .. "→require"
				end
			end
		end
	end

	if type(shared) == "table" and type(shared.import) == "function" and name == "network" then
		local ok, mod = pcall(shared.import, "network")
		if ok and Bridge.isFluxNetwork(mod) then
			State.networkModule = mod
			State.networkModuleSource = "shared.import"
			return mod, "shared.import"
		end
	end

	if name == "network" then
		local gcNet = Bridge.scanGcForNetwork()
		if gcNet then
			State.networkModule = gcNet
			State.networkModuleSource = "getgc.flux"
			return gcNet, "getgc.flux"
		end
	elseif name == "FirearmInventory" and State.firearmModule then
		return State.firearmModule, "cache"
	elseif name == "FirearmInventory" then
		local gcFi = Bridge.scanGcForFirearmClass()
		if gcFi then
			State.firearmModule = gcFi
			return gcFi, "getgc.table"
		end
	end

	local _, mods = Bridge.findRequireRegistry()
	local regInst = mods and mods[name]
	if Bridge.isAliveModuleScript(regInst) then
		local ok4, mod3 = pcall(require, regInst)
		if ok4 and mod3 ~= nil then
			if name == "network" and Bridge.isFluxNetwork(mod3) then
				State.networkModule = mod3
				State.networkModuleSource = "registry alive"
				return mod3, "registry alive"
			elseif name ~= "network" then
				return mod3, "registry alive"
			end
		end
	end

	local loaded = Bridge.findLoadedModuleScript(name)
	if loaded then
		local ok5, mod4 = pcall(require, loaded)
		if ok5 and mod4 ~= nil then
			if name == "network" and Bridge.isFluxNetwork(mod4) then
				State.networkModule = mod4
				State.networkModuleSource = loaded:GetFullName()
				return mod4, loaded:GetFullName()
			elseif name ~= "network" then
				return mod4, loaded:GetFullName()
			end
		end
	end

	return nil, nil
end

function Bridge.loadNetworkModule(force)
	if State.networkModule and not Bridge.isFluxNetwork(State.networkModule) then
		State.networkModule = nil
		State.networkModuleSource = nil
	end
	if not force and Bridge.isFluxNetwork(State.networkModule) then
		return State.networkModule
	end
	local mod, src = Bridge.resolveLiveGameModule("network")
	if Bridge.isFluxNetwork(mod) then
		State.networkModule = mod
		State.networkModuleSource = src
		return mod
	end
	return nil
end

function Bridge.resolveShotTargetForPatch(originHint)
	local target = State.shotAimTarget
	if target and target.Parent and os.clock() - (State.shotAimTargetTime or 0) <= 0.5 then
		return target
	end
	local origin = originHint
	if typeof(origin) ~= "Vector3" then
		local cam = getCamera()
		origin = cam and cam.CFrame.Position
	end
	if typeof(origin) == "Vector3" then
		target = Bridge.getCombatAimTarget(origin, true)
		if target then
			State.shotAimTarget = target
			State.shotAimTargetTime = os.clock()
		end
	end
	return target
end

function Bridge.getFluxClientFolder()
	local flux = RF:FindFirstChild("Flux") or RS:FindFirstChild("Flux")
	if not flux then return nil end
	return flux:FindFirstChild("client") or flux:FindFirstChild("Client")
end


function Bridge.importFluxModule(name)
	if type(name) ~= "string" or name == "" then return nil end
	if type(shared) == "table" and type(shared.import) == "function" then
		local ok, mod = pcall(shared.import, name)
		if ok and mod ~= nil then return mod, "shared.import" end
		local ok2, req = pcall(shared.import, "require")
		if ok2 and type(req) == "function" then
			local ok3, mod2 = pcall(req, name)
			if ok3 and mod2 ~= nil then return mod2, "require" end
		end
	end
	local client = Bridge.getFluxClientFolder()
	local inst = client and client:FindFirstChild(name)
	if inst and inst:IsA("ModuleScript") then
		local ok4, mod3 = pcall(require, inst)
		if ok4 and mod3 ~= nil then return mod3, "Flux/client" end
	end
	return nil
end





function Bridge.refreshServerRemotes()
	if type(State.serverRemotes) ~= "table" then
		State.serverRemotes = {}
	end
	local events = RS:FindFirstChild("Events")
	if not events then return 0 end
	local count = 0
	for _, child in ipairs(events:GetChildren()) do
		if child:IsA("RemoteEvent") or child:IsA("UnreliableRemoteEvent") then
			if not State.serverRemotes[child] then
				count += 1
			end
			State.serverRemotes[child] = child.ClassName
		end
	end
	State.unreliableRemote = events:FindFirstChild("UnreliableRemoteEvent")
	State.mainRemoteEvent = events:FindFirstChild("RemoteEvent")
	if State.mainRemoteEvent and not State.serverRemotes[State.mainRemoteEvent] then
		State.serverRemotes[State.mainRemoteEvent] = State.mainRemoteEvent.ClassName
		count += 1
	end
	return count
end

function Bridge.isServerRemote(inst)
	return type(State.serverRemotes) == "table" and State.serverRemotes[inst] ~= nil
end

function Bridge.combatAimActive()
	if not (CONFIG.SilentAim or mpActive() or Bridge.shouldForceClientHit()) then
		return false
	end
	local now = os.clock()
	if State._combatAimCacheT and now - State._combatAimCacheT < 0.05 then
		return State._combatAimCache == true
	end
	local ctx = Bridge.peekWeaponContext(1.5)
	if not ctx and Bridge.getAimWeaponContext then
		ctx = Bridge.getAimWeaponContext(false)
	end
	if not ctx then
		ctx = Bridge.peekWeaponContext()
	end
	local active = Bridge.isFirearmAimContext and Bridge.isFirearmAimContext(ctx)
		or (ctx and ctx.tune ~= nil and ctx.isMelee ~= true)
	State._combatAimCache = active
	State._combatAimCacheT = now
	return active
end

function Bridge.ensureAimViz()
	if State.aimViz and State.aimViz.crossH then return State.aimViz end
	if State.aimViz then
		local av = State.aimViz
		for _, key in ipairs({ "line", "label", "dot", "crossH", "crossV" }) do
			Bridge.destroyDrawing(av[key])
			av[key] = nil
		end
		Bridge.destroyDrawingList(av.reticleLines)
		Bridge.destroyDrawingList(av.boxLines)
		State.aimViz = nil
	end
	if not Drawing then return nil end
	State.aimViz = {
		crossH = Drawing.new("Line"),
		crossV = Drawing.new("Line"),
		reticleLines = {},
	}
	local viz = State.aimViz
	viz.crossH.Thickness = 1.4
	viz.crossH.ZIndex = 45
	viz.crossV.Thickness = 1.4
	viz.crossV.ZIndex = 45
	for i = 1, 20 do
		local ln = Drawing.new("Line")
		ln.Thickness = 1.2
		ln.ZIndex = 45
		ln.Visible = false
		viz.reticleLines[i] = ln
	end
	Bridge.showDrawing(viz.crossH, 1)
	Bridge.showDrawing(viz.crossV, 1)
	return viz
end

local AIM_VISUAL_STYLES = { "Default", "DefaultV2", "CrossGap", "Diamond", "Swastika" }

function Bridge.cycleAimVisualStyle()
	local cur = CONFIG.AimVisualStyle or "Default"
	local idx = table.find(AIM_VISUAL_STYLES, cur) or 1
	idx = (idx % #AIM_VISUAL_STYLES) + 1
	CONFIG.AimVisualStyle = AIM_VISUAL_STYLES[idx]
	return CONFIG.AimVisualStyle
end

local function aimRgbColor(now, hueOffset)
	local h = ((now or os.clock()) * 0.38 + (hueOffset or 0)) % 1
	return Color3.fromHSV(h, 0.92, 1)
end

local function hideReticleLines(lines, fromIdx)
	for i = fromIdx or 1, #lines do
		if lines[i] then lines[i].Visible = false end
	end
end

local function drawAimReticle(viz, cx, cy, color, alpha, now)
	local style = CONFIG.AimVisualStyle or "Default"
	now = now or os.clock()
	local lines = viz.reticleLines or {}
	local sc = CONFIG.AimVisualScale or 1
	local gap, arm = 5 * sc, 9 * sc

	if style == "Default" then
		viz.crossH.From = Vector2.new(cx - arm, cy)
		viz.crossH.To = Vector2.new(cx + arm, cy)
		viz.crossH.Color = color
		Bridge.showDrawing(viz.crossH, alpha)
		viz.crossV.From = Vector2.new(cx, cy - arm)
		viz.crossV.To = Vector2.new(cx, cy + arm)
		viz.crossV.Color = color
		Bridge.showDrawing(viz.crossV, alpha)
		hideReticleLines(lines)
		return
	end

	viz.crossH.Visible = false
	viz.crossV.Visible = false

	if style == "CrossGap" then
		lines[1].From = Vector2.new(cx - arm, cy); lines[1].To = Vector2.new(cx - gap, cy)
		lines[2].From = Vector2.new(cx + gap, cy); lines[2].To = Vector2.new(cx + arm, cy)
		lines[3].From = Vector2.new(cx, cy - arm); lines[3].To = Vector2.new(cx, cy - gap)
		lines[4].From = Vector2.new(cx, cy + gap); lines[4].To = Vector2.new(cx, cy + arm)
		for i = 1, 4 do
			lines[i].Color = color
			lines[i].Thickness = 1.3
			Bridge.showDrawing(lines[i], alpha)
		end
		hideReticleLines(lines, 5)
		return
	end

	if style == "DefaultV2" then
		local spin = now * 2.8
		for i = 0, 3 do
			local a = spin + i * (math.pi * 0.5)
			local cosA, sinA = math.cos(a), math.sin(a)
			local ln = lines[i + 1]
			ln.From = Vector2.new(cx + cosA * gap, cy + sinA * gap)
			ln.To = Vector2.new(cx + cosA * (gap + arm), cy + sinA * (gap + arm))
			ln.Color = color
			ln.Thickness = 1.35
			Bridge.showDrawing(ln, alpha)
		end
		hideReticleLines(lines, 5)
		return
	end

	if style == "Swastika" then
		local spin = now * 2.8
		local gapS, armLen, hookLen = 3.5 * sc, 7.5 * sc, 6.5 * sc
		local useRgb = CONFIG.SwastikaRGB == true
		local rgbColor = useRgb and aimRgbColor(now, spin * 0.04) or color
		local li = 1
		for armIdx = 0, 3 do
			local ang = spin + armIdx * (math.pi * 0.5)
			local cosA, sinA = math.cos(ang), math.sin(ang)
			local perpX, perpY = sinA, -cosA
			local x0 = cx + cosA * gapS
			local y0 = cy + sinA * gapS
			local x1 = cx + cosA * (gapS + armLen)
			local y1 = cy + sinA * (gapS + armLen)
			local x2 = x1 + perpX * hookLen
			local y2 = y1 + perpY * hookLen
			lines[li].From = Vector2.new(x0, y0)
			lines[li].To = Vector2.new(x1, y1)
			lines[li].Color = rgbColor
			lines[li].Thickness = 1.45
			Bridge.showDrawing(lines[li], alpha * 0.98)
			li += 1
			lines[li].From = Vector2.new(x1, y1)
			lines[li].To = Vector2.new(x2, y2)
			lines[li].Color = rgbColor
			lines[li].Thickness = 1.45
			Bridge.showDrawing(lines[li], alpha)
			li += 1
		end
		hideReticleLines(lines, li)
		return
	end

	if style == "Diamond" then
		local pulse = 0.5 + 0.5 * math.sin(now * 5.8)
		local breathe = (6.5 + pulse * 3.5) * sc
		local outerSpin = now * 1.6
		local innerSpin = -now * 3.4
		local accentSpin = now * 4.2

		for i = 0, 5 do
			local a1 = outerSpin + i * (math.pi / 3)
			local a2 = outerSpin + (i + 1) * (math.pi / 3)
			local r1 = breathe * (0.92 + 0.08 * math.sin(now * 7 + i))
			local ln = lines[i + 1]
			ln.From = Vector2.new(cx + math.cos(a1) * r1, cy + math.sin(a1) * r1)
			ln.To = Vector2.new(cx + math.cos(a2) * r1, cy + math.sin(a2) * r1)
			ln.Thickness = 1.15 + pulse * 0.35
			ln.Color = color
			Bridge.showDrawing(ln, alpha * (0.82 + pulse * 0.18))
		end

		for i = 0, 3 do
			local a = innerSpin + i * (math.pi * 0.5) + math.pi * 0.25
			local cosA, sinA = math.cos(a), math.sin(a)
			local innerGap = 2.5 + pulse * 1.2
			local innerArm = 5.5 + pulse * 1.8
			local ln = lines[7 + i]
			ln.From = Vector2.new(cx + cosA * innerGap, cy + sinA * innerGap)
			ln.To = Vector2.new(cx + cosA * (innerGap + innerArm), cy + sinA * (innerGap + innerArm))
			ln.Thickness = 1.5
			ln.Color = color
			Bridge.showDrawing(ln, alpha)
		end

		for i = 0, 5 do
			local a = accentSpin + i * (math.pi / 3)
			local tipR = breathe * 1.08
			local tickR = tipR + 2.2 + pulse * 1.5
			local ln = lines[11 + i]
			ln.From = Vector2.new(cx + math.cos(a) * tipR, cy + math.sin(a) * tipR)
			ln.To = Vector2.new(cx + math.cos(a) * tickR, cy + math.sin(a) * tickR)
			ln.Thickness = 0.9
			ln.Color = color
			Bridge.showDrawing(ln, alpha * 0.55 * pulse)
		end
		hideReticleLines(lines, 17)
	end
end

function Bridge.hideAimViz(reason, detail)
	Bridge.logVizHide("AIM", reason or "manual", detail)
	local viz = State.aimViz
	if not viz then return end
	pcall(function()
		if viz.crossH then viz.crossH.Visible = false end
		if viz.crossV then viz.crossV.Visible = false end
		if viz.dot then viz.dot.Visible = false end
		if viz.line then viz.line.Visible = false end
		if viz.label then viz.label.Visible = false end
		if viz.ring then viz.ring.Visible = false end
		if viz.reticleLines then
			for _, l in ipairs(viz.reticleLines) do l.Visible = false end
		end
		if viz.muzzleLine then viz.muzzleLine.Visible = false end
		if viz.serverLine then viz.serverLine.Visible = false end
		if viz.clientLine then viz.clientLine.Visible = false end
		if viz.peekLine then viz.peekLine.Visible = false end
		if viz.debugText then viz.debugText.Visible = false end
		if viz.btCurrent then viz.btCurrent.Visible = false end
		if viz.btPast then viz.btPast.Visible = false end
		if viz.btLine then viz.btLine.Visible = false end
		if viz.btText then viz.btText.Visible = false end
		if viz.boxLines then
			for _, l in ipairs(viz.boxLines) do l.Visible = false end
		end
	end)
end

function Bridge.getCachedSilentAimTarget(originForLos, force)
	if force then
		return Bridge.getCombatAimTarget(originForLos, true)
	end
	return Bridge.getCombatAimTarget(originForLos, false)
end

function Bridge.getLocalMuzzleCFrame()
	-- Не вызываем handler:GetMuzzleCFrame: при активном SA-хуке это рекурсия → stack overflow.
	resolveLocalClient(false)
	local client = State.localClient
	local actor = client and Bridge.getActorTable(client)
	if not actor then return nil end

	-- FIX v5: Muzzle в Third Person (Focused=false)
	-- В TP ViewModel.Muzzle содержит FP-позицию (неправильную), нужно брать CFrame камеры
	-- Точнее: SA направляет выстрел через цель, поэтому достаточно корректной origin точки.
	-- В TP наилучший origin = позиция персонажа на уровне груди + направление камеры.
	local focused = rawget(actor, "Focused")
	if focused == false then
		-- Third Person: origin = HumanoidRootPart (грудь), direction = Camera.LookVector
		local cam = getCamera()
		if not cam then return nil end
		local vm = tableField(actor, "ViewModel")
		-- Попытка 1: WorldMuzzle attachment в ViewModel (иногда работает в TP)
		if type(vm) == "table" then
			local worldMuzzle = tableField(vm, "WorldMuzzle")
			if typeof(worldMuzzle) == "Instance" and worldMuzzle:IsA("Attachment")
				and worldMuzzle.Parent and worldMuzzle.Parent.Parent then
				return worldMuzzle.WorldCFrame
			end
		end
		-- Попытка 2: Character HRP + камерное направление (стандартный TP origin)
		local charActor = rawget(actor, "Character")
		if typeof(charActor) == "Instance" and charActor:IsA("Model") then
			local hrp = charActor:FindFirstChild("HumanoidRootPart")
				or charActor:FindFirstChild("UpperTorso")
			if hrp and hrp:IsA("BasePart") then
				-- Поднимаем на ~0.5 studs (уровень рук/мушки при прицеливании)
				local pos = hrp.Position + Vector3.new(0, 0.5, 0)
				local lookDir = cam.CFrame.LookVector
				return CFrame.new(pos, pos + lookDir)
			end
		end
		-- Fallback: Camera CFrame как прежде
		return cam.CFrame
	end

	return Bridge.getFireOriginCFrame(actor)
end

function Bridge.updateAimVisuals()
	if not CONFIG.AimVisuals or not Drawing then
		Bridge.hideAimViz("no_aimvisuals_or_no_Drawing")
		return
	end
	if State._combatAimCache ~= true and not Bridge.combatAimActive() then
		Bridge.hideAimViz("combat_inactive")
		return
	end

	local now = os.clock()
	if now - (State.lastAimVizDraw or 0) < (CONFIG.AimVisualDrawInterval or 0.04) then
		return
	end
	State.lastAimVizDraw = now

	local cam = getCamera()
	if not cam then
		Bridge.hideAimViz("no_camera")
		return
	end

	local maxAngle = CONFIG.SilentAimFOV or 15

	local refreshIv = CONFIG.AimVisualInterval or 0.08
	if now - (State.lastAimVizTargetRefresh or 0) >= refreshIv then
		State.lastAimVizTargetRefresh = now
		Bridge.refreshAimTarget(Bridge.getAimLosOrigin(), false)
	end
	if (not State.aimTargetPart or not State.aimTargetPart.Parent)
		and now - (State.lastAimVizForceRefresh or 0) >= 0.45 then
		State.lastAimVizForceRefresh = now
		Bridge.refreshAimTarget(Bridge.getAimLosOrigin(), true)
	end

	local target = State.aimTargetPart
	if not target or not target.Parent then
		Bridge.hideAimViz("no_target")
		return
	end
	if (CONFIG.LiteMultiPoint) and not State.mpShotReady then
		Bridge.hideAimViz("mp_no_shot")
		return
	end

	local muzzleCf = Bridge.getLocalMuzzleCFrame()
	local muzzlePos = (muzzleCf and typeof(muzzleCf.Position) == "Vector3") and muzzleCf.Position
		or Bridge.getAimLosOrigin()
	if typeof(muzzlePos) ~= "Vector3" then
		muzzlePos = cam.CFrame.Position
	end

	-- Един��я точка: viz всегда показывает predicted aim (если Prediction включён).
	local head = Bridge.getHeadPart(target.Parent, target) or target
	local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or nil
	local aimWorld = Bridge.resolveUnifiedAimPoint(head, muzzlePos, ctx, State.aimTargetUid, target)
	if typeof(aimWorld) ~= "Vector3" then
		aimWorld = State.aimAimPoint or State.forceHitPoint
	end
	if typeof(aimWorld) ~= "Vector3" then
		Bridge.hideAimViz("no_aim_point")
		return
	end
	State.aimAimPoint = aimWorld
	State.forceHitPoint = aimWorld

	if not Bridge.isAimTargetInFov(target, aimWorld, cam, maxAngle) then
		Bridge.hideAimViz("fov")
		return
	end

	local viz = Bridge.ensureAimViz()
	if not viz then return end

	local function ensureLine(key, thickness, zIndex)
		if not viz[key] then
			viz[key] = Drawing.new("Line")
			viz[key].Thickness = thickness
			viz[key].ZIndex = zIndex
		end
		return viz[key]
	end

	local function ensureText(key)
		if not viz[key] then
			viz[key] = Drawing.new("Text")
			viz[key].Size = 13
			viz[key].Outline = true
			viz[key].Center = false
			viz[key].ZIndex = 47
		end
		return viz[key]
	end

	local function drawSeg(line, fromWorld, toWorld, color, alpha)
		local sp1, on1 = cam:WorldToViewportPoint(fromWorld)
		local sp2, on2 = cam:WorldToViewportPoint(toWorld)
		if (on1 or on2) and sp1.Z > 0.01 and sp2.Z > 0.01 then
			line.From = Vector2.new(sp1.X, sp1.Y)
			line.To = Vector2.new(sp2.X, sp2.Y)
			line.Color = color
			Bridge.showDrawing(line, alpha)
			return true
		end
		line.Visible = false
		return false
	end

	-- Прицельный маркер на точке aim
	local sp, onScreen = cam:WorldToViewportPoint(aimWorld)
	if not onScreen or sp.Z < 0.01 then
		Bridge.hideAimViz("off_screen")
		return
	end

	local cx, cy = sp.X, sp.Y
	local tier = State.lastAimVisTier or 0
	-- Используем CONFIG.AimVisualColor если задан, иначе tier-цвет
	local tierColor = CONFIG.AimVisualColor or (
		tier == 0 and Color3.fromRGB(120, 255, 120)
		or (tier == 1 and Color3.fromRGB(255, 220, 80)
		or (tier == 3 and Color3.fromRGB(120, 180, 255) or Color3.fromRGB(255, 90, 90)))
	)
	local reticleAlpha = 0.95 * (1 - (CONFIG.AimVisualTransparency or 0))

	-- Backtrack удалён v4 — скрываем bt-drawings если есть
	if viz.btCurrent then viz.btCurrent.Visible = false end
	if viz.btPast then viz.btPast.Visible = false end
	if viz.btLine then viz.btLine.Visible = false end
	if viz.btText then viz.btText.Visible = false end

	drawAimReticle(viz, cx, cy, tierColor, reticleAlpha, now)

	-- Клиентская линия: muzzle → aim (predict). Цвет/толщина/прозрачность
	-- настраиваются — раньше были захардкожены и найти их было негде.
	if CONFIG.MuzzleVisual then
		drawSeg(
			ensureLine("muzzleLine", CONFIG.MuzzleLineThickness or 2.0, 44),
			muzzlePos, aimWorld,
			CONFIG.MuzzleLineColor or Color3.fromRGB(80, 220, 255),
			1 - (CONFIG.MuzzleLineTransparency or 0.15)
		)
		if Bridge.shouldClientSpoofMuzzlePosition() then
			local spoof, serverAim = Bridge.previewServerWallBang(muzzlePos, aimWorld, target)
			if typeof(spoof) == "Vector3" and typeof(serverAim) == "Vector3"
				and (spoof - muzzlePos).Magnitude > 0.15 then
				drawSeg(
					ensureLine("peekLine", 1.4, 43),
					muzzlePos, spoof,
					Color3.fromRGB(255, 200, 60), 0.7
				)
				drawSeg(
					ensureLine("clientLine", 2.2, 45),
					spoof, serverAim,
					Color3.fromRGB(120, 255, 180), 0.8
				)
			else
				if viz.peekLine then viz.peekLine.Visible = false end
				if viz.clientLine then viz.clientLine.Visible = false end
			end
		elseif viz.peekLine then
			viz.peekLine.Visible = false
			if viz.clientLine then viz.clientLine.Visible = false end
		end
	elseif viz.muzzleLine then
		viz.muzzleLine.Visible = false
		if viz.peekLine then viz.peekLine.Visible = false end
		if viz.clientLine then viz.clientLine.Visible = false end
	end

	-- v138 wallbang preview (красная линия spoof muzzle → aim)
	local showServer = CONFIG.ServerAimDebug == true
	if showServer then
		local spoof, serverAim, wbOk = Bridge.previewServerWallBang(muzzlePos, aimWorld, target)
		if typeof(spoof) == "Vector3" and typeof(serverAim) == "Vector3" then
			drawSeg(
				ensureLine("serverLine", 2.4, 46),
				spoof, serverAim,
				wbOk and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 140, 60),
				wbOk and 0.92 or 0.55
			)
			if (spoof - muzzlePos).Magnitude > 0.25 then
				drawSeg(
					ensureLine("peekLine", 1.3, 42),
					muzzlePos, spoof,
					Color3.fromRGB(255, 200, 60), 0.65
				)
			elseif viz.peekLine then
				viz.peekLine.Visible = false
			end
		elseif viz.serverLine then
			viz.serverLine.Visible = false
			if viz.peekLine then viz.peekLine.Visible = false end
		end
	else
		if viz.serverLine then viz.serverLine.Visible = false end
		if not CONFIG.MuzzleVisual and viz.peekLine then viz.peekLine.Visible = false end
	end

	-- Статус-лейбл
	local label = ensureText("debugText")
	local lines = {}
	lines[#lines + 1] = State.aimTargetLabel or target.Name
	local mpMode = Bridge.getMultiPointMode()
	if mpMode then
		local tierStr = tier == 0 and "LOS" or (tier == 1 and "PEEK" or "BLOCK")
		lines[#lines + 1] = "MP:" .. mpMode .. " " .. tierStr
		if State.vizWallBangOk then
			local off = typeof(State.vizSpoofMuzzle) == "Vector3"
				and (State.vizSpoofMuzzle - muzzlePos).Magnitude or 0
			if off > 0.2 then
				lines[#lines + 1] = string.format("v138 spoof %.1f", off)
			else
				lines[#lines + 1] = "v138 direct"
			end
		else
			lines[#lines + 1] = "v138 no path"
		end
		if State.resolverAimBone and State.resolverAimBone.Parent then
			lines[#lines + 1] = "bone:" .. State.resolverAimBone.Name
		end
	else
		lines[#lines + 1] = tier == 0 and "visible" or "blocked"
	end
	local patch = State.lastV138Patch
	if patch and now - (patch.t or 0) < 1.0 then
		lines[#lines + 1] = patch.ok and "shot:patched" or "shot:fail"
	end
	label.Text = table.concat(lines, " | ")
	local spM, onM = cam:WorldToViewportPoint(muzzlePos)
	if onM and spM.Z > 0.01 then
		label.Position = Vector2.new(spM.X + 10, spM.Y - 32)
		label.Color = tierColor
		Bridge.setDrawingAlpha(label, 0.95)
		label.Visible = true
	else
		label.Visible = false
	end
end

function Bridge.isActorHitPart(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("BasePart") then return false end
	if inst:GetAttribute("ActorUID") then return true end
	local n = inst.Name
	return n == "Head" or n == "UpperTorso" or n == "LowerTorso"
		or n == "LeftUpperArm" or n == "RightUpperArm"
end

function Bridge.silentRetargetCFrame(originCFrame)
	if typeof(originCFrame) ~= "CFrame" then return originCFrame end
	if CONFIG.SilentAim or mpActive() then
		local _, aimCf = Bridge.prepareSilentAimShot(originCFrame)
		if typeof(aimCf) == "CFrame" then return aimCf end
	end
	return originCFrame
end

function Bridge.tryAimPatch(originCFrame, payload, isLocalShot)
	if not CONFIG.SilentAim and not mpActive() then
		return originCFrame, false
	end
	if isLocalShot == false then return originCFrame, false end
	if payload and payload._brm5AimPatched then return originCFrame, false end

	local originPos = typeof(originCFrame) == "CFrame" and originCFrame.Position or nil
	local target = State.shotAimTarget
	if not target or not target.Parent then
		target = Bridge.getCombatAimTarget(originPos, false)
		if target then State.shotAimTarget = target end
	end
	if not target then return originCFrame, false end

	if Bridge.needsServerAimPatch() then
		Bridge.prepareServerAimShot(originPos, target)
	end

	local newCf = originCFrame
	if Bridge.shouldRetargetClientMuzzle() then
		newCf = Bridge.retargetOriginCFrame(
			originCFrame, target, State.forceHitPoint or State.aimAimPoint
		)
	end
	if Bridge.shouldSpoofMuzzlePosition() then
		local aimPt = State.forceHitPoint or State.aimAimPoint
		if typeof(aimPt) == "Vector3"
			and Bridge.needsMuzzleOffset(newCf.Position, aimPt, target) then
			newCf = Bridge.applyShotOriginSpoof(newCf)
		end
	end

	if payload then
		payload._brm5AimPatched = true
		payload.OriginCFrame = newCf
	end

	return newCf, true
end

Bridge.patchBulletPayload = function(payload)
	if type(payload) ~= "table" or typeof(payload.OriginCFrame) ~= "CFrame" then
		return false
	end
	if payload.Local ~= true then return false end
	local newCf, patched = Bridge.tryAimPatch(payload.OriginCFrame, payload, true)
	if typeof(newCf) == "CFrame" then
		payload.OriginCFrame = newCf
		payload._brm5AimPatched = true
		return true
	end
	if typeof(State.combatMuzzleCf) == "CFrame" and Bridge.shouldSpoofMuzzlePosition() then
		payload.OriginCFrame = State.combatMuzzleCf
		payload._brm5AimPatched = true
		return true
	end
	return patched == true
end

function Bridge.patchOriginCFrame(originCFrame)
	return Bridge.silentRetargetCFrame(originCFrame)
end

function Bridge.getBulletService()
	if State.bulletService then return State.bulletService end
	if type(shared) == "table" and type(shared.import) == "function" then
		local okReq, req = pcall(shared.import, "require")
		if okReq and type(req) == "function" then
			local okSvc, svc = pcall(req, "BulletService")
			if okSvc and type(svc) == "table" and type(svc.Discharge) == "function" then
				State.bulletService = svc
				return svc
			end
		end
	end
	local sharedRoot = RS:FindFirstChild("Shared")
	local services = sharedRoot and sharedRoot:FindFirstChild("Services")
	local mod = services and services:FindFirstChild("BulletService")
	if mod and mod:IsA("ModuleScript") then
		local ok, svc = pcall(require, mod)
		if ok and type(svc) == "table" and type(svc.Discharge) == "function" then
			State.bulletService = svc
			return svc
		end
	end
	if type(getgc) == "function" then
		local now = os.clock()
		if now - (State.lastBulletSvcGc or 0) >= 8.0 then
			State.lastBulletSvcGc = now
			for _, obj in ipairs(getGcCached()) do
				if type(obj) == "table"
					and type(rawget(obj, "Discharge")) == "function"
					and rawget(obj, "_multithreadSend") then
					State.bulletService = obj
					return obj
				end
			end
		end
	end
	return nil
end

function Bridge.findBulletSendEvent()
	for _, child in ipairs(RF:GetChildren()) do
		if child:IsA("Actor") then
			local mt = child:FindFirstChild("BulletServiceMultithread")
			if mt then
				local send = mt:FindFirstChild("Send")
				if send and send:IsA("BindableEvent") then
					return send
				end
			end
		end
	end
	local mt = RF:FindFirstChild("BulletServiceMultithread", true)
	if mt then
		local send = mt:FindFirstChild("Send")
		if send and send:IsA("BindableEvent") then
			return send
		end
	end
	return nil
end

function Bridge.findBulletClassModule()
	for _, child in ipairs(RF:GetChildren()) do
		if child:IsA("Actor") then
			local mt = child:FindFirstChild("BulletServiceMultithread")
			if mt then
				local cls = mt:FindFirstChild("BulletClassMultithread")
				if cls and cls:IsA("ModuleScript") then
					return cls
				end
			end
		end
	end
	local mt = RF:FindFirstChild("BulletServiceMultithread", true)
	if mt then
		local cls = mt:FindFirstChild("BulletClassMultithread")
		if cls and cls:IsA("ModuleScript") then
			return cls
		end
	end
	return nil
end

function Bridge.findBulletActor()
	for _, child in ipairs(RF:GetChildren()) do
		if child:IsA("Actor") then
			local mt = child:FindFirstChild("BulletServiceMultithread")
			if mt and mt:FindFirstChild("BulletClassMultithread") then
				return child
			end
		end
	end
	if type(getactors) == "function" then
		for _, actor in ipairs(getactors()) do
			if typeof(actor) == "Instance" and actor:IsA("Actor") then
				local mt = actor:FindFirstChild("BulletServiceMultithread")
				if mt and mt:FindFirstChild("BulletClassMultithread") then
					return actor
				end
			end
		end
	end
	return nil
end

function Bridge.hookBulletSend(send)
	local G = brm5Global()
	if G.sendHooked or State.sendHooked or not send then
		if G.sendHooked then State.sendHooked = true end
		return G.sendHooked == true or State.sendHooked == true
	end

	local originalFire = send.Fire
	local function wrappedFire(self, op, ...)
		if op == 1 then
			local uid, payload = ...
			if type(payload) == "table" and payload.Local == true then
				local ctx = Bridge.peekWeaponContext and Bridge.peekWeaponContext() or nil
				Bridge.ensureGameBulletPayload(payload, ctx)
			end
		end
		return originalFire(self, op, ...)
	end

	if type(hookfunction) == "function" then
		local origFire = originalFire
		local ok, hooked = pcall(function()
			local ref
			local sendHookFn = function(self, op, ...)
				if op == 1 then
					local uid, payload = ...
					if type(payload) == "table" and payload.Local == true then
						local ctx = Bridge.peekWeaponContext and Bridge.peekWeaponContext() or nil
						Bridge.ensureGameBulletPayload(payload, ctx)
					end
				end
				return ref(self, op, ...)
			end
			if type(newcclosure) == "function" then
				sendHookFn = newcclosure(sendHookFn, "Fire")
			end
			ref = hookfunction(origFire, sendHookFn)
			return ref
		end)
		if ok and hooked then
			State.sendHooked = true
			G.sendHooked = true
			log("AIM", "Send.Fire hookfunction")
			return true
		end
	end

	send.Fire = wrappedFire
	State.sendHooked = true
	G.sendHooked = true
	log("AIM", "Send.Fire wrap")
	return true
end

function Bridge.hookBulletSendEventCallback(send)
	if State.sendEventHooked or not send then return false end
	if type(getconnections) ~= "function" then return false end
	if type(State.sendConnHooks) ~= "table" then
		State.sendConnHooks = {}
	end

	local okList, conns = pcall(getconnections, send.Event)
	if not okList or type(conns) ~= "table" then return false end

	local hookedAny = false
	for _, conn in ipairs(conns) do
		if State.sendConnHooks[conn] then continue end
		if type(conn.Function) ~= "function" then continue end

		local hookOk = pcall(function()
			local origFn = conn.Function
			local function wrapped(op, ...)
				return origFn(op, ...)
			end
			if type(newcclosure) == "function" then
				wrapped = newcclosure(wrapped, "brm5SendEvent")
			end
			conn.Function = wrapped
			State.sendConnHooks[conn] = true
			hookedAny = true
		end)
		if not hookOk then
			log("AIM", "Send.Event conn hook skipped")
		end
	end
	if hookedAny then
		State.sendEventHooked = true
		log("AIM", "Send.Event callback hooked")
		return true
	end
	return false
end

function Bridge.hookBulletClassNew()
	local modScript = Bridge.findBulletClassModule()
	if not modScript then return false end
	local ok, mod = pcall(require, modScript)
	if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
		return false
	end
	local originalNew = rawget(mod, "__brm5OrigNew") or mod.new
	if not rawget(mod, "__brm5OrigNew") then
		rawset(mod, "__brm5OrigNew", originalNew)
	end
	local originalUpdate = rawget(mod, "__brm5OrigUpdate")
	if not originalUpdate and type(mod.Update) == "function" then
		originalUpdate = mod.Update
		rawset(mod, "__brm5OrigUpdate", originalUpdate)
	end
	rawset(mod, "__brm5NewHook", true)
	Bridge.hookBulletClassMtSend(mod)

	local function applyForceClientHit(bullet)
		Bridge.forceHitOnBulletUpdate(bullet)
	end

	mod.new = function(payload)
		if type(payload) == "table" and payload.Local == true then
			local ctx = Bridge.peekWeaponContext and Bridge.peekWeaponContext() or nil
			Bridge.ensureGameBulletPayload(payload, ctx)
		end
		local bullet = originalNew(payload)
		if type(bullet) == "table" and payload and payload.Local == true then
			Bridge.installBulletForceHitHooks(bullet)
		end
		return bullet
	end
	if originalUpdate then
		mod.Update = function(self, dt)
			applyForceClientHit(self)
			return originalUpdate(self, dt)
		end
	end
	State.bulletClassHooked = true
	log("AIM", "BulletClassMultithread.new+Update hooked")
	return true
end

function Bridge.shouldPatchClientBullet()
	return CONFIG.SilentAim or mpActive() or Bridge.shouldForceClientHit()
end

function Bridge.patchBulletEventOp1(uid, replicate, hitPos, part, normal, material, timeOff)
	if not (CONFIG.SilentAim or Bridge.shouldForceClientHit()) then
		return uid, replicate, hitPos, part, normal, material, timeOff, false
	end
	if State.inOurBulletOp1Fire == uid then
		if part and Bridge.isEnemyHitPart(part) then
			local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(hitPos, part, nil, uid)
			if changed then
				hitPos, part = nh, np
				if nn then normal = nn end
			end
		end
		return uid, replicate, hitPos, part, normal, material, timeOff, true
	end
	if Bridge.shouldForceClientHit() and type(uid) == "string" and Bridge.isMyBulletUid(uid) then
		if part and Bridge.isEnemyHitPart(part) and type(Bridge.tryLocalEnemyHitFx) == "function" then
			local nh, np = Bridge.redirectEnemyHitToAimBone(hitPos, part, nil, uid)
			Bridge.tryLocalEnemyHitFx(1, np or hitPos, part, normal, nil, uid)
		end
		return uid, replicate, hitPos, part, normal, material, timeOff, "suppress"
	end
	if part and Bridge.isEnemyHitPart(part) then
		local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(hitPos, part, nil, uid)
		if changed then
			hitPos, part = nh, np
			if nn then normal = nn end
			return uid, replicate, hitPos, part, normal, material, timeOff, true
		end
		return uid, replicate, hitPos, part, normal, material, timeOff, false
	end
	if Bridge.shouldPatchClientBullet() and typeof(hitPos) == "Vector3" then
		hitPos, part = Bridge.patchHitPartAndPos(hitPos, part, hitPos)
		return uid, replicate, hitPos, part, normal, material, timeOff, true
	end
	return uid, replicate, hitPos, part, normal, material, timeOff, false
end

function Bridge.dispatchBulletEvent(originalFire, self, op, ...)
	if op == 2 then
		local originPos, hitPos, part, normal, material, caliber, isLocal = ...
		local resolveLocal = Bridge.resolveBulletEventIsLocal or Bridge.isLocalPlayerShot
		local isLocalShot = type(resolveLocal) ~= "function" or resolveLocal(isLocal)
			or Bridge.isRecentCombatShot()
		if isLocalShot then
			local patched
			originPos, hitPos, part, normal, patched = Bridge.patchBulletEventOp2(
				originPos, hitPos, part, normal, isLocal
			)
			if patched then
				return originalFire(self, op, originPos, hitPos, part, normal, material, caliber, true)
			end
		end
	elseif op == 1 then
		local uid, replicate, hitPos, part, normal, material, timeOff = ...
		local isMine = Bridge.isMyBulletUid(uid) or Bridge.getPendingBulletShot(uid) ~= nil
		if isMine then
			local action
			uid, replicate, hitPos, part, normal, material, timeOff, action = Bridge.patchBulletEventOp1(
				uid, replicate, hitPos, part, normal, material, timeOff
			)
			if action == "suppress" then
				return
			end
			if action == true then
				return originalFire(self, op, uid, replicate, hitPos, part, normal, material, timeOff)
			end
		end
	end
	return originalFire(self, op, ...)
end

function Bridge.hookBulletEventFire()
	local G = brm5Global()
	G.State = State
	if G.bulletEventFireHooked then
		State.bulletEventHooked = true
		State.bulletEventInst = RF:FindFirstChild("BulletEvent")
		return true
	end
	local inst = RF:FindFirstChild("BulletEvent")
	if not inst or not inst:IsA("BindableEvent") then
		return false
	end
	State.bulletEventInst = inst

	local originalFire = inst.Fire
	if type(hookfunction) == "function" then
		local ok = pcall(function()
			local ref
			local bulletHookFn = function(self, op, ...)
				return Bridge.dispatchBulletEvent(ref, self, op, ...)
			end
			if type(newcclosure) == "function" then
				bulletHookFn = newcclosure(bulletHookFn, "Fire")
			end
			ref = hookfunction(originalFire, bulletHookFn)
			G.bulletEventFireRef = ref
		end)
		if ok then
			G.bulletEventFireHooked = true
			State.bulletEventHooked = true
			log("AIM", "BulletEvent.Fire hookfunction")
			return true
		end
	end

	inst.Fire = function(self, op, ...)
		return Bridge.dispatchBulletEvent(originalFire, inst, op, ...)
	end
	G.bulletEventFireHooked = true
	State.bulletEventHooked = true
	log("AIM", "BulletEvent.Fire wrap")
	return true
end

function Bridge.isBulletMultithreadSend(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("BindableEvent") or inst.Name ~= "Send" then
		return false
	end
	local parent = inst.Parent
	return parent ~= nil and parent.Name == "BulletServiceMultithread"
end

function Bridge.waitForBulletPipeline(maxWait)
	maxWait = maxWait or 12
	local deadline = os.clock() + maxWait
	while os.clock() < deadline do
		if Bridge.getBulletService() and Bridge.findBulletSendEvent() and Bridge.findBulletActor() then
			return true
		end
		task.wait(0.2)
	end
	return Bridge.getBulletService() ~= nil
end

function Bridge.logBulletHookStatus()
	log(
		"AIM", "hook-status",
		"discharge=" .. tostring(State.dischargeHooked),
		"network=" .. tostring(State.networkDischargeHooked),
		"send=" .. tostring(State.sendHooked),
		"actor=" .. tostring(State.actorBulletHooked),
		"namecall=" .. tostring(State.namecallHooked),
		"ncVer=" .. tostring(State.namecallHookVer or 0),
		"addToFilter=" .. tostring(State.addToFilterHooked),
		"svc=" .. tostring(Bridge.getBulletService() ~= nil),
		"sendEvt=" .. tostring(Bridge.findBulletSendEvent() ~= nil)
	)
end

function Bridge.installNamecallHooks()
	local G = brm5Global()
	G.State = State
	local NAMECALL_VER = 20
	if G.namecallVer and G.namecallVer >= NAMECALL_VER then
		G.State = State
		State.namecallHooked = true
		State.namecallHookVer = G.namecallVer
		State.bulletEventInst = RF:FindFirstChild("BulletEvent")
		State.bulletReceiveInst = Bridge.findBulletReceiveEvent()
		State.bulletSendInst = Bridge.findBulletSendEvent()
		State.bulletEventHooked = State.bulletEventInst ~= nil
		State.receiveHooked = State.bulletReceiveInst ~= nil
		return true
	end
	if State.namecallHooked and (State.namecallHookVer or 0) >= NAMECALL_VER then
		return true
	end
	if type(hookmetamethod) ~= "function" then return false end
	if type(getnamecallmethod) ~= "function" or type(newcclosure) ~= "function" then return false end

	State.bulletEventInst = RF:FindFirstChild("BulletEvent")
	State.bulletReceiveInst = Bridge.findBulletReceiveEvent()
	State.bulletSendInst = Bridge.findBulletSendEvent()
	Bridge.refreshServerRemotes()

	local ok, hookErr = pcall(function()
		local old
		old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecallmethod()

			-- 1. Never interfere with Drawing (global table or its render objects)
			if Drawing then
				if rawequal(self, Drawing) then
					return old(self, ...)
				end
				if type(Drawing.isrenderobj) == "function" then
					local rok, isR = pcall(Drawing.isrenderobj, self)
					if rok and isR then
						return old(self, ...)
					end
				end
			end

			-- 2. Non-Instances (userdata, tables from exploit APIs etc.) passthrough exactly as v1
			if typeof(self) ~= "Instance" then
				return old(self, ...)
			end

			-- 3. KillAura melee + ForceHit: BulletCast raycast/spherecast
			if (method == "Raycast" or method == "Spherecast") and self == workspace
				and Bridge.shouldForceMeleeKaRaycast and Bridge.shouldForceMeleeKaRaycast() then
				return Bridge.interceptMeleeKaRaycast(old, self, ...)
			end

			-- 4. ForceHit: перехват bullet-raycast (CollisionGroup=9) в Actor-потоке
			if method == "Raycast" and self == workspace and Bridge.shouldForceClientHit() then
				return Bridge.interceptForceHitRaycast(old, self, ...)
			end

			-- 5. Fast path: only intercept the methods we care about; everything else direct
			if method ~= "FireServer" and method ~= "Fire" then
				return old(self, ...)
			end

			local args = table.pack(self, ...)

			if method == "Fire" then
				local bulletInst = State.bulletEventInst or RF:FindFirstChild("BulletEvent")
				if self == bulletInst and G.bulletEventFireHooked then
					return old(self, ...)
				end
			end

			-- 5. Patch logic is wrapped: any error here MUST NOT prevent the original call
			local success, result = pcall(function()
				if method == "FireServer" and Bridge.needsServerAimPatch() then
					for i = 2, args.n - 2 do
						if args[i] == "InventoryAction" and args[i + 1] == "Discharge" and type(args[i + 2]) == "table" then
							local origin
							local b = args[i + 2][1]
							if type(b) == "table" and type(b[2]) == "number" then
								origin = Vector3.new(b[2], b[3], b[4])
							end
							Bridge.ensureShotTargetForPatch(origin)
							Bridge.patchV138ServerAim(args[i + 2])
							break
						end
					end
				elseif method == "Fire" then
					local bulletInst = State.bulletEventInst or RF:FindFirstChild("BulletEvent")
					if self == bulletInst then
						local op = args[2]
						if op == 2 then
							local originPos = args[3]
							local hitPos = args[4]
							local part = args[5]
							local normal = args[6]
							local material = args[7]
							local caliber = args[8]
							local isLocal = args[9]
							if Bridge.shouldForceClientHit()
								and (not part or not Bridge.isEnemyHitPart(part))
								and isLocal == true then
								local fOrigin, fHit, fPart, fNormal, fMat, fCal = Bridge.applyForceHitOp2(
									originPos, hitPos, part, normal, material, caliber, nil
								)
								if fPart and fPart.Parent then
									args[3], args[4], args[5], args[6] = fOrigin, fHit, fPart, fNormal
									args[7], args[8], args[9] = fMat, fCal, true
									originPos, hitPos, part, normal = fOrigin, fHit, fPart, fNormal
									isLocal = true
								end
							end
							local patched
							originPos, hitPos, part, normal, patched = Bridge.patchBulletEventOp2(
								originPos, hitPos, part, normal, isLocal
							)
							if patched then
								args[3], args[4], args[5], args[6] = originPos, hitPos, part, normal
								args[9] = true
							end
						elseif Bridge.shouldPatchClientBullet() and op == 1 then
							local hitPos = args[4]
							local part = args[5]
							if typeof(hitPos) == "Vector3" then
								hitPos, part = Bridge.patchHitPartAndPos(hitPos, part, hitPos)
								args[4], args[5] = hitPos, part
							end
						end
					elseif self == State.bulletReceiveInst then
						if not G.receiveFireHooked then
							args[2] = Bridge.patchReceiveBatch(args[2])
						end
					end
				end
				return old(table.unpack(args, 1, args.n))
			end)

			if success then
				return result
			end
			Bridge.reportError("namecall", result)
			return old(self, ...)
		end))
	end)
	G.State = State
	if not ok then
		Bridge.reportError("installNamecallHooks", hookErr)
		return false
	end

	State.namecallHooked = true
	State.namecallHookVer = NAMECALL_VER
	G.namecallVer = NAMECALL_VER
	State.bulletEventHooked = State.bulletEventInst ~= nil
	State.receiveHooked = State.bulletReceiveInst ~= nil

	-- Post-hook Drawing API sanity test: if this vanishes together with ESP, the hook (or something at install time) is killing Drawing.
	-- If it stays visible while ESP/AimViz disappear, then hides are coming from code (see VIZ logs with VizDebug).
	pcall(function()
		if Drawing and type(Drawing.new) == "function" then
			local t = Drawing.new("Text")
			t.Text = "HOOKTEST-v15"
			t.Size = 20
			t.Center = true
			t.Outline = true
			t.Color = Color3.fromRGB(255, 255, 0)
			t.Position = Vector2.new(400, 80)
			t.ZIndex = 99
			t.Visible = true
			State._hookDrawingTest = t
			task.delay(8, function()
				pcall(function()
					if State._hookDrawingTest then Bridge.destroyDrawing(State._hookDrawingTest) end
					State._hookDrawingTest = nil
				end)
			end)
		end
	end)

	log(
		"AIM", "namecall v" .. tostring(NAMECALL_VER),
		"| BulletEvent", (State.bulletEventHooked or brm5Global().bulletEventFireHooked) and "ok" or "no",
		"| Send", State.bulletSendInst and "ok" or "no",
		"| Receive", (State.receiveFireHooked or State.receiveHooked) and "ok" or "no",
		"| AddToFilter", "RaycastParams",
		"| discharge", State.dischargeHooked and "ok" or "no"
	)
	return true
end

function Bridge.hookBulletReceiveFire()
	local G = brm5Global()
	if G.receiveFireHooked or State.receiveFireHooked then
		State.receiveFireHooked = true
		return true
	end
	local recv = State.bulletReceiveInst or Bridge.findBulletReceiveEvent()
	if not recv or not recv:IsA("BindableEvent") then
		return false
	end
	State.bulletReceiveInst = recv
	local originalFire = recv.Fire
	if type(hookfunction) == "function" then
		local ok = pcall(function()
			local ref
			local recvHookFn = function(self, batch, ...)
				batch = Bridge.patchReceiveBatch(batch)
				return ref(self, batch, ...)
			end
			if type(newcclosure) == "function" then
				recvHookFn = newcclosure(recvHookFn, "Fire")
			end
			ref = hookfunction(originalFire, recvHookFn)
			G.receiveFireRef = ref
		end)
		if ok then
			G.receiveFireHooked = true
			State.receiveFireHooked = true
			log("AIM", "Receive.Fire hookfunction")
			return true
		end
	end
	recv.Fire = function(self, batch, ...)
		batch = Bridge.patchReceiveBatch(batch)
		return originalFire(self, batch, ...)
	end
	G.receiveFireHooked = true
	State.receiveFireHooked = true
	log("AIM", "Receive.Fire wrap")
	return true
end

function Bridge.hookReceiveEventConnections(recv)
	if State.receiveConnHooked or type(getconnections) ~= "function" then return false end
	recv = recv or State.bulletReceiveInst or Bridge.findBulletReceiveEvent()
	if not recv or not recv:IsA("BindableEvent") then return false end
	local okList, conns = pcall(getconnections, recv.Event)
	if not okList or type(conns) ~= "table" then return false end
	State.receiveConnHooks = State.receiveConnHooks or {}
	local hookedAny = false
	for _, conn in ipairs(conns) do
		if State.receiveConnHooks[conn] then continue end
		if type(conn.Function) ~= "function" then continue end
		local wrapOk = pcall(function()
			local origFn = conn.Function
			conn.Function = function(batch, ...)
				batch = Bridge.patchReceiveBatch(batch)
				return origFn(batch, ...)
			end
			State.receiveConnHooks[conn] = true
			hookedAny = true
		end)
		if not wrapOk then continue end
	end
	if hookedAny then
		State.receiveConnHooked = true
		log("AIM", "Receive.Event callbacks hooked")
	end
	return hookedAny
end

function Bridge.installBulletEventHook()
	return Bridge.installNamecallHooks()
end

function Bridge.findBulletReceiveEvent()
	for _, child in ipairs(RF:GetChildren()) do
		if child:IsA("Actor") then
			local mt = child:FindFirstChild("BulletServiceMultithread")
			local recv = mt and mt:FindFirstChild("Receive")
			if recv and recv:IsA("BindableEvent") then
				return recv
			end
		end
	end
	return nil
end

function Bridge.installReceiveHook()
	return Bridge.installNamecallHooks()
end

function Bridge.installNetworkNamecallHook()
	return Bridge.installNamecallHooks()
end

function Bridge.hookBulletDischarge()
	local G = brm5Global()
	if G.dischargeHooked or State.dischargeHooked then
		State.dischargeHooked = true
		return true
	end
	local svc = Bridge.getBulletService()
	if not svc or type(svc.Discharge) ~= "function" then
		return false
	end

	local originalDischarge = svc.Discharge
	local function patchLocalDischargeIgnore(originCFrame, ignore)
		local aimPt = State.forceHitPoint or State.aimAimPoint
		local target = State.shotAimTarget or State.aimTargetPart
		if typeof(originCFrame) == "CFrame" and (not target or not target.Parent) then
			local now = os.clock()
			if now - (State.lastDischargePrep or 0) >= 0.05 then
				State.lastDischargePrep = now
				if type(Bridge.prepareCombatShotOnce) == "function" then
					Bridge.prepareCombatShotOnce(originCFrame.Position)
				else
					Bridge.prepareCombatShot(originCFrame.Position)
				end
			end
			aimPt = State.forceHitPoint or State.aimAimPoint
			target = State.shotAimTarget or State.aimTargetPart
		end
		if typeof(originCFrame) == "CFrame" and typeof(aimPt) == "Vector3"
			and target and target.Parent then
			return Bridge.applyCombatBulletIgnore(ignore, originCFrame.Position, aimPt, target)
		end
		return Bridge.applyTeammateBulletIgnore(ignore)
	end
	local function onLocalShot(shotUid, muzzlePos, caliber, replicate)
		State.lastShotOrigin = muzzlePos
		if typeof(muzzlePos) == "Vector3" then
			Bridge.prepareCombatShotOnce(muzzlePos)
		end
		local target = State.shotAimTarget or State.aimTargetPart
		local aimPart = State.aimTargetPart or target
		local aimPt = State.forceHitPoint or State.aimAimPoint
		if (not aimPart or not aimPart.Parent) and typeof(muzzlePos) == "Vector3" then
			target = Bridge.getCombatAimTarget(muzzlePos, false)
			aimPart = State.aimTargetPart or target
			aimPt = State.forceHitPoint or State.aimAimPoint
		end
		Bridge.storePendingBulletShot(shotUid, target, aimPart, aimPt, muzzlePos, caliber, replicate)
		Bridge.spawnDischargeTracer(shotUid, muzzlePos, aimPt)
		if Bridge.shouldForceClientHit() then
			Bridge.scheduleForceBulletOp1(shotUid, muzzlePos, aimPt, caliber, replicate)
		end
	end
	local function runDischarge(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
		if isLocal == true then
			markCombatDischarge()
			if CONFIG.SilentAim or mpActive() or Bridge.shouldForceClientHit() then
				if State.inDischargeHook then
					return originalDischarge(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
				end
				State.inDischargeHook = true
				local okAim, aimCf = pcall(applyDischargeAim, originCFrame)
				if okAim and typeof(aimCf) == "CFrame" then
					originCFrame = aimCf
				end
				State.inDischargeHook = false
			end
			ignore = patchLocalDischargeIgnore(originCFrame, ignore)
		end
		local shotUid = originalDischarge(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
		if isLocal == true and type(shotUid) == "string" then
			local muzzlePos = typeof(originCFrame) == "CFrame" and originCFrame.Position or nil
			onLocalShot(shotUid, muzzlePos, caliber, replicate)
		end
		return shotUid
	end

	if type(hookfunction) == "function" then
		local origDischarge = originalDischarge
		local ok, hooked = pcall(function()
			local ref
			local dischargeHookFn = function(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
				if isLocal == true then
					markCombatDischarge()
					if CONFIG.SilentAim or mpActive() or Bridge.shouldForceClientHit() then
						if State.inDischargeHook then
							return ref(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
						end
						State.inDischargeHook = true
						local okAim, aimCf = pcall(applyDischargeAim, originCFrame)
						if okAim and typeof(aimCf) == "CFrame" then
							originCFrame = aimCf
						end
						State.inDischargeHook = false
					end
					ignore = patchLocalDischargeIgnore(originCFrame, ignore)
				end
				local shotUid = ref(self, originCFrame, caliber, velScale, uid, replicate, isLocal, a7, ignore, a9, a10)
				if isLocal == true and type(shotUid) == "string" then
					local muzzlePos = typeof(originCFrame) == "CFrame" and originCFrame.Position or nil
					onLocalShot(shotUid, muzzlePos, caliber, replicate)
				end
				return shotUid
			end
			if type(newcclosure) == "function" then
				dischargeHookFn = newcclosure(dischargeHookFn, "Discharge")
			end
			if type(setstackhidden) == "function" then
				pcall(setstackhidden, dischargeHookFn, true)
			end
			ref = hookfunction(origDischarge, dischargeHookFn)
			return ref
		end)
		if ok and hooked then
			State.dischargeHooked = true
			G.dischargeHooked = true
			log("AIM", "Discharge hookfunction")
			return true
		end
	end

	svc.Discharge = runDischarge
	State.dischargeHooked = true
	G.dischargeHooked = true
	log("AIM", "Discharge wrap")
	return true
end

function Bridge.installSilentAim()
	brm5Global().State = State
	for k, v in pairs(SA_CONFIG) do
		Lib.CONFIG[k] = v
	end

	local hooked = false
	if Bridge.hookFirearmInventory() then hooked = true end
	if Bridge.hookNetworkDischarge() then hooked = true end
	if Bridge.hookBulletDischarge() then hooked = true end
	local send = Bridge.findBulletSendEvent()
	if send and Bridge.hookBulletSend(send) then hooked = true end
	if Bridge.hookBulletClassNew() then hooked = true end
	if Bridge.hookBulletEventFire() then hooked = true end
	if Bridge.hookBulletReceiveFire() then hooked = true end
	if Bridge.installActorBulletHooks() then hooked = true end
	if Bridge.installNamecallHooks() then hooked = true end
	if not State.actorBulletHooked then
		task.defer(function()
			for _ = 1, 8 do
				if State.actorBulletHooked then break end
				if Bridge.installActorBulletHooks() then hooked = true break end
				task.wait(0.75)
			end
		end)
	end
	if CONFIG.LogBulletEvent == true then
		Bridge.installBulletEventLogger()
	end
	Bridge.installHitFxListener()
	Bridge.logBulletHookStatus()
	if hooked then
		State.silentAimInstalled = true
	elseif not State.silentAimInstalled then
		log("AIM", "hooks pending — GetMuzzleCFrame / Discharge")
	end
	return hooked
end

function Bridge.clearAimVisuals()
	Bridge.hideAimViz()
	Bridge.clearBulletTracers()
	if State.aimViz then
		-- FIX: раньше здесь индексировался несуществующий локал `viz` — pcall
		-- глотал ошибку на ПЕРВОЙ же строке, поэтому НИ ОДИН Drawing ниже
		-- не удалялся. Теперь чистим строго через State.aimViz.
		local av = State.aimViz
		for _, key in ipairs({ "crossH", "crossV", "dot", "line", "label" }) do
			Bridge.destroyDrawing(av[key])
			av[key] = nil
		end
		if av.boxLines then
			for _, l in ipairs(av.boxLines) do Bridge.destroyDrawing(l) end
			av.boxLines = nil
		end
		State.aimViz = nil
	end
end

-- ============================================================
-- MODIFY — live Tune / Caliber / ViewModel
-- ============================================================

local MODIFY_NUMERIC_KEYS = {
	Barrel_Spread = 0,
	Spread = 0,
	Recoil_X = 0,
	Recoil_Z = 0,
	Recoil_Camera = 0,
	RecoilForce_Impulse = 0,
	RecoilForce_Tap = 0,
}

function Bridge.shallowCopyTable(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

function Bridge.backupModifyState(ctx)
	local uid = Bridge.itemUid(ctx.item)
	if not uid or State.modifyBackup[uid] then return end
	local snap = { tune = {}, cal = {}, metaMode = nil }
	if ctx.tune then
		for k, v in pairs(ctx.tune) do
			snap.tune[k] = v
		end
	end
	if ctx.cal then
		for k, v in pairs(ctx.cal) do
			if k ~= "Damage" then
				snap.cal[k] = v
			end
		end
	end
	if ctx.meta then
		snap.metaMode = rawget(ctx.meta, "Mode")
	end
	State.modifyBackup[uid] = snap
end

-- getLiveWeaponContext / getCachedWeaponContext — в BRM5Lib_v2 (fluxHandler + кэш)

function Bridge.ensureHandlerDischargeHook(handler)
	-- Отключено: handler.Discharge == FirearmInventory.Discharge; повторный hook → stack overflow.
	if type(handler) == "table" then
		rawset(handler, "__brm5DHook", true)
	end
end

function Bridge.applyModifyPresetNoSpread(ctx)
	if ctx.tune then
		ctx.tune.Barrel_Spread = 0
		for k, v in pairs(ctx.tune) do
			if type(k) == "string" and k:find("Spread", 1, true) and type(v) == "number" then
				ctx.tune[k] = 0
			end
		end
	end
	if ctx.cal then
		ctx.cal.Spread = 0
	end
	if type(Bridge.zeroClientWeaponSpread) == "function" then
		Bridge.zeroClientWeaponSpread(ctx)
	end
end

function Bridge.applyModifyPresetNoRecoil(ctx)
	if ctx.tune then
		ctx.tune.Recoil_X = 0
		ctx.tune.Recoil_Z = 0
		ctx.tune.Recoil_Camera = 0
		ctx.tune.RecoilForce_Impulse = 0
		ctx.tune.RecoilForce_Tap = 0
		ctx.tune.Recoil_Range = Vector2.zero
		ctx.tune.RecoilAccelDamp_Crouch = Vector3.zero
		ctx.tune.RecoilAccelDamp_Prone = Vector3.zero
		ctx.tune.RecoilAccelDamp_Stock = Vector3.zero
	end
	if ctx.cal then
		ctx.cal.RecoilForce = 0
	end
	local vm = tableField(ctx.actor, "ViewModel")
	if type(vm) == "table" then
		local recoil = tableField(vm, "Recoil")
		if type(recoil) == "table" then
			recoil.Kick = 0
			recoil.Drag = 0
		end
	end
end

function Bridge.applyTuneLive(ctx, fn)
	if type(fn) ~= "function" or not ctx then return end
	pcall(fn, ctx)
	local handler = ctx.handler
	if handler and handler._firearm and handler._firearm.Tune then
		local liveCtx = {
			actor = ctx.actor,
			handler = handler,
			item = ctx.item,
			meta = ctx.meta,
			tune = handler._firearm.Tune,
			cal = ctx.cal,
			info = ctx.info,
		}
		pcall(fn, liveCtx)
	end
end

function Bridge.applyModifyPresetInstantBolt(ctx)
	if not ctx or not ctx.tune then return end
	ctx.tune.Bolt_Action_Pause = 0
	ctx.tune.Bolt_Action_NoPause = true
	ctx.tune.Bolt_Action_Shell = 0
end

function Bridge.applyModifyPresetFastADS(ctx)
	if not ctx or not ctx.tune then return end
	for k, v in pairs(ctx.tune) do
		if type(k) == "string" and k:find("ADS", 1, true) and type(v) == "number" and v > 0 then
			ctx.tune[k] = math.max(v * 0.15, 0.01)
		end
	end
	if type(ctx.tune.ADS_Speed) == "number" then
		ctx.tune.ADS_Speed = math.max(ctx.tune.ADS_Speed * 4, 8)
	end
	if type(ctx.tune.ADS_Time) == "number" then
		ctx.tune.ADS_Time = 0.01
	end
end

function Bridge.resolveForceHitArgs(bullet, pending)
	if not bullet then return nil end
	local payload = Bridge.resolveForceHitPayload(
		bullet._uid,
		bullet._originCFrame and bullet._originCFrame.Position,
		bullet._caliber
	)
	if not payload then return nil end
	return payload.origin, payload.hitPos, payload.part, payload.normal, payload.material, payload.caliber, true
end

function Bridge.injectForceHitOp2OnBullet(bullet)
	if not bullet or bullet._local == false or bullet._brm5ForceHitSent then return end
	if not Bridge.shouldForceClientHit() then return end
	local origin, hitPos, part, normal, material, caliber, isLocal = Bridge.resolveForceHitArgs(bullet)
	if not part or not part.Parent or typeof(hitPos) ~= "Vector3" then return end
	local mp = bullet.MultithreadPayload
	if type(mp) == "table" then
		for _, entry in ipairs(mp) do
			if type(entry) == "table" and entry[1] == 2 then
				if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
					bullet._brm5ForceHitSent = true
					return
				end
				entry[2] = origin
				entry[3] = hitPos
				entry[4] = part
				entry[5] = normal
				entry[6] = material
				entry[7] = caliber
				entry[8] = true
				bullet._brm5ForceHitSent = true
				return
			end
		end
	end
	if bullet._landed and bullet._landed[2] and Bridge.isEnemyHitPart(bullet._landed[2]) then
		bullet._brm5ForceHitSent = true
		return
	end
	bullet._brm5ForceHitSent = true
	if type(bullet._multithreadSend) == "function" then
		bullet:_multithreadSend(2, origin, hitPos, part, normal, material, caliber, isLocal == true)
	end
end

function Bridge.installActorBulletHooks()
	local ACTOR_HOOK_VER = 5
	if State.actorBulletHooked and State.actorBulletHookVer == ACTOR_HOOK_VER then
		return true
	end
	local actor = Bridge.findBulletActor()
	if not actor or type(run_on_actor) ~= "function" then
		return false
	end
	local actorName = actor.Name:gsub("%%", "%%%%")
	local actorCode = ([[
local ACTOR_HOOK_VER = %d
local RF = game:GetService("ReplicatedFirst")
local actor = RF:FindFirstChild("%s")
if not actor then return end
local bsm = actor:FindFirstChild("BulletServiceMultithread")
if not bsm then return end
local mod = require(bsm:WaitForChild("BulletClassMultithread"))
if rawget(mod, "__brm5ActorHookVer") == ACTOR_HOOK_VER then return end
rawset(mod, "__brm5ActorHookVer", ACTOR_HOOK_VER)
local function fhBonePart(fh, hitPart)
	if type(fh) ~= "table" or not hitPart or not hitPart.Parent then return nil end
	local model = hitPart.Parent
	local bone = model:FindFirstChild(fh.boneName or "Head")
	if bone and bone:IsA("BasePart") then return bone end
	if fh.aimPart and fh.aimPart.Parent then return fh.aimPart end
	return nil
end
local function applyForceHitLanded(self, fh)
	if type(fh) ~= "table" or not fh.aimPart or not fh.aimPart.Parent then return end
	local landed = self._landed
	if type(landed) ~= "table" then return end
	local origin = self._originCFrame and self._originCFrame.Position
	local aimPart = fh.aimPart
	local hitPos = fh.hitPos or aimPart.Position
	local normal = origin and (origin - hitPos).Unit or Vector3.new(0, 0, -1)
	local mat = aimPart.Material
	local travel = landed[5] or 0
	local hitPart = landed[2]
	if hitPart and hitPart:GetAttribute("ActorUID") then
		aimPart = fhBonePart(fh, hitPart) or aimPart
		hitPos = fh.hitPos or aimPart.Position
	end
	self._landed = { hitPos, aimPart, normal, mat, travel }
end
local origNew = mod.new
mod.new = function(payload)
	local bullet = origNew(payload)
	if type(payload) == "table" and payload.Local == true and type(payload._brm5Fh) == "table" then
		bullet._brm5Fh = payload._brm5Fh
	end
	return bullet
end
local origUP = mod.UpdateParallel
mod.UpdateParallel = function(self, dt)
	origUP(self, dt)
	if self._local ~= true then return end
	local fh = self._brm5Fh
	if type(fh) == "table" then
		applyForceHitLanded(self, fh)
	end
end
]]):format(ACTOR_HOOK_VER, actorName)
	local ok, err = pcall(function()
		run_on_actor(actor, actorCode)
	end)
	if ok then
		State.actorBulletHooked = true
		State.actorBulletHookVer = ACTOR_HOOK_VER
		log("AIM", "Actor BulletClass hooks (_brm5Fh v" .. tostring(ACTOR_HOOK_VER) .. ")")
		return true
	end
	Bridge.reportError("installActorBulletHooks", err)
	return false
end

function Bridge.hookBulletClassMtSend(mod)
	local origMtSend = rawget(mod, "__brm5OrigMtSend") or mod._multithreadSend
	if type(origMtSend) ~= "function" then return false end
	if rawget(mod, "__brm5MtSendHook") then return true end
	rawset(mod, "__brm5OrigMtSend", origMtSend)
	rawset(mod, "__brm5MtSendHook", true)
	mod._multithreadSend = function(self, op, ...)
		if op == 2 and self._local ~= false and Bridge.shouldForceClientHit() then
			local part = select(3, ...)
			if part and Bridge.isEnemyHitPart(part) then
				self._brm5ForceHitSent = true
			else
				local args = Bridge.resolveForceHitArgs(self)
				if args then
					self._brm5ForceHitSent = true
					return origMtSend(self, 2, unpack(args))
				end
			end
		end
		return origMtSend(self, op, ...)
	end
	return true
end

function Bridge.installBulletForceHitHooks(bullet)
	if not bullet or bullet._local == false or not Bridge.shouldForceClientHit() then
		return
	end
	if bullet._brm5FhHooked then return end
	bullet._brm5FhHooked = true

	local origSend = bullet._multithreadSend
	if type(origSend) == "function" then
		bullet._multithreadSend = function(self, op, ...)
			if op == 2 and Bridge.shouldForceClientHit() then
				local part = select(3, ...)
				if part and Bridge.isEnemyHitPart(part) then
					self._brm5ForceHitSent = true
				elseif not part or not Bridge.isEnemyHitPart(part) then
					local args = Bridge.resolveForceHitArgs(self)
					if args then
						self._brm5ForceHitSent = true
						return origSend(self, 2, unpack(args))
					end
				end
			end
			return origSend(self, op, ...)
		end
	end

	if type(Bridge.patchBulletRayIgnore) == "function" then
		Bridge.patchBulletRayIgnore(bullet)
	end
end

function Bridge.forceHitOnBulletUpdate(bullet)
	Bridge.injectForceHitOp2OnBullet(bullet)
end

function Bridge.applyModifyPresetNoViewKick(ctx)
	if not ctx or not ctx.tune then return end
	ctx.tune.Recoil_Camera = 0
	ctx.tune.Recoil_KickBack = 0
	ctx.tune.RecoilForce_Tap = 0
	ctx.tune.RecoilForce_Impulse = 0
end

function Bridge.applyModifyPresetFastEquip(ctx)
	if not ctx or not ctx.tune then return end
	ctx.tune.Equip_Delay = 0
	for k, v in pairs(ctx.tune) do
		if type(k) == "string" and type(v) == "number" and v > 0 then
			local kl = string.lower(k)
			if (kl:find("equip", 1, true) or kl:find("holster", 1, true) or kl:find("draw", 1, true))
				and (kl:find("delay", 1, true) or kl:find("time", 1, true)) then
				ctx.tune[k] = 0
			end
		end
	end
end

function Bridge.installModifyRuntimeHooks(_ctx)
end

function Bridge.applyModifyPresetNoSway(ctx)
	if not ctx or not ctx.tune then return end
	for k, v in pairs(ctx.tune) do
		if type(k) == "string" and type(v) == "number" then
			if k:find("Sway", 1, true) or k:find("Shake", 1, true) or k:find("Bob", 1, true) then
				ctx.tune[k] = 0
			end
		end
	end
	local vm = ctx.actor and tableField(ctx.actor, "ViewModel")
	if type(vm) == "table" then
		for k, v in pairs(vm) do
			if type(k) == "string" and type(v) == "number" then
				if k:find("Sway", 1, true) or k:find("Shake", 1, true) or k:find("Bob", 1, true) then
					vm[k] = 0
				end
			end
		end
	end
end

function Bridge.applyModifyPresetLowDrag(ctx)
	if ctx.cal and type(ctx.cal.Drag) == "number" then
		ctx.cal.Drag = 0
	end
	local handler = ctx.handler
	if handler then
		local liveCal = Bridge.caliberFromHandler(handler)
		if type(liveCal) == "table" and type(liveCal.Drag) == "number" then
			liveCal.Drag = 0
		end
	end
end

function Bridge.applyModifyPresetRPM(ctx)
	if ctx.tune and CONFIG.ModifyRPMValue then
		ctx.tune.RPM = CONFIG.ModifyRPMValue
	end
end

function Bridge.applyModifyPresetNoSpeedPenalty(ctx)
	if not ctx or not ctx.tune then return end
	if type(ctx.tune.Speed_Penalty) == "number" then
		ctx.tune.Speed_Penalty = 0
	end
	for k, v in pairs(ctx.tune) do
		if type(k) == "string" and k:find("Speed_Penalty", 1, true) and type(v) == "number" then
			ctx.tune[k] = 0
		end
	end
end

function Bridge.applyModifyPresetLightWeight(ctx)
	if ctx.tune and type(ctx.tune.Weight) == "number" then
		ctx.tune.Weight = math.min(ctx.tune.Weight, 1)
	end
	if ctx.meta and type(ctx.meta.Weight) == "number" then
		ctx.meta.Weight = math.max(math.floor(ctx.meta.Weight * 0.15), 1)
	end
	local actor = Bridge.resolveWeaponActor(ctx)
	if actor and ctx.tune and type(ctx.tune.Weight) == "number" then
		actor.Weight = ctx.tune.Weight
	end
end

function Bridge.applyModifyPresetFlatBallistics(ctx)
	if ctx.cal and type(ctx.cal.BallisticCoeff) == "number" then
		ctx.cal.BallisticCoeff = ctx.cal.BallisticCoeff * 0.35
	end
	local handler = ctx.handler
	if handler then
		local liveCal = Bridge.caliberFromHandler(handler)
		if type(liveCal) == "table" and type(liveCal.BallisticCoeff) == "number" then
			liveCal.BallisticCoeff = liveCal.BallisticCoeff * 0.35
		end
	end
end

function Bridge.applyModifyPresetBulletSpeed(ctx)
	local v = CONFIG.ModifyBulletSpeedValue
	if type(v) ~= "number" or v <= 50 then return end
	local function applyCal(cal)
		if type(cal) ~= "table" then return end
		if type(cal.BaseVelocity) == "number" then cal.BaseVelocity = v end
		if type(cal.Speed) == "number" then cal.Speed = v end
		if type(cal.MuzzleVelocity) == "number" then cal.MuzzleVelocity = v end
	end
	if ctx.cal then applyCal(ctx.cal) end
	local handler = ctx.handler
	if handler then
		applyCal(Bridge.caliberFromHandler(handler))
	end
end

function Bridge.applyModifyPresetAlwaysChambered(ctx)
	if ctx.meta then
		rawset(ctx.meta, "Chamber", true)
	end
	if ctx.handler and ctx.handler._item and rawget(ctx.handler._item, "MetaData") then
		rawset(ctx.handler._item.MetaData, "Chamber", true)
	end
end

function Bridge.applyModifyPresetFullAuto(ctx)
	if not ctx then return end
	local handler = ctx.fluxHandler or ctx.handler
	local tune = ctx.tune
	if handler and handler._firearm and handler._firearm.Tune then
		tune = handler._firearm.Tune
	end
	if tune then
		local modes = tune.Firemodes
		if type(modes) ~= "table" then
			modes = { FIREMODE.Auto, FIREMODE.Semi, FIREMODE.Safe }
			tune.Firemodes = modes
		end
		local autoIdx = table.find(modes, FIREMODE.Auto)
		if not autoIdx then
			table.insert(modes, 1, FIREMODE.Auto)
			autoIdx = 1
		end
		if ctx.meta then
			rawset(ctx.meta, "Mode", autoIdx)
		end
		if handler and handler._item and rawget(handler._item, "MetaData") then
			rawset(handler._item.MetaData, "Mode", autoIdx)
		end
	end
	if handler then
		pcall(function()
			rawset(handler, "Mode", FIREMODE.Auto)
			rawset(handler, "_mode", FIREMODE.Auto)
			rawset(handler, "_firemode", FIREMODE.Auto)
			rawset(handler, "Firemode", FIREMODE.Auto)
			rawset(handler, "_currentFiremode", FIREMODE.Auto)
			rawset(handler, "_semi", false)
			rawset(handler, "_burst", false)
			rawset(handler, "_auto", true)
		end)
	end
	local vm = ctx.actor and tableField(ctx.actor, "ViewModel")
	if type(vm) == "table" then
		pcall(function()
			rawset(vm, "_semi", false)
			rawset(vm, "_auto", true)
		end)
	end
end

local MODIFY_APPLIERS = {
	NoViewKick = Bridge.applyModifyPresetNoViewKick,
	RPM = Bridge.applyModifyPresetRPM,
	FullAuto = Bridge.applyModifyPresetFullAuto,
	InstantBolt = Bridge.applyModifyPresetInstantBolt,
	FastEquip = Bridge.applyModifyPresetFastEquip,
	NoSway = Bridge.applyModifyPresetNoSway,
	NoSpeedPenalty = Bridge.applyModifyPresetNoSpeedPenalty,
	LightWeight = Bridge.applyModifyPresetLightWeight,
	FlatBallistics = Bridge.applyModifyPresetFlatBallistics,
	BulletSpeed = Bridge.applyModifyPresetBulletSpeed,
}

function Bridge.getModifyPresetInfo()
	return {
		NoViewKick = "Только визуальная отдача камеры (Recoil_Camera, KickBack)",
		RPM = "Выставляет скорострельность = ModifyRPMValue",
		FullAuto = "Принудительный режим Auto",
		InstantBolt = "Мгновенный перезаряд болта (Bolt_Action_*)",
		FastEquip = "Equip_Delay=0 в Tune (без runtime-хуков)",
		NoSway = "Убирает качание прицела (Sway/Shake/Bob)",
		NoSpeedPenalty = "Tune.Speed_Penalty = 0 — без замедления при стрельбе",
		LightWeight = "Снижает Tune.Weight и Meta.Weight",
		FlatBallistics = "Меньше BallisticCoeff — ровнее полёт пули",
		BulletSpeed = "Override скорости пули = ModifyBulletSpeedValue",
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- GUN MODS — переписано под реальное устройство игры (по дампу BRM5).
--
-- Что было не так раньше:
--   1. Резолвился РОВНО ОДИН ctx (ствол в руках) → моды не доезжали до
--      остальных стволов инвентаря. Это и есть баг «работает только на одно».
--   2. Патчился только handler._firearm.Tune. Но у каждого ствола ДВА
--      независимых _firearm:
--        • FirearmInventory handler   → RPM, Firemodes, Barrel_Spread,
--                                       Equip_Delay, Weight, перезарядка
--        • FirearmInventoryReplicator → ОТДАЧА (getRecoil), ADS_Speed, bolt
--      Поэтому NoRecoil «не работал»: отдача живёт во втором объекте.
--   3. Писали напрямую в Tune. Но Tune — это КЭШ: Calculate() пересобирает
--      его из конфигов и удаляет чужие ключи. Дёргается на каждом Equip,
--      Reload, вставке магазина, сошках, магнифере (_updateModel →
--      _firearm:Remove("Mag")). Отсюда «моды слетают после перезарядки».
--
-- Как правильно (так делает сама игра в своих дебаг-слайдерах):
--   писать в component.OverrideTune — он применяется ПОСЛЕДНИМ в Calculate,
--   поэтому переживает любой пересчёт. В Tune дублируем для мгновенного
--   эффекта до ближайшего Calculate.
--
-- Опасное, чего не делаем:
--   • Tune.Firemodes копируется ПО ССЫЛКЕ из общего конфига — мутация задела
--     бы все стволы этой модели. Всегда кладём НОВУЮ таблицу.
--   • handler._caliber — общая запись Calibers, одна на весь калибр. Не трогаем.
-- ═══════════════════════════════════════════════════════════════════════════

-- Собирает все живые firearm-компоненты игрока: и handler-, и replicator-side.
-- Возвращает массив { uid=, comp=, item=, kind="handler"|"replicator" }.
function Bridge.collectFirearmComponents()
	local out = {}
	local seen = {}
	local function push(uid, comp, item, kind)
		if type(comp) ~= "table" then return end
		local key = tostring(uid) .. "|" .. kind
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = { uid = uid, comp = comp, item = item, kind = kind }
	end

	-- 1) handler-side: InventoryService._inventories[1..4]
	--    Группы 1 и 2 — огнестрел; 4 смешанная, поэтому фильтруем по _firearm.
	local invSvc = Bridge.resolveInventoryService and Bridge.resolveInventoryService()
	local invs = type(invSvc) == "table" and rawget(invSvc, "_inventories")
	if type(invs) == "table" then
		for _, bucket in pairs(invs) do
			if type(bucket) == "table" then
				for _, entry in pairs(bucket) do
					-- entry.Handler бывает nil в момент удаления предмета
					local h = type(entry) == "table" and entry.Handler
					local fa = type(h) == "table" and rawget(h, "_firearm")
					if type(fa) == "table" then
						push(entry.UID, fa, rawget(h, "_item"), "handler")
					end
				end
			end
		end
	end

	-- 2) replicator-side: LocalActor._inventory[UID] — здесь живёт ОТДАЧА
	local _, actor = Bridge.resolveLocalActor(false)
	local rinv = type(actor) == "table" and rawget(actor, "_inventory")
	if type(rinv) == "table" then
		for uid, rep in pairs(rinv) do
			local fa = type(rep) == "table" and rawget(rep, "_firearm")
			if type(fa) == "table" then
				push(uid, fa, rawget(rep, "_item"), "replicator")
			end
		end
	end
	return out
end

-- Пишем значение так, чтобы оно пережило Calculate().
function Bridge.setOverrideTune(comp, key, value)
	if type(comp) ~= "table" then return end
	local ov = rawget(comp, "OverrideTune")
	if type(ov) ~= "table" then
		ov = {}
		pcall(function() comp.OverrideTune = ov end)
		if type(rawget(comp, "OverrideTune")) ~= "table" then return end
		ov = rawget(comp, "OverrideTune")
	end
	ov[key] = value
	local tune = rawget(comp, "Tune")
	if type(tune) == "table" then tune[key] = value end   -- мгновенный эффект
end

-- Применяет один пресет к ОДНОМУ компоненту.
--
-- Метод: отдаём пресету ПЛОСКУЮ КОПИЮ Tune, он свободно её мутирует (в том
-- числе через `for k,v in pairs(ctx.tune)` — так делают 6 пресетов), а потом
-- мы диффим копию с оригиналом и переносим только изменившееся в OverrideTune.
--
-- Почему не metatable-прокси: в Luau `pairs()` НЕ уважает __iter/__pairs, так
-- что пресеты с обходом таблицы молча не срабатывали бы (проверено).
local function applyPresetToComponent(fn, comp, item)
	local tune = rawget(comp, "Tune")
	if type(tune) ~= "table" then return end
	local copy = {}
	for k, v in pairs(tune) do copy[k] = v end
	local ok = pcall(fn, {
		tune = copy,
		item = item,
		meta = type(item) == "table" and rawget(item, "MetaData") or nil,
		-- cal НЕ отдаём: Calibers — ОБЩАЯ таблица на весь калибр, правка
		-- задела бы каждый ствол этого калибра у всех, и навсегда.
		cal  = nil,
	})
	if not ok then return end
	for k, v in pairs(copy) do
		if tune[k] ~= v then
			-- Firemodes и прочие таблицы копируются из конфига ПО ССЫЛКЕ —
			-- кладём свежую таблицу, иначе мутируем общий конфиг модели.
			if type(v) == "table" then
				local fresh = {}
				for i, vv in pairs(v) do fresh[i] = vv end
				v = fresh
			end
			Bridge.setOverrideTune(comp, k, v)
		end
	end
end

Bridge.applyWeaponModify = function(force)
	if not CONFIG.ModifyEnabled then return end
	local comps = Bridge.collectFirearmComponents()
	if #comps == 0 then return end

	-- Троттлим: полный проход не нужен каждый кадр. force обходит троттл.
	local t = os.clock()
	if not force and (t - (State.modifyLastPass or 0)) < (CONFIG.ModifyPassInterval or 0.5) then
		return
	end
	State.modifyLastPass = t

	for _, rec in ipairs(comps) do
		-- Бэкап один раз на компонент (по uid+kind), до первой правки
		Bridge.backupModifyComponent(rec)
		for name, enabled in pairs(CONFIG.ModifyPresets) do
			if enabled then
				local fn = MODIFY_APPLIERS[name]
				if fn then applyPresetToComponent(fn, rec.comp, rec.item) end
			end
		end
	end
	State.modifyAppliedCount = #comps
end

-- Бэкап хранится по ключу uid|kind, чтобы handler и replicator не затирали
-- снапшоты друг друга (у них РАЗНЫЕ значения одних и тех же полей).
function Bridge.backupModifyComponent(rec)
	local key = tostring(rec.uid) .. "|" .. rec.kind
	if State.modifyBackup[key] then return end
	local tune = rawget(rec.comp, "Tune")
	if type(tune) ~= "table" then return end
	local snap = { tune = {}, over = {} }
	for k, v in pairs(tune) do snap.tune[k] = v end
	local ov = rawget(rec.comp, "OverrideTune")
	if type(ov) == "table" then
		for k, v in pairs(ov) do snap.over[k] = v end
	end
	State.modifyBackup[key] = snap
end

function Bridge.restoreWeaponModify()
	-- Раньше: брался ОДИН peekWeaponContext и сверялся с каждым uid — совпадал
	-- максимум один, остальные снапшоты выбрасывались нетронутыми, но
	-- table.clear всё равно их стирал → откатить было уже нечем.
	-- Теперь идём по живым компонентам и чистим OverrideTune адресно.
	local comps = Bridge.collectFirearmComponents()
	for _, rec in ipairs(comps) do
		local key = tostring(rec.uid) .. "|" .. rec.kind
		local snap = State.modifyBackup[key]
		if snap then
			local ov = rawget(rec.comp, "OverrideTune")
			if type(ov) == "table" then
				-- убираем ТОЛЬКО наши ключи, чужие overrides не трогаем
				for k in pairs(ov) do
					if snap.over[k] == nil then ov[k] = nil end
				end
				for k, v in pairs(snap.over) do ov[k] = v end
			end
			local tune = rawget(rec.comp, "Tune")
			if type(tune) == "table" then
				for k, v in pairs(snap.tune) do tune[k] = v end
			end
			-- Просим игру пересобрать Tune из конфигов — самый чистый откат
			pcall(function() rec.comp:Calculate() end)
		end
	end
	table.clear(State.modifyBackup)
	State.modifyAppliedCount = 0
end

-- ============================================================
-- BULLET EVENT — только локальные попадания
-- ============================================================

-- isLocalBulletPayload / isLocalBulletEvent — только в BRM5Lib_v1.lua
-- Формат BulletEvent op=2: origin, hitPos, part, normal, material, caliber, isLocal
-- Формат Receive batch op=2: {2, origin, hitPos, part, normal, material, caliber, isLocal}
-- Формат Receive batch op=1 (Landed): {1, uid, replicate, hitPos, part, normal, material, timeOff}

function Bridge.installBulletEventLogger()
	if CONFIG.LogBulletEvent ~= true then
		return false
	end
	local bulletEvent = RF:FindFirstChild("BulletEvent")
	if not bulletEvent or not bulletEvent:IsA("BindableEvent") then
		log("BULLET", "BulletEvent not found")
		return false
	end
	if State.bulletLogConn then
		pcall(function() State.bulletLogConn:Disconnect() end)
		State.bulletLogConn = nil
	end
	State.bulletLogConn = bulletEvent.Event:Connect(function(op, ...)
		if CONFIG.BulletLogHitsOnly and op ~= 1 and op ~= 2 then
			return
		end
		local args = { ... }
		if CONFIG.LocalBulletsOnly then
			local isOurs = Bridge.isOurBulletEvent
			if type(isOurs) == "function" and not isOurs(op, args) then
				return
			end
		end
		local now = os.clock()
		if now - (State.lastBulletLog or 0) < (CONFIG.BulletLogThrottle or 0.12) then
			return
		end
		State.lastBulletLog = now
		local hitPart, isLocalFlag
		if op == 1 then
			hitPart = args[4]
			isLocalFlag = true
		elseif op == 2 then
			hitPart = args[3]
			isLocalFlag = args[7]
		end
		if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") then
			if type(Bridge.logBulletHit) == "function" then
				Bridge.logBulletHit(op, hitPart, isLocalFlag, "logger")
			else
				log("BULLET", "hit", "part", hitPart.Name, "op", op)
			end
		elseif CONFIG.LogBulletPayload or CONFIG.LogBulletEvent then
			log("BULLET", "event", "op=" .. tostring(op), "argc=" .. tostring(#args),
				"isLocal=" .. tostring(isLocalFlag))
		end
		-- Трейсеры только через markLocalBulletUid / spawnTracerForMyBullet
	end)
	log("BULLET", "logger connected", "hitsOnly=" .. tostring(CONFIG.BulletLogHitsOnly))
	return true
end

-- ============================================================
-- ESP
-- ============================================================

-- Дубль удалён: байт-в-байт копия Bridge.extractWeaponMagFromItem из
-- library.lua. Дублирование только создавало риск, что версии разъедутся.
-- Дубль удалён: копия из library.lua, причём обе версии не вызывались
-- ниоткуда. Оставлена одна, библиотечная.
local function tickFullAutoAssist()
	if not CONFIG.ModifyEnabled or not CONFIG.ModifyPresets.FullAuto then return end
	local ctx = Bridge.getCachedWeaponContext()
	if ctx then
		Bridge.applyModifyPresetFullAuto(ctx)
	end
end

local function resetAfterRespawn()
	State.localPlayerAlive = true
	State.playerInventory = nil
	State.changeHookOwner = nil
	State.handItem = nil
	State.handSlot = nil
	State.cachedHudHandUid = nil
	State.modifyAppliedUid = nil
	-- После респавна InventoryService пересоздаёт _inventories/_inventory
	-- (_cleanInventory), значит все прежние компоненты мертвы: сбрасываем
	-- троттл и кэш сервиса, чтобы моды сразу легли на новые стволы.
	State.modifyLastPass = 0
	State.modifyAppliedCount = 0
	State.invSvcCache = nil
	State.handHookTime = 0
	table.clear(State.modifyBackup)
	State.localClient = nil
	State.fluxInventoryService = nil
	State.fluxInventoryResolved = false
	State.fluxHandlerCache = nil
	State.fluxFireHandlerCache = nil
	State.fluxImportHandlerCache = nil
	State.fluxResolveFailUntil = nil
	State.fluxSharedRef = nil
	State.weaponHudLogged = false
	State.trackHandPending = false  -- v19 PATCH: сброс debounce флага при ресете
	-- v19 PATCH: сброс __brm5Hooked на si объекте — иначе hookSharedInventoryTable
	-- делает early return даже после invCaptureInstalled=false (require кэширует si)
	if State.sharedInventorySiRef then
		rawset(State.sharedInventorySiRef, "__brm5Hooked", nil)
		State.sharedInventorySiRef = nil
	end
	State.invCaptureInstalled = false
	-- v20 PATCH: сброс hudRefreshing — иначе refreshWeaponCache(force=true) блокируется вторым guard
	State.hudRefreshing = false
	State.lastWeaponRefresh = 0
	State.lastHandRediscover = 0
	State.lastInventoryGc = 0
	State.lastInventoryGcResult = nil
	State.lastInventoryGcScore = 0
	State.hudLastLines = { "[Weapon]", "HANDS: scanning...", "respawn" }
	pcall(Bridge.syncWeaponHud, State.hudLastLines)
	-- v18 PATCH: сброс locked resolvers — без ��того resolveEquippedHand использует метод от старого ��л��ента
	State.methods = {}
	-- v18 PATCH: сброс weapon context cache
	State.weaponCtxCache = nil
	State.weaponCtxCacheTime = 0
	State.fovWeaponCtx = nil
	State.lastFovWeaponCheck = 0
	-- v15: сброс кэшей при респауне
	State.resolverCache = nil
	State.espBatchIndex = 0
	State.espActorList = {}
	State.espActorListTime = 0
	State.lastCacheGc = 0
	table.clear(State.multiPointCache)
	table.clear(State.spoofMuzzleCache)
	table.clear(State.losRaycastCache)
	table.clear(State.espVisibleCache)
	task.defer(function()
		if not State.running then return end
		resolveLocalPlayer()
		resolveLocalClient(true)
		local mods = Bridge.loadSharedModules()
		Bridge.installInventoryHooks(mods)
		Bridge.resolvePlayerInventory(true)
		Bridge.installSilentAim()
		if type(Bridge.schedulePostRespawnWeaponRediscover) == "function" then
			Bridge.schedulePostRespawnWeaponRediscover()
		else
			Bridge.requestHudRefresh(true)
		end
		log("INIT", "respawn: inventory + hooks rebound")
	end)
	-- v21: fallback rediscover если handler ещё не поднялся
	task.delay(1.5, function()
		if not State.running then return end
		local ctx = type(Bridge.getLiveWeaponContext) == "function"
			and Bridge.getLiveWeaponContext(true) or nil
		if type(Bridge.weaponContextValid) == "function" and Bridge.weaponContextValid(ctx) then return end
		if type(Bridge.rediscoverEquippedWeapon) == "function" then
			Bridge.rediscoverEquippedWeapon(true)
		end
		State.hudRefreshing = false
		Bridge.requestHudRefresh(true)
	end)
end

-- ============================================================
-- Silent Aim thread (отдельный поток, не блокирует ESP/Lib)
-- ============================================================
local aimConn
local function startAimThread()
	local lastHookRetry = 0
	-- FIX v12: создаём FOV circle при старте thread (не при хите)
	ensureFovCircle()
	aimConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not State.running then return end
		local ok, err = pcall(function()
		local t = os.clock()
		local combatActive = Bridge.combatAimActive()

		if t - (State.lastCacheGc or 0) >= (CONFIG.CacheGcInterval or 10.0) then
			Bridge.pruneAllCaches(t)
			if type(Bridge.prunePendingBulletShots) == "function" then
				Bridge.prunePendingBulletShots(t)
			end
		end

		if type(Bridge.tickHandRediscoverIfNeeded) == "function" then
			Bridge.tickHandRediscoverIfNeeded()
		end

		if combatActive and (CONFIG.SilentAim or mpActive())
			and t - (State.lastCombatAimRefresh or 0) >= (CONFIG.CombatAimRefreshInterval or 0.08) then
			State.lastCombatAimRefresh = t
			Bridge.refreshAimTarget(Bridge.getAimLosOrigin(), mpActive())
		end

		if State.awaitingServerDischarge and t - (State.shotBurstT or 0) > 0.15 then
			State.awaitingServerDischarge = false
			State.pendingBulletSpawns = nil
		end

		-- FullAuto modify assist (LMB)
		tickFullAutoAssist()
		-- Weapon Mods re-apply. IMPORTANT: this must run whenever ModifyEnabled is on,
		-- NOT only when FullAuto is set — otherwise mods (NoRecoil/NoSpread/etc.) never
		-- re-apply on weapon switch and end up missing on many weapons. applyWeaponModify
		-- (force=false) is cheap: it early-returns when the held weapon's uid is unchanged.
		if CONFIG.ModifyEnabled
			and t - (State.lastFullAutoApply or 0) > (CONFIG.ModifyReapplyInterval or 1.0) then
			State.lastFullAutoApply = t
			Bridge.applyWeaponModify(false)
		end

		-- Hook retry (не каждый кадр — раз в 4с)
		local hooksReady = State.namecallHooked and State.networkDischargeHooked
			and State.bulletEventHooked
			and (State.namecallHookVer or 0) >= 18
		if not hooksReady and t - lastHookRetry >= (State.hookGcCooldown or 4) then
			lastHookRetry = t
			Bridge.installSilentAim()
		elseif combatActive
			and (not State.firearmHooked or not State.networkDischargeHooked) then
			if t - lastHookRetry >= (State.hookGcCooldown or 4) then
				lastHookRetry = t
				Bridge.installSilentAim()
			end
		end

		-- ESP обновляется в BRM5ESP_v2 Heartbeat — не дублируем здесь
		-- FIX: единый гейт «в руках огнестрел». combatAimActive уже требует
		-- firearm-контекст, но он завязан ещё и на CONFIG.SilentAim — поэтому
		-- при выключенном SilentAim визуалы могли жить своей жизнью, в том
		-- числе с ножом в руках. Теперь считаем признак один раз за кадр и
		-- гасим ВСЕ визуалы прицеливания, если ствола нет.
		local haveFirearm = combatActive
		if not haveFirearm then
			local wc = Bridge.peekWeaponContext and Bridge.peekWeaponContext(1.5)
			if wc and wc.isMelee ~= true and wc.tune ~= nil then
				local cal = wc.info and wc.info.caliber
				haveFirearm = type(cal) ~= "string" or (cal ~= "melee" and cal ~= "")
			end
		end
		State.saHaveFirearm = haveFirearm
		if CONFIG.AimVisuals and combatActive and haveFirearm then
			Bridge.updateAimVisuals()
		else
			Bridge.hideAimViz()
		end
		if not haveFirearm then
			-- ножом трейсеры/маркеры не рисуем вообще
			if Bridge.clearShotTracers then pcall(Bridge.clearShotTracers) end
		end

		-- FIX v11: FOV Circle — показывается только при наличии огнестрельного оружия И включённом SilentAim
		do
			local fc = State.fovCircle
			if fc then
				local wantShow = CONFIG.FovCircle == true and CONFIG.SilentAim == true
					and State.saHaveFirearm ~= false
				if wantShow then
					local fovCheckT = State.lastFovWeaponCheck or 0
					local wCtx = State.fovWeaponCtx
					if t - fovCheckT >= 0.5 then
						State.lastFovWeaponCheck = t
						wCtx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
							or Bridge.peekWeaponContext(1.2)
						State.fovWeaponCtx = wCtx
					end
					local isFirearm = false
					if wCtx and wCtx.info then
						local cal = wCtx.info.caliber
						isFirearm = type(cal) == "string" and cal ~= "melee" and cal ~= ""
					end
					wantShow = isFirearm
				end
				if wantShow then
					local cam = workspace.CurrentCamera
					local vp  = cam and cam.ViewportSize
					if vp and vp.X > 0 and vp.Y > 0 then
						local fovDeg = CONFIG.SilentAimFOV or 15
						local halfFov = math.rad(fovDeg * 0.5)
						local focalLen = (vp.Y * 0.5) / math.tan(math.rad((cam.FieldOfView or 70) * 0.5))
						local radiusPx = math.tan(halfFov) * focalLen
						fc.Position    = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
						fc.Radius      = math.max(radiusPx, 1)
						fc.Color       = CONFIG.FovCircleColor or Color3.fromRGB(255, 255, 255)
						-- FIX: Thickness и Filled выставлялись ТОЛЬКО при создании
						-- круга (ensureFovCircle) и потом не обновлялись — ползунок
						-- толщины и тумблер Filled в UI не делали ничего.
						fc.Thickness   = CONFIG.FovCircleThickness or 1
						fc.Filled      = CONFIG.FovCircleFilled == true
						-- FIX: у Potassium Transparency ИНВЕРТИРОВАН (1 = видимо).
						-- Тут писалось сырое значение конфига, поэтому ползунок
						-- «Transparency» работал наоборот: 0% давал невидимый круг,
						-- 100% — полностью непрозрачный. Идём через showDrawing.
						Bridge.showDrawing(fc, 1 - (CONFIG.FovCircleTransparency or 0.5))
					else
						fc.Visible = false
					end
				else
					fc.Visible = false
				end
			end
		end

		-- ShotTracers
		if CONFIG.ShotTracers then
			Bridge.updateShotTracers()
		end

		end)
		if not ok then
			log("ERR", "SilentAim heartbeat", tostring(err))
		end
	end)
end

local function stopAimThread()
	if aimConn then aimConn:Disconnect(); aimConn = nil end
	Bridge.clearAimVisuals()
	-- FIX v11: cleanup FOV circle
	if State.fovCircle then
		Bridge.destroyDrawing(State.fovCircle)
		State.fovCircle = nil
	end
end

local SilentAim = {
	start  = function()
		brm5Global().State = State
		State.running = true
		-- FIX (хитсаунды кроме Default не работали, и не только они): здесь
		-- SA_CONFIG заливался в CONFIG БЕЗУСЛОВНО. Дефолты уже применены при
		-- загрузке модуля (строка ~247), а этот повторный проход при каждом
		-- start() затирал всё, что успел выставить пользователь или
		-- автозагрузка конфига MacLib — HitSoundName возвращался в "Default",
		-- цвета/громкость/пресеты тоже. Дозаливаем только НЕДОСТАЮЩИЕ ключи.
		for k, v in pairs(SA_CONFIG) do
			if Bridge.CONFIG[k] == nil then Bridge.CONFIG[k] = v end
		end
		if type(Bridge.installCharacterLifecycle) == "function" then
			Bridge.installCharacterLifecycle(resetAfterRespawn)
		end
		if type(Bridge.tickRepSyncBatch) == "function" then
			task.defer(function()
				Bridge.tickRepSyncBatch(16)
			end)
		end
		Bridge.requestHudRefresh(true)
		-- установка хуков с retry
		task.spawn(function()
			for attempt = 1, 30 do
				if not State.running then return end
				if not LP.Character then
					LP.CharacterAdded:Wait(); task.wait(1)
				end
				if Bridge.installSilentAim() then
					if State.namecallHooked
						and State.networkDischargeHooked
						and State.bulletEventHooked
						and (State.namecallHookVer or 0) >= 18 then
						break
					end
				end
				task.wait(0.5)
			end
		end)
		startAimThread()
	end,
	stop   = stopAimThread,
	cycleAimVisualStyle = function()
		return Bridge.cycleAimVisualStyle()
	end,
	Bridge = Bridge,
}

-- ─────────────────────────────────────────────────────────────────────────
-- UI-интеграция (MacLib). Лоадер вызывает M.buildUI(ui) ПОСЛЕ start().
--   ui.tabs   = { SilentAim, KillAura, GunMods, Movement, Visuals, Misc }
--   ui.notify = function(title, desc)
--   ui.flag   = function(name) -> уникальный флаг
-- Каждый колбэк пишет прямо в CONFIG (= Lib.CONFIG), который модуль читает в рантайме.
-- ─────────────────────────────────────────────────────────────────────────
function SilentAim.buildUI(ui)
	local tabSA = ui.tabs and ui.tabs.SilentAim
	local tabGM = ui.tabs and ui.tabs.GunMods
	local K = Bridge.makeUiKit(ui)

	if tabSA then
		-- ═══ LEFT: сама фича и выбор цели ══════════════════════════════
		local L = tabSA:Section({ Side = "Left" })

		K.feature(L, {
			Title = "Silent Aim", Flag = "SilentAim",
			get = function() return CONFIG.SilentAim end,
			set = function(v) CONFIG.SilentAim = v end,
			Desc = "ur shots land on the best target in the fov\nbind works on PC + mobile",
		})
		K.slider(L, { Name = "FOV", Flag = "FOV", Default = CONFIG.SilentAimFOV,
			Min = 10, Max = 360, Suffix = "°",
			Callback = function(v) CONFIG.SilentAimFOV = v end,
			Desc = "360 = anyone on screen" })
		K.slider(L, { Name = "Max Distance", Flag = "MaxDist", Default = CONFIG.SilentAimMaxDistance,
			Min = 50, Max = 2000, Suffix = " st",
			Callback = function(v) CONFIG.SilentAimMaxDistance = v end })
		K.dropdown(L, {
			Name = "Target Bone", Flag = "Bone",
			Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
			Default = CONFIG.SilentAimBone or "Head",
			Callback = function(v) CONFIG.SilentAimBone = v end,
		})
		K.toggle(L, { Name = "Force Zero Spread", Flag = "ZeroSpread", Title = "Zero Spread",
			get = function() return CONFIG.ForceZeroSpread end,
			set = function(v) CONFIG.ForceZeroSpread = v end })

		K.group(L, "Who To Hit")
		K.toggle(L, { Name = "Players", Flag = "TgtPlayers", Title = "Target Players",
			get = function() return CONFIG.SilentAimTargetPlayers end,
			set = function(v) CONFIG.SilentAimTargetPlayers = v end })
		K.toggle(L, { Name = "Hostiles / NPCs", Flag = "TgtHostile", Title = "Target Hostiles",
			get = function() return CONFIG.SilentAimTargetHostile end,
			set = function(v) CONFIG.SilentAimTargetHostile = v end })
		K.toggle(L, { Name = "Prefer Players", Flag = "PreferPlayers", Title = "Prefer Players",
			get = function() return CONFIG.SilentAimPreferPlayers end,
			set = function(v) CONFIG.SilentAimPreferPlayers = v end,
			Desc = "picks a real player over an npc at the same range" })

		K.group(L, "Who To Skip")
		K.toggle(L, { Name = "Ignore NPCs", Flag = "IgnoreNpc", Title = "Ignore NPCs",
			get = function() return CONFIG.SilentAimIgnoreNpc end,
			set = function(v) CONFIG.SilentAimIgnoreNpc = v end })
		K.toggle(L, { Name = "Ignore PVE Players", Flag = "IgnorePvePlayers", Title = "Ignore PVE Players",
			get = function() return CONFIG.SilentAimIgnorePlayersInPve end,
			set = function(v) CONFIG.SilentAimIgnorePlayersInPve = v end })
		K.toggle(L, { Name = "Team Check", Flag = "TeamCheck", Title = "Team Check",
			get = function() return CONFIG.TeamCheck end,
			set = function(v) CONFIG.TeamCheck = v end })
		K.toggle(L, { Name = "Ignore Teammates", Flag = "IgnoreTeammates", Title = "Ignore Teammates",
			get = function() return CONFIG.IgnoreTeammates end,
			set = function(v) CONFIG.IgnoreTeammates = v end })
		K.toggle(L, { Name = "Skip Dead", Flag = "SkipDead", Title = "Skip Dead",
			get = function() return CONFIG.AimSkipDeadHP end,
			set = function(v) CONFIG.AimSkipDeadHP = v end })

		-- ═══ RIGHT: точность ═══════════════════════════════════════════
		local R = tabSA:Section({ Side = "Right" })
		R:Header({ Name = "Resolver" })
		local resEls = {}
		local function resVis() K.setVisible(resEls, CONFIG.ResolverLite ~= false) end
		K.toggle(R, { Name = "Resolver Lite", Flag = "ResolverLite", Title = "Resolver Lite",
			get = function() return CONFIG.ResolverLite end,
			set = function(v) CONFIG.ResolverLite = v end,
			after = resVis,
			Desc = "aims at a part thats actually exposed\nless shots eaten by walls" })
		resEls[#resEls + 1] = K.slider(R, { Name = "Inset", Flag = "ResInset",
			Default = math.floor((CONFIG.ResolverLiteInset or 0.1) * 100),
			Min = 0, Max = 40, Suffix = "%",
			Callback = function(v) CONFIG.ResolverLiteInset = v / 100 end,
			Desc = "pulls the aim point in from the edge of the part" })
		resVis()

		K.group(R, "MultiPoint")
		local mpEls = {}
		local function mpVis() K.setVisible(mpEls, CONFIG.LiteMultiPoint ~= false) end
		-- Старый тумблер "MultiPoint" удалён: Bridge.setMultiPointMode всегда
		-- выставляет CONFIG.MultiPoint = false, так что галочка ничего не
		-- делала. Рабочий режим — только Lite MultiPoint.
		K.toggle(R, { Name = "Lite MultiPoint", Flag = "LiteMP", Title = "Lite MultiPoint",
			get = function() return CONFIG.LiteMultiPoint end,
			set = function(v) CONFIG.LiteMultiPoint = v end,
			after = mpVis,
			Desc = "tries several bones til one is hittable\nonly for close targets" })
		mpEls[#mpEls + 1] = K.slider(R, { Name = "Lite Max Distance", Flag = "LiteMPDist",
			Default = CONFIG.LiteMultiPointMaxDist, Min = 2, Max = 30, Suffix = " st",
			Callback = function(v) CONFIG.LiteMultiPointMaxDist = v end })
		mpEls[#mpEls + 1] = K.slider(R, { Name = "Lite Max Actors", Flag = "LiteMPActors",
			Default = CONFIG.LiteMultiPointMaxActors, Min = 1, Max = 10,
			Callback = function(v) CONFIG.LiteMultiPointMaxActors = v end })
		mpVis()

		K.group(R, "Force Hit")
		K.toggle(R, { Name = "Force Hit", Flag = "ForceHit", Title = "Force Hit",
			get = function() return CONFIG.ForceHit end,
			set = function(v) CONFIG.ForceHit = v end })
		K.toggle(R, { Name = "Force Client Hit", Flag = "ForceClientHit", Title = "Force Client Hit",
			get = function() return CONFIG.ForceClientHit end,
			set = function(v) CONFIG.ForceClientHit = v end,
			Desc = "marks bullets as hits on ur side\nturn off if u start getting kicked" })

		K.group(R, "Prediction")
		K.toggle(R, { Name = "Ballistic", Flag = "Prediction", Title = "Prediction",
			get = function() return CONFIG.Prediction end,
			set = function(v) CONFIG.Prediction = v end,
			Desc = "leads the target using real bullet speed n drop" })
		local plEls = {}
		local function plVis() K.setVisible(plEls, CONFIG.PredictionLite ~= false) end
		K.toggle(R, { Name = "Light Prediction", Flag = "PredLite", Title = "Light Prediction",
			get = function() return CONFIG.PredictionLite end,
			set = function(v) CONFIG.PredictionLite = v end,
			after = plVis,
			Desc = "flat lead time instead of the full math" })
		plEls[#plEls + 1] = K.slider(R, { Name = "Lead Time", Flag = "PredLiteTime",
			Default = math.floor((CONFIG.PredictionLiteTime or 0.1) * 1000),
			Min = 0, Max = 500, Suffix = " ms",
			Callback = function(v) CONFIG.PredictionLiteTime = v / 1000 end })
		plVis()
		K.toggle(R, { Name = "Vertical", Flag = "PredVert", Title = "Vertical Prediction",
			get = function() return CONFIG.PredictionVertical end,
			set = function(v) CONFIG.PredictionVertical = v end })
		K.toggle(R, { Name = "Ping Compensation", Flag = "PingComp", Title = "Ping Compensation",
			get = function() return CONFIG.PingCompensation end,
			set = function(v) CONFIG.PingCompensation = v end })

		-- ═══ LEFT #2: визуал ═══════════════════════════════════════════
		local V = tabSA:Section({ Side = "Left" })

		local fovEls = {}
		local function fovVis() K.setVisible(fovEls, CONFIG.FovCircle ~= false) end
		K.feature(V, {
			Title = "FOV Circle", Flag = "FovCircle", NoKeybind = true,
			get = function() return CONFIG.FovCircle end,
			set = function(v) CONFIG.FovCircle = v; fovVis() end,
		})
		fovEls[#fovEls + 1] = K.color(V, { Name = "Color", Flag = "FovColor",
			Default = CONFIG.FovCircleColor,
			Callback = function(c) CONFIG.FovCircleColor = c end })
		fovEls[#fovEls + 1] = K.toggle(V, { Name = "Filled", Flag = "FovFilled", Title = "Filled",
			get = function() return CONFIG.FovCircleFilled end,
			set = function(v) CONFIG.FovCircleFilled = v end })
		fovEls[#fovEls + 1] = K.slider(V, { Name = "Thickness", Flag = "FovThick",
			Default = CONFIG.FovCircleThickness, Min = 1, Max = 6,
			Callback = function(v) CONFIG.FovCircleThickness = v end })
		fovEls[#fovEls + 1] = K.slider(V, { Name = "Transparency", Flag = "FovTransp",
			Default = math.floor((CONFIG.FovCircleTransparency or 0.6) * 100),
			Min = 0, Max = 100, Suffix = "%",
			Callback = function(v) CONFIG.FovCircleTransparency = v / 100 end })
		fovVis()

		K.group(V, "Aim Marker")
		local mkEls, swasEls = {}, {}
		local function mkVis()
			K.setVisible(mkEls, CONFIG.AimVisuals ~= false)
			-- RGB-перелив есть только у свастики — прячем для остальных стилей
			K.setVisible(swasEls, CONFIG.AimVisuals ~= false
				and (CONFIG.AimVisualStyle == "Swastika"), true)  -- режим, скрываем всегда
		end
		K.toggle(V, { Name = "Enabled", Flag = "AimVisuals", Title = "Aim Marker",
			get = function() return CONFIG.AimVisuals end,
			set = function(v) CONFIG.AimVisuals = v end,
			after = mkVis,
			Desc = "marker on whoever ur locked on" })
		mkEls[#mkEls + 1] = K.dropdown(V, {
			Name = "Style", Flag = "AimStyle",
			Options = { "Default", "DefaultV2", "CrossGap", "Diamond", "Swastika" },
			Default = CONFIG.AimVisualStyle or "Default",
			Callback = function(v) CONFIG.AimVisualStyle = v end,
			after = mkVis,
		})
		mkEls[#mkEls + 1] = K.slider(V, { Name = "Scale", Flag = "AimScale",
			Default = math.floor((CONFIG.AimVisualScale or 0.5) * 100),
			Min = 20, Max = 200, Suffix = "%",
			Callback = function(v) CONFIG.AimVisualScale = v / 100 end })
		mkEls[#mkEls + 1] = K.color(V, { Name = "Color", Flag = "AimColor",
			Default = CONFIG.AimVisualColor or Color3.fromRGB(255, 60, 60),
			Callback = function(c) CONFIG.AimVisualColor = c end })
		mkEls[#mkEls + 1] = K.slider(V, { Name = "Transparency", Flag = "AimTransp",
			Default = math.floor((CONFIG.AimVisualTransparency or 0) * 100),
			Min = 0, Max = 100, Suffix = "%",
			Callback = function(v) CONFIG.AimVisualTransparency = v / 100 end })
		swasEls[#swasEls + 1] = K.toggle(V, { Name = "RGB", Flag = "SwasRGB", Title = "Marker RGB",
			get = function() return CONFIG.SwastikaRGB end,
			set = function(v) CONFIG.SwastikaRGB = v end })
		mkVis()

		K.group(V, "Lines")
		K.toggle(V, { Name = "Muzzle Line", Flag = "MuzzleVisual", Title = "Muzzle Line",
			get = function() return CONFIG.MuzzleVisual end,
			set = function(v) CONFIG.MuzzleVisual = v end,
			Desc = "line from the barrel to where the shot actually goes" })
		K.color(V, { Name = "Line Color", Flag = "MuzzleColor",
			Default = CONFIG.MuzzleLineColor or Color3.fromRGB(80, 220, 255),
			Callback = function(c) CONFIG.MuzzleLineColor = c end })
		K.slider(V, { Name = "Line Thickness", Flag = "MuzzleThick",
			Default = math.floor((CONFIG.MuzzleLineThickness or 2) * 10), Min = 5, Max = 60,
			Callback = function(v) CONFIG.MuzzleLineThickness = v / 10 end })
		K.slider(V, { Name = "Line Transparency", Flag = "MuzzleTransp",
			Default = math.floor((CONFIG.MuzzleLineTransparency or 0.15) * 100),
			Min = 0, Max = 95, Suffix = "%",
			Callback = function(v) CONFIG.MuzzleLineTransparency = v / 100 end })



		-- ═══ RIGHT #2: фидбэк ══════════════════════════════════════════
		local F = tabSA:Section({ Side = "Right" })
		F:Header({ Name = "Hit Sound" })
		K.toggle(F, { Name = "Enabled", Flag = "HitSound", Title = "Hit Sound",
			get = function() return CONFIG.HitSound end,
			set = function(v) CONFIG.HitSound = v end,
			Desc = "plays a sound when u land a hit" })
		K.dropdown(F, { Name = "Sound", Flag = "HitSoundName",
			Options = Bridge.HIT_SOUND_ORDER or { "Default" },
			Default = CONFIG.HitSoundName or "Default",
			Callback = function(v)
				CONFIG.HitSoundName = v
				CONFIG.HitSoundId = nil   -- имя перебивает ручной override
			end,
			after = function() pcall(Bridge.playLocalHitSound) end,  -- превью
		})
		K.slider(F, { Name = "Volume", Flag = "HitSoundVol",
			Default = math.floor((CONFIG.HitSoundVolume or 0.85) * 100),
			Min = 0, Max = 100, Suffix = "%",
			Callback = function(v) CONFIG.HitSoundVolume = v / 100 end })
		K.slider(F, { Name = "Pitch", Flag = "HitSoundPitch",
			Default = math.floor((CONFIG.HitSoundPitch or 1) * 100),
			Min = 50, Max = 200, Suffix = "%",
			Callback = function(v) CONFIG.HitSoundPitch = v / 100 end,
			Desc = "100 = normal speed" })
		K.button(F, { Name = "Preview", Flag = "HitSoundTest", Title = "Hit Sound",
			Callback = function()
				pcall(Bridge.playLocalHitSound)
				return "played"
			end })

		K.group(F, "Hit Particles")
		K.toggle(F, { Name = "Enabled", Flag = "HitParticles", Title = "Hit Particles",
			get = function() return CONFIG.HitParticles end,
			set = function(v) CONFIG.HitParticles = v end,
			Desc = "3d burst at the point u hit" })
		K.dropdown(F, { Name = "Style", Flag = "HpType",
			Options = { "Sparks", "Orbs", "Wireframe" },
			Default = CONFIG.HitParticleType or "Wireframe",
			Callback = function(v) CONFIG.HitParticleType = v end,
			Desc = "Sparks = flying streaks\nOrbs = glowing dots\nWireframe = spinning cages" })
		K.slider(F, { Name = "Count", Flag = "HpCount",
			Default = CONFIG.HitParticleCount, Min = 8, Max = 48,
			Callback = function(v) CONFIG.HitParticleCount = v end,
			Desc = "more = prettier but heavier" })
		K.slider(F, { Name = "Duration", Flag = "HpDur",
			Default = math.floor((CONFIG.HitParticleDuration or 1) * 1000),
			Min = 300, Max = 3000, Suffix = " ms",
			Callback = function(v) CONFIG.HitParticleDuration = v / 1000 end })
		K.slider(F, { Name = "Size", Flag = "HpSize",
			Default = math.floor((CONFIG.HitParticleOrbSize or 1) * 100),
			Min = 30, Max = 300, Suffix = "%",
			Callback = function(v)
				CONFIG.HitParticleOrbSize = v / 100
				CONFIG.HitParticleSparkSize = v / 100
			end })
		K.slider(F, { Name = "Speed", Flag = "HpSpeed",
			Default = CONFIG.HitParticleSpeedMax or 22, Min = 5, Max = 60,
			Callback = function(v) CONFIG.HitParticleSpeedMax = v end,
			Desc = "how hard the burst throws them out" })
		K.slider(F, { Name = "Gravity", Flag = "HpGrav",
			Default = math.floor(-(CONFIG.HitParticleGravity or -32)), Min = 0, Max = 90,
			Callback = function(v) CONFIG.HitParticleGravity = -v end,
			Desc = "0 = float in place, 90 = drop like rocks" })
		K.color(F, { Name = "Color A", Flag = "HpColA",
			Default = CONFIG.HitParticleColorA,
			Callback = function(c) CONFIG.HitParticleColorA = c end })
		K.color(F, { Name = "Color B", Flag = "HpColB",
			Default = CONFIG.HitParticleColorB,
			Callback = function(c) CONFIG.HitParticleColorB = c end })
		K.toggle(F, { Name = "Orb Glow", Flag = "HpOrbGlow", Title = "Orb Glow",
			get = function() return CONFIG.HitParticleOrbGlow ~= false end,
			set = function(v) CONFIG.HitParticleOrbGlow = v end,
			Desc = "halo ring around each orb, Orbs style only" })

	end

	-- ═══ RIGHT #3: Bullet Tracers — своя секция ════════════════════════
	if tabSA then
		local T = tabSA:Section({ Side = "Right" })
		local trEls = {}
		local function trVis() K.setVisible(trEls, CONFIG.ShotTracers ~= false) end
		K.feature(T, {
			Title = "Bullet Tracers", Flag = "ShotTracers", NoKeybind = true,
			get = function() return CONFIG.ShotTracers end,
			set = function(v) CONFIG.ShotTracers = v; trVis() end,
			Desc = "draws the path of ur own shots",
		})
		K.color(T, { Name = "Color", Flag = "TracerColor",
			Default = CONFIG.TracerColor or Color3.fromRGB(255, 90, 35),
			Callback = function(c) CONFIG.TracerColor = c end })
		K.slider(T, { Name = "Thickness", Flag = "TracerThick",
			Default = math.floor((CONFIG.TracerThickness or 0.9) * 10),
			Min = 5, Max = 40,
			Callback = function(v) CONFIG.TracerThickness = v / 10 end,
			Desc = "10 = thin hairline, 40 = fat beam" })
		K.slider(T, { Name = "Duration", Flag = "TracerDur",
			Default = math.floor((CONFIG.TracerDuration or 1.4) * 1000),
			Min = 200, Max = 4000, Suffix = " ms",
			Callback = function(v) CONFIG.TracerDuration = v / 1000 end,
			Desc = "how long the line stays before it fades" })
		K.slider(T, { Name = "Transparency", Flag = "TracerTransp",
			Default = math.floor((CONFIG.TracerTransparency or 0) * 100),
			Min = 0, Max = 100, Suffix = "%",
			Callback = function(v) CONFIG.TracerTransparency = v / 100 end })
		K.slider(T, { Name = "Fade In", Flag = "TracerFadeIn",
			Default = math.floor((CONFIG.TracerFadeIn or 0.12) * 1000),
			Min = 0, Max = 500, Suffix = " ms",
			Callback = function(v) CONFIG.TracerFadeIn = v / 1000 end })
		K.toggle(T, { Name = "Local Only", Flag = "TracerLocalOnly",
			Title = "Local Only",
			get = function() return CONFIG.TracerLocalOnly ~= false end,
			set = function(v) CONFIG.TracerLocalOnly = v end,
			Desc = "off = also draws other peoples shots" })
		trVis()
	end

	-- ═══ TAB: Gun Mods ═════════════════════════════════════════════════
	if tabGM then
		local G = tabGM:Section({ Side = "Left" })

		local function forceReapply()
			State.modifyAppliedUid = nil
			State.lastFullAutoApply = 0
			State.modifyLastPass = 0
			if CONFIG.ModifyEnabled then
				pcall(function() Bridge.applyWeaponModify(true) end)
			else
				pcall(function() Bridge.restoreWeaponModify() end)
			end
		end

		K.feature(G, {
			Title = "Weapon Mods", Flag = "ModifyEnabled",
			get = function() return CONFIG.ModifyEnabled end,
			set = function(v) CONFIG.ModifyEnabled = v; forceReapply() end,
			Desc = "mods every gun in ur inventory, not just the held one\nsurvives reloads n mag swaps",
		})
		K.button(G, { Name = "Re-apply Now", Flag = "ModifyForce", Title = "Weapon Mods",
			Callback = function()
				forceReapply()
				local n = State.modifyAppliedCount or 0
				return ("applied to %d component%s"):format(n, n == 1 and "" or "s")
			end })

		K.group(G, "Presets")
		local P = CONFIG.ModifyPresets or {}
		CONFIG.ModifyPresets = P
		local function preset(name, label, desc)
			K.toggle(G, { Name = label, Flag = "Preset_" .. name, Title = label,
				get = function() return P[name] == true end,
				set = function(v) P[name] = v end,
				after = forceReapply,
				Desc = desc })
		end
		preset("NoSpread", "No Spread", "kills the bullet cone, every shot goes dead center")
		preset("NoRecoil", "No Recoil", "zeroes kick on the replicator side, where recoil actually lives")
		preset("NoViewKick", "No View Kick", "camera stays still but the gun still kicks\nlooks way less sus than full no recoil")
		preset("FullAuto", "Full Auto", "forces auto firemode on everything")
		preset("InstantBolt", "Instant Bolt")
		preset("FastEquip", "Fast Equip", "no draw delay after swapping")
		preset("NoSway", "No Sway")
		preset("NoSpeedPenalty", "No Speed Penalty", "u dont slow down while shooting")
		preset("LightWeight", "Light Weight")
		preset("FlatBallistics", "Flat Ballistics", "less drop n drag, bullet flies straighter")

		-- ── Правая колонка: числовые оверрайды ──
		local G2 = tabGM:Section({ Side = "Right" })
		G2:Header({ Name = "Fire Rate" })
		local rpmEls = {}
		local function rpmVis() K.setVisible(rpmEls, P.RPM == true) end
		K.toggle(G2, { Name = "Override RPM", Flag = "RPMOn", Title = "Override RPM",
			get = function() return P.RPM == true end,
			set = function(v) P.RPM = v end,
			after = function() rpmVis(); forceReapply() end })
		rpmEls[#rpmEls + 1] = K.slider(G2, { Name = "RPM", Flag = "RPM",
			Default = CONFIG.ModifyRPMValue, Min = 60, Max = 3000,
			Callback = function(v) CONFIG.ModifyRPMValue = v; forceReapply() end,
			Desc = "rounds per minute, applies to every gun" })
		rpmVis()

		K.group(G2, "Bullet Speed")
		local bsEls = {}
		local function bsVis() K.setVisible(bsEls, P.BulletSpeed == true) end
		K.toggle(G2, { Name = "Override Speed", Flag = "BulletSpeedOn", Title = "Override Bullet Speed",
			get = function() return P.BulletSpeed == true end,
			set = function(v) P.BulletSpeed = v end,
			after = function() bsVis(); forceReapply() end })
		bsEls[#bsEls + 1] = K.slider(G2, { Name = "Bullet Speed", Flag = "BulletSpeed",
			Default = CONFIG.ModifyBulletSpeedValue, Min = 100, Max = 5000, Suffix = " st/s",
			Callback = function(v) CONFIG.ModifyBulletSpeedValue = v; forceReapply() end,
			Desc = "faster = less lead needed, but way more obvious" })
		bsVis()

		K.group(G2, "Advanced")
		K.slider(G2, { Name = "Re-apply Interval", Flag = "ModifyReapply",
			Default = math.floor((CONFIG.ModifyReapplyInterval or 1.0) * 1000),
			Min = 250, Max = 3000, Suffix = " ms",
			Callback = function(v) CONFIG.ModifyReapplyInterval = v / 1000 end,
			Desc = "how often we re-check every gun\nhigher = less cpu, slower to catch a fresh pickup" })
	end

	-- ═══ DEBUG ═════════════════════════════════════════════════════════
	local dtab = ui.tabs and ui.tabs.Debug
	if dtab then
		local D = dtab:Section({ Side = "Left" })
		D:Header({ Name = "Silent Aim" })
		K.slider(D, { Name = "Target Refresh", Flag = "DbgTgt",
			Default = math.floor((CONFIG.AimTargetRefreshInterval or 0.06) * 1000),
			Min = 10, Max = 250, Suffix = " ms",
			Callback = function(v) CONFIG.AimTargetRefreshInterval = v / 1000 end })
		K.slider(D, { Name = "Resolver Scan", Flag = "DbgRes",
			Default = math.floor((CONFIG.ResolverScanInterval or 0.18) * 1000),
			Min = 30, Max = 500, Suffix = " ms",
			Callback = function(v) CONFIG.ResolverScanInterval = v / 1000 end })
		K.slider(D, { Name = "Lite MP Refresh", Flag = "DbgLiteMP",
			Default = math.floor((CONFIG.LiteMultiPointRefreshInterval or 0.09) * 1000),
			Min = 20, Max = 400, Suffix = " ms",
			Callback = function(v) CONFIG.LiteMultiPointRefreshInterval = v / 1000 end })
		K.slider(D, { Name = "MultiPoint Cache", Flag = "DbgMPCache",
			Default = math.floor((CONFIG.MultiPointCacheSec or 0.28) * 1000),
			Min = 50, Max = 1000, Suffix = " ms",
			Callback = function(v) CONFIG.MultiPointCacheSec = v / 1000 end })
		K.slider(D, { Name = "Resolver Budget", Flag = "DbgBudget",
			Default = CONFIG.ResolverBudgetPerFrame or 4, Min = 1, Max = 16,
			Callback = function(v) CONFIG.ResolverBudgetPerFrame = v end,
			Desc = "resolver checks per frame" })

		K.group(D, "Logging")
		D:SubLabel({ Text = "console spam, keep off for normal play" })
		K.toggle(D, { Name = "Server Aim", Flag = "DbgServerAim", Title = "Server Aim Debug",
			get = function() return CONFIG.ServerAimDebug end,
			set = function(v) CONFIG.ServerAimDebug = v end })
		K.toggle(D, { Name = "Force Hit", Flag = "DbgForceHit", Title = "Force Hit Debug",
			get = function() return CONFIG.ForceHitDebug end,
			set = function(v) CONFIG.ForceHitDebug = v end })
		K.toggle(D, { Name = "Bullet Payload", Flag = "DbgBulletPayload", Title = "Bullet Payload Log",
			get = function() return CONFIG.LogBulletPayload end,
			set = function(v) CONFIG.LogBulletPayload = v end })
		K.toggle(D, { Name = "Bullet Event", Flag = "DbgBulletEvent", Title = "Bullet Event Log",
			get = function() return CONFIG.LogBulletEvent end,
			set = function(v) CONFIG.LogBulletEvent = v end })
		K.toggle(D, { Name = "Quiet Logs", Flag = "DbgQuiet", Title = "Quiet Logs",
			get = function() return CONFIG.QuietLogs end,
			set = function(v) CONFIG.QuietLogs = v end })

		K.group(D, "Gun Mods")
		local gmStat = D:Label({ Text = "Components: -" })
		task.spawn(function()
			while gmStat and gmStat._frame and gmStat._frame.Parent do
				pcall(function()
					local comps = Bridge.collectFirearmComponents and Bridge.collectFirearmComponents() or {}
					local h, r = 0, 0
					for _, c in ipairs(comps) do
						if c.kind == "handler" then h += 1 else r += 1 end
					end
					gmStat:UpdateName(("Guns: %d handler | %d replicator | modded: %d")
						:format(h, r, State.modifyAppliedCount or 0))
				end)
				task.wait(1)
			end
		end)
	end

	K.ready()
end

return SilentAim
end -- return function(Lib)
