-- Ventana de Misiones (el puesto "Misiones" del hub): tres misiones diarias y tres semanales con su
-- barra de progreso y su recompensa en Fichas de misión. El servidor cuenta el progreso y lo publica en
-- el atributo "Missions" (JSON); las misiones del día se calculan igual aquí con shared/MissionList.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local MissionList = require(ReplicatedStorage.Shared.MissionList)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Missions = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 200, 60)
local CLOSE_DISTANCE = 30 -- se cierra al alejarse del puesto

local PERIODS = {
	{ "daily", "Misiones diarias", Color3.fromRGB(80, 200, 255) },
	{ "weekly", "Misiones semanales", Color3.fromRGB(190, 120, 255) },
}

local function timeLeft(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours >= 24 then
		return `{math.floor(hours / 24)} d {hours % 24} h`
	end
	return `{hours} h {minutes} min`
end

-- Estado publicado por el servidor, o uno vacío si aún no ha llegado.
local function readState()
	local raw = player:GetAttribute("Missions")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(decoded) == "table" then decoded else nil
end

function Missions.start()
	local window, body = Ui.window("Missions", "Misiones", Vector2.new(660, 610), function(parent)
		Ui.orbIcon(parent, GOLD)
	end)

	-- Fichas que tiene el jugador, arriba a la derecha de la cabecera del cuerpo.
	local tokens = Ui.label(body, 24)
	tokens.AnchorPoint = Vector2.new(1, 0)
	tokens.Position = UDim2.new(1, -16, 0, 6)
	tokens.Size = UDim2.fromOffset(280, 34)
	tokens.TextXAlignment = Enum.TextXAlignment.Right
	local note = Ui.label(body, 16)
	note.Position = UDim2.fromOffset(16, 6)
	note.Size = UDim2.fromOffset(320, 34)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Color3.fromRGB(190, 195, 215)
	note.Text = "Las fichas servirán para comprar cosas difíciles."

	local sections = {} -- [periodo] = { header, countdown, rows = { [n] = fila } }
	local y = 46
	for _, period in PERIODS do
		local key, title, color = period[1], period[2], period[3]
		local header = Instance.new("Frame")
		header.Position = UDim2.fromOffset(12, y)
		header.Size = UDim2.new(1, -24, 0, 38)
		header.BackgroundColor3 = WHITE
		header.Parent = body
		Ui.round(header, 10)
		Ui.stroke(header, BLACK, 3)
		Ui.gradient(header, color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.45), 90)
		local name = Ui.label(header, 24)
		name.Position = UDim2.fromOffset(14, 0)
		name.Size = UDim2.new(0.5, 0, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = title
		local countdown = Ui.label(header, 18)
		countdown.AnchorPoint = Vector2.new(1, 0)
		countdown.Position = UDim2.new(1, -14, 0, 0)
		countdown.Size = UDim2.new(0.5, 0, 1, 0)
		countdown.TextXAlignment = Enum.TextXAlignment.Right
		y += 44

		local rows = {}
		for index = 1, MissionList.PER_PERIOD do
			local row = Instance.new("Frame")
			row.Position = UDim2.fromOffset(12, y)
			row.Size = UDim2.new(1, -24, 0, 66)
			row.BackgroundColor3 = WHITE
			row.Parent = body
			Ui.round(row, 10)
			Ui.stroke(row, BLACK, 3)
			Ui.gradient(row, Color3.fromRGB(70, 78, 130), Color3.fromRGB(36, 40, 76), 90)

			local text = Ui.label(row, 21)
			text.Position = UDim2.fromOffset(14, 4)
			text.Size = UDim2.new(1, -250, 0, 28)
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextTruncate = Enum.TextTruncate.AtEnd

			local track = Instance.new("Frame")
			track.Position = UDim2.fromOffset(14, 38)
			track.Size = UDim2.new(1, -262, 0, 18)
			track.BackgroundColor3 = Ui.COLORS.dark
			track.Parent = row
			Ui.round(track, 9)
			Ui.stroke(track, BLACK, 2)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(0, 1)
			fill.BackgroundColor3 = WHITE
			fill.BorderSizePixel = 0
			fill.Parent = track
			Ui.round(fill, 9)
			Ui.gradient(fill, color:Lerp(WHITE, 0.35), color:Lerp(BLACK, 0.2), 90)
			local progress = Ui.label(track, 14)
			progress.Size = UDim2.fromScale(1, 1)
			progress.ZIndex = 3

			local reward = Ui.label(row, 24)
			reward.AnchorPoint = Vector2.new(1, 0.5)
			reward.Position = UDim2.new(1, -140, 0.5, 0)
			reward.Size = UDim2.fromOffset(80, 40)
			reward.TextXAlignment = Enum.TextXAlignment.Right
			reward.TextColor3 = GOLD
			local coin = Instance.new("Frame")
			coin.AnchorPoint = Vector2.new(1, 0.5)
			coin.Position = UDim2.new(1, -96, 0.5, 0)
			coin.Size = UDim2.fromOffset(34, 34)
			coin.BackgroundTransparency = 1
			coin.Parent = row
			Ui.orbIcon(coin, GOLD)

			local claim = Ui.button(row, "Cobrar", Ui.COLORS.green)
			claim.AnchorPoint = Vector2.new(1, 0.5)
			claim.Position = UDim2.new(1, -8, 0.5, 0)
			claim.Size = UDim2.fromOffset(86, 46)
			claim.TextSize = 20

			rows[index] = { text = text, fill = fill, progress = progress, reward = reward, claim = claim, mission = nil }
			claim.Activated:Connect(function()
				local mission = rows[index].mission
				if mission then
					Remotes.ClaimMission:FireServer(key, mission.id)
				end
			end)
			y += 70
		end
		sections[key] = { countdown = countdown, rows = rows }
		y += 6
	end

	local function refresh()
		tokens.Text = `Fichas: <font color="#{GOLD:ToHex()}">{Format.short(player:GetAttribute("Item_missionToken") or 0)}</font>`
		local state = readState()
		local now = os.time()
		for _, period in PERIODS do
			local key = period[1]
			local section = sections[key]
			local id = MissionList.periodId(key, now)
			local current = state and state[key]
			-- Si el servidor aún no ha cambiado de día, el progreso que llega es del periodo anterior: se ignora.
			local valid = current ~= nil and current.id == id
			local progress = if valid then current.progress or {} else {}
			local claimed = if valid then current.claimed or {} else {}
			section.countdown.Text = `Se reinicia en {timeLeft(MissionList.secondsLeft(key, now))}`
			for index, mission in MissionList.pick(key, id) do
				local row = section.rows[index]
				row.mission = mission
				local done = math.min(progress[mission.id] or 0, mission.goal)
				row.text.Text = mission.text
				row.reward.Text = `+{mission.reward}`
				row.fill.Size = UDim2.fromScale(done / mission.goal, 1)
				row.progress.Text = `{Format.short(math.floor(done))} / {Format.short(mission.goal)}`
				local isClaimed = claimed[mission.id] == true
				local ready = not isClaimed and done >= mission.goal
				row.claim.Text = if isClaimed then "Cobrada" else "Cobrar"
				row.claim.BackgroundColor3 = if ready then Ui.COLORS.green else Ui.COLORS.gray
			end
		end
	end

	player:GetAttributeChangedSignal("Missions"):Connect(refresh)
	player:GetAttributeChangedSignal("Item_missionToken"):Connect(function()
		Sfx.play("coin")
		refresh()
	end)
	window:GetPropertyChangedSignal("Visible"):Connect(refresh)
	task.spawn(function()
		-- La cuenta atrás se actualiza cada segundo mientras la ventana está abierta.
		while true do
			task.wait(1)
			if window.Visible then
				refresh()
			end
		end
	end)
	refresh()

	-- Abrir junto al puesto y cerrar al alejarse.
	local openAt: Vector3? = nil
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Shop") == "missions" then
			local parent = prompt.Parent
			openAt = if parent and parent:IsA("BasePart") then parent.Position else nil
			Ui.toggle("Missions")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if openAt and root and window.Visible and (root.Position - openAt).Magnitude > CLOSE_DISTANCE then
				window.Visible = false
				openAt = nil
			end
		end
	end)
end

return Missions
