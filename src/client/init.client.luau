--!strict
-- Точка входа клиента. Живёт в StarterPlayer.StarterPlayerScripts.Client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(("[%s] клиент запущен, Rojo подключён"):format(Config.GAME_NAME))
