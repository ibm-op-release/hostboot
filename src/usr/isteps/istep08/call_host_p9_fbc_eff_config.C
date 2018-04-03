/* IBM_PROLOG_BEGIN_TAG                                                   */
/* This is an automatically generated prolog.                             */
/*                                                                        */
/* $Source: src/usr/isteps/istep08/call_host_p9_fbc_eff_config.C $        */
/*                                                                        */
/* OpenPOWER HostBoot Project                                             */
/*                                                                        */
/* Contributors Listed Below - COPYRIGHT 2016,2018                        */
/* [+] International Business Machines Corp.                              */
/*                                                                        */
/*                                                                        */
/* Licensed under the Apache License, Version 2.0 (the "License");        */
/* you may not use this file except in compliance with the License.       */
/* You may obtain a copy of the License at                                */
/*                                                                        */
/*     http://www.apache.org/licenses/LICENSE-2.0                         */
/*                                                                        */
/* Unless required by applicable law or agreed to in writing, software    */
/* distributed under the License is distributed on an "AS IS" BASIS,      */
/* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or        */
/* implied. See the License for the specific language governing           */
/* permissions and limitations under the License.                         */
/*                                                                        */
/* IBM_PROLOG_END_TAG                                                     */
#include <stdint.h>
#include <trace/interface.H>
#include <errl/errlentry.H>
#include <errl/errlmanager.H>
#include <initservice/taskargs.H>
#include <initservice/isteps_trace.H>
#include <initservice/initserviceif.H>
#include <isteps/hwpisteperror.H>
#include <targeting/common/targetservice.H>
#include <targeting/common/target.H>
#include <fapi2/plat_hwp_invoker.H>
#include <p9_fbc_eff_config.H>

using namespace TARGETING;

namespace ISTEP_08
{

void* call_host_p9_fbc_eff_config( void *io_pArgs )
{
    errlHndl_t l_errl = nullptr;
    ISTEP_ERROR::IStepError l_stepError;

    TRACFCOMP( ISTEPS_TRACE::g_trac_isteps_trace,
               "call_host_p9_fbc_eff_config entry" );

    // Check to see if this procedure was moved to istep 8.1

    // Get Target Service, and the system target.
    TargetService& tS = targetService();
    Target* sys = nullptr;
    (void) tS.getTopLevelTarget( sys );
    assert(sys, "call_host_p9_fbc_eff_config() system target is nullptr");

    // For OpenPower systems there is a chance that the p9_fbc_eff_config HWP
    // was run in an earlier istep (istep 8.1).  If that is the case, then skip
    // it here.
    bool l_do_p9_fbc_eff_config = true;
    if ( !INITSERVICE::spBaseServicesEnabled())
    {
        if ( sys->getAttr<ATTR_PERFORMED_P9_FBC_EFF_CONFIG_EARLY>() )
        {
            l_do_p9_fbc_eff_config = false;
            TRACFCOMP( ISTEPS_TRACE::g_trac_isteps_trace,
                       INFO_MRK"Skipping p9_fbc_eff_config since it was "
                       "called earlier in istep 8.1");
        }
    }

    if (l_do_p9_fbc_eff_config == true)
    {
        FAPI_INVOKE_HWP(l_errl,p9_fbc_eff_config);
        if(l_errl)
        {
            l_stepError.addErrorDetails(l_errl);
            TRACFCOMP( ISTEPS_TRACE::g_trac_isteps_trace,
                       "ERROR : call p9_fbc_eff_config, PLID=0x%x",
                       l_errl->plid() );
            errlCommit(l_errl, HWPF_COMP_ID);
        }
    }

    TRACFCOMP( ISTEPS_TRACE::g_trac_isteps_trace,
               "call_host_p9_fbc_eff_config exit" );

    return l_stepError.getErrorHandle();
}

};
