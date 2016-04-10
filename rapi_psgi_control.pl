#!/usr/bin/env perl

use strict;
use warnings;

use Path::Class qw/file dir/;
use Time::HiRes qw/usleep/;

$| = 1;

my @exit_sigs = qw/INT KILL TERM QUIT/;

BEGIN {
  # Prevent the script from being ran by accident:
  die "This script can only be run via the rapi/psgi docker image.\n"
    unless($ENV{RAPI_PSGI_DOCKERIZED}); # Set in the rapi/psgi Dockerfile
    
  for my $sig (@exit_sigs) {
    $SIG{$sig} = sub {
      print "\n\n  [caught SIG$sig -- aborting startup]\n\n";
      exit;
    } 
  }
}

my $pid_file     = '/_app.pid';
my $status_file  = '/_app.status';
my $stop_file    = file('/_app.stopped');
my $init_file    = file('/_app.initialized');

my $start_server = "start_server --pid-file $pid_file --status-file $status_file";
my @start = split(/\s+/,$start_server);

my $bin_name = (reverse split(/\//,$0))[0];

if($bin_name eq 'via-git') {
  die "$bin_name cannot be ran in an existing container" if (-f $init_file);

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
elsif($bin_name eq 'app-restart') {
  if(-f $stop_file) {
    print "App is stopped -- attempting start back up ...";
    $stop_file->remove;
    usleep(250*1000) and print '.' until(-f $pid_file); # 250 ms
    my $pid = file($pid_file)->slurp;
    chomp($pid);
    print " started [pid: $pid]\n";
    exit;
  }

  -f $pid_file or die "app hasn't been started yet (no $pid_file)\n";
  exec @start => '--restart';
}
elsif($bin_name eq 'stop-app') {
  -f $pid_file or die "app hasn't been started yet (no $pid_file)\n";
  $stop_file->touch;
  exec @start => '--stop';
}

if($bin_name eq 'init-stopped') {
  die "$bin_name cannot be ran in an existing container" if (-f $init_file);
  $stop_file->touch;
}
else {
  $stop_file->remove if (-f $stop_file);
}

&_normal_init;


if(! -f 'app.psgi' && ! $ENV{RAPI_PSGI_START_SERVER_COMMAND}) {
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

$ENV{RAPI_PSGI_PORT} ||= 5000;
$ENV{RAPI_PSGI_START_SERVER_COMMAND} ||= 'plackup -s Gazelle';
my @server_cmd = split(/\s+/,$ENV{RAPI_PSGI_START_SERVER_COMMAND});


if($bin_name eq 'init-stopped' && -f $stop_file) {
  my $name = $ENV{HOSTNAME} || 'some-name';
  
  print join("\n",'','',
    " ** container has been started, but the app has not **",'',
    "run 'app-restart' with docker exec from the host to start the app...",
    "for example, if you started this container with '--name $name' - run:",'','',
    "   docker exec $name app-restart",'',''
  );
}

while(1) {

  unless(-f $stop_file) {
    if(my $pid = fork) {
      local $SIG = $SIG;
    
      for my $sig (@exit_sigs) {
        $SIG{$sig} = sub {
          print "\n\n  [caught SIG$sig -- shutting down]\n\n";
          kill $sig => $pid;
          waitpid( $pid, 0 );
          exit;
        } 
      }
      
      $SIG{HUP} = sub {
        if (-f $stop_file) {
           print "\n\n  [got SIGHUP while app stopped, allow start]\n\n";
           $stop_file->remove();
        }
        else {
          print "\n\n  [got SIGHUP, passing to superdaemon]\n\n";
          kill HUP => $pid;
        }
      };
    
      waitpid( $pid, 0 );
    }
    else {
      exec @start => '--port', $ENV{RAPI_PSGI_PORT}, '--', @server_cmd;
    }
  }
  sleep 2;
}

####

sub _workdir_is_empty {
  my @glob = grep { $_ ne '.' && $_ ne '..' } glob(".* *");
  scalar(@glob) == 0
}

sub _normal_init {

  die "$bin_name cannot be ran in an existing container" if (-f $init_file);
  
  $init_file->touch;

  my $have = $ENV{RAPI_PSGI_IMAGE_VERSION};
  my $need = $ENV{RAPI_PSGI_MIN_VERSION};

  print " ** rapi/psgi:$have based docker container starting [$ENV{HOSTNAME}] **\n" if ($have);

  die join("\n",'',
    "Error: rapi/psgi:$need required (RAPI_PSGI_MIN_VERSION is set)",'',
    "To automatically download the latest version:",'',
    '   docker pull rapi/psgi','',
    'Note: you will also need to recreate the container and/or rebuild downstream image(s)','',''
  ) if ($have && $need && "$need" gt "$have");
  
  if(my $tz = $ENV{RAPI_PSGI_SET_SYSTEM_TIMEZONE}) {
    my $zonefile = file('/usr/share/zoneinfo/',$tz);
    -f $zonefile or die "Bad RAPI_PSGI_SET_SYSTEM_TIMEZONE '$tz' ($zonefile not found)\n";
    
    my $lt = file('/etc/localtime');
    $lt->remove if (-e $lt);
    
    print "Setting system timezone (RAPI_PSGI_SET_SYSTEM_TIMEZONE is set):\n";
    my $cmd = "ln -sf $zonefile $lt";
    qx|$cmd|;
    if(my $exit = $? >> 8) {
      die "\nError: command `$cmd` non-zero exit code ($exit) -- bailing out.\n";
    }
    print " $lt -> $zonefile\n";
  
  }
  
}
