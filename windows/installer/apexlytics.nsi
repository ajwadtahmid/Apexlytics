Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

; Basic settings
Name "Apexlytics"
OutFile "$%GITHUB_WORKSPACE%\apexlytics-installer.exe"
; Fixed subfolder with no directory page: the uninstaller removes $INSTDIR
; recursively, so a user-chosen path like D:\Games would be wiped entirely.
; $PROGRAMFILES64 because makensis builds a 32-bit installer, where plain
; $PROGRAMFILES resolves to "Program Files (x86)".
InstallDir "$PROGRAMFILES64\Apexlytics"
RequestExecutionLevel admin

; MUI Settings
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "Apexlytics requires 64-bit Windows."
    Abort
  ${EndIf}

  ; NSIS still honours `installer.exe /D=D:\Games` with no directory page, and
  ; the uninstaller removes $INSTDIR recursively. Always use the fixed folder.
  StrCpy $INSTDIR "$PROGRAMFILES64\Apexlytics"

  ; A running copy keeps its exe and DLLs locked, so files would be skipped and
  ; a mix of versions left behind. The window class is the Flutter runner's.
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "Apexlytics"
  ${If} $0 <> 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "Apexlytics is running. Close it, then run this installer again."
    Abort
  ${EndIf}
FunctionEnd

Function un.onInit
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "Apexlytics"
  ${If} $0 <> 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "Apexlytics is running. Close it, then run the uninstaller again."
    Abort
  ${EndIf}
FunctionEnd

Section "Install"
  ; Machine-wide install (Program Files, HKLM), so shortcuts must be too;
  ; otherwise they land in whichever profile the UAC prompt elevated as.
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"

  ; Copy all files from the Release folder
  File /r "$%GITHUB_WORKSPACE%\build\windows\x64\runner\Release\*.*"

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\Apexlytics"
  CreateShortcut "$SMPROGRAMS\Apexlytics\Apexlytics.lnk" "$INSTDIR\apexlytics.exe" "" "$INSTDIR\apexlytics.exe" 0
  CreateShortcut "$SMPROGRAMS\Apexlytics\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  ; Create Desktop shortcut
  CreateShortcut "$DESKTOP\Apexlytics.lnk" "$INSTDIR\apexlytics.exe" "" "$INSTDIR\apexlytics.exe" 0

  ; Add to Add/Remove Programs
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "DisplayName" "Apexlytics"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "UninstallString" "$INSTDIR\uninstall.exe"
  ; Substituted by makensis at compile time, same as $%GITHUB_WORKSPACE%
  ; above — set from the release tag in build-release.yml. Don't hand-edit;
  ; it would just go stale again.
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "DisplayVersion" "$%PRODUCT_VERSION%"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "Publisher" "Ajwad Tahmid"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "DisplayIcon" "$INSTDIR\apexlytics.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64

  ; Remove shortcuts
  RMDir /r "$SMPROGRAMS\Apexlytics"
  Delete "$DESKTOP\Apexlytics.lnk"

  ; Remove files
  RMDir /r "$INSTDIR"

  ; Remove registry entries
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics"
SectionEnd
