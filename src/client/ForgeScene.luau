-- Escena de la forja (tienda de Grados): al acercarte al yunque la cámara se pone encima, mirando hacia
-- abajo. Si no hay arma puesta se ve una silueta transparente de espada: un clic en ella abre la lista para
-- elegir (la ventana de ModifierShops solo hace de lista y de ajustes del auto). Con el arma en el yunque
-- el ratón es un martillo 3D: cada clic pide una tirada de grado (RollGrade) y, cuando llega el resultado,
-- da el martillazo: el arma vibra, saltan chispas del color del grado y sale su nombre encima. Los grados
-- raros (menos del 1 %) dan un súper martillazo con más efectos. "Auto" repite martillazos sin parar hasta
-- que sale un grado de los marcados en los ajustes. Todo son piezas y efectos locales de este cliente; el
-- servidor solo ve las mismas peticiones de siempre (RollGrade) y el resultado llega por ModifierRolled.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Modifiers = require(ReplicatedStorage.Shared.Modifiers)
local Stats = require(ReplicatedStorage.Shared.Stats)
local SwordModel = require(ReplicatedStorage.Shared.SwordModel)
local Ui = require(script.Parent.Ui)

local ForgeScene = {}

local player = Players.LocalPlayer
local GRADES = Modifiers.KINDS.grades
local WHITE = Color3.new(1, 1, 1)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Martillo del ratón (en grados: ángulo del mango sobre el plano del yunque).
local HANDLE = 2.2 -- del puño al centro de la cabeza
local HEAD_REACH = 0.74 -- de la cara de abajo de la cabeza (de pie) a su centro
local HOVER, WIND, HIT = math.rad(48), math.rad(80), math.rad(6)
local SUPER_WIND = math.rad(104)
local SWORD_LENGTH = 4.8 -- lo que mide el arma tumbada sobre el yunque
local SUPER_BELOW = 1 -- los grados con menos de este % dan el súper martillazo

local api: any = nil
local active = false
local striking = false
local lastRequest = 0 -- cuándo se pidió la última tirada (el servidor exige un tiempo mínimo entre tiradas)
local scene: any = nil -- lo que existe mientras la escena está activa
local ui: any = nil

local function alive(): boolean
	return active and scene ~= nil
end

-- Interfaz ------------------------------------------------------------------------------

local function buildUi()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ForgeScene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1 -- por debajo del Hud: la ventana de elegir arma queda encima
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function fit()
		local size = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(size.Y / 720, 0.7, 1.25)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local hint = Ui.label(root, 30)
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 84)
	hint.Size = UDim2.fromOffset(700, 44)
	hint.TextWrapped = true
	local cost = Ui.label(root, 22)
	cost.Name = "Cost"
	cost.AnchorPoint = Vector2.new(0.5, 0)
	cost.Position = UDim2.new(0.5, 0, 0, 128)
	cost.Size = UDim2.fromOffset(700, 30)

	local exit = Ui.button(root, "Salir", Ui.COLORS.red)
	exit.Name = "Exit"
	exit.AnchorPoint = Vector2.new(1, 0)
	exit.Position = UDim2.new(1, -16, 0, 84)
	exit.Size = UDim2.fromOffset(130, 52)
	exit.TextSize = 24

	local column = Instance.new("Frame")
	column.Name = "Buttons"
	column.AnchorPoint = Vector2.new(1, 0.5)
	column.Position = UDim2.new(1, -16, 0.5, 0)
	column.Size = UDim2.fromOffset(150, 200)
	column.BackgroundTransparency = 1
	column.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = column
	local function side(name: string, text: string, color: Color3, order: number): TextButton
		local button = Ui.button(column, text, color)
		button.Name = name
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(150, 56)
		button.TextSize = 24
		return button
	end
	local weapon = side("Weapon", "Arma", Ui.COLORS.blue, 1)
	local auto = side("Auto", "Auto", Ui.COLORS.red, 2)
	local settings = side("Settings", "Ajustes", Ui.COLORS.gray, 3)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 20
	flash.Parent = gui

	local big = Ui.label(gui, 72)
	big.Name = "Big"
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, 0.3)
	big.Size = UDim2.fromOffset(900, 150)
	big.Text = ""
	big.TextTransparency = 1
	big.Visible = false
	big.ZIndex = 21
	local bigScale = Instance.new("UIScale")
	bigScale.Parent = big

	-- Cartel del grado de la espada: se coloca cada fotograma encima del yunque (fuera del UIScale).
	local gradeBox = Instance.new("Frame")
	gradeBox.Name = "Grade"
	gradeBox.AnchorPoint = Vector2.new(0.5, 0.5)
	gradeBox.Size = UDim2.fromOffset(300, 120)
	gradeBox.BackgroundTransparency = 1
	gradeBox.Parent = gui
	local gradeScale = Instance.new("UIScale")
	gradeScale.Parent = gradeBox
	local gradeLabel = Ui.label(gradeBox, 64)
	gradeLabel.Size = UDim2.fromScale(1, 0.62)
	local gradeRainbow = Instance.new("UIGradient")
	gradeRainbow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	gradeRainbow.Enabled = false
	gradeRainbow.Parent = gradeLabel
	local gradeInfo = Ui.label(gradeBox, 24)
	gradeInfo.Position = UDim2.fromScale(0, 0.62)
	gradeInfo.Size = UDim2.fromScale(1, 0.3)

	ui = { gui = gui, gradeBox = gradeBox, gradeScale = gradeScale, gradeLabel = gradeLabel, gradeRainbow = gradeRainbow, gradeInfo = gradeInfo, hint = hint, cost = cost, exit = exit, weapon = weapon, auto = auto, settings = settings, flash = flash, big = big, bigScale = bigScale }
end

local function refreshUi()
	if not ui or not api then
		return
	end
	local copy = api.selectedCopy()
	local crystals = player:GetAttribute("Item_gradeCrystal") or 0
	ui.cost.Text = `Cristales de grado: {Format.short(crystals)}  ·  {Config.GradeCost} por martillazo`
	ui.cost.TextColor3 = if api.canAfford() then WHITE else Ui.COLORS.red
	ui.auto.Text = if api.state.auto then "Parar" else "Auto"
	ui.auto.BackgroundColor3 = if api.state.auto then Ui.COLORS.orange else Ui.COLORS.red
	ui.weapon.Text = if scene and scene.placedId then "Cambiar" else "Arma"
	if not scene then
		return
	end
	if not scene.placedId then
		ui.hint.Text = "Haz clic en la silueta del yunque para elegir un arma"
	elseif api.state.auto then
		ui.hint.Text = "Martillazos automáticos… (pulsa Parar)"
	elseif not copy then
		ui.hint.Text = "Elige un arma"
	else
		ui.hint.Text = "¡Haz clic para dar un martillazo!"
	end
end

-- Piezas ----------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CastShadow = false
	item.Size = size
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function rainbow(): ColorSequence
	local keys = {}
	for index = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(index / 6 % 1, 0.75, 1)))
	end
	return ColorSequence.new(keys)
end

local function gradeColors(entry): ColorSequence
	if entry.rainbow then
		return rainbow()
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.35, entry.color),
		ColorSequenceKeypoint.new(1, entry.color:Lerp(Color3.new(0, 0, 0), 0.35)),
	})
end

-- Modelo del arma (centrado y tumbado a lo largo del yunque), listo para PivotTo.
local function swordModel(level: number, metal: number?, ghost: boolean?): (Model, Vector3)
	local model = Instance.new("Model")
	SwordModel.build(level, model, CFrame.identity, 1, true, metal)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item:RemoveTag("WeaponAura")
			item.CanCollide = false
			item.CastShadow = false
			if ghost then
				item.Color = Color3.fromRGB(120, 195, 255)
				item.Material = Enum.Material.ForceField
				item.Transparency = 0.4
			end
		elseif not item:IsA("Model") and not ghost then
			-- Luces y partículas del arma: aquí sobran (el brillo de las que brillan se queda en la pieza).
			if item:IsA("ParticleEmitter") or item:IsA("Trail") then
				item:Destroy()
			end
		elseif ghost and (item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Light")) then
			item:Destroy()
		end
	end
	local center, size = model:GetBoundingBox()
	model.WorldPivot = center
	local factor = math.clamp(SWORD_LENGTH / math.max(size.Y, 0.1), 0.4, 1.8)
	model:ScaleTo(factor)
	-- Largo (Y) del arma pasa a X del yunque; el grosor (X) queda vertical.
	return model, Vector3.new(size.Y * factor, size.X * factor, size.Z * factor)
end

-- Escena ----------------------------------------------------------------------------------

local function findForge()
	local map = workspace:FindFirstChild("Map")
	local forge = map and map:FindFirstChild("Forja")
	local anvil = forge and forge:FindFirstChild("YunqueCara")
	if forge and anvil then
		return forge, anvil :: BasePart
	end
	return nil, nil
end

-- Punto del plano del yunque (a la altura de la parte de arriba del arma) bajo el ratón.
local function mousePoint(planeY: number): Vector3?
	local camera = workspace.CurrentCamera
	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	if math.abs(ray.Direction.Y) < 1e-3 then
		return nil
	end
	local distance = (planeY - ray.Origin.Y) / ray.Direction.Y
	if distance <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * distance
end

local function poseHammer()
	local s = scene
	if not s then
		return
	end
	local back = s.rotation * Vector3.new(0, 0, 1)
	-- Puño: la cabeza, con el mango a HIT grados, queda justo encima del punto P.
	local grip = s.hammerAt + Vector3.new(0, HEAD_REACH - HANDLE * math.sin(HIT), 0) - back * (HANDLE * math.cos(HIT))
	local base = CFrame.new(grip) * s.rotation * CFrame.Angles(math.rad(90) - s.phi, 0, 0)
	for item, relative in s.hammerParts do
		item.CFrame = base * relative
	end
end

local function buildHammer(folder: Instance): { [Part]: CFrame }
	local parts = {}
	local function add(item: Part, relative: CFrame)
		parts[item] = relative
	end
	add(part(folder, "Mango", Vector3.new(0.3, HANDLE, 0.3), Color3.fromRGB(125, 84, 50), Enum.Material.Wood), CFrame.new(0, HANDLE / 2, 0))
	add(part(folder, "Cabeza", Vector3.new(0.8, 0.8, 1.4), Color3.fromRGB(96, 98, 110), Enum.Material.Metal), CFrame.new(0, HANDLE, 0))
	for _, z in { -0.5, 0.5 } do
		add(part(folder, "Aro", Vector3.new(0.88, 0.88, 0.18), Color3.fromRGB(58, 60, 70), Enum.Material.Metal), CFrame.new(0, HANDLE, z))
	end
	add(part(folder, "Puño", Vector3.new(0.36, 0.36, 0.36), Color3.fromRGB(62, 40, 26), Enum.Material.Wood), CFrame.new(0, 0, 0))
	return parts
end

local function setHammerLook(color: Color3?)
	if not scene then
		return
	end
	local head = scene.hammerHead
	if color then
		head.Color = color
		head.Material = Enum.Material.Neon
	else
		head.Color = Color3.fromRGB(96, 98, 110)
		head.Material = Enum.Material.Metal
	end
end

local function showHammer(visible: boolean)
	if not scene then
		return
	end
	for item in scene.hammerParts do
		item.Transparency = if visible then 0 else 1
	end
end

-- Cartel con el grado de la espada, encima del yunque.
local function setGradeLabel(index: number?, pop: boolean?)
	if not ui then
		return
	end
	local entry = if index then GRADES.list[index] else nil
	ui.gradeLabel.Text = if entry then entry.name else "Sin grado"
	ui.gradeLabel.TextColor3 = if entry and not entry.rainbow then entry.color elseif entry then WHITE else Color3.fromRGB(190, 195, 205)
	ui.gradeInfo.Text = if entry then Modifiers.effect(entry) else ""
	ui.gradeRainbow.Enabled = entry ~= nil and entry.rainbow == true
	if entry and entry.rainbow then
		ui.gradeRainbow.Color = rainbow()
	end
	if pop then
		ui.gradeScale.Scale = 1.7
		TweenService:Create(ui.gradeScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function currentGradeIndex(): number?
	local copy = api and api.selectedCopy()
	return copy and copy[GRADES.field]
end

-- Pone (o cambia) el arma del yunque, o la silueta si no hay ninguna.
local function placeSword(drop: boolean, empty: boolean?)
	local s = scene
	if not s then
		return
	end
	local copy = if empty then nil else api.selectedCopy()
	local wanted = if copy then copy.id else nil
	if s.sword then
		s.sword:Destroy()
		s.sword = nil
	end
	s.placedId = wanted
	if not copy then
		s.ghost.Parent = s.folder
		s.hitbox.Parent = s.folder
		showHammer(false)
		setGradeLabel(nil)
		refreshUi()
		return
	end
	s.ghost.Parent = nil
	s.hitbox.Parent = nil
	local model, size = swordModel(copy.sword, copy.metal, false)
	model.Parent = s.folder
	s.sword = model
	s.swordSize = size
	-- Tumbada: el largo a lo largo del yunque (X) y el grosor hacia arriba (Y).
	s.swordRest = s.anvil.CFrame * CFrame.new(0.25, s.anvil.Size.Y / 2 + size.Y / 2 + 0.03, 0) * CFrame.Angles(0, 0, -math.pi / 2)
	s.planeY = (s.swordRest * Vector3.zero).Y + size.Y / 2
	s.swordOffset = CFrame.identity
	if drop then
		s.drop = os.clock()
	else
		s.drop = nil
	end
	model:PivotTo(s.swordRest)
	showHammer(true)
	setGradeLabel(copy[GRADES.field])
	refreshUi()
end

-- Vibración del arma tras el golpe.
local function vibrate(amount: number)
	if scene then
		scene.vibe = { start = os.clock(), amount = amount }
	end
end

local function shake(amount: number)
	if scene then
		scene.shake = math.max(scene.shake or 0, amount)
	end
end

-- Chispas y destellos del golpe en el punto `at`, del color del grado.
local function burst(entry, index: number, super: boolean, at: Vector3)
	local s = scene
	if not s then
		return
	end
	local holder = s.sparkHolder
	holder.Position = at
	local count = 14 + index * 5
	if super then
		count = count * 3
	end
	local sparks = s.sparks
	sparks.Color = gradeColors(entry)
	sparks.Speed = NumberRange.new(10 + index, 20 + index * 1.5 + (if super then 14 else 0))
	sparks:Emit(count)
	local embers = s.embers
	embers.Color = gradeColors(entry)
	embers:Emit(math.floor(count / 2))
	-- Luz del golpe.
	local light = s.hitLight
	light.Color = if entry.rainbow then Color3.fromRGB(255, 220, 255) else entry.color
	light.Range = if super then 36 else 18
	light.Brightness = if super then 9 else 4
	TweenService:Create(light, TweenInfo.new(if super then 0.7 else 0.3), { Brightness = 0 }):Play()
	-- Onda en el yunque.
	local ring = part(s.folder, "Onda", Vector3.new(0.16, 0.6, 0.6), if entry.rainbow then WHITE else entry.color, Enum.Material.Neon)
	ring.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.15
	local reach = if super then 18 else 6 + index * 0.5
	local tween = TweenService:Create(ring, TweenInfo.new(if super then 0.65 else 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.16, reach, reach), Transparency = 1 })
	tween.Completed:Once(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function pulseFlash(color: Color3, strength: number, duration: number)
	if not ui then
		return
	end
	ui.flash.BackgroundColor3 = color
	ui.flash.BackgroundTransparency = 1 - strength
	TweenService:Create(ui.flash, TweenInfo.new(duration), { BackgroundTransparency = 1 }):Play()
end

local function bigText(text: string, color: Color3)
	if not ui then
		return
	end
	ui.big.Text = text
	ui.big.TextColor3 = color
	ui.big.TextTransparency = 0
	ui.big.Visible = true
	ui.bigScale.Scale = 0.3
	TweenService:Create(ui.bigScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.4, function()
		if ui then
			local fade = TweenService:Create(ui.big, TweenInfo.new(0.5), { TextTransparency = 1 })
			fade.Completed:Once(function()
				ui.big.Visible = false
			end)
			fade:Play()
		end
	end)
end

-- Anima scene.phi del ángulo `from` al `to` en `time` segundos.
local function swing(from: number, to: number, time: number, ease: ((number) -> number)?)
	local start = os.clock()
	while alive() do
		local alpha = math.clamp((os.clock() - start) / math.max(time, 1e-3), 0, 1)
		scene.phi = from + (to - from) * (if ease then ease(alpha) else alpha)
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function easeIn(alpha: number): number
	return alpha * alpha
end

local function easeOut(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

-- Un martillazo entero: pide la tirada, levanta el martillo, espera el resultado y golpea.
-- Devuelve false si no se pudo (sin cristales, sin arma, el servidor no contestó).
local function strike(auto: boolean): boolean
	local s = scene
	if not s or striking or not s.sword then
		return false
	end
	if not api.canAfford() then
		Ui.toast("No te quedan Cristales de grado", Ui.COLORS.red)
		return false
	end
	striking = true
	local state = api.state
	s.resultReady = false
	s.resultIndex = nil
	-- Dónde cae: en el punto del arma más cercano al ratón (a lo largo del filo).
	local target = mousePoint(s.planeY)
	local local_ = s.anvil.CFrame:PointToObjectSpace(target or s.swordRest.Position)
	local half = s.swordSize.X / 2 * 0.8
	local hitX = if auto then s.randomX else math.clamp(local_.X, 0.25 - half, 0.25 + half)
	s.hitAt = (s.anvil.CFrame * CFrame.new(hitX, s.anvil.Size.Y / 2, 0)).Position + Vector3.new(0, s.swordSize.Y, 0)
	s.hammerAt = s.hitAt
	s.hammerFixed = true

	-- El servidor descarta las tiradas que llegan antes de su tiempo mínimo: se espera ese margen.
	local gap = Config.ModifierCooldown / math.max(api.speed(), 1) * 1.3 - (os.clock() - lastRequest)
	if gap > 0 then
		task.wait(gap)
	end
	lastRequest = os.clock()
	if not alive() or not api.request() then
		striking = false
		s.hammerFixed = false
		return false
	end
	local fast = (if auto then 0.55 else 1) / math.max(api.speed(), 1)
	swing(s.phi, WIND, 0.11 * fast, easeOut)
	-- El resultado suele llegar enseguida; si tarda, el martillo espera arriba temblando.
	local waited = os.clock()
	while alive() and not s.resultReady and os.clock() - waited < 1.6 do
		s.phi = WIND + math.sin(os.clock() * 40) * math.rad(1.2)
		RunService.Heartbeat:Wait()
	end
	if not alive() then
		striking = false
		return false
	end
	if not s.resultReady then
		swing(s.phi, HOVER, 0.2, easeOut)
		s.hammerFixed = false
		striking = false
		return false
	end

	local index = s.resultIndex :: number
	local entry = GRADES.list[index]
	local super = Modifiers.percent("grades", index) < SUPER_BELOW
	if super then
		-- Súper martillazo: el martillo sube muy arriba brillando del color del grado y la cámara se acerca.
		setHammerLook(if entry.rainbow then Color3.fromRGB(255, 190, 255) else entry.color)
		TweenService:Create(s.fov, TweenInfo.new(0.55, Enum.EasingStyle.Quad), { Value = 40 }):Play()
		swing(s.phi, SUPER_WIND, 0.5, easeOut)
		for step = 1, 8 do
			if not alive() then
				break
			end
			s.phi = SUPER_WIND + math.sin(step * 2) * math.rad(2)
			RunService.Heartbeat:Wait()
		end
	end
	swing(s.phi, HIT, if super then 0.05 else 0.07 * fast, easeIn)
	if not alive() then
		striking = false
		return false
	end

	-- Impacto.
	burst(entry, index, super, s.hitAt)
	vibrate(if super then 0.34 else 0.1 + index * 0.012)
	shake(if super then 0.55 else 0.03 + index * 0.006)
	setGradeLabel(index, true)
	if super then
		pulseFlash(if entry.rainbow then WHITE else entry.color:Lerp(WHITE, 0.5), 0.45, 0.4)
		bigText(`¡SÚPER MARTILLAZO!\n<font size="46">Grado {entry.name}</font>`, if entry.rainbow then Color3.fromRGB(255, 160, 255) else entry.color)
		TweenService:Create(s.fov, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 55 }):Play()
		task.wait(0.09) -- un instante de pausa en el golpe
		setHammerLook(nil)
	end
	if super or Modifiers.percent("grades", index) < 10 then
		Ui.toast(`¡Grado {entry.name}! {Modifiers.effect(entry)}`, entry.color)
	end
	swing(s.phi, math.rad(24), 0.1 * fast, easeOut)
	swing(s.phi, HOVER, 0.16 * fast, easeOut)
	if not alive() then
		striking = false
		return false
	end
	s.hammerFixed = false
	striking = false
	return state.last ~= nil
end

local function autoLoop()
	local state = api.state
	while state.auto and alive() do
		if scene.sword then
			scene.randomX = 0.25 + (math.random() - 0.5) * scene.swordSize.X * 0.5
		end
		if not strike(true) then
			break
		end
		if state.last and state.stop[state.last] then
			break
		end
	end
	state.auto = false
	refreshUi()
end

-- Entrar y salir ---------------------------------------------------------------------------

-- Quieta al personaje mientras dura la escena: las teclas de movimiento se las traga la acción.
local function setControls(enabled: boolean)
	if enabled then
		ContextActionService:UnbindAction("ForgeFreeze")
	else
		ContextActionService:BindActionAtPriority("ForgeFreeze", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space)
	end
end

local function cameraPose(anvil: BasePart, rotation: CFrame): CFrame
	local top = anvil.Position + Vector3.new(0, anvil.Size.Y / 2, 0)
	local front = rotation.LookVector
	local eye = top + Vector3.new(0, 9.5, 0) + front * 2.6
	return CFrame.lookAt(eye, top + front * -0.2)
end

-- Clics: la silueta abre la lista; el arma recibe martillazos.
local function connectInput()
	local s = scene
	if not s then
		return
	end
	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not alive() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if api.window.Visible or os.clock() - scene.enteredAt < 0.9 then
			return
		end
		if not scene.placedId then
			if scene.ghostOver or input.UserInputType == Enum.UserInputType.Touch then
				api.openPicker()
			end
			return
		end
		if not api.state.auto and not striking then
			task.spawn(function()
				local ok, problem = pcall(strike, false)
				if not ok then
					warn("ForgeScene:", problem)
					striking = false
					if scene then
						scene.hammerFixed = false
					end
				end
				refreshUi()
			end)
		end
	end))
	table.insert(s.connections, ui.exit.Activated:Connect(function()
		ForgeScene.exit()
	end))
	table.insert(s.connections, ui.weapon.Activated:Connect(function()
		if not striking and not api.state.auto then
			api.openPicker()
		end
	end))
	table.insert(s.connections, ui.settings.Activated:Connect(function()
		api.openSettings()
	end))
	table.insert(s.connections, ui.auto.Activated:Connect(function()
		local state = api.state
		if state.auto then
			state.auto = false
			refreshUi()
			return
		end
		if not scene.placedId then
			Ui.toast("Elige un arma primero", Ui.COLORS.red)
			return
		end
		state.auto = true
		refreshUi()
		task.spawn(function()
			local ok, problem = pcall(autoLoop)
			if not ok then
				warn("ForgeScene:", problem)
				state.auto = false
				striking = false
				if scene then
					scene.hammerFixed = false
				end
				refreshUi()
			end
		end)
	end))
	for _, name in { "Swords", "Equipped", "Item_gradeCrystal" } do
		table.insert(s.connections, player:GetAttributeChangedSignal(name):Connect(function()
			refreshUi()
		end))
	end
	table.insert(s.connections, player.CharacterRemoving:Connect(function()
		ForgeScene.exit()
	end))
end

function ForgeScene.bind(forgeApi)
	api = forgeApi
end

function ForgeScene.enter()
	if active or not api then
		return
	end
	local forge, anvil = findForge()
	local camera = workspace.CurrentCamera
	local character = player.Character
	if not forge or not anvil or not camera or not character then
		return
	end
	if not ui then
		buildUi()
	end
	active = true
	striking = false
	local rotation = anvil.CFrame.Rotation
	local folder = Instance.new("Folder")
	folder.Name = "ForgeSceneFx"
	folder.Parent = workspace

	-- Se esconden el martillo y el metal de adorno: ahora manda el del jugador.
	local hidden = {}
	for _, item in forge:GetDescendants() do
		if item:IsA("BasePart") and (item.Name == "MetalAlRojo" or (item.Parent and item.Parent.Name == "Martillo")) then
			hidden[item] = item.Transparency
			item.Transparency = 1
		end
	end

	local fov = Instance.new("NumberValue")
	fov.Value = camera.FieldOfView
	local camValue = Instance.new("CFrameValue")
	camValue.Value = camera.CFrame
	local saved = { type = camera.CameraType, cframe = camera.CFrame, fov = camera.FieldOfView }

	local ghost, ghostSize = swordModel(1, nil, true)
	local swordAt = anvil.CFrame * CFrame.new(0.25, anvil.Size.Y / 2 + ghostSize.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, -math.pi / 2)
	ghost:PivotTo(swordAt)
	ghost.Parent = folder
	local hitbox = part(folder, "Zona", Vector3.new(ghostSize.X + 1.2, 2.6, ghostSize.Z + 1.2), WHITE, Enum.Material.SmoothPlastic)
	hitbox.CFrame = CFrame.new(swordAt.Position) * rotation
	hitbox.Transparency = 1
	hitbox.CanQuery = true

	local labelAt = anvil.Position + Vector3.new(0, anvil.Size.Y / 2 + 3.2, 0)

	-- Chispas, brasas y luz del golpe.
	local sparkHolder = part(folder, "Chispas", Vector3.new(0.4, 0.4, 0.4), WHITE, Enum.Material.SmoothPlastic)
	sparkHolder.Transparency = 1
	sparkHolder.Position = anvil.Position
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.LightEmission = 1
	sparks.Enabled = false
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.SpreadAngle = Vector2.new(75, 75)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -42, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = sparkHolder
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK_TEXTURE
	embers.LightEmission = 1
	embers.Enabled = false
	embers.Lifetime = NumberRange.new(0.8, 1.6)
	embers.Speed = NumberRange.new(3, 9)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, 3, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	embers.Parent = sparkHolder
	local hitLight = Instance.new("PointLight")
	hitLight.Brightness = 0
	hitLight.Shadows = false
	hitLight.Parent = sparkHolder

	scene = {
		anvil = anvil,
		forge = forge,
		rotation = rotation,
		folder = folder,
		hidden = hidden,
		fov = fov,
		camValue = camValue,
		saved = saved,
		ghost = ghost,
		hitbox = hitbox,
		sword = nil,
		placedId = nil,
		swordSize = ghostSize,
		swordRest = swordAt,
		planeY = anvil.Position.Y + anvil.Size.Y / 2 + 0.6,
		sparkHolder = sparkHolder,
		sparks = sparks,
		embers = embers,
		hitLight = hitLight,
		labelAt = labelAt,
		hammerParts = {},
		phi = HOVER,
		hammerAt = anvil.Position,
		hammerFixed = false,
		hitAt = anvil.Position,
		randomX = 0,
		connections = {},
		enteredAt = os.clock(),
	}
	scene.hammerParts = buildHammer(folder)
	for item in scene.hammerParts do
		if item.Name == "Cabeza" then
			scene.hammerHead = item
		end
	end
	showHammer(false)
	setGradeLabel(nil)

	api.state.forge = true
	api.state.onPick = function()
		api.closeWindow()
		placeSword(true)
	end
	api.state.onResult = function(index: number)
		if scene then
			scene.resultIndex = index
			scene.resultReady = true
		end
	end

	setControls(false)
	camera.CameraType = Enum.CameraType.Scriptable
	local target = cameraPose(anvil, rotation)
	TweenService:Create(camValue, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = target }):Play()
	TweenService:Create(fov, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = 55 }):Play()

	ui.gui.Enabled = true
	ui.gradeBox.Visible = true
	placeSword(false, true) -- siempre empieza con la silueta: hay que elegir el arma
	refreshUi()

	-- Cada fotograma: cámara con su sacudida, martillo detrás del ratón, silueta que late, arma que vibra.
	RunService:BindToRenderStep("ForgeScene", Enum.RenderPriority.Camera.Value + 2, function()
		local s = scene
		if not s then
			return
		end
		local now = os.clock()
		local offset = Vector3.zero
		if s.shake and s.shake > 0.002 then
			offset = Vector3.new((math.random() - 0.5) * s.shake, (math.random() - 0.5) * s.shake, 0)
			s.shake *= 0.9
		end
		camera.CFrame = s.camValue.Value * CFrame.new(offset)
		camera.FieldOfView = s.fov.Value
		local onScreen = camera:WorldToViewportPoint(s.labelAt)
		ui.gradeBox.Position = UDim2.fromOffset(onScreen.X, onScreen.Y)

		if not s.placedId then
			-- Silueta: late; más clara si el ratón está encima.
			local over = false
			local location = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(location.X, location.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { s.hitbox }
			if workspace:Raycast(ray.Origin, ray.Direction * 200, params) then
				over = true
			end
			s.ghostOver = over
			local beat = (math.sin(now * 3.2) + 1) / 2
			for _, item in s.ghost:GetDescendants() do
				if item:IsA("BasePart") then
					item.Transparency = if over then 0.2 + beat * 0.1 else 0.5 + beat * 0.2
				end
			end
			UserInputService.MouseIconEnabled = true
			return
		end

		-- Arma: caída al ponerla y vibración tras el golpe.
		local rest = s.swordRest
		local lift = 0
		if s.drop then
			local t = (now - s.drop) / 0.35
			if t >= 1 then
				s.drop = nil
			else
				lift = (1 - t) * (1 - t) * 3 * math.abs(math.cos(t * 7)) * (1 - t) + (1 - t) * 1.5
			end
		end
		local jitter = CFrame.identity
		if s.vibe then
			local t = now - s.vibe.start
			if t > 0.7 then
				s.vibe = nil
			else
				local decay = math.exp(-t * 5.5)
				jitter = CFrame.new(math.sin(t * 90) * s.vibe.amount * decay * 0.5, math.sin(t * 70) * s.vibe.amount * decay, math.sin(t * 60) * s.vibe.amount * decay * 0.4) * CFrame.Angles(0, math.sin(t * 80) * s.vibe.amount * decay * 0.25, 0)
			end
		end
		if s.sword then
			s.sword:PivotTo(CFrame.new(0, lift, 0) * jitter * rest)
		end

		-- Martillo: sigue al ratón sobre el yunque (mientras no golpea) y se esconde sobre la interfaz.
		local overWindow = api.window.Visible
		showHammer(not overWindow)
		UserInputService.MouseIconEnabled = overWindow
		if not s.hammerFixed then
			local point = mousePoint(s.planeY)
			if point then
				local localPoint = s.anvil.CFrame:PointToObjectSpace(point)
				local clamped = Vector3.new(math.clamp(localPoint.X, -3.8, 4.4), localPoint.Y, math.clamp(localPoint.Z, -2.6, 2.6))
				local target = s.anvil.CFrame * clamped
				s.hammerAt = s.hammerAt:Lerp(Vector3.new(target.X, s.planeY, target.Z), 0.35)
			end
			s.phi = HOVER + math.sin(now * 3) * math.rad(3)
		end
		poseHammer()
	end)

	connectInput()
end

function ForgeScene.exit()
	if not active then
		return
	end
	active = false
	local s = scene
	api.state.auto = false
	api.state.forge = nil
	api.state.onPick = nil
	api.state.onResult = nil
	api.closeWindow()
	RunService:UnbindFromRenderStep("ForgeScene")
	UserInputService.MouseIconEnabled = true
	if s then
		for _, connection in s.connections do
			connection:Disconnect()
		end
		for item, transparency in s.hidden do
			if item.Parent then
				item.Transparency = transparency
			end
		end
		-- La cámara vuelve a la del jugador.
		local camera = workspace.CurrentCamera
		camera.FieldOfView = s.saved.fov
		camera.CameraType = s.saved.type
		s.folder:Destroy()
		s.camValue:Destroy()
		s.fov:Destroy()
	end
	scene = nil
	striking = false
	setControls(true)
	if ui then
		ui.gui.Enabled = false
		ui.gradeBox.Visible = false
		ui.flash.BackgroundTransparency = 1
		ui.big.TextTransparency = 1
		ui.big.Visible = false
	end
end

function ForgeScene.toggle()
	if active then
		ForgeScene.exit()
	else
		ForgeScene.enter()
	end
end

return ForgeScene
