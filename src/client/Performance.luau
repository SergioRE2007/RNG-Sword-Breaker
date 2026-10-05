-- Modo rendimiento: un interruptor del cliente que consultan los demás módulos (Ui, Hud, Backpack,
-- ModifierShops, SkillTree, WeaponPreview, WeaponAura, SwingAnim, Effects y Ambience). Activado,
-- el juego quita todo lo que sea solo adorno: partículas, estelas, luces, auras, hierba, flores,
-- mariposas, nubes, sombras, efectos de pantalla y las animaciones de la interfaz. Se activa solo
-- en móviles (táctil y sin teclado) y se cambia a mano en Ajustes. Solo afecta a este cliente.
-- Los módulos con bucles preguntan `Performance.get()` en cada vuelta; los que crean cosas una sola
-- vez escuchan `Performance.Changed`.
local UserInputService = game:GetService("UserInputService")

local Performance = {}

local enabled = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local changed = Instance.new("BindableEvent")
Performance.Changed = changed.Event

-- Efectos de luz y partículas del mundo que se apagan en bloque: instancia -> si estaba encendida.
local EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "PointLight", "SpotLight", "SurfaceLight", "Fire", "Smoke", "Sparkles" }
local silenced: { [Instance]: boolean } = {}
local watcher: RBXScriptConnection? = nil

local function isEffect(item: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if item:IsA(className) then
			return true
		end
	end
	return false
end

local function silence(item: Instance)
	if isEffect(item) and silenced[item] == nil then
		silenced[item] = (item :: any).Enabled
		;(item :: any).Enabled = false
	end
end

function Performance.get(): boolean
	return enabled
end

function Performance.set(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	Performance.apply()
	changed:Fire(on)
end

-- Apaga (o devuelve) las partículas, estelas y luces de todo el mundo, también de lo que llegue después.
function Performance.apply()
	if enabled then
		for _, item in workspace:GetDescendants() do
			silence(item)
		end
		if not watcher then
			watcher = workspace.DescendantAdded:Connect(silence)
		end
	else
		if watcher then
			watcher:Disconnect()
			watcher = nil
		end
		for item, wasEnabled in silenced do
			if item.Parent then
				(item :: any).Enabled = wasEnabled
			end
		end
		table.clear(silenced)
	end
end

function Performance.start()
	if enabled then
		Performance.apply()
	end
end

-- Por si algo se ha destruido: limpia cada cierto tiempo lo apagado que ya no existe.
task.spawn(function()
	while true do
		task.wait(30)
		for item in silenced do
			if not item.Parent then
				silenced[item] = nil
			end
		end
	end
end)

return Performance
