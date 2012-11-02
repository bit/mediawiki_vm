#!/bin/sh
cat > /etc/apt/sources.list.d/mediawiki.list <<EOF
## Wikimedia APT repository
deb http://apt.wikimedia.org/wikimedia precise-wikimedia main universe
deb-src http://apt.wikimedia.org/wikimedia precise-wikimedia main universe
EOF
curl http://apt.wikimedia.org/autoinstall/keyring/wikimedia-archive-keyring.gpg > /etc/apt/trusted.gpg.d/wikimedia-archive-keyring.gpg

apt-get update
apt-get -y install oggvideotools

#checkout mediawiki
git clone https://gerrit.wikimedia.org/r/p/mediawiki/core.git /srv/mediawiki

#checkout extensions
for ext in TimedMediaHandler TitleBlacklist UploadWizard MwEmbedSupport OggHandler; do
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
cat > /etc/php5/apache2/conf.d/mediawiki.ini <<EOF 
upload_max_filesize = 128M
post_max_size = 128M
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
    --server http://mediawiki.local \
    --scriptpath "" \
    --pass mediawiki \
    WikiVM admin

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

/*
\$wgForeignFileRepos[] = array(
	'class'                   => 'ForeignAPIRepo',
	'name'                    => 'wikimediacommons',
	'apibase'                 => 'http://commons.wikimedia.org/w/api.php',
);
*/
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
        v)
            maxvirtualmemory=\$OPTARG
            ;;
    esac
done
shift \$((\$OPTIND - 1))
# Limit virtual memory
#echo ulimit -v \$maxvirtualmemory
#ulimit -v \$maxvirtualmemory

# When killed, make sure we are also getting ride of the child jobs
# we have spawned.
#trap 'kill %-; exit' SIGTERM


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
    echo start to loop
for type in \$types; do
    echo nice -n 20 php runJobs.php --wiki=mediawiki --procs=5 --type="\$type" --maxtime=\$maxtime
    nice -n 20 php runJobs.php --wiki=mediawiki --procs=5 --type="\$type" --maxtime=\$maxtime >> /tmp/jobs.log 2>&1 &
    wait
done
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
	echo \$ext
	git pull
done
cd \$base/maintenance
php update.php --quick
EOF
chmod 755 /srv/mediawiki/update.sh

apt-get -y install python-pip
pip install git-review
