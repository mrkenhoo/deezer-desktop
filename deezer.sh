#!/bin/sh
set -e
#
# Maintainer: Ken Hoo <60463234+mrkenhoo@users.noreply.github.com>
#
# Original authors:
#   - Sibren Vasse <arch@sibrenvasse.nl>
#   - Ilya Gulya <ilyagulya@gmail.com>
#
pkgname=deezer
_pkgname=$pkgname-$pkgver-$pkgrel
pkgver=5.30.360
pkgrel=1
arch=amd64
srcdir="`pwd`/src"
tmpdir="$srcdir/tmp"
pkgdir="$srcdir/$_pkgname"

help()
{
    echo "Usage: ${0} [OPTIONS]

Options:
  --build-deb-package,-b    Builds a deb package for $pkgname
  --install,-i              Install the $pkgname deb package
  --uninstall,-u            Uninstall $pkgname
  --cleanup,-c              Uninstalls build dependencies and source files
  --help,-h                 Show this help message"

    return $?
}

createDesktopFile_deb()
{
    echo "Source: $pkgname-$pkgver-$pkgrel
Package: $pkgname
Version: $pkgver-$pkgrel
Depends: nodejs
Section: non-free
Priority: optional
Architecture: amd64
Essential: no
Maintainer: Ken Hoo <60463234+mrkenhoo@users.noreply.github.com>
Copyright: Copyright (c) 2006-2022 Deezer S.A.
Description: Deezer audio streaming service" | tee "$pkgdir/DEBIAN/control"
}

build_deb()
{
    if [ $BUILD_TYPE = "deb" ]
    then
        for p in lsb-release curl
        do
            [ ! -x "`command -v ${p}`" ] && sudo apt install -y "${p}"
        done

        for r in jammy bullseye
        do
            [ "`lsb_release -cs`" = "${r}" ] && \
                sudo apt install -y p7zip-full imagemagick nodejs patch npm && break || \
                    curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E $SHELL -
        done
    elif [ "$BUILD_TYPE" = "rpm" ]
        if [ "$DISTRO_TYPE" = "opensuse" ]
        then
            for p in lsb-release curl
            do
                [ ! -x "`command -v ${p}`" ] && sudo zypper in -y "${p}"
            done

            sudo zypper in p7zip-full ImageMagick nodejs patch npm
        elif [ "$DISTRO_TYPE" = "fedora" ]
            for p in lsb-release curl
            do
                [ ! -x "`command -v ${p}`" ] && sudo dnf install -y "${p}"
            done

            sudo dnf install p7zip-full ImageMagick nodejs patch npm
        else
            [ ! -z "$DISTRO_TYPE" ] && echo "ERROR: $DISTRO_TYPE: Unknown distribution" && exit 1 || \
            echo "ERROR: No distribution was specified" && exit 1
        fi
    else
        [ ! -z "$BUILD_TYPE" ] && echo "ERROR: $BUILD_TYPE: Unknown build type" && exit 1 || \
            echo "ERROR: No build type was specified" && exit 1
    fi

    npm install electron@^13 --unsafe-perm=true
    npm install --engine-strict asar
    npm install prettier

    [ ! -d "$srcdir" ] && mkdir $srcdir && cd $srcdir

    # Download installer
    if [ ! -f "$pkgname-$pkgver-setup.exe" ]
    then
        curl -fSL "https://www.deezer.com/desktop/download/artifact/win32/x86/$pkgver" -o \
            "$pkgname-$pkgver-setup.exe"
    fi

    if [ ! -f "app-32.7z" ]
    then
        7z x -so "$pkgname-$pkgver-setup.exe" "\$PLUGINSDIR/app-32.7z" > "app-32.7z"
    fi

    if [ ! -d "deezer" ]
    then
        7z x -bsp0 -bso0 -y "app-32.7z" -odeezer
    fi

    convert "deezer/resources/win/app.ico" "deezer/resources/win/deezer.png"

    [ -d "deezer/resources/" ] && cd "deezer/resources/"

    [ -d "app" ] && rm -rf "app" || \
        [ -d "npm_temp" ] && rm -rf "npm_temp"

    asar extract "app.asar" "app" && \
        [ ! -d "app/resources/linux" ] && \
            mkdir -p "app/resources/linux/"

    [ -d "app/node_modules/@nodert" ] && rm -r "app/node_modules/@nodert"

    [ ! -d "npm_temp" ] && mkdir "npm_temp" && \
        npm install --prefix npm_temp mpris-service

    for d in npm_temp/node_modules/*; do
        if [ ! -d "app/node_modules/`basename $d`" ]
        then
            mv "$d" "app/node_modules/"
        fi
    done

    [ -d "app/resources/linux" ] && install -Dm644 "win/systray.png" "app/resources/linux/" || exit 1

    cd "app" && prettier --loglevel error --write "build/*.js"

    # Hide to tray (https://github.com/SibrenVasse/deezer/issues/4)
    patch -p1 < "../../../../quit.patch"
    # Add start in tray cli option (https://github.com/SibrenVasse/deezer/pull/12)
    patch --forward --strip=1 --input="../../../../start-hidden-on-tray.patch"

    cd .. && \
        rm "app/node_modules/abstract-socket/build/node_gyp_bins/python3" || \
            asar pack "app" "app.asar"

    [ "$BUILD_TYPE" != "deb" ] && return $?

    [ ! -d "$pkgdir" ] && mkdir -p "$pkgdir"
    [ ! -d "$pkgdir/DEBIAN/" ] && mkdir -p "$pkgdir/DEBIAN/"

    [ ! -f "$pkgdir/DEBIAN/control" ] && createDesktopFile || exit 1

    mkdir -p "$pkgdir/usr/share/deezer"
    mkdir -p "$pkgdir/usr/share/applications"
    mkdir -p "$pkgdir/usr/bin/"

    for size in 16 32 48 64 128 256; do
        [ ! -d "$size" ] && mkdir -p "$pkgdir/usr/share/icons/hicolor/${size}x${size}/apps/"
    done

    install -Dm644 "$srcdir/deezer/resources/app.asar" "$pkgdir/usr/share/deezer/"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-0.png" "$pkgdir/usr/share/icons/hicolor/16x16/apps/deezer.png"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-1.png" "$pkgdir/usr/share/icons/hicolor/32x32/apps/deezer.png"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-2.png" "$pkgdir/usr/share/icons/hicolor/48x48/apps/deezer.png"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-3.png" "$pkgdir/usr/share/icons/hicolor/64x64/apps/deezer.png"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-4.png" "$pkgdir/usr/share/icons/hicolor/128x128/apps/deezer.png"
    install -Dm644 "$srcdir/deezer/resources/win/deezer-5.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/deezer.png"
    install -Dm644 "$srcdir/$pkgname.desktop" "$pkgdir/usr/share/applications/"
    install -Dm755 "$srcdir/deezer" "$pkgdir/usr/bin/"

    cd "$srcdir" && dpkg-deb --build $pkgname-$pkgver-$pkgrel && \
        [ "`command -v update-desktop-database`" ] && \
            update-desktop-database --quiet

    return $?
}

build_rpm()
{
    BUILD_TYPE="rpm" DISTRO_TYPE="$1" build || exit $?

    electron-installer-redhat \
        --src $srcdir/app
        --dest $srcdir
        --arch $arch
        --options.productName $pkgname
        --options.icon $pkgdir/usr/share/icons/hicolor/apps/deezer.png
        --options.desktopTemplate src/deezer.desktop.ejs

    return $?
}

install_deezer()
{
    if [ ! -f "$srcdir/${_pkgname}.deb" ]
    then
        echo "Could not find the package $srcdir/${_pkgname}.deb"
        read -p "  -> Do you want to build it and install it now? [Y/N]: " prompt
        case "$prompt" in
            Y|y|yes|Yes) build; sudo dpkg -i "$srcdir/${_pkgname}.deb"; exit $?;;
            *) exit $?;;
        esac
    else
        sudo dpkg -i "$srcdir/${_pkgname}.deb"
    fi

    return $?
}

uninstall_deezer()
{
    if [ -x "`command -v deezer`" ]
    then
        sudo apt purge --autoremove deezer
    else
        echo "Deezer is not installed"
        exit 1
    fi
}

cleanup()
{
    sudo apt purge --autoremove \*p7zip\* \*imagemagick\* \*nodejs\* \*patch\ \*npm\*
    rm -rf "${tmpdir}" "$srcdir/$pkgdir"
}

[ "$#" -eq "0" ] && help && exit $?

while [ "$#" -eq "1" ]
do
    case "$1" in
        --build-deb-package|-b) build; exit $?;;
        --build-rpm-package|-B) build_rpm; exit $?;;
    	--install|-i) install_deezer; exit $?;;
        --uninstall|-u) uninstall_deezer; exit $?;;
        --cleanup|-c) cleanup; exit $?;;
    	--help|-h) help; exit $?;;
    	*) help; exit $?;;
    esac
    shift
done
