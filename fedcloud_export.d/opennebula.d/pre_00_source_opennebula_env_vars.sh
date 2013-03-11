RVM_LOADED="no"

TRAPS=`trap`

if [ -s "$HOME/.rvm/scripts/rvm" ]; then
  . "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*
  PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting
  RVM_LOADED="yes"
fi

if [ -s "/usr/local/rvm/scripts/rvm" ] && [ "$RVM_LOADED" != "yes" ]; then
  . "/usr/local/rvm/scripts/rvm" # Load RVM into a shell session *as a function*
  PATH=$PATH:/usr/local/rvm/bin # Add RVM to PATH for scripting
  RVM_LOADED="yes"
fi

if [ "$RVM_LOADED" = "yes" ]; then
  eval $TRAPS
fi

if [ -f "$HOME/.opennebula" ]; then
  . "$HOME/.opennebula"
fi
