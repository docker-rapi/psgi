# rapi/psgi

This docker image can be used to run a PSGI application contained
within a real directory on the host system that contains an 
```app.psgi``` file. The image has perl and RapidApp pre-installed, 
but will install any other/additional required packages from CPAN 
at runtime if a ```cpanfile``` is present in the app directory 
(note this can be tweaked and turned off; see Environment Variables
section below).

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

## Environment Variables

### RAPI_PSGI_IGNORE_CPANFILE

Set ```RAPI_PSGI_IGNORE_CPANFILE``` to true to ignore the 
```cpanfile``` if it exists

### RAPI_PSGI_CPAN_NOTEST

Set ```RAPI_PSGI_CPAN_NOTEST``` to true to install CPAN packages with
```cpanm -n``` to skip running tests when processing the ```cpanfile```