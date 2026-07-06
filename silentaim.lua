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

-- Совместимость: SA v2 ожидает хелперы из BRM5Lib_v2.
	if type(Bridge.isLocalPlayerShot) ~= "function" then
	function Bridge.isLocalPlayerShot(isLocal)
		if isLocal == true then return true end
		if isLocal == false then return false end
		return os.clock() - (State.lastDischargeAimTime or 0) < 0.45
	end
end
if type(Bridge.isOurBulletEvent) ~= "function" then
	function Bridge.isOurBulletEvent(op, args)
		if type(args) ~= "table" then return false end
		if op == 2 then
			if args[7] == true then return true end
			if args[7] == false then return false end
			return os.clock() - (State.lastDischargeAimTime or 0) < 0.45
		end
		if op == 1 then
			return os.clock() - (State.lastDischargeAimTime or 0) < 0.35
		end
		return false
	end
end
if type(Bridge.logBulletHit) ~= "function" then
	function Bridge.logBulletHit(op, part, isLocal, stage)
		log("BULLET", "hit", "op=" .. tostring(op), "part=" .. tostring(part and part.Name), "stage=" .. tostring(stage))
	end
end
if type(Bridge._getGcCached) ~= "function" then
	Bridge._getGcCached = function()
		return {}
	end
end

-- SA-specific configuration
local SA_CONFIG = {
	AimTargetRefreshInterval = 0.06,
	AimVisualInterval = 0.1,
	AimVisualDrawInterval = 0.055,
	CombatAimRefreshInterval = 0.08,
	MultiPointRaycastCacheSec = 0.1,
	AimScanMaxActors = 14,
	MultiPointMaxActors = 5,
	MultiPointCacheSec = 0.28,
	MultiPointStickySec = 0.35,
	MultiPointNegCacheSec = 0.05,
	MultiPointRequireLos = false,
	MuzzlePeekMaxOffset = 6,
	SpoofMuzzleCacheSec = 0.12,
	LosRaycastCacheSec = 0.1,
	MuzzleVisual = true,
	ClientMuzzleSpoof = true,
	ServerFirstBullet = false,
	ServerOnlyAimPatch = false,
	ServerAimDebug = false,
	SilentAim = true,
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
	PingCompensation = false,
	PredictionIterations = 3,     -- итераций сходимости времени полёта (2-4)
	PredictionVertical = false,    -- учитывать вертикальную скорость (прыжки/падения)
	PredictionVertCap = 10,       -- кап вертикальной скорости (studs/s)
	PredictionMaxVelCap = 35,     -- кап горизонтальной скорости (studs/s)
	PingCompensationScale = 0.5,  -- доля RTT при PingCompensation=true
	DefaultBulletSpeed = 920,
	ForceZeroSpread = true,
	MultiPoint = false,
	LiteMultiPoint = true,
	LiteMultiPointCacheSec = 0.55,
	LiteMultiPointMaxDist = 8,
	LiteMultiPointMaxActors = 3,
	LiteMultiPointBinarySteps = 2,
	LiteMultiPointRefreshInterval = 0.09,
	MultiPointWallSearchStep = 0.8,
	MultiPointWallSearchMax = 8,
	MultiPointMaxMuzzleDist = 8,
	MultiPointBones = {
		"Head", "UpperTorso", "LowerTorso"
	},
	ResolverLite = true,
	ResolverLiteMode = "Aim",
	ResolverLiteInset = 0.08,
	ResolverScanInterval = 0.18,
	ForceClientHit = true,
	ForceHit = true,
	IgnoreTeammates = true,
	SaCornerPeekDist = 4.5,
	SaPeekMaxOffset = 2.5,
	AimSkipDeadHP = true,
	AimVisuals = true,
	ShotTracers = true,
	TracerDuration = 1.4,
	TracerFadeIn = 0.12,
	TracerThickness = 0.9,
	AimVisualStyle = "Swastika",
	AimVisualScale = 0.5,
	HitSound = true,
	HitSoundId = "rbxassetid://106586644436584",
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
	-- Это геометрия IK текущей позы, а НЕ индекс серверной истории для отмотки.
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
	ModifyEnabled = true,
	ModifyRPMValue = 1200,
	ModifyBulletSpeedValue = 2000,
	ModifyPresets = {
		-- NoSpread: обнуляет Barrel_Spread, cal.Spread и все *Spread* в Tune
		NoSpread = true,
		-- NoRecoil: обнуляет Recoil_X/Z, RecoilForce, ViewModel Recoil
		NoRecoil = true,
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

function Bridge.angleFromCameraLook(cam, worldPos)
	local look = cam.CFrame.LookVector
	local toTarget = worldPos - cam.CFrame.Position
	if toTarget.Magnitude < 0.05 then return 0 end
	return math.deg(math.acos(math.clamp(look:Dot(toTarget.Unit), -1, 1)))
end

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
	line.Color = Color3.fromRGB(255, 90, 35)
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
		if old and old.line then pcall(function() old.line:Remove() end) end
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
			pcall(function() e.line:Remove() end)
			table.remove(State.shotLines, i)
		else
			local sp1, on1 = cam:WorldToViewportPoint(e.a)
			local sp2, on2 = cam:WorldToViewportPoint(e.b)
			local alpha = Bridge.tracerAlpha(age, life, CONFIG.TracerFadeIn)
			if (on1 or on2) and sp1.Z > 0.01 and sp2.Z > 0.01 then
				e.line.From = Vector2.new(sp1.X, sp1.Y)
				e.line.To = Vector2.new(sp2.X, sp2.Y)
				e.line.Thickness = (CONFIG.TracerThickness or 0.9) + alpha * 0.5
				Bridge.showDrawing(e.line, alpha)
				e.line.Color = Color3.fromRGB(255, math.floor(70 + alpha * 80), 25)
			else
				e.line.Visible = false
			end
		end
	end
end

function Bridge.clearShotTracers()
	for _, e in ipairs(State.shotLines) do
		if e.line then pcall(function() e.line:Remove() end) end
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

function Bridge.playLocalHitSound()
	if CONFIG.HitSound == false then return end
	local sid = CONFIG.HitSoundId or "rbxassetid://106586644436584"
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = sid
		s.Volume = 0.85
		s.Parent = workspace
		s:Play()
		game:GetService("Debris"):AddItem(s, 2)
	end)
end

local HIT_PT_COL_A = Color3.fromRGB(88, 165, 255)
local HIT_PT_COL_B = Color3.fromRGB(165, 95, 255)
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
		HIT_PT_COL_A.R + (HIT_PT_COL_B.R - HIT_PT_COL_A.R) * t,
		HIT_PT_COL_A.G + (HIT_PT_COL_B.G - HIT_PT_COL_A.G) * t,
		HIT_PT_COL_A.B + (HIT_PT_COL_B.B - HIT_PT_COL_A.B) * t
	)
end

local function wfRotateOffset(off, ang)
	local cf = CFrame.Angles(ang.X, ang.Y, ang.Z)
	return cf:VectorToWorldSpace(off)
end

-- FIX v8: destroy helper — удаляет все Drawing-объекты системы частиц
local function destroyParticleSystem(sys)
	for _, p in ipairs(sys.pts) do
		if p.dot then pcall(function() p.dot:Remove() end) end
		for _, e in ipairs(p.edges or {}) do
			pcall(function() e.line:Remove() end)
		end
	end
	for _, e in ipairs(sys.links or {}) do
		pcall(function() e.line:Remove() end)
	end
end

local function ensureFovCircle()
	if State.fovCircle then return end
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return end
	local c = Drawing.new("Circle")
	c.NumSides    = 64
	c.Thickness   = CONFIG.FovCircleThickness or 1
	c.Filled      = false
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
			else
				for _, p in ipairs(sys.pts) do
					p.vel += sys.gravity * step
					p.vel *= drag
					p.pos += p.vel * step
					local sp, onScreen = cam:WorldToViewportPoint(p.pos)
					if onScreen and sp.Z > 0.05 then
						local depth = sp.Z
						local r = 0.28 + p.z * 0.62
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
						else
							p.dot.Visible = false
						end
						p.sx, p.sy, p.onScreen = sp.X, sp.Y, true
					else
						p.dot.Visible = false
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
				if p.dot then pcall(function() p.dot:Remove() end) end
				for _, e in ipairs(p.edges or {}) do pcall(function() e.line:Remove() end) end
			end
			for _, e in ipairs(old.links or {}) do pcall(function() e.line:Remove() end) end
		end
	end
	normal = (typeof(normal) == "Vector3" and normal.Magnitude > 0.01) and normal.Unit or Vector3.new(0, 1, 0)
	do
		local count = math.clamp(CONFIG.HitParticleCount or 40, 8, 48)
		local spdMin = CONFIG.HitParticleSpeedMin or 8
		local spdMax = CONFIG.HitParticleSpeedMax or 22
		local wfScale = CONFIG.HitParticleWireScale or 0.55
		local useWireframe = CONFIG.HitParticleWireframe ~= false
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
			else
				local dot = Drawing.new("Circle")
				dot.Filled = true
				dot.Thickness = 1
				dot.NumSides = 8
				dot.ZIndex = 9
				dot.Radius = 1
				dot.Transparency = 1
				dot.Visible = false
				pt.dot = dot
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
	-- Отключено: дубли��ует namecall FireServer patch.
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
		pcall(function()
			for _, key in ipairs({ "ring", "ringOuter", "line", "label", "dot", "crossH", "crossV" }) do
				local d = State.aimViz[key]
				if d then pcall(function() d:Remove() end) end
			end
			if State.aimViz.reticleLines then
				for _, l in ipairs(State.aimViz.reticleLines) do
					pcall(function() l:Remove() end)
				end
			end
			if State.aimViz.boxLines then
				for _, l in ipairs(State.aimViz.boxLines) do
					pcall(function() l:Remove() end)
				end
			end
		end)
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

	-- Единая точка: viz всегда показывает predicted aim (если Prediction включён).
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
	local tierColor = tier == 0 and Color3.fromRGB(120, 255, 120)
		or (tier == 1 and Color3.fromRGB(255, 220, 80)
		or (tier == 3 and Color3.fromRGB(120, 180, 255) or Color3.fromRGB(255, 90, 90)))

	-- Backtrack удалён v4 — скрываем bt-drawings если есть
	if viz.btCurrent then viz.btCurrent.Visible = false end
	if viz.btPast then viz.btPast.Visible = false end
	if viz.btLine then viz.btLine.Visible = false end
	if viz.btText then viz.btText.Visible = false end

	drawAimReticle(viz, cx, cy, tierColor, 0.95, now)

	-- Клиентская линия: muzzle → aim (predict)
	if CONFIG.MuzzleVisual then
		drawSeg(
			ensureLine("muzzleLine", 2.0, 44),
			muzzlePos, aimWorld,
			Color3.fromRGB(80, 220, 255), 0.85
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
					if State._hookDrawingTest then State._hookDrawingTest:Remove() end
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
		pcall(function()
			for _, key in ipairs({ "crossH", "crossV", "dot", "ring", "ringOuter", "line", "label" }) do
				local d = State.aimViz[key]
				if d then d:Remove() end
			end
			if State.aimViz.boxLines then
				for _, l in ipairs(State.aimViz.boxLines) do
					l:Remove()
				end
			end
		end)
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
	NoSpread = Bridge.applyModifyPresetNoSpread,
	NoRecoil = Bridge.applyModifyPresetNoRecoil,
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
		NoSpread = "Обнуляет разброс (Tune.Barrel_Spread, cal.Spread)",
		NoRecoil = "Обнуляет отдачу оружия и ViewModel Recoil",
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

Bridge.applyWeaponModify = function(force)
	if not CONFIG.ModifyEnabled then return end
	local ctx = force and Bridge.getLiveWeaponContext(true)
		or (Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true))
		or Bridge.peekWeaponContext()
	if not ctx then return end
	if not ctx or not ctx.tune then return end
	local uid = Bridge.itemUid(ctx.item)
	if force or not uid or uid ~= State.modifyAppliedUid then
		State.modifyHookHandlerKey = nil
	end
	if not force and uid and uid == State.modifyAppliedUid then
		return
	end
	Bridge.backupModifyState(ctx)
	for name, enabled in pairs(CONFIG.ModifyPresets) do
		if enabled then
			local fn = MODIFY_APPLIERS[name]
			if fn then
				Bridge.applyTuneLive(ctx, fn)
			end
		end
	end
	if uid then
		State.modifyAppliedUid = uid
	end
end

function Bridge.restoreWeaponModify()
	for uid, snap in pairs(State.modifyBackup) do
		local ctx = Bridge.peekWeaponContext and Bridge.peekWeaponContext() or nil
		if ctx and Bridge.itemUid(ctx.item) == uid and ctx.tune and snap.tune then
			for k, v in pairs(snap.tune) do
				ctx.tune[k] = v
			end
			if ctx.cal and snap.cal then
				for k, v in pairs(snap.cal) do
					ctx.cal[k] = v
				end
			end
			if ctx.meta and snap.metaMode ~= nil then
				rawset(ctx.meta, "Mode", snap.metaMode)
			end
		end
	end
	table.clear(State.modifyBackup)
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

function Bridge.extractWeaponMagFromItem(item)
	if type(item) ~= "table" then return nil, nil, nil end
	local meta = rawget(item, "MetaData")
	if type(meta) ~= "table" then
		meta = item
	end
	local name = meta.Name or meta.Receiver
	if type(name) == "table" then
		name = name.Name
	end
	local display = (Bridge.firearmDisplayName and Bridge.firearmDisplayName(item)) or name
	local mag = meta.Mag or rawget(item, "Mag")
	local cur, maxMag = nil, nil
	if type(mag) == "table" then
		maxMag = mag.Max or mag.MaxCapacity or mag.Ammo
	end
	local firearm = rawget(item, "File")
	if type(firearm) == "table" then
		local tune = rawget(firearm, "Tune")
		if type(tune) == "table" and type(tune.Ammo) == "number" then
			maxMag = maxMag or tune.Ammo
		end
	end
	return display, cur, maxMag
end

function Bridge.isAnyFirearmItem(item, mods)
	if type(item) ~= "table" then return false end
	local name = rawget(item, "Name")
	if type(name) == "string" then
		if string.match(name, "^Firearm") or string.match(name, "^Melee") then
			return true
		end
	end
	return Bridge.isPlayerFirearmItem(item, mods)
end

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
	-- v18 PATCH: сброс locked resolvers — без этого resolveEquippedHand использует метод от старого кл��ента
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
		if CONFIG.ModifyEnabled and CONFIG.ModifyPresets.FullAuto
			and t - (State.lastFullAutoApply or 0) > 1.0 then
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
		if CONFIG.AimVisuals and combatActive then
			Bridge.updateAimVisuals()
		else
			Bridge.hideAimViz()
		end

		-- FIX v11: FOV Circle — показывается только при наличии огнестрельного оружия
		do
			local fc = State.fovCircle
			if fc then
				local wantShow = CONFIG.FovCircle == true
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
						fc.Transparency = CONFIG.FovCircleTransparency or 0.5
						fc.Visible     = true
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
		State.fovCircle:Remove()
		State.fovCircle = nil
	end
end

local SilentAim = {
	start  = function()
		brm5Global().State = State
		State.running = true
		for k,v in pairs(SA_CONFIG) do Bridge.CONFIG[k] = v end
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
		-- mouseFireHeld удалён: beginShotBurst теперь вызывается напрямую из
		-- GetMuzzleCFrame hook (p2==nil → вызов из FirearmInventory.Discharge)
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
	local flag = ui.flag or function(s) return "SA_" .. s end
	local tabSA = ui.tabs and ui.tabs.SilentAim
	local tabGM = ui.tabs and ui.tabs.GunMods
	if tabSA then
		local L = tabSA:Section({ Side = "Left" })
		L:Header({ Name = "Silent Aim" })
		L:Toggle({ Name = "Enabled", Default = CONFIG.SilentAim,
			Callback = function(v) CONFIG.SilentAim = v end }, flag("SilentAim"))
		L:Slider({ Name = "FOV", Default = CONFIG.SilentAimFOV, Minimum = 10, Maximum = 360,
			Precision = 0, Callback = function(v) CONFIG.SilentAimFOV = v end }, flag("FOV"))
		L:Slider({ Name = "Max Distance", Default = CONFIG.SilentAimMaxDistance, Minimum = 50,
			Maximum = 2000, Precision = 0, Suffix = " studs",
			Callback = function(v) CONFIG.SilentAimMaxDistance = v end }, flag("MaxDist"))
		L:Dropdown({ Name = "Target Bone", Options = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" },
			Default = CONFIG.SilentAimBone or "Head",
			Callback = function(v) CONFIG.SilentAimBone = v end }, flag("Bone"))
		L:Divider()
		L:Toggle({ Name = "Target Players", Default = CONFIG.SilentAimTargetPlayers,
			Callback = function(v) CONFIG.SilentAimTargetPlayers = v end }, flag("TgtPlayers"))
		L:Toggle({ Name = "Target Hostiles/NPC", Default = CONFIG.SilentAimTargetHostile,
			Callback = function(v) CONFIG.SilentAimTargetHostile = v end }, flag("TgtHostile"))
		L:Toggle({ Name = "Ignore NPCs", Default = CONFIG.SilentAimIgnoreNpc,
			Callback = function(v) CONFIG.SilentAimIgnoreNpc = v end }, flag("IgnoreNpc"))
		L:Toggle({ Name = "Ignore Players in PVE", Default = CONFIG.SilentAimIgnorePlayersInPve,
			Callback = function(v) CONFIG.SilentAimIgnorePlayersInPve = v end }, flag("IgnorePvePlayers"))
		L:Toggle({ Name = "Team Check", Default = CONFIG.TeamCheck,
			Callback = function(v) CONFIG.TeamCheck = v end }, flag("TeamCheck"))

		local R = tabSA:Section({ Side = "Right" })
		R:Header({ Name = "Prediction" })
		R:Toggle({ Name = "Prediction (ballistic)", Default = CONFIG.Prediction,
			Callback = function(v) CONFIG.Prediction = v end }, flag("Prediction"))
		R:Toggle({ Name = "Light Prediction (test)", Default = CONFIG.PredictionLite,
			Callback = function(v) CONFIG.PredictionLite = v end }, flag("PredLite"))
		R:Slider({ Name = "Light Predict Time", Default = CONFIG.PredictionLiteTime, Minimum = 0,
			Maximum = 0.5, Precision = 2, Suffix = " s",
			Callback = function(v) CONFIG.PredictionLiteTime = v end }, flag("PredLiteTime"))
		R:Divider()
		R:Header({ Name = "FOV Circle" })
		R:Toggle({ Name = "Show FOV Circle", Default = CONFIG.FovCircle,
			Callback = function(v) CONFIG.FovCircle = v end }, flag("FovCircle"))
		R:Colorpicker({ Name = "FOV Color", Default = CONFIG.FovCircleColor,
			Callback = function(c) CONFIG.FovCircleColor = c end }, flag("FovColor"))
		R:Toggle({ Name = "Filled", Default = CONFIG.FovCircleFilled,
			Callback = function(v) CONFIG.FovCircleFilled = v end }, flag("FovFilled"))
		R:Divider()
		R:Header({ Name = "Visuals / Feedback" })
		R:Toggle({ Name = "Hit Sound", Default = CONFIG.HitSound,
			Callback = function(v) CONFIG.HitSound = v end }, flag("HitSound"))
		R:Toggle({ Name = "Hit Particles", Default = CONFIG.HitParticles,
			Callback = function(v) CONFIG.HitParticles = v end }, flag("HitParticles"))
		R:Toggle({ Name = "Shot Tracers", Default = CONFIG.ShotTracers,
			Callback = function(v) CONFIG.ShotTracers = v end }, flag("ShotTracers"))
	end
	if tabGM then
		-- Модификации оружия (SA presets). GunMods-таб — общий с FreeGun из visuals.
		local G = tabGM:Section({ Side = "Left" })
		G:Header({ Name = "Weapon Mods (Silent Aim)" })
		G:Toggle({ Name = "Enable Weapon Mods", Default = CONFIG.ModifyEnabled,
			Callback = function(v) CONFIG.ModifyEnabled = v end }, flag("ModifyEnabled"))
		local P = CONFIG.ModifyPresets or {}
		CONFIG.ModifyPresets = P
		local function preset(name, label)
			G:Toggle({ Name = label, Default = P[name] ~= false,
				Callback = function(v) P[name] = v end }, flag("Preset_" .. name))
		end
		preset("NoSpread", "No Spread")
		preset("NoRecoil", "No Recoil")
		preset("NoViewKick", "No View Kick")
		preset("FullAuto", "Full Auto")
		preset("InstantBolt", "Instant Bolt")
		preset("FastEquip", "Fast Equip")
		preset("NoSway", "No Sway")
		preset("NoSpeedPenalty", "No Speed Penalty")

		local G2 = tabGM:Section({ Side = "Right" })
		G2:Header({ Name = "Weapon Tuning" })
		G2:Slider({ Name = "RPM", Default = CONFIG.ModifyRPMValue, Minimum = 60, Maximum = 3000,
			Precision = 0, Callback = function(v) CONFIG.ModifyRPMValue = v; P.RPM = true end }, flag("RPM"))
		G2:Toggle({ Name = "Override Bullet Speed", Default = P.BulletSpeed == true,
			Callback = function(v) P.BulletSpeed = v end }, flag("BulletSpeedOn"))
		G2:Slider({ Name = "Bullet Speed", Default = CONFIG.ModifyBulletSpeedValue, Minimum = 100,
			Maximum = 5000, Precision = 0, Callback = function(v) CONFIG.ModifyBulletSpeedValue = v end }, flag("BulletSpeed"))
	end
end

return SilentAim
end -- return function(Lib)
