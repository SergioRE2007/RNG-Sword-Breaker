-- Carteles de las salas del lobby subterráneo. El servidor (server/DungeonLobby) pone sobre el arco de cada sala un
-- tablón con la etiqueta DungeonRoom y los atributos Index (la zona) y Waiting (cuánta gente espera); aquí se le monta
-- encima, solo para este jugador, una pantalla (SurfaceGui) con el nombre de la zona, su descripción, sus premios
-- principales, el daño recomendado (en verde si ya te llega) y si está abierta o cerrada para ti (DungeonInfo).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DungeonInfo = require(ReplicatedStorage.Shared.DungeonInfo)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)

local RoomSigns = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOOD = Color3.fromRGB(110, 230, 120)
local BAD = Color3.fromRGB(255, 110, 110)
local REFRESH = 1 -- segundos entre repasos de los carteles
local NEAR = 240 -- solo se repasan los carteles tan cerca de la cámara

local signs: { [BasePart]: () -> () } = {} -- tablón -> su repaso

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

local function chip(parent: Instance, position: UDim2, size: UDim2, color: Color3): TextLabel
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Ui.round(frame, 14)
	Ui.stroke(frame, BLACK, 4)
	Ui.panel(frame, Color3.fromRGB(34, 36, 72):Lerp(color, 0.15))
	local text = Ui.label(frame, 30)
	text.Size = UDim2.fromScale(1, 1)
	return text
end

local function build(board: BasePart)
	local index = board:GetAttribute("Index")
	local level = if type(index) == "number" then Config.Dungeons[index] else nil
	if not level or signs[board] then
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "RoomSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Parent = board

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = WHITE
	root.BorderSizePixel = 0
	root.Parent = gui
	Ui.round(root, 24)
	Ui.stroke(root, BLACK, 8)
	Ui.panel(root, Color3.fromRGB(40, 42, 84):Lerp(level.color, 0.22), level.color)

	local title = Ui.label(root, 52)
	title.Position = UDim2.fromOffset(34, 14)
	title.Size = UDim2.new(1, -68, 0, 58)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 52
	limit.MinTextSize = 24
	limit.Parent = title
	title.Text = `<font color="{hex(level.color:Lerp(WHITE, 0.3))}">{string.upper(level.name)}</font>`

	local tagline = Ui.label(root, 28)
	tagline.Position = UDim2.fromOffset(34, 72)
	tagline.Size = UDim2.new(1, -68, 0, 34)
	tagline.TextXAlignment = Enum.TextXAlignment.Left
	tagline.TextTruncate = Enum.TextTruncate.AtEnd
	tagline.Text = `<font color="{Ui.SOFT}">{level.tagline or ""}</font>`

	-- Premios principales.
	local rewards = Ui.label(root, 34)
	rewards.Position = UDim2.fromOffset(34, 112)
	rewards.Size = UDim2.new(1, -68, 0, 120)
	rewards.TextXAlignment = Enum.TextXAlignment.Left
	rewards.TextYAlignment = Enum.TextYAlignment.Top
	rewards.LineHeight = 1.1
	local lines = {}
	for _, reward in DungeonInfo.rewards(index) do
		table.insert(lines, `<font color="{hex(reward.color)}">{reward.text}</font>`)
	end
	rewards.Text = table.concat(lines, "\n")

	local recommended = chip(root, UDim2.new(0, 34, 1, -82), UDim2.new(0.5, -40, 0, 62), level.color)
	local state = chip(root, UDim2.new(0.5, 6, 1, -82), UDim2.new(0.5, -40, 0, 62), level.color)
	local waiting = Ui.label(root, 24)
	waiting.AnchorPoint = Vector2.new(1, 0)
	waiting.Position = UDim2.new(1, -34, 0, 20)
	waiting.Size = UDim2.fromOffset(200, 30)
	waiting.TextXAlignment = Enum.TextXAlignment.Right

	signs[board] = function()
		local damage = Stats.damage(player)
		local ready = damage >= DungeonInfo.recommended(index)
		recommended.Text = `<font color="{Ui.SOFT}">Daño</font> <font color="{hex(if ready then GOOD else BAD)}">{Format.short(DungeonInfo.recommended(index))}</font>`
		local lock = DungeonInfo.lock(index, damage)
		state.Text = if lock then `<font color="{hex(BAD)}">{lock}</font>` else `<font color="{hex(GOOD)}">ABIERTA</font>`
		local count = board:GetAttribute("Waiting") or 0
		waiting.Text = if count > 0 then `<font color="{Ui.SOFT}">Esperando</font> {count}` else ""
	end
	signs[board]()
end

function RoomSigns.start()
	for _, board in CollectionService:GetTagged("DungeonRoom") do
		task.spawn(build, board)
	end
	CollectionService:GetInstanceAddedSignal("DungeonRoom"):Connect(function(board)
		task.defer(build, board :: BasePart)
	end)
	CollectionService:GetInstanceRemovedSignal("DungeonRoom"):Connect(function(board)
		signs[board :: BasePart] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH)
			local camera = workspace.CurrentCamera
			if camera then
				for board, refresh in signs do
					if board.Parent and (board.Position - camera.CFrame.Position).Magnitude < NEAR then
						refresh()
					end
				end
			end
		end
	end)
end

return RoomSigns
