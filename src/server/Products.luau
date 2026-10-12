-- Productos de Robux que se compran las veces que se quiera (Config.Products: los packs de Trébol de la suerte). La
-- compra la abre el cliente (Tienda) y Roblox llama aquí a ProcessReceipt hasta que se le dice que está entregada. Cada
-- compra entregada se apunta en data.receipts (se guarda con la partida), para no dar la misma dos veces si Roblox
-- vuelve a preguntar; si el jugador no está o sus datos no han cargado, se deja pendiente y Roblox lo reintenta.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local Lang = require(ReplicatedStorage.Shared.Lang)

local Products = {}

local KEPT = 100 -- compras recordadas por jugador

local function find(productId: number)
	for _, product in Config.Products do
		if product.id > 0 and product.id == productId then
			return product
		end
	end
	return nil
end

local function process(receipt)
	local product = find(receipt.ProductId)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and PlayerData.read(player)
	if not product or not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	PlayerData.edit(player, function(edited)
		edited.items[product.item] += product.amount
		table.insert(edited.receipts, receipt.PurchaseId)
		while #edited.receipts > KEPT do
			table.remove(edited.receipts, 1)
		end
	end)
	local item = Config.Items[product.item]
	Remotes.Notice:FireClient(player, `+{product.amount} {Lang.t(player, item.name)}`, item.color)
	task.spawn(PlayerData.save, player) -- una compra no espera al guardado automático
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Products.start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(process, receipt)
		if not ok then
			warn(`[Products] Purchase {receipt.PurchaseId} not delivered: {decision}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
end

return Products
