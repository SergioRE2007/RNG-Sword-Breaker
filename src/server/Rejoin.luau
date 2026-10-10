-- Reconexión antes de la expulsión por inactividad (Config.Rejoin). Roblox echa a quien lleva 20 min sin tocar nada;
-- el cliente (client/Rejoin) avisa un poco antes y aquí se saca al jugador y se le vuelve a meter, con lo que estaba
-- haciendo apuntado en los datos del viaje: dónde estaba (en su parcela se guarda el sitio dentro de ella, porque al
-- volver le puede tocar otra), el autoclicker y el Auto, y la mazmorra con su Repetir y su pelea automática.
-- Al llegar no se da nada por bueno: el sitio se comprueba, el autoclicker y el Auto pasan otra vez por server/AutoPlay
-- y la mazmorra por server/Party, como si lo pidiera el jugador. Los datos se guardan antes de salir.
-- En Studio no hay viajes: se hace el mismo recorrido sin salir (se le saca de lo que hacía y se le devuelve), para probarlo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AutoPlay = require(script.Parent.AutoPlay)
local Dungeons = require(script.Parent.Dungeons)
local Party = require(script.Parent.Party)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

local Rejoin = {}

local VERSION = 1
local READY_TIMEOUT = 30 -- segundos que se espera, al llegar, a que el jugador tenga datos, parcela y personaje
local GREEN = Color3.fromRGB(90, 225, 120)

local joined: { [Player]: number } = {}
local leaving: { [Player]: boolean } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Lo que hacía el jugador, en una tabla que cabe en los datos del viaje.
local function capture(player: Player, hint: unknown)
	local data = { v = VERSION, click = player:GetAttribute("AutoClick") == true, farm = player:GetAttribute("AutoFarm") == true }
	local zone = player:GetAttribute("Dungeon") or 0
	if type(hint) == "table" then
		data.fight = hint.fight == true
		-- Entre dos partidas con Repetir el servidor lo ve fuera un instante: vale la zona que dice el cliente.
		if zone == 0 and type(hint.dungeon) == "number" then
			zone = hint.dungeon
		end
	end
	if zone > 0 then
		data.dungeon = zone
		data.loop = Dungeons.getLoop(player)
		return data
	end
	local root = rootOf(player)
	local plot = Plots.get(player)
	if root then
		local cframe = root.CFrame
		if plot then
			local point = plot.cframe:PointToObjectSpace(cframe.Position)
			local half = Config.Plot.Size / 2
			if math.abs(point.X) <= half and math.abs(point.Z) <= half then
				data.plot = true
				cframe = plot.cframe:ToObjectSpace(cframe)
			end
		end
		local look = cframe.LookVector
		data.at = { cframe.X, cframe.Y, cframe.Z, look.X, look.Z }
	end
	return data
end

-- El sitio apuntado, ya en el mundo de este servidor, o nil si no vale (números raros, fuera del mapa).
local function place(player: Player, data): CFrame?
	local at = data.at
	if type(at) ~= "table" then
		return nil
	end
	for index = 1, 5 do
		local value = at[index]
		if type(value) ~= "number" or value ~= value or math.abs(value) > 1e4 then
			return nil
		end
	end
	local position = Vector3.new(at[1], at[2], at[3])
	local look = Vector3.new(at[4], 0, at[5])
	local cframe = if look.Magnitude > 0.1 then CFrame.lookAt(position, position + look) else CFrame.new(position)
	if data.plot == true then
		local plot = Plots.get(player)
		local half = Config.Plot.Size / 2
		if not plot or math.abs(position.X) > half or math.abs(position.Z) > half then
			return nil
		end
		cframe = plot.cframe * cframe
	end
	local flat = Vector3.new(cframe.X, 0, cframe.Z)
	if flat.Magnitude > Config.Plot.LimitRadius or cframe.Y < -200 or cframe.Y > 400 then
		return nil
	end
	return cframe
end

local function restore(player: Player, data)
	if type(data) ~= "table" or data.v ~= VERSION then
		return
	end
	-- Hacen falta los datos (el daño decide si puede entrar en la zona), la parcela y el personaje.
	local deadline = os.clock() + READY_TIMEOUT
	while player.Parent and not (PlayerData.read(player) and Plots.get(player) and rootOf(player)) do
		if os.clock() > deadline then
			return
		end
		task.wait(0.25)
	end
	task.wait(1.5) -- que acabe de aparecer: lo que lo coloca al entrar ya ha pasado
	local character = player.Character
	if not player.Parent or not character or not rootOf(player) then
		return
	end

	local inDungeon = false
	if type(data.dungeon) == "number" then
		Dungeons.setLoop(player, data.loop == true)
		inDungeon = Party.solo(player, data.dungeon)
		if inDungeon and data.fight == true then
			player:SetAttribute("ResumeFight", true)
		end
	end
	if not inDungeon then
		local target = place(player, data)
		if target then
			character:PivotTo(target + Vector3.new(0, 1, 0))
			local root = rootOf(player)
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	if data.click == true then
		AutoPlay.set(player, "click", true)
	end
	if data.farm == true and not inDungeon then
		AutoPlay.set(player, "farm", true)
	end
	if player.Parent then
		Remotes.Notice:FireClient(player, "¡Reconectado! Sigues donde estabas", GREEN)
	end
end

-- Studio: el mismo recorrido sin viaje, para poder probarlo (se le saca de lo que hacía y a los 2 s se le devuelve).
local function simulate(player: Player, data)
	Dungeons.leave(player)
	AutoPlay.set(player, "click", false)
	AutoPlay.set(player, "farm", false)
	player:SetAttribute("ResumeFight", nil)
	local plot = Plots.get(player)
	if plot and player.Character and data.dungeon == nil then
		player.Character:PivotTo(CFrame.new(0, Config.Plot.FloorHeight + 4, 30))
	end
	task.wait(2)
	leaving[player] = nil
	restore(player, data)
end

local function travel(player: Player, data, sameServer: boolean): boolean
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(data)
	-- Con más gente en el servidor se vuelve al mismo, para no separar a nadie; solo, el servidor se cierra al salir.
	if sameServer then
		options.ServerInstanceId = game.JobId
	end
	local ok, problem = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		warn(`[Rejoin] No se pudo reconectar a {player.Name}: {problem}`)
	end
	return ok
end

local function onRequest(player: Player, hint: unknown)
	local studio = RunService:IsStudio()
	if leaving[player] or (not studio and os.clock() - (joined[player] or os.clock()) < Config.Rejoin.MinSession) then
		return
	end
	leaving[player] = true
	local data = capture(player, hint)
	if studio then
		simulate(player, data)
		return
	end
	PlayerData.save(player)
	if not player.Parent then
		return
	end
	-- De un servidor privado solo se vuelve al mismo: el viaje normal lo sacaría a uno público.
	local private = game.PrivateServerId ~= ""
	local same = private or #Players:GetPlayers() > 1
	if not travel(player, data, same) and (private or not same or not travel(player, data, false)) then
		leaving[player] = nil
	end
end

function Rejoin.start()
	Remotes.Rejoin.OnServerEvent:Connect(onRequest)
	local function onPlayer(player: Player)
		joined[player] = os.clock()
		local join = player:GetJoinData()
		-- Solo valen los datos de un viaje que salió de este mismo juego.
		if join and join.SourcePlaceId == game.PlaceId and join.TeleportData then
			task.spawn(restore, player, join.TeleportData)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		joined[player] = nil
		leaving[player] = nil
	end)
	-- El viaje no ha salido (el servidor de destino ya no está, fallo de Roblox): que pueda volver a pedirlo. El cliente
	-- insiste solo mientras siga sin tocar nada.
	TeleportService.TeleportInitFailed:Connect(function(player)
		leaving[player] = nil
	end)
end

return Rejoin
