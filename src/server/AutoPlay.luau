-- Autoclicker y Auto de la parcela (botones a los lados de la casilla del arma, client/AutoPlay). Los espadazos los
-- sigue dando el cliente, por el mismo camino que un clic (Swing), así que aquí solo se decide si puede tenerlos
-- encendidos y se publica en los atributos "AutoClick" y "AutoFarm" del jugador:
--   Autoclicker: gratis para quien esté en el grupo del juego (Config.AutoClicker.group). El "me gusta" no se puede
--     comprobar: Roblox no le dice a un juego quién le ha dado like.
--   Auto: ventaja "autoFarm" de un pase de juego, y solo dentro de tu parcela (al salir de ella se apaga solo).
-- No se guardan: los dos entran apagados.
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Plots = require(script.Parent.Plots)

local AutoPlay = {}

local CHECK_EVERY = 3 -- segundos mínimos entre dos consultas del grupo de un jugador (Roblox las limita)
local PLOT_MARGIN = 6 -- studs de más alrededor de la parcela que aún cuentan como estar dentro
local ORANGE = Color3.fromRGB(255, 170, 60)

local member: { [Player]: boolean } = {} -- ya se ha visto que está en el grupo
local lastCheck: { [Player]: number } = {}

-- Grupo que hay que seguir: el de Config o, si no hay, el grupo dueño del juego. 0 = ninguno (no se pide nada).
local function groupId(): number
	if Config.AutoClicker.group > 0 then
		return Config.AutoClicker.group
	end
	return if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
end

-- Pregunta a Roblox cada vez (Player:IsInGroup se queda con lo que había al entrar y no ve a quien se acaba de unir).
local function inGroup(player: Player, id: number): boolean
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not ok then
		warn(`[AutoPlay] No se pudo mirar el grupo de {player.Name}: {groups}`)
		return false
	end
	for _, group in groups do
		if group.Id == id then
			return true
		end
	end
	return false
end

local function inPlot(player: Player): boolean
	local plot = Plots.get(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not plot or not root or (player:GetAttribute("Dungeon") or 0) > 0 then
		return false
	end
	local point = plot.cframe:PointToObjectSpace(root.Position)
	local half = Config.Plot.Size / 2 + PLOT_MARGIN
	return math.abs(point.X) <= half and math.abs(point.Z) <= half
end

local function setClick(player: Player)
	local id = groupId()
	if id == 0 or member[player] then
		player:SetAttribute("AutoClick", true)
		return
	end
	local now = os.clock()
	if now - (lastCheck[player] or 0) >= CHECK_EVERY then
		lastCheck[player] = now
		if inGroup(player, id) and player.Parent then
			member[player] = true
			player:SetAttribute("AutoClick", true)
			return
		end
	end
	if player.Parent then
		Remotes.AutoDenied:FireClient(player, "click", id)
	end
end

local function setFarm(player: Player)
	if not Stats.perk(player, "autoFarm") then
		Remotes.AutoDenied:FireClient(player, "farm")
	elseif not inPlot(player) then
		Remotes.Notice:FireClient(player, "Ve a tu parcela para activar el Auto", ORANGE)
	else
		player:SetAttribute("AutoFarm", true)
	end
end

function AutoPlay.start()
	Remotes.SetAuto.OnServerEvent:Connect(function(player, mode, on)
		if mode ~= "click" and mode ~= "farm" then
			return
		end
		if on ~= true then
			player:SetAttribute(if mode == "click" then "AutoClick" else "AutoFarm", false)
		elseif mode == "click" then
			setClick(player)
		else
			setFarm(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		member[player] = nil
		lastCheck[player] = nil
	end)
	-- El Auto solo vale en tu parcela: al salir de ella (andando, viajando o entrando en una mazmorra) se apaga.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("AutoFarm") == true and not inPlot(player) then
					player:SetAttribute("AutoFarm", false)
				end
			end
		end
	end)
end

return AutoPlay
