#!/usr/bin/env perl

use strict;
use warnings;

use Path::Class qw/file dir/;
use Time::HiRes qw/usleep/;
use POSIX ":sys_wait_h";
use RapidApp::Util ':all';
use List::Util;
use Log::Dispatch::FileRotate;

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
    usleep(250*1000) and print '.' until(-f $pid_file || -f $stop_file); # 250 ms
    if(-f $pid_file) {
      my $pid = file($pid_file)->slurp;
      chomp($pid);
      print " started [pid: $pid]\n";
    }
    else {
      # If the stop_file was re-created it means the app refused to start
      print "\nstart-up failed - check docker container logs for more info.\n";
    }
    exit;
  }

  -f $pid_file or die "app hasn't been started yet (no $pid_file)\n";
  
  # Calling this is sometimes leaving the app unable to communicate 
  # on the TCP port after the restart
  #exec @start => '--restart';
  
  # Instead, just call stop, but don't touch the $stop_file so the parent
  # will start it back up automatically
  print "App is running -- attempting to stop (will restart automatically)...\n";
  exec @start => '--stop';
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

$ENV{RAPI_PSGI_PORT} ||= 5000;
$ENV{RAPI_PSGI_WORKER_RESTART_RATE} ||= 10;

my $custom_start_cmd = $ENV{RAPI_PSGI_START_SERVER_COMMAND};
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

# Install a generic process reaper if we're PID 1
if ($$ == 1) {
  $SIG{CHLD} = sub { sleep(1) until waitpid(-1 , WNOHANG) == -1 };
}

my $BgReq = undef;
while(1) {

  $BgReq->DEMOLISH if ($BgReq);
  $BgReq = undef;

  unless(-f $stop_file) {
    if(my $pid = fork) {

      local $SIG = $SIG;
      
      $BgReq = Bg::Req->new;
    
      for my $sig (@exit_sigs) {
        $SIG{$sig} = sub {
          if($ENV{RAPI_PSGI_FAST_EXIT}) {
            print "\n\n  [rapi/psgi: caught SIG$sig, fast exiting -- RAPI_PSGI_FAST_EXIT is set]\n\n";
            exit;
          }
          print "\n\n  [rapi/psgi: caught SIG$sig -- shutting down]\n\n";
          $BgReq->DEMOLISH if ($BgReq);
          $BgReq = undef;
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
      &_exec_startup;
    }
  }
  sleep 2;
}

####

sub _exec_startup {

  print "\nStarting up app server...\n";

  if( &_pre_start() ) {
    exec @start => 
      '--port'     => $ENV{RAPI_PSGI_PORT},
      '--interval' => $ENV{RAPI_PSGI_WORKER_RESTART_RATE}, 
      '--'         => @server_cmd;
  }
  else {
    # If the pre-start failed, set the app to stopped
    $stop_file->touch;
    warn "\n ** app has not been started -- run 'app-restart' to start **\n\n";
  }
}

sub _pre_start {

  if(! -f 'app.psgi' && !$custom_start_cmd) {
    &_workdir_is_empty 
      ? warn 'app dir is empty (did you forget \'--volume=$(pwd):/opt/app\' in docker run command?)'."\n"
      : warn "Error: No app.psgi file found; nothing to plackup.\n";
      
    return 0;
  }
  
  # If cpanfile is found, try to install missing deps before plackup:
  if(-f 'cpanfile' && !$ENV{RAPI_PSGI_IGNORE_CPANFILE}) {
    print "\n** Processing cpanfile:";
    my $cmd = $ENV{RAPI_PSGI_CPAN_NOTEST} 
      ? 'cpanm -n --installdeps .'
      : 'cpanm --installdeps .';
    print "  -> `$cmd`\n\n";
    local $SIG{CHLD} = 'DEFAULT';
    qx|$cmd 1>&2|;
    if(my $exit = $? >> 8) {
      warn "\nError: command `$cmd` non-zero exit code ($exit) -- aborting start-up\n";
      return 0;
    }
  }
  
  return 1;
}


sub _workdir_is_empty {
  my @glob = grep { $_ ne '.' && $_ ne '..' } glob(".* *");
  scalar(@glob) == 0
}

sub _normal_init {

  local $SIG{CHLD} = 'DEFAULT';

  unlink $init_file if (-f $init_file && $$ == 1);
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
    
    # We also need to update the timezone file
    qx|echo "$tz" > /etc/timezone|;
  }
  
  &_add_docker_host_to_hosts;
}

sub _add_docker_host_to_hosts {
  my $hosts = file('/etc/hosts');
  for my $line (split(/\n/,(scalar $hosts->slurp))) {
    # Skip if there is already an entry:
    return if ($line =~ /\s+docker-host$/ || $line =~ /\s+docker-host\s+/)
  }
  
  my $routes = `ip route`;
  if(my $gw_line = List::Util::first { /^default via / } split(/\n/,$routes)) {
    if(my $ip = (split(/\s+/,$gw_line))[2]) {
      qx|echo "$ip docker-host" >> /etc/hosts|;
    }
  }
}



BEGIN {
  package Bg::Req;
  use Moo;
  use Types::Standard ':all';
  use RapidApp::Util ':all';
  
  use strict;
  use warnings;
  
  use Time::HiRes qw/gettimeofday tv_interval/;
  use LWP::UserAgent;
  use POSIX ":sys_wait_h";
  use Scalar::Util qw(looks_like_number);
  use Path::Class qw(file dir);
  use DateTime;
  
  # Auto start:
  sub BUILD { 
    my $self = shift;
    if ($self->url) {
      print join('',"** Setting up ",__PACKAGE__," for ",$self->url,"\n");
      $self->logger;
      $self->checkup;
    }
  }
  
  has 'url', is => 'ro', lazy => 1, default => sub {
    my $path = $ENV{RAPI_PSGI_BACKGROUND_URL} or return undef;
    $path =~ /^\// or die "Bad RAPI_PSGI_BACKGROUND_URL '$path' - must start with '/'";
    join('','http://localhost:',($ENV{RAPI_PSGI_PORT} ||= 5000),$path)
  };
  
  my $PosInt = sub { die "$_[0] is not a positive integer" unless($_[0] =~ /^\d+$/ && $_[0] > 0) };
  my %durs = (is => 'ro', isa => $PosInt, lazy => 1);
  has 'frequency', default => sub { $ENV{RAPI_PSGI_BACKGROUND_FREQUENCY} ||= 60  }, %durs;
  has 'timeout',   default => sub { $ENV{RAPI_PSGI_BACKGROUND_TIMEOUT}   ||= 300 }, %durs;
  
  has 'pid',        is => 'rw';
  has 'started_at', is => 'rw';
  
  has 'ua', is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    
    my $ua = LWP::UserAgent->new;
    $ua->timeout($self->timeout);
    $ua->agent("rapi-psgi/$ENV{RAPI_PSGI_IMAGE_VERSION}");
  
    $ua
  }, isa => InstanceOf['LWP::UserAgent'];
  
  has 'logger_opts', is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    my $ref = eval($ENV{RAPI_PSGI_BACKGROUND_LOG_OPTS} || '{}');
    ref($ref)||'' eq 'HASH' ? $ref : $ENV{RAPI_PSGI_BACKGROUND_LOG_OPTS}
  }, isa => HashRef;
  
  has 'logger', is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    $self->url or return undef;
    my $fn = $ENV{RAPI_PSGI_BACKGROUND_LOG} or return undef;
    
    # relative to app dir if not absolute
    $fn = "/opt/app/$fn" unless ($fn =~ /^\//);
    
    my $File = file($fn)->absolute;
    -d $File->parent || $File->parent->mkpath(1);
    
    Log::Dispatch::FileRotate->new(
      min_level => 'debug',
      name      => 'bgreq',
      filename  => $File->stringify,
      mode      => 'append' ,
      size      => 1024*1024*50,
      max       => 6,
      %{ $self->logger_opts }
    )
  
  }, isa => Maybe[InstanceOf['Log::Dispatch::FileRotate']];
  
  sub msg {
    my ($self, $msg, $level) = @_;
    print STDERR $msg;
    $self->logger and $self->logger->log( message => $msg, level => $level || 'info' );
  }
  
  sub allowed_to_run {
    my $self = shift;
    (! $self->{_is_child} && $self->url && ! -f $stop_file && -f $init_file)
  }
  
  sub running {
    my $self = shift;
    $self->pid or return 0;
    if (my $kid = waitpid($self->pid, WNOHANG)) {
      $self->pid(undef);
      return 0;
    }
    return 1;
  }
  
  sub stop {
    my $self = shift;
    $self->running or return 0;
    kill TERM => $self->pid;
    sleep(0.1) if $self->running;
    while($self->running) {
      kill 9 => $self->pid;
      sleep(0.1);
    }
    return 1
  }
  
  sub start {
    my $self = shift;
    $self->stop;
    
    return unless $self->allowed_to_run;
    
    $self->started_at([gettimeofday]);
    if(my $pid = fork) {
      $self->pid($pid);
      $self->checkup;
    }
    else {
      ## ****   CHILD THREAD   **** ##
      $self->{_is_child} = 1;
      eval { alarm(0); delete $SIG{ALRM}; };
      for my $sig (@exit_sigs) { $SIG{$sig} = sub { exit }; }
      
      my $pfx = join('',"++ ",(ref $self)," ($$) [",$self->url,']');
      
      $self->msg(join('',"\n",
        '[', DateTime->now( time_zone => 'local' )->strftime('%a, %d %b %Y %H:%M:%S %z'),']'
      )) if ($self->logger);
      
      $self->msg("\n$pfx --> GET REQUEST ... \n");
      
      my $response = $self->ua->get($self->url);
      
      $self->logger->log(
        level   => 'debug',
        message => join("",
          "RESPONSE - ",$response->status_line,
          ($response->is_success ? (' (',length($response->decoded_content),' bytes)') : ()),
          ' - ',$self->elapsed, ' seconds',
          "\n",
          ('-' x 50),"\n",
          $response->decoded_content,"\n",
          ('-' x 50),"\n"
      )) if ($self->logger);
      
      $self->msg(join('',$pfx,': ',$response->status_line,' (',$self->elapsed,'s)',"\n\n"));
        
      exit
      ## ************************** ##
    }
  }
  
  sub elapsed {
    my $self = shift;
    my $t0 = $self->started_at or return undef;
    sprintf('%.2f',tv_interval($t0))
  }
  
  sub due_in {
    my $self = shift;
    my $due_in = int($self->frequency - ($self->elapsed||0) + 0.5) || 0;
    $due_in > 1 ? $due_in : 2;
  }
  
  sub checkup {
    my $self = shift;
    $self->url or return undef;
    
    return if ($self->{_is_child});
    
    eval { alarm(0) };
    
    $self->stop if (
      $self->running &&
      $self->elapsed > $self->timeout
    );
    
    $self->start if (
      ! $self->running &&
      (! $self->elapsed || $self->elapsed > $self->frequency)
    );
    
    $self->stop unless ($self->allowed_to_run);
    
    $SIG{ALRM} = sub { $self->checkup };
    
    alarm( $self->due_in )
  }
  
  sub DEMOLISH {
    my $self = shift;
    return if ($self->{_is_child});
    eval { alarm(0); delete $SIG{ALRM} };
    $self->stop;
  }
  
  sub _debug_info {
    my $self = shift;
    my $meths = shift || [qw/pid started_at running elapsed allowed_to_run timeout due_in/];
    return { _self => $self, map { $_ => $self->$_ } sort @$meths }
  }
  
  my $fn = __PACKAGE__; $fn =~ s/::/\//g; $fn .= '.pm';
  $INC{$fn} = __FILE__;
  1;
}

