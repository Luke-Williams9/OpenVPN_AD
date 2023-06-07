# OpenVPN AD integration
### Machine level VPN using ADCS-issued certificates

This is intended to be a machine-level OpenVPN setup that 'just works' … during the work hours that we specify.
It was designed for use with OpenVPN on a pfSense firewall, using an AD-CS Certificate Authority
It provides machine-level VPN connectivity for domain computers, for always-on AD domain connection, using non-exportable certificates
Logon hours can be limited, where the computer is actively disconnected from the VPN after hours.

The VPN runs as a system service, and as such, does not show up in the OpenVPN GUI. The setup script puts shortcuts for service start/stop, and log view in the start menu, under OpenVPN. The service permissions are altered to allow regular users to start and stop the VPN manually. They are not allowed to disable/enable it. When off business hours, the VPN service is disabled, and can only be enabled by an administrator or the system.

## Requirements
- A pfSense firewall running OpenVPN
- An AD CS Certificate Authority with CEP / CEP web / OCSP configured, and autoenrollment for domain member computers
- OCSP running in your certificate infrastructure, so that the firewall can check certificate revocation 
- An RMM or deployment tool for mass deployment
- A good brain to figure out everything i'm missing in this unfinished documentation

## Notes
- To limit connection hours, client computer users must not be local admin
- the scripts are set to run from %programdata%\corpvpn
- If you wish to change this folder, will need to change $install_path in a few scripts, and update the task xml files

## Setup

** This is very very under construction, feel free to ask me for clarification **
1. Create an exportable web certificate template for your firewall:
On your AD CS Server, open the Certifate Templates console
- Duplicate the "Web Server" template, and go through the properties tabs:
- 'General' Tab: give it a name, set its validity period to something you think is appropriate (1-2 years? 6 week renewal period)
- 'Request Handling' tab: check the 'Allow private key to be exported' box
- 'Subject Name' tab: Supply in the request
- 'Extensions' tab: Application Policies should only contain 'Server Authentication'
- 'Security' tab: Keep this tight. Allow Read/Write/Enroll permissions to ideally just the one computer you are using (and not for any users). A cert generated from this template can be used to MITM your vpn clients.
- 'Issuance Requirements' tab: I haven't done anything with this yet, but probably should. Consider requiring a CA cert manager approval for this template. I'll update this doc once I've done so myself.
- Click apply / OK, then go to Certification Authority -> right click on 'Certificate Templates' -> New -> Certificate Template to issue, select your template, and click OK.
2. Generate and export the pfSense server certificate
- Open Computer certificates, go to personal -> certificates (or just personal) -> right click -> all tasks -> request new certificate
- Next -> (you should see your policy provider listed here) -> Next -> Select your pfsense server template -> click on 'more information' -> Change subject name type to Common Name, add an FQDN, click apply / OK -> click Enroll
- the new certificate will be listed in Comptuer certificates \ personal \ certificates. Right click on it -> All tasks -> Export
- Yes export the private key -> next
- check 'export all extended properties' (may not be necessary for this one?) -> next
- check 'password', put in a password twice, set encryption to SHA256 -> next
- specify a path -> next -> finish
3. Export the CA cert
- open Computer certificates on the CA (or any domain computer)
- Find the root CA cert under personal \ certificates, or trucsted root certifacation authorities \ certificates
- right click -> all tasks -> export
- next -> select Base-64 encoded x509 -> next -> give it a path -> next -> finish
4. Import the server and CA certs into pfsense
- Log into your pfsense -> go to System \ Cert manager \ CAs, click Add at the bottom
- Fill in the descriptive name, set method to "Import existing Certificate Authority"
- paste the contents of the exported CA file into 'certificate data' (certificate private key is left blank)
- click Save
- go to System \ Cert Manager \ Certificates, click Add/Sign at the bottom
- set Method to 'Import an existing certificate', certificate type 'PKCS #12 (PFX)'
- choose the .pfx file you exported, enter its password, click Save
- Delete all copies of the .pfx file after importing
5. Create a Certificate template for OpenVPN client computers:
- First, create a Security group on your domain controller, for OpenVPN computers
- On your AD CS Server, open the Certifate Templates console
- Duplicate the "Workstation Authentication" template, and go through the properties tabs:
- 'General' Tab: give it a name, set its validity period to something short (I use 3 months / 1 month renewal period)
- 'Request Handling' tab: Shouldn't have to change anything here, but make sure that 'Allow private key to be exported' is NOT checked
- 'Subject Name' tab: make sure 'Build from this Active Directory information' is selected. Set subject name format to 'Fully distinguished name'. Leave 'include email name' unchecked.
- 'Extensions' tab: select 'Application Policies', click edit, add, and select 'IP security end system', click OK
- 'Security' tab: Add your OpenVPN computers SG , with Read, Enroll, and Autoenroll permissons. For tighter security, remove Enroll permissions from all other users/groups
- Hit apply / OK, then go to Certification Authority -> right click on 'Certificate Templates' -> New -> Certificate Template to issue, select your template, and click OK.
6. Create an OpenVPN server on your pfSense. Any unspecified settings can be left as default or changed as you see fit:
- Server mode: Remote Access (SSL/TLS)
- Use a TLS key: checked (copy and paste this key into static.key)
- Peer Certificate Authority: The AD CA that you imported
- OCSP Check: checked
- OCSP URL: the url to your OCSP server (http://your.server/ocsp)
- Server Certificate: the server certificate you imported
- Enforce Key Usage: checked
- DNS Default Domain: your AD domain
- DNS Server enable: checked
- DNS Server 1/2/etc: your AD DNS servers
- Block outside DNS: checked (this is a good way to ensure remote users have the same degree of DNS protection that users in the office have)
- Force DNS cache update: checked
- Custom options: "remote-cert-eku 1.3.6.1.5.5.7.3.5" (without the quotes. This OID corresponds with the 'IP security end system' application policy we added to the client cert template above)
- Gateway creation: IPv4 only
- Verbosity level: default (turn up to 4 if you need to troubleshoot)
7. Configure appropriate firewall rules. (You can use a package like pfBlocker to limit access to specific countries)
8. Edit $conf in oVPN_setup.ps1, filling in your openVPN servers address/port info, Cert / CA info, business hours, and an AD group for 24x7 access
9. Copy the contents of the corpvpn folder to c:\programdata\corpvpn
10. Install OpenVPN client on end user computer
11. run oVPN_setup.ps1

## Config files
### corpvpn\config_params.json
- Auto-generated by the setup script, used by all scheduled scripts
- Contains server address / port info, certificate / CA info, anything specific to your setup
- Customize oVPN_setup.ps1 to change these settings

## Scripts:
### OpenVPN config generation script
#### Description
- the ps1 script reads config.ovpn.template, and generates a new OpenVPN config, using the contents of config_params.json + static.key. 
- It needs to rerun periodically to ensure the current certificate in use.
#### Components
- corpvpn\generate_ovpn_config.ps1
- corpvpn\config.ovpn.template
- corpvpn\static.key
#### Scheduled task
- Monthly

### Network check on interface up script
#### Description
- Script is triggerred via scheduled task, whenever a network interface goes up, to check if the computer is currently connected to the office network or not.
- If the network name matches the the computers domain, then the vpn is disabled. If not, then its enabled
- The XML file is the task itself, which is imported via schtasks.exe
#### Components
- corpvpn\ifup.ps1
- corpvpn\ifup_task.xml
#### Scheduled task
- On windows event: Microsoft-Windows-NetworkProfile/Operational, event id 10000

### Office hours enforcement script
#### Description
- The script checks the time, and disables the VPN service if outside of office hours + the user is not a domain admin / part of the 24x7 group
#### Components
- enforce_office_hours.ps1
- enforce_on_unlock_task.xml
#### Scheduled tasks
- At start and end times specified in oVPN_setup.ps1
- on computer unlock/account session connection
