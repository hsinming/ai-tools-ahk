; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/hsinming/ai-tools-ahk
; based on https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0
#singleInstance force
#Include "_jxon.ahk"
#include "_Cursor.ahk"
#Include "_MD2HTML.ahk"

Persistent
SendMode "Input"

;# init setup
if not (FileExist("settings.ini")) {
    api_key := InputBox("Enter your OpenAI API key", "AI-Tools-AHK : Setup", "W400 H100").value
    if (api_key == "") {
        MsgBox("To use this script, you need to enter an OpenAI key. Please restart the script and try again.")
        ExitApp
    }
    FileCopy("settings.ini.default", "settings.ini")
    IniWrite(api_key, ".\settings.ini", "settings", "default_api_key")
}
RestoreCursor()


;# globals
_running := false
_settingsCache := Map()
_lastModified := FileGetTime("./settings.ini")
_displayResponse := false
_activeWin := ""
_oldClipboard := ""
_debug := ToBool(GetSetting("settings", "debug", "false"))
_reload_on_change := ToBool(GetSetting("settings", "reload_on_change", "false"))

;#
CheckSettings()

;# menu
InitPopupMenu()
InitTrayMenu()

;# hotkeys

HotKey GetSetting("settings", "hotkey_1"), (*) => (
    SelectText()
    PromptHandler(GetSetting("settings", "hotkey_1_prompt")))

HotKey GetSetting("settings", "hotkey_2"), (*) => (
    SelectText()
    ShowPopupMenu())

HotKey GetSetting("settings", "menu_hotkey"), (*) => (
    ShowPopupMenu())

;###

ShowPopupMenu() {
    global _iMenu
    _iMenu.Show()
}

PromptHandler(promptName) {
    global _running, _startTime

    try {
        if (_running) {            
            ;MsgBox "Already running. Please wait for the current request to finish."
            Reload
            return
        }

        _running := true
        _startTime := A_TickCount

        ShowWaitTooltip()
        SetSystemCursor(GetSetting("settings", "cursor_wait_file", "wait"))

        prompt := GetSetting(promptName, "prompt")
        promptEnd := GetSetting(promptName, "prompt_end")
        mode := GetSetting(promptName, "mode", GetSetting("settings", "default_mode"))
        
        try {
            input := GetTextFromClip()
        } catch {
            _running := false
            RestoreCursor()
            return
        }

        CallAPI(mode, promptName, prompt, input, promptEnd)

    } catch as err {
        _running := false
        RestoreCursor()
        MsgBox Format("{1}: {2}.`n`nFile:`t{3}`nLine:`t{4}`nWhat:`t{5}", type(err), err.Message, err.File, err.Line, err.What), , 16
    }
}

;###

SelectText() {
    global _oldClipboard := A_Clipboard  ; 保存原剪貼簿內容

    A_Clipboard := ""  ; 清空剪貼簿
    Send("^c")  ; 嘗試複製當前選取的文字
    ClipWait(1)  ; 等待剪貼簿更新

    text := A_Clipboard
    if StrLen(text) > 0 {
        return  ; 如果成功複製，則直接返回
    }

    ; 使用 Map 來存放應用程式對應的選取方式
    selectionMethods := Map(
        "ahk_exe WINWORD.EXE", "^{Up}^+{Down}+{Left}",    ; Word / Outlook - 選取段落
        "ahk_exe OUTLOOK.EXE", "^{Up}^+{Down}+{Left}",
        "ahk_exe notepad++.exe", "{End}{End}+{Home}+{Home}",  ; Notepad++ / VS Code - 選取整行
        "ahk_exe Code.exe", "{End}{End}+{Home}+{Home}",
        "Radiology Information System", "^{Home}^+{End}"  ; NTUH RIS - 選取游標所在的整頁
    )

    ; 檢查目前的應用程式
    for app, selectKeys in selectionMethods {
        if WinActive(app) {
            Send(selectKeys)
            Sleep(50)  ; 等待選取動作完成
            return
        }
    }

    ; 預設選取所有文字
    Send("^a")
    Sleep(50)
}

GetTextFromClip() {
    global _oldClipboard, _activeWin

    _activeWin := WinGetTitle("A")
    if _oldClipboard == "" {
        _oldClipboard := A_Clipboard
    }

    A_Clipboard := ""
    Send "^c"
    ClipWait(2)
    text := A_Clipboard

    if StrLen(text) < 1 {
        Throw ValueError("No text selected", -1)
    } else if StrLen(text) > 64000 {
        Throw ValueError("Text is too long", -1)
    }

    return text
}

GetSetting(section, key, defaultValue := "") {
    global _settingsCache
    
    if (_settingsCache.Has(section . key . defaultValue)) {
        return _settingsCache.Get(section . key . defaultValue)
    } else {
        value := IniRead(".\settings.ini", section, key, defaultValue)
        if IsNumber(value) {
            value := Number(value)
        } else {
            value := UnescapeSetting(value)
        }
        _settingsCache.Set(section . key . defaultValue, value)
        return value
    }
}

GetBody(mode, promptName, prompt, input, promptEnd) {
    body := Map()

    ;; load mode defaults
    model := GetSetting(mode, "model")
    max_tokens := GetSetting(mode, "max_tokens", 4096)
    temperature := GetSetting(mode, "temperature", 1.0)
    frequency_penalty := GetSetting(mode, "frequency_penalty", 0.0)
    presence_penalty := GetSetting(mode, "presence_penalty", 0.0)
    top_p := GetSetting(mode, "top_p", 1)    
    stop := GetSetting(mode, "stop", "")

    ;; load prompt overrides
    model := GetSetting(promptName, "model", model)
    max_tokens := GetSetting(promptName, "max_tokens", max_tokens)
    temperature := GetSetting(promptName, "temperature", temperature)
    frequency_penalty := GetSetting(promptName, "frequency_penalty", frequency_penalty)
    presence_penalty := GetSetting(promptName, "presence_penalty", presence_penalty)
    top_p := GetSetting(promptName, "top_p", top_p)    
    stop := GetSetting(promptName, "stop", stop)

    ;; assemble messages
    messages := []
    prompt_system := GetSetting(promptName, "prompt_system", "")
    if (prompt_system != "") {
        messages.Push(Map("role", "system", "content", prompt_system))
    }
    content := prompt . input . promptEnd
    messages.Push(Map("role", "user", "content", content))
    
    body["messages"] := messages
    body["model"] := model
    body["max_tokens"] := max_tokens
    body["temperature"] := temperature
    body["frequency_penalty"] := frequency_penalty
    body["presence_penalty"] := presence_penalty
    body["top_p"] := top_p    

    return body
}

CallAPI(mode, promptName, prompt, input, promptEnd) {
    global _running
    
    body := GetBody(mode, promptName, prompt, input, promptEnd)
    bodyJson := Jxon_dump(body, 4)
    LogDebug("bodyJson ->`n" bodyJson)

    endpoint := GetSetting(mode, "endpoint")
    apiKey := GetSetting(mode, "api_key", GetSetting("settings", "default_api_key"))

    req := ComObject("Msxml2.ServerXMLHTTP")

    req.open("POST", endpoint, true)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("Authorization", "Bearer " apiKey) ; OpenAI
    req.SetRequestHeader("api-key", apiKey) ; Azure
    req.SetRequestHeader('Content-Length', StrLen(bodyJson))
    req.SetRequestHeader("If-Modified-Since", "Sat, 1 Jan 2000 00:00:00 GMT")
    req.SetTimeouts(0, 0, 0, GetSetting("settings", "timeout", 120) * 1000) ; read, connect, send, receive

    try {
        req.send(bodyJson)
        req.WaitForResponse()

        if (req.status == 0) {
            RestoreCursor()
            _running := false
            MsgBox "Error: Unable to connect to the API. Please check your internet connection and try again.", , 16
            return
        } else if (req.status == 200) { ; OK.
            data := req.responseText
            HandleResponse(data, mode, promptName, input)
        } else {
            RestoreCursor()
            _running := false
            MsgBox "Error: Status " req.status " - " req.responseText, , 16
            return
        }
    } catch as e {
        RestoreCursor()
        _running := false
        MsgBox "Error: " "Exception thrown!`n`nwhat: " e.what "`nfile: " e.file 
        . "`nline: " e.line "`nmessage: " e.message "`nextra: " e.extra, , 16
        return
    }
}

HandleResponse(data, mode, promptName, input) {
    global _running, _oldClipboard, _displayResponse, _activeWin

    try {
        LogDebug("data ->`n" data)

        var := Jxon_Load(&data)
        text := var.Get("choices")[1].Get("message").Get("content", "")

        if text == "" {
            MsgBox "No text was generated. Consider modifying your input."
            return
        }

        ;; Clean up response text
        text := StrReplace(text, '`r', "") ; remove carriage returns
        replaceSelected := ToBool(GetSetting(promptName, "replace_selected", "true"))
        
        if not replaceSelected {
            responseStart := GetSetting(promptName, "response_start", "")
            responseEnd := GetSetting(promptName, "response_end", "")
            text := input . responseStart . text . responseEnd
        } else {
            ;# Remove leading newlines
            while SubStr(text, 1, 1) == '`n' {
                text := SubStr(text, 2)
            }
            text := Trim(text)
            ;# Remove enclosing quotes
            if SubStr(text, 1, 1) == '"' and SubStr(text, -1) == '"' {
                text := SubStr(text, 2, -1)
            }
        }

        response_type := GetSetting(promptName, "response_type", "popup")
        if _displayResponse or StrLower(response_type) == "popup" {
            MyGui := Gui(, "Response")
            MyGui.SetFont("s13")
            MyGui.Opt("+AlwaysOnTop +Owner +Resize")  ; +Owner avoids a taskbar button.

            ; 設定初始窗口大小（避免顯示時大小為 0）
            InitWidth := 800
            InitHeight := 600            
            margin := 10  ; 控件間的間距
            ButtonWidth := 80  ; 按鈕寬度
            ButtonHeight := 30  ; 按鈕高度

            ; 添加 Tab 控件
            TabCtrl := MyGui.Add("Tab3", "x" margin " y" margin " w" InitWidth - 2*margin " h" InitHeight - 2*margin - ButtonHeight - 2*margin, ["Web View", "Text View"])
            
            ; 設定頁籤內控件的基準 y 座標，向下移動一點點，避免被標籤遮擋
            tabYOffset := 25  ; 調整此值讓內容完整顯示

            ; -------------------
            ; Web View (頁籤1)
            ; -------------------
            TabCtrl.UseTab(1) ; 選擇第一個頁籤

            ; 在第一個頁籤添加 ActiveX 控件
            ogcActiveXWBC := MyGui.Add("ActiveX", "x" margin " y" tabYOffset + margin " w" InitWidth - 4*margin " h" InitHeight - 4*margin - ButtonHeight - 2*margin, "Shell.Explorer")
            css := FileRead("style.css")
            options := {css: css, font_name: "Segoe UI", font_size: 16, font_weight: 400, line_height: "1.6"}
            html := make_html(text, options, true)
            WB := ogcActiveXWBC.Value
            WB.Navigate("about:blank")            
            WB.document.write(html)

            ; -------------------
            ; Text View (頁籤2)
            ; -------------------
            TabCtrl.UseTab(2)

            xEdit := MyGui.Add("Edit", "x" margin " y" tabYOffset + margin " w" InitWidth - 4*margin " h" InitHeight - 4*margin - ButtonHeight - 2*margin " vMyEdit Wrap", text)

            ; 返回到 Tab 控件
            TabCtrl.UseTab()

            ; 添加 Copy 和 Close 按鈕
            xCopy := MyGui.Add("Button", "x" InitWidth - ButtonWidth * 2 - 2*margin " y" InitHeight - ButtonHeight - 2*margin " w" ButtonWidth " h" ButtonHeight, "Copy")
            xCopy.OnEvent("Click", (*) => CopyText(xEdit))

            xClose := MyGui.Add("Button", "x" InitWidth - ButtonWidth - margin " y" InitHeight - ButtonHeight - 2*margin " w" ButtonWidth " h" ButtonHeight " Default", "Close")
            xClose.OnEvent("Click", (*) => MyGui.Destroy())

            ; 顯示 GUI
            MyGui.Show("w" InitWidth " h" InitHeight " NoActivate Center")

            ; 設置 GUI 大小變更事件
            MyGui.OnEvent("Size", Gui_Size)
        } else {
            WinActivate(_activeWin)
            A_Clipboard := text
            send "^v"
        }

        _running := false
        Sleep 500       
        
    } finally {
        _running := false
        A_Clipboard := _oldClipboard
        _oldClipboard := ""
        RestoreCursor()
    }
    
    Gui_Size(thisGui, MinMax, Width, Height) {  
        if MinMax == -1  ; 如果最小化，則不做任何操作
            return
    
        ; 計算頁籤控件的大小和位置
        TabCtrlWidth := Width - 2 * margin
        TabCtrlHeight := Height - 2 * margin - ButtonHeight - margin
    
        ; 調整頁籤控件大小
        TabCtrl.Move(margin, margin, TabCtrlWidth, TabCtrlHeight)
    
        ; 計算頁籤內部控件的大小和位置
        ControlWidth := TabCtrlWidth - 2 * margin
        ControlHeight := TabCtrlHeight - 2 * margin
    
        ; 調整 ActiveX 控件大小
        ogcActiveXWBC.Move(margin, tabYOffset + margin, ControlWidth, ControlHeight)
    
        ; 調整 Edit 控件大小
        xEdit.Move(margin, tabYOffset + margin, ControlWidth, ControlHeight)
    
        ; 調整 Copy 按鈕位置
        xCopy.Move(Width - ButtonWidth * 2 - 2 * margin, Height - ButtonHeight - margin, ButtonWidth, ButtonHeight)
    
        ; 調整 Close 按鈕位置
        xClose.Move(Width - ButtonWidth - margin, Height - ButtonHeight - margin, ButtonWidth, ButtonHeight)
    }
    
    CopyText(edit) {
        A_Clipboard := edit.Text
        MouseGetPos(&mouseX, &mouseY)
        ToolTip("✔ Copied!", mouseX + 10, mouseY + 10)  ; 在游標附近顯示提示
        SetTimer () => ToolTip(), -1000  ; 設定 1 秒後自動清除 ToolTip
    }
}

InitPopupMenu() {
    global _iMenu := Menu()  ; Create a new menu object.
    global _displayResponse
    iMenuItemParms := Map()

    _iMenu.Add("&`` - Display response in new window", NewWindowCheckHandler)
    _iMenu.Add()  ; Add a separator line.

    menu_items := IniRead("./settings.ini", "popup_menu")

    id := 1
    loop parse menu_items, "`n" {
        v_promptName := A_LoopField
        if (v_promptName != "" and SubStr(v_promptName, 1, 1) != "#") {
            if (v_promptName == "-") {
                _iMenu.Add()  ; Add a separator line.
            } else {
                menu_text := GetSetting(v_promptName, "menu_text", v_promptName)
                if (RegExMatch(menu_text, "^[^&]*&[^&]*$") == 0) {
                    if (id == 10)
                        keyboard_shortcut := "&0 - "
                    else if (id > 10)
                        keyboard_shortcut := "&" Chr(id + 86) " - "
                    else
                        keyboard_shortcut := "&" id " - "
                    menu_text := keyboard_shortcut menu_text
                    id++
                }

                _iMenu.Add(menu_text, MenuHandler)
                item_count := DllCall("GetMenuItemCount", "Ptr", _iMenu.Handle)
                iMenuItemParms[item_count] := v_promptName
            }
        }
    }
    MenuHandler(ItemName, ItemPos, MyMenu) {
        PromptHandler(iMenuItemParms[ItemPos])
    }
    NewWindowCheckHandler(*) {
        _iMenu.ToggleCheck("&`` - Display response in new window")
        _displayResponse := !_displayResponse
        _iMenu.Show()
    }
}

InitTrayMenu() {
    tray := A_TrayMenu
    tray.Add()
    tray.Add("Open settings", OpenSettings)
    tray.Add("Reload settings", ReloadSettings)
    tray.Add()
    tray.Add("Github readme", OpenGithub)
    TrayAddStartWithWindows(tray)
}

TrayAddStartWithWindows(tray) {
    tray.Add("Start with Windows", StartWithWindowsAction)
    SplitPath A_ScriptFullPath, , , , &script_name
    _sww_shortcut := A_Startup "\" script_name ".lnk"
    if FileExist(_sww_shortcut) {
        FileGetShortcut _sww_shortcut, &target  ;# update if script has moved
        if (target != A_ScriptFullPath) {
            FileCreateShortcut A_ScriptFullPath, _sww_shortcut
        }
        tray.Check("Start with Windows")
    } else {
        tray.Uncheck("Start with Windows")
    }
    StartWithWindowsAction(*) {
        if FileExist(_sww_shortcut) {
            FileDelete(_sww_shortcut)
            tray.Uncheck("Start with Windows")
            TrayTip("Start With Windows", "Shortcut removed", 5)
        } else {
            FileCreateShortcut(A_ScriptFullPath, _sww_shortcut)
            tray.Check("Start with Windows")
            TrayTip("Start With Windows", "Shortcut created", 5)
        }
    }
}

OpenGithub(*) {
    Run "https://github.com/hsinming/ai-tools-ahk#usage"
}

OpenSettings(*) {
    Run A_ScriptDir . "\settings.ini"
}

ReloadSettings(*) {
    global _settingsCache
    TrayTip("Reload Settings", "Reloading settings...", 5)
    _settingsCache.Clear()
    InitPopupMenu()
}

UnescapeSetting(obj) {
    obj := StrReplace(obj, "\n", "`n")
    return obj
}

ShowWaitTooltip() {
    global _running, _startTime
    if (_running) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
        SetTimer () => ShowWaitTooltip(), -50
    } else {
        ToolTip()
    }
}

CheckSettings() {
    global _lastModified, _reload_on_change
    if (_reload_on_change and FileExist("./settings.ini")) {
        lastModified := FileGetTime("./settings.ini")
        if (lastModified != _lastModified) {
            _lastModified := lastModified
            TrayTip("Settings Updated", "Restarting...", 5)
            Sleep 2000
            Reload
        }
        SetTimer () => CheckSettings(), -10000   ; Check every 10 seconds
    }
}

LogDebug(msg) {
    global _debug
    if (_debug != false) {
        now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logMsg := "[" . now . "] " . msg . "`n"
        FileAppend(logMsg, "./debug.log")
    }
}

ToBool(value) {
    return StrLower(String(value)) == "true"
}