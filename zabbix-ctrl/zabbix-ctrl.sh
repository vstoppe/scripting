#!/bin/bash

set -e # Any subsequent(*) commands which fail will cause the shell script to exit immediately


##################################################
########## Lets prepare some variables: ##########
##################################################

trap "exit 1" TERM
export TOP_PID=$$


### Set some default Variables:
API_CFG="$HOME/.zabbix.cfg"
AUTHFILE="$HOME/.authfile"
AUTHTIME=180                     # Time in minutes to stay authenticated:
EXIT="kill -s TERM $TOP_PID"     # variable to exit in case of Error even the calling script
#PROTOCOL='https'

# If config file exists, the source it:
test -f "$API_CFG" && source $API_CFG
# Get the Zabbix authentication code from file if it exists:
test -f "$AUTHFILE" && AUTHCODE=$(<"$AUTHFILE")

### URL to authenticate against:
AUTHURL=$PROTOCOL://$ADDRESS/api_jsonrpc.php

### Curl Statement to communicate with Zabbix server:
CURL="curl --insecure --silent -n --request POST --header Content-Type:application/json -d@- $AUTHURL"

### Declare of some output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

### First parameter declares what operation will happen:
OPERATION=$1

### Check if jq is installed. If not, exit:
if [ "$(which jq &>/dev/null; echo $?)" -ne 0 ]; then
	echo jq is missing. Install \"jq\" package; exit;
fi



function filter_array_match() {
	local JSON_INPUT=$1
	local PROPERTY=$2 ## (eg. itemid / triggerid)
	local OBJECT_IDS  ## Here we will store the filtered ids

	# This function filters from the JSON-Output the values of a specific property-name
	if [ $# -ne 2 ]; then
		echo Function filter_array_match expects two parameters. Does the item name have white spaces?; $EXIT;
	fi

	OBJECT_IDS=$(echo "$JSON_INPUT" | jq --raw-output ".result | .[].$PROPERTY")
	### Variable $OBJECT_IDS must be outputted without quotes!
	echo $OBJECT_IDS
}



function get_hostid(){
	local -r HOST=$1    # Hostname to query
	local -i HOST_ID # Here we will save the host_id. If quere unsuccessfull then host_id=0
	local RESPONSE
	local -r REQUEST="{
		 \"jsonrpc\": \"2.0\",
		 \"method\": \"host.get\",
		 \"params\": {
			  \"output\": [\"hostid\"],
			  \"filter\": {\"host\":[\"$HOST\"]}
		 },
		 \"auth\": \"$AUTHCODE\",
		 \"id\": 2
		}"

	RESPONSE=$(echo "$REQUEST" | $CURL)
	# Cut out the Host-ID for the return value:
	HOST_ID=$(echo "$RESPONSE" | jq --raw-output '.result | .[].hostid')

	if [ "$HOST_ID" -ne 0 ];
		then echo "$HOST_ID"
	   else echo "Unknown host: $HOST"; exit 1
	fi
}



function get_lastvalue(){
	### prints the last value of an item.
	local -r HOST_NAME=$2
	local -r ITEM=$3
	local    RESPONSE
	local    LASTVALUE

	if [ -z "$HOST_NAME" ] || [ -z "$ITEM" ]; then
		echo "get-lastvalue expects two Parameters:"
		echo "apiXX.sh get-lastvalue [HOSTNAME] [ITEMNAME]"
		exit
	fi

	### Create the request variable:
	local -r REQUEST="{
		 \"jsonrpc\": \"2.0\",
		 \"method\": \"item.get\",
		 \"params\": {
			  \"output\": [\"lastvalue\"],
			  \"host\": \"$HOST_NAME\",
			  \"search\": {\"key_\": \"$ITEM\"}
		 },
		 \"auth\": \"$AUTHCODE\",
		 \"id\": 2
		}"

	RESPONSE=$(echo "$REQUEST" | $CURL)
	LASTVALUE=$(echo "$RESPONSE" | jq --raw-output '.result | .[].lastvalue')

	if [ -n "$LASTVALUE" ];
		then echo "$LASTVALUE";
		else echo "Item $ITEM does not exist on host $HOST_NAME."; $EXIT;
	fi
}



function get_ifid(){
	### get_ifid [HOSTNAME] [IFTYPE]
	local -r HOST_NAME=$1
	local -i HOST_ID
	local    REQUEST
	local    RESPONSE
	local -r INTERFACE_TYPE=$2
	local    INTERFACE_ID # Save the numeric id of the network interface

	case $INTERFACE_TYPE in
		agent) local TYPE=1;;
		snmp)  local TYPE=2;;
		ipmi)	 local TYPE=3;;
		jmx)   local TYPE=4;;
		*) echo You have to set the right interface-type: agent, snmp, ipmi or jmx >&2; $EXIT;;
	esac

	HOST_ID=$(get_hostid "$HOST_NAME")
	REQUEST="{
		\"jsonrpc\": \"2.0\",
		\"method\": \"hostinterface.get\",
		\"params\": {
			\"output\": [\"extend\"],
			\"filter\": {\"type\":[\"$TYPE\"]},
			\"hostids\": \"$HOST_ID\"
	},
		\"auth\": \"$AUTHCODE\",
		\"id\": 2
	}"

	RESPONSE=$(echo "$REQUEST" | $CURL )
	INTERFACE_ID=$(echo "$RESPONSE" | jq --raw-output '.result | .[].interfaceid')

	if [ -n "$INTERFACE_ID" ];
		then echo "$INTERFACE_ID"
		else echo "Interface $INTERFACE_TYPE not available on host $HOST_NAME"
	fi
}



function create_application(){
	local -r APPNAME=$1
	local -r HOST_NAME=$2
	local    HOST_ID=$(get_hostid "$HOST_NAME")
	local -i APPLICATION_ID
	local    RESPONSE_ERROR

	if [ "$#" -ne "2" ]; then
		echo "Invalid number of parameters for function \"create_application\": $1 $2 $3 $4 $5" >&2 ; $EXIT;
	fi

	local -r REQUEST="{
		\"jsonrpc\": \"2.0\",
		\"method\": \"application.create\",
		\"params\": {
			\"name\": \"$APPNAME\",
			\"hostid\": \"$HOST_ID\"
		},
		\"auth\": \"$AUTHCODE\",
		\"id\": 2}"

	RESPONSE=$(echo "$REQUEST" | $CURL)
	### Get possible error messages from response...
	RESPONSE_ERROR=$(echo "$RESPONSE" | jq --raw-output '.error';)
	### If there is null error, then extract the new application_id and print it:
	if [ "$RESPONSE_ERROR" == "null" ]; then
			APPLICATION_ID=$(echo "$RESPONSE" | jq --raw-output '.result.applicationids | .[]');
			echo "$APPLICATION_ID"
		else echo "$RESPONSE_ERROR"; exit 1
	fi
}



function get_appid(){
	### get-appid [APPNAME] [HOST]
	### depends on functions:
	### * get_hostid
	### * create_application
	### call: get_appid APP HOST
	# If the application does not exist on this host, then it has to be created:
	if [ "$#" -ne "2" ]; then echo "Invalid number of parameters for function \"get_appid\": $1 $2 $3 $4 $5." >&2; exit 1; fi
	local APPLICATIONS=$(echo $1 | sed 's/,/ /g')
	local -r HOST_NAME=$2
	local    HOST_ID

	HOST_ID=$(get_hostid "$HOST_NAME")
	for APPLICATION in $APPLICATIONS; do
	out="`$CURL 2> /dev/null  << EOF
	{
	    "jsonrpc": "2.0",
	    "method": "application.get",
		"params": {
	        "output": ["name","applicationid"],
	        "hostids": "$HOST_ID",
	    	"filter": {"name": ["$APPLICATION"]}
	    },
	    "auth": "$AUTHCODE",
	    "id": 2
	}
EOF`"

	out=$(echo -n "$out " | cut -d\" -f10)
	if [ -z "$out" ]; then create_application "$APPLICATION" "$HOST_NAME"; else echo "$out"; fi
	done
}


function declare_vars() {

## to the function passed variables are checked and declared to working variables.

	for i in "${@}"
	do
		if [[ "$i" == *=* ]]; then declare "$i"; fi
	done


	#if [ ! -z "$user"  ]; then export USER=$user;fi
	if [ -n "$pass"  ]; then export PASS=${pass};fi
	if [ -n "$host"  ]; then
		export HOST=$host;
		else HOST=$(hostname);
	fi

	### If we are not authenticating, get the hosid:
	if [ "$OPERATION" != 'auth' ] && [ "$OPERATION" != 'update-trigger' ] ; then
		export HOST_ID=$(get_hostid $HOST)
	fi


	if [ -n "$delta" ]; then
		case $delta in
			""|asis) export DELTA_LINE="";;
			speed)   export DELTA_LINE="\"delta\":1,";;
			simple)  export DELTA_LINE="\"delta\":2,";;
			*) echo "You have passed a wrong value for delta. Take: \"asis\" (default), \"speed\" (per second), or \"simple\" (change)"; $EXIT;;
		esac
	fi

	if [ -n "$type" ]; then
		case $type in
			zabbix-agent)        export TYPE_ID=0;;
			snmpv1)              export TYPE_ID=1;;
			zabbix-trapper)      export TYPE_ID=2;;
			simple-check)        export TYPE_ID=3;;
			snmpv2)              export TYPE_ID=4;;
			internal)            export TYPE_ID=5;;
			snmpv3)              export TYPE_ID=6;;
			zabbix-agent-active) export TYPE_ID=7;;
			*) echo Invalid item type. Possible values are: zabbix-agent, zabbix-agent-active, zabbix-trapper simple-check; exit;;
		esac



		# Select one interface-id according to the item-type
		case $type in
			snmp*) export IFID_LINE="\"interfaceid\":`get_ifid $HOST snmp`,"  ;;
			ipmi)  export IFID_LINE="\"interfaceid\":`get_ifid $HOST ipmi`,"  ;;
			jmx)   export IFID_LINE="\"interfaceid\":`get_ifid $HOST jmx `,"  ;;
			*)     export IFID_LINE="";;
		esac
	fi


	# Convert the name of the data type to an data-id:
	if [ -n "$data" ]; then
		case $data in
			numfl) export DATA_ID=0;;
			char)  export DATA_ID=1;;
			log)   export DATA_ID=2;;
			numun) export DATA_ID=3;;
			text)  export DATA_ID=4;;
			*) echo Inavalid name for data type possible values: numfl, char, log, numun, text >&2 ; $EXIT;;
		esac
	fi

	if [ -n "$name" ]; then NAME="$name"; fi
	#echo NAME aus declare-vars: $NAME >&2

	# Prepare for application/s:
	if [ -n "$app" ]; then
		export APP=$app;
		export APP_ID=$(get_appid $APP $HOST | while read ID; do echo -n "$ID "; done)
		export APPLICATION_LINE="\"applications\":[\"`echo -n $APP_ID | sed 's/ /\",\"/g'`\"],";
	fi

	# Set SNMP parameter if needed:
	if [ -n "$oid" ];       then export SNMPOID_LINE="\"snmp_oid\":\"$oid\",";                 fi
	if [ -n "$community" ]; then export COMMUNITY_LINE="\"snmp_community\":\""$community"\","; fi

	# Set the interval of an item
	if [ -n "$interv" ] && [ "$interv" -gt 60 ]; then export INTERV=$interv; fi

	# Assign the description
	if [ -n "$desc" ]; then
		export DESC_LINE=\"description\":\""$desc"\"\,
	fi

	# If "key" is empty and no trapper item, we have to demand an item key
	if [ -n "$key" ]; then
		export KEY_LINE=\"key_\":\"$key\"\,
	elif [ "${FUNCNAME[0]}" == "create_item" ] && [ "$TYPE_ID" -ne "2" ]; then
			echo "For this check a key is mandatory!" >&2; EXIT;
	fi


	# Define data storage periodes:
	if [ -n "$hist" ];  then export HISTORY=$hist; fi
	if [ -n "$trend" ]; then export TRENDS=$trend; fi


	# set muliplyer and also enable it
	if [ -n "$multi" ]; then export MULTI_STR=\"formula\":$multi,\"multiplier\":1,; else MULTI_STR=""; fi
	if [ -n "$unit" ];  then export UNIT_STR=\"units\":\"$unit\",; else UNIT_STR=""; fi


	### Property to enable or disable an item:
	if [ -n "$status" ]; then
		case $status in
			en|enable)	 export STATUS_LINE=\"status\":\"0\"\, ;;
			dis|disable) export STATUS_LINE=\"status\":\"1\"\, ;;
			*)           echo "Status has to be en[able] or dis[able]"; $EXIT;;
		esac
	fi

	### Variables for graph creating
	if [ -n "$width" ]; then WIDTH=$width; fi
	if [ -n "$hight" ]; then HIGHT=$hight; fi
	if [ -n "$itemids" ]; then ITEM_IDS=(`echo $itemids| sed 's/,/ /g' `);fi

	if [ -n "$items" ]; then
		if [ -z "$host" ]; then echo Hostname is mandatory if you add items by name; $EXIT;
		elif [ -z $ITEM_IDS ]; then
			export ITEMS=$(echo $items | sed 's/,/ /g');
			#eval ITEM_IDS=(`for item in ${ITEMS[@]}; do get_ids type=i hostid=$HOST_ID search="$item"; done`)
		fi
	fi

	### Create variable for trigger condition
	if [ -n "$cond" ];   then export COND=$cond; fi

	### if itemname is passed then delcare it:
	if [ -n "$item" ];   then export ITEM="$item"; fi

	### the warnlevel is used when creating or updating triggers
	if [ -n "$warnlv" ];
		then export WARN="$warnlv";
		else export WARN=\>90;
	fi;

	### If no priority for a trigger is defined, take "Warn"
	if [ -z "$prio" ];   then export priority="warn"; else export priority=$prio; fi;


	# If a trigger-id for a trigger-dependency is passed, then build the line for the dependeny:
	if [ -n "$dep" ]; then DEPENDENCY_LINE="\"dependencies\": [{\"triggerid\": \"$dep\"}],";
		else DEPENDENCY_LINE="" ;
	fi;


}



function auth() {
### Function to authenticate a user:
### auth user=USERNAME

declare_vars "${@}"

if [ -z "$USER"  ]; then echo \"user=\"[name] in mandatory for authorisation; $EXIT; fi
if [ -z "$PASS"  ]; then echo -n "Password: "; read -s PASS  ; fi

auth=`$CURL 2>/dev/null << EOF
{
   "jsonrpc": "2.0",
   "method": "user.login",
   "params": {
      "user": "$USER",
      "password": "$PASS"
   },
   "id": 1
}
EOF`
#echo $auth
AUTHCODE=`echo $auth | cut -d\" -f8`
echo $AUTHCODE > "$AUTHFILE"
chmod 600 $AUTHFILE

if [ `cat $AUTHFILE | wc -c` -eq 33 ];
	then
		echo; echo "Authorisation successful";
		echo "rm $AUTHFILE" | at now+${AUTHTIME}min
	else
		echo; echo "Authorisation failed!"
fi
}



function create_item(){
	### set some default values
	APP="";     # Application (z.B. CPU, JBoss)
	TYPE_ID=2   # "zabbix-trapper"
	DATA_ID=3   # Default "number unsigned"; can be reset by $DATA
	INTERV=60;  # please do not check in shorter intervals then 60 seconds (high data volume)
	HISTORY=30; # time how long values will be saved?
	TRENDS=90;  # how log will trends be saved?

	declare_vars "${@}"


	if [ -z $HOST ]; then echo \"host\"name is mandatory!; $EXIT; fi
	if [ -z $NAME ]; then echo Item\"name\" is mandatory!; $EXIT; fi



	RESULT="`$CURL 2>/dev/null << EOF
	{
		"jsonrpc": "2.0",
		"method": "item.create",
		"params": {
			"name": "$NAME",
			$MULTI_STR
			$UNIT_STR
			$KEY_LINE
			$DELTA_LINE
			$DESC_LINE
			$SNMPOID_LINE
			$COMMUNITY_LINE
			"hostid": "$HOST_ID",
			"type": $TYPE_ID,
			"value_type": $DATA_ID,
			$IFID_LINE
			$APPLICATION_LINE
			"delay": "$INTERV",
			"history": "$HISTORY",
			"trends": "$TRENDS"
		},
		"auth": "$AUTHCODE",
		"id": 2
	}
EOF`"
	echo $RESULT
   if [ $(echo $RESULT | grep -e error -e No | wc -l) -ne 0 ]; then
		echo -n "`date +%Y-%m.%d-%H:%M:%S` ";
		echo "`date +%Y-%m.%d-%H:%M:%S` " $RESULT | cut -d\" -f11-19 | sed -e 's/:"//g' -e 's/\\"/ /g' -e 's/"."/ /g' -e 's/"/ /' -e 's/\\/ /g'
	else RESULT=`echo $RESULT | cut -d\" -f10 `;
		#echo "`date +%Y-%m.%d-%H:%M:%S` Item: \"$NAME\" with ID: \"$RESULT\" on Host: $HOST successfully created" >&2;
		echo "`date +%Y-%m.%d-%H:%M:%S` Item \"$RESULT\" successfully created: $HOST:$NAME" >&2;
	fi
}



function update_item(){
	### set some default values
	APP="";     # Application (z.B. CPU, JBoss)
	TYPE_ID=2   # "zabbix-trapper"
	DATA_ID=3   # Default "number unsigned"; can be reset by $DATA
	INTERV=60;  # please do not check in shorter intervals then 60 seconds (high data volume)
	HISTORY=30; # time how long values will be saved?
	TRENDS=90;  # how log will trends be saved?

	###--> Process the item-id
	if [ ! -z $id ]; then
		ID=$id;
		ID_LINE=\"itemid\":\"$ID\"
		else
			echo Item id=\"ID-Number\" is mandatory!; $EXIT;
	fi



	if [ ! -z $data ]; then
		case $data in
			numfl) DATA_ID=0;;
			char)  DATA_ID=1;;
			log)   DATA_ID=2;;
			numun) DATA_ID=3;;
			text)  DATA_ID=4;;
			*) echo Ungueltiger Wertetyp für Datentyp, moegliche Werte: numfl, char, log, numun, text; exit;;
		esac
	fi
	if [ -n "$app" ];   then APP=$app; fi
	if [ -n "$hist" ];  then HISTORY=$hist; fi
	if [ -n "$trend" ]; then TRENDS=$trend; fi

	###--> Define the muliplier
	if [ -n "$multi" ]; then MULTI_STR=\"formula\":$multi,\"multiplier\":1,; else MULTI_STR=""; fi

	###--> Set the unit of the item
	if [ -n "$unit" ];  then UNIT_STR=\"units\":\"$unit\",; else UNIT_STR=""; fi

	# with the for loop a newline is omitted
#	APP_ID=$(get_appid $APP $HOST | while read ID; do echo -n "$ID "; done)
	APPLICATION_LINE="\"applications\":[\"`echo -n $APP_ID | sed 's/ /\",\"/g'`\"],";

		RESULT="`$CURL 2>/dev/null << EOF
		{
		   "jsonrpc": "2.0",
			"method": "item.update",
		   "params": {
		   $DELTA_LINE
			$DESC_LINE
		   $KEY_LINE
			$MULTI_STR
			$STATUS_LINE
			$UNIT_STR
		   $ID_LINE
		    },
		    "auth": "$AUTHCODE",
		    "id": 2
		}
EOF`"
		#echo $RESULT
		if [ $(echo $RESULT | grep error | wc -l) -ne 0 ]; then
				echo -n "`date +%Y-%m.%d-%H:%M:%S` " >&2 ;
				echo "`date +%Y-%m.%d-%H:%M:%S` " $RESULT | cut -d\" -f11-19 | sed -e 's/:"//g' -e 's/\\"/ /g' -e 's/"."/ /g' -e 's/"/ /' -e 's/\\/ /g' >&2
			else
				echo "`date +%Y-%m.%d-%H:%M:%S` Updating Item $ID on $HOST successfull" >&2 ;
			fi
	}



	function create_trigger(){
		PRIO_ID=2  # Default warn-level: warning; otherwise default, info, warn, avg, high, disaster
		WARN=90

		declare_vars "${@}"


		case $priority in
			default)  PRIO_ID=0;;
			info) 	 PRIO_ID=1;;
			warn)     PRIO_ID=2; WARN_DESC=Warnung ;;
			avg)	    PRIO_ID=3;;
			high)     PRIO_ID=4; WARN_DESC=Kritisch ;;
			disaster) PRIO_ID=5;;
			*) echo Falscher Wert fuer Prioritaet eingegeben. Gueltige Werte: default, info, warn, avg, high, disaster; exit;;
		esac
		#echo Triggername in create-trigger function: $name >&2
		### If no name ($DESC) is set for the trigger, then then name is built from Itemname and Macro {$ITEM_LASTVALUE}
	   #	"description": "$DESC",
		if [ ! -z "$NAME" ]; then
			DESC="$NAME";
			DESC_LINE=\"description\":\ \"${NAME}\"\,
		else
			DESC="$ITEM $WARN_DESC $WARN";
			DESC_LINE=\"description\":\"${ITEM}:\ {ITEM.LASTVALUE}\"\,
		fi

		RESULT="`$CURL 2>/dev/null << EOF
		{
		"jsonrpc": "2.0",
		"method": "trigger.create",
		"params": {
			$DESC_LINE
			"expression": "{$HOST:$ITEM.$COND}$WARN",
			$DEPENDENCY_LINE
			"priority": "$PRIO_ID"
		},
		"auth": "$AUTHCODE",
		"id": 2
		}
EOF`"
	#echo $RESULT

   if [ "$(echo $RESULT | grep already\ exists     | wc -l)" -gt 0 ]; then echo "`date +%Y-%m.%d-%H:%M:%S` Trigger $DESC already exists" >&2     ; fi;
	if [ "$(echo $RESULT | grep item\ key | grep Incorrect | wc -l)" -gt 0 ]; then echo "`date +%Y-%m.%d-%H:%M:%S` Item for Trigger $DESC" not found >&2 ; $EXIT; fi;
	if [ "$(echo $RESULT | grep trigger\ expression | wc -l)" -gt 0 ]; then echo "`date +%Y-%m.%d-%H:%M:%S` Wrong trigger-expression for $DESC" >&2 ; $EXIT; fi;
	if [ "$(echo $RESULT | grep triggerids | wc -l)" -gt 0 ]; then
		#echo "`date +%Y-%m.%d-%H:%M:%S` Erstellen von Trigger $DESC auf $HOST erfolgreich" >&2;
		echo "`date +%Y-%m.%d-%H:%M:%S` Trigger successfully created: ${HOST}:${DESC}" >&2;
		echo $RESULT | cut -d\" -f10;
	fi
	unset name NAME DESC_LINE ITEM COND DEPENDENCY_LINE
}






function update_trigger(){

	declare_vars "${@}"

	PRIO_ID=2  # Default warn-level: warning; sonst default, info, warn, avg, high, disaster

	## to the function passed variables are checked and declared de working variables.
        ## if an exception occuress then exit
        for i in "${@}"
        do
                if [[ $i == *=* ]]; then declare "$i"; fi
        done

	# An Funktion uebergebene Variablen erden ueberprüft und Verarbeitungsvariablen zugewiesen.
	# Wenn Fehler, dann exit:
	if [ -z "$ITEM" ] & [ -n "$COND" ];   then echo \"item\"-name is mandatory!; $EXIT; fi
	if [   -z "$prio" ];   then prio="warn"; fi;
	if [ -n "$COND" ];   then
		### If we want to change the trigger-condition, wie also need an item
		if [ -z "$ITEM"   ];   then echo \"item\"-name is mandatory in case of condition update!; fi
		COND=$cond;
		EXPRESSION_LINE=\"expression\":\"{$HOST:$ITEM.$COND}$WARN\",
		else  EXPRESSION_LINE=""
	fi
	#echo Condition: $COND
	#echo Expression: $EXPRESSION_LINE
	# If a trigger-id for a trigger-dependency is passed, then build the line for the dependeny:
	if [ -n "$dep" ]; then DEPENDENCY_LINE="\"dependencies\": [{\"triggerid\": \"$dep\"}],";
	else DEPENDENCY_LINE="" ;
	fi;



	###--> Process the trigger-id
	if [ -n "$id" ]; then
		ID=$id
		ID_LINE=\"triggerid\":\"$id\"
		else
			echo Item id=\"Trigger-ID" is mandatory\!"; $EXIT;
	fi

	###--> Process commentary field of trigger
	if [ -n "$comment" ]; then
		COMMENT_LINE=\"comments\":\"$comment\"\,
		else COMMENT_LINE="";
	fi


	###--> Process URL field of trigger
	if [ -n "$url" ]; then
		URL_LINE=\"url\":\"$url\"\,
		else URL_LINE="";
	fi

	### Property to enable or disable an item:
	if [ -z "$status" ]; then
		STATUS_LINE="";
		else
		case $status in
			en|enable)	 STATUS_LINE=\"status\":\"0\"\, ;;
			dis|disable) STATUS_LINE=\"status\":\"1\"\, ;;
			*)           STATUS_LINE="";;
			#*)           echo "Status has to be en[able] or dis[able]"; $EXIT;;
		esac
	fi


	RESULT="`$CURL 2>/dev/null << EOF
		{
		"jsonrpc": "2.0",
		"method": "trigger.update",
		"params": {
			$STATUS_LINE
			$EXPRESSION_LINE
			$COMMENT_LINE
			$URL_LINE
			$ID_LINE
		},
		"auth": "$AUTHCODE",
		"id": 2
		}
EOF`"


	if [ "$(echo "$RESULT" | grep -c trigger\ expression)" -gt 0 ]; then echo "$(date +%Y-%m.%d-%H:%M:%S) wrong trigger expression fuer $DESC" >&2 ; $EXIT; fi;
	if [ "$(echo "$RESULT" | grep -c triggerids)" -gt 0 ]; then
		echo "$(date +%Y-%m.%d-%H:%M:%S) Trigger $ID successfully updated" >&2
	fi

}



function get_group_ids() {
	#Parameters
	# * groups=[groupname1],[groupnameN]
	if [ $# -ne 1 ];then echo Wrong number of parameters for get_group_ids; fi
	# Declare passed parameters as variables:
	declare $1;
	### "," ist substitute throug '","' to match JSON-Syntax later
        if [ ! -z $groups ];  then GROUP=$(echo $groups | sed -e 's/,/\",\"/g'); else echo No \"groups\"-parameter defined for fucntion get_group_ids; exit; fi

	RESULT="`$CURL 2>/dev/null << EOF
	{
		"jsonrpc": "2.0",
		"method": "hostgroup.get",
		"params": {
			"output": "shorten",
			"filter": { "name": [ "$GROUP" ] }
		},
		"auth": "$AUTHCODE",
		"id": 2
	}
EOF`"
	# Filter groupids out of result
	GROUP_IDS=`filter_array_match $RESULT groupid`

	if [ -z "$GROUP_IDS" ]; then echo No groups $GROUP found >&2 ; $EXIT;
		else echo $GROUP_IDS; fi
}


function get_ids() {
	# Declare passed parameters as variables:
        for i in "${@}"
        do
                if [[ $i == *=* ]]; then declare "$i"; fi
        done

        if [ -z "$host" ] && [ -z "$groups" ] && [ -z "$hostid" ] && [ -z "$groupid" ]; then
        		echo \"host/id\" or host\"group/id\" is mandatory; exit;
        fi
        if [ ! -z $host ] && [ ! -z $groups ]; then echo Only one Parameter allowed: \"host\" or host\"group\"; exit; fi

	### The OBJECT_FILTER contains the string for the JSON-Syntax, as a search criteria
        if [ ! -z $host  ];  then OBJECT_FILTER=\"hostid\":[\"$(get_hostid $host)\"]; fi
        if [ ! -z $hostid ]; then OBJECT_FILTER=\"hostid\":[\"$hostid\"]; fi
        if [ ! -z $groups ]; then OBJECT_FILTER=\"groupid\":\"$(get_group_ids groups=$groups)\"; fi
        if [ ! -z $groupid ]; then OBJECT_FILTER=\"groupid\":\"$groupid\"; fi
        #if [ ! -z "$search" ]; then SEARCH="$search"; else echo \"search\"-string is mandatory!; exit; fi
        if [ ! -z "$search" ]; then SEARCH="`echo $search| sed 's/\,/ /g'`"; else echo \"search\"-string is mandatory!; exit; fi

	### SRC_Field: property of object in which the string is search:
	### and for triggers it is "description" for items its "name"
	if [ ! -z $type ]; then case $type in
					i|item)    OBJECT_TYPE=item;    SRC_FIELD=name;;
					t|trigger) OBJECT_TYPE=trigger; SRC_FIELD=description;;
					g|graph)   OBJECT_TYPE=graph; SRC_FIELD=name;;
					*) echo Unknown Object-Type \"$type\"; $EXIT;;
				esac
	else echo \"type=\" is mandatory!; $EXIT; fi

for obj in ${SEARCH[@]}; do
	RESULT="`$CURL 2>/dev/null << EOF
		{
		"jsonrpc": "2.0",
		"method": "$OBJECT_TYPE.get",
		"params": {
			"output": ["status", "$SRC_FIELD", "triggerid"],
			"filter": { $OBJECT_FILTER },
			"searchWildcardsEnabled":"true",
			"search": { "$SRC_FIELD":"$obj" }
			},
		"auth": "$AUTHCODE",
		"id": 2
		}
EOF`"
	#echo $RESULT
	filter_array_match "$RESULT" "${OBJECT_TYPE}id"
done
}


function object_show() {
	unset  IDS
	# Declare passed parameters as variables:
        for i in "${@}"
        do
                if [[ $i == *=* ]]; then declare "$i"; fi
        done

        if [ -z "$host" ] && [ -z "$groups" ] && [ -z "$hostid" ] && [ -z "$groupid" ]; then
        		echo \"host/id\" or host\"group/id\" is mandatory; exit;
        fi
        if [ ! -z $host ] && [ ! -z $groups ]; then echo Only one Parameter allowed: \"host\" or host\"group\"; exit; fi

	### The OBJECT_FILTER contains the string for the JSON-Syntax, as a search criteria
        if [ ! -z $host  ];   then OBJECT_FILTER=\"hostid\":[\"$(get_hostid $host)\"]; fi
        if [ ! -z $hostid ];  then OBJECT_FILTER=\"hostid\":[\"$hostid\"]; fi
        if [ ! -z $groups ];  then OBJECT_FILTER=\"groupid\":\"$(get_group_ids groups=$groups)\"; fi
        if [ ! -z $groupid ]; then OBJECT_FILTER=\"groupid\":\"$groupid\"; fi
        if [ -z "$search" ]   && [ -z "$ids" ]; then echo \"search\"-string or \"ids=\" is mandatory!; $EXIT; fi
        if [ ! -z "$search" ] && [ -z "$ids" ]; then SEARCH="$search"; fi
        if [ -z "$search" ]   && [ ! -z "$ids" ]; then IDS=`echo $ids | sed 's/,/\",\"/g'` ; fi
        if [ ! -z $out ];
        		then OUT_LINE=\"output\":[\"`echo $out | sed 's/,/\",\"/g'`\"], ;
        		else OUT_LINE=\"output\":[\"{OBJECT_TYPE}id\"],
        fi

	### SRC_Field: property of object in which the string is search:
	### and for triggers it is "description" for items its "name"
	if [ ! -z $type ]; then case $type in
					i|item)    OBJECT_TYPE=item;    SRC_FIELD=name;;
					g|graph)    OBJECT_TYPE=graph;    SRC_FIELD=name;;
					t|trigger) OBJECT_TYPE=trigger; SRC_FIELD=description;;
					*) echo Unknown Object-Type \"$type\"; $EXIT;;
				esac
	else echo \"type=\" is mandatory!; $EXIT; fi
	if [ ! -z "$IDS" ];
		then echo "Zusammensetzen der Searchline";
			SEARCH_LINE=\"search\":{\"${OBJECT_TYPE}id\":\[\"${IDS}\"\]} ;
		else SEARCH_LINE=\"search\":{\"$SRC_FIELD\":\"${SEARCH}\"}
	fi

	RESULT="`$CURL 2>/dev/null << EOF
		{
		"jsonrpc": "2.0",
		"method": "${OBJECT_TYPE}.get",
		"params": {
			$OUT_LINE
			"filter": { $OBJECT_FILTER },
			"searchWildcardsEnabled":"true",
			$SEARCH_LINE
			},
		"auth": "$AUTHCODE",
		"id": 2
		}
EOF`"
	#echo Resultate $RESULT
	### Strip of characters of the JSON-Output
	RESULT=`echo $RESULT| sed -e 's/^.*\[{//' -e 's/},{/\n/g' -e 's/}\].*$//'`
	IFS=\"
	HEADLINE=(`echo "$RESULT" | head -n 1 | sed 's/,/ /g' `)
	n=1
	for i in ${HEADLINE[@]}; do
		if [[ "$out" == *${HEADLINE[$n]}* ]]; then echo -en \\t${HEADLINE[$n]}\\t; fi
		((n++))
	done
	### from here on the Output-Matrix/table of all objetcs and items will be processed
	echo ""
   echo "$RESULT" | while read line; do
   	n=1
   	LINE=(`echo "$line" | sed 's/:/ /g'`)
   	#echo ${LINE[@]}
   	for i in ${LINE[@]}; do
   		if [[ "$out" == *${LINE[$n]}* ]]; then
				case ${LINE[$n]} in
					# the Status of an item will not be display as "0" or "1" but as "enabled" or "disabled"
					status) if [ ${LINE[$n+2]} -eq 0 ]; then
						echo -en ${GREEN}enabled${NOCOLOR}; else
						echo -en ${RED}disabled${NOCOLOR};
					fi ;;
					*) echo -en ${LINE[$n+2]}\\t; ;;
				esac
   		fi
   		if [ $n -eq ${#LINE[@]} ]; then echo; fi
   		((n++))
   	done
	done
	#set +x
	#filter_array_match "$RESULT" "${OBJECT_TYPE}id"
}




function create_screen() {

	## to the function passed variables are checked and declared  as working variables.
   ## if an exception occuress ten exit
        for i in "${@}"
        do
                if [[ $i == *=* ]]; then declare $i; fi
        done

	if [ ! -z $name  ]; then NAME=$name; else echo Screen\"name\" is mandatory!; $EXIT; fi
	if [ ! -z $host  ]; then HOST=$host; fi
	if [ ! -z $hsize ]; then HSIZE=$hsize; else HSIZE=4; fi
	if [ ! -z $vsize ]; then VSIZE=$vsize; else VSIZE=1; fi

	### Assign ressource type numbers
	case $rtype in
		graph)    RTYPE=0; RTYPE_DESC="graph";;
		sgraph)   RTYPE=1; RTYPE_DESC="simple graph";;
		map)	  RTYPE=2; RTYPE_DESC="map";;
		text)	  RTYPE=3; RTYPE_DESC="plain text";;
		host)	  RTYPE=4; RTYPE_DESC="hosts info";;
		triginfo) RTYPE=5; RTYPE_DESC="triggers info";;
		srvinfo)  RTYPE=6; RTYPE_DESC="server info";;
		clock)	  RTYPE=7; RTYPE_DESC="clock";;
		screen)   RTYPE=8; RTYPE_DESC="screen";;
		trigov)	  RTYPE=9; RTYPE_DESC="triggers overview";;
		dataov)	  RTYPE=10; RTYPE_DESC="data overview";;
		url)	  RTYPE=11; RTYPE_DESC="URL";;
		histac)	  RTYPE=12; RTYPE_DESC="history of actions";;
		histav)	  RTYPE=13; RTYPE_DESC="history of events";;
		stathgt)  RTYPE=14; RTYPE_DESC="status of hostgroup triggers";;
		sysstat)  RTYPE=15; RTYPE_DESC="system status";;
		trigstat) RTYPE=16; RTYPE_DESC="status of host triggers";;
		"") echo "ressource type (rtype=) ist mandatory"; $EXIT;;
		*)  echo You have passed a wrong type of ressource; $EXIT;;
	esac

	if [ -z $objects ]; then
		echo You have to pass at least one $RTYPE_DESC object; $EXIT;
		### splict comma seperated values of passed variable OBJECTS to array-variable
		else i=0; OBJECTS=`echo $objects | sed s'/,/ /g' `;
		case $RTYPE in
			0) OBJECT_IDS=(`for SCREEN_ITEM in ${OBJECTS[@]}; do get_ids type=graph host=$HOST search=$SCREEN_ITEM; done`);;
			1) OBJECT_IDS=(`for SCREEN_ITEM in ${OBJECTS[@]}; do get_ids type=item host=$HOST search=$SCREEN_ITEM; done`);;
			*) echo This ressource type is not implemented yet;;
		esac
	fi
	### calculate the number of tiles for the screen, all objects have to fit in.
	# if vsize*hsize is smaller then [number of objects] , then
	# * [number of objects] / hsize = [2nd vsize]
	# * if [number of objects] < [2nd vsize]*hsize then increase vsize+1
	let NUM_FIELDS="$HSIZE * $VSIZE";
	if [ $NUM_FIELDS -lt ${#OBJECT_IDS[@]} ]; then
		let "VSIZE=${#OBJECT_IDS[@]}/$HSIZE"; if  [ $NUM_FIELDS -lt ${#OBJECT_IDS[@]} ]; then let VSIZE="$VSIZE+1"; fi
	fi

	#set horizontal and vertical  counter variables for for matrix building
	h=0; v=0;
	# set object counter: if object counter reaches the last element of the array
	# then do not add a "," at the end of the line, otherwise it would be no valid JSON-Syntax
	c=1
	RESSOURCE_BLOCK=`
	### Here we build up the matrix of the screen
	# because "x" and "y" start at "0" we have de decrease them by one
	let HSIZE="$HSIZE-1"
	let VSIZE="$VSIZE-1"
	for OBJECT in ${OBJECT_IDS[@]}; do echo
		echo -n \{\"resourcetype\":$RTYPE,\"resourceid\":"$OBJECT",\"x\":$h,\"y\":$v\};
		if [ "${#OBJECT_IDS[@]}" -ne "$c" ]; then echo -n ","; fi
		((h++)); ((c++)); if [ $h -gt $HSIZE ]; then h=0; ((v++));fi;
	done`

	RESULT="`$CURL 2>/dev/null << EOF
	{
	    "jsonrpc": "2.0",
		"method": "screen.create",
	    "params": {
		"name": "$NAME",
		"hsize":$HSIZE,
		"vsize":$VSIZE,
		"screenitems": [
		$RESSOURCE_BLOCK
		]
	    },
	    "auth": "$AUTHCODE",
	    "id": 2
	}
EOF`"
	if [ "$(echo $RESULT | grep is\ already\ taken | grep cell | wc -l)" -gt 0 ]; then echo "`date +%Y-%m.%d-%H:%M:%S` echo Cell is used by another object" ; $EXIT; fi;
	if [ "$(echo $RESULT | grep result | grep screenids | wc -l)" -gt 0 ]; then echo "`date +%Y-%m.%d-%H:%M:%S` Screen $NAME created" ; fi;
}


function create_graph(){
	### set some default values
	typeset -i WIDTH=600;
	HIGHT=200;
	COLORS=(C80000 00C800 0000C8 C800C8 00C8C8 C8C800 C8C8C8 960000 009600 000096 960096 \
		     009696 969600 969696 FF0000 00FF00 0000FF FF00FF 00FFFF FFFF00 FFFFFF)

	declare_vars "${@}"

	[ -z "$NAME" ] && { echo Graph\"name\" is mandatory!; $EXIT; }

	echo "create-graph/ITEMS: $ITEMS"
	echo "create-graph/ITEM_IDS: {ITEM_IDS[@]}"

	### Here the item-ids are brought to shape for the JSON-Syntax
	ITEM_BLOCK=`
	i=1; c=0
	for item in ${ITEM_IDS[@]}; do
		echo -n \{\"itemid\":\"$item\",\"color\":\"${COLORS[$c]}\"}
		if [ ${#ITEM_IDS[@]} -gt $i ]; then echo -n ","; fi;
		((i++)); ((c++)); if [ ${#COLORS[@]} -eq $c ]; then c=0; fi
	done`
	ITEM_BLOCK="`echo $ITEM_BLOCK | sed 's/,$//'`"
	echo Item-Block: $ITEM_BLOCK
	#cat <<EOF
	echo Baue JSON Block für create_graph
	RESULT="`$CURL 2>/dev/null << EOF
	{
	    "jsonrpc": "2.0",
		"method": "graph.create",
	    "params": {
		"name": "$NAME",
		"width":$WIDTH,
		"height":$HIGHT,
		"gitems": [
		$ITEM_BLOCK
		]
	    },
	    "auth": "$AUTHCODE",
	    "id": 2
	}
EOF`"

	if [ "$(echo $RESULT | grep "already exists in graphs or graph" | wc -l)" -gt 0 ]; then
		echo "`date +%Y-%m.%d-%H:%M:%S` Graph $NAME for $HOST already exists" >&2; fi;
	if [ "$(echo $RESULT | grep "error" | wc -l)" -gt 0 ]; then
		echo "`date +%Y-%m.%d-%H:%M:%S` $RESULT" >&2 ; fi;
	if [ "$(echo $RESULT | grep result | grep graphids | wc -l)" -gt 0 ]; then
		echo "`date +%Y-%m.%d-%H:%M:%S` Graph: \"$NAME\" successfully created" >&2 ; fi;
}


function get_hist() {

	## to the function passed variables are checked and declared  as working variables.
   ## if an exception occuress ten exit
        for i in "${@}"
        do
                if [[ "$i" == *=* ]]; then declare "$i"; fi
        done
        #echo Itemname: "$item"

	### Check wheather input of host /hostid could be a problem
	if [ -z $host   ] && [ -z $hostid ]; then host=`hostname` ; fi
	if [ ! -z $host   ] && [ ! -z $hostid ]; then echo "You must only specify either a \"host\" or \"hostid\"" $EXIT; fi
	if [ ! -z $host   ]; then HOST=$host; else HOST=`hostname`; fi
	if [ ! -z $host   ]; then HOST_ID=`get_hostid $host`; fi
	if [ ! -z $hostid ]; then HOST_ID=$hostid; fi

	### If an item-name is passed, then the id(s) will be seached and a itemid-line for the SOAP-Query is build
	if [ -z "$item"   ] && [ -z $itemid ]; then echo "You have to specify either "\"item\"name or \"itemid\" $EXIT; fi
	if [ ! -z "$item" ]; then ITEM="`echo $item | sed 's/,/ /g'`";
		ITEM_ID="`for element in ${ITEM[@]}; do get_ids type=item hostid=$HOST_ID search=$element; done` $ITEM_ID"
		#ITEM_ID=`get_ids type=item hostid=$HOST_ID search="$ITEM"`
		ITEM_LINE="\"itemids\":[\"`echo $ITEM_ID | sed 's/ /\",\"/g'`\"],"
	fi
	if [ ! -z "$itemid" ]; then ITEM_ID="$itemid";
		ITEM_LINE="\"itemids\":[\"`echo $ITEM_ID | sed 's/,/\",\"/g'`\"],"
	fi

 	### Here we have to convert human readable timestampe to unix timestamp:
	if [ ! -z "$from"   ]; then
		FROM=`date -d "$from" "+%s" 2> /dev/null`;
		if [ $? -ne "0" ]; then "Invalid from date: $from"; $EXIT; fi
		else echo "\"from\"-time is mandatory"; $EXIT;
	fi
	if [ ! -z "$till"   ]; then
		TILL=`date -d "$till" "+%s" 2> /dev/null`;
		if [ $? -ne "0" ]; then echo "Invalid till date: $from"; $EXIT; fi
		else echo "\"till\"-time is mandatory"; $EXIT;
	fi

	if [   -z $type   ]; then TYPE=3; else
		case $type in
			float)   TYPE=0;;
			string)  TYPE=1;;
			log)     TYPE=2;;
			integer) TYPE=3;;
			text)    TYPE=4;;
			*)			echo "\"type\" has either to be \"float\", \"string\", \"log\", \"integer\" (default), or \"text\""; $EXIT;;
		esac
	fi


	RESULT="`$CURL 2>/dev/null << EOF
		{
		"jsonrpc": "2.0",
		"method": "history.get",
		"params": {
			"output": "extend",
			"history": "$TYPE",
			"time_from":"$FROM",
			"time_till":"$TILL",
			$ITEM_LINE
			"sortfield":"clock",
			"sortorder":"DESC"
			},
		"auth": "$AUTHCODE",
		"id": 2
		}
EOF`"
	### remove """ and ":" from JSON-Syntax for better porcessing
	#echo "$RESULT" >&2
	RESULT=(`echo $RESULT | sed -e 's/"/ /g' -e 's/: //g'`)
	CSV_OUT=`
		n=0; for i in ${RESULT[@]}; do
			if [ $i == "clock" ]; then
				echo $(date -d @${RESULT[$n+1]} +%Y.%m.%d-%H:%M:%S)\;${RESULT[$n+4]}
			fi
			((n++))
		done
	`
	case $mode in
		max)	case $group in
					day) DAYS=(`echo "$CSV_OUT" | cut -c1-10 | sort | uniq`)
							for DAY in ${DAYS[@]}; do
								MAX="0"
								MAX=(`echo "$CSV_OUT" | grep $DAY | cut -d\; -f2 | \
									while read value; do if [ $(bc <<< "$value > $MAX") -eq 1 ];
																	then MAX=$value;
																		  echo $MAX
																fi
									done`)
								# Print the date/day plus the last element of the MAX-Array which is the highest value
								echo $DAY\;${MAX[@]:(-1)}
							done
					;;
					month) MONTHS=(`echo "$CSV_OUT" | cut -c1-7 | sort | uniq`)
								for MONTH in ${MONTHS[@]}; do
									MAX="0"
									MAX=(`echo "$CSV_OUT" | grep $MONTH | cut -d\; -f2 | \
										while read value; do if [ $(bc <<< "$value > $MAX") -eq 1 ];
																		then 	MAX=$value;
																		      echo $MAX
																	fi
										done `)
									echo $MONTH\;${MAX[@]:(-1)}
								done
					;;
					*) MAX="0"
						MAX=(`echo "$CSV_OUT" | cut -d\; -f2 | \
								while read value; do if [ $(bc <<< "$value > $MAX") -eq 1 ];
																then  MAX=$value;
																		echo $MAX
																fi
														done `)
								echo ${MAX[@]:(-1)}
					;;
			esac
	;;
		min)	case $group in
					day) DAYS=(`echo "$CSV_OUT" | cut -c1-10 | sort | uniq`)
							for DAY in ${DAYS[@]}; do
								### Assign variable a really high value, so that it updates to a min value,
								### I know it is not perfect.
								MIN="999999999999"
								MIN=(`echo "$CSV_OUT" | grep $DAY | cut -d\; -f2 | \
									while read value; do if [ $(bc <<< "$value < $MIN") -eq 1 ];
																	then MIN=$value;
																		  echo $MIN
																fi
									done`)
								# Print the date/day plus the last element of the MAX-Array which is the highest value
								echo $DAY\;${MIN[@]:(-1)}
							done
					;;
					month) MONTHS=(`echo "$CSV_OUT" | cut -c1-7 | sort | uniq`)
								for MONTH in ${MONTHS[@]}; do
								### Assign variable a really high value, so that it updates to a min value,
								### I know it is not perfect.
									MIN="999999999999"
									MIN=(`echo "$CSV_OUT" | grep $MONTH | cut -d\; -f2 | \
										while read value; do if [ $(bc <<< "$value < $MIN") -eq 1 ];
																		then 	MIN=$value;
																		      echo $MIN
																	fi
										done `)
									echo $MONTH\;${MIN[@]:(-1)}
								done
					;;
					*) MIN="999999999999"
						MIN=(`echo "$CSV_OUT" | cut -d\; -f2 | \
								while read value; do if [ $(bc <<< "$value < $MIN") -eq 1 ];
																then  MIN=$value;
																		echo $MIN
																fi
														done `)
								echo ${MIN[@]:(-1)}
					;;
			esac
	;;
	avg)
	;;
	*) case $group in
			day)	DAYS=(`echo "$CSV_OUT" | cut -c1-10 | sort | uniq`)
					for DAY in ${DAYS[@]}; do
							echo "$CSV_OUT" | grep $DAY | cut -d\; -f2
						done
				;;
				month)
				;;
				*) echo "$CSV_OUT";;
			esac
	esac
}

## Wenn api.sh mit auth username password aufgerufen wird, dann wird das auth file geschrieben.
case "$OPERATION" in
   auth) auth $2 $3;;
   create-application) create_application $2 $3;;
	create-graph)    create_graph ${@};;
   create-item)     create_item ${@};;
	create-screen)   create_screen ${@};;
   create-trigger)  create_trigger ${@};;
   get-appid)       get_appid $2 $3;;
	get-group-ids)   get_group_ids $2;;
	get-lastvalue)	  get_lastvalue "${@}";;
	get-hist)		  get_hist "${@}";;
   get-hostid)      get_hostid $2;;
   get-ifid)        get_ifid $2 $3;;
	get-ids)         get_ids "${@}";;
   get-trigger-ids) get_trigger_ids ${@};;
   object-show)	  object_show "${@}";;
   update-item)	  update_item ${@};;
   update-trigger)  update_trigger ${@};;
esac
