!include "MUI2.nsh"
!include "x64.nsh"

; Basic settings
Name "Apexlytics"
OutFile "$%GITHUB_WORKSPACE%\apexlytics-installer.exe"
InstallDir "$PROGRAMFILES\Apexlytics"
RequestExecutionLevel admin

; MUI Settings
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Install"
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
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "DisplayVersion" "0.9.0"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "Publisher" "Ajwad Tahmid"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics" "DisplayIcon" "$INSTDIR\apexlytics.exe"
SectionEnd

Section "Uninstall"
  ; Remove shortcuts
  RMDir /r "$SMPROGRAMS\Apexlytics"
  Delete "$DESKTOP\Apexlytics.lnk"

  ; Remove files
  RMDir /r "$INSTDIR"

  ; Remove registry entries
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Apexlytics"
SectionEnd
