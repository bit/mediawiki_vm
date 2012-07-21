#!/bin/sh

#checkout mediawiki
git clone https://gerrit.wikimedia.org/r/p/mediawiki/core.git /srv/mediawiki

#checkout extensions
for ext in TimedMediaHandler TitleBlacklist UploadWizard MwEmbedSupport; do
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
EOF


cd /srv/mediawiki/maintenance
php update.php --quick

cat > /etc/init/timedmediahandler.conf <<EOF
# TimedMediaHandler WebVideoJobRunner

description	"TimedMediaHandler WebVideoJobRunner"

start on runlevel [2345]
stop on runlevel [!2345]
kill timeout 5
respawn
respawn limit 10 5

umask 022

env IP=/srv/mediawiki
exec /usr/bin/sudo -u www-data /usr/bin/php \$IP/extensions/TimedMediaHandler/maintenance/WebVideoJobRunner.php
EOF
service timedmediahandler start

