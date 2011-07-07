INSTALL_DIR=/usr/local/bin
MAN_DIR=/usr/local/man/man1
ETC_DIR=/etc
VERSION=1.0.8
DIST_FILES=COPYING INSTALL Makefile README \
	colordiff.pl colordiffrc colordiffrc-lightbg cdiff.sh BUGS TODO CHANGES colordiff.1 \
	colordiff.xml cdiff.xml
TMPDIR=colordiff-${VERSION}
TARBALL=${TMPDIR}.tar.gz


doc: colordiff.xml cdiff.xml
	xmlto -vv man colordiff.xml
	xmlto -vv man cdiff.xml
	xmlto -vv txt colordiff.xml
	xmlto -vv html-nochunks colordiff.xml
	mv colordiff.txt README
	perl -p -i -e 's#<head>#<head><link rel=\"stylesheet\" type=\"text/css\" href=\"colordiff.css\">#' colordiff.html
	perl -p -i -e 's#</body>#</div></body>#' colordiff.html
	perl -p -i -e 's#<div class=\"refentry\"#<div id=\"content\"><div class=\"refentry\"#' colordiff.html
	mv colordiff.html ../htdocs

etc:
	sed -e "s%/etc%$(ETC_DIR)%g" colordiff.pl > colordiff.pl.for.install

install: etc
	install -D colordiff.pl.for.install ${INSTALL_DIR}/colordiff
	if [ ! -f ${INSTALL_DIR}/cdiff ] ; then \
	  install cdiff.sh ${INSTALL_DIR}/cdiff; \
	fi
	install -D colordiff.1 ${MAN_DIR}/colordiff.1
	install -D cdiff.1 ${MAN_DIR}/cdiff.1
	if [ -f ${ETC_DIR}/colordiffrc ]; then \
	  mv -f ${ETC_DIR}/colordiffrc ${ETC_DIR}/colordiffrc.old; \
	fi
	cp colordiffrc ${ETC_DIR}/colordiffrc
	chown root.root ${ETC_DIR}/colordiffrc
	chmod 644 ${ETC_DIR}/colordiffrc
	rm -f colordiff.pl.for.install

uninstall: etc
	rm -f ${INSTALL_DIR}/colordiff
	rm -f ${ETC_DIR}/colordiffrc
	rm -f ${INSTALL_DIR}/cdiff

dist:
	mkdir ${TMPDIR}
	cp -p ${DIST_FILES} ${TMPDIR}
	tar -zcvf ${TARBALL} ${TMPDIR}
	rm -fR ${TMPDIR}

clean:
	rm -f README colordiff.1 colordiff.html cdiff.1
