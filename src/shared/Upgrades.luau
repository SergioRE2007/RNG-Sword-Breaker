-- Cálculo del valor y el precio de las mejoras definidas en Config.Upgrades.
local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local Upgrades = {}

function Upgrades.value(name: string, level: number): number
	local upgrade = Config.Upgrades[name]
	if upgrade.mode == "add" then
		return upgrade.base + upgrade.perLevel * level
	end
	return upgrade.base * upgrade.perLevel ^ level
end

-- Precio de pasar de `level` a `level + 1`: el de su lista `costs` (un precio por nivel, sacado del calendario de
-- progreso por tools/equilibrio) o, si la mejora no la trae, cost * growth ^ nivel.
function Upgrades.cost(name: string, level: number): number
	local upgrade = Config.Upgrades[name]
	if upgrade.costs then
		return upgrade.costs[math.clamp(level + 1, 1, #upgrade.costs)]
	end
	return math.floor(upgrade.cost * upgrade.growth ^ level)
end

-- "%s" en display = número abreviado (x1.5, x2.25K...); el resto son formatos de string.format.
function Upgrades.display(name: string, level: number): string
	local display = Config.Upgrades[name].display
	local value = Upgrades.value(name, level)
	if string.find(display, "%%s") then
		return string.format(display, Format.multiplier(value))
	end
	return string.format(display, value)
end

return Upgrades
