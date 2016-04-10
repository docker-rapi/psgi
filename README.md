# rapi/psgi

This docker image can be used to run a PSGI application contained within a real 
directory on the host system that contains an ```app.psgi``` file. The image has 
perl and [RapidApp](http://rapi.io) pre-installed, but will by default install 
any additional, missing required packages from CPAN by at runtime if a ```cpanfile``` 
is present in the app directory.

The application is started using the [start_server](https://metacpan.org/pod/start_server)
superdaemon with sane default options which you can override if needed
(see [Environment Variables][Environment Variables] section below)

## Using this image:

### run interactively:

```bash
cd /path/to/psgi/app/
docker run --name=my-app --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi
```

### running an app directly from a git repo

You can also run an app on-the-fly from a remote repository. This 
feature is mainly provided for the purposes of quick/easy testing. 
This is done by calling the special ```via-git``` command with a
valid repository URL argument. For example:

```bash
docker run --rm -it -p 5000:5000 rapi/psgi \
 via-git https://github.com/RapidApp/yn2015
```

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

The above is roughly equivalent to this:

```bash
git clone --recursive https://github.com/RapidApp/yn2015
cd yn2015/
docker run --rm --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi
```

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

### exec running containers

You can get to a shell for a running container like this:

```bash
docker exec -it my-cool-app bash
```

#### app-restart

From within the shell of the running container, you can restart the app w/o needing
to restart the container itself by running the provided command:

```bash
app-restart
```

You can also restart the app from the host system directly:

```bash
docker exec my-cool-app app-restart
```

This uses the restart functionality provided by [start_server](https://metacpan.org/pod/start_server)

#### stop-app

You can also stop the app, while keeping the container running, with ```stop-app```:

```bash
docker exec my-cool-app stop-app
```

The app will start back up as soon as you run ```app-restart```

```bash
docker exec my-cool-app app-restart
```

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

Starting the container with the ```init-stopped``` command is essentially the same as starting
normally and then running ```stop-app```

## Environment Variables

Several special environment variables can be set to control system behavior, and
others are set automatically to provide useful information to the application.

### RAPI_PSGI_IGNORE_CPANFILE

Set ```RAPI_PSGI_IGNORE_CPANFILE``` to true to ignore the 
```cpanfile``` if it exists

### RAPI_PSGI_CPAN_NOTEST

Set ```RAPI_PSGI_CPAN_NOTEST``` to true to install CPAN packages with
```cpanm -n``` to skip running tests when processing the ```cpanfile```

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

### RAPI_PSGI_MIN_VERSION

Set this to a ```rapi/psgi``` tag/version string to require at least that version
in order to start-up.

```bash
docker create --name=my-cool-app -h my-cool-app \
  -it -p 5000:5000 -v /path/to/MyCoolApp:/opt/app \
  -e RAPI_PSGI_MIN_VERSION="1.1007" \
rapi/psgi
```

Note: ```1.1007-C``` was the first version that this feature was enabled.

### RAPI_PSGI_PORT

TCP port to listen to. Defaults to ```5000``` which you should only change if you
know what you are doing. To use a different port on the docker host, such as ```5432```,
use the ```-p|--port``` option in the ```docker run|create``` command:

```
 -p 5432:5000
```

### RAPI_PSGI_START_SERVER_COMMAND

The command supplied to ```start_server``` (after ```--```). Defaults to ```plackup -s Gazelle```.

See the [start_server](https://metacpan.org/pod/start_server) documentation for more info.

### CATALYST_DEBUG

Set ```CATALYST_DEBUG``` to true to enable verbose debug messages on the console.

This is not specific to ```rapi/psgi``` but to Catalyst/RapidApp in general.

### DBIC_TRACE

Set ```DBIC_TRACE``` to true to enable dumping SQL statements on the console.

This is not specific to ```rapi/psgi``` but to DBIx::Class/RapidApp in general.

### DBIC_TRACE_PROFILE

When ```DBIC_TRACE``` is enabled, set ```DBIC_TRACE_PROFILE=console``` for prettier
output of SQL statements.

This is not specific to ```rapi/psgi``` but to DBIx::Class/RapidApp in general.

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

### RAPI_PSGI_IMAGE_VERSION

This is an informational variable which contains the version/tag of the ```rapi/psgi```
Docker Hub image

### RAPI_PSGI_DOCKERIZED

This value is always true (1) and is used by internal scripts to prevent executing certain
code/commands outside the context of this image. You can also use this value in your
own code to do the same.
