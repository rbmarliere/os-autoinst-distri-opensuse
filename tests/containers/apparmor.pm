# SUSE's openQA tests
#
# Copyright 2024 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Package: apparmor-utils
# Summary: Test apparmor utilities
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'containers::basetest';
use testapi;
use services::apparmor;
use utils;

sub run {
    services::apparmor::check_function;

    my $dnsmasq_file = '/etc/apparmor.d/usr.sbin.dnsmasq';
    script_run "cp $dnsmasq_file /tmp/usr.sbin.dnsmasq";
    script_run "echo this should fail > $dnsmasq_file";

    services::apparmor::check_function;
}

1;
