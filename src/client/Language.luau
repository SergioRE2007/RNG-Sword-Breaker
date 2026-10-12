-- Idioma del jugador: el que tiene elegido para esta experiencia en el menú de Roblox (Ajustes → Idioma), no el de su
-- cuenta. Antes se miraba el de la cuenta y cambiar el idioma en ese menú no hacía nada (lo notó el usuario). Roblox lo
-- da en el Translator del jugador (su LocaleId), que además avisa cuando cambia.
-- Va lo primero en el arranque del cliente: espera un momento a saberlo, para que ningún módulo escriba un texto en
-- el idioma que no es, y se lo dice al servidor (remote SetLang) para sus avisos. Los textos ya escritos no cambian
-- solos: si el jugador cambia de idioma a media partida, se le avisa de que vuelva a entrar.
-- En español el juego pone sus propios textos (shared/LangEs): ahí se apaga la traducción automática de Roblox
-- (AutoLocalize) en la interfaz, para que no los capture ni intente traducirlos como si fueran inglés.
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
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
				local changed = Lang.fromLocale(translator.LocaleId)
				if changed == Lang.code() then
					return
				end
				Lang.set(changed)
				Remotes.SetLang:FireServer(changed)
				autoLocalize()
				-- Ui se pide aquí: este módulo arranca antes que la interfaz.
				local Ui = require(script.Parent.Ui) :: any
				Ui.toast(Lang.t(nil, "Language changed. Rejoin to see everything in the new language."), Ui.COLORS.blue)
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
end

return Language
