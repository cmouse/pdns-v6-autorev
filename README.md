PowerDNS Automatic Autoreverse generator
========================================

PowerDNS configuration
----------------------

launch=remote,gmysql
remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:mysql:database,username=user,password=pass
remote-dnssec=yes/no # depending your choice

pipe backend is recommended. if you want to use unix or http, you need to do extra work.

Configuring zones
-----------------

To enable autorev feature for zones, you'll need a reverse and forward zone. Add into domain metadata following entries

for forward zone

AUTODNS, id-of-reverse-zone

for reverse zone

AUTODNS, id-of-forward-zone

The script uses this information to pick up your forward and reverse zones and serve them via the script. 

WARNING: Rectify-zone is not currently supported thru the script, so you need to either disable dnssec, or run rectify-zone thru gmysql

DNSSEC
------

To enable DNSSEC you need to first run secure-zone and then set-nsec3 with narrow. ONly NSEC3 narrow is supported. 

Support
-------

Please file a ticket in github for any support issues.
