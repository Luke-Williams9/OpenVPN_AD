# Active Directory Certificate Services
Creating an AD CS is out of scope for this documentation.
.
.
..




JUST KIDDING!

I haven't fully documented it though. bear with me.

A lot of "AD-integrated-X" documentation likes to exclude creation of the AD CS infrastructure because there are so many variables that change depending on your organization and its needs, its just easier to tell people to figure it out themselves. And really, you should too. AD CA infrastructure is handy for a number of things in an AD environment, so its a good idea to get a handle on how it works. Below are links I've followed, as well as rough notes on how to get a basic single-root AD CA online.


## Links
### Stealthpuppy articles

1. Create an offline root CA:
https://stealthpuppy.com/deploy-enterprise-root-certificate-authority/

2. Create any number of subordinate CAs:
https://stealthpuppy.com/deploy-enterprise-subordinate-certificate-authority/


### Other articles
#### NDES config
https://www.petenetlive.com/KB/Article/0000947

https://techcommunity.microsoft.com/t5/ask-the-directory-services-team/enabling-cep-and-ces-for-enrolling-non-domain-joined-computers/ba-p/397821

#### Web enrollment
https://learn.microsoft.com/en-us/windows-server/identity/solution-guides/certificate-enrollment-certificate-key-based-renewal


## Rough Howto

Make sure you are part of the domain admins and enterprise admins groups.


### In the server manager:
Install all 6 AD CS roles if you want SCEM, or just AD CS if you don't.

Do post deployment configuration for only the CA - leave the others until later.
Create an Enterprise CA

In this case we will just create a root CA (in a bigger environment, its better to do an offline root ca and then create subordinate from it, as outlined in the Stealthpuppy articles)

Create new private key, use RSA#Microsoft Software key storage provider, SHA256, 2048 key length (or other settings)
Give the CA a name
Do a 5 or 10 year validity period
Use the default database / database log locations

Click next, confirm, and now the CA is created.


### To configure a certificate for enrollment:
- Open Certification Authority
- Right click on Certificate Templates -> Manage
- Certificate templates page will open
- Select a template to use, right click -> Duplicate
- Adjust settings accordingly
- Under security tab, add read/enroll/autoenroll features accordingly (usually per computer)
- Once the new template is saved, go back to Certification Authority
- Right click on Certificate Templates -> New -> Certificate template to issue
- Select the template

### Configure auto enrollment
#### Create or open a GPO in the GPO editor:
- Go to Computer config \ Policies \ Windows settings \ Security Settiogns \ Public Key Policies
- Click on Public Key policies -> enable Certificate Services client auto enrollment
- AD users or computers should now autoenroll certificates
- To manually trigger autoenrollment on a computer, run as adminstrator:
    gpupdate /force
    certutil -pulse

### Configure CEP / Web enrollment
This allows you to manually enroll certificates from the certificate manager
Useful for testing, and necessary for generating server certificates for firewall, phone system, etc
These notes are extra hairy, wow!

- Just use applicationidentity for the service user
- Issue a web certificate
- Run through CEP config in server manager

Go into IIS manager - default website -> ADPolicyprovier_CEP_kerberos -> Application settings
Give it a FriendlyName
Copy the URI if you need it
You may have to explicitly define it in GPO, see below

Also leave templates compatibility set to 2012r2 or below. Newer compatibility creates…. Wait for it…. Compatibility issues!
https://learn.microsoft.com/en-us/troubleshoot/windows-server/identity/cannot-select-windows-server-2016-ca-compatible-certificate-templates
Enrolmentpolicy server (for user?)


Enabled cert enrollment policies in GPO
https://docs.cyberark.com/Product-Doc/OnlineHelp/Idaptive/Latest/en/Content/CoreServices/Connector/UserComputerCerts.htm?TocPath=Administrator%7CConfigure%20MFA%7CManage%20AD%20certificates%20in%20devices%7C_____1



## Configure a CRL

Certifcation Authority -> Rightclick Revoked Certificates -> Properties -> Can change publication interval here
*** I've Set TG-CA to 1 hour for testing purposes ***



NDES - Web enrollment, good for macs  who may need a machine cert?
If configuring NDES / web features, stop and make an NDES service account and a web server certificate template first.

Create a domain user on the DC 
(not a domain admin)
Add it to the IIS_IUSRS group
Make sure the user has permissions to 'log on locally' and 'log on as a service' in any logon-limiting GPOs


Make a web server cert

Go into certificate templates console
Copy the Web server template
Give it a name
Go to security tab, add the AD CS server - read, enroll, autoenroll
Make sure Authenticated users have read permission
Go to Subject Name tab
Select (build from this ad information)
Subject name format: fully distinguished name
Compatibility tab
Change compatibility settings for both, to win10 / server 2016
Go back to Certifiacateion Authority
Right click on Certificate templates -> New Template to deploy…

Go into computer certmgr -> personal -> certificates
Right cligk -> all tasks -> request new certificate
Next Next - select DCM web server
Now you have a webserver certificate to use with cert web services / enrollment

Go back to configure role services
Check the other 5 service boxes

Service account -> enter the account you created previously
Type of authentication - user name and password (trying this for now, may need client cert auth instead)
If prompted to choose the certificate for web, choose the one you created
Otherwise change it later in IIS -> default web site -> bindings