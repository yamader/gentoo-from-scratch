# syntax=docker/dockerfile:1-labs

FROM alpine AS live-bootstrap-src
COPY live-bootstrap.patch /
RUN --mount=type=cache,target=/live-bootstrap/distfiles <<-EOS
	set -eux

	mkdir -p live-bootstrap
	cd live-bootstrap

	# 2026-03-12
	wget -O- https://github.com/fosslinux/live-bootstrap/archive/f824b6f9ac8f54ea327df1e6093cd2109c71c4c2.tar.gz \
		| tee >(tar xz --strip-components=1) \
		| sha256sum -c <(echo 085e0873b9cd78b8771800073d0764e29f762d5e7962c9591f94c32f6d38a0bc -)
	wget -O- https://github.com/ironmeld/builder-hex0/archive/a2781242d19e6be891b453d8fa827137ab5db31a.tar.gz \
		| tee >(tar xzC builder-hex0 --strip-components=1) \
		| sha256sum -c <(echo cc42c9e40b14505cd79165b49750d54959bbfb21d738fab5e7d5762a98b1d7cb -)
	wget -O- https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz \
		| tee >(tar xzC seed/stage0-posix --strip-components=1) \
		| sha256sum -c <(echo f4fdda675de90ab034fd3467ef43cddff61b3d372f8e0e5c2d25d145f224226f -)

	# fix live-bootstrap
	apk add patch
	patch -p1 < /live-bootstrap.patch

	# download distfiles using mirror.sh
	apk add curl git xz
	mkdir -p distfiles
	sh mirror.sh distfiles

	# cf. rootfs.py
	cat > steps/bootstrap.cfg <<-EOF
		ARCH=x86
		ARCH_DIR=x86
		FORCE_TIMESTAMPS=False
		CHROOT=True
		UPDATE_CHECKSUMS=False
		JOBS=$(nproc)
		SWAP_SIZE=0
		FINAL_JOBS=$(nproc)
		INTERNAL_CI=False
		INTERACTIVE=False
		QEMU=False
		BARE_METAL=False
		DISK=hoge
		KERNEL_BOOTSTRAP=False
		BUILD_KERNELS=False
		CONFIGURATOR=False
		MIRRORS_LEN=0
	EOF

	# setup new root
	mkdir -p /rootfs/external
	cp -r distfiles /rootfs/external/
	mv seed/stage0-posix/* seed/*.* steps /rootfs/
	rm -r /rootfs/High\ Level\ Prototypes

	# cleanup after
	ls /rootfs > /rootfs/srcs
	cat >> /rootfs/srcs <<-EOF
		configurator
		preseed-jump.kaem
		script-generator
		seed-full.kaem
	EOF
EOS

FROM scratch AS live-bootstrap
COPY --from=live-bootstrap-src /rootfs /
# from 181 bytes hex0-seed
RUN ["./bootstrap-seeds/POSIX/x86/hex0-seed", "./x86/hex0_x86.hex0", "./x86/artifact/hex0"]
RUN ["./x86/artifact/hex0", "./x86/kaem-minimal.hex0", "./x86/artifact/kaem-0"]
RUN ["./x86/artifact/kaem-0"]
RUN rm -r $(cat srcs) /tmp/*
ENTRYPOINT ["/bin/bash"]

# GNU --------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-gnu
RUN <<-EOS
	set -eux

	TARGET=x86_64-pc-linux-gnu
	BINUTILS=binutils-2.46.0
	GCC=gcc-15.2.0
	GLIBC=glibc-2.42 # must \leq gentoo stable
	WGET=wget-1.25.0
	MAKE=make-4.4.1
	FINDUTILS=findutils-4.10.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/glibc/$GLIBC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ
	curl https://ftp.gnu.org/gnu/make/$MAKE.tar.lz | tar xJ
	curl https://ftp.gnu.org/gnu/findutils/$FINDUTILS.tar.xz | tar xJ

	# merge-usr for glibc
	ln -s usr/lib64 /

	# wget w/ openssl for portage
	cd $WGET
	./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
	make -j$(nproc) install
	cd -

	cd $BINUTILS
	./configure --target=$TARGET --disable-gprofng
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-gcc
	cd $GCC/build-gcc
	# --disable-fixincludes: prevent /usr/local/lib/gcc/x86_64-pc-linux-gnu/15.2.0/include-fixed/stdio.h for glibc
	# --with-newlib: cf. https://ryanstan.com/gcc-without-headers-flag.html
	../configure \
		--target=$TARGET \
		--enable-languages=c,c++ \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libstdcxx \
		--disable-libvtv \
		--disable-shared \
		--disable-threads \
		--disable-fixincludes \
		--with-sysroot=/ \
		--without-headers \
		--with-newlib
	make -j$(nproc)
	make install
	cd -

	mkdir $GLIBC/build-64
	cd $GLIBC/build-64
	../configure --prefix=/usr --host=$TARGET
	make -j$(nproc)
	make install
	cd -
	mkdir $GLIBC/build-32
	cd $GLIBC/build-32
	../configure --prefix=/usr --host=i686-pc-linux-gnu CC="$TARGET-gcc -m32" CXX="$TARGET-g++ -m32"
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-libstdc++
	cd $GCC/build-libstdc++
	../libstdc++-v3/configure \
		--prefix=/usr/local/$TARGET \
		--host=$TARGET \
		--disable-multilib
	make -j$(nproc) install
	cd -

	# fix make -j in portage
	cd $MAKE
	./configure --prefix=/usr --host=$TARGET
	make -j$(nproc) install
	cd -

	# >=findutils-4.9.0 for >=portage-3.0.70
	cd $FINDUTILS
	./configure --prefix=/usr --host=$TARGET
	make -j$(nproc) install
	cd -

	cd ..
	rm -r bootstrap-64

	# fix gcc
	ln -s /lib64/libm.so.6 /usr/local/$TARGET/lib64
	ln -s /usr/local/bin/$TARGET-cpp /lib/cpp

	# fix coreutils
	rm /usr/include/stropts.h

	# fix >=portage-3.0.69.3
	ln -s tar /usr/bin/gtar

	# fix muon
	ln -sf ../local/bin/$TARGET-gcc /usr/bin/cc
	ln -sf ../local/bin/$TARGET-gcc /usr/bin/c99
EOS

FROM x86_64-pc-linux-gnu AS gentoo-gnu
ARG GENTOO_STAGE0=57edf39367851c83fde6be9c4c3995e92982ff2a # 2026-04-05; latest sys-apps/portage
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage <<-EOS
	set -eux

	PORTAGE=portage-3.0.77

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO_STAGE0.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0 /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	# muon(meson) for >=gentoo-functions-1
	curl -L https://github.com/muon-build/muon/archive/0.5.0.tar.gz | tar xz
	cd muon-0.5.0
	./bootstrap.sh build
	build/muon-bootstrap setup build
	build/muon-bootstrap -C build samu
	mv build/muon /usr/bin/muon
	ln -s muon /usr/bin/meson
	echo -e '#!/bin/sh\nmuon samu' > /usr/bin/ninja
	chmod +x /usr/bin/ninja
	cd -

	# meson-format-array for meson.eclass
	USE=python_targets_python3_11 ./bin/emerge -1Oq meson-format-array
	echo -e '#!/bin/sh\n/usr/lib/python-exec/python3.11/$(basename $0)' > /usr/lib/python-exec/python-exec2
	chmod +x /usr/lib/python-exec/python-exec2

	# fix portage
	USE=-* ./bin/emerge -1Oq \
		sys-apps/gentoo-functions \
		app-portage/elt-patches

	# fix toolchain
	USE=-* ./bin/emerge -1Oq \
		sys-libs/zlib \
		sys-devel/binutils-config \
		sys-devel/binutils \
		dev-build/autoconf \
		dev-build/automake \
		net-misc/rsync \
		sys-kernel/linux-headers \
		dev-libs/gmp \
		dev-libs/mpfr \
		dev-libs/mpc \
		sys-devel/gcc-config \
		sys-devel/gcc

	# fix collisions
	mv /bin/{bzip2,bc,dc,gunzip,gzip,zcat} /usr/local/bin
	USE=-* ./bin/emerge -1Oj \
		app-arch/bzip2 \
		app-arch/gzip \
		sys-devel/bc

	rm -r /usr/local

	# fix profile
	USE=-* ./bin/emerge -1Oj \
		app-crypt/libb2 \
		sys-apps/util-linux \
		sys-devel/gettext \
		sys-libs/libxcrypt \
		virtual/libcrypt

	./bin/emerge -1j sys-apps/portage

	cd ..
	rm -r portage-$PORTAGE

	# fix systemd
	sed -i 's/nogroup/nobody/' /etc/group

	# diet
	echo shadow:x:42: >> /etc/group
	USE=-* emerge -1Oj \
		net-misc/wget \
		sys-apps/grep \
		sys-apps/shadow
	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl
	emerge -1Oj dev-lang/perl
EOS
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage \
	emerge -uDN -j3 @world

FROM gentoo-gnu AS stage0-amd64-llvm
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage <<-EOS
	set -eux

	USE='default-compiler-rt default-libcxx default-lld llvm-libunwind' \
	emerge -1j --autounmask-continue \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind

	CXX=clang++ emerge -1Oq dev-libs/jsoncpp dev-build/cmake

	tar cJf /stage0-amd64-llvm.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/gentoo \
		/*
EOS

# musl -------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-musl
RUN <<-EOS
	set -eux

	TARGET=x86_64-pc-linux-musl
	BINUTILS=binutils-2.46.0
	GCC=gcc-15.2.0
	MUSL=musl-1.2.5
	WGET=wget-1.25.0
	MAKE=make-4.4.1
	FINDUTILS=findutils-4.10.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://musl.libc.org/releases/$MUSL.tar.gz | tar xz
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ
	curl https://ftp.gnu.org/gnu/make/$MAKE.tar.lz | tar xJ
	curl https://ftp.gnu.org/gnu/findutils/$FINDUTILS.tar.xz | tar xJ

	cd $WGET
	./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
	make -j$(nproc) install
	cd -

	cd $BINUTILS
	./configure --target=$TARGET --disable-gprofng
	make -j$(nproc)
	make install
	cd -

	mkdir $GCC/build-gcc
	cd $GCC/build-gcc
	../configure \
		--target=$TARGET \
		--enable-languages=c,c++ \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libquadmath \
		--disable-libssp \
		--disable-libstdcxx \
		--disable-libvtv \
		--disable-shared \
		--disable-threads \
		--with-sysroot=/ \
		--without-headers \
		--with-newlib
	make -j$(nproc)
	make install
	cd -

	cd $MUSL
	./configure --prefix=/usr --target=$TARGET
	make -j$(nproc) install
	cd -

	mkdir $GCC/build-libstdc++
	cd $GCC/build-libstdc++
	../libstdc++-v3/configure \
		--prefix=/usr/local/$TARGET \
		--host=$TARGET \
		--disable-multilib
	make -j$(nproc) install
	cd -

	cd $MAKE
	# fix make
	curl -L https://github.com/gentoo/gentoo/raw/945e301/dev-build/make/files/make-4.4.1-c23.patch | patch -p1
	./configure --prefix=/usr --host=$TARGET
	make -j$(nproc) install
	cd -

	cd $FINDUTILS
	./configure --prefix=/usr --host=$TARGET
	make -j$(nproc) install
	cd -

	cd ..
	rm -r bootstrap-64

	ln -s tar /usr/bin/gtar

	ln -sf ../local/bin/$TARGET-gcc /usr/bin/cc
	ln -sf ../local/bin/$TARGET-gcc /usr/bin/c99
EOS

FROM x86_64-pc-linux-musl AS gentoo-musl
ARG GENTOO_STAGE0=57edf39367851c83fde6be9c4c3995e92982ff2a
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage <<-EOS
	set -eux

	PORTAGE=portage-3.0.77

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO_STAGE0.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0/musl /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	curl -L https://github.com/muon-build/muon/archive/0.5.0.tar.gz | tar xz
	cd muon-0.5.0
	./bootstrap.sh build
	build/muon-bootstrap setup build
	build/muon-bootstrap -C build samu
	mv build/muon /usr/bin/muon
	ln -s muon /usr/bin/meson
	echo -e '#!/bin/sh\nmuon samu' > /usr/bin/ninja
	chmod +x /usr/bin/ninja
	cd -

	USE=python_targets_python3_11 ./bin/emerge -1Oq meson-format-array
	echo -e '#!/bin/sh\n/usr/lib/python-exec/python3.11/$(basename $0)' > /usr/lib/python-exec/python-exec2
	chmod +x /usr/lib/python-exec/python-exec2

	USE=-* ./bin/emerge -1Oq \
		sys-apps/gentoo-functions \
		app-portage/elt-patches

	USE=-* ./bin/emerge -1Oq \
		sys-libs/zlib \
		sys-devel/binutils-config \
		sys-devel/binutils \
		dev-build/autoconf \
		dev-build/automake \
		net-misc/rsync \
		sys-kernel/linux-headers \
		sys-libs/musl \
		dev-libs/gmp \
		dev-libs/mpfr \
		dev-libs/mpc \
		sys-devel/gcc-config \
		sys-devel/gcc

	mv /bin/{bzip2,gunzip,gzip,zcat} /usr/local/bin
	USE=-* ./bin/emerge -1Oj \
		app-arch/bzip2 \
		app-arch/gzip

	rm -r /usr/local

	USE=-* ./bin/emerge -1Oj \
		app-crypt/libb2 \
		sys-apps/util-linux \
		sys-devel/gettext

	./bin/emerge -1j sys-apps/portage

	cd ..
	rm -r portage-$PORTAGE

	sed -i 's/nogroup/nobody/' /etc/group

	echo shadow:x:42: >> /etc/group
	USE=-* emerge -1Oj \
		net-misc/wget \
		sys-apps/grep \
		sys-apps/shadow
	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl
	emerge -1Oj dev-lang/perl
EOS
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage \
	emerge -uDN -j3 @world

FROM gentoo-musl AS stage0-amd64-musl-llvm
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage <<-EOS
	set -eux

	USE='default-compiler-rt default-libcxx default-lld llvm-libunwind' \
	emerge -1j --autounmask-continue \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind

	CXX=clang++ emerge -1Oq dev-libs/jsoncpp dev-build/cmake

	tar cJf /stage0-amd64-musl-llvm.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/gentoo \
		/*
EOS

# Catalyst ---------------------------------------------------------------------------------------------------------------------

FROM gentoo-gnu AS catalyst
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/portage \
	emerge -j --autounmask --autounmask-continue dev-util/catalyst

COPY --from=stage0-amd64-llvm /stage0-amd64-llvm.txz /var/tmp/catalyst/builds/seed/
COPY --from=stage0-amd64-musl-llvm /stage0-amd64-musl-llvm.txz /var/tmp/catalyst/builds/seed/

ARG RELENG=759b2ae92949135bca28eb3132eb3060b9c0f708 # latest releases/specs/amd64 and releases/portage/stages
RUN --mount=type=cache,target=/var/cache/distfiles --mount=type=tmpfs,target=/var/tmp/catalyst/tmp --security=insecure <<-EOS
	set -eux

	echo jobs = 3 >> /etc/catalyst/catalyst.conf
	echo unset MAKEOPTS >> /etc/catalyst/catalystrc

	catalyst -s stable
	wget -O- https://github.com/gentoo/releng/archive/$RELENG.tar.gz | tar xz
	cd releng-$RELENG

	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)
	REPO_DIR=$(pwd)
	SPECS=( releases/specs/amd64/{,musl-}llvm/*.spec )

	sed -i '/source_subpath:/c source_subpath: seed/stage0-amd64-llvm' releases/specs/amd64/llvm/stage1*
	sed -i '/source_subpath:/c source_subpath: seed/stage0-amd64-musl-llvm' releases/specs/amd64/musl-llvm/stage1*
	sed -i "
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
		s|@REPO_DIR@|$REPO_DIR|g
	" ${SPECS[@]}

	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch AS target
COPY --from=catalyst /var/tmp/catalyst/builds /
