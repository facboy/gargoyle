#!/bin/sh

update_dnsmasq_conf()
{
	dnsfile="$1"
	new_lines="$2"


	start_line=$(grep -n "BEGIN BONJOUR PRINTER CONFIGURATION" $dnsfile | sed 's/:.*$//g')
	end_line=$(grep -n "END BONJOUR PRINTER CONFIGURATION" $dnsfile | sed 's/:.*$//g')
	lines=$(wc -l $dnsfile | awk '{print $1 }')

	
	rm -rf /tmp/dns.new.tmp
	if [ -n "$start_line" ] ; then
		if [ $start_line -gt 1 ] ; then 
			head -n $(($start_line-1))  $dnsfile            >>/tmp/dns.new.tmp
		fi
		if [ $end_line -lt $lines ] ; then
			tail -n $(( $lines - $end_line ))  $dnsfile     >>/tmp/dns.new.tmp
		fi
	else
		cat "$dnsfile"                                          >>/tmp/dns.new.tmp
	fi

	echo '###### BEGIN BONJOUR PRINTER CONFIGURATION #####' >>/tmp/dns.new.tmp
	printf "$new_lines\n"                                   >>/tmp/dns.new.tmp
	echo '###### END BONJOUR PRINTER CONFIGURATION #######' >>/tmp/dns.new.tmp
	
	original_md5=$(md5sum "$dnsfile" | sed 's/[\t ].*$//g')
	new_md5=$(md5sum "/tmp/dns.new.tmp" | sed 's/[\t ].*$//g')
	if [ "$original_md5" != "$new_md5" ] ; then
		mv /tmp/dns.new.tmp "$dnsfile"
		/etc/init.d/dnsmasq restart
	else
		rm -rf /tmp/dns.new.tmp
	fi
}




if [ -e /tmp/printer_hotplug_lock ] ; then exit ; fi
touch /tmp/printer_hotplug_lock

count=5
while [ ! -e /proc/bus/usb/devices ] && [ $count -gt 0 ] ; do
	sleep 1
	count=$(( $count - 1 ))
done 

if [ ! -e /proc/bus/usb/devices ] ; then 
	rm -rf /tmp/printer_hotplug_lock
	exit 
fi


usb_devices_file="/proc/bus/usb/devices"
usb_dev_drivers=$(egrep "^I:" $usb_devices_file | sed 's/^.*Driver=//g' | sed 's/[\t ].*$//')

usb_dev_index=1
p910nd_enabled=$(uci get p910nd.@p910nd[0].enabled)
for dev_driver in $usb_dev_drivers ; do
	if [ "$dev_driver" = "usblp" ] ; then
		usb_dev_line=$(grep Product  $usb_devices_file | head -n $usb_dev_index | tail -n 1)
		usb_dev_name=$(echo $usb_dev_line | sed 's/^.*=//g')

		if [ "$p910nd_enabled" != "1" ] ; then
			uci set p910nd.@p910nd[0].enabled=1
			uci commit
			/etc/init.d/p910nd enable
			/etc/init.d/p910nd stop >/dev/null 2>&1
			/etc/init.d/p910nd start
		fi

		domain=$(uci get dhcp.@dnsmasq[0].domain)
		hostname=$(uci get system.@system[0].hostname)
		revip=$(uci get network.lan.ipaddr | sed 's/\./ /g' | awk ' { print "0."$3"."$2"."$1 ; }')
		dnsmasqConfLines=""
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=b._dns-sd._udp.$revip.in-addr.arpa,$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=db._dns-sd._udp.$revip.in-addr.arpa,$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=r._dns-sd._udp.$revip.in-addr.arpa,$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=dr._dns-sd._udp.$revip.in-addr.arpa,$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=lb._dns-sd._udp.$revip.in-addr.arpa,$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=_services._dns-sd._udp.$domain,_pdl-datastream._tcp.$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nptr-record=_pdl-datastream._tcp.$domain,$hostname._pdl-datastream._tcp.$domain\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\nsrv-host=Gargoyle._pdl-datastream._tcp.$domain,$hostname.$domain,9100\n")
		dnsmasqConfLines=$(printf "${dnsmasqConfLines}\ntxt-record=$hostname._pdl-datastream._tcp.$domain,ty=$usb_dev_name,product=($usb_dev_name),usb_MDL=$usb_dev_name,txtvers=1,qtotal=1,priority=20\n")


		update_dnsmasq_conf "/etc/dnsmasq.conf" "$dnsmasqConfLines"

		#after we've found a printer we're done -- for now, only one printer at a time
		rm -rf /tmp/printer_hotplug_lock
		exit;

	fi
	usb_dev_index=$(( $usb_dev_index + 1 ))
done

if [ "$p910nd_enabled" != "0" ] ; then
	uci set p910nd.@p910nd[0].enabled=0
	uci commit
	/etc/init.d/p910nd stop
fi
rm -rf /tmp/printer_hotplug_lock
