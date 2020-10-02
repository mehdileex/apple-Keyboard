
#NoEnv ; Recommended for performance and compatibility with future AutoHotkey releases.
#MaxHotkeysPerInterval 1000
#SingleInstance force ; Replace any previous instance 

DetectHiddenWindows, on
OnMessage(0x00FF, "InputMessage")

SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
;#NoTrayIcon

; Set screen title, to set the HWND
Gui, Show, x0 y0 h0 w0, AppleWKHelper
HWND := WinExist("AppleWKHelper")

hidMessage := 0
isSuspend := 0

; Variable for the modifier key
fnPressed := 0
fnPrevState := 0
ejPressed := 0
ejPrevState := 0
pwrPressed := 0
pwrPrevState := 0

; Variable for Fn <> Lctrl
lctrlPressed := 0
lctrlPrevState := 0

; set this to 0 if you're not running windows on Bootcamp (aka: Normal PC)
bootcampWindows := 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; handle HID input, set global vars, call modKeysProcessing

; List all of the "Raw Input" devices available for use and allow 
; capture of output 
; 
; There may be more than one 'raw' device per device actually attached 
; to the system. This is because these devices generally represent 
; "HID Collections", and there may be more than one HID collection per 
; USB device. For example, the Natural Keyboard 4000 supports a normal
; keyboard HID collection, plus an additional HID collection that can 
; be used for the zoom slider and other important buttons

SizeofRawInputDeviceList	:= A_PtrSize * 2
SizeofRawInputDevice		:= 8 + A_PtrSize

RIM_TYPEMOUSE				:= 0
RIM_TYPEKEYBOARD			:= 1
RIM_TYPEHID					:= 2

RIDI_DEVICENAME				:= 0x20000007
RIDI_DEVICEINFO				:= 0x2000000b

RIDEV_INPUTSINK				:= 0x00000100

RID_INPUT					:= 0x10000003

DoCapture					:= 0


;;get count of HID devices
Res := DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", Count, UInt, SizeofRawInputDeviceList)
VarSetCapacity(RawInputList, SizeofRawInputDeviceList * Count)

;;get list of HID devices
Res := DllCall("GetRawInputDeviceList", "Ptr", &RawInputList, "UInt*", Count, "UInt", SizeofRawInputDeviceList)

rimHIDregistered := 0

Loop %Count% ;for all HID devices
{
	Handle := NumGet(RawInputList, (A_Index - 1) * SizeofRawInputDeviceList, "UInt")
	Type := NumGet(RawInputList, ((A_Index - 1) * SizeofRawInputDeviceList) + A_PtrSize, "UInt")
	if (Type = RIM_TYPEMOUSE)
		TypeName := "RIM_TYPEMOUSE"
	else if (Type = RIM_TYPEKEYBOARD)
		TypeName := "RIM_TYPEKEYBOARD"
	else if (Type = RIM_TYPEHID)
		TypeName := "RIM_TYPEHID"
	else
		TypeName := "RIM_OTHER"

; get HID device name length  
	Res := DllCall("GetRawInputDeviceInfo", "Ptr", Handle, "UInt", RIDI_DEVICENAME, "Ptr", 0, "UInt *", nLength)
	VarSetCapacity(Name, (nLength + 1) * 2)
; get HID device name
	Res := DllCall("GetRawInputDeviceInfo", "Ptr", Handle, "UInt", RIDI_DEVICENAME, "Str", Name, "UInt*", nLength)

; get HID device info   
	Res := DllCall("GetRawInputDeviceInfo", "Ptr", Handle, "UInt", RIDI_DEVICEINFO, "Ptr", 0, "UInt *", iLength)
	VarSetCapacity(Info, iLength)
	NumPut(iLength, Info, 0, "UInt") ;Put length in struct RIDI_DEVICEINFO
	
	Res := DllCall("GetRawInputDeviceInfo", "Ptr", Handle, "UInt", RIDI_DEVICEINFO, "UInt", &Info, "UInt *", iLength)

; Keyboards are always Usage 6, Usage Page 1, Mice are Usage 2, Usage Page 1, 
; HID devices specify their top level collection in the info block


; AWK modifier buttons is separate TYPEHID (rather keyboard standard buttons)
	if (Type = RIM_TYPEHID)
	{
		Vendor := NumGet(Info, 4 * 2, "UShort")
		Product := NumGet(Info, 4 * 3, "UShort")
		Version := NumGet(Info, 4 * 4, "UShort")
		UsagePage := NumGet(Info, (4 * 5), "UShort")
		Usage := NumGet(Info, (4 * 5) + 2, "UShort")
	}

	VarSetCapacity(RawDevice, SizeofRawInputDevice, 0)
	NumPut(RIDEV_INPUTSINK, RawDevice, 4)
	NumPut(HWND, RawDevice, 8)

	if (Type = RIM_TYPEHID && Vendor = 1452  && rimHIDregistered = 0) ; AWK Vendor number
	{
		rimHIDregistered := 1
		NumPut(UsagePage, RawDevice, 0, "UShort")
		NumPut(Usage, RawDevice, 2, "UShort")	  
; Register AWK modifier buttons HID
		Res := DllCall("RegisterRawInputDevices", "UInt", &RawDevice, UInt, 1, UInt, SizeofRawInputDevice) 
		if (Res = 0)
		{
			MsgBox, Failed to register for AWK device!
			ExitApp
		}
	}
}

Count := 1 

InputMessage(wParam, lParam, msg, hwnd)
{
	global hidMessage   
	global isSuspend
	global RIM_TYPEMOUSE, RIM_TYPEKEYBOARD, RIM_TYPEHID 
	global RID_INPUT 

	; get HID input
	Res := DllCall("GetRawInputData", "UInt", lParam, "UInt", RID_INPUT, "Ptr", 0, "UInt *", Size, "UInt", 8 + A_PtrSize * 2)
	VarSetCapacity(Buffer, Size)
	Res := DllCall("GetRawInputData", "UInt", lParam, "UInt", RID_INPUT, "Ptr", &Buffer, "UInt *", Size, "UInt", 8 + A_PtrSize * 2)
   
	Type := NumGet(Buffer, 0, "UInt")

	if (Type = RIM_TYPEHID)
	{
		SizeHid := NumGet(Buffer, (8+A_PtrSize*2), "UInt")
		InputCount := NumGet(Buffer, (12+A_PtrSize*2), "UInt")
		Loop %InputCount% {
			Addr := &Buffer + (16+A_PtrSize*2) + ((A_Index - 1) * SizeHid)
			hidMessage := Mem2Hex(Addr, SizeHid)
			ProcessHIDData(wParam, lParam)
		}
	}
	return
}

Mem2Hex( pointer, len )
{
	multiply := 0x100
	Hex := 0
	Loop, %len%
	{
		Hex := Hex * multiply
		Hex := Hex + *Pointer+0
		Pointer ++
	}
	Return Hex 
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; set global vars for further handling

ProcessHIDData(wParam, lParam)
{
  	global hidMessage
	global isSuspend
	
	global fnPressed
	global fnPrevState
	global ejPressed
	global ejPrevState
	global pwrPressed
	global pwrPrevState

	SetTimer, SendDelete, Off			

; Filter bit 5 (Fn key)
	Transform, FnValue, BitAnd, 0xFF10, hidMessage

	if (FnValue = 0x1110) ; Fn is pressed
	{
		fnPrevState := fnPressed
		fnPressed := 1
	} 
	else ; Fn is released
	{
		fnPrevState := fnPressed
		fnPressed := 0
	}

; Filter bit 4 (Eject key)
  Transform, FnValue, BitAnd, 0xFF08, hidMessage
  
	if (FnValue = 0x1108) ; Eject is pressed
	{
		ejPrevState := ejPressed
		ejPressed := 1
	} 
	else ; Eject is Released
	{
		ejPrevState := ejPressed
		ejPressed := 0
	}

; Filter bit 1 fnd 2 (Power key)
	Transform, FnValue, BitAnd, 0xFF03, hidMessage
	if (FnValue = 0x1303) ; Power is pressed
	{ 
		pwrPrevState := 0
		pwrPressed := 1
		 
	}
	if (fnValue = 0x1302) ; Power is released
	{ 	
		pwrPrevState := 1
		pwrPressed := 0
		; no anything doing оn power button release
	}
  
  if (isSuspend = 0)
	modKeysProcessing()

}

modKeysProcessing()  ; handle keypressing for modifier keys
{
	global fnPressed
  	global ejPressed
  	global ejPrevState
  	global fnPrevState

  	global lctrlPressed
  	global lctrlPrevState

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Eject = delete with delay and repeat
	if(lctrlPressed = 0) 								  		; eject only pressed
  	{               		
     	if(ejPressed = 1 and ejPrevState = 0)
	 	{	
			if(GetKeyState("Shift") or GetKeyState("Alt") or GetKeyState("Control"))
			{
				SendInput {Blind}{Delete}                   ; Edit::Cut and other w|o repeating
			}
			else if(fnPressed = 1)
			{
				SendInput {Ctrl}{Delete}                   	; ctrl - del 
			}
			else
			{										  	   	; No modifiers = Del with repeating
				SendInput {Delete}
				SetTimer, SendDelete, -700           		; Delay for start repeating
			}
    	}
  	}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; fn = rCtrl

	if (ejPressed = 0)								; fn only pressed
  	{
		if (fnPressed = 1 and fnPrevState = 0)     	; fn down
        	SendInput {rCtrl Down}
		
		if (fnPressed = 0 and fnPrevState = 1)     	; fn up
 	    	SendInput {rCtrl Up}
  	}


}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Send Delete keystroke repeatedly while Eject still pressed

SendDelete:
	; repeating del while Eject still down
if (ejPressed = 1)
{
	SendInput {delete}
	SetTimer, SendDelete, -40			
}
Return

chkSuspend()
{
	
	global fnPressed
	global fnPrevState
	global ejPressed
	global ejPrevState
	global lctrlPressed
	global lctrlPrevState
	global pwrPressed
	global pwrPrevState
	global isSuspend	
	
	if (isSuspend = 0)
	{
		isSuspend := 1
		
		fnPressed := 0
		fnPrevState := 0
		ejPressed := 0
		ejPrevState := 0
		pwrPressed := 0
		pwrPrevState := 0
		lctrlPressed := 0
		lctrlPrevState := 0
		
		Suspend , On
		SetTimer, SendDelete, Off			
		SendInput {rCtrl Up}
		TrayTip, AWK Helper, Suspended, 1, 1
		Soundplay , off.wav		
	}
	else
	{
		isSuspend := 0
		Suspend , Off
		TrayTip, AWK Helper, Restored, 1, 1
		Soundplay , on.wav	
	}	
}


; switch F12 to Insert
;*F12::sendInput {Blind}{Insert}


; lctrl = fn
; get up and down Lcontrol, sets global variables

$*lControl up::LCtrlUp()
LCtrlUp()
{
	global lctrlPressed
  	global lctrlPrevState

  	lctrlPrevState := 1
  	lctrlPressed := 0

  	SendInput {F24 up} ; previously {LCtrl up}
}
Return

$*lControl::LCtrlDn()
LCtrlDn()
{
	global lctrlPressed
  	global lctrlPrevState

  	lctrlPrevState := 0
  	lctrlPressed := 1
  
  	SetTimer, SendDelete, Off			

  	SendInput {F24 down} ; previously {LCtrl down}
}
Return


 

;-----------------------------------------
; Mac keyboard to Windows Key Mappings
;=========================================

; --------------------------------------------------------------
; NOTES
; --------------------------------------------------------------
; ! = ALT
; ^ = CTRL
; + = SHIFT
; # = WIN
;
; Debug action snippet: MsgBox You pressed Control-A while Notepad is active.

#InstallKeybdHook
#SingleInstance force
SetTitleMatchMode 2
SendMode Input

; --------------------------------------------------------------
; Mac-like screenshots in Windows (requires Windows 10 Snip & Sketch)
; --------------------------------------------------------------

; Capture entire screen with CMD/WIN + SHIFT + 3
#+3::send #{PrintScreen}

; Capture portion of the screen with CMD/WIN + SHIFT + 4
#+4::#+s

; --------------------------------------------------------------
; media/function keys all mapped to the right option key
; --------------------------------------------------------------

RAlt & F7::SendInput {Media_Prev}
RAlt & F8::SendInput {Media_Play_Pause}
RAlt & F9::SendInput {Media_Next}
F10::SendInput {Volume_Mute}
F11::SendInput {Volume_Down}
F12::SendInput {Volume_Up}

; swap left command/windows key with left alt
LWin::LAlt
RWin::RAlt
;LAlt::LWin ; add a semicolon in front of this line if you want to disable the windows key

; Remap Windows + Left OR Right to enable previous or next web page
; Use only if swapping left command/windows key with left alt
;Lwin & Left::Send, !{Left}
;Lwin & Right::Send, !{Right}

; Eject Key
;F20::SendInput {Insert} ; F20 doesn't show up on AHK anymore, see #3

; F13-15, standard windows mapping
F13::SendInput {PrintScreen}
F14::SendInput {ScrollLock}
F15::SendInput {Pause}

;F16-19 custom app launchers, see http://www.autohotkey.com/docs/Tutorial.htm for usage info
F16::Run http://twitter.com
F17::Run http://tumblr.com
F18::Run http://www.reddit.com
F19::Run https://facebook.com

; --------------------------------------------------------------
; OS X system shortcuts
; --------------------------------------------------------------

; Make Ctrl + S work with cmd (windows) key
#s::Send, ^s

; Selecting
#a::Send, ^a

; Copying
#c::Send, ^c

; Pasting
#v::Send, ^v

; Cutting
#x::Send, ^x

; Opening
#o::Send ^o

; Finding
#f::Send ^f

; Undo
#z::Send ^z

; Redo
#y::Send ^y

; New tab
#t::Send ^t

; close tab
#w::Send ^w

; Close windows (cmd + q to Alt + F4)
#q::Send !{F4}

; Remap Windows + Tab to Alt + Tab.
Lwin & Tab::AltTab

; minimize windows
#m::WinMinimize,a


; --------------------------------------------------------------
; OS X keyboard mappings for special chars
; --------------------------------------------------------------

; Map Alt + L to @
!l::SendInput {@}

; Map Alt + N to \
+!7::SendInput {\}

; Map Alt + N to ©
!g::SendInput {©}

; Map Alt + o to ø
!o::SendInput {ø}

; Map Alt + 5 to [
!5::SendInput {[}

; Map Alt + 6 to ]
!6::SendInput {]}

; Map Alt + E to €
!e::SendInput {€}

; Map Alt + - to –
!-::SendInput {–}

; Map Alt + 8 to {
!8::SendInput {{}

; Map Alt + 9 to }
!9::SendInput {}}

; Map Alt + - to ±
!+::SendInput {±}

; Map Alt + R to ®
!r::SendInput {®}

; Map Alt + N to |
!7::SendInput {|}

; Map Alt + W to ∑
!w::SendInput {∑}

; Map Alt + N to ~
!n::SendInput {~}

; Map Alt + 3 to #
!3::SendInput {#}



; --------------------------------------------------------------
; Custom mappings for special chars
; --------------------------------------------------------------

;#ö::SendInput {[} 
;#ä::SendInput {]} 

;^ö::SendInput {{} 
;^ä::SendInput {}} 


; --------------------------------------------------------------
; Application specific
; --------------------------------------------------------------

; Google Chrome
#IfWinActive, ahk_class Chrome_WidgetWin_1

; Show Web Developer Tools with cmd + alt + i
#!i::Send {F12}

; Show source code with cmd + alt + u
#!u::Send ^u

#IfWinActive
 ; Variable for Fn <> Lctrl
SC16A::Lctrl
Lctrl::SC16A