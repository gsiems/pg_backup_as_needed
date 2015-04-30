# pg_backup_as_needed
## Synopsis

pg_backup -- selectively backup a PostgreSQL database cluster

## Description

Perform backups (pg_dump*) of PostgreSQL databases in a cluster on an
as needed basis.

For some database clusters, there may be databases that are:

 * rarely updated/changed and therefore shouldn't require dumping as
    often as those databases that are frequently changed/updated.

 * are large enough that dumping them without need is undesirable.

The global data is always dumped without regard to whether any
individual databases need backing up or not.

## Usage

pg_backup [OPTION]...

General options:

    -F, --format=c|t|p    output file format for data dumps
                            (custom, tar, plain text)
                            (the default is custom)
    -a, --all             backup (pg_dump) all databases in the cluster
                            (the default is to only pg_dump databases
                            that have changed since the last backup)
    --backup-dir          directory to place backup files in
                            (the default is ./backups)
    -v, --verbose         verbose mode
    --help                show this help, then exit

Connection options:

    -h, --host=HOSTNAME   database server host or socket directory
    -p, --port=PORT       database server port number
    -U, --username=NAME   connect as specified database user
    -d, --database=NAME   connect to database name for global data

## Notes

This utility has been developed against PostgreSQL version 8.4.x. Older
versions of PostgreSQL may not work.

`vacuum` does not appear to trigger a backup unless there is actually
something to vacuum whereas `vacuum analyze` appears to always trigger a
backup.

## Copyright and License

Copyright (C) 2011 by Gregory Siems

This library is free software; you can redistribute it and/or modify it
under the same terms as PostgreSQL itself, either PostgreSQL version
8.4 or, at your option, any later version of PostgreSQL you may have
available.
