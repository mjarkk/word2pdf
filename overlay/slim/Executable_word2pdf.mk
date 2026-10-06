# -*- Mode: makefile-gmake; tab-width: 4; indent-tabs-mode: t -*-
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

$(eval $(call gb_Executable_Executable,word2pdf))

$(eval $(call gb_Executable_use_api,word2pdf,\
	offapi \
	udkapi \
))

$(eval $(call gb_Executable_use_custom_headers,word2pdf,\
	officecfg/registry \
))

# In a static build linking cppuhelper pulls in every UNO component of the build
# (see static/Library_components.mk and solenv/gbuild/static.mk).
# dbtools and msword have no listed component, but other libraries call into them directly
# (svx form code, Writer's .doc/.rtf import).
$(eval $(call gb_Executable_use_libraries,word2pdf,\
	comphelper \
	cppu \
	cppuhelper \
	dbtools \
	i18nlangtag \
	msword \
	sal \
	sfx \
	utl \
	vcl \
))

$(eval $(call gb_Executable_use_externals,word2pdf,\
	libxml2 \
))

ifneq ($(filter FONTCONFIG,$(BUILD_TYPE)),)
$(eval $(call gb_Executable_use_externals,word2pdf,\
	fontconfig \
))
endif

# Only depend on the C library at runtime. Packed relative relocations (glibc >= 2.36) keep
# the position independent executable small, and mold folds identical functions (-6%) and
# links in seconds.
ifeq ($(OS)-$(COM),LINUX-GCC)
$(eval $(call gb_Executable_add_ldflags,word2pdf,\
	-static-libstdc++ \
	-static-libgcc \
	-Wl$(COMMA)-z$(COMMA)pack-relative-relocs \
	-fuse-ld=mold \
	-Wl$(COMMA)--icf=all \
))
endif

$(eval $(call gb_Executable_add_exception_objects,word2pdf,\
	slim/source/word2pdf \
))

ifeq ($(OS),WNT)
# the cursors and icons of VCL's Windows backend, which its static library cannot carry
$(eval $(call gb_Executable_add_nativeres,word2pdf,vcl/salsrc))
endif

$(eval $(call gb_Executable_add_generated_exception_objects,word2pdf,\
	CustomTarget/slim/assets/assets \
))

# vim: set noet sw=4 ts=4:
