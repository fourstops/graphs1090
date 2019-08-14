#!/bin/bash

ipath=/usr/share/graphs1090
install=0

packages="lighttpd unzip"
packages2="rrdtool collectd-core"

mkdir -p $ipath/installed
mkdir -p /var/lib/graphs1090/scatter

for i in $packages $packages2
do
	if ! dpkg -s $i 2>/dev/null | grep 'Status.*installed' &>/dev/null
	then
		install=1
		touch $ipath/installed/$i
	fi
done

if ! dpkg -s libpython2.7 2>/dev/null | grep 'Status.*installed' &>/dev/null
then
	apt-get update
	apt-get install -y 'libpython2.7'
	apt-get install -y 'libpython2.?'
	update_done=yes
fi

if [[ $install == "1" ]]
then
	echo "------------------"
	echo "Installing required packages: $packages"
	echo "------------------"
	if [[ $update_done != "yes" ]]; then
		apt-get update
	fi
	#apt-get upgrade -y
	if apt-get install -y --no-install-suggests $packages && apt-get install -y --no-install-suggests $packages2
	then
		echo "------------------"
		echo "Packages successfully installed!"
		echo "------------------"
	else
		echo "------------------"
		echo "Failed to install required packages: $packages"
		echo "Exiting ..."
		exit 1
	fi
fi

# make sure commands are available if they were just installed
hash -r


if [ -z $1 ] || [ $1 != "test" ]
then
	cd /tmp
	if ! wget --timeout=30 -q -O master.zip https://github.com/wiedehopf/graphs1090/archive/master.zip || ! unzip -q -o master.zip
	then
		echo "------------------"
		echo "Unable to download files, exiting! (Maybe try again?)"
		exit 1
	fi
	cd graphs1090-master
fi

cp dump1090.db dump1090.py system_stats.py LICENSE $ipath
cp *.sh $ipath
chmod u+x $ipath/*.sh
if ! grep -e 'system_stats' -qs /etc/collectd/collectd.conf; then
	cp /etc/collectd/collectd.conf /etc/collectd/collectd.conf.graphs1090 2>/dev/null
	cp collectd.conf /etc/collectd/collectd.conf
	echo "------------------"
	echo "Overwriting /etc/collectd/collectd.conf, the old file has been moved to /etc/collectd/collectd.conf.graphs1090"
	echo "------------------"
fi
sed -i -e 's/XFF 0.4/XFF 0.3/' /etc/collectd/collectd.conf
rm -f /etc/cron.d/cron-graphs1090
cp -r html $ipath
cp -n default /etc/default/graphs1090
cp default $ipath/default-config
cp collectd.conf $ipath/default-collectd.conf
cp service.service /lib/systemd/system/graphs1090.service

# bust cache for all css and js files
sed -i -e "s/__cache_version__/$(date +%s | tail -c5)/g" $ipath/html/index.html

cp 88-graphs1090.conf /etc/lighttpd/conf-available
lighty-enable-mod graphs1090 >/dev/null


if wget --timeout=30 http://localhost/dump1090-fa/data/stats.json -O /dev/null -q; then
	true
elif wget --timeout=30 http://localhost/dump1090/data/stats.json -O /dev/null -q; then
	sed -i 's?localhost/dump1090-fa?localhost/dump1090?' /etc/collectd/collectd.conf
	echo --------------
	echo "dump1090 webaddress automatically set to http://localhost/dump1090/"
	echo --------------
else
	echo --------------
	echo "Non-standard configuration detected, you need to change the data URL in /etc/collectd/collectd.conf!"
	echo --------------
fi

if grep jessie /etc/os-release >/dev/null
then
	echo --------------
	echo "Some features are not available on jessie!"
	echo --------------
	sed -i -e 's/ADDNAN/+/' -e 's/TRENDNAN/TREND/' -e 's/MAXNAN/MAX/' -e 's/MINNAN/MIN/' $ipath/graphs1090.sh
	sed -i -e '/axis-format/d' $ipath/graphs1090.sh
fi


mkdir -p /var/lib/collectd/rrd/localhost/dump1090-localhost


systemctl daemon-reload
systemctl enable collectd &>/dev/null
systemctl restart lighttpd
sleep 2
systemctl restart collectd
systemctl enable graphs1090
sleep 1
systemctl restart graphs1090

#fix readonly remount logic in fr24feed update script
sed -i -e 's?$(mount | grep " on / " | grep rw)?{ mount | grep " on / " | grep rw; }?' /usr/lib/fr24/fr24feed_updater.sh &>/dev/null

echo --------------
echo --------------
echo "All done!"
