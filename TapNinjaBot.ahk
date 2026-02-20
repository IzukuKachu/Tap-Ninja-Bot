#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode 2
A_BatchLines := -1
ProcessSetPriority "High"

; ============================================================
; Tap Ninja Bot (v2) - configurable via GUI + INI settings
; ============================================================

; ---------- Game window title ----------
global gTitle := "Tap Ninja"

; ---------- Config ----------
global gCfgFile := A_ScriptDir "\TapNinjaBot.ini"
global gCfg := LoadOrCreateConfigIni(gCfgFile)
InitFlyCounts()

; ---------- Runtime State ----------
global gRunning := false
global gFirstStartCaptureDone := false

global gPausedUntilMain := 0
global gPausedUntilGreen := 0

; pending green click (non-blocking pre-click delay)
global gPendingGreen := false
global gPendingAt := 0
global gPendingX := 0, gPendingY := 0
global gPendingKind := ""  ; "House" or "Upgrades"

; counters
global gFlyTotal := 0
global gFlyCounts := Map()   ; key: fly name, value: count
global gClicksHouse := 0
global gClicksUpgrades := 0

; page state
global gPageState := "Upgrades"
global gNextPageSwap := A_TickCount + gCfg.timing.pageMs
global gSwapDue := false

; enemy/attack runtime
global gLastEnemySeen := 0
global gNextRopeAt := 0
global gNextShurAt := 0


; starting values HBITMAP handles
global gHbm1 := 0, gHbm2 := 0
global gPh1 := 0, gPh2 := 0

CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

; ============================================================
; GUI
; ============================================================

global guiW := 220

; --- Pre-calc Starting Values picture sizes (for compact main window height) ---
global padX := 18
global picW := guiW - (padX*2)
global sv1 := gCfg.startingValues.sv1, sv2 := gCfg.startingValues.sv2
global sv1_w := Abs(sv1.x2 - sv1.x1), sv1_h := Abs(sv1.y2 - sv1.y1)
global sv2_w := Abs(sv2.x2 - sv2.x1), sv2_h := Abs(sv2.y2 - sv2.y1)
global pic1H := Max(1, Round(sv1_h * (picW / Max(1, sv1_w))))
global pic2H := Max(1, Round(sv2_h * (picW / Max(1, sv2_w))))
; Main window height based on content (tabs + starting values pics)
global guiH := Max(320, 340 + pic1H + 6 + pic2H + 40)
global tabH := guiH - 16

global StatusGui := Gui("+AlwaysOnTop +ToolWindow", "Tap Ninja Bot")
StatusGui.BackColor := "202020"
StatusGui.SetFont("s10 cFFFFFF", "Segoe UI")

global Tabs := StatusGui.AddTab3("x8 y8 w" (guiW-16) " h" tabH, ["Main", "Fly Details"])

; -------------------- Main Tab --------------------
Tabs.UseTab("Main")

global StatusLine1 := StatusGui.AddText("x18 y44 w" (guiW-120) " Center", "")
StatusLine1.OnEvent("Click", (*) => ToggleRun())

; Settings opens in a separate window (keeps main GUI compact)
global BtnOpenSettings := StatusGui.AddButton("x" (guiW-92) " y42 w74 h24", "Settings")
BtnOpenSettings.OnEvent("Click", (*) => OpenSettings())

global ResetLine := StatusGui.AddText("x18 y66 w" (guiW-36) " Center cB0B0B0", "RESET (F9)")
ResetLine.OnEvent("Click", (*) => ResetAll())

global StatusLine2 := StatusGui.AddText("x18 y90 w" (guiW-36) " Center cFFFFFF", "")
global FlyTotalLine := StatusGui.AddText("x18 y114 w" (guiW-36) " Center cFFFFFF", "")

global HouseLine := StatusGui.AddText("x18 y138 w" (guiW-36) " Center c0CB200", "")
global UpgLine   := StatusGui.AddText("x18 y160 w" (guiW-36) " Center c0CB200", "")

global CbEnableHouse := StatusGui.AddCheckbox("x28 y188 w210 cFFFFFF", "Enable House")
global CbEnableUpg   := StatusGui.AddCheckbox("x28 y210 w210 cFFFFFF", "Enable Upgrades")
CbEnableHouse.Value := gCfg.enable.enableHouse ? 1 : 0
CbEnableUpg.Value   := gCfg.enable.enableUpgrades ? 1 : 0
CbEnableHouse.OnEvent("Click", (*) => (gCfg.enable.enableHouse := !!CbEnableHouse.Value, SaveConfigIniSafe()))
CbEnableUpg.OnEvent("Click", (*) => (gCfg.enable.enableUpgrades := !!CbEnableUpg.Value, SaveConfigIniSafe()))

global AutoEnergyCb := StatusGui.AddCheckbox("x28 y238 w210 cFFFFFF", "Auto Energy")
AutoEnergyCb.Value := gCfg.enable.autoEnergy ? 1 : 0
AutoEnergyCb.OnEvent("Click", (*) => (gCfg.enable.autoEnergy := !!AutoEnergyCb.Value, SaveConfigIniSafe()))


global AutoRopeCb := StatusGui.AddCheckbox("x28 y266 w210 cFFFFFF", "Auto Rope Hook (Q)")
AutoRopeCb.Value := gCfg.enable.autoRopeHook ? 1 : 0
AutoRopeCb.OnEvent("Click", (*) => (gCfg.enable.autoRopeHook := !!AutoRopeCb.Value, SaveConfigIniSafe()))

global AutoShurikenCb := StatusGui.AddCheckbox("x28 y288 w210 cFFFFFF", "Auto Shuriken Vortex (W)")
AutoShurikenCb.Value := gCfg.enable.autoShuriken ? 1 : 0
AutoShurikenCb.OnEvent("Click", (*) => (gCfg.enable.autoShuriken := !!AutoShurikenCb.Value, SaveConfigIniSafe()))

global StartLabel := StatusGui.AddText("x18 y318 w" (guiW-36) " Center cB0B0B0", "Starting values")

global Pic1 := StatusGui.AddPicture("x" padX " y340 w" picW " h" pic1H, "")
global Pic2 := StatusGui.AddPicture("x" padX " y" (340 + pic1H + 6) " w" picW " h" pic2H, "")

; placeholders keep size stable
gPh1 := CreateSolidBitmap(picW, pic1H, 0x202020)
gPh2 := CreateSolidBitmap(picW, pic2H, 0x202020)
Pic1.Value := "HBITMAP:*" gPh1
Pic2.Value := "HBITMAP:*" gPh2

; -------------------- Fly Details Tab --------------------
Tabs.UseTab("Fly Details")

StatusGui.AddText("x18 y44 w" (guiW-36) " Center cB0B0B0", "Fly click breakdown")

; dynamic fly breakdown lines (built from config list)
global gFlyDetailLines := []
BuildFlyDetailLines()

; Done building tabs

Tabs.UseTab()

; show window
StatusGui.Show("x8 y27 w" guiW " h" guiH " NoActivate")
UpdateStatus()
UpdateFlyDetails()

; ---------- Timer ----------
SetTimer Tick, gCfg.timing.scanIntervalMs

; ---------- Hotkeys ----------
F8::ToggleRun()
F9::ResetAll()
Esc::ExitApp
OnExit CleanupAllBitmaps

; ============================================================
; Main Loop
; ============================================================

Tick()
{
    global gRunning, gTitle, gCfg
    global gPausedUntilMain, gPausedUntilGreen
    global gPendingGreen, gPendingAt, gPendingX, gPendingY, gPendingKind
    global gPageState, gNextPageSwap, gSwapDue
    global gLastEnemySeen, gNextRopeAt, gNextShurAt

    if !gRunning
        return

    hwnd := WinExist(gTitle)
    if !hwnd
        return

    now := A_TickCount

    ; Auto Energy
    if gCfg.enable.autoEnergy
    {
        static nextAuto := 0
        if now >= nextAuto
        {
            ClickAt(gCfg.coords.autoEnergyX, gCfg.coords.autoEnergyY, true, gCfg.timing.restoreDelayMs)
            nextAuto := now + gCfg.timing.autoEnergyEveryMs
        }
    }

    ; If one or both purchase modes disabled, adjust swapping
    EnsureValidPageState()

    ; detect manual page changes
    detected := DetectPage()
    if (detected != "" && detected != gPageState)
    {
        gPageState := detected
        gSwapDue := false
        gNextPageSwap := now + gCfg.timing.pageMs
        UpdateStatus()
    }

    ; schedule page swap
    if now >= gNextPageSwap
        gSwapDue := true

    ; Handle pending green click first (high priority)
    if gPendingGreen && now >= gPendingAt
    {
        if now < gPausedUntilGreen
            return

        if (gPendingKind = "House" && gCfg.enable.enableHouse)
        {
            if PixelMatches(gCfg.coords.houseGreenX, gCfg.coords.houseGreenY, gCfg.colors.green, gCfg.tols.green)
                DoGreenClick("House", gCfg.coords.houseGreenX, gCfg.coords.houseGreenY)
        }
        else if (gPendingKind = "Upgrades" && gCfg.enable.enableUpgrades)
        {
            if PixelMatches(gCfg.coords.upgGreenX, gCfg.coords.upgGreenY, gCfg.colors.green, gCfg.tols.green)
                DoGreenClick("Upgrades", gCfg.coords.upgGreenX, gCfg.coords.upgGreenY)
        }

        gPendingGreen := false
        gPendingKind := ""
        return
    }

    ; Green detection (high priority)
    if now >= gPausedUntilGreen
    {
        if (gPageState = "House" && gCfg.enable.enableHouse)
        {
            if PixelMatches(gCfg.coords.houseGreenX, gCfg.coords.houseGreenY, gCfg.colors.green, gCfg.tols.green)
            {
                gPendingGreen := true
                gPendingAt := now + gCfg.timing.greenPreClickDelayMs
                gPendingX := gCfg.coords.houseGreenX
                gPendingY := gCfg.coords.houseGreenY
                gPendingKind := "House"
                return
            }
        }
        else if (gPageState = "Upgrades" && gCfg.enable.enableUpgrades)
        {
            if PixelMatches(gCfg.coords.upgGreenX, gCfg.coords.upgGreenY, gCfg.colors.green, gCfg.tols.green)
            {
                gPendingGreen := true
                gPendingAt := now + gCfg.timing.greenPreClickDelayMs
                gPendingX := gCfg.coords.upgGreenX
                gPendingY := gCfg.coords.upgGreenY
                gPendingKind := "Upgrades"
                return
            }
        }
    }

    ; Page swapping (only if no green work is pending/cooldown)
    if gSwapDue && (now >= gPausedUntilGreen)
    {
        if TrySwapPage()
            return
    }

    
; Enemy detection + Auto Attacks (keyboard only)
enemyPresent := false
if gCfg.enemies.Length > 0
{
    ; quick scan for any enemy color in enemy rect
    er := gCfg.enemyRect
    for en in gCfg.enemies
    {
        if PixelSearch(&fx, &fy, er.x1, er.y1, er.x2, er.y2, FlyGet(en, "color"), FlyGet(en, "tol"))
        {
            gLastEnemySeen := now
            break
        }
    }
    if (now - gLastEnemySeen) <= gCfg.timing.enemyHoldMs
        enemyPresent := true
}

if enemyPresent
{
    ; Rope Hook first
    if gCfg.enable.autoRopeHook && now >= gNextRopeAt
    {
        SendAttackKey("q")
        gNextRopeAt := now + gCfg.timing.ropeHookCooldownMs
        return
    }
    ; Shuriken only if rope not ready
    if gCfg.enable.autoShuriken && now >= gNextShurAt && now < gNextRopeAt
    {
        SendAttackKey("w")
        gNextShurAt := now + gCfg.timing.shurikenCooldownMs
        return
    }
}

; Fly clicks (lower priority)
    if now < gPausedUntilMain
        return

    ; scan in order (configured fly list)
    rect := gCfg.flyRect
    for fly in gCfg.flys
    {
        if TryFindAndClickFly(FlyGet(fly, "name"), rect.x1, rect.y1, rect.x2, rect.y2, FlyGet(fly, "color"), FlyGet(fly, "tol"))
            return
    }
}

; ============================================================
; Actions
; ============================================================


ClickAt(x, y, restore := true, restoreDelayMs := 0)
{
    ; Click at screen coords (x,y). Optionally restore previous mouse position after a delay.
    ; Uses real cursor movement + mouse_event to improve detection in games.
    local ox := 0, oy := 0
    if restore
        MouseGetPos &ox, &oy

    DllCall("SetCursorPos", "int", x, "int", y)
    Sleep 20  ; let cursor settle

    ; Left button down/up via mouse_event
    DllCall("mouse_event", "UInt", 0x02, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0) ; down
    Sleep 10
    DllCall("mouse_event", "UInt", 0x04, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0) ; up
    Sleep 10

    if restore
    {
        if restoreDelayMs > 0
            Sleep restoreDelayMs
        DllCall("SetCursorPos", "int", ox, "int", oy)
    }
}


GetGameHwnd()
{
    global gTitle
    global StatusGui, SettingsGui

    hwnds := []
    try hwnds := WinGetList(gTitle)
    catch
        return 0

    for hwnd in hwnds
    {
        ; Skip our own GUIs
        if IsObject(StatusGui) && hwnd = StatusGui.Hwnd
            continue
        if IsObject(SettingsGui) && hwnd = SettingsGui.Hwnd
            continue

        ; Skip AHK GUI windows generally (extra safety)
        try {
            if WinGetClass("ahk_id " hwnd) = "AutoHotkeyGUI"
                continue
        }

        return hwnd
    }
    return 0
}

SendAttackKey(key)
{
    global gCfg

    hwnd := GetGameHwnd()
    if !hwnd
        return

    ; Many games ignore ControlSend; activate briefly and use SendEvent.
    if !WinActive("ahk_id " hwnd)
    {
        WinActivate "ahk_id " hwnd
        WinWaitActive "ahk_id " hwnd, , 0.2
    }

    ; Letters should be sent directly (not wrapped in braces).
    SendEvent key

    if gCfg.timing.attackKeyDelayMs > 0
        Sleep gCfg.timing.attackKeyDelayMs
}


ToggleRun()
{
    global gRunning, gFirstStartCaptureDone
    gRunning := !gRunning

    if gRunning && !gFirstStartCaptureDone
    {
        gFirstStartCaptureDone := true
        CaptureStartingValues()
    }
    UpdateStatus()
}

ResetAll()
{
    global gRunning
    global gFlyTotal, gFlyCounts
    global gClicksHouse, gClicksUpgrades
    global gPausedUntilMain, gPausedUntilGreen
    global gPendingGreen, gPendingKind
    global gPageState, gNextPageSwap, gSwapDue, gCfg

    gRunning := false
    UpdateStatus()
    Sleep 1

    gFlyTotal := 0
    InitFlyCounts()
    gClicksHouse := 0
    gClicksUpgrades := 0

    gPausedUntilMain := 0
    gPausedUntilGreen := 0
    gPendingGreen := false
    gPendingKind := ""

    ; assume Upgrades on reset if enabled, else House if enabled, else Upgrades
    if gCfg.enable.enableUpgrades
        ForceUpgrades()
    else if gCfg.enable.enableHouse
        ForceHouse()
    else
        gPageState := "Upgrades"

    gNextPageSwap := A_TickCount + gCfg.timing.pageMs
    gSwapDue := false

    CaptureStartingValues()

    gRunning := true
    UpdateStatus()
    UpdateFlyDetails()
}

ForceHouse()
{
    global gRunning, gPageState, gNextPageSwap, gCfg, gSwapDue
    if !gRunning
        return
    Send "{1}"
    gPageState := "House"
    gSwapDue := false
    gNextPageSwap := A_TickCount + gCfg.timing.pageMs
    UpdateStatus()
}

ForceUpgrades()
{
    global gRunning, gPageState, gNextPageSwap, gCfg, gSwapDue
    if !gRunning
        return
    Send "{2}"
    gPageState := "Upgrades"
    gSwapDue := false
    gNextPageSwap := A_TickCount + gCfg.timing.pageMs
    UpdateStatus()
}

DoGreenClick(kind, x, y)
{
    global gPausedUntilGreen, gCfg
    global gClicksHouse, gClicksUpgrades

    ClickAt(x, y, true, gCfg.timing.restoreDelayMs)
    gPausedUntilGreen := A_TickCount + gCfg.timing.greenPauseMs

    if kind = "House"
        gClicksHouse += 1
    else
        gClicksUpgrades += 1

    UpdateStatus()
}

TryFindAndClickFly(kind, x1, y1, x2, y2, color, tol)
{
    global gPausedUntilMain, gCfg
    global gFlyTotal, gFlyCounts

    foundX := 0, foundY := 0
    try
    {
        if !PixelSearch(&foundX, &foundY, x1, y1, x2, y2, color, tol)
            return false
    }
    catch
    {
        return false
    }

    ; click fly
    ClickAt(foundX, foundY, true, gCfg.timing.restoreDelayMs)

    gFlyTotal += 1
    if !gFlyCounts.Has(kind)
        gFlyCounts[kind] := 0
    gFlyCounts[kind] += 1

    gPausedUntilMain := A_TickCount + gCfg.timing.mainPauseMs
    UpdateStatus()
    UpdateFlyDetails()
    return true
}


TrySwapPage()
{
    global gPageState, gCfg, gNextPageSwap, gSwapDue

    ; if only one purchase mode enabled, do not swap
    if (gCfg.enable.enableHouse && !gCfg.enable.enableUpgrades)
        return false
    if (gCfg.enable.enableUpgrades && !gCfg.enable.enableHouse)
        return false

    ; if both disabled, no need to swap
    if (!gCfg.enable.enableHouse && !gCfg.enable.enableUpgrades)
        return false

    if gPageState = "House"
        Send "{2}"
    else
        Send "{1}"

    gPageState := (gPageState="House") ? "Upgrades" : "House"
    gSwapDue := false
    gNextPageSwap := A_TickCount + gCfg.timing.pageMs
    UpdateStatus()
    return true
}

EnsureValidPageState()
{
    global gPageState, gCfg
    global gPendingGreen, gPendingKind

    ; If a pending purchase is for a disabled mode, drop it.
    if gPendingGreen
    {
        if (gPendingKind = "House" && !gCfg.enable.enableHouse)
            gPendingGreen := false
        else if (gPendingKind = "Upgrades" && !gCfg.enable.enableUpgrades)
            gPendingGreen := false
        if !gPendingGreen
            gPendingKind := ""
    }
    if (gPageState="House" && !gCfg.enable.enableHouse && gCfg.enable.enableUpgrades)
    {
        Send "{2}"
        gPageState := "Upgrades"
    }
    else if (gPageState="Upgrades" && !gCfg.enable.enableUpgrades && gCfg.enable.enableHouse)
    {
        Send "{1}"
        gPageState := "House"
    }
}

DetectPage()
{
    global gCfg
    ; If either detect matches, return that page.
    if PixelMatches(gCfg.pageDetect.houseX, gCfg.pageDetect.houseY, gCfg.pageDetect.houseColor, gCfg.pageDetect.tol)
        return "House"
    if PixelMatches(gCfg.pageDetect.upgX, gCfg.pageDetect.upgY, gCfg.pageDetect.upgColor, gCfg.pageDetect.tol)
        return "Upgrades"
    return ""
}

PixelMatches(x, y, targetColor, tol)
{
    try c := PixelGetColor(x, y, "RGB")
    catch
        return false
    return ColorNear(c, targetColor, tol)
}

ColorNear(c1, c2, tol)
{
    ; c1/c2 are 0xRRGGBB
    r1 := (c1 >> 16) & 0xFF, g1 := (c1 >> 8) & 0xFF, b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF, g2 := (c2 >> 8) & 0xFF, b2 := c2 & 0xFF
    return (Abs(r1-r2) <= tol) && (Abs(g1-g2) <= tol) && (Abs(b1-b2) <= tol)
}

; ============================================================
; Starting Values Capture (two snippets)
; ============================================================

CaptureStartingValues()
{
    global gCfg, Pic1, Pic2, gHbm1, gHbm2, gPh1, gPh2

    ; free previous
    if gHbm1
        DllCall("DeleteObject", "Ptr", gHbm1), gHbm1 := 0
    if gHbm2
        DllCall("DeleteObject", "Ptr", gHbm2), gHbm2 := 0

    gHbm1 := CaptureRectToBitmap(gCfg.startingValues.sv1.x1, gCfg.startingValues.sv1.y1, gCfg.startingValues.sv1.x2, gCfg.startingValues.sv1.y2, Pic1)
    gHbm2 := CaptureRectToBitmap(gCfg.startingValues.sv2.x1, gCfg.startingValues.sv2.y1, gCfg.startingValues.sv2.x2, gCfg.startingValues.sv2.y2, Pic2)

    if gHbm1
        Pic1.Value := "HBITMAP:*" gHbm1
    else
        Pic1.Value := "HBITMAP:*" gPh1

    if gHbm2
        Pic2.Value := "HBITMAP:*" gHbm2
    else
        Pic2.Value := "HBITMAP:*" gPh2
}

CaptureRectToBitmap(x1, y1, x2, y2, picCtrl)
{
    w := Abs(x2-x1), h := Abs(y2-y1)
    if (w <= 0 || h <= 0)
        return 0

    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

    DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Ptr", hdcScreen, "Int", x1, "Int", y1, "UInt", 0x00CC0020)

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

    return hbm
}

CreateSolidBitmap(w, h, rgb)
{
    ; rgb is 0xRRGGBB
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

    brush := DllCall("CreateSolidBrush", "UInt", (rgb & 0xFF) << 16 | (rgb & 0xFF00) | (rgb >> 16) & 0xFF, "Ptr") ; BGR
    rect := Buffer(16, 0)
    NumPut("Int", 0, rect, 0), NumPut("Int", 0, rect, 4), NumPut("Int", w, rect, 8), NumPut("Int", h, rect, 12)
    DllCall("FillRect", "Ptr", hdcMem, "Ptr", rect, "Ptr", brush)
    DllCall("DeleteObject", "Ptr", brush)

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    return hbm
}

CleanupAllBitmaps(*)
{
    global gHbm1, gHbm2, gPh1, gPh2
    for hbm in [gHbm1, gHbm2, gPh1, gPh2]
        if hbm
            DllCall("DeleteObject", "Ptr", hbm)
}

; ============================================================
; GUI Updates
; ============================================================

UpdateStatus()
{
    global gRunning, gPageState, gFlyTotal, gClicksHouse, gClicksUpgrades
    global StatusLine1, StatusLine2, FlyTotalLine, HouseLine, UpgLine
    global gCfg, AutoEnergyCb, CbEnableHouse, CbEnableUpg

    StatusLine1.Text := gRunning ? "RUNNING (F8)" : "STOPPED (F8)"
    StatusLine1.Opt("c" (gRunning ? "00FF00" : "FF4040"))
    StatusLine2.Text := "Page: " gPageState
    FlyTotalLine.Text := "Flies: " gFlyTotal
    HouseLine.Text := "House buys: " gClicksHouse
    UpgLine.Text := "Upgrades buys: " gClicksUpgrades

    ; keep main checkboxes in sync with config
    AutoEnergyCb.Value := gCfg.enable.autoEnergy ? 1 : 0
    CbEnableHouse.Value := gCfg.enable.enableHouse ? 1 : 0
    CbEnableUpg.Value := gCfg.enable.enableUpgrades ? 1 : 0
}

BuildFlyDetailLines()
{
    global StatusGui, Tabs, guiW, gFlyDetailLines, gCfg

    ; clear existing controls if rebuilding
    if IsObject(gFlyDetailLines)
    {
        for ctl in gFlyDetailLines
            try ctl.Destroy()
    }
    gFlyDetailLines := []

    Tabs.UseTab("Fly Details")
    y := 70
    for fly in gCfg.flys
    {
        hex := Format("{:06X}", FlyGet(fly, "color"))
        ctl := StatusGui.AddText("x18 y" y " w" (guiW-36) " Center c" hex, "")
        gFlyDetailLines.Push(ctl)
        y += 22
    }
    Tabs.UseTab()
}

UpdateFlyDetails()
{
    global gCfg, gFlyCounts, gFlyDetailLines
    if !IsObject(gFlyDetailLines)
        return

    i := 0
    for fly in gCfg.flys
    {
        i += 1
        cnt := gFlyCounts.Has(FlyGet(fly, "name")) ? gFlyCounts[FlyGet(fly, "name")] : 0
        if i <= gFlyDetailLines.Length
            gFlyDetailLines[i].Text := FlyGet(fly, "name") ": " cnt
    }

}

RebuildMainFlyDetailsUI()
{
    ; Rebuild the Fly Details tab controls to match current gCfg.flys
    ; Preserve existing counts where possible.
    EnsureFlyCounts()
    BuildFlyDetailLines()
    UpdateFlyDetails()
    UpdateStatus()
}

InitFlyCounts()
{
    global gCfg, gFlyCounts
    gFlyCounts := Map()
    for fly in gCfg.flys
        gFlyCounts[FlyGet(fly, "name")] := 0
}


AddEditBlack(guiObj, options, text := "")
{
    ; Force readable text inside Edit controls on dark theme.
    ; (Some AHK v2 builds ignore Ctrl.SetFont on Edit controls.)
    guiObj.SetFont("c000000")
    ctrl := guiObj.AddEdit(options, text)
    guiObj.SetFont("cFFFFFF")
    return ctrl
}

; ============================================================
; Settings helpers / UI actions
; ============================================================

; Populate the Settings window controls from gCfg (called before showing Settings)
PopulateSettingsUI()
{
    global gCfg
    global UI_EnableHouse, UI_EnableUpg, UI_AutoEnergy
    global UI_HouseDetX, UI_HouseDetY, UI_UpgDetX, UI_UpgDetY
    global UI_HouseGX, UI_HouseGY, UI_UpgGX, UI_UpgGY
    global UI_AutoX, UI_AutoY, UI_FlyX1, UI_FlyY1, UI_FlyX2, UI_FlyY2
    global UI_HouseDetColor, UI_UpgDetColor, UI_HouseDetPreview, UI_UpgDetPreview
    global UI_ScanMs, UI_MainPause, UI_GreenPause, UI_PreClick, UI_PageMs, UI_AutoEvery, UI_RestoreDelay, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay, UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay
    global UI_FlyList, UI_FlyName, UI_FlyColor, UI_FlyTol, UI_FlyPreview
    global UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2
    global UI_EnemyList, UI_EnemyName, UI_EnemyColor, UI_EnemyTol, UI_EnemyPreview
    global BtnEnemyAdd, BtnEnemyRemove, BtnEnemyUpdate, BtnEnemyPickColor, BtnEnemyUp, BtnEnemyDown

    ; Enable / Disable
    try UI_EnableHouse.Value := gCfg.enable.enableHouse ? 1 : 0
    try UI_EnableUpg.Value   := gCfg.enable.enableUpgrades ? 1 : 0
    try UI_AutoEnergy.Value  := gCfg.enable.autoEnergy ? 1 : 0

    ; Coordinates
    try UI_HouseDetX.Value := gCfg.pageDetect.houseX
    try UI_HouseDetY.Value := gCfg.pageDetect.houseY
    try UI_UpgDetX.Value   := gCfg.pageDetect.upgX
    try UI_UpgDetY.Value   := gCfg.pageDetect.upgY

    try UI_HouseGX.Value := gCfg.coords.houseGreenX
    try UI_HouseGY.Value := gCfg.coords.houseGreenY
    try UI_UpgGX.Value   := gCfg.coords.upgGreenX
    try UI_UpgGY.Value   := gCfg.coords.upgGreenY

    try UI_AutoX.Value := gCfg.coords.autoEnergyX
    try UI_AutoY.Value := gCfg.coords.autoEnergyY

    try UI_FlyX1.Value := gCfg.flyRect.x1
    try UI_FlyY1.Value := gCfg.flyRect.y1
    try UI_FlyX2.Value := gCfg.flyRect.x2
    try UI_FlyY2.Value := gCfg.flyRect.y2

    ; Colors
    try UI_HouseDetColor.Value := Format("0x{:06X}", gCfg.pageDetect.houseColor & 0xFFFFFF)
    try UI_UpgDetColor.Value   := Format("0x{:06X}", gCfg.pageDetect.upgColor & 0xFFFFFF)
    try UpdateColorPreview(UI_HouseDetPreview, gCfg.pageDetect.houseColor)
    try UpdateColorPreview(UI_UpgDetPreview,   gCfg.pageDetect.upgColor)

    ; Timing
    try UI_ScanMs.Value     := gCfg.timing.scanIntervalMs
    try UI_MainPause.Value  := gCfg.timing.mainPauseMs
    try UI_GreenPause.Value := gCfg.timing.greenPauseMs
    try UI_PreClick.Value   := gCfg.timing.greenPreClickDelayMs
    try UI_PageMs.Value     := gCfg.timing.pageMs
    try UI_AutoEvery.Value  := gCfg.timing.autoEnergyEveryMs

    try UI_RestoreDelay.Value := gCfg.timing.restoreDelayMs
    try UI_RopeCd.Value := gCfg.timing.ropeHookCooldownMs
    try UI_ShurCd.Value := gCfg.timing.shurikenCooldownMs
    try UI_EnemyHold.Value := gCfg.timing.enemyHoldMs
    try UI_AttackDelay.Value := gCfg.timing.attackKeyDelayMs    ; Enemy rect
    try UI_EnemyX1.Value := gCfg.enemyRect.x1
    try UI_EnemyY1.Value := gCfg.enemyRect.y1
    try UI_EnemyX2.Value := gCfg.enemyRect.x2
    try UI_EnemyY2.Value := gCfg.enemyRect.y2

    ; Enemy list
    RefreshEnemyListUI()

    ; Fly list
    RefreshFlyListUI()
    RebuildMainFlyDetailsUI()
}

RefreshFlyListUI(selectIndex := 1)
{
    global gCfg
    global UI_FlyList
    names := []
    for fly in gCfg.flys
        names.Push(FlyGet(fly, "name"))
    try UI_FlyList.Delete()
    try UI_FlyList.Add(names)

    if names.Length = 0
    {
        OnFlySelect() ; clears fields
        return
    }
    ; clamp desired selection
    if selectIndex < 1
        selectIndex := 1
    if selectIndex > names.Length
        selectIndex := names.Length
    try UI_FlyList.Choose(selectIndex)
    OnFlySelect()
}

OnFlySelect(*)
{
    global gCfg
    global UI_FlyList, UI_FlyName, UI_FlyColor, UI_FlyTol, UI_FlyPreview
    global UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2
    global UI_EnemyList, UI_EnemyName, UI_EnemyColor, UI_EnemyTol, UI_EnemyPreview
    global BtnEnemyAdd, BtnEnemyRemove, BtnEnemyUpdate, BtnEnemyPickColor, BtnEnemyUp, BtnEnemyDown

    idx := 0
    try idx := UI_FlyList.Value
    if (idx < 1) || (idx > gCfg.flys.Length)
    {
        try UI_FlyName.Value := ""
        try UI_FlyColor.Value := ""
        try UI_FlyTol.Value := ""
        try UpdateColorPreview(UI_FlyPreview, 0x202020)
        return
    }

    fly := gCfg.flys[idx]
    try UI_FlyName.Value := FlyGet(fly, "name")
    try UI_FlyColor.Value := Format("0x{:06X}", FlyGet(fly, "color") & 0xFFFFFF)
    try UI_FlyTol.Value := FlyGet(fly, "tol")
    try UpdateColorPreview(UI_FlyPreview, FlyGet(fly, "color"))
}

OnFlyAdd(*)
{
    global gCfg, UI_FlyName, UI_FlyColor, UI_FlyTol
    name := Trim(UI_FlyName.Value)
    if name = ""
        return

    color := SafeHex(UI_FlyColor.Value, 0)
    tol := Clamp(SafeInt(UI_FlyTol.Value, 5), 0, 255)

    gCfg.flys.Push(Map("name", name, "color", color, "tol", tol))
    EnsureFlyCounts()
    RefreshFlyListUI(gCfg.flys.Length)
    RebuildMainFlyDetailsUI()
}

OnFlyUpdate(*)
{
    global gCfg, UI_FlyList, UI_FlyName, UI_FlyColor, UI_FlyTol
    idx := UI_FlyList.Value
    if (idx < 1) || (idx > gCfg.flys.Length)
        return

    name := Trim(UI_FlyName.Value)
    if name = ""
        return

    fly := gCfg.flys[idx]
    FlySet(fly, "name", name)
    FlySet(fly, "color", SafeHex(UI_FlyColor.Value, FlyGet(fly, "color")))
    FlySet(fly, "tol", Clamp(SafeInt(UI_FlyTol.Value, FlyGet(fly, "tol")), 0, 255))
    EnsureFlyCounts()
    RefreshFlyListUI(idx)
    RebuildMainFlyDetailsUI()
}

OnFlyRemove(*)
{
    global gCfg, UI_FlyList
    idx := UI_FlyList.Value
    if (idx < 1) || (idx > gCfg.flys.Length)
        return

    gCfg.flys.RemoveAt(idx)
    EnsureFlyCounts()
    RefreshFlyListUI(idx)
    RebuildMainFlyDetailsUI()
}

OnFlyUp(*)
{
    global gCfg, UI_FlyList
    idx := UI_FlyList.Value
    if idx <= 1 || idx > gCfg.flys.Length
        return

    tmp := gCfg.flys[idx-1]
    gCfg.flys[idx-1] := gCfg.flys[idx]
    gCfg.flys[idx] := tmp
    RefreshFlyListUI(idx-1)
    RebuildMainFlyDetailsUI()
}

OnFlyDown(*)
{
    global gCfg, UI_FlyList
    idx := UI_FlyList.Value
    if idx < 1 || idx >= gCfg.flys.Length
        return

    tmp := gCfg.flys[idx+1]
    gCfg.flys[idx+1] := gCfg.flys[idx]
    gCfg.flys[idx] := tmp
    RefreshFlyListUI(idx+1)
    RebuildMainFlyDetailsUI()
}

EnsureFlyCounts()
{
    global gCfg, gFlyCounts, gFlyTotal
    if !IsObject(gFlyCounts)
        gFlyCounts := Map()
    ; keep existing counts where possible, init new ones
    for fly in gCfg.flys
        if !gFlyCounts.Has(FlyGet(fly, "name"))
            gFlyCounts[FlyGet(fly, "name")] := 0
}



; ----------------------------
; Enemy UI helpers (Settings)
; ----------------------------
RefreshEnemyListUI(selectIndex := 1)
{
    global gCfg, UI_EnemyList
    names := []
    for en in gCfg.enemies
        names.Push(FlyGet(en, "name"))
    try UI_EnemyList.Delete()
    try UI_EnemyList.Add(names)

    if names.Length = 0
    {
        OnEnemySelect()
        return
    }
    if selectIndex < 1
        selectIndex := 1
    if selectIndex > names.Length
        selectIndex := names.Length
    try UI_EnemyList.Choose(selectIndex)
    OnEnemySelect()
}

OnEnemySelect(*)
{
    global gCfg
    global UI_EnemyList, UI_EnemyName, UI_EnemyColor, UI_EnemyTol, UI_EnemyPreview

    idx := 0
    try idx := UI_EnemyList.Value
    if (idx < 1) || (idx > gCfg.enemies.Length)
    {
        try UI_EnemyName.Value := ""
        try UI_EnemyColor.Value := ""
        try UI_EnemyTol.Value := ""
        try UpdateColorPreview(UI_EnemyPreview, 0x202020)
        return
    }

    en := gCfg.enemies[idx]
    try UI_EnemyName.Value := FlyGet(en, "name")
    try UI_EnemyColor.Value := Format("0x{:06X}", FlyGet(en, "color") & 0xFFFFFF)
    try UI_EnemyTol.Value := FlyGet(en, "tol")
    try UpdateColorPreview(UI_EnemyPreview, FlyGet(en, "color"))
}

OnEnemyAdd(*)
{
    global gCfg, UI_EnemyName, UI_EnemyColor, UI_EnemyTol
    name := Trim(UI_EnemyName.Value)
    if name = ""
        return
    color := SafeHex(UI_EnemyColor.Value, 0)
    tol := Clamp(SafeInt(UI_EnemyTol.Value, 5), 0, 255)
    gCfg.enemies.Push(Map("name", name, "color", color, "tol", tol))
    RefreshEnemyListUI(gCfg.enemies.Length)
}

OnEnemyUpdate(*)
{
    global gCfg, UI_EnemyList, UI_EnemyName, UI_EnemyColor, UI_EnemyTol
    idx := UI_EnemyList.Value
    if (idx < 1) || (idx > gCfg.enemies.Length)
        return
    name := Trim(UI_EnemyName.Value)
    if name = ""
        return
    en := gCfg.enemies[idx]
    FlySet(en, "name", name)
    FlySet(en, "color", SafeHex(UI_EnemyColor.Value, FlyGet(en, "color")))
    FlySet(en, "tol", Clamp(SafeInt(UI_EnemyTol.Value, FlyGet(en, "tol")), 0, 255))
    RefreshEnemyListUI(idx)
}

OnEnemyRemove(*)
{
    global gCfg, UI_EnemyList
    idx := UI_EnemyList.Value
    if (idx < 1) || (idx > gCfg.enemies.Length)
        return
    gCfg.enemies.RemoveAt(idx)
    RefreshEnemyListUI(idx)
}

OnEnemyUp(*)
{
    global gCfg, UI_EnemyList
    idx := UI_EnemyList.Value
    if idx <= 1 || idx > gCfg.enemies.Length
        return
    tmp := gCfg.enemies[idx-1]
    gCfg.enemies[idx-1] := gCfg.enemies[idx]
    gCfg.enemies[idx] := tmp
    RefreshEnemyListUI(idx-1)
}

OnEnemyDown(*)
{
    global gCfg, UI_EnemyList
    idx := UI_EnemyList.Value
    if idx < 1 || idx >= gCfg.enemies.Length
        return
    tmp := gCfg.enemies[idx+1]
    gCfg.enemies[idx+1] := gCfg.enemies[idx]
    gCfg.enemies[idx] := tmp
    RefreshEnemyListUI(idx+1)
}

; Apply current Settings UI values into gCfg (does not write INI unless caller saves)
ApplySettingsFromUI()
{
    global gCfg
    global UI_EnableHouse, UI_EnableUpg, UI_AutoEnergy
    global UI_HouseDetX, UI_HouseDetY, UI_UpgDetX, UI_UpgDetY
    global UI_HouseGX, UI_HouseGY, UI_UpgGX, UI_UpgGY
    global UI_AutoX, UI_AutoY, UI_FlyX1, UI_FlyY1, UI_FlyX2, UI_FlyY2
    global UI_HouseDetColor, UI_UpgDetColor
    global UI_ScanMs, UI_MainPause, UI_GreenPause, UI_PreClick, UI_PageMs, UI_AutoEvery, UI_RestoreDelay, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay, UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay

    gCfg.enable.enableHouse := !!UI_EnableHouse.Value
    gCfg.enable.enableUpgrades := !!UI_EnableUpg.Value
    gCfg.enable.autoEnergy := !!UI_AutoEnergy.Value

    gCfg.pageDetect.houseX := SafeInt(UI_HouseDetX.Value, gCfg.pageDetect.houseX)
    gCfg.pageDetect.houseY := SafeInt(UI_HouseDetY.Value, gCfg.pageDetect.houseY)
    gCfg.pageDetect.upgX   := SafeInt(UI_UpgDetX.Value, gCfg.pageDetect.upgX)
    gCfg.pageDetect.upgY   := SafeInt(UI_UpgDetY.Value, gCfg.pageDetect.upgY)

    gCfg.pageDetect.houseColor := SafeHex(UI_HouseDetColor.Value, gCfg.pageDetect.houseColor)
    gCfg.pageDetect.upgColor   := SafeHex(UI_UpgDetColor.Value, gCfg.pageDetect.upgColor)

    gCfg.coords.houseGreenX := SafeInt(UI_HouseGX.Value, gCfg.coords.houseGreenX)
    gCfg.coords.houseGreenY := SafeInt(UI_HouseGY.Value, gCfg.coords.houseGreenY)
    gCfg.coords.upgGreenX   := SafeInt(UI_UpgGX.Value, gCfg.coords.upgGreenX)
    gCfg.coords.upgGreenY   := SafeInt(UI_UpgGY.Value, gCfg.coords.upgGreenY)

    gCfg.coords.autoEnergyX := SafeInt(UI_AutoX.Value, gCfg.coords.autoEnergyX)
    gCfg.coords.autoEnergyY := SafeInt(UI_AutoY.Value, gCfg.coords.autoEnergyY)

    gCfg.flyRect.x1 := SafeInt(UI_FlyX1.Value, gCfg.flyRect.x1)
    gCfg.flyRect.y1 := SafeInt(UI_FlyY1.Value, gCfg.flyRect.y1)
    gCfg.flyRect.x2 := SafeInt(UI_FlyX2.Value, gCfg.flyRect.x2)
    gCfg.flyRect.y2 := SafeInt(UI_FlyY2.Value, gCfg.flyRect.y2)

    gCfg.enemyRect.x1 := SafeInt(UI_EnemyX1.Value, gCfg.enemyRect.x1)
    gCfg.enemyRect.y1 := SafeInt(UI_EnemyY1.Value, gCfg.enemyRect.y1)
    gCfg.enemyRect.x2 := SafeInt(UI_EnemyX2.Value, gCfg.enemyRect.x2)
    gCfg.enemyRect.y2 := SafeInt(UI_EnemyY2.Value, gCfg.enemyRect.y2)

    gCfg.timing.scanIntervalMs := Max(10, SafeInt(UI_ScanMs.Value, gCfg.timing.scanIntervalMs))
    gCfg.timing.mainPauseMs    := Max(0, SafeInt(UI_MainPause.Value, gCfg.timing.mainPauseMs))
    gCfg.timing.greenPauseMs   := Max(0, SafeInt(UI_GreenPause.Value, gCfg.timing.greenPauseMs))
    gCfg.timing.greenPreClickDelayMs:= Max(0, SafeInt(UI_PreClick.Value, gCfg.timing.greenPreClickDelayMs))
    gCfg.timing.pageMs         := Max(0, SafeInt(UI_PageMs.Value, gCfg.timing.pageMs))
    gCfg.timing.autoEnergyEveryMs := Max(50, SafeInt(UI_AutoEvery.Value, gCfg.timing.autoEnergyEveryMs))
    gCfg.timing.restoreDelayMs := Max(0, SafeInt(UI_RestoreDelay.Value, gCfg.timing.restoreDelayMs))


    gCfg.timing.ropeHookCooldownMs := Max(0, SafeInt(UI_RopeCd.Value, gCfg.timing.ropeHookCooldownMs))
    gCfg.timing.shurikenCooldownMs := Max(0, SafeInt(UI_ShurCd.Value, gCfg.timing.shurikenCooldownMs))
    gCfg.timing.enemyHoldMs := Max(0, SafeInt(UI_EnemyHold.Value, gCfg.timing.enemyHoldMs))
    gCfg.timing.attackKeyDelayMs := Max(0, SafeInt(UI_AttackDelay.Value, gCfg.timing.attackKeyDelayMs))
    EnsureFlyCounts()
}

OnBtnApply(*)
{
    ApplySettingsFromUI()
    SaveConfigIniSafe(true)
    RebuildMainFlyDetailsUI()
    SettingsOnClose()
}

OnBtnSave(*)
{
    ApplySettingsFromUI()
    SaveConfigIniSafe(true)
    RebuildMainFlyDetailsUI()
}

OnBtnDefaults(*)
{
    global gCfg
    res := MsgBox("Restore default settings? This will overwrite your current settings.", "Confirm Defaults", "YesNo Icon!")
    if (res != "Yes")
        return
    gCfg := DefaultConfig()
    EnsureFlyCounts()
    PopulateSettingsUI()
    SaveConfigIniSafe(true)
    ; refresh main fly details UI immediately
    RebuildMainFlyDetailsUI()
}
SettingsOnClose(*)
{
    global SettingsGui, gSettingsOpen, gWasRunningBeforeSettings, gRunning
    if IsObject(SettingsGui)
        SettingsGui.Hide()

    if gSettingsOpen
    {
        gSettingsOpen := false
        if gWasRunningBeforeSettings
        {
            gRunning := true
            UpdateStatus()
        }
    }
}

; Simple wrappers around PickXYColorTo for the common cases
PickXYTo(editX, editY)
{
    PickXYColorTo(editX, editY, 0, 0)
}
PickColorTo(editColor, previewCtrl := 0)
{
    PickXYColorTo(0, 0, editColor, previewCtrl)
}

UpdateColorPreview(previewCtrl, rgb)
{
    global SettingsGui
    if !IsObject(previewCtrl)
        return

    rgb := rgb & 0xFFFFFF
    try previewCtrl.Opt("Background" Format("{:06X}", rgb))

    ; Force an immediate repaint (some AHK builds only repaint after tab changes)
    try DllCall("RedrawWindow", "ptr", previewCtrl.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85) ; INVALIDATE|UPDATENOW|ALLCHILDREN
    try DllCall("RedrawWindow", "ptr", previewCtrl.Gui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85)
    if IsObject(SettingsGui)
        try DllCall("RedrawWindow", "ptr", SettingsGui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85)

    ; Last-resort: re-show without activating (nudges repaint on stubborn systems)
    if IsObject(SettingsGui)
        try SettingsGui.Show("NoActivate")
}



; ============================================================
; Settings Window (separate GUI)
; ============================================================

global SettingsGui := 0
global gSettingsOpen := false
global gWasRunningBeforeSettings := false
global gSettingsW := 430
global gSettingsH := 520

OpenSettings()
{
    global SettingsGui, gSettingsOpen, gWasRunningBeforeSettings, gRunning
    if !IsObject(SettingsGui)
        BuildSettingsGui()

    ; Pause bot while Settings is open (prevents mis-clicking UI)
    if !gSettingsOpen
    {
        gWasRunningBeforeSettings := gRunning
        if gRunning
        {
            gRunning := false
            UpdateStatus()
        }
        gSettingsOpen := true
    }

    PopulateSettingsUI()
    SettingsGui.Show("w" gSettingsW " h" gSettingsH)
    try SettingsGui.Opt("+OwnDialogs")
}

BuildSettingsGui()
{
    global SettingsGui, gSettingsW, gSettingsH
    global BtnApply, BtnSave, BtnDefaults, BtnCloseSettings
    global UI_EnableHouse, UI_EnableUpg, UI_AutoEnergy
    global UI_HouseDetX, UI_HouseDetY, UI_UpgDetX, UI_UpgDetY
    global UI_HouseGX, UI_HouseGY, UI_UpgGX, UI_UpgGY
    global UI_AutoX, UI_AutoY, UI_FlyX1, UI_FlyY1, UI_FlyX2, UI_FlyY2
    global UI_HouseDetColor, UI_UpgDetColor, UI_HouseDetPreview, UI_UpgDetPreview
    global UI_ScanMs, UI_MainPause, UI_GreenPause, UI_PreClick, UI_PageMs, UI_AutoEvery, UI_RestoreDelay, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay, UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2, UI_RopeCd, UI_ShurCd, UI_EnemyHold, UI_AttackDelay
    global UI_FlyList, UI_FlyName, UI_FlyColor, UI_FlyTol, UI_FlyPreview
    global UI_EnemyX1, UI_EnemyY1, UI_EnemyX2, UI_EnemyY2
    global UI_EnemyList, UI_EnemyName, UI_EnemyColor, UI_EnemyTol, UI_EnemyPreview
    global BtnEnemyAdd, BtnEnemyRemove, BtnEnemyUpdate, BtnEnemyPickColor, BtnEnemyUp, BtnEnemyDown
    global BtnFlyAdd, BtnFlyRemove, BtnFlyUpdate, BtnFlyPickColor, BtnFlyUp, BtnFlyDown

    SettingsGui := Gui("+AlwaysOnTop +ToolWindow", "Tap Ninja Bot - Settings")
    SettingsGui.BackColor := "202020"
    SettingsGui.SetFont("s10 cFFFFFF", "Segoe UI")

    ; Ensure bot resumes (if it was running) when Settings closes
    SettingsGui.OnEvent("Close", SettingsOnClose)

    SettingsGui.AddText("x12 y8 w" (gSettingsW-24) " cD0D0D0"
        , "Settings pause the bot while open. Use Pick, then click in-game to capture values.")

    ; Tabs (categories)
    btnY := gSettingsH - 44
    tabY := 44
    tabH := btnY - tabY - 10
    tabW := gSettingsW - 24

    TabsS := SettingsGui.AddTab3("x12 y" tabY " w" tabW " h" tabH
        , ["Enable", "Coordinates", "Colors", "Timing", "Enemy", "Flys"])

    ; ---------------- Enable ----------------
    TabsS.UseTab("Enable")
    UI_EnableHouse := SettingsGui.AddCheckbox("x24 y" (tabY+36) " w200 cFFFFFF", "Enable House")
    UI_EnableUpg   := SettingsGui.AddCheckbox("x24 y" (tabY+62) " w200 cFFFFFF", "Enable Upgrades")
    UI_AutoEnergy  := SettingsGui.AddCheckbox("x24 y" (tabY+88) " w200 cFFFFFF", "Auto Energy")

    ; ---------------- Coordinates ----------------
    TabsS.UseTab("Coordinates")
    y := tabY + 34
    row := 28
    colX := 118, colY := 170, colPick := 222

    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "House Detect")
    UI_HouseDetX := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_HouseDetY := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_HouseDetX, UI_HouseDetY))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Upg Detect")
    UI_UpgDetX := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_UpgDetY := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_UpgDetX, UI_UpgDetY))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "House Green")
    UI_HouseGX := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_HouseGY := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_HouseGX, UI_HouseGY))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Upg Green")
    UI_UpgGX := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_UpgGY := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_UpgGX, UI_UpgGY))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Auto Energy")
    UI_AutoX := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_AutoY := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_AutoX, UI_AutoY))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Fly Rect TL")
    UI_FlyX1 := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_FlyY1 := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_FlyX1, UI_FlyY1))

    y += row
    SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Fly Rect BR")
    UI_FlyX2 := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
    UI_FlyY2 := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
    btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYTo(UI_FlyX2, UI_FlyY2))

    ; ---------------- Colors ----------------
    TabsS.UseTab("Colors")
    y := tabY + 34
    SettingsGui.AddText("x24 y" y " w110 cFFFFFF", "House Detect Color")
    UI_HouseDetColor := AddEditBlack(SettingsGui, "x170 y" (y-2) " w90", "")
    UI_HouseDetPreview := SettingsGui.AddText("x268 y" (y-2) " w24 h22 Border Background202020", "")
    btn := SettingsGui.AddButton("x300 y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYColorTo(UI_HouseDetX, UI_HouseDetY, UI_HouseDetColor, UI_HouseDetPreview))

    y += 40
    SettingsGui.AddText("x24 y" y " w110 cFFFFFF", "Upg Detect Color")
    UI_UpgDetColor := AddEditBlack(SettingsGui, "x170 y" (y-2) " w90", "")
    UI_UpgDetPreview := SettingsGui.AddText("x268 y" (y-2) " w24 h22 Border Background202020", "")
    btn := SettingsGui.AddButton("x300 y" (y-2) " w44", "Pick")
    btn.OnEvent("Click", (*) => PickXYColorTo(UI_UpgDetX, UI_UpgDetY, UI_UpgDetColor, UI_UpgDetPreview))

    ; ---------------- Timing ----------------
    TabsS.UseTab("Timing")
    SettingsGui.AddText("x24 y" (tabY+36) " w100 cB0B0B0", "Timing (ms)")

    UI_ScanMs := AddEditBlack(SettingsGui, "x24 y" (tabY+64) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+66) " w80 cFFFFFF", "Scan")

    UI_MainPause := AddEditBlack(SettingsGui, "x200 y" (tabY+64) " w80", "")
    SettingsGui.AddText("x286 y" (tabY+66) " w80 cFFFFFF", "Main")

    UI_GreenPause := AddEditBlack(SettingsGui, "x24 y" (tabY+94) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+96) " w80 cFFFFFF", "Green")

    UI_PreClick := AddEditBlack(SettingsGui, "x200 y" (tabY+94) " w80", "")
    SettingsGui.AddText("x286 y" (tabY+96) " w80 cFFFFFF", "Pre")

    UI_PageMs := AddEditBlack(SettingsGui, "x24 y" (tabY+124) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+126) " w80 cFFFFFF", "Page")

    UI_AutoEvery := AddEditBlack(SettingsGui, "x200 y" (tabY+124) " w80", "")
    SettingsGui.AddText("x286 y" (tabY+126) " w80 cFFFFFF", "Auto")

    UI_RestoreDelay := AddEditBlack(SettingsGui, "x24 y" (tabY+154) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+156) " w120 cFFFFFF", "RestoreDelay")

    UI_RopeCd := AddEditBlack(SettingsGui, "x200 y" (tabY+154) " w80", "")
    SettingsGui.AddText("x286 y" (tabY+156) " w120 cFFFFFF", "Rope CD")

    UI_ShurCd := AddEditBlack(SettingsGui, "x24 y" (tabY+184) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+186) " w120 cFFFFFF", "Shuriken CD")

    UI_EnemyHold := AddEditBlack(SettingsGui, "x200 y" (tabY+184) " w80", "")
    SettingsGui.AddText("x286 y" (tabY+186) " w120 cFFFFFF", "EnemyHold")

    UI_AttackDelay := AddEditBlack(SettingsGui, "x24 y" (tabY+214) " w80", "")
    SettingsGui.AddText("x110 y" (tabY+216) " w160 cFFFFFF", "AttackKeyDelay")


; ---------------- Enemy ----------------
TabsS.UseTab("Enemy")
y := tabY + 34
row := 28
colX := 118, colY := 170, colPick := 222

; Header (keep fully visible)
SettingsGui.AddText("x24 y" y " w" (tabW-48) " cB0B0B0", "Enemy rectangle (attacks only fire when an enemy is found)")
y += 22

SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Enemy TL")
UI_EnemyX1 := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
UI_EnemyY1 := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
btn.OnEvent("Click", (*) => PickXYTo(UI_EnemyX1, UI_EnemyY1))
y += row

SettingsGui.AddText("x24 y" y " w90 cFFFFFF", "Enemy BR")
UI_EnemyX2 := AddEditBlack(SettingsGui, "x" colX " y" (y-2) " w48", "")
UI_EnemyY2 := AddEditBlack(SettingsGui, "x" colY " y" (y-2) " w48", "")
btn := SettingsGui.AddButton("x" colPick " y" (y-2) " w44", "Pick")
btn.OnEvent("Click", (*) => PickXYTo(UI_EnemyX2, UI_EnemyY2))
y += 40

SettingsGui.AddText("x24 y" y " w" (tabW-48) " cB0B0B0", "Dynamic enemy list (priority = top → bottom).")
y += 30

UI_EnemyList := SettingsGui.AddListBox("x24 y" (y+2) " w150 h180")
UI_EnemyList.SetFont("c000000")
UI_EnemyList.OnEvent("Change", (*) => OnEnemySelect())
SettingsGui.SetFont("s10 cFFFFFF", "Segoe UI")

; Right-side editor panel (mirrors Fly layout)
rightX := 186
editX := 246

SettingsGui.AddText("x" rightX " y" (y+4) " w60 cFFFFFF", "Name")
UI_EnemyName := AddEditBlack(SettingsGui, "x" editX " y" (y+2) " w160", "")

y2 := y + 34
SettingsGui.AddText("x" rightX " y" y2 " w60 cFFFFFF", "Color")
UI_EnemyColor := AddEditBlack(SettingsGui, "x" editX " y" (y2-2) " w90", "")
UI_EnemyColor.OnEvent("Change", (*) => (UpdateColorPreview(UI_EnemyPreview, SafeHex(UI_EnemyColor.Value, 0))))
UI_EnemyPreview := SettingsGui.AddText("x" (editX+96) " y" (y2-2) " w24 h22 Border Background202020", "")
BtnEnemyPickColor := SettingsGui.AddButton("x" (editX+126) " y" (y2-2) " w38", "Pick")
BtnEnemyPickColor.OnEvent("Click", (*) => PickColorTo(UI_EnemyColor, UI_EnemyPreview))

y3 := y + 64
SettingsGui.AddText("x" rightX " y" y3 " w60 cFFFFFF", "Tol")
UI_EnemyTol := AddEditBlack(SettingsGui, "x" editX " y" (y3-2) " w60", "")
BtnEnemyAdd := SettingsGui.AddButton("x" rightX " y" (y+104) " w56", "Add")
BtnEnemyUpdate := SettingsGui.AddButton("x" (rightX+60) " y" (y+104) " w62", "Update")
BtnEnemyRemove := SettingsGui.AddButton("x" (rightX+128) " y" (y+104) " w62", "Remove")
BtnEnemyUp := SettingsGui.AddButton("x" rightX " y" (y+134) " w56", "Up")
BtnEnemyDown := SettingsGui.AddButton("x" (rightX+60) " y" (y+134) " w62", "Down")

BtnEnemyAdd.OnEvent("Click", (*) => OnEnemyAdd())
BtnEnemyUpdate.OnEvent("Click", (*) => OnEnemyUpdate())
BtnEnemyRemove.OnEvent("Click", (*) => OnEnemyRemove())
BtnEnemyUp.OnEvent("Click", (*) => OnEnemyUp())
BtnEnemyDown.OnEvent("Click", (*) => OnEnemyDown())

; ---------------- Flys ----------------
    TabsS.UseTab("Flys")
    ; Keep this header fully visible above the list
    SettingsGui.AddText("x24 y" (tabY+38) " w320 cB0B0B0", "Dynamic fly list (scan priority = list order)")

    SettingsGui.SetFont("c000000")
    UI_FlyList := SettingsGui.AddListBox("x24 y" (tabY+76) " w150 h180", [])
    SettingsGui.SetFont("cFFFFFF")
    UI_FlyList.OnEvent("Change", OnFlySelect)

    SettingsGui.AddText("x186 y" (tabY+76) " w60 cFFFFFF", "Name")
    UI_FlyName := AddEditBlack(SettingsGui, "x246 y" (tabY+74) " w160", "")

    SettingsGui.AddText("x186 y" (tabY+106) " w60 cFFFFFF", "Color")
    UI_FlyColor := AddEditBlack(SettingsGui, "x246 y" (tabY+104) " w90", "")
    UI_FlyColor.OnEvent("Change", (*) => (UpdateColorPreview(UI_FlyPreview, SafeHex(UI_FlyColor.Value, 0))))
    UI_FlyPreview := SettingsGui.AddText("x342 y" (tabY+104) " w24 h22 Border Background202020", "")
    BtnFlyPickColor := SettingsGui.AddButton("x372 y" (tabY+104) " w34 h22", "Pick")
    BtnFlyPickColor.OnEvent("Click", (*) => PickColorTo(UI_FlyColor, UI_FlyPreview))

    SettingsGui.AddText("x186 y" (tabY+136) " w60 cFFFFFF", "Tol")
    UI_FlyTol := AddEditBlack(SettingsGui, "x246 y" (tabY+134) " w44", "")

    BtnFlyAdd := SettingsGui.AddButton("x300 y" (tabY+134) " w50 h24", "Add")
    BtnFlyAdd.OnEvent("Click", OnFlyAdd)
    BtnFlyUpdate := SettingsGui.AddButton("x356 y" (tabY+134) " w50 h24", "Update")
    BtnFlyUpdate.OnEvent("Click", OnFlyUpdate)

    BtnFlyRemove := SettingsGui.AddButton("x186 y" (tabY+166) " w70 h24", "Remove")
    BtnFlyRemove.OnEvent("Click", OnFlyRemove)
    BtnFlyUp := SettingsGui.AddButton("x262 y" (tabY+166) " w70 h24", "Up")
    BtnFlyUp.OnEvent("Click", OnFlyUp)
    BtnFlyDown := SettingsGui.AddButton("x338 y" (tabY+166) " w70 h24", "Down")
    BtnFlyDown.OnEvent("Click", OnFlyDown)

    TabsS.UseTab()

    ; Bottom buttons (as requested)
    BtnApply := SettingsGui.AddButton("x12 y" btnY " w90", "Apply")
    BtnSave  := SettingsGui.AddButton("x112 y" btnY " w90", "Save")
    BtnDefaults := SettingsGui.AddButton("x212 y" btnY " w90", "Defaults")
    BtnCloseSettings := SettingsGui.AddButton("x" (gSettingsW-102) " y" btnY " w90", "Close")

    BtnApply.OnEvent("Click", OnBtnApply)
    BtnSave.OnEvent("Click",  OnBtnSave)
    BtnDefaults.OnEvent("Click", OnBtnDefaults)
    BtnCloseSettings.OnEvent("Click", SettingsOnClose)
}

PickXYColorTo(editX, editY, editColor, previewCtrl := 0)
{
    global StatusGui, SettingsGui
    mainWasVisible := false
    settingsWasVisible := false
    try mainWasVisible := StatusGui.Visible
    if IsObject(SettingsGui)
    {
        try settingsWasVisible := SettingsGui.Visible
        SettingsGui.Hide()
    }
    StatusGui.Hide()
    Sleep 120
    ToolTip "Click in the game to capture X/Y + color..."
    WaitClick()
    MouseGetPos &mx, &my
    c := PixelGetColor(mx, my, "RGB")
    ToolTip
    ; Always restore windows (some AHK builds don't reliably expose .Visible)
    StatusGui.Show("NoActivate")
    if IsObject(SettingsGui)
        SettingsGui.Show("NoActivate")
    ; editX/editY/editColor may be omitted (passed as 0) depending on which picker is used
    if IsObject(editX)
        editX.Value := mx
    if IsObject(editY)
        editY.Value := my
    if IsObject(editColor)
        editColor.Value := Format("0x{:06X}", c)
    if IsObject(previewCtrl)
    {
        hex := Format("{:06X}", c)
        try previewCtrl.Opt("+Background" hex)
    }
}

WaitClick()
{
    KeyWait "LButton", "D"
    KeyWait "LButton"
}

; ============================================================
; Config + INI helpers
; ============================================================


; ----------------------------
; Default configuration
; ----------------------------

DefaultConfig()
{
    cfg := {}

    cfg.enable := {
        enableHouse: true,
        enableUpgrades: true,
        autoEnergy: false,
        autoRopeHook: false,
        autoShuriken: false
    }

    cfg.coords := {
        houseGreenX: 1791, houseGreenY: 1026,
        upgGreenX: 1798,   upgGreenY: 282,
        autoEnergyX: 341,  autoEnergyY: 801
    }

    ; Shared green buy-button color
    cfg.colors := { green: 0x0CB200 }
    cfg.tols   := { green: 5 }

    ; Separate page detect pixels/colors
    ; (House defaults are 0/0/0 so it won't falsely match until you set it)
    cfg.pageDetect := {
        houseX: 0, houseY: 0, houseColor: 0x000000,
        upgX: 1883, upgY: 825, upgColor: 0x182187,
        tol: 10
    }

    cfg.flyRect := { x1: 283, y1: 131, x2: 1590, y2: 800 }

    cfg.enemyRect := { x1: 300, y1: 140, x2: 1580, y2: 820 }

    cfg.enemies := []

    cfg.flys := [
    { name: "Fire",   color: 0xFD970C, tol: 5 },
    { name: "Snow",   color: 0xD39146, tol: 5 },
    { name: "Ice",    color: 0x22E5BC, tol: 5 },
    { name: "Snowy",  color: 0x40C6BC, tol: 5 },
    { name: "Sakura", color: 0xFEA03E, tol: 5 }
]

    cfg.timing := {
        scanIntervalMs: 50,
        mainPauseMs: 2000,
        greenPauseMs: 500,
        greenPreClickDelayMs: 100,
        pageMs: 15000,
        autoEnergyEveryMs: 1000,
        restoreDelayMs: 25,
        ropeHookCooldownMs: 20000,
        shurikenCooldownMs: 60000,
        enemyHoldMs: 300,
        attackKeyDelayMs: 30
    }

    cfg.startingValues := {
        sv1: { x1: 1726, y1: 130, x2: 1893, y2: 173 },
        sv2: { x1: 1726, y1: 189, x2: 1893, y2: 225 }
    }

    return cfg
}

LoadOrCreateConfigIni(path)
{
    cfg := DefaultConfig()

    if !FileExist(path)
    {
        ; First run: write defaults
        WriteConfigToIni(cfg, path)
        return cfg
    }

    ; Read values, falling back to defaults if missing/bad
    try
        ReadConfigFromIni(cfg, path)
    catch
    {
        ; If anything goes wrong, re-write defaults so we recover cleanly
        WriteConfigToIni(cfg, path)
        cfg := DefaultConfig()
    }
    return cfg
}

SaveConfigIniSafe(forceMsg := false)
{
    global gCfgFile, gCfg
    try
    {
        WriteConfigToIni(gCfg, gCfgFile)
    }
    catch as e
    {
        if forceMsg
            MsgBox "Failed to save config:`n" e.Message
    }
}

; ----------------------------
; INI read/write implementation
; ----------------------------

; Fly list INI helpers
; ----------------------------
ReadFlysFromIni(path, cfg)
{
    ; Try new format
    countStr := ""
    try countStr := IniRead(path, "Flys", "Count", "")
    if (countStr != "")
    {
        count := SafeInt(countStr, 0)
        out := []
        Loop count
        {
            i := A_Index
            nm := IniRead(path, "Flys", "Fly" i "Name", "Fly" i)
            col := ReadHex(path, "Flys", "Fly" i "Color", 0xFFFFFF)
            tol := Clamp(ReadInt(path, "Flys", "Fly" i "Tol", 5), 0, 255)
            out.Push({ name: nm, color: col, tol: tol })
        }
        if out.Length = 0
            return cfg.flys
        return out
    }

    ; Legacy format ([Fly] section with fixed keys) -> convert to list
    out := []
    legacyFire := IniRead(path, "Fly", "FireColor", "")
    if (legacyFire != "")
    {
        out.Push({ name: "Fire",   color: ReadHex(path, "Fly", "FireColor", 0xFD970C),   tol: Clamp(ReadInt(path, "Fly", "FireTol", 5), 0, 255) })
        out.Push({ name: "Snow",   color: ReadHex(path, "Fly", "SnowColor", 0xD39146),   tol: Clamp(ReadInt(path, "Fly", "SnowTol", 5), 0, 255) })
        out.Push({ name: "Ice",    color: ReadHex(path, "Fly", "IceColor",  0x22E5BC),   tol: Clamp(ReadInt(path, "Fly", "IceTol", 5), 0, 255) })
        out.Push({ name: "Snowy",  color: ReadHex(path, "Fly", "SnowyColor",0x40C6BC),   tol: Clamp(ReadInt(path, "Fly", "SnowyTol", 5), 0, 255) })
        out.Push({ name: "Sakura", color: ReadHex(path, "Fly", "SakuraColor",0xFEA03E),  tol: Clamp(ReadInt(path, "Fly", "SakuraTol", 5), 0, 255) })

        ; Write converted format for next run
        try WriteFlysToIni(out, path)
        return out
    }

    return cfg.flys
}

WriteFlysToIni(flys, path)
{
    IniWrite flys.Length, path, "Flys", "Count"
    Loop flys.Length
    {
        i := A_Index
        fly := flys[i]
        IniWrite FlyGet(fly, "name"), path, "Flys", "Fly" i "Name"
        IniWrite FormatHex(FlyGet(fly, "color")), path, "Flys", "Fly" i "Color"
        IniWrite FlyGet(fly, "tol"), path, "Flys", "Fly" i "Tol"
    }

    ; best-effort cleanup of extra slots (up to 50)
    Loop 50
    {
        i := A_Index
        if i <= flys.Length
            continue
        try IniDelete path, "Flys", "Fly" i "Name"
        try IniDelete path, "Flys", "Fly" i "Color"
        try IniDelete path, "Flys", "Fly" i "Tol"
    }
}





; Enemy list INI helpers
; ----------------------------
ReadEnemiesFromIni(path, cfg)
{
    countStr := ""
    try countStr := IniRead(path, "Enemies", "Count", "")
    if (countStr = "")
        return cfg.enemies

    count := SafeInt(countStr, 0)
    out := []
    Loop count
    {
        i := A_Index
        nm := IniRead(path, "Enemies", "Enemy" i "Name", "Enemy" i)
        col := ReadHex(path, "Enemies", "Enemy" i "Color", 0xFFFFFF)
        tol := Clamp(ReadInt(path, "Enemies", "Enemy" i "Tol", 5), 0, 255)
        out.Push({ name: nm, color: col, tol: tol })
    }
    return out
}

WriteEnemiesToIni(enemies, path)
{
    IniWrite enemies.Length, path, "Enemies", "Count"
    Loop enemies.Length
    {
        i := A_Index
        en := enemies[i]
        IniWrite FlyGet(en, "name"), path, "Enemies", "Enemy" i "Name"
        IniWrite FormatHex(FlyGet(en, "color")), path, "Enemies", "Enemy" i "Color"
        IniWrite FlyGet(en, "tol"), path, "Enemies", "Enemy" i "Tol"
    }

    Loop 50
    {
        i := A_Index
        if i <= enemies.Length
            continue
        try IniDelete path, "Enemies", "Enemy" i "Name"
        try IniDelete path, "Enemies", "Enemy" i "Color"
        try IniDelete path, "Enemies", "Enemy" i "Tol"
    }
}

ReadConfigFromIni(cfg, path)
{
    ; Enable
    cfg.enable.enableHouse    := ReadBool(path, "Enable", "EnableHouse", cfg.enable.enableHouse)
    cfg.enable.enableUpgrades := ReadBool(path, "Enable", "EnableUpgrades", cfg.enable.enableUpgrades)
    cfg.enable.autoEnergy     := ReadBool(path, "Enable", "AutoEnergy", cfg.enable.autoEnergy)
    cfg.enable.autoRopeHook  := ReadBool(path, "Enable", "AutoRopeHook", cfg.enable.autoRopeHook)
    cfg.enable.autoShuriken  := ReadBool(path, "Enable", "AutoShuriken", cfg.enable.autoShuriken)

    ; Coords
    cfg.coords.houseGreenX := ReadInt(path, "Coords", "HouseGreenX", cfg.coords.houseGreenX)
    cfg.coords.houseGreenY := ReadInt(path, "Coords", "HouseGreenY", cfg.coords.houseGreenY)
    cfg.coords.upgGreenX   := ReadInt(path, "Coords", "UpgGreenX",   cfg.coords.upgGreenX)
    cfg.coords.upgGreenY   := ReadInt(path, "Coords", "UpgGreenY",   cfg.coords.upgGreenY)
    cfg.coords.autoEnergyX := ReadInt(path, "Coords", "AutoEnergyX", cfg.coords.autoEnergyX)
    cfg.coords.autoEnergyY := ReadInt(path, "Coords", "AutoEnergyY", cfg.coords.autoEnergyY)

    ; Page detect (separate House / Upgrades)
    cfg.pageDetect.houseX     := ReadInt(path, "PageDetect", "HouseX", cfg.pageDetect.houseX)
    cfg.pageDetect.houseY     := ReadInt(path, "PageDetect", "HouseY", cfg.pageDetect.houseY)
    cfg.pageDetect.houseColor := ReadHex(path, "PageDetect", "HouseColor", cfg.pageDetect.houseColor)

    cfg.pageDetect.upgX       := ReadInt(path, "PageDetect", "UpgX", cfg.pageDetect.upgX)
    cfg.pageDetect.upgY       := ReadInt(path, "PageDetect", "UpgY", cfg.pageDetect.upgY)
    cfg.pageDetect.upgColor   := ReadHex(path, "PageDetect", "UpgColor", cfg.pageDetect.upgColor)

    cfg.pageDetect.tol := ReadInt(path, "PageDetect", "Tol", cfg.pageDetect.tol)

    ; Fly rectangle
    cfg.flyRect.x1 := ReadInt(path, "FlyRect", "X1", cfg.flyRect.x1)
    cfg.flyRect.y1 := ReadInt(path, "FlyRect", "Y1", cfg.flyRect.y1)
    cfg.flyRect.x2 := ReadInt(path, "FlyRect", "X2", cfg.flyRect.x2)
    cfg.flyRect.y2 := ReadInt(path, "FlyRect", "Y2", cfg.flyRect.y2)

    ; Enemy rectangle
    cfg.enemyRect.x1 := ReadInt(path, "EnemyRect", "X1", cfg.enemyRect.x1)
    cfg.enemyRect.y1 := ReadInt(path, "EnemyRect", "Y1", cfg.enemyRect.y1)
    cfg.enemyRect.x2 := ReadInt(path, "EnemyRect", "X2", cfg.enemyRect.x2)
    cfg.enemyRect.y2 := ReadInt(path, "EnemyRect", "Y2", cfg.enemyRect.y2)

    ; Enemy list
    cfg.enemies := ReadEnemiesFromIni(path, cfg)

    ; Fly list (dynamic)
; Preferred format:
; [Flys]
; Count=N
; Fly1Name=Fire
; Fly1Color=0xFD970C
; Fly1Tol=5
;
; Back-compat: if [Flys] missing, we read legacy [Fly] keys and convert.
cfg.flys := ReadFlysFromIni(path, cfg)

; Timing
    cfg.timing.scanIntervalMs      := ReadInt(path, "Timing", "ScanIntervalMs",      cfg.timing.scanIntervalMs)
    cfg.timing.mainPauseMs         := ReadInt(path, "Timing", "MainPauseMs",         cfg.timing.mainPauseMs)
    cfg.timing.greenPauseMs        := ReadInt(path, "Timing", "GreenPauseMs",        cfg.timing.greenPauseMs)
    cfg.timing.greenPreClickDelayMs:= ReadInt(path, "Timing", "GreenPreClickDelayMs",cfg.timing.greenPreClickDelayMs)
    cfg.timing.pageMs              := ReadInt(path, "Timing", "PageMs",              cfg.timing.pageMs)
    cfg.timing.autoEnergyEveryMs   := ReadInt(path, "Timing", "AutoEnergyEveryMs",   cfg.timing.autoEnergyEveryMs)
    cfg.timing.restoreDelayMs     := ReadInt(path, "Timing", "RestoreDelayMs",     cfg.timing.restoreDelayMs)
    cfg.timing.ropeHookCooldownMs := ReadInt(path, "Timing", "RopeHookCooldownMs", cfg.timing.ropeHookCooldownMs)
    cfg.timing.shurikenCooldownMs := ReadInt(path, "Timing", "ShurikenCooldownMs", cfg.timing.shurikenCooldownMs)
    cfg.timing.enemyHoldMs := ReadInt(path, "Timing", "EnemyHoldMs", cfg.timing.enemyHoldMs)
    cfg.timing.attackKeyDelayMs := ReadInt(path, "Timing", "AttackKeyDelayMs", cfg.timing.attackKeyDelayMs)

    ; Starting values capture rectangles
    cfg.startingValues.sv1.x1 := ReadInt(path, "StartingValues", "SV1_X1", cfg.startingValues.sv1.x1)
    cfg.startingValues.sv1.y1 := ReadInt(path, "StartingValues", "SV1_Y1", cfg.startingValues.sv1.y1)
    cfg.startingValues.sv1.x2 := ReadInt(path, "StartingValues", "SV1_X2", cfg.startingValues.sv1.x2)
    cfg.startingValues.sv1.y2 := ReadInt(path, "StartingValues", "SV1_Y2", cfg.startingValues.sv1.y2)

    cfg.startingValues.sv2.x1 := ReadInt(path, "StartingValues", "SV2_X1", cfg.startingValues.sv2.x1)
    cfg.startingValues.sv2.y1 := ReadInt(path, "StartingValues", "SV2_Y1", cfg.startingValues.sv2.y1)
    cfg.startingValues.sv2.x2 := ReadInt(path, "StartingValues", "SV2_X2", cfg.startingValues.sv2.x2)
    cfg.startingValues.sv2.y2 := ReadInt(path, "StartingValues", "SV2_Y2", cfg.startingValues.sv2.y2)
}

WriteConfigToIni(cfg, path)
{
    ; Enable
    IniWrite (cfg.enable.enableHouse ? 1 : 0),    path, "Enable", "EnableHouse"
    IniWrite (cfg.enable.enableUpgrades ? 1 : 0), path, "Enable", "EnableUpgrades"
    IniWrite (cfg.enable.autoEnergy ? 1 : 0),     path, "Enable", "AutoEnergy"
    IniWrite (cfg.enable.autoRopeHook ? 1 : 0), path, "Enable", "AutoRopeHook"
    IniWrite (cfg.enable.autoShuriken ? 1 : 0), path, "Enable", "AutoShuriken"

    ; Coords
    IniWrite cfg.coords.houseGreenX, path, "Coords", "HouseGreenX"
    IniWrite cfg.coords.houseGreenY, path, "Coords", "HouseGreenY"
    IniWrite cfg.coords.upgGreenX,   path, "Coords", "UpgGreenX"
    IniWrite cfg.coords.upgGreenY,   path, "Coords", "UpgGreenY"
    IniWrite cfg.coords.autoEnergyX, path, "Coords", "AutoEnergyX"
    IniWrite cfg.coords.autoEnergyY, path, "Coords", "AutoEnergyY"

    ; Page detect
    IniWrite cfg.pageDetect.houseX, path, "PageDetect", "HouseX"
    IniWrite cfg.pageDetect.houseY, path, "PageDetect", "HouseY"
    IniWrite FormatHex(cfg.pageDetect.houseColor), path, "PageDetect", "HouseColor"

    IniWrite cfg.pageDetect.upgX,   path, "PageDetect", "UpgX"
    IniWrite cfg.pageDetect.upgY,   path, "PageDetect", "UpgY"
    IniWrite FormatHex(cfg.pageDetect.upgColor), path, "PageDetect", "UpgColor"
    IniWrite cfg.pageDetect.tol,    path, "PageDetect", "Tol"

    ; Fly rect
    IniWrite cfg.flyRect.x1, path, "FlyRect", "X1"
    IniWrite cfg.flyRect.y1, path, "FlyRect", "Y1"
    IniWrite cfg.flyRect.x2, path, "FlyRect", "X2"
    IniWrite cfg.flyRect.y2, path, "FlyRect", "Y2"

    ; Enemy rect
    IniWrite cfg.enemyRect.x1, path, "EnemyRect", "X1"
    IniWrite cfg.enemyRect.y1, path, "EnemyRect", "Y1"
    IniWrite cfg.enemyRect.x2, path, "EnemyRect", "X2"
    IniWrite cfg.enemyRect.y2, path, "EnemyRect", "Y2"

    ; Fly list (dynamic)
    WriteFlysToIni(cfg.flys, path)

    ; Enemy list (dynamic)
    WriteEnemiesToIni(cfg.enemies, path)

    ; Timing
    IniWrite cfg.timing.scanIntervalMs,        path, "Timing", "ScanIntervalMs"
    IniWrite cfg.timing.mainPauseMs,           path, "Timing", "MainPauseMs"
    IniWrite cfg.timing.greenPauseMs,          path, "Timing", "GreenPauseMs"
    IniWrite cfg.timing.greenPreClickDelayMs,  path, "Timing", "GreenPreClickDelayMs"
    IniWrite cfg.timing.pageMs,                path, "Timing", "PageMs"
    IniWrite cfg.timing.autoEnergyEveryMs,     path, "Timing", "AutoEnergyEveryMs"
    IniWrite cfg.timing.restoreDelayMs,       path, "Timing", "RestoreDelayMs"

    ; Attack / enemy timing
    IniWrite cfg.timing.ropeHookCooldownMs,    path, "Timing", "RopeHookCooldownMs"
    IniWrite cfg.timing.shurikenCooldownMs,    path, "Timing", "ShurikenCooldownMs"
    IniWrite cfg.timing.enemyHoldMs,           path, "Timing", "EnemyHoldMs"
    IniWrite cfg.timing.attackKeyDelayMs,      path, "Timing", "AttackKeyDelayMs"

    ; Starting values capture
    IniWrite cfg.startingValues.sv1.x1, path, "StartingValues", "SV1_X1"
    IniWrite cfg.startingValues.sv1.y1, path, "StartingValues", "SV1_Y1"
    IniWrite cfg.startingValues.sv1.x2, path, "StartingValues", "SV1_X2"
    IniWrite cfg.startingValues.sv1.y2, path, "StartingValues", "SV1_Y2"

    IniWrite cfg.startingValues.sv2.x1, path, "StartingValues", "SV2_X1"
    IniWrite cfg.startingValues.sv2.y1, path, "StartingValues", "SV2_Y1"
    IniWrite cfg.startingValues.sv2.x2, path, "StartingValues", "SV2_X2"
    IniWrite cfg.startingValues.sv2.y2, path, "StartingValues", "SV2_Y2"
}

; ----------------------------
; ----------------------------
; Small parsing helpers
; ----------------------------

ReadRaw(path, section, key, defVal)
{
    try
        v := IniRead(path, section, key, defVal)
    catch
        v := defVal
    return v
}

ReadInt(path, section, key, defVal)
{
    v := ReadRaw(path, section, key, defVal)
    try
        return Integer(v)
    catch
        return defVal
}

ReadBool(path, section, key, defVal)
{
    v := ReadRaw(path, section, key, defVal ? 1 : 0)
    if (v = 1 || v = "1" || v = true || v = "true" || v = "True" || v = "YES" || v = "yes")
        return true
    if (v = 0 || v = "0" || v = false || v = "false" || v = "False" || v = "NO" || v = "no")
        return false
    return defVal
}

ReadHex(path, section, key, defVal)
{
    v := ReadRaw(path, section, key, FormatHex(defVal))
    if (v = "")
        return defVal
    ; accept 0xRRGGBB or RRGGBB
    if SubStr(v, 1, 2) != "0x"
        v := "0x" v
    try
        return Integer(v)
    catch
        return defVal
}

FormatHex(n)
{
    return Format("0x{:06X}", n & 0xFFFFFF)
}
; ---------- Safe parse helpers for UI text fields ----------
SafeInt(val, defVal)
{
    if IsNumber(val)
        return Integer(val)
    val := Trim(val)
    if (val = "")
        return defVal
    try
        return Integer(val)
    catch
        return defVal
}

SafeHex(val, defVal)
{
    val := Trim(val)
    if (val = "")
        return defVal
    ; accept 0xRRGGBB or RRGGBB
    if (SubStr(val, 1, 2) != "0x" && SubStr(val, 1, 2) != "0X")
        val := "0x" val
    try
        return Integer(val)
    catch
        return defVal
}


FlyGet(fly, key, defVal := "")
{
    ; Supports both Map-based flies and object-based flies.
    try {
        if (fly is Map)
            return fly.Has(key) ? fly[key] : defVal
        return fly.%key%
    } catch {
        return defVal
    }
}

FlySet(fly, key, val)
{
    ; Supports both Map-based flies and object-based flies.
    try {
        if (fly is Map) {
            fly[key] := val
            return
        }
        fly.%key% := val
    } catch {
        ; no-op (ignore invalid keys)
    }
}

Clamp(val, lo, hi)
{
    if (val < lo)
        return lo
    if (val > hi)
        return hi
    return val
}