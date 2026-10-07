-- Pociones, lado del cliente: la tira de pociones activas del HUD (abajo a la izquierda, a la derecha de monedas y
-- gemas) y el icono y el cartel que comparten con la mochila (Backpack). El estado sale de los atributos del Player que
-- publica server/Potions: "Potion_<familia>" = tier y "PotionEnd_<familia>" = hora del servidor a la que acaba
-- (workspace:GetServerTimeNow). Los relojes los pone al día un solo bucle (Heartbeat) que solo trabaja mientras haya
-- alguna poción activa. El cliente solo enseña: lo que hace cada poción lo decide el servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Ui = require(script.Parent.Ui)
local Performance = require(script.Parent.Performance)

local Potions = {}

local player = Players.LocalPlayer
local cfg = Config.Potions

local TILE_W, TILE_H = 62, 74 -- casilla de la tira, en píxeles del HUD (que ya se escala solo en pantallas pequeñas)
local GAP = 8
local LOW_COLOR = Color3.fromRGB(255, 110, 100)

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Parte un texto en líneas de como mucho `width` letras (los carteles no se ajustan solos).
local function wrap(text: string, width: number): string
	local lines, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		if line ~= "" and (utf8.len(line) or #line) + 1 + (utf8.len(word) or #word) > width then
			table.insert(lines, line)
			line = word
		else
			line = if line == "" then word else line .. " " .. word
		end
	end
	if line ~= "" then
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

-- Icono de la poción de esa familia (frasco del color de la familia con su símbolo).
function Potions.icon(parent: Instance, family: string)
	local info = cfg.Families[family]
	Ui.potionIcon(parent, info.color, info.glyph)
end

-- Texto corto del tier para la etiqueta de una casilla: I a VI, y EXC / DIV para Exclusiva y Divina.
function Potions.tag(tier: number): string
	return if tier <= 6 then PotionInfo.tierName(tier) else string.upper(string.sub(PotionInfo.tierName(tier), 1, 3))
end

-- Pone la etiqueta del tier en una casilla (más ancha si el texto lo pide; `large` para las casillas grandes de la mochila).
function Potions.addTag(cell: Instance, tier: number, large: boolean?)
	local text = Potions.tag(tier)
	local tag = Ui.cellTag(cell, text, PotionInfo.color(tier))
	-- A caballo de la esquina, para no tapar el frasco.
	if large then
		tag.TextSize = 17
		tag.Position = UDim2.fromOffset(-6, -8)
		tag.Size = UDim2.fromOffset(math.max(28, 10 + 10 * #text), 24)
	else
		tag.TextSize = 12
		tag.Position = UDim2.fromOffset(-5, -7)
		tag.Size = UDim2.fromOffset(math.max(20, 8 + 7 * #text), 18)
	end
	return tag
end

-- Cartel de una poción: nombre y tier, qué hace, cuánto dura y, si se pasan, cuántas se tienen y cuánto le queda a la
-- activa. Devuelve el texto y el color del borde.
function Potions.tip(family: string, tier: number, count: number?, remaining: number?): (string, Color3)
	local info = cfg.Families[family]
	local color = PotionInfo.color(tier)
	local lines = {
		`{info.name} <font color="{hex(color)}">{PotionInfo.tierName(tier)}</font>`,
		`<font color="{Ui.SOFT}">{wrap(info.desc, 42)}</font>`,
		`Efecto: <font color="{hex(info.color:Lerp(Color3.new(1, 1, 1), 0.3))}">{PotionInfo.effect(family, tier)}</font>`,
		`Dura {PotionInfo.minutes(PotionInfo.duration(tier))} de juego <font color="{Ui.SOFT}">(hasta {PotionInfo.minutes(PotionInfo.cap(tier))} sumando)</font>`,
	}
	if count then
		table.insert(lines, `Tienes: x{Format.short(count)}`)
	end
	if remaining then
		table.insert(lines, `Quedan: <font color="{hex(color)}">{PotionInfo.clock(remaining)}</font>`)
	end
	return table.concat(lines, "\n"), color
end

function Potions.start()
	local gui = Ui.hud()

	-- A la derecha del bloque de monedas y gemas (se mide de su cuadro, no de un número): pegada al borde de abajo.
	local coins = gui:FindFirstChild("Coins") :: GuiObject?
	local left = if coins then coins.Position.X.Offset + coins.Size.X.Offset + 14 else 298
	local strip = Instance.new("Frame")
	strip.Name = "Potions"
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.new(0, left, 1, -14)
	-- Ancho: lo que queda entre las monedas y el cuadro de estadísticas (300 de ancho, pegado al borde derecho; en móvil
	-- empieza plegado y solo asoma su pestaña). Si no caben las seis (pantalla estrecha), las casillas pasan a una
	-- segunda fila en vez de salirse de la pantalla.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	strip.Size = UDim2.new(1, -(left + (if touchOnly then 74 else 324)), 0, TILE_H + 6)
	strip.AutomaticSize = Enum.AutomaticSize.Y
	strip.BackgroundTransparency = 1
	strip.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Wraps = true
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	-- [familia] = { cell, tier, endsAt, text (reloj), pulse (UIScale del latido), shown (segundos que enseña) }
	local tiles = {}
	local active = 0

	local function remaining(tile): number
		return math.max(0, tile.endsAt - workspace:GetServerTimeNow())
	end

	local function build(family: string, tier: number, endsAt: number)
		local info = cfg.Families[family]
		local cell = Ui.cell(strip, PotionInfo.color(tier), tier)
		cell.Name = "Potion_" .. family
		cell.LayoutOrder = table.find(cfg.Order, family) :: number
		cell.Size = UDim2.fromOffset(TILE_W, TILE_H)
		-- El frasco, cuadrado, arriba; el reloj va debajo (Ui.cellLabel) y la etiqueta del tier en la esquina.
		local iconBox = Instance.new("Frame")
		iconBox.Name = "IconBox"
		iconBox.AnchorPoint = Vector2.new(0.5, 0)
		iconBox.Position = UDim2.new(0.5, 0, 0, 5)
		iconBox.Size = UDim2.fromOffset(TILE_W - 14, TILE_W - 14)
		iconBox.BackgroundTransparency = 1
		iconBox.Parent = cell
		Potions.icon(iconBox, family)
		Potions.addTag(cell, tier)
		local text = Ui.cellLabel(cell, "")
		local pulse = Instance.new("UIScale")
		pulse.Name = "PotionPulse"
		pulse.Parent = cell
		local tile = { cell = cell, tier = tier, endsAt = endsAt, text = text, pulse = pulse, shown = -1 }
		Ui.tip(cell, function()
			return Potions.tip(family, tile.tier, nil, remaining(tile)), PotionInfo.color(tile.tier), true
		end, true)
		-- Entra con rebote (con el modo rendimiento, sin animaciones, de golpe).
		local press = cell:FindFirstChild("PressScale") :: UIScale?
		if press and not Performance.get() then
			press.Scale = 0.3
			TweenService:Create(press, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		return tile
	end

	-- Pone el reloj de una casilla: MM:SS o H:MM:SS, y rojo y latiendo cuando queda poco.
	local function paint(tile, now: number)
		local left = math.max(0, tile.endsAt - now)
		local whole = math.ceil(left)
		if whole ~= tile.shown then
			tile.shown = whole
			tile.text.Text = PotionInfo.clock(left)
		end
		if left <= cfg.LowTime then
			tile.text.TextColor3 = LOW_COLOR
			tile.pulse.Scale = if Performance.get() then 1 else 1 + 0.05 * (0.5 + 0.5 * math.sin(now * 6))
		else
			tile.text.TextColor3 = Color3.new(1, 1, 1)
			tile.pulse.Scale = 1
		end
	end

	-- Deja la casilla de esa familia como dicen los atributos del jugador: la crea, la rehace si cambió de tier, la
	-- actualiza si le sumaron tiempo o la quita si ya no hay poción.
	local function sync(family: string)
		local tier = player:GetAttribute("Potion_" .. family)
		local endsAt = player:GetAttribute("PotionEnd_" .. family)
		local tile = tiles[family]
		if type(tier) ~= "number" or type(endsAt) ~= "number" or not cfg.Families[family].values[tier] then
			if tile then
				tile.cell:Destroy()
				tiles[family] = nil
				active -= 1
			end
			return
		end
		if tile and tile.tier ~= tier then
			tile.cell:Destroy()
			tiles[family] = nil
			active -= 1
			tile = nil
		end
		if not tile then
			tile = build(family, tier, endsAt)
			tiles[family] = tile
			active += 1
		elseif endsAt > tile.endsAt + 1 and not Performance.get() then
			-- Le han sumado tiempo: un pequeño salto.
			local press = tile.cell:FindFirstChild("PressScale") :: UIScale?
			if press then
				press.Scale = 1.25
				TweenService:Create(press, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end
		tile.endsAt = endsAt
		paint(tile, workspace:GetServerTimeNow())
	end

	player.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 6) ~= "Potion" then
			return
		end
		local family = string.match(name, "^PotionEnd_(.+)$") or string.match(name, "^Potion_(.+)$")
		if family and cfg.Families[family] then
			sync(family)
		end
	end)
	for family in cfg.Families do
		sync(family)
	end

	-- Un solo bucle para todos los relojes, diez veces por segundo y solo con pociones activas.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if active == 0 then
			return
		end
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local now = workspace:GetServerTimeNow()
		for _, tile in tiles do
			paint(tile, now)
		end
	end)
end

return Potions
