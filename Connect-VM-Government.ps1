<#
.SYNOPSIS 
    Sets up the connection to an Azure VM in Azure Government cloud

.DESCRIPTION
    This runbook sets up a connection to an Azure virtual machine. It requires the Azure virtual machine to
    have the Windows Remote Management service enabled, which is the default. It sets up a connection to the Azure
	subscription and then imports the certificate used for the Azure VM so remote PowerShell calls can be made to it.  

.PARAMETER AzureSubscriptionName
    Name of the Azure subscription to connect to
    
.PARAMETER AzureOrgIdCredential
    A credential containing an Org Id username / password with access to this Azure subscription.

	If invoking this runbook inline from within another runbook, pass a PSCredential for this parameter.

	If starting this runbook using Start-AzureAutomationRunbook, or via the Azure portal UI, pass as a string the
	name of an Azure Automation PSCredential asset instead. Azure Automation will automatically grab the asset with
	that name and pass it into the runbook.

.PARAMETER ServiceName
    Name of the cloud service where the VM is located.

.PARAMETER VMName    
    Name of the virtual machine that you want to connect to  

.EXAMPLE
    Connect-AzureVM -AzureSubscriptionName "Visual Studio Ultimate with MSDN" -ServiceName "Finance" -VMName "WebServer01" -AzureOrgIdCredential $cred

.NOTES
    AUTHOR: System Center Automation Team
    LASTEDIT: Oct 27, 2015 
#>
workflow Connect-VM-Government
{
	[OutputType([System.Uri])]

    Param
    (            
        [parameter(Mandatory=$true)]
        [String]
        $AzureSubscriptionName,

		[parameter(Mandatory=$true)]
        [PSCredential]
        $AzureOrgIdCredential,
        
        [parameter(Mandatory=$true)]
        [String]
        $ServiceName,
        
        [parameter(Mandatory=$true)]
        [String]
        $VMName      
    )

    # Add an environment where the Azure Account and Subscription resides   
    Add-AzureEnvironment `
        -Name "AzureGovernmentCloud" `
        -PublishSettingsFileUrl "https://manage.windowsazure.us/publishsettings/index?client=xplat" `
        -ServiceEndpoint "https://management.core.usgovcloudapi.net" `
        -ActiveDirectoryEndpoint "https://login.windows.net/" `
        -ActiveDirectoryServiceEndpointResourceId "https://management.core.usgovcloudapi.net/" `
        -GalleryEndpoint "https://gallery.usgovcloudapi.net" `
        -ManagementPortalUrl "https://manage.windowsazure.us" `
        -ResourceManagerEndpoint "https://management.usgovcloudapi.net" `
        -StorageEndpoint "core.usgovcloudapi.net" 
   
    # Call to get the Azure Account to be available for Powershell
    Add-AzureAccount -Credential $AzureOrgIdCredential -Environment "AzureGovernmentCloud"

	# Select the Azure subscription we will be working against
    Select-AzureSubscription -SubscriptionName $AzureSubscriptionName | Write-Verbose


    InlineScript { 
        # Get the Azure certificate for remoting into this VM
        $winRMCert = (Get-AzureVM -ServiceName $Using:ServiceName -Name $Using:VMName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint   
        $AzureX509cert = Get-AzureCertificate -ServiceName $Using:ServiceName -Thumbprint $winRMCert -ThumbprintAlgorithm sha1

        # Add the VM certificate into the LocalMachine
        if ((Test-Path Cert:\LocalMachine\Root\$winRMCert) -eq $false)
        {
            Write-Progress "VM certificate is not in local machine certificate store - adding it"
            $certByteArray = [System.Convert]::fromBase64String($AzureX509cert.Data)
            $CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$certByteArray)
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $store.Add($CertToImport)
            $store.Close()
        }
		
		# Return the WinRM Uri so that it can be used to connect to this VM
		Get-AzureWinRMUri -ServiceName $Using:ServiceName -Name $Using:VMName     
    }
}