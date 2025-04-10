#
# Demo code to publish a custom metrrics in an Azure Log Analytics Workspace Custom table using the Azure Monitor Log Ingestion API
#
# Author :  Benoît SAUTIERE (Cellenza)
#
# Version : 1.0
# Date : 2023-10-03
#
# Example : . .\demologingestion.ps1 -ResourceGroup_name "DemoLogIngestion"  -MetricValue (Get-Random -Minimum 0 -Maximum 100)
#
using namespace System.Net
#Requires -PSedition Core
#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Monitor
param(
    [Parameter(mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String]$ResourceGroup_name,
    [Parameter(mandatory = $True)]
    [ValidateRange(0, 100)]
    [int]$MetricValue

)
Set-StrictMode -Version 3.0 
[String]$MetricName = "DemoMetric"
[String]$streamName = "Custom-MyTableRawData" #name of the stream in the DCR that represents the destination table
[String]$WebSite_Time_Zone = "UTC"
[string]$CommputerName = $env:COMPUTERNAME
#
# Check for Azure context
#
$GetAzContext = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $GetAzContext) {
    [String]$ErrorMessage = "No Azure context found. Please login to Azure using Connect-AzAccount."
    Write-Error $ErrorMessage
    exit
}
#
# Check if resource Group exists in the subscription
#
$RG_Object = Get-AzResourceGroup -Name $ResourceGroup_name -ErrorAction SilentlyContinue
if ($null -eq $RG_Object) {
    [String]$ErrorMessage = "Resource group named $ResourceGroup_name does not exist in subscription $((get-azcontext).Subscription.Name)."
    Write-Error $ErrorMessage
    exit
}
else {
    [String]$Message = "Resource group named $ResourceGroup_name exists in subscription $((get-azcontext).Subscription.Name)."
    Write-Output $Message
}
#
# Extract Data Collection Endpoint API and Data Collection rule ImmutableID from azure resources in the resource group
#
[string]$dceEndpoint = (get-azresource -resourcegroupname $ResourceGroup_name -ResourceType microsoft.insights/datacollectionendpoints  -ExpandProperties).Properties.logsIngestion.endpoint
[String]$dcrImmutableId = (get-azresource -resourcegroupname $ResourceGroup_name -ResourceType microsoft.insights/datacollectionrules  -ExpandProperties).Properties.immutableId
#
# Publich metric to Azure Monitor Log Ingestion API
#
[String]$SelectedAzureRegion = (get-azlocation | Select-Object location).location | get-random
[String]$Message = "Metric to Azure Monitor Log Ingestion API $MetricName = $MetricValue for environment $CommputerName in Region $SelectedAzureRegion."
Write-Output  $Message
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
        "InstanceName": "$SelectedAzureRegion",
        "TimeZone": "$WebSite_Time_Zone",
        "Level": 0,
        "CounterName": "$MetricName",
        "CounterValue": "$MetricValue"    
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
    return $null
}
$BearTokenplainText = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)