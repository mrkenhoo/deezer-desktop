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
pkgver=5.30.310
pkgrel=1
_pkgname=$pkgname-$pkgver-$pkgrel
srcdir="`pwd`/src/tmp"
_srcdir="`pwd`/src"
pkgdir="$_srcdir/$pkgname-$pkgver-$pkgrel"

help()
{
    echo "Usage: ${0} [OPTIONS]

Options:
  --build-deb-package,-b    Builds a deb package for $pkgname
  --install,-i              Install the Deezer deb package
  --uninstall,-u            Uninstall Deezer
  --cleanup,-c              Uninstalls build dependencies and source files
  --help,-h                 Show this help message"

    return $?
}

build()
{
    if [ "`lsb_release -cs`" = "jammy" ]
    then
    	sudo apt install -y p7zip-full imagemagick nodejs wget g++ make patch npm
    else
        curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E $SHELL -
    	sudo apt install -y p7zip-full imagemagick wget g++ make patch npm
    fi
    sudo npm install -g electron@^13 --unsafe-perm=true
    sudo npm install -g --engine-strict asar
    sudo npm install -g prettier

    [ ! -d "$srcdir" ] && mkdir $srcdir; cd $srcdir

    # Download installer
    if [ ! -f "$pkgname-$pkgver-setup.exe" ]
    then
        wget "https://www.deezer.com/desktop/download/artifact/win32/x86/$pkgver" -O "$pkgname-$pkgver-setup.exe"
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

    cd "deezer/resources/"
    [ -d "app" ] && rm -rf "app" || [ -d "npm_temp" ] && rm -rf "npm_temp"

    asar extract "app.asar" "app" && mkdir -p "app/resources/linux/"

    [ -d "app/node_modules/@nodert" ] && rm -r "app/node_modules/@nodert"

    mkdir "npm_temp" && npm install --prefix npm_temp mpris-service

    for d in npm_temp/node_modules/*; do
        if [ ! -d "app/node_modules/`basename $d`" ]
        then
            mv "$d" "app/node_modules/"
        fi
    done

    mkdir -p "app/resources/linux/" && install -Dm644 "win/systray.png" "app/resources/linux/"

    cd "app" && prettier --loglevel error --write "build/*.js"

    # Hide to tray (https://github.com/SibrenVasse/deezer/issues/4)
    patch -p1 < "../../../../quit.patch"
    # Add start in tray cli option (https://github.com/SibrenVasse/deezer/pull/12)
    patch --forward --strip=1 --input="../../../../start-hidden-on-tray.patch"

    cd .. && asar pack "app" "app.asar"

    [ ! -d "$pkgdir" ] && mkdir -p "$pkgdir"
    [ ! -d "$pkgdir/DEBIAN/" ] && sudo mkdir -p "$pkgdir/DEBIAN/"

    if [ ! -f "$pkgdir/DEBIAN/control" ]
    then
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
Description: Deezer audio streaming service" | sudo tee "$pkgdir/DEBIAN/control" > /dev/null 2>&1
    fi

    sudo mkdir -p "$pkgdir/usr/share/deezer"
    sudo mkdir -p "$pkgdir/usr/share/applications"
    sudo mkdir -p "$pkgdir/usr/bin/"

    for size in 16 32 48 64 128 256; do
        sudo mkdir -p "$pkgdir/usr/share/icons/hicolor/${size}x${size}/apps/"
    done

    sudo install -Dm644 "$srcdir/deezer/resources/app.asar" "$pkgdir/usr/share/deezer/"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-0.png" "$pkgdir/usr/share/icons/hicolor/16x16/apps/deezer.png"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-1.png" "$pkgdir/usr/share/icons/hicolor/32x32/apps/deezer.png"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-2.png" "$pkgdir/usr/share/icons/hicolor/48x48/apps/deezer.png"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-3.png" "$pkgdir/usr/share/icons/hicolor/64x64/apps/deezer.png"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-4.png" "$pkgdir/usr/share/icons/hicolor/128x128/apps/deezer.png"
    sudo install -Dm644 "$srcdir/deezer/resources/win/deezer-5.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/deezer.png"
    sudo install -Dm644 "$_srcdir/$pkgname.desktop" "$pkgdir/usr/share/applications/"
    sudo install -Dm755 "$_srcdir/deezer" "$pkgdir/usr/bin/"

    cd "$_srcdir" && dpkg-deb --build $pkgname-$pkgver-$pkgrel && sudo update-desktop-database --quiet

    return $?
}

install_deezer()
{
    if [ ! -f "$_srcdir/${_pkgname}.deb" ]
    then
        echo "Could not find the package $_srcdir/${_pkgname}.deb"
        read -p "  -> Do you want to build it and install it now? [Y/N]: " prompt
        case "$prompt" in
            Y|y|yes|Yes) build; sudo dpkg -i "$_srcdir/${_pkgname}.deb"; exit $?;;
            *) exit $?;;
        esac
    else
        sudo dpkg -i "$_srcdir/${_pkgname}.deb"
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
    sudo apt purge --autoremove -y \*p7zip\* \*imagemagick\* \*g++\* \*make\* \*npm\*
    rm -rf "$_srcdir/tmp" "$_srcdir/$pkgdir"
}

[ "$#" -eq "0" ] && help && exit $?

while [ "$#" -eq "1" ]
do
    case "$1" in
        --build-deb-package,|-b) build; exit $?;;
    	--install|-i) install_deezer; exit $?;;
        --uninstall|-u) uninstall_deezer; exit $?;;
        --cleanup|-c) cleanup; exit $?;;
    	--help|-h) help; exit $?;;
    	*) help; exit $?;;
    esac
    shift
done
