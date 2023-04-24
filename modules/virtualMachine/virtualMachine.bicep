targetScope = 'resourceGroup'

@description('Virtual Server Name')
@minLength(1)
@maxLength(15)
param parVirtualMachineName string

@description('Location for all resources.')
param parLocation string = resourceGroup().location

@description('Virtual Machine size. Check MS docs or run pwsh, e.g.:"get-azvmSize -Location westeurope |sort -Property Name" DEFAULT: Standard_B1ms')
param parVMSize string = 'Standard_B1ms'

@description('Existing VNET that contains the domain controller')
param parVirtualNetworkName string

@description('Existing subnet that contains the domain controller')
param parSubnetName string

@description('The FQDN of the AD domain')
param parDomainToJoin string

@description('Username of the account on the domain')
param parDomainUsername string

@description('Password of the account on the domain')
@secure()
param parDomainPassword string

@description('Organizational Unit path in which the nodes and cluster will be present. Canonical format example: OU=servers,DC=domain,DC=com')
param parOUPath string = ''

@description('Set of bit flags that define the join options. Default value of 3 is a combination of NETSETUP_JOIN_DOMAIN (0x00000001) & NETSETUP_ACCT_CREATE (0x00000002) i.e. will join the domain and create the account on the domain. For more information see https://msdn.microsoft.com/en-us/library/aa392154(v=vs.85).aspx')
param parDomainJoinOptions int = 3

@description('The name of the administrator of the new VM.')
param parAdminUsername string

@description('The password for the administrator account of the new VM.')
@secure()
param parAdminPassword string

@description('Storage account name for Boot Diagnostics. If not provided Boot Diagnostics will be disabled')
param parBootDiagStorageAccountName string = ''

@description('Log Analytics Workspace name where VM metrics should be stored. If no name is provived no diagnostic settings will be created.')
param parLogAnalyticsWorkspaceId string = ''

@allowed([
  true
  false
])
@description('Condition to deploy Public IP if required')
param parDeployPublicIP bool

@description('Unique public DNS prefix for the deployment. The fqdn will look something like \'<dnsname>.westus.cloudapp.azure.com\'. Up to 62 chars, digits or dashes, lowercase, should start with a letter: must conform to \'^[a-z][a-z0-9-]{1,61}[a-z0-9]$\'. DEFAULT: parVirtualMachineName')
@minLength(1)
@maxLength(62)
param parDNSLabelPrefix string = toLower(parVirtualMachineName)

      //@description('Number of NIC interfaces. DEFAULT: 1')
      //param parNICNumber int = 1

@description('The image publisher. DEFAULT: MicrosoftWindowsServer')
param parImagePublisher string = 'MicrosoftWindowsServer'

@description('Specifies the offer of the platform image or marketplace image used to create the virtual machine. DEFAULT: WindowsServer')
param parImageOffer string = 'WindowsServer'

@description('The image SKU. DEFAULT: 2022-Datacenter')
param parSKU string = '2022-Datacenter'

@description('List of data disks based on sizes in GB. Letters will be assigned sequentially and then would need to be reassigned as required after provisioning. Example: 500, 200, 1000')
param parDataDisks array = []

@description('List of for VM deployment. E.g.: [1,2,3]. DEFAULT:[1]')
param parZones array = [1]

@description('Recovery Services Vault name. If not provided Backup is disabled')
param parRecoveryServicesVaultName string = ''

@description('Recovery Services Vault RG. If not provided Backup is disabled')
param parRecoveryServicesVaultRG string = ''

@description('Backup policy name if parRecoveryServicesVaultName is provided')
param parBackupPolicyName string = ''

@description('Object with Tags to be applied to all resources in module. Default: empty array')
param parTags object = {}

@description('Set Parameter to true to Opt-out of deployment telemetry')
param parTelemetryOptOut bool = false

// Customer Usage Attribution Id
var varCuaid = '59c2ac61-cd36-413b-b999-86a3e0d958fb'

var varNicName             = 'NIC-${parVirtualMachineName}'
var varPublicIPAddressName = 'PIP-${varNicName}'
var varDiskLetters         = ['E','F','G','H','I','J','K','L','M','N','O','P','Q','R']


resource publicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = if (parDeployPublicIP) {
    name      : varPublicIPAddressName
    location  : parLocation
    properties: {
      publicIPAllocationMethod: 'Dynamic'
      dnsSettings             : {
        domainNameLabel: parDNSLabelPrefix
      }
    }
}

resource resStorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = if (!empty(parBootDiagStorageAccountName)) {
    name: parBootDiagStorageAccountName
}

resource resNIC 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name      : varNicName
  location  : parLocation
  properties: {
    ipConfigurations: [
      {
        name      : 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress          : parDeployPublicIP ? { id: publicIp.id }: null
          subnet                   : {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', parVirtualNetworkName, parSubnetName)
          }
        }
      }
    ]
  }
}

resource resVirtualMachine 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name      : parVirtualMachineName
  location  : parLocation
  properties: {
    hardwareProfile: {
      vmSize: parVMSize
    }
    osProfile: {
      computerName            : parVirtualMachineName
      adminUsername           : parAdminUsername
      adminPassword           : parAdminPassword
      allowExtensionOperations: true
      windowsConfiguration: {
        provisionVMAgent      : true
        enableAutomaticUpdates: true
        patchSettings         : {
          patchMode     : 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
        enableVMAgentPlatformUpdates: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: parImagePublisher
        offer    : parImageOffer
        sku      : parSKU
        version  : 'latest'
      }
      osDisk: {
        name        : '${parVirtualMachineName}_OS'
        caching     : 'ReadWrite'
        createOption: 'FromImage'
      }
      dataDisks: [for (disk, i) in parDataDisks: {
        name        : '${parVirtualMachineName}_${i}'
        caching     : 'None'
        createOption: 'Empty'
        diskSizeGB  : disk
        lun         : i
        managedDisk : {
          storageAccountType: contains(toUpper(parVirtualMachineName), 'PRD') ? 'StandardSSD_ZRS' : 'StandardSSD_LRS'
        }
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resNIC.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: !empty(parBootDiagStorageAccountName) ? {
      enabled   : true
      storageUri: resStorageAccount.properties.primaryEndpoints.blob
      }         : {}
    }
  }
  zones: parZones
  tags : parTags

  resource resVMDomainJoin 'extensions' = {
    name      : 'joindomain'
    location  : parLocation
    properties: {
      publisher              : 'Microsoft.Compute'
      type                   : 'JsonADDomainExtension'
      typeHandlerVersion     : '1.3'
      autoUpgradeMinorVersion: true
      settings               : {
        name   : parDomainToJoin
        ouPath : !empty(parOUPath) ? parOUPath : null
        user   : '${parDomainUsername}@${parDomainToJoin}'
        restart: true
        options: parDomainJoinOptions
      }
      protectedSettings: {
        Password: parDomainPassword
      }
    }
  }
  resource resMMAAgent 'extensions' = {
    name      : 'MMAAgent'
    location  : parLocation
    properties: {
      publisher              : 'Microsoft.EnterpriseCloud.Monitoring'
      type                   : 'MicrosoftMonitoringAgent'
      typeHandlerVersion     : '1.0'
      autoUpgradeMinorVersion: true
      settings               : {
        workspaceId: parLogAnalyticsWorkspaceId
      }
    }
    tags      : parTags
  }

  resource resAntiMalware 'extensions' = {
    name      : 'IaaSAntimalware'
    location  : parLocation
    properties: {
      publisher              : 'Microsoft.Azure.Security'
      type                   : 'IaaSAntimalware'
      typeHandlerVersion     : '1.1'
      autoUpgradeMinorVersion: true
      settings               : {
        AntimalwareEnabled: true
        Exclusions        : {
          Extensions: '.ADD;.ADI;.AOD;.AOI;.bak;.bmp;.cfg;.config;.dat;.dic;.edb;.fbk;.gif;.ico;.idx;.ini;.jpg;.KHD;.KHI;.ldf;.lnk;.log;.mdf;.ndf;.png;.pst;.sft;.tmp;.trn;.txt;.vhd;.vhdx;.eml;.CHK'
          Paths     : '%windir%\\SoftwareDistribution\\Datastore\\Datastore.edb;%ALLUSERSPROFILE%\\Application Data\\Microsoft\\Application Virtualization Client\\;%ALLUSERSPROFILE%\\Documents\\SoftGrid Client;%ALLUSERSPROFILE%\\NTuser.pol;%PROGRAMDATA%\\Microsoft\\Application Virtualization Client\\SoftGrid Client;%SystemDrive%\\inetpub\\temp\\IIS Temporary Compressed File;%SystemRoot%\\System32\\GroupPolicy\\Machine\\registry.pol;%SystemRoot%\\System32\\GroupPolicy\\registry.pol;%SystemRoot%\\System32\\GroupPolicy\\User\\registry.pol;%systemroot%\\system32\\inetsrv;%systemroot%\\Sysvol;%USERPROFILE%\\AppData\\Local\\SoftGrid Client;%UserProfile%\\AppData\\Local\\Temp\\*;%USERPROFILE%\\AppData\\Roaming\\SoftGrid Client;%UserProfile%\\NTUSER.DAT;%windir%\\Ntds\\edb*.jrs;%windir%\\Ntds\\edb*.log;%windir%\\Ntds\\ntds.dit;%windir%\\Ntds\\ntds.pat;%windir%\\Ntds\\res*.log;%windir%\\Ntfrs\\jet\\log\\*.log;%windir%\\Ntfrs\\jet\\ntfrs.jdb;%windir%\\Ntfrs\\jet\\sys\\edb.chk;%windir%\\Security\\Database\\*.chk;%windir%\\Security\\Database\\*.edb;%windir%\\Security\\Database\\*.jrs;%windir%\\Security\\Database\\*.log;%windir%\\Security\\Database\\*.sdb;%windir%\\SoftwareDistribution\\Datastore\\Datastore.edb;%windir%\\SoftwareDistribution\\Datastore\\Logs\\Edb.chk;%windir%\\SoftwareDistribution\\Datastore\\Logs\\Res*.jrs;%windir%\\SoftwareDistribution\\Datastore\\Logs\\Res*.log;%windir%\\SoftwareDistribution\\Datastore\\Logs\\Tmp.edb;C:\\Documents and Settings\\All Users\\Application Data\\Microsoft\\SharePoint\\Config;C:\\Program Files (x86)\\2X;C:\\Program Files\\2x;C:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\12\\Data\\Applications;C:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\12\\Logs;C:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\14\\Data\\Applications;C:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\14\\Logs;C:\\Program Files\\EVault Software\\Agent\\VVAgent.exe;C:\\Program Files\\Microsoft ISA Server;C:\\Program Files\\Microsoft Office Servers\\12.0\\Bin;C:\\Program Files\\Microsoft Office Servers\\12.0\\Data;C:\\Program Files\\Microsoft Office Servers\\12.0\\Logs;C:\\Program Files\\Microsoft Office Servers\\14.0\\Data;C:\\Program Files\\Microsoft SQL Server\\MSSQL$instancename\\FTDATA;C:\\Program Files\\Microsoft SQL Server\\MSSQL\\FTDATA;C:\\ProgramData\\Microsoft\\SharePoint\\;C:\\W:indows\\Microsoft.NET\\Framework64\\v2.0.50727\\Temporary ASP.NET Files;c:\\Windows\\Cluster;C:\\WINDOWS\\system32\\LogFiles;C:\\Windows\\Syswow64\\LogFiles;D:\\Program Files (x86)\\2X;D:\\Program Files\\2x;D:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\12\\Data\\Applications;D:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\12\\Logs;D:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\14\\Data\\Applications;D:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\14\\Logs;D:\\Program Files\\Microsoft CRM Email\\Service\\Microsoft.Crm.Passport.IdCrl.dl;D:\\Program Files\\Microsoft CRM Email\\Service\\microsoft.crm.tools.email.management.exe;D:\\Program Files\\Microsoft CRM Email\\Service\\Microsoft.Crm.Tools.EmailAgent.Configuration.bi;D:\\Program Files\\Microsoft CRM Email\\Service\\microsoft.crm.tools.emailagent.exe;D:\\Program Files\\Microsoft CRM Email\\Service\\Microsoft.Crm.Tools.EmailAgent.SystemState.xml;D:\\Program Files\\Microsoft CRM Email\\Service\\Microsoft.Crm.Tools.EmailAgent.xm;D:\\Program Files\\Microsoft CRM Email\\Service\\microsoft.crm.tools.emailproviders.dl;D:\\Program Files\\Microsoft CRM Email\\Service\\Microsoft.Exchange.WebServices.dl;D:\\Program Files\\Microsoft Dynamics ERP;D:\\Program Files\\Microsoft ISA Server;D:\\Program Files\\Microsoft Office Servers\\12.0\\Bin;D:\\Program Files\\Microsoft Office Servers\\12.0\\Data;D:\\Program Files\\Microsoft Office Servers\\12.0\\Logs;D:\\Program Files\\Microsoft Office Servers\\14.0\\Data;D:\\Program Files\\Microsoft SQL Server\\MSRS10_50.MSSQLSERVER\\Reporting Services;D:\\Program Files\\Microsoft SQL Server\\MSSQL$instancename\\FTDATA;D:\\Program Files\\Microsoft SQL Server\\MSSQL\\FTDATA;D:\\ProgramData\\Microsoft\\SharePoint\\;D:\\Windows\\Microsoft.NET\\Framework64\\v2.0.50727\\Temporary ASP.NET Files;D:\\ProgramData\\Microsoft\\Application Virtualization Client\\SoftGrid Client;C:\\Program Files\\Microsoft Office Servers\\15.0\\Data;C:\\Program Files\\Microsoft System Center 2012 R2\\Operations Manager\\Server\\Health Service State;C:\\Program Files\\System Center Operations Manager\\Gateway\\Health Service State;C:\\Program Files\\Microsoft Monitoring Agent\\Agent\\Health Service State'
          Processes : 'dpmra.exe;csc.exe;VVAgent.exe;TSTheme.exe;Microsoft.Dynamics.GP.eConnect.Service.exe;ReportingServicesService.exe;dynamics.exe;monitoringhost.exe;Smsexec.exe;Ccmexec.exe;CmRcService.exe;Sitecomp.exe;Smswriter.exe;Smssqlbkup.exe;sqlservr.exe'
        }
        RealtimeProtectionEnabled: 'true'
        ScheduledScanSettings: {
          isEnabled: 'true'
          scanType : 'Quick'
          day      : '7'
          time     : '120'
        }
      }
    }
  }
}

resource resVirtualMachineSQL 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2022-08-01-preview' = if (contains(parImagePublisher,'MicrosoftSQLServer')) {
  name    : parVirtualMachineName
  location: parLocation
  properties: {
    virtualMachineResourceId    : resVirtualMachine.id
    sqlManagement               : 'Full'
    sqlServerLicenseType        : 'PAYG'
    storageConfigurationSettings: {
      diskConfigurationType: 'NEW'
      storageWorkloadType  : 'GENERAL'
      sqlDataSettings      : {
        luns           : range(0, length(parDataDisks))
        defaultFilePath: '${varDiskLetters[0]}:\\SQLData'
      }
      sqlLogSettings: {
        luns           : range(0, length(parDataDisks))
        defaultFilePath: '${varDiskLetters[0]}:\\SQLLogs'
      }
      sqlTempDbSettings: {
        defaultFilePath: '${varDiskLetters[0]}:\\SQLTempDB'
      }
    }
  }
}

module modBackupProtectedItem '../backup/protectedItem.bicep' = if (!empty(parRecoveryServicesVaultName)) {    
    name: 'mod-protectedItem-${parRecoveryServicesVaultName}-${resVirtualMachine.name}' 
    scope: resourceGroup(parRecoveryServicesVaultRG)
    params: {
      parRecoveryServicesVaultName: parRecoveryServicesVaultName
      parVirtualMachineName       : resVirtualMachine.name
      parBackupPolicyName         : parBackupPolicyName
      parTags                     : parTags
    }
}


module modCustomerUsageAttribution '../../CRML/customerUsageAttribution/cuaIdSubscription.bicep' = if (!parTelemetryOptOut) {
  name  : 'pid-${varCuaid}-${uniqueString(resourceGroup().name)}'
  scope: subscription()
  params: {}
}


output VMid string   = resVirtualMachine.id
output VMName string = resVirtualMachine.name

