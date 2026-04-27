# SUSE's openQA tests
#
# Copyright 2026 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Prepare Kselftests (install/build and dependencies).
#
# Maintainer: Kernel QE <kernel-qa@suse.de>

use Mojo::Base 'opensusebasetest';

use testapi;
use serial_terminal qw(select_serial_terminal);
use Kselftests::utils;

sub test_flags {
    return {fatal => 1};
}

sub run {
    my ($self) = @_;

    select_serial_terminal;
    record_info('KERNEL VERSION', script_output('uname -a'));

    my $collection = get_required_var('KSELFTEST_COLLECTION');
    install_kselftests($collection);

    # Apply upstream selftest fixes that may not be present in the running kernel yet.
    # install_kselftests() leaves CWD at the kselftest install root, so -p4 strips
    # "tools/testing/selftests/" and lands on the correct relative path (e.g. net/fib_nexthops.sh).
    my @patches;
    if ($collection =~ m{^net(/|$)}) {
        # 465b210fdc65 selftests: fib_nexthops: do not mark skipped tests as failed
        # Old log_test() incremented nfail and set ret=1 even for SKIP results, causing
        # the script to exit 1 instead of 4 when only skips occurred (no real failures).
        push @patches, 'selftests-net-fib_nexthops-do-not-mark-skipped-tests-as-failed.patch';
    }
    for my $patch (@patches) {
        assert_script_run("curl -o /tmp/$patch " . autoinst_url("/data/kernel/$patch"));
        # -N: skip forward (do not apply if already present); tolerate exit!=0 on newer kernels
        if (script_run("patch -p4 --fuzz 0 -N -r - < /tmp/$patch", timeout => 30) == 0) {
            record_info('Selftest patch', "Applied $patch");
        }
    }
}

1;

=head1 Description

This module prepares Linux Kernel Selftests (kselftests) for execution inside
openQA. It installs all required dependencies and the selftests themselves,
leaving the system ready for C<kselftests_run> to execute them.

Separating preparation from execution allows cloned investigation jobs to be
paused at C<kselftests_run> with the SUT already fully configured.

=head1 Configuration

=head2 KSELFTEST_COLLECTION (required)

Specifies the name of the kselftest collection to install, as reported by:

  run_kselftest.sh --list

=head2 KSELFTEST_FROM_GIT

If set, kselftests are installed from a kernel git tree instead of using
packaged RPMs. Allows to point to C<KERNEL_GIT_TREE>. Defaults to the
upstream tree: C<torvalds/linux.git>.

=head2 KSELFTEST_FROM_SRC

If set, kselftests are built from the kernel source tree provided by the
C<kernel-source> package instead of using packaged RPMs. The test harness
(C<run_kselftest.sh> and the C<kselftest/> support directory) is then
replaced with the version from the upstream linux tree (C<KERNEL_GIT_TREE>,
default: C<torvalds/linux.git> master branch), so that the SUSE-patched test
binaries run under the upstream harness. This step requires network access
and C<git>.

=head2 KSELFTEST_BUILD_ENV

Optional string containing environment variable assignments to append to
the C<make> command when building kselftests from source (i.e. when
C<KSELFTEST_FROM_GIT> or C<KSELFTEST_FROM_SRC> is set). Has no effect
when installing from a pre-built RPM package.

Example:

  KSELFTEST_BUILD_ENV="SKIP_DOCS=1"

=head2 KSELFTEST_BUILD_JOBS

Optional number of parallel jobs passed to C<make -j> when building
kselftests from source (i.e. when C<KSELFTEST_FROM_GIT> or
C<KSELFTEST_FROM_SRC> is set). Defaults to the number of online CPUs
(C<getconf _NPROCESSORS_ONLN>). Has no effect when installing from a
pre-built RPM package.

Example:

  KSELFTEST_BUILD_JOBS=4

=cut
