-- Menú de botín de las mazmorras (servidor). Durante la partida `Loot` no entrega nada: apunta el botín en
-- `summary.held`. Al acabar la partida, `DropMenu.offer` se lo ofrece al jugador (cada entrada con un id) y espera su
-- respuesta: el cliente solo manda los ids que tira (`DropDecision`) y aquí se valida que son del botín que se le
-- ofreció. Lo demás entra al inventario. Sin respuesta en `Timeout` s, al salir del juego o con Repetir / Auto de
-- pelea (que no deben parar a nadie) se queda todo. La armadura que no cabe se desmonta sola (Armor.store).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PotionInfo = require(ReplicatedStorage.Shared.PotionInfo)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Armor = require(script.Parent.Armor)
local PlayerData = require(script.Parent.PlayerData)
local Potions = require(script.Parent.Potions)

local DropMenu = {}

local cfg = Config.Dungeon.DropMenu
local pending = {} -- [Player] = { drops = { entrada con id }, token = number }
local tokens = 0

-- Entrega una entrada del botín (lo que se quedó el jugador).
local function grant(player: Player, drop)
	if drop.kind == "item" then
		local item = Config.Items[drop.key]
		if not item then
			return
		end
		PlayerData.edit(player, function(data)
			data.items[drop.key] += drop.amount
		end)
		Remotes.Notice:FireClient(player, `+{Format.short(drop.amount)} {item.name}`, item.color)
	elseif drop.kind == "potion" then
		if PotionInfo.valid(drop.family, drop.tier) then
			for _ = 1, drop.amount do
				Potions.give(player, drop.family, drop.tier)
			end
		end
	elseif drop.kind == "armor" then
		Armor.store(player, drop.piece, drop.luck or 1)
	end
end

-- Cierra lo pendiente del jugador: tira los ids de `discard` (si no es nil) y entrega el resto, en el orden de la lista.
local function resolve(player: Player, discard: { [number]: boolean }?)
	local entry = pending[player]
	if not entry then
		return
	end
	pending[player] = nil
	local thrown = 0
	for _, drop in entry.drops do
		if discard and discard[drop.id] then
			thrown += 1
		elseif player.Parent then
			grant(player, drop)
		end
	end
	if thrown > 0 and player.Parent then
		Remotes.Notice:FireClient(player, `Has tirado {thrown} {if thrown == 1 then "botín" else "botines"}`, Color3.fromRGB(200, 205, 225))
	end
end

-- ¿Es de calidad alta (pide confirmación para tirarlo)?
local function isHigh(drop): boolean
	if drop.kind == "armor" then
		return drop.piece.quality >= cfg.ConfirmQuality
	elseif drop.kind == "potion" then
		return drop.tier >= cfg.ConfirmTier
	end
	return false
end

-- Lo que ve el cliente de cada entrada (nada más que lo necesario para pintarla).
local function describe(drop)
	if drop.kind == "armor" then
		local piece = drop.piece
		return { id = drop.id, kind = "armor", high = isHigh(drop), piece = { slot = piece.slot, quality = piece.quality, level = piece.level, stats = piece.stats } }
	end
	return { id = drop.id, kind = drop.kind, key = drop.key, family = drop.family, tier = drop.tier, amount = drop.amount, high = isHigh(drop) }
end

-- Ofrece el botín retenido de `summary` al jugador. Devuelve los datos para el menú del cliente
-- ({ drops, armorFree, expires }) o nil si no hay menú (sin botín, o se ha entregado todo ya: `granted` = cuántas entradas).
function DropMenu.offer(player: Player, summary): ({ [string]: any }?, number)
	local held = summary.held
	if not held or #held == 0 then
		return nil, 0
	end
	summary.held = {}
	resolve(player, nil) -- lo que quedara sin contestar de una partida anterior se queda
	for index, drop in held do
		drop.id = index
	end
	if player:GetAttribute("DungeonLoop") == true or player:GetAttribute("AutoFight") == true then
		pending[player] = { drops = held, token = 0 }
		resolve(player, nil)
		return nil, #held
	end
	local data = PlayerData.read(player)
	if not data then
		return nil, 0
	end
	tokens += 1
	local token = tokens
	pending[player] = { drops = held, token = token }
	task.delay(cfg.Timeout, function()
		local entry = pending[player]
		if entry and entry.token == token then
			resolve(player, nil)
		end
	end)
	local list = {}
	for _, drop in held do
		table.insert(list, describe(drop))
	end
	return { drops = list, armorFree = math.max(0, Config.Armor.MaxPieces - #data.armor), expires = workspace:GetServerTimeNow() + cfg.Timeout }, 0
end

-- Entrega ya todo el botín retenido (el jugador se va del juego en mitad de la partida: no se pierde nada).
function DropMenu.keepAll(player: Player, summary)
	local held = summary.held
	if not held or #held == 0 then
		return
	end
	summary.held = {}
	for _, drop in held do
		grant(player, drop)
	end
end

-- Respuesta del cliente: { ids } de lo que tira. Nada se da por bueno: solo cuentan números enteros que sean ids del
-- botín ofrecido a ese jugador, sin repetir.
local function onDecision(player: Player, ids: unknown)
	local entry = pending[player]
	if not entry then
		return
	end
	local discard = {}
	if type(ids) == "table" then
		local valid = {}
		for _, drop in entry.drops do
			valid[drop.id] = true
		end
		local count = 0
		for _, id in ids do
			count += 1
			if count > #entry.drops then
				break
			end
			if type(id) == "number" and id % 1 == 0 and valid[id] then
				discard[id] = true
			end
		end
	end
	resolve(player, discard)
end

function DropMenu.start()
	Remotes.DropDecision.OnServerEvent:Connect(onDecision)
	Players.PlayerRemoving:Connect(function(player)
		resolve(player, nil)
	end)
end

return DropMenu
