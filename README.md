# rapi/psgi

This docker image can be used to run a PSGI application contained
within a real directory on the host system that contains an 
```app.psgi``` file. The image has perl and RapidApp pre-installed, 
but will install any other/additional required packages from CPAN 
at runtime if a ```cpanfile``` is present in the app directory.

## Using this image:

### run interactively:

```bash
cd /path/to/psgi/app/
docker run --name=my-app --volume=$(pwd):/opt/app -it -p 5000:5000 rapi/psgi

``` 