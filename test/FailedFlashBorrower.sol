// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lib/yield-utils-v2/contracts/token/IERC20.sol";
import "src/IERC3156FlashLender.sol";
import "src/IERC3156FlashBorrower.sol";

// https://github.com/alcueca/ERC3156/blob/main/contracts/FlashBorrower.sol
/*
We'll implement a flashBorrow function. 

lender is a fixed IERC3156FlashLender contract defined on deployment
We first approve the token to the lender for the total repayment amount. The repayment is calculated as the loan amount + fee. We can get the fee by calling flashFee on the lender.

Lastly we can execute the flashLoan function.

*/

contract FailedFlashBorrower is IERC3156FlashBorrower {

    enum Action {NORMAL, OTHER}

    //lender is a fixed IERC3156FlashLender contract defined on deployment
    IERC3156FlashLender lender;

    constructor (IERC3156FlashLender lender_) {
        lender = lender_;
    }


    /// @notice Approve the token to the lender for the total repayment amount, then take flashloan
    /// @dev Initiate a flash loan
    function flashBorrow(address token, uint256 amount) public {
        bytes memory data = abi.encode(Action.NORMAL);

        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount);
        uint256 _repayment = amount + _fee;

        IERC20(token).approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, token, amount, data);
    }


/*
Now of course we will also need the onFlashLoan callback function in our borrower. 

In our example we

1. verify the sender is actually the lender
2. verify the initiator for the flash loan was actually our contract
3. return the pre-defined hash to verify a successful flash loan

We could further implement additional logic here based on the passed data field if required.

Now we can go into the lender implementation where we will execute the actual flash loan logic.
*/
    /// @dev ERC-3156 Flash loan callback
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
        //Note: this function returns the incorrect keccak hash to lender, should result in revert on callback
        return keccak256("scooby doo");
    }

}