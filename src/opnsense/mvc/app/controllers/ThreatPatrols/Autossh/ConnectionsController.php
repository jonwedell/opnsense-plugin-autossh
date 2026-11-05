<?php

/*
 * Copyright (c) 2022 Threat Patrols Pty Ltd <contact@threatpatrols.com>
 * Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace ThreatPatrols\Autossh;

use OPNsense\Base\IndexController;

class ConnectionsController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('ThreatPatrols/Autossh/connections');
    }
}
