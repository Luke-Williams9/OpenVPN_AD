<?php

require_once("config.inc");


function getCronJobs($command) {
    // Search for existing cron jobs by command name
    global $config;
    $cron_items = &$config['cron']['item'];
    if (count($cron_items) > 0) {
        foreach ($cron_items as $index => $item) {
            if (strpos($item['command'], $command) !== false) {
                return $index;
            }
        }
    }
    return false;
}

function addCronJob($minute, $hour, $mday, $month, $wday, $who, $command) {
    global $config;
    $cron_items = &$config['cron']['item'];
    $a = getCronJobs($command);
    if ($a !== false) {
        echo "Cron job already exists";
        return false;
    }
    $ent = array();
    $ent['minute'] = $minute;
    $ent['hour'] = $hour;
    $ent['mday'] = $mday;
    $ent['month'] = $month;
    $ent['wday'] = $wday;
    $ent['who'] = $who;
    $ent['command'] = $command;
    $cron_items[] = $ent;
    write_config("Adding cron job");
    configure_cron();
    return $ent;
}

function delCronJob($command) {
    $a = getCronJobs($command);
    if ($a !== false) {
        global $config;
        $cron_items = &$config['cron']['item'];    
        unset($cron_items[$a]);
        write_config("Removing cron job");
        return true;
    } else {
        return false;
    }
}
// addCronJob uses standard cron layout
// addCronJob($minute, $hour, $mday, $month, $wday, $who, $command)
addCronJob('0', '7', '*', '*', '1-5', 'root', 'php -f /root/vpn/vpn-users.php enable /root/vpn/users.txt');
addCronJob('30', '17', '*', '*', '1-5', 'root', 'php -f /root/vpn/vpn-users.php disable /root/vpn/users.txt');

// examples:
// addCronJob('*', '*', '*', '*', '*', 'root', '/root/test.sh');
// delCronJob('/root/test.sh');