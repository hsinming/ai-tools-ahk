; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/hsinming/ai-tools-ahk
; based on https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0+
#singleInstance force
#Include "_JXON.ahk"
#include "_Cursor.ahk"
#Include "_MD_Gen.ahk"
Persistent
SendMode "Input"

;# globals
_settingFile := ".\settings.ini"
_running := false
_settingsCache := Map()
_lastModified := FileGetTime(_settingFile)
_displayResponse := false
_activeWin := ""
_oldClipboard := ""
_debug := ToBool(GetSetting("settings", "debug", "false"))
_reload_on_change := ToBool(GetSetting("settings", "reload_on_change", "true"))
_styleCSS := FileRead(".\style.css")


;# init setup
if not (FileExist(_settingFile)) {
    api_key := InputBox("Enter your API key", "AI-Tools-AHK : Setup", "W400 H100").value
    if (api_key == "") {
        MsgBox("To use this script, you need to enter an API key. Please restart the script and try again.")
        ExitApp
    }
    FileCopy("settings.ini.default", _settingFile)
    IniWrite(api_key, _settingFile, "settings", "default_api_key")
}
RestoreCursor()

;# check settings every 10 seconds
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
        
        try {
            input := GetSelectedText()
        } catch as err {
            RestoreCursor()
            _running := false            
            MsgBox Format("{1}: {2}", Type(err), err.Message), , 16
            return
        }        
        
        mode := GetSetting(promptName, "mode", GetSetting("settings", "default_mode"))
        CallAPI(mode, promptName, input)

    } catch as err {
        RestoreCursor()
        _running := false        
        MsgBox Format("{1}: {2}.`n`nFile:`t{3}`nLine:`t{4}`nWhat:`t{5}", Type(err), err.Message, err.File, err.Line, err.What), , 16
    }
}

IniReadSection(section) {
    global _settingsCache, _settingFile

    ; Return cached result if available
    if (_settingsCache.Has(section)) {
        return _settingsCache[section]
    }

    result := Map()
    insideSection := false

    Loop Read _settingFile {
        line := Trim(A_LoopReadLine)
        if (line = "" || SubStr(line, 1, 1) = ";")  ; Skip empty lines and comments
            continue
        if (RegExMatch(line, "^\[(.*)\]$", &match)) {  ; Detect section header
            insideSection := (match[1] = section)
            continue
        }
        if insideSection && RegExMatch(line, "^(.*?)=(.*)$", &match) {
            result[Trim(match[1])] := Trim(match[2])  ; Store key-value pair
        }
    }

    _settingsCache[section] := result  ; Cache the result
    return result
}

RestoreClipboard() {
    global _oldClipboard
    A_Clipboard := _oldClipboard
    _oldClipboard := ""
}

BackupClipboard() {
    global _oldClipboard
    ; Backup clipboard only if it's not already backed up
    if _oldClipboard == "" {
        _oldClipboard := A_Clipboard
    }
}

GetSelectedTextFromControl() {
    focusedControl := ControlGetFocus("A")  ; Get the ClassNN of the focused control
    if !focusedControl
        return ""  ; No control is focused, return empty string

    hwnd := ControlGetHwnd(focusedControl, "A")  ; Get the HWND of the focused control

    ; Send EM_GETSEL message to get the selection range
    result := DllCall("User32.dll\SendMessageW", "Ptr", hwnd, "UInt", 0xB0, "Ptr", 0, "Ptr", 0, "UInt")

    selStart := result & 0xFFFF  ; Lower 16 bits contain the start index
    selEnd := result >> 16       ; Upper 16 bits contain the end index

    ; Retrieve the full text of the control
    controlText := ControlGetText(hwnd, "A")

    return SubStr(controlText, selStart + 1, selEnd - selStart)
}

SelectText() {
    BackupClipboard()

    ; 1️⃣ Try to copy selected text using Ctrl+C
    A_Clipboard := ""  ; Clear clipboard
    Send("^c")
    ClipWait(2)

    if A_Clipboard != "" { ; If text was copied, restore clipboard and exit
        RestoreClipboard()
        return
    }
    
    ; 2️⃣ Try predefined selection methods from settings
    selectionMethods := IniReadSection("selection_methods")
    for identifier, selectKeys in selectionMethods {
        if WinActive(identifier) {  ; If the active window matches a rule
            Send(selectKeys)
            Sleep(50)  ; Allow time for selection to complete
            RestoreClipboard()
            return
        }
    }

    ; 3️⃣ Final fallback: Select all text using Ctrl+A
    Send("^a")
    Sleep(50)
    RestoreClipboard()
}

GetSelectedText() {
    global _activeWin
    _activeWin := WinGetTitle("A")    ; Used in HandleResponse()

    ; Initialize text variable
    text := ""

    ; 1. Try copying text using Ctrl+C
    BackupClipboard()
    A_Clipboard := ""
    Send("^c")
    ClipWait(2)
    text := A_Clipboard    
    RestoreClipboard()

    ; 2. If clipboard is empty, try getting selected text from the focused control
    if StrLen(text) < 1
        text := GetSelectedTextFromControl()

    ; 3. If still empty, try getting all text from the focused control
    if StrLen(text) < 1 {
        focusedControl := ControlGetFocus("A")  ; Get focused control's identifier
        if focusedControl
            text := ControlGetText(focusedControl, "A")
    }    

    ; Final checks:
    if StrLen(text) > 128000
        Throw ValueError("Text is too long", -1)
    
    if StrLen(text) < 1
        Throw ValueError("No text selected", -1)

    return text
}

GetSetting(section, key, defaultValue := "") {
    global _settingsCache, _settingFile
    
    if (_settingsCache.Has(section . key . defaultValue)) {
        return _settingsCache.Get(section . key . defaultValue)
    } else {
        value := IniRead(_settingFile, section, key, defaultValue)
        if IsNumber(value) {
            value := Number(value)
        } else {
            value := UnescapeSetting(value)
        }
        _settingsCache.Set(section . key . defaultValue, value)
        return value
    }
}

GetBody(mode, promptName, input) {
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
    
    prompt := GetSetting(promptName, "prompt")
    promptEnd := GetSetting(promptName, "prompt_end", "")
    content := prompt . input . promptEnd
    messages.Push(Map("role", "user", "content", content))
    
    body := Map()
    body["messages"] := messages
    body["model"] := model
    body["max_tokens"] := max_tokens
    body["temperature"] := temperature
    body["frequency_penalty"] := frequency_penalty
    body["presence_penalty"] := presence_penalty
    body["top_p"] := top_p    

    return body
}

CallAPI(mode, promptName, input) {
    global _running   
    
    body := GetBody(mode, promptName, input)
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
            response := req.responseText   ; UTF-8 by default
            HandleResponse(response, mode, promptName, input)
        } else {
            RestoreCursor()
            _running := false
            MsgBox "Error: Status " req.status " - " req.responseText, , 16
            return
        }
    } catch as e {
        RestoreCursor()
        _running := false
        MsgBox "Error: " "Exception thrown!`n`nwhat: " e.What "`nfile: " e.File 
        . "`nline: " e.Line "`nmessage: " e.Message "`nextra: " e.Extra, , 16
        return
    }
}

HandleResponse(response, mode, promptName, input) {
    global _running, _displayResponse, _activeWin, _styleCSS

    try {
        response_object := Jxon_Load(&response)
        LogDebug("response_object ->`n" Jxon_dump(response_object, 4))  
        
        text := response_object.Get("choices")[1].Get("message").Get("content", "")

        if text == "" {
            MsgBox "No text was generated. Consider modifying your input."
            return
        }

        ;; Clean up response text
        text := StrReplace(text, '`r', "") ; remove carriage returns
        replaceSelected := ToBool(GetSetting(promptName, "replace_selected", "true"))
        
        if not replaceSelected {  ; Append Mode
            responseStart := GetSetting(promptName, "response_start", "")
            responseEnd := GetSetting(promptName, "response_end", "")
            text := input . responseStart . text . responseEnd
        } else {  ; Replace Mode
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

            ; Set the initial size of the GUI
            InitWidth := 800
            InitHeight := 600            
            margin := 10  
            ButtonWidth := 80
            ButtonHeight := 30

            ; Add Tab control
            TabCtrl := MyGui.Add("Tab3", "x" margin " y" margin " w" InitWidth - 2*margin " h" InitHeight - 2*margin - ButtonHeight - 2*margin, ["Web View", "Text View"])
            
            ; Set Y offset to avoid overlapping with the tab control
            tabYOffset := 25
            
            ; -------------------
            ; Web View (Tab 1)
            ; -------------------
            TabCtrl.UseTab(1)

            ; Add ActiveX control
            ogcActiveXWBC := MyGui.Add("ActiveX", "x" margin " y" tabYOffset + margin " w" InitWidth - 4*margin " h" InitHeight - 4*margin - ButtonHeight - 2*margin, "Shell.Explorer")            
            options := {css: _styleCSS, font_name: "Segoe UI", font_size: 16, font_weight: 400, line_height: "1.6"}
            html := make_html(text, options, true)
            WB := ogcActiveXWBC.Value
            WB.Navigate("about:blank")            
            WB.document.write(html)

            ; -------------------
            ; Text View (Tab 2)
            ; -------------------
            TabCtrl.UseTab(2)

            ; Add Edit control
            xEdit := MyGui.Add("Edit", "x" margin " y" tabYOffset + margin " w" InitWidth - 4*margin " h" InitHeight - 4*margin - ButtonHeight - 2*margin " vMyEdit Wrap", text)

            ; Add controls outside of the Tab control
            TabCtrl.UseTab()

            ; Add Copy button and Close button
            xCopy := MyGui.Add("Button", "x" InitWidth - ButtonWidth * 2 - 2*margin " y" InitHeight - ButtonHeight - 2*margin " w" ButtonWidth " h" ButtonHeight, "Copy")
            xCopy.OnEvent("Click", (*) => CopyText(xEdit))

            xClose := MyGui.Add("Button", "x" InitWidth - ButtonWidth - margin " y" InitHeight - ButtonHeight - 2*margin " w" ButtonWidth " h" ButtonHeight " Default", "Close")
            xClose.OnEvent("Click", (*) => MyGui.Destroy())

            ; Show GUI 
            MyGui.Show("w" InitWidth " h" InitHeight " NoActivate Center")

            ; Set Resize event
            MyGui.OnEvent("Size", Gui_Size)
        } else {
            WinActivate(_activeWin)            
            BackupClipboard()
            A_Clipboard := Trim(text, "`n")  ; Remove leading/trailing newlines
            Send("^v")
            Sleep 500
            RestoreClipboard()    
        }        
    } finally {
        RestoreCursor()
        _running := false        
    }
    
    Gui_Size(thisGui, MinMax, Width, Height) {  
        if MinMax == -1  ; if minimized, do nothing
            return
    
        ; Calculate the new size of the GUI
        TabCtrlWidth := Width - 2 * margin
        TabCtrlHeight := Height - 2 * margin - ButtonHeight - margin
    
        ; Move the Tab control to the new position
        TabCtrl.Move(margin, margin, TabCtrlWidth, TabCtrlHeight)
    
        ; Calculate the new size of the ActiveX, Edit, Copy, and Close controls
        ControlWidth := TabCtrlWidth - 2 * margin
        ControlHeight := TabCtrlHeight - 2 * margin
    
        ; Move the ActiveX, Edit, Copy, and Close controls to the new position    
        ogcActiveXWBC.Move(margin, tabYOffset + margin, ControlWidth, ControlHeight)
        xEdit.Move(margin, tabYOffset + margin, ControlWidth, ControlHeight)
        xCopy.Move(Width - ButtonWidth * 2 - 2 * margin, Height - ButtonHeight - margin, ButtonWidth, ButtonHeight)
        xClose.Move(Width - ButtonWidth - margin, Height - ButtonHeight - margin, ButtonWidth, ButtonHeight)
    }
    
    CopyText(edit) {
        A_Clipboard := edit.Text
        MouseGetPos(&mouseX, &mouseY)
        ToolTip("✔ Copied!", mouseX + 10, mouseY + 10)  ; Show a tooltip near the mouse cursor
        SetTimer () => ToolTip(), -1000  ; Set a timer to hide the tooltip after 1 second
    }
}

InitPopupMenu() {
    global _iMenu := Menu()  ; Create a new menu object.
    global _displayResponse, _settingFile
    iMenuItemParms := Map()

    _iMenu.Add("&`` - Display response in new window", NewWindowCheckHandler)
    _iMenu.Add()  ; Add a separator line.

    menu_items := IniRead(_settingFile, "popup_menu")

    id := 1
    Loop Parse menu_items, "`n" {
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
    global _settingFile
    Run A_ScriptDir . _settingFile
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
    global _lastModified, _reload_on_change, _settingFile
    if (_reload_on_change and FileExist(_settingFile)) {
        lastModified := FileGetTime(_settingFile)
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