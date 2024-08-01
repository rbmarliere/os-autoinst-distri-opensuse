# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: perl-Bootloader
# Summary: Basic functional test for pbl package
# Maintainer: QE Core <qe-core@suse.de>

use base 'opensusebasetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use strict;
use warnings;
use utils;
use package_utils;
use power_action_utils 'power_action';
use version_utils qw(is_sle check_version is_transactional);
use transactional;

sub run {
    my ($self) = @_;
    select_serial_terminal;

    if (script_run 'rpm -q perl-Bootloader') {
        install_package 'perl-Bootloader';
    }

    # version older than 1.1 does not support option default-settings
    my $pbl_version = script_output("rpm -q --qf '%{version}' perl-Bootloader");
    my $new_pbl = check_version('>=1.1', $pbl_version);

    # pbl --loader is not available on <15-SP3
    unless (is_sle("<15-SP3")) {
        if (get_var('UEFI')) {
            assert_script_run 'pbl --loader grub2-efi';
            validate_script_output 'cat /etc/sysconfig/bootloader', qr/LOADER_TYPE="grub2-efi"/;
        }
        else {
            assert_script_run 'pbl --loader grub2';
            validate_script_output 'cat /etc/sysconfig/bootloader', qr/LOADER_TYPE="grub2"/;
        }
    }

    # https://github.com/openSUSE/fde-tools/blob/main/share/uefi#L73
    # entry=$(efibootmgr | grep BootCurrent|awk '{print $2;}')
    # file=$(efibootdump "Boot$entry" | sed 's/.*File(\([^)]*\)).*/\1/;t;d' | tr '\\' /)

    if (is_transactional) {
        trup_call 'run pbl --install';
        trup_call '--continue run pbl --config';
        trup_call '--continue run fdectl tpm-authorize';

        # script_run('mkdir /boot/efi/EFI/sl');
        script_run('cp /boot/efi/EFI/BOOT/sealed.tpm /boot/efi/EFI/sl');

        record_info("blkid", script_output("blkid"));
        record_info("lsblk", script_output("lsblk"));
        record_info("efi", script_output("efibootmgr"));
        record_info("boot", script_output("find /boot/efi"));
        record_info("mount", script_output("mount"));
        record_info("btrfs1", script_output("btrfs subvolume show /boot/grub2/x86_64-efi"));
        record_info("btrfs2", script_output("btrfs filesystem show"));
        upload_logs('/etc/fstab');
        upload_logs('/boot/efi/EFI/BOOT/grub.cfg');
        upload_logs('/boot/efi/EFI/sl/grub.cfg');
        upload_logs('/boot/efi/EFI/sl/boot.csv');
        upload_logs('/boot/grub2/grub.cfg');
        upload_logs('/var/log/pbl.log');

        check_reboot_changes;
    } else {
        assert_script_run 'pbl --install';
        assert_script_run 'pbl --config';
        power_action('reboot', textmode => 1);
        $self->wait_boot;
        select_serial_terminal;
    }

    # Add new option and check if it exists
    assert_script_run 'pbl --add-option TEST_OPTION="test_value"';
    validate_script_output 'cat /etc/default/grub', qr/test_value/;

    # Delete option and check if it was deleted
    assert_script_run 'pbl --del-option "TEST_OPTION"';
    assert_script_run('! grep -q "TEST_OPTION" /etc/default/grub');

    # Add new option and check if it's logged in new log file
    assert_script_run 'pbl --log /var/log/pbl-test.log --add-option LOG_OPTION="log_value"';
    validate_script_output 'cat /var/log/pbl-test.log', qr/log_value/;

    if ($new_pbl) {
        validate_script_output 'pbl --default-settings', qr/kernel|initrd|append/;
    }
    power_action('reboot', textmode => 1);
    $self->wait_boot;

}

sub post_fail_hook {
    my ($self) = @_;
    $self->SUPER::post_fail_hook;
    upload_logs('/var/log/pbl.log');
}

1;
