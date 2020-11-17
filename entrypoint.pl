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

-f '/common_env.pl' and require '/common_env.pl';

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
