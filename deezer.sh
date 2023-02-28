#
# Maintainer: Ken Hoo <60463234+mrkenhoo@users.noreply.github.com>
#
# Original authors:
#   - Sibren Vasse <arch@sibrenvasse.nl>
#   - Ilya Gulya <ilyagulya@gmail.com>
#
set -e

pkgname=deezer
pkgver=5.30.400
pkgrel=2
_pkgname=$pkgname-$pkgver-$pkgrel
arch=amd64
srcdir="`pwd`/src"
pkgdir="`pwd`/pkg"
tmpdir="$srcdir/tmp"

help()
{
    echo "Usage: `basename $0` [OPTIONS]

Options:
  --build-package,-b    Build package for $pkgname
  --install-package,-i  Install the $pkgname package
  --uninstall,-u        Uninstall $pkgname
  --cleanup,-c          Uninstall build dependencies and remove source files
  --help,-h             Show this help message"

    return $?
}

main()
{
    tmpfile=$(mktemp)

    if test $DISPLAY
    then
        zenity --list \
               --title="Choose your distribution" \
               --column=ID --column=Distribution \
               opensuse "openSUSE" \
               debian "Debian GNU/Linux" \
               rhel "Red Hat Enterprise Linux" > $tmpfile
        case "`cat $tmpfile`" in
            opensuse) export PACKAGE_TYPE="rpm" LINUX_DISTRIBUTION="opensuse";;
            rhel) export PACKAGE_TYPE="rpm" LINUX_DISTRIBUTION="rhel";;
            debian) export PACKAGE_TYPE="deb" LINUX_DISTRIBUTION="debian";;
        esac
    else
        dialog --menu "Choose your distribution" 10 35 1 \
            1 openSUSE \
            2 RHEL \
            3 Debian 2> $tmpfile

        case "`cat $tmpfile`" in
            1) export PACKAGE_TYPE="rpm" LINUX_DISTRIBUTION="opensuse";;
            2) export PACKAGE_TYPE="rpm" LINUX_DISTRIBUTION="rhel";;
            3) export PACKAGE_TYPE="deb" LINUX_DISTRIBUTION="debian";;
        esac
    fi

    return $?
}

prepare()
{
    if test ! -z $LINUX_DISTRIBUTION
    then
        if test $LINUX_DISTRIBUTION = "opensuse"
        then
            sudo zypper install -y ImageMagick curl nodejs npm p7zip-full || return 1
        elif test $LINUX_DISTRIBUTION = "rhel"
        then
            sudo dnf install -y ImageMagick curl nodejs npm p7zip-full || return 1
        elif test $LINUX_DISTRIBUTION = "debian"
        then
            sudo apt install -y imagemagick curl nodejs npm p7zip-full || return 1
        else
            echo "Unknown distribution: $LINUX_DISTRIBUTION" && exit 1
        fi
    else
        echo "No distribution chosen, exiting..." && exit 1
    fi

    test ! -d "$srcdir" && mkdir -pv "$srcdir"
    test ! -d "$tmpdir" && mkdir -pv "$tmpdir"
    test ! -d "$pkgdir" && mkdir -pv "$pkgdir"
    test ! -d "$pkgdir/$_pkgname" && mkdir -pv "$pkgdir/$_pkgname"

    cd "$srcdir" || return 1
    sudo npm install -g electron@^13 --unsafe-perm=true
    sudo npm install -g --engine-strict @electron/asar
    sudo npm install -g prettier

    if test "$PACKAGE_TYPE" = "deb"
    then
        test ! -d  "$pkgdir/DEBIAN/" && \
            mkdir -p "$pkgdir/$_pkgname/DEBIAN/"

        test ! -f "$pkgdir/DEBIAN/control" && \
            echo "Source: $_pkgname
Package: $pkgname
Version: $pkgver-$pkgrel
Depends: nodejs
Section: non-free
Priority: optional
Architecture: $arch
Essential: no
Maintainer: Ken Hoo <60463234+mrkenhoo@users.noreply.github.com>
Copyright: Copyright (c) 2006-2022 Deezer S.A.
Description: Deezer audio streaming service" | \
                tee "$pkgdir/$_pkgname/DEBIAN/control" > /dev/null

        mkdir -pv "$pkgdir/$_pkgname/usr/share/deezer"
        mkdir -pv "$pkgdir/$_pkgname/usr/share/applications"
        mkdir -pv "$pkgdir/$_pkgname/usr/bin/"

        if test ! -f "$pkgdir/$_pkgname/usr/bin/deezer"
        then
            echo 'exec electron /usr/share/deezer/app.asar "$@"' | \
                tee "$pkgdir/$_pkgname/usr/bin/deezer" > /dev/null
        fi

        for size in 16 32 48 64 128 256; do
            if test ! -d  "$size"
            then
                mkdir -p "$pkgdir/$_pkgname/usr/share/icons/hicolor/${size}x${size}/apps/"
            fi
        done
    elif test "$PACKAGE_TYPE" = "rpm"
    then
        electron-installer-redhat \
            --src "$pkgdir/$_pkgname" \
            --dest "$srcdir" \
            --arch "$arch" \
            --options.productName "$pkgname" \
            --options.icon "$pkgdir/$_pkgname/usr/share/icons/hicolor/apps/deezer.png" \
            --options.desktopTemplate "src/deezer.desktop.ejs"
    fi

    return $?
}

build()
{
    test ! -f "$tmpdir/$pkgname-$pkgver-setup.exe" && \
        curl -fSL "https://www.deezer.com/desktop/download/artifact/win32/x86/$pkgver" \
            -o "$tmpdir/$pkgname-$pkgver-setup.exe"

     test ! -f "$tmpdir/app-32.7z" && \
        7z x -so "$tmpdir/$pkgname-$pkgver-setup.exe" "\$PLUGINSDIR/app-32.7z" > "$tmpdir/app-32.7z"

     test ! -d  "$tmpdir/deezer" && \
        7z x -bsp0 -bso0 -y "$tmpdir/app-32.7z" -o"$tmpdir/deezer"

    convert "$tmpdir/deezer/resources/win/app.ico" "$tmpdir/deezer/resources/win/deezer.png"

    test -d "$tmpdir/deezer/resources/" && \
        cd "$tmpdir/deezer/resources/"

    test -d "app" && rm -rf "app" || \
        test -d "npm_temp" && rm -rf "npm_temp"

    asar extract "app.asar" "app" && \
        test ! -d  "app/resources/linux" && \
            mkdir -p "app/resources/linux/"

    test -d "app/node_modules/@nodert" && \
        rm -r "app/node_modules/@nodert"

    test ! -d  "npm_temp" && mkdir "npm_temp" && \
        npm install --prefix npm_temp mpris-service

    for d in npm_temp/node_modules/*
    do
        test ! -d  "app/node_modules/`basename $d`" && \
           mv "$d" "app/node_modules/"
    done

    test -d "app/resources/linux" && \
        install -Dm644 "win/systray.png" "app/resources/linux/"

    cd "app" && prettier --loglevel error --write "build/*.js"

    # Hide to tray (https://github.com/SibrenVasse/deezer/issues/4)
    patch -p1 < "../../../../quit.patch"

    # Add start in tray cli option (https://github.com/SibrenVasse/deezer/pull/12)
    patch --forward --strip=1 --input="../../../../start-hidden-on-tray.patch"

    cd .. && \
        test -f "app/node_modules/abstract-socket/build/node_gyp_bins/python3" && \
            rm "app/node_modules/abstract-socket/build/node_gyp_bins/python3" || \
                asar pack "app" "app.asar"

    if test $PACKAGE_TYPE = "deb"
    then
        install -Dm644 "$tmpdir/deezer/resources/app.asar" "$pkgdir/$_pkgname/usr/share/deezer/"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-0.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/16x16/apps/deezer.png"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-1.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/32x32/apps/deezer.png"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-2.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/48x48/apps/deezer.png"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-3.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/64x64/apps/deezer.png"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-4.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/128x128/apps/deezer.png"
        install -Dm644 "$tmpdir/deezer/resources/win/deezer-5.png" "$pkgdir/$_pkgname/usr/share/icons/hicolor/256x256/apps/deezer.png"
        install -Dm644 "$srcdir/$pkgname.desktop" "$pkgdir/$_pkgname/usr/share/applications/"
        install -Dm755 "$srcdir/deezer" "$pkgdir/$_pkgname/usr/bin/"

        cd "$pkgdir/$_pkgname" && \
            dpkg-deb -v --build "`pwd`" && \
                test -x "`command -v update-desktop-database`" && \
                    update-desktop-database --quiet || \
                        echo "Build the cache database of MIME types yourself to handle the '$pkgname://' protocol"
    elif test $PACKAGE_TYPE = "rpm"
    then
        echo "Not yet implemented" && return 1
    fi

    return $?
}

install_deezer()
{
    for f in pkg/
    do
        if test "$PACKAGE_TYPE" = "deb"
        then
            if test -f "$pkgdir/$_pkgname.deb"
            then
                if test ! -x "`command -v deezer`"
                then
                    printf "Package found: $pkgdir/$_pkgname.deb\nVersion: $pkgver\nRelease version: $pkgrel\n"
                    read -p "Do you want to install it now? [Y/N] " installPackage
                    case "$installPackage" in
                        Y|y|Yes|yes|YES)
                        sudo dpkg -i "$pkgdir/$_pkgname.deb"
                    ;;
                    esac
                elif test "`dpkg -s deezer | grep Version | cut -d " " -f 2`" = "$pkgver-$pkgrel"
                then
                    echo "You are already using the latest version of $pkgname ($pkgver-$pkgrel)."
                fi
            fi
        elif "$PACKAGE_TYPE" = "rpm"
        then
            echo "Not yet implemented" && return 1
        fi
    done

    return $?
}

uninstall_deezer()
{
    for f in pkg/
    do
        if test "$PACKAGE_TYPE" = "deb"
        then
            if test -f "$pkgdir/$_pkgname.deb"
            then
                if test -x "`command -v deezer`"
                then
                    printf "Package found: $pkgdir/$_pkgname.deb\nVersion: $pkgver\nRelease version: $pkgrel\n"
                    read -p "Do you want to uninstall it now? [Y/N] " installPackage
                    case "$installPackage" in
                        Y|y|Yes|yes|YES)
                        sudo apt purge --autoremove $pkgname
                    ;;
                    esac
                elif test "`dpkg -s deezer | grep Version | cut -d " " -f 2`" = "$pkgver-$pkgrel"
                then
                    echo "You are already using the latest version of $pkgname ($pkgver-$pkgrel)."
                fi
            fi
        elif $PACKAGE_TYPE = "rpm"
        then
            echo "Not yet implemented" && return 1
        fi
    done
    
    return $?
}

cleanup()
{
    find $tmpdir/* -exec rm -rfv {} \;; return $?
}

test $# -eq 0 && help && exit 1

while getopts 'biuch' arg
do
    case $arg in
        b) main && prepare && build; exit $?;;
    	i) main && install_deezer; exit $?;;
        u) main && uninstall_deezer; exit $?;;
        c) cleanup; exit $?;;
        h) help; exit 1;;
        ?) help; exit 1;;
    esac
    shift
done
