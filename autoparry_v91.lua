-- ИЗМЕНЕНО: 2026-08-04 UTC | AutoParry V144 | perf: devirtualize hot paths, kill per-frame garbage
-- Версия для логов живёт в Config.Version (строка ~22) — правь ТАМ, шапка тут только для людей.
-- AutoParry (Potassium) — combat autoparry / desync / boxing-counter
-- Luraph macros: string-key PRELUDE only. Bare `function LPH_*` / `if not LPH_OBFUSCATED`
-- aborts or miscompiles Luraph and leaves hot paths virtualized (50-200x slower → freeze).
-- Hot path: scheduler, combat Heartbeat/RenderStepped, __namecall, desync CFrame loops.
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
	-- [V140] ЕДИНСТВЕННЫЙ ИСТОЧНИК ВЕРСИИ. Раньше строка версии была захардкожена в шапке диага
	-- ("===== AUTOPARRY V74 DIAG ====="), её никто не обновлял, и КАЖДЫЙ лог приходил помеченным
	-- V74 независимо от реальной версии кода. Это не косметика: по такому логу невозможно
	-- понять, воспроизведён баг до или после правки, и я сам на этом ошибся — принял свежий
	-- лог за старый. Держим версию в Config и подставляем в диаг, чтобы расхождение было
	-- невозможно физически.
	Version       = "V150",
	Enabled       = false,  -- [module] start OFF; user flips the "Enabled" toggle/keybind in the UI
	Mode          = "Perfect",

	Range         = 36,    -- [V105] +4 (юзер: враг выходит за радиус и заходит → миссим; чуть шире)
	RequireFacing = false,
	IncludeNPCs   = true,
	HeavyEnabled  = true,

	-- Recognition geometry. The game creates a forward-oriented M1/M2 BasePart; cached
	-- live dimensions replace these fallbacks after the first observed real part.
	M1Forward     = 4,
	M2Forward     = 3,
	HitboxDepth   = 4.0,
	HitboxDepthBack = 1.0, -- geometric rear half-extent for fallback / target-hitbox visual
	HitHalfWidth  = 3.0,
	HitboxSlack   = 0.5,   -- Low: small current-position tolerance
	HighSlack     = 0.35,  -- High: small predicted-position tolerance
	HighReachPad  = 2.0,   -- [V137] High wide-recognition reach padding beyond forward+halfD
	HighFaceFloor = -0.15, -- [V137] High facing gate: attacker look·toMe must be >= this (excludes back-facing)
	-- ═══════════ [V160] ЭКСТРАПОЛЯЦИЯ РОТАЦИИ АТАКУЮЩЕГО — КОРНЕВОЙ ФИКС ═══════════
	-- Диаг V150 доказал арифметически: экстраполяция разворачивала look врага НА 180°.
	--   t=4475.702 TRACE-GEOM  look=(-0.88,0.48)  A=(158.6,158.3)  M=(154.9,162.2)
	--     → toMe = M-A = (-3.7,3.9), |toMe|=5.38, unit=(-0.688,0.725)
	--     → faceToMe = (-0.88)(-0.688) + (0.48)(0.725) = +0.95   ← смотрит НА НАС
	--   t=4475.718 GEOM-REJECT faceToMe=-0.92 BACK-FACING dist2d=5.00 reach=9.00 reach-ok
	-- За 16мс знак перевернулся: враг в 5 студах, в рече, реально бьёт M2 — а гейт видит спину.
	-- В строке 20 диага faceToMe=-1.00 РОВНО — подпись клампа до π.
	-- ПРИЧИНА ДВОЙНАЯ:
	--   1) attackerYawRate считал градусы/сек по ОДНОМУ кадру без сглаживания. Рывок мышью
	--      на 10° за кадр (60 FPS) = 600°/с, хотя враг никуда не «вращается».
	--   2) кап поворота стоял ±π, т.е. экстраполяции РАЗРЕШАЛОСЬ развернуть врага спиной.
	--      При tHit=0.6 (M2) для полного разворота хватало 300°/с.
	-- ПОСЛЕДСТВИЕ: willHitMe=false → threatens=false → всё press-окно (строка ~5609
	-- `if threatens then`) пропускается на этих кадрах → нажатие уходит только после
	-- спасения geom-sticky, то есть LATE (в диаге pressDt=33..50мс, lateBy=+147..200мс).
	-- Именно это, а не модель предикта (resAvg≈0 — модель точна), давало 13 timing-промахов.
	-- [V161] Доля дистанции до нас, дальше которой предсказанная позиция атакующего не уезжает.
	-- Раньше по вектору ограничения не было вовсе: кламп сидел только на осевой компоненте, а
	-- боковая (WillHitLatCap=1.5) прибавлялась ПОСЛЕ него. В упор это проносило predA сквозь нас,
	-- инвертировало вектор «атакующий→я» и давало BACK-FACING на реальном ударе с 1.6 студа.
	WillHitLeadFrac = 0.90,
	YawRateSmooth  = 0.30,  -- EMA-коэф. сглаживания измеренной угловой скорости (0 = не сглаживать)
	YawTurnCapDeg  = 30,    -- макс. доворот, который экстраполяции разрешено предсказать (град)
	YawWidenOnly   = true,  -- экстраполяция может ТОЛЬКО расширять распознавание, не сужать
	FilterFailSafe= true,

	-- [V140] Low removed: DIAG 574090/556482 proved strict box rejected real hits (8.5% acc).
	-- High (WIDE recognition) is the only working mode; exact overlap still used when live.
	AccuracyMode  = "High",

	-- Prediction caps used only to project an oriented box; they never make a threat true.
	WillHitVelCap   = 2.0,
	WillHitCloseCap = 12,
	WillHitLatCap   = 1.5,

	FeintFrac     = 0.80,
	FeintGraceMs  = 90,

	ComboEscape        = true,
	ComboEscapeDodge   = true,
	-- [V97] Мастер-тумблер доджа «когда parry невозможен» (блок в кул��ауне/стан). OFF = скрипт
	-- НЕ уходит доджем в такие моменты (юзер: иногда лучше съесть удар, чем палить додж). НЕ влияет
	-- на must-dodge (неблокируемые атаки — их всё равно нельзя блокнуть) и guardbreak-save.
	DodgeOnParryCooldown = true,
	StunReleaseLead    = 0.14,
	GuardbreakProtect  = true,
	StaminaFloor       = 18,
	StaminaAttrs       = { "Stamina", "BlockStamina", "GuardStamina", "Posture", "Guard" },

	PerfectWindow = 0.15,
	PerfectMin    = 0.05,
	-- [V93] ЦЕНТР перфект-окна, НЕ полное окно. Раньше 0.125 (всё окно) СКЛАДЫВАЛОСЬ с уплин��ом
	-- → ��войной учёт задержки. Физика: локальный атрибут PerfectBlocking истинен на нашем клиенте
	-- в интервале [T+RTT, T+RTT+0.125] (T = момент нажатия). Контакт C должен попасть в него;
	-- при press = C - RTT - lead любой lead∈[0,0.125] даёт перфект, центр 0.0625 максимизирует
	-- запас по джиттеру с обеих сторон (см. UplinkFactor — теперь компенсируем ПОЛНЫЙ RTT).
	PerfectLead   = 0.0625,
	HoldAfter     = 0.12,
	HoldLateGrace = 0.14,

	-- [V64] PER-HIT RE-ARM. Дамп (Block_ModuleScript.Block): PerfectBlocking
	-- взводится ТОЛЬКО при свежем Block/Activated; пока Blocking=true, повторный
	-- вызов — no-op и перфект НЕ перевзводится. Прошлые версии после перфекта c1
	-- держали guard (State.blocking=true), и каждый следующий удар комбо c2..c4
	-- уходил в held-ветку без свежего Activated → NO-PRESS/LATE (в логе 647387
	-- ровно это: c1/c2 fresh=PERFECT, c3/c4 held=HIT). V64 шлёт свежий Activated
	-- на КАЖ������ЫЙ удар в его перфект-окне, даже если уже блокируем.
	PerHitRearm   = true,
	-- [V64] жёсткий доворот на атакующего у самого контакта. В логе часть LATE шла
	-- при face=0.27 BACK! / 0.66 — блок вовремя, но лицом не туда, сервер не
	-- засчитывал. Плавный лерп (FaceLerp) не успевал против стрейфа. Ниже дистанции
	-- по времени до контакта ��� прямой снап лицом на цель блока.
	BlockFaceHard   = true,
	BlockFaceHardDt = 0.30,   -- [V70] снап раньше → успеваем при ������ыстром чередовании

	M2WidenWindow = false,
	M2WidenFront  = 0.22,
	M2WidenHold   = 0.10,

	-- [V74] HITBOX-DRIVEN DODGE: fire dodge when the actual server hitbox appears,
	-- instead of relying only on the predicted animation timeline. This fixes M2/Boxing
	-- and other delayed hitboxes where predicted contact is far from real hit.
	HitboxDodge     = true,

	-- (V115) удалены — калибрация отравляла между врагами (обучалась на одном, ломала второго).
	-- Предикт чисто математический: таймлайн анимации + живой TimePosition.
	ChargeStallMs = 45,
	ReleaseGap    = 0.40,

	-- [V103] FACE-GATE BLOCK: не жечь нажатие блока (и 0.5с BlockCooldown), пока смотрим спиной к
	-- атакующему — блок направленный, се��вер такой парри отклонит. Ждём доворота (applyFacing),
	-- пр��с��им при приемлемом facing ИЛИ когда времени уже не�� (последний шанс). Дефолт ON.
	FaceGateBlock = true,
	FaceGateMin   = 0.2,       -- мин. faceDot (cos) до а��аку��щего, при котором разрешаем нажатие

	-- [V93] ПОЛНЫЙ round-trip. Локальный атрибут PerfectBlocking СЕРВЕРНЫЙ: после нашего нажатия
	-- он проходит нажатие→сервер (RTT/2) и реплик. атрибута назад (RTT/2) = ПОЛНЫЙ RTT, и лишь
	-- т������гда становится true на нашем клиенте. VictimHitConfirm (дамп VictimHitboxServiceClient)
	-- читает ИМЕННО этот локальный атрибут в момент оверлапа хитбокса → чтобы к контакту он был
	-- true, жать надо на полный RTT раньше. Прежний 0.5 (полу-RTT) недокомпенсировал ровно на
	-- пол-пинга → на 195мс пинге блок стабильно опаздывал (диаг: PERFECT@~185мс vs LATE@~95мс,
	-- разрыв ≈ полу-RTT).
	UplinkFactor  = 1.0,
	UplinkMargin  = 0.008,
	UplinkMin     = 0.010,
	-- [V127] LOW-PING LEAD FLOOR. Жалоба: у игрока с НИЗК���� пингом (52–71мс в диаге) парри
	-- опаздывают, хотя resAvg≈0 (модель точна) — блок стабильно садится на true+116..160мс, на
	-- поздней кромке 125мс окна. Причина: помимо RTT есть ФИКСИРОВАННАЯ, не зависящая от пинга
	-- задержка клиентского конвейера (очередь ввода + 1 кадр Heartbeat + применение анимации/
	-- атрибута PerfectBlocking) ≈ LowPingFloor. uplink = ping*Factor+Margin её НЕ моделирует:
	-- на СРЕДНЕМ/ВЫСОКОМ пинге (у автора, 90–150) большой uplink её случайно перекрывает, а на
	-- низком uplink мал → суммарный lead недобирает → LATE. Фикс: добавляем к uplink компенсацию,
	-- которая ПОЛНАЯ при ping→0 и линейно гаснет к нулю на LowPingThresh (при среднем/высоком
	-- пинге = 0 → рабочий сетап автора НЕ трогаем).
	LowPingFloor   = 0.030,   -- макс. добавка к lead при ping→0 (сек)
	LowPingThresh  = 0.090,   -- пинг (сек), выше которого ��обавка = 0
	-- [V94] Подняты капы: диаг2 показал реальный RTT=345ms, а прежние UplinkMax=0.33/PingCap=0.32
	-- САМИ резали компенсацию до ~330ms → на высоком пинге блок недокомпенсировался даже с верным
	-- getPingRaw. Теперь тянем до 0.5с. На умеренном пинге (60–150) это ни на что не влияет (там
	-- клампы не достигаются), а на 300–450ms пинге даёт полный round-trip lead.
	UplinkMax     = 0.500,
	PingCap       = 0.500,
	-- [V161] Во сколько раз GetNetworkPing() может превышать Stats Data Ping, прежде чем считаться
	-- неисправным. В диаге 10810 расхождение было 5-8× (0.75+ против 0.09-0.27), и слепой max по
	-- источникам загонял rawRTT в потолок 1.5с, а за ним medRTT=500 и uplink=500.
	PingSourceMaxRatio = 2.5,
	-- [V116] РОБАСТНЫЙ МЕДИАННЫЙ ПИНГ (замена EMA+peak-hold). Peak-hold ЛАТЧИЛ случайный спайк
	-- (в логе header ping=224 при combat-ping=158) → uplink раздувался → жали СЛИШКОМ РАНО. ��едиана
	-- окна последних сэмплов игнорирует одиночные выбросы (и вверх, и вниз) и отслеживает ИСТИННЫЙ
	-- устойчивый RTT: один спайк-кадр среди 24 сэмплов не сдвигает медиану вообще, а реально
	-- выросший пинг п���днимает её за <1с. Никакого залипания, никакой петли обучения.
	PingWindow    = 24,     -- размер кольца сэмплов (24 × PingSampleGap ≈ 0.72с окна)
	PingSampleGap = 0.03,   -- как часто класть новый сырой сэмпл (сек) — не чаще ~раза в 2 кадра

	MoveLeadMax   = 0.045,
	MoveSpeedFull = 22,

	MaxWait       = 1.6,

	-- [V91.1] Block throttle. The 0.06 "ServerMinInterval" in CombatRemoteLimits is DATA ONLY —
	-- nothing on the client reads it, and Block doesn't even go through CombatRemoteClient.Fire
	-- (Block fires Remotes.Server directly), so the client throttle is ours alone. Dropped to a
	-- token 4ms just to kill exact-same-frame double sends; no reason to sit on a parry for 30ms.
	MinActGap     = 0.004,
	MinDeactGap   = 0.050,

	MatchWindow   = 1.30,
	-- [V125] окно, в котором ВТОРОЙ (и далее) серверный OUT того же типа от того же врага
	-- считается доп-ударом ОДНОГО мультихит-свинга (Boxing M2MultiHitCount=2 шлёт 2 события
	-- Hit/Blocked на одну анимацию), а НЕ новой атакой. В логе 2-й страйк приходил +0.44..1.20с
	-- после свинга → берём с запасом = MatchWindow.
	MultiHitWindow = 1.30,

	-- [V120] МАСТЕР-ТУМБЛЕР ДОДЖА. Раньше было 7 независимых додж-триггеров (iframe-cluster,
	-- must-dodge, blatant, outnumbered/combo/exposed-escape, heavy), каждый со СВОИМ саб-тумблером,
	-- но БЕЗ единого выключателя — все дефолтом ON. Отсюда «до��жит с нихуя»: юзер гасил один флаг,
	-- а остальные продолжали. Теперь ВСЕ доджи проходят через performDodge → один гейт AutoDodge.
	-- false = скрипт НЕ доджит НИКОГДА (даже must-dodge/грэбы), только блок/перфект. Дефолт ON.
	AutoDodge     = true,
	DodgeHeavy    = true,
	FOV           = 360,   -- screen-space angular FOV; 360 preserves current omnidirectional behavior

	-- [V89] MUST-DODGE (неблокируемые). В дампе нет флага Unblockable — всё в теории
	-- блокируется, поэтому список собираем производно по стилю/типу. Сквозь атрибут Blocking
	-- реаль��о проходят только грэбы/слэмы. К��юч таблицы = стиль (lower), значение = {[kind]=true}
	-- или {all=true}. Для таких угроз скрипт доджит НАЗАД в i-frame ок��������������������������������о вместо бесполезного
	-- блока. Расширяется без правки кода: допиши сюда стиль/тип, который пробивает твой блок.
	MustDodge       = true,
	-- [V106] авто-детект грэб-M2 по CombatConfig (M2Grab*/M2Slam*-атрибуты стиля). Ловит Kure и
	-- любые будущие грэб-стили без ручного пополнения MustDodgeStyles. false = только ручной список.
	MustDodgeAutoGrab = true,
	MustDodgeStyles = {
		wrestling = { M2 = true },  -- Wrestling M2 = гарантированный захват (M2GrabTargetForwardOffset), блок не спасает
		-- [V106] Kure M2 = КОМАНДНЫЙ ГРЭБ/СЛЭМ (CombatConfig.Styles.kure: M2GrabAllowRagdollCombo,
		-- M2GrabTargetForwardOffset=2.7, M2GrabLockDuration=0.5, M2GrabSlamDelay=0.3). Проходит
		-- СКВОЗЬ блок, а на попадании ставит M2SlamParryWindowDisableDuration=2с → парри выключ��но
		-- 2 сек �� весь пос��едующий Kure-комбо прилетает не заблокированным (в логе — каскад
		-- Stunned/CantAnything). Раньше скрипт пытался блокировать/переби��ать этот гр��б → слэм.
		-- Теперь Kure M2 = только додж назад в i-frame, как Wrestling M2.
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
	-- [V117] exposed-escape срабатывает ТОЛЬКО когда мы залочены В СВОЕЙ АТАКЕ (не можем блокнуть
	-- мид-свинг), а НЕ когда просто дэшнули. Раньше exposed смотрел на selfBusyUntil, который дэш
	-- тоже выставляет → один додж делал нас «busy» → следующий удар триггерил ещё один exposed-додж
	-- → самоподдерживающийся додж-луп (осо��енно в меньшинстве, где грант обходит кулдаун 2.05с).
	-- Дэш уже даёт i-frames [180,480] — передоджить во время дэша бессмысленно.
	ExposedEscapeAttackOnly = true,
	-- [V117] outnumbered-escape (бесплатный грант-эвейд в меньшинстве) НЕ жжём на ОДИНОЧНЫЙ
	-- блокируемый у����а�� �� его надёжнее спарировать. Грант тратим только если реально НЕ можем блокнуть
	-- ИЛИ это мультиугроза (2+ контакта в окне, одним блоком не покрыть).
	OutnumberEscapePreferBlock = true,
	DashSpeed     = 30,
	MaxHeightDiff = 12,   -- [module] ignore attackers whose Y differs by more than this (different floor/level)
	DashDuration  = 0.20,
	DodgeConfirm  = 0.18,
	DodgeCenter   = true,
	HeavyDodgeInset = 0.075,   -- [V90] БОЛЬШЕ НЕ УЧАСТВУЕТ в центрировании (см. DodgeCenter ниже)
	-- [V90] ЦЕНТРИРОВАНИЕ ДОДЖА — ИСПРАВЛЕНА КОРНЕВАЯ ОШИБКА.
	-- Серверный iframe покрывает [T+up, T+up+IFrameDur], где up (≈RTT) уже прибавляется
	-- отдельно в точке сравнения. Прежняя формула добавляла ЕЩЁ и DodgeConfirm+DodgeArmWindow
	-- (0.23с) ⇒ суммарный lead = RTT+0.38 при допустимом максимуме RTT+0.30 ⇒ контакт
	-- прилетал на ~80мс ПОЗЖЕ конца iframe. Додж играл анимацию, но удар проходил.
	-- DodgeConfirm = ServerConfirmTimeout игры — это ТАЙМАУТ ожидания, а НЕ латентность.
	-- Теперь lead = IFrameDur*0.5 (центр окна) + биасы ниже.
	DodgeCenterBias = 0.00,    -- + = жать раньше, − = позже (сек). 0 = точный центр iframe
	HeavyDodgeBias  = 0.00,    -- доп. биас только для M2 (у тяжёлых предикт контакта шумнее)
	-- [V90] FRAME LOOKAHEAD — лечит деградацию на низком FPS.
	-- Планировщик живёт на Heartbeat, поэтому press/dodge случались на ПЕРВОМ кадре после
	-- дедлайна ⇒ систематическое опоздание [0, dt]: при 20 FPS до 50мс при окне парри 125мс.
	-- Смотрим на полкадра вперёд ⇒ средняя ошибка 0 вместо +dt/2.
	FrameLookahead   = 0.5,    -- доля кадра вперёд (0 = старое поведение, 0.5 = центр)
	FrameLookaheadCap= 0.045,  -- базовый потолок (сек) для стабильного FPS
	-- [V139] ПОЧЕМУ V90 НЕ ЛЕЧИЛ НИЗКИЙ FPS ДО КОНЦА — две отдельные причины:
	--   1) frameDt — это EMA(α=0.2). Она описывает СРЕДНИЙ кадр, а опаздываем мы на КОНКРЕТНОМ
	--      длинном. Стандартный профиль дропа в этой игре — 60 FPS с провалами до 8–15 (спавн
	--      эффектов, стрим ассетов): EMA держится ~17мс, реальный кадр 90мс, lookahead 8мс →
	--      press падает на первый Heartbeat после дедлайна, опоздание до 90мс при окне 125мс.
	--      Теперь ведём ЗАТУХАЮЩИЙ ПИК дельты (frameDtPeak) и берём max(EMA·K, peak·PeakK):
	--      после первого же дропа lookahead мгновенно подскакивает и держится, пока дропы идут.
	--   2) FrameLookaheadCap=0.045 обрезал компенсацию: на 12 FPS (83мс кадр) нужно ~42мс, на
	--      8 FPS — 62мс, а потолок отдавал 45мс. Потолок стал АДАПТИВНЫМ: max(base, peak·CapK),
	--      с абсолютным пределом FrameLookaheadCapHi, чтобы длинный фриз не выстрелил абсурдно рано.
	FrameLookaheadPeakK  = 0.50,  -- доля ПИКОВОГО кадра (главный член на дропах)
	FrameLookaheadPeakDecay = 1.10, -- сек полу-затухания пика (быстро отпускаем после дропов)
	FrameLookaheadCapK   = 0.75,  -- потолок = peak · этого (перекрывает половину худшего кадра)
	FrameLookaheadCapHi  = 0.11,  -- абсолютный предел (сек)
	-- [V139] Собственная стоимость шага скрипта тоже входит в опоздание: `now` берётся в НАЧАЛЕ
	-- Heartbeat, а сравнение `now >= pressAtQ` исполняется после всей геометрии/трейсов. На слабо��
	-- машине с 10+ угрозами это 4–12мс чистого сдвига, которые раньше никем не учитывались.
	FrameStepCostComp    = 0.60,  -- какую долю измеренной стоимости шага компенсируем
	SmartDodgeDir = true,
	DodgeWallCheck = true,
	DodgeWallDist  = 8,

	DodgeHardStates = { "Ragdoll", "Downed", "Knocked", "KnockedDown", "Grabbed", "Carried",
	                    "Frozen", "Sitting", "Cutscene", "Greenzone", "RpCombatLocked",
	                    "StaffModPeaceMode" },
	NoDodgeWhileStunned = true,
	DodgeTelemetry  = true,

	-- [V66] LIVE-таймер контакта для придержанных тяжёлых. Раньше remaining тикал
	-- по стенным часам (contact0 - elapsed), а продление ����рабатывало ТОЛЬКО при
	-- полном стойле анимации (ChargeStallMs). Если враг держит M2 плавно-замедленной
	-- (TimePosition ползёт по чуть-чуть), стойл не детекти��������������ся → contactAbs тикал к
	-- нулю → додж/блок уходили рано, реальный удар прилетал на +300мс позже (в логе
	-- predErr=+328ms → промах по held-heavy → Ragdoll-спираль). Теперь для M2/SKILL
	-- контакт считается по РЕАЛЬНОЙ скорости прогресса трека: remaining =
	-- (hitTL - tp) / max(liveSpeed, floor). При замедлении окно ед��т с ударом.
	LiveHeavyTimer    = true,
	LiveSpeedFloor    = 0.15,   -- ниже этой доли номинала скорость не считаем (антидел/0)
	LiveSpeedSmooth   = 0.35,   -- EMA-сглаживание измеренной скорости прогресса
	LiveM1Timer       = true,   -- [V96] live-TP коррекция и для M1 (лечит скачки predErr на M1)
	LiveM1SpeedFloor  = 0.45,   -- пол скорости для M1 выше (короткий трек → агрессивнее гасим ш��м)

	-- [V66] ЭКСТРЕННЫЙ ДОДЖ дв����х угроз. ��сли 2-й ко��такт прилетает раньше, чем мы
	-- физи��е���к���������� успеваем развернуться к нему + перевзвести перфект, блок 2-г��
	-- нев��змо��ен → доджим оба ���разу (iframes покрывают обоих). Порог = реальное
	-- время разв��рота (по угловой скорости) + запас на перевзвод.
	EmergencyDualDodge = true,
	-- [V134] Multi-cover dodge is a committed transaction: use it only when ONE confirmed
	-- server iframe interval can cover two or more independent contact deadlines.
	MultiDodgeCover = true,
	MultiDodgeConfirmSlack = 0.03,
	TurnRateDegPerSec  = 720,
	RearmBudget        = 0.06,  -- запас на свежий Activated (сервер + throttle)
	DualDodgeMaxGap     = 0.22, -- 2-й удар в пределах этого от 1-го = кандидат на dual

	-- [V66] р��сшире��ная диагностика NO-PRESS/held-heavy (для точного разбора причин)
	DeepDiag           = true,

	-- [V122] BOXING COUNTER — переписан с нуля (простая агрессивная модель по ТЗ юзера). Если наш
	-- стиль Boxing и аддон включён: при ЛЮБОЙ детекте атаки врага, который в радиусе
	-- BoxingCounterReach, и когда наш M2 НЕ на кулдауне — МОМЕНТАЛЬНО бьём M2 в этот же кадр,
	-- БЕЗ задержек и БЕЗ ожидания контакта, вместо парирования. Старые костыли (Lead-задержка до
	-- contact−0.16с, ComboGuard по каденсу, PingCeil, Solo/MinGap-л��гика, pre-face окно) УДАЛЕНЫ —
	-- именно они и ломали: counter ждал момента contact−lead и часто отменялся гейтами, из-за чего
	-- M2 не летел, а guard уже был сброшен → скрипт «стоял и ничего не делал» и мазал парри.
	BoxingCounter     = false,
	BoxingCounterReach= 5.5,   -- макс. плоская ����������истанц��я до ата��ующего, ��туды (��З юзера)
	BoxingCounterGap  = 0.30,  -- анти-даблфайр: не слать M2 повторно чаще (сек). НЕ задержка перед 1-м
	-- ================= [V91] ALI COUNTER =================
	-- Работает по тому же принципу, что боксёрская контра: CombatConfig.Styles.ali.M2GrantsIFrames
	-- = true, а i-frames в этой игре — абсолютная неуязвимость (VictimHitboxServiceClient
	-- ._isSuppressed глушит скан хитбоксов при IFRAMES). Значит своя M2 заменяет парри.
	AliCounter        = false,  -- мастер-тумблер (аналог BoxingCounter, но для Ali)
	AliCounterReach   = 7.5,    -- больше боксёрских 5.5: Ali M2 сама доводит на M2StepForwardStuds=2
	-- Вариант тяжёлой выбираем НАПРАВЛЕНИЕМ ДВИЖЕНИЯ (CombatStepUtils.ResolveM2VariantId), т.к.
	-- в Fire("M2","ServerCheck") вариант не передаётся — сервер резолвит его сам:
	--   "Right" → HitboxDelay 0.67, урон ×1.25, KB ×1.0, Ragdolls=true   (максимальный вы����лоп)
	--   "Left"  → HitboxDelay 0.53, урон ×0.8,  KB ×0.6, Ragdolls=false  (быстрее приходит)
	-- [V160] ДЕФОЛТ СМЕНЁН Right → Left. Контра здесь применяется ВМЕСТО парри, то есть её
	-- единственная защитная задача — поднять i-frames раньше входящего контакта. Right тратит
	-- на это 0.67с против 0.53с у Left, то есть 140мс лишней экспозиции при окне парри 0.125с.
	-- Right выбирался по урону (×1.25 + рэгдолл), что противоречит защитному назначению ветки.
	-- Косвенное подтверждение из дампа: игра для своего же EvasiveCounter жёстко прописала
	-- VariantId = "Left" (CombatConfig.Styles.ali.EvasiveCounter) — ровно по этой причине.
	-- Кому нужен размен на урон — переключает обратно в UI, поведение сохранено.
	AliM2Variant      = "Left",
	-- [V161] Окно, в течение которого мы пытаемся отстрелять полученный проц Evasive Counter.
	-- Доля от его же Cooldown (6с, CombatConfig:261) с жёстким потолком. Нужно потому, что
	-- CombatAttacking от нашего AutoPlay гаснет позже конца i-frame окна, а привязка к untilAt
	-- давала ALI-EVCOUNTER-EXPIRE и ноль отправок за сессию.
	AliProcTTLFrac    = 0.25,
	AliProcTTLMax     = 1.5,
	AliVariantSteerDur= 0.15,   -- сколько держим направление, чтобы сервер увидел нужный MoveDirection
	-- Отдельная механика Ali: EvasiveCounter={Cooldown=6, MaxRange=22, IgnoreM2Cooldown=true}.
	-- Сразу после ПОДТВЕРЖДЁННОГО уклонения M2 бесплатна (минует 7с кулдаун) и достаёт на 22 студа.
	AliEvasiveCounter = false,
	-- [V154/ALI] Dodge Abuse тратит Evasive только когда обычная Ali M2 реально на cooldown
	-- больше 1с и perfect-dodge может открыть авторитетную бесплатную M2.
	AliDodgeAbuse     = false,
	-- [V139] GenericIFrameCounter УДАЛЁН. Он выдавал counter-M2 любому стилю, у которого в дампе
	-- M2GrantsIFrames=true, но реч/вариант/кулдаун у ка��дого стиля свои: counterCandidate брал
	-- боксёрские 5.5 студа, steerM2Variant не знал вариантов, а M2Cooldown=7с сжигался вхолостую.
	-- Контра остаётся ровно у двух стилей, под которые она откалибрована: boxing и ali.
	-- [V92] КОНТРА ВМЕСТО ДОДЖА. CombatConfig.Styles.{ali,boxing}.M2GrantsIFrames = true — своя
	-- тяжёлая выдаёт РОВНО ТЕ ЖЕ i-frames, что и Evasive, но вместе с уроном. Раньше все ветки
	-- доджа стояли в планировщике ВЫШЕ tryBoxingCounter, поэтому при доступной контре скрипт
	-- сначала жёг Evasive (1.5с кулдаун), а контра уходила следующим кадром — два действия на
	-- одну угрозу. Теперь при готовой контре ОПЦИОНАЛЬНЫЕ доджи пропускаются.
	-- must-dodge (грэбы/анблокаблы) НЕ гейтится: это обязательная защита, а не удобство.
	CounterPreemptsDodge = true,
	-- [V92] ЦЕНТРИРОВАНИЕ ДОДЖА. Окно покрытия было [ifLat-0.03, ifLat+ifDur-0.04] ≈ 290мс, и
	-- т.к. планировщик опрашивает каждый кадр, додж уходил на ПЕРВОМ кадре попадания в окно, т.е.
	-- на дальней границе: i-frames поднимались за ~260мс до контакта и исте��али через 40мс после.
	-- Любой джиттер сети/FPS → удар приходит уже ПОСЛЕ окна. Теперь ждём, пока контакт не
	-- окажется у центра окна (доля от IFrameDuration), как это уже делает ветка DodgeCenter.
	DodgeCenterFrac   = 0.5,
	                           -- ударом — только защита от двойной отправки в сетевом окне до того,
	                           -- как появится атрибут M2Cooldown (реальный кулдаун держит игра).

	-- Skill Addons: per-style combat behaviors that plug into the parry brain.
	-- Each maps to a REAL mechanic found in CombatConfig, not a placeholder.
	SkillAddon        = true,
	SA_WrestlingGrab  = true,   -- enemy Wrestling M2 = unblockable grab (M2GrantsHyperArmor) → force dodge
	SA_DirtyGrab      = true,   -- enemy Dirty grab/M2 (GrappleDirtyHit, ImmuneToRagdollM2) → force dodge
	SA_HakariRead     = true,   -- widen window for Hakari momentum M2 (HakariMomentumM2HitboxDelay 0.62)
	SA_HakariWiden    = 0.05,   -- extra front/hold seconds applied to a Hakari M2
	-- [V91] BLATANT force-dodge.
	-- (self-busy) или в софт-стане (Stunned/CantAnything) — из-за этого «атаковал не вовремя →
	-- съел удар». Этот аддон ОВЕРРАЙДИТ блокировку: если удар вот-вот при��е����ит, а мы залочены
	-- софт-��остоянием и не можем блокнуть — форсим сам dodge-инпут (сервер его примет).
	-- Жёсткие состояния (Ragdoll/Grabbed/Downed) НЕ обходим ����� т����м дэш ��и��иче����и ничего ��������е даёт.
	-- Blatant = палевно (легит-игрок не смог бы), поэтому по умолчанию ВЫКЛ.
	SA_BlatantDodge   = false,
	SA_BlatantWindow  = 0.32,   -- сек до кон��акта: в э����м окне ����а��атывает форс-додж

	-- [V97] AutoPlay addon — автоатака. По умолчанию ВЫКЛ (агрессивное поведение).
	AutoPlay          = false,  -- мастер-тумблер аддона
	AP_PunishOnParry  = true,   -- добивать M1 застаненного врага после идеального парри
	AP_Interrupt      = true,   -- вместо parry сбить одиночную атаку, только если наш M1 гарантированно раньше
	AP_InterruptMargin= 0.055,  -- наш ожидаемый hit должен опередить вражеский минимум на 55мс
	AP_InterruptNetK  = 0.50,   -- ServerCheck идёт к серверу примерно за половину RTT
	AP_BaseReach      = 5.5,    -- базовый реч нашего M1 (ForwardOffset 4 + запас), студы
	AP_RefHeight      = 5.5,    -- эталон высоты модели для масштаба реча по ��осту
	-- ── [V139] M2 В INTERRUPT ────────────────────────────────────────────────────────────────
	-- Interrupt раньше знал ровно один инструмент — M1. Когда M1 не успевал, скрипт уходил в
	-- парри, хотя M2 нередко была и доступна, и объективно лучше: BaseDamage 8.5 против 5,
	-- DefaultStrongKnockback=25 сбивает комбо ЦЕЛИКОМ (M1 гасит один удар), а у стилей с
	-- M2GrantsIFrames тяжёлая ещё и выдаёт неуязвимость — размен становится безрисковым.
	AP_InterruptM2       = true,  -- разрешить M2 как инструмент interrupt
	AP_InterruptPreferM2 = true,  -- оба успевают → берём M2 (false = берём физически более ранний)
	AP_M2BaseReach       = 6.5,   -- базовый реч нашей M2 (свой ForwardOffset + запас), студы
	AP_M2Gap             = 0.30,  -- анти-даблфайр; реальный кулдаун держит игра (M2Cooldown ~7с)
	-- Для M2 с i-frames гонку выигрывать НЕ надо: достаточно поднять неуязвимость до контакта,
	-- поэтому дедлайн здесь — только сетевое плечо + этот запас, а не наш hitbox delay.
	AP_M2IFrameMargin    = 0.035,
	-- [V140] ЛОКАЛЬНЫЙ ГАРД ПЕРЕЗАПУСКА СВИНГ-АНИМАЦИИ. В норме повтор держит серверный атрибут
	-- "M1" через canAttack, но при десинке/anti-autoparry сервер его не ставит, и трек
	-- рестартился каждые 80мс → видимое дёрганье. Гард чисто клиентский, поэтому работает
	-- именно там, где штатный гейт отваливается.
	-- [V141] AP_AnimMinFrac и AP_AnimGuardCap УДАЛЕНЫ — именно они и вызывали дёрганье.
	-- Разбор в fireM1Custom. Коротко: 0.55 и потолок 0.30с обрезали гард до ~0.25с при треке
	-- ~0.45с, то есть САМИ РАЗРЕШАЛИ рестарт на середине анимации. Обе настройки были подгонкой
	-- вместо длины трека, которая и так известна из самой анимации.
	AP_AnimGuard    = true,
	AP_AnimFallback = 0.45,   -- если длина трека ��едоступна: AttackDuration из дампа
	-- [V107] РЕЙТ СВОЕГО M1. Раньше fireM1Custom слал через CombatRemoteClient.Fire, а тот держит
	-- ClientSustainedMaxPerSecond["M1.ServerCheck"]=4 с ФРОНТ-ЛОАД окном: 4 свинга по 0.08с подряд,
	-- потом ТИШИНА до конца 1-сек окна. Отсюда: (1) не быстрее 4/с, (2) ан��мация не успевает
	-- проиграться (4 свинга втиснуты в 0.24с → рестарт каждые 80мс = «сбивается»), (3) в окне стана
	-- (M2=1.0с) бьём 4 раза в первой четверти и молчим остаток. Настоящий серверный потолок —
	-- ServerSustainedMax["M1.ServerCheck"]={low=6,mid=8}/сек, ServerMinInterval=0.08. Поэтому шлём
	-- НАПРЯМУЮ (ServerRemote:FireServer, минуя клиентский кап 4) с РАВНОМЕРНЫМ шагом ~6/с: и быстрее,
	-- и анимация видна (0.16с на свинг), и весь стан-window заполнен.
	-- [V110] потолок свингов/сек. Поднят 6→8 (юзер: «M1 медленный, атаковать раньше/чаще»).
	-- 8 = ServerSustainedMax.mid для M1.ServerCheck (реальный серверный потолок); выше него ��ервер
	-- считает нарушением (MonitoredKeys) → риск флага. Слайдер 3..8 в apPlay/Tuning: 6 = безопаснее.
	AP_MaxPerSec      = 8,
	AP_MinSendGap     = 0.08,   -- = server min interval (ClientMinInterval M1.ServerCheck=0.08)
	AP_PunishFastGap  = 0.08,   -- первый post-parry M1 получает приоритет сразу после server min interval
	AP_M2Stun         = 1.0,    -- CombatConfig ParryStun.M2 (стан после M2-парри)
	AP_M1Stun         = 0.5,    -- оценка стана после M1-парри (RecoveryLockout врага)
	AP_PollGap        = 0,      -- [V101] троттл поллинга tryM1 = 0 (пробуем КАЖДЫЙ кадр; настоящий
	                            -- рейт держит игровая tryM1 по AttackDuration 0.45с). Макс��мальная
	                            -- скорость реакции: как только сервер снимает parry-lockout 0.15с — бьём.
	AP_FaceHold       = 0.35,   -- скольк�� держать лицо на цели после выстрела M1
	-- [V101] Комбо-контроль AutoPlay. "Follow" (дефолт) — родная tryM1 сама циклит ��дары комбо
	-- 1→2→3→4→1 (u19 = u19%4+1). "Fixed" — фо��сим один и тот же удар комбо (AP_FixedHit) через
	-- debug.setupvalue(u19) прямо перед свингом. Полезно для стабильного стартового удара.
	AP_ComboMode      = "Follow",  -- "Follow" | "Fixed"
	AP_FixedHit       = 1,          -- 1..4 — какой удар комбо бить в режиме Fixed
	-- [V105] СВОЙ M1-БИЛДЕР ВСЕГДА (fireM1Custom): обходит игровой 450мс-троттл (u21) и клиентские
	-- локи (u32/u33), шлёт ServerCheck сам. Единственный потолок — CombatRemoteClient.Fire
	-- (80мс burst / ~4-в-сек). Тумблеров Turbo/Fast больше нет — это база, всегда включено.

	-- [V98] реагировать только когда руки одеты (Equip==true). Иначе сервер всё равно
	-- откажет и в блоке, и в атаке (Block.lua/M1.lua требуют Equip). Кросс-пл��т��ормен��о.
	RequireEquip      = true,

	RestrictZone      = true,
	RestrictLongOnly  = true,
	RestrictMinWindup = 0.30,
	RestrictPad       = 2.0,
	RestrictSoft      = true,
	RestrictShowZone  = true,


	SelfBusyDur     = 0.45,

	DesyncAttack   = false,
	-- [V88] Режимы desync (ци��л клавишей ]):
	--   delay     — визуал твоего замаха задержан на DesyncDelayMs; FireServer уходит вовремя.
	--   firedelay — визуал идёт ��овремя; только M1/M2 ServerCheck уходит позже на DesyncDelayMs.
	--   idlemask  �� посто��нный ��пуф IDLE, пок�� ты атак��еш����.
	--   prerun    — фейк-атака (как [) СРАЗУ + реальный FireServer задержан на DesyncDelayMs.
	DesyncMode     = "delay",
	DesyncDelayMs  = 140,          -- единая задержка delay/firedelay/prerun (мс)
	DesyncDecoyId  = 507766388,
	DesyncApplyM1  = true,
	DesyncApplyM2  = true,
	-- [V83] анти-decoy: игнорить неестественно быстрые повторы атак от одного врага
	-- (флуд decoy/фейк-атак вроде наших prerun/idlemask), чтобы не сбивали ����аш парри.
	AntiDecoy      = true,
	AntiDecoyGap   = 0.12,       -- мин. интервал между настоящими свингами одного врага (сек)
	-- [V90] Быстрый повтор больше НЕ отбрасывается (раньше терялся настоящий удар, шедший
	-- вторым после фейка) — он живёт как suspect и обязан подтвердиться VictimSwingId.
	-- Этот кап — предохранитель от машинного флуда: свинги свыше него в окне всё же дропаем.
	AntiDecoyMaxBurst = 3,
	-- ================= [V91] BREAKER GATE — по данным диага 614203 =================
	-- Диаг 614203: ОДИН игрок (gugugagafinal) выдал ВСЕ 555 детектов сессии. Профиль потока:
	--   • один и тот же animId повторён 553 раза, медиана интервала 170мс (min 117мс)
	--   • tp=0.000 всегда (трек перезапускается с нуля)
	--   • track.Speed = 2.36  —  у ВСЕХ реальных игроков в диагах 649919/580903 ровно 1.00
	-- Последствия: attacks=2872 при 204 исходах, CLUSTER раздувался до n=8, и 154 промаха
	-- по��учили причину «in-window но не выбран EDF» — фантомы вытесняли настоящий удар.
	-- AntiDecoyGap=0.12 этот поток НЕ ловил: 170мс > 120мс, т.е. брейкер шёл ровно над порогом.
	-- Два независимых физических инварианта (оба проверены на реальных сессиях):
	DecoyRefireSec  = 0.60,   -- один и тот же animId от одного врага не может стартовать заново
	                          -- быстрее этого. Замер: реальные игроки переиспользуют тот же id
	                          -- через 3000–25000мс, брейкер — через 170мс.
	-- ═══════════ [V160] ИНВАРИАНТ «Speed ВСЕГДА 1.00» ОКАЗАЛСЯ ЛОЖНЫМ ═══════════
	-- Прежний коммент утверждал: «Реплицированный трек реального врага всегда 1.00, скорость
	-- удара сервер учитывает через рост, а НЕ через Speed трека». Дамп это опровергает прямо.
	-- M1_ModuleScript.lua:81-90:
	--     local function getFinalM1AnimSpeed(p12, p13)
	--         local v14 = CombatUtils.GetCharacterHeight(p12)
	--         local v15 = v14 and CombatUtils.GetAttackSpeedMultiplier(v14) or 1
	--         local v18 = CombatConfig.GetScaledStyleM1HitboxDelay(style, p13, v15)
	--         return v15 * CombatPingAnimUtils.GetPingAnimSpeedMultiplier(v18, LocalPlayer)
	--     end
	-- и CombatPingAnimUtils:13 ��� D / (D + clamp(ping·0.5, 0, 0.35)).
	-- Это значение уходит в playM1SwingAnimation → LoadAnim → AdjustSpeed, то есть РЕПЛИЦИРУЕТСЯ
	-- наблюдателю. Итоговая ско��ость чужого трека:
	--     speed = h · D/(D + L),  h = GetAttackSpeedMultiplier(рост) ∈ [0.85, 1.15],
	--                             D = (base + 0.012)/h,  L = clamp(ping_атакующего·0.5, 0, 0.35)
	-- Отсюда физические границы ЗАКОННОЙ атаки (не подгонка — вывод из формулы):
	--   • сверху: L ≥ 0 ⇒ speed ≤ h ≤ 1.15;
	--   • снизу:  L ≤ 0.35 и самый короткий замах в игре (Ali M1 удар 4: 0.22 + 0.012 = 0.232)
	--             ⇒ speed ≥ h·0.232/(0.232 + 0.35h) = 0.372 при h=0.85.
	-- Старая полоса 1.00±0.50 = [0.50, 1.50] РЕЗАЛА нижнюю часть законного диапазона: враг с
	-- пингом от ~350мс и/или высоким ростом классифицировался фантомом и, при DecoyHardDrop,
	-- выбрасывался ЦЕЛИКОМ — без угрозы, без нажатия, без строки в диаге.
	-- Новая полоса выведена из формулы с запасом на скиллы с ещё более коротким замахом.
	-- Брейкер из диага 614203 играл на 2.36 → по-прежнему отсекается с большим отрывом.
	DecoySpeedMin   = 0.30,   -- ниже физически невозможной скорости законного трека
	DecoySpeedMax   = 1.25,   -- выше max(h)=1.15 + запас на округление
	DecoySpeedTol   = 0.50,   -- [V160] LEGACY: больше не используется гейтом, оставлен для
	                          -- совместимости со сохранёнными конфигами прошлых версий.
	DecoyHardDrop   = true,   -- true = фантом не создаёт угрозу вообще (не попадает в EDF/cluster)
	-- [V139] Развёртка таблицы виденных animId — по ВРЕМЕНИ, а не раз в N вставок (см. коммент
	-- в точке ��чистки: в людном лобби вставочный триггер зацикливал дорогой pairs-обход).
	DecoySweepSec   = 5,      -- как часто выметать записи старше 8с
	DecoySeenMax    = 512,    -- если после развёртки живых записей больше — таблица сносится целиком
	-- [V91] SERVER-TRUTH RESOLVER (anti "Anti-AutoParry"). Enemies running Anti-AutoParry fake
	-- the swing ANIMATION — the only attack signal their own client can forge — to pull our
	-- parry early, then hit for real while we sit in block cooldown (0.5s). The SERVER instead
	-- sets "M1"/"M2"/"CombatAttacking" on the attacker's character and creates the hitbox part
	-- itself; neither can be faked by the attacker. With this on, an UNPROVEN swing does not get
	-- a press until the server confirms it or we are within ProofGraceSec of contact — so fakes
	-- are ignored while a genuine attack (whose attribute lands late) is still parried.
	ServerProofGate = true,
	ProofGraceSec   = 0.06,      -- press anyway once this close to contact, proven or not
	-- [V142] ОТКАТ V140/V141: ключи ProofEdgeTrigger (владелец атрибута) и Rep* (репутация)
	-- удалены. Первый глушил законные удары multi-hit M2 и комбо, второй ни разу не сработал.
	-- Подробный разбор — у бывшего места State.attrProofTaken.
	-- [V91.1] Parry timestamp spoof. Block.Activated carries a CLIENT-chosen server-time stamp
	-- and nothing clamps it client-side, so a late parry can be back-dated into the 0.125s
	-- perfect window. Off by default — flip it on and creep TimeShiftMs up.
	TimeSpoof    = false,
	TimeShiftMs  = 40,
	-- [V91] Decoy weight. AnimationTrack WEIGHT is what Roblox replicates, so a decoy has to
	-- win the pose to fool anyone: false → 0.92 (mask wins; you still see a hint of the real
	-- swing), true → 1.0 (full mask). The old "0.03 = invisible to me" value replicated almost
	-- nothing, which is why idlemask/prerun looked like dead toggles.
	DesyncClientVisible = false,
	DesyncSendHz      = 0,        -- Anti-AutoParry decoy re-sends per second; 0 = auto (track length)
	-- Invisible desync: реплицируем ��онтортну��ый/опущенный корень на сервер (другие тебя не видят),
	-- локально каждый RenderStep возвращаем на место (ты ��идишь себя ��орма��ьно).
	InvisibleOn    = false,
	InvisibleHeight= 0,           -- ДОП. студы поверх базового з��хо������онения (кастом высота); 0 = базовое
	InvisibleAnim  = true,        -- дополнительная контортящая ани��ация для лучшего скрытия
	-- [V91] DesyncScanSecs / DesyncRaknetWindowMs / DesyncSelfVerify removed — all three only
	-- fed the deleted raknet-scan and self-verify code, so they configured nothing.

	-- [V122] сколько держим жёсткий взгляд на враге ПОСЛЕ выстрела M2-counter (сервер строит
	-- boxing-M2 хи��бокс по нашему LookVector в момент ServerCheck → надо смотреть точно на врага).
	BoxingFaceLockDur = 0.55,
	-- [V155/ALI-ROTATION] Раньше Ali о��ибочно использовал boxing hold=0.55с. У Ali другой
	-- M2-таймлайн, поэтому его LookVector-lock хранится отдельно и доступен в UI.
	AliFaceLockDur = 0.75,

	-- [V62] ГИБРИД мульти����я: перфектим ближайшего, остальным держим guard
	-- непрерывно (нулевые дыры = нулевые полные ������иты). holdUntil тянется по
	-- самому дальнему угрожаю��ему ��онтак��у в ��ла����тере, guard не отпускается
	-- в середине burst, re-press в BlockCooldown исключён.
	MultiThreatGuard  = true,
	MultiThreatMinN   = 2,      -- со скольких одновр��м��нных угроз ��ключать held-��еж��м
	-- [V73] multi-target knobs
	BlockCooldown     = 0.50,
	SequentialSpread  = 0.78,
	MultiFaceAngleMax = 70,
	MultiFaceJitter   = 0.30,
	MultiFaceOnlyFront= true,
	-- [V139/BUG] Здесь ЛЕЖАЛ ВТОРОЙ `MinActGap = 0.030`. В Lua при дублировании ключа в одном
	-- литерале побеждает ПОСЛЕДНИЙ, поэтому осознанное значение из V91.1 (0.004, строка ~156,
	-- с комментарием «no reason to sit on a parry for 30ms») молча затиралось старым 0.030 из
	-- V73 — весь рефакторинг V91.1 не работал ни одной версии. Эффект прямой: гейт
	-- `now - State.lastAct < Config.MinActGap` отклонял Block, если с прошлой активации прошло
	-- <30мс. При 60 FPS это ~2 кадра, при дропах до 15 FPS — целый кадр в никуда, и именно на
	-- второй угрозе в кластере (спред считается через тот же MinActGap на строке ~4544) парри
	-- срывалось. Одна из главных причин «плохо парирует при низком FPS». Дубликат снят,
	-- действует 0.004.
	-- [V62] desync flicker: НИКОГДА не переиспользовать реальные геймплейные
	-- дорожки (walk/run/emote) как decoy — только whitelisted idle или выделенный
	-- decoy-т����ек. Иначе flicker д������ргал твою реальную анимацию на 90Гц.
	DesyncSafeDecoy   = true,

	AntiCheatBypass = true,
	HideHooks       = true,
	MuteAC          = true,
	BlockKick       = true,
	BlockACReports  = true,
	ACScriptName    = "so you're challenging me",
	NeutralizeAC    = true,



	-- [V90.2] Мульт��таргет: мгновенный (hard) снап лицом к следующему атакующему, когда в
	-- замесе 2+ угрозы — без п��авного лерпа, чтобы не терять ка��ры на перекладку между целями.
	MultiFaceHard     = true,

	DodgeHorizon      = 0.34,
	MinBlockSeparation= 0.17,
	DodgeArmWindow    = 0.05,

	LegitAnims    = true,

	AutoFace      = true,
	FaceLerp      = 0.80,   -- [V70] быстрее трекинг между атакующими в замесе
	FaceLeadWindow= 0.30,
	FaceGoodDot   = 0.55,
	-- [V91] ПРЕДИКТ РОТАЦИИ автофейса: целимся чуть НАПЕРЁД движения в��ага (ведём его
	-- позицию по скорости на FaceLead сек), чтобы facing не отставал от ст��ейфа/забегания
	-- за спину. Держим предикт малым (иначе перелёт при резкой смене направления).
	FaceLead      = 0.07,   -- сек упреждения по скорости врага
	FaceLeadMax   = 4,      -- студы: кап упрежде��ия
	-- [V97] PING-SCALED предикт facing (applyFacing). Упреждение = vel * (ping * FacePingLead),
	-- т.к. рассинхрон позиции врага прямо пропорционален латентности. FaceLeadCap — верхний предел
	-- по времени (сек), FaceLeadMaxStuds — по расстоянию (fallback-кап, когда цель почти в упор).
	FacePingLead  = 1.0,
	FaceLeadCap   = 0.28,        -- [V118] 0.22→0.28: пинг в ло��е до 244ms, даём полный desync-lead
	FaceLeadMaxStuds = 16,       -- [V118] 7→16: общий fallback-кап (только vel≈на л��нии/в упор)
	-- [V118] РАЗДЕЛЬНЫЕ капы боковой/радиальной составляющей упреждения. КОРЕНЬ жалобы «враг
	-- дэшит В УПОР (радиально) + толкается влев��/вправо (боково) → блок, не парри»: старый единый
	-- кап (7 студ) на ВЕСЬ вектор vel*lead → большая РАДИАЛЬНАЯ скорость дэша съе��ала весь бюджет
	-- → БОКОВАЯ коррекция (та, что ��адаёт угол facing) обр��залась пропорционально → лицо отставало
	-- (в логе face=0.2/-0.6 BACK! при валидном press → сервер даунгрейдит перфект в обычный блок).
	-- Фикс: раскладываем vel на ради��ль (враг��я, почти не влияет на угол) �� боковую (задаёт угол),
	-- капим РАЗДЕЛЬНО. Боковой лимит щедрый (угол важен), радиальный маленький (анти-��ерелёт в упор).
	FaceLatMaxStuds = 18,        -- кап БОКОВОГО lead (перпендикуляр линии врагу) — главный для угла
	FaceRadMaxStuds = 5,         -- кап РАДИА��ЬНОГО lead (вдоль линии) — на угол не влияет, режем сильнее

	-- [V69] БЛОК НЕНАПРАВЛЕННЫЙ (доказано дампом: attacker M1 проверяет то��ько
	-- атрибут Blocking жертвы; Block-модуль — только PerfectBlocking; VictimHitbox —
	-- лишь попадание в бокс. НИГДЕ нет dot/LookVector/угла на стороне жертвы). Значит
	-- один guard прикрывает ��сех атакующих со всех сторон, и доворачиваться к врагу
	-- РАДИ БЛОКА не нужно. Из этого:
	--  1) мультитаргет: одно нажатие покрывает всех в окне — не теряем "перебитых EDF";
	--  2) поворот: делаем дешёвый ЧАСТИЧНЫЙ доворот к центроиду угроз (не жёсткий снап
	--     к одному), что эконом��т CPU и не дёргает камеру;
	--  3) dual-dodge "не успеем развернуться ко 2-му" больше не нужен — держим guard
	--     на обоих. Додж только когда блок реально недоступен (стан/кд/гардбрейк).
	-- OmniBlock оставлен: даёт мультитаргет-покрытие одним guard'ом и гейт dual-dodge.
	-- SoftFace удалён в V70 — вернули быстрый жёсткий снап.
	OmniBlock      = true,

	ShowVisuals   = true,   -- мастер-переключатель всех визуалов AutoParry
	-- [V90] Настраиваемые визуалы. Каждый элемент можно включить/выключить отдельно, а у
	-- вращающегося кольца настраиваются скорос��ь анимации, размер и дальность прорисов��и.
	VizRing       = true,   -- ��ращающееся кольцо под целью
	-- [V93] Ring style, ported from the TargetESP reference: "Flat" = classic ring at the feet,
	-- "Orbit" = ring tilts through depth so it reads as a 3D band, "OrbitSwirl" = same but the
	-- whole band also spins. Orbit modes additionally draw a mirrored ring for the 3D look.
	VizRingStyle  = "Flat",
	VizRingSeg    = 30,     -- segments in the ring (more = smoother, costs 2 projections each)
	VizRingMirror = true,   -- draw the mirrored/opposite ring (the thing that sells the 3D)
	VizRingTilt   = 0.7,    -- how far Orbit/OrbitSwirl push the band through depth (studs)
	-- [V94] How we face the target: "LookAt" rotates the character (server-safe, what we always
	-- did) | "AimLock" points the CAMERA instead and lets the game turn us (way less snappy).
	RotationMethod = "LookAt",
	AimLockLerp    = 0.35,   -- how hard AimLock pulls the camera (1 = instant snap)
	VizHitbox     = true,   -- бокс хитбокса цели
	VizRestrict   = true,   -- з��н�� ограни��ения (keep-out)
	VizRingSpeed  = 1.0,    -- множитель скорости анимации кольца (0.1–3.0)
	VizRingScale  = 1.0,    -- множител�� радиуса кольца (0.4–2.5)
	VizRange      = 100,    -- дальность (студы), на которой ищется/рисуется цель
	-- [V111] PERF: потолок частоты ПЕРЕРИСОВКИ визуалов. ESP чисто косметика — при 120+ реальных
	-- fps перери��овыват�� кольцо(40 сег)+конус каждый кадр (≈140 WorldToViewportPoint + 140 записей
	-- Drawing) = САМАЯ дорогая всегда-акти��ная работа. Кап 60 → дровинги живут между апдейтами
	-- (не скрываются), ESP визуально гладкий, а нагрузк�� на высоком fps падает вдвое+.
	VizMaxFPS     = 60,
	-- [V139] Авто-��еградация ESP. VizMaxFPS режет нагрузку только когда игра БЫСТРЕЕ кэпа; при
	-- просадке полная перерисовка платилась каждый кадр и усугубляла ту самую просадку.
	VizAutoDegrade   = true,
	VizFrameShare    = 1.5,   -- минимальный интервал перерисовки = frameDt · это (на 20 FPS ≈ 2 кадра)
	VizSkipNearPress = 0.20,  -- сек до/после press-дедлайна: кадр отдаём защите, ESP не рисуем
	-- [V140] Потолок ПОДРЯД идущих пропусков. Без него затяжное окно угроз (или залипшая метрика)
	-- гасит ESP на неопределённый срок — визуалы «замерзают» на последнем кадре.
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
	Key_DesyncSave = Enum.KeyCode.Semicolon,     -- [V75] ; → сохр����нить desync-дебаг в файл
	-- [V91] Key_DesyncScan removed together with the dead raknet scan block (it had no handler
	-- left, so the ' key silently did nothing).
	Key_DesyncTest = Enum.KeyCode.LeftBracket,   -- [V76] [ → тест-режим: постоянно реплицирова��ь АТАКУ ��ока стоишь
	Key_DesyncMode = Enum.KeyCode.RightBracket,  -- ] → циклить: delay → firedelay → idlemask → prerun
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
	-- [V90] ALI (Mystery rarity, CombatStyleRarityConfig weight 0.075 — редчайший стиль).
	-- IDs из дампа ReplicatedStorage.Animations.Combat.AliAnims. База M1=0.22, offsets {0.06,0.15,0.2,0}
	-- ⇒ d = base+offset (WINDUP_EXTRA до��авляет hitTimelineBase).
	-- ВАЖНО: Ali — единственный стиль с ДВУМЯ M2-вариантами (CombatConfig.Styles.ali.M2Variants):
	--   Left  → Anim "M2"      HitboxDelay 0.53  dmg×0.8   kb×0.6  Ragdolls=false
	--   Right → Anim "M2Right" HitboxDelay 0.67  dmg×1.25  kb×1.0  Ragdolls=true
	-- Разница 140мс при PerfectBlockWindow=0.125 ⇒ без различения вариантов парри на Right
	-- систематически EARLY, а это именно тот вариант, который ragdoll'ит и бьёт ×1.25.
	[137247073345979]={t="M1",d=0.28,s="Ali",c=1},   [102632933427597]={t="M1",d=0.37,s="Ali",c=2},
	[119814294807778]={t="M1",d=0.42,s="Ali",c=3},   [74315946602284]={t="M1",d=0.22,s="Ali",c=4},
	[128315752013166]={t="M2",d=0.53,s="Ali",v="Left"},
	[70642098724811]={t="M2",d=0.67,s="Ali",v="Right"},
}

-- [V90] Аварийный маппинг имени анима��ии → id M2-вариант��. Работает, только если живой
-- CombatConfig.GetStyleM2Variants недоступен (модуль не подгрузился). Живой ��онфиг приоритетнее.
local LEGACY_M2_VARIANT = { M2 = "Left", M2Right = "Right", M2Left = "Left" }

local LEGACY_M1_OFFSETS = {
	ali      = {0.06, 0.15, 0.2, 0},      -- [V90] CombatConfig.Styles.ali.M1HitboxDelayOffsets
	basic    = {0.02, 0.02, 0.02, 0.02},
	boxing   = {0.02, 0.02, 0.02, 0.06},
	-- [V90] СВЕ��ЕНО С ДАМПОМ: было {0.16,0.18,0.16,0.21} — ��стар��ло после апдей��а игры.
	hakari   = {0.14, 0.16, 0.07, 0.17},
	hakario  = {0.14, 0.16, 0.07, 0.17},
	karate   = {0.0375, 0.075, 0.15, 0.225},
	capoeira = {0.02, 0.1, 0.02, -0.05},
	slugger  = {0.3, 0.25, 0.25, 0.17},
	wrestling= {0.04, 0.05, 0.04, 0.03},  -- [V90] о��сутствовал
}
local LEGACY_M1_BASE = { ali=0.22, karate=0.24, muaythai=0.30, slugger=0.20, capoeira=0.33,
                         hakari=0.21, hakario=0.21, wingchun=0.28 }
-- [V90] hakari M2 СВЕРЕН С ДАМПОМ: 0.59→0.35, momentum 0.62→0.48. Добавлены все стили из
-- CombatConfig.Styles, которых т��т не было (taekwondo/wild/bulky/dirty/wingchun/skygaolang/variant/kure).
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
-- [V151] UserInputService удалён: ни одной ссылки в файле (ввод идёт через MacLib Keybind).
-- Это регистр главного чанка, а мы упёрлись в лимит Luau 200 → "out of local registers".
local Workspace         = game:GetService("Workspace")
local Stats             = game:GetService("Stats")

local LocalPlayer  = Players.LocalPlayer
local ServerRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server")

local State = {
	blocking     = false,
	guardUp      = false,   -- ИСТИННОЕ серв��рное состояние guard: true когда серверу отправлен
	                        -- Activated и ещё не отправлен Deactivated. Отдельно от blocking
	                        -- (внутреннее намер��ние), чтобы ��арантиров��нно снимать guard даже
	                        -- если blocking ��брошен в обход releaseBlock (dodge/counter/outcome).
	holdUntil    = 0,
	status       = "ARMED",
	lastThreat   = nil,
	parryCount   = 0,
	dodgeCount   = 0,
	grantEscapes = 0,
	selfBusyUntil= 0,
	attackBusyUntil = 0,   -- [V117] busy ТОЛЬКО из-за наше�� А��АКИ (не из-за дэша) — ��ля exposed-escape
	kicksBlocked   = 0,
	reportsBlocked = 0,
	acMuted        = 0,
	acScript       = nil,
	desyncFires    = 0,
	fireCount    = 0,
	lastDodge    = -99,
	-- [V147] Итог ПОСЛЕДНЕЙ закрытой dodge-транзакции: true = сервер подтвердил IFRAMES,
	-- false = отказ, nil = доджей ещё не было. Читает dodgeReady, чтобы под грантом не
	-- спамить дэшем, который сервер всё равно отклоняет. Пиш��тся в updateDodgeTxn.
	-- [V148] Поле dodgeConfirmedLast удалено: после снятия защёлки его никто не читает, а
	-- итог транзакции полностью описывается счётчиком dodgeRejects (он же самоочищается).
	dodgeRejects = 0,
	-- [V150] Пока os.clock() < swingAnimUntil, guard-анимацию ("Blocking") не поднимаем: она
	-- перекрывала трек нашего M1-свинга (разбор в playBlockAnim). Ставится в fireM1Custom.
	-- Это же поле служит оценкой «когда освободится наш перс» для counterReadyAt.
	swingAnimUntil = 0,
	-- [V150] Сколько угроз снято как уже нейтрализованные (атакующий в Parried/Stunned).
	threatNeutralized = 0,
	-- [V147] Анти-спам диага гейта доджа: печатаем факт блокировки один раз, сбрасываем при
	-- первом же прохождении гейта. Это не настройка — это защита лога от 60 строк в секунду.
	dodgeGateSaid = nil,
	lastDodgeInfo   = nil,
	-- [V154/ALI] Edge-tracker авторитетного M2Cooldown. known=false при подключении посреди
	-- cooldown: остаток тогда нельзя восстановить честно, поэтому ждём следующий полный цикл.
	aliM2CD = { char=nil, observed=false, active=false, known=false, started=0, duration=7 },
	-- [V134] authoritative dodge transaction. `pending` exists only after the request was
	-- sent; `confirmed` flips only on the game's replicated IFRAMES attribute.
	dodgeTxn = { pending=false, confirmed=false, fire=0, lo=0, hi=0, untilAt=0, reason=nil },
	-- [V152/BOXING-COUNTER] Контра теперь тоже транзакция, а не флаг «FireServer уже значит успех».
	-- pending живёт только до ожидаемой репликации; confirmed выставляется исключительно по живому
	-- IFRAMES либо серверному состоянию сбитого врага. threat хранит конкретную атаку, ради которой
	-- ушла M2, чтобы fallback возвращал в защиту именно её, не замораживая остальные угрозы.
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
	-- [V95] ЕДИНЫЙ канал поворота (facing authority). Раньше поворотом рулили 4 писателя HRP.CFrame
	-- вразнобой (faceToward в Heartbeat, boxing pre-face, enforceFaceLock в RenderStepped, игровой
	-- AutoRotate/шифтлок) — они дрались, отсюда залипание на одной це��и и дёрганье. Теперь schedulerStep
	-- лишь ВЫСТАВЛЯЕТ цель сюда, а применяет ОДИН аппликатор applyFacing в RenderStepped (последний
	-- писатель кадра, гасит AutoRotate). faceGoalHRP=на кого смотреть, Hard=жёсткий снап vs л��рп,
	-- Until=до какого времени держать (грейс после последней выставки), Hum=кэш Humanoid для AutoRotate.
	faceGoalHRP   = nil,
	faceGoalHard  = false,
	faceGoalUntil = 0,
	faceHum       = nil,
	faceGoalPos   = nil,   -- [V73] midpoint facing goal
	noParryActive = false,
	noParryNow    = false,
}

local Threats = {}

local FaceByResult = {}
local ResidByKS    = {}
local ComboState = {}
local Pending = {}

-- [V91/perf] Log trimming used to be `table.remove(t, 1)` — an O(n) memmove of up to
-- 4000 elements on EVERY push once the cap was reached. In a busy fight diagPush fires
-- dozens of times per second, so that alone was a measurable stall on weak PCs.
-- Now we drop the oldest 25% in ONE table.move when the cap is hit: amortized O(1) per
-- push, and the log keeps the same "most recent N lines" behaviour.
-- [V139/PERF] Два независимых источника фриза «на сбросе кэша» жили ЗДЕСЬ:
--   1) drop = cap/4 при cap=4000 → раз в 1000 пушей делался table.move ~3000 строк + 1000
--      присваиваний nil. Это один длинный синхронный кусок работы ВНУТРИ боевого кадра: ровно
--      тот «фри�� при сбросе кэша», который видно на глаз. Теперь сбрасываем ПОЛОВИНУ: та же
--      амортизация O(1) на пуш, но событие реже (раз в cap/2) и сам move вдвое короче.
--   2) DIAG_MAX=4000 + DESYNC_MAX=3000 = до 7000 отформатированных строк (~1.2МБ) висят в
--      памяти ДО конца сессии и никогда не отдаются GC. Это и есть «мемори лик»: не утечка
--      ссылок, а честно удерживаемый мусор. Кэпы урезаны до 1200/800 — на разбор последнего
--      боя этого с запасом, а удержание падает в ~5 раз.
-- [V144/PERF] Вызывается на КАЖДЫЙ push в три лога; внутри table.move по всему буферу.
local logTrim = LPH_NO_VIRTUALIZE(function(t, cap)
	local n = #t
	if n <= cap then return end
	local drop = cap // 2
	if drop < 1 then drop = 1 end
	table.move(t, drop + 1, n, 1)
	for i = n - drop + 1, n do t[i] = nil end
end)

local DiagLog, DIAG_MAX = {}, 1200
-- [V144/PERF] Точка входа всего диага (36 мест) — дешёвая функция, но вызовов много.
local diagPush = LPH_NO_VIRTUALIZE(function(line)
	DiagLog[#DiagLog+1] = line
	logTrim(DiagLog, DIAG_MAX)
end)

-- [V75] отдельный буфер desync-дебага (сохраняется в свой файл, чтобы слать мне).
local DesyncLog, DESYNC_MAX = {}, 800
local function desyncPush(line)
	local stamped = ("t=%.2f  %s"):format(os.clock(), line)
	DesyncLog[#DesyncLog+1] = stamped
	logTrim(DesyncLog, DESYNC_MAX)
end
-- [V89/module] Status ring-buffer. Replaces console `print`: every status/AC line is
-- pushed here and surfaced live in the loader's Debug tab (no console spam).
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

-- [V94] РОБАСТНЫЙ пинг. КОРНЕВОЙ БАГ (диаг: header ping=111/345, а все строки боя ping=60):
-- прежняя реализация лезла ТОЛЬКО в Stats.Network.ServerStatsItem["Data Ping"], и �� combat-
-- контексте (обработчики remote/AnimationPlayed, schedulerStep) этот путь систематически
-- фейлил pcall → возвращался хардкод 0.06 = ровно те самые 60ms. Из-за этого планировщик
-- (pressAt = contact - lead - up - velLead, где up=uplink() зависит от getPingRaw) компенсировал
-- ~68ms вместо реальных 111–345ms → ��л��к стабильно опаздывал (LATE) на любом заметном пин��е.
-- Фикс: первичный источник — LocalPlayer:GetNetworkPing() (метод самого инстанса ��грока,
-- доступен в ЛЮБОМ контексте, не бросает; возвращает one-way в секундах → RTT = ×2). Stats
-- Data Ping (уже RTT в мс) — как второй источник; берём МАКСИМУМ (перекомпенсация безопаснее
-- недокомпенсации для парри). Если оба недоступны — отдаём последнее валид��ое значение, а НЕ
-- хардкод 60. Итог: и hot-path, и header видят один настоящий RTT.
local _lastGoodPing = 0.08
-- Diagnostic-only source snapshot. Never consumed by scheduler/predictor.
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
-- [V144/PERF] Основа всех сетевых поправок: getPing/uplink/applyFacing тянут её каждый кадр.
-- ═══════════════════ [V161] КОРНЕВОЙ ФИКС: ЕДИНИЦЫ ПИНГА И ВЫБОР ИСТОЧНИКА ═══════════════════
-- Диаг 10810-10893 объясняется этой функцией ПОЛНОСТЬЮ, число в число:
--     rawRTT=1500ms  = потолок клампа ниже (1.5)
--     medRTT=500ms   = min(медиана 1.5, PingCap 0.5)
--     uplink=500ms   = clamp(0.5*UplinkFactor 1.0 + 0.008, 0.01, UplinkMax 0.5)
-- при том что РЕАЛЬНЫЙ RTT в тех же строках: statsRTT=91..266ms.
--
-- ОШИБКА 1 — ЕДИНИЦЫ. Прежний код считал GetNetworkPing() односторонней задержкой и УДВАИВАЛ её.
-- Сама игра трактует ровно это значение как ПОЛНЫЙ RTT и ДЕЛИТ его на 2
-- (CombatPingAnimUtils_ModuleScript:13, единственный потребитель пинга в боёвке):
--     local v3 = p2:GetNetworkPing();
--     return p1 / (p1 + math.clamp(v3 * 0.5, 0, NetworkAnimPingCompensation.MaxEstimatedOneWaySeconds));
-- Имя поля клампа — MaxEstimatedOneWaySeconds — прямо фиксирует: v3*0.5 это ОДНОСТОРОННЯЯ.
-- Значит RTT = GetNetworkPing(), а не ×2. Мы завышали вчетверо относительно модели игры.
--
-- ОШИБКА 2 — max() ПО ИСТОЧНИКАМ. Даже без ×2 источник A на этом клиенте отдавал ≥0.75с при
-- реальных 0.09-0.27с, а слепой max делал худший источник победителем и залипал в потолок.
--
-- ЦЕНА (всё видно в диаге):
--   • COUNTER-SKIP gate=IFRAMES-cannot-precede-contact  need=528ms при contactIn=523ms — контра
--     не проходила по бюджету, промахиваясь на 5мс. Это и есть «Ali Counter то работает, то нет».
--   • press уходил за pressDt=417ms до контакта вместо ~110ms → result=LATE, хотя predErr=-1ms,
--     то есть модель предсказания контакта была ТОЧНОЙ, а губил её сетевой lead.
-- ДОКАЗАТЕЛЬСТВО ОТ ОБРАТНОГО: в конце сессии пинг оценился честно (96мс) и диаг сразу показал
-- uplink=110ms = clamp(0.102+0.008) — то есть при верном входе схема работает как задумана.
--
-- Data Ping делаем ОСНОВНЫМ: в диаге именно он совпал с реальностью. GetNetworkPing() остаётся
-- как corroboration и как единственный источник, если Data Ping недоступен.
local getPingRaw = LPH_NO_VIRTUALIZE(function()
	-- Источник A: Player:GetNetworkPing() — ПОЛНЫЙ RTT в секундах (интерпретация самой игры).
	local aRtt
	local okA, v = pcall(function() return LocalPlayer:GetNetworkPing() end)
	-- v ~= v отсекает NaN — ровно та же проверка, что делает игра перед использованием значения.
	if okA and type(v) == "number" and v == v and v > 0 then aRtt = v end

	-- Источник B: Stats Data Ping — RTT в миллисекундах.
	local bRtt
	local okB, ms = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if okB and type(ms) == "number" and ms == ms and ms > 1 then bRtt = ms / 1000 end

	local best
	if bRtt and aRtt then
		-- Оба живы: берём максимум ТОЛЬКО пока источники согласованы — это сохраняет прежний
		-- консервативный запас на джиттер. Если A расходится с B больше чем в PingSourceMaxRatio
		-- раз, он неисправен (в диаге расхождение было 5-8×), и мы обязаны верить B, иначе
		-- один битый источник снова уводит весь планировщик в потолок.
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

-- [V93] Единый неймспейс-таблица для ВСЕГО нового состояния (пинг-пик + ground-truth хитбоксы).
-- ВАЖНО: модуль целиком — одна гигантская функция, а в Luau лимит 200 жи��ых локалов на функцию.
-- Оригинал был впритык к лимиту, поэтому каждое н��вое ��остоян��е держим п��лями ОДНОЙ таблицы
-- (=1 локал), а не десятком отдельных local — иначе CompileError "Out of local registers".
local V93 = {
	-- [V116] РОБАСТНЫЙ МЕДИАННЫЙ ПИНГ. Кольцо сырых сэмплов RTT; getPing() = медиана окна.
	-- Медиана игнориру��т одиночные спайки/пр��валы Data Ping (пилообразный шум) и отслеживае��
	-- устойчивый RTT — без за��ипания на пике (прежний peak-hold) и без петли о��учения.
	-- [V90] FRAME LOOKAHEAD. Планировщик живёт на Heartbeat, поэтому и press, и dodge раньше
	-- срабатывали на ПЕРВОМ кадре ПОСЛЕ дедлайна ⇒ систематическое опоздание [0, dt] со средним
	-- dt/2. На 144 FPS это ~3мс (незаметно), на 20 FPS — до 50мс при окне парри 125мс, отсюда
	-- «скрипт плохо ��аботает на маленьком фпс». frameDt — EMA дельты Heartbeat, lookahead —
	-- сколько времени смотрим вперёд при сравнении с дедлайном (пересчитывается раз в кадр).
	frameDt   = 1/60,
	lookahead = 0,
	-- [V139] ЗАТУХАЮЩИЙ ПИК дельты кадра. EMA описывает средний кадр, а промах про��сходит на
	-- конкретном ДЛИННОМ: пик ловит его с первого раза и отпускает за FrameLookaheadPeakDecay.
	frameDtPeak = 1/60,
	-- [V139] EMA собственной стоимости schedulerStep (сек). `now` берётся в начале Heartbeat, а
	-- press-сравнение исполняется после всей геометрии — эта разница входит в опоздание.
	stepCost  = 0,
	-- [V139] сколько времени осталось до ближайшего press-дедлайна (сек, из прошлого кадра).
	-- Читает vizGate в RenderStepped: пока идёт защита, ESP не отбирает бюджет кадра.
	nearPress = math.huge,
	-- [V140] Клок последней записи nearPress. Значение пишется на Heartbeat, а читается на
	-- RenderStepped — без метки возраста потребитель не может отличить «press реально рядом»
	-- от «планировщик давно не обновлял метрику», и второй случай замораживал ESP навсегда.
	nearPressStamp = 0,
	vizLast   = 0,    -- клок последней перерисовки ESP
	pingBuf   = {},   -- кольцевой буфер сырых сэмплов (сек)
	pingBufN  = 0,    -- сколько сэмплов накоплено (≤ PingWindow)
	pingBufI  = 0,    -- индекс записи (0-based, крутится по PingWindow)
	pingSampleClock = -1,   -- когда клали последний сэмпл
	pingMedTmp = {},  -- scratch для сортировки медианы (переиспользуется)
	-- ground-truth хитбоксы:
	hbFolder = nil,
	sizes = {},                        -- ["M1"]/["M2"] → Vector3 реального размера парта
	hbParams = nil,                    -- OverlapParams (лениво)
	hbChar = nil,
	hbFrame = -1,
	byOwner = {},                      -- Owner.Value → { part, ... } за текущий FrameId
	hbFirstSeen = setmetatable({}, { __mode = "k" }), -- part → first local observation clock
	hbClaimBySid = {},                 -- VictimSwingId → threat/group currently owning that server swing
	hbLiveSid = {},                    -- persistent scratch set for bounded claim cleanup
	-- [V111] PERF:
	-- НЕ отдельными local — лимит 200 живых локалов на функцию (модуль впритык).
	pingCacheClock = -1,
	pingCacheVal   = 0.08,
	-- [V123] PERF: персистентные буферы imminent/cluster-угроз. Раньше schedulerStep делал
	-- `imminent={}` и `cluster={}` КАЖДЫЙ Heartbeat (даже при 0 уг����з) → 2 таблицы-мусора/кад�� →
	-- GC-дёрганье на высоком fps. Переиспользуем, чистим table.clear в начале кадра. Оба живут
	-- ТОЛЬКО внутри кадра (не escape'ят в State/поля угроз — только читаются и ставят th-флаги).
	imminentBuf = {},
	clusterBuf  = {},
	-- [V91/perf] persistent scratch for computeMultiFaceGoal — it used to allocate a fresh
	-- table (plus one sub-table per threatening attacker) on EVERY RenderStepped frame and
	-- throw it away immediately in the common `#t < 2` case.
	faceBuf     = {},
	-- [V132] persistent cluster attacker-seen table (no per-frame allocation)
	seenAttackers = {},
	threatSeen = {},
	interruptSeen = {},
	boxingM2Contacts = { 0.6000000, 1.0500000 }, -- static .anim Hit markers; config confirms count=2
	ownM1Info = { t = "M1", s = "Basic" },
	-- [V139] Переиспользуемый info-рекорд для расчёта тайминга НАШЕЙ M2. Про��одит �� тот же
	-- hitTimeline, что и вражеские угрозы, поэтому автоматически учитывает вариант (Ali
	-- Left 0.53 / Right 0.67), momentum и множитель роста — без второй копии математики.
	ownM2Info = { t = "M2", s = "Basic", mom = false, variant = nil },
	sortByContact = function(a, b) return a.contactAbs < b.contactAbs end,
	-- [V132] reusable RaycastParams for dodge wall-check
	dodgeParams = nil,
	dodgeChar = nil,
}

-- [V116] РОБАСТНЫЙ ��ЕДИАННЫЙ ПИНГ. Прежний EMA+peak-hold ЛАТЧИЛ спай�� (в логе header ping=224
-- при combat-ping=158) → uplink раздувался → жали СЛИШКОМ РАНО. Медиана окна последних сырых
-- сэмплов игнорирует одиночные выбросы В ОБЕ СТОРОНЫ (Data Ping пилит вверх и вниз) и отслеживает
-- устойчивый RTT: один спайк-кадр среди 24 сэмплов НЕ сдвигает медиану, а реально выросший пинг
-- поднимает её за <1с. ��то принципиальная оценка центральной тенденции, не костыль и не обучение.
-- [V111] PERF: getPing() зовётся из uplink() (schedulerStep) И applyFacing (RenderStepped) каждый
-- кадр → мемоизируем: новый сырой сэмпл кладём не ча��е PingSampleGap, медиану пересчитываем только
-- при добавлении сэмпла, между добавлениями отд��ём кэш.
local function getPing()
	local nowc = os.clock()
	if (nowc - V93.pingSampleClock) < (Config.PingSampleGap or 0.03) then
		return V93.pingCacheVal
	end
	V93.pingSampleClock = nowc

	-- добавляем сы��ой сэмпл �� кольцо
	local raw = getPingRaw()
	local win = math.max(3, Config.PingWindow or 24)
	V93.pingBufI = (V93.pingBufI % win) + 1
	V93.pingBuf[V93.pingBufI] = raw
	if V93.pingBufN < win then V93.pingBufN = V93.pingBufN + 1 end

	-- медиана окна (n ≤ 24 → дёшево, и только раз в PingSampleGap, не per-frame)
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

-- [V144/PERF] Зовётся из schedulerStep и dodge-планировщика каждый кадр.
local uplink = LPH_NO_VIRTUALIZE(function()
	-- опираемся на сглаженный getPing(); БЕЗ пов��орного max с сырым спайком (это и раздувало lead)
	local ping = getPing()
	local up = math.clamp(ping * Config.UplinkFactor + Config.UplinkMargin, Config.UplinkMin, Config.UplinkMax)
	-- [V127] LOW-PING LEAD FLOOR (см. Config.LowPingFloor). Компенсируем фиксированную задержку
	-- клиентского конвейера, которую RTT-модель не учитывает. Линейно гаснет к 0 на LowPingThresh,
	-- поэтому на среднем/высоком пинге НЕ влияет (рабочий сетап автора нетронут).
	local thr = Config.LowPingThresh or 0
	if thr > 0 and ping < thr then
		up = up + (Config.LowPingFloor or 0) * (1 - ping / thr)
	end
	return up
end)

-- [V116] Ада��тивный корректор контакта УДАЛЁН. Отравлял между врагами: меди��на predErr копилась
-- по (kind,style), но реальная ошибка доминируется ПИНГОМ конкретного игрока и выбросами (held-
-- анимации) ���� обучившись на одном враге, скрипт ломал тайминг по вто��ому. Предикт снова чисто
-- математический (таймлайн анимации + живой TimePosition), ResidByKS теперь только диагностика.

local function localChar() return LocalPlayer.Character end

-- [V68] FPS: persistent index fn for pcall-safe property reads WITHOUT allocating
-- a new closure every call. The old hot-path pattern `pcall(function() x=o.Prop end)`
-- built a fresh closure per read → with 15+ threats × several reads × 60fps that's
-- thousands of allocations/sec → GC stalls (the FPS drop, not rendering). pcall on a
-- persistent function allocates nothing.
-- [V144/PERF] safeGet — САМАЯ вызываемая функция скрипта: через неё идёт каждое защищённое чтение
-- свойства в геометрии угроз (15+ угроз × несколько чтений × каждый Heartbeat) + весь Viz. Она
-- НЕ была помечена макросом, то есть в обфусцированной сборке каждое такое чтение проходило через
-- интерпретатор Luraph. Это девиртуализация с наибольшим эффектом на кадр во всём файле.
local _index = LPH_NO_VIRTUALIZE(function(o, k) return o[k] end)
-- [V144/PERF] Персистентный аргумент для pcall в steer-ветке Heartbeat (см. там комментарий).
-- Живёт ПОЛЕМ V93, а не новым локалом: главный чанк впритык к лимиту 200 активных локалов Luau
-- (та же причина, по которой scratch-буферы ESP лежат полями Viz).
V93.humMove = LPH_NO_VIRTUALIZE(function(hum, dir) return hum:Move(dir, false) end)
local safeGet = LPH_NO_VIRTUALIZE(function(o, k, default)
	if o == nil then return default end
	local ok, v = pcall(_index, o, k)
	if ok and v ~= nil then return v end
	return default
end)

-- [V68] per-frame HRP cache. localHRP() is called from many hot spots; each call did
-- a FindFirstChild. Cache it once per Heartbeat frame (FrameId bumped in the tick).
-- [V144/PERF] Тоже без макроса: кэш экономил FindFirstChild, но сам вызов оставался
-- виртуализированным, а зовётся он из планировщика, applyFacing и pickTarget каждый кадр.
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
	-- [V98] руки не одеты (кнопка T / unequip) → сервер НЕ примет ни блок, ни парри
	-- (Block.lua:80 треб��ет Equip==true). Кросс-платформенно через атрибут Equip, без T-хука.
	-- Не реагируем вообще, чтобы не жечь бесполезные пресс���� когда физически не ��ожем блокировать.
	if Config.RequireEquip ~= false and c:GetAttribute("Equip") ~= true then
		return false, "Unequip"
	end
	for _, attr in ipairs(HARD_BLOCKERS) do
		if c:GetAttribute(attr) == true then return false, attr end
	end
	local stunned = c:GetAttribute("Stunned") == true
	local cantAny = c:GetAttribute("CantAnything") == true
	if stunned or cantAny then
		-- Block.lua штатно разрешает по��торный Block во время локального parried-stun:
		-- Parried=true обходит Stunned/CantAnything. Прежний гейт требова�� ParryBuffered,
		-- который скрипт нигде не выставлял, поэтому после запаренного AutoPlay-M1 защита молчала.
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

-- [V144/PERF] Фильтр врага: крутится в цикле по ВСЕМ моделям Workspace внутри Viz.pickTarget
-- (каждая ��ерерисовка ESP) и в резолве OUT. Десятки вызовов на кадр, макроса не имел.
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

local function faceDotTo(targetHRP)
	local myHRP = localHRP()
	if not myHRP or not targetHRP or not targetHRP.Parent then return nil end
	local dir = flatDirTo(myHRP.Position, targetHRP.Position)
	if not dir then return 1 end
	local look = myHRP.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then return nil end
	return flatLook.Unit:Dot(dir)
end

-- [V95] Выставить ЦЕЛЬ поворота в единый канал. НЕ пишет HRP.CFrame напрямую (это делает
-- applyFacing в RenderStepped) — так убираем гонку Heartbeat↔RenderStepped и войну писате��ей.
-- hard=true → жёсткий снап (у контакта/в замесе), иначе плавный лерп. holdFor — грейс, сколько
-- держать цель после этого вызова (schedulerStep дёргает каждый Heartbeat, н�� грейс покрывает
-- сам момент контакта и пару кадров после). Velocity-lead УБРАН: сервер валидирует facing на
-- ФАКТИЧЕСКУЮ позици�� атакующего в момент удара, упреждение по скорости уводило прицел вбок
-- (в логах давало face=0.5 BACK на ��трейфя��ем враге) → блок отклонялся.
local function computeMultiFaceGoal()
	if not Config.AutoFace then return nil end
	-- [V91/perf] Cheapest possible bail-out FIRST: multi-face needs at least two live
	-- threats, so count them before touching the character or doing any vector math.
	-- Previously this ran localHRP() + CFrame math + a fresh table every single frame.
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
	-- Persistent buffer + reused entry tables: no per-frame garbage.
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
	for i = #t, n + 1, -1 do t[i] = nil end   -- shrink to the live count
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
local function attackerYawRate(aHRP, flatLook)
	local now = os.clock()
	local rec = FaceTrack[aHRP]
	local rate = 0
	local prevLook, prevPos, prevT = nil, nil, nil
	if rec then
		local dtr = now - rec.t
		if dtr > 1e-3 and dtr < 0.5 then
			local dAng = math.deg(math.acos(math.clamp(rec.look:Dot(flatLook), -1, 1)))
			-- [V160] СГЛАЖИВАНИЕ. Мгновенная покадровая оценка — это НЕ угловая скорость, а шум:
			-- при 60 FPS рывок мышью на 10° за кадр даёт 600°/с. Прежний код отдавал именно её
			-- в экстраполяцию look (willHitMe), и та разворачивала вра��а спиной к нам, отменяя
			-- живую угрозу. EMA по прошлому сглаженному значению даёт физическую скорость
			-- доворота: одиночный рывок её почти не двигает, реальное вращение — поднимает.
			local inst = dAng / dtr
			local prev = rec.rate
			if prev == nil then prev = inst end
			local a = Config.YawRateSmooth or 0.30
			rate = prev + (inst - prev) * a
			prevLook = rec.look
		else
			-- дырка в наблюдении (респавн/стрим) — держим последнюю оценку, не обнуляем в шум
			rate = rec.rate or 0
		end
		-- [V101] позиция/время прошлого кадра — для measured-closing (дельта дистанци��),
		-- ловит дэш-выпады с CFrame-твином, где AssemblyLinearVelocity остаётся ≈0.
		prevPos, prevT = rec.pos, rec.t
		-- [V160/PERF] Переиспользуем запись вместо `FaceTrack[aHRP] = {...}` на КАЖДЫЙ вызов.
		-- Функция зовётся из hitboxGeom по разу на угрозу за кадр: при мультибое это была
		-- отдельная таблица-мусор на угрозу на кадр в том же горячем пути, где файл борется
		-- за миллисекунды до press-дедлайна.
		rec.look, rec.t, rec.pos, rec.rate = flatLook, now, aHRP.Position, rate
	else
		FaceTrack[aHRP] = { look = flatLook, t = now, pos = aHRP.Position, rate = 0 }
	end
	-- prevLook = facing атакующего на ПРОШЛОМ кадре (для детекта з��ака доворота к нам)
	return rate, prevLook, prevPos, prevT
end

-- ��────���───────────────────────��──────────────────���────────────────────────────
-- [V93] GROUND-TRUTH ХИТБОКСЫ — фундамент нового High-режима.
-- Игровой VictimHitboxServiceClient (декомпилирован из дампа) каждый Heartbeat идёт по
-- workspace.Hitboxes: активный удар = BasePart с детьми Owner/AttackName (StringValue) и
-- строковым атрибутом VictimSwingId. Если парт пересекается с нашим персонажем
-- (workspace:GetPartBoundsInBox(part.CFrame, part.Size, {ourChar})) — клиент шлёт серверу
-- VictimHitConfirm вместе с нашим PerfectBlocking. То есть ИСТИННАЯ геометрия удара — сам
-- парт, а не наши догадки про yaw/размах. High опирается на это:
--   • если парт атакующего ��же есть — п��оверяем пе��есечение с нами 1:1 как игра (авторитетно);
--   • пока парт�� нет — предсказываем бок�� РЕАЛЬНЫМ размером (кэш по типу атаки), без trust-
--     к��стылей (point-blank/heavy/drag/latch).
-- Пер-кадровый индекс живых ��артов по в��адельцу (Owner.Value). Скан один ��аз за FrameId,
-- чтобы не обходить папку по разу на каждую угрозу в м��льтибое. Всё состояние — в V93 (см. выше
-- ��ро лимит 200 локалов), новых local тут не заводим.
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

-- Associate one replicated VictimSwingId with one animation threat/group. A same-owner/kind
-- part is not authoritative until claimed: rapid combos overlap for HitboxDuration=0.15s.
-- [V144/PERF] Вызывается из realHitboxHitsMe на КАЖДУЮ угрозу каждый кадр и внутри перебирает
-- живые парты владельца с FindFirstChild/GetAttribute на каждый. Макроса не имело, хотя стоит
-- дороже уже размеченного realHitboxHitsMe, который её и зовёт.
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
				-- A part belonging to this animation cannot predate its detection except for tiny
				-- replication ordering jitter. This rejects a previous combo strike's still-live part.
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

-- true/false only for the exact associated server swing; nil means no authority yet.
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

-- [V74] Return the closest hitbox part for a given owner, plus its distance to us.
-- Used to trigger dodge right when the server hitbox becomes dangerous.
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

-- [V135] Ground-truth alignment. The game only sends VictimHitConfirm after exact overlap;
-- merely being NEAR a part is not a hit. Pulling a contact from `near` created false early
-- M2/dodge reactions. Match Owner + AttackName and snap only on the same overlap predicate.
local syncContactWithHitbox = LPH_NO_VIRTUALIZE(function(th, now)
	if not Config.HitboxDodge then return end
	-- One Boxing hitbox can serve both strikes; never snap s2 to the first part.
	if (th.strike or 1) > 1 then return end
	if th.dodged or th.hitboxSynced then return end
	local part = hitboxNearestPart(th.name, th.kind)
	if not part then return end
	if not th.hitboxSeen then
		th.hitboxSeen, th.hitboxPart = now, part
	end
	if realHitboxHitsMe(th.name, th) == true then
		-- Exact overlap is the game's VictimHitConfirm moment: it is evidence, not a
		-- predictor. Moving the deadline to "now" here was already too late to create a
		-- reliable parry and corrupted outcome matching. Preserve the anim/config deadline.
		th.gtConfirmed, th.hitboxSynced = true, true
	end
end)

-- ═══════════════════ [V161] ЗАЩИТА ОТ OVERSHOOT ПРЕДСКАЗАННОЙ ПОЗИЦИИ ═══════════════════
-- Предсказанная позиция атакующего служит НАЧАЛОМ ОТСЧЁТА для вектора «атакующий→я». Если lead
-- проносит её сквозь нашу позицию, этот вектор меняет знак и вся угловая геометрия (facing, depth)
-- инвертируется — атакующий в упор выглядит стоящим спиной. Поэтому lead ограничивается ЦЕЛИКОМ,
-- как вектор, а не по отдельной компоненте (см. подробный разбор в вызывающем коде ниже).
local clampLeadToVictim = LPH_NO_VIRTUALIZE(function(lead, aPos, mePos)
	local d = Vector3.new(aPos.X - mePos.X, 0, aPos.Z - mePos.Z).Magnitude
	local maxLead = d * (Config.WillHitLeadFrac or 0.90)
	if lead.Magnitude <= maxLead then return lead end
	if maxLead <= 1e-3 then return Vector3.zero end
	return lead.Unit * maxLead
end)

local hitboxGeom = LPH_NO_VIRTUALIZE(function(th)
	-- [V97/PERF] PER-FRAME MEMO. This is the single most expensive function in the per-threat hot
	-- path (~6 Vector3.new, ~7 .Magnitude, ~5 .Unit — every .Magnitude/.Unit is a sqrt — plus dots
	-- and a styleForward lookup). It was being computed TWICE per frame for the SAME threat:
	-- once from willHitMe and again from activeRestrictZone (RestrictZone is on by default).
	-- Same inputs → same outputs within a frame, so cache on FrameId exactly like realHitboxHitsMe
	-- already does. Pure perf: no behaviour change.
	if th.geomFrame == FrameId then
		return th.geomC, th.geomF, th.geomP, th.geomL
	end
	local aHRP = th.attackerHRP
	if not aHRP or not aHRP.Parent then th.geomFrame = FrameId; th.geomC = nil; return nil end
	local now  = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local aPos = aHRP.Position
	local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
	-- [V67] кап смещения о�� velocity: у стр��йф��щего врага полная ��кс��раполяция
	-- уводит центр хитбокса вбок и ломает willHitMe (ложный не��атив в упор).
	local lead = Vector3.new(aV.X * tHit, 0, aV.Z * tHit)
	-- [V91] РАЗДЕЛЬНЫЙ кап: сближение (toward us) ведём до WillHitCloseCap (лунж/��аскок реально
	-- закрывает дистанцию — иначе бо��с отсекал их как far �� High-миссы), strafe — до
	-- WillHitLatCap (узко, иначе центр бокса уезжает вбок → ложный негатив в упор).
	local meG = localHRP()
	if meG then
		local toMeG = Vector3.new(meG.Position.X - aPos.X, 0, meG.Position.Z - aPos.Z)
		if toMeG.Magnitude > 0.05 then
			toMeG = toMeG.Unit
			local leadDot  = lead:Dot(toMeG)               -- [V97/PERF] computed ONCE, reused below
			local closeAmt = leadDot                       -- >0 = идёт на нас (по velocity)
			-- [V102] ИЗМЕРЕННОЕ сближение (студ/с) кадр-к-кадру. AssemblyLinearVelocity у
			-- бегающего игрока часто занижен/шумит (Humanoid move, CFrame-твины) → predA не
			-- доводи��ся до нас и geom-бокс мазал по врагу, который вбегает и бьёт «на возврате».
			-- Берём МАКС velocity- и измеренног�� сближения → бокс честно доводится к контакту.
			if th.prevPos and th.prevPosT then
				local dtp = now - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx   = th.prevPos.X - meG.Position.X
					local pdz   = th.prevPos.Z - meG.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					-- [V97/PERF] plain sqrt on the two components we already have: the old line built
					-- a throwaway Vector3 just to read .Magnitude (same sqrt, extra allocation).
					local cdx   = aPos.X - meG.Position.X
					local cdz   = aPos.Z - meG.Position.Z
					local curD  = math.sqrt(cdx * cdx + cdz * cdz)
					local measClose = (prevD - curD) / dtp      -- >0 = приближается
					if measClose > 0 then closeAmt = math.max(closeAmt, measClose * tHit) end
				end
			end
			-- [V97/PERF] reuse the dot computed above (closeAmt started as exactly this value);
			-- `lead` and `toMeG` are unchanged in between, so recomputing it was pure waste.
			local latVec   = lead - toMeG * leadDot            -- боковая составляющая (по velocity)
			local latCap   = Config.WillHitLatCap or 1.5
			if latVec.Magnitude > latCap then latVec = latVec.Unit * latCap end
			-- [V109] КОРЕНЬ High-бага «враг подходит и бьёт — скрипт не вовремя, как будто вне
			-- радиуса»: closeAmt капился жёстко WillHitCloseCap(6.5). Реально ВБЕГАЮЩИЙ враг за
			-- время замаха (tHit до ~0.45с при скорости бега 16-28 ст��д/с) закрывает 8-12 студов —
			-- 6.5 обрезал → predA НЕ доводился до нас → geom-бокс мимо → willHitMe=false → NO-PRESS,
			-- а когда враг физически в радиусе, контакт уже неминуем → LATE. ��однял cap до 12. НО
			-- предикт НЕ должен «про��какивать» за нас (иначе центр бокса уедет за спину) → clamp
			-- дополнительно по фактической дистанции до нас (останавливаем predA чуть НЕ доходя).
			-- Ложняков ��е добавляет: в High всё ещё держат facing-гейт (aimLook·toMe) и реальный
			-- размер парта — вбегающий, но целящийся НЕ в нас, отсекается по facing.
			local distToMe = Vector3.new(aPos.X - meG.Position.X, 0, aPos.Z - meG.Position.Z).Magnitude
			local closeCap = math.min(Config.WillHitCloseCap or 12, distToMe * 0.95)
			closeAmt = math.clamp(closeAmt, 0, closeCap)
			lead = toMeG * closeAmt + latVec
			-- ═══════ [V161] КЛАМП ПО ВЕКТОРУ, А НЕ ПО ОДНОЙ ЕГО КОМПОНЕНТЕ ═══════
			-- Кламп выше ограничивает ТОЛЬКО closeAmt (осевую часть), после чего строка ниже
			-- прибавляет latVec — до WillHitLatCap=1.5 студа боком. Итоговый |lead| снова
			-- превышает дистанцию до нас, и predA проносится СКВОЗЬ нашу позицию. Для дальнего
			-- врага это незаметно, но в упор — фатально, потому что origin (=predA) служит
			-- началом отсчёта для ox,oz на строке ~1778, и знак вектора «атакующий→я»
			-- переворачивается. Тогда faceToMe становится отрицательным при ЛЮБОМ реальном look,
			-- и widen-only фикс V160 бессилен: он сравнивает два look'а, а испорчен ORIGIN.
			-- Подпись в диаге — жёсткая корреляция знака depth с дистанцией:
			--   dist2d=0.95 → depth=-0.90 | 1.64 → -0.97 | 1.87 → -1.19 | 5.74 → -5.70
			--   и наоборот 9.23 → +9.15 | 12.63 → +12.04
			-- Именно это давало «враг бьёт в упор, а скрипт игнорирует удар»: строка 133 диага —
			-- dist2d=1.64, reach=9.86 (reach-ok!), faceToMe=-0.59 → BACK-FACING → MISS с proof=NO.
			-- А второй удар комбо (contact=368мс против 282мс у первого) успевал получить
			-- server-overlap и потому проходил — ровно наблюдаемое «реагирует только на второй».
			-- Оставляем зазор: predA обязан остановиться НЕ ДОХОДЯ до нас, как и задумано в V109.
			lead = clampLeadToVictim(lead, aPos, meG.Position)
		else
			local cap = Config.WillHitVelCap or 2.0
			if lead.Magnitude > cap then lead = lead.Unit * cap end
			lead = clampLeadToVictim(lead, aPos, meG.Position)
		end
	else
		-- Это ветка `meG == nil` (наш HRP недоступен). Клампить lead относительно нашей позиции
		-- здесь нечем и не нужно: обращение к meG.Position уронило бы функцию.
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
	-- [V91] + Л��НЖ. Хитбокс рожд��ется в позиции атакующего НА МОМЕНТ КОНТАКТА, а StepForward
	-- (LinearVelocity, 0.14с в начале замаха) к этому моменту уже гарантированно доехал.
	-- Считая реч от ТЕКУЩЕЙ позици��, мы обязаны прибавить эти студы, иначе вбегающий/лунжащий
	-- враг стабильно уходит в predicted-miss (зам��р: p75=8, p95=11 студов при рече 8.2).
	-- Ali: M1 удары 1 и 3 = +1.5, M2 = +2. Для стилей без ступа функция вернёт 0 (поведение
	-- не меняется), поэтому правка безопасна для всех остальных.
	-- ВАЖНО: только в High. В Low `forward` задаёт ПОЛОСУ [forward-halfD, forward+halfD], и
	-- сдвиг наружу отсекал бы врага, стоящего В УПОР (depth < forward-halfD) — то есть лечили бы
	-- дальних, ломая бли��них. В High forward входит только в reach (верхнюю границу), где
	-- прибавка строго корректна. Low и так помечен устаревшим ([V140], 8.5% точности).
	if styleStepForward and (Config.AccuracyMode or "High") == "High" then
		local st = styleStepForward(th.style, th.kind, th.combo)
		if type(st) == "number" and st > 0 then
			forward = forward + st
			th.geomStep = st
		end
	end

	local trackedRate, prevLook, prevPos, prevT = attackerYawRate(aHRP, flatLook)
	-- стэшим на th для drag-детекта в willHitMe (знак доворота = prevLook vs текущий facing)
	th.yawRate  = trackedRate
	th.prevLook = prevLook
	th.prevPos  = prevPos   -- [V101] для measured-closing (лунж-д��тект тяжёлых)
	th.prevPosT = prevT


	local center = predA + flatLook * forward
	-- [V97/PERF] fill the per-frame memo (see the guard at the top of this function)
	th.geomFrame, th.geomC, th.geomF, th.geomP, th.geomL = FrameId, center, forward, predA, flatLook
	return center, forward, predA, flatLook
end)

-- [V136] Recognition is one model, not a collection of trust/radius overrides.
-- The real game recognises a hit only from Owner + AttackName + VictimSwingId + exact overlap.
-- Before its part exists, Low uses the current oriented hitbox; High projects that same box to
-- the canonical server contact. Neither mode ever returns true merely because an M2 is nearby.
local willHitMe = LPH_NO_VIRTUALIZE(function(th)
	local myHRP, aHRP = localHRP(), th.attackerHRP
	if not myHRP then return Config.FilterFailSafe end
	if not aHRP or not aHRP.Parent then
		th.recognitionSource = "no-hrp"
		return false
	end
	if math.abs(myHRP.Position.Y - aHRP.Position.Y) > (Config.MaxHeightDiff or 12) then
		th.recognitionSource = "y-diff"
		return false
	end

	local mode = Config.AccuracyMode or "Low"
	-- A matching live part is authoritative only on positive overlap. A negative sample is
	-- pending because VictimHitboxService repeats the same overlap query every Heartbeat.
	local gt = realHitboxHitsMe(th.name, th)
	if gt == true then
		th.gtConfirmed, th.trustedHit = true, true
		th.recognitionSource = "server-overlap"
		return true
	elseif gt == false then
		-- VictimHitboxService retries this same live part every Heartbeat. `false` only
		-- means "not overlapping on this frame"; it is not a final miss. Continue with
		-- pre-contact geometry while the associated SID remains live.
		th.recognitionSource = "server-pending"
	end

	local _, forward, predA, rawLook = hitboxGeom(th)
	if not predA or not rawLook then return Config.FilterFailSafe end
	local now = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local look, origin = rawLook, aHRP.Position
	local predLook = nil
	if mode == "High" then
		origin = Vector3.new(predA.X, aHRP.Position.Y, predA.Z)
		-- Preserve the observed yaw SIGN. The old abs(rate)+turn-toward-us model invented
		-- turns toward us for every rotating/back-facing enemy, then latched the false threat.
		local angY = safeGet(aHRP, "AssemblyAngularVelocity", Vector3.zero).Y or 0
		local signedRate = angY
		if th.prevLook and (th.yawRate or 0) > math.abs(math.deg(angY)) then
			local crossObserved = th.prevLook.X * rawLook.Z - th.prevLook.Z * rawLook.X
			signedRate = math.rad(th.yawRate or 0) * (crossObserved >= 0 and 1 or -1)
		end
		if math.abs(signedRate) > 0.01 and tHit > 0 then
			-- [V160] КАП ПОВОРОТА (см. Config.YawTurnCapDeg). Прежний кламп стоял на ±π, то есть
			-- экстраполяции Р��ЗРЕШАЛОСЬ развернуть атакующего спиной к нам. При tHit=0.6 (M2) для
			-- этого хватало 300°/с, при tHit=0.315 (M1) — 571°/с; и то и другое обычный рывок
			-- мышью. Отсюда faceToMe=-1.00 РОВНО в диаге — подпись упора в π.
			-- Замах не длится столько, чтобы игрок равномерно докрутился на пол-оборота;
			-- ограничиваем предсказанный доворот физически осмысленной величиной.
			local cap = math.rad(Config.YawTurnCapDeg or 30)
			local turn = math.clamp(signedRate * tHit, -cap, cap)
			local c, s = math.cos(turn), math.sin(turn)
			local rot = Vector3.new(rawLook.X * c - rawLook.Z * s, 0, rawLook.X * s + rawLook.Z * c)
			if rot.Magnitude > 0.05 then
				predLook = rot.Unit
				look = predLook
			end
		end
	end
	local sz = V93.sizes[th.kind]
	-- Do not extrapolate the local Humanoid's instantaneous velocity across the whole windup.
	-- TRACE 385833 proved that this regression moved recognition from +5ms to +250..430ms while
	-- server overlap/contact stayed on the normal timeline. Humanoid input velocity is not a
	-- ballistic trajectory; compare the predicted attacker box against our live position each
	-- Heartbeat instead. Step-in remains handled by attacker prediction above.
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
		-- [V137] WIDE recognition. DIAG 386874 proved the strict oriented box (depth band +
		-- narrow side) rejected real angled/rotating hits: 65% of misses were predicted-miss /
		-- server-pending, and success only happened when recognition fired early (~55ms) vs late
		-- (~134ms). The server hitbox overlap above already gives the authoritative TRUE; this
		-- pre-contact predicate only needs to be EARLY and INCLUSIVE, not geometrically exact.
		-- Model: attacker is within reach of us AND is roughly facing us. This mirrors the old
		-- working "distance + animation + rough facing" recognition, without radius/heavy trust.
		local dist2d = math.sqrt(ox * ox + oz * oz)
		local reach = forward + halfD + (Config.HighReachPad or 2.0)
		-- (ox,oz) = victim - attackerOrigin, i.e. the attacker->victim direction. A real swing
		-- that connects has the attacker's look pointing toward us, so look·(attacker->victim)
		-- is near +1. Loose gate: accept unless clearly back-facing.
		local toMeX, toMeZ = ox, oz
		if dist2d > 0.05 then toMeX, toMeZ = ox / dist2d, oz / dist2d else toMeX, toMeZ = look.X, look.Z end
		local faceToMe = look.X * toMeX + look.Z * toMeZ
		-- [V160] ЭКСТРАПОЛЯЦИЯ ТОЛЬКО РАСШИРЯЕТ. Этот предикат по своему же назначению (коммент
		-- V137 выше) обязан быть РАННИМ и ВКЛЮЧАЮЩИМ — авторитетный TRUE выдаёт server overlap,
		-- а здесь достаточно «враг в рече и примерно смотрит на нас». Предсказанный доворот же
		-- РЕЗАЛ распознавание: шумная ротация уводила look от нас, faceToMe уходил в минус,
		-- threatens становился false и press-окно не обрабатывалось (диаг: реальный M2 в 5 студах
		-- получал BACK-FACING при faceToMe=+0.95 по сырому вектору).
		-- Теперь берём ЛУЧШИЙ из двух: если хоть одно из направлений — наблюдаемое сейчас или
		-- предсказанное к контакту — смотрит на нас, угроза остаётся угрозой.
		if predLook and Config.YawWidenOnly ~= false then
			local rawFace = rawLook.X * toMeX + rawLook.Z * toMeZ
			if rawFace > faceToMe then faceToMe = rawFace end
		end
		th.geomFaceToMe = faceToMe
		local faceFloor = Config.HighFaceFloor or -0.15
		hit = (dist2d <= reach) and (faceToMe >= faceFloor)
	else
		-- [V160] Low-режим facing не считает. Обязательно гасим значение, иначе GEOM-REJECT
		-- напечатает faceToMe, оставшийся с прошлого High-кадра, и диаг снова начнёт врать.
		th.geomFaceToMe = nil
		hit = depth >= (forward - halfD) and depth <= (forward + halfD) and side <= halfW
	end

	-- [V154/GEOM-STICKY] В diag доказанная атака сначала имела predicted-overlap, затем один
	-- промежуточный OUT-OF-REACH снимал её на весь критический кадр и press уходил на +140..235мс.
	-- Защёлка не расширяет range для новых атак: она появляется только после реального overlap у
	-- serverProven свинга и живёт лишь до его contact grace. Feint/stale/neutralized удаляются
	-- scheduler раньше и эту ветку не проходят.
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
		-- [V154] Не перетирать sticky-причину обычным `predicted-overlap`: иначе следующий diag
		-- снова скроет тот промежуточный veto, ради которого защёлка сработала.
	elseif gt == false and not hit then
		th.recognitionSource = "server-pending+predicted-miss"
	else
		th.recognitionSource = hit and (mode == "High" and "predicted-overlap" or "current-overlap")
			or (mode == "High" and "predicted-miss" or "current-miss")
	end
	if not hit then th.offTarget = true end
	-- [V91] ДИАГНОСТИКА ОТКАЗА — закрываем сл��пое пятно логов.
	-- Было: TRACE-GEOM пишется ТОЛЬКО когда threatens==true (в scheduler, под `if threatens and
	-- not th.firstThreatClock`), поэтому у отвергнутых угроз в диаге не было НИ ОДНОЙ ци��ры —
	-- строка MISS сообщала лишь «geometry-rejected source=predicted-miss». По трём диагам это
	-- 63/80/123 промахов, т.е. крупнейшая категория, и причину нельзя был�� увидеть.
	-- Дополнительно: в режиме High решение принимают dist2d/reach/faceToMe, а TRACE-GEOM печатает
	-- поля Low-режима (depth/range/side) — то есть даже для распознанных угроз в логе лежали НЕ те
	-- величины, по которым реально принято решение. Теперь пишем именно решающие.
	if not hit and Config.DeepDiag and not th.geomRejLogged then
		th.geomRejLogged = true
		local dist2d = math.sqrt(ox * ox + oz * oz)
		local reachD = forward + halfD + (Config.HighReachPad or 2.0)
		-- [V160] Печатаем РЕШАЮЩИЙ facing (уже с учётом widen-only), а не только предсказанный:
		-- прежний лог показывал развёрнутый экстраполяцией вектор, из-за чего отказ выглядел
		-- как «враг стоит спиной», хотя сырое направление смотрело прямо на нас.
		local f2m = th.geomFaceToMe
		if f2m == nil then
			f2m = 1
			if dist2d > 0.05 then f2m = (look.X * ox + look.Z * oz) / dist2d end
		end
		diagPush(("GEOM-REJECT t=%.3f %s %s(%s) c%s v%s mode=%s dt=%+.0fms | dist2d=%.2f reach=%.2f (fwd=%.2f step=%.2f halfD=%.2f pad=%.2f) %s | faceToMe=%+.2f floor=%+.2f %s | depth=%.2f side=%.2f/%.2f")
			:format(now, tostring(th.name), tostring(th.kind), tostring(th.style),
				tostring(th.combo or "?"), tostring(th.variant or "-"), tostring(mode),
				((th.contactAbs or now) - now) * 1000,
				dist2d, reachD, forward - (th.geomStep or 0), th.geomStep or 0, halfD,
				Config.HighReachPad or 2.0,
				(dist2d > reachD) and "OUT-OF-REACH" or "reach-ok",
				f2m, Config.HighFaceFloor or -0.15,
				(f2m < (Config.HighFaceFloor or -0.15)) and "BACK-FACING" or "facing-ok",
				depth, side, halfW))
	end
	return hit
end)

local function nextCombo(attacker)
	local now = os.clock()
	local c = ComboState[attacker]
	-- [V139/BUG] `isNew` истинно ДВУМЯ путями: (а) ключа нет, (б) ключ есть, но комбо протухло
	-- (> COMBO_RESET). Раньше _count инкрементился в ОБОИХ случаях, хотя новый ключ появляется
	-- только в (а). У любого врага, который бьёт с паузами > 1.55с — то есть у любого реального
	-- игрока — счётчик рос БЕЗ роста таблицы, навсегда перевешивал порог 64, и с этого момента
	-- КАЖДЫЙ свинг гонял полный pairs-обход ComboState. Тихая O(n)-деградация на пустом месте,
	-- прямо в горячем пути детекта. Считаем только настоящее появление ключа.
	local isFresh = (c == nil)
	local isNew = isFresh or (now - c.last) > COMBO_RESET
	if isNew then c = { idx = 0, last = now } end
	c.idx  = (c.idx % 4) + 1
	c.last = now
	ComboState[attacker] = c
	-- [V73] FPS: cap stale combo-state to avoid unbounded growth across many players
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
		-- [V159/DODGE-REVERT] require(Evasive) удалён вместе с нативным вызовом доджа: модуль
		-- больше никем не читается, а держать ссылку на чужой upvalue-набор, которым уже
		-- управляет movement.lua, — тот самый конфликт двух источников истины.
		-- [V132] CombatPingAnimUtils: реальная скорость аним��ции M2/M1 затормаживается на пинге
		-- (PingAnimSpeedMultiplier), поэтому контакт прилетает позже, чем base / aMult.
		local pauMod = shared and shared:FindFirstChild("Utils") and shared.Utils:FindFirstChild("CombatPingAnimUtils")
		if pauMod then GameData.pau = require(pauMod) end
		-- [V71] CombatUtils.GetAttackSpeedMultiplier(height): игра делит задержку удара
		-- на этот множитель (см. GetScaledHitboxDelay). Нужен, чтобы предсказывать
		-- реальную скорость атаки быстрых (низкорослых) врагов.
		local pkgs = ReplicatedStorage:FindFirstChild("Packages")
		local cuMod = pkgs and pkgs:FindFirstChild("CombatUtils")
		if cuMod then GameData.cu = require(cuMod) end
	end)
	-- [V90] ФИЗИЧЕСКИЕ КОНСТАНТЫ ДОДЖА — ИЗ ИГРЫ, А НЕ ИЗ СОХРАНЁННОГО КОНФИГА.
	-- Config.IFrameDur сидит на UI-слайдере "i-Frame Window", поэтому авто-восстановление
	-- настроек прошлой сессии молча затирало бы и�� реальную Evasive.IFrameDuration и ломало
	-- центрирование доджа (ровно тот класс регрессий, который потом не отладить по логам).
	-- Берём авторитетное значение из живого CombatConfig; слайдер остаётся ручным override.
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
		-- ═══════ [V147] ЖИВЫЕ КУЛДАУНЫ ДОДЖА — ОНИ НУЖНЫ ДЛЯ ГЕЙТА ПОД ГРАНТОМ ═══════
		-- В дампе это ДВА РАЗНЫХ числа, и путать их нельзя:
		--   CombatConfig.Evasive.Cooldown = 1.5              — базовый кулдаун дэша, из него
		--       syncCooldownFromServer считает u6 (Evasive:92-95);
		--   CombatConfig.ClientPredict.Evasive.Cooldown = 2  — кулдаун клиентского предсказания,
		--       именно ему соответствовал хардкод Config.DodgeCooldown = 2.05.
		-- Держим оба живыми: ��ардкод молча разойдётся с игрой при первом ж�� балан��ном п��тче.
		if type(ev) == "table" and type(ev.Cooldown) == "number" and ev.Cooldown > 0 then
			GameData.evCooldown = ev.Cooldown
		end
		if cpe and type(cpe.Cooldown) == "number" and cpe.Cooldown > 0 then
			GameData.evPredictCooldown = cpe.Cooldown
		end
		if type(ev) == "table" and type(ev.DashDuration) == "number" and ev.DashDuration > 0 then
			GameData.dashDuration = ev.DashDuration
		end
		-- Реальное окно перфект-блока (Block.PerfectBlockWindow=0.125) — для диагностики
		-- и как верхняя граница осмысленного PerfectWindow.
		local bl = GameData.cfg and GameData.cfg.Block
		if bl and type(bl.PerfectBlockWindow) == "number" then
			GameData.perfectWindow = bl.PerfectBlockWindow
		end
	end)
end

-- [V151] getPingAnimMult (V132) УДАЛЁН: за всё время не был вызван ни разу — ноль ссылок.
-- Держать его = держать регистр главного чанка, а мы вылезли за лимит Luau 200 и получили
-- "out of local registers". Множитель пинга при необходимости берётся напрямую через
-- GameData.pau.GetPingAnimSpeedMultiplier там, где он реально понадобится.

-- [V71] множитель скорости атаки конкретного АТАКУЮЩЕГО. Задержка удара в игре =
-- base / mult (GetScaledHitboxDelay). mult зависит от роста персонажа: низк��й → до
-- 1.15 (бьёт на 15% быстрее), высокий → 0.85. Раньше мы всегда слали 1 → быстрые
-- враги давали LATE. Сначала пр��бу��м родные функции игры (future-proof при апдейтах),
-- потом ��олбэк на задокументированную формулу от атрибута Height.
-- [V120] WEAK KEYS: к��ш по МОДЕЛИ (Instance). Без weak-ключа каждый респавн/уход игрока = новый
-- перманентный ключ → таблица растёт бесконечно И держит мёртвые модели от GC (утечка памяти,
-- со временем GC-дёр��анье → фризы → п��здние нажатия). __mode="k": запись авто-удаляется, когда
-- модель становится собираемой. На корректность не влияет (чтение ��сегда п�� ЖИВОЙ модели).
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
		-- фолбэк: атрибут Height + формула из дампа CombatUtils
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

-- [V97/PERF] styleOf ran two pcalls with INLINE closures on every call, and it is called per
-- threat per frame (through styleForward/hitboxGeom). Both closures are now persistent helpers,
-- and the result is cached per character with a short TTL so a mid-fight style swap still lands.
-- Weak keys: the entry dies with the character model, no manual eviction needed.
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
-- [V85] id защитных анимаций (block/guard/parry/deflect/perfect). Некоторые стили имеют
-- защитные анимации не должны попадать в статический attack registry.
-- и парри срабатывал на ЧУЖОЙ блок. Собираем их явно и жёстко ис��лючаем из д��текта угроз.
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
					-- [V109] СТИЛЕВАЯ папка = содержит канонические удары (M2 / 1stM1 / 2ndM1). Так мы
					-- отличаем боевой ��тиль (Karate/Boxing/Kure/Striker/…) от НЕ-атак��ющих папок
					-- Combat (Dodges = дэши, Grappling = грэб-секвенции): и�� авто-классифицировать в
					-- атаки НЕЛЬЗЯ (ложные срабатывания на дэш/захват). Проверка по составу папки —
					-- независима от точного имени папки в рантайме.
					local isStyleFolder = styleFolder:FindFirstChild("M2") ~= nil
						or styleFolder:FindFirstChild("1stM1") ~= nil
						or styleFolder:FindFirstChild("2ndM1") ~= nil
					for _, child in ipairs(styleFolder:GetChildren()) do
						local lname     = child.Name:lower()
						local defensive = looksDefensive(child.Name)
						-- [V108] hurt-reaction / success flashes (1stEHit, M2EHit, M2Success, BlockHit)
						-- are NOT incoming attacks — exclude them (иначе "M2EHit"/"M2Success" ловили "M2"
						-- и парри срабатывал на реакцию/успех врага, а не на удар).
						local reaction  = (lname:find("ehit") or lname:find("success")
							or lname:find("blockhit")) ~= nil
						-- idle / walk / run / dash — не атаки (в стилевой папке есть Idle/Walk)
						local benignMove = (lname == "idle" or lname == "walk" or lname == "run"
							or lname:find("dash")) ~= nil
						local kind = nil
						if not defensive and not reaction and not benignMove then
							kind = kindFromName(child.Name)
							-- [V109] КОРЕНЬ «тяжёлой/скилла нет в логе, скрипт её не видит»: ЛЮБОЙ удар
							-- внутри боевого стиля с НЕСТАНДАРТНЫМ именем (не M1/M2 — напр. Striker "Crit",
							-- Kure "6to15_CritStartup" или будущая «крутилка ногами») раньше давал kind=nil →
							-- анимка раньше не попадала в attack registry → детект ГЛУШИЛ её насовсем → нет
							-- угрозы → ни блока, ни доджа, ни interrupt (юзер: «скрипт даже не атакует»).
							-- Теперь любая не-защитная / не-реакционная / не-idle анимка боевого стиля = SKILL.
							-- Ловится по keyframe-таймлайну (hitTimelineBase). Ложняков нет: реакции/блок/
							-- idle/walk/dash уже и��ключены, �� папка гарантир��ванно боевая (есть M1/M2).
							-- Список keyword'ов больше не нужен — покрываем ВСЕ текущие и ��удущие спец-удары.
							if not kind and isStyleFolder then kind = "SKILL" end
						end
						local id = animIdOf(child)
						if id and defensive then BlockIds[id] = true end
						if kind and id then
							AttackIds[id] = {
								kind = kind,
								combo = (kind == "M1") and comboFromName(child.Name) or nil,
								name = child.Name,
								-- CombatConfig.GetStyleM2HitboxDelay(style, true) выбирает
								-- HakariMomentumM2HitboxDelay=0.62 вместо обычных 0.59.
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
							-- [V108] спец-атака (крит/финишер) где угодно в дереве → SKILL, НЕ benign,
							-- чтобы дете��т её видел. Реакции/успехи (ehit/success) остаются benign.
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

-- [V90] РАЗРЕШЕНИЕ M2-ВАРИАНТА. Ali (и любой будущий стиль с M2Variants) держит НЕСКОЛЬКО
-- тяжёлых с РАЗНОЙ HitboxDelay п��д одним kind="M2". Игра выбирает вариант третьим аргументом
-- GetStyleM2HitboxDelay(style, momentum, variantId); скрипт его не передавал вообще, поэтому
-- ВСЕГДА получал базовую Styles.<style>.M2HitboxDelay (для Ali это Left=0.53) и промахивался
-- на 140мс по Right=0.67. Сопоставляем ИМЯ проигранной анимации с полем .Anim каждого варианта
-- живого конфига ⇒ работает и для стилей, которых ещё нет в LEGACY.
-- Кэш и функция живут ПОЛЯМИ GameData: модуль — одна гигантская функция, а в Luau лимит
-- 200 живых локалов на функцию, новые top-level local тут заводить нельзя.
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
			-- 1) точное совпадение по .Anim (авторитетно: ровно то, что читает игра)
			for id, v in pairs(vs) do
				if type(v) == "table" and v.Anim == animName then out = id; return end
			end
			-- 2) имя ан��мации содержит id варианта ("M2Right" ⊃ "Right")
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

-- [V144/PERF] Резолв инфы об атаке н�� каждый распо��нанный удар (зо��ётся из onAttack и из
-- AnimationPlayed). Без макроса шёл через интерпретатор.
local resolveInfo = LPH_NO_VIRTUALIZE(function(id, model)
	local entry  = AttackIds[id]
	if not entry then return nil end
	local legacy = LEGACY_ATTACKS[id]
	local kind = entry.kind
	local rk = registryKind and registryKind(model, id)
	if rk == "M1" or rk == "M2" then kind = rk end
	local style = styleOf(model) or (legacy and legacy.s) or "Basic"
	-- [V91] ВАРИАНТ ТЯЖЁЛОЙ — три источника по убыванию авторитетности:
	--  1) АТРИБУТ M2VariantId на персонаже атакующего. Сервер выставляет его сам и реплицирует
	--     (дамп M2_ModuleScript:1633 читает именно его через GetAttribute). Это ��ер-свинговая
	--     серверная истина — её нельзя подделать чужим клиентом.
	--  2) ИМЯ проигранной анимации ↔ ��оле .Anim варианта в кон��иге (Ali: "M2"→Left, "M2Right"→Right).
	--  3) Статический legacy-хинт по animId.
	-- Как игра выбирает вариант (дамп CombatStepUtils.ResolveM2VariantId): по УГЛУ ДВИЖЕНИЯ
	-- атакующего — deg = atan2(dot(move,Right), dot(move,Look)); Left если не движется или
	-- -112.5 < deg <= 67.5, иначе Right. Считается на клиенте атакующего И на сервере
	-- независимо, поэтому атрибут появл��ется чуть позже анимации — отсюда порядок 1→2→3.
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
		id    = id,                -- [V90] нужен для legacy-фолбэка по конкретному варианту
		hit   = entry.hit,
		contacts = (kind == "M2" and string.lower(style) == "boxing") and V93.boxingM2Contacts or nil,
		combo = entry and entry.combo or (legacy and legacy.c) or nil,
		mom   = (entry and entry.mom) or (legacy and legacy.mom) or false,
		name  = entry and entry.name or nil,
		variant = variant,
	}
end)

-- базовая задержка удара в "speed-1" секундах (без м��ожителя скорости атаки).
local function hitTimelineBase(info, combo)
	if info.t == "SKILL" then
		if info.hit and info.hit > 0 then return info.hit end
		return 0.35
	end
	if info.t == "M2" then
		loadGameModules()
		local cfgv, multi = nil, 1
		if GameData.cfg then
			-- [V90] ТРЕТИЙ АРГУМЕНТ (variantId) — КОРН��ВОЙ ФИКС ALI.
			-- Игровая сигнатур��: GetStyleM2HitboxDelay(style, hakariMomentum, variantId).
			-- Раньше variantId не передавался ⇒ для Ali всегда возвращался Left(0.53), а Right(0.67)
			-- прилетал на 140мс позже ⇒ блок жался слишком рано ⇒ ragdoll-вариант пробивал всегда.
			local ok, d = pcall(function()
				return GameData.cfg.GetStyleM2HitboxDelay(info.s, info.mom, info.variant)
			end)
			if ok and type(d) == "number" then cfgv = d + WINDUP_EXTRA end
			-- multi-hit count (Boxing M2MultiHitCount=2): the meaningful contact is a LATER
			-- strike, so the bare first-hit config delay underestimates the block window.
			local okc, mc = pcall(function() return GameData.cfg.GetStyleNumber(info.s, "M2MultiHitCount", 1) end)
			if okc and type(mc) == "number" then multi = mc end
		end
		if not cfgv then
			-- [V90] legacy-фолбэк тоже стал вариант- и momentum-осведомлённым: приоритет
			-- 1) точн��я задержка варианта из LEGACY_ATTACKS (Ali Right=0.67 vs Left=0.53),
			-- 2) momentum-база (hakari 0.48), 3) обычная база стиля.
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
		-- [V124] КОНФИГ — авторитетный источник тайминга M2 для О��НОhitовых стилей:
		-- GetStyleM2HitboxDelay = ровно та задержка, что сервер делит на mult роста
		-- (GetScaledHitboxDelay: delay/mult). Диаг: Basic M2HitboxDelay=0.525, attacker
		-- aMult=1.09 → 0.525/1.09 = 482мс, measured=485мс (ошибка 3мс). Раньше брали
		-- math.max(cfgv, info.hit) БЕЗУСЛОВНО → ��аркер анимации "Hit" (617мс) перебивал конфиг
		-- и мы жали блок на 130мс позже (predErr=-128ms LATE → HIT). Теперь маркер-страховка
		-- п��именяется ТОЛЬКО к ��ультиhit-стилям (Boxing), где реальный значимый контакт ~749мс
		-- и голый первый удар занижает окно. Одноhitовые (Basic/Capoeira/…) = чистый конфиг.
		if multi > 1 and info.hit and info.hit > 0 then
			-- [V74] Boxing M2 multi-hit: the first marker is the start of the hitbox window,
			-- not the safe contact. Use the config value as the baseline; the hitbox sync
			-- will pull the real contact in when the server part actually appears.
			return cfgv
		end
		return cfgv
	end

	loadGameModules()
	if GameData.cfg then
		-- 3-й аргумент = 1: берём НЕмасштабированную ��азу, множитель применяем ниже сами.
		local ok, d = pcall(function() return GameData.cfg.GetScaledStyleM1HitboxDelay(info.s, combo or 1, 1) end)
		if ok and type(d) == "number" then return d end
	end
	local sl   = string.lower(info.s or "")
	local base = LEGACY_M1_BASE[sl] or 0.32
	local off  = LEGACY_M1_OFFSETS[sl]
	if off then base = base + (off[math.clamp(combo or 1, 1, 4)] or 0) end
	return base + WINDUP_EXTRA
end

-- [V71] реальная задержка = base / attackSpeedMult(attacker). Это р��в����о то, что
-- ��елает игра (GetScaledHitboxDelay: delay/mult). ��дин общий множитель покрывает M1,
-- M2 и скиллы всех стилей БЕЗ ручных патчей — если игра добавит новый стиль/атаку,
-- б��за подтянется из её же ��онфига, а скорость — из роста атакующего.
local function hitTimeline(info, combo, mult, contactBase)
	local base = contactBase or hitTimelineBase(info, combo)
	local m = (type(mult) == "number" and mult > 0.05) and mult or 1
	-- [V124] Сервер делит ВСЕ hitbox-задержки на mult роста атакующего (GetScaledHitboxDelay:
	-- delay/mult) — и M1, и M2, и скиллы. Диаг подтвердил: Basic M2 0.525/1.09=482мс = measured
	-- 485мс. Прошлый V123-демпфер (m→1 для M2) был ОШИБКОЙ — он и ломал M2 (pred 617 vs 485).
	-- Incoming server hitbox deadline is CombatConfig delay / attacker height-speed multiplier.
	-- PingAnimSpeedMultiplier belongs to local animation presentation, not the foreign server
	-- hitbox. Dividing by it (<1 at high ping) made every threat 50-110ms late (diag 365774).
	return base / m
end

-- [V97/PERF] same treatment: persistent pcall target + a cache keyed by "style|kind". The game's
-- per-style hitbox offsets are CONFIG CONSTANTS (CombatConfig), so once resolved they never change
-- for the session — unlike styleOf this needs no TTL.
local _fwdFn = function(st, k) return GameData.cfg.GetStyleHitboxForwardOffset(st, k) end
local _fwdCache = {}
function styleForward(style, kind)
	local ck = tostring(style) .. "|" .. tostring(kind)
	local hit = _fwdCache[ck]
	if type(hit) == "number" then return hit end
	if hit == false then   -- known-miss: skip straight to the Config fallback, no pcall
		return (kind == "M2" or kind == "SKILL") and Config.M2Forward or Config.M1Forward
	end
	loadGameModules()
	if GameData.cfg then
		local ok, f = pcall(_fwdFn, style, kind)
		if ok and type(f) == "number" then _fwdCache[ck] = f; return f end
		-- [V97/PERF] the module exists but refused this style/kind → remember that, otherwise we
		-- would retry the pcall for this key on every single frame.
		_fwdCache[ck] = false
	end
	-- [V91] см. styleStepForward ниже — лунж прибавляется к forward в hitboxGeom.
	-- [V109] SKILL/спец-удары (крит, «крутилка ногами» и т.п.) обычно тяжёлые и длиннорукие →
	-- фолбэк на M2Forward (дальний вылет), а не короткий M1Forward. Меньше риск недооценить диста��цию.
	-- Config values are user-tunable at runtime, so the fallback itself is intentionally not cached.
	return (kind == "M2" or kind == "SKILL") and Config.M2Forward or Config.M1Forward
end

-- [V91] ЛУНЖ (StepForward) — НАЙДЕННАЯ ПРИЧИНА №1 пропусков «NOT-BLOCKED».
-- Дамп ReplicatedStorage.Shared.Utils.CombatStepUtils:
--   ApplyStepForward(char, studs): speed = min(studs/Shared.StepForward.Duration(0.14), MaxSpeed(30))
--   → на HRP навешивается LinearVelocity "CombatStepForwardLinearVelocity" на 0.14с,
--     т.е. атакующий ГАРАНТИРОВАННО доезжает вперёд ровно `studs` за время замаха.
--   Вызовы: M1_ModuleScript ApplyM1StepForward(style, char, combo) на старте свинга,
--           M2_ModuleScript ApplyM2StepForward(style, char).
--   ��туды: GetStyleM1StepForwardStuds(style, comboIdx) / GetStyleM2StepForwardStuds(style).
--   Ali: M1StepForwardStuds={[1]=1.5,[3]=1.5}, M2StepForwardStuds=2.
-- Почему это ломало распознавание: willHitMe в High ср��внивает dist2d <= forward+halfD+HighReachPad.
-- forward брался ТОЛЬКО из GetStyleHitboxForwardOffset (Ali M1 = 4.3), а лунж не учитывался вовс��.
-- Замер по диагам: у пропущенных без нажатия ударов дистанция p75=8, p95=11 студов при рече 8.2 —
-- ровно полоса, которую закрывает лунж. Лунж НЕ всегда виден в velocity: он живёт 0.14с в нача��е
-- замаха, а распознавание идёт вплоть до контакта (0.28–0.68с), когда LinearVelocity уже удалён
-- Debris'ом → predA откатывался назад и угроза отваливалась в predicted-miss.
-- Кэш по "style|kind|combo": это КОНСТАНТЫ конфига, TTL не нужен.
-- ВАЖНО ПРО ОБЛАСТЬ ВИДИМОСТИ: hitboxGeom объявлен ВЫШ�� этой строки, поэтому обычный
-- `local function` он лексически не увидит (ссылка ушла бы в глобал=nil и валила бы весь
-- schedulerStep каждый кадр). Объявляем ГЛОБАЛОМ — ровно так же, как уже сделано для
-- styleForward выше, и на месте вызова страхуемся паттерном `f and f(...)`.
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
		-- фолбэк: зн��чения Ali из дампа (единственный стиль со ступом на момент V91)
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
-- [V91.1/leak] weak keys: this is only a dedupe guard, so it must not PIN handler tables that
-- the game itself has dropped (module reload / respawn). Strong refs here kept every handler
-- object we ever saw alive for the whole session.
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
	-- ═══════ [V150] КОРЕНЬ «анимация атаки рванная в AutoPlay, но целая в Test Swing» ═══════
	-- Виноват НЕ свинг и не рейт-гард (V140/V141 чинили не то). Виноват ЭТОТ трек.
	-- Игровая playM1SwingAnimation (M1.lua:264-268) перед запуском свинга гасит ровно четыре
	-- категории:  "Evasive", "PerfectBlock", "EHit", "Combat"  — категории "Blocking" в этом
	-- списке НЕТ. А наш блок-трек грузится именно как "Blocking" (:2427). Поэтому он остаётся
	-- ЖИВЫМ поверх свинга и, будучи Action-приоритетом с бесконечным лупом, забирает вес за
	-- свой фейд-ин 0.08с (:2432) — свинг успевает показать буквально пару кадров и «сбивается».
	-- Почему у игры этого бага нет: там атаковать в блоке НЕЛЬЗЯ (canAttack требует
	-- Blocking ~= true, :3370), так что «Blocking + M1» — состояние, недостижимое штатно. Его
	-- создаёт наш кастомный билдер, который эти гейты сознательно обходит.
	-- Почему Test Swing был чистым: угроз нет → guard не поднят → трека "Blocking" не
	-- существует → перекрывать свинг нечем. Ровно та разница, о которой сказал пользователь.
	-- Гейт: пока идёт наш свинг, guard-анимацию не поднимаем. Это ТОЛЬКО косметика —
	-- State.blocking и серверный Activated не трогаются, защита продолжает работать.
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
		-- [V156/ALI-TRAJECTORY] Обычный dodge сохраняет DashSpeed. Ali perfect-dodge может
		-- передать меньшую скорость, чтоб�� 6-stud импульс не пронёс близкую цель насквозь.
		lv.VectorVelocity = dir * math.min(speedOverride or Config.DashSpeed, Config.DashSpeed)
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Parent = hrp
		Debris:AddItem(att, Config.DashDuration)
		Debris:AddItem(lv, Config.DashDuration)
	end)
end

-- ════════════ [V91.1] PARRY TIMESTAMP SPOOF ════════════
-- Block.Activated is the ONE combat packet whose timing the client gets to decide: the game
-- sends Server:FireServer({...Block/Activated}, Workspace:GetServerTimeNow()) and that stamp
-- is never clamped or re-read on the client (verified in the dump — Block fires the remote
-- directly, it doesn't even go through CombatRemoteClient). PerfectBlockWindow is 0.125s, so
-- if the server trusts the stamp, a parry sent late can be back-dated INTO the window.
--
-- TimeShiftMs is applied as a negative offset (we claim we pressed earlier than we did). Keep
-- it small: nudging by more than the window is pointless and an obvious outlier if the server
-- ever sanity-checks against its own clock. There is no skew constant anywhere in the client
-- dump, so how much the server tolerates is unknown — start low, raise until it stops helping.
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
	State.guardUp = true          -- сервер теперь держит guard
	playBlockAnim()
	return true
end

-- force=true — принудительное снятие guard (в обход MinDeactGap). Нужно, чтобы реальный
-- релиз никогда не те��ялся из-за рейт-лимита и guard не завис поднятым.
local function sendDeactivate(force)
	local now = os.clock()
	if not force and now - State.lastDeact < Config.MinDeactGap then return false end
	State.lastDeact = now
	local c = localChar()
	if c then c:SetAttribute("Blocking", nil) end
	ServerRemote:FireServer({ Type = "Combat", Action = "Block", Func = "Deactivated" })
	State.guardUp = false         -- guard снят на с��рвере
	stopBlockAnim()
	return true
end

local function sendDodge(dir, speedOverride)
	-- ═══════ [V159/DODGE-REVERT] НАТИВНЫЙ ВЫЗОВ Evasive() ОТКАЧЁН ПОЛНОСТЬЮ ═══════
	-- V158 звал GameData.evasive.Evasive() и считал доджем только появление нового
	-- EvasiveDashLinearVelocity. Runtime это опроверг: за всю сессию `dodges=0` и в диаге НЕТ ни
	-- одной строки DODGE-NATIVE-ACCEPT / DODGE-SKIP/NATIVE-GATE, то есть путь либо не доходил до
	-- отправки, либо гасился внутри чужого модуля молча. Плюс клиентский вызов тащит за собой
	-- CombatRemoteLimits (Evasive 4/сек) и upvalue-гейты u5/u6/u7/u8, которыми уже управляет
	-- movement.lua — два источника истины на одни и те же регистры.
	-- Возврат к V157: пакет уходит в ServerRemote напрямую, гейты решает НАШ canDodgeNow().
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

-- [V122] BOXING COUNTER — полный переписанный блок. Модель проста и агрессивна (ТЗ юзера):
-- «вместо парирования МОМЕНТАЛЬНО бит�� M2, если стиль Boxing, враг атаков��л в радиусе 5.5 и
-- M2 не на кулдауне». Ни задержек, ни ожидания контакта, ни каденс/пинг-гейтов.

-- Атрибуты, при которых наш перс физически НЕ может запустить M2 (тогда counter невозможен).
local BOXING_BLOCK_ATTRS = {
	"CombatAttacking", "Stunned", "Ragdoll",
	"ParryAttackLockout", "BlockAttackLockout",
}

-- Готов ли НАШ перс сейчас пустить boxing-M2 (стиль + все гейты состояния + M2 не на кулдауне).
-- [V91] КОНТРА ОБОБЩЕНА С BOXING НА ЛЮБОЙ СТИЛЬ С IFRAME-M2.
-- Почему это вообще работает: смысл контры — вместо парирования пустить свою M2, у которой
-- M2GrantsIFrames=true. i-frames в этой игре = АБСОЛЮТНАЯ неуязвимость: игровой
-- VictimHitboxServiceClient._isSuppressed гасит скан хитбоксов при IFRAMES, т.е. входящий удар
-- физически не резолвится. По CombatConfig M2GrantsIFrames=true ровно у boxing И ali.
-- Ali как носитель контры ЛУЧШЕ boxing по трём причинам (всё из дампа):
--   • EvasiveCounter={Cooldown=6, MaxRange=22, IgnoreM2Cooldown=true, VariantId="Left"} —
--     после уклонения M2 бесплатна (игнорирует 7с кулдаун) и достаёт на 22 студа;
--   • M2StepForwardStuds=2 — сама доводит до цели;
--   • вариант M2 выбираем МЫ (см. steerM2Variant): Right даёт ×1.25 урона и рэгдолл.
-- Возвращает ключ стиля, если ��онтра сейчас в принципе доступна, иначе nil.
local function counterStyle()
	local c = localChar()
	if not c then return nil end
	local st = (styleOf and styleOf(c) or ""):lower()
	if st == "" then return nil end
	if st == "boxing" then return Config.BoxingCounter and "boxing" or nil end
	if st == "ali"    then return Config.AliCounter    and "ali"    or nil end
	-- [V139] Только boxing и ali. Универсальной ветки по M2GrantsIFrames больше нет: реч, вариант
	-- и кулдаун калибруются на стиль, а слепое включение сжигало 7-секундную M2 вхолостую.
	return nil
end

-- [V91] РУЛЁЖКА ВАРИАНТОМ M2. Дамп CombatStepUtils.ResolveM2VariantId(style, char):
--   deg = atan2(dot(moveDir, RightVector), dot(moveDir, LookVector)) в градусах
--   id  = (deg == nil или -112.5 < deg <= 67.5) and "Left" or "Right"
-- Т.е. вариант определяется НАПРАВЛЕНИЕМ ДВИЖЕНИЯ и считается одинаково на клиенте и сервере
-- (в Fire("M2","ServerCheck") вариант НЕ передаётся — сервер резолвит его сам из
-- реплицированного Humanoid.MoveDirection). Значит мы можем ег�� ВЫБИРАТЬ:
--   Right (нужно deg>67.5): двигаться ВПРАВО → dir = HRP.RightVector (deg=+90)
--   Left  (нужно deg<=67.5): двигаться ВПЕРЁД → dir = HRP.LookVector (deg=0)
-- Humanoid:Move(dir, false) задаёт MoveDirection на кадр, поэтому переутверждаем его короткое
-- время вокруг выстрела, чтобы серверн��я сторона увидела нужное направление при обработке.
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
	-- [V157/HEAVY-ATOMIC] Возвращаем не только bool, но и точный live-гейт. V156 молча
	-- превращал любой отказ sender-а в nil-кандидата, а speculative preempt продолжал обещать M2.
	if not Config.SkillAddon then return false, "SkillAddon-off" end
	local c = localChar()
	if not c then return false, "no-character" end
	local cs = counterStyle()
	if not cs then return false, "counter-style-disabled" end
	-- анти-даблфайр: не спамим M2 быстрее BoxingCounterGap (реальный кулдаун держит игра через
	-- M2Cooldown; этот гэп только закрывает сетевое окно до появления атрибута). НЕ задержка.
	if (os.clock() - (State.lastCounter or 0)) < (Config.BoxingCounterGap or 0.30) then
		return false, "BoxingCounterGap"
	end
	for _, attr in ipairs(BOXING_BLOCK_ATTRS) do
		if c:GetAttribute(attr) then return false, attr end
	end
	if c:GetAttribute("CantAnything") and not c:GetAttribute("CombatRecovery") then
		return false, "CantAnything"
	end
	-- [V139/BUG] Было `== false`: при ещё НЕ выставленном а��рибуте (nil, первые кадры после
	-- спавна/смены стиля) гейт пропускал, и контра улетала без оружия в руках — сервер такой
	-- M2 отклоняет, а State.lastCounter уже обновлён → BoxingCounterGap глушил СЛЕДУЮЩУЮ,
	-- уже валидную контру. canAttack всегда проверял `~= true`; приводим к тому же виду.
	if c:GetAttribute("Equip") ~= true then return false, "Equip" end
	if c:GetAttribute("Greenzone") == true then return false, "Greenzone" end
	if c:GetAttribute("RpCombatLocked") == true then return false, "RpCombatLocked" end
	-- M2 на кулдауне → counter невозможен (FireServer был бы вхолостую, iframes не выдаются).
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

-- ═══════════════════ [V146] ЕДИНАЯ ОТМЕТКА «МЫ ПОД СВОИМИ i-FRAMES» ═══════════════════
-- ПОЧЕМУ V145 НЕ ДАЛ РОВНО НИЧЕГО — ДВЕ КОНКРЕТНЫЕ ОШИБКИ, ОБЕ ВИДНЫ В ДИАГЕ V144:
--
-- ОШИБКА 1. Я читал `GameData.boxingM2Contacts`, а таблица лежит в `V93` (объявлена на :956,
--   и весь остальной код обращается к ней как `V93.boxingM2Contacts`, :2050). GameData такого
--   поля не имеет ВООБЩЕ → выражение бы��о nil → цикл поиска максимума не выполнялся ни разу →
--   lastContact оставался равным hbDelay. Арифметическое доказательство прямо из диага:
--       COUNTER t=47414.59 → COUNTER-COVER t=47414.66 «live for 659ms more»
--       47414.66 + 0.659 = 47415.32 = 47414.59 + 0.73 = 0.43 (hbDelay) + 0.30 (IFrameDuration)
--   Ровно старая формула V142. Второй случай тот же: 47423.91 + 0.73 → «540ms more» на 47424.10.
--   То есть окно так и ост��лось 0.73с вместо 1.05 + 0.30 = 1.35с.
--
-- ОШИБКА 2 (главная). Я правил ТОЛЬКО fireBoxingCounter, а нашу M2 с i-frames пускает ЕЩЁ ОДИН
--   путь — interrupt (:3594 `ap.fireM2(th.attackerModel, "interrupt", m2Var)` при
--   `m2Iframes = ap.m2GrantsIFrames()`). Он не писал counterIFramesUntil никогда. Диаг:
--       INTERRUPT t=47430.40 l13n1 M1(MuayThai) via=M2+IF ours=443ms
--       DODGE     t=47430.48 outnumbered-escape [GRANT]      ← через 80мс, в наших же i-frames
--       INTERRUPT t=47433.60 via=M1/c1 → DODGE t=47433.94    ← то же во время нашей атаки
--   Здесь `+IF` в теге — это и есть m2Iframes=true, то есть мы уже неуязвимы, а скрипт жжёт
--   грант. Именно про это ты и писал. Оба доджа потом получили
--   `DODGE-REJECT … IFRAMES not confirmed` (t=47434.42, t=47437.56) — сервер их не принял,
--   потому что мы в этот момент атаковали (дамп Evasive:613 проверяет CombatAttacking).
--
-- ЧТО ДЕЛАЕМ: одна функция, которую ОБЯЗАНЫ вызвать все пути нашей M2 с i-frames.
-- ═══════════ [V147] ПОЧЕМУ БЫЛО «out of local registers» ═══════════
-- Luau даёт максимум 200 РЕГИСТРОВ (локальных переменных) на функцию, а тело файла — тоже
-- функция (главный чанк). Top-level локалей здесь уже б��ло ровно у предела:
--     коммит 01ca31c → 210 объявлений  (компилировался)
--     коммит 09f31ce → 211 объявлений  ← мой V146, НЕ компилируется
-- Разница ровно в единице — это мой `local function markOwnM2IFrames`. Ошибка не в логике
-- V146, а в том, что я добавил Н��ВУЮ top-level локаль в файл с исчерпанными регистрами.
-- Поэтому функция становится ПОЛЕМ уже существующей таблицы V93 (:898): сама таблица свой
-- регистр занимает давно, а её поля регистров не требуют вообще.
-- ПРАВИЛО НА БУДУЩЕЕ: в этом файле новые top-level `local` добавлять НЕЛЬЗЯ — только поля
-- V93 / State / Config.
function V93.markOwnM2IFrames(now, tag)
	local style = tostring(styleOf(localChar()) or ""):lower()
	loadGameModules()
	-- Последний контакт нашей M2. Базовая задержка — из живого конфига игры.
	local lastContact = 0.43
	if GameData.cfg and GameData.cfg.GetStyleM2HitboxDelay then
		local okd, d = pcall(GameData.cfg.GetStyleM2HitboxDelay, style, false, nil)
		if okd and type(d) == "number" and d > 0 then lastContact = d end
		-- У стиля с вариантами (ali: Left 0.53 / Right 0.67) берём САМЫЙ ДОЛГИЙ: какой вариант
		-- резолвит сервер, мы наверняка не знаем (он считает его из реплицированного
		-- MoveDirection), а недооценка окна — это ровно тот баг, который мы и лечим.
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
	-- Мультихит: у boxing M2 два контакта, второй на 1.05с. Таблица — V93, НЕ GameData (ошибка 1).
	if style == "boxing" then
		local mc = V93.boxingM2Contacts
		if type(mc) == "table" then
			for i = 1, #mc do
				if type(mc[i]) == "number" and mc[i] > lastContact then lastContact = mc[i] end
			end
		end
	end
	-- [V152/BOXING-COUNTER] V146 ошибочно превращал расчётное окно в подтверждённую защиту:
	-- один лишь FireServer ставил counterIFramesUntil ��а всю длительность M2, даже если сервер
	-- отклонил запрос. Из-за этого обычный dodge блокировался без живого IFRAMES. Расчёт контакта
	-- оставляем только для честной ло��альной занятости; неуязвимость подтверждает updateCounterTxn
	-- по реплицированному атрибуту, а interrupt/M2+IF также прикрывается только фактом IFRAMES.
	State.counterIFramesUntil = 0
	-- Занятость своей атакой: на атрибут CombatAttacking опираться НЕЛЬЗЯ — его каждый кадр
	-- стирает No Delay из movement.lua (он в его M1_GATE_ATTRS). Локально атрибут снят, поэтому
	-- и игровой гейт, и canDodgeNow() думают «мы не атакуем», а сервер знает правду и отказывает
	-- в i-frames (`DODGE-REJECT … IFRAMES not confirmed`). Держим своим временем.
	State.attackBusyUntil = math.max(State.attackBusyUntil or 0, now + lastContact)
	State.selfBusyUntil   = math.max(State.selfBusyUntil or 0, now + lastContact)
	State.ownIFrameTag = tag
end

-- [V152/BOXING-COUNTER] Один авторитетный апдейтер транзакции. До V152 FireServer сразу
-- объявлялся успехом через counterIFramesUntil, поэтому отклонённая M2 могла отменить fallback.
-- Теперь SEND, CONFIRM и FAIL — разные факты. Новая top-level local-функция здесь запрещена
-- лимитом регистров, поэтому, как и V146/V151, держим функцию полем уже существующей State.
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
		-- [V152] Живой IFRAMES — сервер принял M2 и уже подавляет victim-hitbox (факт из дампа
		-- VictimHitboxServiceClient). Поэтому конкретная атака, ради которой отправлена контра,
		-- обслужена сразу: не ждём её старого contactAbs и не запускаем dodge после успешной контры.
		if th then
			th.coveredByCounter, th.counterPendingId, th.resolved = true, nil, true
		end
		tx.confirmed, tx.pending, tx.result = false, false, "IFRAMES"
		State.counterIFramesUntil = 0 -- live attribute is the authority; no guessed tail
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

	-- Если подтверждённые IFRAMES уже исчезли ДО контакта, контра не закрыла эту угрозу.
	-- Если подтверждения не было — ждём только до физического ackDeadline. В обоих случаях
	-- возвращаем ровно эту угрозу штатному parry/dodge-планировщику, не трогая остальные.
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

-- [V154/ALI-DODGE-ABUSE] Polling здесь надёжнее CharacterAdded-connect: scheduler и так читает
-- combat-атрибуты каждый реактивный кадр, а таблица переживает респавн. Только ребро nil/false→true
-- даёт известный started; подключение при уже true намеренно оставляет known=false.
function State.updateAliM2Cooldown(now)
	local cd = State.aliM2CD
	local ch = localChar()
	if ch ~= cd.char then
		cd.char, cd.observed, cd.active, cd.known, cd.started = ch, false, false, false, 0
		-- [V155/LIFECYCLE] Таблица dodgeTxn переживает CharacterAdded; без очистки новый персонаж
		-- мог унаследовать target/perfect старого dodge до его timeout.
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

-- [V155/BOXING] Одна политика используется counter и scheduler: когда локальный стиль Ali,
-- Boxing M2 всегда остаётся в parry/held-guard пути и не расходует Evasive/M2.
function State.isAliBoxingM2(th)
	return (styleOf(localChar()) or ""):lower() == "ali"
		and th and tostring(th.style or ""):lower() == "boxing" and th.kind == "M2"
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
	-- [V155/BUG] V154 вызывал local isMustDodge ДО её объявления, что в этой позиции означает
	-- глобальный nil и runtime-error. State.isMustDodge публикуется до первого scheduler.
	if not th or not th.serverProven then return false, nil, "not-server-proven" end
	if State.isMustDodge and State.isMustDodge(th) then return false, nil, "must-dodge" end

	-- [V155/BOXING] Boxing M2 имеет два контакта и собственные IFRAMES. По выбранной безопасной
	-- политике Ali никогда не меняет его на dodge/M2: оба EDF-контакта остаются parry/held-guard.
	if State.isAliBoxingM2(th) then return false, nil, "boxing-m2-parry" end

	local cd = State.aliM2CD
	if not (cd and cd.active and cd.known) then return false, nil, "m2-cooldown-unknown" end
	local remaining = (cd.started + cd.duration) - now
	if remaining <= 1.0 then return false, nil, "m2-ready-soon" end

	-- [V155/PERFECT] Не ограничиваем любой multi-hit последним strike искусственно. Источник истины
	-- — реальные EDF-контакты: dodge разрешён только если ВСЕ ещё активные угрозы помещаются во
	-- внутреннее iframe-окно. Иначе сохраняем parry, а не надеемся на край окна.
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

-- Мгновенно пустить M2 по цели th: снап лицом (сервер строит хитбокс по нашему LookVector),
-- уронить guard (M2 не пустится с поднятым блоком), FireServer прямо в этот кадр.
local function fireBoxingCounter(th, targetDist)
	local myHRP = localHRP()
	local aHRP  = th and th.attackerHRP
	if myHRP and aHRP and aHRP.Parent then
		local d = flatDirTo(myHRP.Position, aHRP.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
		-- [V155/ALI-ROTATION] Общий sender обслуживает два стиля; старый boxing hold для Ali был
		-- неверным. Длительность теперь выбирается по стилю и управляется отдельным UI slider.
		local faceHold = (counterStyle() == "ali") and (Config.AliFaceLockDur or 0.75)
			or (Config.BoxingFaceLockDur or 0.55)
		setFaceGoal(aHRP, true, faceHold)
	end
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)   -- force: guard обязан опуститься, иначе рейт-лимит подвесит M2
	end
	-- [V91] Для стиля с M2Variants (сейчас это Ali) ВЫБИРАЕМ вариант направлением движения ДО
	-- отправки: сервер резолвит его сам из реплицированного MoveDirection, вариант в пакете не
	-- передаётся. Right = ×1.25 урона + рэгдолл (delay 0.67), Left = быстрее (0.53), ×0.8, без
	-- рэгдолла. Для boxing вариантов нет — steer не вызывается и поведение не меняется.
	local cs = counterStyle()
	if cs and cs ~= "boxing" then
		loadGameModules()
		local hasVars = false
		if GameData.cfg and GameData.cfg.GetStyleM2Variants then
			local okv, vs = pcall(GameData.cfg.GetStyleM2Variants, cs)
			hasVars = okv and type(vs) == "table"
		end
		-- [V160] Фолбэк выровнен с новым дефолтом Config.AliM2Variant ("Left"). Раньше здесь
		-- стоял "Right": при пустом/сброшенном конфиге sender молча уводил вариант в медленный
		-- 0.67с, противореча выбранной защитной политике.
		if hasVars then steerM2Variant(Config.AliM2Variant or "Left") end
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	local sentAt = os.clock()
	State.lastCounter  = sentAt
	State.counterCount = (State.counterCount or 0) + 1
	State.flashUntil   = sentAt + 0.25
	State.status       = (cs == "ali") and "ALI-COUNTER" or "BOX-COUNTER"
	-- [V152/BOXING-COUNTER] SEND — ещё не успех. Короткое pending-окно равно сетевому пути
	-- плюс одному кадру/малому джиттеру; после него без живого IFRAMES обычная защита возвращается.
	-- Конкретная угроза помечена только pending: мы не удаляем её до серверного факта.
	local tx = State.counterTxn
	if tx.threat and tx.threat ~= th then tx.threat.counterPendingId = nil end
	tx.seq = (tx.seq or 0) + 1
	local net = math.max(uplink(), 0.02)
	tx.pending, tx.confirmed, tx.sent = true, false, sentAt
	tx.ackDeadline = sentAt + net + (V93.lookahead or 0) + 0.08
	-- [V156/COUNTER-VIABILITY] Runtime опроверг половину RTT: IFRAMES приходил через ~100мс.
	-- Используем полное наблюдае��ое плечо; тот же срок проверяется ДО отправки в tryBoxingCounter.
	tx.expectedIFramesAt = sentAt + net + math.max(V93.lookahead or 0, 0) + (1 / 60)
	tx.threat, tx.source, tx.result = th, cs, "sent"
	tx.threatId = tostring(th.serverSwingId or (th.group and th.group.serverSwingId)
		or ((th.name or "?") .. "/" .. (th.kind or "?") .. "/" .. math.floor((th.detectClock or sentAt) * 1000)))
	th.counterPendingId = tx.seq
	State.counterPreemptFrame = -1
	diagPush(("COUNTER-SEND t=%.2f id=%s target=%s/%s dist=%.1f gate=M2-ready ack=%0.fms")
		:format(sentAt, tx.threatId, tostring(th.name), tostring(th.kind), targetDist or -1,
			(tx.ackDeadline - sentAt) * 1000))
	-- [V142] ФИКС «контра + додж подряд». Гейт counterPreemptsDodge спрашивал counterCandidate,
	-- а тот НАЧИНАЕТСЯ с counterReady() — где стоит проверка атрибута M2Cooldown. То есть ровно
	-- ПОСЛЕ выстрела контры ответ гейта переворачивался с true на false, и ветки эскейпов тут же
	-- получали разрешение на додж — хотя i-frames от нашего же M2 в этот момент активны
	-- (у boxing и ali M2GrantsIFrames=true). Гейт отвечал «могу ли я контрить?», тогда как ��опрос
	-- звучит «прикрыт ли я прямо сейчас?». Запоминаем конец окна неуязвимости контры.
	-- [V146] Расчёт окна вынесен в markOwnM2IFrames (см. выше): его обязан вызывать КАЖДЫЙ путь,
	-- кото��ый пускает н��шу M2 �� i-frames, а не только контра.
	V93.markOwnM2IFrames(os.clock(), "counter/" .. tostring(cs))
end

-- [V158/ALI-PASSIVE] ТОЧНАЯ МЕХАНИКА ИЗ ДАМПА + SERVER EVENT.
-- CombatConfig.Styles.ali.EvasiveCounter содержит ровно:
--   { Cooldown = 6, MaxRange = 22, IgnoreM2Cooldown = true, VariantId = "Left" }
-- Это НЕ накопление нескольких dodge и НЕ сброс обычного Heavy cooldown. Один perfect-dodge
-- заставляет сервер прислать один StyleEvasiveCounter; только этот proc разрешает специальную
-- Left-M2 в радиусе 22. Она игнорирует обычный M2Cooldown, но имеет собственный cooldown 6с.
-- Клиентский дамп не содержит серверный критерий perfect, поэтому никакой выдуманный локальный
-- счётчик не добавляем: единственный авторитет — отдельное CombatBroadcastURE событие.
-- [V154/ALI] Одного `tx.confirmed` недостаточно: IFRAMES означает только принятый dodge.
-- Специальная M2 запрещена, пока StyleEvasiveCounter не пометит транзакцию perfectConfirmed.
local function tryAliEvasiveCounter(now)
	if not Config.SkillAddon or not Config.AliEvasiveCounter then return false end
	if (counterStyle() or "") ~= "ali" then return false end
	local tx = State.dodgeTxn
	if not (tx and tx.pending and tx.perfectConfirmed) then return false end
	if tx.evCounterFired then return false end
	-- [V156/EVCOUNTER-ORDER] StyleEvasiveCounter и IFRAMES реплицируются независимо. Perfect
	-- уже авторитетно доказан сервером, но sender ждёт второй факт, не исчезая молча.
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
	-- [V156/EVCOUNTER-WINDOW] tx.hi — расчётная граница, а StyleEvasiveCounter — серверный
	-- факт perfect-dodge. В логе событие пришло на 15мс позже tx.hi, но ещё внутри transaction.
	-- Поэтому sender живёт до authoritative transaction deadline, не до предсказанного iframe края.
		-- ═══════════ [V161] ОКНО ОТПРАВКИ ПРОЦА ОТВЯЗАНО ОТ ОКНА I-FRAME ═══════════
		-- Проц — это ПРАВО на специальную M2, а не часть неуязвимости. В диаге он стабильно
		-- истекал по gate=transaction-ended, пока CombatAttacking (наш же AutoPlay) не отпускал
		-- нас: untilAt при пинге 112мс ≈ 492мс, а contact/attacking длится дольше.
		-- Клиентский дамп НЕ содержит серверного срока жизни права (StyleEvasiveCounter на клиенте
		-- только косметика — CombatReplicatorClient:559 → AliColorFx.Counter). Единственное
		-- известное из конфига число — Cooldown=6 (CombatConfig:261), и оно же ограничивает
		-- частоту сверху, поэтому за верхнюю границу окна берём консервативную долю от него,
		-- а не выдуманную константу. Так уступка AutoPlay успевает подействовать.
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
	-- [V155/ALI-TARGET] Для Dodge Abuse M2 обязана относиться к тому же swing, который мы
	-- форвард-доджили. Если цель исчезла/вышла из range, не подменяем её случайным соседом.
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
		-- [V155/ALI-ROTATION] Evasive Counter больше не наследует boxing-длительность.
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

-- Главная точка входа: если можем контрить — находим БЛИЖАЙШЕГО атакующего в радиусе и
-- МОМЕНТАЛЬНО бьём M2. Возвращает true, если counter выстрелил (scheduler пропускает блок).
-- [V92] Поиск цели для мгновенной контры БЕЗ побочных эффек��ов. Вынесен из tryBoxingCounter,
-- потому что решение «контра или додж» надо принять ДО того, как ветки доджа сожгут Evasive:
-- у ali и boxing M2GrantsIFrames=true, т.е. своя тяжёлая даёт те же i-frames, что уклонение,
-- но ещё и наносит урон. Возвращает (угроза, дистанция) либо nil.
-- ═══════ [V150] КОРЕНЬ «сначала задоджил, потом M2-контра» ═══════
-- Порядок в планировщике правильный: все ветки доджа (:5272-5508) стоят ВЫШЕ вызовов
-- tryAliEvasiveCounter/tryBoxingCounter (:5594-5595) и честно спрашивают counterPreemptsDodge.
-- Ломался сам ОТВЕТ гейта, потому что counterCandidate начинается с counterReady(), а тот
-- смешивает два разных класса запретов:
--   ПОСТОЯННЫЕ  — не тот стиль, нет Equip, M2Cooldown, Greenzone, EHit, мёртв: контры не будет
--                 вообще, и додж действительно единственный выход;
--   ВРЕМЕННЫЕ   — CombatAttacking/M1 (наш СВОЙ свинг от AutoPlay!), ParryAttackLockout,
--                 BlockAttackLockout и анти-даблфайр BoxingCounterGap (0.30с).
-- Пока висит временный запрет, counterReady=false → гейт разрешает додж → через 1-2 кадра
-- атрибут гаснет, counterReady=true и tryBoxingCounter бьёт M2. Отсюда ровно та пара
-- «додж, а потом M2», которую видел пользователь. Причём в AutoPlay это происходит постоянно:
-- CombatAttacking/M1 на нас висит после каждого своего удара.
-- Решение: различать классы. Кандидата ищем без временных гейтов, а «успеет ли контра к
-- контакту» решаем по времени их снятия. Постоянные гейты по-прежнему запрещают preempt.
-- [V151] Обе функци�� живут ПОЛЯМИ State, а не локалами главного чанка. Причина техническая:
-- Luau жёстко ограничивает функцию 200 локалами, файл уже был на пределе (фикс V130 про это же),
-- и мои два новых `local function` в V150 дали "out of local registers" — скрипт не запускался
-- вообще. Поля таблицы регистров не занимают. State для этого годится: по нему нигде нет
-- pairs/JSONEncode, так что функции в полях ничего не ломают.
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

-- Когда снимутся ВРЕМЕННЫЕ запреты на контру. Оценка сверху, из уже известных нам величин:
-- конец собственного свинга (State.swingAnimUntil ставится в fireM1Custom) и анти-даблфайр-гэп.
function State.counterReadyAt(now)
	local at = now
	local gapEnd = (State.lastCounter or 0) + (Config.BoxingCounterGap or 0.30)
	if gapEnd > at then at = gapEnd end
	local swingEnd = State.swingAnimUntil or 0
	if swingEnd > at then at = swingEnd end
	return at
end

local function counterCandidate(now, ignoreTransient)
	-- [V157/HEAVY-ATOMIC] ignoreTransient разрешён только для диагностики подходящей цели.
	-- Решение об отправке всегда отдельно требует counterReady() в том же кадре.
	if ignoreTransient then
		if State.counterBlockedPerm() then return nil end
	else
		local ready, gate = counterReady()
		if not ready then return nil, nil, gate end
	end
	local myHRP = localHRP()
	if not myHRP then return nil end
	-- [V91] реч контры зависит от стиля: Ali M2 сама доводит на M2StepForwardStuds=2 студа
	-- (CombatStepUtils.ApplyM2StepForward), поэтому её эффективный радиус больше боксёрского.
	local cstyle = counterStyle()
	local reach = (cstyle == "ali") and (Config.AliCounterReach or 7.5)
		or (Config.BoxingCounterReach or 5.5)
	local myPos = myHRP.Position
	local best, bestDist
	-- [V140/BUG] КОНТРА И ДОДЖ СРАБАТЫВАЛИ ОДНОВРЕМЕННО. Раньше этот перебор брал ЛЮБУЮ живую
	-- угрозу, включая unblockable-грэбы (Wrestling M2 и прочий must-dodge список). Но такие
	-- угрозы идут СВОИМ путём: ветка must-dodge на строке ~4700 обязана дать додж и СОЗНАТЕЛЬНО
	-- не спрашивает counterPreemptsDodge («unblockable grabs still always dodge»). Итог в логе:
	--   COUNTER t=17944.96 king_gng2 M2 dist=4.1 (instant M2)
	--   DODGE   t=17945.23 must-dodge(unblockable→back) [GRANT]
	-- то есть мы платили M2 (кулд��ун ~7с) И тут же уходили в додж. Контра там бесполезна вдвойне:
	-- у грэба M2GrantsHyperArmor, поэтому наш M2 его физически НЕ прерывает, а i-frames доджа
	-- и так закрывают весь размен. Уводим must-dodge из кандидатов: у него есть свой обработчик.
	local mustDodgeFn = State.isMustDodge
	for i = 1, #Threats do
		local th = Threats[i]
		local aHRP = th.attackerHRP
		-- [V155/BOXING] Ali M2 больше не летит в собственные IFRAMES Boxing M2. Запрет стоит
		-- в общем candidate, поэтому действует и для instant counter, и для preempt-dodge гейта.
		local aliVsBoxingM2 = State.isAliBoxingM2(th)
		if aliVsBoxingM2 and not th.aliBoxingCounterLogged then
			th.aliBoxingCounterLogged = true
			diagPush(("ALI-BOXING-M2=PARRY t=%.2f target=%s strike=%d contactIn=%.0fms gate=counter")
				:format(now, tostring(th.name), th.strike or 1, (th.contactAbs-now)*1000))
		end
		-- «враг атаковал» = активная угроза (свинг задетекчен) и контак�� ещё не прошёл давно.
		-- [V140/BUG] ВТОРАЯ ПОЛОВИНА ТОЙ ЖЕ ПРОБЛЕМЫ — обратный порядок событий. Раньше здесь
		-- стояло только `not th.dodged`, но при выдаче доджа угроза помечается `coveredByDodge`
		-- (строки ~4788 и ~4812), а `dodged` там НЕ выставляется — его ставит лишь ветка 4284.
		-- Поэтом�� угроза, уже закрытая i-frames доджа, оставалась валидным кандидатом на контру,
		-- и мы били M2 поверх собственного уворо��а. Проверяем оба флага.
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

-- [V92] Мемоизация на кадр: гейты доджа спрашивают это несколько раз за ��адр, а counterCandidate
-- перебирает Threats. FrameId уже инкрементится плани��овщиком, поэтому используем его как ключ.
local function counterPreemptsDodge(now)
	if State.counterPreemptFrame == FrameId then return State.counterPreemptVal end
	-- ═══════ [V146] ФАКТ ВМЕСТО ПРЕДСКАЗАНИЯ: атрибут IFRAMES на наше�� персонаже ═══════
	-- Дамп VictimHitboxServiceClient_ModuleScript.lua:139 — игра решает «не��язвим ли ты» т��к:
	--     return p22:GetAttribute("IFRAMES") == true and true
	--            or (p22:GetAttribute("Ragdoll") == true ... "Downed" ... "UltraInstinct")
	-- Это ЧИТАЕМЫЙ атрибут, а не внутреннее состояние. Значит вычислять окно по конфигу нужно
	-- только как опережение (атрибут приходит с сервера через ~ping), а сам факт ��еуязвимости
	-- надо просто СПРОСИТЬ. Раньше мы этого не делали ни разу и полагались только на свой
	-- расчётный counterIFramesUntil — который, как показано в markOwnM2IFrames, ставился не
	-- всеми путями и считал��я по nil-таблице.
	-- П��оверка стоит ДО Config.CounterPreemptsDodge намеренно: тумблер управляет тактикой
	-- «контра вместо доджа», а здесь мы отказываем в дэше по физике — под i-frames он
	-- бесполезен в принципе, и сервер его всё равно не примет (Evasive:613).
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
	-- [V152/BOXING-COUNTER] V142 считал FireServer готовыми i-frames на всём расчётном окне.
	-- Теперь после SEND придерживаем dodge лишь на коротком пути репликации и только когда
	-- ожидаемый приход IFRAMES физически раньше контакта конкретной угрозы. Живой атрибут уже
	-- обработан выше; timeout/невозможное покрытие State.updateCounterTxn переводит в FALLBACK.
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
	-- [V157/HEAVY-ATOMIC] Удалено speculative резервирование через counterCandidate(now, true).
	-- Heavy, которую мы лишь надеемся отправить после снятия CombatAttacking/lockout, НЕ является
	-- защитой. Отменить dodge теперь могут только live IFRAMES выше или уже отправленный counterTxn.
	State.counterPreemptFrame, State.counterPreemptVal = FrameId, false
	return false
end

local function tryBoxingCounter(now)
	-- [V157/HEAVY-ATOMIC] Сначала находим подходящую угрозу независимо от transient-гейтов,
	-- затем в ЭТОМ ЖЕ кадре проверяем live readiness. Только реальный COUNTER-SEND заменяет parry.
	local best, bestDist = counterCandidate(now, true)
	if not best then return false end
	local ready, gate = counterReady()
	if not ready then
		-- ═══════ [V159/COUNTER-TRANSIENT] ПОЧЕМУ V157 ДАВАЛ `boxing-counter fired=0` ═══════
		-- V157 на ПЕРВОМ же live-отказе ставил counterCommittedToParry=true навсегда. Но в диаге
		-- отказ на детекте — это всегда ВРЕМЕННЫЙ гейт от наших же действий:
		--   COUNTER-FALLBACK/PARRY t=3822.99 ... contactIn=346ms gate=Stunned
		--   COUNTER-FALLBACK/PARRY t=3831.44 ... contactIn=346ms gate=CombatAttacking
		-- До контакта оставалось 346мс, а Stunned/CombatAttacking/BoxingCounterGap снимаются
		-- заметно раньше. Пожизненный запрет превращал каждую такую угрозу в parry, и за всю
		-- сессию контра не вышла ни разу.
		-- Теперь решение принимается по УЖЕ ИЗВЕСТНОМУ времени снятия гейтов (counterReadyAt) и
		-- тому же сетевому плечу, что проверяется перед отправкой. Если после снятия IFRAMES
		-- физически успевают встать до контакта — угроза остаётся кандидатом и пробуется дальше;
		-- если не успевают — только тогда она окончательно уходит в parry. Новых настроек нет.
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
	-- [V156/COUNTER-VIABILITY] В V155 M2 отправлялась даже за 15–30мс до server contact,
	-- хотя runtime показал ~98–100мс до репликации IFRAMES. Такая «контра» снимала guard,
	-- а fallback возвращал parry уже после deadline. До отправки требуем полный наблюдаемый
	-- сетевой путь + lookahead + один physics-frame; если он не помещается, M2 вообще не трогаем.
	local contactIn = (best.contactAbs or now) - now
	local iframeLead = math.max(uplink(), 0.02) + math.max(V93.lookahead or 0, 0) + (1 / 60)
	if contactIn <= iframeLead then
		if not best.counterLateSkipLogged then
			best.counterLateSkipLogged = true
			diagPush(("COUNTER-SKIP/PARRY t=%.2f target=%s/%s contactIn=%.0fms need=%.0fms gate=IFRAMES-cannot-precede-contact")
				:format(now, tostring(best.name), tostring(best.kind), contactIn * 1000, iframeLead * 1000))
		end
		return false
	end
	-- [V152] fireBoxingCounter пишет COUNTER-SEND. Отдельный старый `COUNTER` удалён: он называл
	-- отправку успешной контрой до IFRAMES/нейтрализации и делал диагностику ложной.
	fireBoxingCounter(best, bestDist)
	return true
end

-- [V89] ПРОИЗВОДНЫЙ список «только додж». В дампе НЕТ флага Unblockable/CanBlock: любой
-- M1/M2 в принципе блокируется/перфактится (сетевые исходы: M2Blocked / M2PerfectBlocked /
-- M2GuardBroken). Реальн�� сквозь атрибут Blocking проходят только грэбы/с��эмы ��� прежде всего
-- Wrestling M2 (гарантированный захват, см. M2GrabTargetForwardOffset в CombatConfig). Их
-- нельзя блокнуть, с��асает лишь додж (i-frames = абсолютная неуязвимость: VictimHitboxService
-- ._isSuppressed гасит урон при IFRAMES/Ragdoll/Downed/UltraInstinct). Список собираем по
-- стилю/��ипу через Config.MustDodgeStyles (расширяется ����з правки движка) + живой сигнал по
-- атрибуту атакующего, е��ли игра е��о выставит в момент замаха.
local function isMustDodge(th)
	if not th then return false end
	local st = (th.style or ""):lower()
	-- Skill Addons force-dodge specific unblockable grabs regardless of the Must-Dodge list.
	-- Wrestling M2 is a guaranteed grab with HyperArmor; Dirty grab ignores ragdoll immunity —
	-- both pass through the Blocking attribute, so only i-frames (a backdodge) save you.
	if Config.SkillAddon then
		-- SA grabs are a subset of the Must-Dodge list: they respect the MustDodge master toggle.
		-- If user empties MustDodgeStyles and turns off MustDodge, SA grabs also stop force-dodging.
		if Config.MustDodge and Config.SA_WrestlingGrab and st == "wrestling" and th.kind == "M2" then return true end
		if Config.MustDodge and Config.SA_DirtyGrab and st == "dirty" and (th.kind == "M2" or th.kind == "SKILL") then return true end
	end
	if not Config.MustDodge then return false end
	local byStyle = Config.MustDodgeStyles and Config.MustDodgeStyles[st]
	if byStyle and (byStyle[th.kind] or byStyle.all) then return true end
	-- [V106] АВТО-ДЕТЕКТ грэб-M2 по CombatConfig (без новых top-level локалов — лимит 200/функция;
	-- кэш держим на GameData, детект инлайн). Командный грэб/слэм (Wrestling, Kure, …) проходит
	-- СКВОЗЬ блок и на попада��ии выруба��т парри (M2SlamParryWindowDisableDuration) → т��лько додж.
	-- Опознаём стиль по конфигу: любой M2Grab*/M2Slam*-атрибут ⇒ M2 этого стиля = грэб. Так новые
	-- грэб-стили ловятся ��ез ручного пополнения MustDodgeStyles.
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
-- [V140] Публикуем на State, чтобы counterCandidate (объявлен ВЫШЕ) мог отфильтровать
-- must-dodge угрозы. Через State, а не forward-declare: в этом чанке лимит Luau 200 локалов
-- на функцию уже поджимает (см. комментарий про do-block у визуалов), новый top-level local
-- добавлять нельзя.
State.isMustDodge = isMustDodge

-- ============================ AutoPlay addon (V99) ============================
-- Автоатака через РОДНУЮ tryM1() игры (M1.lua). Фа��ты из ��ампа (CombatConfig.ClientPredict.M1):
--   • ParryStun.M2 = 1.0с                    — жертва M2-парри з��станена 1с (окно добивания);
--   • AttackDuration = 0.45с                 — реальный ре��т M1 (tryM1 сам гейтит по нему, u21);
--   • LocalParryAttackLockoutSeconds = 0.15с — после НАШЕГО парри tryM1 залочен 0.15с (u32);
--   • LocalBlockAttackLockoutSeconds = 0.15с — после блока/гардбрейка (u33);
--   • DefaultHitboxDelay = 0.32с             — хитбокс M1 долетает ��ерез 0.32с (для interrupt-расчёта).
-- tryM1() = ровно то, что делает v1.OnM1Activated (игровой ��лик): проигрывает верную анимацию
-- комбо, сам проверяет ВСЕ ��улдауны/атрибуты, шлёт ServerCheck с правильным внутренним u25.
-- Никаких hold/задержек: зовём напрямую → мгновенно и легитно. Бьём как только tryM1 разрешит.
--   • iframe/hyperarmor-стили (boxing M2GrantsIFrames, wrestling M2GrantsHyperArmor)
--       перебить НЕЛЬЗЯ — их только парировать.
-- Всё состояние И функции держим на State.ap — модуль впритык к лимиту 200 локалов на функцию,
-- поэ��ому НИ ОДНОГО нового top-level local (это переполняло регистры → CompileError).
State.ap = {
	m1         = nil,    -- кэш РОДНОГО модуля M1 игры (return-таблица v1 с .OnM1Activated)
	tryM1Fn    = nil,    -- сам локальный tryM1() (upvalue #1 в OnM1Activated) — даёт bool успеха
	comboIdx   = nil,    -- upvalue-индекс u19 (combo-счётчик) в tryM1 — для Fixed-режима и custom-fire
	m1Tried    = false,  -- уже пытались резолвить модуль (не с��амить резолв каждый кад��)
	-- [V105] CUSTOM FIRE: свой быстрый M1 в обход 450мс-троттла игры. Разметка upvalue tryM1
	-- ЯКОР��ТСЯ на CombatRemoteClient (единственный upvalue-table с полем .Fire) и все прочие индексы
	-- берутся ФИКСИРО��АННЫМ смещением от него + строгая проверка типов (см. getM1). ��очный порядок
	-- upvalue tryM1 (из дампа M1.lua): u29,Player,u23,u21,u32,u33,isBlocked,getFinalM1AnimSpeed,
	-- u19,getM1Animations,AnimHandler,playM1SwingAnimation,Evasive,MovementSvc,scheduleM1SwingTimers,
	-- u25,u26,u27,u28,CombatRemoteClient. Т.е. от CRC(=C): u28=C-1 u27=C-2 u26=C-3 u25=C-4
	-- schedule=C-5 playSwing=C-8 getAnims=C-10 u19=C-11 getSpeed=C-12 u33=C-14 u32=C-15 u21=C-16.
	fireOK     = false,  -- разметка custom-fire успешно проверена
	u25idx     = nil,    -- upvalue-индекс u25 (счётчик свингов)
	u26idx     = nil,    -- upvalue-индекс u26
	u21idx     = nil,    -- upvalue-индекс u21 (bool-троттл AttackDuration: `if not u21 then return`)
	u32idx     = nil,    -- upvalue-индекс u32 (parry-lockout timestamp)
	u33idx     = nil,    -- upvalue-индекс u33 (block-lockout timestamp)
	u27tbl     = nil,    -- таблица u27 (swingId → combo)
	u28tbl     = nil,    -- таблица u28 (swingId → animation)
	crc        = nil,    -- CombatRemoteClient (у него .Fire с настоящими рейт-лимитами сервера)
	getAnims   = nil,    -- getM1Animations()
	getSpeed   = nil,    -- getFinalM1AnimSpeed(char, combo)
	playSwing  = nil,    -- playM1SwingAnimation(char, combo, spd, false)
	nextM1At   = 0,      -- анти-спам ПОЛЛА (сам tryM1 гейтит настоящий рей�� по AttackDuration 0.45с)
	punishTgt  = nil,    -- модель врага, котор��го добива��м после ��арри
	punishUntil= 0,      -- докуда действует окно добивания (по времени стана)
		punishFresh= false,  -- первый post-parry свинг обходит sustained cadence, но не server min-gap
		-- [V153/AUTOPLAY-TXN] Один физический M1 = одна транзакция. Раньше NoDelay каждый Heartbeat
		-- стирал M1/CombatAttacking, поэтому canAttack снова станови��ся true через 10–20мс и scheduler
		-- повторно запускал playSwing + ServerCheck одного окна. Диаг это доказал сериями AUTOPLAY
		-- t=... через 0.01–0.02с. m1Txn не зависит о�� стираемых атрибутов: до её untilAt второй M1
		-- физически не создаётся. suppressed копит число подавленных Heartbeat-повторов для DONE-лога.
		m1Txn      = nil,
		m1TxnSeq   = 0,
		busyAttrs = {
		"Stunned", "Ragdoll", "Downed", "GuardBroken", "CantAnything",
		"M1Cooldown", "ParryAttackLockout", "BlockAttackLockout",
	},
}

-- Резолвим РОДНОЙ модуль M1 игры и его ЛОКАЛЬНУЮ tryM1(). Бьём через tryM1() напрямую —
-- это ровно то, что делает игровой обработчик клика (v1.OnM1Activated просто вызывает tryM1):
-- проигрывает ПРАВИЛЬНУЮ анимацию комбо (u19 1→4), сам пр��веряет ВСЕ кулдауны/атрибуты
-- (Equip, Blocking, u21=AttackDuration 0.45с, u32=parry-lockout 0.15с, u33=block-lockout, стан…)
-- и шлёт ServerCheck с ПРАВИЛЬНЫМ внутренним swingId u25. Никаких задержек/hold — мгновенно и легит.
-- tryM1 возвращает true, если свинг реально прошёл (у н��с есть точный сигнал успеха).
-- Прежний прямой ServerCheck с выдуманным id сервер игнорировал (нет анимации/сессии). Hold-эмуляция
-- тоже плоха — она ждёт серверный hold-хендшейк (вст��оенная задержка). Модули в Hidden →
-- (1) путь-require, (2) глубокий поиск, (3) filtergc по ключам. tryM1 достаём debug.getupvalue.
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
	-- filtergc-фолбэк: находим return-таблицу v1 по её характерному набору методов
	if not State.ap.m1 and type(filtergc) == "function" then
		pcall(function()
			local t = filtergc("table",
				{ Keys = { "Hold", "OnM1Activated", "ServerResponse", "OnHoldSwing" } }, true)
			if type(t) == "table" and type(t.OnM1Activated) == "function" then State.ap.m1 = t end
		end)
	end
	-- дост��ём локальную tryM1(): её единственный upvalue #1 в OnM1Activated (даёт bool успеха)
	if State.ap.m1 and type(debug) == "table" and type(debug.getupvalue) == "function" then
		pcall(function()
			local fn = debug.getupvalue(State.ap.m1.OnM1Activated, 1)
			if type(fn) == "function" then State.ap.tryM1Fn = fn end
		end)
			-- [V105] РАЗМЕТКА через ЯКОРЬ CombatRemoteClient. Прежний поиск «первый int в [0,4]»
			-- был НЕВ��РЕН: u32/u33 (parry/block-lockout timestamps) на старте = 0 → попадали под
			-- фильтр и comboIdx резолвился в u32, а от него все смещения съезжали → fireOK=false и
			-- combo Fixed не работал. CombatRemoteClient — ЕДИНСТВЕННЫЙ upvalue-table с полем .Fire
			-- (function), поэтому это надёжный якорь. О���� него все индексы — фиксированным смещением,
			-- каждый проверяем по типу. Совпал весь профиль → вк��ючаем custom-fire.
			if State.ap.tryM1Fn and type(debug.setupvalue) == "function" then
				pcall(function()
					local fn = State.ap.tryM1Fn
					local function uv(i)
						local ok, v = pcall(debug.getupvalue, fn, i)
						if ok then return v end
						return nil
					end
					-- найти якорь C = CombatRemoteClient (table c .Fire)
					local C
					for i = 1, 40 do
						local v = uv(i)
						if type(v) == "table" and type(rawget(v, "Fire")) == "function" then C = i; break end
						if v == nil and i > 25 then break end
					end
					if not C then return end
					local getSpeed = uv(C - 12)  -- getFinalM1AnimSpeed
					local u19v     = uv(C - 11)  -- u19 (combo)
					local getAnims = uv(C - 10)  -- getM1Animations
					local playSw   = uv(C - 8)   -- playM1SwingAnimation
					local u25v     = uv(C - 4)   -- u25
					local u26v     = uv(C - 3)   -- u26
					local u27v     = uv(C - 2)   -- u27
					local u28v     = uv(C - 1)   -- u28
					local u21v     = uv(C - 16)  -- u21 (bool throttle)
					local u32v     = uv(C - 15)  -- u32 (parry-lockout)
					local u33v     = uv(C - 14)  -- u33 (block-lockout)
					-- ЯДРО custom-fire: этих полей достаточно, чтобы бить своим билдером.
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
						-- lockout-снятие (u21/u32/u33) — ОПЦИОНАЛЬНО (best-effort): ставим индексы
						-- только если профиль сошёлся. Иначе fireM1Custom их просто не трогает.
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

-- [V153] Общая weak-registry владельцев AnimationTrack. movement.lua читает ЭТУ ЖЕ таблицу и
-- поэтому больше не примет AutoPlay/Anti-AutoParry Action4 за серверный ручной 4thM1. Значение
-- живёт в getgenv, потому что scripts загружаются независимо; weak keys не удерживают старые треки.
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
	-- Даже если Action4-трек остановил desync/AnimationHandler, окно отправленного ServerCheck
	-- не исчезает. До untilAt транзакцию не закрываем: ранний Stop и был источником повторного M1.
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
	-- Stopped — факт только для причины DONE. Раньше освобождение прямо по Stop разрешало новый
	-- swing в том же серверном окне; теперь минимальный floor до untilAt остаётся обязательным.
	pcall(function()
		track.Stopped:Connect(function()
			if State.ap.m1Txn == tx then tx.trackStopped = true end
		end)
	end)
	return track
end

-- [V105] СВОЙ БЫСТРЫЙ M1 — ВСЕГДА используется (свой билдер ��место игрового tryM1). Игров��й
-- tryM1 после каждого свинга зовёт scheduleM1SwingTimers → u21=false на AttackDuration(0.45с) →
-- следующий удар только через 0.45с. Мы повторяем ХВОСТ tryM1 (выбор combo, u25++/u27/u28,
-- анимация, CombatRemoteClient.Fire), Н�� трогаем scheduleM1SwingTimers, и СНИМАЕМ клиентские локи
-- (u21=true, u32/u33=0) → троттла нет. Единственный настоя��ий потолок — сам CombatRemoteClient.Fire
-- (M1.ServerCheck: min 80мс, sustained 4/с): он вернёт false, если рано, и тогда мы НЕ двигаем u25
-- → последовательность серверу цела (без «дыр»). combo: Fixed → ровно AP_FixedHit, иначе 1→4.
-- wantCombo (опц.) — при��удительный номер удара для тест-свинга.
function State.ap.fireM1Custom(char, model, wantCombo, ignoreRate, priority, dropGuard)
	local ap = State.ap
	if not (ap.fireOK and ap.tryM1Fn) then return false end
	local ok = false
	pcall(function()
		local now = os.clock()
		-- [V153] ПЕРВЫЙ и главный гейт. Он стоит ДО выбора combo, запуска трека и FireServer.
		-- В diag V152 атрибуты M1/CombatAttacking стирались NoDelay и повторные вызовы проходили
		-- каждые 10–20мс. Теперь незавершённая собственная транзакция запрещает весь повторный путь.
		if ap.m1TxnActive(now) then return end
		-- ═══════════ [V161] AUTOPLAY УСТУПАЕТ ПРОЦУ ALI EVASIVE COUNTER ═══════════
		-- Диаг: НИ ОДНОГО ALI-EVCOUNTER-SEND за сессию, зато повторяющаяся пара
		--     ALI-PERFECT-CONFIRM t=10808.82 dodgeAgo=301ms iframeConfirmed=true
		--     ALI-EVCOUNTER-WAIT  t=10808.82 gate=combat-attacking perfectAgo=2ms
		-- то есть проц приходил и через 2мс глушился атрибутом CombatAttacking, а окно закрывалось
		-- по ALI-EVCOUNTER-EXPIRE. Это и есть «Ali Counter то работает, то нет».
		-- Гейт по CombatAttacking в самой контре ВЕРЕН и снять его нельзя — M2_ModuleScript:1494
		-- (`if v188:GetAttribute("CombatAttacking") then return end`) стоит в предполётном списке
		-- перед Fire("M2","ServerCheck") на :1568, поэтому M2 при этом флаге физически не уйдёт.
		-- Виноват не гейт, а ИСТОЧНИК флага: CombatAttacking во всём клиентском дампе только
		-- ЧИТАЕТСЯ и нигде не ставится — это серверный флаг нашей собственной атаки. Его держал
		-- наш же AutoPlay M1, непрерывно спамящий ServerCheck, и тем сжигал проц с cooldown 6с
		-- (CombatConfig:261 EvasiveCounter = {Cooldown=6, MaxRange=22, IgnoreM2Cooldown=true}).
		-- Приоритет очевиден: M1 повторяется каждые ~90мс, а проц даётся раз в 6 секунд и требует
		-- perfect-dodge. Поэтому на время живого неотстрелянного проца M1 молчит.
		-- Важно: IgnoreM2Cooldown снимает ТОЛЬКО M2Cooldown и делает это на сервере; на
		-- CombatAttacking он не распространяется, так что уступка обязательна, а не косметична.
		if Config.SkillAddon and Config.AliEvasiveCounter then
			local etx = State.dodgeTxn
			if etx and etx.pending and etx.perfectConfirmed and not etx.evCounterFired then
				return
			end
		end
		-- [V153] u21/u32/u33 больше НЕ пишем. Дамп M1.lua показывает, что их читает только мёртвая
		-- tryM1/OnM1Activated; custom builder всё равно строит и шлёт M1 сам. Запись создавала лишь
		-- ложное ощущение «снятых задержек» и второго владельца M1-машины.
		-- выбр��ть номер удара ��омбо
		local combo
		if wantCombo then
			combo = math.clamp(math.floor(wantCombo), 1, 4)
		elseif Config.AP_ComboMode == "Fixed" then
			combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
		else
			-- [V153/NoDelay] AutoPlay-владелец визуального combo использует пул 1→2→3→1.
			-- Серверный p55 этим НЕ подменяется (он авторитетен и приходит через OnHoldSwing), но
			-- собственный Action4-finisher AutoPlay больше не создаёт и не накладывает на decoy.
			combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 3) + 1
		end
		-- [V107] РЕЙТ-ГАРД: равномерный ~AP_MaxPerSec/с (по умолчанию 6 = server sustained low).
		-- ��аньше слали через ap.crc.Fire, а он режет 4/с ФР��НТ-ЛОАДОМ (4 подряд → тишина). Теперь
		-- шлём НАПРЯМУЮ в ServerRemote (минуя клиентский кап) со своим равномерным шагом → быстрее,
		-- анимация успевает, и весь стан-window заполнен. Тест-свинг (ignoreRate) шлёт всегда.
		if not ignoreRate then
			local rate = math.max(1, Config.AP_MaxPerSec or 6)
			-- Первый punish/interrupt не должен ��дать равномерный sustained cadence. Он всё равно
			-- соблю��ает подтверждённый ServerMinInterval=80мс; последующие combo-свинги равномерные.
			local gap = priority and (Config.AP_PunishFastGap or 0.08)
				or math.max(Config.AP_MinSendGap or 0.09, (1 / rate) * 0.97)
			if (now - (ap.m1SendLast or 0)) < gap then return end      -- ещё рано — не шлём
			if (now - (ap.m1WinStart or 0)) >= 1 then ap.m1WinStart, ap.m1WinCount = now, 0 end
			if (ap.m1WinCount or 0) >= rate then return end             -- server sustained-окно исчерпано
		end
		-- [V140/BUG] ДЁРГАНИЕ АНИМАЦИИ ПРИ ДЕСИНКЕ / ANTI-AUTOPARRY.
		-- В норме повторный свинг держит canAttack: сервер ставит на нашем персонаже атрибут
		-- "M1", и до его снятия мы не стреляем — анимация успевает проиграться целиком.
		-- Но при десинке (или когда враг с anti-autoparry вынуждает сервер отклонять наши
		-- ServerCheck) атрибут НЕ выставляется: canAttack остаётся true, рейт-гард пропускает
		-- нас каждые AP_PunishFastGap=80мс, и playSwing РЕСТАРТИТ трек с tp=0. Анимация длиной
		-- ~0.45с (AttackDuration) пер��з��п��скалась 5-6 раз, от��юда видимое дёрганье, которого
		-- «при обычных атаках нет» — там гейтом служит серверный атрибут.
		-- Ставим ЛОКАЛЬНЫЙ пол на перезапуск: он не зависит от серве��ных атрибутов и потому
		-- работает именно в том режиме, где отваливается штатный гейт. Пропорция от реальной
		-- длины трека, а не константа: скорость свинга зависит от стиля и aMult.
		if Config.AP_AnimGuard ~= false and (now - (ap.swingAnimAt or 0)) < (ap.swingAnimMin or 0) then
			return
		end
		local anims = ap.getAnims()
		local v53   = anims and anims[combo] or nil
		if not v53 then return end
		local spd = 1
		pcall(function() spd = ap.getSpeed(char, combo) or 1 end)
		-- [V150] Длину считаем ДО playSwing: окно защиты трека нужно открыть раньше, чем трек
		-- запустится, иначе между запуском и установкой окна успевает влезть кадр планировщика
		-- с playBlockAnim — то есть ровно тот перехлёст, который мы убираем.
		-- [V150] ЧЕСТНО про источник длины. Прежний код (V141) писал
		--     len = v53.Length / spd
		-- и это НИКОГДА не работало: v53 приходит из ap.getAnims(), который повторяет игровой
		-- getM1Animations (M1.lua:64-69) и возвращает объекты `Animation` (WaitForChild("1stM1")).
		-- У класса Animation свойства Length нет вообще — есть только у AnimationTrack. Индексация
		-- падала внутрь pcall, len оставался 0 и молча уходил в фолбэк 0.45. То есть «длина берётся
		-- из самой анимации», как было написано в комментарии V141, — неправда.
		-- Берём длительность из ЖИВОГО конфига игры (CombatConfig.ClientPredict.M1.AttackDuration,
		-- дефолт 0.45 при недоступности) и делим на скорость свинга — это тот же множитель, по
		-- которому игра растягивает трек в getFinalM1AnimSpeed.
		local len = 0
		pcall(function()
			local cp = GameData.cfg and GameData.cfg.ClientPredict
			local m1 = cp and cp.M1
			len = tonumber(m1 and m1.AttackDuration) or 0
		end)
		if len <= 0 then len = Config.AP_AnimFallback or 0.45 end
		len = len / math.max(spd, 0.01)
		-- [V150] Гасим ЖИВОЙ блок-трек сами: игра категорию "Blocking" не трогает (см. разбор
		-- в playBlockAnim), а без этого свинг стартует уже под перекрытием. Только косметика:
		-- State.blocking и серверный статус блока не меняем — это ��елает ветка dropGuard ниже.
		State.swingAnimUntil = now + len
		if AnimLib.tracks.Blocking or (char:GetAttribute("Blocking") == true) then
			stopBlockAnim()
		end
		-- [V153/OWNERSHIP-RACE] AnimationPlayed срабатывает внутри LoadAnim/Play раньше, чем
		-- markM1Track получает трек. Короткий intent до Play не даёт NoDelay принять Action4 за ручной 4thM1.
		local owners = ap.trackOwners()
		if owners then
			owners.__intent = { owner = "autoplay", char = char, animationId = v53.AnimationId, expires = now + 0.15 }
		end
		-- Сначала подтверждаем, что родная M1-анимация реально запустилась. Только после этого
		-- interrupt опускает guard; при failed play текущая защи��а остаётся нетронутой.
		local played = false
		pcall(function() played = ap.playSwing(char, combo, spd, false) == true end)
		if not played then
			if owners and owners.__intent and owners.__intent.char == char then owners.__intent = nil end
			-- Свинг не стартовал — окно защиты немедленно закрываем, иначе оно зря глушило бы
			-- guard-анимацию до конца len при пол��ом отсутствии свинга.
			State.swingAnimUntil = 0
			return
		end
		-- ═══════ [V141] ПОЧЕМУ ДЁРГАЛОСЬ В AUTOPLAY, НО НЕ В TEST SWING ═══════
		-- Разница между двумя путями ровно одна: КОЛИЧЕСТВО вызовов.
		--   testSwing (:3629)  ��� fireM1Custom(char, nil, combo, true) — ОДИН вызов, трек играет
		--                        целиком, перезапускать его некому → дёрганья нет.
		--   AutoPlay (:3594)   → fireM1Custom в цикле, каждый кадр поллинга.
		-- То есть баг н�� в самом свинге, а в том, ЧЕРЕЗ КАКОЕ ВРЕМЯ разрешён следующий.
		--
		-- ВИНОВАТ БЫЛ МОЙ ЖЕ ГАРД V140, а не игра. Он считался так:
		--     min(len * 0.55, 0.30)  →  min(0.45*0.55, 0.30) = min(0.2475, 0.30) = 0.2475с
		-- при реальной длине трека ~0.45с. Гард РАЗРЕШАЛ новый свинг на 55% анимации, поэтому
		-- каждый следующий удар обрывал предыдущий на сере��ине. И это не просто рестарт одного
		-- трека: у каждого удара комбо СВОЯ анимация, а playM1SwingAnimation (M1.lua:252)
		-- сначала делает LoadAnim нового трека, и лишь потом отложенный task.delay(0.1) гасит
		-- остальные M1-треки с фейдом 0.06 (M1.lua:271-289). В итоге 2 свинг-анимации
		-- накладывались и обрывались фейдом — это и есть видимое «дёрганье и недоигрывание».
		--
		-- ИСПРАВЛЕНИЕ: ждём ПОЛНУЮ длину трека, а не долю от неё. Никаких коэффициентов —
		-- длина берётся из самой анимации и делится на её скорость, то есть источник данных
		-- тот же, что у игры. Так темп сам приходит к штатному AttackDuration (0.45с), при
		-- котором анимация успевает доиграть — ровно как при обычных атаках игрока.
		-- [V150] len уже посчитан выше (до playSwing), повторный расчёт удалён.
		ap.swingAnimAt  = now
		ap.swingAnimMin = len
		if dropGuard and (State.blocking or char:GetAttribute("Blocking") == true) then
			State.blocking, State.holdUntil = false, 0
			stopBlockAnim()
			pcall(sendDeactivate, true)
		end
		local newId = (debug.getupvalue(ap.tryM1Fn, ap.u25idx) or 0) + 1
		-- шлём НАПРЯМУЮ: сервер ст��оит M1-хитбокс по нашему LookVector в момент приёма ServerCheck
			ServerRemote:FireServer({ Type = "Combat", Action = "M1", Func = "ServerCheck" }, newId)
			ap.m1SendLast = now
			ap.m1WinCount = (ap.m1WinCount or 0) + 1
			-- фиксируем состояние ровно как игровой tryM1 (для клиентской сверки с ServerResponse)
			debug.setupvalue(ap.tryM1Fn, ap.comboIdx, combo)
			debug.setupvalue(ap.tryM1Fn, ap.u25idx, newId)
			debug.setupvalue(ap.tryM1Fn, ap.u26idx, newId)
			ap.u27tbl[newId] = combo
			ap.u28tbl[newId] = v53
			-- [V153] Транзакция создаётся только ПОСЛЕ реального playSwing + FireServer. untilAt
			-- выведен из живого AttackDuration / скорости, а не из нового slider/cooldown.
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

-- можем ли физически атаковать прямо сейчас (по атрибутам своего перса)
function State.ap.canAttack(ignoreBlocking)
	local c = localChar()
	if not c then return false end
	if c:GetAttribute("Equip") ~= true then return false end   -- ��уки не одеты ��� бить нельзя
	if not ignoreBlocking and c:GetAttribute("Blocking") == true then return false end
	-- Те же конфликтующие combat-гейты, что стоят в родной tryM1. Custom builder их раньше
	-- обходил и запускал M1 поверх другой своей атаки; игровой модуль затем StopAnim'ил трек.
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

-- реальный р��диус нашего M1 С УЧЁТОМ РОСТА (крупнее аватар → больше хитбокс/дос��аёт да��ьше)
function State.ap.reach()
	local base = Config.AP_BaseReach or 5.5
	-- ForwardOffset тоже style-specific. Берём живой CombatConfig, а запас 1.5 stud оставляем
	-- как полов��ну стандартного M1 box; рост ниже масштабирует итог как HitboxSizeMultiplier.
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

-- flat-дистанция до модели с ПИНГ-ПРЕДИКТОМ е�� позиции (сервер видит врага впереди нашего экрана)
function State.ap.flatDist(model)
	local myHRP = localHRP()
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not (myHRP and hrp) then return math.huge end
	local aim = hrp.Position
	local lead = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.22)
	if lead > 0 then
		local v = hrp.AssemblyLinearVelocity   -- hrp уже проверен выше; прямое чтение бе�� closure
		aim = aim + Vector3.new(v.X, 0, v.Z) * lead
	end
	return (Vector3.new(myHRP.Position.X, 0, myHRP.Position.Z)
	        - Vector3.new(aim.X, 0, aim.Z)).Magnitude
end

-- снап лицом ТОЧНО на цель прямо сей��ас + держим предиктивный facing на окно хитбокса.
-- Сервер строит M1-хитбокс по нашему LookVector в момент ServerCheck.
function State.ap.snapTo(hrp)
	setFaceGoal(hrp, true, Config.AP_FaceHold or 0.35)
	local myHRP = localHRP()
	if myHRP then
		local d = flatDirTo(myHRP.Position, hrp.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
	end
end

-- Предсказать момент НАШЕГО следующего M1 тем же источником, что использует игра:
-- style+combo CombatConfig, множитель роста и ping animation multiplier.
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
	-- [V139/PERF] Скан вариантов кэшируется ПО СТИЛЮ. Сами задержки — константы CombatConfig
	-- (GetStyleM2HitboxDelay), они не меняются в рантайме; менять их может только смена стиля,
	-- а она и есть ключ кэша. Б��з кэша каждый вызов гонял pcall(GetStyleM2Variants) плюс по
	-- 2 pcall внутри hitTimelineBase на КАЖДЫЙ вариа��т — ~6 защищённых вызовов и обход хеша
	-- в кадре, где мы и без того боремся за миллисекунды до press-дедлайна.
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
		info.variant = bestId      -- nil для стилей без вариантов → базовая M2HitboxDelay
		if not bestBase then
			local okb, base = pcall(hitTimelineBase, info, nil)
			if okb and type(base) == "number" then bestBase = base end
		end
		-- false = «у эт��го стиля база не считается»; отличаем от nil (ещё не считали).
		hit = bestBase and { id = bestId, base = bestBase } or false
		vc[style] = hit
	end
	if hit == false then return nil, nil end
	info.variant  = hit.id
	local bestId, bestBase = hit.id, hit.base
	return hitTimeline(info, nil, attackSpeedMult(char), bestBase), bestId
end

-- Реч НАШЕЙ M2. Отдельно от reach(): у M2 сво�� ForwardOffset, и часть стилей доводит себя
-- лунжем (Ali M2StepForwardStuds=2 через CombatStepUtils.ApplyM2StepForward).
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

-- Готова ли M2 к отправке ПРЯМО СЕЙЧАС. Кулдаун держит игра (Styles.*.M2Cooldown), атрибут —
-- серверн��я истина; локальный гэп закрывает только сетевое окно до появления атрибута.
function State.ap.m2Ready()
	local c = localChar()
	if not c then return false end
	if c:GetAttribute("M2Cooldown") == true or c:GetAttribute("M2CD") == true then return false end
	if c:GetAttribute("M2") == true or c:GetAttribute("PendingM2") == true then return false end
	-- [V139] ЕДИНЫЙ ГЕЙТ НА ВСЮ M2. Counter (fireBoxingCounter/Ali) �� interrupt шлют ОДНУ И ТУ ЖЕ
	-- Action="M2" — это один физический ресурс с одним кулдауном. Если смотреть только на свою
	-- метку, два пути стреляют в один кадр: вторая M2 отлетает в ServerMinInterval["M2.ServerCheck"]
	-- =0.15, но обе ме��ки уже обновлены → следующая ��АЛИДНАЯ M2 глушится своим же гэпом.
	-- Поэтому берём ПОЗДНЕЙШУЮ из двух отправок.
	local lastM2 = State.ap.m2SendLast or 0
	local lastCn = State.lastCounter or 0
	if lastCn > lastM2 then lastM2 = lastCn end
	if (os.clock() - lastM2) < (Config.AP_M2Gap or 0.30) then return false end
	return true
end

-- Отправить НАШУ M2 по цели. Обязательный порядок (иначе сервер отклонит): развернуться лицом
-- (хитбокс строится по нашему LookVector в момент приёма ServerCheck) → опустить guard (с
-- поднятым блоком M2 не запускается) ��� зарулить MoveDirection под нужный вариант → FireServer.
function State.ap.fireM2(model, why, variant)
	local ap = State.ap
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	ap.snapTo(hrp)
	local c = localChar()
	if State.blocking or (c and c:GetAttribute("Blocking") == true) then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)   -- force: guard обязан опуститься, иначе M2 ��е пройдёт
	end
	if variant then steerM2Variant(variant) end
	local ok = pcall(function()
		ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	end)
	if not ok then return false end
	local now = os.clock()
	ap.m2SendLast    = now
	-- [V139] Обратная сторона единого гейта: counterReady() сверяется с State.lastCounter, и
	-- если interrupt-M2 её не отметит, counter выстрелит второй M2 в то же окно (обе уйдут в
	-- ServerMinInterval=0.15 и обе потеряются). Отмечаем обе метки при любой отправке M2.
	State.lastCounter = now
	State.flashUntil = now + 0.25
	State.apM2Count  = (State.apM2Count or 0) + 1
	return true
end

-- Можно ли физическ�� сбить эту атаку. IFrames/HyperArmor берём из живого CombatConfig,
-- а не из списка стилей: обновлени�� иг��ы автоматически сохранят правильный гейт.
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

-- Контрудар запускает тот же AutoPlay M1 lifecycle (rotation+animation+ServerCheck), но
-- НЕ за��еняет parry: scheduler продолжает обычную защиту как страховку до контакта.
function State.ap.tryInterrupt(now, th, threatCount)
	local ap = State.ap
	if not Config.AutoPlay or Config.AP_Interrupt == false then return false end
	if not th or th.pressed or th.dodged or th.interruptAttempted then return false end
	-- [V138] Если параллельно есть второй враг чья атака приходит РАНЬШЕ DodgeHorizon,
	-- не прерываем: нам нужны i-frames/block для той второй атаки.
	-- Но если второй враг далеко (> DodgeHorizon от now) — это будущая угроза, прерываем смело.
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
	-- M1 тоже можно сбить, если наш style/height-scaled M1 действительно быстрее.
	-- SKILL не включаем: часть спец-атак всё ещё имеет только fallback timing 0.35 без marker/config.
	if th.kind ~= "M1" and th.kind ~= "M2" then return false end
	-- Unblockable/grab policy всегда важнее агрессии: эти атаки уже имеют отдельный must-dodge путь.
	if isMustDodge(th) then return false end
	if not ap.interruptible(th) or not ap.canAttack(true) then return false end
	local enemyLeft = (th.contactAbs or now) - now
	-- [V138] Дополнительная проверка: убедиться что enemyLeft ещё достаточно велик
	-- (не пытаться сбивать атаку у которой осталось < 50ms — уже поздно).
	if enemyLeft < 0.05 then return false end
	-- [V138] Разные margin для M1 �� M2: M2 медленнее (hitboxDelay ~0.59с), у нас больше
	-- времени чтобы опередить. M1 быстрее — нужен строгий margin чтобы не промахнуться.
	local baseMargin = th.kind == "M2" and (Config.AP_InterruptMargin or 0.055) * 0.6
	                                    or  (Config.AP_InterruptMargin or 0.055)
	local netLag = getPingRaw() * (Config.AP_InterruptNetK or 0.5)

	-- ── [V139] КАНДИДАТ M1 ───────────────────────────────────────────────────────────────────
	local m1Hit, m1Combo = nil, nil
	if ap.flatDist(th.attackerModel) <= ap.reach() then
		local d, combo = ap.ownM1Delay()
		if d then m1Hit, m1Combo = d + netLag, combo end
		if m1Hit and m1Hit + baseMargin >= enemyLeft then m1Hit = nil end   -- не успеваем
	end

	-- ── [V139] КАНДИДАТ M2 ──���──────────────────────────────────────────────���─────────────────
	-- Отдельный реч (свой ForwardOffset + лунж) и отдельный гейт готовности (кулдаун 7с).
	local m2Hit, m2Var, m2Iframes = nil, nil, false
	if Config.AP_InterruptM2 ~= false and ap.m2Ready()
	   and ap.flatDist(th.attackerModel) <= ap.reachM2() then
		local d, variant = ap.ownM2Delay()
		if d then
			m2Iframes = ap.m2GrantsIFrames()
			-- ДВЕ РАЗНЫЕ ПОСТАНОВКИ ЗАДАЧИ:
			--  • M2 БЕЗ i-frames — это чистая гонка, как M1: наш удар должен прийти ра��ьше.
			--  • M2 С i-frames — гонку выигрывать НЕ НУЖНО. Достаточно, чтобы сервер принял M2 и
			--    поднял IFRAMES до контакта: внутри окна неуязвимости вражеский удар не проходит
			--    физически, поэтому даже ����проигранный» размен для нас бесплатный. Дедлайн тут —
			--    не наш hitbox delay, а только сетевое плечо до подъёма i-frames.
			if m2Iframes then
				if netLag + (Config.AP_M2IFrameMargin or 0.035) < enemyLeft then
					m2Hit, m2Var = d + netLag, variant
				end
			elseif d + netLag + baseMargin < enemyLeft then
				m2Hit, m2Var = d + netLag, variant
			end
		end
	end

	-- ── [V139] ВЫБОР ─���───────────────────���───────────────────────────────────────────────────
	-- Правило (по ТЗ): M2 успевает → M2. Оба успевают → тоже M2, она объективно лучше
	-- (урон 8.5 против 5, нокбек сбивает комбо целиком, а с i-frames ещё и страхует нас).
	-- M1 остаётся ровно для случая, когда M2 не успела/на кулдауне/вне реча.
	local useM2 = (m2Hit ~= nil)
	if useM2 and m1Hit and Config.AP_InterruptPreferM2 == false then
		-- Если пользователь явно снял приоритет M2 — берём тот, что физически раньше.
		useM2 = m2Hit < m1Hit
	end
	if not useM2 and not m1Hit then return false end

	local ownHit, tag
	if useM2 then
		if not ap.fireM2(th.attackerModel, "interrupt", m2Var) then
			-- M2 не ушла (снап/ремоут) — не теряем окно, пробуем M1 тем же кадром.
			if not m1Hit then return false end
			useM2 = false
		end
	end
	if useM2 then
		ownHit = m2Hit
		tag = ("M2%s%s"):format(m2Var and ("/" .. m2Var) or "", m2Iframes and "+IF" or "")
		-- [V146] КОРЕНЬ «доджа в своих же i-frames». Этот путь пускает нашу M2 (ту же, что контра)
		-- и при m2Iframes даёт ту же неуязвимость, но отметку не ставил ��ИКОГДА — её ставила только
		-- fireBoxingCounter. Поэт��му counterPreemptsDodge не знал о нас ничего, и escape-ветка
		-- разрешала додж через 80мс: `INTERRUPT t=47430.40 via=M2+IF` → `DODGE t=47430.48`.
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
	-- Контрудар больше не владеет scheduler до ETA: обычный parry остаётся страховкой,
	-- если сервер не п��дтвердит interruption. M1 уже ушёл с теми же animation+rotation.
	return false
end

-- послать ЛЕГИТНЫЙ M1 по цели:
-- БЕЗ собственных лок/задержек — и��ровая tryM1 сама разрешит удар к��к только это ��опустимо
-- (AttackDuration/lockout/стан). Наш nextM1At — лишь троттл ПОЛЛА, чтобы не звать tryM1 сотни
-- раз в кадр; настоящий рейт держит игра. Поэтому добиван��е/перебивание бьёт МГНОВЕННО, как
-- только сервер снимает лок (напр. 0.15с parry-lockout после нашего парри).
function State.ap.fireM1(model, why, priority, dropGuard)
		local ap = State.ap
		local now = os.clock()
		-- [V153] Гейт стоит и в общей обёртке, чтобы fallback tryM1/OnM1Activated тоже не стал
		-- вторым владельцем, если разметка custom-fire однажды не сойдётся после обновления игры.
		if ap.m1TxnActive(now) then return false end
		if now < ap.nextM1At then return false end
		if not ap.canAttack(dropGuard) then return false end
	local m1 = ap.getM1()
	if not m1 then return false end
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	ap.snapTo(hrp)   -- серв��р стро��т хитбокс по нашему LookVector в момент ServerCheck
	ap.nextM1At = now + (Config.AP_PollGap or 0)   -- троттл поллинга (0 = каждый кадр, макс. скорость)
	-- [V105] ВСЕГДА свой билдер (обход троттла + Fixed-combo внутри fireM1Custom). Фолбэк на игровую
	-- tryM1 только если разметка custom-fire не сошлась (fireOK=false) �� тогда б��з обхода троттла.
	local swung = false
	if ap.fireOK then
		local char = localChar()
		if char then swung = ap.fireM1Custom(char, model, nil, false, priority, dropGuard) end
	elseif ap.tryM1Fn then
		local ok, res = pcall(ap.tryM1Fn)   -- true = свинг реально прошёл
		swung = ok and res == true
	else
		pcall(function() m1.OnM1Activated() end)   -- последний фолбэк: без сигнала успеха
		swung = true
	end
		if swung then
			State.status      = "AUTO-M1"
			State.flashUntil  = now + 0.2
			State.autoM1Count = (State.autoM1Count or 0) + 1
			-- [V153] SEND печатает сама транзакция после создания swingId. Старый общий AUTOPLAY
			-- называл любой true «успешным ударом», не показывая id/combo/владельца и засоряя лог.
		end
	return swung
end

-- [V105] ТЕСТ-СВИН�� для UI-кнопки: шлёт один M1 с анимацией комбо, которую использовал бы скрипт
-- (Fixed → AP_FixedHit, иначе следующий по счёту). Цель не нужна — бьём «в воздух» на текущий
-- LookVector. Возвращает (номер_удар��, успех) для нотификации.
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
		ok = ap.fireM1Custom(char, nil, combo, true)   -- ignoreRate: одиночный тест шлём всегда
	elseif ap.tryM1Fn then
		local r; local s = pcall(function() r = ap.tryM1Fn() end); ok = s and r == true
	end
	return combo, ok
end

-- триггер добивания: из onOutcome при result=="PERFECT". attackerName — имя игрока.
function State.ap.onPerfectParry(attackerName, kind)
	if not Config.AutoPlay or Config.AP_PunishOnParry == false then return end
	local plr   = attackerName and Players:FindFirstChild(attackerName)
	local model = plr and plr.Character
	if not model then return end
	-- [V138] Если Boxing Counter только что сработал (≤0.35с назад), M2 уже ушёл —
	-- M1 dobivanie беспо��езно (враг ещё не застанен нашим контером) и только палит кулдаун.
	-- Используем стан от нашего M2 (BoxingCounterStun ~ 0.6с) ��ак окно для AutoPlay по��же.
	if Config.BoxingCounter and (os.clock() - (State.lastCounter or 0)) < 0.40 then return end
	-- окно стана: M2-парри = ParryStun.M2 (1с, надёжно); M1-парри короче (RecoveryLockout врага)
	local stun = (kind == "M2") and (Config.AP_M2Stun or 1.0) or (Config.AP_M1Stun or 0.5)
	State.ap.punishTgt   = model
	State.ap.punishUntil = os.clock() + stun
	State.ap.punishFresh = true
end

-- шаг добивания (ка��дый Heartbeat из schedulerStep, ТОЛЬКО когда нет угроз для бло��а).
-- Спамим fireM1 весь стан-window — игровая tryM1 сама решит, когда реально ударить (снимет
-- 0.15с parry-lockout → бьём сразу, потом каждые ~0.45с AttackDuration, пока враг в стане).
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
	if ap.flatDist(tgt) > ap.reach() then return end   -- вне досягаемости — не бьём воздух
	-- [V110] МГНОВЕННОЕ добивание в ТОМ ЖЕ кад��е. Сразу после парри мы ещё ��ержим guard (Blocking),
	-- а fireM1 самогейтится на Blocking. Раньше step ронял guard и делал `return` → первый добив
	-- терял ЦЕЛЫЙ Heartbeat (~16мс) + воспринимался как «медленный старт». Но sendDeactivate снимает
	-- ЛОКАЛЬНЫЙ атрибут Blocking СИНХРОННО (c:SetAttribute("Blocking", nil)) → canAttack() проходит
	-- уже в этом кадре. Поэтому НЕ делаем return — сразу бьём. Deactivated и ServerCheck уходят на
	-- сервер по одному remote по порядку: сервер снимает guard, затем принимает M1. Угроз нет
	-- (#imminent==0) и цель застанена → ронять guard б��зопасно.
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

-- ═══════ [V145] «СКРИПТУ ПОХУЙ НА КУЛДАУН ДОДЖА» — ВОТ ПОЧЕМУ ═══════
-- Первая строка была `if evasiveGranted() then return true end`, то есть РАННИЙ ВЫХОД,
-- который перепрыгивал СРАЗУ ВСЁ: и DodgeMinSpacing, и серверные IFRAMECD /
-- EvasiveCooldownRemaining, и DodgeCooldown. А в диаге V144 все 20 доджей — это
-- `outnumbered-escape`, то есть evasiveGranted() был true ВСЕГДА (dodges=20,
-- outnumbered-escapes=20). Значит на этой сессии проверка кулдауна не выполнялась НИ РАЗУ.
-- Отсюда и доджи через 0.62с и 1.06с подряд (t=46275.49 → 46276.11 → 46277.17) при
-- DodgeCooldown=2.05, и REJECT'ы «IFRAMES not confirmed» — сервер их не принимал.
--
-- ПОЧЕМУ ИМЕННО IFRAMECD — ПРАВИЛЬНЫЙ ПРИЗНАК, А НЕ ЛИШНЯЯ ПРОВЕРКА. Игра, выдавая грант,
-- САМА гасит эти атрибуты (Evasive_ModuleScript.lua):
--     :100-101 resetLocalDashGatesForOutnumberedGrant() → u6=0, u5=0, u7=0, u8=0
--     :324-325 и :345-346  SetAttribute("IFRAMECD", nil); SetAttribute("EvasiveCooldownRemaining", nil)
-- То есть при ЖИВОМ гранте IFRAMECD физически не может быть true. Если он всё-таки true —
-- грант уже НЕ действует (сервер его снял/израсходовал), а атрибут OutnumberedEvasiveGrant
-- на персонаже ещё висит. Мы читали только этот атрибут и потому верили в грант, которого
-- уже нет. Поэтому теперь IFRAMECD/EvasiveCooldownRemaining — вето даже под грантом.
-- Никакой новой настройки: используем ровно те атрибуты, что читает сама игра.
-- ═══════ [V147] ПОЧЕМУ ФИКС V145 НЕ РАБОТАЛ: ВЕТО ПО IFRAMECD ПОД ГРАНТОМ МЁРТВО ═══════
-- V145 переставил ранний выход `if evasiveGranted() then return true end` ПОСЛЕ вето по
-- IFRAMECD / EvasiveCooldownRemaining и считал вопрос закрытым. Это была ошибка, и дамп
-- доказывает её прямо: игра, выдавая грант, САМА СТИРАЕТ ровно эти два атрибута. Пять
-- независимых точек в Evasive_ModuleScript.lua:
--     :148-149   :169-170   :234-235   :323-324   :344-345
--         Character:SetAttribute("IFRAMECD", nil)
--         Character:SetAttribute("EvasiveCooldownRemaining", nil)
-- Значит при ЖИВОМ гранте IFRAMECD физически не может быть true, вето не срабатывает
-- НИКОГДА, управление доходит до `return true`, и единственным ограничителем остаётся
-- DodgeMinSpacing = 0.35. Логика V145 «если IFRAMECD всё-таки true, значит грант уже снят»
-- верна сама по себе, но описывает случай, который под грантом не наступает.
-- Диаг V144 подтверждает численно: доджи на t=46275.49 → 46276.11 → 46277.17, то есть
-- интервалы 0.62с и 1.06с — оба БОЛЬШЕ 0.35 и оба МЕНЬШЕ DodgeCooldown 2.05.
--
-- ЧТО ГРАНТ ОТМЕНЯЕТ НА С��МОМ ДЕЛЕ. В дампе гейты дэша выглядят так (u51 = hasOutnumberedGrant):
--     :574  if not u51 and v54 < u8 then return end   -- лок после начала атаки (0.2с)
--     :578  if not u51 and v54 < u6 then return end   -- полный кулдаун (Evasive.Cooldown = 1.5)
--     :582  if not u51 and v54 < u7 then return end   -- длительность дэша (0.2с)
--     :625  if not u51 and v54 < u5 then return end   -- ожидание подтверждения (0.18с)
-- ВСЕ ЧЕТЫРЕ снимаются грантом. То есть КЛИЕНТ под грантом действительно разрешает спам —
-- никакого «скрытого» клиентского кулдауна, который мы могли бы прочитать, там нет.
-- Но сервер спам не принимает: отсюда `DODGE-REJECT … IFRAMES not confirmed`.
--
-- ПОЭТОМУ ГЕЙТ СТРОИМ НА ОТВЕТЕ СЕРВЕРА, А НЕ НА НОВОЙ НАС��РОЙКЕ. У нас уже есть
-- авторитетный факт — State.dodgeTxn.confirmed (флаг ставится по реплицированному атрибуту
-- IFRAMES, :4532). Правило [V148], после снятия защёлки V147:
--   • БАЗА под грантом — пол, который игра сама себе пишет в u6 (:627) даже при активном
--     гранте:  u6 = max(u6, now + DashDuration + ServerConfirmTimeout) = 0.2 + 0.18 = 0.38с.
--     Это не выдуманное число, а буквально выражение из дампа, и это ЕДИНСТВЕННЫЙ порог,
--     подтверждённый данными.
--   • ОТКАТ на полный ClientPredict.Evasive.Cooldown (2с) — только при устойчивом отказе,
--     то есть от ДВУХ неподтверждённых доджей подряд. Одиночный промах подтверждения при
--     пинге ~300мс нормален (окно IFRAMES живёт 300мс и наблюдается через RTT), поэтому
--     наказывать за него нельзя — в V147 именно это и остановило додж полностью.
-- Новых тумблеров нет: пороги выведены из CombatConfig, решение — из счётчика dodgeRejects,
-- который и так собирался и самоочищается при первом подтверждении.
local function dodgeReady()
	local c = localChar()
	-- MinSpacing действует ВСЕГДА: это наш анти-спам, а не кулдаун игры. Под грантом он и
	-- нужен больше всего — грант с��имает игровой тормоз, и без спейсинга скрипт долбит дэш
	-- каждые несколько кадров.
	if (os.clock() - State.lastDodge) < Config.DodgeMinSpacing then return false end
	if c then
		if c:GetAttribute("IFRAMECD") == true then return false end
		local remG = c:GetAttribute("EvasiveCooldownRemaining")
		if type(remG) == "number" and remG > 0 then return false end
	end
	local since = os.clock() - State.lastDodge
	if evasiveGranted() then
		-- Полный кулдаун предсказания: живой ClientPredict.Evasive.Cooldown, иначе хардкод.
		local fullCd = GameData.evPredictCooldown or Config.DodgeCooldown
		-- [V156/GRANT-COOLDOWN] Runtime опроверг старый пол 0.38с: запросы через 0.52/0.93с
		-- сервер не подтвердил. CombatConfig.Evasive.Cooldown=1.5 уже загружен в GameData,
		-- поэтому используем серверно обоснованный интервал без новой UI-настройки.
		local grantFloor = GameData.evCooldown or 1.5
		-- ═════════════════════���════════════════════════════════════════��════════════
		-- [V148] УБРАНА ЗАЛИПАЮЩАЯ ЗАЩЁЛКА V147 — ИМЕННО ОНА УБИЛА ДОДЖ
		-- ═══════════════════════════════════════════════════════════════════════════
		-- В V147 здесь стояло `if State.dodgeConfirmedLast == false then <ждать 2с> end`.
		-- Это бинарная защёлка на ОДИН промах подтверждения, и она самоподдерживающаяся:
		-- чтобы её снять, нужен подтверждённый додж, а чтобы додж состоялся — нужно отстоять
		-- полные 2с. Первый же неподтверждённый додж переводил спейсинг с 0.38с на 2с и
		-- держал его там, пока не случится удачное попадание в 300-мс окно IFRAMES. При
		-- пинге ~300мс (в логе rawRTT=292…314мс) промахи подтверждения — норма, а не сбой,
		-- поэтому на практике додж переставал выстреливать вовсе. Это репорт пользователя
		-- «додж в принципе ��е вызывается»; регрессию внёс я в V147.
		--
		-- ЧТО НЕ ТАК БЫЛО МЕТОДОЛОГИЧЕСКИ: эскалация до 2с не выведена из дампа. Дамп даёт
		-- ровно одно число — игра сама, ДАЖЕ под активным грантом, пишет в u6 (:627):
		--     u6 = max(u6, now + DashDuration + ServerConfirmTimeout)
		-- то есть 0.38с. Это и есть единственный защищённый данными пол. Всё сверх него было
		-- моей политикой, а не фактом игры.
		--
		-- НОВОЕ ПРАВИЛО: пол 0.38с действует всегда, а на полный CD откатываемся только при
		-- УСТОЙЧИВОМ отказе — двух и более подряд неподтверждённых доджах. State.dodgeRejects
		-- уже обнуляется при первом же подтверждении (:4676), п��этому счётчик не залипает:
		-- один промах из-за пинга ничего не стоит, а реальный серверный отказ (серия) — виден.
		if (State.dodgeRejects or 0) >= 2 and since < fullCd then
			-- Диаг ровно ОДИН раз на факт блокировки (не каждый кадр): иначе 60 строк/сек.
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
		-- Вето по атрибутам уже отработало выше; здесь остаётся только положительный ответ.
		return true
	end
	return since >= (GameData.evPredictCooldown and (GameData.evPredictCooldown + 0.05)
		or Config.DodgeCooldown)
end

-- force=true (blatant override): пропускаем ТОЛЬКО софт-состояния (Stunned/CantAnything),
-- которые сервер всё равно позволяет обойти дэш-инпутом. Жёсткие состояния и смерть — нет.
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
	-- Dump Evasive.lua also refuses while Blocking/CombatAttacking. performDodge clears
	-- Blocking via Deactivated before FireServer; self-attack remains a hard refusal.
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
	sendDeactivate(true)   -- принудительно: намерение уже снято, guard обязан опуститься
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
	-- [V91] ЖИВОЙ ДОРЕЗОЛ�� M2-ВАРИАНТА. Атрибут M2VariantId сервер выставляет и реплицирует,
	-- поэтому он нередко приходит ПОЗЖЕ, чем анимация (мы детектим свинг раньше). Если на
	-- момент детекта варианта не было, а теперь он известен и отличается — пересчитываем
	-- таймлайн. Без этого Ali M2 Right (0.67) навсегда оставался бы посчитанным как Left (0.53),
	-- т.е. на 140��с раньше при окне перфекта 125м��. Проверка стоит один раз на угрозу.
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
					-- contact0 отсчитывается от detectClock: сдвигаем на ту же дельт���, чтобы
					-- wall-clock ветка ниже осталась согласованной.
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

		-- [V66] изме��яем РЕАЛЬНУЮ скорос��ь прогресса анимации (units анимац��и в
		-- секунду ре��льного времени) через EMA. У честной атаки ≈ track.Speed;
		-- у придержанной падает к ~0. По ней и считаем ��еал��ный контакт.
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

		-- [V96] Live-TP коррекция теперь И для M1 (раньше только M2/SKILL). M1 предсказывался
		-- чистым обратн��м отсчётом contact0-elapsed, без учёта РЕАЛЬНОГО прогресс�� анимации → при
		-- desync/ускорении атаки contactAbs уплыв��л (в логе predErr скакал от -290 до +138ms). Для
		-- M1 окно короткое, поэтому корректируем через ту же live-скорость, но с более высоким полом
		-- (M1 редко «придерживают», агрессивный пол убирает шум коротких тре��ов).
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
				-- реальная скорость прогресса, но не ниже пола (иначе деление на ~0
				-- да��т бесконечность, а враг может резко доиграть). Пол = доля от
				-- н���ми����л��ной скорости трека.
				local nominal = math.max(th.initSpeed or 1, 0.05)
				local floor   = nominal * (Config.LiveSpeedFloor or 0.15)
				local sp      = math.max(th.liveSpeed or nominal, floor)
				local liveRemain = (th.hitTL - tp) / sp
				-- берём макс��мум со стеночасовым: если анимация замедлена, live даёт
				-- больше времени; если ��с��орена — то����е уводит корректно.
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

		-- [V121] FEINT-детект ТОЛЬКО для M1. У M1 хитбокс мгновенный (привязан к ��нимации) → трек,
		-- закончившийся до FeintFrac, = реальная отмена свинга. У M2/SKILL хитбокс ЗАДЕРЖАННЫЙ
		-- (M2HitboxDelay): видимая анимация шт��тно конч��ется за ~30% до нашего hitTL (в логе maxTP=69%),
		-- удар прилетает ПОЗЖЕ конца трека. Прежний код это принимал за финт → th.feinted=true → M2
		-- ВООБЩЕ не парировался (корень жалобы). Для M2/SKILL финт не детектим: полагаемся на
		-- live-timer + wall-clock контакт + геометрию willHitMe. Ложный съед��нный M2-финт = 1 ранний
		-- блок (дёшево), пропуск КАЖДОГО реального M2 = недопустимо.
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

-- ═════════════════ [V91] SERVER-TRUTH RESOLVER (anti "Anti-AutoParry") ═════════════════
-- The problem: an enemy running an Anti-AutoParry script fakes swings — it plays a real
-- attack animation (optionally spoofing the id) and never commits, or cancels it. Animation
-- is the ONLY attack signal an attacker's own client can forge, and it is exactly what our
-- resolver keyed on, so we parried thin air and were open for the real hit.
--
-- What the game itself gives us (verified in the client dump):
--   • The SERVER sets the "M1" / "M2" / "CombatAttacking" attributes on the ATTACKER's
--     character. Client code only ever READS them — an exploiting attacker cannot set them.
--   • The SERVER creates the hitbox part under workspace.Hitboxes with Owner/AttackName
--     children and a VictimSwingId attribute (already used here as "server-overlap").
--   • A swing the server DECLINED (or that was cancelled/feinted) produces an animation but
--     NO attribute and NO hitbox.
-- So: attribute/hitbox present ⇒ the swing is real. Animation alone ⇒ unproven.
--
-- We do NOT hard-require server proof, because the attribute can land slightly after the
-- animation and a real hit would then be missed. Instead we mark the threat's trust level;
-- the press logic uses it to decide whether to commit early or wait for proof.
-- [V97/PERF] persistent helper: the old body wrapped the three reads in an INLINE closure, so
-- every call allocated one — and this runs per unproven threat per frame during every windup.
-- safeGet already exists for exactly this pattern (pcall on a named fn, no allocation).
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

-- Does the server currently have a live hitbox owned by this attacker? This is the
-- strongest possible proof (the damage volume itself exists) but it appears late.
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

-- [V142/ОТКАТ V140+V141] Здесь жили State.attrProofTaken (владелец атрибута) и репутация
-- атакующего. Оба убраны как ошибочные, и оба — по данным дампа игры:
--   1) Владелец-тест исходил из «один серверный атрибут = один удар». Ложь: boxing.M2MultiHitCount = 2,
--      один M2 наносит два удара под одним атрибутом, а угроза живёт ещё ~350мс после контакта.
--      Итог — proof отбирался у второго удара multi-hit и у следующего свинга комбо, скрипт
--      переставал реагировать на ЗАКОННЫЕ атаки (в логе: HOLD unproven → LATE, NOT-BLOCKED).
--   2) Репутация за весь бой ни разу не набрала порог (в шап��е диага «offenders: none»), то есть
--      н�� защищала, но приносила 4 ключа конф��га и тум��лер. Убрано.
-- Что осталось от той работы: TRACE-PROOF в диаге и proof=/HELD-BY-GATE в строках MISS — они
-- ничего не решают, только показывают факты, и именно они позволили найти ошибку выше.

-- [V144/PERF] РЕАКТИВНОЕ ЯДРО (~270 строк): выполняется на каждую сыгранную анимацию каждого
-- игрока — в мультибое это десятки вызовов в секунду, и им��нно от его задержки зависит, успеет
-- ли угроза попасть в планировщик к нужному кадру. Самая крупная функц��я файла без макроса.
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

	-- [V83] АНТИ-DECOY: настоящий игрок физически не может выдать два свинга подряд за
	-- <AntiDecoyGap. Флуд атак-decoy (наши prerun/idlemask и такие же трюки врага) прилетает
	-- пачкой с почти нулевым интервалом → это НЕ отдельные удары. Регистрируем только ПЕРВЫЙ
	-- и глушим быстрые повторы, чтобы ��раг не спамил ложные тайминги в наш парри.
	-- [V90] РЕЗОЛВЕР ПЕРЕПИСАН. Было: при двух анимациях от одного врага внутри AntiDecoyGap
	-- регистрировалась ПЕРВАЯ, вторая отбрасывалась ч��рез `return`. Но Anti-AutoParry работае��
	-- ровно наоборот — шлёт ФЕЙК первым, а РЕАЛЬНЫЙ удар через ~50мс. Скрипт цеплялся за фейк,
	-- реальный свинг вообще не попадал в Threats ⇒ нажатия в его окно не было ⇒ чистый хит.
	-- Именно поэтому «некоторые скрипты всё равно пробивают».
	-- Теперь быстрый повт��р НЕ отбрасывается: он регис���рируется с меткой suspect=true, а решение
	-- «настоящий или фейк» принимает пер-свинговая серверная истина — VictimSwingId на партах
	-- Workspace.Hitboxes (associatedHitbox → th.serverSwingId). Ниже в press-гейте suspect-угроза
	-- обязана иметь claimed-хитбокс и НЕ получает bypass по ProofGraceSec.
	-- Почему нельзя доверять старому proof: serverAttackProof читает GetAttribute("M1"/"M2"/
	-- "CombatAttacking") — это булев флаг на МОДЕЛИ, а не на свинге. Пока враг реально бьёт,
	-- флаг true, поэтому ЛЮБАЯ фейковая анимация проходила proof-гейт.
	local suspectSwing = false
	if Config.AntiDecoy then
		local sig = State.antiDecoySig; if not sig then sig = {}; State.antiDecoySig = sig end
		local cnt = State.antiDecoyCount; if not cnt then cnt = {}; State.antiDecoyCount = cnt end
		local nowc = os.clock()
		local prev = sig[name]
		if prev and (nowc - prev) < (Config.AntiDecoyGap or 0.12) then
			cnt[name] = (cnt[name] or 1) + 1
			-- Жёсткий предохранитель от флуд-с��ама: со 4-го свинга в окне это уже гарантированно
			-- машинный по��ок, дальше плодить угрозы бессмысленно (и дорого по кадру).
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

	-- [V140/BUG] РЕЗОЛВЕР ПРОПУСКАЛ ОДИНОЧНЫЕ ФЕЙКИ. suspect ставится только при БЫСТРОМ
	-- ПОВТОРЕ (два свинга внутри AntiDecoyGap). Одиночная фейковая анимация повтором не была и
	-- получала serverProven ��апрямую от serverAttackProof — а тот читает МОДЕЛЬНЫЕ атрибуты
	-- M1/M2/CombatAttacking, ко��орые описывают «враг сейчас в атаке», а НЕ «вот этот свинг
	-- настоящий». Пока враг честно бьёт реальны�� удар, флаг висит true, и любая подмешанная
	-- в это окно фейковая анимация проезжала proof-гейт бесплатно (это прямо признано в
	-- комментарии V90 выше, но исправлено было только для suspect-ветки).
	-- Делаем proof РЕБРО-ТРИГГЕРНЫМ: если тем же атакующим уже владеет живая уг��оза, которая
	-- ��ЖЕ опирается на этот самый атрибут, т�� для нового свинга атрибут — не доказательство, а
	-- унаследованное состояние. Такой свинг живёт как suspect и обязан подтвердиться
	-- пер-свинговым VictimSwingId живого хитбокса.
	-- [V142/ОТКАТ V140] Здесь стояла проверка «��три��ут уже занят другой живой угрозой → новый
	-- свинг это фейк». Она НЕВЕРНА, и дамп игры это доказывает: boxing.M2MultiHitCount = 2, то
	-- есть ОДИН M2 по замыслу наносит ДВА удара (в логе `MULTI ... contacts=[600,1050]ms`).
	-- Оба контакта — законные части одной атаки под одним атрибутом, но владелец-тест отдавал
	-- proof только первому, а второй глушил как фейк:
	--   TRACE-PROOF ClawPixelatedZero M2 PROVEN by=attr      (s2)
	--   TRACE-PROOF ClawPixelatedZero M2 HOLD unproven       (s1 — тот же свинг!)
	--   MISS! ... in-window но не выбран EDF | proof=NO HELD-BY-GATE
	-- То ��е ломало комбо: угроза живёт ещё 350мс после к��нтакта, поэтому c3 «владел» атрибутом,
	-- когда прилетал законный c4 → `HOLD unproven SUSPECT` → LATE, NOT-BLOCKED. Отсюда и
	-- «скр��пт перестал реагировать на атаки». Посылка «один атрибут = один удар» ложна.
	local attrProof = serverAttackProof(model)

	local combo = (info.t == "M1") and (info.combo or nextCombo(name)) or 1

	-- [V70] PURE-MATH: никаких калибратор��в. Предикт = таймлай�� анимации + живой
	-- TimePosition, и точка. (V68-residual удалён: один придерж��нный M2 отравлял EMA
	-- и задирал hitTL всех последующих M2 с 600→730мс → no-window NO-PRESS. База 600мс
	-- почти идеальна про��ив реальных ~585мс.)
	-- [V71] множитель скорости атаки АТАКУЮЩЕГО (по его росту) — делит задержку удара.
	-- track.Speed для чужих игро��ов ��еплицируется как 1.0, по��тому берём из роста.
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
	-- [V133] info.contacts = static .anim Hit KEYFRAME times (already in animation-time
	-- seconds). The correct anim-time→wall-clock divisor is the animation PLAYBACK SPEED
	-- (track.Speed, ~1.0 for replicated enemies), NOT aMult. aMult is the server's
	-- GetScaledHitboxDelay divisor for the CONFIG M2HitboxDelay only. Dividing a raw
	-- keyframe by aMult made Boxing M2 predict ~45-118ms EARLY (diag 368813: marker 600ms
	-- /1.08 = 555 pred vs 602 measured) → parry fired too soon → LATE/miss. Config path
	-- (hitTimeline) still uses aMult; marker path uses live speed.
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
		-- [V91] combo и variant теперь ЖИВУТ НА УГРОЗЕ. combo нужен г��ометрии: студы лунжа
		-- (M1StepForwardStuds) заданы ПО НОМЕРУ УДАРА комбо — у Ali это {[1]=1.5, [3]=1.5}.
		-- variant нужен, чтобы реч тяжёлой считался п�� её настоящему варианту.
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
		-- [V91] server-truth trust. serverProven flips to true the moment the SERVER confirms
		-- this attacker is really swinging (attribute or live hitbox). Animation alone leaves
		-- it false, which is the signature of a faked / cancelled swing.
		-- [V90] suspect = быстрый повтор от того же врага (типовой профиль Anti-AutoParry:
		-- фейк первым, реальный удар вторым). Такая у��ро��а НЕ доверяется по модельному
		-- атрибуту — ей нужен claimed VictimSwingId живого хитбокса.
		suspect = suspectSwing,
		-- [V90] Модельный атрибут НЕ считается доказательством д��я suspect-свинга: ��ока враг
		-- реально бьёт, M1/M2/CombatAttacking = true, и фейк проезжал гейт «бесплатно».
		-- [V140] attrProof уже пос��итан выше с ребро-триггером (одиночный фейк, подмешанный в
		-- окно реального свинга, больше не наследует модельный атрибут как доказательство).
		serverProven = (not suspectSwing) and attrProof or false,
		-- [V142] ЧЕМ именно подтверждена угроза — только для диага (строки MISS/TRACE-PROOF).
		-- На решения больше не влияет: логика владельца атрибута удалена.
		provenBy = ((not suspectSwing) and attrProof) and "attr" or nil,
		serverProofClock = nil,
	}
	if th.serverProven then th.serverProofClock = nowClock end
	-- ═══ [V143] КОРЕНЬ «не различает атаки при фейках» ═══
	-- Один AnimationTrack имеет ОДНУ TimePosition, поэтому физически не может представлять два
	-- одновременных свинга. Но угрозы складывались в список без всякой проверки, а каждая из них
	-- держит ссылку на ЭТОТ ЖЕ объект трека и каждый кадр пересчитывает контакт от живого tp
	-- (`th.contactAbs = now + remaining`). Как только враг переигрывает т��т же трек, ВСЕ старые
	-- записи, привязанные к нему, пересчитываются от новой TimePosition и съезжаются в одну точку.
	-- Р��вно это в диаге:
	--   TRACE-GEOM ClawPixelatedZero M1 first=+941ms dt=+185ms   ← запись возраст��м 941мс
	--   TRACE-PROOF ClawPixelatedZero M1 HOLD unproven | dt=+185ms  ×4  (один и тот же свинг!)
	--   CLUSTER n=5 spread=0ms contacts=[+185,+185]ms
	--   DODGE multi-cover(n=5) [GRANT] → DODGE-CONFIRM covered=0
	-- То есть один свинг размножался в пять «одновременных» дедлайнов, кластер верил, что летит
	-- залп, и жёг Evasive-грант впустую. Отсюда и «видит фейк, но доджит его»: press-гейт держал
	-- эти записи как unproven, а додж-путь их же считал за пять реальных атак.
	-- Правильная модель: атакующий + трек = ОДИН живой свинг. Трек перезапустился → прежняя
	-- запись описывает уже закончившийся свинг, её тайминги мусор, она снимается.
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

	-- [V113] Трекинг КАДЕНСА свингов по атакующему (для boxing combo-guard). Запоминаем интервал
	-- между двумя п��следними свингами этого врага: короткий интервал = активная комбо-цепочка.
	-- Поля на State (таблица — без новых top-level локалов, лимит 200/функция не тронут).
	do
		local key = model or attackerHRP or name
		if key then
			-- [V120] WEAK KEYS: key = model/HRP (Instance) → без weak-ключа утечка (запись на каждый
			-- респавн, мёртвые модели не собираются GC). __mode="k" авто-чистит по уходу игрока.
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
	-- Boxing M2: CombatConfig.M2MultiHitCount=2, .anim Hit markers=[0.60,1.05].
	-- Второй marker — отдельный EDF deadline той же атаки, а не telemetry follow-up.
	if info.contacts and info.contacts[2] then
		local group = { cancelled = false, held = false }
		th.group, th.strike = group, 1
		local hit2 = info.contacts[2] / math.max(speed, 0.05)   -- [V133] anim-keyframe → /speed, not /aMult
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

	-- [V91/perf] These two lines each build a ~16-field string.format on EVERY detected
	-- attack. With several enemies swinging that is a lot of garbage per second for logs
	-- nobody reads unless debugging, so they are now behind DeepDiag like the MISS! log.
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

	-- [V89] preferBack: для НЕБЛОКИРУЕМЫХ (грэб/слэм) додж строго Н��ЗАД (away от врага) —
	-- уводит и�� радиуса захв��та и разрывает клинч; вбок только как fallback у стены. Обычный
	-- умный додж (perp+away) оставлен для блокируемых угроз, гд�� важнее с����ти с линии.
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

-- [V155/ALI-FORWARD] Обычный bestDodgeDir сознательно выбирает side+away. Для perfect-dodge
-- Ali нужен противоположный приоритет: войти В хитбокс атакующего под iframe, чтобы сервер
-- гарантированно мог выдать StyleEvasiveCounter. Стена перед целью переводит в side, затем away.
function State.bestAliForwardDodgeDir(th)
	local me = localHRP()
	local aHRP = th and th.attackerHRP
	if not me or not aHRP or not aHRP.Parent then return nil, "no-target" end

	-- [V156/ALI-TRAJECTORY] V155 целился в HRP и всегда проходил полные 6 studs. Runtime:
	-- dist=8 дал perfect, dist=4/6 часто дал только IFRAMES без StyleEvasiveCounter. Целимся
	-- в центр уже предсказанного server hitbox на contact и ограничиваем физический travel.
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
	-- [V120] ЕДИНЫЙ мастер-гейт: sendDodge вызывается ТОЛЬКО отсюда, все триггеры идут через
	-- performDodge → выключив AutoDodge, юзер убирает ЛЮБОЙ ОПЦИОНАЛЬНЫЙ додж (одно место истины).
	-- [V128] ИСКЛЮЧЕНИЕ — must-dodge (bypassAutoOff=true): грэбы/анблокаблы НЕЛЬЗЯ блокнуть, их
	-- гасит только додж (i-frames). Это обязат��льная защита, а не удобство, поэтому она обязана
	-- срабатывать даже при выключенном Auto Dodge. Свой тумблер у неё есть (Config.MustDodge,
	-- проверяется в isMustDodge), так что полностью отключить её всё равно можно.
	if Config.AutoDodge == false and not bypassAutoOff then
		if State.lastDodgeRefuse ~= "AutoDodge-off" then
			State.lastDodgeRefuse = "AutoDodge-off"
			diagPush(("DODGE-SKIP t=%.2f  %s  (AutoDodge disabled)"):format(now, reason))
		end
		return false
	end
	local tx0 = State.dodgeTxn
	if tx0 and tx0.pending then return false end
	-- [V146] ФИЗИЧЕСКОЕ ВЕТО. Стоит в мастер-гейте, чтобы его не могла обойти НИ ОДНА ветка —
	-- включая must-dodge с bypassAutoOff и blatant с force. Под живым IFRAMES дэш не добавляет
	-- ничего (мы уже неуязвимы по VictimHitboxServiceClient:139), зато сжигает грант/кулдаун, а
	-- сервер его всё равно отклоняет, пока мы в атаке (Evasive:613 → «IFRAMES not confirmed»).
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
	-- ═══════ [V158/DODGE-CENTER] ЦЕНТР ПО ЖИВОМУ contactAbs, НЕ ПО МОМЕНТУ DETECT ═══════
	-- V157 проверял лишь «контакт когда-нибудь попадёт в широкое iframe-окно» и сразу стрелял.
	-- На Kure это давало fire→contact=321-333ms: 300ms IFRAMES заканчивались ДО фактического
	-- контакта. Обратный случай (90-107ms при uplink≈112ms) физически не мог успеть поднять IFRAMES.
	-- Теперь каждый кадр ждём точку contactAbs-(uplink+D/2), а опоздавшую попытку не изображаем.
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
	-- [V159/DODGE-TIMING-SCOPE] Центрирование и TOO-LATE применимы только к ОПЦИОНАЛЬНОМУ доджу,
	-- у которого есть альтернатива в виде parry. Для must-dodge (грэбы/анблокаблы) и явно
	-- форсированных веток блока не существует вовсе: пропуск = гарантированный хит, поэтому там
	-- поздний додж всё равно лучше отсутствия доджа. V158 гейтил их наравне со всеми — это и был
	-- второй способ вообще не увидеть додж в логе.
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
	-- [V155/ALI-FORWARD] playDodgeMotion менял только анимацию и НЕ MoveDirection. Игра читает
	-- именно Humanoid.MoveDirection; ставим его до remote и переутверждаем до server receipt.
	if dir and isAliAbuse then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then pcall(V93.humMove, hum, dir) end
		State.ap.dodgeSteerDir = dir
		State.ap.dodgeSteerUntil = now + math.max((uplink() * 0.5) + 0.06, 0.12)
	end
	-- [V159/DODGE-REVERT] sendDodge снова безусловно отправляет пакет, поэтому проверка «принял ли
	-- чужой модуль» удалена как мёртвая. Гейты остаются там, где им и место — в canDodgeNow().
	sendDodge(dir, dodgeSpeed)
	if granted then State.grantEscapes = (State.grantEscapes or 0) + 1 end
	if type(reason) == "string" and reason:sub(1, 4) == "dual" then
		State.dualDodgeCount = (State.dualDodgeCount or 0) + 1
	end
	-- [V159/DODGE-REVERT] DODGE-NATIVE-ACCEPT удалён: без нативного вызова «accept» — это просто
	-- факт отправки пакета, а он уже печатается строкой DODGE ниже вместе с окном iframe.
	State.lastDodgeRefuse = nil
	local tx = State.dodgeTxn
	-- [V90] Планируемое окно iframe считаем от РЕАЛЬНОЙ латентности (uplink ≈ RTT), а не от
	-- Config.DodgeConfirm: последний — ServerConfirmTimeout игры, т.е. таймаут ожидания, а не
	-- задержка. С фиксированными 0.18 ��лан расходился с фактом на ±150мс, из-за чего
	-- «planned»-счётчик и multi-cover решения считались по неверному интервалу.
	local ifLat0 = math.max(uplink(), 0.02)
	local ifDur0 = GameData.iframeDur or Config.IFrameDur or 0.30
	local iframeLo = now + ifLat0
	local iframeHi = iframeLo + ifDur0
	tx.pending, tx.confirmed = true, false
	tx.fire, tx.lo, tx.hi = now, iframeLo, iframeHi
	-- ═══════════ [V160] ACK-ОКНО = РОВНО ТО ЖЕ, ЧТО ЖДЁТ САМА ИГРА ═══════════
	-- Дамп Evasive_ModuleScript.lua:741 (task.spawn, слушатель GetAttributeChangedSignal("IFRAMES")):
	--     local v69 = u51 and 1.2 or math.max(ServerConfirmTimeout, 0.6);
	--     local v70 = os.clock() + v69;
	--     while os.clock() < v70 and not u67 do task.wait() end
	-- где u51 — флаг гранта (outnumbered; строки 527-555 и все `if not u51` байпасы).
	-- То есть игра ждёт появления IFRAMES 600мс, а под грантом 1200мс.
	--
	-- Прежняя формула (uplink + lookahead + 0.08) при пинге 112мс давала ~218мс и объявляла
	-- отказ РАНЬШЕ, чем сервер вообще обязан ответить. Диаг показывает цену этого напрямую:
	--     DODGE-REJECT/EARLY-FALLBACK t=4475.28 ack=218ms IFRAMES not confirmed
	--     DODGE-OUT t=4475.33 LATE fired 265ms before [hit INSIDE i-frame window (+139ms)]
	-- то есть додж ФИЗИЧЕСКИ ОТРАБОТАЛ (удар пришёл внутрь окна неуязвимости), но был уже
	-- отменён нашим же таймаутом. Итог сессии: 8 доджей = 8 грантов, все сожжены, и
	-- «2 отказа подряд» откатили гейт на полный CD 2.00с (строка DODGE-GATE в диаге).
	--
	-- Ожидание полного окна безопасно: угрозы помечаются covered ТОЛЬК�� по живому IFRAMES
	-- (см. updateDodgeTxn ниже), поэтому parry/EDF всё это время продолжает работать штатно.
	-- Меняется лишь одно — мы перестаём объявлять отказ там, где отказа не было.
	local ackWindow = granted and 1.2
		or math.max(GameData.confirmTimeout or Config.DodgeConfirm or 0.18, 0.6)
	tx.ackDeadline = now + ackWindow
	tx.untilAt, tx.reason = iframeHi + 0.08, reason
	-- [V155/ALI] Источник perfect-dodge закреплён за этой транзакцией: последующая M2 не должна
	-- переехать на случайную ближайшую угрозу, пока исходный серверный swing ещё жив.
	tx.abuseThreat = isAliAbuse and dodgeTarget or nil
	tx.dodgeDirMode = dirMode
	-- [V154/ALI] IFRAMES подтверждает только принятый dodge. Право на бесплатную M2 выдаёт
	-- отдельный серверный StyleEvasiveCounter, поэтому каждый новый dodge сбрасывает обе стадии.
	tx.perfectConfirmed, tx.perfectAt = false, nil
	if (counterStyle() or "") == "ali" and Config.SkillAddon and Config.AliEvasiveCounter then
		diagPush(("ALI-DODGE-ARM t=%.2f reason=%s await=StyleEvasiveCounter proc=one-perfect-dodge specialCd=6s range=22 ignoreNormalM2Cd=true deadline=%.0fms")
			:format(now, tostring(reason), (tx.untilAt-now)*1000))
	end
	-- [V91] ОБЯЗАТЕЛЬНЫЙ СБРОС: State.dodgeTxn — ОДНА переиспользуемая таблица на всю сессию.
	-- Без сброс�� Ali EvasiveCounter выстрелил бы РОВНО ОДИН раз за сессию (флаг остался бы true
	-- на все последующие доджи).
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

-- Authoritative coverage is only granted after the game's replicated IFRAMES flag.
-- Before confirmation, a dodge request remains a request: no threat is removed from EDF.
local function updateDodgeTxn(now)
	local tx = State.dodgeTxn
	if not tx or not tx.pending then return end
	local c = localChar()
	if not tx.confirmed and c and c:GetAttribute("IFRAMES") == true then
		tx.confirmed = true
		-- Planning uses expected network confirmation; authoritative coverage starts when
		-- the replicated IFRAMES flag is actually observed.
		-- [V90] Математика этой ветки ВЕРНА и остаётся как есть: contactAbs живёт в
		-- предсказанн��х КЛИЕНТСКИХ часах (сервер+oneWay), а IFRAMES мы наблюдаем через RTT
		-- после отправки — оба сдвига сокращаются, поэтому окно ровно [now, now+D].
		-- Меняем только источник D: живой Evasive.IFrameDuration вместо UI-слайдера, иначе
		-- восстановленный из прошлой сессии слайдер молча ломает покрытие.
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
	-- [V156/DODGE-ACK] Не держим scheduler выключенным до tx.untilAt, если сервер уже не
	-- подтвердил запрос в физическое ack-окно. Угрозы не были помечены covered до IFRAMES,
	-- поэтому простое закрытие pending немедленно возвращает их обычному EDF/parry.
	if not tx.confirmed and now >= (tx.ackDeadline or tx.untilAt) then
		State.dodgeRejects = (State.dodgeRejects or 0) + 1
		diagPush(("DODGE-REJECT/EARLY-FALLBACK t=%.2f %s ack=%.0fms IFRAMES not confirmed; EDF/parry restored (подряд=%d)")
			:format(now, tostring(tx.reason or "?"), (now-(tx.fire or now))*1000, State.dodgeRejects))
		tx.pending, tx.confirmed, tx.reason = false, false, nil
		tx.abuseThreat, tx.perfectConfirmed, tx.perfectAt = nil, false, nil
		State.ap.dodgeSteerDir, State.ap.dodgeSteerUntil = nil, 0
		return
	end
	-- ═══════════ [V160] untilAt НЕ ДОЛЖЕН ЗАКРЫВАТЬ НЕПОДТВЕРЖДЁННУЮ ТРАНЗАКЦИЮ РАНЬШЕ ack ═══════════
	-- Без этого расширение ack-окна выше было бы полностью бесполезным. Арифметика на реальных
	-- числах (IFrameDuration=0.3 — CombatConfig:99; пинг из диага 112мс):
	--     untilAt = ifLat0 + ifDur + 0.08 = 0.112 + 0.30 + 0.08 = 492мс
	--     ackDeadline (новое)                                    = 600мс
	-- 492 < 600, поэтому ЭТА ветка сработала бы первой и закрыла бы транзакцию как DODGE-REJECT
	-- ещё до срока, который ждёт сама игра, — ровно та же потеря доджа и того же perfect-гранта,
	-- что мы починили выше, просто через другую строку.
	-- Для ПОДТВЕРЖДЁННОЙ транзакции семантика untilAt (конец окна iframe) остаётся неизменной:
	-- продлевать её нельзя, иначе угрозы помечались бы covered после реального конца окна.
	-- Покрытие угроз считается ОДИН раз в блоке DODGE-CONFIRM выше и строго по окну [tx.lo, tx.hi],
	-- поэтому продление времени жизни транзакции НЕ продлевает пометку covered — проверено.
	local hardClose = tx.untilAt
	local budget = tx.ackDeadline or 0
	-- (а) сервер ещё не ответил — ждём столько же, сколько ждёт игра;
	-- (б) Ali-abuse ждёт StyleEvasiveCounter: proc — следствие этого доджа, и его окно приёма
	--     тоже равно бюджету рукопожатия, а не iframeHi+0.08 (несвязанная величина).
	local awaitingProc = (tx.reason == "ali-dodge-abuse") and not tx.perfectConfirmed
	if (not tx.confirmed or awaitingProc) and budget > hardClose then hardClose = budget end
	-- [V161] Проц ПОЛУЧЕН, но ещё не отстрелян: транзакция обязана дожить до конца окна отправки,
	-- иначе tryAliEvasiveCounter потеряет носитель права (tx.pending) ровно в тот момент, когда
	-- AutoPlay наконец уступил и CombatAttacking погас. Ровно эта гонка и давала в диаге
	-- ALI-PERFECT-CONFIRM без единого ALI-EVCOUNTER-SEND.
	if tx.perfectConfirmed and not tx.evCounterFired and Config.AliEvasiveCounter then
		local ttl = math.min(6 * (Config.AliProcTTLFrac or 0.25), Config.AliProcTTLMax or 1.5)
		local procEnd = (tx.perfectAt or 0) + ttl
		if procEnd > hardClose then hardClose = procEnd end
	end
	if now >= hardClose then
		-- [V155/PERFECT] Подтверждённый Evasive без StyleEvasiveCounter — это НЕ perfect-dodge.
		-- M2 в таком случае не отправлялась; отдельный лог доказывает именно отсутствие server hit.
		if tx.reason == "ali-dodge-abuse" and tx.confirmed and not tx.perfectConfirmed then
			diagPush(("ALI-PERFECT-MISS/EXPIRE t=%.2f target=%s gate=no-StyleEvasiveCounter iframe=[%.0f,%.0f]ms")
				:format(now, tostring(tx.abuseThreat and tx.abuseThreat.name or "?"),
					((tx.lo or tx.fire)-tx.fire)*1000, ((tx.hi or tx.fire)-tx.fire)*1000))
		end
		-- [V148] Итог закрытой транзакции нужен гейту под грантом ровно в одном виде — счётчик
		-- ПОДРЯД идущих отказов. Отдельное поле dodgeConfirmedLast убрано вместе с защёлкой
		-- V147: оно писалось, но после правки гейта не читалось ни одной строкой.
		if not tx.confirmed then
			State.dodgeRejects = (State.dodgeRejects or 0) + 1
			-- Текст честный: один отказ ничего не меняет (пол остаётся 0.38с), откат на полный
			-- CD включается только с ВТОРОГО подряд. При пинге ~300мс единичный промах окна
			-- IFRAMES — ожидаемое явление, а не признак серверного отказа.
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

-- ════════════════ [V92] TARGET BRIDGE (for the Visuals TargetHUD) ════════════════
-- The visuals module is a separate file and never reads AutoParry's internals, so we publish the
-- current target through getgenv() — the same channel the AP_* debug commands already use. The
-- HUD over there just reads this table; if AutoParry isn't running the field is simply nil and
-- the HUD stays hidden. Written only when it CHANGES so we don't touch getgenv every frame.
local _pubTargetModel, _pubThreat = nil, nil

-- Called by the threat scheduler: remembers combat detail (kind/contact) for whoever it is
-- currently servicing, so the HUD can show "M2 in 340ms" when that data exists.
local function publishTarget(th)
	_pubThreat = th
end

-- Called from the visuals step with the model the ring/hitbox is actually drawn on. THIS is the
-- authoritative target for the Visuals TargetHUD — it matches what the player sees on screen even
-- when nobody is mid-swing (the scheduler alone would leave the HUD empty in that case).
-- [V144/PERF] Зовётся из vizUpdate на каждую перерисовку ESP и трогает State/HUD-поля.
local publishVizTarget = LPH_NO_VIRTUALIZE(function(model, hrp)
	if type(getgenv) ~= "function" then return end
	if not model then
		if _pubTargetModel ~= nil then _pubTargetModel = nil; getgenv().AP_TARGET = nil end
		return
	end
	local th = _pubThreat
	if th and th.attackerModel ~= model then th = nil end   -- threat detail belongs to someone else
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
	-- same target: refresh the live fields in place (no table churn)
	local t = getgenv().AP_TARGET
	if not t then _pubTargetModel = nil; return end
	t.hrp = hrp
	t.style = th and th.style or t.style
	t.kind = th and th.kind or nil
	t.contactIn = th and math.max((th.contactAbs or 0) - os.clock(), 0) or nil
	t.threatens = th and th.threatens == true or false
	t.t = os.clock()
end)

-- Per-Heartbeat threat scheduler — kept native under Luraph (direct macro call on literal).
local schedulerStep = LPH_NO_VIRTUALIZE(function(now)
	updateDodgeTxn(now)
	State.updateAliM2Cooldown(now)
	-- [V152] Обновляем Counter до idle fast-path: FAIL/FALLBACK обязан сработать даже если
	-- Threats уже опустел/сменился между отправкой M2 и приходом серверного подтверждения.
	State.updateCounterTxn(now)
	-- [V156/EVCOUNTER-ORDER] Perfect-dodge может уже пометить исходную угрозу covered и удалить
	-- её до следующего Heartbeat. Поэтому sender обязан стоять выше TRUE IDLE FAST PATH, а не
	-- только выше pending-return: иначе #Threats==0 снова делает ALI-EVCOUNTER недостижимым.
	if State.interruptFiredFrame ~= FrameId and tryAliEvasiveCounter(now) then return end
	-- [V91/perf] TRUE IDLE FAST PATH. With no threats, no guard up and AutoPlay off there
	-- is nothing for this step to do, yet it still paid GetServerTimeNow() (a cross-VM
	-- property fetch) + uplink() ping math on EVERY Heartbeat. We must NOT skip the tail
	-- when we are blocking (guard release lives there) or when AutoPlay wants to finish a
	-- stunned enemy, so the bail-out is gated on all three.
	if #Threats == 0 and not State.blocking and not Config.AutoPlay then
		State.interruptCandidate = nil
		State.interruptThreatCount = 0
		State.multiThreat = false
		State.multiThreatN = 0
		State.vizTarget = nil
		-- [V140/BUG] ЗАМО��ОЗКА ВИЗУАЛОВ. Этот idle-выход стоит ВЫШЕ строки `V93.nearPress =
		-- math.huge`, поэтому nearPress сохранял значение последнего кадра боя. Сценарий:
		-- враг замахнулся → nearPress стал маленьким (например 0.03) → угроза разрешилась и
		-- Threats опустел → мы выходим ЗДЕСЬ и больше никогда не доходим до сброса. Значение
		-- 0.03 залипает, а vizUpdate по нему решает «press-дедлайн рядом, кадр отдаём защите»
		-- и выходит НАВСЕГДА, не вызывая LinePool:finish() — последний нарисованный кадр так и
		-- висит на экране. Ровно то, что описано как «визуалы иногда замораживаются, вроде
		-- из-за атаки врага». Сбрасываем метрику и здесь.
		V93.nearPress = math.huge
		V93.nearPressStamp = os.clock()
		publishTarget(nil)   -- [V92] let the Visuals TargetHUD know combat ended
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local up        = uplink()
	-- [V90] АВТОРИТЕТНЫЕ КОНСТАНТЫ I-FRAME.
	-- ifDur берём из ЖИВОГО CombatConfig.Evasive.IFrameDuration (GameData.iframeDur), а не из
	-- Config.IFrameDur: последний висит на UI-слайдере "i-Frame Window", и авто-восстановление
	-- конфига из прошлой сессии затирало ��ы им физическую константу игры → тихая регрессия
	-- тайминга, которую невозможно отладить. Слайдер остаётся, но только как ручной override.
	-- ifLat — РЕАЛЬНАЯ задержка до подъёма серверных IFRAMES. Раньше по всему блоку стояла
	-- Config.DodgeConfirm (0.18) — это ServerConfirmTimeout игры, ТАЙМАУТ, а не латентность:
	-- на низком пинге окно пок��ытия завышалось на 150мс, на высоком — занижалось.
	local ifDur     = GameData.iframeDur or Config.IFrameDur or 0.30
	-- Пол 0.02с: ��а ��чень низком пинге up���0.01 и «coverLo = ifLat - 0.03» уходил в минус, т.е.
	-- уже прилетевший удар ��читался покрываемым. Дэш не защищает назад во вр��мени.
	local ifLat     = math.max(up, 0.02)
	local wantBlock = nil
	local faceTgt   = nil
	local imminent  = V93.imminentBuf   -- [V123] персистентный буфер (без аллокации таблицы/кадр)
	table.clear(imminent)
	State.interruptCandidate = nil
	State.interruptThreatCount = 0
	-- [V139/PERF] table.clear вместо `for k in pairs(...) do t[k]=nil end`. Ключ�� здесь —
	-- Instance атакующих; поимённое зануление это полный обход хеш-части КАЖДЫЙ Heartbeat плюс
	-- удержание сильных ссылок на модели между кадрами. table.clear делает то же од��им вызовом.
	table.clear(V93.interruptSeen)
	-- [V139] Обнуляем метрику близости press-дедлайна; заполнится ниже в цикле по угрозам.
	-- [V140] Метка свежести. nearPress ПРОИЗВОДИТСЯ здесь (Heartbeat), а ПОТРЕБЛЯЕТСЯ в
	-- vizUpdate (RenderStepped) — это разные циклы, и потребитель не имеет права д��верять
	-- значению без проверки возраста. Любой будущий ранний выход из schedulerStep (смерть,
	-- respawn, отключение фичи, ошибка выше по стеку) снова оставил бы залипшее значение и
	-- снова заморозил ESP. Со штам��ом visUpdate просто игнорирует несвежую метрику.
	V93.nearPress = math.huge
	V93.nearPressStamp = os.clock()

		for i = #Threats, 1, -1 do
			local th = Threats[i]
			local trackGone = th.track and th.track.Parent == nil
			refreshContact(th)
			-- [V74] Use actual server hitbox to correct timing for delayed hitboxes (Boxing M2, etc.)
			syncContactWithHitbox(th, now)
			local dt = th.contactAbs - now
			-- [V90 FIX] Угрозы БЕЗ трека (хитбокс-детект / сетевые свинги) не могут истечь по
			-- dt: refreshContact клампит contactAbs в now+max(remaining,0), поэтому dt застревает
			-- на 0 и НИКОГДА ��е ухо��ит ниже -0.35, а trackGone для них тоже false. Без трека ��гроза
			-- ��тановилас�� бессмертной → wantBlock де��жался вечно → guard не отпускался (баг «блок
			-- не снимается»). Даём таким угрозам жёсткий wall-clock TTL: живут contact0 + грейс.
			local noTrackExpired = (not th.track)
				and (now - th.detectClock) > ((th.contact0 or 0) + 0.35)

			-- [V143] staleTrack снимается МОЛЧА, как resolved: свинг, который эта запись описывала,
			-- закончился (её трек уже переигран под новый удар). Считать её промахом нельзя —
			-- это накручивало бы фиктивные MISS и портило статистику точности.
			-- ═══════ [V150] КОРЕНЬ «удар уже сбит, а скрипт всё равно доджит» ═══════
			-- У записи угрозы не было НИ ОДНОГО поля про то, что атакующему сорвали замах:
			-- есть resolved/staleTrack/feinted/dodged/coveredByDodge — и все они про НАС.
			-- Состояние атакующего не спрашивалось нигде, поэтому сбитый удар оставался живой
			-- угрозой до истечения по таймингу (dt < -0.35), а додж успевал сжечься впустую.
			--
			-- Факт из дам��а, а не предположение — Block_ModuleScript.ApplyLocalParriedStun
			-- (:161-210), которую вызывают M1.lua:674 и M2.lua:1708 при парри:
			--     Character:SetAttribute("Parried", true)
			--     Character:SetAttribute("Stunned", true)
			--     MovementServiceUtils.SetSpeed(humanoid, p23)   -- ParryStunSpeed
			-- Это АТРИБУТЫ на персонаже атакующего, то есть реплицируемые и читаемые нами — тот
			-- же приём, что уже применён для IFRAMES в counterPreemptsDodge (V146).
			-- Держатся: M1 → RecoveryLockout(0.4)*heightMult + 0.1 ≈ 0.5с; M2 → ParryStun.M2 = 1с.
			-- Пока они висят, свинг физически завершиться н�� может → угроза мертва.
			-- Снимаем её МОЛЧА (как resolved): это не промах, удар отработан парированием, и
			-- записывать его в MISS означало бы врать в статистику точности.
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
							.. "свинг завершиться не может (додж не нужен)"):format(now, th.name, th.kind))
					end
					State.threatNeutralized = (State.threatNeutralized or 0) + 1
					table.remove(Threats, i)
				-- [V152] Эта конкретная угроза ждёт серверный исход уже отправленной M2. Не добавляем
				-- её одновременно в EDF/imminent: иначе тот же кадр планирует block/dodge поверх counter.
				-- updateCounterTxn снимет метку на FAIL и ветка ниже автоматически станет fallback.
				elseif th.counterPendingId and State.counterTxn
					and th.counterPendingId == State.counterTxn.seq
					and (State.counterTxn.pending or State.counterTxn.confirmed) then
					-- transaction owns this threat only
				elseif th.resolved or th.staleTrack or (th.group and th.group.cancelled) then
				table.remove(Threats, i)
			elseif th.feinted then
				if not th.feintLogged then
					th.feintLogged = true
					diagPush(("FEINT  t=%.2f  %s  %s  reached=%.0f%% of hitTL → ignored")
						:format(now, th.name, th.kind, (th.maxTP or 0) / math.max(th.hitTL, 0.001) * 100))
				end
				table.remove(Threats, i)
			-- [V121] КОРЕНЬ «скрипт ВООБЩЕ не парирует M2»: у M2 анимационный трек уничтожается
			-- (Parent=nil) ~0.5с в замах, а реальный удар (delayed hitbox, M2HitboxDelay) прилетает
			-- на 0.78-0.84с. Прежнее `trackGone and elapsed>0.5` уби��ало угрозу РОВНО на 0.5с — за
			-- 30-110мс ДО того как откроется press-окно (pressAt) → M2 никогда не нажимался (в логе
			-- ���бе M2 удалены то��но через 0.5с, dt ещё +250..+300мс). Track-gone угрозы и так тикают
			-- по wall-clock (remaining=contact0-elapsed) → catch-all `dt<-0.35` гарантирует удаление.
			-- Поэтому 0.5с-TTL применяем ТОЛЬКО когда контакт уже практически наступил (dt<lead) —
			-- отменённый/финтовый свинг с прошедшим контактом чистится, а delayed-M2 доживает до press.
			elseif dt < -0.35 or noTrackExpired
				or (trackGone and (now - th.detectClock) > 0.5 and dt < Config.PerfectLead) then
			-- [V66] POST-MORTEM: угроз�� уходит. Если на неё ни разу не нажали и не
			-- задоджили — это независимый пропуск. Логируем ТОЧН��Ю прич��ну, чтобы
			-- закрыть "скрипт проёбывает атаку" по фактам, а н�� догадкам.
			-- [V69] при ненаправленном блоке угроза, ���оше��шая в окно, покрыта поднятым
			-- guard'ом (один блок = защита от всех). ���то НЕ промах — раньше логировалось
			-- лож��ым "пере��ит EDF". Считаем отдельно, чтобы не путать с реа���ьными потерями.
			local coveredByGuard = th.coveredByHeldGuard == true
				or (Config.OmniBlock and State.blocking and th.enteredWindow
					and th.contactAbs <= (State.holdUntil or 0) + 0.05)
				if th.coveredByDodge or th.coveredByCounter then
					-- Explicitly serviced by dodge/counter; not a miss and not guard coverage.
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
					reason = "in-window но не выбран EDF (перебит другой целью в т��т же кадр)"
				elseif th.contactPassedFast then
					reason = ("окно не открылось: контакт приле���ел быстре�� pressAt (minDtToPress=%.0fms)"):format((th.minDtToPress or 0)*1000)
				else
					reason = ("no-window (maxTP=%.0f%% hitTL, feint-grace?)"):format((th.maxTP or 0)/math.max(th.hitTL,0.001)*100)
				end
				-- [V141, ОСТАВЛЕНО] Proof-состояние в каждой MISS-строке. Без него по логу нельзя
				-- отличить «промах по таймингу» от «гейт сознательно держал нажатие» — именн�� эти
				-- две пометки и пока��али, чт�� владелец-тест V140 глушил законные удары.
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
			th.threatens = threatens
			if threatens and not th.firstThreatClock then
				th.firstThreatClock = now
				local ga, gm, gl = th.geomOrigin, th.geomVictim, th.geomLook
				if Config.DeepDiag then   -- [V91/perf] 15-field string.format per threat: debug-only
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
				-- После normal block первого Boxing strike свежий perfect на втором физически
				-- невозможен из-за BlockCooldown=0.5с > marker gap≈0.45с. Не роняем guard.
				if th.group and th.group.held and State.blocking then
					th.pressed, th.coveredByHeldGuard = true, true
					State.holdUntil = math.max(State.holdUntil or 0,
						(th.group.lastContact or th.contactAbs) + Config.HoldAfter + (Config.HoldLateGrace or 0))
				end
				-- AutoPlay interrupt использует уже готовую геометрию/таймлайн этого же scheduler.
				-- Safety-count = разные атакующие, а не animation tracks одного комбо-врага.
				local ik = th.attackerModel or th.attackerHRP or th.name
				if ik and not V93.interruptSeen[ik] then
					V93.interruptSeen[ik] = true
					State.interruptThreatCount = State.interruptThreatCount + 1
				end
				-- Кандидат = earliest точно рассчитанная M1/M2, которую наш M1 потенциально успеет сбить.
				-- Enemy contact уже включает его style/combo/рост/live TimePosition.
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
		-- Hakari addon: the momentum (double) M2 uses a slower hitbox delay (0.62 vs 0.59),
		-- so its contact lands slightly later than a normal M2 — widen both edges a touch.
		if Config.SkillAddon and Config.SA_HakariRead and th.kind == "M2"
			and (th.style or ""):lower() == "hakari" then
			local w = Config.SA_HakariWiden or 0.05
			lead = lead + w
			hold = hold + w
		end
					-- [V116] ЧИСТО МАТЕМАТИЧЕСКИЙ предикт: press строго от сырого contactAbs (таймлайн
					-- анимации + живой TimePosition). Никакой выученной коррекции — она отравляла между
					-- врагами. Компенсация задержки — только физическая (lead + uplink + velLead).
					local pressAt = th.contactAbs - lead - up - th.velLead
					local holdEnd = th.contactAbs + hold
					-- [V90] FRAME LOOKAHEAD. Дальше сравнение идёт как `now >= pressAt`, т.е. нажатие
					-- падало на ПЕРВЫЙ Heartbeat ПОСЛЕ дедлайна ⇒ систематическое опоздание [0, dt].
					-- При 144 FPS это ~3мс, при 20 FPS — до 50мс, а перфект-окно всего 125мс
					-- (Block.PerfectBlockWindow). Сдвигаем дедлайн на полкадра вперёд ⇒ средняя
					-- ошибка квантования 0 вместо +dt/2, и низкий FPS больше не съедает окно.
					local pressAtQ = pressAt - (V93.lookahead or 0)
				-- [V66] ди��г-трекинг: минимальный зазор до момента нажатия и факт
				-- входа в окн�� — для точного post-mortem причины пропуска.
				local dtToPress = pressAt - now
				if th.minDtToPress == nil or dtToPress < th.minDtToPress then
					th.minDtToPress = dtToPress
				end
				-- [V139] Ближайший АКТУАЛЬНЫЙ press-дедлайн кадра (в будущ��м или только что прошедший).
				-- Читает vizGate: пока защита в работе, ESP не претендует н�� бюджет кадра.
				if dtToPress > -(Config.HoldAfter or 0.12) and dtToPress < V93.nearPress then
					V93.nearPress = dtToPress
				end
				if now < pressAt and (th.contactAbs - now) < lead then
					th.contactPassedFast = true
				end
				-- [V91] SERVER-TRUTH refresh. Keep polling cheap authoritative proof while the
				-- swing is in flight: once the server confirms it, the threat is trusted for
				-- good. (Attribute read is a single cheap call; the hitbox sweep only runs
				-- while still unproven and close to contact, so it costs nothing normally.)
				if not th.serverProven then
					-- [V90] Для suspect-свинга модельный атрибут — НЕ доказательство (он true
					-- на всю длительность реальной атаки, поэтому «освящал» и фейки). Единственная
					-- пер-свинговая истина — claimed VictimSwingId живого хитбокса: игровой
					-- VictimHitboxServiceClient шлёт VictimHitConfirm именно по нему, а фейковая
					-- анимация парта в Workspace.Hitboxes НЕ создаёт.
						if th.suspect then
							if th.serverSwingId or (th.group and th.group.serverSwingId) then
								th.serverProven, th.serverProofClock = true, now
								th.suspect = false
								-- [V140] VictimSwingId уник��лен для свинга → атрибут не занимает.
								th.provenBy = "swingid"
							end
						-- [V142/ОТКАТ] Владелец-тест убран и здесь: он отбирал доказательство у второго
						-- удара multi-hit M2 и у следующего зако��ного свинга комбо.
						elseif serverAttackProof(th.attackerModel) then
							th.serverProven, th.serverProofClock = true, now
							th.provenBy = "attr"
							-- [V141] ЗАМЕР, которого не было: когда именно приходит серверный
							-- атрибут относительно д��текта и контакта. ��то единственный способ
							-- подобрать ProofGraceSec по факту, а не на глаз.
							if Config.DeepDiag and not th.proofLogged then
								th.proofLogged = true
								diagPush(("TRACE-PROOF t=%.3f %s %s PROVEN by=attr +%.0fms after detect, %+.0fms to contact")
									:format(now, tostring(th.name), tostring(th.kind),
										(now - th.detectClock) * 1000,
										(th.contactAbs - now) * 1000))
							end
						elseif (th.contactAbs - now) < 0.18 and serverHitboxProof(th.name) then
							-- Хитбо��с — сильное пер-свинговое доказательство, атрибут не занимает.
							th.serverProven, th.serverProofClock = true, now
							th.provenBy = "hitbox"
						end
				end

				if now >= pressAtQ and now <= holdEnd then
					th.enteredWindow = true
					-- [V91] ANTI-BAIT GATE. An enemy Anti-AutoParry script fakes the swing
					-- animation to pull our parry early, then hits us for real while we are in
					-- block cooldown (0.5s per CombatConfig). If the server has NOT confirmed
					-- this swing yet and we still have time before contact, hold the press and
					-- re-check next frame. We never skip a press outright: once we are inside
					-- the final ProofGrace window (or proof arrives) the press goes through, so
					-- a genuine attack whose attribute lands late is still parried.
					-- [V90] suspect-свинг НЕ получает ProofGrace-байпас: если пер-свинговая
					-- истина (VictimSwingId) так и не появилась — это фейк, и жечь на него блок
					-- нельзя, иначе уходим в BlockCooldown=0.5с ровно к приходу настоящего удара.
					-- Реальный свинг всегда создаёт парт в Workspace.Hitboxes, поэтому че��тную
					-- атаку этот гейт не режет.
					-- [V142] Гейт вернулся к исходному условию: держим нажатие, пока доказательства нет
					-- и до контакта ещё больше ProofGraceSec, либо свинг помечен suspect. Попытка
					-- V141 сделать байпас «заработанным» опиралась на репутацию — она убрана.
					if Config.ServerProofGate and not th.serverProven
					   and (th.suspect or (th.contactAbs - now) > (Config.ProofGraceSec or 0.06)) then
						if not th.baitHeldLogged then
							th.baitHeldLogged = true
							th.proofHoldClock = now
							-- [V141, ОСТАВЛЕНО] В diagPush, а не только в aclog: aclog уходит в
							-- status-фид, которого нет в дампе, поэтому решения гейта были невидимы.
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
					-- [V65] EDF (Earliest Deadline First) с приоритетом НЕОБСЛУЖЕННЫМ.
					-- Баг до V65: выбирался просто минимальный contactAbs. У Boxing-комбо
					-- быстрый M1 (contact=352ms) всегда имел contactAbs меньше медленной
					-- M2 (contact=832ms), поэтому п��сле перфекта M1 медленная M2 НИКОГДА
					-- не становилась целью → NO-PRESS → полный хит (твой клип). Теперь
					-- снача��а берём угрозы без н��жати�� (unpressed), сред��� ��их — с самым
					-- ранним дедлайном. Так после блока быстрого heavy получает своё
					-- собственное нажатие (guard держится → бло�� тяжёлой).
					local take = false
					if not wantBlock then
						take = true
					else
						local wbU, thU = not wantBlock.pressed, not th.pressed
						if thU ~= wbU then take = thU
						else take = th.contactAbs < wantBlock.contactAbs end
					end
					if take then wantBlock = th end
					end   -- [V91] close the anti-bait proof gate
				end
				-- [V95] окно кандидата на поворот РАСШИРЕНО на RTT (up): хард-снап нужен за
				-- (BlockFaceHardDt + up) до контакта, иначе на высоком пинге кандидат появлялся
				-- бы слишком поздно и мы прессили бы блок ещё ��е довернувшись → сервер от��лонял.
				if dt <= (Config.FaceLeadWindow + up) and dt >= -Config.HoldAfter then
					-- [V65] лицом к т��му, кто бьёт СЛЕДУ��ЩИМ среди ещё не прилетевших
					-- ударов (contactAbs >= now). После блока быстро���� разворачиваемся
					-- к ме��ленной тяжёлой к её контакту ("rotate to active target").
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
				-- [V143] Устаревшая запись (её трек уже переигран) не должна попадать в imminent:
				-- imminent питает cluster, а именно там дубликаты одного свинга превращали��ь в
				-- «залп из пяти» и вызывали лишний додж. Снятие произойдёт кадром позже, поэтому
				-- фильтруем здесь, а не полагаемся на порядок циклов.
				if dt <= Config.DodgeHorizon and dt >= -Config.HoldAfter and not th.staleTrack then
					imminent[#imminent+1] = th
				end
			end
		end
	end

	-- Counter-M1 не владеет защитой: ниже всегда продолжается штатный dodge/parry fallback.
	State.ap.tryInterrupt(now, State.interruptCandidate, State.interruptThreatCount)

	table.sort(imminent, V93.sortByContact)

	-- [V157/HEAVY-ATOMIC] Единственная обычная попытка Heavy выполняется сразу после построения
	-- EDF-списка, ДО любых optional dodge-веток. Только успешный COUNTER-SEND делает return;
	-- любой live-gate пишет FALLBACK и в том же кадре продолжает к dodge/parry.
	if State.interruptFiredFrame ~= FrameId and tryBoxingCounter(now) then return end

	-- Multi-attacker clustering is based on distinct attackers and absolute contacts.
	-- A cluster is handled as one defensive transaction, never as competing EDF presses.
	local cluster = V93.clusterBuf   -- [V123] персистентный буфер (без аллокации таблицы/кадр)
	table.clear(cluster)
	-- A cluster is a set of CONTACT DEADLINES, not attackers. Two Boxing M2 strikes are
	-- two deadlines (s1/s2); collapsing by attacker loses the second deadline and makes a
	-- one-dodge feasibility test lie. Each threat record is already one animation strike.
	-- [V139/BUG] `clusterHeavy` был СЛУЧАЙНЫМ ГЛОБАЛОМ (забыт `local`) и потому НИКОГДА не
	-- сбрасывался в false. Первая же M2 за сессию залипала в _ENV как true — и с этого момента
	-- два решения принимались по м��сору из прошлого боя:
	--   • строка ~4541: `clusterN == 2 and ... and not clusterHeavy` — стратегия SEQUENTIAL
	--     отключалась НАВСЕГДА, кластеры из двух разнесённых M1 уходили в один общий блок
	--     вместо двух отдельных парри (второй удар проходил);
	--   • строка ~4789: `clusterN >= 2 and clusterHeavy and Config.DodgeHeavy` — форс-додж
	--     срабатывал на ЧИСТО M1-кластерах, сжигая Evasive (кулдаун 1.5с) без причины.
	-- Оба сим��тома выглядели как «скрипт со временем начинает париро��ать хуже» — на деле э��о
	-- залипший флаг. Теперь это локальная переменная кадра.
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
	-- A confirmed/pending dodge owns this burst until its server iframe transaction closes.
	-- Do not recompute it into HELD_GUARD halfway through as deadlines drain from imminent.
	local activeTxn = State.dodgeTxn
	if activeTxn and activeTxn.pending then
		clusterStrategy = "DODGE_TXN"
	end
	if not clusterStrategy and Config.MultiThreatGuard and clusterN >= (Config.MultiThreatMinN or 2) then
		local iframeSpan = math.max(0, ifDur - 0.07)
		local blockCd = Config.BlockCooldown or 0.5
		local seqSpread = Config.SequentialSpread or 0.78
		-- [V73] SEQUENTIAL: separate presses if spread is enough and second press clears cooldown
		-- Transaction strategies are evaluated on CONTACT deadlines. Sequential only applies
	-- to two distinct attacks; two strikes from one Boxing M2 are not sequential because
	-- their guard lifecycle is governed by the group-held path.
	if clusterN == 2 and clusterSpread >= seqSpread and not clusterHeavy
		and cluster[1].attackerModel ~= cluster[2].attackerModel then
			local a, b = cluster[1], cluster[2]
			local spreadOk = (b.contactAbs - a.contactAbs) >= blockCd + Config.PerfectLead + Config.MinActGap + 0.05
			if not isMustDodge(a) and not isMustDodge(b) and spreadOk then
				clusterStrategy = "SEQUENTIAL"
			end
		end
		-- [V138] DODGE_M1_PARRY_M2: two DIFFERENT attackers — player A throws a fast M1 while
		-- player B already has a heavy M2 (e.g. Boxing M2) in the air. Best solution:
		--   dodge the M1 in its iframe window → as soon as iframes drop, parry the M2.
		-- Conditions:
		--   1. First threat is M1, second is M2, from DIFFERENT attackers.
		--   2. M1 contact fits exactly in the dodge iframe window.
		--   3. M2 contact leaves enough time to press block after iframes end.
		--   4. Neither is an unblockable must-dodge (those take their own path).
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
				-- M2 must leave room for a full block press after the dodge lands
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

		-- [V134] One dodge is preferred ONLY when its exact planned server iframe interval
		-- covers at least two live CONTACT deadlines. Unlike the old attacker-deduped/drifting
		-- heuristic, this includes Boxing M2 s1+s2 and requires BOTH lower+upper bounds.
		-- It intentionally runs while blocking is available: one confirmed iframe protects a
		-- genuinely simultaneous burst better than spending BlockCooldown on its first hit.
			if clusterStrategy == "IFRAME_CLUSTER" and Config.EmergencyDualDodge
				-- [V156/SAFE-FALLBACK] Обычный multi-dodge больше не опускает рабочий guard.
				-- Неподтверждённый Evasive не должен превращать блокируемый burst в пустую защиту.
				and not canBlockNow()
				-- [V155/BOXING] Даже если оба Boxing-контакта математически помещаются в iframe,
			-- выбранная Ali-политика требует held guard/parry, а не расход Evasive.
			and not State.clusterHasAliBoxingM2(cluster)
			and Config.MultiDodgeCover ~= false and dodgeReady() and canDodgeNow()
			and not counterPreemptsDodge(now) then
			local firstDt = clusterFirst.contactAbs - now
			local iframeLo = ifLat
			local iframeHi = ifLat + ifDur
			-- [V143] Считаем РАЗЛИЧНЫЕ дедлайны, а не записи. Страховка на случай, если дубликаты
			-- одного свинга появятся др��гим путём, чем общий трек: два РАЗНЫХ удара одного врага
			-- физически не могут прийти в одну миллисекунду. Настоящий multi-hit (boxing M2 s1+s2)
			-- разнесён на сотни мс (в диаге contacts=[600,1050]ms) и полностью проходит этот фильтр,
			-- а дубликаты в диаге шли со spread=0..6ms. Порог 30мс их разделяет без новых настроек.
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

	-- [V156/EVCOUNTER-ORDER] Бесплатная Ali M2 уже проверена до idle fast-path. Здесь pending
	-- только защищает принятый dodge от нового Block/Activated, пока завершается транзакция.
	-- Do not send Block/Activated while an Evasive request is awaiting the game's IFRAMES
	-- acknowledgement: Evasive.lua itself rejects requests while Blocking, and a new block
	-- remote can cancel the just-requested dodge. Coverage is resolved by updateDodgeTxn.
	-- ═══════════ [V160] ЭТА ЗАЩИТА ДЛИТСЯ IN-FLIGHT, А НЕ ВСЮ ТРАНЗАКЦИЮ ═══════════
	-- Гейт привязывался к tx.pending, поэтому расширение ack-окна (218мс → 600мс, по дампу)
	-- автоматически заглушило бы Block/Activated, то есть ПАРРИ, на все 600мс. Это был бы
	-- регресс страшнее исходного бага, и вводить его нельзя.
	-- Дамп даёт точную границу применимости. Evasive_ModuleScript:609 —
	--     if u50:GetAttribute("Blocking") then return end
	-- стоит ПРЕДУСЛОВИЕМ, ДО отправки на строке 632:
	--     CombatRemoteClient.Fire("Evasive", "Evasive")
	-- и сразу после отправки Evasive сам гасит блок: StopAnim(u50, "Blocking", nil, 0.08) (:639).
	-- Следовательно поднятый блок способен помешать доджу ТОЛЬКО пока запрос ещё не ушёл на
	-- сервер. После этого никакой Block ретроактивно принятый Evasive не отменяет.
	-- Держим ровно наблюдаемое плечо доставки + один кадр; всё остальное время парри свободно.
	local dtx = State.dodgeTxn
	if dtx and dtx.pending then
		local inFlightUntil = (dtx.fire or 0) + math.max(uplink(), 0.02) + (1 / 60)
		if now < inFlightUntil then return end
	end

	-- [V138] DODGE_M1_PARRY_M2 execution: fire a dodge to cover the incoming M1 with iframes.
	-- The M2 is left in imminent and will be picked up as wantBlock in the normal parry path
	-- once the dodge transaction resolves. Mark the M1 as covered so EDF skips it for parry.
	-- [V156/SAFE-FALLBACK] Если block доступен, не рискуем guard ради неподтверждённого
	-- Evasive. Split-strategy остаётся только когда dodge действительно единственная защ��та.
	if clusterStrategy == "DODGE_M1_PARRY_M2" and not canBlockNow()
	   and dodgeReady() and canDodgeNow() and not counterPreemptsDodge(now) then
		local m1th = cluster[1]
		local m1Dt = m1th.contactAbs - now
		-- [V92] центрируем так же, как escape-ветки: попадание в дальний край окна означало,
		-- что i-frames истекают почти ровно в момент контакта.
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

	-- MustDodge is its own protection path, independent of DodgeHeavy and cluster policy.
	-- Scan all live imminent threats before any legacy heavy/escape decision.
	-- [V128] Работает даже при выключенном Auto Dodge: анблокабл-грэбы блоком не ост��новить,
	-- поэтому передаём bypassAutoOff=true (последний аргумен�� performDodge). Свой тумблер
	-- (Config.MustDodge) остаётся — им и отключается эта защита при желании.
	local mustDodgeThreat = nil
	for _, candidate in ipairs(imminent) do
		if isMustDodge(candidate) then mustDodgeThreat = candidate; break end
	end
	if mustDodgeThreat and dodgeReady() and canDodgeNow() then
		local mustDt = mustDodgeThreat.contactAbs - now
		-- [V92] центрируем: грэб/анблокабл гасится ТОЛЬКО i-frames, поэтому окно должно накрывать
		-- момент регистрации с запасом с двух сторон, а не заканчиваться на нём.
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

	-- [V91] BLATANT force-dodge — ОТД��ЛЬНА�� ветка, потому что блок ниже требует
	-- canDodgeNow()==true, а это ровно то, что ложно, когда мы залочены (в своей атаке /
	-- софт-стане). Срабатывает только если: нормальный додж запре��ён ��офт-состояние��
	-- (canDodgeNow(false)=false), но форс бы прошёл (canDodgeNow(true)=true), мы не можем
	-- блокнуть, и удар входит в окно. Тогда форсим дэш-инпут поверх и��ровой блокировки.
	if Config.SkillAddon and Config.SA_BlatantDodge and dodgeReady() and #imminent >= 1 then
		local a  = imminent[1]
		local dt = a.contactAbs - now
		local normalOk = canDodgeNow(false)
		local forceOk  = canDodgeNow(true)
		local locked   = (State.selfBusyUntil or 0) > now or (not canBlockNow())
		local coverLo  = ifLat - 0.03
		local coverHi  = ifLat + ifDur - 0.04
		-- [V145] Добавлен гейт counterPreemptsDodge. Это была ЕДИНСТВЕННАЯ ветка доджа (кроме
		-- must-dodge, где пропуск сделан осозна��но), которая его не спрашивала: у остальных он
		-- стоит на :4918, :4962, :5051, :5071, :5092, :5148. Под i-frames своей контры форс-дэш
		-- тем более бессмыслен — мы уже неуязвимы, а Evasive всё равно отклонится по
		-- CombatAttacking (дамп Evasive:613 проверяет его БЕЗ ��облажки на грант и на force).
		if (not normalOk) and forceOk and locked and not State.isAliBoxingM2(a)
		   and dt >= (coverLo - 0.06) and dt <= math.max(coverHi, Config.SA_BlatantWindow or 0.32)
		   and not counterPreemptsDodge(now) then
			if performDodge(now, "blatant-override(locked)", true, true) then return end
		end
	end

	if dodgeReady() and canDodgeNow() and #imminent >= 1 then
		local a = imminent[1]
		local soonestDt = a.contactAbs - now

		-- [V65] iframe-окно доджа фиксированное: [fire+DodgeConfirm, fire+DodgeConfirm
		-- +IFrameDur] = [+180,+480]мс. Удар «покрываем», только если его контакт
		-- попадает �� это ��кно (с малым за��асом п�� кр��ям). �� логе оба мистайминга
		-- (TOO EARLY/TOO LATE) были у GRANT-доджей (outnumbered-escape), которые
		-- жглись по факту выдачи эв��йда, а не по удару: если удар ближе 180мс —
		-- iframes не успевали (hit before window), если фитил�� заранее — окно
		-- закрывалось за 1м�� до ��дара. Теперь escape-д��джи привязаны к контакту.
		-- [V92] ЦЕЛИМСЯ В ЦЕНТР i-frame ОКНА, а не в его дальний край. Нижняя граница остаётся
		-- прежней (поздно замеченную угрозу всё равно надо покрыть, даже если центр уже прошёл),
		-- а верхнюю подтягиваем к центру: планировщик опрашивается каждый кадр, поэтому «ещё не
		-- время» просто означает подождать следующий кадр. Даёт ~±150мс запаса с обе��х сторон
		-- вместо 40мс только справа. Ровно та же математика, что в ветке DodgeCenter ниже.
		local coverLo = ifLat - 0.03
		local coverHi = ifLat + ifDur * (Config.DodgeCenterFrac or 0.5)
			+ (Config.DodgeCenterBias or 0)
		-- страховка: центр обязан лежать внутри физически покрываемого интервала
		local coverMax = ifLat + ifDur - 0.04
		if coverHi > coverMax then coverHi = coverMax end
		if coverHi < coverLo then coverHi = coverLo end
		local function dodgeCovers(dt) return dt >= coverLo and dt <= coverHi end
		local coverable = dodgeCovers(soonestDt)

		-- [V154/ALI-DODGE-ABUSE] Это единственный намеренный dodge-вместо-parry при доступном
		-- блоке. Он разрешён лишь на известном остатке M2 cooldown >1с и при полном покрытии всех
		-- угроз внутренней частью iframe. Для Boxing multi-hit первый strike сюда не проходит.
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

		-- GRANT-эскейп: бесплатный эвейд от игры при численном п��ревесе. Грант
		-- держится, пока мы в меньшинст����, поэтому МОЖНО подождать и фитить строго
		-- когда удар входит в iframe-окно (а не палить сра��у �� тратить впустую).
		if Config.OutnumberEscape and evasiveGranted() and coverable
		   and not State.isAliBoxingM2(a) and not counterPreemptsDodge(now) then
			-- [V117] НЕ жжём грант на ОДИНОЧНЫЙ блокируемый удар — надёжнее спарировать. Считаем,
			-- сколько imminent-у��роз попадают в iframe-окно: если ровно ��дна и мы МОЖЕМ блокнуть —
			-- пропускаем додж (ниже отработает блок). Мультиугроза/блок недоступен → эскейпим.
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
			-- combo-эскейп: блок н��доступен (кулдаун/стан) → додж единственная защита. [V96] ТЕПЕРЬ
			-- строго по iframe-окну (coverable = dt в [coverLo, coverHi]). Раньше условие было
			-- `soonestDt <= coverHi` БЕЗ нижней границы → додж жёгс�� когда удар был в упор (dt<coverLo),
			-- iframes не успевали подняться → в логе `combo-escape ... fire→contact=0ms TOO EARLY`.
				if Config.ComboEscapeDodge and Config.DodgeOnParryCooldown ~= false
				   and not canBlockNow() and coverable and not State.isAliBoxingM2(a)
				   and not counterPreemptsDodge(now) then
					if performDodge(now, "combo-escape") then return end
				end
		-- exposed-эскейп: ��ы з��лочены в СВОЕЙ АТАКЕ (не можем блокнуть мид-сви��г) и удар входит в окно.
			-- [V117] гейт по attackBusyUntil (НЕ selfBusyUntil): дэш тоже ставил selfBusyUntil → один додж
			-- делал нас «busy» → следующий удар → ещё один exposed-додж → самоподдерживающийся додж-луп
			-- (в логе dodges=101, почти все exposed). Дэш сам даёт i-frames, передоджить его незачем.
			--
			-- [V92-FIX «фантомный exposed-додж»] attackBusyUntil>now ⇒ мы в СВОЁМ свинг�� ⇒ CombatAttacking=true.
			-- Игровой Evasive (с��. дамп CombatSystemClient/Combat/Base/Evasive.lua, гейты u1.Evasive) ОТКЛОНЯЕТ
			-- Evasive при CombatAttacking. canDodgeNow() этого НЕ ловит (не проверяет CombatAttacking), поэтому
			-- НЕфорсированный додж здесь ВСЕГДА глотается сервером: анимация есть, i-frames нет → удар съедается
			-- (лог: exposed-escape → hit INSIDE i-frame window → LATE/NOT-BLOCKED). Пробить лок атаки можно
			-- Т��ЛЬКО форс-дэш-инпутом — а это по замысл�� режим Blatant Dodge. Поэтому exposed-escape теперь:
			--   1) разрешён ТОЛЬКО при включённом SA_BlatantDodge (в легит-режиме больше не палит впустую);
			--   2) исполняется через force=true (как ветка blatant-override), иначе и в блатанте был бы фантомным.
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
			-- [V90] КОРНЕВОЙ ФИКС ТАЙМИНГА ДОДЖА.
			-- Модель времени (проверена по дампу): contactAbs живёт в КЛИЕНТСКИХ часах
			-- (onAttack: contactAbs = nowClock + remaining0), а getPingRaw() отда��т RTT
			-- (источник A = GetNetworkPing()*2) ⇒ up ≈ RTT. Сервер поднимает IFRAMES через
			-- oneWay после отправки, iframe жив��т IFrameDur; серверный контакт наступает на
			-- oneWay РАНЬШЕ предсказанного клиентского. Отсюда допустимый суммарный lead
			-- ∈ [RTT, RTT+IFrameDur], а центр окна = RTT + IFrameDur/2.
			-- Было: fireLead = inset + DodgeConfirm + DodgeArmWindow, и ниже ещё + up ⇒
			--   M1: RTT+0.38 при максимуме RTT+0.30 ⇒ промах мимо iframe на ~80мс ВСЕГДА;
			--   M2: RTT+0.305 ⇒ промах на 5мс (borderline, «иногда работает»).
			-- DodgeConfirm — это ServerConfirmTimeout игры (таймаут ожидания), а НЕ латентность:
			-- латентность уже полностью учтена членом up. Теперь ��елимся в центр окна.
			fireLead = ifDur * 0.5 + (Config.DodgeCenterBias or 0)
			if a.kind == "M2" then fireLead = fireLead + (Config.HeavyDodgeBias or 0) end
		else
			fireLead = Config.DodgeLead
		end
			-- [V90] + полкадра вперёд: планировщик на Heartbeat, иначе дожидаемся следующего
			-- кадра и опаздываем на dt (при 20 FPS это 50мс — фатально для окна 300мс).
			if soonestDt <= (fireLead + up + (V93.lookahead or 0)) then
				local overloaded, why = false, nil
				-- [V96] ��БЩЕЕ ПРАВИЛО (по требованию юзер��): до��ж — резервная защита, а не основная.
				-- Пока parry доступен (canBlockNow) — блокируем/перфектим ВСЁ, что блокируемо, и НЕ
				-- тратим додж. Все эвристики ниже (heavy/multi/burst/guardbreak) выполняем только
				-- когда блок реально невозможен прямо сейчас. Неблокируемые атаки идут выше отдельным
				-- ��утём must-dodge (isMustDodge), он не завязан на это условие.
				local blockUp = canBlockNow()
				if not blockUp and Config.DodgeOnParryCooldown ~= false then
					-- A non-coverable multi cluster owns its strategy: keep one continuous guard.
					if clusterStrategy ~= "HELD_GUARD" then
						if clusterN >= 2 and clusterHeavy and Config.DodgeHeavy then
							overloaded, why = true, "heavy+multi"
						elseif clusterN >= 3 then
							overloaded, why = true, ("%dx-burst"):format(clusterN)
						end
					end
					-- одиночная M2 при кулдауне блока: спарировать нельзя → уходим доджем
					if a.kind == "M2" and clusterN == 1 and Config.DodgeHeavy and not overloaded then
						overloaded, why = true, "heavy-dodge(no-block)"
					end
				end
				-- guardbreak-save: ста���ина на нуле → guard всё р��вно проломят, ��одж оправдан даже
				-- если формально блок «доступен» (это и есть случай, когда parry не спасёт).
				if not overloaded and Config.GuardbreakProtect then
					local st = blockStamina()
					if st and st <= Config.StaminaFloor then
						overloaded, why = true, ("guardbreak-save(st=%.0f)"):format(st)
					end
				end
				-- [V92] контра приоритетнее: она и защищает (M2GrantsIFrames), и бьёт.
				if overloaded and counterPreemptsDodge(now) then overloaded = false end
				-- [V155/BOXING] При Ali даже no-block/low-stamina не превращает Boxing M2 в dodge:
				-- сохраняем единый parry/held-guard путь вместо старых противоречащих друг другу веток.
				-- [V158/DODGE-CENTER] performDodge теперь может честно ответить WAIT/TOO-LATE/native-gate.
			-- Старый безусловный return в таком случае выбрасывал EDF/parry вместе с неслучившимся dodge.
			if overloaded and not State.isAliBoxingM2(a) then
				if performDodge(now, why) then return end
			end
			end
	end

	-- [V95] ЕДИНЫЙ АВТОРИТЕТ ПОВОРОТА. Раньше здесь напря��ую дёргался faceToward (писал HRP в
	-- Heartbeat), конфликтуя с enforceFaceLock/AutoRotate/шиф��локом в RenderStepped. Теперь только
	-- ВЫСТАВЛЯЕМ цель — прим��нит applyFacing в RenderStepped (последний писатель кадра).
	-- ЦЕЛЬ = атакующий с БЛИЖАЙШИМ ещё-не-прилетевшим контактом (faceTgt), т.к. сервер валидирует
	-- НАШ facing в момент разрешения удара (victim-репорт читает Blocking/PerfectBlocking на
	-- Heartbeat при оверлапе хитбокса ≈ контакт). Смотрим спиной → сервер отклоняет блок. faceTgt
	-- пересчитывает��я каждый кадр, поэтому как только удар первого разрешился — мгновенно
	-- перекид����ваемся на следующего (тайм-мультиплекс поворота по времени контакта). wantBlock —
	-- запасная цель, если facing-кандидата в окне ещё нет.
	-- [V73] midpoint facing for close-angle multi-targets
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
		-- HARD-снап должен успеть ДО разрешения удара: victim-р��порт читает наш facing у контакта,
		-- а пакет летит к серверу ~пол-RTT. Значит жёстко доворачиваемся заранее — за (окно + RTT)
		-- до ��онтак��а. В ��ультибое (2+) — всегда hard, чтобы мг��овенно пе��екидываться ме��ду целями
		-- и не терять кадры на лерп. Иначе (одиночная, далеко) — плавный трекинг.
		local hardWin = (Config.BlockFaceHardDt or 0.30) + up
		local hard = (dtc <= hardWin) or (Config.MultiFaceHard and clusterN >= (Config.MultiThreatMinN or 2))
		-- держим цель до контакта + грейс (перекрывает ��ам момент оверлапа и пару ��адров после)
		setFaceGoal(turnTo.attackerHRP, hard, math.max(dtc, 0) + (Config.HoldAfter or 0.12) + 0.06)
		State.vizTarget = { hrp = turnTo.attackerHRP, model = turnTo.attackerModel }
		publishTarget(turnTo)
	else
		State.vizTarget = nil
		publishTarget(nil)
	end

	-- [V62] Оценка ��ультиугрозы: считаем РАЗНЫХ атакующих среди imminent и самый
	-- дальний угр��жающий контакт кластера. В логе провалы (NO-PRESS NOT-BLOCKED,
	-- BlockCooldown) и����ут именно когда 2+ врага б��ют внахлёст: guard роняется
	-- между их ударами (boxing-counter/deactivate/release) → re-press ловит
	-- BlockCooldown 0.5с (dump: CombatConfig.Block.CooldownSeconds).
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
		-- [V92] ЛАТЧ УДЕРЖАНИЯ КЛАСТЕРА. Баг «2-я атака ��роходит»: как только 1-й атакующий
		-- отрабатывал, multiThreat ��адал до false (остался 1 враг) → guard отпускался по
		-- КОРОТКОМУ одиночному holdUntil, ровно за ~20мс до уд����ра выжившего (diag t=73.07
		-- PERFECT → t=73.35 LATE NO-PRESS). Теперь при обнаружении кластера ЗАПОМИНАЕМ самый
		-- по��дний контакт + грейс и держи�� guard до него, сколько бы угроз ни осталось потом.
		if farContact then
			local latch = farContact + Config.HoldAfter + (Config.HoldLateGrace or 0) + 0.05
			State.multiHoldUntil = math.max(State.multiHoldUntil or 0, latch)
		end
	end

	-- [V157/HEAVY-ATOMIC] Поздняя повторная Heavy удалена. Если ранняя атомарная попытка выше
	-- не отправила COUNTER-SEND, окно этой угрозы уже принадлежит штатному EDF/parry.
	if wantBlock then
		-- ParryWindowDisabled запрещает perfect-window, но не обычный guard. Если guard уже
		-- поднят, не re-arm'им его на каждый удар: помечаем угрозу покрытой и продолжаем hold.
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
		-- Multi-attacker held-guard mode uses exactly one Activated for the whole burst.
		-- Re-arming each threat hits the game's block rate-limit/cooldown and cascades HITs.
		if clusterStrategy == "HELD_GUARD" and State.blocking then
			for _, th in ipairs(cluster) do
				th.pressed = true
				th.coveredByHeldGuard = true
			end
		end
		-- [V103] FACING-ГЕЙТ НАЖАТИЯ (юзер: миссы из-за ЛОЖНЫХ срабатываний → парри на КД). Блок в
		-- этой игре НАПРАВЛЕННЫЙ: сервер отклоняет парри, если жертва ��мот��ит спиной к атакующему
		-- (в логах face=-0.99 BACK! на проваленных парри). Но ло��ально на��атие всё равно ж��ёт
		-- BlockCooldown 0.5с → следующий РЕАЛЬНЫЙ удар уже не заблокировать. Поэтому если мы ещё
		-- смотрим в сторону (faceDot < HighFaceMin) И есть время довернуться (applyFacing крутит нас
		-- каждый кадр) — НЕ жжём нажатие в этот кад��, ждём разворота. Прессим, только когда facing
		-- приемлем ИЛИ времени уже нет (последний шанс — лучше попытка, чем гарантированный хит).
		-- Не трогает мультибой (held-guard путь) и boxing-counter (у них свой снап).
		if not wantBlock.pressed and Config.AutoFace and Config.FaceGateBlock ~= false
		   and not (clusterStrategy == "HELD_GUARD") then
			local fd = faceDotTo(wantBlock.attackerHRP)
			local dtc = wantBlock.contactAbs - now
			local faceFloor = Config.FaceGateMin or (Config.HighFaceMin or 0.25)
			-- «времени н��т» = до контакта меньше, чем нужно на нажатие+RTT (тогда прессим как есть)
			local lastResort = dtc <= ((Config.PerfectLead or 0.0625) + up + 0.02)
			if fd ~= nil and fd < faceFloor and not lastResort then
				-- держим ��ель поворота на этого атакующего и ЖДЁМ — нажатие в этот кадр п��опускаем
				setFaceGoal(wantBlock.attackerHRP, true, math.max(dtc, 0) + (Config.HoldAfter or 0.12) + 0.06)
				if not wantBlock.faceWaitLogged then
					wantBlock.faceWaitLogged = true
					diagPush(("FACEWAIT t=%.2f %s %s face=%.2f<%.2f dt=%+.0fms → rotating, hold press")
						:format(now, wantBlock.name or "?", wantBlock.kind or "?", fd, faceFloor, dtc * 1000))
				end
				return
			end
		end
		-- Single-attacker path retains per-hit re-arm; multi held-guard cannot re-arm.
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
				wantBlock.faceDot  = faceDotTo(wantBlock.attackerHRP)
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
		-- [V62] в м��ль��ибое тянем guard до САМОГО ДАЛЬНЕГО контакта кластера, а не
		-- только б��ижайше��о — так guard не отпускается в се��едине burst и каждый
		-- последующий удар любого врага ловит��я как normal-block (BLOCKABLE↑, HIT↓).
		local base = wantBlock.contactAbs
		-- [V73] SEQUENTIAL: do not extend hold to far contact, so we can re-press for the second
		if multiThreat and farContact and farContact > base and clusterStrategy ~= "SEQUENTIAL" then
			base = farContact
		end
		State.holdUntil = math.max(State.holdUntil,
			base + Config.HoldAfter + (Config.HoldLateGrace or 0) + holdExtra)
	elseif State.blocking then
		-- [V62] пока в кла��тере есть нез��крытые угр��зы — не отпуск��ем guard даже
		-- е��ли ближайший holdUntil истёк (иначе дыра между волнами burst).
		-- [V92] guard держим пока: (а) активен мультиугрозный кластер прямо сейчас, ИЛИ
		-- (б) не истёк ЛАТЧ кластера (State.multiHoldUntil) ��� даже если остался 1 атакующий,
		-- это выживший из кластера, и его удар ещё летит. Так вторая волн�� бо��ьше не проход��т.
		local keepForCluster = (multiThreat and farContact
			and now < (farContact + Config.HoldAfter + (Config.HoldLateGrace or 0)))
			or (State.multiHoldUntil and now < State.multiHoldUntil)
		-- [V73] do not release guard by ReleaseGap while in multi-threat/cluster latch
		local releaseByGap = (not multiThreat) and (not (State.multiHoldUntil and now < State.multiHoldUntil))
			and (now - State.lastPress) > Config.ReleaseGap
		if not keepForCluster and (now >= State.holdUntil or releaseByGap) then
			releaseBlock()
			State.multiHoldUntil = 0
		end
	end

	-- [V100] AutoPlay: добивани�� застаненного врага — к��гда НЕТ угроз для блока. Убрали гейт
	-- `not State.blocking`: step сам уронит guard первым кадром (враг застанен, угро�� нет →
	-- безопасно), а fireM1 самоге��тится на Blocking. Т��к добивание стартует ср��зу после парри,
	-- не дожидаясь истечения HoldAfter. Защита всё равно в приоритете: step идёт только при
	-- #imminent==0 и not wantBlock, т.е. когда парировать/блокировать сейч��с нечего.
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

-- [V125] SKILL-атаки резолвятся сервером ЧЕРЕЗ M2-канал исхода (в логе SKILL(Kure) прилетал
-- как "M2 PerfectBlocked"). Поэтому M2-исход должен уметь матчиться на SKILL-сви��г.
local function outcomeTypeMatches(recType, kind)
	if recType == kind then return true end
	if kind == "M2" and recType == "SKILL" then return true end
	return false
end

local function onOutcome(attacker, result, kind, eventClock)
	-- [V125] СНАЧАЛА находим свинг, к которому относится этот исход, и ТОЛЬКО ПОТОМ трогаем
	-- state. Иначе фантомный доп-удар (2-й страйк мультихита / дубликат сервера) прогонял бы
	-- логику сброса guard (LATE → blocking=false) и ронял защиту посреди комбо → следующий
	-- ��еа��ьный свинг проходил как HIT. Плюс дубликат раздувал tally/resAvg.
	local q = Pending[attacker]
	local rec, looseRec, followUp
	if q then
		for i = #q, 1, -1 do
			local r = q[i]
			local age = eventClock - r.clock
			-- Broadcast may arrive after a newer AnimationPlayed. Never allow a negative-age
			-- outcome to steal that future record; it caused meas=1260ms / 111ms pairings.
			if age >= 0 and age <= Config.MatchWindow and outcomeTypeMatches(r.type, kind) then
				if not r.matched then
					-- Multi-hit одной ани��ации создаёт несколько одинаковых M2 records. Матчим
					-- исход к БЛИЖАЙШЕМУ ожидаемому strike deadline, а не к последней записи queue.
					local score = math.abs((eventClock - r.clock) - (r.contact or 0))
					if r.type == kind then
						if not rec or score < (rec.matchScore or math.huge) then
							rec, r.matchScore = r, score
						end
					elseif not looseRec or score < (looseRec.matchScore or math.huge) then
						looseRec, r.matchScore = r, score
					end
				elseif not followUp and (eventClock - r.clock) <= Config.MultiHitWindow then
					followUp = r   -- уже засчитанный свинг → это ПОЗДНИЙ страйк той же атаки
				end
			end
		end
		if not rec then rec = looseRec end
	end

	-- Доп-удар мультихита (Boxing M2MultiHitCount=2 шлёт 2-е событие) или дубликат сервера:
	-- свин�� уже оценён. НЕ пере-считываем tally и НЕ роняем guard — сброс тут открыл бы нас
	-- под следующий реальный свинг. Guard держится штатным holdUntil.
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

	-- State mutation is now safe: the record was validated before telemetry above.
	rec.matched = true
	if rec.th then rec.th.resolved = true end

	-- GUARDBREAK = guard physically broken. LATE only releases a non-held guard.
	if result == "GUARDBREAK" then
		State.blocking, State.holdUntil = false, 0
	elseif result == "LATE" then
		local holding = State.blocking and (os.clock() < (State.holdUntil or 0))
		if not (State.multiThreat and holding) then State.blocking, State.holdUntil = false, 0 end
	end
	if result == "PERFECT" and rec.th and rec.th.group then
		rec.th.group.cancelled = true -- perfect первого strike останавливает оставшуюся атаку
	elseif result == "EARLY" and rec.th and rec.th.group then
		rec.th.group.held = true -- ordinary block: держим guard до второ��о marker
	end
	-- A perfect resolves the current held-guard transaction. Other attackers in the
	-- latched cluster must be re-armed; keeping pressed=true caused later M2/M1 NO-PRESS.
	if result == "PERFECT" and rec.th and rec.th.clusterStrategy == "HELD_GUARD" then
		for _, other in ipairs(Threats) do
			if other ~= rec.th and not other.resolved and other.contactAbs > eventClock then
				other.pressed, other.coveredByHeldGuard = false, false
				if other.rec then other.rec.pressDt, other.rec.pressServer = nil, nil end
			end
		end
		State.blocking, State.holdUntil, State.multiHoldUntil = false, 0, 0
	end
	-- Только подтверждённый matched PERFECT открывает punish.
	-- следующий Heartbeat не ждёт старый hold/deadline и сразу запускает priority M1.
	if result == "PERFECT" then State.ap.onPerfectParry(attacker, kind) end

	local measured = eventClock - rec.clock
	local predErr  = (measured - rec.contact) * 1000
	State.lastErrMs = predErr

	-- [V116] ЧИ��ТО ДИАГНОСТИЧЕСКИЙ per-(kind,style) средний predErr — в предикт НЕ подаётся
	-- (адаптивная калибрация удалена: отравляла между врагами — обучалась на одном, ломала второго).
	-- Показываем ско��ьзящее среднее ошибки модели только для наблюдения точности в логе.
	local ksKey = tostring(kind) .. ":" .. tostring(rec.style or "?")
	local ks = ResidByKS[ksKey]; if not ks then ks = { sum = 0, n = 0 }; ResidByKS[ksKey] = ks end
	ks.sum = ks.sum + predErr; ks.n = ks.n + 1
	if ks.n > 100 then ks.sum = ks.sum * (100 / ks.n); ks.n = 100 end  -- [V73] cap
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
		if b.n > 100 then b.sum = b.sum * (100 / b.n); b.n = 100 end  -- [V73] cap
	end

	local reasonStr = rec.blockedReason and (" STATE:" .. rec.blockedReason) or ""
	if rec.blockedReason and (result == "LATE" or result == "GUARDBREAK") then
		State.stateHits = (State.stateHits or 0) + 1
	end

	-- [V64] Замер эффективности per-hit rearm: к��пим ре��ультаты по позиции удара
	-- в ком��о. opener = c1-2 (всегда были свежими нажатиями), tail = c3+ (раньше
	-- шли held-guard → HIT). Если после V64 PERFECT на tail вырос, а HIT упал —
	-- rearm работает и сервер перев����одит перфект от свежего Activated.
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

	diagPush(("OUT    t=%.2f  %s  %s(c%d,s%d)  %-10s  meas=%.0fms pred=%.0fms predErr=%+.0fms resAvg=%+.0fms(n=%d) | blockGap=%s pressDt=%s %s%s | face=%s%s spd=%.2f ping=%.0f")
		:format(eventClock, attacker, kind, rec.combo or 0, rec.strike or 1, result, measured*1000, rec.contact*1000,
		        predErr, resAvg, resNShown, gapStr, pressStr, hint, reasonStr, faceStr, faceFlag, rec.speed or 1, (rec.pingRaw or 0)*1000))
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
		-- [module] Attack Desync is a SEPARATE feature from AutoParry. Desyncing YOUR OWN
		-- swings (delay/idlemask own-track handling) must run even when AutoParry (the
		-- parry/dodge brain) is fully OFF. Do it BEFORE the Enabled gate below.
		if Config.DesyncAttack and AnimLib.desyncOwnTrack and rec.isLocal then
			AnimLib.desyncOwnTrack(track, id, animator)
		end
		-- Everything past here is parry logic and requires AutoParry to be enabled.
		if not Config.Enabled then return end
		if not rec.enemy then return end
		-- [V85] защитная анимация вра��а (блок/парри/perfect) — это НЕ входящая атака, не парир��ем.
		if BlockIds[id] then return end
		-- Полное дерево Animations индексируется один раз при старте. Неизвестные ID не
		-- парсим через KeyframeSequenceProvider в горячем AnimationPlayed callback.
		if not attackEntry(id) then return end
		-- [V91] BREAKER GATE. Стоит ЗДЕСЬ (до resolveInfo/onAttack), потому что это самая
		-- дешёвая точка: фантом отсекается до любых аллокаций, styleOf и геометрии.
		-- Два физических инварианта, оба измерены на реальных диагах (см. Config выше):
		--   1) SAME-ID REFIRE: один и тот же animId от одного врага не перезапускается быстрее
		--      DecoyRefireSec. Реальные игроки: 3–25с. Брейкер 614203: 170мс (553 повтора).
		--   2) TRACK SPEED: скорость трека законной атаки лежит в физически выводимой полосе
		--      [DecoySpeedMin, DecoySpeedMax] — вывод формулы см. в Config. Брейкер: 2.36.
		--      [V160] Пункт 2 РАНЬШЕ утверждал «Speed всегда 1.00» и сравнивал с 1.00±0.50.
		--      Это опровергается дампом (M1_ModuleScript:81-90 + CombatPingAnimUtils:13):
		--      скорость трека = h·D/(D+L) и штатно опускается до ~0.37 у высокого врага с
		--      большим пингом. Полоса [0.50,1.50] резала законный диапазон снизу, а
		--      DecoyHardDrop выбрасывал такую атаку ЦЕЛИКОМ — молча, без строки в диаге.
		-- Фантом не должен просто «не нажиматься» — он не должен СУЩЕСТВОВАТЬ, иначе он всё
		-- равно раздувает clusterN и меняет стратегию (в 614203 из-за этого CLUSTER доходил до
		-- n=8 и strategy улетала в HELD_GUARD), а также крадёт boxing-counter (99 холостых).
		if Config.AntiDecoy and Config.DecoyHardDrop ~= false then
			local S = State.decoySeen; if not S then S = {}; State.decoySeen = S end
			local nowd = os.clock()
			local okS, spd = pcall(function() return track.Speed end)
			if okS and type(spd) == "number" and spd > 0 then
				-- [V160] Полоса вместо «1.00 ± tol». spd == 0 исключён намеренно: у только что
				-- загруженного трека Speed успевает прочитаться нулём до AdjustSpeed, и прежний
				-- код на этом дропал ЗАКОННУЮ атаку (0 < 0.5).
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
			-- [V139/PERF] Было: полный pairs-обход раз в 256 вставок, удаляющий только записи
			-- старше 8с. В людном лобби почти все записи МОЛОЖЕ 8с → обход не удалял ни��его, но
			-- счётчик всё равно сбрасывался в 0 → та же дорогая развёртка запускалась снова через
			-- 256 вставок, и так по кругу. ��торой наблюдаемый «фриз при сбросе кэша», и он же
			-- объясняет, почему таблица всё равно продолжала расти.
			-- Теп��рь: (1) развёртка по ВРЕМЕНИ (раз в DecoySweepSec) — её стоимость больше не
			-- зависит от плотности боя; (2) если после развёртки таблица всё ещё крупнее
			-- DecoySeenMax — сносим её целиком. Terse-режим безопасен: единственное следствие —
			-- одна пропущенная same-id проверка на анимацию, �� фильтр по Speed остаётся на месте.
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
	-- [V154/ALI] Подписываемся на raw URE напрямую. CombatBroadcast.On использовать нельзя:
	-- его callback-таблица хранит одного обработчика на имя, и регистрация здесь затёрла бы
	-- игровой VFX-handler. Сигнатура StyleEvasiveCounter(characterName) подтверждена дампом.
	ure.OnClientEvent:Connect(function(eventName, attacker, victim, ...)
		if type(eventName) ~= "string" then return end
		if eventName == "StyleEvasiveCounter" then
			if attacker ~= myName then return end
			local now = os.clock()
			local tx = State.dodgeTxn
			-- [V155/PERFECT-RACE] Raw CombatBroadcastURE и репликация атрибута IFRAMES — независимые
			-- сетевые пути. V154 отбрасывал настоящий StyleEvasiveCounter, если событие приходило на
			-- кадр раньше IFRAMES. Защёлкиваем server-hit при pending; M2 всё равно ждёт ОБА факта.
			-- [V160] Окно приёма proc — бюджет рукопожатия доджа (ackDeadline), а не iframeHi+0.08.
			-- untilAt описывает конец окна НЕУЯЗВИМОСТИ и к моменту прихода серверного события
			-- отношения не имеет: при пинге 112мс он давал 492мс, и StyleEvasiveCounter, пришедший
			-- в пределах законных 600мс игры, молча отбрасывался — Ali-контра не выходила.
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

-- [V90.4] Серверный hitbox-reactor удалён: он срабатывал только по уже-приземлившемуся удару,
-- из-за чего мог держать guard и мешать. Парри теперь
-- полностью предикти��ный (willHitMe по анимации), как и ра��ьше.

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

-- [V144/PERF] Зовётся из __namecall на КАЖДЫЙ FireServer игры (не только боевой) — самый частый
-- из реактивных путей после самого хука. Макроса не имело.
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

-- [V63] Desync-маска идёт СВОЕЙ загруженной копи��й idle, НИК��ГДА не захватывая
-- живые геймплейные треки. П��ошлые вер��ии брали первый не-атаку��щий playing-трек
-- как decoy и дёргали ЕГО вес на 90Гц + Stop() в конце — если это был walk/emote,
-- реальная анимация ломалась (проблема "не воспр��изводит норма��ьно при движении").
-- V62 форсил ст��к-idle 507766388 → чужая поза, визуальны�� снап ("переводится в idle").
-- Ре��ение: определ��ть НАСТОЯЩИЙ idle игры (доминирующий looped не-атака-трек, пока
-- стоим на месте), закэшировать его id и крутить ��ашу собственную копию п��верх.
-- Живые тр��ки не тро��аем вообще → walk/emote целы, а маска = ��од��ой idle и��ры.
local _capturedIdleId
local function captureIdleId(animator)
	local myHRP = localHRP()
	local speed = 0
	if myHRP then
		local ok, v = pcall(function() return myHRP.AssemblyLinearVelocity end)
		if ok and v then speed = Vector3.new(v.X, 0, v.Z).Magnitude end
	end
	-- доверяем захвату только когда стоим (иначе доминирующий looped-трек = walk)
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
	-- id родного idle игры, иначе к��нфиг-фолбэк
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
			-- [V153] Общая ownership-registry: NoDelay не имеет права принять этот Action4-mask
			-- за ручной 4thM1 и остановить его своим replacement-путём.
			local owners = State.ap.trackOwners()
			if owners and _decoyTrack then owners[_decoyTrack] = { owner = "antiparry-idlemask" } end
		end
		return _decoyTrack
end

-- [V75] общий стейт self-verify (объявлен здесь, т.к. используется и тест-режимом ниже)
local SelfVerify = { conn = nil, lastLog = {}, decoyId = nil }

-- [V76] ТЕСТ-РЕЖИМ "наоборот": пока ты стоишь в idle, ПОСТОЯННО проигрываем АТАКУ как
-- decoy (низкий локальный ��ес, тебе почти незаметно). Смысл: на обсер��ере (твоя мобила)
-- должно Н��ПРЕРЫВНО показывать ATTACK, хотя ты н��чего не жмёшь. Если показывает —
-- значит decoy реально ��ходит в репликацию и хук подмены ра��очий. Тум��лер по клавише.
local _testAnim, _testTrack, _testId
local DesyncTest = { on = false }
local function pickAttackId()
	if Config.DesyncTestId then return Config.DesyncTestId end
	-- берём первый M1 из п��оиндексированных атак игры
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
			-- [V153] PRERUN/тест используют этот же track. Пометка обязательна до первого Play:
			-- AnimationPlayed синхронно увидит его, и NoDelay иначе успеет остановить decoy.
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
		-- ма��симальный приорите��, чтобы перебивать walk/run (Movement) — берём Action4 если есть
		local topPrio = Enum.AnimationPriority.Action
		pcall(function() topPrio = Enum.AnimationPriority.Action4 end)
		-- [V91.2] ANTI-AUTOPARRY WEIGHT — this is NOT the desync-mask weight. What fools an
		-- enemy resolver here is the AnimationPlayed EVENT (a fresh Stop→Play replicates the
		-- attack state), not how hard the pose is driven. In V91 I raised this to 0.92 along
		-- with the mask weight; that made the decoy actually win the pose, so on your screen
		-- your character visibly replays the swing over and over (u reported "animations start
		-- playing"). Back to a whisper weight: the event still fires and still replicates, the
		-- rig barely moves, so u only get the tiny twitch u had before.
		local wgt = Config.DesyncClientVisible and 1 or 0.03
		pcall(function()
			track.Priority = topPrio
			track.Looped = true
			track:Play(0.1)
			track:AdjustWeight(wgt, 0)
		end)
		-- [V76.1] maintenance-цикл: при ходьбе игра запускает walk-а��имацию и перебивает
		-- нашу по весу/событию AnimationPlayed → обсервер свалив��лся на WALK. Тут мы каждые
		-- ~0.35с ПЕРЕУТВЕРЖДАЕМ атаку: если её вырубили/понизили вес — перезапус��аем, чем
		-- держим её постоянно доминирую��ей и заставляем AnimationPlayed по ней срабатывать
		-- снова (иначе обсерв��р показал бы последнюю walk-анимацию).
		-- [V76.2] БЕЗ рывка TimePosition=0 (он и вызывал дёрганье у тебя и в репликации).
		-- Держим трек доминирующим только пока движок ��ам не перебил его walk'ом. Важно:
		-- полностью уд����жать чужую картину клиентски НЕЛЬЗ�� — анимация реплицируе��ся
		-- встроенным Animator'��м Roblox (в дампе НЕТ remote при :Play), а не нашим remote-хуком.
		-- [module FIX] Никогда не обнуляе�� Movement/Core/Idle/Action треки. Старый V81
		-- де��ал AdjustWeight(0.01) каждый Heartbeat, поэтому лог закономерно пок��зывал
		-- Movement/Core weight=0 и locomotion исчезала. Decoy продо��жает реплицироваться
		-- через свой Play/Stop цикл, не уничтожая реальные анимации персонажа.
		if DesyncTest.conn then pcall(function() DesyncTest.conn:Disconnect() end) end
		-- [V82] интервал переигрывания = длина анимации атаки (fallback 0.5с). З��цикленный
		-- трек остаётся IsPlaying=true навсегда → AnimationPlayed НЕ срабатывает повторно, и
		-- у наблюдателя стейт "протухает" через длину анимации. По��тому раз в ~длину делаем
		-- ЧИСТЫЙ Stop+Play → свежи�� сетевой AnimationPlayed → атака возобновляется снова и снова.
		local autoEvery = 0.5
		pcall(function() local L = _testTrack.Length; if type(L) == "number" and L > 0.15 then autoEvery = L * 0.92 end end)
		-- Send frequency: Config.DesyncSendHz > 0 forces a fixed re-send rate (Hz), else auto.
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
					_testTrack:Play(0.05)          -- свежий AnimationPlayed → возобновл��ем стейт атаки
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

-- [V84] DESYNC-РЕЖИМЫ на J (переключаются клавишей ]). ВСЁ обёрнуто в do..end и вынесено
-- в одну таблицу DZ — и��аче десяток top-level локалов переполнял 200-регистровый лимит
-- главного чанка Luau ("out of local registers"). Нару��у торчит ��о��ьк�� DZ.
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
-- [V87] IDLEMASK — постоянный спуф на IDLE-анимацию во время атаки. КРИТИЧНО: idle зациклен
-- (Looped=true), поэтому его НЕ НУЖНО перезапуск��ть чер��з Stop/Play — он крути��ся сам. Именно
-- бывший ци��л "Stop(0); Play()" каждые ~длину и ломал ани��ации со временем (постоянные
-- рестарты накапливали рассинхрон аниматора). Теперь: играем idle-decoy ОДИН раз, дальше в
-- Heartbeat лишь мягко переутверждаем приоритет+вес и переиграем ТОЛЬКО если он реально
-- переста�� играть. Никаких прин��дительных Stop → визуал стабилен неограниченно долго.
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
	-- [V91] DESYNC WEIGHT FIX. This used to be `and 1 or 0.03`: with DesyncClientVisible
	-- off (the default) every decoy played at weight 0.03, which barely moves the rig, so
	-- what OTHER clients received was still essentially the real swing pose — the decoy
	-- fooled nobody and idlemask/prerun looked like dead toggles. Roblox replicates track
	-- weight, so a mask must actually WIN the pose: full weight at top priority. Hiding it
	-- from ourselves is not possible via weight (weight is what replicates), so
	-- DesyncClientVisible now only controls a small local fade, not the replicated weight.
	local wgt = Config.DesyncClientVisible and 1 or 0.92
	pcall(function() track.Priority = topPrio; track.Looped = true; track:Play(0.2); track:AdjustWeight(wgt, 0.1) end)
	IdleMask.conn = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
		local an = localAnimator(); if not an then return end
		local tr = getIdleDecoy(an); if not tr then return end
		pcall(function()
			tr.Priority = topPrio
			if not tr.IsPlaying then
				tr.Looped = true
				tr:Play(0.2); tr:AdjustWeight(wgt, 0.1)   -- переиграть ТОЛЬКО если реально остановился
			elseif tr.WeightCurrent < wgt * 0.5 then
				tr:AdjustWeight(wgt, 0.1)                  -- мягко вер��уть вес, без ��естарта
			end
		end)
	end))
	aclog("[desync] idlemask on")
end

-- PRERUN: короткая фейк-АТАКА (decoy-анимация), которую мы реплицируем РАНЬШЕ реальной —
-- вра��еский autoparry цепляе��ся за неё и пар��руе�� не тот удар, реальный ��роходит. Реальный
-- FireServer при этом НЕ задерживается (уходит штатно).
local PreRun = { busyUntil = 0 }
local function firePreRunDecoy()
	local now = os.clock()
	if now < PreRun.busyUntil then return end
	PreRun.busyUntil = now + 0.22
	local animator = localAnimator(); if not animator then return end
	local track, id = getTestDecoy(animator); if not track then return end
	local topPrio = topPriority()
	-- [V91] DESYNC WEIGHT FIX. This used to be `and 1 or 0.03`: with DesyncClientVisible
	-- off (the default) every decoy played at weight 0.03, which barely moves the rig, so
	-- what OTHER clients received was still essentially the real swing pose — the decoy
	-- fooled nobody and idlemask/prerun looked like dead toggles. Roblox replicates track
	-- weight, so a mask must actually WIN the pose: full weight at top priority. Hiding it
	-- from ourselves is not possible via weight (weight is what replicates), so
	-- DesyncClientVisible now only controls a small local fade, not the replicated weight.
	local wgt = Config.DesyncClientVisible and 1 or 0.92
	local dur = (Config.DesyncDelayMs or 140) / 1000
	SelfVerify.decoyId = "rbxassetid://" .. tostring(id)
	task.spawn(function()
		pcall(function() track.Priority = topPrio; track.Looped = false; track:Play(0.02); track:AdjustWeight(wgt, 0) end)
		task.wait(dur)
		pcall(function() track:Stop(0.05) end)
	end)
end

-- центральный перекл��чатель — вызывать при вкл/выкл J и при смене режима
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

-- экспорт наружу через единстве��ный top-level локал DZ
DZ.firePreRunDecoy = firePreRunDecoy
DZ.applyDesyncMode = applyDesyncMode
DZ.cycleDesyncMode = cycleDesyncMode
end  -- do (DESYNC-РЕЖИМЫ)
if type(getgenv) == "function" then getgenv().AP_DESYNC_MODE = DZ.cycleDesyncMode end

-- ����═════════════════ INVISIBLE + GHOST ���══════════════════
-- Ед��нственный top-level локал IV (как DZ) — ��тобы н�� упереться в лимит регистров.
local IV = {}
do
	local RS = RunService
	local function char()      return LocalPlayer.Character end
	local function humanoid()  local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
	local function rootOf()
		local c = char()
		return c and (c:FindFirstChild("HumanoidRootPart") or (humanoid() and humanoid().RootPart))
	end

	-- ---- INVISIBLE ----
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

		-- RenderStep at priority 0 — MUST run BEFORE the camera update so the camera reads
		-- the RESTORED real position. Using Camera+1 (my earlier bug) ran after the camera
		-- had already framed the dropped root → camera dived underground. Priority 0 = fixed.
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

		-- Heartbeat: смещаем корень вниз+разворот → ЭТО реплицируется другим (они тебя не видят).
		Inv.hb = RS.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
			if not Inv.enabled then return end
			local r = rootOf(); local hum = humanoid()
			if not r or not hum then return end
			Inv.oldcf = r.CFrame
			local isR15 = hum.RigType == Enum.HumanoidRigType.R15
			-- Working-script drop: sink the root exactly one body below ground so the parts
			-- are buried. Custom Invisible Height is added on top for deeper burial.
			local baseDrop = (hum.HipHeight or 2) + (r.Size.Y / 2) - 1
			local drop = baseDrop + (tonumber(Config.InvisibleHeight) or 0)
			local cf = r.CFrame - Vector3.new(0, drop, 0)
			pcall(function()
				r.CFrame = cf * CFrame.Angles(math.rad(isR15 and 180 or 90), 0, 0)
				if Inv.track then Inv.track:AdjustWeight(100) end
			end)
		end))

		-- Респавн: перезапустить, чтобы связи не отвалились после смерти.
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

-- [V91] RAKNET block REMOVED (dead code): the send-hook crashed the native client
-- protection (Hyperion) so it was permanently disabled, and its helpers were only kept
-- alive by `_ = fn` no-op references. The desync path uses the __namecall hook on
-- Remotes.Server:FireServer instead. getgenv().AP_RAKNET_SCAN is gone with it.

-- [V74] DESYNC SELF-VERIFY. К��к понять, работает ли desync ВООБЩЕ, без второго
-- аккаунта: Animator.AnimationPlayed срабатывает на КАЖДЫЙ т��ек, который стартует на
-- н��шем аниматоре — а это ровно то, что Roblox реплицируе�� другим клиентам. Значит
-- если при свинге сюда прилетают И реальная атака, И decoy-idle — оба уходят в се��ь,
-- и чужо�� AnimationPlayed увидит оба трека. Э���� объективное доказательство, что
-- decoy-overlay реально загрязняет чужой детект (а не только крутится локально).
-- Помечаем строку [DECOY] когда id совпал с нашим decoy — сразу видно попадание.
-- SelfVerify объявлен выше (перед тест-режимом)
-- [V91] installDesyncSelfVerify REMOVED (dead code): it was never called anywhere, so
-- Config.DesyncSelfVerify was wired to nothing. Its SelfVerify.lastLog table also grew
-- unbounded (one key per distinct animation id ever seen).

-- [V75] КРОСС-КЛИЕНТНАЯ ПРОВЕРКА (отвечает на "как это видят ��ругие игроки").
-- Ты прав: self-verify и Drawing-текст показывают то, что видит ТВОЙ клиент — это лишь
-- ��РОКСИ репликации, а не док��зательство тог��, ��то реально приходит врагу. Единственн��й
-- надёжный способ увидеть чужую картину — смотреть с ДРУГОГО клиента.
-- ��ак по��ьзоваться: запусти скрипт на ВТОРОМ аккаунте (или попроси друга), встань рядом
-- со своим главным и вызови в консоли:  getgenv().AP_OBSERVE("��мяГлавного")
-- ��огда ВТОРОЙ клиент будет логировать каждый трек, который РЕАЛЬ��О реплицировался ему
-- от твоего главног��. Свингни ��а главном — �� в дебаге второго аккаунта увидишь, что
-- ему при��ло: реальная атака, decoy-idle, или (если raknet-rewrite заработает) только idle.
-- Это и есть объективна�� проверка desync с ��очк�� зрения противника.
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

-- [V91/leak] Observers entries were only replaced when the SAME player respawned, so a name
-- key (and its connection) lingered forever once that player left the server. Drop both on
-- PlayerRemoving so a long session with lots of joins/leaves does not accumulate them.
Players.PlayerRemoving:Connect(function(plr)
	local n = plr.Name
	local c = Observers[n]
	if c then pcall(function() c:Disconnect() end); Observers[n] = nil end
	-- [V91.1/leak] Everything else we key by PLAYER NAME. String keys are never GC'd, so each
	-- of these kept a dead player's entry for the whole session. Instance-keyed caches
	-- (State.lastSwingBy, _ownerCache, _animIdCache, _desyncBusyUntil, hooked, V93.hbFirstSeen)
	-- are all __mode="k" weak tables and clean themselves — these string ones can't.
	if State.antiDecoySig then State.antiDecoySig[n] = nil end   -- grew per unique attacker, no eviction at all
	if Pending then Pending[n] = nil end
	-- ComboState is LRU-capped at 64 but keeps its own _count, so decrement it when we drop a key
	-- by hand, otherwise the counter drifts up and the LRU starts evicting live attackers.
	if ComboState[n] ~= nil then
		ComboState[n] = nil
		ComboState._count = math.max((ComboState._count or 1) - 1, 0)
	end
end)

-- [V75] сохранение desync-деб��га в отдельный файл, чтобы сла��ь мне.
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

	-- [V88] сюда доходит ТОЛЬКО delay: idlemask держится своим циклом, prerun — на FireServer.
	if (Config.DesyncMode or "delay") ~= "delay" then return end
	-- [V88] ФИКС "delay л��мал [": [ и idlemask крутят СВОИ decoy-треки, у к��торых тоже
	-- срабатывает AnimationPlayed. Раньше delay-хук хватал их и делал Stop/replay ��� decoy
	-- дёргался. Пропускаем ��аши собственные decoy-треки — трогаем только реальные атаки.
	if track == _testTrack or track == _decoyTrack then return end
	-- [V91.2] MUTUAL EXCLUSION with Anti-AutoParry. Both features drive the same animation
	-- channel: Anti-AutoParry re-Plays its decoy at Action4 every ~0.35s to keep replicating a
	-- fake attack state, while delay-mode Stops the REAL swing and re-Plays it later. Run both
	-- and the rig gets Stop/Play from two owners in the same window — that is the "animations
	-- start playing" u saw. Anti-AutoParry owns the channel while it is on; the packet-side
	-- modes (firedelay/prerun) are unaffected and still work alongside it.
	if DesyncTest.on then
		if (os.clock() - (State.lastAAPSkipLog or 0)) > 2 then
			State.lastAAPSkipLog = os.clock()
			aclog("[desync] anim-delay skipped — anti-autoparry owns the anim channel (use firedelay instead)")
		end
		return
	end

	local window = (Config.DesyncDelayMs or 0) / 1000 + 0.05
	_desyncBusyUntil[track] = now + window

	local origSpeed = 1
	pcall(function() local s = track.Speed; if type(s) == "number" and s > 0.05 then origSpeed = s end end)
	State.desyncFires = (State.desyncFires or 0) + 1

	-- DELAY: анимацию замаха скрываем сразу и переигры����аем через mag мс (визу��л стартует
	-- позже). FireServer/урон НЕ трогаем — они уходят вовремя (отд��льный __namecall-хук).
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

-- [V91] installAnimDesync REMOVED (dead code): never called, and its whole body was a
-- single aclog("[desync] ready") — it installed nothing. The real desync install is the
-- __namecall hook in the task.spawn below.

task.spawn(function()
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		dbg("combat hook: metamethod API unavailable — Guard/BlockKick/Desync disabled")
		aclog("[desync] no metamethod api")
		return
	end
	-- ═══ [V144/PERF] ГОРЯЧЕЕ МЕСТО №1 ВО ВСЁМ СКРИПТЕ ═══
	-- Через __namecall проходит КАЖДЫЙ метод-вызов игры: :FindFirstChild, :IsA, :GetService,
	-- :Clone, вся внутренняя логика игровых скр��птов — десятки т��сяч вызовов в секунду. Любая
	-- лишняя работа тут умножается на это число, поэтому она стоит дороже всего остального кода.
	--
	-- Что было не так:
	--   1) `checkcaller` и `getnamecallmethod` читались как ГЛОБАЛЫ на каждый вызов — два обхода
	--      таблицы глобалов (у executor это ещё и getgenv-прокси) там, где счёт идёт на десятки
	--      тысяч в секунду. Теперь захвачены в локал��ные upvalue один раз при установке хука.
	--   2) `checkcaller()` — C-вызов через границу executor — выполнялся ПЕРВЫМ, то е��ть для
	--      каждого игрового :IsA/:FindFirstChild, хотя его результат нужен ровно для одной ветки
	--      (FireServer). Теперь сначала берём method и, если он не из интересующих пяти, уходим
	--      в oldNamecall НЕ вызывая checkcaller вообще — это ~99.9% всех namecall.
	--   3) Отбор метода шёл цепочкой строковых сравнений (Kick, PostAsync, RequestAsync,
	--      GetAsync, FireServer). Заменено на один хеш-lookup по WATCHED.
	-- Семантика сохранена дословно: для методов вн�� WATCHED прежний код всё равно возвра��ал
	-- oldNamecall (шаг `mine and method ~= "FireServer"` либо финальный `method ~= "FireServer"`)
	-- независимо от checkcaller — так что ранний выход эквивалентен.
	local NC_WATCHED = {
		FireServer = true, Kick = true,
		PostAsync = true, RequestAsync = true, GetAsync = true,
	}
	local nc_getMethod  = getnamecallmethod
	local nc_checkcaller = (type(checkcaller) == "function") and checkcaller or nil
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", hideHook(LPH_NO_VIRTUALIZE(function(self, ...)
		local method = nc_getMethod()
		-- Ранний выход БЕЗ checkcaller: сюда попадает подавляющее большинство вызовов игры.
		if not NC_WATCHED[method] then return oldNamecall(self, ...) end

		-- [V91] DESYNC FIX. This used to be `if checkcaller() then return oldNamecall(...) end`,
		-- i.e. every call made BY OUR OWN SCRIPT skipped the whole hook. Since AutoPlay /
		-- boxing-counter fire most of our swings themselves (State.ap.fireM1 → ServerRemote:
		-- FireServer), desync never saw them and firedelay/prerun looked like dead toggles.
		-- Now executor-origin calls still skip the anti-cheat branches (Kick/HTTP block are
		-- only about the GAME's calls) but DO fall through to the combat/desync path.
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
		-- наш собственный отложенный re-fire (firedelay/prerun) — пропускаем без обраб��тки,
		-- иначе ��н снова отложится (бесконечный цикл) или потеряется.
		if (State.desyncPass or 0) > 0 then return oldNamecall(self, ...) end

		local a1 = (select(1, ...))
		local ok, kind = pcall(classifyCombat, a1)
		if ok and kind then
			-- разовы�� confirm: доказывает, что __namecall ЛОВИТ игровой ��оевой FireServer.
			-- Если этой ��троки нет в диаге после свинга — ху�� не перехватывает FireServer
			-- (тогда идём в raknet/replicatesignal), а не «firedelay сломан».
			if not State.combatFireSeen then
				State.combatFireSeen = true
				aclog(("[desync] combat FireServer intercepted (%s/%s) — hook OK")
					:format(tostring(a1.Action), tostring(a1.Func)))
			end
			local now = os.clock()
				if kind == "attack" then
					State.selfBusyUntil = now + Config.SelfBusyDur
					State.attackBusyUntil = now + Config.SelfBusyDur   -- [V117] busy из-за АТАКИ
				-- FIREDELAY/PRERUN: задер����ваем САМ боевой паке�� (ServerCheck), анимацию не
				-- трогаем. Г��йт стро��о по Func=="ServerCheck" (реальный удар; Hold*-пакеты не
				-- трогаем — иначе рассинхрон чарджа). Перехват на RemoteEvent Remotes.Server —
				-- он доступен (в отличие от модуля CombatRemoteClient, который может лежать в Hidden).
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
					return   -- глотаем немедленную отправку, реальны�� пакет уйдёт из task.delay
				end
			elseif kind == "dash" then
				State.selfBusyUntil = now + Config.DashDuration
			end
		end
		return oldNamecall(self, ...)
	end)))
	AnimLib.desyncHooked = true
	dbg("combat hook active")
	-- [V74] raknet-скан БОЛЬШЕ НЕ стартует при загрузке (это в��шало клиент). Запускай
	-- вручную по команде getgenv().AP_RAKNET_SCAN() когда стоишь в б��ю.
end)

-- [V90] firedelay/prerun теперь обрабатываю��ся ЕДИНСТ��ЕННЫМ владельцем — __namecall-хуком
-- на Remotes.Server:FireServer (выше). Отдельный хук на CombatRemoteClient.Fire УДАЛЁН: он
-- (а) патчи�� таблицу по пути ReplicatedStorage.Shared.Network, к��торая может ��ы��ь декоем, пока
-- реальный модуль лежит в Hidden, и (б) при работающем namecall-хуке давал ДВОЙНУЮ задержку
-- (модуль держал → origFire → Server:FireServer → namecall д��ржал снова). RemoteEvent
-- Remotes.Server реплицируется и всегда достижим, поэтому перехват на нём надёжнее модульного.

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

-- [V154/LOW-FPS] Реактивная транзакция теперь исполняется в PreSimulation, ДО physics/hitbox
-- текущего кадра. Heartbeat был фундаментально поздней фазой: на 30 FPS серверная проверка удара
-- могла разрешиться до нашего press, хотя математический deadline уже наступил. Fallback оставлен
-- только для старого runtime без PreSimulation; второго scheduler нет, FrameId растёт один раз.
V93.schedulerPhase = RunService.PreSimulation and "PreSimulation" or "Heartbeat-fallback"
;(RunService.PreSimulation or RunService.Heartbeat):Connect(LPH_NO_VIRTUALIZE(function(hbDt)
	-- [V154] Дельта реактивного кадра (PreSimulation/Heartbeat fallback) → EMA → lookahead.
	-- Считаем ДО раннего выхода по Enabled, чтобы при включении тумблера первый же кадр
	-- уже имел валидную оценку, а не 1/60 «с потолка».
	if type(hbDt) == "number" and hbDt > 0 then
		local d = math.clamp(hbDt, 1/480, 0.25)
		V93.frameDt = V93.frameDt + (d - V93.frameDt) * 0.2
		-- [V139] ПИК: вверх мгновенно (один длинный кадр сразу поднимает компенсацию), вниз
		-- экспоненциально ��а FrameLookaheadPeakDecay. Именно это лечит «плохо парирует на низком
		-- FPS»: EMA сглаживала ровно те дропы, из-за которых press и опаздывал.
		if d > V93.frameDtPeak then
			V93.frameDtPeak = d
		else
			local hl = Config.FrameLookaheadPeakDecay or 1.10
			V93.frameDtPeak = V93.frameDtPeak + (d - V93.frameDtPeak) * math.clamp(d / hl, 0, 1)
		end
	end
	do
		-- Компенсируем ХУДШИЙ из двух сценариев: устойчиво низкий FPS (EMA) и рваный (пик).
		local byEma  = V93.frameDt     * (Config.FrameLookahead or 0.5)
		local byPeak = V93.frameDtPeak * (Config.FrameLookaheadPeakK or 0.5)
		local want   = (byEma > byPeak) and byEma or byPeak
		-- + собственная стоимость шага: `now` фиксируется здесь, а press-сравнение исполняется
		-- уже после геометрии всех угроз, и этот сдвиг раньше не компенсировался вообще.
		want = want + (V93.stepCost or 0) * (Config.FrameStepCostComp or 0.60)
		-- Потолок адаптивный: фиксированные 45мс обрезали компенсацию всё ниже ~14 FPS.
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
	FrameId = FrameId + 1        -- [V68] invalidates per-frame HRP cache
	-- [V91] Переутверждаем направ��ение движения для ��ыбора M2-варианта. Humanoid:Move задаёт
	-- MoveDirection только на текущ��й кадр (дальше его перезапишет игровой ControlModule), а
	-- сервер резолвит вариант из РЕПЛИЦИРОВАННОГО MoveDirection при обработке нашего ServerCheck —
	-- т.е. на ~oneWay позже отправки. Поэтому держим направление короткое окно вокруг выстрела.
	if State.ap.steerUntil and now < State.ap.steerUntil and State.ap.steerDir then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		-- [V144/PERF] Было pcall(function() ... end) — новое замыкание КАЖДЫЙ кадр пока открыто
		-- steer-окно. Тот же паттерн уже вычищен из геометрии в V68 через персистентные fn; здесь
		-- он остался. Персистентная _humMove не аллоцирует ничего.
		if hum then pcall(V93.humMove, hum, State.ap.steerDir) end
	end
	-- [V155/ALI-FORWARD] Отдельный steer нельзя смешивать с M2 variant steer: первый нужен
	-- Evasive до server receipt, второй — уже последующей M2. Поля и окна независимы.
	if State.ap.dodgeSteerUntil and now < State.ap.dodgeSteerUntil and State.ap.dodgeSteerDir then
		local c = localChar()
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum then pcall(V93.humMove, hum, State.ap.dodgeSteerDir) end
	end
	pcall(schedulerStep, now)    -- [V68] one persistent-fn pcall guards the whole loop
	                             -- (no per-read closures inside anymore → far less GC)
	-- [V139] Стоимость собственного шага → EMA. Кормит lookahead выше: на слабой машине с
	-- десятком угроз геометрия+трейсы съедают 4–12мс между ��зятием `now` и press-сравнением.
	V93.stepCost = V93.stepCost + ((os.clock() - now) - V93.stepCost) * 0.15
	pcall(restrictStep, now)

	-- ФИКС ЗАСТРЕВАНИЯ БЛОКА: единая реконсиляция guard. Несколько путей (dodge, boxing-
	-- counter, onOutcome LATE/GUARDBREAK) сбрасывают State.blocking напрямую, НЕ отправляя
	-- Deactivated → сервер продолжал держать guard до ручного нажатия. Тут гарантиру��м:
	-- если серверу отправлен Activated (guardUp), но намерения б��окировать больше нет —
	-- принудительно снимаем guard. Идемпотентно и безопасно (force обходит рейт-гейт).
	if State.guardUp and not State.blocking then
		pcall(sendDeactivate, true)
	end

	-- [PERF] Pending-очередь �� это housekeeping (сборка протухших записе�� >3с), НЕ
	-- реактивный путь. Гонять полный обход pairs(Pending) каждый Heartbeat (до 240/с)
	-- впустую при пустой/мелкой очереди — лишний GC-обход на слабых машинах. Чистим
	-- раз в ~15 кадров; TTL=3с это с запасом переживает, тайминг пар��рования не зависит
	-- от этого шага вообще.
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
		-- [V140] Версия и время снятия дампа берутся из кода, а не из забытого литерала.
		("===== AUTOPARRY %s DIAG =====  (dumped %s UTC)")
			:format(tostring(Config.Version or "?"), os.date("!%Y-%m-%d %H:%M:%S")),
		("player=%s  ping=%.0fms  uplink=%.0fms  mode=%s  autoface=%s"):format(LocalPlayer.Name, getPingRaw()*1000, uplink()*1000, Config.Mode, tostring(Config.AutoFace)),
		-- [V154/LOW-FPS] Эти поля отличают позднюю фазу scheduler от ошибки predictor: fps берётся
		-- из реактивной EMA, peak ловит единичный длинный кадр, step — стоимость самой геометрии.
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

-- [V151] saveDiag УДАЛЁН: ноль вызовов (кнопки сохранения в UI нет, диаг читается из консоли).
-- Освобождает ещё один регистр главного чанка — причина "out of local registers".

-- [V130] REGISTER FIX ("out of local registers"): the whole AutoParry visuals module lives in a
-- `do ... end` block so its ~20 constants/pools/draw-funcs stop counting against the main-chunk
-- local budget (Luau hard-caps a function at 200 locals; we were at 212). Only vizUpdate/vizHideAll
-- escape (forward-declared below), and the 5 user-tweakable colors moved to Config (so the UI can
-- still read/write them without keeping 5 main-chunk locals alive).
Config.RingA       = Config.RingA       or Color3.fromRGB(196, 158, 255)
Config.RingB       = Config.RingB       or Color3.fromRGB(122, 214, 255)
Config.ConeSafe    = Config.ConeSafe    or Color3.fromRGB(96, 214, 140)
Config.ConeHit     = Config.ConeHit     or Color3.fromRGB(255, 84, 84)
Config.RestrictCol = Config.RestrictCol or Color3.fromRGB(255, 72, 72)

local vizUpdate, vizHideAll   -- forward-declared; assigned (без local) inside the module below
do
-- [V112] PERF: RING 40→24, CONE 18→12. Каждый сегмент = 2 WorldToViewportPoint (+запись Drawing).
-- 40+18 дав��ло ~140 WTV/кадр отрисовки; 24+12 = ~90 (−35%) при визуально идентичном кольце/конусе
-- (24 сег на круг = 15°/сегмент — глазу гладко). Это всегда-активная работа → режем в корне.
local RING_SEG  = 24
local CONE_SEG  = 12
local CONE_FILL = 0.32
local VIZ_CONE_HALF = math.rad(64)
local VIZ_CONE_PAD  = 5.0
local VIEW_DIST = 100

-- ═══ [V144/PERF] ПУЛЫ DRAWING БЫЛИ ВИРТУАЛИЗИРОВАНЫ ═══
-- Luraph виртуализирует ВСЁ, что не обёрнуто в LPH_NO_VIRTUALIZE (шапка файла: 50-200x медленнее).
-- `:get()` вызывается ~280 раз за одну перерисовку ESP, `:finish()` обходит весь пул — то есть в
-- обфусцированной сборке это были сотни вызовов интерпретатора на кадр. Ни одна из этих функций
-- макроса не имела. Метод-синтаксис `function LinePool:get()` обернуть макросом нельзя, поэтому
-- переписано в присваивание с явным self — вызовы `LinePool:get()` продолжают работать как были.
local LinePool = { items = {}, used = 0, ok = (Drawing ~= nil) }
LinePool.begin = LPH_NO_VIRTUALIZE(function(self) self.used = 0 end)
LinePool.get = LPH_NO_VIRTUALIZE(function(self)
	if not self.ok then return nil end
	self.used += 1
	local ln = self.items[self.used]
	if not ln then
		-- Замыкание тут создаётся только в момент РОСТА пула (первые кадры), а не на каждый get.
		local created = pcall(function() ln = Drawing.new("Line") end)
		if not created then self.ok = false; return nil end
		self.items[self.used] = ln
	end
	return ln
end)
-- [V144/PERF] finish() гасил ХВОСТ пула каждый кадр от used+1 до #items. Пул растёт до пика сцены
-- (ринг 24 сегмента + хитбокс + зона), и после тяжёлого кадра каждый последующий лёгкий кадр
-- переставлял .Visible=false на десятках уже погашенных объектов — запись свойства Drawing идёт
-- через C-границу и стоит дорого. Помним, до какого индекса реально гасили, и не трогаем дважды.
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

-- [module] AnimDbg (экранный Drawing-текст "ANIM ... | desync ...") УДАЛЁН полностью по запросу.

local Viz = { t = 0 }

local NEAR = 0.6

-- [V144/PERF] Вся геометрия ESP была виртуализирована. Это самые вызываемые функции скрипта:
-- rotY — 24 раза на ринг, proj — по 2-3 на каждый сегмент (~280 сегм��нтов), т.е. сотни вызовов
-- на кадр через интерпретатор Luraph. Плюс математика тут чисто числовая — ровно тот код, который
-- от девиртуализации выигрывает больше всего.
Viz.rotY = LPH_NO_VIRTUALIZE(function(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end)

-- [V144/PERF] projRaw отдаёт X/Y/Z числами и НЕ аллоцирует Vector2. Прежний proj создавал Vector2
-- на каждую точку ДО проверки глубины, поэтому за камерой (az<=NEAR) объект выбрасывался сразу
-- после создания — чистый мусор для GC. За кадр это до ~600 Vector2 на выброс, а именно GC-паузы
-- и ощущаются как рывки. Vector2 теперь строится только для точек, которые реально рисуются.
Viz.projRaw = LPH_NO_VIRTUALIZE(function(cam, world)
	local sp = cam:WorldToViewportPoint(world)
	return sp.X, sp.Y, sp.Z
end)

-- Совместимость: proj остался для внешних вызовов с прежней сигнатурой (Vector2, depth).
Viz.proj = LPH_NO_VIRTUALIZE(function(cam, world)
	local x, y, z = Viz.projRaw(cam, world)
	return Vector2.new(x, y), z
end)

Viz.drawWorldSeg = LPH_NO_VIRTUALIZE(function(cam, a, b, color, thick)
	local ax, ay, az = Viz.projRaw(cam, a)
	local bx, by, bz = Viz.projRaw(cam, b)
	-- Обе точки за камерой → выходим ДО любых аллокаций и ДО занятия слота пула.
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

-- [V111] PERF: чтение bbox через персистентную fn (без closure/кадр) + 1-кадровый кэш. drawFlatRing
-- и footYOf оба тянут bbox цели каждый кадр — раньше каждый делал pcall(function()...GetBoundingBox
-- ()...end) (замыка��ие + отдельный вызов). Всё состояние/функции держим полями Viz (НЕ новые local:
-- лимит 200 живых локалов на функцию — модуль впритык).
Viz.bboxRaw = function(m) return m:GetBoundingBox() end
Viz.bbModel, Viz.bbClock, Viz.bbC, Viz.bbS = nil, -1, nil, nil
-- [V112] PERF: ПЕРСИСТЕНТНЫЕ scratch-буферы для точек кольца/конуса. Раньше drawFlatRing де��ал
-- `wpts={}` и drawTargetHitbox — `wArc={}`,`a2d={}`,`az={}` НА КАЖДЫЙ кадр отр��совки = 4 таблицы +
-- ~100 Vector2/Vector3 а��локаций/кадр → GC-дёрганье (главная оставшаяся причина «лагает»). Теперь
-- переиспользуем таблицы (индексы просто перезаписываются, размер сегментов константный). Держим
-- ��олями Viz (НЕ новые local — лимит 200 локалов на giant-функцию).
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

-- [V93] TARGET RING — styles ported from the TargetESP reference the user supplied.
--   Flat       : classic ring on the floor under them (what we always had)
--   Orbit      : the ring is pushed through DEPTH per segment (cos wave), so instead of lying flat
--                it reads as a 3D band tilted around the target
--   OrbitSwirl : same band, but the whole thing also spins around them
-- Orbit styles also draw a MIRRORED ring (the segment angles negated and the depth inverted) —
-- that second pass is what actually sells the 3D effect in the reference.
-- Segment count is user-controlled; each segment costs 2 viewport projections, so it is clamped.
-- [V94.1] TARGET RING — now matching the reference properly.
-- The reference does NOT draw thin lines: every segment is a Drawing "Quad" spanning the gap
-- between radius*0.95 and radius, i.e. a FILLED RIBBON, and each segment is pushed through depth
-- by cos(t + i/seg*2pi) * tilt so the ribbon undulates in 3D. On top of that it draws:
--   • a mirrored ribbon (angles negated, depth inverted) — the crossing second band
--   • a translucent "blur" copy slightly below, which is what gives it that glowy body
-- OrbitSwirl is simply that same ribbon with the whole thing rotating (angle += t*speed*0.75) —
-- it is NOT a stack of many rings, which is what I wrongly built before.
-- Filled geometry comes from TriPool (2 triangles per quad); Flat still uses the cheap line ring.
-- [V144/PERF] Ribbon — самый дорогой элемент ринга: он рисуется дважды (основная лента + зеркальная)
-- и ещё ра�� для blur-копии, т.е. ��о 3×seg вызовов на кадр. Раньше он создавал 4 Vector2 и ТОЛЬКО
-- потом проверял глубину, поэтому за камерой ��се четыр�� уходили в мусор. Сначала глубина, потом
-- аллокации. Плюс сам он был виртуализирован.
Viz.ribbonQuad = LPH_NO_VIRTUALIZE(function(cam, a, b, c, d, color, transp)
	-- a,b = inner edge (angle1, angle2), c,d = outer edge (angle2, angle1)
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

-- [V144/PERF] ГРАДИЕНТ-LUT. `Config.RingA:Lerp(Config.RingB, f)` создавал НОВЫЙ Color3 на каждый
-- сегмент каждой перерисовки: ринг (до 48) + зеркальная лента + blur-копия — под сотню объектов на
-- кадр, которые живут до ближайшего GC. Именно такой ровный поток мелкого мусора и даёт
-- периодические микро-фризы, а не одна дорогая операция. Оттенки на глаз неразлич��мы, поэтому
-- держим 33 предпосчитанных ступени и берём готовый Color3 по индексу. Таблица пересобирается
-- только при смене RingA/RingB (то есть при правке настроек), а не каждый кадр.
-- Ключ — сами Color3 по значению (в Luau это value-тип, сравнение не аллоцирует). Через tostring
-- было бы хуже исходного кода: строка на каждый вызов вместо Color3 на каждый вызов.
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

-- [V144/PERF] drawRing/drawTargetHitbox/drawRestrictZone — тела перерисовки ESP (тригонометрия по
-- сегментам, обход scratch-буферов, запись свойств Drawing). Без макроса каждый кадр целиком шёл
-- через интерпретатор Luraph.
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

	-- ── Flat: the classic cheap line ring on the floor ───────────────────────
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

	-- ── Orbit / OrbitSwirl: filled undulating ribbon ─────────────────────────
	local bodyY = footY + ((bs and bs.Y or 5) * 0.5)
	local swirl = (style == "OrbitSwirl") and (t * 0.75) or 0
	local tilt  = Config.VizRingTilt or 0.7
	local rIn   = radius * 0.985      -- [V94.2] tighter band (was 0.95 — user wanted them closer)

	for i = 0, seg - 1 do
		local a1 = (i / seg) * math.pi * 2 + swirl
		local a2 = ((i + 1) / seg) * math.pi * 2 + swirl
		-- depth wave: same offset for the whole segment, so the ribbon bends smoothly
		local dy = math.cos(t + (i / seg) * math.pi * 2) * tilt
		local f  = 0.5 + 0.5 * math.sin((i / seg) * math.pi * 2 + t * 2.2)
		local col = Viz.grad(Config.RingA, Config.RingB, f)

		local y = bodyY + dy
		local c1, s1 = math.cos(a1), math.sin(a1)
		local c2, s2 = math.cos(a2), math.sin(a2)
		-- NOTE: in this Drawing API Transparency 1 == FULLY OPAQUE (see drawWorldSeg, which always
		-- passes 1). I had been passing 0/0.08 here, which is why the ribbon looked washed out.
		-- Vector3 is an immutable value type, so there is no way to avoid building the 4 corner
		-- points; what we DO avoid is the 2 extra Vector3 the old mirrored *ribbon* needed, and the
		-- 2 more the blur copy needed (both gone now) — that alone cut this loop's allocations in half.
		Viz.ribbonQuad(cam,
			Vector3.new(cx + c1 * rIn,    y, cz + s1 * rIn),
			Vector3.new(cx + c2 * rIn,    y, cz + s2 * rIn),
			Vector3.new(cx + c2 * radius, y, cz + s2 * radius),
			Vector3.new(cx + c1 * radius, y, cz + s1 * radius), col, 1)

		-- [V95] mirrored pass is a plain LINE with the SAME opacity as the ribbon (user asked for the
		-- mirror to match, not to be a translucent ghost — drawWorldSeg is always opaque).
		if Config.VizRingMirror ~= false then
			local ym = bodyY - dy
			local rMid = (rIn + radius) * 0.5
			Viz.drawWorldSeg(cam,
				Vector3.new(cx + math.cos(-a1) * rMid, ym, cz + math.sin(-a1) * rMid),
				Vector3.new(cx + math.cos(-a2) * rMid, ym, cz + math.sin(-a2) * rMid),
				-- Lerp(B,A,f) тождественно Lerp(A,B,1-f), поэтому зеркальная лента идёт через ТУ ЖЕ
				-- таблицу. Если бы порядок цветов остался обратным, LUT пересобиралась бы на каждый
				-- сегмент (33 Color3 вместо одного) — вышло бы кардинально хуже исходного кода.
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
	-- [V97/PERF] styleForward does a pcall+closure internally; it was called 4x here for 2 values
	local styleReach = math.max(styleForward(style, "M1"), styleForward(style, "M2"))
	local reach = styleReach + VIZ_CONE_PAD
	local half  = VIZ_CONE_HALF
	local y = Viz.footYOf(model, hrp)
	local origin = Vector3.new(hrp.Position.X, y, hrp.Position.Z)

		local col = Config.ConeSafe
		local me  = localHRP()
		if me then
			local forward = styleReach   -- [V97/PERF] reuse the value computed a few lines above
			local off  = Vector3.new(me.Position.X - hrp.Position.X, 0, me.Position.Z - hrp.Position.Z)
			local fwd  = off:Dot(flook)
			local side = math.abs(off:Dot(Vector3.new(-flook.Z, 0, flook.X)))
			local slack = Config.HitboxSlack or 0
			if fwd >= (forward - Config.HitboxDepthBack - slack) and fwd <= (forward + Config.HitboxDepth + slack)
			   and side <= (Config.HitHalfWidth + slack) then
				col = Config.ConeHit
			end
		end

	local wArc = Viz.coneW   -- [V112] переиспо��ьзуемые буферы, без аллокации таблиц/кадр
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
	-- [module] AutoParry visuals belong to AutoParry: hide them the instant the feature
	-- is disabled, not just when ShowVisuals is off.
	if not (Config.Enabled and Config.ShowVisuals and cam) then vizHideAll(); return end
	Viz.t += dt   -- анимационные часы идут КАЖДЫЙ кадр (дёшево) → фаза кольца пла��ная ��аже при троттле

	-- [V111] PERF-ТРОТТЛ: тяжёлую перерисовку (пулы + ~280 операций проекции/Drawing) делаем не
	-- чаще VizMaxFPS. Между апдейтами НЕ трогаем пулы (begin/finish не зовём) → дровинги остаются
	-- видимыми на прошлых позициях; при 120+ fps это срезает основную всегда-активную нагрузку.
	local nowc     = os.clock()
	local interval = 1 / math.clamp(Config.VizMaxFPS or 60, 15, 240)
	-- [V139/PERF] АВТО-ДЕГРАДАЦИЯ. Троттл по VizMaxFPS по��огает только когда игра БЫСТРЕЕ кэпа.
	-- Когда FPS ПРОСЕЛ (20 FPS = 50мс ка��р > interval 16мс) условие ниже всегда ложно, и полная
	-- перерисовка (~280 операций проекции + пулы Drawing) платится КАЖДЫЙ кадр — ровно тогда,
	-- когда бюджета и так нет. ESP усугублял просадку, из-за которой сам ��е и вызывался.
	-- Привязываем интервал к РЕАЛЬНОЙ дельте кадра: на 20 FPS рисуем раз в ~2 кадра вместо
	-- каждого. Визуально ESP там и так дискретный, а кадру возвращается полов����на стоимости.
	if Config.VizAutoDegrade ~= false then
		local byFrame = V93.frameDt * (Config.VizFrameShare or 1.5)
		if byFrame > interval then interval = byFrame end
	end
	if (nowc - (Viz.lastDraw or 0)) < interval then return end
	-- [V139] ПРИОРИТЕТ ЗАЩИТЫ. Если press-дедлайн внутри VizSkipNearPress — кадр целиком
	-- отдаётся парирован��ю: ESP не рисуется вообще. Это те 1–2 кадра, где точность тайминга
	-- решает исход, а полная пер��рисовка стоит больше, чем весь schedulerStep.
	-- [V140] Пропуск теперь ОГРАНИЧЕН с двух сторон, иначе он превращается в вечную заморо��ку:
	--   1) метрика обязана быть СВЕЖЕЙ — nearPress пишется на Heartbeat, а читается здесь, на
	--      RenderStepped; несвежая (>0.2с) означает, что планировщик до неё не дошёл;
	--   2) даже при свежей метрике подряд пропускаем не больше VizSkipMaxFrames кадров. Защита
	--      получает свои 1–2 кадра, но затяжное окно угроз уже не может держать ESP погашенным.
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
	-- [V93] Publish EXACTLY the target the visuals are drawing on, so the Visuals TargetHUD shows
	-- the same enemy as the ring/hitbox. Previously the HUD was fed only from the threat scheduler,
	-- so with no live threat the ring picked the nearest enemy while the HUD had nobody → the
	-- "TargetHUD works weirdly" report. publishVizTarget is a no-op when nothing changed.
	publishVizTarget(model, hrp)
	if model and hrp then
		local hot = (State.status == "PARRY" or State.status == "DODGE")
		if Config.VizHitbox ~= false then Viz.drawTargetHitbox(cam, model, hrp) end
		if Config.VizRing ~= false then Viz.drawRing(cam, model, hrp, hot) end
	end
	if Config.VizRestrict ~= false then Viz.drawRestrictZone(cam) end
	LinePool:finish(); TriPool:finish()
end)
end   -- [V130] close AutoParry visuals module (do-block for register budget)

-- [V95] ЕДИНЫЙ АППЛИКАТОР ПОВОРОТА. Единственное место, где ��ишется HRP.CFrame ради facing.
-- Работает в RenderStepped ПОСЛЕ игрового AutoRotate/SmoothShiftLock (��ы подключаемся позже —
-- игра грузится раньше), поэтому наш поворот — последний писатель кадра и не проигрывает г��нку.
-- Пока есть активная цель — гасим Humanoid.AutoRotate, чтобы игра не докручивала HRP к движению
-- (это и рвало снап + давало д��рганье). Как только цель истекла — О��ИН раз возвращаем AutoRotate.
local applyFacing = LPH_NO_VIRTUALIZE(function()
	local goalPos = State.faceGoalPos   -- [V73]
	local goalHRP = State.faceGoalHRP
	-- [V91/perf] FAST PATH: with no facing goal there is nothing to do and nothing to
	-- reset (faceHum is only ever set while a goal is active). Bail before touching
	-- localChar()/GetAttribute — this runs on EVERY rendered frame, and the idle case
	-- (no goal) is by far the most common one.
	if not (goalHRP or goalPos) and not State.faceHum then return end
	-- [V101] EQUIP-ГЕЙТ ротации (юзер: скрипт крути�� перса без одетых рук). Игра запрещает
	-- блок/парри/M1 при Equip ~= true (isInBlockingPreventedState), значит и доворачиваться
	-- незачем. Если руки не одеты — сбрасываем цель поворота и ВОЗВРАЩАЕМ AutoRotate (как при
	-- истечении цели), чтобы отдать управление игроку. Кросс-платформенно (атрибут, не клавиша T).
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
	-- [V91/perf] reuse the character we already resolved above (`ec`) instead of calling
	-- localChar() a second time in the same frame.
	local hum = ec and ec:FindFirstChildOfClass("Humanoid")
	-- [V94] AimLock deliberately LEAVES AutoRotate alone: the whole point is that the game keeps
	-- turning the character toward the camera, so killing it would freeze us facing the wrong way.
	-- LookAt still disables it, because there we own the character's rotation.
	if (Config.RotationMethod or "LookAt") ~= "AimLock" then
		if hum and hum.AutoRotate then hum.AutoRotate = false; State.faceHum = hum end
	elseif State.faceHum then
		pcall(function() State.faceHum.AutoRotate = true end); State.faceHum = nil
	end
	-- [V97] PING-SCALED предикт позиции цели ВОЗВРАЩЁН. В V95 я убрал velocity-lead (ду��ая, что
	-- сервер вали��ир��ет по факт. позиц��и) — но это ломало facing на резко движущемся/рывкающем
	-- враге (в логе face=0.14/-0.58 BACK! на LATE-мисс��х). Причина: на нашем экране другой игрок
	-- отрисован в ПРОШЛОМ (интерп-лаг + ping), а ��ервер держит его ВПЕРЕДИ. При рывке рассинхрон
	-- = vel*latency растёт → мы смотрим туда, гд�� враг БЫЛ, сервер видит спину → блок отклонё��.
	-- Упреждаем: aim = pos + flatVel * (ping-based lead). Стоит н�� месте (vel≈0) �� lead≈0 → как
	-- раньше (нет регресса на статичном боксинг��). Рывок → смотрим на СЕРВЕРНУЮ позицию врага.
	local aimPos = goalPos or goalHRP.Position
	local lead   = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.28)
	if lead > 0 then
		-- прямое чтение свойства (goalHRP уже проверен на .Parent) — БЕЗ pcall-замыкания,
		-- иначе каждый RenderStepped-кадр боя аллоцировался бы новый closure (лишний GC).
		local vel     = goalHRP.AssemblyLinearVelocity
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		-- [V118] раскладываем упреждение на РАДИАЛЬ (вдоль линии враг↔я) и БОКОВУЮ (перпендикуляр).
		-- Боковая задаёт угол facing → щедрый кап; радиаль на угол не влияет → малый кап. Так дэш
		-- В УПОР (радиальный) больше НЕ съедает бюджет боковой коррекц��и (толчок влево/вправо).
		local gp = goalHRP.Position
		local toMe = Vector3.new(myHRP.Position.X - gp.X, 0, myHRP.Position.Z - gp.Z)
		if toMe.Magnitude > 0.05 then
			local axis     = toMe.Unit
			local radialVec = axis * flatVel:Dot(axis)   -- составляющая вдоль линии
			local latVec    = flatVel - radialVec         -- боковая составляющая
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

	-- [V94] ROTATION METHOD.
	--   LookAt  : rotate the character itself (what we always did). The server validates block
	--             direction off the character, so this is the one that guarantees a legal parry.
	--   AimLock : DON'T touch the character — point the CAMERA at them instead. With shiftlock (or
	--             any first/third-person aim-follow) the game turns you toward the camera itself, so
	--             u still end up facing them, but the model never snaps unnaturally. Looks far more
	--             legit; if the game is NOT rotating you toward the camera, prefer LookAt.
	if (Config.RotationMethod or "LookAt") == "AimLock" then
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local cp = cam.CFrame.Position
		local target = aimPos + Vector3.new(0, 1.2, 0)   -- aim at the upper body, not the feet
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

-- viz draw + facing: Connect callbacks also native (docs platform pattern).
-- [V91.1] Viz stays on HEARTBEAT — do NOT move it to RenderStepped. Heartbeat runs AFTER the
-- camera has been updated for the frame, so world→viewport projection matches what u see. On
-- RenderStepped the cam isn't settled yet, so shiftlock / any cam offset makes the whole
-- overlay drift. The only thing kept from the RenderStepped experiment is the cheap gate:
-- when visuals are off we skip the call entirely instead of entering vizUpdate to hide-all.
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
	-- [module] Rescan always: hooking is idempotent (dedup via `hooked`) and the parry
	-- logic stays gated inside AnimationPlayed. This keeps Attack Desync working on your
	-- own animator even while AutoParry is disabled.
	while true do task.wait(3); scanAnimators() end
end)

-- ═════════════════════��═══���═══������═════════��══════���══════════════════════════��
--  LOADER MODULE WRAPPER  (Syllinse Project integration)
--  The loader does: local h = chunk(); if type(h)=="function" then h = h(Lib, Core) end
--  and then calls h.start() and h.buildUI(ctx). Everything above already ran at
--  chunk load (combat connections live but idle: Config.Enabled starts false).
--  buildUI is a closure over all chunk locals above (Config, State, viz colors,
--  styleOf, releaseBlock, vizHideAll, toggleDesyncTest, DesyncTest, statusPush…).
-- ═══════════════════════════════════════════════════════════���═══════════════
return function(_Lib, _Core)
	local M = {}

	function M.start()
		-- Start disabled: nothing acts until the user flips "Enabled" in the UI.
		Config.Enabled     = false
		Config.DesyncAttack = false
		if DesyncTest.on then pcall(toggleDesyncTest) end
	end

	function M.buildUI(ctx)
		local uiReady = false                 -- suppresses notifies during initial element creation
		local function notify(title, body)
			if uiReady then pcall(ctx.notify, title, body) end
		end

		-- ── notify-EXACTLY-ONCE boolean feature (Header + "Enabled" toggle + Keybind) ──
		-- Re-entrancy guard makes the notify fire once regardless of whether MacLib's
		-- UpdateState re-invokes the toggle Callback. The Keybind flips the SAME commit
		-- path, so PC / mobile FAB and the on-screen toggle stay in sync with one notify.
		-- Call this right after the section's Header — the toggle is always named "Enabled".
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
					if guard then return end       -- ignore programmatic UpdateState echo
					commit(v)
				end,
			}, ctx.flag(o.Flag))
			if o.Desc then section:SubLabel({ Text = o.Desc }) end
			-- Unbound keybind (no default key). Works on PC + mobile FAB, persisted.
			-- Named simply "Keybind" per request.
			ctx.keybind(section, {
				Name = "Keybind",
				Flag = ctx.flag(o.Flag .. "_KB"),
				Toggle = function() commit(not o.get()) end,
			})
			return { commit = commit }
		end

		-- Secondary bool toggle (its own label, notifies Enabled/Disabled once).
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

		-- Slider WITHOUT any notify (sliders never notify, per request).
		local function slider(section, o)
			-- [V94] returns the element so callers can drive :SetVisibility on it (style-specific
			-- ring options hide themselves when the chosen style doesn't use them).
			return section:Slider({
				Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
				Precision = o.Precision or 0, Suffix = o.Suffix,
				Callback = o.Callback,
			}, ctx.flag(o.Flag))
		end

		-- ═���══════════════��══ TAB: AutoParry ════════════���═���════
		local AP = ctx.tabs.AutoParry

		-- ── Section 1 — AutoParry core (Left box): Detection + Rotation groups ���─
		local apMain = AP:Section({ Side = "Left" })

		-- Group: master switch + detection
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
		-- [V140] Ребро-триггер серверного доказатель��тва.
		-- [V142] Тумблеры "Strict Proof" и "Track Fakers" удалены вместе со своей логикой (откат
		-- V140/V141): первый резал законные удары, второй не срабатывал. Лишних настроек не держим.
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
		-- [V94] LookAt rotates the character; AimLock only moves the camera and lets the game turn u
		-- (needs shiftlock / cam-follow to actually face them, but looks way less snappy).
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

		-- ── Section 2 — Dodge (Right box): behaviour + tuning + must-dodge ──
		local apDodge = AP:Section({ Side = "Right" })

		apDodge:Header({ Name = "Dodge" })
		-- [V120] МАСТЕР-ту��блер доджа (primary switch секции). OFF = НИ ОДНОГО доджа вообще (все 7
		-- триггеров идут через performDodge → один гейт). Решает «доджит с нихуя»: одним свитчем.
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
			-- В игре есть только M1 и M2 (боевые модули: M1, M2, Grapple, Evasive, Block —
			-- отдельного Skill-каста нет). Поэт��му предлагаем ровно два типа; grab/slam —
			-- это M2 соответствующего стиля (Wrestling/Dirty).
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

		-- ── Section 3 — Skill Addons (Left box): per-style combat behaviours ──
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

		-- [V92] ALI. Рантайм (counterStyle/tryAliEvasiveCounter/steerM2Variant) был реализован ещё
		-- в V91, но без тумблеров Config.AliCounter и Config.AliEvasiveCounter оставались false
		-- навсегда, т.е. весь ко�� был мёртвым. Здесь они выводятся в UI.
		apBox:Divider()
		apBox:Header({ Name = "Ali" })
		boolToggle(apBox, "Ali Counter", "Ali Counter",
			function() return Config.AliCounter end, function(v) Config.AliCounter = v end)
		-- [V139] П��дписи секции Ali убран��: и��ена элементов самодостаточны.
		slider(apBox, { Name = "Ali Counter Range", Flag = "AP_AliCounterReach",
			Default = Config.AliCounterReach or 7.5,
			Min = 3, Max = 14, Precision = 1, Suffix = " studs",
			Callback = function(v) Config.AliCounterReach = v end })
		boolToggle(apBox, "Ali Evasive Counter", "Ali Evasive Counter",
			function() return Config.AliEvasiveCounter end, function(v) Config.AliEvasiveCounter = v end)
		-- [V155/UI] V154 добавил runtime, но не дал пользователю включить Dodge Abuse и настроить
		-- Ali hold через MacLib. Оба элемента флагованы и сохраняются обычной Config System.
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
			-- [V160] Выровнено с новым дефолтом ("Left"): иначе дропдаун показывал "Right",
			-- пока движок работал по "Left" — рассинхрон UI и фактического поведения.
			Default = Config.AliM2Variant or "Left",
			Callback = function(v)
				if type(v) == "string" and v ~= "" then Config.AliM2Variant = v end
			end,
		}, ctx.flag("AP_AliM2Variant"))

		apBox:Divider()
		-- [V139] Секция "Any Style" убрана вместе с Generic i-Frame Counter: контра живёт только
		-- у boxing/ali, под которые откалиброваны реч, вариант и кулдаун. Тумблер
		-- "Counter Instead Of Dodge" общий для обоих стилей, поэтому остаётся отдельной группой.
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

		-- ── Section 3.5 — AutoPlay (Left box): aggressive auto-attack addon ──
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
	-- [V140] Гард перезапуска свинг-анимации (лечит дёрганье при десинке/anti-autoparry).
	boolToggle(apPlay, "Smooth Swings", "Smooth Swings",
		function() return Config.AP_AnimGuard ~= false end,
		function(v) Config.AP_AnimGuard = v end)
	apPlay:SubLabel({ Text = "stops the swing anim restarting mid-play when the server desyncs" })
	boolToggle(apPlay, "Counter Interrupt", "Counter Interrupt",
		function() return Config.AP_Interrupt ~= false end, function(v) Config.AP_Interrupt = v end)
	apPlay:SubLabel({ Text = "if ur next hit lands first and enemy is in reach → hit now instead of parrying" })
	-- [V139] M2 как второй инструмент interrupt.
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

	-- ── Section 4 — Visuals (Right box): ESP / overlay ──
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

		-- [V94] Ring options are grouped and the style-specific ones HIDE unless that style is
		-- picked, so the panel doesn't show u knobs that currently do nothing.
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

		-- ═══════════════════ TAB: Desync ══════════════════��
		local DS = ctx.tabs.Desync

		-- Section 1 — Desync (standalone attack-replicate spoof, the old "[" test).
		-- Fully independent of AutoParry and of Attack Desync.
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

		-- Section 2 — Attack Desync (delay/idlemask/prerun engine, the old "J").
		-- Works on your swings even with AutoParry OFF.
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

		-- Section 3 — Invisible.
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

		-- ═══════════════════ TAB: Debug ══════════════���═���══
		local DB = ctx.tabs.Debug

		-- Section 1 — Status Log (live, newest-first, formatted)
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
		-- Light auto-refresh so the log actually feels live.
		task.spawn(function()
			while statusPara do
				task.wait(1.5)
				pcall(renderStatus)
			end
		end)

		-- Section 2 — Diagnostics (Save AutoParry diag + Copy)
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
					pcall(setclipboard, body)      -- Copy toggle: full log text → clipboard
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

		-- Everything built; allow notifies now (initial element Callbacks are done).
		task.defer(function() uiReady = true end)
	end

	return M
end
