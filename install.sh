#!/bin/sh
CH="chroot $1"
$CH git clone https://gerrit.wikimedia.org/r/p/mediawiki/core.git /srv/mediawiki
for ext in TimedMediaHandler TitleBlacklist UploadWizard MwEmbedSupport; do
$CH git clone https://gerrit.wikimedia.org/r/p/mediawiki/extensions/$ext.git /srv/mediawiki/extensions/$ext
done
