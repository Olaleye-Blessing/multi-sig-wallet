// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

contract ContractOne {
    uint256 public count;

    error ContractOne__InSufficientEth();

    function increaseCount(uint256 _count) public {
        count = _count;
    }

    function multiplyCount(uint256 _multiplyer) public payable {
        if (msg.value <= 0) revert ContractOne__InSufficientEth();

        count *= _multiplyer;
    }

    receive() external payable {}

    fallback() external payable {}
}

contract ContractTwo {
    string public name;

    function changeName(string memory _name) public payable {
        name = _name;
    }

    receive() external payable {}

    fallback() external payable {}
}
