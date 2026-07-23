--!strict
-- Точка входа сервера. Живёт в ServerScriptService.Server

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(("[%s] сервер запущен, Rojo подключён"):format(Config.GAME_NAME))
