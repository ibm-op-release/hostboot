# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/usr/targeting/common/Targets.pm $
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
package Targets;

use strict;
use XML::Simple;
use XML::Parser;
use Data::Dumper;
use feature "state";

use constant
{
    PERVASIVE_PARENT_CORE_OFFSET => 32,
    PERVASIVE_PARENT_EQ_OFFSET => 16,
    PERVASIVE_PARENT_XBUS_OFFSET => 6,
    PERVASIVE_PARENT_OBUS_OFFSET => 9,
    PERVASIVE_PARENT_MCBIST_OFFSET => 7,
    PERVASIVE_PARENT_MCS_OFFSET => 7,
    PERVASIVE_PARENT_MCA_OFFSET => 7,
    PERVASIVE_PARENT_PEC_OFFSET => 13,
    PERVASIVE_PARENT_PHB_OFFSET => 13,
    PERVASIVE_PARENT_NPU_OFFSET => 5,
    PERVASIVE_PARENT_MC_OFFSET => 7,
    PERVASIVE_PARENT_MI_OFFSET => 7,
    PERVASIVE_PARENT_DMI_OFFSET => 7,
    NUM_PROCS_PER_GROUP => 4,
    DIMMS_PER_PROC => 64,  # Cumulus
    DIMMS_PER_DMI => 8,    # Cumulus
    DIMMS_PER_MBA => 4,# Cumulus
    MAX_MCS_PER_PROC => 4, # 4 MCS per Nimbus
    MBA_PER_MEMBUF => 2,
    MAX_DIMMS_PER_MBA_PORT => 2,

};

my %maxInstance = (
    "PROC"          => 4,
    "CORE"          => 24,
    "EX"            => 12,
    "EQ"            => 6,
    "ABUS"          => 3,
    "XBUS"          => 3,
    "OBUS"          => 4,
    "MCBIST"        => 2,
    "MCS"           => 4,
    "MCA"           => 8,
    "PHB"           => 6, #PHB is same as PCIE
    "PEC"           => 3, #PEC is same as PBCQ
    "PCIESWITCH"    => 2,
    "MBA"           => 16,
    "PPE"           => 51, #Only 21, but they are sparsely populated
    "PERV"          => 56, #Only 42, but they are sparsely populated
    "CAPP"          => 2,
    "SBE"           => 1,
    "OBUS_BRICK"    => 12,
    "NPU"           => 1,
    "MC"            => 2,
    "MI"            => 4,
    "DMI"           => 8,
    "OCC"           => 1,
    "NV"            => 6,
    "NX"            => 1,
    "MEMBUF"        => 8,
    "SMPGROUP"      => 8,
);
sub new
{
    my $class = shift;
    my $self  = {
        xml          => undef,
        data         => undef,
        targeting    => undef,
        enumerations => undef,
        MAX_MCS      => 0,
        UNIT_COUNTS  => undef,
        huid_idx     => undef,
        mru_idx      => undef,
        force        => 0,
        debug        => 0,
        version      => "",
        xml_version  => 0,
        errorsExist  => 0,
        NUM_PROCS    => 0,
        TOP_LEVEL    => "",
        TOPOLOGY     => undef,
        report_log   => "",
        vpd_num      => 0,
        dimm_tpos    => 0,
        MAX_MC       => 0,
        MAX_MI       => 0,
        MAX_DMI      => 0,
        DMI_FSI_MAP  => {
            '0' => '3',
            '1' => '2',
            '4' => '7',
            '5' => '6'
        }
        # TODO RTC:132549
        # DMI_FSI_MAP is a lookup table for DMI channel to FSI and ref clock.
        # It is processor specific and needs to be pulled from a
        # processor attribute instead of being hardcoded

    };
    return bless $self, $class;
}

sub setVersion
{
    my $self    = shift;
    my $version = shift;

    $self->{version} = $version;
}

sub getData
{
    my $self = shift;
    return $self->{data};
}

## loads ServerWiz XML format
sub loadXML
{
    my $self = shift;
    my $filename = shift;

    $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    print "Loading MRW XML: $filename\n";
    $self->{xml} =
      XMLin($filename,forcearray => [ 'child_id', 'hidden_child_id', 'bus',
                                      'property', 'field', 'attribute',
                                      'enumerator' ]);

    if (defined($self->{xml}->{'enumerationTypes'}))
    {
          $self->{xml_version} = 1;
    }

    $self->storeEnumerations();
    $self->storeGroups();
    $self->buildHierarchy();
    $self->prune();
    $self->buildAffinity();
    $self->{report_filename}=$filename.".rpt";
    $self->{report_filename}=~s/\.xml//g;
}

################################################
## prints out final XML for HOSTBOOT consumption

sub printXML
{
    my $self = shift;
    my $fh   = shift;
    my $t    = shift;
    my $build= shift;

    my $atTop = 0;
    if ($t eq "top")
    {
        $atTop = 1;
        $t     = $self->{targeting}->{SYS};
        print $fh "<attributes>\n";
        print $fh "<version>" . $self->{version} . "</version>\n";
    }
    if (ref($t) ne "ARRAY")
    {
        return;
    }
    for (my $p = 0; $p < scalar(@{$t}); $p++)
    {
        if (ref($t->[$p]) ne "HASH") { next; }
        my $target = $t->[$p]->{KEY};
        $self->printTarget($fh, $target, $build);
        my $children = $t->[$p];
        foreach my $u (sort(keys %{$children}))
        {
            if ($u ne "KEY")
            {
                $self->printXML($fh, $t->[$p]->{$u}, $build);
            }
        }
    }
    if ($atTop)
    {
        print $fh "</attributes>\n";
    }
}

sub printTarget
{
    my $self   = shift;
    my $fh     = shift;
    my $target = shift;
    my $build  = shift;

    my $target_ptr = $self->getTarget($target);

    if ($target eq "")
    {
        return;
    }

    print $fh "<targetInstance>\n";
    my $target_id = $self->getAttribute($target, "PHYS_PATH");
    my $target_TYPE = $self->getAttribute($target, "TYPE");
    $target_id = substr($target_id, 9);
    $target_id =~ s/\///g;
    $target_id =~ s/\-//g;

    print $fh "\t<id>" . $target_id . "</id>\n";
    if($self->getTargetType($target) eq 'unit-clk-slave')
    {
        if($target_TYPE eq 'SYSREFCLKENDPT')
        {
            print $fh "\t<type>"."unit-sysclk-slave"."</type>\n";
        }
        elsif($target_TYPE eq 'MFREFCLKENDPT')
        {
            print $fh "\t<type>"."unit-mfclk-slave"."</type>\n";
        }
    }
    elsif($self->getTargetType($target) eq 'unit-clk-master')
    {
        if($target_TYPE eq 'SYSREFCLKENDPT')
        {
            print $fh "\t<type>"."unit-sysclk-master"."</type>\n";
        }
        elsif($target_TYPE eq 'MFREFCLKENDPT')
        {
            print $fh "\t<type>"."unit-mfclk-master"."</type>\n";
        }
    }
    elsif($self->getTargetType($target) eq 'enc-node-power9')
    {
        if($target_TYPE eq 'CONTROL_NODE')
        {
            print $fh "\t<type>"."enc-controlnode-power9"."</type>\n";
        }
        else
        {
            print $fh "\t<type>" . $self->getTargetType($target) . "</type>\n";
        }
    }
    else
    {
        print $fh "\t<type>" . $self->getTargetType($target) . "</type>\n";
    }

    ## get attributes
    foreach my $attr (sort (keys %{ $target_ptr->{ATTRIBUTES} }))
    {
        $self->printAttribute($fh, $target_ptr->{ATTRIBUTES}, $attr, $build);
    }
    print $fh "</targetInstance>\n";
}

sub printAttribute
{
    my $self       = shift;
    my $fh         = shift;
    my $target_ptr = shift;
    my $attribute  = shift;
    my $build      = shift;
    my $r          = "";

    # Read the value right away so we can decide if it is even valid
    my $value = $target_ptr->{$attribute}->{default};
    if ($value eq "")
    {
        print " Targets.pm> WARNING: empty default tag for attribute : $attribute\n";
        return;
    }

    # TODO RTC: TBD
    # temporary until we converge attribute types
    my %filter;
    $filter{MODEL}                                                  = 1;
    $filter{NUMERIC_POD_TYPE_TEST}                                  = 1;
    if ($filter{$attribute} == 1)
    {
        return;
    }
    if ( $build eq "fsp" && ($attribute eq "INSTANCE_PATH" || $attribute eq "PEER_HUID"))
    {
        print $fh "\t<compileAttribute>\n";
    }
    else
    {
        print $fh "\t<attribute>\n";
    }
    print $fh "\t\t<id>$attribute</id>\n";

    if (ref($value) eq "HASH")
    {
        if (defined($value->{field}))
        {
            print $fh "\t\t<default>\n";
            foreach my $f (sort keys %{ $value->{field} })
            {
                my $v = $value->{field}->{$f}->{value};
                print $fh "\t\t\t<field><id>$f</id><value>$v</value></field>\n";
            }
            print $fh "\t\t</default>\n";
        }
    }
    else
    {
        print $fh "\t\t<default>$value</default>\n";
    }

    if ( $build eq "fsp" && ($attribute eq "INSTANCE_PATH" || $attribute eq "PEER_HUID"))
    {
        print $fh "\t</compileAttribute>\n";
    }
    else
    {
        print $fh "\t</attribute>\n";
    }
}

## stores TYPE enumeration values which is used to generate HUIDs
sub storeEnumerations
{
    my $self = shift;
    my $baseptr = $self->{xml}->{enumerationType};
    if ($self->{xml_version} == 1)
    {
        $baseptr = $self->{xml}->{enumerationTypes}->{enumerationType};
    }
    foreach my $enumType (keys(%{ $baseptr }))
    {
        foreach my $enum (
            keys(%{$baseptr->{$enumType}->{enumerator}}))
        {
            $self->{enumeration}->{$enumType}->{$enum} =
              $baseptr->{$enumType}->{enumerator}->{$enum}->{value};
        }
    }
}
sub storeGroups
{
    my $self = shift;
    foreach my $grp (keys(%{ $self->{xml}->{attributeGroups}
        ->{attributeGroup} }))
    {
        foreach my $attr (@{$self->{xml}->{attributeGroups}
            ->{attributeGroup}->{$grp}->{'attribute'}})
        {
            $self->{groups}->{$grp}->{$attr} = 1;
        }
    }
}

####################################################
## build target hierarchy recursively
##
## creates convenient data structure
## for accessing targets and busses
## Structure:
##
##{TARGETS}                                         # location of all targets
##{NSTANCE_PATH}                                    # keeps track of hierarchy
##                                                   path while iterating
##{TARGETS} -> target_name                          # specific target
##{TARGETS} -> target_name -> {TARGET}              # pointer to target data
##                                                   from XML data struture
##{TARGETS} -> target_name -> {TYPE}# special attribute
##{TARGETS} -> target_name -> {PARENT}              # parent target name
##{TARGETS} -> target_name -> {CHILDREN}            # array of children targets
##{TARGETS} -> target_name -> {CONNECTION} -> {DEST} # array of connection
##                                                     destination targets
##{TARGETS} -> target_name -> {CONNECTION} -> {BUS} # array of busses
##{TARGETS} -> target_name -> {CHILDREN}            # array of children targets
##{TARGETS} -> target_name -> {ATTRIBUTES}          # attributes
## {ENUMERATION} -> enumeration_type -> enum        # value of enumeration
## {BUSSES} -> bus_type[]                           # array of busses by
##                                                   bus_type (I2C, FSI, etc)
## {BUSSES} -> bus_type[] -> {BUS}                  # pointer to bus target
##                                                   from xml structure
## {BUSSES} -> bus_type[] -> {SOURCE_TARGET}        # source target name
## {BUSSES} -> bus_type[] -> {DEST_TARGET}          # dest target name

sub buildHierarchy
{
    my $self   = shift;
    my $target = shift;

    my $instance_path = $self->{data}->{INSTANCE_PATH};
    if (!defined $instance_path)
    {
        $instance_path = "";
    }
    my $baseptr = $self->{xml}->{'targetInstance'};
    if ($self->{xml_version} == 1)
    {
        $baseptr = $self->{xml}->{'targetInstances'}->{'targetInstance'};
    }
    if ($target eq "")
    {
        ## find system target
        foreach my $t (keys(%{$baseptr}))
        {
            if ($baseptr->{$t}->{attribute}->{TYPE}->{default} eq "SYS")
            {
                $self->{TOP_LEVEL} = $t;
                $target = $t;
            }
        }
    }
    if ($target eq "")
    {
        die "Unable to find system top level target\n";
    }
    my $old_path        = $instance_path;
    my $target_xml      = $baseptr->{$target};
    my $affinity_target = $target;
    my $key             = $instance_path . "/" . $target;

    if ($instance_path ne "")
    {
        $instance_path = "instance:" . substr($instance_path, 1);
    }
    else
    {
        $instance_path = "instance:";
    }
    $self->setAttribute($key, "INSTANCE_PATH", $instance_path);
    $self->{data}->{TARGETS}->{$key}->{TARGET} = $target_xml;
    $self->{data}->{INSTANCE_PATH} = $old_path . "/" . $target;

    ## copy attributes

    foreach my $attribute (keys %{ $target_xml->{attribute} })
    {
        my $value = $target_xml->{attribute}->{$attribute}->{default};
        if (ref($value) eq "HASH")
        {
            if (defined($value->{field}))
            {
                foreach my $f (keys %{ $value->{field} })
                {
                    my $field_val=$value->{field}{$f}{value};
                    if (ref($field_val)) {
                        $self->setAttributeField($key, $attribute, $f,"");
                    }
                    else
                    {
                        $self->setAttributeField($key, $attribute, $f,
                            $value->{field}{$f}{value});
                    }
                }
            }
            else
            {
                if ($attribute eq "FSI_MASTER_CHIP" || $attribute eq "ALTFSI_MASTER_CHIP" )
                {
                    $self->setAttribute($key, $attribute, "physical:sys-0");
                }
                else
                {
                    $self->setAttribute($key, $attribute, "");
                }
            }
        }
        else
        {
            $self->setAttribute($key, $attribute, $value);
        }
    }
    ## global attributes overwrite local
    my $settingptr = $self->{xml}->{globalSetting};
    if ($self->{xml_version} == 1)
    {
        $settingptr = $self->{xml}->{globalSettings}->{globalSetting};
    }

    foreach my $prop (keys %{$settingptr->{$key}->{property}})
    {
        my $val=$settingptr->{$key}->{property}->
                       {$prop}->{value};
        if ($val ne "")
        {
            $self->setAttribute($key, $prop, $val);
        }
    }

    ## Save busses
    if (defined($target_xml->{bus}))
    {
        foreach my $b (@{ $target_xml->{bus} })
        {
            if (ref($b->{dest_path}) eq "HASH") {
                $b->{dest_path}="";
            }
            if (ref($b->{source_path}) eq "HASH") {
                $b->{source_path}="";
            }
            my $source_target =
              $key . "/" . $b->{source_path} . $b->{source_target};

            my $dest_target = $key . "/" . $b->{dest_path} . $b->{dest_target};
            my $bus_type    = $b->{bus_type};

            push(
                @{
                    $self->{data}->{TARGETS}->{$source_target}->{CONNECTION}
                      ->{DEST}
                  },
                $dest_target
            );
            push(
                @{
                    $self->{data}->{TARGETS}->{$dest_target}->{CONNECTION}
                      ->{SOURCE}
                  },
                $source_target
            );
            push(
                @{
                    $self->{data}->{TARGETS}->{$source_target}->{CONNECTION}
                      ->{BUS}
                  },
                $b
            );
            my %bus_entry;
            $bus_entry{SOURCE_TARGET} = $source_target;
            $bus_entry{DEST_TARGET}   = $dest_target;
            $bus_entry{BUS_TARGET}    = $b;
            push(@{ $self->{data}->{BUSSES}->{$bus_type} }, \%bus_entry);
        }
    }

    foreach my $child (@{ $target_xml->{child_id} })
    {
        my $child_key = $self->{data}->{INSTANCE_PATH} . "/" . $child;
        $self->{data}->{TARGETS}->{$child_key}->{PARENT} = $key;
        push(@{ $self->{data}->{TARGETS}->{$key}->{CHILDREN} }, $child_key);
        $self->buildHierarchy($child);
    }
    foreach my $child (@{ $target_xml->{hidden_child_id} })
    {
        my $child_key = $self->{data}->{INSTANCE_PATH} . "/" . $child;
        $self->{data}->{TARGETS}->{$child_key}->{PARENT} = $key;
        push(@{ $self->{data}->{TARGETS}->{$key}->{CHILDREN} }, $child_key);
        $self->buildHierarchy($child);
    }
    $self->{data}->{INSTANCE_PATH} = $old_path;

}

##########################################################
## prunes targets that do not have a valid XML data attached to them.
## Extraneous targets may get added during building heirarchy if the
## source/destination targets in the bus are not valid target instances.

sub prune
{
    my $self = shift;

    # TODO RTC 181162: This is just a temporary solution/workaround to the wrong
    # APSS location in witherspoon XML. Need to take a call on either making
    # this an error or get rid of this function altogether when we have fixed
    # the witherspoon XML.
    foreach my $target (sort keys %{ $self->{data}->{TARGETS} })
    {
        if(not defined $self->{data}->{TARGETS}->{$target}->{TARGET})
        {
            printf("WARNING: Target instance for %s not found, deleting. ",
                    $target);
            printf("This probably indicates a bug in the source XML\n");
            delete $self->{data}->{TARGETS}->{$target};
        }
    }
}

## This function returns the position of the Node corresponding to the
## incoming target
##
sub getParentNodePos
{
    my $self = shift;
    my $target = shift;
    my $pos    = 0;

    my $parent = $target;
    while($self->getType($parent) ne "NODE")
    {
       $parent = $self->getTargetParent($parent);
    }
    if($parent ne "")
    {
      $pos = $self->{data}->{TARGETS}{$parent}{TARGET}{position};
      #Reducing one to account for control node
      if($pos > 0)
      {
        $pos = $pos - 1;
      }
    }
    return $pos;
}

##########################################################
## traces busses and builds affinity hierarchy
## HOSTBOOT expected hierarchy: sys/node/proc/<unit>
##                              sys/node/proc/mcs/membuf/<unit>
##                              sys/node/proc/mcs/membuf/mba/dimm
## This function also sets the common attributes for all the targets
## Common attributes include:
##  - FAPI_NAME
##  - PHYS_PATH
##  - AFFINITY_PATH
##  - ORDINAL_ID
##  - HUID
my $multiNode = 0;
sub buildAffinity
{
    my $self = shift;
    my $node            = -1;
    my $proc            = -1;
    my $tpm             = -1;
    my $ucd             = -1;
    my $bmc             = -1;
    my $sys_phys        = "";
    my $node_phys       = "";
    my $node_aff        = "";
    my $sys_pos         = 0; # There is always a single system target
    my $mcbist          = -1;
    my $num_mc          = 0 ;
    my @tpm_list        = (); # The list of TPMs found on the system
    my @ucd_list        = (); # The list of UCDs found on the system

    $multiNode = 0;

    $self->{membuf_inst_num}=0;

    ## count children target types
    foreach my $target (sort keys %{ $self->{data}->{TARGETS} })
    {
        my $children = $self->getTargetChildren($target);
        if ($children ne "") {
             foreach my $child (@{ $children })
             {
                  my $type = $self->getType($child);
                  $self->{UNIT_COUNTS}->{$target}->{$type}++;
             }
        }
    }

    foreach my $target (sort keys %{ $self->{data}->{TARGETS} })
    {
        my $target_ptr  = $self->{data}->{TARGETS}{$target};
        my $type        = $self->getType($target);
        my $type_id     = $self->getEnumValue("TYPE", $type);
        my $pos         = $self->{data}->{TARGETS}{$target}{TARGET}{position};

        if ($type_id eq "") { $type_id = 0; }

        if ($type eq "SYS")
        {
            $proc = -1;
            $node = -1;
            $self->{targeting}{SYS}[0]{KEY} = $target;

            #SYS target has PHYS_PATH and AFFINITY_PATH defined in the XML
            #Also, there is no HUID for SYS
            $self->setAttribute($target,"FAPI_NAME",$self->getFapiName($type));
            $self->setAttribute($target,"FAPI_POS",      $sys_pos);
            $self->setAttribute($target,"ORDINAL_ID",    $sys_pos);
            $sys_phys = "sys-0"; # just hardcode this as it does not change
        }
        elsif ($type eq "NODE")
        {
            $proc                    = -1;
            $self->{membuf_inst_num} = 0;
            $node++;

            if($node > 0)
            {
                $multiNode = 1;
                #reset the dimm index number across nodes
                $self->{dimm_tpos} = 0;
            }
            else
            {
                $multiNode = 0;
            }

            $node_phys = "physical:".$sys_phys."/node-$node";
            $node_aff  = "affinity:".$sys_phys."/node-$node";

            $self->{targeting}{SYS}[0]{NODES}[$node]{KEY} = $target;

            $self->setHuid($target, $sys_pos, $node);
            $self->setAttribute($target, "FAPI_NAME",$self->getFapiName($type));
            $self->setAttribute($target, "FAPI_POS",      $node);
            $self->setAttribute($target, "PHYS_PATH",     $node_phys);
            $self->setAttribute($target, "AFFINITY_PATH", $node_aff);

            if($pos > 0) #to handle control node in Fleetwood
            {
                $pos = $pos - 1;
            }
            $self->setAttribute($target, "ORDINAL_ID",    $pos);

        }
        elsif ($type eq "TPM")
        {
            $tpm++;
            push @tpm_list, $target;

            $self->{targeting}{SYS}[0]{NODES}[$node]{TPMS}[$tpm]{KEY} = $target;

            my $tpm_phys = $node_phys . "/tpm-$tpm";

            $self->setHuid($target, $sys_pos, $node);
            $self->setAttribute($target, "FAPI_NAME",$self->getFapiName($type));
            $self->setAttribute($target, "FAPI_POS",      $pos);
            # NOTE: Affinity Path is set after this loop so that all procs have
            #       already been dealt with.
            $self->setAttribute($target, "PHYS_PATH",     $tpm_phys);
            $self->setAttribute($target, "ORDINAL_ID",    $tpm);
        }
        elsif ($type eq "POWER_SEQUENCER")
        {

            my $target_type = $self->getTargetType($target);

            # Strip off the chip- part of the target type name
            $target_type =~ s/chip\-//g;

            # Currently only UCD9090 and UCD90120A on FSP systems are supported.
            # Skip over all other UCD types.
            if (($target_type ne "UCD9090")
               && ($target_type ne "UCD90120A"))
            {
                next;
            }

            $ucd++;
            push(@ucd_list, $target);

            $self->{targeting}{SYS}[0]{NODES}[$node]{UCDS}[$ucd]{KEY} = $target;

            my $ucd_phys = $node_phys . "/power_sequencer-$ucd";

            $self->setHuid($target, $sys_pos, $node);
            # NOTE: Affinity Path is set after this loop so that all procs have
            #       already been dealt with.
            $self->setAttribute($target, "PHYS_PATH",     $ucd_phys);
            $self->setAttribute($target, "ORDINAL_ID",    $ucd);
            # @TODO RTC 201991: remove these overrides when the MRW is updated
            $self->setAttribute($target, "CLASS", "ASIC");
            $self->deleteAttribute($target, "POSITION");
            $self->deleteAttribute($target, "FRU_ID");
        }
        elsif ($type eq "BMC")
        {
            $bmc++;

            $self->{targeting}{SYS}[0]{NODES}[$node]{BMC}[$bmc]{KEY} = $target;
            my $bmc_phys = $node_phys . "/bmc-$bmc";
            my $bmc_aff  = $node_aff  . "/bmc-$bmc";

            $self->setHuid($target, $sys_pos, $bmc);
            $self->setAttribute($target, "FAPI_NAME",$self->getFapiName($type));
            $self->setAttribute($target, "FAPI_POS",      $pos);
            $self->setAttribute($target, "PHYS_PATH",     $bmc_phys);
            $self->setAttribute($target, "AFFINITY_PATH", $bmc_aff);
            $self->setAttribute($target, "ORDINAL_ID",    $bmc);

        }
        elsif ($type eq "MCS")
        {
            $self->setAttribute($target, "VPD_REC_NUM", 0);
        }
        elsif ($type eq "MCA")
        {
            my $ddrs = $self->findConnections($target,"DDR4","");
            $self->processMcaDimms($ddrs, $sys_pos, $node_phys, $node, $proc);
        }

        elsif ($type eq "PROC")
        {
            my $socket = $target;
            while($self->getAttribute($socket,"CLASS") ne "CONNECTOR")
            {
               $socket = $self->getTargetParent($socket);
            }
            if($socket ne "")
            {
              $proc = $self->getAttribute($socket,"POSITION");
            }
            else
            {
              die "Cannot find socket connector for $target\n";
            }
            my $num_mcs = 0;
            my $num_mi = 0;
            my $num_dmi  = 0;
            ### count number of MCSs
            foreach my $unit (@{ $self->{data}->{TARGETS}{$target}{CHILDREN} })
            {
                my $unit_type = $self->getType($unit);
                if ($unit_type eq "MCBIST")
                {
                    $num_mcs+=2;  # 2 MCS's per MCBIST
                }
                if ($unit_type eq "MC")
                {
                    $num_mc++;
                    $num_mi += 2; # 2 MI's per MC
                    $num_dmi+=4;  # 2DMI's per MI & 4 DMI per MC
                }
            }
            if ($num_mcs > $self->{MAX_MCS})
            {
                $self->{MAX_MCS} = $num_mcs;
            }
            if ($num_mc > $self->{MAX_MC})
            {
                $self->{MAX_MC} = $num_mc;
            }
            if ($num_mi > $self->{MAX_MI})
            {
                $self->{MAX_MI} = $num_mi;
            }
            if ($num_dmi > $self->{MAX_DMI})
            {
                $self->{MAX_DMI} = $num_dmi;
            }

            if($self->{NUM_PROCS_PER_NODE} < ($proc + 1))
            {
                $self->{NUM_PROCS_PER_NODE} = $proc + 1;
            }

            $self->{targeting}->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{KEY} =
                $target;

            #my $socket=$self->getTargetParent($self->getTargetParent($target));
            my $parent_affinity = $node_aff  . "/proc-$proc";
            my $parent_physical = $node_phys . "/proc-$proc";

            my $fapi_name = $self->getFapiName($type, $node, $proc);
            #unique offset per system
            my $nodepos = $self->getParentNodePos($target) ;
            my $proc_ordinal_id = ($nodepos * $maxInstance{$type}) + $proc;

            # Ensure processor HUID is node-relative
            $self->{huid_idx}->{$type} = $proc;
            $self->setHuid($target, $sys_pos, $node);
            $self->setAttribute($target, "FAPI_NAME",       $fapi_name);
            $self->setAttribute($target, "PHYS_PATH",       $parent_physical);
            $self->setAttribute($target, "AFFINITY_PATH",   $parent_affinity);
            $self->setAttribute($target, "ORDINAL_ID",      $proc_ordinal_id);
            $self->setAttribute($target, "POSITION",        $proc);

            $self->setAttribute($target, "FABRIC_GROUP_ID",
                  $self->getAttribute($socket,"FABRIC_GROUP_ID"));
            $self->setAttribute($target, "FABRIC_CHIP_ID",
                  $self->getAttribute($socket,"FABRIC_CHIP_ID"));
            $self->setAttribute($target, "VPD_REC_NUM",    $proc);
             $self->setAttribute($target, "FAPI_POS",
                 $self->getAttribute($socket,"FABRIC_GROUP_ID") *
                 NUM_PROCS_PER_GROUP +
                 $self->getAttribute($socket,"FABRIC_CHIP_ID"));

            # Both for FSP and BMC based systems, it's good  enough
            # to look for processor with active LPC bus connected
            $self->log($target,"Finding master proc (looking for LPC Bus)");
            my $lpcs=$self->findConnections($target,"LPC","");
            if ($lpcs ne "")
            {
                $self->log ($target, "Setting $target as ACTING_MASTER");
                $self->setAttribute($target, "PROC_MASTER_TYPE",
                                  "ACTING_MASTER");
                $self->setAttribute($target, "PROC_SBE_MASTER_CHIP", "TRUE");
            }
            else
            {
               $self->setAttribute($target, "PROC_MASTER_TYPE",
                               "NOT_MASTER");
               $self->setAttribute($target, "PROC_SBE_MASTER_CHIP", "FALSE");
            }

            $self->iterateOverChiplets($target, $sys_pos, $node, $proc);

            $self->processMc($target, $sys_pos, $node, $proc, $parent_affinity,
                             $parent_physical, $node_phys);
        }
    } # foreach

    # Now populate the affinity path of each TPM. Do this after the main loop
    # because we need to make sure that all of the procs have been processed
    {
        my $type = "";
        if (@tpm_list != 0)
        {
            $type = $self->getAttribute($tpm_list[0], "TYPE");
        }
        $tpm = 0;
        foreach my $tpm_target (@tpm_list)
        {
            my $affinity_path = $self->getParentProcAffinityPath($tpm_target,
                                                                 $tpm,
                                                                 $type);
            $self->
               setAttribute($tpm_target, "AFFINITY_PATH", $affinity_path);
            $tpm++;
        }
    }
    # Populate the affinity path of each UCD. Do this after the main loop
    # because we need to make sure that all of the procs have been processed
    {
        my $type = "";
        if (@ucd_list != 0)
        {
            $type = $self->getAttribute($ucd_list[0], "TYPE");
        }
        $ucd = 0;
        foreach my $ucd_target (@ucd_list)
        {
            my $affinity_path = $self->getParentProcAffinityPath($ucd_target,
                                                                 $ucd,
                                                                 $type);
            $self->
               setAttribute($ucd_target, "AFFINITY_PATH", $affinity_path);
            $ucd++;
        }
    }
}

# Get the affinity path of the passed target. The affinity path is the physical
# path of the target's I2C master which for this function is the parent
# processor with chip unit number appended.
sub getParentProcAffinityPath
{
    my $self   = shift;
    my $target = shift;
    my $chip_unit = shift;
    my $type_name = shift;

    # Make sure the type_name is all upper-case
    my $type_name = uc $type_name;

    # Create a lower-case version of the type name
    my $lc_type_name = lc $type_name;

    my $affinity_path = "";

    # Only get affinity path for supported types.
    if(($type_name ne "TPM")
      && ($type_name ne "POWER_SEQUENCER"))
    {
        die "Attempted to get parent processor affinity path" .
            " on invalid target ($type_name)";
    }

    my $parentProcsPtr = $self->findDestConnections($target, "I2C", "");

    if($parentProcsPtr eq "")
    {
        $affinity_path = "affinity:sys-0/node-0/proc-0/" .
                         "$lc_type_name-$chip_unit";
    }
    else
    {
        my @parentProcsList = @{$parentProcsPtr->{CONN}};
        my $numConnections = scalar @parentProcsList;

        if($numConnections != 1)
        {
            die "Incorrect number of parent procs ($numConnections)".
                " found for $type_name$chip_unit";
        }

        # The target is only connected to one proc, so we can fetch just the
        # first connection.
        my $parentProc = $parentProcsList[0]{SOURCE_PARENT};
        if($self->getAttribute($parentProc, "TYPE") ne "PROC")
        {
            die "Upstream I2C connection to $type_name" .
                "$chip_unit is not type PROC!";
        }

        # Look at the I2C master's physical path; replace
        # "physical" with "affinity" and append chip unit
        $affinity_path = $self->getAttribute($parentProc, "PHYS_PATH");
        $affinity_path =~ s/physical/affinity/g;
        $affinity_path = $affinity_path . "/$lc_type_name-$chip_unit";
    }

    return $affinity_path;
}

sub iterateOverChiplets
{
    my $self     = shift;
    my $target   = shift;
    my $sys      = shift;
    my $node     = shift;
    my $proc     = shift;
    my $tgt_ptr        = $self->getTarget($target);
    my $tgt_type       = $self->getType($target);

    my $target_children  = $self->getTargetChildren($target);

    if ($target_children eq "")
    {
        return "";
    }
    else
    {
        my @phb_array = ();
        my @non_connected_phb_array = ();
        foreach my $child (@{ $self->getTargetChildren($target) })
        {
            # For PEC children, we need to remove duplicate PHB targets
            if ($tgt_type eq "PEC")
            {
                my $pec_num = $self->getAttribute($target, "CHIP_UNIT");
                $self->setAttribute($child,"AFFINITY_PATH",$self
                    ->getAttribute($target,"AFFINITY_PATH"));
                $self->setAttribute($child,"PHYS_PATH",$self
                    ->getAttribute($target,"PHYS_PATH"));

                foreach my $phb (@{ $self->getTargetChildren($child) })
                {
                    my $phb_num = $self->getAttribute($phb, "CHIP_UNIT");
                    foreach my $pcibus (@{ $self->getTargetChildren($phb) })
                    {
                        # We need to ensure that all PHB's get added to the
                        # MRW, but PHB's with busses connected take priority
                        # and we cannot have duplicate PHB targets in the MRW.

                        # We processes every PHB pci bus config starting with
                        # the config with the fewest PHB's. For PEC2 we start
                        # with PHB3_x16. If a bus is not connected to that PHB
                        # we add it to the phb_array anyway so the target will
                        # be populated in the HB MRW. As we processes the later
                        # PHB configs under PEC2 we may find that PHB3 has a
                        # bus connected to it. Since the bus config takes
                        # priority over the target that was already added to
                        # the phb_array, we just overwrite that phb_array entry
                        # with the PHB that has a bus connected.

                        if (($self->getNumConnections($pcibus) > 0) &&
                                (@phb_array[$phb_num] eq ""))
                        {
                            # This PHB does have a bus connection and the slot
                            # is empty. We must add it to the PHB array
                            @phb_array[$phb_num] = $phb;
                        }
                        elsif (($self->getNumConnections($pcibus) == 0) &&
                                   (@phb_array[$phb_num] eq ""))
                        {
                            # This PHB does NOT have a bus connection. It's
                            # slot is still empty, so we must add it to the
                            # array so every PHB has a target in the MRW.
                            @phb_array[$phb_num] = $phb;

                            # Also add it to the non_connected_phb_array so we
                            # can examine later it if needs to be overriden.
                            @non_connected_phb_array[$phb_num] = $phb;
                        }
                        elsif (($self->getNumConnections($pcibus) > 0) &&
                                   (@phb_array[$phb_num] ne ""))
                        {
                             # This PHB has a connection, but the slot has
                             # already been filled by another PHB. We need to
                             # check if it was a non connected PHB
                             if(@non_connected_phb_array[$phb_num] ne "")
                             {
                                 # The previous connection in the PHB elecment
                                 # is not connected to a bus. We should
                                 # override it
                                 @phb_array[$phb_num] = $phb;
                             }
                             else
                             {
                                 # This is our "bug" scenerio. We have found a
                                 # connection, but that PHB element is already
                                 # filled in the array. We need to kill the
                                 # program.
                                 printf("Found a duplicate connection for PEC %s PHB %s.\n",$pec_num,$phb_num);
                                 die "Duplicate PHB bus connection found\n";
                             }
                        }
                    }
                }
            }
            else
            {
                my $unit_ptr        = $self->getTarget($child);
                my $unit_type       = $self->getType($child);

                #System XML has some sensor target as hidden children
                #of targets. We don't care for sensors in this function
                #So, we can avoid them with this conditional

                if ($unit_type ne "PCI" && $unit_type ne "NA" &&
                    $unit_type ne "FSI" && $unit_type ne "PSI" &&
                    $unit_type ne "SYSREFCLKENDPT" && $unit_type ne "MFREFCLKENDPT")
                {
                    #set common attrs for child
                    $self->setCommonAttrForChiplet($child, $sys, $node, $proc);
                    $self->iterateOverChiplets($child, $sys, $node, $proc);
                }
            }
        }
        my $size = @phb_array;
        # For every entry in the PHB array, if there is a PHB in its slot
        # we add that PHB target to the MRW.

        # We process PEC's individually, so we need to make sure the PHB slot
        # has a PHB in it. eg: phb_array[0] will be empty for when processing
        # PEC1 and 2 as there is no PHB0 configured for those PECs.
        for (my $i = 0; $i < $size; $i++)
        {
            if (@phb_array[$i] ne "")
            {
                $self->setCommonAttrForChiplet
                    (@phb_array[$i], $sys, $node, $proc);
            }
        }
    }
}

sub setCommonAttrForChiplet
{
    my $self        = shift;
    my $target      = shift;
    my $sys         = shift;
    my $node        = shift;
    my $proc        = shift;

    my $tgt_ptr        = $self->getTarget($target);
    my $tgt_type       = $self->getType($target);

    push(@{$self->{targeting}
            ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{$tgt_type}},
            { 'KEY' => $target });

    #This is a static variable. Persists over time
    #everything that is a grand_children of proc

    state %grand_children;
    if (not %grand_children)
    {
        $grand_children{"EX"}    = 1;
        $grand_children{"CORE"}  = 1;
        $grand_children{"MCS"}   = 1;
        $grand_children{"MCA"}   = 1;
        $grand_children{"MC"}    = 1;
        $grand_children{"MI"}    = 1;
        $grand_children{"DMI"}   = 1;
    }

    my $pos             = $self->getAttribute($target, "CHIP_UNIT");
    my $unit_pos        = $pos;

    #HB expects chiplets' positions in AFFINITY_PATH to be relative to the
    #parent, serverwiz outputs it unique/absolute.
    #Since, in P9, each of the chiplets only have
    #up to two children (each eq has 2 ex, each ex has 2 cores, each mcbist has
    #two mcs, etc), we can simply calculate this by (absolute_Pos%2)
    #CHIP_UNIT is absolute position
    if ($grand_children{$tgt_type} eq 1)
    {
        $unit_pos = $pos%2;
    }
    elsif ($tgt_type eq "OBUS_BRICK")
    {
        $unit_pos = $pos%3;
    }
    elsif ($tgt_type eq "SMPGROUP")
    {
        # SMPGROUP inherits the same INSTANCE_PATH as its parent OBUS which
        # messes up the HUID -NID mapping, hence adding the below line
        $self->setAttribute($target, "INSTANCE_PATH", $target);
        $unit_pos = $pos%2;
    }

    my $parent_affinity = $self->getAttribute(
                          $self->getTargetParent($target),"AFFINITY_PATH");
    my $parent_physical = $self->getAttribute(
                          $self->getTargetParent($target),"PHYS_PATH");

    my $affinity_path   = $parent_affinity . "/" . lc $tgt_type ."-". $unit_pos;
    my $physical_path   = $parent_physical . "/" . lc $tgt_type ."-". $unit_pos;

    my $fapi_name       = $self->getFapiName($tgt_type, $node, $proc, $pos);

    # Calculate a system wide offset
    my $sys_offset = (($node * $maxInstance{"PROC"} + $proc ) *
        $maxInstance{$tgt_type}) + $pos;

    # Calculate a node specific offset
    my $node_offset = ($proc * $maxInstance{$tgt_type}) + $pos;

    # HUID is node based so use that offset
    $self->{huid_idx}->{$tgt_type} = $node_offset;
    $self->setHuid($target, $sys, $node);
    $self->setAttribute($target, "FAPI_NAME",       $fapi_name);
    $self->setAttribute($target, "PHYS_PATH",       $physical_path);
    $self->setAttribute($target, "AFFINITY_PATH",   $affinity_path);
    $self->setAttribute($target, "ORDINAL_ID",      $sys_offset);
    $self->setAttribute($target, "FAPI_POS",        $sys_offset);
    $self->setAttribute($target, "REL_POS",         $unit_pos);

    my $pervasive_parent= getPervasiveForUnit("$tgt_type$pos");
    if ($pervasive_parent ne "")
    {
        my $perv_parent_val =
            "physical:sys-$sys/node-$node/proc-$proc/perv-$pervasive_parent";
        $self->setAttribute($target, "PARENT_PERVASIVE", $perv_parent_val);
    }
}

sub getFapiName
{
    my $self        = shift;
    my $target      = shift;
    my $node        = shift;
    my $chipPos     = shift;
    my $chipletPos  = shift;

    if ($target eq "")
    {
        die "getFapiName: ERROR: Please specify a taget name\n";
    }

    #This is a static variable. Persists over time
    state %nonFapiTargets;
    if (not %nonFapiTargets)
    {
        $nonFapiTargets{"NODE"}  = "NA";
        $nonFapiTargets{"TPM"}   = "NA";
        $nonFapiTargets{"NVBUS"} = "NA";
        $nonFapiTargets{"OCC"}   = "NA";
        $nonFapiTargets{"NPU"}   = "NA";
        $nonFapiTargets{"BMC"}   = "NA";
    }

    if ($nonFapiTargets{$target} eq "NA")
    {
        return $nonFapiTargets{$target};
    }
    elsif ($target eq "SYS")
    {
        return "k0";
    }
    elsif ($target eq "PROC" || $target eq "DIMM" || $target eq "MEMBUF")
    {
        if ($node eq "" || $chipPos eq "")
        {
            die "getFapiName: ERROR: Must specify node and chipPos for $target
                 current node: $node, chipPos: $chipPos\n";
        }
        my $chip_name;
        if ($target eq "PROC")
        {
            $chip_name = "pu";
        }
        else
        {
            $chip_name = lc $target;
        }

        my $fapi_name = sprintf("%s:k0:n%d:s0:p%02d",$chip_name,$node,$chipPos);
        return $fapi_name;
    }
    else
    {
        if ($node eq "" || $chipPos eq "" || $chipletPos eq "")
        {
            die "getFapiName: ERROR: Must specify node, chipPos,
                 chipletPos for $target. Current node: $node, chipPos: $chipPos
                 chipletPos: $chipletPos\n";
        }

        $target = lc $target;

        my $fapi_name;

        if ($target eq "mba" || $target eq "l4")
        {
          $fapi_name = sprintf("membuf.$target:k0:n%d:s0:p%02d:c%d",
                            $node, $chipPos, $chipletPos);
        }
        else
        {
            $fapi_name = sprintf("pu.$target:k0:n%d:s0:p%02d:c%d",
                            $node, $chipPos, $chipletPos);
        }
        return $fapi_name;
    }
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
        for my $core (0..$maxInstance{"CORE"}-1)
        {
            $unitToPervasive{"CORE$core"} = PERVASIVE_PARENT_CORE_OFFSET+$core;
        }
        for my $eq (0..$maxInstance{"EQ"}-1)
        {
            $unitToPervasive{"EQ$eq"} = PERVASIVE_PARENT_EQ_OFFSET + $eq;
        }
        for my $xbus (0..$maxInstance{"XBUS"}-1)
        {
            $unitToPervasive{"XBUS$xbus"} = PERVASIVE_PARENT_XBUS_OFFSET;
        }
        for my $obus (0..$maxInstance{"OBUS"}-1)
        {
            $unitToPervasive{"OBUS$obus"} = PERVASIVE_PARENT_OBUS_OFFSET+$obus;
        }
        for my $capp (0..$maxInstance{"CAPP"}-1)
        {
            $unitToPervasive{"CAPP$capp"} = 2 * ($capp+1);
        }
        for my $mcbist (0..$maxInstance{"MCBIST"}-1)
        {
            $unitToPervasive{"MCBIST$mcbist"} =
                PERVASIVE_PARENT_MCBIST_OFFSET + $mcbist;
        }
        for my $mcs (0..$maxInstance{"MCS"}-1)
        {
            $unitToPervasive{"MCS$mcs"} =
                PERVASIVE_PARENT_MCS_OFFSET + ($mcs > 1);
        }
        for my $mca (0..$maxInstance{"MCA"}-1)
        {
            $unitToPervasive{"MCA$mca"} =
                PERVASIVE_PARENT_MCA_OFFSET + ($mca > 3);
        }
        for my $mc (0..$maxInstance{"MC"}-1)
        {
            $unitToPervasive{"MC$mc"} =
                PERVASIVE_PARENT_MC_OFFSET + $mc;
        }
        for my $mi (0..$maxInstance{"MI"}-1)
        {
            $unitToPervasive{"MI$mi"} =
                PERVASIVE_PARENT_MI_OFFSET + ($mi > 1);
        }
        for my $dmi (0..$maxInstance{"DMI"}-1)
        {
            $unitToPervasive{"DMI$dmi"} =
                PERVASIVE_PARENT_DMI_OFFSET + ($dmi > 3);
        }
        for my $pec (0..$maxInstance{"PEC"}-1)
        {
            $unitToPervasive{"PEC$pec"} =
                PERVASIVE_PARENT_PEC_OFFSET + $pec;
        }
        for my $phb (0..$maxInstance{"PHB"}-1)
        {
            $unitToPervasive{"PHB$phb"} =
                PERVASIVE_PARENT_PHB_OFFSET + ($phb>0) + ($phb>2);
        }
        my $offset = 0;
        for my $obrick (0..$maxInstance{"OBUS_BRICK"}-1)
        {
            $offset += (($obrick%3 == 0) && ($obrick != 0)) ? 1 : 0;
            $unitToPervasive{"OBUS_BRICK$obrick"}
                = PERVASIVE_PARENT_OBUS_OFFSET + $offset;
        }
        for my $npu (0..$maxInstance{"NPU"}-1)
        {
            $unitToPervasive{"NPU$npu"} = PERVASIVE_PARENT_NPU_OFFSET;
        }
    }

    my $pervasive = "";
    if(exists $unitToPervasive{$unit})
    {
        $pervasive = $unitToPervasive{$unit};
    }

    return $pervasive
}
sub processMcaDimms
{
    my $self        = shift;
    my $ddrs        = shift;
    my $sys         = shift;
    my $node_phys   = shift;
    my $node        = shift;
    my $proc        = shift;

    if ($ddrs ne "")
    {
        #There should be 2 Connections
        #Each MCA has 2 ddr channels
        foreach my $dimms (@{$ddrs->{CONN}})
        {
            my $ddr = $dimms->{SOURCE};
            my $dimm=$dimms->{DEST_PARENT};

            #proc->mcbist->mcs->mca->ddr
            my $mca_target          = $self->getTargetParent($ddr);
            my $mcs_target          = $self->getTargetParent($mca_target);
            my $mcbist_target       = $self->getTargetParent($mcs_target);
            my $proc_target         = $self->getTargetParent($mcbist_target);
            my $dimm_connector_tgt  = $self->getTargetParent($dimm);

            #Get the loc code from connector and update to dimm targ
            my $loc_code = $self->getAttribute($dimm_connector_tgt,"LOCATION_CODE");

            my $mca     = $self->getAttribute($mca_target,       "CHIP_UNIT")%2;
            my $mcs     = $self->getAttribute($mcs_target,       "CHIP_UNIT")%2;
            my $mcbist  = $self->getAttribute($mcbist_target,    "CHIP_UNIT");
            my $dimm_pos= $self->getAttribute($dimm_connector_tgt,"POSITION");

            #The port/dimm attributes have been swizzled too many times and
            # now they no longer make sense.  Until everyone is on the same
            # page we will replicate everything as needed.
            my $dimm_num = 0;
            my $port_num = 0; # MCA only has 1 port

            # Eventually we will converge on a generic name for all
            #  configurations that the MRW will use.
            if( !$self->isBadAttribute($ddr, "POS_ON_MEM_PORT") )
            {
                $dimm_num = $self->getAttribute($ddr,"POS_ON_MEM_PORT");
            }
            # Legacy OP systems are using MBA_PORT to represent the dimm
            #  position within the port, going to remap that to keep that
            #  support in place.
            elsif( !$self->isBadAttribute($ddr, "MBA_PORT") )
            {
                $dimm_num = $self->getAttribute($ddr,"MBA_PORT");
            }
            else
            {
                print "ERROR: No port specified for dimm $ddr\n";
                $self->myExit(4);
            }

            # Write out all the attributes that someone might still be using
            $self->setAttribute($dimm, "CEN_MBA_PORT",$port_num); #unused
            $self->setAttribute($dimm, "MBA_PORT",$port_num); #legacy
            $self->setAttribute($dimm, "MEM_PORT",$port_num); #converged
            $self->setAttribute($dimm, "CEN_MBA_DIMM",$dimm_num); #unused
            $self->setAttribute($dimm, "MBA_DIMM",$dimm_num); #legacy
            $self->setAttribute($dimm, "POS_ON_MEM_PORT",$dimm_num); #converged


            $self->setAttribute($dimm, "AFFINITY_PATH",
                $self->getAttribute($mcbist_target, "AFFINITY_PATH")
             . "/mcs-$mcs/mca-$mca/dimm-$dimm_num"
            );

            $self->setAttribute($dimm, "PHYS_PATH",
                $node_phys . "/dimm-" . $dimm_pos);
            my $type       = $self->getType($dimm);

            $self->setAttribute($dimm, "ORDINAL_ID",$dimm_pos);
            $self->setAttribute($dimm, "POSITION",  $dimm_pos);
            $self->setAttribute($dimm, "VPD_REC_NUM", $dimm_pos);
            $self->setAttribute($dimm, "REL_POS", $dimm_num);
            $self->setAttribute($dimm, "LOCATION_CODE",$loc_code);

            ## set FAPI_POS for dimm
            my $DIMM_PER_MCA = 2;
            my $mca_pos = $self->getAttribute($mca_target,"FAPI_POS");
            my $dimm_pos = ($mca_pos * $DIMM_PER_MCA) +
              $self->getAttribute($dimm,"REL_POS");

            $self->setAttribute($dimm,"FAPI_NAME",
                    $self->getFapiName($type, $node, $dimm_pos));

            $self->setAttribute($dimm, "FAPI_POS",  $dimm_pos);

            $self->{huid_idx}->{$type} = $dimm_pos;
            $self->setHuid($dimm, $sys, $node);

            $self->{targeting}
                  ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{MCBISTS}[$mcbist]
                    {MCSS}[$mcs]{MCAS}[$mca]{DIMMS}[$dimm_pos]{KEY}
                    = $dimm;
        }

    }

}

sub processMc
{

    my $self     = shift;
    my $target   = shift;
    my $sys      = shift;
    my $node     = shift;
    my $proc     = shift;
    my $parent_affinity = shift;
    my $parent_physical = shift;
    my $node_phys       = shift;

    foreach my $proc_child (@{ $self->getTargetChildren($target) })
    {
       my $tgt_type       = $self->getType($proc_child);

       if($tgt_type eq "MC")
       {
            my $mc =  $proc_child;

            my $mc_num =  $self->getAttribute($mc, "CHIP_UNIT");

            foreach my $mi (@{ $self->getTargetChildren($mc) })
            {
                my $mi_num = $self->getAttribute($mi, "CHIP_UNIT");

                foreach my $dmi (@{ $self->getTargetChildren($mi) })
                {
                    my $dmi_num = $self->getAttribute($dmi, "CHIP_UNIT");

                    my $membufnum = $proc * $self->{MAX_DMI} + $dmi_num;

                    my $aff_path = $self->getAttribute($dmi, "AFFINITY_PATH");

                    ## Find connected membufs
                    my $membuf_dmi = $self->{data}->{TARGETS}{$dmi}{CONNECTION}{DEST}[0];
                    if (defined($membuf_dmi))
                    {
                        ## found membuf connected
                        my $membuf = $self->{data}->{TARGETS}{$membuf_dmi}{PARENT};
                        $self->setAttribute($membuf, "POSITION",$membufnum);
                        $self->setAttribute($membuf, "AFFINITY_PATH",
                                            $aff_path . "/membuf-$membufnum");

                        my $membuf_type = $self->getType($membuf);

                        my $memCardOffset = $proc * $maxInstance{"MC"} + $mc_num;

                        $self->setAttribute($membuf, "PHYS_PATH",
                            $node_phys . "/membuf-$membufnum");

                        my $parent_physical = $self->getAttribute($membuf, "PHYS_PATH");

                        $self->setAttribute($membuf,"FAPI_NAME",
                                     $self->getFapiName($membuf_type, $node, $membufnum));

                        my $fapi_pos = (($node * $maxInstance{"PROC"}) + $proc ) * $self->{MAX_DMI} + $dmi_num;

                        $self->setAttribute($membuf, "FAPI_POS",  $fapi_pos);
                        $self->setAttribute($membuf, "ORDINAL_ID", $fapi_pos);

                        $self->setAttribute($membuf, "REL_POS", $membufnum);
                        $self->setAttribute($membuf, "POSITION", $membufnum);

                        # It's okay to hard code these here because the code fixes it as needed
                        # This is hardcoded for proc target as well.
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "useSbeScom","0");
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "useI2cScom","0");
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "useFsiScom","1");
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "reserved",   "0");
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "useInbandScom", "0");
                        $self->setAttributeField($membuf, "SCOM_SWITCHES", "useXscom", "0");

                        my $riser_card_conn = $self->getTargetParent($self->getTargetParent($membuf));
                        my $riser_card_pos = $self->getAttribute($riser_card_conn,"POSITION");
                        $self->setAttribute($membuf, "VPD_REC_NUM", $riser_card_pos);

                        ## get the dmi bus
                        my $dmi_bus = $self->{data}->{TARGETS}{$dmi}{CONNECTION}{BUS}[0];

                        # copy DMI bus attributes to membuf
                        $self->setAttribute($dmi, "EI_BUS_TX_LANE_INVERT",
                            $dmi_bus->{bus_attribute}->{PROC_TX_LANE_INVERT}->{default});
                        $self->setAttribute($membuf, "EI_BUS_TX_LANE_INVERT",
                            $dmi_bus->{bus_attribute}->{MEMBUF_TX_LANE_INVERT}->{default});

                        ## auto setup FSI assuming schematic symbol.  If FSI busses are
                        ## defined in serverwiz2, this will be overridden
                        ## in the schematic symbol, the fsi port num matches dmi ref clk num

                        my $fsi_port = $self->{DMI_FSI_MAP}->{$dmi};
                        my $proc_key =
                            $self->{targeting}->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{KEY};
                        my $proc_path = $self->getAttribute($proc_key,"PHYS_PATH");
                        $self->setFsiAttributes($membuf,"FSICM",0,$proc_path,$fsi_port,0);

                        # HUID needs to be node relative
                        $self->{huid_idx}->{$membuf_type} = $membufnum;
                        $self->setHuid($membuf, $sys, $node);
                        $self->{targeting}
                          ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{MC}[$mc]{MI}[$mi]
                          {DMI}[$dmi] {MEMBUFS}[$membufnum]{KEY} = $membuf;

                        $self->setAttribute($membuf, "ENTITY_INSTANCE",
                               $self->{membuf_inst_num});
                               $self->{membuf_inst_num}++;
                        ## get the mbas
                        foreach my $membuf_child (@{ $self->{data}->{TARGETS}{$membuf}{CHILDREN} })
                        {
                            my $childType = $self->getType($membuf_child);
                            my $membuf_physical = $self->getAttribute(
                                                    $self->getTargetParent($membuf_child),"PHYS_PATH");
                            my $membuf_aff = $self->getAttribute(
                                                    $self->getTargetParent($membuf_child),"AFFINITY_PATH");

                            ## need to not hardcard the subunits
                            if ($childType eq "L4")
                            {
                                $self->{targeting}
                                  ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{MC}[$mc]{MI}[$mi]
                                    {DMI}[$dmi]{MEMBUFS}[$membufnum]{L4S}[0] {KEY} = $membuf_child;

                                $self->setAttribute($membuf_child, "AFFINITY_PATH",
                                                    $membuf_aff . "/l4-0");
                                $self->setAttribute($membuf_child, "PHYS_PATH",
                                    $membuf_physical . "/l4-0");
                                # FAPI_POS and ORDINAL_ID are same as membuf
                                $self->setAttribute($membuf_child, "FAPI_POS",  $fapi_pos);
                                $self->setAttribute($membuf_child, "ORDINAL_ID", $fapi_pos);
                                $self->setAttribute($membuf_child, "REL_POS", 0);

                                # HUID needs to be node relative
                                # L4 is 1 to 1 mapping with membuf
                                $self->{huid_idx}->{"L4"} = $membufnum;
                                $self->setHuid($membuf_child, $sys, $node);

                                $self->setAttribute($membuf_child,"FAPI_NAME",
                                    $self->getFapiName($childType, $node,
                                    $membufnum, 0));
                            }


                            if ($childType eq "MBA")
                            {
                                my $mba = $self->getAttribute($membuf_child,"MBA_NUM");

                                $self->setAttribute($membuf_child, "AFFINITY_PATH",
                                              $membuf_aff . "/mba-$mba");

                                $self->setAttribute($membuf_child, "PHYS_PATH",
                                    $membuf_physical . "/mba-$mba");

                                # Node offset
                                my $mba_offset = (MBA_PER_MEMBUF * $membufnum) +
                                                 $mba ;
                                # System offset
                                my $fapi_pos =
                                 ($node * $maxInstance{"PROC"}) * $maxInstance{"MBA"} +
                                     $mba_offset;

                                $self->setAttribute($membuf_child, "FAPI_POS",  $fapi_pos);
                                $self->setAttribute($membuf_child, "ORDINAL_ID", $fapi_pos);

                                $self->setAttribute($membuf_child, "REL_POS", $mba);
                                $self->setAttribute($membuf_child, "POSITION", $mba_offset);

                                # HUID needs to be node relative
                                $self->{huid_idx}->{"MBA"} = $mba_offset;
                                $self->setHuid($membuf_child, $sys, $node);

                                 $self->setAttribute($membuf_child,"FAPI_NAME",
                                     $self->getFapiName($childType, $node,
                                     $membufnum, $mba));

                                $self->{targeting}
                                  ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{MC}[$mc]{MI}[$mi]
                                    {DMI}[$dmi]{MEMBUFS}[$membufnum]{MBAS}[$mba]{KEY} = $membuf_child;

                                ## Trace the DDR busses to find connected DIMM
                                my $ddrs = $self->findConnections($membuf_child,"DDR4","");

                                if($ddrs eq "")
                                {
                                   # on multi node system there is a possibility that either
                                   # DDR4 or DDR3 dimms are connected under a node
                                   my $ddrs = $self->findConnections($membuf_child,"DDR3","");
                                }
                                if ($ddrs ne "")
                                {
                                    my $dimmPos=0;
                                    foreach my $dimms (@{$ddrs->{CONN}})
                                    {
                                        my $ddr = $dimms->{SOURCE};
                                        my $dimm=$dimms->{DEST_PARENT};
                                        $self->setAttribute($dimm,"CLASS","LOGICAL_CARD");

                                        #We will converge on POS_ON_MEM_PORT/MEM_PORT eventually, but
                                        # we are leaving in support for everything for now
                                        my $port_num = getDimmPort( $self, $ddr );
                                        $self->setAttribute($dimm, "CEN_MBA_PORT",$port_num); #hwp
                                        $self->setAttribute($dimm, "MBA_PORT",$port_num); #legacy
                                        $self->setAttribute($dimm, "MEM_PORT",$port_num); #converged

                                        my $dimm_num = getDimmPos( $self, $ddr );
                                        $self->setAttribute($dimm, "CEN_MBA_DIMM",$dimm_num); #hwp
                                        $self->setAttribute($dimm, "MBA_DIMM",$dimm_num); #legacy
                                        $self->setAttribute($dimm, "POS_ON_MEM_PORT",$dimm_num); #converged


                                        my $aff_pos = DIMMS_PER_PROC*$proc+
                                                      DIMMS_PER_DMI*$dmi_num+
                                                      DIMMS_PER_MBA*$mba+
                                                      MAX_DIMMS_PER_MBA_PORT*$port_num + $dimm_num;
                                        my $fapi_pos =
                                         (($node * $maxInstance{"PROC"}) + $proc ) * DIMMS_PER_PROC +
                                          DIMMS_PER_DMI*$dmi_num+
                                          DIMMS_PER_MBA*$mba+
                                          MAX_DIMMS_PER_MBA_PORT*$port_num  + $dimm_num;

                                        $self->setAttribute($dimm, "AFFINITY_PATH",
                                                  $membuf_aff . "/mba-$mba/dimm-$dimmPos" );

                                        $self->setAttribute($dimm, "PHYS_PATH",
                                             $node_phys  . "/dimm-" . $self->{dimm_tpos});

                                        my $dimmType = $self->getType($dimm);

                                        # cXX portion for dimms is relative to node
                                        $self->setAttribute($dimm,"FAPI_NAME",
                                            $self->getFapiName($dimmType, $node, $aff_pos));

                                        $self->setAttribute($dimm,"FAPI_POS", $fapi_pos);

                                        $self->setAttribute($dimm, "ORDINAL_ID", $fapi_pos);

                                        $self->setAttribute($dimm, "POSITION", $aff_pos);

                                        $self->setAttribute($dimm, "REL_POS",
                                            MAX_DIMMS_PER_MBA_PORT*$port_num +
                                            $dimm_num);

                                        $self->setAttribute($dimm, "VPD_REC_NUM", $self->{dimm_tpos});

                                        # HUID needs to be node relative
                                        $self->{huid_idx}->{$dimmType} = $aff_pos;
                                        $self->setHuid($dimm, $sys, $node);
                                        $self->{targeting}
                                          ->{SYS}[0]{NODES}[$node]{PROCS}[$proc] {MC}[$mc]{MI}[$mi]{DMI}[$dmi]
                                          {MEMBUFS}[$membufnum]{MBAS}[$mba] {DIMMS}[$dimmPos]{KEY} =
                                          $dimm;
                                        $self->setAttribute($dimm, "ENTITY_INSTANCE",
                                             $self->{dimm_tpos});
                                        $self->{dimm_tpos}++;

                                        $dimmPos++;
                                    }
                                }
                            }
                        }
                    }


                }#dmi
            }#mi

        }#mc
    }#membuf_child

}



sub setFsiAttributes
{
    my $self = shift;
    my $target = shift;
    my $type = shift;
    my $cmfsi = shift;
    my $phys_path = shift;
    my $fsi_port = shift;
    my $flip_port = shift;
    my $altfsiswitch = shift;

    $self->setAttribute($target, "FSI_MASTER_TYPE","NO_MASTER");
    if ($type eq "FSIM")
    {
        $self->setAttribute($target, "FSI_MASTER_TYPE","MFSI");
    }
    if ($type eq "FSICM")
    {
        $self->setAttribute($target, "FSI_MASTER_TYPE","CMFSI");
    }
    if ($self->isBadAttribute($target, "FSI_MASTER_CHIP"))
    {
      $self->setAttribute($target, "FSI_MASTER_CHIP","physical:sys-0");
      $self->setAttribute($target, "FSI_MASTER_PORT","0xFF");
    }
    if ($self->isBadAttribute($target,"ALTFSI_MASTER_CHIP"))
    {
      $self->setAttribute($target, "ALTFSI_MASTER_CHIP","physical:sys-0");
      $self->setAttribute($target, "ALTFSI_MASTER_PORT","0xFF");
    }
    $self->setAttribute($target, "FSI_SLAVE_CASCADE", "0");
    if ($type eq "FSICM")
    {
        $self->setAttribute($target, "FSI_MASTER_CHIP",$phys_path);
        $self->setAttribute($target, "FSI_MASTER_PORT", $fsi_port);
        $self->setAttribute($target, "ALTFSI_MASTER_CHIP",$phys_path);
        $self->setAttribute($target, "ALTFSI_MASTER_PORT", $fsi_port);
    }
    else
    {
      if ($altfsiswitch eq 0 )
      {
        $self->setAttribute($target, "FSI_MASTER_CHIP",$phys_path);
        $self->setAttribute($target, "FSI_MASTER_PORT", $fsi_port);
      }
      else
      {
        $self->setAttribute($target, "ALTFSI_MASTER_CHIP",$phys_path);
        $self->setAttribute($target, "ALTFSI_MASTER_PORT", $fsi_port);
      }
    }

    $self->setAttributeField($target, "FSI_OPTION_FLAGS","flipPort",
          $flip_port);
    $self->setAttributeField($target, "FSI_OPTION_FLAGS","reserved", "0");

}

## remove target
sub removeTarget
{
    my $self   = shift;
    my $target = shift;
    delete $self->{data}->{TARGETS}->{$target};
}

## returns pointer to target from target name
sub getTarget
{
    my $self   = shift;
    my $target = shift;
    return $self->{data}->{TARGETS}->{$target};
}

## returns pointer to array of all targets
sub getAllTargets
{
    my $self   = shift;
    my $target = shift;
    return $self->{data}->{TARGETS};
}

## returns the target name of the parent of passed in target
sub getTargetParent
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{PARENT};
}

## returns the number of connections associated with target
sub getNumConnections
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($target_ptr->{CONNECTION}->{DEST}))
    {
        return 0;
    }
    return scalar(@{ $target_ptr->{CONNECTION}->{DEST} });
}

## returns the number of connections associated with target where the target is
## the destination
sub getNumDestConnections
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($target_ptr->{CONNECTION}->{SOURCE}))
    {
        return 0;
    }
    return scalar(@{ $target_ptr->{CONNECTION}->{SOURCE} });
}

## returns destination target name of first connection
## useful for point to point busses with only 1 endpoint
sub getFirstConnectionDestination
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{CONNECTION}->{DEST}->[0];
}

## returns pointer to bus of first connection
sub getFirstConnectionBus
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{CONNECTION}->{BUS}->[0];
}
## returns target name of $i connection
sub getConnectionDestination
{
    my $self       = shift;
    my $target     = shift;
    my $i          = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{CONNECTION}->{DEST}->[$i];
}

## returns target name of $i source connection
sub getConnectionSource
{
    my $self       = shift;
    my $target     = shift;
    my $i          = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{CONNECTION}->{SOURCE}->[$i];
}

sub getConnectionBus
{
    my $self       = shift;
    my $target     = shift;
    my $i          = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{CONNECTION}->{BUS}->[$i];
}

sub findFirstEndpoint
{
    my $self     = shift;
    my $target   = shift;
    my $bus_type = shift;
    my $end_type = shift;

    my $target_children = $self->getTargetChildren($target);
    if ($target_children eq "") { return ""; }

    foreach my $child (@{ $self->getTargetChildren($target) })
    {
        my $child_bus_type = $self->getBusType($child);
        if ($child_bus_type eq $bus_type)
        {
            for (my $i = 0; $i < $self->getNumConnections($child); $i++)
            {
                my $dest_target = $self->getConnectionDestination($child, $i);
                my $dest_parent = $self->getTargetParent($dest_target);
                my $type        = $self->getMrwType($dest_parent);
                my $dest_type   = $self->getType($dest_parent);
                if ($type eq "NA") { $type = $dest_type; }
                if ($type eq $end_type)
                {
                    return $dest_parent;
                }
            }
        }
    }
    return "";
}

# Find connections _from_ $target (and it's children)
sub findConnections
{
    my $self     = shift;
    my $target   = shift;
    my $bus_type = shift;
    my $end_type = shift;

    return $self->findConnectionsByDirection($target, $bus_type,
                                             $end_type, 0);
}

# Find connections _to_ $target (and it's children)
sub findDestConnections
{
    my $self     = shift;
    my $target   = shift;
    my $bus_type = shift;
    my $source_type = shift;

    return $self->findConnectionsByDirection($target, $bus_type,
                                             $source_type, 1);

}

# Find connections from/to $target (and it's children)
# $to_this_target indicates the direction to find.
sub findConnectionsByDirection
{
    my $self     = shift;
    my $target   = shift;
    my $bus_type = shift;
    my $other_end_type = shift;
    my $to_this_target = shift;

    my %connections;
    my $num=0;
    my $target_children = $self->getTargetChildren($target);
    if ($target_children eq "")
    {
        return "";
    }

    foreach my $child ($self->getAllTargetChildren($target))
    {
        my $child_bus_type = "";
        if (!$self->isBadAttribute($child, "BUS_TYPE"))
        {
            $child_bus_type = $self->getBusType($child);
        }

        if ($child_bus_type eq $bus_type)
        {
            my $numOfConnections = 0;
            if($to_this_target)
            {
                $numOfConnections = $self->getNumDestConnections($child);
            }
            else
            {
                $numOfConnections = $self->getNumConnections($child);
            }
            for (my $i = 0; $i < $numOfConnections; $i++)
            {
                my $other_end_target = undef;
                if($to_this_target)
                {
                    $other_end_target = $self->getConnectionSource($child, $i);
                }
                else
                {
                    $other_end_target = $self->getConnectionDestination($child,
                                                                        $i);
                }
                my $other_end_parent = $self->getTargetParent($other_end_target);
                my $type        = $self->getMrwType($other_end_parent);
                my $dest_type   = $self->getType($other_end_parent);
                my $dest_class  = $self->getAttribute($other_end_parent,"CLASS");
                if ($type eq "NA")
                {
                    $type = $dest_type;
                }
                if ($type eq "NA") {
                    $type = $dest_class;
                }

                if ($other_end_type ne "") {
                    #Look for an other_end_type match on any ancestor, as
                    #connections may have a destination unit with a hierarchy
                    #like unit->pingroup->muxgroup->chip where the chip has
                    #the interesting type.
                    while ($type ne $other_end_type) {

                        $other_end_parent = $self->getTargetParent($other_end_parent);
                        if ($other_end_parent eq "") {
                            last;
                        }

                        $type = $self->getMrwType($other_end_parent);
                        if ($type eq "NA") {
                            $type = $self->getType($other_end_parent);
                        }
                        if ($type eq "NA") {
                            $type = $self->getAttribute($other_end_parent, "CLASS");
                        }
                    }
                }

                if ($type eq $other_end_type || $other_end_type eq "")
                {
                    if($to_this_target)
                    {
                        $connections{CONN}[$num]{SOURCE}=$other_end_target;
                        $connections{CONN}[$num]{SOURCE_PARENT}=
                                                $other_end_parent;
                        $connections{CONN}[$num]{DEST}=$child;
                        $connections{CONN}[$num]{DEST_PARENT}=$target;
                    }
                    else
                    {
                        $connections{CONN}[$num]{SOURCE}=$child;
                        $connections{CONN}[$num]{SOURCE_PARENT}=$target;
                        $connections{CONN}[$num]{DEST}=$other_end_target;
                        $connections{CONN}[$num]{DEST_PARENT}=$other_end_parent;
                    }
                    $connections{CONN}[$num]{BUS_NUM}=$i;
                    $num++;
                }
            }
        }
    }
    if ($num==0) { return ""; }
    return \%connections;
}

## returns BUS_TYPE attribute of target
sub getBusType
{
    my $self   = shift;
    my $target = shift;
    my $type   = $self->getAttribute($target, "BUS_TYPE");
    if ($type eq "") { $type = "NA"; }
    return $type;
}

## return target type
sub getType
{
    my $self   = shift;
    my $target = shift;
    my $type   = $self->getAttribute($target, "TYPE");
    if ($type eq "") { $type = "NA"; }
    return $type;
}

## return target type
sub getMrwType
{
    my $self   = shift;
    my $target = shift;
    my $type   = $self->getAttribute($target, "MRW_TYPE");
    if ($type eq "") { $type = "NA"; }
    return $type;
}

## returns target instance name
sub getInstanceName
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{TARGET}->{instance_name};
}

## returns the parent target type
sub getTargetType
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    return $target_ptr->{TARGET}->{type};
}

## checks if attribute is value
## must be defined and have a non-empty value
sub isBadAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $attribute  = shift;
    my $badvalue   = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}))
    {
        return 1;
    }
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}->{default}))
    {
        return 1;
    }
    if ($target_ptr->{ATTRIBUTES}->{$attribute}->{default} eq "")
    {
        return 1;
    }
    if (defined $badvalue &&
        $target_ptr->{ATTRIBUTES}->{$attribute}->{default} eq $badvalue)
    {
        return 1;
    }
    return 0;
}

## checks if complex attribute field is
## defined and non-empty
sub isBadComplexAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $attribute  = shift;
    my $field      = shift;
    my $badvalue   = shift;
    my $target_ptr = $self->getTarget($target);

    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}))
    {
        return 1;
    }
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}->{default}))
    {
        return 1;
    }
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}->{default}->{field}))
    {
        return 1;
    }
    if ($target_ptr->{ATTRIBUTES}->{$attribute}->{default}->{field}->{$field}
        ->{value} eq "")
    {
        return 1;
    }
    if ($target_ptr->{ATTRIBUTES}->{$attribute}->{default}->{field}->{$field}
        ->{value} eq $badvalue)
    {
        return 1;
    }
    return 0;
}

## returns attribute value
sub getAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $attribute  = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}->{default}))
    {
        printf("ERROR: getAttribute(%s,%s) | Attribute not defined\n",
            $target, $attribute);
        $self->myExit(4);
    }
    if (ref($target_ptr->{ATTRIBUTES}->{$attribute}->{default}) eq "HASH")
    {
        return "";
    }
    return $target_ptr->{ATTRIBUTES}->{$attribute}->{default};
}


sub getAttributeGroup
{
    my $self       = shift;
    my $target     = shift;
    my $group      = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($self->{groups}->{$group})) {
        printf("ERROR: getAttributeGroup(%s,%s) | Group not defined\n",
            $target, $group);
        $self->myExit(4);
    }
    my %attr;
    foreach my $attribute (keys(%{$self->{groups}->{$group}}))
    {
        if (defined($target_ptr->{ATTRIBUTES}->{$attribute}->{default}))
        {
            $attr{$attribute} = $target_ptr->{ATTRIBUTES}->{$attribute};
        }
    }
    return \%attr;
}

## delete a target attribute
sub deleteAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $Name       = shift;
    my $target_ptr = $self->{data}->{TARGETS}->{$target};
    if (!defined($target_ptr->{ATTRIBUTES}->{$Name}))
    {
        return 1;
    }
    delete($target_ptr->{ATTRIBUTES}->{$Name});
    $self->log($target, "Deleting attribute: $Name");
    return 0;
}

## renames a target attribute
sub renameAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $oldName    = shift;
    my $newName    = shift;
    my $target_ptr = $self->{data}->{TARGETS}->{$target};
    if (!defined($target_ptr->{ATTRIBUTES}->{$oldName}))
    {
        return 1;
    }
    $target_ptr->{ATTRIBUTES}->{$newName}->{default} =
      $target_ptr->{ATTRIBUTES}->{$oldName}->{default};
    delete($target_ptr->{ATTRIBUTES}->{$oldName});
    $self->log($target, "Renaming attribute: $oldName => $newName");
    return 0;
}

## copy an attribute between targets
sub copyAttribute
{
    my $self = shift;
    my $source_target = shift;
    my $dest_target = shift;
    my $attribute = shift;

    my $value=$self->getAttribute($source_target,$attribute);
    $self->setAttribute($dest_target,$attribute,$value);

    $self->log($dest_target, "Copy Attribute: $attribute=$value");
}

## copy an attribute between targets
sub copyAttributeFields
{
    my $self = shift;
    my $source_target = shift;
    my $dest_target = shift;
    my $attribute = shift;

    foreach my $f(sort keys
        %{$self->{data}->{TARGETS}->{$source_target}->{ATTRIBUTES}->{$attribute}->{default}->{field}})
    {
            my $field_val = $self->getAttributeField($source_target,
                $attribute, $f);
            $self->setAttributeField($dest_target,$attribute,$f,
                $field_val);
            $self->log($dest_target, "Copy Attribute Field:$attribute($f)=$field_val");
    }
}

## sets an attribute
sub setAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $attribute  = shift;
    my $value      = shift;
    my $target_ptr = $self->getTarget($target);
    $target_ptr->{ATTRIBUTES}->{$attribute}->{default} = $value;
    $self->log($target, "Setting Attribute: $attribute=$value");
}
## sets the field of a complex attribute
sub setAttributeField
{
    my $self      = shift;
    my $target    = shift;
    my $attribute = shift;
    my $field     = shift;
    my $value     = shift;
    $self->{data}->{TARGETS}->{$target}->{ATTRIBUTES}->{$attribute}->{default}
      ->{field}->{$field}->{value} = $value;
    $self->log($target, "Setting Attribute: $attribute ($field) =$value");
}
## returns complex attribute value
sub getAttributeField
{
    my $self       = shift;
    my $target     = shift;
    my $attribute  = shift;
    my $field      = shift;
    my $target_ptr = $self->getTarget($target);
    if (!defined($target_ptr->{ATTRIBUTES}->{$attribute}->
       {default}->{field}->{$field}->{value}))
    {
        printf("ERROR: getAttributeField(%s,%s,%s) | Attribute not defined\n",
            $target, $attribute,$field);

        $self->myExit(4);
    }

    return $target_ptr->{ATTRIBUTES}->{$attribute}->
           {default}->{field}->{$field}->{value};
}

## returns an attribute from a bus
sub getBusAttribute
{
    my $self       = shift;
    my $target     = shift;
    my $busnum     = shift;
    my $attr       = shift;
    my $target_ptr = $self->getTarget($target);

    if (
        !defined(
            $target_ptr->{CONNECTION}->{BUS}->[$busnum]->{bus_attribute}
              ->{$attr}->{default}
        )
      )
    {
        printf("ERROR: getBusAttribute(%s,%d,%s) | Attribute not defined\n",
            $target, $busnum, $attr);
        $self->myExit(4);
    }
   if (ref($target_ptr->{CONNECTION}->{BUS}->[$busnum]->{bus_attribute}->{$attr}
      ->{default}) eq  "HASH") {
        return  "";
    }
    return $target_ptr->{CONNECTION}->{BUS}->[$busnum]->{bus_attribute}->{$attr}
      ->{default};
}

## returns a boolean for if a given bus attribute is defined
sub isBusAttributeDefined
{
    my $self       = shift;
    my $target     = shift;
    my $busnum     = shift;
    my $attr       = shift;
    my $target_ptr = $self->getTarget($target);

    return defined($target_ptr->{CONNECTION}->{BUS}->[$busnum]->{bus_attribute}
            ->{$attr}->{default});
}

## returns a pointer to an array of children target names
sub getTargetChildren
{
    my $self       = shift;
    my $target     = shift;
    my $target_ptr = $self->getTarget($target);
    ## this is an array
    return $target_ptr->{CHILDREN};
}

## returns an array of all child (including grandchildren) target names
sub getAllTargetChildren
{
    my $self   = shift;
    my $target = shift;
    my @children;

    my $targets = $self->getTargetChildren($target);
    if ($targets ne "")
    {
        for my $child (@$targets)
        {
            push @children, $child;
            my @more = $self->getAllTargetChildren($child);
            push @children, @more;
        }
    }

    return @children;
}

sub getEnumValue
{
    my $self     = shift;
    my $enumType = shift;
    my $enumName = shift;
    if (!defined($self->{enumeration}->{$enumType}->{$enumName}))
    {
        printf("ERROR: getEnumValue(%s,%s) | enumType not defined\n",
            $enumType, $enumName);
        $self->myExit(4);
    }
    return $self->{enumeration}->{$enumType}->{$enumName};
}

sub getEnumHash
{
    my $self     = shift;
    my $enumType = shift;
    my $enumName = shift;
    if (!defined($self->{enumeration}->{$enumType}))
    {
        printf("ERROR: getEnumValue(%s) | enumType not defined\n",
            $enumType);
            print Dumper($self->{enumeration});
        $self->myExit(4);
    }
    return $self->{enumeration}->{$enumType};
}

sub setHuid
{
    my $self   = shift;
    my $target = shift;
    my $sys    = shift;
    my $node   = shift;

    my $type    = $self->getType($target);
    my $type_id = $self->{enumeration}->{TYPE}->{$type};
    if ($type eq "" || $type eq "NA")
    {
        if (defined ($self->getAttribute($target,"BUS_TYPE")))
        {
            $type = $self->getAttribute($target,"BUS_TYPE");
            $type_id = $self->{enumeration}->{TYPE}->{$type};
            if ($type_id eq "") {$type_id = $self->{enumeration}->{BUS_TYPE}->{$type};}
        }
    }
    if ($type_id eq "") { $type_id = 0; }

    if ($type_id == 0) { return; }
    my $index = 0;
    if (defined($self->{huid_idx}->{$type}))
    {
        $index = $self->{huid_idx}->{$type};
    }
    else { $self->{huid_idx}->{$type} = 0; }

    # Format: SSSS NNNN TTTTTTTT iiiiiiiiiiiiiiii
    my $huid = sprintf("%01x%01x%02x%04x", $sys, $node, $type_id, $index);
    $huid = "0x" . uc($huid);

    $self->setAttribute($target, "HUID", $huid);
    $self->{huid_idx}->{$type}++;
    $self->log($target, "Setting HUID: $huid");
    $self->setMruid($target, $node);
}

sub setMruid
{
    my $self   = shift;
    my $target = shift;
    my $node   = shift;

    my $type          = $self->getType($target);
    my $mru_prefix_id = $self->{enumeration}->{MRU_PREFIX}->{$type};
    if (!defined $mru_prefix_id || $mru_prefix_id eq "")
    {
         $mru_prefix_id = "0xFFFF";
    }
    if ($mru_prefix_id eq "0xFFFF") { return; }
    my $index = 0;
    if (defined($self->{mru_idx}->{$node}->{$type}))
    {
        $index = $self->{mru_idx}->{$node}->{$type};
    }
    else { $self->{mru_idx}->{$node}->{$type} = 0; }

    my $mruid = sprintf("%s%04x", $mru_prefix_id, $index);
    $self->setAttribute($target, "MRU_ID", $mruid);
    $self->{mru_idx}->{$node}->{$type}++;
}

sub getSystemName
{
    my $self = shift;
    return $self->getAttribute("/".$self->{TOP_LEVEL}, "SYSTEM_NAME");
}

#--------------------------------------------------
## Utility function to process all of the existing
## types of dimm port attributes that we have
## supported.
sub getDimmPort
{
    my $self = shift;

    # input can be a dimm connector or a ddr target
    #  data exist on the dimm_port in the xml but
    #  we mirror it to the ddr while processing (somewhere...)
    my $targ = shift;

    # output values
    my $port_num = 0;

    #We will converge on MEM_PORT eventually, but
    # we are leaving in support for everything for now
    if (!$self->isBadAttribute($targ, "MEM_PORT"))
    {
        $port_num = $self->getAttribute($targ,"MEM_PORT");
    }
    elsif (!$self->isBadAttribute($targ, "CEN_MBA_PORT"))
    {
        $port_num = $self->getAttribute($targ,"CEN_MBA_PORT");
    }
    elsif( !$self->isBadAttribute($targ, "MBA_PORT"))
    {
        $port_num = $self->getAttribute($targ,"MBA_PORT");
    }
    else
    {
        print("ERROR: There is no memory port defined for target $targ\n");
        $self->myExit(4);
    }

    return $port_num;
}

#--------------------------------------------------
## Utility function to process all of the existing
## types of dimm port position attributes that we have
## supported.
sub getDimmPos
{
    my $self = shift;

    # input can be a dimm connector or a ddr target
    #  data exist on the dimm_port in the xml but
    #  we mirror it to the ddr while processing (somewhere...)
    my $targ = shift;

    # output values
    my $dimm_num = 0;

    #We will converge on POS_ON_MEM_PORT eventually, but
    # we are leaving in support for everything for now
    if (!$self->isBadAttribute($targ, "POS_ON_MEM_PORT"))
    {
        $dimm_num = $self->getAttribute($targ,"POS_ON_MEM_PORT");
    }
    elsif (!$self->isBadAttribute($targ, "CEN_MBA_DIMM"))
    {
        $dimm_num = $self->getAttribute($targ,"CEN_MBA_DIMM");
    }
    elsif( !$self->isBadAttribute($targ, "MBA_DIMM"))
    {
        $dimm_num = $self->getAttribute($targ,"MBA_DIMM");
    }
    else
    {
        print("ERROR: CEN_MBA_DIMM not defined for dimm $targ\n");
        $self->myExit(4);
    }

    return $dimm_num;
}

sub myExit
{
    my $self      = shift;
    my $exit_code = shift;
    if ($exit_code eq "") { $exit_code = 0; }
    $self->{errorsExist} = 1;
    if ($self->{force} == 0)
    {
        exit($exit_code);
    }
}

sub log
{
    my $self   = shift;
    my $target = shift;
    my $msg    = shift;
    if ($self->{debug})
    {
        print "DEBUG: ($target) $msg\n";
    }
}
sub writeReport
{
    my $self   = shift;
    my $msg    = shift;
    $self->{report_log}=$self->{report_log}.$msg;
}
sub writeReportFile
{
    my $self   = shift;
    open(R,">$self->{report_filename}") ||
          die "Unable to create file: ".$self->{report_filename};
    print R $self->{report_log};
    close R;
}

1;

=head1 NAME

Targets

=head1 SYNOPSIS

    use Targets;

    my $targets = Targets->new;
    $targets->loadXML("myfile.xml");
    foreach my $target ( sort keys %{ $targets->getAllTargets() } ) {
        ## do stuff with targets
    }

    $targets->printXML( $file_handle, "top" );

=head1 DESCRIPTION

C<Targets> is a class that consumes XML generated by ServerWiz2.  The XML
describes a POWER system topology including nodes, cards, chips, and busses.

=head1 OVERVIEW

A simple example of a ServerWiz2 topology would be:

=over 4

=item Topology Example:

   -system
      -node
         -motherboard
           -processor
           -pcie card
               - daughtercard
                  - memory buffer
                  - dimms

=back

Targets->loadXML("myfile.xml") reads this topology and creates 2 data
structures.  One data structure simply represents the hierarchical system
topology.  The other data structure represents the hierarchical structure
that hostboot expects (affinity path).

Unlike hostboot, everything in ServerWiz2 is represented as a target.
For example, FSI and I2C units are targets under the processor that have a
bus type and therefore allow connections to be made.

=head1 CONSTRUCTOR

=over 4

=item new ()

There are no arguments for the constructor.

=back

=head1 METHODS

C<TARGET> is a pointer to data structure containing all target information.
C<TARGET_STRING> is the hierarchical target string used as key for data
structure.  An example for C<TARGET_STRING> would be:
C</sys-0/node-0/motherboard-0/dimm-0>

=over 4

=item loadXml (C<FILENAME>)

Reads ServerWiz2 XML C<FILENAME> and stores into a data structure for
manipulation and printing.

=item removeTarget(C<TARGET_STRING>)

Removes the given target from the data structure (C<TARGET>)

=item getTarget(C<TARGET_STRING>)

Returns pointer to data structure (C<TARGET>)

=item getAllTargets(C<TARGET_STRING>)

Returns array with all existing target data structures

=item getTargetParent(C<TARGET_STRING>)

Returns C<TARGET_STRING> of parent target

=item getNumConnections(C<TARGET_STRING>)

Returns the number of bus connections to this target

=item getFirstConnectionDestination(C<TARGET_STRING>)

Returns the target string of the first target found connected to
C<TARGET_STRING>.  This is useful because many busses are guaranteed
to only have one connection because they are point to point.

=item getFirstConnectionBus(C<TARGET_STRING>)

Returns the data structure of the bus of the first target found connected to
C<TARGET_STRING>.  The bus data structure is also a target with attributes.

=item getConnectionDestination(C<TARGET_STRING>,C<INDEX>)

Returns the target string of the C<INDEX> target found connected to
C<TARGET_STRING>.

=item getConnectionBus(C<TARGET_STRING>)

Returns the data structure of the C<INDEX> bus target found connected to
C<TARGET_STRING>.

=item findEndpoint(C<TARGET_STRING>,C<BUS_TYPE>,C<ENDPOINT_MRW_TYPE>)

Searches through all connections to C<TARGET_STRING>
for a endpoint C<MRW_TYPE> and C<BUS_TYPE>

=item getBusType(C<TARGET_STRING>)

Returns the BUS_TYPE attribute of (C<TARGET_STRING>).  Examples are I2C and DMI.

=item getType(C<TARGET_STRING>)

Returns the TYPE attribute of (C<TARGET_STRING>).
Examples are PROC and MEMBUF.

=item getMrwType(C<TARGET_STRING>)

Returns the MRW_TYPE attribute of (C<TARGET_STRING>).
Examples are CARD and PCI_CONFIG.  This
is an extension to the TYPE attribute and are types that hostboot does
not care about.

=item getTargetType(C<TARGET_STRING>)

Returns the target type id of (C<TARGET_STRING>).
This is not the TYPE attribute.  This is the
<id> from target_types.xml.  Examples are unit-pci-power8 and enc-node-power8.

=item isBadAttribute(C<TARGET_STRING>,C<ATTRIBUTE_NAME>)

Tests where attribute (C<ATTRIBUTE_NAME>) has been set in
target (C<TARGET_STRING>).  Returns true if attribute is undefined or empty
and false if attribute is defined and not empty.

=item getAttribute(C<TARGET_STRING>,C<ATTRIBUTE_NAME>)

Returns the value of attribute C<ATTRIBUTE_NAME> in target C<TARGET_STRING>.

=item renameAttribute(C<TARGET_STRING>,C<ATTRIBUTE_OLDNAME>,
C<ATTRIBUTE_OLDNAME>)

Renames attribute C<ATTRIBUTE_OLDNAME> to C<ATTRIBUTE_NEWNAME> in target
C<TARGET_STRING>.

=item setAttribute(C<TARGET_STRING>,C<ATTRIBUTE_NAME>,C<VALUE>)

Sets attribute C<ATTRIBUTE_NAME> of target C<TARGET_STRING> to value C<VALUE>.

=item setAttributeField(C<TARGET_STRING>,C<ATTRIBUTE_NAME>,C<FIELD>,C<VALUE>)

Sets attribute C<ATTRIBUTE_NAME> and field C<FIELD> of target C<TARGET_STRING>
to value C<VALUE>.  This is for complex attributes.

=item getBusAttribute(C<TARGET_STRING>,C<INDEX>,C<ATTRIBUTE_NAME>)

Gets the attribute C<ATTRIBUTE_NAME> from bus C<TARGET_STRING> bus number
C<INDEX>.

=item isBusAttributeDefined(C<TARGET_STRING>,C<INDEX>.C<ATTRIBUTE_NAME>)

Looks for a specific attribute and returns if it exists or not

=item getTargetChildren(C<TARGET_STRING>)

Returns an array of target strings representing all the children of target
C<TARGET_STRING>.

=item getAllTargetChildren(C<TARGET_STRING>)

Returns an array of target strings representing all the children of target
C<TARGET_STRING>, including grandchildren and below as well.

=item getEnumValue(C<ENUM_TYPE>,C<ENUM_NAME>)

Returns the enum value of type C<ENUM_TYPE> and name C<ENUM_NAME>.  The
enumerations are also defined in ServerWiz2 XML output and are directly
copied from attribute_types.xml.

=item getMasterProc()

Returns the target string of the master processor.

=item myExit(C<EXIT_NUM>)

Calls exit(C<EXIT_NUM>) when force flag is not set.

=item log(C<TARGET_STRING>,C<MESSAGE>)

Prints to stdout log message is debug mode is turned on.


=back

=head1 CREDITS

Norman James <njames@us.ibm.com>

=cut
