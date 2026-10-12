-- A qué servidores van las órdenes del menú de admin: solo a este o a todos los del juego. Librería sin start(); lo
-- cambia el botón `Hud.Admin.Scope` (client/AdminPanel) y lo usan los paneles al mandar lo que vale para todos
-- (clima, regalos a todos, avisos, mensaje grande y eventos). El servidor es quien decide (server/AdminCommands).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AdminScope = {}

AdminScope.all = false -- true = todos los servidores
local changed = Instance.new("BindableEvent")
AdminScope.Changed = changed.Event

function AdminScope.set(all: boolean)
	if AdminScope.all ~= all then
		AdminScope.all = all
		changed:Fire(all)
	end
end

-- Una orden de AdminCommand, con "all" delante si toca.
function AdminScope.command(action: string, ...: any)
	if AdminScope.all then
		Remotes.AdminCommand:FireServer("all", action, ...)
	else
		Remotes.AdminCommand:FireServer(action, ...)
	end
end

-- Clima: un id, "none" o "auto".
function AdminScope.weather(action: string)
	if AdminScope.all then
		Remotes.AdminCommand:FireServer("all", "weather", action)
	else
		Remotes.AdminWeather:FireServer(action)
	end
end

return AdminScope
