Perun scripts for FCTF
======================
## Description
Scripts integrating cloud middleware used within EGI FCTF with Perun.

_Features:_
* Creating users
* Removing users (with full clean-up)
* Updating users (credentials, SSH public keys, e-mail addresses)

## Installation
### Dependencies
#### OpenNebula
* `libxml-xpath-perl` (provides `/usr/bin/xpath`)
* `ruby` (used by `opennebula-cli`)
* `opennebula-cli` (rubygem, is already present in ON installations)

_Notice:_ RVM is _NOT_ required.

#### OpenStack
TODO

#### StratusLab
TODO

#### WNoDeS
TODO

### Scripts
* Copy the scripts in this repository to `/opt/perun/bin`.
* Everything in `/opt/perun/bin` has to be readable by a
  user of your choice, e.g. `oneadmin`.
* `/opt/perun/bin/perun` must be executable by the same
  user.

## Configuration
### Environment
#### OpenNebula
* ENV variables required by `opennebula-cli` must be present.
* Group(s) matching VO name(s) must be present in OpenNebula.

_Notice:_ Have a look at `fedcloud_export.d/opennebula.d/pre_00_source_opennebula_env_vars.sh`
and modify it to suit your needs. The example will attempt
to load RVM functions and ENV variables from `~/.opennebula`.

_Notice:_ The script won't touch users in group `oneadmin` and `users`.
Group(s) matching VO name(s) will be managed fully (any changes
you make manually will be overwritten).

#### OpenStack
TODO

#### StratusLab
TODO

#### WNoDeS
TODO

### SSH access
* The following SSH public key must be present in
`~/.ssh/authorized_keys` of the user you chose earlier.

~~~
from="perun.ics.muni.cz",command="/opt/perun/bin/perun" ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC26+QiDtZ3bnLiLllySgsImSPUX0/sFBmo//3PmqOsuJIBdWB5BLU5Ws+pTRxefqC8SHfI92ZQoGXe7aJniTXxbRPa0FZJ3fskAHwpbiJfstGVZ1hddBcHIvial3v5Rd++zRiKslDVTkXLlb+b1pTnjyTVbD/6kGILgnUz7RKY5DnXADVnmTdPliQCabhE41AhkWdcuWpHBNwvxONKoZJJpbuouDbcviX4lJu9TF9Ij62rZjcoNzg5/JiIKTcMVi8L04FTjyCMxKRzlo00IjSuapFnXQNNZUL5u/mfPA/HpyIkSAOiPXLhWy9UuBNo7xdrCmfTh1qUvzbuWXJZN3d9 perunv3@perun.ics.muni.cz
~~~

## Usage
Perun will automatically initiate connection, provide data
and execute `/opt/perun/bin/perun`.

## FAQ
