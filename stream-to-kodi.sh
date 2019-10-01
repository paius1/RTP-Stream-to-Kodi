#!/bin/bash 

# Stream media file to kodi
# add a .desktop file to ~/.local/share/file-manager/actions
# for Pcmanfm Custom Action
	# [Desktop Entry]
	# Type=Action
	# NoDisplay= false
	# Name[en_US]=RTP Stream to Kodi
	# Tooltip=RTP Stream to Kodi
	# ToolbarLabel[en_US]=RTP Stream to Kodi
	# Icon=applications-multimedia
	# Profiles=profile-zero;
	# Mimetypes=video/*;videos/*;
	# Categories=GTK;GNOME;Video;AudioVideo
	#
	# [X-Action-Profile profile-zero]
	#
	# MimeTypes=video/*;videos/*;
	# TryExec=/home/paul/bin/stream-to-kodi.sh
	# Exec=/home/paul/bin/stream-to-kodi.sh %f
	# SelectionCount==1
# or
	# [Desktop Entry]
	# Name[en_US]=RTP Stream to Kodi
	# Tooltip[en_US]=RTP Stream to Kodi
	# Icon=applications-multimedia
	# Type=Application
	# TryExec=yad
	# Exec=/home/paul/bin/stream-to-kodi.sh  
	# Categories=Gnome;Video;Multimedia;
# to ~/.local/share/applications for a menu listing
# calling from the menu requires yad to enter a file name
# 
#  c pl groves gmail 2019

# default kodi 
  KODI_HOST='192.168.0.xx'
  KODI_PORT='8080'
  KODI_USER='kodi'
  KODI_PASS=''
             
 if [[ -t 0 || -p /dev/stdin ]]; then # && [[ "$#" -lt 1 ]]; then
  # Called from terminal use  cat & read
    cli=true
    FILE=$1
 else
  # Called from .desktop
  # Using 'TryExec=yad' in the .desktop file eliminates menu listing
  # if we are uning pcmanfm it sends %XX for spaces, etc
    FILE=$(printf "%b\n" "${1//%/\\x}") 
       XMESSAGE=(xmessage  -center -title "Stream to Kodi" -geometry 600x80 -file -)
    if command -v yad >/dev/null 2>&1; then
       XMESSAGE=(yad --center "--width=630" "--height=140" "--window-icon=\"applications-multimedia\"" "--title=Stream-to-Kodi" --text-info )
    fi
 fi

  if [ -z "$FILE" ]; then
    if [ "$XMESSAGE" = "yad" ]; then
      if ! FILE=$( yad --title="Stream to Kodi" --window-icon="gtk-open" \
                       --center --width=300 --borders=10 \
                       --text="Choose a file to stream"  \
                       --form --separator="," \
                       --field="":SFL '' 2>/dev/null)
        then exit 1
      fi 
      FILE="${FILE::-1}"
    else
      [[ "$cli" != "true" ]] && 
        { "${XMESSAGE[@]}" <<<"  Usage: stream-to-kodi.sh filename"; exit 1; }
      read -r -p 'Filename: ' FILE
      [[ ! -f $FILE ]] && 
        { echo file $FILE doesn't exist"; exit 1; }
    fi
  else
    echo "Stream: $FILE"
  fi

# if multiple kodi players
  if [ ! "$XMESSAGE" = "xmessage" ]; then
    echo -e "\nChecking for Multiple Media Players on the network"
    MY_INTERFACE=$(ip addr | awk '/state UP/ {print $2}' | tr -d ':')
    KODIS=($(gssdp-discover -i "$MY_INTERFACE" --timeout=3 --target=urn:schemas-upnp-org:device:MediaRenderer:1|grep Location|sed 's:^.*/\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\).*:\1:'))
    if [ "${#KODIS[@]}" -gt 1 ]; then
       if [ "$XMESSAGE" = "yad" ]; then
         for kodi in "${KODIS[@]}"; do
           # Use names instead of dotted decimal notation this requires a valid host file
             kodiCB="${kodiCB}$(host "$kodi" | awk '{print substr($NF, 1, length($NF)-1)}')!"
           # Use dotted decimal notation 
            # kodiCB="${kodiCB}$(awk '{print $NF}' <<<"$kodi")!"
         done
         kodiCB=$(echo "$kodiCB" | rev | cut -c 2- | rev)
         if ! WHICH_KODI=$(  yad --window-icon="gtk-network" --title="Stream to Kodi" \
                             --center --width=270 --borders=20 \
                             --text="Select destination Host" \
                             --form --separator="," \
                             --field="":CB "$kodiCB" 2>/dev/null) 
          then exit 1
         fi 
         KODI_HOST="${WHICH_KODI::-1}"
       else
         echo -e "\n** Select Destination Host *******"
         for kodi in "${KODIS[@]}"; do
            ((i++)) 
           # Use names instead of dotted decimal notation this requires a valid host file
             echo "${i}) $(host "$kodi" | awk '{print $NF}'|tr '.' ' ')"
           # Use dotted decimal notation 
#             echo "${i}) $(awk '{print $NF}' <<<"$kodi")"
         done
         echo
         read -rp "Choose 1-$i: " n
         # Using host file
           KODI_HOST="$(host "${KODIS[$((n-1))]}" | awk '{print substr($NF, 1, length($NF)-1)}')"
         # Using dotted decimal notation 
           #KODI_HOST="$(awk '{print $NF}' <<<"${KODIS[$((n-1))]}")"
       fi
    fi
  else
    # Check KODI_HOST set by default
      echo "Checking $KODI_HOST"
      ! ping -c 1 "$KODI_HOST" >/dev/null 2>&1 && 
        { "${XMESSAGE[@]}" <<<"Destination $KODI_HOST not available"; exit 1; }
  fi

  function _kodi_request {
    output=$(curl -s -i -X POST --header "Content-Type: application/json" -d "$1" http://"$KODI_USER:$KODI_PASS@$KODI_HOST:$KODI_PORT"/jsonrpc)  
      [[ $2  ]] && echo "$output" | head -n1
}

  function _parse_json {
     awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'"$1"'\042/){print $(i+1)}}}' | tr -d '"' 
}

 function _cleanup() {
	 echo " Cleaning up ..."
    # Stop Playback
      output=$(_kodi_request '{"jsonrpc": "2.0", "method": "Player.GetActivePlayers", "id": 0}')
      player_id=$(echo "$output" | _parse_json "playerid")
      sleep 3
      _kodi_request "{\"jsonrpc\": \"2.0\", \"method\": \"Player.Stop\", \"params\": { \"playerid\": \"$player_id\" }, \"id\": 1}" 
    # Stop stream
        kill "$vlcPID" >/dev/null 2>&1 & wait "$vlcPID" >/dev/null 2>&1
        kill "$xmPID" >/dev/null 2>&1 & wait "$xmPID" >/dev/null 2>&1
}

# If this script is killed, kill child processess
  trap  _cleanup EXIT INT

# Setup Stream
  myPID="$$"
  MY_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
  MY_PORT=5004
  RTP="rtp://$MY_IP:$MY_PORT"

  echo -e "\nStarting Stream"
   # raw stream
#     (cvlc "$FILE" --sout "#rtp{access=udp,dst=$KODI_HOST,port=5004,mux=ts}" --no-sout-all  >/dev/null 2>&1)&  vlcPID=$!

   # transcode and scale
    ( cvlc  "$FILE" --sout "#transcode{vcodec=mp2v,vb=800,scale=0.24,acodec=mpga,ab=96,channels=2}:rtp{dst={$KODI_HOST},port=5004,mux=ts}" --no-sout-all >/dev/null 2>&1)&  vlcPID=$!

   # 720p TV
#    ( cvlc  "$FILE" --sout "#transcode{vcodec=h264,vb=1500,width=1280,height=720,acodec=mp3,ab=192,channels=2,samplerate=44100,scodec=none}:rtp{dst=$KODI_HOST,port=5004,mux=ts}" --no-sout-all --sout-keep )& vlcPID=$!
       
   # Give stream time to get going
     sleep 2

  echo -e "Sending request to $KODI_HOST"

    _kodi_request "{ \"jsonrpc\" : \"2.0\", \"id\" : 519, \"method\" : \"Player.Open\", \"params\" : { \"item\" : { \"file\" : \"${RTP}\"  }}}" true

  echo
# If started for the Desktop we need a way to stop the stream
  ( "${XMESSAGE[@]}" <<<"Started stream of $FILE to $KODI_HOST STOP WITH...
     pgrep -P $myPID | tee >(xargs kill 2>/dev/null) >(xargs wait 2>/dev/null)" 2>/dev/null)& xmPID=$!

  # Loop while streaming
echo CTRL C to exit
      now=$(date +%s)seconds
    while kill -0 "$vlcPID" 2> /dev/null; do
      sleep 1
      printf "%s\r" "$(TZ=UTC date --date now-"$now" +%H:%M:%S)"
    done
  echo -e "\nStream stopped ... "
