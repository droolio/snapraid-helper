# snapraid-helper

Powershell script to Snapraid. It can stop services before any actions and start them afterwards and/or run pre/post process executables. Aborting on disk errors in the eventlog is configurable. Email can be send with the snapraid output as a attachment or as the email body.

This is a powershell helper script for SnapRaid to be used in the Task Scheduler.

Current Features:

* If no parameter is passed it runs a sync
* Passing singleword (!) parameters to snapraid if the script is called with the word as an argument
* Different keywords for special actions (syncandscrub,syncandfullscrub and syncandcheck)
* Logging to Eventlog
* If log should be an attachment give the option to zip the file is above a certain size
* Set maximum attachment size to prevent huge emails
* Check to prevent double execution of script and/or snapraid
* Include the extended SnapRAID Log (5.X+ prints detailed error infos there) in the email if there is an snapraid error
* Pre/Post Process (Pre will be called before the parity file test and Post will be called before E-Mail will be sent)
* Option to skip parityfile check to the moment where parity is accessed by snapraid (requires Snapraid 6.0+) (Usefull in combination with pre/post process for mounting volumes i.e.)
* Post Process/Service start will only run if Pre Process/Service stop has run
* If argument passed is "syncandcheck" (without the "") there will be a sync (if needed) before a check is called
* If argument passed is "syncandscrub" (without the "") there will be a sync (if needed) before a scrub is called (scrub without any parameters, snapraid default)
* If argument passed is "syncandfullscrub" (without the "") there will be a sync (if needed) before a full scrub is called (-p 100 -o 0 as parameters)
* If argument passed is "syncandfix" (without the "") there will be a sync (if needed) before a fix is called (fix is called without any parameters)
* Configurable Email Notifications on Success and/or Failure with gmail SMTP support
* Checks Eventlog for disk errors and will notify and/or abort sync
* Logging and Log rotation of helper script logs
* SnapRAID Pre-Diff run to
  * see if there is any need to run a sync
  * ensure that the number of deleted files does not exceed a configurable threshold 
* Process stopping and starting
* Verify paths and files exist
* Validate many configurations
* Configuration .ini file for configurables (has to be in the same path and has to be the same name (without the .ps1 of course))
* If EnableDebugOutput is set to 1 all variables will be written to the powershell console before the snapraid process starts (Usefull for debugging)
