# Abstract

This bash script is used to manage the Zabbix monitoring system and talks to the Zabbix-API. It was used for 

* bulk creation of items, triggers and garphs
* modification/(en/disable) of triggers
* generating reports from zabbix history data.

With my knowledge today I would have implemented it in Python. This is more a historical document. I haven't tested its functionality for a long time. It comes with no guarantee!

## Requirements

Two packages need to be installed:

* atd: At automatically deletes the authcode for Zabbix access after a while.
* jq: Lightweight json parser for the shell. 

## Configuration

You need to tell the sript how to talk to the Zabbix server. This is done in the ~/.zabbix.cfg file:

	ADDRESS=zabbbix-srv.domain.tld
	PROTOCOL=https
	USER=username

# Usage

## Overview

| function          | mandatory parameter | optional parameter | comment |
|-------------------|---------------------|--------------------|---------|
|get_appid          |**[application] [hostname]** | | internal function |
|get_group_ids      |**groups**=[group1,groupN| | internal function |
|get_hist           |**item**=[itemname] or **itemid**=[itemid] <br> **from**=[JJJJ-MM-TT HH:MM:SS]<br> **till**=[JJJJ-MM-TT HH:MM:SS]| \[string\|log\|int\|text\] (default: int)<br> **mode**=\[max\|min\]: just show maximum and minimum values<br>**group**=[day,month] (select if you want to get the result for all values (default), every day, or month. | The valus for time (HH:MM:SS) can be shortend like "HH:MM" or "HH" |
|get_hostid         | | | internal function |
|get_ids            |**host**=[hostname],<br>**groups**=[hostgroup] or<br>**hostid**=[HOST_ID]<br>**type**=\[i(tem)\|t(rigger)\|g(graph)\]<br>**search**=[searchstring1],[searchstringN] | | internal function<br> delivers item- / trigger-ids |
|create_graph       |**name**=[graphname]<br>**items**=[item1],[itemN] or<br> **itemids**=[interger]<br>**host**=\[HOSTNAME\] (only necessary for item names) |**width**=\[int\] (default: 900)<br>**hight**=\[int\] (default: 200) | | 
|create_item        |**host**=[hostname]<br>**name**=[itemname] |**type**=\[itemtyp\] (default: trapper)<br>**app**=[app1],[appN]<br>**data**=\[data type\] (default: Number Unsigned)<br>**key**=Keyvalue (can be empty for type trapper) <br>**interv**=\[Int\] (Interval; default: 60)<br>**hist**=\[int\] (history in days; default: 60)<br>**trend**=\[Int\] (trend data in days; default: 90)<br>**unit**=\[Str\] (unit, eg. "ms", "b")<br>**multi**=\[float\] (multiplicator: eg. 0.001)<br>**delta**=\[asis\|speed\|simple\]<br>**desc**=\[itme description\]<br>**snmp-oid**=\[SNMP-OID\]<br>**snmp-community**=\[SNMP-Community\]<br>**interfaceid**=[usually it gets automatically selected] | **Item type values**:<br>* trapper (default)<br>* interval<br>* simple-check<br>* snmpv1<br>* snmpv2<br>* snmpv3<br>* zabbix-agent<br>* zabbix-agent-active<br>* zabbix-trapper<br>**Delta values**:<br>* asis: don't save delta values<br>* speed=speed per second<br>* simple=simple change<br>**data types**:<br>* numfl: numeric float<br>* char: charecters<br>* log: log file<br>* numun: number unsigned<br>* text: Text |
|get_latestdata     |[HOSTNAME] [ITEMNAME] | | Delivers the latest data of an item on a host |
|create_trigger     |**host**==[hostname]<br>**item**=[Item which is referenced by the trigger]<br>**cond**=[Condition] | **prio**=\[priority\] (default: warn)<br>**warnlv**=\[<,>,=WERT\] (warn value; default: 90)<br>**name**=\[trigger name\] (default: $WARN_DESC _$ITEM $WARN)<br>**dep**=\[trigger-id\]
|create_screen      |**name**=SCREENNAME<br>**rtype**=[ressourcetype]<br>**objects**=[object1],[objectN]<br>**host**=[host] |**hisze**=\[Int\] (default: 4)<br>**vsize**=\[Int\] (default: 1/variabel) | Objects: List of objects which should be added to the screen. These can be of the following **ressource type**:<br>**graph**: graph<br>**sgraph**: simple graph<br>**map**: map<br>**test**: plain text<br>**host**: hosts info <br> **triginfo**: triggers info <br> **srvinfo**: server info <br>**clock**: clock <br> **screen**: screen <br> **trigov**: triggers overview <br> **dataov**: data overview <br> **url**: URL <br> **histac**: history of actions <br> **histav**: history of events <br> **stathgt**: status of host group triggers <br>**sysstat**: system status <br> **trigstat**: status of host triggers <br> Until now only the ressource types "grap" and "simple graph" are implemented. The other types are prepared and could properly work (not tested) |
|filter_array_match |\[#JSON-Sring\] \[#Property-Name\] | | internal function <br> filters the values for a special property as json output |
|get_ifid           |[HOSTNAME] [TYPE] | | **types**: <br> * agent <br> * snmp <br> * ipmi <br> * jmx <br> This function is only used internally when creating items, if they need an interface like for snmp items. The return value is an interface id. |
|object_show        |**host**=Hostname/**hostid**=HostID<br>**group**=group-name/**groupid**=group-id<br>**type**=\[i\[tem\]\|t\[rigger\]\]\|\[g\[raph\] <br>**out**=output-fields <br> **search**=\[string/wildcard\] | | **output-fileds** for: <br> * [trigger](https://www.zabbix.com/documentation/5.0/manual/api/reference/trigger/object) <br> * [items](https://www.zabbix.com/documentation/5.0/manual/api/reference/item/object) <br> * [graphs](https://www.zabbix.com/documentation/5.0/manual/api/reference/graph/object) |
|update_item        |**id**=[itemid]<br>**status**=\[en\[able\]\]\|\[dis\[able\]\]
|update_trigger     |**id**=\[triggerid\] | **cond**=\[condition\] like "'count(#3,800M,ge)'" <br>**comment**=[trigger-comment]<br>**item**=\[ITEMNAME\] (mandatory for "cond=") <br> host=\[HOSTNAME\] <br> warnlv=\[WARNLV\] (eg. "\>90" = default) | |

## Authentication

If you want to use this script, you need to authenticate with your zabbix credentials first.

Interactive authenticaton:

`zabbix-ctrl.sh auth user=ZBX_USER`

Authentication with Password on the comand line. (This will be visible in the history)

`zabbix-ctrl.sh auth user=ZBX_USER pass=ZbXPaSs`

The authetication token will be written to ~/.authfile and deleted after a while by the atd. The duration is set in the script:

	function auth() {
	...
	echo "rm $AUTHFILE" | at now+60min
	...
    }

## Examples

All BASH function can be used in the shell. The underscore of the function names is just replaced by a hyphen.


### create-item

Create an item with the name "CPU-Interrupts" on host "zabbix"

	zabbix-ctrl.sh create-item host=zabbix name=CPU-Interrupts type=zabbix-agent-active app=CPU interv=60 key="system.cpu.intr" hist=60

When the item is created successfully the new item-id will be displayed on stdout.


### get-appid

Query the application-id of application "CPU" on host "zabbix":

	zabbix-ctrl.sh get-appid CPU zabbix


### get-hist

Query the daily maximum values of the item with the id "31972" on host jboss-srv:

	zabbix-ctrl.sh get-hist itemid=31972 from="20140822" till="20140827" host=jboss-srv type=float mode=max group=day


### create-graph

Create a grpah with four items:

	create-graph name=JK_prod_Errors itemids=30577,33673,30579,33675


### get-latestvalue

Returns the latest value of an item:

	zabbix-ctrl.sh get-lastvalue wildflysrv item_name


### create-screen

The following command creates a screen with the name "my_screen" for host "websrv" and all graphs which name match the expression "JK_Prod*"

	 zabbix-ctrl.sh create-screen name=my_screen host=websrv rtype=graph objects=JK_Prod*

create-screen can take multiple expressions for (graph) objects:

	zabbix-ctrl.sh create-screen ... objects="*prod_-_JK-Threads,*prod_-_Container_Memory,*_prod_-_*UserSessions" ...  groups=applicatin-server rtype=graph hsize=5


### object-show

With object-show you can search for objects like items, trigger and graphs and display different fields. This can be useful to search for graphs which you want to use in a screen. You can find out which fields are available in the overview table behind the links of "object_show"

	zabbix-ctrl.sh object-show groups=application-server type=g out=name search=prod*Container_Memory


### update_trigger

Change the condition of a trigger:

	./zabbix-ctrl.sh update-trigger id=25531 cond='count(#3,800M,ge)' item=prod_-_Container_Memory.used warnlv=\>3







