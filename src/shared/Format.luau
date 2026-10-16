local Lang = require(script.Parent.Lang)

local Format = {}

-- Hasta 1e63 (vigintillón): por encima de la última, el número sigue creciendo delante de ella.
local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

-- Los decimales van con punto en inglés y con coma en español (Lang.decimal): `player` es quien va a leer el número
-- (en el cliente siempre es el jugador local; en el servidor, sin él, sale con punto).

-- 1234 -> "1.23K", 1500000 -> "1.5M"
function Format.short(n: number, player: Player?): string
	if n == math.huge then
		return "∞"
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end
	-- Con un poco de margen: con números enormes la división no es exacta (1e23 daba "99,99Sx" en vez de "100Sx").
	local index = math.min(math.floor(math.log10(n) / 3 + 1e-9), #SUFFIXES - 1)
	local value = math.floor(n / 10 ^ (index * 3) * 100 + 1e-6) / 100
	local text = string.format("%.2f", value):gsub("%.?0+$", "")
	return Lang.decimal(player, text) .. SUFFIXES[index + 1]
end

-- Como short pero con decimales por debajo de 1000: 1.5 -> "1.5", 2250 -> "2.25K"
function Format.multiplier(n: number, player: Player?): string
	if n >= 1000 then
		return Format.short(n, player)
	end
	return Lang.decimal(player, (string.format("%.2f", n):gsub("%.?0+$", "")))
end

-- Lo contrario de short: "1000" -> 1000, "1.5k" -> 1500, "2Qi" -> 2e18 (también con coma: "1,5k"). nil si no se entiende.
function Format.parse(text: string): number?
	local digits, suffix = string.match(text, "^%s*([%d%.,]+)%s*(%a*)%s*$")
	local value = tonumber(digits and (string.gsub(digits, ",", ".")))
	if not value then
		return nil
	end
	if suffix == "" then
		return value
	end
	for index, name in SUFFIXES do
		if string.lower(name) == string.lower(suffix) then
			return value * 10 ^ ((index - 1) * 3)
		end
	end
	return nil
end

return Format
