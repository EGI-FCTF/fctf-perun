########################################################################################################################
# 'process-fedcloud_export_openstack.sh' has no external dependencies.
#
# 'process-fedcloud_export_openstack.sh' expects data in the following format:
#
# <UNIQUE_USER_ID>:<VO_NAME>:<USER_DN>:<USER_MAIL>:<PIPE_SEPARATED_SSH_KEYS>
#
# e.g.,
#
# fedcloud.egi.eu_1:fedcloud.egi.eu:/C=CZ/O=University/CN=Name:mymail@example.org:ssh-rsa dfdf...SFfgs5== user@localhost
########################################################################################################################

function process_fedcloud_export {
  DATA_FROM_PERUN="${WORK_DIR}/fedcloud_export"

  # There is no need to call create_lock, this was already taken care of
  # in 'process-fedcloud_export.sh'

  ## TODO: See 'process-fedcloud_export_opennebula.sh' if you are looking for inspiration!
  ## It's important to adopt at least the use of 'log_msg' and 'catch_error' when reporting
  ## status back to Perun.
}
