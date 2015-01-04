#!/usr/bin/perl

# required packages:
#   arpwatch (for ip discovery from /var/lib/arpwatch/arp.dat)
# required permisisons:
#   zabbix user must be added to arpwatch group

# possible qemu items

#   "balloon" : 1610612736,
#   "cpu" : 0,
#   "cpus" : 2,
#   "disk" : 0,
#   "diskread" : 96372390446,
#   "diskwrite" : 345699340800,
#   "freemem" : 137355264,
#   "ha" : 0,
#   "maxdisk" : 53691285504,
#   "maxmem" : 1610612736,
#   "mem" : 1442725888,
#   "name" : "vpsnet",
#   "netin" : 15358170080,
#   "netout" : 17959040362,
#   "pid" : "957545",
#   "qmpstatus" : "running",
#   "status" : "running",
#   "template" : "",
#   "uptime" : 774949

use strict;
use warnings;
use Switch;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use JSON;

my $host = "localhost";
my $port = "8006";
my $username = 'zabbix@pve';
my $password = 'zabbix';

my $arpwatchfile = '/var/lib/arpwatch/arp.dat';
my $ticketfile = '/tmp/.zabbix-proxmox';

my $url_base = "https://" . $host . ":" . $port;
my $url_api = $url_base . "/api2/json";

my $node;

my $ua = LWP::UserAgent->new(cookie_jar => {}, ssl_opts => { verify_hostname => 0 });
$ua->agent('zabbix proxmox monitoring script');

# first run
login() if ! -e $ticketfile;

sub login {
    my $res = $ua->post($url_api . "/access/ticket", { username => $username, password => $password } ) or die $!;
    die $res->message if ($res->code ne 200);
    my $data = decode_json($res->content)->{'data'};
    open(FILE, ">$ticketfile") || die "Can not open: $!";
    print FILE $data->{ticket};
    close(FILE) || die "Error closing file: $!";
    chmod 0600, $ticketfile;
}

sub get_ticket {
    my $ticket;
    open(my $fh, '<', $ticketfile) or die "Can not open: $!";
    { local $/; $ticket = <$fh>; }
    close($fh);
    return $ticket;
}

sub get_data {
    my ($proxmoxpath) = @_;
    my $request = HTTP::Request->new();
    $request->uri($url_api . $proxmoxpath);
    $request->method("GET");
    $request->header('Cookie' => 'PVEAuthCookie=' . get_ticket());
    my $res = $ua->request($request);
    # refresh ticket
    if ($res->code eq 401) {
        login();
        $request->header('Cookie' => 'PVEAuthCookie=' . get_ticket());
        $res = $ua->request($request);
    }
    die $res->message if (!$res->is_success);
    my $data =  decode_json $res->content;
    return $data->{'data'};
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
    return encode_json({'data'=>\@out});
}

sub node_status_item {
    my ($item) = @_;
    my $data = get_data("/nodes/$node/status");
    return $data->{$item};
}

sub qemu_discovery {
    my @out;
    my %arptable = ();
    my $data = get_data("/nodes/$node/qemu");

    my @lines;
    open(ARPDAT, $arpwatchfile) or die "failed to open $!";
    while(<ARPDAT>) {
        push(@lines,[split /\t/]);
    }
    close ARPDAT;
    my @sorted = sort { $a->[2] <=> $b->[2] } @lines;
    foreach my $l (@sorted) {
	my ($mac, $ip, $time, $interface) = @$l;
        $arptable{$mac}{'mac'} = $mac;
        $arptable{$mac}{'ip'} = $ip;
        $arptable{$mac}{'interface'} = $interface;
    }

    foreach(@$data) {
        my $net0mac = qemu_config_item($_->{'vmid'}, 'net0mac');
        push(@out, {
		'{#PMXQEMUVMID}'=>$_->{'vmid'},
		'{#PMXQEMUNAME}'=>$_->{'name'},
                '{#PMXQEMUMAC0}'=>$net0mac,
                '{#PMXQEMUIP0}'=>$arptable{$net0mac}{'ip'}, # find ip from arp with mac
	});
    }
    return encode_json({'data'=>\@out});
}

sub qemu_item {
    my ($vmid, $item) = @_;
    my $data = get_data("/nodes/$node/qemu/$vmid/status/current");
    return $data->{$item} if defined $data->{$item};
}

sub qemu_config_item {
    my ($vmid, $item) = @_;
    my $data = get_data("/nodes/$node/qemu/$vmid/config");
    # add our own items
    $data->{'net0mac'} =  lc((split('=',(split(',', $data->{'net0'}))[0]))[1]);
    $data->{'net0driver'} =  lc((split('=',(split(',', $data->{'net0'}))[0]))[0]);
    $data->{'net0bridge'} =  lc((split('=',(split(',', $data->{'net0'}))[1]))[1]);
    return $data->{$item} if defined $data->{$item};
}

switch ($ARGV[0]) {
    case "nodes_discovery" { print nodes_discovery(); }
    case "node_pveversion" { print node_status_item('pveversion'); }
    case "qemu_discovery" { print qemu_discovery(); }
    case "qemu_item" { print qemu_item($ARGV[1], $ARGV[2]); }
    case "qemu_config_item" { print qemu_config_item($ARGV[1], $ARGV[2]); }
}
 
