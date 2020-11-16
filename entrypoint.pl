#!/usr/bin/env perl

#
# This script is designed to wrap any/all commands called through docker for proper 
# signal handling so when we hit 'Ctrl-C' it will do what we want, and also obey 
# docker stop commands, etc. This is being done to overcome some PID 1 limitations
#

use strict;
use warnings;

use POSIX ":sys_wait_h";
use Time::HiRes qw(sleep);

use List::Util;
use Path::Class qw/file dir/;
use Module::Runtime;

$| = 1;
my $is_kill = 0;

&_maybe_use_dev_perllibs;
&_maybe_use_dev_rapidapp;

# Simple exec to the main script when there are no args
exec "/rapi_psgi_control.pl" unless (scalar(@ARGV) > 0);

# Also exec directly if this is a subcommand of rapi_psgi_control.pl
exec(@ARGV) if (-l "/bin/$ARGV[0]" && readlink("/bin/$ARGV[0]") =~ /\/rapi_psgi_control.pl$/);

# Its some other command, fork/exec
if(my $kid = fork) {
  # This is the parent, setup signal handlers and wait for the child to exit
  &_set_handler($_,$kid) for qw/INT TERM QUIT ABRT/;
  waitpid($kid,0);
  print "ended\n" if $is_kill;
}
else {
  # This is the child - exec the argument list
  exec @ARGV
}

##################################################################
##################################################################

sub _set_handler {
  my ($sig, $kid) = @_;
  $SIG{$sig} = sub {
    $is_kill = 1;
    print STDERR "\n\n  ***** CAUGHT SIG$sig *****  \n\n";
    
    unless($sig eq 'TERM') {
      print STDERR "Sending $sig to child...";
      kill $sig => $kid;
    }
    
    sleep(0.6);
    if(&_still_runs($kid)) {
      print STDERR "\nSending TERM to child...";
      kill TERM => $kid;
      
      sleep(0.6);
       if(&_still_runs($kid)) {
        print STDERR "\nSending KILL to child...";
        kill 9 => $kid;
      }
    }
  }
}


sub _still_runs {
  my $kid = shift;
  waitpid($kid, WNOHANG) ? 0 : 1
}

sub _maybe_use_dev_perllibs {
  # This is a special mode for development
  my $libs_dir = dir('/opt/dev/perllib');
  &_recurse_include_next_lib_dir($libs_dir) if (-d $libs_dir);
}

sub _recurse_include_next_lib_dir {
  my $dir = shift or return;
  return unless ref($dir) && $dir->is_dir && -d $dir;

  return if (
    $dir->basename eq 't'          # don't go into t/ test dirs:
    || ($dir->basename =~ /^\.+/)  # or 'hidden' dirs with names starting with '.'
  );
  
  # If we are a 'lib/' we do what we came to do and we're done:
  if($dir->basename eq 'lib') {
    my $lib = $dir->absolute;
    warn " --> including PERLLIB dir found at '$lib' <--\n";
    eval join('','use lib "',$lib,'"'); # <-- this doesn't really do anything
    $ENV{PERLLIB} = &_prepend_colon_list( $ENV{PERLLIB}, $lib->stringify ); # <-- this does
    
    # don't look for nested lib/ dirs
    return;
  }
  
  if(-d $dir->subdir('lib')) {
    # If there is a lib dir here at the first level, stop and process it only:
    &_recurse_include_next_lib_dir( $dir->subdir('lib') )
  }
  else {
    # Otherwise, recurse on down into sub-folders:
    &_recurse_include_next_lib_dir($_) for ($dir->children)
  }
}


sub _maybe_use_dev_rapidapp {
  # This is a special mode for development
  my $repo_dir = dir('/opt/dev/RapidApp');
  if(-d $repo_dir) {
    my ($lib,$script,$share) = map { $repo_dir->subdir($_) } qw/lib script share/;
    if(-d $lib && -d $script && -d $share && -f $lib->file('RapidApp.pm')) {
      warn " *** Found dev RapidApp repo mounted at '$repo_dir' ***\n";
      eval join('','use lib "',$lib,'"');
      Module::Runtime::require_module('RapidApp');
      my $ver = $RapidApp::VERSION or die "Error loading!";
      
      warn "     [ Active RapidApp version is now: $ver ]\n\n";
      
      %ENV = ( %ENV,
        PERLLIB => &_prepend_colon_list( $ENV{PERLLIB}, $lib->stringify ),
        PATH    => &_prepend_colon_list( $ENV{PATH},    $script->stringify ),
        RAPIDAPP_SHARE_DIR => $share->stringify
      );
    }
  }
}

sub _prepend_colon_list {
  my ($clist, $add) = @_;
  
  my @list = split(/:/,($clist||''));
  
  return ( List::Util::first { $_ eq $add } @list )
    ? $clist
    : join(':',$add,@list)
}
