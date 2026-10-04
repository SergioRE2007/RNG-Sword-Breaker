local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 1500000 -> "1.5M"
function Format.short(n: number): string
	if n == math.huge then
		return "∞"
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end
	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local value = math.floor(n / 10 ^ (index * 3) * 100) / 100
	local text = string.format("%.2f", value):gsub("%.?0+$", "")
	return text .. SUFFIXES[index + 1]
end

-- Como short pero con decimales por debajo de 1000: 1.5 -> "1.5", 2250 -> "2.25K"
function Format.multiplier(n: number): string
	if n >= 1000 then
		return Format.short(n)
	end
	return (string.format("%.2f", n):gsub("%.?0+$", ""))
end

-- Lo contrario de short: "1000" -> 1000, "1.5k" -> 1500, "2Qi" -> 2e18. nil si no se entiende.
function Format.parse(text: string): number?
	local digits, suffix = string.match(text, "^%s*([%d%.]+)%s*(%a*)%s*$")
	local value = tonumber(digits)
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
