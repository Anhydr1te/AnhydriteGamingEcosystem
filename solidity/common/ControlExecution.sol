// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
/*
 * Copyright (C) 2023 Anhydrite Gaming Ecosystem
 *
 * This code is part of the Anhydrite Gaming Ecosystem.
 *
 * ERC-20 Token: Anhydrite ANH
 * Network: Binance Smart Chain
 * Website: https://anh.ink
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that explicit attribution to the original code and website
 * is maintained. For detailed terms, please contact the Anhydrite Gaming Ecosystem team.
 *
 * This code is provided as-is, without warranty of any kind, express or implied,
 * including but not limited to the warranties of merchantability, fitness for a 
 * particular purpose, and non-infringement. In no event shall the authors or 
 * copyright holders be liable for any claim, damages, or other liability, whether 
 * in an action of contract, tort, or otherwise, arising from, out of, or in connection 
 * with the software or the use or other dealings in the software.
 */

abstract contract ControlExecution {

    mapping(address => uint256) internal  _executes;

    function _startExecute() internal {
        require(_executes[msg.sender] == 0, "ControlExecution: Wait for the previous call to end");
        _executes[msg.sender] = 1;
    }

    function _finishExecute() internal {
        _executes[msg.sender] = 0;
    }

    modifier isExecutes() {
        _startExecute();
        _;
        _finishExecute();
    }
}