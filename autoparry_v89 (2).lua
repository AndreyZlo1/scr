local Config = {
	Enabled       = false,  -- [module] start OFF; user flips the "Enabled" toggle/keybind in the UI
	Mode          = "Perfect",

	Range         = 36,    -- [V105] +4 (юзер: враг выходит за радиус и заходит → миссим; чуть шире)
	RequireFacing = false,
	IncludeNPCs   = true,
	HeavyEnabled  = true,

	M1Forward     = 4,
	M2Forward     = 3,
	HitboxDepth   = 4.0,
	HitboxDepthBack = 1.0,
	HitHalfWidth  = 3.0,
	HitboxSlack   = 0.5,
	FilterFailSafe= true,

	-- [V67] БЛИЖНИЙ-БОЙ ДОВЕРИЕ. Первопричина регресса 1v1 (58% против 87% у V64):
	-- willHitMe — жёсткий гейт для нажатия. В упор (dist 2-6) враг стрейфит во
	-- время комбо → predA улетает вбок, flatLook не на нас, конус не дотягивает →
	-- willHitMe=false → NO-PRESS, хотя удар прилетает (LATE). В логе 651000 ровно
	-- это: c1 PERFECT, c2/c3/c4 LATE NO-PRESS + "MISS! never-in-hitbox". Плюс когда
	-- willHitMe=false, faceTgt НЕ обновляется → перестаём поворачиваться → спираль.
	-- Фикс: в пределах HitTrustRange активный свинг ДОВЕРЯЕМ (хитбокс игры щедрый,
	-- сервер доворачивает атакующего сам). Строгий прямоугольник остаётся для
	-- дальней дистанции (различать удар по нам vs по союзнику в мультибое).
	HitTrustRange = 7.0,
	-- [V67] кап на velocity-экстраполяцию predA: у стрейфящего врага aV*tHit за
	-- ~0.35с даёт 5+ студов смещения и уводит центр хитбокса. Ограничиваем.
	WillHitVelCap = 2.0,
	-- [V91] РАЗДЕЛЬНЫЙ кап предикта predA. Раньше единый WillHitVelCap душил и сближение,
	-- и strafe → лунж/наскок с dist=10+ отсекался как «far» (High-миссы never-in-hitbox).
	-- Теперь: сближение (toward us) ведём щедрее (реальный наскок закрывает дистанцию),
	-- боковую (strafe) компоненту жёстко капим (иначе центр бокса уезжает вбок).
	WillHitCloseCap = 6.5,  -- [V102] студы: макс. предикт в сторону сближения (выше — ловим вбегающих)
	WillHitLatCap   = 1.5,  -- студы: макс. предикт боковой (strafe) составляющей

	-- [V68] ДВА РЕЖИМА ТОЧНОСТИ (переключение клавишей B).
	-- Low  = как в V67: щедрое доверие ближнему бою, НО с отбраковкой ударов,
	--        которые явно направлены НЕ в нас (враг лицом в другую сторону на
	--        предсказанной ротации) — чтобы не агриться на чужие атаки в мясорубке.
	-- High = точная модель: строим хитбокс по ПРЕДСКАЗАННОЙ ротации атакующего на
	--        момент контакта (атака привязана к HRP-yaw) и проверяем, попадаем ли мы
	--        в него. Ловит байты/финты: враг доворачивается к нам в последний момент
	--        = угроза; отворачивается = не угроза. Без слепого close-range доверия.
	AccuracyMode  = "Low",
	PointBlank    = 3.0,    -- Low: ≤ этой дист. всегда считаем удар нашим (в упор не отвертеться)
	LowFaceMin    = -0.55,  -- Low: бракуем удар, только если predFacing·toMe < этого (шире конус ~123°: реагируем на большее, отсекаем только явно спиной)
	RotPredMaxDeg = 200,    -- [V88] кап предсказанного доворота за свинг (Low: широкий, ловит 180° финты)
	-- [V92] В HIGH кап доворота ЖЁСТКИЙ. При 200° предсказанный facing разворачивался на
	-- ПОЛ-ОБОРОТА → враг, стоящий СПИНОЙ, «предсказанно смотрел на нас» → High парировал
	-- атаки, которые физически не в нас (жалоба игрока). 55° = реальный доворот за свинг,
	-- спиной-стоящий (rawDot<0) уже не долетает предиктом до нас.
	RotPredMaxDegHigh = 55,
	HighSlack     = 0.35,   -- [V90.5] High: базовый слак бокса, студы (статичный бой — узко, мало ложняков)
	-- [V105] ДВИЖ-СЛАК: юзер — «стоя пиздимся идеально, а когда враг двигается/крутится, скрипт
	-- иногда опаздывает; когда выходит за радиус и заходит — миссаем». На нашем экране движущийся
	-- враг отрисован в прошлом (интерп-лаг + пинг), а сервер держит его позицию ВПЕРЕДИ → предсказанный
	-- бокс уезжает мимо. Добавляем к слаку High-бокса вклад ОТНОСИТЕЛЬНОЙ планарной скорости
	-- (враг + мы), пропорционально, с капом. Стоим оба (speed≈0) → слак = базовый → строгий кейс не
	-- трогаем и ложняков не добавляем; кто-то движется → бокс шире ровно настолько, насколько велик
	-- рассинхрон позиции.
	HighMoveSlackK   = 0.045,  -- студ слака на 1 студ/с относительной скорости
	HighMoveSlackCap = 2.2,    -- макс. добавка слака от движения (студы)
	HeavyHighFaceMin = 0.5, -- [V90.5] High: тяжёлый лунж доверяем, только если нацелен в нас (~60° конус)
	-- [V92] High back-facing гейт: враг сейчас смотрит от нас сильнее HighBackDot И предсказанный
	-- facing не наводится сильнее HighFaceMin → физически не может ударить → сразу reject.
	HighBackDot   = -0.15,  -- rawDot ниже этого = смотрит от нас
	HighFaceMin   = 0.25,   -- предсказанный facing·toMe должен превысить это, иначе не угроза
	-- [V90.4] High = чисто геометрический dual-box (predLook + rawL), без radius/facing-доверия
	-- (см. willHitMe). Никаких HighFaceMin/HighReachPad больше нет — они и делали High как Low.
	-- [V90] DRAG/SNAP-TURN детект (закрученные атаки: враг смотрит мимо, бьёт, резко
	-- доворачивается к нам). Ловим по ЗНАКУ доворота (facing приближается к нам между
	-- кадрами), а не по мгновенной angY (шумной). Работает и в High, и в Low.
	DragDetect    = true,
	DragTurnMinDeg= 35,     -- град/с: доворот выше этого + приближение facing к нам = drag-угроза
	DragTrustRange= 13,     -- радиус (студы), где drag-довороту даём доверие
	Key_Accuracy  = Enum.KeyCode.B,

	-- [V89] HEAVY-ПРИОРИТЕТ. Тяжёлые (M2) и скиллы — выпады, атакующий закрывает дистанцию в
	-- замахе, а velCap=2.0 обрезал predA → geom-бокс отбраковывал их как "never-in-hitbox"
	-- (в диаг ровно так пропала Capoeira M2 → Ragdoll-каскад → провал мультибоя). Тяжёлый в
	-- расширенном радиусе, если смотрит ~на нас ИЛИ реально сближается, считаем угрозой сразу.
		HeavyTrust       = true,
		HeavyTrustRange  = 14,     -- радиус (студы), в котором тяжёлым/скиллам даём безусловное доверие
		HeavyFaceMin     = -0.30,  -- бракуем тяжёлый, только если predFacing·toMe < этого И он не сближается
		HeavyClosingMin  = 6,      -- скорость сближения (студ/с) выше этой = выпад на нас, доверяем даже спиной
		-- [V101] ДЛИННЫЙ ВЫПАД (ло��: digmyswaga M2(MuayThai) dist=26 → never-in-hitbox MISS). Стили
		-- вроде MuayThai/Karate имеют M2 с длинным дэшем (M2HitboxDelay 0.6с), закрывающим 20+ студов
		-- в замахе. Обычный HeavyTrustRange(14) отсекал их по дистанции → скрипт не ре����������гировал.
		-- Ловим ДВУМЯ путя��и: (1) реальный дэш на нас (сильное сближение по velocity ИЛИ по дельте
		-- позиции — второе ловит CFrame-твин-дэши, где velocity=0), доверяем до HeavyLungeRange
		-- независимо от текущей дистанции; (2) на средней дистанции (heavyRange..HeavyFaceRange) —
		-- если тяжёлый РЕАЛЬНО нацелен в нас узким ��онусом (HeavyFarFaceMin). Далёкий стоячий M2,
		-- смотрящий мимо и не идущий на нас, по-прежнему НЕ парируется (нет ложняка).
		HeavyLungeRange   = 36,     -- макс. дистанция, с которой доверяем реально дэшущему выпаду
		HeavyLungeClosing = 14,     -- скорость сближения (студ/с), выше которой это точно дэш на нас
		HeavyFaceRange    = 30,     -- расширенный радиус facing-доверия для тяжёлых
		HeavyFarFaceMin   = 0.85,   -- на средней дистанции доверяем, только если нацелен ТОЧНО в нас (~32° конус)
		-- [V101] BROADPHASE для High: дешёвый ранний отказ явно недосягаемым/неприближающимся
		-- угрозам ДО дорогого предикта ротации/GetPartBoundsInBox. В разы разгружает scheduler в
		-- мультибое (парри перестают опаздывать из-за CPU), при этом реально долетающие
		-- (сближающиеся/лунж) проходят дальше — точность High не страдает.
		HighBroadRange    = 28,     -- [V105] за этим радиусом + враг НЕ приближается → мгновенный reject
		                            -- (24→28: враг, вышедший за радиус и снова зашедший, больше не режется рано)

	-- [V70] residual-калибратор УДАЛЁН. Предикт чисто математический. resAvg в
	-- логе остаётся только как диагностика точности, в hitTL не подаётся.
	TurnWindow    = true,
	TurnBaseDeg   = 42,
	TurnCloseDeg  = 90,
	CloseRangePad = 5,
	TurnWindowMax = 150,
	TurnFloor     = 0.05,
	TurnAngVelK   = 1.0,

	FeintFrac     = 0.80,
	FeintGraceMs  = 90,

	ComboEscape        = true,
	ComboEscapeDodge   = true,
	-- [V97] Мастер-тумблер доджа «когда parry невозможен» (блок в кулдауне/стан). OFF = скрипт
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
	-- → двойной учёт задержки. Физика: локальный атрибут PerfectBlocking истинен на нашем клиенте
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
	-- на КАЖДЫЙ удар в его перфект-окне, даже если уже блокируем.
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
	ChargeStallMs = 45,
	ReleaseGap    = 0.40,

	-- [V103] FACE-GATE BLOCK: не жечь нажатие блока (и 0.5с BlockCooldown), пока смотрим спиной к
	-- атакующему — блок направленный, сервер такой парри отклонит. Ждём доворота (applyFacing),
	-- прессим при приемлемом facing ИЛИ когда времени уже нет (последний шанс). Дефолт ON.
	FaceGateBlock = true,
	FaceGateMin   = 0.2,       -- мин. faceDot (cos) до атакующего, при котором разрешаем нажатие

	-- [V93] ПОЛНЫЙ round-trip. Локальный атрибут PerfectBlocking СЕРВЕРНЫЙ: после нашего нажатия
	-- он проходит нажатие→сервер (RTT/2) и реплик. атрибута назад (RTT/2) = ПОЛНЫЙ RTT, и лишь
	-- тогда становится true на нашем клиенте. VictimHitConfirm (дамп VictimHitboxServiceClient)
	-- читает ИМЕННО этот локальный атрибут в момент оверлапа хитбокса → чтобы к контакту он был
	-- true, жать надо на полный RTT раньше. Прежний 0.5 (полу-RTT) недокомпенсировал ровно на
	-- пол-пинга → на 195мс пинге блок стабильно опаздывал (диаг: PERFECT@~185мс vs LATE@~95мс,
	-- разрыв ≈ полу-RTT).
	UplinkFactor  = 1.0,
	UplinkMargin  = 0.008,
	UplinkMin     = 0.010,
	-- [V94] Подняты капы: диаг2 показал реальный RTT=345ms, а прежние UplinkMax=0.33/PingCap=0.32
	-- САМИ резали компенсацию до ~330ms → на высоком пинге блок недокомпенсировался даже с верным
	-- getPingRaw. Теперь тянем до 0.5с. На умеренном пинге (60–150) это ни на что не влияет (там
	-- клампы не достигаются), а на 300–450ms пинге даёт полный round-trip lead.
	UplinkMax     = 0.500,
	PingSmooth    = 0.25,
	PingCap       = 0.500,
	-- [V96] МЯГКИЙ peak-hold. Было 1.5с — держал случайный спайк как «пол» лишние ~секунды и
	-- завышал lead (в логе ping латчил 180 при среднем ~120). Теперь короткий hold + частичный
	-- вес пика (PingPeakWeight), чтобы спайк не уходил в lead целиком. Сглаживает без залипания.
	PingPeakHold  = 0.4,
	PingPeakWeight = 0.5,   -- сколько от (пик−EMA) добавлять к эффекти��н��м�� RTT (0=только EMA, 1=весь пик)

	MoveLeadMax   = 0.045,
	MoveSpeedFull = 22,

	MaxWait       = 1.6,

	MinActGap     = 0.030,
	MinDeactGap   = 0.050,

	MatchWindow   = 1.30,

	DodgeHeavy    = true,
	FOV           = 360,   -- screen-space angular FOV; 360 preserves current omnidirectional behavior

	-- [V89] MUST-DODGE (неблокируемые). В дампе нет флага Unblockable — всё в теории
	-- блокируется, поэтому список собираем производно по стилю/типу. Сквозь атрибут Blocking
	-- реально проходят только грэбы/слэмы. Ключ таблицы = стиль (lower), значение = {[kind]=true}
	-- или {all=true}. Для таких угроз скрипт доджит НАЗАД в i-frame ок��������������������������������о вместо бесполезного
	-- блока. Расширяется без правки кода: допиши сюда стиль/тип, который пробивает твой блок.
	MustDodge       = true,
	MustDodgeStyles = {
		wrestling = { M2 = true },  -- Wrestling M2 = гарантированный захват (M2GrabTargetForwardOffset), блок не спасает
	},

	IFrameDur     = 0.30,
	DodgeLead     = 0.10,
	UseServerCooldown = true,
	DodgeCooldown = 2.05,
	DodgeMinSpacing = 0.35,
	OutnumberEscape = true,
	ExposedEscapeDodge = true,
	ExposedDodgeWindow = 0.28,
	DashSpeed     = 30,
	MaxHeightDiff = 12,   -- [module] ignore attackers whose Y differs by more than this (different floor/level)
	DashDuration  = 0.20,
	DodgeConfirm  = 0.18,
	DodgeCenter   = true,
	HeavyDodgeInset = 0.075,
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
	-- (hitTL - tp) / max(liveSpeed, floor). При замедлении окно едет с ударом.
	LiveHeavyTimer    = true,
	LiveSpeedFloor    = 0.15,   -- ниже этой доли номинала скорость не считаем (антидел/0)
	LiveSpeedSmooth   = 0.35,   -- EMA-сглаживание измеренной скорости прогресса
	LiveM1Timer       = true,   -- [V96] live-TP коррекция и для M1 (лечит скачки predErr на M1)
	LiveM1SpeedFloor  = 0.45,   -- пол скорости для M1 выше (короткий трек → агрессивнее гасим шум)

	-- [V66] ЭКСТРЕННЫЙ ДОДЖ двух угроз. Если 2-й контакт прилетает раньше, чем мы
	-- физически успеваем развернуться к нему + перевзвести перфект, блок 2-го
	-- невозможен → доджим оба ���разу (iframes покрывают обоих). Порог = реальное
	-- время разв��рота (по угловой скорости) + запас на перевзвод.
	EmergencyDualDodge = true,
	TurnRateDegPerSec  = 720,   -- насколько быстро HRP реально доворачивается снапом
	RearmBudget        = 0.06,  -- запас на свежий Activated (сервер + throttle)
	DualDodgeMaxGap     = 0.22, -- 2-й удар в пределах этого от 1-го = кандидат на dual

	-- [V66] расширенная диагностика NO-PRESS/held-heavy (для точного разбора причин)
	DeepDiag           = true,

	BoxingCounter     = false,
	BoxingCounterReach= 8,
	BoxingCounterLead = 0.16,
	BoxingCounterMinGap = 0.45,

	-- Skill Addons: per-style combat behaviors that plug into the parry brain.
	-- Each maps to a REAL mechanic found in CombatConfig, not a placeholder.
	SkillAddon        = true,
	SA_WrestlingGrab  = true,   -- enemy Wrestling M2 = unblockable grab (M2GrantsHyperArmor) → force dodge
	SA_DirtyGrab      = true,   -- enemy Dirty grab/M2 (GrappleDirtyHit, ImmuneToRagdollM2) → force dodge
	SA_HakariRead     = true,   -- widen window for Hakari momentum M2 (HakariMomentumM2HitboxDelay 0.62)
	SA_HakariWiden    = 0.05,   -- extra front/hold seconds applied to a Hakari M2
	-- [V91] BLATANT force-dodge. Игра НЕ даёт додж, когда мы застряли в собственной атаке
	-- (self-busy) или в софт-стане (Stunned/CantAnything) — из-за этого «атаковал не вовремя →
	-- съел удар». Этот аддон ОВЕРРАЙДИТ блокировку: если удар вот-вот прилетит, а мы залочены
	-- софт-��остоянием и не можем блокнуть — форсим сам dodge-инпут (сервер его примет).
	-- Жёсткие состояния (Ragdoll/Grabbed/Downed) НЕ обходим — там дэш физически ничего не даёт.
	-- Blatant = палевно (легит-игрок не смог бы), поэтому по умолчанию ВЫКЛ.
	SA_BlatantDodge   = false,
	SA_BlatantWindow  = 0.32,   -- сек до контакта: в этом окне срабатывает форс-додж

	-- [V97] AutoPlay addon — автоатака. По умолчанию ВЫКЛ (агрессивное поведение).
	AutoPlay          = false,  -- мастер-тумблер аддона
	AP_PunishOnParry  = true,   -- добивать M1 застаненного врага после идеального парри
	AP_InterruptHeavy = true,   -- перебивать одиночную тяжёлую своим M1 (когда успеваем)
	AP_BaseReach      = 5.5,    -- базовый реч нашего M1 (ForwardOffset 4 + запас), студы
	AP_RefHeight      = 5.5,    -- эталон высоты модели для масштаба реча по росту
	AP_M1Delay        = 0.32,   -- CombatConfig M1.DefaultHitboxDelay (долёт нашего M1)
	-- [V104] INTERRUPT тяжёлых. CUSTOM-FIRE шлёт ServerCheck мгновенно → сервер строит хитбокс в
	-- момент приёма, поэтому «долёт» нашего M1 = только серверная обработка (proc, мал). M2HitboxDelay
	-- врага 0.43..0.82с (�� разы больше окна парри) и удар перебиваем почти всю фазу → HeavyActiveGrace.
	AP_InterruptM1Delay = 0.05,  -- серверная обработка нашего мгновенного ServerCheck (сек)
	AP_HeavyActiveGrace = 0.14,  -- насколько долго тяжёлая ещё перебиваема ПОСЛЕ номинального контакта
	-- [V105] перехват тяжёлой РАЗРЕШЁН и в мультибое, если следующая ДРУГАЯ угроза придёт не раньше,
	-- чем через это время (успеем сбить тяжёлую и снова поднять guard). 0 = только одиночная угроза.
	AP_InterruptMultiClear = 0.28,
	AP_M2Stun         = 1.0,    -- CombatConfig ParryStun.M2 (стан после M2-парри)
	AP_M1Stun         = 0.5,    -- оценка стана после M1-парри (RecoveryLockout врага)
	AP_PollGap        = 0,      -- [V101] троттл поллинга tryM1 = 0 (пробуем КАЖДЫЙ кадр; настоящий
	                            -- рейт держит игровая tryM1 по AttackDuration 0.45с). Максимальная
	                            -- скорость реакции: как только сервер снимает parry-lockout 0.15с — бьём.
	AP_FaceHold       = 0.35,   -- сколько держать лицо на цели после выстрела M1
	AP_InterruptMargin= 0.05,   -- (legacy) запас времени для решения «успеем перебить»
	AP_InterruptPingFactor = 1.0, -- [V104] доля RTT в честной модели: наш пакет летит up, их атаку мы
	                            -- видим на up позже → в оценку входит полный RTT. Агрессивность даёт не
	                            -- урезание пинга, а HeavyActiveGrace (долгая перебиваемая фаза тяжёлой).
	-- [V101] Комбо-контроль AutoPlay. "Follow" (дефолт) — родная tryM1 сама циклит ��дары комбо
	-- 1→2→3→4→1 (u19 = u19%4+1). "Fixed" — форсим один и тот же удар комбо (AP_FixedHit) через
	-- debug.setupvalue(u19) прямо перед свингом. Полезно для стабильного стартового удара.
	AP_ComboMode      = "Follow",  -- "Follow" | "Fixed"
	AP_FixedHit       = 1,          -- 1..4 — какой удар комбо бить в режиме Fixed
	-- [V105] СВОЙ M1-БИЛДЕР ВСЕГДА (fireM1Custom): обходит игровой 450мс-троттл (u21) и клиентские
	-- локи (u32/u33), шлёт ServerCheck сам. Единственный потолок — CombatRemoteClient.Fire
	-- (80мс burst / ~4-в-сек). Тумблеров Turbo/Fast больше нет — это база, всегда включено.

	-- [V98] реагировать только когда руки одеты (Equip==true). Иначе сервер всё равно
	-- откажет и в блоке, и в атаке (Block.lua/M1.lua требуют Equip). Кросс-платформенно.
	RequireEquip      = true,

	-- [V98] Blatant TEST режим: на каждую входящую угрозу шлём блок И RAW M1 (ServerCheck)
	-- ОДНОВРЕМЕННО, без анимации. Для проверки реакции/приёма сервером. Палевно → по умолч. ВЫКЛ.
	Blatant           = false,
	BlatantWindow     = 0.30,   -- сек до контакта, в котором Blatant отрабатывает

	RestrictZone      = true,
	RestrictLongOnly  = true,
	RestrictMinWindup = 0.30,
	RestrictPad       = 2.0,
	RestrictSoft      = true,
	RestrictShowZone  = true,


	SelfBusyDur     = 0.45,

	DesyncAttack   = false,
	-- [V88] Режимы desync (цикл клавишей ]):
	--   delay     — визуал твоего замаха задержан на DesyncDelayMs; FireServer уходит вовремя.
	--   firedelay — визуал идёт ��овремя; только M1/M2 ServerCheck уходит позже на DesyncDelayMs.
	--   idlemask  — постоянный спуф IDLE, пока ты атакуешь.
	--   prerun    — фейк-атака (как [) СРАЗУ + реальный FireServer задержан на DesyncDelayMs.
	DesyncMode     = "delay",
	DesyncDelayMs  = 140,          -- единая задержка delay/firedelay/prerun (мс)
	DesyncDecoyId  = 507766388,
	DesyncApplyM1  = true,
	DesyncApplyM2  = true,
	-- [V83] анти-decoy: игнорить неестественно быстрые повторы атак от одного врага
	-- (флуд decoy/фейк-атак вроде наших prerun/idlemask), чтобы не сбивали ��аш парри.
	AntiDecoy      = true,
	AntiDecoyGap   = 0.12,       -- мин. интервал между настоящими свингами одного врага (сек)
	DesyncClientVisible = false,  -- [V72] false → decoy тебе невидим, локально чистая реальная атака
	DesyncSendHz      = 0,        -- Anti-AutoParry decoy re-sends per second; 0 = auto (track length)
	-- Invisible desync: реплицируем контортнутый/опущенный корень на сервер (другие тебя не видят),
	-- локально каждый RenderStep возвращаем на место (ты видишь себя ��ормально).
	InvisibleOn    = false,
	InvisibleHeight= 0,           -- ДОП. студы поверх базового з��хо������онения (кастом высота); 0 = базовое
	InvisibleAnim  = true,        -- дополнительная контортящая ани��ация для лучшего скрытия
	-- [V74] raknet-скан теперь СЕССИОННЫЙ и запускается только вручную:
	-- getgenv().AP_RAKNET_SCAN() — ставит send-hook на DesyncScanSecs секунд и снимает.
	-- НЕ активен при загрузке (в этом была причина фриза V73).
	DesyncScanSecs = 5,
	DesyncRaknetWindowMs = 220,
	-- [V74] self-verify: подписка на свой Animator.AnimationPlayed.
	-- ВЫКЛ по умолчанию — забивал диаг с��ро��ами [VERIFY]/[DESYNC-VERIFY] на каждый трек.
	DesyncSelfVerify = false,

	BoxingFaceLockDur = 0.55,
	-- [V89] за сколько до контакта начинать ЖЁСТКО смотреть на врага при boxing-counter
	-- (раньше взгляд включался лишь за BoxingCounterLead=160мс → «лишь доворачивал��). 0.5с =
	-- требуемое «смотреть 0.5 секунд на врага» перед тяжёлой контратак��й вместо доджа.
	BoxingPreFace     = 0.5,
	-- [V63] DEPRECATED. Velocity-lead прицел оказался ВРЕДНЫМ: на близкой дистанции
	-- экстраполяция разво��ачивала HRP вбок (в логах face=0.51 BACK!) �� counter уходил
	-- ��имо. Boxing-M2 хитбокс серверный и строится по нашему ТЕКУЩЕМУ LookVector, так
	-- что нужен прямой снап на врага (см. sendBoxingCounter/enforceFaceLock). Поле
	-- оставлено = 0 для обратной совместимости; НЕ используется в прицеливании.
	BoxingAimLead     = 0,
	-- [V62] boxing-counter только когда угроза одиночная. В burst (2+ атакующих)
	-- counter роняет guard + делает return → остальные проходят без блока.
	BoxingCounterSolo = true,

	-- [V62] ГИБРИД мульти��оя: перфектим ближайшего, остальным держим guard
	-- непрерывно (нулевые дыры = нулевые полные ������иты). holdUntil тянется по
	-- самому дальнему угрожающему контакту в кластере, guard не отпускается
	-- в середине burst, re-press в BlockCooldown исключён.
	MultiThreatGuard  = true,
	MultiThreatMinN   = 2,      -- со скольких одновременных угроз включать held-режим
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

	ServerSwingHook   = true,
	ServerSwingDedup  = 0.35,

	-- [V90.2] Мульт��таргет: мгновенный (hard) снап лицом к следующему атакующему, когда в
	-- замесе 2+ угрозы — без плавного лерпа, чтобы не терять кадры на перекладку между целями.
	MultiFaceHard     = true,

	DodgeHorizon      = 0.34,
	MinBlockSeparation= 0.17,
	DodgeArmWindow    = 0.05,

	LegitAnims    = true,

	AutoFace      = true,
	FaceLerp      = 0.80,   -- [V70] быстрее трекинг между атакующими в замесе
	FaceLeadWindow= 0.30,
	FaceGoodDot   = 0.55,
	-- [V91] ПРЕДИКТ РОТАЦИИ автофейса: целимся чуть НАПЕРЁД движения врага (ведём его
	-- позицию по скорости на FaceLead сек), чтобы facing не отставал от стрейфа/забегания
	-- за спину. Держим предикт малым (иначе перелёт при резкой смене направления).
	FaceLead      = 0.07,   -- сек упреждения по скорости врага
	FaceLeadMax   = 4,      -- студы: кап упрежде��ия
	-- [V97] PING-SCALED предикт facing (applyFacing). ��преждение = vel * (ping * FacePingLead),
	-- т.к. рассинхрон позиции врага прямо пропорционален латентности. FaceLeadCap — верхний предел
	-- по времени (сек), FaceLeadMaxStuds — по расстоянию (антиперелёт при рывке).
	FacePingLead  = 1.0,
	FaceLeadCap   = 0.22,
	FaceLeadMaxStuds = 7,

	-- [V69] БЛОК НЕНАПРАВЛЕННЫЙ (доказано дампом: attacker M1 проверяет только
	-- атрибут Blocking жертвы; Block-модуль — только PerfectBlocking; VictimHitbox —
	-- лишь попадание в бокс. НИГДЕ нет dot/LookVector/угла на стороне жертвы). Значит
	-- один guard прикрывает всех атакующих со всех сторон, и доворачиваться к врагу
	-- РАДИ БЛОКА не нужно. Из этого:
	--  1) мультитаргет: одно нажатие покрывает всех в окне — не теряем "перебитых EDF";
	--  2) поворот: делаем дешёвый ЧАСТИЧНЫЙ доворот к центроиду угроз (не жёсткий снап
	--     к одному), что экономит CPU и не дёргает камеру;
	--  3) dual-dodge "не успеем развернуться ко 2-му" больше не нужен — держим guard
	--     на обоих. Додж только когда блок реально недоступен (стан/кд/гардбрейк).
	-- OmniBlock оставлен: даёт мультитаргет-покрытие одним guard'ом и гейт dual-dodge.
	-- SoftFace удалён в V70 — вернули быстрый жёсткий снап.
	OmniBlock      = true,

	ShowVisuals   = true,   -- мастер-переключатель всех визуалов AutoParry
	-- [V90] Настраиваемые визуалы. Каждый элемент можно включить/выключить отдельно, а у
	-- вращающегося кольца настраиваются скорость анимации, размер и дальность прорисовки.
	VizRing       = true,   -- ��ращающееся кольцо под целью
	VizHitbox     = true,   -- бокс хитбокса цели
	VizRestrict   = true,   -- зона ограничения (keep-out)
	VizRingSpeed  = 1.0,    -- множитель скорости анимации кольца (0.1–3.0)
	VizRingScale  = 1.0,    -- множитель радиуса кольца (0.4–2.5)
	VizRange      = 100,    -- дальность (студы), на которой ищется/рисуется цель
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
	Key_DesyncSave = Enum.KeyCode.Semicolon,     -- [V75] ; → сохр��нить desync-дебаг в файл
	Key_DesyncScan = Enum.KeyCode.Quote,         -- [V75] ' → запустить raknet скан-сессию
	Key_DesyncTest = Enum.KeyCode.LeftBracket,   -- [V76] [ → тест-режим: постоянно реплицировать АТАКУ пока стоишь
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
}

local LEGACY_M1_OFFSETS = {
	basic    = {0.02, 0.02, 0.02, 0.02},
	boxing   = {0.02, 0.02, 0.02, 0.06},
	hakari   = {0.16, 0.18, 0.16, 0.21},
	hakario  = {0.16, 0.18, 0.16, 0.21},
	karate   = {0.0375, 0.075, 0.15, 0.225},
	capoeira = {0.02, 0.1, 0.02, -0.05},
	slugger  = {0.3, 0.25, 0.25, 0.17},
}
local LEGACY_M1_BASE = { karate=0.24, muaythai=0.30, slugger=0.20, capoeira=0.33 }
local LEGACY_M2_BASE = { boxing=0.43, capoeira=0.45, hakari=0.59, hakario=0.62, karate=0.4875,
                         muaythai=0.60, slugger=0.82, wrestling=0.525, basic=0.525 }
local WINDUP_EXTRA = 0.012
local COMBO_RESET  = 1.55

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local Stats             = game:GetService("Stats")

local LocalPlayer  = Players.LocalPlayer
local ServerRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server")

local State = {
	blocking     = false,
	guardUp      = false,   -- ИСТИННОЕ серверное состояние guard: true когда серверу отправлен
	                        -- Activated и ещё не отправлен Deactivated. Отдельно от blocking
	                        -- (внутреннее намерение), чтобы гарантированно снимать guard даже
	                        -- если blocking сброшен в обход releaseBlock (dodge/counter/outcome).
	holdUntil    = 0,
	status       = "ARMED",
	lastThreat   = nil,
	parryCount   = 0,
	dodgeCount   = 0,
	grantEscapes = 0,
	selfBusyUntil= 0,
	kicksBlocked   = 0,
	reportsBlocked = 0,
	acMuted        = 0,
	acScript       = nil,
	desyncFires    = 0,
	fireCount    = 0,
	lastDodge    = -99,
	lastDodgeInfo   = nil,
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
	-- AutoRotate/шифтлок) — они дрались, отсюда залипание на одной цели и дёрганье. Теперь schedulerStep
	-- лишь ВЫСТАВЛЯЕТ цель сюда, а применяет ОДИН аппликатор applyFacing в RenderStepped (последний
	-- писатель кадра, гасит AutoRotate). faceGoalHRP=на кого смотреть, Hard=жёсткий снап vs лерп,
	-- Until=до какого времени держать (грейс после последней выставки), Hum=кэш Humanoid для AutoRotate.
	faceGoalHRP   = nil,
	faceGoalHard  = false,
	faceGoalUntil = 0,
	faceHum       = nil,
}

local Threats = {}

local FaceByResult = {}
local ResidByKS    = {}
local ComboState = {}
local Pending = {}

local DiagLog, DIAG_MAX = {}, 4000
local function diagPush(line)
	DiagLog[#DiagLog+1] = line
	if #DiagLog > DIAG_MAX then table.remove(DiagLog, 1) end
end

-- [V75] отдельный буфер desync-дебага (сохраняется в свой файл, чтобы слать мне).
local DesyncLog, DESYNC_MAX = {}, 3000
local function desyncPush(line)
	local stamped = ("t=%.2f  %s"):format(os.clock(), line)
	DesyncLog[#DesyncLog+1] = stamped
	if #DesyncLog > DESYNC_MAX then table.remove(DesyncLog, 1) end
end
-- [V89/module] Status ring-buffer. Replaces console `print`: every status/AC line is
-- pushed here and surfaced live in the loader's Debug tab (no console spam).
local StatusLog, STATUS_MAX = {}, 200
local function statusPush(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local line = table.concat(parts, " ")
	StatusLog[#StatusLog + 1] = line
	if #StatusLog > STATUS_MAX then table.remove(StatusLog, 1) end
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
-- ~68ms вместо реальных 111–345ms → блок стабильно опаздывал (LATE) на любом заметном пинге.
-- Фикс: первичный источник — LocalPlayer:GetNetworkPing() (метод самого инстанса игрока,
-- доступен в ЛЮБОМ контексте, не бросает; возвращает one-way в секундах → RTT = ×2). Stats
-- Data Ping (уже RTT в мс) — как второй источник; берём МАКСИМУМ (перекомпенсация безопаснее
-- недокомпенсации для парри). Если оба недоступны — отдаём последнее валидное значение, а НЕ
-- хардкод 60. Итог: и hot-path, и header видят один настоящий RTT.
local _lastGoodPing = 0.08
local function getPingRaw()
	local best

	-- Источник A: Player:GetNetworkPing() — one-way (сек). RTT ≈ ��2.
	local okA, oneWay = pcall(function() return LocalPlayer:GetNetworkPing() end)
	if okA and type(oneWay) == "number" and oneWay > 0 then
		best = oneWay * 2
	end

	-- Источник B: Stats Data Ping — RTT в мс. Берём максимум с A.
	local okB, ms = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if okB and type(ms) == "number" and ms > 1 then
		local rtt = ms / 1000
		if not best or rtt > best then best = rtt end
	end

	if best and best > 0 then
		_lastGoodPing = math.clamp(best, 0.005, 1.5)
	end
	return _lastGoodPing
end

-- [V93] Единый неймспейс-таблица для ВСЕГО нового состояния (пинг-пик + ground-truth хитбоксы).
-- ВАЖНО: модуль целиком — одна гигантская функция, а в Luau лимит 200 жи��ых локалов на функцию.
-- Оригинал был впритык к лимиту, поэтому каждое новое состояние держим полями ОДНОЙ таблицы
-- (=1 локал), а не десятком отдельных local — иначе CompileError "Out of local registers".
local V93 = {
	pingEMA = 0.08,
	-- peak-hold: держим недавний ПИК RTT, т.к. Data Ping пилообразно прос��дает (в диаг видели
	-- ping=60 при реальных ~195) и на провале мы бы недокомпенсировали → LATE-блок.
	pingPeak = 0.08,
	pingPeakAt = 0,
	-- ground-truth хитбоксы:
	hbFolder = nil,
	sizes = {},                        -- ["M1"]/["M2"] → Vector3 реального размера парта
	hbParams = nil,                    -- OverlapParams (лениво)
	hbChar = nil,
	hbFrame = -1,
	byOwner = {},                      -- Owner.Value → { part, ... } за текущий FrameId
}

-- [V96] Пинг = сглаженный RTT с МЯГКИМ peak-hold. Прежняя версия завышала: держала спайк
-- PingPeakHold=1.5с как «пол», а потом uplink() ещё раз брал max(getPing, getPingRaw) — двойное
-- усиление пика → на первых ударах комбо lead был раздут (в логе ping скакал 148→180 и латчил
-- 180). Теперь: EMA как база, пик держим лишь короткий hold и быстро распускаем к EMA, а uplink
-- НЕ добавляет второй max с сырым спайком. Это даёт стабильный lead около среднего RTT.
local function getPing()
	local raw = getPingRaw()
	V93.pingEMA = V93.pingEMA + (raw - V93.pingEMA) * Config.PingSmooth
	local now = os.clock()
	if raw >= V93.pingPeak then
		V93.pingPeak, V93.pingPeakAt = raw, now      -- новый пик — фиксируем мгновенно
	else
		local hold = Config.PingPeakHold or 0.4
		local age = now - V93.pingPeakAt
		if age >= hold then
			-- окно удержания вышло: быстро распускаем пик к EMA (не мгновенно, но и не залипая)
			V93.pingPeak = V93.pingPeak + (V93.pingEMA - V93.pingPeak) * math.min((age - hold) * 6, 1)
		end
	end
	-- эффективный RTT = EMA, приподнятый к пику лишь частично (не весь спайк идёт �� lead)
	local eff = V93.pingEMA + (V93.pingPeak - V93.pingEMA) * (Config.PingPeakWeight or 0.5)
	return math.min(eff, Config.PingCap)
end

local function uplink()
	-- опираемся на сглаженный getPing(); БЕЗ повторного max с сырым спайком (это и раздувало lead)
	return math.clamp(getPing() * Config.UplinkFactor + Config.UplinkMargin, Config.UplinkMin, Config.UplinkMax)
end

local function localChar() return LocalPlayer.Character end

-- [V68] FPS: persistent index fn for pcall-safe property reads WITHOUT allocating
-- a new closure every call. The old hot-path pattern `pcall(function() x=o.Prop end)`
-- built a fresh closure per read → with 15+ threats × several reads × 60fps that's
-- thousands of allocations/sec → GC stalls (the FPS drop, not rendering). pcall on a
-- persistent function allocates nothing.
local function _index(o, k) return o[k] end
local function safeGet(o, k, default)
	if o == nil then return default end
	local ok, v = pcall(_index, o, k)
	if ok and v ~= nil then return v end
	return default
end

-- [V68] per-frame HRP cache. localHRP() is called from many hot spots; each call did
-- a FindFirstChild. Cache it once per Heartbeat frame (FrameId bumped in the tick).
local FrameId = 0
local _hrpCache, _hrpFrame = nil, -1
local function localHRP()
	if _hrpFrame == FrameId and _hrpCache and _hrpCache.Parent then return _hrpCache end
	local c = localChar()
	_hrpCache = (c and c:FindFirstChild("HumanoidRootPart")) or nil
	_hrpFrame = FrameId
	return _hrpCache
end

local HARD_BLOCKERS = { "BlockCooldown", "Ragdoll", "Downed", "Greenzone",
                        "RpCombatLocked", "StaffModPeaceMode" }
local function canBlockNow()
	local c = localChar()
	if not c then return false, "no-char" end
	-- [V98] руки не одеты (кнопка T / unequip) → сервер НЕ примет ни блок, ни парри
	-- (Block.lua:80 требует Equip==true). Кросс-платформенно через атрибут Equip, без T-хука.
	-- Не реагируем вообще, чтобы не жечь бесполезные пресс���� когда физически не можем блокировать.
	if Config.RequireEquip ~= false and c:GetAttribute("Equip") ~= true then
		return false, "Unequip"
	end
	for _, attr in ipairs(HARD_BLOCKERS) do
		if c:GetAttribute(attr) == true then return false, attr end
	end
	local stunned = c:GetAttribute("Stunned") == true
	local cantAny = c:GetAttribute("CantAnything") == true
	if stunned or cantAny then
		if Config.ComboEscape and c:GetAttribute("ParryBuffered") == true
		   and c:GetAttribute("PerfectBlocking") ~= true then
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

local function isEnemyModel(model)
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
end

local function flatDirTo(fromPos, targetPos)
	local d = Vector3.new(targetPos.X - fromPos.X, 0, targetPos.Z - fromPos.Z)
	if d.Magnitude < 0.05 then return nil end
	return d.Unit
end

-- [V62] упрежда����щая позиция цели: экстраполируем по гор��зонтальной скорости.
-- На близкой дистанции угловая скорость стрейфа макси��альна, п��этому целимся
-- туда, где враг БУДЕТ через BoxingAimLead секунд, а не где он сейчас.
local function aimPosOf(targetHRP, lead)
	if not targetHRP then return nil end
	local pos = targetHRP.Position
	if not lead or lead <= 0 then return pos end
	local vel
	local ok = pcall(function() vel = targetHRP.AssemblyLinearVelocity end)
	if not ok or not vel then
		pcall(function() vel = targetHRP.Velocity end)
	end
	if not vel then return pos end
	return pos + Vector3.new(vel.X, 0, vel.Z) * lead
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
-- applyFacing в RenderStepped) — так убираем гонку Heartbeat↔RenderStepped и войну писателей.
-- hard=true → жёсткий снап (у контакта/в замесе), иначе плавный лерп. holdFor — грейс, сколько
-- держать цель после этого вызова (schedulerStep дёргает каждый Heartbeat, н�� грейс покрывает
-- сам момент контакта и пару кадров после). Velocity-lead УБРАН: сервер валидирует facing на
-- ФАКТИЧЕСКУЮ позицию атакующего в момент удара, упреждение по скорости уводило прицел вбок
-- (в логах давало face=0.5 BACK на стрейфящем враге) → блок отклонялся.
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
			rate = dAng / dtr
			prevLook = rec.look
		end
		-- [V101] позиция/время прошлого кадра — для measured-closing (дельта дистанции),
		-- ловит дэш-выпады с CFrame-твином, где AssemblyLinearVelocity остаётся ≈0.
		prevPos, prevT = rec.pos, rec.t
	end
	FaceTrack[aHRP] = { look = flatLook, t = now, pos = aHRP.Position }
	-- prevLook = facing атакующего на ПРОШЛОМ кадре (для детекта знака доворота к нам)
	return rate, prevLook, prevPos, prevT
end

-- ��────���───────────────────────��───────────────────────────────────────────────
-- [V93] GROUND-TRUTH ХИТБОКСЫ — фундамент нового High-режима.
-- Игровой VictimHitboxServiceClient (декомпилирован из дампа) каждый Heartbeat идёт по
-- workspace.Hitboxes: активный удар = BasePart с детьми Owner/AttackName (StringValue) и
-- строковым атрибутом VictimSwingId. Если парт пересекается с нашим персонажем
-- (workspace:GetPartBoundsInBox(part.CFrame, part.Size, {ourChar})) — клиент шлёт серверу
-- VictimHitConfirm вместе с нашим PerfectBlocking. То есть ИСТИННАЯ геометрия удара — сам
-- парт, а не наши догадки про yaw/размах. High опирается на это:
--   • если парт атакующего уже есть — проверяем пересечение с нами 1:1 как игра (авторитетно);
--   • пока парта нет — предсказываем бокс РЕАЛЬНЫМ размером (кэш по типу атаки), без trust-
--     костылей (point-blank/heavy/drag/latch).
-- Пер-кадровый индекс живых ��артов по в��адельцу (Owner.Value). Скан один раз за FrameId,
-- чтобы не обходить папку по разу на каждую угрозу в мультибое. Всё состояние — в V93 (см. выше
-- про лимит 200 локалов), новых local тут не заводим.
local function hitboxIndex()
	if V93.hbFrame == FrameId then return V93.byOwner end
	V93.hbFrame = FrameId
	local byOwner = V93.byOwner
	for k in pairs(byOwner) do byOwner[k] = nil end
	local folder = V93.hbFolder
	if not (folder and folder.Parent) then
		folder = Workspace:FindFirstChild("Hitboxes")
		V93.hbFolder = folder
	end
	if not folder then return byOwner end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local owner = child:FindFirstChild("Owner")
			local atk   = child:FindFirstChild("AttackName")
			if owner and atk and owner:IsA("StringValue") and atk:IsA("StringValue") then
				local sid = child:GetAttribute("VictimSwingId")
				if typeof(sid) == "string" and sid ~= "" then
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
	return byOwner
end

-- Точная (как в игре) проверка: пересекает ли РЕАЛЬНЫЙ парт атакующего наш персонаж.
-- true — есть парт и он в нас; false — парт(ы) есть, но мимо; nil — активного парта нет.
local function realHitboxHitsMe(ownerName)
	if not ownerName then return nil end
	local lst = hitboxIndex()[ownerName]
	if not lst or #lst == 0 then return nil end
	local char = localChar()
	if not char then return nil end
	local params = V93.hbParams
	if not params then
		params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.MaxParts = 20
		V93.hbParams = params
	end
	if V93.hbChar ~= char then
		params.FilterDescendantsInstances = { char }
		V93.hbChar = char
	end
	for i = 1, #lst do
		local part = lst[i]
		if part.Parent and #Workspace:GetPartBoundsInBox(part.CFrame, part.Size, params) > 0 then
			return true
		end
	end
	return false
end

local function hitboxGeom(th)
	local aHRP = th.attackerHRP
	if not aHRP or not aHRP.Parent then return nil end
	local now  = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local aPos = aHRP.Position
	local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
	-- [V67] кап смещения от velocity: у стрейфящего врага полная ��кс��раполяция
	-- уводит центр хитбокса вбок и ломает willHitMe (ложный негатив в упор).
	local lead = Vector3.new(aV.X * tHit, 0, aV.Z * tHit)
	-- [V91] РАЗДЕЛЬНЫЙ кап: сближение (toward us) ведём до WillHitCloseCap (лунж/��аскок реально
	-- закрывает дистанцию — иначе бокс отсекал их как far → High-миссы), strafe — до
	-- WillHitLatCap (узко, иначе центр бокса уезжает вбок → ложный негатив в упор).
	local meG = localHRP()
	if meG then
		local toMeG = Vector3.new(meG.Position.X - aPos.X, 0, meG.Position.Z - aPos.Z)
		if toMeG.Magnitude > 0.05 then
			toMeG = toMeG.Unit
			local closeAmt = lead:Dot(toMeG)               -- >0 = идёт на нас (по velocity)
			-- [V102] ИЗМЕРЕННОЕ сближение (студ/с) кадр-к-кадру. AssemblyLinearVelocity у
			-- бегающего игрока часто занижен/шумит (Humanoid move, CFrame-твины) → predA не
			-- доводился до нас и geom-бокс мазал по врагу, который вбегает и бьёт «на возврате».
			-- Берём МАКС velocity- и измеренного сближения → бокс честно доводится к контакту.
			if th.prevPos and th.prevPosT then
				local dtp = now - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx   = th.prevPos.X - meG.Position.X
					local pdz   = th.prevPos.Z - meG.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					local curD  = toMeG and Vector3.new(aPos.X - meG.Position.X, 0, aPos.Z - meG.Position.Z).Magnitude or 0
					local measClose = (prevD - curD) / dtp      -- >0 = приближается
					if measClose > 0 then closeAmt = math.max(closeAmt, measClose * tHit) end
				end
			end
			local latVec   = lead - toMeG * (lead:Dot(toMeG))  -- боковая составляющая (по velocity)
			local latCap   = Config.WillHitLatCap or 1.5
			if latVec.Magnitude > latCap then latVec = latVec.Unit * latCap end
			closeAmt = math.clamp(closeAmt, 0, Config.WillHitCloseCap or 6.5)
			lead = toMeG * closeAmt + latVec
		else
			local cap = Config.WillHitVelCap or 2.0
			if lead.Magnitude > cap then lead = lead.Unit * cap end
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

	local trackedRate, prevLook, prevPos, prevT = attackerYawRate(aHRP, flatLook)
	-- стэшим на th для drag-детекта в willHitMe (знак доворота = prevLook vs текущий facing)
	th.yawRate  = trackedRate
	th.prevLook = prevLook
	th.prevPos  = prevPos   -- [V101] для measured-closing (лунж-детект тяжёлых)
	th.prevPosT = prevT

	if Config.TurnWindow then
		local me = localHRP()
		if me then
			local toMe = Vector3.new(me.Position.X - predA.X, 0, me.Position.Z - predA.Z)
			local dist = toMe.Magnitude
			if dist > 0.05 then
				toMe = toMe.Unit
				local angNow = math.deg(math.acos(math.clamp(flatLook:Dot(toMe), -1, 1)))
				local physYaw = math.abs(math.deg(safeGet(aHRP, "AssemblyAngularVelocity", Vector3.zero).Y))
				local turnRate = math.max(trackedRate, physYaw)
				local measuredTurn = turnRate * tHit * (Config.TurnAngVelK or 1)
				local baseCone = Config.TurnBaseDeg
				if dist <= (forward + (Config.CloseRangePad or 5)) then
					baseCone = Config.TurnCloseDeg
				end
				local allow = math.clamp(baseCone + measuredTurn, 0, Config.TurnWindowMax)
				if tHit < Config.TurnFloor then allow = math.min(allow, baseCone) end
				if angNow <= allow then
					flatLook = toMe
				end
			end
		end
	end

	local center = predA + flatLook * forward
	return center, forward, predA, flatLook
end

local function willHitMe(th)
	local myHRP = localHRP()
	local aHRP  = th.attackerHRP
	if not myHRP then return Config.FilterFailSafe end
	if not aHRP or not aHRP.Parent then return false end

	-- [module] VERTICAL GATE: the hitbox math below is flat (X/Z only), so an attacker
	-- standing on another floor directly above/below used to register as point-blank.
	-- Reject anyone whose vertical offset exceeds MaxHeightDiff before any 2D test.
	local maxDY = Config.MaxHeightDiff or 12
	if math.abs(myHRP.Position.Y - aHRP.Position.Y) > maxDY then return false end

	-- [V88] LATCH: как только закоммиченный свинг хоть раз признан у��розой (в упор, лицом
	-- или через доворот-на-нас), держим true до конца жизни угрозы. Это чинит финты с
	-- разворотом: враг бьёт спиной и доворачивается — раньше поздний кадр с "смотрит мимо"
	-- сбрасывал willHitMe и парри отменялся. Настоящий финт-кэнсел сюда не попадает: его
	-- раньше удаляет ветка th.feinted в scheduler.
	local mode = Config.AccuracyMode or "Low"

	-- [V93] В High доверяемся ТОЛЬКО ground-truth (реальный парт) и чистой геометрии; latch из
	-- Low-эвристик (point-blank/drag/heavy) здесь отключён — иначе High «залипал» бы на угрозах,
	-- которые в нас не попадают. Свой latch в High ставит лишь подтверждённое пересечение
	-- реального игрового хитбокса (th.gtConfirmed) в ветке ниже.
	if mode == "High" then
		if th.gtConfirmed then return true end
	elseif th.trustLatch then
		return true
	end

	-- [V102] BROADPHASE (High): ДЕШЁВЫЙ ранний отказ ДО дорогого hitboxGeom. Только для ЛЁГКИХ
	-- M1 — тяжёлые (M2/SKILL) НИКОГДА не режем здесь (у них своя расширенная логика доверия
	-- HeavyTrust/lunge/mid-face ниже; V101-broadphase ошибочно резал стоячий нацеленный хэви на
	-- dist 24-30 → willHitMe=false → ни блока, ни interrupt → «стоим как вкопанный». Теперь хэви
	-- всегда проходит дальше). Для M1: отказ только если враг за HighBroadRange И НЕ приближается
	-- ни по velocity, ни по измеренной дельте позиции (ловит бег «туда-обратно с ударом на входе»).
	if mode == "High" and not th.gtConfirmed and th.kind ~= "M2" and th.kind ~= "SKILL" then
		local bdx = myHRP.Position.X - aHRP.Position.X
		local bdz = myHRP.Position.Z - aHRP.Position.Z
		local d2  = bdx * bdx + bdz * bdz
		local br  = Config.HighBroadRange or 24
		if d2 > (br * br) then
			local bv = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
			local approaching = (bv.X * bdx + bv.Z * bdz) > 0   -- velocity в нашу сторону
			if not approaching and th.prevPos and th.prevPosT then
				local dtp = os.clock() - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx  = th.prevPos.X - myHRP.Position.X
					local pdz  = th.prevPos.Z - myHRP.Position.Z
					-- прошлая дистанция больше текущей → идёт на нас (измеренное сближение)
					approaching = (pdx * pdx + pdz * pdz) > d2 + 1
				end
			end
			if not approaching then
				th.trustedHit = false
				return false
			end
		end
	end

	local _, forward, predA, flatLook = hitboxGeom(th)
	if not predA then return Config.FilterFailSafe end

	-- дешёвые величины сперва — по ним закрываем самый частый кейс (point-blank)
	-- БЕЗ дорогого предикта ротации.
	local toMeV = Vector3.new(myHRP.Position.X - aHRP.Position.X, 0, myHRP.Position.Z - aHRP.Position.Z)
	local dist  = toMeV.Magnitude

	-- Point-blank floor applies in BOTH modes. A hit landed in point-blank range is
	-- physically unavoidable regardless of predicted rotation, so the strict High box
	-- must never reject it — that was the root of High-mode misses on close M1s while
	-- an enemy strafed (predA/box swung off us → false → NO-PRESS → LATE).
	-- [V93] Point-blank floor — ТОЛЬКО не в High. «В упор» ещё не значит «попадёт»: атакующий
	-- может махать мимо/спиной. В High это решает реальный парт либо геометрия ниже, а не радиус.
	if mode ~= "High" then
		local trust = Config.HitTrustRange or 0
		if trust > 0 and dist <= (Config.PointBlank or 3.0) then
			th.trustedHit = true; return true
		end
	end

	-- [V68] предсказанная Р����ТАЦИЯ атакующего на момент контакта. Хитбокс атаки
	-- стр��ит���я игрой по yaw HRP атакующего (см. VictimHitboxService: деталь в
	-- workspace.Hitboxes ориентирована по атакующему). Значит важно не где он
	-- смотрит СЕЙЧАС, а куда будет смотреть в момент удара — это и ловит финты.
	local nowW  = os.clock()
	local tHit  = math.clamp((th.contactAbs or nowW) - nowW, 0, 0.6)
	local toMe  = (dist > 0.05) and toMeV.Unit or flatLook
	local rawL  = aHRP.CFrame.LookVector
	rawL = Vector3.new(rawL.X, 0, rawL.Z)
	rawL = (rawL.Magnitude > 0.05) and rawL.Unit or flatLook
	local angY  = safeGet(aHRP, "AssemblyAngularVelocity", Vector3.zero).Y or 0
	-- [V92] в High жёсткий кап доворота (спиной-стоящий не «долетает» предиктом до нас)
	local capR  = math.rad((mode == "High" and (Config.RotPredMaxDegHigh or 55)) or (Config.RotPredMaxDeg or 120))
	-- [V91] РОБАСТНЫЙ предикт ротации. Физический angY шумит и часто =0 меж��у physics-степами
	-- → predLook НЕ доворачивался на доворачивающегося врага → High-бокс уходил мимо (миссы
	-- never-in-hitbox). Берём МАКС из физической и ИЗМЕРЕННОЙ (кадр-к-кадру) скорости доворота;
	-- знак измеренной — из наблюдённого поворота prevLook→rawL (θ = -(px·rz − pz·rx)).
	-- Это точнее наводит бокс по facing В МОМЕНТ удара — как строит серверный хитбокс.
	local rotRate = math.abs(angY)
	local rotSign = (angY >= 0) and 1 or -1
	if th.prevLook then
		local measR = math.rad(th.yawRate or 0)
		if measR > rotRate then
			rotRate = measR
			local cz = th.prevLook.X * rawL.Z - th.prevLook.Z * rawL.X
			rotSign = (cz <= 0) and 1 or -1
		end
	end
	local dyaw  = math.clamp(rotSign * rotRate * tHit, -capR, capR)
	-- [V89] поворот rawL вокруг Y БЕЗ аллокации CFrame. CFrame.Angles(0,dyaw,0)*rawL
	-- создавал временный CFrame НА КАЖДУЮ угрозу КАЖДЫЙ кадр — в мясорубке (2+ атакующих
	-- по нескольку треков) это давило GC и роняло FPS scheduler'а → он «переставал
	-- успевать». Ручная матрица Y-вращения даёт тот же вектор без мусора.
	local cy, sy   = math.cos(dyaw), math.sin(dyaw)
	local predLook = Vector3.new(rawL.X * cy + rawL.Z * sy, 0, -rawL.X * sy + rawL.Z * cy)
	predLook = (predLook.Magnitude > 0.05) and predLook.Unit or rawL
	local faceDotPred = predLook:Dot(toMe)

	-- [V88] SNAP-TURN FEINT: враг закоммитил свинг и АКТИВНО доворачивается на нас. Серверный
	-- хитбокс строится по его facing В МОМЕНТ удара, поэтому разворот из «спиной» = р��альная
	-- угроза, хотя сейч��с смотрит мимо. Детект по знаку: предсказанный facing ближе к нам, чем
	-- текущий (rawDot) → он поворачивается в нашу сторону. Работает и в High, и в Low.
	local rawDot = rawL:Dot(toMe)
	-- [V90] DRAG/SNAP-TURN — ловим по ЗНАКУ доворота (facing приближается к нам между кадрами),
	-- а не по мгновенной angY (она шумная и часто 0 между physics-степами → старый детект
	-- пропускал «закрученные» атаки). Два независимых источника доворота, любого достаточно:
	--   • physics-предикт: predLook уже развёрнут к нам сильнее текущего (faceDotPred > rawDot)
	--   • измеренный доворот за прошлый кадр: facing реально стал ближе к нам (prevLook→rawL)
	-- Порог скорости — DragTurnMinDeg (ниже прежних ~69°/с, ловим снап раньше). Дальность —
	-- DragTrustRange (шире обычного trust: drag часто начинают с�� средней дистанции).
	local turningToward = false
	if Config.DragDetect then
		local dragDeg   = Config.DragTurnMinDeg or 35
		local predTurns = (faceDotPred > rawDot + 0.03)
		local measTurns = false
		if th.prevLook then
			local prevDot = th.prevLook:Dot(toMe)
			measTurns = (rawDot > prevDot + 0.02) and ((th.yawRate or 0) >= dragDeg)
		end
		local physTurns = (math.abs(angY) > 1.2) and predTurns
		turningToward = physTurns or measTurns or (predTurns and (th.yawRate or 0) >= dragDeg)
	end
		-- [V90.4] drag/snap-turn доверие — ТОЛЬКО в Low. В High доворот, который реально
		-- дойдёт до нас, и так ловит предсказанный бокс (predLook по yaw в момент удара);
		-- radius-доверие в High агрилось бы на довороты, чей замах в нас не попадает.
		local dragRange = math.max(Config.HitTrustRange or 0, Config.DragTrustRange or 0)
		if mode ~= "High" and dragRange > 0 and dist <= dragRange and turningToward then
			th.trustedHit = true; th.trustLatch = true; th.feintTurn = true
			return true
		end

	-- [V89] HEAVY-ПРИОРИТЕТ (главная причина пропусков в диаг). Тяжёлые (M2) и скиллы —
	-- это ВЫПАДЫ: атакующий закрывает дистанцию прямо в замахе. Capoeira M2 детектился на
	-- dist=10, а WillHitVelCap=2.0 обрезал экстраполяцию predA до 2 студов → geom-бокс
	-- давал false ВЕСЬ пу���� → "never-in-hitbox" NO-PRESS, следом Ragdoll и каскад на
	-- остальных ��такующих (отсюда и «не справляется с мультиатаками»). Тяжёлые пропускать
	-- нельзя (их не перевзвести повторным блоком): если враг в расширенном радиусе И либо
	-- смотрит приме������ на нас (predFacing), либо реально СБЛИЖАЕТСЯ — считаем угрозой сразу,
	-- в обход geom-фильтра. Работает и в Low, и в High. Лишний блок безвреден (OmniBlock
	-- ненаправленный), а пропущенный хэви = проигранный разме��.
		-- [V93] HeavyTrust (радиусное доверие тяжёлым) — ТОЛЬКО не в High. В High тяжёлый лунж,
		-- который реально дойдёт, и так ловит предсказанный бокс (predA экстраполируется по
		-- velocity к нам); летящий мимо — не должен парироваться. Радиус тут = ложняки.
		if (th.kind == "M2" or th.kind == "SKILL") and Config.HeavyTrust then
			local aV       = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
			local toMeUnit = (dist > 0.05) and toMe or flatLook
			-- сближение по velocity (обычные дэши/выпады с LinearVelocity)
			local velClose = Vector3.new(aV.X, 0, aV.Z):Dot(toMeUnit)
			-- [V101] measured-closing: дельта дистанции по кадрам. Ловит CFrame-твин-дэши
			-- (MuayThai/Karate flying-knee), где AssemblyLinearVelocity остаётся ≈0.
			local measClose = 0
			if th.prevPos and th.prevPosT then
				local dtp = os.clock() - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx  = th.prevPos.X - myHRP.Position.X
					local pdz  = th.prevPos.Z - myHRP.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					measClose = (prevD - dist) / dtp
				end
			end
			local closing   = math.max(velClose, measClose)  -- >0 = реально идёт на нас
			local closingOk = closing > (Config.HeavyClosingMin or 6)
			-- (1) ДЛИННЫЙ ВЫПАД: враг реально дэшит на нас (сильное сближение) → доверяем до
			-- HeavyLungeRange НЕЗАВИСИМО от текущей дистанции. Это чинит MuayThai M2 dist=26.
			if closing > (Config.HeavyLungeClosing or 14) and dist <= (Config.HeavyLungeRange or 36) then
				th.trustedHit = true; th.trustLatch = true
				return true
			end
			-- (2) БЛИЖНИЙ РАДИУС (HeavyTrustRange): Low — сближение ИЛИ грубый facing; High —
			-- сближение ИЛИ нацелен в нас (конус HeavyHighFaceMin). Стоячий, но нацеленный
			-- тяжёлый (лог: spousespartner M2 dist=13) теперь доверяется.
			local heavyRange = Config.HeavyTrustRange or 14
			if dist <= heavyRange then
				local trustHeavy
				if mode == "High" then
					trustHeavy = closingOk or (faceDotPred >= (Config.HeavyHighFaceMin or 0.5))
				else
					trustHeavy = closingOk or (faceDotPred >= (Config.HeavyFaceMin or -0.30))
				end
				if trustHeavy then
					th.trustedHit = true; th.trustLatch = true
					return true
				end
			-- (3) СРЕДНЯЯ ДИСТАНЦИЯ (heavyRange..HeavyFaceRange): доверяем ТОЛЬКО е��ли тяжёлый
			-- нацелен ТОЧНО в нас узким конусом (HeavyFarFaceMin) — на такой дистанции это почти
			-- наверняка готовящийся выпад. Смотрит мимо / не идёт на нас → не парируем (нет ложняка).
			elseif dist <= (Config.HeavyFaceRange or 30) then
				if faceDotPred >= (Config.HeavyFarFaceMin or 0.85) then
					th.trustedHit = true; th.trustLatch = true
					return true
				end
			end
		end

		if mode == "High" then
			-- [V93] HIGH = GROUND-TRUTH. Решает не «рядом и п��имерно смотрит», а реальная игровая
			-- геометрия удара.
			-- ── Шаг 1: реальный парт. Если игра УЖЕ породила хитбокс-парт этого атакующего в
			-- workspace.Hitboxes — проверяем пересечение с нами тем же методом, что и
			-- VictimHitboxService (GetPartBoundsInBox по нашему персонажу). Это авторитетно и
			-- пинг-независимо по геометрии; вертикаль/ориентация учтены самим партом.
			local gt = realHitboxHitsMe(th.name)
			if gt == true then
				th.gtConfirmed = true      -- латчим: удар реально в нас, держим блок до ко��ца свинга
				th.trustedHit  = true
				return true
			elseif gt == false then
				-- Парт(ы) активен, но в нас не попадает → чужой/мимо-удар. Точно не блокируем.
				th.trustedHit = false
				return false
			end

			-- ── Шаг 2: парта ещё нет (мы во взводе ДО контакта) → предсказательная геометрия,
			-- но РЕАЛЬНЫМ размером бокса (кэш RealHitboxSize по типу атаки, обучается с живых
			-- партов; фолбэк — Config для самого первого свинга). Два origin'а (predA/predLook и
			-- aPos/rawL), их объединение. Никаких trust-радиусов — только «мы внутри замаха».
			-- [V105] движ-слак: расширяем бокс на вклад относительной планарной скорости (враг + мы),
			-- компенсируя рассинхрон отрисованной (прошлой) и серверной (будущей) позиции у движущихся.
			local slack   = Config.HighSlack or 0.6
			do
				local aVel = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
				local mVel = myHRP and safeGet(myHRP, "AssemblyLinearVelocity", Vector3.zero) or Vector3.zero
				local relX, relZ = aVel.X - mVel.X, aVel.Z - mVel.Z
				local relSpeed = math.sqrt(relX * relX + relZ * relZ)
				local add = math.min(relSpeed * (Config.HighMoveSlackK or 0.045), Config.HighMoveSlackCap or 2.2)
				slack = slack + add
			end
			local realSz  = V93.sizes[th.kind]
			-- вертикальный гейт по реальной высоте парта (плюс запас): удар выше/ниже — мимо
			if realSz then
				local halfH = realSz.Y * 0.5 + 3
				if math.abs(myHRP.Position.Y - aHRP.Position.Y) > halfH then
					th.trustedHit = false
					return false
				end
			end
			-- дальность/глубина от origin а��акующего вдоль его facing: центр парта ≈ forward,
			-- полуглубина = realSz.Z/2 (фолбэк — старые Config-границы), полуширина = realSz.X/2.
			local halfW   = (realSz and realSz.X * 0.5 or (Config.HitHalfWidth or 4)) + slack
			local depthF  = (realSz and (forward + realSz.Z * 0.5) or (forward + (Config.HitboxDepth or 0))) + slack
			local depthB  = (realSz and (forward - realSz.Z * 0.5) or -(Config.HitboxDepthBack or 0)) - slack
			local function inBox(originX, originZ, look)
				local ox, oz = myHRP.Position.X - originX, myHRP.Position.Z - originZ
				local fdepth = ox * look.X + oz * look.Z
				local fside  = math.abs(ox * (-look.Z) + oz * look.X)
				return fdepth >= depthB and fdepth <= depthF and fside <= halfW
			end
			-- [V94] AIM-AWARE предикт facing к МОМЕНТУ contact. Серверный хитбокс строится по yaw
			-- атакующего в момент удара (дамп VictimHitboxService). Прежний predLook капался жёстко
			-- на RotPredMaxDegHigh=55° → враг, доворачивающийся к нам со спины/сбоку, «не долетал»
			-- предиктом → back-facing gate его резал → MISS/поздний ответ (жалоба «бьёт и
			-- поворачивается — скрипт не вовремя»). Считаем знаковый угол rawL→toMe и сколько враг
			-- РЕАЛЬНО успеет повернуть за tHit (rotRate = макс физической и измеренной кадр-к-кадру
			-- угловой скорости). Поворачиваем rawL к нам не больше, чем позволяет скорость:
			--   • доворачивается быстро → aimLook смотрит на нас → парируем ВОВРЕМЯ (взвод заранее);
			--   • стоит спиной без вращения → maxTurn≈0 → aimLook≈спина → aimDot низкий → мимо.
			local dotRT   = rawL.X * toMe.X + rawL.Z * toMe.Z
			local crossRT = rawL.X * toMe.Z - rawL.Z * toMe.X
			local angToUs = math.atan2(crossRT, dotRT)          -- знаковый угол rawL→toMe
			local maxTurn = math.max(rotRate, 0) * tHit          -- сколько успеет повернуть (рад)
			local phi     = math.clamp(angToUs, -maxTurn, maxTurn)
			local cphi, sphi = math.cos(phi), math.sin(phi)
			local aimLook = Vector3.new(rawL.X * cphi - rawL.Z * sphi, 0, rawL.X * sphi + rawL.Z * cphi)
			aimLook = (aimLook.Magnitude > 0.05) and aimLook.Unit or rawL
			-- [V96] POINT-BLANK доверие (как в LOW-ветке): в упор враг физически достаёт хитбоксом
			-- НЕЗАВИСИМО от facing, а серверный do��орот довершится к контакту. Прежде High жёстко
			-- резал ближние удары facing-гейтом → в логе валидные комбо-M1 (dist 3–6) падали в
			-- `MISS never-in-hitbox` → NO-PRESS/поздний блок. Ниже PointBlank сразу доверяем.
			if dist <= (Config.PointBlank or 3.0) then
				th.trustedHit = true
				return true
			end
			-- BACK-FACING gate по facing С УЧЁТОМ доворота: даже повернувшись на максимум своей
			-- угловой скорости, враг не наводится на нас → этим свингом не достанет → мимо.
			if aimLook:Dot(toMe) < (Config.HighFaceMin or 0.25) then
				th.trustedHit = false
				return false
			end
			-- бокс строим с facing К МОМЕНТУ contact (aimLook) от предсказанной И текущей позиции
			local hit = inBox(predA.X, predA.Z, aimLook)
			         or inBox(aHRP.Position.X, aHRP.Position.Z, aimLook)
			th.trustedHit = false
			return hit
		end

	-- LOW: щедрое доверие ближнему бою (как V67), НО отбраковываем удары, явно
	-- направленные не в нас (predFacing смотрит от нас и мы не в упор) — чтобы не
	-- агри��ься на чужие атаки в замесе.
	local trust = Config.HitTrustRange or 0
	if trust > 0 and dist <= trust then
		if dist <= (Config.PointBlank or 3.0) then th.trustedHit = true; th.trustLatch = true; return true end
		if faceDotPred >= (Config.LowFaceMin or -0.40) then th.trustedHit = true; th.trustLatch = true; return true end
		th.offTarget = true
		return false
	end

	local off  = Vector3.new(myHRP.Position.X - predA.X, 0, myHRP.Position.Z - predA.Z)
	local fwd  = off:Dot(flatLook)
	local side = math.abs(off:Dot(Vector3.new(-flatLook.Z, 0, flatLook.X)))
	local slack = Config.HitboxSlack or 0
	local inForward = fwd >= (forward - Config.HitboxDepthBack - slack)
	                and fwd <= (forward + Config.HitboxDepth + slack)
	local inLateral = side <= (Config.HitHalfWidth + slack)
	return inForward and inLateral
end

local function nextCombo(attacker)
	local now = os.clock()
	local c = ComboState[attacker]
	if not c or (now - c.last) > COMBO_RESET then c = { idx = 0, last = now } end
	c.idx  = (c.idx % 4) + 1
	c.last = now
	ComboState[attacker] = c
	return c.idx
end

local KSP = game:GetService("KeyframeSequenceProvider")
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
		-- [V71] CombatUtils.GetAttackSpeedMultiplier(height): игра делит задержку удара
		-- на этот множитель (см. GetScaledHitboxDelay). Нужен, чтобы предсказывать
		-- реальную скорость атаки быстрых (низкорослых) врагов.
		local pkgs = ReplicatedStorage:FindFirstChild("Packages")
		local cuMod = pkgs and pkgs:FindFirstChild("CombatUtils")
		if cuMod then GameData.cu = require(cuMod) end
	end)
end

-- [V71] множитель скорости атаки конкретного АТАКУЮЩЕГО. Задержка удара в игре =
-- base / mult (GetScaledHitboxDelay). mult зависит от роста персонажа: низкий → до
-- 1.15 (бьёт на 15% быстрее), высокий → 0.85. Раньше мы всегда слали 1 → быстрые
-- враги давали LATE. Сначала пр��бу��м родные функции игры (future-proof при апдейтах),
-- потом фолбэк на задокументированную формулу от атрибута Height.
local AttackMultCache = {}
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

local function styleOf(model)
	loadGameModules()
	if GameData.cau then
		local ok, s = pcall(function() return GameData.cau.GetCombatStyleForCharacter(model) end)
		if ok and type(s) == "string" and #s > 0 then return s end
	end
	local ok, s = pcall(function() return model:GetAttribute("CombatStyle") end)
	if ok and type(s) == "string" and #s > 0 then return s end
	return "Basic"
end

local BONE_MARKERS = {
	HumanoidRootPart=true, Torso=true, Head=true, ["Left Leg"]=true, ["Right Leg"]=true,
	["Left Arm"]=true, ["Right Arm"]=true, UpperTorso=true, LowerTorso=true,
}
local function scanMarkers(seq)
	local hit, any, count = nil, nil, 0
	pcall(function()
		for _, kf in ipairs(seq:GetKeyframes()) do
			for _, m in ipairs(kf:GetMarkers()) do
				if not BONE_MARKERS[m.Name] then
					count += 1
					if not any or kf.Time < any then any = kf.Time end
					if m.Name == "Hit" and (not hit or kf.Time < hit) then hit = kf.Time end
				end
			end
		end
	end)
	return hit, any, count
end

local AnimMeta = {}
local function resolveAnimMeta(id)
	local cached = AnimMeta[id]
	if cached then return cached end
	local meta = { kind = "M1", hit = nil, marks = 0 }
	local ok, seq = pcall(function() return KSP:GetKeyframeSequenceAsync("rbxassetid://" .. id) end)
	if ok and seq then
		local hit, any, count = scanMarkers(seq)
		meta.marks = count
		if hit and hit > 0 then
			meta.kind, meta.hit = "M2", hit
		elseif count > 0 and any then
			meta.kind, meta.hit = "SKILL", any
		end
		pcall(function() seq:Destroy() end)
	else
		local legacy = LEGACY_ATTACKS[id]
		if legacy then meta.kind = legacy.t end
	end
	AnimMeta[id] = meta
	return meta
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
local BenignIds = {}
-- [V85] id защитных анимаций (block/guard/parry/deflect/perfect). Некоторые стили имеют
-- на ��лок-анимации keyframe-маркеры → resolveAnimMeta оши��очно принимал их за атаку (SKILL/M2)
-- и парри срабатывал на ЧУЖОЙ блок. Собираем их явно и жёстко исключаем из детекта угроз.
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
					for _, child in ipairs(styleFolder:GetChildren()) do
						local defensive = looksDefensive(child.Name)
						local kind = (not defensive) and kindFromName(child.Name) or nil
						local id = animIdOf(child)
						if id and defensive then BlockIds[id] = true end
						if kind and id then
							AttackIds[id] = { kind = kind, combo = comboFromName(child.Name) }
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
					if not AttackIds[id] and not BlockIds[id] then BenignIds[id] = true end
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

local function resolveInfo(id, model)
	local entry  = AttackIds[id]
	local meta   = resolveAnimMeta(id)
	local legacy = LEGACY_ATTACKS[id]
	local kind = (meta.hit and meta.kind == "M2") and "M2" or (entry and entry.kind) or meta.kind
	local rk = registryKind and registryKind(model, id)
	if rk == "M1" or rk == "M2" then kind = rk end
	return {
		t     = kind,
		s     = styleOf(model) or (legacy and legacy.s) or "Basic",
		hit   = meta.hit,
		combo = entry and entry.combo,
		mom   = legacy and legacy.mom or false,
	}
end

-- базовая задержка удара в "speed-1" секундах (без м��ожителя скорости атаки).
local function hitTimelineBase(info, combo)
	if info.t == "SKILL" then
		if info.hit and info.hit > 0 then return info.hit end
		return 0.35
	end
	if info.t == "M2" then
		loadGameModules()
		local cfgv
		if GameData.cfg then
			local ok, d = pcall(function() return GameData.cfg.GetStyleM2HitboxDelay(info.s, info.mom) end)
			if ok and type(d) == "number" then cfgv = d + WINDUP_EXTRA end
		end
		if not cfgv then
			cfgv = (LEGACY_M2_BASE[string.lower(info.s or "")] or 0.30) + WINDUP_EXTRA
		end
		-- [V89] КОНФИГ — авторитетный источник тайминга M2. GetStyleM2HitboxDelay даёт ровно
		-- ту задержку, по которой сервер наносит удар (GetScaledHitboxDelay: delay/mult).
		-- РАНЬШЕ первым в��звращался маркер "Hit" из анимации (info.hit) и он вра��: в диаг
		-- Capoeira M2 читался hitTL=327мс при реальном контакте 448мс (predErr=+163ms LATE
		-- NO-PRESS → Ragdoll-кас��ад). Конфиг для той же Capoeira даё�� ~441мс (ошибка 7мс).
		-- Теперь марк��р — лишь MAX-страховка повер�� конфига: покрывает дли��ные и 2-хитовые
		-- анимации (Boxing M2MultiHitCount=2, реальный значимый контакт ~749мс), где голый
		-- конфиг первого удара занижает окно.
		if info.hit and info.hit > 0 then
			return math.max(cfgv, info.hit)
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
local function hitTimeline(info, combo, mult)
	local base = hitTimelineBase(info, combo)
	local m = (type(mult) == "number" and mult > 0.05) and mult or 1
	return base / m
end

function styleForward(style, kind)
	loadGameModules()
	if GameData.cfg then
		local ok, f = pcall(function() return GameData.cfg.GetStyleHitboxForwardOffset(style, kind) end)
		if ok and type(f) == "number" then return f end
	end
	return (kind == "M2") and Config.M2Forward or Config.M1Forward
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
AnimLib._handlerSet = {}

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
	local char = localChar()
	local anim = resolveBlockAnim()
	if not char or not anim then return end

	local h = getHandler()
	if h and h.LoadAnim then
		local ok, tr = pcall(function() return h.LoadAnim(char, "Blocking", anim, nil, false) end)
		if ok and tr then
			AnimLib.tracks.Blocking = tr
			pcall(function() if not tr.IsPlaying then tr:Play(0.08) end end)
			return
		end
	end
	local animator = getAnimator()
	if not animator then return end
	local tr = AnimLib.tracks.Blocking
	if not tr or not tr.IsPlaying then
		pcall(function()
			if not tr then tr = animator:LoadAnimation(anim); AnimLib.tracks.Blocking = tr end
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

local function playDodgeMotion(dirOverride)
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
		lv.VectorVelocity = dir * Config.DashSpeed
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Parent = hrp
		Debris:AddItem(att, Config.DashDuration)
		Debris:AddItem(lv, Config.DashDuration)
	end)
end

local function sendActivate(tsServer)
	local now = os.clock()
	if now - State.lastAct < Config.MinActGap then return false end
	State.lastAct = now
	local c = localChar()
	if c then c:SetAttribute("Blocking", true) end
	ServerRemote:FireServer(
		{ Type = "Combat", Action = "Block", Func = "Activated" },
		tsServer
	)
	State.guardUp = true          -- сервер теперь держит guard
	playBlockAnim()
	return true
end

-- force=true — принудительное снятие guard (в обход MinDeactGap). Нужно, чтобы реальный
-- релиз никогда не терялся из-за рейт-лимита и guard не завис поднятым.
local function sendDeactivate(force)
	local now = os.clock()
	if not force and now - State.lastDeact < Config.MinDeactGap then return false end
	State.lastDeact = now
	local c = localChar()
	if c then c:SetAttribute("Blocking", nil) end
	ServerRemote:FireServer({ Type = "Combat", Action = "Block", Func = "Deactivated" })
	State.guardUp = false         -- guard снят на сервере
	stopBlockAnim()
	return true
end

local function sendDodge(dir)
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "Evasive", Func = "Evasive" })
	playDodgeMotion(dir)
	State.lastDodge  = os.clock()
	State.dodgeCount = State.dodgeCount + 1
	State.flashUntil = os.clock() + 0.25
	State.status     = "DODGE"
end

local function sendBoxingCounter(th, keepGuard)
	local myHRP = localHRP()
	local aHRP  = th and th.attackerHRP
	if myHRP and aHRP and aHRP.Parent then
		-- [V63] ПРЯМОЙ снап на текущую позицию в��ага, без velocity-lead.
		-- Дамп (M2_ModuleScript.OnM2Activated): у boxing-M2 нет клиентского
		-- прицеливания — сервер строит хитбокс по нашему HRP LookVector в момент
		-- ServerCheck. Экстраполяция по скорости на ближней дистанции разворачивала
		-- HRP вбок (в логе face=0.51 BACK!) и counter уходил мимо. Короткий
		-- boxing-хитбокс требует, чтобы мы смотрели ТОЧНО на врага сейчас.
		-- мгновенный точный снап прямо сейчас (counter стреляет в этот кадр, серверу нужен
		-- наш LookVector немедленно), + держим цель в едином канале весь BoxingFaceLockDur
		local d = flatDirTo(myHRP.Position, aHRP.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
		setFaceGoal(aHRP, true, Config.BoxingFaceLockDur or 0.55)
	end
	-- [V62] в мультибое НЕ роняем guard: держим Blocking для ��стальных угроз,
	-- иначе deactivate создаёт дыру + BlockCooldown при повторно�� нажатии.
	if State.blocking and not keepGuard then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)   -- force: guard обязан опуститься, иначе рейт-лимит его подвесит
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	State.lastCounter  = os.clock()
	State.counterCount = (State.counterCount or 0) + 1
	State.flashUntil   = os.clock() + 0.25
	State.status       = "BOX-COUNTER"
end

local BOXING_BLOCK_ATTRS = {
	"CombatAttacking", "Stunned", "Ragdoll",
	"ParryAttackLockout", "BlockAttackLockout", "GrappleWinnerStun",
}
local function shouldBoxingCounter(th)
	if not Config.SkillAddon or not Config.BoxingCounter then return false end
	local c = localChar()
	if not c then return false end
	if (styleOf and styleOf(c) or ""):lower() ~= "boxing" then return false end
	if (os.clock() - (State.lastCounter or 0)) < Config.BoxingCounterMinGap then return false end
	for _, attr in ipairs(BOXING_BLOCK_ATTRS) do
		if c:GetAttribute(attr) then return false end
	end
	if c:GetAttribute("CantAnything") and not c:GetAttribute("CombatRecovery") then return false end
	if c:GetAttribute("Equip") == false then return false end
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return false end
	-- [V63] ГЛА��НЫЙ ФИКС: counter реально доступен только когда M2 НЕ на cooldown.
	-- Дамп (CombatConfig.M2): RecoveryLockout=0.5, Cooldown=7 (base); boxing даёт
	-- iframes ТОЛЬКО при успешном запуске M2. Раньше проверя��ся лишь клие��тский
	-- таймер BoxingCounterMinGap=0.45 — он врал: скрипт слал M2 когда сервер ещё
	-- на cooldown → FireServer вхолостую, iframes НЕ выдавались, а блок в этот
	-- момент пропускался (COUNTER→NO-PRESS/LATE/refused:CantAnything в логах →
	-- Stunned ��� Ragdoll каскад). Теперь на cooldown counter отменяется, и мы
	-- гарантированно падаем в блок-ветку scheduler'а (perfect/normal block).
	if c:GetAttribute("M2Cooldown") == true then
		State.counterAbortCd = (State.counterAbortCd or 0) + 1
		return false
	end
	if c:GetAttribute("M2CD") == true then
		State.counterAbortCd = (State.counterAbortCd or 0) + 1
		return false
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local h = getHandler()
	if h and h.GetAnims then
		local ehit = false
		pcall(function() ehit = next(h.GetAnims(c, "EHit")) ~= nil end)
		if ehit then return false end
	end
	local myHRP, aHRP = localHRP(), th.attackerHRP
	if not (myHRP and aHRP and aHRP.Parent) then return false end
	local d = (Vector3.new(myHRP.Position.X, 0, myHRP.Position.Z)
	          - Vector3.new(aHRP.Position.X, 0, aHRP.Position.Z)).Magnitude
	return d <= (Config.BoxingCounterReach or 8)
end

-- [V89] ПРОИЗВОДНЫЙ список «только додж». В дампе НЕТ флага Unblockable/CanBlock: любой
-- M1/M2 в принципе блокируется/перфактится (сетевые исходы: M2Blocked / M2PerfectBlocked /
-- M2GuardBroken). Реально сквозь атрибут Blocking проходят только грэбы/слэмы — прежде всего
-- Wrestling M2 (гарантированный захват, см. M2GrabTargetForwardOffset в CombatConfig). Их
-- нельзя блокнуть, спасает лишь додж (i-frames = абсолютная неуязвимость: VictimHitboxService
-- ._isSuppressed гасит урон при IFRAMES/Ragdoll/Downed/UltraInstinct). Список собираем по
-- стилю/��ипу через Config.MustDodgeStyles (расширяется ��ез правки движка) + живой сигнал по
-- атрибуту атакующего, если игра е��о выставит в момент замаха.
local function isMustDodge(th)
	if not th then return false end
	local st = (th.style or ""):lower()
	-- Skill Addons force-dodge specific unblockable grabs regardless of the Must-Dodge list.
	-- Wrestling M2 is a guaranteed grab with HyperArmor; Dirty grab ignores ragdoll immunity —
	-- both pass through the Blocking attribute, so only i-frames (a backdodge) save you.
	if Config.SkillAddon then
		if Config.SA_WrestlingGrab and st == "wrestling" and th.kind == "M2" then return true end
		if Config.SA_DirtyGrab and st == "dirty" and (th.kind == "M2" or th.kind == "SKILL") then return true end
	end
	if not Config.MustDodge then return false end
	local byStyle = Config.MustDodgeStyles and Config.MustDodgeStyles[st]
	if byStyle and (byStyle[th.kind] or byStyle.all) then return true end
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

-- ============================ AutoPlay addon (V99) ============================
-- Автоатака через РОДНУЮ tryM1() игры (M1.lua). Факты из дампа (CombatConfig.ClientPredict.M1):
--   • ParryStun.M2 = 1.0с                    — жертва M2-парри з��станена 1с (окно добивания);
--   • AttackDuration = 0.45с                 — реальный рейт M1 (tryM1 сам гейтит по нему, u21);
--   • LocalParryAttackLockoutSeconds = 0.15с — после НАШЕГО парри tryM1 залочен 0.15с (u32);
--   • LocalBlockAttackLockoutSeconds = 0.15с — после блока/гардбрейка (u33);
--   • DefaultHitboxDelay = 0.32с             — хитбокс M1 долетает через 0.32с (для interrupt-расчёта).
-- tryM1() = ровно то, что делает v1.OnM1Activated (игровой ��лик): проигрывает верную анимацию
-- комбо, сам проверяет ВСЕ кулдауны/атрибуты, шлёт ServerCheck с правильным внутренним u25.
-- Никаких hold/задержек: зовём напрямую → мгновенно и легитно. Бьём как только tryM1 разрешит.
--   • iframe/hyperarmor-стили (boxing M2GrantsIFrames, wrestling M2GrantsHyperArmor)
--       перебить НЕЛЬЗЯ — их только парировать.
-- Всё состояние И функции держим на State.ap — модуль впритык к лимиту 200 локалов на функцию,
-- поэтому НИ ОДНОГО нового top-level local (это переполняло регистры → CompileError).
State.ap = {
	m1         = nil,    -- кэш РОДНОГО модуля M1 игры (return-таблица v1 с .OnM1Activated)
	tryM1Fn    = nil,    -- сам локальный tryM1() (upvalue #1 в OnM1Activated) — даёт bool успеха
	comboIdx   = nil,    -- upvalue-индекс u19 (combo-счётчик) в tryM1 — для Fixed-режима и custom-fire
	m1Tried    = false,  -- уже пытались резолвить модуль (не спамить резолв каждый кадр)
	-- [V105] CUSTOM FIRE: свой быстрый M1 в обход 450мс-троттла игры. Разметка upvalue tryM1
	-- ЯКОРИТСЯ на CombatRemoteClient (единственный upvalue-table с полем .Fire) и все прочие индексы
	-- берутся ФИКСИРОВАННЫМ смещением от него + строгая проверка типов (см. getM1). Точный порядок
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
	nextM1At   = 0,      -- анти-спам ПОЛЛА (сам tryM1 гейтит настоящий рейт по AttackDuration 0.45с)
	punishTgt  = nil,    -- модель врага, которого добиваем после парри
	punishUntil= 0,      -- докуда действует окно добивания (по времени стана)
	blatantId  = 0,      -- счётчик для RAW ServerCheck (только тест-режим Blatant)
	uninterruptible = { boxing = true, wrestling = true },  -- M2 с iframes/hyperarmor → только парри
	busyAttrs = {
		"Stunned", "Ragdoll", "Downed", "GuardBroken", "CantAnything",
		"M1Cooldown", "ParryAttackLockout", "BlockAttackLockout", "GrappleWinnerStun",
	},
}

-- Резолвим РОДНОЙ модуль M1 игры и его ЛОКАЛЬНУЮ tryM1(). Бьём через tryM1() напрямую —
-- это ровно то, что делает игровой обработчик клика (v1.OnM1Activated просто вызывает tryM1):
-- проигрывает ПРАВИЛЬНУЮ анимацию комбо (u19 1→4), сам проверяет ВСЕ кулдауны/атрибуты
-- (Equip, Blocking, u21=AttackDuration 0.45с, u32=parry-lockout 0.15с, u33=block-lockout, стан…)
-- и шлёт ServerCheck с ПРАВИЛЬНЫМ внутренним swingId u25. Никаких задержек/hold — мгновенно и легит.
-- tryM1 возвращает true, если свинг реально прошёл (у нас есть точный сигнал успеха).
-- Прежний прямой ServerCheck с выдуманным id сервер игнорировал (нет анимации/сессии). Hold-эмуляция
-- тоже плоха — она ждёт серверный hold-хендшейк (встроенная задержка). Модули в Hidden →
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
	-- достаём локальную tryM1(): её единственный upvalue #1 в OnM1Activated (даёт bool успеха)
	if State.ap.m1 and type(debug) == "table" and type(debug.getupvalue) == "function" then
		pcall(function()
			local fn = debug.getupvalue(State.ap.m1.OnM1Activated, 1)
			if type(fn) == "function" then State.ap.tryM1Fn = fn end
		end)
			-- [V105] РАЗМЕТКА через ЯКОРЬ CombatRemoteClient. Прежний поиск «первый int в [0,4]»
			-- был НЕВЕРЕН: u32/u33 (parry/block-lockout timestamps) на старте = 0 → попадали под
			-- фильтр и comboIdx резолвился в u32, а от него все смещения съезжали → fireOK=false и
			-- combo Fixed не работал. CombatRemoteClient — ЕДИНСТВЕННЫЙ upvalue-table с полем .Fire
			-- (function), поэтому это надёжный якорь. От него все индексы — фиксированным смещением,
			-- каждый проверяем по типу. Совпал весь профиль → включаем custom-fire.
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

-- [V105] СВОЙ БЫСТРЫЙ M1 — ВСЕГДА используется (свой билдер вместо игрового tryM1). Игровой
-- tryM1 после каждого свинга зовёт scheduleM1SwingTimers → u21=false на AttackDuration(0.45с) →
-- следующий удар только через 0.45с. Мы повторяем ХВОСТ tryM1 (выбор combo, u25++/u27/u28,
-- анимация, CombatRemoteClient.Fire), НЕ трогаем scheduleM1SwingTimers, и СНИМАЕМ клиентские локи
-- (u21=true, u32/u33=0) → троттла нет. Единственный настоящий потолок — сам CombatRemoteClient.Fire
-- (M1.ServerCheck: min 80мс, sustained 4/с): он вернёт false, если рано, и тогда мы НЕ двигаем u25
-- → последовательность серверу цела (без «дыр»). combo: Fixed → ровно AP_FixedHit, иначе 1→4.
-- wantCombo (опц.) — принудительный номер удара для тест-свинга.
function State.ap.fireM1Custom(char, model, wantCombo)
	local ap = State.ap
	if not (ap.fireOK and ap.tryM1Fn) then return false end
	local ok = false
	pcall(function()
		-- снять клиентские локи (мгновенный повторный/послепарийный свинг) — best-effort:
		-- индексы могли не зарезолвиться, тогда просто не трогаем (Fire всё равно решает по рейту).
		local now = os.clock()
		if ap.u21idx then debug.setupvalue(ap.tryM1Fn, ap.u21idx, true) end   -- AttackDuration-троттл
		if ap.u32idx and (debug.getupvalue(ap.tryM1Fn, ap.u32idx) or 0) > now then debug.setupvalue(ap.tryM1Fn, ap.u32idx, now - 0.01) end
		if ap.u33idx and (debug.getupvalue(ap.tryM1Fn, ap.u33idx) or 0) > now then debug.setupvalue(ap.tryM1Fn, ap.u33idx, now - 0.01) end
		-- выбрать номер удара комбо
		local combo
		if wantCombo then
			combo = math.clamp(math.floor(wantCombo), 1, 4)
		elseif Config.AP_ComboMode == "Fixed" then
			combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
		else
			combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 4) + 1
		end
		local anims = ap.getAnims()
		local v53   = anims and anims[combo] or nil
		local newId = (debug.getupvalue(ap.tryM1Fn, ap.u25idx) or 0) + 1
		-- сперва отправляем — Fire сам решает по РЕАЛЬНОМУ рейт-лимиту (80мс/4-в-сек). false = рано.
		local sent = ap.crc.Fire("M1", "ServerCheck", newId)
		if not sent then return end   -- НЕ двигаем состояние → нет дыры в id-последовательности
		-- фиксируем состояние ровно как игровой tryM1 (для клиентской сверки с ServerResponse)
		debug.setupvalue(ap.tryM1Fn, ap.comboIdx, combo)
		debug.setupvalue(ap.tryM1Fn, ap.u25idx, newId)
		debug.setupvalue(ap.tryM1Fn, ap.u26idx, newId)
		ap.u27tbl[newId] = combo
		ap.u28tbl[newId] = v53
		-- анимация свинга — В ФОНЕ (хит уже ушёл ServerCheck-ом; анимация косметическая и может йелдить)
		task.spawn(function()
			local spd = 1
			pcall(function() spd = ap.getSpeed(char, combo) or 1 end)
			pcall(ap.playSwing, char, combo, spd, false)
		end)
		ok = true
	end)
	return ok
end

-- можем ли физически атаковать прямо сейчас (по атрибутам своего перса)
function State.ap.canAttack()
	local c = localChar()
	if not c then return false end
	if c:GetAttribute("Equip") ~= true then return false end   -- руки не одеты → бить нельзя
	if c:GetAttribute("Blocking") == true then return false end -- держим guard → M1 не пройдёт
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return false end
	for _, a in ipairs(State.ap.busyAttrs) do
		if c:GetAttribute(a) then return false end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	return true
end

-- реальный радиус нашего M1 С УЧЁТОМ РОСТА (крупнее аватар → больше хитбокс/дос��аёт да��ьше)
function State.ap.reach()
	local base = Config.AP_BaseReach or 5.5     -- ForwardOffset(4) + половина коробки + запас
	local _, _, myH = heightDiag(localChar())
	if type(myH) == "number" and myH > 0 then
		base = base * math.clamp(myH / (Config.AP_RefHeight or 5.5), 0.85, 1.45)
	end
	return base
end

-- flat-дистанция до модели с ПИНГ-ПРЕДИКТОМ её позиции (сервер видит врага впереди нашего экрана)
function State.ap.flatDist(model)
	local myHRP = localHRP()
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not (myHRP and hrp) then return math.huge end
	local aim = hrp.Position
	local lead = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.22)
	if lead > 0 then
		local v = hrp.AssemblyLinearVelocity   -- hrp уже проверен выше; прямое чтение без closure
		aim = aim + Vector3.new(v.X, 0, v.Z) * lead
	end
	return (Vector3.new(myHRP.Position.X, 0, myHRP.Position.Z)
	        - Vector3.new(aim.X, 0, aim.Z)).Magnitude
end

-- снап лицом ТОЧНО на цель прямо сейчас + держим предиктивный facing на окно хитбокса.
-- Сервер строит M1-хитбокс по нашему LookVector в момент ServerCheck.
function State.ap.snapTo(hrp)
	setFaceGoal(hrp, true, Config.AP_FaceHold or 0.35)
	local myHRP = localHRP()
	if myHRP then
		local d = flatDirTo(myHRP.Position, hrp.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
	end
end

-- послать ЛЕГИТНЫЙ M1 по цели: снап лицом + прямой вызов родной tryM1() (или OnM1Activated).
-- БЕЗ собственных лок/задержек — и��ровая tryM1 сама разрешит удар как только это допустимо
-- (AttackDuration/lockout/стан). Наш nextM1At — лишь троттл ПОЛЛА, чтобы не звать tryM1 сотни
-- раз в кадр; настоящий рейт держит игра. Поэтому добивание/перебивание бьёт МГНОВЕННО, как
-- только сервер снимает лок (напр. 0.15с parry-lockout после нашего парри).
function State.ap.fireM1(model, why)
	local ap = State.ap
	local now = os.clock()
	if now < ap.nextM1At then return false end
	if not ap.canAttack() then return false end
	local m1 = ap.getM1()
	if not m1 then return false end
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	ap.snapTo(hrp)   -- сервер строит хитбокс по нашему LookVector в момент ServerCheck
	ap.nextM1At = now + (Config.AP_PollGap or 0)   -- троттл поллинга (0 = каждый кадр, макс. скорость)
	-- [V105] ВСЕГДА свой билдер (обход троттла + Fixed-combo внутри fireM1Custom). Фолбэк на игровую
	-- tryM1 только если разметка custom-fire не сошлась (fireOK=false) — тогда без обхода троттла.
	local swung = false
	if ap.fireOK then
		local char = localChar()
		if char then swung = ap.fireM1Custom(char, model) end
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
		diagPush(("AUTOPLAY t=%.2f  M1 → %s  (%s)"):format(now, (model and model.Name) or "?", why or "?"))
	end
	return swung
end

-- RAW-удар БЕЗ анимации для тест-режима Blatant: прямой ServerCheck по Remotes.Server.
-- Легитимность не гарантируется (нет hold-сессии/анимации) — только для проверки реакции.
function State.ap.fireM1Raw(model)
	local ap = State.ap
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if hrp then ap.snapTo(hrp) end
	ap.blatantId = ap.blatantId + 1
	pcall(function()
		ServerRemote:FireServer({ Type = "Combat", Action = "M1", Func = "ServerCheck" }, ap.blatantId)
	end)
end

-- [V105] ТЕСТ-СВИНГ для UI-кнопки: шлёт один M1 с анимацией комбо, которую использовал бы скрипт
-- (Fixed → AP_FixedHit, иначе следующий по счёту). Цель не нужна — бьём «в воздух» на текущий
-- LookVector. Возвращает (номер_удара, успех) для нотификации.
function State.ap.testSwing()
	local ap = State.ap
	if not ap.getM1() then return 0, false end
	local char = localChar()
	if not char then return 0, false end
	local combo
	if Config.AP_ComboMode == "Fixed" then
		combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
	elseif ap.fireOK and ap.tryM1Fn then
		combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 4) + 1
	else
		combo = 1
	end
	local ok = false
	if ap.fireOK then
		ok = ap.fireM1Custom(char, nil, combo)
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
	-- окно стана: M2-парри = ParryStun.M2 (1с, надёжно); M1-парри короче (RecoveryLockout врага)
	local stun = (kind == "M2") and (Config.AP_M2Stun or 1.0) or (Config.AP_M1Stun or 0.5)
	State.ap.punishTgt   = model
	State.ap.punishUntil = os.clock() + stun
end

-- шаг добивания (каждый Heartbeat из schedulerStep, ТОЛЬКО когда нет угроз для блока).
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
		return
	end
	if ap.flatDist(tgt) > ap.reach() then return end   -- вне досягаемости — не бьём воздух
	-- [V100] МГНОВЕННОЕ добивание: сразу после парри мы ещё держим guard (Blocking), а fireM1
	-- самогейтится на Blocking→не бьёт → терялось ~0.12-0.2с окна стана. Т.к. угроз нет (step
	-- вызван при #imminent==0) и цель застанена — безопасно уронить guard ЭТОТ кадр, чтобы
	-- со следующего поллинга (через AP_PollGap) tryM1 уже свингнул. Экономит весь HoldAfter.
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
		return
	end
	ap.fireM1(tgt, "punish")
end

-- решение перебить тяжёлую обычным M1: true → перебили (НЕ блокируем этот кадр), false → парируем.
-- remaining — сек до контакта их удара.
function State.ap.tryInterruptHeavy(th, now, remaining, preSwing)
	if not Config.AutoPlay or Config.AP_InterruptHeavy == false then return false end
	if not th or th.kind ~= "M2" then return false end
	local ap = State.ap
	local st = (th.style or ""):lower()
	if ap.uninterruptible[st] then return false end       -- iframe/hyperarmor → ТОЛЬКО парри
	if isMustDodge(th) then return false end              -- грэб/анблок → додж, не перебить
	-- [V98] анти-финт (юзер: драгер финтит → скрипт реагирует → мы в кулдауне → он бьёт снова).
	-- Перебиваем ТОЛЬКО подтверждённый (trustedHit) реальный свинг. Финт/недокрут не trusted →
	-- НЕ жжём наш M1, остаёмся в защите и просто парируем настоящий удар.
	if not th.trustedHit then return false end
	-- [V104] КОГДА УСПЕВАЕМ ПЕРЕБИТЬ (главная мысль юзера): тяжёлая M2 — это ДЛИННЫЙ замах.
	-- РЕГИСТРАЦИЯ их удара по нам наступает через M2HitboxDelay = 0.43..0.82с (CombatConfig) — в
	-- РАЗЫ больше окна perfect-parry (~0.10с). И удар остаётся ПЕРЕБИВАЕМЫМ почти всю эту фазу:
	-- стаггер отменяет тяжёлую вплоть до самого damage-frame (он в конце замаха). Значит времени
	-- сбить атаку своим M1 МНОГО — раньше мы это недооценивали и просто парировали.
	--
	-- Честная модель времени (всё в кадре ОТ now, серверная сторона):
	--   • Наш M1 (CUSTOM-FIRE) шлёт ServerCheck МГНОВЕННО → сервер строит хитбокс в момент приёма →
	--     наш хит регистрируется ≈ up (пол-RTT долёт пакета) + маленькая обработка. Без custom-fire
	--     добавляется клиентский долёт анимации (AP_M1Delay).
	--   • Их damage-frame на сервере ≈ (remaining - up): их атаку мы видим с интерп-лагом ≈ up.
	--   Успеваем, если наш_лэнд < их_дамаг:  up + proc  <  remaining - up + activeGrace
	--   → remaining > 2*up + proc - activeGrace = getPing() + proc - activeGrace.
	-- activeGrace (HeavyActiveGrace) — насколько долго тяжёлая ещё перебиваема ПОСЛЕ номинального
	-- контакта (длинная active/recovery фаза). Это и даёт «много времени», о котором говорил юзер.
	local proc      = ap.fireOK and (Config.AP_InterruptM1Delay or 0.05) or (Config.AP_M1Delay or 0.32)
	local ourLand   = proc + getPing() * (Config.AP_InterruptPingFactor or 1.0)
	local activeGrace = Config.AP_HeavyActiveGrace or 0.14
	if remaining <= (ourLand - activeGrace) then return false end
	if ap.flatDist(th.attackerModel) > ap.reach() then return false end
	-- [V105] Если держим guard — сервер выставил атрибут Blocking, а canAttack его не пропустит
	-- (M1 сквозь guard не идёт). Роняем guard ЭТОТ кадр и «съедаем» его (не блокируем, но и не
	-- бьём) — атрибут снимется через сервер, а свинг пройдёт следующим кадром. Длинная фаза тяжёлой
	-- (0.43..0.82с) это спокойно терпит. preSwing = releaseBlock() из call-site.
	if State.blocking then
		if preSwing then preSwing() end
		return true   -- перехват в процессе: этот кадр НЕ блокируем, свинг — со след. кадра
	end
	if not ap.canAttack() then return false end
	return ap.fireM1(th.attackerModel, "interrupt-heavy")
end

local function evasiveGranted()
	local c = localChar()
	return c and c:GetAttribute("OutnumberedEvasiveGrant") == true or false
end

local function dodgeReady()
	if evasiveGranted() then return true end
	local c = localChar()
	if (os.clock() - State.lastDodge) < Config.DodgeMinSpacing then return false end
	if Config.UseServerCooldown and c then
		if c:GetAttribute("IFRAMECD") == true then return false end
		local rem = c:GetAttribute("EvasiveCooldownRemaining")
		if type(rem) == "number" and rem > 0 then return false end
		return true
	end
	return (os.clock() - State.lastDodge) >= Config.DodgeCooldown
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

local function refreshContact(th)
	local now = os.clock()
	local remaining = th.contact0 - (now - th.detectClock)

	local playing = true
	if th.track then
		playing = safeGet(th.track, "IsPlaying", true)
		local tp = safeGet(th.track, "TimePosition", th.initTP)
		if type(tp) ~= "number" then tp = th.initTP end

		-- [V66] измеряем РЕАЛЬНУЮ скорость прогресса анимации (units анимации в
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
		end

		-- [V96] Live-TP коррекция теперь И для M1 (раньше только M2/SKILL). M1 предсказывался
		-- чистым обратным отсчётом contact0-elapsed, без учёта РЕАЛЬНОГО прогресса анимации → при
		-- desync/ускорении атаки contactAbs уплыв��л (в логе predErr скакал от -290 до +138ms). Для
		-- M1 окно короткое, поэтому корректируем через ту же live-скорость, но с более высоким полом
		-- (M1 редко «придерживают», агрессивный пол убирает шум коротких треков).
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
				-- даёт бесконечность, а враг может резко доиграть). Пол = доля от
				-- н��ми����л��ной скорости трека.
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

		if th.trackSeen and not playing and not th.feinted then
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
end

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

local function onAttack(attackerHRP, info, model, id, track)
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
	if Config.AntiDecoy then
		local sig = State.antiDecoySig; if not sig then sig = {}; State.antiDecoySig = sig end
		local nowc = os.clock()
		local prev = sig[name]
		if prev and (nowc - prev) < (Config.AntiDecoyGap or 0.12) then
			if (nowc - (State.lastAntiDecoyLog or 0)) > 1 then
				State.lastAntiDecoyLog = nowc
				aclog(("[decoy] ignored rapid %s from %s"):format(tostring(info.t), name))
			end
			return
		end
		sig[name] = nowc
	end

	local combo = (info.t == "M1") and (info.combo or nextCombo(name)) or 1

	-- [V70] PURE-MATH: никаких калибратор��в. Предикт = таймлай�� анимации + живой
	-- TimePosition, и точка. (V68-residual удалён: один придерж��нный M2 отравлял EMA
	-- и задирал hitTL всех последующих M2 с 600→730мс → no-window NO-PRESS. База 600мс
	-- почти идеальна про��ив реальных ~585мс.)
	-- [V71] множитель скорости атаки АТАКУЮЩЕГО (по его росту) — делит задержку удара.
	-- track.Speed для чужих игроков ��еплицируется как 1.0, по��тому берём из роста.
	local aMult    = attackSpeedMult(model)
	local heightAttr, bodyHeightScale, modelHeight = heightDiag(model)
	local hitTL    = hitTimeline(info, combo, aMult)
	local speed    = 1
	local already  = 0
	if track then
		local okS, sp = pcall(function() return track.Speed end)
		if okS and type(sp) == "number" and sp > 0.05 then speed = sp end
		local okT, tp = pcall(function() return track.TimePosition end)
		if okT and type(tp) == "number" and tp > 0 then already = tp end
	end
	local remaining0 = math.max(0, hitTL - already)
	if remaining0 > Config.MaxWait then return end

	local vlead = velLead(attackerHRP)
	local nowClock  = os.clock()
	local nowServer = Workspace:GetServerTimeNow()
	local th = {
		name = name, kind = info.t, style = info.s, mom = info.mom, id = id,
		track = track, hitTL = hitTL, initTP = already, initSpeed = speed,
		detectClock = nowClock, detectServer = nowServer, contact0 = remaining0,
		contactAbs = nowClock + remaining0, velLead = vlead,
		attackerHRP = attackerHRP, attackerModel = model,
		heightAttr = heightAttr, bodyHeightScale = bodyHeightScale, modelHeight = modelHeight,
		attackMult = aMult,
		pressed = false, dodged = false,
		pressDt = nil,
		faceDot = nil,
	}
	Threats[#Threats+1] = th

	local rec = { clock = nowClock, detectServer = nowServer, type = info.t, style = info.s,
	              id = id, contact = remaining0, pingRaw = getPingRaw(), combo = combo,
	              speed = speed, matched = false, th = th }
	th.rec = rec
	local q = Pending[name]; if not q then q = {}; Pending[name] = q end
	q[#q+1] = rec
	if #q > 10 then table.remove(q, 1) end

	State.lastThreat = { name = name, type = info.t, dist = dist, hitIn = remaining0 }
	if State.status ~= "PARRY" then State.status = "THREAT" end
	State.parryCount = State.parryCount + 1

	local pRaw  = getPingRaw()
	local pMult = hitTL / (hitTL + math.clamp(pRaw * 0.5, 0, 0.35))
	diagPush(("SWING  t=%.2f  %s  %s(%s)  combo=%d  dist=%.0f  contact=%.0fms  spd=%.2f  aMult=%.2f  height=%s  bodyScale=%s  modelY=%s  pingMult=%.2f  hitTL=%.0fms  vlead=%.0fms  ping=%.0f")
		:format(os.clock(), name, info.t, info.s, combo, dist, remaining0*1000, speed, aMult,
			heightAttr and ("%.3f"):format(heightAttr) or "?",
			bodyHeightScale and ("%.3f"):format(bodyHeightScale) or "?",
			modelHeight and ("%.2f"):format(modelHeight) or "?",
			pMult, hitTL*1000, vlead*1000, pRaw*1000))
end

local function resolveSwingAttacker(arg)
	if typeof(arg) == "Instance" then
		if arg:IsA("Player") then return arg.Character end
		if arg:IsA("Model") then return arg end
		local plr = Players:GetPlayerFromCharacter(arg)
		if plr then return plr.Character end
		return arg.Parent and arg.Parent:IsA("Model") and arg.Parent or nil
	elseif type(arg) == "string" then
		local plr = Players:FindFirstChild(arg)
		if plr and plr.Character then return plr.Character end
		return Workspace:FindFirstChild(arg)
	elseif type(arg) == "table" then
		for _, k in ipairs({ "Character", "Attacker", "Player", "Char", "Model" }) do
			local v = arg[k]
			if v then local m = resolveSwingAttacker(v); if m then return m end end
		end
		local nm = arg.Name or arg.CharacterName or arg.AttackerName
		if type(nm) == "string" then return resolveSwingAttacker(nm) end
	end
	return nil
end

local function registerServerSwing(kind, arg)
	if not (Config.Enabled and Config.ServerSwingHook) then return end
	local model = resolveSwingAttacker(arg)
	if not model then return end
	local ok, hrp = isEnemyModel(model)
	if not ok or not hrp then return end
	local plr  = Players:GetPlayerFromCharacter(model)
	local name = plr and plr.Name or model.Name
	local q = Pending[name]
	if q then
		local nowC = os.clock()
		for i = #q, 1, -1 do
			local r = q[i]
			if r.type == kind and (nowC - r.clock) <= Config.ServerSwingDedup then return end
		end
	end
	local info = { t = kind, s = styleOf(model) or "Basic", hit = nil, combo = nil, mom = false }
	onAttack(hrp, info, model, 0, nil)
end

local function dirIsClear(origin, dir)
	if not Config.DodgeWallCheck then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { localChar() }
	local ok = pcall(function() params.FilterDescendantsInstances = ignore end)
	if not ok then return true end
	local hit
	pcall(function() hit = Workspace:Raycast(origin, dir.Unit * Config.DodgeWallDist, params) end)
	if not hit then return true end
	local part = hit.Instance
	if part and (not part.CanCollide or part:IsDescendantOf(localChar() or part)) then return true end
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

	-- [V89] preferBack: для НЕБЛОКИРУЕМЫХ (грэб/слэм) додж строго НАЗАД (away от врага) —
	-- уводит из радиуса захвата и разрывает клинч; вбок только как fallback у стены. Обычный
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

local function performDodge(now, reason, preferBack, force)
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
	if granted then State.grantEscapes = (State.grantEscapes or 0) + 1 end
	if type(reason) == "string" and reason:sub(1, 4) == "dual" then
		State.dualDodgeCount = (State.dualDodgeCount or 0) + 1
	end
	local dir = bestDodgeDir(now, preferBack)
	sendDodge(dir)
	local coverEnd = now + Config.DodgeConfirm + Config.IFrameDur
	local soonest, covered = nil, 0
	for _, th in ipairs(Threats) do
		if not th.dodged and th.contactAbs <= coverEnd + 0.03 then
			th.dodged = true; covered = covered + 1
			if not soonest or th.contactAbs < soonest then soonest = th.contactAbs end
		end
	end
	State.lastDodgeInfo = {
		fire       = now,
		reason     = reason,
		contactAbs = soonest,
		iframeLo   = now + Config.DodgeConfirm,
		iframeHi   = now + Config.DodgeConfirm + Config.IFrameDur,
		dir        = dir and "smart" or "input",
	}
	diagPush(("DODGE  t=%.2f  %s%s  covers=%d  dir=%s  fire→contact=%s  iframe=[+%.0f,+%.0f]ms")
		:format(now, reason, granted and " [GRANT]" or "", covered, State.lastDodgeInfo.dir,
			soonest and ("%.0fms"):format((soonest-now)*1000) or "n/a",
			Config.DodgeConfirm*1000, (Config.DodgeConfirm+Config.IFrameDur)*1000))
	return true
end

local function schedulerStep(now)
	local serverNow = Workspace:GetServerTimeNow()
	local up        = uplink()
	local wantBlock = nil
	local faceTgt   = nil
	local imminent  = {}

		for i = #Threats, 1, -1 do
			local th = Threats[i]
			local trackGone = th.track and th.track.Parent == nil
			refreshContact(th)
			local dt = th.contactAbs - now
			-- [V90 FIX] Угрозы БЕЗ трека (хитбокс-детект / сетевые свинги) не могут истечь по
			-- dt: refreshContact клампит contactAbs в now+max(remaining,0), поэтому dt застревает
			-- на 0 и НИКОГДА не уходит ниже -0.35, а trackGone для них тоже false. Без трека угроза
			-- становилась бессмертной → wantBlock де��жался вечно → guard не отпускался (баг «блок
			-- не снимается»). Даём таким угрозам жёсткий wall-clock TTL: живут contact0 + грейс.
			local noTrackExpired = (not th.track)
				and (now - th.detectClock) > ((th.contact0 or 0) + 0.35)

			if th.feinted then
				if not th.feintLogged then
					th.feintLogged = true
					diagPush(("FEINT  t=%.2f  %s  %s  reached=%.0f%% of hitTL → ignored")
						:format(now, th.name, th.kind, (th.maxTP or 0) / math.max(th.hitTL, 0.001) * 100))
				end
				table.remove(Threats, i)
			elseif dt < -0.35 or noTrackExpired or (trackGone and (now - th.detectClock) > 0.5) then
			-- [V66] POST-MORTEM: угроза уходит. Если на неё ни разу не нажали и не
			-- задоджили — это независимый пропуск. Логируем ТОЧН��Ю прич��ну, чтобы
			-- закрыть "скрипт проёбывает атаку" по фактам, а не догадкам.
			-- [V69] при ненаправленном блоке угроза, вошедшая в окно, покрыта поднятым
			-- guard'ом (один блок = защита от всех). Это НЕ промах — раньше логировалось
			-- лож��ым "перебит EDF". Считаем отдельно, чтобы не путать с реа��ьными потерями.
			local coveredByGuard = th.coveredByHeldGuard == true
				or (Config.OmniBlock and State.blocking and th.enteredWindow
					and th.contactAbs <= (State.holdUntil or 0) + 0.05)
			if th.coveredByDodge then
				-- Explicitly serviced by the cluster iframe; not a miss and not guard coverage.
			elseif coveredByGuard then
				State.guardCovered = (State.guardCovered or 0) + 1
			elseif Config.DeepDiag and not th.pressed and not th.dodged and not th.deadLogged then
				th.deadLogged = true
				local reason
				if th.everThreatened == nil or th.everThreatened == false then
					reason = th.offTarget
						and "off-target (Low facing-gate: враг предсказанно смотрит от нас → чужая атака)"
						or "never-in-hitbox (willHitMe=false весь путь — фильтр углом/дистанцией отсёк)"
					if th.offTarget then State.offTargetRej = (State.offTargetRej or 0) + 1 end
				elseif th.enteredWindow then
					reason = "in-window но не выбран EDF (перебит другой целью в т��т же кадр)"
				elseif th.contactPassedFast then
					reason = ("окно не открылось: контакт приле��ел быстре�� pressAt (minDtToPress=%.0fms)"):format((th.minDtToPress or 0)*1000)
				else
					reason = ("no-window (maxTP=%.0f%% hitTL, feint-grace?)"):format((th.maxTP or 0)/math.max(th.hitTL,0.001)*100)
				end
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
			if threatens then th.everThreatened = true end
			if threatens then
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
				local pressAt = th.contactAbs - lead - up - th.velLead
				local holdEnd = th.contactAbs + hold
				-- [V66] диаг-трекинг: минимальный зазор до момента нажатия и факт
				-- входа в окно — для точного post-mortem причины пропуска.
				local dtToPress = pressAt - now
				if th.minDtToPress == nil or dtToPress < th.minDtToPress then
					th.minDtToPress = dtToPress
				end
				if now < pressAt and (th.contactAbs - now) < lead then
					th.contactPassedFast = true
				end
				if now >= pressAt and now <= holdEnd then
					th.enteredWindow = true
					-- [V65] EDF (Earliest Deadline First) с приоритетом НЕОБСЛУЖЕННЫМ.
					-- Баг до V65: выбирался просто минимальный contactAbs. У Boxing-комбо
					-- быстрый M1 (contact=352ms) всегда имел contactAbs меньше медленной
					-- M2 (contact=832ms), поэтому п��сле перфекта M1 медленная M2 НИКОГДА
					-- не становилась целью → NO-PRESS → полный хит (твой клип). Теперь
					-- снача��а берём угрозы без нажати�� (unpressed), сред��� ��их — с самым
					-- ранним дедлайном. Так после блока быстрого heavy получает своё
					-- собственное нажатие (guard держится → блок тяжёлой).
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
				-- [V95] окно кандидата на поворот РАСШИРЕНО на RTT (up): хард-снап нужен за
				-- (BlockFaceHardDt + up) до контакта, иначе на высоком пинге кандидат появлялся
				-- бы слишком поздно и мы прессили бы блок ещё ��е довернувшись → сервер от��лонял.
				if dt <= (Config.FaceLeadWindow + up) and dt >= -Config.HoldAfter then
					-- [V65] лицом к тому, кто бьёт СЛЕДУЮЩИМ среди ещё не прилетевших
					-- ударов (contactAbs >= now). После блока быстро��о разворачиваемся
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
				if dt <= Config.DodgeHorizon and dt >= -Config.HoldAfter then
					imminent[#imminent+1] = th
				end
			end
		end
	end

	table.sort(imminent, function(a, b) return a.contactAbs < b.contactAbs end)

	-- [V98] BLATANT TEST режим: на ближайшую угрозу в окне BlatantWindow шлём блок И RAW M1
	-- ОДНОВРЕМЕННО, без анимации. Чисто для теста реакции/приёма сервером — палевно.
	if Config.Blatant and #imminent > 0 then
		local th = imminent[1]
		local dt = th.contactAbs - now
		if dt <= (Config.BlatantWindow or 0.30) and dt >= -Config.HoldAfter then
			if not th.blatantDone then
				th.blatantDone = true
				fireBlock(serverNow)                 -- парри
				State.ap.fireM1Raw(th.attackerModel) -- RAW атака в тот же кадр
				diagPush(("BLATANT t=%.2f  block+M1 → %s  dt=%+.0fms")
					:format(now, (th.name or "?"), dt * 1000))
			end
			return
		end
	end

	-- Multi-attacker clustering is based on distinct attackers and absolute contacts.
	-- A cluster is handled as one defensive transaction, never as competing EDF presses.
	local cluster = {}
	local seenAttackers = {}
	local clusterHeavy = false
	for _, th in ipairs(imminent) do
		local key = th.attackerModel or th.attackerHRP or th.name
		if key and not seenAttackers[key] then
			seenAttackers[key] = true
			cluster[#cluster + 1] = th
			if th.kind == "M2" then clusterHeavy = true end
		end
	end
	local clusterN = #cluster
	local clusterFirst = cluster[1]
	local clusterLast = cluster[#cluster]
	local clusterSpread = (clusterFirst and clusterLast) and (clusterLast.contactAbs - clusterFirst.contactAbs) or 0
	local clusterStrategy = nil
	if Config.MultiThreatGuard and clusterN >= (Config.MultiThreatMinN or 2) then
		local iframeSpan = math.max(0, (Config.IFrameDur or 0.30) - 0.07)
		clusterStrategy = clusterSpread <= iframeSpan and "IFRAME_CLUSTER" or "HELD_GUARD"
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

		-- [V96] Pre-emptive кластер-додж под первый контакт, пока все контакты в одном iframe-окне.
		-- ТЕПЕРЬ только если parry невозможен (not canBlockNow): по требованию юзера при доступном
		-- блоке кластер держим guard'ом + мультиплекс-фейсингом (V95), а НЕ жжём додж. Раньше коммент
		-- прямо гласил «allowed even when block is available» — это и был лишний додж не по делу.
		if clusterStrategy == "IFRAME_CLUSTER" and Config.EmergencyDualDodge
			and Config.DodgeOnParryCooldown ~= false
			and not canBlockNow() and dodgeReady() and canDodgeNow() then
			local firstDt = clusterFirst.contactAbs - now
			local iframeLo = Config.DodgeConfirm - 0.03
			local iframeHi = Config.DodgeConfirm + Config.IFrameDur - 0.04
			local lastDt = clusterLast.contactAbs - now
			if firstDt >= iframeLo and firstDt <= iframeHi and lastDt <= iframeHi then
				if performDodge(now, ("iframe-cluster(n=%d spread=%.0fms)"):format(clusterN, clusterSpread * 1000)) then
					for _, th in ipairs(cluster) do th.coveredByDodge = true end
					return
				end
			end
		end
	end

	-- MustDodge is its own protection path, independent of DodgeHeavy and cluster policy.
	-- Scan all live imminent threats before any legacy heavy/escape decision.
	local mustDodgeThreat = nil
	for _, candidate in ipairs(imminent) do
		if isMustDodge(candidate) then mustDodgeThreat = candidate; break end
	end
	if mustDodgeThreat and dodgeReady() and canDodgeNow() then
		local mustDt = mustDodgeThreat.contactAbs - now
		local mLo = Config.DodgeConfirm - 0.03
		local mHi = Config.DodgeConfirm + Config.IFrameDur - 0.04
		if mustDt >= mLo and mustDt <= mHi then
			if performDodge(now, "must-dodge(unblockable→back)", true) then
				mustDodgeThreat.coveredByDodge = true
				return
			end
		end
	end

	-- [V91] BLATANT force-dodge — ОТДЕЛЬНАЯ ветка, потому что блок ниже требует
	-- canDodgeNow()==true, а это ровно то, что ложно, когда мы залочены (в своей атаке /
	-- софт-стане). Срабатывает только если: нормальный додж запрещён ��офт-состоянием
	-- (canDodgeNow(false)=false), но форс бы прошёл (canDodgeNow(true)=true), мы не можем
	-- блокнуть, и удар входит в окно. Тогда форсим дэш-инпут поверх и��ровой блокировки.
	if Config.SkillAddon and Config.SA_BlatantDodge and dodgeReady() and #imminent >= 1 then
		local a  = imminent[1]
		local dt = a.contactAbs - now
		local normalOk = canDodgeNow(false)
		local forceOk  = canDodgeNow(true)
		local locked   = (State.selfBusyUntil or 0) > now or (not canBlockNow())
		local coverLo  = Config.DodgeConfirm - 0.03
		local coverHi  = Config.DodgeConfirm + Config.IFrameDur - 0.04
		if (not normalOk) and forceOk and locked
		   and dt >= (coverLo - 0.06) and dt <= math.max(coverHi, Config.SA_BlatantWindow or 0.32) then
			if performDodge(now, "blatant-override(locked)", true, true) then return end
		end
	end

	if dodgeReady() and canDodgeNow() and #imminent >= 1 then
		local a = imminent[1]
		local soonestDt = a.contactAbs - now

		-- [V65] iframe-окно доджа фиксированное: [fire+DodgeConfirm, fire+DodgeConfirm
		-- +IFrameDur] = [+180,+480]мс. Удар «покрываем», только если его контакт
		-- попадает �� это ��кно (с малым за��асом п�� кр��ям). В логе оба мистайминга
		-- (TOO EARLY/TOO LATE) были у GRANT-доджей (outnumbered-escape), которые
		-- жглись по факту выдачи эв��йда, а не по удару: если удар ближе 180мс —
		-- iframes не успевали (hit before window), если фитил�� заранее — окно
		-- закрывалось за 1мс до удара. Теперь escape-доджи привязаны к контакту.
		local coverLo = Config.DodgeConfirm - 0.03
		local coverHi = Config.DodgeConfirm + Config.IFrameDur - 0.04
		local function dodgeCovers(dt) return dt >= coverLo and dt <= coverHi end
		local coverable = dodgeCovers(soonestDt)

		-- GRANT-эскейп: бесплатный эвейд от игры при численном перевесе. Грант
		-- держится, пока мы в меньшинст��е, поэтому МОЖНО подождать и фитить строго
		-- когда удар входит в iframe-окно (а не палить сра��у �� тратить впустую).
		if Config.OutnumberEscape and evasiveGranted() and coverable then
			if performDodge(now, "outnumbered-escape") then return end
		end
			-- combo-эскейп: блок недоступен (кулдаун/стан) → додж единственная защита. [V96] ТЕПЕРЬ
			-- строго по iframe-окну (coverable = dt в [coverLo, coverHi]). Раньше условие было
			-- `soonestDt <= coverHi` БЕЗ нижней границы → додж жёгся когда удар был в упор (dt<coverLo),
			-- iframes не успевали подняться → в логе `combo-escape ... fire→contact=0ms TOO EARLY`.
				if Config.ComboEscapeDodge and Config.DodgeOnParryCooldown ~= false
				   and not canBlockNow() and coverable then
					if performDodge(now, "combo-escape") then return end
				end
		-- exposed-эскейп: мы в собственном действии (busy) и удар вход��т в окно.
		if Config.ExposedEscapeDodge and (State.selfBusyUntil or 0) > now
		   and soonestDt <= Config.ExposedDodgeWindow and coverable then
			if performDodge(now, "exposed-escape") then return end
		end

		local fireLead
		if Config.DodgeCenter then
			local contactInset = (a.kind == "M2") and Config.HeavyDodgeInset or (Config.IFrameDur * 0.5)
			fireLead = contactInset + Config.DodgeConfirm + Config.DodgeArmWindow
		else
			fireLead = Config.DodgeLead + Config.DodgeArmWindow
		end
			if soonestDt <= (fireLead + up) then
				local overloaded, why = false, nil
				-- [V96] ОБЩЕЕ ПРАВИЛО (по требованию юзера): додж — резервная защита, а не основная.
				-- Пока parry доступен (canBlockNow) — блокируем/перфектим ВСЁ, что блокируемо, и НЕ
				-- тратим додж. Все эвристики ниже (heavy/multi/burst/guardbreak) выполняем только
				-- когда блок реально невозможен прямо сейчас. Неблокируемые атаки идут выше отдельным
				-- путём must-dodge (isMustDodge), он не завязан на это условие.
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
				-- guardbreak-save: стамина на нуле → guard всё равно проломят, додж оправдан даже
				-- если формально блок «доступен» (это и есть случай, когда parry не спасёт).
				if not overloaded and Config.GuardbreakProtect then
					local st = blockStamina()
					if st and st <= Config.StaminaFloor then
						overloaded, why = true, ("guardbreak-save(st=%.0f)"):format(st)
					end
				end
				if overloaded then performDodge(now, why); return end
			end
	end

	-- [V95] ЕДИНЫЙ АВТОРИТЕТ ПОВОРОТА. Раньше здесь напрямую дёргался faceToward (писал HRP в
	-- Heartbeat), конфликтуя с enforceFaceLock/AutoRotate/шифтлоком в RenderStepped. Теперь только
	-- ВЫСТАВЛЯЕМ цель — применит applyFacing в RenderStepped (последний писатель кадра).
	-- ЦЕЛЬ = атакующий с БЛИЖАЙШИМ ещё-не-прилетевшим контактом (faceTgt), т.к. сервер валидирует
	-- НАШ facing в момент разрешения удара (victim-репорт читает Blocking/PerfectBlocking на
	-- Heartbeat при оверлапе хитбокса ≈ контакт). Смотрим спиной → сервер отклоняет блок. faceTgt
	-- пересчитывает��я каждый кадр, поэтому как только удар первого разрешился — мгновенно
	-- перекидываемся на следующего (тайм-мультиплекс поворота по времени контакта). wantBlock —
	-- запасная цель, если facing-кандидата в окне ещё нет.
	local turnTo = faceTgt or wantBlock
	if turnTo and turnTo.attackerHRP then
		local dtc = turnTo.contactAbs - now
		-- HARD-снап должен успеть ДО разрешения удара: victim-репорт читает наш facing у контакта,
		-- а пакет летит к серверу ~пол-RTT. Значит жёстко доворачиваемся заранее — за (окно + RTT)
		-- до контакта. В мультибое (2+) — всегда hard, чтобы мгновенно перекидываться между целями
		-- и не терять кадры на лерп. Иначе (одиночная, далеко) — плавный трекинг.
		local hardWin = (Config.BlockFaceHardDt or 0.30) + up
		local hard = (dtc <= hardWin) or (Config.MultiFaceHard and clusterN >= (Config.MultiThreatMinN or 2))
		-- держим цель до контакта + грейс (перекрывает ��ам момент оверлапа и пару кадров после)
		setFaceGoal(turnTo.attackerHRP, hard, math.max(dtc, 0) + (Config.HoldAfter or 0.12) + 0.06)
		State.vizTarget = { hrp = turnTo.attackerHRP, model = turnTo.attackerModel }
	else
		State.vizTarget = nil
	end

	-- [V62] Оценка ��ультиугрозы: считаем РАЗНЫХ атакующих среди imminent и самый
	-- дальний угр��жающий контакт кластера. В логе провалы (NO-PRESS NOT-BLOCKED,
	-- BlockCooldown) и����ут именно когда 2+ врага бьют внахлёст: guard роняется
	-- между их ударами (boxing-counter/deactivate/release) → re-press ловит
	-- BlockCooldown 0.5с (dump: CombatConfig.Block.CooldownSeconds).
	local threatN, farContact = 0, nil
	do
		local seen = {}
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
		-- [V92] ЛАТЧ УДЕРЖАНИЯ КЛАСТЕРА. Баг «2-я атака проходит»: как только 1-й атакующий
		-- отрабатывал, multiThreat падал до false (остался 1 враг) → guard отпускался по
		-- КОРОТКОМУ одиночному holdUntil, ровно за ~20мс до уд��ра выжившего (diag t=73.07
		-- PERFECT → t=73.35 LATE NO-PRESS). Теперь при обнаружении кластера ЗАПОМИНАЕМ самый
		-- поздний контакт + грейс и держи�� guard до него, сколько бы угроз ни осталось потом.
		if farContact then
			local latch = farContact + Config.HoldAfter + (Config.HoldLateGrace or 0) + 0.05
			State.multiHoldUntil = math.max(State.multiHoldUntil or 0, latch)
		end
	end

	-- [V105] AutoPlay: перебивание тяжёлой обычным M1 (вместо парри). Тяжёлая (M2) — ДЛИННЫЙ замах,
	-- её damage-frame наступает намного позже окна парри, поэтому времени сбить её своим быстрым M1
	-- много (tryInterruptHeavy решает по честной модели времени). Раньше гейт `not multiThreat` и
	-- `not State.blocking` глушил перехват почти всегда → мы просто парировали перебиваемые тяжёлые.
	-- Теперь:
	--   • мультибой РАЗРЕШЁН, если следующая ДРУГАЯ угроза придёт не раньше InterruptMultiClear —
	--     успеем сбить тяжёлую и снова поднять guard (иначе оставляем held-guard как раньше);
	--   • если держим guard — роняем его прямо перед свингом (враг в тяжёлом замахе, безопасно).
	-- boxing-counter (M2+iframes) по-прежнему в приоритете (это и есть лучший панишинг стиля).
	if Config.AP_InterruptHeavy ~= false and wantBlock and not shouldBoxingCounter(wantBlock) then
		local clearOk = true
		if multiThreat then
			-- ближайший контакт ДРУГОГО (не этого) атакующего
			local nextOther
			for _, th in ipairs(imminent) do
				if th.attackerModel ~= wantBlock.attackerModel then
					local dt = th.contactAbs - now
					if dt > 0 and (not nextOther or dt < nextOther) then nextOther = dt end
				end
			end
			-- разрешаем, только если после нашего перехвата останется запас до другой угрозы
			clearOk = (not nextOther) or (nextOther >= (Config.AP_InterruptMultiClear or 0.28))
		end
		if clearOk and State.ap.tryInterruptHeavy(wantBlock, now, wantBlock.contactAbs - now, function()
				if State.blocking then releaseBlock() end   -- уронить guard прямо перед свингом
			end) then
			setFaceGoal(wantBlock.attackerHRP, true, (wantBlock.contactAbs - now) + 0.1)
			return
		end
	end

	if wantBlock then
		-- boxing-counter — только против ОДИНОЧНОЙ угрозы. В burst он шлёт н��шу M2
		-- (attack lockout) и роняет guard, оставляя остальных без блока.
		-- Гибрид: в мультибое перфектим ближайшего обычным блоком, остальным
		-- держим непрерывный guard (гарантированн��й normal-block, нулевые дыры).
		local allowCounter = shouldBoxingCounter(wantBlock)
			and not (Config.BoxingCounterSolo and multiThreat)
		if allowCounter then
			-- [V89] РАННИЙ HARD FACE-LOCK. Проблема ротации при boxing-аддоне: раньше взгляд
			-- на врага включался Т��ЛЬКО в момент выстрела counter'а (contactAbs - BoxingCounterLead
			-- = ~160мс до контакта), а до этого работал мягкий faceToward-лерп (FaceLerp=0.8) —
			-- он «лишь доворачивал» и не докручивал до врага. Сервер строит boxing-M2 хитбокс по
			-- нашему LookVector в момент ServerCheck, поэтому смотреть надо ТОЧНО и ЗАРАНЕЕ. Теперь
			-- как только решили контрить и контакт в пределах BoxingPreFace (~0.5с) — жёс��ко
			-- снапим лицо на врага �� держим лок весь этот период (enforceFaceLock в RenderStepped
			-- поддерживае�� + гасит AutoRotate). Это и есть требуемые «смотреть 0.5с на врага».
			local dtc = wantBlock.contactAbs - now
			if dtc <= (Config.BoxingPreFace or 0.5) and dtc >= -(Config.HoldAfter or 0.12) then
				-- через единый канал: жёстко держим лицо на цели counter'а весь BoxingFaceLockDur
				setFaceGoal(wantBlock.attackerHRP, true, Config.BoxingFaceLockDur or 0.55)
			end
			if not wantBlock.counterFired and now >= (wantBlock.contactAbs - Config.BoxingCounterLead) then
				wantBlock.counterFired = true
				sendBoxingCounter(wantBlock, false)
				diagPush(("COUNTER t=%.2f  %s  %s"):format(now, wantBlock.name, wantBlock.kind))
			end
			State.holdUntil = math.max(State.holdUntil, wantBlock.contactAbs + Config.HoldAfter)
			return
		end
		if multiThreat and shouldBoxingCounter(wantBlock) and not wantBlock.counterSkipLogged then
			wantBlock.counterSkipLogged = true
			diagPush(("MULTI  t=%.2f  %dx threats → boxing-counter suppressed, holding guard for all")
				:format(now, State.multiThreatN))
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
		-- этой игре НАПРАВЛЕННЫЙ: сервер отклоняет парри, если жертва смотрит спиной к атакующему
		-- (в логах face=-0.99 BACK! на проваленных парри). Но локально нажатие всё равно жжёт
		-- BlockCooldown 0.5с → следующий РЕАЛЬНЫЙ удар уже не заблокировать. Поэтому если мы ещё
		-- смотрим в сторону (faceDot < HighFaceMin) И есть время довернуться (applyFacing крутит нас
		-- каждый кадр) — НЕ жжём нажатие в этот кадр, ждём разворота. Прессим, только когда facing
		-- приемлем ИЛИ времени уже нет (последний шанс — лучше попытка, чем гарантированный хит).
		-- Не трогает мультибой (held-guard путь) и boxing-counter (у них свой снап).
		if not wantBlock.pressed and Config.AutoFace and Config.FaceGateBlock ~= false
		   and not (clusterStrategy == "HELD_GUARD") then
			local fd = faceDotTo(wantBlock.attackerHRP)
			local dtc = wantBlock.contactAbs - now
			local faceFloor = Config.FaceGateMin or (Config.HighFaceMin or 0.25)
			-- «времени нет» = до контакта меньше, чем нужно на нажатие+RTT (тогда прессим как есть)
			local lastResort = dtc <= ((Config.PerfectLead or 0.0625) + up + 0.02)
			if fd ~= nil and fd < faceFloor and not lastResort then
				-- держим цель поворота на этого атакующего и ЖДЁМ — нажатие в этот кадр пропускаем
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
					wantBlock.rec.faceDot = wantBlock.faceDot
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
		-- последующий удар любого врага ловится как normal-block (BLOCKABLE↑, HIT↓).
		local base = wantBlock.contactAbs
		if multiThreat and farContact and farContact > base then base = farContact end
		State.holdUntil = math.max(State.holdUntil,
			base + Config.HoldAfter + (Config.HoldLateGrace or 0) + holdExtra)
	elseif State.blocking then
		-- [V62] пока в кластере есть незакрытые угрозы — не отпуск��ем guard даже
		-- е��ли ближайший holdUntil истёк (иначе дыра между волнами burst).
		-- [V92] guard держим пока: (а) активен мультиугрозный кластер прямо сейчас, ИЛИ
		-- (б) не истёк ЛАТЧ кластера (State.multiHoldUntil) — даже если остался 1 атакующий,
		-- это выживший из кластера, и его удар ещё летит. Так вторая волна бо��ьше не проходит.
		local keepForCluster = (multiThreat and farContact
			and now < (farContact + Config.HoldAfter + (Config.HoldLateGrace or 0)))
			or (State.multiHoldUntil and now < State.multiHoldUntil)
		if not keepForCluster
		   and (now >= State.holdUntil or (now - State.lastPress) > Config.ReleaseGap) then
			releaseBlock()
			State.multiHoldUntil = 0
		end
	end

	-- [V100] AutoPlay: добивание застаненного врага — когда НЕТ угроз для блока. Убрали гейт
	-- `not State.blocking`: step сам уронит guard первым кадром (враг застанен, угроз нет →
	-- безопасно), а fireM1 самогейтится на Blocking. Так добивание стартует ср��зу после парри,
	-- не дожидаясь истечения HoldAfter. Защита всё равно в приоритете: step идёт только при
	-- #imminent==0 и not wantBlock, т.е. когда парировать/блокировать сейчас нечего.
	if Config.AutoPlay and not wantBlock and #imminent == 0 then
		State.ap.step(now)
	end
end

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

local function onOutcome(attacker, result, kind, eventClock)
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

	-- [V62] GUARDBREAK = guard физически сломан сервером → всегда сб��асываем.
	-- LATE = один удар прошёл, но при активном held-guard в мультибое НЕ роняе��
	-- Blocking: guard всё ещё поднят и нужен остальным атакующим. Прежнее
	-- безусловное обнуление прово��ировало re-press → BlockCooldown → каскад HIT.
	if result == "GUARDBREAK" then
		State.blocking  = false
		State.holdUntil = 0
	elseif result == "LATE" then
		local holding = State.blocking and (os.clock() < (State.holdUntil or 0))
		if not (State.multiThreat and holding) then
			State.blocking  = false
			State.holdUntil = 0
		end
	end

	-- [V97] AutoPlay: идеальное парри → враг в стане → запускаем окно добивания.
	if result == "PERFECT" then State.ap.onPerfectParry(attacker, kind) end

	local q = Pending[attacker]
	local rec
	if q then
		for i = #q, 1, -1 do
			local r = q[i]
			if not r.matched and r.type == kind and (eventClock - r.clock) <= Config.MatchWindow then
				rec = r; break
			end
		end
	end
	if not rec then
		diagPush(("OUT    t=%.2f  %s  %s  %s  (no fresh swing)"):format(eventClock, attacker, kind, result))
		return
	end
	rec.matched = true

	local measured = eventClock - rec.clock
	local predErr  = (measured - rec.contact) * 1000
	State.lastErrMs = predErr

	local ksKey = tostring(kind) .. ":" .. tostring(rec.style or "?")
	local ks = ResidByKS[ksKey]; if not ks then ks = { sum = 0, n = 0 }; ResidByKS[ksKey] = ks end
	ks.sum = ks.sum + predErr; ks.n = ks.n + 1
	local resAvg = ks.sum / ks.n   -- [V70] чисто ди��гностика, в предикт НЕ подаётся

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
	end

	local reasonStr = rec.blockedReason and (" STATE:" .. rec.blockedReason) or ""
	if rec.blockedReason and (result == "LATE" or result == "GUARDBREAK") then
		State.stateHits = (State.stateHits or 0) + 1
	end

	-- [V64] Замер эффективности per-hit rearm: к��пим ре��ультаты по позиции удара
	-- в ком��о. opener = c1-2 (всегда были свежими нажатиями), tail = c3+ (раньше
	-- шли held-guard → HIT). Если после V64 PERFECT на tail вырос, а HIT упал —
	-- rearm работает и сервер перевз��одит перфект от свежего Activated.
	do
		State.comboStat = State.comboStat or { opener = {}, tail = {} }
		local bucket = ((rec.combo or 0) >= 3) and State.comboStat.tail or State.comboStat.opener
		bucket[result] = (bucket[result] or 0) + 1
	end

	diagPush(("OUT    t=%.2f  %s  %s(c%d)  %-10s  meas=%.0fms pred=%.0fms predErr=%+.0fms resAvg=%+.0fms(n=%d) | blockGap=%s pressDt=%s %s%s | face=%s%s spd=%.2f ping=%.0f")
		:format(eventClock, attacker, kind, rec.combo or 0, result, measured*1000, rec.contact*1000,
		        predErr, resAvg, ks.n, gapStr, pressStr, hint, reasonStr, faceStr, faceFlag, rec.speed or 1, (rec.pingRaw or 0)*1000))
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
		if not attackEntry(id) then
			if BenignIds[id] then return end
			local meta = resolveAnimMeta(id)
			if not (meta and meta.marks and meta.marks > 0) then return end
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
		local kind, result = parseEvent(eventName)
		if not kind then return end
		if victim ~= myName then return end
		onOutcome(attacker, result, kind, os.clock())
	end)
	dbg("calibration active — listening CombatBroadcastURE")
end)

task.spawn(function()
	if not Config.ServerSwingHook then return end
	local Shared  = ReplicatedStorage:WaitForChild("Shared", 30)
	local Network = Shared and Shared:WaitForChild("Network", 30)
	if not Network then dbg("server-swing hook: Network not found"); return end
	local remote
	for _, ch in ipairs(Network:GetChildren()) do
		if (ch:IsA("RemoteEvent") or ch:IsA("UnreliableRemoteEvent"))
		   and ch.Name:find("CombatClientRemote") then
			remote = ch; break
		end
	end
	remote = remote or Network:FindFirstChild("CombatClientRemoteURE")
	if not remote then dbg("server-swing hook: CombatClientRemote remote not found"); return end
	remote.OnClientEvent:Connect(function(eventName, a1, ...)
		if type(eventName) ~= "string" then return end
		local kind
		if eventName == "CombatM2Swing" then kind = "M2"
		elseif eventName == "CombatM1HoldSwing" then kind = "M1" end
		if not kind then return end
		local ok = pcall(registerServerSwing, kind, a1)
		if not ok then end
	end)
	dbg("server-swing hook active — listening " .. remote.Name)
end)

-- [V90.4] СЕРВЕРНЫЙ ХИТБОКС-ДЕТЕКТ / HOLD BLOCK удалены по запросу: детект срабатывал по
-- уже-приземлившемуся удару (реактивно), из-за чего мог держать guard и мешать. Парри теперь
-- полностью предиктивный (willHitMe по анимации/сервер-свингам), как и раньше.

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

local function classifyCombat(a)
	if type(a) ~= "table" or a.Type ~= "Combat" then return nil end
	if a.Action == "M1" or a.Action == "M2" then return "attack" end
	if a.Action == "Evasive" then return "dash" end
	return nil
end

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

-- [V63] Desync-маска идёт СВОЕЙ загруженной копией idle, НИК��ГДА не захватывая
-- живые геймплейные треки. П��ошлые вер��ии брали первый не-атакующий playing-трек
-- как decoy и дёргали ЕГО вес на 90Гц + Stop() в конце — если это был walk/emote,
-- реальная анимация ломалась (проблема "не воспр��изводит норма��ьно при движении").
-- V62 форсил ст��к-idle 507766388 → чужая поза, визуальны�� снап ("переводится в idle").
-- Ре��ение: определить НАСТОЯЩИЙ idle игры (доминирующий looped не-атака-трек, пока
-- стоим на месте), закэшировать его id и крутить ��ашу собственную копию поверх.
-- Живые треки не тро��аем вообще → walk/emote целы, а маска = ��од��ой idle и��ры.
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
	-- id родного idle игры, иначе конфиг-фолбэк
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
	end
	return _decoyTrack
end

-- [V75] общий стейт self-verify (объявлен здесь, т.к. используется и тест-режимом ниже)
local SelfVerify = { conn = nil, lastLog = {}, decoyId = nil }

-- [V76] ТЕСТ-РЕЖИМ "наоборот": пока ты стоишь в idle, ПОСТОЯННО проигрываем АТАКУ как
-- decoy (низкий локальный ��ес, тебе почти незаметно). Смысл: на обсер��ере (твоя мобила)
-- должно НЕПРЕРЫВНО показывать ATTACK, хотя ты ничего не жмёшь. Если показывает —
-- значит decoy реально ��ходит в репликацию и хук подмены рабочий. Тумблер по клавише.
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
		-- максимальный приорите��, чтобы перебивать walk/run (Movement) — берём Action4 если есть
		local topPrio = Enum.AnimationPriority.Action
		pcall(function() topPrio = Enum.AnimationPriority.Action4 end)
		local wgt = Config.DesyncClientVisible and 1 or 0.03
		pcall(function()
			track.Priority = topPrio
			track.Looped = true
			track:Play(0.1)
			track:AdjustWeight(wgt, 0)
		end)
		-- [V76.1] maintenance-цикл: при ходьбе игра запускает walk-а��имацию и перебивает
		-- нашу по весу/событию AnimationPlayed → обсервер свалив��лся на WALK. Тут мы каждые
		-- ~0.35с ПЕРЕУТВЕРЖДАЕМ атаку: если её вырубили/понизили вес — перезапускаем, чем
		-- держим её постоянно доминирующей и заставляем AnimationPlayed по ней срабатывать
		-- снова (иначе обсервер показал бы последнюю walk-анимацию).
		-- [V76.2] БЕЗ рывка TimePosition=0 (он и вызывал дёрганье у тебя и в репликации).
		-- Держим трек доминирующим только пока движок ��ам не перебил его walk'ом. Важно:
		-- полностью уде��жать чужую картину клиентски НЕЛЬЗЯ — анимация реплицируется
		-- встроенным Animator'��м Roblox (в дампе НЕТ remote при :Play), а не нашим remote-хуком.
		-- [module FIX] Никогда не обнуляем Movement/Core/Idle/Action треки. Старый V81
		-- делал AdjustWeight(0.01) каждый Heartbeat, поэтому лог закономерно пок��зывал
		-- Movement/Core weight=0 и locomotion исчезала. Decoy продолжает реплицироваться
		-- через свой Play/Stop цикл, не уничтожая реальные анимации персонажа.
		if DesyncTest.conn then pcall(function() DesyncTest.conn:Disconnect() end) end
		-- [V82] интервал переигрывания = длина анимации атаки (fallback 0.5с). Зацикленный
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
		DesyncTest.conn = RunService.Heartbeat:Connect(function()
			if not DesyncTest.on or not _testTrack then return end
			pcall(function()
				_testTrack.Priority = topPrio
				local nowc = os.clock()
				if nowc >= nextReplay or not _testTrack.IsPlaying then
					nextReplay = nowc + replayInterval()
					_testTrack:Stop(0)
					_testTrack:Play(0.05)          -- свежий AnimationPlayed → возобновляем стейт атаки
					_testTrack:AdjustWeight(wgt, 0)
				end
				if _testTrack.WeightCurrent < wgt * 0.5 then _testTrack:AdjustWeight(wgt, 0.1) end
			end)
		end)
	else
		if DesyncTest.conn then pcall(function() DesyncTest.conn:Disconnect() end); DesyncTest.conn = nil end
		pcall(function() if _testTrack then _testTrack:Stop(0.1) end end)
	end
end
if type(getgenv) == "function" then getgenv().AP_DESYNC_TEST = toggleDesyncTest end

-- [V84] DESYNC-РЕЖИМЫ на J (переключаются клавишей ]). ВСЁ обёрнуто в do..end и вынесено
-- в одну таблицу DZ — иначе десяток top-level локалов переполнял 200-регистровый лимит
-- главного чанка Luau ("out of local registers"). Нару��у торчит то��ько DZ.
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
-- (Looped=true), поэтому его НЕ НУЖНО перезапускать через Stop/Play — он крути��ся сам. Именно
-- бывший цикл "Stop(0); Play()" каждые ~длину и ломал ани��ации со временем (постоянные
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
	if not track then aclog("[DESYNC:idlemask] idle-decoy не найден"); return end
	local topPrio = topPriority()
	local wgt = Config.DesyncClientVisible and 1 or 0.03
	pcall(function() track.Priority = topPrio; track.Looped = true; track:Play(0.2); track:AdjustWeight(wgt, 0.1) end)
	IdleMask.conn = RunService.Heartbeat:Connect(function()
		local an = localAnimator(); if not an then return end
		local tr = getIdleDecoy(an); if not tr then return end
		pcall(function()
			tr.Priority = topPrio
			if not tr.IsPlaying then
				tr.Looped = true
				tr:Play(0.2); tr:AdjustWeight(wgt, 0.1)   -- переиграть ТОЛЬКО если реально остановился
			elseif tr.WeightCurrent < wgt * 0.5 then
				tr:AdjustWeight(wgt, 0.1)                  -- мягко вернуть вес, без рестарта
			end
		end)
	end)
	aclog("[desync] idlemask on")
end

-- PRERUN: короткая фейк-АТАКА (decoy-анимация), которую мы реплицируем РАНЬШЕ реальной —
-- вра��еский autoparry цепляется за неё и парирует не тот удар, реальный проходит. Реальный
-- FireServer при этом НЕ задерживается (уходит штатно).
local PreRun = { busyUntil = 0 }
local function firePreRunDecoy()
	local now = os.clock()
	if now < PreRun.busyUntil then return end
	PreRun.busyUntil = now + 0.22
	local animator = localAnimator(); if not animator then return end
	local track, id = getTestDecoy(animator); if not track then return end
	local topPrio = topPriority()
	local wgt = Config.DesyncClientVisible and 1 or 0.03
	local dur = (Config.DesyncDelayMs or 140) / 1000
	SelfVerify.decoyId = "rbxassetid://" .. tostring(id)
	task.spawn(function()
		pcall(function() track.Priority = topPrio; track.Looped = false; track:Play(0.02); track:AdjustWeight(wgt, 0) end)
		task.wait(dur)
		pcall(function() track:Stop(0.05) end)
	end)
end

-- центральный переключатель — вызывать при вкл/выкл J и при смене режима
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

-- ═══════════════════ INVISIBLE + GHOST ═══════════════════
-- Ед��нственный top-level локал IV (как DZ) — чтобы не упереться в лимит регистров.
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
			RS:BindToRenderStep(Inv.bindKey, 0, function()
				local r = rootOf()
				if r and Inv.oldcf then
					r.CFrame = Inv.oldcf
					if Inv.track then pcall(function() Inv.track:AdjustWeight(0.001) end) end
				end
			end)
		end)

		-- Heartbeat: смещаем корень вниз+разворот → ЭТО реплицируется другим (они тебя не видят).
		Inv.hb = RS.Heartbeat:Connect(function()
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
		end)

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

-- [V77] RAKNET DISCOVERY — ПЕРЕПИСАНО НА РЕАЛЬНЫЙ Potassium API (фикс крашей).
-- КОРЕНЬ КРАША: старый код использовал НЕВЕРНЫЙ API (docs устарели). Реальный API,
-- подтверждён рабочим андетект-примером юзера:
--   packet.PacketId        -- id пакета (число, обычно hex 0x1B и т.п.)
--   packet.AsBuffer        -- буфер данных (buffer.*), packet:SetData(buf) чтобы записать
--   packet:Drop()          -- отбросить (заблокировать) пакет  (НЕ return false!)
--   raknet.add_send_hook(fn) / raknet.remove_send_hook(fn)   -- снятие по ССЫЛКЕ на fn!
--   raknet.add_recv_hook(fn) / raknet.remove_recv_hook(fn)
-- Старый код: (1) ��итал packet.id / packet.size — таких полей нет; (2) хранил "hookId"
-- из add_send_hook и зва�� remove_send_hook(hookId) — передавал не-функцию в C++ →
-- вылет. Теперь хук — ИМЕНОВАННАЯ фун��ция, снимается по ссылке. Скан read-only:
-- не трогает па����еты (ни Drop, ни SetData), только считает PacketId. Максимально
-- безопасно и мин��мально по работе на пакет — как в андетект-примере.
-- [V79] КОРЕНЬ КРАША НАЙДЕН: send-хук исполняется на СЕТЕВОМ потоке игры, а НЕ на потоке
-- Luau VM. Luau VM однопоточный �� любая МУТАЦИЯ Lua-таблицы с чужого потока (создание
-- нового ключа → rehash → реаллокация кучи) мгновенно рушит heap → краш. Мой скан дел��л
-- RaknetScan.near[pid] = ... с НОВЫМ ключом на каждый ��овый pid → rehash на сетевом потоке
-- → вылет при первом же пакете. Рабочий андетект-пример НИКОГДА не трога��т Lua-таблицы в
-- хуке — только C-операции над пакетом. Поэтому он и не крашит.
-- ФИКС: ��чётчики — ПРЕДВЫДЕЛЕННЫЙ массив на 256 слотов (0..255), в хуке тольк�� IN-PLACE
-- инкремент существующего числового слота (без новых ключей, без rehash, без аллокации).
-- Это безопасно даже с чужого потока (максимум — безобидная гонка знач��ния счётчика).
local RAK_SLOTS = 256
local function newCounterArray()
	local t = table.create and table.create(RAK_SLOTS, 0) or {}
	for i = 1, RAK_SLOTS do t[i] = 0 end   -- слот = pid+1 (pid 0..255)
	return t
end
local RaknetScan = { active = false, window = 0, near = newCounterArray(), far = newCounterArray() }

-- ИМЕНОВАННАЯ функция (снятие по ссылке). НИКАКОЙ аллокации/мутации структуры Lua-таблиц.
local function raknetScanSendHook(packet)
	local pid = packet.PacketId
	if pid and pid >= 0 and pid < RAK_SLOTS then
		local slot = pid + 1
		if os.clock() < RaknetScan.window then
			RaknetScan.near[slot] = RaknetScan.near[slot] + 1   -- IN-PLACE, слот уже существует
		else
			RaknetScan.far[slot] = RaknetScan.far[slot] + 1
		end
	end
	-- пакет не трогаем → уходит штатно.
end

local function reportRaknetScan()
	local cand = {}
	for slot = 1, RAK_SLOTS do
		local n = RaknetScan.near[slot]
		if n > 0 then
			cand[#cand + 1] = { id = slot - 1, near = n, far = RaknetScan.far[slot] }
		end
	end
	table.sort(cand, function(a, b) return (a.near / (a.far + 1)) > (b.near / (b.far + 1)) end)
	if #cand == 0 then
		aclog("[DESYNC-SCAN] 0 пакетов поймано — либо raknet-хук не видит трафик в этой сборке, л��бо не св��нгал во время сессии.")
		desyncPush("[SCAN] 0 packets captured (hook saw no traffic, or no swing during session)")
		return
	end
	local lines = {}
	for i = 1, math.min(10, #cand) do
		local c = cand[i]
		lines[#lines + 1] = ("PacketId=%d (0x%X) near=%d far=%d ratio=%.2f")
			:format(c.id, c.id, c.near, c.far, c.near / (c.far + 1))
	end
	aclog("[DESYNC-SCAN] candidates (near=�� окне атаки, far=фон; высокий ratio = вероятный анимационный/боевой пакет):\n  " ..
		(table.concat(lines, "\n  ")))
	desyncPush("[SCAN] raknet candidates (near=in attack window, far=background, high ratio=likely anim/combat packet):")
	for _, l in ipairs(lines) do desyncPush("[SCAN]   " .. l) end
end

-- [V80] RAKNET-ХУК ЖЁСТКО ОТКЛЮЧЁН. Причина (подтверждена анализом дампов игры):
--   • В клиентских дампах НЕТ ни одного Lua-анти-чита, сканирующего хуки — значит краш
--     вызывает НЕ игрово�� скрипт, который можно "выпилить".
--   • Краш происходит В МОМЕНТ raknet.add_send_hook (мгновенно, до первого пакета) →
--     это native-защита клиента Roblox (Hyperion/Byfron), а не Lua. Её нельзя убрать
--     правкой игровых скриптов. Поэтому и "популяр��ый desync-скрипт" тоже крашил на F.
--   • Сеть игры = Blink: бой/движение шлётся через BLINK_RELIABLE_REMOTE:FireServer(buffer,
--     instances) раз в Heartbeat — это ОБ��Ч��ЫЙ RemoteEvent, а НЕ raknet. Значит desync
--     достижим без raknet: через hookmetamethod(__namecall) на FireServer (UNC-стандарт,
--     эта игра его не де��ектит, и он НЕ крашит). Это отдельная фича — включим по запросу.
_ = raknetScanSendHook  -- функция сохран��на в файле, но НЕ вызывается (ссылка, чтобы не было "unused")
_ = reportRaknetScan
local function runRaknetScanSession()
	aclog("[DESYNC-SCAN] ОТКЛЮЧЕНО: raknet-хук крашит native-защиту клиента (Hyperion), это не Lua-AC и не уби��ается правкой игры. Desync-путь чер��з Blink RemoteEvent (__namecall) — по запросу.")
	desyncPush("[SCAN] raknet path disabled (native anti-tamper crash). Use Blink __namecall path instead.")
end
if type(getgenv) == "function" then getgenv().AP_RAKNET_SCAN = runRaknetScanSession end

-- [V74] DESYNC SELF-VERIFY. Как понять, работает ли desync ВООБЩЕ, без второго
-- аккаунта: Animator.AnimationPlayed срабатывает на КАЖДЫЙ трек, который стартует на
-- нашем аниматоре — а это ровно то, что Roblox реплицирует другим клиентам. Значит
-- если при свинге сюда прилетают И реальная атака, И decoy-idle — оба уходят в сеть,
-- и чужой AnimationPlayed увидит оба трека. Э���� объективное доказательство, что
-- decoy-overlay реально загрязняет чужой детект (а не только крутится локально).
-- Помечаем строку [DECOY] когда id совпал с нашим decoy — сразу видно попадание.
-- SelfVerify объявлен выше (перед тест-режимом)
local function installDesyncSelfVerify()
	if not Config.DesyncSelfVerify then return end
	local function attach(char)
		if not char then return end
		task.spawn(function()
			local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
			local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5))
			if not animator then return end
			if SelfVerify.conn then pcall(function() SelfVerify.conn:Disconnect() end) end
			SelfVerify.conn = animator.AnimationPlayed:Connect(function(track)
				pcall(function()
					local anim = track and track.Animation
					local aid  = anim and anim.AnimationId or "?"
					local now  = os.clock()
					-- throttle: одна строка на id не чаще, чем раз в 0.4с
					if (now - (SelfVerify.lastLog[aid] or 0)) < 0.4 then return end
					SelfVerify.lastLog[aid] = now
					local isDecoy = (SelfVerify.decoyId and aid == SelfVerify.decoyId)
					local isAttack = AttackIds and AttackIds[aid] ~= nil
					local tag = isDecoy and "DECOY" or (isAttack and "ATTACK" or "other")
					local line = ("[VERIFY] %s track played on MY animator: id=%s prio=%s weight=%.2f%s")
						:format(tag, tostring(aid), tostring(track and track.Priority),
							(track and track.WeightCurrent) or 0,
							isDecoy and "  <-- decoy IS in the replicated stream (enemy AnimationPlayed sees it too)" or "")
					aclog("[DESYNC-VERIFY] " .. line)
					desyncPush(line)
				end)
			end)
			aclog("[DESYNC-VERIFY] listening on your Animator.AnimationPlayed — swing to see which tracks actually replicate")
			desyncPush("[VERIFY] self-verify attached to own animator")
		end)
	end
	attach(LocalPlayer.Character)
	LocalPlayer.CharacterAdded:Connect(attach)
end

-- [V75] КРОСС-КЛИЕНТНАЯ ПРОВЕРКА (отвечает на "как это видят другие игроки").
-- Ты прав: self-verify и Drawing-текст показывают то, что видит ТВОЙ клиент — это лишь
-- ��РОКСИ репликации, а не док��зательство тог��, ��то реально приходит врагу. Единственн��й
-- надёжный способ увидеть чужую картину — смотреть с ДРУГОГО клиента.
-- ��ак по��ьзоваться: запусти скрипт на ВТОРОМ аккаунте (или попроси друга), встань рядом
-- со своим главным и вызови в консоли:  getgenv().AP_OBSERVE("ИмяГлавного")
-- Тогда ВТОРОЙ клиент будет логировать каждый трек, который РЕАЛЬ��О реплицировался ему
-- от твоего главного. Свингни ��а главном — �� в дебаге второго аккаунта увидишь, что
-- ему пришло: реальная атака, decoy-idle, или (если raknet-rewrite заработает) только idle.
-- Это и есть объективная проверка desync с ��очки зрения противника.
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

-- [V75] сохранение desync-дебага в отдельный файл, чтобы слать мне.
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

	-- [V74] если идёт скан-��ессия — метим следующие ~220мс ��ак "окно атаки" (near).
	if RaknetScan.active then
		RaknetScan.window = now + (Config.DesyncRaknetWindowMs or 220) / 1000
	end

	-- [V88] сюда доходит ТОЛЬКО delay: idlemask держится своим циклом, prerun — на FireServer.
	if (Config.DesyncMode or "delay") ~= "delay" then return end
	-- [V88] ФИКС "delay ломал [": [ и idlemask крутят СВОИ decoy-треки, у к��торых тоже
	-- срабатывает AnimationPlayed. Раньше delay-хук хватал их и делал Stop/replay → decoy
	-- дёргался. Пропускаем наши собственные decoy-треки — трогаем только реальные атаки.
	if track == _testTrack or track == _decoyTrack then return end

	local window = (Config.DesyncDelayMs or 0) / 1000 + 0.05
	_desyncBusyUntil[track] = now + window

	local origSpeed = 1
	pcall(function() local s = track.Speed; if type(s) == "number" and s > 0.05 then origSpeed = s end end)
	State.desyncFires = (State.desyncFires or 0) + 1

	-- DELAY: анимацию замаха скрываем сразу и переигры��аем через mag мс (визуал стартует
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

local function installAnimDesync()
	aclog("[desync] ready")
end

task.spawn(function()
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		dbg("combat hook: metamethod API unavailable — Guard/BlockKick/Desync disabled")
		aclog("[desync] no metamethod api")
		return
	end
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", hideHook(function(self, ...)
		if checkcaller and checkcaller() then return oldNamecall(self, ...) end
		local method = getnamecallmethod()

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
		-- иначе он снова отложится (бесконечный цикл) или потеряется.
		if State.desyncPassthrough then return oldNamecall(self, ...) end

		local a1 = (select(1, ...))
		local ok, kind = pcall(classifyCombat, a1)
		if ok and kind then
			-- разовый confirm: доказывает, что __namecall ЛОВИТ игровой боевой FireServer.
			-- Если этой строки нет в диаге после свинга — хук не перехватывает FireServer
			-- (тогда идём в raknet/replicatesignal), а не «firedelay сломан».
			if not State.combatFireSeen then
				State.combatFireSeen = true
				aclog(("[desync] combat FireServer intercepted (%s/%s) — hook OK")
					:format(tostring(a1.Action), tostring(a1.Func)))
			end
			local now = os.clock()
			if kind == "attack" then
				State.selfBusyUntil = now + Config.SelfBusyDur
				-- FIREDELAY/PRERUN: задерживаем САМ боевой паке�� (ServerCheck), анимацию не
				-- трогаем. Гейт стро��о по Func=="ServerCheck" (реальный удар; Hold*-пакеты не
				-- трогаем — иначе рассинхрон чарджа). Перехват на RemoteEvent Remotes.Server —
				-- он доступен (в отличие от модуля CombatRemoteClient, который может лежать в Hidden).
				local func = a1.Func
				if Config.DesyncAttack and func == "ServerCheck"
				   and (Config.DesyncMode == "firedelay" or Config.DesyncMode == "prerun")
				   and desyncApplies(a1.Action) then
					if Config.DesyncMode == "prerun" then pcall(DZ.firePreRunDecoy) end
					local remote, packed, d = self, table.pack(...), desyncMag()
					task.delay(d, function()
						State.desyncPassthrough = true
						pcall(function() remote:FireServer(table.unpack(packed, 1, packed.n)) end)
						State.desyncPassthrough = false
					end)
					if (now - (State.lastSwingLog or 0)) > 0.15 then
						State.lastSwingLog = now
						aclog(("[desync] %s send held +%dms"):format(tostring(a1.Action), math.floor(d * 1000)))
					end
					return   -- глотаем немедленную отправку, реальный пакет уйдёт из task.delay
				end
			elseif kind == "dash" then
				State.selfBusyUntil = now + Config.DashDuration
			end
		end
		return oldNamecall(self, ...)
	end))
	AnimLib.desyncHooked = true
	dbg("combat hook active")
	-- [V74] raknet-скан БОЛЬШЕ НЕ стартует при загрузке (это в��шало клиент). Запускай
	-- вручную по команде getgenv().AP_RAKNET_SCAN() когда стоишь в бою.
end)

-- [V90] firedelay/prerun теперь обрабатываю��ся ЕДИНСТ��ЕННЫМ владельцем — __namecall-хуком
-- на Remotes.Server:FireServer (выше). Отдельный хук на CombatRemoteClient.Fire УДАЛЁН: он
-- (а) патчи�� таблицу по пути ReplicatedStorage.Shared.Network, которая может ��ы��ь декоем, пока
-- реальный модуль лежит в Hidden, и (б) при работающем namecall-хуке давал ДВОЙНУЮ задержку
-- (модуль держал → origFire → Server:FireServer → namecall держал снова). RemoteEvent
-- Remotes.Server реплицируется и всегда достижим, поэтому перехват на нём надёжнее модульного.

local function activeRestrictZone(now)
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
end

local function restrictStep(now)
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
end

RunService.Heartbeat:Connect(function()
	if not Config.Enabled then
		if State.blocking then releaseBlock() end
		State.status = "OFF"
		return
	end
	local now = os.clock()
	FrameId = FrameId + 1        -- [V68] invalidates per-frame HRP cache
	pcall(schedulerStep, now)    -- [V68] one persistent-fn pcall guards the whole loop
	                             -- (no per-read closures inside anymore → far less GC)
	pcall(restrictStep, now)

	-- ФИКС ЗАСТРЕВАНИЯ БЛОКА: единая реконсиляция guard. Несколько путей (dodge, boxing-
	-- counter, onOutcome LATE/GUARDBREAK) сбрасывают State.blocking напрямую, НЕ отправляя
	-- Deactivated → сервер продолжал держать guard до ручного нажатия. Тут гарантируем:
	-- если серверу отправлен Activated (guardUp), но намерения блокировать больше нет —
	-- принудительно снимаем guard. Идемпотентно и безопасно (force обходит рей��-гейт).
	if State.guardUp and not State.blocking then
		pcall(sendDeactivate, true)
	end

	for name, q in pairs(Pending) do
		for i = #q, 1, -1 do
			if now - q[i].clock > 3 then table.remove(q, i) end
		end
		if #q == 0 then Pending[name] = nil end
	end

	if not State.blocking and State.status ~= "THREAT" then
		if now >= State.flashUntil then State.status = "ARMED" end
	end
end)

local function summary()
	local t = State.tally
	local total = (t.PERFECT or 0)+(t.EARLY or 0)+(t.LATE or 0)+(t.GUARDBREAK or 0)
	local hits = (t.LATE or 0) + (t.GUARDBREAK or 0)
	local stateHits = State.stateHits or 0
	local realMiss = math.max(0, hits - stateHits)
	local blockable = total - stateHits
	local acc = blockable > 0 and (100 * ((t.PERFECT or 0) + (t.EARLY or 0)) / blockable) or 0
	return table.concat({
		"===== AUTOPARRY V71 DIAG =====",
		("player=%s  ping=%.0fms  uplink=%.0fms  mode=%s  autoface=%s"):format(LocalPlayer.Name, getPingRaw()*1000, uplink()*1000, Config.Mode, tostring(Config.AutoFace)),
		("model: PURE-MATH predict (anim timeline + live TimePosition, NO calibration); lead=%.0fms hold=%.0fms window=[%.0f,%.0f]ms")
			:format(Config.PerfectLead*1000, Config.HoldAfter*1000, Config.PerfectMin*1000, Config.PerfectWindow*1000),
		("outcomes: PERFECT=%d  BLOCK=%d  HIT=%d  GUARDBREAK=%d  total=%d"):format(t.PERFECT or 0, t.EARLY or 0, t.LATE or 0, t.GUARDBREAK or 0, total),
		("attacks=%d  presses=%d  dodges=%d  outnumbered-escapes=%d  desync-anims=%d  ac-muted=%d  kicks-blocked=%d  reports-blocked=%d"):format(State.parryCount, State.fireCount, State.dodgeCount, State.grantEscapes or 0, State.desyncFires or 0, State.acMuted or 0, State.kicksBlocked or 0, State.reportsBlocked or 0),
		("HIT breakdown: %d total → %d game-state-locked (stun/attack/cooldown, unblockable) + %d real timing miss")
			:format(hits, stateHits, realMiss),
		("BLOCKABLE accuracy = %.1f%%  (%d/%d attacks we were allowed to block landed as block/perfect)")
			:format(acc, blockable - realMiss, blockable),
		("accuracy mode: %s  |  off-target swings rejected=%d  |  boxing-counter fired=%d")
			:format(Config.AccuracyMode or "Low", State.offTargetRej or 0, State.counterCount or 0),
		"=============================",
	}, "\n")
end

local function saveDiag()
	local body = summary() .. "\n\n" .. table.concat(DiagLog, "\n") .. "\n"
	local fname = ("autoparry_diag_%d.txt"):format(os.time() % 1000000)
	local ok = pcall(function() if writefile then writefile(fname, body) end end)
	if ok and writefile then
		dbg("SAVED ->", fname, "(", #DiagLog, "lines )")
		if setclipboard then pcall(setclipboard, fname) end
	else
		statusPush(summary())
	end
	return fname
end

local RING_A    = Color3.fromRGB(196, 158, 255)
local RING_B    = Color3.fromRGB(122, 214, 255)
local CONE_SAFE = Color3.fromRGB(96, 214, 140)
local CONE_HIT  = Color3.fromRGB(255, 84, 84)
local RESTRICT_COL = Color3.fromRGB(255, 72, 72)
local RING_SEG  = 40
local CONE_SEG  = 18
local CONE_FILL = 0.32
local VIZ_CONE_HALF = math.rad(64)
local VIZ_CONE_PAD  = 5.0
local VIEW_DIST = 100

local LinePool = { items = {}, used = 0, ok = (Drawing ~= nil) }
function LinePool:begin() self.used = 0 end
function LinePool:get()
	if not self.ok then return nil end
	self.used += 1
	local ln = self.items[self.used]
	if not ln then
		local created = pcall(function() ln = Drawing.new("Line") end)
		if not created then self.ok = false; return nil end
		self.items[self.used] = ln
	end
	return ln
end
function LinePool:finish() for i = self.used + 1, #self.items do self.items[i].Visible = false end end
function LinePool:hideAll() for _, ln in ipairs(self.items) do ln.Visible = false end; self.used = 0 end

local TriPool = { items = {}, used = 0, ok = (Drawing ~= nil) }
function TriPool:begin() self.used = 0 end
function TriPool:get()
	if not self.ok then return nil end
	self.used += 1
	local tr = self.items[self.used]
	if not tr then
		local created = pcall(function() tr = Drawing.new("Triangle"); tr.Filled = true end)
		if not created then self.ok = false; return nil end
		self.items[self.used] = tr
	end
	return tr
end
function TriPool:finish() for i = self.used + 1, #self.items do self.items[i].Visible = false end end
function TriPool:hideAll() for _, tr in ipairs(self.items) do tr.Visible = false end; self.used = 0 end

local function vizHideAll() LinePool:hideAll(); TriPool:hideAll() end

-- [module] AnimDbg (экранный Drawing-текст "ANIM ... | desync ...") УДАЛЁН полностью по запросу.

local Viz = { t = 0 }

local NEAR = 0.6

local function rotY(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

local function proj(cam, world)
	local sp = cam:WorldToViewportPoint(world)
	return Vector2.new(sp.X, sp.Y), sp.Z
end

local function drawWorldSeg(cam, a, b, color, thick)
	local a2d, az = proj(cam, a)
	local b2d, bz = proj(cam, b)
	if az <= NEAR and bz <= NEAR then return end
	if az <= NEAR or bz <= NEAR then
		local t = (NEAR - az) / (bz - az)
		local mid = a:Lerp(b, t)
		local m2d = proj(cam, mid)
		if az <= NEAR then a2d = m2d else b2d = m2d end
	end
	local ln = LinePool:get(); if not ln then return end
	ln.From, ln.To = a2d, b2d
	ln.Color, ln.Thickness, ln.Transparency, ln.Visible = color, thick, 1, true
end

local function pickTarget()
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
end

local function drawFlatRing(cam, model, hrp, hot)
	local footY = hrp.Position.Y - 2.8
	local radius = 3.2
	pcall(function()
		local c, s = model:GetBoundingBox()
		footY  = c.Y - s.Y * 0.5 + 0.08
		radius = math.clamp(math.max(s.X, s.Z) * 0.75, 2.4, 6)
	end)
	radius = radius * (Config.VizRingScale or 1.0)   -- [V90] пользовательский размер кольца
	local spd = Config.VizRingSpeed or 1.0           -- [V90] пользовательская скорость анимации
	local t = Viz.t * spd
	local cx, cz = hrp.Position.X, hrp.Position.Z
	local pulse = 1 + math.sin(t * 3.0) * 0.05
	local wpts = {}
	for i = 0, RING_SEG - 1 do
		local a = i / RING_SEG * math.pi * 2
		local r = radius * pulse * (1 + math.sin(a * 4 + t * 5) * 0.03)
		wpts[i] = Vector3.new(cx + math.cos(a) * r, footY, cz + math.sin(a) * r)
	end
	local thick = hot and 4 or 2.5
	for i = 0, RING_SEG - 1 do
		local j = (i + 1) % RING_SEG
		local f = 0.5 + 0.5 * math.sin(i / RING_SEG * math.pi * 2 + t * 2.2)
		drawWorldSeg(cam, wpts[i], wpts[j], RING_A:Lerp(RING_B, f), thick)
	end
end

local function footYOf(model, hrp)
	local y = hrp.Position.Y - 2.8
	pcall(function() local c, s = model:GetBoundingBox(); y = c.Y - s.Y * 0.5 + 0.05 end)
	return y
end
local function drawTargetHitbox(cam, model, hrp)
	local look = hrp.CFrame.LookVector
	local flook = Vector3.new(look.X, 0, look.Z)
	if flook.Magnitude < 0.05 then return end
	flook = flook.Unit

	local style = styleOf(model)
	local reach = math.max(styleForward(style, "M1"), styleForward(style, "M2")) + VIZ_CONE_PAD
	local half  = VIZ_CONE_HALF
	local y = footYOf(model, hrp)
	local origin = Vector3.new(hrp.Position.X, y, hrp.Position.Z)

		local col = CONE_SAFE
		local me  = localHRP()
		if me then
			local forward = math.max(styleForward(style, "M1"), styleForward(style, "M2"))
			local off  = Vector3.new(me.Position.X - hrp.Position.X, 0, me.Position.Z - hrp.Position.Z)
			local fwd  = off:Dot(flook)
			local side = math.abs(off:Dot(Vector3.new(-flook.Z, 0, flook.X)))
			local slack = Config.HitboxSlack or 0
			if fwd >= (forward - Config.HitboxDepthBack - slack) and fwd <= (forward + Config.HitboxDepth + slack)
			   and side <= (Config.HitHalfWidth + slack) then
				col = CONE_HIT
			end
		end

	local wArc = {}
	for i = 0, CONE_SEG do
		local ang = -half + (i / CONE_SEG) * (half * 2)
		wArc[i] = origin + rotY(flook, ang) * reach
	end
	local o2d, oz = proj(cam, origin)
	local a2d, az = {}, {}
	for i = 0, CONE_SEG do a2d[i], az[i] = proj(cam, wArc[i]) end
	for i = 0, CONE_SEG - 1 do
		if oz > NEAR and az[i] > NEAR and az[i + 1] > NEAR then
			local tr = TriPool:get()
			if tr then
				tr.PointA, tr.PointB, tr.PointC = o2d, a2d[i], a2d[i + 1]
				tr.Color, tr.Transparency, tr.Filled, tr.Visible = col, CONE_FILL, true, true
			end
		end
	end
	drawWorldSeg(cam, origin, wArc[0], col, 2)
	drawWorldSeg(cam, origin, wArc[CONE_SEG], col, 2)
	for i = 0, CONE_SEG - 1 do drawWorldSeg(cam, wArc[i], wArc[i + 1], col, 2) end
end

local function drawRestrictZone(cam)
	if not (Config.RestrictZone and Config.RestrictShowZone) then return end
	local z = activeRestrictZone(os.clock()); if not z then return end
	local aHRP = z.th.attackerHRP; if not (aHRP and aHRP.Parent) then return end
	local y  = footYOf(z.th.attackerModel, aHRP)
	local cx, cz = z.center.X, z.center.Z
	local r  = z.keepOut * (1 + math.sin(Viz.t * 4) * 0.02)
	local center3 = Vector3.new(cx, y, cz)

	local function arc(a0, a1, rr, thick, steps)
		steps = steps or 6
		local prev
		for i = 0, steps do
			local a = a0 + (a1 - a0) * (i / steps)
			local p = Vector3.new(cx + math.cos(a) * rr, y, cz + math.sin(a) * rr)
			if prev then drawWorldSeg(cam, prev, p, RESTRICT_COL, thick) end
			prev = p
		end
	end

	local bracket = math.rad(34)
	for k = 0, 3 do
		local mid = math.rad(45) + k * math.rad(90)
		arc(mid - bracket / 2, mid + bracket / 2, r, 3, 7)
	end

	local ch = math.max(r * 0.14, 0.7)
	drawWorldSeg(cam, Vector3.new(cx - ch, y, cz), Vector3.new(cx + ch, y, cz), RESTRICT_COL, 2)
	drawWorldSeg(cam, Vector3.new(cx, y, cz - ch), Vector3.new(cx, y, cz + ch), RESTRICT_COL, 2)

	if z.aPos then
		local from = Vector3.new(z.aPos.X, y, z.aPos.Z)
		local dir  = Vector3.new(cx - z.aPos.X, 0, cz - z.aPos.Z)
		if dir.Magnitude > 0.1 then
			local edge = center3 - dir.Unit * r
			drawWorldSeg(cam, from, edge, RESTRICT_COL, 1.5)
		end
	end
end

local function vizUpdate(dt)
	if not LinePool.ok then return end
	local cam = Workspace.CurrentCamera
	-- [module] AutoParry visuals belong to AutoParry: hide them the instant the feature
	-- is disabled, not just when ShowVisuals is off.
	if not (Config.Enabled and Config.ShowVisuals and cam) then vizHideAll(); return end
	Viz.t += dt

	LinePool:begin(); TriPool:begin()
	local model, hrp = pickTarget()
	if model and hrp then
		local hot = (State.status == "PARRY" or State.status == "DODGE")
		if Config.VizHitbox ~= false then drawTargetHitbox(cam, model, hrp) end
		if Config.VizRing ~= false then drawFlatRing(cam, model, hrp, hot) end
	end
	if Config.VizRestrict ~= false then drawRestrictZone(cam) end
	LinePool:finish(); TriPool:finish()
end

-- [V95] ЕДИНЫЙ АППЛИКАТОР ПОВОРОТА. Единственное место, где пишется HRP.CFrame ради facing.
-- Работает в RenderStepped ПОСЛЕ игрового AutoRotate/SmoothShiftLock (мы подключаемся позже —
-- игра грузится раньше), поэтому наш поворот — последний писатель кадра и не проигрывает гонку.
-- Пока есть активная цель — гасим Humanoid.AutoRotate, чтобы игра не докручивала HRP к движению
-- (это и рвало снап + давало дёрганье). Как только цель истекла — О��ИН раз возвращаем AutoRotate.
local function applyFacing()
	local goalHRP = State.faceGoalHRP
	-- [V101] EQUIP-ГЕЙТ ротации (юзер: скрипт крути�� перса без одетых рук). Игра запрещает
	-- блок/парри/M1 при Equip ~= true (isInBlockingPreventedState), значит и доворачиваться
	-- незачем. Если руки не одеты — сбрасываем цель поворота и ВОЗВРАЩАЕМ AutoRotate (как при
	-- истечении цели), чтобы отдать управление игроку. Кросс-платформенно (атрибут, не клавиша T).
	local ec = localChar()
	local equipped = ec and ec:GetAttribute("Equip") == true
	if not goalHRP or os.clock() > (State.faceGoalUntil or 0) or not goalHRP.Parent
	   or (Config.RequireEquip ~= false and not equipped) then
		if State.faceHum then pcall(function() State.faceHum.AutoRotate = true end); State.faceHum = nil end
		State.faceGoalHRP = nil
		return
	end
	if not Config.AutoFace then return end
	local myHRP = localHRP()
	if not myHRP then return end
	local c = localChar()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum and hum.AutoRotate then hum.AutoRotate = false; State.faceHum = hum end
	-- [V97] PING-SCALED предикт позиции цели ВОЗВРАЩЁН. В V95 я убрал velocity-lead (думая, что
	-- сервер валидирует по факт. позиции) — но это ломало facing на резко движущемся/рывкающем
	-- враге (в логе face=0.14/-0.58 BACK! на LATE-миссах). Причина: на нашем экране другой игрок
	-- отрисован в ПРОШЛОМ (интерп-лаг + ping), а ��ервер держит его ВПЕРЕДИ. При рывке рассинхрон
	-- = vel*latency растёт → мы смотрим туда, где враг БЫЛ, сервер видит спину → блок отклонён.
	-- Упреждаем: aim = pos + flatVel * (ping-based lead). Стоит на месте (vel≈0) → lead≈0 → как
	-- раньше (нет регресса на статичном боксинге). Рывок → смотрим на СЕРВЕРНУЮ позицию врага.
	local aimPos = goalHRP.Position
	local lead   = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.22)
	if lead > 0 then
		-- прямое чтение свойства (goalHRP уже проверен на .Parent) — БЕЗ pcall-замыкания,
		-- иначе кажды�� RenderStepped-кадр боя аллоцировался бы новый closure (лишний GC).
		local vel = goalHRP.AssemblyLinearVelocity
		local off = Vector3.new(vel.X, 0, vel.Z) * lead
		local mx  = Config.FaceLeadMaxStuds or 7
		if off.Magnitude > mx then off = off.Unit * mx end
		aimPos = aimPos + off
	end
	local d = flatDirTo(myHRP.Position, aimPos)
	if not d then return end
	local goal = CFrame.lookAt(myHRP.Position, myHRP.Position + d)
	if State.faceGoalHard then
		myHRP.CFrame = goal
	else
		myHRP.CFrame = myHRP.CFrame:Lerp(goal, Config.FaceLerp or 0.8)
	end
end

-- [V93] ОТРИСОВКА визуалов — на Heartbeat, НЕ на RenderStepped.
-- Причина бага «визуал плывёт под шифтлоком»: SmoothShiftLock (дамп Packages/SmoothShiftLock)
-- правит Camera.CFrame каждый кадр в RenderStepped. Наш прежний RenderStepped:Connect работал
-- в ТОЙ ЖЕ фазе и проецировал WorldToViewportPoint по камере, которую шифтлок в этот же кадр
-- ещё домётывал → 2D-точки отставали от реально отрендеренной камеры на кадр → при повороте
-- (шифтлок) дровинги сдвигались/дрож��ли. Heartbeat идёт уже ПОСЛЕ рендера — камера
-- зафиксирована, проекция стабильна (к тому же сам VictimHitboxService игры тоже на Heartbeat).
RunService.Heartbeat:Connect(function(dt)
	local ok = pcall(vizUpdate, dt)
	if not ok then vizHideAll() end
end)

-- [V95] applyFacing (единый аппликатор поворота) — в RenderStepped: должен переигрывать
-- AutoRotate/шифтлок каждый ренд��р-кадр как последний писатель HRP. Пока нет активной цели
-- поворота — он дёшево выходит и держит AutoRotate включённым (визуал/движение не трога��тся).
RunService.RenderStepped:Connect(function()
	pcall(applyFacing)
end)

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

-- ═══════════════════════════════════════════════���═══════════════════════════
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
			section:Slider({
				Name = o.Name, Default = o.Default, Minimum = o.Min, Maximum = o.Max,
				Precision = o.Precision or 0, Suffix = o.Suffix,
				Callback = o.Callback,
			}, ctx.flag(o.Flag))
		end

		-- ════════════════��══ TAB: AutoParry ══════════════���════
		local AP = ctx.tabs.AutoParry

		-- ── Section 1 — AutoParry core (Left box): Detection + Rotation groups ──
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
		apMain:Dropdown({
			Name = "Accuracy Mode",
			Options = { "Low", "High" },
			Default = Config.AccuracyMode or "Low",
			Callback = function(v)
				Config.AccuracyMode = v
				notify("Accuracy Mode", "Selected: " .. tostring(v))
			end,
		}, ctx.flag("AP_AccuracyMode"))
		apMain:SubLabel({ Text = "Low = simple hit check (fast).  High = angle/geometry check (fewer false blocks)" })
		slider(apMain, { Name = "FOV", Flag = "AP_FOV", Default = Config.FOV or 360,
			Min = 1, Max = 360, Suffix = "°", Callback = function(v) Config.FOV = v end })
		apMain:SubLabel({ Text = "only reacts to enemies in this cone\n360 = all around u" })
		slider(apMain, { Name = "Range", Flag = "AP_Range", Default = Config.Range or 32,
			Min = 8, Max = 64, Suffix = " st", Callback = function(v) Config.Range = v end })
		slider(apMain, { Name = "Max Height Diff", Flag = "AP_MaxHeight", Default = Config.MaxHeightDiff or 12,
			Min = 4, Max = 40, Suffix = " st", Callback = function(v) Config.MaxHeightDiff = v end })
		apMain:SubLabel({ Text = "ignore enemies this far above/below u (anti platform-cheese)" })

		apMain:Divider()
		apMain:Header({ Name = "Rotation" })
		boolToggle(apMain, "Auto Face", "Auto Face", function() return Config.AutoFace end, function(v) Config.AutoFace = v end)
		apMain:SubLabel({ Text = "turn to face the attacker (needed for directional block/parry)" })
		boolToggle(apMain, "Instant Multi-Target Snap", "Multi Snap",
			function() return Config.MultiFaceHard end, function(v) Config.MultiFaceHard = v end)
		apMain:SubLabel({ Text = "in a group fight snap instantly to the next attacker" })
		boolToggle(apMain, "Hard Snap Near Contact", "Hard Snap", function() return Config.BlockFaceHard end, function(v) Config.BlockFaceHard = v end)
		apMain:SubLabel({ Text = "snap exactly on target right before the hit lands" })
		slider(apMain, { Name = "Rotation Speed", Flag = "AP_FaceLerp",
			Default = Config.FaceLerp or 0.80, Min = 0.10, Max = 1.00, Precision = 2,
			Callback = function(v) Config.FaceLerp = v end })
		slider(apMain, { Name = "Rotation Predict Cap", Flag = "AP_RotPred",
			Default = Config.RotPredMaxDeg or 200, Min = 60, Max = 300, Suffix = "°",
			Callback = function(v) Config.RotPredMaxDeg = v end })

		-- ── Section 2 — Dodge (Right box): behaviour + tuning + must-dodge ──
		local apDodge = AP:Section({ Side = "Right" })

		apDodge:Header({ Name = "Dodge" })
		feature(apDodge, {
			Title = "Dodge All Heavies", Flag = "AP_DodgeHeavy",
			get = function() return Config.DodgeHeavy end,
			set = function(v) Config.DodgeHeavy = v end,
			Desc = "dodge EVERY heavy attack instead of blocking\nnot recommended — burns i-frames",
		})
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
		slider(apDodge, { Name = "Heavy Trust Range", Flag = "AP_HeavyRange", Default = Config.HeavyTrustRange or 14,
			Min = 6, Max = 24, Suffix = " st", Callback = function(v) Config.HeavyTrustRange = v end })
		apDodge:SubLabel({ Text = "how close a heavy must be before we fully trust it (lunges are caught farther out automatically)" })

		apDodge:Divider()
		apDodge:Header({ Name = "Must-Dodge List" })
		do
			-- В игре есть только M1 и M2 (боевые модули: M1, M2, Grapple, Evasive, Block —
			-- отдельного Skill-каста нет). Поэтому предлагаем ровно два типа; grab/slam —
			-- это M2 соответствующего стиля (Wrestling/Dirty).
			local STYLES = {
				"Default","Basic","Boxing","Bulky","Dirty","Hakari","Karate","Kure",
				"MuayThai","SkyGaoLang","Variant","Taekwondo","Wild","WingChun",
				"Wrestling","Capoeira","Slugger",
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
		apBox:SubLabel({ Text = "boxing style only\nface the enemy n throw ur own M2 i-frames instead of rolling" })
		slider(apBox, { Name = "Pre-Face Time", Flag = "AP_PreFace", Default = Config.BoxingPreFace or 0.5,
			Min = 0.1, Max = 1.0, Precision = 2, Suffix = " s", Callback = function(v) Config.BoxingPreFace = v end })
		apBox:SubLabel({ Text = "how long to lock onto the enemy before countering" })

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
			Desc = "aggressive addon: auto-attacks stunned/interruptible enemies\nmaster switch for the stuff below",
		})

		apPlay:Divider()
		apPlay:Header({ Name = "Behaviour" })
		boolToggle(apPlay, "Punish After Parry", "Punish After Parry",
			function() return Config.AP_PunishOnParry ~= false end, function(v) Config.AP_PunishOnParry = v end)
		apPlay:SubLabel({ Text = "a perfect parry stuns them → instantly auto-M1 the stunned enemy in range" })
			boolToggle(apPlay, "Interrupt Heavies", "Interrupt Heavies",
				function() return Config.AP_InterruptHeavy ~= false end, function(v) Config.AP_InterruptHeavy = v end)
			apPlay:SubLabel({ Text = "stagger a heavy with a fast M1 instead of parrying it — heavies have a long windup so there's plenty of time\nworks in group fights too (if the next threat isn't too close); iframe/grab heavies still get parried" })
			apPlay:SubLabel({ Text = "note: our M1 always uses the fast custom builder (bypasses the 450ms throttle) — no toggle needed" })

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
		slider(apPlay, { Name = "M1 Reach", Flag = "AP_BaseReach", Default = Config.AP_BaseReach or 5.5,
			Min = 3, Max = 10, Precision = 1, Suffix = " st", Callback = function(v) Config.AP_BaseReach = v end })
		apPlay:SubLabel({ Text = "scaled by ur character height automatically" })
		slider(apPlay, { Name = "Interrupt Margin", Flag = "AP_InterruptMargin",
			Default = math.floor((Config.AP_InterruptMargin or 0.05) * 1000), Min = 0, Max = 150, Suffix = " ms",
			Callback = function(v) Config.AP_InterruptMargin = v / 1000 end })
		apPlay:SubLabel({ Text = "safety buffer\nhigher = only interrupt when clearly faster" })

		apPlay:Divider()
		apPlay:Header({ Name = "Test" })
		boolToggle(apPlay, "Blatant Test Mode", "Blatant Test Mode",
			function() return Config.Blatant end, function(v) Config.Blatant = v end)
		apPlay:SubLabel({ Text = "TEST ONLY: fires block + raw M1 at the same time, no animation\nvery obvious / detectable, and it SUPPRESSES boxing-counter — keep OFF for normal play" })

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
		apVis:Header({ Name = "Elements" })
		boolToggle(apVis, "Rotating Ring", "Rotating Ring",
			function() return Config.VizRing end,
			function(v) Config.VizRing = v; if not v then pcall(vizHideAll) end end)
		boolToggle(apVis, "Target Hitbox", "Target Hitbox",
			function() return Config.VizHitbox end,
			function(v) Config.VizHitbox = v; if not v then pcall(vizHideAll) end end)
		boolToggle(apVis, "Restrict Zone", "Restrict Zone",
			function() return Config.VizRestrict end,
			function(v) Config.VizRestrict = v; if not v then pcall(vizHideAll) end end)

		apVis:Divider()
		apVis:Header({ Name = "Ring & Range" })
		slider(apVis, { Name = "Ring Speed", Flag = "AP_VizRingSpeed",
			Default = math.floor((Config.VizRingSpeed or 1) * 100), Min = 10, Max = 300, Suffix = "%",
			Callback = function(v) Config.VizRingSpeed = v / 100 end })
		slider(apVis, { Name = "Ring Size", Flag = "AP_VizRingScale",
			Default = math.floor((Config.VizRingScale or 1) * 100), Min = 40, Max = 250, Suffix = "%",
			Callback = function(v) Config.VizRingScale = v / 100 end })
		slider(apVis, { Name = "Render Distance", Flag = "AP_VizRange",
			Default = Config.VizRange or 100, Min = 20, Max = 250, Suffix = " studs",
			Callback = function(v) Config.VizRange = v end })

		apVis:Divider()
		apVis:Header({ Name = "Colors" })
		apVis:Colorpicker({ Name = "Ring Gradient A", Default = RING_A,
			Callback = function(c) RING_A = c end }, ctx.flag("AP_RingA"))
		apVis:Colorpicker({ Name = "Ring Gradient B", Default = RING_B,
			Callback = function(c) RING_B = c end }, ctx.flag("AP_RingB"))
		apVis:Colorpicker({ Name = "Safe Cone", Default = CONE_SAFE,
			Callback = function(c) CONE_SAFE = c end }, ctx.flag("AP_ConeSafe"))
		apVis:Colorpicker({ Name = "Hit Cone", Default = CONE_HIT,
			Callback = function(c) CONE_HIT = c end }, ctx.flag("AP_ConeHit"))
		apVis:Colorpicker({ Name = "Restrict Ring", Default = RESTRICT_COL,
			Callback = function(c) RESTRICT_COL = c end }, ctx.flag("AP_Restrict"))

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

		-- ═══════════════════ TAB: Debug ═══════════════════
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

