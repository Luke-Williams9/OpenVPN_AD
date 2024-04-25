<?php
// All in one script to 
require_once("openvpn.inc");
require_once("pfsense-utils.inc");

// Specify the path to the text file containing usernames
$action = strtolower($argv[1]);
if (!in_array($action, ['enable', 'disable'])) {
    exit("Invalid action. Please specify 'enable' or 'disable' as the first argument.\n");
}
$filename = $argv[2];

// Check if the file exists
if (!file_exists($filename)) {
    exit("The file does not exist. Please specify a file of usernames (one per line) as the second argument.\n");
}

// Read the file into an array, where each line is an element
$usernames = file($filename, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

// Check if the file is not empty
if (empty($usernames)) {
    exit("The file is empty.\n");
}

global $config;
init_config_arr(array('system', 'user'));
$users = &$config['system']['user'];

// Loop through the usernames from file
foreach ($usernames as $index => $username) {
    // Find the user in the config
    $user_found = false;
    foreach ($users as $uid => $user) {
        if (strtolower($user['name']) == strtolower($username)) {
            $user_found = true;
            break;
        }
    }
    if ($action == 'enable') {
        // Enable user account
        $users[$uid]['disabled'] = false;
        echo $username . " enable\n";    
    } else {
        // Halt user VPN connection if found, and disable user account
        $client_found = false;
        $servers = openvpn_get_active_servers();
        foreach ($servers as $server) {
            $mgmt = $server['mgmt'];
            foreach ($server['conns'] as $conn) {
                if (strtolower($user['name']) == strtolower($conn['user_name'])) {
                    $client = $conn;
                    $client_found = true;
                    break;
                }
            }
            if ($client_found == true) {
                break;
            }
        }
        # Give openvpn_kill_client both the remote host and client id, and it will 'HALT' the connection, signalling the client to disconnect and not try to reconnect
        # With only the remote host, it 'kills' the connection, cutting it off without signaling the client at all. the client will try to reconnect until manually stopped
        if ($client_found == true) {
            $result = openvpn_kill_client($mgmt,$client['remote_host'],$client['client_id']);
        }
        $users[$uid]['disabled'] = true;
        echo $username . " disable\n";    
    }
}
Write_config($action . " VPN users");


?>