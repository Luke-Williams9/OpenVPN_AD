<?php
# VPN afterhours disconnect
# Take a username as $argv[0], halt its openvpn connection, and disable the user

# To do:
# make separate script to enable login
# make script to create cron jobs for cutoff in evening, enable in morning

# to create cron jobs, add them to the cron section in pfsenses config
# See the adam one install php script for examples


require_once("openvpn.inc");
require_once("pfsense-utils.inc");


$username = strtolower($argv[1]);
$servers = openvpn_get_active_servers();

foreach ($servers as $server) {
        $mgmt = $server['mgmt'];
        # var_export($server);
        foreach ($server['conns'] as $conn) {
                if ($username == strtolower($conn['user_name'])) {
                        $client = $conn;
                        $breakloop = true;
                        break;
                }
        }
        if ($breakloop == true) {
                break;
        }
}

init_config_arr(array('system', 'user'));
$users = &$config['system']['user'];

foreach ($users as $uid => $user) {
        if (strtolower($user['name']) == $username) {
                break;
        }
}

# Give openvpn_kill_client both the remote host and client id, and it will 'HALT' the connection, signalling the client to disconnect and not try to reconnect
# With only the remote host, it 'kills' the connection, cutting it off without signaling the client at all. the client will try to reconnect until manually stopped
$result = openvpn_kill_client($mgmt,$client['remote_host'],$client['client_id']);

$users[$uid]['disabled'] = true;
Write_config("Disabled VPN user " . $user['name']);

#var_export($user);

#var_export($client);



?>