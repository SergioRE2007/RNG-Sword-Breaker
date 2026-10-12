-- Idioma de cada jugador para los textos que escribe el servidor (server/Tell): su cliente dice cuál tiene elegido
-- para esta experiencia (remote SetLang, client/Language) y aquí se apunta en su atributo "Lang", que es lo primero
-- que mira Lang.code. Solo valen "es" y "en"; es un gusto del jugador, no hay nada que comprobar más allá de eso.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Language = {}

function Language.start()
	Remotes.SetLang.OnServerEvent:Connect(function(player: Player, code: unknown)
		if code == "es" or code == "en" then
			player:SetAttribute("Lang", code)
		end
	end)
end

return Language
