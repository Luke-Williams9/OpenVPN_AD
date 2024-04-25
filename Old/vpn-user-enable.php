<?php

require_once("pfsense-utils.inc");

$username = strtolower($argv[1]);
$servers = openvpn_get_active_servers();

init_config_arr(array('system', 'user'));
$users = &$config['system']['user'];

foreach ($users as $uid => $user) {
        if (strtolower($user['name']) == $username) {
                break;
        }
}


$users[$uid]['disabled'] = false;
Write_config("Enabled VPN user " . $user['name']);

#var_export($user);

?>