# Scripts-Deployment

## Synopsis

Executes a list of SQL script files agianst a list of SQL Server instances.

## Description

Based on an open-source project hosted at <https://github.com/reubensultana/Scripts-Deployment>  
Reads a text file containing a list of Servers, another file containing a list of TSQL Scripts, and executes all of the scripts against the list of remote servers.  
The output is stored as text in a LOG file in a subfolder, using the time stamp name for the file name.

## Syntax

``` powershell
.\Deploy-Scripts.ps1 
    [-ServerListFile] <IO.FileInfo>]
    [-ScriptListFile] <IO.FileInfo>]    
    [-ConnectionTimeout] <Int32]
    [-QueryTimeout] <Int32]
    [<CommonParameters>]
```

## Examples

### Example 1

Parameters inline:

``` powershell
.\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt -ConnectionTimeout 60 -QueryTimeout 60
```

### Example 2

This will use defaults for ConnectionTimeout and QueryTimeout:

``` powershell
.\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt
```

### Example 3

Parameter values in variables:

``` powershell
[string] $ServerListFile = ".\ServerList.txt"
[string] $ScriptListFile = ".\FileList.txt"
.\Deploy-Scripts.ps1 -ServerListFile .\ServerList.txt -ScriptListFile .\FileList.txt -ConnectionTimeout 60 -QueryTimeout 60
```

### Example 4

This is my favourite example. Passing parameter values using Splatting:

``` powershell
$Params = @{
    ServerListFile      = ".\ServerList.txt"
    ScriptListFile      = ".\FileList.txt"
    ConnectionTimeout   = 60
    QueryTimeout        = 60
    Verbose             = $true
}
.\Deploy-Scripts.ps1 @Params 
```

## Required Parameters

**-ServerListFile**  
A text file containing the list of servers where the scripts will be executed/deployed.  
NOTE: the files must exist (DOH!) and have to have a SQL extension.

**-ScriptListFile**  
A text file containing the paths to the list of files that will be executed/deployed.  
NOTE: each script must contain the name of the affected database, otherwise execution will default to "master".

## Optional Parameters

Both are mapped to the respective parameters from the [Invoke-Sqlcmd cmdlet](https://docs.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd) - so I'm reproducing the orignal documentation description.

**-ConnectionTimeout**  
Specifies the number of seconds when this cmdlet times out if it cannot successfully connect to an instance of the Database Engine. The timeout value must be an integer value between 0 and 65534. If 0 is specified, connection attempts do not time out.

**-QueryTimeout**  
Specifies the number of seconds before the queries time out. If a timeout value is not specified, the queries do not time out. The timeout must be an integer value between 1 and 65535.
