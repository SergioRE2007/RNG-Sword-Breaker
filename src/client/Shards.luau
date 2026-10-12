-- Trozos que saltan al romperse algo (librería, sin start()): los mueve este módulo, no las físicas. Pedido por el
-- usuario: los escombros no pueden tocar la cámara, y la de Roblox se acerca al personaje con cualquier pieza opaca
-- que choque (CanCollide) y se le cruce. Un trozo que no choca atravesaría el suelo, así que aquí van anclados y
-- sin choque, con su caída y su rebote hechos a mano en un solo bucle que solo vive mientras queda alguno.
local RunService = game:GetService("RunService")

local Shards = {}

local GRAVITY = 110 -- studs/s²: algo menos que la del juego, para que se vean volar
local BOUNCE = 0.35 -- parte de la velocidad que conserva al rebotar
local GRIP = 0.6 -- parte de la velocidad de lado (y del giro) que conserva en cada rebote
local REST = 5 -- por debajo de esta velocidad de caída ya no rebota: se queda en el suelo

type Shard = { part: BasePart, velocity: Vector3, spin: Vector3, floor: number, resting: boolean }

local shards: { Shard } = {}
local loop: RBXScriptConnection? = nil

local function step(dt: number)
	dt = math.min(dt, 1 / 20)
	for index = #shards, 1, -1 do
		local shard = shards[index]
		local part = shard.part
		if not part.Parent then
			table.remove(shards, index)
			continue
		end
		if shard.resting then
			continue
		end
		local velocity = shard.velocity - Vector3.new(0, GRAVITY * dt, 0)
		local position = part.Position + velocity * dt
		local spin = shard.spin
		if position.Y < shard.floor and velocity.Y < 0 then
			position = Vector3.new(position.X, shard.floor, position.Z)
			if -velocity.Y < REST then
				shard.resting = true
				velocity = Vector3.zero
				spin = Vector3.zero
			else
				velocity = Vector3.new(velocity.X * GRIP, -velocity.Y * BOUNCE, velocity.Z * GRIP)
				spin *= GRIP
			end
		end
		shard.velocity = velocity
		shard.spin = spin
		part.CFrame = CFrame.new(position) * CFrame.fromEulerAnglesXYZ(spin.X * dt, spin.Y * dt, spin.Z * dt) * part.CFrame.Rotation
	end
	if #shards == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

-- Lanza `part` (ya colocada y con padre) con esa velocidad y ese giro (radianes/s); `ground` es la Y del suelo
-- sobre el que cae. Quien la crea se encarga de borrarla: al quedarse sin padre deja de moverse.
function Shards.launch(part: BasePart, velocity: Vector3, spin: Vector3, ground: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local size = part.Size
	table.insert(shards, {
		part = part,
		velocity = velocity,
		spin = spin,
		floor = ground + math.min(size.X, size.Y, size.Z) / 2,
		resting = false,
	})
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

return Shards
