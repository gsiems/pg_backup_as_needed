#!/usr/bin/env perl
=head1 Synopsis

pg_backup -- selectively backup a postgresql database cluster

=head1 Description

Perform backups (pg_dump*) of postgresql databases in a cluster on an
as needed basis.

For some database clusters, there may be databases that are:

 a. rarely updated/changed and therefore shouldn't require dumping as
    often as those databases that are frequently changed/updated.

 b. are large enough that dumping them without need is undesirable.

The global data is always dumped without regard to whether any
individual databases need backing up or not.

=head1 Usage

pg_backup [OPTION]...

General options:

  -F, --format=c|t|p    output file format for data dumps
                          (custom, tar, plain text) (default is custom)
  -a, --all             backup (pg_dump) all databases in the cluster
                          (default is to only pg_dump databases that have
                          changed since the last backup)
  --backup-dir          directory to place backup files in
                          (default is ./backups)
  -v, --verbose         verbose mode
  --help                show this help, then exit

Connection options:

  -h, --host=HOSTNAME   database server host or socket directory
  -p, --port=PORT       database server port number
  -U, --username=NAME   connect as specified database user
  -d, --database=NAME   connect to database name for global data

=head1 Notes

This utility has been developed against PostgreSQL version 8.4.x. Older
versions of PostgreSQL may not work.

`vacuum` does not appear to trigger a backup unless there is actually
something to vacuum whereas `vacuum analyze` appears to always trigger a
backup.

=head1 Copyright and License

Copyright (C) 2011 by Gregory Siems

This library is free software; you can redistribute it and/or modify it
under the same terms as PostgreSQL itself, either PostgreSQL version
8.4 or, at your option, any later version of PostgreSQL you may have
available.

=cut

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use POSIX qw(strftime);

my %opts = get_options();

my $connect_options = '';
$connect_options .= "--$_=$opts{$_} " for (qw(username host port));

my $shared_dump_args = ($opts{verbose})
    ? $connect_options . ' --verbose '
    : $connect_options;

my $backup_prefix = (exists $opts{host} && $opts{host} ne 'localhost')
    ? $opts{backup_dir} . '/' . $opts{host} . '-'
    : $opts{backup_dir} . '/';

do_main();


########################################################################
sub do_main {
    backup_globals();

    my $last_stats_file = $backup_prefix . 'last_stats';

    # get the previous pg_stat_database data
    my %last_stats;
    if ( -f $last_stats_file) {
        %last_stats = parse_stats (split "\n", slurp_file ($last_stats_file));
    }

    # get the current pg_stat_database data
    my $cmd = 'psql ' . $connect_options;
    $cmd .= " $opts{database} " if (exists $opts{database});
    $cmd .= "-Atc \"
        select date_trunc('minute', now()), datid, datname,
            xact_commit, tup_inserted, tup_updated, tup_deleted
        from pg_stat_database
        where datname not in ('template0','template1','postgres'); \"";
    $cmd =~ s/\ns+/ /g;
    my @stats = `$cmd`;
    my %curr_stats = parse_stats (@stats);

    # do a backup if needed
    foreach my $datname (sort keys %curr_stats) {
        my $needs_backup = 0;
        if ($opts{all}) {
            $needs_backup = 1;
        }
        elsif ( ! exists $last_stats{$datname} ) {
            $needs_backup = 1;
            warn "no last stats for $datname\n" if ($opts{debug});
        }
        else {
            for (qw (tup_inserted tup_updated tup_deleted)) {
                if ($last_stats{$datname}{$_} != $curr_stats{$datname}{$_}) {
                    $needs_backup = 1;
                    warn "$_ stats do not match for $datname\n" if ($opts{debug});
                }
            }
        }
        if ($needs_backup) {
            backup_db ($datname);
        }
        else {
            chitchat ("Database \"$datname\" does not currently require backing up.");
        }
    }

    # update the pg_stat_database data
    open my $fh, '>', $last_stats_file || die "Could not open $last_stats_file for output. !$\n";
    print $fh @stats;
    close $fh;
}

sub parse_stats {
    my @in = @_;
    my %stats;
    chomp @in;
    foreach my $line (@in) {
        my @ary = split /\|/, $line;
        my $datname = $ary[2];
        next unless ($datname);
        foreach my $key (qw(tmsp datid datname xact_commit tup_inserted tup_updated tup_deleted)) {
            my $val = shift @ary;
            $stats{$datname}{$key} = $val;
        }
    }
    return %stats;
}

sub backup_globals {
    chitchat ("Backing up the global data.");

    my $backup_file = $backup_prefix . 'globals-only.backup.gz';
    my $cmd = 'pg_dumpall --globals-only ' . $shared_dump_args;
    $cmd .= " --database=$opts{database} " if (exists $opts{database});

    do_dump ($backup_file, "$cmd | gzip");
}

sub backup_db {
    my $database = shift;
    chitchat ("Backing up database \"$database\".");

    my $backup_file = $backup_prefix . $database . '-schema-only.backup.gz';
    do_dump ($backup_file, "pg_dump --schema-only --create --format=plain $shared_dump_args $database | gzip");

    $backup_file = $backup_prefix . $database . '.backup';
    do_dump ($backup_file, "pg_dump --format=". $opts{format} . " $shared_dump_args $database");
}

sub do_dump {
    my ($backup_file, $cmd) = @_;

    my $temp_file = $backup_file . '.new';
    warn "Command is: $cmd > $temp_file" if ($opts{debug});

    chitchat (`$cmd > $temp_file`);
    if ( -f $temp_file ) {
        chitchat (`mv $temp_file $backup_file`);
    }
}

sub chitchat {
    my @ary = @_;
    return unless (@ary);
    chomp @ary;
    my $first   = shift @ary;
    my $now     = strftime "%Y%m%d-%H:%M:%S", localtime;
    print +(join "\n                  ", "$now $first", @ary), "\n";
}

sub get_options {
    Getopt::Long::Configure('bundling');

    my %opts = ();
    GetOptions(
        "a"             => \$opts{all},
        "all"           => \$opts{all},
        "p=s"           => \$opts{port},
        "port=s"        => \$opts{port},
        "U=s"           => \$opts{username},
        "username=s"    => \$opts{username},
        "h=s"           => \$opts{host},
        "host=s"        => \$opts{host},
        "F=s"           => \$opts{format},
        "format=s"      => \$opts{format},
        "d=s"           => \$opts{database},
        "database=s"    => \$opts{database},
        "backup-dir=s"  => \$opts{backup_dir},
        "help"          => \$opts{help},
        "v"             => \$opts{verbose},
        "verbose"       => \$opts{verbose},
        "debug"         => \$opts{debug},
        );

    # Does the user need help?
    if ($opts{help}) {
        show_help();
    }

    $opts{host}         ||= $ENV{PGHOSTADDR} || $ENV{PGHOST}     || 'localhost';
    $opts{port}         ||= $ENV{PGPORT}     || '5432';
    $opts{host}         ||= $ENV{PGHOST}     || 'localhost';
    $opts{username}     ||= $ENV{PGUSER}     || $ENV{USER}       || 'postgres';
    $opts{database}     ||= $ENV{PGDATABASE} || $opts{username};
    $opts{backup_dir}   ||= './backups';

    my %formats = (
        c       => 'custom',
        custom  => 'custom',
        t       => 'tar',
        tar     => 'tar',
        p       => 'plain',
        plain   => 'plain',
    );
    $opts{format} = (defined $opts{format})
        ? $formats{$opts{format}} || 'custom'
        : 'custom';

    warn Dumper \%opts if ($opts{debug});
    return %opts;
}

sub show_help {
    print `perldoc -F $0`;
    exit;
}

sub slurp_file { local (*ARGV, $/); @ARGV = shift; <> }

__END__
