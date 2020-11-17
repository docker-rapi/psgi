#!/usr/bin/env perl

# -----------------------------------------------------------------------------
# This is a special script written for rapi/psgi to dynamically control the
# shell code which is ran from bashrc within the container filesystem. This
# script prints bash commands to the screen which are then called with 'eval'
# from the /root/.bashrc script. This is to provide environment consistency
# allowing users to call 'bash' to get a shell instead of the entrypoint
# -----------------------------------------------------------------------------

use strict;
use warnings;

-f '/common_env.pl' and require '/common_env.pl';

print "\nexport PERLLIB=$ENV{PERLLIB};\n" if ($ENV{PERLLIB});


# This is partially redundant with above but is safe and consistent:
print q|
ra_dev_source_script='/opt/dev/RapidApp/devel/source_dev_shell_vars.bash'
if [ -e $ra_dev_source_script ]; then
  eval "source $ra_dev_source_script"
fi
|;

