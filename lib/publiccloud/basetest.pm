# SUSE's openQA tests
#
# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Base class for publiccloud tests
#
# Maintainer: Clemens Famulla-Conrad <cfamullaconrad@suse.de>

package publiccloud::basetest;
use base 'opensusebasetest';
use testapi;
use publiccloud::azure;
use publiccloud::ec2;
use publiccloud::eks;
use publiccloud::ecr;
use publiccloud::gce;
use publiccloud::gke;
use publiccloud::gcr;
use publiccloud::acr;
use publiccloud::aks;
use publiccloud::openstack;
use publiccloud::noprovider;
use strict;
use warnings;

sub provider_factory {
    my ($self, %args) = @_;
    my $provider;

    die("Provider already initialized") if ($self->{provider});

    $args{provider} //= get_required_var('PUBLIC_CLOUD_PROVIDER');

    if (get_var('PUBLIC_CLOUD_INSTANCE_IP')) {
        $provider = publiccloud::noprovider->new();
    }
    elsif ($args{provider} eq 'EC2') {
        $args{service} //= 'EC2';

        if ($args{service} eq 'ECR') {
            $provider = publiccloud::ecr->new();
        }
        elsif ($args{service} eq 'EKS') {
            $provider = publiccloud::eks->new();
        }
        elsif ($args{service} eq 'EC2') {
            $provider = publiccloud::ec2->new();
        }
        else {
            die('Unknown service given');
        }

    }
    elsif ($args{provider} eq 'AZURE') {
        $args{service} //= 'AVM';
        if ($args{service} eq 'ACR') {
            $provider = publiccloud::acr->new(
                subscription => get_var('PUBLIC_CLOUD_AZURE_SUBSCRIPTION_ID'),
                username => get_var('PUBLIC_CLOUD_USER', 'azureuser')
            );
        }
        elsif ($args{service} eq 'AKS') {
            $provider = publiccloud::aks->new();
        }
        elsif ($args{service} eq 'AVM') {
            $provider = publiccloud::azure->new();
        } else {
            die('Unknown service given');
        }
    }
    elsif ($args{provider} eq 'GCE') {
        $args{service} //= 'GCE';
        if ($args{service} eq 'GCR') {
            $provider = publiccloud::gcr->new();
        }
        elsif ($args{service} eq 'GKE') {
            $provider = publiccloud::gke->new();
        }
        elsif ($args{service} eq 'GCE') {
            $provider = publiccloud::gce->new();
        }
        else {
            die('Unknown service given');
        }
    }
    elsif ($args{provider} eq 'OPENSTACK') {
        $provider = publiccloud::openstack->new();
    }
    else {
        die('Unknown PUBLIC_CLOUD_PROVIDER given');
    }

    $provider->init();
    $self->{provider} = $provider;
    return $provider;
}

sub cleanup {
    # to be overridden by tests
    return 1;
}

sub _cleanup {
    my ($self) = @_;
    die("Cleanup called twice!") if ($self->{cleanup_called});
    $self->{cleanup_called} = 1;

    $self->_upload_logs();

    eval { $self->cleanup(); } or bmwqemu::fctwarn("self::cleanup() failed -- $@");

    my $flags = $self->test_flags();

    diag('Public Cloud _cleanup: $flags->{publiccloud_multi_module}=' . $flags->{publiccloud_multi_module}) if ($flags->{publiccloud_multi_module});
    diag('Public Cloud _cleanup: $flags->{fatal}=' . $flags->{fatal}) if ($flags->{fatal});
    diag('Public Cloud _cleanup: $self->{result}=' . $self->{result}) if ($self->{result});
    diag('Public Cloud _cleanup: $self->{run_args}=' . $self->{run_args}) if ($self->{run_args});
    diag('Public Cloud _cleanup: $self->{run_args}->{my_provider}=' . $self->{run_args}->{my_provider}) if ($self->{run_args} && $self->{run_args}->{my_provider});
    diag('Public Cloud _cleanup: $self->{run_args}->{my_instance}=' . $self->{run_args}->{my_instance}) if ($self->{run_args} && $self->{run_args}->{my_instance});

    if ($self->{run_args} && $self->{run_args}->{my_instance} && $self->{result} && $self->{result} eq 'fail') {
        $self->{run_args}->{my_instance}->upload_supportconfig_log();
    }

    # currently we have two cases when cleanup of image will be skipped:
    # 1. Job should have 'PUBLIC_CLOUD_NO_CLEANUP' variable
    if (get_var('PUBLIC_CLOUD_NO_CLEANUP')) {
        upload_asset(script_output('ls ~/.ssh/id* | grep -v pub | head -n1'));
        return;
    }
    diag('Public Cloud _cleanup: 1st check passed.');

    # 2. Test module needs to have 'publiccloud_multi_module' and should not have 'fatal' flags and 'fail' result
    if ($flags->{publiccloud_multi_module}) {
        diag('Public Cloud _cleanup: Test has `publiccloud_multi_module` flag.');
        return unless ($flags->{fatal} && $self->{result} && $self->{result} eq 'fail');
    } else {
        diag('Public Cloud _cleanup: Test does not have `publiccloud_multi_module` flag.');
    }
    diag('Public Cloud _cleanup: 2nd check passed.');

    # We need $self->{run_args} and $self->{run_args}->{my_provider}
    if ($self->{run_args} && $self->{run_args}->{my_provider}) {
        diag('Public Cloud _cleanup: Ready for provider cleanup.');
        eval { $self->{run_args}->{my_provider}->cleanup(); } or bmwqemu::fctwarn("\$self->provider::cleanup() failed -- $@");
        diag('Public Cloud _cleanup: The provider cleanup finished.');
    } else {
        diag('Public Cloud _cleanup: Not ready for provider cleanup.');
    }
}

sub _upload_logs {
    my ($self) = @_;

    my $ssh_sut_log = '/var/tmp/ssh_sut.log';
    script_run("sudo chmod a+r " . $ssh_sut_log);
    upload_logs($ssh_sut_log, failok => 1, log_name => $ssh_sut_log . ".txt");
    return unless $self->{run_args} && $self->{run_args}->{my_instance};

    my @instance_logs = ('/var/log/cloudregister', '/etc/hosts', '/var/log/zypper.log', '/etc/zypp/credentials.d/SCCcredentials');
    for my $instance_log (@instance_logs) {
        $self->{run_args}->{my_instance}->ssh_script_run("sudo chmod a+r " . $instance_log);
        $self->{run_args}->{my_instance}->upload_log($instance_log, failok => 1, log_name => $instance_log . ".txt");
    }
}

sub post_fail_hook {
    my ($self) = @_;

    if (get_var('PUBLIC_CLOUD_SLES4SAP')) {
        # This is called explicitly to avoid cyclical imports
        sles4sap_publiccloud::sles4sap_cleanup(
            $self,
            cleanup_called => $self->{cleanup_called} // undef,
            network_peering_present => 1,
            ansible_present => 0
        );
        return;
    }

    $self->_cleanup() unless $self->{cleanup_called};
}

sub post_run_hook {
    my ($self) = @_;
    $self->_cleanup() unless $self->{cleanup_called};
}

1;
