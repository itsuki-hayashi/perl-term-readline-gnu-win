# SPDX-FileCopyrightText: 2026 Itsuki Hayashi
# SPDX-License-Identifier: GPL-3.0-or-later
package Gnu::Command;
use 5.044;
use strict;
use warnings;
use IPC::Open3;
sub run_logged {
    my ($log,@command)=@_;
    open my $file,'>>:raw',$log or die "$log: $!";
    my $label=join(' ',@command)."\n";
    print $label; print {$file} $label;
    my ($in,$out); my $err='';
    my $pid=open3($in,$out,$err,@command); close $in;
    while (1) {
        my $n=sysread($out,my $chunk,16384);
        die "Cannot read command output: $!\n" unless defined $n;
        last unless $n;
        print $chunk; print {$file} $chunk;
    }
    close $out;
    waitpid($pid,0); my $status=$?; close $file;
    die "Command failed ($status): @command\n" if $status;
}
1;
