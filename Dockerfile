# syntax=docker/dockerfile:1-labs

FROM alpine AS live-bootstrap-src
WORKDIR /live-bootstrap
RUN <<-EOS
	set -eux

	# 2025-10-19
	wget -O- https://github.com/fosslinux/live-bootstrap/archive/63b24502c7e5bad7db5ee1d2005db4cc5905ab74.tar.gz \
		| tee >(tar xz --strip-components=1) \
		| sha256sum -c <(echo 82249ddbb0c57a34d8e6d775fa723b4a3987fd480a8777f52c8889ef001aad30 -)
	wget -O- https://github.com/ironmeld/builder-hex0/archive/a2781242d19e6be891b453d8fa827137ab5db31a.tar.gz \
		| tee >(tar xzC builder-hex0 --strip-components=1) \
		| sha256sum -c <(echo cc42c9e40b14505cd79165b49750d54959bbfb21d738fab5e7d5762a98b1d7cb -)
	wget -O- https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz \
		| tee >(tar xzC seed/stage0-posix --strip-components=1) \
		| sha256sum -c <(echo f4fdda675de90ab034fd3467ef43cddff61b3d372f8e0e5c2d25d145f224226f -)

	# fix checksums
	sed -i '
		s/95615d5576bad50dc60f308debab69224bb0efa8681522b82f624383533f70fd/85094a1e67548dab74b93c7091678f8c2738bd1668a3907240f5ea6fbdaf36e7/;
		s/b707a9bcb3098008dbe1cfa831d3847aab38143e44c1ab206c02f04916fd28c3/1470435d1102d03b10263689a187eb586d310a904c3980c737fa084a32b7c190/;
		s/35034f09b78483d09a893ee1e9ddc6cb38fe6a73ee6fe63261729faab424e31f/78aa9cbb085448f505b0195dc66302c47760c97ef724f6745268a79ce1520069/;
		s/90c4082c4019b2a045583ac338352173b9e64e51d945205378709ad76f1c25a5/339d893b330a06f85cf0dfab577d133eb7c82cbc83a0a74131f00c7b7d0c064a/;
		s/9ef04af2574cf9518c9f36dfcd0bbc99b83c1a9d42b0505dd93c20330088aaea/162de70abe81290cd18a63482a9e5ff07bf0800c6deec0deccf9d739cf888298/;
		s/0611b81ed8e369e54e51c5a0ac36b76fc172a7602538397a00b6166e1275d50a/72ca4bdf5678f2a7b96920c9573baf0b422783e9bd70290013cd4d4049faa4a6/;
		s/af5238bb99a9d9d7403861ebd7290700050214e0e4a8300b874324b6b5307fe3/fd27696d358cd4f83c89902999ff8660c8ad34f47a91cc11bbd5dc8d95e4d389/;
		s/2e4d36e9794d6646bec5c0ce4cd54932124476b451ff6d8ae7a6676e1770a19a/9a799f372ca641c339740043c9b5c4b07399aa28e9797ef1650711fdb2a8a981/;
		s/dac25836819f6201c3f9f2db683dab299ac00719c3b241290270314250d81ab7/1d270f94cfa9b5ab4ede1ec853748574a5e3b53aaeb3160d817a8e3bd768c6da/;
		s/8ea27e2743262b5f263527fff9ab99b76cdc5b2ec83243f9b8f6a789d112e614/c7a89c8eff816c021e0a85c7c675106f44e01a2456116371ff6a7c590ef4a789/;
		s/204b8b2b2e712e5b638a0ec18661d7a6e704a7d08c279666da7bf79658f9db14/cf8f3db8395ac378be26badd995a9ad35186def8402758808548562da1ef3280/;
		s/3ee21bdc9460dc56fb6482b51c9427e2b65e74e2228e0153e9ab353272e38944/75535b87799931bc2a9df8f1640e151928285397fc0b69618fc9df63b52b28f9/;
	' steps/SHA256SUMS.pkgs

	# download distfiles using mirror.sh
	apk add curl git xz
	mkdir distfiles
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
	mv distfiles /rootfs/external
	mv seed/stage0-posix/* seed/*.* steps /rootfs
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
	BINUTILS=binutils-2.45
	GCC=gcc-15.2.0
	GLIBC=glibc-2.41
	WGET=wget-1.25.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/glibc/$GLIBC.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ

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

	cd ..
	rm -r bootstrap-64

	# for gcc
	ln -s /lib64/libm.so.6 /usr/local/$TARGET/lib64
	ln -s /usr/local/bin/$TARGET-cpp /lib/cpp

	# for coreutils
	rm /usr/include/stropts.h
EOS

FROM x86_64-pc-linux-gnu AS gentoo-gnu
ARG GENTOO=4ff72634fd6dd4da1c91ececea47aa17133d2b3e # 2025-12-18
RUN <<-EOS
	set -eux

	# portage-3.0.70: find: invalid predicate `-files0-from'
	PORTAGE=portage-3.0.69.3

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0 /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	# for portage
	ln -s tar /usr/bin/gtar

	# fix make; live-bootstrap's is not usable with -jN
	MAKEOPTS=-j1 ./bin/emerge -1O \
		app-portage/elt-patches \
		sys-apps/gentoo-functions \
		app-arch/xz-utils \
		dev-build/make

	# fix toolchain
	USE=-* ./bin/emerge -1O \
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

	cd -
	rm -r portage-$PORTAGE

	# moving to 64bit
	emerge -1Oj \
		dev-lang/perl \
		net-misc/wget

	# diet
	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl \
		/var/cache/*
EOS

FROM gentoo-gnu AS gentoo-gnu-tarball
RUN <<-EOS
	set -eux

	emerge -1j \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind
	rm -r /var/cache/*

	tar cJf /gentoo-gnu.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/* \
		/*
EOS

# musl -------------------------------------------------------------------------------------------------------------------------

FROM live-bootstrap AS x86_64-pc-linux-musl
RUN <<-EOS
	set -eux

	TARGET=x86_64-pc-linux-musl
	BINUTILS=binutils-2.45
	GCC=gcc-15.2.0
	MUSL=musl-1.2.5
	WGET=wget-1.25.0

	mkdir bootstrap-64
	cd bootstrap-64

	curl https://ftp.gnu.org/gnu/binutils/$BINUTILS.tar.xz | tar xJ
	curl https://ftp.gnu.org/gnu/gcc/$GCC/$GCC.tar.xz | tar xJ
	curl https://musl.libc.org/releases/$MUSL.tar.gz | tar xz
	curl https://ftp.gnu.org/gnu/wget/$WGET.tar.lz | tar xJ

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

	cd ..
	rm -r bootstrap-64
EOS

FROM x86_64-pc-linux-musl AS gentoo-musl
ARG GENTOO=4ff72634fd6dd4da1c91ececea47aa17133d2b3e # 2025-12-18
RUN <<-EOS
	set -eux

	PORTAGE=portage-3.0.69.3

	mkdir -p /etc/portage /var/db/repos/gentoo
	curl -L https://github.com/gentoo/gentoo/archive/$GENTOO.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0/musl /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/$PORTAGE.tar.gz | tar xz
	cd portage-$PORTAGE

	mkdir /usr/share/portage
	cp -r cnf /usr/share/portage/config
	useradd portage

	ln -s tar /usr/bin/gtar

	MAKEOPTS=-j1 ./bin/emerge -1O \
		app-portage/elt-patches \
		sys-apps/gentoo-functions \
		app-arch/xz-utils \
		dev-build/make

	USE=-* ./bin/emerge -1O \
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

	cd -
	rm -r portage-$PORTAGE

	emerge -1Oj \
		dev-lang/perl \
		net-misc/wget

	rm -r \
		/usr/bin/perl5.{1..3}* \
		/usr/i686-unknown-linux-musl \
		/usr/include/c++ \
		/usr/lib/i686-unknown-linux-musl \
		/usr/lib/perl5 \
		/usr/lib/python2.5 \
		/usr/lib/python3.11 \
		/usr/libexec/gcc/i686-unknown-linux-musl \
		/var/cache/*
EOS

FROM gentoo-musl AS gentoo-musl-tarball
RUN <<-EOS
	set -eux

	emerge -1j \
		llvm-core/clang \
		llvm-core/lld \
		llvm-core/llvm \
		llvm-runtimes/compiler-rt \
		llvm-runtimes/libcxx \
		llvm-runtimes/libcxxabi \
		llvm-runtimes/libunwind
	rm -r /var/cache/*

	tar cJf /gentoo-musl.txz \
		--exclude /dev \
		--exclude /proc \
		--exclude /sys \
		--exclude /var/db/repos/* \
		/*
EOS

# Catalyst ---------------------------------------------------------------------------------------------------------------------

FROM gentoo-gnu AS catalyst
RUN <<-EOS
	set -eux

	echo shadow:x:42: >> /etc/group
	USE=-* emerge -1Oj \
		sys-apps/diffutils \
		sys-apps/shadow

	emerge -j --autounmask --autounmask-continue dev-util/catalyst
EOS

COPY --from=gentoo-gnu-tarball /gentoo-gnu.txz /var/tmp/catalyst/builds/seed/
COPY --from=gentoo-musl-tarball /gentoo-musl.txz /var/tmp/catalyst/builds/seed/

ARG RELENG=656eb9734f2f936fcf136d269cfd0f63442954eb # latest releases/specs/amd64 and releases/portage/stages
RUN --security=insecure <<-EOS
	set -eux

	cat >> /etc/catalyst/catalyst.conf <<-EOF
		jobs = $(nproc)
		load-average = $(nproc)
		var_tmpfs_portage = 16
	EOF

	catalyst -s stable
	wget -O- https://github.com/gentoo/releng/archive/$RELENG.tar.gz | tar xz
	cd releng-$RELENG

	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)
	REPO_DIR=$(pwd)
	SPECS=(
		releases/specs/amd64/llvm/*
		releases/specs/amd64/musl-llvm/*
	)

	sed -i '/source_subpath:/c source_subpath: seed/gentoo-gnu' releases/specs/amd64/llvm/stage1*
	sed -i '/source_subpath:/c source_subpath: seed/gentoo-musl' releases/specs/amd64/musl-llvm/stage1*
	sed -i "
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
		s|@REPO_DIR@|$REPO_DIR|g
	" ${SPECS[@]}

	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch
COPY --from=catalyst /var/tmp/catalyst/builds /
