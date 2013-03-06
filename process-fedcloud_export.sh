########################################################################################################################
# 'process-fedcloud_export.sh' is a splitting point for platform-dependent implementations of 'process_fedcloud_export'
# 
# 'process-fedcloud_export.sh' expects data in the following format:
#
# <UNIQUE_USER_ID>:<VO_NAME>:<USER_DN>:<USER_MAIL>:<PIPE_SEPARATED_SSH_KEYS>
#
# e.g.,
#
# fedcloud.egi.eu_1:fedcloud.egi.eu:/C=CZ/O=University/CN=Name:mymail@example.org:ssh-rsa dfdf...SFfgs5== user@localhost
########################################################################################################################

PROTOCOL_VERSION='3.0.0'

function get_process_fedcloud_export{
  . ${SCRIPTS_DIR}/fedcloud_export.d/process-fedcloud_export_${CLOUD_PLATFORM}.sh
}

function run_fedcloud_export_pre_hooks{
  for F in `ls "${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.d"/pre_* 2>/dev/null` ;do . $F ; done
}

function run_fedcloud_export_post_hooks{
  for F in `ls "${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.d"/post_* 2>/dev/null` ;do . $F ; done
}

function process{
  E_UNKNOWN_CLOUD_PLATFORM=(100 'Unknown cloud platform!')
  CLOUD_PLATFORM=`head -n 1 "${WORK_DIR}/CLOUD_PLATFORM"`

  # This is important, we have to create the lock in /tmp
  # to be able to run without root privileges
  LOCK_FILE="${TMPDIR:-/tmp}/${NAME}-${SERVICE}.lock"
  LOCK_PIDFILE="$LOCK_FILE/pid"
  create_lock

  case $CLOUD_PLATFORM in
    opennebula)
      get_process_fedcloud_export
      ;;
    openstack)
      get_process_fedcloud_export
      ;;
    stratuslab)
      get_process_fedcloud_export
      ;;
    wnodes)
      get_process_fedcloud_export
      ;;
    *)
      catch_error E_UNKNOWN_CLOUD_PLATFORM /bin/false
      ;;
  esac

  run_fedcloud_export_pre_hooks

  process_fedcloud_export

  run_fedcloud_export_post_hooks
}
