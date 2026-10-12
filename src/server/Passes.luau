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

local CHECK_TRIES = 3 -- intentos de preguntar a Roblox si tiene un pase al entrar (la consulta falla a veces)
local VERIFY_TRIES = 6 -- comprobaciones de una compra recién hecha...
local VERIFY_WAIT = 10 -- ...y segundos entre una y otra (Roblox tarda un poco en darla por suya)

local trusted: { [Player]: { [string]: boolean } } = {} -- pases que ya se le han dado una vez sin comprobar

local function grant(player: Player, key: string, owned: boolean)
	player:SetAttribute("Pass_" .. key, owned)
end

-- ¿Tiene ese pase en Roblox? true, false o nil (no se ha podido saber).
local function owns(player: Player, key: string): boolean?
	local ok, owned = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, Config.Gamepasses[key].id)
	if not ok then
		warn(`[Passes] Could not check the pass {key} of {player.Name}: {owned}`)
		return nil
	end
	return owned == true
end

-- Roblox avisa de una compra de pase. Ese aviso lo puede falsear un cliente con trampas, así que la compra se comprueba
-- con Roblox. El pase se da ya (que quien paga no espere), pero solo la primera vez: si la comprobación no lo confirma
-- se le quita, y los avisos siguientes de ese pase esperan a estar confirmados.
local function onPurchased(player: Player, key: string)
	local pass = Config.Gamepasses[key]
	if pass.id <= 0 or Stats.pass(player, key) then
		return
	end
	local given = trusted[player] or {}
	trusted[player] = given
	local early = not given[key]
	given[key] = true
	if early then
		grant(player, key, true)
	end
	for try = 1, VERIFY_TRIES do
		if not player.Parent then
			return
		end
		if owns(player, key) then
			grant(player, key, true)
			-- Robux gastados (clasificaciones): solo de una compra confirmada.
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.id, Enum.InfoType.GamePass)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				PlayerData.addRobuxSpent(player, info.PriceInRobux)
			end
			return
		end
		if try < VERIFY_TRIES then
			task.wait(VERIFY_WAIT)
		end
	end
	local data = PlayerData.read(player)
	if early and player.Parent and not (data and data.passes[key]) then
		warn(`[Passes] {player.Name} announced the purchase of {key} but does not own it: removed.`)
		grant(player, key, false)
	end
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
				-- Si la consulta falla se insiste: quien lo ha pagado no puede quedarse sin él toda la sesión.
				for try = 1, CHECK_TRIES do
					local owned = owns(player, key)
					if owned and player.Parent then
						grant(player, key, true)
					end
					if owned ~= nil or not player.Parent then
						return
					end
					task.wait(try * 5)
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
	if not Config.Tickets.Passes or type(key) ~= "string" or not Config.Gamepasses[key] or Stats.pass(player, key) then
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
		if not purchased or typeof(player) ~= "Instance" then
			return
		end
		for key, pass in Config.Gamepasses do
			if pass.id > 0 and pass.id == gamePassId then
				task.spawn(onPurchased, player, key)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		trusted[player] = nil
	end)
end

return Passes
