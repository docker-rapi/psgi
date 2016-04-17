# rapi/psgi

This docker image can be used to run a PSGI application contained within a real 
directory on the host system that contains an ```app.psgi``` file. The image has 
perl and [RapidApp](http://rapi.io) pre-installed, but will by default install any additional, 
missing required packages from CPAN at runtime if a [cpanfile](https://metacpan.org/pod/cpanfile) is present 
in the app directory.

The application is started using the [start_server](https://metacpan.org/pod/start_server) superdaemon with sane default 
options which you can override if needed (see *Environment Variables* section below)

## Using this image:

### run interactively:

```bash
cd /path/to/psgi/app/
docker run --name=my-app --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi
```
&nbsp;

### running an app directly from a git repo

You can also run an app on-the-fly from a remote repository. This 
feature is mainly provided for the purposes of quick/easy testing. 
This is done by calling the special ```via-git``` command with a
valid repository URL argument. For example:

```bash
docker run --rm -it -p 5000:5000 rapi/psgi \
 via-git https://github.com/RapidApp/yn2015
```
&nbsp;
  
This mode simply clones the repo to ```/opt/app``` to start. The above 
example does not mount an external path on the volume, so the app
is stored and run from the container and not a path of the host system. 
You can still mount a volume on ```/opt/app``` if you want. For 
instance, this would leave the cloned repository on the host system:

```bash
mkdir yn2015
cd yn2015/
docker run --rm --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi \
 via-git https://github.com/RapidApp/yn2015
```
&nbsp;
  
The above is roughly equivalent to this:

```bash
git clone --recursive https://github.com/RapidApp/yn2015
cd yn2015/
docker run --rm --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi
```
&nbsp;
  
### running as a daemon

You can also create a persistent container to run as a daemon in the 
background. This is the suggested setup:

```bash
# Create a new, named container:
docker create \
  --name=my-cool-app \
  --hostname=my-cool-app \
  --interactive --tty \
  -p 5000:5000 \
  -v /path/to/MyCoolApp:/opt/app \
  --restart=always \
rapi/psgi

# Start:
docker start my-cool-app

# View the console output in real-time:
docker logs --follow my-cool-app
```
&nbsp;
  
### exec running containers

You can get to a shell for a running container like this:

```bash
docker exec -it my-cool-app bash
```
&nbsp;
  
#### app-restart

From within the shell of the running container, you can restart the app w/o needing
to restart the container itself by running the provided command:

```bash
app-restart
```
&nbsp;
  
You can also restart the app from the host system directly:

```bash
docker exec my-cool-app app-restart
```
&nbsp;
  
This uses the restart functionality provided by [start_server](https://metacpan.org/pod/start_server)
  
&nbsp;
#### stop-app

You can also stop the app, while keeping the container running, with ```stop-app```:

```bash
docker exec my-cool-app stop-app
```
&nbsp;
  
The app will start back up as soon as you run ```app-restart```

```bash
docker exec my-cool-app app-restart
```
&nbsp;
  
### init-stopped

You can also start the container (```docker run|create```) with the special ```init-stopped```
command to have the system wait for you to run ```app-restart``` to start-up the app for the
first time:

```bash
docker run -d --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
rapi/psgi init-stopped

docker exec my-cool-app app-restart
```
&nbsp;
  
Starting the container with the ```init-stopped``` command is essentially the same as starting
normally and then running ```stop-app```
  
&nbsp;
## Environment Variables

Several special environment variables can be set to control system behavior, and
others are set automatically to provide useful information to the application.
  
&nbsp;
### RAPI_PSGI_IGNORE_CPANFILE

Set ```RAPI_PSGI_IGNORE_CPANFILE``` to true to ignore the 
```cpanfile``` if it exists
  
&nbsp;
### RAPI_PSGI_CPAN_NOTEST

Set ```RAPI_PSGI_CPAN_NOTEST``` to true to install CPAN packages with
```cpanm -n``` to skip running tests when processing the ```cpanfile```
  
&nbsp;
### RAPI_PSGI_SET_SYSTEM_TIMEZONE

Set ```RAPI_PSGI_SET_SYSTEM_TIMEZONE``` to a valid timezone name to change the system
timezone. If this is not set, the timezone will be left as-is which defaults to UTC.
Name must be a valid path under ```/usr/share/zoneinfo/```

```bash
docker create --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
  -e RAPI_PSGI_SET_SYSTEM_TIMEZONE="America/New_York"
rapi/psgi
```
&nbsp;
  
### RAPI_PSGI_MIN_VERSION

Set this to a ```rapi/psgi``` tag/version string to require at least that version
in order to start-up.

```bash
docker create --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
  -e RAPI_PSGI_MIN_VERSION="1.1007" \
rapi/psgi
```
&nbsp;
  
Note: ```1.1007-C``` was the first version that this feature was enabled.
  
&nbsp;
### RAPI_PSGI_PORT

TCP port to listen to. Defaults to ```5000``` which you should only change if you
know what you are doing. To use a different port on the docker host, such as ```5432```,
use the ```-p|--port``` option in the ```docker run|create``` command:

```
 -p 5432:5000
```
&nbsp;
  
### RAPI_PSGI_START_SERVER_COMMAND

The command supplied to ```start_server``` (after ```--```). Defaults to ```plackup -s Gazelle```.

See the [start_server](https://metacpan.org/pod/start_server) documentation for more info.
  
&nbsp;
### RAPI_PSGI_BACKGROUND_URL

Optional url/path of the local app which will be called by the system automatically 
every ```RAPI_PSGI_BACKGROUND_FREQUENCY``` seconds. This provides a simple, in-line
way to have background code ran without needing to setup a separate ```cron```
or other task scheduling system.

For example, if your app had a controller action at ```/run_cron```, the following
would have it automatically called every 5 minutes:

```bash
docker create --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
  -e RAPI_PSGI_BACKGROUND_URL='/run_cron' \
  -e RAPI_PSGI_BACKGROUND_FREQUENCY=300 \
rapi/psgi
```
&nbsp;

Available since version ```1.1008```

&nbsp;
### RAPI_PSGI_BACKGROUND_FREQUENCY

How often (in seconds) the ```RAPI_PSGI_BACKGROUND_URL```, if set, should be called. 
Defaults to ```60``` (1 minute). 

Note: the system will not start a new background request if the previous one is still
running. See ```RAPI_PSGI_BACKGROUND_TIMEOUT``` below for the max time each request 
is allowed to run for.

&nbsp;
### RAPI_PSGI_BACKGROUND_TIMEOUT

Maximum time (in seconds) the background request to the ```RAPI_PSGI_BACKGROUND_URL```
is allowed to run before being stopped/killed. Only 1 request is allowed to be ran
at once, so if the previous request is still running, a new request won't be started
even if ```RAPI_PSGI_BACKGROUND_FREQUENCY``` has elapsed. 

Defaults to ```300``` (5 minutes)

&nbsp;
### CATALYST_DEBUG

Set ```CATALYST_DEBUG``` to true to enable verbose debug messages on the console.

This is not specific to ```rapi/psgi``` but to Catalyst/RapidApp in general.
  
&nbsp;
### DBIC_TRACE

Set ```DBIC_TRACE``` to true to enable dumping SQL statements on the console.

This is not specific to ```rapi/psgi``` but to DBIx::Class/RapidApp in general.
  
&nbsp;
### DBIC_TRACE_PROFILE

When ```DBIC_TRACE``` is enabled, set ```DBIC_TRACE_PROFILE=console``` for prettier
output of SQL statements.

This is not specific to ```rapi/psgi``` but to DBIx::Class/RapidApp in general.
  
&nbsp;
#### example

```bash
docker create --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
  -e RAPI_PSGI_IGNORE_CPANFILE=1 \
  -e RAPI_PSGI_MIN_VERSION="1.1007" \
  -e RAPI_PSGI_SET_SYSTEM_TIMEZONE="PST8PDT" \
  -e CATALYST_DEBUG=1 -e DBIC_TRACE=1 -e DBIC_TRACE_PROFILE=console \
rapi/psgi
```
&nbsp;
  
### RAPI_PSGI_IMAGE_VERSION

This is an informational variable which contains the version/tag of the ```rapi/psgi```
Docker Hub image
  
&nbsp;
### RAPI_PSGI_DOCKERIZED

This value is always true (1) and is used by internal scripts to prevent executing certain
code/commands outside the context of this image. You can also use this value in your
own code to do the same.

&nbsp;
## Misc

### docker-host

For convenience, the host name ```docker-host``` is automatically setup in ```/etc/hosts```
pointing to the IP address of the default gateway (which is the docker host system). This
allows apps to be able to reference ```docker-host``` and have it always mean the same
thing. This is useful for setups which used to reference ```localhost``` for services like
SMTP, etc. ```docker-host``` is the same concept, just always referencing the gateway.

Available since ```1.1008-A```

&nbsp;
### rapi-install-extras

Starting in version ```1.1008-B``` official 'extras' are now available but are not installed
to the base image, but can be installed in either a runniong container or a downstream image
by running the ```rapi-install-extras``` command. These are extra packages and commands which
I find useful (nmap, tcpdump, etc) but aren't pre-installed in order to save image space. The
list of extras changes with the image version just like the Dockerfile does
