-- Misiones diarias y semanales (ver shared/MissionList): cuenta el progreso, lo publica en el atributo
-- "Missions" del jugador (JSON) y paga la recompensa en Fichas de misión al cobrar. También construye el
-- puesto "Misiones" del hub (el mismo que las tiendas de Rasgos y Grados). El progreso se guarda en
-- PlayerData (data.missions) y se reinicia solo al cambiar el día o la semana.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MissionList = require(ReplicatedStorage.Shared.MissionList)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local ModifierShops = require(script.Parent.ModifierShops)

local Missions = {}

local PERIODS = { "daily", "weekly" }
local TOKEN = "missionToken"
local GOLD = Color3.fromRGB(255, 200, 60)

local dirty: { [Player]: boolean } = {}

-- Deja data.missions con el periodo actual (reinicia el progreso si ha cambiado el día o la semana).
local function ensure(data)
	local now = os.time()
	for _, period in PERIODS do
		local id = MissionList.periodId(period, now)
		local state = data.missions[period]
		if type(state) ~= "table" or state.id ~= id or type(state.progress) ~= "table" or type(state.claimed) ~= "table" then
			data.missions[period] = { id = id, progress = {}, claimed = {} }
		end
	end
end

local function publish(player: Player)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	ensure(data)
	local state = {}
	for _, period in PERIODS do
		local current = data.missions[period]
		state[period] = { id = current.id, progress = current.progress, claimed = current.claimed }
	end
	player:SetAttribute("Missions", HttpService:JSONEncode(state))
end

-- Suma progreso a las misiones de ese tipo que estén activas hoy o esta semana.
function Missions.add(player: Player, kind: string, amount: number?)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	ensure(data)
	for _, period in PERIODS do
		local state = data.missions[period]
		for _, mission in MissionList.pick(period, state.id) do
			if mission.kind == kind and not state.claimed[mission.id] then
				state.progress[mission.id] = math.min(mission.goal, (state.progress[mission.id] or 0) + (amount or 1))
				dirty[player] = true
			end
		end
	end
end

local function onClaim(player: Player, period: unknown, id: unknown)
	if (period ~= "daily" and period ~= "weekly") or type(id) ~= "string" then
		return
	end
	local data = PlayerData.read(player)
	if not data then
		return
	end
	ensure(data)
	local state = data.missions[period]
	for _, mission in MissionList.pick(period, state.id) do
		if mission.id == id then
			if state.claimed[id] or (state.progress[id] or 0) < mission.goal then
				return
			end
			state.claimed[id] = true
			PlayerData.edit(player, function(edited)
				edited.items[TOKEN] += mission.reward
			end)
			publish(player)
			Remotes.Notice:FireClient(player, `+{mission.reward} {Config.Items[TOKEN].name}{if mission.reward == 1 then "" else "s"}`, GOLD)
			return
		end
	end
end

function Missions.start()
	Remotes.ClaimMission.OnServerEvent:Connect(onClaim)

	-- Cuando el jugador ya tiene sus datos cargados se publican sus misiones.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			for _ = 1, 60 do
				if PlayerData.read(player) then
					publish(player)
					return
				end
				task.wait(0.5)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)

	-- Publica los cambios juntos cada medio segundo, y de paso comprueba si ha cambiado el día.
	task.spawn(function()
		local ticks = 0
		while true do
			task.wait(0.5)
			ticks += 1
			for player in dirty do
				dirty[player] = nil
				publish(player)
			end
			if ticks % 120 == 0 then
				for _, player in Players:GetPlayers() do
					publish(player)
				end
			end
		end
	end)

	-- Puesto "Misiones" en el hub, junto a las otras tiendas.
	local map = workspace:WaitForChild("Map")
	local radius = Config.Plot.HubRadius - 18
	local angle = math.rad(202.5)
	ModifierShops.buildStall(map, "missions", Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius), {
		Color3.fromRGB(255, 190, 40),
		Color3.fromRGB(60, 200, 110),
		Color3.fromRGB(245, 245, 250),
	}, "Misiones", true)
end

return Missions
