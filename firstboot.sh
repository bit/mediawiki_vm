#!/bin/sh
#fails in bootstrap
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
EOF

a2enmod rewrite
service apache2 restart

mysqladmin create mediawiki

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

\$wgEnableUploads  = true;
\$wgUseImageMagick = true;
\$wgImageMagickConvertCommand = "/usr/bin/convert";


require( "\$IP/extensions/TitleBlacklist/TitleBlacklist.php" );
require( "\$IP/extensions/MwEmbedSupport/MwEmbedSupport.php" );

require( "\$IP/extensions/TimedMediaHandler/TimedMediaHandler.php" );
\$wgMaxShellMemory = 1024*64*1024;
\$wgFFmpegLocation = "/usr/bin/ffmpeg";
\$wgFFmpeg2theoraLocation = "/usr/bin/ffmpeg2theora";
\$wgShowExepctionDetails = true;
\$wgWaitTimeForTranscodeReset = 10;
\$wgTranscodeBackgroundTimeLimit = 3600 * 4 * 1000;

require_once( "\$IP/extensions/UploadWizard/UploadWizard.php" );
\$wgUploadWizardConfig['enableFirefogg'] = true;
\$wgUploadWizardConfig['enableFormData'] = true;
\$wgUploadWizardConfig['enableChunked'] = false;

\$wgFileExtensions = array( 'png', 'gif', 'jpg', 'jpeg' , 'oga', 'ogv', 'ogg', 'webm');
\$wgShowExceptionDetails = true;
EOF


cd /srv/mediawiki/maintenance
php update.php --quick

cat > /etc/init/timedmediahandler <<EOF
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

