# OpenVPN AD integration
### AD user integrated VPN using ADCS-issued certificates

AD user integrated VPN for domain computers, with optional time-of-day limits. Intended to be used with OpenVPN on a pfSense firewall.
Time limit scripts are separate, and run via cron jobs on the firewall. As of now I have only tested the scripts with local users. It should kick off AD (LDAP or RADIUS) users, but will be unable to disable them. AD users should have their logon hours configured via AD.

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

### Firewall certificate
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
- the new certificate will be listed in Comptuter certificates \ personal \ certificates. Right click on it -> All tasks -> Export
- Yes export the private key -> next
- check 'export all extended properties' (may not be necessary for this one?) -> next
- check 'password', put in a password twice, set encryption to SHA256 -> next
- specify a path -> next -> finish

### CA Certificate
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

### Client Certificate template
5. Create a Certificate template for OpenVPN users:
- First, create a Security group on your domain controller, for OpenVPN users
- On your AD CS Server, open the Certifate Templates console
- Duplicate the "Workstation Authentication" template, and go through the properties tabs:
- 'General' Tab: give it a name, set its validity period to something short (I use 3 months / 1 month renewal period)
- 'Request Handling' tab: Shouldn't have to change anything here, but make sure that 'Allow private key to be exported' is NOT checked
- 'Subject Name' tab: make sure 'Build from this Active Directory information' is selected. Set subject name format to 'Fully distinguished name' or 'Common name'. Leave 'include email name' unchecked.
- 'Security' tab: Add your OpenVPN users group, with Read, Enroll, and Autoenroll permissons. For tighter security, remove Enroll permissions from all other users/groups. You can also just allow all domain users to autoenroll, and then limit logins to members of your group, via the firewalls LDAP configuration
- Hit apply / OK, then go to Certification Authority -> right click on 'Certificate Templates' -> New -> Certificate Template to issue, select your template, and click OK.

### pfSense OpenVPN server
6. Create an OpenVPN server on your pfSense. Any unspecified settings can be left as default or changed as you see fit:
- Server mode: Remote Access (SSL/TLS + user auth)
- Backend for authentication: Your LDAP or RADIUS server (I'll document LDAPS setup separately)
- Use a TLS key: checked (copy and paste this key into static.key)
- Peer Certificate Authority: The AD CA that you imported
- OCSP Check: checked
- OCSP URL: the url to your OCSP server (http://your.server/ocsp) ** if implementing ldap via a DNS record to multiple DCs, it could be used for OSCP as well
- Server Certificate: the server certificate you imported
- Enforce Key Usage: checked
- DNS Default Domain: your AD domain
- DNS Server enable: checked
- DNS Server 1/2/etc: your AD DNS servers
- Block outside DNS: checked (this is a good way to ensure remote users have the same degree of DNS protection that users in the office have)
- Force DNS cache update: checked
- Gateway creation: IPv4 only
- Verbosity level: default (turn up to 4 if you need to troubleshoot)
7. Configure appropriate firewall rules. (You can use a package like pfBlocker to limit access to specific countries)

### OpenVPN client deployment
- Run openvpn-create-profile-monolithic.ps1 on any domain-joined computers

## Config files
### corpvpn\config_params.json
- Auto-generated by the monolithic setup script, used by all scheduled scripts
- Contains server address / port info, certificate / CA info, anything specific to your setup

## Scripts:
### OpenVPN config generation script
#### Description
- the ps1 script reads config.ovpn.template, and generates a new OpenVPN config, using the contents of config_params.json + static.key. 
- The deployment script automatically writes all the below files and configures the generator script to run on every time the current user logs in

#### Components
- corpvpn\generate_ovpn_config.ps1
- corpvpn\config.ovpn.template
- corpvpn\static.key

#### Scheduled task
- on Login of the current user, run generate_ovpn_config.ps1
