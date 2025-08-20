// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MultiSig} from "./../src/MultiSig.sol";

contract DeployMultiSig is Script {
    address immutable I_DEPLOYER;

    constructor() {
        I_DEPLOYER = msg.sender;
    }

    function run() external returns (MultiSig) {
        HelperConfig.Config memory activeConfig = new HelperConfig().getConfig();

        vm.startBroadcast(I_DEPLOYER);
        MultiSig multiSig = new MultiSig(activeConfig.owners, activeConfig.confirmations);

        vm.stopBroadcast();

        return (multiSig);
    }
}
