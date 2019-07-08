# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/build/mkrules/images.rules.mk $
#
# OpenPOWER HostBoot Project
#
# Contributors Listed Below - COPYRIGHT 2013,2019
# [+] International Business Machines Corp.
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# IBM_PROLOG_END_TAG

# File: images.rules.mk
# Description:
#     Rules for linking the Hostboot binary images using the custom linker.

# Folder to store *.objdump files in
OBJDUMP_FOLDER := $(IMGDIR)/objdump

# Clean up after ourselves
clean: clean-objdump

.PHONY: clean-objdump
clean-objdump:
	$(C2) "    MAKE       objdump CLEAN"
	$(C1)rm -rf $(OBJDUMP_FOLDER)

ifdef IMGS
_IMGS = $(addprefix $(IMGDIR)/, $(IMGS))
IMAGES += $(addsuffix .bin, $(_IMGS)) $(addsuffix .elf, $(_IMGS))

ifdef BUILD_FAST
OBJDUMP_MODULES := $(sort $(foreach img, $(IMGS), $($(img)_MODULES) $($(img)_EXTENDED_MODULES)))

OBJDUMP_BIN_TARGETS := $(addsuffix .elf.objdump, $(IMGS))
OBJDUMP_LIB_TARGETS := $(addsuffix .so.objdump, $(OBJDUMP_MODULES))

OBJDUMP_TARGETS := $(addprefix $(OBJDUMP_FOLDER)/lib, $(OBJDUMP_LIB_TARGETS))
OBJDUMP_TARGETS += $(addprefix $(OBJDUMP_FOLDER)/, $(OBJDUMP_BIN_TARGETS))

# Tell make not to delete our objdumps
.SECONDARY: $(OBJDUMP_TARGETS)
endif

IMAGE_PASS_POST += $(addsuffix .list.bz2, $(_IMGS)) $(addsuffix .syms, $(_IMGS))
CLEAN_TARGETS += $(addsuffix .list.bz2, $(_IMGS)) $(addsuffix .syms, $(_IMGS))
CLEAN_TARGETS += $(addsuffix .lnkout.bz2, $(addprefix $(IMGDIR)/., $(IMGS)))

$(OBJDUMP_FOLDER):
	mkdir -p $@

$(OBJDUMP_FOLDER)/%.so.objdump: $(IMGDIR)/%.so $(OBJDUMP_FOLDER)
	$(C2) "    OBJDUMP    $(notdir $*)"
	$(C1)$(OBJDUMP) -dCS -j .text -j .data -j .rodata $< | bzip2 >$@

$(OBJDUMP_FOLDER)/%.elf.objdump: $(IMGDIR)/%.elf $(OBJDUMP_FOLDER)
	$(C2) "    OBJDUMP    $(notdir $*)"
	$(C1)$(OBJDUMP) -dCS -j .text -j .data -j .rodata $< | bzip2 >$@

define ELF_template
$$(IMGDIR)/$(1).elf: $$(addprefix $$(OBJDIR)/, $$($(1)_OBJECTS)) \
                     $$(ROOTPATH)/src/$$($(1)_LDFILE)
	$$(C2) "    LD         $$(notdir $$@)"
	$$(C1)$$(LD) -static $$(LDFLAGS) $$($$*_LDFLAGS) \
                     $$(addprefix $$(OBJDIR)/, $$($(1)_OBJECTS)) \
                     $$($(1)_LDFLAGS) -T $$(ROOTPATH)/src/$$($(1)_LDFILE) \
                     -o $$@
endef
$(foreach img,$(IMGS),$(eval $(call ELF_template,$(img))))

# Wrap code in bash call
$(IMGDIR)/%.bin: $(IMGDIR)/%.elf \
    $(wildcard $(IMGDIR)/*.so) $(addprefix $(IMGDIR)/, $($*_DATA_MODULES)) \
    $(CUSTOM_LINKER_EXE)
	$(C2) "    LINKER     $(notdir $@)"
	$(C1)bash -c 'set -o pipefail && $(CUSTOM_LINKER) $@ $< \
        $(addprefix $(IMGDIR)/lib, $(addsuffix .so, $($*_MODULES))) \
	      $(if $($*_EXTENDED_MODULES), \
                  --extended=0x40000 $(IMGDIR)/$*_extended.bin \
                  $(addprefix $(IMGDIR)/lib, \
	              $(addsuffix .so, $($*_EXTENDED_MODULES))) \
	      ) \
          $(if $($*_NO_RELOCATION), --no-relocation) \
        $(addprefix $(IMGDIR)/, $($*_DATA_MODULES)) \
        | bzip2 -zc > $(IMGDIR)/.$*.lnkout.bz2'
	$(C1)$(ROOTPATH)/src/build/tools/addimgid $@ $<

$(IMGDIR)/%.list.bz2 $(IMGDIR)/%.syms: $(IMGDIR)/%.bin $(OBJDUMP_TARGETS)
	$(C2) "    GENLIST    $(notdir $*)"
	$(C1)(cd $(ROOTPATH)&& \
              src/build/linker/gensyms $*.bin \
		  $(if $($*_EXTENDED_MODULES), $*_extended.bin 0x40000000) \
                  > ./img/$*.syms && \
              src/build/linker/genlist $*.bin | bzip2 -zc > ./img/$*.list.bz2)

endif
