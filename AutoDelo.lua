script_name("AutoDelo")
script_author("Zhukoff")
script_description("Автоматическое расследование дел копов")

local SCRIPT_VERSION = "1.1"
local UPDATE_JSON_URL = "https://raw.githubusercontent.com/Zhukoff42/AutoDelo/main/Update.json"
local SCRIPT_URL = "https://raw.githubusercontent.com/Zhukoff42/AutoDelo/main/AutoDelo.lua"

local vkeys = require 'vkeys'
local sampex = require 'samp.events'
local ffi = require 'ffi'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local dlstatus = require('moonloader').download_status

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local config_path = "AutoDelo.ini"
local cfg = inicfg.load({
    settings = {
        enable_rp = true
    }
}, config_path)

if not cfg then
    cfg = {settings = {enable_rp = true}}
    inicfg.save(cfg, config_path)
end

local script_path = thisScript().path
local update_state = "Ожидание проверки..."
local update_available = false
local new_version = ""
local need_reload = false

ffi.cdef[[
    typedef void* HWND;
    typedef void* HKL;
    HWND GetActiveWindow();
    int PostMessageA(HWND hWnd, unsigned int Msg, unsigned long wParam, long lParam);
    HKL LoadKeyboardLayoutA(const char* pwszKLID, unsigned int Flags);
]]

function setRussianLayout()
    pcall(function()
        local hwnd = ffi.C.GetActiveWindow()
        if hwnd ~= nil then
            ffi.C.LoadKeyboardLayoutA("00000419", 1)
            ffi.C.PostMessageA(hwnd, 0x0050, 0, 0x04190419)
        end
    end)
end

local isRunning = false
local activeThread = nil
local savedDate = nil
local savedWeapon = nil

local showMenu = imgui.new.bool(false)
local enableRP = imgui.new.bool(cfg.settings.enable_rp)
local menuAlpha = 0.0

function check_update()
    update_state = "Проверка обновлений..."
    local temp_path = getWorkingDirectory() .. '\\autodelo_upd_' .. tostring(os.time()) .. '_' .. tostring(math.random(100, 999)) .. '.json'
    local no_cache_url = UPDATE_JSON_URL .. "?t=" .. tostring(os.time())
    
    downloadUrlToFile(no_cache_url, temp_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            if doesFileExist(temp_path) then
                local file = io.open(temp_path, "r")
                if file then
                    local content = file:read("*a")
                    file:close()
                    os.remove(temp_path)
                    
                    local res, data = pcall(decodeJson, content)
                    if res and data and data.version then
                        if tostring(data.version) ~= tostring(SCRIPT_VERSION) then
                            update_available = true
                            new_version = tostring(data.version)
                            update_state = "Доступно обновление!"
                        else
                            update_state = "У вас установлена последняя версия."
                            update_available = false
                        end
                    else
                        update_state = "Ошибка: неверный формат Update.json"
                    end
                else
                    update_state = "Ошибка чтения файла проверки."
                end
            end
        elseif status == dlstatus.STATUSEX_ERROR then
            update_state = "Ошибка соединения при проверке."
        end
    end)
end

function perform_update()
    update_state = "Скачивание файлов..."
    local no_cache_url = SCRIPT_URL .. "?t=" .. tostring(os.time())
    downloadUrlToFile(no_cache_url, script_path, function(id, status, p1, p2)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            update_state = "Установка завершена! Перезагрузка..."
            need_reload = true
        elseif status == dlstatus.STATUSEX_ERROR then
            update_state = "Ошибка при скачивании!"
            sampAddChatMessage("[Auto-Delo] Не удалось скачать обновление!", 0xFF0000)
        end
    end)
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors

    style.WindowRounding = 6.0
    style.FrameRounding = 4.0
    style.GrabRounding = 4.0
    style.WindowBorderSize = 1.0
    style.FrameBorderSize = 1.0
    style.WindowPadding = imgui.ImVec2(12, 12)
    style.ItemSpacing = imgui.ImVec2(8, 8)

    colors[imgui.Col.WindowBg]          = imgui.ImVec4(0.07, 0.07, 0.08, 0.96)
    colors[imgui.Col.Border]            = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
    colors[imgui.Col.FrameBg]           = imgui.ImVec4(0.11, 0.12, 0.14, 1.00)
    colors[imgui.Col.FrameBgHovered]    = imgui.ImVec4(0.15, 0.16, 0.19, 1.00)
    colors[imgui.Col.FrameBgActive]     = imgui.ImVec4(0.18, 0.20, 0.24, 1.00)
    colors[imgui.Col.TitleBg]           = imgui.ImVec4(0.07, 0.07, 0.08, 1.00)
    colors[imgui.Col.TitleBgActive]     = imgui.ImVec4(0.07, 0.07, 0.08, 1.00)
    colors[imgui.Col.CheckMark]         = imgui.ImVec4(0.35, 0.65, 0.95, 1.00)
    colors[imgui.Col.Text]              = imgui.ImVec4(0.90, 0.90, 0.90, 1.00)
    colors[imgui.Col.Button]            = imgui.ImVec4(0.20, 0.22, 0.25, 1.00)
    colors[imgui.Col.ButtonHovered]     = imgui.ImVec4(0.28, 0.32, 0.38, 1.00)
    colors[imgui.Col.ButtonActive]      = imgui.ImVec4(0.15, 0.18, 0.22, 1.00)
end)

local render_update_window = imgui.OnFrame(function() return update_available end, function(player)
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(420, 240), imgui.Cond.Always)
    
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.05, 0.06, 0.98))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.2, 0.4, 0.8, 0.6))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 10.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 2.0)
    
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoTitleBar
    
    if imgui.Begin("UpdateWindow", nil, flags) then
        imgui.TextColored(imgui.ImVec4(0.3, 0.6, 1.0, 1.0), u8"ДОСТУПНО НОВОЕ ОБНОВЛЕНИЕ AutoDelo")
        imgui.Separator()
        imgui.Dummy(imgui.ImVec2(0, 5))
        
        imgui.TextWrapped(u8"Вышла новая версия скрипта! Рекомендуем обновиться прямо сейчас, чтобы получить новые функции и исправления багов.")
        imgui.Dummy(imgui.ImVec2(0, 5))
        
        imgui.BeginChild("VersionBlock", imgui.ImVec2(0, 55), true)
        imgui.Text(u8"Текущая версия:")
        imgui.SameLine(160)
        imgui.TextColored(imgui.ImVec4(0.8, 0.3, 0.3, 1.0), "v" .. SCRIPT_VERSION)
        
        imgui.Text(u8"Новая версия:")
        imgui.SameLine(160)
        imgui.TextColored(imgui.ImVec4(0.3, 0.8, 0.3, 1.0), "v" .. new_version)
        imgui.EndChild()
        
        if update_state:find("Скачивание") or update_state:find("Установка") then
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), u8(" " .. update_state))
        else
            imgui.Dummy(imgui.ImVec2(0, 6))
        end
        
        imgui.Dummy(imgui.ImVec2(0, 5))
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.15, 0.45, 0.25, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.60, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.35, 0.20, 1.0))
        if imgui.Button(u8"ОБНОВИТЬ СЕЙЧАС", imgui.ImVec2(240, 35)) then
            perform_update()
        end
        imgui.PopStyleColor(3)
        
        imgui.SameLine()
        
        if imgui.Button(u8"Отложить", imgui.ImVec2(-1, 35)) then
            update_available = false
        end
    end
    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return showMenu[0] end, function(player)
    if menuAlpha < 1.0 then
        menuAlpha = math.min(1.0, menuAlpha + 0.1)
    end
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menuAlpha)
    imgui.SetNextWindowSize(imgui.ImVec2(310, 140), imgui.Cond.Always)
    
    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar
    imgui.Begin(u8" Настройки Auto-Delo", showMenu, flags)
    
    imgui.Dummy(imgui.ImVec2(0, 2))

    if imgui.Checkbox(u8" Отыгрывать РП (/do, /me, /todo)", enableRP) then
        cfg.settings.enable_rp = enableRP[0]
        inicfg.save(cfg, config_path)
    end

    imgui.Dummy(imgui.ImVec2(0, 2))
    
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.50, 0.50, 0.50, 1.0))
    imgui.TextWrapped(u8"Автор: Zhukoff")
    imgui.TextWrapped(u8"Статус: " .. u8(update_state))
    imgui.PopStyleColor()

    imgui.End()
    imgui.PopStyleVar()
end)

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    check_update()

    sampRegisterChatCommand("delo", function()
        if not isRunning then
            startInvestigation()
        else
            stopInvestigation("Скрипт остановлен повторным вводом команды /delo.")
        end
    end)

    sampRegisterChatCommand("setdelo", function()
        menuAlpha = 0.0
        showMenu[0] = not showMenu[0]
    end)
    
    sampAddChatMessage("[Auto-Delo] Скрипт загружен! /delo - начать, /setdelo - меню настроек.", 0xFF00FF00)
    sampAddChatMessage("[Auto-Delo] ALT+1 - вставить дату, ALT+2 - вставить оружие.", 0xFFFFAA00)
    sampAddChatMessage("[Auto-Delo] Автор Zhukoff. Версия: " .. SCRIPT_VERSION, 0xFFFFAA00)
    
    while true do
        wait(0)

        if need_reload then
            wait(500)
            sampAddChatMessage("[Auto-Delo] Скрипт успешно обновлен до версии " .. new_version .. ". Перезагрузка...", 0x00FF00)
            thisScript():reload()
        end

        if wasKeyPressed(vkeys.VK_F12) then
            if isRunning then
                stopInvestigation("Экстренная остановка скрипта клавишей F12!")
            else
                sampAddChatMessage("[Auto-Delo] Скрипт сейчас не активен. Для запуска введите /delo", 0xFFCCCC00)
            end
        end

        if isKeyDown(vkeys.VK_MENU) and wasKeyPressed(vkeys.VK_1) then
            if savedDate then
                pasteToCef(savedDate, "date")
            else
                sampAddChatMessage("[Auto-Delo] Ошибка: Дата и время еще не собраны!", 0xFFFF0000)
            end
        end

        if isKeyDown(vkeys.VK_MENU) and wasKeyPressed(vkeys.VK_2) then
            if savedWeapon then
                pasteToCef(savedWeapon, "weapon")
            else
                sampAddChatMessage("[Auto-Delo] Ошибка: Орудие убийства еще не собрано!", 0xFFFF0000)
            end
        end
    end
end

function startInvestigation()
    isRunning = true
    savedDate = nil
    savedWeapon = nil
    sampAddChatMessage("[Auto-Delo] Запуск процесса расследования... (Для экстренной остановки нажмите F12)", 0xFF00FF00)
    
    activeThread = lua_thread.create(function()
        if cfg.settings.enable_rp then
            sampSendChat("/do Сотрудник прибыл на место убийства.")
            wait(2000)
            sampSendChat("/todo Такс, что же здесь произошло*осматривая место убийства")
            wait(2000)
            sampSendChat("/me осматривает и изучает все улики")
            wait(2000)
            sampAddChatMessage("[Auto-Delo] Взаимодействую с местом убийства (ALT)...", 0xFFFFAA00)
        end
        
        setVirtualKeyDown(vkeys.VK_MENU, true)
        wait(80)
        setVirtualKeyDown(vkeys.VK_MENU, false)
        
        wait(2000)
        
        if cfg.settings.enable_rp then
            sampAddChatMessage("[Auto-Delo] Подтверждаю расследование (ENTER)...", 0xFFFFAA00)
        end
        
        setVirtualKeyDown(vkeys.VK_RETURN, true)
        wait(80)
        setVirtualKeyDown(vkeys.VK_RETURN, false)
        
        sampAddChatMessage("[Auto-Delo] Первичные действия выполнены. Улики сохраняются автоматически.", 0xFF00FF00)
        sampAddChatMessage("[Auto-Delo] В окне CEF наведите курсор на поле ввода и нажмите: ALT+1 (Дата) или ALT+2 (Оружие).", 0xFFFFAA00)
    end)
end

function stopInvestigation(reason)
    isRunning = false
    if activeThread and activeThread:status() ~= 'dead' then
        activeThread:terminate()
    end
    sampAddChatMessage("[Auto-Delo] " .. tostring(reason), 0xFFFF0000)
end

function pasteToCef(text_to_paste, field_type)
    if activeThread and activeThread:status() ~= 'dead' then activeThread:terminate() end
    
    activeThread = lua_thread.create(function()
        if cfg.settings.enable_rp then
            if field_type == "date" then
                sampSendChat("/me достаёт из подсумка бланк для расследования и ручку")
                wait(1500)
                sampSendChat("/me записывает в бланк точную дату и время убийства")
            elseif field_type == "weapon" then
                sampSendChat("/do Найдено орудие убийства.")
                wait(1500)
                sampSendChat("/me записывает в бланк орудие убийства")
            end
            wait(500)
        end

        setRussianLayout()
        wait(150)

        setClipboardText(text_to_paste)
        wait(50)

        setVirtualKeyDown(0x01, true)
        wait(50)
        setVirtualKeyDown(0x01, false)
        wait(150)

        setVirtualKeyDown(0x11, true)
        setVirtualKeyDown(0x56, true)
        wait(50)
        setVirtualKeyDown(0x56, false)
        setVirtualKeyDown(0x11, false)
        
        sampAddChatMessage("[Auto-Delo] Успешно вставлено в CEF: " .. tostring(text_to_paste), 0xFF00FF00)

        if field_type == "weapon" then
            if cfg.settings.enable_rp then
                wait(2000)
                sampSendChat("/do Бланк расследования убийства полностью заполнен.")
                wait(1500)
                sampSendChat("/todo Отлично, расследование окончено*убирая бланк в карман")
            end
            sampAddChatMessage("[Auto-Delo] Расследование успешно завершено!", 0xFF00FF00)
            isRunning = false
        end
    end)
end

function cleanText(text)
    if not text then return "" end
    text = text:gsub("{%x+}", ""):gsub("%[%x+%]", "")
    return text:match("^%s*(.-)%s*$") or text
end

function parseEvidence(text)
    local clean = cleanText(text)
    
    local date, time = clean:match("(%d?%d%.%d?%d%.%d%d%d%d)%s+(%d?%d:%d?%d)")
    if date and time then
        savedDate = date .. " " .. time
        sampAddChatMessage("[Auto-Delo] Собранная дата/время: " .. savedDate, 0xFF00FFFF)
    end

    local weapon = clean:match("Орудие убийства:%s*([^\n]+)")
    if weapon then
        weapon = cleanText(weapon)
        if weapon:find("Неизвестно") then weapon = "Неизвестно (Снятие отпечатков)" end
        savedWeapon = weapon
        sampAddChatMessage("[Auto-Delo] Собранное оружие: " .. savedWeapon, 0xFF00FFFF)
    end
end

function sampex.onServerMessage(color, text)
    if not isRunning then return end
    parseEvidence(text)
end

function sampex.onShowDialog(dialogId, style, title, button1, button2, text)
    if not isRunning then return end
    parseEvidence(title .. "\n" .. text)

    if title:find("ДАТА И ВРЕМЯ УБИЙСТВА") or text:find("Введите дату и время") then
        if savedDate then
            if activeThread and activeThread:status() ~= 'dead' then activeThread:terminate() end
            activeThread = lua_thread.create(function()
                if cfg.settings.enable_rp then
                    sampSendChat("/me достаёт из подсумка бланк для расследования и ручку")
                    wait(1500)
                    sampSendChat("/me записывает в бланк точную дату и время убийства")
                    wait(1000)
                end
                sampSendDialogResponse(dialogId, 1, 0, savedDate)
            end)
            return false
        end
    end

    if title:find("ОРУЖИЕ УБИЙСТВА") or text:find("Введите орудие убийства") then
        if savedWeapon then
            if activeThread and activeThread:status() ~= 'dead' then activeThread:terminate() end
            activeThread = lua_thread.create(function()
                if cfg.settings.enable_rp then
                    sampSendChat("/do Найдено орудие убийства.")
                    wait(1500)
                    sampSendChat("/me записывает в бланк орудие убийства")
                    wait(1000)
                end
                sampSendDialogResponse(dialogId, 1, 0, savedWeapon)
                if cfg.settings.enable_rp then
                    wait(1500)
                    sampSendChat("/do Бланк расследования убийства полностью заполнен.")
                    wait(1500)
                    sampSendChat("/todo Отлично, расследование окончено*убирая бланк в карман")
                end
                sampAddChatMessage("[Auto-Delo] Расследование успешно завершено!", 0xFF00FF00)
                isRunning = false
            end)
            return false
        end
    end
end