# Scripts-Deployment

## Synopsis

Deploy SQL scripts in a sequence using PowerShell

## Description

Reads a text file containing a list of databases, another file containing a list of scripts, and executes all of the scripts against the list of databases.
The output is stored as text in a LOG file in the specified folder, using the database name for the file name.

## Syntax

``` powershell
.\Deploy-Scripts.ps1 
    [-scriptListFile] <IO.FileInfo>]
    [-databaseListFile] <IO.FileInfo>]    
    [-serverInstance] <String>]
    [-sqlAuthCredential] <PSCredential>]
    [-logFilePath] <String>]
    [-QueryTimeout] <Int32]
    [<CommonParameters>]
```

## Examples

### Example 1

Using Windows Authentication

``` powershell
.\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -logFilePath "C:\TEMP" -QueryTimeout 7200
```

### Example 2

Using SQL Authentication and code
First create a PSCredential object to avoid entering the Username and Password in clear text

``` powershell
[string] $username="testuser"
[System.Security.SecureString] $pass = ConvertTo-SecureString "testuserpassword" -AsPlainText -Force
$sqlAuthCredential = New-Object System.Management.Automation.PSCredential ($username, $pass)
```

Another approach would be to launch a prompt window

``` powershell
$sqlAuthCredential = Get-Credential -Message "Enter credentials used for SQL Authentication"
.\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -sqlAuthCredential $sqlAuthCredential -logFilePath "C:\TEMP" -QueryTimeout 7200
```

### Example 3

Using SQL Authentication with prompt window

``` powershell
$sqlAuthCredential = Get-Credential -Message "Enter credentials used for SQL Authentication"
.\Deploy-Scripts.ps1 -scriptListFile ".\scriptslist.txt" -databaseListFile ".\databaselist.txt" -serverInstance "localhost" -sqlAuthCredential $sqlAuthCredential -logFilePath "C:\TEMP" -QueryTimeout 7200
```

## Required Parameters

**-scriptListFile**  
The path to the list of scripts that will be executed against the list of databases. This parameter is mandatory.

**-databaseListFile**  
The path to the list of databases that will be affected by the list of scripts. This parameter is mandatory.

**-serverInstance**  
The name of the SQL Server hosting the databases. This parameter is mandatory and defaults to "localhost".

**-logFilePath**  
The full path to the folder where the log/s will be written. Does not need to exist. This parameter is required.

## Optional Parameters

**-sqlAuthCredential**  
The PSCredential object holding the credentials used for SQL Authentication ONLY. This is an optional parameter.

**-queryTimeout**  
Specifies the number of seconds before the queries time out. If not specified it will default to 3600 (1 hour). The timeout must be an integer value between 1 and 65535.
