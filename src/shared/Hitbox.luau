-- Volumen de ataque contra cajas orientadas. Compartido por objetos y enemigos; sin físicas de la hoja.
local Hitbox = {}

local function rayBox(part, start: Vector3, direction: Vector3, range: number): boolean
	local point = part.CFrame:PointToObjectSpace(start)
	local vector = part.CFrame:VectorToObjectSpace(direction)
	local half = part.Size / 2
	local near, far = 0, range
	for _, axis in { "X", "Y", "Z" } do
		if math.abs(vector[axis]) < 1e-8 then
			if math.abs(point[axis]) > half[axis] then return false end
		else
			local a = (-half[axis] - point[axis]) / vector[axis]
			local b = (half[axis] - point[axis]) / vector[axis]
			near = math.max(near, math.min(a, b))
			far = math.min(far, math.max(a, b))
			if near > far then return false end
		end
	end
	return true
end

function Hitbox.reaches(part, origin: CFrame, range: number, arc: number): boolean
	if range <= 0 then return false end
	local point = part.CFrame:PointToObjectSpace(origin.Position)
	local half = part.Size / 2
	local closest = part.CFrame * Vector3.new(math.clamp(point.X, -half.X, half.X), math.clamp(point.Y, -half.Y, half.Y), math.clamp(point.Z, -half.Z, half.Z))
	local offset = closest - origin.Position
	if offset.Magnitude > range + 1e-6 then return false end
	if arc <= -1 then return true end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	if look.Magnitude < 1e-8 then return false end
	look = look.Unit
	if flat.Magnitude < 1e-6 or flat.Unit:Dot(look) >= arc - 1e-6 then return true end
	-- El punto más cercano puede quedar fuera del arco aunque una caja grande lo cruce.
	local height = closest.Y - origin.Position.Y
	local reach = math.sqrt(math.max(range * range - height * height, 0))
	local start = origin.Position + Vector3.new(0, height, 0)
	local angle = math.acos(math.clamp(arc, -1, 1))
	for _, turn in { 0, -angle, angle } do
		local direction = CFrame.Angles(0, turn, 0):VectorToWorldSpace(look)
		if rayBox(part, start, direction, reach) then return true end
	end
	return false
end

-- Si la pieza toca el círculo de ese radio alrededor de un punto (cuenta su punto más cercano): el círculo del jugador
-- dentro del que puede elegir objetivo (Config.Loadout.Radius).
function Hitbox.within(part, center: Vector3, radius: number): boolean
	return Hitbox.reaches(part, CFrame.new(center), radius, -1)
end

local PIERCE_ARC = 0.94 -- lo estrecha que es la línea de la lanza: coseno del medio ángulo (unos 20°)

-- A qué más llega el golpe de un arma además de a su objetivo, según su tipo (Config.WeaponKinds): las que salpican
-- (area), a lo que haya alrededor del objetivo; las que atraviesan (pierce), a lo que quede detrás, en línea desde quien
-- ataca. `length` = largo del arma, `from` = dónde está quien ataca, `target` = centro del objetivo. Devuelve el origen,
-- el alcance y el arco para Hitbox.reaches, o nil si el arma solo pega a su objetivo. Se mide a la altura de quien
-- ataca, para que un objetivo muy alto no deje fuera a los pequeños que tiene al lado.
function Hitbox.spread(kind, length: number, from: Vector3, target: Vector3): (CFrame?, number, number)
	local center = Vector3.new(target.X, from.Y, target.Z)
	if (kind.area or 0) > 0 then
		return CFrame.new(center), kind.area * length, -1
	end
	if (kind.pierce or 0) > 0 then
		local away = center - from
		if away.Magnitude > 1e-3 then
			-- Mirando en la dirección del golpe (con fromMatrix: el lookAt de Lune, donde corren las pruebas, mira al revés).
			local look = away.Unit
			return CFrame.fromMatrix(center, look:Cross(Vector3.yAxis), Vector3.yAxis, -look), kind.pierce * length, PIERCE_ARC
		end
	end
	return nil, 0, 0
end

return Hitbox
