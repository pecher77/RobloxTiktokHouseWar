--!strict
-- Список мобов и настройки спавна.
-- Живёт в ReplicatedStorage.Shared.MobConfig

export type MobDef = {
	-- Имя модели в ServerStorage.Mobs (должно совпадать один-в-один)
	id: string,
	-- Как моб называется в интерфейсе
	displayName: string,
	-- Вес для случайного выбора. Чем больше — тем чаще выпадает.
	-- Это не проценты: шанс = weight / (сумма всех weight).
	weight: number,
	-- Сколько денег приносит в секунду, когда стоит на базе игрока
	income: number,
	-- Сколько стоит купить с дорожки
	price: number,
	-- Скорость движения по дорожке, шпилек/сек. nil = DEFAULT_SPEED
	speed: number?,
	-- Своя анимация ходьбы, "rbxassetid://...". nil = ищем в модели, потом дефолтную
	walkAnimation: string?,
}

local MobConfig = {}

-- Пауза между спавнами, в секундах
MobConfig.SPAWN_INTERVAL = 1

-- Скорость по умолчанию
MobConfig.DEFAULT_SPEED = 8

-- Предохранитель: больше столько мобов на дорожке одновременно не будет
MobConfig.MAX_ALIVE = 30

-- Шанс, что в очередной тик вообще никто не заспавнится (0 = спавним всегда)
MobConfig.EMPTY_CHANCE = 0

-- Проигрывать ли мобам анимацию ходьбы
MobConfig.PLAY_WALK_ANIMATION = true

-- Стандартные анимации Roblox — запасной вариант для моделей без своих.
-- Ключ — значение Humanoid.RigType.
MobConfig.DEFAULT_WALK_ANIMATION = {
	R6 = "rbxassetid://180426354",
	R15 = "rbxassetid://507777826",
} :: { [string]: string }

MobConfig.MOBS = {
	{ id = "Noob", displayName = "Noob", weight = 50, income = 1, price = 25 },
	{ id = "Guest", displayName = "Guest", weight = 30, income = 3, price = 100 },
	{ id = "Bacon", displayName = "Bacon Hair", weight = 15, income = 10, price = 500 },
	{ id = "Boss", displayName = "Boss", weight = 5, income = 50, price = 5000, speed = 5 },
} :: { MobDef }

-- Случайный моб с учётом весов.
function MobConfig.pickRandom(rng: Random): MobDef?
	if MobConfig.EMPTY_CHANCE > 0 and rng:NextNumber() < MobConfig.EMPTY_CHANCE then
		return nil
	end

	local total = 0
	for _, def in MobConfig.MOBS do
		total += def.weight
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * total
	for _, def in MobConfig.MOBS do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end

	return MobConfig.MOBS[#MobConfig.MOBS]
end

return MobConfig
