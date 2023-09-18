
MPID="$1"
ret=0

#---

if [ -z "$MPID" ] ; then
  if [ -n "$TUNNEL_DEBUG" ] ; then
    exec 2>/tmp/t1
    set -x
    env >&2
  fi

  ABSPATH=$(cd "$(dirname "$0")"; pwd -P)

  query="`dd 2>/dev/null`"
  [ -n "$TUNNEL_DEBUG" ] && echo "query: <$query>" >&2

  export TIMEOUT="`echo $query | sed -e 's/^.*\"timeout\": *\"//' -e 's/\".*$//g'`"
  export SSH_CMD="`echo $query | sed -e 's/^.*\"ssh_cmd\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export LOCAL_HOST="`echo $query | sed -e 's/^.*\"local_host\": *\"//' -e 's/\".*$//g'`"
  export LOCAL_PORT="`echo $query | sed -e 's/^.*\"local_port\": *\"//' -e 's/\".*$//g'`"
  export TARGET_HOST="`echo $query | sed -e 's/^.*\"target_host\": *\"//' -e 's/\".*$//g'`"
  export TARGET_PORT="`echo $query | sed -e 's/^.*\"target_port\": *\"//' -e 's/\".*$//g'`"
  export GATEWAY_HOST="`echo $query | sed -e 's/^.*\"gateway_host\": *\"//' -e 's/\".*$//g'`"
  export GATEWAY_PORT="`echo $query | sed -e 's/^.*\"gateway_port\": *\"//' -e 's/\".*$//g'`"
  export GATEWAY_USER="`echo $query | sed -e 's/^.*\"gateway_user\": *\"//' -e 's/\".*$//g'`"
  export SKIP_GATEWAY_PARAM="`echo $query | sed -e 's/^.*\"skip_gateway_param\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export SHELL_CMD="`echo $query | sed -e 's/^.*\"shell_cmd\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export SSH_TUNNEL_CHECK_SLEEP="`echo $query | sed -e 's/^.*\"ssh_tunnel_check_sleep\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export SSH_PARENT_WAIT_SLEEP="`echo $query | sed -e 's/^.*\"ssh_parent_wait_sleep\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export CREATE="`echo $query | sed -e 's/^.*\"create\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export CHECK_SCRIPT="`echo $query | sed -e 's/^.*\"check_script\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"
  export CHECK_SCRIPT_TIMEOUT="`echo $query | sed -e 's/^.*\"check_script_timeout\": *\"//' -e 's/\",.*$//g' -e 's/\\\"/\"/g'`"

  if [ "X$CREATE" = X -o "X$GATEWAY_HOST" = X ] ; then
    # No tunnel - connect directly to target host
    do_tunnel=''
    cnx_host="$TARGET_HOST"
    cnx_port="$TARGET_PORT"
  else
    do_tunnel='y'
    cnx_host="$LOCAL_HOST"
    cnx_port="$LOCAL_PORT"
  fi

  echo "{ \"host\": \"$cnx_host\",  \"port\": \"$cnx_port\" }"

  if [ -n "$do_tunnel" ] ; then
    p=`ps -p $PPID -o "ppid="`
    clog=`mktemp`
    nohup timeout $TIMEOUT $SHELL_CMD "$ABSPATH/tunnel.sh" $p <&- >&- 2>$clog &
    CPID=$!
    # A little time for the SSH tunnel process to start or fail
    sleep $SSH_PARENT_WAIT_SLEEP
    # If the child process does not exist anymore after this delay, report failure
    if ! ps -p $CPID >/dev/null 2>&1 ; then
      echo "Child process ($CPID) failure - Aborting" >&2
      echo "Child diagnostics follow:" >&2
      cat $clog >&2
      rm -f $clog
      ret=1

      exit $ret
    fi
    rm -f $clog

    # Wait for the tunnel to be ready by checking the remote port is responding
    if [ -n "$CHECK_SCRIPT" ] ; then
      x=0
      while [ $x -lt "$CHECK_SCRIPT_TIMEOUT" ] ; do
        eval $CHECK_SCRIPT && break
        sleep 1
        x=$((x+1))
      done
      if [ $x -ge "$CHECK_SCRIPT_TIMEOUT" ] ; then
        echo "Parent process can't verify tunnel running properly - Aborting" >&2
        ret=1
      fi
    fi
  fi
else
  #------ Child
  if [ -n "$TUNNEL_DEBUG" ] ; then
    exec 2>/tmp/t2
    set -x
    env >&2
  fi

  gw=""
  if [ "X$SKIP_GATEWAY_PARAM" != X ] ; then
    gw="$GATEWAY_HOST"
    [ "X$GATEWAY_USER" = X ] || gw="$GATEWAY_USER@$GATEWAY_HOST"
  fi

  $SSH_CMD -N -L $LOCAL_HOST:$LOCAL_PORT:$TARGET_HOST:$TARGET_PORT -p $GATEWAY_PORT $gw &

  CPID=$!
  
  sleep $SSH_TUNNEL_CHECK_SLEEP

  while true ; do
    if ! ps -p $CPID >/dev/null 2>&1 ; then
      echo "SSH process ($CPID) failure - Aborting" >&2
      exit 1
    fi
    ps -p $MPID >/dev/null 2>&1 || break
    sleep 1
  done

  kill $CPID
fi

exit $ret
