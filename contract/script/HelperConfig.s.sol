// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct Config {
        address[] owners;
        uint256 confirmations;
    }

    Config private activeConfig;
    uint256 private constant BASE_SEPOLIA_CHAINID = 84532;

    constructor() {
        if (block.chainid == BASE_SEPOLIA_CHAINID) {
            activeConfig = getBaseSepoliaConfig();
        } else {
            activeConfig = getAnvilConfig();
        }
    }

    function getConfig() public view returns (Config memory) {
        return activeConfig;
    }

    function getBaseSepoliaConfig() public pure returns (Config memory config) {
        address[] memory owners = new address[](3);
        owners[0] = address(0);
        owners[1] = address(0);
        owners[2] = address(0);

        config = Config({owners: owners, confirmations: 3222222});
    }

    function getAnvilConfig() public pure returns (Config memory config) {
        address[] memory owners = new address[](3);
        owners[0] = address(1);
        owners[1] = address(2);
        owners[2] = address(3);

        config = Config({owners: owners, confirmations: 2});
    }
}
