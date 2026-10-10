-- Reconexión antes de la expulsión por inactividad (Config.Rejoin; el viaje y la vuelta, en server/Rejoin). Roblox
-- avisa con Player.Idled de cuánto lleva el jugador sin tocar nada (el autoclicker y los Auto no cuentan como tocar):
-- al pasar de Config.Rejoin.After sale el cartel Hud.Rejoin con una cuenta atrás y, si nadie toca nada, se pide al
-- servidor la reconexión. En una mazmorra se espera antes a que acabe la partida, para no perder sus premios.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dungeons = require(script.Parent.Dungeons)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Rejoin = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local ACCENT = Color3.fromRGB(90, 200, 255)
local LAYER = 70 -- aviso, por encima de las ventanas
local RETRY = 20 -- segundos tras pedirla sin que llegue el viaje antes de poder pedirla otra vez

local cfg = Config.Rejoin

function Rejoin.start()
	local card = Instance.new("Frame")
	card.Name = "Rejoin"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 150)
	card.Size = UDim2.fromOffset(460, 104)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = Ui.screen()
	Ui.round(card, 14)
	Ui.stroke(card, BLACK, 4)
	Ui.panel(card, Color3.fromRGB(44, 62, 108), ACCENT)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	Ui.popup(card, scale)
	local title = Ui.label(card, 24)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -32, 0, 34)
	Ui.gradient(title, WHITE, ACCENT:Lerp(WHITE, 0.45), 90)
	local detail = Ui.label(card, 17)
	detail.Name = "Detail"
	detail.Position = UDim2.fromOffset(16, 50)
	detail.Size = UDim2.new(1, -32, 0, 42)
	detail.TextWrapped = true
	detail.TextColor3 = Color3.fromRGB(205, 212, 235)
	detail.Text = "Así Roblox no te expulsa por estar quieto. Vuelves al mismo sitio y sigues igual. Toca algo para cancelar."
	Ui.layer(card, LAYER)

	local token = 0 -- cada intento tiene el suyo: tocar algo lo cambia y el intento en marcha se da por cancelado
	local busy = false
	UserInputService.InputBegan:Connect(function()
		if busy then
			token += 1
		end
	end)

	local function attempt()
		busy = true
		token += 1
		local mine = token
		local zone = player:GetAttribute("Dungeon") or 0
		Ui.open(card)
		Sfx.play("toast")
		-- En una mazmorra se espera a que acabe la partida (con Repetir, a que empiece la siguiente).
		if zone > 0 then
			title.Text = "Reconectando al acabar la partida…"
			local run = player:GetAttribute("DungeonRun")
			local limit = os.clock() + cfg.DungeonWait
			while mine == token and os.clock() < limit do
				if (player:GetAttribute("Dungeon") or 0) == 0 or player:GetAttribute("DungeonRun") ~= run then
					break
				end
				task.wait(0.2)
			end
		end
		for left = cfg.Countdown, 1, -1 do
			if mine ~= token then
				break
			end
			title.Text = `Reconectando en {left} s…`
			task.wait(1)
		end
		if mine == token then
			title.Text = "Reconectando…"
			Remotes.Rejoin:FireServer({ fight = Dungeons.autoFight(), dungeon = if zone > 0 then zone else nil })
			-- Si el viaje sale, esta partida se acaba aquí. Si no, se quita el cartel y el siguiente aviso de Roblox lo reintenta.
			local limit = os.clock() + RETRY
			while mine == token and os.clock() < limit do
				task.wait(0.5)
			end
		end
		Ui.close(card)
		busy = false
	end

	player.Idled:Connect(function(seconds: number)
		if seconds >= cfg.After and not busy then
			task.spawn(attempt)
		end
	end)
	-- Pruebas en Studio: lanza el aviso sin esperar 17 minutos.
	player:GetAttributeChangedSignal("RejoinTest"):Connect(function()
		if player:GetAttribute("RejoinTest") and not busy then
			task.spawn(attempt)
		end
	end)
end

return Rejoin
