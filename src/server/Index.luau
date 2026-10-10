-- Índice de armas: apunta las combinaciones (arma + metal + tamaño) que le salen a cada jugador y las publica en su
-- atributo `Index` (códigos de shared/IndexInfo separados por comas), que es lo que lee la ventana del cliente.
-- Decidido por el usuario: solo cuentan las tiradas propias (Index.record, desde Gacha), se quede el arma o la venda
-- la venta automática; lo recibido por comercio no. El día que un jugador lo estrena cuenta además lo que ya tenía
-- en la mochila, una sola vez.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexInfo = require(ReplicatedStorage.Shared.IndexInfo)
local PlayerData = require(script.Parent.PlayerData)

local Index = {}

local known = {} -- [Player] = { [código] = true }: lo que ya tiene apuntado (para no recorrer la lista en cada tirada)

local function publish(player: Player)
	local data = PlayerData.read(player)
	if data and data.index then
		player:SetAttribute("Index", IndexInfo.encode(data.index))
	end
end

-- Apunta esa combinación si es nueva para el jugador. Solo entonces toca sus datos y el atributo.
function Index.record(player: Player, sword: number, metal: number?, size: number?)
	local set = known[player]
	local code = IndexInfo.code(sword, metal, size)
	if not set or set[code] or not IndexInfo.valid(code) then
		return
	end
	set[code] = true
	PlayerData.edit(player, function(data)
		table.insert(data.index, code)
	end)
	publish(player)
end

function Index.start()
	PlayerData.onLoad(function(player)
		local set = {}
		PlayerData.edit(player, function(data)
			if not data.index then
				-- Sin estrenar: empieza con lo que hay en la mochila.
				data.index = {}
				for _, copy in data.swords do
					local code = IndexInfo.code(copy.sword, copy.metal, copy.size)
					if IndexInfo.valid(code) and not set[code] then
						set[code] = true
						table.insert(data.index, code)
					end
				end
			else
				for _, code in data.index do
					set[code] = true
				end
			end
		end)
		known[player] = set
		publish(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		known[player] = nil
	end)
end

return Index
