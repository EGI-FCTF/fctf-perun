########################################################################################################################
# 'process-fedcloud_export_opennebula.sh' has an external dependency on 'libxml-xpath-perl'
# and a Ruby gem 'opennebula-cli'.
#
# 'process-fedcloud_export_opennebula.sh' expects data in the following format:
#
# <RECORD_SEPARATOR> = `echo -e '\x1E'`
# <UNIQUE_USER_ID><RECORD_SEPARATOR><VO_NAME><RECORD_SEPARATOR><USER_DN><RECORD_SEPARATOR><USER_MAIL><RECORD_SEPARATOR><PIPE_SEPARATED_SSH_KEYS>
#
# e.g.,
#
# fedcloud.egi.eu_1<RECORD_SEPARATOR>fedcloud.egi.eu<RECORD_SEPARATOR>/C=CZ/O=University/CN=Name<RECORD_SEPARATOR>mymail@example.org<RECORD_SEPARATOR>ssh-rsa dfdf...SFfgs5== user@localhost
########################################################################################################################

function process_fedcloud_export {
  ### Status codes for log_msg
  I_USER_DELETED=(0 'User ${VO_USER_FROM_ON} is no longer a member of ${VO_FROM_PERUN} and has been removed from OpenNebula!')
  I_USER_ADDED=(0 'User ${USERNAME} is a member of ${VO_SHORTNAME} and has been added to OpenNebula!')
  I_VO_SKIPPED=(0 'VO ${VO_FROM_PERUN} is not registered as a group in OpenNebula, skipping!')
  I_DELETING_VMS=(0 'Killed VMS [${USER_VMS}] owned by ${VO_USER_FROM_ON}!')
  I_DELETING_VNETS=(0 'Deleted VNETS [${USER_VNETS}] owned by ${VO_USER_FROM_ON}!')
  I_DELETING_IMAGES=(0 'Deleted IMAGES [${USER_IMAGES}] owned by ${VO_USER_FROM_ON}!')
  I_DELETING_TEMPLATES=(0 'Deleted TEMPLATES [${USER_TEMPLATES}] owned by ${VO_USER_FROM_ON}!')
  I_USER_AUTHN_UPDATE=(0 'Updated authn [${ON_AUTHN} > x509, ${ON_PASS} > ${VOMS_DN}] for ${USERNAME}!')
  I_USER_GROUP_UPDATE=(0 'Updated group membership [${ON_GROUP} > ${VO_SHORTNAME}] for ${USERNAME}!')
  I_USER_PROPS_UPDATED=(0 'Updated properties [${ON_PROP_X509_DN} > ${USER_DN}, ${ON_PROP_NAME} > ${FULLNAME}, ${ON_PROP_EMAIL} > ${USER_EMAIL}] for ${USERNAME}!')

  ### Error codes for catch_error
  E_ON_DELETE=(50 'Error during OpenNebula delete-user operation')
  E_ON_DELETE_CLEANUP=(51 'Error during OpenNebula delete-users-cleanup operation')
  E_ON_CREATE=(52 'Error during OpenNebula create-user operation')
  E_ON_CREATE_PROPERTIES=(53 'Error during OpenNebula create-user-properties operation')
  E_ON_UPDATE=(54 'Error during OpenNebula update-user operation')
  E_ON_UPDATE_PROPERTIES=(55 'Error during OpenNebula update-user-properties operation')
  E_ON_CHAIN_FAILED=(56 'Error during data parsing, sorting and filtering')

  DATA_FROM_PERUN="${WORK_DIR}/fedcloud_export"
  VOMS_ONLY=1 # Set this to 0 if you want to register DNs from personal certificates
              # as well as VOMS proxy certificates

  RECORD_SEPARATOR=`echo -e '\x1E'`

  # There is no need to call create_lock, this was already taken care of
  # in 'process-fedcloud_export.sh'

  # Make pipe-chained commands report all failures as a global failure
  set -o pipefail

  # Get list of VOs from Perun
  VOS_FROM_PERUN=`cat $DATA_FROM_PERUN | sed 's/^[^'${RECORD_SEPARATOR}']\+'${RECORD_SEPARATOR}'\([[:alnum:]_.-]*\)'${RECORD_SEPARATOR}'.*/\1/' | sort -u`

  # Get a list of existing groups from OpenNebula,
  # each group represents one VO, groups have to be
  # already present in OpenNebula
  VOS_FROM_ON=`onegroup list --xml | xpath -q -e '/GROUP_POOL/GROUP[ NAME!="oneadmin" and NAME!="users" ]/NAME/text()' | sort`

  if [ "$?" -ne 0 ]; then
    catch_error E_ON_CHAIN_FAILED /bin/false
  fi

  # Iterate through every VO and check which user will be added or removed
  while read VO_FROM_PERUN; do

    # Skip VOs not registered as groups in opennebula
    if [ `echo "$VOS_FROM_ON" | grep -c "^$VO_FROM_PERUN$"` -eq 0 ]; then
      log_msg I_VO_SKIPPED
      continue
    fi

    # Get users from the VO_FROM_PERUN
    VO_USERS_FROM_PERUN=`cat $DATA_FROM_PERUN | grep "^[^${RECORD_SEPARATOR}]\+${RECORD_SEPARATOR}${VO_FROM_PERUN}${RECORD_SEPARATOR}[^${RECORD_SEPARATOR}]\+${RECORD_SEPARATOR}[^${RECORD_SEPARATOR}]\+" | awk -F "${RECORD_SEPARATOR}" '{print $1}' | sort`

    # Get current users from OpenNebula
    VO_USERS_FROM_ON_XML=`oneuser list --xml`

    if [ "$?" -ne 0 ]; then
      catch_error E_ON_CHAIN_FAILED /bin/false
    fi

    VO_USERS_FROM_ON=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ GNAME=\"${VO_FROM_PERUN}\" ]/NAME/text()" | sort`

    # Check who should be deleted from OpenNebula
    [ "$VO_USERS_FROM_ON" != "" ] && while read VO_USER_FROM_ON; do

      if [ `echo "$VO_USERS_FROM_PERUN" | grep -c "^$VO_USER_FROM_ON$"` -eq 0 ]; then
        ## User is not in the VO anymore, we have to remove him from OpenNebula
        # Check whether the user has any VMs running and terminate them forcefully
        USER_VMS=`onevm list $VO_USER_FROM_ON --xml | xpath -q -e "/VM_POOL/VM/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`

        if [ "$?" -ne 0 ]; then
          catch_error E_ON_CHAIN_FAILED /bin/false
        fi

        if [ "$USER_VMS" != "" ]; then
          catch_error E_ON_DELETE_CLEANUP onevm delete $USER_VMS
          log_msg I_DELETING_VMS
        fi

        ## TODO: Some grace period is in order for deployment in production
        # Check for networks, images, VM templates owned by this user and delete them
        #USER_VNETS=`onevnet list $VO_USER_FROM_ON --xml | xpath -q -e "/VNET_POOL/VNET/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        #
        #if [ "$?" -ne 0 ]; then
        #  catch_error E_ON_CHAIN_FAILED /bin/false
        #fi
        #
        #if [ "$USER_VNETS" != "" ]; then
        #  catch_error E_ON_DELETE_CLEANUP onevnet delete $USER_VNETS
        #  log_msg I_DELETING_VNETS
        #fi

        #USER_IMAGES=`oneimage list $VO_USER_FROM_ON --xml | xpath -q -e "/IMAGE_POOL/IMAGE/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        #
        #if [ "$?" -ne 0 ]; then
        #  catch_error E_ON_CHAIN_FAILED /bin/false
        #fi
        #
        #if [ "$USER_IMAGES" != "" ]; then
        #  catch_error E_ON_DELETE_CLEANUP oneimage delete $USER_IMAGES
        #  log_msg I_DELETING_IMAGES
        #fi
        
        #USER_TEMPLATES=`onetemplate list $VO_USER_FROM_ON --xml | xpath -q -e "/VMTEMPLATE_POOL/VMTEMPLATE/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        #
        #if [ "$?" -ne 0 ]; then
        #  catch_error E_ON_CHAIN_FAILED /bin/false
        #fi
        #
        #if [ "$USER_TEMPLATES" != "" ]; then
        #  catch_error E_ON_DELETE_CLEANUP onetemplate delete $USER_TEMPLATES
        #  log_msg I_DELETING_TEMPLATES
        #fi

        # Remove the user from OpenNebula
        catch_error E_ON_DELETE oneuser delete $VO_USER_FROM_ON

        # Report success
        log_msg I_USER_DELETED
      fi

    done< <(echo "$VO_USERS_FROM_ON")

    # Need more information to create a user
    VO_USERS_FROM_PERUN=`cat $DATA_FROM_PERUN | grep "^[^${RECORD_SEPARATOR}]\+${RECORD_SEPARATOR}${VO_FROM_PERUN}${RECORD_SEPARATOR}[^${RECORD_SEPARATOR}]\+${RECORD_SEPARATOR}[^${RECORD_SEPARATOR}]\+" | sort`

    # Check who should be added to OpenNebula
    [ "$VO_USERS_FROM_PERUN" != "" ] && while read VO_USER_FROM_PERUN; do

      # Extract <UNIQUE_USER_ID>
      VO_USER_FROM_PERUN_SHORT=`echo "$VO_USER_FROM_PERUN" | awk -F "${RECORD_SEPARATOR}" '{print $1}'`
      
      if [ `echo "$VO_USERS_FROM_ON" | grep -c "^$VO_USER_FROM_PERUN_SHORT$"` -eq 0 ]; then
        # Detected a VO member not present in OpenNebula
        while IFS="${RECORD_SEPARATOR}" read USERNAME VO_SHORTNAME USER_DN USER_EMAIL SSH_KEYS; do
          # Construct a unique username and append VOMS information to user's DN
          if [ "$VOMS_ONLY" = "0" ]; then
            VOMS_DN="${USER_DN}|${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"
          else
            VOMS_DN="${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"
          fi

          # Remove all spaces from VOMS_DN
          VOMS_DN=`echo "$VOMS_DN" | sed 's/\s//g'`

          # Add user to OpenNebula
          catch_error E_ON_CREATE oneuser create "$USERNAME" "$VOMS_DN" --driver x509
          
          # Chgrp user to the right group == VO_SHORTNAME
          catch_error E_ON_CREATE oneuser chgrp "$USERNAME" "$VO_SHORTNAME"

          # Fill in user's properties, e.g. "NAME"/"EMAIL"/"X509_DN"
          TMP_FILE=`mktemp ${WORK_DIR}/${USERNAME}.XXXXXXXXXX`
          [ $? -ne 0 ] && log_msg E_WORK_DIR

          FULLNAME=`echo "$USER_DN" | sed 's|^.*\/CN=\([^/]*\).*|\1|'`

          echo -e "X509_DN=\"${USER_DN}\"\nNAME=\"${FULLNAME}\"\nEMAIL=\"${USER_EMAIL}\"\n" > $TMP_FILE

          if [ "$SSH_KEYS" != "" ]; then
            SSH_KEYS=`echo "$SSH_KEYS" | sed 's/|/\n/g' | sort`
            echo "SSH_KEY=\"$SSH_KEYS\"" >> $TMP_FILE
          fi

          catch_error E_ON_CREATE_PROPERTIES oneuser update "$USERNAME" $TMP_FILE

          log_msg I_USER_ADDED
        done< <(echo "$VO_USER_FROM_PERUN")
      else
        # Detected a VO member present in OpenNebula, we have to check whether his credentials,
        # VO membership or personal information need updating.
        while IFS="${RECORD_SEPARATOR}" read USERNAME VO_SHORTNAME USER_DN USER_EMAIL SSH_KEYS; do
          # Construct a unique username and append VOMS information to user's DN
          if [ "$VOMS_ONLY" = "0" ]; then
            VOMS_DN="${USER_DN}|${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"
          else
            VOMS_DN="${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"
          fi

          # Remove all spaces from VOMS_DN
          VOMS_DN=`echo "$VOMS_DN" | sed 's/\s//g'`
          
          # Check authn driver and password (==VOMS_DN)
          ON_AUTHN=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/AUTH_DRIVER/text()"`
          ON_PASS=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/PASSWORD/text()"`
          if [ "$ON_AUTHN" != "x509" ] || [ "$ON_PASS" != "$VOMS_DN" ]; then
            catch_error E_ON_UPDATE oneuser chauth "$USERNAME" x509 "$VOMS_DN"
            log_msg I_USER_AUTHN_UPDATE
          fi

          # Check group (==VO) membership
          ON_GROUP=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/GNAME/text()"`
          if [ "$ON_GROUP" != "$VO_SHORTNAME" ]; then
            catch_error E_ON_UPDATE oneuser chgrp "$USERNAME" "$VO_SHORTNAME"
            log_msg I_USER_GROUP_UPDATE
          fi
          
          # Check user properties
          ON_PROP_X509_DN=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/X509_DN/text()"`
          ON_PROP_NAME=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/NAME/text()"`
          ON_PROP_EMAIL=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/EMAIL/text()"`
          ON_PROP_SSH_KEY=`echo "$VO_USERS_FROM_ON_XML" | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/SSH_KEY/text()" | sort`

          SSH_KEYS=`echo "$SSH_KEYS" | sed 's/|/\n/g' | sort`

          FULLNAME=`echo "$USER_DN" | sed 's|^.*\/CN=\([^/]*\).*|\1|'`
          if [ "$ON_PROP_X509_DN" != "$USER_DN" ] || [ "$ON_PROP_NAME" != "$FULLNAME" ] || [ "$ON_PROP_EMAIL" != "$USER_EMAIL" ] || [ "$ON_PROP_SSH_KEY" != "$SSH_KEYS" ]; then
            TMP_FILE=`mktemp ${WORK_DIR}/${USERNAME}.XXXXXXXXXX`
            [ $? -ne 0 ] && log_msg E_WORK_DIR
 
            echo -e "X509_DN=\"${USER_DN}\"\nNAME=\"${FULLNAME}\"\nEMAIL=\"${USER_EMAIL}\"\n" > $TMP_FILE

            if [ "$SSH_KEYS" != "" ]; then
              echo "SSH_KEY=\"$SSH_KEYS\"" | sed 's/|/\n/g' >> $TMP_FILE
            fi

            catch_error E_ON_UPDATE_PROPERTIES oneuser update "$USERNAME" $TMP_FILE
            log_msg I_USER_PROPS_UPDATED
          fi
        done< <(echo "$VO_USER_FROM_PERUN")
      fi

    done< <(echo "$VO_USERS_FROM_PERUN")

  done< <(echo "$VOS_FROM_PERUN")

  # Revert to default
  set +o pipefail
}
