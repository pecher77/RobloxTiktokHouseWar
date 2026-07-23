--!strict
-- Спавн мобов и их движение по дорожке.
-- Живёт в ServerScriptService.Server.MobSpawner
--
-- Что нужно на карте:
--   ServerStorage/Mobs        — папка с моделями мобов (имена = id из MobConfig)
--   Workspace/MobPath         — папка с точками маршрута: части с именами 1, 2, 3...

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local MobConfig = require(ReplicatedStorage.Shared.MobConfig)

type ActiveMob = {
	model: Model,
	def: MobConfig.MobDef,
	-- К какой точке маршрута сейчас идём
	targetIndex: number,
	speed: number,
	-- Насколько центр модели выше её ног, чтобы моб не тонул в дорожке
	groundOffset: number,
	-- Собрана ли модель на Motor6D (тогда двигаем только корень)
	rigged: boolean,
}

local templatesFolder = ServerStorage:WaitForChild("Mobs")
local pathFolder = workspace:WaitForChild("MobPath")

local activeFolder = workspace:FindFirstChild("ActiveMobs")
if not activeFolder then
	activeFolder = Instance.new("Folder")
	activeFolder.Name = "ActiveMobs"
	activeFolder.Parent = workspace
end

local rng = Random.new()
local activeMobs: { ActiveMob } = {}

-- Точки маршрута, отсортированные по числу в имени: 1, 2, 10 (а не 1, 10, 2).
local function collectWaypoints(): { Vector3 }
	local parts: { BasePart } = {}
	for _, child in pathFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end

	table.sort(parts, function(a, b)
		local na = tonumber(a.Name:match("%d+") or "") or 0
		local nb = tonumber(b.Name:match("%d+") or "") or 0
		return na < nb
	end)

	local points: { Vector3 } = {}
	for _, part in parts do
		-- Целимся в верхнюю грань части, а не в её центр
		table.insert(points, part.Position + Vector3.new(0, part.Size.Y * 0.5, 0))
	end
	return points
end

local waypoints = collectWaypoints()

-- Откуда взять анимацию ходьбы: из конфига, из самой модели или дефолтную.
local function resolveWalkAnimation(model: Model, humanoid: Humanoid, def: MobConfig.MobDef): string?
	if def.walkAnimation then
		return def.walkAnimation
	end

	-- Объект Animation, положенный в модель руками
	local explicit = model:FindFirstChild("WalkAnim", true)
	if explicit and explicit:IsA("Animation") and explicit.AnimationId ~= "" then
		return explicit.AnimationId
	end

	-- Стандартный скрипт Animate — есть у персонажей из тулбокса
	local animate = model:FindFirstChild("Animate")
	if animate then
		local holder = animate:FindFirstChild("walk") or animate:FindFirstChild("run")
		local anim = holder and holder:FindFirstChildWhichIsA("Animation")
		if anim and anim.AnimationId ~= "" then
			return anim.AnimationId
		end
	end

	return MobConfig.DEFAULT_WALK_ANIMATION[humanoid.RigType.Name]
end

local function playWalkAnimation(model: Model, def: MobConfig.MobDef)
	if not MobConfig.PLAY_WALK_ANIMATION then
		return
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animationId = resolveWalkAnimation(model, humanoid, def)
	if not animationId then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(("[MobSpawner] не загрузилась анимация %s у %s"):format(animationId, def.id))
		return
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement
	track:Play()
end

-- Готовим клон: якорим только корень — его двигает скрипт. Остальные части должны
-- остаться незаякоренными, иначе анимация не сможет крутить суставы Motor6D.
local function prepareModel(model: Model): (number, boolean)
	local primary = model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart") :: BasePart?
		or model:FindFirstChildWhichIsA("BasePart", true)

	if not primary then
		return 0, false
	end
	model.PrimaryPart = primary

	-- Если модель не собрана на Motor6D, анимировать нечего — якорим всё,
	-- иначе части просто рассыплются под гравитацией.
	local isRigged = model:FindFirstChildWhichIsA("Motor6D", true) ~= nil

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = not isRigged or descendant == primary
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Massless = descendant ~= primary
		end
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		-- Моба двигаем сами, встроенный ИИ и урон нам не нужны
		humanoid.WalkSpeed = 0
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Штатный Animate иначе поставит поверх нашей ходьбы анимацию покоя
	local animate = model:FindFirstChild("Animate")
	if animate and (animate:IsA("Script") or animate:IsA("LocalScript")) then
		animate.Disabled = true
	end

	-- Расстояние от точки поворота модели до её "ног"
	local boxCF, boxSize = model:GetBoundingBox()
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	return model:GetPivot().Position.Y - bottomY, isRigged
end

-- У модели на Motor6D двигаем только корень: остальные части подтянутся суставами,
-- и анимация не будет драться с нашими телепортами каждый кадр.
local function setMobCFrame(mob: ActiveMob, cframe: CFrame)
	local primary = mob.model.PrimaryPart
	if mob.rigged and primary then
		primary.CFrame = cframe
	else
		mob.model:PivotTo(cframe)
	end
end

local function spawnMob()
	if #waypoints < 2 then
		return
	end
	if #activeMobs >= MobConfig.MAX_ALIVE then
		return
	end

	local def = MobConfig.pickRandom(rng)
	if not def then
		return
	end

	local template = templatesFolder:FindFirstChild(def.id)
	if not template or not template:IsA("Model") then
		warn(("[MobSpawner] нет модели ServerStorage.Mobs.%s"):format(def.id))
		return
	end

	local model = template:Clone()
	local groundOffset, rigged = prepareModel(model)

	-- Пригодится другим системам (покупка, доход) — читается через GetAttribute
	model:SetAttribute("MobId", def.id)
	model:SetAttribute("Income", def.income)
	model:SetAttribute("Price", def.price)

	local start = waypoints[1] + Vector3.new(0, groundOffset, 0)
	model:PivotTo(CFrame.lookAt(start, Vector3.new(waypoints[2].X, start.Y, waypoints[2].Z)))
	model.Parent = activeFolder

	-- Только после Parent: Animator не грузит треки у модели вне игрового дерева
	playWalkAnimation(model, def)

	table.insert(activeMobs, {
		model = model,
		def = def,
		targetIndex = 2,
		speed = def.speed or MobConfig.DEFAULT_SPEED,
		groundOffset = groundOffset,
		rigged = rigged,
	})
end

-- Один шаг движения. Возвращает false, если моб дошёл до конца и его пора удалить.
local function stepMob(mob: ActiveMob, dt: number): boolean
	local target = waypoints[mob.targetIndex]
	if not target then
		return false
	end

	local pivot = mob.model:GetPivot()
	local goal = target + Vector3.new(0, mob.groundOffset, 0)
	local delta = goal - pivot.Position
	local distance = delta.Magnitude
	local step = mob.speed * dt

	if distance <= step then
		-- Точка достигнута, переключаемся на следующую
		mob.targetIndex += 1
		if mob.targetIndex > #waypoints then
			setMobCFrame(mob, CFrame.new(goal) * (pivot - pivot.Position))
			return false
		end
		target = waypoints[mob.targetIndex]
		goal = target + Vector3.new(0, mob.groundOffset, 0)
		delta = goal - pivot.Position
		distance = delta.Magnitude
		if distance <= 0 then
			return true
		end
	end

	local nextPos = pivot.Position + delta.Unit * math.min(step, distance)
	-- Смотрим вперёд, но не заваливаем моба на подъёмах
	local lookAt = Vector3.new(goal.X, nextPos.Y, goal.Z)
	if (lookAt - nextPos).Magnitude > 0.01 then
		setMobCFrame(mob, CFrame.lookAt(nextPos, lookAt))
	else
		setMobCFrame(mob, CFrame.new(nextPos) * (pivot - pivot.Position))
	end

	return true
end

RunService.Heartbeat:Connect(function(dt)
	-- Идём с конца, чтобы безопасно удалять из массива на ходу
	for i = #activeMobs, 1, -1 do
		local mob = activeMobs[i]
		if not mob.model.Parent then
			table.remove(activeMobs, i)
		elseif not stepMob(mob, dt) then
			mob.model:Destroy()
			table.remove(activeMobs, i)
		end
	end
end)

task.spawn(function()
	if #waypoints < 2 then
		warn("[MobSpawner] в Workspace.MobPath нужно минимум 2 точки маршрута")
		return
	end

	while true do
		task.wait(MobConfig.SPAWN_INTERVAL)
		spawnMob()
	end
end)
