-- Recompensas diarias (Config.DailyRewards, shared/DailyInfo): cuenta el tiempo de juego de cada día (un bucle de 1 s,
-- solo con los datos cargados), lo publica en el atributo "Daily" (JSON) y entrega los premios al recogerlos con
-- ClaimDaily: ("playtime", posición) los de tiempo jugado y ("streak") la casilla de la semana. Lo que da va atado a la
-- cuenta (PlayerData.giveBound), como lo de los códigos.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DailyInfo = require(ReplicatedStorage.Shared.DailyInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local Tell = require(script.Parent.Tell)

local DailyRewards = {}

local GOLD = Color3.fromRGB(255, 200, 60)
local PUBLISH_EVERY = 15 -- segundos entre dos publicaciones del tiempo (el cliente lo adelanta solo entre medias)
local COOLDOWN = 0.4 -- segundos mínimos entre dos peticiones de un jugador

local lastPublish: { [Player]: number } = {}
local lastClaim: { [Player]: number } = {}

local function publish(player: Player)
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local state = data.daily
	player:SetAttribute("Daily", HttpService:JSONEncode({
		day = state.day,
		seconds = math.floor(state.seconds),
		claimed = state.claimed,
		streak = state.streak,
		streakDay = state.streakDay,
	}))
	lastPublish[player] = os.clock()
end

local function give(player: Player, rewards)
	PlayerData.edit(player, function(edited)
		for _, reward in rewards do
			if Config.Items[reward.item] then
				PlayerData.giveBound(edited, reward.item, reward.amount or 1)
			end
		end
	end)
end

local function onClaim(player: Player, kind: unknown, position: unknown)
	local now = os.clock()
	if now - (lastClaim[player] or 0) < COOLDOWN then
		return
	end
	lastClaim[player] = now
	local data = PlayerData.read(player)
	if not data then
		return
	end
	local state = data.daily
	local today = DailyInfo.today()
	DailyInfo.roll(state, today)
	if kind == "playtime" then
		if type(position) ~= "number" or not DailyInfo.playtimeReady(state, position, state.seconds) then
			return
		end
		table.insert(state.claimed, position)
		give(player, Config.DailyRewards.Playtime[position].rewards)
	elseif kind == "streak" then
		if not DailyInfo.streakReady(state, today) then
			return
		end
		local index = state.streak
		state.streakDay = today
		state.streak = index % #Config.DailyRewards.Streak + 1
		give(player, Config.DailyRewards.Streak[index])
	else
		return
	end
	publish(player)
	Tell.notice(player, GOLD, "Reward claimed!")
end

function DailyRewards.start()
	Remotes.ClaimDaily.OnServerEvent:Connect(onClaim)
	PlayerData.onLoad(function(player)
		local data = PlayerData.read(player)
		if data then
			DailyInfo.roll(data.daily, DailyInfo.today())
			publish(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPublish[player] = nil
		lastClaim[player] = nil
	end)

	-- Tiempo de juego: suma 1 s a cada jugador con datos. Se publica cada PUBLISH_EVERY s, al cambiar el día y en
	-- cuanto un premio queda listo (para que el aviso rojo salga en el momento).
	task.spawn(function()
		while true do
			task.wait(1)
			local today = DailyInfo.today()
			for _, player in Players:GetPlayers() do
				local data = PlayerData.read(player)
				if data then
					local state = data.daily
					local changed = DailyInfo.roll(state, today)
					local before = state.seconds
					state.seconds += 1
					for _, entry in Config.DailyRewards.Playtime do
						if before < entry.minutes * 60 and state.seconds >= entry.minutes * 60 then
							changed = true
						end
					end
					if changed or os.clock() - (lastPublish[player] or 0) >= PUBLISH_EVERY then
						publish(player)
					end
				end
			end
		end
	end)
end

return DailyRewards
