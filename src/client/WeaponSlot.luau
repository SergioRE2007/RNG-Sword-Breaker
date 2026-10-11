-- Hueco de abajo en el centro del HUD, donde van los botones de AutoPlay (autoclicker y Auto). Antes llevaba además
-- una casilla por arma equipada; el usuario las mandó quitar (tenían sentido con una sola arma, no con cuatro u
-- ocho): las armas equipadas se ven y se cambian en la mochila (fila `Body.Swords.Slots` de client/Backpack).
--   Hud.HudRoot.WeaponSlot (sin ancho: los dos botones quedan juntos, uno a cada lado del centro)
local Ui = require(script.Parent.Ui)

local WeaponSlot = {}
-- Lado de los botones de AutoPlay, en unidades del HUD (Ui.hud ya adapta su escala).
WeaponSlot.SIZE = 76

local SIZE = WeaponSlot.SIZE

function WeaponSlot.start()
	local root = Ui.hud()
	local dock = Instance.new("Frame")
	dock.Name = "WeaponSlot"
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Size = UDim2.fromOffset(0, SIZE)
	dock.BackgroundTransparency = 1
	dock.Parent = root
	local function fit()
		-- En vertical, deja sitio a los contadores inferiores y a los controles táctiles.
		dock.Position = UDim2.new(0.5, 0, 1, if root.AbsoluteSize.X < root.AbsoluteSize.Y then -154 else -16)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

return WeaponSlot
