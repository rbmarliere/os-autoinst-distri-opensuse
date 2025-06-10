# SUSE's openQA tests
#
# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Executes kselftests targeting the "livepatch" suite.
#
# Maintainer: Kernel QE <kernel-qa@suse.de>

use base 'opensusebasetest';

use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use registration;
use utils;

sub run
{
    select_serial_terminal;
    zypper_call('in bc git-core ncurses-devel gcc flex bison libelf-devel libopenssl-devel');
    zypper_call('in kernel-devel');
    assert_script_run('cd /usr/src/linux');
    assert_script_run('make O=/lib/modules/$(uname -r)/build modules_prepare');
    assert_script_run('make O=/lib/modules/$(uname -r)/build -C tools/testing/selftests TARGETS=livepatch run_tests');
}

1;
