# Limit pfSense OpenVPN users' connnections to a schedule!
### Actively disconnect them when off hours.

## Howto
- Install the cron package on your pfsense
- Put vpn-users.php in a directory in your pfsense (I used /root/vpn/)
- Create a users.txt file, and list the users who should be time limited
- Add cron jobs to run vpn-users.php at the start and end times
- create as many user lists and cron jobs as you want, to create different time frames for different users

## Notes
- This document sucks, I know. ask me questions and I will update it
- This should work with any type if user - local, ldap, radius. If pfSense can see the username, then this script can kick them.
- external users will also need their logon hours configured in AD, via 'login hours'
- umm I need to add external user handling to vpn-users.php, so it doesn't try to disable a local user that doesn't exist

