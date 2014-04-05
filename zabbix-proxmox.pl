#!/usr/bin/perl

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

my $url_base = "https://" . $host . ":" . $port;
my $url_api = $url_base . "/api2/json";

my $ticket = {};
my $node;


my $ua = LWP::UserAgent->new(cookie_jar => {}, ssl_opts => { verify_hostname => 0 });
$ua->agent('zabbix proxmox monitoring script');

sub login {
    my $res = $ua->post($url_api . "/access/ticket", { username => $username, password => $password } ) or die $!;
    die $res->message if ($res->code ne 200);
    $ticket = decode_json($res->content)->{'data'};
}

sub get_data {
    my ($proxmoxpath) = @_;
    my $request = HTTP::Request->new();
    $request->uri($url_api . $proxmoxpath);
    $request->method("GET");
    $request->header('Cookie' => 'PVEAuthCookie=' . $ticket->{ticket});
    my $res = $ua->request($request);
    die res->message if (!$res->is_success);
    my $data =  decode_json $res->content;
    return $data->{'data'};
}

login();

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
    print $data->{$item} if defined $data->{$item};
}

switch ($ARGV[0]) {
    case "nodes_discovery" { nodes_discovery(); }
    case "node_pveversion" { node_status_item('pveversion'); }
    case "qemu_discovery" { qemu_discovery(); }
    case "qemu_item" { qemu_item($ARGV[1], $ARGV[2]); }
}

