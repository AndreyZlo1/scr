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
local Config = {
	Version       = "V167",
	Enabled       = false,
	Mode          = "Perfect",

	Range         = 36,
	RequireFacing = false,
	IncludeNPCs   = true,
	HeavyEnabled  = true,

	M1Forward     = 4,
	M2Forward     = 3,
	HitboxDepth   = 4.0,
	HitboxDepthBack = 1.0,
	HitHalfWidth  = 3.0,
	HitboxSlack   = 0.5,
	HighSlack     = 0.35,
	HighReachPad  = 2.0,
	HighFaceFloor = -0.15,
	WillHitLeadFrac = 0.90,
	FilterFailSafe= true,

	AccuracyMode  = "High",

	WillHitVelCap   = 2.0,
	WillHitCloseCap = 12,
	WillHitLatCap   = 1.5,

	FeintFrac     = 0.80,
	FeintGraceMs  = 90,

	ComboEscape        = true,
	ComboEscapeDodge   = true,
	DodgeOnParryCooldown = true,
	StunReleaseLead    = 0.14,
	GuardbreakProtect  = true,
	StaminaFloor       = 18,
	StaminaAttrs       = { "Stamina", "BlockStamina", "GuardStamina", "Posture", "Guard" },

	PerfectWindow = 0.15,
	PerfectMin    = 0.05,
	PerfectLead   = 0.0625,
	HoldAfter     = 0.12,
	HoldLateGrace = 0.14,

	PerHitRearm   = true,
	BlockFaceHard   = true,
	BlockFaceHardDt = 0.30,

	M2WidenWindow = false,
	M2WidenFront  = 0.22,
	M2WidenHold   = 0.10,

	HitboxDodge     = true,

	ChargeStallMs = 45,
	ReleaseGap    = 0.40,

	FaceGateBlock = true,
	FaceGateMin   = 0.2,

	UplinkFactor  = 1.0,
	UplinkMargin  = 0.008,
	UplinkMin     = 0.010,
	LowPingFloor   = 0.030,
	LowPingThresh  = 0.090,
	UplinkMax     = 0.500,
	PingCap       = 0.500,
	PingSourceMaxRatio = 2.5,
	PingWindow    = 24,
	PingSampleGap = 0.03,

	MoveLeadMax   = 0.045,
	MoveSpeedFull = 22,

	MaxWait       = 1.6,

	MinActGap     = 0.004,
	MinDeactGap   = 0.050,

	MatchWindow   = 1.30,
	MultiHitWindow = 1.30,

	AutoDodge     = true,
	DodgeHeavy    = true,
	FOV           = 360,

	MustDodge       = true,
	MustDodgeAutoGrab = true,
	MustDodgeStyles = {
		wrestling = { M2 = true },
		kure = { M2 = true },
	},

	IFrameDur     = 0.30,
	DodgeLead     = 0.10,
	UseServerCooldown = true,
	DodgeCooldown = 2.05,
	DodgeMinSpacing = 0.35,
	OutnumberEscape = true,
	ExposedEscapeDodge = true,
	ExposedDodgeWindow = 0.28,
	ExposedEscapeAttackOnly = true,
	OutnumberEscapePreferBlock = true,
	DashSpeed     = 30,
	MaxHeightDiff = 12,
	DashDuration  = 0.20,
	DodgeConfirm  = 0.18,
	DodgeCenter   = true,
	HeavyDodgeInset = 0.075,
	DodgeCenterBias = 0.00,
	HeavyDodgeBias  = 0.00,
	FrameLookahead   = 0.5,
	FrameLookaheadCap= 0.045,
	FrameLookaheadPeakK  = 0.50,
	FrameLookaheadPeakDecay = 1.10,
	FrameLookaheadCapK   = 0.75,
	FrameLookaheadCapHi  = 0.11,
	FrameStepCostComp    = 0.60,
	SmartDodgeDir = true,
	DodgeWallCheck = true,
	DodgeWallDist  = 8,

	DodgeHardStates = { "Ragdoll", "Downed", "Knocked", "KnockedDown", "Grabbed", "Carried",
	                    "Frozen", "Sitting", "Cutscene", "Greenzone", "RpCombatLocked",
	                    "StaffModPeaceMode" },
	NoDodgeWhileStunned = true,
	DodgeTelemetry  = true,

	LiveHeavyTimer    = true,
	LiveSpeedFloor    = 0.15,
	LiveSpeedSmooth   = 0.35,
	LiveM1Timer       = true,
	LiveM1SpeedFloor  = 0.45,

	EmergencyDualDodge = true,
	MultiDodgeCover = true,
	MultiDodgeConfirmSlack = 0.03,
	TurnRateDegPerSec  = 720,
	RearmBudget        = 0.06,
	DualDodgeMaxGap     = 0.22,

	DeepDiag           = true,

	BoxingCounter     = false,
	BoxingCounterReach= 5.5,
	BoxingCounterGap  = 0.30,
	AliCounter        = false,
	AliCounterReach   = 7.5,
	AliM2Variant      = "Left",
	AliProcTTLFrac    = 0.25,
	AliProcTTLMax     = 1.5,
	AliVariantSteerDur= 0.15,
	AliEvasiveCounter = false,
	AliDodgeAbuse     = false,
	CounterPreemptsDodge = true,
	DodgeCenterFrac   = 0.5,

	SkillAddon        = true,
	SA_WrestlingGrab  = true,
	SA_DirtyGrab      = true,
	SA_HakariRead     = true,
	SA_HakariWiden    = 0.05,
	SA_BlatantDodge   = false,
	SA_BlatantWindow  = 0.32,

	AutoPlay          = false,
	AP_PunishOnParry  = true,
	AP_Interrupt      = true,
	AP_InterruptMargin= 0.055,
	AP_InterruptNetK  = 0.50,
	AP_BaseReach      = 5.5,
	AP_RefHeight      = 5.5,
	AP_InterruptM2       = true,
	AP_InterruptPreferM2 = true,
	AP_M2BaseReach       = 6.5,
	AP_M2Gap             = 0.30,
	AP_M2IFrameMargin    = 0.035,
	AP_AnimGuard    = true,
	AP_AnimFallback = 0.45,
	AP_MaxPerSec      = 8,
	AP_MinSendGap     = 0.08,
	AP_PunishFastGap  = 0.08,
	AP_M2Stun         = 1.0,
	AP_M1Stun         = 0.5,
	AP_PollGap        = 0,
	AP_FaceHold       = 0.35,
	AP_ComboMode      = "Follow",
	AP_FixedHit       = 1,

	RequireEquip      = true,

	RestrictZone      = true,
	RestrictLongOnly  = true,
	RestrictMinWindup = 0.30,
	RestrictPad       = 2.0,
	RestrictSoft      = true,
	RestrictShowZone  = true,

	SelfBusyDur     = 0.45,

	DesyncAttack   = false,
	DesyncMode     = "delay",
	DesyncDelayMs  = 140,
	DesyncDecoyId  = 507766388,
	DesyncApplyM1  = true,
	DesyncApplyM2  = true,
	AntiDecoy      = true,
	AntiDecoyGap   = 0.12,
	AntiDecoyMaxBurst = 3,
	DecoyRefireSec  = 0.60,
	DecoySpeedMin   = 0.30,
	DecoySpeedMax   = 1.25,
	DecoySpeedTol   = 0.50,
	DecoyHardDrop   = true,
	DecoySweepSec   = 5,
	DecoySeenMax    = 512,
	ServerProofGate = true,
	ProofGraceSec   = 0.06,
	TimeSpoof    = false,
	TimeShiftMs  = 40,
	DesyncClientVisible = false,
	DesyncSendHz      = 0,
	InvisibleOn    = false,
	InvisibleHeight= 0,
	InvisibleAnim  = true,

	BoxingFaceLockDur = 0.55,
	AliFaceLockDur = 0.75,

	MultiThreatGuard  = true,
	MultiThreatMinN   = 2,
	BlockCooldown     = 0.50,
	SequentialSpread  = 0.78,
	MultiFaceAngleMax = 70,
	MultiFaceJitter   = 0.30,
	MultiFaceOnlyFront= true,
	DesyncSafeDecoy   = true,

	AntiCheatBypass = true,
	HideHooks       = true,
	MuteAC          = true,
	BlockKick       = true,
	BlockACReports  = true,
	ACScriptName    = "so you're challenging me",
	NeutralizeAC    = true,

	MultiFaceHard     = true,

	DodgeHorizon      = 0.34,
	MinBlockSeparation= 0.17,
	DodgeArmWindow    = 0.05,

	LegitAnims    = true,

	AutoFace      = true,
	FaceLerp      = 0.80,
	FaceLeadWindow= 0.30,
	FaceGoodDot   = 0.55,
	FaceLead      = 0.07,
	FaceLeadMax   = 4,
	FacePingLead  = 1.0,
	FaceLeadCap   = 0.28,
	FaceLeadMaxStuds = 16,
	FaceLatMaxStuds = 18,
	FaceRadMaxStuds = 5,

	OmniBlock      = true,

	ShowVisuals   = true,
	VizRing       = true,
	VizRingStyle  = "Flat",
	VizRingSeg    = 30,
	VizRingMirror = true,
	VizRingTilt   = 0.7,
	RotationMethod = "LookAt",
	AimLockLerp    = 0.35,
	VizHitbox     = true,
	VizRestrict   = true,
	VizRingSpeed  = 1.0,
	VizRingScale  = 1.0,
	VizRange      = 100,
	VizMaxFPS     = 60,
	VizAutoDegrade   = true,
	VizFrameShare    = 1.5,
	VizSkipNearPress = 0.20,
	VizSkipMaxFrames = 2,
	Debug         = true,

	Key_Toggle    = Enum.KeyCode.K,
	Key_Mode      = Enum.KeyCode.N,
	Key_Desync    = Enum.KeyCode.J,
	Key_Boxing    = Enum.KeyCode.V,
	Key_Double    = Enum.KeyCode.H,
	Key_Face      = Enum.KeyCode.G,
	Key_LogDump   = Enum.KeyCode.L,
	Key_Save      = Enum.KeyCode.P,
	Key_ACScan    = Enum.KeyCode.O,
	Key_DesyncSave = Enum.KeyCode.Semicolon,
	Key_DesyncTest = Enum.KeyCode.LeftBracket,
	Key_DesyncMode = Enum.KeyCode.RightBracket,
	AutoScanAC    = false,
	Key_Panel     = Enum.KeyCode.RightShift,
}

local LEGACY_ATTACKS = {
	[134707728784991]={t="M1",d=0.32,s="Base"},   [113403744416180]={t="M1",d=0.32,s="Base"},
	[112448114445008]={t="M1",d=0.32,s="Base"},   [84015695249789]={t="M1",d=0.32,s="Base"},
	[89985804943092]={t="M2",d=0.30,s="Base"},
	[95267170062803]={t="M1",d=0.32,s="Basic"},   [95363684987743]={t="M1",d=0.32,s="Basic"},
	[139875456638239]={t="M1",d=0.32,s="Basic"},  [133112087379005]={t="M1",d=0.32,s="Basic"},
	[128479795877497]={t="M2",d=0.525,s="Basic"},
	[73977397773505]={t="M1",d=0.32,s="Boxing"},  [140559915903523]={t="M1",d=0.32,s="Boxing"},
	[82475370801539]={t="M1",d=0.32,s="Boxing"},  [82164598010704]={t="M1",d=0.32,s="Boxing"},
	[103379337847201]={t="M2",d=0.43,s="Boxing"},
	[97280263199117]={t="M1",d=0.33,s="Capoeira"},[136563726541554]={t="M1",d=0.33,s="Capoeira"},
	[127253080182564]={t="M1",d=0.33,s="Capoeira"},[85098647244472]={t="M1",d=0.33,s="Capoeira"},
	[114254289386168]={t="M2",d=0.45,s="Capoeira"},
	[95359912376713]={t="M1",d=0.32,s="Hakari"},  [127631232991111]={t="M1",d=0.32,s="Hakari"},
	[71447243477669]={t="M1",d=0.32,s="Hakari"},  [73898520591442]={t="M1",d=0.32,s="Hakari"},
	[137330597899886]={t="M2",d=0.59,s="Hakari"},
	[103814914375577]={t="M2",d=0.62,s="Hakari",mom=true},
	[82516160136439]={t="M1",d=0.32,s="HakariO"}, [110796329013101]={t="M1",d=0.32,s="HakariO"},
	[95399554089638]={t="M1",d=0.32,s="HakariO"}, [79161155390140]={t="M1",d=0.32,s="HakariO"},
	[74345026218889]={t="M2",d=0.62,s="HakariO"},
	[77957614227468]={t="M1",d=0.24,s="Karate"},  [105109868069470]={t="M1",d=0.24,s="Karate"},
	[86918714359440]={t="M1",d=0.24,s="Karate"},  [111317285324171]={t="M1",d=0.24,s="Karate"},
	[130884585830171]={t="M2",d=0.4875,s="Karate"},
	[87171697393871]={t="M1",d=0.30,s="MuayThai"},[140530278540076]={t="M1",d=0.30,s="MuayThai"},
	[73865503612362]={t="M1",d=0.30,s="MuayThai"},[75692393601509]={t="M1",d=0.30,s="MuayThai"},
	[101188641038819]={t="M2",d=0.60,s="MuayThai"},
	[135304344348112]={t="M1",d=0.20,s="Slugger"},[136278929175728]={t="M1",d=0.20,s="Slugger"},
	[73329541283787]={t="M1",d=0.20,s="Slugger"}, [83785650808219]={t="M1",d=0.20,s="Slugger"},
	[116328113967477]={t="M2",d=0.82,s="Slugger"},
	[132178222366446]={t="M1",d=0.32,s="Wrestling"},[128114472490928]={t="M1",d=0.32,s="Wrestling"},
	[138624221040888]={t="M1",d=0.32,s="Wrestling"},[103849336431154]={t="M1",d=0.32,s="Wrestling"},
	[134616225320869]={t="M2",d=0.525,s="Wrestling"},
	[137247073345979]={t="M1",d=0.28,s="Ali",c=1},   [102632933427597]={t="M1",d=0.37,s="Ali",c=2},
	[119814294807778]={t="M1",d=0.42,s="Ali",c=3},   [74315946602284]={t="M1",d=0.22,s="Ali",c=4},
	[128315752013166]={t="M2",d=0.53,s="Ali",v="Left"},
	[70642098724811]={t="M2",d=0.67,s="Ali",v="Right"},
}

local LEGACY_M2_VARIANT = { M2 = "Left", M2Right = "Right", M2Left = "Left" }

local LEGACY_M1_OFFSETS = {
	ali      = {0.06, 0.15, 0.2, 0},
	basic    = {0.02, 0.02, 0.02, 0.02},
	boxing   = {0.02, 0.02, 0.02, 0.06},
	hakari   = {0.14, 0.16, 0.07, 0.17},
	hakario  = {0.14, 0.16, 0.07, 0.17},
	karate   = {0.0375, 0.075, 0.15, 0.225},
	capoeira = {0.02, 0.1, 0.02, -0.05},
	slugger  = {0.3, 0.25, 0.25, 0.17},
	wrestling= {0.04, 0.05, 0.04, 0.03},
}
local LEGACY_M1_BASE = { ali=0.22, karate=0.24, muaythai=0.30, slugger=0.20, capoeira=0.33,
                         hakari=0.21, hakario=0.21, wingchun=0.28 }
local LEGACY_M2_BASE = { ali=0.53, boxing=0.43, capoeira=0.45, hakari=0.35, hakario=0.35, karate=0.4875,
                         muaythai=0.60, slugger=0.82, wrestling=0.525, basic=0.525,
                         taekwondo=0.46, wild=0.525, bulky=0.43, dirty=0.30, wingchun=0.525,
                         skygaolang=0.35, variant=0.35, kure=0.30 }
local LEGACY_M2_MOM_BASE = { hakari=0.48, hakario=0.48 }
local WINDUP_EXTRA = 0.012
local COMBO_RESET  = 1.55

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Stats             = game:GetService("Stats")

local LocalPlayer  = Players.LocalPlayer
local ServerRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server")

local State = {
	blocking     = false,
	guardUp      = false,
	holdUntil    = 0,
	status       = "ARMED",
	lastThreat   = nil,
	parryCount   = 0,
	dodgeCount   = 0,
	grantEscapes = 0,
	selfBusyUntil= 0,
	attackBusyUntil = 0,
	kicksBlocked   = 0,
	reportsBlocked = 0,
	acMuted        = 0,
	acScript       = nil,
	desyncFires    = 0,
	fireCount    = 0,
	lastDodge    = -99,
	dodgeRejects = 0,
	swingAnimUntil = 0,
	threatNeutralized = 0,
	dodgeGateSaid = nil,
	lastDodgeInfo   = nil,
	aliM2CD = { char=nil, observed=false, active=false, known=false, started=0, duration=7 },
	dodgeTxn = { pending=false, confirmed=false, fire=0, lo=0, hi=0, untilAt=0, reason=nil },
	counterTxn = { seq=0, pending=false, confirmed=false, sent=0, ackDeadline=0,
		expectedIFramesAt=0, threat=nil, threatId=nil, source=nil, result=nil },
	lastDodgeRefuse = nil,
	lastAct      = -99,
	lastDeact    = -99,
	flashUntil   = 0,
	lastResult   = "—",
	lastErrMs    = 0,
	lastGapMs    = 0,
	tally        = { PERFECT=0, EARLY=0, LATE=0, GUARDBREAK=0 },
	vizTarget    = nil,
	faceGoalHRP   = nil,
	faceGoalHard  = false,
	faceGoalUntil = 0,
	faceHum       = nil,
	faceGoalPos   = nil,
	noParryActive = false,
	noParryNow    = false,
}

local Threats = {}

local FaceByResult = {}
local ResidByKS    = {}
local ComboState = {}
local Pending = {}

local logTrim = LPH_NO_VIRTUALIZE(function(t, cap)
	local n = #t
	if n <= cap then return end
	local drop = cap // 2
	if drop < 1 then drop = 1 end
	table.move(t, drop + 1, n, 1)
	for i = n - drop + 1, n do t[i] = nil end
end)

local DiagLog, DIAG_MAX = {}, 1200
local diagPush = LPH_NO_VIRTUALIZE(function(line)
	DiagLog[#DiagLog+1] = line
	logTrim(DiagLog, DIAG_MAX)
end)

local DesyncLog, DESYNC_MAX = {}, 800
local function desyncPush(line)
	local stamped = ("t=%.2f  %s"):format(os.clock(), line)
	DesyncLog[#DesyncLog+1] = stamped
	logTrim(DesyncLog, DESYNC_MAX)
end
local StatusLog, STATUS_MAX = {}, 200
local function statusPush(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local line = table.concat(parts, " ")
	StatusLog[#StatusLog + 1] = line
	logTrim(StatusLog, STATUS_MAX)
end

local function dbg(...)
	if Config.Debug then statusPush(...) end
end

local function aclog(...)
	statusPush(...)
end

local _lastGoodPing = 0.08
local function pingDiagSnapshot()
	local oneWay, statsRtt
	pcall(function()
		local v = LocalPlayer:GetNetworkPing()
		if type(v) == "number" and v > 0 then oneWay = v end
	end)
	pcall(function()
		local v = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		if type(v) == "number" and v > 1 then statsRtt = v / 1000 end
	end)
	return oneWay, statsRtt
end
local getPingRaw = LPH_NO_VIRTUALIZE(function()
	local aRtt
	local okA, v = pcall(function() return LocalPlayer:GetNetworkPing() end)
	if okA and type(v) == "number" and v == v and v > 0 then aRtt = v end

	local bRtt
	local okB, ms = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if okB and type(ms) == "number" and ms == ms and ms > 1 then bRtt = ms / 1000 end

	local best
	if bRtt and aRtt then
		local ratio = Config.PingSourceMaxRatio or 2.5
		best = (aRtt > bRtt * ratio) and bRtt or math.max(aRtt, bRtt)
	else
		best = bRtt or aRtt
	end

	if best and best > 0 then
		_lastGoodPing = math.clamp(best, 0.005, 1.5)
	end
	return _lastGoodPing
end)

local V93 = {
	frameDt   = 1/60,
	lookahead = 0,
	frameDtPeak = 1/60,
	stepCost  = 0,
	nearPress = math.huge,
	nearPressStamp = 0,
	vizLast   = 0,
	pingBuf   = {},
	pingBufN  = 0,
	pingBufI  = 0,
	pingSampleClock = -1,
	pingMedTmp = {},
	hbFolder = nil,
	sizes = {},
	hbParams = nil,
	hbChar = nil,
	hbFrame = -1,
	byOwner = {},
	hbFirstSeen = setmetatable({}, { __mode = "k" }),
	hbClaimBySid = {},
	hbLiveSid = {},
	pingCacheClock = -1,
	pingCacheVal   = 0.08,
	imminentBuf = {},
	clusterBuf  = {},
	faceBuf     = {},
	seenAttackers = {},
	threatSeen = {},
	interruptSeen = {},
	boxingM2Contacts = { 0.6000000, 1.0500000 },
	ownM1Info = { t = "M1", s = "Basic" },
	ownM2Info = { t = "M2", s = "Basic", mom = false, variant = nil },
	sortByContact = function(a, b) return a.contactAbs < b.contactAbs end,
	dodgeParams = nil,
	dodgeChar = nil,
}

local function getPing()
	local nowc = os.clock()
	if (nowc - V93.pingSampleClock) < (Config.PingSampleGap or 0.03) then
		return V93.pingCacheVal
	end
	V93.pingSampleClock = nowc

	local raw = getPingRaw()
	local win = math.max(3, Config.PingWindow or 24)
	V93.pingBufI = (V93.pingBufI % win) + 1
	V93.pingBuf[V93.pingBufI] = raw
	if V93.pingBufN < win then V93.pingBufN = V93.pingBufN + 1 end

	local n = V93.pingBufN
	local tmp = V93.pingMedTmp
	for i = 1, n do tmp[i] = V93.pingBuf[i] end
	for i = n + 1, #tmp do tmp[i] = nil end
	table.sort(tmp)
	local med
	if n % 2 == 1 then med = tmp[(n + 1) // 2]
	else med = (tmp[n // 2] + tmp[n // 2 + 1]) * 0.5 end

	V93.pingCacheVal = math.min(med, Config.PingCap)
	return V93.pingCacheVal
end

local uplink = LPH_NO_VIRTUALIZE(function()
	local ping = getPing()
	local up = math.clamp(ping * Config.UplinkFactor + Config.UplinkMargin, Config.UplinkMin, Config.UplinkMax)
	local thr = Config.LowPingThresh or 0
	if thr > 0 and ping < thr then
		up = up + (Config.LowPingFloor or 0) * (1 - ping / thr)
	end
	return up
end)

local function localChar() return LocalPlayer.Character end

local _index = LPH_NO_VIRTUALIZE(function(o, k) return o[k] end)
V93.humMove = LPH_NO_VIRTUALIZE(function(hum, dir) return hum:Move(dir, false) end)
local safeGet = LPH_NO_VIRTUALIZE(function(o, k, default)
	if o == nil then return default end
	local ok, v = pcall(_index, o, k)
	if ok and v ~= nil then return v end
	return default
end)

local FrameId = 0
local _hrpCache, _hrpFrame = nil, -1
local localHRP = LPH_NO_VIRTUALIZE(function()
	if _hrpFrame == FrameId and _hrpCache and _hrpCache.Parent then return _hrpCache end
	local c = localChar()
	_hrpCache = (c and c:FindFirstChild("HumanoidRootPart")) or nil
	_hrpFrame = FrameId
	return _hrpCache
end)

local HARD_BLOCKERS = { "BlockCooldown", "Ragdoll", "Downed", "Greenzone",
                        "RpCombatLocked", "StaffModPeaceMode" }
local function canBlockNow()
	local c = localChar()
	if not c then return false, "no-char" end
	if Config.RequireEquip ~= false and c:GetAttribute("Equip") ~= true then
		return false, "Unequip"
	end
	for _, attr in ipairs(HARD_BLOCKERS) do
		if c:GetAttribute(attr) == true then return false, attr end
	end
	local stunned = c:GetAttribute("Stunned") == true
	local cantAny = c:GetAttribute("CantAnything") == true
	if stunned or cantAny then
		if c:GetAttribute("ParryWindowDisabled") ~= true
		   and c:GetAttribute("PerfectBlocking") ~= true
		   and (c:GetAttribute("Parried") == true
			or (Config.ComboEscape and c:GetAttribute("ParryBuffered") == true)) then
			return true, nil
		end
		return false, stunned and "Stunned" or "CantAnything"
	end
	return true, nil
end

local function blockStamina()
	local c = localChar()
	if not c then return nil end
	for _, name in ipairs(Config.StaminaAttrs) do
		local v = c:GetAttribute(name)
		if type(v) == "number" and v >= 0 and v <= 1000 then return v end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	for _, host in ipairs({ c, hum }) do
		if host then
			for _, name in ipairs(Config.StaminaAttrs) do
				local obj = host:FindFirstChild(name)
				if obj and (obj:IsA("NumberValue") or obj:IsA("IntValue")) then return obj.Value end
			end
		end
	end
	return nil
end

local function ownerOf(animator)
	local p = animator.Parent
	if p and (p:IsA("Humanoid") or p:IsA("AnimationController")) then return p.Parent end
	return p
end

local isEnemyModel = LPH_NO_VIRTUALIZE(function(model)
	if not model or model == localChar() then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return false end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		if plr == LocalPlayer then return false end
		return true, hrp
	end
	if Config.IncludeNPCs then return true, hrp end
	return false
end)

local function flatDirTo(fromPos, targetPos)
	local d = Vector3.new(targetPos.X - fromPos.X, 0, targetPos.Z - fromPos.Z)
	if d.Magnitude < 0.05 then return nil end
	return d.Unit
end

local function faceDotToPos(targetPos)
	local myHRP = localHRP()
	if not myHRP or not targetPos then return nil end
	local dir = flatDirTo(myHRP.Position, targetPos)
	if not dir then return 1 end
	local look = myHRP.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then return nil end
	return flatLook.Unit:Dot(dir)
end

local function faceDotToThreat(th)
	local hb = th and th.hitboxPart
	if hb and hb.Parent then
		local okp, pos = pcall(function() return hb.Position end)
		if okp and pos then return faceDotToPos(pos) end
	end
	local a = th and th.attackerHRP
	if a and a.Parent then return faceDotToPos(a.Position) end
	return nil
end

local function computeMultiFaceGoal()
	if not Config.AutoFace then return nil end
	local nThreat = 0
	for _, th in ipairs(Threats) do
		if th.threatens and th.attackerHRP and th.attackerHRP.Parent then
			nThreat = nThreat + 1
			if nThreat >= 2 then break end
		end
	end
	if nThreat < 2 then return nil end

	local me = localHRP(); if not me then return nil end
	local mePos = me.Position
	local flatMe = me.CFrame.LookVector; flatMe = Vector3.new(flatMe.X, 0, flatMe.Z)
	flatMe = flatMe.Magnitude > 0.05 and flatMe.Unit or Vector3.new(0, 0, 1)
	local t = V93.faceBuf
	local n = 0
	for _, th in ipairs(Threats) do
		if th.threatens and th.attackerHRP and th.attackerHRP.Parent then
			local to = th.attackerHRP.Position - mePos
			local d = Vector3.new(to.X, 0, to.Z)
			local dist = d.Magnitude
			if dist > 0.05 then
				d = d.Unit
				n = n + 1
				local e = t[n]
				if not e then e = {}; t[n] = e end
				e.k = th.attackerModel or th.attackerHRP or th.name
				e.dir = d
				e.dist = dist
				e.front = flatMe:Dot(d) > 0.05
			end
		end
	end
	for i = #t, n + 1, -1 do t[i] = nil end
	if n < 2 then return nil end
	local best, bestAng = nil, nil
	local maxA = math.rad(Config.MultiFaceAngleMax or 70)
	for i = 1, #t-1 do for j = i+1, #t do
		local a, b = t[i], t[j]
		if a.k ~= b.k then
			local ok = (not Config.MultiFaceOnlyFront) or (a.front and b.front)
			if ok then
				local ang = math.acos(math.clamp(a.dir:Dot(b.dir), -1, 1))
				if ang <= maxA and (bestAng == nil or ang < bestAng) then
					bestAng = ang; best = {a, b}
				end
			end
		end
	end end
	if not best then return nil end
	local a, b = best[1], best[2]
	local bis = a.dir + b.dir
	if bis.Magnitude < 0.05 then return nil end
	bis = bis.Unit
	local td = math.min(a.dist, b.dist) + math.abs(a.dist - b.dist)*0.35
	local base = mePos + bis*td
	local j = (Config.MultiFaceJitter or 0.30)
	local side = (math.sin((FrameId % 12)/12 * math.pi * 2) + 1) * 0.5
	local perp = Vector3.new(-bis.Z, 0, bis.X)
	return base + perp * (math.min(a.dist, b.dist) * j * (side - 0.5) * 2)
end

local function setFaceGoalPos(pos, hard, holdFor)
	if not Config.AutoFace then return end
	if not pos then return end
	State.faceGoalHRP = nil
	State.faceGoalPos = pos
	State.faceGoalHard = hard and true or false
	State.faceGoalUntil = os.clock() + (holdFor or 0.15)
end

local function setFaceGoal(targetHRP, hard, holdFor)
	if not Config.AutoFace then return end
	if not targetHRP or not targetHRP.Parent then return end
	State.faceGoalHRP   = targetHRP
	State.faceGoalHard  = hard and true or false
	State.faceGoalUntil = os.clock() + (holdFor or 0.15)
end

local styleForward
local registryKind

local FaceTrack = setmetatable({}, { __mode = "k" })
local function attackerPrevPos(aHRP)
	local now = os.clock()
	local rec = FaceTrack[aHRP]
	local prevPos, prevT = nil, nil
	if rec then
		prevPos, prevT = rec.pos, rec.t
		rec.t, rec.pos = now, aHRP.Position
	else
		FaceTrack[aHRP] = { t = now, pos = aHRP.Position }
	end
	return prevPos, prevT
end

local hitboxIndex = LPH_NO_VIRTUALIZE(function()
	if V93.hbFrame == FrameId then return V93.byOwner end
	V93.hbFrame = FrameId
	local byOwner = V93.byOwner
	for k in pairs(byOwner) do byOwner[k] = nil end
	local liveSid = V93.hbLiveSid
	for k in pairs(liveSid) do liveSid[k] = nil end
	local folder = V93.hbFolder
	if not (folder and folder.Parent) then
		folder = Workspace:FindFirstChild("Hitboxes")
		V93.hbFolder = folder
	end
	if not folder then return byOwner end
	for idx, child in ipairs(folder:GetChildren()) do
		if idx > 60 then break end
		if child:IsA("BasePart") then
			if not V93.hbFirstSeen[child] then V93.hbFirstSeen[child] = os.clock() end
			local owner = child:FindFirstChild("Owner")
			local atk   = child:FindFirstChild("AttackName")
			if owner and atk and owner:IsA("StringValue") and atk:IsA("StringValue") then
				local sid = child:GetAttribute("VictimSwingId")
				if typeof(sid) == "string" and sid ~= "" then
					liveSid[sid] = true
					local aType = atk.Value
					if aType == "M1" or aType == "M2" then V93.sizes[aType] = child.Size end
					local nm  = owner.Value
					local lst = byOwner[nm]
					if not lst then lst = {}; byOwner[nm] = lst end
					lst[#lst + 1] = child
				end
			end
		end
	end
	for sid in pairs(V93.hbClaimBySid) do
		if not liveSid[sid] then V93.hbClaimBySid[sid] = nil end
	end
	return byOwner
end)

local associatedHitbox = LPH_NO_VIRTUALIZE(function(th)
	if th.serverHitbox and th.serverHitbox.Parent then return th.serverHitbox end
	local lst = hitboxIndex()[th.name]
	if not lst then return nil end
	local best, bestScore
	for i = 1, #lst do
		local part = lst[i]
		local atk = part and part:FindFirstChild("AttackName")
		local sid = part and part:GetAttribute("VictimSwingId")
		if part.Parent and atk and atk:IsA("StringValue") and atk.Value == th.kind
			and typeof(sid) == "string" and sid ~= "" then
			local owner = V93.hbClaimBySid[sid]
			local claimKey = th.group or th
			if owner == nil or owner == claimKey then
				local seen = V93.hbFirstSeen[part] or os.clock()
				if seen >= th.detectClock - 0.035 then
					local score = math.abs(seen - (th.contactAbs or (th.detectClock + (th.contact0 or 0))))
					if not bestScore or score < bestScore then best, bestScore = part, score end
				end
			end
		end
	end
	if best then
		local sid = best:GetAttribute("VictimSwingId")
		V93.hbClaimBySid[sid] = th.group or th
		th.serverHitbox, th.serverSwingId = best, sid
		th.hbFirstClock = V93.hbFirstSeen[best] or os.clock()
		th.hbFirstServer = Workspace:GetServerTimeNow()
		th.hbFirstPos, th.hbFirstSize = best.Position, best.Size
		if th.group then
			th.group.serverHitbox, th.group.serverSwingId = best, sid
			th.group.hbFirstClock = th.hbFirstClock
		end
		diagPush(("TRACE-HB t=%.3f %s %s s%d sid=%s first=%+.0fms toPred=%+.0fms pos=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f)")
			:format(os.clock(), th.name or "?", th.kind or "?", th.strike or 1, tostring(sid),
				(th.hbFirstClock - th.detectClock)*1000, ((th.contactAbs or th.hbFirstClock)-th.hbFirstClock)*1000,
				best.Position.X, best.Position.Y, best.Position.Z, best.Size.X, best.Size.Y, best.Size.Z))
	end
	return best
end)

local realHitboxHitsMe = LPH_NO_VIRTUALIZE(function(ownerName, th)
	if th and th.gtQueryFrame == FrameId then return th.gtQueryResult end
	if not ownerName or not th then return nil end
	local part = (th.group and th.group.serverHitbox) or th.serverHitbox or associatedHitbox(th)
	if not (part and part.Parent) then
		th.gtQueryFrame, th.gtQueryResult = FrameId, nil
		return nil
	end
	local char = localChar()
	if not char then return nil end
	local params = V93.hbParams
	if not params then
		params = OverlapParams.new(); params.FilterType = Enum.RaycastFilterType.Include; params.MaxParts = 20
		V93.hbParams = params
	end
	if V93.hbChar ~= char then params.FilterDescendantsInstances = { char }; V93.hbChar = char end
	local hit = #Workspace:GetPartBoundsInBox(part.CFrame, part.Size, params) > 0
	if hit and not th.hbOverlapClock then
		th.hbOverlapClock, th.hbOverlapServer = os.clock(), Workspace:GetServerTimeNow()
		local my = localHRP()
		local av = th.attackerHRP and th.attackerHRP.AssemblyLinearVelocity or Vector3.zero
		local mv = my and my.AssemblyLinearVelocity or Vector3.zero
		diagPush(("TRACE-OV t=%.3f %s %s s%d sid=%s detect=%+.0fms predErr=%+.0fms av=(%.1f,%.1f) mv=(%.1f,%.1f)")
			:format(th.hbOverlapClock, th.name or "?", th.kind or "?", th.strike or 1,
				tostring(th.serverSwingId or (th.group and th.group.serverSwingId) or "none"),
				(th.hbOverlapClock-th.detectClock)*1000,
				(th.hbOverlapClock-(th.contactAbs or th.hbOverlapClock))*1000,
				av.X, av.Z, mv.X, mv.Z))
	end
	th.gtQueryFrame, th.gtQueryResult = FrameId, hit
	return hit
end)

local function hitboxNearestPart(ownerName, kind)
	if not ownerName then return nil, nil end
	local lst = hitboxIndex()[ownerName]
	if not lst or #lst == 0 then return nil, nil end
	local me = localHRP()
	if not me then return nil, nil end
	local best, bestD = nil, math.huge
	for i = 1, #lst do
		local part = lst[i]
		local atk = part and part:FindFirstChild("AttackName")
		if part.Parent and atk and atk:IsA("StringValue") and (not kind or atk.Value == kind) then
			local d = (part.Position - me.Position).Magnitude
			if d < bestD then bestD = d; best = part end
		end
	end
	return best, bestD
end

local syncContactWithHitbox = LPH_NO_VIRTUALIZE(function(th, now)
	if not Config.HitboxDodge then return end
	if (th.strike or 1) > 1 then return end
	if th.dodged or th.hitboxSynced then return end
	local part = hitboxNearestPart(th.name, th.kind)
	if not part then return end
	if not th.hitboxSeen then
		th.hitboxSeen, th.hitboxPart = now, part
	end
	if realHitboxHitsMe(th.name, th) == true then
		th.gtConfirmed, th.hitboxSynced = true, true
	end
end)

local clampLeadToVictim = LPH_NO_VIRTUALIZE(function(lead, aPos, mePos)
	local d = Vector3.new(aPos.X - mePos.X, 0, aPos.Z - mePos.Z).Magnitude
	local maxLead = d * (Config.WillHitLeadFrac or 0.90)
	if lead.Magnitude <= maxLead then return lead end
	if maxLead <= 1e-3 then return Vector3.zero end
	return lead.Unit * maxLead
end)

local hitboxGeom = LPH_NO_VIRTUALIZE(function(th)
	if th.geomFrame == FrameId then
		return th.geomC, th.geomF, th.geomP, th.geomL
	end
	local aHRP = th.attackerHRP
	if not aHRP or not aHRP.Parent then th.geomFrame = FrameId; th.geomC = nil; return nil end
	local now  = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local aPos = aHRP.Position
	local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
	local lead = Vector3.new(aV.X * tHit, 0, aV.Z * tHit)
	local meG = localHRP()
	if meG then
		local toMeG = Vector3.new(meG.Position.X - aPos.X, 0, meG.Position.Z - aPos.Z)
		if toMeG.Magnitude > 0.05 then
			toMeG = toMeG.Unit
			local leadDot  = lead:Dot(toMeG)
			local closeAmt = leadDot
			if th.prevPos and th.prevPosT then
				local dtp = now - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx   = th.prevPos.X - meG.Position.X
					local pdz   = th.prevPos.Z - meG.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					local cdx   = aPos.X - meG.Position.X
					local cdz   = aPos.Z - meG.Position.Z
					local curD  = math.sqrt(cdx * cdx + cdz * cdz)
					local measClose = (prevD - curD) / dtp
					if measClose > 0 then closeAmt = math.max(closeAmt, measClose * tHit) end
				end
			end
			local latVec   = lead - toMeG * leadDot
			local latCap   = Config.WillHitLatCap or 1.5
			if latVec.Magnitude > latCap then latVec = latVec.Unit * latCap end
			local distToMe = Vector3.new(aPos.X - meG.Position.X, 0, aPos.Z - meG.Position.Z).Magnitude
			local closeCap = math.min(Config.WillHitCloseCap or 12, distToMe * 0.95)
			closeAmt = math.clamp(closeAmt, 0, closeCap)
			lead = toMeG * closeAmt + latVec
			lead = clampLeadToVictim(lead, aPos, meG.Position)
		else
			local cap = Config.WillHitVelCap or 2.0
			if lead.Magnitude > cap then lead = lead.Unit * cap end
			lead = clampLeadToVictim(lead, aPos, meG.Position)
		end
	else
		local cap = Config.WillHitVelCap or 2.0
		if lead.Magnitude > cap then lead = lead.Unit * cap end
	end
	local predA = Vector3.new(aPos.X + lead.X, 0, aPos.Z + lead.Z)
	local look = aHRP.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then return nil end
	flatLook = flatLook.Unit

	local forward = (styleForward and styleForward(th.style, th.kind))
	                or ((th.kind == "M2") and Config.M2Forward or Config.M1Forward)
	if styleStepForward and (Config.AccuracyMode or "High") == "High" then
		local st = styleStepForward(th.style, th.kind, th.combo)
		if type(st) == "number" and st > 0 then
			forward = forward + st
			th.geomStep = st
		end
	end

	local prevPos, prevT = attackerPrevPos(aHRP)
	th.prevPos  = prevPos
	th.prevPosT = prevT

	local center = predA + flatLook * forward
	th.geomFrame, th.geomC, th.geomF, th.geomP, th.geomL = FrameId, center, forward, predA, flatLook
	return center, forward, predA, flatLook
end)

local willHitMe = LPH_NO_VIRTUALIZE(function(th)
	local myHRP, aHRP = localHRP(), th.attackerHRP
	if not myHRP then return Config.FilterFailSafe end
	if not aHRP or not aHRP.Parent then
		th.recognitionSource = "no-hrp"
		return false
	end
	local mode = Config.AccuracyMode or "Low"
	local gt = realHitboxHitsMe(th.name, th)
	if gt == true then
		th.gtConfirmed, th.trustedHit = true, true
		th.recognitionSource = "server-overlap"
		return true
	end

	local maxYd = math.max(Config.MaxHeightDiff or 12, 8)
	if not th.serverProven
	   and math.abs(myHRP.Position.Y - aHRP.Position.Y) > maxYd then
		th.recognitionSource = "y-diff"
		return false
	end
	if gt == false then
		th.recognitionSource = "server-pending"
	end

	local _, forward, predA, rawLook = hitboxGeom(th)
	if not predA or not rawLook then return Config.FilterFailSafe end
	local now = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local look, origin = rawLook, aHRP.Position
	if mode == "High" then
		origin = Vector3.new(predA.X, aHRP.Position.Y, predA.Z)
	end
	local sz = V93.sizes[th.kind]
	local myAt = myHRP.Position
	local halfW = (sz and sz.X * 0.5 or Config.HitHalfWidth or 3)
		+ (mode == "High" and (Config.HighSlack or 0.35) or (Config.HitboxSlack or 0))
	local halfH = (sz and sz.Y * 0.5 or 3) + 1.5
	local halfD = sz and sz.Z * 0.5 or (Config.HitboxDepth or 4)
	if math.abs(myAt.Y - origin.Y) > halfH then return false end
	local ox, oz = myAt.X - origin.X, myAt.Z - origin.Z
	local depth = ox * look.X + oz * look.Z
	local side = math.abs(ox * (-look.Z) + oz * look.X)
	th.geomDepth, th.geomSide = depth, side
	th.geomForward, th.geomHalfD, th.geomHalfW = forward, halfD, halfW
	th.geomTHit, th.geomOrigin, th.geomVictim, th.geomLook = tHit, origin, myAt, look

	local hit
	if mode == "High" then
		local dist2d = math.sqrt(ox * ox + oz * oz)
		local reach = forward + halfD + (Config.HighReachPad or 2.0)
		local coreReach = forward + halfD
		local toMeX, toMeZ = ox, oz
		if dist2d > 0.05 then toMeX, toMeZ = ox / dist2d, oz / dist2d else toMeX, toMeZ = look.X, look.Z end
		local faceToMe = look.X * toMeX + look.Z * toMeZ
		th.geomFaceToMe = faceToMe

		local approachAllow = 0
		if dist2d > reach then
			local dtc = (th.contactAbs or now) - now
			if dtc > 0 and dtc <= (Config.MaxWait or 1.2) then
				local avOk, av = pcall(function() return aHRP.AssemblyLinearVelocity end)
				if avOk and av then
					local velToMe = av.X * toMeX + av.Z * toMeZ
					if velToMe > 0.5 then
						approachAllow = math.clamp(velToMe * dtc, 0, Config.HighApproachCap or 6.0)
					end
				end
			end
		end
		th.geomApproach = approachAllow

		local faceFloor = Config.HighFaceFloor or -0.35
		local faceOk = (dist2d <= coreReach) or (faceToMe >= faceFloor)
		th.geomFaceFloor = (dist2d <= coreReach) and -1.01 or faceFloor
		hit = (dist2d <= reach + approachAllow) and faceOk
	else
		th.geomFaceToMe = nil
		hit = depth >= (forward - halfD) and depth <= (forward + halfD) and side <= halfW
	end

	if hit and th.serverProven then
		th.geomStickyUntil = math.max(th.geomStickyUntil or 0,
			(th.contactAbs or now) + (Config.HoldAfter or 0.12) + 0.05)
		th.geomStickySource = th.recognitionSource or (mode == "High" and "predicted-overlap" or "current-overlap")
	elseif not hit and th.serverProven and (th.geomStickyUntil or 0) >= now then
		local reason = (mode == "High" and ((math.sqrt(ox * ox + oz * oz) > (forward + halfD + (Config.HighReachPad or 2.0)))
			and "OUT-OF-REACH" or "BACK-FACING")) or "CURRENT-MISS"
		hit = true
		th.recognitionSource = "geom-sticky/" .. reason
		if Config.DeepDiag and (not th.geomStickyLogAt or now - th.geomStickyLogAt > 0.10) then
			th.geomStickyLogAt = now
			diagPush(("GEOM-STICKY t=%.3f %s %s s%d veto=%s source=%s contactIn=%+.0fms stickyLeft=%.0fms")
				:format(now, tostring(th.name), tostring(th.kind), th.strike or 1, reason,
					tostring(th.geomStickySource or "?"), ((th.contactAbs or now)-now)*1000,
					((th.geomStickyUntil or now)-now)*1000))
		end
	end

	th.trustedHit = hit
	if th.recognitionSource and th.recognitionSource:sub(1, 12) == "geom-sticky/" then
	elseif gt == false and not hit then
		th.recognitionSource = "server-pending+predicted-miss"
	else
		th.recognitionSource = hit and (mode == "High" and "predicted-overlap" or "current-overlap")
			or (mode == "High" and "predicted-miss" or "current-miss")
	end
	if not hit then th.offTarget = true end
	if not hit and Config.DeepDiag and not th.geomRejLogged then
		th.geomRejLogged = true
		local dist2d = math.sqrt(ox * ox + oz * oz)
		local reachD = forward + halfD + (Config.HighReachPad or 2.0)
		local f2m = th.geomFaceToMe
		if f2m == nil then
			f2m = 1
			if dist2d > 0.05 then f2m = (look.X * ox + look.Z * oz) / dist2d end
		end
		local appr = th.geomApproach or 0
			local reachEff = reachD + appr
			diagPush(("GEOM-REJECT t=%.3f %s %s(%s) c%s v%s mode=%s dt=%+.0fms | dist2d=%.2f reach=%.2f+appr%.2f=%.2f (fwd=%.2f step=%.2f halfD=%.2f pad=%.2f) %s | faceToMe=%+.2f floor=%+.2f %s | depth=%.2f side=%.2f/%.2f")
			:format(now, tostring(th.name), tostring(th.kind), tostring(th.style),
				tostring(th.combo or "?"), tostring(th.variant or "-"), tostring(mode),
				((th.contactAbs or now) - now) * 1000,
				dist2d, reachD, appr, reachEff, forward - (th.geomStep or 0), th.geomStep or 0, halfD,
				Config.HighReachPad or 2.0,
				(dist2d > reachEff) and "OUT-OF-REACH" or "reach-ok",
				f2m, th.geomFaceFloor or (Config.HighFaceFloor or -0.15),
				(f2m < (th.geomFaceFloor or (Config.HighFaceFloor or -0.15))) and "BACK-FACING" or "facing-ok",
				depth, side, halfW))
	end
	return hit
end)

local function nextCombo(attacker)
	local now = os.clock()
	local c = ComboState[attacker]
	local isFresh = (c == nil)
	local isNew = isFresh or (now - c.last) > COMBO_RESET
	if isNew then c = { idx = 0, last = now } end
	c.idx  = (c.idx % 4) + 1
	c.last = now
	ComboState[attacker] = c
	ComboState._count = (ComboState._count or 0) + (isFresh and 1 or 0)
	if ComboState._count > 64 then
		local oldest, oldestName = math.huge, nil
		for name, rec in pairs(ComboState) do
			if type(rec) == "table" and rec.last and rec.last < oldest then
				oldest = rec.last; oldestName = name
			end
		end
		if oldestName then ComboState[oldestName] = nil; ComboState._count = ComboState._count - 1 end
	end
	return c.idx
end

local GameData = { cfg = nil, cau = nil, cu = nil, resolved = false }

local function loadGameModules()
	if GameData.resolved then return end
	GameData.resolved = true
	pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local cfgMod = shared and shared:FindFirstChild("Config") and shared.Config:FindFirstChild("CombatConfig")
		if cfgMod then GameData.cfg = require(cfgMod) end
		local cauMod = shared and shared:FindFirstChild("Utils") and shared.Utils:FindFirstChild("CombatAnimationUtils")
		if cauMod then GameData.cau = require(cauMod) end
		local pauMod = shared and shared:FindFirstChild("Utils") and shared.Utils:FindFirstChild("CombatPingAnimUtils")
		if pauMod then GameData.pau = require(pauMod) end
		local pkgs = ReplicatedStorage:FindFirstChild("Packages")
		local cuMod = pkgs and pkgs:FindFirstChild("CombatUtils")
		if cuMod then GameData.cu = require(cuMod) end
	end)
	pcall(function()
		local ev = GameData.cfg and GameData.cfg.Evasive
		if ev and type(ev.IFrameDuration) == "number" and ev.IFrameDuration > 0.05 then
			GameData.iframeDur = ev.IFrameDuration
		end
		local cp = GameData.cfg and GameData.cfg.ClientPredict
		local cpe = cp and cp.Evasive
		if cpe and type(cpe.ServerConfirmTimeout) == "number" then
			GameData.confirmTimeout = cpe.ServerConfirmTimeout
		end
		if type(ev) == "table" and type(ev.Cooldown) == "number" and ev.Cooldown > 0 then
			GameData.evCooldown = ev.Cooldown
		end
		if cpe and type(cpe.Cooldown) == "number" and cpe.Cooldown > 0 then
			GameData.evPredictCooldown = cpe.Cooldown
		end
		if type(ev) == "table" and type(ev.DashDuration) == "number" and ev.DashDuration > 0 then
			GameData.dashDuration = ev.DashDuration
		end
		local bl = GameData.cfg and GameData.cfg.Block
		if bl and type(bl.PerfectBlockWindow) == "number" then
			GameData.perfectWindow = bl.PerfectBlockWindow
		end
	end)
end

local AttackMultCache = setmetatable({}, { __mode = "k" })
local function attackSpeedMult(model)
	if not model then return 1 end
	local c = AttackMultCache[model]
	if c and (os.clock() - c.t) < 1.0 then return c.m end
	loadGameModules()
	local mult = 1
	if GameData.cu then
		local ok, h = pcall(function() return GameData.cu.GetCharacterHeight(model) end)
		if ok and type(h) == "number" then
			local ok2, m = pcall(function() return GameData.cu.GetAttackSpeedMultiplier(h) end)
			if ok2 and type(m) == "number" and m > 0.05 then mult = m end
		end
	end
	if mult == 1 then
		local h
		pcall(function()
		local pd = model:FindFirstChild("PlayerData")
		if pd then h = tonumber(pd:GetAttribute("CurrentHeight")) or tonumber(pd:GetAttribute("Height")) end
		if type(h) ~= "number" then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local scale = hum and hum:FindFirstChild("BodyHeightScale")
			if scale and scale:IsA("NumberValue") then h = scale.Value end
		end
		end)
		if type(h) == "number" then
			mult = 1.15 - math.clamp((h - 0.983) / 0.467, 0, 1) * 0.3
		end
	end
	AttackMultCache[model] = { m = mult, t = os.clock() }
	return mult
end

local function heightDiag(model)
	local attrHeight, bodyScale, modelHeight = nil, nil, nil
	pcall(function()
		local pd = model and model:FindFirstChild("PlayerData")
		if pd then attrHeight = tonumber(pd:GetAttribute("CurrentHeight")) or tonumber(pd:GetAttribute("Height")) end
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local scale = hum and hum:FindFirstChild("BodyHeightScale")
		if scale and scale:IsA("NumberValue") then bodyScale = scale.Value end
		if model then modelHeight = model:GetExtentsSize().Y end
	end)
	return attrHeight, bodyScale, modelHeight
end

local _styleFn  = function(m) return GameData.cau.GetCombatStyleForCharacter(m) end
local _styleAttr = function(m) return m:GetAttribute("CombatStyle") end
local _styleCache = setmetatable({}, { __mode = "k" })
local function styleOf(model)
	local e = _styleCache[model]
	local nowc = os.clock()
	if e and nowc < e.t then return e.v end
	loadGameModules()
	local out
	if GameData.cau then
		local ok, s = pcall(_styleFn, model)
		if ok and type(s) == "string" and #s > 0 then out = s end
	end
	if not out then
		local ok, s = pcall(_styleAttr, model)
		if ok and type(s) == "string" and #s > 0 then out = s end
	end
	out = out or "Basic"
	if e then e.v, e.t = out, nowc + 0.5 else _styleCache[model] = { v = out, t = nowc + 0.5 } end
	return out
end

local AttackIds = {}
local function comboFromName(nm)
	local n = nm:match("^(%d+)")
	if n then return tonumber(n) end
	local l = nm:lower()
	if l:find("first")  then return 1 end
	if l:find("second") then return 2 end
	if l:find("third")  then return 3 end
	if l:find("fourth") then return 4 end
	return nil
end
local function kindFromName(nm)
	if nm:match("M2") then return "M2" end
	if nm:match("M1") then return "M1" end
	return nil
end
local function animIdOf(inst)
	if inst:IsA("Animation") then return tonumber(tostring(inst.AnimationId):match("(%d+)")) end
	local a = inst:FindFirstChildWhichIsA("Animation")
	if a then return tonumber(tostring(a.AnimationId):match("(%d+)")) end
	return nil
end
local BlockIds = {}
local function looksDefensive(nm)
	local l = nm:lower()
	return (l:find("block") or l:find("guard") or l:find("parry")
		or l:find("deflect") or l:find("perfect")) ~= nil
end
local function indexAllAnims()
	pcall(function()
		local anims  = ReplicatedStorage:FindFirstChild("Animations")
		if not anims then return end
		local combat = anims:FindFirstChild("Combat")
		if combat then
			for _, styleFolder in ipairs(combat:GetChildren()) do
				if styleFolder:IsA("Folder") then
					local isStyleFolder = styleFolder:FindFirstChild("M2") ~= nil
						or styleFolder:FindFirstChild("1stM1") ~= nil
						or styleFolder:FindFirstChild("2ndM1") ~= nil
					for _, child in ipairs(styleFolder:GetChildren()) do
						local lname     = child.Name:lower()
						local defensive = looksDefensive(child.Name)
						local reaction  = (lname:find("ehit") or lname:find("success")
							or lname:find("blockhit")) ~= nil
						local benignMove = (lname == "idle" or lname == "walk" or lname == "run"
							or lname:find("dash")) ~= nil
						local kind = nil
						if not defensive and not reaction and not benignMove then
							kind = kindFromName(child.Name)
							if not kind and isStyleFolder then kind = "SKILL" end
						end
						local id = animIdOf(child)
						if id and defensive then BlockIds[id] = true end
						if kind and id then
							AttackIds[id] = {
								kind = kind,
								combo = (kind == "M1") and comboFromName(child.Name) or nil,
								name = child.Name,
								mom = lname:find("momentum") ~= nil,
							}
						end
					end
				end
			end
		end
			for _, d in ipairs(anims:GetDescendants()) do
				if d:IsA("Animation") then
					local id = tonumber(tostring(d.AnimationId):match("(%d+)"))
					if id then
						if looksDefensive(d.Name) or (d.Parent and looksDefensive(d.Parent.Name)) then
							BlockIds[id] = true
						end
						if not AttackIds[id] and not BlockIds[id] then
							local lname = d.Name:lower()
							if not (lname:find("ehit") or lname:find("success"))
								and (lname:find("crit") or lname:find("momentum")
									or lname:find("slam") or lname:find("special") or lname:find("finisher")) then
								AttackIds[id] = { kind = "SKILL", combo = nil }
							end
						end
					end
				end
			end
	end)
	for id, v in pairs(LEGACY_ATTACKS) do
		if not AttackIds[id] then AttackIds[id] = { kind = v.t, combo = nil } end
	end
end

local function attackEntry(id)
	return AttackIds[id]
end

GameData.m2VarCache = {}
GameData.m2VariantId = function(style, animName)
	if type(animName) ~= "string" or animName == "" then return nil end
	local ck = tostring(style):lower() .. "|" .. animName
	local c = GameData.m2VarCache[ck]
	if c ~= nil then return c or nil end
	local out = false
	loadGameModules()
	if GameData.cfg and GameData.cfg.GetStyleM2Variants then
		pcall(function()
			local vs = GameData.cfg.GetStyleM2Variants(style)
			if type(vs) ~= "table" then return end
			for id, v in pairs(vs) do
				if type(v) == "table" and v.Anim == animName then out = id; return end
			end
			local ln = animName:lower()
			for id in pairs(vs) do
				local lid = tostring(id):lower()
				if #lid > 0 and ln:find(lid, 1, true) then out = id; return end
			end
		end)
	end
	if out == false then out = LEGACY_M2_VARIANT[animName] or false end
	GameData.m2VarCache[ck] = out
	return out or nil
end

local resolveInfo = LPH_NO_VIRTUALIZE(function(id, model)
	local entry  = AttackIds[id]
	if not entry then return nil end
	local legacy = LEGACY_ATTACKS[id]
	local kind = entry.kind
	local rk = registryKind and registryKind(model, id)
	if rk == "M1" or rk == "M2" then kind = rk end
	local style = styleOf(model) or (legacy and legacy.s) or "Basic"
	local variant = nil
	if kind == "M2" then
		if model then
			local okv, av = pcall(function() return model:GetAttribute("M2VariantId") end)
			if okv and type(av) == "string" and av ~= "" then variant = av end
		end
		if not variant then
			variant = GameData.m2VariantId(style, entry and entry.name) or (legacy and legacy.v) or nil
		end
	end
	return {
		t     = kind,
		s     = style,
		id    = id,
		hit   = entry.hit,
		contacts = (kind == "M2" and string.lower(style) == "boxing") and V93.boxingM2Contacts or nil,
		combo = entry and entry.combo or (legacy and legacy.c) or nil,
		mom   = (entry and entry.mom) or (legacy and legacy.mom) or false,
		name  = entry and entry.name or nil,
		variant = variant,
	}
end)

local function hitTimelineBase(info, combo)
	if info.t == "SKILL" then
		if info.hit and info.hit > 0 then return info.hit end
		return 0.35
	end
	if info.t == "M2" then
		loadGameModules()
		local cfgv, multi = nil, 1
		if GameData.cfg then
			local ok, d = pcall(function()
				return GameData.cfg.GetStyleM2HitboxDelay(info.s, info.mom, info.variant)
			end)
			if ok and type(d) == "number" then cfgv = d + WINDUP_EXTRA end
			local okc, mc = pcall(function() return GameData.cfg.GetStyleNumber(info.s, "M2MultiHitCount", 1) end)
			if okc and type(mc) == "number" then multi = mc end
		end
		if not cfgv then
			local sl = string.lower(info.s or "")
			local le = info.id and LEGACY_ATTACKS[info.id] or nil
			if le and le.t == "M2" and type(le.d) == "number" then
				cfgv = le.d + WINDUP_EXTRA
			elseif info.mom and LEGACY_M2_MOM_BASE[sl] then
				cfgv = LEGACY_M2_MOM_BASE[sl] + WINDUP_EXTRA
			else
				cfgv = (LEGACY_M2_BASE[sl] or 0.30) + WINDUP_EXTRA
			end
		end
		if multi > 1 and info.hit and info.hit > 0 then
			return cfgv
		end
		return cfgv
	end

	loadGameModules()
	if GameData.cfg then
		local ok, d = pcall(function() return GameData.cfg.GetScaledStyleM1HitboxDelay(info.s, combo or 1, 1) end)
		if ok and type(d) == "number" then return d end
	end
	local sl   = string.lower(info.s or "")
	local base = LEGACY_M1_BASE[sl] or 0.32
	local off  = LEGACY_M1_OFFSETS[sl]
	if off then base = base + (off[math.clamp(combo or 1, 1, 4)] or 0) end
	return base + WINDUP_EXTRA
end

local function hitTimeline(info, combo, mult, contactBase)
	local base = contactBase or hitTimelineBase(info, combo)
	local m = (type(mult) == "number" and mult > 0.05) and mult or 1
	return base / m
end

local _fwdFn = function(st, k) return GameData.cfg.GetStyleHitboxForwardOffset(st, k) end
local _fwdCache = {}
function styleForward(style, kind)
	local ck = tostring(style) .. "|" .. tostring(kind)
	local hit = _fwdCache[ck]
	if type(hit) == "number" then return hit end
	if hit == false then
		return (kind == "M2" or kind == "SKILL") and Config.M2Forward or Config.M1Forward
	end
	loadGameModules()
	if GameData.cfg then
		local ok, f = pcall(_fwdFn, style, kind)
		if ok and type(f) == "number" then _fwdCache[ck] = f; return f end
		_fwdCache[ck] = false
	end
	return (kind == "M2" or kind == "SKILL") and Config.M2Forward or Config.M1Forward
end

local _stepCache = {}
function styleStepForward(style, kind, combo)
	local ck = tostring(style) .. "|" .. tostring(kind) .. "|" .. tostring(combo or 1)
	local v = _stepCache[ck]
	if type(v) == "number" then return v end
	if v == false then return 0 end
	loadGameModules()
	local out = nil
	if GameData.cfg then
		pcall(function()
			if kind == "M1" then
				if GameData.cfg.GetStyleM1StepForwardStuds then
					out = GameData.cfg.GetStyleM1StepForwardStuds(style, combo or 1)
				end
			elseif GameData.cfg.GetStyleM2StepForwardStuds then
				out = GameData.cfg.GetStyleM2StepForwardStuds(style)
			end
		end)
	end
	if type(out) ~= "number" then
		local sl = string.lower(tostring(style))
		if sl == "ali" then
			out = (kind == "M1") and (((combo == 1) or (combo == 3)) and 1.5 or 0) or 2
		else
			out = nil
		end
	end
	if type(out) ~= "number" then _stepCache[ck] = false; return 0 end
	out = math.clamp(out, 0, 8)
	_stepCache[ck] = out
	return out
end

local function velLead(hrp)
	local v = 0
	local ok, vel = pcall(function() return hrp.AssemblyLinearVelocity end)
	if ok and vel then v = Vector3.new(vel.X, 0, vel.Z).Magnitude end
	return math.clamp(v / Config.MoveSpeedFull, 0, 1) * Config.MoveLeadMax
end

local Debris = game:GetService("Debris")
local AnimLib = { tracks = {}, dashCache = {}, blockAnim = nil, handler = nil, resolvedHandler = false }

local function looksLikeHandler(t)
	return type(t) == "table"
		and type(rawget(t, "LoadAnim"))  == "function"
		and type(rawget(t, "GetAnims"))  == "function"
		and type(rawget(t, "IsAnim"))    == "function"
		and type(rawget(t, "StopAnim"))  == "function"
		and type(rawget(t, "Anims"))     == "table"
end

AnimLib.handlers    = {}
AnimLib._handlerSet = setmetatable({}, { __mode = "k" })

local function addHandler(t)
	if not t or AnimLib._handlerSet[t] then return false end
	AnimLib._handlerSet[t] = true
	AnimLib.handlers[#AnimLib.handlers + 1] = t
	return true
end

local _handlerNextScan = 0
local function scanAllHandlers()
	local now = os.clock()
	if now < _handlerNextScan then return AnimLib.handlers end
	_handlerNextScan = now + 2

	pcall(function()
		local pkgs = ReplicatedStorage:FindFirstChild("Packages")
		local mod  = pkgs and pkgs:FindFirstChild("AnimationHandler")
		if mod then
			local ok, ret = pcall(require, mod)
			if ok and looksLikeHandler(ret) then addHandler(ret) end
		end
	end)

	if type(getgc) ~= "function" and type(filtergc) ~= "function" then
		if not AnimLib._gcWarned then
			AnimLib._gcWarned = true
			if aclog then aclog("[DESYNC] no getgc/filtergc — executor can't recover the hidden AnimationHandler") end
		end
		return AnimLib.handlers
	end

	local scanned, before = 0, #AnimLib.handlers
	if type(getgc) == "function" then
		pcall(function()
			for _, obj in pairs(getgc(true)) do
				scanned = scanned + 1
				if looksLikeHandler(obj) then addHandler(obj) end
			end
		end)
	end
	if #AnimLib.handlers == 0 and type(filtergc) == "function" then
		pcall(function()
			local scan = filtergc("table", { Keys = { "LoadAnim", "GetAnims", "IsAnim", "StopAnim", "Anims" } })
			if looksLikeHandler(scan) then addHandler(scan)
			elseif type(scan) == "table" then
				for _, obj in pairs(scan) do if looksLikeHandler(obj) then addHandler(obj) end end
			end
		end)
	end

	local added = #AnimLib.handlers - before
	if #AnimLib.handlers > 0 then
		AnimLib.resolvedHandler = true
		if added > 0 and aclog then
			aclog(("[DESYNC] GC scan: %d AnimationHandler instance(s) live (walked %d objects, +%d new)")
				:format(#AnimLib.handlers, scanned, added))
		end
	elseif aclog and not AnimLib._scanLogged then
		AnimLib._scanLogged = true
		aclog(("[DESYNC] GC scan: walked %d objects, no AnimationHandler yet (will retry)"):format(scanned))
	end
	return AnimLib.handlers
end

local function getHandler()
	if #AnimLib.handlers == 0 then scanAllHandlers() end
	local lc = localChar()
	if lc then
		for _, h in ipairs(AnimLib.handlers) do
			local hasOurs = false
			pcall(function() hasOurs = rawget(h, "Anims")[lc] ~= nil end)
			if hasOurs then AnimLib.handler = h; return h end
		end
	end
	AnimLib.handler = AnimLib.handlers[1]
	return AnimLib.handler
end

function registryKind(model, id)
	if not model then return nil end
	if #AnimLib.handlers == 0 then getHandler() end
	for _, h in ipairs(AnimLib.handlers) do
		if type(rawget(h, "GetAnims")) == "function" then
			local cats
			local ok = pcall(function() cats = h.GetAnims(model) end)
			if ok and type(cats) == "table" then
				for catName, entries in pairs(cats) do
					if type(catName) == "string" and type(entries) == "table" then
						for key, entry in pairs(entries) do
							local kid = tonumber(tostring(key):match("(%d+)"))
							if not kid and type(entry) == "table" and entry.Track then
								pcall(function()
									local a = entry.Track.Animation
									if a then kid = tonumber(tostring(a.AnimationId):match("(%d+)")) end
								end)
							end
							if kid == id then
								if catName == "M1" then return "M1" end
								if catName == "M2" or catName == "WrestlingM2" then return "M2" end
								return catName
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function getAnimator()
	local c = localChar()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	return hum:FindFirstChildOfClass("Animator") or hum
end

local function findAnimByName(root, wanted)
	local found
	pcall(function()
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Animation") and d.Name == wanted then found = d; break end
		end
	end)
	return found
end

local function resolveBlockAnim()
	if AnimLib.blockAnim and AnimLib.blockAnim.Parent then return AnimLib.blockAnim end
	local a
	pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local utils  = shared and shared:FindFirstChild("Utils")
		local mod    = utils and utils:FindFirstChild("CombatAnimationUtils")
		if mod then
			local CAU = require(mod)
			local folder = CAU.GetCombatAnimsFolderForPlayer(LocalPlayer)
			if folder then a = folder:FindFirstChild("Blocking") end
		end
	end)
	if not a then
		local anims = ReplicatedStorage:FindFirstChild("Animations") or ReplicatedStorage:FindFirstChild("Animations_Folder")
		if anims then a = findAnimByName(anims, "Blocking") end
	end
	AnimLib.blockAnim = a
	return a
end

local function playBlockAnim()
	if not Config.LegitAnims then return end
	if os.clock() < (State.swingAnimUntil or 0) then return end
	local char = localChar()
	local anim = resolveBlockAnim()
	if not char or not anim then return end

	local h = getHandler()
	if h and h.LoadAnim then
		local ok, tr = pcall(function() return h.LoadAnim(char, "Blocking", anim, nil, false) end)
		if ok and tr then
			local oldTr = AnimLib.tracks.Blocking
			AnimLib.tracks.Blocking = tr
			pcall(function() if oldTr and oldTr ~= tr and oldTr.Destroy then oldTr:Destroy() end end)
			pcall(function() if not tr.IsPlaying then tr:Play(0.08) end end)
			return
		end
	end
	local animator = getAnimator()
	if not animator then return end
	local tr = AnimLib.tracks.Blocking
	if not tr or not tr.IsPlaying then
		pcall(function()
			if not tr then
				local oldTr = AnimLib.tracks.Blocking
				tr = animator:LoadAnimation(anim); AnimLib.tracks.Blocking = tr
				pcall(function() if oldTr and oldTr ~= tr and oldTr.Destroy then oldTr:Destroy() end end)
			end
			tr.Priority = Enum.AnimationPriority.Action
			if not tr.IsPlaying then tr:Play(0.08) end
		end)
	end
end

local function stopBlockAnim()
	local char = localChar()
	local h = getHandler()
	if char and h and h.StopAnim then
		pcall(function() h.StopAnim(char, "Blocking", nil, 0.08) end)
	end
	local tr = AnimLib.tracks.Blocking
	if tr then pcall(function() tr:Stop(0.08) end) end
end

local function dashAnimMix(hrp, moveDir)
	local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
	if flat.Magnitude < 0.05 then return { "DashBack" } end
	local u     = flat.Unit
	local fwd   = hrp.CFrame.LookVector;  fwd   = Vector3.new(fwd.X, 0, fwd.Z)
	local right = hrp.CFrame.RightVector; right = Vector3.new(right.X, 0, right.Z)
	if fwd.Magnitude < 0.05 then return { "DashBack" } end
	local ang = math.deg(math.atan2(u:Dot(right.Unit), u:Dot(fwd.Unit)))
	if ang > -22.5 and ang <= 22.5   then return { "DashFront" } end
	if ang > 22.5  and ang <= 67.5   then return { "DashFront", "DashRight" } end
	if ang > 67.5  and ang <= 112.5  then return { "DashRight" } end
	if ang > 112.5 and ang <= 157.5  then return { "DashBack", "DashRight" } end
	if ang > 157.5 or  ang <= -157.5 then return { "DashBack" } end
	if ang > -157.5 and ang <= -112.5 then return { "DashBack", "DashLeft" } end
	if ang > -112.5 and ang <= -67.5 then return { "DashLeft" } end
	return { "DashFront", "DashLeft" }
end

local function resolveDashAnim(name)
	if AnimLib.dashCache[name] and AnimLib.dashCache[name].Parent then return AnimLib.dashCache[name] end
	local a
	local anims = ReplicatedStorage:FindFirstChild("Animations") or ReplicatedStorage:FindFirstChild("Animations_Folder")
	if anims then
		local mv = anims:FindFirstChild("Movement")
		if mv then a = mv:FindFirstChild(name) end
		if not a then a = findAnimByName(anims, name) end
	end
	AnimLib.dashCache[name] = a
	return a
end

local function playDodgeMotion(dirOverride, speedOverride)
	if not Config.LegitAnims then return end
	local hrp = localHRP()
	if not hrp then return end
	local c   = localChar()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local moveDir = (hum and hum.MoveDirection) or Vector3.new()
	if dirOverride and dirOverride.Magnitude > 0.05 then
		moveDir = Vector3.new(dirOverride.X, 0, dirOverride.Z)
	end
	local mix = dashAnimMix(hrp, moveDir)

	local h = getHandler()
	local playedViaHandler = false
	if c and h and h.LoadAnim then
		pcall(function() h.StopAnim(c, "Evasive", nil, 0.05) end)
		local tracks = {}
		for _, name in ipairs(mix) do
			local anim = resolveDashAnim(name)
			if anim then
				local ok, tr = pcall(function() return h.LoadAnim(c, "Evasive", anim, nil, false) end)
				if ok and tr then tracks[#tracks+1] = tr end
			end
		end
		if #tracks == 2 then
			pcall(function() tracks[1]:AdjustWeight(0.5, 0.05); tracks[2]:AdjustWeight(0.5, 0.05) end)
		end
		playedViaHandler = #tracks > 0
	end
	if not playedViaHandler then
		local animator = getAnimator()
		if animator then
			for _, name in ipairs(mix) do
				local anim = resolveDashAnim(name)
				if anim then
					pcall(function()
						local tr = animator:LoadAnimation(anim)
						tr.Priority = Enum.AnimationPriority.Action2
						tr:Play(0.05, #mix == 2 and 0.5 or 1)
					end)
				end
			end
		end
	end

	pcall(function()
		local oldV = hrp:FindFirstChild("EvasiveDashLinearVelocity"); if oldV then oldV:Destroy() end
		local oldA = hrp:FindFirstChild("EvasiveDashAttachment");     if oldA then oldA:Destroy() end
		hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
		local dir  = (flat.Magnitude > 0.001) and flat.Unit or (-hrp.CFrame.LookVector)
		local att  = Instance.new("Attachment"); att.Name = "EvasiveDashAttachment"; att.Parent = hrp
		local lv   = Instance.new("LinearVelocity"); lv.Name = "EvasiveDashLinearVelocity"
		lv.MaxForce = 100000
		lv.VectorVelocity = dir * math.min(speedOverride or Config.DashSpeed, Config.DashSpeed)
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Parent = hrp
		Debris:AddItem(att, Config.DashDuration)
		Debris:AddItem(lv, Config.DashDuration)
	end)
end

local function spoofStamp(tsServer)
	if not Config.TimeSpoof then return tsServer end
	local shift = (Config.TimeShiftMs or 0) / 1000
	if shift <= 0 then return tsServer end
	return tsServer - shift
end

local function sendActivate(tsServer)
	local now = os.clock()
	if now - State.lastAct < Config.MinActGap then return false end
	State.lastAct = now
	local c = localChar()
	if c then c:SetAttribute("Blocking", true) end
	ServerRemote:FireServer(
		{ Type = "Combat", Action = "Block", Func = "Activated" },
		spoofStamp(tsServer)
	)
	State.guardUp = true
	playBlockAnim()
	return true
end

local function sendDeactivate(force)
	local now = os.clock()
	if not force and now - State.lastDeact < Config.MinDeactGap then return false end
	State.lastDeact = now
	local c = localChar()
	if c then c:SetAttribute("Blocking", nil) end
	ServerRemote:FireServer({ Type = "Combat", Action = "Block", Func = "Deactivated" })
	State.guardUp = false
	stopBlockAnim()
	return true
end

local function sendDodge(dir, speedOverride)
	if State.guardUp or State.blocking then
		State.blocking, State.holdUntil = false, 0
		sendDeactivate(true)
		stopBlockAnim()
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "Evasive", Func = "Evasive" })
	playDodgeMotion(dir, speedOverride)
	State.lastDodge  = os.clock()
	State.dodgeCount = State.dodgeCount + 1
	State.flashUntil = os.clock() + 0.25
	State.status     = "DODGE"
	return true, nil
end

local BOXING_BLOCK_ATTRS = {
	"CombatAttacking", "Stunned", "Ragdoll",
	"ParryAttackLockout", "BlockAttackLockout",
}

local function counterStyle()
	local c = localChar()
	if not c then return nil end
	local st = (styleOf and styleOf(c) or ""):lower()
	if st == "" then return nil end
	if st == "boxing" then return Config.BoxingCounter and "boxing" or nil end
	if st == "ali"    then return Config.AliCounter    and "ali"    or nil end
	return nil
end

local function steerM2Variant(want)
	local c = localChar(); if not c then return end
	local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
	local hrp = localHRP(); if not hrp then return end
	local dir
	if want == "Right" then dir = hrp.CFrame.RightVector else dir = hrp.CFrame.LookVector end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.05 then return end
	State.ap.steerDir   = dir.Unit
	State.ap.steerUntil = os.clock() + (Config.AliVariantSteerDur or 0.15)
	pcall(function() hum:Move(State.ap.steerDir, false) end)
end

local function counterReady()
	if not Config.SkillAddon then return false, "SkillAddon-off" end
	local c = localChar()
	if not c then return false, "no-character" end
	local cs = counterStyle()
	if not cs then return false, "counter-style-disabled" end
	if (os.clock() - (State.lastCounter or 0)) < (Config.BoxingCounterGap or 0.30) then
		return false, "BoxingCounterGap"
	end
	for _, attr in ipairs(BOXING_BLOCK_ATTRS) do
		if c:GetAttribute(attr) then return false, attr end
	end
	if c:GetAttribute("CantAnything") and not c:GetAttribute("CombatRecovery") then
		return false, "CantAnything"
	end
	if c:GetAttribute("Equip") ~= true then return false, "Equip" end
	if c:GetAttribute("Greenzone") == true then return false, "Greenzone" end
	if c:GetAttribute("RpCombatLocked") == true then return false, "RpCombatLocked" end
	if c:GetAttribute("M2Cooldown") == true then return false, "M2Cooldown" end
	if c:GetAttribute("M2CD") == true then return false, "M2CD" end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false, "dead" end
	local h = getHandler()
	if h and h.GetAnims then
		local ehit = false
		pcall(function() ehit = next(h.GetAnims(c, "EHit")) ~= nil end)
		if ehit then return false, "EHit" end
	end
	return true, "ready"
end

function V93.markOwnM2IFrames(now, tag)
	local style = tostring(styleOf(localChar()) or ""):lower()
	loadGameModules()
	local lastContact = 0.43
	if GameData.cfg and GameData.cfg.GetStyleM2HitboxDelay then
		local okd, d = pcall(GameData.cfg.GetStyleM2HitboxDelay, style, false, nil)
		if okd and type(d) == "number" and d > 0 then lastContact = d end
		if GameData.cfg.GetStyleM2Variants then
			local okv, vs = pcall(GameData.cfg.GetStyleM2Variants, style)
			if okv and type(vs) == "table" then
				for _, vid in pairs(vs) do
					local ok2, d2 = pcall(GameData.cfg.GetStyleM2HitboxDelay, style, false, vid)
					if ok2 and type(d2) == "number" and d2 > lastContact then lastContact = d2 end
				end
			end
		end
	end
	if style == "boxing" then
		local mc = V93.boxingM2Contacts
		if type(mc) == "table" then
			for i = 1, #mc do
				if type(mc[i]) == "number" and mc[i] > lastContact then lastContact = mc[i] end
			end
		end
	end
	State.counterIFramesUntil = 0
	State.attackBusyUntil = math.max(State.attackBusyUntil or 0, now + lastContact)
	State.selfBusyUntil   = math.max(State.selfBusyUntil or 0, now + lastContact)
	State.ownIFrameTag = tag
end

function State.updateCounterTxn(now)
	local tx = State.counterTxn
	if not tx or (not tx.pending and not tx.confirmed) then return end
	local th = tx.threat
	local ch = localChar()
	local liveIFrames = ch and (ch:GetAttribute("IFRAMES") == true
		or ch:GetAttribute("UltraInstinct") == true) or false
	local enemyStopped, stopSource = false, nil
	local enemy = th and th.attackerModel
	if enemy and enemy.Parent then
		if enemy:GetAttribute("Parried") == true or enemy:GetAttribute("Stunned") == true
			or enemy:GetAttribute("Ragdoll") == true or enemy:GetAttribute("Downed") == true
			or enemy:GetAttribute("GuardBroken") == true then
			enemyStopped, stopSource = true, "enemy-state"
		elseif th.kind == "M1" and th.trackSeen and th.track then
			local okPlaying, playing = pcall(function() return th.track.IsPlaying end)
			if okPlaying and not playing and now > tx.sent then
				enemyStopped, stopSource = true, "enemy-track-stopped"
			end
		end
	end

	if liveIFrames then
		if th then
			th.coveredByCounter, th.counterPendingId, th.resolved = true, nil, true
		end
		tx.confirmed, tx.pending, tx.result = false, false, "IFRAMES"
		State.counterIFramesUntil = 0
		diagPush(("COUNTER-CONFIRM t=%.2f id=%s src=IFRAMES sentAgo=%.0fms → threat covered, dodge not needed")
			:format(now, tostring(tx.threatId), (now - tx.sent) * 1000))
		return
	end

	if enemyStopped then
		if th then
			th.coveredByCounter, th.counterPendingId, th.resolved = true, nil, true
		end
		tx.pending, tx.confirmed, tx.result = false, false, stopSource
		diagPush(("COUNTER-CONFIRM t=%.2f id=%s src=%s sentAgo=%.0fms → threat neutralized, dodge not needed")
			:format(now, tostring(tx.threatId), tostring(stopSource), (now - tx.sent) * 1000))
		return
	end

	local coverageMiss = th and (th.contactAbs or 0) <= (tx.expectedIFramesAt or 0)
	local timedOut = now >= (tx.ackDeadline or 0)
	if (tx.confirmed and not liveIFrames) or (tx.pending and (timedOut or coverageMiss)) then
		if th then
			th.counterPendingId = nil
			th.coveredByCounter = nil
		end
		local why = tx.confirmed and "IFRAMES ended before contact"
			or (coverageMiss and "expected IFRAMES cannot precede contact" or "IFRAMES not confirmed")
		tx.pending, tx.confirmed, tx.result = false, false, "fallback"
		State.counterIFramesUntil = 0
		diagPush(("COUNTER-FAIL/FALLBACK t=%.2f id=%s gate=%s sentAgo=%.0fms → normal defense restored")
			:format(now, tostring(tx.threatId), why, (now - tx.sent) * 1000))
	end
end

function State.updateAliM2Cooldown(now)
	local cd = State.aliM2CD
	local ch = localChar()
	if ch ~= cd.char then
		cd.char, cd.observed, cd.active, cd.known, cd.started = ch, false, false, false, 0
		local tx = State.dodgeTxn
		if tx then
			tx.pending, tx.confirmed, tx.perfectConfirmed = false, false, false
			tx.abuseThreat, tx.perfectAt, tx.reason = nil, nil, nil
		end
		State.ap.dodgeSteerDir, State.ap.dodgeSteerUntil = nil, 0
	end
	if not ch then return end
	local active = ch:GetAttribute("M2Cooldown") == true
	if not cd.observed then
		cd.observed, cd.active = true, active
		if active then cd.known = false end
		return
	end
	if active and not cd.active then
		loadGameModules()
		local duration = 7
		if GameData.cfg and GameData.cfg.GetStyleM2Cooldown then
			local ok, v = pcall(GameData.cfg.GetStyleM2Cooldown, "ali")
			if ok and type(v) == "number" and v > 0 then duration = v end
		end
		cd.started, cd.duration, cd.known = now, duration, true
	elseif not active and cd.active then
		cd.known, cd.started = false, 0
	end
	cd.active = active
end

local PARRY_ONLY_M2_CACHE = {}
local function m2IsParryOnlyStyle(style)
	local st = tostring(style or ""):lower()
	if st == "" then return false end
	local cached = PARRY_ONLY_M2_CACHE[st]
	if cached ~= nil then return cached end
	loadGameModules()
	local cfg = GameData.cfg
	local verdict = (st == "boxing")
	if cfg then
		local iframeDur = GameData.iframeDur or Config.IFrameDur or 0.30
		if cfg.GetStyleM2HitboxDuration then
			local ok, dur = pcall(cfg.GetStyleM2HitboxDuration, st)
			if ok and type(dur) == "number" and dur > 0 and dur >= iframeDur then
				verdict = true
			end
		end
		local multi
		if cfg.GetStyleNumber then
			local ok, v = pcall(cfg.GetStyleNumber, st, "M2MultiHitCount", 1)
			if ok and type(v) == "number" then multi = v end
		end
		local grants
		if cfg.GetStyleBoolean then
			local ok, v = pcall(cfg.GetStyleBoolean, st, "M2GrantsIFrames", false)
			if ok and type(v) == "boolean" then grants = v end
		end
		if multi == nil or grants == nil then
			local okS, styles = pcall(function() return cfg.Styles end)
			local s = okS and type(styles) == "table" and styles[st] or nil
			if type(s) == "table" then
				if multi == nil and type(s.M2MultiHitCount) == "number" then multi = s.M2MultiHitCount end
				if grants == nil and type(s.M2GrantsIFrames) == "boolean" then grants = s.M2GrantsIFrames end
			end
		end
		if type(multi) == "number" and multi > 1 then verdict = true end
		if grants == true then verdict = true end
	end
	PARRY_ONLY_M2_CACHE[st] = verdict
	return verdict
end

function State.isParryOnlyM2(th)
	return th ~= nil and th.kind == "M2" and m2IsParryOnlyStyle(th.style)
end

function State.isAliBoxingM2(th)
	return (styleOf(localChar()) or ""):lower() == "ali" and State.isParryOnlyM2(th)
end

function State.clusterHasAliBoxingM2(cluster)
	for _, th in ipairs(cluster or {}) do
		if State.isAliBoxingM2(th) then return true end
	end
	return false
end

function State.aliDodgeAbuseEligible(th, now, imminent, ifLat, ifDur)
	if not (Config.SkillAddon and Config.AliDodgeAbuse and Config.AliEvasiveCounter and Config.AutoDodge) then
		return false, nil, "disabled"
	end
	if (styleOf(localChar()) or ""):lower() ~= "ali" then return false, nil, "not-ali" end
	if not th or not th.serverProven then return false, nil, "not-server-proven" end
	if State.isMustDodge and State.isMustDodge(th) then return false, nil, "must-dodge" end

	local meC = localChar()
	if meC then
		if meC:GetAttribute("CombatAttacking") == true then return false, nil, "self-attacking" end
		if meC:GetAttribute("Stunned") == true then return false, nil, "stunned" end
		if meC:GetAttribute("CantAnything") == true then return false, nil, "cant-anything" end
		if meC:GetAttribute("GuardBroken") == true then return false, nil, "guard-broken" end
	end

	if State.isAliBoxingM2(th) then return false, nil, "boxing-m2-parry" end

	local cd = State.aliM2CD
	if not (cd and cd.active and cd.known) then return false, nil, "m2-cooldown-unknown" end
	local remaining = (cd.started + cd.duration) - now
	if remaining <= 1.0 then return false, nil, "m2-ready-soon" end

	local innerLo = ifLat + math.max(V93.lookahead or 0, 0) + 0.04
	local innerHi = ifLat + ifDur - 0.07
	local dt = th.contactAbs - now
	if dt < innerLo or dt > innerHi then return false, nil, "primary-outside-inner-iframe" end
	for _, other in ipairs(imminent) do
		if not other.dodged and not other.coveredByDodge and not other.feinted then
			local odt = other.contactAbs - now
			if odt < innerLo or odt > innerHi then
				return false, nil, "concurrent-outside-inner-iframe"
			end
		end
	end
	return true, remaining, "all-active-covered"
end

local function fireBoxingCounter(th, targetDist)
	local myHRP = localHRP()
	local aHRP  = th and th.attackerHRP
	if myHRP and aHRP and aHRP.Parent then
		local d = flatDirTo(myHRP.Position, aHRP.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
		local faceHold = (counterStyle() == "ali") and (Config.AliFaceLockDur or 0.75)
			or (Config.BoxingFaceLockDur or 0.55)
		setFaceGoal(aHRP, true, faceHold)
	end
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
	end
	local cs = counterStyle()
	if cs and cs ~= "boxing" then
		loadGameModules()
		local hasVars = false
		if GameData.cfg and GameData.cfg.GetStyleM2Variants then
			local okv, vs = pcall(GameData.cfg.GetStyleM2Variants, cs)
			hasVars = okv and type(vs) == "table"
		end
		if hasVars then steerM2Variant(Config.AliM2Variant or "Left") end
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	local sentAt = os.clock()
	State.lastCounter  = sentAt
	State.counterCount = (State.counterCount or 0) + 1
	State.flashUntil   = sentAt + 0.25
	State.status       = (cs == "ali") and "ALI-COUNTER" or "BOX-COUNTER"
	local tx = State.counterTxn
	if tx.threat and tx.threat ~= th then tx.threat.counterPendingId = nil end
	tx.seq = (tx.seq or 0) + 1
	local net = math.max(uplink(), 0.02)
	tx.pending, tx.confirmed, tx.sent = true, false, sentAt
	tx.ackDeadline = sentAt + net + (V93.lookahead or 0) + 0.08
	tx.expectedIFramesAt = sentAt + net + math.max(V93.lookahead or 0, 0) + (1 / 60)
	tx.threat, tx.source, tx.result = th, cs, "sent"
	tx.threatId = tostring(th.serverSwingId or (th.group and th.group.serverSwingId)
		or ((th.name or "?") .. "/" .. (th.kind or "?") .. "/" .. math.floor((th.detectClock or sentAt) * 1000)))
	th.counterPendingId = tx.seq
	State.counterPreemptFrame = -1
	diagPush(("COUNTER-SEND t=%.2f id=%s target=%s/%s dist=%.1f gate=M2-ready ack=%0.fms")
		:format(sentAt, tx.threatId, tostring(th.name), tostring(th.kind), targetDist or -1,
			(tx.ackDeadline - sentAt) * 1000))
	V93.markOwnM2IFrames(os.clock(), "counter/" .. tostring(cs))
end

local function tryAliEvasiveCounter(now)
	if not Config.SkillAddon or not Config.AliEvasiveCounter then return false end
	if (counterStyle() or "") ~= "ali" then return false end
	local tx = State.dodgeTxn
	if not (tx and tx.pending and tx.perfectConfirmed) then return false end
	if tx.evCounterFired then return false end
	if not tx.confirmed then
		if not tx.evCounterAwaitIframeLogged then
			tx.evCounterAwaitIframeLogged = true
			diagPush(("ALI-EVCOUNTER-WAIT t=%.2f gate=await-iframe perfectAgo=%.0fms")
				:format(now, (now-(tx.perfectAt or now))*1000))
		end
		return false
	end
	loadGameModules()
	local ec
	if GameData.cfg and GameData.cfg.GetStyleEvasiveCounter then
		local ok, v = pcall(GameData.cfg.GetStyleEvasiveCounter, "ali")
		if ok and type(v) == "table" then ec = v end
	end
	local cd    = (ec and tonumber(ec.Cooldown))  or 6
	local range = (ec and tonumber(ec.MaxRange))  or 22
	if (now - (State.lastEvCounter or -99)) < cd then return false end
		local procTTL = math.min(cd * (Config.AliProcTTLFrac or 0.25), Config.AliProcTTLMax or 1.5)
		local procDeadline = math.max(tx.untilAt or 0, (tx.perfectAt or now) + procTTL)
		if now > procDeadline then
			if not tx.evCounterExpiredLogged then
				tx.evCounterExpiredLogged = true
				diagPush(("ALI-EVCOUNTER-EXPIRE t=%.2f perfectAgo=%.0fms gate=proc-window-ended ttl=%.0fms")
					:format(now, (now-(tx.perfectAt or now))*1000, procTTL*1000))
			end
			return false
		end
	local c = localChar()
	if not c then return false end
	local stateGate = c:GetAttribute("Equip") ~= true and "not-equipped"
		or (c:GetAttribute("Stunned") == true and "stunned")
		or (c:GetAttribute("CombatAttacking") == true and "combat-attacking") or nil
	if stateGate then
		if tx.evCounterStateGate ~= stateGate then
			tx.evCounterStateGate = stateGate
			diagPush(("ALI-EVCOUNTER-WAIT t=%.2f gate=%s perfectAgo=%.0fms")
				:format(now, stateGate, (now-(tx.perfectAt or now))*1000))
		end
		return false
	end
	local myHRP = localHRP(); if not myHRP then return false end
	local myPos = myHRP.Position
	local best, bestDist
	local bound = tx.abuseThreat
	if bound then
		local aHRP = bound.attackerHRP
		if aHRP and aHRP.Parent then
			local dx, dz = myPos.X - aHRP.Position.X, myPos.Z - aHRP.Position.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= range then best, bestDist = bound, d end
		end
		if not best then
			if not tx.evCounterTargetGateLogged then
				tx.evCounterTargetGateLogged = true
				diagPush(("ALI-EVCOUNTER-WAIT t=%.2f gate=bound-target-missing-or-range range=%.0f")
					:format(now, range))
			end
			return false
		end
	else
		for i = 1, #Threats do
			local th = Threats[i]
			local aHRP = th.attackerHRP
			local boxingM2 = tostring(th.style or ""):lower() == "boxing" and th.kind == "M2"
			if aHRP and aHRP.Parent and not boxingM2 then
				local dx, dz = myPos.X - aHRP.Position.X, myPos.Z - aHRP.Position.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= range and (not bestDist or d < bestDist) then best, bestDist = th, d end
			end
		end
		if not best then return false end
	end
	local aHRP = best.attackerHRP
	if aHRP and aHRP.Parent then
		local d = flatDirTo(myPos, aHRP.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myPos, myPos + d) end
		setFaceGoal(aHRP, true, Config.AliFaceLockDur or 0.75)
	end
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	tx.evCounterFired    = true
	State.lastEvCounter  = now
	State.evCounterCount = (State.evCounterCount or 0) + 1
	State.flashUntil     = now + 0.25
	State.status         = "ALI-EV-COUNTER"
	diagPush(("ALI-EVCOUNTER-SEND t=%.2f target=%s dist=%.1f range=%.0f specialCd=%.0fs ignoreNormalM2Cd=true variant=Left perfectAgo=%.0fms gate=one-StyleEvasiveCounter")
		:format(now, best.name or "?", bestDist, range, cd, (now-(tx.perfectAt or now))*1000))
	return true
end

function State.counterBlockedPerm()
	if not Config.SkillAddon then return true end
	local c = localChar(); if not c then return true end
	if not counterStyle() then return true end
	if c:GetAttribute("Equip") ~= true then return true end
	if c:GetAttribute("M2Cooldown") == true or c:GetAttribute("M2CD") == true then return true end
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return true end
	if c:GetAttribute("Ragdoll") == true or c:GetAttribute("Downed") == true then return true end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return true end
	local h = getHandler()
	if h and h.GetAnims then
		local ehit = false
		pcall(function() ehit = next(h.GetAnims(c, "EHit")) ~= nil end)
		if ehit then return true end
	end
	return false
end

function State.counterReadyAt(now)
	local at = now
	local gapEnd = (State.lastCounter or 0) + (Config.BoxingCounterGap or 0.30)
	if gapEnd > at then at = gapEnd end
	local swingEnd = State.swingAnimUntil or 0
	if swingEnd > at then at = swingEnd end
	return at
end

local function counterCandidate(now, ignoreTransient)
	if ignoreTransient then
		if State.counterBlockedPerm() then return nil end
	else
		local ready, gate = counterReady()
		if not ready then return nil, nil, gate end
	end
	local myHRP = localHRP()
	if not myHRP then return nil end
	local cstyle = counterStyle()
	local reach = (cstyle == "ali") and (Config.AliCounterReach or 7.5)
		or (Config.BoxingCounterReach or 5.5)
	local myPos = myHRP.Position
	local best, bestDist
	local mustDodgeFn = State.isMustDodge
	for i = 1, #Threats do
		local th = Threats[i]
		local aHRP = th.attackerHRP
		local aliVsBoxingM2 = State.isAliBoxingM2(th)
		if aliVsBoxingM2 and not th.aliBoxingCounterLogged then
			th.aliBoxingCounterLogged = true
			diagPush(("ALI-BOXING-M2=PARRY t=%.2f target=%s strike=%d contactIn=%.0fms gate=counter")
				:format(now, tostring(th.name), th.strike or 1, (th.contactAbs-now)*1000))
		end
		if aHRP and aHRP.Parent and not aliVsBoxingM2 and not th.feinted and not th.dodged
		   and not th.coveredByDodge and not th.coveredByCounter and not th.counterPendingId
		   and not th.counterCommittedToParry
		   and not (mustDodgeFn and mustDodgeFn(th))
		   and (th.contactAbs - now) > -0.15 then
			local dx, dz = myPos.X - aHRP.Position.X, myPos.Z - aHRP.Position.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= reach and (not bestDist or dist < bestDist) then
				best, bestDist = th, dist
			end
		end
	end
	return best, bestDist
end

local function counterPreemptsDodge(now)
	if State.counterPreemptFrame == FrameId then return State.counterPreemptVal end
	local ch = localChar()
	if ch then
		if ch:GetAttribute("IFRAMES") == true or ch:GetAttribute("UltraInstinct") == true then
			State.counterPreemptFrame, State.counterPreemptVal = FrameId, true
			if now >= (State.lastPreemptLogAt or 0) + 0.5 then
				State.lastPreemptLogAt = now
				diagPush(("IFRAME-COVER t=%.2f  dodge skipped, live IFRAMES attribute on us (src=%s)")
					:format(now, tostring(State.ownIFrameTag or "game")))
			end
			return true
		end
	end
	if Config.CounterPreemptsDodge == false then return false end
	local ctx = State.counterTxn
	if ctx and ctx.pending and ctx.threat and ctx.threat.counterPendingId == ctx.seq
		and now < (ctx.ackDeadline or 0)
		and (ctx.expectedIFramesAt or math.huge) < (ctx.threat.contactAbs or 0) then
		State.counterPreemptFrame, State.counterPreemptVal = FrameId, true
		if State.counterCoverTag ~= ctx.seq then
			State.counterCoverTag = ctx.seq
			State.counterCoverSkips = (State.counterCoverSkips or 0) + 1
			diagPush(("COUNTER-COVER t=%.2f id=%s state=PENDING ackLeft=%.0fms contactIn=%.0fms")
				:format(now, tostring(ctx.threatId), ((ctx.ackDeadline or now) - now) * 1000,
					((ctx.threat.contactAbs or now) - now) * 1000))
		end
		return true
	end
	State.counterPreemptFrame, State.counterPreemptVal = FrameId, false
	return false
end

local function tryBoxingCounter(now)
	local best, bestDist = counterCandidate(now, true)
	if not best then return false end
	local ready, gate = counterReady()
	if not ready then
		local contactAt = best.contactAbs or now
		local lead = math.max(uplink(), 0.02) + math.max(V93.lookahead or 0, 0) + (1 / 60)
		local viableAgain = State.counterReadyAt(now) + lead < contactAt
		if not viableAgain then best.counterCommittedToParry = true end
		if best.counterFallbackGate ~= gate then
			best.counterFallbackGate = gate
			diagPush(("COUNTER-FALLBACK/PARRY t=%.2f target=%s/%s contactIn=%.0fms gate=%s retry=%s readyIn=%.0fms")
				:format(now, tostring(best.name), tostring(best.kind),
					(contactAt-now)*1000, tostring(gate or "unknown"),
					tostring(viableAgain), (State.counterReadyAt(now)-now)*1000))
		end
		return false
	end
	local contactIn = (best.contactAbs or now) - now
	local iframeLead = math.max(uplink(), 0.02) + math.max(V93.lookahead or 0, 0) + (1 / 60)
	local parryLead = math.max(Config.PerfectLead - math.max(uplink(), 0.02), 0) + (1 / 60)
	local yieldLead = math.max(iframeLead, parryLead)
	if contactIn <= yieldLead then
		best.counterCommittedToParry = true
		if not best.counterLateSkipLogged then
			best.counterLateSkipLogged = true
			diagPush(("COUNTER-SKIP/PARRY t=%.2f target=%s/%s contactIn=%.0fms need=%.0fms (iframe=%.0f parry=%.0f) gate=%s")
				:format(now, tostring(best.name), tostring(best.kind), contactIn * 1000,
					yieldLead * 1000, iframeLead * 1000, parryLead * 1000,
					parryLead >= iframeLead and "PARRY-DEADLINE-FIRST" or "IFRAMES-cannot-precede-contact"))
		end
		return false
	end
	fireBoxingCounter(best, bestDist)
	return true
end

local function isMustDodge(th)
	if not th then return false end
	local st = (th.style or ""):lower()
	if Config.SkillAddon then
		if Config.MustDodge and Config.SA_WrestlingGrab and st == "wrestling" and th.kind == "M2" then return true end
		if Config.MustDodge and Config.SA_DirtyGrab and st == "dirty" and (th.kind == "M2" or th.kind == "SKILL") then return true end
	end
	if not Config.MustDodge then return false end
	local byStyle = Config.MustDodgeStyles and Config.MustDodgeStyles[st]
	if byStyle and (byStyle[th.kind] or byStyle.all) then return true end
	if th.kind == "M2" and Config.MustDodgeAutoGrab ~= false and st ~= "" then
		GameData.grabCache = GameData.grabCache or {}
		local cached = GameData.grabCache[st]
		if cached == nil then
			cached = false
			loadGameModules()
			if GameData.cfg then
				pcall(function()
					local sc = GameData.cfg.GetStyleConfig and GameData.cfg.GetStyleConfig(st) or nil
					if sc then
						cached = (sc.M2GrabAllowRagdollCombo == true)
							or (type(sc.M2GrabTargetForwardOffset) == "number")
							or (type(sc.M2GrabLockDuration) == "number")
							or (type(sc.M2SlamParryWindowDisableDuration) == "number")
					end
				end)
			end
			GameData.grabCache[st] = cached
		end
		if cached then return true end
	end
	local aModel = th.attackerModel
	if aModel then
		local ok, grab = pcall(function()
			return aModel:GetAttribute("Grabbing") == true
				or aModel:GetAttribute("Unblockable") == true
				or aModel:GetAttribute("GuardBreak") == true
		end)
		if ok and grab then return true end
	end
	return false
end
State.isMustDodge = isMustDodge

State.ap = {
	m1         = nil,
	tryM1Fn    = nil,
	comboIdx   = nil,
	m1Tried    = false,
	fireOK     = false,
	u25idx     = nil,
	u26idx     = nil,
	u21idx     = nil,
	u32idx     = nil,
	u33idx     = nil,
	u27tbl     = nil,
	u28tbl     = nil,
	crc        = nil,
	getAnims   = nil,
	getSpeed   = nil,
	playSwing  = nil,
	nextM1At   = 0,
	punishTgt  = nil,
	punishUntil= 0,
		punishFresh= false,
		m1Txn      = nil,
		m1TxnSeq   = 0,
		busyAttrs = {
		"Stunned", "Ragdoll", "Downed", "GuardBroken", "CantAnything",
		"M1Cooldown", "ParryAttackLockout", "BlockAttackLockout",
	},
}

function State.ap.getM1()
	if State.ap.m1 then return State.ap.m1 end
	if State.ap.m1Tried then return nil end
	State.ap.m1Tried = true
	local mod
	pcall(function()
		local csc = ReplicatedStorage:FindFirstChild("CombatSystemClient")
		local base = csc and csc:FindFirstChild("Combat")
		base = base and base:FindFirstChild("Base")
		mod = base and base:FindFirstChild("M1")
	end)
	if not mod then
		pcall(function()
			for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
				if d.Name == "M1" and d:IsA("ModuleScript")
				   and d.Parent and d.Parent.Name == "Base" then mod = d; break end
			end
		end)
	end
	if mod then
		local ok, tbl = pcall(require, mod)
		if ok and type(tbl) == "table" and type(tbl.OnM1Activated) == "function" then State.ap.m1 = tbl end
	end
	if not State.ap.m1 and type(filtergc) == "function" then
		pcall(function()
			local t = filtergc("table",
				{ Keys = { "Hold", "OnM1Activated", "ServerResponse", "OnHoldSwing" } }, true)
			if type(t) == "table" and type(t.OnM1Activated) == "function" then State.ap.m1 = t end
		end)
	end
	if State.ap.m1 and type(debug) == "table" and type(debug.getupvalue) == "function" then
		pcall(function()
			local fn = debug.getupvalue(State.ap.m1.OnM1Activated, 1)
			if type(fn) == "function" then State.ap.tryM1Fn = fn end
		end)
			if State.ap.tryM1Fn and type(debug.setupvalue) == "function" then
				pcall(function()
					local fn = State.ap.tryM1Fn
					local function uv(i)
						local ok, v = pcall(debug.getupvalue, fn, i)
						if ok then return v end
						return nil
					end
					local C
					for i = 1, 40 do
						local v = uv(i)
						if type(v) == "table" and type(rawget(v, "Fire")) == "function" then C = i; break end
						if v == nil and i > 25 then break end
					end
					if not C then return end
					local getSpeed = uv(C - 12)
					local u19v     = uv(C - 11)
					local getAnims = uv(C - 10)
					local playSw   = uv(C - 8)
					local u25v     = uv(C - 4)
					local u26v     = uv(C - 3)
					local u27v     = uv(C - 2)
					local u28v     = uv(C - 1)
					local u21v     = uv(C - 16)
					local u32v     = uv(C - 15)
					local u33v     = uv(C - 14)
					if type(getSpeed) == "function"
					   and type(getAnims) == "function"
					   and type(playSw)  == "function"
					   and type(u19v) == "number" and u19v >= 0 and u19v <= 4
					   and type(u25v) == "number" and type(u26v) == "number"
					   and type(u27v) == "table"  and type(u28v) == "table" then
						State.ap.comboIdx  = C - 11
						State.ap.u25idx    = C - 4
						State.ap.u26idx    = C - 3
						State.ap.u27tbl    = u27v
						State.ap.u28tbl    = u28v
						State.ap.crc       = uv(C)
						State.ap.getSpeed  = getSpeed
						State.ap.getAnims  = getAnims
						State.ap.playSwing = playSw
						State.ap.fireOK    = true
						if type(u21v) == "boolean" then State.ap.u21idx = C - 16 end
						if type(u32v) == "number"  then State.ap.u32idx = C - 15 end
						if type(u33v) == "number"  then State.ap.u33idx = C - 14 end
					end
				end)
			end
		end
	if State.ap.m1 then diagPush("AUTOPLAY: M1 module resolved (legit attacks ready)"
		.. (State.ap.tryM1Fn and " +tryM1" or " (OnM1Activated only)")
		.. (State.ap.fireOK and " +CUSTOM-FIRE(fast)" or ""))
	else diagPush("AUTOPLAY: M1 module NOT found — attacks disabled") end
	return State.ap.m1
end

function State.ap.trackOwners()
	if type(getgenv) ~= "function" then return nil end
	local g = getgenv()
	local r = rawget(g, "__V0_COMBAT_TRACK_OWNERS")
	if type(r) ~= "table" then
		r = setmetatable({}, { __mode = "k" })
		rawset(g, "__V0_COMBAT_TRACK_OWNERS", r)
	end
	return r
end

function State.ap.finishM1Txn(reason, now)
	local ap, tx = State.ap, State.ap.m1Txn
	if not tx then return end
	ap.m1Txn = nil
	now = now or os.clock()
	diagPush(("AUTOPLAY-DONE t=%.2f tx=%d swing=%d combo=%d reason=%s suppressed=%d age=%.0fms")
		:format(now, tx.txid or 0, tx.swingId or 0, tx.combo or 0, tostring(reason or "complete"),
			tx.suppressed or 0, math.max(0, now - (tx.sentAt or now)) * 1000))
end

function State.ap.m1TxnActive(now)
	local ap, tx = State.ap, State.ap.m1Txn
	if not tx then return false end
	now = now or os.clock()
	local c = localChar()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if c ~= tx.char or not hum or hum.Health <= 0 then
		ap.finishM1Txn("character/death", now)
		return false
	end
	if now < (tx.untilAt or 0) then
		tx.suppressed = (tx.suppressed or 0) + 1
		return true
	end
	local why = tx.trackStopped and "track-stopped+floor" or "duration"
	ap.finishM1Txn(why, now)
	return false
end

function State.ap.markM1Track(char, anim, tx)
	local h = getHandler()
	if not (h and h.GetAnims and anim and tx) then return nil end
	local track
	pcall(function()
		local bucket = h.GetAnims(char, "M1")
		local entry = bucket and bucket[anim.AnimationId]
		track = entry and entry.Track
	end)
	if not track then return nil end
	tx.track = track
	local owners = State.ap.trackOwners()
	if owners then owners[track] = { owner = "autoplay", txid = tx.txid, swingId = tx.swingId } end
	pcall(function()
		track.Stopped:Connect(function()
			if State.ap.m1Txn == tx then tx.trackStopped = true end
		end)
	end)
	return track
end

function State.ap.fireM1Custom(char, model, wantCombo, ignoreRate, priority, dropGuard)
	local ap = State.ap
	if not (ap.fireOK and ap.tryM1Fn) then return false end
	local ok = false
	pcall(function()
		local now = os.clock()
		if ap.m1TxnActive(now) then return end
	if Config.SkillAddon and Config.AliEvasiveCounter then
		local etx = State.dodgeTxn
		if etx and etx.pending and etx.perfectConfirmed and not etx.evCounterFired then
			return
		end
		if Config.AliDodgeAbuse and Config.AutoDodge then
			local cdA = State.aliM2CD
			if cdA and cdA.active and cdA.known then
				local holdUntilContact = math.max(uplink(), 0.02)
					+ (GameData.iframeDur or Config.IFrameDur or 0.30) + 0.10
				for i = 1, #Threats do
					local th = Threats[i]
					if th and th.serverProven and not th.resolved and not th.dodged then
						local dtA = (th.contactAbs or 0) - os.clock()
						if dtA > 0 and dtA <= holdUntilContact then return end
					end
				end
			end
		end
	end
		local combo
		if wantCombo then
			combo = math.clamp(math.floor(wantCombo), 1, 4)
		elseif Config.AP_ComboMode == "Fixed" then
			combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
		else
			combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 3) + 1
		end
		if not ignoreRate then
			local rate = math.max(1, Config.AP_MaxPerSec or 6)
			local gap = priority and (Config.AP_PunishFastGap or 0.08)
				or math.max(Config.AP_MinSendGap or 0.09, (1 / rate) * 0.97)
			if (now - (ap.m1SendLast or 0)) < gap then return end
			if (now - (ap.m1WinStart or 0)) >= 1 then ap.m1WinStart, ap.m1WinCount = now, 0 end
			if (ap.m1WinCount or 0) >= rate then return end
		end
		if Config.AP_AnimGuard ~= false and (now - (ap.swingAnimAt or 0)) < (ap.swingAnimMin or 0) then
			return
		end
		local anims = ap.getAnims()
		local v53   = anims and anims[combo] or nil
		if not v53 then return end
		local spd = 1
		pcall(function() spd = ap.getSpeed(char, combo) or 1 end)
		local len = 0
		pcall(function()
			local cp = GameData.cfg and GameData.cfg.ClientPredict
			local m1 = cp and cp.M1
			len = tonumber(m1 and m1.AttackDuration) or 0
		end)
		if len <= 0 then len = Config.AP_AnimFallback or 0.45 end
		len = len / math.max(spd, 0.01)
		State.swingAnimUntil = now + len
		if AnimLib.tracks.Blocking or (char:GetAttribute("Blocking") == true) then
			stopBlockAnim()
		end
		local owners = ap.trackOwners()
		if owners then
			owners.__intent = { owner = "autoplay", char = char, animationId = v53.AnimationId, expires = now + 0.15 }
		end
		local played = false
		pcall(function() played = ap.playSwing(char, combo, spd, false) == true end)
		if not played then
			if owners and owners.__intent and owners.__intent.char == char then owners.__intent = nil end
			State.swingAnimUntil = 0
			return
		end
		ap.swingAnimAt  = now
		ap.swingAnimMin = len
		if dropGuard and (State.blocking or char:GetAttribute("Blocking") == true) then
			State.blocking, State.holdUntil = false, 0
			stopBlockAnim()
			pcall(sendDeactivate, true)
		end
		local newId = (debug.getupvalue(ap.tryM1Fn, ap.u25idx) or 0) + 1
			ServerRemote:FireServer({ Type = "Combat", Action = "M1", Func = "ServerCheck" }, newId)
			ap.m1SendLast = now
			ap.m1WinCount = (ap.m1WinCount or 0) + 1
			debug.setupvalue(ap.tryM1Fn, ap.comboIdx, combo)
			debug.setupvalue(ap.tryM1Fn, ap.u25idx, newId)
			debug.setupvalue(ap.tryM1Fn, ap.u26idx, newId)
			ap.u27tbl[newId] = combo
			ap.u28tbl[newId] = v53
			ap.m1TxnSeq = (ap.m1TxnSeq or 0) + 1
			local tx = {
				txid = ap.m1TxnSeq, swingId = newId, combo = combo, char = char,
				sentAt = now, untilAt = now + len, suppressed = 0,
			}
			ap.m1Txn = tx
			local tr = ap.markM1Track(char, v53, tx)
			if owners and owners.__intent and owners.__intent.char == char then owners.__intent = nil end
			diagPush(("AUTOPLAY-SEND t=%.2f tx=%d swing=%d combo=%d duration=%.0fms track=%s")
				:format(now, tx.txid, newId, combo, len * 1000, tr and "owned" or "unresolved"))
			ok = true
	end)
	return ok
end

function State.ap.canAttack(ignoreBlocking)
	local c = localChar()
	if not c then return false end
	if c:GetAttribute("Equip") ~= true then return false end
	if not ignoreBlocking and c:GetAttribute("Blocking") == true then return false end
	if c:GetAttribute("CombatAttacking") == true or c:GetAttribute("M1") == true
	   or c:GetAttribute("M2") == true or c:GetAttribute("PendingM2") == true then return false end
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return false end
	for _, a in ipairs(State.ap.busyAttrs) do
		if c:GetAttribute(a) then return false end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	return true
end

function State.ap.reach()
	local base = Config.AP_BaseReach or 5.5
	loadGameModules()
	if GameData.cfg and GameData.cfg.GetStyleHitboxForwardOffset then
		local ok, fwd = pcall(GameData.cfg.GetStyleHitboxForwardOffset, styleOf(localChar()), "M1")
		if ok and type(fwd) == "number" then base = fwd + 1.5 end
	end
	local _, _, myH = heightDiag(localChar())
	if type(myH) == "number" and myH > 0 then
		base = base * math.clamp(myH / (Config.AP_RefHeight or 5.5), 0.85, 1.45)
	end
	return base
end

function State.ap.flatDist(model)
	local myHRP = localHRP()
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not (myHRP and hrp) then return math.huge end
	local aim = hrp.Position
	local lead = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.22)
	if lead > 0 then
		local v = hrp.AssemblyLinearVelocity
		aim = aim + Vector3.new(v.X, 0, v.Z) * lead
	end
	return (Vector3.new(myHRP.Position.X, 0, myHRP.Position.Z)
	        - Vector3.new(aim.X, 0, aim.Z)).Magnitude
end

function State.ap.snapTo(hrp)
	setFaceGoal(hrp, true, Config.AP_FaceHold or 0.35)
	local myHRP = localHRP()
	if myHRP then
		local d = flatDirTo(myHRP.Position, hrp.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
	end
end

function State.ap.ownM1Delay()
	local ap = State.ap
	local char = localChar()
	if not char then return nil, nil end
	local combo = 1
	if Config.AP_ComboMode == "Fixed" then
		combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
	elseif ap.fireOK and ap.tryM1Fn and ap.comboIdx then
		combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 3) + 1
	end
	local char = localChar()
	if not char then return nil, nil end
	local style = styleOf(char)
	local info  = V93.ownM2Info
	info.s, info.mom, info.variant, info.hit, info.id = style, false, nil, nil, nil
	local vc = State.ap.m2VarCache
	if not vc then vc = {}; State.ap.m2VarCache = vc end
	local hit = vc[style]
	if hit == nil then
		local bestId, bestBase = nil, nil
		loadGameModules()
		if GameData.cfg and GameData.cfg.GetStyleM2Variants then
			local okv, vs = pcall(GameData.cfg.GetStyleM2Variants, style)
			if okv and type(vs) == "table" then
				for id in pairs(vs) do
					info.variant = id
					local okb, base = pcall(hitTimelineBase, info, nil)
					if okb and type(base) == "number" and (not bestBase or base < bestBase) then
						bestId, bestBase = id, base
					end
				end
			end
		end
		info.variant = bestId
		if not bestBase then
			local okb, base = pcall(hitTimelineBase, info, nil)
			if okb and type(base) == "number" then bestBase = base end
		end
		hit = bestBase and { id = bestId, base = bestBase } or false
		vc[style] = hit
	end
	if hit == false then return nil, nil end
	info.variant  = hit.id
	local bestId, bestBase = hit.id, hit.base
	return hitTimeline(info, nil, attackSpeedMult(char), bestBase), bestId
end

function State.ap.reachM2()
	local base = Config.AP_M2BaseReach or 6.5
	loadGameModules()
	if GameData.cfg then
		if GameData.cfg.GetStyleHitboxForwardOffset then
			local ok, fwd = pcall(GameData.cfg.GetStyleHitboxForwardOffset, styleOf(localChar()), "M2")
			if ok and type(fwd) == "number" then base = fwd + 1.5 end
		end
		if GameData.cfg.GetStyleNumber then
			local oks, step = pcall(GameData.cfg.GetStyleNumber, styleOf(localChar()), "M2StepForwardStuds", 0)
			if oks and type(step) == "number" and step > 0 then base = base + step end
		end
	end
	local _, _, myH = heightDiag(localChar())
	if type(myH) == "number" and myH > 0 then
		base = base * math.clamp(myH / (Config.AP_RefHeight or 5.5), 0.85, 1.45)
	end
	return base
end

function State.ap.m2Ready()
	local c = localChar()
	if not c then return false end
	if c:GetAttribute("M2Cooldown") == true or c:GetAttribute("M2CD") == true then return false end
	if c:GetAttribute("M2") == true or c:GetAttribute("PendingM2") == true then return false end
	local lastM2 = State.ap.m2SendLast or 0
	local lastCn = State.lastCounter or 0
	if lastCn > lastM2 then lastM2 = lastCn end
	if (os.clock() - lastM2) < (Config.AP_M2Gap or 0.30) then return false end
	return true
end

function State.ap.fireM2(model, why, variant)
	local ap = State.ap
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	ap.snapTo(hrp)
	local c = localChar()
	if State.blocking or (c and c:GetAttribute("Blocking") == true) then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
	end
	if variant then steerM2Variant(variant) end
	local ok = pcall(function()
		ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	end)
	if not ok then return false end
	local now = os.clock()
	ap.m2SendLast    = now
	State.lastCounter = now
	State.flashUntil = now + 0.25
	State.apM2Count  = (State.apM2Count or 0) + 1
	return true
end

function State.ap.interruptible(th)
	if not th or not th.attackerModel or not th.attackerHRP then return false end
	if th.attackerModel:GetAttribute("IFRAMES") == true
	   or th.attackerModel:GetAttribute("HyperArmor") == true then return false end
	if th.kind == "M2" then
		loadGameModules()
		if GameData.cfg and GameData.cfg.GetStyleConfig then
			local ok, sc = pcall(GameData.cfg.GetStyleConfig, th.style or "basic")
			if ok and type(sc) == "table"
			   and (sc.M2GrantsIFrames == true or sc.M2GrantsHyperArmor == true) then return false end
		end
	end
	return true
end

function State.ap.tryInterrupt(now, th, threatCount)
	local ap = State.ap
	if not Config.AutoPlay or Config.AP_Interrupt == false then return false end
	if not th or th.pressed or th.dodged or th.interruptAttempted then return false end
	if threatCount >= 2 then
		local secondClose = false
		for _, other in ipairs(Threats) do
			if other ~= th and not other.feinted and not other.dodged and not other.pressed then
				local otherDt = other.contactAbs - now
				if otherDt >= 0 and otherDt <= (Config.DodgeHorizon or 0.6) then
					secondClose = true
					break
				end
			end
		end
		if secondClose then return false end
	end
	if th.kind ~= "M1" and th.kind ~= "M2" then return false end
	if isMustDodge(th) then return false end
	if not ap.interruptible(th) or not ap.canAttack(true) then return false end
	local enemyLeft = (th.contactAbs or now) - now
	if enemyLeft < 0.05 then return false end
	local baseMargin = th.kind == "M2" and (Config.AP_InterruptMargin or 0.055) * 0.6
	                                    or  (Config.AP_InterruptMargin or 0.055)
	local netLag = getPingRaw() * (Config.AP_InterruptNetK or 0.5)

	local m1Hit, m1Combo = nil, nil
	if ap.flatDist(th.attackerModel) <= ap.reach() then
		local d, combo = ap.ownM1Delay()
		if d then m1Hit, m1Combo = d + netLag, combo end
		if m1Hit and m1Hit + baseMargin >= enemyLeft then m1Hit = nil end
	end

	local m2Hit, m2Var, m2Iframes = nil, nil, false
	if Config.AP_InterruptM2 ~= false and ap.m2Ready()
	   and ap.flatDist(th.attackerModel) <= ap.reachM2() then
		local d, variant = ap.ownM2Delay()
		if d then
			m2Iframes = ap.m2GrantsIFrames()
			if m2Iframes then
				if netLag + (Config.AP_M2IFrameMargin or 0.035) < enemyLeft then
					m2Hit, m2Var = d + netLag, variant
				end
			elseif d + netLag + baseMargin < enemyLeft then
				m2Hit, m2Var = d + netLag, variant
			end
		end
	end

	local useM2 = (m2Hit ~= nil)
	if useM2 and m1Hit and Config.AP_InterruptPreferM2 == false then
		useM2 = m2Hit < m1Hit
	end
	if not useM2 and not m1Hit then return false end

	local ownHit, tag
	if useM2 then
		if not ap.fireM2(th.attackerModel, "interrupt", m2Var) then
			if not m1Hit then return false end
			useM2 = false
		end
	end
	if useM2 then
		ownHit = m2Hit
		tag = ("M2%s%s"):format(m2Var and ("/" .. m2Var) or "", m2Iframes and "+IF" or "")
		if m2Iframes then V93.markOwnM2IFrames(now, "interrupt/M2+IF") end
	else
		if not ap.fireM1(th.attackerModel, "interrupt", true, true) then return false end
		ownHit = m1Hit
		tag = ("M1/c%d"):format(m1Combo or 0)
	end
	th.interruptAttempted = true
	State.interruptFiredFrame = FrameId
	State.status = useM2 and "INTERRUPT-M2" or "INTERRUPT"
	diagPush(("INTERRUPT t=%.2f %s %s(%s) via=%s ours=%.0fms enemy=%.0fms margin=%.0fms m1=%s m2=%s guard=fallback")
		:format(now, th.name or "?", th.kind or "?", th.style or "?", tag,
			(ownHit or 0) * 1000, enemyLeft * 1000, baseMargin * 1000,
			m1Hit and ("%.0fms"):format(m1Hit * 1000) or "no",
			m2Hit and ("%.0fms"):format(m2Hit * 1000) or "no"))
	return false
end

function State.ap.fireM1(model, why, priority, dropGuard)
		local ap = State.ap
		local now = os.clock()
		if ap.m1TxnActive(now) then return false end
		if now < ap.nextM1At then return false end
		if not ap.canAttack(dropGuard) then return false end
	local m1 = ap.getM1()
	if not m1 then return false end
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	ap.snapTo(hrp)
	ap.nextM1At = now + (Config.AP_PollGap or 0)
	local swung = false
	if ap.fireOK then
		local char = localChar()
		if char then swung = ap.fireM1Custom(char, model, nil, false, priority, dropGuard) end
	elseif ap.tryM1Fn then
		local ok, res = pcall(ap.tryM1Fn)
		swung = ok and res == true
	else
		pcall(function() m1.OnM1Activated() end)
		swung = true
	end
		if swung then
			State.status      = "AUTO-M1"
			State.flashUntil  = now + 0.2
			State.autoM1Count = (State.autoM1Count or 0) + 1
		end
	return swung
end

function State.ap.testSwing()
	local ap = State.ap
	if not ap.getM1() then return 0, false end
	local char = localChar()
	if not char then return 0, false end
	local combo
	if Config.AP_ComboMode == "Fixed" then
		combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
		elseif ap.fireOK and ap.tryM1Fn then
			combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 3) + 1
		else
		combo = 1
	end
	local ok = false
	if ap.fireOK then
		ok = ap.fireM1Custom(char, nil, combo, true)
	elseif ap.tryM1Fn then
		local r; local s = pcall(function() r = ap.tryM1Fn() end); ok = s and r == true
	end
	return combo, ok
end

function State.ap.onPerfectParry(attackerName, kind)
	if not Config.AutoPlay or Config.AP_PunishOnParry == false then return end
	local plr   = attackerName and Players:FindFirstChild(attackerName)
	local model = plr and plr.Character
	if not model then return end
	if Config.BoxingCounter and (os.clock() - (State.lastCounter or 0)) < 0.40 then return end
	local stun = (kind == "M2") and (Config.AP_M2Stun or 1.0) or (Config.AP_M1Stun or 0.5)
	State.ap.punishTgt   = model
	State.ap.punishUntil = os.clock() + stun
	State.ap.punishFresh = true
end

function State.ap.step(now)
	if not Config.AutoPlay or Config.AP_PunishOnParry == false then return end
	local ap = State.ap
	local tgt = ap.punishTgt
	if not tgt then return end
	local hum = tgt.Parent and tgt:FindFirstChildOfClass("Humanoid")
	if (not hum) or hum.Health <= 0 or now > ap.punishUntil then
		ap.punishTgt = nil
		ap.punishFresh = false
		return
	end
	if ap.flatDist(tgt) > ap.reach() then return end
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
	end
	if ap.fireM1(tgt, "punish", ap.punishFresh) then ap.punishFresh = false end
end

local function evasiveGranted()
	local c = localChar()
	return c and c:GetAttribute("OutnumberedEvasiveGrant") == true or false
end

local function dodgeReady()
	local c = localChar()
	if (os.clock() - State.lastDodge) < Config.DodgeMinSpacing then return false end
	if c then
		if c:GetAttribute("IFRAMECD") == true then return false end
		local remG = c:GetAttribute("EvasiveCooldownRemaining")
		if type(remG) == "number" and remG > 0 then return false end
	end
	local since = os.clock() - State.lastDodge
	if evasiveGranted() then
		local fullCd = GameData.evPredictCooldown or Config.DodgeCooldown
		local grantFloor = GameData.evCooldown or 1.5
		if (State.dodgeRejects or 0) >= 2 and since < fullCd then
			if not State.dodgeGateSaid then
				State.dodgeGateSaid = true
				diagPush(("DODGE-GATE  грант активен, но %d отказа подряд → откат на полный CD %.2fс (прошло %.2fс)")
					:format(State.dodgeRejects, fullCd, since))
			end
			return false
		end
		if since < grantFloor then
			if not State.dodgeGateSaid then
				State.dodgeGateSaid = true
				diagPush(("DODGE-GATE  грант активен → серверный Evasive.Cooldown %.2fс, прошло %.2fс")
					:format(grantFloor, since))
			end
			return false
		end
		State.dodgeGateSaid = nil
		return true
	end
	if Config.UseServerCooldown and c then
		return true
	end
	return since >= (GameData.evPredictCooldown and (GameData.evPredictCooldown + 0.05)
		or Config.DodgeCooldown)
end

local function canDodgeNow(force)
	local c = localChar()
	if not c then return false, "no-char" end
	if c:GetAttribute("Equip") == false then return false, "Unequipped" end
	for _, attr in ipairs(Config.DodgeHardStates) do
		if c:GetAttribute(attr) == true then return false, attr end
	end
	if not force and not evasiveGranted() and Config.NoDodgeWhileStunned
	   and (c:GetAttribute("Stunned") == true or c:GetAttribute("CantAnything") == true) then
		return false, "Stunned"
	end
	if c:GetAttribute("CombatAttacking") == true then return false, "CombatAttacking" end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum and (hum.Health <= 0
	   or hum:GetState() == Enum.HumanoidStateType.Dead
	   or hum:GetState() == Enum.HumanoidStateType.Physics) then
		return false, "humanoid-state"
	end
	return true, nil
end

local function releaseBlock()
	if not State.blocking then return end
	State.blocking  = false
	State.holdUntil = 0
	sendDeactivate(true)
end

local function fireBlock(tsServer)
	if not Config.Enabled then return nil end
	local ok, reason = canBlockNow()
	if not ok then
		State.blockedReason = reason
		return nil
	end
	State.blockedReason = nil
	if not sendActivate(tsServer) then return nil end
	State.blocking   = true
	State.lastPress  = os.clock()
	State.fireCount  = State.fireCount + 1
	State.status     = "PARRY"
	State.flashUntil = os.clock() + 0.14
	return tsServer
end

local refreshContact = LPH_NO_VIRTUALIZE(function(th)
	local now = os.clock()
	if th.kind == "M2" and not th.variantLocked and th.attackerModel then
		local okv, av = pcall(function() return th.attackerModel:GetAttribute("M2VariantId") end)
		if okv and type(av) == "string" and av ~= "" then
			th.variantLocked = true
			if av ~= th.variant then
				local prev = th.hitTL
				th.variant = av
				local newTL = hitTimeline({ t = "M2", s = th.style, mom = th.mom, id = th.id,
					variant = av, name = th.animName }, th.combo, th.attackMult)
				if type(newTL) == "number" and newTL > 0 then
					th.hitTL = newTL
					th.contact0 = math.max(0, (th.contact0 or 0) + (newTL - (prev or newTL)))
					diagPush(("VARIANT t=%.2f  %s  M2 → %s  hitTL %.0f→%.0fms (server attr)")
						:format(now, tostring(th.name), av, (prev or 0)*1000, newTL*1000))
				end
			end
		end
	end
	local remaining = th.contact0 - (now - th.detectClock)

	local playing = true
	if th.track then
		playing = safeGet(th.track, "IsPlaying", true)
		local tp = safeGet(th.track, "TimePosition", th.initTP)
		if type(tp) ~= "number" then tp = th.initTP end

		local lastTP    = th.lastTP or th.initTP
		local lastClock = th.lastTPClock or th.detectClock
		local dtReal    = now - lastClock
		if dtReal > 0.0005 then
			local inst = (tp - lastTP) / dtReal
			if inst < 0 then inst = 0 end
			local a = Config.LiveSpeedSmooth or 0.35
			th.liveSpeed = th.liveSpeed and (th.liveSpeed * (1 - a) + inst * a) or inst
			th.lastTP = tp; th.lastTPClock = now
		end

		if playing and tp > (th.maxTP or th.initTP) + 0.0005 then
			th.maxTP = tp; th.trackSeen = true; th.lastAdvanceClock = now
			if not th.firstProgressClock then
				th.firstProgressClock = now
				diagPush(("TRACE-ANIM t=%.3f %s %s s%d firstProgress=%+.0fms tp=%.3f init=%.3f live=%.2f")
					:format(now, th.name or "?", th.kind or "?", th.strike or 1,
						(now-th.detectClock)*1000, tp, th.initTP or 0, th.liveSpeed or 0))
			end
		elseif not playing and not th.trackStopClock then
			th.trackStopClock = now
			diagPush(("TRACE-ANIM t=%.3f %s %s s%d stopped=%+.0fms tp=%.3f maxTP=%.3f hitTL=%.3f")
				:format(now, th.name or "?", th.kind or "?", th.strike or 1,
					(now-th.detectClock)*1000, tp, th.maxTP or th.initTP or 0, th.hitTL or 0))
		end

		if th.kind == "M1" and playing and Config.LiveM1Timer ~= false then
			if tp < th.hitTL - 0.001 then
				local nominal = math.max(th.initSpeed or 1, 0.05)
				local floor   = nominal * (Config.LiveM1SpeedFloor or 0.45)
				local sp      = math.max(th.liveSpeed or nominal, floor)
				local liveRemain = (th.hitTL - tp) / sp
				remaining = math.max(remaining, liveRemain)
			end
		elseif (th.kind == "M2" or th.kind == "SKILL") and playing then
			if Config.LiveHeavyTimer and tp < th.hitTL - 0.001 then
				local nominal = math.max(th.initSpeed or 1, 0.05)
				local floor   = nominal * (Config.LiveSpeedFloor or 0.15)
				local sp      = math.max(th.liveSpeed or nominal, floor)
				local liveRemain = (th.hitTL - tp) / sp
				remaining = math.max(remaining, liveRemain)
				th.heldBy = (th.liveSpeed and th.liveSpeed < nominal * 0.6) and
					(liveRemain - math.max(th.contact0 - (now - th.detectClock), 0)) or 0
			else
				local stalledFor = now - (th.lastAdvanceClock or th.detectClock)
				if tp < th.hitTL - 0.001 and stalledFor > (Config.ChargeStallMs / 1000) then
					remaining = math.max(remaining, th.hitTL - tp)
				end
			end
		end

		if th.kind == "M1" and th.trackSeen and not playing and not th.feinted then
			local reached = (th.maxTP or th.initTP)
			local nearContact = (th.contactAbs - now) <= Config.FeintGraceMs / 1000
			if reached < th.hitTL * Config.FeintFrac and not nearContact then
				th.feinted = true
			end
		end
	end

	th.trackPlaying = playing
	th.contactAbs = now + math.max(remaining, 0)
	return remaining
end)

local function insideAutoFOV(attackerHRP)
	local fov = math.clamp(tonumber(Config.FOV) or 360, 1, 360)
	if fov >= 359.5 then return true end
	local cam = Workspace.CurrentCamera
	if not cam or not attackerHRP then return true end
	local ok, point, visible = pcall(function()
		local p, onScreen = cam:WorldToViewportPoint(attackerHRP.Position)
		return p, onScreen
	end)
	if not ok or not point or point.Z <= 0 or not visible then return false end
	local vp = cam.ViewportSize
	local dx, dy = point.X - vp.X * 0.5, point.Y - vp.Y * 0.5
	local focal = math.max(vp.Y * 0.5, 1)
	local angle = math.deg(math.atan(math.sqrt(dx * dx + dy * dy) / focal))
	return angle <= fov * 0.5
end

local function _attrTrue(m, a) return m:GetAttribute(a) == true end
local function serverAttackProof(model)
	if not model then return false end
	local ok, v = pcall(_attrTrue, model, "M1")
	if ok and v then return true end
	ok, v = pcall(_attrTrue, model, "M2")
	if ok and v then return true end
	ok, v = pcall(_attrTrue, model, "CombatAttacking")
	return (ok and v) and true or false
end

local function serverHitboxProof(ownerName)
	if not ownerName then return false end
	local folder = Workspace:FindFirstChild("Hitboxes")
	if not folder then return false end
	for _, part in ipairs(folder:GetChildren()) do
		local o = part:FindFirstChild("Owner")
		if o and o.Value == ownerName then
			local a = part:FindFirstChild("AttackName")
			local an = a and a.Value
			if an == "M1" or an == "M2" then return true end
		end
	end
	return false
end

local onAttack = LPH_NO_VIRTUALIZE(function(attackerHRP, info, model, id, track)
	local myHRP = localHRP()
	if not myHRP then return end
	if not insideAutoFOV(attackerHRP) then return end
	local dist = (attackerHRP.Position - myHRP.Position).Magnitude
	if dist > Config.Range then
		local closingSpeed = 0
		pcall(function()
			local toMe = (myHRP.Position - attackerHRP.Position)
			local flat = Vector3.new(toMe.X, 0, toMe.Z)
			if flat.Magnitude > 0.1 then
				local av = attackerHRP.AssemblyLinearVelocity
				closingSpeed = -Vector3.new(av.X, 0, av.Z):Dot(flat.Unit)
			end
		end)
		local canClose = math.max(closingSpeed, 0) * Config.MaxWait
		if dist > Config.Range + canClose then return end
	end
	if info.t == "M2" and not Config.HeavyEnabled then return end

	local plr  = Players:GetPlayerFromCharacter(model)
	local name = plr and plr.Name or model.Name

	local suspectSwing = false
	if Config.AntiDecoy then
		local sig = State.antiDecoySig; if not sig then sig = {}; State.antiDecoySig = sig end
		local cnt = State.antiDecoyCount; if not cnt then cnt = {}; State.antiDecoyCount = cnt end
		local nowc = os.clock()
		local prev = sig[name]
		if prev and (nowc - prev) < (Config.AntiDecoyGap or 0.12) then
			cnt[name] = (cnt[name] or 1) + 1
			if cnt[name] > (Config.AntiDecoyMaxBurst or 3) then
				if (nowc - (State.lastAntiDecoyLog or 0)) > 1 then
					State.lastAntiDecoyLog = nowc
					aclog(("[decoy] burst cap %dx %s from %s — dropped"):format(cnt[name], tostring(info.t), name))
				end
				return
			end
			suspectSwing = true
			if (nowc - (State.lastAntiDecoyLog or 0)) > 1 then
				State.lastAntiDecoyLog = nowc
				aclog(("[resolver] rapid %s from %s — kept as SUSPECT (needs swing-id proof)")
					:format(tostring(info.t), name))
			end
		else
			cnt[name] = 1
		end
		sig[name] = nowc
	end

	local attrProof = serverAttackProof(model)

	local combo = (info.t == "M1") and (info.combo or nextCombo(name)) or 1

	local aMult    = attackSpeedMult(model)
	local heightAttr, bodyHeightScale, modelHeight = heightDiag(model)
	local speed    = 1
	local already  = 0
	if track then
		local okS, sp = pcall(function() return track.Speed end)
		if okS and type(sp) == "number" and sp > 0.05 then speed = sp end
		local okT, tp = pcall(function() return track.TimePosition end)
		if okT and type(tp) == "number" and tp > 0 then already = tp end
	end
	local hitTL    = info.contacts and (info.contacts[1] / math.max(speed, 0.05))
		or hitTimeline(info, combo, aMult)
	local remaining0 = math.max(0, hitTL - already)
	if remaining0 > Config.MaxWait then return end

	local vlead = velLead(attackerHRP)
	local nowClock  = os.clock()
	local nowServer = Workspace:GetServerTimeNow()
	local netOneWay, statsRtt = pingDiagSnapshot()
	local pingRawDetect, pingMedDetect, uplinkDetect = getPingRaw(), getPing(), uplink()
	local trackLength, trackPlaying = 0, false
	if track then
		pcall(function() trackLength = track.Length end)
		pcall(function() trackPlaying = track.IsPlaying end)
	end
	local th = {
		name = name, kind = info.t, style = info.s, mom = info.mom, id = id,
		combo = combo, variant = info.variant, animName = info.name,
		track = track, hitTL = hitTL, initTP = already, initSpeed = speed,
		detectClock = nowClock, detectServer = nowServer, contact0 = remaining0,
		contactAbs = nowClock + remaining0, velLead = vlead,
		attackerHRP = attackerHRP, attackerModel = model,
		heightAttr = heightAttr, bodyHeightScale = bodyHeightScale, modelHeight = modelHeight,
		attackMult = aMult,
		pingOneWayDetect = netOneWay, pingStatsDetect = statsRtt,
		pingRawDetect = pingRawDetect, pingMedDetect = pingMedDetect, uplinkDetect = uplinkDetect,
		trackLengthDetect = trackLength, trackPlayingDetect = trackPlaying,
		attackerPosDetect = attackerHRP.Position, victimPosDetect = myHRP.Position,
		attackerVelDetect = attackerHRP.AssemblyLinearVelocity, victimVelDetect = myHRP.AssemblyLinearVelocity,
		pressed = false, dodged = false,
		pressDt = nil,
		faceDot = nil,
		suspect = suspectSwing,
		serverProven = (not suspectSwing) and attrProof or false,
		provenBy = ((not suspectSwing) and attrProof) and "attr" or nil,
		serverProofClock = nil,
	}
	if th.serverProven then th.serverProofClock = nowClock end
	if track then
		for i = #Threats, 1, -1 do
			local old = Threats[i]
			if old.name == name and old.track == track and not old.resolved and not old.staleTrack then
				old.staleTrack = true
				if Config.DeepDiag then
					diagPush(("TRACE-STALE t=%.3f %s %s superseded: same track restarted (age=%.0fms, was dt=%+.0fms)")
						:format(nowClock, name, tostring(old.kind),
							(nowClock - old.detectClock) * 1000,
							(old.contactAbs - nowClock) * 1000))
				end
			end
		end
	end
	Threats[#Threats+1] = th

	do
		local key = model or attackerHRP or name
		if key then
			State.lastSwingBy = State.lastSwingBy or setmetatable({}, { __mode = "k" })
			State.swingGapBy  = State.swingGapBy or setmetatable({}, { __mode = "k" })
			local prev = State.lastSwingBy[key]
			if prev then State.swingGapBy[key] = nowClock - prev end
			State.lastSwingBy[key] = nowClock
		end
	end

	local rec = { clock = nowClock, detectServer = nowServer, type = info.t, style = info.s,
	              id = id, contact = remaining0, pingRaw = pingRawDetect, combo = combo,
	              speed = speed, matched = false, th = th, strike = 1 }
	th.rec = rec
	local q = Pending[name]; if not q then q = {}; Pending[name] = q end
	q[#q+1] = rec
	if info.contacts and info.contacts[2] then
		local group = { cancelled = false, held = false }
		th.group, th.strike = group, 1
		local hit2 = info.contacts[2] / math.max(speed, 0.05)
		local rem2 = math.max(0, hit2 - already)
		local th2 = table.clone(th)
		th2.hitTL, th2.contact0, th2.contactAbs = hit2, rem2, nowClock + rem2
		group.lastContact = th2.contactAbs
		th2.strike, th2.pressed, th2.dodged = 2, false, false
		th2.pressDt, th2.faceDot, th2.rec = nil, nil, nil
		th2.hitboxSeen, th2.hitboxSynced, th2.hitboxPart = nil, nil, nil
		Threats[#Threats+1] = th2
		local rec2 = { clock = nowClock, detectServer = nowServer, type = info.t, style = info.s,
			id = id, contact = rem2, pingRaw = rec.pingRaw, combo = combo,
			speed = speed, matched = false, th = th2, strike = 2 }
		th2.rec = rec2
		q[#q+1] = rec2
		diagPush(("MULTI  t=%.2f  %s M2(Boxing) contacts=[%.0f,%.0f]ms markers=[%.0f,%.0f]ms speed=%.2f")
			:format(nowClock, name, remaining0*1000, rem2*1000,
				info.contacts[1]*1000, info.contacts[2]*1000, speed))
	end
	while #q > 10 do table.remove(q, 1) end

	State.lastThreat = { name = name, type = info.t, dist = dist, hitIn = remaining0 }
	if State.status ~= "PARRY" then State.status = "THREAT" end
	State.parryCount = State.parryCount + 1

	if Config.DeepDiag then
		diagPush(("TRACE-DETECT t=%.3f srv=%.3f %s %s id=%s tp=%.3f/%.3f spd=%.2f playing=%s | net1w=%sms statsRTT=%sms rawRTT=%.0fms medRTT=%.0fms uplink=%.0fms | av=(%.1f,%.1f) mv=(%.1f,%.1f)")
			:format(nowClock, nowServer, name, info.t, tostring(id), already, trackLength or 0, speed,
				tostring(trackPlaying), netOneWay and ("%.0f"):format(netOneWay*1000) or "?",
				statsRtt and ("%.0f"):format(statsRtt*1000) or "?", pingRawDetect*1000,
				pingMedDetect*1000, uplinkDetect*1000,
				th.attackerVelDetect.X, th.attackerVelDetect.Z, th.victimVelDetect.X, th.victimVelDetect.Z))
		local pRaw  = pingRawDetect
		local pMult = hitTL / (hitTL + math.clamp(pRaw * 0.5, 0, 0.35))
		diagPush(("SWING  t=%.2f  %s  %s(%s)  combo=%d  dist=%.0f  contact=%.0fms  spd=%.2f  aMult=%.2f  height=%s  bodyScale=%s  modelY=%s  pingMult=%.2f  hitTL=%.0fms  vlead=%.0fms  ping=%.0f")
			:format(os.clock(), name, info.t, info.s, combo, dist, remaining0*1000, speed, aMult,
				heightAttr and ("%.3f"):format(heightAttr) or "?",
				bodyHeightScale and ("%.3f"):format(bodyHeightScale) or "?",
				modelHeight and ("%.2f"):format(modelHeight) or "?",
				pMult, hitTL*1000, vlead*1000, pRaw*1000))
	end
end)

local function dirIsClear(origin, dir, allowedModel)
	if not Config.DodgeWallCheck then return true end
	local char = localChar()
	if not char then return true end
	local params = V93.dodgeParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		V93.dodgeParams = params
	end
	if V93.dodgeChar ~= char then
		V93.dodgeChar = char
		local ok = pcall(function() params.FilterDescendantsInstances = { char } end)
		if not ok then return true end
	end
	local hit
	pcall(function() hit = Workspace:Raycast(origin, dir.Unit * Config.DodgeWallDist, params) end)
	if not hit then return true end
	local part = hit.Instance
	if part and (not part.CanCollide or part:IsDescendantOf(char or part)
		or (allowedModel and part:IsDescendantOf(allowedModel))) then return true end
	return false
end

local function bestDodgeDir(now, preferBack)
	if not Config.SmartDodgeDir then return nil, false end
	local me = localHRP(); if not me then return nil, false end
	local best, bestC
	for _, th in ipairs(Threats) do
		if th.threatens and th.attackerHRP and th.attackerHRP.Parent then
			if not bestC or th.contactAbs < bestC then best, bestC = th, th.contactAbs end
		end
	end
	if not best then return nil, false end
	local aHRP  = best.attackerHRP
	local aLook = aHRP.CFrame.LookVector
	local flook = Vector3.new(aLook.X, 0, aLook.Z)
	local toMe  = me.Position - aHRP.Position
	toMe = Vector3.new(toMe.X, 0, toMe.Z)
	if flook.Magnitude < 0.05 or toMe.Magnitude < 0.05 then return nil, false end
	flook = flook.Unit
	local away = toMe.Unit
	local perp = Vector3.new(-flook.Z, 0, flook.X)
	if perp:Dot(away) < 0 then perp = -perp end

	local candidates
	if preferBack then
		candidates = {
			away,
			(away * 0.7 + perp * 0.5).Unit,
			(away * 0.7 - perp * 0.5).Unit,
			perp,
			-perp,
		}
	else
		local ideal = (perp * 0.8 + away * 0.5)
		candidates = {
			ideal.Magnitude > 0.05 and ideal.Unit or away,
			((-perp) * 0.8 + away * 0.5).Unit,
			away,
			perp,
			-perp,
		}
	end
	local origin = me.Position
	for _, dir in ipairs(candidates) do
		if dir and dir.Magnitude > 0.05 and dirIsClear(origin, dir) then
			return dir.Unit, false
		end
	end
	return nil, true
end

function State.bestAliForwardDodgeDir(th)
	local me = localHRP()
	local aHRP = th and th.attackerHRP
	if not me or not aHRP or not aHRP.Parent then return nil, "no-target" end

	local origin = th.geomOrigin or aHRP.Position
	local look = th.geomLook
	if not look or look.Magnitude < 0.05 then
		local lv = aHRP.CFrame.LookVector
		look = Vector3.new(lv.X, 0, lv.Z)
	end
	if look.Magnitude < 0.05 then return nil, "no-look" end
	look = look.Unit
	local forward = tonumber(th.geomForward) or 0
	local target = origin + look * forward
	local delta = target - me.Position
	local toward = Vector3.new(delta.X, 0, delta.Z)
	local targetDist = toward.Magnitude
	if targetDist < 0.05 then return nil, "already-in-sweet-spot" end
	toward = toward.Unit
	local side = Vector3.new(-toward.Z, 0, toward.X)
	local allowed = aHRP.Parent
	local duration = math.max(tonumber(Config.DashDuration) or 0.2, 0.05)
	local maxTravel = (tonumber(Config.DashSpeed) or 30) * duration
	local travel = math.min(targetDist, maxTravel)
	local speed = travel / duration
	local startDelta = aHRP.Position - me.Position
	local startDist = Vector3.new(startDelta.X, 0, startDelta.Z).Magnitude
	local candidates = {
		{ toward, "hitbox-center", speed },
		{ (toward * 0.8 + side * 0.35).Unit, "hitbox-center-side", speed },
		{ (toward * 0.8 - side * 0.35).Unit, "hitbox-center-side", speed },
	}
	for _, candidate in ipairs(candidates) do
		if dirIsClear(me.Position, candidate[1], allowed) then
			return candidate[1], candidate[2], candidate[3], startDist, targetDist, travel
		end
	end
	return nil, "blocked"
end

local function performDodge(now, reason, preferBack, force, bypassAutoOff, dodgeTarget)
	if Config.AutoDodge == false and not bypassAutoOff then
		if State.lastDodgeRefuse ~= "AutoDodge-off" then
			State.lastDodgeRefuse = "AutoDodge-off"
			diagPush(("DODGE-SKIP t=%.2f  %s  (AutoDodge disabled)"):format(now, reason))
		end
		return false
	end
	local tx0 = State.dodgeTxn
	if tx0 and tx0.pending then return false end
	do
		local ch0 = localChar()
		if ch0 and (ch0:GetAttribute("IFRAMES") == true or ch0:GetAttribute("UltraInstinct") == true) then
			if State.lastDodgeRefuse ~= "already-iframed" then
				State.lastDodgeRefuse = "already-iframed"
				diagPush(("DODGE-SKIP t=%.2f  %s  (already invulnerable: IFRAMES live, src=%s)")
					:format(now, reason, tostring(State.ownIFrameTag or "game")))
			end
			return false
		end
	end
	local can, why = canDodgeNow(force)
	if not can then
		if State.lastDodgeRefuse ~= why then
			State.lastDodgeRefuse = why
			diagPush(("DODGE-SKIP t=%.2f  %s  (cannot dodge: %s)"):format(now, reason, tostring(why)))
		end
		return false
	end
	State.lastDodgeRefuse = nil

	local granted = evasiveGranted()
	local isAliAbuse = reason == "ali-dodge-abuse"
	local timingTarget = dodgeTarget
	if not timingTarget then
		for _, candidate in ipairs(Threats) do
			if type(candidate.contactAbs) == "number" and candidate.contactAbs >= now
			   and not candidate.resolved and not candidate.coveredByDodge
			   and (not timingTarget or candidate.contactAbs < timingTarget.contactAbs) then
				timingTarget = candidate
			end
		end
	end
	local optionalDodge = not (reason == "must-dodge" or reason == "must-dodge(unblockable→back)"
		or (type(reason) == "string" and reason:sub(1, 9) == "must-dodge"))
	if optionalDodge and timingTarget and type(timingTarget.contactAbs) == "number" then
		local contactIn = timingTarget.contactAbs - now
		local net = math.max(uplink(), 0.02)
		local duration = GameData.iframeDur or Config.IFrameDur or 0.30
		local frame = math.max(V93.lookahead or 0, V93.frameDt or (1/60))
		local centerLead = net + duration * 0.5 + (Config.DodgeCenterBias or 0)
		if timingTarget.kind == "M2" then centerLead = centerLead + (Config.HeavyDodgeBias or 0) end
		if contactIn > centerLead + frame then
			if not timingTarget.dodgeCenterWaitLogged then
				timingTarget.dodgeCenterWaitLogged = true
				diagPush(("DODGE-WAIT/CENTER t=%.2f %s contactIn=%.0fms target=%.0fms frame=%.0fms")
					:format(now, tostring(reason), contactIn*1000, centerLead*1000, frame*1000))
			end
			return false
		end
		if contactIn <= net + frame then
			if not timingTarget.dodgeTooLateLogged then
				timingTarget.dodgeTooLateLogged = true
				diagPush(("DODGE-SKIP/TOO-LATE t=%.2f %s contactIn=%.0fms minArrival=%.0fms")
					:format(now, tostring(reason), contactIn*1000, (net+frame)*1000))
			end
			return false
		end
	end

	local dir, dirMode, dodgeSpeed, startDist, targetDist, travel
	if isAliAbuse then
		dir, dirMode, dodgeSpeed, startDist, targetDist, travel = State.bestAliForwardDodgeDir(dodgeTarget)
		if not dir then
			diagPush(("ALI-DODGE-SKIP t=%.2f gate=trajectory reason=%s"):format(now, tostring(dirMode)))
			return false
		end
		diagPush(("ALI-DODGE-TRAJECTORY t=%.2f mode=%s startDist=%.2f targetDist=%.2f travel=%.2f speed=%.1f")
			:format(now, tostring(dirMode), startDist or -1, targetDist or -1, travel or -1, dodgeSpeed or -1))
	else
		dir = bestDodgeDir(now, preferBack)
		dirMode = dir and "smart" or "input"
	end
	if dir and isAliAbuse then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then pcall(V93.humMove, hum, dir) end
		State.ap.dodgeSteerDir = dir
		State.ap.dodgeSteerUntil = now + math.max((uplink() * 0.5) + 0.06, 0.12)
	end
	sendDodge(dir, dodgeSpeed)
	if granted then State.grantEscapes = (State.grantEscapes or 0) + 1 end
	if type(reason) == "string" and reason:sub(1, 4) == "dual" then
		State.dualDodgeCount = (State.dualDodgeCount or 0) + 1
	end
	State.lastDodgeRefuse = nil
	local tx = State.dodgeTxn
	local ifLat0 = math.max(uplink(), 0.02)
	local ifDur0 = GameData.iframeDur or Config.IFrameDur or 0.30
	local iframeLo = now + ifLat0
	local iframeHi = iframeLo + ifDur0
	tx.pending, tx.confirmed = true, false
	tx.fire, tx.lo, tx.hi = now, iframeLo, iframeHi
	local ackWindow = granted and 1.2
		or math.max(GameData.confirmTimeout or Config.DodgeConfirm or 0.18, 0.6)
	tx.ackDeadline = now + ackWindow
	tx.untilAt, tx.reason = iframeHi + 0.08, reason
	tx.abuseThreat = isAliAbuse and dodgeTarget or nil
	tx.dodgeDirMode = dirMode
	tx.perfectConfirmed, tx.perfectAt = false, nil
	if (counterStyle() or "") == "ali" and Config.SkillAddon and Config.AliEvasiveCounter then
		diagPush(("ALI-DODGE-ARM t=%.2f reason=%s await=StyleEvasiveCounter proc=one-perfect-dodge specialCd=6s range=22 ignoreNormalM2Cd=true deadline=%.0fms")
			:format(now, tostring(reason), (tx.untilAt-now)*1000))
	end
	tx.evCounterFired, tx.evCounterExpiredLogged = false, false
	tx.evCounterAwaitIframeLogged, tx.evCounterTargetGateLogged, tx.evCounterStateGate = false, false, nil
	local planned, soonest = 0, nil
	for _, th in ipairs(Threats) do
		local c = th.contactAbs
		if c >= iframeLo - 0.03 and c <= iframeHi + 0.03 then
			planned = planned + 1
			if not soonest or c < soonest then soonest = c end
		end
	end
	State.lastDodgeInfo = {
		fire=now, reason=reason, contactAbs=soonest, iframeLo=iframeLo, iframeHi=iframeHi,
		dir=dirMode or (dir and "smart" or "input"), planned=planned,
	}
	diagPush(("DODGE  t=%.2f  %s%s  planned=%d  dir=%s  fire→contact=%s  iframe=[+%.0f,+%.0f]ms")
		:format(now, reason, granted and " [GRANT]" or "", planned, State.lastDodgeInfo.dir,
			soonest and ("%.0fms"):format((soonest-now)*1000) or "n/a",
			ifLat0*1000, (ifLat0+ifDur0)*1000))
	return true
end

local function updateDodgeTxn(now)
	local tx = State.dodgeTxn
	if not tx or not tx.pending then return end
	local c = localChar()
	if not tx.confirmed and c and c:GetAttribute("IFRAMES") == true then
		tx.confirmed = true
		tx.lo, tx.hi = now, now + (GameData.iframeDur or Config.IFrameDur or 0.30)
		tx.untilAt = tx.hi + 0.08
		if State.lastDodgeInfo then
			State.lastDodgeInfo.iframeLo, State.lastDodgeInfo.iframeHi = tx.lo, tx.hi
		end
		local covered = 0
		for _, th in ipairs(Threats) do
			local contact = th.contactAbs
			if not th.dodged and contact >= tx.lo
				and contact <= tx.hi then
				th.dodged, th.coveredByDodge = true, true
				covered = covered + 1
			end
		end
		diagPush(("DODGE-CONFIRM t=%.2f  %s  covered=%d  window=[+%.0f,+%.0f]ms")
			:format(now, tostring(tx.reason or "?"), covered,
				(tx.lo-tx.fire)*1000, (tx.hi-tx.fire)*1000))
	end
	if not tx.confirmed and now >= (tx.ackDeadline or tx.untilAt) then
		State.dodgeRejects = (State.dodgeRejects or 0) + 1
		diagPush(("DODGE-REJECT/EARLY-FALLBACK t=%.2f %s ack=%.0fms IFRAMES not confirmed; EDF/parry restored (подряд=%d)")
			:format(now, tostring(tx.reason or "?"), (now-(tx.fire or now))*1000, State.dodgeRejects))
		tx.pending, tx.confirmed, tx.reason = false, false, nil
		tx.abuseThreat, tx.perfectConfirmed, tx.perfectAt = nil, false, nil
		State.ap.dodgeSteerDir, State.ap.dodgeSteerUntil = nil, 0
		return
	end
	local hardClose = tx.untilAt
	local budget = tx.ackDeadline or 0
	local awaitingProc = Config.AliEvasiveCounter
		and (tx.reason == "ali-dodge-abuse")
		and not tx.perfectConfirmed
	if (not tx.confirmed or awaitingProc) and budget > hardClose then hardClose = budget end
	if tx.perfectConfirmed and not tx.evCounterFired and Config.AliEvasiveCounter then
		local ttl = math.min(6 * (Config.AliProcTTLFrac or 0.25), Config.AliProcTTLMax or 1.5)
		local procEnd = (tx.perfectAt or 0) + ttl
		if procEnd > hardClose then hardClose = procEnd end
	end
	if now >= hardClose then
		if tx.reason == "ali-dodge-abuse" and tx.confirmed and not tx.perfectConfirmed then
			diagPush(("ALI-PERFECT-MISS/EXPIRE t=%.2f target=%s gate=no-StyleEvasiveCounter iframe=[%.0f,%.0f]ms")
				:format(now, tostring(tx.abuseThreat and tx.abuseThreat.name or "?"),
					((tx.lo or tx.fire)-tx.fire)*1000, ((tx.hi or tx.fire)-tx.fire)*1000))
		end
		if not tx.confirmed then
			State.dodgeRejects = (State.dodgeRejects or 0) + 1
			diagPush(("DODGE-REJECT t=%.2f  %s  IFRAMES not confirmed; EDF retained (подряд отказов=%d%s)")
				:format(now, tostring(tx.reason or "?"), State.dodgeRejects,
					State.dodgeRejects >= 2
						and (", гейт откатился на полный CD %.2fс"):format(
							GameData.evPredictCooldown or Config.DodgeCooldown)
						or ", пол остаётся 0.38с"))
		else
			State.dodgeRejects = 0
		end
		tx.pending, tx.confirmed, tx.reason = false, false, nil
		tx.abuseThreat, tx.perfectConfirmed, tx.perfectAt = nil, false, nil
		State.ap.dodgeSteerDir, State.ap.dodgeSteerUntil = nil, 0
	end
end

local _pubTargetModel, _pubThreat = nil, nil

local function publishTarget(th)
	_pubThreat = th
end

local publishVizTarget = LPH_NO_VIRTUALIZE(function(model, hrp)
	if type(getgenv) ~= "function" then return end
	if not model then
		if _pubTargetModel ~= nil then _pubTargetModel = nil; getgenv().AP_TARGET = nil end
		return
	end
	local th = _pubThreat
	if th and th.attackerModel ~= model then th = nil end
	local plr = Players:GetPlayerFromCharacter(model)
	if model ~= _pubTargetModel then
		_pubTargetModel = model
		getgenv().AP_TARGET = {
			model = model, hrp = hrp,
			name = plr and plr.Name or model.Name,
			style = th and th.style or nil,
			kind = th and th.kind or nil,
			contactIn = th and math.max((th.contactAbs or 0) - os.clock(), 0) or nil,
			threatens = th and th.threatens == true or false,
			t = os.clock(),
		}
		return
	end
	local t = getgenv().AP_TARGET
	if not t then _pubTargetModel = nil; return end
	t.hrp = hrp
	t.style = th and th.style or t.style
	t.kind = th and th.kind or nil
	t.contactIn = th and math.max((th.contactAbs or 0) - os.clock(), 0) or nil
	t.threatens = th and th.threatens == true or false
	t.t = os.clock()
end)

local schedulerStep = LPH_NO_VIRTUALIZE(function(now)
	updateDodgeTxn(now)
	State.updateAliM2Cooldown(now)
	State.updateCounterTxn(now)
	if State.interruptFiredFrame ~= FrameId and tryAliEvasiveCounter(now) then return end
	if #Threats == 0 and not State.blocking and not Config.AutoPlay then
		State.interruptCandidate = nil
		State.interruptThreatCount = 0
		State.multiThreat = false
		State.multiThreatN = 0
		State.vizTarget = nil
		V93.nearPress = math.huge
		V93.nearPressStamp = os.clock()
		publishTarget(nil)
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local up        = uplink()
	local ifDur     = GameData.iframeDur or Config.IFrameDur or 0.30
	local ifLat     = math.max(up, 0.02)
	local wantBlock = nil
	local faceTgt   = nil
	local imminent  = V93.imminentBuf
	table.clear(imminent)
	State.interruptCandidate = nil
	State.interruptThreatCount = 0
	table.clear(V93.interruptSeen)
	V93.nearPress = math.huge
	V93.nearPressStamp = os.clock()

		for i = #Threats, 1, -1 do
			local th = Threats[i]
			local trackGone = th.track and th.track.Parent == nil
			refreshContact(th)
			syncContactWithHitbox(th, now)
			local dt = th.contactAbs - now
			local noTrackExpired = (not th.track)
				and (now - th.detectClock) > ((th.contact0 or 0) + 0.35)

			local atkNeutralized = false
			if th.attackerModel and th.attackerModel.Parent then
				atkNeutralized = th.attackerModel:GetAttribute("Parried") == true
					or th.attackerModel:GetAttribute("Stunned") == true
					or th.attackerModel:GetAttribute("Ragdoll") == true
					or th.attackerModel:GetAttribute("Downed") == true
					or th.attackerModel:GetAttribute("GuardBroken") == true
			end
				if atkNeutralized then
					if Config.DeepDiag and not th.neutralLogged then
						th.neutralLogged = true
						diagPush(("NEUTRALIZED t=%.2f  %s  %s  → угроза снята: атакующий в Parried/Stunned, "
							.. "свинг заве��шиться не может (додж не нужен)"):format(now, th.name, th.kind))
					end
					State.threatNeutralized = (State.threatNeutralized or 0) + 1
					table.remove(Threats, i)
				elseif th.counterPendingId and State.counterTxn
					and th.counterPendingId == State.counterTxn.seq
					and (State.counterTxn.pending or State.counterTxn.confirmed) then
				elseif th.resolved or th.staleTrack or (th.group and th.group.cancelled) then
				table.remove(Threats, i)
			elseif th.feinted then
				if not th.feintLogged then
					th.feintLogged = true
					diagPush(("FEINT  t=%.2f  %s  %s  reached=%.0f%% of hitTL → ignored")
						:format(now, th.name, th.kind, (th.maxTP or 0) / math.max(th.hitTL, 0.001) * 100))
				end
				table.remove(Threats, i)
			elseif dt < -0.35 or noTrackExpired
				or (trackGone and (now - th.detectClock) > 0.5 and dt < Config.PerfectLead) then
			local coveredByGuard = th.coveredByHeldGuard == true
				or (Config.OmniBlock and State.blocking and th.enteredWindow
					and th.contactAbs <= (State.holdUntil or 0) + 0.05)
				if th.coveredByDodge or th.coveredByCounter then
				elseif coveredByGuard then
				State.guardCovered = (State.guardCovered or 0) + 1
			elseif Config.DeepDiag and not th.pressed and not th.dodged and not th.deadLogged then
				th.deadLogged = true
				local reason
				if th.everThreatened == nil or th.everThreatened == false then
					reason = ("geometry-rejected source=%s sid=%s")
						:format(tostring(th.recognitionSource or "none"), tostring(th.serverSwingId or (th.group and th.group.serverSwingId) or "none"))
					if th.offTarget then State.offTargetRej = (State.offTargetRej or 0) + 1 end
				elseif th.enteredWindow then
					reason = ("in-window но нажатия не было: threatens=%s geomLatched=%s blocked=%s")
						:format(tostring(th.threatens), tostring(th.geomLatched or false),
							tostring((th.rec and th.rec.blockedReason) or "-"))
				elseif th.contactPassedFast then
					reason = ("окно не открылось: контакт приле���ел быстре�� pressAt (minDtToPress=%.0fms)"):format((th.minDtToPress or 0)*1000)
				else
					reason = ("no-window (maxTP=%.0f%% hitTL, feint-grace?)"):format((th.maxTP or 0)/math.max(th.hitTL,0.001)*100)
				end
				reason = reason .. (" | proof=%s%s"):format(
					th.serverProven and ("yes/" .. tostring(th.provenBy or "?")) or "NO",
					th.pressHeldForProof and " HELD-BY-GATE" or "")
				diagPush(("MISS!  t=%.2f  %s  %s(%s)  contact0=%.0fms  height=%s bodyScale=%s modelY=%s aMult=%.2f  → %s")
					:format(now, th.name, th.kind, th.style or "?", (th.contact0 or 0)*1000,
						th.heightAttr and ("%.3f"):format(th.heightAttr) or "?",
						th.bodyHeightScale and ("%.3f"):format(th.bodyHeightScale) or "?",
						th.modelHeight and ("%.2f"):format(th.modelHeight) or "?",
						th.attackMult or 1, reason))
				State.independentMiss = (State.independentMiss or 0) + 1
			end
			table.remove(Threats, i)
		elseif not th.dodged then
			local threatens = willHitMe(th)
			if not threatens and th.serverProven and th.everThreatened
			   and (th.contactAbs - now) > -(Config.HoldAfter or 0.12) then
				threatens = true
				th.geomLatched = true
				if Config.DeepDiag and (not th.geomLatchLogAt or now - th.geomLatchLogAt > 0.10) then
					th.geomLatchLogAt = now
					diagPush(("GEOM-LATCH t=%.3f %s %s s%d proven-swing un-threatened by live geometry → HELD"
						.. " | contactIn=%+.0fms src=%s")
						:format(now, tostring(th.name), tostring(th.kind), th.strike or 1,
							(th.contactAbs - now) * 1000, tostring(th.recognitionSource or "?")))
				end
			end
			th.threatens = threatens
			if threatens and not th.firstThreatClock then
				th.firstThreatClock = now
				local ga, gm, gl = th.geomOrigin, th.geomVictim, th.geomLook
				if Config.DeepDiag then
				diagPush(("TRACE-GEOM t=%.3f %s %s s%d src=%s first=%+.0fms dt=%+.0fms tHit=%.0fms depth=%.2f range=[%.2f,%.2f] side=%.2f/%.2f A=(%s) M=(%s) look=(%s)")
					:format(now, th.name or "?", th.kind or "?", th.strike or 1,
						tostring(th.recognitionSource or "?"), (now-th.detectClock)*1000,
						(th.contactAbs-now)*1000, (th.geomTHit or 0)*1000,
						th.geomDepth or 0, (th.geomForward or 0)-(th.geomHalfD or 0),
						(th.geomForward or 0)+(th.geomHalfD or 0), th.geomSide or 0, th.geomHalfW or 0,
						ga and ("%.1f,%.1f"):format(ga.X,ga.Z) or "?",
						gm and ("%.1f,%.1f"):format(gm.X,gm.Z) or "?",
						gl and ("%.2f,%.2f"):format(gl.X,gl.Z) or "?"))
				end
			end
			if threatens then th.everThreatened = true end
			if threatens then
				if th.group and th.group.held and State.blocking then
					th.pressed, th.coveredByHeldGuard = true, true
					State.holdUntil = math.max(State.holdUntil or 0,
						(th.group.lastContact or th.contactAbs) + Config.HoldAfter + (Config.HoldLateGrace or 0))
				end
				local ik = th.attackerModel or th.attackerHRP or th.name
				if ik and not V93.interruptSeen[ik] then
					V93.interruptSeen[ik] = true
					State.interruptThreatCount = State.interruptThreatCount + 1
				end
				if (th.kind == "M1" or th.kind == "M2") and (not State.interruptCandidate
				   or th.contactAbs < State.interruptCandidate.contactAbs) then
					State.interruptCandidate = th
				end
				local lead = Config.PerfectLead
				local hold = Config.HoldAfter
		if Config.M2WidenWindow and th.kind == "M2" then
			lead = lead + Config.M2WidenFront
			hold = hold + Config.M2WidenHold
		end
		if Config.SkillAddon and Config.SA_HakariRead and th.kind == "M2"
			and (th.style or ""):lower() == "hakari" then
			local w = Config.SA_HakariWiden or 0.05
			lead = lead + w
			hold = hold + w
		end
					local pressAt = th.contactAbs - lead - up - th.velLead
					local holdEnd = th.contactAbs + hold
					local pressAtQ = pressAt - (V93.lookahead or 0)
				local dtToPress = pressAt - now
				if th.minDtToPress == nil or dtToPress < th.minDtToPress then
					th.minDtToPress = dtToPress
				end
				if dtToPress > -(Config.HoldAfter or 0.12) and dtToPress < V93.nearPress then
					V93.nearPress = dtToPress
				end
				if now < pressAt and (th.contactAbs - now) < lead then
					th.contactPassedFast = true
				end
				if not th.serverProven then
						if th.suspect then
							if th.serverSwingId or (th.group and th.group.serverSwingId) then
								th.serverProven, th.serverProofClock = true, now
								th.suspect = false
								th.provenBy = "swingid"
							end
						elseif serverAttackProof(th.attackerModel) then
							th.serverProven, th.serverProofClock = true, now
							th.provenBy = "attr"
							if Config.DeepDiag and not th.proofLogged then
								th.proofLogged = true
								diagPush(("TRACE-PROOF t=%.3f %s %s PROVEN by=attr +%.0fms after detect, %+.0fms to contact")
									:format(now, tostring(th.name), tostring(th.kind),
										(now - th.detectClock) * 1000,
										(th.contactAbs - now) * 1000))
							end
						elseif (th.contactAbs - now) < 0.18 and serverHitboxProof(th.name) then
							th.serverProven, th.serverProofClock = true, now
							th.provenBy = "hitbox"
						end
				end

				if now >= pressAtQ and now <= holdEnd then
					th.enteredWindow = true
					if Config.ServerProofGate and not th.serverProven
					   and (th.suspect or (th.contactAbs - now) > (Config.ProofGraceSec or 0.06)) then
						if not th.baitHeldLogged then
							th.baitHeldLogged = true
							th.proofHoldClock = now
							diagPush(("TRACE-PROOF t=%.3f %s %s HOLD unproven%s | dt=%+.0fms")
								:format(now, tostring(th.name), tostring(th.kind),
									th.suspect and " SUSPECT(no swing-id)" or "",
									(th.contactAbs - now) * 1000))
							aclog(("[resolver] %s %s unproven%s — holding press (bait?)")
								:format(tostring(th.name), tostring(th.kind),
									th.suspect and " (SUSPECT: no swing-id)" or " by server"))
						end
						th.pressHeldForProof = true
					else
						th.pressHeldForProof = false
					local take = false
					if not wantBlock then
						take = true
					else
						local wbU, thU = not wantBlock.pressed, not th.pressed
						if thU ~= wbU then take = thU
						else take = th.contactAbs < wantBlock.contactAbs end
					end
					if take then wantBlock = th end
					end
				end
				if dt <= (Config.FaceLeadWindow + up) and dt >= -Config.HoldAfter then
					local grace = now - 0.03
					local take = false
					if not faceTgt then
						take = true
					else
						local fUp, thUp = faceTgt.contactAbs >= grace, th.contactAbs >= grace
						if thUp ~= fUp then take = thUp
						else take = th.contactAbs < faceTgt.contactAbs end
					end
					if take then faceTgt = th end
				end
				if dt <= Config.DodgeHorizon and dt >= -Config.HoldAfter and not th.staleTrack then
					imminent[#imminent+1] = th
				end
			end
		end
	end

	State.ap.tryInterrupt(now, State.interruptCandidate, State.interruptThreatCount)

	table.sort(imminent, V93.sortByContact)

	if State.interruptFiredFrame ~= FrameId and tryBoxingCounter(now) then return end

	local cluster = V93.clusterBuf
	table.clear(cluster)
	local clusterHeavy = false
	for _, th in ipairs(imminent) do
		cluster[#cluster + 1] = th
		if th.kind == "M2" then clusterHeavy = true end
	end
	local clusterN = #cluster
	local clusterFirst = cluster[1]
	local clusterLast = cluster[#cluster]
	local clusterSpread = (clusterFirst and clusterLast) and (clusterLast.contactAbs - clusterFirst.contactAbs) or 0
	local clusterStrategy = nil
	local activeTxn = State.dodgeTxn
	if activeTxn and activeTxn.pending then
		clusterStrategy = "DODGE_TXN"
	end
	if not clusterStrategy and Config.MultiThreatGuard and clusterN >= (Config.MultiThreatMinN or 2) then
		local iframeSpan = math.max(0, ifDur - 0.07)
		local blockCd = Config.BlockCooldown or 0.5
		local seqSpread = Config.SequentialSpread or 0.78
	if clusterN == 2 and clusterSpread >= seqSpread and not clusterHeavy
		and cluster[1].attackerModel ~= cluster[2].attackerModel then
			local a, b = cluster[1], cluster[2]
			local spreadOk = (b.contactAbs - a.contactAbs) >= blockCd + Config.PerfectLead + Config.MinActGap + 0.05
			if not isMustDodge(a) and not isMustDodge(b) and spreadOk then
				clusterStrategy = "SEQUENTIAL"
			end
		end
		if not clusterStrategy and clusterN >= 2 then
			local first, second = cluster[1], cluster[2]
			if first and second
				and first.kind == "M1" and second.kind == "M2"
				and first.attackerModel ~= second.attackerModel
				and not isMustDodge(first) and not isMustDodge(second) then
				local m1Dt  = first.contactAbs - now
				local m2Dt  = second.contactAbs - now
				local dLo   = ifLat - 0.03
				local dHi   = ifLat + ifDur - 0.04
				local m2Gap = m2Dt - (ifLat + ifDur)
				if m1Dt >= dLo and m1Dt <= dHi and m2Gap >= (Config.PerfectLead or 0.0625) + (Config.UplinkMax or 0.25) then
					clusterStrategy = "DODGE_M1_PARRY_M2"
				end
			end
		end
	if not clusterStrategy then
		clusterStrategy = clusterSpread <= iframeSpan and "IFRAME_CLUSTER" or "HELD_GUARD"
		end
		for _, th in ipairs(cluster) do
			th.clusterStrategy = clusterStrategy
		end

		local signature = ("%d:%d:%s"):format(clusterN, math.floor(clusterSpread * 1000 + 0.5), clusterStrategy)
		if State.lastClusterSignature ~= signature or now >= (State.lastClusterLogAt or 0) + 0.5 then
			State.lastClusterSignature = signature
			State.lastClusterLogAt = now
			diagPush(("CLUSTER t=%.2f n=%d spread=%.0fms strategy=%s contacts=[+%.0f,+%.0f]ms")
				:format(now, clusterN, clusterSpread * 1000, clusterStrategy,
					(clusterFirst.contactAbs - now) * 1000, (clusterLast.contactAbs - now) * 1000))
		end

			if clusterStrategy == "IFRAME_CLUSTER" and Config.EmergencyDualDodge
				and not canBlockNow()
			and not State.clusterHasAliBoxingM2(cluster)
			and Config.MultiDodgeCover ~= false and dodgeReady() and canDodgeNow()
			and not counterPreemptsDodge(now) then
			local firstDt = clusterFirst.contactAbs - now
			local iframeLo = ifLat
			local iframeHi = ifLat + ifDur
			local covered = 0
			for _, th in ipairs(cluster) do
				local dtc = th.contactAbs - now
				if dtc >= iframeLo and dtc <= iframeHi then
					local dup = false
					for _, other in ipairs(cluster) do
						if other == th then break end
						local odtc = other.contactAbs - now
						if other.attackerModel == th.attackerModel
						   and odtc >= iframeLo and odtc <= iframeHi
						   and math.abs(odtc - dtc) <= 0.03 then
							dup = true
							break
						end
					end
					if not dup then covered = covered + 1 end
				end
			end
			if firstDt >= iframeLo and covered >= 2 then
				if performDodge(now, ("multi-cover(n=%d span=%.0fms)"):format(covered, clusterSpread * 1000)) then
					return
				end
			end
		end
	end

	local dtx = State.dodgeTxn
	if dtx and dtx.pending then
		local inFlightUntil = (dtx.fire or 0) + math.max(uplink(), 0.02) + (1 / 60)
		if now < inFlightUntil then return end
	end

	if clusterStrategy == "DODGE_M1_PARRY_M2" and not canBlockNow()
	   and dodgeReady() and canDodgeNow() and not counterPreemptsDodge(now) then
		local m1th = cluster[1]
		local m1Dt = m1th.contactAbs - now
		local dLo  = ifLat - 0.03
		local dHi  = math.min(ifLat + ifDur * (Config.DodgeCenterFrac or 0.5)
			+ (Config.DodgeCenterBias or 0), ifLat + ifDur - 0.04)
		if m1Dt >= dLo and m1Dt <= dHi then
			if performDodge(now, "dodge-m1-parry-m2") then
				m1th.coveredByDodge = true
				return
			end
		end
	end

	local mustDodgeThreat = nil
	for _, candidate in ipairs(imminent) do
		if isMustDodge(candidate) then mustDodgeThreat = candidate; break end
	end
	if mustDodgeThreat and dodgeReady() and canDodgeNow() then
		local mustDt = mustDodgeThreat.contactAbs - now
		local mLo = ifLat - 0.03
		local mHi = math.min(ifLat + ifDur * (Config.DodgeCenterFrac or 0.5)
			+ (Config.DodgeCenterBias or 0), ifLat + ifDur - 0.04)
		if mustDt >= mLo and mustDt <= mHi then
			if performDodge(now, "must-dodge(unblockable→back)", true, false, true) then
				mustDodgeThreat.coveredByDodge = true
				return
			end
		end
	end

	if Config.SkillAddon and Config.SA_BlatantDodge and dodgeReady() and #imminent >= 1 then
		local a  = imminent[1]
		local dt = a.contactAbs - now
		local normalOk = canDodgeNow(false)
		local forceOk  = canDodgeNow(true)
		local locked   = (State.selfBusyUntil or 0) > now or (not canBlockNow())
		local coverLo  = ifLat - 0.03
		local coverHi  = ifLat + ifDur - 0.04
		if (not normalOk) and forceOk and locked and not State.isAliBoxingM2(a)
		   and dt >= (coverLo - 0.06) and dt <= math.max(coverHi, Config.SA_BlatantWindow or 0.32)
		   and not counterPreemptsDodge(now) then
			if performDodge(now, "blatant-override(locked)", true, true) then return end
		end
	end

	if dodgeReady() and canDodgeNow() and #imminent >= 1 then
		local a = imminent[1]
		local soonestDt = a.contactAbs - now

		local coverLo = ifLat - 0.03
		local coverHi = ifLat + ifDur * (Config.DodgeCenterFrac or 0.5)
			+ (Config.DodgeCenterBias or 0)
		local coverMax = ifLat + ifDur - 0.04
		if coverHi > coverMax then coverHi = coverMax end
		if coverHi < coverLo then coverHi = coverLo end
		local function dodgeCovers(dt) return dt >= coverLo and dt <= coverHi end
		local coverable = dodgeCovers(soonestDt)

		local abuse, m2Remaining, abuseWhy = State.aliDodgeAbuseEligible(a, now, imminent, ifLat, ifDur)
		if abuse and not counterPreemptsDodge(now) then
			if performDodge(now, "ali-dodge-abuse", false, false, false, a) then
				diagPush(("ALI-DODGE-ABUSE t=%.2f target=%s/%s s%d contactIn=%.0fms m2Remaining=%.2fs dir=%s")
					:format(now, tostring(a.name), tostring(a.kind), a.strike or 1,
						(a.contactAbs-now)*1000, m2Remaining or -1,
						tostring(State.dodgeTxn.dodgeDirMode or "?")))
				return
			end
		elseif abuseWhy == "boxing-m2-parry" and not a.aliBoxingParryLogged then
			a.aliBoxingParryLogged = true
			diagPush(("ALI-BOXING-M2=PARRY t=%.2f target=%s strike=%d contactIn=%.0fms gate=dodge-abuse")
				:format(now, tostring(a.name), a.strike or 1, (a.contactAbs-now)*1000))
		end

		if Config.OutnumberEscape and evasiveGranted() and coverable
		   and not State.isAliBoxingM2(a) and not counterPreemptsDodge(now) then
			local coverableCount = 0
			for _, t in ipairs(imminent) do
				if dodgeCovers(t.contactAbs - now) then coverableCount = coverableCount + 1 end
			end
			local preferBlock = Config.OutnumberEscapePreferBlock ~= false
				and coverableCount <= 1 and canBlockNow()
			if not preferBlock then
				if performDodge(now, "outnumbered-escape") then return end
			end
		end
				if Config.ComboEscapeDodge and Config.DodgeOnParryCooldown ~= false
				   and not canBlockNow() and coverable and not State.isAliBoxingM2(a)
				   and not counterPreemptsDodge(now) then
					if performDodge(now, "combo-escape") then return end
				end
			local blatantOn = Config.SkillAddon and Config.SA_BlatantDodge
			local busyRef = (Config.ExposedEscapeAttackOnly ~= false)
				and (State.attackBusyUntil or 0) or (State.selfBusyUntil or 0)
			if blatantOn and Config.ExposedEscapeDodge and busyRef > now
			   and soonestDt <= Config.ExposedDodgeWindow and coverable and not State.isAliBoxingM2(a)
			   and not counterPreemptsDodge(now) then
				if performDodge(now, "exposed-escape(blatant)", false, true) then return end
			end

		local fireLead
		if Config.DodgeCenter then
			fireLead = ifDur * 0.5 + (Config.DodgeCenterBias or 0)
			if a.kind == "M2" then fireLead = fireLead + (Config.HeavyDodgeBias or 0) end
		else
			fireLead = Config.DodgeLead
		end
			if soonestDt <= (fireLead + up + (V93.lookahead or 0)) then
				local overloaded, why = false, nil
				local blockUp = canBlockNow()
				if not blockUp and Config.DodgeOnParryCooldown ~= false then
					if clusterStrategy ~= "HELD_GUARD" then
						if clusterN >= 2 and clusterHeavy and Config.DodgeHeavy then
							overloaded, why = true, "heavy+multi"
						elseif clusterN >= 3 then
							overloaded, why = true, ("%dx-burst"):format(clusterN)
						end
					end
					if a.kind == "M2" and clusterN == 1 and Config.DodgeHeavy and not overloaded then
						overloaded, why = true, "heavy-dodge(no-block)"
					end
				end
	if not overloaded and Config.GuardbreakProtect then
		local st = blockStamina()
		if st and st <= Config.StaminaFloor then
			overloaded, why = true, ("guardbreak-save(st=%.0f)"):format(st)
		end
	end
				if overloaded and counterPreemptsDodge(now) then overloaded = false end
			if overloaded and not State.isAliBoxingM2(a) then
				if performDodge(now, why) then return end
			end
			end
	end

	local midPos = computeMultiFaceGoal()
	if midPos then
		local nearest = math.huge
		for _, th in ipairs(imminent) do
			local dt = (th.contactAbs or now) - now
			if dt < nearest then nearest = dt end
		end
		local hard = nearest <= (Config.BlockFaceHardDt or 0.30) + up
		setFaceGoalPos(midPos, hard, math.max(nearest, 0) + (Config.HoldAfter or 0.12) + 0.08)
		faceTgt = nil
	end

	local turnTo = faceTgt or wantBlock
	if turnTo and turnTo.attackerHRP then
		local dtc = turnTo.contactAbs - now
		local hardWin = (Config.BlockFaceHardDt or 0.30) + up
		local hard = (dtc <= hardWin) or (Config.MultiFaceHard and clusterN >= (Config.MultiThreatMinN or 2))
		setFaceGoal(turnTo.attackerHRP, hard, math.max(dtc, 0) + (Config.HoldAfter or 0.12) + 0.06)
		State.vizTarget = { hrp = turnTo.attackerHRP, model = turnTo.attackerModel }
		publishTarget(turnTo)
	else
		State.vizTarget = nil
		publishTarget(nil)
	end

	local threatN, farContact = 0, nil
	do
		local seen = V93.threatSeen
		for k in pairs(seen) do seen[k] = nil end
		for _, th in ipairs(imminent) do
			local key = th.attackerModel or th.attackerHRP or th.name
			if key and not seen[key] then seen[key] = true; threatN = threatN + 1 end
			if not farContact or th.contactAbs > farContact then farContact = th.contactAbs end
		end
	end
	local multiThreat = Config.MultiThreatGuard
		and (threatN >= (Config.MultiThreatMinN or 2) or clusterN >= (Config.MultiThreatMinN or 2))
	State.multiThreat  = multiThreat
	State.multiThreatN = math.max(threatN, clusterN)
	if multiThreat then
		State.multiThreatMax   = math.max(State.multiThreatMax or 0, State.multiThreatN)
		State.multiThreatFrames = (State.multiThreatFrames or 0) + 1
		if farContact then
			local latch = farContact + Config.HoldAfter + (Config.HoldLateGrace or 0) + 0.05
			State.multiHoldUntil = math.max(State.multiHoldUntil or 0, latch)
		end
	end

	if wantBlock then
		State.noParryNow = localChar() and localChar():GetAttribute("ParryWindowDisabled") == true
		if State.noParryNow ~= State.noParryActive then
			State.noParryActive = State.noParryNow
			diagPush(("PARRY-WINDOW t=%.2f %s → %s")
				:format(now, State.noParryNow and "DISABLED" or "RESTORED",
					State.noParryNow and "normal guard / must-dodge" or "perfect parry"))
		end
		if State.noParryNow and State.blocking then
			wantBlock.pressed = true
			wantBlock.coveredByHeldGuard = true
			if wantBlock.rec then wantBlock.rec.blockedReason = "ParryWindowDisabled: normal guard" end
		end
		if clusterStrategy == "HELD_GUARD" and State.blocking then
			for _, th in ipairs(cluster) do
				th.pressed = true
				th.coveredByHeldGuard = true
			end
		end
		if not wantBlock.pressed and Config.AutoFace and Config.FaceGateBlock ~= false
		   and not (clusterStrategy == "HELD_GUARD") then
			local fd = faceDotToThreat(wantBlock)
			local dtc = wantBlock.contactAbs - now
			local faceFloor = Config.FaceGateMin or (Config.HighFaceMin or 0.25)
			local lastResort = dtc <= ((Config.PerfectLead or 0.0625) + up + 0.02)
			if fd ~= nil and fd < faceFloor and not lastResort then
				setFaceGoal(wantBlock.attackerHRP, true, math.max(dtc, 0) + (Config.HoldAfter or 0.12) + 0.06)
				if not wantBlock.faceWaitLogged then
					wantBlock.faceWaitLogged = true
					diagPush(("FACEWAIT t=%.2f %s %s face=%.2f<%.2f dt=%+.0fms → rotating, hold press")
						:format(now, wantBlock.name or "?", wantBlock.kind or "?", fd, faceFloor, dtc * 1000))
				end
				return
			end
		end
		if not wantBlock.pressed then
			local sent = fireBlock(serverNow)
			if sent then
				wantBlock.pressed  = true
				wantBlock.pressDt  = wantBlock.contactAbs - now
				if clusterStrategy == "HELD_GUARD" then
					for _, th in ipairs(cluster) do
						th.pressed = true
						th.coveredByHeldGuard = true
					end
				end
				wantBlock.faceDot  = faceDotToThreat(wantBlock)
				State.rearmCount   = (State.rearmCount or 0) + 1
				if wantBlock.trustedHit and not wantBlock.trustCounted then
					wantBlock.trustCounted = true
					State.trustPress = (State.trustPress or 0) + 1
				end
				if wantBlock.rec then
					wantBlock.rec.pressDt = wantBlock.pressDt
					wantBlock.rec.pressServer = serverNow
					wantBlock.rec.pressClock = now
					wantBlock.rec.pressAt = wantBlock.contactAbs - (Config.PerfectLead or 0) - up - (wantBlock.velLead or 0)
					wantBlock.rec.pressLateBy = now - wantBlock.rec.pressAt
					wantBlock.rec.faceDot = wantBlock.faceDot
					local p1, ps = pingDiagSnapshot()
					local tpNow = wantBlock.track and safeGet(wantBlock.track, "TimePosition", -1) or -1
					diagPush(("TRACE-PRESS t=%.3f srv=%.3f %s %s s%d dt=%+.0fms lateBy=%+.0fms tp=%.3f | detect net1w=%sms stats=%sms raw=%.0f med=%.0f up=%.0f | press net1w=%sms stats=%sms raw=%.0f med=%.0f up=%.0f")
						:format(now, serverNow, wantBlock.name or "?", wantBlock.kind or "?", wantBlock.strike or 1,
							wantBlock.pressDt*1000, wantBlock.rec.pressLateBy*1000, tpNow,
							wantBlock.pingOneWayDetect and ("%.0f"):format(wantBlock.pingOneWayDetect*1000) or "?",
							wantBlock.pingStatsDetect and ("%.0f"):format(wantBlock.pingStatsDetect*1000) or "?",
							(wantBlock.pingRawDetect or 0)*1000, (wantBlock.pingMedDetect or 0)*1000,
							(wantBlock.uplinkDetect or 0)*1000,
							p1 and ("%.0f"):format(p1*1000) or "?", ps and ("%.0f"):format(ps*1000) or "?",
							getPingRaw()*1000, getPing()*1000, up*1000))
				end
			elseif State.blockedReason then
				if wantBlock.rec then wantBlock.rec.blockedReason = State.blockedReason end
				if wantBlock.lastReason ~= State.blockedReason then
					wantBlock.lastReason = State.blockedReason
					diagPush(("BLOCK? t=%.2f  %s  %s  refused: %s"):format(now, wantBlock.name, wantBlock.kind, State.blockedReason))
				end
			end
		end
		local holdExtra = (wantBlock.kind == "M2" and Config.M2WidenWindow) and Config.M2WidenHold or 0
		local base = wantBlock.contactAbs
		if multiThreat and farContact and farContact > base and clusterStrategy ~= "SEQUENTIAL" then
			base = farContact
		end
		State.holdUntil = math.max(State.holdUntil,
			base + Config.HoldAfter + (Config.HoldLateGrace or 0) + holdExtra)
	elseif State.blocking then
		local keepForCluster = (multiThreat and farContact
			and now < (farContact + Config.HoldAfter + (Config.HoldLateGrace or 0)))
			or (State.multiHoldUntil and now < State.multiHoldUntil)
		local releaseByGap = (not multiThreat) and (not (State.multiHoldUntil and now < State.multiHoldUntil))
			and (now - State.lastPress) > Config.ReleaseGap
		if not keepForCluster and (now >= State.holdUntil or releaseByGap) then
			releaseBlock()
			State.multiHoldUntil = 0
		end
	end

	if Config.AutoPlay and not wantBlock and #imminent == 0 then
		State.ap.step(now)
	end
end)

local function parseEvent(ev)
	local kind = ev:match("^(M%d)")
	if not kind then return nil end
	local rest = ev:sub(#kind + 1)
	if rest == "Hit" then return kind, "LATE"
	elseif rest == "Blocked" then return kind, "EARLY"
	elseif rest == "PerfectBlocked" then return kind, "PERFECT"
	elseif rest == "GuardBroken" then return kind, "GUARDBREAK" end
	return nil
end

local function outcomeTypeMatches(recType, kind)
	if recType == kind then return true end
	if kind == "M2" and recType == "SKILL" then return true end
	return false
end

local function onOutcome(attacker, result, kind, eventClock)
	local q = Pending[attacker]
	local rec, looseRec, followUp
	if q then
		for i = #q, 1, -1 do
			local r = q[i]
			local age = eventClock - r.clock
			if age >= 0 and age <= Config.MatchWindow and outcomeTypeMatches(r.type, kind) then
				if not r.matched then
					local score = math.abs((eventClock - r.clock) - (r.contact or 0))
					if r.type == kind then
						if not rec or score < (rec.matchScore or math.huge) then
							rec, r.matchScore = r, score
						end
					elseif not looseRec or score < (looseRec.matchScore or math.huge) then
						looseRec, r.matchScore = r, score
					end
				elseif not followUp and (eventClock - r.clock) <= Config.MultiHitWindow then
					followUp = r
				end
			end
		end
		if not rec then rec = looseRec end
	end

	if not rec and followUp then
		diagPush(("OUT    t=%.2f  %s  %s  %s  (multi-hit follow-up +%.0fms, guard kept)")
			:format(eventClock, attacker, kind, result, (eventClock - followUp.clock)*1000))
		return
	end

	if not rec then
		diagPush(("OUT    t=%.2f  %s  %s  %s  (no fresh swing)"):format(eventClock, attacker, kind, result))
		return
	end

	State.tally[result] = (State.tally[result] or 0) + 1
	State.lastResult    = result
	State.flashUntil    = os.clock() + 0.25

	if Config.DodgeTelemetry and State.lastDodgeInfo then
		local di = State.lastDodgeInfo
		local dtSinceFire = eventClock - di.fire
		if dtSinceFire >= 0 and dtSinceFire <= 0.9 then
			local hitT = eventClock
			local rel
			if hitT < di.iframeLo then
				rel = ("hit %.0fms BEFORE window → dodge TOO EARLY"):format((di.iframeLo - hitT)*1000)
			elseif hitT > di.iframeHi then
				rel = ("hit %.0fms AFTER window → dodge TOO LATE"):format((hitT - di.iframeHi)*1000)
			else
				rel = ("hit INSIDE i-frame window (+%.0fms from start)"):format((hitT - di.iframeLo)*1000)
			end
			diagPush(("DODGE-OUT t=%.2f  %s  %s  %s  fired %.0fms before  [%s]")
				:format(eventClock, attacker, kind, result, dtSinceFire*1000, rel))
			State.lastDodgeInfo = nil
		end
	end

	rec.matched = true
	if rec.th then rec.th.resolved = true end

	if result == "GUARDBREAK" then
		State.blocking, State.holdUntil = false, 0
	elseif result == "LATE" then
		local holding = State.blocking and (os.clock() < (State.holdUntil or 0))
		if not (State.multiThreat and holding) then State.blocking, State.holdUntil = false, 0 end
	end
	if result == "PERFECT" and rec.th and rec.th.group then
		rec.th.group.cancelled = true
	elseif result == "EARLY" and rec.th and rec.th.group then
		rec.th.group.held = true
	end
	if result == "PERFECT" and rec.th and rec.th.clusterStrategy == "HELD_GUARD" then
		for _, other in ipairs(Threats) do
			if other ~= rec.th and not other.resolved and other.contactAbs > eventClock then
				other.pressed, other.coveredByHeldGuard = false, false
				if other.rec then other.rec.pressDt, other.rec.pressServer = nil, nil end
			end
		end
		State.blocking, State.holdUntil, State.multiHoldUntil = false, 0, 0
	end
	if result == "PERFECT" then State.ap.onPerfectParry(attacker, kind) end

	local measured = eventClock - rec.clock
	local predErr  = (measured - rec.contact) * 1000
	State.lastErrMs = predErr

	local ksKey = tostring(kind) .. ":" .. tostring(rec.style or "?")
	local ks = ResidByKS[ksKey]; if not ks then ks = { sum = 0, n = 0 }; ResidByKS[ksKey] = ks end
	ks.sum = ks.sum + predErr; ks.n = ks.n + 1
	if ks.n > 100 then ks.sum = ks.sum * (100 / ks.n); ks.n = 100 end
	local resAvg = ks.sum / ks.n
	local resNShown = ks.n

	local upAtPress = math.clamp((rec.pingRaw or 0) * Config.UplinkFactor + Config.UplinkMargin,
	                             Config.UplinkMin, Config.UplinkMax) * 1000
	local eventServer = rec.detectServer and (rec.detectServer + measured) or nil
	local blockGap = nil
	if rec.pressServer and eventServer then blockGap = (eventServer - rec.pressServer) * 1000 end
	local trueGap = blockGap and (blockGap - upAtPress) or nil
	local gapStr  = blockGap and ("%+.0f→true%+.0fms"):format(blockGap, trueGap) or "NO-PRESS"
	local pressStr = rec.pressDt and ("%.0fms"):format(rec.pressDt*1000) or "—"
	local hint = "?"
	if trueGap then
		if trueGap < Config.PerfectMin*1000 then hint = "LATE(<50)"
		elseif trueGap > Config.PerfectWindow*1000 then hint = "EARLY(>150)"
		else hint = "IN-WINDOW" end
	elseif rec.pressServer == nil then
		hint = "NOT-BLOCKED"
	end

	local faceStr = rec.faceDot and ("%.2f"):format(rec.faceDot) or "n/a"
	local faceFlag = (rec.faceDot ~= nil and rec.faceDot < Config.FaceGoodDot) and " BACK!" or ""
	if rec.faceDot ~= nil then
		local b = FaceByResult[result]; if not b then b = { sum = 0, n = 0 }; FaceByResult[result] = b end
		b.sum = b.sum + rec.faceDot; b.n = b.n + 1
		if b.n > 100 then b.sum = b.sum * (100 / b.n); b.n = 100 end
	end

	local reasonStr = rec.blockedReason and (" STATE:" .. rec.blockedReason) or ""
	if rec.blockedReason and (result == "LATE" or result == "GUARDBREAK") then
		State.stateHits = (State.stateHits or 0) + 1
	end

	do
		State.comboStat = State.comboStat or { opener = {}, tail = {} }
		local bucket = ((rec.combo or 0) >= 3) and State.comboStat.tail or State.comboStat.opener
		bucket[result] = (bucket[result] or 0) + 1
	end

	do
		local th = rec.th
		local p1, ps = pingDiagSnapshot()
		local tpOut = th and th.track and safeGet(th.track, "TimePosition", -1) or -1
		diagPush(("TRACE-OUT t=%.3f %s %s s%d result=%s age=%.0fms tp=%.3f | firstThreat=%sms hbFirst=%sms hbOverlap=%sms sid=%s src=%s | pressLate=%sms | net1w=%sms stats=%sms raw=%.0f med=%.0f up=%.0f")
			:format(eventClock, attacker, kind, rec.strike or 1, result, measured*1000, tpOut,
				th and th.firstThreatClock and ("%.0f"):format((th.firstThreatClock-rec.clock)*1000) or "?",
				th and th.hbFirstClock and ("%.0f"):format((th.hbFirstClock-rec.clock)*1000) or "?",
				th and th.hbOverlapClock and ("%.0f"):format((th.hbOverlapClock-rec.clock)*1000) or "?",
				tostring(th and (th.serverSwingId or (th.group and th.group.serverSwingId)) or "none"),
				tostring(th and th.recognitionSource or "none"),
				rec.pressLateBy and ("%+.0f"):format(rec.pressLateBy*1000) or "?",
				p1 and ("%.0f"):format(p1*1000) or "?", ps and ("%.0f"):format(ps*1000) or "?",
				getPingRaw()*1000, getPing()*1000, uplink()*1000))
	end

	diagPush(("OUT    t=%.2f  %s  %s(c%d,s%d)  %-10s  meas=%.0fms pred=%.0fms predErr=%+.0fms resAvg=%+.0fms(n=%d) | blockGap=%s guard=%s pressDt=%s%s | face=%s%s spd=%.2f ping=%.0f")
		:format(eventClock, attacker, kind, rec.combo or 0, rec.strike or 1, result, measured*1000, rec.contact*1000,
		        predErr, resAvg, resNShown, gapStr, hint, pressStr, reasonStr, faceStr, faceFlag, rec.speed or 1, (rec.pingRaw or 0)*1000))
end

local hooked = setmetatable({}, { __mode = "k" })
local _animIdCache = setmetatable({}, { __mode = "k" })
local _ownerCache  = setmetatable({}, { __mode = "k" })
local OWNER_TTL    = 1.0

local function cachedAnimId(anim)
	local v = _animIdCache[anim]
	if v ~= nil then return v or nil end
	local parsed = tonumber(tostring(anim.AnimationId):match("(%d+)"))
	_animIdCache[anim] = parsed or false
	return parsed
end

local function cachedOwner(animator)
	local now = os.clock()
	local rec = _ownerCache[animator]
	if rec and (now - rec.t) < OWNER_TTL then return rec end
	local model = ownerOf(animator)
	local enemy, hrp = isEnemyModel(model)
	rec = { model = model, isLocal = (model ~= nil and model == localChar()), enemy = enemy or false, hrp = hrp, t = now }
	_ownerCache[animator] = rec
	return rec
end

local function hookAnimator(animator)
	if hooked[animator] then return end
	hooked[animator] = true
	animator.AnimationPlayed:Connect(function(track)
		local anim = track and track.Animation
		if not anim then return end
		local id = cachedAnimId(anim)
		if not id then return end
		local rec = cachedOwner(animator)
		if Config.DesyncAttack and AnimLib.desyncOwnTrack and rec.isLocal then
			AnimLib.desyncOwnTrack(track, id, animator)
		end
		if not Config.Enabled then return end
		if not rec.enemy then return end
		if BlockIds[id] then return end
		if not attackEntry(id) then return end
		if Config.AntiDecoy and Config.DecoyHardDrop ~= false then
			local S = State.decoySeen; if not S then S = {}; State.decoySeen = S end
			local nowd = os.clock()
			local okS, spd = pcall(function() return track.Speed end)
			if okS and type(spd) == "number" and spd > 0 then
				local lo = Config.DecoySpeedMin or 0.30
				local hi = Config.DecoySpeedMax or 1.25
				if spd < lo or spd > hi then
					State.decoyDropped = (State.decoyDropped or 0) + 1
					if (nowd - (State.lastDecoyLog or 0)) > 1 then
						State.lastDecoyLog = nowd
						aclog(("[breaker] %s speed=%.2f (legal %.2f..%.2f) — phantom dropped x%d")
							:format(tostring(rec.model and rec.model.Name or "?"), spd, lo, hi,
								State.decoyDropped))
					end
					return
				end
			end
			local dk = tostring(rec.model and rec.model.Name or "?") .. "|" .. tostring(id)
			local prevT = S[dk]
			if prevT and (nowd - prevT) < (Config.DecoyRefireSec or 0.60) then
				State.decoyDropped = (State.decoyDropped or 0) + 1
				if (nowd - (State.lastDecoyLog or 0)) > 1 then
					State.lastDecoyLog = nowd
					aclog(("[breaker] %s same-id refire %.0fms (< %.0fms) — phantom dropped x%d")
						:format(tostring(rec.model and rec.model.Name or "?"), (nowd - prevT)*1000,
							(Config.DecoyRefireSec or 0.60)*1000, State.decoyDropped))
				end
				return
			end
			S[dk] = nowd
			State.decoySweepAt = State.decoySweepAt or nowd
			if nowd >= State.decoySweepAt then
				State.decoySweepAt = nowd + (Config.DecoySweepSec or 5)
				local live = 0
				for k, t in pairs(S) do
					if (nowd - t) > 8 then S[k] = nil else live = live + 1 end
				end
				if live > (Config.DecoySeenMax or 512) then
					State.decoySeen = { [dk] = nowd }
				end
			end
		end
		local info = resolveInfo(id, rec.model)
		if not info then return end
		onAttack(rec.hrp, info, rec.model, id, track)
	end)
end

local function scanAnimators()
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch  = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local an  = hum and hum:FindFirstChildOfClass("Animator")
		if an then hookAnimator(an) end
	end
	if not State.didInitialAnimatorSweep then
		State.didInitialAnimatorSweep = true
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Animator") then hookAnimator(d) end
		end
	end
end

Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Animator") then hookAnimator(d) end
end)

task.spawn(function()
	local Shared  = ReplicatedStorage:WaitForChild("Shared", 30)
	local Network = Shared and Shared:WaitForChild("Network", 30)
	local ure     = Network and Network:WaitForChild("CombatBroadcastURE", 30)
	if not ure then dbg("CombatBroadcastURE not found — calibration off"); return end
	local myName = LocalPlayer.Name
	ure.OnClientEvent:Connect(function(eventName, attacker, victim, ...)
		if type(eventName) ~= "string" then return end
		if eventName == "StyleEvasiveCounter" then
			if attacker ~= myName then return end
			local now = os.clock()
			local tx = State.dodgeTxn
			if tx and tx.pending and now <= math.max(tx.untilAt or 0, tx.ackDeadline or 0) then
				tx.perfectConfirmed, tx.perfectAt = true, now
			diagPush(("ALI-PERFECT-CONFIRM t=%.2f proc=one-perfect-dodge normalHeavyReset=false dodgeAgo=%.0fms iframeConfirmed=%s reason=%s")
				:format(now, (now-(tx.fire or now))*1000, tostring(tx.confirmed == true),
					tostring(tx.reason or "?")))
			end
			return
		end
		local kind, result = parseEvent(eventName)
		if not kind then return end
		if victim ~= myName then return end
		onOutcome(attacker, result, kind, os.clock())
	end)
	dbg("calibration active — listening CombatBroadcastURE")
end)

local function acAvailable(name)
	local ok, v = pcall(function()
		if type(getgenv) == "function" then local g = getgenv()[name]; if g ~= nil then return g end end
		return getfenv(0)[name]
	end)
	return ok and type(v) == "function"
end

local function hideHook(fn)
	if not Config.HideHooks then return fn end
	local out = fn
	if acAvailable("newcclosure") then
		local ok, c = pcall(newcclosure, fn); if ok and c then out = c end
	end
	if acAvailable("setstackhidden") then pcall(setstackhidden, out, true) end
	return out
end

local function findACScript()
	local rf = game:GetService("ReplicatedFirst")
	local s = rf:FindFirstChild(Config.ACScriptName)
	if s then return s end
	local roots = { rf }
	pcall(function()
		local lp = Players.LocalPlayer
		if lp then
			table.insert(roots, lp:FindFirstChild("PlayerScripts"))
			table.insert(roots, lp:FindFirstChild("PlayerGui"))
		end
		table.insert(roots, game:GetService("ReplicatedStorage"))
	end)
	for _, root in ipairs(roots) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("LocalScript") and d.Name:lower():find("challenging") then return d end
			end
		end
	end
	return nil
end

local function muteAC()
	if not (Config.AntiCheatBypass and Config.MuteAC) then return end
	if not acAvailable("getconnections") then
		aclog("[AC] getconnections unavailable on this executor — cannot mute AC connections"); return
	end
	local ac = findACScript()
	if not ac then
		if not State.acMissLogged then
			State.acMissLogged = true
			aclog("[AC] anticheat script NOT FOUND yet (name/location changed?) — will keep retrying")
		end
		return
	end
	State.acScript = ac
	if not State.acFoundLogged then
		State.acFoundLogged = true
		aclog(("[AC] DETECTED anticheat LocalScript: %s  (parent=%s) — muting now"):format(
			tostring(ac.Name), tostring(ac.Parent and ac.Parent.Name or "?")))
	end

	local RS = game:GetService("RunService")
	local signals = {
		RS.Heartbeat, RS.RenderStepped, RS.Stepped, RS.PreSimulation, RS.PostSimulation,
		game.DescendantAdded, game.ChildAdded, workspace.DescendantAdded, workspace.ChildAdded,
	}
	pcall(function()
		local lp = Players.LocalPlayer
		if lp then table.insert(signals, lp.CharacterAdded); table.insert(signals, lp.Idled) end
	end)
	pcall(function()
		for _, svc in ipairs({ "ReplicatedStorage", "StarterGui", "StarterPlayer", "Players" }) do
			local s = game:GetService(svc)
			table.insert(signals, s.ChildAdded); table.insert(signals, s.DescendantAdded)
		end
	end)

	local muted = 0
	for _, sig in ipairs(signals) do
		pcall(function()
			for _, conn in ipairs(getconnections(sig)) do
				if conn.Script == ac then
					if type(conn.Disable) == "function" then
						conn:Disable(); muted = muted + 1
					elseif conn.Enabled ~= nil then
						conn.Enabled = false; muted = muted + 1
					end
				end
			end
		end)
	end
	State.acMuted = muted
	if muted > 0 then
		if (State.acMutedLogged or 0) ~= muted then
			State.acMutedLogged = muted
			aclog(("[AC] BYPASS ACTIVE — muted %d connection(s) on the anticheat; script left enabled"):format(muted))
		end
	elseif not State.acZeroLogged then
		State.acZeroLogged = true
		aclog("[AC] anticheat found but it owns no muteable connections yet — retrying")
	end
end

local function neutralizeAC()
	if not (Config.AntiCheatBypass and Config.NeutralizeAC) then return end
	if not acAvailable("getgc") then
		if not State.acNoGcLogged then
			State.acNoGcLogged = true
			aclog("[AC] getgc unavailable on this executor — cannot neutralize AC objects")
		end
		return
	end
	local killNames = {
		["_sendanticheatreport"]      = true,
		["_sendanticheatshadowreport"] = true,
		["_reportvictimhit"]          = true,
		["_scanhitboxes"]             = true,
		["_wireremotespamtouch"]      = true,
		["_reporthitbox"]             = true,
		["_reportswing"]              = true,
		["_flag"]                     = true,
	}
	local trueNames = { ["_issuppressed"] = true }
	local noop   = hideHook(function() end)
	local truefn = hideHook(function() return true end)

	local patched, tablesHit = 0, 0
	pcall(function()
		for _, o in ipairs(getgc(true)) do
			if type(o) == "table" then
				local todo
				pcall(function()
					for k, v in pairs(o) do
						if type(k) == "string" and type(v) == "function" then
							local lk = k:lower()
							if killNames[lk] then todo = todo or {}; todo[#todo + 1] = { k, noop } end
							if trueNames[lk] then todo = todo or {}; todo[#todo + 1] = { k, truefn } end
						end
					end
				end)
				if todo then
					local hitThis = false
					for _, pair in ipairs(todo) do
						if pcall(function() rawset(o, pair[1], pair[2]) end) then
							patched = patched + 1; hitThis = true
						end
					end
					if hitThis then tablesHit = tablesHit + 1 end
				end
			end
		end
	end)

	State.acNeutralized = patched
	if patched > 0 then
		if (State.acNeutLogged or 0) ~= patched then
			State.acNeutLogged = patched
			aclog(("[AC] NEUTRALIZED — replaced %d report method(s) across %d AC object(s) with no-ops (report senders killed at the source)"):format(patched, tablesHit))
		end
	elseif not State.acNeutZeroLogged then
		State.acNeutZeroLogged = true
		aclog("[AC] neutralize: no AC report methods in GC yet — retrying")
	end
end

local function scanAC()
	local L = {}
	local function w(s) L[#L + 1] = s end
	local function has(name)
		local ok, v = pcall(function()
			if type(getgenv) == "function" then local g = getgenv()[name]; if g ~= nil then return g end end
			return getfenv(0)[name]
		end)
		return ok and type(v) == "function", (ok and v) or nil
	end
	local function trunc(s, n)
		s = tostring(s):gsub("[%z\1-\8\11-\31]", ".")
		if #s > n then return s:sub(1, n) .. "…(" .. #s .. ")" end
		return s
	end

	w("===== AUTOPARRY ANTICHEAT SCAN =====")
	do
		local okId, exe, ver = pcall(function() local a, b = identifyexecutor(); return a, b end)
		w(("executor: %s %s"):format(okId and tostring(exe) or "?", okId and tostring(ver or "") or ""))
	end
	do
		local caps = { "getscriptclosure","getgc","filtergc","getconnections","getscriptbytecode",
			"getscripthash","getrunningscripts","getscriptthread","getcallingscript","decompile",
			"debug","hookfunction","newcclosure","setstackhidden","getsenv","getscripts" }
		local line = {}
		for _, c in ipairs(caps) do line[#line + 1] = (has(c) and "+" or "-") .. c end
		w("caps: " .. table.concat(line, " "))
	end

	local ac = findACScript()
	if not ac then
		w("!! AC script NOT FOUND by findACScript(). Listing candidate LocalScripts (name/parent):")
		local okScr, scripts = pcall(getscripts)
		if okScr and scripts then
			local shown = 0
			for _, s in ipairs(scripts) do
				local okA = pcall(function() return s:IsA("LocalScript") end)
				if okA and s:IsA("LocalScript") and shown < 60 then
					w(("   %s  <%s>"):format(tostring(s.Name), tostring(s.Parent and s.Parent:GetFullName() or "?")))
					shown = shown + 1
				end
			end
		end
	else
		w(("AC script: %s"):format(tostring(ac:GetFullName())))
		pcall(function() w("  hash: " .. tostring(getscripthash(ac))) end)
		pcall(function() local bc = getscriptbytecode(ac); w("  bytecode bytes: " .. tostring(bc and #bc or "?")) end)

		local hasGSC, gsc = has("getscriptclosure")
		local mainFn
		if hasGSC then local ok, f = pcall(gsc, ac); if ok then mainFn = f end end
		if type(mainFn) ~= "function" then
			w("  getscriptclosure: unavailable/failed — cannot walk protos")
		else
			local seen, fnCount = {}, 0
			local function walk(fn, depth, tag)
				if type(fn) ~= "function" or seen[fn] or depth > 6 or fnCount > 400 then return end
				seen[fn] = true; fnCount = fnCount + 1
				local info = {}
				pcall(function() local i = debug.getinfo(fn); if i then
					info = { nups = i.nups, npar = i.numparams, line = i.linedefined, name = i.name } end end)
				w(("  fn[%s] d%d line=%s nups=%s name=%s"):format(tag, depth,
					tostring(info.line or "?"), tostring(info.nups or "?"), tostring(info.name or "")))
				pcall(function()
					local cs = debug.getconstants(fn)
					if cs then for i, c in pairs(cs) do
						local t = type(c)
						if t == "string" and #c > 0 then
							w(("     const[%s] %q"):format(tostring(i), trunc(c, 90)))
						elseif t == "boolean" or t == "number" then
							w(("     const[%s] = %s"):format(tostring(i), tostring(c)))
						end
					end end
				end)
				pcall(function()
					local ups = debug.getupvalues(fn)
					if ups then for name, v in pairs(ups) do
						local t = type(v)
						local desc
						if t == "boolean" or t == "number" then desc = tostring(v)
						elseif t == "string" then desc = ("%q"):format(trunc(v, 60))
						elseif t == "table" then
							local n = 0; pcall(function() for _ in pairs(v) do n = n + 1 end end)
							desc = ("table(#%d)"):format(n)
						elseif t == "userdata" then
							local cls; pcall(function() cls = v.ClassName end)
							desc = "Instance<" .. tostring(cls or "userdata") .. ">"
							pcall(function() if v.Name then desc = desc .. ' "' .. tostring(v.Name) .. '"' end end)
						else desc = t end
						w(("     up[%s] %s = %s"):format(tostring(name), t, desc))
					end end
				end)
				pcall(function()
					local ps = debug.getprotos(fn)
					if ps then for i, p in ipairs(ps) do walk(p, depth + 1, tag .. "." .. i) end end
				end)
			end
			walk(mainFn, 0, "main")
			w(("  (walked %d functions)"):format(fnCount))
		end

		local hasGC, gc = has("getgc")
		if hasGC then
			local okSrc, acSrc = pcall(function() local i = debug.getinfo(mainFn); return i and i.source end)
			acSrc = okSrc and acSrc or nil
			local fnHit, tblHit = 0, 0
			local ok = pcall(function()
				for _, o in ipairs(gc(true)) do
					local t = type(o)
					if t == "function" and fnHit < 40 then
						local src; pcall(function() local i = debug.getinfo(o); src = i and i.source end)
						if src and acSrc and src == acSrc then
							local ln; pcall(function() ln = debug.getinfo(o).linedefined end)
							w(("  gc.fn line=%s (AC-owned, live in GC)"):format(tostring(ln)))
							fnHit = fnHit + 1
						end
					elseif t == "table" and tblHit < 25 then
						local keys = {}
						local okK = pcall(function()
							for k in pairs(o) do
								if type(k) == "string" then keys[#keys + 1] = k:lower() end
								if #keys > 24 then break end
							end
						end)
						if okK then
							local blob = table.concat(keys, ",")
							if blob:find("kick") or blob:find("detect") or blob:find("report")
							   or blob:find("flag") or blob:find("ban") or blob:find("exploit")
							   or blob:find("cheat") or blob:find("suspic") then
								w(("  gc.table keys={%s}"):format(trunc(blob, 120)))
								tblHit = tblHit + 1
							end
						end
					end
				end
			end)
			w(("  gc sweep: %s (AC fns=%d, suspicious tables=%d)"):format(ok and "ok" or "err", fnHit, tblHit))
		end

		local hasConn, gconn = has("getconnections")
		if hasConn then
			local RS = game:GetService("RunService")
			local sigs = {
				{ "Heartbeat", RS.Heartbeat }, { "RenderStepped", RS.RenderStepped }, { "Stepped", RS.Stepped },
				{ "PreSimulation", RS.PreSimulation }, { "PostSimulation", RS.PostSimulation },
				{ "PreRender", RS.PreRender }, { "PreAnimation", RS.PreAnimation },
				{ "game.DescendantAdded", game.DescendantAdded }, { "game.ChildAdded", game.ChildAdded },
				{ "ws.DescendantAdded", workspace.DescendantAdded },
			}
			pcall(function()
				local lp = Players.LocalPlayer
				if lp then
					sigs[#sigs+1] = { "LP.CharacterAdded", lp.CharacterAdded }
					sigs[#sigs+1] = { "LP.Idled", lp.Idled }
					if lp.Character then
						local hum = lp.Character:FindFirstChildOfClass("Humanoid")
						if hum then sigs[#sigs+1] = { "Humanoid.StateChanged", hum.StateChanged } end
					end
				end
			end)
			for _, pair in ipairs(sigs) do
				pcall(function()
					local total, mine = 0, 0
					for _, conn in ipairs(gconn(pair[2])) do
						total = total + 1
						if conn.Script == ac then mine = mine + 1 end
					end
					if total > 0 then w(("  sig %s: %d conns (%d AC-owned)"):format(pair[1], total, mine)) end
				end)
			end
		end

		pcall(function()
			local okT, th = pcall(getscriptthread, ac)
			if okT and th then w(("  script thread: %s status=%s"):format(tostring(th), tostring(coroutine.status(th)))) end
		end)
	end

	w("===== END SCAN =====")
	local report = table.concat(L, "\n")
	statusPush(report)
	local saved
	pcall(function()
		if type(writefile) == "function" then
			writefile("AutoParry_ACScan.txt", report); saved = "AutoParry_ACScan.txt"
		end
	end)
	pcall(function() if type(setclipboard) == "function" then setclipboard(report) end end)
	aclog(("[AC] scan complete — %d lines%s%s"):format(#L,
		saved and (" · saved " .. saved) or "",
		type(setclipboard) == "function" and " · copied to clipboard" or ""))
end

if Config.AntiCheatBypass then
	task.spawn(function()
		aclog("[AC] scanning for anticheat…")
		for _ = 1, 30 do
			pcall(muteAC)
			pcall(neutralizeAC)
			if (State.acMuted or 0) > 0 or (State.acNeutralized or 0) > 0 then break end
			task.wait(0.5)
		end
		if (State.acNeutralized or 0) > 0 then
			aclog(("[AC] READY — %d report method(s) neutralized in GC%s; Kick+HTTP also blocked"):format(
				State.acNeutralized, (State.acMuted or 0) > 0 and (" + " .. State.acMuted .. " conns muted") or ""))
		elseif (State.acMuted or 0) > 0 then
			aclog(("[AC] READY — anticheat muted (%d connections disabled); Kick+HTTP reports also blocked"):format(State.acMuted))
		elseif State.acScript then
			aclog("[AC] anticheat found but nothing muteable/neutralizable yet — Kick+HTTP report blocking still active")
		else
			aclog("[AC] anticheat script not found — Kick+HTTP report blocking still active as fallback")
		end
		pcall(function()
			local lp = Players.LocalPlayer
			if lp then lp.CharacterAdded:Connect(function()
				task.wait(0.5); pcall(muteAC); pcall(neutralizeAC)
			end) end
		end)
	end)
end

if Config.AntiCheatBypass and Config.AutoScanAC then
	task.spawn(function()
		task.wait(5)
		aclog("[AC] auto-running deep scan (also on key O)…")
		local ok, err = pcall(scanAC)
		if not ok then aclog("[AC] auto-scan ERROR: " .. tostring(err)) end
	end)
end

local classifyCombat = LPH_NO_VIRTUALIZE(function(a)
	if type(a) ~= "table" or a.Type ~= "Combat" then return nil end
	if a.Action == "M1" or a.Action == "M2" then return "attack" end
	if a.Action == "Evasive" then return "dash" end
	return nil
end)

local function desyncApplies(action)
	if action == "M1" then return Config.DesyncApplyM1 end
	if action == "M2" then return Config.DesyncApplyM2 end
	return false
end

local function desyncMag()
	local ms = Config.DesyncDelayMs or 0
	if ms < 0 then ms = 0 end
	return ms / 1000
end

local _capturedIdleId
local function captureIdleId(animator)
	local myHRP = localHRP()
	local speed = 0
	if myHRP then
		local ok, v = pcall(function() return myHRP.AssemblyLinearVelocity end)
		if ok and v then speed = Vector3.new(v.X, 0, v.Z).Magnitude end
	end
	if speed > 3 then return _capturedIdleId end
	local best, bestW
	pcall(function()
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			local tid, looped, w = nil, false, 0
			pcall(function() tid = tonumber(tostring(t.Animation.AnimationId):match("(%d+)")) end)
			pcall(function() looped = t.Looped end)
			pcall(function() w = t.WeightCurrent end)
			if tid and looped and not AttackIds[tid] then
				if not bestW or w > bestW then best, bestW = tid, w end
			end
		end
	end)
	if best then _capturedIdleId = best end
	return _capturedIdleId
end

local _decoyAnim, _decoyTrack, _decoyId
local function getIdleDecoy(animator)
	local id = captureIdleId(animator) or Config.DesyncDecoyId or 507766388
	if _decoyId ~= id then
		_decoyId    = id
		_decoyTrack = nil
		pcall(function()
			_decoyAnim = Instance.new("Animation")
			_decoyAnim.AnimationId = "rbxassetid://" .. tostring(id)
		end)
	end
		if not _decoyTrack and _decoyAnim then
			pcall(function() _decoyTrack = animator:LoadAnimation(_decoyAnim) end)
			local owners = State.ap.trackOwners()
			if owners and _decoyTrack then owners[_decoyTrack] = { owner = "antiparry-idlemask" } end
		end
		return _decoyTrack
end

local SelfVerify = { conn = nil, lastLog = {}, decoyId = nil }

local _testAnim, _testTrack, _testId
local DesyncTest = { on = false }
local function pickAttackId()
	if Config.DesyncTestId then return Config.DesyncTestId end
	for id, e in pairs(AttackIds) do
		if e and e.kind == "M1" then return id end
	end
	for id in pairs(AttackIds) do return id end
	return 507766388
end
local function getTestDecoy(animator)
	local id = pickAttackId()
	if _testId ~= id then
		_testId, _testTrack = id, nil
		pcall(function()
			_testAnim = Instance.new("Animation")
			_testAnim.AnimationId = "rbxassetid://" .. tostring(id)
		end)
	end
		if not _testTrack and _testAnim then
			pcall(function() _testTrack = animator:LoadAnimation(_testAnim) end)
			local owners = State.ap.trackOwners()
			if owners and _testTrack then owners[_testTrack] = { owner = "antiparry-decoy" } end
		end
		return _testTrack, id
end
local function toggleDesyncTest()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	DesyncTest.on = not DesyncTest.on
	if DesyncTest.on then
		local track, id = getTestDecoy(animator)
		if not track then DesyncTest.on = false; return end
		SelfVerify.decoyId = "rbxassetid://" .. tostring(id)
		local topPrio = Enum.AnimationPriority.Action
		pcall(function() topPrio = Enum.AnimationPriority.Action4 end)
		local wgt = Config.DesyncClientVisible and 1 or 0.03
		pcall(function()
			track.Priority = topPrio
			track.Looped = true
			track:Play(0.1)
			track:AdjustWeight(wgt, 0)
		end)
		if DesyncTest.conn then pcall(function() DesyncTest.conn:Disconnect() end) end
		local autoEvery = 0.5
		pcall(function() local L = _testTrack.Length; if type(L) == "number" and L > 0.15 then autoEvery = L * 0.92 end end)
		local function replayInterval()
			local hz = tonumber(Config.DesyncSendHz) or 0
			if hz > 0 then return 1 / hz end
			return autoEvery
		end
		local nextReplay = os.clock() + replayInterval()
		DesyncTest.conn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
			if not DesyncTest.on or not _testTrack then return end
			pcall(function()
				_testTrack.Priority = topPrio
				local nowc = os.clock()
				if nowc >= nextReplay or not _testTrack.IsPlaying then
					nextReplay = nowc + replayInterval()
					_testTrack:Stop(0)
					_testTrack:Play(0.05)
					_testTrack:AdjustWeight(wgt, 0)
				end
				if _testTrack.WeightCurrent < wgt * 0.5 then _testTrack:AdjustWeight(wgt, 0.1) end
			end)
		end))
	else
		if DesyncTest.conn then pcall(function() DesyncTest.conn:Disconnect() end); DesyncTest.conn = nil end
		pcall(function() if _testTrack then _testTrack:Stop(0.1) end end)
	end
end
if type(getgenv) == "function" then getgenv().AP_DESYNC_TEST = toggleDesyncTest end

local DZ = {}
do
local function localAnimator()
	local ch = LocalPlayer.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end
local function topPriority()
	local p = Enum.AnimationPriority.Action
	pcall(function() p = Enum.AnimationPriority.Action4 end)
	return p
end
local IdleMask = { conn = nil }
local function stopIdleMask()
	if IdleMask.conn then pcall(function() IdleMask.conn:Disconnect() end); IdleMask.conn = nil end
	pcall(function() if _decoyTrack then _decoyTrack:Stop(0.1) end end)
end
local function startIdleMask()
	if IdleMask.conn then return end
	local animator = localAnimator()
	if not animator then aclog("[DESYNC:idlemask] нет аниматора (заспавнись)"); return end
	local track = getIdleDecoy(animator)
	if not track then aclog("[DESYNC:idlemask] idle-decoy не найде��"); return end
	local topPrio = topPriority()
	local wgt = Config.DesyncClientVisible and 1 or 0.92
	pcall(function() track.Priority = topPrio; track.Looped = true; track:Play(0.2); track:AdjustWeight(wgt, 0.1) end)
	IdleMask.conn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
		local an = localAnimator(); if not an then return end
		local tr = getIdleDecoy(an); if not tr then return end
		pcall(function()
			tr.Priority = topPrio
			if not tr.IsPlaying then
				tr.Looped = true
				tr:Play(0.2); tr:AdjustWeight(wgt, 0.1)
			elseif tr.WeightCurrent < wgt * 0.5 then
				tr:AdjustWeight(wgt, 0.1)
			end
		end)
	end))
	aclog("[desync] idlemask on")
end

local PreRun = { busyUntil = 0 }
local function firePreRunDecoy()
	local now = os.clock()
	if now < PreRun.busyUntil then return end
	PreRun.busyUntil = now + 0.22
	local animator = localAnimator(); if not animator then return end
	local track, id = getTestDecoy(animator); if not track then return end
	local topPrio = topPriority()
	local wgt = Config.DesyncClientVisible and 1 or 0.92
	local dur = (Config.DesyncDelayMs or 140) / 1000
	SelfVerify.decoyId = "rbxassetid://" .. tostring(id)
	task.spawn(function()
		pcall(function() track.Priority = topPrio; track.Looped = false; track:Play(0.02); track:AdjustWeight(wgt, 0) end)
		task.wait(dur)
		pcall(function() track:Stop(0.05) end)
	end)
end

local function applyDesyncMode()
	stopIdleMask()
	if Config.DesyncAttack and Config.DesyncMode == "idlemask" then
		startIdleMask()
	end
end
local DESYNC_CYCLE = { "delay", "firedelay", "idlemask", "prerun" }
local function cycleDesyncMode()
	local cur, idx = Config.DesyncMode or "delay", 1
	for i, m in ipairs(DESYNC_CYCLE) do if m == cur then idx = i break end end
	Config.DesyncMode = DESYNC_CYCLE[(idx % #DESYNC_CYCLE) + 1]
	applyDesyncMode()
	aclog(("[desync] mode: %s%s"):format(Config.DesyncMode, Config.DesyncAttack and "" or " (off)"))
end

DZ.firePreRunDecoy = firePreRunDecoy
DZ.applyDesyncMode = applyDesyncMode
DZ.cycleDesyncMode = cycleDesyncMode
end
if type(getgenv) == "function" then getgenv().AP_DESYNC_MODE = DZ.cycleDesyncMode end

local IV = {}
do
	local RS = RunService
	local function char()      return LocalPlayer.Character end
	local function humanoid()  local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
	local function rootOf()
		local c = char()
		return c and (c:FindFirstChild("HumanoidRootPart") or (humanoid() and humanoid().RootPart))
	end

	local Inv = { enabled = false, bindKey = nil, hb = nil, resp = nil, track = nil, oldcf = nil }

	local function playContort()
		if not Config.InvisibleAnim then return end
		local hum = humanoid(); if not hum then return end
		local animator = hum:FindFirstChildOfClass("Animator"); if not animator then return end
		local isR15 = hum.RigType == Enum.HumanoidRigType.R15
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. (isR15 and "18537363391" or "215384594")
		local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
		pcall(function() anim:Destroy() end)
		if ok and tr then
			Inv.track = tr
			pcall(function()
				tr.Priority = Enum.AnimationPriority.Action4
				tr:Play(0, 0.001, 0)
			end)
			task.delay(0, function() pcall(function() tr.TimePosition = isR15 and 0.77 or 0.38 end) end)
		end
	end

	local function stopInvisible()
		Inv.enabled = false
		if Inv.bindKey then pcall(function() RS:UnbindFromRenderStep(Inv.bindKey) end); Inv.bindKey = nil end
		if Inv.hb   then pcall(function() Inv.hb:Disconnect()   end); Inv.hb   = nil end
		if Inv.resp then pcall(function() Inv.resp:Disconnect() end); Inv.resp = nil end
		if Inv.track then pcall(function() Inv.track:Stop(); Inv.track:Destroy() end); Inv.track = nil end
		local r = rootOf()
		if r and Inv.oldcf then pcall(function() r.CFrame = Inv.oldcf end) end
		Inv.oldcf = nil
	end

	local function startInvisible()
		if Inv.enabled then return end
		Inv.enabled = true
		Inv.oldcf = nil
		playContort()

		Inv.bindKey = "AP_Invisible_" .. tostring(math.random(1e6, 9e6))
		pcall(function()
			RS:BindToRenderStep(Inv.bindKey, 0, LPH_NO_VIRTUALIZE(function()
				local r = rootOf()
				if r and Inv.oldcf then
					r.CFrame = Inv.oldcf
					if Inv.track then pcall(function() Inv.track:AdjustWeight(0.001) end) end
				end
			end))
		end)

		Inv.hb = RS.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
			if not Inv.enabled then return end
			local r = rootOf(); local hum = humanoid()
			if not r or not hum then return end
			Inv.oldcf = r.CFrame
			local isR15 = hum.RigType == Enum.HumanoidRigType.R15
			local baseDrop = (hum.HipHeight or 2) + (r.Size.Y / 2) - 1
			local drop = baseDrop + (tonumber(Config.InvisibleHeight) or 0)
			local cf = r.CFrame - Vector3.new(0, drop, 0)
			pcall(function()
				r.CFrame = cf * CFrame.Angles(math.rad(isR15 and 180 or 90), 0, 0)
				if Inv.track then Inv.track:AdjustWeight(100) end
			end)
		end))

		Inv.resp = LocalPlayer.CharacterAdded:Connect(function()
			if not Config.InvisibleOn then return end
			task.wait(0.6)
			stopInvisible()
			if Config.InvisibleOn then startInvisible() end
		end)
	end

	function IV.setInvisible(on)
		Config.InvisibleOn = on and true or false
		if Config.InvisibleOn then startInvisible() else stopInvisible() end
	end
end

local Observers = {}
local function observeOtherPlayer(name)
	local target = Players:FindFirstChild(name)
	if not target then
		aclog(("[DESYNC-OBSERVE] игрок '%s' не найден рядом"):format(tostring(name)))
		return
	end
	local last = {}
	local function hook(char)
		if not char then return end
		task.spawn(function()
			local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
			local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 8))
			if not animator then return end
			if Observers[name] then pcall(function() Observers[name]:Disconnect() end) end
			Observers[name] = animator.AnimationPlayed:Connect(function(track)
				pcall(function()
					local aid = track and track.Animation and track.Animation.AnimationId or "?"
					local now = os.clock()
					if (now - (last[aid] or 0)) < 0.25 then return end
					last[aid] = now
					local isAttack = AttackIds and AttackIds[aid] ~= nil
					local line = ("[OBSERVE %s] REPLICATED-TO-ME: id=%s %s prio=%s")
						:format(name, tostring(aid), isAttack and "(=ATTACK id!)" or "(non-attack/idle)",
							tostring(track and track.Priority))
					aclog("[DESYNC-OBSERVE] " .. line)
					desyncPush(line)
				end)
			end)
			aclog(("[DESYNC-OBSERVE] watching %s's animator — what THEY replicate to me is now logged (this is the enemy's-eye view)"):format(name))
			desyncPush(("[OBSERVE] started watching %s (enemy's-eye view of what replicates)"):format(name))
		end)
	end
	hook(target.Character)
	target.CharacterAdded:Connect(hook)
end
if type(getgenv) == "function" then getgenv().AP_OBSERVE = observeOtherPlayer end

Players.PlayerRemoving:Connect(function(plr)
	local n = plr.Name
	local c = Observers[n]
	if c then pcall(function() c:Disconnect() end); Observers[n] = nil end
	if State.antiDecoySig then State.antiDecoySig[n] = nil end
	if Pending then Pending[n] = nil end
	if ComboState[n] ~= nil then
		ComboState[n] = nil
		ComboState._count = math.max((ComboState._count or 1) - 1, 0)
	end
end)

local function saveDesyncDebug()
	local header = table.concat({
		"===== AUTOPARRY DESYNC DEBUG (V75) =====",
		("player=%s  mode=%s  DesyncAttack=%s  applyM1=%s applyM2=%s clientVisible=%s")
			:format(LocalPlayer.Name, tostring(Config.DesyncMode), tostring(Config.DesyncAttack),
				tostring(Config.DesyncApplyM1), tostring(Config.DesyncApplyM2), tostring(Config.DesyncClientVisible)),
		("raknet API present=%s  (add_send_hook=%s remove_send_hook=%s)")
			:format(tostring(type(raknet) == "table"),
				tostring(type(raknet) == "table" and type(raknet.add_send_hook) == "function"),
				tostring(type(raknet) == "table" and type(raknet.remove_send_hook) == "function")),
		"legend: [SWING]=ServerCheck packet timing (SENT=immediate, HELD=delayed) | [DESYNC]=animation timing",
		"        [OBSERVE]=track seen on ANOTHER player's animator from a 2nd client (true enemy view)",
		"        [SCAN]=raknet outgoing-packet histogram (near=during my attacks, far=background)",
		"how to get the enemy-view lines: run this script on a 2nd account near your main,",
		"  then call getgenv().AP_OBSERVE(\"YourMainName\") and swing on the main.",
		"=========================================",
	}, "\n")
	local body = header .. "\n\n" .. table.concat(DesyncLog, "\n") .. "\n"
	local fname = ("autoparry_desync_%d.txt"):format(os.time() % 1000000)
	local ok = pcall(function() if writefile then writefile(fname, body) end end)
	if ok and writefile then
		aclog(("[DESYNC] SAVED -> %s  (%d lines). Отправь мне этот файл."):format(fname, #DesyncLog))
		if setclipboard then pcall(setclipboard, fname) end
	else
		aclog("[DESYNC] writefile unavailable — dumping debug to status log:")
		statusPush(body)
	end
	return fname
end
if type(getgenv) == "function" then getgenv().AP_SAVE_DESYNC = saveDesyncDebug end

local _desyncBusyUntil = setmetatable({}, { __mode = "k" })
function AnimLib.desyncOwnTrack(track, id, animator)
	if not track then return end
	local entry = AttackIds[id]
	if not entry then return end
	local kind = (entry.kind == "M2") and "M2" or "M1"
	if not desyncApplies(kind) then return end
	local now = os.clock()
	local busy = _desyncBusyUntil[track]
	if busy and now < busy then return end

	if (Config.DesyncMode or "delay") ~= "delay" then return end
	if track == _testTrack or track == _decoyTrack then return end
	if DesyncTest.on then
		if (os.clock() - (State.lastAAPSkipLog or 0)) > 2 then
			State.lastAAPSkipLog = os.clock()
			aclog("[desync] anim-delay skipped �� anti-autoparry owns the anim channel (use firedelay instead)")
		end
		return
	end

	local window = (Config.DesyncDelayMs or 0) / 1000 + 0.05
	_desyncBusyUntil[track] = now + window

	local origSpeed = 1
	pcall(function() local s = track.Speed; if type(s) == "number" and s > 0.05 then origSpeed = s end end)
	State.desyncFires = (State.desyncFires or 0) + 1

	local animId = id
	local mag = desyncMag()
	pcall(function() track:Stop(0) end)
	task.delay(mag, function()
		pcall(function()
			track:Play(0)
			track:AdjustSpeed(origSpeed > 0 and origSpeed or 1)
		end)
	end)
	if (os.clock() - (State.lastDelayLog or 0)) > 0.15 then
		State.lastDelayLog = os.clock()
		aclog(("[desync] %s anim held +%dms"):format(kind, math.floor(mag * 1000)))
	end
end

task.spawn(function()
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		dbg("combat hook: metamethod API unavailable — Guard/BlockKick/Desync disabled")
		aclog("[desync] no metamethod api")
		return
	end
	local NC_WATCHED = {
		FireServer = true, Kick = true,
		PostAsync = true, RequestAsync = true, GetAsync = true,
	}
	local nc_getMethod  = getnamecallmethod
	local nc_checkcaller = (type(checkcaller) == "function") and checkcaller or nil
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", hideHook(LPH_NO_VIRTUALIZE(function(self, ...)
		local method = nc_getMethod()
		if not NC_WATCHED[method] then return oldNamecall(self, ...) end

		local mine = (nc_checkcaller and nc_checkcaller()) or false
		if mine and method ~= "FireServer" then return oldNamecall(self, ...) end

		if Config.BlockKick and method == "Kick" then
			local okp, isPlayer = pcall(function() return typeof(self) == "Instance" and self:IsA("Player") end)
			if okp and isPlayer then
				State.kicksBlocked = (State.kicksBlocked or 0) + 1
				diagPush(("BYPASS  t=%.2f  blocked local Kick on %s"):format(os.clock(), tostring(self.Name)))
				aclog(("[AC] !! KICK BLOCKED #%d — anticheat tried to Player:Kick() us; swallowed"):format(State.kicksBlocked))
				return
			end
		end

		if Config.BlockACReports
		   and (method == "PostAsync" or method == "RequestAsync" or method == "GetAsync") then
			local caller = (type(getcallingscript) == "function") and getcallingscript() or nil
			if caller and caller == State.acScript then
				State.reportsBlocked = (State.reportsBlocked or 0) + 1
				diagPush(("BYPASS  t=%.2f  blocked AC HTTP %s"):format(os.clock(), method))
				if State.reportsBlocked <= 3 or (os.clock() - (State.lastReportLog or 0)) > 5 then
					State.lastReportLog = os.clock()
					aclog(("[AC] REPORT BLOCKED #%d — anticheat tried %s (detection phone-home); swallowed")
						:format(State.reportsBlocked, method))
				end
				return
			end
		end

		if method ~= "FireServer" then
			return oldNamecall(self, ...)
		end
		if (State.desyncPass or 0) > 0 then return oldNamecall(self, ...) end

		local a1 = (select(1, ...))
		local ok, kind = pcall(classifyCombat, a1)
		if ok and kind then
			if not State.combatFireSeen then
				State.combatFireSeen = true
				aclog(("[desync] combat FireServer intercepted (%s/%s) — hook OK")
					:format(tostring(a1.Action), tostring(a1.Func)))
			end
			local now = os.clock()
				if kind == "attack" then
					State.selfBusyUntil = now + Config.SelfBusyDur
					State.attackBusyUntil = now + Config.SelfBusyDur
				local func = a1.Func
				if Config.DesyncAttack and func == "ServerCheck"
				   and (Config.DesyncMode == "firedelay" or Config.DesyncMode == "prerun")
				   and desyncApplies(a1.Action) then
					if Config.DesyncMode == "prerun" then pcall(DZ.firePreRunDecoy) end
					local remote, packed, d = self, table.pack(...), desyncMag()
					task.delay(d, function()
						State.desyncPass = (State.desyncPass or 0) + 1
						pcall(function() remote:FireServer(table.unpack(packed, 1, packed.n)) end)
						State.desyncPass = State.desyncPass - 1
					end)
					if (now - (State.lastSwingLog or 0)) > 0.15 then
						State.lastSwingLog = now
						aclog(("[desync] %s send held +%dms"):format(tostring(a1.Action), math.floor(d * 1000)))
					end
					return
				end
			elseif kind == "dash" then
				State.selfBusyUntil = now + Config.DashDuration
			end
		end
		return oldNamecall(self, ...)
	end)))
	AnimLib.desyncHooked = true
	dbg("combat hook active")
end)

local activeRestrictZone = LPH_NO_VIRTUALIZE(function(now)
	if not Config.RestrictZone then return nil end
	local best, bestC
	for _, th in ipairs(Threats) do
		if th.threatens and th.attackerHRP and th.attackerHRP.Parent then
			local isLong   = (not Config.RestrictLongOnly) or th.kind == "M2" or th.kind == "SKILL"
			local windupOK = (th.contact0 or 0) >= Config.RestrictMinWindup
			local future   = (th.contactAbs or 0) > now
			if isLong and windupOK and future then
				if not bestC or th.contactAbs < bestC then best, bestC = th, th.contactAbs end
			end
		end
	end
	if not best then return nil end
	local center, _forward, aPos, look = hitboxGeom(best)
	if not center then return nil end
	local radius = math.max(Config.HitboxDepth or 4, Config.HitHalfWidth or 3.2)
	return {
		center = center, keepOut = radius + Config.RestrictPad, radius = radius,
		aPos = aPos, look = look, th = best,
	}
end)

local restrictStep = LPH_NO_VIRTUALIZE(function(now)
	if not Config.RestrictZone then return end
	local hrp = localHRP(); if not hrp then return end
	if (now - State.lastDodge) < (Config.DashDuration + 0.05) then return end
	local z = activeRestrictZone(now); if not z then return end
	local pos  = hrp.Position
	local toC  = Vector3.new(z.center.X - pos.X, 0, z.center.Z - pos.Z)
	local dist = toC.Magnitude
	if dist < 0.05 or dist >= z.keepOut then return end
	local inward = toC.Unit
	local vel = hrp.AssemblyLinearVelocity
	local hv  = Vector3.new(vel.X, 0, vel.Z)
	local vin = hv:Dot(inward)
	if vin <= 0 then return end
	local newHV = hv - inward * vin
	hrp.AssemblyLinearVelocity = Vector3.new(newHV.X, vel.Y, newHV.Z)
	if not Config.RestrictSoft then
		local b = z.center - inward * z.keepOut
		hrp.CFrame = CFrame.new(Vector3.new(b.X, pos.Y, b.Z)) * (hrp.CFrame - hrp.CFrame.Position)
	end
end)

V93.schedulerPhase = RunService.PreSimulation and "PreSimulation" or "Heartbeat-fallback"
;(RunService.PreSimulation or RunService.Heartbeat):Connect(LPH_NO_VIRTUALIZE(function(hbDt)
	if type(hbDt) == "number" and hbDt > 0 then
		local d = math.clamp(hbDt, 1/480, 0.25)
		V93.frameDt = V93.frameDt + (d - V93.frameDt) * 0.2
		if d > V93.frameDtPeak then
			V93.frameDtPeak = d
		else
			local hl = Config.FrameLookaheadPeakDecay or 1.10
			V93.frameDtPeak = V93.frameDtPeak + (d - V93.frameDtPeak) * math.clamp(d / hl, 0, 1)
		end
	end
	do
		local byEma  = V93.frameDt     * (Config.FrameLookahead or 0.5)
		local byPeak = V93.frameDtPeak * (Config.FrameLookaheadPeakK or 0.5)
		local want   = (byEma > byPeak) and byEma or byPeak
		want = want + (V93.stepCost or 0) * (Config.FrameStepCostComp or 0.60)
		local cap = Config.FrameLookaheadCap or 0.045
		local capByPeak = V93.frameDtPeak * (Config.FrameLookaheadCapK or 0.75)
		if capByPeak > cap then cap = capByPeak end
		local capHi = Config.FrameLookaheadCapHi or 0.11
		if cap > capHi then cap = capHi end
		V93.lookahead = (want < cap) and want or cap
	end
	if not Config.Enabled then
		if State.blocking then releaseBlock() end
		State.status = "OFF"
		return
	end
	local now = os.clock()
	FrameId = FrameId + 1
	if State.ap.steerUntil and now < State.ap.steerUntil and State.ap.steerDir then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then pcall(V93.humMove, hum, State.ap.steerDir) end
	end
	if State.ap.dodgeSteerUntil and now < State.ap.dodgeSteerUntil and State.ap.dodgeSteerDir then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then pcall(V93.humMove, hum, State.ap.dodgeSteerDir) end
	end
	pcall(schedulerStep, now)
	V93.stepCost = V93.stepCost + ((os.clock() - now) - V93.stepCost) * 0.15
	pcall(restrictStep, now)

	if State.guardUp and not State.blocking then
		pcall(sendDeactivate, true)
	end

	if FrameId % 15 == 0 then
		for name, q in pairs(Pending) do
			for i = #q, 1, -1 do
				if now - q[i].clock > 3 then table.remove(q, i) end
			end
			if #q == 0 then Pending[name] = nil end
		end
	end

	if not State.blocking and State.status ~= "THREAT" then
		if now >= State.flashUntil then State.status = "ARMED" end
	end
end))

local function summary()
	local t = State.tally
	local total = (t.PERFECT or 0)+(t.EARLY or 0)+(t.LATE or 0)+(t.GUARDBREAK or 0)
	local hits = (t.LATE or 0) + (t.GUARDBREAK or 0)
	local stateHits = State.stateHits or 0
	local realMiss = math.max(0, hits - stateHits)
	local blockable = total - stateHits
	local acc = blockable > 0 and (100 * ((t.PERFECT or 0) + (t.EARLY or 0)) / blockable) or 0
	return table.concat({
		("===== AUTOPARRY %s DIAG =====  (dumped %s UTC)")
			:format(tostring(Config.Version or "?"), os.date("!%Y-%m-%d %H:%M:%S")),
		("player=%s  ping=%.0fms  uplink=%.0fms  mode=%s  autoface=%s"):format(LocalPlayer.Name, getPingRaw()*1000, uplink()*1000, Config.Mode, tostring(Config.AutoFace)),
		("scheduler: phase=%s fps=%.1f frame=%.1fms peak=%.1fms lookahead=%.1fms step=%.1fms")
			:format(tostring(V93.schedulerPhase or "?"), 1 / math.max(V93.frameDt or 1/60, 1/480),
				(V93.frameDt or 0)*1000, (V93.frameDtPeak or 0)*1000,
				(V93.lookahead or 0)*1000, (V93.stepCost or 0)*1000),
		("model: PURE anim timeline + live TimePosition (NO calibration) | ping=robust median; lead=%.0fms hold=%.0fms window=[%.0f,%.0f]ms")
			:format(Config.PerfectLead*1000, Config.HoldAfter*1000, Config.PerfectMin*1000, Config.PerfectWindow*1000),
		("outcomes: PERFECT=%d  BLOCK=%d  HIT=%d  GUARDBREAK=%d  total=%d"):format(t.PERFECT or 0, t.EARLY or 0, t.LATE or 0, t.GUARDBREAK or 0, total),
		("attacks=%d  presses=%d  dodges=%d  outnumbered-escapes=%d  desync-anims=%d  ac-muted=%d  kicks-blocked=%d  reports-blocked=%d"):format(State.parryCount, State.fireCount, State.dodgeCount, State.grantEscapes or 0, State.desyncFires or 0, State.acMuted or 0, State.kicksBlocked or 0, State.reportsBlocked or 0),
		("HIT breakdown: %d total → %d game-state-locked (stun/attack/cooldown, unblockable) + %d real timing miss")
			:format(hits, stateHits, realMiss),
		("BLOCKABLE accuracy = %.1f%%  (%d/%d attacks we were allowed to block landed as block/perfect)")
			:format(acc, blockable - realMiss, blockable),
		("accuracy mode: %s  |  off-target swings rejected=%d  |  boxing-counter fired=%d  |  dodges skipped by counter i-frames=%d")
			:format(Config.AccuracyMode or "Low", State.offTargetRej or 0, State.counterCount or 0,
				State.counterCoverSkips or 0),
		"=============================",
	}, "\n")
end

Config.RingA       = Config.RingA       or Color3.fromRGB(196, 158, 255)
Config.RingB       = Config.RingB       or Color3.fromRGB(122, 214, 255)
Config.ConeSafe    = Config.ConeSafe    or Color3.fromRGB(96, 214, 140)
Config.ConeHit     = Config.ConeHit     or Color3.fromRGB(255, 84, 84)
Config.RestrictCol = Config.RestrictCol or Color3.fromRGB(255, 72, 72)

local vizUpdate, vizHideAll
do
local RING_SEG  = 24
local CONE_SEG  = 12
local CONE_FILL = 0.32
local VIZ_CONE_HALF = math.rad(64)
local VIZ_CONE_PAD  = 5.0
local VIEW_DIST = 100

local LinePool = { items = {}, used = 0, ok = (Drawing ~= nil) }
LinePool.begin = LPH_NO_VIRTUALIZE(function(self) self.used = 0 end)
LinePool.get = LPH_NO_VIRTUALIZE(function(self)
	if not self.ok then return nil end
	self.used += 1
	local ln = self.items[self.used]
	if not ln then
		local created = pcall(function() ln = Drawing.new("Line") end)
		if not created then self.ok = false; return nil end
		self.items[self.used] = ln
	end
	return ln
end)
LinePool.finish = LPH_NO_VIRTUALIZE(function(self)
	local hidden = self.hiddenTo or #self.items
	for i = self.used + 1, hidden do self.items[i].Visible = false end
	self.hiddenTo = self.used
end)
LinePool.hideAll = LPH_NO_VIRTUALIZE(function(self)
	for _, ln in ipairs(self.items) do ln.Visible = false end
	self.used, self.hiddenTo = 0, 0
end)

local TriPool = { items = {}, used = 0, ok = (Drawing ~= nil) }
TriPool.begin = LPH_NO_VIRTUALIZE(function(self) self.used = 0 end)
TriPool.get = LPH_NO_VIRTUALIZE(function(self)
	if not self.ok then return nil end
	self.used += 1
	local tr = self.items[self.used]
	if not tr then
		local created = pcall(function() tr = Drawing.new("Triangle"); tr.Filled = true end)
		if not created then self.ok = false; return nil end
		self.items[self.used] = tr
	end
	return tr
end)
TriPool.finish = LPH_NO_VIRTUALIZE(function(self)
	local hidden = self.hiddenTo or #self.items
	for i = self.used + 1, hidden do self.items[i].Visible = false end
	self.hiddenTo = self.used
end)
TriPool.hideAll = LPH_NO_VIRTUALIZE(function(self)
	for _, tr in ipairs(self.items) do tr.Visible = false end
	self.used, self.hiddenTo = 0, 0
end)

function vizHideAll() LinePool:hideAll(); TriPool:hideAll() end

local Viz = { t = 0 }

local NEAR = 0.6

Viz.rotY = LPH_NO_VIRTUALIZE(function(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end)

Viz.projRaw = LPH_NO_VIRTUALIZE(function(cam, world)
	local sp = cam:WorldToViewportPoint(world)
	return sp.X, sp.Y, sp.Z
end)

Viz.proj = LPH_NO_VIRTUALIZE(function(cam, world)
	local x, y, z = Viz.projRaw(cam, world)
	return Vector2.new(x, y), z
end)

Viz.drawWorldSeg = LPH_NO_VIRTUALIZE(function(cam, a, b, color, thick)
	local ax, ay, az = Viz.projRaw(cam, a)
	local bx, by, bz = Viz.projRaw(cam, b)
	if az <= NEAR and bz <= NEAR then return end
	if az <= NEAR or bz <= NEAR then
		local t = (NEAR - az) / (bz - az)
		local mx, my = Viz.projRaw(cam, a:Lerp(b, t))
		if az <= NEAR then ax, ay = mx, my else bx, by = mx, my end
	end
	local ln = LinePool:get(); if not ln then return end
	ln.From, ln.To = Vector2.new(ax, ay), Vector2.new(bx, by)
	ln.Color, ln.Thickness, ln.Transparency, ln.Visible = color, thick, 1, true
end)

Viz.pickTarget = LPH_NO_VIRTUALIZE(function()
	local vt = State.vizTarget
	if vt and vt.model and vt.model.Parent and vt.hrp and vt.hrp.Parent then
		return vt.model, vt.hrp
	end
	local me = localHRP(); if not me then return nil end
	local best, bestHrp, bestD = nil, nil, (Config.VizRange or VIEW_DIST)
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch then
			local ok, hrp = isEnemyModel(ch)
			if ok and hrp then
				local d = (hrp.Position - me.Position).Magnitude
				if d < bestD then best, bestHrp, bestD = ch, hrp, d end
			end
		end
	end
	return best, bestHrp
end)

Viz.bboxRaw = function(m) return m:GetBoundingBox() end
Viz.bbModel, Viz.bbClock, Viz.bbC, Viz.bbS = nil, -1, nil, nil
Viz.ringPts = {}
Viz.coneW   = {}
Viz.cone2d  = {}
Viz.coneZ   = {}
Viz.bboxOf = LPH_NO_VIRTUALIZE(function(model)
	local nowc = os.clock()
	if model == Viz.bbModel and (nowc - Viz.bbClock) < 0.004 then return Viz.bbC, Viz.bbS end
	local ok, c, s = pcall(Viz.bboxRaw, model)
	if ok and typeof(c) == "CFrame" and typeof(s) == "Vector3" then
		Viz.bbModel, Viz.bbClock, Viz.bbC, Viz.bbS = model, nowc, c, s
		return c, s
	end
	return nil
end)

Viz.ribbonQuad = LPH_NO_VIRTUALIZE(function(cam, a, b, c, d, color, transp)
	local ax, ay, az = Viz.projRaw(cam, a)
	local bx, by, bz = Viz.projRaw(cam, b)
	local cx, cy, cz = Viz.projRaw(cam, c)
	local dx, dy, dz = Viz.projRaw(cam, d)
	if az <= 0 or bz <= 0 or cz <= 0 or dz <= 0 then return end
	local a2, b2 = Vector2.new(ax, ay), Vector2.new(bx, by)
	local c2, d2 = Vector2.new(cx, cy), Vector2.new(dx, dy)
	local t1 = TriPool:get()
	if t1 then
		t1.PointA, t1.PointB, t1.PointC = a2, b2, c2
		t1.Color, t1.Transparency, t1.Visible = color, transp, true
	end
	local t2 = TriPool:get()
	if t2 then
		t2.PointA, t2.PointB, t2.PointC = a2, c2, d2
		t2.Color, t2.Transparency, t2.Visible = color, transp, true
	end
end)

Viz.gradLUT, Viz.gradA, Viz.gradB = {}, nil, nil
Viz.grad = LPH_NO_VIRTUALIZE(function(a, b, f)
	if Viz.gradA ~= a or Viz.gradB ~= b then
		Viz.gradA, Viz.gradB = a, b
		local lut = Viz.gradLUT
		for i = 0, 32 do lut[i] = a:Lerp(b, i / 32) end
	end
	local i = f * 32 + 0.5
	i = (i < 0 and 0) or (i > 32 and 32) or (i // 1)
	return Viz.gradLUT[i]
end)

Viz.drawRing = LPH_NO_VIRTUALIZE(function(cam, model, hrp, hot)
	local footY = hrp.Position.Y - 2.8
	local radius = 3.2
	local bc, bs = Viz.bboxOf(model)
	if bc and bs then
		footY  = bc.Y - bs.Y * 0.5 + 0.08
		radius = math.clamp(math.max(bs.X, bs.Z) * 0.75, 2.4, 6)
	end
	radius = radius * (Config.VizRingScale or 1.0)
	local spd   = Config.VizRingSpeed or 1.0
	local style = Config.VizRingStyle or "Flat"
	local seg   = math.clamp(math.floor(Config.VizRingSeg or 30), 8, 48)
	local t     = Viz.t * spd
	local cx, cz = hrp.Position.X, hrp.Position.Z

	if style ~= "Orbit" and style ~= "OrbitSwirl" then
		local pulse = 1 + math.sin(t * 3.0) * 0.05
		local wpts = Viz.ringPts
		for i = 0, seg - 1 do
			local a = i / seg * math.pi * 2
			local r = radius * pulse * (1 + math.sin(a * 4 + t * 5) * 0.03)
			wpts[i] = Vector3.new(cx + math.cos(a) * r, footY, cz + math.sin(a) * r)
		end
		local thick = hot and 4 or 2.5
		for i = 0, seg - 1 do
			local j = (i + 1) % seg
			local f = 0.5 + 0.5 * math.sin(i / seg * math.pi * 2 + t * 2.2)
			Viz.drawWorldSeg(cam, wpts[i], wpts[j], Viz.grad(Config.RingA, Config.RingB, f), thick)
		end
		return
	end

	local bodyY = footY + ((bs and bs.Y or 5) * 0.5)
	local swirl = (style == "OrbitSwirl") and (t * 0.75) or 0
	local tilt  = Config.VizRingTilt or 0.7
	local rIn   = radius * 0.985

	for i = 0, seg - 1 do
		local a1 = (i / seg) * math.pi * 2 + swirl
		local a2 = ((i + 1) / seg) * math.pi * 2 + swirl
		local dy = math.cos(t + (i / seg) * math.pi * 2) * tilt
		local f  = 0.5 + 0.5 * math.sin((i / seg) * math.pi * 2 + t * 2.2)
		local col = Viz.grad(Config.RingA, Config.RingB, f)

		local y = bodyY + dy
		local c1, s1 = math.cos(a1), math.sin(a1)
		local c2, s2 = math.cos(a2), math.sin(a2)
		Viz.ribbonQuad(cam,
			Vector3.new(cx + c1 * rIn,    y, cz + s1 * rIn),
			Vector3.new(cx + c2 * rIn,    y, cz + s2 * rIn),
			Vector3.new(cx + c2 * radius, y, cz + s2 * radius),
			Vector3.new(cx + c1 * radius, y, cz + s1 * radius), col, 1)

		if Config.VizRingMirror ~= false then
			local ym = bodyY - dy
			local rMid = (rIn + radius) * 0.5
			Viz.drawWorldSeg(cam,
				Vector3.new(cx + math.cos(-a1) * rMid, ym, cz + math.sin(-a1) * rMid),
				Vector3.new(cx + math.cos(-a2) * rMid, ym, cz + math.sin(-a2) * rMid),
				Viz.grad(Config.RingA, Config.RingB, 1 - f), hot and 3 or 2)
		end
	end
end)

Viz.footYOf = LPH_NO_VIRTUALIZE(function(model, hrp)
	local y = hrp.Position.Y - 2.8
	local bc, bs = Viz.bboxOf(model)
	if bc and bs then y = bc.Y - bs.Y * 0.5 + 0.05 end
	return y
end)
Viz.drawTargetHitbox = LPH_NO_VIRTUALIZE(function(cam, model, hrp)
	local look = hrp.CFrame.LookVector
	local flook = Vector3.new(look.X, 0, look.Z)
	if flook.Magnitude < 0.05 then return end
	flook = flook.Unit

	local style = styleOf(model)
	local styleReach = math.max(styleForward(style, "M1"), styleForward(style, "M2"))
	local reach = styleReach + VIZ_CONE_PAD
	local half  = VIZ_CONE_HALF
	local y = Viz.footYOf(model, hrp)
	local origin = Vector3.new(hrp.Position.X, y, hrp.Position.Z)

		local col = Config.ConeSafe
		local me  = localHRP()
		if me then
			local forward = styleReach
			local off  = Vector3.new(me.Position.X - hrp.Position.X, 0, me.Position.Z - hrp.Position.Z)
			local fwd  = off:Dot(flook)
			local side = math.abs(off:Dot(Vector3.new(-flook.Z, 0, flook.X)))
			local slack = Config.HitboxSlack or 0
			if fwd >= (forward - Config.HitboxDepthBack - slack) and fwd <= (forward + Config.HitboxDepth + slack)
			   and side <= (Config.HitHalfWidth + slack) then
				col = Config.ConeHit
			end
		end

	local wArc = Viz.coneW
	for i = 0, CONE_SEG do
		local ang = -half + (i / CONE_SEG) * (half * 2)
		wArc[i] = origin + Viz.rotY(flook, ang) * reach
	end
	local o2d, oz = Viz.proj(cam, origin)
	local a2d, az = Viz.cone2d, Viz.coneZ
	for i = 0, CONE_SEG do a2d[i], az[i] = Viz.proj(cam, wArc[i]) end
	for i = 0, CONE_SEG - 1 do
		if oz > NEAR and az[i] > NEAR and az[i + 1] > NEAR then
			local tr = TriPool:get()
			if tr then
				tr.PointA, tr.PointB, tr.PointC = o2d, a2d[i], a2d[i + 1]
				tr.Color, tr.Transparency, tr.Filled, tr.Visible = col, CONE_FILL, true, true
			end
		end
	end
	Viz.drawWorldSeg(cam, origin, wArc[0], col, 2)
	Viz.drawWorldSeg(cam, origin, wArc[CONE_SEG], col, 2)
	for i = 0, CONE_SEG - 1 do Viz.drawWorldSeg(cam, wArc[i], wArc[i + 1], col, 2) end
end)

Viz.drawRestrictZone = LPH_NO_VIRTUALIZE(function(cam)
	if not (Config.RestrictZone and Config.RestrictShowZone) then return end
	local z = activeRestrictZone(os.clock()); if not z then return end
	local aHRP = z.th.attackerHRP; if not (aHRP and aHRP.Parent) then return end
	local y  = Viz.footYOf(z.th.attackerModel, aHRP)
	local cx, cz = z.center.X, z.center.Z
	local r  = z.keepOut * (1 + math.sin(Viz.t * 4) * 0.02)
	local center3 = Vector3.new(cx, y, cz)

	local function arc(a0, a1, rr, thick, steps)
		steps = steps or 6
		local prev
		for i = 0, steps do
			local a = a0 + (a1 - a0) * (i / steps)
			local p = Vector3.new(cx + math.cos(a) * rr, y, cz + math.sin(a) * rr)
			if prev then Viz.drawWorldSeg(cam, prev, p, Config.RestrictCol, thick) end
			prev = p
		end
	end

	local bracket = math.rad(34)
	for k = 0, 3 do
		local mid = math.rad(45) + k * math.rad(90)
		arc(mid - bracket / 2, mid + bracket / 2, r, 3, 7)
	end

	local ch = math.max(r * 0.14, 0.7)
	Viz.drawWorldSeg(cam, Vector3.new(cx - ch, y, cz), Vector3.new(cx + ch, y, cz), Config.RestrictCol, 2)
	Viz.drawWorldSeg(cam, Vector3.new(cx, y, cz - ch), Vector3.new(cx, y, cz + ch), Config.RestrictCol, 2)

	if z.aPos then
		local from = Vector3.new(z.aPos.X, y, z.aPos.Z)
		local dir  = Vector3.new(cx - z.aPos.X, 0, cz - z.aPos.Z)
		if dir.Magnitude > 0.1 then
			local edge = center3 - dir.Unit * r
			Viz.drawWorldSeg(cam, from, edge, Config.RestrictCol, 1.5)
		end
	end
end)

vizUpdate = LPH_NO_VIRTUALIZE(function(dt)
	if not LinePool.ok then return end
	local cam = Workspace.CurrentCamera
	if not (Config.Enabled and Config.ShowVisuals and cam) then vizHideAll(); return end
	Viz.t += dt

	local nowc     = os.clock()
	local interval = 1 / math.clamp(Config.VizMaxFPS or 60, 15, 240)
	if Config.VizAutoDegrade ~= false then
		local byFrame = V93.frameDt * (Config.VizFrameShare or 1.5)
		if byFrame > interval then interval = byFrame end
	end
	if (nowc - (Viz.lastDraw or 0)) < interval then return end
	local skipLim = Config.VizSkipNearPress or 0.20
	if skipLim > 0
	   and (nowc - (V93.nearPressStamp or 0)) < 0.20
	   and math.abs(V93.nearPress or math.huge) < skipLim
	   and (Viz.skipRun or 0) < (Config.VizSkipMaxFrames or 2) then
		Viz.skipRun = (Viz.skipRun or 0) + 1
		return
	end
	Viz.skipRun  = 0
	Viz.lastDraw = nowc

	LinePool:begin(); TriPool:begin()
	local model, hrp = Viz.pickTarget()
	publishVizTarget(model, hrp)
	if model and hrp then
		local hot = (State.status == "PARRY" or State.status == "DODGE")
		if Config.VizHitbox ~= false then Viz.drawTargetHitbox(cam, model, hrp) end
		if Config.VizRing ~= false then Viz.drawRing(cam, model, hrp, hot) end
	end
	if Config.VizRestrict ~= false then Viz.drawRestrictZone(cam) end
	LinePool:finish(); TriPool:finish()
end)
end

local applyFacing = LPH_NO_VIRTUALIZE(function()
	local goalPos = State.faceGoalPos
	local goalHRP = State.faceGoalHRP
	if not (goalHRP or goalPos) and not State.faceHum then return end
	local ec = localChar()
	local equipped = ec and ec:GetAttribute("Equip") == true
	if not (goalHRP or goalPos) or os.clock() > (State.faceGoalUntil or 0)
	   or (goalHRP and not goalHRP.Parent)
	   or (Config.RequireEquip ~= false and not equipped) then
		if State.faceHum then pcall(function() State.faceHum.AutoRotate = true end); State.faceHum = nil end
		State.faceGoalHRP = nil
		State.faceGoalPos = nil
		return
	end
	if not Config.AutoFace then return end
	local myHRP = localHRP()
	if not myHRP then return end
	local hum = ec and ec:FindFirstChildOfClass("Humanoid")
	if (Config.RotationMethod or "LookAt") ~= "AimLock" then
		if hum and hum.AutoRotate then hum.AutoRotate = false; State.faceHum = hum end
	elseif State.faceHum then
		pcall(function() State.faceHum.AutoRotate = true end); State.faceHum = nil
	end
	local aimPos = goalPos or goalHRP.Position
	local lead   = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.28)
	if lead > 0 then
		local vel     = goalHRP.AssemblyLinearVelocity
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		local gp = goalHRP.Position
		local toMe = Vector3.new(myHRP.Position.X - gp.X, 0, myHRP.Position.Z - gp.Z)
		if toMe.Magnitude > 0.05 then
			local axis     = toMe.Unit
			local radialVec = axis * flatVel:Dot(axis)
			local latVec    = flatVel - radialVec
			local latOff = latVec * lead
			local latCap = Config.FaceLatMaxStuds or 18
			if latOff.Magnitude > latCap then latOff = latOff.Unit * latCap end
			local radOff = radialVec * lead
			local radCap = Config.FaceRadMaxStuds or 5
			if radOff.Magnitude > radCap then radOff = radOff.Unit * radCap end
			aimPos = aimPos + latOff + radOff
		else
			local off = flatVel * lead
			local mx  = Config.FaceLeadMaxStuds or 16
			if off.Magnitude > mx then off = off.Unit * mx end
			aimPos = aimPos + off
		end
	end
	local d = flatDirTo(myHRP.Position, aimPos)
	if not d then return end

	if (Config.RotationMethod or "LookAt") == "AimLock" then
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local cp = cam.CFrame.Position
		local target = aimPos + Vector3.new(0, 1.2, 0)
		local goalCam = CFrame.lookAt(cp, target)
		if State.faceGoalHard then
			cam.CFrame = goalCam
		else
			cam.CFrame = cam.CFrame:Lerp(goalCam, math.clamp(Config.AimLockLerp or 0.35, 0.05, 1))
		end
		return
	end

	local goal = CFrame.lookAt(myHRP.Position, myHRP.Position + d)
	if State.faceGoalHard then
		myHRP.CFrame = goal
	else
		myHRP.CFrame = myHRP.CFrame:Lerp(goal, Config.FaceLerp or 0.8)
	end
end)

RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(dt)
	if not (Config.Enabled and Config.ShowVisuals) then return end
	local ok = pcall(vizUpdate, dt)
	if not ok then vizHideAll() end
end))

RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
	pcall(applyFacing)
end))

indexAllAnims()
loadGameModules()
scanAnimators()
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		task.wait(0.2)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then hookAnimator(animator) end
	end)
end)
task.spawn(function()
	while true do task.wait(3); scanAnimators() end
end)

return function(_Lib, _Core)
	local M = {}

	function M.start()
		Config.Enabled     = false
		Config.DesyncAttack = false
		if DesyncTest.on then pcall(toggleDesyncTest) end
	end

	function M.buildUI(ctx)
		local uiReady = false
		local function notify(title, body)
			if uiReady then pcall(ctx.notify, title, body) end
		end

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
				Name    = "Enabled",
				Default = o.get(),
				Callback = function(v)
					if guard then return end
					commit(v)
				end,
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
			local guard, togEl = false, nil
			togEl = section:Toggle({
				Name = name, Default = get(),
				Callback = function(v)
					if guard then return end
					set(v and true or false)
					notify(title, v and "Enabled" or "Disabled")
				end,
			}, ctx.flag(name:gsub("%s+", "") .. "_T"))
			return togEl
		end

		local function slider(section, o)
			return section:Slider({
				Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
				Precision = o.Precision or 0, Suffix = o.Suffix,
				Callback = o.Callback,
			}, ctx.flag(o.Flag))
		end

		local AP = ctx.tabs.AutoParry

		local apMain = AP:Section({ Side = "Left" })

		apMain:Header({ Name = "AutoParry" })
		feature(apMain, {
			Title = "AutoParry", Flag = "AP_Enabled",
			get = function() return Config.Enabled end,
			set = function(v)
				Config.Enabled = v
				if not v then pcall(releaseBlock); pcall(vizHideAll) end
			end,
			Desc = "auto blocks n rolls hits for u\nbind works on PC + mobile",
		})

		apMain:Divider()
		apMain:Header({ Name = "Detection" })
		slider(apMain, { Name = "FOV", Flag = "AP_FOV", Default = Config.FOV or 360,
			Min = 1, Max = 360, Suffix = "°", Callback = function(v) Config.FOV = v end })
		apMain:SubLabel({ Text = "only reacts to enemies in this cone\n360 = all around u" })
		slider(apMain, { Name = "Range", Flag = "AP_Range", Default = Config.Range or 32,
			Min = 8, Max = 64, Suffix = " st", Callback = function(v) Config.Range = v end })
		slider(apMain, { Name = "Max Height Diff", Flag = "AP_MaxHeight", Default = Config.MaxHeightDiff or 12,
			Min = 4, Max = 40, Suffix = " st", Callback = function(v) Config.MaxHeightDiff = v end })
		apMain:SubLabel({ Text = "ignore enemies this far above/below u (anti platform-cheese)" })
		boolToggle(apMain, "Server Proof", "Server Proof",
			function() return Config.ServerProofGate ~= false end,
			function(v) Config.ServerProofGate = v end)
		apMain:SubLabel({ Text = "counters ppl running anti-autoparry\nonly parries swings the server actually confirmed, fake anims get ignored" })
		slider(apMain, { Name = "Proof Grace", Flag = "AP_ProofGrace",
			Default = math.floor((Config.ProofGraceSec or 0.06) * 1000),
			Min = 20, Max = 150, Suffix = " ms",
			Callback = function(v) Config.ProofGraceSec = v / 1000 end })
		apMain:SubLabel({ Text = "this close to the hit we press anyway even if unconfirmed\nlower = harsher on fakes, higher = safer if server data is late" })
		apMain:Divider()
		apMain:Header({ Name = "Time Spoof" })
		boolToggle(apMain, "Time Spoof", "Time Spoof",
			function() return Config.TimeSpoof == true end,
			function(v) Config.TimeSpoof = v end)
		apMain:SubLabel({ Text = "parry sends its own timestamp, so we back-date it\nlate parries still land as perfect. tbh idk how much the server checks — test it" })
		slider(apMain, { Name = "Back-date", Flag = "AP_TimeShift",
			Default = Config.TimeShiftMs or 40,
			Min = 0, Max = 120, Suffix = " ms",
			Callback = function(v) Config.TimeShiftMs = v end })
		apMain:SubLabel({ Text = "how far back we claim u pressed. perfect window is 125ms\nstart ~40, creep up til it stops helping" })

		apMain:Divider()
		apMain:Header({ Name = "Rotation" })
		boolToggle(apMain, "Auto Face", "Auto Face", function() return Config.AutoFace end, function(v) Config.AutoFace = v end)
		apMain:SubLabel({ Text = "turn to face the attacker (needed for directional block/parry)" })
		local aimEls = {}
		local function rotVis()
			local isAim = (Config.RotationMethod or "LookAt") == "AimLock"
			for _, el in ipairs(aimEls) do pcall(function() el:SetVisibility(isAim) end) end
		end
		apMain:Dropdown({
			Name = "Method",
			Options = { "LookAt", "AimLock" },
			Default = Config.RotationMethod or "LookAt",
			Callback = function(v)
				if type(v) == "string" and v ~= "" then Config.RotationMethod = v; rotVis() end
			end,
		}, ctx.flag("AP_RotMethod"))
		apMain:SubLabel({ Text = "LookAt = turns ur model (safest for parry)\nAimLock = aims the camera instead, model isn't forced" })
		aimEls[#aimEls + 1] = slider(apMain, { Name = "Aim Speed", Flag = "AP_AimLockLerp",
			Default = math.floor((Config.AimLockLerp or 0.35) * 100), Min = 5, Max = 100, Suffix = "%",
			Callback = function(v) Config.AimLockLerp = v / 100 end })
		rotVis()
		boolToggle(apMain, "Instant Multi-Target Snap", "Multi Snap",
			function() return Config.MultiFaceHard end, function(v) Config.MultiFaceHard = v end)
		apMain:SubLabel({ Text = "in a group fight snap instantly to the next attacker" })
		boolToggle(apMain, "Hard Snap Near Contact", "Hard Snap", function() return Config.BlockFaceHard end, function(v) Config.BlockFaceHard = v end)
		apMain:SubLabel({ Text = "snap exactly on target right before the hit lands" })
		slider(apMain, { Name = "Rotation Speed", Flag = "AP_FaceLerp",
			Default = Config.FaceLerp or 0.80, Min = 0.10, Max = 1.00, Precision = 2,
			Callback = function(v) Config.FaceLerp = v end })

		local apDodge = AP:Section({ Side = "Right" })

		apDodge:Header({ Name = "Dodge" })
		feature(apDodge, {
			Title = "Auto Dodge", Flag = "AP_AutoDodge",
			get = function() return Config.AutoDodge ~= false end,
			set = function(v) Config.AutoDodge = v end,
			Desc = "master switch for ALL dodging (heavies, escapes, grabs, cluster)\nOFF = never dodge, block/parry only",
		})
		boolToggle(apDodge, "Dodge All Heavies", "Dodge All Heavies",
			function() return Config.DodgeHeavy end, function(v) Config.DodgeHeavy = v end)
		apDodge:SubLabel({ Text = "when block is unavailable and a heavy (M2) is coming:\ndodge it instead of eating the hit\n(unblockable grabs always dodged via Must-Dodge)" })
		boolToggle(apDodge, "Dodge If Cant Parry", "Dodge If Cant Parry",
			function() return Config.DodgeOnParryCooldown ~= false end,
			function(v) Config.DodgeOnParryCooldown = v end)
		apDodge:SubLabel({ Text = "dodge when block is on cooldown / cant parry in time\nOFF = eat the hit instead (unblockable must-dodge unaffected)" })
		boolToggle(apDodge, "Smart Dodge Direction", "Smart Dodge", function() return Config.SmartDodgeDir end, function(v) Config.SmartDodgeDir = v end)
		apDodge:SubLabel({ Text = "roll away from the attacker instead of a fixed direction" })
		boolToggle(apDodge, "Face-Gate Block", "Face-Gate Block",
			function() return Config.FaceGateBlock ~= false end, function(v) Config.FaceGateBlock = v end)
		apDodge:SubLabel({ Text = "dont waste a block (and its 0.5s cooldown) pressing while facing away\nwait for the turn — block is directional, the server rejects back-facing parries" })

		apDodge:Divider()
		apDodge:Header({ Name = "Dodge Tuning" })
		slider(apDodge, { Name = "Dodge Reaction (lead)", Flag = "AP_DodgeLead",
			Default = math.floor((Config.DodgeLead or 0.10) * 1000), Min = 40, Max = 300,
			Suffix = " ms", Callback = function(v) Config.DodgeLead = v / 1000 end })
		apDodge:SubLabel({ Text = "how early to start the roll before impact" })
		slider(apDodge, { Name = "Dodge Speed", Flag = "AP_DashSpeed", Default = Config.DashSpeed or 30,
			Min = 10, Max = 90, Suffix = " st/s", Callback = function(v) Config.DashSpeed = v end })
		slider(apDodge, { Name = "i-Frame Window", Flag = "AP_IFrame",
			Default = math.floor((Config.IFrameDur or 0.30) * 1000), Min = 120, Max = 500,
			Suffix = " ms", Callback = function(v) Config.IFrameDur = v / 1000 end })

		apDodge:Divider()
		apDodge:Header({ Name = "Must-Dodge List" })
		do
			local STYLES = {
				"Default","Basic","Boxing","Bulky","Dirty","Hakari","Karate","Kure",
				"MuayThai","SkyGaoLang","Variant","Taekwondo","Wild","WingChun",
				"Wrestling","Capoeira","Slugger","Striker",
			}
			local KINDS = { { label = "M1", key = "M1" }, { label = "M2 (Heavy)", key = "M2" } }
			local mdOptions, mdDefault = {}, {}
			for _, s in ipairs(STYLES) do
				local saved = Config.MustDodgeStyles and Config.MustDodgeStyles[s:lower()]
				for _, k in ipairs(KINDS) do
					local opt = s .. " / " .. k.label
					mdOptions[#mdOptions + 1] = opt
					if saved and (saved[k.key] or saved.all) then
						mdDefault[#mdDefault + 1] = opt
					end
				end
			end
			apDodge:Dropdown({
				Name = "Must-Dodge Attacks", Options = mdOptions, Multi = true, Search = true,
				Default = mdDefault,
				Callback = function(sel)
					local t, n = {}, 0
					for label, on in pairs(sel) do
						if on then
							local st, kindLabel = label:match("^(.-) / (.+)$")
							if st and kindLabel then
								local key = (kindLabel == "M1" and "M1")
									or (kindLabel == "M2 (Heavy)" and "M2")
								if key then
									st = st:lower()
									t[st] = t[st] or {}
									t[st][key] = true
									n += 1
								end
							end
						end
					end
					Config.MustDodgeStyles = t
					notify("Must-Dodge", "Selected: " .. n .. " attack(s)")
				end,
			}, ctx.flag("AP_MustDodge"))
			apDodge:SubLabel({ Text = "roll into i-frames on these instead of blocking\npick M1 or M2 per style" })
		end

		local apBox = AP:Section({ Side = "Left" })

		apBox:Header({ Name = "Skill Addons" })
		feature(apBox, {
			Title = "Skill Addons", Flag = "AP_SkillAddon",
			get = function() return Config.SkillAddon end,
			set = function(v) Config.SkillAddon = v end,
			Desc = "master switch for the per-style stuff below",
		})

		apBox:Divider()
		apBox:Header({ Name = "Boxing" })
		boolToggle(apBox, "Boxing Counter", "Boxing Counter",
			function() return Config.BoxingCounter end, function(v) Config.BoxingCounter = v end)
		apBox:SubLabel({ Text = "boxing style only\nenemy attacks in range → INSTANTLY throw ur own M2 instead of parrying" })
		slider(apBox, { Name = "Counter Range", Flag = "AP_CounterReach",
			Default = Config.BoxingCounterReach or 5.5,
			Min = 3, Max = 12, Precision = 1, Suffix = " studs",
			Callback = function(v) Config.BoxingCounterReach = v end })
		apBox:SubLabel({ Text = "max distance to the attacker to fire the instant counter M2" })

		apBox:Divider()
		apBox:Header({ Name = "Ali" })
		boolToggle(apBox, "Ali Counter", "Ali Counter",
			function() return Config.AliCounter end, function(v) Config.AliCounter = v end)
		slider(apBox, { Name = "Ali Counter Range", Flag = "AP_AliCounterReach",
			Default = Config.AliCounterReach or 7.5,
			Min = 3, Max = 14, Precision = 1, Suffix = " studs",
			Callback = function(v) Config.AliCounterReach = v end })
		boolToggle(apBox, "Ali Evasive Counter", "Ali Evasive Counter",
			function() return Config.AliEvasiveCounter end, function(v) Config.AliEvasiveCounter = v end)
		boolToggle(apBox, "Ali Dodge Abuse", "Ali Dodge Abuse",
			function() return Config.AliDodgeAbuse end, function(v) Config.AliDodgeAbuse = v end)
		slider(apBox, { Name = "Ali Rotation Hold", Flag = "AP_AliFaceLockDur",
			Default = math.floor((Config.AliFaceLockDur or 0.75) * 1000),
			Min = 200, Max = 1400, Suffix = " ms",
			Callback = function(v) Config.AliFaceLockDur = v / 1000 end })
		apBox:SubLabel({ Text = "Dodge Abuse only fires M2 after server-confirmed perfect dodge\nBoxing M2 stays parry-only" })
		apBox:Dropdown({
			Name = "Ali M2 Variant",
			Options = { "Right", "Left" },
			Default = Config.AliM2Variant or "Left",
			Callback = function(v)
				if type(v) == "string" and v ~= "" then Config.AliM2Variant = v end
			end,
		}, ctx.flag("AP_AliM2Variant"))

		apBox:Divider()
		apBox:Header({ Name = "Counter" })
		boolToggle(apBox, "Counter Instead Of Dodge", "Counter Instead Of Dodge",
			function() return Config.CounterPreemptsDodge ~= false end,
			function(v) Config.CounterPreemptsDodge = v end)
		apBox:SubLabel({ Text = "dont burn a dodge when the counter M2 already covers u\nunblockable grabs still always dodge" })

		apBox:Divider()
		apBox:Header({ Name = "Anti-Grab" })
		boolToggle(apBox, "Wrestling Anti-Grab", "Wrestling Anti-Grab",
			function() return Config.SA_WrestlingGrab end, function(v) Config.SA_WrestlingGrab = v end)
		apBox:SubLabel({ Text = "wrestling M2 is an unblockable grab\nalways roll it" })
		boolToggle(apBox, "Dirty Anti-Grab", "Dirty Anti-Grab",
			function() return Config.SA_DirtyGrab end, function(v) Config.SA_DirtyGrab = v end)
		apBox:SubLabel({ Text = "dirty grab ignores immunity n eats blocks\nroll it instead" })
		boolToggle(apBox, "Hakari Double Read", "Hakari Double Read",
			function() return Config.SA_HakariRead end, function(v) Config.SA_HakariRead = v end)
		apBox:SubLabel({ Text = "hakari momentum M2 hits late\nwidens the window to match" })

		apBox:Divider()
		apBox:Header({ Name = "Force-Dodge (client)" })
		boolToggle(apBox, "Blatant Force-Dodge", "Blatant Force-Dodge",
			function() return Config.SA_BlatantDodge end, function(v) Config.SA_BlatantDodge = v end)
		apBox:SubLabel({ Text = "dodges even when the game wont let u (client sided, obvious)" })
		slider(apBox, { Name = "Force-Dodge Window", Flag = "AP_SABlatantWin",
			Default = math.floor((Config.SA_BlatantWindow or 0.32) * 1000), Min = 150, Max = 500, Suffix = " ms",
			Callback = function(v) Config.SA_BlatantWindow = v / 1000 end })

		local apPlay = AP:Section({ Side = "Left" })

		apPlay:Header({ Name = "AutoPlay" })
		feature(apPlay, {
			Title = "AutoPlay", Flag = "AP_AutoPlay",
			get = function() return Config.AutoPlay end,
			set = function(v) Config.AutoPlay = v end,
			Desc = "aggressive addon: auto-M1 a stunned enemy after ur perfect parry\nmaster switch for the stuff below",
		})

		apPlay:Divider()
		apPlay:Header({ Name = "Behaviour" })
		boolToggle(apPlay, "Punish After Parry", "Punish After Parry",
			function() return Config.AP_PunishOnParry ~= false end, function(v) Config.AP_PunishOnParry = v end)
	apPlay:SubLabel({ Text = "a perfect parry stuns them → instantly auto-M1 the stunned enemy in range" })
	boolToggle(apPlay, "Smooth Swings", "Smooth Swings",
		function() return Config.AP_AnimGuard ~= false end,
		function(v) Config.AP_AnimGuard = v end)
	apPlay:SubLabel({ Text = "stops the swing anim restarting mid-play when the server desyncs" })
	boolToggle(apPlay, "Counter Interrupt", "Counter Interrupt",
		function() return Config.AP_Interrupt ~= false end, function(v) Config.AP_Interrupt = v end)
	apPlay:SubLabel({ Text = "if ur next hit lands first and enemy is in reach → hit now instead of parrying" })
	boolToggle(apPlay, "Interrupt With M2", "Interrupt With M2",
		function() return Config.AP_InterruptM2 ~= false end, function(v) Config.AP_InterruptM2 = v end)
	apPlay:SubLabel({ Text = "also check ur M2, not just M1\nM2 hits way harder n knocks the whole combo off" })
	boolToggle(apPlay, "Prefer M2", "Prefer M2",
		function() return Config.AP_InterruptPreferM2 ~= false end, function(v) Config.AP_InterruptPreferM2 = v end)
	apPlay:SubLabel({ Text = "both in time → take M2\noff = take whichever lands earlier" })
	slider(apPlay, { Name = "Interrupt M2 Range", Flag = "AP_M2BaseReach",
		Default = Config.AP_M2BaseReach or 6.5,
		Min = 3, Max = 14, Precision = 1, Suffix = " studs",
		Callback = function(v) Config.AP_M2BaseReach = v end })
	apPlay:SubLabel({ Text = "M2 reach (scaled by style n height)" })

	apPlay:Divider()
			apPlay:Header({ Name = "Combo" })
			apPlay:Dropdown({
				Name = "Combo Mode",
				Options = { "Follow", "Fixed" },
				Default = Config.AP_ComboMode or "Follow",
				Callback = function(v)
					Config.AP_ComboMode = v
					notify("Combo Mode", "Selected: " .. tostring(v))
				end,
			}, ctx.flag("AP_ComboMode"))
			apPlay:SubLabel({ Text = "Follow = natural combo 1→2→3→4→1.  Fixed = always throw one chosen hit" })
			slider(apPlay, { Name = "Fixed Combo Hit", Flag = "AP_FixedHit", Default = Config.AP_FixedHit or 1,
				Min = 1, Max = 4, Callback = function(v) Config.AP_FixedHit = v end })
			apPlay:SubLabel({ Text = "which hit of the 4-move combo to throw (only used in Fixed mode)" })
			apPlay:Button({
				Name = "Test Swing",
				Callback = function()
					local combo, ok = State.ap.testSwing()
					if ok then
						notify("Test Swing", "sent M1 hit #" .. tostring(combo)
							.. (Config.AP_ComboMode == "Fixed" and " (Fixed)" or " (next in combo)"))
					else
						notify("Test Swing", "could not swing (equip weapon / rate-limited / M1 not resolved)")
					end
				end,
			})
			apPlay:SubLabel({ Text = "fires one M1 right now with the combo animation the script would use (Fixed hit, or next in sequence)" })

		apPlay:Divider()
			apPlay:Header({ Name = "Tuning" })
			slider(apPlay, { Name = "M1 Rate", Flag = "AP_MaxPerSec", Default = Config.AP_MaxPerSec or 6,
				Min = 3, Max = 8, Suffix = " /s", Callback = function(v) Config.AP_MaxPerSec = v end })
			apPlay:SubLabel({ Text = "swings per second, spread evenly (fills the whole stun window)\n6 = safe server ceiling; 7-8 hits harder but is more detectable" })
			slider(apPlay, { Name = "M1 Reach", Flag = "AP_BaseReach", Default = Config.AP_BaseReach or 5.5,
				Min = 3, Max = 10, Precision = 1, Suffix = " st", Callback = function(v) Config.AP_BaseReach = v end })
	apPlay:SubLabel({ Text = "scaled by ur character height automatically" })

		local apVis = AP:Section({ Side = "Right" })

		apVis:Header({ Name = "Visuals" })
		feature(apVis, {
			Title = "Visuals", Flag = "AP_ShowVisuals",
			get = function() return Config.ShowVisuals end,
			set = function(v)
				Config.ShowVisuals = v
				if not v then pcall(vizHideAll) end
			end,
			Desc = "master switch for all AutoParry visuals",
		})

		apVis:Divider()
		apVis:Header({ Name = "What To Draw" })
		boolToggle(apVis, "Target Ring", "Target Ring",
			function() return Config.VizRing end,
			function(v) Config.VizRing = v; if not v then pcall(vizHideAll) end end)
		boolToggle(apVis, "Attack Cone", "Attack Cone",
			function() return Config.VizHitbox end,
			function(v) Config.VizHitbox = v; if not v then pcall(vizHideAll) end end)
		apVis:SubLabel({ Text = "their reach — green = ur safe, red = ur in it" })
		boolToggle(apVis, "Keep-Out Zone", "Keep-Out Zone",
			function() return Config.VizRestrict end,
			function(v) Config.VizRestrict = v; if not v then pcall(vizHideAll) end end)

		apVis:Divider()
		apVis:Header({ Name = "Ring" })
		local ringOrbitEls, ringSwirlEls = {}, {}
		local function ringVis()
			local st = Config.VizRingStyle or "Flat"
			local isOrbit = (st == "Orbit" or st == "OrbitSwirl")
			for _, el in ipairs(ringOrbitEls) do pcall(function() el:SetVisibility(isOrbit) end) end
			for _, el in ipairs(ringSwirlEls) do pcall(function() el:SetVisibility(st == "OrbitSwirl") end) end
		end
		apVis:Dropdown({
			Name = "Style",
			Options = { "Flat", "Orbit", "OrbitSwirl" },
			Default = Config.VizRingStyle or "Flat",
			Callback = function(v)
				if type(v) == "string" and v ~= "" then Config.VizRingStyle = v; ringVis() end
			end,
		}, ctx.flag("AP_VizRingStyle"))
		apVis:SubLabel({ Text = "Flat = line ring at their feet\nOrbit = filled 3d ribbon · OrbitSwirl = same ribbon, spinning" })
		slider(apVis, { Name = "Size", Flag = "AP_VizRingScale",
			Default = math.floor((Config.VizRingScale or 1) * 100), Min = 40, Max = 250, Suffix = "%",
			Callback = function(v) Config.VizRingScale = v / 100 end })
		slider(apVis, { Name = "Speed", Flag = "AP_VizRingSpeed",
			Default = math.floor((Config.VizRingSpeed or 1) * 100), Min = 10, Max = 300, Suffix = "%",
			Callback = function(v) Config.VizRingSpeed = v / 100 end })
		slider(apVis, { Name = "Smoothness", Flag = "AP_VizRingSeg",
			Default = Config.VizRingSeg or 30, Min = 8, Max = 48, Suffix = "",
			Callback = function(v) Config.VizRingSeg = v end })
		ringOrbitEls[#ringOrbitEls + 1] = slider(apVis, { Name = "Depth", Flag = "AP_VizRingTilt",
			Default = math.floor((Config.VizRingTilt or 0.7) * 100), Min = 10, Max = 200, Suffix = "%",
			Callback = function(v) Config.VizRingTilt = v / 100 end })
		ringOrbitEls[#ringOrbitEls + 1] = boolToggle(apVis, "Mirror Band", "Ring Mirror",
			function() return Config.VizRingMirror ~= false end,
			function(v) Config.VizRingMirror = v end)
		ringVis()
		apVis:Colorpicker({ Name = "Color A", Default = Config.RingA,
			Callback = function(c) Config.RingA = c end }, ctx.flag("AP_RingA"))
		apVis:Colorpicker({ Name = "Color B", Default = Config.RingB,
			Callback = function(c) Config.RingB = c end }, ctx.flag("AP_RingB"))

		apVis:Divider()
		apVis:Header({ Name = "Cone & Zone Colors" })
		apVis:Colorpicker({ Name = "Cone (safe)", Default = Config.ConeSafe,
			Callback = function(c) Config.ConeSafe = c end }, ctx.flag("AP_ConeSafe"))
		apVis:Colorpicker({ Name = "Cone (in range)", Default = Config.ConeHit,
			Callback = function(c) Config.ConeHit = c end }, ctx.flag("AP_ConeHit"))
		apVis:Colorpicker({ Name = "Keep-Out", Default = Config.RestrictCol,
			Callback = function(c) Config.RestrictCol = c end }, ctx.flag("AP_Restrict"))

		apVis:Divider()
		apVis:Header({ Name = "Performance" })
		slider(apVis, { Name = "Draw Distance", Flag = "AP_VizRange",
			Default = Config.VizRange or 100, Min = 20, Max = 250, Suffix = " st",
			Callback = function(v) Config.VizRange = v end })
		slider(apVis, { Name = "Redraw Cap", Flag = "AP_VizMaxFPS",
			Default = Config.VizMaxFPS or 60, Min = 15, Max = 240, Suffix = " fps",
			Callback = function(v) Config.VizMaxFPS = v end })
		apVis:SubLabel({ Text = "how often the overlay redraws, not ur game fps. lower = more headroom" })

		local DS = ctx.tabs.Desync

		local dsSelf = DS:Section({ Side = "Left" })
		dsSelf:Header({ Name = "Anti AutoParry" })
		feature(dsSelf, {
			Title = "Anti AutoParry", Flag = "DS_Test",
			get = function() return DesyncTest.on end,
			set = function(v)
				if (DesyncTest.on and true or false) ~= v then pcall(toggleDesyncTest) end
			end,
			Desc = "fakes a swing while u move\nenemy autoparry bites on nothing",
		})
		slider(dsSelf, { Name = "Send Frequency", Flag = "DS_SendHz", Default = Config.DesyncSendHz or 0,
			Min = 0, Max = 20, Suffix = " Hz", Callback = function(v) Config.DesyncSendHz = v end })
		dsSelf:SubLabel({ Text = "decoy re-sends per second\n0 = auto" })
		boolToggle(dsSelf, "Client Visible", "Desync Client Visible",
			function() return Config.DesyncClientVisible end,
			function(v) Config.DesyncClientVisible = v end)

		local dsAtk = DS:Section({ Side = "Right" })
		dsAtk:Header({ Name = "Attack Desync" })
		feature(dsAtk, {
			Title = "Attack Desync", Flag = "DS_Attack",
			get = function() return Config.DesyncAttack end,
			set = function(v) Config.DesyncAttack = v end,
			Desc = "desyncs ur swings so enemies mistime the parry",
		})
		dsAtk:Dropdown({
			Name = "Desync Mode", 			Options = { "delay", "firedelay", "idlemask", "prerun" },
			Default = Config.DesyncMode or "delay",
			Callback = function(v)
				Config.DesyncMode = v
				pcall(function() if DZ and DZ.applyDesyncMode then DZ.applyDesyncMode() end end)
				notify("Desync Mode", "Selected: " .. tostring(v))
			end,
		}, ctx.flag("DS_Mode"))
		dsAtk:SubLabel({ Text = "not working shit  but i will fix it later ok?" })
		slider(dsAtk, { Name = "Desync Delay", Flag = "DS_Delay", Default = Config.DesyncDelayMs or 140,
			Min = 40, Max = 400, Suffix = " ms", Callback = function(v) Config.DesyncDelayMs = v end })
		boolToggle(dsAtk, "Apply to M1", "Desync M1", function() return Config.DesyncApplyM1 end, function(v) Config.DesyncApplyM1 = v end)
		boolToggle(dsAtk, "Apply to M2", "Desync M2", function() return Config.DesyncApplyM2 end, function(v) Config.DesyncApplyM2 = v end)

		local dsInv = DS:Section({ Side = "Left" })
		dsInv:Header({ Name = "Invisible" })
		feature(dsInv, {
			Title = "Invisible", Flag = "DS_Invisible",
			get = function() return Config.InvisibleOn end,
			set = function(v) pcall(function() IV.setInvisible(v) end) end,
			Desc = "drops ur body underground for everyone else\nu still look normal to urself",
		})
		slider(dsInv, { Name = "Invisible Height", Flag = "DS_InvHeight", Default = Config.InvisibleHeight or 0,
			Min = 0, Max = 15, Suffix = " studs", Callback = function(v) Config.InvisibleHeight = v end })
		dsInv:SubLabel({ Text = "extra studs\n2-3 is good" })
		boolToggle(dsInv, "Contort Anim", "Invisible Anim",
			function() return Config.InvisibleAnim end, function(v) Config.InvisibleAnim = v end)

		local DB = ctx.tabs.Debug

		local dbLog = DB:Section({ Side = "Left" })
		dbLog:Header({ Name = "Status Log" })
		local statusPara = dbLog:Paragraph({ Header = "Live events", Body = "—" })
		local function renderStatus()
			local n = #StatusLog
			if n == 0 then statusPara:UpdateBody("No events yet."); return end
			local shown = math.min(16, n)
			local out = { ("Showing %d of %d (newest first):"):format(shown, n), "" }
			for i = n, n - shown + 1, -1 do
				out[#out + 1] = "• " .. tostring(StatusLog[i])
			end
			statusPara:UpdateBody(table.concat(out, "\n"))
		end
		renderStatus()
		dbLog:Button({ Name = "Refresh", Callback = renderStatus })
		dbLog:Button({ Name = "Clear", Callback = function()
			table.clear(StatusLog); statusPara:UpdateBody("No events yet.")
		end })
		task.spawn(function()
			while statusPara do
				task.wait(1.5)
				pcall(renderStatus)
			end
		end)

		local dbDiag = DB:Section({ Side = "Right" })
		dbDiag:Header({ Name = "Diagnostics" })
		local copyDiag = false
		dbDiag:Button({
			Name = "Save AutoParry diag",
			Callback = function()
				local body  = summary() .. "\n\n" .. table.concat(DiagLog, "\n") .. "\n"
				local fname = ("autoparry_diag_%d.txt"):format(os.time() % 1000000)
				local wrote = pcall(function() if writefile then writefile(fname, body) end end) and (writefile ~= nil)
				if copyDiag and type(setclipboard) == "function" then
					pcall(setclipboard, body)
				end
				if wrote then
					notify("Diagnostics", (copyDiag and "Saved + copied: " or "Saved: ") .. fname)
				elseif copyDiag and type(setclipboard) == "function" then
					notify("Diagnostics", "writefile unavailable — copied log to clipboard")
				else
					notify("Diagnostics", "writefile/clipboard unavailable")
				end
			end,
		})
		boolToggle(dbDiag, "Copy", "Diag Copy",
			function() return copyDiag end,
			function(v) copyDiag = v end)

		task.defer(function() uiReady = true end)
	end

	return M
end
