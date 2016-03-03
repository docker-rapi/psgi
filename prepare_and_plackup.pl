#!/usr/bin/perl

use strict;
use warnings;

if(! -f 'app.psgi') {
  die "Error: No app.psgi file found; nothing to plackup.\n";
}

# If cpanfile is found, try to install missing deps before plackup:
if(-f 'cpanfile') {
  print "\nProcessing cpanfile...\n";
  my $cmd = 'cpanm --installdeps .';
  print "  -> $cmd\n";
  qx|$cmd 1>&2|;
  if(my $exit = $? >> 8) {
    die "\n\nError: command `$cmd` non-zero exit code ($exit) -- bailing out.\n";
  }
}

exec(qw/start_server --port=5000 -- plackup -s Gazelle/);
