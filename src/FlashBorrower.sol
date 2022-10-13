// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/yield-utils-v2/contracts/token/IERC20.sol";
import "src/IERC3156FlashLender.sol";
import "src/IERC3156FlashBorrower.sol";


contract FlashBorrower is IERC3156FlashBorrower {

    /// @dev Flash loan action states: do something with flash loan if in this state (see onFlashLoan fn)
    enum Action {NORMAL, OTHER}

    /// @dev Lender is a fixed IERC3156FlashLender contract defined on deployment
    IERC3156FlashLender lender;

    constructor (IERC3156FlashLender lender_) {
        lender = lender_;
    }


    /// @notice Initiate a flash loan
    /// @dev Approve the token to the lender for the total repayment amount, then take flashloan
    /// @param token Address of the loan currency
    /// @param amount Amount of token to be loaned 
    function flashBorrow(address token, uint256 amount) public {
        bytes memory data = abi.encode(Action.NORMAL);

        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount);
        uint256 _repayment = amount + _fee;

        IERC20(token).approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, token, amount, data);
    }


    /// @dev ERC-3156 Flash loan callback
    /// @param initiator Address of the caller of lender.flashLoan() - msg.sender from lender's perspective
    /// @param token Address of token being loaned in flash loan transaction
    /// @param amount Amount of token to loan
    /// @param fee Flash loan fee denominated in amount of tokens
    /// @param data Calldata that was passed to lender on initiation of flashloan
    /// Note: Can implement logic (what to do with flash loan) based on passed calldata field
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external override returns(bytes32) {
        require(msg.sender == address(lender), "FlashBorrower: Untrusted lender");
        require(initiator == address(this), "FlashBorrower: Untrusted loan initiator");
        
        // optionally check data here if wanted
        (Action action) = abi.decode(data, (Action));
        if (action == Action.NORMAL) {
            // do one thing
        } else if (action == Action.OTHER) {
            // do another
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

}