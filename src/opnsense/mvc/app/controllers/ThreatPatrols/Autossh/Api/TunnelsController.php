<?php

/*
 * Copyright (c) 2022 Threat Patrols Pty Ltd <contact@threatpatrols.com>
 * Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace ThreatPatrols\Autossh\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;

class TunnelsController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'autossh';
    protected static $internalModelClass = 'ThreatPatrols\Autossh\Autossh';
    protected static $internalModelUseSafeDelete = true;

    public function searchTunnelAction()
    {
        return $this->searchBase('tunnels.tunnel', null, 'hostname');
    }

    public function getTunnelAction($uuid = null)
    {
        return $this->getBase('tunnel', 'tunnels.tunnel', $uuid);
    }

    public function addTunnelAction()
    {
        return $this->addBase('tunnel', 'tunnels.tunnel');
    }

    public function setTunnelAction($uuid)
    {
        return $this->setBase('tunnel', 'tunnels.tunnel', $uuid);
    }

    public function delTunnelAction($uuid)
    {
        return $this->delBase('tunnels.tunnel', $uuid);
    }

    public function toggleTunnelAction($uuid, $enabled = null)
    {
        return $this->toggleBase('tunnels.tunnel', $uuid, $enabled);
    }

    /**
     * Backs the grid's info button: report the ssh host keys learned for this
     * tunnel so they can be eyeballed against the remote.
     */
    public function infoAction($uuid)
    {
        $info = [
            'title' => gettext('SSH host keys recorded for this tunnel'),
            'message' => gettext('Unable to read host keys, review the configd log.'),
        ];

        $response = json_decode(
            trim((new Backend())->configdpRun('autossh hostkeys', [$uuid])),
            true
        );

        if (empty($response)) {
            return $info;
        }

        if (($response['status'] ?? '') !== 'success') {
            $info['message'] = $response['message'];
            return $info;
        }

        // plain text only: the dialog escapes whatever it is handed
        $info['message'] = implode("\n\n", $response['data']);

        return $info;
    }
}
