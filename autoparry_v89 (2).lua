-- ИЗМЕНЕНО: 2026-07-17 02:21:20 UTC | AutoParry V74 | hitbox-driven dodge + Boxing M2 timing
-- AutoParry (Potassium) — combat autoparry / desync / boxing-counter
-- Luraph macro raw shim. The per-Heartbeat scheduler is wrapped in a
-- LPH_NO_VIRTUALIZE(function() ... end) macro so Luraph keeps the parry-timing
-- path native (virtualized timing math = missed parries). You CANNOT declare a
-- local/variable named LPH_* — Luraph reserves the prefix and errors with
-- "cannot be used as a variable name". So when run raw (un-obfuscated) we install
-- an identity fallback under that name via a STRING key (built by concat so the
-- reserved token never appears as an identifier). After Luraph the macro call
-- sites are replaced at compile time and this line is dead/harmless.
do
	local k = "LPH" .. "_NO_VIRTUALIZE"
	local G = (type(getgenv) == "function") and getgenv() or _G
	if not G[k] then G[k] = function(f) return f end end
end
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
	WillHitCloseCap = 12,   -- [V109] студы: макс. предикт в сторону сближения (6.5→12: ловим ВБЕГАЮЩИХ
	                        -- врагов, чей наскок за время замаха закрывает 8-12 студов; доп. clamp по
	                        -- фактической дистанции в hitboxGeom не даёт predA проскочить за нас)
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
	-- доворачивается к нам). Ловим по ЗНА��У довор����та (facing приближается к нам между
	-- кадрами), а не по мгновенной angY (шумной). Работает и в High, и в Low.
	DragDetect    = true,
	DragTurnMinDeg= 35,     -- град/с: доворот в������ше этого + приближение facing к нам = drag-угроза
	DragTrustRange= 13,     -- радиус (студы), где drag-довороту даём доверие
	Key_Accuracy  = Enum.KeyCode.B,

	-- [V89] HEAVY-ПРИОРИТЕТ. Тяжёлые (M2) и скиллы — выпады, атакующий закрывает дистанцию в
	-- замахе, а velCap=2.0 обрезал predA → geom-бокс отбраковывал их как "never-in-hitbox"
	-- (в диаг ровно так пропала Capoeira M2 → Ragdoll-каскад → провал мультибоя). Тяжёлы�� в
	-- расширенно�� радиусе, если смотрит ~н�� нас ��ЛИ реально сближается, считаем угрозой сразу.
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
		-- [V114] M1 APPROACH-TRUST. КОРЕНЬ жалобы «враг в ~10 studs подходит во время замаха → скрипт
		-- не успевает; когда всегда в радиусе — парри норм». В High лёгкий M1 доверялся ТОЛЬКО когда
		-- предсказательный бокс (predA+forward) уже накрывал нас. У ВБЕГАЮЩЕГО врага closing≈0 в начале
		-- замаха (сперва замах, step-in в середине) → бокс накрывает поздно → willHitMe=false почти до
		-- контакта → press в упор (в логе pressDt=0ms LATE). HeavyTrust решает это для M2/SKILL, но для
		-- M1 такого пути НЕ было. Фикс: committed M1, НАЦЕЛЕННЫЙ в нас (faceDotPred) и который НА МОМЕНТ
		-- контакта окажется в пределах досягаемости (radial predict по closing) → доверяем СРАЗУ, не
		-- дожидаясь бокса → press планируется заранее → PERFECT. Ложняков нет: стоячий whiff (closing≈0,
		-- dist-at-contact = dist > reach) НЕ триггерит; смотрящий мимо отсекается faceDotPred.
		M1ApproachTrust    = true,
		M1ApproachRange    = 14,    -- макс. текущая дистанция, на которой рассматриваем approach-trust для M1
		M1ApproachFaceMin  = 0.30,  -- предсказанный facing·toMe (нацелен в нас) — иначе чужой/мимо-удар
		M1ApproachReachPad = 3.0,   -- запас к forward: dist-на-контакте ≤ forward+pad ⇒ долетит

		-- [V126] M1 BAIT-GATE. Жалоба: «скрипт легко разбайтить — ударить относительно рядом,
		-- если враг смотрит на меня удар регается, если нет — нет». Сервер строит M1-хитбокс
		-- по facing атакующего в момент контакта (мгновенно, без задержки — victim НЕ проверяет
		-- угол). Значит свинг, в котором враг НИ РАЗУ фактически не наводится на нас и НЕ
		-- доворачивается к нам — физически не попадёт → это байт. Предиктный конус (faceDotPred)
		-- легко обмануть кратким дёрганьем прицела: angY скачет → predLook переворачивает на нас
		-- → trust → жжём блок/сбиваем тайминг. Гейт: для M1 доверять, только если враг РЕАЛЬНО
		-- смотрит в нашу сторону (rawDot) ЛИБО измеримо доворачивается к нам. ТОЛЬКО M1 — у
		-- M2/скиллов уникальные/широкие хитбоксы и лунжи (просил пользователь), их не трогаем.
		M1BaitGate     = true,
		M1CommitFaceMin = 0.10,  -- rawDot(текущий facing·toMe) ≥ этого = реально смотрит в нашу
		                         --   полусферу (~84° конус). Ниже И без доворота к нам → байт.
		M1BaitTurnMinDeg = 25,   -- град/с фактического доворота К НАМ, снимающего байт-гейт
		                         --   (реальный снап-финт со спины проходит; статичный байт — нет)

	-- [V116] Адаптивная калибрация УДАЛЕНА (отравляла между врагами — см. коммент у press-схемы).
	-- Пр������д����кт чисто математический; resAvg в логе — только диагностика точности, в press НЕ подаётся.
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

	-- [V74] HITBOX-DRIVEN DODGE: fire dodge when the actual server hitbox appears,
	-- instead of relying only on the predicted animation timeline. This fixes M2/Boxing
	-- and other delayed hitboxes where predicted contact is far from real hit.
	HitboxDodge     = true,
	HitboxNearDist  = 6.0,   -- studs: if a hitbox part is this close, treat it as imminent
	HitboxDodgeLead = 0.05,   -- small safety margin before the hitbox contacts
	-- [V116] Никакой контакт-коррекции нет: и flat M2ContactBias (V113), и адаптивный калибратор
	-- (V115) удалены — калибрация отравляла между врагами (обучалась на одном, ломала второго).
	-- Предикт чисто математический: таймлайн анимации + живой TimePosition.
	ChargeStallMs = 45,
	ReleaseGap    = 0.40,

	-- [V103] FACE-GATE BLOCK: не жечь нажатие блока (и 0.5с BlockCooldown), пока смотрим спиной к
	-- атакующему — блок направленный, сервер такой парри отклонит. Ждём доворота (applyFacing),
	-- пр��с��им при приемлемом facing ИЛИ когда времени уже нет (последний шанс). Дефолт ON.
	FaceGateBlock = true,
	FaceGateMin   = 0.2,       -- мин. faceDot (cos) до а��аку��щего, при котором разрешаем нажатие

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
	-- [V127] LOW-PING LEAD FLOOR. Жалоба: у игрока с НИЗКИМ пингом (52–71мс в диаге) парри
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

	MinActGap     = 0.030,
	MinDeactGap   = 0.050,

	MatchWindow   = 1.30,
	-- [V125] окно, в котором ВТОРОЙ (и далее) серверный OUT того же типа от того же врага
	-- считается доп-ударом ОДНОГО мультихит-свинга (Boxing M2MultiHitCount=2 шлёт 2 события
	-- Hit/Blocked на одну анимацию), а НЕ новой атакой. В логе 2-й страйк приходил +0.44..1.20с
	-- после свинга → берём с запасом = MatchWindow.
	MultiHitWindow = 1.30,

	-- [V120] МАСТЕР-ТУМБЛЕР ДОДЖА. Раньше было 7 независимых додж-триггеров (iframe-cluster,
	-- must-dodge, blatant, outnumbered/combo/exposed-escape, heavy), каждый со СВОИМ саб-тумблером,
	-- но БЕЗ единого выключателя — все дефолтом ON. Отсюда «доджит с нихуя»: юзер гасил один флаг,
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
	-- блокируемый удар — его надёжнее спарировать. Грант тратим только если реально НЕ можем блокнуть
	-- ИЛИ это мультиугроза (2+ контакта в окне, одним блоком не покрыть).
	OutnumberEscapePreferBlock = true,
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

	-- [V66] ЭКСТРЕННЫЙ ДОДЖ дв����х угроз. ��сли 2-й ко��такт прилетает раньше, чем мы
	-- физически успеваем развернуться к нему + перевзвести перфект, блок 2-г��
	-- нев��змо��ен → доджим оба ���разу (iframes покрывают обоих). Порог = реальное
	-- время разв��рота (по угловой скорости) + запас на перевзвод.
	EmergencyDualDodge = true,
	TurnRateDegPerSec  = 720,   -- насколько быстро HRP реально доворачивается снапом
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
	BoxingCounterReach= 5.5,   -- макс. плоская дистанция до атакующего, студы (ТЗ юзера)
	BoxingCounterGap  = 0.30,  -- анти-даблфайр: не слать M2 повторно чаще (сек). НЕ задержка перед 1-м
	                           -- ударом — только защита от двойной отправки в сетевом окне до того,
	                           -- как появится атрибут M2Cooldown (реальный кулдаун держит игра).

	-- Skill Addons: per-style combat behaviors that plug into the parry brain.
	-- Each maps to a REAL mechanic found in CombatConfig, not a placeholder.
	SkillAddon        = true,
	SA_WrestlingGrab  = true,   -- enemy Wrestling M2 = unblockable grab (M2GrantsHyperArmor) → force dodge
	SA_DirtyGrab      = true,   -- enemy Dirty grab/M2 (GrappleDirtyHit, ImmuneToRagdollM2) → force dodge
	SA_HakariRead     = true,   -- widen window for Hakari momentum M2 (HakariMomentumM2HitboxDelay 0.62)
	SA_HakariWiden    = 0.05,   -- extra front/hold seconds applied to a Hakari M2
	-- [V131] GRAPPLE WIN. Настоящее состояние борьбы = атрибут Grappling==true на персонаже.
	-- В окне клэша (Grapple.Duration=2.29) сервер отдаёт победу тому, кто в борьбе жмёт M2
	-- непрерывно/последним (проигравшему летит GrappleWinnerStun). Поэтому, ПОКА мы в грэппле,
	-- спамим M2 — так остаёмся «последним атакующим». Вне грэппла (Grappling≠true) фича молчит,
	-- поэтому в обычном бою M2 больше НЕ фаерится (это была причина ложных срабатываний).
	SA_GrappleWin     = false,  -- while Grappling==true, spam M2 to stay the last attacker & win the clash
	-- [V91] BLATANT force-dodge. Игра НЕ даёт додж, когда мы застряли в собственной атаке
	-- (self-busy) или в софт-стане (Stunned/CantAnything) — из-за этого «атаковал не вовремя →
	-- съел удар». Этот аддон ОВЕРРАЙДИТ блокировку: если удар вот-вот при��етит, а мы залочены
	-- софт-��остоянием и не можем блокнуть — форсим сам dodge-инпут (сервер его примет).
	-- Жёсткие состояния (Ragdoll/Grabbed/Downed) НЕ обходим — там дэш физичес��и ничего ����е даёт.
	-- Blatant = палевно (легит-игрок не смог бы), поэтому по умолчанию ВЫКЛ.
	SA_BlatantDodge   = false,
	SA_BlatantWindow  = 0.32,   -- сек до контакта: в этом окне срабатывает форс-додж

	-- [V97] AutoPlay addon — автоатака. По умолчанию ВЫКЛ (агрессивное поведение).
	AutoPlay          = false,  -- мастер-тумблер аддона
	AP_PunishOnParry  = true,   -- добивать M1 застаненного врага после идеального парри
	AP_BaseReach      = 5.5,    -- базовый реч нашего M1 (ForwardOffset 4 + запас), студы
	AP_RefHeight      = 5.5,    -- эталон высоты модели для масштаба реча по росту
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
	AP_M2Stun         = 1.0,    -- CombatConfig ParryStun.M2 (стан после M2-парри)
	AP_M1Stun         = 0.5,    -- оценка стана после M1-парри (RecoveryLockout врага)
	AP_PollGap        = 0,      -- [V101] троттл поллинга tryM1 = 0 (пробуем КАЖДЫЙ кадр; настоящий
	                            -- рейт держит игровая tryM1 по AttackDuration 0.45с). Макс��мальная
	                            -- скорость реакции: как только сервер снимает parry-lockout 0.15с — бьём.
	AP_FaceHold       = 0.35,   -- сколько держать лицо на цели после выстрела M1
	-- [V101] Комбо-контроль AutoPlay. "Follow" (дефолт) — родная tryM1 сама циклит ��дары комбо
	-- 1→2→3→4→1 (u19 = u19%4+1). "Fixed" — фо��сим один и тот же удар комбо (AP_FixedHit) через
	-- debug.setupvalue(u19) прямо перед свингом. Полезно для стабильного стартового удара.
	AP_ComboMode      = "Follow",  -- "Follow" | "Fixed"
	AP_FixedHit       = 1,          -- 1..4 — какой удар комбо бить в режиме Fixed
	-- [V105] СВОЙ M1-БИЛДЕР ВСЕГДА (fireM1Custom): обходит игровой 450мс-троттл (u21) и клиентские
	-- локи (u32/u33), шлёт ServerCheck сам. Единственный потолок — CombatRemoteClient.Fire
	-- (80мс burst / ~4-в-сек). Тумблеров Turbo/Fast больше нет — это база, всегда включено.

	-- [V98] реагировать только когда руки одеты (Equip==true). Иначе сервер всё равно
	-- откажет и в блоке, и в атаке (Block.lua/M1.lua требуют Equip). Кросс-платформенно.
	RequireEquip      = true,

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
	--   idlemask  — постоянный спуф IDLE, пока ты атакуеш����.
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
	DesyncClientVisible = false,  -- [V72] false → decoy тебе невидим, локально чистая реальная атака
	DesyncSendHz      = 0,        -- Anti-AutoParry decoy re-sends per second; 0 = auto (track length)
	-- Invisible desync: реплицируем ��онтортну��ый/опущенный корень на сервер (другие тебя не видят),
	-- локально каждый RenderStep возвращаем на место (ты ��идишь себя ��орма��ьно).
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

	-- [V122] сколько держим жёсткий взгляд на враге ПОСЛЕ выстрела M2-counter (сервер строит
	-- boxing-M2 хитбокс по нашему LookVector в момент ServerCheck → надо смотреть точно на врага).
	BoxingFaceLockDur = 0.55,

	-- [V62] ГИБРИД мульти��оя: перфектим ближайшего, остальным держим guard
	-- непрерывно (нулевые дыры = нулевые полные ������иты). holdUntil тянется по
	-- самому дальнему угрожающему контакту в кластере, guard не отпускается
	-- в середине burst, re-press в BlockCooldown исключён.
	MultiThreatGuard  = true,
	MultiThreatMinN   = 2,      -- со скольких одновременных угроз включать held-режим
	-- [V73] multi-target knobs
	BlockCooldown     = 0.50,
	SequentialSpread  = 0.78,
	MultiFaceAngleMax = 70,
	MultiFaceJitter   = 0.30,
	MultiFaceOnlyFront= true,
	MinActGap         = 0.030,
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
	-- [V91] ПРЕДИКТ РОТАЦИИ автофейса: целимся чуть НАПЕРЁД движения врага (ведём его
	-- позицию по скорости на FaceLead сек), чтобы facing не отставал от ст��ейфа/забегания
	-- за спину. Держим предикт малым (иначе перелёт при резкой смене направления).
	FaceLead      = 0.07,   -- сек упреждения по скорости врага
	FaceLeadMax   = 4,      -- студы: кап упрежде��ия
	-- [V97] PING-SCALED предикт facing (applyFacing). Упреждение = vel * (ping * FacePingLead),
	-- т.к. рассинхрон позиции врага прямо пропорционален латентности. FaceLeadCap — верхний предел
	-- по времени (сек), FaceLeadMaxStuds — по расстоянию (fallback-кап, когда цель почти в упор).
	FacePingLead  = 1.0,
	FaceLeadCap   = 0.28,        -- [V118] 0.22→0.28: пинг в логе до 244ms, даём полный desync-lead
	FaceLeadMaxStuds = 16,       -- [V118] 7→16: общий fallback-кап (только vel≈на л��нии/в упор)
	-- [V118] РАЗДЕЛЬНЫЕ капы боковой/радиальной составляющей упреждения. КОРЕНЬ жалобы «враг
	-- дэшит В УПОР (радиально) + толкается влев��/вправо (боково) → блок, не парри»: старый единый
	-- кап (7 студ) на ВЕСЬ вектор vel*lead → большая РАДИАЛЬНАЯ скорость дэша съе��ала весь бюджет
	-- → БОКОВАЯ коррекция (та, что задаёт угол facing) обрезалась пропорционально → лицо отставало
	-- (в логе face=0.2/-0.6 BACK! при валидном press → сервер даунгрейдит перфект в обычный блок).
	-- Фикс: раскладываем vel на радиаль (враг↔я, почти не влияет на угол) и боковую (задаёт угол),
	-- капим РАЗДЕЛЬНО. Боковой лимит щедрый (угол важен), радиальный маленький (анти-��ерелёт в упор).
	FaceLatMaxStuds = 18,        -- кап БОКОВОГО lead (перпендикуляр линии врагу) — главный для угла
	FaceRadMaxStuds = 5,         -- кап РАДИАЛЬНОГО lead (вдоль линии) — на угол не влияет, режем сильнее

	-- [V69] БЛОК НЕНАПРАВЛЕННЫЙ (доказано дампом: attacker M1 проверяет только
	-- атрибут Blocking жертвы; Block-модуль — только PerfectBlocking; VictimHitbox —
	-- лишь попадание в бокс. НИГДЕ нет dot/LookVector/угла на стороне жертвы). Значит
	-- один guard прикрывает всех атакующих со всех сторон, и доворачиваться к врагу
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
	VizHitbox     = true,   -- бокс хитбокса цели
	VizRestrict   = true,   -- зона ограничения (keep-out)
	VizRingSpeed  = 1.0,    -- множитель скорости анимации кольца (0.1–3.0)
	VizRingScale  = 1.0,    -- множител�� радиуса кольца (0.4–2.5)
	VizRange      = 100,    -- дальность (студы), на которой ищется/рисуется цель
	-- [V111] PERF: потолок частоты ПЕРЕРИСОВКИ визуалов. ESP чисто косметика — при 120+ реальных
	-- fps перери��овыват�� кольцо(40 сег)+конус каждый кадр (≈140 WorldToViewportPoint + 140 записей
	-- Drawing) = САМАЯ дорогая всегда-активная работа. Кап 60 → дровинги живут между апдейтами
	-- (не скрываются), ESP визуально гладкий, а нагрузк�� на высоком fps падает вдвое+.
	VizMaxFPS     = 60,
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
	Key_DesyncScan = Enum.KeyCode.Quote,         -- [V75] ' → запустить raknet скан-сес��и��
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
	                        -- если blocking ��брошен в обход releaseBlock (dodge/counter/outcome).
	holdUntil    = 0,
	status       = "ARMED",
	lastThreat   = nil,
	parryCount   = 0,
	dodgeCount   = 0,
	grantEscapes = 0,
	selfBusyUntil= 0,
	attackBusyUntil = 0,   -- [V117] busy ТОЛЬКО из-за нашей АТАКИ (не из-за дэша) — для exposed-escape
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
	-- AutoRotate/шифтлок) — они дрались, отсюда залипание на одной це��и и дёрганье. Теперь schedulerStep
	-- лишь ВЫСТАВЛЯЕТ цель сюда, а применяет ОДИН аппликатор applyFacing в RenderStepped (последний
	-- писатель кадра, гасит AutoRotate). faceGoalHRP=на кого смотреть, Hard=жёсткий снап vs л��рп,
	-- Until=до какого времени держать (грейс после последней выставки), Hum=кэш Humanoid для AutoRotate.
	faceGoalHRP   = nil,
	faceGoalHard  = false,
	faceGoalUntil = 0,
	faceHum       = nil,
	faceGoalPos   = nil,   -- [V73] midpoint facing goal
	-- Подтверждённое CombatClientRemoteEvent состояние grapple. Атрибут Grappling остаётся
	-- fallback, но remote даёт точного второго участника и тип клэша.
	grapple       = { active=false, dirty=false, foeName=nil, clashType=nil, winnerName=nil, startedAt=0 },
	noParryActive = false,
	noParryNow    = false,
	grappleChar   = nil,
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
-- ~68ms вместо реальных 111–345ms → ��лок стабильно опаздывал (LATE) на любом заметном пинге.
-- Фикс: первичный источник — LocalPlayer:GetNetworkPing() (метод самого инстанса ��грока,
-- доступен в ЛЮБОМ контексте, не бросает; возвращает one-way в секундах → RTT = ×2). Stats
-- Data Ping (уже RTT в мс) — как второй источник; берём МАКСИМУМ (перекомпенсация безопаснее
-- недокомпенсации для парри). Если оба недоступны — отдаём последнее валидное значение, а НЕ
-- хардкод 60. Итог: и hot-path, и header видят один настоящий RTT.
local _lastGoodPing = 0.08
local function getPingRaw()
	local best

	-- Источник A: Player:GetNetworkPing() — one-way (сек). RTT ≈ ×2.
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
	-- [V116] РОБАСТНЫЙ МЕДИАННЫЙ ПИНГ. Кольцо сырых сэмплов RTT; getPing() = медиана окна.
	-- Медиана игнориру��т одиночные спайки/пр��валы Data Ping (пилообразный шум) и отслеживае��
	-- устойчивый RTT — без залипания на пике (прежний peak-hold) и без петли о��учения.
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
	-- [V111] PERF: кэш getPing по времени (пересчёт не чаще ~раза в кадр). Держим полями V93,
	-- НЕ отдельными local — лимит 200 живых локалов на функцию (модуль впритык).
	pingCacheClock = -1,
	pingCacheVal   = 0.08,
	-- [V123] PERF: персистентные буферы imminent/cluster-угроз. Раньше schedulerStep делал
	-- `imminent={}` и `cluster={}` КАЖДЫЙ Heartbeat (даже при 0 угр��з) → 2 таблицы-мусора/кадр →
	-- GC-дёрганье на высоком fps. Переиспользуем, чистим table.clear в начале кадра. Оба живут
	-- ТОЛЬКО внутри кадра (не escape'ят в State/поля угроз — только читаются и ставят th-флаги).
	imminentBuf = {},
	clusterBuf  = {},
	-- [V132] persistent cluster attacker-seen table (no per-frame allocation)
	seenAttackers = {},
	-- [V132] reusable RaycastParams for dodge wall-check
	dodgeParams = nil,
	dodgeChar = nil,
}

-- [V116] РОБАСТНЫЙ МЕДИАННЫЙ ПИНГ. Прежний EMA+peak-hold ЛАТЧИЛ спай�� (в логе header ping=224
-- при combat-ping=158) → uplink раздувался → жали СЛИШКОМ РАНО. Медиана окна последних сырых
-- сэмплов игнорирует одиночные выбросы В ОБЕ СТОРОНЫ (Data Ping пилит вверх и вниз) и отслеживает
-- устойчивый RTT: один спайк-кадр среди 24 сэмплов НЕ сдвигает медиану, а реально выросший пинг
-- поднимает её за <1с. Это принципиальная оценка центральной тенденции, не костыль и не обучение.
-- [V111] PERF: getPing() зовётся из uplink() (schedulerStep) И applyFacing (RenderStepped) каждый
-- кадр → мемоизируем: новый сырой сэмпл кладём не чаще PingSampleGap, медиану пересчитываем только
-- при добавлении сэмпла, между добавлениями отдаём кэш.
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

local function uplink()
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
end

-- [V116] Адаптивный корректор контакта УДАЛЁН. Отравлял между врагами: меди��на predErr копилась
-- по (kind,style), но реальная ошибка доминируется ПИНГОМ конкретного игрока и выбросами (held-
-- анимации) ���� обучившись на одном враге, скрипт ломал тайминг по вто��ому. Предикт снова чисто
-- математический (таймлайн анимации + живой TimePosition), ResidByKS теперь только диагностика.

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
		if Config.ComboEscape and c:GetAttribute("ParryWindowDisabled") ~= true
		   and c:GetAttribute("ParryBuffered") == true
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
-- ФАКТИЧЕСКУЮ позици�� атакующего в момент удара, упреждение по скорости уводило прицел вбок
-- (в логах давало face=0.5 BACK на стрейфящем враге) → блок отклонялся.
local function computeMultiFaceGoal()
	if not Config.AutoFace then return nil end
	local me = localHRP(); if not me then return nil end
	local mePos = me.Position
	local flatMe = me.CFrame.LookVector; flatMe = Vector3.new(flatMe.X, 0, flatMe.Z)
	flatMe = flatMe.Magnitude > 0.05 and flatMe.Unit or Vector3.new(0, 0, 1)
	local t = {}
	for _, th in ipairs(Threats) do
		if th.threatens and th.attackerHRP and th.attackerHRP.Parent then
			local to = th.attackerHRP.Position - mePos
			local d = Vector3.new(to.X, 0, to.Z)
			local dist = d.Magnitude
			if dist > 0.05 then
				d = d.Unit
				local front = flatMe:Dot(d) > 0.05
				local key = th.attackerModel or th.attackerHRP or th.name
				t[#t+1] = {k=key, dir=d, dist=dist, front=front}
			end
		end
	end
	if #t < 2 then return nil end
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
--   • если парт атакующего уже есть — проверяем пе��есечение с нами 1:1 как игра (авторитетно);
--   • пока парт�� нет — предсказываем бокс РЕАЛЬНЫМ размером (кэш по типу атаки), без trust-
--     к��стылей (point-blank/heavy/drag/latch).
-- Пер-кадровый индекс живых ��артов по в��адельцу (Owner.Value). Скан один раз за FrameId,
-- чтобы не обходить папку по разу на каждую угрозу в м��льтибое. Всё состояние — в V93 (см. выше
-- ��ро лимит 200 локалов), новых local тут не заводим.
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
	for idx, child in ipairs(folder:GetChildren()) do
		if idx > 60 then break end
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

-- Точная (как в игре) проверка: пересекает ли РЕАЛЬНЫЙ парт атакующего ��аш персонаж.
-- true — есть парт и он в нас; false — па��т(ы) есть, но мимо; nil — активного парта нет.
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

-- [V74] Return the closest hitbox part for a given owner, plus its distance to us.
-- Used to trigger dodge right when the server hitbox becomes dangerous.
local function hitboxNearestPart(ownerName)
	if not ownerName then return nil, nil end
	local lst = hitboxIndex()[ownerName]
	if not lst or #lst == 0 then return nil, nil end
	local me = localHRP()
	if not me then return nil, nil end
	local best, bestD = nil, math.huge
	for i = 1, #lst do
		local part = lst[i]
		if part.Parent then
			local d = (part.Position - me.Position).Magnitude
			if d < bestD then bestD = d; best = part end
		end
	end
	return best, bestD
end

-- [V74] Update a threat's predicted contact based on the actual hitbox appearance.
-- When the server hitbox appears near us, we know the real hit is now, so we pull
-- contactAbs in to make the iframe window cover the actual registration window.
local function syncContactWithHitbox(th, now)
	if not Config.HitboxDodge then return end
	if th.dodged or th.hitboxSynced then return end
	local part, dist = hitboxNearestPart(th.name)
	if not part then return end
	-- First time we see the hitbox, remember it and snap contactAbs to just before it.
	if not th.hitboxSeen then
		th.hitboxSeen = now
		th.hitboxPart = part
	end
	local near = dist <= Config.HitboxNearDist
	local hitting = realHitboxHitsMe(th.name) == true
	if near or hitting then
		-- Pull contact in so the existing dodge/block math fires right now.
		local target = now + (hitting and 0 or Config.HitboxDodgeLead)
		if th.contactAbs > target then
			th.contactAbs = target
			th.hitboxSynced = true
		end
	end
end

local function hitboxGeom(th)
	local aHRP = th.attackerHRP
	if not aHRP or not aHRP.Parent then return nil end
	local now  = os.clock()
	local tHit = math.clamp((th.contactAbs or now) - now, 0, 0.6)
	local aPos = aHRP.Position
	local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
	-- [V67] кап смещения о�� velocity: у стр��йф��щего врага полная ��кс��раполяция
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
			-- Берём МАКС velocity- и измеренног�� сближения → бокс честно доводится к контакту.
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
			-- [V109] КОРЕНЬ High-бага «враг подходит и бьёт — скрипт не вовремя, как будто вне
			-- радиуса»: closeAmt капился жёстко WillHitCloseCap(6.5). Реально ВБЕГАЮЩИЙ враг за
			-- время замаха (tHit до ~0.45с при скорости бега 16-28 студ/с) закрывает 8-12 студов —
			-- 6.5 обрезал → predA НЕ доводился до нас → geom-бокс мимо → willHitMe=false → NO-PRESS,
			-- а когда враг физически в радиусе, контакт уже неминуем → LATE. Поднял cap до 12. НО
			-- предикт НЕ должен «проскакивать» за нас (иначе центр бокса уедет за спину) → clamp
			-- дополнительно по фактической дистанции до нас (останавливаем predA чуть НЕ доходя).
			-- Ложняков не добавляет: в High всё ещё держат facing-гейт (aimLook·toMe) и реальный
			-- размер парта — вбегающий, но целящийся НЕ в нас, отсекается по facing.
			local distToMe = Vector3.new(aPos.X - meG.Position.X, 0, aPos.Z - meG.Position.Z).Magnitude
			local closeCap = math.min(Config.WillHitCloseCap or 12, distToMe * 0.95)
			closeAmt = math.clamp(closeAmt, 0, closeCap)
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

	-- [V88] LATCH: как то��ько закоммиченный свинг хоть раз признан у��розой (в упор, лицом
	-- или че��ез доворот-на-нас), держим true до конца жиз��и угрозы. Это чинит финты с
	-- разворотом: враг бьёт спиной и доворачивается — раньше поздний кадр с "смотрит мимо"
	-- сбрасывал willHitMe и парри отменялся. Настоящий финт-кэнсел сюда не попадает: его
	-- раньше удаляет ветка th.feinted в scheduler.
	local mode = Config.AccuracyMode or "Low"

	-- [V93] В High доверяемся ТОЛЬКО ground-truth (реальный па��т) и ч��стой геометр��и; latch из
	-- Low-эвристик (point-blank/drag/heavy) здесь отключён — иначе High «залипал» бы на угрозах,
	-- которые в нас не попадают. Свой latch в High ставит лишь подтверждённое пересечение
	-- реального игрового хитбокса (th.gtConfirmed) в ветке ниже.
	if mode == "High" then
		if th.gtConfirmed then return true end
	elseif th.trustLatch then
		return true
	end

	-- [V102] BROADPHASE (High): ДЕШЁВЫЙ ранний отказ ДО дорогого hitboxGeom. Только для ��ЁГКИХ
	-- M1 — ��яжёлые (M2/SKILL) НИКОГДА не режем здесь (у них своя расширенная логика доверия
	-- HeavyTrust/lunge/mid-face ниже; V101-broadphase ошибочно резал стоячий нацеленный хэви на
	-- dist 24-30 → willHitMe=false → ни блока, ни interrupt → «стоим как вкопанный». Теперь хэви
	-- всегда проходит дальше). Для M1: отказ только если враг за HighBroadRange И НЕ приближается
	-- ни по velocity, ни по измеренной дельте поз��ции (ловит бег «туда-обратно с у��аром на входе»).
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
	-- БЕЗ дорогого пред��кта ротации.
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
	-- смотрит СЕЙЧАС, а куда бу��ет смотреть в момент ��дара — это и ловит финты.
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
	-- соз��авал временный CFrame НА КАЖДУЮ угрозу КАЖДЫЙ кадр — в мясорубке (2+ атакующих
	-- по нескольку треков) это давило GC и роняло FPS scheduler'а → он «переставал
	-- успевать». Ручная матрица Y-вращения даёт тот же вектор без мусора.
	local cy, sy   = math.cos(dyaw), math.sin(dyaw)
	local predLook = Vector3.new(rawL.X * cy + rawL.Z * sy, 0, -rawL.X * sy + rawL.Z * cy)
	predLook = (predLook.Magnitude > 0.05) and predLook.Unit or rawL
	local faceDotPred = predLook:Dot(toMe)

	-- [V88] SNAP-TURN FEINT: враг закоммитил свинг и АКТИВНО доворачивается на нас. Серверный
	-- хитбокс строится по его facing В МОМЕНТ удара, поэтому разворот из «спин��й» = р��альная
	-- угроза, хотя сейч��с смотрит мимо. Детект по знаку: предсказанный facing ближе к нам, чем
	-- текущий (rawDot) → он поворачивается в нашу сторо��у. Работает и в High, и в Low.
	local rawDot = rawL:Dot(toMe)
	-- [V90] DRAG/SNAP-TURN — ловим по ЗНАКУ д��вор��та (facing приближается к нам между кадрами),
	-- а не по мгновенной angY (она шумная и ч����сто 0 между physics-степами → старый детект
	-- пропускал «закрученные» атаки). Два независимых источника доворота, любого достаточно:
	--   • physics-предикт: predLook уже развёрнут к нам сильнее те��ущего (faceDotPred > rawDot)
	--   • измере��ный ��оворот за п��ошлый кадр: facing реально стал ближе к нам (prevLook→rawL)
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

	-- [V126] M1 BAIT-GATE сигнал: РЕАЛЬНАЯ нацеленность/доворот К НАМ (не предиктный конус,
	-- который легко обмануть дёрганьем прицела). Сервер строит M1-хитбокс по facing атакующего
	-- в момент контакта, поэтому свинг, где враг ни разу не смотрит на нас И не доворачивается —
	-- физически не попадёт = байт. Считаем ТОЛЬКО для M1 (у M2/скиллов свои широкие хитбоксы).
	-- gtConfirmed (реальный парт уже пересёк нас) — не переопределяем ground-truth.
	local m1FacingCommitted = true
	if Config.M1BaitGate and th.kind == "M1" and not th.gtConfirmed then
		local facesUs = (rawDot >= (Config.M1CommitFaceMin or 0.10))
		local turnsToUs = false
		if th.prevLook then
			local prevDot = th.prevLook:Dot(toMe)
			-- facing реально приближается к нам между ��адрами И скорость доворота зн��чима
			turnsToUs = (rawDot > prevDot + 0.01) and ((th.yawRate or 0) >= (Config.M1BaitTurnMinDeg or 25))
		end
		m1FacingCommitted = facesUs or turnsToUs
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
	-- остальных ��такующих (отсюда и «не справляется с мульти��таками»). Тяжёлые пропускать
	-- нельзя (их не перевзвести повторным блоком): если враг в расширенном радиусе И либо
	-- смотрит приме������ на нас (predFacing), либо реально СБЛИЖАЕТСЯ — считаем угрозой сразу,
	-- в обход geom-фильтра. Работает и в Low, и в High. Лишний блок безвреден (OmniBlock
	-- ненаправленный), а пропущенный хэви = проигр��нный разме��.
		-- [V93] HeavyTrust (радиусное доверие тяжёлым) — ТОЛЬКО не в High. В High тяжёлый лунж,
		-- который реально дойдёт, и так ловит предсказанный бокс (predA экстраполируется по
		-- velocity к нам); летящий мимо — не должен парироваться. Радиус тут = ложняки.
		if (th.kind == "M2" or th.kind == "SKILL") and Config.HeavyTrust then
			local aV       = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
			local toMeUnit = (dist > 0.05) and toMe or flatLook
			-- сближение по velocity (обычные дэши/выпады с LinearVelocity)
			local velClose = Vector3.new(aV.X, 0, aV.Z):Dot(toMeUnit)
			-- [V101] measured-closing: дельта дистанции по кадрам. Л��вит CFrame-твин-дэши
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
			-- (3) СРЕДНЯЯ ДИСТАНЦИЯ (heavyRange..HeavyFaceRange): дове��яем ТОЛЬКО е����ли тяжёлый
			-- нацелен ТОЧНО в нас узким конусом (HeavyFarFaceMin) — на такой дистанции это почти
			-- наверняка готовящийся выпад. Смотрит мимо / не идёт на нас → не парируем (нет ложняка).
			elseif dist <= (Config.HeavyFaceRange or 30) then
				if faceDotPred >= (Config.HeavyFarFaceMin or 0.85) then
					th.trustedHit = true; th.trustLatch = true
					return true
				end
			end
		end

		-- [V132] M2 HIGH-MODE FALLBACK. Long-windup M2s (Capoeira, MuayThai, Karate, Hakari,
		-- Boxing, Wrestling) часто двигаются боком/под углом, но их hitbox большой и delayed.
		-- Строгий предикт-бокс отбраковывал реальные M2 → "never-in-hitbox" MISS. Если враг в
		-- радиусе досягаемости lunge и не явно разворачивается от нас, лучше лишний блок, чем
		-- пропустить тяжёлый. Срабатывает ТОЛЬКО в High (в Low уже покрывает HeavyTrust).
		if mode == "High" and th.kind == "M2" and not th.trustLatch then
			local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
			local toMeUnit = (dist > 0.05) and toMe or flatLook
			local velClose = Vector3.new(aV.X, 0, aV.Z):Dot(toMeUnit)
			local measClose = 0
			if th.prevPos and th.prevPosT then
				local dtp = nowW - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx  = th.prevPos.X - myHRP.Position.X
					local pdz  = th.prevPos.Z - myHRP.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					measClose = (prevD - dist) / dtp
				end
			end
			local closing = math.max(velClose, measClose)
			-- long-windup M2 = стиль с M2HitboxDelay > 0.45; это практически всегда выпад/схватка
			loadGameModules()
			local m2Delay = 0.45
			pcall(function()
				if GameData.cfg and GameData.cfg.GetStyleM2HitboxDelay then
					m2Delay = GameData.cfg.GetStyleM2HitboxDelay(th.style or "basic", th.mom or false)
				end
			end)
			local longM2 = (type(m2Delay) == "number" and m2Delay > 0.45)
			local inLunge = dist <= (Config.HeavyLungeRange or 36)
			local facesUs = faceDotPred >= (Config.HighFaceMin or 0.25)
			local closingOk = closing > 4
			local alreadyClose = dist <= (Config.HeavyTrustRange or 14)
			if inLunge and (longM2 or alreadyClose) and (facesUs or closingOk) then
				th.trustedHit = true; th.trustLatch = true
				return true
			end
		end

		-- [V114] M1 APPROACH-TRUST: аналог HeavyTrust, но для ЛЁГКОГО M1 и с более узкими рамками.
		-- Ловит «враг в ~10 studs, во время замаха подходит и бьёт�� — раньше High-бокс накрывал нас
		-- поздно (closing≈0 в начале замаха) → willHitMe=false почти до контакта → LATE (pressDt=0).
		-- Доверяем, как только committed-M1 НАЦЕЛЕН в нас И по прогнозу окажется в досягаемости на
		-- момент контакта. НЕ латчим (в High каждый кадр перерешаем — финт/отмена мгновенно сбросят).
		if th.kind == "M1" and Config.M1ApproachTrust ~= false
		   and dist <= (Config.M1ApproachRange or 14) then
			local aV = safeGet(aHRP, "AssemblyLinearVelocity", Vector3.zero)
			local toMeUnit = (dist > 0.05) and toMe or flatLook
			local velClose = Vector3.new(aV.X, 0, aV.Z):Dot(toMeUnit)   -- сближение по velocity
			local measClose = 0                                          -- измеренное кадр-к-кадру
			if th.prevPos and th.prevPosT then
				local dtp = os.clock() - th.prevPosT
				if dtp > 1e-3 and dtp < 0.5 then
					local pdx   = th.prevPos.X - myHRP.Position.X
					local pdz   = th.prevPos.Z - myHRP.Position.Z
					local prevD = math.sqrt(pdx * pdx + pdz * pdz)
					measClose = (prevD - dist) / dtp
				end
			end
			local closing       = math.max(velClose, measClose, 0)
			local distAtContact = dist - closing * tHit          -- где он будет к контакту
			local reach         = forward + (Config.M1ApproachReachPad or 3.0)
			local faceMin       = (mode == "High")
				and (Config.M1ApproachFaceMin or Config.HighFaceMin or 0.30)
				or (Config.HeavyFaceMin or -0.30)
			-- нацелен в нас И (уже в досягаемости ИЛИ по прогнозу долетит к контакту)
			-- [V126] + bait-gate: не доверяем approach'у, где враг фактически не наводится и не
			-- доворачивается к нам (иначе он подходит боком/спиной и свингом не достаёт = ��айт).
			if faceDotPred >= faceMin and distAtContact <= reach and m1FacingCommitted then
				th.trustedHit = true
				return true
			end
		end

		if mode == "High" then
			-- [V93] HIGH = GROUND-TRUTH. Решает не «рядом и п��имерно смотрит», а реальная игровая
			-- геометрия удара.
			-- ── Шаг 1: реальный парт. Если игра УЖЕ породила хитбокс-парт этого атакующего в
			-- workspace.Hitboxes — проверяем пересечение с нами тем же методом, что и
			-- VictimHitboxService (GetPartBoundsInBox по нашему персонажу). Это авторитетно и
			-- пинг-независимо по геометрии; вертикаль/ориентация учтены самим партом.
			-- [V132] ground-truth hitbox check is expensive (GetPartBoundsInBox per part). Only
			-- run it close to contact or on every 3rd frame; otherwise rely on geometry.
			local gt = nil
			local tHit = math.clamp((th.contactAbs or nowW) - nowW, 0, 0.6)
			if tHit < 0.18 or (FrameId % 3 == 0) then
				gt = realHitboxHitsMe(th.name)
			end
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
			-- aPos/rawL), их объединение. Никаких trust-ра��иусов — только «мы внутри замаха».
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
			-- дальность/глубина от origin а��акующего вдоль его facing: центр пар��а ≈ forward,
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
			-- [V94] AIM-AWARE пр��дикт facing к МОМЕ��ТУ contact. Серверный хитбокс строится по yaw
			-- атакующего в момент удара (дамп VictimHitboxService). Прежний predLook капался жёстко
			-- на RotPredMaxDegHigh=55° → враг, доворачивающийся к нам со спины/сбоку, «не долетал»
			-- предиктом → back-facing gate его резал → MISS/поздний отве�� (жалоба «бьёт и
			-- поворачивается — скрипт не вовремя»). Считаем знаковый угол rawL→toMe и сколько враг
			-- РЕАЛЬНО успеет повернуть за tHit (rotRate = макс физической и измеренной кадр-к-кадру
			-- угловой скорости). Поворачиваем rawL к нам не больше, чем позволяет скорость:
			--   • доворачивается быстро → aimLook смотрит на нас → парируем ВОВРЕМЯ (взвод заранее);
			--   • стоит спиной б��з вращения → maxTurn≈0 → aimLook≈спина → aimDot низкий → мимо.
			local dotRT   = rawL.X * toMe.X + rawL.Z * toMe.Z
			local crossRT = rawL.X * toMe.Z - rawL.Z * toMe.X
			local angToUs = math.atan2(crossRT, dotRT)          -- знаковый угол rawL→toMe
			local maxTurn = math.max(rotRate, 0) * tHit          -- сколько успеет повернуть (рад)
			local phi     = math.clamp(angToUs, -maxTurn, maxTurn)
			local cphi, sphi = math.cos(phi), math.sin(phi)
			local aimLook = Vector3.new(rawL.X * cphi - rawL.Z * sphi, 0, rawL.X * sphi + rawL.Z * cphi)
			aimLook = (aimLook.Magnitude > 0.05) and aimLook.Unit or rawL
			-- [V96] POINT-BLANK дове��ие (как в LOW-ветке): в упор враг физически достаёт хитбоксом
			-- НЕЗАВИСИМО от facing, а серверный do��орот довершится к контакту. Прежде High жёстко
			-- резал ближние удары facing-гейтом → в логе валидные комбо-M1 (dist 3–6) п��дали в
			-- `MISS never-in-hitbox` → NO-PRESS/поздний блок. Ниже PointBlank сразу доверяем.
			-- [V126] point-blank авто-доверие: для M2/с��иллов безусловно (широкие хитбоксы,
			-- в упор не отвертеться), а для M1 — только если враг фактически наводится/
			-- доворачивается к нам (иначе в упор спиной = байт, M1-боксом не достанет).
			if dist <= (Config.PointBlank or 3.0) and (th.kind ~= "M1" or m1FacingCommitted) then
				th.trustedHit = true
				return true
			end
			-- [V126] M1 BAIT-GATE (глобально для M1 в High): свинг, где враг не смотрит на нас и
			-- не доворачивается — сервер построит хитбокс мимо → не попадёт. Отсекаем как чужой/
			-- байтовый ДО предиктного бокса (иначе краткий дёрг прицела раскручивал aimLook на нас).
			if not m1FacingCommitted then
				th.trustedHit = false
				th.offTarget  = true
				return false
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

	-- LOW: щедрое доверие ближнему бою (как V67), НО отбрако��ываем удары, явно
	-- направленные не в на�� (predFacing смотрит от нас �� мы не в упор) — чтоб�� не
	-- ��гри��ься на чужие атаки в замесе.
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
	local isNew = not c or (now - c.last) > COMBO_RESET
	if isNew then c = { idx = 0, last = now } end
	c.idx  = (c.idx % 4) + 1
	c.last = now
	ComboState[attacker] = c
	-- [V73] FPS: cap stale combo-state to avoid unbounded growth across many players
	ComboState._count = (ComboState._count or 0) + (isNew and 1 or 0)
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
end

-- [V132] Получить множитель замедления анимации на пинге (CombatPingAnimUtils).
local function getPingAnimMult(scaledDelay)
	loadGameModules()
	local pau = GameData.pau
	if pau and pau.GetPingAnimSpeedMultiplier then
		local ok, mult = pcall(function()
			return pau.GetPingAnimSpeedMultiplier(scaledDelay, LocalPlayer)
		end)
		if ok and type(mult) == "number" and mult > 0.05 and mult < 1 then
			return mult
		end
	end
	return 1
end

-- [V71] множитель скорости атаки конкретного АТАКУЮЩЕГО. Задержка удара в игре =
-- base / mult (GetScaledHitboxDelay). mult зависит от роста персонажа: низкий → до
-- 1.15 (бьёт на 15% быстрее), высокий → 0.85. Раньше мы всегда слали 1 → быстрые
-- враги давали LATE. Сначала пр��бу��м родные функции игры (future-proof при апдейтах),
-- потом фолбэк на задокументированную формулу от атрибута Height.
-- [V120] WEAK KEYS: кэш по МОДЕЛИ (Instance). Без weak-ключа каждый респавн/уход игрока = новый
-- перманентный ключ → таблица растёт бесконечно И держит мёртвые модели от GC (утечка памяти,
-- со временем GC-дёрганье → фризы → поздние нажатия). __mode="k": запись авто-удаляется, когда
-- модель становится собираемой. На корректность не влияет (чтение ��сегда по ЖИВОЙ модели).
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
	-- [V73] FPS: cap metadata cache
	if not AnimMetaCount then AnimMetaCount = 0 end
	AnimMetaCount = AnimMetaCount + 1
	if AnimMetaCount > 250 then
		for k in pairs(AnimMeta) do AnimMeta[k] = nil end
		AnimMetaCount = 0
	end
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
-- на ��лок-анимации keyframe-маркеры → resolveAnimMeta оши����очно принимал их за атаку (SKILL/M2)
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
					-- [V109] СТИЛЕВАЯ папка = содержит канонические удары (M2 / 1stM1 / 2ndM1). Так мы
					-- отличаем боевой ��тиль (Karate/Boxing/Kure/Striker/…) от НЕ-атакующих папок
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
							-- анимка проваливалась в BenignIds (loop2) → детект ГЛУШИЛ её насовсем → нет
							-- угрозы → ни блока, ни доджа, ни interrupt (юзер: «скрипт даже не атакует»).
							-- Теперь любая не-защитная / не-реакционная / не-idle анимка боевого стиля = SKILL.
							-- Ловится по keyframe-таймлайну (hitTimelineBase). Ложняков нет: реакции/блок/
							-- idle/walk/dash уже исключены, а папка гарантированно боевая (есть M1/M2).
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
							-- чтобы детект её видел. Реакции/успехи (ehit/success) остаются benign.
							local lname = d.Name:lower()
							if not (lname:find("ehit") or lname:find("success"))
								and (lname:find("crit") or lname:find("momentum")
									or lname:find("slam") or lname:find("special") or lname:find("finisher")) then
								AttackIds[id] = { kind = "SKILL", combo = nil }
							else
								BenignIds[id] = true
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
		mom   = (entry and entry.mom) or (legacy and legacy.mom) or false,
		name  = entry and entry.name or nil,
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
		local cfgv, multi = nil, 1
		if GameData.cfg then
			local ok, d = pcall(function() return GameData.cfg.GetStyleM2HitboxDelay(info.s, info.mom) end)
			if ok and type(d) == "number" then cfgv = d + WINDUP_EXTRA end
			-- multi-hit count (Boxing M2MultiHitCount=2): the meaningful contact is a LATER
			-- strike, so the bare first-hit config delay underestimates the block window.
			local okc, mc = pcall(function() return GameData.cfg.GetStyleNumber(info.s, "M2MultiHitCount", 1) end)
			if okc and type(mc) == "number" then multi = mc end
		end
		if not cfgv then
			cfgv = (LEGACY_M2_BASE[string.lower(info.s or "")] or 0.30) + WINDUP_EXTRA
		end
		-- [V124] КОНФИГ — авторитетный источник тайминга M2 для ОДНОhitовых стилей:
		-- GetStyleM2HitboxDelay = ровно та задержка, что сервер делит на mult роста
		-- (GetScaledHitboxDelay: delay/mult). Диаг: Basic M2HitboxDelay=0.525, attacker
		-- aMult=1.09 → 0.525/1.09 = 482мс, measured=485мс (ошибка 3мс). Раньше брали
		-- math.max(cfgv, info.hit) БЕЗУСЛОВНО → ��аркер анимации "Hit" (617мс) перебивал конфиг
		-- и мы жали блок на 130мс позже (predErr=-128ms LATE → HIT). Теперь маркер-страховка
		-- применяется ТОЛЬКО к мультиhit-стилям (Boxing), где реальный значимый контакт ~749мс
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
local function hitTimeline(info, combo, mult)
	local base = hitTimelineBase(info, combo)
	local m = (type(mult) == "number" and mult > 0.05) and mult or 1
	-- [V124] Сервер делит ВСЕ hitbox-задержки на mult роста атакующего (GetScaledHitboxDelay:
	-- delay/mult) — и M1, и M2, и скиллы. Диаг подтвердил: Basic M2 0.525/1.09=482мс = measured
	-- 485мс. Прошлый V123-демпфер (m→1 для M2) был ОШИБКОЙ — он и ломал M2 (pred 617 vs 485).
	-- [V132] Учитываем PingAnimSpeedMultiplier: игра проигрывает анимацию МЕДЛЕННЕЕ на пинге,
	-- поэтому реальный контакт = base / (aMult * pingMult). Без этого M2/M1 приходят раньше
	-- предсказания, особенно на высоком пинге, и парри оказывается поздним (LATE / HIT).
	local scaled = base / m
	local pingMult = getPingAnimMult(scaled)
	m = m * math.max(pingMult, 0.05)
	return base / m
end

function styleForward(style, kind)
	loadGameModules()
	if GameData.cfg then
		local ok, f = pcall(function() return GameData.cfg.GetStyleHitboxForwardOffset(style, kind) end)
		if ok and type(f) == "number" then return f end
	end
	-- [V109] SKILL/спец-удары (крит, «крутилка ногами» и т.п.) обычно тяжёлые и длиннорукие →
	-- фолбэк на M2Forward (дальний вылет), а не короткий M1Forward. Меньше риск недооценить диста��цию.
	return (kind == "M2" or kind == "SKILL") and Config.M2Forward or Config.M1Forward
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
	State.guardUp = false         -- guard снят на с��рвере
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

-- [V122] BOXING COUNTER — полный переписанный блок. Модель проста и агрессивна (ТЗ юзера):
-- «вместо парирования МОМЕНТАЛЬНО бить M2, если стиль Boxing, враг атаковал в радиусе 5.5 и
-- M2 не на кулдауне». Ни задержек, ни ожидания контакта, ни каденс/пинг-гейтов.

-- Атрибуты, при которых наш перс физически НЕ может запустить M2 (тогда counter невозможен).
local BOXING_BLOCK_ATTRS = {
	"CombatAttacking", "Stunned", "Ragdoll",
	"ParryAttackLockout", "BlockAttackLockout", "GrappleWinnerStun",
}

-- Готов ли НАШ перс сейчас пустить boxing-M2 (стиль + все гейты состояния + M2 не на кулдауне).
local function counterReady()
	if not Config.SkillAddon or not Config.BoxingCounter then return false end
	local c = localChar()
	if not c then return false end
	if (styleOf and styleOf(c) or ""):lower() ~= "boxing" then return false end
	-- анти-даблфайр: не спамим M2 быстрее BoxingCounterGap (реальный кулдаун держит игра через
	-- M2Cooldown; этот гэп только закрывает сетевое окно до появления атрибута). НЕ задержка.
	if (os.clock() - (State.lastCounter or 0)) < (Config.BoxingCounterGap or 0.30) then return false end
	for _, attr in ipairs(BOXING_BLOCK_ATTRS) do
		if c:GetAttribute(attr) then return false end
	end
	if c:GetAttribute("CantAnything") and not c:GetAttribute("CombatRecovery") then return false end
	if c:GetAttribute("Equip") == false then return false end
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return false end
	-- M2 на кулдауне → counter невозможен (FireServer был бы вхолостую, iframes не выдаются).
	if c:GetAttribute("M2Cooldown") == true or c:GetAttribute("M2CD") == true then return false end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local h = getHandler()
	if h and h.GetAnims then
		local ehit = false
		pcall(function() ehit = next(h.GetAnims(c, "EHit")) ~= nil end)
		if ehit then return false end
	end
	return true
end

-- Мгновенно пустить M2 по цели th: снап лицом (сервер строит хитбокс по нашему LookVector),
-- уронить guard (M2 не пустится с поднятым блоком), FireServer прямо в этот кадр.
local function fireBoxingCounter(th)
	local myHRP = localHRP()
	local aHRP  = th and th.attackerHRP
	if myHRP and aHRP and aHRP.Parent then
		local d = flatDirTo(myHRP.Position, aHRP.Position)
		if d then myHRP.CFrame = CFrame.lookAt(myHRP.Position, myHRP.Position + d) end
		setFaceGoal(aHRP, true, Config.BoxingFaceLockDur or 0.55)
	end
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)   -- force: guard обязан опуститься, иначе рейт-лимит подвесит M2
	end
	ServerRemote:FireServer({ Type = "Combat", Action = "M2", Func = "ServerCheck" })
	State.lastCounter  = os.clock()
	State.counterCount = (State.counterCount or 0) + 1
	State.flashUntil   = os.clock() + 0.25
	State.status       = "BOX-COUNTER"
end

-- Главная точка входа: если можем контрить — находим БЛИЖАЙШЕГО атакующего в радиусе и
-- МОМЕНТАЛЬНО бьём M2. Возвращает true, если counter выстрелил (scheduler пропускает блок).
local function tryBoxingCounter(now)
	if not counterReady() then return false end
	local myHRP = localHRP()
	if not myHRP then return false end
	local reach = Config.BoxingCounterReach or 5.5
	local myPos = myHRP.Position
	local best, bestDist
	for i = 1, #Threats do
		local th = Threats[i]
		local aHRP = th.attackerHRP
		-- «враг атаковал» = активная угроза (свинг задетекчен) и контакт ещё не прошёл давно.
		if aHRP and aHRP.Parent and not th.feinted and not th.dodged
		   and (th.contactAbs - now) > -0.15 then
			local dx, dz = myPos.X - aHRP.Position.X, myPos.Z - aHRP.Position.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= reach and (not bestDist or dist < bestDist) then
				best, bestDist = th, dist
			end
		end
	end
	if not best then return false end
	fireBoxingCounter(best)
	diagPush(("COUNTER t=%.2f  %s  %s  dist=%.1f  (instant M2)")
		:format(now, best.name or "?", best.kind or "?", bestDist))
	return true
end

-- ── GRAPPLE WIN ─────────────────────────────────────────────────────────────────────────────
-- [V131] ИСПРАВЛЕНО: раньше фича фаерила M2 на ЛЮБОЙ входящий тяжёлый в радиусе — то есть в
-- обычном бою, а не в борьбе. Настоящее состояние борьбы — атрибут Grappling==true на персонаже
-- (M2.lua:566/684, MovementServiceClient:1105, SmoothShiftLock:811). Теперь фича РАБОТАЕТ ТОЛЬКО
-- пока Grappling==true у НАС: в окне клэша (Grapple.Duration=2.29) сервер отдаёт победу тому, кто
-- в борьбе жмёт M2 непрерывно/последним (проигравшему летит GrappleWinnerStun). Поэтому мы просто
-- спамим M2 весь grapple — так гарантированно остаёмся «последним атакующим».
local function grappleM2Ready()
	if not Config.SkillAddon or not Config.SA_GrappleWin then return false end
	local c = localChar()
	if not c then return false end
	-- ГЛАВНЫЙ гейт: мы должны реально быть В БОРЬБЕ. Вне грэппла фича молчит.
	if c:GetAttribute("Grappling") ~= true then return false end
	-- анти-даблфайр: не спамим M2 быстрее BoxingCounterGap (реальный кулдаун держит игра).
	if (os.clock() - (State.lastCounter or 0)) < (Config.BoxingCounterGap or 0.30) then return false end
	for _, attr in ipairs(BOXING_BLOCK_ATTRS) do
		if c:GetAttribute(attr) then return false end
	end
	if c:GetAttribute("CantAnything") and not c:GetAttribute("CombatRecovery") then return false end
	if c:GetAttribute("Equip") == false then return false end
	if c:GetAttribute("Greenzone") == true or c:GetAttribute("RpCombatLocked") == true then return false end
	if c:GetAttribute("M2Cooldown") == true or c:GetAttribute("M2CD") == true then return false end
	if c:GetAttribute("GrappleWinnerStun") == true then return false end   -- уже проиграли клэш
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	return true
end

-- Найти оппонента по борьбе. Remote-state авторитетнее: CombatGrappleStart payload содержит
-- CharAName/CharBName. Поиск ближайшего Grappling-игрока — только fallback при пропущенном событии.
local function findGrappleFoe(myHRP)
	local gs = State.grapple
	if gs and gs.active and type(gs.foeName) == "string" then
		local fp = Players:FindFirstChild(gs.foeName)
		local fc = fp and fp.Character
		local fh = fc and fc:FindFirstChild("HumanoidRootPart")
		if fh then return fh end
		local fm = Workspace:FindFirstChild(gs.foeName)
		local mh = fm and fm:IsA("Model") and fm:FindFirstChild("HumanoidRootPart")
		if mh then return mh end
	end
	local myPos = myHRP.Position
	local best, bestDist
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= LocalPlayer then
			local oc = pl.Character
			local ohrp = oc and oc:FindFirstChild("HumanoidRootPart")
			if ohrp and oc:GetAttribute("Grappling") == true then
				local d = (ohrp.Position - myPos).Magnitude
				if not bestDist or d < bestDist then best, bestDist = ohrp, d end
			end
		end
	end
	return best
end

State.grappleStart = function(payload, dirty)
	if type(payload) ~= "table" then return end
	local a, b = payload.CharAName, payload.CharBName
	local me = LocalPlayer.Name
	if a ~= me and b ~= me then return end
	local gs = State.grapple
	gs.active = true
	gs.dirty = dirty == true
	gs.foeName = (a == me) and b or a
	gs.clashType = payload.ClashType
	gs.winnerName = payload.WinnerName
	gs.startedAt = os.clock()
	diagPush(("GRAPPLE-START t=%.2f type=%s foe=%s clash=%s winner=%s")
		:format(gs.startedAt, gs.dirty and "DIRTY" or "NORMAL", tostring(gs.foeName),
			tostring(gs.clashType), tostring(gs.winnerName)))
end

State.grappleEnd = function(payload)
	local gs = State.grapple
	if not gs.active then return end
	if type(payload) == "table" then
		local a, b = payload.CharAName, payload.CharBName
		if a and b and a ~= LocalPlayer.Name and b ~= LocalPlayer.Name then return end
		gs.winnerName = payload.WinnerName or gs.winnerName
	end
	diagPush(("GRAPPLE-END t=%.2f foe=%s winner=%s")
		:format(os.clock(), tostring(gs.foeName), tostring(gs.winnerName)))
	gs.active, gs.dirty, gs.foeName, gs.clashType, gs.winnerName, gs.startedAt = false, false, nil, nil, nil, 0
end

-- Пока мы в борьбе (Grappling==true), непрерывно жмём M2, чтобы выиграть клэш.
-- Переиспользуем fireBoxingCounter (снап лицом при наличии цели, сброс guard,
-- FireServer M2). Срабатывает ТОЛЬКО в грэппле, поэтому в обычном бою больше не мешает.
local function tryGrappleWin(now)
	-- Remote-state мог потерять End; атрибут — авторитетный fallback после короткого grace.
	local gs = State.grapple
	local gc = localChar()
	if gs.active and gc and gc:GetAttribute("Grappling") ~= true and now - gs.startedAt > 0.35 then
		State.grappleEnd(nil)
	end
	if not grappleM2Ready() then return false end
	local myHRP = localHRP()
	if not myHRP then return false end
	local foe = findGrappleFoe(myHRP)
	fireBoxingCounter({ attackerHRP = foe, name = "grapple-foe", kind = "GRAPPLE" })
	State.status = "GRAPPLE-WIN"
	diagPush(("GRAPPLE-WIN t=%.2f  (M2 spam in grapple)"):format(now))
	return true
end

-- [V89] ПРОИЗВОДНЫЙ список «только додж». В дампе НЕТ флага Unblockable/CanBlock: любой
-- M1/M2 в принципе блокируется/перфактится (сетевые исходы: M2Blocked / M2PerfectBlocked /
-- M2GuardBroken). Реальн�� сквозь атрибут Blocking проходят только грэбы/с��эмы — прежде всего
-- Wrestling M2 (гарантированный захват, см. M2GrabTargetForwardOffset в CombatConfig). Их
-- нельзя блокнуть, с��асает лишь додж (i-frames = абсолютная неуязвимость: VictimHitboxService
-- ._isSuppressed гасит урон при IFRAMES/Ragdoll/Downed/UltraInstinct). Список собираем по
-- стилю/��ипу через Config.MustDodgeStyles (расширяется ��ез правки движка) + живой сигнал по
-- атрибуту атакующего, е��ли игра е��о выставит в момент замаха.
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
	-- [V106] АВТО-ДЕТЕКТ грэб-M2 по CombatConfig (без новых top-level локалов — лимит 200/функция;
	-- кэш держим на GameData, детект инлайн). Командный грэб/слэм (Wrestling, Kure, …) проходит
	-- СКВОЗЬ блок и на попада��ии выруба��т парри (M2SlamParryWindowDisableDuration) → т��лько додж.
	-- Опознаём стиль по конфигу: любой M2Grab*/M2Slam*-атрибут ⇒ M2 этого стиля = грэб. Так новые
	-- грэб-стили ловятся без ручного пополнения MustDodgeStyles.
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

-- ============================ AutoPlay addon (V99) ============================
-- Автоатака через РОДНУЮ tryM1() игры (M1.lua). Фа��ты из ��ампа (CombatConfig.ClientPredict.M1):
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
-- поэ��ому НИ ОДНОГО нового top-level local (это переполняло регистры → CompileError).
State.ap = {
	m1         = nil,    -- кэш РОДНОГО модуля M1 игры (return-таблица v1 с .OnM1Activated)
	tryM1Fn    = nil,    -- сам локальный tryM1() (upvalue #1 в OnM1Activated) — даёт bool успеха
	comboIdx   = nil,    -- upvalue-индекс u19 (combo-счётчик) в tryM1 — для Fixed-режима и custom-fire
	m1Tried    = false,  -- уже пытались резолвить модуль (не с��амить резолв каждый кад��)
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
	nextM1At   = 0,      -- анти-спам ПОЛЛА (сам tryM1 гейтит настоящий рей�� по AttackDuration 0.45с)
	punishTgt  = nil,    -- модель врага, которого добиваем после ��арри
	punishUntil= 0,      -- докуда действует окно добивания (по времени стана)
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
-- tryM1 возвращает true, если свинг реально прошёл (у н��с есть точный сигнал успеха).
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
			-- (function), поэтому это надёжный якорь. О�� него все индексы — фиксированным смещением,
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

-- [V105] СВОЙ БЫСТРЫЙ M1 — ВСЕГДА используется (свой билдер ��место игрового tryM1). Игровой
-- tryM1 после каждого свинга зовёт scheduleM1SwingTimers → u21=false на AttackDuration(0.45с) →
-- следующий удар только через 0.45с. Мы повторяем ХВОСТ tryM1 (выбор combo, u25++/u27/u28,
-- анимация, CombatRemoteClient.Fire), НЕ трогаем scheduleM1SwingTimers, и СНИМАЕМ клиентские локи
-- (u21=true, u32/u33=0) → троттла нет. Единственный настоя��ий потолок — сам CombatRemoteClient.Fire
-- (M1.ServerCheck: min 80мс, sustained 4/с): он вернёт false, если рано, и тогда мы НЕ двигаем u25
-- → последовательность серверу цела (без «дыр»). combo: Fixed → ровно AP_FixedHit, иначе 1→4.
-- wantCombo (опц.) — принудительный номер удара для тест-свинга.
function State.ap.fireM1Custom(char, model, wantCombo, ignoreRate)
	local ap = State.ap
	if not (ap.fireOK and ap.tryM1Fn) then return false end
	local ok = false
	pcall(function()
		-- снять клиен��ские локи (мгновенный повторный/послепарийный свинг) — best-effort:
		-- индексы могли не зарезолвиться, тогда просто не трогаем (Fire всё равно решает по рейту).
		local now = os.clock()
		if ap.u21idx then debug.setupvalue(ap.tryM1Fn, ap.u21idx, true) end   -- AttackDuration-троттл
		if ap.u32idx and (debug.getupvalue(ap.tryM1Fn, ap.u32idx) or 0) > now then debug.setupvalue(ap.tryM1Fn, ap.u32idx, now - 0.01) end
		if ap.u33idx and (debug.getupvalue(ap.tryM1Fn, ap.u33idx) or 0) > now then debug.setupvalue(ap.tryM1Fn, ap.u33idx, now - 0.01) end
		-- выбр��ть номер удара комбо
		local combo
		if wantCombo then
			combo = math.clamp(math.floor(wantCombo), 1, 4)
		elseif Config.AP_ComboMode == "Fixed" then
			combo = math.clamp(math.floor(Config.AP_FixedHit or 1), 1, 4)
		else
			combo = ((debug.getupvalue(ap.tryM1Fn, ap.comboIdx) or 0) % 4) + 1
		end
		-- [V107] РЕЙТ-ГАРД: равномерный ~AP_MaxPerSec/с (по умолчанию 6 = server sustained low).
		-- ��аньше слали через ap.crc.Fire, а он режет 4/с ФР��НТ-ЛОАДОМ (4 подряд → тишина). Теперь
		-- шлём НАПРЯМУЮ в ServerRemote (минуя клиентский кап) со своим равномерным шагом → быстрее,
		-- анимация успевает, и весь стан-window заполнен. Тест-свинг (ignoreRate) шлёт всегда.
		if not ignoreRate then
			local rate = math.max(1, Config.AP_MaxPerSec or 6)
			local gap  = math.max(Config.AP_MinSendGap or 0.09, (1 / rate) * 0.97)
			if (now - (ap.m1SendLast or 0)) < gap then return end      -- ещё рано — не шлём
			if (now - (ap.m1WinStart or 0)) >= 1 then ap.m1WinStart, ap.m1WinCount = now, 0 end
			if (ap.m1WinCount or 0) >= rate then return end            -- окно 1с исчерпано
		end
		local anims = ap.getAnims()
		local v53   = anims and anims[combo] or nil
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
	if c:GetAttribute("Equip") ~= true then return false end   -- ��уки не одеты ��� бить нельзя
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
-- БЕЗ собственных лок/задержек — и��ровая tryM1 сама разрешит удар как только это ��опустимо
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

-- [V105] ТЕСТ-СВИН�� для UI-кнопки: шлёт один M1 с анимацией комбо, которую использовал бы скрипт
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
	-- окно стана: M2-парри = ParryStun.M2 (1с, надёжно); M1-парри короче (RecoveryLockout врага)
	local stun = (kind == "M2") and (Config.AP_M2Stun or 1.0) or (Config.AP_M1Stun or 0.5)
	State.ap.punishTgt   = model
	State.ap.punishUntil = os.clock() + stun
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
		return
	end
	if ap.flatDist(tgt) > ap.reach() then return end   -- вне досягаемости — не бьём воздух
	-- [V110] МГНОВЕННОЕ добивание в ТОМ ЖЕ кад��е. Сразу после парри мы ещё держим guard (Blocking),
	-- а fireM1 самогейтится на Blocking. Раньше step ронял guard и делал `return` → первый добив
	-- терял ЦЕЛЫЙ Heartbeat (~16мс) + воспринимался как «медленный старт». Но sendDeactivate снимает
	-- ЛОКАЛЬНЫЙ атрибут Blocking СИНХРОННО (c:SetAttribute("Blocking", nil)) → canAttack() проходит
	-- уже в этом кадре. Поэтому НЕ делаем return — сразу бьём. Deactivated и ServerCheck уходят на
	-- сервер по одному remote по порядку: сервер снимает guard, затем принимает M1. Угроз нет
	-- (#imminent==0) и цель застанена → ронять guard безопасно.
	if State.blocking then
		State.blocking, State.holdUntil = false, 0
		stopBlockAnim()
		pcall(sendDeactivate, true)
	end
	ap.fireM1(tgt, "punish")
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

		-- [V66] изме��яем РЕАЛЬНУЮ скорость прогресса анимации (units анимации в
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
		-- чистым обратным отсчётом contact0-elapsed, без учёта РЕАЛЬНОГО прогресс�� анимации → при
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

		-- [V121] FEINT-детект ТОЛЬКО для M1. У M1 хитбокс мгновенный (привязан к анимации) → трек,
		-- закончившийся до FeintFrac, = реальная отмена свинга. У M2/SKILL хитбокс ЗАДЕРЖАННЫЙ
		-- (M2HitboxDelay): видимая анимация шт��тно конч��ется за ~30% до нашего hitTL (в логе maxTP=69%),
		-- удар прилетает ПОЗЖЕ конца трека. Прежний код это принимал за финт → th.feinted=true → M2
		-- ВООБЩЕ не парировался (корень жалобы). Для M2/SKILL финт не детектим: полагаемся на
		-- live-timer + wall-clock контакт + геометрию willHitMe. Ложный съеденный M2-финт = 1 ранний
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
	-- track.Speed для чужих игро��ов ��еплицируется как 1.0, по��тому берём из роста.
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

	-- [V113] Трекинг КАДЕНСА свингов по атакующему (для boxing combo-guard). Запоминаем интервал
	-- между двумя последними свингами этого врага: короткий интервал = активная комбо-цепочка.
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

local function dirIsClear(origin, dir)
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
	if part and (not part.CanCollide or part:IsDescendantOf(char or part)) then return true end
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

local function performDodge(now, reason, preferBack, force, bypassAutoOff)
	-- [V120] ЕДИНЫЙ мастер-гейт: sendDodge вызывается ТОЛЬКО отсюда, все триггеры идут через
	-- performDodge → выключив AutoDodge, юзер убирает ЛЮБОЙ ОПЦИОНАЛЬНЫЙ додж (одно место истины).
	-- [V128] ИСКЛЮЧЕНИЕ — must-dodge (bypassAutoOff=true): грэбы/анблокаблы НЕЛЬЗЯ блокнуть, их
	-- гасит только додж (i-frames). Это обязательная защита, а не удобство, поэтому она обязана
	-- срабатывать даже при выключенном Auto Dodge. Свой тумблер у неё есть (Config.MustDodge,
	-- проверяется в isMustDodge), так что полностью отключить её всё равно можно.
	if Config.AutoDodge == false and not bypassAutoOff then
		if State.lastDodgeRefuse ~= "AutoDodge-off" then
			State.lastDodgeRefuse = "AutoDodge-off"
			diagPush(("DODGE-SKIP t=%.2f  %s  (AutoDodge disabled)"):format(now, reason))
		end
		return false
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

-- [LURAPH] The per-Heartbeat threat scheduler — the reactive parry path. Kept
-- native (not virtualized) so timing math stays fast; Luraph still obfuscates
-- its constants/strings. Not the secret, so nothing is lost by not virtualizing.
local schedulerStep = LPH_NO_VIRTUALIZE(function(now)
	local serverNow = Workspace:GetServerTimeNow()
	local up        = uplink()
	local wantBlock = nil
	local faceTgt   = nil
	local imminent  = V93.imminentBuf   -- [V123] персистентный буфер (без аллокации таблицы/кадр)
	table.clear(imminent)

	-- Grapple — отдельное подтверждённое состояние боя. Пока наш персонаж реально Grappling,
	-- старые animation-threats не должны запускать обычные block/dodge/counter ветки.
	State.grappleChar = localChar()
	if State.grapple.active and State.grappleChar
	   and State.grappleChar:GetAttribute("Grappling") ~= true
	   and now - State.grapple.startedAt > 0.35 then
		State.grappleEnd(nil)
	end
	if State.grappleChar and State.grappleChar:GetAttribute("Grappling") == true then
		tryGrappleWin(now)
		return
	end

		for i = #Threats, 1, -1 do
			local th = Threats[i]
			local trackGone = th.track and th.track.Parent == nil
			refreshContact(th)
			-- [V74] Use actual server hitbox to correct timing for delayed hitboxes (Boxing M2, etc.)
			syncContactWithHitbox(th, now)
			local dt = th.contactAbs - now
			-- [V90 FIX] Угрозы БЕЗ трека (хитбокс-детект / сетевые свинги) не могут истечь по
			-- dt: refreshContact клампит contactAbs в now+max(remaining,0), поэтому dt застревает
			-- на 0 и НИКОГДА не ухо��ит ниже -0.35, а trackGone для них тоже false. Без трека ��гроза
			-- ��тановилас�� бессмертной → wantBlock де��жался вечно → guard не отпускался (баг «блок
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
			-- [V121] КОРЕНЬ «скрипт ВООБЩЕ не парирует M2»: у M2 анимационный трек уничтожается
			-- (Parent=nil) ~0.5с в замах, а реальный удар (delayed hitbox, M2HitboxDelay) прилетает
			-- на 0.78-0.84с. Прежнее `trackGone and elapsed>0.5` убивало угрозу РОВНО на 0.5с — за
			-- 30-110мс ДО того как откроется press-окно (pressAt) → M2 никогда не нажимался (в логе
			-- обе M2 удалены точно через 0.5с, dt ещё +250..+300мс). Track-gone угрозы и так тикают
			-- по wall-clock (remaining=contact0-elapsed) → catch-all `dt<-0.35` гарантирует удаление.
			-- Поэтому 0.5с-TTL применяем ТОЛЬКО когда контакт уже практически наступил (dt<lead) —
			-- отменённый/финтовый свинг с прошедшим контактом чистится, а delayed-M2 доживает до press.
			elseif dt < -0.35 or noTrackExpired
				or (trackGone and (now - th.detectClock) > 0.5 and dt < Config.PerfectLead) then
			-- [V66] POST-MORTEM: угроза уходит. Если на неё ни разу не нажали и не
			-- задоджили — это независимый пропуск. Логируем ТОЧН��Ю прич��ну, чтобы
			-- закрыть "скрипт проёбывает атаку" по фактам, а не догадкам.
			-- [V69] при ненаправленном блоке угроза, ��оше��шая в окно, покрыта поднятым
			-- guard'ом (один блок = защита от всех). ��то НЕ промах — раньше логировалось
			-- лож��ым "пере��ит EDF". Считаем отдельно, чтобы не путать с реа��ьными потерями.
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
					-- [V116] ЧИСТО МАТЕМАТИЧЕСКИЙ предикт: press строго от сырого contactAbs (таймлайн
					-- анимации + живой TimePosition). Никакой выученной коррекции — она отравляла между
					-- врагами. Компенсация задержки — только физическая (lead + uplink + velLead).
					local pressAt = th.contactAbs - lead - up - th.velLead
					local holdEnd = th.contactAbs + hold
				-- [V66] диаг-трекинг: минимальный зазор до момента нажатия и факт
				-- входа в окн�� — для точного post-mortem причины пропуска.
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
				end
				-- [V95] окно кандидата на поворот РАСШИРЕНО на RTT (up): хард-снап нужен за
				-- (BlockFaceHardDt + up) до контакта, иначе на высоком пинге кандидат появлялся
				-- бы слишком поздно и мы прессили бы блок ещё ��е довернувшись → сервер от��лонял.
				if dt <= (Config.FaceLeadWindow + up) and dt >= -Config.HoldAfter then
					-- [V65] лицом к т��му, кто бьёт СЛЕДУЮЩИМ среди ещё не прилетевших
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
				if dt <= Config.DodgeHorizon and dt >= -Config.HoldAfter then
					imminent[#imminent+1] = th
				end
			end
		end
	end

	table.sort(imminent, function(a, b) return a.contactAbs < b.contactAbs end)

	-- Multi-attacker clustering is based on distinct attackers and absolute contacts.
	-- A cluster is handled as one defensive transaction, never as competing EDF presses.
	local cluster = V93.clusterBuf   -- [V123] персистентный буфер (без аллокации таблицы/кадр)
	table.clear(cluster)
	local seenAttackers = V93.seenAttackers
	for k in pairs(seenAttackers) do seenAttackers[k] = nil end
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
		local blockCd = Config.BlockCooldown or 0.5
		local seqSpread = Config.SequentialSpread or 0.78
		-- [V73] SEQUENTIAL: separate presses if spread is enough and second press clears cooldown
		if clusterN == 2 and clusterSpread >= seqSpread and not clusterHeavy then
			local a, b = cluster[1], cluster[2]
			local spreadOk = (b.contactAbs - a.contactAbs) >= blockCd + Config.PerfectLead + Config.MinActGap + 0.05
			if not isMustDodge(a) and not isMustDodge(b) and spreadOk then
				clusterStrategy = "SEQUENTIAL"
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

		-- [V96] Pre-emptive кластер-додж под первый контакт, пока все контакты в одном iframe-окне.
		-- ТЕПЕРЬ только если parry невозможен (not canBlockNow): по требованию юзера при доступном
		-- блоке кластер держим guard'ом + мультип��екс-фейсингом (V95), а НЕ жжём додж. Раньше коммент
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
	-- [V128] Работает даже при выключенном Auto Dodge: анблокабл-грэбы блоком не остановить,
	-- поэтому передаём bypassAutoOff=true (последний аргумен�� performDodge). Свой тумблер
	-- (Config.MustDodge) остаётся — им и отключается эта защита при желании.
	local mustDodgeThreat = nil
	for _, candidate in ipairs(imminent) do
		if isMustDodge(candidate) then mustDodgeThreat = candidate; break end
	end
	if mustDodgeThreat and dodgeReady() and canDodgeNow() then
		local mustDt = mustDodgeThreat.contactAbs - now
		local mLo = Config.DodgeConfirm - 0.03
		local mHi = Config.DodgeConfirm + Config.IFrameDur - 0.04
		if mustDt >= mLo and mustDt <= mHi then
			if performDodge(now, "must-dodge(unblockable→back)", true, false, true) then
				mustDodgeThreat.coveredByDodge = true
				return
			end
		end
	end

	-- [V91] BLATANT force-dodge — ОТД��ЛЬНА�� ветка, потому что блок ниже требует
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
		-- закрывалось за 1м�� до ��дара. Теперь escape-д��джи привязаны к контакту.
		local coverLo = Config.DodgeConfirm - 0.03
		local coverHi = Config.DodgeConfirm + Config.IFrameDur - 0.04
		local function dodgeCovers(dt) return dt >= coverLo and dt <= coverHi end
		local coverable = dodgeCovers(soonestDt)

		-- GRANT-эскейп: бесплатный эвейд от игры при численном перевесе. Грант
		-- держится, пока мы в меньшинст����, поэтому МОЖНО подождать и фитить строго
		-- когда удар входит в iframe-окно (а не палить сра��у �� тратить впустую).
		if Config.OutnumberEscape and evasiveGranted() and coverable then
			-- [V117] НЕ жжём грант на ОДИНОЧНЫЙ блокируемый удар — надёжнее спарировать. Считаем,
			-- сколько imminent-у��роз попадают в iframe-окно: если ровно одна и мы МОЖЕМ блокнуть —
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
			-- `soonestDt <= coverHi` БЕЗ нижней границы → додж жёгся когда удар был в упор (dt<coverLo),
			-- iframes не успевали подняться → в логе `combo-escape ... fire→contact=0ms TOO EARLY`.
				if Config.ComboEscapeDodge and Config.DodgeOnParryCooldown ~= false
				   and not canBlockNow() and coverable then
					if performDodge(now, "combo-escape") then return end
				end
		-- exposed-эскейп: ��ы залочены в СВОЕЙ АТАКЕ (не можем блокнуть мид-сви��г) и удар входит в окно.
			-- [V117] гейт по attackBusyUntil (НЕ selfBusyUntil): дэш тоже ставил selfBusyUntil → один додж
			-- делал нас «busy» → следующий удар → ещё один exposed-додж → самоподдерживающийся додж-луп
			-- (в логе dodges=101, почти все exposed). Дэш сам даёт i-frames, передоджить его незачем.
			--
			-- [V92-FIX «фантомный exposed-додж»] attackBusyUntil>now ⇒ мы в СВОЁМ свинге ⇒ CombatAttacking=true.
			-- Игровой Evasive (см. дамп CombatSystemClient/Combat/Base/Evasive.lua, гейты u1.Evasive) ОТКЛОНЯЕТ
			-- Evasive при CombatAttacking. canDodgeNow() этого НЕ ловит (не проверяет CombatAttacking), поэтому
			-- НЕфорсированный додж здесь ВСЕГДА глотается сервером: анимация есть, i-frames нет → удар съедается
			-- (лог: exposed-escape → hit INSIDE i-frame window → LATE/NOT-BLOCKED). Пробить лок атаки можно
			-- Т��ЛЬКО форс-дэш-инпутом — а это по замыслу режим Blatant Dodge. Поэтому exposed-escape теперь:
			--   1) разрешён ТОЛЬКО при включённом SA_BlatantDodge (в легит-режиме больше не палит впустую);
			--   2) исполняется через force=true (как ветка blatant-override), иначе и в блатанте был бы фантомным.
			local blatantOn = Config.SkillAddon and Config.SA_BlatantDodge
			local busyRef = (Config.ExposedEscapeAttackOnly ~= false)
				and (State.attackBusyUntil or 0) or (State.selfBusyUntil or 0)
			if blatantOn and Config.ExposedEscapeDodge and busyRef > now
			   and soonestDt <= Config.ExposedDodgeWindow and coverable then
				if performDodge(now, "exposed-escape(blatant)", false, true) then return end
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
				-- guardbreak-save: ста��ина на нуле → guard всё равно проломят, ��одж оправдан даже
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
	-- перекид��ваемся на следующего (тайм-мультиплекс поворота по времени контакта). wantBlock —
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
		-- HARD-снап должен успеть ДО разрешения удара: victim-репорт читает наш facing у контакта,
		-- а пакет летит к серверу ~пол-RTT. Значит жёстко доворачиваемся заранее — за (окно + RTT)
		-- до контакта. В мультибое (2+) — всегда hard, чтобы мг��овенно перекидываться ме��ду целями
		-- и не терять кадры на лерп. Иначе (одиночная, далеко) — плавный трекинг.
		local hardWin = (Config.BlockFaceHardDt or 0.30) + up
		local hard = (dtc <= hardWin) or (Config.MultiFaceHard and clusterN >= (Config.MultiThreatMinN or 2))
		-- держим цель до контакта + грейс (перекрывает ��ам момент оверлапа и пару ��адров после)
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
		-- [V92] ЛАТЧ УДЕРЖАНИЯ КЛАСТЕРА. Баг «2-я атака ��роходит»: как только 1-й атакующий
		-- отрабатывал, multiThreat ��адал до false (остался 1 враг) → guard отпускался по
		-- КОРОТКОМУ одиночному holdUntil, ровно за ~20мс до уд����ра выжившего (diag t=73.07
		-- PERFECT → t=73.35 LATE NO-PRESS). Теперь при обнаружении кластера ЗАПОМИНАЕМ самый
		-- поздний контакт + грейс и держи�� guard до него, сколько бы угроз ни осталось потом.
		if farContact then
			local latch = farContact + Config.HoldAfter + (Config.HoldLateGrace or 0) + 0.05
			State.multiHoldUntil = math.max(State.multiHoldUntil or 0, latch)
		end
	end

	-- [V110] Interrupt Heavies УДАЛЁН (юзер: не срабатывал на тяжёлые вовсе и ломал парри —
	-- скрипт ждал «перехвата», которого не было, вместо чес��ного блока/доджа). Теперь тяжёлые
	-- обрабатываются ТОЛЬКО обычным путём: must-dodge (грэбы) → block/perfect-parry. Надёжнее.

	-- [V122] BOXING COUNTER (instant). Вместо парирования МОМЕНТАЛЬНО бьём M2 по ближайшему
	-- атакующему в радиусе, если наш стиль Boxing и M2 не на кулдауне. Стоит ПОСЛЕ must-dodge
	-- (грэбы всё равно доджим) и обычных додж��й, но ДО блока — counter ЗАМЕНЯЕТ парри. НЕ зависит
	-- от wantBlock/willHitMe (тот баговал на delayed-hitbox M2) — скан идёт по сырым Threats, так
	-- что counter срабатывает даже когда предиктор-геометрия отка��ала. Выстрелил → скип блока.
	-- Grapple обрабатывается отдельным ранним state-path в начале schedulerStep.
	if tryBoxingCounter(now) then return end

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
		-- этой игре НАПРАВЛЕННЫЙ: сервер отклоняет парри, если жертва смот��ит спиной к атакующему
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
			-- «времени нет» = до контакта меньше, чем нужно на нажатие+RTT (тогда прессим как есть)
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
		-- это выживший из кластера, и его удар ещё летит. Так вторая волн�� бо��ьше не проходит.
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
	-- `not State.blocking`: step сам уронит guard первым кадром (враг застанен, угроз нет →
	-- безопасно), а fireM1 самоге��тится на Blocking. Так добивание стартует ср��зу после парри,
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
-- как "M2 PerfectBlocked"). Поэтому M2-исход должен уметь матчиться на SKILL-свинг.
local function outcomeTypeMatches(recType, kind)
	if recType == kind then return true end
	if kind == "M2" and recType == "SKILL" then return true end
	return false
end

local function onOutcome(attacker, result, kind, eventClock)
	-- [V125] СНАЧАЛА находим свинг, к которому относится этот исход, и ТОЛЬКО ПОТОМ трогаем
	-- state. Иначе фантомный доп-удар (2-й страйк мультихита / дубликат сервера) прогонял бы
	-- логику сброса guard (LATE → blocking=false) и ронял защиту посреди комбо → следующий
	-- реальный свинг проходил как HIT. Плюс дубликат раздувал tally/resAvg.
	local q = Pending[attacker]
	local rec, looseRec, followUp
	if q then
		for i = #q, 1, -1 do
			local r = q[i]
			if (eventClock - r.clock) <= Config.MatchWindow and outcomeTypeMatches(r.type, kind) then
				if not r.matched then
					if r.type == kind then rec = r; break          -- точный тип — берём сразу
					elseif not looseRec then looseRec = r end        -- SKILL↔M2 — запасной кандидат
				elseif not followUp and (eventClock - r.clock) <= Config.MultiHitWindow then
					followUp = r   -- уже засчитанный свинг → это ПОЗДНИЙ страйк той же атаки
				end
			end
		end
		if not rec then rec = looseRec end
	end

	-- Доп-удар мультихита (Boxing M2MultiHitCount=2 шлёт 2-е событие) или дубликат сервера:
	-- свинг уже оценён. НЕ пере-считываем tally и НЕ роняем guard — сброс тут открыл бы нас
	-- под следующий реальный свинг. Guard держится штатным holdUntil.
	if not rec and followUp then
		diagPush(("OUT    t=%.2f  %s  %s  %s  (multi-hit follow-up +%.0fms, guard kept)")
			:format(eventClock, attacker, kind, result, (eventClock - followUp.clock)*1000))
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

	-- rec/followUp уже вычислены в начале функции (до мутаций state).
	if not rec then
		diagPush(("OUT    t=%.2f  %s  %s  %s  (no fresh swing)"):format(eventClock, attacker, kind, result))
		return
	end
	rec.matched = true

	local measured = eventClock - rec.clock
	local predErr  = (measured - rec.contact) * 1000
	State.lastErrMs = predErr

	-- [V116] ЧИСТО ДИАГНОСТИЧЕСКИЙ per-(kind,style) средний predErr — в предикт НЕ подаётся
	-- (адаптивная калибрация удалена: отравляла между врагами — обучалась на одном, ломала второго).
	-- Показываем скользящее среднее ошибки модели только для наблюдения точности в логе.
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
	-- rearm работает и сервер перевз��одит перфект от свежего Activated.
	do
		State.comboStat = State.comboStat or { opener = {}, tail = {} }
		local bucket = ((rec.combo or 0) >= 3) and State.comboStat.tail or State.comboStat.opener
		bucket[result] = (bucket[result] or 0) + 1
	end

	diagPush(("OUT    t=%.2f  %s  %s(c%d)  %-10s  meas=%.0fms pred=%.0fms predErr=%+.0fms resAvg=%+.0fms(n=%d) | blockGap=%s pressDt=%s %s%s | face=%s%s spd=%.2f ping=%.0f")
		:format(eventClock, attacker, kind, rec.combo or 0, result, measured*1000, rec.contact*1000,
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

-- Точный grapple lifecycle. Этот RemoteEvent передаёт подтверждённые дампом имена обоих
-- участников, тип клэша и победителя; атрибут Grappling остаётся аварийным fallback.
task.spawn(function()
	local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
	local Network = Shared and Shared:WaitForChild("Network", 30)
	local remote = Network and Network:WaitForChild("CombatClientRemoteEvent", 30)
	if not remote or not remote:IsA("RemoteEvent") then
		dbg("grapple-state: CombatClientRemoteEvent not found; attribute fallback only")
		return
	end
	remote.OnClientEvent:Connect(function(eventName, payload)
		if eventName == "CombatGrappleStart" then
			State.grappleStart(payload, false)
		elseif eventName == "CombatGrappleStartDirty" then
			State.grappleStart(payload, true)
		elseif eventName == "CombatGrappleEnd" then
			State.grappleEnd(payload)
		end
	end)
	dbg("grapple-state active — listening CombatClientRemoteEvent")
end)

-- [V90.4] Серверный hitbox-reactor удалён: он срабатывал только по уже-приземлившемуся удару,
-- из-за чего мог держать guard и мешать. Парри теперь
-- полностью предиктивный (willHitMe по анимации), как и раньше.

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
	end
	return _decoyTrack
end

-- [V75] общий стейт self-verify (объявлен здесь, т.к. используется и тест-режимом ниже)
local SelfVerify = { conn = nil, lastLog = {}, decoyId = nil }

-- [V76] ТЕСТ-РЕЖИМ "наоборот": пока ты стоишь в idle, ПОСТОЯННО проигрываем АТАКУ как
-- decoy (низкий локальный ��ес, тебе почти незаметно). Смысл: на обсер��ере (твоя мобила)
-- должно НЕПРЕРЫВНО показывать ATTACK, хотя ты ничего не жмёшь. Если показывает —
-- значит decoy реально ��ходит в репликацию и хук подмены ра��очий. Тумблер по клавише.
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
		-- ма��симальный приорите��, чтобы перебивать walk/run (Movement) — берём Action4 если есть
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
		-- держим её постоянно доминирую��ей и заставляем AnimationPlayed по ней срабатывать
		-- снова (иначе обсерв��р показал бы последнюю walk-анимацию).
		-- [V76.2] БЕЗ рывка TimePosition=0 (он и вызывал дёрганье у тебя и в репликации).
		-- Держим трек доминирующим только пока движок ��ам не перебил его walk'ом. Важно:
		-- полностью уд����жать чужую картину клиентски НЕЛЬЗЯ — анимация реплицируется
		-- встроенным Animator'��м Roblox (в дампе НЕТ remote при :Play), а не нашим remote-хуком.
		-- [module FIX] Никогда не обнуляем Movement/Core/Idle/Action треки. Старый V81
		-- делал AdjustWeight(0.01) каждый Heartbeat, поэтому лог закономерно пок��зывал
		-- Movement/Core weight=0 и locomotion исчезала. Decoy продолжает реплицироваться
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
		DesyncTest.conn = RunService.Heartbeat:Connect(function()
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
-- (Looped=true), поэтому его НЕ НУЖНО перезапускать чер��з Stop/Play — он крути��ся сам. Именно
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
				tr:AdjustWeight(wgt, 0.1)                  -- мягко вер��уть вес, без рестарта
			end
		end)
	end)
	aclog("[desync] idlemask on")
end

-- PRERUN: короткая фейк-АТАКА (decoy-анимация), которую мы реплицируем РАНЬШЕ реальной —
-- вра��еский autoparry цепляе��ся за неё и пар��рует не тот удар, реальный проходит. Реальный
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

-- ����═════════════════ INVISIBLE + GHOST ═══════════════════
-- Ед��нственный top-level локал IV (как DZ) — ��тобы не упереться в лимит регистров.
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
--   packet:Drop()          -- отбросить (заблоки��овать) пакет  (НЕ return false!)
--   raknet.add_send_hook(fn) / raknet.remove_send_hook(fn)   -- снятие по ССЫЛКЕ на fn!
--   raknet.add_recv_hook(fn) / raknet.remove_recv_hook(fn)
-- Старый код: (1) ��итал packet.id / packet.size �� таких полей нет; (2) хранил "hookId"
-- из add_send_hook и зва�� remove_send_hook(hookId) — передавал не-функцию в C++ →
-- вылет. Теперь хук — ИМЕНОВАННАЯ фун��ция, снимается по ссылке. Скан read-only:
-- не трогает па������ты (ни Drop, ни SetData), только считает PacketId. Максимально
-- безопасно и мин��мально по работе на пакет — как в андетект-примере.
-- [V79] КОРЕНЬ КРАША НАЙДЕН: send-хук исполняется на СЕТЕВОМ потоке игры, а НЕ на потоке
-- Luau VM. Luau VM однопоточный �� любая МУТАЦИЯ Lua-таблицы с чужого потока (создание
-- нов���го ключа → rehash → реаллокация кучи) мгновенно рушит heap → краш. Мой скан дел��л
-- RaknetScan.near[pid] = ... с НОВЫМ ключом на каждый ��овый pid → rehash на сетевом потоке
-- → вылет при первом же пакете. Рабочий андетект-пример НИКОГДА не трога��т Lua-таблицы в
-- хуке — только C-операции над пакетом. Поэтому он и ��е крашит.
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

-- ИМЕНОВАННАЯ функция (с��ятие по ссылке). НИКАКОЙ аллокации/мутации структуры Lua-таблиц.
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
		aclog("[DESYNC-SCAN] 0 пакетов поймано — либо raknet-хук не видит трафик в ��той сбо��ке, л��бо не св��нгал во время сессии.")
		desyncPush("[SCAN] 0 packets captured (hook saw no traffic, or no swing during session)")
		return
	end
	local lines = {}
	for i = 1, math.min(10, #cand) do
		local c = cand[i]
		lines[#lines + 1] = ("PacketId=%d (0x%X) near=%d far=%d ratio=%.2f")
			:format(c.id, c.id, c.near, c.far, c.near / (c.far + 1))
	end
	aclog("[DESYNC-SCAN] candidates (near=�� окне атаки, far=фон; высокий ratio = вероятн��й анимационный/боевой пакет):\n  " ..
		(table.concat(lines, "\n  ")))
	desyncPush("[SCAN] raknet candidates (near=in attack window, far=background, high ratio=likely anim/combat packet):")
	for _, l in ipairs(lines) do desyncPush("[SCAN]   " .. l) end
end

-- [V80] RAKNET-ХУК ЖЁСТКО ОТКЛЮЧЁН. Причина (подтверждена анализом дампов игры):
--   • В клиентских дампах НЕТ ни одного Lua-анти-чита, сканирующего хуки — значит краш
--     вызывает НЕ игрово�� скрипт, который можно "выпилить".
--   • Краш происходит В МОМЕ��Т raknet.add_send_hook (мгновенно, до первого пакета) →
--     это native-защита клиента Roblox (Hyperion/Byfron), а не Lua. Её нельзя убрать
--     правкой игровых скриптов. Поэтому и "популяр��ый desync-скрипт" тоже крашил ��а F.
--   • Сеть игры = Blink: бой/движение шлётся через BLINK_RELIABLE_REMOTE:FireServer(buffer,
--     instances) раз в Heartbeat — это ОБ��Ч��ЫЙ RemoteEvent, а НЕ raknet. Значит desync
--     достижим без raknet: через hookmetamethod(__namecall) на FireServer (UNC-стандарт,
--     эта игра ��го не де��ектит, и он НЕ крашит). Это отдел��ная фича — включим по запросу.
_ = raknetScanSendHook  -- функция сохран��на в файле, но НЕ вызывается (ссылка, чтобы не было "unused")
_ = reportRaknetScan
local function runRaknetScanSession()
	aclog("[DESYNC-SCAN] ОТКЛЮЧЕНО: raknet-хук крашит native-защиту клиента (Hyperion), это не Lua-AC и не уби��ается правкой игры. Desync-путь чер��з Blink RemoteEvent (__namecall) — по запросу.")
	desyncPush("[SCAN] raknet path disabled (native anti-tamper crash). Use Blink __namecall path instead.")
end
if type(getgenv) == "function" then getgenv().AP_RAKNET_SCAN = runRaknetScanSession end

-- [V74] DESYNC SELF-VERIFY. К��к понять, работает ли desync ВООБЩЕ, без второго
-- аккаунта: Animator.AnimationPlayed срабатывает на КАЖДЫЙ т��ек, который стартует на
-- нашем аниматоре — а это ровно то, что Roblox реплицируе�� другим клиентам. Значит
-- если при свинге сюда прилетают И реальная атака, И decoy-idle — оба уходят в сеть,
-- и чужо�� AnimationPlayed увидит оба трека. Э���� объективное доказательство, что
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
-- ��огда ВТОРОЙ клиент будет логировать каждый трек, который РЕАЛЬ��О реплицировался ему
-- от твоего главного. Свингни ��а главном — �� в дебаге второго аккаунта увидишь, что
-- ему при��ло: реальная атака, decoy-idle, или (если raknet-rewrite заработает) только idle.
-- Это и есть объективная проверка desync с ��очк�� зрения противника.
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

-- [V75] сохранение desync-дебага в отдельный файл, чтобы сла��ь мне.
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

	-- [V74] если идёт скан-��ессия — метим следующие ~220мс ����ак "окно атаки" (near).
	if RaknetScan.active then
		RaknetScan.window = now + (Config.DesyncRaknetWindowMs or 220) / 1000
	end

	-- [V88] сюда доходит ТОЛЬКО delay: idlemask держится своим циклом, prerun — на FireServer.
	if (Config.DesyncMode or "delay") ~= "delay" then return end
	-- [V88] ФИКС "delay л��мал [": [ и idlemask крутят СВОИ decoy-треки, у к��торых тоже
	-- срабатывает AnimationPlayed. Раньше delay-хук хватал их и делал Stop/replay ��� decoy
	-- дёргался. Пропускаем наши собственные decoy-треки — трогаем только реальные атаки.
	if track == _testTrack or track == _decoyTrack then return end

	local window = (Config.DesyncDelayMs or 0) / 1000 + 0.05
	_desyncBusyUntil[track] = now + window

	local origSpeed = 1
	pcall(function() local s = track.Speed; if type(s) == "number" and s > 0.05 then origSpeed = s end end)
	State.desyncFires = (State.desyncFires or 0) + 1

	-- DELAY: анимацию замаха скрываем сразу и переигры����аем через mag мс (визуал стартует
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
		-- иначе ��н снова отложится (бесконечный цикл) или потеряется.
		if State.desyncPassthrough then return oldNamecall(self, ...) end

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
				-- FIREDELAY/PRERUN: задер��иваем САМ боевой паке�� (ServerCheck), анимацию не
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
	-- вручную по команде getgenv().AP_RAKNET_SCAN() когда стоишь в б��ю.
end)

-- [V90] firedelay/prerun теперь обрабатываю��ся ЕДИНСТ��ЕННЫМ владельцем — __namecall-хуком
-- на Remotes.Server:FireServer (выше). Отдельный хук на CombatRemoteClient.Fire УДАЛЁН: он
-- (а) патчи�� таблицу по пути ReplicatedStorage.Shared.Network, к��торая может ��ы��ь декоем, пока
-- реальный модуль лежит в Hidden, и (б) при работающем namecall-хуке давал ДВОЙНУЮ задержку
-- (модуль держал → origFire → Server:FireServer → namecall д��ржал снова). RemoteEvent
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

	-- ФИКС ЗАСТРЕВАНИЯ БЛОКА: ед��ная реконсиляция guard. Несколько путей (dodge, boxing-
	-- counter, onOutcome LATE/GUARDBREAK) сбрасывают State.blocking напрямую, НЕ отправляя
	-- Deactivated → сервер продолжал держать guard до ручного нажатия. Тут гарантируем:
	-- если серверу отправлен Activated (guardUp), но намерения блокировать больше нет —
	-- принудительно снимаем guard. Идемпотентно и безопасно (force обходит рей��-гейт).
	if State.guardUp and not State.blocking then
		pcall(sendDeactivate, true)
	end

	-- [PERF] Pending-очередь — это housekeeping (сборка протухших записей >3с), НЕ
	-- реактивный путь. Гонять полный обход pairs(Pending) каждый Heartbeat (до 240/с)
	-- впустую при пустой/мелкой очереди — лишний GC-обход на слабых машинах. Чистим
	-- раз в ~15 кадров; TTL=3с это с запасом переживает, тайминг парирования не зависит
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
		"===== AUTOPARRY V74 DIAG =====",
		("player=%s  ping=%.0fms  uplink=%.0fms  mode=%s  autoface=%s"):format(LocalPlayer.Name, getPingRaw()*1000, uplink()*1000, Config.Mode, tostring(Config.AutoFace)),
		("model: PURE anim timeline + live TimePosition (NO calibration) | ping=robust median; lead=%.0fms hold=%.0fms window=[%.0f,%.0f]ms")
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
-- 40+18 давало ~140 WTV/кадр отрисовки; 24+12 = ~90 (−35%) при визуально идентичном кольце/конусе
-- (24 сег на круг = 15°/сегмент — глазу гладко). Это всегда-активная работа → режем в корне.
local RING_SEG  = 24
local CONE_SEG  = 12
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

function vizHideAll() LinePool:hideAll(); TriPool:hideAll() end

-- [module] AnimDbg (экранный Drawing-текст "ANIM ... | desync ...") УДАЛЁН полностью по запросу.

local Viz = { t = 0 }

local NEAR = 0.6

Viz.rotY = function(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

Viz.proj = function(cam, world)
	local sp = cam:WorldToViewportPoint(world)
	return Vector2.new(sp.X, sp.Y), sp.Z
end

Viz.drawWorldSeg = function(cam, a, b, color, thick)
	local a2d, az = Viz.proj(cam, a)
	local b2d, bz = Viz.proj(cam, b)
	if az <= NEAR and bz <= NEAR then return end
	if az <= NEAR or bz <= NEAR then
		local t = (NEAR - az) / (bz - az)
		local mid = a:Lerp(b, t)
		local m2d = Viz.proj(cam, mid)
		if az <= NEAR then a2d = m2d else b2d = m2d end
	end
	local ln = LinePool:get(); if not ln then return end
	ln.From, ln.To = a2d, b2d
	ln.Color, ln.Thickness, ln.Transparency, ln.Visible = color, thick, 1, true
end

Viz.pickTarget = function()
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

-- [V111] PERF: чтение bbox через персистентную fn (без closure/кадр) + 1-кадровый кэш. drawFlatRing
-- и footYOf оба тянут bbox цели каждый кадр — раньше каждый делал pcall(function()...GetBoundingBox
-- ()...end) (замыка��ие + отдельный вызов). Всё состояние/функции держим полями Viz (НЕ новые local:
-- лимит 200 живых локалов на функцию — модуль впритык).
Viz.bboxRaw = function(m) return m:GetBoundingBox() end
Viz.bbModel, Viz.bbClock, Viz.bbC, Viz.bbS = nil, -1, nil, nil
-- [V112] PERF: ПЕРСИСТЕНТНЫЕ scratch-буферы для точек кольца/конуса. Раньше drawFlatRing делал
-- `wpts={}` и drawTargetHitbox — `wArc={}`,`a2d={}`,`az={}` НА КАЖДЫЙ кадр отр��совки = 4 таблицы +
-- ~100 Vector2/Vector3 аллокаций/кадр → GC-дёрганье (главная оставшаяся причина «лагает»). Теперь
-- переиспользуем таблицы (индексы просто перезаписываются, размер сегментов константный). Держим
-- ��олями Viz (НЕ новые local — лимит 200 локалов на giant-функцию).
Viz.ringPts = {}
Viz.coneW   = {}
Viz.cone2d  = {}
Viz.coneZ   = {}
Viz.bboxOf = function(model)
	local nowc = os.clock()
	if model == Viz.bbModel and (nowc - Viz.bbClock) < 0.004 then return Viz.bbC, Viz.bbS end
	local ok, c, s = pcall(Viz.bboxRaw, model)
	if ok and typeof(c) == "CFrame" and typeof(s) == "Vector3" then
		Viz.bbModel, Viz.bbClock, Viz.bbC, Viz.bbS = model, nowc, c, s
		return c, s
	end
	return nil
end

Viz.drawFlatRing = function(cam, model, hrp, hot)
	local footY = hrp.Position.Y - 2.8
	local radius = 3.2
	local bc, bs = Viz.bboxOf(model)
	if bc and bs then
		footY  = bc.Y - bs.Y * 0.5 + 0.08
		radius = math.clamp(math.max(bs.X, bs.Z) * 0.75, 2.4, 6)
	end
	radius = radius * (Config.VizRingScale or 1.0)   -- [V90] пользо��ательский размер кольца
	local spd = Config.VizRingSpeed or 1.0           -- [V90] пользовательская скорость анимации
	local t = Viz.t * spd
	local cx, cz = hrp.Position.X, hrp.Position.Z
	local pulse = 1 + math.sin(t * 3.0) * 0.05
	local wpts = Viz.ringPts   -- [V112] переиспользуемы�� буфер, без аллокации таблицы/кадр
	for i = 0, RING_SEG - 1 do
		local a = i / RING_SEG * math.pi * 2
		local r = radius * pulse * (1 + math.sin(a * 4 + t * 5) * 0.03)
		wpts[i] = Vector3.new(cx + math.cos(a) * r, footY, cz + math.sin(a) * r)
	end
	local thick = hot and 4 or 2.5
	for i = 0, RING_SEG - 1 do
		local j = (i + 1) % RING_SEG
		local f = 0.5 + 0.5 * math.sin(i / RING_SEG * math.pi * 2 + t * 2.2)
		Viz.drawWorldSeg(cam, wpts[i], wpts[j], Config.RingA:Lerp(Config.RingB, f), thick)
	end
end

Viz.footYOf = function(model, hrp)
	local y = hrp.Position.Y - 2.8
	local bc, bs = Viz.bboxOf(model)
	if bc and bs then y = bc.Y - bs.Y * 0.5 + 0.05 end
	return y
end
Viz.drawTargetHitbox = function(cam, model, hrp)
	local look = hrp.CFrame.LookVector
	local flook = Vector3.new(look.X, 0, look.Z)
	if flook.Magnitude < 0.05 then return end
	flook = flook.Unit

	local style = styleOf(model)
	local reach = math.max(styleForward(style, "M1"), styleForward(style, "M2")) + VIZ_CONE_PAD
	local half  = VIZ_CONE_HALF
	local y = Viz.footYOf(model, hrp)
	local origin = Vector3.new(hrp.Position.X, y, hrp.Position.Z)

		local col = Config.ConeSafe
		local me  = localHRP()
		if me then
			local forward = math.max(styleForward(style, "M1"), styleForward(style, "M2"))
			local off  = Vector3.new(me.Position.X - hrp.Position.X, 0, me.Position.Z - hrp.Position.Z)
			local fwd  = off:Dot(flook)
			local side = math.abs(off:Dot(Vector3.new(-flook.Z, 0, flook.X)))
			local slack = Config.HitboxSlack or 0
			if fwd >= (forward - Config.HitboxDepthBack - slack) and fwd <= (forward + Config.HitboxDepth + slack)
			   and side <= (Config.HitHalfWidth + slack) then
				col = Config.ConeHit
			end
		end

	local wArc = Viz.coneW   -- [V112] переиспользуемые буферы, без аллокации таблиц/кадр
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
end

Viz.drawRestrictZone = function(cam)
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
end

function vizUpdate(dt)
	if not LinePool.ok then return end
	local cam = Workspace.CurrentCamera
	-- [module] AutoParry visuals belong to AutoParry: hide them the instant the feature
	-- is disabled, not just when ShowVisuals is off.
	if not (Config.Enabled and Config.ShowVisuals and cam) then vizHideAll(); return end
	Viz.t += dt   -- анимационные часы идут КАЖДЫЙ кадр (дёшево) → фаза кольца плавная даже при троттле

	-- [V111] PERF-ТРОТТЛ: тяжёлую перерисовку (пулы + ~280 операций проекции/Drawing) делаем не
	-- чаще VizMaxFPS. Между апдейтами НЕ трогаем пулы (begin/finish не зовём) → дровинги остаются
	-- видимыми на прошлых позициях; при 120+ fps это срезает основную всегда-активную нагрузку.
	local nowc     = os.clock()
	local interval = 1 / math.clamp(Config.VizMaxFPS or 60, 15, 240)
	if (nowc - (Viz.lastDraw or 0)) < interval then return end
	Viz.lastDraw = nowc

	LinePool:begin(); TriPool:begin()
	local model, hrp = Viz.pickTarget()
	if model and hrp then
		local hot = (State.status == "PARRY" or State.status == "DODGE")
		if Config.VizHitbox ~= false then Viz.drawTargetHitbox(cam, model, hrp) end
		if Config.VizRing ~= false then Viz.drawFlatRing(cam, model, hrp, hot) end
	end
	if Config.VizRestrict ~= false then Viz.drawRestrictZone(cam) end
	LinePool:finish(); TriPool:finish()
end
end   -- [V130] close AutoParry visuals module (do-block for register budget)

-- [V95] ЕДИНЫЙ АППЛИКАТОР ПОВОРОТА. Единственное место, где ��ишется HRP.CFrame ради facing.
-- Работает в RenderStepped ПОСЛЕ игрового AutoRotate/SmoothShiftLock (��ы подключаемся позже —
-- игра грузится раньше), поэтому наш поворот — последний писатель кадра и не проигрывает гонку.
-- Пока есть активная цель — гасим Humanoid.AutoRotate, чтобы игра не докручивала HRP к движению
-- (это и рвало снап + давало д��рганье). Как только цель истекла — О��ИН раз возвращаем AutoRotate.
local function applyFacing()
	local goalPos = State.faceGoalPos   -- [V73]
	local goalHRP = State.faceGoalHRP
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
	local c = localChar()
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum and hum.AutoRotate then hum.AutoRotate = false; State.faceHum = hum end
	-- [V97] PING-SCALED предикт позиции цели ВОЗВРАЩЁН. В V95 я убрал velocity-lead (ду��ая, что
	-- сервер валидирует по факт. позиции) — но это ломало facing на резко движущемся/рывкающем
	-- враге (в логе face=0.14/-0.58 BACK! на LATE-миссах). Причина: на нашем экране другой игрок
	-- отрисован в ПРОШЛОМ (интерп-лаг + ping), а ��ервер держит его ВПЕРЕДИ. При рывке рассинхрон
	-- = vel*latency растёт → мы смотрим туда, где враг БЫЛ, сервер видит спину → блок отклонён.
	-- Упреждаем: aim = pos + flatVel * (ping-based lead). Стоит на месте (vel≈0) �� lead≈0 → как
	-- раньше (нет регресса на статичном боксинге). Рывок → смотрим на СЕРВЕРНУЮ позицию врага.
	local aimPos = goalPos or goalHRP.Position
	local lead   = math.clamp(getPing() * (Config.FacePingLead or 1.0), 0, Config.FaceLeadCap or 0.28)
	if lead > 0 then
		-- прямое чтение свойства (goalHRP уже проверен на .Parent) — БЕЗ pcall-замыкания,
		-- иначе каждый RenderStepped-кадр боя аллоцировался бы новый closure (лишний GC).
		local vel     = goalHRP.AssemblyLinearVelocity
		local flatVel = Vector3.new(vel.X, 0, vel.Z)
		-- [V118] раскладываем упреждение на РАДИАЛЬ (вдоль линии враг↔я) и БОКОВУЮ (перпендикуляр).
		-- Боковая задаёт угол facing → щедрый кап; радиаль на угол не влияет → малый кап. Так дэш
		-- В УПОР (радиальный) больше НЕ съедает бюджет боковой коррекции (толчок влево/вправо).
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
	local goal = CFrame.lookAt(myHRP.Position, myHRP.Position + d)
	if State.faceGoalHard then
		myHRP.CFrame = goal
	else
		myHRP.CFrame = myHRP.CFrame:Lerp(goal, Config.FaceLerp or 0.8)
	end
end

-- [V93] ОТРИС��ВКА визуалов — на Heartbeat, НЕ на RenderStepped.
-- Причина бага «визуал плывёт под ши��тлоком»: SmoothShiftLock (дамп Packages/SmoothShiftLock)
-- правит Camera.CFrame каждый кадр в RenderStepped. Наш прежний RenderStepped:Connect работал
-- в ТОЙ ЖЕ фазе и проеци��овал WorldToViewportPoint по камере, которую шифтлок в этот же кадр
-- ещё домётывал → 2D-точки отставали от реально отрендеренной камеры на кадр → при повороте
-- (шифтлок) дровинги сдвигались/дрож��ли. Heartbeat идёт уже ПОСЛЕ рендера — камера
-- зафиксирована, проекция стабильна (к тому же сам VictimHitboxService игры тоже на Heartbeat).
RunService.Heartbeat:Connect(function(dt)
	local ok = pcall(vizUpdate, dt)
	if not ok then vizHideAll() end
end)

-- [V95] applyFacing (единый аппликатор поворота) — в RenderStepped: должен переигрывать
-- AutoRotate/шифтлок каждый ренд��р-кадр ��ак последний писатель HRP. Пока нет активной цели
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

-- ══════════════════════════════���════════════════���═══════════════════════════
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

		-- ════════════════��══ TAB: AutoParry ════════════��═���════
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
		-- [V120] МАСТЕР-тумблер доджа (primary switch секции). OFF = НИ ОДНОГО доджа вообще (все 7
		-- триггеров идут через performDodge → один гейт). Решает «доджит с нихуя»: одним свитчем.
		feature(apDodge, {
			Title = "Auto Dodge", Flag = "AP_AutoDodge",
			get = function() return Config.AutoDodge ~= false end,
			set = function(v) Config.AutoDodge = v end,
			Desc = "master switch for ALL dodging (heavies, escapes, grabs, cluster)\nOFF = never dodge, block/parry only",
		})
		boolToggle(apDodge, "Dodge All Heavies", "Dodge All Heavies",
			function() return Config.DodgeHeavy end, function(v) Config.DodgeHeavy = v end)
		apDodge:SubLabel({ Text = "dodge EVERY heavy attack instead of blocking\nnot recommended — burns i-frames" })
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

		apBox:Divider()
		apBox:Header({ Name = "Grapple" })
		boolToggle(apBox, "Grapple Win", "Grapple Win",
			function() return Config.SA_GrappleWin end, function(v) Config.SA_GrappleWin = v end)
		apBox:SubLabel({ Text = "any style, makes u win grapple" })

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
	apPlay:SubLabel({ Text = "note: our M1 always uses the fast custom builder (bypasses the 450ms throttle)" })

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
		slider(apVis, { Name = "Visual FPS Cap", Flag = "AP_VizMaxFPS",
			Default = Config.VizMaxFPS or 60, Min = 15, Max = 240, Suffix = " fps",
			Callback = function(v) Config.VizMaxFPS = v end })
		apVis:SubLabel({ Text = "caps how often the ESP redraws (not ur game fps)\nlower = more fps headroom; 60 looks perfectly smooth" })

		apVis:Divider()
		apVis:Header({ Name = "Colors" })
		apVis:Colorpicker({ Name = "Ring Gradient A", Default = Config.RingA,
			Callback = function(c) Config.RingA = c end }, ctx.flag("AP_RingA"))
		apVis:Colorpicker({ Name = "Ring Gradient B", Default = Config.RingB,
			Callback = function(c) Config.RingB = c end }, ctx.flag("AP_RingB"))
		apVis:Colorpicker({ Name = "Safe Cone", Default = Config.ConeSafe,
			Callback = function(c) Config.ConeSafe = c end }, ctx.flag("AP_ConeSafe"))
		apVis:Colorpicker({ Name = "Hit Cone", Default = Config.ConeHit,
			Callback = function(c) Config.ConeHit = c end }, ctx.flag("AP_ConeHit"))
		apVis:Colorpicker({ Name = "Restrict Ring", Default = Config.RestrictCol,
			Callback = function(c) Config.RestrictCol = c end }, ctx.flag("AP_Restrict"))

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

		-- ═══════════════════ TAB: Debug ══════════════���════
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
