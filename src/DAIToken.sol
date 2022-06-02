// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "yield-utils-v2/contracts/mocks/ERC20Mock.sol";

contract DAIToken is ERC20Mock {
    
    bool public transferFail;

    /// @dev Inherited constructor from ERC20Mock.sol
    /// @dev No parameters need to be passed for top-level constructor
    constructor() ERC20Mock("DAI", "DAI") {
        transferFail = false;
    }
    
    /// @dev Sets value of transferFail
    /// @param state_ Default value is false, as set in constructor
    function setFailTransfers(bool state_) public {
        transferFail = state_;
    }

    /// @dev Overriding _transfer from ERC20Mock to allow for a 'transfer failed' simulation, via transferFail variable
    function _transfer(address src, address dst, uint wad) internal override returns (bool) {
        if (transferFail) {
            return false;
        } 
        else {
            return super._transfer(src, dst, wad);
        }
    }
}