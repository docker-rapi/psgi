# ~/.bashrc: executed by bash(1) for non-login shells.
# -- Custom bashrc for rapi/psgi --

echo "----"
echo "----  rapi/psgi ($RAPI_PSGI_IMAGE_VERSION) - CONTAINER root shell [/root/.bashrc]  ----"
echo "----"
echo ''

source <(perl /print_bashrc_eval.pl)

echo ''
