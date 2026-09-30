-- SpeechBridge Setup: makes every game in the CrossOver bottle speak through the Mac.
-- Runs the copy of install.sh inside this app (safe to run any time: after installing a
-- game, or after a Steam "verify integrity" puts a game's original speech plugins back)
-- and shows what it did.
set installer to (POSIX path of (path to me)) & "Contents/Resources/SpeechBridge/install.sh"
set report to ""
try
	set report to do shell script quoted form of installer & " 2>&1"
on error msg
	set report to "The installer stopped with an error:" & return & msg
end try
set summary to ""
repeat with l in paragraphs of report
	set t to l as string
	if t does not end with ":" and t is not "" and t does not start with "SpeechBridge install" then set summary to summary & t & return
end repeat
if summary is "" then set summary to "Nothing needed doing."
display dialog "SpeechBridge is set up." & return & return & summary buttons {"OK"} default button "OK" with title "SpeechBridge Setup" giving up after 120
