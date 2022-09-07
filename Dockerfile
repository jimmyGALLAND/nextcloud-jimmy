ARG NC_VERS

FROM php:8.0-apache-bullseye as nextcloud-tmp
ARG NC_VERS
ENV NEXTCLOUD_VERSION ${NC_VERS}


# entrypoint.sh and cron.sh dependencies
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        rsync \
        bzip2 \
        busybox-static \
        libldap-common \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    \
    mkdir -p /var/spool/cron/crontabs; \
    echo '*/5 * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data

# install the PHP extensions we need
# see https://docs.nextcloud.com/server/stable/admin_manual/installation/source_installation.html
ENV PHP_MEMORY_LIMIT 512M
ENV PHP_UPLOAD_LIMIT 512M
RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libevent-dev \
        libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libldap2-dev \
        libmcrypt-dev \
        libmemcached-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libmagickwand-dev \
        libzip-dev \
        libwebp-dev \
        libgmp-dev \
    ; \
    \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        ldap \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        zip \
        gmp \
    ; \
    \
# pecl will claim success even if one install fails, so we need to perform each install separately
    pecl install APCu-5.1.21; \
    pecl install memcached-3.2.0RC2; \
    pecl install redis-5.3.7; \
    pecl install imagick-3.7.0; \
    \
    docker-php-ext-enable \
        apcu \
        memcached \
        redis \
        imagick \
    ; \
    rm -r /tmp/pear; \
    \
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://docs.nextcloud.com/server/latest/admin_manual/installation/server_tuning.html#enable-php-opcache
RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.interned_strings_buffer=16'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.revalidate_freq=60'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
    \
    echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini; \
    \
    { \
        echo 'memory_limit=${PHP_MEMORY_LIMIT}'; \
        echo 'upload_max_filesize=${PHP_UPLOAD_LIMIT}'; \
        echo 'post_max_size=${PHP_UPLOAD_LIMIT}'; \
    } > /usr/local/etc/php/conf.d/nextcloud.ini; \
    \
    mkdir /var/www/data; \
    chown -R www-data:root /var/www; \
    chmod -R g=u /var/www

VOLUME /var/www/html

RUN a2enmod headers rewrite remoteip ;\
    {\
     echo RemoteIPHeader X-Real-IP ;\
     echo RemoteIPTrustedProxy 10.0.0.0/8 ;\
     echo RemoteIPTrustedProxy 172.16.0.0/12 ;\
     echo RemoteIPTrustedProxy 192.168.0.0/16 ;\
    } > /etc/apache2/conf-available/remoteip.conf;\
    a2enconf remoteip


RUN set -ex; \
    fetchDeps=" \
        gnupg \
        dirmngr \
    "; \
    apt-get update; \
    apt-get install -y --no-install-recommends $fetchDeps; \
    \
    curl -fsSL -o nextcloud.tar.bz2 \
        "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERS}.tar.bz2"; \
    curl -fsSL -o nextcloud.tar.bz2.asc \
        "https://download.nextcloud.com/server/releases/nextcloud-${NC_VERS}.tar.bz2.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
# gpg key from https://nextcloud.com/nextcloud.asc
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 28806A878AE423A28372792ED75899B9A724937A; \
    gpg --batch --verify nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
    tar -xjf nextcloud.tar.bz2 -C /usr/src/; \
    gpgconf --kill all; \
    rm nextcloud.tar.bz2.asc nextcloud.tar.bz2; \
    rm -rf "$GNUPGHOME" /usr/src/nextcloud/updater; \
    mkdir -p /usr/src/nextcloud/data; \
    mkdir -p /usr/src/nextcloud/custom_apps; \
    chmod +x /usr/src/nextcloud/occ; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $fetchDeps; \
    rm -rf /var/lib/apt/lists/*

COPY *.sh upgrade.exclude /
COPY config/* /usr/src/nextcloud/config/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]

# iamklaus - ENJOY IT
# jimmyGALLAND - Thx iamklaus

FROM nextcloud-tmp as builder
ARG NC_VERS
# Build and install dlib on builder
RUN apt-get update ; \
    apt-get install -y build-essential wget cmake libx11-dev libopenblas-dev shtool apt-utils

ARG DLIB_BRANCH=v19.21
RUN cd; \
    wget -c -q https://github.com/davisking/dlib/archive/$DLIB_BRANCH.tar.gz \
    && tar xf $DLIB_BRANCH.tar.gz \
    && mv dlib-* dlib \
    && cd dlib/dlib \
    && mkdir build \
    && cd build \
    && cmake -DBUILD_SHARED_LIBS=ON --config Release .. \
    && make \
    && make install

# Build and install PDLib on builder
ARG PDLIB_BRANCH=master
RUN apt-get install unzip
RUN cd; \
    wget -c -q https://github.com/matiasdelellis/pdlib/archive/$PDLIB_BRANCH.zip \
    && unzip $PDLIB_BRANCH \
    && mv pdlib-* pdlib \
    && cd pdlib \
    && phpize \
    && ./configure \
    && make \
    && make install

# Enable PDlib on builder
# If necesary take the php settings folder uncommenting the next line
# RUN php -i | grep "Scan this dir for additional .ini files"
RUN echo "extension=pdlib.so" > /usr/local/etc/php/conf.d/pdlib.ini

# Test PDlib installation on builder
RUN apt-get install -y git
RUN cd; \
    git clone https://github.com/matiasdelellis/pdlib-min-test-suite.git \
    && cd pdlib-min-test-suite \
    && make

# If pass the tests, we are able to create the final image.
FROM nextcloud-tmp
ARG NC_VERS

# Install dependencies to image
RUN apt-get update ; \
    apt-get install -y libopenblas-base

# Install dlib and PDlib to image
COPY --from=builder /usr/local/lib/libdlib.so* /usr/local/lib/

# If is necesary take the php extention folder uncommenting the next line
# RUN php -i | grep extension_dir
COPY --from=builder  /usr/local/lib/php/extensions/no-debug-non-zts-20200930/pdlib.so /usr/local/lib/php/extensions/no-debug-non-zts-20200930/

# Enable PDlib on final image
RUN echo "extension=pdlib.so" > /usr/local/etc/php/conf.d/pdlib.ini

# Set ENV varaiable for PHP memory limits (can be adjusted in docker)
RUN echo 'memory_limit=${MEMORY_LIMIT}' > /usr/local/etc/php/conf.d/memory-limit.ini
# At this point you meet all the dependencies to install the application
# If is available you can skip this step and install the application from the application store
#ARG FR_BRANCH=master
#RUN apt-get install -y wget unzip nodejs npm
#RUN wget -c -q -O facerecognition https://github.com/matiasdelellis/facerecognition/archive/$FR_BRANCH.zip \
#  && unzip facerecognition \
#  && mv facerecognition-*  /usr/src/nextcloud/facerecognition \
#  && cd /usr/src/nextcloud/facerecognition \
#  && make; \


RUN set -ex; \
    apt-get update; \
    apt-get install -y  \
        ffmpeg \
        imagemagick \
        libmagickcore-6.q16-6-extra \
        ghostscript \
        procps \
        vim \
        fontconfig \
        exiftool \
        gnupg
RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libbz2-dev \
        libc-client-dev \
    ; \
    \
    docker-php-ext-install \
        bz2 \
    ; \
    \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
;

ENV NEXTCLOUD_UPDATE=1
ENV PHP_MEMORY_LIMIT=2048M
ENV PHP_UPLOAD_LIMIT=2048M
ENV extra_params=--o:net.proto=IPv4
ENV NEXTCLOUD_VERSION ${NC_VERS}

RUN sh -x \
    && for file in `convert -list policy | grep "Path:" | grep -v built | sed 's/Path: \(.*\)/\1/g'`; \
        do \
            sed -i 's/domain="coder" rights="none" pattern="PDF"/domain="coder" rights="read|write" pattern="PDF"/g' $file ;\
        done

