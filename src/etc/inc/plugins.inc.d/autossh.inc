<?php

/*
 * Copyright (c) 2022 Threat Patrols Pty Ltd <contact@threatpatrols.com>
 * Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

use ThreatPatrols\Autossh\Autossh;

/**
 * Each enabled tunnel is registered as its own service so that it shows up
 * individually under System: Diagnostics: Services and in the service widget.
 */
function autossh_services()
{
    $services = [];

    $model = new Autossh();
    foreach ($model->tunnels->tunnel->iterateItems() as $uuid => $tunnel) {
        if ((string)$tunnel->enabled !== '1') {
            continue;
        }

        $description = (string)$tunnel->user . '@' . (string)$tunnel->hostname;
        if (!empty((string)$tunnel->port)) {
            $description .= ':' . (string)$tunnel->port;
        }
        if (!empty((string)$tunnel->description)) {
            $description = (string)$tunnel->description . ' (' . $description . ')';
        }
        if (strlen($description) > 48) {
            $description = substr($description, 0, 45) . '...';
        }

        $services[] = [
            'description' => gettext('Autossh') . ': ' . $description,
            'id' => $uuid,
            'name' => 'autossh',
            'pidfile' => '/var/run/autossh.' . $uuid . '.pid',
            'configd' => [
                'start' => ['autossh start_tunnel ' . $uuid],
                'stop' => ['autossh stop_tunnel ' . $uuid],
                'restart' => ['autossh restart_tunnel ' . $uuid],
            ],
        ];
    }

    return $services;
}

function autossh_syslog()
{
    return [
        'autossh' => [
            'facility' => ['autossh', 'autosshd', '/usr/local/bin/ssh'],
        ],
    ];
}

function autossh_xmlrpc_sync()
{
    return [[
        'description' => gettext('Autossh'),
        'section' => 'ThreatPatrols.Autossh',
        'id' => 'autossh',
        'services' => ['autossh'],
    ]];
}
