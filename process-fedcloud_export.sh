########################################################################################################################
# 'process-fedcloud_export.sh' is a splitting point for platform-dependent implementations of 'process_fedcloud_export'
# 
# 'process-fedcloud_export.sh' expects data in the following format:
#
# <RECORD_SEPARATOR> = `echo -e '\x1E'`
# <UNIQUE_USER_ID><RECORD_SEPARATOR><VO_NAME><RECORD_SEPARATOR><USER_DN><RECORD_SEPARATOR><USER_MAIL><RECORD_SEPARATOR><PIPE_SEPARATED_SSH_KEYS>
#
# e.g.,
#
# fedcloud.egi.eu_1<RECORD_SEPARATOR>fedcloud.egi.eu<RECORD_SEPARATOR>/C=CZ/O=University/CN=Name<RECORD_SEPARATOR>mymail@example.org<RECORD_SEPARATOR>ssh-rsa dfdf...SFfgs5== user@localhost
########################################################################################################################

PROTOCOL_VERSION='3.1.0'

function get_process_fedcloud_export {
  . ${SCRIPTS_DIR}/fedcloud_export.d/process-fedcloud_export_${CLOUD_PLATFORM}.sh
}

function run_fedcloud_export_pre_hooks {
  for F in `ls "${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.d"/pre_* 2>/dev/null` ;do . $F ; done
}

function run_fedcloud_export_post_hooks {
  for F in `ls "${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.d"/post_* 2>/dev/null` ;do . $F ; done
}

function add_fedcloud_export_bin {
  PATH=${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.bin:$PATH
}

function add_fedcloud_export_lib {
  LD_LIBRARY_PATH=${SCRIPTS_DIR}/fedcloud_export.d/${CLOUD_PLATFORM}.lib:$LD_LIBRARY_PATH
}

function process {
  E_UNKNOWN_CLOUD_PLATFORM=(100 'Unknown cloud platform!')
  CLOUD_PLATFORM=`head -n 1 "${WORK_DIR}/CLOUD_PLATFORM"`

  # This is important, we have to create the lock in /tmp
  # to be able to run without root privileges
  LOCK_FILE="${TMPDIR:-/tmp}/${NAME}-${SERVICE}.lock"
  LOCK_PIDFILE="$LOCK_FILE/pid"
  create_lock

  #
  case $CLOUD_PLATFORM in
    opennebula)
      get_process_fedcloud_export
      ;;
    stratuslab)
      get_process_fedcloud_export
      ;;
    *)
      catch_error E_UNKNOWN_CLOUD_PLATFORM /bin/false
      ;;
  esac

  #
  add_fedcloud_export_lib
  add_fedcloud_export_bin

  #
  run_fedcloud_export_pre_hooks

  #
  process_fedcloud_export

  #
  run_fedcloud_export_post_hooks
}
