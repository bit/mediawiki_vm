#!/bin/sh
CH="chroot $1"
$CH svn checkout http://svn.wikimedia.org/svnroot/mediawiki/trunk/phase3 /srv/mediawiki
for ext in TimedMediaHandler TitleBlacklist UploadWizard MwEmbedSupport; do
$CH svn checkout http://svn.wikimedia.org/svnroot/mediawiki/trunk/extensions/$ext /srv/mediawiki/extensions/$ext
done
