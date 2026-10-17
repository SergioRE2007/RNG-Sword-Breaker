-- Casilla de un arma (librería sin start()), pedida por el usuario: la misma en todos los menús (mochila, bolsa,
-- comercio, Rasgos y Grados, fusión, venta, subir nivel...). Lleva la vista 3D, el daño abajo, el nivel arriba en el
-- centro, la "E" de equipada (o la "B" de la Bolsa de oro), el candado, el metal y el tamaño a la izquierda, el logo
-- del rasgo arriba a la derecha y el grado abajo a la derecha, y el cartel al pasar el ratón.
--   WeaponCell.create(padre, copia, opciones?) -> casilla nueva (Ui.cell)
--   WeaponCell.fill(casilla, copia, opciones?)  -> pinta un arma en una casilla que ya existe (borra la de antes)
--   WeaponCell.clear(casilla)                   -> quita lo que puso fill
--   WeaponCell.key(copia, opciones?)           -> texto con todo lo que enseña la casilla: si cambia, hay que rehacerla
--   WeaponCell.tip(copia)                       -> el cartel (también lo usan los menús con casillas propias)
-- Opciones: `owner` (de quién es la copia, para la "E" y la "B"; LocalPlayer si falta, false = sin marcas),
-- `value` y `valueColor` (otro número abajo en vez del daño: la bolsa enseña monedas por golpe), `tip` (otro cartel,
-- function(copia) con lo mismo que devuelve WeaponCell.tip; false = sin cartel).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Lang = require(ReplicatedStorage.Shared.Lang)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Permanent = require(ReplicatedStorage.Shared.Permanent)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)
local WeaponPreview = require(script.Parent.WeaponPreview)

local WeaponCell = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local LEVEL_TEXT = Color3.fromRGB(255, 214, 92)
local LEVEL_RIM = Color3.fromRGB(170, 90, 255)
-- Lo que pone fill en la casilla (para quitarlo al pintar otra arma en la misma).
local PARTS = { "Glow", "Preview", "Marks" }

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Nombre de un rasgo o grado con letras animadas, como en las tiendas: el arcoíris corre por las letras y los demás
-- llevan un destello blanco que las cruza. Hay que volver a pedirlo cada fotograma (el cartel lo hace solo si tip
-- devuelve `true` como tercer valor).
local function animatedName(entry): string
	local now = os.clock()
	local name = Lang.t(nil, entry.name)
	local shine = (now * 7) % ((utf8.len(name) or #name) + 10) - 5
	local letters = {}
	local index = 0
	for _, code in utf8.codes(name) do
		index += 1
		local color
		if entry.tones then
			color = Modifiers.toneAt(entry, now * 4 + index * 0.9)
		elseif entry.rainbow then
			color = Color3.fromHSV((now * 0.6 + index * 0.09) % 1, 0.6, 1)
		else
			color = entry.color:Lerp(WHITE, math.max(0, 1 - math.abs(index - shine) / 2.5) * 0.85)
		end
		table.insert(letters, `<font color="{hex(color)}">{utf8.char(code)}</font>`)
	end
	return table.concat(letters)
end

local TIP_TITLE = 28 -- tamaño del nombre en el cartel (el resto va a 21, el de Ui.tip)
local TIP_ODDS = 16 -- y el de la probabilidad
local TIP_FAINT = "#868b9c" -- gris tenue de la probabilidad
local TIP_VALUE = 25 -- tamaño del número de daño
local TIP_DAMAGE = "#ff7d5e" -- la palabra "Daño"
local TIP_GOLD = "#ffd65c" -- y su número
-- Separador entre las partes del cartel (pedido por el usuario, con una captura de otro juego de referencia): una
-- línea fina y tenue hecha de texto, porque el cartel es un solo TextLabel.
local TIP_SEPARATOR = `<font size="11" color="#4c5370">━━━━━━━━━━━━━━━━━━━━</font>`

-- Cartel de una copia (nombre, rareza, metal y tamaño, nivel, rasgo, grado, daño, probabilidad).
function WeaponCell.tip(copy): (string, Color3, boolean, any)
	local sword = Config.Swords[copy.sword]
	local trait = Config.Traits[copy.trait]
	local rarity = Stats.rarity(copy)
	local tier = Rarity.tier(rarity)
	-- Pedido por el usuario: el nombre más grande que el resto y con la animación de su rareza, y la probabilidad más
	-- pequeña y en gris tenue. Sin el tipo de arma: debajo del nombre, solo la rareza.
	local lines = { `<font size="{TIP_TITLE}">{Ui.rarityText(Lang.t(nil, sword.name), tier.color, table.find(Config.RarityTiers, tier))}</font>`, `<font color="{hex(tier.color)}">{Lang.t(nil, tier.name)}</font>` }
	local icon = nil -- logo del rasgo, al principio de su línea (Ui.tip)
	local grade = Config.Grades[copy.grade]
	local border = tier.color
	-- Metal y tamaño (permanentes, salen con el arma): solo el nombre, en una línea. Pedido por el usuario: el cartel
	-- es para niños, sin lo que multiplica cada uno ni su probabilidad por separado.
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	local extras = {}
	if metal then
		table.insert(extras, `<font color="{hex(metal.color)}">{Lang.t(nil, metal.name)}</font>`)
	end
	if size then
		table.insert(extras, `<font color="{hex(size.color)}">{Lang.t(nil, size.name)}</font>`)
	end
	if #extras > 0 then
		table.insert(lines, table.concat(extras, " · "))
	end
	if (copy.level or 0) > 0 then
		table.insert(lines, `<font color="{TIP_GOLD}">{Lang.t(nil, "Level {n}", { n = copy.level })}</font>`)
	end
	if trait or grade then
		table.insert(lines, TIP_SEPARATOR)
	end
	if trait then
		-- Su logo y su nombre, sin "Rasgo:" ni lo que da (pedido por el usuario: el cartel queda más limpio).
		local logo = Ui.traitLogo(trait)
		table.insert(lines, (if logo then Ui.TIP_ICON_GAP else "") .. animatedName(trait))
		icon = if logo then { image = logo, line = #lines } else nil
		if trait.rainbow then
			border = if trait.tones then Modifiers.toneAt(trait, os.clock() * 3) else Color3.fromHSV(os.clock() * 0.5 % 1, 0.55, 1)
		end
	end
	if grade then
		table.insert(lines, `<font color="{hex(grade.color)}">{Lang.t(nil, "Grade:")}</font> {animatedName(grade)}`)
		if grade.rainbow then
			border = if grade.tones then Modifiers.toneAt(grade, os.clock() * 3) else Color3.fromHSV(os.clock() * 0.5 % 1, 0.55, 1)
		end
	end
	if copy.locked then
		table.insert(lines, `<font color="{hex(Ui.COLORS.coins)}">{Lang.t(nil, "Locked")}</font>`)
	end
	-- El daño destaca (pedido por el usuario: no tan plano): la palabra en rojo cálido y el número más grande en dorado.
	table.insert(lines, TIP_SEPARATOR)
	table.insert(lines, `<font color="{TIP_DAMAGE}">{Lang.t(nil, "Damage")}</font> <font size="{TIP_VALUE}" color="{TIP_GOLD}">{Format.multiplier(Stats.swordDamage(copy))}</font>`)
	table.insert(lines, TIP_SEPARATOR)
	if not sword.rarity then
		table.insert(lines, `<font size="{TIP_ODDS}" color="{TIP_FAINT}">{Lang.t(nil, "Starter sword")}</font>`)
	else
		-- Una sola probabilidad: la del arma entera, con su metal y su tamaño.
		table.insert(lines, `<font size="{TIP_ODDS}" color="{TIP_FAINT}">{Lang.t(nil, "1 in {n}", { n = Format.short(rarity) })}</font>`)
	end
	return table.concat(lines, "\n"), border, true, icon -- animado: el nombre lleva el brillo de su rareza
end

-- "E" (equipada), "B" (en la Bolsa de oro) o nada.
local function slotMark(copy, options): string?
	local owner = if options and options.owner ~= nil then options.owner else Players.LocalPlayer
	if not owner then
		return nil
	end
	if Stats.isEquipped(owner, copy.id) then
		return "E"
	elseif Stats.isDeposited(owner, copy.id) then
		return "B"
	end
	return nil
end

function WeaponCell.key(copy, options: any?): string
	return `{copy.id}:{copy.sword}:{copy.trait or 0}:{copy.grade or 0}:{copy.metal or 0}:{copy.size or 0}:{copy.level or 0}:{copy.locked}:{slotMark(copy, options)}:{options and options.value}`
end

local function tag(parent: Instance, text: string, color: Color3, position: UDim2): TextLabel
	local label = Ui.cellTag(parent, text, color)
	label.Position = position
	label.ZIndex = 4
	return label
end

-- Quita de una casilla el arma que pintó fill.
function WeaponCell.clear(cell: GuiObject)
	for _, name in PARTS do
		local old = cell:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

function WeaponCell.fill(cell: GuiObject, copy, options: any?)
	WeaponCell.clear(cell)
	local tier = Rarity.tier(Stats.rarity(copy))
	WeaponPreview.attach(cell, copy.sword, tier.color, copy.metal)
	local marks = Instance.new("Frame")
	marks.Name = "Marks"
	marks.Size = UDim2.fromScale(1, 1)
	marks.BackgroundTransparency = 1
	marks.ZIndex = 3
	marks.Parent = cell

	-- Número grande abajo a la izquierda: el daño (o lo que pida el menú).
	local value = Ui.cellLabel(marks, if options and options.value then options.value else Format.multiplier(Stats.swordDamage(copy)))
	value.Name = "Value"
	value.Position = UDim2.new(0.5, 3, 1, -3)
	value.Size = UDim2.new(1, -10, 0, 26)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.ZIndex = 4
	value:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 23
	value:FindFirstChildOfClass("UIStroke").Thickness = 2.5
	Ui.gradient(value, WHITE, if options and options.valueColor then options.valueColor else tier.color:Lerp(WHITE, 0.45), 90)

	-- Columna de la izquierda, de arriba abajo: "E"/"B", metal y tamaño. El candado, a la derecha de la "E".
	local mark = slotMark(copy, options)
	local top = 4
	if mark then
		tag(marks, mark, if mark == "E" then Ui.COLORS.green else Ui.COLORS.coins, UDim2.fromOffset(4, 4)).Name = "Slot"
		top = 30
	end
	if copy.locked then
		local badge = Instance.new("Frame")
		badge.Name = "Locked"
		badge.Position = UDim2.fromOffset(if mark then 28 else 4, 4)
		badge.Size = UDim2.fromOffset(22, 22)
		badge.BackgroundColor3 = Ui.COLORS.dark
		badge.BorderSizePixel = 0
		badge.Parent = marks
		Ui.round(badge, 6)
		Ui.stroke(badge, BLACK, 2)
		Ui.lockIcon(badge, Ui.COLORS.coins)
		Ui.layer(badge, 4)
		if not mark then
			top = 30
		end
	end
	local metal, size = Permanent.metal(copy), Permanent.size(copy)
	if metal then
		local dot = Instance.new("Frame")
		dot.Name = "Metal"
		dot.Position = UDim2.fromOffset(6, top)
		dot.Size = UDim2.fromOffset(18, 18)
		dot.BackgroundColor3 = metal.color
		dot.BorderSizePixel = 0
		dot.ZIndex = 4
		dot.Parent = marks
		Ui.round(dot, 9)
		Ui.stroke(dot, BLACK, 2)
		top += 22
	end
	if size then
		tag(marks, string.sub(Lang.t(nil, size.name), 1, 1), size.color, UDim2.fromOffset(4, top)).Name = "Size"
	end

	-- Nivel (Config.WeaponLevel) arriba en el centro; con "E", "B" o candado, un poco a la derecha para no pisarlos en
	-- las casillas pequeñas.
	if (copy.level or 0) > 0 then
		local level = Ui.label(marks, 13)
		level.Name = "Level"
		level.AnchorPoint = Vector2.new(0.5, 0)
		level.Position = UDim2.new(0.5, if mark or copy.locked then 8 else 0, 0, 4)
		level.Size = UDim2.fromOffset(40, 18)
		level.BackgroundTransparency = 0
		level.BackgroundColor3 = Ui.COLORS.dark
		level.TextColor3 = LEVEL_TEXT
		level.Text = Lang.t(nil, "Lv {n}", { n = copy.level })
		level.ZIndex = 4
		Ui.round(level, 6)
		Ui.stroke(level, LEVEL_RIM, 2)
	end

	-- Rasgo arriba a la derecha (su logo) y grado abajo a la derecha (su nombre en su color), pedido por el usuario.
	local trait = Config.Traits[copy.trait]
	local logo = trait and Ui.traitLogo(trait)
	if logo then
		local holder = Instance.new("Frame")
		holder.Name = "Trait"
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(1, -2, 0, 2)
		holder.Size = UDim2.fromOffset(36, 36)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 4
		holder.Parent = marks
		Ui.image(holder, logo).ZIndex = 4
	end
	local grade = Config.Grades[copy.grade]
	if grade then
		local label = Ui.label(marks, 16)
		label.Name = "Grade"
		label.AnchorPoint = Vector2.new(1, 1)
		label.Position = UDim2.new(1, -5, 1, -5)
		label.Size = UDim2.fromOffset(math.max(24, 8 + 10 * (utf8.len(grade.name) or 1)), 22)
		label.BackgroundTransparency = 0
		label.BackgroundColor3 = Ui.COLORS.dark
		label.TextColor3 = grade.color
		label.Text = Lang.t(nil, grade.name)
		label.ZIndex = 4
		Ui.round(label, 6)
		Ui.stroke(label, grade.color, 2)
	end
end

function WeaponCell.create(parent: Instance, copy, options: any?): TextButton
	local tier = Rarity.tier(Stats.rarity(copy))
	local cell = Ui.cell(parent, tier.color, table.find(Config.RarityTiers, tier))
	WeaponCell.fill(cell, copy, options)
	local tip = if options and options.tip ~= nil then options.tip else WeaponCell.tip
	if tip then
		Ui.tip(cell, function()
			return tip(copy)
		end, true)
	end
	return cell
end

return WeaponCell
