-- Regalo a quien compró tréboles antes del cambio (pedido por el usuario el 18-10-2026): el grande pasó de un objeto a
-- toda la parcela y los que pagaron antes reciben otra vez los mismos tréboles que compraron, con un mensaje grande.
-- Se da una sola vez por cuenta (marca KEY en data.codes, que ya se guarda). La lista sale de las ventas del grupo
-- (Creator Hub → Ingresos → Ventas), que enseñan el nombre visible: cada entrada lleva el UserId cuando se encontró y
-- el nombre por si no; y solo cuenta quien tiene alguna compra de producto apuntada (data.receipts), para que un nombre
-- visible repetido no se lo lleve otro.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local CloverRefund = {}

local KEY = "~refund:clover-plot" -- con "~" y minúsculas: ningún código escrito en la Tienda puede coincidir
local SEEN = "~refund:clover-plot:seen" -- el mensaje ya se vio entero
local ITEM = "luckClover"
local DELAY = 8 -- segundos tras cargar, para que no lo tape la pantalla de carga
local SHOW = 14 -- segundos del mensaje grande

local LIST = {
	{ id = 1186440479, name = "Haynsi", amount = 3 },
	{ id = 2064366140, name = "Oabxixjs", amount = 2 }, -- usuario "4opas"
	{ id = 282573706, name = "kavaki", amount = 1 },
	{ id = 11755852771, name = "Namoaengg", amount = 1 },
	{ id = 4277720977, name = "sniperjor", amount = 11 },
	{ name = "I_Stog", amount = 1 }, -- no apareció en la búsqueda de Roblox: solo por nombre
}

local function entryFor(player: Player)
	local display, name = string.lower(player.DisplayName), string.lower(player.Name)
	for _, entry in LIST do
		local wanted = string.lower(entry.name)
		if entry.id == player.UserId or wanted == display or wanted == name then
			return entry
		end
	end
	return nil
end

local function check(player: Player)
	local data = PlayerData.read(player)
	local entry = entryFor(player)
	if not data or not entry or data.codes[SEEN] or #data.receipts == 0 then
		return
	end
	-- Los tréboles se dan en cuanto entra (y se guarda ya); el mensaje solo se da por visto cuando ha estado en pantalla
	-- entero: si se va antes, le vuelve a salir la próxima vez, sin darle más tréboles.
	if not data.codes[KEY] then
		PlayerData.edit(player, function(edited)
			edited.codes[KEY] = true
			edited.items[ITEM] += entry.amount
		end)
		PlayerData.save(player)
	end
	task.delay(DELAY, function()
		if not player.Parent then
			return
		end
		local text = if entry.amount == 1
			then Lang.t(player, "Clovers have changed! Now they boost a whole plot. Thanks for buying before: here is 1 Lucky Clover!")
			else Lang.t(player, "Clovers have changed! Now they boost a whole plot. Thanks for buying before: here are {n} Lucky Clovers!", { n = entry.amount })
		Remotes.AdminBanner:FireClient(player, text, Lang.t(player, "GIFT"), SHOW)
		task.wait(SHOW)
		if player.Parent then
			PlayerData.edit(player, function(edited)
				edited.codes[SEEN] = true
			end)
		end
	end)
end

function CloverRefund.start()
	PlayerData.onLoad(check)
end

return CloverRefund
