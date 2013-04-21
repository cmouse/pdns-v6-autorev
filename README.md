PowerDNS Automatic Autoreverse generator
========================================

Required software
-----------------
You'll need following perl modules for this software to work
 - JSON::Any 
 - JSON::XS,JSON::DWIW or JSON
 - DBI
 - DBD::mysql or DBD::sqlite

For debian users

    apt-get install libjson-any-perl libjson-xs-perl libdbi-perl
    
MySQL
    apt-get install libdbd-mysql-perl
    
SQLite3
    apt-get install libdbd-sqlite3-perl

PowerDNS configuration
----------------------
NB! This script will not work if you do not use newer than 3.2 version due to remotebackend bugfixes 
that are not included here. You'll need to apply following tickets to fix things before this works for 3.2: 
 - http://wiki.powerdns.com/trac/ticket/740
 - http://wiki.powerdns.com/trac/ticket/697

or you can use the remotebackend from PowerDNS SVN. 

Use the following configuration in powerdns config file for mysql

    launch=remote,gmysql
    remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:mysql:database,username=user,password=pass
    remote-dnssec=yes/no # depending your choice

Use the following configuration in powerdns config file for sqlite
    launch=remote,gsqlite3
    remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:SQLite:dbname=/path/to/db,username=user,password=pass
    remote-dnssec=yes/no # depending your choice


pipe backend is recommended. if you want to use unix or http, you need to do extra work.

If you want to change the default prefix 'node' into something else, add prefix=something in the connection string.

Configuring zones
-----------------

To enable autorev feature for zones, you'll need a reverse and forward zone. Add into domain metadata following entries

for forward zone

    AUTODNS, id-of-reverse-zone

for reverse zone

    AUTODNS, id-of-forward-zone

The script uses this information to pick up your forward and reverse zones and serve them via the script. 

If you want to configure per-domain prefix for the value, use AUTOPRE key for this.

WARNING: Rectify-zone is not currently supported thru the script, so you need to either disable dnssec,
or run rectify-zone thru gmysql

DNSSEC
------

To enable DNSSEC you need to first run secure-zone and then set-nsec3 with narrow. ONly NSEC3 narrow is supported. 

Support
-------

Please file a ticket in github for any support issues.
