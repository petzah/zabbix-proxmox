#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use Switch;
use File::stat;
use Data::Dumper;

my $pveshcmd = "/usr/bin/sudo /usr/bin/pvesh get";
my $tmpdir = "/tmp/zabbix-proxmox";
my $node;

# create tmp directory
mkdir $tmpdir;

# update cache files in tmp dir with current values
# if file is older than 1min
sub get_data {
    my ($proxmoxpath) = @_;
    my $filename = $proxmoxpath;
    $filename =~ s/\//\./g;
    my $file = "$tmpdir/$filename";

    # wtf why $mtimestamp = (stat($file))[9]; is not working ???
    my $filestat = stat($file);
    my $mtimestamp = (defined(@$filestat[9]) ? @$filestat[9] : 0);
    if((time - $mtimestamp) > 60) {
        my $data = decode_json `$pveshcmd $proxmoxpath 2>/dev/null`;
        open(FILE, ">$file") || die "Can not open: $!";
        print FILE Data::Dumper->Dump([$data],["data"]);
        close(FILE) || die "Error closing file: $!";
        return $data;
    }
    return eval { do $file };
}

# get_local_node 
my $data = get_data("/cluster/status");
foreach(@$data) {
    $node = $_->{'name'} if($_->{'local'} && $_->{'local'} == 1);
} 

sub nodes_discovery {
    my $data = get_data("/nodes");
    my @out;
    foreach(@$data) {
        push(@out,{'{#PMXNODE}'=>$_->{'node'}});
    }
    print encode_json({'data'=>\@out});
}

sub node_status_item {
    my ($item) = @_;
    my $data = get_data("/nodes/$node/status");
    print $data->{$item};
}

sub qemu_discovery {
    my @out;
    my $data = get_data("/nodes/$node/qemu");
    foreach(@$data) {
        push(@out, {
		'{#PMXQEMUVMID}'=>$_->{'vmid'},
		'{#PMXQEMUNAME}'=>$_->{'name'}
	});
    }
    print encode_json({'data'=>\@out});
}

sub qemu_item {
    my ($vmid, $item) = @_;
    my $data = get_data("/nodes/$node/qemu/$vmid/status/current");
    print $data->{$item};
}

switch ($ARGV[0]) {
    case "nodes_discovery" { nodes_discovery(); }
    case "node_pveversion" { node_status_item('pveversion'); }
    case "qemu_discovery" { qemu_discovery(); }
    case "qemu_item" { qemu_item($ARGV[1], $ARGV[2]); }
}

