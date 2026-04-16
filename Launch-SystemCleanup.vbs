Option Explicit

Dim scriptPath
scriptPath = "D:\Users\joty79\scripts\SystemCleanup\SystemCleanup.ps1"

Dim wtPath
Dim wtArgs

On Error Resume Next
wtPath = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\wt.exe"
On Error GoTo 0

If Len(wtPath) > 0 Then
    wtArgs = "-w 0 nt --title ""SystemCleanup"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -WtHosted"
    CreateObject("Shell.Application").ShellExecute wtPath, wtArgs, "", "runas", 1
Else
    CreateObject("Shell.Application").ShellExecute "pwsh.exe", "-NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """", "", "runas", 1
End If
