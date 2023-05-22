# Maintainer: Ken Hoo <60463234+mrkenhoo@users.noreply.github.com>

APPNAME = org.mrkenhoo.deezer
PKGVER = 5.30.530
BASE_URL = https://www.deezer.com/desktop/download/artifact/win32/x86/$(PKGVER)
VERSION_REGEX = ^v$(PKGVER)-[0-9]{1,}$$

all: clean install_dependencies

clean:
		@echo "Cleaning build directory..."
		@$(foreach p, $(wildcard build/*), rm -rf $(p))

install_build_dependencies:
		@test ! -d build && mkdir -v build || continue

		@test ! $$(command -v npm) && echo "Please install npm" && exit 1 || continue

		@echo "[NPM] Installing package electron/asar..."
		@cd build && npm install --engine-strict electron/asar

		@echo "[NPM] Installing package prettier..."
		@cd build && npm install prettier

		@echo "[NPM] Installing package yarn..."
		@cd build && npm install yarn

prepare: clean install_build_dependencies
		@test ! -d build/tmp && mkdir -pv build/tmp || continue

		@echo "Downloading installer..."
		@cd build/tmp && curl -fSL $(BASE_URL) -o deezer-setup-$(PKGVER).exe

		@echo "Extracting files..."
		@cd build/tmp && 7z x -so deezer-setup-$(PKGVER).exe '$$PLUGINSDIR/app-32.7z' > app-32.7z

		@echo "Decompressing files..."
		@cd build/tmp && 7z x -y -bsp0 -bso0 app-32.7z -oraw_app

		@echo "Extracting source files..."
		@cd build && node_modules/.bin/asar extract tmp/raw_app/resources/app.asar app

		@echo "Making source files ready for patching..."
		@cd build && node_modules/.bin/prettier --write "app/build/*.js"

		@echo "Applying patches..."
		@$(foreach p, $(wildcard .src/patches/*.patch), patch --verbose -p1 -d build/app -i ../../$(p))
		@cat src/package-append.json >> build/app/package.json

		@echo "Fixing syntax of the file build/app/package.json..."
		@sed '34d' -i build/app/package.json || exit 1
		@sed '33d' -i build/app/package.json || exit 1
		@sed '33 i\ },"scripts": {' -i build/app/package.json

install_dependencies: prepare
		@echo "Installing dependencies for $(APPNAME), version $(PKGVER)..."
		@build/node_modules/.bin/yarn --cwd=build/app install

build_deb: install_dependencies
		@build/node_modules/.bin/yarn --cwd=build/app build-deb

build_rpm: install_dependencies
		@build/node_modules/.bin/yarn --cwd=build/app build-rpm

build_appimage: install_dependencies
		@build/node_modules/.bin/yarn --cwd=build/app build-appimage

build_tar: install_dependencies
		@build/node_modules/.bin/yarn --cwd=build/app build-tar-gz

build_all: build_deb build_rpm build_appimage build_tar

