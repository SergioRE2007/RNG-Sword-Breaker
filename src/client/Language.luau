-- Idioma del jugador: el que tiene elegido para esta experiencia en el menú de Roblox (Ajustes → Idioma), no el de su
-- cuenta. Antes se miraba el de la cuenta y cambiar el idioma en ese menú no hacía nada (lo notó el usuario). Roblox lo
-- da en el Translator del jugador (su LocaleId), que además avisa cuando cambia.
-- Va lo primero en el arranque del cliente: espera un momento a saberlo, para que ningún módulo escriba un texto en
-- el idioma que no es, y se lo dice al servidor (remote SetLang) para sus avisos. Si el jugador cambia de idioma a
-- media partida, lo que ya está escrito se traduce en el momento (client/LangSwap; antes había que volver a entrar).
-- En Studio, el atributo "LangTest" del jugador local ("es" o "en") hace lo mismo que cambiarlo en el menú de Roblox.
-- En español el juego pone sus propios textos (shared/LangEs): ahí se apaga la traducción automática de Roblox
-- (AutoLocalize) en la interfaz, para que no los capture ni intente traducirlos como si fueran inglés.
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage.Shared.Lang)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Language = {}

local WAIT = 3 -- segundos como mucho esperando a Roblox al arrancar; después vale el idioma de la cuenta

local player = Players.LocalPlayer

local function autoLocalize()
	local on = Lang.code() ~= "es"
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui then
		for _, layer in gui:GetChildren() do
			if layer:IsA("LayerCollector") then
				layer.AutoLocalize = on
			end
		end
	end
end

-- El jugador ha elegido otro idioma con el juego abierto: lo nuevo sale ya en ese y lo escrito se traduce.
local function change(code: string)
	local before = Lang.code()
	if code == before then
		return
	end
	Lang.set(code)
	Remotes.SetLang:FireServer(code)
	autoLocalize()
	-- Se piden aquí: este módulo arranca antes que la interfaz.
	require(script.Parent.LangSwap).change(before, code)
	require(script.Parent.WorldText).refresh()
end

function Language.start()
	local done = false
	task.spawn(function()
		local ok, translator = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(player)
		end)
		if ok and translator then
			local code = Lang.fromLocale(translator.LocaleId)
			Lang.set(code)
			Remotes.SetLang:FireServer(code)
			translator:GetPropertyChangedSignal("LocaleId"):Connect(function()
				change(Lang.fromLocale(translator.LocaleId))
			end)
		end
		done = true
	end)
	local waited = 0
	while not done and waited < WAIT do
		waited += task.wait()
	end

	local gui = player:WaitForChild("PlayerGui")
	gui.ChildAdded:Connect(function(layer)
		if layer:IsA("LayerCollector") and Lang.code() == "es" then
			layer.AutoLocalize = false
		end
	end)
	autoLocalize()
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("LangTest"):Connect(function()
			local code = player:GetAttribute("LangTest")
			if code == "es" or code == "en" then
				change(code)
			end
		end)
	end
end

return Language
