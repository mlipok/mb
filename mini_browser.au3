#NoTrayIcon
#include 'cefau3/cefau3.au3'

; startup =========================

global $cef = CefStart(default)

$cef.EnableHighDPISupport()

global $cef_app = $cef.new('App'), _
	$cef_args = $cef.new('MainArgs')

if ($cef.ExecuteProcess($cef_args.__ptr, $cef_app.__ptr) >= 0) then exit

global $width = 1000, $height = 600, $gui_title = 'Mini Browser'
global $url = 'https://www.google.com/'

global $html_dir = @scriptdir & '\app'
global $toolbar_height = 30

; gui =========================

Opt('GUIOnEventMode', 1)

global $hMainGUI = GUICreate($gui_title, $width, $height, -1, -1, 0x00CF0000)
GUISetBkColor(0xffffff)

; cef components =========================

global $cef_settings = $cef.new('Settings'), _
	$cef_bs = $cef.new('BrowserSettings')

$cef_settings.single_process = 1 ; // cannot multiple process!
$cef_settings.multi_threaded_message_loop = 1
$cef_settings.cache_path = @scriptdir & '\cache'

if ($cef.Initialize($cef_args.__ptr, $cef_settings.__ptr, $cef_app.__ptr) == 0) then exit

global $cef_winfo = $cef.new('WindowInfo')
$cef_winfo.parent_window = $hMainGUI
$cef_winfo.style = 0x40000000 ; ws_child

global $toolbar_client = $cef.new('Client')
global $toolbar_lifespan = $cef.new('LifeSpanHandler')

$toolbar_client.GetLifeSpanHandler = toolbar_getLifeSpanHandler
$toolbar_lifespan.OnAfterCreated = toolbar_onAfterCreated

; =========================

global $browser_client = $cef.new('Client'), _
	$browser_lifespan = $cef.new('LifeSpanHandler'), _
	$browser_display = $cef.new('DisplayHandler')

$browser_client.GetLifeSpanHandler = browser_getLifeSpanHandler
$browser_client.GetDisplayHandler = browser_getDisplayHandler

$browser_lifespan.OnAfterCreated = browser_onAfterCreated

$browser_display.OnTitleChange = browser_onTitleChange
$browser_display.OnAddressChange = browser_onAddressChange
$browser_display.OnFaviconUrlChange = browser_onFaviconUrlChange

; =========================

global $app_renderprocess = $cef.new('RenderProcessHandler')
global $app_v8 = $cef.new('V8Handler')

$app_v8.Execute = app_execute
$cef_app.GetRenderProcessHandler = app_getRenderProcessHandler
$app_renderprocess.OnWebKitInitialized = app_onWebKitInitialized

; =========================

global $toolbar_hwnd = 0, $browser_hwnd = 0
global $main_frame = 0, $main_browser = 0, $toolbar_frame = 0
global $rcGUI = DllStructCreate('int[2];int w;int h')

$cef.CreateBrowser($cef_winfo.__ptr, $toolbar_client.__ptr, _
	'file:///' & $html_dir & '\index.html', $cef_bs.__ptr, null)

; add gui event =========================

GUISetOnEvent(-3, '__exit')
GUIRegisterMsg(0x0005, '__sizing')
OnAutoItExitRegister('CefExit') ; ~ force exit

; main windows loop =========================

CefWndMsg_RunLoop()

; callback/handler event =========================

func __exit()
	GUISetState(@SW_HIDE)
	CefWndMsg_QuitLoop()
	exit
endfunc

func __sizing($h, $m, $w, $l)
	#forceref $h, $m, $w, $l
	if ($toolbar_hwnd and $browser_hwnd) then
		dllcall('user32', 'bool', 'GetClientRect', 'hwnd', $hMainGUI, 'struct*', $rcGUI)
		_MoveWindow($toolbar_hwnd, 0, 0, $rcGUI.w, $toolbar_height, 1)
		_MoveWindow($browser_hwnd, 0, $toolbar_height, $rcGUI.w, $rcGUI.h - $toolbar_height, 1)
	endif
endfunc

; toolbar =========================

func toolbar_getLifeSpanHandler()
	return $toolbar_lifespan.__ptr
endfunc

func toolbar_onAfterCreated($browser)
	if ($toolbar_hwnd==0) then
		$toolbar_frame = $browser.GetMainFrame()
		$toolbar_hwnd = ptr($browser.GetHost().GetWindowHandle())
		
		_MoveWindow($toolbar_hwnd, 0, 0, $width, $toolbar_height, 1)
		_ShowWindow($toolbar_hwnd)

		$cef.CreateBrowser($cef_winfo.__ptr, $browser_client.__ptr, $url, $cef_bs.__ptr, null)
	endif
endfunc

; browser =========================

func browser_getLifeSpanHandler()
	return $browser_lifespan.__ptr
endfunc

func browser_getDisplayHandler()
	return $browser_display.__ptr
endfunc

func browser_onAfterCreated($browser)
	if ($browser_hwnd==0) then
		$main_browser = $browser
		$main_frame = $browser.GetMainFrame()
		$browser_hwnd = ptr($browser.GetHost().GetWindowHandle())

		_MoveWindow($browser_hwnd, 0, 30, $width, $height - 30, 1)
		_ShowWindow($browser_hwnd)

		GUISetState(@SW_SHOW)
	endif
endfunc

func browser_onTitleChange($browser, $title)
	#forceref $browser
	if ($browser_hwnd) then WinSetTitle($hMainGUI, '', $gui_title & ' :: ' & $title.val)
endfunc

func browser_onAddressChange($browser, $frame, $url)
	#forceref $browser, $frame
	if ($toolbar_frame <> 0) then
		local $code = 'setLink("' & $url.val & '");'
		$toolbar_frame.ExecuteJS($code)
	endif
endfunc

func browser_onFaviconUrlChange($browser, $icon_urls)
	#forceref $browser
	if ($toolbar_frame <> 0) then
		local $code = 'setIcon("' & $icon_urls.read() & '");'
		$toolbar_frame.ExecuteJS($code)
	endif
endfunc

; app/v8 =========================

func app_getRenderProcessHandler()
	return $app_renderprocess.__ptr
endfunc

func app_onWebKitInitialized()
	local $code = fileread($html_dir & '\ext.js')
	CefRegisterExtension('v8/app', $code, $app_v8.__ptr)


	Local $handle = DllCall('kernel32.dll', 'handle', 'OpenProcess', 'dword', 0x1F0FFF, 'bool', 0, 'dword', @autoitpid)
	If Not @error Then
		$handle = $handle[0]
		DllCall('kernel32.dll', 'bool', 'SetProcessWorkingSetSizeEx', 'handle', $handle, 'int', -1, 'int', -1, 'dword', 0x1)
		DllCall('psapi.dll', 'bool', 'EmptyWorkingSet', 'handle', $handle)
		DllCall('kernel32.dll', 'bool', 'CloseHandle', 'handle', $handle)
	EndIf

endfunc

;              fn name |  this  | a[n] | <ret>  |   err     // a[0] = count; a[N] = param N (count > 0)
func app_execute($name, $object, $args, $retval, $exception)
	#forceref $name, $object, $args, $retval, $exception

	if ($main_browser == 0 and $main_frame == 0) then return 0;

	switch ($name.val)
		case 'back'
			$main_browser.GoBack()
			
		case 'forward'
			$main_browser.GoForward()

		case 'reload'
			$main_browser.Reload()

		case 'home'
			$main_frame.LoadURL($url)

		case 'about'
			MsgBox(0x40, 'About', 'Mini Browser v0.1 - Cefau3 example.' & @cr & _
				'CEF: ' & $cef.Version & @cr & _
				'Chromium: ' & $cef.ChromiumVersion & @cr & _
				@cr & @tab & @tab & '@by wuuyi123.' _
			)

		case 'load'
			if ($args[0] > 0) then ; check
				local $new_url = $args[1].GetStringValue()
				$main_frame.LoadURL($new_url)
			endif
	endswitch

	return 0 ; 1 for change retval
endfunc