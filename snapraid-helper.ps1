###############################
# Snapraid Sync Helper Script #
###############################
# this is a helper script that keeps snapraid parity info in sync with
# your data. Here's how it works:
#   1) it first calls diff to figure out if the parity info is out of sync
#   2) if there are changed files (i.e. new, changed, moved or removed),
#         it then checks how many files were removed.
#   3) if the deleted files exceed X (configurable), it triggers an
#         alert email and stops. (in case of accidental deletions)
#   4) otherwise, it will call sync.
#   5) when sync finishes, it sends an email with the output to user.
#
# $Author: therealjmc
# $Version: 2.5.2 (2014/04/06)
#
# Originally inspired by bash script written by sidney for linux/bash
# Based on the powershell script written by lrissman at gmail dot com
#
#######################################################################
###################### CHANGELOG ######################################
#######################################################################
#
# Version 2.5.2 (2014/04/06)
# Looks like a small encoding bug in the script. Should fix "A positional parameter cannot be found that accepts argument[...]" error
#
# Version 2.5.1 (2014/04/06)
# Added some more Debug Output to find a user reported Error
#
# Version 2.5 (2014/04/05)
# Added EnableDebugOutput Variable, if set to 1 all variables will be printed before snapraid starts
#
# Version 2.4 (2014/04/05)
# Fixed a wrong info about the location of the output files in the ini file
#
# Version 2.3 (2014/04/03)
# Added syncandfix option
#
# Version 2.2 (2014/03/24)
# Fixed a small cosmetic bug regarding Eventlog on the first script run
#
# Version 2.1 (2014/03/14)
# Added SnapRAIDConfig to ini file and included it as passing arguments to snapraid (fixes bug from Task sheduler when working directory was not set to snapraid dir)
#
# Version 2.0 (2014/03/13)
# Release on codeplex
# Fix a little bug in the condition for running pre-process only if needed when SkipParityFilesAtStart=1
#
#######################################################################
###################### END CHANGELOG ##################################
#######################################################################
#
# Modification by therealjmc:
# - Various fixes (for example the LastExiStCode and various "=" instead of -eq)
# - Added parameter to script to pass other commands (for example scrub)
# - Added Eventlog logging
# - Added output as attachment (including zip if above certain size)
# - Max Attachment Size is configurable
# - Added check to prevent double execution of script and/or snapraid
# - Making Logfile rotation a config variable (How many zip files should be stored)
# - Fixed messed up Umlauts with .Net File reading method
# - Added possibility to send emails without auth
# - Filename for ini now has to be the same as the script (without the .ps1 of course) (instead of fixed name)
# - Fixed the Services Section (was Process in .ini instead of Service) - UNTESTED!
# - Fixed the counting for the diff (especially with Snapraid 5.X+ since update and resize are different now)
# - Fixed double printing of snapraid diff output in email
# - Include the extended SnapRAID Log (5.X+ prints detailed error infos there) in the email if there is an snapraid error
# - Added Pre/Post Process (Pre will be called before the parity file test and Post will be called before E-Mail will be sent)
# - Added SkipParityFilesAtStart - if set to 1 parity file checking will be skipped unless diff finds a diference and runs Pre Process only if needed
# - Post Process/Service start will only run if Pre Process/Service stop has run
# - If argument passed is "syncandcheck" (without the "") there will be a sync (if needed) before a check is called
# - If argument passed is "syncandscrub" (without the "") there will be a sync (if needed) before a scrub is called (scrub without any parameters, snapraid default)
# - If argument passed is "syncandfullscrub" (without the "") there will be a sync (if needed) before a full scrub is called (-p 100 -o 0 as parameters)
# - If argument passed is "syncandfix" (without the "") there will be a sync (if needed) before a fix option (without any parameters) is done. Usefull for fixable errors in parity i.e.
#
# NOTE TO USERS WITH SPECIAL CHARACTERS IN FILE/FOLDER NAMES:
# I had a problem with German Umlauts not beeing displayed correct. Enable UTF8Console in the .ini
# You HAVE to Change the Powershell Console Font to something like Lucida Console
# Note: Windows has a bug saving Lucida with Fontsize 12 as default. Select 10 or 14 - this works
# 
#######################################################################
#Enable to pass the check/scrub command to SnapRAID as a parameter for the Powershellscript
#Has to be the first non-comment and non-blank line, otherwise param won't work.
Param([string]$Argument1='sync')
$Argument1 = $Argument1.ToLower()

<#

Note:  To run a powershell script you must perform the following:
Only Once:
1) Download the PowerShellExecutionPolicy.adm from http://go.microsoft.com/fwlink/?LinkId=131786.
2) Install it
3) open gpedit.msc
4) Under computer configuration, right-click Administrative Templates and then click Add/Remove Templates
5) Add PowerShellExecutionPolicy.adm from %programfiles%\Microsoft Group policy
6) Open Administrative Templates\Classic Administrative Templates\Windows Components\Windows PowerShell
7) Enable the property and allow unsigned scripts to be run

each time:
1) open the power shell prompt
2) from the directory of video files, run the script
#>

##########################################
############# NOTES ######################
##########################################
<#   
- This script depends upon the powershell community extensions from http://pscx.codeplex.com/
- Or direct sownload: http://pscx.codeplex.com/downloads/get/523236
- Snapraid's output is unix formatted (CRLF vs CR) so -delim "`0" is required to have each line on newline when using Get-Content
- Service Start and Stop requires the script to run with Elevated Rights
- snapraid-helper.ini file is required in the same dir as the .ps1
#>
##########################################
############# END NOTES ##################
##########################################

##########################################
########## INCLUSDES #####################
##########################################
$env:PSModulePath=$env:PSModulePath+";C:\Program Files (x86)\PowerShell Community Extensions\Pscx3"
##########################################
########## END INCLUSDES #################
##########################################

$Scriptname			= $MyInvocation.MyCommand.Name
#$Scriptrunning		= get-wmiobject win32_process -filter "name='powershell.exe'AND CommandLine LIKE '%$Scriptname%'"
$Scriptrunning		= get-wmiobject win32_process -filter "name='powershell.exe'AND CommandLine LIKE '%$Scriptname%' AND NOT Handle LIKE '$PID'"
$Snapraidrunning	= get-wmiobject win32_process -filter "name='snapraid.exe'"


##############################################
############# VARIABLES ######################
##############################################

$global:PreProcessHasRun = 0
$global:ServicesStarted = 0
$global:ServicesStopped = 0
$global:Diffchanges = 99
$SomethingDone = 0
$HomePath = $MyInvocation.Line | Split-Path
$message = ""
$ConfigError = 0

##############################################
############# END VARIABLES ##################
##############################################



##############################################
############# FUNCTIONS ######################
##############################################

function Test-IsAdmin {     #Borrowed from with some modifications: http://stackoverflow.com/questions/9999963/powershell-test-admin-rights-within-powershell-script
	try {
		$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
		$principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
		return $principal.IsInRole( [Security.Principal.WindowsBuiltInRole]::Administrator )
	} catch {
		#throw "Failed to determine if the current user has elevated privileges. The error was: '{0}'." -f $_
		return 0
	}
	return 1
}

Function Start-Pre-Process {
	# If Process Management is enabled, then start Pre Process
	if ($config["ProcessEnable"] -eq 1) {
		# timestamp the job
		$CurrentDate = Get-Date
		$message = "Starting Pre-Process $CurrentDate"
		WriteLogFile $message
		$exe = $config["ProcessPre"]
		& "$exe" | Out-Null
		if (!($LastExitCode -eq "0")) {
			$CurrentDate = Get-Date
			$message = "ERROR: Pre-Process failed on $CurrentDate with exit code $LastExitCode"
			WriteLogFile $message
			Start-Post-Process
			$subject = $config["SubjectPrefix"]+" "+$message
			Send-Email $subject "error" $EmailBody
			Stop-Transcript | out-null
			exit 1
		}
		else {
			$CurrentDate = Get-Date
			$message = "Done Starting Pre-Process $CurrentDate"
			WriteLogFile $message
			$global:PreProcessHasRun = 1
		}
	}
}

Function Start-Post-Process {
	# If Process Management is enabled, then start Post Process
	if ($config["ProcessEnable"] -eq 1) {
		if ($global:PreProcessHasRun -eq 1) {
			# timestamp the job
			$CurrentDate = Get-Date
			$message = "Starting Post-Process $CurrentDate"
			WriteLogFile $message
			$exe = $config["ProcessPost"]
			& "$exe" | Out-Null
			if (!($LastExitCode -eq "0")) {
				$CurrentDate = Get-Date
				$message = "ERROR: Post-Process failed on $CurrentDate with exit code $LastExitCode"
				WriteLogFile $message
				$subject = $config["SubjectPrefix"]+" "+$message
				Send-Email $subject "error" $EmailBody
				Stop-Transcript | out-null
				exit 1
			}
			else {
				$CurrentDate = Get-Date
				$message = "Done Starting Post-Process $CurrentDate"
				WriteLogFile $message
			}
		}
	}
}

# Build Email Function (used many times in script)
Function Send-Email ($fSubject,$fSuccess,$EmailBody){
	#$fSubject -- passed subject line
	#$fSuccess -- "success" = success email, "error" = error email, "error2" = error email script/snapraid running
	$Body = ""
	
	if ($fSuccess -ne "error2") {
		if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			If (Test-Path $EmailBodyTmp) {
				Rename-Item "$EmailBodyTmp" "$EmailBodyTxt"
			}
		
			if (Test-Path "$EmailBodyTxt") { 
				$file = Get-Item "$EmailBodyTxt"
				if ($file.length -ge $config["LogFileMaxSizeZIP"]) {
					Write-zip -Path "$EmailBodyTxt" -OutputPath "$EmailBodyZip"  -level 9 -Quiet
				}
				else {
					$EmailBodyZip = $EmailBodyTxt
				}
			}
		}
	}
	
	if (($fSuccess -eq "success") -and ($config["EmailOnSuccess"] -eq 1) -and ($config["EmailEnable"] -eq 1)) {
		if ($config["IncludeExtendedInfo"] -eq 1 ){
			$Body = (Get-Content $EmailBody | Out-string)
		}
		if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			If (Test-Path $EmailBodyZip) {
				If ((Get-Item $EmailBodyZip).length -le $config["MaxAttachSize"]){
					If (Test-Path $EmailBodyZip) {
						$att = new-object Net.Mail.Attachment($EmailBodyZip)
						$MailMessage.Attachments.Add($att)
					}
				}
				else {
					Add-Content $EmailBody "LOG FILE TOO LARGE TO ATTACH"
				}
			}
			$Body = (Get-Content $EmailBody | Out-string)
		}
		$MailMessage.Subject = $fSubject
		$Mailmessage.Body 	= $Body
		$smtpclient.Send($MailMessage)
		if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			If (Test-Path $EmailBodyZip) {
				$att.Dispose()
			}
		}
		$EventlogID = 4711
	}
	if (($fSuccess -eq "error") -and ($config["EmailOnError"] -eq 1) -and ($config["EmailEnable"] -eq 1)) {
		if ($config["IncludeExtendedInfo"] -eq 1 ){
			$Body = (Get-Content $EmailBody | Out-string)
		}
		if ($config["IncludeExtendedInfoZip"] -eq 1){
			If (Test-Path $EmailBodyZip) {
				If ((Get-Item $EmailBodyZip).length -le $config["MaxAttachSize"]){
					If (Test-Path $EmailBodyZip) {
						$att = new-object Net.Mail.Attachment($EmailBodyZip)
						$MailMessage.Attachments.Add($att)
					}
				}
				else {
					Add-Content $EmailBody "LOG FILE TOO LARGE TO ATTACH"
				}
			}
			$Body = (Get-Content $EmailBody | Out-string)
		}
		$MailMessage.Subject = $fSubject
		$Mailmessage.Body 	= $Body
		$smtpclient.Send($MailMessage)
		if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			If (Test-Path $EmailBodyZip) {
				$att.Dispose()
			}
		}
		$EventlogID = 4712
	}
	if (($fSuccess -eq "error2") -and ($config["EmailOnError"] -eq 1) -and ($config["EmailEnable"] -eq 1)) {
		$MailMessage.Subject = $fSubject
		$Mailmessage.Body 	= $fSubject
		$smtpclient.Send($MailMessage)
		$EventlogID = 4712
	}
	
	if (!(Get-Eventlog -Source SnapRaid-Helper -LogName Application -ErrorAction SilentlyContinue)){
		New-EventLog -Source SnapRaid-Helper -LogName Application
	}
	write-eventlog -logname Application -source SnapRaid-Helper -eventID $EventlogID -message $fSubject
}

Function Check-Content-Files {
	foreach ($element in $config["SnapRAIDContentFiles"]) {
		if (!(Test-Path $element)){
			$message = "ERROR: Content file ($element) not found!"
			Write-Host $message -ForegroundColor red -backgroundcolor yellow
			Add-Content $EmailBody $message
			Start-Post-Process
			$subject = $config["SubjectPrefix"]+" "+$message
			Send-Email $subject "error" $EmailBody
			Stop-Transcript | out-null
			exit 1
		}
	}
}

Function Check-Parity-Files {
	foreach ($element in $config["SnapRAIDParityFiles"]) {
		if (!(Test-Path $element)){
			$message = "ERROR: Parity file ($element) not found!"
			Write-Host $message -ForegroundColor red -backgroundcolor yellow
			Add-Content $EmailBody $message
			Start-Post-Process
			$subject = $config["SubjectPrefix"]+" "+$message
			Send-Email $subject "error" $EmailBody
			Stop-Transcript | out-null
			exit 1
		}
	}
}

Function WriteLogFile ($ftext){
	Write-Host "----------------------------------------"
	Write-Host $ftext
	Write-Host "----------------------------------------"
	Add-Content $EmailBody "----------------------------------------"
	Add-Content $EmailBody $ftext
	Add-Content $EmailBody "----------------------------------------"
}

Function WriteExtendedLogFile ($ftext){
	Write-Host "----------------------------------------"
	Write-Host $ftext
	Write-Host "----------------------------------------"
	Add-Content $EmailBody "----------------------------------------"
	Add-Content $EmailBody $ftext
	Add-Content $EmailBody "----------------------------------------"
	if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			Add-Content $EmailBodyTmp "----------------------------------------"
			Add-Content $EmailBodyTmp $ftext
			Add-Content $EmailBodyTmp "----------------------------------------"
	}
}

Function ServiceManagement ($startstop){
	if ($startstop -eq "stop") {
		# If Service Management is enabled, then take services offline
		if ($config["ServiceEnable"] -eq 1 -and $global:ServicesStopped -ne 1) {
			# timestamp the job
			$CurrentDate = Get-Date
			$message = "Stopping Services $CurrentDate"
			WriteLogFile $message
			foreach ($service in $ServiceList) {
				$message = Stop-Service $service
				WriteLogFile $message
			}
			# timestamp the job
			$CurrentDate = Get-Date
			$message = "Done Stopping Services $CurrentDate"
			WriteLogFile $message
			$global:ServicesStopped = 1
		}
	}
	if ($startstop -eq "start") {
		# If Service Management is enabled, then bring services back online
		if ($config["ServiceEnable"] -eq 1 -and $global:ServicesStarted -ne 1 -and $global:ServicesStopped -eq 1) {
			# timestamp the job
			$CurrentDate = Get-Date
			$message = "Starting Services $CurrentDate"
			WriteLogFile $message
			foreach ($service in $ServiceList) {
				$message = Start-Service $service
				WriteLogFile $message
			}
			# timestamp the job
			$CurrentDate = Get-Date
			$message = "Done Starting Services $CurrentDate"
			WriteLogFile $message
			$global:ServicesStarted = 1
		}
	}
}

Function RunSnapraid ($sargument){
	$exe = $config["SnapRAIDPath"] + $config["SnapRAIDExe"]
	$configfile = $config["SnapRAIDPath"] + $config["SnapRAIDConfig"]
	if ($sargument -ne "fullscrub") {
		& "$exe" -c $configfile $sargument -l $SnapRAIDLogfile 2>&1 3>&1 4>&1 | %{ "$_" } | tee-object -file $TmpOutput -append
	}
	else {
		$sargument = "scrub"
		& "$exe" -c $configfile $sargument -p 100 -o 0 -l $SnapRAIDLogfile 2>&1 3>&1 4>&1 | %{ "$_" } | tee-object -file $TmpOutput -append
	}
	#$TmpOutputInRAM = Get-Content $TmpOutput  -readcount 100 -delim "`0" 
	# NOTE the above Get-Content command is VERY VERY VERY VERY slow, so I am using the .Net function below to get the output of the Snapraid command into a variable
	# NOTE the .Net function breaks german Umlauts so I'm using this fast way with get-content and out-string - no real time difference to .Net function
	$TmpOutputInRAM = (Get-Content $TmpOutput | Out-string)
	if ($config["IncludeExtendedInfoZip"] -eq 1 ){
		$FileToAdd = $EmailBodyTmp
	}
	else {
		$FileToAdd = $EmailBody
	}
	foreach ($line in $TmpOutputInRAM){
		Add-Content $FileToAdd $line
		# since output is done with tee it isn't necessary to use write-host again
		# Write-Host $line
	}
	if (!($LastExitCode -eq "0")) {
		# If enabled bring services back online
		ServiceManagement "start"
		$CurrentDate = Get-Date
		$message = "ERROR: SnapRAID $sargument Job FAILED on $CurrentDate with exit code $LastExitCode"
		WriteExtendedLogFile $message
		$message2 = "Including detailed SnapRAID Log"
		WriteExtendedLogFile $message2
		$SnapRAIDLogfileInRAM = (Get-Content $SnapRAIDLogfile | Out-string)
		if ($config["IncludeExtendedInfoZip"] -eq 1 ){
			$FileToAdd = $EmailBodyTmp
		}
		else {
			$FileToAdd = $EmailBody
		}
		foreach ($line in $SnapRAIDLogfileInRAM){
			Add-Content $FileToAdd $line
			Write-Host $line
		}
		Start-Post-Process
		$subject = $config["SubjectPrefix"]+" "+$message
		Send-Email $subject "error" $EmailBody
		Stop-Transcript | out-null
		exit 1
	}
	# Job was successful, move onto processing.
	$CurrentDate = Get-Date
	$message = "SnapRAID $sargument Job finished on $CurrentDate"
	WriteExtendedLogFile $message
	If ($sargument -eq "diff") {
		DiffAnalyze
	}
}

Function DiffAnalyze {
	If ($global:Diffchanges -eq 99) {
		$DEL_COUNT = Select-String $TMPOUTPUT -Pattern "^remove" | Measure-Object -Line
		$ADD_COUNT = Select-String $TMPOUTPUT  -Pattern "^add" | Measure-Object -Line
		$MOVE_COUNT = Select-String $TMPOUTPUT  -Pattern "^move" | Measure-Object -Line
		$RESIZE_COUNT = Select-String $TMPOUTPUT  -Pattern "^resize" | Measure-Object -Line
		$UPDATE_COUNT = Select-String $TMPOUTPUT  -Pattern "^update" | Measure-Object -Line
		
		$DEL_COUNT = $DEL_COUNT.Lines 
		$ADD_COUNT = $ADD_COUNT.Lines 
		$MOVE_COUNT = $MOVE_COUNT.Lines 
		$UPDATE_COUNT = $UPDATE_COUNT.Lines + $RESIZE_COUNT.Lines
		
		$message = "SUMMARY of changes - Added [$ADD_COUNT] - Deleted [$DEL_COUNT] - Moved [$MOVE_COUNT] - Updated [$UPDATE_COUNT]"
		WriteExtendedLogFile $message
		
		# check if files have changed
		if ( $DEL_COUNT -gt 0 -or $ADD_COUNT -gt 0 -or $MOVE_COUNT -gt 0 -or $UPDATE_COUNT -gt 0 ) {
			# YES, check if number of deleted files exceed DEL_THRESHOLD
			if ( $DEL_COUNT -gt $config["SnapRAIDDelThreshold"] ) {
				# YES, lets inform user and not proceed with the job just in case
				$message = "WARNING: Number of deleted files ($DEL_COUNT) exceeded threshold (" + $config["SnapRAIDDelThreshold"] + "). NOT proceeding with job. Please run manually if this is not an error condition."
				Write-Host $message
				Add-Content $EmailBody $message
				Start-Post-Process
				$subject = $config["SubjectPrefix"]+" "+$message
				Send-Email $subject "error" $EmailBody
				Stop-Transcript | out-null
				exit 1
			}
			else {
				# NO, delete threshold not reached, lets run the job
				$message = "Deleted files ($DEL_COUNT) did not exceed threshold (" + $config["SnapRAIDDelThreshold"] + "), proceeding with job."
				Write-Host $message
				Add-Content $EmailBody $message
				$CurrentDate = Get-Date
				$message = "$CurrentDate Changes detected [A-$ADD_COUNT,D-$DEL_COUNT,M-$MOVE_COUNT,U-$UPDATE_COUNT] and deleted files ($DEL_COUNT) is below threshold (" + $config["SnapRAIDDelThreshold"] + "). Running Command."
				Write-Host $message
				Add-Content $EmailBody $message
				$global:Diffchanges = 1
			}
		}
		else {
			# NO, so lets log it and exit
			$CurrentDate = Get-Date
			$message = "$CurrentDate No change detected. Nothing to do"
			WriteExtendedLogFile $message
			$global:Diffchanges = 0
		}
	}
}

##############################################
############### END FUNCTIONS ################
##############################################

##############################################
###### Configuration Verification Start ######
##############################################
# Get variables from <scriptname>.ini
$Scriptname2=[System.IO.Path]::GetFileNameWithoutExtension("$Scriptname")
$ConfigFile="$HomePath\$Scriptname2.ini"
$config = @{}

Get-Content $ConfigFile | foreach {
	if (($_.StartsWith(";")) -or (!($_))) {
		#Non-variable or is Space
	#    write-host "Non-Variable: $_"
	}
	else {
		$line = $_.Split("=")
		#$config.($line[0]) = $line[1]
		$config[$line[0]] = $line[1].TrimEnd()
	#   write-host Variable: $line[0]  Content: $line[1]
	}
}
##### Validate configuration variables are sane

#SnapRAID and LogFile Config
$SnapRAIDConfigs = "SnapRAIDDelThreshold","SnapRAIDPath","SnapRAIDExe","SnapRAIDContentFiles","SnapRAIDParityFiles","TmpOutputFile","LogFileName","LogFileMaxSize","LogFileZipCount","UTF8Console"
foreach ($element in $SnapRAIDConfigs){
	if (!($config[$element]) -or ($config[$element] -eq "")) {
		write-host "$element is null, please add a value"
		$ConfigError ++
	}
}

if ($config["UTF8Console"] -eq 1){
	chcp 65001
}

#Validate EmailBodyPath and if not specified, use ScriptPath
if (!($config["LogPath"]) -or ($config["LogPath"] -eq "") ) { 
	$config["LogPath"] = "$HomePath\" 
}

if ( !(Test-Path $config["LogPath"] -pathType container) ) {
	Write-host "ERROR: LogPath: "$config["LogPath"]"  - Path Does not exist.  Please fix $ConfigFile or create the path"
	exit 1
}
else {
	$LogPathTest = $config["LogPath"].EndsWith("\")
	If (!($LogPathTest)) {
		$config["LogPath"] = $config["LogPath"] += "\"
	}
}

$LogFile=$config["LogPath"] + $config["LogFileName"]

#Email Configs
$EmailConfigs = "SubjectPrefix","EmailTo","EmailFrom","Body","SMTPHost","SMTPSSLEnable","SMTPAuthEnable","EmailBodyFile","EmailBodyFileZip","EmailEnable","SMTPPort","EmailOnSuccess","EmailOnError","IncludeExtendedInfo","IncludeExtendedInfoZip","LogFileMaxSizeZIP","MaxAttachSize"
#If email is enabled, validate email configs are not null
if ($config["EmailEnable"] -eq 1){
	foreach ($element in $EmailConfigs){
		if (!($config[$element]) -or ($config[$element] -eq "")) {
			write-host "$element is null, please add a value"
			$ConfigError ++
		}
		
	}
	if ($config["IncludeExtendedInfoZip"] -eq 1){
		$config["IncludeExtendedInfo"] = 0
	}
}

#Service/Process Configs
if ($config["ServiceEnable"] -eq 1){ 
	if (!(Test-IsAdmin)) {
		Write-Host "You need to run the script with elevated rights to start and stop services. Either run with Elevated Rights or change in $ConfigFile ProcessEnable=0"
		exit 1
	}
	$ServiceConfigs = "ServiceName"
	#If service handling is enabled, validate configs are not null
	
	foreach ($element in $ServiceConfigs){
		if (!($config[$element]) -or ($config[$element] -eq "")) {
			write-host "$element is null, please add a value"
			$ConfigError ++
		}
	}
	$ServiceNum = 0
	$ServiceList = $config["ServiceName"].Split(",").Replace('"',"")
	foreach ($Service in $ServiceList) {
		$ServiceNum ++
		if (!(Get-Service $Service -ErrorAction SilentlyContinue))
		{
			"The Service $Service does not exist.   Please remove or correct in ProcessName in $ConfigFile"
		}
	}
}

if ($config["ProcessEnable"] -eq 1){ 
	#If process handling is enabled, validate configs are not null
	
	$ProcessConfigs = "ProcessPre","ProcessPost"
	
	foreach ($element in $ProcessConfigs){
		if (!($config[$element]) -or ($config[$element] -eq "")) {
			write-host "$element is null, please add a value"
			$ConfigError ++
		}
		if (!(Test-Path $config[$element])){
			wite-host "$config[$element] is not a valid path to execute!"
			$ConfigError ++
		}
	}
}

#EventLog Configs
$EventLogConfigs = "EventLogSources","EventLogEntryType","EventLogDays","EventLogHaltOnDiskError"
if ($config["EventLogEnable"] -eq 1){
	foreach ($element in $EventLogConfigs){
		if (!($config[$element]) -or ($config[$element] -eq "")) {
			write-host "$element is null, please add a value"
			$ConfigError ++
		}
	}
	$EventLogEntryTypeList = $config["EventLogEntryType"].Replace('"',"").Trim().Split(",")
	$EventLogSourcesList = $config["EventLogSources"].Replace('"',"").Trim().Split(",")
}


#Report if there are errors and exit
if ($ConfigError -ge 1) {
	write-host "Number of config errors: $ConfigError"
	write-host "Please correct $ConfigFile and run again"
	exit 1
}

#Validate EmailBodyPath and if not specified, use Windows Temp path
if (!($config["EmailBodyPath"]) -or ($config["EmailBodyPath"] -eq "") ) { 
	$config["EmailBodyPath"] = "$env:temp\" 
}

if ( !(Test-Path $config["EmailBodyPath"] -pathType container) ) {
	Write-host "ERROR: EmailBodyPath: "$config["EmailBodyPath"]"  - Path Does not exist.  Please fix $ConfigFile or create the path"
	exit 1
}


#Validate TmpOutputPath and if not specified, use Windows Temp path
if (!($config["TmpOutputPath"]) -or ($config["TmpOutputPath"] -eq "")){ 
	$config["TmpOutputPath"] = "$env:temp\" 
}

if ( !(Test-Path $config["TmpOutputPath"] -pathType container) ) {
	Write-host "ERROR: TmpOutputPath:" $config["TmpOutputPath"]"  - Path Does not exist.  Please fix $ConfigFile or create the path"
	exit 1
}

##############################################
###### Configuration Verification End ########
##############################################

#Initalize Email
if ($config["EmailEnable"] -eq 1) {
	$SMTPClient = New-Object Net.Mail.SmtpClient
	$MailMessage= New-Object Net.Mail.Mailmessage
	$MailMessage.IsBodyHtml = $false
	$SMTPClient.Host = $config["SMTPHost"]
	$SMTPClient.Port = $config["SMTPPort"]
	$MailMessage.From = $config["EmailFrom"]
	$MailMessage.To.add($config["EmailTo"])
	if ($config["SMTPSSLEnable"] -eq 1) {
		$SMTPClient.EnableSsl = $true
	}
	else {
		$SMTPClient.EnableSsl = $false
	}
	if ($config["SMTPAuthEnable"] -eq 1) {
		$SMTPClient.Credentials = new-Object System.Net.NetworkCredential($config["SMTPUID"],$config["SMTPPass"]); 
	}
}
$TmpOutput=$config["TmpOutputPath"] + $config["TmpOutputfile"]
$EmailBody=$config["EmailBodyPath"] + $config["EmailBodyfile"]
$EmailBodyTmp=$config["EmailBodyPath"] + $config["EmailBodyFileZip"] + ".out"
$EmailBodyTxt=$config["EmailBodyPath"] + $config["EmailBodyFileZip"] + ".txt"
$EmailBodyZip=$config["EmailBodyPath"] + $config["EmailBodyFileZip"] + ".zip"
$SnapRAIDLogfile=$config["TmpOutputPath"] + "snapRAIDerror.out"

#Ensure only one Snapraid process and only one instance of this script is running
#Note that the detection for running script only works if it is called with the script as a parameter
#for example powershell.exe snapraid-helper.ps1 - but not if the script is called like .\snapraid-helper.ps1
If ($Scriptrunning -match "Handle"){
	$CurrentDate = Get-Date
	$message = "ERROR: Another instance of the script is still running! $Argument1 can't run on $CurrentDate"
	Write-Host "----------------------------------------"
	Write-Host $message
	Write-Host "----------------------------------------"
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "error2"
	exit 1
}
If ($Snapraidrunning -match "Handle"){
	$CurrentDate = Get-Date
	$message = "ERROR: Another instance of snapraid is still running! $Argument1 can't run on $CurrentDate"
	Write-Host "----------------------------------------"
	Write-Host $message
	Write-Host "----------------------------------------"
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "error2"
	exit 1
}

#Start with some cleanup
if (Test-Path $TmpOutput){
	Remove-Item $TmpOutput
}
if (Test-Path $EmailBody){
	Remove-Item $EmailBody
}
if (Test-Path $EmailBodyTmp){
	Remove-Item $EmailBodyTmp
}
if (Test-Path $EmailBodyTxt){
	Remove-Item $EmailBodyTxt
}
if (Test-Path $EmailBodyZip){
	Remove-Item $EmailBodyZip
}
if (Test-Path $SnapRAIDLogfile){
	Remove-Item $SnapRAIDLogfile
}

if ($config["EnableDebugOutput"] -eq 1) {
	foreach ($element in $Config){
		echo $element
		echo "TmpOutput = $TmpOutput"
		echo "EmailBody = $EmailBody"
		echo "EmailBodyTmp = $EmailBodyTmp"
		echo "EmailBodyTxt = $EmailBodyTxt"
		echo "EmailBodyZip = $EmailBodyZip"
		echo "SnapRAIDLogfile = $SnapRAIDLogfile"
	}
}

#Log Management Section
if (Test-Path "$LogFile") { 
	$file = Get-Item "$LogFile"
	If ($file.length -ge $config["LogFileMaxSize"]){
		if ($config["LogFileZipCount"] -ge 1) {
			$i = $config["LogFileZipCount"]
			while ($i -gt 1) {
				$j = $i - 1
				if (Test-Path "$LogFile.$j.zip") {
					Rename-Item "$LogFile.$j.zip" "$LogFile.$i.zip"
				}
				$i = $i-1
			}
			Write-zip "$LogFile" -level 9
			Rename-Item "$LogFile.zip" "$LogFile.1.zip"
		}
		Remove-Item "$LogFile"
		New-Item "$LogFile" -type file
	}
}

# Start Transcript logging
# redirect all stdout to log file (leave stderr alone thou)
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path $LogFile -append

#Check Eventlog for Errors
$CurrentDate = Get-Date
$message = "Checking for Disk issues in Eventlog at $CurrentDate"
WriteLogFile $message

$EventLogOutput = get-eventlog -logname system -entrytype $EventLogEntryTypeList -Source $EventLogSourcesList -After (Get-Date).AddDays($config["EventLogdays"])
Write-Host "TimeGenerated,EntryType,Source,Message"
foreach ($event in $EventLogOutput) {
	$EventLogCount = $EventLogcount + 1
	$TimeGenerated = $event.TimeGenerated
	$EntryType = $event.EntryType
	$Source = $event.Source
	$EventMessage = $event.Message
	
	Write-Host "$TimeGenerated,$EntryType,$Source,$EventMessage"  
	Add-Content $EmailBody "$TimeGenerated,$EntryType,$Source,$EventMessage"  
}

if (($EventLogCount -ge 1) -and ($config["EventLogHaltOnDiskError"] -eq 1)) {
	$message = "WARN: Found disk Errors/Warnings in EventLogs.  Aborting sync based on HaltOnDiskError"
	Write-Host $message -ForegroundColor red -backgroundcolor yellow
	Add-Content $EmailBody $message
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "error" $EmailBody
	Stop-Transcript | out-null
	exit 1
}

#sanity check first to make sure we can access the content and parity files
$config["SnapRAIDContentFiles"] = $config["SnapRAIDContentFiles"].split(",")
$config["SnapRAIDParityFiles"] = $config["SnapRAIDParityFiles"].split(",")

Check-Content-Files

if (!($config["SkipParityFilesAtStart"]) -or ($config["SkipParityFilesAtStart"] -ne 1) ) { 
	Start-Pre-Process
	Check-Parity-Files
}

# timestamp the job
$CurrentDate = Get-Date
$message = "SnapRAID $argument1 Job started on $CurrentDate"
WriteExtendedLogFile $message

If ($Argument1 -eq "syncandcheck" -and $SomethingDone -ne 1) {
	$argument = "diff"
	RunSnapraid $argument
	If ($global:Diffchanges -eq 1){
		if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
			Start-Pre-Process
			Check-Parity-Files
		}
		# If enabled take services offline
		ServiceManagement "stop"
		$argument = "sync"
		RunSnapraid $argument
	}
	if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
		Start-Pre-Process
		Check-Parity-Files
	}
	# If enabled take services offline
	ServiceManagement "stop"
	$argument = "check"
	RunSnapraid $argument
	# If enabled bring services back online
	ServiceManagement "start"
	$CurrentDate = Get-Date
	$message = "SUCCESS: SnapRAID SYNC and CHECK Job finished on $CurrentDate"
	WriteExtendedLogFile $message
	Start-Post-Process
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "success" $EmailBody
	$SomethingDone = 1
}
ElseIf ($Argument1 -eq "syncandscrub" -and $SomethingDone -ne 1) {
	$argument = "diff"
	RunSnapraid $argument
	If ($global:Diffchanges -eq 1){
		if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
			Start-Pre-Process
			Check-Parity-Files
		}
		# If enabled take services offline
		ServiceManagement "stop"
		$argument = "sync"
		RunSnapraid $argument
	}
	if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
		Start-Pre-Process
		Check-Parity-Files
	}
	# If enabled take services offline
	ServiceManagement "stop"
	$argument = "scrub"
	RunSnapraid $argument
	# If enabled bring services back online
	ServiceManagement "start"
	$CurrentDate = Get-Date
	$message = "SUCCESS: SnapRAID SYNC and SCRUB Job finished on $CurrentDate"
	WriteExtendedLogFile $message
	Start-Post-Process
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "success" $EmailBody
	$SomethingDone = 1
}
ElseIf ($Argument1 -eq "syncandfix" -and $SomethingDone -ne 1) {
	$argument = "diff"
	RunSnapraid $argument
	If ($global:Diffchanges -eq 1){
		if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
			Start-Pre-Process
			Check-Parity-Files
		}
		# If enabled take services offline
		ServiceManagement "stop"
		$argument = "sync"
		RunSnapraid $argument
	}
	if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
		Start-Pre-Process
		Check-Parity-Files
	}
	# If enabled take services offline
	ServiceManagement "stop"
	$argument = "fix"
	RunSnapraid $argument
	# If enabled bring services back online
	ServiceManagement "start"
	$CurrentDate = Get-Date
	$message = "SUCCESS: SnapRAID SYNC and FIX Job finished on $CurrentDate"
	WriteExtendedLogFile $message
	Start-Post-Process
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "success" $EmailBody
	$SomethingDone = 1
}
ElseIf ($Argument1 -eq "syncandfullscrub" -and $SomethingDone -ne 1) {
	$argument = "diff"
	RunSnapraid $argument
	If ($global:Diffchanges -eq 1){
		if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
			Start-Pre-Process
			Check-Parity-Files
		}
		# If enabled take services offline
		ServiceManagement "stop"
		$argument = "sync"
		RunSnapraid $argument
	}
	if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
		Start-Pre-Process
		Check-Parity-Files
	}
	# If enabled take services offline
	ServiceManagement "stop"
	$argument = "fullscrub"
	RunSnapraid $argument
	# If enabled bring services back online
	ServiceManagement "start"
	$CurrentDate = Get-Date
	$message = "SUCCESS: SnapRAID SYNC and FULL SCRUB Job finished on $CurrentDate"
	WriteExtendedLogFile $message
	Start-Post-Process
	$subject = $config["SubjectPrefix"]+" "+$message
	Send-Email $subject "success" $EmailBody
	$SomethingDone = 1
}

If ($SomethingDone -ne 1){
	# If another command was passed to the script run this command, else run the sync command
	If ($Argument1 -ne "sync") {
		If (($Argument1 -ne "diff" -and $Argument1 -ne "list" -and $Argument1 -ne "dup" -and $Argument1 -ne "status" -and $Argument1 -ne "pool") -and ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0)){ 
			Start-Pre-Process
			Check-Parity-Files
		}
		# If enabled take services offline
		ServiceManagement "stop"
		$argument = $Argument1
		RunSnapraid $argument
		# If enabled bring services back online
		ServiceManagement "start"
		$CurrentDate = Get-Date
		$message = "SUCCESS: SnapRAID $Argument1 Job finished on $CurrentDate"
		WriteExtendedLogFile $message
		Start-Post-Process
		$subject = $config["SubjectPrefix"]+" "+$message
		Send-Email $subject "success" $EmailBody
		$SomethingDone = 1
	}
	else {
		$argument = "diff"
		RunSnapraid $argument
		If ($global:Diffchanges -eq 1){
			if ($config["SkipParityFilesAtStart"] -eq 1 -and $global:PreProcessHasRun -eq 0){ 
				Start-Pre-Process
				Check-Parity-Files
			}
			# If enabled take services offline
			ServiceManagement "stop"
			$argument = "sync"
			RunSnapraid $argument
			# If enabled bring services back online
			ServiceManagement "start"
			$CurrentDate = Get-Date
			$message = "SUCCESS: SnapRAID SYNC Job finished on $CurrentDate"
			WriteExtendedLogFile $message
			Start-Post-Process
			$subject = $config["SubjectPrefix"]+" "+$message
			Send-Email $subject "success" $EmailBody
			$SomethingDone = 1
		}
		else {
			# NO, so lets log it and exit
			$CurrentDate = Get-Date
			$message = "$CurrentDate No change detected. Nothing to do"
			WriteExtendedLogFile $message
			Start-Post-Process
			$subject = $config["SubjectPrefix"]+" SUCCESS: SnapRAID SYNC - No change detected. Nothing to do"
			Send-Email $subject "success" $EmailBody
			$SomethingDone = 1
		}
	}
}
# End Transcript
Stop-Transcript | out-null