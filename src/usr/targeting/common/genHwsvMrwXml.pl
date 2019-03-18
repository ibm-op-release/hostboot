#!/usr/bin/perl
# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/usr/targeting/common/genHwsvMrwXml.pl $
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
#
# Usage:
#
# genHwsvMrwXml.pl --system=systemname --mrwdir=pathname
#                  [--build=hb] [--outfile=XmlFilename]
#        --system=systemname
#              Specify which system MRW XML to be generated
#        --systemnodes=systemnodesinbrazos
#              Specify number of nodes for brazos system, by default it is 4
#        --mrwdir=pathname
#              Specify the complete dir pathname of the MRW. Colon-delimited
#              list accepted to specify multiple directories to search.
#        --build=hb
#              Specify HostBoot build (hb)
#        --outfile=XmlFilename
#              Specify the filename for the output XML. If omitted, the output
#              is written to STDOUT which can be saved by redirection.
#
# Purpose:
#
#   This perl script processes the various xml files of the MRW to
#   extract the needed information for generating the final xml file.
#
use strict;
use XML::Simple;
use Data::Dumper;

# Enables the state variable feature
use feature "state";

################################################################################
# Set PREFERRED_PARSER to XML::Parser. Otherwise it uses XML::SAX which contains
# bugs that result in XML parse errors that can be fixed by adjusting white-
# space (i.e. parse errors that do not make sense).
################################################################################
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

#------------------------------------------------------------------------------
# Constants
#------------------------------------------------------------------------------
use constant CHIP_NODE_INDEX => 0; # Position in array of chip's node
use constant CHIP_POS_INDEX => 1; # Position in array of chip's position
use constant CHIP_ATTR_START_INDEX => 2; # Position in array of start of attrs

use constant
{
    MAX_PROC_PER_NODE => 8,
    MAX_CORE_PER_PROC => 24,
    MAX_EX_PER_PROC => 12,
    MAX_EQ_PER_PROC => 6,
    MAX_ABUS_PER_PROC => 3,
    MAX_XBUS_PER_PROC => 3,
    MAX_MCS_PER_PROC => 4,
    MAX_MCA_PER_PROC => 8,
    MAX_MCBIST_PER_PROC => 2,
    MAX_PEC_PER_PROC => 3,    # PEC is same as PBCQ
    MAX_PHB_PER_PROC => 6,    # PHB is same as PCIE
    MAX_MBA_PER_MEMBUF => 2,
    MAX_OBUS_PER_PROC => 4,
    MAX_OBUS_BRICK_PER_PROC => 12,
    MAX_NPU_PER_PROC => 1,
    MAX_PPE_PER_PROC => 51,   #Only 21, but they are sparsely populated
    MAX_PERV_PER_PROC => 56,  #Only 42, but they are sparsely populated
    MAX_CAPP_PER_PROC => 2,
    MAX_SBE_PER_PROC => 1,
    MAX_MI_PER_PROC => 4,
};

# Architecture limits, for the purpose of calculating FAPI_POS.
# This sometimes differs subtley from the max constants above
# due to trying to account for worst case across all present and
# future designs for a processor generation, as well as to account for
# holes in the mapping.  It is also more geared towards parent/child
# maxes. Some constants pass through to the above.
use constant
{
    ARCH_LIMIT_DIMM_PER_MCA => 2,
    ARCH_LIMIT_DIMM_PER_MBA => 4,
    # Note: this is proc per fabric group, vs. physical node
    ARCH_LIMIT_PROC_PER_FABRIC_GROUP => 4,
    ARCH_LIMIT_MEMBUF_PER_DMI => 1,
    ARCH_LIMIT_EX_PER_EQ => MAX_EX_PER_PROC / MAX_EQ_PER_PROC,
    ARCH_LIMIT_MBA_PER_MEMBUF => MAX_MBA_PER_MEMBUF,
    ARCH_LIMIT_MCS_PER_MCBIST => MAX_MCS_PER_PROC / MAX_MCBIST_PER_PROC,
    ARCH_LIMIT_XBUS_PER_PROC => MAX_XBUS_PER_PROC,
    ARCH_LIMIT_ABUS_PER_PROC => MAX_ABUS_PER_PROC,
    ARCH_LIMIT_L4_PER_MEMBUF => 1,
    ARCH_LIMIT_CORE_PER_EX => MAX_CORE_PER_PROC / MAX_EX_PER_PROC,
    ARCH_LIMIT_EQ_PER_PROC => MAX_EQ_PER_PROC,
    ARCH_LIMIT_MCA_PER_MCS => MAX_MCA_PER_PROC / MAX_MCS_PER_PROC,
    ARCH_LIMIT_MCBIST_PER_PROC => MAX_MCBIST_PER_PROC,
    ARCH_LIMIT_MI_PER_PROC => MAX_MI_PER_PROC,
    ARCH_LIMIT_CAPP_PER_PROC => MAX_CAPP_PER_PROC,
    ARCH_LIMIT_DMI_PER_MI => 2,
    ARCH_LIMIT_NPU_PER_PROC => MAX_NPU_PER_PROC,
    ARCH_LIMIT_OBUS_PER_PROC => MAX_OBUS_PER_PROC,
    ARCH_LIMIT_OBUS_BRICK_PER_OBUS => MAX_OBUS_BRICK_PER_PROC / MAX_OBUS_PER_PROC,
    ARCH_LIMIT_SBE_PER_PROC => MAX_SBE_PER_PROC,
    # There are 20+ PPE, but lots of holes in the mapping.   Further the
    # architecture supports potentially many more PPEs.  So, for now we'll pick
    # power of 2 value larger than largest pervasive unit of 50
    ARCH_LIMIT_PPE_PER_PROC => 64,
    # Pervasives are numbered 1..55.  0 Is not possible but acts as a hole.
    # Some pervasives within the range are holes as well
    ARCH_LIMIT_PERV_PER_PROC => 56,
    ARCH_LIMIT_PEC_PER_PROC => MAX_PEC_PER_PROC,
    # There are only 6 PHBs per chip, but they are unbalanced across the 3
    # PECs.  To make the math easy, we'll assume there are potentially 3 PHBs
    # per PEC, but PEC0 and PEC1 will have 2 and 1 holes respectively
    ARCH_LIMIT_PHB_PER_PEC => 3,
};

# for SPI connections in the @SPIs array
use constant SPI_PROC_PATH_FIELD => 0;
use constant SPI_NODE_FIELD => 1;
use constant SPI_POS_FIELD  => 2;
use constant SPI_ENDPOINT_PATH_FIELD => 3;
use constant SPI_APSS_POS_FIELD => 4;
use constant SPI_APSS_ORD_FIELD => 5;
use constant SPI_APSS_RID_FIELD => 6;

use constant
{
    # Domain is programmed as part of regular power on sequence.
    # No need to do anything in host_enable_memvolt
    POWERON_PROGRAM => 0,

    # Domain needs to be programmed during host_enable_memvolt, but
    # there is no special computation involved
    STATIC_PROGRAM => 1,

    # Domain needs to be programmed during host_enable_memvolt, and the
    # new dynamic vid values must be computed beyond what p9_mss_volt() did
    DYNAMIC_PROGRAM => 2,

    # Domain needs to be programmed during host_enable_memvolt, and the
    # new vid values will come from VRM xml system file consumed by POWR code
    DEFAULT_PROGRAM => 3,
};

our $mrwdir = "";
my $sysname = "";
my $sysnodes = "";
my $usage = 0;
my $DEBUG = 0;
my $outFile = "";
my $build = "fsp";

# used to map voltage domains to mcbist target
my %mcbist_dimms;  # $node$proc_$mcbist -> @(n0p1, n0p2, ...)

use Getopt::Long;
GetOptions( "mrwdir:s"  => \$mrwdir,
            "system:s"  => \$sysname,
            "systemnodes:s"  => \$sysnodes,
            "outfile:s" => \$outFile,
            "build:s"   => \$build,
            "DEBUG"     => \$DEBUG,
            "help"      => \$usage, );

if ($usage || ($mrwdir eq ""))
{
    display_help();
    exit 0;
}

our %hwsvmrw_plugins;
# FSP-specific functions
if ($build eq "fsp")
{
    eval("use genHwsvMrwXml_fsp; return 1;");
    genHwsvMrwXml_fsp::return_plugins();
}

if ($outFile ne "")
{
    # Uncomment to emit debug trace to STDERR
    # print STDERR "Opening OUTFILE $outFile\n";
    open OUTFILE, '+>', $outFile ||
                die "ERROR: unable to create $outFile\n";
    select OUTFILE;
}

my $SYSNAME = uc($sysname);
my $CHIPNAME = "";
my $MAXNODE = 0;
if ($sysname =~ /brazos/)
{
    $MAXNODE = 4;
}

my $NODECONF = "";
if( ($sysnodes) && ($sysnodes =~ /2/) )
{
    $NODECONF = "2-node";
}
else
{
    $NODECONF = "3-and-4-node";
}

my $mru_ids_file = open_mrw_file($mrwdir, "${sysname}-mru-ids.xml");
my $mruAttr = parse_xml_file($mru_ids_file);
#------------------------------------------------------------------------------
# Process the system-policy MRW file
#------------------------------------------------------------------------------
my $system_policy_file = open_mrw_file($mrwdir, "${sysname}-system-policy.xml");
my $sysPolicy = parse_xml_file($system_policy_file,
        forcearray=>['proc_r_loadline_vdd','proc_r_distloss_vdd',
        'proc_vrm_voffset_vdd','proc_r_loadline_vcs',
        'proc_r_distloss_vcs','proc_vrm_voffset_vcs',
        'proc_r_loadline_vdn','proc_r_distloss_vdn',
        'proc_vrm_voffset_vdn']);

my $reqPol = $sysPolicy->{"required-policy-settings"};

my @systemAttr; # Repeated {ATTR, VAL, ATTR, VAL, ATTR, VAL...}
my @nodeAttr; # Repeated {ATTR, VAL, ATTR, VAL, ATTR, VAL...}

#No mirroring supported yet so the policy is just based on multi-node or not
my $placement = 0x0; #NORMAL
if ($sysname =~ /brazos/)
{
    $placement = 0x3; #DRAWER
}

push @systemAttr,
[
    "FREQ_PROC_REFCLOCK", $reqPol->{'processor-refclock-frequency'}->{content},
    "FREQ_PROC_REFCLOCK_KHZ",
        $reqPol->{'processor-refclock-frequency-khz'}->{content},
    "FREQ_MEM_REFCLOCK", $reqPol->{'memory-refclock-frequency'}->{content},
    "BOOT_FREQ_MHZ", $reqPol->{'boot-frequency'}->{content},
    "FREQ_A_MHZ", $reqPol->{'proc_a_frequency'}->{content},
    "FREQ_PB_MHZ", $reqPol->{'proc_pb_frequency'}->{content},
    "ASYNC_NEST_FREQ_MHZ", $reqPol->{'async_nest_freq_mhz'},
    "FREQ_PCIE_MHZ", $reqPol->{'proc_pcie_frequency'}->{content},
    "FREQ_X_MHZ", $reqPol->{'proc_x_frequency'}->{content},
    "PROC_EPS_TABLE_TYPE", $reqPol->{'proc_eps_table_type'},
    "PROC_FABRIC_PUMP_MODE", $reqPol->{'proc_fabric_pump_mode'},
    "PROC_FABRIC_X_BUS_WIDTH", $reqPol->{'proc_fabric_x_bus_width'},
    "PROC_FABRIC_A_BUS_WIDTH", $reqPol->{'proc_fabric_a_bus_width'},
    "PROC_FABRIC_SMP_OPTICS_MODE", $reqPol->{'proc_fabric_smp_optics_mode'},
    "PROC_FABRIC_CAPI_MODE", $reqPol->{'proc_fabric_capi_mode'},
    "X_EREPAIR_THRESHOLD_FIELD", $reqPol->{'x-erepair-threshold-field'},
    "O_EREPAIR_THRESHOLD_FIELD", $reqPol->{'a-erepair-threshold-field'},
    "DMI_EREPAIR_THRESHOLD_FIELD", $reqPol->{'dmi-erepair-threshold-field'},
    "X_EREPAIR_THRESHOLD_MNFG", $reqPol->{'x-erepair-threshold-mnfg'},
    "O_EREPAIR_THRESHOLD_MNFG", $reqPol->{'a-erepair-threshold-mnfg'},
    "DMI_EREPAIR_THRESHOLD_MNFG", $reqPol->{'dmi-erepair-threshold-mnfg'},
    "MSS_MBA_ADDR_INTERLEAVE_BIT", $reqPol->{'mss_mba_addr_interleave_bit'},
    "EXTERNAL_VRM_STEPSIZE", $reqPol->{'pm_external_vrm_stepsize'},
    "PM_SAFE_FREQUENCY_MHZ", $reqPol->{'pm_safe_frequency'}->{content},
    "SPIPSS_FREQUENCY", $reqPol->{'pm_spipss_frequency'}->{content},
    "MEM_MIRROR_PLACEMENT_POLICY", $placement,
    "MSS_MRW_DIMM_POWER_CURVE_PERCENT_UPLIFT",
        $reqPol->{'mss_mrw_dimm_power_curve_percent_uplift'},
    "MSS_MRW_DIMM_POWER_CURVE_PERCENT_UPLIFT_IDLE",
        $reqPol->{'mss_mrw_dimm_power_curve_percent_uplift_idle'},
    "MRW_MEM_THROTTLE_DENOMINATOR",
        $reqPol->{'mss_mrw_mem_m_dram_clocks'},
    "MSS_MRW_MAX_DRAM_DATABUS_UTIL",
        $reqPol->{'mss_mrw_max_dram_databus_util'},
    "MSS_MRW_MAX_NUMBER_DIMMS_POSSIBLE_PER_VMEM_REGULATOR",
        $reqPol->{'mss_mrw_max_number_dimms_possible_per_vmem_regulator'},
    "MSS_MRW_THERMAL_MEMORY_POWER_LIMIT",
        $reqPol->{'mss_mrw_thermal_memory_power_limit'},
    "MNFG_DMI_MIN_EYE_WIDTH", $reqPol->{'mnfg-dmi-min-eye-width'},
    "MNFG_DMI_MIN_EYE_HEIGHT", $reqPol->{'mnfg-dmi-min-eye-height'},
    "MNFG_ABUS_MIN_EYE_WIDTH", $reqPol->{'mnfg-abus-min-eye-width'},
    "MNFG_ABUS_MIN_EYE_HEIGHT", $reqPol->{'mnfg-abus-min-eye-height'},
    "MNFG_XBUS_MIN_EYE_WIDTH", $reqPol->{'mnfg-xbus-min-eye-width'},
    "REDUNDANT_CLOCKS", $reqPol->{'redundant-clocks'},
    "MSS_MRW_POWER_CONTROL_REQUESTED", (uc $reqPol->{'mss_mrw_mem_power_control_requested'}),
    "MSS_MRW_IDLE_POWER_CONTROL_REQUESTED", $reqPol->{'mss_mrw_idle_power_control_requested'},
    "MNFG_TH_P8EX_L2_CACHE_CES", $reqPol->{'mnfg_th_p8ex_l2_cache_ces'},
    "MNFG_TH_P8EX_L2_DIR_CES", $reqPol->{'mnfg_th_p8ex_l2_dir_ces'},
    "MNFG_TH_P8EX_L3_CACHE_CES", $reqPol->{'mnfg_th_p8ex_l3_cache_ces'},
    "MNFG_TH_P8EX_L3_DIR_CES", $reqPol->{'mnfg_th_p8ex_l3_dir_ces'},
    "FIELD_TH_P8EX_L2_LINE_DELETES", $reqPol->{'field_th_p8ex_l2_line_deletes'},
    "FIELD_TH_P8EX_L3_LINE_DELETES", $reqPol->{'field_th_p8ex_l3_line_deletes'},
    "FIELD_TH_P8EX_L2_COL_REPAIRS", $reqPol->{'field_th_p8ex_l2_col_repairs'},
    "FIELD_TH_P8EX_L3_COL_REPAIRS", $reqPol->{'field_th_p8ex_l3_col_repairs'},
    "MNFG_TH_P8EX_L2_LINE_DELETES", $reqPol->{'mnfg_th_p8ex_l2_line_deletes'},
    "MNFG_TH_P8EX_L3_LINE_DELETES", $reqPol->{'mnfg_th_p8ex_l3_line_deletes'},
    "MNFG_TH_P8EX_L2_COL_REPAIRS", $reqPol->{'mnfg_th_p8ex_l2_col_repairs'},
    "MNFG_TH_P8EX_L3_COL_REPAIRS", $reqPol->{'mnfg_th_p8ex_l3_col_repairs'},
    "MNFG_TH_CEN_MBA_RT_SOFT_CE_TH_ALGO",
                                $reqPol->{'mnfg_th_cen_mba_rt_soft_ce_th_algo'},
    "MNFG_TH_CEN_MBA_IPL_SOFT_CE_TH_ALGO",
                               $reqPol->{'mnfg_th_cen_mba_ipl_soft_ce_th_algo'},
    "MNFG_TH_CEN_MBA_RT_RCE_PER_RANK",
                                   $reqPol->{'mnfg_th_cen_mba_rt_rce_per_rank'},
    "MNFG_TH_CEN_L4_CACHE_CES", $reqPol->{'mnfg_th_cen_l4_cache_ces'},
    "BRAZOS_RX_FIFO_OVERRIDE", $reqPol->{'rx_fifo_final_l2u_dly_override'},
    "MAX_ALLOWED_DIMM_FREQ",  $reqPol->{'max_allowed_dimm_freq'},
    "MRW_VMEM_REGULATOR_MEMORY_POWER_LIMIT_PER_DIMM_DDR3", $reqPol->{'vmem_regulator_memory_power_limit_per_dimm'},
    "MRW_VMEM_REGULATOR_MEMORY_POWER_LIMIT_PER_DIMM_DDR4", $reqPol->{'mss_mrw_vmem_regulator_memory_power_limit_per_dimm_ddr4'},
    "MSS_MRW_VMEM_REGULATOR_POWER_LIMIT_PER_DIMM_ADJ_ENABLE", $reqPol->{'vmem_regulator_memory_power_limit_per_dimm_adjustment_enable'},
    "MSS_MRW_PREFETCH_ENABLE", $reqPol->{'mss_prefetch_enable'},
    "MSS_MRW_CLEANER_ENABLE", $reqPol->{'mss_cleaner_enable'},
    #TODO RTC:161768 these need to come from MRW
    "MSS_MRW_MEM_M_DRAM_CLOCKS", $reqPol->{'mss_mrw_mem_m_dram_clocks'},
    "MSS_MRW_PERIODIC_MEMCAL_MODE_OPTIONS", $reqPol->{'mss_mrw_periodic_memcal_mode_options'},
    "MSS_MRW_PERIODIC_ZQCAL_MODE_OPTIONS", $reqPol->{'mss_mrw_periodic_zqcal_mode_options'},
    "MSS_MRW_SAFEMODE_MEM_THROTTLED_N_COMMANDS_PER_PORT", $reqPol->{'mss_mrw_safemode_mem_throttled_n_commands_per_port'},
    "MSS_MRW_PWR_SLOPE", $reqPol->{'mss_mrw_pwr_slope'},
    "MSS_MRW_PWR_INTERCEPT", $reqPol->{'mss_mrw_pwr_intercept'},
    "PROC_FSP_MMIO_MASK_SIZE", 0x0000000100000000,
    "PROC_FSP_BAR_SIZE", 0xFFFFFC00FFFFFFFF,
    "PROC_FSP_BAR_BASE_ADDR_OFFSET", 0x0000030100000000 ,
    "PROC_PSI_BRIDGE_BAR_BASE_ADDR_OFFSET", 0x0000030203000000 ,
    "PROC_NPU_PHY0_BAR_BASE_ADDR_OFFSET",0x0000030201200000 ,
    "PROC_NPU_PHY1_BAR_BASE_ADDR_OFFSET", 0x0000030201400000 ,
    "PROC_NX_RNG_BAR_BASE_ADDR_OFFSET", 0x00000302031D0000 ,
    "PROC_NPU_MMIO_BAR_BASE_ADDR_OFFSET", 0x0000030200000000,
    "CP_REFCLOCK_RCVR_TERM", $reqPol->{'processor-refclock-receiver-termination'},
    "IO_REFCLOCK_RCVR_TERM", $reqPol->{'pci-refclock-receiver-termination'},
    "SYSTEM_RESCLK_STEP_DELAY", $reqPol->{'system_resclk_step_delay'},
    "NEST_LEAKAGE_PERCENT", $reqPol->{'nest_leakage_percent'},
    "PM_SAFE_VOLTAGE_MV", $reqPol->{'pm_safe_voltage_mv'},
    "IVRM_STABILIZATION_DELAY_NS", $reqPol->{'ivrm_stabilization_delay_ns'},
    "SBE_UPDATE_DISABLE", 0,
    "SYSTEM_WOF_DISABLE", $reqPol->{'system_wof_disable'},
];

if ($reqPol->{'mss_mrw_refresh_rate_request'} eq 'SINGLE')
{
    push @systemAttr, ['MSS_MRW_REFRESH_RATE_REQUEST', 1];
}
elsif ($reqPol->{'mss_mrw_refresh_rate_request'} eq 'DOUBLE')
{
    push @systemAttr, ['MSS_MRW_REFRESH_RATE_REQUEST', 0];
}
elsif ($reqPol->{'mss_mrw_refresh_rate_request'} eq 'SINGLE_10_PERCENT_FASTER')
{
    push @systemAttr, ['MSS_MRW_REFRESH_RATE_REQUEST', 2];
}
elsif ($reqPol->{'mss_mrw_refresh_rate_request'} eq 'DOUBLE_10_PERCENT_FASTER')
{
    push @systemAttr, ['MSS_MRW_REFRESH_RATE_REQUEST', 3];
}

if ($reqPol->{'mss_mrw_fine_refresh_mode'} eq 'NORMAL')
{
    push @systemAttr, ['MSS_MRW_FINE_REFRESH_MODE', 0];
}
elsif ($reqPol->{'mss_mrw_fine_refresh_mode'} eq 'FIXED_2X')
{
    push @systemAttr, ['MSS_MRW_FINE_REFRESH_MODE', 1];
}
elsif ($reqPol->{'mss_mrw_fine_refresh_mode'} eq 'FIXED_4X')
{
    push @systemAttr, ['MSS_MRW_FINE_REFRESH_MODE', 2];
}
elsif ($reqPol->{'mss_mrw_fine_refresh_mode'} eq 'FLY_2X')
{
    push @systemAttr, ['MSS_MRW_FINE_REFRESH_MODE', 5];
}
elsif ($reqPol->{'mss_mrw_fine_refresh_mode'} eq 'FLY_4X')
{
    push @systemAttr, ['MSS_MRW_FINE_REFRESH_MODE', 6];
}

if ($reqPol->{'mss_mrw_temp_refresh_range'} eq 'NORMAL')
{
    push @systemAttr, ['MSS_MRW_TEMP_REFRESH_RANGE', 0];
}
elsif ($reqPol->{'mss_mrw_temp_refresh_range'} eq 'EXTEND')
{
    push @systemAttr, ['MSS_MRW_TEMP_REFRESH_RANGE', 1];
}

if ($reqPol->{'mss_mrw_dram_2N_mode'} eq 'AUTO')
{
    push @systemAttr, ['MSS_MRW_DRAM_2N_MODE', 0];
}
elsif ($reqPol->{'mss_mrw_dram_2N_mode'} eq 'FORCE_TO_1N_MODE')
{
    push @systemAttr, ['MSS_MRW_DRAM_2N_MODE', 1];
}
elsif ($reqPol->{'mss_mrw_dram_2N_mode'} eq 'FORCE_TO_2N_MODE')
{
    push @systemAttr, ['MSS_MRW_DRAM_2N_MODE', 2];
}

if ($reqPol->{'required_synch_mode'} eq 'never')
{
    push @systemAttr, ['REQUIRED_SYNCH_MODE', 2];
}
elsif ($reqPol->{'required_synch_mode'} eq 'always')
{
    push @systemAttr, ['REQUIRED_SYNCH_MODE', 1];
}
elsif ($reqPol->{'required_synch_mode'} eq 'undetermined')
{
    push @systemAttr, ['REQUIRED_SYNCH_MODE', 0];
}

# Handle the new name when/if it shows up in the xml
#  otherwise we'll just rely on the default value
if ( exists $reqPol->{'system_vdm_disable'} )
{
    push @systemAttr, ['SYSTEM_VDM_DISABLE',
        $reqPol->{'system_vdm_disable'}];
}


if ( exists $reqPol->{'dpll_vdm_response'} )
{
    push @systemAttr, ['DPLL_VDM_RESPONSE',
        $reqPol->{'dpll_vdm_response'}];
}
else
{
    push @systemAttr, ['DPLL_VDM_RESPONSE', 0 ];
}

if ( exists $reqPol->{'mss_mrw_allow_unsupported_rcw'} )
{
    push @systemAttr, ['MSS_MRW_ALLOW_UNSUPPORTED_RCW',
        $reqPol->{'mss_mrw_allow_unsupported_rcw'}];
}
else
{
    push @systemAttr, ['MSS_MRW_ALLOW_UNSUPPORTED_RCW', 0 ];
}

my $xBusWidth = $reqPol->{'proc_x_bus_width'};
if( $xBusWidth == 1 )
{
    push @systemAttr, ['PROC_FABRIC_X_BUS_WIDTH', '2_BYTE'];
}
else
{
    push @systemAttr, ['PROC_FABRIC_X_BUS_WIDTH', '4_BYTE'];
}

# Note - if below attribute is specified with im-id, it will not get
#  set into the output
if( exists $reqPol->{'mss_mrw_interleave_enable'} )
{
    push @systemAttr, ['MSS_INTERLEAVE_ENABLE',
      $reqPol->{'mss_mrw_interleave_enable'}];
}


if ($reqPol->{'supports_dynamic_mem_volt'} eq 'true')
{
    push @systemAttr, ['SUPPORTS_DYNAMIC_MEM_VOLT', 1];
}
else
{
    push @systemAttr, ['SUPPORTS_DYNAMIC_MEM_VOLT', 0];
}

# Handle the new name when/if it shows up in the xml
#  otherwise we'll just rely on the default value
if ( exists $reqPol->{'mss_mrw_force_bcmode_off'} )
{
    push @systemAttr, ['MSS_MRW_FORCE_BCMODE_OFF',
      $reqPol->{'mss_mrw_force_bcmode_off'}];
}


# Handle the new name when it shows up in the xml
#  otherwise force the value
if ( exists $reqPol->{'wof_enable_vratio'} )
{
    push @systemAttr, ['WOF_ENABLE_VRATIO',
      $reqPol->{'wof_enable_vratio'}];
}
else
{
    push @systemAttr, ['WOF_ENABLE_VRATIO', 'CALCULATED'];
}

# Handle the new name when it shows up in the xml
#  otherwise force the value
if ( exists $reqPol->{'wof_vratio_select'} )
{
    push @systemAttr, ['WOF_VRATIO_SELECT',
      $reqPol->{'wof_vratio_select'}];
}
else
{
    push @systemAttr, ['WOF_VRATIO_SELECT', 'ACTIVE_CORES'];
}

# Handle the new name when/if it shows up in the xml
#  otherwise we'll just rely on the default value
if ( exists $reqPol->{'mss_mrw_nvdimm_plug_rules'} )
{
    push @systemAttr, ['MSS_MRW_NVDIMM_PLUG_RULES',
      $reqPol->{'mss_mrw_nvdimm_plug_rules'}];
}


my $nestFreq = $reqPol->{'proc_pb_frequency'}->{content};


if($nestFreq == 1600)
{
    push @systemAttr, ['NEST_PLL_BUCKET', 1];
}
elsif ($nestFreq == 1866)
{
    push @systemAttr, ['NEST_PLL_BUCKET', 2];
}
elsif ($nestFreq == 2000)
{
    push @systemAttr, ['NEST_PLL_BUCKET', 3];
}
elsif ($nestFreq == 2133)
{
    push @systemAttr, ['NEST_PLL_BUCKET', 4];
}
elsif ($nestFreq == 2400)
{
    push @systemAttr, ['NEST_PLL_BUCKET', 5];
}


my %domainProgram = (   MSS_VDD_PROGRAM  => $reqPol->{'mss_vdd_program'},
                        MSS_VCS_PROGRAM  => $reqPol->{'mss_vcs_program'},
                        MSS_AVDD_PROGRAM => $reqPol->{'mss_avdd_program'},
                        MSS_VDDR_PROGRAM => $reqPol->{'mss_vddr_program'},
                        MSS_VPP_PROGRAM  => $reqPol->{'mss_vpp_program'} );
for my $domain (keys %domainProgram)
{
    if ($domainProgram{$domain} eq "poweron")
    {
        push @systemAttr, [$domain, POWERON_PROGRAM];
    }
    elsif ($domainProgram{$domain} eq "static")
    {
        push @systemAttr, [$domain, STATIC_PROGRAM];
    }
    elsif ($domainProgram{$domain} eq "dynamic")
    {
        push @systemAttr, [$domain, DYNAMIC_PROGRAM];
    }
    elsif ($domainProgram{$domain} eq "default")
    {
        push @systemAttr, [$domain, DEFAULT_PROGRAM];
    }
    else
    {
        # default to not program in host_enable_memvolt
        push @systemAttr, [$domain, POWERON_PROGRAM];
    }
}

my %procLoadline = ();
$procLoadline{PROC_R_LOADLINE_VDD_UOHM}{sys}
    = $reqPol->{'proc_r_loadline_vdd' }[0];
$procLoadline{PROC_R_DISTLOSS_VDD_UOHM}{sys}
    = $reqPol->{'proc_r_distloss_vdd' }[0];
$procLoadline{PROC_VRM_VOFFSET_VDD_UV}{sys}
    = $reqPol->{'proc_vrm_voffset_vdd'}[0];
$procLoadline{PROC_R_LOADLINE_VCS_UOHM}{sys}
    = $reqPol->{'proc_r_loadline_vcs' }[0];
$procLoadline{PROC_R_DISTLOSS_VCS_UOHM}{sys}
    = $reqPol->{'proc_r_distloss_vcs' }[0];
$procLoadline{PROC_VRM_VOFFSET_VCS_UV}{sys}
    = $reqPol->{'proc_vrm_voffset_vcs'}[0];
$procLoadline{PROC_R_LOADLINE_VDN_UOHM}{sys}
    = $reqPol->{'proc_r_loadline_vdn' }[0];
$procLoadline{PROC_R_DISTLOSS_VDN_UOHM}{sys}
    = $reqPol->{'proc_r_distloss_vdn' }[0];
$procLoadline{PROC_VRM_VOFFSET_VDN_UV}{sys}
    = $reqPol->{'proc_vrm_voffset_vdn'}[0];

#Save avsbus data to add to proc target type later
our %voltageRails = (
        "vdd_avsbus_busnum" => $reqPol->{'vdd_avsbus_busnum'},
        "vdd_avsbus_rail"   => $reqPol->{'vdd_avsbus_rail'  },
        "vdn_avsbus_busnum" => $reqPol->{'vdn_avsbus_busnum'},
        "vdn_avsbus_rail"   => $reqPol->{'vdn_avsbus_rail'  },
        "vcs_avsbus_busnum" => $reqPol->{'vcs_avsbus_busnum'},
        "vcs_avsbus_rail"   => $reqPol->{'vcs_avsbus_rail'  }, );




my $optPol = $sysPolicy->{"optional-policy-settings"};
if(defined $optPol->{'loadline-overrides'})
{
    foreach my $attr (keys %procLoadline)
    {
        my $mrwPolicy = lc $attr;
        foreach my $pol (@ {$optPol->{'loadline-overrides'}{$mrwPolicy}} )
        {
            if(defined $pol->{target})
            {
                if(defined $procLoadline{$attr}{ $pol->{target} })
                {
                    die "Multiple overrides of $attr specified for same target "
                        . "proc $pol->{target}\n";
                }
                $procLoadline{$attr}{ $pol->{target} } = $pol->{content} ;
            }
        }
    }
}

my $xbusFfePrecursor = $reqPol->{'io_xbus_tx_ffe_precursor'};

if ($MAXNODE > 1 && $sysname !~ m/mfg/)
{
    push @systemAttr, ["DO_ABUS_DECONFIG", 0];
}

# Process optional policies related to dyanmic VID
my $optMrwPolicies = $sysPolicy->{"optional-policy-settings"};
use constant MRW_NAME => 'mrw-name';

my %optSysPolicies = ();
my %optNodePolicies = ();

# Add the optional system-level attributes
$optSysPolicies{'MIN_FREQ_MHZ'}{MRW_NAME}
    = "minimum-frequency" ;
$optSysPolicies{'NOMINAL_FREQ_MHZ'}{MRW_NAME}
    = "nominal-frequency" ;
$optSysPolicies{'FREQ_CORE_MAX'}{MRW_NAME}
    = "maximum-frequency" ;
$optSysPolicies{'MSS_CENT_AVDD_SLOPE_ACTIVE'}{MRW_NAME}
    = "mem_avdd_slope_active" ;
$optSysPolicies{'MSS_CENT_AVDD_SLOPE_INACTIVE'}{MRW_NAME}
    = "mem_avdd_slope_inactive" ;
$optSysPolicies{'MSS_CENT_AVDD_INTERCEPT'}{MRW_NAME}
    = "mem_avdd_intercept" ;
$optSysPolicies{'MSS_VOLT_VPP_SLOPE'}{MRW_NAME}
    = "mem_vpp_slope" ;
$optSysPolicies{'MSS_VOLT_VPP_INTERCEPT'}{MRW_NAME}
    = "mem_vpp_intercept" ;
$optSysPolicies{'MSS_VOLT_DDR3_VDDR_SLOPE'}{MRW_NAME}
    = "mem_ddr3_vddr_slope" ;
$optSysPolicies{'MSS_VOLT_DDR3_VDDR_INTERCEPT'}{MRW_NAME}
    = "mem_ddr3_vddr_intercept" ;
$optSysPolicies{'MSS_VOLT_DDR4_VDDR_SLOPE'}{MRW_NAME}
    = "mem_ddr4_vddr_slope" ;
$optSysPolicies{'MSS_VOLT_DDR4_VDDR_INTERCEPT'}{MRW_NAME}
    = "mem_ddr4_vddr_intercept" ;
$optSysPolicies{'MRW_DDR3_VDDR_MAX_LIMIT'}{MRW_NAME}
    = "mem_ddr3_vddr_max_limit" ;
$optSysPolicies{'MRW_DDR4_VDDR_MAX_LIMIT'}{MRW_NAME}
    = "mem_ddr4_vddr_max_limit" ;


# Add the optional node-level attributes
$optNodePolicies{'MSS_CENT_VDD_SLOPE_ACTIVE'}{MRW_NAME}
    = "mem_vdd_slope_active" ;
$optNodePolicies{'MSS_CENT_VDD_SLOPE_INACTIVE'}{MRW_NAME}
    = "mem_vdd_slope_inactive" ;
$optNodePolicies{'MSS_CENT_VDD_INTERCEPT'}{MRW_NAME}
    = "mem_vdd_intercept" ;
$optNodePolicies{'MSS_CENT_VCS_SLOPE_ACTIVE'}{MRW_NAME}
    = "mem_vcs_slope_active" ;
$optNodePolicies{'MSS_CENT_VCS_SLOPE_INACTIVE'}{MRW_NAME}
    = "mem_vcs_slope_inactive" ;
$optNodePolicies{'MSS_CENT_VCS_INTERCEPT'}{MRW_NAME}
    = "mem_vcs_intercept" ;


# Add System Attributes
foreach my $policy ( keys %optSysPolicies )
{
    if(exists $optMrwPolicies->{ $optSysPolicies{$policy}{MRW_NAME}})
    {
        push @systemAttr, [ $policy ,
          $optMrwPolicies->{$optSysPolicies{$policy}{MRW_NAME}}];
    }
}

# Add Node Attribues
foreach my $policy ( keys %optNodePolicies )
{
    if(exists $optMrwPolicies->{ $optNodePolicies{$policy}{MRW_NAME}})
    {
        push @nodeAttr, [ $policy ,
          $optMrwPolicies->{$optNodePolicies{$policy}{MRW_NAME}}];
    }
}


#OpenPOWER policies
foreach my $policy (keys %{$optMrwPolicies->{"open_power"}})
{
        push(@systemAttr,[ uc($policy),
            $optMrwPolicies->{"open_power"}->{$policy} ] );
}




#------------------------------------------------------------------------------
# Process the pm-settings MRW file
#------------------------------------------------------------------------------
my $pm_settings_file = open_mrw_file($mrwdir, "${sysname}-pm-settings.xml");
my $pmSettings = parse_xml_file($pm_settings_file,
                       forcearray=>['processor-settings']);

my @pmChipAttr; # Repeated [NODE, POS, ATTR, VAL, ATTR, VAL, ATTR, VAL...]
my $pbaxAttr;
my $pbaxId;

foreach my $i (@{$pmSettings->{'processor-settings'}})
{
    if(exists $i->{pbax_groupid})
    {
        $pbaxAttr = "PBAX_GROUPID";
        $pbaxId = $i->{pbax_groupid};
    }
    else
    {
        $pbaxAttr = "PBAX_GROUPID";
        $pbaxId = $i->{pm_pbax_nodeid};
    }

    push @pmChipAttr,
    [
        $i->{target}->{node}, $i->{target}->{position},
        "PM_APSS_CHIP_SELECT", $i->{pm_apss_chip_select},
        $pbaxAttr, $pbaxId,
        "PBAX_CHIPID", $i->{pm_pbax_chipid},
        "PBAX_BRDCST_ID_VECTOR", $i->{pm_pbax_brdcst_id_vector},
    ];
}

my @SortedPmChipAttr = sort byNodePos @pmChipAttr;

if ((scalar @SortedPmChipAttr) == 0)
{
    # For all systems without a populated <sys>-pm-settings file, this script
    # defaults the values.
    # Orlena: Platform dropped so there will never be a populated
    #         orlena-pm-settings file
    # Brazos: SW231069 raised to get brazos-pm-settings populated
    print STDOUT "WARNING: No data in mrw dir(s): $mrwdir with ".
                  "filename:${sysname}-pm-settings.xml. Defaulting values\n";
}

#------------------------------------------------------------------------------
# Process the proc-pcie-settings MRW file
#------------------------------------------------------------------------------
my $proc_pcie_settings_file = open_mrw_file($mrwdir,
                                           "${sysname}-proc-pcie-settings.xml");
my $ProcPcie = parse_xml_file($proc_pcie_settings_file,
                    forcearray=>['processor-settings']);

my %procPcieTargetList = ();
my $pcieInit = 0;

# MAX Phb values Per PROC is 6 in P9 and is hard coded here
use constant MAX_NUM_PHB_PER_PROC => 6;

# MAX lane settings value is 16 lanes per phb and is hard coded here
use constant MAX_LANE_SETTINGS_PER_PHB => 16;

################################################################################
# If value is hex, convert to regular number
###############################################################################

sub unhexify {
    my($val) = @_;
    if($val =~ m/^0[xX][01234567890A-Fa-f]+$/)
    {
        $val = hex($val);
    }
    return $val;
}

# Determine values of proc pcie attributes
# Currently
#   PROC_PCIE_LANE_EQUALIZATION_GEN3/4 PROC_PCIE_IOP_CONFIG PROC_PCIE_PHB_ACTIVE
sub pcie_init ($)
{
    my $proc = $_[0];

    # Used for handling shifting operations of hex values read from mrw
    # done in scope to not affect sort functions
    use bigint;

    my $procPcieKey = "";
    my @gen3_phb_values = ();  # [PHB#][lane#] = uint16 value
    my @gen4_phb_values = ();  # [PHB#][lane#] = uint16 value
    my $procPcieIopConfig = 0;
    my $procPciePhbActive = 0;
    $procPcieKey = sprintf("n%dp%d\,", $proc->{'target'}->{'node'},
                            $proc->{'target'}->{'position'});

    if(!(exists($procPcieTargetList{$procPcieKey})))
    {
        # Loop through each PHB which each contain 32 bytes (2 bytes * 16) of EQ
        foreach my $Phb (@{$proc->{'phb-settings'}})
        {
            my $phb_number = 0;
            if(exists($Phb->{'phb-number'}))
            {
                $phb_number = $Phb->{'phb-number'};
            }
            else
            {
                die "ERROR: phb-number does not exist for
                      proc:$procPcieKey\n";
            }

            # Each PHB has 16 lanes (Each lane containing 2 total bytes of EQ)
            foreach my $Lane (@{$Phb->{'lane-settings'}})
            {
                my $lane_number = 0;
                if(exists($Lane->{'lane-number'}))
                {
                    $lane_number = $Lane->{'lane-number'};
                }
                else
                {
                    die "ERROR: lane-number does not exist for
                          proc:$procPcieKey\n";
                }

                my $gen = 3;
                my $pPhb_value = \@gen3_phb_values;
                while ($gen < 5) # go through gen3 and gen4
                {
                    if ($gen == 4)
                    {
                        $pPhb_value = \@gen4_phb_values
                    }
                    my $genKey = "gen".$gen;
                    foreach my $Equ (@{$Lane->{$genKey}{'equalization-setting'}})
                    {
                        my $eq_value = hex($Equ->{value});

                        # Accumulate all values for each of the lanes from the MRW
                        # (2 Bytes)
                        # First Byte:
                        #       - Nibble 1: up_rx_hint (bit 0 reserved)
                        #       - Nibble 2: up_tx_preset
                        # Second Byte:
                        #       - Nibble 1: dn_rx_hint (bit 0 reserved)
                        #       - Nibble 2: dn_tx_preset

                        if($Equ->{'type'} eq 'up_rx_hint')
                        {
                            $pPhb_value->[$phb_number][$lane_number] =
                                $pPhb_value->[$phb_number][$lane_number] |
                                (($eq_value & 0x0007) << 12);
                            if($eq_value > 0x7)
                            {
                                die "ERROR: Attempting to modify the
                                     reserved bit in $genKey PHB$phb_number
                                     (up_rx_hint value: ". $Equ->{value} . ")\n";
                            }
                        }
                        if($Equ->{'type'} eq 'up_tx_preset')
                        {
                            $pPhb_value->[$phb_number][$lane_number] =
                                $pPhb_value->[$phb_number][$lane_number] |
                                (($eq_value & 0x000F) << 8);
                        }
                        if($Equ->{'type'} eq 'dn_rx_hint')
                        {
                            $pPhb_value->[$phb_number][$lane_number] =
                                $pPhb_value->[$phb_number][$lane_number] |
                                (($eq_value & 0x0007) << 4);
                            if($eq_value > 0x7)
                            {
                                die "ERROR: Attempting to modify the
                                     reserved bit in $genKey PHB$phb_number
                                     (dn_rx_hint value: ". $Equ->{value} . ")\n";
                            }
                        }
                        if($Equ->{'type'} eq 'dn_tx_preset')
                        {
                            $pPhb_value->[$phb_number][$lane_number] =
                                $pPhb_value->[$phb_number][$lane_number] |
                                ($eq_value & 0x000F);
                        }
                    } # end of equalization-setting
                    $gen++;
                } # end of gen
            } # end of lane-number
        } # end of phb

        my @gen3PhbValues; # gen3 PHB values for this processor
        my @gen4PhbValues; # gen4 PHB values for this processor

        for (my $phbnumber = 0; $phbnumber < MAX_NUM_PHB_PER_PROC;
             ++$phbnumber)
        {
            my $gen3PhbValue;
            my $gen4PhbValue;

            for(my $lane_settings_count = 0;
                $lane_settings_count < MAX_LANE_SETTINGS_PER_PHB;
                ++$lane_settings_count)
            {
                $gen3PhbValue = sprintf("%s0x%04X\,", $gen3PhbValue,
                    $gen3_phb_values[$phbnumber][$lane_settings_count]);
                $gen4PhbValue = sprintf("%s0x%04X\,", $gen4PhbValue,
                    $gen4_phb_values[$phbnumber][$lane_settings_count]);
            }

            $gen3PhbValues[$phbnumber] = substr($gen3PhbValue, 0, -1);
            $gen4PhbValues[$phbnumber] = substr($gen4PhbValue, 0, -1);
        }

        if ( exists($proc->{proc_pcie_iop_config}) )
        {
            $procPcieIopConfig = $proc->{proc_pcie_iop_config};
        }
        if ( exists($proc->{proc_pcie_phb_active}) )
        {
            $procPciePhbActive = $proc->{proc_pcie_phb_active};
        }

        $procPcieTargetList{$procPcieKey} = {
            'procName'      => $proc->{'target'}->{'name'},
            'procPosition'  => $proc->{'target'}->{'position'},
            'nodePosition'  => $proc->{'target'}->{'node'},
            'gen3phbValues' => \@gen3PhbValues,
            'gen4phbValues' => \@gen4PhbValues,
            'phbActive'     => $procPciePhbActive,
            'iopConfig'     => $procPcieIopConfig,
        };
    } # end of processor loop
}

# Repeated [NODE, POS, ATTR, IOP0-VAL, IOP1-VAL, ATTR, IOP0-VAL, IOP1-VAL]
my @pecPcie;
foreach my $proc (@{$ProcPcie->{'processor-settings'}})
{
    # determine values of proc pcie attributes
    pcie_init($proc);

}


#------------------------------------------------------------------------------
# Process the chip-ids MRW file
#------------------------------------------------------------------------------
my $chip_ids_file = open_mrw_file($mrwdir, "${sysname}-chip-ids.xml");
my $chipIds = parse_xml_file($chip_ids_file, forcearray=>['chip-id']);

use constant CHIP_ID_NODE => 0;
use constant CHIP_ID_POS  => 1;
use constant CHIP_ID_PATH => 2;
use constant CHIP_ID_NXPX => 3;

my @chipIDs;
foreach my $i (@{$chipIds->{'chip-id'}})
{
    push @chipIDs, [ $i->{node}, $i->{position}, $i->{'instance-path'},
                     "n$i->{target}->{node}:p$i->{target}->{position}" ];
}

#------------------------------------------------------------------------------
# Process the power-busses MRW file
#------------------------------------------------------------------------------
my $power_busses_file = open_mrw_file($mrwdir, "${sysname}-power-busses.xml");
my $powerbus = parse_xml_file($power_busses_file);

my @pbus;
use constant PBUS_FIRST_END_POINT_INDEX => 0;
use constant PBUS_SECOND_END_POINT_INDEX => 1;
use constant PBUS_DOWNSTREAM_INDEX => 2;
use constant PBUS_UPSTREAM_INDEX => 3;
use constant PBUS_TX_MSB_LSB_SWAP => 4;
use constant PBUS_RX_MSB_LSB_SWAP => 5;
use constant PBUS_ENDPOINT_INSTANCE_PATH => 6;
use constant PBUS_NODE_CONFIG_FLAG => 7;
foreach my $i (@{$powerbus->{'power-bus'}})
{
    # Pull out the connection information from the description
    # example: n0:p0:A2 to n0:p2:A2

    my $endp1 = $i->{'description'};
    my $endp2 = "null";
    my $dwnstrm_swap = 0;
    my $upstrm_swap = 0;
    my $nodeconfig = "null";

    my $present = index $endp1, 'not connected';
    if ($present eq -1)
    {
        $endp2 = $endp1;
        $endp1 =~ s/^(.*) to.*/$1/;
        $endp2 =~ s/.* to (.*)\s*$/$1/;

        # Grab the lane swap information
        $dwnstrm_swap = $i->{'downstream-n-p-lane-swap-mask'};
        $upstrm_swap =  $i->{'upstream-n-p-lane-swap-mask'};

        # Abort if node config information is not found
        if(!(exists $i->{'include-for-node-config'}))
        {
            die "include-for-node-config element not found ";
        }
        $nodeconfig = $i->{'include-for-node-config'};
    }
    else
    {
        $endp1 =~ s/^(.*) unit.*/$1/;
        $endp2 = "invalid";


        # Set the lane swap information to 0 to avoid junk
        $dwnstrm_swap = 0;
        $upstrm_swap =  0;
    }

    my $bustype = $endp1;
    $bustype =~ s/.*:p.*:(.).*/$1/;
    my $tx_swap = 0;
    my $rx_swap = 0;
    if (lc($bustype) eq "a")
    {
        $tx_swap =  $i->{'tx-msb-lsb-swap'};
        $rx_swap =  $i->{'rx-msb-lsb-swap'};
        $tx_swap = ($tx_swap eq "false") ? 0 : 1;
        $rx_swap = ($rx_swap eq "false") ? 0 : 1;
    }

    my $endpoint1_ipath = $i->{'endpoint'}[0]->{'instance-path'};
    my $endpoint2_ipath = $i->{'endpoint'}[1]->{'instance-path'};
    #print STDOUT "powerbus: $endp1, $endp2, $dwnstrm_swap, $upstrm_swap\n";

    # Brazos: Populate power bus list only for "2-node", 3-and-4-node  & "all"
    #         configuration for ABUS. Populate all entries for other bus type.

    # Other targets(tuleta, alphine..etc) : nodeconfig will be "all".

    if ( (lc($bustype) ne "a") || ($nodeconfig eq $NODECONF) ||
            ($nodeconfig eq "all") )
    {
        push @pbus, [ lc($endp1), lc($endp2), $dwnstrm_swap,
                      $upstrm_swap, $tx_swap, $rx_swap, $endpoint1_ipath,
                      $nodeconfig ];
        push @pbus, [ lc($endp2), lc($endp1), $dwnstrm_swap,
                      $upstrm_swap, $tx_swap, $rx_swap, $endpoint2_ipath,
                      $nodeconfig ];
    }
}

#------------------------------------------------------------------------------
# Process the dmi-busses MRW file
#------------------------------------------------------------------------------
my $dmi_busses_file = open_mrw_file($mrwdir, "${sysname}-dmi-busses.xml");
my $dmibus = parse_xml_file($dmi_busses_file, forcearray=>['dmi-bus']);

my @dbus_mcs;
use constant DBUS_MCS_NODE_INDEX => 0;
use constant DBUS_MCS_PROC_INDEX => 1;
use constant DBUS_MCS_UNIT_INDEX => 2;
use constant DBUS_MCS_DOWNSTREAM_INDEX => 3;
use constant DBUS_MCS_TX_SWAP_INDEX => 4;
use constant DBUS_MCS_RX_SWAP_INDEX => 5;
use constant DBUS_MCS_SWIZZLE_INDEX => 6;

my @dbus_centaur;
use constant DBUS_CENTAUR_NODE_INDEX => 0;
use constant DBUS_CENTAUR_MEMBUF_INDEX => 1;
use constant DBUS_CENTAUR_UPSTREAM_INDEX => 2;
use constant DBUS_CENTAUR_TX_SWAP_INDEX => 3;
use constant DBUS_CENTAUR_RX_SWAP_INDEX => 4;
foreach my $dmi (@{$dmibus->{'dmi-bus'}})
{
    # First grab the MCS information
    # MCS is always master so it gets downstream
    my $node = $dmi->{'mcs'}->{'target'}->{'node'};
    my $proc = $dmi->{'mcs'}->{'target'}->{'position'};
    my $mcs = $dmi->{'mcs'}->{'target'}->{'chipUnit'};
    my $swap = $dmi->{'downstream-n-p-lane-swap-mask'};
    my $tx_swap = $dmi->{'tx-msb-lsb-swap'};
    my $rx_swap = $dmi->{'rx-msb-lsb-swap'};
    $tx_swap = ($tx_swap eq "false") ? 0 : 1;
    $rx_swap = ($rx_swap eq "false") ? 0 : 1;
    my $swizzle = $dmi->{'mcs-refclock-enable-mapping'};
    #print STDOUT "dbus_mcs: n$node:p$proc:mcs:$mcs swap:$swap\n";
    push @dbus_mcs, [ $node, $proc, $mcs, $swap, $tx_swap, $rx_swap, $swizzle ];

    # Now grab the centuar chip information
    # Centaur is always slave so it gets upstream
    my $node = $dmi->{'centaur'}->{'target'}->{'node'};
    my $membuf = $dmi->{'centaur'}->{'target'}->{'position'};
    my $swap = $dmi->{'upstream-n-p-lane-swap-mask'};
    my $tx_swap = $dmi->{'rx-msb-lsb-swap'};
    my $rx_swap = $dmi->{'tx-msb-lsb-swap'};
    $tx_swap = ($tx_swap eq "false") ? 0 : 1;
    $rx_swap = ($rx_swap eq "false") ? 0 : 1;
    #print STDOUT "dbus_centaur: n$node:cen$membuf swap:$swap\n";
    push @dbus_centaur, [ $node, $membuf, $swap, $tx_swap, $rx_swap ];
}


#------------------------------------------------------------------------------
# Process the dimm-vrds MRW file
#------------------------------------------------------------------------------
my $dimm_vrds_file = open_mrw_file($mrwdir, "${sysname}-dimm-vrds.xml");
my $mrwMemVoltageDomains = parse_xml_file($dimm_vrds_file,
                                 forcearray=>['dimm-vrd-connection']);

our %vrmHash = ();
my %dimmVrmUuidHash;
my %vrmIdHash;
my %validVrmTypes
    = ('VDDR' => 1,'AVDD' => 1,'VCS' => 1,'VPP' => 1,'VDD' => 1);
use constant VRM_I2C_DEVICE_PATH => 'vrmI2cDevicePath';
use constant VRM_I2C_ADDRESS => 'vrmI2cAddress';
use constant VRM_DOMAIN_TYPE => 'vrmDomainType';
use constant VRM_DOMAIN_ID => 'vrmDomainId';
use constant VRM_UUID => 'vrmUuid';

foreach my $mrwMemVoltageDomain (
    @{$mrwMemVoltageDomains->{'dimm-vrd-connection'}})
{
    if( (!exists $mrwMemVoltageDomain->{'vrd'}->{'i2c-dev-path'})
       || (!exists $mrwMemVoltageDomain->{'vrd'}->{'i2c-address'})
       || (ref($mrwMemVoltageDomain->{'vrd'}->{'i2c-dev-path'}) eq "HASH")
       || (ref($mrwMemVoltageDomain->{'vrd'}->{'i2c-address'}) eq "HASH")
       || ($mrwMemVoltageDomain->{'vrd'}->{'i2c-dev-path'} eq "")
       || ($mrwMemVoltageDomain->{'vrd'}->{'i2c-address'} eq ""))
    {
        next;
    }

    my $vrmDev  = $mrwMemVoltageDomain->{'vrd'}->{'i2c-dev-path'};
    my $vrmAddr = $mrwMemVoltageDomain->{'vrd'}->{'i2c-address'};
    my $vrmType = uc $mrwMemVoltageDomain->{'vrd'}->{'type'};
    my $dimmInstance =
        "n"  . $mrwMemVoltageDomain->{'dimm'}->{'target'}->{'node'} .
        ":p" . $mrwMemVoltageDomain->{'dimm'}->{'target'}->{'position'};

    if ($vrmType eq 'VMEM') # VMEM is same as VDDR
    {
        $vrmType = 'VDDR';
    }

    if(!exists $validVrmTypes{$vrmType})
    {
        die "Illegal VRM type of $vrmType used\n";
    }

    if(!exists $vrmIdHash{$vrmType})
    {
        $vrmIdHash{$vrmType} = 1; # changed to 1 as 0 = invalid
    }

    my $uuid = -1;
    foreach my $vrm ( keys %vrmHash )
    {
        if(   ($vrmHash{$vrm}{VRM_I2C_DEVICE_PATH} eq $vrmDev )
           && ($vrmHash{$vrm}{VRM_I2C_ADDRESS}     eq $vrmAddr)
           && ($vrmHash{$vrm}{VRM_DOMAIN_TYPE}     eq $vrmType) )
        {
            #print STDOUT "-> Duplicate VRM: $vrm  ($dimmInstance)\n";
            #print STDOUT "-> Device path: $vrmDev + Address: $vrmAddr\n";
            #print STDOUT "-> VRM Domain Type: $vrmType\n";
            #print STDOUT "-> VRM Domain ID: $vrmHash{$vrm}{VRM_DOMAIN_ID}\n";
            $uuid =  $vrm;
            last;
        }
    }

    if($uuid == -1)
    {
        my $vrm = scalar keys %vrmHash;
        $vrmHash{$vrm}{VRM_I2C_DEVICE_PATH} = $vrmDev;
        $vrmHash{$vrm}{VRM_I2C_ADDRESS} = $vrmAddr;
        $vrmHash{$vrm}{VRM_DOMAIN_TYPE} = $vrmType;
        $vrmHash{$vrm}{VRM_DOMAIN_ID} =
            $vrmIdHash{$vrmType}++;
        $uuid = $vrm;

        #print STDOUT "** New vrm: $vrm  ($dimmInstance)\n";
        #print STDOUT "Device path: $vrmDev + Address: $vrmAddr\n";
        #print STDOUT "VRM Domain Type: $vrmType\n";
        #print STDOUT "VRM Domain ID: $vrmHash{$vrm}{VRM_DOMAIN_ID}\n";
    }

    $dimmVrmUuidHash{$dimmInstance}{$vrmType}{VRM_UUID} = $uuid;
}

my $vrmDebug = 0;
if($vrmDebug)
{
    print STDOUT "DIMM list from $dimm_vrds_file\n";
    foreach my $dimm ( sort keys %dimmVrmUuidHash)
    {
        print STDOUT "dimm instance: (" . $dimm . ")\n";
        foreach my $vrmType ( keys %{$dimmVrmUuidHash{$dimm}} )
        {
            print STDOUT "VRM type: " . $vrmType . "\n";
            print STDOUT "VRM UUID: " .
                $dimmVrmUuidHash{$dimm}{$vrmType}{VRM_UUID} . "\n";
        }
    }

    foreach my $vrm ( keys %vrmHash)
    {
        print STDOUT "VRM UUID: " . $vrm . "\n";
        print STDOUT "VRM type: " . $vrmHash{$vrm}{VRM_DOMAIN_TYPE} . "\n";
        print STDOUT "VRM id: " . $vrmHash{$vrm}{VRM_DOMAIN_ID} . "\n";
        print STDOUT "VRM dev: " . $vrmHash{$vrm}{VRM_I2C_DEVICE_PATH} . "\n";
        print STDOUT "VRM addr: " .  $vrmHash{$vrm}{VRM_I2C_ADDRESS} . "\n";
    }
}

#------------------------------------------------------------------------------
# Process the proc-vrds MRW file
#------------------------------------------------------------------------------
my $proc_vrds_file = open_mrw_file($mrwdir, "${sysname}-proc-vrds.xml");
my $mrwProcVoltageDomains = parse_xml_file($proc_vrds_file,
                                 forcearray=>['proc-vrd-connection']);
our %vrdHash = ();
my %procVrdUuidHash;
my %mcBistVrmUuidHash;
my %procVrdIdHash;
my %validProcVrdTypes
    = ('VCS' => 1, 'VDN' => 1, 'VIO' => 1, 'VDDR' => 1, 'VDD' => 1);

use constant VRD_PROC_I2C_DEVICE_PATH => 'vrdProcI2cDevicePath';
use constant VRD_PROC_I2C_ADDRESS => 'vrdProcI2cAddress';
use constant VRD_PROC_DOMAIN_TYPE => 'vrdProcDomainType';
use constant VRD_PROC_DOMAIN_ID => 'vrdProcDomainId';
use constant VRD_PROC_UUID => 'vrdProcUuid';

foreach my $mrwProcVoltageDomain (
    @{$mrwProcVoltageDomains->{'proc-vrd-connection'}})
{

    if( (!exists $mrwProcVoltageDomain->{'vrd'}->{'i2c-dev-path'})
      ||(!exists $mrwProcVoltageDomain->{'vrd'}->{'i2c-address'})
      ||(ref($mrwProcVoltageDomain->{'vrd'}->{'i2c-dev-path'}) eq "HASH")
       || (ref($mrwProcVoltageDomain->{'vrd'}->{'i2c-address'}) eq "HASH")
       || ($mrwProcVoltageDomain->{'vrd'}->{'i2c-dev-path'} eq "")
       || ($mrwProcVoltageDomain->{'vrd'}->{'i2c-address'} eq ""))
   {
       next;
   }

    my $procVrdDev  = $mrwProcVoltageDomain->{'vrd'}->{'i2c-dev-path'};
    my $procVrdAddr = $mrwProcVoltageDomain->{'vrd'}->{'i2c-address'};
    my $procVrdType = uc $mrwProcVoltageDomain->{'vrd'}->{'type'};
    my $procInstance =
        "n"  . $mrwProcVoltageDomain->{'proc'}->{'target'}->{'node'} .
        ":p" . $mrwProcVoltageDomain->{'proc'}->{'target'}->{'position'};


    if(!exists $validProcVrdTypes{$procVrdType})
    {
        print STDOUT "Illegal VRD type of $procVrdType used\n";
        next;
    }

    if(!exists $procVrdIdHash{$procVrdType})
    {
        $procVrdIdHash{$procVrdType} = 1; # changed to 1 as 0 = invalid
    }
    my $uuid = -1;
    foreach my $vrd (keys %vrdHash )
    {
        if(   ($vrdHash{$vrd}{VRD_PROC_I2C_DEVICE_PATH} eq $procVrdDev )
           && ($vrdHash{$vrd}{VRD_PROC_I2C_ADDRESS}     eq $procVrdAddr)
           && ($vrdHash{$vrd}{VRD_PROC_DOMAIN_TYPE}     eq $procVrdType) )
        {
            # print STDOUT "-> Duplicate VRD: $vrd  ($procInstance)\n";
            # print STDOUT "-> Device path: $procVrdDev + Address: $procVrdAddr\n";
            # print STDOUT "-> VR Domain Type: $procVrdType\n";
            # print STDOUT "-> VR Domain ID: $vrdHash{$vrd}{VRD_PROC_DOMAIN_ID}\n";
            $uuid =  $vrd;
            last;
        }
    }

    if($uuid == -1)
    {
        my $vrd = scalar keys %vrdHash;
        $vrdHash{$vrd}{VRD_PROC_I2C_DEVICE_PATH} = $procVrdDev;
        $vrdHash{$vrd}{VRD_PROC_I2C_ADDRESS} = $procVrdAddr;
        $vrdHash{$vrd}{VRD_PROC_DOMAIN_TYPE} = $procVrdType;
        $vrdHash{$vrd}{VRD_PROC_DOMAIN_ID} =
            $procVrdIdHash{$procVrdType}++;
        $uuid = $vrd;

        #Need to manually add in the VDDR from vrd to vrm.  This is specific to all IBM
        #systems that use serverwiz 1 formatting == one and only ZZ system
        if($procVrdType eq "VDDR")
        {
            if(!exists $vrmIdHash{$procVrdType})
            {
                $vrmIdHash{procVrdType} = 1; # changed to 1 as 0 = invalid
            }
            my $vrm = scalar keys %vrmHash;
            $vrmHash{$vrm}{VRM_I2C_DEVICE_PATH} = $procVrdDev;
            $vrmHash{$vrm}{VRM_I2C_ADDRESS} = $procVrdAddr;
            $vrmHash{$vrm}{VRM_DOMAIN_TYPE} = $procVrdType;
            $vrmHash{$vrm}{VRM_DOMAIN_ID} = $vrmIdHash{$procVrdType}++;
            $mcBistVrmUuidHash{$procInstance}{$procVrdType}{VRM_UUID} = $vrm;
        }

        if(0)
        {
            print STDOUT "** New vrd: $vrd  ($procInstance)\n";
            print STDOUT "Device path: $procVrdDev + Address: $procVrdAddr\n";
            print STDOUT "VRD Domain Type: $procVrdType\n";
            print STDOUT "VRD Domain ID: $vrdHash{$vrd}{VRD_PROC_DOMAIN_ID}\n";
        }
    }
    $procVrdUuidHash{$procInstance}{$procVrdType}{VRD_PROC_UUID} = $uuid;
}


#------------------------------------------------------------------------------
# Process the cec-chips and pcie-busses MRW files
#------------------------------------------------------------------------------
my $cec_chips_file = open_mrw_file($mrwdir, "${sysname}-cec-chips.xml");
my $devpath = parse_xml_file($cec_chips_file,
                        KeyAttr=>'instance-path');

my $pcie_busses_file = open_mrw_file($mrwdir, "${sysname}-pcie-busses.xml");
my $pcie_buses = parse_xml_file($pcie_busses_file);

our %pcie_list;

foreach my $pcie_bus (@{$pcie_buses->{'pcie-bus'}})
{
    if(!exists($pcie_bus->{'switch'}))
    {
        foreach my $lane_set (0,1)
        {
            $pcie_list{$pcie_bus->{source}->{'instance-path'}}->{$pcie_bus->
                                            {source}->{iop}}->{$lane_set}->
                                            {'lane-mask'} = 0;
            $pcie_list{$pcie_bus->{source}->{'instance-path'}}->{$pcie_bus->
                                            {source}->{iop}}->{$lane_set}->
                                            {'dsmp-capable'} = 0;
            $pcie_list{$pcie_bus->{source}->{'instance-path'}}->{$pcie_bus->
                                            {source}->{iop}}->{$lane_set}->
                                            {'lane-swap'} = 0;
            $pcie_list{$pcie_bus->{source}->{'instance-path'}}->{$pcie_bus->
                                            {source}->{iop}}->{$lane_set}->
                                            {'lane-reversal'} = 0;
            $pcie_list{$pcie_bus->{source}->{'instance-path'}}->{$pcie_bus->
                                            {source}->{iop}}->{$lane_set}->
                                            {'is-slot'} = 0;
        }
    }
}

foreach my $pcie_bus (@{$pcie_buses->{'pcie-bus'}})
{
    if(!exists($pcie_bus->{'switch'}))
    {
        my $dsmp_capable = 0;
        my $is_slot = 0;
        if((exists($pcie_bus->{source}->{'dsmp-capable'}))&&
          ($pcie_bus->{source}->{'dsmp-capable'} eq 'Yes'))
        {

            $dsmp_capable = 1;
        }

        if((exists($pcie_bus->{endpoint}->{'is-slot'}))&&
          ($pcie_bus->{endpoint}->{'is-slot'} eq 'Yes'))
        {

            $is_slot = 1;
        }
        my $lane_set = 0;
        if(($pcie_bus->{source}->{'lane-mask'} eq '0xFFFF')||
           ($pcie_bus->{source}->{'lane-mask'} eq '0xFF00'))
        {
            $lane_set = 0;
        }
        else
        {
            if($pcie_bus->{source}->{'lane-mask'} eq '0x00FF')
            {
                $lane_set = 1;
            }

        }
        $pcie_list{$pcie_bus->{source}->{'instance-path'}}->
            {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-mask'}
                = $pcie_bus->{source}->{'lane-mask'};
        $pcie_list{$pcie_bus->{source}->{'instance-path'}}->
            {$pcie_bus->{source}->{iop}}->{$lane_set}->{'dsmp-capable'}
                = $dsmp_capable;
        $pcie_list{$pcie_bus->{source}->{'instance-path'}}->
            {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-swap'}
                = oct($pcie_bus->{source}->{'lane-swap-bits'});
        $pcie_list{$pcie_bus->{source}->{'instance-path'}}->
            {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-reversal'}
                = oct($pcie_bus->{source}->{'lane-reversal-bits'});
        $pcie_list{$pcie_bus->{source}->{'instance-path'}}->
            {$pcie_bus->{source}->{iop}}->{$lane_set}->{'is-slot'} = $is_slot;
    }
}
our %bifurcation_list;
foreach my $pcie_bus (@{$pcie_buses->{'pcie-bus'}})
{
    if(!exists($pcie_bus->{'switch'}))
    {
        foreach my $lane_set (0,1)
        {
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-mask'}= 0;
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-swap'}= 0;
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                {$pcie_bus->{source}->{iop}}->{$lane_set}->{'lane-reversal'}= 0;
        }
    }
}
foreach my $pcie_bus (@{$pcie_buses->{'pcie-bus'}})
{
    if(   (!exists($pcie_bus->{'switch'}))
       && (exists($pcie_bus->{source}->{'bifurcation-settings'})))
    {
        my $bi_cnt = 0;
        foreach my $bifurc (@{$pcie_bus->{source}->{'bifurcation-settings'}->
                                                   {'bifurcation-setting'}})
        {
            my $lane_swap = 0;
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                             {$pcie_bus->{source}->{iop}}{$bi_cnt}->
                             {'lane-mask'} =  $bifurc->{'lane-mask'};
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                             {$pcie_bus->{source}->{iop}}{$bi_cnt}->
                             {'lane-swap'} =  oct($bifurc->{'lane-swap-bits'});
            $bifurcation_list{$pcie_bus->{source}->{'instance-path'}}->
                             {$pcie_bus->{source}->{iop}}{$bi_cnt}->
                             {'lane-reversal'} = oct($bifurc->
                             {'lane-reversal-bits'});
            $bi_cnt++;

        }


    }
}

#------------------------------------------------------------------------------
# Process the targets MRW file
#------------------------------------------------------------------------------
my $targets_file = open_mrw_file($mrwdir, "${sysname}-targets.xml");
my $eTargets = parse_xml_file($targets_file);

# Capture all targets into the @Targets array
use constant NAME_FIELD => 0;
use constant NODE_FIELD => 1;
use constant POS_FIELD  => 2;
use constant UNIT_FIELD => 3;
use constant PATH_FIELD => 4;
use constant LOC_FIELD  => 5;
use constant ORDINAL_FIELD  => 6;
use constant FRU_PATH => 7;
use constant PLUG_POS => 8;
my @Targets;
foreach my $i (@{$eTargets->{target}})
{
    my $plugPosition = $i->{'plug-xpath'};
    my $frupath = "";
    $plugPosition =~ s/.*mrw:position\/text\(\)=\'(.*)\'\]$/$1/;
    if (exists $devpath->{chip}->{$i->{'instance-path'}}->{'fru-instance-path'})
    {
        $frupath = $devpath->{chip}->{$i->{'instance-path'}}->
                                          {'fru-instance-path'};
    }

    push @Targets, [ $i->{'ecmd-common-name'}, $i->{node}, $i->{position},
                     $i->{'chip-unit'}, $i->{'instance-path'}, $i->{location},
                      0,$frupath, $plugPosition ];

    if (($i->{'ecmd-common-name'} eq "pu") && ($CHIPNAME eq ""))
    {
        $CHIPNAME = $i->{'description'};
        $CHIPNAME =~ s/Instance of (.*) cpu/$1/g;
        $CHIPNAME = lc($CHIPNAME);
    }
}

# For open-power there is an MRW change which leads the venice to be called
# opnpwr_venice. Hostboot doesn't care - it's the same PVR. So, to keep the
# rest of the tools happy (e.g., those which use target_types.xml) lets map
# the open-power venice to a regular venice. Note: not just removing the
# opnpwr_ prefix as I think we want this to be a cannary if other opnpwr_
# "processors" get created.
$CHIPNAME =~ s/opnpwr_venice/venice/g;

#------------------------------------------------------------------------------
# Process the fsi-busses MRW file
#------------------------------------------------------------------------------
my $fsi_busses_file = open_mrw_file($mrwdir, "${sysname}-fsi-busses.xml");
my $fsiBus = parse_xml_file($fsi_busses_file, forcearray=>['fsi-bus']);

# Build all the FSP chip targets / attributes
my %FSPs = ();
foreach my $fsiBus (@{$fsiBus->{'fsi-bus'}})
{
    # FSP always has master type of FSP master; Add unique ones
    my $instancePathKey = $fsiBus->{master}->{'instance-path'};
    if (    (lc($fsiBus->{master}->{type}) eq "fsp master")
        && !(exists($FSPs{$instancePathKey})))
    {
        my $node = $fsiBus->{master}->{target}->{node};
        my $position = $fsiBus->{master}->{target}->{position};
        my $huid = sprintf("0x%02X15%04X",$node,$position);
        my $rid = sprintf("0x%08X", 0x200 + $position);
        my $sys = "0";
        $FSPs{$instancePathKey} = {
            'sys'         => $sys,
            'node'        => $node,
            'position'    => $position,
            'ordinalId'   => $position,
            'instancePath'=> $fsiBus->{master}->{'instance-path'},
            'huid'        => $huid,
            'rid'         => $rid,
        };
    }
}

# Keep the knowledge of whether we have FSPs or not.
my $haveFSPs = keys %FSPs != 0;

# Build up FSI paths
# Capture all FSI connections into the @Fsis array
my @Fsis;
use constant FSI_TYPE_FIELD   => 0;
use constant FSI_LINK_FIELD   => 1;
use constant FSI_TARGET_FIELD => 2;
use constant FSI_MASTERNODE_FIELD => 3;
use constant FSI_MASTERPOS_FIELD => 4;
use constant FSI_TARGET_TYPE_FIELD  => 5;
use constant FSI_SLAVE_PORT_FIELD => 6;
use constant FSI_UNIT_ID_FIELD => 7;
use constant FSI_MASTER_TYPE_FIELD => 8;
use constant FSI_INSTANCE_FIELD => 9;
#Master procs have FSP as their master
#<fsi-bus>
#  <master>
#    <type>FSP Master</type>
#    <part-id>BRAZOS_FSP2</part-id>
#    <unit-id>FSIM_CLK[23]</unit-id>
#    <target><name>fsp</name><node>4</node><position>1</position></target>
#    <engine>0</engine>
#    <link>23</link>
#  </master>
#  <slave>
#    <part-id>VENICE</part-id>
#    <unit-id>FSI_SLAVE0</unit-id>
#    <target><name>pu</name><node>3</node><position>1</position></target>
#    <port>0</port>
#  </slave>
#</fsi-bus>
#Non-master chips have a MURANO/VENICE as their master
#<fsi-bus>
#  <master>
#    <part-id>VENICE</part-id>
#    <unit-id>FSI_CASCADE3</unit-id>
#    <target><name>pu</name><node>0</node><position>0</position></target>
#    <engine>12</engine>
#    <link>3</link>
#    <type>Cascaded Master</type>
#  </master>
#  <slave>
#    <part-id>CENTAUR</part-id>
#    <unit-id>FSI_SLAVE0</unit-id>
#    <target><name>memb</name><node>0</node><position>0</position></target>
#    <fsp-device-path-segments>L02C0E12:L3C0</fsp-device-path-segments>
#    <port>0</port>
#  </slave>
#</fsi-bus>
foreach my $fsiBus (@{$fsiBus->{'fsi-bus'}})
{
    #skip slaves that we don't care about
    if( !($fsiBus->{'slave'}->{'target'}->{'name'} eq "pu")
       && !($fsiBus->{'slave'}->{'target'}->{'name'} eq "memb") )
    {
        next;
    }

    push @Fsis, [
      #TYPE :: 'fsp master','hub master','cascaded master'
      $fsiBus->{'master'}->{'type'},
      #LINK :: coming out of master
      $fsiBus->{'master'}->{'link'},
      #TARGET :: Slave chip
        "n$fsiBus->{slave}->{target}->{node}:"
        . "p$fsiBus->{slave}->{target}->{position}",
      #MASTERNODE :: Master chip node
        "$fsiBus->{master}->{target}->{node}",
      #MASTERPOS :: Master chip position
        "$fsiBus->{master}->{target}->{position}",
      #TARGET_TYPE :: Slave chip type 'pu','memb'
      $fsiBus->{'slave'}->{'target'}->{'name'},
      #SLAVE_PORT :: mproc->'fsi_slave0',altmproc->'fsi_slave1'
      $fsiBus->{'slave'}->{'unit-id'},
      #UNIT_ID :: FSI_CASCADE, MFSI
      $fsiBus->{'master'}->{'unit-id'},
      #MASTER_TYPE :: Master chip type 'pu','memb'
      $fsiBus->{'master'}->{'target'}->{'name'},
      #INSTANCE_FIELD :: palmetto_board-assembly-0/...
      $fsiBus->{'master'}->{'instance-path'}
        ];

   #print "\nTARGET=$Fsis[$#Fsis][FSI_TARGET_FIELD]\n";
   #print "TYPE=$Fsis[$#Fsis][FSI_TYPE_FIELD]\n";
   #print "LINK=$Fsis[$#Fsis][FSI_LINK_FIELD]\n";
   #print "MASTERNODE=$Fsis[$#Fsis][FSI_MASTERNODE_FIELD]\n";
   #print "MASTERPOS=$Fsis[$#Fsis][FSI_MASTERPOS_FIELD]\n";
   #print "TARGET_TYPE=$Fsis[$#Fsis][FSI_TARGET_TYPE_FIELD]\n";
   #print "SLAVE_PORT=$Fsis[$#Fsis][FSI_SLAVE_PORT_FIELD]\n";
}
#print "Fsis = $#Fsis\n";

#------------------------------------------------------------------------------
# Process the psi-busses MRW file
#------------------------------------------------------------------------------

my @hbPSIs;
our $psiBus;

if ($haveFSPs)
{
    my $psi_busses_file = open_mrw_file($mrwdir, "${sysname}-psi-busses.xml");
    $psiBus = parse_xml_file($psi_busses_file,
                                 forcearray=>['psi-bus']);

    # Capture all PSI connections into the @hbPSIs array
    use constant HB_PSI_MASTER_CHIP_POSITION_FIELD  => 0;
    use constant HB_PSI_MASTER_CHIP_UNIT_FIELD      => 1;
    use constant HB_PSI_PROC_NODE_FIELD             => 2;
    use constant HB_PSI_PROC_POS_FIELD              => 3;

    foreach my $i (@{$psiBus->{'psi-bus'}})
    {
        push @hbPSIs, [
            $i->{fsp}->{'psi-unit'}->{target}->{position},
            $i->{fsp}->{'psi-unit'}->{target}->{chipUnit},
            $i->{processor}->{target}->{node},
            $i->{processor}->{target}->{position},
        ];
    }
}

#
#------------------------------------------------------------------------------
# Process the memory-busses MRW file
#------------------------------------------------------------------------------
my $memory_busses_file = open_mrw_file($mrwdir, "${sysname}-memory-busses.xml");
my $memBus = parse_xml_file($memory_busses_file);

# Capture all memory buses info into the @Membuses array
use constant MCS_TARGET_FIELD     =>  0;
use constant MCA_TARGET_FIELD     =>  1;
use constant CENTAUR_TARGET_FIELD =>  2;
use constant DIMM_TARGET_FIELD    =>  3;
use constant DIMM_PATH_FIELD      =>  4;
use constant BUS_NODE_FIELD       =>  5;
use constant BUS_POS_FIELD        =>  6;
use constant BUS_ORDINAL_FIELD    =>  7;
use constant DIMM_POS_FIELD       =>  8;
use constant MBA_SLOT_FIELD       =>  9;
use constant MBA_PORT_FIELD       => 10;
use constant DIMM_LOC_CODE_FIELD  => 11;

use constant CDIMM_RID_NODE_MULTIPLIER => 32;

my @Membuses;
foreach my $i (@{$memBus->{'memory-bus'}})
{
    push @Membuses, [
         "n$i->{mcs}->{target}->{node}:p$i->{mcs}->{target}->{position}:mcs" .
         $i->{mcs}->{target}->{chipUnit},
         "n$i->{mca}->{target}->{node}:p$i->{mca}->{target}->{position}:mca" .
         $i->{mca}->{target}->{chipUnit},
         "n$i->{mba}->{target}->{node}:p$i->{mba}->{target}->{position}:mba" .
         $i->{mba}->{target}->{chipUnit},
         "n$i->{dimm}->{target}->{node}:p$i->{dimm}->{target}->{position}",
         $i->{dimm}->{'instance-path'},
         $i->{mcs}->{target}->{node},
         $i->{mcs}->{target}->{position}, 0,
         $i->{dimm}->{'instance-path'},
         $i->{mba}->{'mba-slot'},
         $i->{mba}->{'mba-port'},
         $i->{dimm}->{'location-code'}];
}

# Determine if the DIMMs are CDIMM or JDIMM (IS-DIMM). Check for "not
# centaur dimm" rather than "is ddr3 dimm" so ddr4 etc will work.
my $isISDIMM = 1
   if $memBus->{'drams'}->{'dram'}[0]->{'dram-instance-path'} !~ /centaur_dimm/;

# Sort the memory busses, based on their Node, Pos & instance paths
my @SMembuses = sort byDimmNodePos @Membuses;
my $BOrdinal_ID = 0;

# Increment the Ordinal ID in sequential order for dimms.
for my $i ( 0 .. $#SMembuses )
{
    $SMembuses[$i] [BUS_ORDINAL_FIELD] = $BOrdinal_ID;
    $BOrdinal_ID += 1;
}

# Rewrite each DIMM instance path's DIMM instance to be indexed from 0
for my $i ( 0 .. $#SMembuses )
{
    $SMembuses[$i][DIMM_PATH_FIELD] =~ s/[0-9]*$/$i/;
}

#------------------------------------------------------------------------------
# Process VDDR GPIO enables
#------------------------------------------------------------------------------

my %vddrEnableHash = ();
my $useGpioToEnableVddr = 0;

if(!$haveFSPs)
{
    $useGpioToEnableVddr = 1;
}

if($useGpioToEnableVddr)
{
    my $vddrEnablesFile = open_mrw_file($mrwdir, "${sysname}-vddr.xml");
    my $vddrEnables = parse_xml_file(
        $vddrEnablesFile,
        forcearray=>['vddr-enable']);

    foreach my $vddrEnable (@{$vddrEnables->{'vddr-enable'}})
    {
        # Get dependent Centaur info
        my $centaurNode = $vddrEnable->{'centaur-target'}->{node};
        my $centaurPosition = $vddrEnable->{'centaur-target'}->{position};

        # Get I2C master which drives the GPIO for this Centaur
        my $i2cMasterNode     = $vddrEnable->{i2c}->{'master-target'}->{node};
        my $i2cMasterPosition
            = $vddrEnable->{i2c}->{'master-target'}->{position};
        my $i2cMasterPort     = $vddrEnable->{i2c}->{port};
        my $i2cMasterEngine   = $vddrEnable->{i2c}->{engine};

        # Get GPIO expander info.  For now these are pca9535 specific
        # Targeting requires real i2c address to be shifted left one bit
        my $i2cAddress        = unhexify( $vddrEnable->{i2c}->{address} ) << 1;
        my $i2cAddressHexStr  = sprintf("0x%X",$i2cAddress);
        my $vddrPort          = $vddrEnable->{'io-expander'}->{port};
        my $vddrPortPin       = $vddrEnable->{'io-expander'}->{pin};
        my $vddrPin           = $vddrPort * 8 + $vddrPortPin;

        # Build foreign keys to the Centaur targets
        my $vddrKey = "n" . $centaurNode . "p" . $centaurPosition;
        my $i2cMasterKey = "n" . $i2cMasterNode . "p" . $i2cMasterPosition;
        my $i2cMasterEntityPath =
            "physical:sys-0/node-$i2cMasterNode/membuf-$i2cMasterPosition";

        # Populate the key => value pairs for a given Centaur
        $vddrEnableHash{$vddrKey} = {
            'i2cMasterKey'        => $i2cMasterKey,
            'i2cMasterEntityPath' => $i2cMasterEntityPath,
            'i2cMasterNode'       => $i2cMasterNode,
            'i2cMasterPosition'   => $i2cMasterPosition,
            'i2cMasterPort'       => $i2cMasterPort,
            'i2cMasterEngine'     => $i2cMasterEngine,
            'i2cAddress'          => $i2cAddress,
            'i2cAddressHexStr'    => $i2cAddressHexStr,
            'vddrPin'             => $vddrPin,
        };
    }
}

#------------------------------------------------------------------------------
# Process the i2c-busses MRW file
#------------------------------------------------------------------------------
my $i2c_busses_file = open_mrw_file($mrwdir, "${sysname}-i2c-busses.xml");
my $i2cBus = XMLin($i2c_busses_file);

# Capture all i2c buses info into the @I2Cdevices array
my @I2Cdevices;
my @I2CHotPlug;
foreach my $i (@{$i2cBus->{'i2c-device'}})
{

    my $max_mem_size = "0x80";
    my $chip_count = "0x02";
    my $cycle_time = "0x05";

    if( ($i->{'content-type'} eq 'PRIMARY_SBE_VPD') ||
        ($i->{'content-type'} eq 'REDUNDANT_SBE_VPD') )
    {
        $max_mem_size = "0x100";
        $chip_count = "0x04";
        $cycle_time = "0x0A";
    }

    push @I2Cdevices, {
         'i2cm_name'=>$i->{'i2c-master'}->{target}->{name},
         'i2cm_node'=>$i->{'i2c-master'}->{target}->{node},
         'i2cm_pos' =>$i->{'i2c-master'}->{target}->{position},
         'i2cm_uid' =>$i->{'i2c-master'}->{'unit-id'},
         'i2c_content_type'=>$i->{'content-type'},
         'i2c_part_id'=>$i->{'part-id'},
         'i2c_port'=>$i->{'i2c-master'}->{'i2c-port'},
         'i2c_devAddr'=>$i->{'address'},
         'i2c_engine'=>$i->{'i2c-master'}->{'i2c-engine'},
         'i2c_speed'=>$i->{'speed'},
         'i2c_size'=>$i->{'size'},
         'i2c_byte_addr_offset'=> "0x02",
         'i2c_max_mem_size' => $max_mem_size,
         'i2c_chip_count' => $chip_count,
         'i2c_write_page_size' =>"0x80",
         'i2c_write_cycle_time' => $cycle_time,
         'i2c_instance_path' => $i->{'instance-path'},
         'i2c_card_id' => $i->{'card-id'},
         'i2c_part_type' => $i->{'part-type'} };

    if(( ($i->{'part-type'} eq 'hotplug-controller') &&
             ($i->{'part-id'} eq 'MAX5961')) ||
       ( ($i->{'part-id'} eq 'PCA9551') &&
             ($i->{'i2c-master'}->{'host-connected'} eq '1' )))
    {
        push @I2CHotPlug, {
             'i2cm_node'=>$i->{'i2c-master'}->{target}->{node},
             'i2cm_pos' =>$i->{'i2c-master'}->{target}->{position},
             'i2c_port'=>$i->{'i2c-master'}->{'i2c-port'},
             'i2c_engine'=>$i->{'i2c-master'}->{'i2c-engine'},
             'i2c_speed'=>$i->{'speed'},
             'i2c_part_id'=>$i->{'part-id'},
             'i2c_slaveAddr'=>$i->{'address'},
             'i2c_instPath'=>$i->{'instance-path'}};
     }
}

# If proc has a TPM, cache the I2C device index
my %tpmI2cIndex = ();
my %ucdI2cIndex = ();
for my $i ( 0 .. $#I2Cdevices )
{
    my $node=$I2Cdevices[$i]{i2cm_node};
    my $position=$I2Cdevices[$i]{i2cm_pos};

    if($I2Cdevices[$i]{i2c_part_type} eq "tpm")
    {
        $tpmI2cIndex{"n${node}p${position}"}=$i;
    }
    elsif(   ($I2Cdevices[$i]{i2c_part_type}   eq "hotplug-controller")
          && (   ($I2Cdevices[$i]{i2c_part_id} eq "UCD9090")
              || ($I2Cdevices[$i]{i2c_part_id} eq "UCD90120A")))
    {
        push @{$ucdI2cIndex{"n${node}p${position}"}} , $i;
    }
}

my $i2c_host_file = open_mrw_file($mrwdir, "${sysname}-host-i2c.xml");
my $i2cHost = XMLin($i2c_host_file);

my @I2CHotPlug_Host;
foreach my $i (@{$i2cHost->{'host-i2c-connection'}})
{
    my $instancePath = $i->{'slave-device'}->{'instance-path'};

    if( index($instancePath,'MAX5961') != -1 ||
        index($instancePath,'PCA9551') != -1 )
    {
        push @I2CHotPlug_Host, {
             'i2c_slave_path'=>$i->{'slave-device'}->{'instance-path'},
             'i2c_proc_node'=>$i->{'processor'}->{'target'}->{'node'},
             'i2c_proc_pos'=>$i->{'processor'}->{'target'}->{'position'}};
    }
}

# Generate @STargets array from the @Targets array to have the order as shown
# belows. The rest of the codes assume that this order is in place
#
#   pu
#   ex  (one or more EX of pu before it)
#   eq  (one or more EQ of pu before it)
#   core (one or more CORE of pu before it)
#   mcbist (one or more MCBIST of pu before it)
#   mcs (one or more MCS of pu before it)
#   mca (one or more MCA of pu before it)
#   pec (one or more PEC of pu before it)
#   phb (one or more PHB of pu before it)
#   obus (one or more OBUS of pu before it)
#   xbus (one or more XBUS of pu before it)
#   ppe (one or more PPE of pu before it)
#   perv (one or more PERV of pu before it)
#   capp (one or more CAPP of pu before it)
#   sbe (one or more SBE of pu before it)
#   (Repeat for remaining pu)
#   memb
#   mba (to for membuf before it)
#   L4
#   (Repeat for remaining membuf)

# Sort the target array based on Target Type,Node,Position and Chip-Unit.
my @SortedTargets = sort byTargetTypeNodePosChipunit @Targets;
my $Type = $SortedTargets[0][NAME_FIELD];
my $ordinal_ID = 0;

# Increment the Ordinal ID in sequential order for same family Type.
for my $i ( 0 .. $#SortedTargets )
{
    if($SortedTargets[$i][NAME_FIELD] ne $Type)
    {
       $ordinal_ID = 0;
    }
    $SortedTargets[$i] [ORDINAL_FIELD] = $ordinal_ID;
    $Type = $SortedTargets[$i][NAME_FIELD];
    $ordinal_ID += 1;
}

my @fields;
my @STargets;
for my $i ( 0 .. $#SortedTargets )
{
    if ($SortedTargets[$i][NAME_FIELD] eq "pu")
    {
        for my $k ( 0 .. PLUG_POS )
        {
            $fields[$k] = $SortedTargets[$i][$k];
        }
        push @STargets, [ @fields ];

        my $node = $SortedTargets[$i][NODE_FIELD];
        my $position = $SortedTargets[$i][POS_FIELD];

        my @targetOrder = ("eq","ex","core","mcbist","mcs","mca","pec",
                "phb","obus","xbus","ppe","perv","capp","sbe");
        for my $m (0 .. $#targetOrder)
        {
            for my $j ( 0 ..$#SortedTargets)
            {
                if(($SortedTargets[$j][NAME_FIELD] eq $targetOrder[$m]) &&
                   ($SortedTargets[$j][NODE_FIELD] eq $node) &&
                   ($SortedTargets[$j][POS_FIELD] eq $position))
                {
                    for my $n ( 0 .. PLUG_POS )
                    {
                        $fields[$n] = $SortedTargets[$j][$n];
                    }
                    push @STargets, [@fields];
                }
            }
        }
    }
}

for my $i ( 0 .. $#SortedTargets )
{
    if ($SortedTargets[$i][NAME_FIELD] eq "memb")
    {
        for my $k ( 0 .. PLUG_POS )
        {
           $fields[$k] = $SortedTargets[$i][$k];
        }
        push @STargets, [ @fields ];

        my $node = $SortedTargets[$i][NODE_FIELD];
        my $position = $SortedTargets[$i][POS_FIELD];

        my @targetOrder = ("mba","L4");
        for my $m (0 .. $#targetOrder)
        {
            for my $j ( 0 ..$#SortedTargets)
            {
                if(($SortedTargets[$j][NAME_FIELD] eq $targetOrder[$m]) &&
                   ($SortedTargets[$j][NODE_FIELD] eq $node) &&
                   ($SortedTargets[$j][POS_FIELD] eq $position))
                {
                    for my $n ( 0 .. PLUG_POS )
                    {
                        $fields[$n] = $SortedTargets[$j][$n];
                    }
                    push @STargets, [@fields ];
                }
            }
        }
    }
}

# Finally, generate the xml file.
print "<!-- Source path(s) = $mrwdir -->\n";


print "<attributes>\n";

# First, generate system target (always sys0)
my $sys = 0;
generate_sys();

my $node = 0;
my @mprocs;
my $altMproc = 0;
my $fru_id = 0;
my @fru_paths;
my $hasProc = 0;
my $hash_ax_buses;
my $axBusesHuidInit = 0;

my $tpmOrdinalId=0;
my $ucdOrdinalId=0;
for (my $curnode = 0; $curnode <= $MAXNODE; $curnode++)
{

$node = $curnode;

my @Mfsis;
my %Pus;

# find master proc of this node
for my $i ( 0 .. $#Fsis )
{
    my $nodeId = lc($Fsis[$i][FSI_TARGET_FIELD]);
    $nodeId =~ s/.*n(.*):.*$/$1/;

    if ($nodeId eq $node)
    {
        # Keep track of MSFI connections
        push @Mfsis, $Fsis[$i][FSI_TARGET_FIELD]
            if $Fsis[$i][FSI_UNIT_ID_FIELD] =~ /mfsi/i;

        # Keep track of the of pu's, too.
        $Pus{$Fsis[$i][FSI_INSTANCE_FIELD]} =
            "n$Fsis[$i][FSI_MASTERNODE_FIELD]:p$Fsis[$i][FSI_MASTERPOS_FIELD]"
            if $Fsis[$i][FSI_MASTER_TYPE_FIELD] =~ /pu/;

        # Check for fsp master, if so - we have a master proc.
        if ((lc($Fsis[$i][FSI_TYPE_FIELD]) eq "fsp master") &&
            (($Fsis[$i][FSI_TARGET_TYPE_FIELD]) eq "pu"))
        {
            push @mprocs, $Fsis[$i][FSI_TARGET_FIELD];
            #print "Mproc = $Fsis[$i][FSI_TARGET_FIELD]\n";
        }
    }
}

# fsp-less systems won't have an fsp master, so we use an augmented algorithm.
if ($#mprocs < 0)
{
    # If there are no FSPs, no mfsi links and one pu, this is the master proc
    if ((!$haveFSPs) && ($#Mfsis < 0) && (keys %Pus == 1))
    {
        push @mprocs, values %Pus;
    }
}

# Second, generate system node

generate_system_node();

# Third, generate the FSP chip(s)
foreach my $fsp ( keys %FSPs )
{
    if( $FSPs{$fsp}{node} eq $node )
    {
        my $fspChipHashRef = (\%FSPs)->{$fsp};
        do_plugin('fsp_chip', $fspChipHashRef);
    }
}

# Node has no master processor, maybe it is just a control node?
if ($#mprocs < 0)
{
    next;
}

#preCalculate HUID for A-Bus
if($axBusesHuidInit == 0)
{
    $axBusesHuidInit = 1;
    for (my $my_curnode = 0; $my_curnode <= $MAXNODE; $my_curnode++)
    {
        for (my $do_core = 0, my $i = 0; $i <= $#STargets; $i++)
        {
            if ($STargets[$i][NODE_FIELD] != $my_curnode)
            {
                next;
            }
            if ($STargets[$i][NAME_FIELD] eq "mcs")
            {
                my $proc = $STargets[$i][POS_FIELD];
                if (($STargets[$i+1][NAME_FIELD] eq "pu") ||
                        ($STargets[$i+1][NAME_FIELD] eq "memb"))
                {
                    preCalculateAxBusesHUIDs($my_curnode, $proc, "A");
                }
            }
        }
    }
}

# Fourth, generate the proc, occ, ex-chiplet, mcs-chiplet
# unit-tp (if on fsp), pcie bus and A/X-bus.
my $ex_count = 0;
my $ex_core_count = 0;
my $eq_count = 0;
my $mcbist_count = 0;
my $mcs_count = 0;
my $mca_count = 0;
my $pec_count = 0;
my $phb_count = 0;
my $obus_count = 0;
my $xbus_count = 0;
my $ppe_count = 0;
my $perv_count = 0;
my $capp_count = 0;
my $sbe_count = 0;
my $proc_ordinal_id =0;
#my $fru_id = 0;
#my @fru_paths;
my $hwTopology =0;

# A hash mapping an affinity path to a FAPI_POS
my %fapiPosH;

for (my $do_core = 0, my $i = 0; $i <= $#STargets; $i++)
{
    if ($STargets[$i][NODE_FIELD] != $node)
    {
        next;
    }

    my $ipath = $STargets[$i][PATH_FIELD];
    if ($STargets[$i][NAME_FIELD] eq "pu")
    {
        my $fru_found = 0;
        my $fru_path = $STargets[$i][FRU_PATH];
        my $proc = $STargets[$i][POS_FIELD];
        $proc_ordinal_id = $STargets[$i][ORDINAL_FIELD];

        use constant FRU_PATHS => 0;
        use constant FRU_ID => 1;

        $hwTopology = $STargets[$i][NODE_FIELD] << 12;
        $fru_path  =~ m/.*-([0-9]*)$/;
        $hwTopology |= $1 <<8;
        $ipath =~ m/.*-([0-9]*)$/;
        $hwTopology |= $1 <<4;
        my $lognode;
        my $logid;
        for (my $j = 0; $j <= $#chipIDs; $j++)
        {
            if ($chipIDs[$j][CHIP_ID_PATH] eq $ipath)
            {
                $lognode = $chipIDs[$j][CHIP_ID_NODE];
                $logid = $chipIDs[$j][CHIP_ID_POS];
                last;
            }
        }

        if($#fru_paths < 0)
        {
            $fru_id = 0;
            push @fru_paths, [ $fru_path, $fru_id ];
        }
        else
        {
            for (my $k = 0; $k <= $#fru_paths; $k++)
            {
                if ( $fru_paths[$k][FRU_PATHS] eq $fru_path)
                {
                    $fru_id =  $fru_paths[$k][FRU_ID];
                    $fru_found = 1;
                    last;
                }

            }
            if ($fru_found == 0)
            {
                $fru_id = $#fru_paths + 1;
                push @fru_paths, [ $fru_path, $fru_id ];
            }
        }

        my @fsi;
        for (my $j = 0; $j <= $#Fsis; $j++)
        {
            if (($Fsis[$j][FSI_TARGET_FIELD] eq "n${node}:p$proc") &&
                ($Fsis[$j][FSI_TARGET_TYPE_FIELD] eq "pu") &&
                (lc($Fsis[$j][FSI_MASTERPOS_FIELD]) eq "0") &&
                (lc($Fsis[$j][FSI_TYPE_FIELD]) eq "hub master") )
            {
                @fsi = @{@Fsis[$j]};
                last;
            }
        }

        my @altfsi;
        for (my $j = 0; $j <= $#Fsis; $j++)
        {
            if (($Fsis[$j][FSI_TARGET_FIELD] eq "n${node}:p$proc") &&
                ($Fsis[$j][FSI_TARGET_TYPE_FIELD] eq "pu") &&
                (lc($Fsis[$j][FSI_MASTERPOS_FIELD]) eq "1") &&
                (lc($Fsis[$j][FSI_TYPE_FIELD]) eq "hub master") )
            {
                @altfsi = @{@Fsis[$j]};
                last;
            }
        }

        my $is_master = 0;
        foreach my $m (@mprocs)
        {
            if ($m eq "n${node}:p$proc")
            {
                $is_master = 1;
            }
        }

        # Uncomment to emit debug trace to STDERR
        # print STDERR "Running generate_proc for $proc\n";
        generate_proc($proc, $is_master, $ipath, $lognode, $logid,
                      $proc_ordinal_id, \@fsi, \@altfsi, $fru_id, $hwTopology,
                      \%fapiPosH,\%voltageRails );

        generate_npu($proc,0,0,$ipath);
        generate_occ($proc, $proc_ordinal_id);
        generate_nx($proc,$proc_ordinal_id,$node);

        # call to do any fsp per-proc targets (ie, occ, psi)
        do_plugin('fsp_proc_targets', $proc, $i, $proc_ordinal_id,
                    $STargets[$i][NODE_FIELD], $STargets[$i][POS_FIELD]);

        if(exists $tpmI2cIndex{"n${node}p${proc}"})
        {
            generate_tpm($proc, $tpmOrdinalId);
            ++$tpmOrdinalId;
        }

        # Generate UCD targets connected to each proc
        generate_ucds($proc);
    }
    elsif ($STargets[$i][NAME_FIELD] eq "ex")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $ex = $STargets[$i][UNIT_FIELD];

        if ($ex_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc EX units -->\n";
        }
        generate_ex($proc, $ex, $STargets[$i][ORDINAL_FIELD], $ipath,
            \%fapiPosH);
        $ex_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "core")
        {
            $ex_count = 0;
        }
    }
    elsif ($STargets[$i][NAME_FIELD] eq "core")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $core = $STargets[$i][UNIT_FIELD];

        if ($ex_core_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc core units -->\n";
        }
        generate_core($proc,$core,$STargets[$i][ORDINAL_FIELD],
                      $STargets[$i][PATH_FIELD],\%fapiPosH);
        $ex_core_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "mcs")
        {
            $ex_core_count = 0;
        }
    }
    elsif ($STargets[$i][NAME_FIELD] eq "eq")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $eq = $STargets[$i][UNIT_FIELD];

        if ($eq_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc EQ units -->\n";
        }
        generate_eq($proc, $eq, $STargets[$i][ORDINAL_FIELD], $ipath,
            \%fapiPosH);
        $eq_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "core")
        {
            $eq_count = 0;
        }

    }
    elsif ($STargets[$i][NAME_FIELD] eq "mcs")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $mcs = $STargets[$i][UNIT_FIELD];
        if ($mcs_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc MCS units -->\n";
        }
        generate_mcs($proc,$mcs, $STargets[$i][ORDINAL_FIELD],
            $ipath,\%fapiPosH);
        $mcs_count++;
        if (($STargets[$i+1][NAME_FIELD] eq "pu") ||
            ($STargets[$i+1][NAME_FIELD] eq "memb"))
        {
            $mcs_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "mca")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $mca = $STargets[$i][UNIT_FIELD];
        if ($mca_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc MCA units -->\n";
        }
        generate_mca($proc,$mca, $STargets[$i][ORDINAL_FIELD], $ipath,
            \%fapiPosH);
        $mca_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $mca_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "mcbist")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $mcbist = $STargets[$i][UNIT_FIELD];
        addFapiPos_for_mcbist($proc,$mcbist,\%fapiPosH);
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "pec")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $pec = $STargets[$i][UNIT_FIELD];
        if ($pec_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc PEC units -->\n";
        }
        generate_pec($proc,$pec,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $pec_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $pec_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "phb")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $phb = $STargets[$i][UNIT_FIELD];
        if ($phb_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc PHB units -->\n";
        }
        generate_phb_chiplet($proc,$phb,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $phb_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $phb_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "obus")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $obus = $STargets[$i][UNIT_FIELD];
        if ($obus_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc OBUS units -->\n";
        }
        generate_obus($proc,$obus,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $obus_count++;
        #function to add all the obus bricks under this obus
        generate_obus_brick($proc,$obus, $ipath);
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $obus_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "xbus")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $xbus = $STargets[$i][UNIT_FIELD];
        if ($xbus_count == 0)
        {
           print "\n<!-- $SYSNAME n${node}p$proc XBUS units -->\n";
        }
        generate_xbus($proc,$xbus,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH, $xbusFfePrecursor );
        $xbus_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
           $xbus_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "ppe")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $ppe = $STargets[$i][UNIT_FIELD];
        if ($ppe_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc PPE units -->\n";
        }
        generate_ppe($proc,$ppe,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $ppe_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu" )
        {
            $ppe_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "perv")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $perv = $STargets[$i][UNIT_FIELD];
        if ($perv_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc PERV units -->\n";
        }
        generate_perv($proc,$perv,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $perv_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $perv_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "capp")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $capp = $STargets[$i][UNIT_FIELD];
        if ($capp_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc CAPP units -->\n";
        }
        generate_capp($proc,$capp,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $capp_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $capp_count = 0;
        }
    }
    elsif ( $STargets[$i][NAME_FIELD] eq "sbe")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $sbe = $STargets[$i][UNIT_FIELD];
        if ($sbe_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc SBE units -->\n";
        }
        generate_sbe($proc,$sbe,$STargets[$i][ORDINAL_FIELD],$ipath,
            \%fapiPosH);
        $sbe_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $sbe_count = 0;
        }
    }
}

# Fifth, generate the Centaur, L4, and MBA

my $memb;
my $membMcs;
my $mba_count = 0;

for my $i ( 0 .. $#STargets )
{
    if ($STargets[$i][NODE_FIELD] != $node)
    {
        next;
    }

    my $ipath = $STargets[$i][PATH_FIELD];
    if ($STargets[$i][NAME_FIELD] eq "memb")
    {
        $memb = $STargets[$i][POS_FIELD];
        my $centaur = "n${node}:p${memb}";
        my $found = 0;
        my $cfsi;
        for my $j ( 0 .. $#Membuses )
        {
            my $mba = $Membuses[$j][CENTAUR_TARGET_FIELD];
            $mba =~ s/(.*):mba.*$/$1/;
            if ($mba eq $centaur)
            {
                $membMcs = $Membuses[$j][MCS_TARGET_FIELD];
                $found = 1;
                last;
            }
        }
        if ($found == 0)
        {
            die "ERROR. Can't locate Centaur from memory bus table\n";
        }

        my @fsi;
        for (my $j = 0; $j <= $#Fsis; $j++)
        {
            if (($Fsis[$j][FSI_TARGET_FIELD] eq "n${node}:p${memb}") &&
                ($Fsis[$j][FSI_TARGET_TYPE_FIELD] eq "memb") &&
                (lc($Fsis[$j][FSI_SLAVE_PORT_FIELD]) eq "fsi_slave0") &&
                (lc($Fsis[$j][FSI_TYPE_FIELD]) eq "cascaded master") )
            {
                @fsi = @{@Fsis[$j]};
                last;
            }
        }

        my @altfsi;
        for (my $j = 0; $j <= $#Fsis; $j++)
        {
            if (($Fsis[$j][FSI_TARGET_FIELD] eq "n${node}:p${memb}") &&
                ($Fsis[$j][FSI_TARGET_TYPE_FIELD] eq "memb") &&
                (lc($Fsis[$j][FSI_SLAVE_PORT_FIELD]) eq "fsi_slave1") &&
                (lc($Fsis[$j][FSI_TYPE_FIELD]) eq "cascaded master") )
            {
                @altfsi = @{@Fsis[$j]};
                last;
            }
        }

        my $relativeCentaurRid = $STargets[$i][PLUG_POS]
            + (CDIMM_RID_NODE_MULTIPLIER * $STargets[$i][NODE_FIELD]);

        generate_centaur( $memb, $membMcs, \@fsi, \@altfsi, $ipath,
                          $STargets[$i][ORDINAL_FIELD],$relativeCentaurRid,
                          $ipath, $dimmVrmUuidHash{"n${node}:p${memb}"},
                          \%fapiPosH);
    }
    elsif ($STargets[$i][NAME_FIELD] eq "mba")
    {
        if ($mba_count == 0)
        {
            print "\n";
            print "<!-- $SYSNAME Centaur MBAs affiliated with membuf$memb -->";
            print "\n";
        }
        my $mba = $STargets[$i][UNIT_FIELD];
        generate_mba( $memb, $membMcs, $mba,
            $STargets[$i][ORDINAL_FIELD], $ipath,\%fapiPosH);
        $mba_count += 1;
        if ($mba_count == 2)
        {
            $mba_count = 0;
            print "\n<!-- $SYSNAME Centaur n${node}p${memb} : end -->\n"
        }
    }
    elsif ($STargets[$i][NAME_FIELD] eq "L4")
    {
        print "\n";
        print "<!-- $SYSNAME Centaur L4 affiliated with membuf$memb -->";
        print "\n";

        my $l4 = $STargets[$i][UNIT_FIELD];
        generate_l4( $memb, $membMcs, $l4, $STargets[$i][ORDINAL_FIELD],
                     $ipath,\%fapiPosH );

        print "\n<!-- $SYSNAME Centaur n${node}p${l4} : end -->\n"
    }
}

# Sixth, generate DIMM targets

generate_is_dimm(\%fapiPosH) if ($isISDIMM);
generate_centaur_dimm(\%fapiPosH) if (!$isISDIMM);

# Now generate MCBIST targets
# Moved here to associate voltage dimms to mcbist targets
for (my $i = 0; $i <= $#STargets; $i++)
{
    if ($STargets[$i][NODE_FIELD] != $node)
    {
        next;
    }

    my $ipath = $STargets[$i][PATH_FIELD];
    if ( $STargets[$i][NAME_FIELD] eq "mcbist")
    {
        my $proc = $STargets[$i][POS_FIELD];
        my $mcbist = $STargets[$i][UNIT_FIELD];
        if ($mcbist_count == 0)
        {
            print "\n<!-- $SYSNAME n${node}p$proc MCBIST units -->\n";
        }
        generate_mcbist($proc,$mcbist,$STargets[$i][ORDINAL_FIELD],
                        $ipath,\%fapiPosH);
        $mcbist_count++;
        if ($STargets[$i+1][NAME_FIELD] eq "pu")
        {
            $mcbist_count = 0;
        }
    }
}

# call to do pnor attributes
do_plugin('all_pnors', $node);

# call to do refclk attributes
do_plugin('all_refclk');
}

print "\n</attributes>\n";

# All done!
#close ($outFH);
exit 0;

##########   Subroutines    ##############

################################################################################
# utility function used to preCalculate the AX Buses HUIDs
################################################################################

sub preCalculateAxBusesHUIDs
{
    my ($my_node, $proc, $type) = @_;

    my ($minbus, $maxbus, $numperchip, $typenum, $type) =
            getBusInfo($type, $CHIPNAME);

    for my $i ( $minbus .. $maxbus )
    {
        my $uidstr = sprintf( "0x%02X%02X%04X",
            ${my_node},
            $typenum,
            $proc*$numperchip + $i);
        my $phys_path =
            "physical:sys-$sys/node-$my_node/proc-$proc/${type}bus-$i";
        $hash_ax_buses->{$phys_path} = $uidstr;
        #print STDOUT "Phys Path = $phys_path, HUID = $uidstr\n";
    }
}

################################################################################
# utility function used to call plugins. if none exists, call is skipped.
################################################################################

sub do_plugin
{
    my $step = shift;
    if (exists($hwsvmrw_plugins{$step}))
    {
        $hwsvmrw_plugins{$step}(@_);
    }
    elsif ($DEBUG && ($build eq "fsp"))
    {
        print STDERR "build is $build but no plugin for $step\n";
    }
}

################################################################################
# Compares two MRW Targets based on the Type,Node,Position & Chip-Unit #
################################################################################

sub byTargetTypeNodePosChipunit ($$)
{
    # Operates on two Targets, based on the following parameters Targets will
    # get sorted,
    # 1.Type of the Target.Ex; pu , ex , mcs ,mba etc.
    # 2.Node of the Target.Node instance number, integer 0,1,2 etc.
    # 3.Position of the Target, integer 0,1,2 etc.
    # 4.ChipUnit of the Target , integer 0,1,2 etc.
    # Note the above order is sequential & comparison is made in the same order.

    #Assume always $lhsInstance < $rhsInstance, will reduce redundant coding.
    my $retVal = -1;

    # Get just the instance path for each supplied memory bus
    my $lhsInstance_Type = $_[0][NAME_FIELD];
    my $rhsInstance_Type = $_[1][NAME_FIELD];

    if($lhsInstance_Type eq $rhsInstance_Type)
    {
       my $lhsInstance_Node = $_[0][NODE_FIELD];
       my $rhsInstance_Node = $_[1][NODE_FIELD];

       if(int($lhsInstance_Node) eq int($rhsInstance_Node))
       {
           my $lhsInstance_Pos = $_[0][POS_FIELD];
           my $rhsInstance_Pos = $_[1][POS_FIELD];

           if(int($lhsInstance_Pos) eq int($rhsInstance_Pos))
           {
               my $lhsInstance_ChipUnit = $_[0][UNIT_FIELD];
               my $rhsInstance_ChipUnit = $_[1][UNIT_FIELD];

               if(int($lhsInstance_ChipUnit) eq int($rhsInstance_ChipUnit))
               {
                   die "ERROR: Duplicate Targets: 2 Targets with same \
                    TYPE: $lhsInstance_Type NODE: $lhsInstance_Node \
                    POSITION: $lhsInstance_Pos \
                    & CHIP-UNIT: $lhsInstance_ChipUnit\n";
               }
               elsif(int($lhsInstance_ChipUnit) > int($rhsInstance_ChipUnit))
               {
                   $retVal = 1;
               }
           }
           elsif(int($lhsInstance_Pos) > int($rhsInstance_Pos))
           {
               $retVal = 1;
           }
         }
         elsif(int($lhsInstance_Node) > int($rhsInstance_Node))
         {
            $retVal = 1;
         }
    }
    elsif($lhsInstance_Type gt $rhsInstance_Type)
    {
        $retVal = 1;
    }
    return $retVal;
}

################################################################################
# Compares two MRW DIMMs based on the Node,Position & DIMM instance #
################################################################################

sub byDimmNodePos($$)
{
    # Operates on two Targets, based on the following parameters Targets will
    # get sorted,
    # 1.Node of the Target.Node instance number, integer 0,1,2 etc.
    # 2.Position of the Target, integer 0,1,2 etc.
    # 3.On two DIMM instance paths, each in the form of:
    #     assembly-0/shilin-0/dimm-X
    #
    # Assumes that "X is always a decimal number, and that every DIMM in the
    # system has a unique value of "X", including for multi-node systems and for
    # systems whose DIMMs are contained on different parts of the system
    # topology
    #
    # Note, in the path example above, the parts leading up to the dimm-X could
    # be arbitrarily deep and have different types/instance values
    #
    # Note the above order is sequential & comparison is made in the same order.

    #Assume always $lhsInstance < $rhsInstance, will reduce redundant coding.
    my $retVal = -1;

    my $lhsInstance_node = $_[0][BUS_NODE_FIELD];
    my $rhsInstance_node = $_[1][BUS_NODE_FIELD];
    if(int($lhsInstance_node) eq int($rhsInstance_node))
    {
         my $lhsInstance_pos = $_[0][BUS_POS_FIELD];
         my $rhsInstance_pos = $_[1][BUS_POS_FIELD];
         if(int($lhsInstance_pos) eq int($rhsInstance_pos))
         {
            # Get just the instance path for each supplied memory bus
            my $lhsInstance = $_[0][DIMM_PATH_FIELD];
            my $rhsInstance = $_[1][DIMM_PATH_FIELD];
            # Replace each with just its DIMM instance value (a string)
            $lhsInstance =~ s/.*-([0-9]*)$/$1/;
            $rhsInstance =~ s/.*-([0-9]*)$/$1/;

            if(int($lhsInstance) eq int($rhsInstance))
            {
                die "ERROR: Duplicate Dimms: 2 Dimms with same TYPE, \
                    NODE: $lhsInstance_node POSITION: $lhsInstance_pos & \
                    PATH FIELD: $lhsInstance\n";
            }
            elsif(int($lhsInstance) > int($rhsInstance))
            {
               $retVal = 1;
            }
         }
         elsif(int($lhsInstance_pos) > int($rhsInstance_pos))
         {
             $retVal = 1;
         }
    }
    elsif(int($lhsInstance_node) > int($rhsInstance_node))
    {
        $retVal = 1;
    }
    return $retVal;
}

################################################################################
# Compares two MRW DIMM instance paths based only on the DIMM instance #
################################################################################

sub byDimmInstancePath ($$)
{
    # Operates on two DIMM instance paths, each in the form of:
    #     assembly-0/shilin-0/dimm-X
    #
    # Assumes that "X is always a decimal number, and that every DIMM in the
    # system has a unique value of "X", including for multi-node systems and for
    # systems whose DIMMs are contained on different parts of the system
    # topology
    #
    # Note, in the path example above, the parts leading up to the dimm-X could
    # be arbitrarily deep and have different types/instance values

    # Get just the instance path for each supplied memory bus
    my $lhsInstance = $_[0][DIMM_PATH_FIELD];
    my $rhsInstance = $_[1][DIMM_PATH_FIELD];

    # Replace each with just its DIMM instance value (a string)
    $lhsInstance =~ s/.*-([0-9]*)$/$1/;
    $rhsInstance =~ s/.*-([0-9]*)$/$1/;

    # Convert each DIMM instance value string to int, and return comparison
    return int($lhsInstance) <=> int($rhsInstance);
}

################################################################################
# Compares two arrays based on chip node and position
################################################################################
sub byNodePos($$)
{
    my $retVal = -1;

    my $lhsInstance_node = $_[0][CHIP_NODE_INDEX];
    my $rhsInstance_node = $_[1][CHIP_NODE_INDEX];
    if(int($lhsInstance_node) eq int($rhsInstance_node))
    {
         my $lhsInstance_pos = $_[0][CHIP_POS_INDEX];
         my $rhsInstance_pos = $_[1][CHIP_POS_INDEX];
         if(int($lhsInstance_pos) eq int($rhsInstance_pos))
         {
                die "ERROR: Duplicate chip positions: 2 chip with same
                    node and position, \
                    NODE: $lhsInstance_node POSITION: $lhsInstance_pos\n";
         }
         elsif(int($lhsInstance_pos) > int($rhsInstance_pos))
         {
             $retVal = 1;
         }
    }
    elsif(int($lhsInstance_node) > int($rhsInstance_node))
    {
        $retVal = 1;
    }
    return $retVal;
}

sub addProcVrdIds
{
    my($node, $proc) = @_;
    my %o_vrd_uuids;
    my $procInstance = "n0:p$proc";
    my %vrd_ids =
    (
        "VCS"  => -1,
        "VDN"  => -1,
        "VIO"  => -1,
        "VDDR" => -1,
        "VDD"  => -1,
    );


#    print "\n<!-- addProcVrdIds for proc $proc" .
#        "--n".$node."p".$proc." -->\n";



    foreach my $procVrdType ( keys %{$procVrdUuidHash{$procInstance}} )
    {
        my $key = $procVrdUuidHash{$procInstance}{$procVrdType}{VRD_PROC_UUID};
        my $domain_id = $vrdHash{$key}{VRD_PROC_DOMAIN_ID};

        if( ($vrd_ids{ $procVrdType } != $domain_id) &&
            ($vrd_ids{ $procVrdType } == -1) )
        {
            print "\n"
            . "    <attribute>\n"
            . "        <id>NEST_$procVrdType" . "_ID</id>\n"
            . "        <default>$domain_id</default>\n"
            . "    </attribute>";
            $vrd_ids{ $procVrdType } = $domain_id;
            $o_vrd_uuids{ $procVrdType } = $key;
        }
        elsif (!exists($vrd_ids{$procVrdType}))
        {
            die "Unkown vrd type $procVrdType for proc $proc\n";
        }
        elsif ($vrd_ids{ $procVrdType } != $domain_id)
        {
            die "PROC $proc: $procVrdType"."_ID has a different DomainID then expected".
            " (found " . $domain_id . ", expected ". $vrd_ids{ $procVrdType } . ")\n";
        }
    }
    print "\n";
    #   print "\n<!-- end addProcVrdIds for proc $proc" .
    #       "--n".$node."p".$proc." -->\n";

    return %o_vrd_uuids;
}


sub addVoltageDomainIDs
{
  my ($node, $proc, $mcbist) = @_;

  # grab dimms under this mcbist (filled in by generate_is_dimm)
  my @dimms = @{ $mcbist_dimms{ $node . $proc . "_" . $mcbist } };

  my %o_vrm_uuids;
  my %vrm_ids =
  (
    "AVDD" => -1,
    "VDD"  => -1,
    "VCS"  => -1,
    "VPP"  => -1,
    "VDDR" => -1,
  );

  #print "\n<!-- addVoltageDomainIDs for mcbist $mcbist" .
            "--  n".$node."p".$proc." -->\n";
  foreach my $dimm (@dimms)
  {
#     print "\n<!-- DIMM $dimm -->";

    foreach my $vrmType ( keys %{$dimmVrmUuidHash{$dimm}} )
    {
      my $key = $dimmVrmUuidHash{$dimm}{$vrmType}{VRM_UUID};
      my $domain_id = $vrmHash{$key}{VRM_DOMAIN_ID};
      #      print "\n<!-- Key $key: Domain $domain_id -->\n";
      if ( ($vrm_ids{ $vrmType } != $domain_id) &&
           ($vrm_ids{ $vrmType } == -1) )
      {
        print "\n"
            . "    <attribute>\n"
            . "        <id>$vrmType" . "_ID</id>\n"
            . "        <default>$domain_id</default>\n"
            . "    </attribute>";
        $vrm_ids{ $vrmType } = $domain_id;
        $o_vrm_uuids{ $vrmType } = $key;
      }
      elsif (!exists($vrm_ids{$vrmType}))
      {
        die "Unknown vrmType $vrmType for dimm $dimm\n";
      }
      elsif ($vrm_ids{ $vrmType } != $domain_id)
      {
        # MCBIST can only have one unique domainID per domain type
        die "DIMM $dimm: $vrmType"."_ID has a different DomainID then expected".
         " (found " . $domain_id . ", expected ". $vrm_ids{ $vrmType } . ")\n";
      }
    }
  }

  ## Add in the domain for VDDR for this proc (on ZZ proc based)
  my $procInstance = "n0:p$proc";
  my $key = $mcBistVrmUuidHash{$procInstance}{"VDDR"}{VRM_UUID};
  my $domain_id = $vrmHash{$key}{VRM_DOMAIN_ID};
  $o_vrm_uuids{ "VDDR" } = $key;
  print "\n"
            . "    <attribute>\n"
            . "        <id>VDDR_ID</id>\n"
            . "        <default>$domain_id</default>\n"
            . "    </attribute>";

  return %o_vrm_uuids;
}

sub generate_sys
{
    my $plat = 0;

    if ($build eq "fsp")
    {
        $plat = 2;
    }
    elsif ($build eq "hb")
    {
        $plat = 1;
    }

    print "
<!-- $SYSNAME System with new values-->

<targetInstance>
    <id>sys$sys</id>
    <type>sys-sys-power9</type>
    <attribute>
        <id>FAPI_NAME</id>
        <default>k0</default>
    </attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:sys-$sys</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>0</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:sys-$sys</default>
    </compileAttribute>
    <attribute>
        <id>EXECUTION_PLATFORM</id>
        <default>$plat</default>
    </attribute>\n";

    my $mss_mrw_supported_freq = $reqPol->{'mss_mrw_supported_freq'};
    print "    <attribute>
      <id>MSS_MRW_SUPPORTED_FREQ</id>
      <default> $mss_mrw_supported_freq </default>
    </attribute>\n";

    print "    <!-- System Attributes from MRW -->\n";
    addSysAttrs();

    print "    <!-- End System Attributes from MRW -->";

    # If we don't have any FSPs (open-power) then we don't need any SP_FUNCTIONS
    my $HaveSPFunctions = $haveFSPs ? 1 : 0;
    print "
    <attribute>
        <id>SP_FUNCTIONS</id>
        <default>
            <field><id>baseServices</id><value>$HaveSPFunctions</value></field>
            <field><id>fsiSlaveInit</id><value>$HaveSPFunctions</value></field>
            <field><id>mailboxEnabled</id><value>$HaveSPFunctions</value></field>
            <field><id>fsiMasterInit</id><value>$HaveSPFunctions</value></field>
            <field><id>hardwareChangeDetection</id><value>$HaveSPFunctions</value></field>
            <field><id>powerLineDisturbance</id><value>$HaveSPFunctions</value></field>
            <field><id>reserved</id><value>0</value></field>
        </default>
    </attribute>
    <attribute>
        <id>HB_SETTINGS</id>
        <default>
            <field><id>traceContinuous</id><value>0</value></field>
            <field><id>traceScanDebug</id><value>0</value></field>
            <field><id>traceFapiDebug</id><value>0</value></field>
            <field><id>reserved</id><value>0</value></field>
        </default>
    </attribute>
    <attribute>
        <id>PAYLOAD_KIND</id>\n";

    # If we have FSPs, we setup the default as PHYP, and the FSP
    # will set this up correctly. We can't just add the SAPPHIRE as a
    # default because the FSP assumes the PAYLOAD_BASE comes via
    # attribute_types.xml
    if ($haveFSPs)
    {
        print "        <default>PHYP</default>\n";
    }
    else
    {
        print "
        <default>SAPPHIRE</default>
    </attribute>
    <attribute>
        <id>PAYLOAD_BASE</id>
        <default>0</default>
    </attribute>
    <attribute>
        <id>PAYLOAD_ENTRY</id>
        <default>0x10</default>\n";
    }
    print "    </attribute>";

    generate_max_config();

    # HDAT drawer number (physical node) to
    # HostBoot Instance number (logical node) map
    # Index is the hdat drawer number, value is the HB instance number
    # Only the max drawer system needs to be represented.
    if ($sysname =~ /brazos/)
    {
        print "
    <!-- correlate HDAT drawer number to Hostboot Instance number -->
    <attribute><id>FABRIC_TO_PHYSICAL_NODE_MAP</id>
        <default>0,1,2,3,255,255,255,255</default>
    </attribute>
";
    }
    else # single drawer
    {
        print "
    <!-- correlate HDAT drawer number to Hostboot Instance number -->
    <attribute><id>FABRIC_TO_PHYSICAL_NODE_MAP</id>
        <default>0,255,255,255,255,255,255,255</default>
    </attribute>
";
    }

    if( $haveFSPs == 0 )
    {
        generate_apss_adc_config()
    }

    # call to do any fsp per-sys attributes
    do_plugin('fsp_sys', $sys, $sysname, 0);

print "
</targetInstance>

";
}

sub generate_max_config
{
    my $maxMcs_Per_System = 0;
    my $maxChiplets_Per_Proc = 0;
    my $maxProcChip_Per_Node =0;
    my $maxEx_Per_Proc =0;
    my $maxDimm_Per_MbaPort =0;
    my $maxMbaPort_Per_Mba =0;
    my $maxMba_Per_MemBuf =0;

    # MBA Ports Per MBA is 2 in P8 and is hard coded here
    use constant MBA_PORTS_PER_MBA => 2;

    # MAX Chiplets Per Proc is 32 and is hard coded here
    use constant CHIPLETS_PER_PROC => 32;

    # MAX Mba Per MemBuf is 2 and is hard coded here
    # PNEW_TODO to change if P9 different
    use constant MAX_MBA_PER_MEMBUF => 2;

    # MAX Dimms Per MBA PORT is 2 and is hard coded here
    # PNEW_TODO to change if P9 different
    use constant MAX_DIMMS_PER_MBAPORT => 2;

    for (my $i = 0; $i < $#STargets; $i++)
    {
        if ($STargets[$i][NAME_FIELD] eq "pu")
        {
            if ($node == 0)
            {
                $maxProcChip_Per_Node += 1;
            }
        }
        elsif ($STargets[$i][NAME_FIELD] eq "ex")
        {
            my $proc = $STargets[$i][POS_FIELD];
            if (($proc == 0) && ($node == 0))
            {
                $maxEx_Per_Proc += 1;
            }
        }
        elsif ($STargets[$i][NAME_FIELD] eq "mcs")
        {
            $maxMcs_Per_System += 1;
        }
    }

    # loading the hard coded value
    $maxMbaPort_Per_Mba = MBA_PORTS_PER_MBA;

    # loading the hard coded value
    $maxChiplets_Per_Proc = CHIPLETS_PER_PROC;

    # loading the hard coded value
    $maxMba_Per_MemBuf = MAX_MBA_PER_MEMBUF;

    # loading the hard coded value
    $maxDimm_Per_MbaPort = MAX_DIMMS_PER_MBAPORT;

    print "
    <attribute>
        <id>MAX_PROC_CHIPS_PER_NODE</id>
        <default>$maxProcChip_Per_Node</default>
    </attribute>
    <attribute>
        <id>MAX_EXS_PER_PROC_CHIP</id>
        <default>$maxEx_Per_Proc</default>
    </attribute>
    <attribute>
        <id>MAX_CHIPLETS_PER_PROC</id>
        <default>$maxChiplets_Per_Proc</default>
    </attribute>
    <attribute>
        <id>MAX_MCS_PER_SYSTEM</id>
        <default>$maxMcs_Per_System</default>
    </attribute>";
}

sub generate_apss_adc_config
{
    my $uc_sysname = uc $sysname;
    my $apss_xml_file = open_mrw_file($::mrwdir,"${uc_sysname}_APSS.xml");
    my $xmlData = parse_xml_file($apss_xml_file,forcearray=>['id']);
    my $adc_cfg = $xmlData->{part}
                          ->{"internal-attributes"}
                          ->{configurations}
                          ->{configuration}
                          ->{'configuration-entries'}
                          ->{'configuration-entry'};

    my @channel_id;
    my $gain = {};
    my $func_id = {};
    my $offset = {};
    my $gnd = {};

    my @gpio_mode;
    my @gpio_pin;
    my $gpio_fid = {};

    foreach my $i (@{$adc_cfg})
    {
        if( $i->{'unit-type'} eq 'adc-unit' )
        {
            foreach my $id (@{$i->{'id'}})
            {
                if( $id eq "CHANNEL")
                {
                    $channel_id[$i->{value}] = $i->{'unit-id'};
                }
                if( $id eq "GND")
                {
                    if(ref($i->{value}) ne "HASH")
                    {
                        $gnd->{$i->{'unit-id'}} = $i->{value};
                    }
                    else
                    {
                        $gnd->{$i->{'unit-id'}} = 0;
                    }
                }
                if( $id eq "GAIN")
                {
                    $gain->{$i->{'unit-id'}} = $i->{value} * 1000;
                }
                if( $id eq "OFFSET")
                {
                    if(ref($i->{value}) ne "HASH")
                    {
                        $offset->{$i->{'unit-id'}} = $i->{value} * 1000;
                    }
                    else
                    {
                        $offset->{$i->{'unit-id'}} = 0;
                    }
                }
                if( $id eq "FUNCTION_ID" )
                {
                    if(ref($i->{value}) ne "HASH")
                    {
                        $func_id->{$i->{'unit-id'}} = $i->{value};
                    }
                    else
                    {
                        $func_id->{$i->{'unit-id'}} = 0;
                    }
                }
            }
        }
        if( $i->{'unit-type'} eq 'gpio-global' )
        {
            foreach my $id (@{$i->{'id'}})
            {
                if( $id eq "GPIO_P0_MODE")
                {
                    $gpio_mode[0] = $i->{value};
                }
                if( $id eq "GPIO_P1_MODE")
                {
                    $gpio_mode[1] = $i->{value};
                }
            }
        }
        if( $i->{'unit-type'} eq 'gpio-unit' )
        {
            my $unit_id = $i->{'unit-id'};
            if($unit_id =~ /^GPIO/)
            {
                foreach my $id (@{$i->{'id'}})
                {
                    if( $id eq "FUNCTION_ID")
                    {
                        $gpio_fid->{$unit_id} = $i->{value};
                    }
                }
            }
        }
    }

    my @func_id_a;
    my @gain_a;
    my @offset_a;
    my @gnd_a;

    foreach my $i (@channel_id)
    {
        push @func_id_a, $func_id->{$i};
        push @gain_a, $gain->{$i};
        push @offset_a, $offset->{$i};
        push @gnd_a, $gnd->{$i};
    }

    foreach my $i (0..15)
    {
        my $unit = "GPIO[$i]";
        if($gpio_fid->{$unit} ne "#N/A")
        {
            $gpio_pin[$i] = $gpio_fid->{$unit};
        }
        else
        {
            $gpio_pin[$i] = 0;
        }
    }

    print "
    <attribute>
        <id>ADC_CHANNEL_FUNC_IDS</id>
        <default> ";

    print join(',',@func_id_a);

    print " </default>
    </attribute>
    <attribute>
        <id>ADC_CHANNEL_GNDS</id>
        <default> ";

    print join(',',@gnd_a);

    print " </default>
    </attribute>
    <attribute>
        <id>ADC_CHANNEL_GAINS</id>
        <default>\n            ";

    print join(",\n            ",@gain_a);

    print "\n        </default>
    </attribute>
    <attribute>
        <id>ADC_CHANNEL_OFFSETS</id>
        <default> ";

    print join(',',@offset_a);

    print " </default>
    </attribute>
    <attribute>
        <id>APSS_GPIO_PORT_MODES</id>
        <default> ";

    print join(',',@gpio_mode);

    print " </default>
    </attribute>
    <attribute>
        <id>APSS_GPIO_PORT_PINS</id>
        <default> ";

    print join(',',@gpio_pin);

    print " </default>
    </attribute>\n";
}

my $computeNodeInit = 0;
my %computeNodeList = ();
sub generate_compute_node_ipath
{
    my $location_codes_file = open_mrw_file($::mrwdir,
                                            "${sysname}-location-codes.xml");
    my $nodeTargets = parse_xml_file($location_codes_file);

    #get the node (compute) ipath details
    foreach my $Target (@{$nodeTargets->{'location-code-entry'}})
    {
        if($Target->{'assembly-type'} eq "compute")
        {
            my $ipath = $Target->{'instance-path'};
            my $assembly = $Target->{'assembly-type'};
            my $position = $Target->{position};

            $computeNodeList{$position} = {
                'position'     => $position,
                'assembly'     => $assembly,
                'instancePath' => $ipath,
            }
        }
    }
}

sub generate_system_node
{
    # Get the node ipath info
    if ($computeNodeInit == 0)
    {
        generate_compute_node_ipath;
        $computeNodeInit = 1;
    }

    # Brazos node4 is the fsp node and we'll let the fsp
    # MRW parser handle that.
    if( !( ($sysname =~ /brazos/) && ($node == $MAXNODE) ) )
    {
        my $fapi_name = "NA"; # node not FAPI target

        print "
<!-- $SYSNAME System node $node -->

<targetInstance>
    <id>sys${sys}node${node}</id>
    <type>enc-node-power9</type>
    <attribute><id>HUID</id><default>0x0${node}020000</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:sys-$sys/node-$node</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$node</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$computeNodeList{$node}->{'instancePath'}</default>
    </compileAttribute>";

    print "    <!-- Node Attributes from MRW -->\n";
    addNodeAttrs();

        # add fsp extensions
        do_plugin('fsp_node_add_extensions', $node);
        print "
</targetInstance>
";
    }
    else
    {
        # create fsp control node
        do_plugin('fsp_control_node', $node);
    }

    # call to do any fsp per-system_node targets
    do_plugin('fsp_system_node_targets', $node);
}

sub calcAndAddFapiPos
{
    my ($type,$affinityPath,
        $relativePos,$fapiPosHr,$parentFapiPosOverride, $noprint) = @_;

    my $fapiPos = 0xFF;

    # Uncomment to emit debug trace to STDERR
    #print STDERR "$affinityPath,";

    state %typeToLimit;
    if(not %typeToLimit)
    {
        # FAPI types with FAPI_POS attribute
        # none: NA
        # system: NA
        $typeToLimit{"isdimm"} = ARCH_LIMIT_DIMM_PER_MCA;
        $typeToLimit{"cdimm"}  = ARCH_LIMIT_DIMM_PER_MBA;
        $typeToLimit{"proc"}   = ARCH_LIMIT_PROC_PER_FABRIC_GROUP;
        $typeToLimit{"membuf"} = ARCH_LIMIT_MEMBUF_PER_DMI;
        $typeToLimit{"ex"}     = ARCH_LIMIT_EX_PER_EQ;
        $typeToLimit{"mba"}    = ARCH_LIMIT_MBA_PER_MEMBUF;
        $typeToLimit{"mcbist"} = ARCH_LIMIT_MCBIST_PER_PROC;
        $typeToLimit{"mcs"}    = ARCH_LIMIT_MCS_PER_MCBIST;
        $typeToLimit{"xbus"}   = ARCH_LIMIT_XBUS_PER_PROC;
        $typeToLimit{"abus"}   = ARCH_LIMIT_ABUS_PER_PROC;
        $typeToLimit{"l4"}     = ARCH_LIMIT_L4_PER_MEMBUF;
        $typeToLimit{"core"}   = ARCH_LIMIT_CORE_PER_EX;
        $typeToLimit{"eq"}     = ARCH_LIMIT_EQ_PER_PROC;
        $typeToLimit{"mca"}    = ARCH_LIMIT_MCA_PER_MCS;
        $typeToLimit{"mi"}     = ARCH_LIMIT_MI_PER_PROC;
        $typeToLimit{"capp"}   = ARCH_LIMIT_CAPP_PER_PROC;
        $typeToLimit{"dmi"}    = ARCH_LIMIT_DMI_PER_MI;
        $typeToLimit{"obus"}   = ARCH_LIMIT_OBUS_PER_PROC;
        $typeToLimit{"sbe"}    = ARCH_LIMIT_SBE_PER_PROC;
        $typeToLimit{"ppe"}    = ARCH_LIMIT_PPE_PER_PROC;
        $typeToLimit{"perv"}   = ARCH_LIMIT_PERV_PER_PROC;
        $typeToLimit{"pec"}    = ARCH_LIMIT_PEC_PER_PROC;
        $typeToLimit{"phb"}    = ARCH_LIMIT_PHB_PER_PEC;
    }

    my $parentFapiPos = 0;
    if(defined $parentFapiPosOverride)
    {
        $parentFapiPos = $parentFapiPosOverride;
    }
    else
    {
        my $parentAffinityPath = $affinityPath;
        # Strip off the trailing affinity path component to get the
        # affinity path of the parent.  For example,
        # affinity:sys-0/proc-0/eq-0 becomes affinity:sys-0/proc-0
        $parentAffinityPath =~ s/\/[a-zA-Z]+-[0-9]+$//;

        if(!exists $fapiPosHr->{$parentAffinityPath} )
        {
            die "No record of affinity path $parentAffinityPath";
        }
        $parentFapiPos = $fapiPosHr->{$parentAffinityPath};
    }

    if(exists $typeToLimit{$type})
    {
        # Compute this target's FAPI_POS value.  We first take the parent's
        # FAPI_POS and multiply by the max number of targets of this type that
        # the parent's type can have. This yields the lower bound of this
        # target's FAPI_POS.  Then we add in the relative position of this
        # target with respect to the parent.  Typically this is done by passing
        # in the chip unit, in which case (such as for cores) it can be much
        # greater than the architecture limit ratio (there can be cores with
        # chip units of 0..23, but only 2 cores per ex), so to normalize we
        # have to take the value mod the architecture limit.  Note that this
        # scheme only holds up because every parent also had the same type of
        # calculation to compute its own FAPI_POS.
        $fapiPos = ($parentFapiPos
            * $typeToLimit{$type}) + ($relativePos % $typeToLimit{$type});

        $fapiPosHr->{$affinityPath} = $fapiPos;

        # Uncomment to emit debug trace to STDERR
        #print STDERR "$fapiPos\n";

        # Indented oddly to get the output XML to line up in the final output
        print "
   <attribute>
       <id>FAPI_POS</id>
       <default>$fapiPos</default>
   </attribute>" unless ($noprint);

    }
    else
    {
        die "Invalid type of $type specified";
    }

    return $fapiPos;
}

sub generate_proc
{
    my ($proc, $is_master, $ipath, $lognode, $logid, $ordinalId,
        $fsiA, $altfsiA,
        $fruid, $hwTopology, $fapiPosHr, $voltageRails) = @_;

    my @fsi = @{$fsiA};
    my @altfsi = @{$altfsiA};
    our %nestRails = %{$voltageRails};
    my $uidstr = sprintf("0x%02X05%04X",${node},${proc});
    my $vpdnum = ${proc};
    my $position = ${proc};
    my $scomFspApath = $devpath->{chip}->{$ipath}->{'scom-path-a'};
    my $scanFspApath = $devpath->{chip}->{$ipath}->{'scan-path-a'};
    my $scomFspAsize = length($scomFspApath) + 1;
    my $scanFspAsize = length($scanFspApath) + 1;
    my $scomFspBpath = "";
    if (ref($devpath->{chip}->{$ipath}->{'scom-path-b'}) ne "HASH")
    {
        $scomFspBpath = $devpath->{chip}->{$ipath}->{'scom-path-b'};
    }
    my $scanFspBpath = "";
    if (ref($devpath->{chip}->{$ipath}->{'scan-path-b'}) ne "HASH")
    {
        $scanFspBpath = $devpath->{chip}->{$ipath}->{'scan-path-b'};
    }
    my $scomFspBsize = length($scomFspBpath) + 1;
    my $scanFspBsize = length($scanFspBpath) + 1;
    my $mboxFspApath = "";
    my $mboxFspAsize = 0;
    my $mboxFspBpath = "";
    my $mboxFspBsize = 0;
    if (exists $devpath->{chip}->{$ipath}->{'mailbox-path-a'})
    {
        $mboxFspApath = $devpath->{chip}->{$ipath}->{'mailbox-path-a'};
        $mboxFspAsize = length($mboxFspApath) + 1;
    }
    if (exists $devpath->{chip}->{$ipath}->{'mailbox-path-b'})
    {
        $mboxFspBpath = $devpath->{chip}->{$ipath}->{'mailbox-path-b'};
        $mboxFspBsize = length($mboxFspBpath) + 1;
    }

    #sbeFifo paths
    my $sbefifoFspApath = "";
    my $sbefifoFspAsize = 0;
    my $sbefifoFspBpath = "";
    my $sbefifoFspBsize = 0;
    if (exists $devpath->{chip}->{$ipath}->{'sbefifo-path-a'})
    {
        $sbefifoFspApath = $devpath->{chip}->{$ipath}->{'sbefifo-path-a'};
        $sbefifoFspAsize = length($sbefifoFspApath) + 1;
    }
    if (exists $devpath->{chip}->{$ipath}->{'sbefifo-path-b'})
    {
        $sbefifoFspBpath = $devpath->{chip}->{$ipath}->{'sbefifo-path-b'};
        $sbefifoFspBsize = length($sbefifoFspBpath) + 1;
    }

    my $psichip = 0;
    my $psilink = 0;
    for my $psi ( 0 .. $#hbPSIs )
    {
        if(($node eq $hbPSIs[$psi][HB_PSI_PROC_NODE_FIELD]) &&
           ($proc eq $hbPSIs[$psi][HB_PSI_PROC_POS_FIELD] ))
        {
            $psichip = $hbPSIs[$psi][HB_PSI_MASTER_CHIP_POSITION_FIELD];
            $psilink = $hbPSIs[$psi][HB_PSI_MASTER_CHIP_UNIT_FIELD];
            last;
        }
    }

    #MURANO=DCM installed, VENICE=SCM
    my $dcm_installed = 0;
    if($CHIPNAME eq "murano")
    {
        $dcm_installed = 1;
    }

    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc";

    my $mruData = get_mruid($ipath);

    # default needed
    my $UseXscom   = $haveFSPs ? 0 : 1;
    my $UseFsiScom = $haveFSPs ? 0 : 1;
    my $UseSbeScom = $haveFSPs ? 1 : 0;
    if($proc ne 0)
    {
        $UseFsiScom = 1;
        $UseSbeScom = 0;
    }

    my $fapi_name = sprintf("pu:k0:n%d:s0:p%02d", $node, $proc);
    print "
    <!-- $SYSNAME n${node}p${proc} processor chip -->

<targetInstance>
    <id>sys${sys}node${node}proc${proc}</id>
    <type>chip-processor-$CHIPNAME</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute><id>POSITION</id><default>${position}</default></attribute>
    <attribute><id>SCOM_SWITCHES</id>
        <default>
            <field><id>useSbeScom</id><value>$UseSbeScom</value></field>
            <field><id>useFsiScom</id><value>$UseFsiScom</value></field>
            <field><id>useXscom</id><value>$UseXscom</value></field>
            <field><id>useInbandScom</id><value>0</value></field>
            <field><id>reserved</id><value>0</value></field>
        </default>
    </attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>FABRIC_GROUP_ID</id>
        <default>$lognode</default>
    </attribute>
    <attribute>
        <id>PROC_EFF_FABRIC_GROUP_ID</id>
        <default>$lognode</default>
    </attribute>
    <attribute>
        <id>FABRIC_CHIP_ID</id>
        <default>$logid</default>
    </attribute>
    <attribute>
        <id>PROC_EFF_FABRIC_CHIP_ID</id>
        <default>$logid</default>
    </attribute>
    <attribute>
        <id>FRU_ID</id>
        <default>$fruid</default>
    </attribute>
    <attribute><id>VPD_REC_NUM</id><default>$vpdnum</default></attribute>
    <attribute><id>PROC_DCM_INSTALLED</id>
        <default>$dcm_installed</default>
    </attribute>";

    calcAndAddFapiPos("proc",$affinityPath,$logid,$fapiPosHr,$lognode);

    #For FSP-based systems, the default will always get overridden by the
    # the FSP code before it is used, based on which FSP is being used as
    # the primary.  Therefore, the default is only relevant in the BMC
    # case where it is required since the value generated here will not
    # be updated before it is used by HB.
    ## Master value ##
    if( $is_master && ($proc == 0) )
    {
        print "
    <attribute>
        <id>PROC_MASTER_TYPE</id>
        <default>ACTING_MASTER</default>
    </attribute>";
    }
    elsif( $is_master )
    {
        print "
    <attribute>
        <id>PROC_MASTER_TYPE</id>
        <default>MASTER_CANDIDATE</default>
    </attribute>";
    }
    else
    {
        print "
    <attribute>
        <id>PROC_MASTER_TYPE</id>
        <default>NOT_MASTER</default>
    </attribute>";
    }

    ## Setup FSI Attributes ##
    if( ($#fsi <= 0) && ($#altfsi <= 0) )
    {
        print "
    <!-- No FSI connection -->
    <attribute>
        <id>FSI_MASTER_TYPE</id>
        <default>NO_MASTER</default>
    </attribute>";
    }
    else
    {
        print "
    <!-- FSI connections -->
    <attribute>
        <id>FSI_MASTER_TYPE</id>
        <default>MFSI</default>
    </attribute>";
    }

    # if a proc is sometimes the master then it
    #  will have flipped ports
    my $flipport = 0;
    if( $is_master )
    {
        $flipport = 1;
    }

    # these values are common for both fsi ports
    print "
    <attribute>
        <id>FSI_SLAVE_CASCADE</id>
        <default>0</default>
    </attribute>
    <attribute>
        <id>FSI_OPTION_FLAGS</id>
        <default>
        <field><id>flipPort</id><value>$flipport</value></field>
        <field><id>reserved</id><value>0</value></field>
        </default>
    </attribute>";

    if( $#fsi <= 0 )
    {
        print "
    <!-- FSI-A is not connected -->
    <attribute>
        <id>FSI_MASTER_CHIP</id>
        <default>physical:sys</default><!-- no A path -->
    </attribute>
    <attribute>
        <id>FSI_MASTER_PORT</id>
        <default>0xFF</default><!-- no A path -->
    </attribute>";
    }
    else
    {
        my $mNode = $fsi[FSI_MASTERNODE_FIELD];
        my $mPos = $fsi[FSI_MASTERPOS_FIELD];
        my $link = $fsi[FSI_LINK_FIELD];
        print "
    <!-- FSI-A is connected via node$mNode:proc$mPos:MFSI-$link -->
    <attribute>
        <id>FSI_MASTER_CHIP</id>
        <default>physical:sys-$sys/node-$mNode/proc-$mPos</default>
    </attribute>
    <attribute>
        <id>FSI_MASTER_PORT</id>
        <default>$link</default>
    </attribute>";
    }

    if( $#altfsi <= 0 )
    {
        print "
    <!-- FSI-B is not connected -->
    <attribute>
        <id>ALTFSI_MASTER_CHIP</id>
        <default>physical:sys</default><!-- no B path -->
    </attribute>
    <attribute>
        <id>ALTFSI_MASTER_PORT</id>
        <default>0xFF</default><!-- no B path -->
    </attribute>\n";
    }
    else
    {
        my $mNode = $altfsi[FSI_MASTERNODE_FIELD];
        my $mPos = $altfsi[FSI_MASTERPOS_FIELD];
        my $link = $altfsi[FSI_LINK_FIELD];
        print "
    <!-- FSI-B is connected via node$mNode:proc$mPos:MFSI-$link -->
    <attribute>
        <id>ALTFSI_MASTER_CHIP</id>
        <default>physical:sys-$sys/node-$mNode/proc-$mPos</default>
    </attribute>
    <attribute>
        <id>ALTFSI_MASTER_PORT</id>
        <default>$link</default>
    </attribute>\n";
    }
    print "    <!-- End FSI connections -->\n";
    ## End FSI ##

    # add EEPROM attributes
    addEepromsProc($sys, $node, $proc);

    #add Hot Plug attributes
    addHotPlug($sys,$node,$proc);

    # add I2C_BUS_SPEED_ARRAY attribute
    addI2cBusSpeedArray($sys, $node, $proc, "pu");

    #add Voltage Rail Domain IDs
    my %proc_vrd_hash = addProcVrdIds($node, $proc);

    print "
    <!-- Nest Voltage Rails -->
    <attribute>
        <id>VDD_AVSBUS_BUSNUM</id>
        <default>$nestRails{vdd_avsbus_busnum}</default>
    </attribute>
    <attribute>
        <id>VDD_AVSBUS_RAIL</id>
        <default>$nestRails{vdd_avsbus_rail}</default>
    </attribute>
    <attribute>
        <id>VDN_AVSBUS_BUSNUM</id>
        <default>$nestRails{vdn_avsbus_busnum}</default>
    </attribute>
    <attribute>
        <id>VDN_AVSBUS_RAIL</id>
        <default>$nestRails{vdn_avsbus_rail}</default>
    </attribute>
    <attribute>
        <id>VCS_AVSBUS_BUSNUM</id>
        <default>$nestRails{vcs_avsbus_busnum}</default>
    </attribute>
    <attribute>
        <id>VCS_AVSBUS_RAIL</id>
        <default>$nestRails{vcs_avsbus_rail}</default>
    </attribute>\n";

    # fsp-specific proc attributes
    do_plugin('fsp_proc',
            $scomFspApath, $scomFspAsize, $scanFspApath, $scanFspAsize,
            $scomFspBpath, $scomFspBsize, $scanFspBpath, $scanFspBsize,
            $node, $proc, $fruid, $ipath, $hwTopology, $mboxFspApath,
            $mboxFspAsize, $mboxFspBpath, $mboxFspBsize, $ordinalId,
            $sbefifoFspApath, $sbefifoFspAsize, $sbefifoFspBpath,
            $sbefifoFspBsize, \%proc_vrd_hash, \%nestRails );

    # Data from PHYP Memory Map
    print "\n";
    print "    <!-- Data from PHYP Memory Map -->\n";

    my $nodeSize = 0x200000000000; # 32 TB
    my $chipSize = 0x40000000000;  #  4 TB

    # Calculate the FSP and PSI BRIGDE BASE ADDR
    my $fspBase = 0;
    foreach my $i (@{$psiBus->{'psi-bus'}})
    {
        if (($i->{'processor'}->{target}->{position} eq $proc) &&
            ($i->{'processor'}->{target}->{node} eq $node ))
        {
            #FSP MMIO address
            $fspBase = 0x0006030100000000 + $nodeSize*$lognode +
                         $chipSize*$logid;
            last;
        }
    }

    # FSP MMIO address
    printf( "    <attribute><id>FSP_BASE_ADDR</id>\n" );
    printf( "        <default>0x%016X</default>\n", $fspBase );
    printf( "    </attribute>\n" );
    print "    <!-- End PHYP Memory Map -->\n\n";
    # end PHYP Memory Map

    if ((scalar @SortedPmChipAttr) == 0)
    {
        # Default the values.
        print "    <!-- PM_ attributes (default values) -->\n";
        print "    <attribute>\n";
        print "        <id>PM_APSS_CHIP_SELECT</id>\n";
        if( $proc % 2 == 0 ) # proc0 of DCM
        {
            print "        <default>0x00</default><!-- CS0 -->\n";
        }
        else # proc1 of DCM
        {
            print "        <default>0xFF</default><!-- NONE -->\n";
        }
        print "    </attribute>\n";
        print "    <attribute>\n";
        print "        <id>PM_PBAX_NODEID</id>\n";
        print "        <default>0</default>\n";
        print "    </attribute>\n";
        print "    <attribute>\n";
        print "        <id>PBAX_CHIPID</id>\n";
        print "        <default>$logid</default>\n";
        print "    </attribute>\n";
        print "    <attribute>\n";
        print "        <id>PBAX_BRDCST_ID_VECTOR</id>\n";
        print "        <default>$lognode</default>\n";
        print "    </attribute>\n";
        print "    <!-- End PM_ attributes (default values) -->\n";
    }
    else
    {
        print "    <!-- PM_ attributes -->\n";
        addProcPmAttrs( $proc, $node );
        print "    <!-- End PM_ attributes -->\n";
    }

    my $bootFreq = $reqPol->{'boot-frequency'}->{content};
    my $divisorRefclk = $reqPol->{'mb_bit_rate_divisor_refclk'};

    #Assume this will be the default, 8
    my $dpllDivider = 8;
    # Pull the value from the system policy we grabbed earlier
    print "    <attribute>\n";
    print "        <id>BOOT_FREQ_MHZ</id>\n";
    print "        <default>$reqPol->{'boot-frequency'}->{content}</default>\n";
    print "    </attribute>\n";
    print "    <attribute>\n";
    print "        <id>TDP_RDP_CURRENT_FACTOR</id>\n";
    print "        <default>$reqPol->{'tdp_rdp_current_factor'}</default>\n";
    print "    </attribute>\n";

    print "    <attribute>\n";
    print "        <id>MB_BIT_RATE_DIVISOR_REFCLK</id>\n";
    print "        <default>$divisorRefclk</default>\n";
    print "    </attribute>\n";

    my $bootFreqMult;
    {
        use Math::BigFloat ':constant';
        $bootFreqMult = $bootFreq / ($divisorRefclk / $dpllDivider);
    }

    $bootFreqMult = int ($bootFreqMult);
    print "    <attribute>\n";
    print "        <id>BOOT_FREQ_MULT</id>\n";
    print "        <default>$bootFreqMult</default>\n";
    print "    </attribute>\n";



    my $nXpY = "n" . $node . "p" . $proc;
    foreach my $attr (keys %procLoadline)
    {
        my $val;
        if(defined $procLoadline{$attr}{ $nXpY })
        {
            $val = $procLoadline{$attr}{ $nXpY };
        }
        else
        {
            $val = $procLoadline{$attr}{sys};
        }
        #if it has VRM_OFFSET in the attr name then add _UV suffix to ID
        if(index($attr, "VRM_VOFFSET" ) != -1)
        {
            print "    <attribute>\n";
            print "        <id>".$attr."</id>\n";
            print "        <default>$val</default>\n";
            print "    </attribute>\n";
        }
        #otherwise add UOHM suffix to ID
        else
        {
            print "    <attribute>\n";
            print "        <id>".$attr."</id>\n";
            print "        <default>$val</default>\n";
            print "    </attribute>\n";
        }
    }

    my $clock_pll_mux  = $reqPol->{'clock_pll_mux'};
    my $clock_pll_mux0 = $reqPol->{'clock_pll_mux0'};
    my $obus_ratio     = $reqPol->{'obus_ratio_value'};

    print "    <attribute>\n";
    print "        <id>CLOCK_PLL_MUX</id>\n";
    print "        <default>$clock_pll_mux</default>\n";
    print "    </attribute>\n";

    print "    <attribute>\n";
    print "        <id>CLOCK_PLL_MUX0</id>\n";
    print "        <default>$clock_pll_mux0</default>\n";
    print "    </attribute>\n";

    print "    <attribute>\n";
    print "        <id>OBUS_RATIO_VALUE</id>\n";
    print "        <default>$obus_ratio</default>\n";
    print "    </attribute>\n";


    print "    <attribute>\n";
    print "        <id>FREQ_O_MHZ</id>\n";
    print "        <default>" .
                join (",", ( $reqPol->{'obus_freq_mhz'}->{content},
                             $reqPol->{'obus_freq_mhz'}->{content},
                             $reqPol->{'obus_freq_mhz'}->{content},
                             $reqPol->{'obus_freq_mhz'}->{content} )) .
                  "</default>\n";
    print "    </attribute>\n";

    my $freq_regions      = $reqPol->{'system_resclk_freq_regions'};
    my $freq_region_index = $reqPol->{'system_resclk_freq_region_index'};
    my $l3_value          = $reqPol->{'system_resclk_l3_value'};
    my $l3_voltage_thresh = $reqPol->{'system_resclk_l3_voltage_threshold_mv'};
    my $resclk_value      = $reqPol->{'system_resclk_value'};

    print "</targetInstance>\n";

}

sub generate_ex
{
    my ($proc, $ex, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X06%04X",${node},$proc*MAX_EX_PER_PROC + $ex);
    my $eq = ($ex - ($ex%2))/2;
    my $ex_orig = $ex;
    $ex = $ex % 2;
    my $mruData = get_mruid($ipath);
    my $fapi_name = sprintf("pu.ex:k0:n%d:s0:p%02d:c%d", $node, $proc,$ex_orig);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/eq-$eq/ex-$ex";
    #EX is a logical target, Chiplet ID is the chiplet id of their immediate
    #parent which is EQ. The range of EQ is 0x10 - 0x15
    my $chipletId = sprintf("0x%X",(($ex_orig/2) + 0x10));
    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}eq${eq}ex$ex</id>
    <type>unit-ex-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/eq-$eq/ex-$ex</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$ex_orig</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$ex</default>
    </attribute>
    ";

    calcAndAddFapiPos("ex",$affinityPath,$ex_orig,$fapiPosHr);

    # call to do any fsp per-ex attributes
    do_plugin('fsp_ex', $proc, $ex, $ordinalId );

    print "
</targetInstance>
";
}

sub getPervasiveForUnit
{
    # Input should be of the form <type><chip unit>, example: "core0"
    my ($unit) = @_;

    # The mapping is a static variable that is preserved across new calls to
    # the function to speed up the mapping performance
    state %unitToPervasive;

    if ( not %unitToPervasive )
    {
        for my $core (0..MAX_CORE_PER_PROC-1)
        {
            $unitToPervasive{"core$core"} = 32 + $core;
        }
        for my $eq (0..MAX_EQ_PER_PROC-1)
        {
            $unitToPervasive{"eq$eq"} = 16 + $eq;
        }
        for my $xbus (0..MAX_XBUS_PER_PROC-1)
        {
            $unitToPervasive{"xbus$xbus"} = 6;
        }
        for my $obus (0..MAX_OBUS_PER_PROC-1)
        {
            $unitToPervasive{"obus$obus"} = 9 + $obus;
        }
        for my $capp (0..MAX_CAPP_PER_PROC-1)
        {
            $unitToPervasive{"capp$capp"} = 2 * ($capp+1);
        }
        for my $mcbist (0..MAX_MCBIST_PER_PROC-1)
        {
            $unitToPervasive{"mcbist$mcbist"} = 7 + $mcbist;
        }
        for my $mcs (0..MAX_MCS_PER_PROC-1)
        {
            $unitToPervasive{"mcs$mcs"} = 7 + ($mcs > 1);
        }
        for my $mca (0..MAX_MCA_PER_PROC-1)
        {
            $unitToPervasive{"mca$mca"} = 7 + ($mca > 3);
        }
        for my $pec (0..MAX_PEC_PER_PROC-1)
        {
            $unitToPervasive{"pec$pec"} = 13 + $pec;
        }
        for my $phb (0..MAX_PHB_PER_PROC-1)
        {
            $unitToPervasive{"phb$phb"} = 13 + ($phb>0) + ($phb>2);
        }
        my $offset = 0;
        for my $obrick (0..MAX_OBUS_BRICK_PER_PROC-1)
        {
            $offset += (($obrick%3 == 0) && ($obrick != 0)) ? 1 : 0;
            $unitToPervasive{"obus_brick$obrick"}
                = 9 + $offset;
        }
    }

    my $pervasive = "unknown";
    if(exists $unitToPervasive{$unit})
    {
        $pervasive = $unitToPervasive{$unit};
    }
    else
    {
        die "Cannot find pervasive for $unit";
    }

    return $pervasive
}

sub addPervasiveParentLink
{
    my ($sys,$node,$proc,$unit,$type) = @_;

    my $pervasive = getPervasiveForUnit("$type$unit");

    print "
    <attribute>
        <id>PARENT_PERVASIVE</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/perv-$pervasive</default>
    </attribute>";
}

sub generate_core
{
    my ($proc, $core, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X07%04X",${node},
                         $proc*MAX_CORE_PER_PROC + $core);
    my $mruData = get_mruid($ipath);
    my $core_orig = $core;
    my $ex = (($core - ($core % 2))/2) % 2;
    my $eq = ($core - ($core % 4))/4;
    $core = $core % 2;
    #Chiplet ID range for Cores start with 0x20
    my $chipletId = sprintf("0x%X",($core_orig + 0x20));
    my $fapi_name = sprintf("pu.core:k0:n%d:s0:p%02d:c%d",
                            $node, $proc, $core_orig);
    my $affinityPath =
        "affinity:sys-$sys/node-$node/proc-$proc/eq-$eq/ex-$ex/core-$core";
    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}eq${eq}ex${ex}core$core</id>
    <type>unit-core-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/eq-$eq/ex-$ex/core-$core</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$core_orig</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$core</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$core_orig,"core");

    calcAndAddFapiPos("core",$affinityPath,$core_orig,$fapiPosHr);

    # call to do any fsp per-ex_core attributes
    do_plugin('fsp_ex_core', $proc, $core, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_eq
{
    my ($proc, $eq, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X23%04X",${node},$proc*MAX_EQ_PER_PROC + $eq);
    my $mruData = get_mruid($ipath);
    my $fapi_name = sprintf("pu.eq:k0:n%d:s0:p%02d:c%d", $node, $proc, $eq);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/eq-$eq";
    #Chiplet ID range for EQ start with 0x10
    my $chipletId = sprintf("0x%X",($eq + 0x10));

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}eq$eq</id>
    <type>unit-eq-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/eq-$eq</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$eq</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$eq</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$eq,"eq");

    calcAndAddFapiPos("eq",$affinityPath,$eq,$fapiPosHr);

    # call to do any fsp per-eq attributes
    do_plugin('fsp_eq', $proc, $eq, $ordinalId );

    print "
</targetInstance>
";
}


sub generate_mcs
{
    my ($proc, $mcs, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X0B%04X",${node},$proc*MAX_MCS_PER_PROC + $mcs);
    my $mruData = get_mruid($ipath);
    my $mcs_orig = $mcs;
    $mcs = $mcs%2;
    my $mcbist = ($mcs_orig - ($mcs_orig%2))/2;

    #MCS is a logical target, Chiplet ID is the chiplet id of their immediate
    #parent which is MCBIST. The range of MCBIST is 0x07 - 0x08
    my $chipletId = sprintf("0x%X",($mcbist + 0x07));

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }

    my $lane_swap = 0;
    my $msb_swap = 0;
    my $swizzle = 0;
    foreach my $dmi ( @dbus_mcs )
    {
        if (($dmi->[DBUS_MCS_NODE_INDEX] eq ${node} ) &&
            ( $dmi->[DBUS_MCS_PROC_INDEX] eq $proc  ) &&
            ($dmi->[DBUS_MCS_UNIT_INDEX] eq  $mcs_orig   ))
        {
            $lane_swap = $dmi->[DBUS_MCS_DOWNSTREAM_INDEX];
            $msb_swap = $dmi->[DBUS_MCS_TX_SWAP_INDEX];
            $swizzle = $dmi->[DBUS_MCS_SWIZZLE_INDEX];
            last;
        }
    }
    my $physicalPath = "physical:sys-$sys/node-$node/proc-$proc"
                       . "/mcbist-$mcbist/mcs-$mcs";
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc"
                       . "/mcbist-$mcbist/mcs-$mcs";

    my $fapi_name =
               sprintf("pu.mcs:k0:n%d:s0:p%02d:c%d", $node, $proc, $mcs_orig);
    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}mcbist${mcbist}mcs$mcs</id>
    <type>unit-mcs-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>$physicalPath</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$mcs_orig</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>EI_BUS_TX_MSBSWAP</id>
        <default>$msb_swap</default>
    </attribute>
    <attribute><id>VPD_REC_NUM</id><default>0</default></attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$mcs</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$mcs_orig,"mcs");

    my $fapi_pos = calcAndAddFapiPos("mcs",$affinityPath,$mcs_orig,$fapiPosHr);

    #mcs MEMVPD_POS cannot exceed 16, so base on physical position
    #  instead of FAPI_POS to handle a system with multiple fabric groups
    my $memvpd_pos = $proc*4 + $mcs_orig;
    print "
    <attribute>
       <id>MEMVPD_POS</id>
       <default>$memvpd_pos</default>
     </attribute>";

    # call to do any fsp per-mcs attributes
    do_plugin('fsp_mcs', $proc, $mcs, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_mca
{
    my ($proc, $mca, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X24%04X",${node},$proc*MAX_MCA_PER_PROC + $mca);
    my $mruData = get_mruid($ipath);
    my $mcs = (($mca - ($mca%2))/2)%2;
    my $mcbist = ($mca - ($mca%4))/4;
    my $mca_orig = $mca;
    $mca = $mca % 2;
    #MCA is a logical target, Chiplet ID is the chiplet id of their immediate
    #parent which is MCS. since MCS is the also logical, therefore the
    # chiplet id of MCSIST will be returned. The range of MCBIST is 0x07 - 0x08
    my $chipletId = sprintf("0x%X",($mcbist + 0x07));

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.mca:k0:n%d:s0:p%02d:c%d",
                            $node, $proc, $mca_orig);
    my $affinityPath =
        "affinity:sys-$sys/node-$node/proc-$proc"
        . "/mcbist-$mcbist/mcs-$mcs/mca-$mca";
    my $physicalPath =
        "physical:sys-$sys/node-$node/proc-$proc"
         . "/mcbist-$mcbist/mcs-$mcs/mca-$mca";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}mcbist${mcbist}mcs${mcs}mca$mca</id>
    <type>unit-mca-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>$physicalPath</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$mca_orig</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$mca</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$mca_orig,"mca");

    calcAndAddFapiPos("mca",$affinityPath,$mca_orig,$fapiPosHr);

    # call to do any fsp per-mca attributes
    do_plugin('fsp_mca', $proc, $mca_orig, $ordinalId );

    print "
</targetInstance>
";
}

sub addFapiPos_for_mcbist
{
  my ($proc, $mcbist, $fapiPosHr) = @_;
  my $affinityPath="affinity:sys-$sys/node-$node/proc-$proc/mcbist-$mcbist";

  calcAndAddFapiPos("mcbist",$affinityPath,$mcbist,$fapiPosHr, undef, 1);
}

sub generate_mcbist
{
    my ($proc, $mcbist, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X25%04X",${node},$proc*MAX_MCBIST_PER_PROC + $mcbist);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.mcbist:k0:n%d:s0:p%02d:c%d",
                            $node, $proc, $mcbist);
    my $physicalPath="physical:sys-$sys/node-$node/proc-$proc/mcbist-$mcbist";
    my $affinityPath="affinity:sys-$sys/node-$node/proc-$proc/mcbist-$mcbist";

    my $chipletId = sprintf("0x%X",($mcbist + 0x07));

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}mcbist$mcbist</id>
    <type>unit-mcbist-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>$physicalPath</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$mcbist</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$mcbist</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$mcbist,"mcbist");

    calcAndAddFapiPos("mcbist",$affinityPath,$mcbist,$fapiPosHr);

    my %mcbist_rails_hash = addVoltageDomainIDs($node, $proc, $mcbist);

    # call to do any fsp per-mcbist attributes
    do_plugin('fsp_mcbist', \%mcbist_rails_hash);

    print "
</targetInstance>
";

}

sub generate_pec
{
    my ($proc, $pec, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X2D%04X",${node},$proc*MAX_PEC_PER_PROC + $pec);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.pec:k0:n%d:s0:p%02d:c%d", $node, $proc, $pec);

    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/pec-$pec";

    #Chiplet IDs for pec 0,1,2 => 0xd, 0xe, 0xf
    my $chipletId = sprintf("0x%X",($pec + 0xd));

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}pec$pec</id>
    <type>unit-pec-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/pec-$pec</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$pec</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$pec</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$pec,"pec");

    calcAndAddFapiPos("pec",$affinityPath,$pec,$fapiPosHr);

    # fill in the PCIE attributes
    my %pciAttr;
    $pciAttr{"PROC_PCIE_PCS_RX_CDR_GAIN"} = 'proc_pcie_pcs_rx_cdr_gain';
    $pciAttr{"PROC_PCIE_PCS_RX_LOFF_CONTROL"} = 'proc_pcie_pcs_rx_loff_control';
    $pciAttr{"PROC_PCIE_PCS_RX_VGA_CONTRL_REGISTER3"} = 'proc_pcie_pcs_rx_vga_control_register3';
    $pciAttr{"PROC_PCIE_PCS_RX_ROT_CDR_LOOKAHEAD"} = 'proc_pcie_pcs_rx_rot_cdr_lookahead';
    $pciAttr{"PROC_PCIE_PCS_PCLCK_CNTL_PLLA"} = 'proc_pcie_pcs_pclck_cntl_plla';
    $pciAttr{"PROC_PCIE_PCS_PCLCK_CNTL_PLLB"} = 'proc_pcie_pcs_pclck_cntl_pllb';
    $pciAttr{"PROC_PCIE_PCS_TX_DCLCK_ROT"} = 'proc_pcie_pcs_tx_dclck_rot_ovr';
    $pciAttr{"PROC_PCIE_PCS_TX_FIFO_CONFIG_OFFSET"} = 'proc_pcie_pcs_tx_fifo_config_offset';
    $pciAttr{"PROC_PCIE_PCS_TX_POWER_SEQ_ENABLE"} = 'proc_pcie_pcs_tx_power_seq_enable';
    $pciAttr{"PROC_PCIE_PCS_RX_PHASE_ROTATOR_CNTL"} = 'proc_pcie_pcs_rx_phase_rot_cntl';
    $pciAttr{"PROC_PCIE_PCS_RX_VGA_CNTL_REG1"} = 'proc_pcie_pcs_rx_vga_cntl_reg1';
    $pciAttr{"PROC_PCIE_PCS_RX_VGA_CNTL_REG2"} = 'proc_pcie_pcs_rx_vga_cntl_reg2';
    $pciAttr{"PROC_PCIE_PCS_RX_SIGDET_CNTL"} = 'proc_pcie_pcs_rx_sigdet_cntl';
    $pciAttr{"PROC_PCIE_PCS_RX_ROT_CDR_SSC"} = 'proc_pcie_pcs_rx_rot_cdr_ssc';
    $pciAttr{"PROC_PCIE_PCS_TX_PCIE_RECV_DETECT_CNTL_REG2"} = 'proc_pcie_pcs_tx_pcie_recv_detect_cntl_reg2';
    $pciAttr{"PROC_PCIE_PCS_TX_PCIE_RECV_DETECT_CNTL_REG1"} = 'proc_pcie_pcs_tx_pcie_recv_detect_cntl_reg1';
    $pciAttr{"PROC_PCIE_PCS_SYSTEM_CNTL"} = 'proc_pcie_pcs_system_cntl';
    $pciAttr{"PROC_PCIE_PCS_M_CNTL"} = 'proc_pcie_pcs_m_cntl';

    # PCIE Hack to set PEC PCIE_LANE_MASK and PCIE_IOP_SWAP attributes
    my %pciOtherAttr;

    #set PROC_PCIE_LANE_MASK to the default lane mask as defined
    #in the workbook - this value will be used to restore the slot to the default
    #lane configuration if it was once altered by the HX keyword
    if ($pec == 0)
    {
        $pciOtherAttr{"PEC_IS_BIFURCATABLE"} = 0x0;

        $pciOtherAttr{"PROC_PCIE_LANE_MASK"} = "0xFFFF, 0x0000, 0x0000, 0x0000";
        $pciOtherAttr{"PROC_PCIE_IOP_SWAP"} = 0x0;
    }
    elsif ($pec == 1)
    {
        $pciOtherAttr{"PEC_IS_BIFURCATABLE"} = 0x1;

        if ($proc == 0)
        {
            $pciOtherAttr{"PROC_PCIE_LANE_MASK"} = "0xFF00, 0x0000, 0x00FF, 0x0000";
            $pciOtherAttr{"PROC_PCIE_IOP_SWAP"} = 0x2;
        }
        elsif ($proc == 1)
        {
            $pciOtherAttr{"PROC_PCIE_LANE_MASK"} = "0xFF00, 0x0000, 0x0000, 0x0000";
            $pciOtherAttr{"PROC_PCIE_IOP_SWAP"} = 0x2;
        }
    }
    elsif ($pec == 2)
    {
        $pciOtherAttr{"PEC_IS_BIFURCATABLE"} = 0x1;

        if ($proc == 0)
        {
            # lane is bifurcated by default
            $pciOtherAttr{"PROC_PCIE_LANE_MASK"} = "0xFF00, 0x0000, 0x00FF, 0x0000";
            $pciOtherAttr{"PROC_PCIE_IOP_SWAP"} = 0x6;
        }
        elsif ($proc == 1)
        {
            $pciOtherAttr{"PROC_PCIE_LANE_MASK"} = "0xFFFF, 0x0000, 0x0000, 0x0000";
            $pciOtherAttr{"PROC_PCIE_IOP_SWAP"} = 0x4;
        }
    }

    # XML has this structure (iop==pec):
    #   <processor-settings>
    #     <target><name>pu</name><node>0</node><position>0</position></target>
    #       <attributename_iop0>data,data,data</attributename_iop0>
    #       <attributename_iop1>data,data,data</attributename_iop1>
    #       <attributename_iop2>data,data,data</attributename_iop2>
    foreach my $procsetting (@{$ProcPcie->{'processor-settings'}})
    {
        # only look at the values for my proc
        if( !(($procsetting->{'target'}->{'node'} == $node)
              && ($procsetting->{'target'}->{'position'} == $proc)) )
        {
            next;
        }

        foreach my $attr ( keys %pciAttr)
        {
            my $mrwname = $pciAttr{$attr}."_iop$pec";
            print "
    <attribute>
        <id>$attr</id>
        <default>$procsetting->{$mrwname}</default>
    </attribute>\n";
        }

        foreach my $attr ( keys %pciOtherAttr )
        {


            my $val = $pciOtherAttr{$attr};
            print "    <attribute>
        <id>$attr</id>
        <default>$val</default>
    </attribute>\n";
        }

    }

    # call to do any fsp per-pec attributes
    do_plugin('fsp_pec', $proc, $pec, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_phb_chiplet
{
    my ($proc, $phb, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $phb_orig = $phb;
    my $uidstr = sprintf("0x%02X2E%04X",${node},$proc*MAX_PHB_PER_PROC + $phb);
    my $mruData = get_mruid($ipath);
    my $pec = 0;
    my $phbChipUnit = $phb;
    if($phb > 0 && $phb < 3)
    {
        $pec = 1;
        $phb = $phb - 1;
    }
    elsif($phb >= 3)
    {
        $pec = 2;
        $phb = $phb - 3;
    }

    #Chiplet IDs for pec0phb0 => 0xd
    #Chiplet IDs for pec1phb1, pec1phb2 => 0xe
    #Chiplet IDs for pec2phb3, pec2phb4, pec2phb5 => 0xf
    my $chipletId = sprintf("0x%X",($pec + 0xd));

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
           $lognode = $chipIDs[$j][CHIP_ID_NODE];
           $logid = $chipIDs[$j][CHIP_ID_POS];
           last;
        }
    }

    my $fapi_name = sprintf("pu.phb:k0:n%d:s0:p%02d:c%d",
                            $node, $proc, $phb_orig);
    my $affinityPath =
        "affinity:sys-$sys/node-$node/proc-$proc/pec-$pec/phb-$phb";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}pec${pec}phb$phb</id>
    <type>unit-phb-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/pec-$pec/phb-$phb</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$phbChipUnit</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$phb</default>
    </attribute>
    ";

    addProcPcieAttrs( $proc, $node, $phb_orig );

    addPervasiveParentLink($sys,$node,$proc,$phbChipUnit,"phb");

    calcAndAddFapiPos("phb",$affinityPath,$phb,$fapiPosHr);

    # call to do any fsp per-phb attributes
    do_plugin('fsp_phb', $proc, $phb, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_ppe
{
    my ($proc, $ppe, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X2B%04X",${node},$proc*MAX_PPE_PER_PROC + $ppe);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.ppe:k0:n%d:s0:p%02d:c%d", $node, $proc, $ppe);

    my $affinityPath="affinity:sys-$sys/node-$node/proc-$proc/ppe-$ppe";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}ppe$ppe</id>
    <type>unit-ppe-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/ppe-$ppe</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$ppe</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$ppe</default>
    </attribute>
    ";

    calcAndAddFapiPos("ppe",$affinityPath,$ppe,$fapiPosHr);

    # call to do any fsp per-ppe attributes
    do_plugin('fsp_ppe', $proc, $ppe, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_obus
{
    my ($proc, $obus, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X28%04X",${node},
                         $proc*MAX_OBUS_PER_PROC + $obus);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }

    #Chiplet ID range for OBUS start with 0x09
    my $chipletId = sprintf("0x%X",($obus + 0x09));

    my $fapi_name = sprintf("pu.obus:k0:n%d:s0:p%02d:c%d", $node, $proc, $obus);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/obus-$obus";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}obus$obus</id>
    <type>unit-obus-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/obus-$obus</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$obus</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$obus</default>
    </attribute>
    <attribute>
        <id>OPTICS_CONFIG_MODE</id>
        <default>NV</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$obus,"obus");

    calcAndAddFapiPos("obus",$affinityPath,$obus,$fapiPosHr);

    # call to do any fsp per-obus attributes
    do_plugin('fsp_obus', $proc, $obus, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_xbus
{
    my ($proc, $xbus, $ordinalId, $ipath,$fapiPosHr, $ffePrecursor) = @_;
    my $mruData = get_mruid($ipath);
    my $uidstr = sprintf("0x%02X0E%04X",${node},$proc*MAX_XBUS_PER_PROC + $xbus);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }

    my $fapi_name = sprintf("pu.xbus:k0:n%d:s0:p%02d:c%d", $node, $proc, $xbus);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/xbus-$xbus";

    #Chiplet ID for XBUS is 0x06
    my $chipletId = sprintf("0x%X", 0x06);

    # Peer target variables
    my $peer;
    my $p_proc;
    my $p_port;
    my $p_node;
    my $tx_swap;

    # See if this bus is connected to anything
    foreach my $pbus ( @pbus )
    {
        if ($pbus->[PBUS_FIRST_END_POINT_INDEX] eq
            "n${node}:p${proc}:x${xbus}" )
        {
            if ($pbus->[PBUS_SECOND_END_POINT_INDEX] ne "invalid")
            {
                $peer = 1;
                $p_proc = $pbus->[PBUS_SECOND_END_POINT_INDEX];
                $p_port = $p_proc;
                $p_node = $pbus->[PBUS_SECOND_END_POINT_INDEX];
                $p_node =~ s/^n(.*):p.*:.*$/$1/;
                $p_proc =~ s/^.*:p(.*):.*$/$1/;
                $p_port =~ s/.*:p.*:.(.*)$/$1/;
                my $node_config = $pbus->[PBUS_NODE_CONFIG_FLAG];
                $tx_swap = $pbus->[PBUS_TX_MSB_LSB_SWAP];
                last;
            }
        }
    }

    #Just going to hardcode this forever on ZZ
    if($xbus == 2)
    {
        $tx_swap = sprintf("0x%X", 0x80);
    }

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}xbus$xbus</id>
    <type>unit-xbus-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/xbus-$xbus</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$xbus</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$xbus</default>
    </attribute>
    <attribute>
        <id>IO_XBUS_TX_FFE_PRECURSOR</id>
        <default>$ffePrecursor</default>
    </attribute>
    <attribute>
        <id>EI_BUS_TX_MSBSWAP</id>
        <default>$tx_swap</default>
    </attribute>
    ";

    if ($peer)
    {
        my $peerPhysPath = "physical:sys-${sys}/node-${p_node}/"
            ."proc-${p_proc}/xbus-${p_port}";
        my $peerHuid = sprintf("0x%02X0E%04X",${p_node},
            $p_proc*MAX_XBUS_PER_PROC + $p_port);

    print "
    <attribute>
        <id>PEER_TARGET</id>
        <default>$peerPhysPath</default>
    </attribute>
    <attribute>
        <id>PEER_PATH</id>
        <default>$peerPhysPath</default>
    </attribute>
    <compileAttribute>
        <id>PEER_HUID</id>
        <default>${peerHuid}</default>
    </compileAttribute>";

    }

    addPervasiveParentLink($sys,$node,$proc,$xbus,"xbus");

    calcAndAddFapiPos("xbus",$affinityPath,$xbus,$fapiPosHr);

    # call to do any fsp per-obus attributes
    do_plugin('fsp_xbus', $proc, $xbus, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_perv
{
    my ($proc, $perv, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X2C%04X",${node},$proc*MAX_PERV_PER_PROC + $perv);
    my $mruData = get_mruid($ipath);

    #Chiplet ID for PERV is 0x01
    my $chipletId = sprintf("0x%X", $perv);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.perv:k0:n%d:s0:p%02d:c%d", $node, $proc,$perv);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/perv-$perv";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}perv$perv</id>
    <type>unit-perv-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/perv-$perv</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$perv</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$perv</default>
    </attribute>
    ";

    calcAndAddFapiPos("perv",$affinityPath,$perv,$fapiPosHr);

    # call to do any fsp per-perv attributes
    do_plugin('fsp_perv', $proc, $perv, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_capp
{
    my ($proc, $capp, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X21%04X",${node},$proc*MAX_CAPP_PER_PROC + $capp);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }

    my $fapi_name = sprintf("pu.capp:k0:n%d:s0:p%02d:c%d", $node, $proc,$capp);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/capp-$capp";

    #Chiplet IDs for capp 0 => 0x2 and capp 1 => 0x4
    my $chipletId = sprintf("0x%X",(($capp + 1) * 2));

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}capp$capp</id>
    <type>unit-capp-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/capp-$capp</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$capp</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$capp</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$capp,"capp");

    calcAndAddFapiPos("capp",$affinityPath,$capp,$fapiPosHr);

    # call to do any fsp per-capp attributes
    do_plugin('fsp_capp', $proc, $capp, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_sbe
{
    my ($proc, $sbe, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $uidstr = sprintf("0x%02X2A%04X",${node},$proc*MAX_SBE_PER_PROC + $sbe);
    my $mruData = get_mruid($ipath);

    my $lognode;
    my $logid;
    for (my $j = 0; $j <= $#chipIDs; $j++)
    {
        if ($chipIDs[$j][CHIP_ID_NXPX] eq "n${node}:p${proc}")
        {
            $lognode = $chipIDs[$j][CHIP_ID_NODE];
            $logid = $chipIDs[$j][CHIP_ID_POS];
            last;
        }
    }
    my $fapi_name = sprintf("pu.sbe:k0:n%d:s0:p%02d:c%d", $node, $proc,$sbe);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/sbe-$sbe";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}sbe$sbe</id>
    <type>unit-sbe-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/sbe-$sbe</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$sbe</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$sbe</default>
    </attribute>
    ";


    calcAndAddFapiPos("sbe",$affinityPath,$sbe,$fapiPosHr);

    # call to do any fsp per-sbe attributes
    do_plugin('fsp_sbe', $proc, $sbe, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_npu
{
    my ($proc, $npu, $ordinalId, $ipath) = @_;
    my $uidstr = sprintf("0x%02X43%04X",${node},$proc*MAX_NPU_PER_PROC + $npu);

    my $fapi_name    = "NA";
    my $path = "sys-$sys/node-$node/proc-$proc/npu-$npu";

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}npu$npu</id>
    <type>unit-npu-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:$path</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:$path</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath/npu$npu</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$npu</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>0x05</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$npu</default>
    </attribute>
</targetInstance>
";
}

sub generate_obus_brick
{
    my ($proc, $obus, $ipath) = @_;
    my $proc_name = "n${node}:p${proc}";
    print "\n<!-- $SYSNAME n${node}p${proc} OBUS BRICK units -->\n";

    for my $i ( 0 .. ARCH_LIMIT_OBUS_BRICK_PER_OBUS-1 )
    {
        generate_a_obus_brick( $proc, $obus, $i, $ipath);
    }
}

sub generate_a_obus_brick
{
    my ($proc, $obus, $obus_brick, $ipath) = @_;

    my $ordinalId = ($proc * MAX_OBUS_BRICK_PER_PROC) +
                    ($obus * ARCH_LIMIT_OBUS_BRICK_PER_OBUS) +
                    ($obus_brick);
    my $uidstr    = sprintf("0x%02X42%04X",${node},$ordinalId);
    my $fapi_name = sprintf("pu.obrick:k0:n0:s0:p%02d:c%d", $proc,$ordinalId);
    my $chipletId = sprintf("0x%X",(0x5));

    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}obus${obus}obus-brick${obus_brick}</id>
    <type>unit-obus-brick-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/obus-$obus/obus_brick-$obus_brick</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:sys-$sys/node-$node/proc-$proc/obus-$obus/obus_brick-$obus_brick</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath/obus_brick$obus_brick</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$obus_brick</default>
    </attribute>
    <attribute>
        <id>CHIPLET_ID</id>
        <default>$chipletId</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$obus_brick</default>
    </attribute>
    ";

    addPervasiveParentLink($sys,$node,$proc,$obus_brick,"obus_brick");

    print "
</targetInstance>
";
}

my $nxInit = 0;
my %nxList = ();
sub generate_nx_ipath
{
    foreach my $Target (@{$eTargets->{target}})
    {
        #get the nx ipath detail
        if($Target->{'ecmd-common-name'} eq "nx")
        {
            my $ipath = $Target->{'instance-path'};
            my $node = $Target->{node};
            my $position = $Target->{position};

            $nxList{$node}{$position} = {
                'node'         => $node,
                'position'     => $position,
                'instancePath' => $ipath,
            }
        }
    }
}

sub generate_nx
{
    my ($proc, $ordinalId, $node) = @_;
    my $uidstr = sprintf("0x%02X1E%04X",${node},$proc);

    # Get the nx info
    if ($nxInit == 0)
    {
        generate_nx_ipath;
        $nxInit = 1;
    }

    my $ipath = $nxList{$node}{$proc}->{'instancePath'};
    my $mruData = get_mruid($ipath);
    my $fapi_name = "NA"; # nx not FAPI target
    my $nx = 0;

    print "\n<!-- $SYSNAME n${node}p$proc NX units -->\n";
    print "
<targetInstance>
    <id>sys${sys}node${node}proc${proc}nx$nx</id>
    <type>unit-nx-power9</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/nx-$nx</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:sys-$sys/node-$node/proc-$proc/nx-$nx</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>0</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$nx</default>
    </attribute>
    ";

    # call to do any fsp per-nx attributes
    do_plugin('fsp_nx', $proc, $ordinalId );

    print "
</targetInstance>
";
}

my $logicalDimmInit = 0;
my %logicalDimmList = ();
sub generate_logicalDimms
{
    my $memory_busses_file = open_mrw_file($::mrwdir,
                                           "${sysname}-memory-busses.xml");
    my $dramTargets = parse_xml_file($memory_busses_file);

    #get the DRAM details
    foreach my $Target (@{$dramTargets->{drams}->{dram}})
    {
        my $node = $Target->{'assembly-position'};
        my $ipath = $Target->{'dram-instance-path'};
        my $dimmIpath = $Target->{'dimm-instance-path'};
        my $mbaIpath = $Target->{'mba-instance-path'};
        my $mbaPort = $Target->{'mba-port'};
        my $mbaSlot = $Target->{'mba-slot'};

        my $dimm = substr($dimmIpath, index($dimmIpath, 'dimm-')+5);
        my $mba = substr($mbaIpath, index($mbaIpath, 'mba')+3);

        $logicalDimmList{$node}{$dimm}{$mba}{$mbaPort}{$mbaSlot} = {
                'node'             => $node,
                'dimmIpath'        => $dimmIpath,
                'mbaIpath'         => $mbaIpath,
                'dimm'             => $dimm,
                'mba'              => $mba,
                'mbaPort'          => $mbaPort,
                'mbaSlot'          => $mbaSlot,
                'logicalDimmIpath' => $ipath,
        }
    }
}

sub generate_centaur
{
    my ($ctaur, $mcs, $fsiA, $altfsiA, $ipath, $ordinalId, $relativeCentaurRid,
        $ipath, $membufVrmUuidHash,$fapiPosHr) = @_;

    my @fsi = @{$fsiA};
    my @altfsi = @{$altfsiA};
    my $scomFspApath = $devpath->{chip}->{$ipath}->{'scom-path-a'};
    my $scanFspApath = $devpath->{chip}->{$ipath}->{'scan-path-a'};
    my $scomFspAsize = length($scomFspApath) + 1;
    my $scanFspAsize = length($scanFspApath) + 1;
    my $scomFspBpath = "";

    if (ref($devpath->{chip}->{$ipath}->{'scom-path-b'}) ne "HASH")
    {
        $scomFspBpath = $devpath->{chip}->{$ipath}->{'scom-path-b'};
    }
    my $scanFspBpath = "";
    if (ref($devpath->{chip}->{$ipath}->{'scan-path-b'}) ne "HASH")
    {
        $scanFspBpath = $devpath->{chip}->{$ipath}->{'scan-path-b'};
    }
    my $scomFspBsize = length($scomFspBpath) + 1;
    my $scanFspBsize = length($scanFspBpath) + 1;
    my $proc = $mcs;
    $proc =~ s/.*:p(.*):.*/$1/g;
    $mcs =~ s/.*:.*:mcs(.*)/$1/g;

    my $mruData = get_mruid($ipath);
    my $uidstr = sprintf("0x%02X04%04X",${node},$proc*MAX_MCS_PER_PROC + $mcs);

    my $lane_swap = 0;
    my $msb_swap = 0;
    foreach my $dmi ( @dbus_centaur )
    {
        if (($dmi->[DBUS_CENTAUR_NODE_INDEX] eq ${node} ) &&
            ($dmi->[DBUS_CENTAUR_MEMBUF_INDEX] eq $ctaur) )
        {
            $lane_swap = $dmi->[DBUS_CENTAUR_UPSTREAM_INDEX];
            # Note: We swap rx/tx when we fill in the array, so there's no
            # need to use rx here - we already accounted for direction
            $msb_swap = $dmi->[DBUS_CENTAUR_TX_SWAP_INDEX];
            last;
        }
    }

    # Get the logical DIMM info
    if ($logicalDimmInit == 0)
    {
        generate_logicalDimms;
        $logicalDimmInit = 1;
    }

    my $fapi_name = sprintf("pu.centaur:k0:n%d:s0:p%02d:c0",
                            $node, $ctaur);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/mcs-$mcs/"
            . "membuf-$ctaur";
    print "
<!-- $SYSNAME Centaur n${node}p${ctaur} : start -->

<targetInstance>
    <id>sys${sys}node${node}membuf${ctaur}</id>
    <type>chip-membuf-centaur</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute><id>POSITION</id><default>$ctaur</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/membuf-$ctaur</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>EI_BUS_TX_MSBSWAP</id>
        <default>$msb_swap</default>
    </attribute>";

    calcAndAddFapiPos("membuf",$affinityPath,0,$fapiPosHr);

    # FSI Connections #
    if( $#fsi <= 0 )
    {
        die "\n*** No valid FSI link found for Centaur $ctaur ***\n";
    }

    print "\n
    <!-- FSI connections -->
    <attribute>
        <id>FSI_MASTER_TYPE</id>
        <default>CMFSI</default>
    </attribute>
    <attribute>
        <id>FSI_SLAVE_CASCADE</id>
        <default>0</default>
    </attribute>
    <attribute>
        <id>FSI_OPTION_FLAGS</id>
        <default>
        <field><id>flipPort</id><value>0</value></field>
        <field><id>reserved</id><value>0</value></field>
        </default>
    </attribute>";

    my $mNode = $fsi[FSI_MASTERNODE_FIELD];
    my $mPos = $fsi[FSI_MASTERPOS_FIELD];
    my $link = $fsi[FSI_LINK_FIELD];
    print "
    <!-- FSI-A is connected via node$mNode:proc$mPos:CMFSI-$link -->
    <attribute>
        <id>FSI_MASTER_CHIP</id>
        <default>physical:sys-$sys/node-$mNode/proc-$mPos</default>
    </attribute>
    <attribute>
        <id>FSI_MASTER_PORT</id>
        <default>$link</default>
    </attribute>";

    if( $#altfsi <= 0 )
    {
        print "
    <!-- FSI-B is not connected -->
    <attribute>
        <id>ALTFSI_MASTER_CHIP</id>
        <default>physical:sys</default><!-- no B path -->
    </attribute>
    <attribute>
        <id>ALTFSI_MASTER_PORT</id>
        <default>0xFF</default><!-- no B path -->
    </attribute>\n";
    }
    else
    {
        $mNode = $altfsi[FSI_MASTERNODE_FIELD];
        $mPos = $altfsi[FSI_MASTERPOS_FIELD];
        $link = $altfsi[FSI_LINK_FIELD];
        print "
    <!-- FSI-B is connected via node$mNode:proc$mPos:CMFSI-$link -->
    <attribute>
        <id>ALTFSI_MASTER_CHIP</id>
        <default>physical:sys-$sys/node-$mNode/proc-$mPos</default>
    </attribute>
    <attribute>
        <id>ALTFSI_MASTER_PORT</id>
        <default>$link</default>
    </attribute>\n";
    }
    print "    <!-- End FSI connections -->\n";
    # End FSI #

    print "
    <attribute><id>VPD_REC_NUM</id><default>$ctaur</default></attribute>
    <attribute>
        <id>EI_BUS_TX_LANE_INVERT</id>
        <default>$lane_swap</default>
    </attribute>";


    # call to do any fsp per-centaur attributes
    do_plugin('fsp_centaur', $scomFspApath, $scomFspAsize, $scanFspApath,
       $scanFspAsize, $scomFspBpath, $scomFspBsize, $scanFspBpath,
       $scanFspBsize, $relativeCentaurRid, $ordinalId);


    # Centaur is only used as an I2C Master in openpower systems
    if ( $haveFSPs == 0 )
    {
        # add EEPROM attributes
        addEepromsCentaur($sys, $node, $ctaur);

        # add I2C_BUS_SPEED_ARRAY attribute
        addI2cBusSpeedArray($sys, $node, $ctaur, "memb");
    }

    if($useGpioToEnableVddr)
    {
        my $vddrKey = "n" . $node . "p" . $ctaur;
        if(!exists $vddrEnableHash{$vddrKey})
        {
            die   "FATAL! Cannot find required GPIO info for memory buffer "
                . "$vddrKey VDDR enable.\n"
        }
        elsif(!exists $vddrEnableHash{$vddrEnableHash{$vddrKey}{i2cMasterKey}})
        {
            die   "FATAL! Must reference real membuf as I2C master for VDDR "
                . "enable.  Membuf $vddrEnableHash{$vddrKey}{i2cMasterKey} "
                . "requested.\n";
        }
        else
        {
            print
"\n    <attribute>
        <id>GPIO_INFO</id>
        <default>
            <field>
                <id>i2cMasterPath</id>
                <value>$vddrEnableHash{$vddrKey}{i2cMasterEntityPath}</value>
            </field>
            <field>
                <id>port</id>
                <value>$vddrEnableHash{$vddrKey}{i2cMasterPort}</value>
            </field>
            <field>
                <id>devAddr</id>
                <value>$vddrEnableHash{$vddrKey}{i2cAddressHexStr}</value>
            </field>
            <field>
                <id>engine</id>
                <value>$vddrEnableHash{$vddrKey}{i2cMasterEngine}</value>
            </field>
            <field>
                <id>vddrPin</id>
                <value>$vddrEnableHash{$vddrKey}{vddrPin}</value>
            </field>
        </default>
    </attribute>\n";
        }
    }

    print "\n</targetInstance>\n";

}

sub generate_mba
{
    my ($ctaur, $mcs, $mba, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $proc = $mcs;
    $proc =~ s/.*:p(.*):.*/$1/g;
    $mcs =~ s/.*:.*:mcs(.*)/$1/g;

    my $uidstr = sprintf("0x%02X0D%04X",
                          ${node},($proc * MAX_MCS_PER_PROC + $mcs)*
                                   MAX_MBA_PER_MEMBUF + $mba);
    my $mruData = get_mruid($ipath);

    my $fapi_name = sprintf("pu.mba:k0:n%d:s0:p%02d:c%d", $node, $proc, $mba);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/mcs-$mcs/"
            . "membuf-$ctaur/mba-$mba";

    print "
<targetInstance>
    <id>sys${sys}node${node}membuf${ctaur}mba$mba</id>
    <type>unit-mba-centaur</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/membuf-$ctaur/"
            . "mba-$mba</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$mba</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$mba</default>
    </attribute>
    ";

    calcAndAddFapiPos("mba",$affinityPath,$mba,$fapiPosHr);

    # call to do any fsp per-mba attributes
    do_plugin('fsp_mba', $ctaur, $mba, $ordinalId );

    print "
</targetInstance>
";
}

sub generate_l4
{
    my ($ctaur, $mcs, $l4, $ordinalId, $ipath,$fapiPosHr) = @_;
    my $proc = $mcs;
    $proc =~ s/.*:p(.*):.*/$1/g;
    $mcs =~ s/.*:.*:mcs(.*)/$1/g;

    my $uidstr = sprintf("0x%02X0A%04X",${node},$proc*MAX_MCS_PER_PROC + $mcs);
    my $mruData = get_mruid($ipath);
    my $fapi_name = sprintf("pu.l4:k0:n%d:s0:p%02d:c0", $node, $proc, $l4);

    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/mcs-$mcs/"
            . "membuf-$ctaur/l4-$l4";

    print "
<targetInstance>
    <id>sys${sys}node${node}membuf${ctaur}l4${l4}</id>
    <type>unit-l4-centaur</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/membuf-$ctaur/"
            . "l4-$l4</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$ipath</default>
    </compileAttribute>
    <attribute>
        <id>CHIP_UNIT</id>
        <default>$l4</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>$l4</default>
    </attribute>
    ";

    calcAndAddFapiPos("l4",$affinityPath,$l4,$fapiPosHr);

    # call to do any fsp per-centaur_l4 attributes
    do_plugin('fsp_centaur_l4', $ctaur, $ordinalId );

    print "</targetInstance>";
}

sub generate_is_dimm
{
    my ($fapiPosHr) = @_;

    # Use this i2c info to populate thermal sensors
    # From the i2c busses, grab the information for the DIMMs, if any.
    my @dimmI2C;
    my $i2c_file = open_mrw_file($mrwdir, "${sysname}-i2c-busses.xml");
    my $i2cSettings = XMLin($i2c_file);

    foreach my $i (@{$i2cSettings->{'i2c-device'}})
    {
        # look for THERMAL_SENSOR data from Host-connected side
        if ( $i->{'part-id'} eq 'DIMM_THERMAL_SENSOR' &&
            ($i->{'i2c-master'}->{'host-connected'} eq "1") )
        {
            my $node = $i->{'card-target'}->{'node'};
            my $pos = $i->{'card-target'}->{'position'};

            $dimmI2C[$node][$pos] = {
                   'port'=> $i->{'i2c-master'}->{'i2c-port'},
                'devAddr'=> $i->{'address'},
                 'engine'=> $i->{'i2c-master'}->{'i2c-engine'}
                 };
        }
    }

    print "\n<!-- $SYSNAME JEDEC DIMMs -->\n";
    for my $i ( 0 .. $#SMembuses )
    {
        if ($SMembuses[$i][BUS_NODE_FIELD] != $node)
        {
            next;
        }

        my $ipath = $SMembuses[$i][DIMM_PATH_FIELD];
        my $pos = $SMembuses[$i][DIMM_TARGET_FIELD];
        $pos =~ s/.*:p(.*)/$1/;
        my $dimm = $SMembuses[$i][DIMM_PATH_FIELD];
        $dimm =~ s/.*dimm-(.*)/$1/;

        my $fapi_name = sprintf("dimm:k0:n%d:s0:p%02d",
                                $node, $dimm);

        # PROC position relative to node and MCA position relative to PROC.
        my $tmp = $SMembuses[$i][MCA_TARGET_FIELD];
        my ( $proc, $mca ) = ( $1, $2 ) if ( $tmp =~ ":p([0-9]+):mca([0-9]+)" );

        # MCBIST, MCS, MCA, and DIMM relative positions for affinity path.
        my $mcb_rel_proc = int($mca/4) % ARCH_LIMIT_MCBIST_PER_PROC;
        my $mcs_rel_mcb  = int($mca/2) % ARCH_LIMIT_MCS_PER_MCBIST;
        my $mca_rel_mcs  =     $mca    % ARCH_LIMIT_MCA_PER_MCS;
        my $dimm_rel_mca =     $dimm   % ARCH_LIMIT_DIMM_PER_MCA;

        my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc" .
                           "/mcbist-$mcb_rel_proc/mcs-$mcs_rel_mcb" .
                           "/mca-$mca_rel_mcs/dimm-$dimm_rel_mca";

        # DIMM relative to NODE using affinity path for HUID. Note that this is
        # different than the DIMM position used in $dimm, which is from the
        # instance path and changes based on board configuation.
        my $dimm_rel_node = $proc * MAX_MCA_PER_PROC * ARCH_LIMIT_DIMM_PER_MCA +
                            $mca * ARCH_LIMIT_DIMM_PER_MCA +
                            $dimm_rel_mca;

        my $uidstr = sprintf( "0x%02X03%04X", $node, $dimm_rel_node );

        # add dimm to mcbist array
        push(@{$mcbist_dimms{$node . $proc."_".$mcb_rel_proc}}, "n${node}:p${pos}");

        print "\n<!-- DIMM n${node}:p${pos} -->\n";
        print "
<targetInstance>
    <id>sys${sys}node${node}dimm$dimm</id>
    <type>lcard-dimm-jedec</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute><id>POSITION</id><default>$pos</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/dimm-$dimm</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$dimm</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>$ipath</default>
    </compileAttribute>
    <attribute>
        <id>VPD_REC_NUM</id>
        <default>$pos</default>
    </attribute>";

        my $fapi_pos = calcAndAddFapiPos("isdimm",$affinityPath,$dimm,$fapiPosHr);
        my $dimm_drop = $fapi_pos % 2;
        print "
    <attribute>
        <id>REL_POS</id>
        <default>$dimm_drop</default>
    </attribute>
    <attribute>
        <id>POS_ON_MEM_PORT</id>
        <default>$dimm_rel_mca</default>
    </attribute>";

        # Add TEMP_SENSOR_I2C_CONFIG
        if (exists $dimmI2C[$node][$pos])
        {

        print "
    <attribute>
        <id>TEMP_SENSOR_I2C_CONFIG</id>
        <default>
            <field><id>i2cMasterPath</id><value>physical:sys-$sys/node-$node/dimm-$dimm</value></field>
            <field><id>engine</id><value>". $dimmI2C[$node][$pos]->{engine} ."</value></field>
            <field><id>port</id><value>". $dimmI2C[$node][$pos]->{port} ."</value></field>
            <field><id>devAddr</id><value>0x". $dimmI2C[$node][$pos]->{devAddr} ."</value></field>
        </default>
    </attribute>
    ";

        # Add EEPROM_NV_INFO i2c config
        # Base address for the NV controller is 0x80
        # piggybacking the last nibble of devAddr from $dimmI2C to build the device address
        print "
    <attribute>
        <id>EEPROM_NV_INFO</id>
        <default>
            <field><id>i2cMasterPath</id><value>physical:sys-$sys/node-$node/proc-$proc</value></field>
            <field><id>port</id><value>". $dimmI2C[$node][$pos]->{port} ."</value></field>
            <field><id>devAddr</id><value>0x8". substr($dimmI2C[$node][$pos]->{devAddr},-1) ."</value></field>
            <field><id>engine</id><value>". $dimmI2C[$node][$pos]->{engine} ."</value></field>
            <field><id>byteAddrOffset</id><value>0x03</value></field>
            <field><id>maxMemorySizeKB</id><value>0x01</value></field>
            <field><id>chipCount</id><value>0x01</value></field>
            <field><id>writePageSize</id><value>0x01</value></field>
            <field><id>writeCycleTime</id><value>0x05</value></field>
        </default>
    </attribute>
    ";
        }

        #RID number hack, get it from location code
        my $dimmLoc = $SMembuses[$i][DIMM_LOC_CODE_FIELD];
        $dimmLoc =~ s/.*C(.*)/$1/;

        # call to do any fsp per-dimm attributes
        my $dimmHex = sprintf("0xD0%02X",($dimmLoc-15));
        do_plugin('fsp_dimm', $proc, $dimm, $dimm, $dimmHex );

        print "\n</targetInstance>\n";

    }
}

sub generate_centaur_dimm
{
    my ($fapiPosHr) = @_;

    print "\n<!-- $SYSNAME Centaur DIMMs -->\n";

    for my $i ( 0 .. $#SMembuses )
    {
        if ($SMembuses[$i][BUS_NODE_FIELD] != $node)
        {
            next;
        }

        my $ipath = $SMembuses[$i][DIMM_PATH_FIELD];
        my $proc = $SMembuses[$i][MCS_TARGET_FIELD];
        my $mcs = $proc;
        $proc =~ s/.*:p(.*):.*/$1/;
        $mcs =~ s/.*mcs(.*)/$1/;
        my $ctaur = $SMembuses[$i][CENTAUR_TARGET_FIELD];
        my $mba = $ctaur;
        $ctaur =~ s/.*:p(.*):mba.*$/$1/;
        $mba =~ s/.*:mba(.*)$/$1/;
        my $pos = $SMembuses[$i][DIMM_TARGET_FIELD];
        $pos =~ s/.*:p(.*)/$1/;
        my $dimm = $SMembuses[$i][DIMM_PATH_FIELD];
        $dimm =~ s/.*dimm-(.*)/$1/;
        my $relativeDimmRid = $dimm;
        my $dimmPos = $SMembuses[$i][DIMM_POS_FIELD];
        $dimmPos =~ s/.*dimm-(.*)/$1/;
        my $relativePos = $dimmPos;
        print "\n<!-- C-DIMM n${node}:p${pos} -->\n";
        for my $id ( 0 .. 7 )
        {
            my $dimmid = $dimm;
            $dimmid <<= 3;
            $dimmid |= $id;
            $dimmid = sprintf ("%d", $dimmid);
            generate_dimm( $proc, $mcs, $ctaur, $pos, $dimmid, $id,
                           ($SMembuses[$i][BUS_ORDINAL_FIELD]*8)+$id,
                           $relativeDimmRid, $relativePos, $ipath,
                           $fapiPosHr);
        }
    }
}

sub generate_ucds
{
    my ($proc) = @_;

    if(defined $ucdI2cIndex{"n${node}p${proc}"} )
    {
        foreach my $index ( @{$ucdI2cIndex{"n${node}p${proc}"}})
        {
            generate_ucd($proc,$ucdOrdinalId++,$index);
        }
    }
}

sub generate_ucd
{
    my ($proc,$ordinalId,$i) = @_;

    my $instancePath = $I2Cdevices[$i]{i2c_instance_path};

    # For simplicity, position tracks ordinal ID on ZZ, the only FSP MRW
    # platform with UCD devices
    my $position = $ordinalId;

    # Determine the type of target instance to request
    my $targetType;
    if($I2Cdevices[$i]{i2c_part_id} eq "UCD9090")
    {
        $targetType = "ucd9090";
    }
    elsif ($I2Cdevices[$i]{i2c_part_id} eq "UCD90120A")
    {
        $targetType = "ucd90120a";
    }
    else
    {
        die "UCD type " . $I2Cdevices[$i]{i2c_part_id} . " not supported.";
    }

    # Build the I2C_CONTRL_INFO attribute
    my %i2cControlInfo = ();
    $i2cControlInfo{i2cMasterPath} = "physical:sys-0/node-${node}/proc-${proc}";
    $i2cControlInfo{engine}        = "$I2Cdevices[$i]{i2c_engine}";
    $i2cControlInfo{port}          = "$I2Cdevices[$i]{i2c_port}";
    $i2cControlInfo{devAddr}       = "0x$I2Cdevices[$i]{i2c_devAddr}";

    my $i2cControlInfoAttr = "\n";
    foreach my $field ( sort keys %i2cControlInfo )
    {
        $i2cControlInfoAttr .=
              "            <field>\n"
            . "                <id>$field</id>\n"
            . "                <value>$i2cControlInfo{$field}</value>\n"
            . "            </field>\n";
    }
    $i2cControlInfoAttr .= "        ";

    # Compute the remaining attributes
    my $huidAttr = sprintf("0x%02X3F%04X",${node},$position);
    my $physPathAttr = "physical:sys-$sys/node-$node/power_sequencer-$position";
    my $affinityPathAttr = "affinity:sys-$sys/node-$node/proc-$proc/power_sequencer-$position";
    my $ordinalIdAttr = "$ordinalId";
    my $instancePathAttr = "$instancePath";

    # Load the attributes into a hash and build the attribute output string
    my %attrs = ();
    $attrs{I2C_CONTROL_INFO}{VALUE}="$i2cControlInfoAttr";
    $attrs{HUID}{VALUE}="$huidAttr";
    $attrs{PHYS_PATH}{VALUE}="$physPathAttr";
    $attrs{AFFINITY_PATH}{VALUE}="$affinityPathAttr";
    $attrs{ORDINAL_ID}{VALUE}="$ordinalIdAttr";
    $attrs{INSTANCE_PATH}{VALUE}="$instancePathAttr";
    $attrs{INSTANCE_PATH}{TYPE}="compileAttribute";

    my $attrOutput = "";
    foreach my $attr ( sort keys %attrs )
    {
        my $type = exists $attrs{$attr}{TYPE} ? $attrs{$attr}{TYPE} :
            "attribute";
        $attrOutput .=
              "    <${type}>\n"
            . "        <id>$attr</id>\n"
            . "        <default>$attrs{$attr}{VALUE}</default>\n"
            . "    </${type}>\n";
    }

    # Output the target
    print "
<targetInstance>
    <id>sys${sys}node${node}power_sequencer$position</id>
    <type>$targetType</type>\n";
    print "$attrOutput";

    print "</targetInstance>\n";
}

sub generate_tpm
{
    my ($proc, $ordinalId) = @_;

    # Get the index of the TPM i2c device within the i2Cdevices container
    my $i=$tpmI2cIndex{"n${node}p${proc}"};

    # Compute the TPM position; find i2c card name within i2c instance path
    # and extract the instance, which equals the position
    my $cardId = $I2Cdevices[$i]{i2c_card_id};
    my $instancePath = $I2Cdevices[$i]{i2c_instance_path};
    $instancePath =~ /$cardId-(\d+)/;
    my $position = $1;

    # Build the TPM_INFO attribute
    my %tpmInfo = ();
    $tpmInfo{tpmEnabled} = "1"; # Fixed, not in MRW
    $tpmInfo{i2cMasterPath} = "physical:sys-0/node-${node}/proc-${proc}";
    $tpmInfo{port} = "$I2Cdevices[$i]{i2c_port}";
    $tpmInfo{devAddrLocality0} = "0x$I2Cdevices[$i]{i2c_devAddr}";
    $tpmInfo{devAddrLocality1} = "0xA8"; # Fixed, not in MRW
    $tpmInfo{devAddrLocality2} = "0xAA"; # Fixed, not in MRW
    $tpmInfo{devAddrLocality3} = "0xA4"; # Fixed, not in MRW
    $tpmInfo{devAddrLocality4} = "0xA6"; # Fixed, not in MRW
    $tpmInfo{engine} = "$I2Cdevices[$i]{i2c_engine}";
    $tpmInfo{byteAddrOffset} = "0x01"; # Fixed, not in MRW

    my $tpmAttr = "\n";
    foreach my $field ( sort keys %tpmInfo )
    {
        $tpmAttr .=
              "            <field>\n"
            . "                <id>$field</id>\n"
            . "                <value>$tpmInfo{$field}</value>\n"
            . "            </field>\n";
    }
    $tpmAttr .= "        ";

    # Compute the rest of the attributes
    my $huidAttr = sprintf("0x%02X31%04X",${node},$position);
    my $physPathAttr = "physical:sys-$sys/node-$node/tpm-$position";
    my $affinityPathAttr = "affinity:sys-$sys/node-$node/proc-$proc/tpm-$position";
    my $ordinalIdAttr = "$ordinalId";
    my $positionAttr = $position;
    my $instancePathAttr = "$instancePath";
    my $mruIdAttr = get_mruid($instancePath);

    # Load the attributes into a hash and build the attribute output string
    my %attrs = ();
    $attrs{TPM_INFO}{VALUE}="$tpmAttr";
    $attrs{HUID}{VALUE}="$huidAttr";
    $attrs{PHYS_PATH}{VALUE}="$physPathAttr";
    $attrs{AFFINITY_PATH}{VALUE}="$affinityPathAttr";
    $attrs{ORDINAL_ID}{VALUE}="$ordinalIdAttr";
    $attrs{POSITION}{VALUE}="$positionAttr";
    $attrs{INSTANCE_PATH}{VALUE}="$instancePathAttr";
    $attrs{INSTANCE_PATH}{TYPE}="compileAttribute";
    $attrs{MRU_ID}{VALUE}="$mruIdAttr";

    my $attrOutput = "";
    foreach my $attr ( sort keys %attrs )
    {
        my $type = exists $attrs{$attr}{TYPE} ? $attrs{$attr}{TYPE} :
            "attribute";
        $attrOutput .=
              "    <${type}>\n"
            . "        <id>$attr</id>\n"
            . "        <default>$attrs{$attr}{VALUE}</default>\n"
            . "    </${type}>\n";
    }

    # Output the target
    print "
<targetInstance>
    <id>sys${sys}node${node}tpm$position</id>
    <type>chip-tpm-cectpm</type>\n";
    print "$attrOutput";

    # call the fsp per-tpm attribute handler
    do_plugin('fsp_tpm', $ordinalId);

    print "\n</targetInstance>\n";
}

# Since each Centaur has only one dimm, it is assumed to be attached to port 0
# of the MBA0 chiplet.
sub generate_dimm
{
    my ($proc, $mcs, $ctaur, $pos, $dimm, $id, $ordinalId, $relativeDimmRid,
        $relativePos,$fapiPosHr)
        = @_;

    my $x = $id;
    $x = int ($x / 4);
    my $y = $id;
    $y = int(($y - 4 * $x) / 2);
    my $z = $id;
    $z = $z % 2;
    my $zz = $id;
    $zz = $zz % 4;
    #$x = sprintf ("%d", $x);
    #$y = sprintf ("%d", $y);
    #$z = sprintf ("%d", $z);
    #$zz = sprintf ("%d", $zz);
    my $uidstr = sprintf("0x%02X03%04X",${node},$dimm);

    # Calculate the VPD Record number value
    my $vpdRec = 0;

    # Set offsets based on mba and dimm values
    if( 1 == $x )
    {
        $vpdRec = $vpdRec + 4;
    }
    if( 1 == $y )
    {
        $vpdRec = $vpdRec + 2;
    }
    if( 1 == $z )
    {
        $vpdRec = $vpdRec + 1;
    }

    my $position = ($proc * 64) + 8 * $mcs + $vpdRec;

    # Adjust offset based on MCS value
    $vpdRec = ($mcs * 8) + $vpdRec;
    # Adjust offset basedon processor value
    $vpdRec = ($proc * 64) + $vpdRec;

    my $dimmHex = sprintf("0xD0%02X",$relativePos
        + (CDIMM_RID_NODE_MULTIPLIER * ${node}));

    #MBA numbers should be 01 and 23
    my $mbanum=0;
    if (1 ==$x )
    {
        $mbanum = '23';
    }
    else
    {
        $mbanum = '01';
    }

    my $logicalDimmInstancePath = "instance:"
        . $logicalDimmList{$node}{$relativePos}{$mbanum}{$y}{$z}->{'logicalDimmIpath'};

    my $fapi_name = sprintf("dimm:k0:n%d:s0:p%02d", $node, $dimm);
    my $affinityPath = "affinity:sys-$sys/node-$node/proc-$proc/mcs-$mcs/"
            . "membuf-$pos/mba-$x/dimm-$zz";

    print "
<targetInstance>
    <id>sys${sys}node${node}dimm$dimm</id>
    <type>lcard-dimm-cdimm</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>
    <attribute><id>POSITION</id><default>$position</default></attribute>
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/dimm-$dimm</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>$affinityPath</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>$logicalDimmInstancePath</default>
    </compileAttribute>
    <attribute>
        <id>MBA_DIMM</id>
        <default>$z</default>
    </attribute>
    <attribute>
        <id>MBA_PORT</id>
        <default>$y</default>
    </attribute>
    <attribute><id>VPD_REC_NUM</id><default>$vpdRec</default></attribute>";

    calcAndAddFapiPos("cdimm",$affinityPath,$y*$z,$fapiPosHr);

    # call to do any fsp per-dimm attributes
    do_plugin('fsp_dimm', $proc, $ctaur, $dimm, $ordinalId, $dimmHex );

    print "\n</targetInstance>\n";
}

################################################################################
# Compares two Apss instances based on the node and position #
################################################################################
sub byApssNodePos($$)
{
    my $retVal = -1;

    my $lhsInstance_node = $_[0][SPI_NODE_FIELD];
    my $rhsInstance_node = $_[1][SPI_NODE_FIELD];
    if(int($lhsInstance_node) eq int($rhsInstance_node))
    {
         my $lhsInstance_pos = $_[0][SPI_APSS_POS_FIELD];
         my $rhsInstance_pos = $_[1][SPI_APSS_POS_FIELD];
         if(int($lhsInstance_pos) eq int($rhsInstance_pos))
         {
                die "ERROR: Duplicate apss positions: 2 apss with same
                    node and position, \
                    NODE: $lhsInstance_node POSITION: $lhsInstance_pos\n";
         }
         elsif(int($lhsInstance_pos) > int($rhsInstance_pos))
         {
             $retVal = 1;
         }
    }
    elsif(int($lhsInstance_node) > int($rhsInstance_node))
    {
        $retVal = 1;
    }
    return $retVal;
}

our @SPIs;
our $apssInit = 0;

# This routine is common to FSP and HB
my $getBaseRidApss = 0;
my $ridApssBase = 0;

sub init_apss
{
    my $proc_spi_busses =
                open_mrw_file($::mrwdir, "${sysname}-proc-spi-busses.xml");
    if($proc_spi_busses ne "")
    {
        my $spiBus = ::parse_xml_file($proc_spi_busses,
            forcearray=>['processor-spi-bus']);

        # Capture all SPI connections into the @SPIs array
        my @rawSPIs;
        foreach my $i (@{$spiBus->{'processor-spi-bus'}})
        {
            if($getBaseRidApss == 0)
            {
                if ($i->{endpoint}->{'instance-path'} =~ /.*APSS-[0-9]+$/i)
                {
                    my $locCode = $i->{endpoint}->{'location-code'};
                    my @locCodeComp = split( '-', $locCode );
                    $ridApssBase = (@locCodeComp > 2) ? 0x4900 : 0x800;
                    $getBaseRidApss = 1;
                }
            }

            if ($i->{endpoint}->{'instance-path'} =~ /.*APSS-[0-9]+$/i)
            {
                my $pos = $i->{endpoint}->{'instance-path'};
                while (chop($pos) ne '/') {};
                $pos = chop($pos);
                push @rawSPIs, [
                $i->{processor}->{'instance-path'},
                $i->{processor}->{target}->{node},
                $i->{processor}->{target}->{position},
                $i->{endpoint}->{'instance-path'},
                $pos, 0, 0
                ];
            }
        }

        @SPIs = sort byApssNodePos @rawSPIs;

        my $ordinalApss = 0;
        my $apssPos = 0;
        my $currNode = -1;
        for my $i (0 .. $#SPIs)
        {
            $SPIs[$i][SPI_APSS_ORD_FIELD] = $ordinalApss;
            $ordinalApss++;
            if($currNode != $SPIs[$i][SPI_NODE_FIELD])
            {
                $apssPos = 0;
                $currNode = $SPIs[$i][SPI_NODE_FIELD];
            }
            $SPIs[$i][SPI_APSS_RID_FIELD]
            = sprintf("0x%08X", $ridApssBase + (2*$currNode) + $apssPos++);
        }
    }
}


my $occInit = 0;
my %occList = ();
sub occ_init
{
    my $targets_file = open_mrw_file($::mrwdir, "${sysname}-targets.xml");
    my $occTargets = ::parse_xml_file($targets_file);

    #get the OCC details
    foreach my $Target (@{$occTargets->{target}})
    {
        if($Target->{'ecmd-common-name'} eq "occ")
        {
            my $ipath = $Target->{'instance-path'};
            my $node = $Target->{node};
            my $position = $Target->{position};

            $occList{$node}{$position} = {
                'node'         => $node,
                'position'     => $position,
                'instancePath' => $ipath,
            }
        }
    }
}

sub generate_occ
{
    # input parameters
    my ($proc, $ordinalId) = @_;

    if ($apssInit == 0)
    {
        init_apss;
        $apssInit = 1;
    }

    my $uidstr = sprintf("0x%02X13%04X",${node},$proc);
    my $mastercapable = 0;

    for my $spi ( 0 .. $#SPIs )
    {
        my $ipath = $SPIs[$spi][SPI_ENDPOINT_PATH_FIELD];
        if(($SPIs[$spi][SPI_ENDPOINT_PATH_FIELD] =~ /.*APSS-[0-9]+$/i) &&
           ($node eq $SPIs[$spi][SPI_NODE_FIELD]) &&
           ($proc eq $SPIs[$spi][SPI_POS_FIELD]))
        {
            $mastercapable = 1;
            last;
        }
    }

    # Get the OCC info
    if ($occInit == 0)
    {
        occ_init;
        $occInit = 1;
    }
    my $mruData = get_mruid($occList{$node}{$proc}->{'instancePath'});

    my $fapi_name = "NA"; # OCC not FAPI target

    print "
<!-- $SYSNAME n${node}p${proc} OCC units -->

<targetInstance>
    <id>sys${sys}node${node}proc${proc}occ0</id>
    <type>occ</type>
    <attribute><id>HUID</id><default>${uidstr}</default></attribute>
    <attribute><id>FAPI_NAME</id><default>$fapi_name</default></attribute>";

    do_plugin('fsp_occ', $ordinalId );

    print "
    <attribute>
        <id>PHYS_PATH</id>
        <default>physical:sys-$sys/node-$node/proc-$proc/occ-0</default>
    </attribute>
    <attribute>
        <id>MRU_ID</id>
        <default>$mruData</default>
    </attribute>
    <attribute>
        <id>AFFINITY_PATH</id>
        <default>affinity:sys-$sys/node-$node/proc-$proc/occ-0</default>
    </attribute>
    <attribute>
        <id>ORDINAL_ID</id>
        <default>$ordinalId</default>
    </attribute>
    <compileAttribute>
        <id>INSTANCE_PATH</id>
        <default>instance:$occList{$node}{$proc}->{'instancePath'}</default>
    </compileAttribute>
    <attribute>
        <id>OCC_MASTER_CAPABLE</id>
        <default>$mastercapable</default>
    </attribute>
    <attribute>
        <id>REL_POS</id>
        <default>0</default>
    </attribute>
    ";

    print "</targetInstance>\n";

}

sub addSysAttrs
{
    for my $i (0 .. $#systemAttr)
    {
        my $j =0;
        my $sysAttrArraySize=$#{$systemAttr[$i]};
        while ($j<$sysAttrArraySize)
        {
            # systemAttr is an array of pairs
            #  even index is the attribute id
            #  odd index has its default value
            my $l_default = $systemAttr[$i][$j+1];
            if (substr($l_default,0,2) eq "0b") #convert bin to hex
            {
                $l_default = sprintf('0x%X', oct($l_default));
            }
            print "    <attribute>\n";
            print "        <id>$systemAttr[$i][$j]</id>\n";
            print "        <default>$l_default</default>\n";
            print "    </attribute>\n";
            $j+=2; # next attribute id and default pair
        }
    }
}

sub addNodeAttrs
{
    for my $i (0 .. $#nodeAttr)
    {
        my $j =0;
        my $nodeAttrArraySize=$#{$nodeAttr[$i]};
        while ($j<$nodeAttrArraySize)
        {
            # nodeAttr is an array of pairs
            #  even index is the attribute id
            #  odd index has its default value
            my $l_default = $nodeAttr[$i][$j+1];
            if (substr($l_default,0,2) eq "0b") #convert bin to hex
            {
                $l_default = sprintf('0x%X', oct($l_default));
            }
            print "    <attribute>\n";
            print "        <id>$nodeAttr[$i][$j]</id>\n";
            print "        <default>$l_default</default>\n";
            print "    </attribute>\n";
            $j+=2; # next attribute id and default pair
        }
    }
}



sub addProcPmAttrs
{
    my ($position,$nodeId) = @_;

    for my $i (0 .. $#SortedPmChipAttr)
    {
        if (($SortedPmChipAttr[$i][CHIP_POS_INDEX] == $position) &&
            ($SortedPmChipAttr[$i][CHIP_NODE_INDEX] == $nodeId) )
        {
            #found the corresponding proc and node
            my $j =0;
            my $arraySize=$#{$SortedPmChipAttr[$i]} - CHIP_ATTR_START_INDEX;
            while ($j<$arraySize)
            {
                print "    <attribute>\n";
                print "        <id>$SortedPmChipAttr[$i][CHIP_ATTR_START_INDEX+$j]</id>\n";
                $j++;
                print "        <default>$SortedPmChipAttr[$i][CHIP_ATTR_START_INDEX+$j]</default>\n";
                print "    </attribute>\n";
                $j++;
            }
        }
    }
}

sub addProcPcieAttrs
{
    my ($position, $nodeId, $phbNum) = @_;

    foreach my $pcie ( keys %procPcieTargetList )
    {
        if( $procPcieTargetList{$pcie}{nodePosition} eq $nodeId &&
            $procPcieTargetList{$pcie}{procPosition} eq $position)
        {
            my $procPcieRef = (\%procPcieTargetList)->{$pcie};
            my @gen3PhbValues = @{ $procPcieRef->{'gen3phbValues'}};
            my @gen4PhbValues = @{ $procPcieRef->{'gen4phbValues'}};
            print "    <attribute>\n";
            print "        <id>PROC_PCIE_LANE_EQUALIZATION_GEN3</id>\n";
            print "        <default>$gen3PhbValues[$phbNum]\n";
            print "        </default>\n";
            print "    </attribute>\n";
            print "    <attribute>\n";
            print "        <id>PROC_PCIE_LANE_EQUALIZATION_GEN4</id>\n";
            print "        <default>$gen4PhbValues[$phbNum]\n";
            print "        </default>\n";
            print "    </attribute>\n";
            last;
        }
    }
}

sub addEepromsProc
{
    my ($sys, $node, $proc) = @_;

    my $id_name eq "";
    my $devAddr = 0x00;
    my $tmp_ct eq "";

    # Loop through all i2c devices
    # Uncomment to emit debug trace to STDERR
    # print STDERR "Loop through all $#I2Cdevices i2c devices\n";
    for my $i ( 0 .. $#I2Cdevices )
    {
        # FSP/Power systems:
        if ( $haveFSPs == 1 )
        {

            # Skip I2C devices that we don't care about
            if( ( !($I2Cdevices[$i]{i2cm_uid} =~ /I2CM_PROC_PROMC\d+/)
                ) ||
                !($I2Cdevices[$i]{i2cm_node} == $node) )
            {
                next;
            }

            # Position field must match $proc with one exception:
            # Murano's PRIMARY_MODULE_VPD has a position field one spot
            # behind $proc
            if ( ($CHIPNAME eq "murano") &&
                 ("$I2Cdevices[$i]{i2c_content_type}" eq
                  "PRIMARY_MODULE_VPD") )
            {
                if ( ($I2Cdevices[$i]{i2cm_pos}+1) != $proc )
                {
                    next;
                }
            }
            elsif ( $I2Cdevices[$i]{i2cm_pos} != $proc)
            {
                next;
            }
        }

        # Openpower
        else
        {
            if ( ($I2Cdevices[$i]{i2cm_pos} != $proc) ||
                 ($I2Cdevices[$i]{i2cm_node} != $node) )
            {
                next;
            }
        }

        # Convert Content Type
        $tmp_ct = $I2Cdevices[$i]{i2c_content_type};
        if ( $tmp_ct eq "PRIMARY_SBE_VPD")
        {
            $id_name = "EEPROM_SBE_PRIMARY_INFO";
        }
        elsif ($tmp_ct eq "REDUNDANT_SBE_VPD")
        {
            $id_name = "EEPROM_SBE_BACKUP_INFO";
        }
        elsif ( $tmp_ct eq "PRIMARY_FRU_AND_MODULE_VPD")
        {
            $id_name = "EEPROM_VPD_PRIMARY_INFO";
        }
        elsif ($tmp_ct eq "REDUNDANT_FRU_AND_MODULE_VPD")
        {
            $id_name = "EEPROM_VPD_BACKUP_INFO";
        }
        elsif ( ($tmp_ct eq "PRIMARY_SBE_VPD_SPARE") ||
                ($tmp_ct eq "REDUNDANT_SBE_VPD_SPARE") ||
                ($tmp_ct eq "PRIMARY_FRU_AND_MODULE_VPD_SPARE") ||
                ($tmp_ct eq "REDUNDANT_FRU_AND_MODULE_VPD_SPARE") )
        {
            next; # Skipping these entries
        }

        else
        {
            die "ERROR: addEepromsProc: unrecognized Content Type $tmp_ct\n";
        }

        print "    <attribute>\n";
        print "        <id>$id_name</id>\n";
        print "        <default>\n";
        print "            <field><id>i2cMasterPath</id><value>physical:",
                          "sys-$sys/node-$node/proc-$proc</value></field>\n";
        print "            <field><id>port</id><value>",
                          "$I2Cdevices[$i]{i2c_port}</value></field>\n";
        print "            <field><id>devAddr</id><value>0x",
                          "$I2Cdevices[$i]{i2c_devAddr}",
                          "</value></field>\n";
        print "            <field><id>engine</id><value>",
                          "$I2Cdevices[$i]{i2c_engine}",
                          "</value></field>\n";
        print "            <field><id>byteAddrOffset</id><value>",
                          "$I2Cdevices[$i]{i2c_byte_addr_offset}",
                          "</value></field>\n";
        print "            <field><id>maxMemorySizeKB</id><value>",
                          "$I2Cdevices[$i]{i2c_max_mem_size}",
                          "</value></field>\n";
        print "            <field><id>chipCount</id><value>",
                          "$I2Cdevices[$i]{i2c_chip_count}",
                          "</value></field>\n";
        print "            <field><id>writePageSize</id><value>",
                          "$I2Cdevices[$i]{i2c_write_page_size}",
                          "</value></field>\n";
        print "            <field><id>writeCycleTime</id><value>",
                          "$I2Cdevices[$i]{i2c_write_cycle_time}",
                          "</value></field>\n";
        print "        </default>\n";
        print "    </attribute>\n";

    }
}

sub addHotPlug
{
    my ($sys,$node,$proc) = @_;

    #hot plug array is 8x8 array
    my @hot_plug_array = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                          0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    my $row_count = 8;
    my $column_count = 8;

    my $hot_count = 0;
    my $tmp_speed = 0x0;

    for my $i ( 0 .. $#I2CHotPlug )
    {
        my $i2cmProcNode;
        my $i2cmProcPos;
        for my $x (0 .. $#I2CHotPlug_Host )
        {
            if( $I2CHotPlug_Host[$x]{i2c_slave_path} eq
                    $I2CHotPlug[$i]{i2c_instPath})
            {
                $i2cmProcNode = $I2CHotPlug_Host[$i]{i2c_proc_node};
                $i2cmProcPos = $I2CHotPlug_Host[$i]{i2c_proc_pos};
                last;
            }
        }


        if(!($I2CHotPlug[$i]{'i2cm_node'} == $node) ||
                !($I2CHotPlug[$i]{'i2cm_pos'} == $proc))
        {
            next;
        }
        if($hot_count < $row_count)
        {
            #enum for MAX5961 and PCA9551 defined in attribute_types.xml
            #as SUPPORTED_HOT_PLUG.
            my $part_id_enum = 0x00;
            if($I2CHotPlug[$i]{i2c_part_id} eq "MAX5961")
            {
                $part_id_enum = 0x01;
            }
            else
            {
                $part_id_enum = 0x02;
            }

            #update array
            $tmp_speed = $I2CHotPlug[$i]{i2c_speed};

            #update array 8 at a time (for up to 8 times)
            $hot_plug_array[($hot_count*$row_count)]     =
                $I2CHotPlug[$i]{i2c_engine};
            $hot_plug_array[($hot_count*$row_count) + 1] =
                $I2CHotPlug[$i]{i2c_port};
            $hot_plug_array[($hot_count*$row_count) + 2] =
                ($tmp_speed & 0xFF00) >> 8;
            $hot_plug_array[($hot_count*$row_count) + 3] =
                ($tmp_speed & 0x00FF);
            $hot_plug_array[($hot_count*$row_count) + 4] =
                sprintf("0x%x",(hex $I2CHotPlug[$i]{i2c_slaveAddr}) * 2);
            $hot_plug_array[($hot_count*$row_count) + 5] = $part_id_enum;
            $hot_plug_array[($hot_count*$row_count) + 6] = $i2cmProcNode;
            $hot_plug_array[($hot_count*$row_count) + 7] = $i2cmProcPos;

            $hot_count = $hot_count + 1;
        }
        else
        {
            #if we have found more than 8 controllers (not supported)
            die "ERROR: addHotPlug: too many hotPlug's: $hot_count\n";
        }
    }

    #and then print attribute here
    if($hot_count > 0)
    {
        print "    <attribute>\n";
        print "        <id>HOT_PLUG_POWER_CONTROLLER_INFO</id>\n";
        print "        <default>\n";
        for my $j (0 .. ($row_count - 1))
        {
            print "            ";
            for my $k (0 .. ($column_count - 1))
            {
                if($j == ($row_count -1) && $k == ($column_count - 1))
                {
                    #last entry does not have a comma
                    print "$hot_plug_array[($j*$row_count) + $k]";
                }else
                {
                    print "$hot_plug_array[($j*$row_count) + $k],";
                }
            }
            print "\n";
        }
        print "        </default>\n";
        print "    </attribute>\n";
    }
}

sub addEepromsCentaur
{
    my ($sys, $node, $ctaur) = @_;

    my $id_name eq "";
    my $devAddr = 0x00;
    my $tmp_ct eq "";

    # Loop through all i2c devices
    for my $i ( 0 .. $#I2Cdevices )
    {
        # Convert Content Type
        $tmp_ct = "$I2Cdevices[$i]{i2c_content_type}";
        if ( $tmp_ct eq "ALL_CENTAUR_VPD" )
        {
            $id_name = "EEPROM_VPD_PRIMARY_INFO";
        }
        elsif ( $tmp_ct eq "CENTAUR_VPD" )
        {
            if ( ($I2Cdevices[$i]{i2cm_pos} != $ctaur) ||
                 ($I2Cdevices[$i]{i2cm_node} != $node) )
            {
                next;
            }
            $id_name = "EEPROM_VPD_PRIMARY_INFO";
        }
        else
        {
            next;
        }

        # Since I2C Master might be different than centaur, need to do
        # some checks
        if ( $I2Cdevices[$i]{i2cm_name} == "pu" )
        {
            $I2Cdevices[$i]{i2cm_name} = "proc";
        }
        elsif ( $I2Cdevices[$i]{i2cm_name} == "memb" )
        {
            $I2Cdevices[$i]{i2cm_name} = "membuf";
        }

        print "    <attribute>\n";
        print "        <id>$id_name</id>\n";
        print "        <default>\n";
        print "            <field><id>i2cMasterPath</id><value>physical:",
                          "sys-$sys/node-$node/",
                          "$I2Cdevices[$i]{i2cm_name}",
                          "-$I2Cdevices[$i]{i2cm_pos}</value></field>\n";
        print "            <field><id>port</id><value>",
                          "$I2Cdevices[$i]{i2c_port}</value></field>\n";
        print "            <field><id>devAddr</id><value>0x",
                          "$I2Cdevices[$i]{i2c_devAddr}",
                          "</value></field>\n";
        print "            <field><id>engine</id><value>",
                          "$I2Cdevices[$i]{i2c_engine}",
                          "</value></field>\n";
        print "            <field><id>byteAddrOffset</id><value>",
                          "$I2Cdevices[$i]{i2c_byte_addr_offset}",
                          "</value></field>\n";
        print "            <field><id>maxMemorySizeKB</id><value>",
                          "$I2Cdevices[$i]{i2c_max_mem_size}",
                          "</value></field>\n";
        print "            <field><id>chipCount</id><value>",
                          "$I2Cdevices[$i]{i2c_chip_count}",
                          "</value></field>\n";
        print "            <field><id>writePageSize</id><value>",
                          "$I2Cdevices[$i]{i2c_write_page_size}",
                          "</value></field>\n";
        print "            <field><id>writeCycleTime</id><value>",
                          "$I2Cdevices[$i]{i2c_write_cycle_time}",
                          "</value></field>\n";
        print "        </default>\n";
        print "    </attribute>\n";

    }
}


sub addI2cBusSpeedArray
{
    my ($sys, $node, $pos, $i2cm_name) = @_;

    my $tmp_speed  = 0x0;
    my $tmp_engine = 0x0;
    my $tmp_port   = 0x0;
    my $tmp_offset = 0x0;
    my $tmp_ct eq "";

    # bus_speed_array[engine][port] is 4x13 array
    # Hardcoding speed_array[3][1] for nvdimm as NVDIMM is current 
    # not in mrw for ZZ (last gen of serverwiz1)
    my @speed_array =  (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 400, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    # Loop through all i2c devices
    for my $i ( 0 .. $#I2Cdevices )
    {

        # -----------------------
        # Processor is I2C Master
        if ( $i2cm_name eq "pu" )
        {
            # FSP/Power systems:
            if ( $haveFSPs == 1 )
            {
                # Skip I2C devices that we don't care about
                if( ( !($I2Cdevices[$i]{i2cm_uid} eq "I2CM_TPM")
                      &&
                      !($I2Cdevices[$i]{i2cm_uid} =~ /I2CM_PROC_PROMC\d+/)
                      &&
                      !( ($I2Cdevices[$i]{i2cm_uid}
                         eq "I2CM_HOTPLUG") &&
                         ( ($I2Cdevices[$i]{i2c_part_id}
                           eq "MAX5961") ||
                           ($I2Cdevices[$i]{i2c_part_id}
                           eq "PCA9551") ||
                           ($I2Cdevices[$i]{i2c_part_id}
                           eq "UCD90120A") ||
                           ($I2Cdevices[$i]{i2c_part_id}
                           eq "UCD9090")
                         )
                       )
                    ) ||
                    ($I2Cdevices[$i]{i2cm_node} != $node) ||
                    ($I2Cdevices[$i]{i2cm_name} != $i2cm_name) )
                {
                    next;
                }

                # Processor position field must match $pos with one exception:
                # Murano's PRIMARY_MODULE_VPD has a position field one spot
                # behind $proc
                if ( ($CHIPNAME eq "murano") &&
                     ("$I2Cdevices[$i]{i2c_content_type}" eq
                     "PRIMARY_MODULE_VPD") )
                {
                    if ( ($I2Cdevices[$i]{i2cm_pos}+1) != $pos )
                    {
                        next;
                    }
                }
                elsif ( $I2Cdevices[$i]{i2cm_pos} != $pos)
                {
                    next;
                }

            }
            # No FSP
            else
            {
                if ( ($I2Cdevices[$i]{i2cm_pos} != $pos) ||
                     ($I2Cdevices[$i]{i2cm_node} != $node) ||
                     !($I2Cdevices[$i]{i2cm_name} eq $i2cm_name) )
                {
                    next;
                }
            }
        }

        # -----------------------
        # Memb is I2C Master
        elsif ( $i2cm_name eq "memb" )
        {
            if ( ($I2Cdevices[$i]{i2cm_pos} != $pos) ||
                 ($I2Cdevices[$i]{i2cm_node} != $node) ||
                 !($I2Cdevices[$i]{i2cm_name} eq $i2cm_name) )
            {
                next;
            }

            # @todo RTC:160630 - engine 6 is invalid for hostboot
            if ( $I2Cdevices[$i]{i2c_engine} == 6 )
            {
                $I2Cdevices[$i]{i2c_engine} = 0;
            }
        }
        else
        {
            die "ERROR: addI2cBusSpeedArray: unsupported input $i2cm_name\n";
        }


        # update array
        $tmp_speed  = $I2Cdevices[$i]{i2c_speed};
        $tmp_engine = $I2Cdevices[$i]{i2c_engine};
        $tmp_port   = $I2Cdevices[$i]{i2c_port};
        $tmp_offset = ($tmp_engine * 13) + $tmp_port;

        # use the slower speed if there is a previous entry
        if ( ($speed_array[$tmp_offset] == 0) ||
             ($tmp_speed < $speed_array[$tmp_offset] ) )
        {
            $speed_array[$tmp_offset] = $tmp_speed;

        }

    }
    print "     <attribute>\n";
    print "        <id>I2C_BUS_SPEED_ARRAY</id>\n";
    print "        <default>\n";

    my $speed_array_len = scalar(@speed_array);
    my $speed_array_str = "";
    for my $i (0 .. $speed_array_len)
    {
        $speed_array_str .= "            $speed_array[$i],\n";
    }

    #remove last ","
    $speed_array_str =~ s/,\n$/\n/;
    print $speed_array_str;

    print "        </default>\n";
    print "    </attribute>\n";

}



sub get_mruid
{
    my($ipath) = @_;
    my $mruData = 0;
    foreach my $i (@{$mruAttr->{'mru-id'}})
    {
        if ($ipath eq $i->{'instance-path'})
        {
            $mruData = $i->{'mrid-value'};
            last;
        }
    }
    return $mruData;
}

sub open_mrw_file
{
    my ($paths, $filename) = @_;

    #Need to get list of paths to search
    my @paths_to_search = split /:/, $paths;
    my $file_found = "";

    #Check for file at each directory in list
    foreach my $path (@paths_to_search)
    {
        if ( open (FH, "<$path/$filename") )
        {
            $file_found = "$path/$filename";
            close(FH);
            last; #break out of loop
        }
    }

    if ($file_found eq "")
    {
        #If the file was not found, build up error message and exit
        my $err_msg = "Could not find $filename in following paths:\n";
        foreach my $path (@paths_to_search)
        {
            $err_msg = $err_msg."  $path\n";
        }
        die $err_msg;
    }
    else
    {
        #Return the full path to the file found
        return $file_found;
    }
}

my %g_xml_cache = ();
sub parse_xml_file
{
    my $parms = Dumper(\@_);
    if (not defined $g_xml_cache{$parms})
    {
        $g_xml_cache{$parms} = XMLin(@_);
    }
    return $g_xml_cache{$parms};
}

sub display_help
{
    use File::Basename;
    my $scriptname = basename($0);
    print STDERR "
Usage:

    $scriptname --help
    $scriptname --system=sysname --systemnodes=2 --mrwdir=pathname
                     [--build=hb] [--outfile=XmlFilename]
        --system=systemname
              Specify which system MRW XML to be generated
        --systemnodes=systemnodesinbrazos
              Specify number of nodes for brazos system, by default it is 4
        --mrwdir=pathname
              Specify the complete dir pathname of the MRW. Colon-delimited
              list accepted to specify multiple directories to search.
        --build=hb
              Specify HostBoot build (hb)
        --outfile=XmlFilename
              Specify the filename for the output XML. If omitted, the output
              is written to STDOUT which can be saved by redirection.
\n";
}
