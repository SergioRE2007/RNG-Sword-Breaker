-- Códigos de regalo (Config.Codes; se escriben en la Tienda, sección "Códigos"). Cada jugador canjea cada código una
-- sola vez (data.codes, guardado). Un código puede caducar (`expires`, "AAAA-MM-DD": vale hasta que acaba ese día, hora
-- UTC) y tener un tope de usos entre todos los jugadores (`maxUses`): ese contador es global, en el DataStore
-- "<DataStoreName>_Codes", y se pide con UpdateAsync para que dos servidores no den el último a la vez. En Studio o sin
-- publicar el contador vale solo para esa partida. Lo que da es la lista `rewards`: { coins = N }, { gems = N } o
-- { item = clave de Config.Items, amount = N } (tickets, cristales, tréboles, pociones...).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Codes = {}

local GOOD = Color3.fromRGB(110, 230, 130)
local BAD = Color3.fromRGB(255, 110, 110)
local COOLDOWN = 1.5 -- segundos entre dos intentos de un jugador
local MAX_LENGTH = 40

local last: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local localUses: { [string]: number } = {} -- contador de usos cuando no hay DataStore (Studio)

local function store()
	if game.PlaceId == 0 or RunService:IsStudio() then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName .. "_Codes")
	end)
	return if ok then result else nil
end

-- Como se guarda y se compara un código: sin espacios y en mayúsculas.
function Codes.normalize(text: string): string
	return string.upper((string.gsub(text, "%s+", "")))
end

-- Hora (os.time) en que deja de valer ese código, o nil si no caduca. Una fecha mal escrita lo da por caducado.
function Codes.expiry(code): number?
	if code.expires == nil then
		return nil
	end
	local year, month, day = string.match(tostring(code.expires), "^(%d+)-(%d+)-(%d+)$")
	if not year then
		return 0
	end
	return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) + 1, hour = 0 })
end

-- Coge uno de los usos del código. Devuelve true, false (agotado) o nil (no se pudo comprobar).
local function takeUse(key: string, max: number): boolean?
	local ds = store()
	if not ds then
		if RunService:IsStudio() or game.PlaceId == 0 then
			local used = localUses[key] or 0
			if used >= max then
				return false
			end
			localUses[key] = used + 1
			return true
		end
		return nil
	end
	local taken = false
	local ok = pcall(ds.UpdateAsync, ds, key, function(current)
		local used = if type(current) == "number" then current else 0
		if used >= max then
			taken = false
			return nil
		end
		taken = true
		return used + 1
	end)
	return if ok then taken else nil
end

local function give(player: Player, rewards): string
	local parts = {}
	for _, reward in rewards do
		if reward.coins then
			PlayerData.addCoins(player, reward.coins)
			table.insert(parts, `{Format.short(reward.coins)} monedas`)
		elseif reward.gems then
			PlayerData.addGems(player, reward.gems)
			table.insert(parts, `{Format.short(reward.gems)} gemas`)
		elseif reward.item and Config.Items[reward.item] then
			local amount = reward.amount or 1
			PlayerData.edit(player, function(edited)
				edited.items[reward.item] += amount
			end)
			table.insert(parts, `{Format.short(amount)} {Config.Items[reward.item].name}`)
		end
	end
	return table.concat(parts, ", ")
end

local function onRedeem(player: Player, text: unknown)
	local now = os.clock()
	if type(text) ~= "string" or #text > MAX_LENGTH or busy[player] or now - (last[player] or 0) < COOLDOWN then
		return
	end
	last[player] = now
	local key = Codes.normalize(text)
	local code = Config.Codes[key]
	local data = PlayerData.read(player)
	if not data or key == "" then
		return
	end
	if not code then
		Remotes.Notice:FireClient(player, "Ese código no existe", BAD)
		return
	end
	if data.codes[key] then
		Remotes.Notice:FireClient(player, "Ya has usado ese código", BAD)
		return
	end
	local expiry = Codes.expiry(code)
	if expiry and os.time() >= expiry then
		Remotes.Notice:FireClient(player, "Ese código ha caducado", BAD)
		return
	end
	if code.maxUses then
		-- La consulta tarda: mientras, no se atiende otro intento suyo (no podría coger dos usos del mismo código).
		busy[player] = true
		local taken = takeUse(key, code.maxUses)
		busy[player] = nil
		if not player.Parent or PlayerData.read(player) ~= data then
			return
		end
		if taken == nil then
			Remotes.Notice:FireClient(player, "No se ha podido comprobar el código: prueba otra vez", BAD)
			return
		elseif not taken then
			Remotes.Notice:FireClient(player, "Ese código ya no tiene usos", BAD)
			return
		end
	end
	PlayerData.edit(player, function(edited)
		edited.codes[key] = true
	end)
	local got = give(player, code.rewards)
	Remotes.Notice:FireClient(player, `¡Código canjeado! +{got}`, GOOD)
	task.spawn(PlayerData.save, player) -- que no se pierda el canje si el servidor se cae
end

function Codes.start()
	Remotes.RedeemCode.OnServerEvent:Connect(onRedeem)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		busy[player] = nil
	end)
end

return Codes
