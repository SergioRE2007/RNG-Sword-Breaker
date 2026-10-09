-- Lo que enseñan de cada zona de mazmorra los carteles de las salas, la ventana de grupo y el resultado: sus premios
-- principales, el daño recomendado y si está cerrada. Una sola fuente para cliente y servidor (el servidor repite la
-- comprobación de "cerrada" antes de dejar entrar).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local DungeonInfo = {}

local GOLD = Color3.fromRGB(255, 215, 90)

-- Premios principales de la zona, uno por línea: { text, color }. Lo que cae es la armadura del set de la zona y los
-- cristales (multiplicados por "loot"); la calidad de la armadura sube con "qualityLuck".
function DungeonInfo.rewards(index: number): { { text: string, color: Color3 } }
	local level = Config.Dungeons[index]
	if not level then
		return {}
	end
	return {
		{ text = `Armadura {level.set}`, color = GOLD },
		{ text = `Cristales x{Format.multiplier(level.loot)}`, color = Config.Items.gradeCrystal.color },
		{ text = `Calidad x{Format.multiplier(level.qualityLuck)}`, color = Config.Items.traitCrystal.color },
	}
end

-- Daño por golpe recomendado para la zona.
function DungeonInfo.recommended(index: number): number
	local level = Config.Dungeons[index]
	return if level then level.hp else 0
end

-- Por qué no se puede entrar con ese daño (texto corto), o nil si se puede. Solo cierra una zona si trae "minDamage".
function DungeonInfo.lock(index: number, damage: number): string?
	local level = Config.Dungeons[index]
	if level and level.minDamage and damage < level.minDamage then
		return `Daño mínimo {Format.short(level.minDamage)}`
	end
	return nil
end

return DungeonInfo
