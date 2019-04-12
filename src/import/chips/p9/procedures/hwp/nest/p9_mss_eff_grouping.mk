# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/import/chips/p9/procedures/hwp/nest/p9_mss_eff_grouping.mk $
#
# OpenPOWER HostBoot Project
#
# Contributors Listed Below - COPYRIGHT 2015,2019
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

# Include the macros and things for MSS procedures
PROCEDURE=p9_mss_eff_grouping
$(call ADD_MODULE_INCDIR,$(PROCEDURE),$(ROOTPATH)/chips/p9/procedures/hwp/memory/)
lib$(PROCEDURE)_DEPLIBS+=cen
OBJS+=p9_fbc_utils.o
$(call ADD_MODULE_INCDIR,$(PROCEDURE),$(ROOTPATH))
$(call BUILD_PROCEDURE)

