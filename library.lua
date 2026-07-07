--[[
	BRM5Lib_v20 — CHANGELOG от v19:

	FIX MELEE IN HANDS:
	  getLiveWeaponContext — melee ctx без tune/handler (caliber=melee).
	  handFromCharacterHandWeld / findWeaponModelOnCharacter — визуальный match.
	  weaponContextValid — rediscover не крутится вечно на melee.

	FIX WEAPON AFTER RESPAWN (unchanged slots):
	  rediscoverEquippedWeapon + schedulePostRespawnWeaponRediscover — polling без PerformEquipCalls.
	  normalizeEquipUid — Flux _equipped может быть number.
	  handFromEquippedHandlers / handFromCharacterFirearmModel — fallback resolvers.
	  getLiveWeaponContext — findFirearmHandler + discover при отсутствии tune/handler.

	FIX WEAPON STUCK AFTER DEATH:
	  installCharacterLifecycle — Died/CharacterAdded, resetWeaponStateOnDeath немедленно.
	  getLiveWeaponContext — negative cache (нет оружия не резолвится каждый кадр).
	  handFromChangeHook / resolveEquippedHand — проверка isLocalPlayerAlive.

	FIX FPS DROP (NPC-карты):
	  scanActors — синхронно только игроки; NPC через tickRepSyncBatch (без O(N) spike).
	  getLiveWeaponContext — кэш пустого ctx 0.25s без оружия в руках.

	BRM5Lib_v19 — CHANGELOG от v18:

	FIX WEAPON NOT DETECTED / FPS DROP:
	  ПАТЧ A-1: hookSharedInventoryTable сохраняет si ref в State.sharedInventorySiRef.
	  ПАТЧ B:   debounce в hookOwnerChange.Change — только один task.defer при rebuild.

	BRM5Lib_v7 — CHANGELOG от v6:

	FIX ZMP PLAYERS NOT VISIBLE (InactiveWorld — все 5 мест):
	  FIX #1: considerReplicatorActor distSq — rootForDist.Position=0,0,0 для InactiveWorld
	    → теперь использует actorData.SimulatedPosition для distance check.
	  FIX #2: considerReplicatorActor prev cache — prev возвращался без обновления adPos
	    → теперь при inInactiveWorld=true всегда обновляем prev.adPos из actorData.SimulatedPosition.
	  FIX #3: refreshActorsForEsp — adPos обновляется каждые 0.5s для InactiveWorld акторов.
	  FIX #4: collectAimActorCandidates — root.Position=0,0,0 давало distSq>maxDist
	    → использует data.adPos для InactiveWorld.
	  FIX #5: computeCombatAimPoint — aimPart.Position=0,0,0, point был 0,0,0
	    → InactiveWorld path: adPos как aim point, LOS=assumed visible.
	  Везде SimulatedPosition > ServerPosition > Position (ActorClass.Replicate обновляет SimulatedPosition).

	BRM5Lib_v6 — CHANGELOG от v5:

	BRM5Lib_v5 — CHANGELOG от v3:

	FIX #1 NPC пропускаются вблизи (ForceHit не работал):
	  [v5 patch] considerReplicatorActor: NPC fast path — rawget(actorData,"Character")
	    без workspace scan. Owner==nil → NPC, class через TargetGroup/Zombie.
	  [v5 patch] tickRepSyncBatch: NPC throttle — обновляются каждые 3 тика.
	  [v5 patch] getLocalMuzzleCFrame: TP fix — Focused==false использует HRP+CamLook.
	  isEnemyHitPart: ActorUID числовой → tostring() перед проверкой.
	  pseudo-object в fallback: class="player" для NPC → определяем через TargetGroup/Zombie.
	  wasClientBulletHitFired, markClientBulletHitFired, isMyBulletUid,
	  getPendingBulletShot — tostring(uid) нормализация.

	FIX #2 FPS просад на больших картах:
	  considerReplicatorActor: NPC > 1000м пропускаются, Zombie > 200м пропускаются.
	  Проверка через distSq (без sqrt) по камере.

	FIX #3 Backtrack:
	  getBacktrackSec → return 0
	  shouldUseBacktrackAim → return false
	  applyBacktrackOffset → return pt (no-op)
	  CONFIG.Backtrack и BacktrackTest удалены.

	BRM5Lib_v3 — CHANGELOG от v2:

	FIX #1 NPC НЕ НАХОДИЛИСЬ (кроме Zombie):
	  Flux хранит Actors[] с числовыми ключами (integer UID).
	  Весь код проверял type(uid)=="string" → числовые UID пропускались.
	  Исправлено: scanReplicatorActors, ensureRepSyncQueue — tostring(uid).
	  tickRepSyncBatch, getReplicatorActorData — tonumber(uid) fallback.
	  getActorUidFromModel — tostring(GetAttribute результата).

	FIX #2 FPS DROP (большие карты, 100+ NPC):
	  getActorUidFromModel: GetDescendants() → GetChildren() (30 частей → прямые дети).
	  collectAimActorCandidates: кэш врагов 0.15s, distSq без sqrt для пре-фильтра.
	  finalizeActorScan: инвалидация _aimEnemyCache при пересборке.
	  resolveActorCharacterModel: rawget(actorData,"Character") fast path для NPC.
	  classifyReplicatorActor: rawget Owner, TargetGroup fast path для NPC (Owner=nil).
	  resolveActorTeamKey: пропуск resolvePlayerFromActor для NPC.

	FIX #3 Friendly/Hostile классификация NPC:
	  NPC с Owner=nil → TargetGroup атрибут на модели: tg:0=friendly, tg:1=hostile, tg:2=zombie.
	  Default при отсутствии TargetGroup: "npc_hostile" (правильно для большинства NPC).
]]

--[[
	BRM5Lib_v1 — Game Library
	Взаимодействие с игрой: дампинг, акторы, инвентарь, raycast, LOS.
	Не содержит логики SilentAim и ESP рендера.

	Использование:
	  local Lib = loadstring(readfile("BRM5Lib.lua"), "BRM5Lib")()
	  -- Lib.Bridge, Lib.CONFIG, Lib.State
]]
local FIREMODE = {
	Safe = 0,
	Semi = 1,
	Auto = 2,
	Burst = 3,
}

local CONFIG = {
	ScanInterval = 30.0,
	GcRefreshInterval = 180.0,
	WeaponHudInterval = 1.5,
	LocalClientGcCooldown = 2.0,
	ClientResolveInterval = 0.5,
	WeaponHudMaxLines = 0,
	WeaponHudMaxTuneLines = 22,
	WeaponHudLineHeight = 16,
	WeaponHud = false,
	LogBulletEvent = false,
	LogBulletPayload = false,
	LocalBulletsOnly = true,
	BulletLogHitsOnly = true,
	BulletLogThrottle = 0.5,
	LogAttributesOnce = false,
	ReserveCacheSec = 5.0,
	WeaponCtxCacheSec = 0.85,
	WeaponCtxEmptyCacheSec = 8.0,
	EspWeaponInfoTtl = 2.5,
	HandRediscoverInterval = 0.45,  -- FIX v21: poll после respawn если ctx пуст
	NoWeaponRediscoverInterval = 2.5,
	LogV138Patch = false,
	ForceHitDebug = false,  -- OPT: было true → диагностический спам на каждый выстрел
	QuietLogs = true,
	GcRescanCooldown = 30,      -- v18: getgc(true) скан клиентов не чаще 30s
	InventoryGcCooldown = 20,   -- v18: getgc(true) скан инвентаря не чаще 20s
	LogBulletSpeed = false,
	DumpQuickMode = true,
	DumpMaxDepth = 3,
	CacheGcInterval = 12.0,         -- интервал автоочистки всех кэшей (сек)
-- SA defaults (overridden by SA_CONFIG on SA.start)
	AimTargetRefreshInterval = 0.05,
	CombatAimRefreshInterval = 0.035,
	AimScanMaxActors = 24,
	MultiPointMaxActors = 5,
	MultiPointCacheSec = 0.15,
	SpoofMuzzleCacheSec = 0.25,
	ResolverLite = true,
	ResolverLiteMode = "Aim",
	ResolverLiteInset = 0.08,
	ResolverScanInterval = 0.18,
	MuzzleVisual = true,
	ServerOnlyAimPatch = false,
	ServerFirstBullet = true,
	DrawingHighTransparencyMeansVisible = true,
	ClientMuzzleSpoof = false,
	ServerAimDebug = false,
	VizDebug = false,
	SilentAim = false,
	SilentAimFOV = 15,
	SilentAimBone = "Head",
	TeamCheck = true,
	Prediction = true,
	-- ── ЛЁГКИЙ предикт (тестовый) ─────────────────────────────────
	-- Простейшая версия: где цель окажется через PredictionLiteTime секунд,
	-- БЕЗ учёта оружия, скорости пули, баллистики и гравитации — просто
	-- pos + velocity * t. Когда включён, полностью подменяет обычный предикт
	-- (для сравнения/отладки). По умолчанию выключен.
	PredictionLite = false,
	PredictionLiteTime = 0.12,   -- секунд упреждения
	PredictionMaxVelCap = 35,  -- FIX v10: max velocity в studs/s для предикта (WalkSpeed~16, Sprint~28)
	-- ── Вертикальный prediction (FIX v23) ────────────────────────
	-- ВЫКЛ по умолчанию: раньше линейный vertVel*t завышал аим над головой.
	-- Включай только если реально нужно упреждать по прыжкам. Теперь модель
	-- гравитационная (Δy = vy*t − ½g·t²) с гейтом и жёстким клампом смещения.
	PredictionVertical    = false,
	PredictionVertCap     = 50,   -- кламп |vel.Y| studs/s перед расчётом
	PredictionVertMinVel  = 8,    -- ниже этой |vel.Y| вертикаль игнорируется (physics-джиттер стоящей цели)
	PredictionVertMaxOffset = 2.5,-- макс |смещение по Y| в studs (~радиус головы) — аим не улетает выше
	-- ── Глобальный масштаб силы предикта (FIX v23) ────────────────
	-- Умножается на velScaled ПОСЛЕ кампинга. 1.0 = без изменений.
	-- При медленных снарядах (бол. tFlight) lead автоматически растёт,
	-- но слишком агрессивно — уменьши до 0.6-0.8 если аим "уводит" вперёд.
	PredictionScale       = 1.0,
	PingCompensation = false,  -- FIX v11: не включать — добавляет лишний offset (pingMs*0.0005 к tFlight)
	DefaultBulletSpeed = 920,
	TracerLocalOnly = true,
	MultiPoint = false,
	LiteMultiPoint = true,
	LiteMultiPointCacheSec = 0.55,
	LiteMultiPointMaxDist = 6,
	LiteMultiPointStep = 1.8,
	LiteMultiPointMaxActors = 6,
	LiteMultiPointBinarySteps = 3,
	LiteMultiPointRefreshInterval = 0.08,
	MultiPointBones = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand",
	},
	ForceClientHit = false,
	ForceHit = false,
	-- Backtrack удалён v4
	SilentAimIgnoreNpc = false,
	SilentAimPreferPlayers = true,
	-- В PVE-режимах другие игроки — кооп-союзники: silent aim НЕ должен на них
	-- наводиться (ESP их всё равно показывает через EspShowPlayersInPve).
	SilentAimIgnorePlayersInPve = true,
	EspVisibleCheckNpc = false,
	ForceHitTimeOff = 0,
	IgnoreTeammates = true,
	-- FIX v8: Отображение игроков в PVE/ZMP режимах
	EspShowPlayersInPve = true,  -- показывать игроков в PVE-зонах
	ForceShowAllPlayers = true,  -- показывать ВСЕХ игроков (bypass isEnemyActor)
	SaCornerPeekDist = 4.5,
	SaPeekMaxOffset = 2.5,
	MultiPointStickySec = 0.35,
	MultiPointNegCacheSec = 0.05,
	AimSkipDeadHP = true,
	AimVisuals = true,
	ShotTracers = true,
	ModifyEnabled = false,
	NoSpread = false,
	NoRecoil = false,

-- ESP defaults (overridden by ESP_CONFIG on ESP.start)
	ESP = true,
	EspBox = true,
	EspSkeleton = true,
	EspChams = true,
	EspVisibleCheck = true,
	EspSmooth = false,
	EspSmoothAlpha = 1.0,
	EspHpBar = true,
	EspWeaponInfo = true,
	EspUpdateInterval = 0.0167,  -- FIX v8: 60fps
	EspMaxDistance = 1800,       -- глобальный лимит ESP (studs), дальше не рендерится
	EspRescanInterval = 4.0,     -- FIX v8: ресканирование каждые 4s
	EspRenderInterval = 0.0167,  -- FIX v8: 60fps рендер
	EspFullRescanInterval = 60.0,  -- FIX v10: полный скан каждые 60s (было 30s) — снижает фризы на NPC картах
	EspBoxAspect = 0.42,
	EspVisibleInterval = 0.22,
	EspVisibleFast = true,
	EspVisibleMaxRaysPerFrame = 8,
	EspChamsMaxActors = 24,          -- FIX v9: больше акторов
	EspSkeletonMaxActors = 24,       -- FIX v9
	EspSkeletonMaxDist = 800,        -- FIX v9: скелет только до 800 studs
	EspBoxMaxActors = 64,            -- FIX v9: ESP box для 64 акторов
	EspBoundsParts = 4,
	EspWeaponPlayersOnly = true,
	EspIgnoreTeam = true,
	EspVisibleBones = { "Head", "UpperTorso", "LowerTorso" },
	EspVisibleMinBones = 1,
	EspBatchSize = 6,               -- акторов за кадр для ESP (батчинг)
	EspScanWorldModels = false,
	ActorSyncBatchSize = 8,          -- v18 PATCH: было 5 (дубль 12 удалён), повышено для NPC скан
	ActorEnrichBatchSize = 2,
	RepSyncMinInterval = 0.35,       -- минимум между батчами rep sync (снижает FPS при enrich)
	RepSyncQueueScanSec = 0.75,      -- интервал pairs(rep) для новых UID (было 2.5 — новые NPC появлялись через ~минуту)
	NewActorPriorityPerTick = 24,    -- сколько НОВЫХ акторов обрабатывать немедленно за тик (в обход NPC-троттла)
	RepSyncQueueSortSec = 2.0,       -- nearest-first очередь actor sync
	MaxTrackedActors = 96,           -- v18 PATCH: было 64 (дубль 128 удалён), оптимальный баланс
	PerfHud = false,
	PerfHudInterval = 0.35,
	PerfHudRows = 22,
	PerfHudTextSize = 13,

}

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RF = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

-- MP-режимы взаимоисключающие — активный режим через Bridge.getMultiPointMode()


local State = {
	clients = nil,
	clientsSource = nil,
	actors = {},
	uidToPlayer = {},
	modelToPlayer = {},
	uidToActorModel = {},
	localActorUID = nil,
	localModel = nil,
	drawings = {},
	espHighlights = {},
	attributesLogged = false,
	clientsLogged = false,
	localLogged = false,
	summaryCount = 0,
	lastBulletLog = 0,
	lastGcRefresh = 0,
	gcInitialized = false,
	localClient = nil,
	sharedModules = nil,
	hudRows = {},
	hudLastLines = { "[Weapon]", "loading...", "F1 local | F2 weapon | F3 dump | F4 actor" },
	hudAnchorY = 0.35,
	weaponHudLogged = false,
	lastWeaponRefresh = 0,
	hudRefreshing = false,
	methods = {},
	reserveCache = {},
	playerInventory = nil,
	invDebugLogged = false,
	invCaptureInstalled = false,
	invCaptureLogged = false,
	lastInventoryGc = 0,
	cachedHudHandUid = nil,
	handItem = nil,
	handSlot = nil,
	handHookTime = 0,
	changeHookOwner = nil,
	tuneCache = {},
	modifyBackup = {},
	running = false,
	lastEspRescan = 0,
	lastEspFullRescan = -1,  -- FIX: -1 = не инициализирован, обновится при старте
	lastEspUpdate = 0,
	espVisibleCache = {},
	lastAimTargetRefresh = 0,
	aimTargetCache = nil,
	multiPointCache = {},
	spoofMuzzleCache = {},
	losRaycastCache = {},
	perf = nil,
	perfHud = nil,
	perfFrame = nil,
	lastSpoofCachePrune = 0,
	lastAimVisTier = nil,
	silentAimInstalled = false,
	dischargeHooked = false,
	dischargeHookRef = nil,
	sendHooked = false,
	aimTargetPart = nil,
	aimTargetLabel = nil,
	aimViz = nil,
	bulletService = nil,
	aimFrameTarget = nil,
	packetLoopRunning = false,
	bulletClassHooked = false,
	addToFilterHooked = false,
	actorBulletHooked = false,
	sendEventHooked = false,
	sendConnHooks = nil,
	bulletEventHooked = false,
	receiveHooked = false,
	namecallHooked = false,
	namecallHookVer = 0,
	bulletLogConn = nil,
	lastDischargeAimTime = 0,
	inBulletPatch = false,
	inShotPrep = false,
	inShotPrepTime = 0,
	inDischargeHook = false,
	dischargeOrigFn = nil,
	bulletSendInst = nil,
	shotAimTarget = nil,
	shotAimTargetTime = 0,
	shotLines = {},
	lastAutoShot = 0,
	localTeamKey = nil,
	localSquad = nil,
	clientService = nil,
	clientByPlayer = {},
	clientGcNegByPlayer = {},
	squadByPlayer = {},
	firearmModule = nil,
	firearmHooked = false,
	networkDischargeHooked = false,
	dischargeClosureHooked = false,
	forceHitPoint = nil,
	lastHookGcScan = 0,
	lastTeamRefresh = 0,
	hookGcCooldown = 12.0,
	weaponCtxCache = nil,
	weaponCtxCacheTime = 0,
	forceCombatAimRefresh = false,
	shotBurstActive = false,
	shotBurstT = 0,
	shotBurstAimPoint = nil,
	awaitingServerDischarge = false,
	pendingBulletSpawns = nil,
	lastShotOrigin = nil,
	pendingBulletShots = nil,
	myBulletUids = nil,
	lastV138Patch = nil,
	espFrameCache = nil,
	espLosParams = nil,
	lastEspRescanTick = 0,
	modifyAppliedUid = nil,
	mouseFireHeld = false,
	lastMouseFireTime = 0,
	bulletEventInst = nil,
	bulletReceiveInst = nil,
	fluxDumpFolder = "BRM5_FluxDump",
	lastLocalClientGc = 0,
	localClientLogged = false,
	clientsHookInstalled = false,
	-- v15 additions
	resolverCache    = nil,
	lastCacheGc      = 0,
	espBatchIndex    = 0,
	espActorList     = {},
	espActorListTime = 0,
	gcCache = nil,
	gcCacheTime = 0,
	trackedActorCount = 0,
	actorVelTrack = {},
	actorVelInstant = {},
	localPlayerAlive = true,
	sharedInventorySiRef = nil,
	trackHandPending = false,
	characterLifecycleInstalled = false,
	respawnHandScanGen = 0,
	lastHandRediscover = 0,
	lastInventoryGcResult = nil,
	lastInventoryGcScore = 0,
}

local WEAPON_CTX_EMPTY = { __empty = true }

-- GC Cache — getgc(true) не чаще раз в 20s; объявлено до любых Bridge.* GC-сканов
local GC_CACHE_TTL = 20.0
local function getGcCached()
	local now = os.clock()
	if State.gcCache and (now - (State.gcCacheTime or 0)) < GC_CACHE_TTL then
		return State.gcCache
	end
	if type(getgc) ~= "function" then return {} end
	if State.perf and State.perf.counts then
		State.perf.counts.gcRefresh = (State.perf.counts.gcRefresh or 0) + 1
	end
	local ok, result = pcall(getgc, true)
	if not ok or type(result) ~= "table" then return State.gcCache or {} end
	State.gcCache = result
	State.gcCacheTime = now
	return result
end

local Bridge = {}

local function perfState()
	State.perf = State.perf or {
		samples = {},
		values = {},
		counts = {},
		lastCounts = {},
		spikes = {},
		fps = 0,
		dtMs = 0,
		dtMaxMs = 0,
		lastHudT = 0,
	}
	return State.perf
end

function Bridge.perfBegin()
	return os.clock()
end

function Bridge.perfEnd(name, t0, meta)
	if not CONFIG.PerfHud or type(name) ~= "string" or type(t0) ~= "number" then return end
	local dt = (os.clock() - t0) * 1000
	local p = perfState()
	local s = p.samples[name]
	if not s then
		s = { last = 0, avg = 0, max = 0, n = 0, meta = nil }
		p.samples[name] = s
	end
	s.last = dt
	s.avg = s.n == 0 and dt or (s.avg * 0.82 + dt * 0.18)
	s.max = math.max(s.max * 0.985, dt)
	s.n += 1
	if meta ~= nil then s.meta = meta end
	if dt >= 6.0 then
		p.spikes[#p.spikes + 1] = { name = name, dt = dt, t = os.clock(), meta = meta }
		if #p.spikes > 6 then table.remove(p.spikes, 1) end
	end
end

function Bridge.perfCount(name, n)
	if not CONFIG.PerfHud or type(name) ~= "string" then return end
	local p = perfState()
	p.counts[name] = (p.counts[name] or 0) + (n or 1)
end

function Bridge.perfSet(name, value)
	if not CONFIG.PerfHud or type(name) ~= "string" then return end
	perfState().values[name] = value
end

function Bridge.perfGet(name)
	local p = State.perf
	if not p or not p.values then return nil end
	return p.values[name]
end

local function countTableKeys(tbl)
	local n = 0
	if type(tbl) == "table" then
		for _ in pairs(tbl) do n += 1 end
	end
	return n
end

local function perfSampleLine(samples, name, label)
	local s = samples[name]
	if not s then return string.format("%s -", label or name) end
	local meta = s.meta and (" " .. tostring(s.meta)) or ""
	return string.format("%s %.2f/%.2f/%.2fms%s", label or name, s.last or 0, s.avg or 0, s.max or 0, meta)
end

local function ensurePerfHudRows(rowCount)
	if not Drawing or type(Drawing.new) ~= "function" then return nil end
	local hud = State.perfHud
	if hud and hud.rows and #hud.rows >= rowCount then return hud end
	if hud and hud.rows then
		for _, row in ipairs(hud.rows) do
			pcall(function() row:Remove() end)
		end
	end
	hud = { rows = {} }
	for i = 1, rowCount do
		local txt = Drawing.new("Text")
		txt.Size = CONFIG.PerfHudTextSize or 13
		txt.Outline = true
		txt.Center = false
		txt.Color = i == 1 and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(210, 235, 255)
		txt.Visible = false
		hud.rows[i] = txt
	end
	State.perfHud = hud
	return hud
end

function Bridge.clearPerfHud()
	local hud = State.perfHud
	if not hud or not hud.rows then return end
	for _, row in ipairs(hud.rows) do
		pcall(function() row:Remove() end)
	end
	State.perfHud = nil
end

function Bridge.updatePerfHud(dt)
	if not CONFIG.PerfHud then
		Bridge.clearPerfHud()
		return
	end
	local p = perfState()
	local now = os.clock()
	local dtMs = (dt or 0) * 1000
	if dtMs > 0 then
		local fps = 1000 / math.max(dtMs, 0.001)
		p.fps = p.fps == 0 and fps or (p.fps * 0.9 + fps * 0.1)
		p.dtMs = dtMs
		p.dtMaxMs = math.max((p.dtMaxMs or 0) * 0.97, dtMs)
	end
	if now - (p.lastHudT or 0) < (CONFIG.PerfHudInterval or 0.35) then return end
	p.lastHudT = now

	local actors, playersN, npcN, zombieN = 0, 0, 0, 0
	for _, data in pairs(State.actors or {}) do
		actors += 1
		if data.class == "player" then playersN += 1 end
		if Bridge.isNpcActorClass and Bridge.isNpcActorClass(data.class) then npcN += 1 end
		if data.class == "npc_zombie" then zombieN += 1 end
	end
	State.trackedActorCount = actors

	local q = State.repSyncQueue
	local spike = p.spikes[#p.spikes]
	local counts = p.counts or {}
	local lines = {
		string.format("[PERF] fps %.0f dt %.1f max %.1f", p.fps or 0, p.dtMs or 0, p.dtMaxMs or 0),
		string.format("actors %d p:%d npc:%d z:%d ranked:%d", actors, playersN, npcN, zombieN, #(State.espRanked or {})),
		string.format("rep queue %d/%d enrich %s visCache:%d los:%d",
			State.repSyncIndex or 0, q and #q or 0, tostring(State.espEnrichBatchIndex or 0),
			countTableKeys(State.espVisibleCache), countTableKeys(State.losRaycastCache)),
		perfSampleLine(p.samples, "esp.heartbeat", "espHB"),
		perfSampleLine(p.samples, "esp.refresh", "refresh"),
		perfSampleLine(p.samples, "rep.batch", "repBatch"),
		perfSampleLine(p.samples, "scanActors", "scanFull"),
		perfSampleLine(p.samples, "esp.update", "espDraw"),
		perfSampleLine(p.samples, "esp.box", "box"),
		perfSampleLine(p.samples, "esp.hp", "hp"),
		perfSampleLine(p.samples, "esp.meta", "meta"),
		perfSampleLine(p.samples, "esp.skel", "skel"),
		perfSampleLine(p.samples, "esp.chams", "chams"),
		perfSampleLine(p.samples, "esp.rank", "rank"),
		perfSampleLine(p.samples, "esp.visibleBatch", "visBatch"),
		string.format("vis checks:%d rays:%d cacheHit:%d", counts.visibleCheck or 0, counts.espRay or 0, counts.visibleCacheHit or 0),
		string.format("ctx cache:%d emptyHit:%d resolve:%d ok:%d empty:%d redisc:%d invGC:%d gc:%d dump:%d",
			counts.weaponCtxCacheHit or 0, counts.weaponCtxEmptyHit or 0, counts.weaponCtxResolve or 0,
			counts.weaponCtxOk or 0, counts.weaponCtxEmpty or 0,
			counts.weaponRediscover or 0, counts.inventoryGcScan or 0, counts.gcRefresh or 0,
			counts.weaponDump or 0),
		string.format("draw actors:%s hidden:%s chams:%d", tostring(p.values.drawActors or "?"), tostring(p.values.hiddenActors or "?"), counts.chamsUpdate or 0),
		spike and string.format("last spike %s %.2fms %s", spike.name, spike.dt, tostring(spike.meta or "")) or "last spike -",
		"F2 weapon | right HUD = perf diagnostics",
	}

	p.lastCounts = counts
	p.counts = {}
	local rowCount = math.min(CONFIG.PerfHudRows or 14, #lines)
	local hud = ensurePerfHudRows(rowCount)
	local cam = workspace and workspace.CurrentCamera
	if not hud or not cam then return end
	local vp = cam.ViewportSize
	local lineH = (CONFIG.PerfHudTextSize or 13) + 3
	local x = math.max(16, vp.X - 430)
	local y = math.max(16, vp.Y * 0.5 - (rowCount * lineH) * 0.5)
	for i, row in ipairs(hud.rows) do
		if i <= rowCount then
			row.Text = lines[i]
			row.Position = Vector2.new(x, y + (i - 1) * lineH)
			row.Visible = true
		else
			row.Visible = false
		end
	end
end

local PHYSICS_GROUP = {
	[1] = "Character",
	[2] = "CharacterCast",
	[12] = "BotCast",
	[10] = "BotNoCollide",
	[15] = "BotEyes",
	[11] = "BotSightBlocker",
}

local scanConn = nil
local bulletConn = nil
local inputConn = nil
local fireInputBeganConn = nil
local fireInputEndedConn = nil
local characterAddedConn = nil
local changeOriginals = setmetatable({}, { __mode = "k" })

local CORE_PARTS = { "UpperTorso", "Head", "LowerTorso", "Torso", "HumanoidRootPart" }

-- ============================================================
-- LOG
-- ============================================================

local function shouldLogTag(tag)
	if tag == "ERR" then return true end
	if tag == "FH" and CONFIG.ForceHitDebug == true then return true end
	if tag == "BULLET" and (CONFIG.LogBulletEvent == true or CONFIG.LogBulletPayload == true) then return true end
	if tag == "VIZ" and CONFIG.VizDebug == true then return true end
	if tag == "AIM" and CONFIG.ServerAimDebug == true then return true end
	if CONFIG.QuietLogs == true then return false end
	return true
end

local function log(tag, ...)
	if not shouldLogTag(tag) then return end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	print("[BRM5Research]", string.format("[%s] %s", tag, table.concat(parts, " ")))
end

function Bridge.diagForceHit(stage, ...)
	if CONFIG.ForceHitDebug ~= true then return end
	log("FH", stage, ...)
end

local function markResolver(category, method)
	if not category or not method then return end
	if State.methods[category] == method then return end
	State.methods[category] = method
	log("RESOLVE", category, "=", method)
end

local function logLockedMethods()
	local parts = {}
	for _, cat in ipairs({ "client", "inventory", "slots", "hand" }) do
		if State.methods[cat] then
			parts[#parts + 1] = cat .. ":" .. State.methods[cat]
		end
	end
	if #parts > 0 then
		log("RESOLVE", "locked", table.concat(parts, " | "))
	end
end

local function tableField(t, key)
	if type(t) ~= "table" then return nil end
	-- v18: сначала rawget (без метатаблиц, без pcall) — быстрый путь
	local v = rawget(t, key)
	if v ~= nil then return v end
	-- есть метатаблица — используем pcall чтобы не крашиться
	if getmetatable(t) ~= nil then
		local ok, got = pcall(function() return t[key] end)
		if ok then return got end
		return nil
	end
	-- нет метатаблицы — прямой доступ безопасен
	return t[key]
end

local function isPureInventoryTable(t)
	if type(t) ~= "table" then return false end
	if type(rawget(t, "Storages")) ~= "table" then return false end
	if rawget(t, "Loadouts") ~= nil then return false end
	if rawget(t, "IsLocalClient") == true then return false end
	if rawget(t, "ActiveLoadout") ~= nil then return false end
	return true
end

local function getCamera()
	return Workspace.CurrentCamera
end

function Bridge.getLocalViewOrigin()
	local cam = getCamera()
	if cam then
		return cam.CFrame.Position
	end
	local char = LP and LP.Character
	local head = char and char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

-- ============================================================
-- CLIENTS
-- ============================================================

local function isClientsTable(t)
	return type(t) == "table"
		and type(rawget(t, "Clients")) == "table"
		and type(rawget(t, "GetClientFromPlayer")) == "function"
end

local function countClientsTable(t)
	local n = 0
	for _ in pairs(t.Clients) do
		n += 1
	end
	return n
end

local function findClientsInGC()
	if not getgc then return nil, 0 end
	local best, bestCount = nil, 0
	for _, v in ipairs(getGcCached()) do
		if isClientsTable(v) then
			local n = countClientsTable(v)
			if n > bestCount then
				best = v
				bestCount = n
			end
		end
	end
	return best, bestCount
end

local function isMaleModel(model)
	return typeof(model) == "Instance"
		and model:IsA("Model")
		and (model.Name == "Male" or string.match(model.Name, "^Male") ~= nil)
end

local function getActorUidFromModel(model)
	-- FIX v3: Flux хранит ActorUID как число (SetAttribute("ActorUID", numberUID))
	-- tostring нормализует к строке для единообразия с остальным кодом
	for _, name in ipairs(CORE_PARTS) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local uid = part:GetAttribute("ActorUID")
			if uid ~= nil then return tostring(uid), part end
		end
	end

	local humanoid = model:FindFirstChild("Humanoid")
	if humanoid then
		local root = humanoid:FindFirstChild("Root")
		if root and root:IsA("BasePart") then
			local uid = root:GetAttribute("ActorUID")
			if uid ~= nil then return tostring(uid), root end
		end
	end

	-- FIX v3: GetDescendants() дорог при 100+ NPC — проверяем только прямых детей
	-- Если не нашли в CORE_PARTS — быстрый проход только по BasePart детям (не всех потомков)
	for _, inst in ipairs(model:GetChildren()) do
		if inst:IsA("BasePart") then
			local uid = inst:GetAttribute("ActorUID")
			if uid ~= nil then return tostring(uid), inst end
		end
	end

	return nil, nil
end

local function rememberActorModel(uid, model)
	if type(uid) ~= "string" or uid == "" or not model then return end
	State.uidToActorModel = State.uidToActorModel or {}
	State.uidToActorModel[uid] = model
end

local function findModelByActorUid(uid)
	if type(uid) ~= "string" or uid == "" then return nil end
	local cached = State.uidToActorModel and State.uidToActorModel[uid]
	if cached and cached.Parent then return cached end
	return nil
end

local function looksLikeActorClient(v)
	if type(v) ~= "table" then return false end
	local player = rawget(v, "Player") or rawget(v, "Owner")
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	return rawget(v, "ActorUID") or rawget(v, "UID") or rawget(v, "Model") or rawget(v, "Rig")
end

local function isLocalGameClient(v)
	if type(v) ~= "table" then return false end
	if isPureInventoryTable(v) then return false end
	if rawget(v, "IsLocalClient") == true then return true end
	if rawget(v, "IsLocalPlayer") == true then return true end
	if rawget(v, "Loadouts") ~= nil and (rawget(v, "ActiveLoadout") ~= nil or rawget(v, "IsLocalClient") == true) then
		return rawget(v, "Owner") == LP or rawget(v, "IsLocalClient") == true
	end
	if rawget(v, "Player") == LP or rawget(v, "Owner") == LP then return true end
	if State.localActorUID then
		local uid = rawget(v, "UID") or rawget(v, "ActorUID")
		if type(uid) == "string" and uid == State.localActorUID then return true end
	end
	if State.localModel then
		local m = rawget(v, "Model") or rawget(v, "Rig") or rawget(v, "Character")
		if m == State.localModel then return true end
	end
	return false
end

local function captureLocalClient(client, source)
	if type(client) ~= "table" then return end
	if isPureInventoryTable(client) then
		if not State.playerInventory then
			State.playerInventory = client
		end
		return
	end
	State.localClient = client
	if State.clients and State.clients.Clients then
		State.clients.Clients[LP] = client
	end
	if source then
		markResolver("client", source)
	end
	if source and not State.localClientLogged then
		State.localClientLogged = true
		log(
			"MODULE", "local client:", source,
			"| IsLocalClient", tostring(tableField(client, "IsLocalClient")),
			"| ActiveLoadout", tostring(tableField(client, "ActiveLoadout"))
		)
	end
end

local function ingestActorClientTable(v)
	if rawget(v, "IsLocalClient") == true or rawget(v, "IsLocalPlayer") == true then
		captureLocalClient(v, "ingest-local")
	end
	local uid = rawget(v, "ActorUID") or rawget(v, "UID")
	local player = rawget(v, "Player") or rawget(v, "Owner")
	if type(uid) == "string" and typeof(player) == "Instance" and player:IsA("Player") then
		State.uidToPlayer[uid] = player
		if player == LP and type(v) == "table" then
			State.localClient = v
		end
	end
	local m = rawget(v, "Model") or rawget(v, "Rig") or rawget(v, "Character")
	if typeof(m) == "Instance" and m:IsA("Model") then
		State.modelToPlayer[m] = player
		local partUid = select(1, getActorUidFromModel(m))
		if partUid then
			State.uidToPlayer[partUid] = player
		end
	end
end

local function refreshActorClientsFromGC()
	if type(getgc) ~= "function" then return end
	local now = os.clock()
	-- v18: GC с��ан очень дорог — не чаще 1 раза в 30 секунд
	local gcCooldown = CONFIG.GcRescanCooldown or 30
	if State.gcInitialized and now - (State.lastGcRefresh or 0) < gcCooldown then
		return
	end
	table.clear(State.uidToPlayer)
	table.clear(State.modelToPlayer)
	for _, v in ipairs(getGcCached()) do
		if isLocalGameClient(v) then
			captureLocalClient(v, "gc-scan")
		elseif looksLikeActorClient(v) then
			ingestActorClientTable(v)
		end
	end
	State.lastGcRefresh = now
	State.gcInitialized = true
	log("GC", "full GC scan done, took", string.format("%.3fs", os.clock() - now))
end

local function mergeClientsRegistry(found, source)
	if not isClientsTable(found) then return false end
	if not State.clients or not isClientsTable(State.clients) then
		State.clients = found
	elseif found.Clients then
		for player, client in pairs(found.Clients) do
			if type(client) == "table" then
				State.clients.Clients[player] = client
				if player == LP then
					State.localClient = client
				end
			end
		end
	end
	if source then
		State.clientsSource = source
	end
	return countClientsTable(State.clients) > 0
end

local function tryImportClients()
	if type(shared) ~= "table" or type(shared.import) ~= "function" then
		return false
	end
	local attempts = {
		function() return shared.import("clients") end,
		function() return shared.import("require", "clients") end,
		function()
			local req = shared.import("require")
			if type(req) == "function" then
				return req("clients")
			end
		end,
		function()
			local _, _, _, clients = shared.import("network", "require", "clients", "Enum")
			return clients
		end,
	}
	for _, fn in ipairs(attempts) do
		local ok, clients = pcall(fn)
		if ok and mergeClientsRegistry(clients, "shared.import") then
			if not State.clientsLogged then
				State.clientsLogged = true
				log("MODULE", "clients via shared.import, entries:", countClientsTable(State.clients))
			end
			return true
		end
	end
	return false
end

local function tryFluxRuntimeClients()
	local flux = RF:FindFirstChild("Flux") or RS:FindFirstChild("Flux")
	if not flux then return false end
	local clientFolder = flux:FindFirstChild("client")
	if not clientFolder then return false end
	local inst = clientFolder:FindFirstChild("clients")
	if not inst or not inst:IsA("ModuleScript") then return false end
	local ok, clients = pcall(require, inst)
	if ok and mergeClientsRegistry(clients, "Flux/client") then
		log("MODULE", "clients via Flux/client, entries:", countClientsTable(State.clients))
		State.clientsLogged = true
		return true
	end
	return false
end

local function loadClientsModule()
	-- v2: early exit если уже полностью загружен
	if State.clientsReady then return end
	if State.clients and countClientsTable(State.clients) > 0 then
		State.clientsReady = true
		return
	end

	if tryImportClients() or tryFluxRuntimeClients() then
		return
	end

	if not State.clients then
		State.clients = require(RS:WaitForChild("Packages"):WaitForChild("clients"))
		State.clientsSource = "Packages"
		if not State.clientsLogged then
			State.clientsLogged = true
			log("MODULE", "clients fallback Packages (registry empty until runtime)")
		end
	end
end

local function getLocalClientObject()
	if State.localClient then return State.localClient end

	loadClientsModule()

	if State.clients and State.clients.Clients then
		local c = State.clients.Clients[LP]
		if type(c) == "table" then
			captureLocalClient(c, "registry")
			return c
		end

		for player, client in pairs(State.clients.Clients) do
			if player == LP and type(client) == "table" then
				captureLocalClient(client, "registry")
				return client
			end
		end

		if State.localActorUID then
			for _, client in pairs(State.clients.Clients) do
				if type(client) == "table" then
					local uid = client.ActorUID or client.UID
					if uid == State.localActorUID then
						captureLocalClient(client, "registry-uid")
						return client
					end
				end
			end
		end

		if State.localModel then
			for _, client in pairs(State.clients.Clients) do
				if type(client) == "table" then
					local m = client.Model or client.Rig or client.Character
					if m == State.localModel then
						captureLocalClient(client, "registry-model")
						return client
					end
				end
			end
		end
	end

	if State.clients then
		local getter = State.clients.GetClientFromPlayer
		if type(getter) == "function" then
			local ok, c = pcall(getter, State.clients, LP)
			if ok and type(c) == "table" then
				captureLocalClient(c, "GetClientFromPlayer")
				return c
			end
		end
	end

	return nil
end

local function resolveLocalClient(force)
	-- v18: быстрый early return — не делаем лишнюю работу если клиент уже найден
	if State.localClient and not force then
		return State.localClient
	end
	local client = getLocalClientObject()
	if client then return client end

	tryImportClients()
	tryFluxRuntimeClients()
	client = getLocalClientObject()
	if client then return client end

	if State.localClient and not force then
		return State.localClient
	end
	if not force or type(getgc) ~= "function" then
		return State.localClient
	end

	local now = os.clock()
	if now - State.lastLocalClientGc < CONFIG.LocalClientGcCooldown then
		return State.localClient
	end
	State.lastLocalClientGc = now

	for _, v in ipairs(getGcCached()) do
		if type(v) == "table" and rawget(v, "IsLocalClient") == true then
			captureLocalClient(v, "gc-IsLocalClient")
			return v
		end
	end

	local fromGC, gcCount = findClientsInGC()
	if fromGC and gcCount > 0 then
		mergeClientsRegistry(fromGC, "getgc-registry")
		client = getLocalClientObject()
		if client then return client end
	end

	for _, v in ipairs(getGcCached()) do
		if isLocalGameClient(v) then
			captureLocalClient(v, "getgc-client")
			return v
		end
	end

	return nil
end

local function installClientsHooks()
	if State.clientsHookInstalled then return end
	loadClientsModule()
	local clients = State.clients
	if not clients then return end

	local getter = clients.GetClientFromPlayer
	if type(getter) == "function" then
		if type(hookfunction) == "function" then
			hookfunction(getter, function(self, player, ...)
				local ret = getter(self, player, ...)
				if player == LP and type(ret) == "table" then
					captureLocalClient(ret, "hook-GetClientFromPlayer")
				end
				return ret
			end)
		else
			clients.GetClientFromPlayer = function(self, player, ...)
				local ret = getter(self, player, ...)
				if player == LP and type(ret) == "table" then
					captureLocalClient(ret, "wrap-GetClientFromPlayer")
				end
				return ret
			end
		end
	end

	State.clientsHookInstalled = true
end

local function logClientsRegistry()
	local clients = State.clients
	if not clients or not clients.Clients then
		log("REGISTRY", "нет Clients")
		return
	end
	local n = 0
	for player, client in pairs(clients.Clients) do
		n += 1
		if type(client) == "table" then
			local squad = tableField(client, "Squad")
			log("REGISTRY", player.Name, "uid=", client.ActorUID or client.UID or "?", "squad=", tostring(squad))
		end
	end
	log("REGISTRY", "count", n)
end

local function rebuildUidMap(forceGc)
	if forceGc and type(getgc) == "function" then
		refreshActorClientsFromGC()
	end

	local clients = State.clients
	if clients and clients.Clients then
		for player, client in pairs(clients.Clients) do
			if type(client) ~= "table" then continue end
			local uid = client.ActorUID or client.UID
			if uid then
				State.uidToPlayer[uid] = player
			end
			local m = client.Model or client.Character or client.Rig
			if typeof(m) == "Instance" and m:IsA("Model") then
				State.modelToPlayer[m] = player
				local partUid = select(1, getActorUidFromModel(m))
				if partUid then
					State.uidToPlayer[partUid] = player
				end
			end
		end
	end
end

local function normalizeCollisionGroup(col)
	if type(col) == "number" then
		return PHYSICS_GROUP[col] or tostring(col)
	end
	return col ~= "" and col or nil
end

-- ============================================================
-- LOCAL PLAYER — CameraSubject → Male, UID из Humanoid.Root
-- ============================================================

local function resolveLocalPlayer()
	local cam = getCamera()
	if not cam then return end

	local male = nil
	local subject = cam.CameraSubject
	if subject and subject:IsA("Humanoid") and isMaleModel(subject.Parent) then
		male = subject.Parent
	elseif subject and subject:IsA("BasePart") then
		local m = subject:FindFirstAncestorWhichIsA("Model")
		if isMaleModel(m) then
			male = m
		end
	end

	if not male and State.modelToPlayer then
		for model, player in pairs(State.modelToPlayer) do
			if player == LP and model.Parent then
				male = model
				break
			end
		end
	end

	if not male then return end

	State.localModel = male
	local uid = select(1, getActorUidFromModel(male))
	if uid then
		State.localActorUID = uid
		State.uidToPlayer[uid] = LP
		State.modelToPlayer[male] = LP
		if not State.localLogged then
			State.localLogged = true
			log("LOCAL", male:GetFullName(), "uid", uid)
		end
	end
end

function Bridge.isLocalPlayerAlive()
	local char = LP and LP.Character
	if not char or not char.Parent then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		if hum.Health <= 0 then
			State.localPlayerAlive = false
			return false
		end
		-- Локальный Humanoid — источник истины; replicate-флаги актора часто stale после respawn.
		if State.localPlayerAlive == false then
			State.localPlayerAlive = true
		end
		return true
	end
	if State.localPlayerAlive == false then
		return false
	end
	return true
end

function Bridge.resetWeaponStateOnDeath()
	State.localPlayerAlive = false
	State.handItem = nil
	State.handSlot = nil
	State.handHookTime = 0
	State.cachedHudHandUid = nil
	State.modifyAppliedUid = nil
	State.weaponCtxCache = WEAPON_CTX_EMPTY
	State.weaponCtxCacheTime = os.clock()
	State.trackHandPending = false
	if State.methods then
		State.methods.hand = nil
	end
	State.lastInventoryGc = 0
	State.lastInventoryGcResult = nil
	State.lastInventoryGcScore = 0
	State.hudLastLines = { "[Weapon]", "HANDS: none (dead)" }
	pcall(Bridge.syncWeaponHud, State.hudLastLines)
	log("WEAPON", "state cleared on death")
end

function Bridge.installCharacterLifecycle(onRespawn)
	if State.characterLifecycleInstalled then return end
	State.characterLifecycleInstalled = true

	local function bindHumanoid(char)
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then
			task.spawn(function()
				local waited = char:WaitForChild("Humanoid", 8)
				if waited and waited:IsA("Humanoid") then
					bindHumanoid(char)
				end
			end)
			return
		end
		hum.Died:Connect(function()
			Bridge.resetWeaponStateOnDeath()
		end)
	end

	LP.CharacterAdded:Connect(function(char)
		State.localPlayerAlive = true
		State.localModel = nil
		State.localActorUID = nil
		State.localLogged = false
		task.defer(function()
			resolveLocalPlayer()
		end)
		bindHumanoid(char)
		if type(onRespawn) == "function" then
			task.defer(onRespawn)
		end
	end)

	if LP.Character then
		bindHumanoid(LP.Character)
	end
	log("INIT", "character lifecycle active")
end

-- ============================================================
-- SCAN (Replicator.Actors + Workspace Male)
-- ============================================================

local function logModelAttributesOnce(model, part)
	if State.attributesLogged then return end
	State.attributesLogged = true
	log("ATTR", "=== образец", model:GetFullName(), "===")
	if part then
		log("ATTR", "part", part.Name, "CollisionGroup", normalizeCollisionGroup(part.CollisionGroup) or "?")
		for name, value in part:GetAttributes() do
			log("ATTR", "part", name, value)
		end
	end
end

local function isModelDead(model, actorData)
	if type(actorData) == "table" then
		if tableField(actorData, "Alive") == false then return true end
		if tableField(actorData, "Dead") == true then return true end
		if tableField(actorData, "IsDead") == true then return true end
	end
	if not model then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		if hum.Health <= 0 then return true end
		local ok, st = pcall(function()
			return hum:GetState()
		end)
		if ok and st == Enum.HumanoidStateType.Dead then return true end
	end
	if model:GetAttribute("Dead") == true or model:GetAttribute("IsDead") == true
		or model:GetAttribute("Corpse") == true or model:GetAttribute("Ragdoll") == true then
		return true
	end
	local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Head")
	if root and root:IsA("BasePart") then
		local col = normalizeCollisionGroup(root.CollisionGroup)
		if col == "Corpse" or col == "Ragdoll" or col == "Debris" then return true end
	end
	local health = type(actorData) == "table" and tableField(actorData, "Health") or nil
	if type(health) == "number" and health <= 0 then return true end
	return false
end

local function isActorCorpseModel(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false end
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not head or not torso then return false end
	if isMaleModel(model) then
		return isModelDead(model, nil)
	end
	local col = normalizeCollisionGroup(head.CollisionGroup)
	return col == "Ragdoll" or col == "Corpse" or col == "Debris"
end

local function classifyActor(uid, part, model, actorData)
	if isModelDead(model, actorData) then
		return "dead", "Dead"
	end
	local player = State.uidToPlayer[uid] or State.modelToPlayer[model]
	if player then
		if player == LP then
			return "self", "localplayer"
		end
		return "player", player.Name
	end
	if type(actorData) == "table" then
		local ownerName = tableField(actorData, "OwnerName")
		if type(ownerName) == "string" and ownerName ~= "" then
			if ownerName == LP.Name then
				return "self", "localplayer"
			end
			return "player", ownerName
		end
	end

	if uid == State.localActorUID or model == State.localModel then
		return "self", "localplayer"
	end

	local tg = part and part:GetAttribute("TargetGroup")
	if tg == nil then tg = model:GetAttribute("TargetGroup") end
	if tg == 0 then return "npc_friendly", "friendly" end
	if tg == 1 then return "npc_hostile", "hostile" end
	if tg == 2 then return "npc_zombie", "zombie" end

	if model:GetAttribute("Zombie") == true then
		return "npc_zombie", "zombie"
	end
	local mname = model.Name
	if type(mname) == "string" and string.find(mname, "Zombie", 1, true) then
		return "npc_zombie", "zombie"
	end

	local col = normalizeCollisionGroup(part and part.CollisionGroup)
	if col == "BotCast" or col == "BotNoCollide" or col == "BotEyes" then
		return "npc", "bot"
	end

	if model:GetAttribute("IsBot") == true or model:GetAttribute("Bot") == true then
		return "npc", "bot"
	end

	return "npc", "actor"
end

local function classifyReplicatorActor(uid, actorData, model, part)
	if type(actorData) == "table" then
		-- FIX v3: быстрый путь для зомби
		if rawget(actorData, "Zombie") == true then
			return "npc_zombie", "zombie"
		end
		if tableField(actorData, "IsLocalPlayer") == true then
			return "self", "localplayer"
		end
		if uid == State.localActorUID then
			return "self", "localplayer"
		end
		local owner = rawget(actorData, "Owner")
		if owner ~= nil then
			if typeof(owner) == "Instance" and owner:IsA("Player") then
				if owner == LP then
					return "self", "localplayer"
				end
				return "player", owner.Name
			end
		else
			-- FIX v3: Owner=nil означает NPC/бот — быстрый путь через TargetGroup
			-- TargetGroup: 0=friendly, 1=hostile, 2=zombie (из SetAttribute на Character parts)
			local tg = model and model:GetAttribute("TargetGroup")
			if tg == 0 then return "npc_friendly", "friendly" end
			if tg == 2 then return "npc_zombie", "zombie" end
			if tg == 1 then return "npc_hostile", "hostile" end
			-- Нет TargetGroup — hostile по умолчанию для NPC
			return "npc_hostile", "hostile"
		end
		local ownerName = tableField(actorData, "OwnerName")
		if type(ownerName) == "string" and ownerName ~= "" then
			if ownerName == LP.Name then
				return "self", "localplayer"
			end
			return "player", ownerName
		end
	end
	if model and part then
		return classifyActor(uid, part, model, actorData)
	end
	if type(actorData) == "table" and isModelDead(model, actorData) then
		return "dead", "Dead"
	end
	return "npc_hostile", "hostile"
end

local function actorEspRoot(model)
	if not model then return nil end
	return model:FindFirstChild(CONFIG.SilentAimBone or "Head")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("LowerTorso")
		or model:FindFirstChildWhichIsA("BasePart")
end

function Bridge.isNpcActorClass(class)
	return class == "npc" or class == "npc_zombie" or class == "npc_hostile" or class == "npc_friendly"
end

function Bridge.countTrackedNpcs()
	local n = 0
	for _, data in pairs(State.actors or {}) do
		if data and Bridge.isNpcActorClass(data.class) then
			n += 1
		end
	end
	return n
end

function Bridge.isPlayerActorClass(class)
	return class == "player"
end

function Bridge.resolveWeaponActor(ctx)
	if not ctx then return nil end
	local fluxHandler = ctx.fluxHandler
	if type(fluxHandler) == "table" and type(fluxHandler._actor) == "table" then
		return fluxHandler._actor
	end
	local handler = ctx.handler
	if type(handler) == "table" and type(handler._actor) == "table" then
		return handler._actor
	end
	return ctx.actor
end

local function safeTableGet(tbl, key)
	if type(tbl) ~= "table" then return nil end
	local ok, v = pcall(rawget, tbl, key)
	if not ok then return nil end
	return v
end

function Bridge.scanFluxInventoryService(force)
	local now = os.clock()
	if force then
		State.fluxInventoryService = nil
		State.fluxInventoryResolved = false
	end
	if State.fluxInventoryResolved then
		local svc = State.fluxInventoryService
		if svc == false then return nil end
		return svc
	end
	local now = os.clock()
	local sh = Bridge.getGameSharedImport()
	if sh then
		local ok, svc = pcall(sh.import, "InventoryService")
		if ok and type(svc) == "table" then
			local eq = rawget(svc, "Equipped")
			local handler = type(eq) == "table" and rawget(eq, "Handler") or nil
			if type(handler) == "table" and type(safeTableGet(handler, "_discharge")) == "function" then
				State.fluxInventoryService = svc
				State.fluxInventoryResolved = true
				return svc
			end
		end
	end
	if type(getgc) ~= "function" then
		State.fluxInventoryResolved = true
		State.fluxInventoryService = false
		return nil
	end
	if now - (State.lastFluxScan or 0) < 2.5 then
		return nil
	end
	State.lastFluxScan = now
	local best, bestScore = nil, 0
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "table" then continue end
		local eq = rawget(obj, "Equipped")
		if type(eq) ~= "table" then continue end
		local handler = rawget(eq, "Handler")
		if type(handler) ~= "table" then continue end
		if type(rawget(handler, "_discharge")) ~= "function" then continue end
		if not Bridge.isFluxShooterHandler(handler) then continue end
		local score = 10
		if type(rawget(handler, "Discharge")) == "function" then score += 5 end
		if rawget(obj, "_localActor") then score += 8 end
		if score > bestScore then
			best, bestScore = obj, score
		end
	end
	State.fluxInventoryResolved = true
	State.fluxInventoryService = best or false
	return best
end

function Bridge.scanFluxFireHandlerFromGc(force)
	local now = os.clock()
	if force then
		if now - (State.lastFluxGcScan or 0) < 2.5 then
			force = false
		else
			State.lastFluxGcScan = now
			State.fluxFireHandlerCache = nil
		end
	end
	if State.fluxFireHandlerCache ~= nil then
		return State.fluxFireHandlerCache ~= false and State.fluxFireHandlerCache or nil
	end
	if type(getgc) ~= "function" then
		State.fluxFireHandlerCache = false
		return nil
	end
	if not force and now - (State.lastFluxGcScan or 0) < 2.5 then
		State.fluxFireHandlerCache = false
		return nil
	end
	State.lastFluxGcScan = now
	local best, bestScore = nil, 0
	for _, obj in ipairs(getGcCached()) do
		if type(obj) ~= "table" then continue end
		if type(safeTableGet(obj, "_discharge")) ~= "function" then continue end
		if type(safeTableGet(obj, "_item")) ~= "table" and type(safeTableGet(obj, "_firearm")) ~= "table" then
			continue
		end
		if not Bridge.isFluxShooterHandler(obj) then continue end
		local score = 8
		local actor = safeTableGet(obj, "_actor")
		if type(actor) == "table" then
			if actor.IsLocalPlayer == true then score += 40 end
			if safeTableGet(obj, "Equipped") == true then score += 12 end
		end
		if type(safeTableGet(obj, "_discharge")) == "function" then score += 6 end
		if score > bestScore then
			best, bestScore = obj, score
		end
	end
	State.fluxFireHandlerCache = best or false
	return best
end

function Bridge.resolveFluxFireHandler(ctx)
	local importHandler = Bridge.resolveFluxImportHandler(false)
	if Bridge.isFluxShooterHandler(importHandler) then
		return importHandler, "flux.import"
	end
	local clientHandler, clientSrc = Bridge.resolveFluxFromClientActor(ctx)
	if Bridge.isFluxShooterHandler(clientHandler) then
		return clientHandler, clientSrc
	end
	local itemHandler = Bridge.resolveFluxHandlerByItemUid(ctx, false)
	if Bridge.isFluxShooterHandler(itemHandler) then
		return itemHandler, "flux.itemuid"
	end
	local svc = Bridge.scanFluxInventoryService()
	if svc then
		local handler = Bridge.pickFluxHandlerFromService(svc)
		if Bridge.isFluxShooterHandler(handler) then
			return handler, "flux.inventory"
		end
	end
	local gcHandler = Bridge.scanFluxFireHandlerFromGc(false)
	if Bridge.isFluxShooterHandler(gcHandler) then
		return gcHandler, "flux.gc"
	end
	if ctx and Bridge.isFluxShooterHandler(ctx.fluxHandler) then
		return ctx.fluxHandler, ctx.fluxSource or "flux.ctx"
	end
	local h = ctx and ctx.handler
	if type(h) == "table" and Bridge.isFluxShooterHandler(h) then
		return h, "actor.flux"
	end
	return nil, nil
end

function Bridge.isFluxFirearmHandler(handler)
	if type(handler) ~= "table" then return false end
	if safeTableGet(handler, "_tpChain") or safeTableGet(handler, "_heroModel") then return false end
	if type(safeTableGet(handler, "_discharge")) ~= "function" then return false end
	if type(safeTableGet(handler, "_item")) == "table" then return true end
	if type(safeTableGet(handler, "Discharge")) == "function" then return true end
	return type(safeTableGet(handler, "_firearm")) == "table"
end

function Bridge.isFluxShooterHandler(handler)
	if Bridge.isFluxFirearmHandler(handler) then return true end
	if type(handler) ~= "table" then return false end
	if safeTableGet(handler, "_tpChain") or safeTableGet(handler, "_heroModel") then return false end
	return type(safeTableGet(handler, "_discharge")) == "function"
end

function Bridge.getGameSharedImport()
	if State.fluxSharedRef == false then return nil end
	if type(State.fluxSharedRef) == "table" then return State.fluxSharedRef end
	if type(shared) == "table" and type(shared.import) == "function" then
		State.fluxSharedRef = shared
		return shared
	end
	if type(getrenv) == "function" then
		local ok, renv = pcall(getrenv)
		if ok and type(renv) == "table" and type(renv.shared) == "table" and type(renv.shared.import) == "function" then
			State.fluxSharedRef = renv.shared
			return renv.shared
		end
	end
	State.fluxSharedRef = false
	return nil
end

function Bridge.pickFluxHandlerFromService(svc)
	if type(svc) ~= "table" then return nil end
	if Bridge.isFluxShooterHandler(svc) then return svc end
	local eq = rawget(svc, "Equipped")
	local candidates = {}
	if type(eq) == "table" then
		candidates[#candidates + 1] = rawget(eq, "Handler")
		candidates[#candidates + 1] = eq
	elseif type(eq) == "string" and eq ~= "" then
		for _, mapKey in ipairs({ "_handlers", "Handlers", "_inventory", "Inventory" }) do
			local map = rawget(svc, mapKey)
			if type(map) == "table" then
				candidates[#candidates + 1] = map[eq]
			end
		end
	end
	candidates[#candidates + 1] = rawget(svc, "Handler")
	for _, h in ipairs(candidates) do
		if Bridge.isFluxShooterHandler(h) then
			return h
		end
	end
	return nil
end

function Bridge.resolveFluxHandlerByItemUid(ctx, force)
	if not ctx or not ctx.item then return nil end
	local handUid = Bridge.itemUid(ctx.item)
	if not handUid then return nil end
	local now = os.clock()
	if not force then
		local c = State.fluxItemHandlerCache
		if c and c.uid == handUid and now - (c.t or 0) < 1.0 then
			return c.handler ~= false and c.handler or nil
		end
		if now - (State.lastFluxItemScan or 0) < 5.0 then
			return nil
		end
	end
	State.lastFluxItemScan = now
	if type(getgc) ~= "function" then return nil end
	local found = nil
	for _, obj in ipairs(getGcCached()) do
		if not Bridge.isFluxShooterHandler(obj) then continue end
		local item = safeTableGet(obj, "_item")
		if type(item) ~= "table" then continue end
		if Bridge.itemUid(item) == handUid then
			found = obj
			break
		end
	end
	State.fluxItemHandlerCache = { uid = handUid, handler = found or false, t = now }
	return found
end

function Bridge.resolveFluxFromClientActor(ctx)
	resolveLocalClient(false)
	local client = State.localClient
	local actor = (ctx and ctx.actor) or (client and Bridge.getActorTable(client))
	if type(actor) ~= "table" then return nil, nil end
	for _, key in ipairs({
		"Inside_InventoryService", "InventoryService", "_inventoryService",
		"_InventoryService", "InsideInventoryService",
	}) do
		local svc = safeTableGet(actor, key)
		if type(svc) == "table" then
			local handler = Bridge.pickFluxHandlerFromService(svc)
			if handler then
				return handler, "flux.client." .. key
			end
		end
	end
	for k, v in pairs(actor) do
		if type(k) == "string" and string.find(k, "Inventory", 1, true) and type(v) == "table" then
			local handler = Bridge.pickFluxHandlerFromService(v)
			if handler then
				return handler, "flux.client.scan." .. k
			end
			if Bridge.isFluxShooterHandler(v) then
				return v, "flux.client.scan." .. k
			end
		end
	end
	return nil, nil
end

function Bridge.resolveFluxImportHandler(force)
	local now = os.clock()
	if not force then
		local c = State.fluxImportHandlerCache
		if c and now - (c.t or 0) < 0.35 then
			return c.handler ~= false and c.handler or nil
		end
	end
	local handler, svc
	local sh = Bridge.getGameSharedImport()
	if sh then
		local ok, imported = pcall(sh.import, "InventoryService")
		if ok and type(imported) == "table" then
			svc = imported
			handler = Bridge.pickFluxHandlerFromService(svc)
		end
	end
	if not handler then
		handler, _ = Bridge.resolveFluxFromClientActor(nil)
	end
	if not Bridge.isFluxShooterHandler(handler) then
		State.fluxImportHandlerCache = { handler = false, t = now }
		return nil
	end
	State.fluxImportHandlerCache = { handler = handler, t = now }
	if type(svc) == "table" then
		State.fluxInventoryService = svc
		State.fluxInventoryResolved = true
	end
	return handler
end

function Bridge.ensureWeaponFluxHandler(ctx, force)
	if not ctx then return nil, nil end
	local now = os.clock()
	local handUid = ctx.item and Bridge.itemUid(ctx.item)
	if handUid ~= State.fluxResolveHandUid then
		State.fluxResolveHandUid = handUid
		State.fluxResolveFailUntil = nil
		State.fluxHandlerCache = nil
	end
	if force then
		State.fluxResolveFailUntil = nil
	else
		if State.fluxResolveFailUntil and now < State.fluxResolveFailUntil then
			return nil, nil
		end
		local fluxCache = State.fluxHandlerCache
		if fluxCache and fluxCache.uid == handUid and now - (fluxCache.t or 0) < 1.0 then
			if fluxCache.handler == false then
				ctx.fluxHandler = nil
				ctx.fluxSource = nil
				return nil, nil
			end
			ctx.fluxHandler = fluxCache.handler
			ctx.fluxSource = fluxCache.source
			if Bridge.isFluxShooterHandler(ctx.fluxHandler) then
				return ctx.fluxHandler, ctx.fluxSource
			end
		end
		if Bridge.isFluxShooterHandler(ctx.fluxHandler) then
			return ctx.fluxHandler, ctx.fluxSource
		end
	end
	local fluxHandler, fluxSource = Bridge.resolveFluxFireHandler(ctx)
	ctx.fluxHandler = fluxHandler
	ctx.fluxSource = fluxSource
	State.fluxHandlerCache = {
		uid = handUid,
		handler = fluxHandler or false,
		source = fluxSource,
		t = now,
	}
	if not fluxHandler then
		State.fluxResolveFailUntil = now + 2.0
	end
	return fluxHandler, fluxSource
end

function Bridge.getEquippedFirearmReplicator(actor)
	if type(actor) ~= "table" then return nil end
	local eq = rawget(actor, "_equipped")
	if type(eq) ~= "string" or eq == "" then return nil end
	local inv = rawget(actor, "_inventory")
	if type(inv) ~= "table" then return nil end
	return inv[eq]
end

function Bridge.getCharacterHeightStateEnum()
	if State.characterHeightState ~= nil then
		return State.characterHeightState ~= false and State.characterHeightState or nil
	end
	local enum = nil
	if type(shared) == "table" and type(shared.import) == "function" then
		local ok, en = pcall(shared.import, "Enum")
		if ok and type(en) == "table" then
			enum = en.CharacterHeightState
		end
	end
	State.characterHeightState = enum or false
	return enum
end

local function espAnimPlaying(anim)
	if typeof(anim) ~= "Instance" or not anim:IsA("AnimationTrack") then
		return false
	end
	if anim.IsPlaying ~= true then return false end
	local len = anim.Length
	if type(len) ~= "number" or len <= 0.05 then return false end
	return anim.TimePosition < len * 0.9
end

local function espFirearmDischarging(firearmRep)
	if type(firearmRep) ~= "table" then return false end
	for _, key in ipairs({ "_discharge_tp", "_discharge_fp" }) do
		if espAnimPlaying(rawget(firearmRep, key)) then
			return true
		end
	end
	return false
end

local ESP_STATUS_COLORS = {
	weapon = Color3.fromRGB(255, 70, 70),
	reload = Color3.fromRGB(255, 160, 45),
	combat = Color3.fromRGB(255, 70, 70),
	move = Color3.fromRGB(90, 200, 255),
	stance = Color3.fromRGB(190, 170, 255),
	interact = Color3.fromRGB(255, 210, 90),
	gear = Color3.fromRGB(170, 255, 150),
}

local function statusKindForText(kind, text)
	if text == "Reloading" then return "reload" end
	if kind == "combat" or kind == "weapon" then
		if text == "Reloading" then return "reload" end
		return "weapon"
	end
	return kind
end

local function stateTruthy(v)
	if v == nil or v == false then return false end
	if typeof(v) == "Instance" then return true end
	if type(v) == "string" then return v ~= "" end
	if type(v) == "number" then return v ~= 0 end
	if type(v) == "table" then return false end
	return v == true
end

function Bridge.getActorStatusEntries(data)
	if not data or Bridge.isNpcActorClass(data.class) then
		return {}
	end
	local actor = data.actorData
	if not actor and data.uid then
		actor = Bridge.getReplicatorActorData(data.uid)
		if actor then data.actorData = actor end
	end
	if type(actor) ~= "table" then return {} end

	local entries = {}
	local seen = {}
	local function add(kind, text)
		if seen[text] then return end
		seen[text] = true
		local resolvedKind = statusKindForText(kind, text)
		local c = ESP_STATUS_COLORS[resolvedKind] or ESP_STATUS_COLORS.interact
		entries[#entries + 1] = { text = text, color = c, kind = resolvedKind }
	end

	local firearmRep = Bridge.getEquippedFirearmReplicator(actor)
	if firearmRep then
		if firearmRep._ads == true then
			add("weapon", "Aiming")
		end
		if firearmRep._reload and espAnimPlaying(firearmRep._reload) then
			add("reload", "Reloading")
		elseif firearmRep._reload_fp and espAnimPlaying(firearmRep._reload_fp) then
			add("reload", "Reloading")
		end
		if espFirearmDischarging(firearmRep) then
			add("weapon", "Firing")
		end
		local bipod = rawget(firearmRep, "_bipod")
		if type(bipod) == "table" and bipod.Reloading then
			add("reload", "Reloading")
		end
	end

	if actor.Focused == true then
		add("weapon", "Aiming")
	elseif actor.ADS == true then
		add("weapon", "ADS")
	end
	local kit = actor.AnimationKit
	if type(kit) == "string" and string.find(kit, "Aiming", 1, true) then
		add("weapon", "Aiming")
	end
	if actor._reloading or actor.Reloading then
		add("reload", "Reloading")
	end
	if actor.CQB and actor.CQB ~= 0 then
		add("weapon", "CQB")
	end

	local state = tableField(actor, "CurrentState")
	if type(state) == "table" then
		if stateTruthy(state.LootInventory) then add("interact", "Looting") end
		if stateTruthy(state.Dragging) then add("interact", "Dragging") end
		if stateTruthy(state.Dragged) then add("interact", "Dragged") end
		if stateTruthy(state.Climbing) then add("interact", "Climbing") end
		if stateTruthy(state.Downed) then add("stance", "Downed") end
		if stateTruthy(state.Medical) then add("interact", "Medical") end
		if stateTruthy(state.LockPick) then add("interact", "Lockpick") end
		if stateTruthy(state.Hostage) then add("interact", "Hostage") end
		if stateTruthy(state.TakeDown) then add("weapon", "Takedown") end
	end

	if actor.Sprinting then add("move", "Sprinting") end
	local slideT = rawget(actor, "_sliding")
	if type(slideT) == "number" and tick() - slideT < 1.1 then
		add("move", "Sliding")
	end
	if actor.Sliding then add("move", "Sliding") end
	if actor.Swimming then add("move", "Swimming") end

	local chs = Bridge.getCharacterHeightStateEnum()
	local hs = actor.HeightState
	if chs and type(hs) == "number" then
		if hs == chs.Proning then
			add("stance", "Prone")
		elseif hs == chs.Crouching then
			add("stance", "Crouching")
		end
	elseif actor.ProneDelay and tick() < actor.ProneDelay then
		add("stance", "Prone")
	end

	return entries
end

function Bridge.getActorStatusEntriesCached(data, maxAge)
	if not data then return {} end
	maxAge = maxAge or 0.22
	local now = os.clock()
	if data._statusCache and now - (data._statusCacheT or 0) < maxAge then
		return data._statusCache
	end
	local entries = Bridge.getActorStatusEntries(data)
	data._statusCache = entries
	data._statusCacheT = now
	return entries
end

function Bridge.getActorStatusTags(data)
	local entries = Bridge.getActorStatusEntries(data)
	local tags = {}
	for _, e in ipairs(entries) do
		tags[#tags + 1] = e.text
	end
	return tags
end

-- Шрифт Drawing (2D ESP) не умеет рисовать не-ASCII (кириллица/CJK/эмодзи имён
-- NPC) → выводит "???". Определяем «читаемо ли имя»: разрешаем печатаемый ASCII
-- (0x20..0x7E). Если в строке есть иные байты — считаем нерендерящейся.
function Bridge.isRenderableName(s)
	if type(s) ~= "string" or s == "" then return false end
	for i = 1, #s do
		local b = string.byte(s, i)
		if b < 32 or b > 126 then return false end
	end
	return true
end

function Bridge.formatEspActorLabel(data)
	local label = data.label
	-- Защита: если метка нерендерящаяся (например, кириллическое имя NPC) —
	-- откатываемся на человекочитаемую метку класса вместо "???".
	if type(label) == "string" and label ~= "" and not Bridge.isRenderableName(label) then
		local c = data.class
		if c == "npc_zombie" then label = "Zombie"
		elseif c == "npc_hostile" then label = "Hostile"
		elseif c == "npc_friendly" then label = "Friendly"
		elseif c == "npc" then label = "NPC"
		elseif c == "dead" then label = "Dead"
		else label = "Player" end
	end
	return label or "?"
end

function Bridge.weaponInfoFromItem(item)
	if type(item) ~= "table" then return nil end
	local n, c, m = Bridge.extractWeaponMagFromItem(item)
	if not n and not c then
		local rawName = rawget(item, "Name")
		if type(rawName) == "string" then
			n = Bridge.firearmDisplayName(item)
		end
	end
	if not n and not c then return nil end
	return { name = n or "?", cur = c, max = m }
end

function Bridge.weaponInfoFromHandler(h)
	if type(h) ~= "table" then return nil end
	local item = tableField(h, "_item") or tableField(h, "Item")
	local info = item and Bridge.weaponInfoFromItem(item)
	if not info then
		local firearm = tableField(h, "_firearm")
		local fname = type(firearm) == "table" and rawget(firearm, "Name")
		if type(fname) == "string" then
			info = { name = Bridge.firearmDisplayName({ Name = fname }), cur = nil, max = nil }
		end
	end
	if not info then return nil end

	local firearm = tableField(h, "_firearm")
	local tune = type(firearm) == "table" and rawget(firearm, "Tune")
	if type(tune) == "table" and type(tune.Ammo) == "number" then
		info.max = tune.Ammo
	end

	local loaded = rawget(h, "_bulletsLoaded")
	if type(loaded) == "number" then
		info.cur = loaded
	end

	local mag = rawget(h, "_mag")
	if type(mag) == "table" then
		if type(mag.Max) == "number" then info.max = mag.Max end
		if type(mag.MaxCapacity) == "number" and not info.max then
			info.max = mag.MaxCapacity
		end
	end

	local meta = item and rawget(item, "MetaData")
	if type(meta) == "table" and meta.Chamber == true and type(info.cur) == "number" then
		info.cur += 1
	end
	return info
end

function Bridge.parseActorWeaponInfo(data)
	if not data then return nil end
	if not Bridge.shouldEspWeaponInfo(data) then return nil end
	local actor = data.actorData
	if type(actor) ~= "table" and data.uid then
		actor = Bridge.getReplicatorActorData(data.uid)
	end
	local mods = State.sharedModules or Bridge.loadSharedModules()

	if type(actor) == "table" then
		local eqUid = tableField(actor, "_equipped")
		local state = tableField(actor, "CurrentState")
		if type(state) == "table" and (type(eqUid) ~= "string" or eqUid == "") then
			eqUid = tableField(state, "Equip")
		end

		if type(eqUid) == "string" and eqUid ~= "" then
			local item = Bridge.readEquippedItem(actor, eqUid)
			local handler = Bridge.findFirearmHandler(actor, eqUid)
			local info = item and Bridge.weaponInfoFromItem(item) or nil
			if not info and handler then
				info = Bridge.weaponInfoFromHandler(handler)
			end
			if info then
				local cur = Bridge.findBulletsLoadedOnActor(actor, eqUid)
				if type(cur) == "number" then
					info.cur = cur
				end
				local maxMag = Bridge.resolveMagMax(handler, item, mods)
				if type(maxMag) == "number" then
					info.max = maxMag
				end
				local meta = item and rawget(item, "MetaData")
				if type(meta) == "table" and meta.Chamber == true and type(info.cur) == "number" then
					info.cur += 1
				end
				if data.model then
					local fm = Bridge.findFirearmModelOnCharacter(data.model)
					local vis, tot = Bridge.countVisibleBulletsOnWeaponModel(fm)
					if type(vis) == "number" then
						info.cur = vis
						info.visual = true
						if type(tot) == "number" then
							info.max = tot
						end
					end
				end
				return info
			end
		end

		local handlers = tableField(actor, "_inventory")
		if type(handlers) == "table" then
			for _, h in pairs(handlers) do
				if type(h) == "table" and rawget(h, "_equipped") == true then
					local info = Bridge.weaponInfoFromHandler(h)
					if info then return info end
				end
			end
		end
	end

	if data and data.model then
		local fm = Bridge.findFirearmModelOnCharacter(data.model)
		local vis, tot = Bridge.countVisibleBulletsOnWeaponModel(fm)
		if type(vis) == "number" then
			local info = data.weaponInfo or {}
			if not info.name and fm then
				info.name = string.gsub(fm.Name, "^FirearmPrimary", ""):gsub("^FirearmSecondary", "")
			end
			info.cur = vis
			if type(tot) == "number" then
				info.max = info.max or tot
			end
			return info.name and info or nil
		end
	end

	return nil
end


local function resolveActorCharacterModel(uid, actorData)
	if type(actorData) ~= "table" then
		return findModelByActorUid(uid)
	end
	-- FIX v3: для NPC/ботов самый быстрый путь — actorData.Character напрямую
	-- Это работает потому что ActorClass.new хранит Character = v229 (клонированная Male модель)
	local directChar = rawget(actorData, "Character")
	if typeof(directChar) == "Instance" and directChar:IsA("Model") and directChar.Parent then
		return directChar
	end
	local owner = tableField(actorData, "Owner")
	if typeof(owner) == "Instance" and owner:IsA("Player") then
		-- FIX v12: Player.Character — стандартный Roblox respawn путь (обновляется мгновенно)
		local pChar = owner.Character
		if typeof(pChar) == "Instance" and pChar:IsA("Model") and pChar.Parent then
			local modelUid = select(1, getActorUidFromModel(pChar))
			if not modelUid or modelUid == uid then
				return pChar
			end
		end
		-- Fallback: WorldModel.Male (внутренний Flux путь)
		local wm = owner:FindFirstChild("WorldModel")
		if wm then
			local male = wm:FindFirstChild("Male")
			if male and male:IsA("Model") and male.Parent then
				local modelUid = select(1, getActorUidFromModel(male))
				if not modelUid or modelUid == uid then
					return male
				end
			end
		end
	end
	local lodInst = tableField(actorData, "LOD")
	if typeof(lodInst) == "Instance" and lodInst:IsA("Model") and lodInst.Parent then
		return lodInst
	end
	local lodTbl = tableField(actorData, "_lod")
	if type(lodTbl) == "table" then
		for _, key in ipairs({ "Character", "Model", "Male", "Rig" }) do
			local nested = tableField(lodTbl, key)
			if typeof(nested) == "Instance" and nested:IsA("Model") and nested.Parent then
				return nested
			end
		end
	end
	local charKeys = { "Character", "Model", "Rig", "Ragdoll", "Corpse", "Body" }
	for _, key in ipairs(charKeys) do
		local char = tableField(actorData, key)
		if typeof(char) == "Instance" then
			if char:IsA("Model") and char.Parent then
				local modelUid = select(1, getActorUidFromModel(char))
				if not modelUid or modelUid == uid then
					return char
				end
			elseif char:IsA("Folder") then
				local nested = char:FindFirstChild("Male") or char:FindFirstChildWhichIsA("Model")
				if nested and nested:IsA("Model") and nested.Parent then
					return nested
				end
			end
		end
	end
	return findModelByActorUid(uid)
end

local function findReplicatorPartForUid(char, uid)
	if not char or not char:IsA("Model") then return nil end
	for _, name in ipairs(CORE_PARTS) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") and p:GetAttribute("ActorUID") == uid then
			return p
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = hum and hum:FindFirstChild("Root")
	if root and root:IsA("BasePart") and root:GetAttribute("ActorUID") == uid then
		return root
	end
	return char:FindFirstChild("Head") or char:FindFirstChild("UpperTorso")
end

local function considerReplicatorActor(uid, actorData, found)
	-- FIX v3: uid уже нормализован через tostring в scanReplicatorActors
	if type(actorData) ~= "table" then return end
	if type(uid) ~= "string" or uid == "" then return end

	local prev = found[uid]
	if prev and prev.actorData == actorData and prev.model and prev.model.Parent
		and prev.root and prev.root.Parent then
		local deadFlag = isModelDead(prev.model, actorData)
		if prev.dead == deadFlag then
			found[uid] = prev
			return
		end
	end

	-- FIX v5: определяем является ли актор NPC до workspace-обращений
	local isNpcActor = rawget(actorData, "Owner") == nil
	local camInst = workspace and workspace.CurrentCamera
	local camPos = camInst and camInst.CFrame.Position

	-- FIX v5: NPC fast path — actorData.Character уже есть, workspace не нужен
	if isNpcActor then
		local directChar = rawget(actorData, "Character")
		if typeof(directChar) ~= "Instance" or not directChar:IsA("Model") or not directChar.Parent then
			return -- NPC без Character = не рендерится, пропускаем
		end
		-- Дистанционный фильтр для NPC
		if camPos then
			-- v18 PATCH: используем кэшированный root из prev (Character тот же) вместо FindFirstChild
			local rootForDist = (prev and prev.model == directChar and prev.root)
				or directChar.PrimaryPart
				or directChar:FindFirstChild("HumanoidRootPart")
				or directChar:FindFirstChild("UpperTorso")
				or directChar:FindFirstChild("Head")
			if rootForDist and rootForDist:IsA("BasePart") then
				local p = rootForDist.Position
				local distSq = (p.X-camPos.X)^2 + (p.Y-camPos.Y)^2 + (p.Z-camPos.Z)^2
				local isZombieData = rawget(actorData, "Zombie") == true
				local espMaxDist = CONFIG.EspMaxDistance or 1800
				local maxDistSq = isZombieData and (200*200) or (espMaxDist * espMaxDist)
				if distSq > maxDistSq then return end
			end
		end
		-- Для NPC: обновляем только если что-то изменилось (health/dead)
		local hp = tableField(actorData, "Health")
		local deadFlag = isModelDead(directChar, actorData)
		if prev and prev.model == directChar and prev.actorData == actorData
			and prev.dead == deadFlag and prev.root and prev.root.Parent
			and prev.health == hp then
			found[uid] = prev
			return
		end
		-- NPC root: берём напрямую без actorEspRoot (избегаем FindFirstChild-цепочку)
		-- v18 PATCH: NPC root — кэш через prev.root если Character не сменился
		local root = (prev and prev.model == directChar and prev.root)
			or directChar.PrimaryPart
			or directChar:FindFirstChild("HumanoidRootPart")
			or directChar:FindFirstChild("UpperTorso")
			or directChar:FindFirstChild("Head")
		if not root then return end
		-- NPC class: определяем через TargetGroup/Zombie
		local npcClass, npcLabel
		if rawget(actorData, "Zombie") == true then
			npcClass = "npc_zombie"; npcLabel = "Zombie"
		else
			local tg = directChar:GetAttribute("TargetGroup")
			if tg == 0 then npcClass = "npc_friendly"; npcLabel = "Friendly"
			else npcClass = "npc_hostile"; npcLabel = "Hostile" end
		end
		local ownerName = tableField(actorData, "OwnerName") or tableField(actorData, "Name")
		-- Берём кастомное имя NPC ТОЛЬКО если оно рендерится Drawing-шрифтом.
		-- Кириллические/CJK имена давали "???" — для них оставляем метку класса.
		if ownerName and ownerName ~= "" and Bridge.isRenderableName(ownerName) then
			npcLabel = ownerName
		end
		if deadFlag then npcClass = "dead"; npcLabel = "Dead" end
		if Bridge.shouldSkipActorCollect(npcClass, nil, nil, nil, uid) then return end
		found[uid] = {
			model = directChar,
			uid = uid,
			class = npcClass,
			label = npcLabel,
			player = nil,
			teamKey = npcClass,
			squad = nil,
			root = root,
			path = nil, -- не нужен для NPC
			collisionGroup = "replicator",
			alive = not deadFlag,
			dead = deadFlag,
			actorData = actorData,
			health = hp,
			maxHealth = tableField(actorData, "MaxHealth") or tableField(actorData, "MaxHP"),
			weaponInfo = nil,
		}
		return
	end

	-- Путь для игроков (Owner != nil)
	local char = resolveActorCharacterModel(uid, actorData)
	if typeof(char) ~= "Instance" or not char:IsA("Model") or not char.Parent then
		return
	end
	-- FIX v7 ZMP: Character может быть в LocalPlayer.WorldModel (InactiveWorld)
	-- пока актор ещё не "loaded". Проверяем флаг и сохраняем позицию из actorData.
	local inInactiveWorld = false
	do
		local charParent = char.Parent
		if charParent and charParent:IsA("WorldModel") then
			local wpParent = charParent.Parent
			if wpParent and wpParent:IsA("Player") then
				inInactiveWorld = true
			end
		end
	end
	if camPos then
		-- FIX v7: InactiveWorld персонажи — rootForDist.Position = Vector3(0,0,0) или stale
		-- Используем actorData.Position для distance check чтобы не пропустить ближних игроков
		local distP
		if inInactiveWorld then
			local ap = tableField(actorData, "SimulatedPosition") or tableField(actorData, "ServerPosition") or tableField(actorData, "Position")
			if typeof(ap) == "Vector3" then distP = ap end
		end
		if not distP then
			local rootForDist = char:FindFirstChild("HumanoidRootPart")
				or char:FindFirstChild("UpperTorso") or char.PrimaryPart
			if rootForDist and rootForDist:IsA("BasePart") then
				distP = rootForDist.Position
			end
		end
		if distP then
			local distSq = (distP.X-camPos.X)^2 + (distP.Y-camPos.Y)^2 + (distP.Z-camPos.Z)^2
			local espMaxDist = CONFIG.EspMaxDistance or 1800
			if distSq > (espMaxDist * espMaxDist) then return end -- глобальный лимит
		end
	end

	local part = findReplicatorPartForUid(char, uid)
	local deadFlag = isModelDead(char, actorData)
	-- FIX v11: respawn detection на уровне considerReplicatorActor
	-- Если prev был dead/не было записи, а сейчас char живой → добавить в priority queue
	if prev and prev.dead and not deadFlag then
		State._playerPriorityQueue = State._playerPriorityQueue or {}
		table.insert(State._playerPriorityQueue, 1, uid)
	end
	if prev and prev.model == char and prev.actorData == actorData
		and prev.dead == deadFlag and prev.root and prev.root.Parent then
		-- FIX v7: InactiveWorld — всегда обновляем adPos в кэше (actorData.Position меняется каждый тик)
		if inInactiveWorld then
			local rp = tableField(actorData, "SimulatedPosition") or tableField(actorData, "ServerPosition") or tableField(actorData, "Position")
			if typeof(rp) == "Vector3" then
				prev.adPos = rp
				prev.inInactiveWorld = true
			end
		end
		found[uid] = prev
		return
	end

	local root = actorEspRoot(char)
	if not root then return end

		local class, label = classifyReplicatorActor(uid, actorData, char, part)
		-- FIX: раньше label затирался на "Dead" ДО resolvePlayerFromActor. У трупа
		-- Owner/OwnerName часто уже очищены, поэтому резолв падал на поиск игрока по
		-- имени "Dead" → player=nil → рендер трупа игрока скрывался (EspShowDead-гейт
		-- требует data.player ~= nil). Резолвим игрока по РЕАЛЬНОМУ имени/кэшу uid
		-- ПЕРЕД подменой на "Dead" — тогда мёртвые игроки снова видны.
		local player = Bridge.resolvePlayerFromActor(uid, actorData, label)
		if deadFlag then
			class, label = "dead", "Dead"
		end
		local teamKey = Bridge.resolveActorTeamKey(uid, actorData, char, label)
		local squad = Bridge.resolveActorSquad(uid, actorData, label, player)
	-- FIX v8: ForceShowAllPlayers — не скипать игроков даже если shouldSkipActorCollect=true
	local skipThis = Bridge.shouldSkipActorCollect(class, player, squad, teamKey, uid)
	if skipThis then
		if not (CONFIG.ForceShowAllPlayers == true and class == "player") then
			return
		end
	end
	-- FIX v6 ZMP: для InactiveWorld персонажей сохраняем fallback позицию из actorData
	local adPos = nil
	if inInactiveWorld then
		local rp = tableField(actorData, "SimulatedPosition") or tableField(actorData, "ServerPosition") or tableField(actorData, "Position")
		if typeof(rp) == "Vector3" then adPos = rp end
	end
	found[uid] = {
		model = char,
		uid = uid,
		class = class,
		label = label,
		player = player,
		teamKey = teamKey,
		squad = squad,
		root = root,
		path = char:GetFullName(),
		collisionGroup = normalizeCollisionGroup(part and part.CollisionGroup) or "replicator",
		alive = not deadFlag,
		dead = deadFlag,
		actorData = actorData,
		health = tableField(actorData, "Health"),
		maxHealth = tableField(actorData, "MaxHealth") or tableField(actorData, "MaxHP"),
		weaponInfo = nil,
		inInactiveWorld = inInactiveWorld,
		adPos = adPos,
	}
	rememberActorModel(uid, char)
end

local function syncReplicatorActorsTable()
	resolveLocalClient(false)
	local client = State.localClient
	if not client or type(Bridge.getActorTable) ~= "function" then return end
	local actor = Bridge.getActorTable(client)
	if not actor then return end
	local rep = tableField(actor, "Replicator")
	if type(rep) ~= "table" then return end
	local actors = tableField(rep, "Actors")
	if type(actors) ~= "table" then return end
	State.replicatorActorsTable = actors
	State.repSyncSource = nil
end

local function considerReplicatorPlayersOnly(found)
	local rep = State.replicatorActorsTable
	if not rep then return end
	for uid, actorData in pairs(rep) do
		if type(actorData) ~= "table" or rawget(actorData, "Owner") == nil then
			continue
		end
		local suid = type(uid) == "number" and tostring(uid) or uid
		if type(suid) == "string" and suid ~= "" then
			considerReplicatorActor(suid, actorData, found)
		end
	end
end

local function scanReplicatorActors(found)
	syncReplicatorActorsTable()
	local rep = State.replicatorActorsTable
	if not rep or not found then return end
	for uid, actorData in pairs(rep) do
		local suid = type(uid) == "number" and tostring(uid) or uid
		if type(suid) == "string" and suid ~= "" then
			considerReplicatorActor(suid, actorData, found)
		end
	end
end

local function considerModel(model, found)
	local uid, part = getActorUidFromModel(model)
	if not uid then
		if isModelDead(model, nil) and isActorCorpseModel(model) then
			uid = "corpse:" .. model:GetFullName()
		else
			return
		end
	end
	if found[uid] then return end

	if CONFIG.LogAttributesOnce then
		logModelAttributesOnce(model, part)
	end

	local root = model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Head")
		or part
		or model:FindFirstChildWhichIsA("BasePart")
	if not root then return end

	local actorData = Bridge.getReplicatorActorData and Bridge.getReplicatorActorData(uid) or nil
	local class, label = classifyActor(uid, part, model, actorData)
	local dead = isModelDead(model, actorData)
	if dead then
		class, label = "dead", "Dead"
	end
	local player = Bridge.resolvePlayerFromActor(uid, actorData, label)
		or State.uidToPlayer[uid] or State.modelToPlayer[model]
	local teamKey = Bridge.resolveActorTeamKey(uid, actorData, model, label)
	local squad = Bridge.resolveActorSquad(uid, actorData, label, player)
	-- FIX v8: ForceShowAllPlayers — не скипать игроков даже если shouldSkipActorCollect=true
	local skipThis = Bridge.shouldSkipActorCollect(class, player, squad, teamKey, uid)
	if skipThis then
		if not (CONFIG.ForceShowAllPlayers == true and class == "player") then
			return
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	found[uid] = {
		model = model,
		uid = uid,
		class = class,
		label = label,
		player = player,
		teamKey = teamKey,
		squad = squad,
		root = root,
		path = model:GetFullName(),
		collisionGroup = normalizeCollisionGroup(part and part.CollisionGroup) or "?",
		alive = not dead,
		dead = dead,
		actorData = actorData,
		health = (actorData and tableField(actorData, "Health")) or (hum and hum.Health),
		maxHealth = (actorData and (tableField(actorData, "MaxHealth") or tableField(actorData, "MaxHP")))
			or (hum and hum.MaxHealth),
		weaponInfo = nil,
	}
	rememberActorModel(uid, model)
end

local function finalizeActorScan(found)
	local prev = State.actors or {}
	local maxTracked = CONFIG.MaxTrackedActors or 128
	local prevCount = 0
	for _ in pairs(prev) do prevCount += 1 end
	if prevCount < maxTracked then
		for uid, data in pairs(prev) do
			if not found[uid] and data.model and data.model.Parent then
				-- Мёртвого держим ТОЛЬКО если это игрок и включён EspShowDead —
				-- иначе (труп NPC / показ выключен) отпускаем как раньше. Без этого
				-- между смертью и следующим полным сканом труп игрока мигал/пропадал.
				local isDead = Bridge.isActorDead(data)
				local keepDead = isDead and CONFIG.EspShowDead ~= false and data.player ~= nil
				-- FIX v9: не держим актора если его root пропал (respawn удалил персонажа)
				if (not isDead or keepDead) and data.root and data.root.Parent then
					found[uid] = data
				end
			end
		end
	end
	local tracked = 0
	for uid in pairs(found) do
		tracked += 1
		if tracked > maxTracked then
			found[uid] = nil
		end
	end
	-- FIX v3: инвалидируем enemy cache при пересборке actors
	State._aimEnemyCache = nil
	State._aimEnemyCacheT = 0

	local newCount = 0
	for _ in pairs(found) do newCount += 1 end
	if newCount == 0 and next(prev) ~= nil then
		local kept = {}
		local keptCount = 0
		for uid, data in pairs(prev) do
			local model = data and data.model
			local root = data and data.root
			if model and model.Parent and root and root.Parent then
				kept[uid] = data
				keptCount += 1
			end
		end
		if keptCount > 0 then
			State.actors = kept
			State.trackedActorCount = keptCount
			State.repSyncSource = nil
			Bridge.refreshActorSquads()
			log("SCAN", "actors", keptCount, "(kept-valid)", "clients", State.clientsSource or "?")
			return
		end
		State.actors = {}
		State.repSyncSource = nil
		Bridge.refreshActorSquads()
		log("SCAN", "actors", 0, "(cleared-stale)", "clients", State.clientsSource or "?")
		return
	end

	State.actors = found
	State.trackedActorCount = newCount
	State.espActorList = nil
	State.repSyncSource = nil
	Bridge.refreshActorSquads()
	log("SCAN", "actors", newCount, "clients", State.clientsSource or "?")
end

local function gatherPlayerMaleModels()
	local seen = {}
	local list = {}
	local function add(model)
		if not model or seen[model] or not isMaleModel(model) or not model.Parent then return end
		seen[model] = true
		list[#list + 1] = model
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local wm = plr:FindFirstChild("WorldModel")
			local male = wm and wm:FindFirstChild("Male")
			if male and male:IsA("Model") then
				add(male)
			end
		end
	end
	if State.localModel and State.localModel.Parent then
		add(State.localModel)
	end
	return list
end

local function scanActors()
	if State.scanBusy then return end
	local perfT = Bridge.perfBegin()
	State.scanBusy = true
	State.actorScanNoGc = true
	loadClientsModule()
	local now_s = os.clock()
	if now_s - (State.lastUidMapRebuild or 0) > 5 then
		State.lastUidMapRebuild = now_s
		rebuildUidMap(false)
	end
	resolveLocalPlayer()
	resolveLocalClient(false)
	Bridge.refreshLocalTeamKey()
	local found = {}
	-- FIX v20: полн��й O(N) проход по Replicator.Actors убран — NPC подтягиваются батчами.
	syncReplicatorActorsTable()
	considerReplicatorPlayersOnly(found)
	for _, model in ipairs(gatherPlayerMaleModels()) do
		considerModel(model, found)
	end
	finalizeActorScan(found)
	State.actorScanNoGc = false
	State.scanBusy = false
	Bridge.perfEnd("scanActors", perfT, "found=" .. tostring(countTableKeys(found)))
end

local sortRepSyncQueue

local function ensureRepSyncQueue()
	local rep = State.replicatorActorsTable
	if not rep then
		Bridge.getReplicatorActorData("__probe__")
		rep = State.replicatorActorsTable
	end
	if not rep then return nil end
	-- FIX v12: перестраиваем очередь если rep изменился ИЛИ её нет
	if State.repSyncSource ~= rep or not State.repSyncQueue then
		State.repSyncSource = rep
		State.repSyncQueue = {}
		State._repSyncSet = {}
		State._newActorPriorityQueue = {}
		for uid in pairs(rep) do
			local suid = type(uid) == "number" and tostring(uid) or uid
			if type(suid) == "string" and suid ~= "" then
				State.repSyncQueue[#State.repSyncQueue + 1] = suid
				State._repSyncSet[suid] = true
			end
		end
		State.repSyncIndex = 1
		if sortRepSyncQueue then sortRepSyncQueue(rep, true) end
	else
		-- FIX v12: динамически добавляем НОВЫЕ UIDs (новые игроки/акторы) в конец очереди
		-- Без этого новый актор попадёт в скан только через EspFullRescanInterval (60s)
		local now = os.clock()
		local scanInterval = CONFIG.RepSyncQueueScanSec or 2.5
		if now - (State._repSyncLastScan or 0) >= scanInterval then
			State._repSyncLastScan = now
			local set = State._repSyncSet or {}
			State._repSyncSet = set
			State._newActorPriorityQueue = State._newActorPriorityQueue or {}
			local napq = State._newActorPriorityQueue
			for uid in pairs(rep) do
				local suid = type(uid) == "number" and tostring(uid) or uid
				if type(suid) == "string" and suid ~= "" and not set[suid] then
					local pad = rep[uid] or rep[tonumber(uid)]
					local insertAt = State.repSyncIndex or 1
					if type(pad) == "table" and rawget(pad, "Zombie") == true then
						insertAt = 1
					end
					table.insert(State.repSyncQueue, insertAt, suid)
					set[suid] = true
					-- НОВЫЙ актор (в т.ч. NPC): в приоритетную очередь, чтобы попасть
					-- в скан на СЛЕДУЮЩЕМ тике в обход NPC-троттла (иначе ~минута ожидания)
					napq[#napq + 1] = suid
				end
			end
			if sortRepSyncQueue then sortRepSyncQueue(rep, false) end
		end
	end
	return rep
end

local function isZombieActorData(actorData)
	return type(actorData) == "table" and rawget(actorData, "Zombie") == true
end

local function tickRepSyncBatch(batchSize)
	if State.scanBusy then return end
	local perfT = Bridge.perfBegin()
	local processed, skippedNpc = 0, 0
	batchSize = batchSize or CONFIG.ActorSyncBatchSize or 12
	local rep = ensureRepSyncQueue()
	if not rep then
		Bridge.perfEnd("rep.batch", perfT, "no_rep")
		return
	end
	State.actors = State.actors or {}
	local queue = State.repSyncQueue
	if not queue or #queue == 0 then
		Bridge.perfEnd("rep.batch", perfT, "empty")
		return
	end

	-- FIX v11: Player Priority Queue — игроки обновляются НЕМ��ДЛЕННО, без ожидания своей очереди
	-- Это решает respawn задержку: при смерти/respawn игрок мог ждать полный проход 200+ NPC
	State._playerPriorityQueue = State._playerPriorityQueue or {}
	local ppq = State._playerPriorityQueue
	if #ppq > 0 then
		for pi = #ppq, 1, -1 do
			local puid = ppq[pi]
			local pad = rep[puid] or rep[tonumber(puid)]
			if pad then
				considerReplicatorActor(puid, pad, State.actors)
			end
			table.remove(ppq, pi)
		end
	end

	-- НОВЫЕ акторы (включая NPC): обрабатываем немедленно, в обход NPC-троттла.
	-- Раньше новый NPC ждал полного прохода очереди (~минута на плотных картах).
	local napq = State._newActorPriorityQueue
	if napq and #napq > 0 then
		local cap = CONFIG.NewActorPriorityPerTick or 24
		local done = 0
		while #napq > 0 and done < cap do
			local nuid = table.remove(napq, 1)
			local nad = rep[nuid] or rep[tonumber(nuid)]
			if nad then
				considerReplicatorActor(nuid, nad, State.actors)
				processed = processed + 1
			end
			done = done + 1
		end
	end

	local idx = State.repSyncIndex or 1
	local endIdx = math.min(idx + batchSize - 1, #queue)
	State._npcThrottleCounter = (State._npcThrottleCounter or 0) + 1
	local npcCount = Bridge.countTrackedNpcs()
	local npcEvery = 5
	if npcCount >= 30 then
		npcEvery = 8
	elseif npcCount >= 20 then
		npcEvery = 7
	elseif npcCount >= 12 then
		npcEvery = 6
	end
	local processNpc = (State._npcThrottleCounter % npcEvery == 0)
	for i = idx, endIdx do
		local uid = queue[i]
		local actorData = rep[uid] or rep[tonumber(uid)]
		if actorData then
			local isNpc = rawget(actorData, "Owner") == nil
			local isZombie = isNpc and isZombieActorData(actorData)
			if isNpc and not isZombie and not processNpc then
				-- keep prev NPC entry
				skippedNpc += 1
			else
				local prevEntry = State.actors[uid]
				local prevDead = prevEntry and prevEntry.dead
				considerReplicatorActor(uid, actorData, State.actors)
				processed += 1
				-- FIX v11: respawn detection
				-- Если игрок был dead/отсутствовал и теперь появился → приоритетный перепрогон
				if not isNpc then
					local curEntry = State.actors[uid]
					if curEntry and not curEntry.dead and (not prevEntry or prevDead) then
						-- немедленный полный скан через pendingPlayerRescan
						State.pendingPlayerRescan = true
					end
				end
			end
		end
	end
	State.repSyncIndex = endIdx + 1
	if State.repSyncIndex > #queue then
		State.repSyncIndex = 1
		local count = 0
		for _ in pairs(State.actors) do count += 1 end
		State.trackedActorCount = count
	end
	Bridge.perfEnd("rep.batch", perfT, string.format("%d/%d skipNpc=%d", processed, batchSize, skippedNpc))
end

function Bridge.queueFullActorScan()
	State.pendingFullScan = true
end

function Bridge.tickActorScan()
	if not State.pendingFullScan or State.scanBusy then
		return false
	end
	State.pendingFullScan = false
	scanActors()
	return true
end

local function actorDataWorldPos(actorData)
	if type(actorData) ~= "table" then return nil end
	for _, key in ipairs({ "SimulatedPosition", "ServerPosition", "Position" }) do
		local p = rawget(actorData, key)
		if typeof(p) == "Vector3" then return p end
	end
	local char = rawget(actorData, "Character")
	if typeof(char) == "Instance" and char:IsA("Model") and char.Parent then
		local root = char.PrimaryPart
			or char:FindFirstChild("HumanoidRootPart")
			or char:FindFirstChild("UpperTorso")
			or char:FindFirstChild("Head")
		if root and root:IsA("BasePart") then return root.Position end
	end
	return nil
end

local function repSyncPriority(rep, uid, origin)
	local actorData = rep[uid] or rep[tonumber(uid)]
	if type(actorData) ~= "table" then return math.huge end
	local owner = rawget(actorData, "Owner")
	local isNpc = owner == nil
	local isZombie = rawget(actorData, "Zombie") == true
	local p = origin and actorDataWorldPos(actorData)
	local distSq = p and ((p.X - origin.X)^2 + (p.Y - origin.Y)^2 + (p.Z - origin.Z)^2) or 999999999
	if not isNpc then return distSq end
	if isZombie then
		return 1000000 + distSq
	end
	return 2000000 + distSq
end

sortRepSyncQueue = function(rep, force)
	local queue = State.repSyncQueue
	if not queue or #queue < 2 then return end
	local now = os.clock()
	if not force and now - (State._repSyncLastSort or 0) < (CONFIG.RepSyncQueueSortSec or 2.0) then return end
	State._repSyncLastSort = now
	local cam = workspace and workspace.CurrentCamera
	local origin = cam and cam.CFrame.Position
	if not origin then
		local char = LP and LP.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
		origin = root and root.Position or nil
	end
	if not origin then return end
	table.sort(queue, function(a, b)
		return repSyncPriority(rep, a, origin) < repSyncPriority(rep, b, origin)
	end)
	State.repSyncIndex = 1
	Bridge.perfSet("repSorted", #queue)
end

local function updateActorVelocity(uid, root)
	if type(uid) ~= "string" or uid == "" or not root or not root:IsA("BasePart") then return end
	local now = os.clock()
	local pos = root.Position
	local track = State.actorVelTrack[uid]
	if track and typeof(track.pos) == "Vector3" then
		local dt = now - (track.t or now)
		if dt >= 0.01 and dt <= 0.5 then
			local rawVel = (pos - track.pos) / dt
			-- FIX v9: EMA по скорости (alpha=0.35) — сглаживает зиг-заг без задержки позиции
			-- НЕ интерполируем позицию, только усредняем производную
			local prev = State.actorVelInstant[uid]
			if prev and typeof(prev) == "Vector3" and prev.Magnitude > 0.05 then
				State.actorVelInstant[uid] = prev:Lerp(rawVel, 0.35)
			else
				State.actorVelInstant[uid] = rawVel
			end
		end
	end
	State.actorVelTrack[uid] = { pos = pos, t = now }
end

Bridge.updateActorVelocity = updateActorVelocity

local function refreshActorsForEsp()
	if State.scanBusy then return end
	local perfT = Bridge.perfBegin()
	local now = os.clock()
	-- FIX v10: startup guard — первые 4s после запуска скрипта не делаем тяжёлый скан
	-- Это убирает фриз при первом запуске (особенно на картах с NPC)
	State._startTime = State._startTime or now
	if now - State._startTime < 4.0 then
		Bridge.perfEnd("esp.refresh", perfT, "startup")
		return
	end
	local fullInterval = CONFIG.EspFullRescanInterval or 60.0
	-- FIX FPS: при первом запуске НЕ делаем тяжёлый scanActors()
	-- Устанавливаем lastEspFullRescan=now, данные строятся батчами (12 NPC/тик)
	if State.lastEspFullRescan == -1 then
		State.lastEspFullRescan = now
		tickRepSyncBatch(CONFIG.ActorSyncBatchSize or 12)
		Bridge.perfEnd("esp.refresh", perfT, "init_batch")
		return
	end
	-- FIX v10: немедленный полный скан при обнаружении нового игрока (respawn)
	if State.pendingPlayerRescan then
		State.pendingPlayerRescan = false
		State.lastEspFullRescan = now
		tickRepSyncBatch(math.max(CONFIG.ActorSyncBatchSize or 12, 16))
		Bridge.perfEnd("esp.refresh", perfT, "player_resync")
		return
	end
	if now - (State.lastEspFullRescan or 0) >= fullInterval then
		State.lastEspFullRescan = now
		State.espActorList = nil
		State.espRanked = nil
		tickRepSyncBatch(math.max(CONFIG.ActorSyncBatchSize or 12, 16))
	else
		local repSyncMin = CONFIG.RepSyncMinInterval or 0.35
		if now - (State.lastRepSyncBatch or 0) >= repSyncMin then
			State.lastRepSyncBatch = now
			tickRepSyncBatch(CONFIG.ActorSyncBatchSize or 12)
		end
	end
	if now - (State.lastSquadRefresh or 0) >= 10.0 then
		State.lastSquadRefresh = now
		Bridge.refreshActorSquads()
	end
	if Bridge.pruneStaleActors then
		Bridge.pruneStaleActors(now)
	end
	local repActors = State.replicatorActorsTable
	if not repActors then
		Bridge.getReplicatorActorData("__probe__")
		repActors = State.replicatorActorsTable
	end
	local actorList = State.espActorList
	if not actorList or now - (State.espActorListTime or 0) > 4.0 then
		actorList = {}
		for _, data in pairs(State.actors) do
			if data.model and data.model.Parent then
				actorList[#actorList + 1] = data
			end
		end
		State.espActorList = actorList
		State.espActorListTime = now
		State.espEnrichBatchIndex = 0
	end
	local batchSize = CONFIG.ActorEnrichBatchSize or CONFIG.EspBatchSize or 4
	local batchIdx = State.espEnrichBatchIndex or 0
	local startAt = batchIdx * batchSize + 1
	local endAt = math.min(startAt + batchSize - 1, #actorList)
	if startAt > #actorList then
		State.espEnrichBatchIndex = 0
		startAt = 1
		endAt = math.min(batchSize, #actorList)
	end
	for i = startAt, endAt do
		local data = actorList[i]
		if not data or not data.model or not data.model.Parent then continue end
		if Bridge.shouldSkipActorCollect(
			data.class, data.player, data.squad, data.teamKey, data.uid
		) then
			continue
		end
		if repActors and data.uid and not data.actorData then
			data.actorData = repActors[data.uid]
		end
		-- FIX v7 ZMP: обновляем adPos для InactiveWorld акторов каждые 0.5s
		if data.inInactiveWorld and data.actorData then
			local ad = data.actorData
			local p = rawget(ad, "SimulatedPosition") or rawget(ad, "ServerPosition") or rawget(ad, "Position")
			if typeof(p) == "Vector3" then data.adPos = p end
		end
		local prevNoGc = State.actorScanNoGc
		State.actorScanNoGc = true
		if data.class == "player" then
			local player = data.player or Bridge.resolvePlayerFromActor(data.uid, nil, data.label)
			if player then
				data.player = player
				data.squad = Bridge.getPlayerSquad(player, false)
			end
		end
		State.actorScanNoGc = prevNoGc
		if Bridge.shouldEspWeaponInfo(data)
			and not Bridge.isNpcActorClass(data.class) then
			Bridge.refreshActorWeaponInfo(data)
		else
			data.weaponInfo = nil
		end
		if data.uid and data.root and not Bridge.isNpcActorClass(data.class) then
			updateActorVelocity(data.uid, data.root)
		end
		local skipHeavy = Bridge.isNpcActorClass(data.class)
		if not skipHeavy then
			local humHp, humMax = Bridge.resolveActorHealth(data)
			if humHp ~= nil then
				data.health = humHp
				data.maxHealth = humMax
			end
		end
	end
	if endAt >= #actorList then
		State.espEnrichBatchIndex = 0
	else
		State.espEnrichBatchIndex = batchIdx + 1
	end
	Bridge.perfEnd("esp.refresh", perfT, string.format("enrich=%d-%d/%d", startAt, endAt, #actorList))
end

local function printSummary(verboseActors)
	local total, counts = 0, {}
	for _, data in pairs(State.actors) do
		total += 1
		counts[data.class] = (counts[data.class] or 0) + 1
	end
	log(
		"SCAN", "total", total,
		"| localUID", State.localActorUID and State.localActorUID:sub(1, 12) or "nil",
		"| clients", State.clientsSource or "?"
	)
	if State.summaryCount == 0 then
		logClientsRegistry()
	end
	for class, n in pairs(counts) do
		log("SCAN", class, n)
	end
	State.summaryCount += 1
	if verboseActors then
		for _, data in pairs(State.actors) do
			log("ACTOR", data.label, data.class, "col", data.collisionGroup, data.path)
		end
	end
end

-- ============================================================
-- WEAPON PARSER + HUD
-- ============================================================

local SLOT_LABELS = { "Primary", "Secondary", "Melee" }

-- Combat mods: LiteMultiPoint (full MultiPoint удалён)
function Bridge.combatModsActive()
	return CONFIG.LiteMultiPoint == true
end

function Bridge.liteMpActive()
	return CONFIG.LiteMultiPoint == true
end

function Bridge.getMultiPointMode()
	if CONFIG.LiteMultiPoint then return "litemp" end
	return nil
end

local function mpActive()
	return Bridge.liteMpActive()
end

function Bridge.setMultiPointMode(mode)
	if mode == "litemp" or mode == "lite" or mode == "multipoint" or mode == "blatant" or mode == "legit" then
		CONFIG.LiteMultiPoint = true
	elseif mode == "off" or mode == false or mode == nil then
		CONFIG.LiteMultiPoint = false
	end
	CONFIG.MultiPoint = false
end

function Bridge.loadSharedModules()
	if State.sharedModules then return State.sharedModules end
	local mods = {}

	local function tryGameModule(name)
		if type(shared) == "table" and type(shared.import) == "function" then
			local ok, m = pcall(shared.import, name)
			if ok and m ~= nil then return m end
			local ok2, req = pcall(shared.import, "require")
			if ok2 and type(req) == "function" then
				local ok3, m2 = pcall(req, name)
				if ok3 and m2 ~= nil then return m2 end
			end
		end
		local sharedRoot = RS:FindFirstChild("Shared")
		if sharedRoot then
			local inst = sharedRoot:FindFirstChild(name, true)
			if inst and inst:IsA("ModuleScript") then
				local ok4, m3 = pcall(require, inst)
				if ok4 then return m3 end
			end
		end
		local packages = RS:FindFirstChild("Packages")
		if packages then
			local inst = packages:FindFirstChild(name)
			if inst and inst:IsA("ModuleScript") then
				local ok5, m4 = pcall(require, inst)
				if ok5 then return m4 end
			end
		end
		return nil
	end

	mods.SharedInventory = tryGameModule("SharedInventory")
	mods.Enum = tryGameModule("Enum")
	mods.BaseComponent = tryGameModule("BaseComponent")
	mods.Calibers = tryGameModule("Calibers")
	mods.StorageLayout = tryGameModule("StorageLayout")
	mods.Melee = tryGameModule("Melee")
	State.sharedModules = mods
	return mods
end

local SLOT_TYPE_LABEL = {
	Primary = "Primary",
	Secondary = "Secondary",
	Melee = "Melee",
}

local SLOT_TYPE_NUM = {
	[3] = "Primary",
	[5] = "Secondary",
	[7] = "Melee",
}

function Bridge.slotTypeToLabel(slotType, mods)
	if type(slotType) == "number" then
		local lbl = SLOT_TYPE_NUM[slotType]
		if lbl then return lbl end
	end
	if type(slotType) == "string" then
		return SLOT_TYPE_LABEL[slotType] or slotType
	end
	if mods and mods.Enum and mods.Enum.SlotType then
		local st = mods.Enum.SlotType
		for name, id in pairs(st) do
			if id == slotType then
				return SLOT_TYPE_LABEL[name] or name
			end
		end
	end
	return nil
end

function Bridge.isInventoryTable(t)
	if type(t) ~= "table" then return false end
	if type(tableField(t, "Storages")) == "table" then return true end
	return type(tableField(t, "Change")) == "function"
		and type(tableField(t, "StoragesID")) == "number"
end

function Bridge.inventoryHasMainStorage(inv)
	if not Bridge.isInventoryTable(inv) then return false end
	local storages = tableField(inv, "Storages")
	if type(storages) ~= "table" then return false end
	for _, storage in pairs(storages) do
		if type(storage) == "table" and storage.StorageName == "Main" then
			return true
		end
	end
	return false
end

function Bridge.firearmDisplayName(item)
	if type(item) ~= "table" then return "-" end
	local name = rawget(item, "Name") or "?"
	return string.gsub(name, "^FirearmPrimary", ""):gsub("^FirearmSecondary", ""):gsub("^Melee", "")
end

function Bridge.isMeleeItem(item, mods)
	if type(item) ~= "table" then return false end
	local layout = rawget(item, "Layout")
	if layout and rawget(layout, "Handler") == "Melee" then return true end
	local name = rawget(item, "Name")
	return type(name) == "string" and string.match(name, "^Melee") ~= nil
end

function Bridge.isMeleeHandler(handler)
	if type(handler) ~= "table" then return false end
	if rawget(handler, "_firearm") or tableField(handler, "_fpFirearm") then return false end
	local build = rawget(handler, "_build")
	return type(build) == "string" and build ~= ""
end

function Bridge.isPlayerFirearmItem(item, mods)
	if type(item) ~= "table" then return false end
	local name = rawget(item, "Name")
	if type(name) ~= "string" then return false end
	if string.find(name, "AI", 1, true) then return false end
	if string.match(name, "^Firearm") or string.match(name, "^Melee") then return true end
	local layout = rawget(item, "Layout")
	if type(layout) == "table" then
		if rawget(layout, "Handler") == "Firearm" or rawget(layout, "Handler") == "Melee" then
			return true
		end
	end
	return false
end

function Bridge.slotLabelFromItem(item, mods)
	if type(item) ~= "table" then return nil end
	local layout = rawget(item, "Layout")
	if type(layout) == "table" then
		if rawget(layout, "Secondary") == true then
			return "Secondary"
		end
		local invGroup = rawget(layout, "InventoryGroup")
		if invGroup == 2 then return "Secondary" end
		if invGroup == 1 then return "Primary" end
		if invGroup == 3 then return "Melee" end
		local lbl = Bridge.slotTypeToLabel(rawget(layout, "SlotType"), mods)
		if lbl then return lbl end
	end
	local name = rawget(item, "Name") or ""
	if string.find(name, "Primary", 1, true) then return "Primary" end
	if string.find(name, "Secondary", 1, true) then return "Secondary" end
	if string.find(name, "Melee", 1, true) then return "Melee" end
	return nil
end

function Bridge.getMagAmmo(meta)
	if type(meta) ~= "table" then return nil, 0 end
	local chamber = rawget(meta, "Chamber") == true and 1 or 0
	local inMag = rawget(meta, "Capacity")
	local mag = rawget(meta, "Mag")
	if inMag == nil and type(mag) == "table" then
		inMag = rawget(mag, "Capacity")
	end
	return inMag, chamber
end

function Bridge.itemUid(item)
	if type(item) ~= "table" then return nil end
	local meta = rawget(item, "MetaData")
	local uid = type(meta) == "table" and rawget(meta, "UID") or nil
	return Bridge.normalizeEquipUid(uid)
end

function Bridge.normalizeEquipUid(uid)
	if uid == nil then return nil end
	if type(uid) == "number" then return tostring(uid) end
	if type(uid) == "string" and uid ~= "" then return uid end
	return nil
end

function Bridge.normalizeActorUid(uid)
	if uid == nil then return nil end
	if type(uid) == "number" then return uid end
	if type(uid) == "string" and uid ~= "" then
		local n = tonumber(uid)
		return n or uid
	end
	return uid
end

local CLIENT_INV_KEYS = {
	"_inventory", "Inventory", "inventory", "Gear", "Loadout", "Equipment",
	"Handler", "Handlers", "State", "Data", "Actor", "Character",
	"Controller", "PlayerState", "LocalState",
}

function Bridge.hasPlayerFirearmInMain(inv, mods)
	local storages = tableField(inv, "Storages")
	if type(storages) ~= "table" then return false end
	for _, storage in pairs(storages) do
		if type(storage) ~= "table" or storage.StorageName ~= "Main" then continue end
		local section = storage.Sections and storage.Sections[1]
		if type(section) ~= "table" then continue end
		for _, cell in pairs(section) do
			if Bridge.isPlayerFirearmItem(cell, mods) then
				return true
			end
		end
	end
	return false
end

function Bridge.inventoryOwnerScore(t, mods)
	if not Bridge.isInventoryTable(t) or not Bridge.inventoryHasMainStorage(t) then
		return 0
	end
	local score = 10
	if type(tableField(t, "Change")) == "function" then score += 20 end
	if type(tableField(t, "ChangeWearable")) == "function" then score += 10 end
	local player = tableField(t, "Player")
	if player == LP then
		score += 40
	elseif player ~= nil then
		return 0
	end
	if Bridge.hasPlayerFirearmInMain(t, mods) then
		score += 30
	end
	return score
end

function Bridge.walkForInventory(root, depth, seen)
	if depth > 3 or type(root) ~= "table" then return nil end
	if seen[root] then return nil end
	seen[root] = true
	if Bridge.inventoryHasMainStorage(root) then return root end
	for _, v in pairs(root) do
		if type(v) == "table" then
			local found = Bridge.walkForInventory(v, depth + 1, seen)
			if found then return found end
		end
	end
	return nil
end

function Bridge.findInventoryFromClient(client, mods)
	if type(client) ~= "table" then return nil end
	if Bridge.inventoryHasMainStorage(client) then return client end
	for _, key in ipairs(CLIENT_INV_KEYS) do
		local v = tableField(client, key)
		if Bridge.inventoryHasMainStorage(v) then return v end
	end
	for _, key in ipairs(CLIENT_INV_KEYS) do
		local v = tableField(client, key)
		if type(v) == "table" then
			local found = Bridge.walkForInventory(v, 0, {})
			if found then return found end
		end
	end
	return Bridge.walkForInventory(client, 0, {})
end

function Bridge.mapHandlerKeyToSlot(key)
	if not key then return nil end
	local k = string.lower(tostring(key))
	if string.find(k, "primary", 1, true) then return "Primary" end
	if string.find(k, "secondary", 1, true) then return "Secondary" end
	if string.find(k, "melee", 1, true) then return "Melee" end
	return nil
end

function Bridge.normalizeEquippedSlotKey(eq)
	if type(eq) ~= "string" or eq == "" then return nil end
	local slot = Bridge.mapHandlerKeyToSlot(eq)
	if slot then return slot end
	for _, label in ipairs(SLOT_LABELS) do
		if string.lower(label) == string.lower(eq) then
			return label
		end
	end
	return nil
end

function Bridge.handFromEquippedString(eq, slots, mods)
	if type(eq) ~= "string" or eq == "" then return nil, nil end

	local slot = Bridge.normalizeEquippedSlotKey(eq)
	if slot and slots[slot] and Bridge.isPlayerFirearmItem(slots[slot], mods) then
		return slots[slot], slot
	end

	local n = tonumber(eq)
	if n and SLOT_LABELS[n] and slots[SLOT_LABELS[n]] then
		return slots[SLOT_LABELS[n]], SLOT_LABELS[n]
	end

	local lower = string.lower(eq)
	for label, item in pairs(slots) do
		if not Bridge.isPlayerFirearmItem(item, mods) then continue end
		local name = string.lower(Bridge.firearmDisplayName(item))
		local itemName = string.lower(rawget(item, "Name") or "")
		if name == lower or itemName == lower
			or string.find(name, lower, 1, true)
			or string.find(itemName, lower, 1, true) then
			return item, label
		end
		local uid = Bridge.itemUid(item)
		if uid and (uid == eq or string.find(uid, eq, 1, true)) then
			return item, label
		end
	end

	return nil, nil
end

function Bridge.handFromEquippedSlotField(tbl, slots, mods)
	if type(tbl) ~= "table" then return nil, nil end
	for _, key in ipairs({ "EquippedSlot", "ActiveSlot", "SelectedSlot", "Slot", "Hand", "Active", "Equipped" }) do
		local v = tableField(tbl, key)
		if type(v) == "number" and SLOT_LABELS[v] and slots[SLOT_LABELS[v]] then
			return slots[SLOT_LABELS[v]], SLOT_LABELS[v]
		end
		if type(v) == "string" and v ~= "" then
			local item, slot = Bridge.handFromEquippedString(v, slots, mods)
			if item then return item, slot end
		end
	end
	return nil, nil
end

function Bridge.resolveActiveLoadoutTable(client)
	local loadouts = tableField(client, "Loadouts")
	local idx = tableField(client, "ActiveLoadout")
	if type(loadouts) ~= "table" then return nil end
	if type(idx) == "number" then
		return tableField(loadouts, idx)
			or tableField(loadouts, idx + 1)
			or tableField(loadouts, tostring(idx))
	end
	return nil
end

function Bridge.handFromLoadoutClient(client, slots, mods)
	if type(client) ~= "table" then return nil, nil end

	local hand, slot = Bridge.handFromEquippedSlotField(client, slots, mods)
	if hand then return hand, slot end

	local loadout = Bridge.resolveActiveLoadoutTable(client)
	if type(loadout) == "table" then
		hand, slot = Bridge.handFromEquippedSlotField(loadout, slots, mods)
		if hand then return hand, slot end

		for _, slotName in ipairs(SLOT_LABELS) do
			local entry = tableField(loadout, slotName)
			if type(entry) == "table" then
				if tableField(entry, "Equipped") == true or tableField(entry, "Active") == true then
					local item = tableField(entry, "Item") or tableField(entry, "Cell") or entry
					if Bridge.isPlayerFirearmItem(item, mods) then
						return item, slotName
					end
				end
			elseif Bridge.isPlayerFirearmItem(entry, mods) then
				return entry, slotName
			end
		end
	end

	return nil, nil
end

function Bridge.slotFromUid(item, slots)
	local uid = Bridge.itemUid(item)
	if not uid then return nil end
	for slot, slotItem in pairs(slots) do
		if Bridge.itemUid(slotItem) == uid then
			return slot
		end
	end
	return nil
end


function Bridge.actorCurrentInventory(actor)
	if type(actor) ~= "table" then return nil end
	local state = tableField(actor, "CurrentState")
	if type(state) ~= "table" then return nil end
	local inv = tableField(state, "Inventory")
	return type(inv) == "table" and inv or nil
end

function Bridge.itemFromActorInventory(actor, uid)
	uid = Bridge.normalizeEquipUid(uid)
	if not uid then return nil end
	local inv = Bridge.actorCurrentInventory(actor)
	if inv then
		local item = inv[uid] or inv[tonumber(uid)]
		if type(item) == "table" then return item end
	end
	return nil
end

function Bridge.readSlotsFromActorState(actor, mods)
	local out = {}
	local inv = Bridge.actorCurrentInventory(actor)
	if not inv then return out end
	for _, item in pairs(inv) do
		if Bridge.isPlayerFirearmItem(item, mods) then
			local lbl = Bridge.slotLabelFromItem(item, mods)
			if lbl then
				out[lbl] = item
			end
		end
	end
	return out
end

function Bridge.findBulletsLoadedOnActor(actor, eqUid)
	local handler = Bridge.findFirearmHandler(actor, eqUid)
	local cur = Bridge.readBulletsLoaded(handler)
	if type(cur) == "number" then return cur end
	if type(actor) ~= "table" then return nil end
	for _, v in pairs(actor) do
		if type(v) ~= "table" or not rawget(v, "_item") then continue end
		local item = rawget(v, "_item")
		local meta = type(item) == "table" and rawget(item, "MetaData")
		if type(meta) == "table" and rawget(meta, "UID") == eqUid then
			cur = Bridge.readBulletsLoaded(v)
			if type(cur) == "number" then return cur end
		end
	end
	return nil
end

function Bridge.findFirearmModelOnCharacter(model)
	if not model then return nil end
	local cached = State._firearmModelCache
	if cached and cached.model == model and cached.firearm and cached.firearm.Parent then
		return cached.firearm
	end
	local function tryModel(m)
		if m and m:IsA("Model") and type(m.Name) == "string" then
			if string.match(m.Name, "^Firearm") then return m end
			if m:FindFirstChild("muzzle", true) and m:FindFirstChild("bullets", true) then return m end
		end
	end
	for _, child in ipairs(model:GetChildren()) do
		local r = tryModel(child)
		if r then State._firearmModelCache = {model=model,firearm=r}; return r end
	end
	for _, holder in ipairs({"WorldModel","HeroModel","LODModel"}) do
		local h = model:FindFirstChild(holder)
		if h then
			for _, child in ipairs(h:GetChildren()) do
				local r = tryModel(child)
				if r then State._firearmModelCache = {model=model,firearm=r}; return r end
			end
		end
	end
	State._firearmModelCache = {model=model, firearm=nil}
	return nil
end

function Bridge.findMeleeModelOnCharacter(model)
	if not model then return nil end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and type(child.Name) == "string" then
			if string.match(child.Name, "^Melee") then return child end
		end
	end
	return nil
end

function Bridge.findHandWeldedWeaponModel(model)
	if not model or not model:IsA("Model") then return nil end
	local now = os.clock()
	if State._handWeldCache and State._handWeldCache.model == model
		and now - (State._handWeldCache.t or 0) < 0.2 then
		local w = State._handWeldCache.weapon
		return (w and w.Parent) and w or nil
	end
	local rh = model:FindFirstChild("RightHand")
	local found = nil
	if rh and rh:IsA("BasePart") then
		for _, child in ipairs(model:GetChildren()) do
			if not child:IsA("Model") then continue end
			for _, desc in ipairs(child:GetDescendants()) do
				if desc:IsA("Motor6D") and desc.Part0 == rh then
					found = child
					break
				end
			end
			if found then break end
		end
	end
	State._handWeldCache = { model = model, weapon = found, t = now }
	return found
end

function Bridge.findWeaponModelOnCharacter(model)
	return Bridge.findFirearmModelOnCharacter(model)
		or Bridge.findMeleeModelOnCharacter(model)
		or Bridge.findHandWeldedWeaponModel(model)
end

function Bridge.itemBuildKey(item)
	if type(item) ~= "table" then return nil end
	local layout = rawget(item, "Layout")
	local build = layout and rawget(layout, "Build")
	if type(build) == "string" and build ~= "" then return string.lower(build) end
	local name = rawget(item, "Name")
	if type(name) ~= "string" then return nil end
	name = Bridge.firearmDisplayName(item)
	return name ~= "" and string.lower(name) or nil
end

function Bridge.matchSlotItemToWeaponModel(slots, mods, weaponModel)
	if not weaponModel or not slots then return nil, nil end
	local mname = string.lower(weaponModel.Name or "")
	mname = string.gsub(mname, "^firearmprimary", "")
	mname = string.gsub(mname, "^firearmsecondary", "")
	mname = string.gsub(mname, "^melee", "")
	for label, item in pairs(slots) do
		if not Bridge.isPlayerFirearmItem(item, mods) then continue end
		local key = Bridge.itemBuildKey(item)
		local iname = string.lower(tostring(rawget(item, "Name") or ""))
		local disp = string.lower(Bridge.firearmDisplayName(item))
		if key and (key == mname or string.find(mname, key, 1, true) or string.find(key, mname, 1, true)) then
			return item, label
		end
		if disp ~= "" and (disp == mname or string.find(mname, disp, 1, true) or string.find(disp, mname, 1, true)) then
			return item, label
		end
		if iname ~= "" and (string.find(iname, mname, 1, true) or string.find(mname, iname, 1, true)) then
			return item, label
		end
	end
	return nil, nil
end

function Bridge.findEquippedHandlerForItem(actor, item)
	if type(actor) ~= "table" or type(item) ~= "table" then return nil end
	local uid = Bridge.itemUid(item)
	if uid then
		local h = Bridge.findFirearmHandler(actor, uid) or Bridge.getWeaponHandler(actor, uid)
		if h then return h end
	end
	local inv = tableField(actor, "_inventory")
	if type(inv) ~= "table" then return nil end
	for _, h in pairs(inv) do
		if type(h) ~= "table" then continue end
		local hi = rawget(h, "_item") or rawget(h, "Item")
		if hi == item then return h end
		if uid and Bridge.itemUid(hi) == uid then return h end
	end
	return nil
end

function Bridge.weaponContextValid(ctx)
	if not ctx or ctx == WEAPON_CTX_EMPTY or type(ctx) ~= "table" then return false end
	if not ctx.item or not ctx.info then return false end
	if ctx.isMelee == true or ctx.info.caliber == "melee" then return true end
	return ctx.handler ~= nil and ctx.tune ~= nil
end

function Bridge.countVisibleBulletsOnWeaponModel(firearmModel)
	if not firearmModel then return nil, nil end
	local now = os.clock()
	if not State._bulletModelCache then State._bulletModelCache = {} end
	local cached = State._bulletModelCache[firearmModel]
	if cached and now - cached.t < 0.5 then return cached.vis, cached.tot end
	local visible, total = 0, 0
	local roots = {firearmModel}
	local bulletsFolder = firearmModel:FindFirstChild("bullets", true)
	if bulletsFolder then roots[#roots+1] = bulletsFolder end
	for _, root in ipairs(roots) do
		for _, desc in ipairs(root:GetDescendants()) do
			if not desc:IsA("BasePart") then continue end
			local num = tonumber(string.match(string.lower(desc.Name), "^bullet(%d+)"))
			if num then
				total = math.max(total, num)
				if desc.Transparency < 0.92 and desc.LocalTransparencyModifier < 0.92 then
					visible += 1
				end
			end
		end
	end
	if total > 0 then
		State._bulletModelCache[firearmModel] = {t=now, vis=visible, tot=total}
		return visible, total
	end
	return nil, nil
end

function Bridge.findFirearmHandler(actor, eqUid)
	if type(actor) ~= "table" then return nil end
	eqUid = Bridge.normalizeEquipUid(eqUid)
	if not eqUid then return nil end
	local inv = rawget(actor, "_inventory")
	if type(inv) == "table" then
		local direct = inv[eqUid] or inv[tonumber(eqUid)]
		if type(direct) == "table" and rawget(direct, "_item") then
			return direct
		end
		for _, h in pairs(inv) do
			if type(h) ~= "table" then continue end
			local item = rawget(h, "_item")
			local meta = type(item) == "table" and rawget(item, "MetaData")
			local huid = type(meta) == "table" and Bridge.normalizeEquipUid(rawget(meta, "UID"))
			if huid and huid == eqUid then
				return h
			end
		end
	end
	return Bridge.getWeaponHandler(actor, eqUid)
end

function Bridge.readEquippedItem(actor, eqUid)
	if type(actor) ~= "table" or type(eqUid) ~= "string" then return nil end
	local state = tableField(actor, "CurrentState")
	local inv = state and tableField(state, "Inventory")
	if type(inv) == "table" and type(inv[eqUid]) == "table" then
		return inv[eqUid]
	end
	return Bridge.itemFromActorInventory(actor, eqUid)
end

function Bridge.resolveMagMax(handler, item, mods)
	if type(handler) == "table" then
		local mag = rawget(handler, "_mag")
		if type(mag) == "table" then
			local maxC = rawget(mag, "Max") or rawget(mag, "MaxCapacity") or rawget(mag, "Capacity")
			if type(maxC) == "number" and maxC > 0 then return maxC end
		end
	end
	local tune = handler and Bridge.tuneFromHandler(handler)
	if type(tune) == "table" and type(tune.Ammo) == "number" then
		return tune.Ammo
	end
	local meta = item and rawget(item, "MetaData")
	if type(meta) == "table" then
		local magMeta = rawget(meta, "Mag")
		if type(magMeta) == "table" and type(rawget(magMeta, "Capacity")) == "number" then
			return magMeta.Capacity
		end
		local _, magMax = Bridge.parseFirearmTuneCached(meta, mods)
		if type(magMax) == "number" then return magMax end
	end
	return nil
end

function Bridge.readBulletsLoaded(handler)
	if type(handler) ~= "table" then return nil end
	local loaded = rawget(handler, "_bulletsLoaded")
	if type(loaded) == "number" then return loaded end
	local mag = rawget(handler, "_mag")
	if type(mag) == "table" and type(mag.Capacity) == "number" then
		return mag.Capacity
	end
	return nil
end

function Bridge.shouldEspWeaponInfo(data)
	if not CONFIG.EspWeaponInfo then return false end
	if data and Bridge.isNpcActorClass(data.class) then return false end
	if CONFIG.EspWeaponPlayersOnly ~= false then
		return data and data.class == "player"
	end
	return true
end

function Bridge.getWeaponHandler(actor, uid)
	if type(actor) ~= "table" then return nil end
	uid = Bridge.normalizeEquipUid(uid)
	if not uid then return nil end
	local inv = tableField(actor, "_inventory")
	if type(inv) ~= "table" then return nil end
	local handler = inv[uid] or inv[tonumber(uid)]
	return type(handler) == "table" and handler or nil
end

function Bridge.tuneFromHandler(handler)
	if type(handler) ~= "table" then return nil end
	local firearm = tableField(handler, "_firearm")
	if type(firearm) == "table" then
		local tune = tableField(firearm, "Tune")
		if type(tune) == "table" then return tune end
	end
	local fp = tableField(handler, "_fpFirearm")
	if type(fp) == "table" then
		local tune = tableField(fp, "Tune")
		if type(tune) == "table" then return tune end
	end
	return tableField(handler, "Tune")
end

function Bridge.caliberFromHandler(handler)
	if type(handler) ~= "table" then return nil end
	local direct = tableField(handler, "_caliber")
	if type(direct) == "table" then return direct end
	local firearm = tableField(handler, "_firearm")
	if type(firearm) == "table" then
		local cal = tableField(firearm, "_caliber")
		if type(cal) == "table" then return cal end
	end
	local fp = tableField(handler, "_fpFirearm")
	if type(fp) == "table" then
		local cal = tableField(fp, "_caliber")
		if type(cal) == "table" then return cal end
	end
	return nil
end

-- Discharge умножает Tune.Barrel_Spread и _caliber.Spread до формирования v138.
function Bridge.zeroClientWeaponSpread(ctx)
	if CONFIG.ForceZeroSpread == false and not Bridge.needsServerAimPatch() then
		if not CONFIG.ModifyEnabled or not CONFIG.ModifyPresets or not CONFIG.ModifyPresets.NoSpread then
			return
		end
	end
	ctx = ctx or Bridge.peekWeaponContext() or Bridge.getLiveWeaponContext(false)
	if not ctx then return end

	local function zeroSpreadTable(tune)
		if type(tune) ~= "table" then return end
		if type(tune.Barrel_Spread) == "number" then
			tune.Barrel_Spread = 0
		end
		for k, v in pairs(tune) do
			if type(k) == "string" and k:find("Spread", 1, true) and type(v) == "number" then
				tune[k] = 0
			end
		end
	end

	zeroSpreadTable(ctx.tune)
	if type(ctx.cal) == "table" and type(ctx.cal.Spread) == "number" then
		ctx.cal.Spread = 0
	end

	local handler = ctx.handler
	if type(handler) == "table" then
		zeroSpreadTable(Bridge.tuneFromHandler(handler))
		local liveCal = Bridge.caliberFromHandler(handler)
		if type(liveCal) == "table" and type(liveCal.Spread) == "number" then
			liveCal.Spread = 0
		end
	end
end

function Bridge.mergeTuneTables(base, live)
	if not live then return base end
	if not base then
		local out = {}
		for k, v in pairs(live) do out[k] = v end
		return out
	end
	local out = {}
	for k, v in pairs(base) do out[k] = v end
	for k, v in pairs(live) do out[k] = v end
	return out
end

function Bridge.resolveActorForClient(client)
	local actor = Bridge.getActorTable(client)
	if not actor and type(client) == "table"
		and (rawget(client, "_equipped") ~= nil or rawget(client, "IsLocalPlayer") == true) then
		actor = client
	end
	if not actor and Bridge.resolveLocalActor then
		local _, la = Bridge.resolveLocalActor(false)
		if type(la) == "table" then
			actor = la
		end
	end
	return actor
end

function Bridge.resolveMeleeItemFromHandler(actor, handler, eqUid, slots, stateItem)
	if type(handler) ~= "table" then return nil end
	local item = tableField(handler, "_item") or tableField(handler, "Item")
	if item then return item end
	if not Bridge.isMeleeHandler(handler) then return nil end
	item = stateItem or (eqUid and Bridge.itemFromActorInventory(actor, eqUid))
	if item then return item end
	local build = rawget(handler, "_build")
	if type(build) ~= "string" or type(slots) ~= "table" then return nil end
	for _, slotItem in pairs(slots) do
		local layout = type(slotItem) == "table" and rawget(slotItem, "Layout")
		if layout and rawget(layout, "Build") == build then
			return slotItem
		end
	end
	return nil
end

function Bridge.handFromActorEquippedUid(client, slots, mods)
	local actor = Bridge.resolveActorForClient(client)
	if not actor then return nil, nil end

	local eqUid = Bridge.normalizeEquipUid(tableField(actor, "_equipped"))
	if not eqUid then
		local state = tableField(actor, "CurrentState")
		if type(state) == "table" then
			eqUid = Bridge.normalizeEquipUid(tableField(state, "Equip"))
		end
	end
	if not eqUid then return nil, nil end

	local stateItem = Bridge.itemFromActorInventory(actor, eqUid)
	if stateItem and Bridge.isPlayerFirearmItem(stateItem, mods) then
		return stateItem, Bridge.slotFromUid(stateItem, slots) or Bridge.slotLabelFromItem(stateItem, mods)
	end

	for label, item in pairs(slots) do
		if Bridge.itemUid(item) == eqUid then
			return item, label
		end
	end

	local invHandlers = tableField(actor, "_inventory")
	if type(invHandlers) == "table" then
		local handler = invHandlers[eqUid] or invHandlers[tonumber(eqUid)]
		if type(handler) == "table" then
			local item = Bridge.resolveMeleeItemFromHandler(actor, handler, eqUid, slots, stateItem)
				or tableField(handler, "_item") or tableField(handler, "Item")
			if Bridge.isPlayerFirearmItem(item, mods) then
				return item, Bridge.slotFromUid(item, slots) or Bridge.slotLabelFromItem(item, mods)
			end
		end
	end

	return Bridge.handFromEquippedString(eqUid, slots, mods)
end

function Bridge.handFromEquippedHandlers(client, slots, mods)
	local actor = Bridge.resolveActorForClient(client)
	if not actor then return nil, nil end
	local inv = tableField(actor, "_inventory")
	if type(inv) ~= "table" then return nil, nil end

	local eqUid = Bridge.normalizeEquipUid(tableField(actor, "_equipped"))
	if eqUid then
		local handler = inv[eqUid] or inv[tonumber(eqUid)]
		if type(handler) == "table" then
			local item = Bridge.resolveMeleeItemFromHandler(actor, handler, eqUid, slots, nil)
				or tableField(handler, "_item") or tableField(handler, "Item")
			if Bridge.isPlayerFirearmItem(item, mods) then
				return item, Bridge.slotFromUid(item, slots) or Bridge.slotLabelFromItem(item, mods)
			end
		end
	end

	for _, handler in pairs(inv) do
		if type(handler) ~= "table" or rawget(handler, "_equipped") ~= true then
			continue
		end
		local item = tableField(handler, "_item") or tableField(handler, "Item")
		if Bridge.isPlayerFirearmItem(item, mods) then
			return item, Bridge.slotFromUid(item, slots) or Bridge.slotLabelFromItem(item, mods)
		end
	end
	return nil, nil
end

function Bridge.handFromCharacterWeaponModel(slots, mods)
	if not Bridge.isLocalPlayerAlive() then return nil, nil end
	local model = State.localModel
	if (not model or not model.Parent) and LP and LP.Character then
		model = LP.Character
	end
	if not model or not model.Parent then return nil, nil end

	local wm = Bridge.findWeaponModelOnCharacter(model)
	if not wm then return nil, nil end
	local item, slot = Bridge.matchSlotItemToWeaponModel(slots, mods, wm)
	if item then return item, slot end
	if Bridge.resolveLocalActor then
		local _, actor = Bridge.resolveLocalActor(false)
		if type(actor) == "table" then
			local eqUid = Bridge.normalizeEquipUid(rawget(actor, "_equipped"))
			local stateItem = eqUid and Bridge.itemFromActorInventory(actor, eqUid)
			if stateItem and Bridge.isPlayerFirearmItem(stateItem, mods) then
				return stateItem, Bridge.slotLabelFromItem(stateItem, mods) or "Melee"
			end
		end
	end
	return nil, nil
end

function Bridge.handFromCharacterFirearmModel(slots, mods)
	return Bridge.handFromCharacterWeaponModel(slots, mods)
end

function Bridge.handFromChangeHook(slots, mods)
	if not Bridge.isLocalPlayerAlive() then
		return nil, nil
	end
	if not State.handItem or not Bridge.isPlayerFirearmItem(State.handItem, mods) then
		return nil, nil
	end
	if State.handHookTime <= 0 or os.clock() - State.handHookTime > 120 then
		return nil, nil
	end
	local slot = Bridge.slotFromUid(State.handItem, slots) or State.handSlot or Bridge.slotLabelFromItem(State.handItem, mods)
	return State.handItem, slot
end

local HAND_RESOLVERS = {
	{
		id = "actor.equip",
		try = function(client, slots, mods)
			return Bridge.handFromActorEquippedUid(client, slots, mods)
		end,
	},
	{
		id = "actor.handler",
		try = function(client, slots, mods)
			return Bridge.handFromEquippedHandlers(client, slots, mods)
		end,
	},
	{
		id = "visual.model",
		try = function(client, slots, mods)
			return Bridge.handFromCharacterWeaponModel(slots, mods)
		end,
	},
	{
		id = "loadout",
		try = function(client, slots, mods)
			return Bridge.handFromLoadoutClient(client, slots, mods)
		end,
	},
	{
		id = "equip.hook",
		try = function(client, slots, mods)
			return Bridge.handFromChangeHook(slots, mods)
		end,
	},
}


function Bridge.scanInventoryFromGc(mods)
	if type(getgc) ~= "function" then return nil, 0 end
	local now = os.clock()
	-- v18: cooldown жёсткий — getgc(true) очень дорого
	local cooldown = CONFIG.InventoryGcCooldown or 20
	if now - (State.lastInventoryGc or 0) < cooldown then
		-- возвращаем кэш если есть
		if State.lastInventoryGcResult then
			return State.lastInventoryGcResult, State.lastInventoryGcScore or 0
		end
		return nil, 0
	end
	State.lastInventoryGc = now
	Bridge.perfCount("inventoryGcScan")

	local best, bestScore = nil, 0
	for _, v in ipairs(getGcCached()) do
		if type(v) ~= "table" then continue end
		local score = Bridge.inventoryOwnerScore(v, mods)
		if score > bestScore then
			best = v
			bestScore = score
		end
	end
	-- v18: кэшируем результат
	if best and bestScore >= 20 then
		State.lastInventoryGcResult = best
		State.lastInventoryGcScore = bestScore
		return best, bestScore
	end
	return nil, bestScore
end

function Bridge.trackHandFromChange(item, equipped, mods)
	if type(item) ~= "table" or type(equipped) ~= "boolean" then return end
	-- FIX: при unequip — сбрасываем handItem независимо от типа предмета
	if not equipped then
		if State.handItem == item or State.handItem ~= nil then
			State.handItem = nil
			State.handSlot = nil
			State.handHookTime = 0
			State.cachedHudHandUid = nil
			State.modifyAppliedUid = nil
			Bridge.invalidateWeaponCache()
		end
		return
	end
	if not Bridge.isPlayerFirearmItem(item, mods) then return end
	if equipped then
		State.handItem = item
		State.noWeaponRediscoverMisses = 0
		State.handSlot = Bridge.slotLabelFromItem(item, mods)
		State.handHookTime = os.clock()
		State.cachedHudHandUid = nil
		State.modifyAppliedUid = nil
		Bridge.invalidateWeaponCache()
		markResolver("hand", "equip.hook")
	elseif State.handItem == item then
		State.handItem = nil
		State.handSlot = nil
		State.handHookTime = 0
		State.cachedHudHandUid = nil
		State.modifyAppliedUid = nil
	end
	task.defer(function()
		if State.running then
			-- v20 PATCH: force=true если methods.hand не залочен (после ресета)
			-- гарантирует что discover выполнится даже если был предыдущий refresh
			local needForce = equipped and (State.methods.hand == nil or State.methods.hand == "")
			Bridge.requestHudRefresh(needForce)
		end
	end)
end

function Bridge.hookOwnerChange(owner, mods)
	if changeOriginals[owner] then return end
	local changeFn = tableField(owner, "Change")
	if type(changeFn) ~= "function" then return end

	changeOriginals[owner] = changeFn
	rawset(owner, "Change", function(self, item, equipped, ...)
		local orig = changeOriginals[owner]
		local ret = table.pack(orig(self, item, equipped, ...))
		-- v19 PATCH: debounce — при rebuild инвентаря Change зовётся N раз подряд
		-- каждый task.defer → N тяжёлых coroutines = FPS дроп.
		-- Запускаем только ОДИН defer, остальные пропускаем.
		if not State.trackHandPending then
			State.trackHandPending = true
			local _item, _eq = item, equipped
			task.defer(function()
				State.trackHandPending = false
				if State.running then
					Bridge.trackHandFromChange(_item, _eq, mods)
				end
			end)
		end
		return table.unpack(ret, 1, ret.n)
	end)
	State.changeHookOwner = owner
end

function Bridge.bindPlayerInventory(owner, source, mods)
	if not Bridge.inventoryHasMainStorage(owner) then return end
	State.playerInventory = owner
	Bridge.hookOwnerChange(owner, mods)
	if source then
		markResolver("inventory", source)
	end
	if source and not State.invCaptureLogged then
		State.invCaptureLogged = true
		log("WEAPON", "inventory owner:", source)
	end
end

function Bridge.hookSharedInventoryTable(si, mods)
	if type(si) ~= "table" then return end
	if rawget(si, "__brm5Hooked") then
		-- v19 PATCH: флаг уже стоит, но если State требует переустановки — снимаем
		if not State.sharedInventorySiRef then
			State.sharedInventorySiRef = si
		end
		return
	end
	State.sharedInventorySiRef = si  -- v19 PATCH: сохраняем ref для сброса при ресете
	rawset(si, "__brm5Hooked", true)

	local function wrap(name, handler)
		local orig = si[name]
		if type(orig) ~= "function" then return end
		si[name] = function(...)
			handler(...)
			return orig(...)
		end
	end

	wrap("SetFunctional", function(owner)
		Bridge.bindPlayerInventory(owner, "SetFunctional", mods)
	end)
		wrap("PerformEquipCalls", function(itemA, itemB, owner)
		Bridge.bindPlayerInventory(owner, "PerformEquipCalls", mods)
		if type(itemA) == "table" and Bridge.isPlayerFirearmItem(itemA, mods) then
			State.handItem = itemA
			State.noWeaponRediscoverMisses = 0
			State.handSlot = Bridge.slotLabelFromItem(itemA, mods)
			State.handHookTime = os.clock()
			State.cachedHudHandUid = nil
			State.modifyAppliedUid = nil
			Bridge.invalidateWeaponCache()
			markResolver("hand", "equip.hook")
			task.spawn(function()
				task.wait(0.2)
				if not State.running then return end
				if CONFIG.ModifyEnabled then
					-- первая попытка
					pcall(Bridge.applyWeaponModify, true)
					-- повторная через 0.5 с — на случай если tune ещё не прикреплён
					task.wait(0.5)
					if State.running and CONFIG.ModifyEnabled then
						State.modifyAppliedUid = nil
						pcall(Bridge.applyWeaponModify, true)
					end
				end
				Bridge.requestHudRefresh(true)
			end)
		elseif type(itemB) == "table" and Bridge.isPlayerFirearmItem(itemB, mods) and not itemA then
			if State.handItem == itemB or Bridge.itemUid(State.handItem) == Bridge.itemUid(itemB) then
				State.handItem = nil
				State.handSlot = nil
				State.handHookTime = 0
				State.cachedHudHandUid = nil
				State.modifyAppliedUid = nil
				task.defer(function()
					if State.running then
						Bridge.requestHudRefresh(false)
					end
				end)
			end
		end
	end)
	wrap("AddStorage", function(inv)
		Bridge.bindPlayerInventory(inv, "AddStorage", mods)
	end)
	wrap("GetAllFunctional", function(owner)
		Bridge.bindPlayerInventory(owner, "GetAllFunctional", mods)
	end)
	wrap("MoveItem", function(owner)
		Bridge.bindPlayerInventory(owner, "MoveItem", mods)
	end)
end

function Bridge.installInventoryHooks(mods)
	if State.invCaptureInstalled then return end
	local si = mods and mods.SharedInventory
	Bridge.hookSharedInventoryTable(si, mods)

	if type(shared) == "table" and type(shared.import) == "function" then
		local ok, direct = pcall(shared.import, "SharedInventory")
		if ok and direct ~= si then
			Bridge.hookSharedInventoryTable(direct, mods)
		end
	end

	local sharedRoot = RS:FindFirstChild("Shared")
	if sharedRoot then
		local inst = sharedRoot:FindFirstChild("SharedInventory", true)
		if inst and inst:IsA("ModuleScript") then
			local ok, alt = pcall(require, inst)
			if ok and alt ~= si then
				Bridge.hookSharedInventoryTable(alt, mods)
			end
		end
	end

	State.invCaptureInstalled = true
	log("WEAPON", "SharedInventory hooks active", si and "ok" or "module nil")
end

function Bridge.resolvePlayerInventory(force)
	if force then
		State.playerInventory = nil
		State.changeHookOwner = nil
		State.lastInventoryGc = 0
	end
	if State.playerInventory then
		return State.playerInventory
	end

	loadClientsModule()
	local mods = Bridge.loadSharedModules()
	Bridge.installInventoryHooks(mods)
	if State.playerInventory then
		return State.playerInventory
	end

	getLocalClientObject()
	if not State.localClient and force then
		resolveLocalClient(true)
	end
	local client = State.localClient

	if client then
		local inv = tableField(client, "_inventory")
		if Bridge.inventoryHasMainStorage(inv) then
			Bridge.bindPlayerInventory(inv, "client._inventory", mods)
			return State.playerInventory
		end
		inv = Bridge.findInventoryFromClient(client, mods)
		if inv then
			Bridge.bindPlayerInventory(inv, "client.walk", mods)
			return State.playerInventory
		end
	end

	if force and not State.methods.inventory then
		local gcOwner, gcScore = Bridge.scanInventoryFromGc(mods)
		if gcOwner then
			Bridge.bindPlayerInventory(gcOwner, "getgc score=" .. tostring(gcScore), mods)
			return State.playerInventory
		end

		if not State.invDebugLogged then
			State.invDebugLogged = true
			local keys = {}
			if client then
				for k in pairs(client) do
					table.insert(keys, tostring(k))
				end
				table.sort(keys)
			end
			log(
				"WEAPON", "inventory not found",
				"| client", client and "yes" or "no",
				"| gcBest", gcScore,
				"| fields", client and table.concat(keys, ",", 1, 12) or "none"
			)
		end
	end
	return nil
end

function Bridge.findMainStorageId(inv)
	local storages = tableField(inv, "Storages")
	if type(storages) ~= "table" then return nil end
	for id, storage in pairs(storages) do
		if type(storage) == "table" and storage.StorageName == "Main" then
			return id
		end
	end
	return nil
end

function Bridge.decodeBuild(build)
	if type(build) == "table" then return build end
	if type(build) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, build)
		if ok then return data end
	end
	return nil
end

function Bridge.parseFirearmTune(meta, mods)
	if not meta or not meta.Build or not mods.BaseComponent then return nil, nil end
	local build = Bridge.decodeBuild(meta.Build)
	if not build then return nil, nil end
	local ok, comp = pcall(mods.BaseComponent.Deserialize, build, true)
	if not ok or not comp then return nil, nil end
	local magMax = nil
	local magChild = comp.Children and comp.Children.Mag and comp.Children.Mag[1]
	if magChild and magChild.File and magChild.File.Config and magChild.File.Config.Tune then
		magMax = magChild.File.Config.Tune.Ammo
	end
	local tune = comp.Tune
	pcall(function() comp:Destroy() end)
	return tune, magMax
end

function Bridge.parseFirearmTuneCached(meta, mods)
	if not meta or not meta.Build or not mods.BaseComponent then return nil, nil end
	local cacheKey = rawget(meta, "UID") or rawget(meta, "Build")
	if cacheKey then
		local cached = State.tuneCache[cacheKey]
		if cached then
			return cached.tune, cached.magMax
		end
	end
	local tune, magMax = Bridge.parseFirearmTune(meta, mods)
	if cacheKey and tune then
		State.tuneCache[cacheKey] = { tune = tune, magMax = magMax }
	end
	return tune, magMax
end

function Bridge.formatAmmoLine(info)
	local inMag = info.inMag
	local chamber = info.chamber or 0
	if inMag == nil then
		if chamber > 0 then
			return string.format("chamber %d", chamber)
		end
		return "?"
	end
	local max = info.magMax or inMag
	return string.format("%d+%d/%d", inMag, chamber, max)
end

function Bridge.readFunctionalSlotsDirect(owner, mods)
	local mainId = Bridge.findMainStorageId(owner)
	if not mainId then return nil end
	local storages = tableField(owner, "Storages")
	if type(storages) ~= "table" then return nil end
	local storage = storages[mainId]
	if type(storage) ~= "table" then return nil end

	local layouts = mods.StorageLayout
	if type(layouts) ~= "table" then return nil end
	local storageLayout = layouts[storage.StorageName]
	if type(storageLayout) ~= "table" then return nil end

	local sectionLayout = storageLayout.Sections and storageLayout.Sections[1]
	local section = storage.Sections and storage.Sections[1]
	if type(sectionLayout) ~= "table" or type(section) ~= "table" then return nil end

	local base = sectionLayout.Size.X * sectionLayout.Size.Y
	local slots = {}
	for i = 1, math.min(3, #(sectionLayout.FunctionCells or {})) do
		slots[i] = section[base + i]
	end
	return slots
end



function Bridge.getCaliberData(mods, caliberKey)

	if not mods.Calibers or not caliberKey then return nil end
	return mods.Calibers[caliberKey]
end

function Bridge.parseFirearmItem(item, slotLabel, mods, handler)
	if not Bridge.isPlayerFirearmItem(item, mods) then return nil end
	local meta = rawget(item, "MetaData") or {}
	local layout = rawget(item, "Layout")
	local itemName = rawget(item, "Name") or ""
	if layout and rawget(layout, "Handler") == "Melee" then
		return {
			item = item,
			slot = slotLabel,
			name = Bridge.firearmDisplayName(item),
			caliber = "melee",
			inMag = nil,
			chamber = 0,
			mode = "-",
			weight = rawget(meta, "Weight"),
		}
	end
	if layout and rawget(layout, "Handler") ~= "Firearm" and not string.match(itemName, "^Firearm") then
		return nil
	end

	local tune, magMax = nil, nil
	local liveTune = Bridge.tuneFromHandler(handler)
	if not liveTune or not liveTune.RPM then
		tune, magMax = Bridge.parseFirearmTuneCached(meta, mods)
	end
	tune = Bridge.mergeTuneTables(tune, liveTune)

	local magMeta = rawget(meta, "Mag")
	local caliberKey = (type(magMeta) == "table" and rawget(magMeta, "Caliber")) or (tune and tune.Caliber)
	local inMag, chamber = Bridge.getMagAmmo(meta)
	local bulletsLoaded = handler and tableField(handler, "_bulletsLoaded")
	if type(bulletsLoaded) == "number" then
		inMag = bulletsLoaded
	end
	if type(magMeta) == "table" and not magMax then
		magMax = rawget(magMeta, "Capacity")
	end
	local modeIdx = rawget(meta, "Mode") or 1
	local firemodes = tune and tune.Firemodes
	local modeName = firemodes and firemodes[modeIdx] or ("mode" .. tostring(modeIdx))
	local cal = Bridge.getCaliberData(mods, caliberKey)

	return {
		item = item,
		slot = slotLabel,
		name = Bridge.firearmDisplayName(item),
		caliber = caliberKey or "unknown",
		inMag = inMag,
		chamber = chamber,
		magMax = magMax or (tune and tune.Ammo),
		mode = modeName,
		modeIdx = modeIdx,
		modeCount = firemodes and #firemodes or nil,
		firemodes = firemodes,
		magName = type(magMeta) == "table" and rawget(magMeta, "Name") or nil,
		tune = tune,
		cal = cal,
		weight = rawget(meta, "Weight"),
		handler = handler,
	}
end

function Bridge.countReserveAmmo(inv, caliberKey, mods)
	if not inv or not caliberKey then return 0, 0 end
	local storages = tableField(inv, "Storages")
	if type(storages) ~= "table" then return 0, 0 end
	local itemType = mods.Enum and mods.Enum.ItemType
	local rounds, mags = 0, 0
	for _, storage in pairs(storages) do
		for _, section in pairs(storage.Sections) do
			for _, cell in pairs(section) do
				if type(cell) ~= "table" or not cell.MetaData then continue end
				local layout = cell.Layout
				local cellCal = cell.MetaData.Caliber
					or (cell.MetaData.Mag and cell.MetaData.Mag.Caliber)
				if cellCal ~= caliberKey then continue end
				local cap = cell.MetaData.Capacity or 0
				if itemType and layout and layout.ItemType == itemType.Mag then
					mags += 1
					rounds += cap
				elseif itemType and layout and layout.ItemType == itemType.Ammo then
					rounds += cap
				elseif string.match(cell.Name or "", "^FirearmMag") then
					mags += 1
					rounds += cap
				elseif string.match(cell.Name or "", "^AmmoBox") then
					rounds += cap
				end
			end
		end
	end
	return rounds, mags
end

function Bridge.countReserveAmmoCached(inv, caliberKey, mods)
	if not inv or not caliberKey then return 0, 0 end
	local now = os.clock()
	local cached = State.reserveCache[caliberKey]
	if cached and now - cached.t < CONFIG.ReserveCacheSec then
		return cached.rounds, cached.mags
	end
	local rounds, mags = Bridge.countReserveAmmo(inv, caliberKey, mods)
	State.reserveCache[caliberKey] = { rounds = rounds, mags = mags, t = now }
	return rounds, mags
end

function Bridge.appendWeaponStatsCompact(lines, info)
	table.insert(lines, string.format("mag %s", Bridge.formatAmmoLine(info)))
	table.insert(lines, string.format("mode %s", info.mode or "?"))
	if info.tune and info.tune.RPM then
		table.insert(lines, string.format("rpm %d", math.floor(info.tune.RPM + 0.5)))
	end
end

function Bridge.appendWeaponStats(lines, info, owner, mods, full)
	if not full then
		Bridge.appendWeaponStatsCompact(lines, info)
		return
	end
	table.insert(lines, string.format("mag %s", Bridge.formatAmmoLine(info)))
	table.insert(lines, string.format("mode %s", info.mode or "?"))
	if info.firemodes then
		local modes = {}
		for i, m in ipairs(info.firemodes) do
			modes[#modes + 1] = tostring(m)
		end
		table.insert(lines, "firemodes " .. table.concat(modes, ","))
	end
	if info.magName then
		table.insert(lines, string.format("magtype %s", info.magName))
	end
	if info.caliber and info.caliber ~= "unknown" then
		table.insert(lines, string.format("caliber %s", info.caliber))
	end
	if info.weight then
		table.insert(lines, string.format("weight %s", tostring(info.weight)))
	end
	if owner and info.caliber then
		local reserve, magCount = Bridge.countReserveAmmoCached(owner, info.caliber, mods)
		table.insert(lines, string.format("reserve %d rnds %d mags", reserve, magCount))
	end

	local cal = info.cal
	if cal then
		table.insert(lines, "-- cal --")
		local calKeys = {}
		for k in pairs(cal) do calKeys[#calKeys + 1] = k end
		table.sort(calKeys)
		for _, k in ipairs(calKeys) do
			local v = cal[k]
			if k == "Damage" and type(v) == "table" then
				for zone, arr in pairs(v) do
					if type(arr) == "table" and arr[1] then
						table.insert(lines, string.format("dmg.%s %s", zone, tostring(arr[1])))
					end
				end
			elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
				table.insert(lines, string.format("cal.%s %s", k, tostring(v)))
			end
		end
	end

	local tune = info.tune
	if tune then
		table.insert(lines, "-- tune --")
		local tuneKeys = {}
		for k in pairs(tune) do
			if k ~= "Firemodes" then tuneKeys[#tuneKeys + 1] = k end
		end
		table.sort(tuneKeys)
		local maxTune = CONFIG.WeaponHudMaxTuneLines or 22
		local shown = 0
		for _, k in ipairs(tuneKeys) do
			if shown >= maxTune then
				table.insert(lines, string.format("... +%d tune keys", #tuneKeys - shown))
				break
			end
			local v = tune[k]
			local tv = typeof(v)
			if tv == "number" or tv == "boolean" or tv == "string" then
				table.insert(lines, string.format("%s %s", k, tostring(v)))
				shown += 1
			elseif tv == "Vector2" or tv == "Vector3" then
				table.insert(lines, string.format("%s %s", k, tostring(v)))
				shown += 1
			end
		end
	end
end

function Bridge.createHudRow()
	local row = Drawing.new("Text")
	row.Size = 14
	row.Outline = true
	row.Color = Color3.fromRGB(220, 235, 255)
	row.Transparency = 1
	row.ZIndex = 12
	row.Center = false
	row.Visible = false
	if Drawing.Fonts and Drawing.Fonts.Monospace then
		row.Font = Drawing.Fonts.Monospace
	elseif Drawing.Fonts and Drawing.Fonts.UI then
		row.Font = Drawing.Fonts.UI
	end
	return row
end

function Bridge.getHudRow(index)
	local row = State.hudRows[index]
	if row then
		local ok, dead = pcall(function()
			return row.__OBJECT_EXISTS == false
		end)
		if ok and dead then
			row = nil
			State.hudRows[index] = nil
		end
	end
	if not row then
		row = Bridge.createHudRow()
		State.hudRows[index] = row
	end
	return row
end

function Bridge.hideHudRow(index)
	local row = State.hudRows[index]
	if row then
		pcall(function()
			row.Visible = false
		end)
	end
end

Bridge.syncWeaponHud = function(lines)
	if not CONFIG.WeaponHud or not Drawing then return end
	if type(lines) ~= "table" or #lines == 0 then
		lines = { "[Weapon]", "no data" }
	end

	local cam = getCamera()
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local x = 16
	local y0 = vp.Y * State.hudAnchorY
	local step = CONFIG.WeaponHudLineHeight or 16

	for i = 1, #lines do
		local row = Bridge.getHudRow(i)
		local text = tostring(lines[i] or "")
		if #text > 120 then
			text = string.sub(text, 1, 117) .. "..."
		end
		pcall(function()
			row.Text = text
			row.Position = Vector2.new(x, y0 + (i - 1) * step)
			row.Transparency = 1
			row.Visible = true
		end)
	end

	for i = #lines + 1, #State.hudRows do
		Bridge.hideHudRow(i)
	end
end

Bridge.buildWeaponHudLines = function(forceFull)
	local lines = { "[Weapon]" }
	local mods = Bridge.loadSharedModules()

	local okClient, clientErr = pcall(function()
		resolveLocalClient(forceFull == true)
	end)
	local client = State.localClient
	local actor = client and Bridge.getActorTable(client) or nil

	if not okClient then
		table.insert(lines, "client error")
		table.insert(lines, tostring(clientErr):sub(1, 80))
		return lines
	end

	local owner = Bridge.resolvePlayerInventory(forceFull == true)
	if not owner then
		table.insert(lines, "no inventory owner")
	end
	if not client then
		table.insert(lines, "no local client")
		table.insert(lines, "F1 local | F2 weapon | F3 dump | F4 actor")
	end
	if not owner and not actor then
		return lines
	end

	local slots = Bridge.mergeWeaponSlots(owner, mods, client)
	local hand, handSlot = Bridge.resolveEquippedHand(slots, mods, forceFull == true)
	if not hand then
		hand, handSlot = Bridge.resolveEquippedHand(slots, mods, true)
	end

	if hand then
		local handUid = Bridge.itemUid(hand)
		if handUid ~= State.cachedHudHandUid then
			State.cachedHudHandUid = handUid
			table.clear(State.reserveCache)
		end
		local handler = actor and (
			Bridge.findFirearmHandler(actor, handUid)
			or Bridge.getWeaponHandler(actor, handUid)
			or Bridge.findEquippedHandlerForItem(actor, hand)
		)
		local okInfo, info = pcall(Bridge.parseFirearmItem, hand, handSlot or "Hand", mods, handler)
		if okInfo and info then
			table.insert(lines, string.format("HANDS: %s", info.name))
			if handSlot then
				table.insert(lines, string.format("slot %s", handSlot))
			end
			local okStats, statsErr = pcall(Bridge.appendWeaponStats, lines, info, owner, mods, true)
			if not okStats then
				table.insert(lines, "stats error")
				table.insert(lines, tostring(statsErr):sub(1, 80))
			end
		elseif not okInfo then
			table.insert(lines, string.format("HANDS: %s", Bridge.firearmDisplayName(hand)))
			table.insert(lines, "parse error")
			table.insert(lines, tostring(info):sub(1, 80))
		else
			table.insert(lines, string.format("HANDS: %s", Bridge.firearmDisplayName(hand)))
		end
	else
		State.cachedHudHandUid = nil
		local hasWeapons = false
		for _, slot in ipairs(SLOT_LABELS) do
			if slots[slot] then hasWeapons = true break end
		end
		if hasWeapons and Bridge.isLocalPlayerAlive() then
			table.insert(lines, "HANDS: scanning...")
		else
			table.insert(lines, "HANDS: none")
		end
	end

	table.insert(lines, "-- slots --")
	for _, slot in ipairs(SLOT_LABELS) do
		local item = slots[slot]
		local mark = (slot == handSlot) and ">" or " "
		if item then
			table.insert(lines, string.format("%s%s %s", mark, slot, Bridge.firearmDisplayName(item)))
		else
			table.insert(lines, string.format(" %s -", slot))
		end
	end

	if State.methods.hand then
		table.insert(lines, string.format("via %s", State.methods.hand))
	end

	local maxLines = CONFIG.WeaponHudMaxLines
	if type(maxLines) == "number" and maxLines > 0 and #lines > maxLines then
		while #lines > maxLines do
			table.remove(lines, #lines)
		end
	end

	return lines
end



function Bridge.clearWeaponHud()
	for i, row in ipairs(State.hudRows) do
		pcall(function()
			row:Remove()
		end)
		State.hudRows[i] = nil
	end
	table.clear(State.hudRows)
end

function Bridge.startWeaponHudLoop()
	task.spawn(function()
		task.wait(1)
		if not State.running then return end
		Bridge.refreshWeaponCache(true)
		while State.running do
			Bridge.refreshWeaponCache(false)
			task.wait(CONFIG.WeaponHudInterval)
		end
	end)
end

-- ============================================================
-- SILENT AIM — Discharge + Send, визуализация
-- ============================================================

function Bridge.getLocalIgnoreList()
	local now = os.clock()
	if State._ignoreListCache and now - (State._ignoreListCacheT or 0) < 0.5 then
		return State._ignoreListCache
	end
	local list = {}
	if State.localModel then list[#list+1] = State.localModel end
	local cam = getCamera()
	if cam then list[#list+1] = cam end
	State._ignoreListCache = list
	State._ignoreListCacheT = now
	return list
end

function Bridge.getFireOriginCFrame(actor)
	if type(actor) ~= "table" then
		local cam = getCamera()
		return cam and cam.CFrame
	end
	local vm = tableField(actor, "ViewModel")
	if type(vm) == "table" then
		local muzzle = tableField(vm, "Muzzle")
		if rawget(actor, "Focused") == true and typeof(muzzle) == "CFrame" then
			return muzzle
		end
		if typeof(muzzle) == "CFrame" then
			return muzzle
		end
		local worldMuzzle = tableField(vm, "WorldMuzzle")
		if typeof(worldMuzzle) == "Instance" and worldMuzzle:IsA("Attachment") then
			return worldMuzzle.WorldCFrame
		end
	end
	local cam = getCamera()
	return cam and cam.CFrame
end

function Bridge.getReplicateName()
	local cam = getCamera()
	if not cam then return nil end
	for _, ch in ipairs(cam:GetChildren()) do
		if type(ch.Name) == "string" and #ch.Name >= 8 then
			return ch.Name
		end
	end
	return nil
end

function Bridge.isDescendantOfModel(part, model)
	if typeof(part) ~= "Instance" or typeof(model) ~= "Instance" then
		return false
	end
	return part == model or part:IsDescendantOf(model)
end

function Bridge.isValidActorHitPart(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("BasePart") then return false end
	if not inst.Parent then return false end
	local uid = inst:GetAttribute("ActorUID")
	return type(uid) == "string" and uid ~= ""
end

function Bridge.claimHitOnPart(part, model, aimPoint)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return nil, nil
	end
	local hitPart = part
	if not Bridge.isValidActorHitPart(hitPart) and typeof(model) == "Instance" then
		local head = Bridge.getHeadPart(model, part)
		if head and Bridge.isValidActorHitPart(head) then
			hitPart = head
		else
			for _, inst in ipairs(model:GetDescendants()) do
				if inst:IsA("BasePart") and Bridge.isValidActorHitPart(inst) then
					hitPart = inst
					break
				end
			end
		end
	end
	local valid = Bridge.isValidActorHitPart(hitPart)
	if not valid and type(Bridge.isActorHitPart) == "function" then
		valid = Bridge.isActorHitPart(hitPart)
	end
	if not valid then return nil, nil end
	if typeof(model) == "Instance" and not hitPart:IsDescendantOf(model) then
		return nil, nil
	end
	local pos = typeof(aimPoint) == "Vector3" and aimPoint
		or typeof(State.forceHitPoint) == "Vector3" and State.forceHitPoint
		or typeof(State.aimAimPoint) == "Vector3" and State.aimAimPoint
		or hitPart.Position
	return pos, hitPart
end

function Bridge.reportError(tag, err)
	local msg = tostring(err)
	log("ERR", tag, msg)
	warn("[BRM5Research]", tag, msg)
	if debug and type(debug.traceback) == "function" then
		warn(debug.traceback(msg, 2))
	end
end

function Bridge.safeCall(tag, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		Bridge.reportError(tag, res)
		return false, res
	end
	return true, res
end

function Bridge.logVizHide(tag, reason, detail)
	if CONFIG.VizDebug ~= true then return end
	local key = tostring(tag) .. ":" .. tostring(reason)
	local now = os.clock()
	State._vizHideLog = State._vizHideLog or {}
	local last = State._vizHideLog[key] or 0
	if now - last < 0.75 then return end
	State._vizHideLog[key] = now
	local extra = detail and (" | " .. tostring(detail)) or ""
	log("VIZ", tostring(tag), "hide", tostring(reason), extra)
end

function Bridge.beginShotBurst(muzzleOrigin)
	if typeof(muzzleOrigin) ~= "Vector3" then return nil end
	Bridge.zeroClientWeaponSpread(Bridge.peekWeaponContext() or ctx)
	State.shotBurstActive = true
	State.shotBurstT = os.clock()
	State.lastDischargeAimTime = os.clock()
	State.localDischargePending = true
	State.awaitingServerDischarge = CONFIG.ServerFirstBullet == true
	State.pendingBulletSpawns = {}
	State.inShotPrep = false
	Bridge.refreshAimTarget(muzzleOrigin, true)
	if not State.shotAimTarget or not State.shotAimTarget.Parent then
		Bridge.refreshAimTarget(muzzleOrigin, true)
	end
	local target = State.shotAimTarget
	if target and target.Parent then
		Bridge.refreshShotAimAtMuzzle(muzzleOrigin, target)
	end
	State.shotBurstAimPoint = State.forceHitPoint or State.aimAimPoint
	if typeof(State.shotBurstAimPoint) == "Vector3" then
		State.aimAimPoint = State.shotBurstAimPoint
		State.forceHitPoint = State.shotBurstAimPoint
	end
	return State.shotBurstAimPoint
end

function Bridge.queueClientBulletSpawn(ref, self, uid, payload)
	if type(State.pendingBulletSpawns) ~= "table" then
		State.pendingBulletSpawns = {}
	end
	State.pendingBulletSpawns[#State.pendingBulletSpawns + 1] = {
		ref = ref,
		self = self,
		uid = uid,
		payload = payload,
	}
	return uid
end

function Bridge.flushPendingClientBullets()
	local pending = State.pendingBulletSpawns
	State.awaitingServerDischarge = false
	State.pendingBulletSpawns = nil
	if type(pending) ~= "table" then return end
	for _, job in ipairs(pending) do
		if type(job) == "table" and job.ref and job.payload then
			local ok, err = pcall(job.ref, job.self, 1, job.uid, job.payload)
			if not ok then
				Bridge.reportError("flushBullet", err)
			end
		end
	end
end

function Bridge.isShotBurstLocked()
	return State.shotBurstActive == true
		and os.clock() - (State.shotBurstT or 0) < 0.12
end

function Bridge.endShotBurst()
	State.shotBurstActive = false
end

function Bridge.getLockedShotAimPoint()
	if typeof(State.shotBurstAimPoint) == "Vector3"
		and os.clock() - (State.lastDischargeAimTime or 0) < 0.35 then
		return State.shotBurstAimPoint
	end
	if Bridge.isShotBurstLocked() and typeof(State.shotBurstAimPoint) == "Vector3" then
		return State.shotBurstAimPoint
	end
	return State.forceHitPoint or State.aimAimPoint
end

function Bridge.v138PelletNeedsPatch(muzzle, aimPoint, target, entry)
	-- SilentAim: never skip v138 — server needs our pitch/yaw.
	if Bridge.needsServerAimPatch() then return true end
	if CONFIG.LiteMultiPoint then return true end
	if typeof(muzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then return true end
	if target and Bridge.needsMuzzleOffset(muzzle, aimPoint, target) then return true end
	if type(entry) ~= "table" or type(entry[5]) ~= "number" or type(entry[6]) ~= "number" then
		return true
	end
	local dir = aimPoint - muzzle
	if dir.Magnitude < 0.05 then return false end
	local cf = CFrame.new(muzzle) * CFrame.fromOrientation(entry[5], entry[6], 0)
	return cf.LookVector:Dot(dir.Unit) < 0.992
end

function Bridge.resolveActorUidForPart(head, fallbackUid)
	if fallbackUid ~= nil then
		return Bridge.normalizeActorUid(fallbackUid)
	end
	if type(State.aimTargetUid) == "string" or type(State.aimTargetUid) == "number" then
		return Bridge.normalizeActorUid(State.aimTargetUid)
	end
	if head and head:IsA("BasePart") then
		local attr = head:GetAttribute("ActorUID")
		if attr ~= nil then return Bridge.normalizeActorUid(attr) end
		for uid, data in pairs(State.actors or {}) do
			if data.model and head:IsDescendantOf(data.model) then
				return Bridge.normalizeActorUid(data.uid or uid)
			end
		end
	end
	return nil
end

-- Единая точка прицеливания: v138, silent aim и aim-viz используют од��о и то же.
function Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, aimBone, basePoint)
	if not head or not head:IsA("BasePart") then return nil end
	ctx = ctx or Bridge.peekWeaponContext() or Bridge.getLiveWeaponContext(false)
	if typeof(muzzleOrigin) ~= "Vector3" then
		muzzleOrigin = Bridge.getAimLosOrigin()
	end
	uid = Bridge.resolveActorUidForPart(head, uid)
	local bone = (aimBone and aimBone:IsA("BasePart")) and aimBone or head
	local pt = typeof(basePoint) == "Vector3" and basePoint or bone.Position
	if CONFIG.Prediction == true and typeof(muzzleOrigin) == "Vector3" then
		local predicted = Bridge.predictAimPoint(uid, pt, muzzleOrigin, Bridge.getBulletSpeed(ctx), bone, 0)
		if typeof(predicted) == "Vector3" then
			pt = predicted
		end
	end
	if Bridge.shouldUseBacktrackAim() then
		pt = Bridge.applyBacktrackOffset(uid, pt, bone)
	end
	return pt
end

-- Точка для серверного ray: голова если видна с дула, иначе открытая кость (только при resolver).
function Bridge.resolveServerAimPoint(aimPart, head, muzzleOrigin, ctx, uid, cam, maxAngle, shotTime)
	if not head or not head:IsA("BasePart") then return nil end
	ctx = ctx or Bridge.peekWeaponContext() or Bridge.getLiveWeaponContext(false)
	if typeof(muzzleOrigin) ~= "Vector3" then
		muzzleOrigin = Bridge.getAimLosOrigin()
	end
	uid = Bridge.resolveActorUidForPart(head, uid)
	cam = cam or getCamera()
	maxAngle = maxAngle or CONFIG.SilentAimFOV or 15

	local model = head.Parent
	if Bridge.hasClearShotToPoint(muzzleOrigin, head.Position, head) then
		return Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, head)
	end

	if aimPart and aimPart:IsA("BasePart") and aimPart.Parent and aimPart ~= head then
		if Bridge.hasClearShotToPoint(muzzleOrigin, aimPart.Position, aimPart) then
			return Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, aimPart)
		end
	end

	if (shotTime or Bridge.needsExposedPointResolver()) and model and model:IsA("Model") then
		local expPart, expPoint = Bridge.findExposedPoint(model, uid, muzzleOrigin, cam, maxAngle, shotTime)
		if expPart and expPoint and expPart.Parent then
			return Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, expPart, expPoint)
		end
	end

	return Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, head)
end

function Bridge.retargetOriginDirection(originCFrame, aimWorldPos)
	if typeof(originCFrame) ~= "CFrame" or typeof(aimWorldPos) ~= "Vector3" then
		return originCFrame
	end
	local origin = originCFrame.Position
	if (aimWorldPos - origin).Magnitude < 0.01 then
		return originCFrame
	end
	return CFrame.lookAt(origin, aimWorldPos)
end

-- Перенаправляет OriginCFrame пули на цель: позиция мушки сохраняется,
-- только направление меняется к aimPt.
function Bridge.retargetOriginCFrame(originCFrame, _target, aimPt)
	return Bridge.retargetOriginDirection(originCFrame, aimPt)
end

function Bridge.shouldClientSpoofMuzzlePosition()
	if CONFIG.ClientMuzzleSpoof == false then return false end
	-- Подмена payload.OriginCFrame только для WallBang/MultiPoint (сдвиг muzzle).
	-- Обычный SA перенаправляет через GetMuzzleCFrame hook — не трогаем Send payload.
	return Bridge.shouldSpoofMuzzlePosition()
end

function Bridge.shouldServerMuzzleSpoof()
	return CONFIG.LiteMultiPoint == true
end

function Bridge.needsExposedPointResolver()
	return CONFIG.ResolverLite ~= false
end

function Bridge.exposedCacheKey(uid, model)
	if type(uid) == "string" and uid ~= "" then return uid end
	if typeof(model) == "Instance" then
		return "mdl:" .. model:GetFullName()
	end
	return "mdl:unknown"
end

function Bridge.needsMuzzleOffset(realMuzzle, aimPoint, targetPart)
	if not Bridge.shouldClientSpoofMuzzlePosition() then return false end
	if typeof(realMuzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then return false end
	return not Bridge.hasClearShotToPoint(realMuzzle, aimPoint, targetPart)
end

function Bridge.isValidRaycastFilterInstance(inst)
	return typeof(inst) == "Instance" and inst.Parent ~= nil
end

function Bridge.sanitizeBulletIgnore(ignore)
	if ignore == nil then return nil end
	if typeof(ignore) == "Instance" then
		return Bridge.isValidRaycastFilterInstance(ignore) and ignore or nil
	end
	if type(ignore) == "table" then
		local clean = {}
		local seen = {}
		local function collect(value)
			if typeof(value) == "Instance" then
				if Bridge.isValidRaycastFilterInstance(value) and not seen[value] then
					seen[value] = true
					clean[#clean + 1] = value
				end
			elseif type(value) == "table" then
				for _, nested in pairs(value) do
					collect(nested)
				end
			end
		end
		collect(ignore)
		if #clean == 0 then return nil end
		if #clean == 1 then return clean[1] end
		return clean
	end
	return nil
end

function Bridge.installSafeAddToFilterHook()
	if State.addToFilterHooked then return true end
	if type(hookfunction) ~= "function" then return false end

	local ok = pcall(function()
		local params = RaycastParams.new()
		local orig = params.AddToFilter
		local ref
		local function safeAdd(self, filter)
			if filter == nil then
				return ref(self, filter)
			end
			if typeof(filter) == "Instance" then
				if filter.Parent then
					return ref(self, filter)
				end
				return
			end
			if type(filter) == "table" then
				local clean = Bridge.sanitizeBulletIgnore(filter)
				if clean == nil then return end
				return ref(self, clean)
			end
		end
		local hookFn = type(newcclosure) == "function"
			and newcclosure(safeAdd, "brm5AddToFilter") or safeAdd
		ref = hookfunction(orig, hookFn)
		State.addToFilterRef = ref
	end)

	if ok then
		State.addToFilterHooked = true
		log("AIM", "RaycastParams.AddToFilter safe hook")
		return true
	end
	return false
end

function Bridge.isLocalBulletFlag(value)
	return value ~= nil and value ~= false
end

function Bridge.isLocalBulletPayload(payload)
	return type(payload) == "table" and Bridge.isLocalBulletFlag(payload.Local)
end

function Bridge.isOurBulletEvent(op, args)
	if type(args) ~= "table" then return false end
	if op == 2 then
		if args[7] == true then return true end
		if args[7] == false then return false end
		return Bridge.isRecentCombatShot()
	end
	if op == 1 then
		return Bridge.isRecentCombatShot()
			and (State.localDischargePending == true or State.shotBurstAimPoint ~= nil)
	end
	return false
end

function Bridge.shouldDrawBulletTracer(op, args, isLocal)
	if CONFIG.TracerLocalOnly == false then
		return op == 2
	end
	return Bridge.isOurBulletEvent(op, args)
end

function Bridge.isLocalPlayerShot(isLocal)
	return Bridge.resolveBulletEventIsLocal(isLocal)
end

function Bridge.isLocalBulletEvent(op, args)
	return Bridge.isOurBulletEvent(op, args)
end

function Bridge.isRecentCombatShot()
	return os.clock() - (State.lastDischargeAimTime or 0) < 0.45
end

function Bridge.isLocalDischargeWindow()
	return State.localDischargePending == true
		and os.clock() - (State.lastDischargeAimTime or 0) < 0.45
end

function Bridge.shouldPatchBulletHitEvent(isLocal)
	return Bridge.resolveBulletEventIsLocal(isLocal)
end

function Bridge.patchBulletHitArgs(originPos, hitPos, part, isLocal)
	if not Bridge.shouldPatchClientBulletHit() then
		return hitPos, part, false
	end
	if not Bridge.shouldPatchBulletHitEvent(isLocal) then
		return hitPos, part, false
	end
	if part and Bridge.isEnemyHitPart(part) then
		return hitPos, part, false
	end
	local newHit, newPart = Bridge.patchHitPartAndPos(hitPos, part, originPos)
	hitPos, part = newHit, newPart
	local aimPos = Bridge.getLockedShotAimPoint()
	if typeof(aimPos) == "Vector3" then
		hitPos = aimPos
	end
	return hitPos, part, part ~= nil
end

function Bridge.logBulletHit(op, part, isLocal, stage)
	if not CONFIG.LogBulletEvent and not CONFIG.LogBulletPayload then return end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
	log(
		"BULLET", "hit",
		stage or "evt",
		"op=" .. tostring(op),
		"part=" .. part.Name,
		"uid=" .. tostring(part:GetAttribute("ActorUID") or "?"),
		"isLocal=" .. tostring(isLocal)
	)
end

function Bridge.prepareCombatShotOnce(origin)
	if State.inShotPrep then
		if os.clock() - (State.inShotPrepTime or 0) > 0.05 then
			State.inShotPrep = false
		else
			return State.shotAimTarget
		end
	end
	if typeof(origin) ~= "Vector3" then
		local cam = getCamera()
		origin = cam and cam.CFrame.Position
	end
	if typeof(origin) ~= "Vector3" then return nil end
	Bridge.zeroClientWeaponSpread(Bridge.peekWeaponContext() or ctx)
	State.inShotPrep = true
	State.inShotPrepTime = os.clock()
	State.lastDischargeAimTime = os.clock()
	State.localDischargePending = true
	State.forceCombatAimRefresh = true
	local target = Bridge.getCombatAimTarget(origin, true)
	if target and target.Parent then
		local head = Bridge.getHeadPart(target.Parent, target) or target
		State.shotAimTarget = head
		State.shotAimTargetTime = os.clock()
		Bridge.refreshShotAimAtMuzzle(origin, head)
	end
	State.inShotPrep = false
	return State.shotAimTarget
end

function Bridge.forceClientBulletPayload(payload, muzzleHint)
	if type(payload) ~= "table" or State.inBulletPatch then
		return payload
	end
	-- shouldClientSpoofMuzzlePosition() — SA/MP/WallBang
	if not Bridge.shouldClientSpoofMuzzlePosition() then
		return payload
	end
	State.inBulletPatch = true
	payload.Local = true
	if payload._brm5AimPatched then
		State.inBulletPatch = false
		return payload
	end
	local aimPt = Bridge.getLockedShotAimPoint() or State.aimAimPoint or State.forceHitPoint
	local target = State.shotAimTarget
	if typeof(payload.OriginCFrame) == "CFrame" and typeof(aimPt) == "Vector3"
		and Bridge.shouldClientSpoofMuzzlePosition() then
		if target and target.Parent and type(Bridge.retargetOriginCFrame) == "function" then
			payload.OriginCFrame = Bridge.retargetOriginCFrame(payload.OriginCFrame, target, aimPt)
		end
		payload._brm5AimPatched = true
	elseif payload.Ignore ~= nil then
		payload.Ignore = Bridge.sanitizeBulletIgnore(payload.Ignore)
	end
	State.inBulletPatch = false
	return payload
end

function Bridge.sanitizeBulletPayload(payload, opts)
	if type(payload) ~= "table" then return end
	opts = type(opts) == "table" and opts or {}
	local localOnly = opts.localOnly == true
	local isLocal = Bridge.isLocalBulletFlag(payload.Local)

	if isLocal or not localOnly then
		if payload.Ignore ~= nil then
			payload.Ignore = Bridge.sanitizeBulletIgnore(payload.Ignore)
		end
		if payload.Replicate ~= nil and typeof(payload.Replicate) ~= "string" then
			payload.Replicate = nil
		end
	end

	if isLocal and typeof(payload.OriginCFrame) ~= "CFrame" then
		local actor = State.localClient and Bridge.getActorTable(State.localClient)
		local cf = Bridge.getFireOriginCFrame(actor)
		if typeof(cf) == "CFrame" then
			payload.OriginCFrame = cf
		end
	end
end

function Bridge.touchBulletPayload(payload)
	if type(payload) ~= "table" or payload._brm5AimPatched then
		return payload
	end
	if CONFIG.WallBangTest == true then
		Bridge.applyWallBangBulletPayload(payload)
	end
	if Bridge.isLocalPlayerShot(payload.Local) or Bridge.isLocalDischargeWindow() then
		return Bridge.forceClientBulletPayload(payload)
	end
	return payload
end

function Bridge.logBulletPayload(stage, payload)
	if not CONFIG.LogBulletEvent and not CONFIG.LogBulletPayload then return end
	if type(payload) ~= "table" then
		log("BULLET", stage, "type=" .. typeof(payload))
		return
	end
	local ig = payload.Ignore
	local igType = ig == nil and "nil"
		or (typeof(ig) == "Instance" and ("Instance:" .. ig.ClassName))
		or (type(ig) == "table" and ("table:" .. tostring(#ig)))
		or typeof(ig)
	log(
		"BULLET", stage,
		"uid=" .. tostring(payload.UID),
		"Ignore=" .. igType,
		"Origin=" .. (typeof(payload.OriginCFrame) == "CFrame" and "CFrame" or typeof(payload.OriginCFrame)),
		"Local=" .. tostring(payload.Local)
	)
end

function Bridge.processBulletPayload(payload)
	return Bridge.touchBulletPayload(payload)
end

function Bridge.resolveClientBulletOrigin(realOrigin, aimPoint, targetPart)
	if typeof(realOrigin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return realOrigin
	end
	local spoof = Bridge.resolveCombatMuzzleOffset(realOrigin, aimPoint, targetPart)
	if typeof(spoof) ~= "Vector3" then return realOrigin end
	State.spoofedMuzzlePos = spoof
	return spoof
end

function Bridge.ensureBulletHitPart(part, targetModel, fallbackPart)
	if Bridge.isValidActorHitPart(part) and part.Parent then
		if not targetModel or part:IsDescendantOf(targetModel) then
			return part
		end
	end
	if typeof(fallbackPart) == "Instance" and fallbackPart:IsA("BasePart") and fallbackPart.Parent then
		if Bridge.isValidActorHitPart(fallbackPart) then
			if not targetModel or fallbackPart:IsDescendantOf(targetModel) then
				return fallbackPart
			end
		end
		local head = Bridge.getHeadPart(targetModel, fallbackPart)
		if head and Bridge.isValidActorHitPart(head) then return head end
	end
	return nil
end

function Bridge.shouldPatchClientBulletOrigin()
	if CONFIG.ServerOnlyAimPatch == true then return false end
	return CONFIG.SilentAim or mpActive()
end

function Bridge.shouldPatchClientBulletHit()
	if CONFIG.ServerOnlyAimPatch == true then return false end
	return CONFIG.SilentAim == true or mpActive() or Bridge.shouldForceClientHit()
end

-- thin wrapper → hasClearShotToPoint
function Bridge.hasClearShot(origin, targetPart)
	if typeof(origin) ~= "Vector3" or not targetPart or not targetPart.Parent then return false end
	return Bridge.hasClearShotToPoint(origin, targetPart.Position, targetPart)
end

function Bridge.looksLikeClientService(t)
	return type(t) == "table"
		and type(rawget(t, "Clients")) == "table"
		and (
			type(rawget(t, "LocalClient")) == "table"
			or type(rawget(t, "GetClients")) == "function"
			or type(rawget(t, "GetClientFromName")) == "function"
			or rawget(t, "SquadChanged") ~= nil
		)
end

function Bridge.scoreClientService(t)
	if not Bridge.looksLikeClientService(t) then return 0 end
	local score = 0
	for _ in pairs(t.Clients) do
		score += 1
	end
	if t.LocalClient then score += 10 end
	return score
end

function Bridge.findClientServiceInGC()
	if type(getgc) ~= "function" then return nil end
	if State.actorScanNoGc then return State.clientService end
	local best, bestScore = nil, 0
	for _, v in ipairs(getGcCached()) do
		local score = Bridge.scoreClientService(v)
		if score > bestScore then
			best = v
			bestScore = score
		end
	end
	return best
end

function Bridge.resolveClientServiceInstance(force)
	if not force and State.clientService and Bridge.scoreClientService(State.clientService) > 0 then
		return State.clientService
	end

	local best, bestScore = nil, 0
	local function consider(svc)
		if not svc then return end
		local score = Bridge.scoreClientService(svc)
		if score > bestScore then
			best = svc
			bestScore = score
		end
	end

	if type(shared) == "table" and type(shared.import) == "function" then
		for _, path in ipairs({
			function() return shared.import("ClientService") end,
			function()
				local req = shared.import("require")
				if type(req) == "function" then return req("ClientService") end
			end,
			function()
				local req = shared.import("require")
				if type(req) == "function" then
					local mods = req({ "ClientService" })
					return type(mods) == "table" and mods.ClientService or nil
				end
			end,
		}) do
			local ok, svc = pcall(path)
			if ok then consider(svc) end
		end
	end

	consider(Bridge.findClientServiceInGC())

	if bestScore > 0 then
		State.clientService = best
		if best.LocalClient then
			State.localClient = best.LocalClient
		end
		if type(best.Clients) == "table" then
			for player, client in pairs(best.Clients) do
				if typeof(player) == "Instance" and player:IsA("Player") and type(client) == "table" then
					if player == LP then
						State.localClient = client
					end
					local uid = client.ActorUID or client.UID
					if uid then
						State.uidToPlayer[uid] = player
					end
				end
			end
		end
		return best
	end

	return State.clientService
end

function Bridge.getClientService()
	loadClientsModule()
	local svc = Bridge.resolveClientServiceInstance(false)
	if svc and Bridge.scoreClientService(svc) > 0 then
		return svc
	end
	if State.clients and type(State.clients.Clients) == "table" and countClientsTable(State.clients) > 0 then
		return State.clients
	end
	return svc or State.clients
end

function Bridge.looksLikeClientClass(t, player)
	if type(t) ~= "table" then return false end
	local owner = rawget(t, "Owner") or rawget(t, "Player")
	if player and owner ~= player then return false end
	return rawget(t, "Loadouts") ~= nil
		or rawget(t, "Squad") ~= nil
		or rawget(t, "IsLocalClient") ~= nil
		or rawget(t, "Order") ~= nil
		or rawget(t, "ActiveLoadout") ~= nil
end

function Bridge.findClientTableInGC(player)
	if type(getgc) ~= "function" or not player then return nil end
	if State.actorScanNoGc then return nil end
	local now = os.clock()
	local cached = State.clientByPlayer and State.clientByPlayer[player]
	if type(cached) == "table" then return cached end
	local negT = State.clientGcNegByPlayer and State.clientGcNegByPlayer[player]
	if type(negT) == "number" and now - negT < 20.0 then
		return nil
	end
	for _, v in ipairs(getGcCached()) do
		if Bridge.looksLikeClientClass(v, player) then
			State.clientByPlayer[player] = v
			return v
		end
	end
	State.clientGcNegByPlayer[player] = now
	return nil
end

function Bridge.getClientForPlayer(player, allowGc)
	if not player or not player:IsA("Player") then return nil end
	local cached = State.clientByPlayer and State.clientByPlayer[player]
	if type(cached) == "table" then return cached end

	local svc = Bridge.getClientService()
	if svc and type(svc.Clients) == "table" then
		local direct = svc.Clients[player]
		if type(direct) == "table" then
			State.clientByPlayer[player] = direct
			return direct
		end

		for key, client in pairs(svc.Clients) do
			if type(client) == "table" then
				local owner = tableField(client, "Owner") or tableField(client, "Player")
				if owner == player or key == player then
					State.clientByPlayer[player] = client
					return client
				end
			end
		end

		local byName = svc.GetClientFromName
		if type(byName) == "function" then
			local ok, client = pcall(byName, svc, player.Name)
			if ok and type(client) == "table" then
				State.clientByPlayer[player] = client
				return client
			end
		end
	end

	if State.clients and type(State.clients.Clients) == "table" then
		local direct = State.clients.Clients[player]
		if type(direct) == "table" then
			State.clientByPlayer[player] = direct
			return direct
		end
		local getter = State.clients.GetClientFromPlayer
		if type(getter) == "function" then
			local ok, client = pcall(getter, State.clients, player)
			if ok and type(client) == "table" then
				State.clientByPlayer[player] = client
				return client
			end
		end
	end

	if player == LP and type(State.localClient) == "table" then
		State.clientByPlayer[player] = State.localClient
		return State.localClient
	end

	if allowGc == true then
		return Bridge.findClientTableInGC(player)
	end
	return nil
end

function Bridge.getSquadFromClient(client)
	if type(client) ~= "table" then return nil end
	local squad = tableField(client, "Squad")
	if squad == nil then return nil end
	return tostring(squad)
end

function Bridge.getPlayerSquad(player, allowGc)
	if not player then return nil end
	local cached = State.squadByPlayer[player]
	if type(cached) == "string" then
		return cached
	end

	local client = Bridge.getClientForPlayer(player, allowGc == true)
	local squad = Bridge.getSquadFromClient(client)
	if squad ~= nil then
		State.squadByPlayer[player] = squad
	end
	return squad
end

function Bridge.getPlayerTeamKey(player, allowGc)
	local squad = Bridge.getPlayerSquad(player, allowGc == true)
	if squad then
		return "squad:" .. squad
	end
	return nil
end

function Bridge.resolvePlayerFromActor(uid, actorData, label)
	if type(actorData) == "table" then
		local owner = tableField(actorData, "Owner")
		if typeof(owner) == "Instance" and owner:IsA("Player") then
			State.uidToPlayer[uid] = owner
			return owner
		end
		local ownerName = tableField(actorData, "OwnerName")
		if type(ownerName) == "string" and ownerName ~= "" then
			local plr = Players:FindFirstChild(ownerName)
			if plr then
				State.uidToPlayer[uid] = plr
				return plr
			end
		end
	end
	local player = State.uidToPlayer[uid]
	if player then return player end
	if type(label) == "string" and label ~= "" and label ~= "localplayer" and label ~= "?" then
		local plr = Players:FindFirstChild(label)
		if plr then
			State.uidToPlayer[uid] = plr
			return plr
		end
	end
	return nil
end

function Bridge.resolveActorSquad(uid, actorData, label, player)
	player = player or Bridge.resolvePlayerFromActor(uid, actorData, label)
	if player then
		return Bridge.getPlayerSquad(player, false)
	end
	return nil
end

function Bridge.resolveActorTeamKey(uid, actorData, model, label)
	-- FIX v3: для NPC Owner=nil — не нужно resolvePlayerFromActor (дорогой поиск)
	if type(actorData) == "table" then
		local owner = rawget(actorData, "Owner")
		if owner ~= nil and typeof(owner) == "Instance" and owner:IsA("Player") then
			local squad = State.squadByPlayer[owner]
			return squad and ("squad:" .. squad) or nil
		end
		if owner == nil then
			-- NPC — берём TargetGroup с модели напрямую
			if rawget(actorData, "Zombie") == true then return "tg:2" end
			if model then
				local tg = model:GetAttribute("TargetGroup")
				if tg ~= nil then return "tg:" .. tostring(tg) end
			end
			return "tg:1" -- default hostile для NPC без TargetGroup
		end
	end
	local player = Bridge.resolvePlayerFromActor(uid, actorData, label)
	if player then
		local squad = State.squadByPlayer[player]
		return squad and ("squad:" .. squad) or nil
	end
	if model then
		local tg = model:GetAttribute("TargetGroup")
		if tg ~= nil then
			return "tg:" .. tostring(tg)
		end
	end
	return nil
end

function Bridge.refreshLocalTeamKey()
	loadClientsModule()
	resolveLocalClient(false)
	Bridge.resolveClientServiceInstance(false)

	local client = State.localClient
	local svc = Bridge.getClientService()
	if not client and svc then
		client = svc.LocalClient or (svc.Clients and svc.Clients[LP])
	end
	if not client then
		client = Bridge.getClientForPlayer(LP, not State.actorScanNoGc)
	end
	if client then
		State.localClient = client
	end

	local squad = client and Bridge.getSquadFromClient(client)
	State.localSquad = squad
	if squad ~= nil then
		State.localTeamKey = "squad:" .. squad
		State.squadByPlayer[LP] = squad
		return State.localTeamKey
	end

	State.localTeamKey = nil
	return nil
end

function Bridge.isSameSquad(mySquad, theirSquad)
	if mySquad == nil or theirSquad == nil then return false end
	return tostring(mySquad) == tostring(theirSquad)
end

function Bridge.refreshActorSquads()
	-- v2: throttle — не чаще раз в 5s
	local now = os.clock()
	if (now - (State.lastSquadRefresh or 0)) < 5.0 then return end
	State.lastSquadRefresh = now
	rebuildUidMap(false)
	Bridge.resolveClientServiceInstance(false)
	Bridge.refreshLocalTeamKey()
	table.clear(State.squadByPlayer)

	local svc = Bridge.getClientService()
	if svc and type(svc.Clients) == "table" then
		for player, client in pairs(svc.Clients) do
			if typeof(player) == "Instance" and player:IsA("Player") and type(client) == "table" then
				local squad = Bridge.getSquadFromClient(client)
				if squad ~= nil then
					State.squadByPlayer[player] = squad
				end
			elseif type(client) == "table" then
				local owner = tableField(client, "Owner")
				if typeof(owner) == "Instance" and owner:IsA("Player") then
					local squad = Bridge.getSquadFromClient(client)
					if squad ~= nil then
						State.squadByPlayer[owner] = squad
					end
				end
			end
		end
	end

	for _, data in pairs(State.actors) do
		if data.class ~= "player" then continue end
		local player = data.player
		if not player then
			player = State.uidToPlayer[data.uid]
		end
		if not player and data.label then
			player = Players:FindFirstChild(data.label)
		end
		if player then
			data.player = player
			data.squad = Bridge.getPlayerSquad(player, false)
			data.teamKey = data.squad and ("squad:" .. data.squad) or nil
		end
	end
end

function Bridge.isEnemyActor(data)
	if not data or data.class == "self" or data.class == "dead" or Bridge.isActorDead(data) then
		return false
	end
	-- FIX v8: EspShowPlayersInPve=true — показывать игроков даже в PVE-режимах
	if data.class == "player" and Bridge.isPveMode() then
		if CONFIG.EspShowPlayersInPve ~= true and CONFIG.ForceShowAllPlayers ~= true then
			return false
		end
	end
	if CONFIG.TeamCheck then
		if data.class == "npc_friendly" then return false end

		local mySquad = State.localSquad
		if mySquad == nil then
			Bridge.refreshLocalTeamKey()
			mySquad = State.localSquad
		end

		local theirSquad = data.squad
		if data.class == "player" then
			local player = data.player or Bridge.resolvePlayerFromActor(data.uid, nil, data.label)
			if player then
				theirSquad = Bridge.getPlayerSquad(player, false)
				data.player = player
				data.squad = theirSquad
			end
		end
		if theirSquad == nil and data.teamKey and string.sub(data.teamKey, 1, 6) == "squad:" then
			theirSquad = string.sub(data.teamKey, 7)
		end

		if Bridge.isSameSquad(mySquad, theirSquad) then
			return false
		end

		if data.class == "player" then
			return CONFIG.SilentAimTargetPlayers ~= false
		end
		if data.class == "npc_hostile" or data.class == "npc_zombie" then return true end
		if data.class == "npc" then
			local tk = data.teamKey
			if tk == "tg:0" then return false end
			if tk == "tg:1" or tk == "tg:2" then return true end
			return CONFIG.SilentAimTargetHostile ~= false
		end
		return false
	end
	return Bridge.isSilentAimTargetClass(data.class)
end

function Bridge.getReplicatorActorData(uid)
	if type(uid) ~= "string" or uid == "" or string.sub(uid, 1, 7) == "corpse:" then
		return nil
	end
	-- FIX v3: Flux хранит Actors[] с числовыми ключами — пробуем uid и tonumber(uid)
	local nuid = tonumber(uid)
	local cached = State.replicatorActorsTable
	if cached then
		local entry = cached[uid] or (nuid and cached[nuid])
		if entry ~= nil then return entry end
	end
	-- холодный путь — только если кэш пустой
	resolveLocalClient(false)
	local client = State.localClient
	if not client or type(Bridge.getActorTable) ~= "function" then return nil end
	local actor = Bridge.getActorTable(client)
	if not actor then return nil end
	local rep = tableField(actor, "Replicator")
	if type(rep) ~= "table" then return nil end
	local actors = tableField(rep, "Actors")
	if type(actors) ~= "table" then return nil end
	State.replicatorActorsTable = actors
	return actors[uid] or (nuid and actors[nuid])
end

-- v18: сбросить кэш actors таблицы (при смене клиента / full rescan)
function Bridge.invalidateReplicatorCache()
	State.replicatorActorsTable = nil
end

function Bridge.ensureHandlerDischargeHook(_handler)
	-- no-op в Lib; BRM5SilentAim может переопределить после загрузки.
end

function Bridge.weaponCanBreach()
	local ctx = State.weaponCtxCache
	if ctx == WEAPON_CTX_EMPTY then return false end
	local now = os.clock()
	if ctx and ctx._canBreach ~= nil and now - (ctx._canBreachT or 0) < 0.5 then
		return ctx._canBreach == true
	end
	if not ctx or not ctx.cal then
		ctx = Bridge.getLiveWeaponContext(false)
	end
	local can = ctx and ctx.cal and ctx.cal.CanBreach == true
	if ctx then
		ctx._canBreach = can == true
		ctx._canBreachT = now
	end
	return can == true
end

function Bridge.setDrawingAlpha(obj, visibleAmount)
	if not obj then return end
	visibleAmount = math.clamp(visibleAmount or 0, 0, 1)
	if CONFIG.DrawingHighTransparencyMeansVisible ~= false then
		obj.Transparency = visibleAmount
	else
		obj.Transparency = 1 - visibleAmount
	end
end

function Bridge.showDrawing(obj, visibleAmount)
	if not obj then return end
	visibleAmount = visibleAmount or 1
	-- Potassium Drawing: как HUD — Transparency=1 это видимо
	obj.Transparency = visibleAmount
	obj.Visible = visibleAmount > 0.01
end

function Bridge.resolveAimBonePart(model, fallbackPart)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return fallbackPart
	end
	local boneName = CONFIG.SilentAimBone or "Head"
	local bone = model:FindFirstChild(boneName)
	if bone and bone:IsA("BasePart") then return bone end
	return Bridge.getHeadPart(model, fallbackPart)
end

function Bridge.buildBulletForceHitSnapshot(origin, uid)
	if not (CONFIG.SilentAim or Bridge.shouldForceClientHit()) then return nil end
	local pending = uid and Bridge.getPendingBulletShot(uid) or nil
	local target = pending and pending.target or State.shotAimTarget or State.aimTargetPart
	local aimPart = pending and pending.aimPart or State.aimTargetPart or target
	local aimPt = pending and pending.aimPt or State.forceHitPoint or State.aimAimPoint
	if (not aimPart or not aimPart.Parent) and typeof(origin) == "Vector3" then
		target = Bridge.getCombatAimTarget(origin, false)
		aimPart = State.aimTargetPart or target
		aimPt = State.forceHitPoint or State.aimAimPoint
	end
	if not aimPart or not aimPart.Parent then return nil end
	local model = aimPart.Parent
	aimPart = Bridge.resolveAimBonePart(model, aimPart)
	if typeof(aimPt) ~= "Vector3" then
		aimPt = aimPart.Position
	end
	local aimUid = aimPart:GetAttribute("ActorUID")
	return {
		aimPart = aimPart,
		hitPos = aimPt,
		boneName = CONFIG.SilentAimBone or "Head",
		aimUid = type(aimUid) == "string" and aimUid or nil,
		replicate = true,
	}
end

function Bridge.wasClientBulletHitFired(uid)
	-- FIX v4: нормализуем uid
	if uid ~= nil and type(uid) ~= "string" then uid = tostring(uid) end
	if type(uid) ~= "string" or not State.clientBulletHitFired then return false end
	local t = State.clientBulletHitFired[uid]
	return type(t) == "number" and os.clock() - t < 3.0
end

function Bridge.markClientBulletHitFired(uid)
	if uid ~= nil and type(uid) ~= "string" then uid = tostring(uid) end
	if type(uid) ~= "string" or uid == "" then return end
	State.clientBulletHitFired = State.clientBulletHitFired or {}
	State.clientBulletHitFired[uid] = os.clock()
end

function Bridge.getBulletEventInstance()
	local inst = RF:FindFirstChild("BulletEvent")
	if inst and inst:IsA("BindableEvent") then return inst end
	return nil
end

local BRM5_PLACE_FALLBACK = {
	CM_Mission1 = { 83829699029749, 4843465225, 4 },
	OW_Ronograd = { 95595459346841, 3701546109, 1 },
	OW_Blank = { 0, 5899968224, 1 },
	HQ_Seychelles = { 139188553486454, 14014688944, 3 },
	PVP_Blank = { 99240342190508, 10938546013, 2 },
	PVP_Sandbox = { 125537938344868, 5468388011, 6 },
	ZMP_NYC = { 84460047957624, 4747446334, 5 },
	ZME_NYC = { 84460047957624, 4747446334, 5 },
}

function Bridge.refreshPlaceMode()
	local pid = game.PlaceId
	if State.placeModeCacheId == pid and State.placeModeCache then
		return State.placeModeCache
	end
	local placeName, placeType, isPve = nil, nil, false
	local sh = Bridge.getGameSharedImport and Bridge.getGameSharedImport()
	if sh then
		local ok, placeSvc = pcall(sh.import, "PlaceService")
		if ok and type(placeSvc) == "table" then
			placeName = placeSvc.PlaceName
			local places = placeSvc.Places
			if placeName and type(places) == "table" and type(places[placeName]) == "table" then
				placeType = places[placeName][3]
			end
		end
	end
	if not placeName then
		for name, entry in pairs(BRM5_PLACE_FALLBACK) do
			if entry[1] == pid or entry[2] == pid then
				placeName = name
				placeType = entry[3]
				break
			end
		end
	end
	if placeType == 2 or placeType == 6 then
		isPve = false
	elseif placeType == 1 or placeType == 3 or placeType == 4 then
		isPve = true
	elseif placeType == 5 then
		isPve = type(placeName) == "string" and string.match(placeName, "^ZME") ~= nil
	elseif type(placeName) == "string" then
		if string.sub(placeName, 1, 3) == "PVP" or string.match(placeName, "^ZMP") then
			isPve = false
		elseif string.match(placeName, "^ZME") or string.match(placeName, "^(CM_|OW_|HQ_)") then
			isPve = true
		end
	end
	State.placeModeCache = { name = placeName, type = placeType, isPve = isPve }
	State.placeModeCacheId = pid
	return State.placeModeCache
end

function Bridge.isPveMode()
	local mode = Bridge.refreshPlaceMode()
	return mode and mode.isPve == true
end

function Bridge.getNetworkPingMs()
	local ok, ping = pcall(function()
		return LP:GetNetworkPing() * 1000
	end)
	if ok and type(ping) == "number" and ping >= 0 then
		return ping
	end
	return 0
end

function Bridge.getBacktrackSec()
	return 0 -- Backtrack удалён v4
end

function Bridge.shouldUseBacktrackAim()
	return false -- Backtrack удалён v4
end

function Bridge.applyBacktrackOffset(uid, pt, bone)
	return pt -- Backtrack удалён v4
end

function Bridge.computeBacktrackWorldPoint(uid, point, part)
	return Bridge.applyBacktrackOffset(uid, point, part)
end

function Bridge.computeForceHitTimeOff()
	local sec = Bridge.getBacktrackSec()
	if sec > 0 then
		return -sec
	end
	return tonumber(CONFIG.ForceHitTimeOff) or 0
end

function Bridge.shouldSkipActorCollect(class, player, squad, teamKey, uid)
	-- FIX v8: ForceShowAllPlayers — показывать всех игроков без фильтрации
	if CONFIG.ForceShowAllPlayers == true and class == "player" then
		return false
	end
	if CONFIG.IgnoreTeammates == false and CONFIG.EspIgnoreTeam == false then
		return false
	end
	if class == "self" then
		return true
	end
	-- Труп: показываем ИГРОКОВ (data.player ~= nil) пока включён EspShowDead —
	-- рендер (esp.lua) сам рисует метку 'Dead'. Раньше здесь труп ИГРОКА тоже
	-- скипался на этапе сбора → в ESP мёртвые игроки не появлялись вообще.
	if class == "dead" then
		if CONFIG.EspShowDead ~= false and player ~= nil then
			return false
		end
		return true
	end
	return not Bridge.isEnemyActor({
		class = class,
		player = player,
		squad = squad,
		teamKey = teamKey,
		uid = uid,
	})
end

function Bridge.formatEspLabelWithDistance(data, camPos)
	local label = Bridge.formatEspActorLabel(data)
	if CONFIG.EspShowDistance == false or not data or not data.root or not camPos then
		return label
	end
	if data.class == "self" then return label end
	if Bridge.isEnemyActor(data) then
		local dist = (data.root.Position - camPos).Magnitude
		return string.format("%s [%.0fm]", label, dist)
	end
	return label
end

function Bridge.fireClientBulletOp1(uid, opts)
	opts = opts or {}
	if type(uid) ~= "string" or uid == "" then
		return false, "bad-uid"
	end
	if Bridge.wasClientBulletHitFired(uid) and not opts.allowRepeat then
		Bridge.diagForceHit("op1-skip", uid:sub(1, 8), "already-fired")
		return false, "already-fired"
	end
	if not (Bridge.shouldForceClientHit() or opts.force) then
		return false, "force-off"
	end
	if not Bridge.isMyBulletUid(uid) then
		return false, "foreign-uid"
	end
	local pending = Bridge.getPendingBulletShot(uid)
	local payload = opts.payload
	if not payload then
		payload = Bridge.resolveForceHitPayload(uid, opts.origin, opts.caliber)
	end
	if (not payload or not payload.part or not payload.part.Parent) and pending and pending.forceHitSnapshot then
		payload = Bridge.payloadFromForceHitSnapshot(pending.forceHitSnapshot, pending, opts.origin, opts.caliber)
	end
	if not payload or not payload.part or not payload.part.Parent then
		Bridge.diagForceHit("op1-fail", uid:sub(1, 8), "no-payload")
		return false, "no-payload"
	end
	local hitPos, part = payload.hitPos, payload.part
	local normal, material = payload.normal, payload.material
	if part and Bridge.isEnemyHitPart(part) then
		local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(hitPos, part, payload.origin, uid)
		if changed then
			hitPos, part = nh, np
			if nn then normal = nn end
		end
	end
	local replicate = opts.replicate
	if replicate == nil and pending then replicate = pending.replicate end
	if replicate == nil then replicate = true end
	local be = Bridge.getBulletEventInstance()
	if not be then
		return false, "no-BulletEvent"
	end
	local timeOff = opts.timeOff
	if timeOff == nil then
		timeOff = Bridge.computeForceHitTimeOff()
	end
	State.inOurBulletOp1Fire = uid
	local ok, err = pcall(function()
		be:Fire(1, uid, replicate, hitPos, part, normal, material, timeOff)
	end)
	State.inOurBulletOp1Fire = nil
	if not ok then
		Bridge.diagForceHit("op1-fail", uid:sub(1, 8), "pcall", tostring(err))
		return false, "pcall"
	end
	Bridge.markClientBulletHitFired(uid)
	Bridge.diagForceHit("our-op1", uid:sub(1, 8), "part=" .. tostring(part.Name), "repl=" .. tostring(replicate))
	if CONFIG.LogBulletEvent and type(Bridge.logBulletHit) == "function" then
		Bridge.logBulletHit(1, part, true, "our-op1")
	end
	return true
end

function Bridge.fireClientBulletHits(uid, opts)
	opts = opts or {}
	if type(uid) ~= "string" or uid == "" then
		Bridge.diagForceHit("fire-skip", "bad-uid")
		return false, "bad-uid"
	end
	if Bridge.wasClientBulletHitFired(uid) and not opts.allowRepeat then
		Bridge.diagForceHit("fire-skip", uid:sub(1, 8), "already-fired")
		return false, "already-fired"
	end
	if not (Bridge.shouldForceClientHit() or opts.force) then
		Bridge.diagForceHit("fire-skip", uid:sub(1, 8), "force-off")
		return false, "force-off"
	end
	if not Bridge.isMyBulletUid(uid) then
		Bridge.diagForceHit("fire-skip", uid:sub(1, 8), "foreign-uid")
		return false, "foreign-uid"
	end
	if opts.op1Only then
		return Bridge.fireClientBulletOp1(uid, opts)
	end
	local pending = Bridge.getPendingBulletShot(uid)
	local payload = Bridge.resolveForceHitPayload(uid, opts.origin, opts.caliber)
	if not payload or not payload.part or not payload.part.Parent then
		Bridge.diagForceHit(
			"fire-fail",
			uid:sub(1, 8),
			"no-payload",
			pending and "pending" or "no-pending",
			pending and pending.forceHitSnapshot and "snap" or "no-snap"
		)
		return false, "no-payload"
	end
	local hitPos, part = payload.hitPos, payload.part
	local normal, material, caliber = payload.normal, payload.material, payload.caliber
	local origin = payload.origin
	if part and Bridge.isEnemyHitPart(part) then
		local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(hitPos, part, origin, uid)
		if changed then
			hitPos, part = nh, np
			if nn then normal = nn end
		end
	end
	local replicate = opts.replicate
	if replicate == nil and pending then replicate = pending.replicate end
	if replicate == nil then replicate = true end
	local be = Bridge.getBulletEventInstance()
	if not be then
		Bridge.diagForceHit("fire-fail", uid:sub(1, 8), "no-BulletEvent")
		return false, "no-BulletEvent"
	end
	local timeOff = opts.timeOff or 0
	local ok2, err2 = pcall(function()
		be:Fire(2, origin, hitPos, part, normal, material, caliber, true)
	end)
	if not ok2 then
		Bridge.diagForceHit("fire-fail", uid:sub(1, 8), "op2-pcall", tostring(err2))
		return false, "pcall"
	end
	if opts.skipOp1 then
		Bridge.diagForceHit("flux-fire", uid:sub(1, 8), "op=2-only", "part=" .. tostring(part.Name))
		return true
	end
	local ok1, reason = Bridge.fireClientBulletOp1(uid, {
		origin = opts.origin,
		caliber = opts.caliber,
		replicate = replicate,
		timeOff = timeOff,
		allowRepeat = opts.allowRepeat,
		force = opts.force,
	})
	if not ok1 then
		Bridge.diagForceHit("fire-fail", uid:sub(1, 8), "op1", reason or "?")
		return false, reason or "op1-fail"
	end
	Bridge.diagForceHit(
		"flux-fire",
		uid:sub(1, 8),
		"op=2+our-op1",
		"part=" .. tostring(part.Name),
		"repl=" .. tostring(replicate)
	)
	if CONFIG.LogBulletEvent and type(Bridge.logBulletHit) == "function" then
		Bridge.logBulletHit(2, part, true, "flux-fire")
	end
	return true
end

function Bridge.scheduleForceBulletOp1(uid, origin, aimPt, caliber, replicate)
	if not Bridge.shouldForceClientHit() or type(uid) ~= "string" then return end
	if not Bridge.isMyBulletUid(uid) then return end
	if Bridge.wasClientBulletHitFired(uid) then
		Bridge.diagForceHit("op1-skip", uid:sub(1, 8), "already-fired")
		return
	end
	local function tryFire(attempt)
		if Bridge.wasClientBulletHitFired(uid) then return end
		if attempt == 1 then
			Bridge.diagForceHit("op1-now", uid:sub(1, 8))
		end
		local ok, reason = Bridge.fireClientBulletOp1(uid, {
			origin = origin,
			caliber = caliber,
			replicate = replicate,
		})
		if ok then return end
		if reason == "no-payload" and attempt < 4 and typeof(origin) == "Vector3" then
			Bridge.prepareCombatShotOnce(origin)
			task.defer(function()
				tryFire(attempt + 1)
			end)
			return
		end
		Bridge.diagForceHit("op1-fail", uid:sub(1, 8), reason or "?")
	end
	tryFire(1)
end

function Bridge.scheduleForceBulletHit(uid, origin, aimPt, caliber)
	if not Bridge.shouldForceClientHit() or type(uid) ~= "string" then return end
	if not Bridge.isMyBulletUid(uid) then return end
	if Bridge.wasClientBulletHitFired(uid) then return end
	local ok2, reason2 = Bridge.fireClientBulletHits(uid, {
		origin = origin,
		caliber = caliber,
		skipOp1 = true,
	})
	if not ok2 then
		Bridge.diagForceHit("fire-fail", uid:sub(1, 8), reason2 or "?")
		return
	end
	Bridge.scheduleForceBulletOp1(uid, origin, aimPt, caliber)
end

function Bridge.redirectEnemyHitToAimBone(hitPos, part, originPos, bulletUid)
	if not part or not Bridge.isEnemyHitPart(part) then
		return hitPos, part, nil, false
	end
	if not (CONFIG.SilentAim or Bridge.shouldForceClientHit()) then
		return hitPos, part, nil, false
	end
	local model = part.Parent
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return hitPos, part, nil, false
	end
	local pending = bulletUid and Bridge.getPendingBulletShot(bulletUid) or nil
	local bonePart = Bridge.resolveAimBonePart(model, part)
	if not bonePart or not bonePart.Parent then
		return hitPos, part, nil, false
	end
	local newPos = bonePart.Position
	local hitUid = part:GetAttribute("ActorUID")
		or Bridge.resolveActorUidForPart(part, nil)
	if pending and typeof(pending.aimPt) == "Vector3" then
		local pUid = pending.target and pending.target:GetAttribute("ActorUID")
			or State.aimTargetUid
		if hitUid and pUid and hitUid == pUid then
			newPos = pending.aimPt
		end
	elseif typeof(State.forceHitPoint) == "Vector3" and hitUid and State.aimTargetUid == hitUid then
		newPos = State.forceHitPoint
	elseif typeof(State.aimAimPoint) == "Vector3" and hitUid and State.aimTargetUid == hitUid then
		newPos = State.aimAimPoint
	elseif CONFIG.Prediction == true or CONFIG.SilentAim then
		local head = Bridge.getHeadPart(model, bonePart) or bonePart
		local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or Bridge.getLiveWeaponContext(false)
		local muzzle = typeof(originPos) == "Vector3" and originPos or Bridge.getAimLosOrigin()
		local aimPt = Bridge.resolveUnifiedAimPoint(head, muzzle, ctx, hitUid, bonePart)
		if typeof(aimPt) == "Vector3" then
			newPos = aimPt
		end
	end
	if bonePart == part and typeof(hitPos) == "Vector3" and (newPos - hitPos).Magnitude < 0.15 then
		return hitPos, part, nil, false
	end
	local normal
	if typeof(originPos) == "Vector3" then
		local n = originPos - newPos
		if n.Magnitude > 0.01 then normal = n.Unit end
	end
	return newPos, bonePart, normal, true
end

function Bridge.shouldForceClientHit()
	return CONFIG.ForceClientHit == true or CONFIG.ForceHit == true
end

function Bridge.getBulletRayIncludeRegistry()
	if not State.bulletRayIncludeRegistry then
		State.bulletRayIncludeRegistry = setmetatable({}, { __mode = "k" })
	end
	return State.bulletRayIncludeRegistry
end

function Bridge.getBulletRayTmRegistry()
	if not State.bulletRayTmRegistry then
		State.bulletRayTmRegistry = setmetatable({}, { __mode = "k" })
	end
	return State.bulletRayTmRegistry
end

function Bridge.markBulletRayInclude(params)
	if typeof(params) == "RaycastParams" then
		Bridge.getBulletRayIncludeRegistry()[params] = true
	end
end

function Bridge.isBulletRayInclude(params)
	return typeof(params) == "RaycastParams"
		and Bridge.getBulletRayIncludeRegistry()[params] == true
end

function Bridge.isGameBulletRaycastParams(params)
	if typeof(params) ~= "RaycastParams" then return false end
	if Bridge.isBulletRayInclude(params) then return true end
	local ok, cg = pcall(function()
		return params.CollisionGroup
	end)
	return ok and cg == 9
end

function Bridge.collectEnemyRayIncludeParts(targetPart)
	if typeof(targetPart) ~= "Instance" or not targetPart:IsA("BasePart") then
		return {}
	end
	local model = targetPart.Parent
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return { targetPart }
	end
	local parts, seen = {}, {}
	local function addPart(part)
		if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end
		if not part.Parent or seen[part] then return end
		seen[part] = true
		parts[#parts + 1] = part
	end
	addPart(targetPart)
	local head = Bridge.getHeadPart and Bridge.getHeadPart(model, targetPart)
	if head then addPart(head) end
	for _, name in ipairs({ "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
		"LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
		"LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg" }) do
		local p = model:FindFirstChild(name)
		if p then addPart(p) end
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc:GetAttribute("ActorUID") then
			addPart(desc)
		end
	end
	return parts
end

function Bridge.resolveForceHitRayTarget(bullet, originHint)
	local pending = bullet and bullet._uid and Bridge.getPendingBulletShot(bullet._uid) or nil
	local target = pending and (pending.aimPart or pending.target)
		or State.shotAimTarget or State.aimTargetPart
	if (not target or not target.Parent) and typeof(originHint) == "Vector3" then
		target = Bridge.getCombatAimTarget(originHint, false)
	end
	if target and target.Parent then
		target = Bridge.resolveAimBonePart(target.Parent, target)
	end
	return target
end

function Bridge.patchBulletRayForceHit(bullet)
	if not Bridge.shouldForceClientHit() or not bullet or not bullet._rayParams then
		return false
	end
	local params = bullet._rayParams
	if Bridge.isBulletRayInclude(params) then return true end
	local origin = bullet._originCFrame and bullet._originCFrame.Position
	local target = Bridge.resolveForceHitRayTarget(bullet, origin)
	if not target or not target.Parent then return false end
	local includeParts = Bridge.collectEnemyRayIncludeParts(target)
	if #includeParts == 0 then return false end
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = includeParts
	Bridge.markBulletRayInclude(params)
	bullet._brm5ForceHitRay = true
	return true
end

function Bridge.interceptForceHitRaycast(old, workspaceInst, origin, direction, params)
	if not Bridge.isGameBulletRaycastParams(params) then
		return old(workspaceInst, origin, direction, params)
	end
	if not Bridge.isRecentCombatShot() and not Bridge.isLocalDischargeWindow() then
		return old(workspaceInst, origin, direction, params)
	end
	local realHit = old(workspaceInst, origin, direction, params)
	if realHit and Bridge.isEnemyHitPart(realHit.Instance) then
		return realHit
	end
	local payload = Bridge.resolveForceHitPayloadForRecent(origin, nil)
	if not payload or not payload.part or not payload.part.Parent or typeof(payload.hitPos) ~= "Vector3" then
		return realHit
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return realHit
	end
	local dist = direction.Magnitude
	if dist < 0.05 then return realHit end
	local dirU = direction.Unit
	local toAim = payload.hitPos - origin
	local along = toAim:Dot(dirU)
	if along < 0 or along > dist + 8 then
		return realHit
	end
	if realHit and not Bridge.isEnemyHitPart(realHit.Instance) then
		return {
			Instance = payload.part,
			Position = payload.hitPos,
			Normal = payload.normal,
			Material = payload.material or Bridge.resolveHitMaterial(payload.part),
			Distance = math.min(math.max(along, 0), dist),
		}
	end
	if not realHit then
		return {
			Instance = payload.part,
			Position = payload.hitPos,
			Normal = payload.normal,
			Material = payload.material or Bridge.resolveHitMaterial(payload.part),
			Distance = math.min(math.max(along, 0), dist),
		}
	end
	return realHit
end

function Bridge.shouldForceMeleeKaRaycast()
	return CONFIG.KillAura == true
		and CONFIG.KillAuraForceHit ~= false
		and State.kaMeleeForceRaycast == true
end

function Bridge.resolveMeleeKaForceHitPart()
	local td = State.kaTarget
	local aimPart = State.kaImpactPart
	local hitPos = State.kaAimPoint
	if aimPart and typeof(aimPart) == "Instance" and aimPart:IsA("BasePart") and aimPart.Parent then
		if typeof(hitPos) ~= "Vector3" then hitPos = aimPart.Position end
		return aimPart, hitPos
	end
	if type(td) == "table" and td.model and td.model.Parent then
		local p = td.model:FindFirstChild("Head")
			or td.model:FindFirstChild("UpperTorso")
			or td.model:FindFirstChild("HumanoidRootPart")
			or td.root
		if p and p:IsA("BasePart") then
			if typeof(hitPos) ~= "Vector3" then hitPos = p.Position end
			return p, hitPos
		end
	end
	if aimPart and typeof(aimPart) == "Instance" and aimPart:IsA("BasePart") then
		if typeof(hitPos) ~= "Vector3" then hitPos = aimPart.Position end
		return aimPart, hitPos
	end
	if typeof(hitPos) == "Vector3" then return nil, hitPos end
	return nil, nil
end

function Bridge.interceptMeleeKaRaycast(old, workspaceInst, origin, direction, params)
	if not Bridge.shouldForceMeleeKaRaycast() then
		return old(workspaceInst, origin, direction, params)
	end
	if typeof(params) ~= "RaycastParams" and not Bridge.isGameBulletRaycastParams(params) then
		return old(workspaceInst, origin, direction, params)
	end
	local part, hitPos = Bridge.resolveMeleeKaForceHitPart()
	if typeof(hitPos) ~= "Vector3" or typeof(origin) ~= "Vector3" then
		return old(workspaceInst, origin, direction, params)
	end
	if not part then
		return old(workspaceInst, origin, direction, params)
	end
	local dist = typeof(direction) == "Vector3" and direction.Magnitude or 0
	local along = (hitPos - origin).Magnitude
	local normal = origin - hitPos
	if normal.Magnitude < 0.01 then
		normal = Vector3.new(0, 1, 0)
	else
		normal = normal.Unit
	end
	return {
		Instance = part,
		Position = hitPos,
		Normal = normal,
		Material = Bridge.resolveHitMaterial(part),
		Distance = dist > 0.05 and math.min(along, dist) or along,
	}
end

function Bridge.resolveHitMaterial(part)
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		local ok, mat = pcall(function()
			return part.Material
		end)
		if ok and typeof(mat) == "EnumItem" then
			return mat
		end
	end
	return Enum.Material.Plastic
end

function Bridge.isStrictLocalShot(isLocal)
	return isLocal == true
end

function Bridge.markLocalBulletUid(uid)
	if type(uid) ~= "string" or uid == "" then return end
	State.myBulletUids = State.myBulletUids or {}
	State.myBulletUids[uid] = os.clock()
end

function Bridge.isMyBulletUid(uid)
	if uid ~= nil and type(uid) ~= "string" then uid = tostring(uid) end
	if type(uid) ~= "string" or not State.myBulletUids then return false end
	local t = State.myBulletUids[uid]
	return type(t) == "number" and os.clock() - t < 3.0
end

function Bridge.isMyBulletBatch(uid, entry)
	return Bridge.isMyBulletUid(uid)
end

function Bridge.getRecentPendingBulletUid(maxAge)
	maxAge = maxAge or 0.65
	local bestUid, bestAge = nil, maxAge
	for uid, entry in pairs(State.pendingBulletShots or {}) do
		local age = os.clock() - (entry.t or 0)
		if age < bestAge then
			bestAge = age
			bestUid = uid
		end
	end
	return bestUid
end

function Bridge.resolveForceHitPayloadForRecent(originHint, caliberHint)
	local uid = Bridge.getRecentPendingBulletUid()
	return Bridge.resolveForceHitPayload(uid, originHint, caliberHint)
end

function Bridge.applyForceHitOp2(originPos, hitPos, part, normal, material, caliber, bulletUid)
	if not Bridge.shouldForceClientHit() then return nil end
	if part and Bridge.isEnemyHitPart(part) then return nil end
	local payload = Bridge.resolveForceHitPayload(bulletUid, originPos, caliber)
		or Bridge.resolveForceHitPayloadForRecent(originPos, caliber)
	if not payload then return nil end
	return payload.origin, payload.hitPos, payload.part, payload.normal, payload.material, payload.caliber, true
end

function Bridge.spawnTracerForMyBullet(uid, origin, aimPt)
	if not CONFIG.ShotTracers then return end
	if not Bridge.isMyBulletUid(uid) then return end
	if typeof(origin) ~= "Vector3" or typeof(aimPt) ~= "Vector3" then return end
	if type(Bridge.spawnShotTracer) == "function" then
		Bridge.spawnShotTracer(origin, aimPt, { bulletUid = uid })
	end
end

function Bridge.payloadFromForceHitSnapshot(snap, pending, originHint, caliberHint)
	if type(snap) ~= "table" then return nil end
	local aimPart = snap.aimPart
	if not aimPart or not aimPart.Parent then return nil end
	local aimPt = snap.hitPos
	if typeof(aimPt) ~= "Vector3" then
		aimPt = aimPart.Position
	end
	local origin = (pending and pending.origin) or originHint or State.lastShotOrigin
	if typeof(origin) ~= "Vector3" then
		local cf = Bridge.getLocalMuzzleCFrame and Bridge.getLocalMuzzleCFrame()
		if cf and typeof(cf.Position) == "Vector3" then
			origin = cf.Position
		end
	end
	if typeof(origin) ~= "Vector3" then return nil end
	local normal = origin - aimPt
	if normal.Magnitude < 0.01 then
		normal = Vector3.new(0, 0, -1)
	else
		normal = normal.Unit
	end
	local mat = Bridge.resolveHitMaterial(aimPart)
	local caliber = caliberHint or (pending and pending.caliber)
	return {
		origin = origin,
		hitPos = aimPt,
		part = aimPart,
		normal = normal,
		material = mat,
		caliber = caliber,
		isLocal = true,
	}
end

function Bridge.storePendingBulletShot(uid, target, aimPart, aimPt, origin, caliber, replicate)
	if type(uid) ~= "string" or uid == "" then return end
	State.pendingBulletShots = State.pendingBulletShots or {}
	local snap = Bridge.buildBulletForceHitSnapshot(origin, uid)
	State.pendingBulletShots[uid] = {
		target = target,
		aimPart = aimPart,
		aimPt = aimPt,
		origin = origin,
		caliber = caliber,
		replicate = replicate ~= nil and replicate or true,
		forceHitSnapshot = snap,
		t = os.clock(),
	}
	Bridge.markLocalBulletUid(uid)
	Bridge.diagForceHit(
		"store",
		uid:sub(1, 8),
		snap and snap.aimPart and snap.aimPart.Name or "no-aim",
		"repl=" .. tostring(replicate ~= nil and replicate or true)
	)
end

function Bridge.resolveForceHitPayload(uid, originHint, caliberHint)
	local pending = Bridge.getPendingBulletShot(uid)
	if pending and pending.forceHitSnapshot then
		local snapPayload = Bridge.payloadFromForceHitSnapshot(
			pending.forceHitSnapshot, pending, originHint, caliberHint
		)
		if snapPayload and snapPayload.part and snapPayload.part.Parent then
			return snapPayload
		end
	end
	local target = pending and pending.target or State.shotAimTarget or State.aimTargetPart
	local aimPart = pending and pending.aimPart or State.aimTargetPart or target
	local aimPt = pending and pending.aimPt or State.forceHitPoint or State.aimAimPoint
	if (not aimPart or not aimPart.Parent) and target and target.Parent then
		aimPart = target
	end
	if typeof(aimPt) ~= "Vector3" and aimPart and aimPart.Parent then
		aimPt = aimPart.Position
	end
	if (not aimPart or not aimPart.Parent or typeof(aimPt) ~= "Vector3")
		and typeof(originHint) == "Vector3" and Bridge.shouldForceClientHit()
		and not State.inForceHitResolve then
		State.inForceHitResolve = true
		Bridge.prepareCombatShot(originHint)
		State.inForceHitResolve = nil
		target = State.shotAimTarget or State.aimTargetPart
		aimPart = State.aimTargetPart or target
		aimPt = State.forceHitPoint or State.aimAimPoint
		if typeof(aimPt) ~= "Vector3" and aimPart and aimPart.Parent then
			aimPt = aimPart.Position
		end
	end
	if not aimPart or not aimPart.Parent or typeof(aimPt) ~= "Vector3" then
		if pending and pending.forceHitSnapshot then
			return Bridge.payloadFromForceHitSnapshot(pending.forceHitSnapshot, pending, originHint, caliberHint)
		end
		return nil
	end
	aimPart = Bridge.resolveAimBonePart(aimPart.Parent, aimPart) or aimPart
	local origin = pending and pending.origin or originHint or State.lastShotOrigin
	if typeof(origin) ~= "Vector3" then
		local cf = Bridge.getLocalMuzzleCFrame and Bridge.getLocalMuzzleCFrame()
		if cf and typeof(cf.Position) == "Vector3" then
			origin = cf.Position
		end
	end
	if typeof(origin) ~= "Vector3" then return nil end
	local normal = origin - aimPt
	if normal.Magnitude < 0.01 then
		normal = Vector3.new(0, 0, -1)
	else
		normal = normal.Unit
	end
	local mat = Bridge.resolveHitMaterial(aimPart)
	local caliber = caliberHint or (pending and pending.caliber)
	return {
		origin = origin,
		hitPos = aimPt,
		part = aimPart,
		normal = normal,
		material = mat,
		caliber = caliber,
		isLocal = true,
	}
end

function Bridge.buildForceHitOp1Entry(uid, replicateHint, timeOffHint)
	if not Bridge.shouldForceClientHit() then return nil end
	local payload = Bridge.resolveForceHitPayload(uid, nil, nil)
	if not payload then return nil end
	local pending = Bridge.getPendingBulletShot(uid)
	return {
		1,
		uid,
		replicateHint ~= nil and replicateHint or (pending and pending.replicate) or true,
		payload.hitPos,
		payload.part,
		payload.normal,
		payload.material,
		timeOffHint or 0,
	}
end

function Bridge.buildForceHitOp2Entry(uid, originHint, caliberHint)
	if not Bridge.shouldForceClientHit() then return nil end
	local payload = Bridge.resolveForceHitPayload(uid, originHint, caliberHint)
	if not payload then return nil end
	return {
		2,
		payload.origin,
		payload.hitPos,
		payload.part,
		payload.normal,
		payload.material,
		payload.caliber,
		true,
	}
end

function Bridge.shouldPatchClientBullet()
	return CONFIG.SilentAim == true or mpActive() or Bridge.shouldForceClientHit()
end

function Bridge.patchReceiveBatch(batch)
	if type(batch) ~= "table" then return batch end
	if rawget(batch, "__brm5RecvPatched") then return batch end
	rawset(batch, "__brm5RecvPatched", true)
	for uid, payloads in pairs(batch) do
		if type(payloads) ~= "table" then continue end
		local isMine = Bridge.isMyBulletUid(uid)
		local hadEnemyOp2 = false
		local hadEnemyOp1 = false
		for _, entry in ipairs(payloads) do
			if type(entry) ~= "table" then continue end
			local op = entry[1]
			if op == 2 then
				if not isMine then continue end
				if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
					hadEnemyOp2 = true
					local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(
						entry[3], entry[4], entry[2], uid
					)
					if changed then
						entry[3], entry[4] = nh, np
						if nn then entry[5] = nn end
					end
					if type(Bridge.tryLocalEnemyHitFx) == "function" then
						Bridge.tryLocalEnemyHitFx(2, entry[3], entry[4], entry[5], true, uid)
					end
					continue
				end
				if Bridge.shouldForceClientHit() then
					local forced = Bridge.buildForceHitOp2Entry(uid, entry[2], entry[6])
					if forced then
						for i = 1, #forced do entry[i] = forced[i] end
						if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
							hadEnemyOp2 = true
						end
					end
				end
				if Bridge.shouldPatchClientBullet() and type(Bridge.patchHitPartAndPos) == "function" then
					entry[3], entry[4] = Bridge.patchHitPartAndPos(entry[3], entry[4], entry[2])
				end
				if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
					hadEnemyOp2 = true
				end
			elseif op == 1 then
				if not isMine then continue end
				if Bridge.shouldForceClientHit() then
					if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
						local nh, np = Bridge.redirectEnemyHitToAimBone(entry[3], entry[4], nil, uid)
						if type(Bridge.tryLocalEnemyHitFx) == "function" then
							Bridge.tryLocalEnemyHitFx(1, np or entry[3], entry[4], entry[5], nil, uid)
						end
					end
					entry._brm5DropOp1 = true
					continue
				end
				if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
					hadEnemyOp1 = true
					local nh, np, nn, changed = Bridge.redirectEnemyHitToAimBone(
						entry[3], entry[4], nil, uid
					)
					if changed then
						entry[3], entry[4] = nh, np
						if nn then entry[5] = nn end
					end
					if type(Bridge.tryLocalEnemyHitFx) == "function" then
						Bridge.tryLocalEnemyHitFx(1, entry[3], entry[4], entry[5], nil, uid)
					end
					continue
				end
				if Bridge.shouldPatchClientBullet() and typeof(entry[3]) == "Vector3"
					and type(Bridge.patchHitPartAndPos) == "function" then
					entry[3], entry[4] = Bridge.patchHitPartAndPos(entry[3], entry[4], entry[3])
				end
				if entry[4] and Bridge.isEnemyHitPart(entry[4]) then
					hadEnemyOp1 = true
				end
			end
		end
		for idx = #payloads, 1, -1 do
			local entry = payloads[idx]
			if type(entry) == "table" and entry._brm5DropOp1 then
				table.remove(payloads, idx)
			end
		end
		if isMine and Bridge.shouldForceClientHit() then
			if not hadEnemyOp2 then
				local injected2 = Bridge.buildForceHitOp2Entry(uid)
				if injected2 then
					payloads[#payloads + 1] = injected2
				end
			end
			if not Bridge.wasClientBulletHitFired(uid) then
				task.defer(function()
					if Bridge.wasClientBulletHitFired(uid) then return end
					Bridge.scheduleForceBulletOp1(uid)
				end)
			end
		end
	end
	return batch
end

function Bridge.spawnDischargeTracer(uid, origin, aimPt)
	Bridge.spawnTracerForMyBullet(uid, origin, aimPt)
end

function Bridge.getPendingBulletShot(uid)
	if uid ~= nil and type(uid) ~= "string" then uid = tostring(uid) end
	if type(uid) ~= "string" or not State.pendingBulletShots then return nil end
	local entry = State.pendingBulletShots[uid]
	if not entry or os.clock() - (entry.t or 0) > 2.5 then
		State.pendingBulletShots[uid] = nil
		return nil
	end
	return entry
end

function Bridge.prunePendingBulletShots(now)
	if not State.pendingBulletShots then return end
	now = now or os.clock()
	for uid, entry in pairs(State.pendingBulletShots) do
		if now - (entry.t or 0) > 2.5 then
			State.pendingBulletShots[uid] = nil
		end
	end
	if State.myBulletUids then
		for uid, t in pairs(State.myBulletUids) do
			if now - (t or 0) > 3.0 then
				State.myBulletUids[uid] = nil
			end
		end
	end
end

function Bridge.mergeBulletIgnore(existing, additions)
	if type(additions) ~= "table" or #additions == 0 then
		return existing
	end
	local seen, out = {}, {}
	local function add(v)
		if typeof(v) == "Instance" and v.Parent and not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	if typeof(existing) == "Instance" then
		add(existing)
	elseif type(existing) == "table" then
		for _, v in ipairs(existing) do add(v) end
	end
	for _, v in ipairs(additions) do add(v) end
	if #out == 0 then return existing end
	if #out == 1 then return out[1] end
	return out
end

function Bridge.isTeammateActor(data)
	if not data or data.class == "self" or data.class == "dead" then
		return false
	end
	if data.class == "npc_friendly" then return true end
	if not CONFIG.TeamCheck or CONFIG.IgnoreTeammates == false then
		return false
	end
	local mySquad = State.localSquad
	if mySquad == nil then
		Bridge.refreshLocalTeamKey()
		mySquad = State.localSquad
	end
	local theirSquad = data.squad
	if data.class == "player" then
		local player = data.player or Bridge.resolvePlayerFromActor(data.uid, nil, data.label)
		if player then
			theirSquad = Bridge.getPlayerSquad(player, false)
			data.player = player
			data.squad = theirSquad
		end
	end
	if theirSquad == nil and data.teamKey and string.sub(data.teamKey, 1, 6) == "squad:" then
		theirSquad = string.sub(data.teamKey, 7)
	end
	if Bridge.isSameSquad(mySquad, theirSquad) then return true end
	if data.class == "npc" and data.teamKey == "tg:0" then return true end
	return false
end

function Bridge.applyTeammateBulletIgnore(ignore)
	if CONFIG.IgnoreTeammates == false then return ignore end
	local tm = Bridge.collectTeammateIgnore()
	if #tm == 0 then return ignore end
	return Bridge.mergeBulletIgnore(ignore, tm)
end

function Bridge.collectTeammateIgnore()
	local now = os.clock()
	if State._teammateIgnoreCache and now - (State._teammateIgnoreCacheT or 0) < 0.45 then
		return State._teammateIgnoreCache
	end
	local out, seen = {}, {}
	local function addInst(inst)
		if typeof(inst) ~= "Instance" or not inst.Parent or seen[inst] then return end
		seen[inst] = true
		out[#out + 1] = inst
	end
	local function addModel(model)
		if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then return end
		addInst(model)
		if #out >= 16 then return end
	end
	Bridge.refreshActorSquads()
	for _, data in pairs(State.actors or {}) do
		if Bridge.isTeammateActor(data) and data.model then
			addModel(data.model)
		end
	end
	local lp = Players.LocalPlayer
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp and plr.Character then
			local uid = plr.Character:GetAttribute("ActorUID")
			local data = uid and State.actors and State.actors[uid]
			if data and Bridge.isTeammateActor(data) then
				addModel(plr.Character)
			elseif data == nil and CONFIG.TeamCheck then
				local mySquad = State.localSquad
				local theirSquad = Bridge.getPlayerSquad(plr, false)
				if Bridge.isSameSquad(mySquad, theirSquad) then
					addModel(plr.Character)
				end
			end
		end
	end
	State._teammateIgnoreCache = out
	State._teammateIgnoreCacheT = now
	return out
end

function Bridge.patchBulletRayIgnore(bullet)
	if not bullet or not bullet._rayParams then return end
	if Bridge.shouldForceClientHit() then
		Bridge.patchBulletRayForceHit(bullet)
	end
	if CONFIG.IgnoreTeammates == false then
		return
	end
	local params = bullet._rayParams
	local tmReg = Bridge.getBulletRayTmRegistry()
	if tmReg[params] then return end
	tmReg[params] = true
	for _, inst in ipairs(Bridge.collectTeammateIgnore()) do
		pcall(function() params:AddToFilter(inst) end)
	end
end

function Bridge.applyCombatBulletIgnore(ignore, origin, aimPoint, targetPart)
	ignore = Bridge.applyTeammateBulletIgnore(ignore)
	if CONFIG.WallBangTest == true and typeof(origin) == "Vector3" and typeof(aimPoint) == "Vector3" and targetPart then
		ignore = Bridge.applyWallBangIgnore(ignore, origin, aimPoint, targetPart)
	end
	return ignore
end

-- WallBangTest: собираем стены между muzzle и целью → в Ignore пули (без патча BulletEvent)
function Bridge.collectWallBangIgnore(origin, aimPoint, targetPart, maxParts)
	if typeof(origin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return {}
	end
	maxParts = maxParts or 6
	local model = targetPart and targetPart.Parent
	local dir = aimPoint - origin
	local dist = dir.Magnitude
	if dist < 0.05 then return {} end
	local key = math.floor(origin.X) .. "|" .. math.floor(aimPoint.X) .. "|" .. (targetPart and targetPart.Name or "")
	local now = os.clock()
	State.wallBangIgnoreCache = State.wallBangIgnoreCache or {}
	local cached = State.wallBangIgnoreCache[key]
	if cached and now - (cached.t or 0) < 0.2 then
		return cached.v
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = Bridge.getLocalIgnoreList()
	params.IgnoreWater = true
	local out, seen = {}, {}
	local cursor, travelled, dirU = origin, 0, dir.Unit
	for _ = 1, maxParts + 2 do
		local rem = dist - travelled
		if rem <= 0.05 then break end
		local hit = Workspace:Raycast(cursor, dirU * rem, params)
		if not hit then break end
		local inst = hit.Instance
		if targetPart and (inst == targetPart or (model and inst:IsDescendantOf(model))) then
			break
		end
		if not seen[inst] and not Bridge.isRaycastNoisePart(inst)
			and not Bridge.isBulletPenetrableInstance(inst, Bridge.weaponCanBreach()) then
			seen[inst] = true
			out[#out + 1] = inst
			params:AddToFilter(inst)
		end
		local seg = (hit.Position - cursor).Magnitude
		travelled += math.max(seg, 0.01)
		cursor = hit.Position + dirU * 0.04
	end
	State.wallBangIgnoreCache[key] = { t = now, v = out }
	return out
end

function Bridge.applyWallBangIgnore(ignore, origin, aimPoint, targetPart)
	if CONFIG.WallBangTest ~= true then return ignore end
	local blocks = Bridge.collectWallBangIgnore(origin, aimPoint, targetPart, 6)
	if #blocks == 0 then return ignore end
	return Bridge.mergeBulletIgnore(ignore, blocks)
end

function Bridge.applyWallBangBulletPayload(payload)
	if type(payload) ~= "table" then return payload end
	if not Bridge.isLocalBulletFlag(payload.Local) and not Bridge.isRecentCombatShot() then
		return payload
	end
	local aimPt = Bridge.getLockedShotAimPoint() or State.aimAimPoint or State.forceHitPoint
	local target = State.shotAimTarget or State.aimTargetPart
	local origin = typeof(payload.OriginCFrame) == "CFrame" and payload.OriginCFrame.Position or nil
	if typeof(origin) == "Vector3" and typeof(aimPt) == "Vector3" and target and target.Parent then
		payload.Ignore = Bridge.applyCombatBulletIgnore(payload.Ignore, origin, aimPt, target)
	else
		payload.Ignore = Bridge.applyTeammateBulletIgnore(payload.Ignore)
	end
	return payload
end

function Bridge.resolveBulletEventIsLocal(isLocal)
	if isLocal == true then return true end
	return false
end

function Bridge.isCombatActorPart(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end
	if part.Name == "Terrain" then return false end
	if part:GetAttribute("ActorUID") then return true end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then return false end
	return model:FindFirstChild("Head") ~= nil or model:FindFirstChild("UpperTorso") ~= nil
end

function Bridge.isRaycastNoisePart(inst)
	if typeof(inst) ~= "Instance" or not inst:IsA("BasePart") then
		return true
	end
	if not inst.CanCollide and not inst.CanQuery then return true end
	local eff = inst.Transparency + (inst.LocalTransparencyModifier or 0)
	if eff >= 0.92 then return true end
	if not inst.CanCollide and eff >= 0.5 then return true end
	local sz = inst.Size
	if math.min(sz.X, sz.Y, sz.Z) < 0.04 and inst.CanCollide == false then
		return true
	end
	if inst:IsA("Trail") or inst:IsA("ParticleEmitter") then return true end
	local parent = inst.Parent
	if parent and (parent:IsA("Accessory") or parent:IsA("Tool")) then
		return true
	end
	local lname = string.lower(inst.Name)
	if string.find(lname, "hitbox") or string.find(lname, "collision")
		or string.find(lname, "blocker") or string.find(lname, "invisible") then
		if eff >= 0.35 then return true end
	end
	return false
end

local COMBAT_LOS_BONE_NAMES = {
	Head = true, UpperTorso = true, LowerTorso = true,
	LeftUpperArm = true, RightUpperArm = true,
	LeftLowerArm = true, RightLowerArm = true,
	LeftHand = true, RightHand = true,
}

function Bridge.isCombatLosBone(inst)
	return typeof(inst) == "Instance" and inst:IsA("BasePart") and COMBAT_LOS_BONE_NAMES[inst.Name] == true
end

function Bridge.isLosTargetPart(hitInst, targetPart, model)
	if typeof(hitInst) ~= "Instance" then return false end
	if targetPart and hitInst == targetPart then return true end
	if model and hitInst:IsDescendantOf(model) then
		if Bridge.isCombatLosBone(hitInst) then return true end
		if hitInst:GetAttribute("ActorUID") then return true end
		return false
	end
	return false
end

function Bridge.shouldPierceLosInstance(inst, canBreachWeapon, targetModel)
	if Bridge.isRaycastNoisePart(inst) then return true end
	if Bridge.isVisiblePassThroughInstance(inst, canBreachWeapon) then return true end
	if targetModel and typeof(inst) == "Instance" and inst:IsDescendantOf(targetModel) then
		if not Bridge.isCombatLosBone(inst) then
			local eff = inst.Transparency + (inst.LocalTransparencyModifier or 0)
			if eff >= 0.45 or inst.CanCollide == false then return true end
		end
	end
	return false
end

function Bridge.isBulletPenetrableInstance(inst, canBreachWeapon)
	if typeof(inst) ~= "Instance" then return false end
	if inst:HasTag("Prefab") then
		local prefab = inst:GetAttribute("Prefab")
		if prefab == "Glass" then return true end
		if prefab == "Door" or prefab == "BunkerDoor" or prefab == "ServerDoor" then
			return canBreachWeapon == true or inst:GetAttribute("CanBreach") == true
		end
		if prefab == "Grate" or prefab == "Wire" then return true end
	end
	if inst:GetAttribute("CanBreach") == true then return true end
	if inst:GetAttribute("MagBulletPenetrates") == true then return true end
	if inst:GetAttribute("Penetratable") == true then return true end
	if inst:GetAttribute("Penetrable") == true then return true end
	if inst:GetAttribute("BulletPassThrough") == true then return true end
	if inst:GetAttribute("BulletPenetrates") == true then return true end
	if inst:IsA("BasePart") then
		local mat = inst.Material
		if mat == Enum.Material.Glass then return true end
	end
	return false
end

function Bridge.isVisiblePassThroughInstance(inst, canBreachWeapon)
	if Bridge.isBulletPenetrableInstance(inst, canBreachWeapon) then return true end
	if typeof(inst) ~= "Instance" then return false end
	if inst:HasTag("Prefab") then
		local prefab = inst:GetAttribute("Prefab")
		if prefab == "Ladder" or prefab == "Stair" or prefab == "Stairs"
			or prefab == "Railing" or prefab == "Supported20Metal"
			or prefab == "Tarp" or prefab == "Net" or prefab == "Cloth" then
			return true
		end
	end
	local meta = inst:GetAttribute("MetaMaterial")
	if type(meta) == "string" then
		local ml = string.lower(meta)
		if string.find(ml, "ladder") or string.find(ml, "stair") or string.find(ml, "railing")
			or string.find(ml, "glass") or string.find(ml, "window") then
			return true
		end
	end
	local lname = string.lower(inst.Name)
	if string.find(lname, "ladder") or string.find(lname, "stair")
		or string.find(lname, "railing") or string.find(lname, "rung")
		or string.find(lname, "handrail") or string.find(lname, "banister")
		or string.find(lname, "climb") or string.find(lname, "window")
		or string.find(lname, "glass") or string.find(lname, "pane")
		or string.find(lname, "fence") or string.find(lname, "grate")
		or string.find(lname, "chain") or string.find(lname, "bars")
		or string.find(lname, "wire") or string.find(lname, "net")
		or string.find(lname, "curtain") or string.find(lname, "tarp") then
		return true
	end
	if inst:IsA("BasePart") then
		local mat = inst.Material
		if mat == Enum.Material.Glass or mat == Enum.Material.Neon
			or mat == Enum.Material.ForceField then
			return true
		end
		local sz = inst.Size
		local minSz = math.min(sz.X, sz.Y, sz.Z)
		if minSz <= 0.35 and inst.CanCollide then
			return true
		end
		if inst.Transparency >= 0.35 then
			if minSz < 1.5 then return true end
		end
		if mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks then
			if string.find(lname, "ladder") or string.find(lname, "stair")
				or string.find(lname, "step") or string.find(lname, "rung") then
				return true
			end
		end
	end
	return false
end

function Bridge.isLosPassThroughInstance(inst, canBreachWeapon)
	return Bridge.isVisiblePassThroughInstance(inst, canBreachWeapon)
end

function Bridge.isPierceableInstance(inst, canBreachWeapon)
	return Bridge.isLosPassThroughInstance(inst, canBreachWeapon)
end

-- v17: собираем список пробиваемых объектов рядом с актором для ESP
-- чтобы исключить их из LOS raycast (куст/забор/стекло рядом с врагом)
function Bridge.buildPierceIgnoreListNearPoint(worldPos, radius)
	if not worldPos then return {} end
	radius = radius or 3.5
	local key = string.format("%.0f|%.0f|%.0f", worldPos.X, worldPos.Y, worldPos.Z)
	local now = os.clock()
	if not State.pierceListCache then State.pierceListCache = {} end
	local cached = State.pierceListCache[key]
	if cached and now - cached.t < 1.0 then return cached.v end
	local out = {}
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = Bridge.getLocalIgnoreList()
	local parts = Workspace:GetPartBoundsInBox(
		CFrame.new(worldPos),
		Vector3.new(radius*2, radius*2, radius*2),
		op
	)
	for _, p in ipairs(parts) do
		if #out >= 24 then break end
		if Bridge.isRaycastNoisePart(p) then continue end
		if Bridge.isVisiblePassThroughInstance(p, false) then out[#out+1] = p end
	end
	State.pierceListCache[key] = { t = now, v = out }
	return out
end

function Bridge.buildLosRayParams()
	local ignore = Bridge.getLocalIgnoreList()
	if not State.losRayParams then
		State.losRayParams = RaycastParams.new()
		State.losRayParams.FilterType = Enum.RaycastFilterType.Exclude
		State.losRayParams.IgnoreWater = true
	end
	State.losRayParams.FilterDescendantsInstances = ignore
	return State.losRayParams
end

-- v17: LOS params с пробиваемыми объектами исключёнными (для visible check у забора/куста)
function Bridge.buildLosRayParamsPierce(targetWorldPos)
	local ignore = Bridge.getLocalIgnoreList()
	local pierce = targetWorldPos and Bridge.buildPierceIgnoreListNearPoint(targetWorldPos, 4.0) or {}
	local combined = {}
	for _, v in ipairs(ignore) do combined[#combined+1] = v end
	for _, v in ipairs(pierce) do combined[#combined+1] = v end
	if not State.losPierceRayParams then
		State.losPierceRayParams = RaycastParams.new()
		State.losPierceRayParams.FilterType = Enum.RaycastFilterType.Exclude
		State.losPierceRayParams.IgnoreWater = true
	end
	State.losPierceRayParams.FilterDescendantsInstances = combined
	return State.losPierceRayParams
end

function Bridge.hasVisiblePath(origin, worldPos, targetPart, allowGapRays)
	return Bridge.hasClearShotToPoint(origin, worldPos, targetPart, allowGapRays == true)
end

function Bridge.losFromView(origin, worldPos, targetPart, allowGapRays)
	return Bridge.hasClearShotToPoint(origin, worldPos, targetPart, allowGapRays == true)
end

function Bridge.quickLosVisible(origin, worldPos, targetPart)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	return Bridge.hasClearShotToPoint(origin, worldPos, targetPart)
end

function Bridge.raycastWithPierce(origin, direction, maxDist, targetModel, targetPart, canBreachWeapon, pierceFn)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return false
	end
	canBreachWeapon = canBreachWeapon == true or Bridge.weaponCanBreach()
	if not pierceFn then
		pierceFn = function(inst, breach)
			return Bridge.shouldPierceLosInstance(inst, breach, targetModel)
		end
	end
	local dist = direction.Magnitude
	if dist < 0.05 then return true end
	local dirUnit = direction.Unit
	if not State.pierceRayParams then
		State.pierceRayParams = RaycastParams.new()
		State.pierceRayParams.FilterType = Enum.RaycastFilterType.Exclude
		State.pierceRayParams.IgnoreWater = true
	end
	local params = State.pierceRayParams
	local filterList = {}
	local baseIgnore = Bridge.getLocalIgnoreList()
	for _, v in ipairs(baseIgnore) do
		filterList[#filterList + 1] = v
	end
	params.FilterDescendantsInstances = filterList
	local travelled = 0
	local cursor = origin
	for _ = 1, (CONFIG.LosPierceMaxSteps or 12) do
		params.FilterDescendantsInstances = filterList
		local remaining = maxDist - travelled
		if remaining <= 0.05 then return true end
		local hit = Workspace:Raycast(cursor, dirUnit * remaining, params)
		if not hit then return true end
		local inst = hit.Instance
		if targetPart and Bridge.isLosTargetPart(inst, targetPart, targetModel) then
			return true
		end
		if pierceFn(inst, canBreachWeapon) then
			local seg = (hit.Position - cursor).Magnitude
			travelled += math.max(seg, 0.01)
			cursor = hit.Position + dirUnit * 0.04
			filterList[#filterList + 1] = inst
			continue
		end
		return false
	end
	return false
end

function Bridge.hasClearShotToPoint(origin, worldPos, targetPart, allowGapRays)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	local function testLos(fromPos)
		local dir = worldPos - fromPos
		local dist = dir.Magnitude
		if dist < 0.05 then return true end
		local model = targetPart and targetPart.Parent
		local canBreach = Bridge.weaponCanBreach()
		local losP = Bridge.buildLosRayParams()
		local hitFast = Workspace:Raycast(fromPos, dir, losP)
		local result
		if not hitFast then
			result = true
		elseif targetPart and Bridge.isLosTargetPart(hitFast.Instance, targetPart, model) then
			result = true
		elseif Bridge.shouldPierceLosInstance(hitFast.Instance, canBreach, model) then
			result = nil
		else
			result = false
		end
		if result == nil then
			result = Bridge.raycastWithPierce(fromPos, dir, dist, model, targetPart, canBreach, nil)
		end
		if not result and targetPart and hitFast
			and Bridge.shouldPierceLosInstance(hitFast.Instance, canBreach, model) then
			local pierceParams = Bridge.buildLosRayParamsPierce(worldPos)
			local hit2 = Workspace:Raycast(fromPos, dir, pierceParams)
			if not hit2 then
				result = true
			elseif Bridge.isLosTargetPart(hit2.Instance, targetPart, model) then
				result = true
			end
		end
		return result == true
	end

	local now = os.clock()
	local ttl = CONFIG.LosRaycastCacheSec or 0.10
	local tid = targetPart and (targetPart:GetAttribute("ActorUID") or targetPart.Name) or ""
	local key = math.floor(origin.X * 4) .. "|"
		.. math.floor(origin.Y * 4) .. "|"
		.. math.floor(origin.Z * 4) .. "|"
		.. math.floor(worldPos.X * 4) .. "|"
		.. math.floor(worldPos.Y * 4) .. "|"
		.. math.floor(worldPos.Z * 4) .. "|"
		.. tid
	local cached = State.losRaycastCache[key]
	if cached and now - (cached.t or 0) < ttl then
		return cached.v == true
	end

	local result = testLos(origin)
	if not result and allowGapRays then
		for _, off in ipairs({ 0.22, -0.22 }) do
			if testLos(origin + Vector3.new(0, off, 0)) then
				result = true
				break
			end
		end
	end
	State.losRaycastCache[key] = { t = now, v = result }
	if State.losRaycastCache then
		local n = 0
		for _ in pairs(State.losRaycastCache) do
			n += 1
			if n > 400 then
				State.losRaycastCache = { [key] = State.losRaycastCache[key] }
				break
			end
		end
	end
	return result
end

function Bridge.rayPassesPart(origin, aimPoint, part, tolerance)
	if typeof(origin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" or not part then
		return false
	end
	tolerance = tolerance or (part.Size.Magnitude * 0.35 + 0.25)
	local dir = aimPoint - origin
	local dist = dir.Magnitude
	if dist < 0.05 then return false end
	local u = dir.Unit
	local rel = part.Position - origin
	local t = math.clamp(u:Dot(rel), 0, dist)
	local closest = origin + u * t
	return (closest - part.Position).Magnitude <= tolerance
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MultiPoint: выдвигаем muzzle к краю стены чтобы пуля прошла к врагу.
-- Теория: пуля регистрируется только если muzzle не перекрыт геометрией.
-- resolveSpoofedMuzzleOrigin уже ищет такую позицию (сдвиг вправо/влево/вперёд).
-- patchV138ServerAim патчит X,Y,Z,pitch,yaw в v138 перед отправкой на сервер.
-- Нам нужно только ПРАВИЛЬНО находить цель и не отфильтровывать её раньше времени.
-- ─────────────────────────────────────────────────────────────────────────────

-- isValidMultiPointShot: проверяет, достижима ли цель после spoofed muzzle.
-- Не отфильтровывает если spoof нашёл позицию — это работа patchV138ServerAim.
function Bridge.isValidMultiPointShot(origin, aimPoint, targetPart, model)
	if typeof(origin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return false
	end
	if CONFIG.LiteMultiPoint then
		local _, _, _, ok = Bridge.findLiteMultiPointShot(origin, aimPoint, targetPart, nil)
		return ok == true
	end
	-- Legit без RequireLos — тоже принимаем все
	if not CONFIG.MultiPointRequireLos then
		return true
	end
	-- Legit с RequireLos: проверяем через spoofed muzzle
	local spoofOrigin = Bridge.resolveSpoofedMuzzleOrigin(origin, aimPoint, targetPart)
	if Bridge.hasClearShotToPoint(spoofOrigin, aimPoint, targetPart) then
		return true
	end
	if Bridge.hasClearShotToPoint(spoofOrigin, aimPoint, nil) then
		local head = model and model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return Bridge.rayPassesPart(spoofOrigin, aimPoint, head, head.Size.Magnitude * 0.55 + 0.15)
		end
		if targetPart then
			return Bridge.rayPassesPart(spoofOrigin, aimPoint, targetPart, targetPart.Size.Magnitude * 0.45 + 0.2)
		end
		return true
	end
	return false
end

-- Resolver: inset-сэмплы на грани хитбокса, обращённой к стрелку
local _EXPOSE_BONUS = { Head = 12, UpperTorso = 6, LowerTorso = 3 }

-- Только голова + туловище; порядок = приоритет (ранний выход)
local CORE_LOS_BONES = { "Head", "UpperTorso", "LowerTorso" }

-- ≤2 сэмпла на кость: центр + front-facing edge (оптимизация ESP/SA)
function Bridge.getCoreLosSamples(bone, origin)
	if not bone or not bone:IsA("BasePart") then return {} end
	local cf, sz = bone.CFrame, bone.Size * 0.5
	local center = cf.Position
	local toObs = origin - center
	if toObs.Magnitude < 0.05 then
		return { center }
	end
	local localDir = cf:VectorToObjectSpace(toObs.Unit)
	local ax, ay, az = math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z)
	local rel
	if ax >= ay and ax >= az then
		rel = Vector3.new((localDir.X >= 0 and 1 or -1) * sz.X * 0.72, 0, 0)
	elseif ay >= az then
		rel = Vector3.new(0, (localDir.Y >= 0 and 1 or -1) * sz.Y * 0.72, 0)
	else
		rel = Vector3.new(0, 0, (localDir.Z >= 0 and 1 or -1) * sz.Z * 0.72)
	end
	return { center, cf:PointToWorldSpace(rel) }
end

function Bridge.getBoneLosSamples(bone, origin)
	if not bone or not bone:IsA("BasePart") then return {} end
	local cf, sz = bone.CFrame, bone.Size * 0.5
	local center = cf.Position
	local toObs = origin - center
	if toObs.Magnitude < 0.05 then
		return { center }
	end
	local localDir = cf:VectorToObjectSpace(toObs.Unit)
	local ax, ay, az = math.abs(localDir.X), math.abs(localDir.Y), math.abs(localDir.Z)
	local rel
	if ax >= ay and ax >= az then
		rel = Vector3.new((localDir.X >= 0 and 1 or -1) * sz.X * 0.82, 0, 0)
	elseif ay >= az then
		rel = Vector3.new(0, (localDir.Y >= 0 and 1 or -1) * sz.Y * 0.82, 0)
	else
		rel = Vector3.new(0, 0, (localDir.Z >= 0 and 1 or -1) * sz.Z * 0.82)
	end
	local points = { center, cf:PointToWorldSpace(rel) }
	-- Lean peek: lateral edges catch offset head/torso
	local lateral = math.min(sz.X, sz.Z) * 0.78
	if lateral > 0.04 then
		points[#points + 1] = center + cf.RightVector * lateral
		points[#points + 1] = center - cf.RightVector * lateral
	end
	return points
end

-- Строгая проверка видимости: Head → UpperTorso → LowerTorso, ≤2 луча на ко��ть, early exit
function Bridge.checkCoreBodyVisible(model, origin, losFn)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or typeof(origin) ~= "Vector3" then
		return false, nil, nil
	end
	losFn = losFn or function(o, wp, bone)
		return Bridge.hasClearShotToPoint(o, wp, bone, false)
	end
	for _, boneName in ipairs(CORE_LOS_BONES) do
		local bone = model:FindFirstChild(boneName)
		if not bone or not bone:IsA("BasePart") then continue end
		for _, wp in ipairs(Bridge.getCoreLosSamples(bone, origin)) do
			if losFn(origin, wp, bone) then
				return true, bone, wp
			end
		end
	end
	return false, nil, nil
end

function Bridge.fastEspActorVisible(model, origin)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or typeof(origin) ~= "Vector3" then
		return false
	end
	local part = model:FindFirstChild("Head")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
	if not part or not part:IsA("BasePart") then return false end
	return Bridge.espStrictLosPoint(origin, part.Position, part) == true
end

function Bridge.isActorVisible(model, uid, intervalOverride)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false
	end
	Bridge.perfCount("visibleCheck")
	local origin = Bridge.getLocalViewOrigin()
	if not origin then return false end
	uid = uid or model:GetAttribute("ActorUID") or ""
	local now = os.clock()
	local interval = intervalOverride or CONFIG.EspVisibleInterval or 0.22
	State.espVisibleCache = State.espVisibleCache or {}
	local cached = State.espVisibleCache[uid]
	if uid ~= "" and cached and now - (cached.t or 0) < interval then
		Bridge.perfCount("visibleCacheHit")
		return cached.v == true
	end
	local visible = false
	local actorData = uid ~= "" and State.actors and State.actors[uid]
	local isNpc = actorData and Bridge.isNpcActorClass(actorData.class)
	if isNpc and CONFIG.EspVisibleCheckNpc == false then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			visible = Bridge.espLosPoint(origin, head.Position, head) == true
		else
			visible = true
		end
	elseif CONFIG.EspVisibleFast ~= false then
		visible = Bridge.fastEspActorVisible(model, origin) == true
	else
		local losFn = function(o, wp, bone)
			return Bridge.espLosPoint(o, wp, bone)
		end
		visible = Bridge.checkCoreBodyVisible(model, origin, losFn) == true
	end
	if uid ~= "" then
		State.espVisibleCache[uid] = { v = visible == true, t = now }
	end
	return visible == true
end

function Bridge.sampleBoneInsetPoints(bone, origin)
	if not bone or not bone:IsA("BasePart") then return {} end
	local cf, sz = bone.CFrame, bone.Size * 0.5
	local toBone = cf.Position - origin
	if toBone.Magnitude < 0.05 then
		return { cf.Position }
	end
	local localLook = cf:VectorToObjectSpace(toBone.Unit)
	local ax, ay, az = math.abs(localLook.X), math.abs(localLook.Y), math.abs(localLook.Z)
	local points = {}
	local grid = { -0.35, 0, 0.35, 0.88 }
	for _, gu in ipairs(grid) do
		for _, gv in ipairs(grid) do
			local rel
			if ax >= ay and ax >= az then
				local sx = localLook.X >= 0 and 1 or -1
				rel = Vector3.new(sx * gu * sz.X, gv * sz.Y, gv * sz.Z * 0.45)
			elseif ay >= az then
				local sy = localLook.Y >= 0 and 1 or -1
				rel = Vector3.new(gv * sz.X, sy * gu * sz.Y, gv * sz.Z * 0.45)
			else
				local szs = localLook.Z >= 0 and 1 or -1
				rel = Vector3.new(gv * sz.X * 0.45, gv * sz.Y, szs * gu * sz.Z)
			end
			points[#points + 1] = cf:PointToWorldSpace(rel)
		end
	end
	points[#points + 1] = cf.Position
	return points
end

-- ESP LOS: solid geometry blocks; no bullet-pierce pass-through
function Bridge.espStrictLosPoint(origin, worldPos, targetPart)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	local dir = worldPos - origin
	local dist = dir.Magnitude
	if dist < 0.05 then return true end
	local params = Bridge.buildLosRayParams()
	Bridge.perfCount("espRay")
	local hit = Workspace:Raycast(origin, dir, params)
	if not hit then return true end
	local model = targetPart and targetPart.Parent
	if targetPart and Bridge.isLosTargetPart(hit.Instance, targetPart, model) then
		return true
	end
	return false
end

-- Legacy pierce LOS (SA aim); ESP uses espStrictLosPoint
function Bridge.espLosPoint(origin, worldPos, targetPart)
	if CONFIG.EspVisibleStrict ~= false then
		return Bridge.espStrictLosPoint(origin, worldPos, targetPart)
	end
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	local dir = worldPos - origin
	local dist = dir.Magnitude
	if dist < 0.05 then return true end
	local model = targetPart and targetPart.Parent
	Bridge.perfCount("espRay")
	return Bridge.raycastWithPierce(origin, dir, dist, model, targetPart, false, function(inst)
		return Bridge.isBulletPenetrableInstance(inst, false)
	end)
end

-- Быстрый LOS: один raycast, без pierce-цепочки (для lite resolver / SA aim)
function Bridge.fastLosPoint(origin, worldPos, targetPart)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	local dir = worldPos - origin
	if dir.Magnitude < 0.05 then return true end
	local hit = Workspace:Raycast(origin, dir, Bridge.buildLosRayParams())
	if not hit then return true end
	if targetPart then
		if hit.Instance == targetPart then return true end
		local model = targetPart.Parent
		if model and hit.Instance:IsDescendantOf(model) then return true end
	end
	return Bridge.isVisiblePassThroughInstance(hit.Instance, false)
end

-- Строгий LOS для ESP: пробиваемые препятствия считаются блоком (игра пробивает толь��о Glass)
function Bridge.fastLosPointStrict(origin, worldPos, targetPart)
	return Bridge.hasClearShotToPoint(origin, worldPos, targetPart)
end

-- ResolverLite: partial expose от muzzle + inset (Aim / Muzzle)
local RESOLVER_LITE_BONES = { "Head", "UpperTorso" }

local function resolverLiteLos(muzzleOrigin, worldPos, bone)
	return Bridge.hasClearShotToPoint(muzzleOrigin, worldPos, bone, false)
end

function Bridge.applyResolverLiteInset(bone, exposedPoint, muzzleOrigin)
	if not bone or not bone:IsA("BasePart") or typeof(exposedPoint) ~= "Vector3" then
		return exposedPoint
	end
	local inset = CONFIG.ResolverLiteInset or 0.08
	if inset <= 0 then return exposedPoint end
	local center = bone.CFrame.Position
	local dir = center - exposedPoint
	if dir.Magnitude < 0.04 then return exposedPoint end
	return exposedPoint + dir.Unit * math.min(inset, dir.Magnitude * 0.35)
end

function Bridge.computeResolverLiteMuzzle(muzzleOrigin, aimPoint, insetPoint, bone, uid)
	if typeof(muzzleOrigin) ~= "Vector3" or typeof(insetPoint) ~= "Vector3" or not bone then
		return nil
	end
	if Bridge.hasSaDirectPath(muzzleOrigin, insetPoint, bone) then
		return muzzleOrigin
	end
	local spoof, _, _, ok = Bridge.findLiteMultiPointShot(muzzleOrigin, insetPoint, bone, uid)
	if ok and typeof(spoof) == "Vector3" then
		return spoof
	end
	if typeof(aimPoint) == "Vector3" then
		spoof, _, _, ok = Bridge.findLiteMultiPointShot(muzzleOrigin, aimPoint, bone, uid)
		if ok and typeof(spoof) == "Vector3" then
			return spoof
		end
	end
	return nil
end

-- v22: per-window raycast budget для тяжёлых резолверов (плоский FPS при N игроках).
-- Текущая цель прицела никогда не голодает; прочие акторы резолвятся round-robin
-- по кадрам — при исчерпании бюдж��та возвращается последний кэш вместо raycast.
function Bridge.resolverBudgetAllow(uid)
	if uid ~= nil and State.aimTargetUid ~= nil and uid == State.aimTargetUid then
		return true
	end
	local now = os.clock()
	local window = CONFIG.ResolverBudgetWindow or (1 / 60)
	if now - (State.resolverBudgetT or 0) >= window then
		State.resolverBudgetT = now
		State.resolverBudgetLeft = CONFIG.ResolverBudgetPerFrame or 4
	end
	if (State.resolverBudgetLeft or 0) <= 0 then return false end
	State.resolverBudgetLeft = State.resolverBudgetLeft - 1
	return true
end

function Bridge.resolveResolverLite(muzzleOrigin, model, uid, cam, maxAngle)
	if CONFIG.ResolverLite == false then return nil, nil, nil end
	if typeof(muzzleOrigin) ~= "Vector3" or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, nil, nil
	end
	-- FIX v10: resolver не делает LoS-check для дальних акторов (>600 studs)
	local rlHead = model:FindFirstChild("Head")
	local rlDist
	if rlHead and typeof(muzzleOrigin) == "Vector3" then
		rlDist = (rlHead.Position - muzzleOrigin).Magnitude
		if rlDist > (CONFIG.ResolverLiteMaxDist or 600) then return nil, nil, nil end
	end
	cam = cam or getCamera()
	maxAngle = maxAngle or CONFIG.SilentAimFOV or 15
	local cacheKey = Bridge.exposedCacheKey(uid, model)
	local now = os.clock()
	-- v22: дистанционный троттлинг — дальние акторы пересканируются реже
	local interval = CONFIG.ResolverScanInterval or 0.18
	if rlDist then
		interval = interval * (1 + rlDist / (CONFIG.ResolverDistScale or 140))
	end
	State.exposedCacheByUid = State.exposedCacheByUid or {}
	State.resolverThrottle = State.resolverThrottle or {}
	if State.resolverThrottle[cacheKey] and now - State.resolverThrottle[cacheKey] < interval then
		local ec = State.exposedCacheByUid[cacheKey]
		if ec and ec.part and ec.part.Parent
			and typeof(ec.muzzle) == "Vector3" and (ec.muzzle - muzzleOrigin).Magnitude < 0.85 then
			return ec.part, ec.point, ec.spoof
		end
	end
	-- v22: бюджет raycast — при исчерпании отдаём последний кэш (throttle НЕ сдвигаем,
	-- чтобы актор переехал на следующий кадр, а не завис на interval).
	if not Bridge.resolverBudgetAllow(uid) then
		local ec = State.exposedCacheByUid[cacheKey]
		if ec and ec.part and ec.part.Parent then
			return ec.part, ec.point, ec.spoof
		end
		return nil, nil, nil
	end
	State.resolverThrottle[cacheKey] = now
	local mode = string.lower(tostring(CONFIG.ResolverLiteMode or "Aim"))
	local useMuzzleMode = mode == "muzzle"
	for _, boneName in ipairs(RESOLVER_LITE_BONES) do
		local bone = model:FindFirstChild(boneName)
		if not bone or not bone:IsA("BasePart") then continue end
		local center = bone.CFrame.Position
		-- v22: дешёвый FOV-cull по центру ДО getCoreLosSamples (экономит расчёт сэмплов)
		if cam and Bridge.angleFromCameraLook(cam, center) > maxAngle * 1.25 then continue end
		local samples = Bridge.getCoreLosSamples(bone, muzzleOrigin)
		local edge = samples[2]
		local fovPt = edge or center
		if cam and Bridge.angleFromCameraLook(cam, fovPt) > maxAngle * 1.08 then continue end
		local centerOk = resolverLiteLos(muzzleOrigin, center, bone)
		local exposedPt, partial = nil, false
		if centerOk then
			exposedPt = center
		elseif edge and resolverLiteLos(muzzleOrigin, edge, bone) then
			exposedPt = edge
			partial = true
		else
			continue
		end
		local aimPt = center
		local spoof = nil
		if useMuzzleMode then
			if partial or not centerOk then
				spoof = Bridge.computeResolverLiteMuzzle(muzzleOrigin, center, exposedPt, bone, uid)
				if not spoof then continue end
			end
		elseif partial then
			aimPt = Bridge.applyResolverLiteInset(bone, exposedPt, muzzleOrigin)
		end
		State.exposedCacheByUid[cacheKey] = {
			part = bone,
			point = aimPt,
			spoof = spoof,
			muzzle = muzzleOrigin,
			t = now,
		}
		return bone, aimPt, spoof
	end
	return nil, nil, nil
end

function Bridge.findExposedPointLite(model, uid, muzzleOrigin, cam, maxAngle)
	local part, point = Bridge.resolveResolverLite(muzzleOrigin, model, uid, cam, maxAngle)
	return part, point
end

function Bridge.getAimLosOrigin(originHint)
	if typeof(originHint) == "Vector3" then
		return originHint
	end
	if type(Bridge.getLocalMuzzleCFrame) == "function" then
		local cf = Bridge.getLocalMuzzleCFrame()
		if typeof(cf) == "CFrame" then
			return cf.Position
		end
	end
	return Bridge.getAimOrigin(originHint)
end

function Bridge.findExposedPoint(model, uid, origin, cam, maxAngle, _)
	return Bridge.findExposedPointLite(model, uid, origin, cam, maxAngle)
end

-- SA LOS: pierceable пропускаем, solid блокирует (без pierce-near-target хака из hasClearShotToPoint)
function Bridge.hasSaDirectPath(origin, worldPos, targetPart)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then
		return false
	end
	local dir = worldPos - origin
	local dist = dir.Magnitude
	if dist < 0.05 then return true end
	local model = targetPart and targetPart.Parent
	return Bridge.raycastWithPierce(
		origin, dir, dist, model, targetPart, Bridge.weaponCanBreach(), Bridge.isBulletPenetrableInstance
	)
end

function Bridge.isEnemyHitPart(part)
	if not Bridge.isCombatActorPart(part) then return false end
	local uid = part:GetAttribute("ActorUID")
	-- FIX v4: ActorUID числовой у NPC — нормализуем
	if uid ~= nil then uid = tostring(uid) end
	if type(uid) ~= "string" or uid == "" then return false end
	if State.localActorUID and uid == State.localActorUID then return false end
	local lp = LP and LP.Character
	local model = part:FindFirstAncestorOfClass("Model")
	if lp and model and model == lp then return false end
	local data = State.actors and State.actors[uid]
	if data then
		if Bridge.isTeammateActor(data) then return false end
		return Bridge.isEnemyActor(data)
	end
	local repData = Bridge.getReplicatorActorData(uid)
	if type(repData) == "table" then
		-- FIX v4: для NPC (Owner=nil) определяем класс через TargetGroup
		local owner = rawget(repData, "Owner") or tableField(repData, "Owner")
		local isNpc = (owner == nil)
		local npcClass = "player"
		if isNpc then
			if rawget(repData, "Zombie") == true then
				npcClass = "npc_zombie"
			else
				-- TargetGroup с модели — ищем через Character
				local char = rawget(repData, "Character")
				local tg = char and typeof(char) == "Instance" and char:GetAttribute("TargetGroup")
				if tg == 0 then npcClass = "npc_friendly"
				elseif tg == 2 then npcClass = "npc_zombie"
				else npcClass = "npc_hostile" end
			end
		end
		local pseudo = {
			uid = uid,
			actorData = repData,
			class = npcClass,
			label = tableField(repData, "OwnerName") or tableField(repData, "Name") or "npc",
		}
		if Bridge.isTeammateActor(pseudo) then return false end
		if Bridge.isEnemyActor(pseudo) then return true end
	end
	return false
end

function Bridge.findAnyVisibleBone(model, origin, cam, maxAngle)
	local viewOrigin = Bridge.getLocalViewOrigin() or origin
	local visible, bone, point = Bridge.checkCoreBodyVisible(model, viewOrigin, function(o, wp, b)
		return Bridge.hasClearShotToPoint(o, wp, b, false)
	end)
	if not visible or not bone then return nil, nil end
	if cam and point and Bridge.angleFromCameraLook(cam, point) > (maxAngle or CONFIG.SilentAimFOV or 15) * 1.15 then
		return nil, nil
	end
	return bone, point
end

function Bridge.detectCornerPeek(muzzleOrigin, cam, model, uid, maxAngle)
	return Bridge.resolveResolverLite(muzzleOrigin, model, uid, cam, maxAngle)
end

function Bridge.canHardWallbangTarget(_origin, _aimPoint, _targetPart)
	return false
end

local function mpBuildSteps(maxDist, stepMin)
	local out = {}
	for _, s in ipairs({ 1.0, 2.0, 3.5, 5.0, maxDist }) do
		if s <= maxDist + 0.01 then out[#out + 1] = s end
	end
	return out
end

local function mpOrderSearchDirs(dirs, wallNormal)
	if wallNormal.Magnitude < 0.05 then return dirs end
	local wn = wallNormal.Unit
	local scored = {}
	for i, dir in ipairs(dirs) do
		local score = i
		if dir.Magnitude > 0.01 and math.abs(dir.Unit.Y) < 0.35 then
			score -= math.abs(dir.Unit:Dot(wn)) * 12
		end
		scored[#scored + 1] = { dir = dir, score = score }
	end
	table.sort(scored, function(a, b) return a.score < b.score end)
	local out = {}
	for _, e in ipairs(scored) do
		out[#out + 1] = e.dir
	end
	return out
end

local function mpBuildDirs(wallNormal, muzzle, aimPoint)
	local up = Vector3.new(0, 1, 0)
	local peekH = wallNormal - Vector3.new(0, wallNormal.Y, 0)
	if peekH.Magnitude < 0.1 then
		local ta = aimPoint - muzzle
		peekH = Vector3.new(ta.X, 0, ta.Z)
	end
	if peekH.Magnitude < 0.01 then peekH = Vector3.new(1, 0, 0) end
	peekH = peekH.Unit
	local peekH2 = Vector3.new(-peekH.Z, 0, peekH.X)
	return {
		peekH, -peekH,
		peekH2, -peekH2,
		up, -up,
	}
end

function Bridge.mpShotCacheKey(realMuzzle, targetPart)
	local tid = targetPart and (targetPart:GetAttribute("ActorUID") or targetPart.Name) or "nil"
	return string.format(
		"%.1f|%.1f|%.1f|%s",
		realMuzzle.X, realMuzzle.Y, realMuzzle.Z, tid
	)
end

function Bridge.pruneMpSearchDirs(muzzle, aimPoint, dirs)
	if typeof(muzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return dirs
	end
	local out = {}
	local dy = aimPoint.Y - muzzle.Y
	local params = Bridge.buildLosRayParams()
	for _, dir in ipairs(dirs) do
		if dir.Magnitude < 0.01 then continue end
		local unit = dir.Unit
		local absY = math.abs(unit.Y)
		if dy > 1.2 and unit.Y < -0.35 then continue end
		if absY > 0.65 then
			local hit = Workspace:Raycast(muzzle + unit * 0.08, unit * 0.55, params)
			if hit and not Bridge.isBulletPenetrableInstance(hit.Instance, Bridge.weaponCanBreach()) then
				continue
			end
		end
		out[#out + 1] = dir
	end
	return #out > 0 and out or dirs
end

-- findMultiPointShot удалён — алиас на LiteMultiPoint
function Bridge.findMultiPointShot(realMuzzle, aimPoint, targetPart, uid)
	return Bridge.findLiteMultiPointShot(realMuzzle, aimPoint, targetPart, uid)
end

-- LiteMultiPoint: Head, L/R/Up от камеры, бинарный поиск дистанции (меньше raycast)
local LITE_MP_DIRS = nil

local function liteMpSearchDirs(cam)
	if LITE_MP_DIRS and LITE_MP_DIRS.cam == cam then
		return LITE_MP_DIRS.dirs
	end
	local right = cam and cam.CFrame.RightVector or Vector3.new(1, 0, 0)
	local up = cam and cam.CFrame.UpVector or Vector3.new(0, 1, 0)
	local dirs = { right, -right, up }
	LITE_MP_DIRS = { cam = cam, dirs = dirs }
	return dirs
end

local function liteMpBinaryPeek(origin, aimPoint, targetPart, dir, maxOff, steps)
	local lo, hi = 0.25, maxOff
	local best = nil
	for _ = 1, (steps or 3) do
		local mid = (lo + hi) * 0.5
		local cand = origin + dir * mid
		if Bridge.isMuzzleOriginValid(cand, origin)
			and Bridge.hasSaDirectPath(cand, aimPoint, targetPart) then
			best = cand
			hi = mid
		else
			lo = mid
		end
	end
	return best
end

function Bridge.findLiteMultiPointShot(realMuzzle, aimPoint, targetPart, uid)
	if typeof(realMuzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" or not targetPart then
		return nil, aimPoint, targetPart, false
	end
	local now = os.clock()
	local key = "lite|" .. Bridge.mpShotCacheKey(realMuzzle, targetPart)
	State.multiPointCache = State.multiPointCache or {}
	local cached = State.multiPointCache[key]
	-- v22: дистанционный троттлинг TTL — для дальних целей держим кэш дольше
	local cacheTtl = CONFIG.LiteMultiPointCacheSec or 0.55
	do
		local d = (targetPart.Position - realMuzzle).Magnitude
		cacheTtl = cacheTtl * (1 + d / (CONFIG.LiteMultiPointDistScale or 200))
	end
	if cached and now - (cached.t or 0) < cacheTtl then
		if cached.ok and Bridge.hasSaDirectPath(cached.spoof, aimPoint, targetPart) then
			return cached.spoof, aimPoint, targetPart, true
		elseif not cached.ok and now - (cached.t or 0) < 0.08 then
			return nil, nil, nil, false
		end
	end
	-- v22: бюджет raycast — при исчерпании не делаем дорогой поиск пиков,
	-- возвращаем кэш (даже подстаревший) либо nil (round-robin по кадрам).
	if not Bridge.resolverBudgetAllow(uid) then
		if cached and cached.ok and typeof(cached.spoof) == "Vector3" then
			return cached.spoof, aimPoint, targetPart, true
		end
		return nil, nil, nil, false
	end
	if Bridge.hasSaDirectPath(realMuzzle, aimPoint, targetPart) then
		State.multiPointCache[key] = { ok = true, spoof = realMuzzle, t = now }
		return realMuzzle, aimPoint, targetPart, true
	end
	local cam = getCamera()
	local maxOff = CONFIG.LiteMultiPointMaxDist or 6
	local steps = CONFIG.LiteMultiPointBinarySteps or 3
	for _, dir in ipairs(liteMpSearchDirs(cam)) do
		local best = liteMpBinaryPeek(realMuzzle, aimPoint, targetPart, dir, maxOff, steps)
		if best then
			State.multiPointCache[key] = { ok = true, spoof = best, t = now }
			return best, aimPoint, targetPart, true
		end
	end
	State.multiPointCache[key] = { ok = false, t = now }
	return nil, nil, nil, false
end

function Bridge.resolveLiteMultiPointAim(data, origin, _ctx, cam, maxAngle)
	if not data or not data.model or typeof(origin) ~= "Vector3" then
		return nil, nil, nil, nil
	end
	local model = data.model
	cam = cam or getCamera()
	maxAngle = maxAngle or CONFIG.SilentAimFOV or 15
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return nil, nil, nil, nil end
	local aimPt = head.Position
	-- FIX v10: LiteMultiPoint не делает raycast для дальних акторов (>600 studs)
	local lmpMaxDist = CONFIG.LiteMultiPointEngageDist or 600
	if typeof(origin) == "Vector3" and (aimPt - origin).Magnitude > lmpMaxDist then
		return nil, nil, nil, nil
	end
	if cam and Bridge.angleFromCameraLook(cam, aimPt) > maxAngle * 1.05 then
		return nil, nil, nil, nil
	end
	local spoof, _, _, ok = Bridge.findLiteMultiPointShot(origin, aimPt, head, data.uid)
	if ok and typeof(spoof) == "Vector3" then
		return head, aimPt, 3, spoof
	end
	return nil, nil, nil, nil
end

function Bridge.resolveMultiPointAim(data, origin, ctx, cam, maxAngle)
	return Bridge.resolveLiteMultiPointAim(data, origin, ctx, cam, maxAngle)
end

-- Приоритет цели (SA): 0=прямой LOS, 1=LiteMP, 2=ResolverLite, 3+=остальное
local TARGET_PRIORITY_WEIGHT = { [0] = 0, [1] = 750, [2] = 2100, [3] = 3800, [4] = 5200 }

function Bridge.classifyTargetShootPriority(data, cam, muzzleOrigin, maxAngle)
	local model = data and data.model
	if not model or not model:IsA("Model") or typeof(muzzleOrigin) ~= "Vector3" then
		return 99, nil, nil, nil
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return 99, nil, nil, nil end
	local function clearTo(part)
		if not part or not part:IsA("BasePart") then return false end
		if Bridge.hasSaDirectPath(muzzleOrigin, part.Position, part) then return true end
		return Bridge.hasClearShotToPoint(muzzleOrigin, part.Position, part, false)
	end
	if clearTo(head) then return 0, head, head.Position, nil end
	local torso = model:FindFirstChild("UpperTorso")
	if clearTo(torso) then return 0, torso, torso.Position, nil end
	if CONFIG.LiteMultiPoint then
		local spoof, _, _, ok = Bridge.findLiteMultiPointShot(muzzleOrigin, head.Position, head, data.uid)
		if ok and typeof(spoof) == "Vector3" then
			return 1, head, head.Position, spoof
		end
	end
	if CONFIG.ResolverLite ~= false then
		local expPart, expPoint, expSpoof = Bridge.resolveResolverLite(
			muzzleOrigin, model, data.uid, cam, maxAngle
		)
		if expPart and expPoint then
			return 2, expPart, expPoint, expSpoof
		end
	end
	return 3, head, head.Position, nil
end

-- Чистый расчёт точки (без записи в State)
function Bridge.computeCombatAimPoint(data, origin, ctx, cam, maxAngle)
	if not data or not data.model then return nil, nil, 3, nil end
	local model = data.model
	cam = cam or getCamera()
	maxAngle = maxAngle or CONFIG.SilentAimFOV or 15
	local muzzleOrigin = Bridge.getAimLosOrigin(origin)
	local viewOrigin = Bridge.getLocalViewOrigin() or muzzleOrigin
	local losFn = function(o, wp, bone)
		return Bridge.hasClearShotToPoint(o, wp, bone, false)
	end
	local head = Bridge.getHeadPart(model, nil)
	local aimPart = head
	if type(Bridge.getSilentAimPart) == "function" then
		aimPart = Bridge.getSilentAimPart(data) or head
	end
	if not aimPart or not aimPart.Parent then return nil, nil, 3, nil end

	-- FIX v7: InactiveWorld персонажи — part.Position = 0,0,0, используем adPos
	local function resolvePartPos(p)
		if data.inInactiveWorld and data.adPos and typeof(data.adPos) == "Vector3" then
			return data.adPos
		end
		return p.Position
	end
	local part, point, visTier, resolverSpoof = aimPart, resolvePartPos(aimPart), 3, nil
	if not data.inInactiveWorld and Bridge.hasVisiblePath(viewOrigin, aimPart.Position, aimPart, false) then
		part = aimPart
		point = part.Position
		visTier = 0
	elseif data.inInactiveWorld then
		-- InactiveWorld: нет прямого LOS через WorldToRay, принимаем как видимый если adPos есть
		if data.adPos and typeof(data.adPos) == "Vector3" then
			part = aimPart
			point = data.adPos
			visTier = 0
		end
	else
		local visOk, visBone, visPoint = Bridge.checkCoreBodyVisible(model, viewOrigin, losFn)
		if visOk and visBone and visPoint then
			part = visBone
			point = visPoint
			visTier = 0
		end
	end
	if visTier ~= 0 and CONFIG.ResolverLite ~= false then
		local expPart, expPoint, expSpoof = Bridge.resolveResolverLite(
			muzzleOrigin, model, data.uid, cam, maxAngle
		)
		if expPart and expPoint then
			part = expPart
			point = expPoint
			visTier = 1
			resolverSpoof = expSpoof
		else
			return nil, nil, 3, nil
		end
	elseif visTier ~= 0 then
		return nil, nil, 3, nil
	end
	return part, point, visTier, resolverSpoof
end

function Bridge.refreshAimTarget(originHint, force)
	if not CONFIG.SilentAim and not CONFIG.AimVisuals and not mpActive() then
		Bridge.clearAimTargetState(true)
		return nil
	end

	local now = os.clock()
	local interval = CONFIG.CombatAimRefreshInterval or 0.05
	if CONFIG.LiteMultiPoint then
		interval = math.max(interval, CONFIG.LiteMultiPointRefreshInterval or 0.08)
	end
	if not force and not Bridge.isRecentCombatShot() then
		interval = math.max(interval, CONFIG.AimTargetRefreshInterval or 0.08)
	end
	if not force and State.aimLockTime and now - State.aimLockTime < interval then
		if State.aimTargetPart and State.aimTargetPart.Parent and State.aimTargetUid then
			local locked = State.actors[State.aimTargetUid]
			if locked and locked.root and locked.root:IsA("BasePart") then
				updateActorVelocity(State.aimTargetUid, locked.root)
			end
			if not CONFIG.LiteMultiPoint or State.mpShotReady then
				return State.aimTargetPart
			end
		end
	end

	if CONFIG.TeamCheck then
		if now - (State.lastTeamRefresh or 0) > 1.0 then
			State.lastTeamRefresh = now
			Bridge.refreshLocalTeamKey()
		end
	end

	local cam = getCamera()
	if not cam then
		State.inAimRefresh = false
		Bridge.clearAimTargetState(false)
		return nil
	end

	State.inAimRefresh = true
	local losOrigin = Bridge.getAimLosOrigin(originHint)
	local maxAngle = CONFIG.SilentAimFOV or 15
	local maxDist = CONFIG.SilentAimMaxDistance or 500
	local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or Bridge.getLiveWeaponContext(false)

	local candidates = Bridge.collectAimActorCandidates(cam, losOrigin, maxDist, maxAngle)
	local best, bestScore = nil, math.huge

	for _, data in ipairs(candidates) do
		if data.uid and data.root and data.root:IsA("BasePart") then
			updateActorVelocity(data.uid, data.root)
		end
		local shootPriority, priPart, priPoint, priSpoof = Bridge.classifyTargetShootPriority(
			data, cam, losOrigin, maxAngle
		)
		if shootPriority >= 99 or not priPart then continue end

		local part, point, visTier, spoofOrigin
		if shootPriority == 1 and typeof(priSpoof) == "Vector3" then
			part, point, visTier, spoofOrigin = priPart, priPoint, 3, priSpoof
		elseif shootPriority == 2 and priPart and priPoint then
			part, point, visTier, spoofOrigin = priPart, priPoint, 1, priSpoof
		else
			part, point, visTier, spoofOrigin = Bridge.computeCombatAimPoint(
				data, losOrigin, ctx, cam, maxAngle
			)
			if not part then continue end
			if shootPriority == 0 then visTier = 0 end
		end
		if not part or not part.Parent or typeof(point) ~= "Vector3" then continue end

		local head = Bridge.getHeadPart(data.model, part) or part
		local aimPart = part
		local shotOrigin = Bridge.getAimLosOrigin(losOrigin)
		local aimPoint = Bridge.resolveServerAimPoint(aimPart, head, shotOrigin, ctx, data.uid, cam, maxAngle)
			or Bridge.resolveUnifiedAimPoint(head, shotOrigin, ctx, data.uid, aimPart, point)
			or point

		local angle = Bridge.angleFromCameraLook(cam, aimPoint)
		if angle > maxAngle then continue end

		if CONFIG.LiteMultiPoint and typeof(spoofOrigin) == "Vector3" then
			local reSpoof, _, _, reOk = Bridge.findLiteMultiPointShot(
				shotOrigin, aimPoint, aimPart, data.uid
			)
			if reOk and typeof(reSpoof) == "Vector3" then
				spoofOrigin = reSpoof
			end
		end

		if not Bridge.validateTargetShot(shotOrigin, aimPoint, aimPart, data.model, visTier, spoofOrigin) then
			continue
		end

		local dist = (aimPoint - losOrigin).Magnitude
		if dist > maxDist then continue end

		local tierScore = TARGET_PRIORITY_WEIGHT[shootPriority] or TARGET_PRIORITY_WEIGHT[3]
		local playerBias = 0
		if CONFIG.SilentAimPreferPlayers ~= false then
			if Bridge.isPlayerActorClass(data.class) then
				playerBias = -500
			elseif Bridge.isNpcActorClass(data.class) then
				playerBias = 250
			end
		end
		local score = tierScore + angle * 12 + dist * 0.008 + (visTier or 0) * 40 + playerBias
		if score < bestScore then
			bestScore = score
			best = {
				part = aimPart, point = aimPoint, data = data, visTier = visTier,
				head = head, spoofOrigin = spoofOrigin, shootPriority = shootPriority,
			}
		end
	end

	-- Backtrack fallback: цель заблокирована стеной СЕЙЧАС, но её записанный
	-- снапшот (позиция ~BacktrackOffsetMs назад) был на линии огня. Тогда стреляем
	-- в прошлое: ForceHit синтезирует дескриптор {UID,Part}, а хук FireServer
	-- переписывает Unix на снапшот → сервер отматывает цель к этой позиции.
	-- Полностью инертно для скриптов без CONFIG.Backtrack (nil).
	if not best and CONFIG.Backtrack and type(Bridge.pickBacktrackSnapshot) == "function" then
		local btBest, btScore = nil, math.huge
		for _, data in ipairs(candidates) do
			if data.uid and data.model then
				local head = Bridge.getHeadPart(data.model, nil)
				local snap = head and Bridge.pickBacktrackSnapshot(data.uid, now)
				if snap and typeof(snap.pos) == "Vector3" then
					local visOk = CONFIG.BacktrackRequireVisible == false
						or Bridge.hasClearShotToPoint(losOrigin, snap.pos, head, false)
					if visOk then
						local angle = Bridge.angleFromCameraLook(cam, snap.pos)
						local dist = (snap.pos - losOrigin).Magnitude
						if angle <= maxAngle and dist <= maxDist then
							local score = angle * 12 + dist * 0.008
							if score < btScore then
								btScore = score
								btBest = { head = head, point = snap.pos, data = data, snap = snap }
							end
						end
					end
				end
			end
		end
		if btBest then
			best = {
				part = btBest.head, point = btBest.point, data = btBest.data,
				visTier = 1, head = btBest.head, spoofOrigin = nil,
				shootPriority = 2, backtrack = true, btSnap = btBest.snap,
			}
		end
	end

	if not best then
		local sticky = CONFIG.MultiPointStickySec or 0.35
		if CONFIG.LiteMultiPoint and State.shotAimTarget and State.shotAimTarget.Parent
			and State.aimTargetPart and State.aimTargetPart.Parent
			and now - (State.aimLockTime or 0) < sticky then
			local aimPt = State.aimAimPoint or State.aimTargetPart.Position
			local reSpoof, _, _, reOk = Bridge.findLiteMultiPointShot(
				losOrigin, aimPt, State.aimTargetPart, State.aimTargetUid
			)
			if reOk and typeof(reSpoof) == "Vector3" then
				State.mpShotReady = true
				State.mpSpoofOrigin = reSpoof
				State.inAimRefresh = false
				return State.shotAimTarget
			end
		end
		State.inAimRefresh = false
		State.mpShotReady = false
		Bridge.clearAimTargetState(false)
		return nil
	end

	State.lastAimVisTier = best.visTier
	State.aimTargetPart = best.part or best.head
	State.aimTargetUid = best.data.uid
	State.aimTargetLabel = best.data.label or "target"
	State.aimFrameTarget = best.head
	State.shotAimTarget = best.head
	State.aimAimPoint = best.point
	State.forceHitPoint = best.point
	State.shotAimTargetTime = now
	State.aimBacktrack = best.backtrack == true
	State.aimBacktrackSnap = best.btSnap
	State.aimLockTime = now
	State.resolverAimBone = best.visTier == 1 and best.part or nil
	State.mpShotReady = not CONFIG.LiteMultiPoint or best.visTier == 3 or (
		typeof(best.spoofOrigin) == "Vector3"
		and Bridge.hasSaDirectPath(best.spoofOrigin, best.point, best.part)
	) or (CONFIG.LiteMultiPoint and best.visTier == 0)
	State.mpSpoofOrigin = best.spoofOrigin
	local muzzle = Bridge.getAimLosOrigin(losOrigin)
	if typeof(muzzle) == "Vector3" and best.part and best.part.Parent then
		local spoof = best.spoofOrigin
		if CONFIG.LiteMultiPoint then
			spoof = spoof or Bridge.resolveCombatMuzzleOffset(muzzle, best.point, best.part)
		end
		if typeof(spoof) == "Vector3" and (spoof - muzzle).Magnitude > 0.02 then
			State.combatMuzzleCf = CFrame.lookAt(spoof, best.point)
			State.spoofedMuzzlePos = spoof
			State.mpSpoofOrigin = spoof
		elseif typeof(spoof) == "Vector3" then
			State.combatMuzzleCf = nil
			State.spoofedMuzzlePos = spoof
		end
	end
	State.inAimRefresh = false
	return best.head
end

function Bridge.resolveExposedAimPoint(model, uid, origin, cam, maxAngle, _)
	return Bridge.findExposedPoint(model, uid, origin, cam, maxAngle)
end

function Bridge.resolveCombatAimPoint(data, origin, ctx, cam, maxAngle)
	local part, point, _ = Bridge.computeCombatAimPoint(data, origin, ctx, cam, maxAngle)
	return part, point
end

function Bridge.getHeadPart(model, fallback)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return fallback
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	return fallback
end

function Bridge.getHeadshotClaimPoint(_targetPart, _originHint)
	return nil
end

function Bridge.applyHitboxExpander(aimPoint, _targetPart, _origin)
	return aimPoint
end

function Bridge.isActorDead(data)
	if not data then return false end
	if data.dead == true or data.alive == false or data.class == "dead" then
		return true
	end
	-- v16: проверяем HP из actorData (реплицированное) и data.health
	if type(data.health) == "number" and data.health <= 0 then
		return true
	end
	if type(data.actorData) == "table" then
		local hp = tableField(data.actorData, "Health")
		if type(hp) == "number" and hp <= 0 then return true end
		if tableField(data.actorData, "Dead") == true then return true end
		if tableField(data.actorData, "IsDead") == true then return true end
	end
	return isModelDead(data.model, data.actorData)
end

function Bridge.getAimOrigin(originHint)
	if typeof(originHint) == "Vector3" then
		return originHint
	end
	local actor = State.localClient and Bridge.getActorTable(State.localClient)
	local cf = Bridge.getFireOriginCFrame(actor)
	if typeof(cf) == "CFrame" then
		return cf.Position
	end
	local cam = getCamera()
	return cam and cam.CFrame.Position
end

function Bridge.isAimTargetInFov(target, aimPoint, cam, maxAngle)
	if not target or not target.Parent or not cam then return false end
	maxAngle = maxAngle or CONFIG.SilentAimFOV or 15
	local checkPos = typeof(aimPoint) == "Vector3" and aimPoint or target.Position
	return Bridge.angleFromCameraLook(cam, checkPos) <= maxAngle
end

function Bridge.clearAimTargetState(clearMpCache)
	State.aimTargetPart = nil
	State.aimTargetUid = nil
	State.aimTargetLabel = nil
	State.aimFrameTarget = nil
	State.shotAimTarget = nil
	State.shotAimTargetTime = nil
	State.aimAimPoint = nil
	State.forceHitPoint = nil
	State.combatMuzzleCf = nil
	State.spoofedMuzzlePos = nil
	State.resolverAimBone = nil
	State.vizSpoofMuzzle = nil
	State.vizServerAim = nil
	State.vizWallBangOk = false
	State.mpAimCache = nil
	State.aimLockTime = nil
	State.exposedCache = nil
	if clearMpCache == true then
		State.exposedCacheByUid = nil
		State.combatMuzzleCache = nil
		State.aimTargetCache = nil
		if State.multiPointCache then
			table.clear(State.multiPointCache)
		end
	end
	State.lastAimVisTier = nil
	State.mpShotCache = nil
	State.mpShotReady = false
	State.mpSpoofOrigin = nil
end

function Bridge.resolveSilentAimPoint(part, origin, ctx)
	if not part or not part:IsA("BasePart") then return nil end
	local head = Bridge.getHeadPart(part.Parent, part) or part
	return Bridge.resolveShotAimPoint(head, origin, ctx)
end

function Bridge.resolveShotAimPoint(head, muzzleOrigin, ctx, uid)
	return Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid)
end

function Bridge.refreshShotAimAtMuzzle(muzzleOrigin, targetPart)
	if typeof(muzzleOrigin) ~= "Vector3" or not targetPart or not targetPart.Parent then
		return nil
	end
	local head = Bridge.getHeadPart(targetPart.Parent, targetPart) or targetPart
	local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or Bridge.getLiveWeaponContext(false)
	local uid = Bridge.resolveActorUidForPart(head, State.aimTargetUid)
	local point = Bridge.resolveServerAimPoint(targetPart, head, muzzleOrigin, ctx, uid, nil, nil, true)
		or Bridge.resolveUnifiedAimPoint(head, muzzleOrigin, ctx, uid, targetPart)
	if point then
		State.shotAimTarget = head
		State.aimTargetUid = uid or State.aimTargetUid
		State.forceHitPoint = point
		State.aimAimPoint = point
		State.shotBurstAimPoint = point
		State.shotAimTargetTime = os.clock()
	end
	return point
end

function Bridge.validateTargetShot(origin, aimPoint, part, model, visTier, spoofOrigin)
	if typeof(origin) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" or not part then
		return false
	end
	visTier = visTier or 0
	if visTier == 3 then
		if typeof(spoofOrigin) ~= "Vector3" then return false end
		return Bridge.hasSaDirectPath(spoofOrigin, aimPoint, part)
	elseif visTier == 0 then
		local viewOrigin = Bridge.getLocalViewOrigin() or origin
		return Bridge.hasVisiblePath(viewOrigin, aimPoint, part, false)
	elseif visTier == 1 then
		if typeof(spoofOrigin) == "Vector3" then
			return Bridge.hasSaDirectPath(spoofOrigin, aimPoint, part)
		end
		return true
	end
	return false
end

function Bridge.shouldSpoofMuzzlePosition()
	return CONFIG.LiteMultiPoint == true
end

function Bridge.needsServerAimPatch()
	return CONFIG.SilentAim == true or mpActive()
end

function Bridge.previewServerWallBang(originPos, aimPoint, targetPart)
	if typeof(originPos) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return originPos, aimPoint, false
	end
	if not targetPart or not targetPart.Parent then
		return originPos, aimPoint, false
	end
	if not Bridge.shouldSpoofMuzzlePosition() then
		return originPos, aimPoint, false
	end
	local spoof = Bridge.resolveCombatMuzzleOffset(originPos, aimPoint, targetPart)
	local ok = Bridge.hasClearShotToPoint(spoof, aimPoint, targetPart)
		or (typeof(spoof) == "Vector3" and (spoof - originPos).Magnitude > 0.15)
	State.vizSpoofMuzzle = spoof
	State.vizServerAim = aimPoint
	State.vizWallBangOk = ok
	return spoof, aimPoint, ok
end

function Bridge.prepareCombatShot(originPos)
	if typeof(originPos) ~= "Vector3" then return nil end
	State.forceCombatAimRefresh = false
	local target = Bridge.getCombatAimTarget(originPos, true)
	if target then
		State.shotAimTarget = target
		State.shotAimTargetTime = os.clock()
		if Bridge.needsServerAimPatch() then
			Bridge.prepareServerAimShot(originPos, target)
		end
	end
	return target
end

function Bridge.getCombatAimTarget(originForLos, force)
	if force or Bridge.isRecentCombatShot() or State.forceCombatAimRefresh then
		State.forceCombatAimRefresh = false
		return Bridge.refreshAimTarget(originForLos, true)
	end
	return Bridge.refreshAimTarget(originForLos, false)
end

function Bridge.angleFromLook(origin, lookVector, worldPos)
	if typeof(origin) ~= "Vector3" or typeof(worldPos) ~= "Vector3" then return 180 end
	local look = typeof(lookVector) == "Vector3" and lookVector.Magnitude > 0.01 and lookVector.Unit
		or Vector3.new(0, 0, -1)
	local toTarget = worldPos - origin
	if toTarget.Magnitude < 0.05 then return 0 end
	return math.deg(math.acos(math.clamp(look:Dot(toTarget.Unit), -1, 1)))
end

function Bridge.angleFromCameraLook(cam, worldPos)
	if not cam then return 180 end
	return Bridge.angleFromLook(cam.CFrame.Position, cam.CFrame.LookVector, worldPos)
end

function Bridge.getBoneVisSamplePoints(bone)
	if not bone or not bone:IsA("BasePart") then return nil end
	local cf = bone.CFrame
	local p = cf.Position
	local up = cf.UpVector
	local right = cf.RightVector
	local halfY = bone.Size.Y * 0.5
	local halfX = bone.Size.X * 0.5
	return {
		p,
		p + up * math.min(halfY * 0.65, 0.45),
		p - up * math.min(halfY * 0.35, 0.25),
		p + right * math.min(halfX * 0.78, 0.42),
		p - right * math.min(halfX * 0.78, 0.42),
	}
end

function Bridge.isActorVisibleForEsp(data, cam, intervalOverride)
	if not CONFIG.EspVisibleCheck then return true end
	if not data or not data.model then return false end
	local uid = data.uid
	if uid and State.espVisibleCache and State.espVisibleCache[uid] then
		local cached = State.espVisibleCache[uid]
		local ttl = intervalOverride or CONFIG.EspVisibleInterval or 0.35
		if os.clock() - (cached.t or 0) < ttl then
			return cached.v == true
		end
	end
	return Bridge.isActorVisible(data.model, uid, intervalOverride)
end

function Bridge.getEspActorVisible(uid)
	if not CONFIG.EspVisibleCheck then return true end
	if not uid then return true end
	local cached = State.espVisibleCache and State.espVisibleCache[uid]
	-- FIX v6: нет кеша = актор ещё не проверен = считаем невидимым
	-- Убирает "всегда visible" при первом появлении нового актора
	if cached then return cached.v == true end
	return false
end


function Bridge.resolveLocalActor(force)
	resolveLocalClient(force == true)
	local client = State.localClient
	local actor = client and Bridge.getActorTable(client)
	if actor then return client, actor end
	syncReplicatorActorsTable()
	local rep = State.replicatorActorsTable
	if type(rep) == "table" then
		local la = rawget(rep, "LocalActor")
		if type(la) == "table" then
			return client, la
		end
	end
	if client and (rawget(client, "_equipped") ~= nil or tableField(client, "IsLocalPlayer") == true) then
		return client, client
	end
	return client, nil
end

function Bridge.resolveHandFromActor(actor, mods)
	if type(actor) ~= "table" then return nil, nil, nil end
	mods = mods or Bridge.loadSharedModules()
	local eqUid = Bridge.normalizeEquipUid(rawget(actor, "_equipped"))
	if not eqUid then
		local state = tableField(actor, "CurrentState")
		if type(state) == "table" then
			eqUid = Bridge.normalizeEquipUid(tableField(state, "Equip"))
		end
	end
	if not eqUid then return nil, nil, nil end
	local handler = Bridge.getWeaponHandler(actor, eqUid)
		or Bridge.findFirearmHandler(actor, eqUid)
	local item = handler and (rawget(handler, "_item") or rawget(handler, "Item"))
	if not item then
		item = Bridge.itemFromActorInventory(actor, eqUid)
	end
	if not item or not Bridge.isPlayerFirearmItem(item, mods) then
		return nil, nil, handler
	end
	local slot = Bridge.slotLabelFromItem(item, mods) or "Primary"
	return item, slot, handler
end

function Bridge.isWeaponInHand(actor, hand, mods)
	if type(hand) ~= "table" then return false end
	mods = mods or Bridge.loadSharedModules()
	if State.handItem == hand and (State.handHookTime or 0) > 0 then
		return true
	end
	if type(actor) ~= "table" then return false end
	local uid = Bridge.itemUid(hand)
	local eq = Bridge.normalizeEquipUid(rawget(actor, "_equipped"))
	if uid and eq and uid == eq then
		if Bridge.isMeleeItem(hand, mods) then
			local handler = Bridge.getWeaponHandler(actor, eq)
			return handler ~= nil and (rawget(handler, "_toHand") == true or rawget(handler, "_mode") == 2)
		end
		return true
	end
	return false
end

function Bridge.handFromCharacterHandModel(slots, mods)
	if not Bridge.isLocalPlayerAlive() then return nil, nil end
	local model = State.localModel
	if (not model or not model.Parent) and LP and LP.Character then
		model = LP.Character
	end
	if not model or not model.Parent then return nil, nil end
	local wm = Bridge.findHandWeldedWeaponModel(model)
	if not wm then return nil, nil end
	local item, slot = Bridge.matchSlotItemToWeaponModel(slots, mods, wm)
	if item then return item, slot end
	local _, actor = Bridge.resolveLocalActor(false)
	if type(actor) == "table" then
		local eqUid = Bridge.normalizeEquipUid(rawget(actor, "_equipped"))
		local stateItem = eqUid and Bridge.itemFromActorInventory(actor, eqUid)
		if stateItem and Bridge.isPlayerFirearmItem(stateItem, mods) then
			return stateItem, Bridge.slotLabelFromItem(stateItem, mods) or "Melee"
		end
	end
	return nil, nil
end

function Bridge.peekWeaponContext(maxAge)
	maxAge = maxAge or (CONFIG.WeaponCtxCacheSec or 0.85)
	if State.weaponCtxCache == WEAPON_CTX_EMPTY then return nil end
	local ctx = State.weaponCtxCache
	if ctx and Bridge.weaponContextValid(ctx) then
		if os.clock() - (State.weaponCtxCacheTime or 0) < maxAge then
			return ctx
		end
	end
	return nil
end

function Bridge.buildWeaponContext(actor, hand, handSlot, mods)
	if not hand then return nil end
	mods = mods or Bridge.loadSharedModules()
	local uid = Bridge.itemUid(hand)
	local handler = nil
	if actor then
		handler = Bridge.findFirearmHandler(actor, uid)
			or Bridge.getWeaponHandler(actor, uid)
			or Bridge.findEquippedHandlerForItem(actor, hand)
	end
	local meta = rawget(hand, "MetaData") or tableField(hand, "MetaData")
	local info = Bridge.parseFirearmItem(hand, handSlot or "Hand", mods, handler)
	local isMelee = Bridge.isMeleeItem(hand, mods)
		or (info and info.caliber == "melee")
		or Bridge.isMeleeHandler(handler)

	if not isMelee then
		if (not handler or not Bridge.tuneFromHandler(handler)) and actor then
			handler = Bridge.findFirearmHandler(actor, uid) or Bridge.getWeaponHandler(actor, uid)
		end
		if not handler or not Bridge.tuneFromHandler(handler) then
			return nil
		end
	else
		handler = handler or (actor and Bridge.findEquippedHandlerForItem(actor, hand))
		if not info then
			info = {
				item = hand,
				slot = handSlot or "Melee",
				name = Bridge.firearmDisplayName(hand),
				caliber = "melee",
				inMag = nil,
				chamber = 0,
				mode = "-",
			}
		end
	end

	if handler and not isMelee and type(Bridge.ensureHandlerDischargeHook) == "function" then
		pcall(Bridge.ensureHandlerDischargeHook, handler)
	end
	local tune = handler and Bridge.tuneFromHandler(handler) or nil
	if not info then
		info = Bridge.parseFirearmItem(hand, handSlot or "Hand", mods, handler)
	end
	return {
		actor = actor,
		handler = handler,
		item = hand,
		meta = meta,
		tune = tune,
		cal = info and info.cal,
		info = info,
		isMelee = isMelee,
	}
end

Bridge.getLiveWeaponContext = function(force)
	local now = os.clock()
	local cacheTtl = CONFIG.WeaponCtxCacheSec or 0.55
	local emptyTtl = CONFIG.WeaponCtxEmptyCacheSec or 8.0
	if not force and State.weaponCtxCacheTime then
		local age = now - State.weaponCtxCacheTime
		if State.weaponCtxCache == WEAPON_CTX_EMPTY then
			if age < emptyTtl then
				Bridge.perfCount("weaponCtxEmptyHit")
				return nil
			end
		elseif State.weaponCtxCache and Bridge.weaponContextValid(State.weaponCtxCache) then
			if age < cacheTtl then
				Bridge.perfCount("weaponCtxCacheHit")
				return State.weaponCtxCache
			end
		end
	end
	Bridge.perfCount("weaponCtxResolve")
	if force ~= true and not Bridge.isLocalPlayerAlive() then
		State.weaponCtxCache = WEAPON_CTX_EMPTY
		State.weaponCtxCacheTime = now
		Bridge.perfCount("weaponCtxEmpty")
		return nil
	end
	local mods = Bridge.loadSharedModules()
	local client, actor = Bridge.resolveLocalActor(force == true)
	if not actor and force == true then
		client, actor = Bridge.resolveLocalActor(true)
	end
	if not client and actor then
		State.localClient = State.localClient or actor
		client = State.localClient
	end

	local hand, handSlot, handlerHint
	if State.handItem and Bridge.isPlayerFirearmItem(State.handItem, mods)
		and (State.handHookTime or 0) > 0 then
		hand, handSlot = State.handItem, State.handSlot
	end
	if not hand and actor then
		hand, handSlot, handlerHint = Bridge.resolveHandFromActor(actor, mods)
	end
	if not hand then
		hand, handSlot = Bridge.handFromCharacterHandModel({}, mods)
	end
	if not hand then
		hand, handSlot = Bridge.handFromCharacterWeaponModel({}, mods)
	end
	if not hand then
		local owner = Bridge.resolvePlayerInventory(force == true)
		local slots = Bridge.mergeWeaponSlots(owner, mods, client)
		local discover = force == true
		hand, handSlot = Bridge.resolveEquippedHand(slots, mods, discover)
		if not hand and not discover then
			hand, handSlot = Bridge.resolveEquippedHand(slots, mods, true)
		end
		if not hand then
			hand, handSlot = Bridge.handFromCharacterWeaponModel(slots, mods)
		end
	end
	if not hand then
		State.weaponCtxCache = WEAPON_CTX_EMPTY
		State.weaponCtxCacheTime = now
		Bridge.perfCount("weaponCtxEmpty")
		return nil
	end
	if actor and not Bridge.isWeaponInHand(actor, hand, mods) then
		State.weaponCtxCache = WEAPON_CTX_EMPTY
		State.weaponCtxCacheTime = now
		Bridge.perfCount("weaponCtxEmpty")
		return nil
	end
	if not actor then
		client, actor = Bridge.resolveLocalActor(true)
	end
	local ctx = Bridge.buildWeaponContext(actor, hand, handSlot, mods)
	if ctx and handlerHint and not ctx.handler then
		ctx.handler = handlerHint
	end
	if ctx and Bridge.weaponContextValid(ctx) then
		State.weaponCtxCache = ctx
		State.weaponCtxCacheTime = now
		Bridge.perfCount("weaponCtxOk")
		return ctx
	end
	ctx = Bridge.buildWeaponContextFallback(force == true)
	if ctx and Bridge.weaponContextValid(ctx) then
		State.weaponCtxCache = ctx
		State.weaponCtxCacheTime = now
		Bridge.perfCount("weaponCtxOk")
		return ctx
	end
	State.weaponCtxCache = WEAPON_CTX_EMPTY
	State.weaponCtxCacheTime = now
	Bridge.perfCount("weaponCtxEmpty")
	return nil
end

function Bridge.buildWeaponContextFallback(force)
	if force ~= true and not Bridge.isLocalPlayerAlive() then return nil end
	local mods = Bridge.loadSharedModules()
	local client, actor = Bridge.resolveLocalActor(force == true)
	if not client and actor then
		State.localClient = State.localClient or actor
		client = State.localClient
	end
	local owner = Bridge.resolvePlayerInventory(force == true)
	local slots = Bridge.mergeWeaponSlots(owner, mods, client)
	local hand, slot = Bridge.resolveEquippedHand(slots, mods, true)
	if not hand then
		hand, slot = Bridge.handFromCharacterWeaponModel(slots, mods)
	end
	if not hand then return nil end
	if not actor then
		_, actor = Bridge.resolveLocalActor(true)
	end
	return Bridge.buildWeaponContext(actor, hand, slot, mods)
end

function Bridge.vector3ToTable(pos)
	if typeof(pos) ~= "Vector3" then return nil end
	if not State._v3ToTableFn then
		if type(shared) == "table" and type(shared.import) == "function" then
			local ok, fn = pcall(shared.import, "vector3toTable")
			if ok and type(fn) == "function" then
				State._v3ToTableFn = fn
			end
		end
	end
	if State._v3ToTableFn then
		local ok, t = pcall(State._v3ToTableFn, pos)
		if ok and type(t) == "table" then
			local x = rawget(t, 1)
			local y = rawget(t, 2)
			local z = rawget(t, 3)
			if type(x) == "number" and type(y) == "number" and type(z) == "number" then
				return { x, y, z }
			end
			x = x or rawget(t, "X") or rawget(t, "x")
			y = y or rawget(t, "Y") or rawget(t, "y")
			z = z or rawget(t, "Z") or rawget(t, "z")
			if type(x) == "number" and type(y) == "number" and type(z) == "number" then
				return { x, y, z }
			end
		end
	end
	return { pos.X, pos.Y, pos.Z }
end

function Bridge.isFluxNetwork(net)
	if net == nil or type(net) ~= "table" then
		return false
	end
	local fs = rawget(net, "FireServer")
	return type(fs) == "function"
end

function Bridge.resolveGameNetwork()
	if Bridge.isFluxNetwork(State.networkModule) then
		return State.networkModule
	end
	if type(Bridge.loadNetworkModule) == "function" then
		local net = Bridge.loadNetworkModule(true)
		if Bridge.isFluxNetwork(net) then
			State.networkModule = net
			return net
		end
	end
	if type(shared) == "table" and type(shared.import) == "function" then
		local ok, net = pcall(shared.import, "network")
		if ok and Bridge.isFluxNetwork(net) then
			State.networkModule = net
			State.networkModuleSource = State.networkModuleSource or "shared.import"
			return net
		end
	end
	if type(Bridge.scanGcForNetwork) == "function" then
		local gcNet = Bridge.scanGcForNetwork()
		if Bridge.isFluxNetwork(gcNet) then
			State.networkModule = gcNet
			State.networkModuleSource = "getgc.flux"
			return gcNet
		end
	end
	return nil
end

function Bridge.getNetworkModule(force)
	if State.networkModule and not Bridge.isFluxNetwork(State.networkModule) then
		State.networkModule = nil
		State.networkModuleSource = nil
	end
	if not force and Bridge.isFluxNetwork(State.networkModule) then
		return State.networkModule
	end
	local net = Bridge.resolveGameNetwork()
	if Bridge.isFluxNetwork(net) then
		State.networkModuleT = os.clock()
	end
	return net
end

function Bridge.networkFireServer(...)
	local net = Bridge.resolveGameNetwork()
	if not Bridge.isFluxNetwork(net) then
		return false, "bad_network"
	end
	local args = table.pack(...)
	local ok, err = pcall(function()
		net:FireServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function Bridge.isFirearmAimContext(ctx)
	if not ctx or ctx == WEAPON_CTX_EMPTY or not Bridge.weaponContextValid(ctx) then
		return false
	end
	if ctx.isMelee == true or (ctx.info and ctx.info.caliber == "melee") then
		return false
	end
	if ctx.tune then return true end
	if ctx.handler and Bridge.tuneFromHandler and Bridge.tuneFromHandler(ctx.handler) then
		return true
	end
	return ctx.handler ~= nil
end

function Bridge.getAimWeaponContext(allowResolve)
	local peeked = Bridge.peekWeaponContext(1.5)
	if peeked and Bridge.isFirearmAimContext(peeked) then
		return peeked
	end
	if allowResolve ~= true then return nil end
	local now = os.clock()
	local iv = CONFIG.AimCtxResolveInterval or 0.35
	if now - (State.lastAimCtxResolve or 0) < iv then
		local c = State.weaponCtxCache
		if Bridge.isFirearmAimContext(c) then return c end
		return nil
	end
	State.lastAimCtxResolve = now
	local force = State.weaponCtxCache == WEAPON_CTX_EMPTY
		or not State.weaponCtxCache
		or not Bridge.isFirearmAimContext(State.weaponCtxCache)
	return Bridge.getLiveWeaponContext(force)
end

function Bridge.getCachedWeaponContext(maxAge)
	maxAge = maxAge or (CONFIG.WeaponCtxCacheSec or 0.85)
	local peeked = Bridge.peekWeaponContext(maxAge)
	if peeked then return peeked end
	return Bridge.getLiveWeaponContext(false)
end

Bridge.getActorTable = function(client)
	if type(client) ~= "table" then return nil end
	local actor = tableField(client, "Actor")
	if type(actor) == "table" then return actor end
	if tableField(client, "_equipped") or tableField(client, "IsLocalPlayer") == true then
		return client
	end
	return nil
end

Bridge.readFunctionalSlots = function(owner, mods)
	local arr = nil
	if mods.SharedInventory then
		local mainId = Bridge.findMainStorageId(owner)
		local getFn = mods.SharedInventory.GetAllFunctional
		if mainId and type(getFn) == "function" then
			local ok, got = pcall(getFn, owner, mainId, 1)
			if ok and type(got) == "table" then
				arr = got
			end
		end
	end
	if not arr or not arr[1] then
		arr = Bridge.readFunctionalSlotsDirect(owner, mods)
	end

	local out = {}
	if not arr then return out end
	for i, label in ipairs(SLOT_LABELS) do
		out[label] = arr[i]
	end
	return out
end


Bridge.mergeWeaponSlots = function(owner, mods, client)
	local slots = {}
	local actor = Bridge.getActorTable(client)
	if actor then
		slots = Bridge.readSlotsFromActorState(actor, mods)
		if next(slots) then
			markResolver("slots", "actor.inventory")
		end
	end
	if owner and (not next(slots) or State.methods.slots == "storages.functional") then
		local fromStorages = Bridge.readFunctionalSlots(owner, mods)
		if next(fromStorages) then
			markResolver("slots", "storages.functional")
			for label, item in pairs(fromStorages) do
				if not slots[label] then
					slots[label] = item
				end
			end
		end
	end
	return slots
end

Bridge.resolveEquippedHand = function(slots, mods, discover)
	local client = State.localClient
	if not client and Bridge.resolveLocalActor then
		local c, a = Bridge.resolveLocalActor(discover == true)
		if c then
			client = c
		elseif type(a) == "table" then
			State.localClient = State.localClient or a
			client = a
		end
	end
	if not client then return nil, nil end

	local locked = State.methods.hand
	if locked and not discover then
		for _, resolver in ipairs(HAND_RESOLVERS) do
			if resolver.id == locked then
				local hand, slot = resolver.try(client, slots, mods)
				if hand then
					State.handItem = hand
					State.handSlot = slot
					return hand, slot
				end
				break
			end
		end
		-- stale lock — пробуем полный проход вместо мгновенного nil
		State.methods.hand = nil
	end

	for _, resolver in ipairs(HAND_RESOLVERS) do
		local hand, slot = resolver.try(client, slots, mods)
		if hand then
			markResolver("hand", resolver.id)
			State.handItem = hand
			State.handSlot = slot
			return hand, slot
		end
	end

	if Bridge.isLocalPlayerAlive()
		and State.handItem and Bridge.isPlayerFirearmItem(State.handItem, mods) then
		markResolver("hand", "equip.hook")
		log("RESOLVE", "hand = equip.hook (fallback from State.handItem)")
		return State.handItem, State.handSlot
	end

	State.handItem = nil
	State.handSlot = nil
	return nil, nil
end

function Bridge.invalidateWeaponCache()
	State.weaponCtxCache = nil
	State.weaponCtxCacheTime = 0
	State.fovWeaponCtx = nil
	State._weaponCtxForceTryT = 0
end

function Bridge.rediscoverEquippedWeapon(forceDiscover)
	if not Bridge.isLocalPlayerAlive() then return nil, nil end
	Bridge.perfCount("weaponRediscover")
	Bridge.invalidateWeaponCache()
	if forceDiscover == true then
		State.methods.hand = nil
		State.lastInventoryGc = 0
		State.lastInventoryGcResult = nil
		State.lastInventoryGcScore = 0
	end
	resolveLocalClient(forceDiscover == true)
	resolveLocalPlayer()
	local mods = Bridge.loadSharedModules()
	if forceDiscover == true then
		Bridge.resolvePlayerInventory(true)
	else
		Bridge.resolvePlayerInventory(false)
	end
	local client = State.localClient
	if not client then return nil, nil end
	local owner = State.playerInventory or Bridge.resolvePlayerInventory(false)
	local slots = Bridge.mergeWeaponSlots(owner, mods, client)
	local hand, slot = Bridge.resolveEquippedHand(slots, mods, forceDiscover == true)
	if hand then
		State.noWeaponRediscoverMisses = 0
		State.handHookTime = os.clock()
		Bridge.invalidateWeaponCache()
	else
		State.noWeaponRediscoverMisses = (State.noWeaponRediscoverMisses or 0) + 1
	end
	State.lastHandRediscover = os.clock()
	return hand, slot
end

function Bridge.schedulePostRespawnWeaponRediscover()
	State.respawnHandScanGen = (State.respawnHandScanGen or 0) + 1
	local gen = State.respawnHandScanGen
	local delays = { 0, 0.45, 1.0, 2.0, 3.5, 5.5, 8.0 }
	for _, delay in ipairs(delays) do
		task.delay(delay, function()
			if not State.running then return end
			if State.respawnHandScanGen ~= gen then return end
			if not Bridge.isLocalPlayerAlive() then return end
			local ctx = Bridge.getLiveWeaponContext(true)
			if Bridge.weaponContextValid(ctx) then return end
			Bridge.rediscoverEquippedWeapon(true)
			Bridge.requestHudRefresh(true)
		end)
	end
end

function Bridge.tickHandRediscoverIfNeeded()
	if not State.running or not Bridge.isLocalPlayerAlive() then return end
	local now = os.clock()
	local misses = State.noWeaponRediscoverMisses or 0
	local interval = CONFIG.HandRediscoverInterval or 0.45
	if misses >= 2 then
		interval = CONFIG.NoWeaponRediscoverInterval or 2.5
	end
	if misses >= 4 then
		interval = math.max(interval, 4.0)
	end
	if now - (State.lastHandRediscover or 0) < interval then return end
	local ctx = State.weaponCtxCache
	if ctx and ctx ~= WEAPON_CTX_EMPTY and Bridge.weaponContextValid(ctx) then return end
	local emptyAge = now - (State.weaponCtxCacheTime or 0)
	if ctx == WEAPON_CTX_EMPTY and emptyAge < (CONFIG.WeaponCtxEmptyCacheSec or 8.0) then return end
	if misses >= 2 and emptyAge < 2.0 then return end
	Bridge.rediscoverEquippedWeapon(false)
end


Bridge.requestHudRefresh = function(force)
	if Bridge.refreshWeaponCache then
		Bridge.refreshWeaponCache(force == true)
	end
end

Bridge.refreshWeaponCache = function(force)
	local now = os.clock()
	if State.hudRefreshing and not force then return end
	if not force and now - State.lastWeaponRefresh < CONFIG.WeaponHudInterval then
		return
	end
	-- v20 FIX: убран двойной guard + task.spawn→defer
	if State.hudRefreshing and not force then return end
	State.hudRefreshing = true

	task.defer(function()
		local ok, result = pcall(Bridge.buildWeaponHudLines, force == true)
		State.hudRefreshing = false
		State.lastWeaponRefresh = os.clock()

		if ok and type(result) == "table" then
			State.hudLastLines = result
		elseif not ok then
			log("WEAPON", "HUD build error", result)
			if force then
				State.hudLastLines = { "[Weapon]", "HUD error", tostring(result):sub(1, 80) }
			else
				table.insert(State.hudLastLines, "HUD error (kept last lines)")
			end
		end

		pcall(Bridge.syncWeaponHud, State.hudLastLines)

		if not State.weaponHudLogged then
			for _, line in ipairs(State.hudLastLines) do
				if type(line) == "string" and line:find("HANDS:") then
					State.weaponHudLogged = true
					log("WEAPON", "HUD active", #State.hudLastLines, "lines")
					logLockedMethods()
					break
				end
			end
		end
	end)
end


function Bridge.collectAimActorCandidates(cam, losOrigin, maxDist, maxAngle)
	-- FIX v3: кэш врагов на 0.15s — не перебираем pairs(actors) каждые 55ms
	local now = os.clock()
	local enemyCache = State._aimEnemyCache
	if not enemyCache or (now - (State._aimEnemyCacheT or 0)) > 0.15
		or (State._aimEnemyCacheCount or 0) ~= (State.trackedActorCount or 0) then
		enemyCache = {}
		-- PVE: игроки — союзники, silent aim их пропускает (ESP не трогаем).
		-- Считаем режим один раз перед циклом (refreshPlaceMode кэширован по placeId).
		local pveIgnorePlayers = CONFIG.SilentAimIgnorePlayersInPve ~= false and Bridge.isPveMode()
		for _, data in pairs(State.actors) do
			if Bridge.isEnemyActor(data) then
				local skipNpc = CONFIG.SilentAimIgnoreNpc == true and Bridge.isNpcActorClass(data.class)
				local skipPve = pveIgnorePlayers and Bridge.isPlayerActorClass(data.class)
				if not skipNpc and not skipPve then
					enemyCache[#enemyCache + 1] = data
				end
			end
		end
		State._aimEnemyCache = enemyCache
		State._aimEnemyCacheT = now
		State._aimEnemyCacheCount = State.trackedActorCount or 0
	end

	local list = {}
	for _, data in ipairs(enemyCache) do
		local root = data.root
		if not root or not root.Parent then continue end
		-- FIX v7: InactiveWorld игроки — root.Position = 0,0,0, используем adPos
		local refPos
		if data.inInactiveWorld and data.adPos and typeof(data.adPos) == "Vector3" then
			refPos = data.adPos
		else
			refPos = root.Position
		end
		-- FIX v3: проверяем дистанцию через Vector3 dot — без sqrt для быстрого отсева
		local dx = refPos.X - losOrigin.X
		local dy = refPos.Y - losOrigin.Y
		local dz = refPos.Z - losOrigin.Z
		local distSq = dx*dx + dy*dy + dz*dz
		if distSq > maxDist * maxDist then continue end
		local dist = math.sqrt(distSq)
		-- угол считаем только для прошедших дистанцию
		local angle = Bridge.angleFromCameraLook(cam, refPos)
		if angle > maxAngle then continue end
		list[#list + 1] = { data = data, dist = dist, angle = angle }
	end
	table.sort(list, function(a, b)
		local aPlayer = Bridge.isPlayerActorClass(a.data.class) and 0 or 1
		local bPlayer = Bridge.isPlayerActorClass(b.data.class) and 0 or 1
		if CONFIG.SilentAimPreferPlayers ~= false and aPlayer ~= bPlayer then
			return aPlayer < bPlayer
		end
		if math.abs(a.angle - b.angle) > 0.01 then return a.angle < b.angle end
		return a.dist < b.dist
	end)
	local cap = CONFIG.AimScanMaxActors or 14
	if CONFIG.LiteMultiPoint then
		cap = math.min(cap, CONFIG.LiteMultiPointMaxActors or 6)
	end
	local out = {}
	for i = 1, math.min(#list, cap) do
		out[i] = list[i].data
	end
	return out
end

function Bridge.prepareServerAimShot(originPos, targetPart)
	if not targetPart then return end
	Bridge.refreshShotAimAtMuzzle(originPos, targetPart)
end

function Bridge.resolveV138CanonicalMuzzle(v138, originHint)
	if typeof(originHint) == "Vector3" then return originHint end
	if type(v138) ~= "table" then return nil end
	for _, entry in ipairs(v138) do
		if type(entry) == "table" and type(entry[2]) == "number" then
			return Vector3.new(entry[2], entry[3], entry[4])
		end
	end
	return nil
end

function Bridge.resolveServerShotMuzzle(realMuzzle, aimPoint, targetPart)
	if typeof(realMuzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return realMuzzle
	end
	if not Bridge.shouldServerMuzzleSpoof() then
		return realMuzzle
	end
	if Bridge.hasClearShotToPoint(realMuzzle, aimPoint, targetPart) then
		return realMuzzle
	end
	return Bridge.resolveCombatMuzzleOffset(realMuzzle, aimPoint, targetPart)
end

function Bridge.v138OrientationFromMuzzle(muzzle, aimPoint)
	if typeof(muzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return 0, 0, nil
	end
	if (aimPoint - muzzle).Magnitude < 0.01 then
		return 0, 0, nil
	end
	local cf = CFrame.lookAt(muzzle, aimPoint)
	local pitch, yaw, roll = cf:ToOrientation()
	return pitch, yaw, cf
end

function Bridge.cframeForServerAim(muzzle, aimPoint, ctx)
	if typeof(muzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return CFrame.lookAt(muzzle, aimPoint)
	end
	return CFrame.lookAt(muzzle, aimPoint)
end

function Bridge.cframeToPitchYaw(cf)
	if typeof(cf) ~= "CFrame" then return 0, 0 end
	local ok, pitch, yaw = pcall(function()
		return cf:ToOrientation()
	end)
	if ok and type(pitch) == "number" and type(yaw) == "number" then
		return pitch, yaw
	end
	return 0, 0
end

function Bridge.ensureShotTargetForPatch(origin)
	return Bridge.prepareCombatShotOnce(origin)
end

function Bridge.resolveV138AimPoint(target, originHint)
	if not target or not target.Parent or typeof(originHint) ~= "Vector3" then
		return typeof(State.aimAimPoint) == "Vector3" and State.aimAimPoint
			or typeof(State.forceHitPoint) == "Vector3" and State.forceHitPoint
			or nil
	end
	local head = Bridge.getHeadPart(target.Parent, target) or target
	local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or Bridge.getLiveWeaponContext(false)
	local point = Bridge.resolveShotAimPoint(head, originHint, ctx)
	if point then
		State.shotAimTarget = head
		State.forceHitPoint = point
		State.aimAimPoint = point
	end
	return point or head.Position
end

function Bridge.isMuzzleOriginValid(candidate, realOrigin)
	if typeof(candidate) ~= "Vector3" or typeof(realOrigin) ~= "Vector3" then
		return false
	end
	local maxOff = CONFIG.MuzzlePeekMaxOffset or 2.6
	if CONFIG.MultiPoint then
		maxOff = math.max(maxOff, CONFIG.MultiPointMaxMuzzleDist or 10)
	elseif CONFIG.LiteMultiPoint then
		maxOff = math.max(maxOff, CONFIG.LiteMultiPointMaxDist or 6)
	end
	return (candidate - realOrigin).Magnitude <= maxOff + 0.05
end


function Bridge.clampSpoofedMuzzle(spoofPos)
	-- Clamp отключён: muzzle может двигаться на любую дистанцию
	return spoofPos
end

function Bridge.spoofMuzzleCacheKey(realMuzzle, aimPoint, targetPart)
	local tid = targetPart and (targetPart:GetAttribute("ActorUID") or targetPart.Name) or "nil"
	return string.format(
		"%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%s",
		realMuzzle.X, realMuzzle.Y, realMuzzle.Z,
		aimPoint.X, aimPoint.Y, aimPoint.Z,
		tid
	)
end

function Bridge.pruneStaleActors(now)
	now = now or os.clock()
	if now - (State._lastActorPrune or 0) < 4.0 then return 0 end
	State._lastActorPrune = now
	local actors = State.actors
	if type(actors) ~= "table" then return 0 end
	local rep = State.replicatorActorsTable
	local removed = 0
	for uid, data in pairs(actors) do
		if type(data) ~= "table" then
			actors[uid] = nil
			removed += 1
			continue
		end
		local model = data.model
		local root = data.root
		local gone = not model or not model.Parent or not root or not root.Parent
		if gone then
			actors[uid] = nil
			removed += 1
		end
	end
	if removed > 0 then
		local count = 0
		for _ in pairs(actors) do count += 1 end
		State.trackedActorCount = count
		State._aimEnemyCache = nil
		State._aimEnemyCacheT = 0
		State.espActorList = nil
		State.espRanked = nil
		State._espNpcCount = nil
	end
	if State.actorVelTrack then
		for uid in pairs(State.actorVelTrack) do
			if not actors[uid] then State.actorVelTrack[uid] = nil end
		end
	end
	if State.actorVelInstant then
		for uid in pairs(State.actorVelInstant) do
			if not actors[uid] then State.actorVelInstant[uid] = nil end
		end
	end
	return removed
end

function Bridge.pruneSpoofCaches(now)
	if now - (State.lastSpoofCachePrune or 0) < 1.5 then return end
	State.lastSpoofCachePrune = now
	local spoofTtl = (CONFIG.SpoofMuzzleCacheSec or 0.1) * 4
	for k, e in pairs(State.spoofMuzzleCache) do
		if now - (e.t or 0) > spoofTtl then
			State.spoofMuzzleCache[k] = nil
		end
	end
	local losTtl = (CONFIG.LosRaycastCacheSec or 0.06) * 4
	for k, e in pairs(State.losRaycastCache) do
		if now - (e.t or 0) > losTtl then
			State.losRaycastCache[k] = nil
		end
	end
end

-- v15: универсальная очистка всех кэшей по CacheGcInterval
function Bridge.pruneAllCaches(now)
	local interval = CONFIG.CacheGcInterval or 2.0
	if now - (State.lastCacheGc or 0) < interval then return end
	State.lastCacheGc = now
	State.lastSpoofCachePrune = 0
	Bridge.pruneSpoofCaches(now)
	-- v19: pierceListCache TTL
	if State.pierceListCache then
		for k, e in pairs(State.pierceListCache) do
			if now - e.t > 2.0 then State.pierceListCache[k] = nil end
		end
	end
	-- v19: bulletModelCache мёртвых моделей
	if State._bulletModelCache then
		for model, e in pairs(State._bulletModelCache) do
			if not model.Parent or now - e.t > 3.0 then State._bulletModelCache[model] = nil end
		end
	end
	-- v19: firearmModelCache сброс если модель ушла
	if State._firearmModelCache and not (State._firearmModelCache.model and State._firearmModelCache.model.Parent) then
		State._firearmModelCache = nil
	end
	-- v18: hard cap на losRaycastCache — не больше 120 записей
	local losCount = 0
	for _ in pairs(State.losRaycastCache) do losCount += 1 end
	if losCount > 120 then
		table.clear(State.losRaycastCache)
	end
	-- multiPointCache
	local mpTtl = (CONFIG.MultiPointCacheSec or 0.05) * 8
	for k, e in pairs(State.multiPointCache) do
		if type(e) == "table" and now - (e.t or 0) > mpTtl then
			State.multiPointCache[k] = nil
		end
	end
	-- resolverCache
	if State.resolverCache and type(State.resolverCache.t) == "number" then
		if now - State.resolverCache.t > 0.12 then
			State.resolverCache = nil
		end
	end
	-- tbMuzzleCache
	if State.tbMuzzleCache then
		for k, e in pairs(State.tbMuzzleCache) do
			if now - (e.t or 0) > 0.25 then State.tbMuzzleCache[k] = nil end
		end
		local tbCount = 0
		for _ in pairs(State.tbMuzzleCache) do tbCount += 1 end
		if tbCount > 48 then table.clear(State.tbMuzzleCache) end
	end
	-- mpAimCache
	if State.mpAimCache and now - (State.mpAimCache.t or 0) > 0.15 then
		State.mpAimCache = nil
	end
	-- espVisibleCache
	local espVisTtl = (CONFIG.EspVisibleInterval or 0.1) * 5
	local espCount = 0
	for k, e in pairs(State.espVisibleCache) do
		espCount += 1
		if type(e) == "table" and now - (e.t or 0) > espVisTtl then
			State.espVisibleCache[k] = nil
			espCount -= 1
		end
	end
	if espCount > 96 then
		table.clear(State.espVisibleCache)
	end
	-- healthCache cleanup on dead actors
	for _, data in pairs(State.actors) do
		if data._healthCache and Bridge.isActorDead(data) then
			data._healthCache = nil
			data._healthCacheT = nil
		end
	end
	Bridge.pruneStaleActors(now)
	-- reserveCache cap
	if State.reserveCache then
		local rc = 0
		for _ in pairs(State.reserveCache) do rc += 1 end
		if rc > 24 then table.clear(State.reserveCache) end
	end
	-- tuneCache cap
	if State.tuneCache then
		local tc = 0
		for _ in pairs(State.tuneCache) do tc += 1 end
		if tc > 32 then table.clear(State.tuneCache) end
	end
end

function Bridge.resolveSpoofedMuzzleOrigin(realMuzzle, aimPoint, targetPart)
	if typeof(realMuzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return realMuzzle
	end
	if not State.inDischargeHook and not Bridge.isRecentCombatShot() then
		return realMuzzle
	end
	local now = os.clock()
	local key = Bridge.spoofMuzzleCacheKey(realMuzzle, aimPoint, targetPart)
	local ttl = CONFIG.SpoofMuzzleCacheSec or 0.1
	local cached = State.spoofMuzzleCache[key]
	if cached and now - (cached.t or 0) < ttl then
		State.spoofedMuzzlePos = cached.pos
		return cached.pos
	end
	Bridge.pruneSpoofCaches(now)

	if Bridge.hasClearShotToPoint(realMuzzle, aimPoint, targetPart) then
		State.spoofedMuzzlePos = realMuzzle
		State.spoofMuzzleCache[key] = { t = now, pos = realMuzzle }
		return realMuzzle
	end

	local cam = getCamera()
	local toAim = aimPoint - realMuzzle
	if toAim.Magnitude < 0.05 then
		State.spoofedMuzzlePos = realMuzzle
		State.spoofMuzzleCache[key] = { t = now, pos = realMuzzle }
		return realMuzzle
	end
	local toAimU = toAim.Unit
	local right = cam and cam.CFrame.RightVector or Vector3.new(1, 0, 0)
	local maxOff = CONFIG.MuzzlePeekMaxOffset or 2.6

	local best, bestScore = realMuzzle, math.huge
	local sideDists = { 1.0, 1.8 }
	for _, sideMul in ipairs({ -1, 1 }) do
		for _, sideDist in ipairs(sideDists) do
			local cand = realMuzzle + right * sideMul * sideDist
			if not Bridge.isMuzzleOriginValid(cand, realMuzzle) then continue end
			if Bridge.fastLosPoint(cand, aimPoint, targetPart) then
				local score = sideDist
				if score < bestScore then
					bestScore = score
					best = cand
				end
			end
		end
	end

	if best == realMuzzle then
		-- fallback: один полный LOS-check
		for _, sideMul in ipairs({ -1, 1 }) do
			for _, sideDist in ipairs({ 2.4 }) do
				local cand = realMuzzle + right * sideMul * sideDist
				if Bridge.isMuzzleOriginValid(cand, realMuzzle)
					and Bridge.hasClearShotToPoint(cand, aimPoint, targetPart) then
					best = cand
					break
				end
			end
		end
	end

	State.spoofedMuzzlePos = best
	State.spoofMuzzleCache[key] = { t = now, pos = best }
	return best
end

-- MultiPoint / WallBang: минимальный умный muzzle offset (без 12×24 stud brute-force)
function Bridge.resolveCombatMuzzleOffset(realMuzzle, aimPoint, targetPart)
	if typeof(realMuzzle) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return realMuzzle
	end
	if not CONFIG.LiteMultiPoint then
		return realMuzzle
	end
	if not State.inDischargeHook and not Bridge.isRecentCombatShot() and not State.inAimRefresh then
		return realMuzzle
	end
	if Bridge.hasSaDirectPath(realMuzzle, aimPoint, targetPart) then
		State.spoofedMuzzlePos = realMuzzle
		return realMuzzle
	end

	local now = os.clock()
	local key = Bridge.spoofMuzzleCacheKey(realMuzzle, aimPoint, targetPart)

	local spoof = select(1, Bridge.findLiteMultiPointShot(realMuzzle, aimPoint, targetPart, nil))
	if typeof(spoof) == "Vector3" then
		State.spoofedMuzzlePos = spoof
		State.combatMuzzleCache = State.combatMuzzleCache or {}
		State.combatMuzzleCache[key] = { pos = spoof, t = now }
		return spoof
	end

	State.combatMuzzleCache = State.combatMuzzleCache or {}
	local cached = State.combatMuzzleCache[key]
	if cached and now - (cached.t or 0) < 0.2 then
		State.spoofedMuzzlePos = cached.pos
		return cached.pos
	end

	local peek = Bridge.resolveSpoofedMuzzleOrigin(realMuzzle, aimPoint, targetPart)
	if peek ~= realMuzzle and Bridge.hasClearShotToPoint(peek, aimPoint, targetPart) then
		State.combatMuzzleCache[key] = { pos = peek, t = now }
		State.spoofedMuzzlePos = peek
		return peek
	end

	State.combatMuzzleCache[key] = { pos = realMuzzle, t = now }
	State.spoofedMuzzlePos = realMuzzle
	return realMuzzle
end

Bridge.resolveServerDischargeOrigin = Bridge.resolveCombatMuzzleOffset

local function smartWallRaycast(origin, target, params)
	local dir = target - origin
	if dir.Magnitude < 0.05 then return nil, nil, nil end
	local hit = Workspace:Raycast(origin, dir, params or Bridge.buildLosRayParams())
	if hit and hit.Instance then
		return hit.Position, hit.Normal, hit.Instance
	end
	return nil, nil, nil
end

-- Прямой raycast без глобального кэша — для внутреннего поиска позиции спуфа
local function fastLos(origin, target, part, params)
	local dir = target - origin
	if dir.Magnitude < 0.05 then return true end
	local hit = Workspace:Raycast(origin, dir, params)
	if not hit then return true end
	if part then
		if hit.Instance == part then return true end
		local model = part.Parent
		if model and hit.Instance:IsDescendantOf(model) then return true end
	end
	return false
end

-- Динамические шаги: от stepMin до maxDist с геометрическим ростом
local function buildSteps(maxDist, stepMin, growFactor)
	local out, s = {}, stepMin or 0.5
	local gf = growFactor or 1.85
	while s <= maxDist + 0.01 do
		out[#out+1] = s
		local ns = s * gf
		if ns > maxDist and out[#out] < maxDist - 0.1 then
			out[#out+1] = maxDist
		end
		s = ns
		if s > maxDist * 1.1 then break end
	end
	return out
end

-- Строим 12-направленный список (горизонт + вертикаль + диагонали)
-- Без предубеждения vertSign — все направления равноправны
local function buildDirs(wallNormal, muzzle, aimPoint)
	local up = Vector3.new(0, 1, 0)
	local peekH = wallNormal - Vector3.new(0, wallNormal.Y, 0)
	if peekH.Magnitude < 0.1 then
		local ta = aimPoint - muzzle
		peekH = Vector3.new(ta.X, 0, ta.Z)
	end
	if peekH.Magnitude < 0.01 then peekH = Vector3.new(1, 0, 0) end
	peekH = peekH.Unit
	local peekH2 = Vector3.new(-peekH.Z, 0, peekH.X)
	return {
		peekH, -peekH,
		peekH2, -peekH2,
		up, -up,
		(peekH  + up) * 0.7071, (peekH  - up) * 0.7071,
		(-peekH + up) * 0.7071, (-peekH - up) * 0.7071,
		(peekH2 + up) * 0.7071, (peekH2 - up) * 0.7071,
	}
end

-- legacy alias → resolveCombatMuzzleOffset (только MultiPoint / WallBang)
function Bridge.resolveSmartMuzzleOrigin(muzzle, aimPoint, targetPart)
	if not Bridge.shouldServerMuzzleSpoof() then
		return muzzle
	end
	return Bridge.resolveCombatMuzzleOffset(muzzle, aimPoint, targetPart)
end

function Bridge.estimateBulletFlightTime(origin, targetPos, bulletSpeed, drag)
	local dist = (targetPos - origin).Magnitude
	if dist < 0.05 or bulletSpeed <= 0 then return 0 end
	local t = dist / bulletSpeed
	if type(drag) == "number" and drag > 0 then
		for _ = 1, 3 do
			local avgVel = math.max(bulletSpeed - drag * t * 0.5, bulletSpeed * 0.35)
			t = dist / avgVel
		end
	end
	return t
end

function Bridge.getBulletDrag(ctx)
	if ctx and type(ctx.cal) == "table" and type(ctx.cal.Drag) == "number" then
		return ctx.cal.Drag
	end
	local calKey = ctx and ctx.info and ctx.info.caliber
	if type(calKey) == "string" then
		local mods = State.sharedModules or Bridge.loadSharedModules()
		local cal = mods and mods.Calibers and mods.Calibers[calKey]
		if type(cal) == "table" and type(cal.Drag) == "number" then
			return cal.Drag
		end
	end
	return nil
end

function Bridge.recordV138Patch(realMuzzle, aimPoint, pitch, yaw, patched, spoofedMuzzle)
	State.lastV138Patch = {
		t = os.clock(),
		realMuzzle = realMuzzle,
		spoofedMuzzle = spoofedMuzzle or realMuzzle,
		aim = aimPoint,
		pitch = pitch,
		yaw = yaw,
		ok = patched == true,
	}
		if CONFIG.LogV138Patch and patched then
		local sm = spoofedMuzzle or realMuzzle
		local spoofed = sm and realMuzzle and (sm - realMuzzle).Magnitude > 0.2
		local vel = State.shotAimTarget and Bridge.getActorRootVelocity(State.shotAimTarget, State.aimTargetUid) or Vector3.zero
		log(
			"AIM", "v138 patched",
			"| pitch", string.format("%.3f", pitch or 0),
			"| yaw", string.format("%.3f", yaw or 0),
			"| aim", aimPoint and string.format("%.1f,%.1f,%.1f", aimPoint.X, aimPoint.Y, aimPoint.Z) or "?",
			"| muzzleRay", sm and aimPoint and string.format("%.1f", (aimPoint - sm).Magnitude) or "?",
			"| vel", string.format("%.1f", vel.Magnitude),
			"| muzzleSpoof", spoofed and string.format("%.2f", (sm - realMuzzle).Magnitude) or "no"
		)
	end
end

function Bridge.patchV138ServerAim(v138)
	if type(v138) ~= "table" then return false end
	if not Bridge.needsServerAimPatch() then return false end

	-- 1. Извлечь muzzle из первого валидного pellet (pairs, т.к. v138 не гарантирован как array)
	local canonicalMuzzle
	for _, entry in pairs(v138) do
		if type(entry) == "table" and type(entry[2]) == "number" then
			canonicalMuzzle = Vector3.new(entry[2], entry[3], entry[4])
			break
		end
	end
	if typeof(canonicalMuzzle) ~= "Vector3" then return false end

	-- 2. Нулевой spread контекста
	local ctx = Bridge.getAimWeaponContext and Bridge.getAimWeaponContext(true)
		or Bridge.peekWeaponContext()
		or Bridge.getLiveWeaponContext(false)
	Bridge.zeroClientWeaponSpread(ctx)

	-- 3. Получить актуальную цель (не испо��ьзовать кеш — нам нужна позиция СЕЙЧАС)
	local target = State.shotAimTarget
	if not target or not target.Parent then
		target = Bridge.getCombatAimTarget(canonicalMuzzle, true)
	end
	if not target or not target.Parent then
		if CONFIG.LogV138Patch then
			log("AIM", "v138 not patched: no target")
		end
		return false
	end
	if CONFIG.MultiPoint and not State.mpShotReady then
		if CONFIG.LogV138Patch then
			log("AIM", "v138 not patched: multipoint no shot")
		end
		return false
	end
	local head = Bridge.getHeadPart(target.Parent, target) or target
	local uid = Bridge.resolveActorUidForPart(head, State.aimTargetUid)
	State.shotAimTarget = head
	State.aimTargetUid = uid or State.aimTargetUid

	-- 4. Вычислить СВЕЖУЮ точку прицеливания прямо сейчас, не из кеша burst
	local aimPoint = Bridge.computeFreshShotAimPoint(head, canonicalMuzzle, uid, ctx)
	if typeof(aimPoint) ~= "Vector3" then return false end

	State.forceHitPoint = aimPoint
	State.aimAimPoint = aimPoint
	State.shotBurstAimPoint = aimPoint

	-- 5. Патчить каждый pellet (pairs — не ipairs, т.к. v138 не обязательно 1..N)
	local patched = false
	local pelletCount = 0
	local firstPitch, firstYaw, spoofedMuzzleUsed

	for _, entry in pairs(v138) do
		if type(entry) ~= "table" then continue end
		local x, y, z = entry[2], entry[3], entry[4]
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then continue end

		local pelletMuzzle = Vector3.new(x, y, z)
		local aimOrigin = pelletMuzzle

		if Bridge.shouldServerMuzzleSpoof() then
			local peek = Bridge.resolveServerShotMuzzle(pelletMuzzle, aimPoint, head)
			if typeof(peek) == "Vector3" and (peek - pelletMuzzle).Magnitude > 0.05 then
				aimOrigin = peek
				entry[2], entry[3], entry[4] = peek.X, peek.Y, peek.Z
			end
		end

		local dir = aimPoint - aimOrigin
		if dir.Magnitude < 0.01 then continue end

		local cf = CFrame.lookAt(aimOrigin, aimPoint)
		local pitch, yaw = cf:ToOrientation()
		entry[5] = pitch
		entry[6] = yaw

		if not firstPitch then
			firstPitch, firstYaw = pitch, yaw
			spoofedMuzzleUsed = aimOrigin ~= pelletMuzzle and aimOrigin or nil
		end
		patched = true
		pelletCount += 1
	end

	if patched then
		Bridge.recordV138Patch(canonicalMuzzle, aimPoint, firstPitch, firstYaw, true, spoofedMuzzleUsed)
		if CONFIG.LogV138Patch then
			local vel = Bridge.getActorRootVelocity(head, uid)
			local lead = (aimPoint - head.Position).Magnitude
			log("AIM", "v138 patched",
				"| pellets", pelletCount,
				"| dist", string.format("%.1f", (aimPoint - canonicalMuzzle).Magnitude),
				"| lead", string.format("%.2f", lead),
				"| vel", string.format("%.1f", vel.Magnitude),
				"| pred", CONFIG.Prediction and "on" or "off")
		end
	else
		if CONFIG.LogV138Patch then
			log("AIM", "v138 not patched: no valid pellets in", type(v138), "len", #v138)
		end
	end
	return patched
end

-- Prediction: ballistic flight time (g=32.2) + lead по root velocity, без ping.
local BULLET_GRAVITY = 32.2

local function predictionFlightTime(muzzleOrigin, targetPos, bulletSpeed)
	if typeof(muzzleOrigin) ~= "Vector3" or typeof(targetPos) ~= "Vector3" or bulletSpeed <= 0 then
		return 0
	end
	return Bridge.brm5EstimateFlightTime(CFrame.lookAt(muzzleOrigin, targetPos), targetPos, bulletSpeed)
end

function Bridge.computeFreshShotAimPoint(head, muzzlePos, uid, ctx)
	if not head or not head:IsA("BasePart") or typeof(muzzlePos) ~= "Vector3" then
		return nil
	end
	ctx = ctx or Bridge.peekWeaponContext() or Bridge.getLiveWeaponContext(false)

	local aimBone = head
	local resolverPoint = nil
	if CONFIG.ResolverLite ~= false and head.Parent then
		local cam = getCamera()
		local expPart, expPoint = Bridge.resolveResolverLite(muzzlePos, head.Parent, uid, cam, nil)
		if expPart and expPart:IsA("BasePart") and expPart.Parent then
			aimBone = expPart
			resolverPoint = expPoint
		end
	end

	local basePos = typeof(resolverPoint) == "Vector3" and resolverPoint or aimBone.Position
	if CONFIG.Prediction ~= true then
		return basePos
	end

	local predicted = Bridge.predictAimPoint(uid, basePos, muzzlePos, Bridge.getBulletSpeed(ctx), aimBone, 0)
	if typeof(predicted) == "Vector3" then
		return predicted
	end
	return basePos
end

function Bridge.getBulletSpeed(ctx)
	if CONFIG.ModifyEnabled and CONFIG.ModifyPresets and CONFIG.ModifyPresets.BulletSpeed then
		local override = CONFIG.ModifyBulletSpeedValue
		if type(override) == "number" and override > 50 then
			return override
		end
	end
	-- v20: всегда пробуем получить живой контекст для точного логирования
	if not ctx then ctx = Bridge.peekWeaponContext() or Bridge.getLiveWeaponContext(false) end
	local function logSpeed(vel, source, calKey, barrel)
		if not CONFIG.LogBulletSpeed then return end
		local drag = Bridge.getBulletDrag(ctx) or 0
		log("BULLET", "speed=" .. tostring(vel) .. " src=" .. tostring(source)
			.. " cal=" .. tostring(calKey) .. " barrel=" .. tostring(barrel)
			.. " drag=" .. tostring(drag))
	end
	if ctx and ctx.info and ctx.info.caliber and ctx.tune then
		local calKey = ctx.info.caliber
		local barrel = ctx.tune.Barrel
		if type(calKey) == "string" and barrel ~= nil then
			local svc = Bridge.getBulletService()
			if svc and type(svc.GetInfo) == "function" then
				local ok, vel = pcall(svc.GetInfo, svc, calKey, barrel)
				if ok and type(vel) == "number" and vel > 50 then
					logSpeed(vel, "BulletService.GetInfo", calKey, barrel)
					return vel
				end
			end
			local mods = State.sharedModules or Bridge.loadSharedModules()
			local cal = mods and mods.Calibers and mods.Calibers[calKey]
			if type(cal) == "table" then
				if type(cal.Velocity) == "function" then
					local ok2, vel2 = pcall(cal.Velocity, barrel)
					if ok2 and type(vel2) == "number" and vel2 > 50 then
						logSpeed(vel2, "Calibers.Velocity(barrel)", calKey, barrel)
						return vel2
					end
				end
				if type(cal.BaseVelocity) == "number" and cal.BaseVelocity > 50 then
					logSpeed(cal.BaseVelocity, "Calibers.BaseVelocity", calKey, barrel)
					return cal.BaseVelocity
				end
				if type(cal.Speed) == "number" and cal.Speed > 50 then
					logSpeed(cal.Speed, "Calibers.Speed", calKey, barrel)
					return cal.Speed
				end
				if type(cal.MuzzleVelocity) == "number" and cal.MuzzleVelocity > 50 then
					logSpeed(cal.MuzzleVelocity, "Calibers.MuzzleVelocity", calKey, barrel)
					return cal.MuzzleVelocity
				end
				-- v17: все числовые поля не нашли — логируем какие поля есть
				if CONFIG.LogBulletSpeed then
					local fields = {}
					for k, v in pairs(cal) do
						if type(v) == "number" then
							fields[#fields+1] = k .. "=" .. tostring(v)
						end
					end
					log("BULLET", "cal fields: " .. table.concat(fields, ", "))
				end
			end
		end
	end
	local fallback = CONFIG.DefaultBulletSpeed or 920
	if CONFIG.LogBulletSpeed then
		local calKey = ctx and ctx.info and ctx.info.caliber or "nil"
		local barrel = ctx and ctx.tune and ctx.tune.Barrel
		log("BULLET", "speed=FALLBACK(" .. tostring(fallback) .. ") cal=" .. tostring(calKey) .. " barrel=" .. tostring(barrel))
	end
	return fallback
end

function Bridge.getPartVelocity(part)
	if not part then return Vector3.zero end
	local vel = part.AssemblyLinearVelocity
	if vel.Magnitude > 0.05 then return vel end
	local model = part.Parent
	if model and model:IsA("Model") then
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso")
		if root and root:IsA("BasePart") then
			return root.AssemblyLinearVelocity
		end
	end
	return vel
end

function Bridge.closestPointOnPart(part, from)
	local cf = part.CFrame
	local rel = cf:PointToObjectSpace(from)
	local h = part.Size * 0.5
	rel = Vector3.new(
		math.clamp(rel.X, -h.X, h.X),
		math.clamp(rel.Y, -h.Y, h.Y),
		math.clamp(rel.Z, -h.Z, h.Z)
	)
	return cf:PointToWorldSpace(rel)
end

function Bridge.resolveAimWorldPoint(part, origin, ctx)
	if not part then return nil end
	local center = part.Position
	if not CONFIG.SilentAimOnlySafe or Bridge.hasClearShot(origin, part) then
		return center
	end
	return nil
end

-- Utility functions shared between ESP, SA and Main


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

function Bridge.serializeHandlerDump(handler, depth, seen)
	if type(handler) ~= "table" then
		return Bridge.serializeDumpValue(handler, depth, seen)
	end
	seen = seen or {}
	local slim = {}
	for k, v in pairs(handler) do
		if k == "Replicator" then
			slim[k] = "<omitted>"
		elseif k == "_actor" then
			slim[k] = "<cycle>"
		else
			slim[k] = v
		end
	end
	return Bridge.serializeDumpValue(slim, depth or 0, seen)
end

function Bridge.serializeDumpValue(v, depth, seen)
	depth = depth or 0
	local maxDepth = CONFIG.DumpMaxDepth or 3
	if CONFIG.DumpQuickMode and depth >= maxDepth then return "<maxdepth>" end
	if depth > maxDepth then return "<maxdepth>" end
	if v == nil then return "nil" end
	local tv = typeof(v)
	if tv == "boolean" or tv == "number" then
		return tostring(v)
	end
	if tv == "string" then
		if #v > 96 then
			return string.format("%q...", string.sub(v, 1, 64))
		end
		return string.format("%q", v)
	end
	if tv == "Vector3" then
		return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
	end
	if tv == "Vector2" then
		return string.format("(%.1f, %.1f)", v.X, v.Y)
	end
	if tv == "CFrame" then
		local p = v.Position
		return string.format("pos(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
	end
	if tv == "Color3" then
		return string.format("rgb(%.2f, %.2f, %.2f)", v.R, v.G, v.B)
	end
	if typeof(v) == "Instance" then
		return string.format("<%s %s>", v.ClassName, v:GetFullName())
	end
	if type(v) == "function" then return "<function>" end
	if type(v) == "userdata" then return "<userdata>" end
	if type(v) == "table" then
		if seen[v] then return "<cycle>" end
		seen[v] = true
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		local limit = CONFIG.DumpQuickMode and (depth < 1 and 24 or (depth < 2 and 12 or 6)) or (depth < 2 and 48 or (depth < 4 and 20 or 8))
		for i = 1, math.min(#keys, limit) do
			local k = keys[i]
			parts[#parts + 1] = string.format("[%s]=%s", tostring(k), Bridge.serializeDumpValue(v[k], depth + 1, seen))
		end
		if #keys > limit then
			parts[#parts + 1] = "..."
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "<" .. tv .. ">"
end



function Bridge.copyTextToClipboard(text, tag)
	tag = tag or "dump"
	local copied = false
	if type(setclipboard) == "function" then
		copied = pcall(setclipboard, text)
	elseif type(toclipboard) == "function" then
		copied = pcall(toclipboard, text)
	end
	if copied then
		log("INIT", tag, "copied", #text, "chars")
	else
		log("INIT", tag, "clipboard unavailable,", #text, "chars")
		print(text)
	end
	return text, copied
end

function Bridge.copyWeaponDump()
	Bridge.perfCount("weaponDump")
	Bridge.invalidateWeaponCache()
	local ctx = Bridge.getLiveWeaponContext(true)
	if not ctx or not Bridge.weaponContextValid(ctx) then
		ctx = Bridge.buildWeaponContextFallback(true)
		if ctx and Bridge.weaponContextValid(ctx) then
			State.weaponCtxCache = ctx
			State.weaponCtxCacheTime = os.clock()
		end
	end
	local lines = { "=== WEAPON DUMP ===", os.date("%H:%M:%S") }
	if ctx and Bridge.weaponContextValid(ctx) then
		lines[#lines + 1] = "kind=" .. (ctx.isMelee and "melee" or "firearm")
		if ctx.fluxHandler then
			lines[#lines + 1] = "fluxSource=" .. tostring(ctx.fluxSource or "?")
			lines[#lines + 1] = "fluxHandler=" .. Bridge.serializeHandlerDump(ctx.fluxHandler, 0, {})
		end
		if ctx.tune then
			lines[#lines + 1] = "tune=" .. Bridge.serializeDumpValue(ctx.tune, 0, {})
		end
		if ctx.cal then
			lines[#lines + 1] = "cal=" .. Bridge.serializeDumpValue(ctx.cal, 0, {})
		end
		if ctx.meta then
			lines[#lines + 1] = "meta=" .. Bridge.serializeDumpValue(ctx.meta, 0, {})
		end
		if ctx.item then
			lines[#lines + 1] = "item=" .. Bridge.serializeDumpValue(ctx.item, 0, {})
		end
		if ctx.info then
			lines[#lines + 1] = "info=" .. Bridge.serializeDumpValue(ctx.info, 0, {})
		end
		if ctx.handler then
			lines[#lines + 1] = "handler=" .. Bridge.serializeHandlerDump(ctx.handler, 0, {})
		end
	else
		lines[#lines + 1] = "no weapon context"
		local mods = Bridge.loadSharedModules()
		local client, actor = Bridge.resolveLocalActor(true)
		if not client and actor then
			State.localClient = State.localClient or actor
			client = State.localClient
		end
		local owner = Bridge.resolvePlayerInventory(true)
		local slots = Bridge.mergeWeaponSlots(owner, mods, client)
		local hand, slot = Bridge.resolveEquippedHand(slots, mods, true)
		if hand then
			lines[#lines + 1] = "resolvedHand=" .. Bridge.firearmDisplayName(hand)
			lines[#lines + 1] = "resolvedSlot=" .. tostring(slot)
			lines[#lines + 1] = "item=" .. Bridge.serializeDumpValue(hand, 0, {})
			local handler = actor and Bridge.findEquippedHandlerForItem(actor, hand)
			if handler then
				lines[#lines + 1] = "handler=" .. Bridge.serializeHandlerDump(handler, 0, {})
			end
			local info = Bridge.parseFirearmItem(hand, slot or "Hand", mods, handler)
			if info then
				lines[#lines + 1] = "info=" .. Bridge.serializeDumpValue(info, 0, {})
			end
		end
		if actor then
			lines[#lines + 1] = "_equipped=" .. Bridge.serializeDumpValue(rawget(actor, "_equipped"), 0, {})
		end
		if State.methods.hand then
			lines[#lines + 1] = "via=" .. tostring(State.methods.hand)
		end
	end
	return Bridge.copyTextToClipboard(table.concat(lines, "\n"), "weapon")
end

function Bridge.copyLocalPlayerDump()
	resolveLocalClient(true)
	resolveLocalPlayer()
	local lines = { "=== LOCAL PLAYER ===", os.date("%H:%M:%S") }
	if State.localClient then
		lines[#lines + 1] = "client=" .. Bridge.serializeDumpValue(State.localClient, 0, {})
	end
	local owner = Bridge.resolvePlayerInventory(true)
	if owner then
		lines[#lines + 1] = "inventory=" .. Bridge.serializeDumpValue(owner, 0, {})
	end
	local lp = Players.LocalPlayer
	if lp and lp.Character then
		lines[#lines + 1] = "actorUID=" .. tostring(lp.Character:GetAttribute("ActorUID"))
		lines[#lines + 1] = "character=" .. lp.Character:GetFullName()
	end
	return Bridge.copyTextToClipboard(table.concat(lines, "\n"), "local")
end

function Bridge.buildActorInventoryDumpLines(actor)
	local lines = {}
	if type(actor) ~= "table" then return lines end
	local eq = rawget(actor, "_equipped")
	if eq ~= nil then
		lines[#lines + 1] = "_equipped=" .. Bridge.serializeDumpValue(eq, 0, {})
	end
	local inv = tableField(actor, "_inventory")
	if type(inv) == "table" then
		lines[#lines + 1] = "--- _inventory ---"
		local n = 0
		for slotUid, handler in pairs(inv) do
			n += 1
			if n > 12 then
				lines[#lines + 1] = "... +" .. tostring(n - 12) .. " more"
				break
			end
			local row = { "uid=" .. tostring(slotUid) }
			if type(handler) == "table" then
				local item = rawget(handler, "_item")
				if type(item) == "table" then
					row[#row + 1] = "name=" .. tostring(rawget(item, "Name"))
				end
				if rawget(handler, "_equipped") == true then row[#row + 1] = "equipped" end
				if rawget(handler, "_reloading") then row[#row + 1] = "reloading" end
				local mag = rawget(handler, "_mag")
				if type(mag) == "table" then
					local cap = rawget(mag, "Capacity")
					local maxC = rawget(mag, "MaxCapacity") or rawget(mag, "Max")
					if type(cap) == "number" then
						row[#row + 1] = "mag=" .. tostring(cap) .. "/" .. tostring(maxC or "?")
					end
				end
				local meta = type(item) == "table" and rawget(item, "MetaData") or nil
				if type(meta) == "table" and rawget(meta, "Chamber") == true then
					row[#row + 1] = "chambered"
				end
			end
			lines[#lines + 1] = table.concat(row, " ")
		end
	end
	local stateInv = tableField(tableField(actor, "CurrentState"), "Inventory")
	if type(stateInv) == "table" then
		local cnt = 0
		for _ in pairs(stateInv) do cnt += 1 end
		lines[#lines + 1] = "State.Inventory.count=" .. tostring(cnt)
	end
	return lines
end

function Bridge.buildActorDumpLines(uid, data)
	local lines = {
		"=== ACTOR " .. tostring(uid) .. " ===",
		os.date("%H:%M:%S"),
		"label=" .. tostring(data and data.label),
		"class=" .. tostring(data and data.class),
		"path=" .. tostring(data and data.path),
	}
	if not data then return lines end

	local hp, maxHp = Bridge.resolveActorHealth(data)
	lines[#lines + 1] = string.format("health=%s/%s", tostring(hp), tostring(maxHp))

	local actor = data.actorData
	if not actor and uid then
		actor = Bridge.getReplicatorActorData(uid)
	end
	local actorPos = type(actor) == "table" and tableField(actor, "Position") or nil
	if type(actor) == "table" then
		lines[#lines + 1] = "--- actor ---"
		if typeof(actorPos) == "Vector3" then
			lines[#lines + 1] = string.format(
				"actorPos=%.1f,%.1f,%.1f",
				actorPos.X, actorPos.Y, actorPos.Z
			)
		end
		local hs = tableField(actor, "HeightState")
		if type(hs) == "number" then
			local hsLabel = ({ [0] = "stand", [1] = "crouch", [2] = "prone" })[hs] or tostring(hs)
			lines[#lines + 1] = "HeightState=" .. tostring(hs) .. " (" .. hsLabel .. ")"
		end
		local actorKeys = {
			"Focused", "ADS", "Sprinting", "Sliding", "Swimming", "CQB", "Firearm",
			"Weight", "Alive", "Locked", "_equipped", "_reloading",
			"AnimationKit", "AnimationState", "ProneDelay", "SpeedPenalty",
			"CFrame", "RootCFrame", "WorldPosition", "_position",
			"NavPosition", "TargetPosition", "SpawnPosition", "IsLocalPlayer",
			"Character", "Ragdoll", "LOD", "_lod", "Loaded", "_loaded", "Visible",
		}
		for _, key in ipairs(actorKeys) do
			local v = tableField(actor, key)
			if v ~= nil then
				lines[#lines + 1] = key .. "=" .. Bridge.serializeDumpValue(v, 0, {})
			end
		end
		for _, invLine in ipairs(Bridge.buildActorInventoryDumpLines(actor)) do
			lines[#lines + 1] = invLine
		end
		local state = tableField(actor, "CurrentState")
		if type(state) == "table" then
			lines[#lines + 1] = "--- CurrentState ---"
			local stateKeys = {}
			for k in pairs(state) do stateKeys[#stateKeys + 1] = k end
			table.sort(stateKeys, function(a, b) return tostring(a) < tostring(b) end)
			for _, sk in ipairs(stateKeys) do
				local sv = state[sk]
				if sk == "Inventory" and type(sv) == "table" then
					local n = 0
					for _ in pairs(sv) do n += 1 end
					lines[#lines + 1] = "State.Inventory items=" .. tostring(n)
				else
					lines[#lines + 1] = "State." .. tostring(sk) .. "=" .. Bridge.serializeDumpValue(sv, 0, {})
				end
			end
		end
		local vm = tableField(actor, "ViewModel")
		if type(vm) == "table" then
			lines[#lines + 1] = "ViewModel=" .. Bridge.serializeDumpValue(vm, 0, {})
		end
	end

	if data.root and data.root:IsA("BasePart") then
		lines[#lines + 1] = string.format(
			"rootPos=%.1f,%.1f,%.1f",
			data.root.Position.X, data.root.Position.Y, data.root.Position.Z
		)
	end
	local localRoot = State.localModel and (
		State.localModel:FindFirstChild("HumanoidRootPart") or State.localModel:FindFirstChild("UpperTorso")
	)
	if localRoot and localRoot:IsA("BasePart") then
		local refPos = (data.root and data.root:IsA("BasePart") and data.root.Position)
			or (typeof(actorPos) == "Vector3" and actorPos)
		if typeof(refPos) == "Vector3" then
			lines[#lines + 1] = string.format("dist=%.0f studs", (refPos - localRoot.Position).Magnitude)
		end
	end
	if data.model and data.model.Parent then
		local hrp = data.model:FindFirstChild("HumanoidRootPart") or data.model:FindFirstChild("UpperTorso")
		if hrp and hrp:IsA("BasePart") then
			lines[#lines + 1] = string.format(
				"modelPos=%.1f,%.1f,%.1f",
				hrp.Position.X, hrp.Position.Y, hrp.Position.Z
			)
		end
	end
	local velInstant = State.actorVelInstant and State.actorVelInstant[uid]
	if typeof(velInstant) == "Vector3" then
		lines[#lines + 1] = string.format(
			"velEst=%.1f,%.1f,%.1f speed=%.1f",
			velInstant.X, velInstant.Y, velInstant.Z, velInstant.Magnitude
		)
	end
	if not data.model and type(actor) == "table" then
		lines[#lines + 1] = "model=nil (actor data without Character model — check Position/CurrentState above)"
	end

	if data.model and data.model.Parent then
		lines[#lines + 1] = "model=" .. data.model:GetFullName()
		local attrs = {}
		for name, value in data.model:GetAttributes() do
			attrs[#attrs + 1] = name .. "=" .. tostring(value)
		end
		if #attrs > 0 then
			table.sort(attrs)
			lines[#lines + 1] = "modelAttrs=" .. table.concat(attrs, ", ")
		end
	end

	if data.player then
		lines[#lines + 1] = "player=" .. tostring(data.player.Name)
	end
	if data.squad ~= nil then
		lines[#lines + 1] = "squad=" .. Bridge.serializeDumpValue(data.squad, 0, {})
	end
	if data.teamKey ~= nil then
		lines[#lines + 1] = "teamKey=" .. tostring(data.teamKey)
	end
	if data.collisionGroup then
		lines[#lines + 1] = "collisionGroup=" .. tostring(data.collisionGroup)
	end

	if not Bridge.isNpcActorClass(data.class) then
		Bridge.refreshActorWeaponInfo(data)
		if data.weaponInfo then
			lines[#lines + 1] = "weaponInfo=" .. Bridge.serializeDumpValue(data.weaponInfo, 0, {})
		end
	end

	local status = Bridge.getActorStatusEntries(data)
	if #status > 0 then
		local parts = {}
		for _, e in ipairs(status) do
			parts[#parts + 1] = e.text .. "(" .. tostring(e.kind) .. ")"
		end
		lines[#lines + 1] = "espStatus=" .. table.concat(parts, ", ")
	end

	lines[#lines + 1] = "--- cache ---"
	lines[#lines + 1] = "visible=" .. tostring(data.visible)
	lines[#lines + 1] = "dead=" .. tostring(data.dead)
	lines[#lines + 1] = "alive=" .. tostring(data.alive)
	return lines
end

function Bridge.copyRandomActorDump()
	local players, others = {}, {}
	for uid, data in pairs(State.actors or {}) do
		if not data or data.class == "self" then continue end
		local hasModel = data.model and data.model.Parent
		local hasActor = type(data.actorData) == "table"
		if not hasModel and not hasActor then continue end
		if data.class == "player" then
			players[#players + 1] = { uid = uid, data = data }
		else
			others[#others + 1] = { uid = uid, data = data }
		end
	end
	local pool = #players > 0 and players or others
	if #pool == 0 then
		return Bridge.copyTextToClipboard("no actors in cache", "actor")
	end
	local picks = {}
	local want = math.min(3, #pool)
	local used = {}
	for _ = 1, want do
		local idx = math.random(1, #pool)
		if used[idx] then
			for i = 1, #pool do
				if not used[i] then idx = i break end
			end
		end
		used[idx] = true
		picks[#picks + 1] = pool[idx]
	end
	local chunks = {}
	for i, pick in ipairs(picks) do
		chunks[#chunks + 1] = table.concat(Bridge.buildActorDumpLines(pick.uid, pick.data), "\n")
	end
	return Bridge.copyTextToClipboard(table.concat(chunks, "\n\n"), "actors")
end

function Bridge.copyClientDump()
	local text = Bridge.buildClientDumpText()
	return Bridge.copyTextToClipboard(text, "client")
end

function Bridge.getActorRootVelocity(part, uid)
	uid = type(uid) == "string" and uid or nil
	-- FIX v9: обновляем velocity track при каждом вызове
	if uid and part and part.Parent then
		local model = part.Parent
		local root = model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChild("UpperTorso")
			or part
		if root and root:IsA("BasePart") then
			updateActorVelocity(uid, root)
		end
	end
	-- FIX v9: EMA velocity — приоритетный источник
	-- Threshold 0.5 (было 0.08) — убирает physics drift стоящего игрока
	if uid and State.actorVelInstant[uid] then
		local est = State.actorVelInstant[uid]
		if est.Magnitude > 0.5 then return est end
	end
	-- FIX v9: AssemblyLinearVelocity как fallback с threshold 0.5
	-- MoveDirection * WalkSpeed убран — даёт неверное значение при торможении/зиг-заге
	if not part or not part:IsA("BasePart") then return Vector3.zero end
	local model = part.Parent
	if model and model:IsA("Model") then
		local root = model:FindFirstChild("HumanoidRootPart")
			or model:FindFirstChild("UpperTorso")
		if root and root:IsA("BasePart") then
			local vel = root.AssemblyLinearVelocity
			if vel.Magnitude > 0.5 then return vel end
		end
	end
	local vel = part.AssemblyLinearVelocity
	if vel.Magnitude > 0.5 then return vel end
	return Vector3.zero
end

function Bridge.ballisticOffsetAtTime(pitch, velocity, t)
	if t <= 0 or velocity <= 0 then
		return Vector3.zero
	end
	local cosA = math.cos(pitch)
	local tanA = math.tan(pitch)
	local divConstant = 1 / (2 * velocity * velocity * cosA * cosA)
	local travel = cosA * velocity * t
	return Vector3.new(0, travel * tanA - BULLET_GRAVITY * travel * travel * divConstant, -travel)
end

function Bridge.worldBallisticPoint(originCFrame, velocity, t)
	if typeof(originCFrame) ~= "CFrame" or t <= 0 then
		return originCFrame and originCFrame.Position
	end
	local pitch = select(1, originCFrame:ToOrientation())
	local _, yaw = originCFrame:ToOrientation()
	local horizontal = CFrame.new(originCFrame.Position) * CFrame.Angles(0, yaw, 0)
	return horizontal:PointToWorldSpace(Bridge.ballisticOffsetAtTime(pitch, velocity, t))
end

function Bridge.brm5EstimateFlightTime(originCFrame, targetPos, velocity)
	if typeof(originCFrame) ~= "CFrame" or typeof(targetPos) ~= "Vector3" or velocity <= 0 then
		return 0
	end
	local dist = (targetPos - originCFrame.Position).Magnitude
	if dist < 0.05 then return 0 end
	local t = dist / velocity
	for _ = 1, 8 do
		local sample = Bridge.worldBallisticPoint(originCFrame, velocity, t)
		local remain = (targetPos - sample).Magnitude
		if remain < 0.06 then break end
		t += remain / math.max(velocity * 0.92, 120)
	end
	return math.clamp(t, 0, 6)
end

function Bridge.predictAimPoint(uid, currentPos, origin, bulletSpeed, part, _extraTime)
	-- ЛЁГКИЙ предикт (тест): просто pos + velocity * t, без оружия/баллистики.
	-- Работает независимо от CONFIG.Prediction и подменяет его, когда включён.
	if CONFIG.PredictionLite == true and typeof(currentPos) == "Vector3"
		and part and part:IsA("BasePart") then
		local uidL = Bridge.resolveActorUidForPart(part, uid)
		-- Принудительно обновляем EMA-трек скорости перед чтением
		if uidL and part.Parent then
			local root = part.Parent:FindFirstChild("HumanoidRootPart")
				or part.Parent:FindFirstChild("UpperTorso")
				or part
			if root and root:IsA("BasePart") then
				pcall(updateActorVelocity, uidL, root)
			end
		end
		local vel = Bridge.getActorRootVelocity(part, uidL)
		local t = tonumber(CONFIG.PredictionLiteTime) or 0.12
		local lead = vel * t  -- полная скорость (X,Y,Z), без клампа и гравитации
		return currentPos + lead, lead, t
	end
	if CONFIG.Prediction ~= true or typeof(currentPos) ~= "Vector3" then
		return currentPos, Vector3.zero, 0
	end
	if not part or not part:IsA("BasePart") then
		return currentPos, Vector3.zero, 0
	end
	uid = Bridge.resolveActorUidForPart(part, uid)
	bulletSpeed = tonumber(bulletSpeed)
	if not bulletSpeed or bulletSpeed <= 0 then
		local pctx = Bridge.peekWeaponContext()
		bulletSpeed = pctx and Bridge.getBulletSpeed(pctx) or (CONFIG.DefaultBulletSpeed or 920)
	end
	if bulletSpeed <= 0 then bulletSpeed = CONFIG.DefaultBulletSpeed or 920 end

	local muzzleOrigin = typeof(origin) == "Vector3" and origin or nil
	if not muzzleOrigin then
		local cam = getCamera()
		muzzleOrigin = cam and cam.CFrame.Position or currentPos
	end

	local vel = Bridge.getActorRootVelocity(part, uid)
	local horiz = Vector3.new(vel.X, 0, vel.Z)
	local velMag = horiz.Magnitude
	local velCap = CONFIG.PredictionMaxVelCap or 35  -- studs/s, ~WalkSpeed*2
	local velScaled = velMag > velCap and horiz * (velCap / velMag) or horiz
	-- FIX v23: глобальный масштаб предикта. Для медленных оружий уменьши
	-- PredictionScale (0.6-0.8) — иначе большой tFlight даёт избыточный lead.
	local predScale = math.clamp(CONFIG.PredictionScale or 1.0, 0.0, 2.0)
	if predScale ~= 1.0 then velScaled = velScaled * predScale end

	-- FIX v23 (вертикальный prediction завышал аим над головой):
	--   Было: линейный vertVel * t. Он игнорировал гравитацию, поэтому по
	--   прыгающей/падающей цели точка улетала ВЫШЕ головы (цель тормозит на
	--   взлёте / ускоряется на падении — линейная экстраполяция переоценивает Y),
	--   а по стоящей на земле ловил physics-джиттер vel.Y и слегка приподнимал аим.
	--   Стало: opt-in (== true), гравитационная кинематика Δy = vy*t − ½·g·t²,
	--   гейт по минимальной вертикальной скорости (игнор джиттера) и жёсткий
	--   кламп смещения, чтобы аим НИКОГДА не уходил заметно выше головы.
	local doVert   = CONFIG.PredictionVertical == true
	local vcap     = CONFIG.PredictionVertCap or 50
	local vy       = doVert and math.clamp(vel.Y, -vcap, vcap) or 0
	if doVert and math.abs(vy) <= (CONFIG.PredictionVertMinVel or 8) then
		vy = 0  -- цель по сути на земле: не трогаем вертикаль, целимся в голову
	end
	local gChar    = (Workspace and Workspace.Gravity) or 196.2
	local vMaxOff  = CONFIG.PredictionVertMaxOffset or 2.5  -- studs, ~радиус головы
	local function vertLead(t)
		if vy == 0 or t <= 0 then return 0 end
		return math.clamp(vy * t - 0.5 * gChar * t * t, -vMaxOff, vMaxOff)
	end

	-- FIX: PingCompensation убрана из базового предикта — сервер игры сам компенсирует RTT.
	-- Итеративная сходимость: время полёта зависит от ПРЕДСКАЗАННОЙ позиции, а не текущей.
	-- Один проход недооценивал lead для целей, движущихся от/к стрелку.
	local iters = math.max(1, CONFIG.PredictionIterations or 3)
	local tTotal = predictionFlightTime(muzzleOrigin, currentPos, bulletSpeed)
	local predicted = currentPos
	for _ = 1, iters do
		predicted = currentPos + velScaled * tTotal + Vector3.new(0, vertLead(tTotal), 0)
		tTotal = predictionFlightTime(muzzleOrigin, predicted, bulletSpeed)
	end
	predicted = currentPos + velScaled * tTotal + Vector3.new(0, vertLead(tTotal), 0)

	-- Опциональная ping-компенсация (доля RTT сверху), по умолчанию выключена.
	if CONFIG.PingCompensation == true then
		local pingMs = (type(Bridge.getLocalPingMs) == "function" and Bridge.getLocalPingMs()) or 0
		local pingLead = math.clamp(pingMs / 1000, 0, 0.2) * (CONFIG.PingCompensationScale or 0.5)
		predicted = predicted + velScaled * pingLead
		tTotal = tTotal + pingLead
	end
	return predicted, velScaled, tTotal
end

function Bridge.predictActorPosition(uid, currentPos, bulletSpeed, extraTime, originHint)
	local origin = originHint
	if typeof(origin) ~= "Vector3" then
		local cam = getCamera()
		origin = cam and cam.CFrame.Position or currentPos
	end
	return Bridge.predictAimPoint(uid, currentPos, origin, bulletSpeed, nil, extraTime)
end

function Bridge.getActorDisplayName(data)
	if not data then return "?" end
	if data.label and data.label ~= "" then return data.label end
	local model = data.model
	if model then
		local name = model.Name
		if type(name) == "string" and name ~= "" then return name end
	end
	if data.uid then return tostring(data.uid):sub(1, 8) end
	return "?"
end

function Bridge.buildClientDumpText()
	local lines = {}
	local actors = State.actors or {}
	for uid, data in pairs(actors) do
		if data.label then
			lines[#lines + 1] = uid .. ": " .. tostring(data.label)
				.. " hp=" .. tostring(data.health or "?")
				.. " class=" .. tostring(data.class or "?")
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end


-- v1: экспорт internal функций для модулей SilentAim и ESP
-- ============================================================
Bridge.CONFIG                 = CONFIG
Bridge.queueFullActorScan         = Bridge.queueFullActorScan
Bridge.tickActorScan              = Bridge.tickActorScan
Bridge.computeForceHitTimeOff     = Bridge.computeForceHitTimeOff
Bridge.getBacktrackSec            = Bridge.getBacktrackSec
Bridge.applyBacktrackOffset       = Bridge.applyBacktrackOffset
Bridge.shouldUseBacktrackAim      = Bridge.shouldUseBacktrackAim
Bridge.computeBacktrackWorldPoint = Bridge.computeBacktrackWorldPoint
Bridge.formatEspLabelWithDistance = Bridge.formatEspLabelWithDistance
Bridge.shouldSkipActorCollect     = Bridge.shouldSkipActorCollect
Bridge.lightSyncReplicatorActors = tickRepSyncBatch
Bridge.tickRepSyncBatch         = tickRepSyncBatch
Bridge._scanActors            = scanActors
Bridge._refreshActorsForEsp   = refreshActorsForEsp
Bridge._printSummary          = printSummary
Bridge._getCamera             = getCamera
Bridge._log                   = log
Bridge._mpActive              = mpActive
Bridge._getMultiPointMode       = Bridge.getMultiPointMode
Bridge._setMultiPointMode       = Bridge.setMultiPointMode
Bridge._tableField            = tableField
Bridge._getGcCached           = getGcCached
Bridge._RS                    = RS
Bridge._RF                    = RF
Bridge._RunService            = RunService
Bridge._FIREMODE              = FIREMODE
Bridge._HttpService           = HttpService
Bridge._Players               = Players

Bridge._resolveLocalClient    = resolveLocalClient
Bridge._resolveLocalPlayer    = resolveLocalPlayer


-- ============================================================
-- Return
-- ============================================================
local BRM5Lib = {
	Bridge  = Bridge,
	CONFIG  = CONFIG,
	State   = State,
	version = "BRM5Lib_v1",
}
return BRM5Lib
