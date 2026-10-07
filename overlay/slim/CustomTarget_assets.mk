# -*- Mode: makefile-gmake; tab-width: 4; indent-tabs-mode: t -*-
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

# The installation files word2pdf needs at runtime, compiled into the executable as a
# read-only file tree (see include/osl/detail/embeddedfs.h).

$(eval $(call gb_CustomTarget_CustomTarget,slim/assets))

slim_assets_DIR := $(gb_CustomTarget_workdir)/slim/assets

# DEST=SOURCE pairs, see embed_files.py. The ini files LibreOffice finds by name have the
# platform's names (bootstrap.ini on Windows); the others are named by the ini files. Which
# share/ files are needed was found by tracing the files conversions open
# (LO_SLIM_TRACE_FILES); missing optional files are tolerated. Not palette/standard.sob, 1 MB of
# fill bitmaps Writer opens only to offer them in its dialogs.
slim_assets_FILES := \
	$(LIBO_ETC_FOLDER)/$(call gb_Helper_get_rcfile,bootstrap)=$(SRCDIR)/slim/assets/program/bootstraprc \
	$(LIBO_ETC_FOLDER)/fundamentalrc=$(slim_assets_DIR)/fundamentalrc \
	$(LIBO_ETC_FOLDER)/sofficerc=$(SRCDIR)/slim/assets/program/sofficerc \
	$(LIBO_ETC_FOLDER)/unorc=$(SRCDIR)/slim/assets/program/unorc \
	$(LIBO_ETC_FOLDER)/$(call gb_Helper_get_rcfile,version)=$(INSTROOT)/$(LIBO_ETC_FOLDER)/$(call gb_Helper_get_rcfile,version) \
	$(LIBO_ETC_FOLDER)/types.rdb=$(call gb_UnoApi_get_target,udkapi) \
	$(LIBO_ETC_FOLDER)/types/offapi.rdb=$(call gb_UnoApi_get_target,offapi) \
	$(LIBO_ETC_FOLDER)/services.rdb=$(slim_assets_DIR)/ure-services.rdb \
	$(LIBO_ETC_FOLDER)/services/services.rdb=$(slim_assets_DIR)/services.rdb \
	$(LIBO_SHARE_FOLDER)/config/soffice.cfg/svt/ui/scrollbars.ui=$(SRCDIR)/svtools/uiconfig/ui/scrollbars.ui \
	$(LIBO_SHARE_FOLDER)/filter/oox-drawingml-cs-presets=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/filter/oox-drawingml-cs-presets \
	$(foreach ext,soc sod soe sog soh,$(LIBO_SHARE_FOLDER)/palette/standard.$(ext)=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/palette/standard.$(ext)) \
	$(LIBO_SHARE_FOLDER)/registry=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/registry \
	$(LIBO_SHARE_FOLDER)/registry/word2pdf.xcd=$(SRCDIR)/slim/assets/share/registry/word2pdf.xcd \
	$(LIBO_SHARE_FOLDER)/liblangtag=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/liblangtag \
	$(LIBO_SHARE_FOLDER)/themes=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/themes \
	$(if $(SLIM_DISCOVER),$(foreach d,$(filter-out registry liblangtag config themes,$(notdir $(wildcard $(INSTROOT)/$(LIBO_SHARE_FOLDER)/*))),$(LIBO_SHARE_FOLDER)/$(d)=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/$(d)) $(LIBO_SHARE_FOLDER)/config/soffice.cfg=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/config/soffice.cfg $(LIBO_SHARE_FOLDER)/config/images_colibre.zip=$(INSTROOT)/$(LIBO_SHARE_FOLDER)/config/images_colibre.zip) \

# Directories are embedded recursively; make can only depend on what installs them.
slim_assets_DIRS := $(foreach d,registry liblangtag themes,$(INSTROOT)/$(LIBO_SHARE_FOLDER)/$(d))

# The installation's folder names differ per platform (share/ is Resources/ on macOS).
$(slim_assets_DIR)/fundamentalrc : \
		$(SRCDIR)/slim/assets/program/fundamentalrc.in \
		$(BUILDDIR)/config_host.mk \
		| $(slim_assets_DIR)/.dir
	$(call gb_Output_announce,$(subst $(WORKDIR)/,,$@),$(true),SED,1)
	sed -e 's|@LIBO_SHARE_FOLDER@|$(LIBO_SHARE_FOLDER)|g' \
		-e 's|@LIBO_SHARE_RESOURCE_FOLDER@|$(LIBO_SHARE_RESOURCE_FOLDER)|g' \
		-e 's|@LIBO_LIB_FOLDER@|$(LIBO_LIB_FOLDER)|g' \
		-e 's|@LIBO_URE_BIN_FOLDER@|$(LIBO_URE_BIN_FOLDER)|g' \
		$< > $@

# Only the services whose implementations are linked (slim/constructors.list).
define slim_assets_filter_services
$(slim_assets_DIR)/$(1) : \
		$(2) \
		$(SRCDIR)/slim/filter_services.py \
		$(SRCDIR)/slim/constructors.list \
		$(call gb_ExternalExecutable_get_dependencies,python) \
		| $(slim_assets_DIR)/.dir
	$$(call gb_Output_announce,$$(subst $$(WORKDIR)/,,$$@),$$(true),PY ,1)
	$$(call gb_ExternalExecutable_get_command,python) $(SRCDIR)/slim/filter_services.py $(2) $(SRCDIR)/slim/constructors.list $$@

endef

$(eval $(call slim_assets_filter_services,services.rdb,$(call gb_Rdb_get_target,services)))
$(eval $(call slim_assets_filter_services,ure-services.rdb,$(call gb_Rdb_get_target,ure/services)))

# With fontconfig (Linux, headless macOS) its configuration is baked in too, so /etc/fonts is
# never read.
ifneq ($(filter FONTCONFIG,$(BUILD_TYPE)),)
slim_assets_FILES += $(LIBO_SHARE_FOLDER)/fontconfig/fonts.conf=$(slim_assets_DIR)/fonts.conf

$(slim_assets_DIR)/fonts.conf : \
		$(SRCDIR)/slim/make_fonts_conf.py \
		$(SRCDIR)/extras/source/truetype/symbol/fc_local.snippet \
		$(SRCDIR)/postprocess/fontconfig/fc_local.snippet \
		$(call gb_ExternalProject_get_target,fontconfig) \
		$(call gb_ExternalExecutable_get_dependencies,python) \
		| $(slim_assets_DIR)/.dir
	$(call gb_Output_announce,$(subst $(WORKDIR)/,,$@),$(true),PY ,1)
	$(call gb_ExternalExecutable_get_command,python) $(SRCDIR)/slim/make_fonts_conf.py --os=$(OS) $@ \
		$(gb_UnpackedTarball_workdir)/fontconfig \
		$(SRCDIR)/extras/source/truetype/symbol/fc_local.snippet \
		$(SRCDIR)/postprocess/fontconfig/fc_local.snippet

# The metric-compatible replacements for Calibri, Cambria, Arial, Times New Roman and Courier
# New that LibreOffice bundles, so documents keep their layout without them installed; word2pdf
# hands everything below fonts/truetype/ to fontconfig from memory. Not Liberation Sans Narrow:
# it is GPL-licensed.
slim_assets_FONTS := $(foreach style,Regular Bold Italic BoldItalic,\
	font_caladea/Caladea-$(style).ttf \
	font_carlito/Carlito-$(style).ttf \
	$(foreach family,Mono Sans Serif,font_liberation/Liberation$(family)-$(style).ttf))

slim_assets_FILES += $(foreach font,$(slim_assets_FONTS),\
	$(LIBO_SHARE_FOLDER)/fonts/truetype/$(notdir $(font))=$(gb_UnpackedTarball_workdir)/$(font))

# LibreOffice's own font, for symbol fonts that are not installed (Word's bullets are in Symbol),
# and formulas. Prebuilt: configure has --disable-build-opensymbol.
slim_assets_FILES += $(LIBO_SHARE_FOLDER)/fonts/truetype/opens___.ttf=$(TARFILE_LOCATION)/$(OPENSYMBOL_TTF)

$(foreach font,$(slim_assets_FONTS),\
	$(eval $(call gb_UnpackedTarball_mark_output_file,$(patsubst %/,%,$(dir $(font))),$(notdir $(font)))))
endif

$(call gb_CustomTarget_get_target,slim/assets) : $(slim_assets_DIR)/assets.cxx

$(slim_assets_DIR)/assets.cxx : \
		$(SRCDIR)/slim/embed_files.py \
		$(SRCDIR)/slim/CustomTarget_assets.mk \
		$(filter-out $(slim_assets_DIRS),$(foreach pair,$(slim_assets_FILES),$(lastword $(subst =, ,$(pair))))) \
		$(call gb_Package_get_target,postprocess_registry) \
		$(call gb_ExternalPackage_get_target,liblangtag_data) \
		$(call gb_Package_get_target,svx_document_themes) \
		$(call gb_ExternalExecutable_get_dependencies,python) \
		| $(slim_assets_DIR)/.dir
	$(call gb_Output_announce,$(subst $(WORKDIR)/,,$@),$(true),PY ,1)
	$(call gb_Trace_StartRange,$(subst $(WORKDIR)/,,$@),PY)
	$(call gb_ExternalExecutable_get_command,python) $(SRCDIR)/slim/embed_files.py $@ slim_assets $(slim_assets_FILES)
	$(call gb_Trace_EndRange,$(subst $(WORKDIR)/,,$@),PY)

# vim: set noet sw=4 ts=4:
