PowerDNS Automatic Autoreverse generator for IPv6 addresses
===========================================================

Required software
-----------------
You'll need following perl modules for this software to work
 - JSON::Any 
 - JSON::XS,JSON::DWIW or JSON
 - DBI
 - DBD::mysql, DBD::sqlite or DBD::Pg

For debian users

    apt-get install libjson-any-perl libjson-xs-perl libdbi-perl
    
MySQL

    apt-get install libdbd-mysql-perl
    
SQLite3

    apt-get install libdbd-sqlite3-perl
    
PostgreSQL

    apt-get install libdbd-pg-perl

PowerDNS configuration
----------------------
Minimum required version of PowerDNS is 3.3.

Make sure your schema has been upgraded, as this script expects your schema to conform with the one recommended for 3.3.
You should have 'auth' field in records table, and domainmetadata table present. The auth field is only required to be present, if you enable DNSSEC support, otherwise the value is ignored. 

Use the following configuration in powerdns config file for mysql

    launch=remote,gmysql
    remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:mysql:database,username=user,password=pass
    remote-dnssec=yes/no # depending on your choice

Use the following configuration in powerdns config file for sqlite

    launch=remote,gsqlite3
    remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:SQLite:dbname=/path/to/db,username=user,password=pass
    remote-dnssec=yes/no # depending on your choice

Use the following configuration in powerdns config file for postgresql

    launch=remote,gpgsql
    remote-connection-string=pipe:command=/path/to/rev.pl,timeout=2000,dsn=DBI:Pg:dbname=database;host=127.0.0.1;port=5432,username=user,password=pass
    remote-dnssec=yes/no # depending on your choice

pipe backend is recommended. if you want to use unix or http, you need to do extra work. For unix connector mode it is possibly enough to use socat. 

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
or run rectify-zone thru gmysql (or gsqlite3/gpgsql).

DNSSEC
------

To enable DNSSEC you need to first run secure-zone and then set-nsec3 with narrow. Only NSEC3 narrow is supported for forward zones, you can use NSEC/NSEC3 non-narrow for reverse
zones.  

Support
-------

Please file a ticket in github for any support issues.
