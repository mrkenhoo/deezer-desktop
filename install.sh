#!/bin/sh
set -e

# Maintainer: Sibren Vasse <arch@sibrenvasse.nl>
# Contributor: Ilya Gulya <ilyagulya@gmail.com>
pkgname="deezer"
pkgver=5.30.310
srcdir="$PWD"

help()
{
    echo "Usage: $0 [OPTIONS]

Options:
  --install-app,-i      Install Deezer desktop app
  --uninstall-app,-u    Uninstall Deezer desktop app
  --help,-h		Show this help message"
    return $?
}

install_dependencies() {
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
}

prepare() {
    # Download installer
    wget "https://www.deezer.com/desktop/download/artifact/win32/x86/$pkgver" -O "$pkgname-$pkgver-setup.exe"
    # Extract app from installer
    7z x -so $pkgname-$pkgver-setup.exe "\$PLUGINSDIR/app-32.7z" > app-32.7z
    # Extract app archive
    7z x -y -bsp0 -bso0 app-32.7z

    # Extract png from ico container
    convert resources/win/app.ico resources/win/deezer.png

    cd resources/
    rm -rf app "$srcdir/npm_temp" || true
    asar extract app.asar app

    mkdir -p app/resources/linux/

    # Remove NodeRT from package (-205.72 MiB)
    [ -d "app/node_modules/@nodert" ] && rm -r app/node_modules/@nodert

    # Install extra node modules for mpris-service
    mkdir "$srcdir/npm_temp"; cd "$srcdir/npm_temp"
    npm install  --prefix ./ mpris-service

    for d in node_modules/*; do
        if [ ! -d "$srcdir/resources/app/node_modules/$(basename $d)" ]
        then
            mv "$d" "$srcdir/resources/app/node_modules/"
        fi
    done

    cd "$srcdir/resources/app"
    mkdir -p resources/linux/
    install -Dm644 "$srcdir/resources/win/systray.png" resources/linux/

    prettier --write "build/*.js"
    # Hide to tray (https://github.com/SibrenVasse/deezer/issues/4)
    patch -p1 < "$srcdir/quit.patch"
    # Add start in tray cli option (https://github.com/SibrenVasse/deezer/pull/12)
    patch --forward --strip=1 --input="$srcdir/start-hidden-on-tray.patch"

    cd ..
    asar pack app app.asar
}

package() {
    cd "$srcdir"
    sudo mkdir -p "$pkgdir"/usr/share/deezer
    sudo mkdir -p "$pkgdir"/usr/share/applications
    sudo mkdir -p "$pkgdir"/usr/bin/
    for size in 16 32 48 64 128 256; do
        sudo mkdir -p "$pkgdir"/usr/share/icons/hicolor/${size}x${size}/apps/
    done

    sudo install -Dm644 resources/app.asar "$pkgdir"/usr/share/deezer/
    sudo install -Dm644 resources/win/deezer-0.png "$pkgdir"/usr/share/icons/hicolor/16x16/apps/deezer.png
    sudo install -Dm644 resources/win/deezer-1.png "$pkgdir"/usr/share/icons/hicolor/32x32/apps/deezer.png
    sudo install -Dm644 resources/win/deezer-2.png "$pkgdir"/usr/share/icons/hicolor/48x48/apps/deezer.png
    sudo install -Dm644 resources/win/deezer-3.png "$pkgdir"/usr/share/icons/hicolor/64x64/apps/deezer.png
    sudo install -Dm644 resources/win/deezer-4.png "$pkgdir"/usr/share/icons/hicolor/128x128/apps/deezer.png
    sudo install -Dm644 resources/win/deezer-5.png "$pkgdir"/usr/share/icons/hicolor/256x256/apps/deezer.png
    sudo install -Dm644 "$pkgname".desktop "$pkgdir"/usr/share/applications/
    sudo install -Dm755 deezer "$pkgdir"/usr/bin/

    # Make sure the deezer:// protocol handler is immediately registered as it's needed for login 
    sudo update-desktop-database --quiet
}

install_app()
{
    install_dependencies && prepare && package; [ $? = "0" ] && echo "Successfully installed Deezer Desktop!" || echo "An error occurred"
    return $1
}

uninstall_app()
{
    printf "\nUninstalling Deezer... "
    [ -f "/usr/share/deezer" ] && sudo rm -rfv /usr/share/deezer || true
    [ -f "//usr/share/applications/" ] && sudo rm -v /usr/share/applications/deezer.desktop || true
    [ -f "/usr/bin/" ] && sudo rm -v /usr/bin/deezer || true

    for size in 16 32 48 64 128 256; do
        if [ -f "/usr/share/icons/hicolor/${size}x${size}/apps/deezer.png" ]
        then
            sudo rm -v /usr/share/icons/hicolor/${size}x${size}/apps/deezer.png
        fi
    done

    sudo update-desktop-database --quiet

    sudo apt purge --autoremove \*p7zip\* \*imagemagick\* \*nodejs\* \*g++\* \*make\* \*npm\*

    [ $? = "0" ] && printf "OK.\nDeezer has been uninstalled.\n\n" || echo "An error occurred"

    return $1
}

[ $# -eq 0 ] && help && exit 0

while [ $# -eq 1 ]
do
    case "$1" in
    	--install-app|-i) install_app; exit $?;;
    	--uninstall-app|-u) uninstall_app; exit $?;;
    	--help|-h) help; exit $?;;
    	*) help; exit $?;;
    esac
    shift
done

