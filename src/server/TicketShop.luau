-- Lo que se compra con tickets de misión en el puesto de Misiones (pestaña "Comprar"): la lista y los precios son
-- Config.Tickets.Shop. El cliente pide con BuyTicketItem(posición en la lista) y aquí se cobra y se da de una vez.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local TicketShop = {}

local TICKET = "missionToken"
local COOLDOWN = 0.2 -- segundos mínimos entre dos compras de un jugador

local last: { [Player]: number } = {}

local function onBuy(player: Player, index: unknown)
	local offer = if type(index) == "number" then Config.Tickets.Shop[index] else nil
	local item = offer and Config.Items[offer.item]
	local now = os.clock()
	if not offer or not item or now - (last[player] or 0) < COOLDOWN then
		return
	end
	local data = PlayerData.read(player)
	if not data or not (offer.price > 0) or data.items[TICKET] < offer.price then
		return
	end
	last[player] = now
	PlayerData.edit(player, function(edited)
		edited.items[TICKET] -= offer.price
		edited.items[offer.item] += 1
	end)
	Remotes.Notice:FireClient(player, `+1 {item.name}`, item.color)
end

function TicketShop.start()
	Remotes.BuyTicketItem.OnServerEvent:Connect(onBuy)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return TicketShop
