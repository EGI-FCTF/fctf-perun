#!/bin/bash

################################################################################################
# 'process-opennebula_fedcloud.sh' has an external dependency on 'libxml-xpath-perl'
# and a Ruby gem 'opennebula-cli'.
#
# 'process-opennebula_fedcloud.sh' expects data in the following format:
#
# <VO_NAME>_<UNIQUE_USER_ID>-<USER_DN_HASH>:<VO_NAME>:<USER_DN>:<USER_MAIL>
#
# e.g.,
#
# fedcloud.egi.eu_1-5sfg6f54gfs:fedcloud.egi.eu:/C=CZ/O=University/CN=Name:mymail@example.org
################################################################################################

PROTOCOL_VERSION='3.0.0'

function process {
  ### Status codes for log_msg
  I_USER_DELETED=(0 "User ${VO_USER_FROM_ON} is no longer a member of ${VO_FROM_PERUN} and has been removed from OpenNebula!")
  I_USER_ADDED=(0 "User ${USERNAME} is a member of ${VO_SHORTNAME} and has been added to OpenNebula!")
  I_USER_UPDATED=(0 "User ${USERNAME} is still a member of ${VO_SHORTNAME} and has been updated in OpenNebula!")

  ### Error codes for catch_error
  E_ON_DELETE=(50 'Error during OpenNebula delete-user operation')
  E_ON_DELETE_CLEANUP=(51 'Error during OpenNebula delete-users-cleanup operation')
  E_ON_CREATE=(52 'Error during OpenNebula create-user operation')
  E_ON_CREATE_PROPERTIES=(53 'Error during OpenNebula create-user-properties operation')
  E_ON_UPDATE=(54 'Error during OpenNebula update-user operation')
  E_ON_UPDATE_PROPERTIES=(55 'Error during OpenNebula update-user-properties operation')

  DATA_FROM_PERUN="${WORK_DIR}/opennebula_fedcloud"

  create_lock

  # Get list of VOs from Perun
  VOS_FROM_PERUN=`cat $DATA_FROM_PERUN | sed 's/^[^:]\+:\([[:alnum:]_.-]*\):.*/\1/' | uniq | sort`
  
  # Get a list of existing groups from OpenNebula,
  # each group represents one VO, groups have to be
  # already present in OpenNebula
  VOS_FROM_ON=`onegroup list --xml | xpath -q -e '/GROUP_POOL/GROUP[ NAME!="oneadmin" and NAME!="users" ]/NAME/text()' | sort`

  # Iterate through every VO and check which user will be added or removed
  while read VO_FROM_PERUN; do

    echo "Processing VO $VO_FROM_PERUN ..."

    # Skip VOs not registered as groups in opennebula
    if [ `echo $VOS_FROM_ON | grep -c "$VO_FROM_PERUN"` -eq 0 ]; then
      echo "This VO is not registered as a group in OpenNebula, skipping ..."
      continue
    fi

    # Get users from the VO_FROM_PERUN
    VO_USERS_FROM_PERUN=`cat $DATA_FROM_PERUN | grep "^[^:]\+:${VO_FROM_PERUN}:[^:]\+:[^:]\+" | awk -F ':' '{print $1}' | sort`

    # Get current users from OpenNebula
    VO_USERS_FROM_ON_XML=`oneuser list --xml`
    VO_USERS_FROM_ON=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ GNAME=\"${VO_FROM_PERUN}\" and AUTH_DRIVER=\"x509\" ]/NAME/text()" | sort`

    # Check who should be deleted from OpenNebula
    while read VO_USER_FROM_ON; do

      echo "Checking whether $VO_USER_FROM_ON from OpenNebula is still in VO $VO_FROM_PERUN from Perun ..."

      if [ `echo $VO_USERS_FROM_PERUN | grep -c "$VO_USER_FROM_ON"` -eq 0 ]; then

        echo "$VO_USER_FROM_ON is not in $VO_FROM_PERUN, removing from OpenNebula ..."

        ## User is not in the VO anymore, we have to remove him from OpenNebula
        # Check whether the user has any VMs running and terminate them forcefully
        USER_VMS=`onevm list $VO_USER_FROM_ON --xml | xpath -q -e "/VM_POOL/VM/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        if [ "$USER_VMS" != "" ]; then
          catch_error E_ON_DELETE_CLEANUP onevm delete $USER_VMS
        fi

        # Check for networks, images, VM templates owned by this user and delete them
        USER_VNETS=`onevnet list $VO_USER_FROM_ON --xml | xpath -q -e "/VNET_POOL/VNET/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        if [ "$USER_VNETS" != "" ]; then
          catch_error E_ON_DELETE_CLEANUP onevnet delete $USER_VNETS
        fi

        USER_IMAGES=`oneimage list $VO_USER_FROM_ON --xml | xpath -q -e "/IMAGE_POOL/IMAGE/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        if [ "$USER_IMAGES" != "" ]; then
          catch_error E_ON_DELETE_CLEANUP oneimage delete $USER_IMAGES
        fi
        
        USER_TEMPLATES=`onetemplate list $VO_USER_FROM_ON --xml | xpath -q -e "/VMTEMPLATE_POOL/VMTEMPLATE/ID/text()" | sort | sed ':a;N;$!ba;s/\n/,/g'`
        if [ "$USER_TEMPLATES" != "" ]; then
          catch_error E_ON_DELETE_CLEANUP onetemplate delete $USER_TEMPLATES
        fi

        # Remove the user from OpenNebula
        catch_error E_ON_DELETE oneuser delete $VO_USER_FROM_ON

        # Report success
        log_msg I_USER_DELETED
      else
        echo "$VO_USER_FROM_ON is still in VO $VO_FROM_PERUN, doing nothing ..."
      fi

    done< <(echo -e "$VO_USERS_FROM_ON")

    # Need more information to create a user
    VO_USERS_FROM_PERUN=`cat $DATA_FROM_PERUN | grep "^[^:]\+:${VO_FROM_PERUN}:[^:]\+:[^:]\+" | sort`

    # Check who should be added to OpenNebula
    while read VO_USER_FROM_PERUN; do

      # Extract <VO_NAME>_<UNIQUE_USER_ID>
      VO_USER_FROM_PERUN_SHORT=`echo "$VO_USER_FROM_PERUN" | awk -F ':' '{print $1}'`
      
      echo "Checking whether $VO_USER_FROM_PERUN_SHORT from Perun should be added to OpenNebula ..."
      if [ `echo $VO_USERS_FROM_ON | grep -c "$VO_USER_FROM_PERUN_SHORT"` -eq 0 ]; then
        # Detected a VO member not present in OpenNebula
        while IFS=":" read USERNAME VO_SHORTNAME USER_DN USER_EMAIL; do
          echo "Adding $USERNAME to OpenNebula ..."
          # Construct a unique username and append VOMS information to user's DN
          VOMS_DN="${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"

          # Remove all spaces from VOMS_DN
          VOMS_DN=`echo "$VOMS_DN" | sed 's/ //g'`

          # Add user to OpenNebula
          catch_error E_ON_CREATE oneuser create "$USERNAME" "$VOMS_DN" --driver x509
          
          # Chgrp user to the right group == VO_SHORTNAME
          catch_error E_ON_CREATE oneuser chgrp "$USERNAME" "$VO_SHORTNAME"

          # Fill in user's properties, e.g. "NAME"/"EMAIL"/"X509_DN"
          TMP_FILE=`mktemp ${WORK_DIR}/${USERNAME}.XXXXXXXXXX`
          [ $? -ne 0 ] && log_msg E_WORK_DIR

          FULLNAME=`echo $USER_DN | sed 's|^.*\/CN=\([^/]*\).*|\1|'`

          echo -e "X509_DN=\"${USER_DN}\"\nNAME=\"${FULLNAME}\"\nEMAIL=\"${USER_EMAIL}\"" > $TMP_FILE
          catch_error E_ON_CREATE_PROPERTIES oneuser update "$USERNAME" $TMP_FILE

          log_msg I_USER_ADDED
        done< <(echo "$VO_USER_FROM_PERUN")
      else
        # Detected a VO member present in OpenNebula, we have to check whether his credentials,
        # VO membership or personal information need updating.
        while IFS=":" read USERNAME VO_SHORTNAME USER_DN USER_EMAIL; do
          echo "Updating $USERNAME in OpenNebula, if necessary ..."
          # Construct a unique username and append VOMS information to user's DN
          VOMS_DN="${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"

          # Remove all spaces from VOMS_DN
          VOMS_DN=`echo "$VOMS_DN" | sed 's/ //g'`
          
          # Check authn driver and password (==VOMS_DN)
          ON_AUTHN=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/AUTH_DRIVER/text()"`
          ON_PASS=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/PASSWORD/text()"`
          if [ "X${ON_AUTHN}" != "Xx509" ] || [ "X${ON_PASS}" != "X${VOMS_DN}" ]; then
            catch_error E_ON_UPDATE oneuser chauth "$USERNAME" x509 "$VOMS_DN"
          fi

          # Check group (==VO) membership
          ON_GROUP=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/GNAME/text()"`
          if [ "X${ON_GROUP}" != "X${VO_SHORTNAME}" ]; then
            catch_error E_ON_UPDATE oneuser chgrp "$USERNAME" "$VO_SHORTNAME"
          fi
          
          # Check user properties
          ON_PROP_X509_DN=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/X509_DN/text()"`
          ON_PROP_NAME=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/NAME/text()"`
          ON_PROP_EMAIL=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ NAME=\"${USERNAME}\" ]/TEMPLATE/EMAIL/text()"`

          FULLNAME=`echo $USER_DN | sed 's|^.*\/CN=\([^/]*\).*|\1|'`
          if [ "X${ON_PROP_X509_DN}" != "X${USER_DN}" ] || [ "X${ON_PROP_NAME}" != "X${FULLNAME}" ] || [ "X${ON_PROP_EMAIL}" != "X${USER_EMAIL}" ]; then
            TMP_FILE=`mktemp ${WORK_DIR}/${USERNAME}.XXXXXXXXXX`
            [ $? -ne 0 ] && log_msg E_WORK_DIR
 
            echo -e "X509_DN=\"${USER_DN}\"\nNAME=\"${FULLNAME}\"\nEMAIL=\"${USER_EMAIL}\"" > $TMP_FILE
            catch_error E_ON_UPDATE_PROPERTIES oneuser update "$USERNAME" $TMP_FILE
          fi

          log_msg I_USER_UPDATED
        done< <(echo "$VO_USER_FROM_PERUN")
      fi

    done< <(echo -e "$VO_USERS_FROM_PERUN")

  done< <(echo -e "$VOS_FROM_PERUN")
}
