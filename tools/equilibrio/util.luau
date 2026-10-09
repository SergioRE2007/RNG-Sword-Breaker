-- Utilidades comunes de la herramienta de equilibrio.
local Util = {}

-- Mediana de una lista de números (la ordena).
function Util.mediana(values: { number }): number
	table.sort(values)
	local count = #values
	if count == 0 then
		return 0 / 0
	end
	if count % 2 == 1 then
		return values[(count + 1) / 2]
	end
	return (values[count / 2] + values[count / 2 + 1]) / 2
end

-- Segundos -> "45 s", "12 min", "3.4 h"; "no llega" si es infinito.
function Util.tiempo(seconds: number?): string
	if not seconds or seconds ~= seconds or seconds == math.huge then
		return "no llega"
	end
	if seconds < 90 then
		return `{math.round(seconds)} s`
	end
	if seconds < 5400 then
		return `{math.round(seconds / 60)} min`
	end
	return `{string.format("%.1f", seconds / 3600)} h`
end

-- Redondea a `digits` cifras significativas (precios y vidas "bonitos").
function Util.redondo(value: number, digits: number): number
	if value <= 0 then
		return 0
	end
	local scale = 10 ^ (math.floor(math.log10(value)) - digits + 1)
	return math.round(value / scale) * scale
end

return Util
