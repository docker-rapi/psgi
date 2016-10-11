# ~/.bashrc: executed by bash(1) for non-login shells.
# -- Custom bashrc for rapi/psgi --

ra_dev_source_script='/opt/dev/RapidApp/devel/source_dev_shell_vars.bash'
if [ -e $ra_dev_source_script ]; then
  eval "source $ra_dev_source_script"
fi
