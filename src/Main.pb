; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
; [SteamRoller] appcache autopatcher v0.56
; Developed in 2015 by Victoria A. Guevara
; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

EnableExplicit ; Essential.

;{ [Definitions]
;{ --Constants--
#Options		= "Collateral rules"
#NoAcess    = "Unable to access ["
#DB_naming	= "appinfo.vdf"
#RuleFile		= "Ruleset.ini"
#SubCache		= "\appcache\"
#Title			= "=[SteamRoller]="
#BackupExt	= ".bak"
#MarkupChar = "`"
#CommandChar= ";"
#InFile			= 0
#OutFile		= 1
;}
;{ --Enumerations--
Enumeration ; Type identifiers.
#TYPE_NONE
#TYPE_STRING
#TYPE_INT
#TYPE_FLOAT
#TYPE_PTR
#TYPE_WSTRING
#TYPE_COLOR
#TYPE_UINT64
#TYPE_NUMTYPES
EndEnumeration
;}
;{ --Structures--
Structure Header
Sign.l
Version.l
EndStructure

Structure FieldRules
Map ValTable.s()
EndStructure
;}
;{ --Macros block--
Macro ReadAscString(File) ; [I/O]
ReadString(File, #PB_Ascii | #PB_File_IgnoreEOL)
EndMacro

Macro MirrorString(File, String) ; [I/O]
WriteString(File, String, #PB_Ascii) : WriteByte(File, 0)
EndMacro

Macro MaxPathBytes() ; [I/O]
#MAX_PATH * SizeOf(Unicode) + 1
EndMacro

Macro NormalizePath(Path) ; [I/O.next]
ReplaceString(ReplaceString(Path, "/", "\"), "\\", "\")
EndMacro

Macro BoolPref(Key, Shim = #True, Sect = #Options) ; [INI]
Bool(Val(RequestPref(Key, Sect, Str(Shim))))
EndMacro

Macro Echo(Text, Color = 7, Hack =N) ; [GUI]
ConsoleColor(Color, 0) : Print#Hack(Text)
EndMacro

Macro Delim() ; [GUI]
Echo(LSet("", 45, "-"), 8) 
EndMacro

Macro Inform(Text, Cat) ; [GUI]
Echo("[" + Cat + "]:: ", 11, _) : Echo(Text, 15)
EndMacro

Macro Assert(Key, Value) ; [GUI]
Echo(" ->: ", 3, _) : Echo("<" + Key + "> == " + Value, 6)
EndMacro

Macro AssertPref(Key, Value, Prefix) ; [GUI]
Assert(Prefix + "::" + Key, Value)
EndMacro

Macro AssertStrPref(Key, Prefix, Section = #Options, DefShim = #True) ; [GUI]
AssertPref(Key, RequestPref(Key, Section, DefShim), Prefix)
EndMacro

Macro AssertBoolPref(Key, Prefix, Section = #Options, DefShim = #True, TruthShim = "enabled", FalseShim = "disabled") ; [GUI]
AssertPref(Key, IIFS(BoolPref(Key, DefShim, Section), TruthShim, FalseShim), Prefix)
EndMacro

Macro ExitSoon(Sec = 5) ; [GUI.next]
Echo("Exiting in " + Str(Sec) + " seconds...", 14) : Delay((Sec) * 1000) : End
EndMacro

Macro Fault(Text) ; [GUI.next]
Echo("<FAULT>:: " + Text + " !", 12)	
CompilerIf Defined(BackupFile, #PB_Variable)	; [Convenience]
CloseFile(#InFile) : CloseFile(#OutFile) 			; Closing -> copying back:
If CopyFile(BackupFile, VDFile) : Inform(#DB_naming + " was restored from backup.", "i/o") : EndIf
CompilerEndIf				 													; [Convenience]
Delim() : ExitSoon()													; Report quitting.
EndMacro

Macro Inquire(Request, Title = #Title) ; [Win.GUI]
Bool(MessageRequester(Title, Request, #PB_MessageRequester_YesNo) = #PB_MessageRequester_Yes)
EndMacro

Macro PartEqual(Text, Template) ; [Logick]
Bool(Text = Left(Template, Len(Text)))
EndMacro
;}
;{ --Procedures--
Procedure.s IIFS(Log.i, Truth.s, False.s) ; Basic logic.
If Log : ProcedureReturn Truth : Else : ProcedureReturn False : EndIf
EndProcedure

Procedure Print_(Text.s) ; Dummy.
Print(Text) ; So, Print_ == Print, actually.
EndProcedure

Procedure CheckCommand(Text.s, Cmd.s)
If Left(Text, 1) = #CommandChar : ProcedureReturn PartEqual(LCase(Mid(Text, 2)), LCase(Cmd)) : EndIf
EndProcedure

Procedure.s RequestPref(Key.s, Section.s = "", Shim.s = "")
If Section : PreferenceGroup(Section.s) : EndIf		; Changing section for requested one.
DisableDebugger   																; [Essential fix]
Define PrefVal.s = ReadPreferenceString(Key, "")	; Actual preference absorbtion.
EnableDebugger																		; [Essential fix]
If Shim And PrefVal = "" : WritePreferenceString(Key, Shim) : PrefVal = Shim : EndIf ; Using shim to actualize field.
ProcedureReturn PrefVal
EndProcedure

Procedure.s ParseMarkup(Text.s)
If Left(Text, 1) = #MarkupChar : Text = Mid(Text, 2)
If Left(Text, 1) = #MarkupChar : ProcedureReturn Text : EndIf
ProcedureReturn #CommandChar + Text
Else : ProcedureReturn Text
EndIf
EndProcedure

Procedure AssertRuletable(Map RTable.FieldRules(), Section.s)
PreferenceGroup(Section.s)	; Setting current section.
ExaminePreferenceKeys()		  ; Preparing key query.
Section = Mid(Section, 2)   ; Trailing '*' deletion.
AddMapElement(RTable(), Section) ; Registering element at table.
Define KeyCount.i           ; Total template counter.
While NextPreferenceKey()   ; For all found keys...
RTable()\ValTable(PreferenceKeyName()) = ParseMarkup(PreferenceKeyValue()) : KeyCount + 1 ; Adding found keys to ruleset.
Wend
If KeyCount                 ; If any translation rules was found...
Assert("field::[" + Section + "]", KeyCount + " entries")
Else : DeleteMapElement(RTable()) ; If nothing to translate here - discarding.
EndIf
EndProcedure

Procedure CheckRunning(ExeFile.s)
Define ProcInfo.PROCESSENTRY32, Snap = CreateToolhelp32Snapshot_(#TH32CS_SNAPPROCESS, 0) ; Preparing all required API.
Define Lib = OpenLibrary(#PB_Any, "psapi.dll"), *PathQueryProc = GetFunction(Lib, "GetModuleFileNameExW")
ExeFile = LCase(ExeFile)											; Preparing for comparation.
If Snap : ProcInfo\dwSize = SizeOf(ProcInfo)	; Initializing data accum.
If Process32First_(Snap, @ProcInfo) 					; Initializing process snapshoot.
While Process32Next_(Snap, @ProcInfo)					; Looping through processae.
; Actual comparsion:[
Define *hProcess = OpenProcess_(#PROCESS_QUERY_INFORMATION|#PROCESS_VM_READ, #False, ProcInfo\th32ProcessID)
Define ProcPath.s{#MAX_PATH} = "" : CallFunctionFast(*PathQueryProc, *hProcess, 0, @ProcPath, MaxPathBytes())
CloseHandle_(*hProcess) : If LCase(ProcPAth) = ExeFile : Define Found = #True : Break : EndIf ; If we found what we want - quit.
; ]:Actual comparison.
Wend	; Closing everything back now:
EndIf : CloseLibrary(Lib) : CloseHandle_(snap)
EndIf : ProcedureReturn Found
EndProcedure
;}
;} {End/Definitions}

;{ ==Preparations==
; =GUI setup=
OpenConsole() : ConsoleTitle(#Title) ; Main GUI port.
Echo("; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-", 10)
Echo("; [SteamRoller] appcache autopatcher v0.56"	, 10)
Echo("; Developed in 2015 by Victoria A. Guevara"	, 10)
Echo("; -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-" + #CRLF$, 10)

; =Primary initialization=
Define hKey.i, SteamRoot.s{#MAX_PATH}, SteamExe.s{#MAX_PATH}, PathLen
RegOpenKeyEx_(#HKEY_CURRENT_USER, "Software\Valve\Steam", 0, #KEY_QUERY_VALUE, @hKey) 
If hKey ; Main target directory request:
PathLen = MaxPathBytes() : RegQueryValueEx_(hKey, "SteamPath", 0, 0, @SteamRoot, @PathLen)
PathLen = MaxPathBytes() : RegQueryValueEx_(hKey, "SteamExe", 0, 0, @SteamExe, @PathLen)
RegCloseKey_(hKey) : SteamExe = NormalizePath(SteamExe) : SteamRoot = NormalizePath(SteamRoot)																											
Else : Fault("Unable to access registry data for Steam")	; <ERROR !>
EndIf		; Aux target directory request:
Define FixDir.s = GetPathPart(ProgramFilename())
If FixDir <> GetTemporaryDirectory() : SetCurrentDirectory(FixDir) : EndIf
If CheckRunning(SteamExe) And Inquire("Steam client is already running. Exit ?") ; =WinGUI request=
Echo("Terminated by user request.", 4) : End : EndIf					 ; Special echo for prelimiray exit.
Inform("Steam base path extracted from registry data.", "sys") ; [Progress]
Assert("Steam dir", SteamRoot) : Assert("Steam exe", SteamExe) ; (rem)

; =Pathing initialization=:
Define VDFile.s			= SteamRoot + #SubCache + #DB_naming
Define BackupFile.s	= VDFile + #BackupExt
Define HDR.Header, IChar.A, Aux.s, Patches.i
NewMap Fields.FieldRules()
Inform("All auxilary paths appointed.", "i/o") ; [Progress]
Assert("Source datafile", VDFile) : Assert("Backup file", BackupFile) ; (rem)

; =Ruleset initialization=
#IniPrefix = "ini"
If Not OpenPreferences(#RuleFile)	: Fault(#NoAcess + #RuleFile + "]")	: EndIf	; <ERROR !>
Inform("Rulefile initialized for access.", "aux") ; [Progress]
ExaminePreferenceGroups()
While NextPreferenceGroup() : Define Section.s = PreferenceGroupName()
Select Section                                    ; /Sorting by section name:
Case "Collateral rules"                           ; --Common options.
AssertBoolPref("BackupScript", #IniPrefix)				; (rem)
AssertBoolPref("WaitForSteam", #IniPrefix)				; (rem)
Default : If PeekC(@Section) = '*' And Len(Section) > 1 ; --Field translation table.
AssertRuletable(Fields(), Section)                ; (rem) 
EndIf
EndSelect
Wend
If MapSize(Fields()) = 0 : Fault("No rules was found for translation table") : EndIf

; =IO initialization=
If Not CopyFile(VDFile, BackupFile)		: Fault("Unable to make backup copy for [" + #DB_naming + "]") : EndIf ; <ERROR !>
If Not ReadFile(#InFile, BackupFile)	: Fault(#NoAcess + BackupFile + "]")	: EndIf	; <ERROR !>
If Not CreateFile(#OutFile, VDFile)		: Fault(#NoAcess + VDFile + "]")			: EndIf	; <ERROR !>

; =Streaming initialization=
ReadData(#InFile, @HDR, SizeOf(Header))
If HDR\Sign <> $7564427 Or HDR\Version <> 1 : Fault("Incorrect .VDF header encountered") : EndIf ; <ERROR !>
WriteData(#OutFile, @HDR, SizeOf(Header))
Inform("Header integrity check passed.", "aux") ; [Progress]
Assert("Header\sign", "0x" + Hex(HDR\Sign)) : Assert("Header\ver", HDR\Version) ; (rem)
;}
;{ ==Main loop==
Delim()           ; GUI separator.
While Not Eof(#InFile) : IChar = ReadAsciiCharacter(#InFile)
Select IChar			; Primary state analyzis:
Case #TYPE_STRING : Define Key.s = ReadAscString(#InFile), StrVal.s = ReadAscString(#InFile)	; String record beginning signal.
If Fields(Key)	      																																				; Ruleset key lookup.
If StrVal And FindMapElement(Fields()\ValTable(), StrVal)                                     ; If there are anything to patch...
Aux = Fields()\ValTable() : Patches + 1				      													             		; Dictionary lookup for parsed value.
If CheckCommand(Aux, "delete")                                                                ; If deletion was set in rule table...
Inform("Entry was deleted for [" + Key + "] record.", "*" + Hex(Loc(#InFile)))                ; Primery deletion report for location.
Assert(StrVal, "/nil/") : Continue                                                            ; Secondary report for found key
Else : Inform("Patch was applied for [" + Key + "] record.", "*" + Hex(Loc(#InFile)))	        ; Primary fix report with location.
Assert(StrVal, Aux) : StrVal = Aux              																							; Secondary report for made change.
EndIf : EndIf : EndIf
WriteAsciiCharacter(#OutFile, IChar) : MirrorString(#OutFile, Key) : MirrorString(#OutFile, StrVal) ; Record mirroring.
Default : WriteAsciiCharacter(#OutFile, IChar)                                                ; Unconditonal byte mirroring.
EndSelect
Wend
If Patches : Delim() : EndIf ; GUI separator.
;}
;{ ==AfterMath==
CloseFile(#InFile) : CloseFile(#OutFile)
Define BackupScript.s = SteamRoot + #SubCache + "\Restore [" + #DB_naming + "].bat"
If Patches                              ; If any patching was done....
If BoolPref("BackupScript")	And Patches ; Restorative scripting:
CreateFile(#OutFile, BackupScript)
WriteString(#OutFile, ~"@copy \"" + BackupFile + ~"\" \"" + VDFile + ~"\" >nul")
Inform("Backup script file created in appcache.", "fin") : Assert("Script path", BackupScript) ; Progress @ remark.
CloseFile(#OutFile) 
EndIf : Else : DeleteFile(BackupScript) ; Backup deletion (script as well) if no patches:
If Not DeleteFile(BackupFile)	: Fault(#NoAcess + #RuleFile + "]") : EndIf
Inform("No patching was done, backup file discraded.", "fin")
EndIf	; Final preparations:
If BoolPref("WaitForSteam", #False) : Define WaitFlag = #True : EndIf
Echo("Work complete ! Launching Steam client...", 10)
If CheckRunning(SteamExe) : WaitFlag = #False : EndIf
RunProgram(SteamExe, "", "", WaitFlag * #PB_Program_Wait)
If Not WaitFlag : ExitSoon() : EndIf
;}
; IDE Options = PureBasic 5.40 LTS (Windows - x86)
; ExecutableFormat = Console
; Folding = B-z
; EnableUnicode
; EnableXP
; EnableUser
; UseIcon = main_icon.ico
; Executable = ..\SteamRoller.exe
; CurrentDirectory = ..\
; IncludeVersionInfo
; VersionField0 = 0,5,6,0
; VersionField1 = 0,5,6,0
; VersionField2 = Guevara-chan [~R.i.P]
; VersionField3 = [SteamRoller]
; VersionField4 = 0.56
; VersionField5 = 0.56
; VersionField6 = [SteamRoller] appcache autopatcher
; VersionField7 = [SteamRoller]
; VersionField8 = SteamRoller.exe
; VersionField13 = Guevara-chan@Mail.ru
; VersionField14 = http://vk.com/guevara_chan