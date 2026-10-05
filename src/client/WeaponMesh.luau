-- Viste las armas con malla propia (shared/MeshWeapon) que el servidor entrega solo con la empuñadura
-- marcada con la etiqueta "WeaponMesh", y anima sus piezas sueltas: cinta, halo, chispas y esquirlas dan
-- vueltas alrededor de la hoja y flotan arriba y abajo.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MeshWeapon = require(ReplicatedStorage.Shared.MeshWeapon)

local Performance = require(script.Parent.Performance)

local WeaponMesh = {}

local LOOP = 5 -- segundos que dura el bucle de la animación
local TAU = 2 * math.pi

local moving = {} -- [Weld] = { weld, piece, center, scale }

local function dress(handle: Instance)
	if not handle:IsA("BasePart") then
		return
	end
	task.spawn(function()
		local welds = MeshWeapon.attach(handle, false)
		for _, entry in welds or {} do
			moving[entry.weld] = entry
		end
	end)
end

local function step()
	if Performance.get() then return end -- modo rendimiento
	local phase = os.clock() / LOOP * TAU
	for weld, entry in moving do
		if not weld.Parent then
			moving[weld] = nil
			continue
		end
		local piece = entry.piece
		local rise = math.sin(phase) * piece.bob * entry.scale
		weld.C0 = CFrame.Angles(0, phase * piece.spin, 0) * CFrame.new(entry.center + Vector3.new(0, rise, 0))
	end
end

function WeaponMesh.start()
	CollectionService:GetInstanceAddedSignal(MeshWeapon.TAG):Connect(dress)
	for _, handle in CollectionService:GetTagged(MeshWeapon.TAG) do
		dress(handle)
	end
	RunService.RenderStepped:Connect(step)
end

return WeaponMesh
