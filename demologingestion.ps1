#
# Publish custom Metric for Azure Firewall As a Service solution using the Azure Monitor Logs Ingestion API
# Rely on the User-Assigned Managed Identity to perform operation
#
using namespace System.Net
#Requires -PSedition Core
#Requires -Version 7.0
param($Request, $TriggerMetadata)
Set-StrictMode -Version 1.0 # Because $Request.Query may be empty
$VerbosePreference = 'SilentlyContinue'
[Bool]$Debug_Flag = $false # to be configured to true for local debug.
[String]$streamName = "Custom-MyTableRawData" #name of the stream in the DCR that represents the destination table
[String]$WebSite_Time_Zone = "UTC"
#[String]$TELEMETRY_MODULE_NAME = "AzureFirewallAsAService"
#
# Manage input parameters
#
if ($Debug_Flag -eq $false) {
    $AzureFirewallRegion = $Request.Query.AzureFirewallRegion
    If ([string]::IsNullOrEmpty($AzureFirewallRegion)) {
        $AzureFirewallRegion = $Request.Body.AzureFirewallRegion
    }
    $MetricName = $Request.Query.MetricName
    If ([string]::IsNullOrEmpty($MetricName)) {
        $MetricName = $Request.Body.MetricName
    }
    $MetricValue = $Request.Query.MetricValue
    If ([string]::IsNullOrEmpty($MetricValue)) {
        $MetricValue = $request.Body.MetricValue
    }
    If ([string]::IsNullOrEmpty($AzureFirewallRegion)) {
        #
        # Missing parameter
        # OK
        [String]$ErrorMessage = "AzureFirewallRegion parameter missing."
        Write-Error $ErrorMessage
        exit
    }
    If ([string]::IsNullOrEmpty($MetricName)) {
        #
        # Missing parameter
        # OK
        [String]$ErrorMessage = "MetricName parameter missing."
        Write-Error $ErrorMessage
        exit
    }
    If ([string]::IsNullOrEmpty($MetricValue)) {
        #
        # Missing parameter
        # OK
        [String]$ErrorMessage = "MetricValue parameter missing."
        Write-Error $ErrorMessage
        exit
    }
    [String]$Environment_Name = (Get-ChildItem env:Environment).value
    [String]$CommputerName = $Environment_Name
    $SubscriptionID = (Get-ChildItem env:SubscriptionID).value
    [String]$dceEndpoint = (Get-ChildItem env:dCELogsIngestion).value
    [String]$dcrImmutableId = (Get-ChildItem env:dCRImmutableId).value
    [String]$ApplicationInsights_Connection_String = (Get-ChildItem env:APPLICATIONINSIGHTS_CONNECTION_STRING).value
    Set-AzContext -Subscription $SubscriptionID | Out-Null
}
else {
    [String]$ApplicationInsights_Connection_String = "InstrumentationKey=ab677503-3d10-424e-b4ed-083f44073927;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/;ApplicationId=c3f00ca5-f4cc-49fd-9718-ba1de22b39da"
    [String]$Solution_RG = "FACTORY_PRD"
    [String]$Environment_Name = "PRD"
    [String]$CommputerName = $Environment_Name
    [String]$AzureFirewallRegion = "WestEurope"
    [String]$MetricName = "Demo"
    $MetricValue = 100
    [string]$dceEndpoint = (get-azresource -resourcegroupname $Solution_RG -ResourceType microsoft.insights/datacollectionendpoints -name ($Environment_Name + "-DCEACTIVITYLOG-" + $AzureFirewallRegion.tolower()) -ExpandProperties).Properties.logsIngestion.endpoint
    [String]$dcrImmutableId = (get-azresource -resourcegroupname $Solution_RG -ResourceType microsoft.insights/datacollectionrules -name ($Environment_Name + "-DCRACTIVITYLOG-" + $AzureFirewallRegion.tolower()) -ExpandProperties).Properties.immutableId
}
# Blocked - 334 - [Azure Functions] - Add Application Insights Instrumentation
#Initialize-THTelemetry -ModuleName $TELEMETRY_MODULE_NAME
#Set-THTelemetryConfiguration -UserOptIn $True -ModuleName $TELEMETRY_MODULE_NAME
#Add-THAppInsightsConnectionString -ConnectionString $ApplicationInsights_Connection_String -ModuleName $TELEMETRY_MODULE_NAME
Set-StrictMode -Version 3.0
$VerbosePreference = 'SilentlyContinue'
#
# Azure Log Ingestion API publish metric
#
Function Publish_Custom_Metric(
    [Parameter(mandatory = $True)]
    [String]$CommputerName,
    [Parameter(mandatory = $True)]
    [String]$Counter_Name,
    [Parameter(mandatory = $True)]
    [Int]$Counter_value,
    [Parameter(mandatory = $True)]
    [Int]$Level    
) {
    #
    # Get Access token from current context
    #
    Add-Type -AssemblyName System.Web
    # Decode SecureString : https://learn.microsoft.com/en-us/powershell/azure/faq?view=azps-13.3.0#how-can-i-convert-a-securestring-to-plain-text-in-powershell-
    $SecureString = (Get-AzAccessToken  -ResourceUrl "https://monitor.azure.com/" -AsSecureString -WarningAction SilentlyContinue).Token
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    $BearTokenplainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    $currentTime = Get-Date ([datetime]::UtcNow) -Format O
    $staticData = @"
[
{
    "Time": "$currentTime",
    "Computer": "$CommputerName",
    "AdditionalContext": {
        "InstanceName": "$AzureFirewallRegion",
        "TimeZone": "$WebSite_Time_Zone",
        "Level": $Level,
        "CounterName": "$Counter_Name",
        "CounterValue": "$Counter_value"    
    }
}
]
"@;
    # https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview
    try {
        $body = $staticData;
        $headers = @{"Authorization" = "Bearer $BearTokenplainText"; "Content-Type" = "application/json" }
        $uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/$($streamName)?api-version=2021-11-01-preview"
        $uploadResponse = Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers   
    }
    catch {
        [String]$ErrorMessage = "Error while publishing custom metrics using uri $uri : $($_.Exception.Message)."
        Write-Error $ErrorMessage
        #Send-THException -Exception $ErrorMessage -ModuleName $TELEMETRY_MODULE_NAME
        return $null
    }
    $BearTokenplainText = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    return $uploadResponse
}
#
# Code begin
#
# New Log Ingestion API
[String]$Message = "Metric to Azure Monitor Log Ingestion API $MetricName = $MetricValue for environment $CommputerName in Region $AzureFirewallRegion."
Write-Output  $Message
$return = Publish_Custom_Metric -CommputerName $CommputerName -Counter_Name $MetricName -Counter_value $MetricValue -Level 0
If ($null -ne $return) {
    [String]$BodyMessage = "Metric successfully published."
    Write-Output $BodyMessage
}
else {
    [String]$BodyMessage = "Error while publishing custom metrics."
    Write-Output $BodyMessage
}