# syntax=docker/dockerfile:1-labs

FROM alpine AS live-bootstrap-src
ARG LIVE_BOOTSTRAP_COMMIT=f2d7fda4601236656c8d3243845375ba1c1ad6d9
RUN <<-EOS
	apk add git

	mkdir live-bootstrap
	cd live-bootstrap
	git init
	git remote add origin https://github.com/fosslinux/live-bootstrap
	git fetch origin $LIVE_BOOTSTRAP_COMMIT
	git reset --hard FETCH_HEAD
	git submodule update --init --recursive

	{
		mkdir -p distfiles
		wget -P distfiles \
			https://files.bootstrapping.world/coreutils-9.4.tar.xz \
			https://files.bootstrapping.world/gnulib-30820c.tar.gz \
			https://files.bootstrapping.world/gnulib-8e128e.tar.gz \
			https://files.bootstrapping.world/gnulib-d279bc.tar.gz \
			https://files.bootstrapping.world/gnulib-3639c57.tar.gz \
			https://files.bootstrapping.world/gnulib-5651802.tar.gz \
			https://files.bootstrapping.world/gnulib-5d2fe24.tar.gz \
			https://files.bootstrapping.world/gnulib-672663a.tar.gz \
			https://files.bootstrapping.world/gnulib-7daa86f.tar.gz \
			https://files.bootstrapping.world/gnulib-a521820.tar.gz \
			https://files.bootstrapping.world/gnulib-b28236b.tar.gz \
			https://files.bootstrapping.world/gnulib-b81ec69.tar.gz \
			https://files.bootstrapping.world/gnulib-bb5bb43.tar.gz \
			https://files.bootstrapping.world/gnulib-d271f86.tar.gz \
			https://files.bootstrapping.world/gnulib-e017871.tar.gz \
			https://files.bootstrapping.world/gnulib-356a414e.tar.gz \
			https://files.bootstrapping.world/gnulib-52a06cb3.tar.gz \
			https://files.bootstrapping.world/gnulib-8f4538a5.tar.gz \
			https://files.bootstrapping.world/gnulib-901694b9.tar.gz
	}
	sed -i 's/curl.*true$/wget "$url" -O "$dest_path" || true/' download-distfiles.sh
	sh download-distfiles.sh

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
		BARE_METAL=False
		DISK=hoge
		KERNEL_BOOTSTRAP=False
		BUILD_KERNELS=False
		CONFIGURATOR=False
		MIRRORS_LEN=0
	EOF

	mkdir -p /rootfs/external
	mv distfiles /rootfs/external
	mv seed/stage0-posix/* seed/*.* steps /rootfs
	ls /rootfs > /rootfs/srcs
EOS

FROM scratch AS live-bootstrap
COPY --from=live-bootstrap-src /rootfs /
RUN ["/bootstrap-seeds/POSIX/x86/kaem-optional-seed"]
RUN <<-EOS
	TARGET=x86_64-pc-linux-musl

	mkdir bootstrap-64
	(
		cd bootstrap-64

		# 先に32bit環境でコンパイルしておく
		curl -L https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz | tar xz
		cd wget-1.25.0
		./configure --prefix=/usr --with-ssl=openssl --with-libssl-prefix=/usr/ssl
		make -j$(nproc) install
		cd -

		# todo: fix gcc default search path
		mkdir -p /usr/local/$TARGET
		ln -s /usr/{include,lib} /usr/local/$TARGET

		tar xf /external/distfiles/binutils-2.41.tar.xz
		cd binutils-2.41
		./configure --target=$TARGET --disable-gprofng
		make -j$(nproc)
		make install
		cd -

		tar xf /external/distfiles/gcc-13.3.0.tar.xz
		mkdir gcc-13.3.0/build-gcc
		cd gcc-13.3.0/build-gcc
		# --disable-shared and --disable-threads are for libgcc
		../configure --target=$TARGET \
			--enable-languages=c,c++ \
			--disable-libatomic \
			--disable-libgomp \
			--disable-libquadmath \
			--disable-libssp \
			--disable-libstdcxx \
			--disable-libvtv \
			--disable-shared \
			--disable-threads
		make -j$(nproc)
		make install
		cd -

		tar xf /external/distfiles/musl-1.2.5.tar.gz
		cd musl-1.2.5
		./configure --prefix=/usr --host=$TARGET
		make -j$(nproc) install
		cd -

		mkdir gcc-13.3.0/build-libstdc++
		cd gcc-13.3.0/build-libstdc++
		../libstdc++-v3/configure --prefix=/usr --host=$TARGET \
			--disable-libstdcxx-pch \
			--disable-multilib
		make -j$(nproc) install
		mv /usr/lib64/libs??c++* /usr/lib # for bfd
		cd -

		ln -sf $TARGET-gcc /usr/local/bin/gcc
		ln -sf $TARGET-g++ /usr/local/bin/g++
	)
	rm -r bootstrap-64
EOS
RUN xargs -i rm -r "{}" < srcs; rm configurator script-generator *.kaem

FROM live-bootstrap AS gentoo
RUN <<-EOS
	mkdir -p /var/db/repos/gentoo
	curl -L https://github.com/gentoo-mirror/gentoo/archive/stable.tar.gz | tar xzC /var/db/repos/gentoo --strip-components=1
	mkdir -p /etc/portage
	ln -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/23.0/musl /etc/portage/make.profile

	curl -L https://github.com/gentoo/portage/archive/portage-3.0.68.tar.gz | tar xz
	(
		cd portage-portage-3.0.68

		mkdir /usr/share/portage
		cp -r $(pwd)/cnf /usr/share/portage/config
		useradd portage

		# live-bootstrap's 32bit make is not usable with -jN
		MAKEOPTS=-j1 ./bin/emerge -1O \
			app-portage/elt-patches \
			sys-apps/gentoo-functions \
			app-arch/xz-utils \
			dev-build/make

		EXTRA_ECONF=--disable-lto USE=-* ./bin/emerge -1O \
			sys-libs/musl \
			sys-libs/zlib \
			dev-libs/gmp \
			dev-libs/mpfr \
			dev-libs/mpc \
			sys-devel/binutils-config \
			sys-devel/binutils \
			sys-devel/gcc-config \
			sys-devel/gcc
		rm -r /usr/local

		mkdir -p /usr/local/bin
		mv /usr/bin/bzip2 /usr/local/bin
		./bin/emerge -1O app-arch/bzip2
		rm /usr/local/bin/bzip2

		USE=-* ./bin/emerge -1O \
			dev-build/autoconf \
			dev-build/autoconf-wrapper \
			dev-build/automake \
			dev-build/automake-wrapper \
			net-misc/rsync \
			sys-kernel/linux-headers \
			sys-apps/util-linux \
			sys-devel/gettext \
			app-crypt/libb2
		./bin/emerge -1j sys-apps/portage
	)
	rm -r portage-portage-3.0.68
EOS

FROM gentoo AS gentoo-tarball
RUN <<-EOS
	# diet
	rm -r \
		/var/cache/* \
		/var/db/repos/* \
		/usr/lib/i386-unknown-linux-musl \
		/usr/libexec/gcc/i386-unknown-linux-musl \
		/usr/lib/python3.11

	tar cJf /stage3.txz /
EOS

FROM gentoo AS catalyst
COPY --from=gentoo-tarball /stage3.txz /var/tmp/catalyst/builds/seed/
RUN emerge --autounmask --autounmask-continue dev-util/catalyst
RUN --security=insecure <<-EOS
	catalyst -s stable
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	cat >> /etc/catalyst/catalyst.conf <<-EOF
		jobs = $(nproc)
		load-average = $(nproc)
		var_tmpfs_portage = 16
	EOF

	# seed stage4 for llvm
	cat > stage4-llvm-seed.spec <<-EOF
		subarch: amd64
		version_stamp: llvm
		target: stage4
		rel_type: seed
		source_subpath: seed/stage3
		profile: default/linux/amd64/23.0
		snapshot_treeish: $TREEISH
		stage4/packages:
		  llvm-core/clang
		  llvm-core/lld
		  llvm-core/llvm
		  llvm-runtimes/compiler-rt
		  llvm-runtimes/libcxx
		  llvm-runtimes/libcxxabi
		  llvm-runtimes/libunwind
	EOF
	catalyst -f stage4-llvm-seed.spec
EOS

ARG GENTOO_RELENG_COMMIT=c622211a2f847d473199e597d95eaf55cbbe40b2
RUN --security=insecure <<-EOS
	TREEISH=$(git -C /var/tmp/catalyst/repos/gentoo.git rev-parse stable)

	wget -O- https://github.com/gentoo/releng/archive/$GENTOO_RELENG_COMMIT.tar.gz | tar xz
	REPO_DIR=$(pwd)/releng-$GENTOO_RELENG_COMMIT
	SPECS=($REPO_DIR/releases/specs/amd64/llvm/stage?-openrc-23.spec)
	sed -i "
		s|@REPO_DIR@|$REPO_DIR|g
		s|@TIMESTAMP@|$(date -u +%Y%m%dT%H%M%SZ)|g
		s|@TREEISH@|$TREEISH|g
	" ${SPECS[@]}
	sed -i '/source/c\source_subpath: seed/stage4-amd64-llvm' $SPECS
	for i in ${SPECS[@]}; do
		catalyst -f $i
	done
EOS

FROM scratch
COPY --from=catalyst /var/tmp/catalyst/builds /
