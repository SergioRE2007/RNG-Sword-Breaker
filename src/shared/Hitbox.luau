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

return Hitbox
