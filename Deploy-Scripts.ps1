param(
	[Parameter(Mandatory=$true)] [String]$ServerName
)
Clear-Host

# Global params
$ServerInstance = $ServerName
$Database = "master" # <-- to avoid connecting to a database which does not exist

# build an array of files, in the order they have to be executed
$filelist = New-Object System.Collections.ArrayList
# read list of files from the "configuration" text file
$ScriptFiles = Get-Content -Path ".\scriptslist.txt"
# verify that the files adhere to specific criteria
ForEach ($ScriptFile in $ScriptFiles) {
    # only SQL files allowed; check if the file exists
    if (($ScriptFile -like "*.sql") -and (Test-Path $ScriptFile -PathType Leaf)) {
        # NOTE: The "> $null" part is to remove the array item index output
        $filelist.Add($ScriptFile.ToString()) > $null
    }
    #else { "Script '{0}' could not be found" -f $ScriptFile }
}

# read and deploy scripts to the SQl Server instance
if ($filelist.Count -gt 0) {
    # load and run the scripts listed in the array
    "{0} : Starting deployment of {1} database scripts to {2}" -f $(Get-Date -Format "HH:mm:ss"), $filelist.Count, $ServerInstance
    "{0} : ---------------------------------------------------------------------------" -f $(Get-Date -Format "HH:mm:ss")
    # start loop
    ForEach ($script In $filelist) {
        $scriptexecpath = $script.ToString()
        # check if the file exists, again
        if (Test-Path $scriptexecpath -PathType Leaf) {
            $sql = Get-Content -Path $scriptexecpath -Raw
            "{0} : Running script: {1}" -f $(Get-Date -Format "HH:mm:ss"), $scriptexecpath
            try { Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $sql -AbortOnError }
            catch { break } # On Error, Exit the ForEach Loop
        }
        else { "{0} : Script '{1}' could not be found" -f $(Get-Date -Format "HH:mm:ss"), $scriptexecpath }
    }
    # end loop
    "{0} : ---------------------------------------------------------------------------" -f $(Get-Date -Format "HH:mm:ss")
    "{0} : Script execution complete" -f $(Get-Date -Format "HH:mm:ss")
}

# deallocate variables
$ServerInstance = $null
$Database = $null
$filelist = $null
$script = $null
$scriptexecpath = $null
$sql = $null
