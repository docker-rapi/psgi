#!/usr/local/bin/perl

use strict;
use warnings;

# Prevent the script from being ran by accident:
die "This script can only be run via the rapi/psgi docker image.\n"
  unless($ENV{RAPI_PSGI_DOCKERIZED}); # Set in the rapi/psgi Dockerfile

my $bin_name = (reverse split(/\//,$0))[0];

if($bin_name eq 'via-git') {
  my $url = $ARGV[0] or die "rapi/psgi via-git: mising repo URL argument\n";

  &_workdir_is_empty
    or die "rapi/psgi via-git: will not clone repo to non-empty app directory!\n";
    
  print "\n** Populating app dir from repo:";
  my $cmd = join(' ','git','clone','--recursive',$url,'./');
  print "  -> `$cmd`\n\n";
  qx|$cmd 1>&2|;
  if(my $exit = $? >> 8) {
    die "\nError: command `$cmd` non-zero exit code ($exit) -- bailing out.\n";
  }
}


if(! -f 'app.psgi') {
  &_workdir_is_empty 
    ? die 'app dir is empty (did you forget \'--volume=$(pwd):/opt/app\' in docker run command?)'."\n"
    : die "Error: No app.psgi file found; nothing to plackup.\n"
}

# If cpanfile is found, try to install missing deps before plackup:
if(-f 'cpanfile' && !$ENV{RAPI_PSGI_IGNORE_CPANFILE}) {
  print "\n** Processing cpanfile:";
  my $cmd = $ENV{RAPI_PSGI_CPAN_NOTEST} 
    ? 'cpanm -n --installdeps .'
    : 'cpanm --installdeps .';
  print "  -> `$cmd`\n\n";
  qx|$cmd 1>&2|;
  if(my $exit = $? >> 8) {
    print "\nError: command `$cmd` non-zero exit code ($exit) -- bailing out to shell...\n";
    exec('/bin/bash');
  }
}

exec(qw/start_server --port=5000 -- plackup -s Gazelle/);


####

sub _workdir_is_empty {
  my @glob = grep { $_ ne '.' && $_ ne '..' } glob(".* *");
  scalar(@glob) == 0
}