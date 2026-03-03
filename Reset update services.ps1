net stop wuauserv
net stop cryptSvc
net stop bits
net stop msiserver

Rename-Item C:\Windows\SoftwareDistribution SoftwareDistribution.old
Rename-Item C:\Windows\System32\catroot2 catroot2.old

net start wuauserv
net start cryptSvc
net start bits
net start msiserver
