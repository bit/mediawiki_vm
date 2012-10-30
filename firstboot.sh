#!/bin/bash

#Swift setup based on http://docs.openstack.org/developer/swift/development_saio.html

# using version >1.4.3 mediawiki unittests will fail
# https://bugzilla.wikimedia.org/show_bug.cgi?id=38552

cd /opt
git clone https://github.com/openstack/swift
cd swift
#git checkout 1.4.3
python setup.py develop

swkey=mymadeupkey
#5GB swift disk
dd if=/dev/zero of=/srv/swift-disk bs=1024 count=0 seek=5000000
mkfs.xfs -i size=1024 /srv/swift-disk
echo /srv/swift-disk /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0 >> /etc/fstab
mkdir /mnt/sdb1
mount /mnt/sdb1
mkdir /mnt/sdb1/1 /mnt/sdb1/2 /mnt/sdb1/3 /mnt/sdb1/4
chown -R swift.swift /mnt/sdb1/*
for x in {1..4}; do ln -s /mnt/sdb1/$x /srv/$x; done
mkdir -p /etc/swift/object-server \
    /etc/swift/container-server \
    /etc/swift/account-server \
    /srv/1/node/sdb1 /srv/2/node/sdb2 /srv/3/node/sdb3 /srv/4/node/sdb4 \
    /var/run/swift
chown -R swift:swift /etc/swift /srv/[1-4]/ /var/run/swift
mkdir /var/run/swift
chown swift.swift /var/run/swift

cat > /etc/rsyncd.conf << EOF
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = 127.0.0.1

[account6012]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/account6012.lock

[account6022]
max connections = 25
path = /srv/2/node/
read only = false
lock file = /var/lock/account6022.lock

[account6032]
max connections = 25
path = /srv/3/node/
read only = false
lock file = /var/lock/account6032.lock

[account6042]
max connections = 25
path = /srv/4/node/
read only = false
lock file = /var/lock/account6042.lock


[container6011]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/container6011.lock

[container6021]
max connections = 25
path = /srv/2/node/
read only = false
lock file = /var/lock/container6021.lock

[container6031]
max connections = 25
path = /srv/3/node/
read only = false
lock file = /var/lock/container6031.lock

[container6041]
max connections = 25
path = /srv/4/node/
read only = false
lock file = /var/lock/container6041.lock


[object6010]
max connections = 25
path = /srv/1/node/
read only = false
lock file = /var/lock/object6010.lock

[object6020]
max connections = 25
path = /srv/2/node/
read only = false
lock file = /var/lock/object6020.lock

[object6030]
max connections = 25
path = /srv/3/node/
read only = false
lock file = /var/lock/object6030.lock

[object6040]
max connections = 25
path = /srv/4/node/
read only = false
lock file = /var/lock/object6040.lock
EOF

echo SYNC_ENABLE=true >> /etc/default/rsync
service rsync start

cat > /etc/rsyslog.d/10-swift.conf << EOF
# Uncomment the following to have a log containing all logs together
#local1,local2,local3,local4,local5.*   /var/log/swift/all.log

# Uncomment the following to have hourly proxy logs for stats processing
#\$template HourlyProxyLog,"/var/log/swift/hourly/%\$YEAR%%\$MONTH%%\$DAY%%\$HOUR%"
#local1.*;local1.!notice ?HourlyProxyLog

local1.*;local1.!notice /var/log/swift/proxy.log
local1.notice           /var/log/swift/proxy.error
local1.*                ~

local2.*;local2.!notice /var/log/swift/storage1.log
local2.notice           /var/log/swift/storage1.error
local2.*                ~

local3.*;local3.!notice /var/log/swift/storage2.log
local3.notice           /var/log/swift/storage2.error
local3.*                ~

local4.*;local4.!notice /var/log/swift/storage3.log
local4.notice           /var/log/swift/storage3.error
local4.*                ~

local5.*;local5.!notice /var/log/swift/storage4.log
local5.notice           /var/log/swift/storage4.error
local5.*  
EOF
mkdir -p /var/log/swift/hourly
chown -R syslog.adm /var/log/swift
service rsyslog restart

cat > /etc/swift/proxy-server.conf << EOF
[DEFAULT]
bind_port = 8080
user = swift
log_facility = LOG_LOCAL1

[pipeline:main]
pipeline = healthcheck cache swauth proxy-server
#pipeline = healthcheck cache swauth proxy-logging proxy-server

[app:proxy-server]
use = egg:swift#proxy
allow_account_management = true
account_autocreate = true

[filter:swauth]
use = egg:swauth#swauth
default_swift_cluster = local#http://127.0.0.1:8080/v1
set log_name = swauth
super_admin_key = $swkey


[filter:tempauth]
use = egg:swift#tempauth
user_admin_admin = admin .admin .reseller_admin
user_test_tester = testing .admin
user_test2_tester2 = testing2 .admin
user_test_tester3 = testing3

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:cache]
use = egg:swift#memcache
memcache_servers = 127.0.0.1:11211

#[filter:proxy-logging]
#use = egg:swift#proxy_logging
EOF

cat > /etc/swift/swift.conf << EOF
[swift-hash]
# random unique string that can never change (DO NOT LOSE)
swift_hash_path_suffix = changeme
EOF
for i in 1 2 3 4; do 
let log=i+1
cat > /etc/swift/account-server/$i.conf << EOF
[DEFAULT]
devices = /srv/$i/node
mount_check = false
bind_port = 60${i}2
user = swift
log_facility = LOG_LOCAL$log

[pipeline:main]
pipeline = account-server

[app:account-server]
use = egg:swift#account

[account-replicator]
vm_test_mode = yes

[account-auditor]

[account-reaper]
EOF
cat > /etc/swift/container-server/$i.conf <<EOF
[DEFAULT]
devices = /srv/$i/node
mount_check = false
bind_port = 60${i}1
user = swift
log_facility = LOG_LOCAL$log

[pipeline:main]
pipeline = container-server

[app:container-server]
use = egg:swift#container

[container-replicator]
vm_test_mode = yes

[container-updater]

[container-auditor]

[container-sync]
EOF
cat > /etc/swift/object-server/$i.conf <<EOF
[DEFAULT]
devices = /srv/$i/node
mount_check = false
bind_port = 60${i}0
user = swift
log_facility = LOG_LOCAL$log

[pipeline:main]
pipeline = object-server

[app:object-server]
use = egg:swift#object

[object-replicator]
vm_test_mode = yes

[object-updater]

[object-auditor]
EOF
done
cat > /usr/local/bin/makerings << EOF
#!/bin/bash

cd /etc/swift

rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz

swift-ring-builder object.builder create 18 3 1
swift-ring-builder object.builder add z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object.builder add z2-127.0.0.1:6020/sdb2 1
swift-ring-builder object.builder add z3-127.0.0.1:6030/sdb3 1
swift-ring-builder object.builder add z4-127.0.0.1:6040/sdb4 1
swift-ring-builder object.builder rebalance
swift-ring-builder container.builder create 18 3 1
swift-ring-builder container.builder add z1-127.0.0.1:6011/sdb1 1
swift-ring-builder container.builder add z2-127.0.0.1:6021/sdb2 1
swift-ring-builder container.builder add z3-127.0.0.1:6031/sdb3 1
swift-ring-builder container.builder add z4-127.0.0.1:6041/sdb4 1
swift-ring-builder container.builder rebalance
swift-ring-builder account.builder create 18 3 1
swift-ring-builder account.builder add z1-127.0.0.1:6012/sdb1 1
swift-ring-builder account.builder add z2-127.0.0.1:6022/sdb2 1
swift-ring-builder account.builder add z3-127.0.0.1:6032/sdb3 1
swift-ring-builder account.builder add z4-127.0.0.1:6042/sdb4 1
swift-ring-builder account.builder rebalance
EOF
cat > /usr/local/bin/resetswift << EOF
#!/bin/bash

swift-init all stop
find /var/log/swift -type f -exec rm -f {} \;
sudo umount /mnt/sdb1
sudo mkfs.xfs -f -i size=1024 /srv/swift-disk
sudo mount /mnt/sdb1
sudo mkdir /mnt/sdb1/1 /mnt/sdb1/2 /mnt/sdb1/3 /mnt/sdb1/4
sudo chown swift.swift /mnt/sdb1/*
mkdir -p /srv/1/node/sdb1 /srv/2/node/sdb2 /srv/3/node/sdb3 /srv/4/node/sdb4
sudo rm -f /var/log/debug /var/log/messages /var/log/rsyncd.log /var/log/syslog
chown -R swift.swift /mnt/sdb1/
sudo service rsyslog restart
sudo service memcached restart
EOF
cat > /usr/local/bin/remakerings << EOF
#!/bin/bash

cd /etc/swift

rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz

swift-ring-builder object.builder create 18 3 1
swift-ring-builder object.builder add z1-127.0.0.1:6010/sdb1 1
swift-ring-builder object.builder add z2-127.0.0.1:6020/sdb2 1
swift-ring-builder object.builder add z3-127.0.0.1:6030/sdb3 1
swift-ring-builder object.builder add z4-127.0.0.1:6040/sdb4 1
swift-ring-builder object.builder rebalance
swift-ring-builder container.builder create 18 3 1
swift-ring-builder container.builder add z1-127.0.0.1:6011/sdb1 1
swift-ring-builder container.builder add z2-127.0.0.1:6021/sdb2 1
swift-ring-builder container.builder add z3-127.0.0.1:6031/sdb3 1
swift-ring-builder container.builder add z4-127.0.0.1:6041/sdb4 1
swift-ring-builder container.builder rebalance
swift-ring-builder account.builder create 18 3 1
swift-ring-builder account.builder add z1-127.0.0.1:6012/sdb1 1
swift-ring-builder account.builder add z2-127.0.0.1:6022/sdb2 1
swift-ring-builder account.builder add z3-127.0.0.1:6032/sdb3 1
swift-ring-builder account.builder add z4-127.0.0.1:6042/sdb4 1
swift-ring-builder account.builder rebalance
EOF
cat > /usr/local/bin/startmain << EOF
#!/bin/bash

swift-init main start
EOF
cat > /usr/local/bin/startrest << EOF
#!/bin/bash

swift-init rest start
EOF
chmod +x /usr/local/bin/*
hash -r
remakerings
startmain

AUTH=http://127.0.0.1:8080/auth
AUTH_USER="test:tester"
AUTH_KEY="testing"
swauth-prep -K $swkey
swauth-add-user -A http://127.0.0.1:8080/auth -K $swkey -a test tester testing

#AUTH_URL="http://127.0.0.1:8080/v1/AUTH_85ba186e-992b-4652-8759-311198e7e22d"
AUTH_URL=`curl  -H "X-Storage-User: $AUTH_USER" -H "X-Storage-Pass: $AUTH_KEY" $AUTH/v1.0 | sed "s/.*http/http/" | sed "s/\".*//"`
PUBLIC_URL=`echo $AUTH_URL | sed "s/127.0.0.1/swift.local/"`

for container in public thumb temp; do
    swift -A $AUTH/v1.0 -U $AUTH_USER -K $AUTH_KEY post -r '.r:*' mediawiki-$container
done

#checkout mediawiki
git clone https://gerrit.wikimedia.org/r/p/mediawiki/core.git /srv/mediawiki

#checkout extensions
for ext in TimedMediaHandler TitleBlacklist UploadWizard MwEmbedSupport SwiftCloudFiles; do
    git clone https://gerrit.wikimedia.org/r/p/mediawiki/extensions/$ext.git /srv/mediawiki/extensions/$ext
done

cat > /etc/apache2/sites-available/default << EOF
<VirtualHost *:80>
  ServerName mediawiki.local
  Options +Indexes +FollowSymlinks
  RewriteEngine on
  DocumentRoot /srv/mediawiki

  ErrorLog /var/log/apache2/mediawiki_error.log
  CustomLog /var/log/apache2/mediawiki_access.log combined
  <Directory "/srv/mediawiki/images">
   # Ignore .htaccess files
   AllowOverride None
   # Serve HTML as plaintext, don't execute SHTML
   AddType text/plain .html .htm .shtml .php
   # Don't run arbitrary PHP code.
   php_admin_flag engine off
  </Directory>
</VirtualHost>
EOF
cat > /etc/php5/apache2/conf.d/mediawiki.ini << EOF 
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 360
EOF
grep webm /etc/mime.types || echo "video/webm       webm" >> /etc/mime.types

a2enmod rewrite
service apache2 restart

mysqladmin create mediawiki

chown -R mediawiki.mediawiki /srv/mediawiki
chown -R www-data.www-data /srv/mediawiki/images

cd /srv/mediawiki/maintenance
php install.php \
    --dbname mediawiki \
    --dbuser root \
    --conf /srv/mediawiki/LocalSettings.php \
    --server http://swift.local \
    --scriptpath "" \
    --pass mediawiki \
    SwiftVM admin

cat >> /srv/mediawiki/LocalSettings.php << EOF
\$wgMainCacheType = CACHE_MEMCACHED;
\$wgParserCacheType = CACHE_MEMCACHED; # optional
\$wgMessageCacheType = CACHE_MEMCACHED; # optional
\$wgMemCachedServers = array( "127.0.0.1:11211" );
\$wgSessionsInMemcached = true;

\$wgEnableUploads  = true;
\$wgUseImageMagick = true;
\$wgImageMagickConvertCommand = "/usr/bin/convert";


require( "\$IP/extensions/TitleBlacklist/TitleBlacklist.php" );
require( "\$IP/extensions/MwEmbedSupport/MwEmbedSupport.php" );

require( "\$IP/extensions/TimedMediaHandler/TimedMediaHandler.php" );
\$wgFFmpegLocation = "/usr/bin/avconv";
\$wgFFmpeg2theoraLocation = "/usr/bin/ffmpeg2theora";
\$wgShowExepctionDetails = true;
\$wgWaitTimeForTranscodeReset = 10;

require_once( "\$IP/extensions/UploadWizard/UploadWizard.php" );
\$wgUploadWizardConfig['enableFirefogg'] = true;
\$wgUploadWizardConfig['enableFormData'] = true;
\$wgUploadWizardConfig['enableChunked'] = true;

\$wgFileExtensions = array( 'png', 'gif', 'jpg', 'jpeg' , 'oga', 'ogv', 'ogg', 'webm');
\$wgShowExceptionDetails = true;

\$wgAPIRequestLog="/tmp/mw.log";
\$wgDebugLogFile = "/tmp/debug.log";

\$wgUseTidy = true;
\$wgTidyInternal = false;
\$wgAlwaysUseTidy = false;
\$wgTidyBin = '/usr/bin/tidy';

require( "\$IP/extensions/SwiftCloudFiles/SwiftCloudFiles.php" );

\$wgSwiftConf = array(
	'authUrl' => '$AUTH',
	'user' => '$AUTH_USER',
	'key' => '$AUTH_KEY',
    'url' => '$PUBLIC_URL'
);

\$wgFileBackends[]  =  array(
        'name'                => 'local-swift',
        'class'               => 'SwiftFileBackend',
        'lockManager'         => 'nullLockManager',
        'swiftAuthUrl'        => \$wgSwiftConf['authUrl'],
        'swiftUser'           => \$wgSwiftConf['user'],
        'swiftKey'            => \$wgSwiftConf['key'],
        'parallelize'         => 'implicit'
);
\$wgLocalFileRepo  =  array(
        'class'              => 'LocalRepo',
        'name'               => 'local',
        'backend'            => 'local-swift',
        'scriptDirUrl'       => \$wgScriptPath,
        'scriptExtension'    => \$wgScriptExtension,
        'url'                => \$wgSwiftConf['url'],
        'hashLevels'         => 0,
        'deletedHashLevels'  => 0,
        'zones'             =>  array(
            'public'  =>  array( 'container' =>  'public', 'url' =>  \$wgSwiftConf['url'] . '/mediawiki-public' ),
            'thumb'   =>  array( 'container' =>  'thumb',  'url' =>  \$wgSwiftConf['url'] . '/mediawiki-thumb' ),
            'temp'    =>  array( 'container' =>  'temp', 'url' =>  \$wgSwiftConf['url'] . '/mediawiki-temp' ),
            'deleted' =>  array( 'container' =>  'deleted' ),
        )
	);
EOF

cd /srv/mediawiki/maintenance
php update.php --quick

cat <<- EOF | php edit.php MediaWiki:Common.js
addOnloadHook(function() {
    \$('a[accesskey="u"]').attr('href', '/index.php/Special:UploadWizard');
});
EOF

cat <<- EOF | php edit.php Main_Page

Upload file at [[Special:UploadWizard]]

List of uploaded files [[Special:ListFiles]]
EOF


cat > /usr/local/bin/jobs-loop.sh <<EOF
#!/bin/bash
#
# NAME
# jobs-loop.sh -- Continuously process a MediaWiki jobqueue
#
# SYNOPSIS
# jobs-loop.sh [-t timeout] [-v virtualmemory] [job_type]

# default maxtime for jobs
maxtime=300
maxvirtualmemory=400000

# Whether to process the default queue. Will be the case if no job type
# was specified on the command line. Else we only want to process given types
dodefault=true

while getopts "t:v:" flag
do
	case \$flag in
		t)
			maxtime=\$OPTARG
			;;
		t)
			maxvirtualmemory=\$OPTARG
			;;
	esac
done
shift \$((\$OPTIND - 1))

# Limit virtual memory
ulimit -v \$maxvirtualmemory

# When killed, make sure we are also getting ride of the child jobs
# we have spawned.
trap 'kill %-; exit' SIGTERM


if [ -z "\$1" ]; then
	echo "Starting default queue job runner"
	dodefault=true
	#types="htmlCacheUpdate sendMail enotifNotify uploadFromUrl fixDoubleRedirect renameUser"
	types="sendMail enotifNotify uploadFromUrl fixDoubleRedirect MoodBarHTMLMailerJob ArticleFeedbackv5MailerJob RenderJob"
else
	echo "Starting type-specific job runner: \$1"
	dodefault=false
	types=\$1
fi

cd /srv/mediawiki/maintenance
while [ 1 ];do
	nice -n 20 php runJobs.php --wiki=mediawiki --procs=5 --type="\$type" --maxtime=\$maxtime &
	wait
	sleep 5
done
EOF
chmod 755 /usr/local/bin/jobs-loop.sh

cat > /etc/init/timedmediahandler.conf <<EOF
# TimedMediaHandler WebVideoJobRunner

description	"TimedMediaHandler WebVideoJobRunner"

start on runlevel [2345]
stop on runlevel [!2345]
kill timeout 5
respawn
respawn limit 10 5

umask 022

exec /usr/bin/sudo -u www-data /usr/local/bin/jobs-loop.sh -t 14400 -v 0 webVideoTranscode
EOF
service timedmediahandler start


cat > /srv/mediawiki/update.sh <<EOF
#!/bin/bash
cd \`dirname \$0\`
base=\`pwd\`
git pull
cd extensions
for ext in \`ls | grep -v README\`; do
	cd \$base/extensions/\$ext
	git pull
done
cd \$base/maintenance
php update.php --quick
EOF
chmod 755 /srv/mediawiki/update.sh

cat > /etc/apt/sources.list.d/mediawiki.list <<EOF
## Wikimedia APT repository
deb http://apt.wikimedia.org/wikimedia precise-wikimedia main universe
deb-src http://apt.wikimedia.org/wikimedia precise-wikimedia main universe
EOF
curl http://apt.wikimedia.org/autoinstall/keyring/wikimedia-archive-keyring.gpg > /etc/apt/trusted.gpg.d/wikimedia-archive-keyring.gpg

apt-get update
apt-get -y install oggvideotools pip-python

pip install git-review
