#!/usr/bin/perl

use strict;
use warnings;

# Prevent the script from being ran by accident:
die "This script can only be run via the rapi/psgi docker image.\n"
  unless($ENV{RAPI_PSGI_DOCKERIZED}); # Set in the rapi/psgi Dockerfile

if(! -f 'app.psgi') {
  die "Error: No app.psgi file found; nothing to plackup.\n";
}

# If cpanfile is found, try to install missing deps before plackup:
if(-f 'cpanfile') {
  print "\n** Processing cpanfile:";
  my $cmd = 'cpanm --installdeps .';
  print "  -> `$cmd`\n\n";
  qx|$cmd 1>&2|;
  if(my $exit = $? >> 8) {
    die "\nError: command `$cmd` non-zero exit code ($exit) -- bailing out.\n";
  }
}

exec(qw/start_server --port=5000 -- plackup -s Gazelle/);
