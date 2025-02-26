# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

include $(MOZILLA_DIR)/toolkit/mozapps/installer/package-name.mk
include $(MOZILLA_DIR)/toolkit/mozapps/installer/upload-files.mk

# This is how we create the binary packages we release to the public.

# browser/locales/Makefile uses this makefile for its variable defs, but
# doesn't want the libs:: rule.
ifndef PACKAGER_NO_LIBS
libs:: make-package
endif

export USE_ELF_HACK ELF_HACK_FLAGS

# Override the value of OMNIJAR_NAME from config.status with the value
# set earlier in this file.

stage-package: multilocale.txt locale-manifest.in $(MOZ_PKG_MANIFEST) $(MOZ_PKG_MANIFEST_DEPS)
	OMNIJAR_NAME=$(OMNIJAR_NAME) \
	NO_PKG_FILES="$(NO_PKG_FILES)" \
	$(PYTHON) $(MOZILLA_DIR)/toolkit/mozapps/installer/packager.py $(DEFINES) $(ACDEFINES) \
		--format $(MOZ_PACKAGER_FORMAT) \
		$(addprefix --removals ,$(MOZ_PKG_REMOVALS)) \
		$(if $(filter-out 0,$(MOZ_PKG_FATAL_WARNINGS)),,--ignore-errors) \
		$(if $(MOZ_PACKAGER_MINIFY),--minify) \
		$(if $(MOZ_PACKAGER_MINIFY_JS),--minify-js \
		  $(addprefix --js-binary ,$(JS_BINARY)) \
		) \
		$(if $(JARLOG_DIR),$(addprefix --jarlog ,$(wildcard $(JARLOG_FILE_AB_CD)))) \
		$(if $(OPTIMIZEJARS),--optimizejars) \
		$(addprefix --compress ,$(JAR_COMPRESSION)) \
		$(MOZ_PKG_MANIFEST) '$(DIST)' '$(DIST)'/$(MOZ_PKG_DIR)$(if $(MOZ_PKG_MANIFEST),,$(_BINPATH)) \
		$(if $(filter omni,$(MOZ_PACKAGER_FORMAT)),$(if $(NON_OMNIJAR_FILES),--non-resource $(NON_OMNIJAR_FILES)))
	$(PYTHON) $(MOZILLA_DIR)/toolkit/mozapps/installer/find-dupes.py $(DEFINES) $(ACDEFINES) $(MOZ_PKG_DUPEFLAGS) $(DIST)/$(MOZ_PKG_DIR)
ifndef MOZ_IS_COMM_TOPDIR
	# Package mozharness
	$(call py_action,test_archive, \
		mozharness \
		$(ABS_DIST)/$(PKG_PATH)$(MOZHARNESS_PACKAGE))
endif # MOZ_IS_COMM_TOPDIR
ifdef MOZ_PACKAGE_JSSHELL
	# Package JavaScript Shell
	@echo 'Packaging JavaScript Shell...'
	$(RM) $(PKG_JSSHELL)
	$(MAKE_JSSHELL)
endif # MOZ_PACKAGE_JSSHELL
ifdef MOZ_ARTIFACT_BUILD_SYMBOLS
	@echo 'Packaging existing crashreporter symbols from artifact build...'
	$(NSINSTALL) -D $(DIST)/$(PKG_PATH)
	cd $(DIST)/crashreporter-symbols && \
          zip -r5D '../$(PKG_PATH)$(SYMBOL_ARCHIVE_BASENAME).zip' . -i '*.sym' -i '*.txt'
endif # MOZ_ARTIFACT_BUILD_SYMBOLS
ifdef MOZ_CODE_COVERAGE
	@echo 'Generating chrome-map for coverage data...'
	$(topsrcdir)/mach build-backend -b ChromeMap
	@echo 'Packaging code coverage data...'
	$(RM) $(CODE_COVERAGE_ARCHIVE_BASENAME).zip
	$(PYTHON) -mmozbuild.codecoverage.packager \
		--output-file='$(DIST)/$(PKG_PATH)$(CODE_COVERAGE_ARCHIVE_BASENAME).zip'
endif
ifdef ENABLE_MOZSEARCH_PLUGIN
	@echo 'Generating mozsearch index tarball...'
	$(RM) $(MOZSEARCH_ARCHIVE_BASENAME).zip
	cd $(topobjdir)/mozsearch_index && \
          zip -r5D '$(ABS_DIST)/$(PKG_PATH)$(MOZSEARCH_ARCHIVE_BASENAME).zip' .
	@echo 'Generating mozsearch rust-analysis tarball...'
	$(RM) $(MOZSEARCH_RUST_ANALYSIS_BASENAME).zip
	cd $(topobjdir)/ && \
          find . -type d -name save-analysis | xargs zip -r5D '$(ABS_DIST)/$(PKG_PATH)$(MOZSEARCH_RUST_ANALYSIS_BASENAME).zip'
endif
ifeq (Darwin, $(OS_ARCH))
ifdef MOZ_ASAN
	@echo "Rewriting ASan runtime dylib paths for all binaries in $(DIST)/$(MOZ_PKG_DIR)$(_BINPATH) ..."
	$(PYTHON) $(MOZILLA_DIR)/build/unix/rewrite_asan_dylib.py $(DIST)/$(MOZ_PKG_DIR)$(_BINPATH)
endif # MOZ_ASAN
endif # Darwin
ifdef MOZ_STYLO
ifndef MOZ_ARTIFACT_BUILDS
	@echo 'Packing stylo binding files...'
	cd '$(DIST)/rust_bindings/style' && \
		zip -r5D '$(ABS_DIST)/$(PKG_PATH)$(STYLO_BINDINGS_PACKAGE)' .
endif # MOZ_ARTIFACT_BUILDS
endif # MOZ_STYLO

prepare-package: stage-package

make-package-internal: prepare-package make-sourcestamp-file
	@echo 'Compressing...'
	cd $(DIST) && $(MAKE_PACKAGE)

make-package: FORCE
	$(MAKE) make-package-internal
ifeq (WINNT,$(OS_ARCH))
ifeq ($(MOZ_PKG_FORMAT),ZIP)
	$(MAKE) -C windows ZIP_IN='$(ABS_DIST)/$(PACKAGE)' installer
endif
endif
ifdef MOZ_AUTOMATION
	cp $(DEPTH)/mozinfo.json $(MOZ_MOZINFO_FILE)
	$(PYTHON) $(MOZILLA_DIR)/toolkit/mozapps/installer/informulate.py \
		$(MOZ_BUILDINFO_FILE) $(MOZ_BUILDHUB_JSON) $(MOZ_BUILDID_INFO_TXT_FILE) \
		$(MOZ_PKG_PLATFORM) \
		--package=$(DIST)/$(PACKAGE) \
		--installer=$(INSTALLER_PACKAGE)
endif
	$(TOUCH) $@

GARBAGE += make-package

make-sourcestamp-file::
	$(NSINSTALL) -D $(DIST)/$(PKG_PATH)
	@echo '$(BUILDID)' > $(MOZ_SOURCESTAMP_FILE)
ifdef MOZ_INCLUDE_SOURCE_INFO
	@awk '$$2 == "MOZ_SOURCE_URL" {print $$3}' $(DEPTH)/source-repo.h >> $(MOZ_SOURCESTAMP_FILE)
endif

# The install target will install the application to prefix/lib/appname-version
# In addition if INSTALL_SDK is set, it will install the development headers,
# libraries, and IDL files as follows:
# dist/include -> prefix/include/appname-version
# dist/idl -> prefix/share/idl/appname-version
# dist/sdk/lib -> prefix/lib/appname-devel-version/lib
# prefix/lib/appname-devel-version/* symlinks to the above directories
install:: prepare-package
ifeq ($(OS_ARCH),WINNT)
	$(error "make install" is not supported on this platform. Use "make package" instead.)
endif
ifeq (bundle,$(MOZ_FS_LAYOUT))
	$(error "make install" is not supported on this platform. Use "make package" instead.)
endif
	$(NSINSTALL) -D $(DESTDIR)$(installdir)
	(cd $(DIST)/$(MOZ_PKG_DIR) && $(TAR) --exclude=precomplete $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DESTDIR)$(installdir) && tar -xf -)
	$(NSINSTALL) -D $(DESTDIR)$(bindir)
	$(RM) -f $(DESTDIR)$(bindir)/$(MOZ_APP_NAME)
	ln -s $(installdir)/$(MOZ_APP_NAME) $(DESTDIR)$(bindir)
ifdef INSTALL_SDK # Here comes the hard part
	$(NSINSTALL) -D $(DESTDIR)$(includedir)
	(cd $(DIST)/include && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DESTDIR)$(includedir) && tar -xf -)
	$(NSINSTALL) -D $(DESTDIR)$(idldir)
	(cd $(DIST)/idl && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DESTDIR)$(idldir) && tar -xf -)
# SDK directory is the libs + a bunch of symlinks
	$(NSINSTALL) -D $(DESTDIR)$(sdkdir)/sdk/lib
	$(NSINSTALL) -D $(DESTDIR)$(sdkdir)/sdk/bin
	if test -f $(DIST)/include/xpcom-config.h; then \
	  $(SYSINSTALL) $(IFLAGS1) $(DIST)/include/xpcom-config.h $(DESTDIR)$(sdkdir); \
	fi
	find $(DIST)/sdk -name '*.pyc' | xargs rm -f
	(cd $(DIST)/sdk/lib && $(TAR) $(TAR_CREATE_FLAGS) - .) | (cd $(DESTDIR)$(sdkdir)/sdk/lib && tar -xf -)
	(cd $(DIST)/sdk/bin && $(TAR) $(TAR_CREATE_FLAGS) - .) | (cd $(DESTDIR)$(sdkdir)/sdk/bin && tar -xf -)
	$(RM) -f $(DESTDIR)$(sdkdir)/lib $(DESTDIR)$(sdkdir)/bin $(DESTDIR)$(sdkdir)/include $(DESTDIR)$(sdkdir)/include $(DESTDIR)$(sdkdir)/sdk/idl $(DESTDIR)$(sdkdir)/idl
	ln -s $(sdkdir)/sdk/lib $(DESTDIR)$(sdkdir)/lib
	ln -s $(installdir) $(DESTDIR)$(sdkdir)/bin
	ln -s $(includedir) $(DESTDIR)$(sdkdir)/include
	ln -s $(idldir) $(DESTDIR)$(sdkdir)/idl
endif # INSTALL_SDK

make-sdk:
ifndef SDK_UNIFY
	$(MAKE) stage-package UNIVERSAL_BINARY= STAGE_SDK=1 MOZ_PKG_DIR=sdk-stage
endif
	@echo 'Packaging SDK...'
	$(RM) -rf $(DIST)/$(MOZ_APP_NAME)-sdk
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/bin
ifdef SDK_UNIFY
	(cd $(UNIFY_DIST)/sdk-stage && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/bin && tar -xf -)
else
	(cd $(DIST)/sdk-stage && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/bin && tar -xf -)
endif
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/host/bin
	(cd $(DIST)/host/bin && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/host/bin && tar -xf -)
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/sdk
	find $(DIST)/sdk -name '*.pyc' | xargs rm -f
	(cd $(DIST)/sdk && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/sdk && tar -xf -)
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/include
	(cd $(DIST)/include && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/include && tar -xf -)
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/idl
	(cd $(DIST)/idl && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/idl && tar -xf -)
	$(NSINSTALL) -D $(DIST)/$(MOZ_APP_NAME)-sdk/lib
# sdk/lib is the same as sdk/sdk/lib
	(cd $(DIST)/sdk/lib && $(TAR) $(TAR_CREATE_FLAGS) - .) | \
	  (cd $(DIST)/$(MOZ_APP_NAME)-sdk/lib && tar -xf -)
	$(NSINSTALL) -D $(DIST)/$(SDK_PATH)
ifndef PKG_SKIP_STRIP
	USE_ELF_HACK= $(PYTHON) $(MOZILLA_DIR)/toolkit/mozapps/installer/strip.py $(DIST)/$(MOZ_APP_NAME)-sdk
endif
	cd $(DIST) && $(MAKE_SDK)
ifdef UNIFY_DIST
ifndef SDK_UNIFY
	$(MAKE) -C $(UNIFY_DIST)/.. sdk SDK_UNIFY=1
endif
endif

checksum:
	mkdir -p `dirname $(CHECKSUM_FILE)`
	@$(PYTHON) $(MOZILLA_DIR)/build/checksums.py \
		-o $(CHECKSUM_FILE) \
		$(CHECKSUM_ALGORITHM_PARAM) \
		-s $(call QUOTED_WILDCARD,$(DIST)) \
		$(UPLOAD_FILES)
	@echo 'CHECKSUM FILE START'
	@cat $(CHECKSUM_FILE)
	@echo 'CHECKSUM FILE END'
	$(SIGN_CHECKSUM_CMD)


upload: checksum
	$(PYTHON) -u $(MOZILLA_DIR)/build/upload.py --base-path $(DIST) \
		$(UPLOAD_FILES) \
		$(CHECKSUM_FILES)

# source-package creates a source tarball from the files in MOZ_PKG_SRCDIR,
# which is either set to a clean checkout or defaults to $topsrcdir
source-package:
	@echo 'Generate the sourcestamp file'
	# Make sure to have repository information available and then generate the
	# sourcestamp file.
	$(MAKE) -C $(DEPTH) 'source-repo.h'
	$(MAKE) make-sourcestamp-file
	@echo 'Packaging source tarball...'
	# We want to include the sourcestamp file in the source tarball, so copy it
	# in the root source directory. This is useful to enable telemetry submissions
	# from builds made from the source package with the correct revision information.
	# Don't bother removing it as this is only used by automation.
	@cp $(MOZ_SOURCESTAMP_FILE) '$(MOZ_PKG_SRCDIR)/sourcestamp.txt'
	$(MKDIR) -p $(DIST)/$(PKG_SRCPACK_PATH)
	(cd $(MOZ_PKG_SRCDIR) && $(CREATE_SOURCE_TAR) - ./ ) | xz -9e > $(SOURCE_TAR)

hg-bundle:
	$(MKDIR) -p $(DIST)/$(PKG_SRCPACK_PATH)
	$(CREATE_HG_BUNDLE_CMD)

source-upload:
	$(MAKE) upload UPLOAD_FILES='$(SOURCE_UPLOAD_FILES)' CHECKSUM_FILE='$(SOURCE_CHECKSUM_FILE)'


ALL_LOCALES = $(if $(filter en-US,$(LOCALES)),$(LOCALES),$(LOCALES) en-US)

# Firefox uses @RESPATH@.
# Fennec uses @BINPATH@ and doesn't have the @RESPATH@ variable defined.
ifeq ($(MOZ_BUILD_APP),mobile/android)
BASE_PATH:=@BINPATH@
MULTILOCALE_DIR = $(DIST)/$(BINPATH)/res
else
BASE_PATH:=@RESPATH@
MULTILOCALE_DIR = $(DIST)/$(RESPATH)/res
endif

# This version of the target uses MOZ_CHROME_MULTILOCALE to build multilocale.txt
# and places it in dist/bin/res - it should be used when packaging a build.
multilocale.txt: LOCALES?=$(MOZ_CHROME_MULTILOCALE)
multilocale.txt:
	$(call py_action,file_generate,$(MOZILLA_DIR)/toolkit/locales/gen_multilocale.py main '$(MULTILOCALE_DIR)/multilocale.txt' $(MDDEPDIR)/multilocale.txt.pp $(ALL_LOCALES))

# This version of the target uses AB_CD to build multilocale.txt and places it
# in the $(XPI_NAME)/res dir - it should be used when repackaging a build.
multilocale.txt-%: LOCALES?=$(AB_CD)
multilocale.txt-%: MULTILOCALE_DIR=$(DIST)/xpi-stage/$(XPI_NAME)/res
multilocale.txt-%:
	$(call py_action,file_generate,$(MOZILLA_DIR)/toolkit/locales/gen_multilocale.py main '$(MULTILOCALE_DIR)/multilocale.txt' $(MDDEPDIR)/multilocale.txt.pp $(ALL_LOCALES))

locale-manifest.in: LOCALES?=$(MOZ_CHROME_MULTILOCALE)
locale-manifest.in: $(GLOBAL_DEPS) FORCE
	printf '\n[multilocale]\n' > $@
	printf '$(BASE_PATH)/res/multilocale.txt\n' >> $@
	for LOCALE in $(ALL_LOCALES) ;\
	do \
	  for ENTRY in $(MOZ_CHROME_LOCALE_ENTRIES) ;\
		do \
		  printf "$$ENTRY""$$LOCALE"'@JAREXT@\n' >> $@; \
		  printf "$$ENTRY""$$LOCALE"'.manifest\n' >> $@; \
	  done \
	done
