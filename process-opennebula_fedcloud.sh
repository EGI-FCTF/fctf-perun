#!/bin/bash

##############################################################################
# 'process-opennebula_fedcloud.sh' has an external dependency on 'xpath'
# and 'opennebula-oca'.
#
# 'process-opennebula_fedcloud.sh' expects data in the following format:
#
# <UNIQUE_USER_ID>:<VO_NAME>:<USER_DN>:<USER_MAIL>
#
# e.g.,
#
# 1:fedcloud.egi.eu:/C=CZ/O=Masaryk University/CN=My Name:mymail@example.org
##############################################################################

PROTOCOL_VERSION='3.5.0'

function process {
  ### Status codes for log_msg
  I_USER_DELETED=(0 "User ${VO_USER_FROM_ON} is no longer a member of ${VO_FROM_PERUN} and has been removed from OpenNebula!")
  I_USER_ADDED=(0 "User ${VO_SHORTNAME}_${USER_ID} is a member of ${VO_SHORTNAME} and has been added to OpenNebula!")
  I_USER_UPDATED=(0 "User ${VO_SHORTNAME}_${USER_ID} is still a member of ${VO_SHORTNAME} and has been updated in OpenNebula!")

  ### Error codes for catch_error
  E_ON_DELETE=(50 'Error during OpenNebula delete-user operation')
  E_ON_DELETE_CLEANUP=(50 'Error during OpenNebula delete-users-cleanup operation')
  E_ON_CREATE=(50 'Error during OpenNebula create-user operation')
  E_ON_UPDATE_PROPERTIES=(50 'Error during OpenNebula update-user-properties operation')

  DATA_FROM_PERUN="${WORK_DIR}/opennebula_fedcloud"

  create_lock

  # Get list of VOs from Perun
  VOS_FROM_PERUN=`cat $DATA_FROM_PERUN | sed 's/^[[:digit:]]*:\([[:alnum:]_.-]*\):.*/\1/' | uniq | sort`
  
  # Get a list of existing groups from OpenNebula,
  # each group represents one VO, groups have to be
  # already present in OpenNebula
  VOS_FROM_ON=`onegroup list --xml | xpath -q -e '/GROUP_POOL/GROUP[ NAME!="oneadmin" and NAME!="users" ]/NAME/text()' | sort`

  # Iterate through every VO and check which user will be added or removed
  echo -e "$VOS_FROM_PERUN" | while read VO_FROM_PERUN; do

    # Skip VOs not registered as groups in opennebula
    if [ `echo $VOS_FROM_ON | grep -c "$VO_FROM_PERUN"` -eq 0 ]; then
      continue
    fi

    # Get users from the VO_FROM_PERUN
    VO_USERS_FROM_PERUN=`cat $DATA_FROM_PERUN | grep "^[[:digit:]]*:${VO_FROM_PERUN}:.*:.*" | awk -F ':' '{print $2"_"$1"}' | sort`

    # Get current users from OpenNebula
    VO_USERS_FROM_ON_XML=`oneuser list --xml`
    VO_USERS_FROM_ON=`echo $VO_USERS_FROM_ON_XML | xpath -q -e "/USER_POOL/USER[ GNAME=\"${VO_FROM_PERUN}\" and AUTH_DRIVER=\"x509\" ]/NAME/text()" | sort`

    # Check who should be deleted from OpenNebula
    echo -e "$VO_USERS_FROM_ON" | while read VO_USER_FROM_ON; do

      if [ `echo $VO_USERS_FROM_PERUN | grep -c "$VO_USER_FROM_ON"` -eq 0 ]; then  
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
      fi

    done

    # Check who should be added to OpenNebula
    echo -e "$VO_USERS_FROM_PERUN" | while read VO_USER_FROM_PERUN; do

      if [ `echo $VO_USERS_FROM_ON | grep -c "$VO_USER_FROM_PERUN"` -eq 0 ]; then
        # Detected a VO member not present in OpenNebula
        echo $VO_USER_FROM_PERUN | while IFS=":" read USER_ID VO_SHORTNAME USER_DN USER_EMAIL; do
          # Construct a unique username and append VOMS information to user's DN
          USERNAME="${VO_SHORTNAME}_${USER_ID}"
          VOMS_DN="${USER_DN}/VO=${VO_SHORTNAME}/Role=NULL/Capability=NULL"

          # Remove all spaces from VOMS_DN
          VOMS_DN=`echo "$VOMS_DN" | sed 's/ //g'`

          # Add user to OpenNebula
          catch_error E_ON_CREATE oneuser create "$USERNAME" "$VOMS_DN" --driver x509
          
          # Chgrp user to the right group == VO_SHORTNAME
          catch_error E_ON_CREATE oneuser chgrp "$USERNAME" "$VO_SHORTNAME"

          # TODO: Fill in user's properties, e.g. "Full name"/"E-mail"/"X509_DN"
          # TODO: USER_CN=`echo $USER_DN | sed 's|^.*\/CN=\([^/]*\).*|\1|'`
          log_msg I_USER_ADDED
        done
      else
        # Detected a VO member present in OpenNebula, we have to check whether his credentials
        # or personal information need updating.
        echo $VO_USER_FROM_PERUN | while IFS=":" read USER_ID VO_SHORTNAME USER_DN USER_EMAIL; do
          # TODO: Check /USER_POOL/USER/PASSWORD and DN match
          # TODO: Check /USER_POOL/USER/TEMPLATE/509_DN and DN match
          # TODO: Check other /USER_POOL/USER/TEMPLATE/* properties
          # TODO: USER_CN=`echo $USER_DN | sed 's|^.*\/CN=\([^/]*\).*|\1|'`
          log_msg I_USER_UPDATED
        done
      fi

    done

  done
}
