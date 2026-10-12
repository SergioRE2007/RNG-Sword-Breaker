-- Pases de juego (gamepass, Config.Gamepasses): mira cuáles tiene cada jugador y lo publica en el atributo
-- "Pass_<clave>" (true o false), que es lo que leen servidor y cliente con Stats.pass y Stats.perk. La compra
-- la abre el cliente (tienda del menú) y Roblox avisa aquí cuando se completa. El atributo solo lo pone el
-- servidor: lo que el cliente se cambie a sí mismo no llega aquí, así que no puede regalarse un pase.
-- Un pase también se compra con tickets de misión (BuyPassTickets; precio en Stats.ticketPrice): esos se guardan en
-- data.passes y valen igual que los de Robux.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local PlayerData = require(script.Parent.PlayerData)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Tell = require(script.Parent.Tell)

local Passes = {}

local TICKET = "missionToken"
local GOLD = Color3.fromRGB(255, 200, 60)

local function grant(player: Player, key: string, owned: boolean)
	player:SetAttribute("Pass_" .. key, owned)
end

local function onPlayer(player: Player)
	-- Modo de pruebas (solo en Studio): todos los pases.
	local test = RunService:IsStudio() and Config.Test.AllGamepasses
	-- Los comprados con tickets: si los datos ya están cargados se ponen aquí, y si no, al cargar (onLoaded).
	local data = PlayerData.read(player)
	for key, pass in Config.Gamepasses do
		grant(player, key, test or (data ~= nil and data.passes[key] == true))
		if not test and pass.id > 0 then
			task.spawn(function()
				local ok, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
				if ok and owned and player.Parent then
					grant(player, key, true)
				elseif not ok then
					warn(`[Passes] Could not check the pass {key} of {player.Name}: {owned}`)
				end
			end)
		end
	end
end

local function onLoaded(player: Player)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	for key in Config.Gamepasses do
		if data.passes[key] then
			grant(player, key, true)
		end
	end
	-- Modo de pruebas (solo en Studio): tickets para probar la compra.
	local gift = if RunService:IsStudio() then Config.Test.Tickets or 0 else 0
	if gift > 0 and (Config.Test.Progress or 0) <= 0 then
		PlayerData.edit(player, function(edited)
			edited.items[TICKET] = math.max(edited.items[TICKET], gift)
		end)
	end
end

-- Compra con tickets: el precio lo pone el servidor y se cobra y se apunta de una vez.
local function onBuy(player: Player, key: unknown)
	if type(key) ~= "string" or not Config.Gamepasses[key] or Stats.pass(player, key) then
		return
	end
	local data = PlayerData.read(player)
	local cost = Stats.ticketPrice(key)
	if not data or data.passes[key] or not (cost > 0) or data.items[TICKET] < cost then
		return
	end
	PlayerData.edit(player, function(edited)
		edited.items[TICKET] -= cost
		edited.passes[key] = true
	end)
	grant(player, key, true)
	Tell.notice(player, GOLD, "Pass unlocked: {name}!", { name = Lang.t(player, Config.Gamepasses[key].name) })
	task.spawn(PlayerData.save, player) -- una compra no espera al guardado automático
end

function Passes.start()
	PlayerData.onLoad(onLoaded)
	Remotes.BuyPassTickets.OnServerEvent:Connect(onBuy)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		for key, pass in Config.Gamepasses do
			if pass.id == gamePassId then
				grant(player, key, true)
			end
		end
	end)
end

return Passes
